"""Replay the actual workflow shell steps with isolated fake external services.

No test may create a real tag, dispatch a workflow, or publish a package.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHA = "1" * 40


def step(name, workflow="release_genkit_on_prep_merge.yml"):
    source = (ROOT / ".github/workflows" / workflow).read_text()
    # These workflows use literal run blocks at the standard step indentation.
    # Fail if the layout changes instead of silently testing an empty script.
    match = re.search(r"^      - name: " + re.escape(name) + r"\n(.*?)(?=^      - name: |\Z)", source, re.M | re.S)
    if not match:
        raise AssertionError(f"Missing step: {name}")
    block = re.search(r"^        run: \|\n((?:          .*\n|\n)+)", match[1], re.M)
    if not block:
        raise AssertionError(f"Missing run block: {name}")
    return textwrap.dedent(block[1])


FAKE = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
s = json.loads(os.environ['SCENARIO'])
a = sys.argv[1:]
name = Path(sys.argv[0]).name
if name == 'git':
    if a[0] == 'rev-parse': print(s.get('sha', '1' * 40))
    elif a[0] == 'ls-remote': print(s.get('tags', ''))
    else: sys.exit('Unexpected git call: ' + repr(a))
elif name == 'curl':
    key = 'pub' if any('pub.dev/' in v for v in a) else 'release'
    print(s.get(key + '_http', '404'), end='')
    sys.exit(s.get('curl_exit', 0))
elif name == 'gh':
    if any('/files' in v for v in a):
        print(json.dumps(s.get('files', [[{'filename': 'packages/genkit_llamadart/pubspec.yaml', 'status': 'modified'}, {'filename': 'packages/genkit_llamadart/CHANGELOG.md', 'status': 'modified'}]])))
        sys.exit(s.get('files_exit', 0))
    elif any('/runs?' in v for v in a):
        print(json.dumps([{'workflow_runs': s.get('runs', [])}]))
        sys.exit(s.get('runs_exit', 0))
    elif '--method' in a or a[:2] == ['release', 'create']:
        with open(os.environ['MUTATIONS'], 'a') as f: f.write(json.dumps(a) + '\\n')
    else: sys.exit('Unexpected gh call: ' + repr(a))
else: sys.exit('Unexpected command: ' + name)
'''


class ReleaseAutomationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "bin").mkdir()
        (self.root / "tool/release").mkdir(parents=True)
        (self.root / "packages/genkit_llamadart").mkdir(parents=True)
        shutil.copy(ROOT / "tool/release/genkit_release_helpers.sh", self.root / "tool/release")
        for name in ("git", "gh", "curl"):
            p = self.root / "bin" / name
            p.write_text(FAKE)
            p.chmod(0o755)
        (self.root / "packages/genkit_llamadart/pubspec.yaml").write_text("name: genkit_llamadart\nversion: 1.5.0\n")
        (self.root / "packages/genkit_llamadart/CHANGELOG.md").write_text("## 1.5.0 - 2026-09-28\n")
        self.event = {"pull_request": {"head": {"ref": "release/genkit_llamadart-v1.5.0", "repo": {"full_name": "leehack/llamadart"}}, "labels": []}}
        self.scenario = {}
        self.env = {**os.environ, "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                    "GITHUB_WORKSPACE": str(self.root), "GITHUB_REPOSITORY": "leehack/llamadart", "GITHUB_EVENT_PATH": str(self.root / "event.json"),
                    "GITHUB_OUTPUT": str(self.root / "output"), "MUTATIONS": str(self.root / "mutations"),
                    "GH_TOKEN": "test-token", "PR_NUMBER": "20", "BRANCH_VERSION": "1.5.0",
                    "RELEASE_SHA": SHA, "TAG": "genkit_llamadart-v1.5.0", "PACKAGE_NAME": "genkit_llamadart", "VERSION": "1.5.0",
                    "RELEASE_WAIT_ATTEMPTS": "1", "RELEASE_WAIT_INTERVAL_SECONDS": "1"}

    def run_step(self, name, success=True, workflow="release_genkit_on_prep_merge.yml"):
        (self.root / "event.json").write_text(json.dumps(self.event))
        (self.root / "output").write_text("")
        result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", step(name, workflow)], cwd=self.root,
                                env={**self.env, "SCENARIO": json.dumps(self.scenario)}, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return dict(line.split("=", 1) for line in (self.root / "output").read_text().splitlines())

    def mutations(self):
        path = self.root / "mutations"
        return [json.loads(s) for s in path.read_text().splitlines()] if path.exists() else []

    def test_version_branch_patterns(self):
        for branch in ["release/genkit_llamadart-v1.5.0"]:
            with self.subTest(branch=branch):
                self.event["pull_request"]["head"]["ref"] = branch
                output = self.run_step("Check release-prep gate")
                self.assertEqual(output["should_release"], "true")
                self.assertEqual(output["branch_version"], "1.5.0")
        self.assertEqual(self.mutations(), [])

    def test_ordinary_automation_and_malformed_branches_skip(self):
        for branch in ["feature/foo", "release/prep-merge-automation", "release/genkit_llamadart-v1.5.0-rc1", "release/genkit_llamadart-v1.5.0/extra", "release/v1x5x0"]:
            self.event["pull_request"]["head"]["ref"] = branch
            self.assertEqual(self.run_step("Check release-prep gate")["should_release"], "false")
        self.assertEqual(self.mutations(), [])

    def test_label_allows_same_repo_only(self):
        self.event["pull_request"]["head"]["ref"] = "prepare-release"
        self.event["pull_request"]["labels"] = [{"name": "release-prep:genkit_llamadart"}]
        self.assertEqual(self.run_step("Check release-prep gate")["should_release"], "true")
        self.event["pull_request"]["head"]["repo"]["full_name"] = "fork/repo"
        self.assertEqual(self.run_step("Check release-prep gate")["should_release"], "false")

    def test_core_gate_cannot_publish_genkit_only_or_cross_package_prep(self):
        self.event['pull_request']['labels'] = [{'name': 'release-prep'}]
        self.assertEqual(self.run_step('Check release-prep gate',
            workflow='release_on_prep_merge.yml')['should_release'], 'false')
        self.event['pull_request']['head']['ref'] = 'release/prep-0.15.1'
        self.assertEqual(self.run_step('Check release-prep gate',
            workflow='release_on_prep_merge.yml')['should_release'], 'false')
        self.scenario['files'] = [[{'filename': 'pubspec.yaml', 'status': 'modified'},
                                  {'filename': 'CHANGELOG.md', 'status': 'modified'}]]
        self.assertEqual(self.run_step('Check release-prep gate',
            workflow='release_on_prep_merge.yml')['should_release'], 'true')
        self.scenario['files'][0].append({'filename': 'packages/genkit_llamadart/pubspec.yaml',
                                         'status': 'modified'})
        self.assertEqual(self.run_step('Check release-prep gate',
            workflow='release_on_prep_merge.yml')['should_release'], 'false')
        self.scenario['files'][0][-1] = {'filename': 'doc/moved-adapter.md',
            'previous_filename': 'packages/genkit_llamadart/README.md', 'status': 'renamed'}
        self.assertEqual(self.run_step('Check release-prep gate',
            workflow='release_on_prep_merge.yml')['should_release'], 'false')
        self.scenario['files_exit'] = 1
        self.run_step('Check release-prep gate', success=False,
                      workflow='release_on_prep_merge.yml')
        self.assertEqual(self.mutations(), [])

    def test_core_release_name_and_generic_label_do_not_route_to_genkit(self):
        for branch in ('release/prep-0.15.1', 'release/v1.5.0', 'feature/docs'):
            self.event['pull_request']['head']['ref'] = branch
            self.event['pull_request']['labels'] = [{'name': 'release-prep'}]
            self.assertEqual(self.run_step('Check release-prep gate')['should_release'], 'false')
        self.assertEqual(self.mutations(), [])

    def test_scope_accepts_exact_modified_files_across_pages(self):
        self.scenario["files"] = [[{"filename": "packages/genkit_llamadart/pubspec.yaml", "status": "modified"}], [{"filename": "packages/genkit_llamadart/CHANGELOG.md", "status": "modified"}]]
        self.run_step("Validate release-prep scope")

    def test_scope_rejects_extra_missing_deleted_or_duplicate_files(self):
        good = [{"filename": "packages/genkit_llamadart/pubspec.yaml", "status": "modified"}, {"filename": "packages/genkit_llamadart/CHANGELOG.md", "status": "modified"}]
        cases = [good + [{"filename": "lib/x.dart", "status": "modified"}], good[:1], good + good[:1], [good[0], {"filename": "packages/genkit_llamadart/CHANGELOG.md", "status": "removed"}]]
        for files in cases:
            self.scenario["files"] = [files]
            self.run_step("Validate release-prep scope", success=False)

    def test_partial_scope_api_failure_is_not_accepted(self):
        self.scenario["files_exit"] = 1
        self.run_step("Validate release-prep scope", success=False)

    def test_new_release_state(self):
        output = self.run_step("Validate release state")
        self.assertEqual(output["should_dispatch"], "true")
        self.assertEqual(output["release_sha"], SHA)
        self.assertEqual(output["tag_sha"], "")
        self.assertEqual(self.mutations(), [])

    def test_lightweight_and_annotated_matching_tags(self):
        for tags in [f"{SHA}\trefs/tags/genkit_llamadart-v1.5.0", f"{'2'*40}\trefs/tags/genkit_llamadart-v1.5.0\n{SHA}\trefs/tags/genkit_llamadart-v1.5.0^{{}}"]:
            self.scenario["tags"] = tags
            self.assertEqual(self.run_step("Validate release state")["tag_sha"], SHA)

    def test_conflicting_tag_fails(self):
        self.scenario["tags"] = f"{'2'*40}\trefs/tags/genkit_llamadart-v1.5.0"
        self.run_step("Validate release state", success=False)

    def test_version_or_changelog_mismatch_fails(self):
        self.env["BRANCH_VERSION"] = "9.9.9"
        self.run_step("Validate release state", success=False)
        self.env["BRANCH_VERSION"] = "1.5.0"
        for heading in ["## Unreleased", "## 1.4.0 - 2026-09-28", "## 1.5.0"]:
            (self.root / "packages/genkit_llamadart/CHANGELOG.md").write_text(heading + "\n")
            self.run_step("Validate release state", success=False)

    def test_published_version_requires_tag_and_skips_dispatch(self):
        self.scenario["pub_http"] = "200"
        self.run_step("Validate release state", success=False)
        self.scenario["tags"] = f"{SHA}\trefs/tags/genkit_llamadart-v1.5.0"
        output = self.run_step("Validate release state")
        self.assertEqual(output["should_dispatch"], "false")
        self.assertEqual(output["release_live"], "false")

    def test_github_release_without_package_fails(self):
        self.scenario["release_http"] = "200"
        self.run_step("Validate release state", success=False)

    def test_lookup_errors_fail_closed(self):
        for key in ["pub_http", "release_http"]:
            for status in ["401", "403", "429", "500"]:
                self.scenario = {key: status}
                self.run_step("Validate release state", success=False)
        self.scenario = {"curl_exit": 7}
        self.run_step("Validate release state", success=False)
        self.assertEqual(self.mutations(), [])

    def test_create_tag_uses_exact_merge_sha(self):
        self.run_step("Create release tag")
        self.assertIn("sha=" + SHA, self.mutations()[0])
        self.assertIn("ref=refs/tags/genkit_llamadart-v1.5.0", self.mutations()[0])

    def test_dispatch_uses_tag(self):
        self.run_step("Dispatch publish workflow")
        self.assertEqual(len(self.mutations()), 1)
        self.assertIn("ref=genkit_llamadart-v1.5.0", self.mutations()[0])

    def test_retry_does_not_dispatch_over_active_publisher(self):
        for status in ["queued", "in_progress", "waiting"]:
            self.scenario["runs"] = [{"head_branch": "genkit_llamadart-v1.5.0", "status": status}]
            self.run_step("Dispatch publish workflow")
        self.assertEqual(self.mutations(), [])

    def test_completed_failed_run_can_be_retried(self):
        self.scenario["runs"] = [{"head_branch": "genkit_llamadart-v1.5.0", "status": "completed", "conclusion": "failure"}]
        self.run_step("Dispatch publish workflow")
        self.assertEqual(len(self.mutations()), 1)

    def test_run_lookup_failure_blocks_dispatch(self):
        self.scenario["runs_exit"] = 1
        self.run_step("Dispatch publish workflow", success=False)
        self.assertEqual(self.mutations(), [])

    def test_repair_requires_existing_tag(self):
        self.run_step("Repair missing GitHub Release")
        self.assertIn("--verify-tag", self.mutations()[0])

    def test_wait_requires_both_surfaces(self):
        self.run_step("Wait for publication", success=False)
        self.scenario = {"pub_http": "200"}
        self.run_step("Wait for publication", success=False)
        self.scenario["release_http"] = "200"
        self.run_step("Wait for publication")

    def test_invalid_polling_settings_fail_before_dispatch_and_during_wait(self):
        for key in ["RELEASE_WAIT_ATTEMPTS", "RELEASE_WAIT_INTERVAL_SECONDS"]:
            for value in ["0", "-1", "oops", "1.5", ""]:
                with self.subTest(key=key, value=value):
                    self.env[key] = value
                    output = self.run_step("Validate release state", success=False)
                    self.assertNotIn("should_dispatch", output)
                    self.run_step("Wait for publication", success=False)
            self.env[key] = "1"
        self.assertEqual(self.mutations(), [])

    def test_publish_only_accepts_matching_stable_tag(self):
        self.env.update(GITHUB_REF_TYPE="tag", GITHUB_REF_NAME="genkit_llamadart-v1.5.0", GITHUB_REF="refs/tags/genkit_llamadart-v1.5.0")
        self.run_step("Verify package-specific stable tag", workflow="publish_genkit_pubdev.yml")
        for kind, name in [("branch", "main"), ("tag", "v1.5.1"), ("tag", "v1.5.0-rc1")]:
            self.env.update(GITHUB_REF_TYPE=kind, GITHUB_REF_NAME=name)
            self.run_step("Verify package-specific stable tag", success=False, workflow="publish_genkit_pubdev.yml")


if __name__ == "__main__":
    unittest.main()
