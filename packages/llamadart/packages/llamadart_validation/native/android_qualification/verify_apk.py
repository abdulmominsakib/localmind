"""Static paired-runtime admission only; never implies Android launch or inference."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

INSTRUMENTATION_CLASSES = frozenset({
    "dev.flutter.plugins.integration_test.IntegrationTestPlugin",
    "dev.flutter.plugins.integration_test.FlutterTestRunner",
})
ANDROID_RUNNER = "androidx.test.runner.AndroidJUnitRunner"
TEST_CLASS = "com.example.llamadart_chat_example.MainActivityTest"
FRAMEWORK_CLASSES = frozenset({
    ANDROID_RUNNER,
    "androidx.test.rule.ActivityTestRule",
    "androidx.test.platform.app.InstrumentationRegistry",
    "org.junit.runner.RunWith",
    "org.junit.Rule",
})
ANDROID = "{http://schemas.android.com/apk/res/android}"


def parse_defined_classes(output):
    # Android SDK apkanalyzer: row kind, defined/reference, method counts,
    # byte size, then the exact class name. References and members cannot pass.
    classes = set()
    for line in output.splitlines():
        fields = line.split()
        if not fields or fields[0] != "C":
            continue
        if (len(fields) != 6 or fields[1] not in ("d", "r") or
                not all(value.isdecimal() for value in fields[2:5])):
            raise ValueError("Malformed apkanalyzer class row")
        if fields[1] == "d":
            classes.add(fields[5])
    return classes


def analyze(apkanalyzer, *arguments):
    with tempfile.TemporaryFile() as output:
        result = subprocess.run(
            [str(apkanalyzer), *map(str, arguments)],
            stdout=output, stderr=subprocess.PIPE, timeout=120, check=False)
        if result.returncode != 0:
            raise ValueError("apkanalyzer failed to inspect APK")
        if output.tell() > 64 * 1024 * 1024:
            raise ValueError("apkanalyzer output exceeds size bound")
        output.seek(0)
        return output.read().decode("utf-8")


def manifest_identity(output):
    root = ET.fromstring(output)
    package = root.get("package")
    if root.tag != "manifest" or not package:
        raise ValueError("APK manifest lacks package identity")
    return root, package


def verify_test_annotations(output):
    # Inspect the actual test DEX: class-name definitions alone cannot prove
    # that R8 retained the runtime annotations used by both runner layers.
    header = output.split("# static fields", 1)[0].split("# instance fields", 1)[0]
    if not re.search(
            r"(?m)^\.annotation runtime Lorg/junit/runner/RunWith;\s+"
            r"value = Ldev/flutter/plugins/integration_test/FlutterTestRunner;\s+"
            r"\.end annotation$", header):
        raise ValueError("Test DEX lacks runtime @RunWith(FlutterTestRunner)")
    fields = re.findall(r"(?ms)^\.field .*?^\.end field$", output)
    if not any(re.search(r"(?m)^\.field public rule:Landroidx/test/rule/ActivityTestRule;$", field)
               and re.search(r"(?m)^    \.annotation runtime Lorg/junit/Rule;\s+"
                             r"\.end annotation$", field) for field in fields):
        raise ValueError("Test DEX lacks public ActivityTestRule with runtime @Rule")


def verify_instrumentation_classes(apk, test_apk, apkanalyzer):
    if apkanalyzer is None:
        raise ValueError("Consumer release APK verification requires --apkanalyzer")
    if test_apk is None or test_apk.resolve() == apk.resolve():
        raise ValueError("Consumer release APK verification requires a separate --test-apk")
    app_manifest, app_package = manifest_identity(analyze(apkanalyzer, "manifest", "print", apk))
    test_manifest, test_package = manifest_identity(analyze(apkanalyzer, "manifest", "print", test_apk))
    declarations = test_manifest.findall("instrumentation")
    if (app_manifest.findall("instrumentation") or len(declarations) != 1 or
            test_package == app_package or declarations[0].get(ANDROID + "targetPackage") != app_package):
        raise ValueError("APK pair instrumentation target mismatch")
    runner = declarations[0].get(ANDROID + "name")
    if runner != ANDROID_RUNNER:
        raise ValueError("Unexpected manifest-declared instrumentation runner")
    app_classes = parse_defined_classes(analyze(apkanalyzer, "dex", "packages", "--defined-only", apk))
    test_classes = parse_defined_classes(analyze(apkanalyzer, "dex", "packages", "--defined-only", test_apk))
    if not INSTRUMENTATION_CLASSES.issubset(app_classes):
        raise ValueError("Consumer APK lacks defined, unobfuscated integration_test classes")
    if not FRAMEWORK_CLASSES.issubset(app_classes | test_classes):
        raise ValueError("APK pair lacks defined, unobfuscated manifest runner or reflective test framework")
    if TEST_CLASS not in test_classes:
        raise ValueError("Test APK lacks defined MainActivityTest")
    verify_test_annotations(analyze(apkanalyzer, "dex", "code", "--class", TEST_CLASS, test_apk))
    return {"classes_defined": sorted(INSTRUMENTATION_CLASSES | FRAMEWORK_CLASSES | {TEST_CLASS}),
            "runner": runner, "target_package": app_package,
            "test_apk_sha256": hashlib.sha256(test_apk.read_bytes()).hexdigest(),
            "test_runtime_annotations_verified": True}


def verify(apk, binding, plan, apkanalyzer=None, test_apk=None):
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate APK entries")
        prefix = "assets/llamadart_android_qualification/"
        if json.loads(archive.read(prefix + "binding.json")) != binding:
            raise ValueError("APK build binding mismatch")
        if archive.read(prefix + "plan.json") != plan:
            raise ValueError("APK request contract mismatch")
        if hashlib.sha256(plan).hexdigest() != binding["plan_sha256"]:
            raise ValueError("APK request hash mismatch")
        expected = set(binding["libraries"])
        observed = {Path(name).name for name in names if name.startswith("lib/arm64-v8a/")
                    and Path(name).name.startswith(("libllama", "libggml", "libmtmd"))}
        if observed != expected:
            raise ValueError("APK paired-runtime inventory mismatch")
        for name, lock in binding["libraries"].items():
            if Path(name).name != name:
                raise ValueError("Unsafe APK runtime name")
            entry = "lib/arm64-v8a/" + name
            info = archive.getinfo(entry)
            if info.file_size != lock["bytes"] or info.file_size > 256 * 1024 * 1024:
                raise ValueError("APK library size mismatch")
            data = archive.read(entry)
            if hashlib.sha256(data).hexdigest() != lock["sha256"]:
                raise ValueError("APK library bytes differ from admitted archive/probe")
            if data[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", data, 18)[0] != 183:
                raise ValueError("Expected arm64 ELF runtime")
            phoff = struct.unpack_from("<Q", data, 32)[0]
            size, count = struct.unpack_from("<HH", data, 54)
            if size != 56 or count < 1 or phoff + size * count > len(data):
                raise ValueError("Invalid ELF program headers")
            for index in range(count):
                offset = phoff + index * size
                kind = struct.unpack_from("<I", data, offset)[0]
                alignment = struct.unpack_from("<Q", data, offset + 48)[0]
                if kind == 1 and alignment < 16384:
                    raise ValueError("Runtime lacks 16 KiB LOAD alignment")
            if name == "libllamadart_android_qualification.so":
                if struct.unpack_from("<Q", data, 24)[0] == 0:
                    raise ValueError("Diagnostic probe lacks an executable entry point")
    result = {"qualified": False, "android_launch_observed": False,
              "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest()}
    if json.loads(plan).get("scenario") == "consumer-cpu":
        result["instrumentation"] = verify_instrumentation_classes(apk, test_apk, apkanalyzer)
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("apk", "binding", "plan"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--apkanalyzer", type=Path)
    parser.add_argument("--test-apk", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.apk, json.loads(args.binding.read_text()), args.plan.read_bytes(),
                            args.apkanalyzer, args.test_apk)))
