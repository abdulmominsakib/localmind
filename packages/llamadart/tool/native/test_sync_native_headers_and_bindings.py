from __future__ import annotations

import hashlib
import io
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parent / "sync_native_headers_and_bindings.sh"
TAG = "v0.16.0"
ASSET_NAME = f"llamadart-native-headers-{TAG}.tar.gz"
CURRENT_LAYOUT_FILES = {
    "llama_cpp/include/llama.h": "// new llama\n",
    "llama_cpp/ggml/include/ggml.h": "// new ggml\n",
    "llama_cpp/ggml/include/ggml-backend.h": "// new ggml backend\n",
    "llama_cpp/tools/mtmd/mtmd.h": "// new mtmd\n",
    "llama_cpp/tools/mtmd/mtmd-helper.h": "// new mtmd helper\n",
    "libllamadart/llama_dart_wrapper.h": "// new wrapper\n",
}


class NativeHeaderSyncIntegrationTest(unittest.TestCase):
    def _temp_archive_path(self) -> Path:
        descriptor, name = tempfile.mkstemp(suffix=".tar.gz")
        os.close(descriptor)
        path = Path(name)
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        return path

    def _write_archive(self, path: Path, files: dict[str, str]) -> None:
        with tarfile.open(path, "w:gz") as archive:
            for name, content in files.items():
                payload = content.encode("utf-8")
                info = tarfile.TarInfo(name)
                info.size = len(payload)
                archive.addfile(info, io.BytesIO(payload))

    def _write_executable(self, path: Path, content: str) -> None:
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def _run_sync(
        self,
        *,
        archive_bytes: bytes,
        curl_mode: str = "ok",
        mv_mode: str = "ok",
        dart_mode: str = "ok",
        skip_ffigen: bool = True,
        live_kind: str = "directory",
        asset_url: str | None = None,
        digest: str | None = None,
        token: str = "",
        stale_paths: bool = False,
        duplicate_asset: bool = False,
        config_capture: str = "",
    ) -> tuple[subprocess.CompletedProcess[str], Path]:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        archive = root / "headers.tar.gz"
        archive.write_bytes(archive_bytes)
        release = root / "release.json"
        asset = {
            "name": ASSET_NAME,
            "browser_download_url": asset_url
            or f"https://github.com/owner/repo/releases/download/{TAG}/{ASSET_NAME}",
            "digest": (
                digest
                if digest is not None
                else f"sha256:{hashlib.sha256(archive_bytes).hexdigest()}"
            ),
        }
        release.write_text(
            json.dumps(
                {
                    "tag_name": TAG,
                    "assets": [asset, dict(asset)] if duplicate_asset else [asset],
                }
            ),
            encoding="utf-8",
        )
        self._write_executable(
            bin_dir / "curl",
            """#!/usr/bin/env python3
import os
from pathlib import Path
import sys

args = sys.argv[1:]
mode = os.environ.get("FAKE_CURL_MODE", "ok")
capture = os.environ.get("FAKE_CONFIG_CAPTURE", "")
if capture:
    for index, arg in enumerate(args[:-1]):
        if arg == "--config":
            text = Path(args[index + 1]).read_text(encoding="utf-8")
            if text.startswith('header = "Authorization:'):
                Path(capture).write_text(text, encoding="utf-8")
token = os.environ.get("FAKE_EXPECT_TOKEN", "")
if token:
    if any(token in arg for arg in args):
        raise SystemExit(90)
    configs = [
        Path(args[index + 1])
        for index, arg in enumerate(args[:-1])
        if arg == "--config"
    ]
    auth = [path for path in configs if token in path.read_text(encoding="utf-8")]
    if len(auth) != 1 or (auth[0].stat().st_mode & 0o777) != 0o600:
        raise SystemExit(91)
if "-o" in args:
    expected_url = os.environ.get("FAKE_EXPECT_URL", "")
    if expected_url and any(expected_url in arg for arg in args):
        raise SystemExit(92)
    configs = [
        Path(args[index + 1])
        for index, arg in enumerate(args[:-1])
        if arg == "--config"
    ]
    if expected_url and not any(
        expected_url in path.read_text(encoding="utf-8") for path in configs
    ):
        raise SystemExit(93)
    if mode == "asset-failure":
        Path(args[args.index("-o") + 1]).write_bytes(b"partial")
        raise SystemExit(22)
    Path(args[args.index("-o") + 1]).write_bytes(
        Path(os.environ["FAKE_ARCHIVE"]).read_bytes()
    )
    raise SystemExit(0)
if mode == "metadata-failure":
    raise SystemExit(22)
sys.stdout.write(Path(os.environ["FAKE_RELEASE"]).read_text(encoding="utf-8"))
""",
        )
        self._write_executable(
            bin_dir / "mv",
            """#!/bin/sh
if [ "${1:-}" = "--" ]; then shift; fi
case "${FAKE_MV_MODE:-ok}:$1" in
  publish-failure:*/staging|swap-failure:*/staging) exit 42 ;;
  preserve-failure:*/ffigen_headers) exit 43 ;;
  restore-failure:*/backup) exit 44 ;;
esac
exec /bin/mv "$@"
""",
        )
        self._write_executable(
            bin_dir / "dart",
            """#!/bin/sh
if [ "${FAKE_DART_MODE:-ok}" = "ffigen-failure" ]; then exit 41; fi
exit 0
""",
        )

        live = root / "ffigen_headers"
        if live_kind == "directory":
            (live / "llama_cpp/include").mkdir(parents=True)
            (live / "llama_cpp/include/llama.h").write_text(
                "// old llama\n", encoding="utf-8"
            )
            (live / "old-marker.txt").write_text("old root\n", encoding="utf-8")
        elif live_kind == "file":
            live.write_text("old file\n", encoding="utf-8")
        elif live_kind == "symlink":
            target = root / "old-target"
            target.mkdir()
            (target / "old-marker.txt").write_text("old link\n", encoding="utf-8")
            live.symlink_to(target, target_is_directory=True)
        elif live_kind != "missing":
            raise AssertionError(f"unsupported live kind: {live_kind}")
        if stale_paths:
            for suffix in ("staging.123", "backup.123"):
                stale = live.parent / f"{live.name}.{suffix}"
                stale.mkdir()
                (stale / "marker").write_text("stale", encoding="utf-8")
        env = os.environ.copy()
        env.update(
            {
                "FAKE_ARCHIVE": str(archive),
                "FAKE_RELEASE": str(release),
                "FAKE_CURL_MODE": curl_mode,
                "FAKE_MV_MODE": mv_mode,
                "FAKE_DART_MODE": dart_mode,
                "PATH": f"{bin_dir}{os.pathsep}{env['PATH']}",
                "LLAMADART_FFIGEN_HEADER_ROOT": str(live),
                "GH_TOKEN": token,
                "FAKE_EXPECT_TOKEN": token,
                "FAKE_CONFIG_CAPTURE": config_capture,
                "FAKE_EXPECT_URL": asset_url
                or f"https://github.com/owner/repo/releases/download/{TAG}/{ASSET_NAME}",
            }
        )
        command = [str(SCRIPT_PATH), "--tag", TAG]
        if skip_ffigen:
            command.append("--skip-ffigen")
        result = subprocess.run(
            command,
            cwd=SCRIPT_PATH.parents[2],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        return result, live

    def _assert_previous_root(self, live: Path) -> None:
        self.assertEqual(
            (live / "old-marker.txt").read_text(encoding="utf-8"), "old root\n"
        )
        self.assertEqual(
            (live / "llama_cpp/include/llama.h").read_text(encoding="utf-8"),
            "// old llama\n",
        )
        self.assertEqual(list(live.parent.glob(f"{live.name}.*")), [])

    def test_successful_replacement_swaps_complete_root(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        result, live = self._run_sync(archive_bytes=archive_path.read_bytes())

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((live / "old-marker.txt").exists())
        for relative, content in CURRENT_LAYOUT_FILES.items():
            self.assertEqual((live / relative).read_text(encoding="utf-8"), content)
        self.assertEqual(list(live.parent.glob(f"{live.name}.*")), [])

    def test_missing_required_header_preserves_previous_root(self) -> None:
        files = dict(CURRENT_LAYOUT_FILES)
        files.pop("llama_cpp/tools/mtmd/mtmd-helper.h")
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, files)
        result, live = self._run_sync(archive_bytes=archive_path.read_bytes())

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("left", result.stderr)
        self._assert_previous_root(live)

    def test_corrupt_archive_preserves_previous_root(self) -> None:
        result, live = self._run_sync(archive_bytes=b"not a gzip archive")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("left", result.stderr)
        self._assert_previous_root(live)

    def test_unsafe_archive_entry_preserves_previous_root(self) -> None:
        archive_path = self._temp_archive_path()
        with tarfile.open(archive_path, "w:gz") as archive:
            for name, content in CURRENT_LAYOUT_FILES.items():
                payload = content.encode("utf-8")
                info = tarfile.TarInfo(name)
                info.size = len(payload)
                archive.addfile(info, io.BytesIO(payload))
            link = tarfile.TarInfo("llama_cpp/include/unsafe.h")
            link.type = tarfile.SYMTYPE
            link.linkname = "/etc/passwd"
            archive.addfile(link)
        result, live = self._run_sync(archive_bytes=archive_path.read_bytes())

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("left", result.stderr)
        self._assert_previous_root(live)

    def test_swap_failure_restores_previous_root(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        result, live = self._run_sync(
            archive_bytes=archive_path.read_bytes(), mv_mode="publish-failure"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Restored the previous header root", result.stderr)
        self._assert_previous_root(live)

    def test_backup_rename_failure_leaves_previous_root_in_place(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        result, live = self._run_sync(
            archive_bytes=archive_path.read_bytes(), mv_mode="preserve-failure"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to preserve", result.stderr)
        self._assert_previous_root(live)

    def test_restore_failure_preserves_the_backup(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        result, live = self._run_sync(
            archive_bytes=archive_path.read_bytes(),
            mv_mode="restore-failure",
            dart_mode="ffigen-failure",
            skip_ffigen=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("preserved its backup", result.stderr)
        backups = list(live.parent.glob(f".{live.name}.sync.*/backup"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(
            (backups[0] / "old-marker.txt").read_text(encoding="utf-8"),
            "old root\n",
        )

    def test_ffigen_failure_without_previous_root_removes_publication(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        result, live = self._run_sync(
            archive_bytes=archive_path.read_bytes(),
            dart_mode="ffigen-failure",
            skip_ffigen=False,
            live_kind="missing",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(live.exists())
        self.assertEqual(list(live.parent.glob(f".{live.name}.sync.*")), [])

    def test_ffigen_failure_restores_file_and_symlink_roots(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        payload = archive_path.read_bytes()
        for live_kind in ("file", "symlink"):
            with self.subTest(live_kind=live_kind):
                result, live = self._run_sync(
                    archive_bytes=payload,
                    dart_mode="ffigen-failure",
                    skip_ffigen=False,
                    live_kind=live_kind,
                )
                self.assertNotEqual(result.returncode, 0)
                if live_kind == "file":
                    self.assertTrue(live.is_file())
                    self.assertEqual(live.read_text(encoding="utf-8"), "old file\n")
                else:
                    self.assertTrue(live.is_symlink())
                    self.assertEqual(
                        (live / "old-marker.txt").read_text(encoding="utf-8"),
                        "old link\n",
                    )

    def test_stale_pid_paths_are_not_used_or_removed(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        result, live = self._run_sync(
            archive_bytes=archive_path.read_bytes(), stale_paths=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for suffix in ("staging.123", "backup.123"):
            self.assertEqual(
                (live.parent / f"{live.name}.{suffix}" / "marker").read_text(
                    encoding="utf-8"
                ),
                "stale",
            )

    def test_digest_failure_preserves_previous_root(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        result, live = self._run_sync(
            archive_bytes=archive_path.read_bytes(), digest=f"sha256:{'0' * 64}"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum mismatch", result.stderr)
        self._assert_previous_root(live)

    def test_missing_stable_digest_preserves_previous_root(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        result, live = self._run_sync(
            archive_bytes=archive_path.read_bytes(), digest=""
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not publish", result.stderr)
        self._assert_previous_root(live)

    def test_duplicate_asset_inventory_preserves_previous_root(self) -> None:
        result, live = self._run_sync(
            archive_bytes=b"unused", duplicate_asset=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicates", result.stderr)
        self._assert_previous_root(live)

    def test_token_and_asset_url_stay_out_of_curl_arguments(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        secret = "test-secret-token"
        result, _ = self._run_sync(
            archive_bytes=archive_path.read_bytes(), token=secret
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(secret, result.stdout + result.stderr)

    def _serve_authorization_probe(self) -> tuple[str, list[str | None]]:
        seen: list[str | None] = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                seen.append(self.headers.get("Authorization"))
                self.send_response(200)
                self.send_header("Content-Length", "2")
                self.end_headers()
                self.wfile.write(b"{}")

            def log_message(self, *args: object) -> None:
                return

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_address[1]}/release", seen

    @unittest.skipUnless(shutil.which("curl"), "requires curl")
    def test_written_curl_config_authenticates_a_real_request(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        secret = "ghp-llamadart-transport-probe-9f2c4e"
        capture_dir = tempfile.TemporaryDirectory()
        self.addCleanup(capture_dir.cleanup)
        capture = Path(capture_dir.name) / "curl.conf"

        result, _ = self._run_sync(
            archive_bytes=archive_path.read_bytes(),
            token=secret,
            config_capture=str(capture),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            capture.read_text(encoding="utf-8"),
            f'header = "Authorization: Bearer {secret}"\n',
        )

        url, seen = self._serve_authorization_probe()
        probe = subprocess.run(
            ["curl", "-fsS", "--config", str(capture), url],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(probe.returncode, 0, probe.stderr)
        self.assertEqual(seen, [f"Bearer {secret}"])
        self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertNotIn(secret, probe.stdout + probe.stderr)

    def test_token_and_credential_url_are_not_reported(self) -> None:
        secret = "test-secret-token"
        result, live = self._run_sync(
            archive_bytes=b"unused",
            asset_url="https://user:password@github.com/owner/repo/archive?token=secret",
            token=secret,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertNotIn("password", result.stdout + result.stderr)
        self._assert_previous_root(live)

    def test_ffigen_failure_restores_previous_root(self) -> None:
        archive_path = self._temp_archive_path()
        self._write_archive(archive_path, CURRENT_LAYOUT_FILES)
        result, live = self._run_sync(
            archive_bytes=archive_path.read_bytes(),
            dart_mode="ffigen-failure",
            skip_ffigen=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Restored the previous header root", result.stderr)
        self._assert_previous_root(live)

    def test_interrupted_asset_download_preserves_previous_root(self) -> None:
        result, live = self._run_sync(
            archive_bytes=b"partial archive", curl_mode="asset-failure"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to download", result.stderr)
        self._assert_previous_root(live)

    def test_release_metadata_failure_preserves_previous_root(self) -> None:
        result, live = self._run_sync(
            archive_bytes=b"unused", curl_mode="metadata-failure"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to fetch", result.stderr)
        self._assert_previous_root(live)


TAG_PREDICATES = (
    "is_supported_native_tag",
    "is_latest_eligible_tag",
    "is_stable_upstream_tag",
    "is_allowed_native_tag_input",
)


class NativeReleaseTagGrammarBashIntegrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        fixture_path = (
            Path(__file__).resolve().parent
            / "fixtures"
            / "native_release_tag_grammar.json"
        )
        cls.fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        cls.forms = cls.fixture["forms"]

    def _classify(self, tag: str) -> dict[str, bool]:
        if "\x00" in tag:
            return dict.fromkeys(TAG_PREDICATES, False)
        script = f'source "{SCRIPT_PATH}"\n' + "".join(
            f'if {name} "$1"; then echo 1; else echo 0; fi\n' for name in TAG_PREDICATES
        )
        proc = subprocess.run(
            ["bash", "-c", script, "_", tag],
            capture_output=True,
            text=True,
            check=True,
        )
        return dict(zip(TAG_PREDICATES, [line == "1" for line in proc.stdout.split()]))

    def test_positive_tag_corpus_in_bash(self) -> None:
        for case in self.fixture["positive_cases"]:
            tag = case["tag"]
            form = self.forms[case["form"]]
            with self.subTest(tag=tag):
                actual = self._classify(tag)
                self.assertTrue(actual["is_supported_native_tag"])
                self.assertTrue(actual["is_allowed_native_tag_input"])
                self.assertEqual(
                    actual["is_latest_eligible_tag"], form["is_latest_eligible"]
                )
                self.assertEqual(
                    actual["is_stable_upstream_tag"], form["is_stable_upstream"]
                )

    def test_negative_tag_corpus_in_bash(self) -> None:
        for case in self.fixture["negative_cases"]:
            tag = case["tag"]
            with self.subTest(tag=tag, reason=case["reason"]):
                self.assertEqual(
                    self._classify(tag), dict.fromkeys(TAG_PREDICATES, False)
                )

    def test_reserved_inputs_follow_consumer_policy(self) -> None:
        for case in self.fixture["reserved_inputs"]:
            value = case["value"]
            with self.subTest(value=value):
                actual = self._classify(value)
                self.assertEqual(
                    actual["is_allowed_native_tag_input"], case["bash_header_sync"]
                )
                self.assertFalse(actual["is_supported_native_tag"])

    def test_cli_rejects_negative_corpus_before_network(self) -> None:
        for case in self.fixture["negative_cases"]:
            tag = case["tag"]
            with self.subTest(tag=tag, reason=case["reason"]):
                if "\x00" in tag:
                    with self.assertRaises(ValueError):
                        subprocess.run(
                            [str(SCRIPT_PATH), "--tag", tag, "--skip-ffigen"],
                            capture_output=True,
                            text=True,
                        )
                    continue
                proc = subprocess.run(
                    [str(SCRIPT_PATH), "--tag", tag, "--skip-ffigen"],
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(proc.returncode, 0)
                self.assertIn("Invalid llamadart-native tag", proc.stderr)


if __name__ == "__main__":
    unittest.main()
