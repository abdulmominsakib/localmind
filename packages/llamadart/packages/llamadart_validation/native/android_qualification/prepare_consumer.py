"""Seal a public consumer CPU stage; no compiler, model, network or device calls."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess

from build_probe import ARCHIVE_SHA, ROOT, command, sha, unpack


def operator_plan(profile, commit, tree, output):
    defines = ["LLAMADART_ANDROID_CPU_PROFILE=" + profile,
               "LLAMADART_SOURCE_COMMIT=" + commit, "LLAMADART_SOURCE_TREE=" + tree]
    encoded = ",".join(base64.b64encode(value.encode()).decode() for value in defines)
    target = "integration_test/android_consumer_profile_test.dart"
    return {"qualification": False, "profile": profile,
            "consumer_dependency_requirements": {
                "integration_test": {"sdk": "flutter", "section": "dependencies",
                                     "forbidden_section": "dev_dependencies"}},
            "source_commit": commit, "source_tree": tree,
            "environment": {"LLAMADART_ANDROID_CONSUMER_PROFILE_STAGE": str(output / "stage")},
            "commands": [
                {"cwd": "example/chat_app", "argv": ["flutter", "build", "apk", "--release",
                  "--target", target, "--target-platform", "android-arm64"] +
                  ["--dart-define=" + value for value in defines]},
                {"cwd": "example/chat_app/android", "argv": ["./gradlew", "app:assembleAndroidTest",
                  "-Ptarget=" + target, "-Ptarget-platform=android-arm64", "-Pdart-defines=" + encoded]}],
            "run_drafts": [{"device_class": device, "status": "NOT_RUN",
                            "device_model": None, "device_api": None,
                            "device_build": None, "cpu_isa_evidence": None,
                            "app_apk_sha256": None, "test_apk_sha256": None,
                            "instrumentation_arguments": {
                                "stageModel": "true", "androidQualificationScenario": "consumer-cpu",
                                "androidConsumerDeviceClass": device,
                                "androidConsumerDeviceModel": "REQUIRES_ADMISSION",
                                "androidConsumerDeviceApi": "REQUIRES_ADMISSION"}}
                           for device in ("old", "modern")]}


def prepare(dart, native_archive, profile, output):
    if profile not in ("full", "compact"):
        raise ValueError("Expected full or compact")
    if command("git", "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Consumer stage requires clean committed source/configuration")
    output.mkdir(parents=True, exist_ok=False)
    native = output / "native"
    unpack(native_archive, native, ARCHIVE_SHA)
    inventory = {file.name: {"bytes": file.stat().st_size, "sha256": sha(file)}
                 for file in sorted(native.glob("*.so"))}
    inventory_file = output / "archive-library-inventory.json"
    inventory_file.write_text(json.dumps(inventory, sort_keys=True) + "\n")
    package = ROOT / "packages/llamadart_validation"
    consumer = ROOT / "example/chat_app/pubspec.yaml"
    request_file = output / "request.json"
    subprocess.run([str(dart), "--packages=" + str(package / ".dart_tool/package_config.json"),
                    str(package / "bin/android_consumer_profile_plan.dart"), profile,
                    str(consumer), str(inventory_file), str(request_file)], cwd=ROOT, check=True)
    request = json.loads(request_file.read_text())
    source = {}
    for name in command("git", "ls-files", "-z").split("\0"):
        if not name:
            continue
        file = ROOT / name
        if file.is_symlink() or not file.is_file():
            raise ValueError("Source inventory requires regular files")
        source[name] = {"bytes": file.stat().st_size, "sha256": sha(file)}
    encoded = json.dumps(source, sort_keys=True, separators=(",", ":")).encode()
    binding = {"schema": 1, "plan_sha256": request["plan_sha256"],
               "source_commit": command("git", "rev-parse", "HEAD"),
               "source_tree": command("git", "rev-parse", "HEAD^{tree}"),
               "source_dirty": False,
               "source_inventory_sha256": hashlib.sha256(encoded).hexdigest(),
               "consumer_pubspec_sha256": sha(consumer),
               "hook_sha256": sha(ROOT / "hook/build.dart"),
               "selector_sha256": sha(ROOT / "lib/src/hook/native_bundle_config.dart"),
               "native_tag": "v0.9.0", "native_archive_sha256": ARCHIVE_SHA,
               "archive_libraries": inventory,
               "libraries": {name: inventory[name] for name in request["packaging_selection"]["packaged"]},
               "packaging_selection": request["packaging_selection"]}
    if command("git", "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Source changed while staging")
    assets = output / "stage/assets/llamadart_android_qualification"
    assets.mkdir(parents=True)
    # Runtime libraries are emitted only by the production consumer hook.
    (assets / "binding.json").write_text(json.dumps(binding, sort_keys=True) + "\n")
    (assets / "plan.json").write_text(json.dumps(request["plan"], separators=(",", ":")))
    (output / "source-inventory.json").write_bytes(encoded)
    plan = operator_plan(profile, binding["source_commit"], binding["source_tree"], output)
    (output / "operator-plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    return {"stage": str(output / "stage"), "binding": binding, "qualified": False,
            "operator_plan": str(output / "operator-plan.json")}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", type=Path, required=True)
    parser.add_argument("--native-archive", type=Path, required=True)
    parser.add_argument("--profile", choices=("full", "compact"), required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.dry_run:
        draft = operator_plan(args.profile, command("git", "rev-parse", "HEAD"),
                              command("git", "rev-parse", "HEAD^{tree}"), args.out.resolve())
        draft["source_and_configuration_admitted"] = False
        print(json.dumps(draft, indent=2))
        raise SystemExit(0)
    print(json.dumps(prepare(args.dart, args.native_archive, args.profile, args.out.resolve())))
