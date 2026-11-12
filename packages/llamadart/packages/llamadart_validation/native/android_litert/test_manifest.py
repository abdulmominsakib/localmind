"""Model-free mutation controls for effective APK OpenCL admission."""
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import verify_manifest

OPENCL = '<uses-native-library android:name="libOpenCL.so" android:required="false"/>'
MANIFEST = (f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
            f'package="example.app"><uses-sdk android:targetSdkVersion="36"/>'
            f'<application>{OPENCL}</application></manifest>')


class ManifestTest(unittest.TestCase):
    def test_optional_request_and_target_version_are_read_from_effective_manifest(self):
        for target in (29, 31, 36):
            result = verify_manifest.require_optional_opencl(
                MANIFEST.replace('targetSdkVersion="36"', f'targetSdkVersion="{target}"'))
            self.assertEqual(result['target_sdk'], target)
            self.assertEqual(result['optional_native_library'], 'libOpenCL.so')

    def test_missing_required_duplicate_or_misplaced_vendor_request_fails(self):
        for manifest in [MANIFEST.replace(OPENCL, ''),
                         MANIFEST.replace('android:required="false"', 'android:required="true"'),
                         MANIFEST.replace(' android:required="false"', ''),
                         MANIFEST.replace(OPENCL, OPENCL * 2),
                         MANIFEST.replace(OPENCL, '').replace('</manifest>', OPENCL + '</manifest>'),
                         MANIFEST.replace('libOpenCL.so', 'libOpenCL.so.other'),
                         MANIFEST.replace('targetSdkVersion="36"', 'targetSdkVersion="preview"'),
                         MANIFEST.replace('<application>', '<activity>').replace('</application>', '</activity>')]:
            with self.subTest(manifest=manifest), self.assertRaises(ValueError):
                verify_manifest.require_optional_opencl(manifest)

    def test_verifier_inspects_apk_and_does_not_trust_source_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = Path(temporary) / 'app.apk'
            apk.write_bytes(b'APK identity')

            def run(argv, **kwargs):
                self.assertEqual(argv, ['/sdk/apkanalyzer', 'manifest', 'print', str(apk)])
                self.assertEqual(kwargs['timeout'], 120)
                kwargs['stdout'].write(MANIFEST.encode())
                return SimpleNamespace(returncode=0)

            with patch.object(verify_manifest.subprocess, 'run', side_effect=run):
                result = verify_manifest.verify(apk, Path('/sdk/apkanalyzer'))
            self.assertEqual(result['package'], 'example.app')
            self.assertFalse(result['qualified'])
            self.assertFalse(result['runtime_execution'])
            for output in ('<manifest/>', MANIFEST.replace(OPENCL, '')):
                with patch.object(verify_manifest.subprocess, 'run') as command:
                    command.side_effect = lambda argv, **kwargs: (
                        kwargs['stdout'].write(output.encode()), SimpleNamespace(returncode=0))[1]
                    with self.assertRaises(ValueError):
                        verify_manifest.verify(apk, Path('/sdk/apkanalyzer'))


if __name__ == '__main__':
    unittest.main()
