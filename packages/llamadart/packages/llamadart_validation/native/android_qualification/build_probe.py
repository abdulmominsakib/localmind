"""Prepare a clean-source, hash-bound diagnostic stage. Never dispatches tests."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[4]
ARCHIVE_SHA = "d3c933a63e8ccaafeee32edd30685fdccd17c05e54b75895282f01fe74914a1b"
HEADERS_SHA = "b88b62fd6c5ff8ac371b281e394dc0e231da58c850707579367d1655d12d5462"

def sha(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while data := stream.read(1024 * 1024):
            value.update(data)
    return value.hexdigest()

def command(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()

def unpack(archive, destination, expected):
    if sha(archive) != expected:
        raise ValueError("Archive checksum mismatch")
    destination.mkdir()
    with tarfile.open(archive) as source:
        members = source.getmembers()
        if sum(item.size for item in members) > 512 * 1024 * 1024:
            raise ValueError("Archive exceeds diagnostic extraction bound")
        for item in members:
            target = destination / item.name
            if (not target.resolve().is_relative_to(destination.resolve()) or
                    not (item.isfile() or item.isdir())):
                raise ValueError("Unsafe diagnostic archive entry")
        source.extractall(destination, filter="data")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--dart", type=Path, required=True)
    parser.add_argument("--native-archive", type=Path, required=True)
    parser.add_argument("--headers-archive", type=Path, required=True)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    # git status includes untracked source: a dirty fixture cannot seal itself.
    if command("git", "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Diagnostic stage requires clean committed source")
    plan_bytes = args.plan.read_bytes()
    plan = json.loads(plan_bytes)
    if plan.get("schema") != 1 or plan.get("scenario") not in ("a35", "pixel8a"):
        raise ValueError("Select a maintained Android diagnostic plan")
    # Dart writes canonical compact JSON, without a newline, for this hash.
    plan_hash = hashlib.sha256(plan_bytes).hexdigest()
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=False)
    native, headers = output / "native", output / "headers"
    unpack(args.native_archive, native, ARCHIVE_SHA)
    unpack(args.headers_archive, headers, HEADERS_SHA)
    stage = output / "stage"
    jni = stage / "jniLibs/arm64-v8a"
    assets = stage / "assets/llamadart_android_qualification"
    jni.mkdir(parents=True)
    assets.mkdir(parents=True)
    compiler = args.ndk / "toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android29-clang++"
    if not compiler.is_file():
        compiler = args.ndk / "toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang++"
    probe = jni / "libllamadart_android_qualification.so"
    subprocess.run([str(compiler), "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                    "-fPIE", "-pie", "-static-libstdc++", "-Wl,-z,max-page-size=16384",
                    "-Wl,-rpath,$ORIGIN", "-I" + str(headers / "llama_cpp/include"),
                    "-I" + str(headers / "llama_cpp/ggml/include"),
                    str(Path(__file__).with_name("main.cpp")), "-L" + str(native),
                    "-lllama", "-lggml", "-lggml-base", "-ldl", "-o", str(probe)], check=True)
    archive_libraries = {file.name: {"bytes": file.stat().st_size, "sha256": sha(file)}
                         for file in sorted(native.glob("*.so"))}
    archive_inventory = output / "archive-library-inventory.json"
    archive_inventory.write_text(json.dumps(archive_libraries, sort_keys=True) + "\n")
    selection_path = output / "packaging-selection.json"
    package = ROOT / "packages/llamadart_validation"
    subprocess.run([str(args.dart), "--packages=" + str(package / ".dart_tool/package_config.json"),
                    str(package / "bin/android_qualification_libraries.dart"),
                    str(archive_inventory), str(selection_path)], cwd=ROOT, check=True)
    selection = json.loads(selection_path.read_text())
    libraries = {name: archive_libraries[name] for name in selection["packaged"]}
    libraries[probe.name] = {"bytes": probe.stat().st_size, "sha256": sha(probe)}
    inventory = {}
    for name in command("git", "ls-files", "-z").split("\0"):
        if name:
            file = ROOT / name
            if file.is_symlink() or not file.is_file():
                raise ValueError("Source inventory requires regular files")
            inventory[name] = {"bytes": file.stat().st_size, "sha256": sha(file)}
    encoded_inventory = json.dumps(inventory, sort_keys=True, separators=(",", ":")).encode()
    binding = {"schema": 1, "plan_sha256": plan_hash,
               "source_commit": command("git", "rev-parse", "HEAD"),
               "source_tree": command("git", "rev-parse", "HEAD^{tree}"),
               "source_dirty": False,
               "source_inventory_sha256": hashlib.sha256(encoded_inventory).hexdigest(),
               "hook_sha256": sha(ROOT / "hook/build.dart"),
               "native_tag": "v0.9.0", "native_archive_sha256": ARCHIVE_SHA,
               "headers_archive_sha256": HEADERS_SHA,
               "probe_sha256": sha(probe), "libraries": libraries,
               "archive_libraries": archive_libraries,
               "packaging_selection": selection,
               "selector_sha256": sha(ROOT / "lib/src/hook/native_bundle_config.dart")}
    if command("git", "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Source changed while staging")
    (assets / "binding.json").write_text(json.dumps(binding, sort_keys=True) + "\n")
    (assets / "plan.json").write_bytes(plan_bytes)
    (output / "source-inventory.json").write_bytes(encoded_inventory)
    print(json.dumps({"stage": str(stage), "binding": binding,
                      "qualified": False, "android_launch_observed": False}))

if __name__ == "__main__":
    main()
