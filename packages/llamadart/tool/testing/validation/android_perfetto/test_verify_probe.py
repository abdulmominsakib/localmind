import os
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from verify_probe import fields, packet_counts, registered_sources, validate_controls


def varint(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def field(number, value):
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, bytes):
        return varint(number << 3 | 2) + varint(len(value)) + value
    return varint(number << 3) + varint(value)


def trace_fixture(nonce, pid=321):
    events = b''
    for control, cookie, start in [('cpu', 1, 1_000_000_000), ('idle', 2, 2_100_000_000)]:
        name = 'llamadart_probe_' + control + '_' + nonce
        for time, marker in [(start, f'S|{pid}|{name}|{cookie}'),
                             (start + 1_000_000_000, f'F|{pid}|{name}|{cookie}')]:
            # FtraceEvent: timestamp=1, tid=2, print=3; PrintFtraceEvent.buf=2.
            event = field(1, time) + field(2, pid) + field(3, field(2, marker))
            events += field(2, event)
    return field(1, field(1, field(1, 0) + events))


class VerifyProbeTest(unittest.TestCase):
    def setUp(self):
        self.nonce = '11111111-2222-4333-8444-555555555555'
        self.receipt = {'nonce': self.nonce, 'pid': 321}
        self.rows = []
        for control, start in [('cpu', 1_000_000_000), ('idle', 2_100_000_000)]:
            name = 'llamadart_probe_' + control + '_' + self.nonce
            self.receipt[control + '_control'] = {'marker': name, 'start_boottime_ns': start,
                                                  'end_boottime_ns': start + 1_000_000_000}
            self.rows.append({'name': name, 'ts': str(start), 'dur': '1000000000', 'pid': '321'})

    def test_raw_registered_name_not_arbitrary_text(self):
        descriptor = field(1, 'gpu.renderstages.adreno')
        data = field(5, 'gpu.renderstages.fake') + field(2, field(1, descriptor))
        self.assertEqual(registered_sources(data), ['gpu.renderstages.adreno'])

    def test_truncated_and_overflow_wire_rejected(self):
        for data in (b'\x12\x05bad', b'\x80' * 10, b'\x00', b'\x0e'):
            with self.assertRaises(ValueError):
                list(fields(data))

    def test_counter_and_specs_only_are_not_render_execution(self):
        trace = field(1, field(52, b'') + field(53, field(7, field(1, b''))))
        counts = packet_counts(trace)
        self.assertEqual(counts['gpu_counter_packets'], 1)
        self.assertEqual(counts['render_stage_events'], 0)

    def test_actual_render_event_is_inventory_only(self):
        counts = packet_counts(field(1, field(53, field(1, 9) + field(2, 17))))
        self.assertEqual(counts['render_stage_duration_events'], 1)
        self.assertNotIn('gpu_inference_qualified', counts)

    def test_compressed_or_nontrace_rejected(self):
        for trace in (b'', field(1, field(50, b'compressed')), b'perfetto failed'):
            with self.assertRaises(ValueError):
                packet_counts(trace)

    def test_stale_pid_or_nonce_rejected(self):
        validate_controls(self.receipt, self.rows)
        for key, value in [('pid', '322'), ('name', 'llamadart_probe_cpu_stale')]:
            bad = [dict(row) for row in self.rows]
            bad[0][key] = value
            with self.assertRaises(ValueError):
                validate_controls(self.receipt, bad)

    def test_missing_duplicate_incomplete_clock_skew_rejected(self):
        for rows in (self.rows[:1], self.rows + [self.rows[0]],
                     [dict(self.rows[0], dur='-1'), self.rows[1]],
                     [dict(self.rows[0], ts='1200000000'), self.rows[1]]):
            with self.assertRaises(ValueError):
                validate_controls(self.receipt, rows)

    @unittest.skipUnless(os.environ.get('TRACE_PROCESSOR'), 'Set TRACE_PROCESSOR for real parser identity negatives')
    def test_real_parser_receipt_apk_and_payload_negatives(self):
        from verify_probe import FILES, sha256, verify
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / self.nonce
            directory.mkdir()
            for name in FILES:
                (directory / name).write_bytes(b'')
            (directory / 'capture.perfetto-trace').write_bytes(trace_fixture(self.nonce))
            (directory / 'capture-start-ack.txt').write_bytes(b'987\nREADY:0\n')
            (directory / 'service-state.pb').write_bytes(field(2, field(1, field(1, 'linux.ftrace'))))
            build = {'source_commit': 'a' * 40, 'source_dirty': False, 'submittable': True,
                     'files': {'app.apk': {'sha256': 'b' * 64}, 'test.apk': {'sha256': 'c' * 64}}}
            build_path = Path(temporary) / 'build.json'
            build_path.write_text(json.dumps(build))
            receipt = dict(self.receipt, schema_version=1, scope='model_free_trace_collection_capability',
                           gpu_inference_qualified=False, trace_semantics_validated=False,
                           source_commit_declaration=build['source_commit'], app_apk_sha256='b' * 64,
                           test_apk_sha256='c' * 64, uid=10001, api=36,
                           package='dev.llamadart.validation.perfetto', no_activity_or_flutter_engine=True,
                           app_hardware_accelerated=False, atrace_enabled_when_markers_submitted=True,
                           capture_session_start_acknowledged=True, capture_session_pid=987, capture_ack_boottime_ns=900000000,
                           discovered_render_stage_source_names=[])
            receipt['files'] = {name: {'sha256': sha256(directory / name), 'bytes': (directory / name).stat().st_size}
                                for name in FILES}
            receipt_path = directory / 'receipt.json'
            receipt_path.write_text(json.dumps(receipt))
            binary = Path(os.environ['TRACE_PROCESSOR'])
            result = verify(directory, build_path, binary, sha256(binary))
            self.assertTrue(result['trace_collection_validated'])
            self.assertFalse(result['gpu_inference_qualified'])
            self.assertFalse(result['render_stage_transport_observed'])
            for key, bad in [('app_apk_sha256', 'd' * 64), ('test_apk_sha256', 'd' * 64),
                             ('source_commit_declaration', 'd' * 40), ('gpu_inference_qualified', True),
                             ('capture_session_start_acknowledged', False), ('capture_session_pid', 0),
                             ('capture_ack_boottime_ns', 1000000001)]:
                receipt_path.write_text(json.dumps(dict(receipt, **{key: bad})))
                with self.assertRaises(ValueError):
                    verify(directory, build_path, binary, sha256(binary))
            receipt_path.write_text(json.dumps(receipt))
            (directory / 'capture.perfetto-trace').write_bytes(b'tampered')
            with self.assertRaises(ValueError):
                verify(directory, build_path, binary, sha256(binary))

    @unittest.skipUnless(os.environ.get('TRACE_PROCESSOR'), 'Set TRACE_PROCESSOR for real schema/parser regression')
    def test_real_trace_processor_control_schema(self):
        from verify_probe import query
        with tempfile.TemporaryDirectory() as temporary:
            trace = Path(temporary) / 'controls.perfetto-trace'
            trace.write_bytes(trace_fixture(self.nonce))
            self.assertEqual(packet_counts(trace.read_bytes())['packets'], 1)
            rows, _ = query(Path(os.environ['TRACE_PROCESSOR']), trace,
                "SELECT s.name, s.ts, s.dur, p.pid FROM slice s JOIN process_track t ON t.id=s.track_id JOIN process p ON p.upid=t.upid WHERE s.name GLOB 'llamadart_probe_*' ORDER BY s.ts")
            validate_controls(self.receipt, rows)
            errors, _ = query(Path(os.environ['TRACE_PROCESSOR']), trace,
                "SELECT name, severity, value FROM stats WHERE value > 0 AND severity IN ('error', 'data_loss')")
            self.assertEqual(errors, [])


if __name__ == '__main__':
    unittest.main()
