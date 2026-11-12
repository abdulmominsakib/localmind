#!/usr/bin/env python3
"""Reviewed default-native consumer/AOT qualifier. Heavy execution is opt-in.

The expected tag is an assertion on committed source, never a hook selector.
A native2 success is explicitly pipeline-only. No publication/deployment occurs.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True

import verify as v
from owned_process import WindowsJob, CancellationGuard, Cancelled

FIXTURE = Path(__file__).resolve().parent


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def command(argv, *, cwd, env, timeout, log):
    """Register before initializing Popen; own every catchable cancellation."""
    argv = [str(value) for value in argv]
    v.require(timeout > 0 and log is not None, 'owned command requires bounded timeout and receipt')
    started = time.monotonic()
    receipt = {'argv': argv, 'cwd': str(cwd), 'timeoutSeconds': timeout,
               'cleanupComplete': False}
    process = job = failure = traceback = None
    with CancellationGuard() as cancellation:
        try:
            with Path(str(log) + '.stdout.log').open('wb') as stdout, Path(str(log) + '.stderr.log').open('wb') as stderr:
                # The handler records signals until both the object and PID/job
                # are registered. The object exists before __init__ can spawn.
                with cancellation.deferred():
                    job = WindowsJob() if os.name == 'nt' else None
                    options = ({'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP | 0x4}
                               if os.name == 'nt' else {'start_new_session': True})
                    process = subprocess.Popen.__new__(subprocess.Popen)
                    process.__init__(argv, cwd=cwd, env=env, stdout=stdout, stderr=stderr, **options)
                    receipt['pid'] = process.pid
                    if job is not None:
                        job.attach_and_resume(process)
                receipt['exitCode'] = cancellation.wait(process, timeout)
            v.require(receipt['exitCode'] == 0, 'child failed: ' + Path(argv[0]).name)
        except BaseException as error:
            failure, traceback = error, error.__traceback__
        finally:
            with cancellation.deferred(deliver=False):
                cleanup_errors = []
                pid = getattr(process, 'pid', None)
                if pid is not None:
                    receipt['pid'] = pid
                if job is not None:
                    try:
                        job.close()  # Includes zero-ActiveProcesses proof.
                    except BaseException as error:
                        cleanup_errors.append(error)
                elif pid is not None:
                    try:
                        os.killpg(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    except BaseException as error:
                        cleanup_errors.append(error)
                if pid is not None:
                    try:
                        if process.poll() is None:
                            process.kill()
                        process.wait(timeout=30)
                        receipt['reapedExitCode'] = process.returncode
                    except BaseException as error:
                        cleanup_errors.append(error)
                receipt['cleanupComplete'] = not cleanup_errors
                if cleanup_errors:
                    receipt['cleanupErrors'] = [f'{type(error).__name__}: {error}' for error in cleanup_errors]
                if failure is None:
                    if cancellation.signals:
                        failure = Cancelled(cancellation.signals[0])
                    elif cleanup_errors:
                        failure = cleanup_errors[0]
                if failure is not None:
                    receipt.update({'failureType': type(failure).__name__, 'failure': str(failure)})
                receipt['cancelledSignals'] = cancellation.signals
                receipt['elapsedSeconds'] = time.monotonic() - started
                write_json(str(log) + '.command.json', receipt)
        def record_late_cancellation(signals):
            receipt['cancelledSignals'] = list(signals)
            receipt.setdefault('failureType', 'Cancelled')
            receipt.setdefault('failure', str(Cancelled(signals[0])))
            write_json(str(log) + '.command.json', receipt)
        cancellation.on_cancel = record_late_cancellation
        if failure is not None:
            raise failure.with_traceback(traceback)
        cancellation.checkpoint()
        return Path(str(log) + '.stdout.log').read_text(encoding='utf-8')


def git(root, *args, log=None):
    # A missing receipt is refusal before creation, including preflight Git.
    v.require(log is not None, 'git requires a bounded owned command receipt')
    environment = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_OPTIONAL_LOCKS='0')
    return command(['git', '-C', str(root), *args], cwd=root, env=environment,
                   timeout=60, log=log).encode('utf-8')


def pubspec(source):
    # JSON strings are valid YAML scalars, including Windows backslashes.
    return ('name: default_native_consumer\npublish_to: none\nversion: 0.0.0\n'
        'environment:\n  sdk: ">=3.13.1 <4.0.0"\ndependencies:\n'
        '  llamadart:\n    path: ' + json.dumps(str(source)) + '\n'
        '  crypto: ^3.0.0\n  ffi: ^2.1.0\n'
        'hooks:\n  user_defines:\n    llamadart:\n'
        '      llamadart_native_runtimes: [llama_cpp]\n')


def clean_environment(parent, temporary, pub_cache, *, sdk=False):
    v.reject_overrides(parent)
    keep = ('SystemRoot', 'WINDIR', 'COMSPEC', 'PATHEXT', 'HOME', 'USERPROFILE',
            'LOCALAPPDATA', 'APPDATA', 'LANG', 'LC_ALL', 'SSL_CERT_FILE', 'SSL_CERT_DIR')
    result = {key: parent[key] for key in keep if key in parent}
    if os.name == 'nt':
        system = Path(parent['SystemRoot'])
        result['PATH'] = os.pathsep.join((str(system / 'System32'), str(system)))
    else:
        result['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin'
    # Build tools may need the pinned SDK on PATH; AOT never receives it.
    if sdk:
        result['PATH'] = str(sdk) + os.pathsep + result['PATH']
    for key in ('TMPDIR', 'TMP', 'TEMP'):
        result[key] = str(temporary)
    result['PUB_CACHE'] = str(pub_cache)
    result['CI'] = 'true'
    return result


def sdk_paths(environment):
    flutter_root = environment.get('FLUTTER_ROOT')
    if flutter_root:
        flutter_root = Path(flutter_root).resolve()
    else:
        flutter = shutil.which('flutter', path=environment.get('PATH'))
        v.require(flutter is not None, 'pinned Flutter SDK missing')
        flutter_root = Path(flutter).resolve().parent.parent
    dart = flutter_root / 'bin' / 'cache' / 'dart-sdk' / 'bin' / ('dart.exe' if os.name == 'nt' else 'dart')
    flutter = flutter_root / 'bin' / ('flutter.bat' if os.name == 'nt' else 'flutter')
    v.require(dart.is_file() and flutter.is_file(), 'pinned Flutter/Dart SDK incomplete')
    return flutter_root, flutter, dart


def plan(args):
    root = Path(args.core_root).absolute()
    output = Path(args.output).absolute()
    v.require(re.fullmatch('[a-f0-9]{40}', args.expected_core_sha), 'expected-core-sha must be full lowercase SHA')
    v.no_links(root)
    v.no_links(output)
    v.require(not output.exists(), 'output must be a fresh nonexistent directory')
    v.require(not v.inside(output, root) and not v.inside(root, output), 'output and core source roots must be separate')
    v.reject_overrides(os.environ)
    pin_source = (root / 'lib/src/hook/native_release_pins.dart').read_text(encoding='utf-8')
    # Dry-run deliberately accepts either target without executing host/SDK discovery.
    checksums = {target: v.pins(pin_source, args.expected_native_tag, target)
                 for target in ('macos-arm64', 'windows-x64')}
    v.require((root / '.flutter-version').read_text().strip() == '3.47.1', 'unreviewed Flutter SDK pin')
    return root, output, checksums


def seal_terminal(output, terminal):
    terminal['evidenceInventory'] = v.inventory(output / 'logs')
    write_json(output / 'terminal.json', terminal)
    evidence = v.inventory(output)
    evidence.pop('manifest.json', None)
    write_json(output / 'manifest.json', {'schemaVersion': 1,
        'files': evidence, 'terminalSha256': v.sha256(output / 'terminal.json')})
    v.verify_seal(output)


def invalidate_cancelled_receipt(output, tag, signals):
    receipt = output / 'terminal.json'
    if receipt.exists():
        terminal = json.loads(receipt.read_text(encoding='utf-8'))
        terminal.update({'completed': False, **v.scope(tag, False),
            'cancelledSignals': list(signals)})
        terminal.setdefault('failureType', 'Cancelled')
        terminal.setdefault('failure', str(Cancelled(signals[0])))
        seal_terminal(output, terminal)


def qualify(args):
    with CancellationGuard() as cancellation:
        return _qualify(args, cancellation)


def _qualify(args, cancellation):
    root, output, checksums = plan(args)
    cancellation.checkpoint()
    if args.dry_run:
        print(json.dumps({'dryRun': True, 'coreRoot': str(root), 'expectedCoreSha': args.expected_core_sha,
            'expectedNativeTagVerificationOnly': args.expected_native_tag,
            'output': str(output), 'operations': ['verify clean exact H and SDK pins',
                'export tracked H; ordinary hooks.runtimes=[llama_cpp]', 'public JIT CPU0 baseline/active/reload/reuse/dispose',
                'dart build cli -o build/default -t consumer.dart', 'copy build/default/bundle wholly outside source/app roots',
                'execute copied bundle/bin/consumer from empty CWD/system PATH',
                'bind actual providers and symbol owners to committed public hook archive checksums',
                'seal complete before/after source and bundle inventories'],
            **v.scope(args.expected_native_tag, False)}, indent=2))
        return
    system = platform.system()
    target = {('Darwin', 'arm64'): 'macos-arm64', ('Windows', 'AMD64'): 'windows-x64',
              ('Windows', 'x86_64'): 'windows-x64'}.get((system, platform.machine()))
    v.require(target is not None, 'supported qualification hosts: macOS arm64 or Windows x64')
    output.mkdir()
    logs = output / 'logs'; logs.mkdir()
    temporary = output / 'temp'; temporary.mkdir()
    pub_cache = output / 'pub-cache'; pub_cache.mkdir()
    files = source_before = None
    terminal = {'schemaVersion': 1, 'completed': False, 'expectedCoreSha': args.expected_core_sha,
                'target': target, 'model': {'bytes': v.MODEL_BYTES, 'sha256': v.MODEL_SHA256},
                **v.scope(args.expected_native_tag, False)}
    # Register a receipt callback only after this invocation owns fresh output.
    cancellation.on_cancel = lambda signals: invalidate_cancelled_receipt(
        output, args.expected_native_tag, signals)

    def run_command(*arguments, **options):
        cancellation.checkpoint()
        return command(*arguments, **options)

    def run_git(*arguments, **options):
        cancellation.checkpoint()
        return git(*arguments, **options)

    try:
        v.require(run_git(root, 'rev-parse', 'HEAD', log=logs / 'git-head').decode().strip() == args.expected_core_sha, 'reviewed source SHA mismatch')
        v.require(not run_git(root, 'status', '--porcelain=v1', '--untracked-files=normal', log=logs / 'git-clean-before').strip(), 'reviewed source is dirty')
        v.require(FIXTURE == root / 'test/fixtures/native_default_consumer_qualification',
                  'driver must run from the reviewed core checkout')
        files = [name.decode('utf-8') for name in run_git(root, 'ls-files', '-z', log=logs / 'git-files').split(b'\0') if name]
        v.require(all(not name.startswith('/') and '..' not in Path(name).parts for name in files), 'unsafe source inventory')
        source_before = v.inventory(root, files)
        v.require(all(row['kind'] == 'file' for row in source_before.values()), 'source must contain only regular tracked files')
        model = Path(args.model).absolute()
        v.no_links(model)
        v.require(model.is_file() and model.stat().st_size == v.MODEL_BYTES
                  and v.sha256(model) == v.MODEL_SHA256, 'fixed Qwen model checksum/size mismatch')
        flutter_root, flutter, dart = sdk_paths(os.environ)
        environment = clean_environment(os.environ, temporary, pub_cache, sdk=dart.parent)
        write_json(output / 'source-before.json', source_before)
        # Invoke the pinned Dart directly. Flutter version is read from its
        # machine-readable pinned SDK version file, avoiding shell/.bat dispatch.
        flutter_version = json.loads((flutter_root / 'bin/cache/flutter.version.json').read_text(encoding='utf-8'))
        v.require(flutter_version.get('frameworkVersion') == '3.47.1'
                  and flutter_version.get('dartSdkVersion', '').split()[0] == '3.13.1', 'Flutter/Dart version pin mismatch')
        dart_version = run_command([dart, '--version'], cwd=output, env=environment, timeout=60, log=logs / 'dart-version')
        # Dart writes version to stdout on the pinned SDK; retain stderr too.
        version_text = dart_version + (logs / 'dart-version.stderr.log').read_text()
        v.require('Dart SDK version: 3.13.1 ' in version_text, 'Dart executable version mismatch')
        terminal['sdk'] = {'flutterRoot': str(flutter_root), 'dart': str(dart), 'version': flutter_version}
        source = output / 'source'; source.mkdir()
        for name in files:
            cancellation.checkpoint()
            destination = source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / name, destination)
        v.unchanged(source_before, v.inventory(source, files), 'exported reviewed source')
        app = output / 'app'; app.mkdir()
        (app / 'pubspec.yaml').write_text(pubspec(source), encoding='utf-8')
        for name in ('consumer.dart', 'providers.dart', 'passive_modules.dart'):
            # Read the reviewed exported fixture, not an unrelated checkout.
            shutil.copy2(source / 'test/fixtures/native_default_consumer_qualification' / name, app / name)
        run_command([dart, 'pub', 'get'], cwd=app, env=environment, timeout=600, log=logs / 'pub-get')
        run_command([dart, 'analyze', '--fatal-infos', 'consumer.dart', 'providers.dart', 'passive_modules.dart'],
                cwd=app, env=environment, timeout=120, log=logs / 'analyze')
        jit_stdout = run_command([dart, 'run', 'consumer.dart', model], cwd=app, env=environment,
                             timeout=900, log=logs / 'jit')
        jit_result = v.public_result(jit_stdout)
        jit_modules, jit_registry = v.native_modules(jit_stdout, target)
        v.query_result(jit_result, jit_modules, args.expected_native_tag)
        run_command([dart, 'build', 'cli', '-o', 'build/default', '-t', 'consumer.dart'],
                cwd=app, env=environment, timeout=600, log=logs / 'build')
        bundle = app / 'build/default/bundle'
        distributed = output / 'distributed'
        bundle_before = v.copy_bundle(bundle, distributed, (root, source, app))
        write_json(output / 'bundle-before.json', bundle_before)
        empty_cwd = output / 'empty-cwd'; empty_cwd.mkdir()
        cwd_before = v.inventory(empty_cwd)
        executable = distributed / 'bin' / ('consumer.exe' if system == 'Windows' else 'consumer')
        v.require(executable.is_file(), 'SDK CLI executable missing in complete bundle')
        aot_env = clean_environment(os.environ, temporary, pub_cache)
        aot_stdout = run_command([executable, model], cwd=empty_cwd, env=aot_env,
                             timeout=900, log=logs / 'aot')
        v.unchanged(cwd_before, v.inventory(empty_cwd), 'empty execution CWD')
        aot_result = v.public_result(aot_stdout)
        aot_modules, aot_registry = v.native_modules(aot_stdout, target)
        v.query_result(aot_result, aot_modules, args.expected_native_tag)
        cache = source / '.dart_tool/llamadart/native_bundles_v2'
        acquired, members = v.archive_members(cache, args.expected_native_tag, target, checksums[target])
        jit_bound = v.bind_providers(jit_modules, members, 'windows' if system == 'Windows' else 'macos', output)
        aot_bound = v.bind_providers(aot_modules, members, 'windows' if system == 'Windows' else 'macos', distributed)
        v.require(jit_result['baselineOutput'] == aot_result['baselineOutput'], 'JIT/AOT full public output mismatch')
        terminal.update({'publicAcquisition': acquired, 'jit': {'result': jit_result, 'registry': jit_registry, 'providers': jit_bound},
            'aot': {'result': aot_result, 'registry': aot_registry, 'providers': aot_bound},
            'aotEnvironment': {key: aot_env[key] for key in ('PATH', 'TMPDIR', 'TMP', 'TEMP', 'PUB_CACHE')}, 'emptyCwdInventory': cwd_before})
        v.unchanged(bundle_before, v.inventory(bundle), 'SDK source bundle')
        v.unchanged(bundle_before, v.inventory(distributed), 'distributed bundle')
        write_json(output / 'bundle-after.json', v.inventory(distributed))
        v.require(model.stat().st_size == v.MODEL_BYTES and v.sha256(model) == v.MODEL_SHA256,
                  'fixed model changed during qualification')
        v.unchanged(source_before, v.inventory(source, files), 'exported tracked source')
        v.unchanged(source_before, v.inventory(root, files), 'reviewed tracked source')
        v.require(not run_git(root, 'status', '--porcelain=v1', '--untracked-files=normal', log=logs / 'git-clean-after').strip(), 'reviewed source became dirty')
        write_json(output / 'source-after.json', v.inventory(root, files))
        cancellation.checkpoint()
        terminal.update({'completed': True, **v.scope(args.expected_native_tag, True)})
    except BaseException as error:
        terminal.update({'completed': False, **v.scope(args.expected_native_tag, False)})
        if isinstance(error, Cancelled):
            terminal['cancelledSignals'] = [error.signum]
        terminal['failureType'] = type(error).__name__
        terminal['failure'] = str(error)
        raise
    finally:
        with cancellation.deferred(deliver=False):
            for label, snapshot_root in (('source', root), ('exported-source', output / 'source')):
                if files is not None and source_before is not None and snapshot_root.exists():
                    try:
                        after = v.inventory(snapshot_root, files)
                        write_json(output / (label + '-after.json'), after)
                        v.unchanged(source_before, after, label)
                    except (v.Refusal, OSError) as error:
                        terminal.update({'completed': False, **v.scope(args.expected_native_tag, False)})
                        terminal.setdefault('inventoryFailures', []).append({'scope': label, 'error': str(error)})
            if 'bundle_before' in locals():
                for label, bundle_root in (('sdk-bundle', bundle), ('distributed-bundle', distributed)):
                    try:
                        after = v.inventory(bundle_root)
                        write_json(output / (label + '-after.json'), after)
                        v.unchanged(bundle_before, after, label)
                    except (v.Refusal, OSError) as error:
                        terminal.update({'completed': False, **v.scope(args.expected_native_tag, False)})
                        terminal.setdefault('inventoryFailures', []).append({'scope': label, 'error': str(error)})
            # A catchable signal during the first seal invalidates success
            # and causes one failure-only reseal; inference/build never repeat.
            for seal_pass in range(2):
                if cancellation.signals:
                    terminal.update({'completed': False, **v.scope(args.expected_native_tag, False),
                        'cancelledSignals': cancellation.signals})
                    terminal.setdefault('failureType', 'Cancelled')
                    terminal.setdefault('failure', str(Cancelled(cancellation.signals[0])))
                seal_terminal(output, terminal)
                if not (cancellation.signals and terminal['completed']):
                    break
            if terminal.get('inventoryFailures') and sys.exc_info()[0] is None:
                raise v.Refusal('final source/bundle inventory changed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-root', required=True)
    parser.add_argument('--expected-core-sha', required=True)
    parser.add_argument('--expected-native-tag', required=True, choices=v.TAGS,
                        help='verification of committed pin only; never a runtime selector')
    parser.add_argument('--model', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        qualify(args)
    except Cancelled as error:
        print(str(error), file=sys.stderr)
        return 128 + error.signum
    except KeyboardInterrupt:
        print('qualification cancelled by keyboard interruption', file=sys.stderr)
        return 130
    except (v.Refusal, OSError, subprocess.SubprocessError) as error:
        print(f'qualification refused: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
