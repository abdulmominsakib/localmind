"""Synthetic contracts only. No SDK, model, provider or archive release is read."""
import argparse
import hashlib
import inspect
import io
import json
import os
import re
import signal
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import qualify
import verify as v
from test_compare_macho_identity import fixture, dylib


def pin_fixture(tag='v0.8.0-2'):
    # Model both future source pins without pinning source-only controls to
    # today's production tag. Archive bytes are fabricated in separate tests.
    source = (qualify.FIXTURE.parents[2] / 'lib/src/hook/native_release_pins.dart').read_text()
    return re.sub(r"^const llamaCppTag = '[^']+';$", "const llamaCppTag = '" + tag + "';",
                  source, count=1, flags=re.M)


def good_result():
    output = 'synthetic public text'
    return {**{key: True for key in ('completed', 'disposed', 'unloaded', 'fullOutputParity', 'reloadParity', 'reuseParity')},
        'gpuLayers': 0, 'threads': 2, 'maxTokens': 128,
        'fixture': {'strategy': 'ngram-simple', 'sizeN': 4, 'sizeM': 8, 'minHits': 1,
                    'promptSha256': v.PROMPT_SHA256},
        **{key: 128 for key in ('baselineEvalTokens', 'ngramEvalTokens', 'reloadEvalTokens', 'reuseEvalTokens')},
        **{key: 5 for key in ('drafted', 'accepted', 'draftAttempts')},
        **{key: output for key in ('baselineOutput', 'ngramOutput', 'reloadOutput', 'reuseOutput')},
        **{key: hashlib.sha256(output.encode()).hexdigest() for key in ('baselineSha256', 'ngramSha256')}}


def line(result):
    return 'CONSUMER_RESULT ' + json.dumps(result) + '\n'


def observations(root):
    wrapper = str(root / 'libllamadart.dylib')
    digest = hashlib.sha256(fixture()).hexdigest()
    exports = [{'symbol': symbol, 'address': address, 'ownerBase': 1024, 'ownerPath': wrapper}
               for symbol, address in zip(v.MAC_SYMBOLS, (2048, 3000, 4000, 5000))]
    row = {'modulePath': wrapper, 'moduleBase': 1024, 'sha256': digest,
           'exports': exports, 'imports': []}
    registry = {'runtimeLayout': 'consolidated-apple', 'codeAssetId': v.MAC_ASSET,
        'primaryMatchesCodeAsset': True, 'noUnintendedDuplicateRegistry': True,
        'observerAfterFirstPassiveSnapshot': True, 'codeAssetAddress': 2048,
        'codeAssetOwner': {**exports[0], 'sha256': digest},
        'codeAssetProvider': [exports[0]], 'primaryRegistryExport': exports[0],
        'primaryRegistryImports': [], 'distinctRegistryProviderBasesBefore': 1,
        'modelCodeAsset': {**exports[2], 'assetId': v.MAC_ASSET, 'sha256': digest}}
    result = good_result()
    result['query'] = {'hasNextn': True, 'nextnNullFalse': True, 'probeAfterPublicOutcome': True,
        'hasLegacyQuery': True, 'wrapperPath': wrapper, 'wrapperSha256': digest,
        'nextnOwnerPath': wrapper, 'nextnOwnerSha256': digest,
        'nextnAddress': 5000, 'nextnOwnerBase': 1024}
    return ('PASSIVE_MODULE ' + json.dumps({**row, 'checkpoint': 'after-public-model-outcome'}) + '\n'
        + 'REGISTRY_IDENTITY ' + json.dumps(registry) + '\n'
        + 'PASSIVE_MODULE ' + json.dumps({**row, 'checkpoint': 'after-registry-observation'}) + '\n'
        + line(result))


def split_observations(root):
    wrapper, llama, ggml = [str(root / name) for name in ('llamadart.dll', 'llama.dll', 'ggml.dll')]
    digest = hashlib.sha256(b'syntheticDLL').hexdigest()
    registry = {'address': 2048, 'ownerBase': 1024, 'ownerPath': ggml}
    rows = [{'modulePath': path, 'checkpoint': 'after-public-model-outcome', 'sha256': digest,
        'exports': ([{'symbol': 'llama_model_load_from_file', 'address': 3000, 'ownerPath': llama}]
                    if path == llama else []), 'imports': []} for path in (wrapper, llama, ggml)]
    identity = {'primaryMatchesCodeAsset': True, 'noUnintendedDuplicateRegistry': True,
        'observerAfterFirstPassiveSnapshot': True, 'codeAssetAddress': 2048,
        'codeAssetProvider': [registry], 'primaryRegistryImports': [registry]}
    return ''.join('PASSIVE_MODULE ' + json.dumps(row) + '\n' for row in rows) + 'REGISTRY_IDENTITY ' + json.dumps(identity) + '\n'


class QualificationControls(unittest.TestCase):
    def setUp(self):
        # Resolve host /var alias once. Synthetic layout must not test a host
        # symlink when it intends to test a regular positive fixture.
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def test_native2_can_never_count_as_native3(self):
        self.assertFalse(v.scope('v0.8.0-2', True)['finalNative3Qualified'])
        self.assertTrue(v.scope('v0.8.0-2', True)['pipelineOnly'])
        self.assertFalse(v.scope('v0.8.0-3', False)['finalNative3Qualified'])
        self.assertTrue(v.scope('v0.8.0-3', True)['finalNative3Qualified'])
        self.assertFalse(v.scope('v0.9.0', False)['finalNative3Qualified'])
        self.assertTrue(v.scope('v0.9.0', True)['finalNative3Qualified'])

    def test_tag_is_verification_only_and_mismatch_refused(self):
        for tag in v.TAGS:
            source = pin_fixture(tag)
            self.assertIn('macos-arm64', v.pins(source, tag, 'macos-arm64'))
            other = next(value for value in v.TAGS if value != tag)
            with self.assertRaisesRegex(v.Refusal, 'committed default pin'):
                v.pins(source, other, 'macos-arm64')
        config = qualify.pubspec(self.root)
        self.assertIn('llamadart_native_runtimes: [llama_cpp]', config)
        for forbidden in ('native_tag', 'native_path', 'native_repository', 'native_backends', 'v0.8.0'):
            self.assertNotIn(forbidden, config)

    def test_override_environment_refused_without_values(self):
        for name in ('DYLD_LIBRARY_PATH', 'LD_PRELOAD', 'GGML_BACKEND_PATH',
                     'LLAMADART_NATIVE_LIB_DIR', 'LLAMADART_BACKEND_MODULE_DIR', 'DART_DEFINES'):
            with self.subTest(name=name), self.assertRaises(v.Refusal) as caught:
                v.reject_overrides({name: 'DO_NOT_DISCLOSE'})
            self.assertNotIn('DO_NOT_DISCLOSE', str(caught.exception))
        v.reject_overrides({'LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG': 'v0.8.0-2'})

    def test_environment_preserves_home_without_repurposing_and_removes_sdk_path(self):
        parent = {'HOME': '/synthetic-home', 'PATH': '/foreign-sdk:/foreign-runtime', 'TOKEN': 'private'}
        if os.name == 'nt':
            parent['SystemRoot'] = os.environ['SystemRoot']
        actual = qualify.clean_environment(parent, self.root / 'temp', self.root / 'pub')
        self.assertEqual('/synthetic-home', actual['HOME'])
        self.assertNotIn('foreign', actual['PATH'])
        self.assertNotIn('TOKEN', actual)

    def test_whole_bundle_copy_retains_hidden_nested_and_excludes_parent_only_file(self):
        app = self.root / 'app'
        bundle = app / 'build/stock/bundle'
        (bundle / 'bin').mkdir(parents=True)
        (bundle / '.hidden/nested').mkdir(parents=True)
        (bundle / 'bin/consumer').write_bytes(b'not executable synthetic')
        (bundle / '.hidden/nested/sidecar').write_bytes(b'sidecar')
        (bundle.parent / 'parent-only').write_bytes(b'not shipped')
        manifest = v.copy_bundle(bundle, self.root / 'distributed', (app,))
        self.assertIn('.hidden/nested/sidecar', manifest)
        self.assertNotIn('parent-only', manifest)
        with self.assertRaisesRegex(v.Refusal, 'bundle root'):
            v.copy_bundle(bundle.parent, self.root / 'wrong', (app,))

    def test_bundle_destination_inside_app_refused(self):
        app = self.root / 'app'; bundle = app / 'bundle'; bundle.mkdir(parents=True)
        (bundle / 'file').write_bytes(b'a')
        with self.assertRaisesRegex(v.Refusal, 'outside every'):
            v.copy_bundle(bundle, app / 'distributed', (app,))

    def test_changed_bundle_and_written_cwd_refused(self):
        bundle = self.root / 'bundle'; bundle.mkdir()
        (bundle / 'library').write_bytes(b'raw')
        before = v.inventory(bundle)
        (bundle / 'library').write_bytes(b'changed')
        with self.assertRaisesRegex(v.Refusal, 'bundle changed'):
            v.unchanged(before, v.inventory(bundle), 'bundle')
        with self.assertRaisesRegex(v.Refusal, 'CWD changed'):
            v.unchanged({}, v.inventory(bundle), 'CWD')

    @unittest.skipIf(os.name == 'nt', 'symlink creation requires host privilege')
    def test_linked_provider_ancestor_refused(self):
        real = self.root / 'real'; real.mkdir(); (real / 'provider').write_bytes(b'a')
        alias = self.root / 'alias'; alias.symlink_to(real, target_is_directory=True)
        with self.assertRaisesRegex(v.Refusal, 'symlink'):
            v.no_links(alias / 'provider')

    def test_public_result_requires_complete_positive_active_full_output(self):
        v.public_result(line(good_result()))
        for key, value in [('drafted', 0), ('accepted', 0), ('draftAttempts', 0), ('completed', False),
                           ('disposed', False), ('reuseParity', False), ('ngramEvalTokens', 127),
                           ('ngramOutput', 'different'), ('baselineSha256', '0' * 64)]:
            changed = good_result(); changed[key] = value
            with self.subTest(key=key), self.assertRaises(v.Refusal):
                v.public_result(line(changed))
        for text in ('', line(good_result()) * 2, line({'completed': True})):
            with self.assertRaises(v.Refusal):
                v.public_result(text)

    def test_provider_map_and_query_validate_actual_addresses_and_owners(self):
        stdout = observations(self.root)
        result = v.public_result(stdout)
        modules, registry = v.native_modules(stdout, 'macos-arm64')
        v.query_result(result, modules, 'v0.8.0-2')
        with self.assertRaisesRegex(v.Refusal, 'legacy query'):
            v.query_result(result, modules, 'v0.8.0-3')
        wrong = stdout.replace('"codeAssetAddress": 2048', '"codeAssetAddress": 2049')
        with self.assertRaisesRegex(v.Refusal, 'addresses disagree'):
            v.native_modules(wrong, 'macos-arm64')
        wrong = stdout.replace('"ownerPath": ' + json.dumps(str(self.root / 'libllamadart.dylib')),
                               '"ownerPath": "/foreign/libggml.dylib"')
        with self.assertRaisesRegex(v.Refusal, 'consolidated export owner'):
            v.native_modules(wrong, 'macos-arm64')

    def test_provider_binding_preserves_actual_hash_and_rejects_foreign_or_changed(self):
        path = self.root / 'libllamadart.dylib'; path.write_bytes(fixture())
        members = {path.name: {'bytes': fixture(), 'archive': 'synthetic', 'member': 'lib/' + path.name}}
        modules = {str(path): {'sha256': v.sha256(path)}}
        bound = v.bind_providers(modules, members, 'macos', self.root)
        self.assertEqual(v.sha256(path), bound[str(path)]['actualSha256'])
        with self.assertRaisesRegex(v.Refusal, 'foreign loaded'):
            v.bind_providers(modules, members, 'macos', self.root / 'elsewhere')
        path.write_bytes(fixture(text=b'CHANGED!'))
        with self.assertRaisesRegex(v.Refusal, 'changed after'):
            v.bind_providers(modules, members, 'macos', self.root)

    def test_mac_scoped_relation_records_unattributed_difference_and_refuses_code_or_dependencies(self):
        raw = fixture()
        relation = v.mac_relation(raw, fixture(tail=b'CHANGEDSIGNATURE!'))
        self.assertFalse(relation['whole_file_identity'])
        self.assertFalse(relation['runtime_identity_proven'])
        self.assertIn('Unattributed', relation['transformation_cause'])
        with self.assertRaisesRegex(v.Refusal, 'code/data/UUID'):
            v.mac_relation(raw, fixture(text=b'CHANGED!'))
        with self.assertRaisesRegex(v.Refusal, 'dependency commands'):
            v.mac_relation(fixture(extra_commands=[dylib('/one', 0xc)]),
                           fixture(extra_commands=[dylib('/two', 0xc)]))

    def test_windows_dll_requires_exact_raw_bytes(self):
        path = self.root / 'llama.dll'; path.write_bytes(b'actualDLL')
        modules = {str(path): {'sha256': v.sha256(path)}}
        members = {'llama.dll': {'bytes': b'actualDLL', 'archive': 'synthetic', 'member': 'lib/llama.dll'}}
        v.bind_providers(modules, members, 'windows', self.root)
        members['llama.dll']['bytes'] = b'otherDLL'
        with self.assertRaisesRegex(v.Refusal, 'differs from pinned'):
            v.bind_providers(modules, members, 'windows', self.root)

    def test_archive_checksum_and_native_members_are_acquisition_oracle(self):
        tag, target = 'v0.8.0-2', 'macos-arm64'
        directory = self.root / tag / target; directory.mkdir(parents=True)
        archive = directory / f'llamadart-native-{target}-{tag}.tar.gz'
        def make(unsafe=False):
            with tarfile.open(archive, 'w:gz') as bundle:
                for name in ('libllamadart.dylib',):
                    row = tarfile.TarInfo('../escape' if unsafe else './' + name)
                    row.size = len(fixture()); bundle.addfile(row, io.BytesIO(fixture()))
        make()
        acquired, members = v.archive_members(self.root, tag, target, {target: v.sha256(archive)})
        self.assertEqual(1, len(members)); self.assertEqual(1, len(acquired))
        with self.assertRaisesRegex(v.Refusal, 'checksum mismatch'):
            v.archive_members(self.root, tag, target, {target: '0' * 64})
        make(True)
        with self.assertRaisesRegex(v.Refusal, 'traversal'):
            v.archive_members(self.root, tag, target, {target: v.sha256(archive)})

    def test_dry_run_uses_no_child_sdk_or_model_read(self):
        core = self.root / 'core'; core.mkdir()
        pins = core / 'lib/src/hook/native_release_pins.dart'; pins.parent.mkdir(parents=True)
        pins.write_text(pin_fixture())
        (core / '.flutter-version').write_text('3.47.1\n')
        args = argparse.Namespace(core_root=str(core), expected_core_sha='a' * 40,
            expected_native_tag='v0.8.0-2', model='/nonexistent-model', output=str(self.root / 'out'), dry_run=True)
        with (patch.dict(os.environ, {}, clear=True),
             patch.object(qualify, 'command', side_effect=AssertionError('no SDK')),
             patch.object(qualify, 'git', side_effect=AssertionError('no child')),
             patch.object(qualify, 'sdk_paths', side_effect=AssertionError('no SDK discovery')),
             patch('sys.stdout', new=io.StringIO()) as stdout):
            qualify.qualify(args)
        self.assertTrue(json.loads(stdout.getvalue())['dryRun'])
        self.assertFalse((self.root / 'out').exists())

    def run_synthetic_driver(self, failure=None):
        # Windows' system-only PATH still requires the actual host root.
        parent_environment = {'SystemRoot': os.environ['SystemRoot']} if os.name == 'nt' else {}
        core = self.root / 'core'; core.mkdir()
        fixture_dir = core / 'test/fixtures/native_default_consumer_qualification'
        fixture_dir.mkdir(parents=True)
        for name in ('consumer.dart', 'providers.dart', 'passive_modules.dart'):
            (fixture_dir / name).write_text((qualify.FIXTURE / name).read_text())
        pin = core / 'lib/src/hook/native_release_pins.dart'; pin.parent.mkdir(parents=True)
        pin.write_text(pin_fixture())
        (core / '.flutter-version').write_text('3.47.1\n')
        files = [p.relative_to(core).as_posix() for p in core.rglob('*') if p.is_file()]
        sdk = self.root / 'synthetic-sdk'; (sdk / 'bin/cache').mkdir(parents=True)
        (sdk / 'bin/cache/flutter.version.json').write_text(json.dumps({
            'frameworkVersion': '3.47.1', 'dartSdkVersion': '3.13.1'}))
        model = self.root / 'synthetic-model'; model.write_bytes(b'synthetic-not-a-model')
        output = self.root / 'out'
        args = argparse.Namespace(core_root=str(core), expected_core_sha='a' * 40,
            expected_native_tag='v0.8.0-2', model=str(model), output=str(output), dry_run=False)
        calls = []
        def fake_git(root, *arguments, log=None):
            self.assertIsNotNone(log)
            if arguments[0] == 'rev-parse': return b'a' * 40 + b'\n'
            if arguments[0] == 'status': return b''
            if arguments[0] == 'ls-files': return b'\0'.join(name.encode() for name in files) + b'\0'
            raise AssertionError(arguments)
        def libraries(directory):
            directory.mkdir(parents=True, exist_ok=True)
            for name in ('libllamadart.dylib',):
                (directory / name).write_bytes(fixture())
        def fake_command(argv, *, cwd, env, timeout, log):
            calls.append([str(value) for value in argv])
            stage = Path(log).name
            stdout = ''
            if stage == 'dart-version': stdout = 'Dart SDK version: 3.13.1 (stable)'
            if stage == 'analyze' and failure == 'before-model-signal':
                signal.raise_signal(signal.SIGTERM)
            if stage == 'jit':
                libraries(output / 'jit-provider')
                stdout = observations(output / 'jit-provider')
            if stage == 'build':
                bundle = Path(cwd) / 'build/default/bundle'
                (bundle / 'bin').mkdir(parents=True)
                (bundle / 'bin/consumer').write_bytes(b'not-an-executable')
                libraries(bundle / 'lib')
                (bundle / '.hidden/nested').mkdir(parents=True)
                (bundle / '.hidden/nested/sidecar').write_bytes(b'required hidden sidecar')
                (bundle.parent / 'parent-only').write_bytes(b'do not copy')
            if stage == 'aot':
                self.assertEqual({}, v.inventory(cwd))
                self.assertNotIn('synthetic-sdk', env['PATH'])
                self.assertTrue((output / 'distributed/.hidden/nested/sidecar').is_file())
                self.assertFalse((output / 'distributed/parent-only').exists())
                stdout = observations(output / 'distributed/lib')
                if failure == 'cwd': (Path(cwd) / 'write').write_text('forbidden')
                if failure == 'bundle': (output / 'distributed/bin/consumer').write_bytes(b'changed')
                if failure == 'result': stdout = stdout.replace('"accepted": 5', '"accepted": 0')
                if failure == 'source': pin.write_text(pin.read_text() + '\nchanged')
                if failure == 'signal': signal.raise_signal(signal.SIGTERM)
            Path(str(log) + '.stdout.log').write_text(stdout)
            Path(str(log) + '.stderr.log').write_text('')
            Path(str(log) + '.command.json').write_text(json.dumps({'synthetic': True, 'cleanupComplete': True}))
            return stdout
        members = {name: {'bytes': fixture(), 'archive': 'synthetic', 'member': 'lib/' + name}
                   for name in ('libllamadart.dylib',)}
        original_write = qualify.write_json
        signalled = False
        def signal_while_sealing(path, value):
            nonlocal signalled
            original_write(path, value)
            if failure == 'seal-signal' and Path(path).name == 'terminal.json' and not signalled:
                signalled = True
                signal.raise_signal(signal.SIGTERM)
        original_exit = qualify.CancellationGuard.__exit__
        def signal_at_guard_exit(guard, *arguments):
            if failure == 'exit-signal':
                signal.raise_signal(signal.SIGTERM)
            return original_exit(guard, *arguments)
        with (patch.dict(os.environ, parent_environment, clear=True), patch.object(qualify, 'FIXTURE', fixture_dir),
              patch.object(qualify.CancellationGuard, '__exit__', signal_at_guard_exit),
              patch.object(qualify, 'write_json', side_effect=signal_while_sealing),
              patch.object(qualify, 'git', side_effect=fake_git),
              patch.object(qualify, 'sdk_paths', return_value=(sdk, sdk / 'flutter', sdk / 'dart')),
              patch.object(qualify, 'command', side_effect=fake_command),
              patch.object(qualify.platform, 'system', return_value='Darwin'),
              patch.object(qualify.platform, 'machine', return_value='arm64'),
              patch.object(v, 'MODEL_BYTES', model.stat().st_size),
              patch.object(v, 'MODEL_SHA256', v.sha256(model)),
              patch.object(v, 'archive_members', return_value=({'synthetic': True}, members))):
            if failure:
                expected = qualify.Cancelled if failure in ('signal', 'seal-signal', 'exit-signal', 'before-model-signal', 'restore-signal') else v.Refusal
                with self.assertRaises(expected): qualify.qualify(args)
            else:
                qualify.qualify(args)
        return json.loads((output / 'terminal.json').read_text()), calls, output

    def test_synthetic_driver_builds_real_bundle_callsite_and_seals_pipeline_scope(self):
        terminal, calls, output = self.run_synthetic_driver()
        self.assertTrue(terminal['completed'])
        self.assertFalse(terminal['finalNative3Qualified'])
        build = next(call for call in calls if 'build' in call)
        self.assertEqual(['build', 'cli', '-o', 'build/default', '-t', 'consumer.dart'], build[1:])
        self.assertIn('distributed/bin/consumer', Path(calls[-1][0]).as_posix())
        self.assertTrue((output / 'source-after.json').is_file())
        manifest = json.loads((output / 'manifest.json').read_text())
        self.assertEqual(v.sha256(output / 'terminal.json'), manifest['terminalSha256'])
        self.assertTrue(v.verify_seal(output)['completed'])
        (output / 'logs/aot.stdout.log').write_text('tampered after seal')
        with self.assertRaisesRegex(v.Refusal, 'sealed evidence'):
            v.verify_seal(output)

    def test_synthetic_driver_retains_only_required_host_environment(self):
        expected = {'SYSTEMROOT': os.environ['SystemRoot']} if os.name == 'nt' else {}
        parents = []
        original = qualify.clean_environment
        def clean_environment(parent, *args, **kwargs):
            parents.append({key.upper(): value for key, value in parent.items()})
            return original(parent, *args, **kwargs)
        with (patch.dict(os.environ, {'LLAMADART_NATIVE_LIB_DIR': 'ambient-override',
                                     'PATH': 'ambient-path', 'TOKEN': 'ambient-secret'}),
              patch.object(qualify, 'clean_environment', side_effect=clean_environment)):
            terminal, _, _ = self.run_synthetic_driver()
        self.assertTrue(terminal['completed'])
        self.assertEqual([expected, expected], parents)

    def test_synthetic_driver_refuses_written_cwd(self):
        terminal, _, _ = self.run_synthetic_driver('cwd')
        self.assertFalse(terminal['completed'])

    def test_synthetic_driver_refuses_changed_whole_bundle(self):
        terminal, _, _ = self.run_synthetic_driver('bundle')
        self.assertFalse(terminal['completed'])

    def test_synthetic_driver_refuses_zero_activity(self):
        terminal, _, _ = self.run_synthetic_driver('result')
        self.assertFalse(terminal['completed'])

    def test_synthetic_driver_retains_changed_source_failure_inventory(self):
        terminal, _, output = self.run_synthetic_driver('source')
        self.assertFalse(terminal['completed'])
        self.assertIn('inventoryFailures', terminal)
        self.assertTrue((output / 'source-after.json').is_file())

    def test_synthetic_driver_sigterm_leaves_failure_terminal(self):
        terminal, _, output = self.run_synthetic_driver('signal')
        self.assertFalse(terminal['completed'])
        self.assertFalse(terminal['finalNative3Qualified'])
        self.assertEqual('Cancelled', terminal['failureType'])
        self.assertFalse(v.verify_seal(output)['completed'])

    def test_sigterm_during_terminal_write_cannot_leave_qualified_receipt(self):
        terminal, _, output = self.run_synthetic_driver('seal-signal')
        self.assertFalse(terminal['completed'])
        self.assertIn(signal.SIGTERM, terminal['cancelledSignals'])
        self.assertFalse(v.verify_seal(output)['completed'])

    def test_pending_outer_signal_refuses_the_next_model_child_before_creation(self):
        terminal, calls, output = self.run_synthetic_driver('before-model-signal')
        self.assertFalse(terminal['completed'])
        self.assertFalse(any('run' in call or 'build' in call for call in calls))
        self.assertFalse(v.verify_seal(output)['completed'])

    def test_signal_after_driver_seal_at_guard_exit_invalidates_success(self):
        terminal, _, output = self.run_synthetic_driver('exit-signal')
        self.assertFalse(terminal['completed'])
        self.assertFalse(terminal['finalNative3Qualified'])
        self.assertEqual('Cancelled', terminal['failureType'])
        self.assertIn(signal.SIGTERM, terminal['cancelledSignals'])
        self.assertFalse(v.verify_seal(output)['completed'])

    def test_signal_recorded_during_final_handler_restoration_invalidates_driver(self):
        exit_code = qualify.CancellationGuard.__exit__.__code__
        lines, first = inspect.getsourcelines(qualify.CancellationGuard.__exit__)
        restore = next(first + offset for offset, text in enumerate(lines)
                       if 'for signum, previous in self.previous.items()' in text)
        observed = []
        def trace(frame, event, argument):
            if (frame.f_code is exit_code and event == 'line'
                    and frame.f_lineno == restore and not observed):
                signal.raise_signal(signal.SIGTERM)
                observed.append(list(frame.f_locals['self'].signals))
            return trace
        previous_trace = sys.gettrace()
        try:
            sys.settrace(trace)
            terminal, _, output = self.run_synthetic_driver('restore-signal')
            self.assertEqual([[signal.SIGTERM]], observed)
            self.assertFalse(terminal['completed'])
            self.assertFalse(terminal['finalNative3Qualified'])
            self.assertEqual('Cancelled', terminal['failureType'])
            self.assertIn(signal.SIGTERM, terminal['cancelledSignals'])
            self.assertFalse(v.verify_seal(output)['completed'])
        finally:
            sys.settrace(previous_trace)

    def test_synthetic_python_child_timeout_is_reaped_and_receipted(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            qualify.command([sys.executable, '-c', 'import time; time.sleep(30)'], cwd=self.root,
                env=dict(os.environ), timeout=0.05, log=self.root / 'timeout')
        receipt = json.loads((self.root / 'timeout.command.json').read_text())
        self.assertTrue(receipt['cleanupComplete'])
        self.assertNotIn('exitCode', receipt)

    def test_synthetic_python_descendant_is_stopped_when_leader_exits(self):
        marker = self.root / 'orphan-wrote'
        code = "import time,pathlib; time.sleep(.3); pathlib.Path(" + repr(str(marker)) + ").write_text('leaked')"
        parent = "import subprocess,sys; subprocess.Popen([sys.executable,'-c'," + repr(code) + "])"
        qualify.command([sys.executable, '-c', parent], cwd=self.root,
            env=dict(os.environ), timeout=5, log=self.root / 'tree')
        # A synthetic Python-only delay lets the refused writer's deadline pass.
        import time
        time.sleep(.4)
        self.assertFalse(marker.exists())
        self.assertTrue(json.loads((self.root / 'tree.command.json').read_text())['cleanupComplete'])

    def test_synthetic_python_child_failure_still_has_cleanup_receipt(self):
        with self.assertRaises(v.Refusal):
            qualify.command([sys.executable, '-c', 'raise SystemExit(7)'], cwd=self.root,
                env=dict(os.environ), timeout=5, log=self.root / 'failure')
        receipt = json.loads((self.root / 'failure.command.json').read_text())
        self.assertEqual(7, receipt['exitCode']); self.assertTrue(receipt['cleanupComplete'])


if __name__ == '__main__':
    unittest.main()
