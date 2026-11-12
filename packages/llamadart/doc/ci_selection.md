# CI impact selection

`tool/ci/select_jobs.py` selects the core CI jobs and portable bundle targets
from a complete Git diff. Both workflows still report a final status for every
PR. A path filter must not prevent a required workflow from reporting.

## Selection boundary

| Changed inputs | Core checks | Portable builds |
|---|---|---|
| Documentation, website, docs tooling | Docs build/tool tests plus version and bridge-pin checks | None |
| Any `*.md` path | Adds `Markdown Tests`, unless full Linux coverage is selected | None |
| `tool/docs/`, `tool/testing/validation/`, or `tool/testing/validation.dart` | Adds the Markdown reader inventory guard through `Markdown Tests`; retains the path's other checks | Existing path selection |
| One companion package | Root static checks, affected package's Flutter/SwiftPM/publish checks, root Linux coverage and full macOS/Windows VM checks, Web Chat consumer | Android, Web, iOS inputs |
| Validation package tests/schemas or unbundled assets | Root static checks, private suite and provider/workspace/Flutter consumer contracts | None |
| Validation assets the chat app bundles (`flutter.assets`, such as profiles) | Same validation checks and Web Chat | None |
| Validation implementation/dependencies | Same validation checks and Web Chat | All desktop and app targets |
| Validation provider/build helpers | Same validation checks | All desktop and app targets |
| Android/iOS/Web chat packaging | Root static checks; Web Chat for Web inputs | Affected app target |
| Other chat app implementation/dependencies | Static, private harness, Web Chat | All app targets |
| Chat app unit tests | Static and Web Chat | None |
| Root tests/fixtures | Static, all Linux VM tests, Chrome and macOS/Windows host tests | None |
| Root runtime/hooks/dependencies, other example packages, shared or unknown paths | Full behavioral graph | All targets; a PR defers macOS desktop and Android unless it changes their build inputs |
| Workflow/selector changes | Full graph including synthetic artifact transport | All targets; a PR defers macOS desktop and Android unless it changes the bundle workflow or selector |
| Missing, empty or invalid diff; explicit manual bundle run | Full fallback | All targets |

Selections combine for mixed changes. Version checks already executed by the
root static job are not duplicated in the docs-only job. Provider root tests
already executed by full Linux coverage are not duplicated in a separate job.
The consumer job is omitted entirely only when both root coverage and Web Chat
(which runs all Flutter app tests) substitute its assertions. Mixed validation
and root-test changes still run the Flutter consumer assertions.
Web Chat Contract installs no system packages, so an Ubuntu mirror outage cannot fail the required job.
The private harness also checks APK integrity. Its separate consumer job runs
root provider/NPU/workspace tests and the Flutter validation controller/app tests.

PR diffs use the merge base of the immutable base/head revisions; push diffs use
the event's before/after revisions. Checkout fetches history. Renames include
both source and destination; deleted paths remain inputs. Git's NUL-delimited
output preserves whitespace and avoids API file-count limits. Missing history,
invalid event metadata and malformed inventory fall back to full work. Paths and
revision inputs are never interpolated into shell code. Changes to the selector
itself select every lane.

The existing `Test Linux & Web (with Coverage)` status now aggregates **all**
selected core jobs. It runs with `always()` and rejects failed, cancelled,
missing or unexpectedly skipped selected jobs. Only deliberately unselected
jobs may be skipped. The bundle result applies the same rule to target matrices.
This is executable job accounting, not a new repository protection setting.

`Markdown Tests` runs only the root suites listed in
`tool/ci/markdown_test_suites.txt`, for a change that selects no full Linux
coverage. It carries no coverage, so a Markdown-only commit uploads none to
Codecov. `markdown_test_suites_test.dart` fails when a root test names Markdown,
directly or through a local helper or tool, and is neither listed nor explained
in that test: list a suite that reads a tracked `.md`, or a tool that does. That
check runs in `Markdown Tests` itself as well as the full graph. Changes to
`tool/docs/`, `tool/testing/validation/` or `tool/testing/validation.dart` also
select it, since those helpers can introduce a reader without editing a test.
The exemption map's test has an explicit CODEOWNERS assignment; requiring owner
approval still depends on repository protection settings. The source scan is
heuristic and does not prove the absence of every possible Markdown reader.
Because Linux coverage can no longer stand in for
`validation-integration` on a Markdown path, that job stays selected there.

Root tests run as file shards: Linux VM (3), Chrome (3), macOS `Test Native`
(3) and Windows `Test Native` (1 `windows-tooling`, 2 `windows-runtime`).
Linux VM and Chrome run every root test file; macOS and Windows run only the
host tests described under "Host OS lanes". `tool/ci/test_shards.dart` lists
every root `*_test.dart` file and assigns each to exactly one shard of each
lane that runs it, longest first onto the
lightest shard, using suite times in `tool/ci/test_shard_weights.json`; a new
file counts as the median suite until the weights are refreshed
(`doc/testing_matrix.md`, "Test timing and shards"). Windows keeps tooling and
runtime suites in separate processes: a tooling suite's `dart run` child cannot
replace `.dart_tool/lib` DLLs a native suite in the same process holds open.
Stale weights only unbalance shards; they cannot drop or repeat a file. A shard
count is the length of its matrix, which `ci_workflow_selection_test.dart`
checks against the selector call. VM shards keep `-j 1 --exclude-tags
local-only` and their own LiteRT-LM temp canary.
Coverage is collected after merge only: it doubles the Linux VM time. The
selector's `coverage` output is false for pull requests and true for pushes
to `main` and manual runs. Then each Linux shard runs with `--coverage` and
uploads its raw VM coverage, and `Test Linux VM (with Coverage)` waits for
every shard, formats their combined raw coverage with `format_lcov.dart`
exactly as one full run would, enforces the **70%** threshold and uploads to
Codecov. A PR's Linux shards run the same files without coverage, and that
job is skipped. **The threshold is enforced post-merge:** a drop fails the
`main` run, its `Test Linux & Web (with Coverage)` aggregate and the chat app
deploy, and the job adds an error annotation and a step summary naming the
commit. Run the `coverage-lib` matrix row locally before merging a change that
may lower coverage. The aggregate requires the shards (`SHARD_JOBS` in the
selector) whenever root Linux tests are selected, and the coverage job only
when coverage is also selected. A job's aggregate result is `failure` if any of its
shards fails. Shard by whole files: most of the Chrome lane is dart2js compiling
each suite, and on the VM each suite's load and coverage collection would
repeat under `dart test --total-shards`.

Shards add jobs against the account's concurrent-job cap (20 jobs, 5 of them
macOS, shared with `llamadart-native`), so counts are set so that no shard
outlasts the longest unsharded job (`Web Chat Contract`) by much. Windows shards start Python once before their tests, since any
shard's tooling suites may be the first to start it. `Genkit` runs its lower
bound and published checks and its checkout-core, real-model and browser
checks as two matrix legs.

Checks share a job to stay under GitHub Free's limit of 5 concurrent macOS jobs
across the owner's repositories, and each keeps its own selection on its step:
`Companion Packages (macOS)` runs when companion packages, `Test Native` or the
validation harness is selected, then runs the selected companion packages, the
validation process memory test and the Apple companion cache-transition test,
each even if an earlier one failed. On Windows the process memory test runs in
`Test Native` when that job is selected, and otherwise in a
`Validation harness` matrix leg, so a validation-only change starts no native
tests. The Genkit job runs Dart 3.12.0 lower bounds on a fresh tree before it
sets up Flutter, so `FLUTTER_ROOT` and Flutter's Dart cannot affect them.

`Example Package Tests` runs the model-free tests (`--exclude-tags
local-only`) of every example package except the chat app, which Web Chat
covers, as one Ubuntu job in the full graph. `ci_workflow_selection_test.dart`
fails when an example package with a `test/` directory has no step there.

Obsolete PR CI runs cancel within the same PR. Every non-PR CI run uses its
own run ID as its concurrency group, so consecutive main pushes and manual
runs retain all selected checks, including runs waiting for a runner. Disabling
`cancel-in-progress` alone on a shared group would still replace its pending
run. Push selection continues to use only that event's before/after diff;
retaining each run preserves the checks selected for every merge (#1646).

Obsolete PR bundle runs cancel. Manual and `main` push bundle runs have unique
concurrency groups and do not cancel one another. Every push to `main` builds
the bundle targets its change selects. A pull request defers the macOS desktop
and Android builds to that push unless it changes their own build inputs
(`POST_MERGE_TARGETS` and `builds_target` in the selector): the bundle
workflow or selector, `hook/`, `lib/src/hook/` (native pins), root
`pubspec.yaml`/`pubspec.lock`, compiled validation package code or bundle
tooling (`tool/testing/validation*`), and for Android also chat app sources
outside its tests and other platforms' folders, and the Apple companions'
`lib/` and `pubspec.yaml`. Their Dart code still compiles in the PR's Linux
desktop and Web builds. A deferred target is unselected, so `Validation bundle
result` expects it skipped. A break in a deferred build first shows on `main`.

## Host OS lanes

macOS and Windows `Test Native` run a root test file only when it can behave
differently by host OS; every other file is platform-neutral and runs on
Linux (and Chrome where it supports the browser). `hostReasons` in
`tool/ci/test_shards.dart` decides from the source, so a new test lands in the
right lanes without a list to maintain. A file runs on every OS when:

- it is in a host-bound area: `test/unit/backends/{llama_cpp,litert_lm,stable_diffusion,native}/`,
  the files directly in `test/unit/backends/` and `test/integration/`,
  `test/unit/hook/`, `test/unit/platform/`, `test/integration/backends/` or
  `test/e2e/`;
- it is a `*_io_test.dart` (a `dart:io` implementation);
- it, or a `test/` helper it imports, imports `dart:ffi`, `package:ffi`, a
  native runtime (`lib/src/backends/{llama_cpp,litert_lm,stable_diffusion,native}/`),
  `lib/src/platform/io/`, `lib/src/hook/` or `hook/`, loads a test model
  (`TestHelper`, `LLAMADART_TEST_MODELS_DIR`) or constructs `LlamaBackend()`;
- its own source checks the host OS (`Platform.isWindows` and the like, an OS
  in `@TestOn`, `onPlatform:`), other than a lone
  `skip: Platform.isWindows ? <reason> : false` POSIX guard; or
- its own source imports both `dart:io` and `package:path` (host paths); or
- `hostHistoryTests` lists it with evidence of an OS-only failure the rules
  miss.

`dart tool/ci/test_shards.dart hosts [<file>...]` prints each file's lanes and
reasons. Of the test files that Windows- or macOS-specific fixes touched in
`git log`, the rules keep all but two on those lanes: `prepare_workspace_test`
(#678, now in `hostHistoryTests`) and `safe_pr_head_update_test`, whose
Windows fix only normalized the test's own CRLF checkout. Template, parser,
grammar, engine-logic tests with fake backends and tooling without a host
branch run on Linux only. `test_shards_test.dart` pins the rules, rejects
`hostHistoryTests` entries the rules already cover, and checks that macOS and
Windows run the same files and that no file restricted away from Linux misses
them; Linux VM runs every file, so no file is in zero lanes.

## Retained protections and separate work

Full runtime and shared changes still execute every root test on the Linux VM
and the host tests on macOS and Windows, including tiny native inference and
ABI checks, Windows process and DLL-loader tests, the macOS Apple companion
cache-transition test, Chrome, Web Chat and prompt-reuse parity. Isolated companion work still runs root
consumers, not just package-local tests. No model oracle or coverage threshold
changed. Build success does not qualify real GPU/NPU/device/model execution.

The synthetic Actions upload/download roundtrip now runs on workflow/selector
changes; ordinary runtime work retains real failure-diagnostic upload behavior.
The new workflow contract tests validate the actual selection/aggregate wiring.

Coverage tooling is pinned to **1.16.0**, with the **70%** threshold retained
and enforced post-merge.
This version parses `--workers` but does not forward it to `HitMap.parseFiles`,
which loops over inputs sequentially. Adding `--workers 2` or `4` therefore
would not implement parallel formatting. Benchmark numbers must be identified
as local or hosted measurements and compared on identical raw coverage using
semantic LCOV records, including all hit counts, not just overall percentages.

Integration-repository cleanup remains a separate proposal tracked by #532. #384 remains the
coverage measurement work item; historical latency targets are not claims about
this implementation. No release, publication, runtime pin or settings change is
part of this batch.

## Verify changes

```bash
python3 -m unittest discover -s test/ci -p 'test_*.py'
dart run tool/testing/run_local_e2e.dart --scenario ci-selection
actionlint .github/workflows/ci.yml .github/workflows/validation_bundles.yml
actionlint -ignore '^unexpected key "queue" for "concurrency" section\. expected one of "cancel-in-progress", "group"$' .github/workflows/chat_app_hf_static_deploy.yml
```

Actionlint 1.7.12 rejects GitHub's documented `concurrency.queue` key
([upstream issue](https://github.com/rhysd/actionlint/issues/657),
[pending fix](https://github.com/rhysd/actionlint/pull/654)). Retain its unfiltered
diagnostic as evidence before the second invocation: that invocation excludes
only this known schema diagnostic for the reusable deploy workflow. Its queue
policy is covered by the workflow tests; other lint diagnostics still fail.

Tests cover docs-only and package changes, shared/runtime/unknown inputs,
platform targets, workflow changes, actual Git rename/deletion histories,
invalid/truncated inventories, mixed changes, and aggregate failure/cancellation
semantics. Workflow tests verify every planned job is wired into the aggregate,
dynamic matrices consume the selector, full OS commands survive, and isolated
validation retains root/Flutter consumer tests.

Predicted savings come from omitted jobs and obsolete PR cancellation, not
faster runtime tests. Measure hosted wall time, queue delay and summed job time
separately after approved PR execution; do not report docs-only results as a
full-code speedup or local measurements as GitHub-hosted results.

## Flutter Chrome test shutdown

Flutter 3.47.1's `flutter test --platform chrome` waits with no timeout for
Chrome's reply to DevTools `Browser.close`, so it hangs after reporting results
when Chrome exits before the reply arrives (#1702). Web Chat Contract therefore
runs its Chrome tests under `tool/ci/supervise_chrome_test.py` with a 10-minute
deadline and uploads `chat-app-chrome-diagnostics`. If the command is still
running 30 seconds after its JSON file reporter's `done` event and no browser
process remains, the supervisor stops it, logs a warning, records
`browser_close_stall` in `result.json` and exits with the reporter's result: 0
only when the run succeeded with at least one test, 1 when a test failed. Any
other stall still fails at the deadline. Browser tests that need no Flutter API
use `dart test -p chrome`, which stops Chrome with a signal (Model Store).

## Tested Web deployment and previews

On canonical-repository main pushes and manual main runs, Web Chat Contract
builds the production root (`/`) once, runs mock and real tiny-GGUF browser smokes against those files,
and uploads the successful artifact. The production reusable workflow waits for
both Web Chat and the existing all-selected-checks aggregate to succeed. An
explicit cancellation status check prevents intentionally skipped ancestors from
triggering GitHub’s implicit `success()` skip propagation; failed or skipped
direct requirements still block deployment. It
verifies the same run's artifact ID, archive digest, source commit/tree, pinned
Flutter version and production build target before uploading those files to HF.
It does not install Flutter or rebuild. HF's README remains hosting metadata.

Directly before the upload, `tool/ci/deploy_guard.py` fetches `main` and
compares its tip with the artifact's commit:

| `main` since the artifact's commit | Outcome |
|---|---|
| Unchanged | Upload and verify. |
| Only commits that would not select Web Chat on their own, such as a docs version cut | Upload and verify; a notice names `main`'s tip. |
| Web Chat inputs differ at `main`'s tip | Superseded: upload and verification are skipped, the job passes, and a notice plus the job summary name `main`'s tip and the changed inputs. |
| Web Chat inputs changed and then restored | Upload and verify; the artifact matches `main`'s inputs. Git records no push boundaries, so this holds even when the change had its own deploy run. |
| `main` no longer contains the commit, or the fetch fails | The job fails. |

A push that changes Web Chat inputs deploys through its own CI run, so a superseded
artifact is never uploaded over it. The Laya Tetris deploy runs the same guard
with its workflow's `paths` filter as the input list, since a push outside that
filter starts no Laya Tetris run.

Chat app deployments share a serialized, non-cancelling group with
[`queue: max`](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency#example-queueing-multiple-pending-runs).
It retains up to 100 pending deployments. Older validation can finish after
newer validation: it must not cancel a running newer deployment or replace a
pending one before reaching its own stale-input guard. Each retained build
checks current inputs after entering the group, so stale builds skip without
displacing the current build. At the 100-pending limit, GitHub cancels additional
arrivals; rerun a cancelled current build once capacity is available.

Before merging this concurrency-policy change, let all queued and running main
CI and chat app deployment runs from the old revision finish. An older CI run
can still invoke its original cancelling deployment workflow and preempt the
new group. If old and new runs overlap and a current deployment is cancelled,
first drain the old runs, then dispatch CI on current `main` with the command
below to rebuild, test and deploy it.

`main` can still move between the guard and the Hugging Face commit. A push
that changes chat app inputs starts its own run, whose upload waits for the
current deployment to finish. The Laya Tetris deploy keeps its separate
cancelling group. An input change pushed with `GITHUB_TOKEN` starts no workflow
and stays undeployed until the next run; today only the docs version cut pushes
that way, and it changes no demo input.

CI retains each `main` run when a newer push arrives. A later push that does
not select Web Chat leaves the earlier run eligible to finish and deploy,
subject to the same artifact and current-input guards above.

The former manual arbitrary-ref deployment is removed. A manual CI run on
`main` selects the full graph and deploys the artifact that run built and
tested; on any other ref it deploys nothing:

```bash
gh workflow run ci.yml --ref main
gh workflow run laya_tetris_hf_static_deploy.yml --ref main
```

Each manual CI run has its own concurrency group, so it retains its checks
alongside main pushes and other manual runs. Retry a failed upload through its
original CI run while the guard still accepts that commit and its seven-day
artifact is available. No artifact from another run or untested rebuild is
accepted. GitHub-hosted promotion and HF upload must still be verified after an
approved PR/merge; local tests do not claim hosted deployment evidence.

PR previews default to non-draft same-repository changes selected for Web Chat
(including shared runtime dependencies and conservative unknown inputs).
Docs-only and mobile-only changes skip the build. A `preview` label explicitly
opts in, including drafts. Forks and Dependabot remain excluded. Selection runs
before Flutter setup; the build job has no deployment secrets. Deployment uses
the resulting artifact and verification scripts from the PR base. Closing a PR
always attempts cleanup regardless of paths, labels or draft status. Converting
a PR to draft or removing the label skips future ineligible builds; an existing
preview remains until close. Unrelated label events skip the build and cannot cancel useful work. Provider writes
run in a per-PR `queue: max`, `cancel-in-progress: false` job, using only
trusted base helpers. Up to 100 pending jobs are retained; saturation and
external cross-provider atomicity are outside this contract. Arrival at the
queue can differ from dispatch order, so every create, upload, retry, delete
and comment checks the live PR head/state and eligibility. A delayed close
requires the original close timestamp, protecting reopen/reclose sequences.
API failures fail closed. Artifacts are bound to the same run, PR,
repository, head, archive digest, Git tree and build stamp. A provider-only
job rerun can reuse a verified artifact from an earlier positive-numbered build
attempt of that run while the head remains eligible. It never accepts an
artifact from another run. The production main-only verifier stays separate.
A PR changing the trusted helper requires that helper to land before its new
preview workflow can run against the base.

To exercise the production layout locally, cache `stories15M.gguf` at
`.dart_tool/test_models/stories15M.gguf`, then run:

```bash
dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-production-smoke
```

The runner builds once and starts two loopback servers: the unchanged app at
`--port` (default 7358), with HF's `require-corp` isolation policy, and the model
at the next port with CORS limited to that app origin. Both servers are cleaned
up on success or failure. `--model-url` overrides the model URL; `--skip-build`
validates and tests an existing build. Model files are never added to the
uploaded app. The corresponding matrix row is `web-production-artifact-smoke`.
The concrete saving is one removed production Flutter setup/dependency/build;
no hosted timing or cost percentage is claimed before measurement.
