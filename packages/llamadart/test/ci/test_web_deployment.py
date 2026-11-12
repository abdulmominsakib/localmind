"""Behavioral checks for the production artifact boundary and preview policy."""
import copy
import hashlib
import importlib.util
import functools
import threading
import urllib.request
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tool/ci'))
import web_deployment as guard


class DeploymentTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.args = dict(artifact_id=11, digest='a' * 64, run_id=22,
                         sha='b' * 40, repository_id=33)
        self.metadata = dict(id=11, expired=False, digest='sha256:' + 'a' * 64,
                             workflow_run=dict(id=22, head_sha='b' * 40,
                                               head_branch='main', repository_id=33,
                                               head_repository_id=33))

    def test_metadata_requires_exact_identity(self):
        guard.verify_artifact(self.metadata, **self.args)
        for field, value in [('id', 12), ('expired', True), ('digest', 'sha256:'+'c'*64)]:
            with self.subTest(field=field):
                metadata = copy.deepcopy(self.metadata)
                metadata[field] = value
                with self.assertRaises(ValueError):
                    guard.verify_artifact(metadata, **self.args)
        for field, value in [('id', 23), ('head_sha', 'c'*40), ('head_branch', 'topic'),
                             ('repository_id', 34), ('head_repository_id', 34)]:
            with self.subTest(field=field):
                metadata = copy.deepcopy(self.metadata)
                metadata['workflow_run'][field] = value
                with self.assertRaises(ValueError):
                    guard.verify_artifact(metadata, **self.args)
        with self.assertRaises(ValueError):
            guard.verify_artifact({}, **self.args)

    def archive(self, entries, *, root=None):
        archive = (root or self.root) / 'artifact.zip'
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(archive, 'w') as bundle:
                for name, content in entries:
                    if isinstance(name, str):
                        item = zipfile.ZipInfo(name)
                        # Preserve deliberately unsafe names in both ZIP headers,
                        # bypassing ZipInfo's Windows and NUL normalization.
                        item.filename = name
                    else:
                        item = name
                    bundle.writestr(item, content)
        return archive, hashlib.sha256(archive.read_bytes()).hexdigest()

    def test_extract_preserves_bytes_and_rejects_tampering(self):
        archive, digest = self.archive([('assets/data', b'\x00\xff'), ('index.html', 'app')])
        guard.extract_artifact(archive, self.root / 'out', digest)
        self.assertEqual(sorted(path.relative_to(self.root / 'out').as_posix()
                                for path in (self.root / 'out').rglob('*')
                                if path.is_file()), ['assets/data', 'index.html'])
        self.assertEqual((self.root / 'out/assets/data').read_bytes(), b'\x00\xff')
        self.assertEqual((self.root / 'out/index.html').read_text(), 'app')
        with self.assertRaises(ValueError):
            guard.extract_artifact(archive, self.root / 'out', digest)
        with archive.open('ab') as stream:
            stream.write(b'tamper')
        with self.assertRaises(ValueError):
            guard.extract_artifact(archive, self.root / 'tampered', digest)
        self.assertFalse((self.root / 'tampered').exists())

    def test_unsafe_archive_never_extracts_partial_files(self):
        link = zipfile.ZipInfo('link')
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        for entries in [[('../escape', '')], [('/absolute', '')], [('a\\b', '')],
                        [('C:drive', '')], [('a/../b', '')], [('a//b', '')],
                        [('a/./b', '')], [('same', ''), ('same', '')], [('same/', ''), ('same', '')], [(link, 'target')]]:
            with (self.subTest(entries=entries),
                  tempfile.TemporaryDirectory(dir=self.root) as temp):
                root = Path(temp)
                archive, digest = self.archive([('innocent', 'ok'), *entries], root=root)
                with self.assertRaises(ValueError):
                    guard.extract_artifact(archive, root / 'unsafe', digest)
                self.assertFalse((root / 'unsafe').exists())

    def test_raw_names_are_rejected_before_platform_normalization_can_hide_them(self):
        for sep in ['/', '\\']:
            for name in ['a\\b', 'a\x00b']:
                with (self.subTest(sep=sep, name=name),
                      tempfile.TemporaryDirectory(dir=self.root) as temp):
                    root = Path(temp)
                    with (mock.patch.object(zipfile.os, 'sep', sep),
                          mock.patch.object(zipfile.os, 'altsep', None)):
                        archive, digest = self.archive([('innocent', 'ok'), (name, 'bad')], root=root)
                        # The local and central headers must both contain the raw
                        # name; a normalized writer would erase the regression.
                        self.assertEqual(archive.read_bytes().count(name.encode()), 2)
                        with zipfile.ZipFile(archive) as bundle:
                            self.assertEqual(bundle.infolist()[1].orig_filename, name)
                        with self.assertRaisesRegex(ValueError, 'Unsafe or duplicate'):
                            guard.extract_artifact(archive, root / 'unsafe', digest)
                    self.assertFalse((root / 'unsafe').exists())

    def test_build_configuration_requires_production_and_exact_source(self):
        metadata = dict(commit='sha', tree='tree', base_href='/',
                        target='lib/main.dart', flutter_version='3.47.1')
        (self.root / 'index.html').write_text('<base href="/">')
        stamp = self.root / 'llamadart-build.json'
        stamp.write_text(json.dumps(metadata))
        guard.verify_build(self.root, 'sha', 'tree', '3.47.1')
        for field in metadata:
            with self.subTest(field=field):
                stamp.write_text(json.dumps({**metadata, field: 'wrong'}))
                with self.assertRaises(ValueError):
                    guard.verify_build(self.root, 'sha', 'tree', '3.47.1')
        stamp.write_text(json.dumps(metadata))
        (self.root / 'index.html').write_text('<base href="/test/">')
        with self.assertRaises(ValueError):
            guard.verify_build(self.root, 'sha', 'tree', '3.47.1')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()

    def test_real_build_stamp_is_compatible_with_deployment_verifier(self):
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.root / '.flutter-version').write_text('3.47.1')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        sha = self.git('rev-parse', 'HEAD')
        # Execute the actual build-script stamp code, replacing only SDK discovery.
        source = (ROOT/'scripts/build_chat_app_web.sh').read_text().split("<<'PYTHON'\n", 1)[1].split('\nPYTHON', 1)[0]
        code = "import subprocess\nreal = subprocess.check_output\nsubprocess.check_output = lambda args, **kwargs: '{\"frameworkVersion\":\"3.47.1\"}' if args[0] == 'flutter' else real(args, **kwargs)\n" + source
        stamp = self.root/'llamadart-build.json'
        env = dict(os.environ, CHAT_APP_BUILD_SHA=sha, CHAT_APP_BUILD_BASE_HREF='/', CHAT_APP_BUILD_TARGET='lib/main.dart')
        result = subprocess.run([sys.executable, '-c', code, str(stamp), str(self.root)],
                                cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('"commit":"' + sha + '"', stamp.read_text())
        self.assertEqual(json.loads(stamp.read_text())['tree'], self.git('rev-parse', 'HEAD^{tree}'))
        (self.root/'.flutter-version').write_text('changed')
        result = subprocess.run([sys.executable, '-c', code, str(stamp), str(self.root)],
                                cwd=self.root, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)

    def test_cli_accepts_same_run_main_and_rejects_pr_fork_or_wrong_checkout(self):
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.root / '.flutter-version').write_text('3.47.1\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        sha, tree = self.git('rev-parse', 'HEAD'), self.git('rev-parse', 'HEAD^{tree}')
        build = dict(commit=sha, tree=tree, base_href='/', target='lib/main.dart',
                     flutter_version='3.47.1')
        archive, digest = self.archive([('index.html', '<base href="/">'),
                                        ('llamadart-build.json', json.dumps(build))])
        archive.rename(self.root / 'web-artifact.zip')
        self.metadata['digest'] = 'sha256:' + digest
        self.metadata['workflow_run']['head_sha'] = sha
        (self.root / 'web-artifact.json').write_text(json.dumps(self.metadata))
        event = self.root / 'event.json'
        event.write_text(json.dumps({'repository': {'full_name': 'leehack/llamadart', 'fork': False}}))
        env = dict(os.environ, GITHUB_EVENT_PATH=str(event), GITHUB_EVENT_NAME='push',
                   GITHUB_REF='refs/heads/main', GITHUB_REPOSITORY='leehack/llamadart',
                   ARTIFACT_ID='11', ARTIFACT_DIGEST=digest, GITHUB_RUN_ID='22',
                   GITHUB_SHA=sha, GITHUB_REPOSITORY_ID='33')
        def run(extra):
            return subprocess.run([sys.executable, str(ROOT/'tool/ci/web_deployment.py'), 'verify'],
                                  cwd=self.root, env={**env, **extra}, capture_output=True, text=True)
        dispatch = dict(GITHUB_EVENT_NAME='workflow_dispatch')
        for extra in [dict(GITHUB_EVENT_NAME='pull_request'), dict(GITHUB_EVENT_NAME='workflow_run'),
                      dict(GITHUB_REF='refs/heads/topic'), dict(dispatch, GITHUB_REF='refs/heads/topic'),
                      dict(GITHUB_REPOSITORY='fork/llamadart'), dict(GITHUB_SHA='c'*40),
                      dict(dispatch, GITHUB_RUN_ID='23')]:
            self.assertNotEqual(run(extra).returncode, 0, extra)
            self.assertFalse((self.root / 'web-artifact').exists())
        for extra in [{}, dispatch]:
            result = run(extra)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((self.root / 'web-artifact/index.html').read_text(), '<base href="/">')
            shutil.rmtree(self.root / 'web-artifact')


class PreviewTest(unittest.TestCase):
    def setUp(self):
        self.event = dict(action='synchronize', repository=dict(full_name='leehack/llamadart'),
                          pull_request=dict(draft=False, labels=[], user=dict(login='maintainer'),
                                            head=dict(repo=dict(full_name='leehack/llamadart'))))

    def test_relevance_and_conservative_unknown(self):
        for path in ['doc/ci_selection.md', 'example/chat_app/android/app/build.gradle.kts']:
            self.assertEqual(guard.preview_action(self.event, [path]), 'skip', path)
        for path in ['example/chat_app/lib/main.dart', 'lib/llamadart.dart', 'new-unknown-input']:
            self.assertEqual(guard.preview_action(self.event, [path]), 'build', path)
        self.assertEqual(guard.preview_action(self.event, []), 'build')

    def test_draft_opt_in_and_unfiltered_cleanup(self):
        self.event['pull_request']['draft'] = True
        self.assertEqual(guard.preview_action(self.event, ['lib/llamadart.dart']), 'skip')
        self.event['pull_request']['labels'] = [dict(name='preview')]
        self.assertEqual(guard.preview_action(self.event, ['README.md']), 'build')
        self.event['pull_request']['labels'] = []
        self.event['action'] = 'closed'
        self.assertEqual(guard.preview_action(self.event, ['README.md']), 'cleanup')
        self.event['pull_request']['head']['repo']['full_name'] = 'fork/repo'
        self.assertEqual(guard.preview_action(self.event, []), 'skip')
        self.event['pull_request']['head']['repo']['full_name'] = 'leehack/llamadart'
        self.event['pull_request']['user']['login'] = 'dependabot[bot]'
        self.assertEqual(guard.preview_action(self.event, []), 'skip')

    def test_unrelated_labels_never_request_a_build(self):
        for action in ['labeled', 'unlabeled']:
            self.event['action'] = action
            self.event['label'] = dict(name='unrelated')
            self.assertEqual(guard.preview_action(self.event, ['lib/llamadart.dart']), 'skip')
            self.event['label'] = dict(name='preview')
            self.assertEqual(guard.preview_action(self.event, ['lib/llamadart.dart']), 'build')

    def test_missing_git_history_does_not_emit_build_or_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.event['pull_request']['head']['sha'] = 'a'*40
            self.event['pull_request']['base'] = dict(sha='b'*40)
            (root/'event.json').write_text(json.dumps(self.event))
            result = subprocess.run([sys.executable, str(ROOT/'tool/ci/web_deployment.py'), 'preview'],
                                    cwd=root, env=dict(os.environ, GITHUB_EVENT_PATH=str(root/'event.json'),
                                                       GITHUB_OUTPUT=str(root/'output')),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root/'output').exists())


class ProductionServerTest(unittest.TestCase):
    def test_cross_origin_model_range_has_cors_and_app_matches_hf_isolation(self):
        spec = importlib.util.spec_from_file_location('static', ROOT/'tool/testing/serve_static_with_headers.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temp:
            Path(temp, 'model.gguf').write_bytes(b'0123456789')
            module.CoiStaticHandler.cors_origin = 'http://127.0.0.1:7358'
            module.CoiStaticHandler.coep = 'require-corp'
            handler = functools.partial(module.CoiStaticHandler, directory=temp)
            with module.ThreadingTcpServer(('127.0.0.1', 0), handler) as server:
                thread = threading.Thread(target=server.serve_forever)
                thread.start()
                try:
                    request = urllib.request.Request(f'http://127.0.0.1:{server.server_address[1]}/model.gguf',
                                                     headers={'Range': 'bytes=2-4', 'Origin': 'http://127.0.0.1:7358'})
                    with urllib.request.urlopen(request) as response:
                        self.assertEqual(response.status, 206)
                        self.assertEqual(response.read(), b'234')
                        self.assertEqual(response.headers['Access-Control-Allow-Origin'], 'http://127.0.0.1:7358')
                        self.assertEqual(response.headers['Cross-Origin-Embedder-Policy'], 'require-corp')
                        self.assertEqual(response.headers['Cross-Origin-Resource-Policy'], 'cross-origin')
                finally:
                    server.shutdown()
                    thread.join()


if __name__ == '__main__':
    unittest.main()
