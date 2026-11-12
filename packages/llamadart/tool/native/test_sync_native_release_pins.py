from __future__ import annotations

import copy
import hashlib
import http.client
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest.mock import patch
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parent))

import sync_native_release_pins as pins  # noqa: E402
from sync_native_release_pins import (  # noqa: E402
    ReleaseError,
    LEGACY_SCHEMA1_RELEASES,
    atomic_write_many,
    fetch_release,
    litert_lm_bundle_names,
    litert_schema2_bundle_required_libraries,
    litert_lm_runtime_version,
    normalize_litert_lm_release_tag,
    prepare_litert_lm_package_swift,
    replace_litert_lm_bundle_required_libraries,
    require_exact_keys,
    required_litert_release_asset_names,
    validate_litert_lm_transition,
    validate_litert_lm_release_manifest,
    validate_litert_release_asset_inventory,
)


LEGACY_LITERT_SWIFT = Path(__file__).resolve().parent / "fixtures/litert_lm_legacy_Package.swift"
MODERN_LITERT_SWIFT = Path(__file__).resolve().parent / "fixtures/litert_lm_modern_provider_Package.swift"

UPSTREAM_COMMIT = "ba82499873945908bf8bcfc96e955d0677eb1fa1"
NATIVE_COMMIT = "451ba0ce7c366972b4dc0e58f08ffe590958f943"
DEVELOPMENT_TAG = "gba8249987394"

SIGNED_URL = "https://objects.example.invalid/asset?token=super-secret"


class _FakeResponse:
    def __init__(
        self, payload: bytes = b"", read_error: BaseException | None = None
    ) -> None:
        self._payload = payload
        self._read_error = read_error

    def __enter__(self) -> _FakeResponse:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self, *args: object) -> bytes:
        if self._read_error is not None:
            raise self._read_error
        payload, self._payload = self._payload, b""
        return payload


def _release_with_asset(asset_name: str, tag: str = "v0.16.0") -> dict:
    return {
        "tag_name": tag,
        "assets": [
            {"name": asset_name, "browser_download_url": SIGNED_URL},
        ],
    }


PROBE_TOKEN = "ghp-llamadart-transport-probe-9f2c4e"


class GithubAuthTransportTest(unittest.TestCase):
    """The real token must reach GitHub while staying out of every diagnostic."""

    def setUp(self) -> None:
        self.seen: list[str | None] = []
        self.status = 200
        test = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                test.seen.append(self.headers.get("Authorization"))
                body = json.dumps({"tag_name": "v0.16.0", "assets": []}).encode()
                self.send_response(test.status)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args: object) -> None:
                return

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        self.url = f"http://127.0.0.1:{server.server_address[1]}/release.json"

    def _env(self, name: str = "") -> dict[str, str]:
        env = {
            k: v
            for k, v in os.environ.items()
            if k not in ("GH_TOKEN", "GITHUB_TOKEN")
        }
        if name:
            env[name] = PROBE_TOKEN
        return env

    def test_auth_header_carries_the_real_token(self) -> None:
        for name in ("GH_TOKEN", "GITHUB_TOKEN"):
            with self.subTest(variable=name), patch.dict(
                os.environ, self._env(name), clear=True
            ):
                self.assertEqual(
                    pins.github_auth_header(),
                    {"Authorization": f"Bearer {PROBE_TOKEN}"},
                )
                self.assertEqual(
                    pins.github_api_headers()["Authorization"],
                    f"Bearer {PROBE_TOKEN}",
                )

    def test_no_auth_header_without_a_token(self) -> None:
        with patch.dict(os.environ, self._env(), clear=True):
            self.assertEqual(pins.github_auth_header(), {})

    def test_transport_sends_the_real_token(self) -> None:
        with patch.dict(os.environ, self._env("GH_TOKEN"), clear=True):
            payload = pins.read_release_url(
                self.url, context="probe", headers=pins.github_api_headers()
            )
        self.assertEqual(self.seen, [f"Bearer {PROBE_TOKEN}"])
        self.assertEqual(json.loads(payload)["tag_name"], "v0.16.0")

    def test_failures_never_echo_the_token(self) -> None:
        self.status = 404
        with patch.dict(os.environ, self._env("GH_TOKEN"), clear=True):
            with self.assertRaises(ReleaseError) as raised:
                pins.read_release_url(
                    self.url, context="probe", headers=pins.github_api_headers()
                )
        self.assertEqual(self.seen, [f"Bearer {PROBE_TOKEN}"])
        cause = raised.exception.__cause__
        message = f"{raised.exception}{cause}"
        if isinstance(cause, urllib.error.HTTPError):
            cause.close()
        self.assertIn("HTTP 404", message)
        self.assertNotIn(PROBE_TOKEN, message)
        self.assertNotIn(self.url, str(raised.exception))


class ReleaseTransportFailureTest(unittest.TestCase):
    def setUp(self) -> None:
        for name, value in (
            ("HTTP_RETRY_DELAY_SECONDS", 0.0),
            ("HTTP_SOCKET_TIMEOUT_SECONDS", 0.25),
        ):
            patcher = patch.object(pins, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def _http_error(self, code: int) -> urllib.error.HTTPError:
        error = urllib.error.HTTPError(SIGNED_URL, code, SIGNED_URL, {}, None)
        self.addCleanup(error.close)
        return error

    def _assert_actionable(self, message: str, *expected: str) -> None:
        for fragment in expected:
            self.assertIn(fragment, message)
        self.assertNotIn("Traceback", message)
        self.assertNotIn("objects.example.invalid", message)
        self.assertNotIn("super-secret", message)

    def test_dns_failure_is_retried_and_reported_without_the_url(self) -> None:
        error = urllib.error.URLError(socket.gaierror(SIGNED_URL))
        with patch.object(
            pins.urllib.request, "urlopen", side_effect=error
        ) as urlopen:
            with self.assertRaises(ReleaseError) as raised:
                fetch_release("owner/repo", "v0.16.0")

        self._assert_actionable(
            str(raised.exception),
            "Failed to fetch release owner/repo@v0.16.0",
            "DNS lookup failed",
        )
        self.assertEqual(urlopen.call_count, pins.HTTP_MAX_ATTEMPTS)
        self.assertEqual(
            {call.kwargs["timeout"] for call in urlopen.call_args_list},
            {pins.HTTP_SOCKET_TIMEOUT_SECONDS},
        )

    def test_permanent_http_error_is_not_retried(self) -> None:
        error = self._http_error(404)
        with patch.object(
            pins.urllib.request, "urlopen", side_effect=error
        ) as urlopen:
            with self.assertRaises(ReleaseError) as raised:
                fetch_release("owner/repo", "v0.16.0")

        self._assert_actionable(
            str(raised.exception), "owner/repo@v0.16.0", "HTTP 404"
        )
        urlopen.assert_called_once()

    def test_transient_http_error_is_retried_then_reported(self) -> None:
        error = self._http_error(503)
        with patch.object(
            pins.urllib.request, "urlopen", side_effect=error
        ) as urlopen:
            with self.assertRaises(ReleaseError) as raised:
                fetch_release("owner/repo", "v0.16.0")

        self._assert_actionable(str(raised.exception), "HTTP 503")
        self.assertEqual(urlopen.call_count, pins.HTTP_MAX_ATTEMPTS)

    def test_nontransient_os_error_is_not_retried(self) -> None:
        with patch.object(
            pins.urllib.request, "urlopen", side_effect=OSError(SIGNED_URL)
        ) as urlopen:
            with self.assertRaises(ReleaseError) as raised:
                fetch_release("owner/repo", "v0.16.0")
        self._assert_actionable(str(raised.exception), "network error")
        urlopen.assert_called_once()

    def test_connection_timeout_is_reported_with_the_bound(self) -> None:
        with patch.object(
            pins.urllib.request, "urlopen", side_effect=TimeoutError(SIGNED_URL)
        ):
            with self.assertRaises(ReleaseError) as raised:
                fetch_release("owner/repo", "v0.16.0")

        self._assert_actionable(
            str(raised.exception),
            f"timed out (socket {pins.HTTP_SOCKET_TIMEOUT_SECONDS:g}s, "
            f"total {pins.HTTP_TOTAL_TIMEOUT_SECONDS:g}s)",
        )

    def test_interrupted_asset_download_is_reported(self) -> None:
        with patch.object(
            pins.urllib.request,
            "urlopen",
            side_effect=lambda *a, **k: _FakeResponse(
                read_error=http.client.IncompleteRead(b"partial")
            ),
        ) as urlopen:
            with self.assertRaises(ReleaseError) as raised:
                pins.release_asset_bytes(
                    _release_with_asset("bundle.tar.gz"),
                    "bundle.tar.gz",
                    repo="owner/repo",
                    tag="v0.16.0",
                    release_json_dir="",
                )

        self._assert_actionable(
            str(raised.exception),
            "Failed to read release asset bundle.tar.gz (owner/repo@v0.16.0)",
            "interrupted download",
        )
        self.assertEqual(urlopen.call_count, pins.HTTP_MAX_ATTEMPTS)

    def test_invalid_manifest_payloads_are_release_errors(self) -> None:
        for payload in (b"{not json", b"\xff\xfe", b'"a string"'):
            with self.subTest(payload=payload), patch.object(
                pins.urllib.request,
                "urlopen",
                return_value=_FakeResponse(payload),
            ):
                with self.assertRaises(ReleaseError) as raised:
                    pins.release_asset_json(
                        _release_with_asset("assets.json"), "assets.json"
                    )
                self._assert_actionable(str(raised.exception), "assets.json")

        release = _release_with_asset("assets.json")
        release["assets"][0]["fixture_json"] = []
        with self.assertRaisesRegex(ReleaseError, "must be a JSON object"):
            pins.release_asset_json(release, "assets.json")

    def test_checksum_fallback_download_failure_names_the_asset(self) -> None:
        error = self._http_error(403)
        with patch.object(pins.urllib.request, "urlopen", side_effect=error):
            with self.assertRaises(ReleaseError) as raised:
                pins.release_asset_checksum(
                    _release_with_asset("SHA256SUMS"),
                    "SHA256SUMS",
                    repo="owner/repo",
                )

        self._assert_actionable(
            str(raised.exception),
            "Failed to read release asset SHA256SUMS (owner/repo@v0.16.0)",
            "HTTP 403",
        )

    def test_missing_fixture_is_actionable(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ReleaseError) as raised:
                fetch_release("owner/repo", "v0.16.0", temp)

        self._assert_actionable(
            str(raised.exception),
            "Failed to fetch release owner/repo@v0.16.0",
            "cannot read fixture",
        )

    def test_transient_failure_recovers_on_retry(self) -> None:
        payload = json.dumps({"tag_name": "v0.16.0", "assets": []}).encode("utf-8")
        with patch.object(
            pins.urllib.request,
            "urlopen",
            side_effect=[
                urllib.error.URLError(ConnectionResetError("reset")),
                _FakeResponse(payload),
            ],
        ) as urlopen:
            release = fetch_release("owner/repo", "v0.16.0")

        self.assertEqual(release["tag_name"], "v0.16.0")
        self.assertEqual(urlopen.call_count, 2)

    def test_invalid_url_is_typed_and_redacted(self) -> None:
        secret_url = "not-a-url?token=super-secret"
        with self.assertRaises(ReleaseError) as raised:
            pins.read_release_url(secret_url, context="Failed to read asset")
        self._assert_actionable(
            str(raised.exception), "Failed to read asset", "invalid download URL"
        )

    def test_streaming_read_cannot_exceed_the_overall_deadline(self) -> None:
        with patch.object(
            pins.time,
            "monotonic",
            side_effect=[
                0.0,
                0.0,
                0.0,
                pins.HTTP_TOTAL_TIMEOUT_SECONDS + 1,
                pins.HTTP_TOTAL_TIMEOUT_SECONDS + 1,
            ],
        ), patch.object(
            pins.urllib.request, "urlopen", return_value=_FakeResponse(b"payload")
        ) as urlopen:
            with self.assertRaises(ReleaseError) as raised:
                pins.read_release_url(SIGNED_URL, context="Failed to read asset")

        self._assert_actionable(str(raised.exception), "timed out")
        urlopen.assert_called_once()

    def test_invalid_digest_and_asset_inventory_are_rejected(self) -> None:
        release = _release_with_asset("bundle.tar.gz")
        release["assets"][0]["digest"] = "sha512:abcd"
        with self.assertRaisesRegex(ReleaseError, "invalid GitHub SHA-256 digest"):
            pins.release_asset_checksum(release, "bundle.tar.gz")

        duplicate = _release_with_asset("bundle.tar.gz")
        duplicate["assets"].append(dict(duplicate["assets"][0]))
        with self.assertRaisesRegex(ReleaseError, "duplicates asset"):
            pins.release_asset_checksum(duplicate, "bundle.tar.gz")


def _schema2_fixture_payloads() -> tuple[dict, dict]:
    fixture_root = Path(__file__).resolve().parent / "fixtures"
    manifest = json.loads(
        (fixture_root / "litert_lm_schema2_owner_manifest.json").read_text(
            encoding="utf-8"
        )
    )
    release = json.loads(
        (fixture_root / "litert_lm_schema2_owner_release.json").read_text(
            encoding="utf-8"
        )
    )
    return manifest, release


def _set_release_asset_digest(release: dict, name: str, digest: str) -> None:
    asset = next(asset for asset in release["assets"] if asset["name"] == name)
    asset["digest"] = f"sha256:{digest}"


def _materialize_schema2_release_fixtures(
    fixture_dir: Path,
    manifest: dict,
    release: dict,
) -> None:
    repo = "leehack/litert-lm-native"
    tag = manifest["release"]["tag"]
    manifest_bytes = json.dumps(manifest).encode("utf-8")
    (fixture_dir / f"{repo.replace('/', '__')}__{tag}__manifest.json").write_bytes(
        manifest_bytes
    )
    _set_release_asset_digest(
        release,
        "manifest.json",
        hashlib.sha256(manifest_bytes).hexdigest(),
    )
    checksum_text = "".join(
        f"{artifact['sha256']}  {artifact['path']}\n"
        for artifact in manifest["artifacts"]
    ).encode("utf-8")
    (fixture_dir / f"{repo.replace('/', '__')}__{tag}__SHA256SUMS").write_bytes(
        checksum_text
    )
    _set_release_asset_digest(
        release,
        "SHA256SUMS",
        hashlib.sha256(checksum_text).hexdigest(),
    )
    upstream_ref = manifest["upstream"]["tag"] or manifest["upstream"]["commit"]
    (fixture_dir / f"google-ai-edge__LiteRT-LM__{upstream_ref}__commit.json").write_text(
        json.dumps({"sha": manifest["upstream"]["commit"]}),
        encoding="utf-8",
    )
    (fixture_dir / f"{repo.replace('/', '__')}__{tag}__commit.json").write_text(
        json.dumps({"sha": manifest["native"]["commit"]}),
        encoding="utf-8",
    )
    (fixture_dir / f"{repo.replace('/', '__')}__{tag}.json").write_text(
        json.dumps(release),
        encoding="utf-8",
    )


_MACOS_SPM_COMPANION_DIGEST = "b" * 64


def _v018_litert_swift(tag: str = "v0.16.0-native.2") -> str:
    # Historical schema-2 inventories retain samplers removed in v0.19.0.
    source = (
        Path(__file__).resolve().parent
        / "fixtures/litert_lm_v018_samplers_Package.swift"
    ).read_text(encoding="utf-8")
    return re.sub(r'let liteRtLmTag = "[^"]+"', f'let liteRtLmTag = "{tag}"', source)


def _add_macos_bundle_library(manifest: dict, library: str) -> None:
    platform = next(item for item in manifest["platforms"]
        if item["platform"] == "macos" and item["arch"] == "arm64")
    companion = f"bin/macos/arm64/{library}"
    platform["artifactPaths"].append(companion)
    artifact = dict(next(item for item in manifest["artifacts"]
        if item["path"] == "bin/macos/arm64/libLiteRtLm.dylib"))
    artifact.update(path=companion, fileName=library)
    manifest["artifacts"].append(artifact)


def _add_macos_spm_companions(manifest: dict, release: dict) -> None:
    """Mirrors the v0.18.0 macOS GPU inventory and its flat-dylib xcframeworks."""
    tag = manifest["release"]["tag"]
    for library, target in (
        ("libLiteRt.dylib", "LiteRt"),
        ("libLiteRtTopKWebGpuSampler.dylib", "LiteRtTopKWebGpuSampler"),
        ("libLiteRtWebGpuAccelerator.dylib", "LiteRtWebGpuAccelerator"),
        ("libwebgpu_dawn.dylib", "WebgpuDawn"),
    ):
        _add_macos_bundle_library(manifest, library)
        archive = f"litert-lm-native-apple-{target}-xcframework-{tag}.zip"
        artifact = dict(next(item for item in manifest["artifacts"]
            if item["path"].startswith("dist/spm/")))
        artifact.update(
            path=f"dist/spm/{tag}/{archive}",
            fileName=archive,
            sha256=_MACOS_SPM_COMPANION_DIGEST,
        )
        manifest["artifacts"].append(artifact)
        release["assets"].append(
            {"name": archive, "digest": "sha256:" + _MACOS_SPM_COMPANION_DIGEST}
        )


def _hook_for_litert_swift(hook: str, swift: str) -> str:
    return re.sub(
        r"(const _liteRtLmCompanionManifestTemplateSha256 =\s*')[0-9a-f]{64}(';)",
        r"\g<1>" + pins.litert_lm_companion_template_hash(swift) + r"\g<2>", hook,
    )


def _run_schema2_sync(
    temp_dir: Path,
    manifest: dict,
    release: dict,
    *,
    include_runtime_dependencies: bool = False,
    current_litert_tag: str = "v0.16.0-native.2",
    allow_stable_rebuild_entry: bool = False,
    starting_swift: str | None = None,
) -> subprocess.CompletedProcess[str]:
    repo_root = temp_dir / "repo"
    source_root = Path(__file__).resolve().parents[2]
    if include_runtime_dependencies:
        shutil.copytree(source_root / "lib", repo_root / "lib")
        (repo_root / ".dart_tool").mkdir(parents=True, exist_ok=True)
        shutil.copyfile(
            source_root / ".dart_tool/package_config.json",
            repo_root / ".dart_tool/package_config.json",
        )
        shutil.copyfile(source_root / "pubspec.yaml", repo_root / "pubspec.yaml")
    for relative_path in (
        "hook/build.dart",
        "lib/src/hook/native_release_pins.dart",
        "lib/src/backends/litert_lm/litert_lm_runtime.dart",
        "tool/macos_litert_lm_prepare_app.sh",
        "README.md",
        "CHANGELOG.md",
        "website/docs/getting-started/installation.md",
        "website/docs/platforms/support-matrix.md",
        "packages/llamadart_litert_lm_flutter/darwin/"
        "llamadart_litert_lm_flutter/Package.swift",
        "packages/llamadart_litert_lm_flutter/pubspec.yaml",
        "packages/llamadart_litert_lm_flutter/README.md",
        "packages/llamadart_litert_lm_flutter/CHANGELOG.md",
    ):
        target = repo_root / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_root / relative_path, target)
    # Historical transition fixtures must not follow the checkout's live pin.
    pins = repo_root / "lib/src/hook/native_release_pins.dart"
    pins.write_text(re.sub(
        r"const liteRtLmReleaseTag = '[^']+';",
        f"const liteRtLmReleaseTag = '{current_litert_tag}';",
        pins.read_text(),
    ))
    swift = repo_root / (
        "packages/llamadart_litert_lm_flutter/darwin/"
        "llamadart_litert_lm_flutter/Package.swift"
    )
    if starting_swift is None:
        shutil.copyfile(LEGACY_LITERT_SWIFT, swift)
    else:
        swift.write_text(starting_swift, encoding="utf-8")
    hook = repo_root / "hook/build.dart"
    hook.write_text(_hook_for_litert_swift(hook.read_text(), swift.read_text()))
    release_dir = temp_dir / "releases"
    release_dir.mkdir()
    _materialize_schema2_release_fixtures(release_dir, manifest, release)
    script = Path(__file__).resolve().parent / "sync_native_release_pins.py"
    return subprocess.run(
        [
            sys.executable,
            str(script),
            *(["--allow-litert-stable-rebuild-entry"] if allow_stable_rebuild_entry else []),
            "--repo-root",
            str(repo_root),
            "--release-json-dir",
            str(release_dir),
            "--llama-cpp-tag",
            "keep",
            "--litert-lm-tag",
            manifest["release"]["tag"],
            "--litert-lm-package-swift",
            "packages/llamadart_litert_lm_flutter/darwin/"
            "llamadart_litert_lm_flutter/Package.swift",
            "--litert-lm-macos-prepare-script",
            "tool/macos_litert_lm_prepare_app.sh",
        ],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=True,
    )


def _run_generated_macos_prepare(
    repo_root: Path,
    library_dir: Path,
    app_dir: Path,
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment.update(
        {
            "LLAMADART_LITERT_LM_ARCH": "arm64",
            "LLAMADART_LITERT_LM_LIB_DIR": str(library_dir),
        }
    )
    return subprocess.run(
        [
            "bash",
            str(repo_root / "tool/macos_litert_lm_prepare_app.sh"),
            str(app_dir),
        ],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=True,
        env=environment,
    )


def _runtime_inventory_function(runtime: str, name: str) -> str:
    match = re.search(
        rf"List<String> {name}\(Abi abi\) \{{\n.*?\n\}}\n", runtime, re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"Missing runtime inventory function {name}")
    return match.group()


def _v019_inventory_projection() -> dict:
    fixture = Path(__file__).resolve().parent / "fixtures/litert_lm_v019_apple_inventory_projection.json"
    return json.loads(fixture.read_text())


def _preserved_runtime_lane_probe_checks(runtime: str, *, c_api_v1: bool) -> str:
    flag = str(c_api_v1).lower()
    prefix = "_liteRtLmV1MacOs" if c_api_v1 else "_liteRtLmMacOs"
    names = {
        "liteRtLmRequiredLibrariesForAbi": (
            "_liteRtLmV1RequiredLibrariesForAbi" if c_api_v1
            else "_liteRtLmLegacyRequiredLibrariesForAbi"
        ),
        "liteRtLmMacOsRequiredFrameworksForAbi": prefix + "RequiredFrameworksForAbi",
        "liteRtLmMacOsRequiredNativeSpmFilesForAbi": prefix + "RequiredNativeSpmFilesForAbi",
    }
    declarations, checks = [], []
    for public, private in names.items():
        expected = "expected" + public
        declarations.append(_runtime_inventory_function(runtime, private).replace(private, expected))
        for abi in ("macosArm64", "macosX64", "linuxArm64", "linuxX64", "windowsX64", "androidArm64"):
            checks.append(
                f"  _expectList('preserved {public} {abi} v1={flag}', "
                f"{public}(Abi.{abi}, cApiV1: {flag}), {expected}(Abi.{abi}));"
            )
    return "\n".join(declarations + checks)


def _runtime_inventory_probe_checks(
    *,
    c_api_v1: bool,
    libraries: dict[str, tuple[str, ...]],
    frameworks: tuple[str, ...],
    native_spm: tuple[str, ...],
) -> str:
    checks = []
    flag = str(c_api_v1).lower()
    for abi in ("macosArm64", "macosX64", "linuxArm64", "linuxX64", "windowsX64", "androidArm64"):
        for function, expected in (
            ("liteRtLmRequiredLibrariesForAbi", libraries.get(abi, ())),
            ("liteRtLmMacOsRequiredLibrariesForAbi", libraries.get(abi, ()) if abi == "macosArm64" else ()),
            ("liteRtLmMacOsRequiredFrameworksForAbi", frameworks if abi == "macosArm64" else ()),
            ("liteRtLmMacOsRequiredNativeSpmFilesForAbi", native_spm if abi == "macosArm64" else ()),
        ):
            checks.append(
                f"  _expectList('{function} {abi} v1={flag}', "
                f"{function}(Abi.{abi}, cApiV1: {flag}), "
                f"<String>{json.dumps(list(expected))});"
            )
    return "\n".join(checks)


def _run_dart_inventory_checks(
    repo_root: Path,
    *,
    checks: str | None = None,
) -> tuple[
    subprocess.CompletedProcess[str],
    subprocess.CompletedProcess[str],
    subprocess.CompletedProcess[str],
]:
    generated = repo_root / "tool/native/generated_litert_lm_inventory.dart"
    generated.parent.mkdir(parents=True, exist_ok=True)
    if checks is None:
        projection = _v019_inventory_projection()
        pinned_tag = pins.current_litert_lm_release_tag(
            (Path(__file__).resolve().parents[2] / pins.DEFAULT_NATIVE_RELEASE_PINS).read_text(
                encoding="utf-8"
            )
        )
        platforms = copy.deepcopy(projection["platforms"])
        for platform in platforms:
            if platform["platform"] == "macos":
                # The v0.19.0 projection predates the pins that stopped shipping
                # the Metal accelerator and the embedded LiteRT companions.
                platform["artifactPaths"] = [
                    path
                    for path in platform["artifactPaths"]
                    if Path(path).name
                    not in {
                        "libLiteRtMetalAccelerator.dylib",
                        "libLiteRt.dylib",
                        "libLiteRtWebGpuAccelerator.dylib",
                    }
                ]
        manifest = {
            "upstream": {"compatibilityTag": projection["compatibilityTag"]},
            "platforms": platforms,
            # The pinned release decides which owner files its hosts load.
            "release": {"tag": pinned_tag},
        }
        bundles = pins.litert_schema2_runtime_required_libraries(
            pins.litert_schema2_bundle_required_libraries(manifest)
        )
        checks = _runtime_inventory_probe_checks(
            c_api_v1=False,
            libraries={
                "macosArm64": ("libCLiteRTLM_mac.dylib", "libLiteRtLm.dylib"),
                "linuxArm64": ("libLiteRtLm.so",),
                "linuxX64": ("libLiteRtLm.so",),
                "windowsX64": ("LiteRtLm.dll",),
            },
            frameworks=(
                "CLiteRTLM_mac.framework/Versions/A/CLiteRTLM_mac",
                "LiteRtLm.framework/Versions/A/LiteRtLm",
            ),
            native_spm=("LiteRtLm.framework/Versions/A/LiteRtLm", "libCLiteRTLM_mac.dylib"),
        )
        checks += "\n" + _runtime_inventory_probe_checks(
            c_api_v1=True,
            libraries={
                "macosArm64": bundles["macos-arm64"],
                "linuxArm64": bundles["linux-arm64"],
                "linuxX64": bundles["linux-x64"],
                "windowsX64": bundles["windows-x64"],
            },
            frameworks=pins._litert_schema2_macos_framework_entries(bundles)["arm64"],
            native_spm=pins.litert_macos_complete_spm_entries(
                bundles, pins.litert_schema2_macos_required_native_spm_files(manifest, projection["releaseTag"]),
            )["arm64"],
        )
    generated.write_text(
        """import 'dart:ffi';
import 'dart:io';

import '../../lib/src/backends/litert_lm/litert_lm_runtime.dart';

void _expectList(String label, List<String> actual, List<String> expected) {
  if (actual.length != expected.length ||
      !actual.asMap().entries.every(
        (entry) => entry.value == expected[entry.key],
      )) {
    throw StateError('$label: $actual != $expected');
  }
}

void main() {
""" + checks + "\n}\n",
        encoding="utf-8",
    )
    format_result = subprocess.run(
        [
            "dart",
            "format",
            "--output=none",
            "--set-exit-if-changed",
            str(repo_root / "lib/src/backends/litert_lm/litert_lm_runtime.dart"),
        ],
        check=False,
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    analyze_result = subprocess.run(
        [
            "dart",
            "analyze",
            str(repo_root / "lib/src/backends/litert_lm/litert_lm_runtime.dart"),
        ],
        check=False,
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    run_result = subprocess.run(
        [
            "dart",
            f"--packages={repo_root / '.dart_tool/package_config.json'}",
            str(generated),
        ],
        check=False,
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    return format_result, analyze_result, run_result


class LiteRtRuntimeInventoryDispatchTest(unittest.TestCase):
    def setUp(self) -> None:
        self.source_root = Path(__file__).resolve().parents[2]
        self.runtime = (self.source_root / "lib/src/backends/litert_lm/litert_lm_runtime.dart").read_text()
        self.projection = _v019_inventory_projection()
        self.manifest = {
            "upstream": {"compatibilityTag": self.projection["compatibilityTag"]},
            "platforms": self.projection["platforms"],
        }
        self.bundles = pins.litert_schema2_bundle_required_libraries(self.manifest)

    def replace(self, runtime: str) -> str:
        updated = pins.replace_litert_lm_runtime_required_libraries(
            runtime, self.bundles, manifest=self.manifest,
        )
        return pins.replace_litert_lm_runtime_macos_inventory(
            updated, self.bundles, manifest=self.manifest,
            resolved_tag=self.projection["releaseTag"],
        )

    def test_v019_sync_generates_only_admitted_inventory_and_is_idempotent(self) -> None:
        # Distinct reviewed companions detect a stale/no-op inventory generator.
        mac = next(item for item in self.manifest["platforms"] if item["platform"] == "macos")
        mac["artifactPaths"].remove("bin/macos/arm64/libGemmaModelConstraintProvider.dylib")
        self.bundles = pins.litert_schema2_bundle_required_libraries(self.manifest)
        updated = self.replace(self.runtime)
        self.assertNotEqual(updated, self.runtime)
        self.assertEqual(self.replace(updated), updated)
        for name in (
            "_liteRtLmLegacyRequiredLibrariesForAbi",
            "_liteRtLmMacOsRequiredFrameworksForAbi",
            "_liteRtLmMacOsRequiredNativeSpmFilesForAbi",
        ):
            self.assertEqual(_runtime_inventory_function(updated, name), _runtime_inventory_function(self.runtime, name))
        for name in (
            "_liteRtLmV1RequiredLibrariesForAbi",
            "_liteRtLmV1MacOsRequiredFrameworksForAbi",
            "_liteRtLmV1MacOsRequiredNativeSpmFilesForAbi",
        ):
            output = _runtime_inventory_function(updated, name)
            self.assertNotIn("TopK", output)
            self.assertNotIn("libGemmaModelConstraintProvider.dylib", output)
            self.assertNotIn("GemmaModelConstraintProvider.framework", output)

    def test_legacy_sync_preserves_admitted_inventory(self) -> None:
        for compatibility in ("v0.16.0", "v0.17.0", "v0.18.0", "v0.18.1"):
            with self.subTest(version=compatibility):
                self.manifest["upstream"]["compatibilityTag"] = compatibility
                updated = self.replace(self.runtime)
                for name in (
                    "_liteRtLmV1RequiredLibrariesForAbi",
                    "_liteRtLmV1MacOsRequiredFrameworksForAbi",
                    "_liteRtLmV1MacOsRequiredNativeSpmFilesForAbi",
                ):
                    self.assertEqual(_runtime_inventory_function(updated, name), _runtime_inventory_function(self.runtime, name))

    def test_compatibility_tag_selects_lane_even_for_development_release(self) -> None:
        self.manifest["release"] = {"tag": "g83ce6067f2e2"}
        self.assertTrue(pins._litert_lm_runtime_inventory_is_v1(self.manifest))
        self.manifest["upstream"]["compatibilityTag"] = "v0.19.1"
        self.assertTrue(pins._litert_lm_runtime_inventory_is_v1(self.manifest))
        self.manifest["upstream"]["compatibilityTag"] = "v0.18.1"
        self.assertFalse(pins._litert_lm_runtime_inventory_is_v1(self.manifest))

    def test_unknown_or_malformed_api_mapping_refuses(self) -> None:
        for version in ("v0.19.2", "v0.20.0", "v1.0.0", "g83ce6067f2e2", "", None):
            with self.subTest(version=version):
                self.manifest["upstream"]["compatibilityTag"] = version
                with self.assertRaises(ReleaseError):
                    self.replace(self.runtime)

    def test_missing_or_duplicate_generated_function_refuses(self) -> None:
        for name in (
            "_liteRtLmV1RequiredLibrariesForAbi",
            "_liteRtLmV1MacOsRequiredFrameworksForAbi",
            "_liteRtLmV1MacOsRequiredNativeSpmFilesForAbi",
        ):
            block = _runtime_inventory_function(self.runtime, name)
            for malformed in (self.runtime.replace(block, ""), self.runtime + block):
                with self.subTest(function=name), self.assertRaisesRegex(ReleaseError, name):
                    self.replace(malformed)

    def test_generated_v019_dart_uses_real_owner_files_without_changing_legacy(self) -> None:
        if shutil.which("dart") is None:
            self.skipTest("Dart SDK is required to execute generated inventory")
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp) / "repo"
            shutil.copytree(self.source_root / "lib", repo / "lib")
            (repo / ".dart_tool").mkdir()
            shutil.copyfile(self.source_root / ".dart_tool/package_config.json", repo / ".dart_tool/package_config.json")
            shutil.copyfile(self.source_root / "pubspec.yaml", repo / "pubspec.yaml")
            runtime_path = repo / "lib/src/backends/litert_lm/litert_lm_runtime.dart"
            runtime_path.write_text(self.replace(self.runtime))
            entries = pins.litert_schema2_runtime_required_libraries(self.bundles)
            checks = _preserved_runtime_lane_probe_checks(self.runtime, c_api_v1=False)
            checks += "\n" + _runtime_inventory_probe_checks(
                c_api_v1=True,
                libraries={
                    "macosArm64": entries["macos-arm64"],
                    "linuxArm64": entries["linux-arm64"],
                    "linuxX64": entries["linux-x64"],
                    "windowsX64": entries["windows-x64"],
                },
                frameworks=pins._litert_schema2_macos_framework_entries(self.bundles)["arm64"],
                native_spm=pins.litert_macos_complete_spm_entries(
                    self.bundles,
                    pins.litert_schema2_macos_required_native_spm_files(self.manifest, self.projection["releaseTag"]),
                )["arm64"],
            )
            # Removing any owner-required v1 companion still refuses completeness;
            # the same no-sampler directory must never be admitted as legacy.
            checks += """
  final root = Directory.systemTemp.createTempSync('generated_inventory_');
  try {
    for (final abi in [Abi.macosArm64, Abi.linuxArm64, Abi.linuxX64, Abi.windowsX64]) {
      final dir = Directory('${root.path}/$abi')..createSync();
      final files = liteRtLmRequiredLibrariesForAbi(abi, cApiV1: true);
      for (final file in files) {
        File('${dir.path}/$file').createSync();
      }
      if (!liteRtLmIsCacheDirectoryForAbi(dir, abi, cApiV1: true) ||
          liteRtLmIsCacheDirectoryForAbi(dir, abi)) {
        throw StateError('v1/legacy inventory admission crossed for $abi');
      }
      for (final file in files) {
        final missing = File('${dir.path}/$file')..deleteSync();
        if (liteRtLmIsCacheDirectoryForAbi(dir, abi, cApiV1: true)) {
          throw StateError('missing $file was accepted for $abi');
        }
        missing.createSync();
      }
    }
  } finally {
    root.deleteSync(recursive: true);
  }
"""
            results = _run_dart_inventory_checks(repo, checks=checks)
            for result in results:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class LiteRtSourcePatchesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest, self.release = _schema2_fixture_payloads()
        # tools/asr_overlap_patch.py source_patch_manifest('v0.18.0') in the owner.
        self.record = {
            "id": "asr-untimed-overlap",
            "path": "native/bridge/asr_untimed_overlap.patch",
            "sha256": "665fe85a8a4e7f9abde048b3038ede1b4385aaac016aa90438210352b865e589",
            "source": "omni/asr/timestamp_text_merger.cc",
            "preimageSha256Lf": "6458bdfb32cbb32250c5be8843d303a9759da96f5675eae2d23a5f01f41dc826",
            "postimageSha256Lf": "c320a49202fcaed40ef2619e977b3a44303e7aa9aa04012c94a6ca07c016caee",
            "scope": "source-built runtimes only; excludes official upstream prebuilts",
        }

    def _validate(self) -> dict:
        with tempfile.TemporaryDirectory() as temp:
            _materialize_schema2_release_fixtures(
                Path(temp), self.manifest, self.release
            )
            return validate_litert_lm_release_manifest(
                self.release,
                repo="leehack/litert-lm-native",
                tag=self.manifest["release"]["tag"],
                release_json_dir=temp,
                required_bundles=[
                    f"{item['platform']}-{item['arch']}"
                    for item in self.manifest["platforms"]
                ],
            )

    def test_absent_source_patches_preserves_owner_manifest(self) -> None:
        validated = self._validate()
        self.assertEqual(validated, self.manifest)
        self.assertNotIn("sourcePatches", validated["upstream"])

    def test_valid_source_patches(self) -> None:
        self.manifest["upstream"]["sourcePatches"] = [self.record]
        self.assertEqual(
            self._validate()["upstream"]["sourcePatches"], [self.record]
        )
        second = dict(self.record, id="another-patch", sha256="a" * 64)
        self.manifest["upstream"]["sourcePatches"].append(second)
        self.assertEqual(
            self._validate()["upstream"]["sourcePatches"], [self.record, second]
        )

    def test_unknown_upstream_key_is_still_rejected(self) -> None:
        self.manifest["upstream"]["sourcePatches"] = [self.record]
        self.manifest["upstream"]["unexpected"] = []
        with self.assertRaisesRegex(ReleaseError, r"unexpected=\['unexpected'\]"):
            self._validate()

    def test_source_patches_requires_non_empty_list(self) -> None:
        for value in (None, {}, "patch", 1, True, []):
            with self.subTest(value=value):
                self.manifest["upstream"]["sourcePatches"] = value
                with self.assertRaisesRegex(
                    ReleaseError, "sourcePatches must be a non-empty list"
                ):
                    self._validate()

    def test_source_patch_requires_object(self) -> None:
        for value in (None, [], "patch", 1, True):
            with self.subTest(value=value):
                self.manifest["upstream"]["sourcePatches"] = [self.record, value]
                with self.assertRaisesRegex(
                    ReleaseError, r"sourcePatches\[1\] must be an object"
                ):
                    self._validate()

    def test_source_patch_requires_exact_keys(self) -> None:
        for key in self.record:
            with self.subTest(missing=key):
                malformed = dict(self.record)
                del malformed[key]
                self.manifest["upstream"]["sourcePatches"] = [malformed]
                with self.assertRaisesRegex(
                    ReleaseError, rf"sourcePatches\[0\].*missing=\['{key}'\]"
                ):
                    self._validate()
        self.manifest["upstream"]["sourcePatches"] = [
            dict(self.record, unexpected="value")
        ]
        with self.assertRaisesRegex(
            ReleaseError, r"sourcePatches\[0\].*unexpected=\['unexpected'\]"
        ):
            self._validate()

    def test_source_patch_fields_require_non_empty_strings(self) -> None:
        for key in self.record:
            for value in (None, [], {}, 1, True, ""):
                with self.subTest(field=key, value=value):
                    self.manifest["upstream"]["sourcePatches"] = [
                        dict(self.record, **{key: value})
                    ]
                    with self.assertRaisesRegex(
                        ReleaseError,
                        rf"sourcePatches\[0\] {key} must be a non-empty string",
                    ):
                        self._validate()

    def test_source_patch_hashes_require_lowercase_sha256(self) -> None:
        for key in ("sha256", "preimageSha256Lf", "postimageSha256Lf"):
            for value in ("z" * 64, "A" * 64, "a" * 63, "a" * 65, "a" * 64 + "\n"):
                with self.subTest(field=key, value=value):
                    self.manifest["upstream"]["sourcePatches"] = [
                        self.record, dict(self.record, **{key: value})
                    ]
                    with self.assertRaisesRegex(
                        ReleaseError,
                        rf"sourcePatches\[1\] {key} must be an exact SHA-256 digest",
                    ):
                        self._validate()


class LiteRtV019SamplerTransitionTest(unittest.TestCase):
    def setUp(self) -> None:
        fixture = Path(__file__).resolve().parent / "fixtures"
        self.source_path = fixture / "litert_lm_v018_samplers_Package.swift"
        self.original = self.source_path.read_text(encoding="utf-8")
        self.projection = json.loads((fixture / "litert_lm_v019_apple_inventory_projection.json").read_text())
        self.manifest, _ = _schema2_fixture_payloads()
        self.tag = self.projection["releaseTag"]
        self.manifest["release"]["tag"] = self.tag
        self.manifest["upstream"]["compatibilityTag"] = self.projection["compatibilityTag"]
        self.manifest["platforms"] = [item for item in self.manifest["platforms"]
            if item["platform"] not in ("ios", "macos")] + [
                item for item in self.projection["platforms"]
                if item["platform"] in ("ios", "macos")
            ]
        self.macos = next(item for item in self.manifest["platforms"]
            if item["platform"] == "macos")
        self.targets = {
            "LiteRtLm", "CLiteRTLM", "CLiteRTLMMac", "LiteRtMetalAccelerator",
            "LiteRt", "LiteRtWebGpuAccelerator", "WebgpuDawn",
        }
        self.release = {"assets": [{"name": item["fileName"], "digest": "sha256:" + item["sha256"]}
            for item in self.projection["spmArtifacts"]]}
        self.samplers = {"LiteRtTopKMetalSampler": ".iOS", "LiteRtTopKWebGpuSampler": ".macOS"}

    def asset(self, target: str) -> dict:
        return {
            "name": f"litert-lm-native-apple-{target}-xcframework-{self.tag}.zip",
            "digest": "sha256:" + hashlib.sha256(target.encode()).hexdigest(),
        }

    def binary_block(self, target: str) -> str:
        return re.search(
            rf'(?m)^[ \t]*nativeRepoBinaryTarget\(\s*name: "{target}",.*?^[ \t]*\),\n',
            self.original, re.DOTALL,
        ).group()

    def dependency(self, target: str) -> str:
        return f'.target(name: "{target}", condition: .when(platforms: [{self.samplers[target]}])),'

    def prepare(self, source: str) -> str:
        return prepare_litert_lm_package_swift(
            source, release=self.release, manifest=self.manifest, resolved_tag=self.tag,
        )

    def test_removes_both_obsolete_samplers_and_is_idempotent(self) -> None:
        prepared = self.prepare(self.original)
        self.assertEqual(self.source_path.read_text(encoding="utf-8"), self.original)
        expected = self.original
        for sampler in self.samplers:
            self.assertNotIn(sampler, prepared)
            expected = expected.replace(self.binary_block(sampler), "").replace(
                '                ' + self.dependency(sampler) + '\n', "",
            )
        self.assertEqual({name for name, _ in pins.swift_native_repo_binary_targets(
            prepared, tag_variable="liteRtLmTag", current_tag=self.tag,
        )}, self.targets)
        self.assertIn('.target(name: "LiteRtMetalAccelerator", condition: .when(platforms: [.iOS]))', prepared)
        expected = expected.replace('let liteRtLmTag = "v0.18.1-4"', f'let liteRtLmTag = "{self.tag}"')
        for target in self.targets:
            asset = next(item for item in self.release["assets"] if item["name"] == self.asset(target)["name"])
            expected = pins.replace_swift_binary_target_checksum(expected, target, asset["digest"][7:])
        self.assertEqual(prepared, expected)
        self.assertEqual(self.prepare(prepared), prepared)

    def test_already_current_topology_rejects_wrong_ios_platform(self) -> None:
        prepared = self.prepare(self.original)
        original = '.target(name: "CLiteRTLM", condition: .when(platforms: [.iOS])),'
        malformed = prepared.replace(original, original.replace(".iOS", ".macOS"))
        self.assertNotEqual(malformed, prepared)
        with self.assertRaisesRegex(ReleaseError, "platform dependency"):
            self.prepare(malformed)

    def test_already_current_topology_rejects_missing_ios_dependency(self) -> None:
        prepared = self.prepare(self.original)
        dependency = '.target(name: "CLiteRTLM", condition: .when(platforms: [.iOS])),'
        malformed = prepared.replace(dependency, "")
        self.assertNotEqual(malformed, prepared)
        with self.assertRaisesRegex(ReleaseError, "platform dependency"):
            self.prepare(malformed)

    def test_already_current_topology_rejects_wrong_repository(self) -> None:
        prepared = self.prepare(self.original)
        malformed = prepared.replace(
            'repository: "leehack/litert-lm-native",',
            'repository: "other/runtime",', 1,
        )
        self.assertNotEqual(malformed, prepared)
        with self.assertRaisesRegex(ReleaseError, "canonical"):
            self.prepare(malformed)

    def test_already_current_topology_rejects_duplicate_binary_target(self) -> None:
        prepared = self.prepare(self.original)
        block = re.search(
            r'(?m)^[ \t]*nativeRepoBinaryTarget\(\s*name: "CLiteRTLM",.*?^[ \t]*\),\n',
            prepared, re.DOTALL,
        ).group()
        malformed = prepared.replace(block, block * 2)
        with self.assertRaisesRegex(ReleaseError, "duplicate or unexpected"):
            self.prepare(malformed)

    def test_actual_owner_projection_does_not_require_prebuilt_topk(self) -> None:
        self.assertEqual(self.projection["ownerCommit"], "7ea10d0cce10dfddbae273bb69e253d9ea97e1d2")
        self.assertEqual(self.projection["upstreamCommit"], "83ce6067f2e2a3fb697556928f93936693ded971")
        paths = {path for platform in self.projection["platforms"] for path in platform["artifactPaths"]}
        self.assertTrue(any("LiteRtMetalAccelerator" in path for path in paths))
        self.assertFalse(any("TopK" in path for path in paths))
        self.assertFalse(any("TopK" in path for path in pins.required_litert_manifest_paths(
            "v0.19.0", self.tag, official_assets=False,
        )))
        pins.validate_litert_spm_artifact_inventory(
            {item["path"] for item in self.projection["spmArtifacts"]},
            compatibility_tag="v0.19.0", release_tag=self.tag,
        )

    def test_v016_through_v018_still_require_prebuilt_ios_sampler(self) -> None:
        for compatibility in ["v0.16.0", "v0.17.0", "v0.18.0", "v0.18.1"]:
            with self.subTest(version=compatibility):
                required = pins.required_litert_manifest_paths(compatibility, self.tag, official_assets=False)
                for arch in ["arm64", "arm64-sim"]:
                    self.assertIn(f"bin/ios/{arch}/LiteRtTopKMetalSampler.framework/LiteRtTopKMetalSampler", required)
                self.assertIn(f"dist/spm/{self.tag}/litert-lm-native-apple-LiteRtTopKMetalSampler-xcframework-{self.tag}.zip", required)

    def test_v018_owner_inventory_retains_both_sampler_dependencies(self) -> None:
        self.manifest["upstream"]["compatibilityTag"] = "v0.18.1"
        self.macos["artifactPaths"].append("bin/macos/arm64/libLiteRtTopKWebGpuSampler.dylib")
        for sampler in self.samplers:
            self.release["assets"].append(self.asset(sampler))
        prepared = self.prepare(self.original)
        for sampler in self.samplers:
            self.assertIn(self.dependency(sampler), prepared)
        self.assertEqual(self.prepare(prepared), prepared)
        self.release["assets"] = [item for item in self.release["assets"]
            if item["name"] != self.asset("LiteRtTopKMetalSampler")["name"]]
        with self.assertRaisesRegex(ReleaseError, "required asset.*LiteRtTopKMetalSampler"):
            self.prepare(self.original)

    def test_v019_rejects_sampler_required_by_manifest_or_archive(self) -> None:
        for sampler, platform in self.samplers.items():
            with self.subTest(sampler=sampler):
                bundle = self.macos if platform == ".macOS" else next(
                    item for item in self.manifest["platforms"] if item["platform"] == "ios")
                path = ("bin/macos/arm64/lib" + sampler + ".dylib" if platform == ".macOS"
                    else f'bin/ios/{bundle["arch"]}/{sampler}.framework/{sampler}')
                bundle["artifactPaths"].append(path)
                with self.assertRaisesRegex(ReleaseError, "prebuilt TopK"):
                    self.prepare(self.original)
                bundle["artifactPaths"].remove(path)
                with self.assertRaisesRegex(ReleaseError, "unexpected="):
                    pins.validate_litert_spm_artifact_inventory(
                        {item["path"] for item in self.projection["spmArtifacts"]}
                        | {f'dist/spm/{self.tag}/{self.asset(sampler)["name"]}'},
                        compatibility_tag="v0.19.0", release_tag=self.tag,
                    )

    def test_unknown_inventory_or_version_transition_refuses(self) -> None:
        self.macos["artifactPaths"].remove("bin/macos/arm64/libLiteRtWebGpuAccelerator.dylib")
        with self.assertRaisesRegex(ReleaseError, "owner inventory"):
            self.prepare(self.original)
        for unreviewed in ("v0.19.2", "v0.20.0"):
            with self.subTest(version=unreviewed):
                self.setUp()
                self.manifest["upstream"]["compatibilityTag"] = unreviewed
                with self.assertRaisesRegex(ReleaseError, "owner inventory"):
                    self.prepare(self.original)

    def test_v0191_reuses_the_reviewed_sampler_free_topology(self) -> None:
        reviewed = self.prepare(self.original)
        self.manifest["upstream"]["compatibilityTag"] = "v0.19.1"
        self.assertEqual(self.prepare(self.original), reviewed)
        self.assertEqual(self.prepare(reviewed), reviewed)
        self.assertFalse(any("TopK" in path for path in pins.required_litert_manifest_paths(
            "v0.19.1", self.tag, official_assets=False,
        )))

    def drop_metal_accelerator(self, *bundles: str) -> None:
        for item in self.manifest["platforms"]:
            if f'{item["platform"]}-{item["arch"]}' in bundles:
                item["artifactPaths"] = [
                    path for path in item["artifactPaths"] if "MetalAccelerator" not in path
                ]
        self.release["assets"] = [item for item in self.release["assets"]
            if item["name"] != self.asset("LiteRtMetalAccelerator")["name"]]

    def test_metal_free_owner_removes_the_metal_target_and_is_idempotent(self) -> None:
        with_metal = self.prepare(self.original)
        self.drop_metal_accelerator("ios-arm64", "ios-arm64-sim", "macos-arm64")
        for label, source in (("nine-target", self.original), ("seven-target", with_metal)):
            with self.subTest(source=label):
                prepared = self.prepare(source)
                self.assertNotIn("LiteRtMetalAccelerator", prepared)
                self.assertNotIn("TopK", prepared)
                self.assertEqual({name for name, _ in pins.swift_native_repo_binary_targets(
                    prepared, tag_variable="liteRtLmTag", current_tag=self.tag,
                )}, self.targets - {"LiteRtMetalAccelerator"})
                block = re.search(
                    r'(?m)^[ \t]*nativeRepoBinaryTarget\(\s*name: "LiteRtMetalAccelerator",.*?^[ \t]*\),\n',
                    with_metal, re.DOTALL,
                ).group()
                self.assertEqual(prepared, with_metal.replace(block, "").replace(
                    '                .target(name: "LiteRtMetalAccelerator", '
                    'condition: .when(platforms: [.iOS])),\n', ""))
                self.assertEqual(self.prepare(prepared), prepared)

    def test_metal_accelerator_is_optional_from_v019(self) -> None:
        for compatibility in ("v0.19.0", "v0.19.1"):
            with self.subTest(version=compatibility):
                self.assertFalse(any("Metal" in path for path in pins.required_litert_manifest_paths(
                    compatibility, self.tag, official_assets=False,
                )))
                spm = {item["path"] for item in self.projection["spmArtifacts"]}
                for paths in (spm, {path for path in spm if "MetalAccelerator" not in path}):
                    pins.validate_litert_spm_artifact_inventory(
                        paths, compatibility_tag=compatibility, release_tag=self.tag,
                    )
        required = pins.required_litert_manifest_paths("v0.18.1", self.tag, official_assets=False)
        self.assertIn("bin/ios/arm64/LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator", required)
        self.assertIn(f"dist/spm/{self.tag}/" + self.asset("LiteRtMetalAccelerator")["name"], required)

    def test_metal_accelerator_on_only_some_ios_bundles_refuses(self) -> None:
        self.drop_metal_accelerator("ios-arm64-sim")
        with self.assertRaisesRegex(ReleaseError, "only some iOS bundles"):
            self.prepare(self.original)

    def test_pre_v019_apple_targets_do_not_derive_the_ios_metal_target(self) -> None:
        self.manifest["upstream"]["compatibilityTag"] = "v0.18.1"
        self.drop_metal_accelerator("ios-arm64-sim")
        self.assertIn(
            "LiteRtMetalAccelerator",
            pins.litert_schema2_apple_targets(self.manifest, self.tag),
        )

    def test_metal_removal_refuses_ambiguous_metal_references(self) -> None:
        with_metal = self.prepare(self.original)
        self.drop_metal_accelerator("ios-arm64", "ios-arm64-sim", "macos-arm64")
        dependency = '.target(name: "LiteRtMetalAccelerator", condition: .when(platforms: [.iOS])),'
        for label, source in (
            ("extra-reference", with_metal + "\n// LiteRtMetalAccelerator"),
            ("duplicate-dependency", with_metal.replace(dependency, dependency * 2)),
            ("missing-dependency", with_metal.replace(dependency, "")),
            ("wrong-platform", with_metal.replace(dependency, dependency.replace(".iOS", ".macOS"))),
        ):
            with self.subTest(source=label), self.assertRaises(ReleaseError):
                self.prepare(source)

    LITERT_COMPANIONS = ("LiteRt", "LiteRtWebGpuAccelerator")

    def drop_litert_companions(self, *targets: str) -> None:
        self.drop_metal_accelerator("ios-arm64", "ios-arm64-sim", "macos-arm64")
        names = {f"lib{target}.dylib" for target in targets}
        for item in self.manifest["platforms"]:
            item["artifactPaths"] = [
                path for path in item["artifactPaths"] if Path(path).name not in names
            ]
        gone = {self.asset(target)["name"] for target in targets}
        self.release["assets"] = [
            item for item in self.release["assets"] if item["name"] not in gone
        ]

    def metal_free_package(self) -> str:
        self.drop_metal_accelerator("ios-arm64", "ios-arm64-sim", "macos-arm64")
        prepared = self.prepare(self.original)
        self.setUp()
        return prepared

    def test_litert_free_owner_keeps_four_targets_and_libraries(self) -> None:
        metal_free = self.metal_free_package()
        self.drop_litert_companions(*self.LITERT_COMPANIONS)
        keep = {"LiteRtLm", "CLiteRTLM", "CLiteRTLMMac", "WebgpuDawn"}
        self.assertEqual(pins.litert_schema2_apple_targets(self.manifest, self.tag), keep)
        self.assertEqual(
            pins.litert_schema2_bundle_required_libraries(self.manifest)["macos-arm64"],
            (
                "libCLiteRTLM_mac.dylib", "libGemmaModelConstraintProvider.dylib",
                "libLiteRtLm.dylib", "libwebgpu_dawn.dylib",
            ),
        )
        for label, source in (("nine-target", self.original), ("six-target", metal_free)):
            with self.subTest(source=label):
                prepared = self.prepare(source)
                self.assertEqual({name for name, _ in pins.swift_native_repo_binary_targets(
                    prepared, tag_variable="liteRtLmTag", current_tag=self.tag,
                )}, keep)
                for target in self.LITERT_COMPANIONS:
                    self.assertNotIn(f'name: "{target}"', prepared)
                for target in keep:
                    self.assertIn(f'name: "{target}"', prepared)
                self.assertEqual(self.prepare(prepared), prepared)

    def test_litert_removal_requires_both_companions_to_leave(self) -> None:
        for gone in (("LiteRt",), ("LiteRtWebGpuAccelerator",)):
            with self.subTest(gone=gone):
                self.setUp()
                self.drop_litert_companions(*gone)
                with self.assertRaises(ReleaseError):
                    self.prepare(self.original)

    def test_litert_removal_refuses_ambiguous_references(self) -> None:
        with_litert = self.metal_free_package()
        dependency = '.target(name: "LiteRt", condition: .when(platforms: [.macOS])),'
        self.assertIn(dependency, with_litert)
        self.drop_litert_companions(*self.LITERT_COMPANIONS)
        for label, source in (
            ("duplicate-dependency", with_litert.replace(dependency, dependency * 2)),
            ("missing-dependency", with_litert.replace(dependency, "")),
            ("wrong-platform", with_litert.replace(dependency, dependency.replace(".macOS", ".iOS"))),
        ):
            with self.subTest(source=label), self.assertRaises(ReleaseError):
                self.prepare(source)

    def test_litert_remover_guards_hold_without_the_topology_validator(self) -> None:
        # The topology validator runs first and rejects these sources itself,
        # so stub it to pin the remover's own count and platform checks.
        with_litert = self.metal_free_package()
        blocks = pins._validate_litert_lm_v019_swift_topology(
            with_litert, current_tag=self.tag,
            include_obsolete_samplers=False, include_metal_accelerator=False,
        )
        self.assertEqual(
            pins._remove_litert_lm_unused_litert_companions(
                with_litert, current_tag=self.tag,
            ).count('name: "LiteRt"'), 0,
        )
        dependency = '.target(name: "LiteRt", condition: .when(platforms: [.macOS])),'
        accelerator = '.target(name: "LiteRtWebGpuAccelerator", condition: .when(platforms: [.macOS])),'
        unrelated = with_litert + '\n// see "LiteRt" and "LiteRtWebGpuAccelerator"'
        self.assertEqual(
            pins._remove_litert_lm_unused_litert_companions(
                unrelated, current_tag=self.tag,
            ).count('name: "LiteRt"'), 0,
        )
        for label, source, message in (
            ("stray-reference", with_litert + '\n// name: "LiteRt"', "ambiguous LiteRt references"),
            ("stray-accelerator-reference", with_litert + '\n// name: "LiteRtWebGpuAccelerator"', "ambiguous LiteRtWebGpuAccelerator references"),
            ("duplicate-dependency", with_litert.replace(dependency, dependency * 2), "ambiguous LiteRt references"),
            ("missing-dependency", with_litert.replace(dependency, ""), "ambiguous LiteRt references"),
            ("wrong-platform", with_litert.replace(dependency, dependency.replace(".macOS", ".iOS")), "LiteRt must have exactly one macOS dependency"),
            ("wrong-accelerator-platform", with_litert.replace(accelerator, accelerator.replace(".macOS", ".iOS")), "LiteRtWebGpuAccelerator must have exactly one macOS dependency"),
        ):
            with self.subTest(source=label), patch.object(
                pins, "_validate_litert_lm_v019_swift_topology", return_value=blocks,
            ), self.assertRaisesRegex(ReleaseError, message):
                self.assertNotEqual(source, with_litert)
                pins._remove_litert_lm_unused_litert_companions(
                    source, current_tag=self.tag,
                )

    def test_malformed_or_ambiguous_topology_refuses(self) -> None:
        for sampler in self.samplers:
            block, dependency = self.binary_block(sampler), self.dependency(sampler)
            other = self.binary_block("LiteRtWebGpuAccelerator")
            for label, source in (
                ("duplicate-block", self.original.replace(block, block * 2)),
                ("duplicate-other-block", self.original.replace(other, other * 2)),
                ("duplicate-dependency", self.original.replace(dependency, dependency * 2)),
                ("missing-dependency", self.original.replace(dependency, "")),
                ("orphan-dependency", self.original.replace(block, "")),
                ("bad-checksum-field", self.original.replace(block, block.replace("checksum:", "badChecksum:"))),
                ("short-checksum", self.original.replace(block, re.sub(r'checksum: "[0-9a-f]+"', 'checksum: "a"', block))),
                ("wrong-repository", self.original.replace(block, block.replace("leehack/litert-lm-native", "other/runtime"))),
                ("wrong-tag-argument", self.original.replace(block, block.replace("tag: liteRtLmTag", 'tag: "other"'))),
                ("extra-sampler-reference", self.original + '\n// ' + sampler),
                ("string-dependency", self.original.replace(dependency, dependency + '\n"Other",')),
                ("dynamic-dependency", self.original.replace(dependency, dependency + '\n.target(name: dynamicTarget),')),
                ("dangling-dependency", self.original.replace(dependency, dependency + '\n.target(name: "Other"),')),
                ("unknown-binary-call", self.original + '\nlet extra = nativeRepoBinaryTarget(name: dynamicTarget)\n'),
            ):
                with self.subTest(sampler=sampler, source=label), self.assertRaises(ReleaseError):
                    self.prepare(source)

    def test_every_platform_dependency_is_preserved(self) -> None:
        for target, original, wrong in (
            ("LiteRtTopKMetalSampler", ".iOS", ".macOS"),
            ("LiteRtTopKWebGpuSampler", ".macOS", ".iOS"),
            ("LiteRtLm", ".iOS, .macOS", ".iOS"),
            ("CLiteRTLM", ".iOS", ".macOS"),
            ("CLiteRTLMMac", ".macOS", ".iOS"),
            ("LiteRtMetalAccelerator", ".iOS", ".macOS"),
            ("LiteRt", ".macOS", ".iOS"),
            ("LiteRtWebGpuAccelerator", ".macOS", ".iOS"),
            ("WebgpuDawn", ".macOS", ".iOS"),
        ):
            dependency = f'.target(name: "{target}", condition: .when(platforms: [{original}]))'
            with self.subTest(target=target), self.assertRaisesRegex(ReleaseError, "platform dependency"):
                source = self.original.replace(dependency, dependency.replace(original, wrong))
                self.assertNotEqual(source, self.original)
                self.prepare(source)

    def test_wrong_artifact_cannot_rewire_any_retained_target(self) -> None:
        for target in self.targets | set(self.samplers):
            source = self.original.replace(
                f'artifactName: "litert-lm-native-apple-{target}-xcframework-',
                'artifactName: "litert-lm-native-apple-WrongTarget-xcframework-',
            )
            with self.subTest(target=target), self.assertRaisesRegex(ReleaseError, "canonical"):
                self.prepare(source)


class LiteRtCompanionTemplateSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.source_root = Path(__file__).resolve().parents[2]
        self.hook = (self.source_root / "hook/build.dart").read_text()
        self.hook = self.hook.replace(
            self.declared_hash(self.hook),
            "be71ff20cc6f29dae94ccfadcc8d7ae1cc78945385d11aa625223ccd559a9e74",
        )
        self.original = (self.source_root / "tool/native/fixtures/litert_lm_v018_samplers_Package.swift").read_text()
        projection = _v019_inventory_projection()
        self.manifest, _ = _schema2_fixture_payloads()
        self.manifest["release"]["tag"] = "v0.19.0"
        self.manifest["upstream"]["compatibilityTag"] = "v0.19.0"
        self.manifest["platforms"] = projection["platforms"]
        self.release = {"tag_name": "v0.19.0", "assets": [
            {"name": item["fileName"], "digest": "sha256:" + item["sha256"]}
            for item in projection["spmArtifacts"]
        ]}
        for bundle in pins.litert_lm_bundle_names(
            (self.source_root / pins.DEFAULT_NATIVE_RELEASE_PINS).read_text()
        ):
            self.release["assets"].append({
                "name": f"litert-lm-native-runtime-{bundle}-v0.19.0.tar.gz",
                "digest": "sha256:" + hashlib.sha256(bundle.encode()).hexdigest(),
            })
        self.prepared = prepare_litert_lm_package_swift(
            self.original, release=self.release, manifest=self.manifest,
            resolved_tag="v0.19.0",
        )

    def declared_hash(self, hook: str) -> str:
        return re.search(
            r"const _liteRtLmCompanionManifestTemplateSha256 =\s*'([0-9a-f]{64})';",
            hook,
        ).group(1)

    def stage(self, root: Path) -> None:
        for relative in (
            "hook/build.dart", pins.DEFAULT_NATIVE_RELEASE_PINS,
            pins.DEFAULT_LITERT_LM_RUNTIME_DART,
            pins.DEFAULT_LITERT_LM_MACOS_PREPARE_SCRIPT,
            *pins.DEFAULT_LLAMA_CPP_PROJECT_DOCS,
        ):
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.source_root / relative, target)
        package = "packages/llamadart_litert_lm_flutter"
        shutil.copytree(self.source_root / package, root / package)
        (root / "hook/build.dart").write_text(self.hook)
        (root / pins.DEFAULT_LITERT_LM_PACKAGE_SWIFT).write_text(self.original)
        pin_path = root / pins.DEFAULT_NATIVE_RELEASE_PINS
        pin_path.write_text(re.sub(
            r"const liteRtLmReleaseTag = '[^']+';",
            "const liteRtLmReleaseTag = 'v0.18.1-4';", pin_path.read_text(),
        ))

    def sync(self, root: Path, *, dry_run: bool = False) -> str:
        argv = ["sync", "--repo-root", str(root), "--litert-lm-tag", "v0.19.0"]
        if dry_run:
            argv.append("--dry-run")
        output = io.StringIO()
        with patch.object(sys, "argv", argv), patch.object(
            pins, "fetch_release", return_value=self.release,
        ), patch.object(
            pins, "validate_litert_lm_release_manifest", return_value=self.manifest,
        ), patch.object(pins, "write_github_output"), patch("sys.stdout", output):
            self.assertEqual(pins.main(), 0)
        return output.getvalue()

    def test_ordinary_sync_updates_hook_from_rendered_seven_target_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.stage(root)
            self.sync(root)
            updated = (root / "hook/build.dart").read_text()
            self.assertEqual(self.declared_hash(updated),
                             "df03e4e53c34d1d7c7039e221092d30fb72b2a71d93b4f6227299af41aff26cb")
            self.assertEqual((root / pins.DEFAULT_LITERT_LM_PACKAGE_SWIFT).read_text(), self.prepared)
            self.assertIn("const liteRtLmReleaseTag = 'v0.19.0';",
                          (root / pins.DEFAULT_NATIVE_RELEASE_PINS).read_text())
            self.assertNotIn("TopK", self.prepared)
            first = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
            self.sync(root)
            self.assertEqual(first, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})

    def test_dry_run_reports_prospective_hash_without_changing_current_eighteen(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.stage(root)
            before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
            output = self.sync(root, dry_run=True)
            self.assertIn("df03e4e53c34d1d7c7039e221092d30fb72b2a71d93b4f6227299af41aff26cb", output)
            self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})
            self.assertIn("const liteRtLmReleaseTag = 'v0.18.1-4';",
                          (root / pins.DEFAULT_NATIVE_RELEASE_PINS).read_text())

    def test_stale_admitted_hash_refuses_before_any_sync_write(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.stage(root)
            hook = root / "hook/build.dart"
            hook.write_text(self.hook.replace(self.declared_hash(self.hook), "0" * 64))
            before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
            with self.assertRaisesRegex(ReleaseError, "reviewed.*template"):
                self.sync(root)
            self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})

    def test_missing_hook_refuses_before_any_sync_write(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.stage(root)
            (root / "hook/build.dart").unlink()
            before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
            with self.assertRaisesRegex(ReleaseError, "Missing native build hook"):
                self.sync(root)
            self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})

    def test_current_nine_target_template_retains_current_hook(self) -> None:
        self.assertEqual(pins.replace_litert_lm_companion_template_hash(
            self.hook, original_swift=self.original,
            prepared_swift=self.original.replace("\n", "\r\n"),
            resolved_tag="v0.18.1-4",
        ), self.hook)

    def test_rendered_version_skew_cannot_authorize_a_template(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "rendered.*tag"):
            pins.replace_litert_lm_companion_template_hash(
                self.hook, original_swift=self.original,
                prepared_swift=self.prepared, resolved_tag="v0.18.1-4",
            )

    def test_duplicate_rendered_tag_cannot_authorize_a_template(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "one.*template tag"):
            pins.replace_litert_lm_companion_template_hash(
                self.hook, original_swift=self.original,
                prepared_swift=self.prepared + '\nlet liteRtLmTag = "v0.19.0"\n',
                resolved_tag="v0.19.0",
            )

    def test_missing_or_duplicate_hook_contract_refuses(self) -> None:
        declaration = re.search(
            r"const _liteRtLmCompanionManifestTemplateSha256 =\s*'[0-9a-f]{64}';",
            self.hook,
        ).group()
        for hook in (self.hook.replace(declaration, ""), self.hook + declaration):
            with self.subTest(hook=hook[-100:]), self.assertRaises(ReleaseError):
                pins.replace_litert_lm_companion_template_hash(
                    hook, original_swift=self.original,
                    prepared_swift=self.prepared, resolved_tag="v0.19.0",
                )


class LiteRtCallbackAbiAdmissionTest(unittest.TestCase):
    def _payloads(self, version: str) -> tuple[dict, dict]:
        if version == "v0.16.0":
            return _schema2_fixture_payloads()
        fixtures = Path(__file__).resolve().parent / "fixtures"
        return tuple(
            json.loads((fixtures / f"litert_lm_v019_owner_{name}.json").read_text())
            for name in ("manifest", "release")
        )

    def _validate(self, manifest: dict, release: dict) -> dict:
        with tempfile.TemporaryDirectory() as temp:
            _materialize_schema2_release_fixtures(Path(temp), manifest, release)
            return validate_litert_lm_release_manifest(
                release,
                repo="leehack/litert-lm-native",
                tag=manifest["release"]["tag"],
                release_json_dir=temp,
                required_bundles=[
                    f"{item['platform']}-{item['arch']}"
                    for item in manifest["platforms"]
                ],
            )

    def test_synthetic_corrected_modern_declarations_are_accepted(self) -> None:
        for version in ("v0.16.0", "v0.19.0"):
            with self.subTest(version=version):
                manifest, release = self._payloads(version)
                # In-memory stand-in only; no corrected published artifact exists.
                manifest["abi"]["streamProxyCallback"] = 2
                manifest["native"]["commit"] = "a" * 40
                release["target_commitish"] = "a" * 40
                for smoke in manifest["realModelSmokes"]:
                    smoke["nativeCommit"] = "a" * 40
                self.assertEqual(self._validate(manifest, release), manifest)

    def test_historical_callback1_declarations_remain_readable(self) -> None:
        for version in ("v0.16.0", "v0.19.0"):
            with self.subTest(version=version):
                manifest, release = self._payloads(version)
                self.assertEqual(manifest["abi"]["streamProxyCallback"], 1)
                self.assertEqual(self._validate(manifest, release), manifest)

    def test_callback_scalars_and_unknown_versions_are_rejected(self) -> None:
        for value in (True, False, None, "2", 2.0, 0, 3):
            with self.subTest(value=value):
                manifest, release = self._payloads("v0.19.0")
                manifest["abi"]["streamProxyCallback"] = value
                with self.assertRaisesRegex(ReleaseError, "callback ABI"):
                    self._validate(manifest, release)

    def test_callback2_is_rejected_below_v015(self) -> None:
        for version in ("v0.14.0", "v0.14.9"):
            with self.subTest(version=version):
                manifest, release = _schema2_fixture_payloads()
                tag = manifest["release"]["tag"]
                manifest = json.loads(json.dumps(manifest).replace(tag, version))
                release = json.loads(json.dumps(release).replace(tag, version))
                manifest["upstream"].update(
                    tag=version, compatibilityTag=version, prebuiltOverrides=[]
                )
                manifest["release"].update(
                    kind="upstream", rebuild=0, githubPrerelease=False
                )
                release["prerelease"] = False
                manifest["abi"]["streamProxyCallback"] = 2
                with self.assertRaisesRegex(
                    ReleaseError, f"callback ABI 2 for {version}"
                ):
                    self._validate(manifest, release)

    def test_callback2_preserves_other_abi_and_capability_checks(self) -> None:
        for section, field, value in (
            ("abi", "asrBridge", 2),
            ("abi", "asrBridge", True),
            ("abi", "upstreamC", "c/unknown.h"),
            ("capabilities", "streamChunkAccessors", False),
            ("capabilities", "streamChunkAccessors", 1),
        ):
            with self.subTest(field=field, value=value):
                manifest, release = self._payloads("v0.19.0")
                manifest["abi"]["streamProxyCallback"] = 2
                manifest[section][field] = value
                with self.assertRaises(ReleaseError):
                    self._validate(manifest, release)

    def test_callback2_preserves_exact_source_and_digest_checks(self) -> None:
        manifest, release = self._payloads("v0.19.0")
        manifest["abi"]["streamProxyCallback"] = 2
        release["target_commitish"] = "b" * 40
        with self.assertRaisesRegex(ReleaseError, "release target"):
            self._validate(manifest, release)
        release["target_commitish"] = manifest["native"]["commit"]
        with tempfile.TemporaryDirectory() as temp:
            _materialize_schema2_release_fixtures(Path(temp), manifest, release)
            _set_release_asset_digest(release, "manifest.json", "0" * 64)
            with self.assertRaisesRegex(ReleaseError, "manifest bytes"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=manifest["release"]["tag"],
                    release_json_dir=temp,
                    required_bundles=[],
                )


class LiteRtV019PrebuiltOverridesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fixtures = Path(__file__).resolve().parent / "fixtures"
        self.manifest_bytes = (
            self.fixtures / "litert_lm_v019_owner_manifest.json"
        ).read_bytes()
        self.manifest = json.loads(self.manifest_bytes)
        self.release = json.loads(
            (self.fixtures / "litert_lm_v019_owner_release.json").read_text()
        )
        self.tag = "v0.19.0"

    def validate(self, fixture_dir: Path) -> dict:
        return validate_litert_lm_release_manifest(
            self.release,
            repo="leehack/litert-lm-native",
            tag=self.tag,
            release_json_dir=str(fixture_dir),
            required_bundles=[
                f"{item['platform']}-{item['arch']}"
                for item in self.manifest["platforms"]
            ],
        )

    def test_published_owner_bytes_pass_full_manifest_validation(self) -> None:
        self.assert_published_owner_bytes_validate(
            fixture_prefix="litert_lm_v019_owner",
            tag="v0.19.0",
            manifest_sha256="bd6f67c047bbd853fd962d363e0507c043be0658c00502b4e486b02c27107871",
            native_commit="f173fe9b18a30fdc23cc896be27a36bf85657921",
            upstream_commit="83ce6067f2e2a3fb697556928f93936693ded971",
            checksum_sha256="735f30d786f1f2bac9d145396370139c69c54643c931a239cdb0f96eeb48cc28",
        )

    def test_published_v0191_owner_bytes_pass_full_manifest_validation(self) -> None:
        self.assert_published_owner_bytes_validate(
            fixture_prefix="litert_lm_v0191_owner",
            tag="v0.19.1",
            manifest_sha256="6ee1528a37f7e473c23def3dacfcdad1d9631cf7ed54d9891264e346e1d17e2e",
            native_commit="1fa4d43705fe07ba5e4d962e41cf32b8a2ac6116",
            upstream_commit="7a03724cece417f1724c923b3d527b4319730841",
            checksum_sha256="2555c3a556071dceebc8b4baddee4c0c6d03427f07f2d4380ddbe874422fb34a",
        )

    def assert_published_owner_bytes_validate(
        self,
        *,
        fixture_prefix: str,
        tag: str,
        manifest_sha256: str,
        native_commit: str,
        upstream_commit: str,
        checksum_sha256: str,
    ) -> None:
        self.tag = tag
        self.manifest_bytes = (
            self.fixtures / f"{fixture_prefix}_manifest.json"
        ).read_bytes()
        self.manifest = json.loads(self.manifest_bytes)
        self.release = json.loads(
            (self.fixtures / f"{fixture_prefix}_release.json").read_text()
        )
        self.assertEqual(
            hashlib.sha256(self.manifest_bytes).hexdigest(), manifest_sha256,
        )
        self.assertEqual(self.manifest["release"]["tag"], tag)
        self.assertEqual(self.manifest["native"]["commit"], native_commit)
        self.assertEqual(self.manifest["upstream"]["commit"], upstream_commit)
        self.assertEqual(self.release["target_commitish"], native_commit)
        checksum_bytes = (
            self.fixtures / f"{fixture_prefix}_SHA256SUMS"
        ).read_bytes()
        self.assertEqual(
            hashlib.sha256(checksum_bytes).hexdigest(), checksum_sha256,
        )
        published_digests = {
            asset["name"]: asset["digest"] for asset in self.release["assets"]
        }
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _materialize_schema2_release_fixtures(root, self.manifest, self.release)
            for name, payload in (
                ("manifest.json", self.manifest_bytes),
                ("SHA256SUMS", checksum_bytes),
            ):
                (root / f"leehack__litert-lm-native__{self.tag}__{name}").write_bytes(payload)
                self.assertEqual(
                    published_digests[name],
                    "sha256:" + hashlib.sha256(payload).hexdigest(),
                )
                _set_release_asset_digest(
                    self.release, name, published_digests[name].removeprefix("sha256:")
                )
            self.assertEqual(self.validate(root), self.manifest)
            stale_table = dict(pins.LITERT_PREBUILT_OVERRIDES)
            del stale_table[self.tag]
            with patch.object(pins, "LITERT_PREBUILT_OVERRIDES", stale_table):
                with self.assertRaisesRegex(
                    ReleaseError,
                    f"LITERT_PREBUILT_OVERRIDES has no entry for upstream {tag}",
                ):
                    self.validate(root)

    def test_v019_override_provenance_rejects_missing_and_altered_records(self) -> None:
        original = json.loads(json.dumps(self.manifest))
        cases = (
            ("missing", None, None),
            ("sourceCommit", "sourceCommit", "1" * 40),
            ("sourcePath", "sourcePath", "prebuilt/android_arm64/other.so"),
            ("sourceRepository", "sourceRepository", "other/LiteRT-LM"),
            ("targetPath", "targetPath", "bin/android/arm64/other.so"),
            ("sha256", "sha256", "1" * 64),
        )
        for label, field, value in cases:
            with self.subTest(field=label), tempfile.TemporaryDirectory() as temp:
                self.manifest = json.loads(json.dumps(original))
                overrides = self.manifest["upstream"]["prebuiltOverrides"]
                if field is None:
                    overrides.pop()
                else:
                    overrides[0][field] = value
                _materialize_schema2_release_fixtures(
                    Path(temp), self.manifest, self.release
                )
                with self.assertRaisesRegex(ReleaseError, "prebuilt override provenance"):
                    self.validate(Path(temp))

    def test_v019_override_target_artifact_hash_is_still_enforced(self) -> None:
        target = self.manifest["upstream"]["prebuiltOverrides"][0]["targetPath"]
        artifact = next(
            item for item in self.manifest["artifacts"] if item["path"] == target
        )
        artifact["sha256"] = "1" * 64
        with tempfile.TemporaryDirectory() as temp:
            _materialize_schema2_release_fixtures(
                Path(temp), self.manifest, self.release
            )
            with self.assertRaisesRegex(
                ReleaseError, "prebuilt override target provenance"
            ):
                self.validate(Path(temp))

    def test_v019_override_provenance_does_not_admit_version_skew(self) -> None:
        self.manifest["upstream"]["compatibilityTag"] = "v0.18.1"
        with tempfile.TemporaryDirectory() as temp:
            _materialize_schema2_release_fixtures(
                Path(temp), self.manifest, self.release
            )
            with self.assertRaisesRegex(ReleaseError, "compatibility tag"):
                self.validate(Path(temp))


class SyncNativeReleasePinsTest(unittest.TestCase):
    def test_exact_keys_rejects_non_object_json(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "must be an object"):
            require_exact_keys([], {"expected"}, "test payload")

    def test_release_fixture_errors_are_typed_and_tag_bound(self) -> None:
        repo = "leehack/litert-lm-native"
        tag = "v0.16.0-3"
        with tempfile.TemporaryDirectory() as temp:
            fixture = Path(temp) / f"leehack__litert-lm-native__{tag}.json"
            fixture.write_bytes(b"\xff")
            with self.assertRaisesRegex(ReleaseError, "Failed to fetch release"):
                fetch_release(repo, tag, temp)

            fixture.write_text("[]", encoding="utf-8")
            with self.assertRaisesRegex(ReleaseError, "must be a JSON object"):
                fetch_release(repo, tag, temp)

            fixture.write_text(
                json.dumps({"tag_name": "v0.16.0-4"}), encoding="utf-8"
            )
            with self.assertRaisesRegex(ReleaseError, "unexpected tag"):
                fetch_release(repo, tag, temp)

    def test_sync_workflow_captures_every_litert_pin_surface(self) -> None:
        workflow = (
            Path(__file__).resolve().parents[2]
            / ".github"
            / "workflows"
            / "sync_native_bindings.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("tool/macos_litert_lm_prepare_app.sh", workflow)
        self.assertIn("allow_litert_channel_transition:", workflow)
        self.assertIn("allow_litert_development_line_transition:", workflow)
        self.assertIn("--allow-litert-channel-transition", workflow)
        self.assertIn("--allow-litert-development-line-transition", workflow)
        self.assertIn("legacy vX.Y.Z-native.N, latest, or keep", workflow)
        allowlist = (
            Path(__file__).resolve().parent
            / "fixtures"
            / "legacy_release_allowlist.json"
        )
        self.assertEqual(
            hashlib.sha256(allowlist.read_bytes()).hexdigest(),
            "23ba56a9b11d60410b45398e5b3410f67ffca53d282deac74dd44102d15ec674",
        )
        self.assertEqual(len(LEGACY_SCHEMA1_RELEASES), 13)

    def test_sync_workflow_captures_every_stable_diffusion_surface(self) -> None:
        workflow = (
            Path(__file__).resolve().parents[2]
            / ".github"
            / "workflows"
            / "sync_native_bindings.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("stable_diffusion_tag:", workflow)
        self.assertEqual(
            workflow.count('--stable-diffusion-tag "${STABLE_DIFFUSION_TAG}"'), 2
        )
        self.assertEqual(
            workflow.count(
                "          STABLE_DIFFUSION_TAG: "
                "${{ inputs.stable_diffusion_tag }}\n"
            ),
            2,
        )
        self.assertEqual(
            workflow.count("${{ inputs.stable_diffusion_tag }}"),
            2,
            "inputs.stable_diffusion_tag must only reach run: blocks via env",
        )
        self.assertIn("tool/native/sync_stable_diffusion_bindings.py", workflow)
        self.assertIn(
            "        if: steps.sync_pins.outputs.resolved_stable_diffusion_tag"
            " != 'keep'\n",
            workflow,
        )
        self.assertEqual(
            workflow.count(
                "RESOLVED_STABLE_DIFFUSION_TAG: "
                "${{ steps.sync_pins.outputs.resolved_stable_diffusion_tag }}"
            ),
            2,
        )
        self.assertIn(
            'if [[ "${RESOLVED_STABLE_DIFFUSION_TAG}" != "keep" ]]; then\n'
            '            branch="${branch}-sd-${RESOLVED_STABLE_DIFFUSION_TAG}"',
            workflow,
        )
        for path in (
            "lib/src/backends/stable_diffusion/stable_diffusion_bindings.dart",
            "packages/llamadart_stable_diffusion_flutter/darwin/"
            "llamadart_stable_diffusion_flutter/Package.swift",
            "packages/llamadart_stable_diffusion_flutter/pubspec.yaml",
            "packages/llamadart_stable_diffusion_flutter/CHANGELOG.md",
            "packages/llamadart_stable_diffusion_flutter/README.md",
        ):
            with self.subTest(path=path):
                self.assertIn(f"            {path} \\\n", workflow)

    def test_litert_tag_grammar_preserves_new_and_legacy_forms(self) -> None:
        expected = {
            "0.16.1": "v0.16.1",
            "0.16.1-2": "v0.16.1-2",
            "v0.16.1": "v0.16.1",
            "v0.16.1-2": "v0.16.1-2",
            DEVELOPMENT_TAG: DEVELOPMENT_TAG,
            f"{DEVELOPMENT_TAG}-1": f"{DEVELOPMENT_TAG}-1",
            "0.16.0-native.2": "v0.16.0-native.2",
            "v0.16.0-native.2": "v0.16.0-native.2",
            "latest": "latest",
            "keep": "keep",
        }
        for value, normalized in expected.items():
            with self.subTest(value=value):
                self.assertEqual(normalize_litert_lm_release_tag(value), normalized)
        with self.assertRaises(ReleaseError):
            normalize_litert_lm_release_tag("main")
        self.assertEqual(litert_lm_runtime_version("v0.16.1-2"), "0.16.1-2")
        self.assertEqual(litert_lm_runtime_version(DEVELOPMENT_TAG), DEVELOPMENT_TAG)

    def test_transition_rejects_stable_and_rebuild_rollbacks(self) -> None:
        validate_litert_lm_transition("v0.16.0-native.2", "v0.16.0-3")
        validate_litert_lm_transition("v0.16.0-3", "v0.16.1")
        validate_litert_lm_transition(DEVELOPMENT_TAG, f"{DEVELOPMENT_TAG}-1")
        with self.assertRaisesRegex(ReleaseError, "rollback"):
            validate_litert_lm_transition("v0.16.0-native.2", "v0.16.0-1")
        with self.assertRaisesRegex(ReleaseError, "rollback"):
            validate_litert_lm_transition("v0.16.1", "v0.16.0-3")
        with self.assertRaisesRegex(ReleaseError, "rollback"):
            validate_litert_lm_transition(f"{DEVELOPMENT_TAG}-2", DEVELOPMENT_TAG)
        with self.assertRaisesRegex(ReleaseError, "ordinal alias"):
            validate_litert_lm_transition("v0.16.0-native.2", "v0.16.0-2")
        with self.assertRaisesRegex(ReleaseError, "immediate next ordinal"):
            validate_litert_lm_transition("v0.16.0-native.2", "v0.16.0-42")
        with self.assertRaisesRegex(ReleaseError, "target line at its base"):
            validate_litert_lm_transition("v0.16.0-native.2", "v0.17.0-1")
        with self.assertRaisesRegex(ReleaseError, "immediate next ordinal"):
            validate_litert_lm_transition(DEVELOPMENT_TAG, f"{DEVELOPMENT_TAG}-2")

    def test_stable_rebuild_entry_cli_enforces_opt_in_and_manifest(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        for enabled in (False, True):
            with tempfile.TemporaryDirectory() as temp:
                result = _run_schema2_sync(Path(temp), manifest, release,
                    current_litert_tag="v0.15.0-native.2",
                    allow_stable_rebuild_entry=enabled)
                self.assertEqual(result.returncode, 0 if enabled else 1,
                    result.stdout + result.stderr)
                if not enabled:
                    self.assertIn("target line at its base", result.stderr)
        manifest["platforms"][0]["artifactPaths"].append("../unsafe.so")
        with tempfile.TemporaryDirectory() as temp:
            result = _run_schema2_sync(Path(temp), manifest, release,
                current_litert_tag="v0.15.0-native.2", allow_stable_rebuild_entry=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("v0.15.0-native.2", (Path(temp) / "repo/lib/src/hook/native_release_pins.dart").read_text())

    def test_stable_rebuild_entry_opt_in_preserves_other_guards(self) -> None:
        validate_litert_lm_transition(
            "v0.16.0-native.2", "v0.17.0-1", allow_stable_rebuild_entry=True
        )
        for current, target, error in (
            ("v0.17.0-1", "v0.16.0-3", "rollback"),
            ("v0.17.0-2", "v0.17.0-1", "rollback"),
            ("v0.17.0-native.1", "v0.17.0-1", "ordinal alias"),
            ("v0.17.0-1", "v0.17.0-3", "immediate next ordinal"),
            ("v0.17.0", DEVELOPMENT_TAG, "stable/development"),
            (DEVELOPMENT_TAG, "g111111111111-1", "development line"),
        ):
            with self.subTest(current=current, target=target):
                with self.assertRaisesRegex(ReleaseError, error):
                    validate_litert_lm_transition(
                        current, target, allow_stable_rebuild_entry=True
                    )

    def test_channel_and_development_line_transitions_require_explicit_approval(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "stable/development"):
            validate_litert_lm_transition("v0.16.0", DEVELOPMENT_TAG)
        validate_litert_lm_transition(
            "v0.16.0",
            DEVELOPMENT_TAG,
            allow_channel_transition=True,
        )
        with self.assertRaisesRegex(ReleaseError, "development line"):
            validate_litert_lm_transition(DEVELOPMENT_TAG, "g111111111111")
        validate_litert_lm_transition(
            DEVELOPMENT_TAG,
            "g111111111111",
            allow_development_line_transition=True,
        )
        with self.assertRaisesRegex(ReleaseError, "enter at its base"):
            validate_litert_lm_transition(
                DEVELOPMENT_TAG,
                "g111111111111-1",
                allow_development_line_transition=True,
            )

    def test_atomic_write_rolls_back_every_file_after_partial_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            first = root / "a.txt"
            second = root / "b.txt"
            first.write_text("old-a", encoding="utf-8")
            second.write_text("old-b", encoding="utf-8")
            new_replace_count = 0

            def flaky_replace(source: Path, destination: Path) -> None:
                nonlocal new_replace_count
                if ".new-" in source.name:
                    new_replace_count += 1
                    if new_replace_count == 2:
                        raise OSError("injected replacement failure")
                source.replace(destination)

            with self.assertRaisesRegex(ReleaseError, "Atomic pin update failed"):
                atomic_write_many(
                    {first: "new-a", second: "new-b"},
                    replace_func=flaky_replace,
                )
            self.assertEqual(first.read_text(encoding="utf-8"), "old-a")
            self.assertEqual(second.read_text(encoding="utf-8"), "old-b")

    def test_v017_and_v018_require_exact_android_dawn_repair_provenance(self) -> None:
        expected = [
            ("arm64", "android_arm64", "7282aacdb076ce89f0c9d93107a145b991b99eb1dfbd5b5746dd0d99466ab3c3"),
            ("x64", "android_x86_64", "fcfb9a0b902f7dd3f81f01295f381c10b22a2d5774f95ee0db813f284a0ab087"),
        ]
        for upstream_version in ("v0.17.0", "v0.17.1", "v0.18.0"):
            with self.subTest(upstream_version=upstream_version):
                self.assertEqual(
                    pins.LITERT_PREBUILT_OVERRIDES.get(upstream_version),
                    [
                        {
                            "sourceRepository": "google-ai-edge/LiteRT-LM",
                            "sourceCommit": "f73637c57f0940b53da184e0d5adfc52a4e55eef",
                            "sourcePath": f"prebuilt/{upstream}/libwebgpu_dawn.so",
                            "targetPath": f"bin/android/{arch}/libwebgpu_dawn.so",
                            "sha256": digest,
                        }
                        for arch, upstream, digest in expected
                    ],
                )

    def test_override_table_has_an_entry_for_the_pinned_upstream_version(self) -> None:
        tag = re.search(
            r"const liteRtLmReleaseTag = '([^']+)';",
            (
                Path(__file__).resolve().parents[2]
                / "lib/src/hook/native_release_pins.dart"
            ).read_text(encoding="utf-8"),
        )[1]
        if pins.DEVELOPMENT_LITERT_TAG_RE.fullmatch(tag):
            self.skipTest(
                "the upstream version of a development pin is only in its "
                "release manifest"
            )
        upstream = re.fullmatch(r"(v\d+\.\d+\.\d+)(?:-.+)?", tag)
        self.assertIsNotNone(upstream, f"unrecognized LiteRT-LM pin {tag}")
        self.assertIn(upstream[1], pins.LITERT_PREBUILT_OVERRIDES)

    def test_override_mismatch_names_the_upstream_version_missing_from_the_table(
        self,
    ) -> None:
        manifest, release = _schema2_fixture_payloads()
        tag = manifest["release"]["tag"]
        compatibility_tag = manifest["upstream"]["compatibilityTag"]
        required_bundles = [
            f"{item['platform']}-{item['arch']}" for item in manifest["platforms"]
        ]
        with tempfile.TemporaryDirectory() as temp:
            _materialize_schema2_release_fixtures(Path(temp), manifest, release)
            validate_litert_lm_release_manifest(
                release,
                repo="leehack/litert-lm-native",
                tag=tag,
                release_json_dir=temp,
                required_bundles=required_bundles,
            )
            stale_table = {
                key: value
                for key, value in pins.LITERT_PREBUILT_OVERRIDES.items()
                if key != compatibility_tag
            }
            with patch.object(pins, "LITERT_PREBUILT_OVERRIDES", stale_table):
                with self.assertRaises(ReleaseError) as raised:
                    validate_litert_lm_release_manifest(
                        release,
                        repo="leehack/litert-lm-native",
                        tag=tag,
                        release_json_dir=temp,
                        required_bundles=required_bundles,
                    )
        message = str(raised.exception)
        self.assertIn(
            f"LITERT_PREBUILT_OVERRIDES has no entry for upstream {compatibility_tag}",
            message,
        )
        self.assertIn("bin/android/arm64/libwebgpu_dawn.so", message)
        self.assertIn("tools/prebuilt_overrides.py", message)

    def test_owner_generated_schema_2_manifest_is_consumed_exactly(self) -> None:
        owner_fixture = (
            Path(__file__).resolve().parent
            / "fixtures"
            / "litert_lm_schema2_owner_manifest.json"
        )
        self.assertEqual(
            hashlib.sha256(owner_fixture.read_bytes()).hexdigest(),
            "a0d29aa83dc11a565703a395accfbd4a5ca686305c6607dc3807d417a4952bed",
        )
        manifest = json.loads(owner_fixture.read_text(encoding="utf-8"))
        tag = manifest["release"]["tag"]
        required_bundles = [
            f"{item['platform']}-{item['arch']}" for item in manifest["platforms"]
        ]
        expected_assets = required_litert_release_asset_names(manifest, tag)
        owner_release_fixture = (
            Path(__file__).resolve().parent
            / "fixtures"
            / "litert_lm_schema2_owner_release.json"
        )
        self.assertEqual(
            hashlib.sha256(owner_release_fixture.read_bytes()).hexdigest(),
            "a5352536af34e1a4076c05261766ea85e532eb174be3fee6cd35deb3eb94d8e6",
        )
        release = json.loads(owner_release_fixture.read_text(encoding="utf-8"))
        release_assets = release["assets"]
        manifest_asset = next(
            asset for asset in release_assets if asset["name"] == "manifest.json"
        )
        self.assertEqual(
            {asset["name"] for asset in release_assets}, expected_assets
        )
        with tempfile.TemporaryDirectory() as temp:
            fixture_dir = Path(temp)
            fixture = fixture_dir / f"leehack__litert-lm-native__{tag}__manifest.json"
            fixture.write_bytes(owner_fixture.read_bytes())
            manifest_asset["digest"] = (
                "sha256:" + hashlib.sha256(fixture.read_bytes()).hexdigest()
            )
            upstream_ref_fixture = (
                fixture_dir
                / "google-ai-edge__LiteRT-LM__v0.16.0__commit.json"
            )
            upstream_ref_fixture.write_text(
                json.dumps({"sha": manifest["upstream"]["commit"]}),
                encoding="utf-8",
            )
            native_ref_fixture = (
                fixture_dir
                / f"leehack__litert-lm-native__{tag}__commit.json"
            )
            native_ref_fixture.write_text(
                json.dumps({"sha": manifest["native"]["commit"]}),
                encoding="utf-8",
            )
            checksum_fixture = (
                fixture_dir
                / f"leehack__litert-lm-native__{tag}__SHA256SUMS"
            )
            checksum_fixture.write_text(
                "".join(
                    f"{artifact['sha256']}  {artifact['path']}\n"
                    for artifact in manifest["artifacts"]
                ),
                encoding="utf-8",
            )
            checksum_asset = next(
                asset for asset in release_assets if asset["name"] == "SHA256SUMS"
            )
            checksum_asset["digest"] = (
                "sha256:" + hashlib.sha256(checksum_fixture.read_bytes()).hexdigest()
            )
            validate_litert_lm_release_manifest(
                release,
                repo="leehack/litert-lm-native",
                tag=tag,
                release_json_dir=str(fixture_dir),
                required_bundles=required_bundles,
            )

            scalar_cases = (
                (
                    manifest["artifacts"][0],
                    "runtime",
                    ["native"],
                    "artifact runtime",
                ),
                (
                    manifest["platforms"][0],
                    "artifactPaths",
                    [["nested"]],
                    "artifact paths are invalid",
                ),
                (
                    manifest["platforms"][0],
                    "accelerators",
                    [{"x": "metal"}],
                    "platform accelerators are invalid",
                ),
                (
                    manifest["abi"],
                    "streamProxyCallback",
                    True,
                    "stream proxy callback ABI must be an integer",
                ),
                (
                    manifest["realModelSmokes"][0],
                    "abiVersion",
                    True,
                    "smoke ABI version must be an integer",
                ),
                (
                    manifest["realModelSmokes"][0]["fixture"],
                    "sampleCount",
                    True,
                    "sample count must be an integer",
                ),
            )
            for target, key, malformed, expected_error in scalar_cases:
                with self.subTest(malformed_schema_scalar=key):
                    original = target[key]
                    target[key] = malformed
                    fixture.write_text(json.dumps(manifest), encoding="utf-8")
                    manifest_asset["digest"] = (
                        "sha256:" + hashlib.sha256(fixture.read_bytes()).hexdigest()
                    )
                    with self.assertRaisesRegex(ReleaseError, expected_error):
                        validate_litert_lm_release_manifest(
                            release,
                            repo="leehack/litert-lm-native",
                            tag=tag,
                            release_json_dir=str(fixture_dir),
                            required_bundles=required_bundles,
                        )
                    target[key] = original
            fixture.write_bytes(owner_fixture.read_bytes())
            manifest_asset["digest"] = (
                "sha256:" + hashlib.sha256(fixture.read_bytes()).hexdigest()
            )

            native_ref_fixture.write_text(
                json.dumps({"sha": "1" * 40}), encoding="utf-8"
            )
            with self.assertRaisesRegex(ReleaseError, "exact native tag"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            native_ref_fixture.write_text(
                json.dumps({"sha": manifest["native"]["commit"]}),
                encoding="utf-8",
            )

            checksum_digest = checksum_asset["digest"]
            checksum_asset["digest"] = [checksum_digest]
            with self.assertRaisesRegex(ReleaseError, "invalid GitHub SHA-256"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            checksum_asset["digest"] = checksum_digest

            original_artifact_digest = manifest["artifacts"][0]["sha256"]
            manifest["artifacts"][0]["sha256"] = int("1" * 64)
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = (
                "sha256:" + hashlib.sha256(fixture.read_bytes()).hexdigest()
            )
            with self.assertRaisesRegex(ReleaseError, "artifact digest"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["artifacts"][0]["sha256"] = original_artifact_digest

            original_native_commit = manifest["native"]["commit"]
            numeric_native_commit = int("1" * 40)
            manifest["native"]["commit"] = numeric_native_commit
            release["target_commitish"] = numeric_native_commit
            for smoke in manifest["realModelSmokes"]:
                smoke["nativeCommit"] = numeric_native_commit
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = (
                "sha256:" + hashlib.sha256(fixture.read_bytes()).hexdigest()
            )
            with self.assertRaisesRegex(ReleaseError, "native commit"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["native"]["commit"] = original_native_commit
            release["target_commitish"] = original_native_commit
            for smoke in manifest["realModelSmokes"]:
                smoke["nativeCommit"] = original_native_commit
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = (
                "sha256:" + hashlib.sha256(fixture.read_bytes()).hexdigest()
            )

            fixture.write_bytes(b"\xff")
            with self.assertRaisesRegex(ReleaseError, "Failed to read release manifest"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            fixture.write_bytes(owner_fixture.read_bytes())
            manifest_asset["digest"] = (
                "sha256:" + hashlib.sha256(fixture.read_bytes()).hexdigest()
            )

            upstream_ref_fixture.write_text("{", encoding="utf-8")
            with self.assertRaisesRegex(ReleaseError, "Failed to resolve exact commit"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            upstream_ref_fixture.write_text(
                json.dumps({"sha": manifest["upstream"]["commit"]}),
                encoding="utf-8",
            )

            checksum_fixture.write_bytes(b"\xff")
            checksum_asset["digest"] = (
                "sha256:" + hashlib.sha256(checksum_fixture.read_bytes()).hexdigest()
            )
            with self.assertRaisesRegex(ReleaseError, "not valid UTF-8"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            checksum_fixture.write_text(
                "".join(
                    f"{artifact['sha256']}  {artifact['path']}\n"
                    for artifact in manifest["artifacts"]
                ),
                encoding="utf-8",
            )
            checksum_asset["digest"] = (
                "sha256:" + hashlib.sha256(checksum_fixture.read_bytes()).hexdigest()
            )

            upstream_ref_fixture.write_text(
                json.dumps({"sha": "1" * 40}), encoding="utf-8"
            )
            with self.assertRaisesRegex(ReleaseError, "exact upstream ref"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            upstream_ref_fixture.write_text(
                json.dumps({"sha": manifest["upstream"]["commit"]}),
                encoding="utf-8",
            )

            original_checksum_text = checksum_fixture.read_text(encoding="utf-8")
            checksum_lines = original_checksum_text.splitlines()
            for checksum_text, expected_error in (
                ("\n".join(checksum_lines[1:]) + "\n", "missing="),
                (
                    original_checksum_text + f"{'4' * 64}  unexpected.bin\n",
                    "unexpected=",
                ),
                (
                    original_checksum_text + checksum_lines[0] + "\n",
                    "duplicates",
                ),
            ):
                checksum_fixture.write_text(checksum_text, encoding="utf-8")
                checksum_asset["digest"] = (
                    "sha256:"
                    + hashlib.sha256(checksum_fixture.read_bytes()).hexdigest()
                )
                with self.assertRaisesRegex(ReleaseError, expected_error):
                    validate_litert_lm_release_manifest(
                        release,
                        repo="leehack/litert-lm-native",
                        tag=tag,
                        release_json_dir=str(fixture_dir),
                        required_bundles=required_bundles,
                    )

            checksum_fixture.write_text(
                original_checksum_text.replace(
                    manifest["artifacts"][0]["sha256"], "2" * 64, 1
                ),
                encoding="utf-8",
            )
            checksum_asset["digest"] = (
                "sha256:" + hashlib.sha256(checksum_fixture.read_bytes()).hexdigest()
            )
            with self.assertRaisesRegex(ReleaseError, "mismatched="):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            checksum_fixture.write_text(original_checksum_text, encoding="utf-8")
            checksum_asset["digest"] = "sha256:" + "3" * 64
            with self.assertRaisesRegex(ReleaseError, "bytes do not match"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            checksum_asset["digest"] = (
                "sha256:" + hashlib.sha256(checksum_fixture.read_bytes()).hexdigest()
            )

            runtime_asset = next(
                asset
                for asset in release_assets
                if asset["name"].startswith("litert-lm-native-runtime-")
            )
            runtime_asset["digest"] = "sha256:not-a-sha256"
            with self.assertRaisesRegex(ReleaseError, "invalid GitHub SHA-256"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            runtime_asset["digest"] = "sha256:" + "f" * 64

            for asset_name in sorted(expected_assets):
                with self.subTest(owner_rejected_missing_asset=asset_name):
                    removed_index = next(
                        index
                        for index, asset in enumerate(release_assets)
                        if asset["name"] == asset_name
                    )
                    removed = release_assets.pop(removed_index)
                    with self.assertRaisesRegex(ReleaseError, "owner policy"):
                        validate_litert_release_asset_inventory(release, manifest, tag)
                    release_assets.insert(removed_index, removed)
            release_assets.append(
                {"name": "unexpected-owner-rejected.bin", "digest": "sha256:" + "f" * 64}
            )
            with self.assertRaisesRegex(ReleaseError, "owner policy"):
                validate_litert_release_asset_inventory(release, manifest, tag)
            release_assets.pop()

            release_assets.append(dict(release_assets[0]))
            with self.assertRaisesRegex(ReleaseError, "duplicates"):
                validate_litert_release_asset_inventory(release, manifest, tag)
            release_assets.pop()

            original_digest = release_assets[0]["digest"]
            release_assets[0]["digest"] = "sha256:not-a-digest"
            with self.assertRaisesRegex(ReleaseError, "invalid GitHub SHA-256"):
                validate_litert_release_asset_inventory(release, manifest, tag)
            release_assets[0]["digest"] = original_digest

            release["draft"] = True
            with self.assertRaisesRegex(ReleaseError, "published, not a draft"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            release["draft"] = False
            release["prerelease"] = not release["prerelease"]
            with self.assertRaisesRegex(ReleaseError, "prerelease classification"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            release["prerelease"] = manifest["release"]["githubPrerelease"]

            removed_override = manifest["upstream"]["prebuiltOverrides"].pop()
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "owner policy"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["upstream"]["prebuiltOverrides"].append(removed_override)

            override_target = removed_override["targetPath"]
            override_artifact = next(
                artifact
                for artifact in manifest["artifacts"]
                if artifact["path"] == override_target
            )
            manifest["artifacts"].remove(override_artifact)
            override_platform = next(
                platform
                for platform in manifest["platforms"]
                if override_target in platform["artifactPaths"]
            )
            override_platform["artifactPaths"].remove(override_target)
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "override target provenance"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["artifacts"].append(override_artifact)
            override_platform["artifactPaths"].append(override_target)

            removed_artifact = next(
                artifact
                for artifact in manifest["artifacts"]
                if "CLiteRTLM-xcframework" in artifact["path"]
            )
            manifest["artifacts"].remove(removed_artifact)
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "SPM artifact inventory"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["artifacts"].append(removed_artifact)

            smoke = manifest["realModelSmokes"][0]
            smoke["model"]["sha256"] = "a" * 64
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "owner-pinned asset"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            smoke["model"]["sha256"] = (
                "97abdeea122d579229091659c24c59d988c6419d453a200f6471241a53b9a9b9"
            )

            smoke["source"]["model"] = "https://example.invalid/model.tflite"
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "source provenance"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            smoke["source"]["model"] = (
                "https://huggingface.co/litert-community/moonshine-tiny/resolve/"
                "beb49ee5028b4fb21eb989bcbd2db30a433373db/"
                "moonshine_tiny_5s_i8.tflite"
            )

            original_library_digest = smoke["library"]["sha256"]
            smoke["library"]["sha256"] = "b" * 64
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "runtime artifact"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            smoke["library"]["sha256"] = original_library_digest

            smoke["expectation"]["value"] = "fabricated"
            smoke["transcript"] = "fabricated"
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "owner-pinned transcript"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            smoke["expectation"]["value"] = "country"
            smoke["transcript"] = "ask not what your country can do for you"

            manifest["platforms"][0]["artifactPaths"].append(
                manifest["platforms"][0]["artifactPaths"][0]
            )
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "artifact paths are invalid"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["platforms"][0]["artifactPaths"].pop()

            original_platforms = manifest["platforms"]
            manifest["platforms"] = {"not": "a list"}
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "platforms must be a list"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["platforms"] = original_platforms[:-1]
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(
                ReleaseError, "exactly 8 finalized platform bundles; found 7"
            ):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["platforms"] = original_platforms
            original_second_platform = manifest["platforms"][1]
            manifest["platforms"][1] = dict(manifest["platforms"][0])
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(
                ReleaseError, "missing .*; duplicates .*"
            ):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["platforms"][1] = original_second_platform

            manifest["platforms"] = [
                *original_platforms,
                {
                    "accelerators": [],
                    "arch": "x64",
                    "artifactPaths": [
                        "bin/macos/x64/libCLiteRTLM_mac.dylib",
                        "bin/macos/x64/libLiteRtLm.dylib",
                    ],
                    "platform": "macos",
                    "releaseAsset": f"litert-lm-native-runtime-macos-x64-{tag}.tar.gz",
                },
            ]
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(
                ReleaseError, "exactly 8 finalized platform bundles; found 9"
            ):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )
            manifest["platforms"] = original_platforms
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(
                ReleaseError, "finalized 8-platform schema-2 contract"
            ):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=[*required_bundles, "macos-x64"],
                )

            del manifest["capabilities"]["streamChunkAccessors"]
            fixture.write_text(json.dumps(manifest), encoding="utf-8")
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "owner schema 2"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=str(fixture_dir),
                    required_bundles=required_bundles,
                )

    def test_schema_2_prepares_the_real_apple_target_transition(self) -> None:
        fixture_root = Path(__file__).resolve().parent / "fixtures"
        manifest = json.loads(
            (fixture_root / "litert_lm_schema2_owner_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        release = json.loads(
            (fixture_root / "litert_lm_schema2_owner_release.json").read_text(
                encoding="utf-8"
            )
        )
        package_swift = (
            Path(__file__).resolve().parents[2]
            / "packages"
            / "llamadart_litert_lm_flutter"
            / "darwin"
            / "llamadart_litert_lm_flutter"
            / "Package.swift"
        )
        original = LEGACY_LITERT_SWIFT.read_text(encoding="utf-8")

        prepared = prepare_litert_lm_package_swift(
            original,
            release=release,
            manifest=manifest,
            resolved_tag="v0.16.0-3",
        )

        self.assertEqual(
            LEGACY_LITERT_SWIFT.read_text(encoding="utf-8"),
            original,
            "pin preparation must not modify the checked-in manifest",
        )
        self.assertIn('let liteRtLmTag = "v0.16.0-3"', prepared)
        self.assertNotIn("GemmaModelConstraintProvider", prepared)
        self.assertIn('name: "CLiteRTLMMac"', prepared)
        self.assertIn(
            'name: "CLiteRTLMMac", condition: .when(platforms: [.macOS])',
            prepared,
        )
        self.assertIn(
            'name: "LiteRtLm", condition: .when(platforms: [.iOS, .macOS])',
            prepared,
        )
        expected_targets = {
            "LiteRtLm",
            "CLiteRTLM",
            "CLiteRTLMMac",
            "LiteRtMetalAccelerator",
            "LiteRtTopKMetalSampler",
        }
        for target in expected_targets:
            asset_name = (
                f"litert-lm-native-apple-{target}-xcframework-v0.16.0-3.zip"
            )
            asset = next(
                item for item in release["assets"] if item["name"] == asset_name
            )
            self.assertIn(
                f'checksum: "{asset["digest"].removeprefix("sha256:")}"',
                prepared,
            )

    def test_schema_2_keeps_required_ios_provider_and_repairs_missing_target(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        tag = manifest["release"]["tag"]
        original = LEGACY_LITERT_SWIFT.read_text(encoding="utf-8")
        previous = prepare_litert_lm_package_swift(
            original, release=release, manifest=manifest, resolved_tag=tag,
        )
        provider = "GemmaModelConstraintProvider"
        asset_name = f"litert-lm-native-apple-{provider}-xcframework-{tag}.zip"
        release["assets"].append({"name": asset_name, "digest": "sha256:" + "a" * 64})
        for platform in manifest["platforms"]:
            if platform["platform"] == "ios":
                platform["artifactPaths"].append(
                    f'bin/ios/{platform["arch"]}/{provider}.framework/{provider}'
                )
        for label, source in (
            ("legacy", original),
            ("schema2", previous),
            ("modern-provider", MODERN_LITERT_SWIFT.read_text(encoding="utf-8")),
        ):
            with self.subTest(source=label):
                prepared = prepare_litert_lm_package_swift(
                    source, release=release, manifest=manifest, resolved_tag=tag,
                )
                self.assertEqual(prepared.count('name: "GemmaModelConstraintProvider"'), 2)
                self.assertIn('.target(name: "GemmaModelConstraintProvider", condition: .when(platforms: [.iOS]))', prepared)
                self.assertIn('.target(name: "CLiteRTLMMac", condition: .when(platforms: [.macOS]))', prepared)
                self.assertIn(asset_name.replace(tag, r"\(liteRtLmTag)"), prepared)
                self.assertIn('checksum: "' + 'a' * 64 + '"', prepared)
                self.assertEqual(prepare_litert_lm_package_swift(
                    prepared, release=release, manifest=manifest, resolved_tag=tag,
                ), prepared)
        wrong_platform = prepared.replace(
            '.target(name: "GemmaModelConstraintProvider", condition: .when(platforms: [.iOS]))',
            '.target(name: "GemmaModelConstraintProvider", condition: .when(platforms: [.macOS]))',
        )
        with self.assertRaisesRegex(ReleaseError, "exactly one iOS dependency"):
            prepare_litert_lm_package_swift(
                wrong_platform, release=release, manifest=manifest, resolved_tag=tag,
            )
        release["assets"] = [asset for asset in release["assets"] if asset["name"] != asset_name]
        with self.assertRaisesRegex(ReleaseError, "GemmaModelConstraintProvider"):
            prepare_litert_lm_package_swift(
                original, release=release, manifest=manifest, resolved_tag=tag,
            )

    def test_schema_2_removes_only_unused_modern_ios_provider(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        tag = manifest["release"]["tag"]
        original = MODERN_LITERT_SWIFT.read_text(encoding="utf-8")
        prepared = prepare_litert_lm_package_swift(
            original, release=release, manifest=manifest, resolved_tag=tag,
        )
        self.assertEqual(MODERN_LITERT_SWIFT.read_text(encoding="utf-8"), original)
        self.assertNotIn("GemmaModelConstraintProvider", prepared)
        for dependency in (
            'name: "CLiteRTLMMac", condition: .when(platforms: [.macOS])',
            'name: "LiteRtLm", condition: .when(platforms: [.iOS, .macOS])',
            'name: "LiteRtMetalAccelerator", condition: .when(platforms: [.iOS])',
            'name: "LiteRtTopKMetalSampler", condition: .when(platforms: [.iOS])',
        ):
            self.assertIn(dependency, prepared)
        self.assertEqual(
            {name for name, _ in pins.swift_native_repo_binary_targets(
                prepared, tag_variable="liteRtLmTag", current_tag=tag,
            )},
            pins.litert_schema2_apple_targets(manifest, tag),
        )
        for target in pins.litert_schema2_apple_targets(manifest, tag):
            asset = next(item for item in release["assets"] if item["name"] ==
                f"litert-lm-native-apple-{target}-xcframework-{tag}.zip")
            self.assertIn(f'checksum: "{asset["digest"][7:]}"', prepared)
        self.assertEqual(prepare_litert_lm_package_swift(
            prepared, release=release, manifest=manifest, resolved_tag=tag,
        ), prepared)

    def test_schema_2_modern_provider_removal_rejects_ambiguous_topology(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        tag = manifest["release"]["tag"]
        original = MODERN_LITERT_SWIFT.read_text(encoding="utf-8")
        dependency = '.target(name: "GemmaModelConstraintProvider", condition: .when(platforms: [.iOS])),'
        provider_block = re.search(
            r'(?m)^[ \t]*nativeRepoBinaryTarget\(\s*name: "GemmaModelConstraintProvider",.*?^[ \t]*\),',
            original, re.DOTALL,
        ).group()
        mac_block = re.search(
            r'(?m)^[ \t]*nativeRepoBinaryTarget\(\s*name: "CLiteRTLMMac",.*?^[ \t]*\),',
            original, re.DOTALL,
        ).group()
        mac_dependency = '.target(name: "CLiteRTLMMac", condition: .when(platforms: [.macOS])),'
        shared_dependency = '.target(name: "LiteRtLm", condition: .when(platforms: [.iOS, .macOS])),'
        metal_dependency = '.target(name: "LiteRtMetalAccelerator", condition: .when(platforms: [.iOS])),'
        for label, source in (
            ("duplicate-block", original.replace(provider_block, provider_block + "\n" + provider_block)),
            ("duplicate-dependency", original.replace(dependency, dependency + "\n" + dependency)),
            ("missing-dependency", original.replace(dependency, "")),
            ("wrong-provider-platform", original.replace(dependency, dependency.replace(".iOS", ".macOS"))),
            ("shared-provider-platform", original.replace(dependency, dependency.replace(".iOS", ".iOS, .macOS"))),
            ("malformed-block", original.replace(provider_block, provider_block.replace("checksum:", "invalidChecksum:"))),
            ("malformed-artifact", original.replace(provider_block, provider_block.replace("apple-GemmaModelConstraintProvider-", "apple-OtherProvider-"))),
            ("wrong-mac-platform", original.replace('name: "CLiteRTLMMac", condition: .when(platforms: [.macOS])', 'name: "CLiteRTLMMac", condition: .when(platforms: [.iOS])')),
            ("wrong-shared-platform", original.replace('name: "LiteRtLm", condition: .when(platforms: [.iOS, .macOS])', 'name: "LiteRtLm", condition: .when(platforms: [.iOS])')),
            ("duplicate-mac-block", original.replace(mac_block, mac_block + "\n" + mac_block)),
            ("duplicate-mac-dependency", original.replace(mac_dependency, mac_dependency + "\n" + mac_dependency)),
            ("duplicate-shared-dependency", original.replace(shared_dependency, shared_dependency + "\n" + shared_dependency)),
            ("unconditional-shared-reference", original.replace(shared_dependency, shared_dependency + '\n.target(name: "LiteRtLm"),')),
            ("extra-metal-platform", original.replace(metal_dependency, metal_dependency + "\n" + metal_dependency.replace(".iOS", ".macOS"))),
            ("dangling-dependency", original.replace(dependency, dependency + '\n.target(name: "MissingTarget"),')),
            ("formatted-dangling-dependency", original.replace(dependency, dependency + '\n.target (\n name : "MissingTarget"\n),')),
            ("string-dependency", original.replace(dependency, dependency + '\n"MissingTarget",')),
            ("dynamic-dependency", original.replace(dependency, dependency + '\n.target(name: dynamicTarget),')),
        ):
            with self.subTest(source=label), self.assertRaisesRegex(ReleaseError, "provider|Provider|owner inventory"):
                prepare_litert_lm_package_swift(
                    source, release=release, manifest=manifest, resolved_tag=tag,
                )

    def test_schema_2_modern_provider_removal_rejects_missing_required_target(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        tag = manifest["release"]["tag"]
        original = MODERN_LITERT_SWIFT.read_text(encoding="utf-8")
        missing, count = re.subn(
            r'(?m)^[ \t]*nativeRepoBinaryTarget\(\s*name: "LiteRtMetalAccelerator",.*?^[ \t]*\),\n',
            "", original, flags=re.DOTALL,
        )
        self.assertEqual(count, 1)
        for label, source in (
            ("missing-required", missing),
            ("unexpected-target", original.replace('name: "CLiteRTLMMac",', 'name: "UnexpectedTarget",')),
        ):
            with self.subTest(source=label), self.assertRaisesRegex(ReleaseError, "owner inventory"):
                prepare_litert_lm_package_swift(
                    source, release=release, manifest=manifest, resolved_tag=tag,
                )

    def test_schema_2_modern_provider_removal_rejects_valid_wrong_artifact(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        tag = manifest["release"]["tag"]
        original = MODERN_LITERT_SWIFT.read_text(encoding="utf-8")
        for target, wrong_asset in (
            ("LiteRtLm", "LiteRtMetalAccelerator"),
            ("CLiteRTLM", "LiteRtMetalAccelerator"),
            ("LiteRtMetalAccelerator", "CLiteRTLM"),
            ("CLiteRTLMMac", "CLiteRTLM"),
        ):
            with self.subTest(target=target), self.assertRaisesRegex(ReleaseError, "canonical.*artifact template"):
                source = original.replace(
                    f'artifactName: "litert-lm-native-apple-{target}-xcframework-',
                    f'artifactName: "litert-lm-native-apple-{wrong_asset}-xcframework-',
                )
                self.assertNotEqual(source, original)
                prepare_litert_lm_package_swift(
                    source, release=release, manifest=manifest, resolved_tag=tag,
                )

    def test_schema_2_sync_modern_provider_removal_preserves_macos_inventory(self) -> None:
        # This retained v0.16 contract fixture exercises the mechanism, not a
        # published v7 release. Its macOS inventory mirrors the required provider.
        manifest, release = _schema2_fixture_payloads()
        platform = next(item for item in manifest["platforms"]
            if item["platform"] == "macos" and item["arch"] == "arm64")
        companion = "bin/macos/arm64/libGemmaModelConstraintProvider.dylib"
        platform["artifactPaths"].append(companion)
        artifact = dict(next(item for item in manifest["artifacts"]
            if item["path"] == "bin/macos/arm64/libLiteRtLm.dylib"))
        artifact.update(path=companion, fileName="libGemmaModelConstraintProvider.dylib")
        manifest["artifacts"].append(artifact)
        # An optional provider archive must not become an iOS dependency.
        tag = manifest["release"]["tag"]
        archive = f"litert-lm-native-apple-GemmaModelConstraintProvider-xcframework-{tag}.zip"
        artifact = dict(next(item for item in manifest["artifacts"]
            if item["path"].startswith("dist/spm/")))
        artifact.update(path=f"dist/spm/{tag}/{archive}", fileName=archive, sha256="a" * 64)
        manifest["artifacts"].append(artifact)
        release["assets"].append({"name": archive, "digest": "sha256:" + "a" * 64})
        current_tag = "v0.16.0-native.2"
        modern = MODERN_LITERT_SWIFT.read_text(encoding="utf-8").replace(
            'let liteRtLmTag = "v0.17.0-6"', f'let liteRtLmTag = "{current_tag}"',
        )
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = _run_schema2_sync(
                root, manifest, release, current_litert_tag=current_tag,
                starting_swift=modern,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            repo = root / "repo"
            swift = (repo / "packages/llamadart_litert_lm_flutter/darwin/llamadart_litert_lm_flutter/Package.swift").read_text()
            self.assertNotIn("GemmaModelConstraintProvider", swift)
            self.assertIn('name: "CLiteRTLMMac", condition: .when(platforms: [.macOS])', swift)
            for relative in (
                "tool/macos_litert_lm_prepare_app.sh",
                "lib/src/backends/litert_lm/litert_lm_runtime.dart",
            ):
                text = (repo / relative).read_text()
                self.assertIn("libGemmaModelConstraintProvider.dylib", text)
                self.assertIn(
                    "LiteRtLm.framework/Versions/A/Dependencies/"
                    "libGemmaModelConstraintProvider.dylib",
                    text,
                )
            runtime = (repo / "lib/src/backends/litert_lm/litert_lm_runtime.dart").read_text()
            self.assertIn("GemmaModelConstraintProvider.framework/Versions/A/GemmaModelConstraintProvider", runtime)
            self.assertIn("libGemmaModelConstraintProvider.dylib", (repo / "lib/src/hook/native_release_pins.dart").read_text())

    def test_schema_2_sync_rejects_modern_provider_without_partial_pin_edits(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        current_tag = "v0.16.0-native.2"
        original = MODERN_LITERT_SWIFT.read_text(encoding="utf-8").replace(
            'let liteRtLmTag = "v0.17.0-6"', f'let liteRtLmTag = "{current_tag}"',
        )
        dependency = '.target(name: "GemmaModelConstraintProvider", condition: .when(platforms: [.iOS])),'
        for label, modern in (
            ("wrong-platform", original.replace(dependency, dependency.replace(".iOS", ".macOS"))),
            ("duplicate-reference", original.replace(dependency, dependency + "\n" + dependency)),
            ("runtime-to-metal-asset", original.replace('artifactName: "litert-lm-native-apple-LiteRtLm-xcframework-', 'artifactName: "litert-lm-native-apple-LiteRtMetalAccelerator-xcframework-')),
            ("capi-to-metal-asset", original.replace('artifactName: "litert-lm-native-apple-CLiteRTLM-xcframework-', 'artifactName: "litert-lm-native-apple-LiteRtMetalAccelerator-xcframework-')),
            ("metal-to-capi-asset", original.replace('artifactName: "litert-lm-native-apple-LiteRtMetalAccelerator-xcframework-', 'artifactName: "litert-lm-native-apple-CLiteRTLM-xcframework-')),
            ("dangling-dependency", original.replace(dependency, dependency + '\n.target(name: "MissingTarget"),')),
            ("formatted-dangling-dependency", original.replace(dependency, dependency + '\n.target (\n name : "MissingTarget"\n),')),
            ("string-dependency", original.replace(dependency, dependency + '\n"MissingTarget",')),
        ):
            with self.subTest(source=label), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                result = _run_schema2_sync(
                    root, manifest, release, current_litert_tag=current_tag,
                    starting_swift=modern,
                )
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("provider", result.stdout + result.stderr)
                repo = root / "repo"
                for path in repo.rglob("*"):
                    if not path.is_file():
                        continue
                    relative = path.relative_to(repo)
                    expected = (Path(__file__).resolve().parents[2] / relative).read_text()
                    if relative.name == "Package.swift":
                        expected = modern
                    elif relative.name == "native_release_pins.dart":
                        expected = re.sub(
                            r"const liteRtLmReleaseTag = '[^']+';",
                            f"const liteRtLmReleaseTag = '{current_tag}';", expected,
                        )
                    elif relative.as_posix() == "hook/build.dart":
                        expected = _hook_for_litert_swift(expected, modern)
                    self.assertEqual(path.read_text(), expected, str(relative))

    def test_schema_2_prepares_hook_libraries_from_owner_inventory(self) -> None:
        fixture_root = Path(__file__).resolve().parent / "fixtures"
        manifest = json.loads(
            (fixture_root / "litert_lm_schema2_owner_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        pins_path = Path(__file__).resolve().parents[2] / "lib/src/hook/native_release_pins.dart"
        prepared = pins_path.read_text(encoding="utf-8")
        expected = litert_schema2_bundle_required_libraries(manifest)
        for bundle, libraries in expected.items():
            prepared = replace_litert_lm_bundle_required_libraries(
                prepared,
                bundle,
                libraries,
            )

        self.assertNotIn("GemmaModelConstraintProvider", prepared)
        self.assertIn(
            "requiredLibraries: {'libLiteRtLm.so', 'libwebgpu_dawn.so'},",
            prepared,
        )
        self.assertIn("requiredLibraries: {'LiteRtLm.dll'},", prepared)
        for bundle, libraries in expected.items():
            bundle_start = prepared.index(f"LiteRtLmBundleSpec(\n    '{bundle}',")
            bundle_end = prepared.index("\n  ),", bundle_start)
            block = prepared[bundle_start:bundle_end]
            required_block = block[block.index("requiredLibraries:") :]
            self.assertEqual(
                set(re.findall(r"'([^']+)'", required_block)),
                set(libraries),
            )

    def test_schema_2_ios_framework_metadata_is_not_a_flat_library(self) -> None:
        paths = [
            "bin/ios/arm64/CLiteRTLM.framework/CLiteRTLM",
            "bin/ios/arm64/CLiteRTLM.framework/Info.plist",
            "bin/ios/arm64/LiteRtLm.framework/LiteRtLm",
            "bin/ios/arm64/LiteRtLm.framework/Info.plist",
            "bin/ios/arm64/libLiteRtLm.dylib",
        ]
        manifest = {"platforms": [{"platform": "ios", "arch": "arm64",
                                   "artifactPaths": paths}]}
        self.assertEqual(litert_schema2_bundle_required_libraries(manifest), {
            "ios-arm64": ("CLiteRTLM", "LiteRtLm")})
        for extra in (paths[0], paths[1],
                      "bin/ios/arm64/Other.framework/LiteRtLm",
                      "bin/ios/arm64/../Other.framework/Info.plist"):
            with self.subTest(extra=extra):
                manifest["platforms"][0]["artifactPaths"] = paths + [extra]
                with self.assertRaises(ReleaseError):
                    litert_schema2_bundle_required_libraries(manifest)
        manifest["platforms"][0]["artifactPaths"] = [paths[1], paths[3]]
        with self.assertRaisesRegex(ReleaseError, "no runtime libraries"):
            litert_schema2_bundle_required_libraries(manifest)

    def test_ios_raw_inputs_require_canonical_frameworks(self) -> None:
        for arch in ("arm64", "arm64-sim"):
            for raw, framework in (
                ("libLiteRtLm.dylib", "LiteRtLm"),
                ("libLiteRt.dylib", "LiteRtLm"),
                ("libGemmaModelConstraintProvider.dylib", "GemmaModelConstraintProvider"),
                ("libLiteRtMetalAccelerator.dylib", "LiteRtMetalAccelerator"),
                ("libLiteRtTopKMetalSampler.dylib", "LiteRtTopKMetalSampler"),
            ):
                paths = [f"bin/ios/{arch}/{raw}"]
                manifest = {"platforms": [{"platform": "ios", "arch": arch,
                    "artifactPaths": paths}]}
                with self.subTest(arch=arch, raw=raw):
                    with self.assertRaisesRegex(ReleaseError, "no canonical framework"):
                        litert_schema2_bundle_required_libraries(manifest)
                    paths.append(f"bin/ios/{arch}/{framework}.framework/{framework}")
                    self.assertEqual(litert_schema2_bundle_required_libraries(manifest),
                        {f"ios-{arch}": (framework,)})

    def test_schema_2_framework_metadata_filter_is_platform_and_path_scoped(self) -> None:
        for platform, arch, paths in (
            ("macos", "arm64", ["bin/macos/arm64/A.framework/Info.plist", "bin/macos/arm64/B.framework/Info.plist"]),
            ("ios", "arm64", ["bin/ios/arm64-sim/A.framework/Info.plist", "bin/ios/arm64-sim/B.framework/Info.plist"]),
            ("ios", "arm64", ["bin/ios/arm64/A.framework/extra/Info.plist", "bin/ios/arm64/B.framework/extra/Info.plist"]),
        ):
            with self.subTest(platform=platform, paths=paths):
                manifest = {"platforms": [{"platform": platform, "arch": arch,
                    "artifactPaths": [
                        f"bin/ios/{arch}/LiteRtLm.framework/LiteRtLm" if platform == "ios"
                        else f"bin/{platform}/{arch}/libLiteRtLm.dylib", *paths]}]}
                with self.assertRaisesRegex(ReleaseError, "duplicated"):
                    litert_schema2_bundle_required_libraries(manifest)

    def test_schema_2_windows_import_library_is_not_loaded(self) -> None:
        paths = ["bin/windows/x64/LiteRtLm.dll",
                 "bin/windows/x64/libGemmaModelConstraintProvider.dll",
                 "bin/windows/x64/libGemmaModelConstraintProvider.lib"]
        manifest = {"platforms": [{"platform": "windows", "arch": "x64",
                                   "artifactPaths": paths}]}
        self.assertEqual(litert_schema2_bundle_required_libraries(manifest), {
            "windows-x64": ("LiteRtLm.dll", "libGemmaModelConstraintProvider.dll")})
        manifest["platforms"][0]["artifactPaths"] = paths[::2]
        with self.assertRaisesRegex(ReleaseError, "no matching DLL"):
            litert_schema2_bundle_required_libraries(manifest)

    def test_schema_2_linked_desktop_hosts_do_not_require_prebuilt_litert(self) -> None:
        def manifest(tag: str | None) -> dict:
            value: dict = {"platforms": [
                {"platform": platform, "arch": arch, "artifactPaths": [
                    f"bin/{platform}/{arch}/{name}" for name in names]}
                for platform, arch, names in (
                    ("linux", "x64", ["libLiteRt.so", "libLiteRtLm.so"]),
                    ("windows", "x64", ["LiteRtLm.dll", "libLiteRt.dll"]),
                    ("macos", "arm64", ["libLiteRt.dylib", "libLiteRtLm.dylib"]),
                )]}
            if tag is not None:
                value["release"] = {"tag": tag}
            return value

        for tag in ("v0.19.1-1", "v0.19.1-2", "v0.19.2", "v0.20.0"):
            with self.subTest(tag=tag):
                self.assertEqual(litert_schema2_bundle_required_libraries(manifest(tag)), {
                    "linux-x64": ("libLiteRtLm.so",),
                    "windows-x64": ("LiteRtLm.dll",),
                    "macos-arm64": ("libLiteRt.dylib", "libLiteRtLm.dylib"),
                })
        for tag in (None, "v0.19.0", "v0.19.1", "v0.18.1-4", "v0.16.0-native.2", "g83ce6067f2e2"):
            with self.subTest(tag=tag):
                bundles = litert_schema2_bundle_required_libraries(manifest(tag))
                self.assertIn("libLiteRt.so", bundles["linux-x64"])
                self.assertIn("libLiteRt.dll", bundles["windows-x64"])

    def test_schema_2_hook_inventory_rejects_unsafe_library_names(self) -> None:
        fixture_root = Path(__file__).resolve().parent / "fixtures"
        original = json.loads(
            (fixture_root / "litert_lm_schema2_owner_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        for filename in (
            "libx','injected.so",
            "libx$interpolated.so",
            "libx with space.so",
            "libx;command.so",
            "../injected.so",
            r"bin\android\arm64\libx.so",
        ):
            with self.subTest(filename=filename):
                manifest = json.loads(json.dumps(original))
                manifest["platforms"][0]["artifactPaths"][0] = (
                    f"bin/android/arm64/{filename}"
                )
                with self.assertRaisesRegex(
                    ReleaseError,
                    "platform artifact paths are invalid|library names are invalid",
                ):
                    litert_schema2_bundle_required_libraries(manifest)

    def test_schema_2_sync_rejects_manifest_added_spm_archive(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        tag = manifest["release"]["tag"]
        extra_path = f"dist/spm/{tag}/unexpected-extra.zip"
        extra_artifact = dict(
            next(
                artifact
                for artifact in manifest["artifacts"]
                if artifact["path"].startswith("dist/spm/")
            )
        )
        extra_artifact.update(
            path=extra_path,
            fileName="unexpected-extra.zip",
            sha256="e" * 64,
            runtime="archive",
            platform=None,
            arch=None,
            accelerators=[],
        )
        manifest["artifacts"].append(extra_artifact)
        release["assets"].append(
            {"name": "unexpected-extra.zip", "digest": f"sha256:{'e' * 64}"}
        )

        with tempfile.TemporaryDirectory() as temp:
            result = _run_schema2_sync(Path(temp), manifest, release)

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SPM artifact inventory", result.stdout + result.stderr)

    def test_schema_2_sync_binds_spm_release_digest_to_manifest(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        spm_asset = next(
            asset
            for asset in release["assets"]
            if asset["name"].startswith(
                "litert-lm-native-apple-LiteRtLm-xcframework-"
            )
        )
        original_digest = spm_asset["digest"]
        spm_asset["digest"] = "sha256:" + "0" * 64
        self.assertNotEqual(original_digest, spm_asset["digest"])

        with tempfile.TemporaryDirectory() as temp:
            result = _run_schema2_sync(Path(temp), manifest, release)

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SPM release asset digest", result.stdout + result.stderr)

    def test_schema_2_sync_rejects_backslash_artifact_paths(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        tag = manifest["release"]["tag"]
        artifact = dict(
            next(
                artifact
                for artifact in manifest["artifacts"]
                if artifact["path"].startswith("dist/spm/")
            )
        )
        artifact.update(
            path=rf"dist\\spm\\{tag}\\unexpected-extra.zip",
            fileName=rf"dist\\spm\\{tag}\\unexpected-extra.zip",
            sha256="d" * 64,
            runtime="archive",
            platform=None,
            arch=None,
            accelerators=[],
        )
        manifest["artifacts"].append(artifact)

        with tempfile.TemporaryDirectory() as temp:
            result = _run_schema2_sync(Path(temp), manifest, release)

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("invalid artifact path", result.stdout + result.stderr)

    def test_schema_2_sync_accepts_owner_gpu_accelerator_union(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        artifact = next(
            artifact
            for artifact in manifest["artifacts"]
            if artifact["path"] == "bin/android/arm64/libLiteRtLm.so"
        )
        artifact["accelerators"] = sorted(set(artifact["accelerators"]) | {"gpu"})
        platform = next(
            platform
            for platform in manifest["platforms"]
            if platform["platform"] == "android" and platform["arch"] == "arm64"
        )
        platform["accelerators"] = sorted(set(platform["accelerators"]) | {"gpu"})

        with tempfile.TemporaryDirectory() as temp:
            result = _run_schema2_sync(Path(temp), manifest, release)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_schema_2_sync_keeps_macos_gpu_companions_in_spm_completeness(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        _add_macos_spm_companions(manifest, release)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = _run_schema2_sync(
                root, manifest, release, starting_swift=_v018_litert_swift(),
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            expected = (
                "LiteRtLm.framework/Versions/A/LiteRtLm",
                "libCLiteRTLM_mac.dylib",
                "libLiteRt.dylib",
                "libLiteRtTopKWebGpuSampler.dylib",
                "libLiteRtWebGpuAccelerator.dylib",
                "libwebgpu_dawn.dylib",
            )
            runtime = (root / "repo/lib/src/backends/litert_lm/litert_lm_runtime.dart").read_text()
            function = _runtime_inventory_function(runtime, "_liteRtLmMacOsRequiredNativeSpmFilesForAbi")
            arm64 = function.split("Abi.macosArm64", 1)[1].split("Abi.macosX64", 1)[0]
            self.assertEqual(re.findall(r"'([^']+)'", arm64), list(expected))
            self.assertNotIn("WebGpuAccelerator.framework", function)
            self.assertNotIn("GemmaModelConstraintProvider", function)
            prepare = (root / "repo/tool/macos_litert_lm_prepare_app.sh").read_text()
            function = prepare.split("required_native_spm_files()", 1)[1].split("\n}", 1)[0]
            arm64 = function.split("arm64)", 1)[1].split("x64)", 1)[0]
            self.assertEqual(re.findall(r'"([^"]+)"', arm64), list(expected))
            swift = (root / "repo/packages/llamadart_litert_lm_flutter/darwin/llamadart_litert_lm_flutter/Package.swift").read_text()
            for target in ("LiteRt", "LiteRtTopKWebGpuSampler", "LiteRtWebGpuAccelerator", "WebgpuDawn"):
                block = swift.split(f'name: "{target}",', 1)[1].split("),", 1)[0]
                self.assertIn(f'checksum: "{_MACOS_SPM_COMPANION_DIGEST}"', block)

    def test_schema_2_sync_keeps_metal_plugins_off_the_macos_spm_layout(self) -> None:
        # The v0.18.0 macOS Metal slices carry an invalid signature that kills
        # Debug launches; the macOS GPU path loads the WebGPU accelerator.
        manifest, release = _schema2_fixture_payloads()
        _add_macos_spm_companions(manifest, release)
        for library in ("libLiteRtMetalAccelerator.dylib", "libLiteRtTopKMetalSampler.dylib"):
            _add_macos_bundle_library(manifest, library)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = _run_schema2_sync(
                root, manifest, release, starting_swift=_v018_litert_swift(),
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            repo = root / "repo"
            runtime = (repo / "lib/src/backends/litert_lm/litert_lm_runtime.dart").read_text()
            spm = _runtime_inventory_function(runtime, "_liteRtLmMacOsRequiredNativeSpmFilesForAbi")
            prepare = (repo / "tool/macos_litert_lm_prepare_app.sh").read_text()
            prepare_spm = prepare.split("required_native_spm_files()", 1)[1].split("\n}", 1)[0]
            for text in (spm, prepare_spm):
                self.assertNotIn("Metal", text)
            hook_libraries = prepare.split("required_libraries()", 1)[1].split("\n}", 1)[0]
            self.assertIn("libLiteRtMetalAccelerator.dylib", hook_libraries)
            swift = (repo / "packages/llamadart_litert_lm_flutter/darwin/llamadart_litert_lm_flutter/Package.swift").read_text()
            for target in ("LiteRtMetalAccelerator", "LiteRtTopKMetalSampler"):
                self.assertIn(
                    f'.target(name: "{target}", condition: .when(platforms: [.iOS]))',
                    swift,
                )

    def test_schema_2_sync_rejects_package_swift_missing_macos_runtime_target(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        _add_macos_spm_companions(manifest, release)
        starting = re.sub(
            r'(?ms)^[ \t]*nativeRepoBinaryTarget\(\s*name: "LiteRt",.*?^[ \t]*\),\n',
            "",
            _v018_litert_swift(),
        )
        starting = re.sub(r'(?m)^[ \t]*\.target\(name: "LiteRt", .*\n', "", starting)
        self.assertNotIn('name: "LiteRt"', starting)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = _run_schema2_sync(root, manifest, release, starting_swift=starting)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("binary targets do not match", result.stdout + result.stderr)
            runtime = root / "repo/lib/src/backends/litert_lm/litert_lm_runtime.dart"
            self.assertEqual(
                runtime.read_text(),
                (Path(__file__).resolve().parents[2] / "lib/src/backends/litert_lm/litert_lm_runtime.dart").read_text(),
            )

    def test_schema_2_sync_rejects_macos_library_without_reviewed_spm_layout(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        _add_macos_bundle_library(manifest, "libLiteRtFutureAccelerator.dylib")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = _run_schema2_sync(root, manifest, release)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(
                "libLiteRtFutureAccelerator.dylib has no reviewed SwiftPM",
                result.stdout + result.stderr,
            )

    def test_schema_2_sync_generates_runtime_inventory_from_platform_paths(self) -> None:
        manifest, release = _schema2_fixture_payloads()

        with tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            result = _run_schema2_sync(temp_path, manifest, release)
            runtime = (
                temp_path / "repo/lib/src/backends/litert_lm/litert_lm_runtime.dart"
            ).read_text(encoding="utf-8")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(
            """Abi.macosArm64 => const <String>[\n      'libCLiteRTLM_mac.dylib',\n      'libLiteRtLm.dylib',\n    ],""",
            runtime,
        )
        self.assertIn(
            "Abi.linuxX64 => const <String>['libLiteRtLm.so'],",
            runtime,
        )
        self.assertIn(
            "Abi.windowsX64 => const <String>['LiteRtLm.dll'],",
            runtime,
        )
        legacy = _runtime_inventory_function(runtime, "_liteRtLmLegacyRequiredLibrariesForAbi")
        self.assertNotIn("libGemmaModelConstraintProvider.dylib", legacy)
        self.assertNotIn("libLiteRtTopKWebGpuSampler.so", legacy)

    def test_schema_2_sync_updates_real_macos_inventory_surfaces(self) -> None:
        manifest, release = _schema2_fixture_payloads()

        with tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            result = _run_schema2_sync(
                temp_path,
                manifest,
                release,
                include_runtime_dependencies=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            repo_root = temp_path / "repo"
            prepare = (repo_root / "tool/macos_litert_lm_prepare_app.sh").read_text(
                encoding="utf-8"
            )
            runtime = (
                repo_root / "lib/src/backends/litert_lm/litert_lm_runtime.dart"
            ).read_text(encoding="utf-8")
            if shutil.which("dart") is None:
                self.skipTest("Dart SDK is required to analyze generated inventory")
            (
                dart_format_result,
                dart_analyze_result,
                dart_run_result,
            ) = _run_dart_inventory_checks(repo_root)
            package_swift = (
                repo_root
                / "packages/llamadart_litert_lm_flutter/darwin/"
                / "llamadart_litert_lm_flutter/Package.swift"
            ).read_text(encoding="utf-8")

            library_dir = temp_path / "macos-arm64-libraries"
            library_dir.mkdir()
            for library in (
                "libCLiteRTLM_mac.dylib",
                "libLiteRtLm.dylib",
            ):
                (library_dir / library).touch()
            app_dir = temp_path / "Test.app"
            (app_dir / "Contents/Frameworks").mkdir(parents=True)
            prepare_result = _run_generated_macos_prepare(
                repo_root,
                library_dir,
                app_dir,
            )
            staged_runtime = app_dir / "Contents/Frameworks/LiteRtLmRuntime"
            staged_runtime_files = sorted(
                path.name for path in staged_runtime.iterdir()
            )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            prepare_result.returncode,
            0,
            prepare_result.stdout + prepare_result.stderr,
        )
        self.assertEqual(
            dart_format_result.returncode,
            0,
            dart_format_result.stdout + dart_format_result.stderr,
        )
        self.assertEqual(
            dart_analyze_result.returncode,
            0,
            dart_analyze_result.stdout + dart_analyze_result.stderr,
        )
        self.assertEqual(
            dart_run_result.returncode,
            0,
            dart_run_result.stdout + dart_run_result.stderr,
        )
        self.assertEqual(
            staged_runtime_files,
            ["libCLiteRTLM_mac.dylib", "libLiteRtLm.dylib"],
        )
        self.assertIn(
            '"libCLiteRTLM_mac.dylib" \\\n        "libLiteRtLm.dylib"',
            prepare,
        )
        self.assertIn(
            '"LiteRtLm.framework/Versions/A/LiteRtLm" \\\n        "libCLiteRTLM_mac.dylib"',
            prepare,
        )
        self.assertNotIn("libGemmaModelConstraintProvider.dylib", prepare)
        self.assertNotIn("LiteRtMetalAccelerator.framework", prepare)
        self.assertIn(
            """Abi.macosArm64 => const <String>[\n      'CLiteRTLM_mac.framework/Versions/A/CLiteRTLM_mac',\n      'LiteRtLm.framework/Versions/A/LiteRtLm',\n    ],""",
            runtime,
        )
        self.assertIn(
            """Abi.macosArm64 => const <String>[\n      'LiteRtLm.framework/Versions/A/LiteRtLm',\n      'libCLiteRTLM_mac.dylib',\n    ],""",
            runtime,
        )
        frameworks = _runtime_inventory_function(runtime, "_liteRtLmMacOsRequiredFrameworksForAbi")
        self.assertNotIn("GemmaModelConstraintProvider.framework", frameworks)
        self.assertNotIn("LiteRtMetalAccelerator.framework", frameworks)
        for target in (
            "LiteRtLm",
            "CLiteRTLM",
            "CLiteRTLMMac",
            "LiteRtMetalAccelerator",
            "LiteRtTopKMetalSampler",
        ):
            self.assertIn(f'name: "{target}"', package_swift)
        for optional_target in (
            "GemmaModelConstraintProvider",
            "LiteRt",
            "LiteRtTopKWebGpuSampler",
            "LiteRtWebGpuAccelerator",
            "WebgpuDawn",
        ):
            self.assertNotIn(f'name: "{optional_target}"', package_swift)

    def test_schema_2_optional_spm_companions_do_not_require_swift_targets(self) -> None:
        manifest, release = _schema2_fixture_payloads()
        tag = manifest["release"]["tag"]
        optional_targets = (
            "GemmaModelConstraintProvider",
            "LiteRt",
            "LiteRtTopKWebGpuSampler",
            "LiteRtWebGpuAccelerator",
            "WebgpuDawn",
        )
        for index, target in enumerate(optional_targets, start=1):
            asset_name = (
                f"litert-lm-native-apple-{target}-xcframework-{tag}.zip"
            )
            artifact = dict(
                next(
                    artifact
                    for artifact in manifest["artifacts"]
                    if artifact["path"].startswith("dist/spm/")
                )
            )
            artifact.update(
                path=f"dist/spm/{tag}/{asset_name}",
                fileName=asset_name,
                sha256=f"{index:x}" * 64,
                runtime="archive",
                platform=None,
                arch=None,
                accelerators=[],
            )
            manifest["artifacts"].append(artifact)
            release["assets"].append(
                {
                    "name": asset_name,
                    "digest": "sha256:" + f"{index:x}" * 64,
                }
            )

        package_swift = (
            Path(__file__).resolve().parents[2]
            / "packages/llamadart_litert_lm_flutter/darwin/"
            / "llamadart_litert_lm_flutter/Package.swift"
        )
        with tempfile.TemporaryDirectory() as temp:
            release_dir = Path(temp)
            _materialize_schema2_release_fixtures(release_dir, manifest, release)
            validated = validate_litert_lm_release_manifest(
                release,
                repo="leehack/litert-lm-native",
                tag=tag,
                release_json_dir=str(release_dir),
                required_bundles=litert_lm_bundle_names(
                    (Path(__file__).resolve().parents[2] / "lib/src/hook/native_release_pins.dart").read_text(
                        encoding="utf-8"
                    )
                ),
            )
        self.assertEqual(validated, manifest)
        prepared = prepare_litert_lm_package_swift(
            LEGACY_LITERT_SWIFT.read_text(encoding="utf-8"),
            release=release,
            manifest=manifest,
            resolved_tag=tag,
        )
        self.assertNotIn("GemmaModelConstraintProvider", prepared)
        self.assertNotIn("LiteRtWebGpuAccelerator", prepared)

    def test_hook_bundle_inventory_rejects_duplicate_specs(self) -> None:
        spec = (
            "LiteRtLmBundleSpec('linux-x64', "
            "sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', "
            "requiredLibraries: {'libLiteRtLm.so'}),"
        )
        with self.assertRaisesRegex(ReleaseError, "duplicate LiteRT-LM bundle"):
            litert_lm_bundle_names(f"{spec}\n{spec}\n")

    def test_hook_library_sets_follow_dart_formatter_width(self) -> None:
        hook = (
            "LiteRtLmBundleSpec(\n"
            "    'linux-x64',\n"
            f"    sha256: '{'a' * 64}',\n"
            "    requiredLibraries: {'old.so'},\n"
            "  ),"
        )
        short = replace_litert_lm_bundle_required_libraries(
            hook,
            "linux-x64",
            ("a.so", "b.so", "c.so"),
        )
        self.assertIn(
            "requiredLibraries: {'a.so', 'b.so', 'c.so'},",
            short,
        )

        long = replace_litert_lm_bundle_required_libraries(
            hook,
            "linux-x64",
            (
                "libLiteRtTopKWebGpuSampler.so",
                "libLiteRtWebGpuAccelerator.so",
                "libwebgpu_dawn.so",
            ),
        )
        self.assertIn(
            "requiredLibraries: {\n"
            "      'libLiteRtTopKWebGpuSampler.so',\n"
            "      'libLiteRtWebGpuAccelerator.so',\n"
            "      'libwebgpu_dawn.so',\n"
            "    },",
            long,
        )

    def test_known_legacy_schema_1_manifest_requires_exact_immutable_evidence(self) -> None:
        tag = "v0.16.0-native.2"
        owner_fixture = (
            Path(__file__).resolve().parent
            / "fixtures"
            / "v0.16.0-native.2-manifest.json"
        )
        legacy_identity = LEGACY_SCHEMA1_RELEASES[tag]
        release = {
            "tag_name": tag,
            "tag_commit_sha": "baef0ee4459582778fdfbe5a7e3b214775f2f99c",
            "draft": False,
            "prerelease": False,
            "assets": [
                {
                    "name": name,
                    "digest": digest,
                }
                for name, digest in legacy_identity["assets"].items()
            ],
        }
        with tempfile.TemporaryDirectory() as temp:
            fixture = (
                Path(temp)
                / f"leehack__litert-lm-native__{tag}__manifest.json"
            )
            fixture.write_bytes(owner_fixture.read_bytes())
            validate_litert_lm_release_manifest(
                release,
                repo="leehack/litert-lm-native",
                tag=tag,
                release_json_dir=temp,
                required_bundles=["linux-x64"],
            )

            fixture.write_text(
                json.dumps({"schemaVersion": 1, "release": {"tag": tag}}),
                encoding="utf-8",
            )
            manifest_asset = next(
                asset for asset in release["assets"] if asset["name"] == "manifest.json"
            )
            manifest_asset["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "immutable allowlist"):
                validate_litert_lm_release_manifest(
                    release,
                    repo="leehack/litert-lm-native",
                    tag=tag,
                    release_json_dir=temp,
                    required_bundles=["linux-x64"],
                )

        x64_asset = f"litert-lm-native-runtime-macos-x64-{tag}.tar.gz"
        without_x64 = {
            **legacy_identity,
            "assets": {
                name: digest
                for name, digest in legacy_identity["assets"].items()
                if name != x64_asset
            },
        }
        release["assets"] = [
            {"name": name, "digest": digest}
            for name, digest in without_x64["assets"].items()
        ]
        with tempfile.TemporaryDirectory() as temp:
            fixture = (
                Path(temp)
                / f"leehack__litert-lm-native__{tag}__manifest.json"
            )
            fixture.write_bytes(owner_fixture.read_bytes())
            with patch.dict(pins.LEGACY_SCHEMA1_RELEASES, {tag: without_x64}):
                with self.assertRaisesRegex(
                    ReleaseError, "schema-1 nine-platform contract; missing macos-x64"
                ):
                    validate_litert_lm_release_manifest(
                        release,
                        repo="leehack/litert-lm-native",
                        tag=tag,
                        release_json_dir=temp,
                        required_bundles=["linux-x64"],
                    )

        future_tag = "v99.0.0-native.1"
        future_release = {
            "tag_name": future_tag,
            "assets": [{"name": "manifest.json", "digest": "sha256:" + "a" * 64}],
        }
        future_manifest = {
            "schemaVersion": 1,
            "release": {"tag": future_tag},
        }
        with tempfile.TemporaryDirectory() as temp:
            fixture = (
                Path(temp)
                / f"leehack__litert-lm-native__{future_tag}__manifest.json"
            )
            fixture.write_text(json.dumps(future_manifest), encoding="utf-8")
            future_release["assets"][0]["digest"] = "sha256:" + hashlib.sha256(
                fixture.read_bytes()
            ).hexdigest()
            with self.assertRaisesRegex(ReleaseError, "schema 2"):
                validate_litert_lm_release_manifest(
                    future_release,
                    repo="leehack/litert-lm-native",
                    tag=future_tag,
                    release_json_dir=temp,
                    required_bundles=["linux-x64"],
                )


class NativeReleaseTagGrammarCorpusTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        fixture_path = (
            Path(__file__).resolve().parent
            / "fixtures"
            / "native_release_tag_grammar.json"
        )
        cls.fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        cls.forms = cls.fixture["forms"]

    def test_patterns_match_fixture(self) -> None:
        patterns = self.fixture["patterns"]
        self.assertEqual(
            pins._STABLE_NATIVE_TAG_PATTERN.pattern, patterns["stable_pattern"]
        )
        self.assertEqual(
            pins._STABLE_WRAPPER_TAG_PATTERN.pattern,
            patterns["stable_wrapper_pattern"],
        )
        self.assertEqual(
            pins._LEGACY_NATIVE_TAG_PATTERN.pattern, patterns["nightly_pattern"]
        )
        self.assertEqual(
            pins._NIGHTLY_WRAPPER_TAG_PATTERN.pattern,
            patterns["nightly_wrapper_pattern"],
        )
        self.assertEqual(
            pins._LEGACY_WRAPPER_TAG_PATTERN.pattern,
            patterns["legacy_wrapper_pattern"],
        )
        self.assertEqual(pins._NATIVE_DOC_TAG_PATTERN, patterns["doc_tag_pattern"])

    def test_positive_tag_corpus(self) -> None:
        for case in self.fixture["positive_cases"]:
            tag = case["tag"]
            form = self.forms[case["form"]]
            with self.subTest(tag=tag):
                parsed = pins.parse_native_release_tag(tag)
                self.assertEqual(parsed.channel, form["channel"])
                self.assertEqual(list(parsed.version), case["version"])
                self.assertEqual(parsed.wrapper_revision, case["wrapper_revision"])
                self.assertEqual(parsed.wrapper_revision > 0, form["is_wrapper"])
                self.assertEqual(parsed.channel == "nightly", form["is_legacy"])
                self.assertEqual(parsed.upstream_tag, case["upstream_tag"])
                self.assertTrue(tag.startswith(parsed.upstream_tag))
                self.assertEqual(pins.normalize_release_tag(tag), tag)
                is_stable_upstream = bool(
                    pins._STABLE_NATIVE_TAG_PATTERN.fullmatch(tag)
                    or pins._STABLE_WRAPPER_TAG_PATTERN.fullmatch(tag)
                )
                self.assertEqual(is_stable_upstream, form["is_stable_upstream"])

    def test_latest_discovery_accepts_only_unsuffixed_stable(self) -> None:
        for case in self.fixture["positive_cases"]:
            tag = case["tag"]
            form = self.forms[case["form"]]
            def resolve_latest() -> str:
                return pins.validate_resolved_native_release(
                    {"tag_name": tag},
                    requested_tag="latest",
                    current_tag=tag,
                    allow_legacy_tag=False,
                )

            with self.subTest(tag=tag):
                if form["is_latest_eligible"]:
                    self.assertEqual(resolve_latest(), tag)
                else:
                    with self.assertRaisesRegex(ReleaseError, "Automatic discovery"):
                        resolve_latest()

    def test_transitions_enforce_channel_and_rollback_policy(self) -> None:
        def transition(current: str, target: str) -> None:
            pins.validate_native_release_transition(
                current, target, allow_legacy_tag=False
            )

        transition("v0.2.0", "v0.3.0")
        transition("v0.2.0", "v0.2.0-1")
        transition("b10514", "v0.3.0")
        transition("b10514-llamadart.1", "b10514-2")
        with self.assertRaisesRegex(ReleaseError, "rollback"):
            transition("v0.3.0", "v0.2.0")
        with self.assertRaisesRegex(ReleaseError, "rollback"):
            transition("v0.2.0-2", "v0.2.0-1")
        with self.assertRaisesRegex(ReleaseError, "equivalent native release"):
            transition("b10514-llamadart.1", "b10514-1")
        with self.assertRaisesRegex(ReleaseError, "stable-to-historical/nightly"):
            transition("v0.3.0", "b10514")
        pins.validate_native_release_transition(
            "v0.3.0", "b10514", allow_legacy_tag=True
        )

    def test_reserved_inputs_follow_consumer_policy(self) -> None:
        for case in self.fixture["reserved_inputs"]:
            value = case["value"]
            with self.subTest(value=value):
                if case["python_sync"]:
                    self.assertEqual(pins.normalize_release_tag(value), value)
                else:
                    with self.assertRaises(ReleaseError):
                        pins.normalize_release_tag(value)
                with self.assertRaises(ReleaseError):
                    pins.parse_native_release_tag(value)

    def test_negative_tag_corpus(self) -> None:
        for case in self.fixture["negative_cases"]:
            tag = case["tag"]
            reason = case["reason"]
            with self.subTest(tag=tag, reason=reason):
                with self.assertRaises(ReleaseError):
                    pins.parse_native_release_tag(tag)
                with self.assertRaises(ReleaseError):
                    pins.normalize_release_tag(tag)


class CoreChangelogNativePinTest(unittest.TestCase):
    repo = "leehack/llamadart-native"

    def test_writes_a_dash_bullet_and_replaces_a_legacy_star_entry(self) -> None:
        legacy = (
            "## Unreleased\n\n* Updated the default llama.cpp native runtime pin to\n"
            "  `leehack/llamadart-native@b1`, old.\n\n- Kept.\n\n## 1.0.0\n"
        )
        updated = pins.update_core_changelog_native_pin(legacy, self.repo, "b2")
        self.assertIn("\n- Updated the default llama.cpp native runtime pin to\n", updated)
        self.assertIn("`leehack/llamadart-native@b2`", updated)
        self.assertNotIn("b1", updated)
        self.assertNotIn("\n* ", updated)
        self.assertIn("- Kept.", updated)

    def test_replaces_a_hand_written_entry_with_unindented_continuation_lines(
        self,
    ) -> None:
        handwritten = (
            "## Unreleased\n\n- Updated the default llama.cpp native runtime pin to\n"
            "`leehack/llamadart-native@b1`, hand written\n"
            "continuation.\n\n\n- Kept.\n\n## 1.0.0\n\n- Released.\n"
        )
        updated = pins.update_core_changelog_native_pin(handwritten, self.repo, "b2")
        self.assertNotIn("b1", updated)
        self.assertNotIn("continuation", updated)
        self.assertIn("`leehack/llamadart-native@b2`", updated)
        self.assertTrue(updated.endswith("- Kept.\n\n## 1.0.0\n\n- Released.\n"))
        self.assertEqual(updated.count("- Updated the default llama.cpp"), 1)

    def _update_with_following(self, following: str) -> str:
        handwritten = (
            "## Unreleased\n\n- Updated the default llama.cpp native runtime pin to\n"
            "`leehack/llamadart-native@b1`, hand written\n"
            f"continuation.\n{following}\n\n## 1.0.0\n"
        )
        updated = pins.update_core_changelog_native_pin(handwritten, self.repo, "b2")
        self.assertNotIn("b1", updated)
        self.assertNotIn("continuation", updated)
        return updated

    def test_keeps_an_adjacent_dash_bullet(self) -> None:
        updated = self._update_with_following("- Adjacent dash.")
        self.assertIn("\n- Adjacent dash.\n", updated)

    def test_keeps_an_adjacent_star_bullet(self) -> None:
        updated = self._update_with_following("* Adjacent star.")
        self.assertIn("\n* Adjacent star.\n", updated)

    def test_keeps_an_adjacent_heading(self) -> None:
        updated = self._update_with_following("### Adjacent heading")
        self.assertIn("\n### Adjacent heading\n", updated)

    def test_keeps_an_adjacent_h2_heading(self) -> None:
        updated = self._update_with_following("## Adjacent heading")
        self.assertIn("\n## Adjacent heading\n", updated)

    def test_keeps_an_adjacent_empty_heading(self) -> None:
        updated = self._update_with_following("#")
        self.assertIn("\n#\n", updated)

    def test_consumes_a_continuation_line_starting_with_an_issue_reference(
        self,
    ) -> None:
        updated = self._update_with_following("#1234 follow-up")
        self.assertNotIn("#1234", updated)
        self.assertNotIn("follow-up", updated)

    def test_consumes_a_continuation_line_starting_with_a_hashtag(self) -> None:
        updated = self._update_with_following("#hashtag")
        self.assertNotIn("#hashtag", updated)

    def test_consumes_a_continuation_line_with_seven_hashes(self) -> None:
        updated = self._update_with_following("####### not a heading")
        self.assertNotIn("not a heading", updated)

    def test_consumes_trailing_blank_lines_but_keeps_the_next_paragraph(self) -> None:
        handwritten = (
            "## Unreleased\n\n- Prior.\n\n"
            "- Updated the default llama.cpp native runtime pin to\n"
            "`leehack/llamadart-native@b1`, hand written\n"
            "continuation.\n\n\nNext paragraph.\n\n## 1.0.0\n"
        )
        updated = pins.update_core_changelog_native_pin(handwritten, self.repo, "b2")
        self.assertIn("\n\n- Prior.\n\nNext paragraph.\n\n## 1.0.0\n", updated)
        self.assertNotIn("\n\n\n", updated)


class CompanionChangelogUnreleasedTest(unittest.TestCase):
    repo = "leehack/litert-lm-native"
    entry = "* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v2`."
    released = "## 0.0.11\n\n" + entry + "\n\n## 0.0.10\n\n* Older.\n"

    def test_adds_unreleased_entry_for_a_new_pin(self) -> None:
        updated = pins.update_companion_changelog_unreleased(
            "## 0.0.11\n\n* Updated Apple SwiftPM native pin to "
            "`leehack/litert-lm-native@v1`.\n",
            self.entry,
            self.repo,
        )
        self.assertTrue(updated.startswith(f"## Unreleased\n\n{self.entry}\n\n## 0.0.11"))

    def test_replaces_stale_unreleased_pin_entry(self) -> None:
        updated = pins.update_companion_changelog_unreleased(
            "## Unreleased\n\n* Updated Apple SwiftPM native pin to "
            "`leehack/litert-lm-native@v1`.\n* Kept.\n\n## 0.0.11\n\n* Old.\n",
            self.entry,
            self.repo,
        )
        self.assertEqual(
            updated,
            f"## Unreleased\n\n{self.entry}\n\n* Kept.\n\n## 0.0.11\n\n* Old.\n",
        )

    def test_is_a_no_op_when_a_released_section_records_the_pin(self) -> None:
        self.assertEqual(
            pins.update_companion_changelog_unreleased(
                self.released, self.entry, self.repo
            ),
            self.released,
        )
        pinless_release = "## 0.0.12\n\n* Updated the install example.\n\n" + self.released
        self.assertEqual(
            pins.update_companion_changelog_unreleased(
                pinless_release, self.entry, self.repo
            ),
            pinless_release,
        )

    def test_matches_a_wrapped_released_pin_entry(self) -> None:
        wrapped = (
            "## 0.0.11\n\n* Updated Apple SwiftPM native pin to\n"
            "  `leehack/litert-lm-native@v2`\n  and packaged more plugins.\n"
        )
        self.assertEqual(
            pins.update_companion_changelog_unreleased(wrapped, self.entry, self.repo),
            wrapped,
        )

    def test_records_a_rollback_to_an_older_released_pin(self) -> None:
        rolled_back = (
            "## 0.0.12\n\n* Updated Apple SwiftPM native pin to "
            "`leehack/litert-lm-native@v3`.\n\n" + self.released
        )
        updated = pins.update_companion_changelog_unreleased(
            rolled_back, self.entry, self.repo
        )
        self.assertTrue(updated.startswith(f"## Unreleased\n\n{self.entry}\n\n## 0.0.12"))

    def test_drops_stale_unreleased_pin_already_released(self) -> None:
        stale = (
            "## Unreleased\n\n* Updated Apple SwiftPM native pin to "
            "`leehack/litert-lm-native@v1`.\n\n" + self.released
        )
        self.assertEqual(
            pins.update_companion_changelog_unreleased(stale, self.entry, self.repo),
            self.released,
        )
        kept = (
            "## Unreleased\n\n* Updated Apple SwiftPM native pin to "
            "`leehack/litert-lm-native@v1`.\n* Kept.\n\n" + self.released
        )
        self.assertEqual(
            pins.update_companion_changelog_unreleased(kept, self.entry, self.repo),
            "## Unreleased\n\n* Kept.\n\n" + self.released,
        )

    def test_ignores_other_repo_pins(self) -> None:
        other = (
            "## 0.0.11\n\n* Updated Apple SwiftPM native pin to "
            "`leehack/llamadart-native@v2`.\n"
        )
        updated = pins.update_companion_changelog_unreleased(other, self.entry, self.repo)
        self.assertTrue(updated.startswith(f"## Unreleased\n\n{self.entry}\n\n## 0.0.11"))



SD_REPO = "leehack/stable-diffusion-native"
SD_BUNDLES = {
    "android-arm64": "libstable-diffusion.so",
    "ios-arm64": "libstable-diffusion.dylib",
    "ios-arm64-sim": "libstable-diffusion.dylib",
    "ios-x64-sim": "libstable-diffusion.dylib",
    "macos-arm64": "libstable-diffusion.dylib",
    "macos-x64": "libstable-diffusion.dylib",
    "linux-arm64": "libstable-diffusion.so",
    "linux-arm64-vulkan": "libstable-diffusion.so",
    "linux-x64": "libstable-diffusion.so",
    "linux-x64-vulkan": "libstable-diffusion.so",
    "windows-x64": "stable-diffusion.dll",
    "windows-x64-vulkan": "stable-diffusion.dll",
}


def _sd_fixture(
    tag: str, targets: dict[str, str], *, xcframework: bool = False
) -> tuple[dict, dict]:
    artifacts = []
    assets = []
    if xcframework:
        name = f"stable-diffusion-native-apple-xcframework-{tag}.zip"
        checksum = hashlib.sha256(f"xcframework-{tag}".encode()).hexdigest()
        artifacts.append(
            {
                "target": "apple",
                "kind": "xcframework",
                "file": name,
                "sha256": checksum,
                "size": 77000000,
                "library": "stable_diffusion.framework",
                "accelerators": ["metal", "cpu"],
            }
        )
        assets.append({"name": name, "digest": f"sha256:{checksum}"})
    for index, (target, library) in enumerate(sorted(targets.items())):
        for kind in ("runtime", "symbols"):
            name = f"stable-diffusion-native-{kind}-{target}-{tag}.tar.gz"
            checksum = hashlib.sha256(f"{kind}-{target}-{tag}".encode()).hexdigest()
            artifacts.append(
                {
                    "target": target,
                    "kind": kind,
                    "file": name,
                    "sha256": checksum,
                    "size": 1000 + index,
                    "library": library,
                    "accelerators": ["cpu"],
                }
            )
            assets.append(
                {
                    "name": name,
                    "digest": f"sha256:{checksum}",
                    "browser_download_url": (
                        f"https://github.com/{SD_REPO}/releases/download/{tag}/{name}"
                    ),
                }
            )
    manifest = {
        "schemaVersion": 1,
        "package": "stable-diffusion-native",
        "tag": tag,
        "upstream": {
            "repository": "leejet/stable-diffusion.cpp",
            "commit": "3f8527a46c54ecf4cb4ed6003da8e8982283c73c",
        },
        "artifacts": artifacts,
    }
    release = {"tag_name": tag, "assets": assets}
    return manifest, release


class StableDiffusionAppleCompatibilitySyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.source = (Path(__file__).resolve().parents[2] /
                       "lib/src/hook/native_release_pins.dart").read_text()
        self.current = pins.current_stable_diffusion_release_tag(self.source)
        self.checksum = re.search(
            r"const stableDiffusionAppleCompanionChecksums = <String, String>\{\s*"
            r"'" + re.escape(self.current) + r"':\s*'([0-9a-f]{64})'",
            self.source,
        ).group(1)

    def test_same_tag_retains_verified_compatibility(self) -> None:
        self.assertEqual(pins.refresh_stable_diffusion_apple_contract(
            self.source, self.current, self.current, self.checksum), self.source)

    def test_same_tag_checksum_changes_fail_closed(self) -> None:
        with self.assertRaisesRegex(pins.ReleaseError, "Same-tag Apple SD checksum changed"):
            pins.refresh_stable_diffusion_apple_contract(
                self.source, self.current, self.current, "0" * 64)

    def test_checksum_contract_rejects_comments_duplicates_and_nonliteral_values(self) -> None:
        for body in [
            f"/* '{self.current}': '{self.checksum}', */",
            f"// '{self.current}': '{self.checksum}',\n",
            f"'{self.current}': '{'0' * 64}', '{self.current}': '{self.checksum}',",
            f"'{self.current}': expectedChecksum,",
        ]:
            with self.subTest(body=body):
                source = re.sub(
                    r"const stableDiffusionAppleCompanionChecksums = <String, String>\{.*?\};",
                    "const stableDiffusionAppleCompanionChecksums = <String, String>{" + body + "};",
                    self.source, flags=re.DOTALL,
                )
                with self.assertRaisesRegex(pins.ReleaseError, "Malformed Apple SD checksum contract"):
                    pins.refresh_stable_diffusion_apple_contract(
                        source, self.current, self.current, self.checksum)

    def test_duplicate_checksum_contract_declarations_fail_closed(self) -> None:
        source = self.source + "\nconst stableDiffusionAppleCompanionChecksums = <String, String>{};\n"
        with self.assertRaisesRegex(pins.ReleaseError, "uniquely.*Apple SD checksum contract"):
            pins.refresh_stable_diffusion_apple_contract(
                source, self.current, self.current, self.checksum)

    def test_duplicate_compatibility_contract_declarations_fail_closed(self) -> None:
        source = self.source + "\nconst stableDiffusionCompatibleAppleCompanionTags = <String, String>{};\n"
        with self.assertRaisesRegex(pins.ReleaseError, "uniquely.*Apple SD compatibility contract"):
            pins.refresh_stable_diffusion_apple_contract(
                source, self.current, "v0.2.0-5", "a" * 64)

    def test_non_code_declarations_cannot_supply_or_override_proof(self) -> None:
        pattern = r"const stableDiffusionAppleCompanionChecksums = <String, String>\{.*?\};"
        declaration = re.search(pattern, self.source, re.DOTALL).group(0)
        for wrapper in [
            "/* outer /* nested */\n%s\n*/",
            "const example = '''\n%s\n''';",
            'const example = r"""literal $dollar\n%s\n""";',
        ]:
            with self.subTest(wrapper=wrapper):
                hidden = wrapper % declaration
                source = re.sub(pattern, lambda _: hidden, self.source, flags=re.DOTALL)
                with self.assertRaisesRegex(pins.ReleaseError, "Missing Apple SD checksum contract"):
                    pins.refresh_stable_diffusion_apple_contract(
                        source, self.current, self.current, self.checksum)
                # A non-code example beside the real declaration is ignored
                # and is never rewritten when the live contracts move.
                source = self.source + "\n" + hidden
                self.assertEqual(pins.refresh_stable_diffusion_apple_contract(
                    source, self.current, self.current, self.checksum), source)
                result = pins.refresh_stable_diffusion_apple_contract(
                    source, self.current, "v0.2.0-5", "a" * 64)
                self.assertIn(hidden, result)

    def test_native_pin_source_requires_complete_literal_strings_and_comments(self) -> None:
        for suffix in [
            "\n/* unterminated",
            "\nconst example = 'unterminated",
            '\nconst example = "${value}";',
        ]:
            with self.subTest(suffix=suffix):
                with self.assertRaises(pins.ReleaseError):
                    pins.refresh_stable_diffusion_apple_contract(
                        self.source + suffix, self.current, self.current, self.checksum)
        source = self.source + "\nconst example = 'it\\'s // literal text';\n"
        self.assertEqual(pins.refresh_stable_diffusion_apple_contract(
            source, self.current, self.current, self.checksum), source)

    def test_changed_pin_clears_older_compatibility_and_checksum(self) -> None:
        result = pins.refresh_stable_diffusion_apple_contract(
            self.source, self.current, "v0.2.0-5", "a" * 64)
        self.assertIn("const stableDiffusionCompatibleAppleCompanionTags = <String, String>{};", result)
        block = re.search(r"const stableDiffusionAppleCompanionChecksums = <String, String>\{(.*?)\};", result, re.S).group(1)
        self.assertIn("'v0.2.0-5': '" + "a" * 64 + "'", block)
        self.assertNotIn("v0.2.0-3", block)
        self.assertNotIn("v0.2.0-4", block)


class StableDiffusionPinSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.repo_root = self.root / "repo"
        self.pins = self.repo_root / "lib/src/hook/native_release_pins.dart"
        self.pins.parent.mkdir(parents=True)
        shutil.copyfile(
            Path(__file__).resolve().parents[2] / "lib/src/hook/native_release_pins.dart",
            self.pins,
        )
        self.pins.write_text(
            re.sub(
                r"const stableDiffusionReleaseTag = '[^']+';",
                "const stableDiffusionReleaseTag = 'v0.1.0';",
                self.pins.read_text(encoding="utf-8"),
            ),
            encoding="utf-8",
        )
        self.release_dir = self.root / "releases"
        self.release_dir.mkdir()

    def run_sync(
        self,
        tag: str,
        manifest: dict,
        release: dict,
        *,
        manifest_digest: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        manifest_bytes = json.dumps(manifest).encode("utf-8")
        prefix = SD_REPO.replace("/", "__")
        (self.release_dir / f"{prefix}__{tag}__manifest.json").write_bytes(
            manifest_bytes
        )
        release = json.loads(json.dumps(release))
        release["assets"].append(
            {
                "name": "manifest.json",
                "digest": "sha256:"
                + (manifest_digest or hashlib.sha256(manifest_bytes).hexdigest()),
                "browser_download_url": (
                    f"https://github.com/{SD_REPO}/releases/download/{tag}/manifest.json"
                ),
            }
        )
        (self.release_dir / f"{prefix}__{tag}.json").write_text(
            json.dumps(release), encoding="utf-8"
        )
        return subprocess.run(
            [
                sys.executable,
                str(Path(__file__).resolve().parent / "sync_native_release_pins.py"),
                "--repo-root",
                str(self.repo_root),
                "--release-json-dir",
                str(self.release_dir),
                "--stable-diffusion-tag",
                tag,
            ],
            cwd=self.repo_root,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_rewrites_tag_version_and_every_bundle_from_the_manifest(self) -> None:
        manifest, release = _sd_fixture(
            "v0.2.0", {**SD_BUNDLES, "android-x64": "libstable-diffusion.so"}
        )
        result = self.run_sync("v0.2.0", manifest, release)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("also publishes android-x64", result.stderr)
        text = self.pins.read_text(encoding="utf-8")
        self.assertIn("const stableDiffusionReleaseTag = 'v0.2.0';", text)
        self.assertIn("const stableDiffusionVersion = '0.2.0';", text)
        self.assertEqual(pins.stable_diffusion_bundle_names(text), list(SD_BUNDLES))
        for artifact in manifest["artifacts"]:
            if artifact["kind"] != "runtime" or artifact["target"] == "android-x64":
                continue
            self.assertIn(
                f"'{artifact['target']}',\n    sha256: '{artifact['sha256']}',\n"
                f"    requiredLibraries: {{'{artifact['library']}'}},",
                text,
            )

    def test_rejects_untrusted_or_incomplete_releases(self) -> None:
        def missing_bundle(manifest: dict, release: dict) -> None:
            manifest["artifacts"] = [
                a for a in manifest["artifacts"] if a["target"] != "linux-x64-vulkan"
            ]

        def digest_mismatch(manifest: dict, release: dict) -> None:
            release["assets"][0]["digest"] = "sha256:" + "0" * 64

        def wrong_file(manifest: dict, release: dict) -> None:
            manifest["artifacts"][0]["file"] = "other.tar.gz"

        def unsafe_library(manifest: dict, release: dict) -> None:
            manifest["artifacts"][0]["library"] = "../libevil.so"

        def wrong_package(manifest: dict, release: dict) -> None:
            manifest["package"] = "litert-lm-native"

        for mutate, message in (
            (missing_bundle, "does not publish pinned bundles: linux-x64-vulkan"),
            (digest_mismatch, "does not match its GitHub digest"),
            (wrong_file, "artifact must be"),
            (unsafe_library, "library name is invalid"),
            (wrong_package, "names another package"),
        ):
            with self.subTest(message=message):
                original = self.pins.read_text(encoding="utf-8")
                manifest, release = _sd_fixture("v0.2.0", SD_BUNDLES)
                mutate(manifest, release)
                result = self.run_sync("v0.2.0", manifest, release)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn(message, result.stderr)
                self.assertEqual(self.pins.read_text(encoding="utf-8"), original)

    def test_rejects_a_manifest_that_differs_from_its_github_digest(self) -> None:
        manifest, release = _sd_fixture("v0.2.0", SD_BUNDLES)
        result = self.run_sync(
            "v0.2.0", manifest, release, manifest_digest="1" * 64
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("manifest.json does not match its GitHub digest", result.stderr)

    def add_companion(self) -> Path:
        package = "packages/llamadart_stable_diffusion_flutter"
        source = Path(__file__).resolve().parents[2] / package
        for relative in (
            "pubspec.yaml",
            "README.md",
            "CHANGELOG.md",
            "darwin/llamadart_stable_diffusion_flutter/Package.swift",
        ):
            destination = self.repo_root / package / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / relative, destination)
        for doc in pins.DEFAULT_LLAMA_CPP_PROJECT_DOCS:
            path = self.repo_root / doc
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                "```yaml\n  llamadart_stable_diffusion_flutter: ^0.0.1\n```\n",
                encoding="utf-8",
            )
        return self.repo_root / package

    def test_pins_the_companion_xcframework_from_the_manifest(self) -> None:
        companion = self.add_companion()
        manifest, release = _sd_fixture("v0.3.0", SD_BUNDLES, xcframework=True)
        result = self.run_sync("v0.3.0", manifest, release)

        self.assertEqual(result.returncode, 0, result.stderr)
        checksum = hashlib.sha256(b"xcframework-v0.3.0").hexdigest()
        swift = (
            companion / "darwin/llamadart_stable_diffusion_flutter/Package.swift"
        ).read_text(encoding="utf-8")
        self.assertIn('let stableDiffusionTag = "v0.3.0"', swift)
        self.assertIn(f'checksum: "{checksum}"', swift)
        self.assertIn(
            "The Apple SwiftPM manifest pins "
            "`leehack/stable-diffusion-native@v0.3.0`.",
            (companion / "README.md").read_text(encoding="utf-8"),
        )
        self.assertTrue(
            (companion / "CHANGELOG.md")
            .read_text(encoding="utf-8")
            .startswith(
                "## Unreleased\n\n- Updated Apple SwiftPM native pin to "
                "`leehack/stable-diffusion-native@v0.3.0`."
            )
        )

    def test_rejects_a_companion_sync_without_a_trusted_xcframework(self) -> None:
        companion = self.add_companion()
        swift = companion / "darwin/llamadart_stable_diffusion_flutter/Package.swift"

        def drop_xcframework(manifest: dict, release: dict) -> None:
            manifest["artifacts"] = [
                a for a in manifest["artifacts"] if a["kind"] != "xcframework"
            ]

        def digest_mismatch(manifest: dict, release: dict) -> None:
            release["assets"][0]["digest"] = "sha256:" + "0" * 64

        def wrong_file(manifest: dict, release: dict) -> None:
            manifest["artifacts"][0]["file"] = "other.zip"

        for mutate, message in (
            (drop_xcframework, "publishes no Apple XCFramework"),
            (digest_mismatch, "does not match its GitHub digest"),
            (wrong_file, "XCFramework artifact must be"),
        ):
            with self.subTest(message=message):
                original = swift.read_text(encoding="utf-8")
                manifest, release = _sd_fixture(
                    "v0.3.0", SD_BUNDLES, xcframework=True
                )
                mutate(manifest, release)
                result = self.run_sync("v0.3.0", manifest, release)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn(message, result.stderr)
                self.assertEqual(swift.read_text(encoding="utf-8"), original)

    def test_rejects_rollback_and_foreign_tag_grammar(self) -> None:
        manifest, release = _sd_fixture("v0.0.9", SD_BUNDLES)
        result = self.run_sync("v0.0.9", manifest, release)
        self.assertEqual(result.returncode, 1)
        self.assertIn("rollback from v0.1.0 to v0.0.9", result.stderr)

        for tag in ("b1234", "v0.1", "v0.1.0-0", "v0.1.0-native.1"):
            with self.subTest(tag=tag):
                with self.assertRaises(ReleaseError):
                    pins.normalize_stable_diffusion_release_tag(tag)
        self.assertEqual(
            pins.normalize_stable_diffusion_release_tag("v0.1.0-2"), "v0.1.0-2"
        )
        self.assertLess(
            pins.stable_diffusion_release_order("v0.1.0"),
            pins.stable_diffusion_release_order("v0.1.0-1"),
        )


class LlamaCppAppleCompanionCompatibilitySyncTest(unittest.TestCase):
    SOURCE_ROOT = Path(__file__).resolve().parents[2]
    COMPANION = "packages/llamadart_llama_cpp_flutter"

    def setUp(self) -> None:
        self.make_repo()

    def make_repo(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.repo_root = self.root / "repo"
        for relative in (
            "lib/src/hook/native_release_pins.dart",
            "CHANGELOG.md",
            *pins.DEFAULT_LLAMA_CPP_PROJECT_DOCS,
            f"{self.COMPANION}/pubspec.yaml",
            f"{self.COMPANION}/README.md",
            f"{self.COMPANION}/CHANGELOG.md",
            f"{self.COMPANION}/darwin/llamadart_llama_cpp_flutter/Package.swift",
        ):
            target = self.repo_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.SOURCE_ROOT / relative, target)
        self.pins = self.repo_root / "lib/src/hook/native_release_pins.dart"
        # Exercise retention and clearing even when the live pin has no
        # compatible earlier companion releases.
        fixture_pins, replacements = re.subn(
            r"const llamaCppCompatibleAppleCompanionTags = <String, String>\{.*?\};",
            "const llamaCppCompatibleAppleCompanionTags = <String, String>{\n"
            "  'v0.6.0-2': 'fixture compatibility limitation',\n"
            "};",
            self.pins.read_text(encoding="utf-8"),
            count=1,
            flags=re.DOTALL,
        )
        self.assertEqual(replacements, 1)
        self.pins.write_text(fixture_pins, encoding="utf-8")
        self.release_dir = self.root / "releases"
        self.release_dir.mkdir()

    def write_release(
        self,
        tag: str,
        *,
        contract: int = 1,
        sidecar_artifacts: tuple[dict, ...] = (),
        apple_checksum: str | None = None,
    ) -> None:
        def asset(name: str) -> dict:
            digest = hashlib.sha256(name.encode()).hexdigest()
            if name == f"llamadart-native-apple-xcframework-{tag}.zip":
                source = self.pins.read_text(encoding="utf-8")
                contract = pins._COMPATIBLE_APPLE_COMPANION_CHECKSUMS_PATTERN.search(source)
                assert contract is not None
                recorded = dict(re.findall(r"'([^']+)':\s*'([a-f0-9]{64})'", contract.group(1)))
                digest = apple_checksum or recorded.get(tag, digest)
            return {
                "name": name,
                "digest": "sha256:" + digest,
                "browser_download_url": (
                    "https://github.com/leehack/llamadart-native/releases/"
                    f"download/{tag}/{name}"
                ),
            }

        bundles = [
            *(
                asset(f"llamadart-native-{bundle}-{tag}.tar.gz")
                for bundle in pins._STABLE_NATIVE_BUNDLES
            ),
            asset(f"llamadart-native-headers-{tag}.tar.gz"),
            asset(f"llamadart-native-apple-xcframework-{tag}.zip"),
            *(asset(sidecar["file"]) for sidecar in sidecar_artifacts),
        ]
        sidecar_fields = {sidecar["file"]: sidecar for sidecar in sidecar_artifacts}
        manifest = {
            "native_release_tag": tag,
            "tag": tag,
            "hook_contract_version": contract,
            "llama_cpp_commit": "d81235049384534c167caea52b85a694f6103d14",
            "native_commit": NATIVE_COMMIT,
            "llama_cpp_tag": pins.parse_native_release_tag(tag).upstream_tag,
            "artifacts": [
                {
                    **sidecar_fields.get(bundle["name"], {}),
                    "file": bundle["name"],
                    "sha256": bundle["digest"][7:],
                }
                for bundle in bundles
            ],
        }
        manifest_asset = asset("assets.json")
        manifest_asset["fixture_json"] = manifest
        sums_asset = asset("SHA256SUMS")
        sums_asset["fixture_text"] = "".join(
            f"{bundle['digest'][7:]}  {bundle['name']}\n" for bundle in bundles
        )
        release = {
            "tag_name": tag,
            "prerelease": True,
            "assets": [manifest_asset, sums_asset, *bundles],
        }
        (self.release_dir / f"leehack__llamadart-native__{tag}.json").write_text(
            json.dumps(release), encoding="utf-8"
        )

    def run_sync(
        self,
        tag: str,
        *extra: str,
        contract: int = 1,
        sidecar_artifacts: tuple[dict, ...] = (),
        apple_checksum: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        self.write_release(
            tag,
            contract=contract,
            sidecar_artifacts=sidecar_artifacts,
            apple_checksum=apple_checksum,
        )
        return subprocess.run(
            [
                sys.executable,
                str(Path(__file__).resolve().parent / "sync_native_release_pins.py"),
                "--repo-root",
                str(self.repo_root),
                "--release-json-dir",
                str(self.release_dir),
                "--llama-cpp-tag",
                tag,
                *extra,
            ],
            cwd=self.repo_root,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_a_pin_move_clears_compatible_tags_and_records_the_companion(
        self,
    ) -> None:
        current = pins.read_hook_native_tag(self.pins.read_text(encoding="utf-8"))
        upstream = pins.parse_native_release_tag(current).upstream_tag
        build = int(current.rsplit("-", 1)[1]) if "-" in current else 0
        target = f"{upstream}-{build + 1}"
        version = pins.companion_pubspec_version(
            (self.repo_root / self.COMPANION / "pubspec.yaml").read_text(),
            self.repo_root / self.COMPANION / "pubspec.yaml",
        )
        for extra, pubspec_version in (
            ((), version),
            (("--bump-companion-versions",), pins.bump_patch_version(version)),
        ):
            with self.subTest(extra=extra):
                self.make_repo()
                self.pins.write_text(
                    re.sub(
                        r"const llamaCppAppleCompanionVersion = '[^']+';",
                        "const llamaCppAppleCompanionVersion = '0.0.1';",
                        self.pins.read_text(encoding="utf-8"),
                    ).replace(
                        "const llamaCppCompatibleAppleCompanionTags = "
                        "<String, String>{\n",
                        "const llamaCppCompatibleAppleCompanionTags = "
                        "<String, String>{\n  'v0.0.1-1': 'x',\n",
                    ),
                    encoding="utf-8",
                )
                result = self.run_sync(target, *extra)
                self.assertEqual(result.returncode, 0, result.stderr)
                text = self.pins.read_text(encoding="utf-8")
                self.assertIn(f"const llamaCppTag = '{target}';", text)
                self.assertIn(
                    "const llamaCppCompatibleAppleCompanionTags = "
                    "<String, String>{};",
                    text,
                )
                checksum = hashlib.sha256(
                    f"llamadart-native-apple-xcframework-{target}.zip".encode()
                ).hexdigest()
                self.assertIn(f"'{target}':\n      '{checksum}',", text)
                self.assertNotIn(f"'{current}':", text)
                self.assertIn(
                    "const llamaCppAppleCompanionVersion = "
                    f"'{pins.bump_patch_version(version)}';",
                    text,
                )
                self.assertIn(
                    f"version: {pubspec_version}\n",
                    (self.repo_root / self.COMPANION / "pubspec.yaml").read_text(),
                )
                self.assertIn("cleared compatible Apple llama.cpp companion tags", result.stdout)
                self.assertIn("v0.0.1-1", result.stdout)

    def test_a_lockstep_pin_move_records_the_next_same_minor_companion(
        self,
    ) -> None:
        # From core 0.13.0 the hook names this constant when it shares the
        # core MAJOR.MINOR, so a pin moved inside a minor must record the
        # first companion release of that minor that pins it.
        current = pins.read_hook_native_tag(self.pins.read_text(encoding="utf-8"))
        upstream = pins.parse_native_release_tag(current).upstream_tag
        build = int(current.rsplit("-", 1)[1]) if "-" in current else 0
        target = f"{upstream}-{build + 1}"
        for extra in ((), ("--bump-companion-versions",)):
            with self.subTest(extra=extra):
                self.make_repo()
                pubspec = self.repo_root / self.COMPANION / "pubspec.yaml"
                pubspec.write_text(
                    pins.replace_pubspec_version(
                        pubspec.read_text(encoding="utf-8"), "0.13.0", pubspec
                    ),
                    encoding="utf-8",
                )
                result = self.run_sync(target, *extra)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(
                    "const llamaCppAppleCompanionVersion = '0.13.1';",
                    self.pins.read_text(encoding="utf-8"),
                )
                self.assertIn(
                    f"version: {'0.13.1' if extra else '0.13.0'}\n",
                    pubspec.read_text(encoding="utf-8"),
                )

    def next_wrapper_tag(self) -> str:
        current = pins.read_hook_native_tag(self.pins.read_text(encoding="utf-8"))
        upstream = pins.parse_native_release_tag(current).upstream_tag
        build = int(current.rsplit("-", 1)[1]) if "-" in current else 0
        return f"{upstream}-{build + 1}"

    @staticmethod
    def cuda_sidecar(tag: str, **fields: str) -> dict:
        return {
            "module": "backend-cuda12",
            "platform": "windows",
            "arch": "x64",
            "backend": "cuda",
            "file": f"llamadart-native-windows-x64-cuda12-{tag}.tar.gz",
            **fields,
        }

    def test_a_contract_2_release_pins_its_backend_sidecars(self) -> None:
        target = self.next_wrapper_tag()
        sidecar_file = f"llamadart-native-windows-x64-cuda12-{target}.tar.gz"

        result = self.run_sync(
            target,
            contract=2,
            sidecar_artifacts=(self.cuda_sidecar(target),),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.pins.read_text(encoding="utf-8")
        self.assertIn("const llamaCppHookContractVersion = 2;", text)
        self.assertIn(
            "const llamaCppBackendSidecarSpecs = <LlamaCppBackendSidecarSpec>[\n"
            "  LlamaCppBackendSidecarSpec(\n"
            "    bundle: 'windows-x64',\n"
            "    backend: 'cuda',\n"
            "    archive: 'windows-x64-cuda12',\n"
            f"    sha256: '{hashlib.sha256(sidecar_file.encode()).hexdigest()}',\n"
            "  ),\n"
            "];",
            text,
        )
        self.assertEqual(pins.llama_cpp_bundle_names(text), list(pins._STABLE_NATIVE_BUNDLES))

        resync = self.run_sync(target)
        self.assertEqual(resync.returncode, 0, resync.stderr)
        text = self.pins.read_text(encoding="utf-8")
        self.assertIn("const llamaCppHookContractVersion = 1;", text)
        self.assertIn(
            "const llamaCppBackendSidecarSpecs = <LlamaCppBackendSidecarSpec>[];",
            text,
        )

    def test_rejects_unsupported_contracts_and_malformed_sidecars(self) -> None:
        target = self.next_wrapper_tag()
        cases = {
            "requires native hook contract 3": dict(contract=3),
            "requires native hook contract True": dict(contract=True),
            "under hook contract 1, which has none": dict(
                sidecar_artifacts=(self.cuda_sidecar(target),),
            ),
            "has invalid backend": dict(
                contract=2,
                sidecar_artifacts=(self.cuda_sidecar(target, backend=""),),
            ),
            "extends unknown bundle linux-riscv64": dict(
                contract=2,
                sidecar_artifacts=(
                    self.cuda_sidecar(
                        target,
                        platform="linux",
                        arch="riscv64",
                        file=f"llamadart-native-linux-riscv64-cuda12-{target}.tar.gz",
                    ),
                ),
            ),
            "is not named llamadart-native-windows-x64-<variant>": dict(
                contract=2,
                sidecar_artifacts=(
                    self.cuda_sidecar(
                        target,
                        file=f"llamadart-native-linux-x64-cuda12-{target}.tar.gz",
                    ),
                ),
            ),
            "more than one cuda sidecar for windows-x64": dict(
                contract=2,
                sidecar_artifacts=(
                    self.cuda_sidecar(target),
                    self.cuda_sidecar(
                        target,
                        module="backend-cuda13",
                        file=f"llamadart-native-windows-x64-cuda13-{target}.tar.gz",
                    ),
                ),
            ),
        }
        original = self.pins.read_text(encoding="utf-8")
        for message, release in cases.items():
            with self.subTest(message=message):
                result = self.run_sync(target, **release)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn(message, result.stderr)
                self.assertEqual(self.pins.read_text(encoding="utf-8"), original)

    def test_sidecar_pins_require_their_constants(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "llamaCppBackendSidecarSpecs"):
            pins.replace_llama_cpp_backend_sidecars("const llamaCppTag = 'v0.6.0';\n", [])
        with self.assertRaisesRegex(ReleaseError, "hook contract version"):
            pins.replace_llama_cpp_hook_contract("const llamaCppTag = 'v0.6.0';\n", 2)

    def test_a_same_tag_resync_keeps_compatible_tags(self) -> None:
        original = self.pins.read_text(encoding="utf-8")
        compatible = re.search(
            r"const llamaCppCompatibleAppleCompanionTags = <String, String>\{.*?\};",
            original,
            re.DOTALL,
        )
        assert compatible is not None
        self.assertIn("'v0.6.0-2':", compatible.group(0))
        result = self.run_sync(pins.read_hook_native_tag(original))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(compatible.group(0), self.pins.read_text(encoding="utf-8"))
        self.assertNotIn("cleared compatible Apple llama.cpp companion tags", result.stdout)

    def test_same_tag_checksum_change_fails_before_writing(self) -> None:
        original = self.pins.read_text(encoding="utf-8")
        swift = self.repo_root / self.COMPANION / "darwin/llamadart_llama_cpp_flutter/Package.swift"
        original_swift = swift.read_text(encoding="utf-8")
        result = self.run_sync(pins.read_hook_native_tag(original), apple_checksum="a" * 64)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("Same-tag Apple llama.cpp checksum changed", result.stderr)
        self.assertEqual(self.pins.read_text(encoding="utf-8"), original)
        self.assertEqual(swift.read_text(encoding="utf-8"), original_swift)

    def test_checksum_refresh_rejects_malformed_contracts(self) -> None:
        original = self.pins.read_text(encoding="utf-8")
        pattern = pins._COMPATIBLE_APPLE_COMPANION_CHECKSUMS_PATTERN
        for body in ("// comment\n", "'x': compute(),", "'x': '" + "a" * 64 + "',\n'x': '" + "b" * 64 + "',"):
            with self.subTest(body=body):
                malformed = pattern.sub(
                    "const llamaCppCompatibleAppleCompanionChecksums = <String, String>{" + body + "};",
                    original,
                )
                with self.assertRaisesRegex(ReleaseError, "Malformed Apple llama.cpp checksum contract"):
                    pins.refresh_llama_cpp_apple_checksum(malformed, "v1.0.0", "a" * 64)

    def test_clear_reports_every_listed_tag_and_requires_the_constant(self) -> None:
        text = self.pins.read_text(encoding="utf-8")
        cleared_text, cleared = pins.clear_compatible_apple_companion_tags(text)
        self.assertEqual(cleared, ["v0.6.0-2"])
        self.assertIn(
            "const llamaCppCompatibleAppleCompanionTags = <String, String>{};",
            cleared_text,
        )
        self.assertIn(
            "const llamaCppCompatibleAppleCompanionChecksums = <String, String>{};",
            cleared_text,
        )
        self.assertEqual(
            pins.clear_compatible_apple_companion_tags(cleared_text),
            (cleared_text, []),
        )
        with self.assertRaisesRegex(ReleaseError, "llamaCppCompatibleAppleCompanionTags"):
            pins.clear_compatible_apple_companion_tags("const llamaCppTag = 'v0.6.0';\n")
        with self.assertRaisesRegex(
            ReleaseError, "llamaCppCompatibleAppleCompanionChecksums"
        ):
            pins.clear_compatible_apple_companion_tags(
                "const llamaCppCompatibleAppleCompanionTags = <String, String>{};\n"
            )


class LlamaCppBundleDigestPinTest(unittest.TestCase):
    PINS = Path(__file__).resolve().parents[2] / "lib/src/hook/native_release_pins.dart"

    def checked_in_pins(self) -> str:
        return self.PINS.read_text(encoding="utf-8")

    def test_checked_in_pins_list_every_hook_bundle(self) -> None:
        self.assertEqual(
            pins.llama_cpp_bundle_names(self.checked_in_pins()),
            list(pins._STABLE_NATIVE_BUNDLES),
        )

    def test_replaces_only_the_named_bundle_and_keeps_the_layout(self) -> None:
        text = self.checked_in_pins()
        digest = "a" * 64
        updated = pins.replace_llama_cpp_bundle_checksum(text, "linux-x64", digest)
        self.assertIn(f"  'linux-x64':\n      '{digest}',", updated)
        changed = [
            (before, after)
            for before, after in zip(text.splitlines(), updated.splitlines())
            if before != after
        ]
        self.assertEqual(len(changed), 1)
        self.assertEqual(len(updated), len(text))
        self.assertEqual(
            pins.litert_lm_bundle_names(updated),
            pins.litert_lm_bundle_names(text),
        )

    def test_rejects_missing_unknown_or_duplicate_pins(self) -> None:
        text = self.checked_in_pins()
        with self.assertRaisesRegex(ReleaseError, "Could not find llamaCppBundleSha256"):
            pins.llama_cpp_bundle_names("const llamaCppTag = 'v0.6.0';\n")
        with self.assertRaisesRegex(ReleaseError, "Could not replace llama.cpp checksum"):
            pins.replace_llama_cpp_bundle_checksum(text, "linux-riscv64", "a" * 64)
        duplicated = text.replace(
            "  'linux-x64':",
            "  'linux-arm64':",
        )
        with self.assertRaisesRegex(ReleaseError, "duplicates a bundle"):
            pins.llama_cpp_bundle_names(duplicated)

    def test_bundle_checksum_comes_from_the_release_and_must_match_the_manifest(
        self,
    ) -> None:
        name = "llamadart-native-linux-x64-b10514-1.tar.gz"
        release = {
            "tag_name": "b10514-1",
            "assets": [{"name": name, "digest": "sha256:" + "b" * 64}],
        }
        self.assertEqual(
            pins.llama_cpp_bundle_checksum(
                release, "linux-x64", "b10514-1", {}, repo="leehack/llamadart-native"
            ),
            "b" * 64,
        )
        self.assertEqual(
            pins.llama_cpp_bundle_checksum(
                release,
                "linux-x64",
                "b10514-1",
                {name: "b" * 64},
                repo="leehack/llamadart-native",
            ),
            "b" * 64,
        )
        with self.assertRaisesRegex(ReleaseError, "assets.json lists"):
            pins.llama_cpp_bundle_checksum(
                release,
                "linux-x64",
                "b10514-1",
                {name: "c" * 64},
                repo="leehack/llamadart-native",
            )
        with self.assertRaisesRegex(ReleaseError, "does not contain required asset"):
            pins.llama_cpp_bundle_checksum(
                release, "linux-arm64", "b10514-1", {}, repo="leehack/llamadart-native"
            )


if __name__ == "__main__":
    unittest.main()
