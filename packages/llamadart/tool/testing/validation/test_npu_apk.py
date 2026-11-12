import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from check_npu_apk import verify


class NpuApkTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.apk = Path(self.temp.name) / "app.apk"
        record = lambda data: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        self.profile = {"id": "npu-fixture", "model": record(b"model"),
                        "npu_target": {"libraries": {"libLiteRtDispatch_Test.so": record(b"library")}}}
        self.kit = {"libraries": self.profile["npu_target"]["libraries"]}
        self.files = {
            "assets/llamadart_npu/profile.json": json.dumps(self.profile).encode(),
            "assets/llamadart_npu/npu-kit.json": json.dumps(self.kit).encode(),
            "assets/llamadart_npu/model.litertlm": b"model",
            "lib/arm64-v8a/libLiteRtDispatch_Test.so": b"library",
        }

    def write(self):
        with zipfile.ZipFile(self.apk, "w") as archive:
            for name, data in self.files.items():
                archive.writestr(name, data)

    def test_exact_inputs(self):
        self.write()
        verify(self.apk, self.profile, self.kit)

    def test_modified_model_even_at_same_size(self):
        self.files["assets/llamadart_npu/model.litertlm"] = b"Model"
        self.write()
        with self.assertRaises(ValueError): verify(self.apk, self.profile, self.kit)

    def test_missing_library(self):
        del self.files["lib/arm64-v8a/libLiteRtDispatch_Test.so"]
        self.write()
        with self.assertRaises(ValueError): verify(self.apk, self.profile, self.kit)

    def test_stale_vendor_library(self):
        self.files["lib/arm64-v8a/libLiteRtDispatch_Other.so"] = b"stale"
        self.write()
        with self.assertRaises(ValueError): verify(self.apk, self.profile, self.kit)

    def test_different_embedded_profile(self):
        self.files["assets/llamadart_npu/profile.json"] = json.dumps({**self.profile, "id": "other"}).encode()
        self.write()
        with self.assertRaises(ValueError): verify(self.apk, self.profile, self.kit)


if __name__ == "__main__":
    unittest.main()
