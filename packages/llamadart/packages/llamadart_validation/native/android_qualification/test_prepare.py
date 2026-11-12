"""Model-free hostile artifact controls for diagnostic preparation/admission."""
import hashlib
import io
import json
from pathlib import Path
import struct
import tarfile
import tempfile
import unittest
import zipfile

import build_probe
import verify_apk

class PreparationTest(unittest.TestCase):
    def test_archive_traversal_and_links_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for index, name in enumerate(("../escape", "/absolute", "link")):
                archive = root / (str(index) + ".tar")
                with tarfile.open(archive, "w") as target:
                    entry = tarfile.TarInfo(name)
                    if name == "link":
                        entry.type = tarfile.SYMTYPE
                        entry.linkname = "../escape"
                    else:
                        entry.size = 1
                    target.addfile(entry, io.BytesIO(b"x"))
                with self.assertRaises(ValueError):
                    build_probe.unpack(archive, root / str(index), build_probe.sha(archive))
            self.assertFalse((root / "escape").exists())

    def test_apk_hash_inventory_and_elf_controls(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            elf = bytearray(120)
            elf[:6] = b"\x7fELF\x02\x01"
            struct.pack_into("<H", elf, 18, 183)
            struct.pack_into("<Q", elf, 24, 1)
            struct.pack_into("<Q", elf, 32, 64)
            struct.pack_into("<HH", elf, 54, 56, 1)
            struct.pack_into("<I", elf, 64, 1)
            struct.pack_into("<Q", elf, 112, 16384)
            plan = b'{"schema":1}'
            owner_fixture = Path(__file__).resolve().parents[2] / (
                "test/fixtures/android_qualification/android_arm64_runtime_names.json")
            owner = json.loads(owner_fixture.read_text())
            self.assertEqual(owner["native_archive_sha256"], build_probe.ARCHIVE_SHA)
            # The production default CPU/Vulkan selector omits only OpenCL;
            # its exact selection is covered by android_qualification_test.dart.
            names = [name for name in owner["libraries"] if name != "libggml-opencl.so"]
            self.assertEqual(len(names), 14)
            self.assertIn("libmtmd.so", names)
            names.append("libllamadart_android_qualification.so")
            self.assertEqual(len(names), 15)
            binding = {"plan_sha256": hashlib.sha256(plan).hexdigest(), "libraries": {
                name: {"bytes": len(elf), "sha256": hashlib.sha256(elf).hexdigest()} for name in names}}
            def apk(mode):
                path = root / (mode + ".apk")
                with zipfile.ZipFile(path, "w") as target:
                    target.writestr("assets/llamadart_android_qualification/binding.json", json.dumps(binding))
                    target.writestr("assets/llamadart_android_qualification/plan.json", plan)
                    for name in names:
                        if mode == "missing-mtmd" and name == "libmtmd.so":
                            continue
                        data = bytes(elf)
                        if mode == "changed-mtmd" and name == "libmtmd.so":
                            data = data[:-1] + b"x"
                        target.writestr("lib/arm64-v8a/" + name, data)
                    extras = {
                        "extra-opencl": "libggml-opencl.so",
                        "extra-llama": "libllama-unexpected.so",
                        "extra-ggml": "libggml-unexpected.so",
                        "extra-mtmd": "libmtmd-unexpected.so",
                    }
                    if mode in extras:
                        target.writestr("lib/arm64-v8a/" + extras[mode], elf)
                return path
            result = verify_apk.verify(apk("good"), binding, plan)
            self.assertFalse(result["qualified"])
            self.assertFalse(result["android_launch_observed"])
            for mode in ("missing-mtmd", "extra-opencl", "extra-llama", "extra-ggml", "extra-mtmd"):
                with self.subTest(mode=mode):
                    with self.assertRaisesRegex(ValueError, "inventory mismatch"):
                        verify_apk.verify(apk(mode), binding, plan)
            with self.assertRaisesRegex(ValueError, "bytes differ"):
                verify_apk.verify(apk("changed-mtmd"), binding, plan)

if __name__ == "__main__":
    unittest.main()
