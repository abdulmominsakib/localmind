"""Strict offline recovery of binary Android qualification journal captures."""
import base64
import hashlib
import json
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def recover(rows):
    rows = list(rows)
    require(rows and rows[0].get('event') == 'manifest', 'Missing first manifest')
    manifest = rows[0]
    require(manifest.get('schema') == 1, 'Manifest schema')
    cases = manifest['plan']['cases']
    require(isinstance(cases, list) and len(cases) == len(set(cases)), 'Invalid manifest cases')
    started = set()
    expected = ({'app_apk.sha256', 'vkjson.json', 'cpuinfo.txt'}
                if manifest['plan'].get('scenario') == 'consumer-cpu' else set())
    files = {}
    inventory = []
    active = None
    terminal = False
    summary = False
    total = 0
    for row in rows:
        event = row.get('event')
        require(not summary, 'Records after summary')
        if event == 'case_started':
            require(not terminal and active is None, 'Late case start')
            case = row['case_id']
            require(case in cases, 'Case outside manifest')
            identity = (case, row.get('model_free_launch', False))
            require(identity not in started, 'Duplicate started case')
            started.add(identity)
            require(isinstance(case, str) and all(c.isalnum() or c in '._-' for c in case), 'Unsafe case')
            if '.native.' in case:
                name = 'launch' if row.get('model_free_launch') else case
                expected.update(name + '/' + suffix for suffix in ('stdout.jsonl', 'stderr.log', 'capture.json'))
            elif '.public.' in case:
                expected.update((case + '.stderr.log', case + '.maps'))
            else:
                raise ValueError('Unknown case family')
        elif event == 'manifest':
            require(row is manifest, 'Duplicate manifest')
        elif event == 'raw_file_start':
            require(not terminal and active is None, 'Overlapping raw envelope')
            name = row['name']
            require(name in expected and name not in files, 'Unexpected or duplicate file')
            size = row['bytes']
            require(type(size) is int and 0 <= size <= 4 * 1024 * 1024, 'File size limit')
            require(row['chunks'] == (size + 24575) // 24576, 'Chunk count')
            active = (dict(row), bytearray(), 0)
        elif event == 'raw_file_chunk':
            require(active is not None and not terminal, 'Chunk without start')
            start, data, index = active
            require(row['name'] == start['name'] and type(row['index']) is int and row['index'] == index, 'Chunk order')
            raw = base64.b64decode(row['base64'], validate=True)
            require(base64.b64encode(raw).decode() == row['base64'], 'Noncanonical base64')
            require(len(raw) == min(24576, start['bytes'] - len(data)) and len(raw) > 0, 'Chunk size')
            data.extend(raw)
            active = (start, data, index + 1)
        elif event == 'raw_file_end':
            require(active is not None and not terminal, 'End without start')
            start, data, count = active
            lock = {key: start[key] for key in ('name', 'bytes', 'sha256', 'chunks')}
            require({key: row[key] for key in lock} == lock, 'End lock mismatch')
            require(len(data) == start['bytes'] and count == start['chunks'], 'Incomplete file')
            require(hashlib.sha256(data).hexdigest() == start['sha256'], 'Digest mismatch')
            total += len(data)
            require(total <= 32 * 1024 * 1024, 'Aggregate limit')
            files[start['name']] = bytes(data)
            inventory.append(lock)
            active = None
        elif event == 'raw_export_end':
            require(not terminal and active is None and row['complete'] is True, 'Incomplete export')
            require(set(files) == expected and expected, 'Missing expected files')
            require(row['files'] == inventory and row['total_bytes'] == total, 'Inventory mismatch')
            terminal = True
        elif event == 'raw_file_error':
            raise ValueError('Producer reported raw export failure')
        elif event == 'summary':
            require(terminal and row.get('raw_export_complete') is True, 'Missing export completion')
            require(set(row['case_inventory']) == set(cases), 'Summary case inventory')
            for case, result in row['case_inventory'].items():
                require(result['status'] == 'NOT_RUN' or (case, False) in started, 'Missing case start')
            summary = True
        else:
            require(active is None and not terminal, 'Interrupted export or late record')
    require(summary and terminal and active is None, 'Truncated journal')
    for name, data in files.items():
        if name.endswith('/capture.json'):
            capture = json.loads(data)
            prefix = name.rsplit('/', 1)[0]
            for suffix in ('stdout.jsonl', 'stderr.log'):
                raw = files[prefix + '/' + suffix]
                lock = capture['files'][suffix]
                require(len(raw) == lock['bytes'] and hashlib.sha256(raw).hexdigest() == lock['sha256'], 'Native capture lock mismatch')
    native_events = {}
    public_events = {}
    for row in rows:
        event = row.get('event')
        if event == 'native_capture':
            key = (row['case_id'], row.get('model_free_launch', False))
            require(key in started and key not in native_events, 'Unexpected or duplicate native capture')
            native_events[key] = row
        elif event in ('public_stderr_capture', 'public_geometry_stderr_snapshot'):
            key = (row['case_id'], event)
            require((row['case_id'], False) in started and key not in public_events, 'Unexpected or duplicate public lock')
            public_events[key] = row
    for case, launch in started:
        if '.native.' in case:
            require((case, launch) in native_events, 'Missing native capture event')
        else:
            for event in ('public_stderr_capture', 'public_geometry_stderr_snapshot'):
                require((case, event) in public_events, 'Missing public lock event')
    for row in rows:
        if row.get('event') == 'public_stderr_capture':
            raw = files[row['case_id'] + '.stderr.log']
            require(len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256'], 'Public stderr mismatch')
        elif row.get('event') == 'public_geometry_stderr_snapshot':
            raw = files[row['case_id'] + '.stderr.log']
            require(type(row['bytes']) is int and 0 <= row['bytes'] <= len(raw), 'Snapshot length')
            require(hashlib.sha256(raw[:row['bytes']]).hexdigest() == row['sha256'], 'Public snapshot mismatch')
        elif row.get('event') == 'native_capture':
            prefix = 'launch' if row.get('model_free_launch') else row['case_id']
            captured = json.loads(files[prefix + '/capture.json'])
            require(captured == row['capture'], 'Journal native capture mismatch')
            require(captured.get('schema') == 1 and captured.get('binding') == manifest.get('execution_binding')
                    and isinstance(manifest.get('execution_binding'), str)
                    and len(manifest['execution_binding']) == 64
                    and captured.get('case_id') == row['case_id']
                    and type(captured.get('pid')) is int and captured['pid'] > 0, 'Native capture identity mismatch')
            records = [json.loads(line) for line in files[prefix + '/stdout.jsonl'].splitlines()]
            for index, record in enumerate(records):
                require(record.get('schema') == 1 and record.get('binding') == captured['binding']
                        and record.get('case_id') == captured['case_id'] and record.get('pid') == captured['pid']
                        and record.get('sequence') == index, 'Native stdout identity mismatch')
            if 'records' in captured:
                require(captured['records'] == records, 'Parsed native records mismatch')
    return files


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('journal', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    require(args.journal.stat().st_size <= 64 * 1024 * 1024, 'Journal size limit')
    with args.journal.open() as source:
        rows = []
        for line in source:
            require(len(line) <= 4 * 1024 * 1024, 'Journal line size limit')
            rows.append(json.loads(line))
    files = recover(rows)
    args.out.mkdir(mode=0o700, exist_ok=False)
    for name, raw in files.items():
        target = args.out / name
        target.parent.mkdir(mode=0o700, exist_ok=True)
        with target.open('xb') as output:
            output.write(raw)
        target.chmod(0o600)
    print(json.dumps({'raw_integrity_verified': True, 'files': len(files),
                      'hardware_qualified': False}))


if __name__ == '__main__':
    main()
