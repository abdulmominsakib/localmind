"""Check the built app's optional vendor OpenCL request; no runtime execution."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"


def require_optional_opencl(output):
    manifest = ET.fromstring(output)
    if manifest.tag != "manifest" or not manifest.get("package"):
        raise ValueError("APK manifest lacks package identity")
    sdk = manifest.findall("uses-sdk")
    if len(sdk) != 1:
        raise ValueError("APK manifest lacks one target SDK declaration")
    target = sdk[0].get(ANDROID + "targetSdkVersion", "")
    if not target.isdecimal():
        raise ValueError("APK manifest target SDK must be numeric")
    applications = manifest.findall("application")
    if len(applications) != 1:
        raise ValueError("APK manifest lacks one application")
    declarations = [node for node in manifest.iter("uses-native-library")
                    if node.get(ANDROID + "name") == "libOpenCL.so"]
    if (len(declarations) != 1 or
            declarations[0] not in applications[0].findall("uses-native-library") or
            declarations[0].get(ANDROID + "required") != "false"):
        raise ValueError("APK must request libOpenCL.so once as an optional application library")
    return {"package": manifest.get("package"), "target_sdk": int(target),
            "optional_native_library": "libOpenCL.so"}


def verify(apk, apkanalyzer):
    with tempfile.TemporaryFile() as output:
        result = subprocess.run(
            [str(apkanalyzer), "manifest", "print", str(apk)],
            stdout=output, stderr=subprocess.PIPE, timeout=120, check=False)
        if result.returncode != 0 or output.tell() > 1024 * 1024:
            raise ValueError("Cannot inspect bounded built APK manifest")
        output.seek(0)
        receipt = require_optional_opencl(output.read().decode("utf-8"))
    receipt.update(apk_sha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
                   qualified=False, runtime_execution=False)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--apkanalyzer", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.apk, args.apkanalyzer), indent=2))


if __name__ == "__main__":
    main()
