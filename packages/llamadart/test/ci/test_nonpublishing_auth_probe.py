"""Exercise the real probe with fake HTTP only; never read real credentials."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import signal
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tool/release/nonpublishing_auth_probe.py"
spec = importlib.util.spec_from_file_location("auth_probe", SOURCE)
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
SHA = "a" * 40
READ = "READ_SECRET_NOT_FOR_RECEIPTS"
SECRET = "PAT_SECRET_NOT_FOR_RECEIPTS"
SAS = "SIGNED_SECRET_NOT_FOR_RECEIPTS"
LOCATION = "https://productionresultssa0.blob.core.windows.net/artifact?sig=" + SAS
NEGATIVE = "ci-auth-probe-100-" + "1" * 32
POSITIVE = "ci-auth-probe-100-" + "2" * 32


def repository():
    return {"id": 10, "full_name": p.REPO, "owner": {"id": 20, "login": "leehack"}}


def context(receiver=False):
    ref = "refs/tags/" + POSITIVE if receiver else "refs/heads/main"
    return {"repo": p.REPO, "owner": "leehack", "owner_id": "20", "repo_id": "10",
            "event": "push" if receiver else "workflow_dispatch", "ref": ref, "sha": SHA,
            "attempt": "1", "run_id": "200" if receiver else "100", "actor": "leehack", "actor_id": "20",
            "expected_sha": SHA, "checkout_sha": SHA, "source_hashes": {"workflow": "b" * 64},
            "payload": {"repository": repository(), "ref": ref, "after": SHA,
                        "created": True, "deleted": False, "forced": False}}


def run(run_id, event, branch, status):
    return {"id": run_id, "workflow_id": 30, "path": p.WORKFLOW, "event": event,
            "head_branch": branch, "head_sha": SHA, "run_attempt": 1, "repository": repository(),
            "actor": {"id": 20, "login": "leehack", "ignoredUntrustedField": SECRET},
            "created_at": "2026-11-05T20:00:00Z", "updated_at": "2026-11-05T20:01:00Z",
            "status": status, "conclusion": "success" if status == "completed" else None,
            "display_title": "auth-probe " + branch}


class FakeHTTP:
    def __init__(self):
        self.calls = []
        self.refs = {}
        self.options = {}
        self.sender_run = run(100, "workflow_dispatch", "main", "in_progress")
        self.receiver_run = run(200, "push", POSITIVE, "completed")
        self.main_reads = 0
        self.positive_reads = 0

    def response(self, status, value=None, headers=None):
        return status, headers or {}, b"" if value is None else json.dumps(value).encode()

    def ref(self, tag):
        return {"ref": "refs/tags/" + tag, "object": {"type": "commit", "sha": self.refs[tag]}}

    def request(self, method, path, token, body=None):
        self.calls.append((method, path, token, body))
        suffix = path.removeprefix(p.ROOT)
        o = self.options
        if method == "POST":
            tag = body["ref"][10:]
            if tag == NEGATIVE and not o.get("negative_created"):
                if o.get("negative_timeout"):
                    raise TimeoutError(SECRET)
                headers = {"x-accepted-github-permissions": "contents=write", "x-ratelimit-remaining": "100"}
                headers.update(o.get("negative_headers", {}))
                headers = {key: value for key, value in headers.items() if value is not None}
                value = o.get("negative_body", {"message": "Resource not accessible by integration"})
                if o.get("negative_raw"):
                    raw = o["negative_raw"]
                    return o.get("negative_status", 403), headers, raw if isinstance(raw, bytes) else b'{"message":'
                return self.response(o.get("negative_status", 403), value, headers)
            self.refs[tag] = SHA
            if o.get("positive_timeout") and tag == POSITIVE:
                raise TimeoutError(SECRET)
            value = self.ref(tag)
            if tag == POSITIVE:
                if "created_ref" in o:
                    value["ref"] = o["created_ref"]
                value["object"].update(o.get("created_object", {}))
            if o.get("malformed_create"):
                return 201, {}, ("bad-json-" + SECRET).encode()
            return self.response(o.get("positive_status", 201), value)
        if method == "DELETE":
            tag = suffix.removeprefix("/git/refs/tags/")
            if o.get("delete_timeout"):
                if o.get("delete_happened"):
                    self.refs.pop(tag, None)
                raise TimeoutError(SECRET)
            status = o.get("delete_status", 204)
            if status == 204 and not o.get("delete_still_present"):
                self.refs.pop(tag, None)
            return self.response(status, {"message": SECRET})
        if suffix == "/actions/workflows/nonpublishing_release_auth_probe.yml":
            return self.response(200, {"id": 30, "path": p.WORKFLOW, "state": "active"})
        if suffix == "/git/ref/heads/main":
            self.main_reads += 1
            return self.response(200, {"ref": "refs/heads/main", "object": {"type": "commit",
                "sha": "b" * 40 if o.get("main_drift") and self.main_reads > 1 else SHA}})
        if suffix.startswith("/git/ref/tags/"):
            tag = suffix.removeprefix("/git/ref/tags/")
            if tag not in self.refs:
                return self.response(404)
            if tag == POSITIVE:
                self.positive_reads += 1
                if o.get("moved_ref") and self.positive_reads >= 2:
                    self.refs[tag] = "c" * 40
                if o.get("wrong_readback"):
                    return self.response(200, {"ref": "refs/tags/" + tag, "object": {"type": "tag", "sha": SHA}})
            return self.response(200, self.ref(tag))
        if suffix == "/actions/runs/100":
            return self.response(200, self.sender_run)
        if suffix == "/actions/runs/200":
            return self.response(200, self.receiver_run)
        if suffix.startswith("/actions/workflows/nonpublishing_release_auth_probe.yml/runs?"):
            if o.get("interrupt"):
                raise KeyboardInterrupt()
            runs = [] if o.get("receiver_timeout") else [self.receiver_run]
            if o.get("duplicate_receiver"):
                runs *= 2
            return self.response(200, {"total_count": len(runs), "workflow_runs": runs})
        if suffix == "/actions/runs/200/jobs?per_page=100":
            return self.response(200, {"total_count": 1, "jobs": [{"name": "Diagnostic push receipt",
                "status": "completed", "conclusion": o.get("job_conclusion", "success"), "run_id": 200}]})
        if suffix == "/actions/runs/200/artifacts?per_page=100":
            value = self.probe.receiver_receipt(self.receiver_run, self.sender_run, POSITIVE)
            if o.get("receipt_wrong_nonce"):
                value["nonce"] = "3" * 32
            if o.get("receipt_wrong_type"):
                value["senderAttempt"] = True
            data = json.dumps(value).encode()
            if o.get("duplicate_json"):
                data = b'{"x":1,"x":2}'
            if o.get("oversized_receipt"):
                data = b"x" * (64 * 1024 + 1)
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                member = zipfile.ZipInfo(o.get("member_name", "receiver.json"))
                member.external_attr = o.get("member_mode", stat.S_IFREG) << 16
                archive.writestr(member, data)
                if o.get("duplicate_member"):
                    archive.writestr("second.json", b"{}")
            self.archive = buffer.getvalue()
            artifact = {"id": 40, "name": "auth-probe-receiver-200-attempt-1", "expired": False,
                "size_in_bytes": len(self.archive), "digest": "sha256:" + hashlib.sha256(self.archive).hexdigest(),
                "workflow_run": {"id": 200, "head_sha": SHA, "head_branch": POSITIVE}}
            artifact.update(o.get("artifact", {}))
            return self.response(200, {"total_count": 1, "artifacts": [artifact]})
        if suffix == "/actions/artifacts/40/zip":
            return self.response(o.get("artifact_status", 302), headers={"Location": o.get("location", LOCATION)})
        raise AssertionError("unplanned fake endpoint")

    def blob(self, location):
        self.calls.append(("BLOB", location, None, None))
        if self.options.get("blob_error"):
            raise RuntimeError(location)
        return self.options.get("blob_status", 200), {}, self.archive + (b"tampered" if self.options.get("tamper") else b"")


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.http = FakeHTTP()
        self.credentials = []
        self.now = 0
        self.sequence = iter(("1" * 32, "2" * 32))
        self.probe = self.make(context())

    def credential(self, name):
        self.credentials.append(name)
        return {"PROBE_READ_TOKEN": READ, "RELEASE_AUTOMATION_TOKEN": SECRET}[name]

    def sleep(self, amount):
        self.now += amount

    def make(self, c):
        directory = self.root / str(len(list(self.root.iterdir())))
        probe = p.Probe(c, self.credential, p.Journal(directory), self.http,
                        clock=lambda: self.now, sleep=self.sleep, nonce=lambda: next(self.sequence))
        self.http.probe = probe
        return probe

    def fail(self, pattern=None):
        with self.assertRaises(p.Failure) as error:
            self.probe.sender()
        if pattern:
            self.assertRegex(str(error.exception), pattern)
        return str(error.exception)

    def mutations(self):
        return [call for call in self.http.calls if call[0] in ("POST", "DELETE")]

    def test_complete_sender_requires_both_tokens_actual_receipt_and_exact_cleanup(self):
        result = self.probe.sender()
        self.assertTrue(result["passed"])
        self.assertEqual(["POST", "POST", "DELETE"], [c[0] for c in self.mutations()])
        self.assertEqual([READ, SECRET, SECRET], [c[2] for c in self.mutations()])
        self.assertEqual({}, self.http.refs)
        receipt = json.loads((self.probe.journal.directory / "observed-receiver.json").read_text())
        self.assertEqual("200", receipt["receiverRunId"])
        self.assertEqual("100", receipt["senderRunId"])
        self.assertEqual("2" * 32, receipt["nonce"])
        for path in self.probe.journal.directory.iterdir():
            for secret in (READ, SECRET, SAS, LOCATION):
                self.assertNotIn(secret, path.read_text())
        artifact_hop = [c for c in self.http.calls if c[1].endswith("/40/zip")]
        self.assertEqual(READ, artifact_hop[0][2])

    def test_all_local_guards_fail_before_credential_access_or_network(self):
        changes = {"repo": "elsewhere/llamadart", "owner": "elsewhere", "owner_id": "0",
                   "repo_id": "0", "event": "push", "ref": "refs/heads/other", "sha": "0" * 40,
                   "checkout_sha": "b" * 40, "expected_sha": "b" * 40, "attempt": "2",
                   "run_id": "../100", "actor_id": "0", "actor": "bad actor"}
        for field, value in changes.items():
            with self.subTest(field=field):
                c = context()
                c[field] = value
                probe = self.make(c)
                with self.assertRaises(p.Failure):
                    probe.sender()
                self.assertEqual([], self.credentials)
                self.assertEqual([], self.http.calls)

    def test_invalid_negative_responses_cannot_reach_pat_or_positive(self):
        scenarios = [{"negative_status": status} for status in (200, 401, 404, 422, 429, 500)]
        scenarios += [{"negative_timeout": True}, {"negative_headers": {"x-ratelimit-remaining": "0"}},
                      {"negative_headers": {"retry-after": "1"}},
                      {"negative_headers": {"x-accepted-github-permissions": ""}},
                      {"negative_body": {"message": "policy denial " + SECRET}},
                      {"negative_body": {"message": "secondary rate limit"}}, {"negative_raw": True}]
        for options in scenarios:
            with self.subTest(options=options):
                self.setUp()
                self.http.options = options
                self.fail()
                self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)
                self.assertEqual(1, len(self.mutations()))

    def denial_receipt(self):
        receipt = json.loads((self.probe.journal.directory / "negative-denial.json").read_text())
        self.assertIn(receipt["acceptedPermissionsClassification"], {
            "missing", "malformed", "unrecognized", "contents-write",
            "contents-and-workflows-write", "documented-alternatives"})
        self.assertTrue(all(type(value) is bool for key, value in receipt.items()
                            if key != "acceptedPermissionsClassification"))
        return receipt

    def test_documented_permission_header_forms_complete_sender(self):
        cases = [
            ("literal", "contents=write", "contents-write"),
            ("and", "contents=write,workflows=write", "contents-and-workflows-write"),
            ("and-reordered", "workflows=write,contents=write", "contents-and-workflows-write"),
            ("alternatives", "contents=write; contents=write,workflows=write", "documented-alternatives"),
            ("alternatives-inner-reordered", "contents=write;workflows=write,contents=write", "documented-alternatives"),
            ("alternatives-outer-reordered", "contents=write,workflows=write;contents=write", "documented-alternatives"),
            ("alternatives-reordered", "workflows=write,contents=write;contents=write", "documented-alternatives"),
            ("literal-whitespace", "\t contents=write \t", "contents-write"),
            ("whitespace", "\t contents=write , workflows=write \t", "contents-and-workflows-write"),
        ]
        for name, value, classification in cases:
            with self.subTest(case=name):
                self.setUp()
                self.http.options["negative_headers"] = {"x-accepted-github-permissions": value}
                result = self.probe.sender()
                self.assertTrue(result["passed"])
                receipt = self.denial_receipt()
                self.assertEqual(classification, receipt["acceptedPermissionsClassification"])
                self.assertIs(True, receipt["acceptedPermissionsRequireContentsWrite"])
                self.assertEqual(value == "contents=write", receipt["acceptedPermissionsIsContentsWrite"])
                self.assertEqual(["POST", "POST", "DELETE"], [call[0] for call in self.mutations()])
                self.assertEqual({}, self.http.refs)

    def test_unknown_or_malformed_permission_header_stops_before_positive(self):
        cases = [
            ("missing", None, "missing"), ("wrong-type", [], "malformed"),
            ("empty", "", "malformed"), ("read-only", "contents=read", "unrecognized"),
            ("workflows-only", "workflows=write", "unrecognized"),
            ("unknown-conjunct", "contents=write,metadata=read", "unrecognized"),
            ("unknown-alternative", "contents=write;issues=write", "unrecognized"),
            ("unknown-first-alternative", "issues=write;contents=write", "unrecognized"),
            ("weaker-alternative", "contents=write;contents=read", "unrecognized"),
            ("unknown-level", "contents=admin", "unrecognized"),
            ("duplicate-term", "contents=write,contents=write", "malformed"),
            ("conflicting-term", "contents=write,contents=read", "malformed"),
            ("duplicate-alternative", "contents=write;contents=write", "malformed"),
            ("reordered-duplicate-alternative",
             "contents=write,workflows=write;workflows=write,contents=write", "malformed"),
            ("leading-delimiter", ";contents=write", "malformed"),
            ("trailing-delimiter", "contents=write;", "malformed"),
            ("empty-term", "contents=write,", "malformed"),
            ("extra-equals", "contents==write", "malformed"),
            ("quoted", '"contents=write"', "malformed"),
            ("newline", "contents=write\n", "malformed"),
            ("crlf", "contents=write\r\nX: injected", "malformed"),
            ("nul", "contents=write\x00", "malformed"),
            ("del", "contents=write\x7f", "malformed"),
            ("non-ascii", "contents=wr\u0131te", "malformed"),
            ("case-change", "Contents=write", "malformed"),
            ("internal-whitespace", "contents =write", "malformed"),
            ("too-many-alternatives", "contents=write;contents=write,workflows=write;contents=write", "malformed"),
            ("too-many-terms", "contents=write,workflows=write,issues=write", "malformed"),
            ("oversized", "x" * 257, "malformed"),
            ("secret-url-injection", "contents=write," + READ + SECRET + SAS + LOCATION, "malformed"),
        ]
        for name, value, classification in cases:
            with self.subTest(case=name):
                self.setUp()
                self.http.options["negative_headers"] = {"x-accepted-github-permissions": value}
                self.assertEqual("negative-not-write-denial", self.fail())
                receipt = self.denial_receipt()
                self.assertEqual(classification, receipt["acceptedPermissionsClassification"])
                self.assertIs(False, receipt["acceptedPermissionsRequireContentsWrite"])
                self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)
                self.assertEqual([("POST", p.ROOT + "/git/refs", READ,
                                   {"ref": "refs/tags/" + NEGATIVE, "sha": SHA})], self.mutations())
                self.assertEqual("absent", json.loads((self.probe.journal.directory /
                    "negative-inspection.json").read_text())["observed"])
                self.assertFalse((self.probe.journal.directory / "positive-create-intent.json").exists())
                evidence = "".join(path.read_text() for path in self.probe.journal.directory.iterdir())
                for secret in (READ, SECRET, SAS, LOCATION):
                    self.assertNotIn(secret, evidence)

    def test_denial_guard_consumes_the_same_permission_parse_as_telemetry(self):
        with patch.object(p, "accepted_permissions_classification", return_value="unrecognized") as parser:
            self.assertEqual("negative-not-write-denial", self.fail())
        parser.assert_called_once_with("contents=write")
        receipt = self.denial_receipt()
        self.assertIs(True, receipt["acceptedPermissionsIsContentsWrite"])
        self.assertEqual("unrecognized", receipt["acceptedPermissionsClassification"])
        self.assertIs(False, receipt["acceptedPermissionsRequireContentsWrite"])
        self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)
        self.assertEqual(1, len(self.mutations()))

    def test_negative_denial_receipt_records_only_fixed_predicates_and_classification(self):
        self.probe.sender()
        self.assertEqual({
            "statusIs403": True,
            "rateLimitRemainingPresent": True,
            "rateLimitRemainingCanonicalDecimal": True,
            "rateLimitRemainingIsNotZero": True,
            "retryAfterAbsent": True,
            "acceptedPermissionsPresent": True,
            "acceptedPermissionsIsContentsWrite": True,
            "acceptedPermissionsClassification": "contents-write",
            "acceptedPermissionsRequireContentsWrite": True,
            "bodyIsJsonObject": True,
            "messageIsIntegrationDenial": True,
        }, self.denial_receipt())

    def test_negative_denial_receipt_identifies_each_failed_predicate_without_retry(self):
        scenarios = [
            ({"negative_status": 429}, "statusIs403", "negative-not-write-denial"),
            ({"negative_headers": {"x-ratelimit-remaining": "0"}},
             "rateLimitRemainingIsNotZero", "negative-not-write-denial"),
            ({"negative_headers": {"retry-after": ""}}, "retryAfterAbsent", "negative-not-write-denial"),
            ({"negative_headers": {"x-accepted-github-permissions": None}},
             "acceptedPermissionsPresent", "negative-not-write-denial"),
            ({"negative_headers": {"x-accepted-github-permissions": "contents=write,metadata=read"}},
             "acceptedPermissionsIsContentsWrite", "negative-not-write-denial"),
            ({"negative_body": {"message": "secondary rate limit"}},
             "messageIsIntegrationDenial", "negative-not-write-denial"),
            ({"negative_body": ["Resource not accessible by integration"]},
             "bodyIsJsonObject", "invalid-json-object"),
            ({"negative_raw": True}, "bodyIsJsonObject", "invalid-json"),
            ({"negative_raw": b'{"message":"x","message":"y"}'},
             "bodyIsJsonObject", "duplicate-json-key"),
            ({"negative_status": 429, "negative_raw": True},
             "bodyIsJsonObject", "negative-not-write-denial"),
            ({"negative_raw": b'\xff'}, "bodyIsJsonObject", "invalid-json"),
        ]
        for options, predicate, category in scenarios:
            with self.subTest(options=options):
                self.setUp()
                self.http.options = options
                self.assertEqual(category, self.fail())
                receipt = self.denial_receipt()
                self.assertIs(False, receipt[predicate])
                self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)
                self.assertEqual([("POST", p.ROOT + "/git/refs", READ,
                                   {"ref": "refs/tags/" + NEGATIVE, "sha": SHA})], self.mutations())
                self.assertEqual("absent", json.loads((self.probe.journal.directory /
                    "negative-inspection.json").read_text())["observed"])
                self.assertFalse((self.probe.journal.directory / "positive-create-intent.json").exists())

    def test_negative_denial_telemetry_does_not_change_existing_rate_limit_criteria(self):
        for remaining in (None, "", "unknown", "00", "-1", " 100", "100 " + SECRET):
            with self.subTest(remaining=remaining):
                self.setUp()
                self.http.options["negative_headers"] = {"x-ratelimit-remaining": remaining}
                self.probe.sender()
                receipt = self.denial_receipt()
                self.assertEqual(remaining is not None, receipt["rateLimitRemainingPresent"])
                self.assertIs(False, receipt["rateLimitRemainingCanonicalDecimal"])
                self.assertIs(True, receipt["rateLimitRemainingIsNotZero"])

    def test_negative_denial_receipt_never_echoes_headers_body_secrets_or_urls(self):
        self.http.options = {
            "negative_headers": {"x-ratelimit-remaining": READ + LOCATION,
                "retry-after": SECRET + LOCATION, "x-accepted-github-permissions": SAS + LOCATION,
                "location": LOCATION, SECRET: READ},
            "negative_body": {"message": READ + SECRET + SAS + LOCATION, "url": LOCATION},
        }
        self.assertEqual("negative-not-write-denial", self.fail())
        evidence = "".join(path.read_text() for path in self.probe.journal.directory.iterdir())
        for value in (READ, SECRET, SAS, LOCATION, "https://", "blob.core.windows.net"):
            self.assertNotIn(value, evidence)
        self.denial_receipt()

    def test_accepted_denial_never_retains_unrelated_response_fields(self):
        self.http.options = {
            "negative_headers": {"location": LOCATION, SECRET: READ},
            "negative_body": {"message": "Resource not accessible by integration",
                              "documentation_url": LOCATION, "untrusted": SECRET},
        }
        self.probe.sender()
        self.assertTrue(all(self.denial_receipt().values()))
        evidence = "".join(path.read_text() for path in self.probe.journal.directory.iterdir())
        for value in (READ, SECRET, SAS, LOCATION):
            self.assertNotIn(value, evidence)

    def assert_stopped_at_negative(self):
        self.assertTrue((self.probe.journal.directory / "negative-inspection.json").is_file())
        self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)
        self.assertEqual(1, len(self.mutations()))
        self.assertEqual(("POST", p.ROOT + "/git/refs", READ,
                          {"ref": "refs/tags/" + NEGATIVE, "sha": SHA}), self.mutations()[0])
        self.assertFalse((self.probe.journal.directory / "positive-create-intent.json").exists())
        self.assertFalse((self.probe.journal.directory / "negative-denial.json").exists())

    def test_sigterm_during_denial_observation_cannot_reach_positive_operations(self):
        previous = signal.signal(signal.SIGTERM, p.interrupted)
        self.addCleanup(signal.signal, signal.SIGTERM, previous)
        original = p.decode
        signals = []
        def decode(raw):
            if raw == b'{"message": "Resource not accessible by integration"}' and not signals:
                signals.append(True)
                signal.raise_signal(signal.SIGTERM)
            return original(raw)
        with patch.object(p, "decode", side_effect=decode):
            try:
                self.probe.sender()
            except p.Failure as error:
                self.assertEqual("cancelled", str(error))
            else:
                raise AssertionError("SIGTERM cancellation was swallowed")
        self.assertEqual([True], signals)
        self.assert_stopped_at_negative()

    def test_sigterm_during_permission_parse_cannot_reach_positive_operations(self):
        previous = signal.signal(signal.SIGTERM, p.interrupted)
        self.addCleanup(signal.signal, signal.SIGTERM, previous)
        original = p.accepted_permissions_classification
        signals = []
        def classify(value):
            signals.append(True)
            signal.raise_signal(signal.SIGTERM)
            return original(value)
        with patch.object(p, "accepted_permissions_classification", side_effect=classify):
            self.assertEqual("cancelled", self.fail())
        self.assertEqual([True], signals)
        self.assert_stopped_at_negative()

    def test_operational_permission_parse_failure_stops_before_positive(self):
        with patch.object(p, "accepted_permissions_classification", side_effect=OSError(SECRET + LOCATION)), \
                self.assertRaises(OSError):
            self.probe.sender()
        self.assert_stopped_at_negative()

    def test_denial_observation_propagates_operational_and_unexpected_decode_failures(self):
        class OperationalFailure(p.Failure):
            pass
        for problem in (p.Failure("cancelled"), p.Failure("transport-error"),
                        OperationalFailure("invalid-json"), RecursionError(SECRET + LOCATION),
                        OSError(SECRET + LOCATION), ValueError(SECRET + LOCATION)):
            with self.subTest(problem=type(problem)):
                self.setUp()
                original = p.decode
                failures = []
                def decode(raw):
                    if raw == b'{"message": "Resource not accessible by integration"}' and not failures:
                        failures.append(True)
                        raise problem
                    return original(raw)
                with patch.object(p, "decode", side_effect=decode):
                    try:
                        self.probe.sender()
                    except BaseException as error:
                        self.assertIs(problem, error)
                    else:
                        raise AssertionError("Operational decode failure was swallowed")
                self.assertEqual([True], failures)
                self.assert_stopped_at_negative()
                evidence = "".join(path.read_text() for path in self.probe.journal.directory.iterdir())
                for value in (READ, SECRET, SAS, LOCATION):
                    self.assertNotIn(value, evidence)

    def test_denial_journal_error_keeps_original_failure_and_negative_inspection(self):
        for error in (OSError, KeyboardInterrupt, p.Failure):
            with self.subTest(error=error):
                self.setUp()
                original = self.probe.journal.save
                def save(name, value):
                    if name == "negative-denial.json":
                        raise error(SECRET + LOCATION)
                    original(name, value)
                self.probe.journal.save = save
                self.http.options["negative_raw"] = True
                self.assertEqual("invalid-json", self.fail())
                self.assertTrue((self.probe.journal.directory / "negative-inspection.json").is_file())
                self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)

    def test_successful_denial_with_journal_error_stops_before_positive(self):
        original = self.probe.journal.save
        def save(name, value):
            if name == "negative-denial.json":
                raise OSError(SECRET + LOCATION)
            original(name, value)
        self.probe.journal.save = save
        with self.assertRaises(OSError):
            self.probe.sender()
        self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)
        self.assertEqual(1, len(self.mutations()))

    def test_unexpected_negative_creation_cleans_only_owned_negative_and_fails(self):
        self.http.options["negative_created"] = True
        self.fail("negative-unexpectedly-created")
        self.assertEqual(["POST", "DELETE"], [c[0] for c in self.mutations()])
        self.assertTrue(self.mutations()[-1][1].endswith(NEGATIVE))
        self.assertNotIn(POSITIVE, self.http.refs)

    def test_intent_precedes_post_and_unknown_owned_names_never_mutate(self):
        original = self.http.request
        def request(method, path, token, body=None):
            if method == "POST":
                name = "negative" if body["ref"].endswith(NEGATIVE) else "positive"
                self.assertTrue((self.probe.journal.directory / (name + "-create-intent.json")).is_file())
            return original(method, path, token, body)
        self.http.request = request
        self.probe.sender()
        before = len(self.http.calls)
        for tag in ("v0.18.0", "refs/heads/main", "ci-auth-probe-100-" + "f" * 32):
            with self.assertRaises(p.Failure):
                self.probe.cleanup(tag, SECRET)
        self.assertEqual(before, len(self.http.calls))

    def test_main_drift_stops_before_pat(self):
        self.http.options["main_drift"] = True
        self.fail("main-drift")
        self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)
        self.assertEqual(1, len(self.mutations()))

    def test_preexisting_ref_is_never_claimed_or_deleted(self):
        for tag in (NEGATIVE, POSITIVE):
            with self.subTest(tag=tag):
                self.setUp()
                self.http.refs[tag] = SHA
                self.fail("ref-not-absent")
                self.assertEqual([], self.mutations())
                self.assertEqual({tag: SHA}, self.http.refs)
                self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)

    def test_missing_secret_does_not_fall_back_to_read_token(self):
        original = self.probe.credential
        self.probe.credential = lambda name: "" if name == "RELEASE_AUTOMATION_TOKEN" else original(name)
        self.fail("automation-token-missing")
        self.assertEqual(1, len(self.mutations()))

    def test_process_boundary_returns_zero_only_for_complete_success_and_sanitizes_failure(self):
        for options, expected in (({}, 0), ({"blob_error": True}, 1), ({"delete_status": 500}, 1),
                                  ({"negative_headers": {"retry-after": SECRET + LOCATION},
                                    "negative_body": {"message": READ + SAS + LOCATION}}, 1),
                                  ({"negative_body": [SECRET, LOCATION]}, 1)):
            with self.subTest(options=options):
                self.setUp()
                self.http.options = options
                event = self.root / "event.json"
                event.write_text(json.dumps(self.probe.c["payload"]))
                output = io.StringIO()
                env = {"GITHUB_EVENT_PATH": str(event), "RUNNER_TEMP": str(self.root / "runner")}
                with patch.dict(p.os.environ, env, clear=True), patch.object(p.sys, "argv", ["probe", "sender"]), \
                        patch.object(p.subprocess, "check_output", return_value=SHA), \
                        patch.object(p, "context", return_value=self.probe.c), \
                        patch.object(p, "Probe", return_value=self.probe), \
                        patch.object(p.signal, "signal"), patch.object(p.sys, "stdout", output), patch.object(p.sys, "stderr", output):
                    self.assertEqual(expected, p.main())
                self.assertEqual(expected == 0, (self.root / "runner/auth-probe/result.json").exists())
                evidence = output.getvalue() + "".join(f.read_text() for directory in
                    (self.root / "runner/auth-probe", self.probe.journal.directory) for f in directory.iterdir())
                for secret in (READ, SECRET, SAS, LOCATION):
                    self.assertNotIn(secret, evidence)

    def test_ambiguous_create_is_inspected_never_retried_or_automatically_deleted(self):
        scenarios = [{"positive_timeout": True}, {"positive_status": 422}, {"malformed_create": True},
                     {"created_ref": "refs/tags/v0.18.0"}, {"created_object": {"type": "tag"}},
                     {"created_object": {"sha": "b" * 40}}, {"wrong_readback": True}]
        for options in scenarios:
            with self.subTest(options=options):
                self.setUp()
                self.http.options = options
                self.fail()
                self.assertEqual(["POST", "POST"], [c[0] for c in self.mutations()])
                self.assertTrue((self.probe.journal.directory / "positive-inspection.json").is_file())

    def test_receiver_failure_or_interruption_keeps_failure_despite_successful_cleanup(self):
        for options in ({"receiver_timeout": True}, {"duplicate_receiver": True},
                        {"job_conclusion": "skipped"}, {"interrupt": True}):
            with self.subTest(options=options):
                self.setUp()
                self.http.options = options
                self.fail()
                self.assertEqual({}, self.http.refs)
                self.assertEqual(1, len([c for c in self.mutations() if c[0] == "DELETE"]))

    def test_manual_rerun_wrong_source_and_failed_receiver_are_not_delivery(self):
        for field, value in (("event", "workflow_dispatch"), ("run_attempt", 2), ("head_sha", "c" * 40),
                             ("conclusion", "failure"), ("display_title", "wrong")):
            with self.subTest(field=field):
                self.setUp()
                self.http.receiver_run[field] = value
                self.fail()
                self.assertEqual({}, self.http.refs)

    def test_moved_ref_is_not_deleted(self):
        self.http.options["moved_ref"] = True
        self.fail("ref-identity")
        self.assertFalse(any(c[0] == "DELETE" for c in self.http.calls))
        self.assertEqual("c" * 40, self.http.refs[POSITIVE])

    def test_cleanup_does_not_overwrite_the_original_receiver_failure(self):
        self.http.options.update({"receiver_timeout": True, "delete_status": 500})
        self.fail("receiver-and-cleanup-failed")
        directory = self.probe.journal.directory
        self.assertEqual("receiver-timeout", json.loads((directory / "receiver-failure.json").read_text())["category"])
        self.assertEqual("cleanup-incomplete", json.loads((directory / "cleanup-failure.json").read_text())["category"])

    def test_ambiguous_or_failed_delete_is_never_retried_or_promoted_to_pass(self):
        for options in ({"delete_timeout": True}, {"delete_timeout": True, "delete_happened": True},
                        {"delete_status": 500}, {"delete_still_present": True}):
            with self.subTest(options=options):
                self.setUp()
                self.http.options = options
                self.fail()
                self.assertEqual(1, len([c for c in self.mutations() if c[0] == "DELETE"]))
                self.assertTrue((self.probe.journal.directory / "cleanup.json").is_file())

    def test_artifact_identity_transport_layout_and_receipt_fail_closed(self):
        scenarios = [{"tamper": True}, {"blob_error": True}, {"blob_status": 302}, {"artifact_status": 200},
                     {"artifact": {"expired": True}}, {"artifact": {"size_in_bytes": p.LIMIT + 1}},
                     {"artifact": {"digest": "sha256:" + "0" * 64}}, {"receipt_wrong_nonce": True},
                     {"receipt_wrong_type": True},
                     {"duplicate_json": True}, {"duplicate_member": True}, {"member_name": "../receiver.json"},
                     {"member_mode": stat.S_IFLNK}, {"oversized_receipt": True},
                     {"location": "https://evil.example/?sig=" + SAS}]
        for options in scenarios:
            with self.subTest(options=options):
                self.setUp()
                self.http.options = options
                message = self.fail()
                self.assertEqual({}, self.http.refs)
                evidence = message + "".join(f.read_text() for f in self.probe.journal.directory.iterdir())
                for secret in (READ, SECRET, SAS, LOCATION):
                    self.assertNotIn(secret, evidence)

    def test_receiver_reads_only_and_correlates_actual_parent_and_exact_ref(self):
        self.probe = self.make(context(True))
        self.http.refs[POSITIVE] = SHA
        self.probe.receiver()
        self.assertEqual(["PROBE_READ_TOKEN"], self.credentials)
        self.assertTrue(all(c[0] == "GET" for c in self.http.calls))
        self.assertEqual(["receiver.json"], [f.name for f in self.probe.journal.directory.iterdir()])

    def test_receiver_guards_deletion_forced_and_wrong_source_before_credentials(self):
        cases = [{"created": False}, {"deleted": True}, {"forced": True}, {"after": "b" * 40},
                 {"ref": "refs/tags/v0.18.0"}]
        for change in cases:
            with self.subTest(change=change):
                c = context(True)
                c["payload"].update(change)
                probe = self.make(c)
                with self.assertRaises(p.Failure):
                    probe.receiver()
                self.assertEqual([], self.credentials)
                self.assertEqual([], self.http.calls)

    def test_receiver_rejects_completed_parent_and_wrong_ref(self):
        for change in ("parent", "ref"):
            with self.subTest(change=change):
                self.setUp()
                self.probe = self.make(context(True))
                self.http.refs[POSITIVE] = SHA
                if change == "parent":
                    self.http.sender_run["status"] = "completed"
                else:
                    self.http.refs[POSITIVE] = "b" * 40
                with self.assertRaises(p.Failure):
                    self.probe.receiver()
                self.assertTrue(all(c[0] == "GET" for c in self.http.calls))
                self.assertNotIn("RELEASE_AUTOMATION_TOKEN", self.credentials)


class TransportAndSourceTests(unittest.TestCase):
    def test_non_json_constants_and_duplicate_keys_are_not_accepted(self):
        for body in (b'{"x":NaN}', b'{"x":Infinity}', b'{"x":1,"x":2}'):
            with self.subTest(body=body), self.assertRaises(p.Failure):
                p.decode(body)

    def test_fresh_blob_request_carries_no_api_credentials_or_other_headers(self):
        requests = []
        http = p.HTTP()
        with patch.object(http, "exchange", side_effect=lambda request, **_: requests.append(request) or (200, {}, b"{}")):
            http.request("GET", p.ROOT + "/git/ref/heads/main", READ)
            http.blob(LOCATION)
        self.assertIn(READ, requests[0].get_header("Authorization"))
        self.assertEqual({}, dict(requests[1].header_items()))
        for location in ("http://example.blob.core.windows.net/x", "https://user:pass@a.blob.core.windows.net/x",
                         "https://a.blob.core.windows.net:444/x", "https://a.blob.core.windows.net/x#fragment",
                         "https://127.0.0.1/x", "https://localhost/x", "https://a.blob.core.windows.net.evil.example/x",
                         "https://a.blob.core.windows.net/x\n", "https://a.githubusercontent.com/x"):
            with self.subTest(location=location), self.assertRaises(p.Failure):
                p.validate_location(location)

    def test_redirect_handler_never_follows_and_mutation_api_has_no_release_escape(self):
        self.assertIsNone(p.NoRedirect().redirect_request(None, None, 302, None, None, LOCATION))
        http = p.HTTP()
        with patch.object(http, "exchange", side_effect=AssertionError("network forbidden")):
            cases = [("PATCH", p.ROOT + "/git/refs/tags/" + POSITIVE, {}),
                     ("POST", p.ROOT + "/releases", {}),
                     ("POST", p.ROOT + "/git/refs", {"ref": "refs/tags/v0.18.0", "sha": SHA}),
                     ("POST", p.ROOT + "/git/refs", {"ref": "refs/heads/main", "sha": SHA}),
                     ("DELETE", p.ROOT + "/git/refs/tags/v0.18.0", None),
                     ("GET", "/repos/elsewhere/repo/git/ref/heads/main", None)]
            for method, path, body in cases:
                with self.subTest(path=path), self.assertRaises(p.Failure):
                    http.request(method, path, SECRET, body)

    def test_workflow_scope_permissions_credentials_concurrency_and_owners(self):
        workflow = (ROOT / p.WORKFLOW).read_text()
        sender, receiver = workflow.split("\n  receiver:\n")
        self.assertIn("tags: ['ci-auth-probe-*']", workflow)
        self.assertEqual(1, workflow.count("secrets.RELEASE_AUTOMATION_TOKEN"))
        self.assertNotIn("RELEASE_AUTOMATION_TOKEN", receiver)
        self.assertNotRegex(workflow, r":\s*write(?:\s|$)")
        self.assertNotIn("id-token", workflow)
        self.assertIn("group: nonpublishing-auth-probe-${{ github.run_id }}", workflow)
        self.assertIn("cancel-in-progress: false", workflow)
        self.assertEqual(2, workflow.count("persist-credentials: false"))
        self.assertEqual(2, workflow.count("overwrite: false"))
        self.assertIn("github.event.deleted == false", receiver)
        self.assertIn("github.event.created == true", receiver)
        self.assertIn("github.event.forced == false", receiver)
        self.assertIn("inputs.expected_sha", sender)
        owners = (ROOT / ".github/CODEOWNERS").read_text()
        for path in (p.WORKFLOW, "tool/release/nonpublishing_auth_probe.py", "test/ci/test_nonpublishing_auth_probe.py"):
            self.assertIn("/" + path + " @leehack", owners)


if __name__ == "__main__":
    unittest.main()
