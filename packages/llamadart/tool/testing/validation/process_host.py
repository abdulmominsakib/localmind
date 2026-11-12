"""Bounded subprocess host. No shell, credentials, or command text in errors."""
import ctypes
import os
import signal
import shutil
import subprocess
import sys
import threading
import time

RETIREMENT_SECONDS = 5


class GroupAbsenceTimeout(RuntimeError):
    pass


class PosixChildReservation:
    """Hold the returned child unreaped through final owned-group delivery.

    WNOWAIT completion observation preserves the actual child reservation; an
    old PID receipt or a matching sampled group alone does not. After wait/reap,
    only non-delivering absence probes are allowed. Unknown remains failure,
    except that main() keeps a known child status when only the absence wait
    times out (a container PID 1 may never reap orphans).
    """
    def __init__(self, child):
        self.child = child
        self.group = None
        self.held = True
        self.returncode = None

    def observe(self):
        if not self.held:
            raise RuntimeError('Child reservation is not held')
        try:
            observed = os.waitid(os.P_PID, self.child.pid,
                                 os.WEXITED | os.WNOHANG | os.WNOWAIT)
        except ChildProcessError:
            self.held = False
            raise RuntimeError('Child reservation was lost') from None
        if observed is None:
            return None
        if observed.si_pid != self.child.pid:
            raise RuntimeError('Unexpected child completion identity')
        if observed.si_code == os.CLD_EXITED:
            self.returncode = observed.si_status
        elif observed.si_code in (os.CLD_KILLED, os.CLD_DUMPED):
            self.returncode = -observed.si_status
        else:
            raise RuntimeError('Unexpected child completion state')
        return self.returncode

    def bind(self):
        self.observe()
        try:
            actual_group = os.getpgid(self.child.pid)
        except ProcessLookupError:
            # macOS getpgid() fails for an exited child that is still unreaped.
            # Held completion keeps its PID, and so the ID of the group its
            # setsid() created, from reuse; a session leader cannot leave that
            # group. Without completion, ESRCH stays a binding failure.
            if self.observe() is None:
                raise
            actual_group = self.child.pid
        if actual_group != self.child.pid:
            raise RuntimeError('Cannot bind returned child session group')
        self.group = actual_group

    def reap(self, deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError('Child retirement deadline expired')
        self.child.wait(timeout=remaining)
        self.held = False

    def retire(self):
        # The existing five-second child-wait bound covers delivery, reap and
        # eventual group absence. This is not general daemon containment.
        deadline = time.monotonic() + RETIREMENT_SECONDS
        completion = self.observe()
        if self.group is None:
            # Reservation proves this actual child only, not an unbound group.
            # Retire the leader without delivering to any guessed group; group
            # cleanup remains unproved even when this wait succeeds.
            try:
                os.kill(self.child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.reap(deadline)
            raise RuntimeError('Child group retirement remains unproved')
        # A completed unreaped child can no longer support getpgid on every
        # POSIX host. Its earlier bound own-session group remains reserved while
        # WNOWAIT holds the returned child reservation. Retirement never binds
        # a group: an unbound child still fails above.
        if completion is None:
            try:
                actual_group = os.getpgid(self.child.pid)
            except ProcessLookupError:
                # The leader may exit between observation and lookup. Require
                # fresh held completion; ESRCH alone proves no group absence.
                if self.observe() is None:
                    raise RuntimeError('Returned child group binding is unproved') from None
            else:
                if actual_group != self.group:
                    raise RuntimeError('Returned child group binding changed')
        group_present = True
        try:
            os.killpg(self.group, 0)
        except ProcessLookupError:
            group_present = False
        except PermissionError:
            # Permission is unknown, so do not deliver a group signal. The
            # owned returned child must still receive a bounded wait/reap.
            group_present = False
        if group_present:
            # The returned child is still unreaped here, reserving its actual
            # PID/group. No delivering group signal may occur after reap.
            try:
                os.killpg(self.group, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except PermissionError:
                # Denial is not delivery proof; still finish the bounded child
                # wait. Only eventual passive ESRCH may establish absence.
                pass
        self.reap(deadline)
        while True:
            try:
                os.killpg(self.group, 0)
            except ProcessLookupError:
                return
            except PermissionError:
                # Unknown remains unknown until this same finite deadline;
                # never turn EPERM into absence or deliver after reaping.
                pass
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise GroupAbsenceTimeout('Child group retirement deadline expired')
            time.sleep(min(0.02, remaining))


def posix_waitid_available():
    return all(hasattr(os, name) for name in
               ('waitid', 'P_PID', 'WEXITED', 'WNOHANG', 'WNOWAIT',
                'CLD_EXITED', 'CLD_KILLED', 'CLD_DUMPED'))


def main(on_child_started=None):
    """Optionally record the returned child PID; it is not a lineage proof.

    The callback receives no command text. No CLI/environment receipt binding
    is provided: the ordinary entry point retains its existing behavior.
    The synchronous callback must return promptly; it cannot be preempted by
    this host's loop deadline, which includes elapsed callback/setup time.
    """
    terminated = threading.Event()
    def request_stop(signum, frame):
        terminated.set()
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    seconds = float(sys.argv[1])
    arguments = sys.argv[2:]
    job = None
    kernel = None
    if os.name == 'nt':
        # A job retains descendants even when the immediate launcher exits.
        from ctypes import wintypes
        class Basic(ctypes.Structure):
            _fields_ = [('PerProcessUserTimeLimit', ctypes.c_longlong), ('PerJobUserTimeLimit', ctypes.c_longlong),
                        ('LimitFlags', wintypes.DWORD), ('MinimumWorkingSetSize', ctypes.c_size_t),
                        ('MaximumWorkingSetSize', ctypes.c_size_t), ('ActiveProcessLimit', wintypes.DWORD),
                        ('Affinity', ctypes.c_size_t), ('PriorityClass', wintypes.DWORD), ('SchedulingClass', wintypes.DWORD)]
        class IO(ctypes.Structure):
            _fields_ = [(name, ctypes.c_ulonglong) for name in ('ReadOperationCount', 'WriteOperationCount', 'OtherOperationCount', 'ReadTransferCount', 'WriteTransferCount', 'OtherTransferCount')]
        class Limits(ctypes.Structure):
            _fields_ = [('BasicLimitInformation', Basic), ('IoInfo', IO), ('ProcessMemoryLimit', ctypes.c_size_t), ('JobMemoryLimit', ctypes.c_size_t), ('PeakProcessMemoryUsed', ctypes.c_size_t), ('PeakJobMemoryUsed', ctypes.c_size_t)]
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateJobObjectW.restype = wintypes.HANDLE
        kernel.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        kernel.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        job = kernel.CreateJobObjectW(None, None)
        limits = Limits()
        limits.BasicLimitInformation.LimitFlags = 0x2000  # KILL_ON_JOB_CLOSE
        if not job or not kernel.SetInformationJobObject(job, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            raise RuntimeError('Cannot establish subprocess job')
        # Flutter/Gradle/gcloud are batch launchers on Windows. Resolve PATHEXT
        # first, quote every argument, and reject cmd expansion syntax.
        arguments[0] = shutil.which(arguments[0]) or arguments[0]
        if arguments[0].lower().endswith(('.bat', '.cmd')):
            if any(any(c in arg for c in ('"', '%', '!', '\r', '\n')) for arg in arguments):
                raise ValueError('Unsafe Windows batch argument')
            quoted = ' '.join('"' + arg + '"' for arg in arguments)
            arguments = '"' + os.environ.get('COMSPEC', 'cmd.exe') + '" /d /v:off /s /c "' + quoted + '"'
    child = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             start_new_session=os.name != 'nt')
    job_assigned = False
    known_status = False
    # os.waitid is missing on macOS before Python 3.13. Without it the
    # returned child cannot be held unreaped, so that host keeps the earlier
    # unheld group delivery instead of refusing every command.
    reservation = (PosixChildReservation(child)
                   if os.name != 'nt' and posix_waitid_available() else None)
    try:
        deadline = time.monotonic() + seconds
        if reservation is not None:
            reservation.bind()
        if job:
            job_assigned = bool(kernel.AssignProcessToJobObject(job, int(child._handle)))
            if not job_assigned:
                raise RuntimeError('Cannot contain subprocess descendants')
        if on_child_started is not None:
            on_child_started(child.pid)
        overflow = threading.Event()
        def copy(stream, sink):
            total = 0
            while True:
                chunk = stream.read(4096)
                if not chunk:
                    return
                total += len(chunk)
                if total > 8 * 1024 * 1024:
                    overflow.set()
                    return
                sink.buffer.write(chunk)
                sink.buffer.flush()
        readers = [threading.Thread(target=copy, args=(child.stdout, sys.stdout), daemon=True),
                   threading.Thread(target=copy, args=(child.stderr, sys.stderr), daemon=True)]
        for reader in readers:
            reader.start()
        while (child.poll() if reservation is None else reservation.observe()) is None or any(reader.is_alive() for reader in readers):
            if terminated.is_set():
                return 143
            if overflow.is_set():
                return 125
            if time.monotonic() >= deadline:
                return 124
            time.sleep(0.02)
        # Setup can consume the deadline after an already-exited child. Do not
        # bypass stop/deadline checks merely because no reader remains active.
        if terminated.is_set():
            return 143
        if time.monotonic() >= deadline:
            return 124
        known_status = reservation is not None and reservation.returncode is not None
        return child.returncode if reservation is None else reservation.returncode
    finally:
        if job:
            kernel.CloseHandle(job)
            if not job_assigned and child.poll() is None:
                child.kill()
        elif reservation is not None:
            try:
                reservation.retire()
            except GroupAbsenceTimeout:
                if not known_status:
                    raise
                print('Subprocess host warning: child group still present after '
                      'child exit; keeping the child exit status', file=sys.stderr)
        elif os.name != 'nt':
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except PermissionError as denied:
                # macOS denies a group of unreaped zombies. Keep the setup
                # error that left the child unreaped; denial alone still fails.
                if denied.__context__ is None:
                    raise
        elif child.poll() is None:
            child.kill()
        if reservation is None:
            child.wait(timeout=5)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print('Subprocess host failed (' + type(error).__name__ + ')', file=sys.stderr)
        sys.exit(125)
