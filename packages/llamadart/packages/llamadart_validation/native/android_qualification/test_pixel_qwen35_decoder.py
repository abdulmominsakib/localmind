"""Model-free checks of collection admission and exact native-byte transport."""
import base64
import tempfile
from pathlib import Path
import unittest
import pixel_qwen35_decoder as d
import pixel_qwen35_decoder_fixtures as fixtures


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.canonical = self.root / d.COLLECTION_JOURNAL
        self.canonical.parent.mkdir(parents=True)
        self.raw = b'{"event":"unqualified fixture"}\n'
        self.canonical.write_bytes(self.raw)
        self.alias = self.canonical.parent / d.PRODUCER_RUN / 'journal.jsonl'

    def test_canonical_and_one_exact_known_alias(self):
        self.assertEqual(d.collection_journal(self.root), self.canonical)
        self.alias.parent.mkdir()
        self.alias.write_bytes(self.raw)
        self.assertEqual(d.collection_journal(self.root), self.canonical)
        self.alias.write_bytes(self.raw + b'\n')
        with self.assertRaises(ValueError):
            d.collection_journal(self.root)

    def test_foreign_extra_or_missing_canonical(self):
        foreign = self.root / 'foreign' / 'journal.jsonl'
        foreign.parent.mkdir()
        foreign.write_bytes(self.raw)
        with self.assertRaises(ValueError):
            d.collection_journal(self.root)
        self.canonical.unlink()
        with self.assertRaises(ValueError):
            d.collection_journal(self.root)

    def test_symlinks_and_size_bound(self):
        self.alias.parent.mkdir()
        self.alias.symlink_to(self.canonical)
        with self.assertRaises(ValueError):
            d.collection_journal(self.root)
        self.alias.unlink()
        with self.canonical.open('wb') as output:
            output.truncate(8 * 1024 * 1024 + 1)
        with self.assertRaises(ValueError):
            d.collection_journal(self.root)

    def test_exact_capture_and_corrupted_hash_or_length(self):
        raw = bytes([0, 255, 128, 13, 10])
        capture = {'base64': base64.b64encode(raw).decode(), 'bytes': len(raw), 'sha256': d.digest(raw)}
        self.assertEqual(d.capture(capture), raw)
        for field, value in [('bytes', 1), ('sha256', '0' * 64), ('base64', '!!!')]:
            with self.assertRaises(ValueError):
                d.capture({**capture, field: value})

    def test_native_proof_is_embedded_and_optional_raw_must_agree(self):
        raw = bytes([0, 255, 128, 13, 10])
        lock = {'schema': 'pixel-native-stderr.v1', 'file': 'cpu-original.stderr.log',
                'base64': base64.b64encode(raw).decode(), 'bytes': len(raw), 'sha256': d.digest(raw)}
        self.assertEqual(d.native_stderr(self.root, 'cpu-original', lock), raw)
        sibling = self.root / lock['file']
        sibling.write_bytes(raw)
        self.assertEqual(d.native_stderr(self.root, 'cpu-original', lock), raw)
        sibling.write_bytes(b'changed')
        with self.assertRaises(ValueError):
            d.native_stderr(self.root, 'cpu-original', lock)
        sibling.unlink()
        sibling.symlink_to(self.canonical)
        with self.assertRaises(ValueError):
            d.native_stderr(self.root, 'cpu-original', lock)
        for bad in [{k: v for k, v in lock.items() if k != 'schema'}, {**lock, 'file': '../foreign'}]:
            with self.assertRaises(ValueError):
                d.native_stderr(self.root, 'cpu-original', bad)


class CompleteReaderTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.binding_bytes = b'{"libraries":{"libllamadart.so":{},"libllama.so":{},"libggml-vulkan.so":{}}}'
        self.binding = d.loads(self.binding_bytes)
        self.app_sha = 'a' * 64
        self.sequence = 0

    def fixture(self):
        self.sequence += 1
        return fixtures.fixture(
            self.root / str(self.sequence), self.binding_bytes, self.app_sha)

    def decode(self, path, rows):
        fixtures.write(path, rows)
        return d.decode(path, self.binding, d.digest(self.binding_bytes), self.app_sha)

    def lifetime(self, rows, case):
        return next(r for r in rows
                    if r['event'] == 'lifetime_complete' and r['case_id'] == case)

    def capacity(self, rows, case, value):
        row = self.lifetime(rows, case)
        raw = d.capture(row['stderr'])
        old = row['observed_native_n_ubatch'][0]
        raw = raw.replace(f'n_ubatch = {old}\n'.encode(),
                          b'' if value is None else f'n_ubatch = {value}\n'.encode())
        row['stderr'].update(fixtures.cap(raw))
        row['observed_native_n_ubatch'] = [] if value is None else [value]

    def assert_semantic_failure(self, result, failure):
        self.assertIn(failure, result['raw_semantic_or_placement_failures'])
        self.assertFalse(result['supported_C04_pass'])
        self.assertFalse(result['restriction_assertions_pass'])
        self.assertFalse(result['all_current_cases_pass'])

    def test_default_native_capacity_512_with_prompt_cap_8(self):
        path, rows = self.fixture()
        self.assertEqual(self.lifetime(rows, 'gpu-default')['observed_native_n_ubatch'], [512])
        result = self.decode(path, rows)
        self.assertTrue(result['strict_raw_decode_complete'])
        self.assertEqual(result['lifetimes'], 17)
        self.assertEqual(len(result['case_statuses']), 41)
        self.assertEqual(list(result['case_statuses'].values()).count('PASS'), 39)
        self.assertEqual(list(result['case_statuses'].values()).count('FAIL'), 2)
        self.assertEqual(result['raw_semantic_or_placement_failures'], [])
        self.assertTrue(result['supported_C04_pass'])
        self.assertTrue(result['restriction_assertions_pass'])
        self.assertFalse(result['qualified'])

    def test_explicit_sizes_1_through_8_still_require_exact_capacity(self):
        for size in range(1, 9):
            with self.subTest(size=size):
                path, rows = self.fixture()
                case = f'gpu-size-{size}'
                self.capacity(rows, case, size + 1)
                self.assert_semantic_failure(self.decode(path, rows), case + '.actual-microbatch')

    def test_size_32_cpu_and_zero_layer_controls_still_require_exact_capacity(self):
        for case in ('cpu-size-32', 'vulkan-zero-layers-size-32'):
            with self.subTest(case=case):
                path, rows = self.fixture()
                self.capacity(rows, case, 512)
                self.assert_semantic_failure(self.decode(path, rows), case + '.actual-microbatch')

    def test_missing_native_capacity_still_fails_every_admitted_load(self):
        for case in [c for c in d.LIFETIMES if not c.startswith('gpu-refuse-')]:
            with self.subTest(case=case):
                path, rows = self.fixture()
                self.capacity(rows, case, None)
                self.assert_semantic_failure(self.decode(path, rows), case + '.actual-microbatch')

    def test_each_gpu_lifetime_still_requires_correct_cap_facts(self):
        for case in ['gpu-default'] + [f'gpu-size-{n}' for n in range(1, 9)]:
            for facts in ([], ['Android Vulkan text prompt decode is not capped (unknown)'],
                          ['Android Vulkan text prompt decode is capped at 7 tokens per call (unknown)']):
                with self.subTest(case=case, facts=facts):
                    path, rows = self.fixture()
                    self.lifetime(rows, case)['device_fact_logs'] = facts
                    self.assert_semantic_failure(self.decode(path, rows), case + '.actual-cap-facts')

    def test_each_gpu_lifetime_still_requires_positive_placement(self):
        for case in ['gpu-default'] + [f'gpu-size-{n}' for n in range(1, 9)]:
            with self.subTest(case=case):
                path, rows = self.fixture()
                row = self.lifetime(rows, case)
                raw = d.capture(row['stderr']).replace(b'offloaded 25/25', b'offloaded 0/25')
                row['stderr'].update(fixtures.cap(raw))
                row['positive_vulkan_placement'] = False
                self.assert_semantic_failure(self.decode(path, rows), case + '.actual-placement')

    def test_both_Cedar17_history_outputs_remain_strict_failures(self):
        path, rows = self.fixture()
        result = self.decode(path, rows)
        cases = ['cpu-original.C06.history', 'gpu-default.C06.history']
        self.assertEqual([r['content'] for r in rows if r['event'] == 'correctness_result'],
                         ['Cedar17', 'Cedar17'])
        self.assertEqual(result['correctness_failures'], cases)
        self.assertEqual([result['case_statuses'][c] for c in cases], ['FAIL', 'FAIL'])
        self.assertFalse(result['all_current_cases_pass'])
        for row in rows:
            if row['event'] == 'correctness_result':
                row['status'] = 'PASS'
        with self.assertRaisesRegex(ValueError, 'Strict C06 oracle mismatch'):
            self.decode(path, rows)

    def test_missing_actual_watchdog_completion_still_rejects_complete_journal(self):
        path, rows = self.fixture()
        (path.parent / 'watchdog.done').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing/unsafe producer file: watchdog.done'):
            self.decode(path, rows)

    def test_missing_terminal_remains_incomplete(self):
        path, rows = self.fixture()
        result = self.decode(path, rows[:-1])
        self.assertFalse(result['strict_raw_decode_complete'])
        self.assertFalse(result['supported_C04_pass'])
        self.assertFalse(result['restriction_assertions_pass'])
        self.assertFalse(result['all_current_cases_pass'])


if __name__ == '__main__':
    unittest.main()
