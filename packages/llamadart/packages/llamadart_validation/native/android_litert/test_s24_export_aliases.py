"""Source-only admission of retained Dart transport bytes; no SDK or device calls."""
from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import decode_s24 as decoder

FIXTURES = Path(__file__).parent / 'fixtures/dart_transport'


class AliasFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.plan = {'run_id': 'synthetic-run', 'binding': {'path': str(self.root / 'binding.json')}}
        (self.root / 'binding.json').write_bytes((FIXTURES / 'unicode-2028/binding.json').read_bytes())

    def install(self, export='a', point='2028', framing='lf', encoding='compact'):
        source = FIXTURES / ('unicode-' + point)
        target = self.root / export / self.plan['run_id']
        shutil.copytree(source, target)
        path = target / 's24-litert-public.jsonl'
        path.write_bytes((source / (framing + '-' + encoding + '.jsonl')).read_bytes())
        return path

    def inspect(self):
        return decoder.inspect_collection(self.root, self.plan)

    def assert_rejected(self, text=None):
        result = self.inspect()
        self.assertFalse(result['qualified'])
        self.assertFalse(result['strict_raw_decode_complete'])
        self.assertTrue(result['errors'])
        if text:
            self.assertIn(text, result['errors'][0]['message'])
        return result

class ExportAliasTests(AliasFixture):
    def test_pinned_actual_Dart_fixtures_hashes_and_complete_single_journal(self):
        manifest = json.loads((FIXTURES / 'manifest.json').read_bytes())
        for name, lock in manifest.items():
            raw = (FIXTURES / name).read_bytes()
            self.assertEqual(len(raw), lock['bytes'])
            self.assertEqual(hashlib.sha256(raw).hexdigest(), lock['sha256'])
        for point in ('0085', '2028', '2029'):
            for framing in ('lf', 'crlf'):
                for encoding in ('compact', 'base64'):
                    with self.subTest(point=point, framing=framing, encoding=encoding):
                        path = self.install(point + framing + encoding, point, framing, encoding)
                        raw = path.read_bytes()
                        self.assertEqual(chr(int(point, 16)).encode() in raw, encoding == 'compact')
                        decoded = decoder.decode(path, json.loads((self.root / 'binding.json').read_bytes()))
                        self.assertEqual(decoded['records'], 106)
                        self.assertEqual(len(decoded['producer_statuses']), 20)
                        self.assertEqual(set(decoded['producer_statuses'].values()), {'PASS'})
                        self.assertFalse(decoded['qualified'])
                        self.assertTrue(self.inspect()['strict_raw_decode_complete'])
                        self.assertEqual(sum(row['event'] == 'lifetime_closed' for row in decoder.jsonl(raw, decoder.JOURNAL_LIMIT, decoder.JOURNAL_LIMIT)), 6)
                        shutil.rmtree(path.parent.parent)
        self.install()
        self.assertTrue(self.inspect()['strict_raw_decode_complete'])

    def test_identical_two_aliases_deterministic_canonical_and_raw_preserved(self):
        paths = [self.install('z'), self.install('a')]
        before = {p.relative_to(self.root).as_posix(): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        result = self.inspect()
        self.assertTrue(result['strict_raw_decode_complete'], result)
        self.assertFalse(result['qualified'])
        self.assertFalse(result['decoded']['qualified'])
        self.assertEqual(result['canonical_journal'], 'a/synthetic-run/s24-litert-public.jsonl')
        self.assertEqual(result['journal_candidates'], sorted(result['journal_candidates']))
        self.assertEqual(len(result['journal_aliases']), 2)
        for lock in result['journal_aliases']:
            self.assertEqual(lock['bytes'], len(paths[0].read_bytes()))
            self.assertEqual(lock['sha256'], result['decoded']['journal_sha256'])
        self.assertEqual(before, {p.relative_to(self.root).as_posix(): p.read_bytes() for p in self.root.rglob('*') if p.is_file()})

    def test_different_same_size_bytes_size_empty_truncated_oversized_rejected(self):
        self.install('a')
        alias = self.install('z')
        original = alias.read_bytes()
        for raw in (original.replace(b'synthetic-byte-fixture', b'synthetic-byte-fixturX'), original + b' ', b'', original[:-1]):
            with self.subTest(size=len(raw)):
                alias.write_bytes(raw)
                self.assert_rejected()
        with alias.open('wb') as stream:
            stream.truncate(decoder.JOURNAL_LIMIT + 1)
        with patch.object(Path, 'open', side_effect=AssertionError('Oversized alias must fail before reading')):
            self.assert_rejected('oversized')

    def test_symlink_nonregular_foreign_run_and_count_limit_rejected(self):
        canonical = self.install('a')
        alias = self.install('z')
        alias.unlink()
        alias.symlink_to(canonical)
        self.assert_rejected('nonsymlink')
        alias.unlink()
        alias.mkdir()
        self.assert_rejected('nonsymlink')
        alias.rmdir()
        alias.parent.rename(alias.parent.with_name('foreign-run'))
        foreign = alias.parent.with_name('foreign-run') / alias.name
        foreign.write_bytes(canonical.read_bytes())
        self.assert_rejected('Foreign run')
        shutil.rmtree(foreign.parent.parent)
        for number in range(decoder.MAX_JOURNAL_ALIASES):
            self.install('alias-' + str(number))
        self.assert_rejected('count limit')

    def test_symlink_directory_and_unreadable_traversal_fail_closed(self):
        self.install()
        linked = self.root / 'linked-export'
        linked.symlink_to(self.root / 'a', target_is_directory=True)
        self.assert_rejected('Symlink directory')
        linked.unlink()
        def inaccessible(*args, **kwargs):
            kwargs['onerror'](PermissionError('unreadable export'))
            return iter(())
        with patch.object(decoder.os, 'walk', side_effect=inaccessible):
            self.assert_rejected('unreadable export')

    def test_missing_malformed_identical_and_incomplete_identical_rejected(self):
        self.assert_rejected('Missing')
        canonical, alias = self.install('a'), self.install('z')
        original = canonical.read_bytes()
        for raw, error in ((b'not JSON\n', 'Expecting'), (b'\xff\n', 'utf-8'),
                           (original[:original.rfind(b'{"event":"complete"')], 'completion')):
            with self.subTest(error=error):
                self.assertTrue(raw)
                canonical.write_bytes(raw)
                alias.write_bytes(raw)
                self.assert_rejected(error)


class DescriptorAdmissionTests(AliasFixture):
    def mutate(self, path, kind):
        if kind == 'symlink':
            raw_copy = self.root / 'linked-copy'
            raw_copy.write_bytes(path.read_bytes())
            path.unlink(); path.symlink_to(raw_copy)
        elif kind == 'replacement':
            replacement = path.with_suffix('.replacement')
            replacement.write_bytes(path.read_bytes())
            replacement.replace(path)
        elif kind == 'delete':
            path.unlink()
        elif kind == 'same-size-content':
            original = path.read_bytes()
            path.write_bytes(original.replace(b'synthetic-byte-fixture', b'synthetic-byte-fixturX'))
        elif kind == 'grow':
            with path.open('ab') as stream: stream.write(b' ')
        else:
            parent = path.parent
            saved = parent.with_name(parent.name + '-saved')
            parent.rename(saved)
            if kind == 'parent-symlink':
                parent.symlink_to(saved, target_is_directory=True)
            else:
                shutil.copytree(saved, parent)

    def test_discovery_to_open_races_reject_alias_and_canonical(self):
        original_discover = decoder.journal_aliases
        for export in ('a', 'z'):
            for kind in ('symlink', 'replacement', 'delete', 'parent-symlink', 'parent-replacement'):
                with self.subTest(export=export, kind=kind):
                    self.install('a'); self.install('z')
                    path = self.root / export / self.plan['run_id'] / 's24-litert-public.jsonl'
                    def discover(*args):
                        candidates = original_discover(*args)
                        self.mutate(path, kind)
                        return candidates
                    with patch.object(decoder, 'journal_aliases', side_effect=discover):
                        self.assert_rejected()
                    shutil.rmtree(self.root / 'a'); shutil.rmtree(self.root / 'z')
                    (self.root / 'linked-copy').unlink(missing_ok=True)

    def test_pinned_descriptors_reject_path_or_content_mutation_during_comparison(self):
        original_compare = decoder.compare_journal_alias
        for export in ('a', 'z'):
            for kind in ('symlink', 'replacement', 'delete', 'parent-symlink',
                         'parent-replacement', 'same-size-content', 'grow'):
                with self.subTest(export=export, kind=kind):
                    self.install('a'); self.install('z')
                    path = self.root / export / self.plan['run_id'] / 's24-litert-public.jsonl'
                    def compare(*args):
                        self.mutate(path, kind)
                        return original_compare(*args)
                    with patch.object(decoder, 'compare_journal_alias', side_effect=compare):
                        self.assert_rejected()
                    shutil.rmtree(self.root / 'a'); shutil.rmtree(self.root / 'z')
                    (self.root / 'linked-copy').unlink(missing_ok=True)

    def test_during_read_rewrite_grow_and_truncate_rejected(self):
        original_read = os.read
        for kind in ('same-size-content', 'grow', 'truncate'):
            with self.subTest(kind=kind):
                path = self.install()
                changed = False
                def read(fd, amount):
                    nonlocal changed
                    raw = original_read(fd, amount)
                    self.assertLessEqual(amount, 64 * 1024)
                    if raw and not changed:
                        changed = True
                        if kind == 'truncate': path.write_bytes(b'')
                        else: self.mutate(path, kind)
                    return raw
                with patch.object(decoder.os, 'read', side_effect=read):
                    self.assert_rejected()
                shutil.rmtree(path.parent.parent)

    def test_same_size_rewrite_with_restored_mtime_still_changes_ctime(self):
        path = self.install()
        original_read = os.read
        before = path.stat()
        changed = False
        def read(fd, amount):
            nonlocal changed
            raw = original_read(fd, amount)
            if raw and not changed:
                changed = True
                self.mutate(path, 'same-size-content')
                os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
                self.assertEqual(path.stat().st_size, before.st_size)
                self.assertEqual(path.stat().st_mtime_ns, before.st_mtime_ns)
                self.assertNotEqual(path.stat().st_ctime_ns, before.st_ctime_ns)
            return raw
        with patch.object(decoder.os, 'read', side_effect=read):
            self.assert_rejected('identity/content changed')

    def test_exact_alias_count_limit_remains_accepted(self):
        for number in range(decoder.MAX_JOURNAL_ALIASES): self.install(str(number))
        result = self.inspect()
        self.assertTrue(result['strict_raw_decode_complete'], result)
        self.assertEqual(len(result['journal_aliases']), 16)

    def test_parser_consumes_admitted_bytes_without_reopening_canonical(self):
        self.install('a'); self.install('z')
        original_open = Path.open
        def open_path(path, *args, **kwargs):
            if path.name == 's24-litert-public.jsonl':
                self.fail('Parser reopened a mutable journal path')
            return original_open(path, *args, **kwargs)
        with patch.object(Path, 'open', open_path):
            result = self.inspect()
        self.assertTrue(result['strict_raw_decode_complete'], result)

    def test_post_parse_path_mutation_and_hash_change_rejected(self):
        original_decode = decoder.decode
        for kind in ('replacement', 'delete', 'parent-symlink', 'same-size-content'):
            with self.subTest(kind=kind):
                path = self.install()
                def decode(*args, **kwargs):
                    result = original_decode(*args, **kwargs)
                    self.mutate(path, kind)
                    return result
                with patch.object(decoder, 'decode', side_effect=decode):
                    self.assert_rejected()
                shutil.rmtree(self.root / 'a')
        # Even unchanged metadata cannot waive the independently reread byte hash.
        path = self.install()
        def decode(*args, **kwargs):
            result = original_decode(*args, **kwargs)
            self.mutate(path, 'same-size-content')
            return result
        with patch.object(decoder, 'decode', side_effect=decode), \
             patch.object(decoder, 'file_identity', return_value='forced-stable-metadata'):
            self.assert_rejected('bytes changed')

    def test_collection_directory_replacement_rejected(self):
        self.install()
        original_decode = decoder.decode
        saved = self.root.with_name(self.root.name + '-saved')
        self.addCleanup(lambda: shutil.rmtree(saved, ignore_errors=True))
        def decode(*args, **kwargs):
            result = original_decode(*args, **kwargs)
            self.root.rename(saved)
            shutil.copytree(saved, self.root)
            return result
        with patch.object(decoder, 'decode', side_effect=decode):
            self.assert_rejected('Collection directory changed')

    def test_new_alias_in_existing_unadmitted_subtree_rejects_whole_collection(self):
        original_decode = decoder.decode
        for kind in ('different', 'identical', 'empty', 'oversized', 'symlink'):
            with self.subTest(kind=kind):
                canonical = self.install()
                target = self.root / 'z' / self.plan['run_id'] / canonical.name
                target.parent.mkdir(parents=True)
                def decode(*args, **kwargs):
                    result = original_decode(*args, **kwargs)
                    raw = canonical.read_bytes()
                    if kind == 'symlink': target.symlink_to(canonical)
                    elif kind == 'oversized':
                        with target.open('wb') as stream: stream.truncate(decoder.JOURNAL_LIMIT + 1)
                    else:
                        target.write_bytes(raw if kind == 'identical' else b'' if kind == 'empty' else raw + b' ')
                    return result
                with patch.object(decoder, 'decode', side_effect=decode):
                    self.assert_rejected()
                self.assertTrue(target.exists())
                shutil.rmtree(self.root / 'a'); shutil.rmtree(self.root / 'z')

    def test_final_discovery_exact_alias_set_is_checked_independently_of_metadata(self):
        canonical = self.install()
        original_decode = decoder.decode
        def decode(*args, **kwargs):
            result = original_decode(*args, **kwargs)
            self.install('z')
            return result
        with patch.object(decoder, 'decode', side_effect=decode), \
             patch.object(decoder, 'directory_identity', return_value='forced-stable-metadata'):
            self.assert_rejected('alias set changed')
        self.assertTrue(canonical.is_file())

    def test_transient_unadmitted_subtree_content_change_is_detected(self):
        canonical = self.install()
        target = self.root / 'z' / self.plan['run_id'] / canonical.name
        target.parent.mkdir(parents=True)
        original_decode = decoder.decode
        def decode(*args, **kwargs):
            result = original_decode(*args, **kwargs)
            target.write_bytes(canonical.read_bytes() + b' ')
            target.unlink()
            return result
        with patch.object(decoder, 'decode', side_effect=decode):
            self.assert_rejected('directory contents changed')

    def test_shared_ancestor_content_changes_do_not_reject_collection(self):
        self.install()
        original_decode = decoder.decode
        def decode(*args, **kwargs):
            result = original_decode(*args, **kwargs)
            # The sibling changes the shared temp parent's contents, not ours.
            with tempfile.TemporaryDirectory(dir=self.root.parent): pass
            return result
        with patch.object(decoder, 'decode', side_effect=decode):
            result = self.inspect()
        self.assertTrue(result['strict_raw_decode_complete'], result)

    def test_independent_non_EOF_short_reads_accept_identical_aliases(self):
        self.install('a'); self.install('z')
        original_read = os.read
        original_admit = decoder.admit_journal
        for canonical_cap, alias_cap in ((64 * 1024, 7), (13, 7), (1, 64 * 1024)):
            with self.subTest(canonical_cap=canonical_cap, alias_cap=alias_cap):
                caps = {}; calls = []
                def admit(candidate, stack):
                    journal = original_admit(candidate, stack)
                    caps[journal.fd] = canonical_cap if candidate.path.parts[-3] == 'a' else alias_cap
                    return journal
                def read(fd, amount):
                    calls.append(amount)
                    self.assertLessEqual(amount, 64 * 1024)
                    return original_read(fd, min(amount, caps[fd]))
                with patch.object(decoder, 'admit_journal', side_effect=admit), \
                     patch.object(decoder.os, 'read', side_effect=read):
                    result = self.inspect()
                self.assertTrue(result['strict_raw_decode_complete'], result)
                self.assertFalse(result['qualified'])
                self.assertTrue(calls)
                self.assertEqual(result['journal_aliases'][0]['sha256'], result['journal_aliases'][1]['sha256'])

    def test_required_descriptor_primitives_fail_closed(self):
        self.install()
        with patch.object(decoder.os, 'supports_dir_fd', set()):
            self.assert_rejected('Host lacks required no-follow descriptor admission primitives')
        for flag in ('O_NOFOLLOW', 'O_DIRECTORY', 'O_NONBLOCK'):
            with self.subTest(flag=flag), patch.object(decoder.os, flag):
                # Absence, rather than a zero-valued fallback, is unsupported.
                saved = getattr(decoder.os, flag)
                delattr(decoder.os, flag)
                try: self.assert_rejected('Host lacks required')
                finally: setattr(decoder.os, flag, saved)

    def test_descriptors_close_on_success_partial_admission_compare_read_and_parse_error(self):
        original_open = os.open
        original_supports = os.supports_dir_fd
        for stage in ('success', 'partial-admission', 'compare', 'read', 'parse', 'rediscovery'):
            with self.subTest(stage=stage):
                self.install('a'); alias = self.install('z'); opened = []
                def open_fd(*args, **kwargs):
                    if stage == 'partial-admission' and len(opened) == 5:
                        raise PermissionError('injected partial admission failure')
                    fd = original_open(*args, **kwargs); opened.append(fd); return fd
                with patch.object(decoder.os, 'open', side_effect=open_fd) as mocked_open, ExitStack() as stack:
                    stack.enter_context(patch.object(decoder.os, 'supports_dir_fd', original_supports | {mocked_open}))
                    if stage == 'compare': alias.write_bytes(alias.read_bytes() + b' ')
                    if stage == 'read': stack.enter_context(patch.object(decoder.os, 'read', side_effect=OSError('injected read error')))
                    if stage == 'parse': stack.enter_context(patch.object(decoder, 'decode', side_effect=ValueError('injected parse error')))
                    if stage == 'rediscovery':
                        original_discover = decoder.journal_aliases
                        discovery = original_discover(self.root, self.plan['run_id'])
                        stack.enter_context(patch.object(decoder, 'journal_aliases', side_effect=[discovery, ValueError('injected final discovery error')]))
                    result = self.inspect()
                self.assertEqual(result['strict_raw_decode_complete'], stage == 'success', result)
                self.assertTrue(opened)
                for fd in opened:
                    with self.assertRaises(OSError): os.fstat(fd)
                shutil.rmtree(self.root / 'a'); shutil.rmtree(self.root / 'z')


if __name__ == '__main__':
    unittest.main()
