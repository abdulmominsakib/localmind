#!/usr/bin/env python3
"""Validate a llamadart-native header archive and stage a complete header root."""

from __future__ import annotations

import argparse
import shutil
import sys
import tarfile
from pathlib import Path, PurePosixPath
from typing import NamedTuple


class ArchiveError(RuntimeError):
    pass


class HeaderLayout(NamedTuple):
    llama_include: Path
    ggml_include: Path
    mtmd_dir: Path
    wrapper_header: Path


MTMD_HEADERS = ("mtmd.h", "mtmd-helper.h")


def required_sources(layout: HeaderLayout) -> dict[str, Path]:
    """Map each required staged header path to its archive source."""
    return {
        "llama_cpp/include/llama.h": layout.llama_include / "llama.h",
        "llama_cpp/ggml/include/ggml.h": layout.ggml_include / "ggml.h",
        "llama_cpp/ggml/include/ggml-backend.h": (
            layout.ggml_include / "ggml-backend.h"
        ),
        **{
            f"llama_cpp/tools/mtmd/{name}": layout.mtmd_dir / name
            for name in MTMD_HEADERS
        },
        "libllamadart/llama_dart_wrapper.h": layout.wrapper_header,
    }


def member_relative_path(name: str) -> PurePosixPath:
    if name.startswith("/"):
        raise ArchiveError(f"archive entry {name!r} uses an absolute path")
    parts = [part for part in PurePosixPath(name).parts if part != "."]
    if any(part == ".." for part in parts):
        raise ArchiveError(f"archive entry {name!r} escapes the archive root")
    if not parts:
        raise ArchiveError(f"archive entry {name!r} has an empty path")
    return PurePosixPath(*parts)


def validate_member(member: tarfile.TarInfo) -> PurePosixPath:
    if member.issym() or member.islnk():
        raise ArchiveError(f"archive entry {member.name!r} is a link entry")
    if not (member.isfile() or member.isdir()):
        raise ArchiveError(
            f"archive entry {member.name!r} is neither a regular file nor a "
            "directory"
        )
    if getattr(member, "sparse", None) is not None:
        raise ArchiveError(f"archive entry {member.name!r} is sparse")
    return member_relative_path(member.name)


def validate_members(
    members: list[tarfile.TarInfo],
) -> list[tuple[tarfile.TarInfo, PurePosixPath]]:
    validated: list[tuple[tarfile.TarInfo, PurePosixPath]] = []
    by_path: dict[PurePosixPath, tarfile.TarInfo] = {}
    for member in members:
        relative = validate_member(member)
        if relative in by_path:
            raise ArchiveError(f"archive entry {member.name!r} is duplicated")
        by_path[relative] = member
        validated.append((member, relative))
    for member, relative in validated:
        for parent in relative.parents:
            parent_member = by_path.get(parent)
            if parent_member is not None and not parent_member.isdir():
                raise ArchiveError(
                    f"archive entry {member.name!r} is nested below a file"
                )
    return validated


def extract_archive(archive_path: Path, destination: Path) -> None:
    """Extract validated regular files and directories only.

    Every member is checked before any byte is written so a hostile or
    malformed archive cannot place files outside ``destination``.
    """
    if destination.is_symlink() or (
        destination.exists()
        and (not destination.is_dir() or any(destination.iterdir()))
    ):
        raise ArchiveError(
            f"Extraction path is not an empty directory: {destination}"
        )
    destination.mkdir(parents=True, exist_ok=True)
    resolved_destination = destination.resolve()
    try:
        with tarfile.open(archive_path, "r:gz") as archive:
            validated = validate_members(archive.getmembers())
            for member, relative in validated:
                target = destination / relative
                if not target.resolve().is_relative_to(resolved_destination):
                    raise ArchiveError(
                        f"archive entry {member.name!r} escapes the archive root"
                    )
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise ArchiveError(
                        f"archive entry {member.name!r} has no readable content"
                    )
                with source, open(target, "xb") as output:
                    shutil.copyfileobj(source, output)
    except ArchiveError:
        raise
    except (tarfile.TarError, OSError, EOFError) as error:
        raise ArchiveError(
            f"Header archive {archive_path.name} could not be extracted: {error}"
        ) from error


def resolve_layout(extract_root: Path) -> HeaderLayout:
    if (extract_root / "llama_cpp" / "include").is_dir():
        return HeaderLayout(
            extract_root / "llama_cpp" / "include",
            extract_root / "llama_cpp" / "ggml" / "include",
            extract_root / "llama_cpp" / "tools" / "mtmd",
            extract_root / "libllamadart" / "llama_dart_wrapper.h",
        )
    # Retained for historical llamadart-native header bundles.
    if (extract_root / "include" / "llama.cpp").is_dir():
        return HeaderLayout(
            extract_root / "include" / "llama.cpp",
            extract_root / "include" / "ggml",
            extract_root / "include" / "llama.cpp",
            extract_root / "include" / "llama_dart_wrapper.h",
        )
    raise ArchiveError("Unsupported header archive layout")


def stage_header_root(extract_root: Path, staging_root: Path) -> None:
    layout = resolve_layout(extract_root)
    sources = required_sources(layout)
    missing = sorted(name for name, path in sources.items() if not path.is_file())
    if missing:
        raise ArchiveError(
            "Header archive is missing required header(s): " + ", ".join(missing)
        )
    if staging_root.exists() or staging_root.is_symlink():
        raise ArchiveError(f"Staging path already exists: {staging_root.name}")
    try:
        shutil.copytree(
            layout.llama_include,
            staging_root / "llama_cpp" / "include",
            symlinks=False,
        )
        shutil.copytree(
            layout.ggml_include,
            staging_root / "llama_cpp" / "ggml" / "include",
            symlinks=False,
        )
        mtmd_root = staging_root / "llama_cpp" / "tools" / "mtmd"
        mtmd_root.mkdir(parents=True, exist_ok=True)
        for name in MTMD_HEADERS:
            shutil.copyfile(layout.mtmd_dir / name, mtmd_root / name)
        wrapper = staging_root / "libllamadart" / "llama_dart_wrapper.h"
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(layout.wrapper_header, wrapper)
    except (OSError, shutil.Error) as error:
        shutil.rmtree(staging_root, ignore_errors=True)
        raise ArchiveError(f"Failed to stage header root: {error}") from error


def prepare_header_root(
    archive_path: Path, extract_root: Path, staging_root: Path
) -> None:
    extract_archive(archive_path, extract_root)
    stage_header_root(extract_root, staging_root)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate a llamadart-native header archive and stage a complete "
            "header root without touching the live header root."
        )
    )
    parser.add_argument("--archive", required=True)
    parser.add_argument("--extract-dir", required=True)
    parser.add_argument("--staging", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    prepare_header_root(
        Path(args.archive), Path(args.extract_dir), Path(args.staging)
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ArchiveError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
    except (OSError, shutil.Error, tarfile.TarError):
        print("error: Could not prepare the staged header root", file=sys.stderr)
        raise SystemExit(1)
