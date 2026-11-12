#!/usr/bin/env python3
"""Verify a fresh model-free Perfetto probe. Never qualifies inference placement."""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import uuid

FILES = {'version.txt', 'version.stderr.txt', 'service-state.txt', 'service-state.stderr.txt',
         'service-state.pb', 'service-state-raw.stderr.txt', 'config.pbtxt',
         'capture.perfetto-trace', 'capture.stderr.txt', 'capture-start-ack.txt'}
SOURCE = re.compile(r'gpu\.renderstages(?:\.[A-Za-z0-9_-]+)?\Z')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fields(data):
    """Bounded wire decoder for explicitly inspected fields; rejects malformed input."""
    offset = 0

    def varint():
        nonlocal offset
        value = 0
        for shift in range(0, 70, 7):
            require(offset < len(data), 'Truncated protobuf varint')
            byte = data[offset]
            offset += 1
            require(shift < 63 or byte <= 1, 'Protobuf varint overflow')
            value |= (byte & 127) << shift
            if byte < 128:
                return value
        raise ValueError('Protobuf varint overflow')

    while offset < len(data):
        key = varint()
        number, wire = key >> 3, key & 7
        require(number > 0, 'Invalid protobuf field number')
        if wire == 0:
            value = varint()
        elif wire == 2:
            length = varint()
            require(length <= len(data) - offset, 'Truncated protobuf payload')
            value = data[offset:offset + length]
            offset += length
        elif wire in (1, 5):
            length = 8 if wire == 1 else 4
            require(length <= len(data) - offset, 'Truncated fixed protobuf field')
            value = data[offset:offset + length]
            offset += length
        else:
            raise ValueError('Unsupported protobuf wire type')
        yield number, wire, value


def messages(data, number):
    return [value for field, wire, value in fields(data) if field == number and wire == 2]


def registered_sources(data):
    # TracingServiceState.data_sources=2 -> DataSource.ds_descriptor=1
    # -> DataSourceDescriptor.name=1. A text mention is not registration.
    names = []
    for source in messages(data, 2):
        descriptors = messages(source, 1)
        require(len(descriptors) == 1, 'Missing/duplicate source descriptor')
        values = messages(descriptors[0], 1)
        require(len(values) == 1, 'Missing/duplicate descriptor name')
        names.append(values[0].decode('utf-8', errors='strict'))
    require(names, 'No registered data sources in raw service response')
    return sorted(set(names))


def packet_counts(data):
    counts = {'packets': 0, 'render_stage_events': 0, 'render_stage_duration_events': 0,
              'gpu_counter_packets': 0}
    for packet in messages(data, 1):
        counts['packets'] += 1
        for number, wire, value in fields(packet):
            require(number not in (50, 133), 'Compressed packets require a supported schema-aware reader')
            if wire == 2 and number == 52:
                counts['gpu_counter_packets'] += 1
            if wire == 2 and number == 53:
                values = list(fields(value))
                # Specifications-only packets have no event_id and are not execution events.
                if any(n == 1 and w == 0 for n, w, v in values):
                    counts['render_stage_events'] += 1
                    if any(n == 2 and w == 0 and v > 0 for n, w, v in values):
                        counts['render_stage_duration_events'] += 1
    require(counts['packets'] > 0, 'No Perfetto TracePacket payloads')
    return counts


def query(binary, trace, sql):
    result = subprocess.run([str(binary), 'query', str(trace), sql], check=True,
                            text=True, capture_output=True, timeout=30)
    require(len(result.stdout) <= 1024 * 1024, 'SQL output exceeds probe limit')
    return list(csv.DictReader(io.StringIO(result.stdout))), result.stderr


def validate_controls(receipt, rows):
    require(len(rows) == 2, 'Exactly one CPU and one idle marker required')
    for control in ('cpu', 'idle'):
        expected = receipt[control + '_control']
        require(expected['marker'] == 'llamadart_probe_' + control + '_' + receipt['nonce'], 'Marker nonce mismatch')
        matches = [row for row in rows if row['name'] == expected['marker']]
        require(len(matches) == 1, 'Missing/duplicate control marker')
        row = matches[0]
        require(int(row['pid']) == receipt['pid'], 'Control PID does not match current probe')
        start, duration = int(row['ts']), int(row['dur'])
        require(800_000_000 <= duration <= 5_000_000_000, 'Incomplete/out-of-bound control slice')
        require(abs(start - expected['start_boottime_ns']) < 100_000_000, 'Control start clock mismatch')
        require(abs(start + duration - expected['end_boottime_ns']) < 100_000_000, 'Control end clock mismatch')
    require(receipt['cpu_control']['end_boottime_ns'] <= receipt['idle_control']['start_boottime_ns'], 'Controls overlap')


def verify(directory, build_path, binary, expected_binary_sha256):
    require(directory.is_dir() and not directory.is_symlink(), 'Unsafe receipt directory')
    require({path.name for path in directory.iterdir()} == FILES | {'receipt.json'}, 'Unexpected/missing probe files')
    require(all(path.is_file() and not path.is_symlink() for path in directory.iterdir()), 'Probe files must be regular files')
    require(build_path.stat().st_size <= 256 * 1024, 'Build manifest exceeds size bound')
    require((directory / 'receipt.json').stat().st_size <= 256 * 1024, 'Receipt exceeds size bound')
    build = json.loads(build_path.read_text())
    receipt = json.loads((directory / 'receipt.json').read_text())
    require(build['submittable'] is True and build['source_dirty'] is False, 'Dirty preview cannot qualify a cloud probe')
    require(re.fullmatch('[0-9a-f]{40}', build['source_commit']), 'Invalid frozen source commit')
    require(receipt['schema_version'] == 1 and receipt['scope'] == 'model_free_trace_collection_capability', 'Unknown receipt schema')
    require(receipt['gpu_inference_qualified'] is False and receipt['trace_semantics_validated'] is False, 'Self-qualified receipt rejected')
    require(receipt['source_commit_declaration'] == build['source_commit'], 'Source declaration mismatch')
    require(receipt['app_apk_sha256'] == build['files']['app.apk']['sha256'], 'Installed app APK mismatch')
    require(receipt['test_apk_sha256'] == build['files']['test.apk']['sha256'], 'Installed test APK mismatch')
    require(str(uuid.UUID(receipt['nonce'])) == receipt['nonce'], 'Invalid nonce')
    require(directory.name == receipt['nonce'], 'Pulled directory nonce mismatch')
    require(receipt['api'] >= 34 and receipt['package'] == 'dev.llamadart.validation.perfetto', 'Unsupported target')
    require(receipt['pid'] > 0 and receipt['uid'] > 0, 'Missing process identity')
    require(receipt['no_activity_or_flutter_engine'] is True and receipt['app_hardware_accelerated'] is False,
            'Unexpected application rendering')
    require(receipt['atrace_enabled_when_markers_submitted'] is True, 'ATrace was not enabled')
    require(receipt.get('capture_session_start_acknowledged') is True, 'Session start was not acknowledged')
    require(type(receipt.get('capture_session_pid')) is int and receipt['capture_session_pid'] > 0, 'Missing acknowledged capture PID')
    acknowledgment = (directory / 'capture-start-ack.txt').read_bytes()
    require(acknowledgment == (str(receipt['capture_session_pid']) + '\nREADY:0\n').encode(),
            'Invalid session-start acknowledgment payload')
    require(type(receipt.get('capture_ack_boottime_ns')) is int and
            0 < receipt['capture_ack_boottime_ns'] <= receipt['cpu_control']['start_boottime_ns'],
            'CPU control preceded session acknowledgment')
    require(set(receipt['files']) == FILES, 'Receipt file inventory mismatch')
    for name, expected in receipt['files'].items():
        path = directory / name
        require(path.stat().st_size <= 16 * 1024 * 1024, 'Probe payload exceeds size bound')
        require(path.stat().st_size == expected['bytes'] and sha256(path) == expected['sha256'], 'Payload identity mismatch: ' + name)
    registered = registered_sources((directory / 'service-state.pb').read_bytes())
    render_sources = [name for name in registered if SOURCE.fullmatch(name)]
    require(render_sources == receipt['discovered_render_stage_source_names'], 'Text/raw producer discovery mismatch')
    counts = packet_counts((directory / 'capture.perfetto-trace').read_bytes())
    require(sha256(binary) == expected_binary_sha256, 'Trace processor binary mismatch')
    trace = directory / 'capture.perfetto-trace'
    rows, diagnostics = query(binary, trace, "SELECT s.name, s.ts, s.dur, p.pid FROM slice s JOIN process_track t ON t.id=s.track_id JOIN process p ON p.upid=t.upid WHERE s.name GLOB 'llamadart_probe_*' ORDER BY s.ts")
    validate_controls(receipt, rows)
    errors, other_diagnostics = query(binary, trace, "SELECT name, severity, value FROM stats WHERE value > 0 AND severity IN ('error', 'data_loss')")
    require(not errors, 'Trace parse/data-loss errors: ' + str(errors))
    version = subprocess.check_output([str(binary), '--version'], text=True, timeout=10).strip()
    return {'schema_version': 1, 'scope': receipt['scope'], 'gpu_inference_qualified': False,
            'trace_collection_validated': True, 'gpu_execution_attribution_validated': False,
            'source_commit': build['source_commit'], 'nonce': receipt['nonce'], 'pid': receipt['pid'],
            'registered_render_stage_sources': render_sources, 'packet_inventory': counts, 'controls': rows,
            'render_stage_transport_observed': bool(render_sources and counts['render_stage_events']),
            'trace_processor_sha256': expected_binary_sha256, 'trace_processor_version': version,
            'trace_processor_diagnostics': diagnostics + other_diagnostics,
            'receipt_sha256': sha256(directory / 'receipt.json'), 'build_sha256': sha256(build_path),
            'remaining': 'Per-request model dispatch/completion attribution and CPU/software fallback exclusion'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--build', required=True, type=Path)
    parser.add_argument('--trace-processor', required=True, type=Path)
    parser.add_argument('--trace-processor-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    require(not args.output.exists(), 'Qualification output must be fresh')
    result = verify(args.directory, args.build, args.trace_processor, args.trace_processor_sha256)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
