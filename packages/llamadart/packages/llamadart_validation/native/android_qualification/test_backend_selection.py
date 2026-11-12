"""Compile the real selector against model-free backend registry controls."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class BackendSelectionTest(unittest.TestCase):
    def test_registry_and_discrete_integrated_device_controls(self):
        compiler = shutil.which("c++")
        if compiler is None:
            self.skipTest("A C++ compiler is required for the model-free selector")
        native = Path(__file__).resolve().parent
        fixture = native.parents[1] / "test/fixtures/android_qualification/backend_selection"
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "backend-selection"
            subprocess.run([compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                            "-I" + str(native), "-I" + str(fixture),
                            str(fixture / "main.cpp"), "-o", str(binary)], check=True,
                           capture_output=True, text=True, timeout=60)
            cases = ("mali-integrated", "discrete", "shared-device-name", "cpu-plus-mali",
                     "cpu-only", "cpu-with-vulkan-registry", "opencl-only", "accelerator",
                     "meta", "missing-registry-name", "no-devices", "multiple-integrated",
                     "multiple-discrete", "mixed-vulkan-gpus")
            for case in cases:
                with self.subTest(case=case):
                    subprocess.run([str(binary), case], check=True, capture_output=True,
                                   text=True, timeout=5)


if __name__ == "__main__":
    unittest.main()
