"""Model-free raw-channel checks; execute only under the run's operator authority."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parent
LOGS = b'INFO: Loaded OpenCL library with dlopen.\nvendor stderr\nvendor cout\n'


class ProtocolOutputTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='s24-protocol-output-')
        compiler = shutil.which('clang++') or shutil.which('c++')
        if not compiler:
            raise unittest.SkipTest('C++17 compiler unavailable')
        cls.fixture = Path(cls.temp.name) / 'protocol-output'
        subprocess.run([compiler, '-std=c++17', '-O2', '-Wall', '-Wextra',
                        str(ROOT / 'protocol_output_fixture.cpp'), '-o', str(cls.fixture)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_fixture(self, mode):
        return subprocess.run([str(self.fixture), mode], capture_output=True, timeout=5)

    def test_vendor_channels_remain_raw_stderr_and_protocol_is_exclusive(self):
        result = self.run_fixture('channels')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, LOGS)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([row['event'] for row in rows], ['started', 'finished'])
        self.assertEqual([row['sequence'] for row in rows], [0, 1])
        self.assertTrue(all(row['schema'] == 1 and row['binding'] == 'fixture-binding'
                            and row['case_id'] == 'fixture-case' and row['pid'] > 0 for row in rows))
        self.assertEqual(rows[0]['pid'], rows[1]['pid'])

    def test_actual_probe_requires_no_runtime_and_emits_only_two_records(self):
        result = self.run_fixture('probe')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b'')
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([row['event'] for row in rows], ['started', 'finished'])
        self.assertEqual([row['sequence'] for row in rows], [0, 1])
        self.assertEqual(rows[0]['mode'], 'probe')
        self.assertTrue(rows[1]['model_free_launch'])

    def test_unavailable_descriptors_fail_without_success(self):
        for mode in ('closed-stdout', 'closed-stderr', 'broken-protocol'):
            with self.subTest(mode=mode):
                result = self.run_fixture(mode)
                self.assertEqual(result.returncode, 74)
                rows = [json.loads(line) for line in result.stdout.splitlines()]
                self.assertFalse(any(row['event'] == 'finished' for row in rows))


if __name__ == '__main__':
    unittest.main()
