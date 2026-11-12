"""Model-free Linux process/pipe fixtures for the production Chrome supervisor."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'tool/ci/supervise_chrome_test.py'


def load_supervisor():
    spec = importlib.util.spec_from_file_location('supervise_chrome_test', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ProcessTableTest(unittest.TestCase):
    def test_processes_exiting_mid_scan_do_not_abort_the_table(self):
        supervisor = load_supervisor()
        with tempfile.TemporaryDirectory() as temp:
            proc = Path(temp)
            stat_tail = ' '.join(['S', '1', '10', '10'] + ['0'] * 15 + ['4242'])
            for pid in ('100', '101', '102'):
                (proc / pid).mkdir()
                (proc / pid / 'stat').write_text(f'{pid} (worker) {stat_tail}\n')
                (proc / pid / 'wchan').write_text('do_wait')
            vanished = {proc / '101' / 'stat', proc / '102' / 'wchan'}
            read_text = Path.read_text

            def racing_read(path, *args, **kwargs):
                if path in vanished:
                    raise ProcessLookupError(3, 'No such process')
                return read_text(path, *args, **kwargs)

            with mock.patch.object(supervisor, 'Path', lambda _: proc), \
                    mock.patch.object(Path, 'read_text', racing_read):
                table = supervisor.process_table()

        self.assertEqual(sorted(table), [100, 102])
        self.assertEqual(table[100]['wchan'], 'do_wait')
        self.assertEqual(table[102]['wchan'], 'unavailable')
        self.assertEqual(table[102]['start_ticks'], 4242)


class ReporterEventsTest(unittest.TestCase):
    def test_reads_split_lines_and_counts_only_visible_tests(self):
        supervisor = load_supervisor()
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'events.jsonl'
            reporter = supervisor.ReporterEvents(path)
            self.assertFalse(reporter.poll())
            path.write_bytes(b'{"type":"testDone","hidden":true}\nnot json\n[]\n'
                             b'{"type":"testDone","hidden":false}\n{"type":"do')
            self.assertFalse(reporter.poll())
            self.assertIsNone(reporter.verdict())
            with path.open('ab') as events:
                events.write(b'ne","success":true}\n')
            self.assertTrue(reporter.poll())
            self.assertFalse(reporter.poll())
        self.assertEqual((reporter.tests, reporter.success, reporter.verdict()), (1, True, 0))

    def test_verdict_needs_a_settled_result_with_tests(self):
        supervisor = load_supervisor()
        for tests, success, verdict in [(2, True, 0), (2, False, 1), (0, False, 1),
                                        (0, True, None), (2, None, None)]:
            reporter = supervisor.ReporterEvents(None)
            reporter.tests, reporter.success = tests, success
            self.assertEqual(reporter.verdict(), verdict, (tests, success))


@unittest.skipUnless(sys.platform == 'linux', 'Requires Linux /proc and pidfds')
class SupervisorTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / 'diagnostics'

    def command(self, program, timeout=3, shutdown=0.25, reporter=False, post_done=0.3,
                script=SCRIPT):
        options = (['--reporter-file', str(self.reporter), '--post-done-seconds', str(post_done)]
                   if reporter else [])
        return [sys.executable, str(script), '--output-dir', str(self.output),
                '--timeout-seconds', str(timeout), '--shutdown-seconds', str(shutdown),
                '--cleanup-seconds', '0.5', '--snapshot-seconds', '0.1', *options, '--',
                sys.executable, '-c', program]

    @property
    def reporter(self):
        return Path(self.temp.name) / 'reporter.jsonl'

    def browser_then(self, done, browser_seconds, then):
        """A CLI that reports `done`, runs a process named `chrome`, then runs `then`."""
        # A script's comm is its own file name; multicall coreutils reject a renamed sleep.
        browser = Path(self.temp.name) / 'chrome'
        browser.write_text(f'#!{sys.executable}\nimport sys,time; time.sleep(float(sys.argv[1]))\n')
        browser.chmod(0o755)
        events = [{'type': 'testDone', 'hidden': False}] * 2 + [done]
        lines = ''.join(json.dumps(event) + '\n' for event in events)
        return (f"import pathlib,subprocess\n"
                f"pathlib.Path({str(self.reporter)!r}).write_text({lines!r})\n"
                f"print('All tests passed!', flush=True)\n"
                f"subprocess.Popen([{str(browser)!r}, '{browser_seconds}'])\n"
                f"{then}\n")

    def patched_supervisor(self, patch):
        """A launcher that runs the production supervisor with `patch(module)` applied."""
        launcher = Path(self.temp.name) / 'launcher.py'
        launcher.write_text(
            'import importlib.util, sys, time\n'
            f'spec = importlib.util.spec_from_file_location("supervisor", {str(SCRIPT)!r})\n'
            'module = importlib.util.module_from_spec(spec)\n'
            'spec.loader.exec_module(module)\n'
            f'{patch}\n'
            'sys.exit(module.main())\n')
        return launcher

    def run_fixture(self, program, script=SCRIPT, **options):
        result = subprocess.run(self.command(program, script=script, **options),
                                capture_output=True, timeout=8)
        return result, json.loads((self.output / 'result.json').read_text())

    def events(self):
        return [json.loads(line) for line in (self.output / 'events.jsonl').read_text().splitlines()]

    def assert_clean(self, result):
        self.assertEqual(result['owned_processes_remaining'], [])
        self.assertTrue(result['stdout_eof'])
        self.assertTrue(result['stderr_eof'])
        for line in (self.output / 'processes.jsonl').read_text().splitlines():
            for row in json.loads(line)['processes']:
                try:
                    raw = Path('/proc', str(row['pid']), 'stat').read_text()
                except FileNotFoundError:
                    continue
                start = int(raw[raw.rindex(')') + 2:].split()[19])
                self.assertNotEqual(start, row['start_ticks'], 'Owned process survived supervisor exit')

    def test_real_exit_and_both_eofs_are_required_for_success(self):
        child, result = self.run_fixture(
            "import sys; print('2 tests passed.'); print('diagnostic', file=sys.stderr)")
        self.assertEqual(child.returncode, 0, child.stderr)
        self.assertTrue(result['passed'])
        self.assertEqual(result['cli_exit_code'], 0)
        self.assertFalse(result['forced_cleanup'])
        self.assert_clean(result)
        self.assertEqual((self.output / 'stdout.log').read_bytes(), b'2 tests passed.\n')
        self.assertEqual((self.output / 'stderr.log').read_bytes(), b'diagnostic\n')
        self.assertEqual(child.stdout, b'2 tests passed.\n')
        self.assertEqual(child.stderr, b'diagnostic\n')
        kinds = [event['event'] for event in self.events()]
        for kind in ['command_started', 'reporter_summary_observed', 'cli_exit',
                     'output_eof', 'owned_children_exited', 'supervisor_exit']:
            self.assertIn(kind, kinds)

    def test_mixed_pass_fail_summary_is_observed_and_stays_failure(self):
        child, result = self.run_fixture(
            "print('1 test passed, 1 failed.'); raise SystemExit(1)")
        self.assertEqual(child.returncode, 1, child.stderr)
        self.assertFalse(result['passed'])
        self.assertIn('reporter_summary_observed', [event['event'] for event in self.events()])
        self.assertEqual(child.stdout, b'1 test passed, 1 failed.\n')

    def test_caller_pipes_keep_their_blocking_mode_after_the_supervisor_exits(self):
        script = ("import os,subprocess,sys\n"
                  "os.set_blocking(2, False)\n"
                  f"subprocess.run({self.command('print(1)')!r}, stdout=sys.stdout, stderr=sys.stderr)\n"
                  "print(os.get_blocking(1), os.get_blocking(2))")
        done = subprocess.run([sys.executable, '-c', script], capture_output=True, timeout=8)
        self.assertEqual(done.stdout.split()[-2:], [b'True', b'False'], done.stderr)

    def test_stale_reporter_error_keeps_the_caller_stderr_blocking(self):
        self.reporter.write_text('{"type":"done","success":true}\n')
        script = ("import os,subprocess,sys\n"
                  f"subprocess.run({self.command('pass', reporter=True)!r}, stdout=sys.stdout, stderr=sys.stderr)\n"
                  "print(os.get_blocking(2))")
        done = subprocess.run([sys.executable, '-c', script], capture_output=True, timeout=8)
        self.assertEqual(done.stdout.split()[-1:], [b'True'], done.stderr)

    def test_stale_reporter_error_keeps_a_non_blocking_caller_stderr_non_blocking(self):
        self.reporter.write_text('{"type":"done","success":true}\n')
        script = ("import os,subprocess,sys\n"
                  "os.set_blocking(2, False)\n"
                  f"subprocess.run({self.command('pass', reporter=True)!r}, stdout=sys.stdout, stderr=sys.stderr)\n"
                  "print(os.get_blocking(2))")
        done = subprocess.run([sys.executable, '-c', script], capture_output=True, timeout=8)
        self.assertEqual(done.stdout.split()[-1:], [b'False'], done.stderr)

    def test_stale_reporter_error_cannot_delay_or_change_the_exit(self):
        self.reporter.write_text('{"type":"done","success":true}\n')
        full_read, full_write = os.pipe()
        os.set_blocking(full_write, False)
        try:
            while True:
                os.write(full_write, b'x' * 65536)
        except BlockingIOError:
            pass
        os.set_blocking(full_write, True)
        broken_read, broken_write = os.pipe()
        os.close(broken_read)
        try:
            for name, stderr in [('full pipe', full_write), ('broken pipe', broken_write)]:
                with self.subTest(name):
                    child = subprocess.run(self.command('pass', reporter=True),
                                           stdout=subprocess.DEVNULL, stderr=stderr, timeout=3)
                    self.assertEqual(child.returncode, 125)
        finally:
            for descriptor in (full_read, full_write, broken_write):
                os.close(descriptor)

    def test_stale_reporter_error_survives_a_non_utf8_path(self):
        self.reporter.parent.joinpath(os.fsdecode(b'bad\xff.jsonl')).write_text('{}\n')
        command = self.command('pass', reporter=True)
        command[command.index('--reporter-file') + 1] = str(self.reporter.parent / os.fsdecode(b'bad\xff.jsonl'))
        child = subprocess.run(command, capture_output=True, timeout=3)
        self.assertEqual(child.returncode, 125, child.stderr)
        self.assertIn(b'bad\\udcff.jsonl', child.stderr)

    def test_closed_stdout_cannot_redirect_the_echo_into_events(self):
        child = subprocess.run(
            self.command("print('echoed output')"),
            stdin=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=8,
            preexec_fn=lambda: os.close(1))
        self.assertEqual(child.returncode, 0, child.stderr)
        self.assertEqual((self.output / 'stdout.log').read_bytes(), b'echoed output\n')
        self.assertIn('supervisor_exit', [event['event'] for event in self.events()])

    def test_reporter_success_does_not_override_a_failing_exit(self):
        child, result = self.run_fixture("print('All tests passed!'); raise SystemExit(7)")
        self.assertEqual(child.returncode, 7, child.stderr)
        self.assertFalse(result['passed'])
        self.assertEqual(result['cli_exit_code'], 7)
        self.assertFalse(result['forced_cleanup'])
        self.assert_clean(result)

    def test_success_text_does_not_end_a_running_command(self):
        child, result = self.run_fixture(
            "import time; print('2 tests passed.', flush=True); time.sleep(5)", timeout=0.25)
        self.assertEqual(child.returncode, 124, child.stderr)
        self.assertEqual(result['failure_reason'], 'command_timeout')
        self.assertTrue(result['forced_cleanup'])
        self.assertFalse(result['passed'])
        self.assert_clean(result)

    def unread_consumer(self, stream):
        payload = b'0123456789abcdef' * 65536
        program = (
            f'import sys,time; sys.{stream}.buffer.write(b"0123456789abcdef" * 65536); '
            f'sys.{stream}.flush(); time.sleep(5)'
        )
        child = subprocess.Popen(self.command(program, timeout=0.5),
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            # wait(), unlike communicate(), leaves both downstream pipes unread.
            # Echo must drop output past the pipe capacity instead of blocking.
            child.wait(timeout=3)
            self.assertEqual(child.returncode, 124)
            result = json.loads((self.output / 'result.json').read_text())
            self.assertEqual(result['failure_reason'], 'command_timeout')
            self.assertTrue(result['forced_cleanup'])
            self.assertFalse(result['passed'])
            self.assertEqual((self.output / f'{stream}.log').read_bytes(), payload)
            self.assert_clean(result)
            forwarded = dict(zip(('stdout', 'stderr'), child.communicate(timeout=2)))
            other = 'stderr' if stream == 'stdout' else 'stdout'
            self.assertEqual(forwarded[other], b'')
            self.assertTrue(payload.startswith(forwarded[stream]))
            self.assertLess(len(forwarded[stream]), len(payload))
        finally:
            if child.poll() is None:
                child.kill()
            child.communicate(timeout=2)

    def test_unread_downstream_stdout_cannot_block_deadline_or_cleanup(self):
        self.unread_consumer('stdout')

    def test_unread_downstream_stderr_cannot_block_deadline_or_cleanup(self):
        self.unread_consumer('stderr')

    def test_cli_stalled_after_its_browser_exits_takes_the_reporter_result(self):
        for success, expected in [(True, 0), (False, 1)]:
            with self.subTest(success=success):
                shutil.rmtree(self.output, ignore_errors=True)
                self.reporter.unlink(missing_ok=True)
                child, result = self.run_fixture(self.browser_then(
                    {'type': 'done', 'success': success}, 0.05, 'import time; time.sleep(5)'),
                    reporter=True)
                self.assertEqual(child.returncode, expected, child.stderr)
                self.assertTrue(result['browser_close_stall'])
                self.assertEqual(result['reporter_tests'], 2)
                self.assertIsNone(result['failure_reason'])
                self.assertEqual(result['cli_exit_code'], 128 + signal.SIGTERM)
                self.assertIn(b'::warning::', child.stderr)
                self.assert_clean(result)
                kinds = [event['event'] for event in self.events()]
                self.assertLess(kinds.index('reporter_done'), kinds.index('browser_close_stall'))

    def test_cli_stall_keeps_failing_while_its_browser_runs(self):
        child, result = self.run_fixture(self.browser_then(
            {'type': 'done', 'success': True}, 5, 'import time; time.sleep(5)'),
            timeout=1.5, reporter=True)
        self.assertEqual(child.returncode, 124, child.stderr)
        self.assertEqual(result['failure_reason'], 'command_timeout')
        self.assertFalse(result['browser_close_stall'])
        self.assert_clean(result)

    def test_cli_stall_without_a_settled_reporter_result_keeps_failing(self):
        for done in [{'type': 'done', 'success': None}, {'type': 'start'}]:
            with self.subTest(done=done):
                shutil.rmtree(self.output, ignore_errors=True)
                self.reporter.unlink(missing_ok=True)
                child, result = self.run_fixture(self.browser_then(
                    done, 0.05, 'import time; time.sleep(5)'), timeout=1.5, reporter=True)
                self.assertEqual(child.returncode, 124, child.stderr)
                self.assertFalse(result['browser_close_stall'])
                self.assert_clean(result)

    def test_reporter_result_never_replaces_a_real_cli_exit(self):
        child, result = self.run_fixture(self.browser_then(
            {'type': 'done', 'success': True}, 0.05, 'import time; time.sleep(.1); raise SystemExit(7)'),
            reporter=True, shutdown=1)
        self.assertEqual(child.returncode, 7, child.stderr)
        self.assertEqual(result['cli_exit_code'], 7)
        self.assertTrue(result['reporter_success'])
        self.assert_clean(result)

    def test_the_supervisor_waits_post_done_seconds_before_recovering(self):
        child, result = self.run_fixture(self.browser_then(
            {'type': 'done', 'success': True}, 0.05, 'import time; time.sleep(.5); raise SystemExit(7)'),
            reporter=True, post_done=2, shutdown=1)
        self.assertEqual(child.returncode, 7, child.stderr)
        self.assertEqual(result['cli_exit_code'], 7)
        self.assertFalse(result['browser_close_stall'])
        self.assert_clean(result)

    def test_recovery_happens_no_earlier_than_post_done_seconds_after_done(self):
        child, result = self.run_fixture(self.browser_then(
            {'type': 'done', 'success': True}, 0.05, 'import time; time.sleep(5)'),
            reporter=True, post_done=0.6)
        self.assertEqual(child.returncode, 0, child.stderr)
        self.assertTrue(result['browser_close_stall'])
        at = {event['event']: event['elapsed_seconds'] for event in self.events()}
        # Events are rounded to milliseconds, so compare at that precision.
        self.assertGreaterEqual(round(at['browser_close_stall'] - at['reporter_done'], 3), 0.6)

    def test_post_done_window_starts_after_a_slow_reporter_poll(self):
        launcher = self.patched_supervisor(
            'poll = module.ReporterEvents.poll\n'
            'def slow_poll(self):\n'
            '    done = poll(self)\n'
            '    if done:\n'
            '        time.sleep(0.2)\n'
            '    return done\n'
            'module.ReporterEvents.poll = slow_poll')
        child, result = self.run_fixture(self.browser_then(
            {'type': 'done', 'success': True}, 0.05, 'import time; time.sleep(5)'),
            reporter=True, post_done=0.6, script=launcher)
        self.assertEqual(child.returncode, 0, child.stderr)
        self.assertTrue(result['browser_close_stall'])
        at = {event['event']: event['elapsed_seconds'] for event in self.events()}
        self.assertGreaterEqual(round(at['browser_close_stall'] - at['reporter_done'], 3), 0.6)

    def test_leftover_owned_processes_after_a_recovered_stall_exit_125(self):
        launcher = self.patched_supervisor('module.deliver = lambda row, number: False')
        child, result = self.run_fixture(self.browser_then(
            {'type': 'done', 'success': True}, 0.05, 'import time; time.sleep(2)'),
            reporter=True, script=launcher)
        self.assertEqual(child.returncode, 125, child.stderr)
        self.assertTrue(result['browser_close_stall'])
        self.assertNotEqual(result['owned_processes_remaining'], [])
        self.assertFalse(result['passed'])

    def test_a_surviving_process_alone_fails_a_recovered_stall(self):
        launcher = self.patched_supervisor('module.deliver = lambda row, number: False')
        child, result = self.run_fixture(self.browser_then(
            {'type': 'done', 'success': True}, 0.05,
            'import os,time; os.close(1); os.close(2); time.sleep(2)'),
            reporter=True, script=launcher)
        self.assertEqual(child.returncode, 125, child.stderr)
        self.assertTrue(result['browser_close_stall'])
        self.assertTrue(result['stdout_eof'] and result['stderr_eof'])
        self.assertNotEqual(result['owned_processes_remaining'], [])

    def test_missing_output_eof_after_a_recovered_stall_exits_125(self):
        lingerer = Path(self.temp.name) / 'lingerer'
        lingerer.write_text(f'#!{sys.executable}\nimport sys,time; time.sleep(2)\n')
        lingerer.chmod(0o755)
        launcher = self.patched_supervisor(
            'table = module.process_table\n'
            'module.process_table = lambda: {pid: row for pid, row in table().items()\n'
            "                                 if row['comm'] != 'lingerer'}")
        child, result = self.run_fixture(self.browser_then(
            {'type': 'done', 'success': True}, 0.05,
            f"subprocess.Popen([{str(lingerer)!r}]); import time; time.sleep(2)"),
            reporter=True, script=launcher)
        self.assertEqual(child.returncode, 125, child.stderr)
        self.assertTrue(result['browser_close_stall'])
        self.assertEqual(result['owned_processes_remaining'], [])
        self.assertFalse(result['stdout_eof'] and result['stderr_eof'])
        self.assertFalse(result['passed'])

    def test_a_stale_reporter_file_does_not_start_the_command(self):
        self.reporter.write_text('{"type":"done","success":true}\n')
        child = subprocess.run(self.command('raise SystemExit(0)', reporter=True),
                               capture_output=True, timeout=3)
        self.assertEqual(child.returncode, 125)
        self.assertIn(str(self.reporter).encode(), child.stderr)
        self.assertIn(b'Stale reporter file', child.stderr)
        self.assertFalse(self.output.exists())

    def test_cli_exit_is_distinct_from_inherited_pipe_eof(self):
        child, result = self.run_fixture(
            "import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time; time.sleep(5)'])")
        self.assertEqual(child.returncode, 125, child.stderr)
        self.assertEqual(result['cli_exit_code'], 0)
        self.assertEqual(result['failure_reason'], 'shutdown_timeout')
        self.assertTrue(result['forced_cleanup'])
        self.assert_clean(result)
        events = self.events()
        exited = next(i for i, event in enumerate(events) if event['event'] == 'cli_exit')
        eof = [i for i, event in enumerate(events) if event['event'] == 'output_eof']
        self.assertTrue(all(i > exited for i in eof))

    def test_closed_pipes_do_not_hide_a_surviving_child(self):
        child, result = self.run_fixture(
            "import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time; time.sleep(5)'],"
            "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)")
        self.assertEqual(child.returncode, 125, child.stderr)
        self.assertEqual(result['cli_exit_code'], 0)
        self.assertEqual(result['failure_reason'], 'shutdown_timeout')
        self.assertTrue(result['forced_cleanup'])
        self.assert_clean(result)

    def test_subreaper_tracks_children_that_leave_the_command_session(self):
        child, result = self.run_fixture(
            "import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time; time.sleep(5)'],"
            "start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)")
        self.assertEqual(child.returncode, 125, child.stderr)
        self.assertTrue(result['forced_cleanup'])
        self.assert_clean(result)
        snapshots = [json.loads(line) for line in (self.output / 'processes.jsonl').read_text().splitlines()]
        leader = self.events()[0]['pid']
        self.assertTrue(any(row['pid'] != leader and row['sid'] != leader
                            for shot in snapshots for row in shot['processes']))

    def test_natural_child_shutdown_within_the_grace_period_needs_no_cleanup(self):
        child, result = self.run_fixture(
            "import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time; time.sleep(.15)'])",
            shutdown=1)
        self.assertEqual(child.returncode, 0, child.stderr)
        self.assertFalse(result['forced_cleanup'])
        self.assert_clean(result)

    def test_term_resistant_command_is_killed_and_stays_failure(self):
        child, result = self.run_fixture(
            'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(5)',
            timeout=0.25)
        self.assertEqual(child.returncode, 124, child.stderr)
        self.assertEqual(result['cli_exit_code'], 137)
        self.assertTrue(result['forced_cleanup'])
        self.assert_clean(result)
        self.assertIn(9, [event['signal'] for event in self.events()
                          if event['event'] == 'cleanup_signal'])

    def test_cleanup_never_targets_an_unrelated_process(self):
        peer = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(5)'],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            child, result = self.run_fixture('import time; time.sleep(5)', timeout=0.25)
            self.assertEqual(child.returncode, 124, child.stderr)
            self.assertIsNone(peer.poll())
            self.assert_clean(result)
        finally:
            peer.terminate()
            peer.wait(timeout=3)

    def test_term_interrupt_stays_failure_and_cleans_children(self):
        child = subprocess.Popen(self.command('import time; time.sleep(5)'),
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            path = self.output / 'events.jsonl'
            if path.exists() and 'command_started' in path.read_text():
                break
            time.sleep(0.01)
        child.send_signal(signal.SIGTERM)
        stdout, stderr = child.communicate(timeout=5)
        self.assertEqual(child.returncode, 143, (stdout, stderr))
        result = json.loads((self.output / 'result.json').read_text())
        self.assertFalse(result['passed'])
        self.assertTrue(result['forced_cleanup'])
        self.assert_clean(result)

    def test_process_receipts_exclude_command_arguments_and_environment(self):
        marker = 'synthetic-sensitive-argument'
        command = self.command('import time; time.sleep(.15)') + [marker]
        child = subprocess.run(command, capture_output=True, timeout=8,
                               env={**os.environ, 'SYNTHETIC_SECRET': marker})
        self.assertEqual(child.returncode, 0, child.stderr)
        for name in ['events.jsonl', 'processes.jsonl', 'result.json']:
            self.assertNotIn(marker, (self.output / name).read_text())

    def test_invalid_deadlines_do_not_start_the_command(self):
        for seconds in ['nan', 'inf', '0', '-1']:
            command = self.command('raise SystemExit(0)')
            command[command.index('--timeout-seconds') + 1] = seconds
            child = subprocess.run(command, capture_output=True, timeout=3)
            self.assertNotEqual(child.returncode, 0)
            self.assertFalse(self.output.exists())

    def test_output_limit_is_a_failure_even_when_the_command_would_exit_zero(self):
        child, result = self.run_fixture("import sys; sys.stdout.buffer.write(b'x' * (9 * 1024 * 1024))")
        self.assertEqual(child.returncode, 125, child.stderr)
        self.assertEqual(result['failure_reason'], 'output_limit')
        self.assertFalse(result['passed'])
        self.assertLessEqual((self.output / 'stdout.log').stat().st_size, 8 * 1024 * 1024)
        self.assert_clean(result)

    def test_launch_error_keeps_evidence_without_the_secret_bearing_path(self):
        command = self.command('unused')
        command[command.index('--') + 1:] = ['/synthetic-sensitive-path/not-an-executable']
        child = subprocess.run(command, capture_output=True, timeout=3)
        self.assertEqual(child.returncode, 125)
        result = json.loads((self.output / 'result.json').read_text())
        self.assertIsNone(result['cli_exit_code'])
        self.assertEqual(result['failure_reason'], 'supervisor_error')
        self.assertFalse(result['passed'])
        for path in self.output.iterdir():
            self.assertNotIn('synthetic-sensitive-path', path.read_text())


class WorkflowTest(unittest.TestCase):
    def test_post_done_default_stays_thirty_seconds_for_every_workflow_caller(self):
        source = SCRIPT.read_text()
        self.assertIn("'--post-done-seconds', type=positive_seconds, default=30)", source)
        self.assertIn('reporter_file=None, post_done=30)', source)
        for workflow in (ROOT / '.github/workflows').glob('*.yml'):
            self.assertNotIn('--post-done-seconds', workflow.read_text(), workflow.name)

    def test_model_store_keeps_failure_gates_and_uploads_before_job_cancellation(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        lane = workflow.split('\n  model-store:\n', 1)[1].split('\n  analyze:\n', 1)[0]
        chrome = lane.index('name: Test on Chrome with bounded shutdown diagnostics')
        upload = lane.index('name: Upload Chrome process and phase diagnostics')
        package_gate = lane.index('name: Check the lane leaves the package unchanged')
        self.assertLess(chrome, upload)
        self.assertLess(upload, package_gate)
        self.assertIn('if: always()', lane[upload:package_gate])
        self.assertIn('actions/upload-artifact@v7', lane[upload:package_gate])
        self.assertIn('--timeout-seconds 180 --', lane[chrome:upload])
        self.assertEqual(lane.count('dart test -p chrome test/model_store_web_test.dart'), 1)
        self.assertNotIn('flutter test --platform chrome', lane)
        self.assertIn('timeout-minutes: 20', lane)
        self.assertIn('flutter-version: 3.47.1', lane)
        self.assertNotIn('continue-on-error', lane)
        self.assertNotIn('|| true', lane)

    def test_web_chat_chrome_tests_take_only_their_own_reporter_result(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        lane = workflow.split('\n  web-chat-contract:\n', 1)[1].split('\n  deploy-chat-app:\n', 1)[0]
        chrome = lane.index('name: Run chat app Chrome tests with bounded shutdown')
        upload = lane.index('name: Upload chat app Chrome diagnostics')
        restore = lane.index('name: Restore the chat app pubspec')
        self.assertLess(lane.index('run: flutter test test test_vm'), chrome)
        self.assertLess(chrome, upload)
        self.assertLess(upload, restore)
        step = lane[chrome:upload]
        self.assertIn('python3 ../../tool/ci/supervise_chrome_test.py', step)
        self.assertIn('--timeout-seconds 600 --', step)
        self.assertNotIn('--post-done-seconds', step)
        report = '$RUNNER_TEMP/chat-app-chrome/reporter.jsonl'
        self.assertIn(f'--reporter-file "{report}"', step)
        self.assertIn(f'--file-reporter "json:{report}"', step)
        self.assertLess(step.index('--reporter-file'), step.index(' --\n'))
        self.assertGreater(step.index('--file-reporter'), step.index('flutter test --platform chrome'))
        self.assertEqual(lane.count('flutter test --platform chrome'), 1)
        self.assertIn('if: always()', lane[upload:restore])
        self.assertIn('actions/upload-artifact@v7', lane[upload:restore])
        self.assertIn('path: ${{ runner.temp }}/chat-app-chrome', lane[upload:restore])
        self.assertNotIn('continue-on-error', lane)
        self.assertNotIn('|| true', lane)


if __name__ == '__main__':
    unittest.main()
