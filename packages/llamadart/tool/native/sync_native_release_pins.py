#!/usr/bin/env python3
"""Sync native runtime pins from published GitHub release assets."""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
import re
import shutil
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.request
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any, NamedTuple


DEFAULT_LLAMADART_NATIVE_REPO = "leehack/llamadart-native"
DEFAULT_LITERT_LM_NATIVE_REPO = "leehack/litert-lm-native"
DEFAULT_STABLE_DIFFUSION_NATIVE_REPO = "leehack/stable-diffusion-native"
DEFAULT_NATIVE_RELEASE_PINS = "lib/src/hook/native_release_pins.dart"
DEFAULT_BUILD_HOOK = "hook/build.dart"
DEFAULT_LLAMA_CPP_PACKAGE_SWIFT = (
    "packages/llamadart_llama_cpp_flutter/darwin/"
    "llamadart_llama_cpp_flutter/Package.swift"
)
DEFAULT_LITERT_LM_PACKAGE_SWIFT = (
    "packages/llamadart_litert_lm_flutter/darwin/"
    "llamadart_litert_lm_flutter/Package.swift"
)
DEFAULT_STABLE_DIFFUSION_PACKAGE_SWIFT = (
    "packages/llamadart_stable_diffusion_flutter/darwin/"
    "llamadart_stable_diffusion_flutter/Package.swift"
)
DEFAULT_LITERT_LM_RUNTIME_DART = (
    "lib/src/backends/litert_lm/litert_lm_runtime.dart"
)
DEFAULT_LITERT_LM_MACOS_PREPARE_SCRIPT = "tool/macos_litert_lm_prepare_app.sh"
DEFAULT_LLAMA_CPP_PROJECT_DOCS = (
    "README.md",
    "website/docs/getting-started/installation.md",
    "website/docs/platforms/support-matrix.md",
)
DEFAULT_CHANGELOG = "CHANGELOG.md"
SUPPORTED_NATIVE_HOOK_CONTRACT_VERSIONS = (1, 2)
# Contract 2 adds backend sidecar archives (`module: backend-*`), extracted
# over a core bundle only when that backend is selected.
_BACKEND_SIDECAR_ARCHIVE_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
_STABLE_NATIVE_TAG_PATTERN = re.compile(
    r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"
)
_STABLE_WRAPPER_TAG_PATTERN = re.compile(
    r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\."
    r"(0|[1-9][0-9]*)-([1-9][0-9]*)$"
)
_LEGACY_NATIVE_TAG_PATTERN = re.compile(r"^b(0|[1-9][0-9]*)$")
_NIGHTLY_WRAPPER_TAG_PATTERN = re.compile(
    r"^b(0|[1-9][0-9]*)-([1-9][0-9]*)$"
)
_LEGACY_WRAPPER_TAG_PATTERN = re.compile(
    r"^b(0|[1-9][0-9]*)-llamadart\.([1-9][0-9]*)$"
)
_NATIVE_DOC_TAG_PATTERN = (
    r"(?:v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)(?:-[1-9][0-9]*)?|"
    r"b(?:0|[1-9][0-9]*)(?:-[1-9][0-9]*|-llamadart\.[1-9][0-9]*)?)"
)
_COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
_STABLE_NATIVE_BUNDLES = (
    "android-arm64",
    "android-x64",
    "ios-arm64",
    "ios-arm64-sim",
    "ios-x86_64-sim",
    "linux-arm64",
    "linux-x64",
    "macos-arm64",
    "macos-x86_64",
    "windows-arm64",
    "windows-x64",
)
STABLE_LITERT_TAG_RE = re.compile(r"^v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$")
STABLE_LITERT_REBUILD_RE = re.compile(
    r"^v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)-[1-9][0-9]*$"
)
DEVELOPMENT_LITERT_TAG_RE = re.compile(r"^g[0-9a-f]{12}(?:-[1-9][0-9]*)?$")
LEGACY_LITERT_TAG_RE = re.compile(
    r"^v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)-native\.[1-9][0-9]*$"
)
FULL_COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SAFE_LITERT_LIBRARY_FILENAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.+-]*$")
STABLE_DIFFUSION_TAG_RE = re.compile(
    r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([1-9][0-9]*))?$"
)
STABLE_DIFFUSION_TARGET_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
DART_FORMAT_PAGE_WIDTH = 80
LEGACY_ALLOWLIST_PATH = (
    Path(__file__).resolve().parent / "fixtures" / "legacy_release_allowlist.json"
)
LEGACY_SCHEMA1_RELEASES: dict[str, dict[str, Any]] = json.loads(
    LEGACY_ALLOWLIST_PATH.read_text(encoding="utf-8")
)["releases"]
REQUIRED_LITERT_PLATFORM_BUNDLES = {
    "android-arm64",
    "android-x64",
    "ios-arm64",
    "ios-arm64-sim",
    "linux-arm64",
    "linux-x64",
    "macos-arm64",
    "windows-x64",
}
# Schema 1 releases predate the arm64-only macOS policy (litert-lm-native#72)
# and keep their macOS x64 runtime archive.
LEGACY_SCHEMA1_LITERT_PLATFORM_BUNDLES = REQUIRED_LITERT_PLATFORM_BUNDLES | {
    "macos-x64",
}
LITERT_SMOKE_ASSETS = {
    "model": {
        "fileName": "moonshine_tiny_5s_i8.tflite",
        "sha256": "97abdeea122d579229091659c24c59d988c6419d453a200f6471241a53b9a9b9",
        "url": (
            "https://huggingface.co/litert-community/moonshine-tiny/resolve/"
            "beb49ee5028b4fb21eb989bcbd2db30a433373db/"
            "moonshine_tiny_5s_i8.tflite"
        ),
    },
    "tokenizer": {
        "fileName": "moonshine_tokenizer.json",
        "sha256": "6579793438bc4fbafffacf699169ff53e3769c5a0a0f5e71cdee8853e8130deb",
        "url": (
            "https://huggingface.co/UsefulSensors/moonshine-tiny/resolve/"
            "390624ed33d594443aa4aa221f5b9f283b545b5a/tokenizer.json"
        ),
    },
    "fixture": {
        "fileName": "jfk.wav",
        "sha256": "59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e",
        "url": (
            "https://raw.githubusercontent.com/ggml-org/whisper.cpp/"
            "592feef04a1802b18cbeffd0fd0eb5d02570c2ec/samples/jfk.wav"
        ),
    },
}
LITERT_ANDROID_DAWN_OVERRIDES = [
    {
        "sourceRepository": "google-ai-edge/LiteRT-LM",
        "sourceCommit": "f73637c57f0940b53da184e0d5adfc52a4e55eef",
        "sourcePath": "prebuilt/android_arm64/libwebgpu_dawn.so",
        "targetPath": "bin/android/arm64/libwebgpu_dawn.so",
        "sha256": "7282aacdb076ce89f0c9d93107a145b991b99eb1dfbd5b5746dd0d99466ab3c3",
    },
    {
        "sourceRepository": "google-ai-edge/LiteRT-LM",
        "sourceCommit": "f73637c57f0940b53da184e0d5adfc52a4e55eef",
        "sourcePath": "prebuilt/android_x86_64/libwebgpu_dawn.so",
        "targetPath": "bin/android/x64/libwebgpu_dawn.so",
        "sha256": "fcfb9a0b902f7dd3f81f01295f381c10b22a2d5774f95ee0db813f284a0ab087",
    },
]
# Hand-kept mirror of PREBUILT_OVERRIDES in leehack/litert-lm-native
# tools/prebuilt_overrides.py, keyed by upstream LiteRT-LM version. Extend it
# from the owner table before syncing a release on a new upstream version; never
# derive it from the manifest under validation.
LITERT_PREBUILT_OVERRIDES = {
    "v0.15.0": [
        {
            "sourceRepository": "google-ai-edge/LiteRT-LM",
            "sourceCommit": "8bee4dddc3794958b4bdd8a3a4ba75bcb71f6fbb",
            "sourcePath": "prebuilt/android_arm64/libLiteRtTopKOpenClSampler.so",
            "targetPath": "bin/android/arm64/libLiteRtTopKOpenClSampler.so",
            "sha256": "4404dc68786460602685cab62ddfa29035e9cfc38bb4550dec15abaaa1302a82",
        },
        {
            "sourceRepository": "google-ai-edge/LiteRT-LM",
            "sourceCommit": "8bee4dddc3794958b4bdd8a3a4ba75bcb71f6fbb",
            "sourcePath": "prebuilt/android_x86_64/libLiteRtTopKOpenClSampler.so",
            "targetPath": "bin/android/x64/libLiteRtTopKOpenClSampler.so",
            "sha256": "747ca5ed6a175fb4c2854ccee1d6ad97f11fe14d9e0d2b0c1710e1435376d51e",
        },
        *LITERT_ANDROID_DAWN_OVERRIDES,
    ],
    "v0.16.0": LITERT_ANDROID_DAWN_OVERRIDES,
    "v0.16.1": LITERT_ANDROID_DAWN_OVERRIDES,
    # v0.17.0-3 restores the reviewed Pixel/Mali correction. Earlier v0.17
    # artifacts without this provenance must not be newly adopted.
    "v0.17.0": LITERT_ANDROID_DAWN_OVERRIDES,
    "v0.17.1": LITERT_ANDROID_DAWN_OVERRIDES,
    # Stock v0.18 still loses the Vulkan device on Pixel Mali-G715.
    "v0.18.0": LITERT_ANDROID_DAWN_OVERRIDES,
    "v0.18.1": LITERT_ANDROID_DAWN_OVERRIDES,
    # v0.19 rebuilds Dawn; the owner retains the correction pending Pixel/Mali evidence.
    "v0.19.0": LITERT_ANDROID_DAWN_OVERRIDES,
    # v0.19.1 ships the same prebuilt Dawn and accelerator payloads as v0.19.0.
    "v0.19.1": LITERT_ANDROID_DAWN_OVERRIDES,
}
LITERT_REQUIRED_RUNTIME_PATHS = {
    "bin/android/arm64/libLiteRtLm.so",
    "bin/android/x64/libLiteRtLm.so",
    "bin/ios/arm64/LiteRtLm.framework/LiteRtLm",
    "bin/ios/arm64/CLiteRTLM.framework/CLiteRTLM",
    "bin/ios/arm64-sim/LiteRtLm.framework/LiteRtLm",
    "bin/ios/arm64-sim/CLiteRTLM.framework/CLiteRTLM",
    "bin/linux/arm64/libLiteRtLm.so",
    "bin/linux/x64/libLiteRtLm.so",
    "bin/macos/arm64/libCLiteRTLM_mac.dylib",
    "bin/macos/arm64/libLiteRtLm.dylib",
    "bin/windows/x64/LiteRtLm.dll",
}
LITERT_V0_16_IOS_GPU_PATHS = {
    "bin/ios/arm64/LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator",
    "bin/ios/arm64/LiteRtTopKMetalSampler.framework/LiteRtTopKMetalSampler",
    "bin/ios/arm64-sim/LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator",
    "bin/ios/arm64-sim/LiteRtTopKMetalSampler.framework/LiteRtTopKMetalSampler",
}
LITERT_SPM_ASSET_PATTERNS = (
    "litert-lm-native-apple-CLiteRTLM-xcframework-{tag}.zip",
    "litert-lm-native-apple-CLiteRTLMMac-xcframework-{tag}.zip",
    "litert-lm-native-apple-LiteRtLm-xcframework-{tag}.zip",
)
LITERT_METAL_ACCELERATOR_SPM_ASSET_PATTERN = (
    "litert-lm-native-apple-LiteRtMetalAccelerator-xcframework-{tag}.zip"
)
LITERT_V0_16_SPM_ASSET_PATTERNS = (
    LITERT_METAL_ACCELERATOR_SPM_ASSET_PATTERN,
    "litert-lm-native-apple-LiteRtTopKMetalSampler-xcframework-{tag}.zip",
)
LITERT_V0_16_ALLOWED_SPM_COMPANION_ASSET_PATTERNS = (
    "litert-lm-native-apple-GemmaModelConstraintProvider-xcframework-{tag}.zip",
    "litert-lm-native-apple-LiteRt-xcframework-{tag}.zip",
    "litert-lm-native-apple-LiteRtTopKWebGpuSampler-xcframework-{tag}.zip",
    "litert-lm-native-apple-LiteRtWebGpuAccelerator-xcframework-{tag}.zip",
    "litert-lm-native-apple-WebgpuDawn-xcframework-{tag}.zip",
)
LITERT_ALLOWED_ACCELERATORS = {"gpu", "metal", "opencl", "webgpu"}
# Where Xcode embeds each macOS runtime library from the owner xcframeworks:
# (Package.swift target, path under <App>.app/Contents/Frameworks). Library
# xcframeworks embed flat dylibs, framework xcframeworks embed versioned
# bundles, and LiteRtLm.framework carries its own Gemma provider. The Metal
# accelerator and sampler stay off macOS: their v0.18.0 macOS slices carry an
# invalid signature that kills Debug launches, and the macOS GPU path loads the
# WebGPU accelerator. A library missing here has an unreviewed layout and must
# fail the sync.
LITERT_MACOS_SPM_LAYOUT: dict[str, tuple[str | None, str | None]] = {
    "libLiteRtLm.dylib": ("LiteRtLm", "LiteRtLm.framework/Versions/A/LiteRtLm"),
    "libCLiteRTLM_mac.dylib": ("CLiteRTLMMac", "libCLiteRTLM_mac.dylib"),
    "libGemmaModelConstraintProvider.dylib": (
        None,
        "LiteRtLm.framework/Versions/A/Dependencies/"
        "libGemmaModelConstraintProvider.dylib",
    ),
    "libLiteRt.dylib": ("LiteRt", "libLiteRt.dylib"),
    "libLiteRtMetalAccelerator.dylib": (None, None),
    "libLiteRtTopKMetalSampler.dylib": (None, None),
    "libLiteRtTopKWebGpuSampler.dylib": (
        "LiteRtTopKWebGpuSampler",
        "libLiteRtTopKWebGpuSampler.dylib",
    ),
    "libLiteRtWebGpuAccelerator.dylib": (
        "LiteRtWebGpuAccelerator",
        "libLiteRtWebGpuAccelerator.dylib",
    ),
    "libwebgpu_dawn.dylib": ("WebgpuDawn", "libwebgpu_dawn.dylib"),
}


class ReleaseError(RuntimeError):
    pass


HTTP_SOCKET_TIMEOUT_SECONDS = 15.0
HTTP_TOTAL_TIMEOUT_SECONDS = 300.0
HTTP_MAX_ATTEMPTS = 3
HTTP_RETRY_DELAY_SECONDS = 2.0
HTTP_CHUNK_BYTES = 1024 * 1024
RETRYABLE_HTTP_STATUS = frozenset({408, 425, 429, 500, 502, 503, 504})


def describe_transport_error(error: BaseException) -> str:
    """Summarize a transport failure without echoing URLs or credentials."""
    if isinstance(error, urllib.error.HTTPError):
        return f"HTTP {error.code}"
    if isinstance(error, http.client.IncompleteRead):
        return "interrupted download"
    if isinstance(error, ValueError):
        return "invalid download URL"
    reason = error.reason if isinstance(error, urllib.error.URLError) else error
    if isinstance(reason, (TimeoutError, socket.timeout)):
        return (
            f"timed out (socket {HTTP_SOCKET_TIMEOUT_SECONDS:g}s, "
            f"total {HTTP_TOTAL_TIMEOUT_SECONDS:g}s)"
        )
    if isinstance(reason, socket.gaierror):
        return "DNS lookup failed"
    if isinstance(reason, ConnectionError):
        return "connection failed"
    if isinstance(reason, http.client.HTTPException):
        return "HTTP protocol error"
    return "network error"


def is_retryable_transport_error(error: BaseException) -> bool:
    if isinstance(error, ValueError):
        return False
    if isinstance(error, urllib.error.HTTPError):
        return error.code in RETRYABLE_HTTP_STATUS
    reason = error.reason if isinstance(error, urllib.error.URLError) else error
    return isinstance(
        reason,
        (
            TimeoutError,
            socket.timeout,
            socket.gaierror,
            ConnectionError,
            http.client.HTTPException,
        ),
    )


def response_chunks(response: Any, deadline: float) -> Iterator[bytes]:
    while True:
        if time.monotonic() > deadline:
            raise TimeoutError("release download exceeded the overall timeout")
        chunk = response.read(HTTP_CHUNK_BYTES)
        if time.monotonic() > deadline:
            raise TimeoutError("release download exceeded the overall timeout")
        if not chunk:
            return
        yield chunk


def read_release_url(
    url: str,
    *,
    context: str,
    headers: dict[str, str] | None = None,
    consume: Callable[[Iterator[bytes]], Any] = b"".join,
) -> Any:
    """Read a release URL with a 15s socket and 300s overall deadline.

    Transport failures and 408, 425, 429, and selected 5xx responses get at
    most three total attempts. Permanent HTTP failures are not retried. Errors
    omit the URL because release URLs may carry short-lived credentials.
    """
    deadline = time.monotonic() + HTTP_TOTAL_TIMEOUT_SECONDS
    for attempt in range(1, HTTP_MAX_ATTEMPTS + 1):
        try:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("release download exceeded the overall timeout")
            request = urllib.request.Request(url, headers=headers or {})
            with urllib.request.urlopen(
                request, timeout=min(HTTP_SOCKET_TIMEOUT_SECONDS, remaining)
            ) as response:
                return consume(response_chunks(response, deadline))
        except (OSError, ValueError, http.client.HTTPException) as error:
            reason = describe_transport_error(error)
            retryable = (
                attempt < HTTP_MAX_ATTEMPTS
                and is_retryable_transport_error(error)
                and time.monotonic() < deadline
            )
            if not retryable:
                raise ReleaseError(f"{context}: {reason}") from error
            delay = min(
                HTTP_RETRY_DELAY_SECONDS * attempt,
                max(0.0, deadline - time.monotonic()),
            )
            if delay:
                time.sleep(delay)
    raise ReleaseError(f"{context}: network error")


def read_release_fixture(path: Path, context: str) -> bytes:
    try:
        return path.read_bytes()
    except OSError as error:
        raise ReleaseError(f"{context}: cannot read fixture") from error


def github_api_headers() -> dict[str, str]:
    return {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        **github_auth_header(),
    }


def release_asset_context(
    release: dict[str, Any], asset_name: str, kind: str, repo: str = ""
) -> str:
    tag = release.get("tag_name")
    if not isinstance(tag, str) or not tag:
        tag = "<unknown>"
    identity = f"{repo}@{tag}" if repo else tag
    return f"Failed to read release {kind} {asset_name} ({identity})"


def _litert_compatibility_version(compatibility_tag: str) -> tuple[int, ...]:
    if not STABLE_LITERT_TAG_RE.fullmatch(compatibility_tag):
        raise ReleaseError("LiteRT-LM compatibility tag is invalid")
    return tuple(int(part) for part in compatibility_tag[1:].split("."))


# Upstream versions reviewed to export C API 1.0 and link both TopK samplers
# from source. Add a version only after comparing its C API exports.
LITERT_V1_COMPATIBILITY_VERSIONS = {(0, 19, 0), (0, 19, 1)}
# v0.19 LiteRtLm embeds LiteRT, so owner releases after v0.19.1-3 drop the
# macOS libLiteRt and WebGPU accelerator it never opens (#1911).
LITERT_UNUSED_APPLE_COMPANION_TARGETS = ("LiteRt", "LiteRtWebGpuAccelerator")


def _litert_is_v1_compatibility_tag(compatibility_tag: str) -> bool:
    return (
        _litert_compatibility_version(compatibility_tag)
        in LITERT_V1_COMPATIBILITY_VERSIONS
    )


def litert_spm_asset_patterns(
    compatibility_tag: str,
    *,
    allowed: bool,
) -> tuple[str, ...]:
    patterns: list[str] = list(LITERT_SPM_ASSET_PATTERNS)
    version = _litert_compatibility_version(compatibility_tag)
    if version >= (0, 16, 0):
        patterns.extend(LITERT_V0_16_SPM_ASSET_PATTERNS)
        if allowed:
            patterns.extend(LITERT_V0_16_ALLOWED_SPM_COMPANION_ASSET_PATTERNS)
        if version in LITERT_V1_COMPATIBILITY_VERSIONS:
            # The reviewed v0.19 owner links both TopK samplers from source.
            obsolete = {
                "litert-lm-native-apple-LiteRtTopKMetalSampler-xcframework-{tag}.zip",
                "litert-lm-native-apple-LiteRtTopKWebGpuSampler-xcframework-{tag}.zip",
            }
            if not allowed:
                # v0.19 Apple runtimes link their GPU accelerator, so owner
                # releases after v0.19.1-2 drop the unused Metal one (#1798).
                obsolete.add(LITERT_METAL_ACCELERATOR_SPM_ASSET_PATTERN)
            patterns = [pattern for pattern in patterns if pattern not in obsolete]
    return tuple(patterns)


def litert_spm_artifact_paths(
    compatibility_tag: str,
    release_tag: str,
    *,
    allowed: bool,
) -> set[str]:
    return {
        f"dist/spm/{release_tag}/{pattern.format(tag=release_tag)}"
        for pattern in litert_spm_asset_patterns(
            compatibility_tag,
            allowed=allowed,
        )
    }


def validate_litert_spm_artifact_inventory(
    artifact_paths: set[str],
    *,
    compatibility_tag: str,
    release_tag: str,
) -> set[str]:
    required_paths = litert_spm_artifact_paths(
        compatibility_tag,
        release_tag,
        allowed=False,
    )
    allowed_paths = litert_spm_artifact_paths(
        compatibility_tag,
        release_tag,
        allowed=True,
    )
    actual_paths = {
        path
        for path in artifact_paths
        if Path(path).parts[:2] == ("dist", "spm")
    }
    missing_paths = required_paths - actual_paths
    unexpected_paths = actual_paths - allowed_paths
    if missing_paths or unexpected_paths:
        raise ReleaseError(
            "LiteRT-LM SPM artifact inventory mismatch; "
            f"missing={sorted(missing_paths)}, "
            f"unexpected={sorted(unexpected_paths)}"
        )
    return actual_paths


class NativeReleaseVersion(NamedTuple):
    channel: str
    version: tuple[int, ...]
    wrapper_revision: int
    upstream_tag: str


class NativeBackendSidecar(NamedTuple):
    bundle: str
    backend: str
    archive: str


class NativeReleaseManifest(NamedTuple):
    checksums: dict[str, str]
    hook_contract_version: int
    sidecars: tuple[NativeBackendSidecar, ...]


def require_exact_keys(value: Any, expected: set[str], label: str) -> None:
    if not isinstance(value, dict):
        raise ReleaseError(f"LiteRT-LM {label} must be an object")
    actual = set(value.keys())
    if actual != expected:
        raise ReleaseError(
            f"LiteRT-LM {label} keys do not match owner schema 2; "
            f"missing={sorted(expected - actual)}, "
            f"unexpected={sorted(actual - expected)}"
        )


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ReleaseError(f"LiteRT-LM {label} must be a non-empty string")
    return value


def require_full_commit(value: Any, label: str) -> str:
    commit = require_string(value, label)
    if not FULL_COMMIT_RE.fullmatch(commit):
        raise ReleaseError(f"LiteRT-LM {label} must be an exact 40-hex commit")
    return commit


def require_sha256(value: Any, label: str) -> str:
    digest = require_string(value, label)
    if not SHA256_RE.fullmatch(digest):
        raise ReleaseError(f"LiteRT-LM {label} must be an exact SHA-256 digest")
    return digest


def require_int(value: Any, label: str, *, minimum: int | None = None) -> int:
    if type(value) is not int:
        raise ReleaseError(f"LiteRT-LM {label} must be an integer")
    if minimum is not None and value < minimum:
        raise ReleaseError(f"LiteRT-LM {label} must be at least {minimum}")
    return value


def required_litert_manifest_paths(
    compatibility_tag: str,
    release_tag: str,
    *,
    official_assets: bool,
) -> set[str]:
    version = _litert_compatibility_version(compatibility_tag)
    required = set(LITERT_REQUIRED_RUNTIME_PATHS)
    if version >= (0, 16, 0):
        required.update(
            path for path in LITERT_V0_16_IOS_GPU_PATHS
            if version not in LITERT_V1_COMPATIBILITY_VERSIONS
        )
    if official_assets and version >= (0, 14, 0):
        required.update(
            {
                f"dist/official/{compatibility_tag}/CLiteRTLM.xcframework.zip",
                f"dist/official/{compatibility_tag}/CLiteRTLM_mac.xcframework.zip",
            }
        )
    required.update(
        litert_spm_artifact_paths(
            compatibility_tag,
            release_tag,
            allowed=False,
        )
    )
    required.update(
        override["targetPath"]
        for override in LITERT_PREBUILT_OVERRIDES.get(compatibility_tag, [])
    )
    return required


def required_litert_release_asset_names(
    manifest: dict[str, Any], release_tag: str
) -> set[str]:
    platforms = manifest.get("platforms")
    artifacts = manifest.get("artifacts")
    capabilities = manifest.get("capabilities")
    upstream = manifest.get("upstream")
    if not isinstance(platforms, list) or not isinstance(artifacts, list):
        raise ReleaseError("LiteRT-LM owner inventory requires schema-2 platform artifacts")
    if not isinstance(capabilities, dict):
        raise ReleaseError("LiteRT-LM owner inventory requires schema-2 capabilities")
    if not isinstance(upstream, dict):
        raise ReleaseError("LiteRT-LM owner inventory requires schema-2 upstream metadata")
    compatibility_tag = require_string(
        upstream.get("compatibilityTag"),
        "owner inventory upstream compatibilityTag",
    )
    artifact_paths = {
        artifact["path"]
        for artifact in artifacts
        if isinstance(artifact, dict) and isinstance(artifact.get("path"), str)
    }
    spm_paths = validate_litert_spm_artifact_inventory(
        artifact_paths,
        compatibility_tag=compatibility_tag,
        release_tag=release_tag,
    )
    assets = {
        "manifest.json",
        "SHA256SUMS",
        "release-result.json",
        f"litert-lm-native-prebuilts-{release_tag}.tar.gz",
    }
    for platform in platforms:
        if not isinstance(platform, dict) or not isinstance(
            platform.get("releaseAsset"), str
        ):
            raise ReleaseError("LiteRT-LM owner inventory has an invalid platform asset")
        assets.add(platform["releaseAsset"])
    assets.update(Path(path).name for path in spm_paths)
    if capabilities.get("officialUpstreamAssets") is True:
        assets.add(f"litert-lm-native-official-assets-{release_tag}.tar.gz")
    return assets


def litert_schema2_apple_targets(
    manifest: dict[str, Any], release_tag: str
) -> set[str]:
    prefix = "litert-lm-native-apple-"
    suffix = f"-xcframework-{release_tag}.zip"
    upstream = manifest.get("upstream")
    compatibility_tag = require_string(
        upstream.get("compatibilityTag") if isinstance(upstream, dict) else None,
        "owner inventory upstream compatibilityTag",
    )
    required_asset_names = {
        Path(path).name
        for path in litert_spm_artifact_paths(
            compatibility_tag,
            release_tag,
            allowed=False,
        )
    }
    targets = {
        asset_name[len(prefix) : -len(suffix)]
        for asset_name in required_asset_names
        if asset_name.startswith(prefix) and asset_name.endswith(suffix)
    }
    # Optional release assets alone do not imply a dependency. Include the
    # provider only when an iOS runtime bundle actually requires its binary.
    bundles = litert_schema2_bundle_required_libraries(manifest)
    if _litert_is_v1_compatibility_tag(compatibility_tag) and any(
        "TopKMetalSampler" in library or "TopKWebGpuSampler" in library
        for bundle, libraries in bundles.items()
        if bundle.startswith(("ios-", "macos-"))
        for library in libraries
    ):
        raise ReleaseError(
            f"LiteRT-LM {compatibility_tag} owner inventory unexpectedly requires a prebuilt TopK sampler"
        )
    if any(
        "GemmaModelConstraintProvider" in libraries
        for bundle, libraries in bundles.items() if bundle.startswith("ios-")
    ):
        targets.add("GemmaModelConstraintProvider")
    if _litert_is_v1_compatibility_tag(compatibility_tag):
        ios_metal = {
            "LiteRtMetalAccelerator" in libraries
            for bundle, libraries in bundles.items() if bundle.startswith("ios-")
        }
        if ios_metal == {True}:
            targets.add("LiteRtMetalAccelerator")
        elif ios_metal != {False}:
            raise ReleaseError(
                f"LiteRT-LM {compatibility_tag} owner inventory ships the iOS "
                "Metal accelerator for only some iOS bundles"
            )
    allowed_asset_names = {
        Path(path).name
        for path in litert_spm_artifact_paths(
            compatibility_tag,
            release_tag,
            allowed=True,
        )
    }
    for bundle, libraries in bundles.items():
        if not bundle.startswith("macos-"):
            continue
        for library in libraries:
            target, _ = litert_macos_spm_layout(library)
            if target is None:
                continue
            if f"{prefix}{target}{suffix}" not in allowed_asset_names:
                raise ReleaseError(
                    f"LiteRT-LM macOS runtime library {library} needs the "
                    f"{target} SwiftPM artifact, which the owner inventory "
                    "does not allow"
                )
            targets.add(target)
    if not targets:
        raise ReleaseError("LiteRT-LM schema-2 owner inventory has no Apple targets")
    return targets


def validate_litert_release_asset_inventory(
    release: dict[str, Any], manifest: dict[str, Any], release_tag: str
) -> None:
    assets = release.get("assets")
    if not isinstance(assets, list) or any(
        not isinstance(asset, dict) or not isinstance(asset.get("name"), str)
        for asset in assets
    ):
        raise ReleaseError("LiteRT-LM GitHub release asset inventory is invalid")
    names = [asset["name"] for asset in assets]
    if len(names) != len(set(names)):
        raise ReleaseError("LiteRT-LM GitHub release asset inventory has duplicates")
    expected = required_litert_release_asset_names(manifest, release_tag)
    actual = set(names)
    if actual != expected:
        raise ReleaseError(
            "LiteRT-LM GitHub release asset inventory does not match owner policy; "
            f"missing={sorted(expected - actual)}, unexpected={sorted(actual - expected)}"
        )
    for asset in assets:
        digest = asset.get("digest")
        if (
            not isinstance(digest, str)
            or not digest.startswith("sha256:")
            or not SHA256_RE.fullmatch(digest.removeprefix("sha256:"))
        ):
            raise ReleaseError(
                f"Asset {asset['name']} has an invalid GitHub SHA-256 digest"
            )


def validate_litert_release_sha256_sums(
    release: dict[str, Any],
    manifest: dict[str, Any],
    *,
    repo: str,
    tag: str,
    release_json_dir: str,
) -> None:
    checksum_bytes = release_asset_bytes(
        release,
        "SHA256SUMS",
        repo=repo,
        tag=tag,
        release_json_dir=release_json_dir,
    )
    expected_asset_digest = release_asset_checksum(
        release, "SHA256SUMS", repo=repo
    )
    actual_asset_digest = hashlib.sha256(checksum_bytes).hexdigest()
    if actual_asset_digest != expected_asset_digest:
        raise ReleaseError(
            "LiteRT-LM SHA256SUMS bytes do not match the GitHub release digest"
        )
    try:
        checksum_text = checksum_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ReleaseError(
            f"Release {tag} SHA256SUMS is not valid UTF-8: {error}"
        ) from error
    actual = parse_sha256_sums(checksum_text, tag)
    expected = {
        require_string(artifact["path"], "artifact path"): require_sha256(
            artifact["sha256"], "artifact digest"
        )
        for artifact in manifest["artifacts"]
    }
    if actual != expected:
        missing = sorted(set(expected) - set(actual))
        unexpected = sorted(set(actual) - set(expected))
        mismatched = sorted(
            path
            for path in set(expected) & set(actual)
            if expected[path] != actual[path]
        )
        raise ReleaseError(
            "LiteRT-LM SHA256SUMS does not match manifest artifacts; "
            f"missing={missing}, unexpected={unexpected}, mismatched={mismatched}"
        )


def validate_litert_spm_release_asset_digests(
    release: dict[str, Any],
    manifest: dict[str, Any],
    *,
    repo: str,
    release_tag: str,
) -> None:
    upstream = manifest.get("upstream")
    compatibility_tag = require_string(
        upstream.get("compatibilityTag") if isinstance(upstream, dict) else None,
        "owner inventory upstream compatibilityTag",
    )
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise ReleaseError("LiteRT-LM owner inventory requires schema-2 artifacts")
    artifacts_by_path = {
        artifact["path"]: artifact
        for artifact in artifacts
        if isinstance(artifact, dict) and isinstance(artifact.get("path"), str)
    }
    spm_paths = validate_litert_spm_artifact_inventory(
        set(artifacts_by_path),
        compatibility_tag=compatibility_tag,
        release_tag=release_tag,
    )
    for path in sorted(spm_paths):
        asset_name = Path(path).name
        release_digest = release_asset_checksum(release, asset_name, repo=repo)
        manifest_digest = require_sha256(
            artifacts_by_path[path].get("sha256"),
            f"SPM artifact {path} digest",
        )
        if release_digest != manifest_digest:
            raise ReleaseError(
                "LiteRT-LM SPM release asset digest does not match manifest; "
                f"asset={asset_name}, manifest={manifest_digest}, "
                f"release={release_digest}"
            )


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    pins_path = repo_root / args.native_pins
    llama_cpp_package_swift_path = repo_root / args.llama_cpp_package_swift
    litert_lm_package_swift_path = repo_root / args.litert_lm_package_swift
    stable_diffusion_package_swift_path = (
        repo_root / args.stable_diffusion_package_swift
    )
    litert_lm_runtime_dart_path = repo_root / args.litert_lm_runtime_dart
    litert_lm_macos_prepare_path = repo_root / args.litert_lm_macos_prepare_script
    changelog_path = repo_root / DEFAULT_CHANGELOG
    llama_cpp_project_doc_paths = [
        repo_root / relative_path for relative_path in DEFAULT_LLAMA_CPP_PROJECT_DOCS
    ]

    pins_text = pins_path.read_text(encoding="utf-8")
    pending_writes: dict[Path, str] = {}
    project_doc_dependency_versions: dict[str, str] = {}

    summaries: list[str] = []
    resolved_llama_cpp_tag = ""
    resolved_litert_lm_tag = "keep"
    resolved_stable_diffusion_tag = "keep"

    llama_cpp_tag_input = normalize_release_tag(args.llama_cpp_tag)
    litert_lm_tag_input = normalize_litert_lm_release_tag(args.litert_lm_tag)
    stable_diffusion_tag_input = normalize_stable_diffusion_release_tag(
        args.stable_diffusion_tag
    )

    if llama_cpp_tag_input != "keep":
        release = fetch_release(
            args.llamadart_native_repo,
            llama_cpp_tag_input,
            args.release_json_dir,
        )
        current_llama_cpp_tag = read_hook_native_tag(pins_text)
        resolved_llama_cpp_tag = validate_resolved_native_release(
            release,
            requested_tag=llama_cpp_tag_input,
            current_tag=current_llama_cpp_tag,
            allow_legacy_tag=args.allow_legacy_tag,
        )
        native_manifest = validate_native_release_manifest(
            release,
            resolved_llama_cpp_tag,
            repo=args.llamadart_native_repo,
        )
        manifest_checksums = native_manifest.checksums
        pins_text = replace_one(
            pins_text,
            r"const llamaCppTag = '[^']+';",
            f"const llamaCppTag = '{resolved_llama_cpp_tag}';",
            "native pins llama.cpp tag",
        )
        for bundle in llama_cpp_bundle_names(pins_text):
            pins_text = replace_llama_cpp_bundle_checksum(
                pins_text,
                bundle,
                llama_cpp_bundle_checksum(
                    release,
                    bundle,
                    resolved_llama_cpp_tag,
                    manifest_checksums,
                    repo=args.llamadart_native_repo,
                ),
            )
        pins_text = replace_llama_cpp_hook_contract(
            pins_text,
            native_manifest.hook_contract_version,
        )
        pins_text = replace_llama_cpp_backend_sidecars(
            pins_text,
            [
                (
                    sidecar,
                    llama_cpp_bundle_checksum(
                        release,
                        sidecar.archive,
                        resolved_llama_cpp_tag,
                        manifest_checksums,
                        repo=args.llamadart_native_repo,
                    ),
                )
                for sidecar in native_manifest.sidecars
            ],
        )
        if resolved_llama_cpp_tag != current_llama_cpp_tag:
            pins_text, cleared_tags = clear_compatible_apple_companion_tags(
                pins_text
            )
            if cleared_tags:
                summaries.append(
                    "cleared compatible Apple llama.cpp companion tags "
                    f"{', '.join(cleared_tags)}; re-verify their ABI against "
                    f"{resolved_llama_cpp_tag} before listing them again"
                )
        if llama_cpp_package_swift_path.exists():
            checksum = release_asset_checksum(
                release,
                f"llamadart-native-apple-xcframework-{resolved_llama_cpp_tag}.zip",
                repo=args.llamadart_native_repo,
            )
            pins_text = refresh_llama_cpp_apple_checksum(
                pins_text, resolved_llama_cpp_tag, checksum
            )
            original_swift_text = llama_cpp_package_swift_path.read_text(
                encoding="utf-8"
            )
            swift_text = original_swift_text
            swift_text = replace_one(
                swift_text,
                r'let llamaCppTag = "[^"]+"',
                f'let llamaCppTag = "{resolved_llama_cpp_tag}"',
                "llama.cpp Package.swift tag",
            )
            swift_text = replace_swift_binary_target_checksum(
                swift_text,
                "llama",
                checksum,
            )
            pending_writes[llama_cpp_package_swift_path] = swift_text
            package_root = companion_package_root(llama_cpp_package_swift_path)
            bump_companion = (
                args.bump_companion_versions and swift_text != original_swift_text
            )
            companion_version = update_companion_package_metadata(
                pending_writes,
                package_root,
                args.llamadart_native_repo,
                resolved_llama_cpp_tag,
                bump_version=bump_companion,
            )
            project_doc_dependency_versions[package_root.name] = companion_version
            if swift_text != original_swift_text:
                pins_text = replace_one(
                    pins_text,
                    r"const llamaCppAppleCompanionVersion = '[^']+';",
                    "const llamaCppAppleCompanionVersion = '"
                    + (
                        companion_version
                        if bump_companion
                        else bump_patch_version(companion_version)
                    )
                    + "';",
                    "native pins Apple llama.cpp companion version",
                )
        update_llama_cpp_project_docs(
            pending_writes,
            llama_cpp_project_doc_paths,
            changelog_path,
            args.llamadart_native_repo,
            resolved_llama_cpp_tag,
        )

        summaries.append(
            f"llama.cpp -> {args.llamadart_native_repo}@{resolved_llama_cpp_tag}"
        )

    if litert_lm_tag_input != "keep":
        release = fetch_release(
            args.litert_lm_native_repo,
            litert_lm_tag_input,
            args.release_json_dir,
        )
        resolved_litert_lm_tag = release["tag_name"]
        current_litert_lm_tag = current_litert_lm_release_tag(pins_text)
        validate_litert_lm_transition(
            current_litert_lm_tag,
            resolved_litert_lm_tag,
            allow_channel_transition=args.allow_litert_channel_transition,
            allow_stable_rebuild_entry=args.allow_litert_stable_rebuild_entry,
            allow_development_line_transition=(
                args.allow_litert_development_line_transition
            ),
        )
        litert_version = litert_lm_runtime_version(resolved_litert_lm_tag)
        litert_lm_manifest = validate_litert_lm_release_manifest(
            release,
            repo=args.litert_lm_native_repo,
            tag=resolved_litert_lm_tag,
            release_json_dir=args.release_json_dir,
            required_bundles=litert_lm_bundle_names(pins_text),
        )

        pins_text = replace_one(
            pins_text,
            r"const liteRtLmReleaseTag = '[^']+';",
            f"const liteRtLmReleaseTag = '{resolved_litert_lm_tag}';",
            "native pins LiteRT-LM release tag",
        )
        pins_text = replace_one(
            pins_text,
            r"const liteRtLmVersion = '[^']+';",
            f"const liteRtLmVersion = '{litert_version}';",
            "native pins LiteRT-LM version",
        )
        if not litert_lm_runtime_dart_path.exists():
            raise ReleaseError(
                f"Missing LiteRT-LM Dart runtime {litert_lm_runtime_dart_path}"
            )
        runtime_dart_text = litert_lm_runtime_dart_path.read_text(
            encoding="utf-8"
        )
        runtime_dart_text = replace_one(
            runtime_dart_text,
            r"const _litertLmReleaseTag = '[^']+';",
            f"const _litertLmReleaseTag = '{resolved_litert_lm_tag}';",
            "LiteRT-LM Dart runtime release tag",
        )
        schema2_bundle_libraries: dict[str, tuple[str, ...]] | None = None
        if litert_lm_manifest.get("schemaVersion") == 2:
            schema2_bundle_libraries = litert_schema2_bundle_required_libraries(
                litert_lm_manifest
            )
            runtime_dart_text = replace_litert_lm_runtime_required_libraries(
                runtime_dart_text,
                schema2_bundle_libraries,
                manifest=litert_lm_manifest,
            )
            runtime_dart_text = replace_litert_lm_runtime_macos_inventory(
                runtime_dart_text,
                schema2_bundle_libraries,
                manifest=litert_lm_manifest,
                resolved_tag=resolved_litert_lm_tag,
            )
        pending_writes[litert_lm_runtime_dart_path] = replace_one(
            runtime_dart_text,
            r"const _litertLmVersion = '[^']+';",
            f"const _litertLmVersion = '{litert_version}';",
            "LiteRT-LM Dart runtime version",
        )
        if litert_lm_macos_prepare_path.exists():
            prepare_text = litert_lm_macos_prepare_path.read_text(encoding="utf-8")
            updated_prepare_text, replacement_count = re.subn(
                r"(/litert_lm/)[^/]+(/macos(?:_|/))",
                rf"\g<1>{litert_version}\g<2>",
                prepare_text,
            )
            if replacement_count == 0:
                raise ReleaseError(
                    "Could not replace LiteRT-LM version in macOS prepare script"
                )
            if schema2_bundle_libraries is not None:
                updated_prepare_text = replace_litert_lm_macos_prepare_inventory(
                    updated_prepare_text,
                    schema2_bundle_libraries,
                    manifest=litert_lm_manifest,
                    resolved_tag=resolved_litert_lm_tag,
                )
            pending_writes[litert_lm_macos_prepare_path] = updated_prepare_text
        for bundle in litert_lm_bundle_names(pins_text):
            checksum = release_asset_checksum(
                release,
                f"litert-lm-native-runtime-{bundle}-{resolved_litert_lm_tag}.tar.gz",
                repo=args.litert_lm_native_repo,
            )
            pins_text = replace_litert_lm_bundle_checksum(
                pins_text,
                bundle,
                checksum,
            )
        if schema2_bundle_libraries is not None:
            for bundle, libraries in schema2_bundle_libraries.items():
                pins_text = replace_litert_lm_bundle_required_libraries(
                    pins_text,
                    bundle,
                    libraries,
                )

        if litert_lm_package_swift_path.exists():
            original_swift_text = litert_lm_package_swift_path.read_text(
                encoding="utf-8"
            )
            swift_text = prepare_litert_lm_package_swift(
                original_swift_text,
                release=release,
                manifest=litert_lm_manifest,
                resolved_tag=resolved_litert_lm_tag,
                repo=args.litert_lm_native_repo,
            )
            hook_path = repo_root / DEFAULT_BUILD_HOOK
            if not hook_path.exists():
                raise ReleaseError(f"Missing native build hook {hook_path}")
            hook_text = hook_path.read_text(encoding="utf-8")
            pending_writes[hook_path] = replace_litert_lm_companion_template_hash(
                hook_text,
                original_swift=original_swift_text,
                prepared_swift=swift_text,
                resolved_tag=resolved_litert_lm_tag,
            )
            summaries.append(
                "LiteRT-LM SwiftPM template SHA-256 -> "
                + litert_lm_companion_template_hash(swift_text)
            )
            pending_writes[litert_lm_package_swift_path] = swift_text
            package_root = companion_package_root(litert_lm_package_swift_path)
            project_doc_dependency_versions[package_root.name] = (
                update_companion_package_metadata(
                    pending_writes,
                    package_root,
                    args.litert_lm_native_repo,
                    resolved_litert_lm_tag,
                    bump_version=(
                        args.bump_companion_versions
                        and swift_text != original_swift_text
                    ),
                )
            )

        summaries.append(
            f"LiteRT-LM -> {args.litert_lm_native_repo}@{resolved_litert_lm_tag}"
        )

    if stable_diffusion_tag_input != "keep":
        release = fetch_release(
            args.stable_diffusion_native_repo,
            stable_diffusion_tag_input,
            args.release_json_dir,
        )
        resolved_stable_diffusion_tag = normalize_stable_diffusion_release_tag(
            release["tag_name"]
        )
        if resolved_stable_diffusion_tag in {"keep", "latest"}:
            raise ReleaseError(
                "stable-diffusion-native release resolved an invalid tag"
            )
        validate_stable_diffusion_transition(
            current_stable_diffusion_release_tag(pins_text),
            resolved_stable_diffusion_tag,
        )
        runtime_artifacts, xcframework_checksum = (
            validate_stable_diffusion_release_manifest(
                release,
                repo=args.stable_diffusion_native_repo,
                tag=resolved_stable_diffusion_tag,
                release_json_dir=args.release_json_dir,
            )
        )
        pinned_bundles = stable_diffusion_bundle_names(pins_text)
        missing = sorted(set(pinned_bundles) - set(runtime_artifacts))
        if missing:
            raise ReleaseError(
                "stable-diffusion-native "
                f"{resolved_stable_diffusion_tag} does not publish pinned "
                "bundles: " + ", ".join(missing)
            )
        unpinned = sorted(set(runtime_artifacts) - set(pinned_bundles))
        if unpinned:
            print(
                "note: stable-diffusion-native "
                f"{resolved_stable_diffusion_tag} also publishes "
                + ", ".join(unpinned)
                + "; add a StableDiffusionBundleSpec and hook mapping to use "
                "them.",
                file=sys.stderr,
            )
        pins_text = refresh_stable_diffusion_apple_contract(
            pins_text,
            current_stable_diffusion_release_tag(pins_text),
            resolved_stable_diffusion_tag,
            xcframework_checksum,
        )
        pins_text = replace_one(
            pins_text,
            r"const stableDiffusionReleaseTag = '[^']+';",
            "const stableDiffusionReleaseTag = "
            f"'{resolved_stable_diffusion_tag}';",
            "native pins stable_diffusion release tag",
        )
        pins_text = replace_one(
            pins_text,
            r"const stableDiffusionVersion = '[^']+';",
            "const stableDiffusionVersion = "
            f"'{resolved_stable_diffusion_tag[1:]}';",
            "native pins stable_diffusion version",
        )
        for bundle in pinned_bundles:
            checksum, library = runtime_artifacts[bundle]
            pins_text = replace_stable_diffusion_bundle(
                pins_text, bundle, checksum, library
            )
        if stable_diffusion_package_swift_path.exists():
            if xcframework_checksum is None:
                raise ReleaseError(
                    "stable-diffusion-native "
                    f"{resolved_stable_diffusion_tag} publishes no Apple "
                    "XCFramework for the Flutter companion"
                )
            original_swift_text = stable_diffusion_package_swift_path.read_text(
                encoding="utf-8"
            )
            swift_text = replace_one(
                original_swift_text,
                r'let stableDiffusionTag = "[^"]+"',
                f'let stableDiffusionTag = "{resolved_stable_diffusion_tag}"',
                "stable_diffusion Package.swift tag",
            )
            swift_text = replace_swift_binary_target_checksum(
                swift_text,
                "stable_diffusion",
                xcframework_checksum,
            )
            pending_writes[stable_diffusion_package_swift_path] = swift_text
            package_root = companion_package_root(
                stable_diffusion_package_swift_path
            )
            companion_version = update_companion_package_metadata(
                pending_writes,
                package_root,
                args.stable_diffusion_native_repo,
                resolved_stable_diffusion_tag,
                bump_version=(
                    args.bump_companion_versions
                    and swift_text != original_swift_text
                ),
            )
            project_doc_dependency_versions[package_root.name] = companion_version
            if swift_text != original_swift_text:
                first_release = (
                    companion_version if args.bump_companion_versions
                    else bump_patch_version(companion_version)
                )
                pins_text = replace_one(
                    pins_text,
                    r"const stableDiffusionAppleCompanionVersion = '[^']+';",
                    f"const stableDiffusionAppleCompanionVersion = '{first_release}';",
                    "native pins Apple SD companion version",
                )

        summaries.append(
            "stable_diffusion -> "
            f"{args.stable_diffusion_native_repo}@{resolved_stable_diffusion_tag}"
        )

    if not summaries:
        print("No native release pins requested; pass a tag or latest.")
        return 0

    if project_doc_dependency_versions:
        update_project_doc_dependency_versions(
            pending_writes,
            llama_cpp_project_doc_paths,
            project_doc_dependency_versions,
        )

    if args.dry_run:
        print("Dry run; no files written.")
    else:
        pending_writes[pins_path] = pins_text
        atomic_write_many(pending_writes)

    for summary in summaries:
        print(f"Synced {summary}")

    write_github_output(
        {
            "resolved_llama_cpp_tag": resolved_llama_cpp_tag,
            "resolved_litert_lm_tag": resolved_litert_lm_tag,
            "resolved_stable_diffusion_tag": resolved_stable_diffusion_tag,
        }
    )
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Update the native release pins from published native release "
            "asset checksums."
        )
    )
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Repository root. Defaults to the current directory.",
    )
    parser.add_argument(
        "--native-pins",
        default=DEFAULT_NATIVE_RELEASE_PINS,
        help="Path to the native release pins Dart file relative to repo root.",
    )
    parser.add_argument(
        "--llama-cpp-package-swift",
        default=DEFAULT_LLAMA_CPP_PACKAGE_SWIFT,
        help=(
            "Path to the llama.cpp Flutter companion Package.swift relative "
            "to repo root. Skipped if the file does not exist."
        ),
    )
    parser.add_argument(
        "--litert-lm-package-swift",
        default=DEFAULT_LITERT_LM_PACKAGE_SWIFT,
        help=(
            "Path to the LiteRT-LM Flutter companion Package.swift relative "
            "to repo root. Skipped if the file does not exist."
        ),
    )
    parser.add_argument(
        "--stable-diffusion-package-swift",
        default=DEFAULT_STABLE_DIFFUSION_PACKAGE_SWIFT,
        help=(
            "Path to the stable_diffusion Flutter companion Package.swift "
            "relative to repo root. Skipped if the file does not exist."
        ),
    )
    parser.add_argument(
        "--litert-lm-runtime-dart",
        default=DEFAULT_LITERT_LM_RUNTIME_DART,
        help=(
            "Path to the LiteRT-LM Dart runtime version pin relative "
            "to repo root."
        ),
    )
    parser.add_argument(
        "--litert-lm-macos-prepare-script",
        default=DEFAULT_LITERT_LM_MACOS_PREPARE_SCRIPT,
        help=(
            "Path to the LiteRT-LM macOS app preparation script relative "
            "to repo root. Skipped if the file does not exist."
        ),
    )
    parser.add_argument(
        "--llama-cpp-tag",
        default="keep",
        help=(
            "Explicit llamadart-native stable, wrapper-rebuild, or "
            "historical/nightly tag; latest unsuffixed stable; or keep."
        ),
    )
    parser.add_argument(
        "--allow-legacy-tag",
        action="store_true",
        help=(
            "Allow an explicit stable-to-historical/nightly bNNNN channel "
            "switch. This does not permit version rollback or make latest "
            "accept a wrapper rebuild or nightly release."
        ),
    )
    parser.add_argument(
        "--litert-lm-tag",
        default="keep",
        help=(
            "litert-lm-native vX.Y.Z, vX.Y.Z-N, g<12hex>[-N], legacy "
            "vX.Y.Z-native.N, latest, or keep."
        ),
    )
    parser.add_argument(
        "--llamadart-native-repo",
        default=DEFAULT_LLAMADART_NATIVE_REPO,
        help="GitHub repo slug for llama.cpp native artifacts.",
    )
    parser.add_argument(
        "--litert-lm-native-repo",
        default=DEFAULT_LITERT_LM_NATIVE_REPO,
        help="GitHub repo slug for LiteRT-LM native artifacts.",
    )
    parser.add_argument(
        "--stable-diffusion-tag",
        default="keep",
        help="stable-diffusion-native vX.Y.Z or vX.Y.Z-N, latest, or keep.",
    )
    parser.add_argument(
        "--stable-diffusion-native-repo",
        default=DEFAULT_STABLE_DIFFUSION_NATIVE_REPO,
        help="GitHub repo slug for stable_diffusion native artifacts.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Resolve releases and validate assets without writing files.",
    )
    parser.add_argument(
        "--bump-companion-versions",
        action="store_true",
        help=(
            "Also bump Flutter companion package pubspec versions and current "
            "install snippets. Native sync PRs should leave this unset; "
            "release-prep PRs may opt in."
        ),
    )
    parser.add_argument(
        "--allow-litert-channel-transition",
        action="store_true",
        help=(
            "Explicitly approve a stable/development channel transition after "
            "reviewing the owner manifest ancestry evidence."
        ),
    )
    parser.add_argument(
        "--allow-litert-development-line-transition",
        action="store_true",
        help=(
            "Explicitly approve changing from one g<commit> development line to "
            "another after reviewing owner manifest ancestry evidence."
        ),
    )
    parser.add_argument(
        "--allow-litert-stable-rebuild-entry",
        action="store_true",
        help=(
            "Allow entering a newer stable version at a qualified rebuild. "
            "Manifest validation and all other transition guards still apply."
        ),
    )
    parser.add_argument(
        "--release-json-dir",
        default="",
        help=(
            "Optional fixture directory for tests. Files are named "
            "<owner>__<repo>__<tag>.json."
        ),
    )
    return parser.parse_args()


def fetch_release(repo: str, tag: str, release_json_dir: str = "") -> dict[str, Any]:
    context = f"Failed to fetch release {repo}@{tag}"
    if release_json_dir:
        path = Path(release_json_dir) / f"{repo.replace('/', '__')}__{tag}.json"
        raw = read_release_fixture(path, context)
    else:
        if tag == "latest":
            url = f"https://api.github.com/repos/{repo}/releases/latest"
        else:
            url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
        raw = read_release_url(url, context=context, headers=github_api_headers())
    try:
        payload: Any = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError(f"{context}: invalid UTF-8 or JSON") from error
    if not isinstance(payload, dict):
        raise ReleaseError(f"Release {repo}@{tag} must be a JSON object")
    resolved_tag = payload.get("tag_name")
    if not isinstance(resolved_tag, str) or not resolved_tag:
        raise ReleaseError(f"Release {repo}@{tag} has no valid tag_name")
    if tag != "latest" and resolved_tag != tag:
        raise ReleaseError(
            f"Release {repo}@{tag} resolved unexpected tag {resolved_tag}"
        )
    return payload


def github_auth_header() -> dict[str, str]:
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    return {"Authorization": f"Bearer {token}"} if token else {}


def release_asset_checksum(
    release: dict[str, Any], asset_name: str, *, repo: str = ""
) -> str:
    asset = find_release_asset(release, asset_name)
    if asset is not None:
        digest = asset.get("digest")
        if digest not in (None, "") and not isinstance(digest, str):
            raise ReleaseError(
                f"Asset {asset_name} has a non-string GitHub SHA-256 digest"
            )
        if isinstance(digest, str) and digest:
            if re.fullmatch(r"sha256:[0-9a-f]{64}", digest) is None:
                raise ReleaseError(
                    f"Asset {asset_name} has an invalid GitHub SHA-256 digest"
                )
            return digest.removeprefix("sha256:")
        download_url = asset.get("browser_download_url")
        if not isinstance(download_url, str) or not download_url:
            raise ReleaseError(f"Asset {asset_name} has no download URL")
        return sha256_url(
            download_url,
            context=release_asset_context(
                release, asset_name, "asset", repo=repo
            ),
        )
    tag = release.get("tag_name", "<unknown>")
    names = ", ".join(
        sorted(str(asset.get("name", "")) for asset in release_assets(release))
    )
    raise ReleaseError(
        f"Release {tag} does not contain required asset {asset_name}. "
        f"Available assets: {names}"
    )


def sha256_url(url: str, *, context: str) -> str:
    def hash_chunks(chunks: Iterator[bytes]) -> str:
        digest = hashlib.sha256()
        for chunk in chunks:
            digest.update(chunk)
        return digest.hexdigest()

    return read_release_url(
        url,
        context=context,
        headers=github_auth_header(),
        consume=hash_chunks,
    )


def normalize_release_tag(tag: str) -> str:
    if tag not in {"keep", "latest"}:
        parse_native_release_tag(tag)
    return tag


def parse_native_release_tag(tag: str) -> NativeReleaseVersion:
    stable_match = _STABLE_NATIVE_TAG_PATTERN.fullmatch(tag)
    if stable_match:
        version = tuple(int(value) for value in stable_match.groups())
        return NativeReleaseVersion("stable", version, 0, tag)

    stable_wrapper_match = _STABLE_WRAPPER_TAG_PATTERN.fullmatch(tag)
    if stable_wrapper_match:
        major, minor, patch, wrapper_revision = (
            int(value) for value in stable_wrapper_match.groups()
        )
        return NativeReleaseVersion(
            "stable",
            (major, minor, patch),
            wrapper_revision,
            f"v{major}.{minor}.{patch}",
        )

    legacy_match = _LEGACY_NATIVE_TAG_PATTERN.fullmatch(tag)
    if legacy_match:
        build = int(legacy_match.group(1))
        return NativeReleaseVersion("nightly", (build,), 0, tag)

    nightly_wrapper_match = _NIGHTLY_WRAPPER_TAG_PATTERN.fullmatch(tag)
    if nightly_wrapper_match:
        build = int(nightly_wrapper_match.group(1))
        wrapper_revision = int(nightly_wrapper_match.group(2))
        return NativeReleaseVersion(
            "nightly",
            (build,),
            wrapper_revision,
            f"b{nightly_wrapper_match.group(1)}",
        )

    wrapper_match = _LEGACY_WRAPPER_TAG_PATTERN.fullmatch(tag)
    if wrapper_match:
        build = int(wrapper_match.group(1))
        wrapper_revision = int(wrapper_match.group(2))
        return NativeReleaseVersion(
            "nightly",
            (build,),
            wrapper_revision,
            f"b{wrapper_match.group(1)}",
        )

    raise ReleaseError(
        f"Invalid llamadart-native release tag {tag!r}. Expected stable "
        "vMAJOR.MINOR.PATCH, stable wrapper rebuild "
        "vMAJOR.MINOR.PATCH-N, canonical historical/nightly bNNNN without "
        "leading zeros, nightly wrapper "
        "rebuild bNNNN-N, or legacy wrapper artifact bNNNN-llamadart.N."
    )


def read_hook_native_tag(pins_text: str) -> str:
    match = re.search(r"const llamaCppTag = '([^']+)';", pins_text)
    if not match:
        raise ReleaseError("Could not read pinned llama.cpp tag")
    tag = match.group(1)
    parse_native_release_tag(tag)
    return tag


def validate_resolved_native_release(
    release: dict[str, Any],
    *,
    requested_tag: str,
    current_tag: str,
    allow_legacy_tag: bool,
) -> str:
    resolved_tag = release.get("tag_name")
    if not isinstance(resolved_tag, str) or not resolved_tag:
        raise ReleaseError("Native release metadata has no non-empty tag_name")
    parse_native_release_tag(resolved_tag)

    if requested_tag == "latest":
        if _STABLE_NATIVE_TAG_PATTERN.fullmatch(resolved_tag) is None:
            raise ReleaseError(
                f"llamadart-native latest resolved to {resolved_tag}. "
                "Automatic discovery accepts only unsuffixed "
                "vMAJOR.MINOR.PATCH releases; select wrapper rebuilds and "
                "historical or nightly tags explicitly."
            )
    elif resolved_tag != requested_tag:
        raise ReleaseError(
            f"Requested llamadart-native tag {requested_tag}, but release "
            f"metadata resolved {resolved_tag}. Refusing version-skewed pins."
        )

    validate_native_release_transition(
        current_tag,
        resolved_tag,
        allow_legacy_tag=allow_legacy_tag,
    )
    return resolved_tag


def validate_native_release_transition(
    current_tag: str,
    target_tag: str,
    *,
    allow_legacy_tag: bool,
) -> None:
    current = parse_native_release_tag(current_tag)
    target = parse_native_release_tag(target_tag)
    if current_tag == target_tag:
        return

    if current.channel == "nightly" and target.channel == "stable":
        return

    if current.channel == "stable" and target.channel == "nightly":
        if allow_legacy_tag:
            return
        raise ReleaseError(
            f"Refusing stable-to-historical/nightly native channel switch "
            f"{current_tag} -> {target_tag}. Pass --allow-legacy-tag only for "
            "an intentional compatibility override."
        )

    current_key = native_release_order_key(current)
    target_key = native_release_order_key(target)
    if target_key == current_key:
        raise ReleaseError(
            f"Refusing equivalent native release sequence aliases "
            f"{current_tag} -> {target_tag}. Keep the current artifact or "
            "move to a higher wrapper revision."
        )
    if target_key < current_key:
        raise ReleaseError(
            f"Refusing native release rollback {current_tag} -> {target_tag}. "
            "Use a forward release and regenerate bindings for its exact "
            "header manifest."
        )


def native_release_order_key(version: NativeReleaseVersion) -> tuple[int, ...]:
    return (*version.version, version.wrapper_revision)


def find_release_asset(
    release: dict[str, Any], asset_name: str
) -> dict[str, Any] | None:
    for asset in release_assets(release):
        if asset.get("name") == asset_name:
            return asset
    return None


def release_assets(release: dict[str, Any]) -> list[dict[str, Any]]:
    assets = release.get("assets", [])
    if not isinstance(assets, list):
        raise ReleaseError("Native release metadata assets must be a list")
    names: set[str] = set()
    for index, asset in enumerate(assets):
        if not isinstance(asset, dict):
            raise ReleaseError(
                "Native release metadata asset list contains a non-object "
                f"entry at index {index}"
            )
        name = asset.get("name")
        if not isinstance(name, str) or not name:
            raise ReleaseError(
                f"Native release metadata asset at index {index} has no valid name"
            )
        if name in names:
            raise ReleaseError(f"Native release metadata duplicates asset {name}")
        names.add(name)
    return assets


def require_github_sha256_digest(
    asset: dict[str, Any], release_tag: str, asset_name: str
) -> str:
    digest = asset.get("digest")
    if not isinstance(digest, str) or re.fullmatch(
        r"sha256:[0-9a-f]{64}", digest
    ) is None:
        raise ReleaseError(
            f"Stable release {release_tag} does not publish a GitHub "
            f"SHA-256 digest for {asset_name}"
        )
    return digest.removeprefix("sha256:")


def release_asset_json(
    release: dict[str, Any], asset_name: str, *, repo: str = ""
) -> dict[str, Any]:
    asset = find_release_asset(release, asset_name)
    if asset is None:
        tag = release.get("tag_name", "<unknown>")
        raise ReleaseError(
            f"Release {tag} does not contain required asset {asset_name}"
        )

    if "fixture_json" in asset:
        fixture_json = asset["fixture_json"]
        if not isinstance(fixture_json, dict):
            raise ReleaseError(f"Release manifest {asset_name} must be a JSON object")
        return fixture_json

    download_url = asset.get("browser_download_url")
    if not isinstance(download_url, str) or not download_url:
        raise ReleaseError(f"Asset {asset_name} has no download URL")
    context = release_asset_context(release, asset_name, "manifest", repo=repo)
    raw = read_release_url(
        download_url, context=context, headers=github_auth_header()
    )
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError(f"{context}: invalid UTF-8 or JSON") from error
    if not isinstance(payload, dict):
        raise ReleaseError(f"Release manifest {asset_name} must be a JSON object")
    return payload


def release_asset_text(
    release: dict[str, Any], asset_name: str, *, repo: str = ""
) -> str:
    asset = find_release_asset(release, asset_name)
    if asset is None:
        tag = release.get("tag_name", "<unknown>")
        raise ReleaseError(
            f"Release {tag} does not contain required asset {asset_name}"
        )

    if "fixture_text" in asset:
        fixture_text = asset["fixture_text"]
        if not isinstance(fixture_text, str):
            raise ReleaseError(f"Release checksum file {asset_name} must be text")
        return fixture_text

    download_url = asset.get("browser_download_url")
    if not isinstance(download_url, str) or not download_url:
        raise ReleaseError(f"Asset {asset_name} has no download URL")
    context = release_asset_context(
        release, asset_name, "checksum file", repo=repo
    )
    raw = read_release_url(
        download_url, context=context, headers=github_auth_header()
    )
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ReleaseError(f"{context}: invalid UTF-8") from error


def release_asset_bytes(
    release: dict[str, Any],
    asset_name: str,
    *,
    repo: str,
    tag: str,
    release_json_dir: str,
) -> bytes:
    asset = find_release_asset(release, asset_name)
    if asset is None:
        raise ReleaseError(
            f"Release {tag} does not contain required asset {asset_name}"
        )
    context = f"Failed to read release asset {asset_name} ({repo}@{tag})"
    if release_json_dir:
        fixture = (
            Path(release_json_dir)
            / f"{repo.replace('/', '__')}__{tag}__{asset_name}"
        )
        return read_release_fixture(fixture, context)
    download_url = asset.get("browser_download_url")
    if not isinstance(download_url, str) or not download_url:
        raise ReleaseError(f"Asset {asset_name} has no download URL")
    return read_release_url(
        download_url, context=context, headers=github_auth_header()
    )


def parse_sha256_sums(checksum_text: str, release_tag: str) -> dict[str, str]:
    checksums: dict[str, str] = {}
    for line_number, line in enumerate(checksum_text.splitlines(), start=1):
        if not line.strip():
            continue
        match = re.fullmatch(r"([0-9a-f]{64})  (\S+)", line)
        if match is None:
            raise ReleaseError(
                f"Release {release_tag} SHA256SUMS has invalid line "
                f"{line_number}: {line!r}"
            )
        checksum, file_name = match.groups()
        if file_name in checksums:
            raise ReleaseError(
                f"Release {release_tag} SHA256SUMS duplicates {file_name}"
            )
        checksums[file_name] = checksum
    return checksums


def validate_native_release_manifest(
    release: dict[str, Any],
    release_tag: str,
    *,
    repo: str = DEFAULT_LLAMADART_NATIVE_REPO,
) -> NativeReleaseManifest:
    """Validate the release manifest.

    Returns its checksums by file name, its hook contract, and its backend
    sidecars. A legacy release without assets.json is contract 1.
    """
    release_version = parse_native_release_tag(release_tag)
    is_new_wrapper_form = bool(
        _STABLE_WRAPPER_TAG_PATTERN.fullmatch(release_tag)
        or _NIGHTLY_WRAPPER_TAG_PATTERN.fullmatch(release_tag)
    )
    manifest_asset = find_release_asset(release, "assets.json")
    if manifest_asset is None:
        if release_version.channel == "stable" or is_new_wrapper_form:
            raise ReleaseError(
                f"Release {release_tag} is missing required assets.json "
                "provenance and hook-contract metadata."
            )
        return NativeReleaseManifest({}, 1, ())
    if release_version.channel == "stable":
        require_github_sha256_digest(
            manifest_asset,
            release_tag,
            "assets.json",
        )

    manifest = release_asset_json(release, "assets.json", repo=repo)
    native_release_tag = manifest.get("native_release_tag")
    legacy_release_tag = manifest.get("tag")
    for field_name, value in (
        ("native_release_tag", native_release_tag),
        ("tag", legacy_release_tag),
    ):
        if value is not None and (not isinstance(value, str) or not value):
            raise ReleaseError(
                f"Release {release_tag} manifest has invalid {field_name}: "
                f"{value!r}"
            )
    if is_new_wrapper_form:
        missing_tag_fields = [
            field_name
            for field_name, value in (
                ("native_release_tag", native_release_tag),
                ("tag", legacy_release_tag),
            )
            if value is None
        ]
        if missing_tag_fields:
            raise ReleaseError(
                f"Release {release_tag} manifest is missing required "
                f"tag field(s): {', '.join(missing_tag_fields)}"
            )
    if native_release_tag is not None and legacy_release_tag is not None:
        if native_release_tag != legacy_release_tag:
            raise ReleaseError(
                f"Release {release_tag} manifest native_release_tag "
                f"{native_release_tag!r} disagrees with legacy tag alias "
                f"{legacy_release_tag!r}."
            )
    manifest_release_tag = (
        native_release_tag
        if native_release_tag is not None
        else legacy_release_tag
    )
    if manifest_release_tag != release_tag:
        raise ReleaseError(
            f"Release manifest tag {manifest_release_tag!r} does not match "
            f"release {release_tag}. Refusing version-skewed native assets."
        )

    hook_contract_version = manifest.get("hook_contract_version")
    if (
        not isinstance(hook_contract_version, int)
        or isinstance(hook_contract_version, bool)
        or hook_contract_version not in SUPPORTED_NATIVE_HOOK_CONTRACT_VERSIONS
    ):
        raise ReleaseError(
            f"Release {release_tag} requires native hook contract "
            f"{hook_contract_version!r}; this checkout supports "
            + " and ".join(map(str, SUPPORTED_NATIVE_HOOK_CONTRACT_VERSIONS))
            + "."
        )

    for field in ("llama_cpp_commit", "native_commit"):
        value = manifest.get(field)
        if not isinstance(value, str) or not _COMMIT_PATTERN.fullmatch(value):
            raise ReleaseError(
                f"Release {release_tag} manifest has invalid {field}: {value!r}"
            )

    llama_cpp_tag = manifest.get("llama_cpp_tag")
    llama_cpp_ref = manifest.get("llama_cpp_ref")
    if llama_cpp_tag is not None and llama_cpp_ref is not None:
        if llama_cpp_tag != llama_cpp_ref:
            raise ReleaseError(
                f"Release {release_tag} manifest llama_cpp_tag "
                f"{llama_cpp_tag!r} disagrees with llama_cpp_ref "
                f"{llama_cpp_ref!r}."
            )
    upstream_ref = llama_cpp_tag if llama_cpp_tag is not None else llama_cpp_ref
    if upstream_ref != release_version.upstream_tag:
        raise ReleaseError(
            f"Release {release_tag} manifest resolves llama.cpp tag "
            f"{upstream_ref!r}, expected {release_version.upstream_tag!r}. "
            "Refusing version-skewed native ABI metadata."
        )

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise ReleaseError(
            f"Release {release_tag} manifest artifacts must be a list"
        )

    manifest_checksums: dict[str, str] = {}
    sidecars: list[NativeBackendSidecar] = []
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise ReleaseError(
                f"Release {release_tag} manifest contains a non-object artifact"
            )
        file_name = artifact.get("file")
        checksum = artifact.get("sha256")
        if not isinstance(file_name, str) or not file_name:
            raise ReleaseError(
                f"Release {release_tag} manifest artifact has no file name"
            )
        if not isinstance(checksum, str) or not re.fullmatch(r"[0-9a-f]{64}", checksum):
            raise ReleaseError(
                f"Release {release_tag} manifest has invalid checksum for "
                f"{file_name}"
            )
        if file_name in manifest_checksums:
            raise ReleaseError(
                f"Release {release_tag} manifest duplicates artifact {file_name}"
            )
        manifest_checksums[file_name] = checksum
        sidecar = native_backend_sidecar(
            artifact,
            release_tag,
            hook_contract_version=hook_contract_version,
        )
        if sidecar is not None:
            if any(
                (other.bundle, other.backend) == (sidecar.bundle, sidecar.backend)
                for other in sidecars
            ):
                raise ReleaseError(
                    f"Release {release_tag} manifest lists more than one "
                    f"{sidecar.backend} sidecar for {sidecar.bundle}"
                )
            sidecars.append(sidecar)

        release_asset = find_release_asset(release, file_name)
        if release_asset is None:
            raise ReleaseError(
                f"Release {release_tag} manifest lists unavailable bundle "
                f"{file_name}"
            )
        digest = release_asset.get("digest") or ""
        if release_version.channel == "stable":
            digest = (
                "sha256:"
                + require_github_sha256_digest(
                    release_asset,
                    release_tag,
                    file_name,
                )
            )
        if (
            digest.startswith("sha256:")
            and digest.removeprefix("sha256:") != checksum
        ):
            raise ReleaseError(
                f"Release {release_tag} checksum mismatch for {file_name}: "
                "manifest and GitHub release metadata disagree."
            )

    if release_version.channel == "stable":
        required_assets = {
            *(
                f"llamadart-native-{bundle}-{release_tag}.tar.gz"
                for bundle in _STABLE_NATIVE_BUNDLES
            ),
            f"llamadart-native-apple-xcframework-{release_tag}.zip",
            f"llamadart-native-headers-{release_tag}.tar.gz",
        }
        missing = sorted(required_assets.difference(manifest_checksums))
        if missing:
            raise ReleaseError(
                f"Stable release {release_tag} manifest is missing required "
                f"bundle(s): {', '.join(missing)}"
            )
        checksum_asset = find_release_asset(release, "SHA256SUMS")
        if checksum_asset is None:
            raise ReleaseError(
                f"Stable release {release_tag} is missing required SHA256SUMS"
            )
        require_github_sha256_digest(
            checksum_asset,
            release_tag,
            "SHA256SUMS",
        )
        published_checksums = parse_sha256_sums(
            release_asset_text(release, "SHA256SUMS", repo=repo),
            release_tag,
        )
        for file_name, checksum in manifest_checksums.items():
            published_checksum = published_checksums.get(file_name)
            if published_checksum != checksum:
                raise ReleaseError(
                    f"Stable release {release_tag} SHA256SUMS checksum for "
                    f"{file_name} is {published_checksum!r}, expected "
                    f"{checksum!r} from assets.json"
                )
    return NativeReleaseManifest(
        manifest_checksums,
        hook_contract_version,
        tuple(sidecars),
    )


def native_backend_sidecar(
    artifact: dict[str, Any],
    release_tag: str,
    *,
    hook_contract_version: int,
) -> NativeBackendSidecar | None:
    """Return the backend sidecar [artifact] describes, or None for others."""
    module = artifact.get("module")
    if not isinstance(module, str) or not module.startswith("backend-"):
        return None
    file_name = artifact["file"]
    if hook_contract_version < 2:
        raise ReleaseError(
            f"Release {release_tag} manifest lists backend sidecar {file_name} "
            f"under hook contract {hook_contract_version}, which has none."
        )
    fields = {}
    for field in ("platform", "arch", "backend"):
        value = artifact.get(field)
        if not isinstance(value, str) or not value:
            raise ReleaseError(
                f"Release {release_tag} manifest sidecar {file_name} has "
                f"invalid {field}: {value!r}"
            )
        fields[field] = value
    bundle = f"{fields['platform']}-{fields['arch']}"
    if bundle not in _STABLE_NATIVE_BUNDLES:
        raise ReleaseError(
            f"Release {release_tag} manifest sidecar {file_name} extends "
            f"unknown bundle {bundle}"
        )
    prefix = f"llamadart-native-{bundle}-"
    suffix = f"-{release_tag}.tar.gz"
    variant = (
        file_name[len(prefix) : -len(suffix)]
        if file_name.startswith(prefix) and file_name.endswith(suffix)
        else ""
    )
    archive = f"{bundle}-{variant}"
    if not variant or not _BACKEND_SIDECAR_ARCHIVE_PATTERN.fullmatch(archive):
        raise ReleaseError(
            f"Release {release_tag} manifest sidecar {file_name} is not named "
            f"{prefix}<variant>{suffix}"
        )
    return NativeBackendSidecar(bundle, fields["backend"], archive)


def normalize_litert_lm_release_tag(tag: str) -> str:
    tag = tag.strip()
    if not tag:
        return "keep"
    if tag in {"keep", "latest"}:
        return tag
    if (
        STABLE_LITERT_TAG_RE.fullmatch(tag)
        or STABLE_LITERT_REBUILD_RE.fullmatch(tag)
        or DEVELOPMENT_LITERT_TAG_RE.fullmatch(tag)
        or LEGACY_LITERT_TAG_RE.fullmatch(tag)
    ):
        return tag
    prefixed_tag = f"v{tag}"
    if (
        STABLE_LITERT_TAG_RE.fullmatch(prefixed_tag)
        or STABLE_LITERT_REBUILD_RE.fullmatch(prefixed_tag)
        or LEGACY_LITERT_TAG_RE.fullmatch(prefixed_tag)
    ):
        return prefixed_tag
    raise ReleaseError(
        "Invalid LiteRT-LM native tag. Expected vMAJOR.MINOR.PATCH, "
        "vMAJOR.MINOR.PATCH-N, g<12hex>, g<12hex>-N, or legacy "
        "vMAJOR.MINOR.PATCH-native.N."
    )


def current_litert_lm_release_tag(pins_text: str) -> str:
    release_match = re.search(
        r"const liteRtLmReleaseTag = '([^']+)';", pins_text
    )
    if release_match is not None:
        return release_match.group(1)
    match = re.search(r"const liteRtLmVersion = '([^']+)';", pins_text)
    if match is None:
        raise ReleaseError(
            f"Could not find current LiteRT-LM version in {DEFAULT_NATIVE_RELEASE_PINS}"
        )
    version = match.group(1)
    return version if version.startswith("g") else f"v{version}"


def litert_lm_runtime_version(release_tag: str) -> str:
    """Return the cache/runtime version without altering commit release tags."""
    return release_tag.removeprefix("v")


def validate_litert_lm_transition(
    current: str,
    target: str,
    *,
    allow_channel_transition: bool = False,
    allow_development_line_transition: bool = False,
    allow_stable_rebuild_entry: bool = False,
) -> None:
    if current == target:
        return
    current_development = DEVELOPMENT_LITERT_TAG_RE.fullmatch(current)
    target_development = DEVELOPMENT_LITERT_TAG_RE.fullmatch(target)
    if current_development or target_development:
        if bool(current_development) != bool(target_development):
            if not allow_channel_transition:
                raise ReleaseError(
                    "LiteRT-LM stable/development transition requires explicit "
                    "owner-ancestry approval"
                )
            target_rebuild = (
                development_release_order(target)[1]
                if target_development
                else stable_release_order(target)[1]
            )
            if target_rebuild != 0:
                raise ReleaseError(
                    "LiteRT-LM channel transition must enter the target line at its base"
                )
            return
        if current_development and target_development:
            current_base, current_rebuild = development_release_order(current)
            target_base, target_rebuild = development_release_order(target)
            if (
                current_base != target_base
                and not allow_development_line_transition
            ):
                raise ReleaseError(
                    "LiteRT-LM development line transition requires explicit "
                    "owner-ancestry approval"
                )
            if current_base != target_base:
                if target_rebuild != 0:
                    raise ReleaseError(
                        "LiteRT-LM development line transition must enter at its base"
                    )
                return
            if target_rebuild < current_rebuild:
                raise ReleaseError(
                    f"LiteRT-LM development rebuild rollback: {current} -> {target}"
                )
            if target_rebuild != current_rebuild + 1:
                raise ReleaseError(
                    "LiteRT-LM development rebuild must use the immediate next ordinal"
                )
        return

    current_version, current_rebuild = stable_release_order(current)
    target_version, target_rebuild = stable_release_order(target)
    if (
        target_version == current_version
        and target_rebuild == current_rebuild
        and target != current
    ):
        raise ReleaseError(
            f"LiteRT-LM ordinal alias is forbidden: {current} and {target} "
            "identify the same rebuild"
        )
    if target_version < current_version or (
        target_version == current_version and target_rebuild < current_rebuild
    ):
        raise ReleaseError(f"LiteRT-LM release rollback: {current} -> {target}")
    if target_version > current_version:
        if target_rebuild != 0 and not allow_stable_rebuild_entry:
            raise ReleaseError(
                "LiteRT-LM stable transition must enter the target line at its base"
            )
        return
    if target_rebuild != current_rebuild + 1:
        raise ReleaseError(
            "LiteRT-LM stable rebuild must use the immediate next ordinal"
        )


def stable_release_order(tag: str) -> tuple[tuple[int, int, int], int]:
    legacy = LEGACY_LITERT_TAG_RE.fullmatch(tag)
    compact = STABLE_LITERT_REBUILD_RE.fullmatch(tag)
    stable = STABLE_LITERT_TAG_RE.fullmatch(tag)
    if legacy:
        version_text, rebuild_text = tag[1:].rsplit("-native.", 1)
    elif compact:
        version_text, rebuild_text = tag[1:].rsplit("-", 1)
    elif stable:
        version_text, rebuild_text = tag[1:], "0"
    else:
        raise ReleaseError(f"Cannot order invalid LiteRT-LM release tag {tag}")
    return tuple(int(part) for part in version_text.split(".")), int(rebuild_text)


def development_release_order(tag: str) -> tuple[str, int]:
    if not DEVELOPMENT_LITERT_TAG_RE.fullmatch(tag):
        raise ReleaseError(f"Cannot order invalid LiteRT-LM development tag {tag}")
    parts = tag.rsplit("-", 1)
    return parts[0], int(parts[1]) if len(parts) == 2 else 0


def validate_litert_lm_release_manifest(
    release: dict[str, Any],
    *,
    repo: str,
    tag: str,
    release_json_dir: str,
    required_bundles: list[str],
) -> dict[str, Any]:
    manifest_result = fetch_litert_lm_release_manifest(
        release,
        repo=repo,
        tag=tag,
        release_json_dir=release_json_dir,
    )
    if manifest_result is None:
        raise ReleaseError(
            f"Release {repo}@{tag} has no immutable manifest.json evidence"
        )
    manifest, manifest_digest = manifest_result
    release_manifest_digest = release_asset_checksum(
        release, "manifest.json", repo=repo
    )
    if release_manifest_digest != manifest_digest:
        raise ReleaseError(
            "LiteRT-LM manifest bytes do not match the GitHub release digest"
        )

    schema = manifest.get("schemaVersion")
    release_identity = manifest.get("release")
    if not isinstance(release_identity, dict) or release_identity.get("tag") != tag:
        raise ReleaseError(f"Release manifest tag does not match {tag}")
    if schema == 1:
        legacy_identity = LEGACY_SCHEMA1_RELEASES.get(tag)
        if legacy_identity is None:
            raise ReleaseError(
                f"Release {repo}@{tag} must use LiteRT-LM manifest schema 2"
            )
        expected_assets = legacy_identity.get("assets")
        if not isinstance(expected_assets, dict):
            raise ReleaseError("Legacy release allowlist has invalid asset evidence")
        expected_manifest_asset_digest = expected_assets.get("manifest.json")
        if not isinstance(expected_manifest_asset_digest, str) or not expected_manifest_asset_digest.startswith("sha256:"):
            raise ReleaseError("Legacy release allowlist has no manifest digest")
        expected_manifest_digest = expected_manifest_asset_digest.removeprefix(
            "sha256:"
        )
        expected_tag_commit = legacy_identity.get("tagCommit")
        if manifest_digest != expected_manifest_digest:
            raise ReleaseError(
                f"Legacy release {repo}@{tag} manifest digest is not immutable allowlist evidence"
            )
        if fetch_tag_commit(repo, tag, release_json_dir, release) != expected_tag_commit:
            raise ReleaseError(
                f"Legacy release {repo}@{tag} tag commit is not immutable allowlist evidence"
            )
        release_assets_value = release.get("assets")
        if not isinstance(release_assets_value, list):
            raise ReleaseError(
                f"Legacy release {repo}@{tag} asset inventory is invalid"
            )
        actual_assets: dict[str, str] = {}
        for asset in release_assets_value:
            if not isinstance(asset, dict):
                raise ReleaseError(
                    f"Legacy release {repo}@{tag} asset inventory is invalid"
                )
            name = require_string(asset.get("name"), "legacy release asset name")
            digest = require_string(
                asset.get("digest"), "legacy release asset digest"
            )
            if name in actual_assets:
                raise ReleaseError(
                    f"Legacy release {repo}@{tag} asset inventory has duplicates"
                )
            actual_assets[name] = digest
        if actual_assets != expected_assets:
            raise ReleaseError(
                f"Legacy release {repo}@{tag} asset digests are not immutable allowlist evidence"
            )
        missing_legacy_bundles = sorted(
            bundle
            for bundle in LEGACY_SCHEMA1_LITERT_PLATFORM_BUNDLES
            if f"litert-lm-native-runtime-{bundle}-{tag}.tar.gz" not in actual_assets
        )
        if missing_legacy_bundles:
            raise ReleaseError(
                f"Legacy release {repo}@{tag} does not cover the schema-1 "
                "nine-platform contract; missing "
                + ", ".join(missing_legacy_bundles)
            )
        if release.get("draft", False) != legacy_identity.get("draft") or release.get(
            "prerelease", False
        ) != legacy_identity.get("prerelease"):
            raise ReleaseError(
                f"Legacy release {repo}@{tag} classification is not immutable allowlist evidence"
            )
        return manifest
    if schema != 2:
        raise ReleaseError(f"Unsupported LiteRT-LM manifest schemaVersion {schema}")

    require_exact_keys(
        manifest,
        {
            "schemaVersion",
            "package",
            "release",
            "upstream",
            "native",
            "abi",
            "capabilities",
            "platforms",
            "artifacts",
            "realModelSmokes",
        },
        "manifest",
    )
    if manifest.get("package") != "litert-lm-native":
        raise ReleaseError("LiteRT-LM manifest has an unexpected package identity")

    upstream = manifest.get("upstream")
    native = manifest.get("native")
    if not isinstance(upstream, dict):
        raise ReleaseError("LiteRT-LM manifest is missing an exact upstream commit")
    if not isinstance(native, dict):
        raise ReleaseError("LiteRT-LM manifest is missing an exact native commit")
    upstream_repository = require_string(
        upstream.get("repository"), "upstream repository"
    )
    upstream_commit = require_full_commit(
        upstream.get("commit"), "upstream commit"
    )
    native_repository = require_string(native.get("repository"), "native repository")
    native_commit = require_full_commit(native.get("commit"), "native commit")
    if upstream_repository != "google-ai-edge/LiteRT-LM":
        raise ReleaseError("LiteRT-LM manifest has an unexpected upstream repository")
    if native_repository != repo:
        raise ReleaseError("LiteRT-LM manifest has an unexpected native repository")
    release_target = require_full_commit(
        release.get("target_commitish"), "release target commit"
    )
    if release_target != native_commit:
        raise ReleaseError("LiteRT-LM release target does not match native commit")
    resolved_native_commit = fetch_ref_commit(
        native_repository,
        tag,
        release_json_dir,
        release,
    )
    if resolved_native_commit != native_commit:
        raise ReleaseError(
            "LiteRT-LM manifest native commit does not match the exact native tag"
        )

    stable_rebuild = STABLE_LITERT_REBUILD_RE.fullmatch(tag)
    development = DEVELOPMENT_LITERT_TAG_RE.fullmatch(tag)
    expected_rebuild = int(tag.rsplit("-", 1)[1]) if stable_rebuild else 0
    if development:
        development_parts = tag.rsplit("-", 1)
        expected_rebuild = (
            int(development_parts[1]) if len(development_parts) == 2 else 0
        )
        expected_base = f"g{upstream_commit[:12]}"
        if tag != expected_base and not tag.startswith(f"{expected_base}-"):
            raise ReleaseError(
                f"Development release {tag} does not match upstream commit {upstream['commit']}"
            )
        if upstream.get("tag") is not None:
            raise ReleaseError("Development release must not claim a stable upstream tag")
        if upstream.get("developmentIdentity") != expected_base:
            raise ReleaseError("Development identity does not match upstream commit")
        resolved_upstream_commit = fetch_ref_commit(
            upstream_repository,
            upstream_commit,
            release_json_dir,
        )
        expected_channel = "development"
        expected_kind = "rebuild" if expected_rebuild > 0 else "commit"
    else:
        expected_upstream_tag = (
            tag.rsplit("-", 1)[0] if stable_rebuild else tag
        )
        upstream_tag = require_string(upstream.get("tag"), "upstream tag")
        if upstream_tag != expected_upstream_tag:
            raise ReleaseError(
                f"Stable release {tag} must use upstream tag {expected_upstream_tag}"
            )
        if upstream.get("compatibilityTag") != expected_upstream_tag:
            raise ReleaseError("Stable compatibility tag must equal its upstream tag")
        resolved_upstream_commit = fetch_ref_commit(
            upstream_repository,
            expected_upstream_tag,
            release_json_dir,
        )
        expected_channel = "stable"
        expected_kind = "rebuild" if expected_rebuild > 0 else "upstream"

    if resolved_upstream_commit != upstream_commit:
        raise ReleaseError(
            "LiteRT-LM manifest upstream commit does not match the exact upstream ref"
        )

    compatibility_tag = require_string(
        upstream.get("compatibilityTag"), "compatibility tag"
    )
    if not STABLE_LITERT_TAG_RE.fullmatch(compatibility_tag):
        raise ReleaseError("LiteRT-LM manifest has an invalid compatibility tag")
    expected_prerelease = development is not None or expected_rebuild > 0
    expected_release_fields = {
        "channel": expected_channel,
        "kind": expected_kind,
        "rebuild": expected_rebuild,
        "githubPrerelease": expected_prerelease,
    }
    require_exact_keys(
        release_identity,
        {"tag", *expected_release_fields.keys()},
        "release identity",
    )
    require_string(release_identity.get("tag"), "release identity tag")
    require_string(release_identity.get("channel"), "release identity channel")
    require_string(release_identity.get("kind"), "release identity kind")
    require_int(release_identity.get("rebuild"), "release identity rebuild", minimum=0)
    if type(release_identity.get("githubPrerelease")) is not bool:
        raise ReleaseError(
            "LiteRT-LM release identity githubPrerelease must be a boolean"
        )
    require_exact_keys(
        upstream,
        {
            "repository",
            "tag",
            "commit",
            "compatibilityTag",
            "developmentIdentity",
            "prebuiltOverrides",
        } | ({"sourcePatches"} if "sourcePatches" in upstream else set()),
        "upstream provenance",
    )
    if "sourcePatches" in upstream:
        source_patches = upstream["sourcePatches"]
        if not isinstance(source_patches, list) or not source_patches:
            raise ReleaseError(
                "LiteRT-LM upstream sourcePatches must be a non-empty list"
            )
        for index, source_patch in enumerate(source_patches):
            label = f"upstream sourcePatches[{index}]"
            require_exact_keys(
                source_patch,
                {
                    "id", "path", "sha256", "source",
                    "preimageSha256Lf", "postimageSha256Lf", "scope",
                },
                label,
            )
            for field in ("id", "path", "source", "scope"):
                require_string(source_patch[field], f"{label} {field}")
            for field in ("sha256", "preimageSha256Lf", "postimageSha256Lf"):
                require_sha256(source_patch[field], f"{label} {field}")
    require_exact_keys(native, {"repository", "commit"}, "native provenance")
    if not isinstance(upstream.get("prebuiltOverrides"), list):
        raise ReleaseError("LiteRT-LM manifest prebuiltOverrides must be a list")
    if upstream.get("developmentIdentity") != f"g{upstream_commit[:12]}":
        raise ReleaseError("LiteRT-LM development identity does not match upstream commit")
    for override in upstream["prebuiltOverrides"]:
        if not isinstance(override, dict):
            raise ReleaseError("LiteRT-LM prebuilt override provenance is invalid")
        require_exact_keys(
            override,
            {
                "sourceRepository",
                "sourceCommit",
                "sourcePath",
                "targetPath",
                "sha256",
            },
            "prebuilt override provenance",
        )
        source_repository = require_string(
            override.get("sourceRepository"), "prebuilt override source repository"
        )
        require_full_commit(
            override.get("sourceCommit"), "prebuilt override source commit"
        )
        require_string(override.get("sourcePath"), "prebuilt override source path")
        require_string(override.get("targetPath"), "prebuilt override target path")
        require_sha256(override.get("sha256"), "prebuilt override digest")
        if source_repository != "google-ai-edge/LiteRT-LM":
            raise ReleaseError("LiteRT-LM prebuilt override provenance is invalid")
    expected_overrides = LITERT_PREBUILT_OVERRIDES.get(
        compatibility_tag, []
    )
    if upstream["prebuiltOverrides"] != expected_overrides:
        if compatibility_tag not in LITERT_PREBUILT_OVERRIDES:
            declared = ", ".join(
                sorted(
                    override["targetPath"]
                    for override in upstream["prebuiltOverrides"]
                )
            )
            raise ReleaseError(
                "LITERT_PREBUILT_OVERRIDES has no entry for upstream "
                f"{compatibility_tag}, but the manifest declares prebuilt "
                f"overrides for {declared}; mirror tools/prebuilt_overrides.py "
                "from leehack/litert-lm-native before syncing"
            )
        raise ReleaseError(
            "LiteRT-LM prebuilt override provenance does not match owner policy "
            f"for upstream {compatibility_tag}"
        )
    for name, expected in expected_release_fields.items():
        if release_identity.get(name) != expected:
            raise ReleaseError(
                f"LiteRT-LM manifest release {name} does not match {tag}"
            )
    if release.get("draft") is not False:
        raise ReleaseError("LiteRT-LM release must be published, not a draft")
    if release.get("prerelease") is not expected_prerelease:
        raise ReleaseError(
            "LiteRT-LM GitHub prerelease classification does not match manifest"
        )

    abi = manifest.get("abi")
    capabilities = manifest.get("capabilities")
    if isinstance(abi, dict):
        require_exact_keys(
            abi,
            {"upstreamC", "streamProxyCallback", "asrBridge"},
            "ABI declaration",
        )
    if isinstance(capabilities, dict):
        require_exact_keys(
            capabilities,
            {
                "textGeneration",
                "streaming",
                "streamChunkAccessors",
                "asr",
                "officialUpstreamAssets",
            },
            "capability declaration",
        )
    if not isinstance(abi, dict):
        raise ReleaseError("LiteRT-LM manifest does not declare required bridge ABIs")
    require_string(abi.get("upstreamC"), "ABI upstream header")
    stream_proxy_abi = require_int(
        abi.get("streamProxyCallback"), "stream proxy callback ABI", minimum=1
    )
    asr_bridge_abi = require_int(abi.get("asrBridge"), "ASR bridge ABI", minimum=1)
    # Historical owner manifests declared 1 even for modern runtimes
    # (leehack/litert-lm-native#107).
    # New-candidate declaration correctness belongs to the owner validator;
    # runtime admission still uses the library's independent ABI probes.
    allowed_callback_abis = (
        (1, 2) if _litert_compatibility_version(compatibility_tag) >= (0, 15, 0)
        else (1,)
    )
    if stream_proxy_abi not in allowed_callback_abis:
        raise ReleaseError(
            f"LiteRT-LM manifest has unsupported stream proxy callback ABI "
            f"{stream_proxy_abi} for {compatibility_tag}"
        )
    if (
        abi.get("upstreamC") != "c/engine.h"
        or asr_bridge_abi != 1
    ):
        raise ReleaseError("LiteRT-LM manifest does not declare required bridge ABIs")
    if not isinstance(capabilities, dict) or not all(
        capabilities.get(name) is True
        for name in ("textGeneration", "streaming", "streamChunkAccessors", "asr")
    ):
        raise ReleaseError("LiteRT-LM manifest lacks required generation capabilities")
    if development is None and capabilities.get("officialUpstreamAssets") is not True:
        raise ReleaseError("Stable LiteRT-LM release lacks official upstream assets")
    if development is not None and capabilities.get("officialUpstreamAssets") is not False:
        raise ReleaseError("Development LiteRT-LM release must not claim official assets")

    platforms = manifest.get("platforms")
    if not isinstance(platforms, list):
        raise ReleaseError("LiteRT-LM manifest platforms must be a list")
    required_platform_count = len(REQUIRED_LITERT_PLATFORM_BUNDLES)
    if len(platforms) != required_platform_count:
        raise ReleaseError(
            "LiteRT-LM manifest must contain exactly "
            f"{required_platform_count} finalized platform bundles; "
            f"found {len(platforms)}"
        )
    if any(not isinstance(item, dict) for item in platforms):
        raise ReleaseError("LiteRT-LM manifest contains an invalid platform")
    for item in platforms:
        require_string(item.get("platform"), "platform name")
        require_string(item.get("arch"), "platform architecture")
    manifest_bundle_list = [
        f"{item.get('platform')}-{item.get('arch')}"
        for item in platforms
    ]
    available_bundles = set(manifest_bundle_list)
    expected_bundles = set(required_bundles)
    if expected_bundles != REQUIRED_LITERT_PLATFORM_BUNDLES:
        raise ReleaseError(
            "llamadart hook bundle inventory does not cover the finalized "
            f"{required_platform_count}-platform schema-2 contract"
        )
    missing_bundles = sorted(expected_bundles - available_bundles)
    unexpected_bundles = sorted(available_bundles - expected_bundles)
    duplicate_bundles = sorted(
        bundle
        for bundle in available_bundles
        if manifest_bundle_list.count(bundle) > 1
    )
    if missing_bundles or unexpected_bundles or duplicate_bundles:
        details = []
        if missing_bundles:
            details.append("missing " + ", ".join(missing_bundles))
        if unexpected_bundles:
            details.append("unexpected " + ", ".join(unexpected_bundles))
        if duplicate_bundles:
            details.append("duplicates " + ", ".join(duplicate_bundles))
        raise ReleaseError(
            "LiteRT-LM finalized platform bundle inventory mismatch: "
            + "; ".join(details)
        )

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ReleaseError("LiteRT-LM manifest contains no artifacts")
    artifacts_by_path: dict[str, dict[str, Any]] = {}
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise ReleaseError("LiteRT-LM manifest contains an invalid artifact")
        require_exact_keys(
            artifact,
            {
                "runtime",
                "platform",
                "arch",
                "path",
                "fileName",
                "sha256",
                "upstreamTag",
                "upstreamCommit",
                "releaseTag",
                "accelerators",
            },
            "artifact provenance",
        )
        require_sha256(artifact.get("sha256"), "artifact digest")
        runtime = require_string(artifact.get("runtime"), "artifact runtime")
        require_string(artifact.get("fileName"), "artifact file name")
        require_string(artifact.get("releaseTag"), "artifact release tag")
        require_full_commit(
            artifact.get("upstreamCommit"), "artifact upstream commit"
        )
        artifact_platform = artifact.get("platform")
        artifact_arch = artifact.get("arch")
        if artifact_platform is not None:
            require_string(artifact_platform, "artifact platform")
        if artifact_arch is not None:
            require_string(artifact_arch, "artifact architecture")
        artifact_upstream_tag = artifact.get("upstreamTag")
        if artifact_upstream_tag is not None:
            require_string(artifact_upstream_tag, "artifact upstream tag")
        if artifact.get("releaseTag") != tag:
            raise ReleaseError("LiteRT-LM artifact releaseTag does not match release")
        if artifact.get("upstreamCommit") != upstream["commit"]:
            raise ReleaseError("LiteRT-LM artifact upstream commit does not match manifest")
        if artifact.get("upstreamTag") != upstream.get("tag"):
            raise ReleaseError("LiteRT-LM artifact upstream tag does not match manifest")
        artifact_path = artifact.get("path")
        if (
            not isinstance(artifact_path, str)
            or not artifact_path
            or artifact_path == "."
            or "\\" in artifact_path
            or Path(artifact_path).is_absolute()
            or ".." in Path(artifact_path).parts
            or Path(artifact_path).as_posix() != artifact_path
        ):
            raise ReleaseError("LiteRT-LM manifest contains an invalid artifact path")
        if artifact.get("fileName") != Path(artifact_path).name:
            raise ReleaseError("LiteRT-LM artifact fileName does not match path")
        if runtime not in {"native", "archive", "web"}:
            raise ReleaseError("LiteRT-LM artifact has an invalid runtime family")
        accelerators = artifact.get("accelerators")
        if (
            not isinstance(accelerators, list)
            or any(not isinstance(value, str) or not value for value in accelerators)
            or len(accelerators) != len(set(accelerators))
            or not set(accelerators).issubset(LITERT_ALLOWED_ACCELERATORS)
        ):
            raise ReleaseError("LiteRT-LM artifact accelerators are invalid")
        if artifact_path in artifacts_by_path:
            raise ReleaseError("LiteRT-LM manifest contains duplicate artifact paths")
        artifacts_by_path[artifact_path] = artifact

    validate_litert_spm_artifact_inventory(
        set(artifacts_by_path),
        compatibility_tag=compatibility_tag,
        release_tag=tag,
    )

    for override in expected_overrides:
        target = artifacts_by_path.get(override["targetPath"])
        if (
            target is None
            or target.get("runtime") != "native"
            or target.get("sha256") != override["sha256"]
        ):
            raise ReleaseError(
                "LiteRT-LM prebuilt override target provenance does not match owner policy"
            )

    covered_native_paths: set[str] = set()
    for platform in platforms:
        require_exact_keys(
            platform,
            {"platform", "arch", "releaseAsset", "artifactPaths", "accelerators"},
            "platform declaration",
        )
        platform_name = require_string(platform.get("platform"), "platform name")
        platform_arch = require_string(
            platform.get("arch"), "platform architecture"
        )
        require_string(platform.get("releaseAsset"), "platform release asset")
        paths = platform.get("artifactPaths")
        if (
            not isinstance(paths, list)
            or not paths
            or any(not isinstance(path, str) or not path for path in paths)
            or len(paths) != len(set(paths))
        ):
            raise ReleaseError("LiteRT-LM platform artifact paths are invalid")
        if any(path not in artifacts_by_path for path in paths):
            raise ReleaseError("LiteRT-LM platform references an unknown artifact path")
        if any(
            artifacts_by_path[path].get("platform") != platform_name
            or artifacts_by_path[path].get("arch") != platform_arch
            for path in paths
        ):
            raise ReleaseError("LiteRT-LM platform artifact provenance does not match")
        if any(artifacts_by_path[path].get("runtime") != "native" for path in paths):
            raise ReleaseError("LiteRT-LM platform may reference only native artifacts")
        covered_native_paths.update(paths)
        accelerators = platform.get("accelerators")
        if (
            not isinstance(accelerators, list)
            or any(
                not isinstance(accelerator, str) or not accelerator
                for accelerator in accelerators
            )
            or len(accelerators) != len(set(accelerators))
        ):
            raise ReleaseError("LiteRT-LM platform accelerators are invalid")
        linked_accelerators = sorted(
            {
                accelerator
                for path in paths
                for accelerator in artifacts_by_path[path]["accelerators"]
            }
        )
        if accelerators != linked_accelerators or not set(accelerators).issubset(
            LITERT_ALLOWED_ACCELERATORS
        ):
            raise ReleaseError(
                "LiteRT-LM platform accelerators do not match linked artifacts"
            )
        expected_release_asset = (
            "litert-lm-native-runtime-"
            f"{platform_name}-{platform_arch}-{tag}.tar.gz"
        )
        if platform.get("releaseAsset") != expected_release_asset:
            raise ReleaseError("LiteRT-LM platform release asset does not match identity")

    native_paths = {
        path
        for path, artifact in artifacts_by_path.items()
        if artifact.get("runtime") == "native"
    }
    if covered_native_paths != native_paths:
        raise ReleaseError("LiteRT-LM manifest has unbound native artifact provenance")
    required_paths = required_litert_manifest_paths(
        compatibility_tag,
        tag,
        official_assets=capabilities["officialUpstreamAssets"] is True,
    )
    missing_paths = sorted(required_paths - set(artifacts_by_path))
    if missing_paths:
        raise ReleaseError(
            "LiteRT-LM manifest is missing owner-required artifact paths: "
            + ", ".join(missing_paths)
        )
    platform_paths = {
        (platform["platform"], platform["arch"]): set(platform["artifactPaths"])
        for platform in platforms
    }
    for path in sorted(required_paths):
        artifact = artifacts_by_path[path]
        parts = Path(path).parts
        if parts[0] == "bin":
            expected_platform, expected_arch = parts[1:3]
            if (
                artifact.get("runtime") != "native"
                or artifact.get("platform") != expected_platform
                or artifact.get("arch") != expected_arch
                or path not in platform_paths[(expected_platform, expected_arch)]
            ):
                raise ReleaseError(
                    "LiteRT-LM required runtime path has invalid platform binding"
                )
        elif (
            artifact.get("runtime") != "archive"
            or artifact.get("platform") is not None
            or artifact.get("arch") is not None
        ):
            raise ReleaseError(
                "LiteRT-LM required archive path has invalid platform binding"
            )

    validate_litert_release_asset_inventory(release, manifest, tag)

    passed_smokes: set[str] = set()
    smokes = manifest.get("realModelSmokes")
    if not isinstance(smokes, list):
        raise ReleaseError("LiteRT-LM realModelSmokes must be a list")
    smoke_identities: set[tuple[str, str, str]] = set()
    for item in smokes:
        if not isinstance(item, dict):
            raise ReleaseError("LiteRT-LM smoke must be an object")
        require_exact_keys(
            item,
            {
                "id",
                "result",
                "platform",
                "arch",
                "backend",
                "upstreamCommit",
                "nativeCommit",
                "abiVersion",
                "library",
                "model",
                "tokenizer",
                "fixture",
                "source",
                "expectation",
                "transcript",
            },
            "real-model smoke",
        )
        if item.get("result") != "pass":
            raise ReleaseError("LiteRT-LM smoke is not a pass")
        if item.get("upstreamCommit") != upstream["commit"]:
            raise ReleaseError("LiteRT-LM smoke upstream commit does not match manifest")
        if item.get("nativeCommit") != native["commit"]:
            raise ReleaseError("LiteRT-LM smoke native commit does not match manifest")
        if item.get("id") != "litert_lm_asr_moonshine":
            raise ReleaseError("LiteRT-LM smoke has an unexpected identity")
        require_string(item.get("backend"), "smoke backend")
        smoke_abi_version = require_int(
            item.get("abiVersion"), "smoke ABI version", minimum=1
        )
        if item.get("backend") != "cpu" or smoke_abi_version != 1:
            raise ReleaseError("LiteRT-LM smoke has invalid backend or ABI evidence")
        if not isinstance(item.get("transcript"), str) or not item["transcript"].strip():
            raise ReleaseError("LiteRT-LM smoke has no transcript evidence")
        for field, expected_keys in (
            ("library", {"fileName", "sha256"}),
            ("model", {"fileName", "sha256"}),
            ("tokenizer", {"fileName", "sha256"}),
            ("fixture", {"fileName", "sha256", "sampleRateHz", "sampleCount"}),
        ):
            payload = item.get(field)
            if not isinstance(payload, dict):
                raise ReleaseError(f"LiteRT-LM smoke has invalid {field} evidence")
            require_exact_keys(payload, expected_keys, f"smoke {field}")
            if not isinstance(payload.get("fileName"), str) or not payload["fileName"]:
                raise ReleaseError(f"LiteRT-LM smoke has an invalid {field} digest")
            require_sha256(payload.get("sha256"), f"smoke {field} digest")
        fixture = item["fixture"]
        sample_rate = require_int(
            fixture.get("sampleRateHz"), "smoke fixture sample rate", minimum=1
        )
        sample_count = require_int(
            fixture.get("sampleCount"), "smoke fixture sample count", minimum=1
        )
        if sample_rate != 16000 or sample_count <= 0:
            raise ReleaseError("LiteRT-LM smoke has invalid fixture metadata")
        for field, pinned in LITERT_SMOKE_ASSETS.items():
            payload = item[field]
            if (
                payload.get("fileName") != pinned["fileName"]
                or payload.get("sha256") != pinned["sha256"]
            ):
                raise ReleaseError(
                    f"LiteRT-LM smoke {field} does not match the owner-pinned asset"
                )
        library = item["library"]
        matching_libraries = [
            artifact
            for artifact in artifacts_by_path.values()
            if artifact.get("runtime") == "native"
            and artifact.get("platform") == item.get("platform")
            and artifact.get("arch") == item.get("arch")
            and artifact.get("fileName") == library.get("fileName")
            and artifact.get("sha256") == library.get("sha256")
        ]
        if len(matching_libraries) != 1:
            raise ReleaseError(
                "LiteRT-LM smoke library does not match one packaged runtime artifact"
            )
        source = item.get("source")
        if not isinstance(source, dict):
            raise ReleaseError("LiteRT-LM smoke has no immutable source provenance")
        require_exact_keys(
            source,
            {"runtimeReleaseAsset", "model", "tokenizer", "fixture"},
            "smoke source provenance",
        )
        expected_runtime_asset = (
            "litert-lm-native-runtime-"
            f"{item.get('platform')}-{item.get('arch')}-{tag}.tar.gz"
        )
        if source.get("runtimeReleaseAsset") != expected_runtime_asset or any(
            source.get(field) != LITERT_SMOKE_ASSETS[field]["url"]
            for field in ("model", "tokenizer", "fixture")
        ):
            raise ReleaseError("LiteRT-LM smoke has invalid source provenance")
        expectation = item.get("expectation")
        if not isinstance(expectation, dict):
            raise ReleaseError("LiteRT-LM smoke has no transcript expectation")
        require_exact_keys(
            expectation,
            {"type", "value"},
            "smoke transcript expectation",
        )
        expectation_value = expectation.get("value")
        if expectation != {
            "type": "case-insensitive-substring",
            "value": "country",
        } or expectation_value.casefold() not in item["transcript"].casefold():
            raise ReleaseError(
                "LiteRT-LM smoke does not satisfy the owner-pinned transcript expectation"
            )
        identity = (
            require_string(item.get("id"), "smoke id"),
            require_string(item.get("platform"), "smoke platform"),
            require_string(item.get("arch"), "smoke architecture"),
        )
        if identity in smoke_identities:
            raise ReleaseError("LiteRT-LM smoke identity is duplicated")
        smoke_identities.add(identity)
        passed_smokes.add(f"{item.get('platform')}/{item.get('arch')}")
    required_smokes = {"linux/x64", "windows/x64"}
    if not required_smokes.issubset(passed_smokes):
        raise ReleaseError(
            "LiteRT-LM manifest is missing required real-model smoke evidence: "
            + ", ".join(sorted(required_smokes - passed_smokes))
        )
    validate_litert_release_sha256_sums(
        release,
        manifest,
        repo=repo,
        tag=tag,
        release_json_dir=release_json_dir,
    )
    validate_litert_spm_release_asset_digests(
        release,
        manifest,
        repo=repo,
        release_tag=tag,
    )
    return manifest


def fetch_litert_lm_release_manifest(
    release: dict[str, Any],
    *,
    repo: str,
    tag: str,
    release_json_dir: str,
) -> tuple[dict[str, Any], str] | None:
    manifest_asset = next(
        (
            asset
            for asset in release.get("assets", [])
            if isinstance(asset, dict) and asset.get("name") == "manifest.json"
        ),
        None,
    )
    if manifest_asset is None:
        return None
    context = f"Failed to read release manifest {repo}@{tag}"
    if release_json_dir:
        fixture = (
            Path(release_json_dir)
            / f"{repo.replace('/', '__')}__{tag}__manifest.json"
        )
        payload = read_release_fixture(fixture, context)
    else:
        url = manifest_asset.get("browser_download_url")
        if not isinstance(url, str) or not url:
            raise ReleaseError(f"Release {repo}@{tag} manifest has no download URL")
        payload = read_release_url(
            url, context=context, headers=github_auth_header()
        )
    try:
        manifest = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError(f"{context}: invalid UTF-8 or JSON") from error
    if not isinstance(manifest, dict):
        raise ReleaseError(f"Release {repo}@{tag} manifest is not a JSON object")
    return manifest, hashlib.sha256(payload).hexdigest()


def _native_pins_code_mask(source: str) -> str:
    """Mask comments and literal strings while retaining source offsets."""
    masked = list(source)
    cursor = 0
    while cursor < len(source):
        start = cursor
        if source.startswith("//", cursor):
            end = source.find("\n", cursor)
            cursor = len(source) if end < 0 else end
        elif source.startswith("/*", cursor):
            cursor += 2
            depth = 1
            while cursor < len(source) and depth:
                if source.startswith("/*", cursor):
                    depth += 1
                    cursor += 2
                elif source.startswith("*/", cursor):
                    depth -= 1
                    cursor += 2
                else:
                    cursor += 1
            if depth:
                raise ReleaseError("Unterminated comment in native pins")
        else:
            raw = source[cursor] in "rR" and source[cursor + 1:cursor + 2] in ("'", '"')
            quote_at = cursor + 1 if raw else cursor
            quote = source[quote_at:quote_at + 1]
            if quote not in ("'", '"'):
                cursor += 1
                continue
            delimiter = quote * 3 if source.startswith(quote * 3, quote_at) else quote
            cursor = quote_at + len(delimiter)
            while cursor < len(source):
                if source.startswith(delimiter, cursor):
                    cursor += len(delimiter)
                    break
                if not raw and source[cursor] == "\\":
                    cursor += 2
                    continue
                if not raw and source[cursor] == "$":
                    raise ReleaseError("Native pins require literal strings without interpolation")
                if len(delimiter) == 1 and source[cursor] in "\r\n":
                    raise ReleaseError("Unterminated string in native pins")
                cursor += 1
            else:
                raise ReleaseError("Unterminated string in native pins")
        for position in range(start, cursor):
            if source[position] not in "\r\n":
                masked[position] = " "
    return "".join(masked)


def refresh_stable_diffusion_apple_contract(
    source: str, current: str, target: str, checksum: str | None
) -> str:
    """Bind compatibility to one exact pin; same-tag refreshes retain proof."""
    pattern = r"^const stableDiffusionAppleCompanionChecksums = <String, String>\{(.*?)\};"
    flags = re.DOTALL | re.MULTILINE
    code = _native_pins_code_mask(source)
    matches = list(re.finditer(pattern, code, flags=flags))
    if not matches:
        raise ReleaseError("Missing Apple SD checksum contract")
    if len(matches) != 1:
        raise ReleaseError("Could not uniquely find Apple SD checksum contract")
    checksum_match = matches[0]
    body = source[checksum_match.start(1):checksum_match.end(1)]
    # Accept only the generated literal format, never examples in comments,
    # computed values or duplicate keys that a partial regex could hide.
    entry_pattern = r"'([^'\r\n]+)':\s*'([a-f0-9]{64})'\s*,"
    if re.fullmatch(r"(?:\s*" + entry_pattern + r")*\s*", body) is None:
        raise ReleaseError("Malformed Apple SD checksum contract; requalify the contract")
    entries = re.findall(entry_pattern, body)
    checksums = dict(entries)
    if len(checksums) != len(entries):
        raise ReleaseError("Malformed Apple SD checksum contract; duplicate tag")
    compatibility_pattern = r"^const stableDiffusionCompatibleAppleCompanionTags = <String, String>\{.*?\};"
    compatibility_matches = list(re.finditer(compatibility_pattern, code, flags=flags))
    if not compatibility_matches:
        raise ReleaseError("Missing Apple SD compatibility contract")
    if len(compatibility_matches) != 1:
        raise ReleaseError("Could not uniquely find Apple SD compatibility contract")
    if current == target:
        if checksum is not None and checksums.get(target) != checksum:
            raise ReleaseError("Same-tag Apple SD checksum changed; requalify the contract")
        return source
    entry = f"\n  '{target}': '{checksum}',\n" if checksum is not None else ""
    replacements = [
        (compatibility_matches[0], "const stableDiffusionCompatibleAppleCompanionTags = <String, String>{};"),
        (checksum_match, "const stableDiffusionAppleCompanionChecksums = <String, String>{" + entry + "};"),
    ]
    for match, replacement in sorted(replacements, key=lambda item: item[0].start(), reverse=True):
        source = source[:match.start()] + replacement + source[match.end():]
    return source


def normalize_stable_diffusion_release_tag(tag: str) -> str:
    if tag in {"keep", "latest"} or STABLE_DIFFUSION_TAG_RE.fullmatch(tag):
        return tag
    raise ReleaseError(
        f"Unsupported stable-diffusion-native tag {tag!r}; expected "
        "vX.Y.Z, vX.Y.Z-N, latest, or keep"
    )


def stable_diffusion_release_order(tag: str) -> tuple[int, int, int, int]:
    match = STABLE_DIFFUSION_TAG_RE.fullmatch(tag)
    if match is None:
        raise ReleaseError(f"Unsupported stable-diffusion-native tag {tag!r}")
    major, minor, patch, rebuild = match.groups()
    return int(major), int(minor), int(patch), int(rebuild or 0)


def current_stable_diffusion_release_tag(pins_text: str) -> str:
    match = re.search(r"const stableDiffusionReleaseTag = '([^']+)';", pins_text)
    if match is None:
        raise ReleaseError(
            f"Could not find stableDiffusionReleaseTag in {DEFAULT_NATIVE_RELEASE_PINS}"
        )
    return match.group(1)


def validate_stable_diffusion_transition(current: str, resolved: str) -> None:
    if stable_diffusion_release_order(resolved) < stable_diffusion_release_order(
        current
    ):
        raise ReleaseError(
            f"Refusing stable-diffusion-native rollback from {current} to {resolved}"
        )


def validate_stable_diffusion_release_manifest(
    release: dict[str, Any],
    *,
    repo: str,
    tag: str,
    release_json_dir: str,
) -> tuple[dict[str, tuple[str, str]], str | None]:
    """Map each runtime target to its (sha256, library) from manifest.json,
    and return the Apple XCFramework zip's SHA-256 (its SwiftPM checksum), or
    None when the release has none.

    Every archive digest must equal the GitHub digest of the release asset of
    the same name, so the manifest cannot vouch for bytes GitHub did not serve.
    """
    fetched = fetch_litert_lm_release_manifest(
        release, repo=repo, tag=tag, release_json_dir=release_json_dir
    )
    if fetched is None:
        raise ReleaseError(f"Release {repo}@{tag} has no manifest.json")
    manifest, manifest_sha256 = fetched
    manifest_asset = find_release_asset(release, "manifest.json")
    if require_github_sha256_digest(manifest_asset, tag, "manifest.json") != (
        manifest_sha256
    ):
        raise ReleaseError(
            f"Release {repo}@{tag} manifest.json does not match its GitHub digest"
        )
    if manifest.get("schemaVersion") != 1:
        raise ReleaseError(
            f"Release {repo}@{tag} manifest schemaVersion must be 1"
        )
    if manifest.get("package") != "stable-diffusion-native":
        raise ReleaseError(f"Release {repo}@{tag} manifest names another package")
    if manifest.get("tag") != tag:
        raise ReleaseError(f"Release {repo}@{tag} manifest names another tag")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise ReleaseError(f"Release {repo}@{tag} manifest artifacts must be a list")

    runtime: dict[str, tuple[str, str]] = {}
    xcframework_checksum: str | None = None
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise ReleaseError(f"Release {repo}@{tag} manifest has an invalid artifact")
        if artifact.get("kind") == "xcframework":
            if xcframework_checksum is not None:
                raise ReleaseError(
                    f"Release {repo}@{tag} manifest lists more than one XCFramework"
                )
            xcframework_checksum = validate_stable_diffusion_xcframework(
                artifact, release, repo=repo, tag=tag
            )
            continue
        if artifact.get("kind") != "runtime":
            continue
        target = artifact.get("target")
        if not isinstance(target, str) or (
            STABLE_DIFFUSION_TARGET_RE.fullmatch(target) is None
        ):
            raise ReleaseError(f"stable_diffusion target {target!r} is invalid")
        if target in runtime:
            raise ReleaseError(f"stable_diffusion target {target} is duplicated")
        file_name = f"stable-diffusion-native-runtime-{target}-{tag}.tar.gz"
        if artifact.get("file") != file_name:
            raise ReleaseError(
                f"stable_diffusion {target} artifact must be {file_name}"
            )
        checksum = artifact.get("sha256")
        if not isinstance(checksum, str) or SHA256_RE.fullmatch(checksum) is None:
            raise ReleaseError(f"stable_diffusion {target} sha256 is invalid")
        library = artifact.get("library")
        if not isinstance(library, str) or (
            SAFE_LITERT_LIBRARY_FILENAME_RE.fullmatch(library) is None
        ):
            raise ReleaseError(f"stable_diffusion {target} library name is invalid")
        asset = find_release_asset(release, file_name)
        if asset is None:
            raise ReleaseError(f"Release {repo}@{tag} does not contain {file_name}")
        if require_github_sha256_digest(asset, tag, file_name) != checksum:
            raise ReleaseError(
                f"stable_diffusion {file_name} manifest sha256 does not match "
                "its GitHub digest"
            )
        runtime[target] = (checksum, library)
    if not runtime:
        raise ReleaseError(f"Release {repo}@{tag} manifest lists no runtime archives")
    return runtime, xcframework_checksum


def validate_stable_diffusion_xcframework(
    artifact: dict[str, Any],
    release: dict[str, Any],
    *,
    repo: str,
    tag: str,
) -> str:
    file_name = f"stable-diffusion-native-apple-xcframework-{tag}.zip"
    if artifact.get("target") != "apple" or artifact.get("file") != file_name:
        raise ReleaseError(
            f"stable_diffusion XCFramework artifact must be apple/{file_name}"
        )
    checksum = artifact.get("sha256")
    if not isinstance(checksum, str) or SHA256_RE.fullmatch(checksum) is None:
        raise ReleaseError("stable_diffusion XCFramework sha256 is invalid")
    asset = find_release_asset(release, file_name)
    if asset is None:
        raise ReleaseError(f"Release {repo}@{tag} does not contain {file_name}")
    if require_github_sha256_digest(asset, tag, file_name) != checksum:
        raise ReleaseError(
            f"stable_diffusion {file_name} manifest sha256 does not match its "
            "GitHub digest"
        )
    return checksum


def stable_diffusion_bundle_names(pins_text: str) -> list[str]:
    bundles = re.findall(
        r"\bStableDiffusionBundleSpec\(\s*'([^']+)',\s*sha256: '[0-9a-f]+'",
        pins_text,
    )
    if not bundles:
        raise ReleaseError(
            "Could not find stable_diffusion bundle specs in "
            f"{DEFAULT_NATIVE_RELEASE_PINS}"
        )
    if len(bundles) != len(set(bundles)):
        raise ReleaseError(
            f"{DEFAULT_NATIVE_RELEASE_PINS} contains duplicate stable_diffusion "
            "bundle specs"
        )
    return bundles


def replace_stable_diffusion_bundle(
    pins_text: str,
    bundle: str,
    checksum: str,
    library: str,
) -> str:
    pattern = re.compile(
        rf"(\bStableDiffusionBundleSpec\(\s*'{re.escape(bundle)}',\s*sha256: ')"
        r"[0-9a-f]+(',\s*requiredLibraries: \{')[^']+('\},)"
    )
    updated, count = pattern.subn(
        lambda match: f"{match.group(1)}{checksum}{match.group(2)}{library}"
        f"{match.group(3)}",
        pins_text,
        count=1,
    )
    if count != 1:
        raise ReleaseError(f"Could not replace stable_diffusion pins for {bundle}")
    return updated


def fetch_ref_commit(
    repo: str,
    ref: str,
    release_json_dir: str,
    release: dict[str, Any] | None = None,
) -> str:
    if release_json_dir:
        fixture = (
            Path(release_json_dir)
            / f"{repo.replace('/', '__')}__{ref}__commit.json"
        )
        try:
            if fixture.exists():
                payload: Any = json.loads(fixture.read_text(encoding="utf-8"))
            elif release is not None:
                payload = {"sha": release.get("tag_commit_sha")}
            else:
                raise ReleaseError(f"Missing upstream ref fixture {fixture}")
        except ReleaseError:
            raise
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ReleaseError(
                f"Failed to resolve exact commit for {repo}@{ref}: {error}"
            ) from error
    else:
        context = f"Failed to resolve exact commit for {repo}@{ref}"
        raw = read_release_url(
            f"https://api.github.com/repos/{repo}/commits/{ref}",
            context=context,
            headers=github_api_headers(),
        )
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ReleaseError(f"{context}: invalid UTF-8 or JSON") from error
    if not isinstance(payload, dict):
        raise ReleaseError(f"Commit response for {repo}@{ref} must be a JSON object")
    commit = payload.get("sha")
    if not isinstance(commit, str) or not FULL_COMMIT_RE.fullmatch(commit):
        raise ReleaseError(f"Could not resolve exact commit for {repo}@{ref}")
    return commit


def fetch_tag_commit(
    repo: str,
    tag: str,
    release_json_dir: str,
    release: dict[str, Any],
) -> str:
    return fetch_ref_commit(repo, tag, release_json_dir, release)


def allows_legacy_litert_manifest(tag: str) -> bool:
    return tag in LEGACY_SCHEMA1_RELEASES


_COMPATIBLE_APPLE_COMPANION_TAGS_PATTERN = re.compile(
    r"const llamaCppCompatibleAppleCompanionTags = <String, String>\{(.*?)\};",
    re.DOTALL,
)
_COMPATIBLE_APPLE_COMPANION_CHECKSUMS_PATTERN = re.compile(
    r"const llamaCppCompatibleAppleCompanionChecksums = <String, String>\{(.*?)\};",
    re.DOTALL,
)


def refresh_llama_cpp_apple_checksum(source: str, tag: str, checksum: str) -> str:
    """Record the current qualified artifact without changing same-tag proof."""
    matches = list(_COMPATIBLE_APPLE_COMPANION_CHECKSUMS_PATTERN.finditer(
        _native_pins_code_mask(source)
    ))
    if len(matches) != 1:
        raise ReleaseError("Could not uniquely find Apple llama.cpp checksum contract")
    match = matches[0]
    body = source[match.start(1):match.end(1)]
    entry_pattern = r"'([^'\r\n]+)':\s*'([a-f0-9]{64})'\s*,"
    if re.fullmatch(r"(?:\s*" + entry_pattern + r")*\s*", body) is None:
        raise ReleaseError("Malformed Apple llama.cpp checksum contract")
    entries = re.findall(entry_pattern, body)
    checksums = dict(entries)
    if len(checksums) != len(entries):
        raise ReleaseError("Malformed Apple llama.cpp checksum contract; duplicate tag")
    if tag in checksums:
        if checksums[tag] != checksum:
            raise ReleaseError("Same-tag Apple llama.cpp checksum changed; requalify the contract")
        return source
    checksums[tag] = checksum
    rendered = "\n" + "".join(
        f"  '{key}':\n      '{value}',\n" for key, value in checksums.items()
    )
    return source[:match.start(1)] + rendered + source[match.end(1):]


def clear_compatible_apple_companion_tags(pins_text: str) -> tuple[str, list[str]]:
    """Empty the accepted earlier companion tags and their checksums, which
    hold for one pin only."""
    cleared: list[str] = []
    for name, pattern, collect in (
        (
            "llamaCppCompatibleAppleCompanionTags",
            _COMPATIBLE_APPLE_COMPANION_TAGS_PATTERN,
            True,
        ),
        (
            "llamaCppCompatibleAppleCompanionChecksums",
            _COMPATIBLE_APPLE_COMPANION_CHECKSUMS_PATTERN,
            False,
        ),
    ):
        matches = list(pattern.finditer(pins_text))
        if len(matches) != 1:
            raise ReleaseError(
                f"Could not find {name} in {DEFAULT_NATIVE_RELEASE_PINS}"
            )
        match = matches[0]
        if collect:
            cleared = re.findall(r"^  '([^']+)':", match.group(1), re.MULTILINE)
        pins_text = (
            pins_text[: match.start()]
            + f"const {name} = <String, String>{{}};"
            + pins_text[match.end() :]
        )
    return pins_text, cleared


def replace_one(text: str, pattern: str, replacement: str, description: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        raise ReleaseError(f"Could not replace {description}")
    return updated


def atomic_write_many(
    writes: dict[Path, str],
    *,
    replace_func: Any = os.replace,
) -> None:
    """Commit a set of text replacements with rollback on partial failure."""
    staged: dict[Path, Path] = {}
    backups: dict[Path, Path | None] = {}
    replaced: list[Path] = []
    try:
        for path, text in writes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            descriptor, staged_name = tempfile.mkstemp(
                prefix=f".{path.name}.new-", dir=path.parent
            )
            staged_path = Path(staged_name)
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                output.write(text)
                output.flush()
                os.fsync(output.fileno())
            if path.exists():
                staged_path.chmod(path.stat().st_mode)
                backup_descriptor, backup_name = tempfile.mkstemp(
                    prefix=f".{path.name}.backup-", dir=path.parent
                )
                os.close(backup_descriptor)
                backup_path = Path(backup_name)
                shutil.copy2(path, backup_path)
                backups[path] = backup_path
            else:
                backups[path] = None
            staged[path] = staged_path

        for path in sorted(writes, key=lambda item: item.as_posix()):
            replace_func(staged[path], path)
            replaced.append(path)
            staged.pop(path, None)
    except Exception as error:
        rollback_errors: list[str] = []
        for path in reversed(replaced):
            backup = backups[path]
            try:
                if backup is None:
                    path.unlink(missing_ok=True)
                else:
                    replace_func(backup, path)
                    backups[path] = None
            except Exception as rollback_error:  # pragma: no cover - catastrophic IO
                rollback_errors.append(f"{path}: {rollback_error}")
        detail = ""
        if rollback_errors:
            detail = "; rollback failures: " + "; ".join(rollback_errors)
        raise ReleaseError(f"Atomic pin update failed: {error}{detail}") from error
    finally:
        for path in (*staged.values(), *(item for item in backups.values() if item)):
            path.unlink(missing_ok=True)


_LLAMA_CPP_BUNDLE_DIGESTS_RE = re.compile(
    r"const llamaCppBundleSha256 = <String, String>\{(.*?)\n\};",
    re.DOTALL,
)


def llama_cpp_bundle_names(pins_text: str) -> list[str]:
    match = _LLAMA_CPP_BUNDLE_DIGESTS_RE.search(pins_text)
    if match is None:
        raise ReleaseError(
            "Could not find llamaCppBundleSha256 in "
            f"{DEFAULT_NATIVE_RELEASE_PINS}"
        )
    bundles = re.findall(r"'([^']+)':\s*'[0-9a-f]{64}',", match.group(1))
    if not bundles:
        raise ReleaseError(
            f"{DEFAULT_NATIVE_RELEASE_PINS} llamaCppBundleSha256 pins no bundles"
        )
    if len(bundles) != len(set(bundles)):
        raise ReleaseError(
            f"{DEFAULT_NATIVE_RELEASE_PINS} llamaCppBundleSha256 duplicates a "
            "bundle"
        )
    return bundles


def llama_cpp_bundle_checksum(
    release: dict[str, Any],
    bundle: str,
    release_tag: str,
    manifest_checksums: dict[str, str],
    *,
    repo: str,
) -> str:
    """Return the archive SHA-256 the hook must verify for [bundle].

    The GitHub asset digest (or the hash of the downloaded asset) is the
    source; an assets.json entry for the archive must agree with it.
    """
    asset_name = f"llamadart-native-{bundle}-{release_tag}.tar.gz"
    checksum = release_asset_checksum(release, asset_name, repo=repo)
    manifest_checksum = manifest_checksums.get(asset_name)
    if manifest_checksum is not None and manifest_checksum != checksum:
        raise ReleaseError(
            f"Release {release_tag} checksum mismatch for {asset_name}: "
            f"assets.json lists {manifest_checksum}, the release asset is "
            f"{checksum}."
        )
    return checksum


def replace_llama_cpp_bundle_checksum(
    pins_text: str,
    bundle: str,
    checksum: str,
) -> str:
    match = _LLAMA_CPP_BUNDLE_DIGESTS_RE.search(pins_text)
    if match is None:
        raise ReleaseError(
            "Could not find llamaCppBundleSha256 in "
            f"{DEFAULT_NATIVE_RELEASE_PINS}"
        )
    body, count = re.subn(
        rf"('{re.escape(bundle)}':\s*')[0-9a-f]{{64}}(')",
        rf"\g<1>{checksum}\2",
        match.group(1),
    )
    if count != 1:
        raise ReleaseError(f"Could not replace llama.cpp checksum for {bundle}")
    return pins_text[: match.start(1)] + body + pins_text[match.end(1) :]


_LLAMA_CPP_BACKEND_SIDECARS_RE = re.compile(
    r"const llamaCppBackendSidecarSpecs = <LlamaCppBackendSidecarSpec>\[.*?\];",
    re.DOTALL,
)


def replace_llama_cpp_hook_contract(pins_text: str, version: int) -> str:
    return replace_one(
        pins_text,
        r"const llamaCppHookContractVersion = [0-9]+;",
        f"const llamaCppHookContractVersion = {version};",
        "native pins llama.cpp hook contract version",
    )


def replace_llama_cpp_backend_sidecars(
    pins_text: str,
    sidecars: list[tuple[NativeBackendSidecar, str]],
) -> str:
    """Rewrite llamaCppBackendSidecarSpecs as dart format lays it out."""
    if not sidecars:
        body = "const llamaCppBackendSidecarSpecs = <LlamaCppBackendSidecarSpec>[];"
    else:
        entries = "".join(
            "  LlamaCppBackendSidecarSpec(\n"
            f"    bundle: '{sidecar.bundle}',\n"
            f"    backend: '{sidecar.backend}',\n"
            f"    archive: '{sidecar.archive}',\n"
            f"    sha256: '{checksum}',\n"
            "  ),\n"
            for sidecar, checksum in sidecars
        )
        body = (
            "const llamaCppBackendSidecarSpecs = <LlamaCppBackendSidecarSpec>[\n"
            f"{entries}];"
        )
    updated, count = _LLAMA_CPP_BACKEND_SIDECARS_RE.subn(
        lambda _: body,
        pins_text,
    )
    if count != 1:
        raise ReleaseError(
            "Could not find llamaCppBackendSidecarSpecs in "
            f"{DEFAULT_NATIVE_RELEASE_PINS}"
        )
    return updated


def litert_lm_bundle_names(pins_text: str) -> list[str]:
    pattern = re.compile(
        r"\bLiteRtLmBundleSpec\(\s*'([^']+)',\s*sha256: '[0-9a-f]+'",
        re.DOTALL,
    )
    bundles = pattern.findall(pins_text)
    if not bundles:
        raise ReleaseError(
            f"Could not find LiteRT-LM bundle specs in {DEFAULT_NATIVE_RELEASE_PINS}"
        )
    if len(bundles) != len(set(bundles)):
        raise ReleaseError(
            f"{DEFAULT_NATIVE_RELEASE_PINS} contains duplicate LiteRT-LM bundle specs"
        )
    return bundles


def replace_litert_lm_bundle_checksum(
    pins_text: str,
    bundle: str,
    checksum: str,
) -> str:
    pattern = re.compile(
        rf"(\bLiteRtLmBundleSpec\(\s*'{re.escape(bundle)}',\s*sha256: ')[0-9a-f]+(')",
        re.DOTALL,
    )
    updated, count = pattern.subn(rf"\g<1>{checksum}\2", pins_text, count=1)
    if count != 1:
        raise ReleaseError(f"Could not replace LiteRT-LM checksum for {bundle}")
    return updated


# From v0.19.1-1, Linux and Windows hosts link LiteRT in, and the owner build
# fails if they still import it (litert-lm-native#112). Bundles keep the
# upstream prebuilt only to preserve their layout, so it is not required.
LITERT_DESKTOP_LINKED_LITERT_FIRST_RELEASE = ((0, 19, 1), 1)
LITERT_DESKTOP_UNLOADED_PREBUILTS = {
    "linux": "libLiteRt.so",
    "windows": "libLiteRt.dll",
}


def _litert_desktop_hosts_link_litert(manifest: dict[str, Any]) -> bool:
    release = manifest.get("release")
    tag = release.get("tag") if isinstance(release, dict) else None
    if not isinstance(tag, str):
        return False
    try:
        order = stable_release_order(tag)
    except ReleaseError:
        return False
    return order >= LITERT_DESKTOP_LINKED_LITERT_FIRST_RELEASE


def litert_schema2_bundle_required_libraries(
    manifest: dict[str, Any],
) -> dict[str, tuple[str, ...]]:
    unloaded_prebuilts = (
        LITERT_DESKTOP_UNLOADED_PREBUILTS
        if _litert_desktop_hosts_link_litert(manifest)
        else {}
    )
    platforms = manifest.get("platforms")
    if not isinstance(platforms, list):
        raise ReleaseError("LiteRT-LM manifest platforms must be a list")
    result: dict[str, tuple[str, ...]] = {}
    for platform in platforms:
        if not isinstance(platform, dict):
            raise ReleaseError("LiteRT-LM manifest contains an invalid platform")
        platform_name = require_string(platform.get("platform"), "platform name")
        arch = require_string(platform.get("arch"), "platform architecture")
        paths = platform.get("artifactPaths")
        if (
            not isinstance(paths, list)
            or not paths
            or any(
                not isinstance(path, str)
                or not path
                or path == "."
                or "\\" in path
                or Path(path).is_absolute()
                or ".." in Path(path).parts
                or Path(path).as_posix() != path
                for path in paths
            )
        ):
            raise ReleaseError("LiteRT-LM platform artifact paths are invalid")
        if len(paths) != len(set(paths)):
            raise ReleaseError("LiteRT-LM platform artifact paths are duplicated")
        # Framework metadata is part of the archive provenance, not a library
        # the flat native-assets hook should extract or require.
        framework_metadata = re.compile(
            rf"bin/ios/{re.escape(arch)}/[A-Za-z0-9_]+\.framework/Info\.plist"
        )
        library_paths = []
        for path in paths:
            if platform_name == "ios" and framework_metadata.fullmatch(path):
                continue
            if platform_name == "ios":
                # Owner archives include raw build inputs beside canonical
                # frameworks. Flutter would embed those as duplicate frameworks.
                raw_frameworks = {
                    "libLiteRtLm.dylib": "LiteRtLm",
                    "libLiteRt.dylib": "LiteRtLm",
                    "libGemmaModelConstraintProvider.dylib": "GemmaModelConstraintProvider",
                    "libLiteRtMetalAccelerator.dylib": "LiteRtMetalAccelerator",
                    "libLiteRtTopKMetalSampler.dylib": "LiteRtTopKMetalSampler",
                }
                framework = raw_frameworks.get(Path(path).name)
                if framework and Path(path).parent.as_posix() == f"bin/ios/{arch}":
                    canonical = f"bin/ios/{arch}/{framework}.framework/{framework}"
                    if canonical not in paths:
                        raise ReleaseError("LiteRT-LM iOS raw input has no canonical framework")
                    continue
            if platform_name == "windows" and Path(path).suffix == ".lib":
                if (Path(path).parent.as_posix() != f"bin/windows/{arch}"
                        or Path(path).with_suffix(".dll").as_posix() not in paths):
                    raise ReleaseError("LiteRT-LM Windows import library has no matching DLL")
                continue
            if Path(path).name == unloaded_prebuilts.get(platform_name):
                continue
            library_paths.append(path)
        if not library_paths:
            raise ReleaseError("LiteRT-LM platform contains no runtime libraries")
        libraries = tuple(sorted(Path(path).name for path in library_paths))
        if any(
            not SAFE_LITERT_LIBRARY_FILENAME_RE.fullmatch(library)
            for library in libraries
        ):
            raise ReleaseError("LiteRT-LM platform library names are invalid")
        if len(libraries) != len(set(libraries)):
            raise ReleaseError("LiteRT-LM platform library names are duplicated")
        bundle = f"{platform_name}-{arch}"
        if bundle in result:
            raise ReleaseError("LiteRT-LM platform bundle is duplicated")
        result[bundle] = libraries
    return result


def replace_litert_lm_bundle_required_libraries(
    pins_text: str,
    bundle: str,
    libraries: tuple[str, ...],
) -> str:
    if not libraries:
        raise ReleaseError(f"LiteRT-LM bundle {bundle} has no required libraries")
    inline_libraries = "{" + ", ".join(f"'{library}'" for library in libraries) + "}"
    multiline_libraries = "{\n" + "".join(
        f"      '{library}',\n" for library in libraries
    ) + "    }"
    pattern = re.compile(
        rf"(\bLiteRtLmBundleSpec\(\s*'{re.escape(bundle)}',\s*"
        r"sha256: '[0-9a-f]+',\s*requiredLibraries:\s*)\{.*?\},?(\s*\),)",
        re.DOTALL,
    )
    def replacement(match: re.Match[str]) -> str:
        field_prefix_width = len(match.group(1).rsplit("\n", maxsplit=1)[-1])
        required_libraries = (
            inline_libraries
            if field_prefix_width + len(inline_libraries) + 1
            <= DART_FORMAT_PAGE_WIDTH
            else multiline_libraries
        )
        return f"{match.group(1)}{required_libraries},{match.group(2)}"

    updated, count = pattern.subn(replacement, pins_text, count=1)
    if count != 1:
        raise ReleaseError(
            f"Could not replace LiteRT-LM required libraries for {bundle}"
        )
    return updated


def litert_schema2_runtime_required_libraries(
    bundle_libraries: dict[str, tuple[str, ...]],
) -> dict[str, tuple[str, ...]]:
    required_bundles = (
        "macos-arm64",
        "linux-arm64",
        "linux-x64",
        "windows-x64",
    )
    missing_bundles = set(required_bundles) - set(bundle_libraries)
    if missing_bundles:
        raise ReleaseError(
            "LiteRT-LM runtime inventory is missing bundles: "
            + ", ".join(sorted(missing_bundles))
        )
    return {
        bundle: bundle_libraries[bundle]
        for bundle in required_bundles
    }


def _render_litert_lm_runtime_library_function(
    function_name: str,
    entries: dict[str, tuple[str, ...]],
) -> str:
    lines = [
        f"List<String> {function_name}(Abi abi) {{",
        "  return switch (abi) {",
    ]
    for abi, libraries in entries.items():
        if len(libraries) == 1:
            lines.append(f"    Abi.{abi} => const <String>['{libraries[0]}'],")
        elif libraries:
            lines.append(f"    Abi.{abi} => const <String>[")
            lines.extend(f"      '{library}'," for library in libraries)
            lines.append("    ],")
        else:
            lines.append(f"    Abi.{abi} => const <String>[],")
    lines.extend(
        [
            "    _ => const <String>[],",
            "  };",
            "}",
        ]
    )
    return "\n".join(lines) + "\n"


def _replace_litert_lm_runtime_library_function(
    runtime_text: str,
    function_name: str,
    entries: dict[str, tuple[str, ...]],
) -> str:
    pattern = re.compile(
        rf"List<String> {re.escape(function_name)}\(Abi abi\) \{{\n"
        r"  return switch \(abi\) \{.*?\n  \};\n\}\n",
        re.DOTALL,
    )
    replacement = _render_litert_lm_runtime_library_function(
        function_name,
        entries,
    )
    updated, count = pattern.subn(replacement, runtime_text)
    if count != 1:
        raise ReleaseError(
            f"Could not replace LiteRT-LM runtime library function {function_name}"
        )
    return updated


def _litert_lm_runtime_inventory_is_v1(manifest: dict[str, Any]) -> bool:
    upstream = manifest.get("upstream")
    compatibility_tag = require_string(
        upstream.get("compatibilityTag") if isinstance(upstream, dict) else None,
        "runtime inventory upstream compatibilityTag",
    )
    version = _litert_compatibility_version(compatibility_tag)
    if version > max(LITERT_V1_COMPATIBILITY_VERSIONS):
        raise ReleaseError(
            "LiteRT-LM runtime inventory has no reviewed API mapping for "
            + compatibility_tag
        )
    return version in LITERT_V1_COMPATIBILITY_VERSIONS


def replace_litert_lm_runtime_required_libraries(
    runtime_text: str,
    bundle_libraries: dict[str, tuple[str, ...]],
    *,
    manifest: dict[str, Any],
) -> str:
    runtime_libraries = litert_schema2_runtime_required_libraries(bundle_libraries)
    # Explicit legacy runtimes must retain their own inventory after a v1 repin.
    function_name = (
        "_liteRtLmV1RequiredLibrariesForAbi"
        if _litert_lm_runtime_inventory_is_v1(manifest)
        else "_liteRtLmLegacyRequiredLibrariesForAbi"
    )
    # The bundle keys use hyphens while the Dart ABI enum uses camel case.
    runtime_entries = {
        "macosArm64": runtime_libraries["macos-arm64"],
        "linuxArm64": runtime_libraries["linux-arm64"],
        "linuxX64": runtime_libraries["linux-x64"],
        "windowsX64": runtime_libraries["windows-x64"],
    }
    return _replace_litert_lm_runtime_library_function(
        runtime_text,
        function_name,
        runtime_entries,
    )


def _litert_schema2_macos_bundle_entries(
    bundle_libraries: dict[str, tuple[str, ...]],
) -> dict[str, tuple[str, ...]]:
    runtime_libraries = litert_schema2_runtime_required_libraries(bundle_libraries)
    return {"arm64": runtime_libraries["macos-arm64"]}


def _litert_macos_framework_binary_path(library: str) -> str:
    if not library.endswith(".dylib"):
        raise ReleaseError(
            "LiteRT-LM macOS runtime inventory must contain dylib filenames"
        )
    framework_name = library.removesuffix(".dylib")
    if framework_name.startswith("lib"):
        framework_name = framework_name[3:]
    if not framework_name:
        raise ReleaseError("LiteRT-LM macOS runtime inventory has an empty library")
    return (
        f"{framework_name}.framework/Versions/A/"
        f"{framework_name}"
    )


def _litert_schema2_macos_framework_entries(
    bundle_libraries: dict[str, tuple[str, ...]],
) -> dict[str, tuple[str, ...]]:
    macos_bundles = _litert_schema2_macos_bundle_entries(bundle_libraries)
    return {
        arch: tuple(
            sorted(_litert_macos_framework_binary_path(library) for library in libraries)
        )
        for arch, libraries in macos_bundles.items()
    }


def litert_schema2_macos_required_native_spm_files(
    manifest: dict[str, Any],
    resolved_tag: str,
) -> tuple[str, ...]:
    targets = litert_schema2_apple_targets(manifest, resolved_tag)
    target_paths = {
        "LiteRtLm": "LiteRtLm.framework/Versions/A/LiteRtLm",
        "CLiteRTLMMac": "libCLiteRTLM_mac.dylib",
    }
    missing_targets = set(target_paths) - targets
    if missing_targets:
        raise ReleaseError(
            "LiteRT-LM schema-2 owner inventory is missing required macOS SPM "
            "targets: "
            + ", ".join(sorted(missing_targets))
        )
    return tuple(target_paths[target] for target in ("LiteRtLm", "CLiteRTLMMac"))


def litert_macos_spm_layout(library: str) -> tuple[str | None, str | None]:
    layout = LITERT_MACOS_SPM_LAYOUT.get(library)
    if layout is None:
        raise ReleaseError(
            f"LiteRT-LM macOS runtime library {library} has no reviewed SwiftPM "
            "app-bundle layout; inspect its owner xcframework and extend "
            "LITERT_MACOS_SPM_LAYOUT"
        )
    return layout


def litert_macos_complete_spm_entries(
    bundle_libraries: dict[str, tuple[str, ...]],
    native_spm_files: tuple[str, ...],
) -> dict[str, tuple[str, ...]]:
    # Core/shim linking does not establish availability of dynamic GPU plugins.
    # Require the complete per-architecture inventory before skipping raw staging.
    macos_bundles = _litert_schema2_macos_bundle_entries(bundle_libraries)
    entries: dict[str, tuple[str, ...]] = {}
    for arch in macos_bundles:
        embedded = [
            litert_macos_spm_layout(library)[1]
            for library in sorted(macos_bundles[arch])
        ]
        entries[arch] = native_spm_files + tuple(
            item for item in embedded
            if item is not None and item not in native_spm_files
        )
    return entries


def _render_litert_lm_shell_inventory_function(
    function_name: str,
    entries: dict[str, tuple[str, ...]],
) -> str:
    lines = [
        f"{function_name}() {{",
        '  case "$LITERT_ARCH" in',
    ]
    for arch, libraries in entries.items():
        if not libraries:
            raise ReleaseError(
                f"LiteRT-LM macOS {arch} inventory has no required files"
            )
        lines.append(f"    {arch})")
        lines.append("      printf '%s\\n' " + "\\")
        for index, library in enumerate(libraries):
            suffix = " " + "\\" if index < len(libraries) - 1 else ""
            lines.append(f'        "{library}"{suffix}')
        lines.append("      ;;")
    lines.extend(("  esac", "}"))
    return "\n".join(lines) + "\n"


def _replace_litert_lm_shell_inventory_function(
    prepare_text: str,
    function_name: str,
    entries: dict[str, tuple[str, ...]],
) -> str:
    pattern = re.compile(
        rf"{re.escape(function_name)}\(\) \{{.*?\n\}}\n",
        re.DOTALL,
    )
    replacement = _render_litert_lm_shell_inventory_function(
        function_name,
        entries,
    )
    updated, count = pattern.subn(replacement, prepare_text, count=1)
    if count != 1:
        raise ReleaseError(
            f"Could not replace LiteRT-LM macOS prepare function {function_name}"
        )
    return updated


def replace_litert_lm_macos_prepare_inventory(
    prepare_text: str,
    bundle_libraries: dict[str, tuple[str, ...]],
    *,
    manifest: dict[str, Any],
    resolved_tag: str,
) -> str:
    bundle_entries = _litert_schema2_macos_bundle_entries(bundle_libraries)
    native_spm_files = litert_schema2_macos_required_native_spm_files(
        manifest,
        resolved_tag,
    )
    native_spm_entries = litert_macos_complete_spm_entries(
        bundle_libraries, native_spm_files
    )
    updated = _replace_litert_lm_shell_inventory_function(
        prepare_text,
        "required_libraries",
        bundle_entries,
    )
    return _replace_litert_lm_shell_inventory_function(
        updated,
        "required_native_spm_files",
        native_spm_entries,
    )


def replace_litert_lm_runtime_macos_inventory(
    runtime_text: str,
    bundle_libraries: dict[str, tuple[str, ...]],
    *,
    manifest: dict[str, Any],
    resolved_tag: str,
) -> str:
    framework_entries = _litert_schema2_macos_framework_entries(bundle_libraries)
    runtime_framework_entries = {"macosArm64": framework_entries["arm64"]}
    native_spm_files = litert_schema2_macos_required_native_spm_files(
        manifest,
        resolved_tag,
    )
    complete_spm = litert_macos_complete_spm_entries(bundle_libraries, native_spm_files)
    runtime_native_spm_entries = {"macosArm64": complete_spm["arm64"]}
    prefix = (
        "_liteRtLmV1MacOs"
        if _litert_lm_runtime_inventory_is_v1(manifest)
        else "_liteRtLmMacOs"
    )
    updated = _replace_litert_lm_runtime_library_function(
        runtime_text,
        prefix + "RequiredFrameworksForAbi",
        runtime_framework_entries,
    )
    return _replace_litert_lm_runtime_library_function(
        updated,
        prefix + "RequiredNativeSpmFilesForAbi",
        runtime_native_spm_entries,
    )


def replace_swift_binary_target_checksum(
    swift_text: str,
    target_name: str,
    checksum: str,
) -> str:
    pattern = re.compile(
        rf'(nativeRepoBinaryTarget\(\s*name: "{re.escape(target_name)}",'
        r'.*?checksum: ")[0-9a-f]+(")',
        re.DOTALL,
    )
    updated, count = pattern.subn(rf"\g<1>{checksum}\2", swift_text, count=1)
    if count != 1:
        raise ReleaseError(f"Could not replace Package.swift checksum for {target_name}")
    return updated


def _validate_litert_lm_v019_swift_topology(
    swift_text: str, *, current_tag: str, include_obsolete_samplers: bool,
    include_metal_accelerator: bool = True,
    include_litert_companions: bool = True,
) -> dict[str, str]:
    platforms = {
        "LiteRtLm": ".iOS, .macOS",
        "CLiteRTLM": ".iOS",
        "CLiteRTLMMac": ".macOS",
        "LiteRtMetalAccelerator": ".iOS",
        "LiteRtTopKMetalSampler": ".iOS",
        "LiteRt": ".macOS",
        "LiteRtTopKWebGpuSampler": ".macOS",
        "LiteRtWebGpuAccelerator": ".macOS",
        "WebgpuDawn": ".macOS",
    }
    if not include_obsolete_samplers:
        platforms.pop("LiteRtTopKMetalSampler")
        platforms.pop("LiteRtTopKWebGpuSampler")
    if not include_metal_accelerator:
        platforms.pop("LiteRtMetalAccelerator")
    if not include_litert_companions:
        for target in LITERT_UNUSED_APPLE_COMPANION_TARGETS:
            platforms.pop(target)
    label = "LiteRT-LM v0.19 Swift topology"
    assets = swift_native_repo_binary_targets(
        swift_text, tag_variable="liteRtLmTag", current_tag=current_tag,
    )
    if (
        len(assets) != len(platforms)
        or {name for name, _ in assets} != set(platforms)
        or len(re.findall(r"\bnativeRepoBinaryTarget\s*\(", swift_text))
        != len(platforms) + 1
    ):
        raise ReleaseError(f"{label} has duplicate or unexpected binary targets")
    blocks = {}
    for target in platforms:
        artifact = re.escape(f"litert-lm-native-apple-{target}-xcframework-")
        interpolated = re.escape(r'\(liteRtLmTag)')
        tag = rf"(?:{interpolated}|{re.escape(current_tag)})"
        pattern = (
            r'(?m)^[ \t]*nativeRepoBinaryTarget\(\s*'
            rf'name: "{target}",\s*'
            r'repository: "leehack/litert-lm-native",\s*'
            rf'artifactName: "{artifact}{tag}\.zip",\s*'
            r'tag: liteRtLmTag,\s*checksum: "[0-9a-f]{64}"\s*'
            r'\),\n'
        )
        matches = re.findall(pattern, swift_text)
        if len(matches) != 1:
            raise ReleaseError(f"{label} requires the canonical {target} binary target")
        blocks[target] = matches[0]
        dependencies = re.findall(
            rf'\.target\(name: "{target}", condition: '
            r'\.when\(platforms: \[([^]]*)\]\)\)', swift_text,
        )
        if (
            dependencies != [platforms[target]]
            or swift_text.count(f'name: "{target}"') != 2
        ):
            raise ReleaseError(f"{label} requires the maintained {target} platform dependency")
    references = re.findall(r'\.target\s*\(\s*name\s*:\s*"([^\"]+)"', swift_text)
    if (
        sorted(references) != sorted(set(platforms) | {"llamadart_litert_lm_flutter"})
        or len(re.findall(r'\.target\s*\(', swift_text)) != len(references)
    ):
        raise ReleaseError(f"{label} has unexpected target references")
    dependencies = re.findall(
        r'\bdependencies\s*:\s*\[(.*?)\]\s*,\s*linkerSettings\s*:',
        swift_text, re.DOTALL,
    )
    if len(dependencies) != 1 or re.sub(
        r'\.target\s*\(\s*name\s*:\s*"[^\"]+"\s*,\s*condition\s*:\s*'
        r'\.when\s*\(\s*platforms\s*:\s*\[[^]]*\]\s*\)\s*\)',
        "", dependencies[0] if dependencies else "",
    ).strip(" \t\r\n,"):
        raise ReleaseError(f"{label} has malformed dependency inventory")
    return blocks


def _remove_litert_lm_obsolete_topk_samplers(
    swift_text: str, *, current_tag: str,
) -> str:
    blocks = _validate_litert_lm_v019_swift_topology(
        swift_text, current_tag=current_tag, include_obsolete_samplers=True,
    )
    for sampler, platform in (
        ("LiteRtTopKMetalSampler", ".iOS"),
        ("LiteRtTopKWebGpuSampler", ".macOS"),
    ):
        if swift_text.count(sampler) != 3:
            raise ReleaseError("LiteRT-LM v0.19 removal has ambiguous sampler references")
        swift_text = swift_text.replace(blocks[sampler], "", 1)
        swift_text = replace_one(
            swift_text,
            rf'(?m)^[ \t]*\.target\(name: "{sampler}", '
            rf'condition: \.when\(platforms: \[{re.escape(platform)}\]\)\),\n',
            "",
            f"LiteRT-LM obsolete {sampler} must have exactly one {platform} dependency",
        )
    return swift_text


def _remove_litert_lm_unused_metal_accelerator(
    swift_text: str, *, current_tag: str,
) -> str:
    blocks = _validate_litert_lm_v019_swift_topology(
        swift_text, current_tag=current_tag, include_obsolete_samplers=False,
    )
    if swift_text.count("LiteRtMetalAccelerator") != 3:
        raise ReleaseError(
            "LiteRT-LM v0.19 removal has ambiguous Metal accelerator references"
        )
    swift_text = swift_text.replace(blocks["LiteRtMetalAccelerator"], "", 1)
    return replace_one(
        swift_text,
        r'(?m)^[ \t]*\.target\(name: "LiteRtMetalAccelerator", '
        r'condition: \.when\(platforms: \[\.iOS\]\)\),\n',
        "",
        "LiteRT-LM unused Metal accelerator must have exactly one iOS dependency",
    )


def _remove_litert_lm_unused_litert_companions(
    swift_text: str, *, current_tag: str,
) -> str:
    blocks = _validate_litert_lm_v019_swift_topology(
        swift_text,
        current_tag=current_tag,
        include_obsolete_samplers=False,
        include_metal_accelerator=False,
    )
    for target in LITERT_UNUSED_APPLE_COMPANION_TARGETS:
        # Exact quoted match: "LiteRt" is a substring of other target names.
        if swift_text.count(f'name: "{target}"') != 2:
            raise ReleaseError(
                f"LiteRT-LM v0.19 removal has ambiguous {target} references"
            )
        swift_text = swift_text.replace(blocks[target], "", 1)
        swift_text = replace_one(
            swift_text,
            rf'(?m)^[ \t]*\.target\(name: "{target}", '
            r'condition: \.when\(platforms: \[\.macOS\]\)\),\n',
            "",
            f"LiteRT-LM unused {target} must have exactly one macOS dependency",
        )
    return swift_text


def prepare_litert_lm_package_swift(
    original_swift_text: str,
    *,
    release: dict[str, Any],
    manifest: dict[str, Any],
    resolved_tag: str,
    repo: str = DEFAULT_LITERT_LM_NATIVE_REPO,
) -> str:
    original_tag = swift_variable_value(
        original_swift_text,
        "liteRtLmTag",
        "LiteRT-LM Package.swift tag",
    )
    swift_text = original_swift_text
    if manifest.get("schemaVersion") == 2:
        expected_targets = litert_schema2_apple_targets(manifest, resolved_tag)
        legacy_targets = (expected_targets - {"CLiteRTLMMac"}) | {
            "GemmaModelConstraintProvider"
        }
        current_targets = {
            target_name
            for target_name, _ in swift_native_repo_binary_targets(
                swift_text,
                tag_variable="liteRtLmTag",
                current_tag=original_tag,
            )
        }
        obsolete_samplers = {"LiteRtTopKMetalSampler", "LiteRtTopKWebGpuSampler"}
        sampler_free_targets = {
            "LiteRtLm", "CLiteRTLM", "CLiteRTLMMac", "LiteRtMetalAccelerator",
            "LiteRt", "LiteRtWebGpuAccelerator", "WebgpuDawn",
        }
        metal = "LiteRtMetalAccelerator"
        litert_companions = set(LITERT_UNUSED_APPLE_COMPANION_TARGETS)
        if _litert_is_v1_compatibility_tag(
            manifest["upstream"]["compatibilityTag"]
        ) and expected_targets in (
            sampler_free_targets,
            sampler_free_targets - {metal},
            sampler_free_targets - {metal} - litert_companions,
        ):
            if current_targets == sampler_free_targets | obsolete_samplers:
                swift_text = _remove_litert_lm_obsolete_topk_samplers(
                    swift_text, current_tag=original_tag,
                )
                current_targets -= obsolete_samplers
            if metal not in expected_targets and current_targets == sampler_free_targets:
                swift_text = _remove_litert_lm_unused_metal_accelerator(
                    swift_text, current_tag=original_tag,
                )
                current_targets.discard(metal)
            if (
                not litert_companions & expected_targets
                and current_targets == sampler_free_targets - {metal}
            ):
                swift_text = _remove_litert_lm_unused_litert_companions(
                    swift_text, current_tag=original_tag,
                )
                current_targets -= litert_companions
            if current_targets == expected_targets:
                _validate_litert_lm_v019_swift_topology(
                    swift_text,
                    current_tag=original_tag,
                    include_obsolete_samplers=False,
                    include_metal_accelerator=metal in expected_targets,
                    include_litert_companions=litert_companions <= expected_targets,
                )
        if current_targets == legacy_targets:
            if swift_text.count("GemmaModelConstraintProvider") != 3:
                raise ReleaseError(
                    "Legacy LiteRT-LM Package.swift Gemma target topology is ambiguous"
                )
            swift_text = swift_text.replace(
                "GemmaModelConstraintProvider",
                "CLiteRTLMMac",
            )
            swift_text = replace_one(
                swift_text,
                (
                    r'(name: "CLiteRTLMMac", condition: '
                    r'\.when\(platforms: \[)\.iOS(\]\)\))'
                ),
                r"\g<1>.macOS\2",
                "LiteRT-LM Package.swift macOS compatibility target condition",
            )
            swift_text = replace_one(
                swift_text,
                (
                    r'(name: "LiteRtLm", condition: '
                    r'\.when\(platforms: \[)\.iOS(\]\)\))'
                ),
                r"\g<1>.iOS, .macOS\2",
                "LiteRT-LM Package.swift shared runtime target condition",
            )
        elif (
            "GemmaModelConstraintProvider" not in expected_targets
            and current_targets == expected_targets | {"GemmaModelConstraintProvider"}
        ):
            # Modern manifests already have the separate macOS shim. Remove
            # only the formerly required iOS provider, never the macOS runtime
            # inventory or an optional owner release asset.
            if swift_text.count("GemmaModelConstraintProvider") != 3:
                raise ReleaseError(
                    "Modern LiteRT-LM Package.swift provider topology is ambiguous"
                )
            current_target_assets = swift_native_repo_binary_targets(
                swift_text, tag_variable="liteRtLmTag", current_tag=original_tag,
            )
            if len(current_target_assets) != len(current_targets):
                raise ReleaseError(
                    "Modern LiteRT-LM provider removal has duplicate binary targets"
                )
            for target, artifact_template in current_target_assets:
                canonical_template = (
                    f"litert-lm-native-apple-{target}-xcframework-{{tag}}.zip"
                )
                if artifact_template != canonical_template:
                    raise ReleaseError(
                        "Modern LiteRT-LM provider removal requires the "
                        f"canonical {target} artifact template"
                    )
            target_references = re.findall(
                r'\.target\s*\(\s*name\s*:\s*"([^\"]+)"', swift_text,
            )
            if (
                sorted(target_references) != sorted(
                    current_targets | {"llamadart_litert_lm_flutter"}
                )
                or len(re.findall(r'\.target\s*\(', swift_text)) != len(target_references)
            ):
                raise ReleaseError(
                    "Modern LiteRT-LM provider removal has unexpected target references"
                )
            dependency_lists = re.findall(
                r'\bdependencies\s*:\s*\[(.*?)\]\s*,\s*linkerSettings\s*:',
                swift_text, re.DOTALL,
            )
            if len(dependency_lists) != 1 or re.sub(
                r'\.target\s*\(\s*name\s*:\s*"[^\"]+"\s*,\s*condition\s*:\s*'
                r'\.when\s*\(\s*platforms\s*:\s*\[[^]]*\]\s*\)\s*\)',
                "", dependency_lists[0] if dependency_lists else "",
            ).strip(" \t\r\n,"):
                raise ReleaseError(
                    "Modern LiteRT-LM provider removal has malformed dependency inventory"
                )
            for target, platforms in (
                ("CLiteRTLMMac", ".macOS"),
                ("LiteRtLm", ".iOS, .macOS"),
                ("CLiteRTLM", ".iOS"),
                ("LiteRtMetalAccelerator", ".iOS"),
                ("LiteRtTopKMetalSampler", ".iOS"),
            ):
                dependencies = re.findall(
                    rf'\.target\(name: "{target}", condition: '
                    r'\.when\(platforms: \[([^]]*)\]\)\)',
                    swift_text,
                )
                if (
                    dependencies != [platforms]
                    or swift_text.count(f'name: "{target}"') != 2
                ):
                    raise ReleaseError(
                        "Modern LiteRT-LM provider removal requires the "
                        f"maintained {target} platform dependency"
                    )
            swift_text = replace_one(
                swift_text,
                r'(?ms)^[ \t]*nativeRepoBinaryTarget\(\s*'
                r'name: "GemmaModelConstraintProvider",.*?^[ \t]*\),\n',
                "",
                "LiteRT-LM unused iOS provider binary target",
            )
            swift_text = replace_one(
                swift_text,
                r'(?m)^[ \t]*\.target\(name: "GemmaModelConstraintProvider", '
                r'condition: \.when\(platforms: \[\.iOS\]\)\),\n',
                "",
                "LiteRT-LM unused provider must have exactly one iOS dependency",
            )
        elif (
            "GemmaModelConstraintProvider" in expected_targets
            and current_targets == expected_targets - {"GemmaModelConstraintProvider"}
        ):
            pass  # Repair a previously generated schema-2 manifest.
        elif current_targets != expected_targets:
            raise ReleaseError(
                "LiteRT-LM Package.swift binary targets do not match the legacy "
                "or schema-2 owner inventory"
            )
        if _litert_is_v1_compatibility_tag(
            manifest["upstream"]["compatibilityTag"]
        ) and any(
            sampler in swift_text for sampler in obsolete_samplers
        ):
            raise ReleaseError(
                "LiteRT-LM Package.swift has malformed or unexpected obsolete sampler references"
            )
        if (
            "GemmaModelConstraintProvider" not in expected_targets
            and "GemmaModelConstraintProvider" in swift_text
        ):
            raise ReleaseError(
                "LiteRT-LM Package.swift has malformed or unexpected provider references"
            )

    if manifest.get("schemaVersion") == 2 and "GemmaModelConstraintProvider" in expected_targets:
        current_targets = {
            name for name, _ in swift_native_repo_binary_targets(
                swift_text, tag_variable="liteRtLmTag", current_tag=original_tag,
            )
        }
        if "GemmaModelConstraintProvider" not in current_targets:
            pattern = re.compile(
                r'(?m)(?P<indent>^[ \t]*)nativeRepoBinaryTarget\(\s*'
                r'name: "CLiteRTLMMac",.*?^[ \t]*\),',
                re.MULTILINE | re.DOTALL,
            )
            matches = list(pattern.finditer(swift_text))
            if len(matches) != 1:
                raise ReleaseError("LiteRT-LM macOS compatibility target is ambiguous")
            match = matches[0]
            provider = match.group().replace("CLiteRTLMMac", "GemmaModelConstraintProvider")
            swift_text = swift_text[:match.end()] + "\n" + provider + swift_text[match.end():]
            swift_text = replace_one(
                swift_text,
                r'(?m)(?P<indent>^[ \t]*)(?P<target>\.target\(name: "CLiteRTLMMac", condition: \.when\(platforms: \[\.macOS\]\)\),)',
                r'\g<indent>\g<target>\n\g<indent>.target(name: "GemmaModelConstraintProvider", condition: .when(platforms: [.iOS])),',
                "LiteRT-LM required iOS provider dependency",
            )

        provider_dependencies = re.findall(
            r'\.target\(name: "GemmaModelConstraintProvider", condition: \.when\(platforms: \[([^]]*)\]\)\)',
            swift_text,
        )
        if provider_dependencies != [".iOS"]:
            raise ReleaseError("LiteRT-LM required provider must have exactly one iOS dependency")

    apple_targets = swift_native_repo_binary_targets(
        swift_text,
        tag_variable="liteRtLmTag",
        current_tag=original_tag,
    )
    if manifest.get("schemaVersion") == 2 and {
        target_name for target_name, _ in apple_targets
    } != litert_schema2_apple_targets(manifest, resolved_tag):
        raise ReleaseError(
            "LiteRT-LM Package.swift binary targets do not match schema-2 owner inventory"
        )
    swift_text = replace_one(
        swift_text,
        r'let liteRtLmTag = "[^"]+"',
        f'let liteRtLmTag = "{resolved_tag}"',
        "LiteRT-LM Package.swift tag",
    )
    for target_name, asset_template in apple_targets:
        checksum = release_asset_checksum(
            release,
            asset_template.format(tag=resolved_tag),
            repo=repo,
        )
        swift_text = replace_swift_binary_target_checksum(
            swift_text,
            target_name,
            checksum,
        )
    return swift_text


def litert_lm_companion_template_hash(swift_text: str) -> str:
    """Match the full-manifest normalization used by the macOS build hook."""
    normalized, count = re.subn(
        r'(?m)^let liteRtLmTag = "[^"\n]+"$',
        'let liteRtLmTag = "PIN"',
        swift_text.replace("\r\n", "\n"),
    )
    if count != 1:
        raise ReleaseError("Expected one LiteRT-LM companion template tag")
    normalized = re.sub(
        r'checksum: "[0-9a-f]{64}"', 'checksum: "CHECKSUM"', normalized,
    )
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def replace_litert_lm_companion_template_hash(
    hook_text: str,
    *,
    original_swift: str,
    prepared_swift: str,
    resolved_tag: str,
) -> str:
    pattern = (
        r"(?m)(^const _liteRtLmCompanionManifestTemplateSha256 =\s*')"
        r"([0-9a-f]{64})(';)"
    )
    matches = list(re.finditer(pattern, hook_text))
    if len(matches) != 1:
        raise ReleaseError("Expected one reviewed LiteRT-LM companion template hash")
    if matches[0].group(2) != litert_lm_companion_template_hash(original_swift):
        raise ReleaseError(
            "The hook does not admit the reviewed LiteRT-LM companion template; "
            "review its manifest contract before syncing"
        )
    prepared_tag = swift_variable_value(
        prepared_swift, "liteRtLmTag", "rendered LiteRT-LM companion tag",
    )
    if prepared_tag != resolved_tag:
        raise ReleaseError("The rendered LiteRT-LM companion tag differs from the resolved tag")
    # The production renderer validates the owner inventory and known target
    # transition before this contract is staged in the same atomic write.
    return replace_one(
        hook_text, pattern,
        r"\g<1>" + litert_lm_companion_template_hash(prepared_swift) + r"\g<3>",
        "LiteRT-LM companion template hash",
    )


def swift_variable_value(
    swift_text: str,
    variable_name: str,
    description: str,
) -> str:
    match = re.search(
        rf'\blet\s+{re.escape(variable_name)}\s*=\s*"([^"]+)"',
        swift_text,
    )
    if not match:
        raise ReleaseError(f"Could not read {description}")
    return match.group(1)


def swift_native_repo_binary_targets(
    swift_text: str,
    *,
    tag_variable: str,
    current_tag: str,
) -> list[tuple[str, str]]:
    pattern = re.compile(
        r'nativeRepoBinaryTarget\(\s*name:\s*"(?P<name>[^"]+)"'
        r'.*?artifactName:\s*"(?P<artifact_name>[^"]+)"'
        r'.*?checksum:\s*"[0-9a-f]+"',
        re.DOTALL,
    )
    targets: list[tuple[str, str]] = []
    for match in pattern.finditer(swift_text):
        artifact_template = swift_artifact_template(
            match.group("artifact_name"),
            tag_variable=tag_variable,
            current_tag=current_tag,
        )
        targets.append((match.group("name"), artifact_template))
    if not targets:
        raise ReleaseError("Could not find nativeRepoBinaryTarget entries")
    return targets


def swift_artifact_template(
    artifact_name: str,
    *,
    tag_variable: str,
    current_tag: str,
) -> str:
    interpolated_tag = rf"\({tag_variable})"
    if interpolated_tag in artifact_name:
        return artifact_name.replace(interpolated_tag, "{tag}")
    if current_tag in artifact_name:
        return artifact_name.replace(current_tag, "{tag}")
    return artifact_name


def companion_package_root(package_swift_path: Path) -> Path:
    try:
        return package_swift_path.parents[2]
    except IndexError as error:
        raise ReleaseError(
            f"Could not infer companion package root from {package_swift_path}"
        ) from error


def update_companion_package_metadata(
    pending_writes: dict[Path, str],
    package_root: Path,
    repo: str,
    tag: str,
    *,
    bump_version: bool,
) -> str:
    pubspec_path = package_root / "pubspec.yaml"
    readme_path = package_root / "README.md"
    changelog_path = package_root / "CHANGELOG.md"
    if not pubspec_path.exists():
        raise ReleaseError(f"Missing companion package pubspec {pubspec_path}")
    if not readme_path.exists():
        raise ReleaseError(f"Missing companion package README {readme_path}")
    if not changelog_path.exists():
        raise ReleaseError(f"Missing companion package CHANGELOG {changelog_path}")

    pubspec_text = pubspec_path.read_text(encoding="utf-8")
    current_version = companion_pubspec_version(pubspec_text, pubspec_path)
    next_version = (
        bump_patch_version(current_version) if bump_version else current_version
    )
    if bump_version:
        pending_writes[pubspec_path] = replace_pubspec_version(
            pubspec_text,
            next_version,
            pubspec_path,
        )

    readme_text = readme_path.read_text(encoding="utf-8")
    readme_text = replace_one(
        readme_text,
        r"The Apple SwiftPM manifest pins\s+`[^`]+`\.",
        f"The Apple SwiftPM manifest pins `{repo}@{tag}`.",
        f"{package_root.name} README native pin",
    )
    readme_text = replace_readme_dependency_version(
        readme_text,
        package_root.name,
        next_version,
    )
    pending_writes[readme_path] = readme_text

    if bump_version:
        changelog_text = changelog_path.read_text(encoding="utf-8")
        pending_writes[changelog_path] = prepend_companion_changelog_release(
            changelog_text,
            next_version,
            f"- Updated Apple SwiftPM native pin to `{repo}@{tag}`.",
            repo,
        )
    else:
        changelog_text = changelog_path.read_text(encoding="utf-8")
        pending_writes[changelog_path] = update_companion_changelog_unreleased(
            changelog_text,
            f"- Updated Apple SwiftPM native pin to `{repo}@{tag}`.",
            repo,
        )

    return next_version


def update_llama_cpp_project_docs(
    pending_writes: dict[Path, str],
    doc_paths: list[Path],
    changelog_path: Path,
    repo: str,
    tag: str,
) -> None:
    for doc_path in doc_paths:
        if not doc_path.exists():
            raise ReleaseError(f"Missing project native pin doc {doc_path}")
        doc_text = doc_path.read_text(encoding="utf-8")
        updated_doc_text = replace_llama_cpp_native_doc_references(
            doc_text,
            repo,
            tag,
        )
        if updated_doc_text == doc_text:
            if tag not in doc_text:
                raise ReleaseError(
                    f"Could not update llama.cpp native pin references in {doc_path}"
                )
        else:
            pending_writes[doc_path] = updated_doc_text

    if not changelog_path.exists():
        raise ReleaseError(f"Missing project CHANGELOG {changelog_path}")
    changelog_text = changelog_path.read_text(encoding="utf-8")
    pending_writes[changelog_path] = update_core_changelog_native_pin(
        changelog_text,
        repo,
        tag,
    )


def replace_llama_cpp_native_doc_references(
    doc_text: str,
    repo: str,
    tag: str,
) -> str:
    replacements = (
        (
            rf"(llamadart_native_tag:\s*){_NATIVE_DOC_TAG_PATTERN}",
            rf"\g<1>{tag}",
        ),
        (
            rf"({re.escape(repo)}@){_NATIVE_DOC_TAG_PATTERN}",
            rf"\g<1>{tag}",
        ),
        (
            rf"(llamadart-native-[a-z0-9_-]+-)"
            rf"{_NATIVE_DOC_TAG_PATTERN}(?=\.tar\.gz`)",
            rf"\g<1>{tag}",
        ),
        (
            rf"(default native tag `){_NATIVE_DOC_TAG_PATTERN}(`)",
            rf"\g<1>{tag}\2",
        ),
        (
            rf"(llamadart-native` tag\s+`){_NATIVE_DOC_TAG_PATTERN}(`)",
            rf"\g<1>{tag}\2",
        ),
        (
            rf"(module availability by bundle \(`){_NATIVE_DOC_TAG_PATTERN}(`\))",
            rf"\g<1>{tag}\2",
        ),
    )
    for pattern, replacement in replacements:
        doc_text = re.sub(pattern, replacement, doc_text)
    return doc_text


def update_project_doc_dependency_versions(
    pending_writes: dict[Path, str],
    doc_paths: list[Path],
    dependency_versions: dict[str, str],
) -> None:
    replacement_counts = {
        package_name: 0 for package_name in dependency_versions
    }
    for doc_path in doc_paths:
        if not doc_path.exists():
            raise ReleaseError(f"Missing project dependency doc {doc_path}")
        doc_text = pending_writes.get(doc_path)
        if doc_text is None:
            doc_text = doc_path.read_text(encoding="utf-8")
        for package_name, version in dependency_versions.items():
            doc_text, count = replace_dependency_version(
                doc_text,
                package_name,
                version,
            )
            replacement_counts[package_name] += count
        pending_writes[doc_path] = doc_text

    missing = [
        package_name
        for package_name, count in replacement_counts.items()
        if count == 0
    ]
    if missing:
        raise ReleaseError(
            "Could not replace project docs dependency versions for "
            + ", ".join(missing)
        )


def update_core_changelog_native_pin(
    changelog_text: str,
    repo: str,
    tag: str,
) -> str:
    native_version = parse_native_release_tag(tag)
    if native_version.wrapper_revision > 0:
        base_tag = native_version.upstream_tag
        entry = (
            "- Updated the default llama.cpp native runtime pin to\n"
            f"  `{repo}@{tag}`, keeping the `{base_tag}` llama.cpp\n"
            "  ABI/bindings while picking up wrapper-only native fixes. Refreshed\n"
            "  the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum and\n"
            "  aligned current README/website native override docs."
        )
    else:
        entry = (
            "- Updated the default llama.cpp native runtime pin to\n"
            f"  `{repo}@{tag}`, regenerated matching Dart FFI bindings, refreshed\n"
            "  the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and\n"
            "  aligned current README/website native override docs."
        )
    heading_match = re.search(r"(?m)^## Unreleased\s*\n+", changelog_text)
    if not heading_match:
        return f"## Unreleased\n\n{entry}\n\n{changelog_text.lstrip()}"

    body_start = heading_match.end()
    next_heading = re.search(r"(?m)^##\s+", changelog_text[body_start:])
    body_end = (
        body_start + next_heading.start() if next_heading else len(changelog_text)
    )
    body = changelog_text[body_start:body_end]
    old_entry_pattern = re.compile(
        r"^[-*] Updated the default llama\.cpp native runtime pin to[^\n]*"
        r"(?:\n(?![-*] |#{1,6}(?:[ \t]|$))[^\S\n]*\S[^\n]*)*\n?(?:[^\S\n]*\n)*",
        re.MULTILINE,
    )
    existing_entry = old_entry_pattern.search(body)
    if existing_entry and f"`{repo}@{tag}`" in existing_entry.group(0):
        return changelog_text
    body = old_entry_pattern.sub("", body).lstrip()
    return (
        changelog_text[:body_start]
        + f"{entry}\n\n{body}"
        + changelog_text[body_end:]
    )


def companion_pubspec_version(pubspec_text: str, pubspec_path: Path) -> str:
    match = re.search(
        r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$",
        pubspec_text,
        re.MULTILINE,
    )
    if not match:
        raise ReleaseError(f"Could not read semver version from {pubspec_path}")
    return match.group(1)


def bump_patch_version(version: str) -> str:
    major, minor, patch = version.split(".")
    return f"{major}.{minor}.{int(patch) + 1}"


def replace_pubspec_version(
    pubspec_text: str,
    version: str,
    pubspec_path: Path,
) -> str:
    updated, count = re.subn(
        r"^version:\s*[0-9]+\.[0-9]+\.[0-9]+\s*$",
        f"version: {version}",
        pubspec_text,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise ReleaseError(f"Could not replace version in {pubspec_path}")
    return updated


def replace_readme_dependency_version(
    readme_text: str,
    package_name: str,
    version: str,
) -> str:
    updated, count = replace_dependency_version(
        readme_text,
        package_name,
        version,
        count=1,
    )
    if count != 1:
        raise ReleaseError(f"Could not replace {package_name} README version")
    return updated


def replace_dependency_version(
    text: str,
    package_name: str,
    version: str,
    *,
    count: int = 0,
) -> tuple[str, int]:
    pattern = rf"(\s{re.escape(package_name)}:\s*\^)[0-9]+\.[0-9]+\.[0-9]+"
    return re.subn(pattern, rf"\g<1>{version}", text, count=count)


def prepend_companion_changelog_release(
    changelog_text: str,
    version: str,
    entry: str,
    repo: str,
) -> str:
    old_entry_pattern = re.compile(
        rf"^[*-] Updated Apple SwiftPM native pin to\s+`{re.escape(repo)}@[^`]+`\.\n?",
        re.MULTILINE,
    )
    unreleased_match = re.search(r"(?m)^## Unreleased\s*\n+", changelog_text)
    if unreleased_match:
        body_start = unreleased_match.end()
        next_heading = re.search(r"(?m)^##\s+", changelog_text[body_start:])
        body_end = (
            body_start + next_heading.start()
            if next_heading
            else len(changelog_text)
        )
        body = old_entry_pattern.sub(
            "", changelog_text[body_start:body_end]
        ).strip()
        release_body = entry if not body else f"{entry}\n\n{body}"
        remaining = (
            changelog_text[: unreleased_match.start()]
            + changelog_text[body_end:]
        ).lstrip()
        return f"## {version}\n\n{release_body}\n\n{remaining}"

    heading_match = re.search(
        rf"(?m)^## {re.escape(version)}\s*\n+",
        changelog_text,
    )
    if not heading_match:
        return f"## {version}\n\n{entry}\n\n{changelog_text.lstrip()}"

    body_start = heading_match.end()
    next_heading = re.search(r"(?m)^##\s+", changelog_text[body_start:])
    body_end = (
        body_start + next_heading.start() if next_heading else len(changelog_text)
    )
    body = old_entry_pattern.sub("", changelog_text[body_start:body_end]).strip()
    new_body = f"{entry}\n\n"
    if body:
        new_body = f"{entry}\n\n{body}\n\n"
    return changelog_text[:body_start] + new_body + changelog_text[body_end:]


def _changelog_section_span(
    changelog_text: str,
    heading: str,
) -> tuple[int, int, int] | None:
    heading_match = re.search(
        rf"(?m)^## {re.escape(heading)}\s*\n+", changelog_text
    )
    if not heading_match:
        return None
    body_start = heading_match.end()
    next_heading = re.search(r"(?m)^##\s+", changelog_text[body_start:])
    body_end = (
        body_start + next_heading.start() if next_heading else len(changelog_text)
    )
    return heading_match.start(), body_start, body_end


def update_companion_changelog_unreleased(
    changelog_text: str,
    entry: str,
    repo: str,
) -> str:
    """Records `entry` under `## Unreleased`, replacing any earlier pin entry.

    When the newest released section that records a `repo` pin already names
    the tag in `entry`, the pin is published: no `Unreleased` entry is added, a
    stale pin entry left under `Unreleased` is removed, and an emptied section
    is dropped.
    """
    old_entry_pattern = re.compile(
        rf"^[*-] Updated Apple SwiftPM native pin to\s+`{re.escape(repo)}@[^`]+`\.\n?",
        re.MULTILINE,
    )
    pin_pattern = re.compile(
        rf"[*-] Updated Apple SwiftPM native pin to[^`]*`{re.escape(repo)}@([^`]+)`"
    )
    unreleased = _changelog_section_span(changelog_text, "Unreleased")
    released_text = (
        changelog_text if unreleased is None else changelog_text[unreleased[2] :]
    )
    target_pin = pin_pattern.search(entry)
    published_pin = pin_pattern.search(released_text)
    already_released = (
        target_pin is not None
        and published_pin is not None
        and published_pin.group(1) == target_pin.group(1)
    )
    if unreleased is None:
        if already_released:
            return changelog_text
        return f"## Unreleased\n\n{entry}\n\n{changelog_text.lstrip()}"

    heading_start, body_start, body_end = unreleased
    body = old_entry_pattern.sub("", changelog_text[body_start:body_end]).strip()
    if already_released:
        if not body:
            return changelog_text[:heading_start] + changelog_text[body_end:]
        new_body = f"{body}\n\n"
    elif body:
        new_body = f"{entry}\n\n{body}\n\n"
    else:
        new_body = f"{entry}\n\n"
    return changelog_text[:body_start] + new_body + changelog_text[body_end:]


def write_github_output(values: dict[str, str]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    with open(output_path, "a", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
