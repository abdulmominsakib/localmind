from __future__ import annotations

import io
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))

from native_header_archive import (  # noqa: E402
    ArchiveError,
    extract_archive,
    member_relative_path,
    prepare_header_root,
    stage_header_root,
)


MODULE_PATH = Path(__file__).resolve().parent / "native_header_archive.py"
REQUIRED_HEADERS = (
    "llama_cpp/include/llama.h",
    "llama_cpp/ggml/include/ggml.h",
    "llama_cpp/ggml/include/ggml-backend.h",
    "llama_cpp/tools/mtmd/mtmd.h",
    "llama_cpp/tools/mtmd/mtmd-helper.h",
    "libllamadart/llama_dart_wrapper.h",
)
CURRENT_LAYOUT_FILES = {
    "llama_cpp/include/llama.h": "// llama\n",
    "llama_cpp/include/llama-cpp.h": "// llama-cpp\n",
    "llama_cpp/ggml/include/ggml.h": "// ggml\n",
    "llama_cpp/ggml/include/ggml-backend.h": "// ggml-backend\n",
    "llama_cpp/tools/mtmd/mtmd.h": "// mtmd\n",
    "llama_cpp/tools/mtmd/mtmd-helper.h": "// mtmd-helper\n",
    "libllamadart/llama_dart_wrapper.h": "// wrapper\n",
}
LEGACY_LAYOUT_FILES = {
    "include/llama.cpp/llama.h": "// llama\n",
    "include/llama.cpp/mtmd.h": "// mtmd\n",
    "include/llama.cpp/mtmd-helper.h": "// mtmd-helper\n",
    "include/ggml/ggml.h": "// ggml\n",
    "include/ggml/ggml-backend.h": "// ggml-backend\n",
    "include/llama_dart_wrapper.h": "// wrapper\n",
}


def _write_archive(path: Path, files: dict[str, str]) -> Path:
    with tarfile.open(path, "w:gz") as archive:
        for name, content in files.items():
            payload = content.encode("utf-8")
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            archive.addfile(info, io.BytesIO(payload))
    return path


def _archive_with_extra_member(path: Path, info: tarfile.TarInfo) -> Path:
    with tarfile.open(path, "w:gz") as archive:
        for name, content in CURRENT_LAYOUT_FILES.items():
            payload = content.encode("utf-8")
            member = tarfile.TarInfo(name)
            member.size = len(payload)
            archive.addfile(member, io.BytesIO(payload))
        archive.addfile(info)
    return path


class MemberPathTest(unittest.TestCase):
    def test_rejects_absolute_and_traversing_member_paths(self) -> None:
        for name in (
            "/etc/passwd",
            "//etc/passwd",
            "../outside.h",
            "llama_cpp/../../outside.h",
            ".",
        ):
            with self.subTest(name=name):
                with self.assertRaises(ArchiveError):
                    member_relative_path(name)

    def test_accepts_normal_member_paths(self) -> None:
        self.assertEqual(
            str(member_relative_path("./llama_cpp/include/llama.h")),
            "llama_cpp/include/llama.h",
        )


class ExtractArchiveTest(unittest.TestCase):
    def test_rejects_link_device_and_traversing_members(self) -> None:
        symlink = tarfile.TarInfo("llama_cpp/include/evil.h")
        symlink.type = tarfile.SYMTYPE
        symlink.linkname = "/etc/passwd"
        hardlink = tarfile.TarInfo("llama_cpp/include/evil-hard.h")
        hardlink.type = tarfile.LNKTYPE
        hardlink.linkname = "llama_cpp/include/llama.h"
        device = tarfile.TarInfo("llama_cpp/include/evil-dev")
        device.type = tarfile.CHRTYPE
        fifo = tarfile.TarInfo("llama_cpp/include/evil-fifo")
        fifo.type = tarfile.FIFOTYPE
        sparse = tarfile.TarInfo("llama_cpp/include/evil-sparse.h")
        sparse.type = tarfile.GNUTYPE_SPARSE
        traversal = tarfile.TarInfo("../escaped.h")
        traversal.size = 0

        expectations = {
            "symlink": (symlink, "link entry"),
            "hardlink": (hardlink, "link entry"),
            "device": (device, "neither a regular file nor a directory"),
            "fifo": (fifo, "neither a regular file nor a directory"),
            "sparse": (sparse, "sparse"),
            "traversal": (traversal, "escapes the archive root"),
        }
        for label, (info, message) in expectations.items():
            with self.subTest(entry=label), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                archive = _archive_with_extra_member(root / "headers.tar.gz", info)
                destination = root / "extract"
                with self.assertRaisesRegex(ArchiveError, message):
                    extract_archive(archive, destination)
                self.assertFalse((root / "escaped.h").exists())
                self.assertFalse(
                    (destination / "llama_cpp" / "include" / "evil.h").exists()
                )

    def test_rejects_duplicate_normalized_paths_before_extraction(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive_path = root / "headers.tar.gz"
            with tarfile.open(archive_path, "w:gz") as archive:
                for name in ("headers/value.h", "./headers//value.h"):
                    payload = name.encode("utf-8")
                    member = tarfile.TarInfo(name)
                    member.size = len(payload)
                    archive.addfile(member, io.BytesIO(payload))
            destination = root / "extract"
            with self.assertRaisesRegex(ArchiveError, "duplicated"):
                extract_archive(archive_path, destination)
            self.assertEqual(list(destination.iterdir()), [])

    def test_rejects_nonempty_or_symlink_extraction_roots(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = _write_archive(root / "headers.tar.gz", CURRENT_LAYOUT_FILES)
            nonempty = root / "nonempty"
            nonempty.mkdir()
            (nonempty / "marker").write_text("keep", encoding="utf-8")
            with self.assertRaisesRegex(ArchiveError, "not an empty directory"):
                extract_archive(archive, nonempty)
            target = root / "target"
            target.mkdir()
            symlink = root / "symlink"
            symlink.symlink_to(target, target_is_directory=True)
            with self.assertRaisesRegex(ArchiveError, "not an empty directory"):
                extract_archive(archive, symlink)

    def test_rejects_corrupt_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "headers.tar.gz"
            archive.write_bytes(b"not a gzip archive")
            with self.assertRaisesRegex(ArchiveError, "could not be extracted"):
                extract_archive(archive, root / "extract")

    def test_rejects_truncated_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = _write_archive(root / "headers.tar.gz", CURRENT_LAYOUT_FILES)
            payload = archive.read_bytes()
            archive.write_bytes(payload[: len(payload) // 2])
            with self.assertRaisesRegex(ArchiveError, "could not be extracted"):
                extract_archive(archive, root / "extract")


class StageHeaderRootTest(unittest.TestCase):
    def _stage(self, files: dict[str, str], temp: str) -> Path:
        root = Path(temp)
        archive = _write_archive(root / "headers.tar.gz", files)
        staging = root / "ffigen_headers.staging"
        prepare_header_root(archive, root / "extract", staging)
        return staging

    def test_stages_every_required_header_for_the_current_layout(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            staging = self._stage(CURRENT_LAYOUT_FILES, temp)
            for header in REQUIRED_HEADERS:
                self.assertTrue((staging / header).is_file(), header)
            self.assertTrue(
                (staging / "llama_cpp/include/llama-cpp.h").is_file(),
                "sibling headers are copied with the include tree",
            )

    def test_stages_every_required_header_for_the_legacy_layout(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            staging = self._stage(LEGACY_LAYOUT_FILES, temp)
            for header in REQUIRED_HEADERS:
                self.assertTrue((staging / header).is_file(), header)

    def test_rejects_unsupported_layout(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(ArchiveError, "Unsupported header archive"):
                self._stage({"headers/llama.h": "// llama\n"}, temp)

    def test_rejects_missing_required_headers_without_creating_staging(self) -> None:
        for missing in (
            "llama_cpp/tools/mtmd/mtmd-helper.h",
            "libllamadart/llama_dart_wrapper.h",
            "llama_cpp/ggml/include/ggml-backend.h",
        ):
            files = dict(CURRENT_LAYOUT_FILES)
            files.pop(missing)
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as temp:
                with self.assertRaisesRegex(ArchiveError, f"missing.*{missing}"):
                    self._stage(files, temp)
                self.assertFalse((Path(temp) / "ffigen_headers.staging").exists())

    def test_reports_copy_failure_and_removes_partial_staging(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = _write_archive(root / "headers.tar.gz", CURRENT_LAYOUT_FILES)
            extract_root = root / "extract"
            extract_archive(archive, extract_root)
            staging = root / "ffigen_headers.staging"
            with patch(
                "native_header_archive.shutil.copytree",
                side_effect=OSError("injected copy failure"),
            ):
                with self.assertRaisesRegex(
                    ArchiveError, "Failed to stage header root"
                ):
                    stage_header_root(extract_root, staging)
            self.assertFalse(staging.exists())


class CommandLineTest(unittest.TestCase):
    def _run(self, archive: Path, extract: Path, staging: Path):
        return subprocess.run(
            [
                sys.executable,
                str(MODULE_PATH),
                "--archive",
                str(archive),
                "--extract-dir",
                str(extract),
                "--staging",
                str(staging),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_reports_concise_error_without_traceback(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "headers.tar.gz"
            archive.write_bytes(b"not a gzip archive")
            result = self._run(archive, root / "extract", root / "staging")
            self.assertEqual(result.returncode, 1)
            self.assertIn("error: Header archive", result.stderr)
            self.assertNotIn("Traceback", result.stderr)

    def test_stages_a_valid_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = _write_archive(root / "headers.tar.gz", CURRENT_LAYOUT_FILES)
            staging = root / "staging"
            result = self._run(archive, root / "extract", staging)
            self.assertEqual(result.returncode, 0, result.stderr)
            for header in REQUIRED_HEADERS:
                self.assertTrue((staging / header).is_file(), header)


if __name__ == "__main__":
    unittest.main()
