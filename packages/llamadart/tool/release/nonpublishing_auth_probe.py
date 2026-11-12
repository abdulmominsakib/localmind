#!/usr/bin/env python3
"""One disposable diagnostic ref; no publishing or general-purpose API command."""
import hashlib
import io
import json
import os
from pathlib import Path
import re
import secrets
import signal
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

REPO = "leehack/llamadart"
ROOT = "/repos/" + REPO
WORKFLOW = ".github/workflows/nonpublishing_release_auth_probe.yml"
WORKFLOW_API = ROOT + "/actions/workflows/nonpublishing_release_auth_probe.yml"
TAG = re.compile(r"ci-auth-probe-([1-9][0-9]*)-([0-9a-f]{32})\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")
LIMIT = 128 * 1024
API_LIMIT = 2 * 1024 * 1024
WRITE_PERMISSION_SETS = {
    frozenset((("contents", "write"),)): "contents-write",
    frozenset((("contents", "write"), ("workflows", "write"))): "contents-and-workflows-write",
}


class Failure(Exception):
    """Only fixed, nonsecret categories may cross the process boundary."""


def require(condition, category):
    if not condition:
        raise Failure(category)


def identifier(value):
    return isinstance(value, (str, int)) and not isinstance(value, bool) and bool(re.fullmatch(r"[1-9][0-9]*", str(value)))


def commit(value):
    return isinstance(value, str) and bool(SHA.fullmatch(value)) and value != "0" * 40


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, "duplicate-json-key")
        result[key] = value
    return result


def reject_constant(_value):
    raise Failure("invalid-json")


def decode(body):
    require(len(body) <= API_LIMIT, "response-too-large")
    try:
        result = json.loads(body, object_pairs_hook=pairs, parse_constant=reject_constant)
    except (ValueError, UnicodeError):
        raise Failure("invalid-json") from None
    require(isinstance(result, dict), "invalid-json-object")
    return result


def accepted_permissions_classification(value):
    # GitHub joins required permissions with commas and alternatives with semicolons.
    if value is None:
        return "missing"
    if (not isinstance(value, str) or not 1 <= len(value) <= 256
            or any(not (32 <= ord(char) <= 126 or char == "\t") for char in value)):
        return "malformed"
    alternatives = value.split(";")
    if not 1 <= len(alternatives) <= 2:
        return "malformed"
    parsed = []
    for alternative in alternatives:
        terms = alternative.split(",")
        if not 1 <= len(terms) <= 2:
            return "malformed"
        permissions = {}
        for term in terms:
            term = term.strip(" \t")
            if not re.fullmatch(r"[a-z][a-z0-9_]*=[a-z][a-z0-9_]*", term):
                return "malformed"
            name, level = term.split("=")
            if name in permissions:
                return "malformed"
            permissions[name] = level
        branch = frozenset(permissions.items())
        if branch not in WRITE_PERMISSION_SETS:
            return "unrecognized"
        if branch in parsed:
            return "malformed"
        parsed.append(branch)
    if len(parsed) == 2:
        return "documented-alternatives"
    return WRITE_PERMISSION_SETS[parsed[0]]


def negative_denial_predicates(status, headers, raw):
    body = None
    try:
        body = decode(raw)
    except Failure as error:
        # Only parser rejections are observations; cancellation must propagate.
        if type(error) is not Failure or str(error) not in {
                "response-too-large", "duplicate-json-key", "invalid-json", "invalid-json-object"}:
            raise
    remaining = headers.get("x-ratelimit-remaining")
    permissions = accepted_permissions_classification(headers.get("x-accepted-github-permissions"))
    return {
        "statusIs403": status == 403,
        "rateLimitRemainingPresent": "x-ratelimit-remaining" in headers,
        "rateLimitRemainingCanonicalDecimal": isinstance(remaining, str)
            and bool(re.fullmatch(r"0|[1-9][0-9]*", remaining)),
        "rateLimitRemainingIsNotZero": remaining != "0",
        "retryAfterAbsent": "retry-after" not in headers,
        "acceptedPermissionsPresent": "x-accepted-github-permissions" in headers,
        "acceptedPermissionsIsContentsWrite": headers.get("x-accepted-github-permissions") == "contents=write",
        "acceptedPermissionsClassification": permissions,
        "acceptedPermissionsRequireContentsWrite": permissions in {
            *WRITE_PERMISSION_SETS.values(), "documented-alternatives"},
        "bodyIsJsonObject": body is not None,
        "messageIsIntegrationDenial": body is not None and body.get("message") == "Resource not accessible by integration",
    }


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class HTTP:
    @staticmethod
    def exchange(request, limit=API_LIMIT):
        # Each request has a fresh opener: no cookie jar or inherited credentials.
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect).open(request, timeout=20) as response:
                return response.status, dict(response.headers.items()), response.read(limit + 1)
        except urllib.error.HTTPError as error:
            with error:
                return error.code, dict(error.headers.items()), error.read(limit + 1)
        except Exception:
            raise Failure("transport-error") from None

    def request(self, method, path, token, body=None):
        suffix = path.removeprefix(ROOT)
        allowed_read = re.fullmatch(
            r"/git/ref/(?:heads/main|tags/ci-auth-probe-[1-9][0-9]*-[0-9a-f]{32})"
            r"|/actions/runs/[1-9][0-9]*(?:/(?:jobs|artifacts)\?per_page=100)?"
            r"|/actions/artifacts/[1-9][0-9]*/zip"
            r"|/actions/workflows/nonpublishing_release_auth_probe\.yml(?:/runs\?event=push&head_sha=[0-9a-f]{40}&per_page=100)?", suffix)
        require(path.startswith(ROOT) and (
            (method == "GET" and allowed_read and body is None)
            or (method == "POST" and suffix == "/git/refs" and isinstance(body, dict)
                and set(body) == {"ref", "sha"} and body["ref"].startswith("refs/tags/")
                and TAG.fullmatch(body["ref"][10:]) and commit(body["sha"]))
            or (method == "DELETE" and re.fullmatch(r"/git/refs/tags/ci-auth-probe-[1-9][0-9]*-[0-9a-f]{32}", suffix)
                and body is None)), "invalid-api-operation")
        headers = {"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "llamadart-auth-probe"}
        data = None if body is None else json.dumps(body).encode()
        if data is not None:
            headers["Content-Type"] = "application/json"
        return self.exchange(urllib.request.Request("https://api.github.com" + path, data=data, headers=headers, method=method))

    def blob(self, location):
        validate_location(location)
        # Deliberately no API headers, Authorization, cookies or Referer.
        return self.exchange(urllib.request.Request(location, method="GET"), limit=LIMIT)


def validate_location(location):
    try:
        require(isinstance(location, str) and len(location) <= 8192
                and all(ord(char) > 32 for char in location), "artifact-location-rejected")
        url = urllib.parse.urlsplit(location)
        host = url.hostname or ""
        require(url.scheme == "https" and url.username is None and url.password is None
                and not url.fragment and url.port in (None, 443)
                and bool(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.blob\.core\.windows\.net", host)), "artifact-location-rejected")
    except (ValueError, TypeError):
        raise Failure("artifact-location-rejected") from None


def local_guard(c, mode):
    p = c["payload"]
    repository = p.get("repository", {})
    require(c["repo"] == REPO and c["owner"] == "leehack"
            and repository.get("full_name") == REPO
            and repository.get("owner", {}).get("login") == "leehack"
            and identifier(c["owner_id"]) and str(repository.get("owner", {}).get("id")) == c["owner_id"]
            and identifier(c["repo_id"]) and str(repository.get("id")) == c["repo_id"], "repository-guard")
    require(c["attempt"] == "1" and identifier(c["run_id"]) and identifier(c["actor_id"])
            and bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_\[\]-]{0,100}", c["actor"])), "run-guard")
    require(commit(c["sha"]) and c["sha"] == c["checkout_sha"], "checkout-guard")
    if mode == "sender":
        require(c["event"] == "workflow_dispatch" and c["ref"] == "refs/heads/main"
                and commit(c["expected_sha"]) and c["sha"] == c["expected_sha"], "sender-guard")
    else:
        require(mode == "receiver" and c["event"] == "push" and c["ref"].startswith("refs/tags/"), "receiver-event-guard")
        tag = c["ref"].removeprefix("refs/tags/")
        require(TAG.fullmatch(tag) and p.get("created") is True and p.get("deleted") is False
                and p.get("forced") is False and p.get("after") == c["sha"]
                and p.get("ref") == c["ref"], "receiver-push-guard")


class Journal:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=False)

    def save(self, name, value):
        with (self.directory / name).open("x", encoding="utf-8") as stream:
            json.dump(value, stream, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())


class Probe:
    def __init__(self, context, credential, journal, transport=None, clock=time.monotonic,
                 sleep=time.sleep, nonce=lambda: secrets.token_hex(16)):
        self.c, self.credential, self.journal = context, credential, journal
        self.http, self.clock, self.sleep, self.nonce = transport or HTTP(), clock, sleep, nonce
        self.steps = []

    def call(self, method, path, token, body=None):
        try:
            status, headers, raw = self.http.request(method, path, token, body)
        except Exception:
            raise Failure("transport-error") from None
        require(type(status) is int and len(raw) <= API_LIMIT, "invalid-response")
        self.steps.append({"method": method, "status": status})
        return status, {k.lower(): v for k, v in headers.items()}, raw

    def get(self, path):
        status, _, raw = self.call("GET", path, self.read)
        require(status == 200, "readback-status")
        return decode(raw)

    def main(self):
        data = self.get(ROOT + "/git/ref/heads/main")
        require(data.get("ref") == "refs/heads/main" and data.get("object", {}).get("type") == "commit"
                and data["object"].get("sha") == self.c["sha"], "main-drift")

    def authenticate(self, mode):
        local_guard(self.c, mode)
        self.read = self.credential("PROBE_READ_TOKEN")
        require(bool(self.read), "read-token-missing")
        # Repository identity comes from both the event context and authenticated run metadata.
        workflow = self.get(WORKFLOW_API)
        require(identifier(workflow.get("id")) and workflow.get("path") == WORKFLOW
                and workflow.get("state") == "active", "workflow-identity")
        self.workflow_id = workflow["id"]
        self.own_run = self.run(self.c["run_id"], self.c["event"],
                                "main" if mode == "sender" else self.c["ref"][10:])
        require(str(self.own_run["actor"]["id"]) == self.c["actor_id"]
                and self.own_run["actor"]["login"] == self.c["actor"], "actor-identity")
        self.main()

    def run(self, run_id, event, branch):
        require(identifier(run_id), "invalid-run-id")
        row = self.get(ROOT + "/actions/runs/" + str(run_id))
        repo = row.get("repository", {})
        require(str(row.get("id")) == str(run_id) and row.get("workflow_id") == self.workflow_id
                and row.get("path") == WORKFLOW and row.get("event") == event
                and type(row.get("run_attempt")) is int and row["run_attempt"] == 1
                and row.get("head_sha") == self.c["sha"]
                and row.get("head_branch") == branch and repo.get("full_name") == REPO
                and str(repo.get("id")) == self.c["repo_id"]
                and repo.get("owner", {}).get("login") == "leehack"
                and str(repo.get("owner", {}).get("id")) == self.c["owner_id"], "run-identity")
        actor = row.get("actor", {})
        require(identifier(actor.get("id")) and isinstance(actor.get("login"), str)
                and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_\[\]-]{0,100}", actor["login"]), "run-actor")
        for field in ("created_at", "updated_at"):
            require(isinstance(row.get(field), str) and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", row[field]), "run-time")
        return row

    def ref_path(self, tag, plural=False):
        require(TAG.fullmatch(tag) and TAG.fullmatch(tag)[1] == self.c["run_id"]
                and tag in self.owned_tags, "owned-ref-guard")
        return ROOT + ("/git/refs/tags/" if plural else "/git/ref/tags/") + tag

    def identity(self, value, tag):
        require(value.get("ref") == "refs/tags/" + tag and value.get("object", {}).get("type") == "commit"
                and value["object"].get("sha") == self.c["sha"], "ref-identity")

    def absent(self, tag):
        status, _, _ = self.call("GET", self.ref_path(tag), self.read)
        require(status == 404, "ref-not-absent")

    def inspect(self, tag):
        # Read-only handoff for ambiguous POST/DELETE; never turns ambiguity into success.
        try:
            status, _, raw = self.call("GET", self.ref_path(tag), self.read)
            if status == 404:
                return "absent"
            if status == 200:
                self.identity(decode(raw), tag)
                return "expected-commit"
        except Exception:
            pass
        return "unknown-or-moved"

    def create(self, tag, token):
        self.ref_path(tag)
        return self.call("POST", ROOT + "/git/refs", token,
                         {"ref": "refs/tags/" + tag, "sha": self.c["sha"]})

    def created(self, tag, raw):
        self.identity(decode(raw), tag)
        self.identity(self.get(self.ref_path(tag)), tag)

    def secret(self):
        token = self.credential("RELEASE_AUTOMATION_TOKEN")
        require(bool(token), "automation-token-missing")
        return token

    def cleanup(self, tag, token):
        # GET is a movement guard, NOT an atomic expected-SHA DELETE.
        self.identity(self.get(self.ref_path(tag)), tag)
        status = None
        try:
            status, _, _ = self.call("DELETE", self.ref_path(tag, True), token)
        finally:
            observed = self.inspect(tag)
            self.journal.save("cleanup.json", {"tag": tag, "status": status, "observed": observed,
                                               "atomicCompareAndSwap": False})
        require(status == 204 and observed == "absent", "cleanup-incomplete")

    def receipt(self, receiver, tag):
        rid = str(receiver["id"])
        jobs = self.get(ROOT + "/actions/runs/" + rid + "/jobs?per_page=100")
        require(jobs.get("total_count", 101) <= 100, "jobs-truncated")
        matched = [j for j in jobs.get("jobs", []) if j.get("name") == "Diagnostic push receipt"]
        require(len(matched) == 1 and matched[0].get("status") == "completed"
                and matched[0].get("conclusion") == "success" and matched[0].get("run_id") == receiver["id"], "receiver-job")
        artifacts = self.get(ROOT + "/actions/runs/" + rid + "/artifacts?per_page=100")
        require(artifacts.get("total_count", 101) <= 100, "artifacts-truncated")
        name = "auth-probe-receiver-" + rid + "-attempt-1"
        matches = [a for a in artifacts.get("artifacts", []) if a.get("name") == name]
        require(len(matches) == 1, "receiver-artifact")
        artifact = matches[0]
        binding = artifact.get("workflow_run", {})
        require(identifier(artifact.get("id")) and artifact.get("expired") is False
                and type(artifact.get("size_in_bytes")) is int and 0 < artifact["size_in_bytes"] <= LIMIT
                and isinstance(artifact.get("digest"), str) and re.fullmatch(r"sha256:[0-9a-f]{64}", artifact["digest"])
                and binding.get("id") == receiver["id"] and binding.get("head_sha") == self.c["sha"]
                and binding.get("head_branch") == tag, "artifact-identity")
        status, headers, _ = self.call("GET", ROOT + "/actions/artifacts/" + str(artifact["id"]) + "/zip", self.read)
        require(status == 302, "artifact-redirect-status")
        location = headers.get("location")
        validate_location(location)
        try:
            status, _, body = self.http.blob(location)
            require(status == 200 and len(body) == artifact["size_in_bytes"] and len(body) <= LIMIT
                    and "sha256:" + hashlib.sha256(body).hexdigest() == artifact["digest"], "artifact-digest")
            with zipfile.ZipFile(io.BytesIO(body)) as archive:
                members = archive.infolist()
                require(len(members) == 1, "receipt-zip-layout")
                member = members[0]
                require(member.filename == member.orig_filename == "receiver.json" and not member.is_dir()
                        and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG)
                        and 0 < member.file_size <= 64 * 1024, "receipt-zip-layout")
                data = archive.read(member)
                require(len(data) == member.file_size and len(data) <= 64 * 1024, "receipt-expanded-size")
                receipt = decode(data)
        except Failure:
            raise
        except Exception:
            raise Failure("artifact-download-or-zip-error") from None
        expected = self.receiver_receipt(receiver, self.own_run, tag)
        require(json.dumps(receipt, sort_keys=True) == json.dumps(expected, sort_keys=True), "receipt-binding")
        self.journal.save("observed-receiver.json", receipt)
        return rid

    def receiver_receipt(self, receiver, sender, tag):
        match = TAG.fullmatch(tag)
        def actor(row):
            return {"id": str(row["actor"]["id"]), "login": row["actor"]["login"]}
        return {"repository": REPO, "sourceSha": self.c["sha"], "tag": tag, "nonce": match[2],
                "senderRunId": str(sender["id"]), "senderAttempt": 1,
                "receiverRunId": str(receiver["id"]), "receiverAttempt": 1,
                "workflowId": self.workflow_id, "workflowPath": WORKFLOW,
                "senderActor": actor(sender), "receiverActor": actor(receiver),
                "senderCreatedAt": sender["created_at"], "receiverCreatedAt": receiver["created_at"],
                "created": True, "deleted": False, "forced": False,
                "refCommitSha": self.c["sha"], "observedMainSha": self.c["sha"]}

    def wait_receiver(self, tag):
        deadline = self.clock() + 300
        while self.clock() < deadline:
            data = self.get(WORKFLOW_API + "/runs?event=push&head_sha=" + self.c["sha"] + "&per_page=100")
            require(data.get("total_count", 101) <= 100, "runs-truncated")
            matches = [r for r in data.get("workflow_runs", []) if r.get("head_branch") == tag
                       or r.get("display_title") == "auth-probe " + tag]
            require(len(matches) <= 1, "duplicate-receiver")
            if matches:
                candidate = matches[0]
                receiver = self.run(candidate.get("id"), "push", tag)
                require(receiver.get("display_title") == "auth-probe " + tag, "receiver-title")
                if receiver.get("status") == "completed":
                    require(receiver.get("conclusion") == "success", "receiver-failed")
                    return self.receipt(receiver, tag)
            self.sleep(10)
        raise Failure("receiver-timeout")

    def sender(self):
        self.authenticate("sender")
        require(self.own_run.get("status") == "in_progress", "sender-state")
        nonces = [self.nonce(), self.nonce()]
        require(all(isinstance(n, str) and re.fullmatch(r"[0-9a-f]{32}", n) for n in nonces)
                and nonces[0] != nonces[1], "nonce-guard")
        negative, positive = ["ci-auth-probe-" + self.c["run_id"] + "-" + n for n in nonces]
        self.owned_tags = (negative, positive)
        self.journal.save("intent.json", {"repository": REPO, "sourceSha": self.c["sha"],
            "runId": self.c["run_id"], "attempt": 1, "actor": self.c["actor"], "actorId": self.c["actor_id"],
            "negativeTag": negative, "positiveTag": positive, "createdAt": self.own_run["created_at"],
            "workflowId": self.workflow_id, "workflowPath": WORKFLOW, "sourceHashes": self.c["source_hashes"]})
        self.absent(negative)
        self.absent(positive)
        self.journal.save("negative-create-intent.json", {"tag": negative, "sha": self.c["sha"]})
        try:
            status, headers, raw = self.create(negative, self.read)
            if status == 201:
                self.created(negative, raw)
                self.cleanup(negative, self.secret())
                raise Failure("negative-unexpectedly-created")
            predicates = negative_denial_predicates(status, headers, raw)
            try:
                require(status == 403 and headers.get("x-ratelimit-remaining") != "0"
                        and "retry-after" not in headers
                        and predicates["acceptedPermissionsRequireContentsWrite"]
                        and decode(raw).get("message") == "Resource not accessible by integration", "negative-not-write-denial")
            except Exception:
                try:
                    self.journal.save("negative-denial.json", predicates)
                except BaseException:
                    # Keep the denial failure and still inspect the owned ref.
                    pass
                raise
            self.journal.save("negative-denial.json", predicates)
            self.absent(negative)
        except BaseException:
            self.journal.save("negative-inspection.json", {"tag": negative, "observed": self.inspect(negative)})
            raise
        self.absent(positive)
        self.main()
        token = self.secret()
        self.journal.save("positive-create-intent.json", {"tag": positive, "sha": self.c["sha"]})
        try:
            status, _, raw = self.create(positive, token)
            require(status == 201, "positive-create-status")
            self.created(positive, raw)
        except BaseException:
            self.journal.save("positive-inspection.json", {"tag": positive, "observed": self.inspect(positive)})
            raise
        problem = None
        try:
            receiver_id = self.wait_receiver(positive)
        except Failure as error:
            problem = error
        except BaseException:
            problem = Failure("receiver-observation-interrupted")
        if problem:
            self.journal.save("receiver-failure.json", {"category": str(problem)})
        try:
            self.cleanup(positive, token)
        except BaseException as error:
            category = str(error) if type(error) is Failure else "cleanup-interrupted-or-unexpected"
            self.journal.save("cleanup-failure.json", {"category": category})
            if problem:
                raise Failure("receiver-and-cleanup-failed") from None
            raise
        if problem:
            raise problem
        return {"passed": True, "negativeWriteDenied": True, "positiveCreated": True,
                "receiverRunId": receiver_id, "cleanupVerified": True}

    def receiver(self):
        self.authenticate("receiver")
        tag = self.c["ref"][10:]
        sender_id = TAG.fullmatch(tag)[1]
        require(sender_id != self.c["run_id"], "receiver-parent")
        sender = self.run(sender_id, "workflow_dispatch", "main")
        require(sender.get("status") == "in_progress", "receiver-parent-state")
        # ref_path is sender-owned; receivers may only read this exact event ref.
        self.identity(self.get(ROOT + "/git/ref/tags/" + tag), tag)
        receipt = self.receiver_receipt(self.own_run, sender, tag)
        self.journal.save("receiver.json", receipt)
        return {"received": True}


def context(env, payload, checkout_sha, source_hashes):
    names = {"repo": "GITHUB_REPOSITORY", "owner": "GITHUB_REPOSITORY_OWNER", "owner_id": "PROBE_OWNER_ID",
             "repo_id": "PROBE_REPOSITORY_ID", "event": "GITHUB_EVENT_NAME", "ref": "GITHUB_REF", "sha": "GITHUB_SHA",
             "attempt": "GITHUB_RUN_ATTEMPT", "run_id": "GITHUB_RUN_ID", "actor": "GITHUB_ACTOR", "actor_id": "GITHUB_ACTOR_ID",
             "expected_sha": "EXPECTED_SHA"}
    return {**{key: env.get(name, "") for key, name in names.items()}, "payload": payload,
            "checkout_sha": checkout_sha, "source_hashes": source_hashes}


def interrupted(_signal, _frame):
    raise Failure("cancelled")


def main():
    journal = None
    probe = None
    try:
        require(len(sys.argv) == 2 and sys.argv[1] in ("sender", "receiver"), "invalid-mode")
        mode = sys.argv[1]
        journal = Journal(Path(os.environ["RUNNER_TEMP"]) / "auth-probe")
        payload = decode(Path(os.environ["GITHUB_EVENT_PATH"]).read_bytes())
        sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
        hashes = {name: hashlib.sha256(Path(name).read_bytes()).hexdigest()
                  for name in (WORKFLOW, "tool/release/nonpublishing_auth_probe.py")}
        c = context(os.environ, payload, sha, hashes)
        local_guard(c, mode)
        probe = Probe(c, os.environ.get, journal)
        signal.signal(signal.SIGTERM, interrupted)
        result = probe.sender() if mode == "sender" else probe.receiver()
        if mode == "sender":
            journal.save("result.json", {**result, "steps": probe.steps})
        print("Diagnostic auth probe completed; inspect the retained receipt and its limits.")
        return 0
    except BaseException as error:
        category = str(error) if type(error) is Failure else "unexpected-or-cancelled"
        if journal:
            journal.save("failure.json", {"category": category, "steps": probe.steps if probe else []})
        print("Diagnostic auth probe failed: " + category, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
