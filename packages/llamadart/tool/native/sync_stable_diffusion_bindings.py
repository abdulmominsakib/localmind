#!/usr/bin/env python3
"""Stage the pinned stable-diffusion-native headers and regenerate their Dart
FFI bindings.

stable-diffusion-native ships its headers inside every runtime archive, so
they come from the archive pinned in lib/src/hook/native_release_pins.dart,
after its SHA-256 matches that pin.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
from native_header_archive import ArchiveError, validate_members  # noqa: E402

DEFAULT_PINS = "lib/src/hook/native_release_pins.dart"
DEFAULT_HEADER_ROOT = ".dart_tool/llamadart/ffigen_headers_stable_diffusion"
DEFAULT_FFIGEN_CONFIG = "ffigen_stable_diffusion.yaml"
DEFAULT_BUNDLE = "linux-x64"
RELEASE_BASE_URL = "https://github.com/leehack/stable-diffusion-native/releases/download"
HEADER_MEMBERS = (
    PurePosixPath("include/stable-diffusion.h"),
    PurePosixPath("include/sd_dart_wrapper.h"),
)
DOWNLOAD_TIMEOUT_SECONDS = 300


class SyncError(RuntimeError):
    pass


def pinned_release(pins_text: str, bundle: str) -> tuple[str, str]:
    """Return the pinned (tag, sha256) of the stable_diffusion [bundle]."""
    tag = re.search(r"const stableDiffusionReleaseTag = '([^']+)';", pins_text)
    if tag is None:
        raise SyncError(f"{DEFAULT_PINS} has no stableDiffusionReleaseTag")
    if re.fullmatch(r"v\d+\.\d+\.\d+(?:-[1-9]\d*)?", tag.group(1)) is None:
        raise SyncError(f"Unsupported stable_diffusion tag {tag.group(1)!r}")
    spec = re.search(
        rf"StableDiffusionBundleSpec\(\s*'{re.escape(bundle)}',\s*"
        r"sha256: '([0-9a-f]{64})'",
        pins_text,
    )
    if spec is None:
        raise SyncError(f"{DEFAULT_PINS} pins no stable_diffusion bundle {bundle}")
    return tag.group(1), spec.group(1)


def archive_name(bundle: str, tag: str) -> str:
    return f"stable-diffusion-native-runtime-{bundle}-{tag}.tar.gz"


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(
        url, headers={"User-Agent": "llamadart-stable-diffusion-sync"}
    )
    try:
        with urllib.request.urlopen(
            request, timeout=DOWNLOAD_TIMEOUT_SECONDS
        ) as response, open(destination, "wb") as output:
            shutil.copyfileobj(response, output)
    except OSError as error:
        raise SyncError(f"Failed to download {url}: {error}") from error


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_headers(archive_path: Path) -> dict[PurePosixPath, bytes]:
    """Return every HEADER_MEMBERS file from a validated runtime archive."""
    try:
        with tarfile.open(archive_path, "r:gz") as archive:
            members = validate_members(archive.getmembers())
            headers = {}
            for header in HEADER_MEMBERS:
                matches = [
                    member
                    for member, relative in members
                    if relative == header and member.isfile()
                ]
                if len(matches) != 1:
                    raise SyncError(f"{archive_path.name} has no {header}")
                source = archive.extractfile(matches[0])
                if source is None:
                    raise SyncError(f"{archive_path.name} {header} is unreadable")
                with source:
                    headers[header] = source.read()
            return headers
    except (tarfile.TarError, OSError, EOFError) as error:
        raise SyncError(f"{archive_path.name} could not be read: {error}") from error


def publish_headers(headers: dict[PurePosixPath, bytes], header_root: Path) -> None:
    """Replace [header_root] with one holding [headers]."""
    header_root.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{header_root.name}.", dir=header_root.parent)
    )
    try:
        for member, content in headers.items():
            target = staging / member
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        if header_root.exists() or header_root.is_symlink():
            if header_root.is_symlink() or not header_root.is_dir():
                raise SyncError(f"Refusing to replace non-directory {header_root}")
            shutil.rmtree(header_root)
        os.replace(staging, header_root)
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    tag, expected_sha256 = pinned_release(
        (repo_root / DEFAULT_PINS).read_text(encoding="utf-8"), args.bundle
    )
    name = archive_name(args.bundle, tag)
    with tempfile.TemporaryDirectory() as temp:
        archive = Path(args.archive) if args.archive else Path(temp) / name
        if not args.archive:
            download(f"{RELEASE_BASE_URL}/{tag}/{name}", archive)
        actual_sha256 = sha256_file(archive)
        if actual_sha256 != expected_sha256:
            raise SyncError(
                f"{name} SHA-256 {actual_sha256} does not match the pinned "
                f"{expected_sha256}"
            )
        headers = read_headers(archive)
    header_root = repo_root / args.header_root
    publish_headers(headers, header_root)
    staged = ", ".join(str(member) for member in HEADER_MEMBERS)
    print(f"Staged {staged} from {name} in {header_root}")

    if not args.skip_ffigen:
        result = subprocess.run(
            ["dart", "run", "ffigen", "--config", DEFAULT_FFIGEN_CONFIG],
            cwd=repo_root,
            check=False,
        )
        if result.returncode != 0:
            raise SyncError("ffigen failed for the stable_diffusion bindings")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".")
    parser.add_argument(
        "--bundle",
        default=DEFAULT_BUNDLE,
        help="Pinned runtime archive to take the headers from.",
    )
    parser.add_argument(
        "--archive",
        default="",
        help="Use this local archive instead of downloading; it must match the pin.",
    )
    parser.add_argument("--header-root", default=DEFAULT_HEADER_ROOT)
    parser.add_argument("--skip-ffigen", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (SyncError, ArchiveError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
