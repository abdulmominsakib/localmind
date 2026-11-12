"""Pure lossless codec and complete S24 transport; never device/runtime evidence."""
import base64
import copy
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import decode_s24 as decoder
import s24_capture as codec
import s24_decoder_fixtures as fixtures


class CaptureTests(unittest.TestCase):
    def test_text_binary_unicode_NUL_and_escaping_roundtrip_and_size_choice(self):
        for raw in (b'',b'native maps\n'*500,b'\x00'*500,b'"\\\t'*500,'é漢😀\u2028\u2029\n'.encode()*100,bytes(range(256)),b'\xc0\xaf\xff\x80'):
            with self.subTest(raw=raw[:20]):
                value=codec.encode_capture(raw);self.assertEqual(codec.decode_capture(value),raw)
                self.assertLessEqual(len(json.dumps(value,ensure_ascii=False)),len(json.dumps(fixtures.cap(raw),ensure_ascii=False)))
                self.assertEqual(value['bytes'],len(raw));self.assertEqual(value['sha256'],hashlib.sha256(raw).hexdigest())
        self.assertIn('base64',codec.encode_capture(b'\x00'*500));self.assertIn('base64',codec.encode_capture(b'\xff'))
    def test_legacy_base64_and_noncanonical_encoding(self):
        raw=bytes(range(256));self.assertEqual(codec.decode_capture(fixtures.cap(raw)),raw)
        for bad in ('YR==','YQ','____','!!!!'):
            with self.subTest(bad=bad),self.assertRaises(ValueError):codec.decode_capture({**fixtures.cap(b'a'),'base64':bad})
    def test_ambiguous_missing_types_lengths_hashes_and_Unicode_refused(self):
        valid=codec.encode_capture(b'valid native log\n')
        values=[{k:v for k,v in valid.items() if k!='utf8'},{**valid,'base64':''},{**valid,'utf8':1},{**valid,'utf8':'changed'},
            {**valid,'bytes':-1},{**valid,'bytes':1.0},{**valid,'bytes':True},{**valid,'bytes':valid['bytes']+1},
            {**valid,'sha256':'g'*64},{**valid,'sha256':'0'*64},{**valid,'sha256':None},
            {'bytes':1,'sha256':'0'*64,'utf8':'\ud800'},{'bytes':1,'sha256':'0'*64,'utf8':'\udfff'},
            {'bytes':1,'sha256':'0'*64,'utf8':'漢'},{**fixtures.cap(b'\xff'),'base64':1}]
        for value in values:
            with self.subTest(value=value),self.assertRaises(ValueError):codec.decode_capture(value)
    def test_oversize_refused_before_allocation_or_decode(self):
        with patch.object(base64,'b64decode',side_effect=AssertionError('No decoding')):
            for value in ({'bytes':8388609,'sha256':'0'*64,'base64':''},{'bytes':0,'sha256':'0'*64,'base64':'AAAA'}):
                with self.assertRaises(ValueError):codec.decode_capture(value)
        with patch.object(base64,'b64encode',side_effect=AssertionError('No encoding')):
            with self.assertRaises(ValueError):codec.encode_capture(b'a'*8388609)
    def test_existing_maximum_raw_capture(self):
        raw=b'a'*8388608;self.assertEqual(codec.decode_capture(codec.encode_capture(raw)),raw)


class CompleteTransportTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.binding={'synthetic':'metadata-only'};self.rows=fixtures.valid(self.root,self.binding);self.path=self.root/'s24-litert-public.jsonl'
    def decode(self):
        fixtures.write(self.path,self.rows);return decoder.decode(self.path,self.binding)
    def convert(self,value):
        if isinstance(value,dict):
            if {'bytes','sha256','base64'}<=value.keys():
                converted=codec.encode_capture(codec.decode_capture(value))
                return {**{k:v for k,v in value.items() if k!='base64'},**converted}
            return {k:self.convert(v) for k,v in value.items()}
        if isinstance(value,list):return [self.convert(v) for v in value]
        return value
    def test_complete20_both_encodings_remain_unqualified(self):
        old=self.decode();self.rows=self.convert(self.rows);new=self.decode()
        self.assertEqual(len(new['producer_statuses']),20);self.assertEqual(set(new['producer_statuses'].values()),{'PASS'})
        self.assertEqual(old['decoded_captures'],new['decoded_captures']);self.assertFalse(new['qualified']);self.assertIn('NOT_ASSESSED',new['semantic_or_placement_assessment'])
    def test_missing_completion_closure_cancel_raw_or_result_reject(self):
        self.decode()
        for event in ('complete','lifetime_closed','public_cancel','owned_child_capture','case_result'):
            old=self.rows;self.rows=copy.deepcopy(old);self.rows.pop(next(i for i,r in enumerate(self.rows) if r['event']==event));fixtures.resequence(self.rows)
            with self.subTest(event=event),self.assertRaises(ValueError):self.decode()
            self.rows=old
    def test_duplicate_completion_corrupt_payload_or_execution_overclaim_reject(self):
        self.decode();old=copy.deepcopy(self.rows);self.rows.append(copy.deepcopy(self.rows[-1]))
        with self.assertRaises(ValueError):self.decode()
        self.rows=copy.deepcopy(old);self.rows[-1]['gpu_per_request_execution_qualified']=True
        with self.assertRaises(ValueError):self.decode()
        self.rows=copy.deepcopy(old);next(r for r in self.rows if r['event']=='public_chunk')['capture']['base64']=base64.b64encode(b'x').decode()
        with self.assertRaises(ValueError):self.decode()
    def test_original_journal_and_child_bounds_not_waived(self):
        with self.assertRaises(ValueError):decoder.jsonl(b' '*16777216+b'\n',16777216,12*1024*1024)
        next(r for r in self.rows if r['event']=='owned_child_capture')['stderr']={'bytes':8388609,'sha256':'0'*64,'utf8':''}
        with self.assertRaises(ValueError):self.decode()
    def test_journal_bound_is_checked_before_opening_or_allocating(self):
        class OversizedPath:
            def stat(self):
                class Stat:st_size=16777217
                return Stat()
            def open(self,*args,**kwargs):raise AssertionError('Oversized journal must not open')
        with self.assertRaises(ValueError):decoder.decode(OversizedPath(),self.binding)
    def test_nested_snapshot_requires_exactly_one_payload(self):
        row={'sequence':0,'case_id':None,'event':'default_discovery_probe','mappings':{'capture':fixtures.cap(b'synthetic maps')}}
        self.rows.insert(1,row);fixtures.resequence(self.rows);self.decode()
        row['mappings']['capture'].pop('base64')
        with self.assertRaises(ValueError):self.decode()
    def test_duplicate_keys_and_nonfinite_JSON_reject(self):
        for raw in ('{"x":1,"x":2}','{"x":NaN}'):
            with self.assertRaises(ValueError):decoder.loads(raw)


class DartSerializedTransportTests(unittest.TestCase):
    setUp=CompleteTransportTests.setUp
    @classmethod
    def setUpClass(cls):
        cls.dart=os.environ.get('DART_BIN') or shutil.which('dart')
        package=Path(__file__).resolve().parents[2]
        cls.config=package/'.dart_tool/package_config.json'
        cls.script=package/'test/support/serialize_s24_transport.dart'
        if not cls.dart or not cls.config.is_file():
            raise unittest.SkipTest('Prepared package config and DART_BIN/Dart SDK required')
    def test_actual_Dart_complete20_Unicode_LF_CRLF_and_legacy_base64(self):
        for point in (0x85,0x2028,0x2029):
            for encoding in ('base64','compact'):
                for ending in ('lf','crlf'):
                    with self.subTest(point=f'U+{point:04X}',encoding=encoding,ending=ending):
                        result=subprocess.run([self.dart,'--packages='+str(self.config),str(self.script),str(point),encoding,ending],input=json.dumps(self.rows).encode(),capture_output=True,check=True,timeout=30)
                        raw=result.stdout
                        self.assertTrue(raw.endswith(b'\n' if ending=='lf' else b'\r\n'))
                        self.assertEqual(chr(point).encode() in raw,encoding=='compact')
                        literal_rows=[json.loads(line) for line in raw.split(b'\n') if line]
                        capture=next(row for row in literal_rows if row['event']=='public_observation')['mappings']['capture']
                        self.assertEqual(codec.decode_capture(capture),f'native {chr(point)} log\n'.encode())
                        self.path.write_bytes(raw);decoded=decoder.decode(self.path,self.binding)
                        self.assertEqual(decoded['records'],106)
                        self.assertEqual(set(decoded['producer_statuses'].values()),{'PASS'})
                        self.assertEqual(len(decoded['producer_statuses']),20)
                        self.assertFalse(decoded['qualified'])


class PhysicalFramingTests(unittest.TestCase):
    def test_LF_and_CRLF_physical_frames_preserve_valid_objects(self):
        for raw in (b'{}\n',b'{}\r\n',b' {} \r\n{}\n'):
            self.assertEqual(decoder.jsonl(raw,100,10),[{}]*(2 if raw.count(b'\n')==2 else 1))
        self.assertEqual(decoder.jsonl(b'{}\r\n',4,2),[{}])
    def test_empty_truncated_nonobject_invalid_UTF8_or_bare_separator_reject(self):
        values=[b'',b'{}',b'{}\r',b'\n',b'\r\n',b'{}\n\n',b'[]\n',b'\xff\n',b'{}\r{}\n',b'\r{}\n',b'{}\r\r\n',b'{}\r \n']
        values += [b'{}'+chr(point).encode()+b'{}\n' for point in (0x85,0x2028,0x2029)]
        for raw in values:
            with self.subTest(raw=raw),self.assertRaises((ValueError,UnicodeError)):decoder.jsonl(raw,100,100)
    def test_line_byte_bound_rejects_before_UTF8_or_JSON_allocation(self):
        with patch.object(decoder,'loads',side_effect=AssertionError('Do not parse oversized frame')):
            with self.assertRaisesRegex(ValueError,'Empty/oversized'):decoder.jsonl(b'\xff'*8+b'\n',100,4)


if __name__=='__main__':unittest.main()
