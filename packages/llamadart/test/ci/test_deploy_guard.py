"""Behavioral checks for the hosted-demo deploy guard against real Git histories."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tool/ci'))
import deploy_guard as guard

DOCS_CUT = ['website/versions.json', 'website/versioned_docs/version-1.2.3/intro.md',
            'website/versioned_sidebars/version-1.2.3-sidebars.json']


class InputTest(unittest.TestCase):
    def test_docs_cut_and_root_tests_change_no_demo_inputs(self):
        for demo in guard.DEMOS:
            for path in [*DOCS_CUT, 'CHANGELOG.md', 'test/unit/core/some_test.dart']:
                self.assertFalse(guard.is_input(demo, path), (demo, path))

    def test_each_demo_follows_its_own_deploy_trigger(self):
        for path in ['lib/llamadart.dart', 'hook/build.dart', 'pubspec.yaml']:
            for demo in guard.DEMOS:
                self.assertTrue(guard.is_input(demo, path), (demo, path))
        self.assertTrue(guard.is_input('laya-tetris', 'example/laya_tetris/lib/main.dart'))
        self.assertFalse(guard.is_input('laya-tetris', 'example/chat_app/lib/main.dart'))
        self.assertFalse(guard.is_input('laya-tetris', 'pubspec.yaml.bak'))
        self.assertFalse(guard.is_input('laya-tetris', 'library/notes.txt'))
        self.assertTrue(guard.is_input('chat-app', 'example/chat_app/lib/main.dart'))
        self.assertFalse(guard.is_input('chat-app', 'example/chat_app/android/app/build.gradle.kts'))
        # Unknown paths stay conservative for the selector-driven chat app.
        self.assertTrue(guard.is_input('chat-app', 'new-unknown-input'))
        # The chat app depends on the validation package and bundles its profiles.
        for path in ['packages/llamadart_validation/lib/src/runner.dart',
                     'packages/llamadart_validation/assets/profiles/chat-gguf-cpu.json']:
            self.assertTrue(guard.is_input('chat-app', path), path)
            self.assertFalse(guard.is_input('laya-tetris', path), path)

    def test_laya_patterns_stay_within_the_supported_filter_forms(self):
        for pattern in guard.LAYA_TETRIS_INPUTS:
            literal = pattern[:-3] if pattern.endswith('/**') else pattern
            self.assertNotRegex(literal, r'[*?\[\]!]', pattern)

    def test_superseded_verdict_names_main_and_bounds_the_path_list(self):
        deploy, title, message = guard.verdict(
            'chat-app', 'a' * 40, 'b' * 40, ['lib/a', 'lib/b', 'lib/c', 'lib/d', 'lib/e'])
        self.assertFalse(deploy)
        self.assertIn('superseded', title)
        self.assertIn('main is at ' + 'b' * 40, message)
        self.assertIn('lib/a, lib/b, lib/c and 2 more', message)
        self.assertNotIn('lib/d', message)


class HistoryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.origin = self.root / 'origin'
        self.origin.mkdir()
        self.git(self.origin, 'init', '-q', '-b', 'main')
        self.git(self.origin, 'config', 'user.name', 'Test')
        self.git(self.origin, 'config', 'user.email', 'test@example.invalid')
        self.commit({'lib/llamadart.dart': 'old', 'README.md': 'old'})
        self.deploy_sha = self.commit({'pubspec.yaml': 'version: 1.2.3', 'CHANGELOG.md': '1.2.3'})
        # The deploy jobs check out one revision without history or credentials.
        self.work = self.root / 'work'
        self.work.mkdir()
        self.git(self.work, 'init', '-q')
        self.git(self.work, 'remote', 'add', 'origin', self.origin.as_uri())
        self.git(self.work, 'fetch', '-q', '--no-tags', '--depth=1', 'origin', self.deploy_sha)
        self.git(self.work, 'checkout', '-q', '--detach', self.deploy_sha)

    def git(self, cwd, *args):
        return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()

    def commit(self, files):
        for name, content in files.items():
            path = self.origin / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.git(self.origin, 'add', '-A')
        self.git(self.origin, 'commit', '-qm', 'change')
        return self.git(self.origin, 'rev-parse', 'HEAD')

    def run_guard(self, demo, **extra):
        output, summary = self.root / 'output', self.root / 'summary'
        for path in (output, summary):
            path.write_text('')
        env = {name: value for name, value in os.environ.items() if name != 'GH_TOKEN'}
        env.update(DEPLOY_SHA=self.deploy_sha, GITHUB_OUTPUT=str(output),
                   GITHUB_STEP_SUMMARY=str(summary))
        env.update(extra)
        result = subprocess.run([sys.executable, str(ROOT / 'tool/ci/deploy_guard.py'), demo],
                                cwd=self.work, env=env, capture_output=True, text=True)
        return result, output.read_text(), summary.read_text()

    def test_tip_of_main_deploys(self):
        for demo in guard.DEMOS:
            result, output, summary = self.run_guard(demo)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output, 'deploy=true\n')
            self.assertNotIn('::', result.stdout)
            self.assertIn(self.deploy_sha, summary)

    def test_release_commit_still_deploys_after_the_docs_cut(self):
        cut = self.commit({name: 'snapshot' for name in DOCS_CUT})
        for demo in guard.DEMOS:
            # The stand-in token must not disturb a fetch from another host.
            result, output, summary = self.run_guard(demo, GH_TOKEN='not-a-real-token')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output, 'deploy=true\n')
            self.assertIn('::notice title=Deploying behind main::', result.stdout)
            self.assertIn(cut, result.stdout)
            self.assertIn(cut, summary)
            self.assertNotIn('not-a-real-token', result.stdout + result.stderr + summary)

    def test_newer_demo_input_supersedes_without_failing(self):
        self.commit({name: 'snapshot' for name in DOCS_CUT})
        newer = self.commit({'lib/llamadart.dart': 'new'})
        for demo in guard.DEMOS:
            result, output, summary = self.run_guard(demo)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output, 'deploy=false\n')
            self.assertIn('::notice title=Deploy skipped: superseded::', result.stdout)
            self.assertIn('main is at ' + newer, summary)
            self.assertIn('lib/llamadart.dart', summary)
            self.assertEqual(summary.count('\n'), 1)

    def test_input_changed_and_restored_after_the_build_still_deploys(self):
        # Git cannot tell one push from two: this may be one push that started no
        # deploy run, and the build matches main's inputs either way.
        self.commit({'lib/llamadart.dart': 'new'})
        self.commit({'lib/llamadart.dart': 'old'})
        self.assertEqual(self.git(self.origin, 'diff', '--name-only', self.deploy_sha, 'HEAD'), '')
        for demo in guard.DEMOS:
            result, output, _ = self.run_guard(demo)
            self.assertEqual(output, 'deploy=true\n', result.stderr)
            self.assertIn('::notice title=Deploying behind main::', result.stdout)

    def test_validation_package_change_supersedes_only_the_chat_app(self):
        self.commit({'packages/llamadart_validation/lib/src/runner.dart': 'new'})
        self.assertEqual(self.run_guard('chat-app')[1], 'deploy=false\n')
        self.assertEqual(self.run_guard('laya-tetris')[1], 'deploy=true\n')

    def fast_forward_main_to_branch_that_merged_it(self, files):
        self.git(self.origin, 'checkout', '-q', '-b', 'topic', self.deploy_sha + '~1')
        self.commit(files)
        self.git(self.origin, 'merge', '-q', '--no-ff', '--no-edit', 'main')
        self.git(self.origin, 'checkout', '-q', 'main')
        self.git(self.origin, 'merge', '-q', '--ff-only', 'topic')
        self.assertEqual(self.git(self.origin, 'rev-parse', 'HEAD^2'), self.deploy_sha)

    def test_fast_forward_to_a_branch_that_merged_main_compares_its_inputs(self):
        for history in ('shallow', 'full'):
            for files, deploy in (({'README.md': 'new'}, 'true'),
                                  ({'lib/llamadart.dart': 'new'}, 'false')):
                with self.subTest(history=history, files=files):
                    self.setUp()
                    if history == 'full':
                        self.git(self.work, 'fetch', '-q', '--unshallow', 'origin')
                    self.fast_forward_main_to_branch_that_merged_it(files)
                    for demo in guard.DEMOS:
                        result, output, _ = self.run_guard(demo)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(output, f'deploy={deploy}\n', (demo, result.stdout))

    def test_demo_specific_inputs_only_supersede_their_own_demo(self):
        self.commit({'example/chat_app/web/index.html': 'new'})
        self.assertEqual(self.run_guard('laya-tetris')[1], 'deploy=true\n')
        self.assertEqual(self.run_guard('chat-app')[1], 'deploy=false\n')

    def test_rename_out_of_an_input_directory_counts_as_an_input_change(self):
        self.git(self.origin, 'mv', 'lib/llamadart.dart', 'README.txt')
        self.git(self.origin, 'commit', '-qm', 'rename')
        self.assertEqual(self.run_guard('laya-tetris')[1], 'deploy=false\n')

    @unittest.skipIf(os.name == 'nt', 'Windows file names cannot hold a line break or colon')
    def test_path_text_cannot_issue_workflow_commands(self):
        self.commit({'lib/a\n::error::forged': 'new'})
        result, output, summary = self.run_guard('laya-tetris')
        self.assertEqual(output, 'deploy=false\n')
        self.assertEqual(result.stdout.count('\n'), 1)
        self.assertEqual(summary.count('\n'), 1)

    def test_revision_main_no_longer_contains_fails_closed(self):
        self.git(self.origin, 'reset', '-q', '--hard', 'HEAD~1')
        self.commit({'README.md': 'rewritten'})
        result, output, _ = self.run_guard('chat-app')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, '')
        self.assertIn('::error title=Deploy guard failed::', result.stderr)
        self.assertIn('does not contain ' + self.deploy_sha, result.stderr)

    def test_unreadable_main_and_bad_arguments_fail_closed(self):
        for demo, extra in [('unknown-demo', {}), ('chat-app', dict(DEPLOY_SHA='main'))]:
            result, output, _ = self.run_guard(demo, **extra)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output, '')
        self.git(self.work, 'remote', 'set-url', 'origin', (self.root / 'missing').as_uri())
        result, output, _ = self.run_guard('laya-tetris')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, '')
        self.assertIn('::error title=Deploy guard failed::', result.stderr)


if __name__ == '__main__':
    unittest.main()
