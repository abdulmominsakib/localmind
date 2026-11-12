"""Owned subprocess/signal regressions; no SD reader, checkpoint or model runs."""
from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import owned_capture as profiler


class CaptureOwnershipTest(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory(prefix='sd24-capture-test-')
        self.root = Path(self.scratch.name)
        self.binary = self.root / 'fake-binary'
        self.binary.write_bytes(b'fake synthetic binary')
        self.input = self.root / 'synthetic-input'
        self.input.write_bytes(b'synthetic bytes, not a model')
        self.receipt = self.root / 'build.json'
        self.receipt.write_text(json.dumps({'binary_sha256': profiler.digest(self.binary)}))

    def tearDown(self) -> None:
        self.scratch.cleanup()

    def mocked_failure(self, failure: BaseException, repeat_signals: bool = False):
        calls = []
        class Child:
            pid = 123456789
            returncode = None
            def wait(self, timeout):
                calls.append(('wait', timeout))
                self.returncode = -signal.SIGKILL
                return self.returncode
        child = Child()
        def kill(pid, signum):
            calls.append(('killpg', pid, signum))
            if repeat_signals:
                signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
                signal.getsignal(signal.SIGINT)(signal.SIGINT, None)
        with patch.object(profiler.subprocess, 'Popen', return_value=child), \
                patch.object(profiler, 'child_exited_unreaped', return_value=False), \
                patch.object(profiler.time, 'sleep', side_effect=failure), \
                patch.object(profiler.os, 'killpg', side_effect=kill):
            with self.assertRaises(type(failure)):
                profiler.capture([str(self.binary)], self.root / 'capture', {}, seconds=177)
        saved = json.loads((self.root / 'capture/capture.json').read_text())
        self.assertEqual(calls, [('killpg', child.pid, signal.SIGKILL), ('wait', 3)])
        self.assertTrue(saved['leader_reaped'])
        self.assertEqual(saved['failure_type'], type(failure).__name__)
        self.assertNotIn('observation', saved)
        self.assertEqual(set(saved['raw']), {'stdout.log', 'stderr.log'})
        self.assertTrue(all('sha256' in row for row in saved['raw'].values()))
        return saved

    def test_keyboard_interrupt_always_kills_reaps_and_records(self) -> None:
        self.mocked_failure(KeyboardInterrupt())

    def test_runtime_error_and_repeated_cleanup_signals_cannot_bypass_receipt(self) -> None:
        saved = self.mocked_failure(RuntimeError('synthetic polling failure'), True)
        self.assertEqual(saved['received_signals'], [signal.SIGTERM, signal.SIGINT])

    def test_deadline_and_capture_limit_keep_their_fixed_bounds(self) -> None:
        for kind in ('deadline', 'limit'):
            with self.subTest(kind=kind):
                clock = {'launched': False}
                waits = []
                class Child:
                    pid = 123456789
                    returncode = None
                    def wait(self, timeout):
                        waits.append(timeout)
                        self.returncode = -signal.SIGKILL
                        return self.returncode
                def start(*args, **kwargs):
                    clock['launched'] = True
                    if kind == 'limit':
                        kwargs['stdout'].write(b'x' * ((2 << 20) + 1))
                        kwargs['stdout'].flush()
                    return Child()
                with patch.object(profiler.subprocess, 'Popen', side_effect=start), \
                        patch.object(profiler, 'child_exited_unreaped', return_value=False), \
                        patch.object(profiler.time, 'monotonic', side_effect=lambda:
                                     178 if kind == 'deadline' and clock['launched'] else 0), \
                        patch.object(profiler.os, 'killpg') as kill:
                    result = profiler.capture([str(self.binary)], self.root / kind, {}, seconds=177)
                kill.assert_called_once_with(123456789, signal.SIGKILL)
                self.assertTrue(result['leader_reaped'])
                self.assertEqual(result['deadline_seconds'], 177)
                self.assertEqual(result['cleanup_deadline_seconds'], 3)
                self.assertEqual(result['case_deadline_seconds'], 180)
                self.assertEqual(waits, [2 if kind == 'deadline' else 3],
                                 'cleanup must consume only the remaining absolute case budget')
                self.assertEqual(result['timed_out'], kind == 'deadline')
                self.assertEqual(result['capture_limit_exceeded'], kind == 'limit')
                self.assertNotIn('observation', result)

    def test_launch_failure_records_no_owned_child_without_signalling_other_groups(self) -> None:
        with patch.object(profiler.subprocess, 'Popen', side_effect=OSError('synthetic launch')), \
                patch.object(profiler.os, 'killpg') as kill:
            with self.assertRaises(OSError):
                profiler.capture([str(self.binary)], self.root / 'capture', {}, seconds=177)
            kill.assert_not_called()
        saved = json.loads((self.root / 'capture/capture.json').read_text())
        self.assertIsNone(saved['pid'])
        self.assertFalse(saved['leader_reaped'])
        self.assertEqual(saved['failure_type'], 'OSError')

    def signal_subprocess(self, signum: int, during_launch: bool) -> None:
        # Both supervisor and its child are owned synthetic Python processes.
        child = self.root / 'child.py'
        ready = self.root / 'ready'
        child.write_text('import os,time\nfrom pathlib import Path\n' +
                         f'Path({str(ready)!r}).write_text(str(os.getpid()))\ntime.sleep(60)\n')
        build = self.root / 'python-build.json'
        build.write_text(json.dumps({'binary_sha256': profiler.digest(Path(sys.executable))}))
        driver = self.root / 'driver.py'
        driver.write_text('''import json,os,signal,subprocess,sys
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import owned_capture as p
root=Path(sys.argv[2]); signum=int(sys.argv[3]); launch=sys.argv[4]=='yes'
real_popen=p.subprocess.Popen
real_kill=p.os.killpg
def start(*args,**kwargs):
 assert kwargs.get('start_new_session') is True
 child=real_popen(*args,**kwargs)
 (root/'owned-pid').write_text(str(child.pid))
 if launch: os.kill(os.getpid(),signum)
 return child
def kill(*args,**kwargs):
 os.kill(os.getpid(),signal.SIGTERM)
 os.kill(os.getpid(),signal.SIGINT)
 return real_kill(*args,**kwargs)
p.subprocess.Popen=start;p.os.killpg=kill
try:
 p.capture([sys.executable,str(root/'child.py')],root/'capture',{},seconds=177)
except p.CaptureInterrupted as error:
 raise SystemExit(128+error.signum)
''')
        process = subprocess.Popen([sys.executable, str(driver), str(profiler.ROOT), str(self.root),
                                    str(signum), 'yes' if during_launch else 'no'],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        owned_pid = None
        try:
            end = time.monotonic() + 5
            marker = self.root / 'owned-pid' if during_launch else ready
            while not marker.exists() and process.poll() is None and time.monotonic() < end:
                time.sleep(0.01)
            self.assertTrue(marker.exists(), 'synthetic child did not start')
            owned_pid = int((self.root / 'owned-pid').read_text())
            if not during_launch:
                os.kill(process.pid, signum)
            stdout, stderr = process.communicate(timeout=8)
            self.assertEqual(process.returncode, 128 + signum, stderr.decode())
            saved = json.loads((self.root / 'capture/capture.json').read_text())
            self.assertTrue(saved['leader_reaped'])
            self.assertEqual(saved['failure_type'], 'CaptureInterrupted')
            self.assertEqual(saved['received_signals'], [signum, signal.SIGTERM, signal.SIGINT])
            self.assertNotIn('observation', saved)
            with self.assertRaises(ProcessLookupError):
                os.kill(owned_pid, 0)
            owned_pid = None
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
            if owned_pid:
                try:
                    os.killpg(owned_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_sigterm_during_popen_registration_and_repeated_cleanup_signals(self) -> None:
        self.signal_subprocess(signal.SIGTERM, True)

    def test_sigint_during_popen_registration_and_repeated_cleanup_signals(self) -> None:
        self.signal_subprocess(signal.SIGINT, True)

    def test_sigterm_during_owned_capture_and_repeated_cleanup_signals(self) -> None:
        self.signal_subprocess(signal.SIGTERM, False)

    def test_sigint_during_owned_capture_and_repeated_cleanup_signals(self) -> None:
        self.signal_subprocess(signal.SIGINT, False)

    def test_actual_short_deadline_without_load_marker_retains_receipt_and_reaps(self):
        # Interpreter startup is charged to the deadline and cannot prove load.
        script = 'import time\ntime.sleep(60)\n'
        output = self.root / 'actual-deadline'
        result = profiler.capture([sys.executable, '-c', script], output, {},
                                  seconds=0.2, observation_seconds=0.05)
        self.assertTrue(result['timed_out'])
        self.assertTrue(result['leader_reaped'])
        self.assertEqual(result['exit'], -signal.SIGKILL)
        self.assertEqual(result['cleanup_errors'], [])
        self.assertIsNone(result['failure_type'])
        self.assertIsNone(result['load_observation']['pending'])
        self.assertIsNone(result['load_observation']['reported_load_ms'])
        self.assertFalse(result['qualified'])
        self.assertEqual(result['deadline_seconds'], 0.2)
        self.assertEqual(result['cleanup_deadline_seconds'], 3)
        self.assertEqual(result['case_deadline_seconds'], 3.2)
        self.assertEqual(json.loads((output / 'capture.json').read_text()), result)
        with self.assertRaises(ProcessLookupError): os.kill(result['pid'], 0)

    def test_load_observation_uses_marker_time_without_extending_absolute_deadline(self):
        for label, marker_at, pending in (('early', 100.0, True),
                                          ('late', 100.18, None),
                                          ('absent', None, None)):
            with self.subTest(marker=label):
                clock = {'now': 100.0, 'stdout': None, 'emitted': False}
                calls = []
                class Child:
                    pid = 123456789
                    returncode = None
                    def wait(self, timeout):
                        calls.append(('wait', timeout, clock['now']))
                        self.returncode = -signal.SIGKILL
                        return self.returncode
                child = Child()
                def emit_marker():
                    if marker_at is not None and not clock['emitted'] and clock['now'] >= marker_at:
                        clock['stdout'].write(b'SD24_STAGE {"schema":1,"stage":"load_begin","elapsedMs":0,"loadMs":-1}\n')
                        clock['stdout'].flush()
                        clock['emitted'] = True
                def start(*args, **kwargs):
                    self.assertTrue(kwargs['start_new_session'])
                    calls.append(('Popen', clock['now']))
                    clock['stdout'] = kwargs['stdout']
                    emit_marker()
                    return child
                def sleep(seconds):
                    self.assertEqual(seconds, 0.02)
                    clock['now'] = round(clock['now'] + seconds, 9)
                    emit_marker()
                def kill(pid, signum):
                    calls.append(('killpg', pid, signum, clock['now']))
                output = self.root / ('marker-' + label)
                with patch.object(profiler.subprocess, 'Popen', side_effect=start), \
                        patch.object(profiler, 'child_exited_unreaped', return_value=False), \
                        patch.object(profiler.time, 'monotonic', side_effect=lambda: clock['now']), \
                        patch.object(profiler.time, 'sleep', side_effect=sleep), \
                        patch.object(profiler.os, 'killpg', side_effect=kill):
                    result = profiler.capture([str(self.binary)], output, {},
                                              seconds=0.2, observation_seconds=0.05)
                self.assertEqual(calls, [('Popen', 100.0),
                                        ('killpg', child.pid, signal.SIGKILL, 100.2),
                                        ('wait', 3, 100.2)])
                self.assertEqual(clock['now'], 100.2)
                self.assertEqual(calls[-1][2] + calls[-1][1], 103.2)
                self.assertEqual(result['exit'], -signal.SIGKILL)
                self.assertTrue(result['timed_out'])
                self.assertTrue(result['leader_reaped'])
                self.assertEqual(result['cleanup_errors'], [])
                self.assertIsNone(result['failure_type'])
                self.assertFalse(result['qualified'])
                self.assertEqual(result['deadline_seconds'], 0.2)
                self.assertEqual(result['cleanup_deadline_seconds'], 3)
                self.assertEqual(result['case_deadline_seconds'], 3.2)
                self.assertAlmostEqual(result['elapsed_seconds'], 0.2)
                self.assertIsNone(result['shared_active_deadline'])
                self.assertIsNone(result['shared_total_deadline'])
                self.assertEqual(result['load_observation']['at_seconds'], 0.05)
                self.assertIs(result['load_observation']['pending'], pending)
                self.assertIsNone(result['load_observation']['reported_load_ms'])
                self.assertEqual(clock['emitted'], marker_at is not None)
                self.assertEqual(json.loads((output / 'capture.json').read_text()), result)

    def test_actual_output_limit_and_widened_bounds_are_not_accepted(self):
        script = "import time\nprint('x'*4096,flush=True)\ntime.sleep(60)\n"
        result = profiler.capture([sys.executable, '-c', script], self.root / 'actual-limit', {},
                                  seconds=1, max_bytes=1024)
        self.assertTrue(result['capture_limit_exceeded'])
        self.assertTrue(result['leader_reaped'])
        for options in ({'seconds':178}, {'max_bytes':(2 << 20)+1}, {'observation_seconds':46}):
            with self.assertRaises(ValueError):
                profiler.capture([sys.executable], self.root / 'not-created', {}, **options)

    def test_malformed_stage_cannot_bypass_terminal_receipt_or_cleanup(self):
        script = 'import time\nprint(\'SD24_STAGE ["not","an object"]\',flush=True)\ntime.sleep(60)\n'
        result = profiler.capture([sys.executable, '-c', script], self.root / 'malformed-stage', {}, seconds=0.15)
        self.assertTrue(result['timed_out'])
        self.assertTrue(result['leader_reaped'])
        self.assertTrue((self.root / 'malformed-stage/capture.json').is_file())
        self.assertEqual(result['cleanup_errors'], [])

    def test_active_foreign_alarm_is_refused_before_popen(self):
        previous = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGALRM})
        try:
            signal.setitimer(signal.ITIMER_REAL, 10)
            with patch.object(profiler.subprocess, 'Popen') as launch:
                with self.assertRaisesRegex(ValueError, 'SIGALRM'):
                    profiler.capture([sys.executable], self.root / 'active-alarm', {})
                launch.assert_not_called()
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            if signal.SIGALRM in signal.sigpending(): signal.sigwait({signal.SIGALRM})
            signal.pthread_sigmask(signal.SIG_SETMASK, previous)

    def test_expired_cancelled_os_alarm_is_refused_before_popen(self):
        previous = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGALRM})
        try:
            signal.setitimer(signal.ITIMER_REAL, 0.01)
            pending_deadline = time.monotonic() + 2
            while signal.SIGALRM not in signal.sigpending() and time.monotonic() < pending_deadline:
                time.sleep(0.005)
            self.assertIn(signal.SIGALRM, signal.sigpending(), 'alarm must expire before cancellation')
            signal.setitimer(signal.ITIMER_REAL, 0)
            self.assertIn(signal.SIGALRM, signal.sigpending(), 'real cancelled alarm must remain pending')
            with patch.object(profiler.subprocess, 'Popen') as launch:
                with self.assertRaisesRegex(ValueError, 'SIGALRM'):
                    profiler.capture([sys.executable], self.root / 'no-alarm-launch', {})
                launch.assert_not_called()
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            if signal.SIGALRM in signal.sigpending(): signal.sigwait({signal.SIGALRM})
            signal.pthread_sigmask(signal.SIG_SETMASK, previous)


if __name__ == '__main__':
    unittest.main()
