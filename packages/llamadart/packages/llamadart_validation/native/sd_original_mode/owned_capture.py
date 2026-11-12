"""Owned POSIX capture adapted from the independently reviewed SD metadata runner.

Only the operator's bound fixture entrypoints, data-only phase workers and two
scoped Git metadata builtins are admitted. This is not a general command runner.
Signal masking/teardown/reaping/atomic terminal receipts preserve ownership.
"""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parent


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def stage_records(path):
    rows = []
    for line in path.read_bytes().splitlines():
        if line.startswith(b'SD24_STAGE '):
            try:
                row = json.loads(line[len(b'SD24_STAGE '):])
                if isinstance(row, dict):
                    rows.append(row)
            except (ValueError, UnicodeError):
                pass
    return rows


class CaptureInterrupted(BaseException):
    def __init__(self, signum: int):
        self.signum = signum
        super().__init__(signal.Signals(signum).name)


@contextlib.contextmanager
def capture_signals(state: dict):
    watched = {signal.SIGINT, signal.SIGTERM}
    # A signal must not run its old handler between fork and Popen assignment.
    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, watched)
    previous_handlers = {}
    def received(signum, frame):
        # Defer interruption to a supervised checkpoint. Repeated signals cannot
        # interrupt group cleanup, reaping or the terminal receipt.
        state['signals'].append(signum)
    try:
        for signum in watched:
            previous_handlers[signum] = signal.signal(signum, received)
        yield previous_mask
    finally:
        signal.pthread_sigmask(signal.SIG_BLOCK, watched)
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)


def child_exited_unreaped(child) -> bool:
    # Reserve the leader PID until abnormal-path group teardown or normal reap.
    return os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is not None


def capture(command: list[str], output: Path, identity: dict, *, seconds: float = 177,
            observation_seconds: float = 45, max_bytes: int = 2 << 20,
            active_deadline: float | None = None, total_deadline: float | None = None) -> dict:
    if not command or not Path(command[0]).is_absolute():
        raise ValueError('absolute owned executable required')
    if not (0 < seconds <= 177 and 0 < observation_seconds <= 45 and 0 < max_bytes <= 2 << 20):
        raise ValueError('capture bounds cannot be widened')
    if (active_deadline is None) != (total_deadline is None):
        raise ValueError('both shared deadlines are required')
    if active_deadline is not None and active_deadline > total_deadline:
        raise ValueError('shared deadline order is invalid')
    if signal.getitimer(signal.ITIMER_REAL)[0] or signal.SIGALRM in signal.sigpending():
        raise ValueError('active or pending foreign SIGALRM refused before launch')
    output.mkdir(parents=True, exist_ok=False)
    stdout, stderr = output / 'stdout.log', output / 'stderr.log'
    capture_receipt = output / 'capture.json'
    started = time.monotonic()
    local_active_end = started + seconds
    local_total_end = started + seconds + 3
    effective_active_end = min(local_active_end, active_deadline) if active_deadline is not None else local_active_end
    effective_total_end = min(local_total_end, total_deadline) if total_deadline is not None else local_total_end
    shared_timed_out = False
    timed_out = limited = reaped = completed = False
    child = None
    error = None
    cleanup_errors = []
    state = {'signals': []}
    load_seen = None
    load_observation = None
    with capture_signals(state) as previous_mask:
        try:
            with stdout.open('wb') as out, stderr.open('wb') as err:
                try:
                    try:
                        if time.monotonic() >= effective_active_end:
                            timed_out = True
                            shared_timed_out = active_deadline is not None
                            raise TimeoutError('owned launch deadline already expired')
                        child = subprocess.Popen(
                            command,
                            stdout=out, stderr=err, start_new_session=True)
                    finally:
                        # Pending termination is delivered only after registration.
                        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
                    while True:
                        if state['signals']:
                            raise CaptureInterrupted(state['signals'][0])
                        now = time.monotonic()
                        timed_out = now >= effective_active_end
                        shared_timed_out = active_deadline is not None and now >= active_deadline
                        limited = (stdout.stat().st_size > max_bytes or
                                   stderr.stat().st_size > max_bytes)
                        stages = stage_records(stdout)
                        if load_seen is None and any(s.get('stage') == 'load_begin' for s in stages):
                            load_seen = time.monotonic()
                        if load_seen is not None and load_observation is None and time.monotonic() - load_seen >= observation_seconds:
                            ends = [s for s in stages if s.get('stage') == 'load_end']
                            load_observation = {'at_seconds': observation_seconds, 'pending': not ends,
                                                'reported_load_ms': ends[-1].get('loadMs') if ends else None}
                        if timed_out or limited:
                            break
                        if child_exited_unreaped(child):
                            completed = True
                            break
                        time.sleep(0.02)
                finally:
                    if child is not None:
                        # Admitted fixtures/workers do not spawn children; the two
                        # scoped Git builtins disable hooks/fsmonitor/submodules.
                        # Abnormal paths kill the owned group before reaping.
                        # macOS may refuse a signal to an already-exited group.
                        if not completed:
                            try:
                                os.killpg(child.pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass
                            except BaseException as failure:
                                cleanup_errors.append(type(failure).__name__)
                        try:
                            remaining = max(0, min(3, effective_total_end - time.monotonic()))
                            child.wait(timeout=remaining)
                            reaped = child.returncode is not None
                        except BaseException as failure:
                            cleanup_errors.append(type(failure).__name__)
        except BaseException as failure:
            error = failure
        finally:
            raw = {}
            for path in (stdout, stderr):
                try:
                    size = path.stat().st_size
                    limited = limited or size > max_bytes
                    raw[path.name] = {'sha256': digest(path), 'bytes': size}
                except BaseException as failure:
                    raw[path.name] = {'capture_error': type(failure).__name__}
                    cleanup_errors.append(type(failure).__name__)
            if load_observation is None:
                ends = [s for s in stage_records(stdout) if s.get('stage') == 'load_end'] if stdout.exists() else []
                load_observation = {'at_seconds': observation_seconds, 'pending': None,
                                    'reported_load_ms': ends[-1].get('loadMs') if ends else None,
                                    'note': 'child completed before observation or never reached load'}
            record = {
                'schema': 1, 'qualified': False, 'model_inference': identity.get('model_inference', False),
                'scope': 'owned raw capture; image acceptance is graded separately',
                'pid': child.pid if child is not None else None,
                'exit': child.returncode if child is not None else None,
                'timed_out': timed_out, 'capture_limit_exceeded': limited,
                'deadline_seconds': seconds, 'cleanup_deadline_seconds': 3,
                'case_deadline_seconds': seconds + 3,
                'shared_active_deadline': active_deadline, 'shared_total_deadline': total_deadline,
                'shared_deadline_reached': shared_timed_out,
                'leader_reaped': reaped, 'cleanup_errors': cleanup_errors,
                'failure_type': type(error).__name__ if error else None,
                'received_signals': state['signals'],
                'elapsed_seconds': time.monotonic() - started,
                'identity': identity, 'command': command,
                'load_observation': load_observation,
                'raw': raw,
            }
            # The failed/interrupted transport is durable before protocol grading.
            temporary = output / 'capture.partial'
            def save():
                temporary.write_text(json.dumps(record, indent=2) + '\n')
                os.replace(temporary, capture_receipt)
            save()
            if state['signals']:
                if error is None:
                    error = CaptureInterrupted(state['signals'][0])
                    record['failure_type'] = type(error).__name__
            save()
    if error is not None:
        raise error
    return record
