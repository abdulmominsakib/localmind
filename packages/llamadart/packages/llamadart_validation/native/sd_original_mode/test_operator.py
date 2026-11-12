"""Synthetic protocol/graph controls; never opens the pinned original files."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import run as operator


class OperatorTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sd24-operator-model-free-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.library = self.root / "synthetic-library"
        self.library.write_bytes(b"synthetic, never loaded")
        self.bound = {"path": str(self.library), "sha256": operator.digest(self.library)}
        self.executable = self.root / "synthetic-macho-header"
        self.executable.write_bytes(bytes.fromhex("cffaedfe") + b"not executable")
        self.snapshot = self.root / "synthetic-kernel-header"
        self.snapshot.write_bytes(bytes.fromhex("90abcdef") + b"not executable")

    def plan(self):
        plan = {"schema": 1, "scope": "pr41-original-mode-diagnostic", "ownerCommit": operator.OWNER,
                "sourceCommit": "a" * 40, "artifactRun": 41673639935, "artifactId": 13249907568,
                "models": [{"id": name, "sha256": sha, "bytes": size, "path": "/synthetic/" + name}
                           for name, sha, size in operator.MODELS],
                "taesd": {"path": "/synthetic/taesd", "sha256": operator.TAESD, "bytes": 9793292}}
        for key in ("nativeExecutable", "dartExecutable", "publicSnapshot", "nativeLibrary", "publicLibrary", "artifactReview", "sourceAdmission", "nativeAssets", "nativeBuildReceipt", "publicBuildReceipt", "runtimeStagingReceipt"):
            plan[key] = dict(self.bound)
        plan["nativeLibrary"]["sha256"] = operator.LIBRARY
        plan["artifactReview"]["sha256"] = operator.ARTIFACT_REVIEW
        for key in ("nativeExecutable", "dartExecutable"):
            plan[key] = {"path": str(self.executable), "sha256": operator.digest(self.executable)}
        plan["publicSnapshot"] = {"path": str(self.snapshot), "sha256": operator.digest(self.snapshot)}
        return plan

    def fixture(self, name, route="native", load_ms=3, pixels=None, stages=None):
        directory = self.root / name
        directory.mkdir()
        rows = stages or [{"schema": 1, "stage": s, "elapsedMs": i, "loadMs": load_ms} for i, s in enumerate(operator.STAGES)]
        binding = {"schema": 1, "route": route, "mappedLibraryPath": str(self.library), "mappedLibrarySha256": self.bound["sha256"]}
        data = "".join("SD24_STAGE " + json.dumps(row) + "\n" for row in rows)
        data += "SD24_BINDING " + json.dumps(binding) + "\n"
        data += "SD24_CONFIG " + json.dumps(operator.CONFIG) + "\n"
        if route == "public": data += 'SD24_PUBLIC {"backend":"CPU","family":"SD 2.x"}\n'
        (directory / "stdout.log").write_text(data)
        (directory / "stderr.log").write_bytes(b"FAMILY=SD 2.x\n")
        rgb = pixels if pixels is not None else bytes(range(256)) * 192
        (directory / "image.ppm").write_bytes(operator.PREFIX + rgb)
        record = {"exit": 0, "leader_reaped": True, "deadline_seconds": 177, "cleanup_deadline_seconds": 3,
                  "case_deadline_seconds": 180,
                  "timed_out": False, "capture_limit_exceeded": False, "cleanup_errors": [], "failure_type": None,
                  "received_signals": [], "raw": {}}
        for filename in ("stdout.log", "stderr.log"):
            path = directory / filename
            record["raw"][filename] = {"sha256": operator.digest(path), "bytes": path.stat().st_size}
        (directory / "capture.json").write_text(json.dumps(record))
        return directory, rgb

    def grade(self, directory, route="native", baseline=None, paired=None):
        plan = {"nativeLibrary": self.bound, "publicLibrary": self.bound}
        return operator.grade(directory, {"route": route}, plan, baseline, paired)

    def test_native_baseline_public_pair_and_unmodified_raw_hashes(self):
        native, rgb = self.fixture("native")
        self.assertEqual(self.grade(native), rgb)
        public, _ = self.fixture("public", route="public")
        self.assertEqual(self.grade(public, "public", rgb, rgb), rgb)
        (public / "stderr.log").write_bytes(b"tampered")
        with self.assertRaises(ValueError): self.grade(public, "public", rgb, rgb)

    def test_late_load_trivial_pixels_wrong_parity_and_missing_disposal_fail(self):
        for name in ("late", "trivial", "parity", "dispose"):
            with self.subTest(case=name):
                directory, rgb = self.fixture(name, load_ms=45000 if name == "late" else 3,
                    pixels=bytes(49152) if name == "trivial" else None,
                    stages=[{"schema": 1, "stage": s, "elapsedMs": i, "loadMs": 3} for i, s in enumerate(operator.STAGES[:-1])] if name == "dispose" else None)
                with self.assertRaises(ValueError):
                    self.grade(directory, baseline=bytes(49152) if name == "parity" else None)
                self.assertTrue((directory / "image-receipt.json").is_file(), "raw output must be hash-bound before grading")

    def test_original_input_or_scope_substitution_is_rejected(self):
        plan = self.plan()
        operator.validate_plan(plan)
        for key in ("model", "taesd", "runtime", "scope"):
            changed = copy.deepcopy(plan)
            if key == "model": changed["models"][1]["sha256"] = "0" * 64
            if key == "taesd": changed["taesd"]["sha256"] = "0" * 64
            if key == "runtime": changed["nativeLibrary"]["sha256"] = "0" * 64
            if key == "scope": changed["scope"] = "published-qualified"
            with self.assertRaises(ValueError): operator.validate_plan(changed)
        wrong = {**self.bound, "sha256": "0" * 64}
        with self.assertRaises(ValueError): operator.verify(wrong)

    def test_first_baseline_failure_stops_all_remaining_children(self):
        output = self.root / "run"
        calls = []
        def owned(argv, directory, identity, **kwargs):
            calls.append((identity, kwargs))
            directory.mkdir()
            phase = identity.get("phase")
            if phase == "preflight-git-head": (directory / "stdout.log").write_text("a" * 40 + "\n")
            if phase == "preflight-git-status": (directory / "stdout.log").write_bytes(b"")
            if phase == "preflight-hash": (output / "identities.json").write_text("{}")
            if phase == "grade": raise ValueError("synthetic baseline failure")
        with patch.object(operator.sys, "platform", "darwin"), patch.object(operator.platform, "machine", return_value="arm64"), \
             patch.dict(operator.os.environ, {k: "" for k in ("DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "LD_PRELOAD", "LD_LIBRARY_PATH")}), \
             patch.object(operator, "run_owned", side_effect=owned):
            with self.assertRaisesRegex(ValueError, "baseline failure"):
                operator.execute(self.plan(), output)
        models = [(identity, kwargs) for identity, kwargs in calls if identity.get("model_inference")]
        self.assertEqual(len(models), 1)
        self.assertEqual(models[0][1]["seconds"], 177)
        self.assertEqual(models[0][1]["budget"]["phase"], "cases")
        summary = json.loads((output / "summary.json").read_text())
        self.assertFalse(summary["diagnosticPassed"])
        self.assertEqual([r["status"] for r in summary["cases"]], ["FAIL"] + ["NOT_RUN"] * 5)

    def test_fixed_six_case_graph_and_strict_total_budget(self):
        rows = operator.commands(self.plan(), self.root)
        self.assertEqual([r["id"] for r in rows], ["native-safetensors", "public-safetensors", "native-flat", "public-flat", "native-nested", "public-nested"])
        self.assertIn("--original-mode", rows[0]["argv"])
        self.assertEqual(rows[1]["argv"][1], str(self.snapshot))

    def test_whole_case_expiry_rejects_grade_with_aggregate_time_remaining(self):
        output = self.root / "whole-case"
        now = [0.0]
        calls = []
        def owned(argv, directory, identity, **kwargs):
            calls.append((identity, kwargs))
            directory.mkdir()
            phase = identity.get("phase")
            if phase == "preflight-git-head": (directory / "stdout.log").write_text("a" * 40 + "\n")
            if phase == "preflight-git-status": (directory / "stdout.log").write_bytes(b"")
            if phase == "preflight-hash": (output / "identities.json").write_text("{}")
            if identity.get("model_inference") and identity["case"] == "native-safetensors": now[0] = 176.5
            if phase == "grade":
                (output / identity["case"] / "grade.json").write_text('{"passed":true}')
                now[0] = 180.5
            if phase == "post":
                summary = json.loads((output / "summary.json").read_text())
                summary["diagnosticPassed"] = not summary.get("failure")
                (output / "summary.json").write_text(json.dumps(summary))
        with patch.object(operator.sys, "platform", "darwin"), patch.object(operator.platform, "machine", return_value="arm64"), \
             patch.dict(operator.os.environ, {k: "" for k in ("DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "LD_PRELOAD", "LD_LIBRARY_PATH")}), \
             patch.object(operator.time, "monotonic", side_effect=lambda: now[0]), \
             patch.object(operator, "run_owned", side_effect=owned):
            with self.assertRaises(operator.PhaseTimeout): operator.execute(self.plan(), output)
        summary = json.loads((output / "summary.json").read_text())
        self.assertLess(now[0], summary["phaseBudgets"]["cases"]["active_end"])
        self.assertFalse(summary["diagnosticPassed"])
        self.assertEqual([r["status"] for r in summary["cases"]], ["FAIL"] + ["NOT_RUN"] * 5)
        models = [kwargs for identity, kwargs in calls if identity.get("model_inference")]
        grades = [kwargs for identity, kwargs in calls if identity.get("phase") == "grade"]
        self.assertEqual(len(models), 1)
        self.assertEqual(models[0]["budget"]["total_end"], 180)
        self.assertEqual(grades[0]["budget"], models[0]["budget"])

    def test_loader_overrides_are_refused_before_any_payload_or_child(self):
        keys = ("DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "LD_PRELOAD", "LD_LIBRARY_PATH")
        for key in keys:
            with self.subTest(variable=key):
                environment = {k: "" for k in keys}
                environment[key] = "/synthetic/override"
                with patch.object(operator.sys, "platform", "darwin"), patch.object(operator.platform, "machine", return_value="arm64"), \
                     patch.dict(operator.os.environ, environment), patch.object(operator, "verify") as verify, \
                     patch.object(operator, "capture") as child:
                    with self.assertRaisesRegex(ValueError, "override"):
                        operator.execute(self.plan(), self.root / key)
                verify.assert_not_called()
                child.assert_not_called()

    def test_late_grade_or_post_success_cannot_mark_diagnostic_passed(self):
        for failure_at in ("grade", "post", "unknown"):
            with self.subTest(failure_at=failure_at):
                output = self.root / ("aggregate-" + failure_at)
                calls = []
                def owned(argv, directory, identity, **kwargs):
                    calls.append(identity)
                    directory.mkdir()
                    phase = identity.get("phase")
                    if phase == "preflight-git-head": (directory / "stdout.log").write_text("a" * 40 + "\n")
                    if phase == "preflight-git-status": (directory / "stdout.log").write_bytes(b"")
                    if phase == "preflight-hash": (output / "identities.json").write_text("{}")
                    if identity.get("model_inference") and failure_at == "unknown":
                        raise operator.CleanupUnknown("synthetic unverified cleanup")
                    if phase == "grade":
                        (output / identity["case"] / "grade.json").write_text('{"passed":true}')
                        if failure_at == "grade": kwargs["budget"]["active_end"] = -1
                    if phase == "post":
                        summary = json.loads((output / "summary.json").read_text())
                        summary["diagnosticPassed"] = True
                        (output / "summary.json").write_text(json.dumps(summary))
                        if failure_at == "post": raise operator.PhaseTimeout("synthetic late post")
                with patch.object(operator.sys, "platform", "darwin"), patch.object(operator.platform, "machine", return_value="arm64"), \
                     patch.dict(operator.os.environ, {k: "" for k in ("DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "LD_PRELOAD", "LD_LIBRARY_PATH")}), \
                     patch.object(operator, "run_owned", side_effect=owned):
                    with self.assertRaises((operator.PhaseTimeout, operator.CleanupUnknown)):
                        operator.execute(self.plan(), output)
                summary = json.loads((output / "summary.json").read_text())
                self.assertFalse(summary["diagnosticPassed"])
                if failure_at != "post":
                    self.assertEqual(summary["cases"][0]["status"], "FAIL")
                    self.assertEqual(sum(bool(c.get("model_inference")) for c in calls), 1)
                if failure_at == "unknown":
                    self.assertEqual(summary["cleanup"], "UNKNOWN")
                    self.assertFalse(any(c.get("phase") == "post" for c in calls))


if __name__ == "__main__": unittest.main()
