"""Fabricated consolidated/split observations and archives, never real providers."""
import copy
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

import verify as v
from test_compare_macho_identity import fixture
from test_qualification import observations, split_observations


def records(text):
    return [(line.split(' ', 1)[0], json.loads(line.split(' ', 1)[1])) for line in text.splitlines()]


def emit(rows):
    return ''.join(prefix + ' ' + json.dumps(value) + '\n' for prefix, value in rows)


class ConsolidatedAppleControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def test_consolidated_positive_binds_actual_asset_model_registry_and_query_owners(self):
        text = observations(self.root)
        modules, identity = v.native_modules(text, 'macos-arm64')
        v.query_result(v.public_result(text), modules, 'v0.8.0-2')
        self.assertEqual(1, len(modules))
        self.assertEqual('package:llamadart/llamadart', identity['codeAssetId'])
        self.assertEqual([], identity['primaryRegistryImports'])
        self.assertEqual('consolidated-apple', identity['runtimeLayout'])
        self.assertEqual(identity['codeAssetOwner']['sha256'], next(iter(modules.values()))['sha256'])

    def test_windows_split_relation_stays_required_and_cannot_qualify_as_mac(self):
        text = split_observations(self.root)
        v.native_modules(text, 'windows-x64')
        with self.assertRaisesRegex(v.Refusal, 'exactly one'):
            v.native_modules(text, 'macos-arm64')
        rows = records(text)
        skewed = copy.deepcopy(rows)
        skewed[-1][1]['primaryRegistryImports'][0]['address'] += 1
        with self.assertRaisesRegex(v.Refusal, 'addresses disagree'):
            v.native_modules(emit(skewed), 'windows-x64')
        with self.assertRaisesRegex(v.Refusal, 'incomplete native provider map'):
            v.native_modules(emit(rows[1:]), 'windows-x64')
        with self.assertRaisesRegex(v.Refusal, 'incomplete native provider map'):
            v.native_modules(observations(self.root), 'windows-x64')

    def test_missing_duplicate_or_foreign_self_export_fails_even_in_first_snapshot(self):
        original = records(observations(self.root))
        for symbol in v.MAC_SYMBOLS:
            for mode in ('missing', 'duplicate', 'foreign', 'base', 'null'):
                with self.subTest(symbol=symbol, mode=mode):
                    rows = copy.deepcopy(original)
                    exports = rows[0][1]['exports']
                    row = next(item for item in exports if item['symbol'] == symbol)
                    if mode == 'missing': exports.remove(row)
                    elif mode == 'duplicate': exports.append(dict(row))
                    elif mode == 'foreign': row['ownerPath'] = '/foreign/libllamadart.dylib'
                    elif mode == 'base': row['ownerBase'] += 1
                    else: row['address'] = 0
                    with self.assertRaises(v.Refusal):
                        v.native_modules(emit(rows), 'macos-arm64')

    def test_extra_mixed_unknown_or_incomplete_native_images_fail(self):
        original = records(observations(self.root))
        for name in ('libggml.dylib', 'libllama.dylib', 'libmtmd.dylib'):
            rows = copy.deepcopy(original)
            row = copy.deepcopy(rows[0][1]); row['modulePath'] = str(self.root / name)
            rows.insert(1, ('PASSIVE_MODULE', row))
            with self.subTest(name=name), self.assertRaisesRegex(v.Refusal, 'exactly one'):
                v.native_modules(emit(rows), 'macos-arm64')
        with self.assertRaisesRegex(v.Refusal, 'before/after'):
            v.native_modules(emit([row for row in original if row[1].get('checkpoint') != 'after-registry-observation']),
                             'macos-arm64')
        rows = copy.deepcopy(original)
        for prefix, row in rows:
            if prefix == 'PASSIVE_MODULE':
                row['modulePath'] = str(self.root / 'libllama.dylib')
        with self.assertRaisesRegex(v.Refusal, 'provider name'):
            v.native_modules(emit(rows), 'macos-arm64')

    def test_wrong_asset_relation_hash_address_and_fabricated_import_fail(self):
        original = records(observations(self.root))
        mutations = [
            lambda row: row.update(codeAssetId='package:llamadart/ggml'),
            lambda row: row.update(runtimeLayout='split'),
            lambda row: row.update(primaryRegistryImports=[row['primaryRegistryExport']]),
            lambda row: row.update(codeAssetAddress=row['codeAssetAddress'] + 1),
            lambda row: row['codeAssetOwner'].update(ownerPath='/foreign/libllamadart.dylib'),
            lambda row: row['codeAssetOwner'].update(sha256='0' * 64),
            lambda row: row['modelCodeAsset'].update(assetId='package:llamadart/ggml'),
            lambda row: row['modelCodeAsset'].update(address=1),
            lambda row: row['modelCodeAsset'].update(ownerBase=1),
            lambda row: row['modelCodeAsset'].update(sha256='0' * 64),
            lambda row: row.update(distinctRegistryProviderBasesBefore=2),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                rows = copy.deepcopy(original)
                mutate(next(row for prefix, row in rows if prefix == 'REGISTRY_IDENTITY'))
                with self.assertRaises(v.Refusal):
                    v.native_modules(emit(rows), 'macos-arm64')

    def test_nextn_address_base_or_foreign_owner_skew_fails(self):
        text = observations(self.root)
        modules, _ = v.native_modules(text, 'macos-arm64')
        result = v.public_result(text)
        for key, value in (('nextnAddress', 1), ('nextnOwnerBase', 1),
                           ('nextnOwnerPath', '/foreign/libllamadart.dylib')):
            with self.subTest(key=key):
                changed = copy.deepcopy(result); changed['query'][key] = value
                with self.assertRaises(v.Refusal):
                    v.query_result(changed, modules, 'v0.8.0-2')

    def make_archive(self, names, target='macos-arm64'):
        tag = 'v0.8.0-2'
        directory = self.root / tag / target; directory.mkdir(parents=True, exist_ok=True)
        path = directory / f'llamadart-native-{target}-{tag}.tar.gz'
        with tarfile.open(path, 'w:gz') as archive:
            for name in names:
                row = tarfile.TarInfo(name); row.size = len(fixture())
                archive.addfile(row, io.BytesIO(fixture()))
        return tag, target, {target: v.sha256(path)}

    def test_windows_archive_still_requires_split_native_members(self):
        tag, target, expected = self.make_archive(['llamadart.dll', 'llama.dll', 'ggml.dll'], 'windows-x64')
        _, members = v.archive_members(self.root, tag, target, expected)
        self.assertEqual(3, len(members))
        tag, target, expected = self.make_archive(['llamadart.dll', 'llama.dll'], 'windows-x64')
        with self.assertRaisesRegex(v.Refusal, 'incomplete verified native archive'):
            v.archive_members(self.root, tag, target, expected)

    def test_exact_verified_single_root_member_is_accepted_for_mac(self):
        tag, target, expected = self.make_archive(['./libllamadart.dylib'])
        acquired, members = v.archive_members(self.root, tag, target, expected)
        self.assertEqual({'macos-arm64'}, set(acquired))
        self.assertEqual({'libllamadart.dylib'}, set(members))

    def test_extra_missing_nested_or_split_raw_members_are_refused(self):
        cases = ([], ['./libllamadart.dylib', './libggml.dylib'],
                 ['./libllamadart.dylib', './unexpected.txt'], ['lib/libllamadart.dylib'],
                 ['./libllama.dylib', './libggml.dylib', './libllamadart.dylib'])
        for names in cases:
            with self.subTest(names=names):
                tag, target, expected = self.make_archive(names)
                with self.assertRaises(v.Refusal):
                    v.archive_members(self.root, tag, target, expected)
        tag, target, expected = self.make_archive(['./libllamadart.dylib'])
        expected['macos-arm64-unexpected'] = '0' * 64
        with self.assertRaisesRegex(v.Refusal, 'sidecar'):
            v.archive_members(self.root, tag, target, expected)


if __name__ == '__main__':
    unittest.main()
