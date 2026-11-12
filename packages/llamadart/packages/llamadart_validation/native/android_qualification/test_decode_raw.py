import base64
import copy
import hashlib
import json
import unittest

from decode_raw import recover


def fixture():
    rows = [{'event': 'manifest', 'schema': 1, 'plan': {'cases': ['a35.public.cpu']}},
            {'event': 'case_started', 'case_id': 'a35.public.cpu'}]
    inventory = []
    payloads = {'a35.public.cpu.maps': b'mapping\n',
                'a35.public.cpu.stderr.log': bytes(range(256)) * 100}
    raw = payloads['a35.public.cpu.stderr.log']
    for event in ('public_stderr_capture', 'public_geometry_stderr_snapshot'):
        rows.append(dict(event=event, case_id='a35.public.cpu', bytes=len(raw),
                         sha256=hashlib.sha256(raw).hexdigest()))
    for name, raw in payloads.items():
        count = (len(raw) + 24575) // 24576
        lock = dict(name=name, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), chunks=count)
        rows.append(dict(event='raw_file_start', **lock))
        for index in range(count):
            rows.append(dict(event='raw_file_chunk', name=name, index=index,
                base64=base64.b64encode(raw[index*24576:(index+1)*24576]).decode()))
        rows.append(dict(event='raw_file_end', **lock))
        inventory.append(lock)
    rows.append(dict(event='raw_export_end', complete=True, files=inventory,
        total_bytes=sum(map(len, payloads.values()))))
    rows.append(dict(event='summary', raw_export_complete=True, case_inventory={'a35.public.cpu': {'status': 'PASS'}}))
    return rows, payloads


class DecoderTest(unittest.TestCase):
    def test_native_identity_with_consistent_file_hashes(self):
        def native(binding='1' * 64, case='a35.native.cpu', pid=7, sequence=0):
            record = dict(schema=1, binding=binding, case_id=case, pid=pid,
                          sequence=sequence, event='started')
            stdout = (json.dumps(record) + '\n').encode()
            payloads = {'a35.native.cpu/stdout.jsonl': stdout,
                        'a35.native.cpu/stderr.log': b'native\xff\n'}
            capture = dict(schema=1, binding=binding, case_id=case, pid=pid,
                           records=[record], files={})
            for name, raw in payloads.items():
                capture['files'][name.rsplit('/', 1)[1]] = dict(
                    bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
            payloads['a35.native.cpu/capture.json'] = json.dumps(capture).encode()
            rows = [dict(event='manifest', schema=1, execution_binding='1' * 64,
                         plan={'cases': ['a35.native.cpu']}),
                    dict(event='case_started', case_id='a35.native.cpu'),
                    dict(event='native_capture', case_id='a35.native.cpu', capture=capture)]
            inventory = []
            for name, raw in payloads.items():
                lock = dict(name=name, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), chunks=1)
                rows += [dict(event='raw_file_start', **lock),
                         dict(event='raw_file_chunk', name=name, index=0, base64=base64.b64encode(raw).decode()),
                         dict(event='raw_file_end', **lock)]
                inventory.append(lock)
            rows += [dict(event='raw_export_end', complete=True, files=inventory,
                          total_bytes=sum(map(len, payloads.values()))),
                     dict(event='summary', raw_export_complete=True,
                          case_inventory={'a35.native.cpu': {'status': 'PASS'}})]
            return rows, payloads

        rows, files = native()
        self.assertEqual(recover(rows), files)
        for kwargs in [dict(binding='2' * 64), dict(case='a35.native.vulkan'),
                       dict(pid=0), dict(sequence=1)]:
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                recover(native(**kwargs)[0])
        for mutation in [rows[:2] + rows[3:], rows[:3] + [rows[2]] + rows[3:]]:
            with self.assertRaises(ValueError):
                recover(mutation)

    def test_binary_roundtrip(self):
        rows, files = fixture()
        self.assertEqual(recover(rows), files)

    def test_corruption_and_truncation_refused(self):
        rows, _ = fixture()
        variants = []
        for index in range(len(rows)):
            variants.append(rows[:index] + rows[index+1:])
        for index, row in enumerate(rows):
            if row['event'] == 'raw_file_chunk':
                variants.append(rows[:index] + [row, row] + rows[index+1:])
                bad = copy.deepcopy(rows)
                bad[index]['base64'] = base64.b64encode(b'wrong').decode()
                variants.append(bad)
        bad = copy.deepcopy(rows)
        bad[-2]['total_bytes'] += 1
        variants.append(bad)
        bad = copy.deepcopy(rows)
        bad[4]['name'] = '../outside'
        variants.append(bad)
        for variant in variants:
            with self.subTest(events=[r['event'] for r in variant]):
                with self.assertRaises((ValueError, KeyError)):
                    recover(variant)

    def test_reordering_inventory_and_public_locks(self):
        rows, files = fixture()
        variants = []
        chunks = [i for i, row in enumerate(rows)
                  if row['event'] == 'raw_file_chunk' and row['name'].endswith('stderr.log')]
        bad = copy.deepcopy(rows)
        bad[chunks[0]], bad[chunks[1]] = bad[chunks[1]], bad[chunks[0]]
        variants.append(bad)
        for field, value in [('sha256', '0' * 64), ('bytes', 1), ('chunks', 9)]:
            bad = copy.deepcopy(rows)
            bad[4][field] = value
            variants.append(bad)
        bad = copy.deepcopy(rows)
        bad[-2]['files'].pop()
        variants.append(bad)
        bad = copy.deepcopy(rows)
        bad.insert(2, {'event': 'public_stderr_capture', 'case_id': 'a35.public.cpu',
                       'bytes': 25600, 'sha256': '0' * 64})
        variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError):
                recover(bad)


if __name__ == '__main__':
    unittest.main()
