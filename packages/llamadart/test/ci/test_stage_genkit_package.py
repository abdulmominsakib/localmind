"""Exercise the same package staging used by CI and the publisher."""
from pathlib import Path
import os
import runpy
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
stage = runpy.run_path(str(ROOT / 'tool/release/stage_genkit_package.py'))['stage']


class StageTest(unittest.TestCase):
    def test_copy_keeps_api_guides_license_and_skills_but_never_local_state(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'source'
            source.mkdir()
            expected = ['pubspec.yaml', 'README.md', 'CHANGELOG.md', 'LICENSE',
                        'lib/genkit_llamadart.dart', 'skills/guide/SKILL.md', 'doc/usage.md',
                        'test/test.dart', 'example/main.dart']
            excluded = ['pubspec_overrides.yaml', 'pubspec.lock', '.github/workflows/publish.yml',
                        '.dart_tool/assets.dill', 'build/output', 'coverage/lcov.info', 'run.log']
            for name in expected + excluded:
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('content of ' + name)
            target = stage(source, Path(folder) / 'staged')
            self.assertEqual(sorted(p.relative_to(target).as_posix() for p in target.rglob('*') if p.is_file()),
                             sorted(expected))
            for name in expected:
                self.assertEqual((target / name).read_bytes(), (source / name).read_bytes())
            self.assertTrue((source / 'pubspec_overrides.yaml').exists())

    def test_refuses_existing_and_nested_destinations(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'source'
            source.mkdir()
            for name in ('pubspec.yaml', 'README.md', 'CHANGELOG.md', 'LICENSE'):
                (source / name).write_text(name)
            for target in (source, source / 'nested', Path(folder)):
                with self.assertRaises(ValueError):
                    stage(source, target)

    @unittest.skipIf(os.name == 'nt', 'Windows symlink fixtures require elevation')
    def test_refuses_symlink_sources_before_copying(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'source'
            source.mkdir()
            for name in ('pubspec.yaml', 'README.md', 'CHANGELOG.md', 'LICENSE'):
                (source / name).write_text(name)
            (source / 'escaped').symlink_to(Path(folder) / 'outside')
            with self.assertRaises(ValueError):
                stage(source, Path(folder) / 'staged')
            self.assertFalse((Path(folder) / 'staged').exists())
