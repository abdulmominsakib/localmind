# AGENTS.md

Open a linked doc before working in its area; it holds the procedure this file
leaves out.

## Build and test

```bash
dart run tool/prepare_workspace.dart
dart format --output=none --set-exit-if-changed .
dart analyze   # CI's Pana step also fails on any info in lib/
dart run tool/testing/check_platform_boundaries.dart
dart test -p vm -j 1 --exclude-tags local-only
dart test -p chrome --exclude-tags local-only
```

- Run `prepare_workspace.dart` first, on a clean checkout; CI fails if it leaves
  tracked files modified. Never hand-edit a `pubspec.lock`: constrain
  `pubspec.yaml` and let pub regenerate it.
- On macOS, run local VM tests with an isolated temp directory
  (`TMPDIR="$(mktemp -d)" dart test -p vm ...`): LiteRT-LM engines without
  `liteRtLmCacheDir` prune the program caches apps share in
  `$TMPDIR/llamadart_litert_lm`, and local-only LiteRT-LM E2E tests prune it
  like any 0.13 app. Suites that load LiteRT-LM models call
  `useSuiteSystemTemp()` (`test/support/suite_system_temp.dart`); CI fails a VM
  lane whose tests delete its canary there.
- Use the Flutter SDK in `.flutter-version`; other SDKs format differently from
  CI. A pin bump is its own PR that updates `.flutter-version`, every workflow
  `flutter-version:`, and the reformat it causes.
- Root preparation, analysis and tests skip `packages/` and `website/` (root
  format does not): companion packages keep their own dependency, analyze,
  test, SwiftPM and publish-validation lanes, and the Jaspr docs site its own
  analyze and test lane (`ci.yml`).
- `packages/genkit_llamadart` is independently versioned and resolved. Its
  package-specific CI, history and release routing are documented in
  `website/docs/maintainers/genkit-package.md`; never include it in core or
  Apple companion release numbering. The same holds for the unpublished
  `packages/llamadart_model_store`
  (`website/docs/maintainers/model-store-package.md`).
- Chat app changes: `(cd example/chat_app && flutter test test test_vm)`
  (`test_vm/` holds VM-only tests kept out of the Web compile), plus
  `flutter test --platform chrome test/chat_generation_service_test.dart
  test/image_generation_screen_test.dart test/unit_test.dart
  test/conversation_state_service_test.dart` there for Web-only paths such as
  LiteRT-LM generation settings and the image screen's unsupported state.
- Pick further validation from `dart run tool/testing/test_matrix.dart --list`
  (`doc/testing_matrix.md`) and put its `--pr-template` rows in the PR.
- PR CI runs no coverage (`main` enforces the 70% threshold after merge), so
  run the `coverage-lib` row when `lib/` behavior changes. It runs a root test
  on macOS and Windows only when the test can differ by host OS; check with
  `dart tool/ci/test_shards.dart hosts <file>` (`doc/ci_selection.md`).
- Heavy, device- or model-backed checks stay out of default CI: tag such tests
  `local-only`, or wire the scenario into `run_local_e2e.dart` and
  `test_matrix.dart` and document it. Run one with `run_local_e2e.dart --list`,
  then `--scenario <name> --dry-run` before a real run. No one-off repro
  scripts in `tool/testing/`; prefer durable tests under `test/`.
- Build, serve or Playwright-smoke the Web chat app only through
  `run_local_e2e.dart` web scenarios or `scripts/build_chat_app_web.sh`; a plain
  `flutter build web` omits the gitignored bridge assets. Check a reused build
  with `scripts/validate_chat_app_web_build.sh`. To run a helper by hand, copy
  what `--dry-run` prints. Keep the required `Web Chat Contract` CI job free of
  large or availability-sensitive remote models.
- Before calling a llama.cpp n-gram speculative output-hash mismatch Dart-only,
  compare the same prompt and sampling settings against upstream `llama-server`.
- Docs: `./tool/docs/build_site.sh` fails on broken links; site code and
  procedure are in `website/docs/maintainers/docs-site.md`.

## Code

- Prefer small, reviewable changes and simple, focused designs without
  meaningful duplication. Add an abstraction only to cut real complexity,
  protect a stable boundary or match a repo pattern; refactor beyond the task
  only when correctness or maintainability needs it.
- Order imports SDK, package, then relative, with a blank line between groups.
  Avoid `show`/`hide` on imports unless resolving a name clash.
- Names: `PascalCase` types; `lowerCamelCase` members, variables and
  constants; `snake_case` files and directories.
- No new TODO/FIXME comments in maintained source or workflow code.
- Public API has explicit parameter, return and field types (locals may infer
  when the type is obvious). Export new public API from `lib/llamadart.dart`,
  or from `lib/backend.dart` when it is backend SPI (custom or fake backends,
  `Backend*` interfaces, engine hooks), with useful `///` Dartdoc and tests;
  implementation stays in `lib/src/`.
  Select platform-specific backends with conditional imports or exports.
- Throw the `LlamaException` hierarchy (`lib/src/core/exceptions.dart`). An
  unsupported platform or option combination throws `LlamaUnsupportedException`
  (or a typed subtype) naming the missing capability, the platform/runtime
  condition and, where known, the required version, or it is explicitly
  disabled and documented. It never reports success.
- When behavior depends on runtime assets, platform, browser APIs or native
  features, prefer an explicit capability probe to a structural or interface
  check, and test both the supported and the unsupported/version-skew path.
- If `test/unit/test_structure/mirrored_unit_structure_test.dart` demands a test
  for a file with no behavior (bare enum, marker interface, `external` interop
  only), add the file to its `behaviorlessSources`. Never assert something true
  by construction; assert wire values where they are consumed
  (`test/README.md`).
- In `lib/src/backends/llama_cpp/`, a native call on a model, context,
  projector or decision-head object that must not race exit teardown goes
  through `LlamaCppObjectCalls` or `ExitTeardownApi`. Teardown waits only for
  those guarded calls; any other call in flight at a direct C `exit()` is
  unprotected (`doc/llama_cpp_exit_teardown.md`).
- In `lib/src/backends/stable_diffusion/`, every native call of an image
  worker goes through `StableDiffusionCalls`, and Dart gives
  stable-diffusion.cpp no callback. A call on an `sd_ctx_t` that can run
  longer than 250 ms needs an `sd_dart_` wrapper in `stable-diffusion-native`
  first (same doc, "Image models").
- Generated files that should not count toward coverage carry
  `// coverage:ignore-file`.
- Tests close the ports, streams and controllers they open.
- Tests that decode on a real model set `numberOfThreads` and
  `numberOfThreadsBatch` (usually 2): the default is up to 4 spin-waiting
  threads, and Dart counts the host's cores, not a container limit or a busy
  shared runner's, so decoding can be tens of times slower. Tests of the
  default path keep it and inject `availableCores`
  (`llama_cpp_service_default_threads_test.dart`).
- A public capability or platform-support change updates README, website
  docs/support matrix, examples and changelog in the same PR.
- Map public capability changes to a validation pack or a reasoned, issue-linked
  exemption in `packages/llamadart_validation/assets/capability_coverage.json`.
  Run `dart test -p vm test/unit/tooling/validation_coverage_test.dart`;
  see the private harness README for the coverage/qualification distinction.
- `skills/` is published to consumers' coding agents: a public API or behavior
  change updates the affected `SKILL.md` in the same PR
  (`test/unit/tooling/package_skills_test.dart` analyzes its examples).
- Keep credentials, tokens, signed URLs and secret-bearing paths out of logs,
  errors, cache keys, metadata and snapshots.

## Ownership

Never patch upstream native or web bridge sources here. Owners:
`llamadart-native` (llama.cpp runtime), `litert-lm-native` (LiteRT-LM runtime),
`stable-diffusion-native` (stable-diffusion.cpp runtime), `llama-web-bridge`
(web bridge), `llama-web-bridge-assets` (published assets).
This repo only consumes them: native hook/config/bindings, and bridge tag
pinning, fetch and runtime wiring
(`website/docs/maintainers/runtime-ownership.md`). Checkouts often keep them as
siblings in `..`; verify the path first. Commit, push and release the change
in the owning repo first, then update pins, hooks, docs and tests here, and run
analyze and the relevant tests before the final commit.

- A WebGPU bridge change is verified across the pinned tag/manifest, direct and
  worker paths, Dart interop, public API, docs and examples together; capability
  floors and changelog entries keep their own versions. Bridge behavior and
  browser-storage durability: `doc/webgpu_bridge.md`.
- Native or web pins, bindings, sync scripts, `hook/`, or companion SwiftPM
  changes: `website/docs/maintainers/native-and-web-sync.md`. Native release
  tags: `latest` accepts only unsuffixed `vMAJOR.MINOR.PATCH`; new nightly
  wrapper rebuilds use `bNNNN-N`, while `bNNNN-llamadart.N` is consume-only;
  nightly cores use canonical decimal spelling, and rebuild counters start at 1
  without leading zeros.

## Changelog and releases

- New entries go under `## Unreleased` in `CHANGELOG.md` and
  `website/docs/changelog/recent-releases.md`. `main` always has that heading,
  empty or not: release prep removes it and `docs_version_cut.yml` restores it
  after the release. Never add to a released section. Move `Unreleased` into a
  version only in an explicit release task.
- Both changelogs union-merge (`.gitattributes`), so a rebase never conflicts
  there but can move bullets silently; CI fails a non-release-prep PR that
  changes a released section. Release prep turns union off first
  (`website/docs/maintainers/release-workflow.md`).
- One short user-facing bullet per change; implementation detail and migration
  notes go in the PR or maintainer docs.
- When release prep moves `Unreleased` into a version, compact it in both
  files: merge related or follow-up bullets, drop duplicates and items users
  cannot observe, and tighten wording. Released sections stay as published.
- Every release stays recorded: `CHANGELOG.md` from 0.10.0 on, older ones
  verbatim in `doc/changelog_archive.md`. pub.dev rejects a `CHANGELOG.md`,
  `README.md`, `LICENSE` or example file over 256 KiB, and
  `verify_release_docs_versions.dart` fails first; to make room, move the
  oldest `CHANGELOG.md` sections unchanged to the top of the archive's
  releases. The docs changelog
  (`website/docs/changelog/recent-releases.md`) keeps only `Unreleased` and the
  current and previous minor, and links `CHANGELOG.md` for older ones: when
  release prep opens a new minor, delete the minor two back from it (`0.18.0`
  keeps `0.18.x` and `0.17.x`). `verify_release_docs_versions.dart` fails on
  older sections. The released-section check lets only that page lose whole
  sections from its tail, and `CHANGELOG.md` only move them to the archive.
- Before release prep or a change to current install snippets, run
  `dart run tool/testing/verify_release_docs_versions.dart`, then again with
  `--release-prep`; resolve pending companion bumps in the release-prep PR.
- Apple companions constrain `llamadart` to the core minor
  (`'>=M.m.0 <M.(m+1).0'`), so automation publishes the core before them. A
  core minor bump re-releases every companion. A patch repin needs explicitly
  verified older-companion compatibility and a new companion floor excluding
  older rejecting cores. Release prep checks both directions from full tag
  history; see `website/docs/maintainers/native-and-web-sync.md`.
- Companion versions share the core `MAJOR.MINOR` and move their patch
  independently: core `0.13.0` ships every companion at `0.13.0`. The release
  docs verifier enforces this from core `0.13.0`. A companion-only release
  still needs a new core version.
- Never push release tags by hand unless release automation is disabled,
  blocked or being repaired. Give each new release-sensitive path a
  `.github/CODEOWNERS` entry. Release work follows
  `website/docs/maintainers/release-workflow.md`.

## Pull requests

- `main` stays production-ready. The PR body follows
  `.github/pull_request_template.md`; fill every section or mark it N/A with a
  reason.
- Update an open PR branch only through `tool/git/safe_pr_head_update.dart`
  (expected-head CAS, fast-forward only); writers it cannot govern are in
  `doc/pr_branch_writer_inventory.md`. Whenever the head moves, earlier CI runs,
  approvals, audits and matrix evidence no longer count: rerun or re-request
  them against the new head and update the PR body.
- Before merge, reply to every review thread, with concrete rationale when not
  acting on it, and resolve it.
- Classify every PR with
  `git diff --name-only --no-renames <base>...HEAD | dart run tool/testing/classify_high_risk_changes.dart`.
  Before a high-risk PR is marked ready, an independent auditor runs a
  blocking-only adversarial review of the exact head against the current base.
  The auditor is an operator or a fresh agent session that took no part in the
  implementation, never the PR author.
  Build the evidence per `doc/high_risk_pre_merge_readiness.md` and check it
  with `tool/testing/high_risk_readiness.dart` against
  `tool/testing/high_risk_readiness_evidence.schema.json`; a valid local run
  exits 2 (`unverifiedPrerequisites`). Mark ready only with
  zero known PR-caused P1 regressions and zero unresolved review threads,
  recorded in the PR's high-risk block and the evidence.
- Use the closest affected-family model or artifact; if its weights are
  unavailable, name each unavailable family and use primary upstream emissions
  plus durable fixtures. An unrelated model is pipeline-only evidence.
- Several PRs may land as one batch integration PR. High-risk constituents are
  audited at their own exact head as above and standard-risk ones pinned at the
  head whose CI passed; they are then combined on a new branch cut from current
  `main`, one commit per PR, and landed with a rebase merge, never squash. A
  constituent audit lets its diff land through a batch
  only together with a passing integration audit of the integration head.
  Dropping or replacing a constituent, or `main` moving, means
  a new integration branch and PR.
  Procedure: `doc/high_risk_pre_merge_readiness.md`, "Batch integration PR".
- Post-merge QA is still required but is never the first adversarial pass. When
  the merged tree equals an audited head, it need not repeat checks the
  independent audit already ran on that head. If it finds a PR-caused P1, stop
  lower-priority merge work, file a causally accurate issue, and prepare one
  cohesive recovery before resuming feature work.

## Writing for people

PR bodies, issues, comments, review replies, commit messages, changelog
entries, docs and code comments are read by people. Keep them concise: lead
with the outcome, say each thing once, and cut narration, restated context and
boilerplate. Put bulky evidence (logs, matrices, mutation lists) in a table or
a linked artifact, not prose. Code comments explain why (a non-obvious
constraint or trade-off), never what the code does.

## This file

When a task reveals a durable rule that changes agent behavior and that no
tool, test or linked doc covers, add it here. Point to docs instead of copying
them, delete stale rules, and leave out incident history. Tests pin some
phrases here; Markdown changes select the root tests in
`tool/ci/markdown_test_suites.txt`. After editing, run
`dart test -p vm test/unit/tooling/`.
