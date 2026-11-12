#!/usr/bin/env python3
"""Stream-verify the exact model and dispatch kit embedded in a validation APK."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path


def verify(apk, profile, kit):
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate APK entries")
        embedded_profile = json.loads(archive.read("assets/llamadart_npu/profile.json"))
        # Path selection is a Dart build define; model/target inputs are shared.
        if any(embedded_profile[k] != profile[k] for k in ("id", "model", "npu_target")):
            raise ValueError("Embedded NPU profile differs")
        if json.loads(archive.read("assets/llamadart_npu/npu-kit.json")) != kit:
            raise ValueError("Embedded kit manifest differs")
        if set(kit["libraries"]) != set(profile["npu_target"]["libraries"]):
            raise ValueError("Kit inventory differs from profile")
        npu_names = {name.removeprefix("lib/arm64-v8a/") for name in names
                     if name.startswith(("lib/arm64-v8a/libLiteRtDispatch_",
                                         "lib/arm64-v8a/libLlamadartVendor_",
                                         "lib/arm64-v8a/libQnn"))}
        if npu_names != set(kit["libraries"]):
            raise ValueError("Unexpected NPU libraries in APK")
        entries = {"assets/llamadart_npu/model.litertlm": profile["model"]}
        for name, record in kit["libraries"].items():
            if Path(name).name != name:
                raise ValueError("Unsafe library name")
            lock = profile["npu_target"]["libraries"][name]
            if "sha256" in lock and record["sha256"] != lock["sha256"]:
                raise ValueError("Audited library differs")
            entries["lib/arm64-v8a/" + name] = record
        for name, record in entries.items():
            if archive.getinfo(name).file_size != record["bytes"]:
                raise ValueError("APK entry size differs")
            with archive.open(name) as stream:
                digest = hashlib.sha256()
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
                if digest.hexdigest() != record["sha256"]:
                    raise ValueError("APK entry hash differs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("apk", "profile", "kit"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    verify(args.apk, json.loads(args.profile.read_text()), json.loads(args.kit.read_text()))
    print("NPU APK model and library hashes verified")
