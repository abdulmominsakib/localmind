## Summary
-

## Production-readiness scope
- **User-facing scope:** <!-- What can users do after this merges? -->
- **Supported platforms/paths:** <!-- Native/WebGPU/Flutter app/docs-only/etc. -->
- **Unsupported or intentionally unavailable paths:** <!-- Include the error, disabled UI, or fallback users see. Do not silently succeed. -->
- **Out of scope / follow-ups:** <!-- Link GitHub issues for non-blocking future work, or write "None". -->

## Completeness checklist
- [ ] Declared scope is fully implemented, or explicitly reduced above.
- [ ] Unsupported platform/option combinations fail loudly with actionable diagnostics or are clearly documented as unavailable.
- [ ] Public API docs, README/website docs, examples, support matrices, and changelog entries are updated where relevant.
- [ ] Regression coverage covers the original issue plus key negative/version-skew paths where relevant.
- [ ] Public capability changes update the validation coverage registry with a pack or a reasoned, issue-linked exemption; inventory checks pass (or N/A with scope).
- [ ] Security/privacy review completed: no secrets, bearer tokens, signed URLs, or raw secret-bearing paths leak through logs, cache keys, metadata, errors, or snapshots.
- [ ] Follow-up work that is useful but not required for this PR is tracked in GitHub Issues, or explicitly marked "None" above.

## PR type guidance
<!-- Keep the relevant line(s), or mark N/A with a short reason. -->
- **Feature PR:** include API/docs/example updates, platform matrix, unsupported-path behavior, and tests for both happy and negative paths.
- **Bugfix PR:** include the regression root cause, targeted regression test or documented reason one is impractical, and affected platform matrix.
- **Docs-only PR:** confirm no runtime behavior changes and note any commands used to validate docs links/builds.

## Test Plan
<!-- Mark commands as N/A with a short reason for docs-only/template-only changes. -->
- [ ] `dart run tool/prepare_workspace.dart`
- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `dart analyze`
- [ ] `dart test -p vm -j 1 --exclude-tags local-only`
- [ ] `dart test -p chrome --exclude-tags local-only` <!-- N/A with reason if not relevant -->
- [ ] `coverage-lib` matrix row when `lib/` behavior changes <!-- PR CI skips coverage; main enforces the 70% threshold after merge. N/A with reason otherwise -->
- [ ] Other targeted/local-only validation: <!-- Use `dart run tool/testing/test_matrix.dart --list` and `dart run tool/testing/run_local_e2e.dart --list`; e.g. Web mock smoke, WebGPU smoke, Flutter app E2E, docs build, N/A -->

## Matrix Evidence
<!-- Generate rows with `dart run tool/testing/test_matrix.dart --pr-template`; keep applicable rows and mark skipped rows N/A with a concrete reason. -->
| Matrix row | Scope covered | Platform / model / backend | Result | Evidence / notes |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

## Review Notes
- Independent review status: <!-- reviewer/tool/verdict, or N/A for trivial docs-only changes -->
- CI status / head SHA: <!-- fill after CI runs -->

## High-risk regression review
<!--
Use this section when production changes touch parsers, grammars, streaming
protocols, backend/runtime routing, capability probes, artifact consumers,
release automation, or this review policy. Classify changed paths with
`tool/testing/classify_high_risk_changes.dart`, then run
`dart run tool/testing/test_matrix.dart --tier high-risk` and follow
`doc/testing_matrix.md`. The independent QA task must be separate from the
implementation task and must review the exact PR head against the current base.
Do not mark ready with a known PR-caused P1 or an unresolved review thread.
For standard-risk PRs, leave the classification as `standard` and mark the
remaining rows N/A.
-->
- **Classification:** standard
- **Implementation task:** N/A
- **Independent blocking QA task:** N/A
- **Exact head / current base:** N/A
- **Production-branch deletion, bypass, or miswire proof:** N/A
- **Affected-family real-model/artifact evidence:** N/A
- **Explicit unavailable-family or other N/A evidence:** N/A
- **Known PR-caused P1 regressions:** 0
- **Unresolved review threads:** 0
