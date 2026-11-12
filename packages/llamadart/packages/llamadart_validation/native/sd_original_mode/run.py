"""Six fixed original-mode image cases; explicit local diagnostic admission only."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import shutil
import time
import sys

from owned_capture import CaptureInterrupted, capture, digest

REPO = Path(__file__).resolve().parents[4]
OWNER = "6f54ed2d257faa0ed27d2a93cc5d89ea268e622d"
LIBRARY = "3c371373a9d91599c44a1301c3a3b8c3dca629c1b0cbfb3c1cf687bde4a3a5c8"
ARTIFACT_REVIEW = "6470c09fafb5458b8ed08415292ea85947d992c8608e22247703c2a2479eb364"
MODELS = [
    ("safetensors", "4505ca3da482f3e01679f6301bf23cde136e0cb3ffeb66b7e809038f619a19b4", 2612796864),
    ("flat", "05e2a2fef17ef03962c522374c01c373a71d5cbde20380f7800678c3ae99a75d", 2613072319),
    ("nested", "52dfdb8aa825c27bded6f11c5f25f8c4fe57405c0fc633e2f74f375186a36309", 2613072319),
]
TAESD = "db169d69145ec4ff064e49d99c95fa05d3eb04ee453de35824a6d0f325513549"
PREFIX = b"P6\n128 128\n255\n"
STAGES = ["load_begin", "load_end", "generation_begin", "generation_end", "pixels_written", "disposed"]
CONFIG = {"backend": "cpu", "threads": 4, "cache": 4, "eager": True, "batchedCfg": False,
          "diffusionFlash": True, "vaeDirect": False, "flashMode": "off,diffusion=on", "convMode": "off", "autoFit": True}
if not __debug__:
    raise RuntimeError("Python optimization disables diagnostic validation")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_plan(plan):
    keys = {"schema", "scope", "ownerCommit", "sourceCommit", "artifactRun", "artifactId", "models", "taesd",
            "nativeExecutable", "dartExecutable", "publicSnapshot", "nativeLibrary", "publicLibrary",
            "artifactReview", "sourceAdmission", "nativeAssets", "nativeBuildReceipt", "publicBuildReceipt", "runtimeStagingReceipt"}
    require(set(plan) == keys, "missing or unknown plan configuration")
    require(plan["schema"] == 1 and plan["scope"] == "pr41-original-mode-diagnostic", "diagnostic scope required")
    require(plan["ownerCommit"] == OWNER, "exact reviewed owner source required")
    require(plan["artifactRun"] == 41673639935 and plan["artifactId"] == 13249907568, "exact diagnostic artifact required")
    require(plan["nativeLibrary"]["sha256"] == LIBRARY, "exact PR41 Mac dylib required")
    require(plan["artifactReview"]["sha256"] == ARTIFACT_REVIEW, "accepted diagnostic artifact review required")
    require(re.fullmatch("[0-9a-f]{40}", plan["sourceCommit"]) is not None, "frozen consumer source required")
    require(len(plan["models"]) == 3, "exactly three original inputs required")
    for model, (name, sha, size) in zip(plan["models"], MODELS):
        require((model["id"], model["sha256"], model["bytes"]) == (name, sha, size), "original model substitution refused")
        require(Path(model["path"]).is_absolute(), "absolute original model path required")
    require(plan["taesd"]["sha256"] == TAESD and plan["taesd"]["bytes"] == 9793292, "exact external full TAESD required")
    require(Path(plan["taesd"]["path"]).is_absolute(), "absolute decoder path required")
    for key in ("nativeExecutable", "dartExecutable", "publicSnapshot", "nativeLibrary", "publicLibrary", "artifactReview", "sourceAdmission", "nativeAssets", "nativeBuildReceipt", "publicBuildReceipt", "runtimeStagingReceipt"):
        item = plan[key]
        require(Path(item["path"]).is_absolute() and re.fullmatch("[0-9a-f]{64}", item["sha256"]) is not None, "complete binding required: " + key)


def verify(item):
    path = Path(item["path"])
    require(path.is_file(), "missing bound file: " + str(path))
    if "bytes" in item:
        require(path.stat().st_size == item["bytes"], "file size differs: " + str(path))
    actual = digest(path)
    require(actual == item["sha256"], "file hash differs: " + str(path))
    return {"path": str(path), "sha256": actual, "bytes": path.stat().st_size}


def commands(plan, output):
    rows = []
    for model in plan["models"]:
        for route in ("native", "public"):
            case = route + "-" + model["id"]
            image = output / case / "image.ppm"
            argv = ([plan["nativeExecutable"]["path"], "--original-mode", model["path"], plan["taesd"]["path"], str(image), plan["nativeLibrary"]["path"]]
                    if route == "native" else [plan["dartExecutable"]["path"], plan["publicSnapshot"]["path"],
                    model["path"], plan["taesd"]["path"], str(image), plan["publicLibrary"]["sha256"], plan["publicLibrary"]["path"]])
            rows.append({"id": case, "route": route, "model": model, "argv": argv})
    return rows


def protocol(path, prefix):
    rows = []
    for line in path.read_bytes().splitlines():
        if line.startswith(prefix):
            rows.append(json.loads(line[len(prefix):]))
    return rows


def retain_image(directory):
    image = directory / "image.ppm"
    if not image.is_file():
        return None
    record = {"sha256": digest(image), "bytes": image.stat().st_size}
    (directory / "image-receipt.json").write_text(json.dumps(record, indent=2) + "\n")
    return record


def grade(directory, row, plan, baseline, paired):
    image_record = retain_image(directory)
    receipt = json.loads((directory / "capture.json").read_text())
    for key in ("timed_out", "capture_limit_exceeded", "cleanup_errors", "failure_type", "received_signals"):
        require(not receipt[key], "failed capture: " + key)
    require(receipt["exit"] == 0 and receipt["leader_reaped"] is True, "owned exit/reap required")
    require(receipt["deadline_seconds"] == 177 and receipt["cleanup_deadline_seconds"] == 3, "case bounds changed")
    require(receipt["case_deadline_seconds"] == 180, "total case cap differs")
    require(set(receipt["raw"]) == {"stdout.log", "stderr.log"}, "complete raw streams required")
    for filename, raw in receipt["raw"].items():
        path = directory / filename
        require(raw["bytes"] == path.stat().st_size <= 2 << 20 and digest(path) == raw["sha256"], "raw capture changed")
    stdout = directory / "stdout.log"
    stages = protocol(stdout, b"SD24_STAGE ")
    require([s["stage"] for s in stages] == STAGES, "complete ordered load/generate/dispose required")
    require(all(s["schema"] == 1 for s in stages), "stage schema differs")
    require(all(a["elapsedMs"] <= b["elapsedMs"] for a, b in zip(stages, stages[1:])), "stage clock reversed")
    load = stages[1]["loadMs"]
    require(type(load) is int and 0 <= load < 45000, "original load bound exceeded")
    bindings = protocol(stdout, b"SD24_BINDING ")
    require(len(bindings) == 1 and bindings[0]["route"] == row["route"], "one actual route binding required")
    library = plan["nativeLibrary" if row["route"] == "native" else "publicLibrary"]
    require(Path(bindings[0]["mappedLibraryPath"]).resolve() == Path(library["path"]).resolve(), "mapped library differs")
    verify(library)
    if row["route"] == "public":
        require(bindings[0]["mappedLibrarySha256"] == library["sha256"], "public binding hash differs")
        public = protocol(stdout, b"SD24_PUBLIC ")
        require(len(public) == 1 and public[0]["backend"] == "CPU" and public[0]["family"] == "SD 2.x", "public CPU/family evidence missing")
    else:
        require(b"FAMILY=SD 2.x\n" in (directory / "stderr.log").read_bytes(), "native family differs")
        require(protocol(stdout, b"SD24_CONFIG ") == [CONFIG], "actual native context settings differ")
    image = directory / "image.ppm"
    require(image_record is not None, "raw image missing")
    require(image_record["bytes"] == len(PREFIX) + 128 * 128 * 3, "wrong raw RGB dimensions/count")
    raw = image.read_bytes()
    require(raw.startswith(PREFIX), "wrong PPM header")
    rgb = raw[len(PREFIX):]
    require(len(set(rgb)) > 64, "trivial RGB output")
    if baseline is not None:
        require(rgb == baseline, "original same-weight baseline RGB differs")
    if row["route"] == "public":
        require(paired is not None and rgb == paired, "public/native RGB differs")
    result = {"passed": True, "scope": "PR41 diagnostic only; not final-published runtime qualification",
              "loadMs": load, "rgbSha256": hashlib.sha256(rgb).hexdigest(), "binding": bindings[0]}
    (directory / "grade.json").write_text(json.dumps(result, indent=2) + "\n")
    return rgb


# Phase workers own all potentially blocking hashing/grading work. No alarms
# can become pending across Popen registration; every subprocess has one owner.
BUDGETS = {"preflight": (57, 60), "cases": (1074, 1080), "post": (7, 10)}


class PhaseTimeout(TimeoutError):
    pass


class CleanupUnknown(RuntimeError):
    pass


def phase_budget(name):
    started = time.monotonic()
    active, total = BUDGETS[name]
    return {"phase": name, "started": started, "active_end": started + active, "total_end": started + total}


def before_deadline(budget):
    if time.monotonic() >= budget["active_end"]:
        raise PhaseTimeout(budget["phase"] + " active deadline expired")


def settled(record):
    return (record.get("pid") is None or record.get("leader_reaped") is True) and not record.get("cleanup_errors")


def run_owned(command, directory, identity, *, seconds, budget):
    before_deadline(budget)
    try:
        record = capture(command, directory, identity, seconds=seconds,
                         active_deadline=budget["active_end"], total_deadline=budget["total_end"])
    except BaseException:
        try:
            record = json.loads((directory / "capture.json").read_text())
        except BaseException as failure:
            raise CleanupUnknown("owned terminal receipt unavailable") from failure
        if not settled(record):
            raise CleanupUnknown("owned cleanup is UNKNOWN")
        raise
    if not settled(record):
        raise CleanupUnknown("owned cleanup is UNKNOWN")
    require(record["exit"] == 0 and not record["timed_out"] and not record["capture_limit_exceeded"]
            and not record["received_signals"] and not record["failure_type"]
            and not record.get("shared_deadline_reached"), "owned phase/case failed")
    # A zero exit or already-written grade cannot turn an expired phase green.
    before_deadline(budget)
    return record


def verify_payloads(plan, output):
    identities = {}
    for key in ("nativeExecutable", "dartExecutable", "publicSnapshot", "nativeLibrary", "publicLibrary", "artifactReview", "sourceAdmission", "nativeAssets", "nativeBuildReceipt", "publicBuildReceipt", "runtimeStagingReceipt", "taesd"):
        identities[key] = verify(plan[key])
    for key in ("nativeExecutable", "dartExecutable"):
        with Path(plan[key]["path"]).open("rb") as stream:
            require(stream.read(4) in (bytes.fromhex("cffaedfe"), bytes.fromhex("cafebabe"), bytes.fromhex("cafebabf")),
                    "direct Mach-O executable required; shell/build launchers refused")
    with Path(plan["publicSnapshot"]["path"]).open("rb") as stream:
        require(stream.read(4) == bytes.fromhex("90abcdef"), "precompiled public kernel snapshot required")
    for model in plan["models"]:
        identities[model["id"]] = verify(model)
    (output / "identities.json").write_text(json.dumps(identities, indent=2) + "\n")


def worker_command(kind, plan_path, output, expected, case=None):
    command = [str(Path(sys.executable).resolve()), str(Path(__file__).resolve()),
               "--phase-worker", kind, "--plan", str(plan_path), "--plan-sha256", expected, "--out", str(output)]
    if case is not None:
        command += ["--case-id", case]
    return command


def phase_worker(kind, plan, output, case):
    if kind == "preflight":
        verify_payloads(plan, output)
    elif kind == "grade":
        row = next(r for r in commands(plan, output) if r["id"] == case)
        baseline = None if case == "native-safetensors" else (output / "native-safetensors/image.ppm").read_bytes()[len(PREFIX):]
        paired = (output / ("native-" + row["model"]["id"]) / "image.ppm").read_bytes()[len(PREFIX):] if row["route"] == "public" else None
        grade(output / case, row, plan, baseline, paired)
    elif kind == "post":
        for row in commands(plan, output):
            retain_image(output / row["id"])
        summary = json.loads((output / "summary.json").read_text())
        summary["diagnosticPassed"] = not summary.get("failure") and all(s["status"] == "PASS" for s in summary["cases"])
        temporary = output / "summary.partial"
        temporary.write_text(json.dumps(summary, indent=2) + "\n")
        temporary.replace(output / "summary.json")
    else:
        raise ValueError("unknown data-only phase worker")
    print(json.dumps({"phase": kind, "case": case, "completed": True, "model_inference": False}))


def execute(plan, output):
    validate_plan(plan)
    preflight = phase_budget("preflight")
    output.mkdir(parents=True, exist_ok=False)
    rows = commands(plan, output)
    summary = {"scope": plan["scope"], "qualified": False, "diagnosticPassed": False,
               "host": {"system": platform.system(), "machine": platform.machine(), "osRelease": platform.release(), "macos": platform.mac_ver()[0]},
               "cases": [{"id": r["id"], "status": "NOT_RUN"} for r in rows], "phaseBudgets": {}}
    plan_path = output / "frozen-plan.json"
    plan_path.write_text(json.dumps(plan, indent=2) + "\n")
    summary["planSha256"] = digest(plan_path)
    def save():
        temporary = output / "summary.partial"
        temporary.write_text(json.dumps(summary, indent=2) + "\n")
        temporary.replace(output / "summary.json")
    save()
    error = None
    try:
        require(sys.platform == "darwin" and platform.machine() == "arm64", "this diagnostic plan is macOS arm64-only")
        require(not any(os.environ.get(k) for k in ("DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "LD_PRELOAD", "LD_LIBRARY_PATH")), "library injection/override environment refused")
        summary["phaseBudgets"]["preflight"] = preflight
        git = shutil.which("git")
        require(git is not None, "git required for frozen source identity")
        # These two read-only builtins suppress hooks, fsmonitor, paging and
        # submodule recursion; no unjoined Git child exists in a phase worker.
        git_prefix = [git, "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
                      "-c", "core.hooksPath=/dev/null", "--no-pager", "-C", str(REPO)]
        for name, arguments in (("head", ["rev-parse", "HEAD"]),
                                ("status", ["status", "--porcelain", "--untracked-files=no", "--ignore-submodules=all"])):
            directory = output / ("_preflight-git-" + name)
            run_owned([*git_prefix, *arguments], directory, {"phase": "preflight-git-" + name, "model_inference": False}, seconds=5, budget=preflight)
            raw = (directory / "stdout.log").read_bytes()
            require(raw.decode("ascii").strip() == plan["sourceCommit"] if name == "head" else not raw,
                    "consumer source differs or is dirty")
        run_owned(worker_command("preflight", plan_path, output, summary["planSha256"]), output / "_preflight-hash",
                  {"phase": "preflight-hash", "model_inference": False}, seconds=57, budget=preflight)
        before_deadline(preflight)
        summary["identitiesSha256"] = digest(output / "identities.json")
        summary["identitiesVerified"] = True
        # This deadline begins here, before any model case is marked/launched.
        cases = phase_budget("cases")
        summary["phaseBudgets"]["cases"] = cases
        for row, state in zip(rows, summary["cases"]):
            before_deadline(cases)
            started = time.monotonic()
            case = {"phase": "cases", "started": started,
                    "active_end": min(cases["active_end"], started + 180),
                    "total_end": min(cases["total_end"], started + 180)}
            state["budget"] = case
            state["status"] = "RUNNING"
            save()
            directory = output / row["id"]
            run_owned(row["argv"], directory, {"case": row["id"], "model": row["model"], "ownerCommit": OWNER,
                      "planSha256": summary["planSha256"], "identitiesSha256": summary["identitiesSha256"], "model_inference": True}, seconds=177, budget=case)
            run_owned(worker_command("grade", plan_path, output, summary["planSha256"], row["id"]), output / ("_grade-" + row["id"]),
                      {"phase": "grade", "case": row["id"], "model_inference": False}, seconds=7, budget=case)
            before_deadline(case)
            require(json.loads((directory / "grade.json").read_text())["passed"] is True, "grader did not accept")
            before_deadline(case)
            state["status"] = "PASS"
            save()
        before_deadline(cases)
    except BaseException as failure:
        error = failure
        for state in summary["cases"]:
            if state["status"] == "RUNNING": state["status"] = "FAIL"
        summary["failure"] = type(failure).__name__ + ": " + str(failure)
        if isinstance(failure, CleanupUnknown): summary["cleanup"] = "UNKNOWN"
    save()
    # Never create another worker after unknown cleanup or a user cancellation.
    if summary.get("identitiesVerified") and not isinstance(error, (CleanupUnknown, CaptureInterrupted)):
        post = phase_budget("post")
        summary["phaseBudgets"]["post"] = post
        save()
        try:
            run_owned(worker_command("post", plan_path, output, summary["planSha256"]), output / "_post",
                      {"phase": "post", "model_inference": False}, seconds=7, budget=post)
            before_deadline(post)
            summary = json.loads((output / "summary.json").read_text())
        except BaseException as failure:
            error = failure
            summary["failure"] = type(failure).__name__ + ": " + str(failure)
            summary["diagnosticPassed"] = False
            save()
    if error is not None:
        summary["diagnosticPassed"] = False
        save()
        raise error
    require(summary["diagnosticPassed"] is True, "diagnostic did not complete")
    return summary


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--plan", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--execute", action="store_true")
    mode.add_argument("--phase-worker", choices=("preflight", "grade", "post"))
    p.add_argument("--plan-sha256")
    p.add_argument("--case-id", choices=[route + "-" + model[0] for model in MODELS for route in ("native", "public")])
    a = p.parse_args()
    if a.phase_worker:
        require(a.plan_sha256 is not None and digest(a.plan) == a.plan_sha256, "frozen worker plan differs")
    plan = json.loads(a.plan.read_text())
    validate_plan(plan)
    try:
        if a.phase_worker:
            phase_worker(a.phase_worker, plan, a.out.resolve(), a.case_id)
        else:
            print(json.dumps(execute(plan, a.out.resolve()) if a.execute else commands(plan, a.out.resolve()), indent=2))
    except CaptureInterrupted as failure:
        raise SystemExit(128 + failure.signum)
