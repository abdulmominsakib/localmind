"""Windows kill-on-close job ownership, established before the child resumes."""
import ctypes
import os
import time


class WindowsJob:
    def __init__(self):
        if os.name != 'nt':
            raise RuntimeError('WindowsJob is Windows-only')
        from ctypes import wintypes as w
        self.api = ctypes.WinDLL('kernel32', use_last_error=True)
        self.api.CreateJobObjectW.argtypes = [ctypes.c_void_p, w.LPCWSTR]
        self.api.CreateJobObjectW.restype = w.HANDLE
        self.api.SetInformationJobObject.argtypes = [w.HANDLE, ctypes.c_int, ctypes.c_void_p, w.DWORD]
        self.api.SetInformationJobObject.restype = w.BOOL
        self.api.AssignProcessToJobObject.argtypes = [w.HANDLE, w.HANDLE]
        self.api.AssignProcessToJobObject.restype = w.BOOL
        self.api.TerminateJobObject.argtypes = [w.HANDLE, w.UINT]
        self.api.TerminateJobObject.restype = w.BOOL
        self.api.QueryInformationJobObject.argtypes = [w.HANDLE, ctypes.c_int, ctypes.c_void_p, w.DWORD, ctypes.c_void_p]
        self.api.QueryInformationJobObject.restype = w.BOOL
        self.api.CloseHandle.argtypes = [w.HANDLE]
        self.api.CloseHandle.restype = w.BOOL

        class Basic(ctypes.Structure):
            _fields_ = [('PerProcessUserTimeLimit', ctypes.c_int64), ('PerJobUserTimeLimit', ctypes.c_int64),
                ('LimitFlags', w.DWORD), ('MinimumWorkingSetSize', ctypes.c_size_t),
                ('MaximumWorkingSetSize', ctypes.c_size_t), ('ActiveProcessLimit', w.DWORD),
                ('Affinity', ctypes.c_size_t), ('PriorityClass', w.DWORD), ('SchedulingClass', w.DWORD)]

        class Io(ctypes.Structure):
            _fields_ = [(name, ctypes.c_uint64) for name in ('ReadOperationCount', 'WriteOperationCount',
                'OtherOperationCount', 'ReadTransferCount', 'WriteTransferCount', 'OtherTransferCount')]

        class Extended(ctypes.Structure):
            _fields_ = [('BasicLimitInformation', Basic), ('IoInfo', Io),
                ('ProcessMemoryLimit', ctypes.c_size_t), ('JobMemoryLimit', ctypes.c_size_t),
                ('PeakProcessMemoryUsed', ctypes.c_size_t), ('PeakJobMemoryUsed', ctypes.c_size_t)]

        self.handle = self.api.CreateJobObjectW(None, None)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())
        info = Extended()
        info.BasicLimitInformation.LimitFlags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not self.api.SetInformationJobObject(self.handle, 9, ctypes.byref(info), ctypes.sizeof(info)):
            error = ctypes.WinError(ctypes.get_last_error())
            self.api.CloseHandle(self.handle)
            raise error

    def attach_and_resume(self, process):
        # Popen was created suspended. Assignment cannot race child spawning.
        if not self.api.AssignProcessToJobObject(self.handle, int(process._handle)):
            raise ctypes.WinError(ctypes.get_last_error())
        native = ctypes.WinDLL('ntdll')
        native.NtResumeProcess.argtypes = [ctypes.c_void_p]
        native.NtResumeProcess.restype = ctypes.c_long
        if native.NtResumeProcess(int(process._handle)) != 0:
            raise RuntimeError('cannot resume owned suspended child')

    def close(self):
        from ctypes import wintypes as w

        class Accounting(ctypes.Structure):
            _fields_ = [(name, ctypes.c_int64) for name in ('TotalUserTime', 'TotalKernelTime',
                'ThisPeriodTotalUserTime', 'ThisPeriodTotalKernelTime')] + [
                (name, w.DWORD) for name in ('TotalPageFaultCount', 'TotalProcesses',
                'ActiveProcesses', 'TotalTerminatedProcesses')]

        try:
            if not self.api.TerminateJobObject(self.handle, 1):
                raise ctypes.WinError(ctypes.get_last_error())
            deadline = time.monotonic() + 30
            while True:
                accounting = Accounting()
                if not self.api.QueryInformationJobObject(self.handle, 1, ctypes.byref(accounting),
                        ctypes.sizeof(accounting), None):
                    raise ctypes.WinError(ctypes.get_last_error())
                if accounting.ActiveProcesses == 0:
                    break
                if time.monotonic() >= deadline:
                    raise OSError('owned Windows job did not become empty before cleanup deadline')
                time.sleep(.01)
        finally:
            if not self.api.CloseHandle(self.handle):
                raise ctypes.WinError(ctypes.get_last_error())


class Cancelled(RuntimeError):
    def __init__(self, signum):
        self.signum = signum
        super().__init__(f'qualification cancelled by signal {signum}')


class CancellationGuard:
    """Record-only signal handlers; cancellation raises only at safe checkpoints."""
    def __init__(self, on_cancel=None):
        self.on_cancel = on_cancel
        self.signals = []
        self.depth = 0
        self.previous = {}

    def __enter__(self):
        import signal
        import threading
        # Python permits signal handlers only in the main thread. Refuse
        # before creating any child rather than claim thread cancellation safety.
        if threading.current_thread() is not threading.main_thread():
            raise RuntimeError('owned commands require the supervisor main thread')
        self.depth = 1
        try:
            for name in ('SIGINT', 'SIGTERM', 'SIGBREAK'):
                signum = getattr(signal, name, None)
                if signum is not None:
                    self.previous[signum] = signal.signal(signum, self._handle)
            self.depth = 0
            self.checkpoint()
        except BaseException:
            for signum, previous in self.previous.items():
                signal.signal(signum, previous)
            raise
        return self

    def _handle(self, signum, frame):
        if len(self.signals) < 16:
            self.signals.append(signum)
        # Never raise from a signal handler: an exception at a finally/context
        # entry can bypass ownership cleanup even when its body is protected.

    def checkpoint(self):
        if self.signals:
            if self.on_cancel is not None:
                self.on_cancel(self.signals)
            raise Cancelled(self.signals[0])

    def wait(self, process, timeout):
        import subprocess
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(process.args, timeout)
            self.checkpoint()
            try:
                result = process.wait(timeout=min(.1, remaining))
            except subprocess.TimeoutExpired:
                continue
            self.checkpoint()
            return result

    def deferred(self, *, deliver=True):
        from contextlib import contextmanager

        @contextmanager
        def protection():
            self.depth += 1
            try:
                yield
            finally:
                self.depth -= 1
            if deliver:
                self.checkpoint()
        return protection()

    def __exit__(self, exception_type, exception, traceback):
        import signal
        self.depth += 1
        for signum, previous in self.previous.items():
            signal.signal(signum, previous)
        # The record-only handlers can still run during their restoration.
        # Close that observation interval before the final delivery/receipt.
        if exception_type is None:
            self.checkpoint()
        elif self.signals and self.on_cancel is not None:
            self.on_cancel(self.signals)
        return False
