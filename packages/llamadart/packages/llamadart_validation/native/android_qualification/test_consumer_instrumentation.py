"""Model-free paired release instrumentation and reflective framework controls."""
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import verify_apk


PLUGIN = "dev.flutter.plugins.integration_test.IntegrationTestPlugin"
RUNNER = "dev.flutter.plugins.integration_test.FlutterTestRunner"
APP_PACKAGE = "com.example.llamadart_chat_example"
APP_MANIFEST = f'<manifest package="{APP_PACKAGE}"/>'
TEST_MANIFEST = f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
package="{APP_PACKAGE}.test"><instrumentation
android:name="{verify_apk.ANDROID_RUNNER}" android:targetPackage="{APP_PACKAGE}"/></manifest>'''
TEST_CODE = '''.class public Lcom/example/llamadart_chat_example/MainActivityTest;
.super Ljava/lang/Object;
# annotations
.annotation runtime Lorg/junit/runner/RunWith;
    value = Ldev/flutter/plugins/integration_test/FlutterTestRunner;
.end annotation
# instance fields
.field public rule:Landroidx/test/rule/ActivityTestRule;
    .annotation runtime Lorg/junit/Rule;
    .end annotation
.end field
'''


def rows(classes):
    return "".join(f"C d 1 1 100 {name}\n" for name in classes)


class ConsumerInstrumentationTest(unittest.TestCase):
    def test_only_exact_defined_class_rows_count(self):
        observed = verify_apk.parse_defined_classes(
            f"P d 10 10 950 dev.flutter.plugins.integration_test\n"
            f"C d 10 10 950 {PLUGIN}\nC r 0 0 0 {RUNNER}\n"
            f"M d 1 1 52 {RUNNER} <init>()\nC d 1 1 100 {RUNNER}Suffix\n")
        self.assertEqual(observed, {PLUGIN, RUNNER + "Suffix"})
        for row in [f"C d x 1 1 {PLUGIN}", f"C d 1 1 {PLUGIN}"]:
            with self.assertRaises(ValueError):
                verify_apk.parse_defined_classes(row)

    def inspect(self, *, app_classes=None, test_classes=None, test_manifest=TEST_MANIFEST,
                app_manifest=APP_MANIFEST, code=TEST_CODE, failed_command=None):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "app.apk"
            test = Path(temporary) / "test.apk"
            test.write_bytes(b"test-apk")
            outputs = {
                ("manifest", "print", str(app)): app_manifest,
                ("manifest", "print", str(test)): test_manifest,
                ("dex", "packages", "--defined-only", str(app)): rows(
                    verify_apk.INSTRUMENTATION_CLASSES | verify_apk.FRAMEWORK_CLASSES
                    if app_classes is None else app_classes),
                ("dex", "packages", "--defined-only", str(test)): rows(
                    {verify_apk.TEST_CLASS} if test_classes is None else test_classes),
                ("dex", "code", "--class", verify_apk.TEST_CLASS, str(test)): code,
            }
            def run(argv, **kwargs):
                self.assertEqual(argv[0], "/sdk/apkanalyzer")
                self.assertEqual(kwargs["timeout"], 120)
                kwargs["stdout"].write(outputs[tuple(argv[1:])].encode())
                return SimpleNamespace(returncode=1 if failed_command == argv[1:3] else 0)
            with patch.object(verify_apk.subprocess, "run", side_effect=run):
                return verify_apk.verify_instrumentation_classes(app, test, Path("/sdk/apkanalyzer"))

    def test_pair_manifest_runner_framework_and_runtime_annotations(self):
        result = self.inspect()
        self.assertEqual(result["runner"], verify_apk.ANDROID_RUNNER)
        self.assertEqual(result["target_package"], APP_PACKAGE)
        self.assertEqual(result["test_apk_sha256"], hashlib.sha256(b"test-apk").hexdigest())
        self.assertTrue(result["test_runtime_annotations_verified"])
        # Framework dependencies may be packaged in either APK; the SDK plugin
        # must be in the target app, where the Flutter engine registers it.
        self.inspect(app_classes=verify_apk.INSTRUMENTATION_CLASSES,
                     test_classes=verify_apk.FRAMEWORK_CLASSES | {verify_apk.TEST_CLASS})

    def test_each_missing_or_obfuscated_framework_entry_is_rejected(self):
        required = verify_apk.INSTRUMENTATION_CLASSES | verify_apk.FRAMEWORK_CLASSES
        for missing in required:
            with self.subTest(missing=missing), self.assertRaises(ValueError):
                self.inspect(app_classes=(required - {missing}) | {"a.b"})
        with self.assertRaisesRegex(ValueError, "MainActivityTest"):
            self.inspect(test_classes=set())
        # This was the failed release's old two-class acceptance condition.
        with self.assertRaisesRegex(ValueError, "manifest runner or reflective"):
            self.inspect(app_classes=verify_apk.INSTRUMENTATION_CLASSES)

    def test_missing_wrong_duplicate_or_mismatched_manifest_runner_is_rejected(self):
        declaration = TEST_MANIFEST[TEST_MANIFEST.index('<instrumentation'):TEST_MANIFEST.index('/>') + 2]
        for manifest in [TEST_MANIFEST.replace(declaration, ""),
                         TEST_MANIFEST.replace(verify_apk.ANDROID_RUNNER, "a.b"),
                         TEST_MANIFEST.replace(APP_PACKAGE + '"/>', 'other.package"/>'),
                         TEST_MANIFEST.replace(declaration, declaration * 2),
                         '<manifest/>']:
            with self.subTest(manifest=manifest), self.assertRaises(ValueError):
                self.inspect(test_manifest=manifest)

    def test_actual_test_annotations_cannot_be_removed_renamed_or_nonruntime(self):
        for code in ["", TEST_CODE.replace("RunWith;", "a;"),
                     TEST_CODE.replace("FlutterTestRunner;", "OtherRunner;"),
                     TEST_CODE.replace("Lorg/junit/Rule;", "LB1/a;"),
                     TEST_CODE.replace(".annotation runtime", ".annotation build"),
                     TEST_CODE.replace(".field public rule:", ".field private rule:"),
                     TEST_CODE.replace("Landroidx/test/rule/ActivityTestRule;", "La/b;")]:
            with self.subTest(code=code), self.assertRaises(ValueError):
                self.inspect(code=code)
        # A method annotation or annotation-looking string is not a field rule.
        with self.assertRaises(ValueError):
            self.inspect(code=TEST_CODE.replace(".field public rule:", ".method public rule:"))

    def test_analyzer_failure_missing_tool_and_missing_pair_fail_closed(self):
        for command in (["manifest", "print"], ["dex", "packages"], ["dex", "code"]):
            with self.subTest(command=command), self.assertRaises(ValueError):
                self.inspect(failed_command=command)
        with self.assertRaisesRegex(ValueError, "requires --apkanalyzer"):
            verify_apk.verify_instrumentation_classes(Path('/app.apk'), Path('/test.apk'), None)
        for test in (None, Path('/app.apk')):
            with self.assertRaisesRegex(ValueError, "separate --test-apk"):
                verify_apk.verify_instrumentation_classes(Path('/app.apk'), test, Path('/sdk/apkanalyzer'))

    def test_consumer_apk_cannot_skip_pair_inspection(self):
        with tempfile.TemporaryDirectory() as temporary:
            apk = Path(temporary) / "consumer.apk"
            test = Path(temporary) / "test.apk"
            plan = b'{"schema":1,"scenario":"consumer-cpu"}'
            binding = {"plan_sha256": hashlib.sha256(plan).hexdigest(), "libraries": {}}
            with zipfile.ZipFile(apk, "w") as archive:
                prefix = "assets/llamadart_android_qualification/"
                archive.writestr(prefix + "binding.json", json.dumps(binding))
                archive.writestr(prefix + "plan.json", plan)
            with self.assertRaisesRegex(ValueError, "requires --apkanalyzer"):
                verify_apk.verify(apk, binding, plan)
            with patch.object(verify_apk, "verify_instrumentation_classes", return_value={"proof": True}) as inspect:
                result = verify_apk.verify(apk, binding, plan, Path('/sdk/apkanalyzer'), test)
                inspect.assert_called_once_with(apk, test, Path('/sdk/apkanalyzer'))
                self.assertEqual(result["instrumentation"], {"proof": True})
                self.assertFalse(result["qualified"])
                self.assertFalse(result["android_launch_observed"])


if __name__ == "__main__":
    unittest.main()
