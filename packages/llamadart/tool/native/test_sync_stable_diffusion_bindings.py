from __future__ import annotations

import hashlib
import io
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync_stable_diffusion_bindings as sync  # noqa: E402

SCRIPT = Path(__file__).resolve().parent / "sync_stable_diffusion_bindings.py"
REPO_ROOT = Path(__file__).resolve().parents[2]
HEADER = b"// stable-diffusion.h\nint sd_version(void);\n"
WRAPPER_HEADER = b'#include "stable-diffusion.h"\nvoid sd_dart_progress_enable(void);\n'


def write_archive(path: Path, members: dict[str, bytes | str]) -> None:
    """Write a .tar.gz; a str value makes that member a symlink to it."""
    with tarfile.open(path, "w:gz") as archive:
        for name, content in members.items():
            info = tarfile.TarInfo(name)
            if isinstance(content, str):
                info.type = tarfile.SYMTYPE
                info.linkname = content
                archive.addfile(info)
            else:
                info.size = len(content)
                archive.addfile(info, io.BytesIO(content))


def pins_for(sha256: str, tag: str = "v0.1.0") -> str:
    return (
        f"const stableDiffusionReleaseTag = '{tag}';\n"
        "const stableDiffusionBundleSpecs = <StableDiffusionBundleSpec>[\n"
        "  StableDiffusionBundleSpec(\n"
        "    'linux-x64',\n"
        f"    sha256: '{sha256}',\n"
        "    requiredLibraries: {'libstable-diffusion.so'},\n"
        "  ),\n"
        "];\n"
    )


class PinnedReleaseTest(unittest.TestCase):
    def test_reads_the_checked_in_pins(self) -> None:
        pins = (REPO_ROOT / sync.DEFAULT_PINS).read_text(encoding="utf-8")
        tag, sha256 = sync.pinned_release(pins, "linux-x64")
        self.assertRegex(tag, r"^v\d+\.\d+\.\d+")
        self.assertRegex(sha256, r"^[0-9a-f]{64}$")
        self.assertIn(f"sha256: '{sha256}'", pins)

    def test_rejects_unpinned_bundles_and_bad_tags(self) -> None:
        with self.assertRaisesRegex(sync.SyncError, "android-x64"):
            sync.pinned_release(pins_for("0" * 64), "android-x64")
        with self.assertRaisesRegex(sync.SyncError, "Unsupported"):
            sync.pinned_release(pins_for("0" * 64, tag="latest"), "linux-x64")
        with self.assertRaisesRegex(sync.SyncError, "stableDiffusionReleaseTag"):
            sync.pinned_release("", "linux-x64")


class SyncScriptTest(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.archive = self.root / "runtime.tar.gz"
        self.header_root = self.root / "headers"
        (self.header_root / "include").mkdir(parents=True)
        (self.header_root / "include" / "stable-diffusion.h").write_bytes(b"old")

    def run_sync(self, members: dict[str, bytes | str], *, pin: str | None = None):
        write_archive(self.archive, members)
        sha256 = pin or hashlib.sha256(self.archive.read_bytes()).hexdigest()
        pins = self.root / sync.DEFAULT_PINS
        pins.parent.mkdir(parents=True, exist_ok=True)
        pins.write_text(pins_for(sha256), encoding="utf-8")
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--repo-root",
                str(self.root),
                "--archive",
                str(self.archive),
                "--header-root",
                str(self.header_root),
                "--skip-ffigen",
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def staged_header(self, name: str = "stable-diffusion.h") -> bytes:
        return (self.header_root / "include" / name).read_bytes()

    def test_stages_both_headers_from_a_pinned_archive(self) -> None:
        result = self.run_sync(
            {
                "./include/stable-diffusion.h": HEADER,
                "./include/sd_dart_wrapper.h": WRAPPER_HEADER,
                "lib/libstable-diffusion.so": b"\x7fELF",
                "LICENSE": b"MIT",
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.staged_header(), HEADER)
        self.assertEqual(self.staged_header("sd_dart_wrapper.h"), WRAPPER_HEADER)
        self.assertEqual(
            sorted(p.name for p in self.header_root.rglob("*") if p.is_file()),
            ["sd_dart_wrapper.h", "stable-diffusion.h"],
        )
        self.assertEqual(
            [p.name for p in self.root.iterdir() if p.name.startswith(".headers")],
            [],
        )

    def test_checksum_mismatch_leaves_the_header_root_unchanged(self) -> None:
        result = self.run_sync(
            {
                "include/stable-diffusion.h": HEADER,
                "include/sd_dart_wrapper.h": WRAPPER_HEADER,
            },
            pin="0" * 64,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("does not match the pinned", result.stderr)
        self.assertEqual(self.staged_header(), b"old")

    def test_rejects_link_entries_and_missing_headers(self) -> None:
        for members, message in (
            ({"include/stable-diffusion.h": "../../etc/passwd"}, "link entry"),
            ({"../include/stable-diffusion.h": HEADER}, "escapes"),
            ({"lib/libstable-diffusion.so": b"\x7fELF"}, "has no"),
            (
                {"include/stable-diffusion.h": HEADER},
                "has no include/sd_dart_wrapper.h",
            ),
        ):
            with self.subTest(message=message):
                result = self.run_sync(members)
                self.assertEqual(result.returncode, 1)
                self.assertIn(message, result.stderr)
                self.assertEqual(self.staged_header(), b"old")


if __name__ == "__main__":
    unittest.main()
