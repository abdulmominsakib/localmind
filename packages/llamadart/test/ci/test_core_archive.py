"""Pub inventory parsing and missing/checkout-only package controls."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    'check_core_archive', ROOT / 'tool/release/check_core_archive.py')
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)


class CoreArchiveTest(unittest.TestCase):
    def test_fixture_log_exceptions_do_not_unignore_other_logs(self):
        prefix = 'packages/llamadart_validation/native/android_litert/fixtures/dart_transport/'
        manifest = json.loads((ROOT / prefix / 'manifest.json').read_text())
        fixture_logs = [prefix + path for path in manifest if path.endswith('/stderr.log')]
        self.assertTrue(fixture_logs)
        unrelated = ['runtime.log', prefix + 'unicode-0085/s24.native.launch/runtime.log',
                     prefix + 'unicode-0085/s24.native.other/stderr.log',
                     prefix + 'unicode-2030/s24.native.launch/stderr.log']
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            (root / '.gitignore').write_text((ROOT / '.gitignore').read_text())
            excludes = root / 'empty-global-ignore'
            excludes.write_text('')
            subprocess.run(['git', 'init', '-q'], cwd=root, check=True)
            command = ['git', '-c', 'core.excludesFile=' + str(excludes),
                       'check-ignore', '--no-index', '--stdin']
            result = subprocess.run(command, cwd=root, input='\n'.join(fixture_logs) + '\n',
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertEqual(result.stdout, '')
            result = subprocess.run(command, cwd=root, input='\n'.join(unrelated) + '\n',
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(set(result.stdout.splitlines()), set(unrelated))

    def test_inventory_comes_from_pub_and_preserves_nested_files(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch).resolve()
            for path in ('pubspec.yaml', 'lib/llamadart.dart'):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('source')
            output = ('noise\nFINE: Creating .tar.gz stream containing:\n'
                      f'    | {root}/.\n    | {root}/pubspec.yaml\n'
                      f'    | {root}/lib\n    | {root}/lib/llamadart.dart\n'
                      'MSG : Validating package...\n')
            self.assertEqual(archive.archive_files(output, root),
                             ['pubspec.yaml', 'lib/llamadart.dart'])
            for bad in (output.replace('Creating .tar.gz stream containing:', 'changed'),
                        output.replace(f'{root}/lib/llamadart.dart', '/outside/lib.dart'),
                        output.replace(f'{root}/lib/llamadart.dart', 'relative/lib.dart'),
                        output.replace(f'    | {root}/lib/llamadart.dart\n', ''),
                        output + output):
                with self.subTest(bad=bad), self.assertRaises(ValueError):
                    archive.archive_files(bad, root)

    def test_private_harness_and_chat_must_both_be_absent(self):
        valid = ['pubspec.yaml', 'lib/llamadart.dart', 'hook/build.dart',
                 'example/basic_app/pubspec.yaml',
                 'example/basic_app/bin/llamadart_litert_embedding_example.dart']
        self.assertEqual(archive.archive_errors(valid), [])
        for path in ('packages/llamadart_validation/lib/llamadart_validation.dart',
                     'example/chat_app/pubspec.yaml',
                     'packages/genkit_llamadart/pubspec.yaml',
                     'packages/llamadart_model_store/pubspec.yaml'):
            self.assertTrue(archive.archive_errors(valid + [path]), path)
        for path in valid:
            self.assertTrue(archive.archive_errors([p for p in valid if p != path]), path)

    def test_production_check_rejects_private_files_before_resolving_consumers(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch).resolve()
            files = ['pubspec.yaml', 'lib/llamadart.dart', 'hook/build.dart',
                     'example/basic_app/pubspec.yaml',
                     'example/basic_app/bin/llamadart_litert_embedding_example.dart',
                     'packages/llamadart_validation/pubspec.yaml']
            for path in files:
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('source')
            output = 'FINE: Creating .tar.gz stream containing:\n' + ''.join(
                '    | %s\n' % (root / path) for path in files)
            with patch.object(archive.subprocess, 'run', return_value=SimpleNamespace(
                    returncode=0, stdout=output, stderr='')) as run:
                with self.assertRaisesRegex(ValueError, 'checkout-only files'):
                    archive.check(root)
                self.assertEqual(run.call_count, 1)

    def test_production_check_propagates_pub_and_consumer_failures(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch).resolve()
            files = ['pubspec.yaml', 'lib/llamadart.dart', 'hook/build.dart',
                     'example/basic_app/pubspec.yaml',
                     'example/basic_app/bin/llamadart_litert_embedding_example.dart']
            for path in files:
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('source')
            output = 'FINE: Creating .tar.gz stream containing:\n' + ''.join(
                '    | %s\n' % (root / path) for path in files)
            failure = SimpleNamespace(returncode=65, stdout='expected failure', stderr='')
            success = SimpleNamespace(returncode=0, stdout=output, stderr='')
            with patch.object(archive.subprocess, 'run', return_value=failure):
                with self.assertRaisesRegex(RuntimeError, 'pub dry-run failed'):
                    archive.check(root)
            # Keep every later command available: bypassing failure handling
            # must fail assertRaises, not exhaust the mock's response list.
            with patch.object(archive.subprocess, 'run',
                              side_effect=[success, failure, failure, failure, failure]):
                with self.assertRaisesRegex(RuntimeError, 'consumer failed'):
                    archive.check(root)

    def test_pub_failure_preserves_bounded_diagnostic_tails(self):
        failure = SimpleNamespace(
            returncode=65,
            stdout='discarded stdout prefix\n' + 'x' * 20000 + '\nSDK stdout cause',
            stderr='discarded stderr prefix\n' + 'y' * 20000 + '\nSDK stderr cause')
        with patch.object(archive.subprocess, 'run', return_value=failure) as run:
            with self.assertRaises(RuntimeError) as raised:
                archive.check(ROOT)
        message = str(raised.exception)
        self.assertIn('exit 65', message)
        self.assertIn('SDK stdout cause', message)
        self.assertIn('SDK stderr cause', message)
        self.assertNotIn('discarded stdout prefix', message)
        self.assertNotIn('discarded stderr prefix', message)
        self.assertLess(len(message), 34000)
        self.assertEqual(run.call_count, 1)


if __name__ == '__main__':
    unittest.main()
