"""Exercise candidate-source lookup without weakening archive or score checks."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    'genkit_score', ROOT / 'tool/ci/check_genkit_package_score.py')
score = importlib.util.module_from_spec(spec)
spec.loader.exec_module(score)
RUN = subprocess.run


class CandidateScoreTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.folder = Path(self.scratch.name).resolve()
        self.root = self.folder / 'checkout'
        self.root.mkdir()
        self.package = self.folder / 'package'
        self.package.mkdir()
        self.git('init', '--quiet', '-b', 'main')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'commit.gpgsign', 'false')
        # Fixture bytes must survive Git checkout unchanged on Windows.
        self.git('config', 'core.autocrlf', 'false')
        self.metadata = self.root / score.PUBSPEC
        self.metadata.parent.mkdir(parents=True)
        self.metadata.write_text('name: genkit_llamadart\nversion: 3.4.0\n'
                                 'repository: https://github.com/leehack/genkit-llamadart\n')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'base')
        base = self.git('rev-parse', 'HEAD').strip()
        self.git('checkout', '--quiet', '-b', 'candidate')
        self.metadata.write_text('name: genkit_llamadart\nversion: 3.4.1\n'
                                 'repository: ' + score.CLONE_URL
                                 + '/tree/main/packages/genkit_llamadart\n')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'candidate')
        head = self.git('rev-parse', 'HEAD').strip()
        self.git('checkout', '--quiet', 'main')
        self.git('merge', '--quiet', '--no-ff', '-m', 'tested merge', 'candidate')
        self.merge = self.git('rev-parse', 'HEAD').strip()
        self.git('update-ref', 'refs/remotes/origin/main', 'main')
        (self.package / 'pubspec.yaml').write_bytes(self.metadata.read_bytes())
        self.event = {'repository': {'full_name': score.REPOSITORY}, 'pull_request': {
            'base': {'ref': 'main', 'sha': base, 'repo': {'full_name': score.REPOSITORY}},
            'head': {'sha': head, 'repo': {'full_name': score.REPOSITORY}}}}
        self.event_file = self.folder / 'event.json'
        self.env = dict(os.environ, GITHUB_EVENT_NAME='pull_request',
                        GITHUB_REPOSITORY=score.REPOSITORY, GITHUB_SHA=self.merge,
                        GITHUB_EVENT_PATH=str(self.event_file))
        for key in list(self.env):
            if key.startswith('GIT_CONFIG_'):
                del self.env[key]
        self.calls = []

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args],
                                       stderr=subprocess.PIPE).decode()

    def execute(self, callback=None, result=0):
        self.event_file.write_text(json.dumps(self.event))

        def run(command, **kwargs):
            if command != score.SCORE_COMMAND:
                return RUN(command, **kwargs)
            self.calls.append((command, kwargs))
            self.assertEqual(command[-2:], ['--exit-code-threshold', '0'])
            if callback:
                callback(kwargs['env'])
            return subprocess.CompletedProcess(command, result)

        with patch.object(score.subprocess, 'run', side_effect=run):
            return score.score(self.package, self.root, self.env)

    def test_candidate_lookup_uses_exact_merge_without_editing_archive_or_global_config(self):
        before = (self.package / 'pubspec.yaml').read_bytes()
        config = (self.root / '.git/config').read_bytes()
        environment = dict(self.env)

        def check(child):
            clone = self.folder / 'pana-source'
            RUN(['git', 'clone', '--quiet', score.CLONE_URL, str(clone)],
                env=child, check=True)
            actual = subprocess.check_output(['git', '-C', str(clone), 'rev-parse', 'HEAD'])
            self.assertEqual(actual.decode().strip(), self.merge)
            self.assertEqual((clone / score.PUBSPEC).read_bytes(), before)
            self.assertIn('version: 3.4.0', self.git('show',
                          self.event['pull_request']['base']['sha'] + ':' + score.PUBSPEC))

        self.assertEqual(self.execute(check), 0)
        self.assertEqual((self.package / 'pubspec.yaml').read_bytes(), before)
        self.assertEqual((self.root / '.git/config').read_bytes(), config)
        self.assertEqual(self.env, environment)
        mirror = self.calls[0][1]['env']['GIT_CONFIG_KEY_0']
        self.assertFalse(Path(mirror.removeprefix('url.file://')
                              .removesuffix('.insteadOf')).exists())

    def test_main_and_manual_runs_use_public_repository_and_preserve_score_failure(self):
        for event in ('push', 'workflow_dispatch'):
            with self.subTest(event=event):
                self.env['GITHUB_EVENT_NAME'] = event
                self.assertEqual(self.execute(result=127), 127)
                self.assertNotIn('GIT_CONFIG_COUNT', self.calls[-1][1]['env'])

    def test_fork_pr_uses_public_repository(self):
        self.event['pull_request']['head']['repo']['full_name'] = 'someone/fork'
        self.assertEqual(self.execute(), 0)
        self.assertNotIn('GIT_CONFIG_COUNT', self.calls[-1][1]['env'])

    def test_legacy_repository_keeps_public_lookup(self):
        # Rebuild only the fixture merge tree with the legacy repository field.
        self.metadata.write_text('name: genkit_llamadart\nversion: 3.4.1\n'
                                 'repository: https://github.com/leehack/genkit-llamadart\n')
        self.replace_merge_tree()
        self.assertEqual(self.execute(), 0)
        self.assertNotIn('GIT_CONFIG_COUNT', self.calls[-1][1]['env'])

    def replace_merge_tree(self):
        self.git('add', '.')
        tree = self.git('write-tree').strip()
        pr = self.event['pull_request']
        self.merge = self.git('commit-tree', tree, '-p', pr['base']['sha'],
                              '-p', pr['head']['sha'], '-m', 'fixture merge tree').strip()
        self.git('update-ref', 'HEAD', self.merge)
        self.env['GITHUB_SHA'] = self.merge
        (self.package / 'pubspec.yaml').write_bytes(self.metadata.read_bytes())

    def test_executable_manifest_blob_stops_before_pana(self):
        self.git('update-index', '--chmod=+x', score.PUBSPEC)
        tree = self.git('write-tree').strip()
        pr = self.event['pull_request']
        self.merge = self.git('commit-tree', tree, '-p', pr['base']['sha'],
                              '-p', pr['head']['sha'], '-m', 'fixture executable blob').strip()
        self.git('update-ref', 'HEAD', self.merge)
        self.env['GITHUB_SHA'] = self.merge
        with self.assertRaisesRegex(ValueError, 'regular Git blob'):
            self.execute()
        self.assertFalse(self.calls)

    def test_stale_checkout_or_event_revisions_stop_before_pana(self):
        for field in ('merge', 'base', 'head'):
            with self.subTest(field=field):
                if field == 'merge':
                    self.env['GITHUB_SHA'] = '1' * 40
                else:
                    self.event['pull_request'][field]['sha'] = '1' * 40
                with self.assertRaises(ValueError):
                    self.execute()
                self.assertFalse(self.calls)
                self.env['GITHUB_SHA'] = self.merge
                parents = self.git('show', '-s', '--format=%P', self.merge).split()
                self.event['pull_request']['base']['sha'] = parents[0]
                self.event['pull_request']['head']['sha'] = parents[1]

    def advance_base(self):
        """Merge candidate onto a base that moved after the PR recorded it."""
        pr = self.event['pull_request']
        head = pr['head']['sha']
        self.git('checkout', '--quiet', '-B', 'moved', pr['base']['sha'])
        (self.root / 'other.txt').write_text('main moved\n')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'main moved')
        moved = self.git('rev-parse', 'HEAD').strip()
        self.git('update-ref', 'refs/remotes/origin/main', moved)
        return moved, head

    def set_merge(self, tree_from, *parents):
        args = [item for parent in parents for item in ('-p', parent)]
        self.merge = self.git('commit-tree', self.git('rev-parse', tree_from + '^{tree}').strip(),
                              *args, '-m', 'fixture merge').strip()
        self.git('update-ref', 'HEAD', self.merge)
        self.env['GITHUB_SHA'] = self.merge

    def test_stale_recorded_base_that_is_an_ancestor_is_accepted(self):
        moved, head = self.advance_base()
        self.set_merge('main', moved, head)
        self.assertEqual(self.execute(), 0)

    def test_merge_with_wrong_head_is_rejected(self):
        moved, head = self.advance_base()
        self.set_merge('main', moved, moved)
        with self.assertRaisesRegex(ValueError, 'does not match GitHub PR base and head'):
            self.execute()
        self.assertFalse(self.calls)

    def test_first_parent_not_descending_from_recorded_base_is_rejected(self):
        moved, head = self.advance_base()
        orphan = self.git('commit-tree', self.git('rev-parse', 'main^{tree}').strip(),
                          '-m', 'unrelated').strip()
        self.git('update-ref', 'refs/remotes/origin/main', orphan)
        self.set_merge('main', orphan, head)
        with self.assertRaisesRegex(ValueError, 'does not match GitHub PR base and head'):
            self.execute()
        self.assertFalse(self.calls)

    def test_first_parent_outside_base_branch_is_rejected(self):
        moved, head = self.advance_base()
        self.git('update-ref', 'refs/remotes/origin/main', self.event['pull_request']['base']['sha'])
        self.set_merge('main', moved, head)
        with self.assertRaisesRegex(ValueError, 'does not match GitHub PR base and head'):
            self.execute()
        self.assertFalse(self.calls)

    def test_invalid_sha_or_repository_stops_before_pana(self):
        for value in ('0' * 40, 'not-a-sha', None):
            with self.subTest(value=value):
                self.env['GITHUB_SHA'] = value
                with self.assertRaises(ValueError):
                    self.execute()
        self.env['GITHUB_SHA'] = self.merge
        self.env['GITHUB_REPOSITORY'] = 'someone/other'
        with self.assertRaises(ValueError):
            self.execute()
        self.assertFalse(self.calls)

    def test_shallow_checkout_stops_before_pana(self):
        shallow = self.folder / 'shallow'
        RUN(['git', 'clone', '--quiet', '--depth', '1', self.root.as_uri(), str(shallow)],
            check=True)
        self.root = shallow
        with self.assertRaisesRegex(ValueError, 'fetch-depth: 0'):
            self.execute()
        self.assertFalse(self.calls)

    def test_modified_archive_manifest_stops_before_pana(self):
        (self.package / 'pubspec.yaml').write_text('name: another_package\n')
        with self.assertRaisesRegex(ValueError, 'Staged manifest differs'):
            self.execute()
        self.assertFalse(self.calls)

    @unittest.skipIf(os.name == 'nt', 'Windows symlinks require elevation')
    def test_symlink_archive_manifest_stops_before_pana(self):
        (self.package / 'pubspec.yaml').unlink()
        (self.package / 'pubspec.yaml').symlink_to(self.metadata)
        with self.assertRaisesRegex(ValueError, 'Staged manifest differs'):
            self.execute()
        self.assertFalse(self.calls)

    def test_candidate_score_failure_propagates_and_preserves_other_git_settings(self):
        self.env.update(GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='fetch.fsckObjects',
                        GIT_CONFIG_VALUE_0='true')
        self.assertEqual(self.execute(result=127), 127)
        child = self.calls[0][1]['env']
        self.assertEqual(child['GIT_CONFIG_COUNT'], '2')
        self.assertEqual(child['GIT_CONFIG_KEY_0'], 'fetch.fsckObjects')
        self.assertEqual(child['GIT_CONFIG_VALUE_1'], score.CLONE_URL)


if __name__ == '__main__':
    unittest.main()
