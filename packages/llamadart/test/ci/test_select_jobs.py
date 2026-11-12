"""Behavioral trigger and aggregate tests. Run without Dart or third-party deps."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('select_jobs', ROOT / 'tool/ci/select_jobs.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class SelectionTest(unittest.TestCase):
    def test_documentation_omits_native_and_bundles(self):
        for path in ('website/pubspec.lock', 'website/sidebars.json'):
            with self.subTest(path=path):
                plan = ci.select([path])
                self.assertEqual({j for j, v in plan['jobs'].items() if v},
                                 {'docs-check', 'docs-versions'})
                self.assertEqual(plan['apps'], [])
                self.assertEqual(plan['desktops'], [])

    def test_every_maintained_markdown_path_runs_only_the_markdown_tests(self):
        for path in ('AGENTS.md', 'CONTRIBUTING.md', 'doc/testing_matrix.md',
                     'doc/pr_branch_writer_inventory.md', 'README.md', 'CHANGELOG.md',
                     'website/docs/guides/embeddings.md',
                     'website/versioned_docs/version-0.15.2/intro.md',
                     'packages/llamadart_validation/README.md',
                     'packages/llamadart_stable_diffusion_flutter/README.md',
                     'example/chat_app/README.md'):
            with self.subTest(path=path):
                plan = ci.select([path])
                self.assertEqual({j for j, v in plan['jobs'].items() if v},
                                 {'docs-check', 'docs-versions', 'markdown-tests'})
                self.assertEqual(plan['apps'], [])
                self.assertEqual(plan['desktops'], [])

        # Unclassified Markdown retains the conservative full fallback too.
        self.assertTrue(ci.select(['skills/llamadart-chat/SKILL.md'])
                        ['jobs']['test-linux-coverage'])

    def test_markdown_tests_defer_to_linux_coverage_which_runs_them_too(self):
        for paths in (['README.md', 'lib/llamadart.dart'], ['doc/a.md', 'test/unit/a_test.dart'],
                      ['test/README.md'], ['packages/llamadart_litert_lm_flutter/lib/a.dart', 'doc/a.md'],
                      ['skills/llamadart-chat/SKILL.md'], []):
            with self.subTest(paths=paths):
                plan = ci.select(paths)
                self.assertTrue(plan['jobs']['test-linux-coverage'])
                self.assertFalse(plan['jobs']['markdown-tests'])

    def test_validation_integration_is_not_dropped_for_markdown_alone(self):
        # Only full Linux coverage, not the Markdown tests, runs its root tests.
        plan = ci.select(['packages/llamadart_validation/lib/a.dart', 'doc/a.md'])
        self.assertFalse(plan['jobs']['test-linux-coverage'])
        self.assertTrue(plan['jobs']['web-chat-contract'])
        self.assertTrue(plan['jobs']['validation-integration'])

    def test_markdown_reader_helpers_run_the_guard_without_full_coverage(self):
        for path in ('tool/docs/build_site.sh', 'tool/docs/new_reader.dart',
                     'tool/testing/validation/remote.dart', 'tool/testing/validation.dart'):
            with self.subTest(path=path):
                plan = ci.select([path])
                self.assertTrue(plan['jobs']['markdown-tests'])
                self.assertFalse(plan['jobs']['test-linux-coverage'])
                self.assertFalse(plan['jobs']['test-web'])
                self.assertFalse(plan['jobs']['test-other-os'])

    def test_unrelated_paths_do_not_select_markdown_tests(self):
        for path in ('website/sidebars.json', 'doc/images/a.png',
                     'LICENSE', 'packages/genkit_llamadart/lib/a.dart',
                     'example/chat_app/test/unit_test.dart'):
            with self.subTest(path=path):
                self.assertFalse(ci.select([path])['jobs']['markdown-tests'])

    def test_deleted_and_renamed_markdown_keep_tooling_and_specialized_jobs(self):
        for raw in (b'D\0website/docs/integrations/genkit.md\0',
                    b'R100\0packages/genkit_llamadart/README.md\0website/docs/new.md\0'):
            plan = ci.select(ci.inventory(raw))
            self.assertTrue(plan['jobs']['markdown-tests'])
            self.assertTrue(plan['jobs']['genkit'])
            self.assertEqual(plan['apps'], [])
            self.assertEqual(plan['desktops'], [])

    def test_chat_app_vm_only_tests_select_chat_app_tests_only(self):
        for path in ('example/chat_app/test/unit_test.dart',
                     'example/chat_app/test_vm/image_evidence_test.dart'):
            with self.subTest(path=path):
                plan = ci.select([path])
                self.assertEqual({j for j, v in plan['jobs'].items() if v},
                                 {'analyze', 'web-chat-contract'})
                self.assertEqual(plan['apps'], [])

    def test_example_package_tests_follow_core_and_example_changes_only(self):
        for path in ('lib/llamadart.dart', 'pubspec.yaml', 'example/basic_app/lib/main.dart',
                     'example/laya_tetris/test/tetris_test.dart',
                     'example/tui_coding_agent/pubspec.yaml'):
            with self.subTest(path=path):
                self.assertTrue(ci.select([path])['jobs']['example-packages'])
        for path in ('example/chat_app/lib/main.dart', 'example/chat_app/test/unit_test.dart',
                     'example/basic_app/README.md', 'test/unit/core/engine_test.dart',
                     'packages/genkit_llamadart/lib/genkit_llamadart.dart',
                     'packages/llamadart_validation/lib/src/runner.dart'):
            with self.subTest(path=path):
                self.assertFalse(ci.select([path])['jobs']['example-packages'])

    def test_genkit_gateway_runs_package_snippet_compilation_with_docs(self):
        plan = ci.select(['website/docs/integrations/genkit.md'])
        self.assertEqual({j for j, v in plan['jobs'].items() if v},
                         {'docs-check', 'docs-versions', 'markdown-tests',
                          'genkit'})
        self.assertEqual(plan['companions'], [])
        self.assertEqual(plan['apps'], [])

    def test_genkit_is_independent_but_core_and_shared_changes_test_the_adapter(self):
        for path in ('lib/genkit_llamadart.dart', 'README.md', 'pubspec.yaml',
                     '.github/check_docs.py', 'test/contract_test.dart'):
            plan = ci.select(['packages/genkit_llamadart/' + path])
            expected = {'genkit'}
            if path.endswith('.md'):
                expected.add('markdown-tests')
            self.assertEqual({j for j, v in plan['jobs'].items() if v}, expected)
            self.assertEqual(plan['companions'], [])
            self.assertEqual(plan['apps'], [])
            self.assertEqual(plan['desktops'], [])
        for paths in (['lib/llamadart.dart'], ['pubspec.yaml'], ['hook/build.dart'],
                      ['.github/workflows/ci.yml'], [],
                      ['packages/genkit_llamadart/lib/a.dart', 'lib/llamadart.dart']):
            plan = ci.select(paths)
            self.assertTrue(plan['jobs']['genkit'])

    def test_model_store_is_independent_but_core_changes_test_it(self):
        for path in ('lib/llamadart_model_store.dart', 'README.md', 'pubspec.yaml',
                     'test/model_store_test.dart'):
            plan = ci.select(['packages/llamadart_model_store/' + path])
            expected = {'model-store'}
            if path.endswith('.md'):
                expected.add('markdown-tests')
            self.assertEqual({j for j, v in plan['jobs'].items() if v}, expected)
            self.assertEqual(plan['companions'], [])
            self.assertEqual(plan['apps'], [])
            self.assertEqual(plan['desktops'], [])
        plan = ci.select(['website/docs/guides/model-store.md'])
        self.assertEqual({j for j, v in plan['jobs'].items() if v},
                         {'docs-check', 'docs-versions', 'markdown-tests',
                          'model-store'})
        for paths in (['lib/llamadart.dart'], ['pubspec.yaml'],
                      ['.github/workflows/ci.yml'], []):
            self.assertTrue(ci.select(paths)['jobs']['model-store'], paths)

    def test_shared_runtime_and_unknown_select_full(self):
        for path in ('lib/src/core/engine.dart', 'hook/build.dart', 'pubspec.yaml',
                     'pubspec.lock', '.flutter-version', 'dart_test.yaml',
                     'scripts/new-build.sh', 'new/unknown.file', '.github/actions/local/action.yml'):
            with self.subTest(path=path):
                plan = ci.select([path])
                self.assertTrue(plan['jobs']['test-linux-coverage'])
                self.assertTrue(plan['jobs']['test-web'])
                self.assertTrue(plan['jobs']['test-other-os'])
                self.assertTrue(plan['jobs']['native-prompt-reuse-parity'])
                self.assertEqual(plan['desktops'], list(ci.DESKTOPS))
                self.assertEqual(plan['apps'], list(ci.APPS))

    def test_companions_name_every_checked_out_flutter_apple_companion(self):
        checked_out = sorted(
            path.parents[2].name
            for path in (ROOT / 'packages').glob('*/darwin/*/Package.swift')
            if path.parent.name == path.parents[2].name
        )
        self.assertIn('llamadart_stable_diffusion_flutter', checked_out)
        self.assertEqual(sorted(ci.COMPANIONS), checked_out)

    def test_companion_keeps_real_consumers_and_only_affected_package(self):
        for name in ci.COMPANIONS:
            plan = ci.select(['packages/' + name + '/darwin/Package.swift'])
            self.assertEqual(plan['companions'], ['packages/' + name])
            for job in ('analyze', 'companion-packages', 'test-linux-coverage',
                        'test-other-os', 'web-chat-contract'):
                self.assertTrue(plan['jobs'][job], job)
            self.assertFalse(plan['jobs']['test-web'])
            self.assertEqual(plan['apps'], list(ci.APPS))
            self.assertEqual(plan['desktops'], [])

    def test_validation_profiles_tests_keep_contracts_without_compilation(self):
        for path in ('test/validation_test.dart', 'assets/profiles/chat-gguf-cpu.json',
                     'schemas/profile.schema.json'):
            plan = ci.select(['packages/llamadart_validation/' + path])
            for job in ('analyze', 'validation-harness', 'validation-integration'):
                self.assertTrue(plan['jobs'][job])
            self.assertEqual(plan['apps'], [])
            self.assertEqual(plan['desktops'], [])

    def test_validation_files_the_chat_app_builds_from_select_web_chat(self):
        for path in ('lib/src/runner.dart', 'pubspec.yaml', 'assets/profiles/chat-gguf-cpu.json',
                     'assets/decision/laya_0_3_5_reference.json',
                     'assets/embeddings/v1/reference.json'):
            with self.subTest(path=path):
                self.assertTrue(ci.select(['packages/llamadart_validation/' + path])
                                ['jobs']['web-chat-contract'])
        for path in ('test/validation_test.dart', 'schemas/profile.schema.json',
                     'assets/capability_coverage.json', 'assets/speech/tone.wav'):
            with self.subTest(path=path):
                self.assertFalse(ci.select(['packages/llamadart_validation/' + path])
                                 ['jobs']['web-chat-contract'])

    def test_bundled_validation_assets_match_the_package_flutter_assets(self):
        lines = (ROOT / 'packages/llamadart_validation/pubspec.yaml').read_text().splitlines()
        start = lines.index('  assets:', lines.index('flutter:'))
        declared = []
        for line in lines[start + 1:]:
            if not line.startswith('    - '):
                break
            declared.append('packages/llamadart_validation/' + line[len('    - '):])
        self.assertEqual(sorted(declared), sorted(ci.VALIDATION_BUNDLED_ASSETS))

    def test_validation_implementation_and_deps_build_consumers(self):
        for path in ('lib/src/runner.dart', 'bin/run.dart', 'pubspec.yaml'):
            plan = ci.select(['packages/llamadart_validation/' + path])
            self.assertTrue(plan['jobs']['validation-integration'])
            self.assertEqual(plan['apps'], list(ci.APPS))
            self.assertEqual(plan['desktops'], list(ci.DESKTOPS))

    def test_mixed_changes_keep_flutter_consumer_when_only_root_tests_are_substituted(self):
        validation = 'packages/llamadart_validation/test/validation_test.dart'
        mixed = ci.select([validation, 'test/unit/tooling/validation_remote_test.dart'])
        self.assertTrue(mixed['jobs']['test-linux-coverage'])
        self.assertFalse(mixed['jobs']['web-chat-contract'])
        self.assertTrue(mixed['jobs']['validation-integration'])
        full = ci.select([validation, 'lib/llamadart.dart'])
        self.assertTrue(full['jobs']['test-linux-coverage'])
        self.assertTrue(full['jobs']['web-chat-contract'])
        self.assertFalse(full['jobs']['validation-integration'])

    def test_platform_targets(self):
        for directory, target in [('android', 'android'), ('ios', 'ios-inputs'), ('web', 'web')]:
            plan = ci.select([f'example/chat_app/{directory}/config'])
            self.assertEqual(plan['apps'], [target])
            self.assertEqual(plan['desktops'], [])
        plan = ci.select(['example/chat_app/lib/validation/controller.dart'])
        self.assertEqual(plan['apps'], list(ci.APPS))
        self.assertFalse(plan['jobs']['validation-integration'])

    def test_chat_app_files_imported_by_validation_tooling_run_root_validation_tests(self):
        for path in ('example/chat_app/lib/models/image_model_profile.dart',
                     'example/chat_app/integration_test/support/image_evidence.dart',
                     'example/chat_app/integration_test/support/image_settings_evidence.dart'):
            with self.subTest(path=path):
                plan = ci.select([path])
                for job in ('analyze', 'validation-harness', 'validation-integration',
                            'web-chat-contract'):
                    self.assertTrue(plan['jobs'][job], job)

    def test_root_tests_retain_all_os_inventories(self):
        for path in ('test/unit/tooling/windows_test.dart', 'test/test_helper.dart',
                     'test/fixtures/grammar.json'):
            plan = ci.select([path])
            for job in ('test-linux-coverage', 'test-web', 'test-other-os'):
                self.assertTrue(plan['jobs'][job])

    def test_pull_requests_build_macos_desktop_and_android_for_their_inputs_only(self):
        for paths in (['lib/llamadart.dart'], ['lib/src/core/engine.dart', 'README.md'],
                      ['.github/workflows/ci.yml'], ['new/unknown.file'],
                      ['example/basic_app/lib/main.dart'], ['example/chat_app/web/config'],
                      ['example/chat_app/test/unit_test.dart']):
            with self.subTest(paths=paths):
                after_merge = ci.select(paths)
                plan = ci.select(paths, pull_request=True)
                self.assertNotIn('macos-15', plan['desktops'])
                self.assertNotIn('android', plan['apps'])
                self.assertEqual(plan['jobs'], after_merge['jobs'])
                self.assertEqual(
                    [d for d in after_merge['desktops'] if d != 'macos-15'], plan['desktops'])
                self.assertEqual(
                    [a for a in after_merge['apps'] if a != 'android'], plan['apps'])
        for path in ('hook/build.dart', 'lib/src/hook/native_release_pins.dart', 'pubspec.yaml',
                     'pubspec.lock', 'tool/testing/validation/bundle.dart',
                     'tool/testing/validation.dart', 'packages/llamadart_validation/bin/run.dart',
                     '.github/workflows/validation_bundles.yml', 'tool/ci/select_jobs.py'):
            with self.subTest(path=path):
                plan = ci.select([path], pull_request=True)
                self.assertIn('macos-15', plan['desktops'])
                self.assertIn('android', plan['apps'])
        for path in ('example/chat_app/android/app/build.gradle', 'example/chat_app/lib/main.dart',
                     'example/chat_app/pubspec.yaml',
                     'packages/llamadart_llama_cpp_flutter/pubspec.yaml'):
            with self.subTest(path=path):
                plan = ci.select([path], pull_request=True)
                self.assertNotIn('macos-15', plan['desktops'])
                self.assertIn('android', plan['apps'])
        # An unknown or unreadable inventory stays full.
        self.assertEqual(ci.select([], pull_request=True)['desktops'], list(ci.DESKTOPS))
        self.assertEqual(ci.select(['README.md'], force_full=True, pull_request=True)['apps'],
                         list(ci.APPS))

    def test_coverage_runs_after_merge_only(self):
        self.assertTrue(ci.select(['lib/llamadart.dart'])['coverage'])
        self.assertTrue(ci.select([], force_full=True)['coverage'])
        plan = ci.select(['lib/llamadart.dart'], pull_request=True)
        self.assertFalse(plan['coverage'])
        self.assertTrue(plan['jobs']['test-linux-coverage'])
        expected = ci.expected_jobs(plan)
        self.assertTrue(expected['test-linux-vm'])
        self.assertFalse(expected['test-linux-coverage'])

    def test_workflows_select_real_artifact_roundtrip(self):
        for path in ('.github/workflows/ci.yml', '.github/workflows/validation_bundles.yml',
                     'tool/ci/select_jobs.py', 'test/ci/test_select_jobs.py'):
            self.assertTrue(ci.select([path])['jobs']['artifact-contract'])
        self.assertFalse(ci.select(['lib/llamadart.dart'])['jobs']['artifact-contract'])

    def test_workflow_artifact_selection_survives_later_shared_paths(self):
        for paths in (
            ['.github/workflows/ci.yml', 'tool/testing/test_matrix.dart'],
            ['tool/testing/test_matrix.dart', '.github/workflows/ci.yml'],
            ['.github/workflows/ci.yml', 'lib/llamadart.dart', 'README.md'],
        ):
            with self.subTest(paths=paths):
                self.assertTrue(ci.select(paths)['jobs']['artifact-contract'])

    def test_selection_is_independent_of_changed_path_order(self):
        paths = [
            'README.md', 'lib/llamadart.dart', '.github/workflows/ci.yml',
            'tool/testing/test_matrix.dart', 'new/unknown',
            'packages/llamadart_llama_cpp_flutter/lib/plugin.dart',
            'packages/llamadart_validation/lib/src/runner.dart',
            'packages/llamadart_validation/assets/profiles/chat-gguf-cpu.json',
            'test/unit/tooling/validation_remote_test.dart',
            'example/chat_app/android/config', 'example/chat_app/web/config',
        ]
        for left in paths:
            for right in paths:
                forward, reverse = ci.select([left, right]), ci.select([right, left])
                for key in ('jobs', 'companions', 'desktops', 'apps'):
                    self.assertEqual(forward[key], reverse[key], (left, right, key))

    def test_rename_delete_and_union(self):
        paths = ci.inventory(b'R100\0lib/old.dart\0doc/new.md\0D\0hook/build.dart\0')
        self.assertEqual(paths, ['lib/old.dart', 'doc/new.md', 'hook/build.dart'])
        plan = ci.select(paths)
        self.assertTrue(plan['jobs']['test-other-os'])
        plan = ci.select(ci.inventory(b'D\0example/chat_app/android/build.gradle\0'))
        self.assertEqual(plan['apps'], ['android'])
        plan = ci.select(['example/chat_app/android/a', 'example/chat_app/ios/b'])
        self.assertEqual(plan['apps'], ['android', 'ios-inputs'])

    def test_inventory_rejects_truncation_unsafe_paths_and_invalid_encoding(self):
        for raw in (b'M\0no-terminator', b'R100\0only-one\0', b'M\0../x\0',
                    b'M\0/x\0', b'?\0x\0', b'M\0\xff\0'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                ci.inventory(raw)
        self.assertEqual(ci.inventory(b'M\0path with spaces\nand newline\0'),
                         ['path with spaces\nand newline'])

    def test_manual_or_missing_inventory_is_full(self):
        for plan in (ci.select([]), ci.select(['README.md'], force_full=True)):
            self.assertEqual(plan['desktops'], list(ci.DESKTOPS))
            self.assertTrue(plan['jobs']['artifact-contract'])

    def test_real_git_inventory_for_pr_push_rename_and_delete(self):
        with tempfile.TemporaryDirectory() as scratch:
            def git(*args):
                return subprocess.check_output(['git', '-C', scratch, *args], text=True).strip()
            git('init', '-q')
            git('config', 'user.email', 'test@example.invalid')
            git('config', 'user.name', 'CI test')
            file = Path(scratch) / 'runtime.dart'
            file.write_text('same bytes')
            git('add', '.')
            git('commit', '-qm', 'base')
            base = git('rev-parse', 'HEAD')
            (Path(scratch) / 'doc').mkdir()
            git('mv', 'runtime.dart', 'doc/renamed.md')
            git('commit', '-qm', 'rename')
            head = git('rev-parse', 'HEAD')
            previous = os.getcwd()
            try:
                os.chdir(scratch)
                for event, payload in (
                    ('push', {'before': base, 'after': head}),
                    ('pull_request', {'pull_request': {'base': {'sha': base}, 'head': {'sha': head}}}),
                ):
                    self.assertEqual(ci.event_paths(event, payload), ['runtime.dart', 'doc/renamed.md'])
                git('rm', 'doc/renamed.md')
                git('commit', '-qm', 'delete')
                self.assertEqual(ci.event_paths('push', {'before': head, 'after': git('rev-parse', 'HEAD')}),
                                 ['doc/renamed.md'])
            finally:
                os.chdir(previous)

    def test_cli_missing_revision_falls_back_full(self):
        with tempfile.TemporaryDirectory() as scratch:
            event = Path(scratch) / 'event.json'
            event.write_text(json.dumps({'before': '0' * 40, 'after': '1' * 40}))
            output = Path(scratch) / 'output'
            env = dict(os.environ, GITHUB_EVENT_NAME='push', GITHUB_EVENT_PATH=str(event), GITHUB_OUTPUT=str(output))
            result = subprocess.run([sys.executable, str(ROOT / 'tool/ci/select_jobs.py'), 'select'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            plan = json.loads(result.stdout)
            self.assertTrue(plan['jobs']['test-other-os'])
            self.assertIn('desktops-enabled=true', output.read_text())
            self.assertIn('coverage=true', output.read_text())

    def test_cli_pull_request_skips_coverage_even_when_it_falls_back_full(self):
        with tempfile.TemporaryDirectory() as scratch:
            event = Path(scratch) / 'event.json'
            event.write_text(json.dumps({'pull_request': {'base': {'sha': '0' * 40},
                                                          'head': {'sha': '1' * 40}}}))
            output = Path(scratch) / 'output'
            env = dict(os.environ, GITHUB_EVENT_NAME='pull_request',
                       GITHUB_EVENT_PATH=str(event), GITHUB_OUTPUT=str(output))
            result = subprocess.run([sys.executable, str(ROOT / 'tool/ci/select_jobs.py'), 'select'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            plan = json.loads(result.stdout)
            self.assertTrue(plan['jobs']['test-linux-coverage'])
            self.assertFalse(plan['coverage'])
            self.assertEqual(plan['desktops'], list(ci.DESKTOPS))
            self.assertIn('coverage=false', output.read_text())

    def test_cli_manual_run_selects_every_job_that_gates_the_chat_app_deploy(self):
        with tempfile.TemporaryDirectory() as scratch:
            event = Path(scratch) / 'event.json'
            event.write_text(json.dumps({'ref': 'refs/heads/main', 'inputs': None}))
            output = Path(scratch) / 'output'
            env = dict(os.environ, GITHUB_EVENT_NAME='workflow_dispatch',
                       GITHUB_EVENT_PATH=str(event), GITHUB_OUTPUT=str(output))
            result = subprocess.run([sys.executable, str(ROOT / 'tool/ci/select_jobs.py'), 'select'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['jobs'],
                             ci.select([], force_full=True)['jobs'])
            self.assertIn('web-chat-contract=true', output.read_text())


class AggregateTest(unittest.TestCase):
    def test_each_selected_job_must_succeed_and_each_unselected_job_must_skip(self):
        for bundle, pull_request in ((False, False), (True, False), (False, True), (True, True)):
            for paths in (['README.md'], ['lib/llamadart.dart'], ['example/chat_app/android/a'],
                          ['example/chat_app/ios/a']):
                plan = ci.select(paths, pull_request=pull_request)
                expected = ci.expected_jobs(plan, bundle)
                needs = {'changes': {'result': 'success'}}
                needs.update({j: {'result': 'success' if selected else 'skipped'} for j, selected in expected.items()})
                self.assertEqual(ci.aggregate(plan, needs, bundle), [])
                for job, selected in expected.items():
                    correct = needs[job]['result']
                    for result in ('failure', 'cancelled', 'skipped' if selected else 'success'):
                        needs[job]['result'] = result
                        self.assertTrue(ci.aggregate(plan, needs, bundle), (job, result))
                    needs[job]['result'] = correct
                needs['changes']['result'] = 'failure'
                self.assertTrue(ci.aggregate(plan, needs, bundle))

    def test_linux_vm_shards_share_the_coverage_selection(self):
        for paths, selected in ((['example/chat_app/android/a'], False), (['lib/llamadart.dart'], True)):
            plan = ci.select(paths)
            self.assertEqual(plan['jobs']['test-linux-coverage'], selected)
            self.assertEqual(ci.expected_jobs(plan)['test-linux-vm'], selected)
            self.assertNotIn('test-linux-vm', ci.expected_jobs(plan, bundle=True))
            needs = {'changes': {'result': 'success'}}
            needs.update({j: {'result': 'success' if s else 'skipped'}
                          for j, s in ci.expected_jobs(plan).items()})
            del needs['test-linux-vm']
            self.assertTrue(ci.aggregate(plan, needs), paths)

    def test_companion_job_runs_for_every_check_it_hosts(self):
        # Each path selects one of the checks without the others being implied.
        cases = (
            (['packages/llamadart_litert_lm_flutter/lib/a.dart'], True),
            (['test/integration/apple_companion_flutter_cache_test.dart'], True),
            (['packages/llamadart_validation/test/process_memory_test.dart'], True),
            (['example/chat_app/lib/main.dart'], True),
            (['README.md'], False),
            (['packages/genkit_llamadart/lib/a.dart'], False),
            (['example/chat_app/test/unit_test.dart'], False),
        )
        for paths, selected in cases:
            with self.subTest(paths=paths):
                plan = ci.select(paths)
                self.assertEqual(ci.expected_jobs(plan)['companion-packages'], selected)
                needs = {'changes': {'result': 'success'}}
                needs.update({j: {'result': 'success' if s else 'skipped'}
                              for j, s in ci.expected_jobs(plan).items()})
                self.assertEqual(ci.aggregate(plan, needs), [])
                needs['companion-packages']['result'] = 'failure' if selected else 'success'
                self.assertTrue(ci.aggregate(plan, needs))

    def test_windows_harness_leg_stands_alone_only_without_test_native(self):
        cases = (
            (['packages/llamadart_validation/test/process_memory_test.dart'],
             ['ubuntu-latest', 'windows-latest']),
            (['example/chat_app/lib/main.dart'], ['ubuntu-latest', 'windows-latest']),
            (['packages/llamadart_validation/lib/src/runner.dart'],
             ['ubuntu-latest', 'windows-latest']),
            (['lib/llamadart.dart'], ['ubuntu-latest']),
            (['packages/llamadart_validation/test/a.dart', 'test/unit/core/a_test.dart'],
             ['ubuntu-latest']),
        )
        for paths, oses in cases:
            with self.subTest(paths=paths):
                plan = ci.select(paths)
                self.assertTrue(plan['jobs']['validation-harness'])
                self.assertEqual(ci.validation_harness_oses(plan), oses)

    def test_malformed_selection_cannot_turn_missing_work_into_success(self):
        for field, value in [('jobs', {}), ('desktops', ['unknown']), ('apps', ['web', 'web']),
                             ('companions', ['packages/llamadart_llama_cpp_flutter']),
                             ('coverage', 'false')]:
            plan = ci.select(['README.md'])
            plan[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                ci.aggregate(plan, {'changes': {'result': 'success'}})
        plan = ci.select(['README.md'])
        plan['jobs']['analyze'] = 'false'
        with self.assertRaises(ValueError):
            ci.aggregate(plan, {})

    def test_missing_or_extra_dependency_is_not_success(self):
        plan = ci.select(['README.md'])
        self.assertTrue(ci.aggregate(plan, {'changes': {'result': 'success'}}))
        needs = {'changes': {'result': 'success'}}
        needs.update({j: {'result': 'success' if selected else 'skipped'}
                      for j, selected in ci.expected_jobs(plan).items()})
        self.assertEqual(ci.aggregate(plan, needs), [])
        needs['new-unaccounted-job'] = {'result': 'success'}
        self.assertTrue(ci.aggregate(plan, needs))


if __name__ == '__main__':
    unittest.main()
