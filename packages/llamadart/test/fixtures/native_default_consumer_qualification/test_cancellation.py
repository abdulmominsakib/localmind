"""Real synthetic Python cancellation controls, without SDK/model/native input."""
import json
import inspect
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import threading
import unittest
from unittest.mock import patch

import qualify


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


class CancellationControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def test_interrupt_after_spawn_before_constructor_return_has_registered_owner(self):
        original = subprocess.Popen.__init__
        spawned = []
        def interrupted_init(process, *args, **kwargs):
            original(process, *args, **kwargs)
            spawned.append(process)
            raise KeyboardInterrupt('synthetic constructor-return interruption')
        try:
            with patch.object(subprocess.Popen, '__init__', interrupted_init):
                with self.assertRaises(KeyboardInterrupt):
                    qualify.command([sys.executable, '-c', 'import time; time.sleep(30)'],
                        cwd=self.root, env=dict(os.environ), timeout=5, log=self.root / 'registration')
            self.assertEqual(1, len(spawned))
            self.assertIsNotNone(spawned[0].poll(), 'child escaped ownership during constructor return')
            receipt = json.loads((self.root / 'registration.command.json').read_text())
            self.assertEqual(spawned[0].pid, receipt['pid'])
            self.assertTrue(receipt['cleanupComplete'])
            self.assertEqual('KeyboardInterrupt', receipt['failureType'])
        finally:
            for process in spawned:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)

    def test_control_signal_during_constructor_is_deferred_until_owner_registration(self):
        for name in ('SIGINT', 'SIGBREAK'):
            if hasattr(signal, name):
                with self.subTest(signal=name):
                    self.assert_signal_during_constructor(getattr(signal, name))

    def assert_signal_during_constructor(self, signum):
        original = subprocess.Popen.__init__
        spawned = []
        previous = {name: signal.getsignal(getattr(signal, name))
                    for name in ('SIGINT', 'SIGTERM', 'SIGBREAK') if hasattr(signal, name)}
        def cancelled_init(process, *args, **kwargs):
            original(process, *args, **kwargs)
            spawned.append(process)
            signal.raise_signal(signum)
        try:
            with patch.object(subprocess.Popen, '__init__', cancelled_init):
                with self.assertRaises(qualify.Cancelled):
                    qualify.command([sys.executable, '-c', 'import time; time.sleep(30)'],
                        cwd=self.root, env=dict(os.environ), timeout=5, log=self.root / 'signal-registration')
            self.assertIsNotNone(spawned[0].poll())
            receipt = json.loads((self.root / 'signal-registration.command.json').read_text())
            self.assertEqual([signum], receipt['cancelledSignals'])
            self.assertEqual(spawned[0].pid, receipt['pid'])
            self.assertTrue(receipt['cleanupComplete'])
            for name, handler in previous.items():
                self.assertEqual(handler, signal.getsignal(getattr(signal, name)))
        finally:
            for process in spawned:
                if process.poll() is None: process.kill()
                process.wait(timeout=5)

    @unittest.skipIf(os.name == 'nt', 'POSIX group cleanup injection; Windows job covered on actual Windows')
    def test_repeated_sigterm_during_cleanup_is_deferred_and_preserves_timeout(self):
        original = os.killpg
        def interrupted_cleanup(pid, signum):
            original(pid, signum)
            signal.raise_signal(signal.SIGTERM)
            signal.raise_signal(signal.SIGTERM)
        with patch.object(os, 'killpg', interrupted_cleanup):
            with self.assertRaises(subprocess.TimeoutExpired):
                qualify.command([sys.executable, '-c', 'import time; time.sleep(30)'],
                    cwd=self.root, env=dict(os.environ), timeout=.03, log=self.root / 'cleanup-signal')
        receipt = json.loads((self.root / 'cleanup-signal.command.json').read_text())
        self.assertTrue(receipt['cleanupComplete'])
        self.assertEqual('TimeoutExpired', receipt['failureType'])
        self.assertEqual([signal.SIGTERM, signal.SIGTERM], receipt['cancelledSignals'])
        self.assertFalse(alive(receipt['pid']))

    def test_sigterm_at_cleanup_entry_preserves_timeout_and_reaps_child(self):
        lines, first = inspect.getsourcelines(qualify.command)
        entry = next(first + offset for offset, text in enumerate(lines)
                     if 'with cancellation.deferred(deliver=False):' in text)
        injected = []
        owned = []
        def trace(frame, event, argument):
            if (frame.f_code is qualify.command.__code__ and event == 'line'
                    and frame.f_lineno == entry and not injected):
                injected.append(frame.f_locals['cancellation'].depth)
                owned.append(frame.f_locals['process'])
                signal.raise_signal(signal.SIGTERM)
            return trace
        previous_trace = sys.gettrace()
        try:
            sys.settrace(trace)
            with self.assertRaises(subprocess.TimeoutExpired):
                qualify.command([sys.executable, '-c', 'import time; time.sleep(30)'],
                    cwd=self.root, env=dict(os.environ), timeout=.03, log=self.root / 'cleanup-entry')
            self.assertEqual([0], injected)
            self.assertIsNotNone(owned[0].poll())
            receipt = json.loads((self.root / 'cleanup-entry.command.json').read_text())
            self.assertTrue(receipt['cleanupComplete'])
            self.assertEqual('TimeoutExpired', receipt['failureType'])
            self.assertEqual([signal.SIGTERM], receipt['cancelledSignals'])
        finally:
            sys.settrace(previous_trace)
            for process in owned:
                if process.poll() is None: process.kill()
                process.wait(timeout=5)

    def test_real_sigterm_at_command_boundaries_never_skips_cleanup(self):
        boundaries = [
            ("receipt['pid'] = process.pid", qualify.Cancelled),
            ("receipt['exitCode'] = cancellation.wait", qualify.Cancelled),
            ('failure, traceback = error, error.__traceback__', subprocess.TimeoutExpired),
            ('cleanup_errors = []', subprocess.TimeoutExpired),
            ('write_json(str(log)', subprocess.TimeoutExpired),
            ('cancellation.on_cancel = record_late_cancellation', subprocess.TimeoutExpired),
        ]
        lines, first = inspect.getsourcelines(qualify.command)
        previous_trace = sys.gettrace()
        for index, (needle, expected) in enumerate(boundaries):
            with self.subTest(boundary=needle):
                entry = next(first + offset for offset, text in enumerate(lines) if needle in text)
                owned = []
                fired = False
                def trace(frame, event, argument):
                    nonlocal fired
                    if (frame.f_code is qualify.command.__code__ and event == 'line'
                            and frame.f_lineno == entry and not fired):
                        fired = True
                        owned.append(frame.f_locals['process'])
                        signal.raise_signal(signal.SIGTERM)
                    return trace
                log = self.root / f'boundary-{index}'
                try:
                    sys.settrace(trace)
                    with self.assertRaises(expected):
                        qualify.command([sys.executable, '-c', 'import time; time.sleep(30)'],
                            cwd=self.root, env=dict(os.environ), timeout=.03, log=log)
                    self.assertTrue(fired)
                    self.assertIsNotNone(owned[0].poll())
                    receipt = json.loads(Path(str(log) + '.command.json').read_text())
                    self.assertTrue(receipt['cleanupComplete'])
                    self.assertEqual(expected.__name__, receipt['failureType'])
                    self.assertIn(signal.SIGTERM, receipt['cancelledSignals'])
                finally:
                    sys.settrace(previous_trace)
                    for process in owned:
                        if process.poll() is None: process.kill()
                        process.wait(timeout=5)

    def test_sigterm_at_completed_command_guard_exit_still_records_cancellation(self):
        original = qualify.CancellationGuard.__exit__
        def interrupted_exit(guard, *args):
            signal.raise_signal(signal.SIGTERM)
            return original(guard, *args)
        with patch.object(qualify.CancellationGuard, '__exit__', interrupted_exit):
            with self.assertRaises(qualify.Cancelled):
                qualify.command([sys.executable, '-c', 'pass'], cwd=self.root,
                    env=dict(os.environ), timeout=5, log=self.root / 'exit-signal')
        receipt = json.loads((self.root / 'exit-signal.command.json').read_text())
        self.assertTrue(receipt['cleanupComplete'])
        self.assertEqual('Cancelled', receipt['failureType'])
        self.assertIn(signal.SIGTERM, receipt['cancelledSignals'])

    def test_signal_during_handler_restoration_is_delivered_after_restoration(self):
        exit_code = qualify.CancellationGuard.__exit__.__code__
        lines, first = inspect.getsourcelines(qualify.CancellationGuard.__exit__)
        restore = next(first + offset for offset, text in enumerate(lines)
                       if 'for signum, previous in self.previous.items()' in text)
        for timeout in (False, True):
            with self.subTest(original_timeout=timeout):
                observed = []
                previous_handlers = {getattr(signal, name): signal.getsignal(getattr(signal, name))
                    for name in ('SIGINT', 'SIGTERM', 'SIGBREAK') if hasattr(signal, name)}
                def trace(frame, event, argument):
                    if (frame.f_code is exit_code and event == 'line'
                            and frame.f_lineno == restore and not observed):
                        signal.raise_signal(signal.SIGTERM)
                        observed.append(list(frame.f_locals['self'].signals))
                    return trace
                previous_trace = sys.gettrace()
                log = self.root / ('restore-timeout' if timeout else 'restore-success')
                try:
                    sys.settrace(trace)
                    expected = subprocess.TimeoutExpired if timeout else qualify.Cancelled
                    with self.assertRaises(expected):
                        qualify.command([sys.executable, '-c',
                            'import time; time.sleep(30)' if timeout else 'pass'],
                            cwd=self.root, env=dict(os.environ), timeout=.03 if timeout else 5, log=log)
                    self.assertEqual([[signal.SIGTERM]], observed)
                    receipt = json.loads(Path(str(log) + '.command.json').read_text())
                    self.assertTrue(receipt['cleanupComplete'])
                    self.assertEqual(expected.__name__, receipt['failureType'])
                    self.assertIn(signal.SIGTERM, receipt['cancelledSignals'])
                    for signum, previous in previous_handlers.items():
                        self.assertEqual(previous, signal.getsignal(signum))
                finally:
                    sys.settrace(previous_trace)

    def test_background_thread_refuses_before_child_creation(self):
        errors = []
        def invoke():
            try:
                qualify.command([sys.executable, '-c', 'raise SystemExit(0)'],
                    cwd=self.root, env=dict(os.environ), timeout=5, log=self.root / 'thread')
            except BaseException as error:
                errors.append(error)
        with patch.object(subprocess.Popen, '__init__') as constructor:
            thread = threading.Thread(target=invoke)
            thread.start(); thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
            constructor.assert_not_called()
        self.assertEqual(1, len(errors))
        self.assertIn('main thread', str(errors[0]))

    def test_git_uses_owned_timeout_receipt_or_refuses_before_creation(self):
        with patch.object(qualify, 'command', return_value='synthetic git output') as runner:
            result = qualify.git(self.root, 'rev-parse', 'HEAD', log=self.root / 'git')
            self.assertEqual(b'synthetic git output', result)
            self.assertEqual(60, runner.call_args.kwargs['timeout'])
            self.assertEqual(self.root / 'git', runner.call_args.kwargs['log'])
            self.assertEqual('1', runner.call_args.kwargs['env']['GIT_NO_LAZY_FETCH'])
        with patch.object(qualify, 'command') as runner:
            with self.assertRaises(qualify.v.Refusal):
                qualify.git(self.root, 'status')
            runner.assert_not_called()

    @unittest.skipIf(os.name == 'nt', 'POSIX supervisor SIGTERM; Windows control events tested separately')
    def test_supervisor_sigterm_cleans_new_session_child_and_writes_failure_receipt(self):
        child_pid = self.root / 'child.pid'
        child = f'import os,pathlib,time; pathlib.Path({str(child_pid)!r}).write_text(str(os.getpid())); time.sleep(30)'
        supervisor = ('import sys,os; sys.path.insert(0,' + repr(str(qualify.FIXTURE)) + '); import qualify; '
            + f'qualify.command([sys.executable,"-c",{child!r}],cwd={str(self.root)!r},'
            + f'env=dict(os.environ),timeout=900,log={str(self.root / "supervisor")!r})')
        process = subprocess.Popen([sys.executable, '-B', '-c', supervisor],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True)
        pid = None
        try:
            deadline = time.monotonic() + 5
            while not child_pid.exists() and time.monotonic() < deadline and process.poll() is None:
                time.sleep(.01)
            self.assertTrue(child_pid.exists(), 'synthetic child did not become ready')
            pid = int(child_pid.read_text())
            cancelled_at = time.monotonic()
            os.kill(process.pid, signal.SIGTERM)
            _, stderr = process.communicate(timeout=5)
            self.assertNotEqual(0, process.returncode, stderr.decode())
            self.assertLess(time.monotonic() - cancelled_at, 3, 'cancellation waited for the 900-second deadline')
            self.assertFalse(alive(pid), 'SIGTERM left owned child alive')
            receipt = json.loads((self.root / 'supervisor.command.json').read_text())
            self.assertEqual(pid, receipt['pid'])
            self.assertTrue(receipt['cleanupComplete'])
            self.assertIn(signal.SIGTERM, receipt['cancelledSignals'])
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
            if pid and alive(pid):
                os.kill(pid, signal.SIGKILL)
            if process.stderr:
                process.stderr.close()


if __name__ == '__main__':
    unittest.main()
