"""In-memory fabricated Mach-O controls only; no actual runtime is accessed."""

import contextlib
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

import compare_macho_identity as target


BASE = 0x100000000
DATA = 1024


def name(value):
    return value.encode("ascii").ljust(16, b"\0")


def section(sn, offset, length, flags=0, addr=None):
    return struct.pack("<16s16sQQ8I", name(sn), name("__TEXT"),
        BASE + offset if addr is None else addr, length, offset, 0, 0, 0,
        flags, 0, 0, 0)


def dylib(value, cmd=0xD):
    tail = value.encode() + b"\0"
    size = (24 + len(tail) + 7) & ~7
    return struct.pack("<6I", cmd, size, 24, 0, 0x10000, 0x10000) + tail.ljust(size - 24, b"\0")


def fixture(text=b"TEXTDATA", uuid=b"0123456789abcdef", tail=b"SIGNATURE-BYTES!!",
            zero_flag=1, section_flags=0, extra_commands=(), duplicate_section=False):
    assert len(text) == 8
    sections = [section("__text", DATA, 8, section_flags),
                section("__const", DATA + 8, 8),
                section("__bss", 0, 64, zero_flag, BASE + 4096)]
    if duplicate_section:
        sections.append(sections[0])
    text_segment = struct.pack("<II16sQQQQiiII", 0x19, 72 + len(sections) * 80,
        name("__TEXT"), BASE, 8192, 0, DATA + 16, 7, 5, len(sections), 0) + b"".join(sections)
    linkedit = struct.pack("<II16sQQQQiiII", 0x19, 72, name("__LINKEDIT"),
        BASE + 8192, 4096, DATA + 16, len(tail), 1, 1, 0, 0)
    commands = [text_segment, linkedit, struct.pack("<II16s", 0x1B, 24, uuid),
                struct.pack("<4I", 0x1D, 16, DATA + 16, len(tail)), dylib("self")]
    commands.extend(extra_commands)
    body = b"".join(commands)
    header = struct.pack("<8I", target.MAGIC, target.ARM64, 0, 6, len(commands), len(body), 0, 0)
    assert len(header + body) <= DATA
    return (header + body).ljust(DATA, b"\0") + text + b"DATA1234" + tail


def set_u32(data, offset, value):
    result = bytearray(data)
    struct.pack_into("<I", result, offset, value)
    return bytes(result)


class IdentityControls(unittest.TestCase):
    def test_identical(self):
        result = target.compare(fixture(), fixture())
        self.assertTrue(result["code_data_uuid_identity"])
        self.assertTrue(result["whole_file_identity"])
        self.assertFalse(result["runtime_identity_proven"])
        self.assertEqual(2, result["left"]["nonempty_file_backed_section_count"])
        self.assertEqual(3, result["left"]["section_count"])

    def test_changed_section_byte_refused(self):
        result = target.compare(fixture(), fixture(text=b"TEXTDATX"))
        self.assertFalse(result["code_data_uuid_identity"])
        self.assertFalse(result["checks"]["section_bytes_equal"])
        self.assertFalse(result["checks"]["ordered_section_metadata_and_hashes_equal"])

    def test_changed_uuid_refused(self):
        result = target.compare(fixture(), fixture(uuid=b"FEDCBA9876543210"))
        self.assertFalse(result["code_data_uuid_identity"])
        self.assertFalse(result["checks"]["uuid_equal"])
        self.assertTrue(result["checks"]["section_bytes_equal"])

    def test_changed_flags_refused(self):
        self.assertFalse(target.compare(fixture(), fixture(section_flags=0x80000000))["code_data_uuid_identity"])

    def test_fabricated_signature_tail_change_is_not_whole_identity(self):
        result = target.compare(fixture(), fixture(tail=b"DIFFERENT-BYTES!!"))
        self.assertTrue(result["code_data_uuid_identity"])
        self.assertFalse(result["whole_file_identity"])
        self.assertFalse(result["referenced_payloads_equal"])
        self.assertTrue(result["load_commands_equal"])
        self.assertIn("Unattributed", result["transformation_cause"])

    def test_signature_tail_length_and_command_delta_reported(self):
        result = target.compare(fixture(), fixture(tail=b"longer fabricated signature"))
        self.assertTrue(result["code_data_uuid_identity"])
        self.assertFalse(result["load_commands_equal"])
        self.assertFalse(result["whole_file_identity"])

    def test_dependency_difference_separate_and_no_runtime_claim(self):
        a = fixture(extra_commands=(dylib("/A", 0xC),))
        b = fixture(extra_commands=(dylib("/B", 0xC),))
        result = target.compare(a, b)
        self.assertTrue(result["code_data_uuid_identity"])
        self.assertFalse(result["dylib_commands_equal"])
        self.assertFalse(result["load_commands_equal"])
        self.assertFalse(result["runtime_identity_proven"])

    def test_only_three_documented_zerofill_types_skip_content(self):
        for flag, label in target.ZEROFILL.items():
            with self.subTest(flag=flag):
                result = target.parse(fixture(zero_flag=flag))
                self.assertEqual(label, result["sections"][2]["skip_reason"])
                self.assertNotIn("sha256", result["sections"][2])
        with self.assertRaises(target.InvalidMachO):
            target.parse(fixture(zero_flag=0x13))  # file-backed section at header offset

    def test_zerofill_metadata_change_refused(self):
        result = target.compare(fixture(zero_flag=1), fixture(zero_flag=12))
        self.assertFalse(result["code_data_uuid_identity"])

    def test_empty_section_retains_metadata_without_hash(self):
        data = set_u32(fixture(), 32 + 72 + 80 + 40, 0)
        result = target.parse(data)
        self.assertEqual(3, result["section_count"])
        self.assertEqual(1, result["nonempty_file_backed_section_count"])
        self.assertEqual("empty section; metadata compared", result["sections"][1]["skip_reason"])
        self.assertNotIn("sha256", result["sections"][1])
        self.assertFalse(target.compare(fixture(), data)["code_data_uuid_identity"])

    def test_complete_ordered_section_sequence_compared(self):
        original = fixture()
        data = bytearray(original)
        start = 32 + 72
        data[start:start + 80], data[start + 80:start + 160] = (
            data[start + 80:start + 160], data[start:start + 80])
        result = target.compare(original, bytes(data))
        self.assertFalse(result["code_data_uuid_identity"])
        self.assertFalse(result["checks"]["ordered_section_metadata_and_hashes_equal"])

    def test_all_truncations_refused(self):
        data = fixture()
        for length in range(len(data)):
            with self.subTest(length=length), self.assertRaises(target.InvalidMachO):
                target.parse(data[:length])

    def test_unsupported_magic_cpu_filetype(self):
        for offset, value in ((0, 0xCAFEBABE), (0, 0xCFFAEDFE), (4, 0x01000007), (12, 1)):
            with self.subTest(offset=offset, value=value), self.assertRaises(target.InvalidMachO):
                target.parse(set_u32(fixture(), offset, value))

    def test_bad_command_sizes_and_count(self):
        for offset, value in ((36, 0), (36, 9), (36, 0xFFFFFFF8), (16, 0), (16, 100000), (20, 8), (20, 0xFFFFFFFF)):
            with self.subTest(offset=offset, value=value), self.assertRaises(target.InvalidMachO):
                target.parse(set_u32(fixture(), offset, value))

    def test_section_outside_file_segment_and_vm(self):
        start = 32 + 72
        # section_64 offset is +48; addr is +32; size is +40.
        for offset, value in ((start + 48, 0xFFFFFFFF), (start + 48, 900), (start + 40, 0xFFFFFFFF)):
            with self.subTest(offset=offset, value=value), self.assertRaises(target.InvalidMachO):
                target.parse(set_u32(fixture(), offset, value))

    def test_duplicate_uuid_section_segment_and_dependency_refused(self):
        cases = [fixture(extra_commands=(struct.pack("<II16s", 0x1B, 24, b"0123456789abcdef"),)),
                 fixture(duplicate_section=True), fixture(extra_commands=(dylib("other"),))]
        for data in cases:
            with self.assertRaises(target.InvalidMachO):
                target.parse(data)
        data = bytearray(fixture())
        linkedit_start = 32 + 72 + 3 * 80
        data[linkedit_start + 8:linkedit_start + 24] = name("__TEXT")
        with self.assertRaises(target.InvalidMachO):
            target.parse(bytes(data))

    def test_overlapping_sections_refused(self):
        data = set_u32(fixture(), 32 + 72 + 80 + 48, DATA + 4)
        with self.assertRaises(target.InvalidMachO):
            target.parse(data)

    def test_unknown_command_refused(self):
        with self.assertRaisesRegex(target.InvalidMachO, "unsupported load command"):
            target.parse(fixture(extra_commands=(struct.pack("<2I", 0x76543210, 8),)))

    def test_signature_payload_outside_file_refused(self):
        start = 32 + 72 + 3 * 80 + 72 + 24
        with self.assertRaises(target.InvalidMachO):
            target.parse(set_u32(fixture(), start + 8, 0xFFFFFFFF))

    def test_cli_synthetic_input_success_mismatch_and_malformed(self):
        with tempfile.TemporaryDirectory() as folder:
            left, right = Path(folder) / "a", Path(folder) / "b"
            left.write_bytes(fixture())
            for data, status in ((fixture(tail=b"DIFFERENT-BYTES!!"), 0),
                                 (fixture(text=b"TEXTDATX"), 1), (b"bad", 2)):
                right.write_bytes(data)
                output = io.StringIO()
                with patch.object(sys, "argv", ["compare", str(left), str(right)]), contextlib.redirect_stdout(output):
                    self.assertEqual(status, target.main())
                result = json.loads(output.getvalue())
                self.assertFalse(result["runtime_identity_proven"])


if __name__ == "__main__":
    unittest.main()
