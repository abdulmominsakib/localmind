"""Finite owned-process fixtures for the maintained subprocess host.

Only the fixture's returned child group is signaled. IDs below are observations,
not a claim that a PID receipt establishes general descendant ownership.
"""
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
import importlib.util
import io
from types import SimpleNamespace


HOST = Path(__file__).resolve().parents[3] / 'tool/testing/validation/process_host.py'
WAITID_NAMES = ('waitid', 'P_PID', 'WEXITED', 'WNOHANG', 'WNOWAIT',
                'CLD_EXITED', 'CLD_KILLED', 'CLD_DUMPED')


def load_host(name):
    spec = importlib.util.spec_from_file_location(name, HOST)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# macOS gains os.waitid in Python 3.13; older hosts use the unheld fallback.
HELD_CHILD = load_host('held_child_probe').posix_waitid_available()


@unittest.skipIf(os.name == 'nt', 'POSIX owned-group source fixtures')
class ProcessHostTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='validation-host-fixture-')
        self.root = Path(self.scratch.name)
        self.host = None
        self.child = None

    def tearDown(self):
        observed = self.root / 'observed.json'
        if self.child is None and observed.exists():
            self.child = json.loads(observed.read_text())
        # Only the actual returned fixture host remains a delivery authority.
        # Once the host has reaped its child, an old child PID/group observation
        # cannot authorize teardown to signal that group again.
        if self.host is not None and self.host.poll() is None:
            self.host.terminate()
            self.host.wait(timeout=8)
        child_absent = None
        if self.child is not None:
            try:
                os.getpgid(self.child['pid'])
                child_absent = False
            except ProcessLookupError:
                child_absent = True
        print(json.dumps({'fixture': self.id().split('.')[-1],
                          'cleanup': {'host_waited': self.host is None or self.host.poll() is not None,
                                      'recorded_child_absent': child_absent}}), flush=True)
        self.scratch.cleanup()

    def launch(self, mode, child_source):
        script = '''
import importlib.util, json, os, pathlib, signal, subprocess, sys, time
spec = importlib.util.spec_from_file_location('owned_host', sys.argv[1])
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)
root = pathlib.Path(sys.argv[2])
mode = sys.argv[3]
source = sys.argv[4]
if mode == 'unheld-fallback' or mode.startswith(('missing:', 'denied-')):
    # Remove the name itself, as on a Python without it, not the host's gate.
    name = mode.partition(':')[2] or 'waitid'
    if hasattr(host.os, name):
        delattr(host.os, name)
if mode.startswith('denied-'):
    # macOS denies killpg on a group whose members are all unreaped zombies.
    def denied(group, sig):
        raise PermissionError()
    host.os.killpg = denied
if mode == 'exited-leader-inherited-pipe':
    original_waitid = host.os.waitid
    def observed_completion(kind, pid, flags):
        result = original_waitid(kind, pid, flags)
        if result is not None and not (root / 'completion.json').exists():
            with (root / 'completion.json').open('x') as stream:
                stream.write(json.dumps({'pid': result.si_pid,
                                         'WNOWAIT': bool(flags & host.os.WNOWAIT)}))
                stream.flush()
        return result
    host.os.waitid = observed_completion
def wait_for_zombie(pid):
    for _ in range(500):
        state = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)],
                               capture_output=True, text=True).stdout
        if state.strip().startswith('Z'):
            return
        time.sleep(0.01)
    raise RuntimeError('fixture child did not exit')
if mode == 'exited-before-bind':
    # macOS getpgid() raises ESRCH for an exited child that is still unreaped.
    def exited_lookup(pid):
        (root / 'observed.json').write_text(json.dumps({'pid': pid}))
        wait_for_zombie(pid)
        raise ProcessLookupError()
    host.os.getpgid = exited_lookup
setup_done = []
stop_requests = []
def receipt(pid):
    data = {'pid': pid, 'pgid': os.getpgid(pid)}
    (root / 'observed.json').write_text(json.dumps(data))
    if mode in ('exited-slow-receipt', 'stopped-receipt', 'denied-exited-setup'):
        wait_for_zombie(pid)
    if mode == 'stopped-receipt':
        host_stop = signal.getsignal(signal.SIGTERM)
        def observed_stop(signum, frame):
            host_stop(signum, frame)
            stop_requests.append(signum)
        signal.signal(signal.SIGTERM, observed_stop)
    if mode in ('publication-failure', 'denied-exited-setup'):
        with (root / 'occupied').open('x') as stream:
            stream.write(json.dumps({'pid': pid}))
    else:
        with (root / 'receipt.json').open('x') as stream:
            stream.write(json.dumps({'pid': pid}))
            stream.flush()
    if mode == 'reader-failure':
        def reject_start(self):
            raise RuntimeError('fixture reader setup failure')
        host.threading.Thread.start = reject_start
    if mode == 'slow-receipt':
        time.sleep(2.5)
        setup_done.append(time.monotonic())
    if mode == 'exited-slow-receipt':
        time.sleep(0.15)
    if mode == 'stopped-receipt':
        for _ in range(500):
            if stop_requests:
                break
            time.sleep(0.01)
    if mode in ('exited-slow-receipt', 'stopped-receipt'):
        # Deterministically reach the terminal predicate after the empty-output
        # child exits; do not depend on reader-thread scheduling for this case.
        host.threading.Thread.start = lambda thread: thread.run()
seconds = {'slow-receipt': '2.0', 'exited-slow-receipt': '0.1'}.get(mode, '4')
sys.argv = [str(spec.origin), seconds, sys.executable, '-c', source]
try:
    sys.exit(host.main(None if mode in ('default', 'exited-before-bind') or mode.startswith('missing:') else receipt))
except Exception as error:
    print('Subprocess host failed (' + type(error).__name__ + ')', file=sys.stderr)
    sys.exit(125)
finally:
    if setup_done:
        (root / 'after-setup.json').write_text(json.dumps(time.monotonic() - setup_done[0]))
'''
        self.host = subprocess.Popen(
            [sys.executable, '-c', script, str(HOST), str(self.root), mode, child_source],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def complete(self):
        output, error = self.host.communicate(timeout=8)
        observed = self.root / 'observed.json'
        if observed.exists():
            self.child = json.loads(observed.read_text())
        print(json.dumps({'fixture': self.id().split('.')[-1],
                          'host_pid': self.host.pid, 'child': self.child,
                          'status': self.host.returncode}), flush=True)
        return self.host.returncode, output, error

    def sleeping_child(self):
        return (
            'from pathlib import Path; import time; '
            f'Path({str(self.root / "ready")!r}).write_text("ready"); '
            'time.sleep(0.7); '
            f'Path({str(self.root / "leaked")!r}).write_text("leaked")'
        )

    def assert_child_retired(self):
        self.assertIsNotNone(self.child)
        time.sleep(0.9)
        self.assertFalse((self.root / 'leaked').exists())
        with self.assertRaises(ProcessLookupError):
            os.kill(self.child['pid'], 0)
        with self.assertRaises(ProcessLookupError):
            os.killpg(self.child['pgid'], 0)

    def test_default_output_and_status(self):
        self.launch('default', 'import sys; print("out"); print("err", file=sys.stderr); sys.exit(17)')
        status, output, error = self.complete()
        self.assertEqual((status, output, error), (17, b'out\n', b'err\n'))
        self.assertFalse((self.root / 'receipt.json').exists())

    def test_opt_in_actual_returned_pid_and_status(self):
        self.launch('receipt', 'import sys; print("out"); sys.exit(17)')
        status, output, error = self.complete()
        self.assertEqual((status, output, error), (17, b'out\n', b''))
        receipt = json.loads((self.root / 'receipt.json').read_text())
        self.assertEqual(receipt, {'pid': self.child['pid']})
        self.assertGreater(self.child['pid'], 0)
        self.assertEqual(self.child['pid'], self.child['pgid'])

    def test_failed_publication_keeps_failure_and_retires_child(self):
        (self.root / 'occupied').write_bytes(b'prior receipt')
        self.launch('publication-failure', self.sleeping_child())
        status, output, error = self.complete()
        self.assertEqual(status, 125)
        self.assertEqual(output, b'')
        self.assertEqual(error, b'Subprocess host failed (FileExistsError)\n')
        self.assertEqual((self.root / 'occupied').read_bytes(), b'prior receipt')
        self.assert_child_retired()

    def test_reader_setup_failure_retires_child(self):
        self.launch('reader-failure', self.sleeping_child())
        status, output, error = self.complete()
        self.assertEqual(status, 125)
        self.assertEqual(output, b'')
        self.assertEqual(error, b'Subprocess host failed (RuntimeError)\n')
        self.assert_child_retired()

    def test_receipt_setup_time_is_charged_to_deadline(self):
        # A 2.5 s receipt overruns the 2.0 s deadline. Charged setup stops the
        # child at once; uncharged setup would wait at least another 2.0 s.
        self.launch('slow-receipt', self.sleeping_child().replace('sleep(0.7)', 'sleep(30)'))
        status, output, error = self.complete()
        self.assertEqual((status, output, error), (124, b'', b''))
        self.assertLess(json.loads((self.root / 'after-setup.json').read_text()), 1.5)
        self.assert_child_retired()

    def test_exited_child_does_not_bypass_setup_deadline(self):
        self.launch('exited-slow-receipt', 'pass')
        status, output, error = self.complete()
        self.assertEqual((status, output, error), (124, b'', b''))
        with self.assertRaises(ProcessLookupError):
            os.kill(self.child['pid'], 0)

    def test_exited_child_does_not_bypass_stop_during_setup(self):
        # The receipt waits for this SIGTERM, so it always lands during setup.
        self.launch('stopped-receipt', 'pass')
        for _ in range(400):
            if (self.root / 'receipt.json').exists():
                break
            time.sleep(0.005)
        self.assertTrue((self.root / 'receipt.json').exists())
        self.host.send_signal(signal.SIGTERM)
        status, output, error = self.complete()
        self.assertEqual((status, output, error), (143, b'', b''))
        with self.assertRaises(ProcessLookupError):
            os.kill(self.child['pid'], 0)

    def test_sigterm_retains_receipt_and_retires_child(self):
        self.launch('receipt', self.sleeping_child())
        for _ in range(400):
            if (self.root / 'ready').exists():
                break
            time.sleep(0.005)
        self.assertTrue((self.root / 'ready').exists())
        self.host.send_signal(signal.SIGTERM)
        status, output, error = self.complete()
        self.assertEqual((status, output, error), (143, b'', b''))
        self.assertEqual(json.loads((self.root / 'receipt.json').read_text()),
                         {'pid': self.child['pid']})
        self.assert_child_retired()

    def test_host_without_waitid_keeps_status_and_retires_descendants(self):
        descendant = (
            'import time; from pathlib import Path; time.sleep(0.7); '
            f'Path({str(self.root / "leaked")!r}).write_text("leaked")'
        )
        child = (
            'import subprocess,sys; '
            f'subprocess.Popen([sys.executable,"-c",{descendant!r}], stdin=subprocess.DEVNULL, '
            'stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); '
            'print("leader", flush=True); sys.exit(17)'
        )
        self.launch('unheld-fallback', child)
        status, output, error = self.complete()
        self.assertEqual((status, output, error), (17, b'leader\n', b''))
        self.assert_child_retired()

    def test_each_missing_waitid_name_uses_unheld_fallback(self):
        # A signal-killed child makes the held path read every name.
        child = 'import os, signal; print("leader", flush=True); os.kill(os.getpid(), signal.SIGKILL)'
        for name in WAITID_NAMES:
            with self.subTest(name=name):
                self.launch('missing:' + name, child)
                status, output, error = self.complete()
                self.assertEqual((status, output, error),
                                 (-signal.SIGKILL & 0xFF, b'leader\n', b''))

    def test_denied_zombie_group_keeps_setup_error(self):
        (self.root / 'occupied').write_bytes(b'prior receipt')
        self.launch('denied-exited-setup', 'pass')
        status, output, error = self.complete()
        self.assertEqual((status, output, error),
                         (125, b'', b'Subprocess host failed (FileExistsError)\n'))
        with self.assertRaises(ProcessLookupError):
            os.kill(self.child['pid'], 0)

    def test_denied_group_without_setup_error_stays_failure(self):
        self.launch('denied-exit', 'import sys; sys.exit(17)')
        status, output, error = self.complete()
        self.assertEqual((status, output, error),
                         (125, b'', b'Subprocess host failed (PermissionError)\n'))

    @unittest.skipUnless(HELD_CHILD, 'os.waitid is unavailable on this host')
    def test_child_exited_before_bind_keeps_output_and_status(self):
        self.launch('exited-before-bind',
                    'import sys; print("out"); print("err", file=sys.stderr); sys.exit(17)')
        status, output, error = self.complete()
        self.assertEqual((status, output, error), (17, b'out\n', b'err\n'))
        with self.assertRaises(ProcessLookupError):
            os.kill(self.child['pid'], 0)
        with self.assertRaises(ProcessLookupError):
            os.killpg(self.child['pid'], 0)

    @unittest.skipUnless(HELD_CHILD, 'os.waitid is unavailable on this host')
    def test_exited_leader_with_inherited_pipe_stays_reserved_until_stop(self):
        descendant = (
            'import time; from pathlib import Path; time.sleep(0.7); '
            f'Path({str(self.root / "leaked")!r}).write_text("leaked")'
        )
        child = (
            'import subprocess,sys; '
            f'subprocess.Popen([sys.executable,"-c",{descendant!r}]); '
            'print("leader", flush=True)'
        )
        self.launch('exited-leader-inherited-pipe', child)
        completion = self.root / 'completion.json'
        for _ in range(200):
            if completion.exists() and (self.root / 'receipt.json').exists():
                break
            time.sleep(0.005)
        self.assertTrue(completion.exists())
        observed = json.loads(completion.read_text())
        receipt = json.loads((self.root / 'receipt.json').read_text())
        self.assertEqual(observed, {'pid': receipt['pid'], 'WNOWAIT': True})
        self.host.send_signal(signal.SIGTERM)
        status, output, error = self.complete()
        # The retained stop contract covers status and actual retirement.
        # Existing buffered daemon readers do not promise a delivered prefix
        # before stop; ordinary successful stdout/status has its own tests.
        self.assertEqual((status, error), (143, b''))
        self.assert_child_retired()


@unittest.skipIf(os.name == 'nt', 'POSIX reservation source controls')
@unittest.skipUnless(HELD_CHILD, 'os.waitid is unavailable on this host')
class PosixReservationTest(unittest.TestCase):
    def setUp(self):
        self.module = load_host('reservation_host')
        self.events = []
        self.child = SimpleNamespace(pid=42, returncode=None)
        def reap(timeout):
            self.events.append('reap')
            self.child.returncode = 17
            return 17
        self.child.wait = reap
        self.child.poll = lambda: (_ for _ in ()).throw(AssertionError('reaping poll forbidden'))
        self.observation = SimpleNamespace(si_pid=42, si_code=self.module.os.CLD_EXITED, si_status=17)

    def test_final_group_delivery_precedes_reap_with_WNOWAIT(self):
        def observe(kind, pid, flags):
            self.assertTrue(flags & self.module.os.WNOWAIT)
            self.assertEqual((kind, pid), (self.module.os.P_PID, 42))
            self.assertIsNone(self.child.returncode)
            self.events.append('observe')
            return self.observation
        def group_signal(group, sig):
            self.assertEqual(group, 42)
            if sig == signal.SIGKILL:
                self.assertIsNone(self.child.returncode)
                self.events.append('deliver')
            elif self.child.returncode is not None:
                raise ProcessLookupError()
        with patch.object(self.module.os, 'waitid', observe), patch.object(self.module.os, 'getpgid', return_value=42), patch.object(self.module.os, 'killpg', group_signal):
            reservation = self.module.PosixChildReservation(self.child)
            reservation.bind()
            self.assertEqual(reservation.observe(), 17)
            reservation.retire()
        self.assertLess(self.events.index('deliver'), self.events.index('reap'))
        self.assertFalse(reservation.held)

    def test_lost_reservation_never_delivers_group_signal(self):
        reservation = self.module.PosixChildReservation(self.child)
        reservation.group = 42
        with patch.object(self.module.os, 'waitid', side_effect=ChildProcessError()), patch.object(self.module.os, 'killpg') as delivery:
            with self.assertRaisesRegex(RuntimeError, 'reservation was lost'):
                reservation.retire()
        delivery.assert_not_called()
        self.assertEqual(self.events, [])

    def test_permission_unknown_reaps_then_requires_eventual_ESRCH(self):
        reservation = self.module.PosixChildReservation(self.child)
        reservation.group = 42
        probes = [PermissionError(), PermissionError(), ProcessLookupError()]
        def group_probe(group, sig):
            self.assertEqual((group, sig), (42, 0))
            raise probes.pop(0)
        with patch.object(self.module.os, 'waitid', return_value=self.observation), patch.object(self.module.os, 'getpgid', return_value=42), patch.object(self.module.os, 'killpg', group_probe), patch.object(self.module.time, 'sleep'):
            reservation.retire()
        self.assertEqual(self.events, ['reap'])
        self.assertEqual(probes, [])
        self.assertFalse(reservation.held)

    def test_delivery_denial_still_reaps_and_needs_ESRCH(self):
        reservation = self.module.PosixChildReservation(self.child)
        reservation.group = 42
        calls = []
        def group_signal(group, sig):
            calls.append((sig, self.child.returncode))
            if sig == signal.SIGKILL:
                raise PermissionError()
            if self.child.returncode is not None:
                raise ProcessLookupError()
        with patch.object(self.module.os, 'waitid', return_value=self.observation), patch.object(self.module.os, 'getpgid', return_value=42), patch.object(self.module.os, 'killpg', group_signal):
            reservation.retire()
        self.assertEqual(self.events, ['reap'])
        self.assertEqual(calls, [(0, None), (signal.SIGKILL, None), (0, 17)])

    def test_denied_live_child_wait_failure_never_claims_retirement(self):
        reservation = self.module.PosixChildReservation(self.child)
        reservation.group = 42
        waits = []
        def bounded_wait(timeout):
            waits.append(timeout)
            raise subprocess.TimeoutExpired('owned-fixture-child', timeout)
        self.child.wait = bounded_wait
        with patch.object(self.module.os, 'waitid', return_value=None), patch.object(self.module.os, 'getpgid', return_value=42), patch.object(self.module.os, 'killpg', side_effect=PermissionError()) as probe:
            with self.assertRaises(subprocess.TimeoutExpired):
                reservation.retire()
        self.assertEqual(probe.call_args_list[0].args, (42, 0))
        self.assertEqual(probe.call_count, 1)
        self.assertEqual(len(waits), 1)
        self.assertGreater(waits[0], 0)
        self.assertLessEqual(waits[0], 5)
        self.assertTrue(reservation.held)
        self.assertIsNone(self.child.returncode)

    def test_post_reap_permission_unknown_stays_failure_at_deadline(self):
        reservation = self.module.PosixChildReservation(self.child)
        reservation.group = 42
        calls = []
        def unknown_group(group, sig):
            calls.append((sig, self.child.returncode))
            raise PermissionError()
        with patch.object(self.module.os, 'waitid', return_value=self.observation), patch.object(self.module.os, 'getpgid', return_value=42), patch.object(self.module.os, 'killpg', unknown_group), patch.object(self.module.time, 'monotonic', side_effect=[0, 0, 0, 6]), patch.object(self.module.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'retirement deadline expired'):
                reservation.retire()
        self.assertEqual(self.events, ['reap'])
        self.assertFalse(reservation.held)
        self.assertTrue(all(sig == 0 for sig, _ in calls))

    def test_no_delivering_group_signal_after_reap(self):
        reservation = self.module.PosixChildReservation(self.child)
        reservation.group = 42
        calls = []
        def group_signal(group, sig):
            calls.append((sig, self.child.returncode))
            if self.child.returncode is not None:
                self.assertEqual(sig, 0)
                raise ProcessLookupError()
        with patch.object(self.module.os, 'waitid', return_value=self.observation), patch.object(self.module.os, 'getpgid', return_value=42), patch.object(self.module.os, 'killpg', group_signal):
            reservation.retire()
        self.assertEqual(calls, [(0, None), (signal.SIGKILL, None), (0, 17)])


    def test_bound_completed_leader_uses_reserved_group_without_late_lookup(self):
        calls = []
        def group_signal(group, sig):
            self.assertEqual(group, 42)
            calls.append((sig, self.child.returncode))
            if self.child.returncode is not None:
                self.assertEqual(sig, 0)
                raise ProcessLookupError()
        with patch.object(self.module.os, 'waitid', side_effect=[None, self.observation]), patch.object(self.module.os, 'getpgid', side_effect=[42, AssertionError('late completed lookup forbidden')]) as lookup, patch.object(self.module.os, 'killpg', group_signal):
            reservation = self.module.PosixChildReservation(self.child)
            reservation.bind()
            reservation.retire()
        self.assertEqual(lookup.call_count, 1)
        self.assertEqual(calls, [(0, None), (signal.SIGKILL, None), (0, 17)])
        self.assertEqual(self.events, ['reap'])
        self.assertFalse(reservation.held)

    def test_bound_lookup_ESRCH_requires_fresh_unreaped_completion(self):
        calls = []
        def group_signal(group, sig):
            calls.append((sig, self.child.returncode))
            if self.child.returncode is not None:
                self.assertEqual(sig, 0)
                raise ProcessLookupError()
        with patch.object(self.module.os, 'waitid', side_effect=[None, None, self.observation]) as observe, patch.object(self.module.os, 'getpgid', side_effect=[42, ProcessLookupError()]) as lookup, patch.object(self.module.os, 'killpg', group_signal):
            reservation = self.module.PosixChildReservation(self.child)
            reservation.bind()
            reservation.retire()
        self.assertEqual(observe.call_count, 3)
        self.assertEqual(lookup.call_count, 2)
        self.assertEqual(calls, [(0, None), (signal.SIGKILL, None), (0, 17)])
        self.assertEqual(self.events, ['reap'])
        self.assertFalse(reservation.held)

    def test_bound_lookup_ESRCH_without_completion_refuses_delivery(self):
        reservation = self.module.PosixChildReservation(self.child)
        reservation.group = 42
        with patch.object(self.module.os, 'waitid', return_value=None), patch.object(self.module.os, 'getpgid', side_effect=ProcessLookupError()), patch.object(self.module.os, 'killpg') as delivery:
            with self.assertRaisesRegex(RuntimeError, 'binding is unproved'):
                reservation.retire()
        delivery.assert_not_called()
        self.assertEqual(self.events, [])
        self.assertTrue(reservation.held)

    def test_lookup_ESRCH_after_held_completion_binds_own_session_group(self):
        # The child exits between the first observation and the lookup.
        calls = []
        def group_signal(group, sig):
            self.assertEqual(group, 42)
            calls.append((sig, self.child.returncode))
            if self.child.returncode is not None:
                self.assertEqual(sig, 0)
                raise ProcessLookupError()
        with patch.object(self.module.os, 'waitid', side_effect=[None, self.observation, self.observation]), patch.object(self.module.os, 'getpgid', side_effect=[ProcessLookupError(), AssertionError('late completed lookup forbidden')]) as lookup, patch.object(self.module.os, 'kill') as leader_stop, patch.object(self.module.os, 'killpg', group_signal):
            reservation = self.module.PosixChildReservation(self.child)
            reservation.bind()
            self.assertEqual(reservation.group, 42)
            reservation.retire()
        self.assertEqual(lookup.call_count, 1)
        leader_stop.assert_not_called()
        self.assertEqual(calls, [(0, None), (signal.SIGKILL, None), (0, 17)])
        self.assertEqual(self.events, ['reap'])
        self.assertEqual(reservation.returncode, 17)
        self.assertFalse(reservation.held)

    def test_initial_lookup_ESRCH_without_completion_never_guesses_group(self):
        reservation = self.module.PosixChildReservation(self.child)
        def own_leader_stop(pid, sig):
            self.assertEqual((pid, sig), (42, signal.SIGKILL))
            self.assertIsNone(self.child.returncode)
            self.events.append('own-leader-stop')
        with patch.object(self.module.os, 'waitid', side_effect=[None, None, self.observation]), patch.object(self.module.os, 'getpgid', side_effect=ProcessLookupError()), patch.object(self.module.os, 'kill', own_leader_stop), patch.object(self.module.os, 'killpg') as delivery:
            with self.assertRaises(ProcessLookupError):
                reservation.bind()
            self.assertIsNone(reservation.group)
            with self.assertRaisesRegex(RuntimeError, 'group retirement remains unproved'):
                reservation.retire()
        delivery.assert_not_called()
        self.assertEqual(self.events, ['own-leader-stop', 'reap'])
        self.assertFalse(reservation.held)

@unittest.skipIf(os.name == 'nt', 'POSIX reservation source controls')
@unittest.skipUnless(HELD_CHILD, 'os.waitid is unavailable on this host')
class GroupAbsenceTimeoutTest(unittest.TestCase):
    def run_host(self, child_source, group_probe, seconds='5'):
        module = load_host('absence_timeout_host')
        stdout = io.TextIOWrapper(io.BytesIO())
        stderr = io.TextIOWrapper(io.BytesIO())
        argv = ['host', seconds, sys.executable, '-c', child_source]
        previous = {s: signal.getsignal(s) for s in (signal.SIGTERM, signal.SIGINT)}
        try:
            with patch.object(module.sys, 'argv', argv), \
                    patch.object(module.sys, 'stdout', stdout), \
                    patch.object(module.sys, 'stderr', stderr), \
                    patch.object(module, 'RETIREMENT_SECONDS', 0.1), \
                    patch.object(module.os, 'killpg', group_probe):
                try:
                    status = module.main()
                except Exception as error:
                    status = error
        finally:
            for number, handler in previous.items():
                signal.signal(number, handler)
        stderr.flush()
        return status, stderr.buffer.getvalue()

    def test_known_status_wins_when_group_absence_wait_times_out(self):
        def never_absent(group, sig):
            raise PermissionError()
        status, error = self.run_host('import sys; sys.exit(17)', never_absent)
        self.assertEqual(status, 17)
        self.assertIn(b'keeping the child exit status', error)

    def test_unknown_status_still_fails_when_group_absence_wait_times_out(self):
        real_killpg = os.killpg
        delivered = []
        def unprovable_absence(group, sig):
            if sig == 0 and delivered:
                raise PermissionError()
            real_killpg(group, sig)
            delivered.append(sig)
        status, error = self.run_host('import time; time.sleep(30)',
                                      unprovable_absence, seconds='0.2')
        self.assertIsInstance(status, Exception)
        self.assertEqual(str(status), 'Child group retirement deadline expired')
        self.assertNotIn(b'keeping', error)


if __name__ == '__main__':
    unittest.main()
