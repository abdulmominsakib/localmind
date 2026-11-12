# High-Risk Pre-Merge Readiness Contract

This document defines the repository-local contract for issue #419 and the
external controls that are still required before it can enforce merge
readiness.

## Current status

The repository currently provides:

- a strict evidence schema;
- a read-only Dart evaluator bound to independently supplied repository, PR,
  author, head, and base values;
- a Git-derived name-status inventory that preserves deletions and both sides
  of renames;
- candidate-tree checks for relevant production tests;
- a trusted-default-branch GitHub Actions advisory.

It does **not** provide an authenticated GitHub App publisher, protected
environment provenance, conditional ruleset enforcement, or an authenticated
independent-auditor identity. Consequently:

- a valid local high-risk evaluation returns
  `unverifiedPrerequisites` and exits 2;
- no local JSON field, command-line flag, process environment variable, or
  credential-shaped value can produce an operational-ready result;
- the advisory workflow reports that limitation instead of enforcing it, and
  must not be selected as a required status check;
- high-risk merge readiness is established by manual repository-local review and
  evidence, which is how issue #419 was closed as completed.

Protected external enforcement is intentionally unconfigured and is not a
pending merge requirement. Adopting it would need a separate approved
governance change satisfying the boundary in
[Missing external prerequisites](#missing-external-prerequisites).

## Threat model

The contract fails closed against:

1. stale or mismatched repository, PR, author, head, or base claims;
2. self-approval and the retired standalone `qa` identity;
3. duplicate JSON keys, unknown fields, wrong scalar/container types, and
   caller-declared decisions;
4. caller-forged changed-file lists;
5. deleted, renamed-old, unproven existing, absolute, traversal, wildcard, non-test, or
   phantom evidence paths;
6. boolean-only structured-output attestations without named production tests;
7. PR-authored workflow or evidence execution;
8. ordinary environment variables masquerading as protected App provenance.

## Evidence document

The canonical schema is
`tool/testing/high_risk_readiness_evidence.schema.json`.
Input documents set `evaluation` to `null`. The evaluator owns that field and
replaces it with its decision, failure classification, exact changed-file
inventory, diagnostic, and external-prerequisite state.

The input binds:

- `repository`, `pr_number`, `pr_author`;
- `expected_pr_head_sha` and `current_base_sha`;
- `classification` and the exact classified `surfaces`;
- the exact required matrix row IDs and matching row evidence;
- an independent audit record for high-risk changes;
- relevant production tests under `test/**/_test.dart` (or an explicitly paired
  Python suite, below), with causal evidence;
- structured-output coverage and affected-family evidence when applicable.

The evaluator rejects missing and unknown keys at every object level. Lists
must contain correctly typed, non-empty, unique values. SHAs are nonzero,
lowercase, full 40-character SHA-1 values. Timestamps are RFC 3339 UTC strings.
Repository names, GitHub authors, correlation IDs, and auditor identities have
bounded character sets.

### Exact changed-file and tree binding

The CLI never accepts `changedFiles` from JSON or a command-line option. It
derives the inventory with:

```bash
git diff --name-status -z --find-renames <base>...<head>
```

Both commits must exist and the base must be an ancestor of the head. Rename
source and destination paths are both classified. Every cited test must:

- be a normalized, wildcard-free repository-relative `test/**/_test.dart` path
  or one of the explicitly paired Python suites listed below;
- not be deleted or the old side of a rename;
- resolve literally to one regular blob in the exact candidate tree via
  `git ls-tree`.

Changed and unchanged tests follow the same evidence rule. `test_evidence` is
keyed by exactly `affected_test_paths`. Each record names the test case and a
literal test callsite snippet, inspected production references (`path`, `snippet`),
the test command, `head_result: pass`, `control_result: fail`, `control_kind`
(`before-fix` or `mutation`), control description, and evidence notes linking the
observed results. The independent reviewer checks that the case really reaches
the affected branch and that the failure is causal, not a setup error. Every
changed production path under `lib/`, `tool/`, `hook/`,
`packages/genkit_llamadart/lib/`, `.github/workflows/`, or `.github/actions/`
needs this coverage unless it is
[proven comment-only](#comment-only-production-changes). Workflows and composite actions count because the
classifier treats each one as high-risk and the tooling tests that load them
are their only durable proof; no other `.github/` or policy path is a
production reference. The independent Genkit
package may cite its own `packages/genkit_llamadart/test/**/*_test.dart` files;
the same exact-blob, callsite, causal-control and structured-output obligations
apply. The private validation harness additionally admits only
`packages/llamadart_validation/lib/` and the exact
`packages/llamadart_validation/assets/capability_coverage.json` registry as
production references. Every changed path in that bounded set needs coverage.
Its `packages/llamadart_validation/test/**/*_test.dart` tests may cite only
harness production references; harness references may be cited only by those
package tests or `test/unit/tooling/**/*_test.dart` tests. This pairing admits
paths, not a caller assertion of reachability: the independent reviewer still
inspects the actual callsite and causal control. The registry's literal JSON
snippet must occur in its exact candidate blob, like any source reference.
This does not admit other harness assets or arbitrary package paths, or relax
compiled-grammar, independent-audit or external-authentication requirements.

The exact root `ffigen.yaml` is an artifact-consumer production reference,
paired only with
`test/unit/tooling/native_bindings_generator_policy_test.dart`. That test reads
the actual YAML through the locked ffigen configuration and AST transformer;
it does not invoke the native header-sync shell script. Its evidence must
reference only `ffigen.yaml`, present at the exact head, with the real case,
callsite, config snippet and observed causal control. Changed config coverage
is required. A deleted or renamed-away config cannot use this pairing. Other
root configs and policy files remain outside production-reference admission.
This bounded pairing changes no audit, caller-binding or external-prerequisite
requirements; the reviewer still verifies actual producer reachability.

Changes to the following scripts may cite the Python suites CI runs
directly, each only with its paired script in `production_refs` and a
`command` that names the suite (path or dotted unittest module):

| Suite | Paired script |
| --- | --- |
| `tool/native/test_native_header_archive.py` | `tool/native/native_header_archive.py` |
| `tool/native/test_sync_native_headers_and_bindings.py` | `tool/native/sync_native_headers_and_bindings.sh` |
| `tool/native/test_sync_native_release_pins.py` | `tool/native/sync_native_release_pins.py` |
| `tool/native/test_sync_stable_diffusion_bindings.py` | `tool/native/sync_stable_diffusion_bindings.py` |
| `test/ci/test_nonpublishing_auth_probe.py` | `tool/release/nonpublishing_auth_probe.py` |

Every other path rule, case/snippet and causal-control obligation applies. Other
Python files are rejected regardless of name or extension. Everything under
`tool/` counts as production, so a PR that also changes a suite or files under
`tool/native/fixtures/` must list each of them in `production_refs`; otherwise
it fails with "Some changed production paths lack reviewed test reachability".

The evaluator verifies named cases/snippets against exact Git blobs and rejects
missing or disconnected references. A literal match does **not** establish a
callgraph, execute tests, authenticate logs, or prove independence. The existing
independent audit must inspect those semantics and results; do not invent a
record for tests that were not run. Unknown or unproven reachability blocks the
review even if local JSON validation succeeds. No new approval identity is added.

### Comment-only production changes

A changed production path needs no `test_evidence` coverage when Git proves
the edit comment-only. When every changed production path is proven,
`affected_test_paths` and `test_evidence` may be empty. There is no caller
flag: the evaluator derives the proof from the exact base and head blobs
(`isCommentOnlyDartChange` in `tool/testing/high_risk_readiness.dart`).

A path qualifies only if:

- it is a `.dart` production path changed in place (`M`, no rename or copy)
  and a regular non-executable blob at both revisions;
- both revisions parse without diagnostics and scan to identical tokens, type
  and lexeme, so string contents, directives, annotations, imports, exports and
  the script tag are compared;
- whitespace changes only between two tokens whose comments changed, and the
  later token starts its line in both revisions: edited comments are full-line
  or trailing, never inline before code;
- every comment added, removed or moved is plain prose or Dartdoc. It contains
  no control, invisible or bidirectional character and no tool marker:
  language version (`// @dart`), `@docImport`, Dartdoc directives (`{@...}`,
  `@nodoc`, any `@name`), `ignore:`/`ignore_for_file:`, `coverage:`,
  `dart format`, excerpt regions (`#docregion`, any `#name`) or a security or
  lint suppression (`nosemgrep`, `nosec`, `NOSONAR`, `lgtm`, `codeql`, `noqa`,
  `nolint`, `expect_lint`, `pragma` and similar). An unchanged
  `ignore_for_file:`, `coverage:ignore-file` or `// @dart=` comment may precede
  an edited one at the same token; any other marker there fails closed;
- the file is not generated: no `.g`, `.freezed`, `.mocks`, `.gr` or protobuf
  suffix, no comment before the first token mentioning `generated` (including
  `@generated`) or `do not edit`/`do not modify`, and no comment anywhere that
  starts with `AUTO GENERATED`, `GENERATED FILE/CODE`, `Generated by`,
  `Code generated` or `DO NOT EDIT`;
- the file is not in `rawTextConsumedSources`: production sources whose raw
  text, comments included, repository tooling reads with regular expressions.
  These are the release pins (`lib/src/hook/native_release_pins.dart`, read
  by the release-docs verifier, the WebGPU bridge tag check, validation
  bundles and the native sync scripts), `lib/src/web_setup/web_bridge_setup.dart`
  (bridge tag check), and `lib/src/backends/litert_lm/litert_lm_runtime.dart`
  and `hook/build.dart` (rewritten by `sync_native_release_pins.py`). A
  commented-out pin there can change what a CI gate or sync script reads. A
  test fails if a listed path disappears; add any new raw-text reader's source
  to the list.

Code inside doc comments is inert and qualifies. Anything else, including
malformed source, an unreadable or non-UTF-8 blob and non-Dart paths, keeps
the ordinary causal-test requirement. The proof covers compiled behavior:
stack-trace line numbers can still shift, and tooling that reads source text
is handled only by the list above. `check_platform_boundaries.dart` also
scans raw lines for directives; because no edited comment can precede code on
its line, a comment edit can only add a violation there, never hide one.

The route changes only that coverage obligation. Classification, surfaces,
matrix rows, the exact-pair independent audit and the zero-P1 and
zero-thread gates are unchanged. A comment-only structured-output path keeps
its minimum impacts, coverage axes and family evidence, and impact review must
still cite it. Other changed production paths in the same PR still need
coverage. A cited test may still reference only comment-only paths and must
pass every existing check. A PR with no changed production path at all still
cites a relevant test.

### Schema migration

New evidence uses `schema_version: 2.0.0`. The current evaluator rejects v1;
changing its version string is not migration. Re-review the exact head/base and
supply impact decisions plus test relevance/causal observations. The frozen
`high_risk_readiness_evidence.v1.schema.json` is retained only for historical
report readers. Consumers must select the schema by version; archived v1 output
is never current readiness evidence. The repository advisory workflow does not
consume evidence JSON and is unchanged. Standard-risk and release-metadata v2
records set `test_evidence` to `{}`; the bounded release route remains unchanged.

### Core-patch release metadata evidence

A release-only PR remains **high-risk / artifactConsumer**. It can additionally
declare the `release-metadata-verification` matrix row, with this exact command
and a `pass` result (never `notApplicable`):

```bash
dart run tool/testing/verify_release_docs_versions.dart --release-prep && dart test -p vm -j 1 test/unit/tooling/verify_release_docs_companion_pins_test.dart
```

For this route, `affected_test_paths` must name exactly that existing test.
The independent audit and both matrix rows remain required and are bound to
the exact head and base. This records an existing release regression suite,
not a fabricated newly changed test. The evaluator does not execute candidate
scripts and cannot authenticate a claimed test run; the independent reviewer
must inspect the exact-head command/log evidence.

Eligibility comes from literal Git blobs and the complete rename-aware diff,
not a `metadata_only` flag or a caller-provided inventory:

- `pubspec.yaml` changes only its canonical stable version to the next patch;
  every other byte, including dependencies, SDK, hooks and overrides, is fixed.
- Both current changelogs and the four maintained installation README/docs
  pages are modified. Historical numbered changelog sections, runtime identity
  identities, frontmatter and already-prepared companion constraints remain
  unchanged; current core snippets name the new patch. Mutable release prose
  must be inactive Markdown with no MDX expressions/imports/exports or HTML
  outside inert code examples. Executable `mdx-code-block` fences are rejected.
  Historical changelog tails are excluded from that syntax check only after
  proving byte equality. Narrative prose still needs independent review.
- All three generated consumer locks are required: `example/chat_app/pubspec.lock`,
  `packages/llamadart_validation/pubspec.lock` and
  `website/examples/observability/pubspec.lock`. Each changes only the matching
  local `llamadart` version. The first two resolve `../..`; observability
  resolves `../../..`. Path source, relative flag, inventory, hashes, SDK and
  all other bytes remain identical. Pub must generate every lock normally.
- All changed paths are existing non-executable regular files; additions,
  deletions, copies, renames and mode changes are excluded.
- The existing release verifier and named regression test are unchanged
  regular blobs at both revisions.

The exact allowlist lives in `tool/testing/release_metadata_readiness.dart`.
Companion version changes, runtime pins, generated bindings, hooks, SwiftPM,
workflows, security/review policy, other docs/MDX and production changes cannot
use this exception. Broader release changes use the ordinary relevance-and-causal-evidence
contract instead of expanding this route implicitly.

An internally consistent release evaluation still returns
`unverifiedPrerequisites` (exit 2), never operational readiness. External
authentication/publication/ruleset boundaries below are unchanged.

### Independent audit

High-risk evidence requires an audit whose head and base exactly match the PR
context, whose decision is `accepted`, and whose known PR-caused P1 regression
and unresolved-thread counts are both zero. The auditor must differ from the PR
author and must not use a retired `qa` identity. A Codex session records
`audit_kind: codex-adversarial`; an operator or any other fresh agent session
records `operator-owned`. `auditor_identity` and `summary` name the reviewer
that actually ran.

These repository-local checks establish internal consistency only. They do not
authenticate the auditor. That requires the missing external boundary described
below.

### Structured-output proof

`structured_output_evidence.impacts` accounts for all three impacts. Each entry
contains `applicable`, a nonempty independently reviewed `rationale`, and
`production_refs` with exact source paths/snippets. The existing audit binds
these observations to the exact head/base and rejects author self-approval.
All changed production paths must be inspected. Deleted source and the old side of a rename are read at base. Both sides of
a rename contribute impacts; a copy source does not.

| Impact | Required coverage axes |
| --- | --- |
| `inputRenderingHistory` | `input_rendering_history`, `upstream_parity` |
| `outputParsingStreaming` | `schema_reconstruction`, `streaming_rollback`, `tool_choice_thinking`, `upstream_parity` |
| `grammarSchema` | `compiled_grammar_acceptance`, `compiled_grammar_rejection`, `schema_reconstruction`, `tool_choice_thinking`, `upstream_parity` |

All seven coverage keys are present. An inapplicable axis may have an empty
list; applicable axes must cite reviewed tests. Rendering evidence checks byte,
role, content, history and typed tool-result preservation. Parser evidence checks
schema-directed scalars/containers, incomplete-stream suppression, malformed-final
rollback and `auto`/`required`/`none` with thinking prefixes. Grammar evidence must
exercise compiled valid and malformed/unknown/missing/wrong-type shapes.
Acceptance/rejection still cite a maintained compiled production grammar test:

- `test/integration/core/grammar/generated_tool_schema_grammar_test.dart`; or
- `test/e2e/template/specialized_tool_grammar_validation_e2e_test.dart`;
- `packages/genkit_llamadart/test/integration/genkit/plugin/real_model_constrained_grammar_test.dart`; or
- `packages/genkit_llamadart/test/integration/genkit/plugin/real_model_rich_tool_schemas_test.dart`.

The adapter suites compile serialized tool/response schemas with the native
sampler and test accepted and rejected token sequences. They require the pinned
Qwen3 fixture; an optional-fixture skip is not passing model evidence. This keeps
adapter tests independent of core's dependency graph without accepting arbitrary
package tests as compiled grammar proof.

Path hints establish conservative minimum impacts. The render-context boundary
is rendering/history; dedicated PEG execution/fallback parse files are parsing/streaming;
grammar files are grammar/schema; shared tool-schema utilities and parser builders stay conservative. Shared handlers, shared
utilities, unknown paths, and evidence-only changes require all impacts. A mixed
change unions its impacts. Test filenames do not add runtime effects to a known
production change. Hints cannot prove the absence of indirect effects: the
independent reviewer must add any further affected impacts, and only exclude an
impact after inspecting its production callsites. A minimum impact cannot be
excluded. No empty rationale or blanket author-authored N/A is sufficient.

One bounded Git-derived refinement applies to `lib/llamadart.dart`: adding
exactly the explicit `show ImageEditingPixels, ImageEditingRequest` export from
`src/core/image/image_editing_request.dart` may contribute no minimum chat
impacts. It remains high-risk and `structuredOutput`; all three independently
reviewed impact decisions, exact production references, causal image and public
export test evidence, matrix rows and exact-head/base audit remain required.
The evaluator supplies no caller exemption flag or schema waiver.

The addition must be a real parsed directive, and removing its exact bytes must
recover the base barrel byte for byte. Both barrels and the new target must be
non-executable regular Git blobs; the target must be newly added with the two
named final classes and the bounded recipe helper. Its four unconditional,
unprefixed imports must already load through the old barrel at both revisions.
The evaluator traverses the base barrel at both revisions: its bytes are exactly
the head barrel with only the proven added directive removed. No other edge is
skipped, including pre-existing or indirect references to the target. Every
conditional branch is inspected and `show`/`hide` filters are conservatively
ignored. At base the two new identifiers must be absent from all parsed source
tokens. At head, exhaustive AST declaration names reject collisions while
allowing existing image methods to reference the new types; unknown declaration
nodes or name shapes retain conservative minima. Comments and string contents
do not count as identifier tokens. Unknown syntax, graph cycles, parts,
missing/nonlocal export sources, additional declarations/imports, modified existing exports, different
names or URIs, conditional additions, renames and mode changes retain ordinary
conservative minima. Every other changed structured production path, including
rename origins, still contributes its normal impacts. Evidence-only emptiness
still requires all impacts; proven empty contribution is a distinct case.

Namespace extraction uses stable AST keyword tokens for class, enum and
extension-type names across the allowed analyzer range. To qualify cached older
and current dependency graphs without editing the checkout's pubspec or lock:

```bash
LLAMADART_ANALYZER_COMPATIBILITY_VERSIONS=8.0.0,8.4.1,14.6.0 \
  dart test -p vm -j 1 --run-skipped -t local-only \
  test/unit/tooling/high_risk_readiness_test.dart \
  --plain-name 'readiness AST supports explicitly requested allowed analyzer versions'
```

This opt-in test resolves the full root dependency graph offline in scratch
packages and checks CLI compilation plus the namespace and comment-only
regressions. Missing
requested cached dependencies fail qualification; a skipped test is no proof.

This proof bounds the additive namespace and existing loading dependencies; it
does not prove an absence of behavioral or transitive effects. The independent
reviewer still inspects the new classes, their production callsites and every
other changed production source, adds any affected chat impact and supplies the
corresponding coverage. An internally consistent result still exits 2 for the
unconfigured external prerequisites; it never establishes operational readiness.

The `families` list retains unique `tested`/`unavailable` entries, relevant tests
and a rationale. Missing weights require named unavailable families and primary
upstream emissions plus fixtures; unrelated model evidence remains pipeline-only.

For the original rendering-only #529 fix, `TemplateRenderContext.messagesForTemplate`
normalizes typed incoming tool results. A review of its handler callsites can
exclude emitted parsing and grammar enforcement. Relevant existing tests can be
used if they actually exercise that conversion and fail before the fix or under
a targeted bypass. Existing tests that never cover typed results are insufficient;
add a focused rendering regression in that case. No unrelated compiled-grammar
edit is required. This policy example is not a claim that historical #529 had
already supplied v2 causal evidence or an authenticated audit.

## Batch integration PR

Whenever a PR head moves, earlier CI runs, approvals, audits and matrix
evidence no longer count. Landing N high-risk PRs one at a time therefore
costs N rounds of merging `main` in, re-audit, CI and post-merge QA. A batch
integration PR is the allowed alternative. It changes nothing for a PR that
lands on its own.

A release-prep PR is never a constituent, and the integration PR never carries
the `release-prep` label or a `release/prep-*` branch name.

1. **Constituent gates.** Each constituent PR first passes its own pre-merge
   gate at its own exact head, exactly as if it were landing alone.
   - A high-risk constituent has its [independent audit](#independent-audit)
     at that head: blocking-only, by an auditor who took no part in the
     implementation, with decision `accepted`, zero known PR-caused P1
     regressions and zero unresolved review threads.
   - A standard-risk constituent is pinned at the exact head whose CI passed.

   A constituent whose head moves afterwards passes its gate again at the new
   head before it joins a batch.
2. **Integration branch.** Cut a new branch from current `main` and add the
   constituents as one commit each, so each stays individually revertable.
   Each commit subject ends with `(#<constituent PR number>)`. Resolve
   conflicts once, inside the commit of the constituent being applied. Publish
   the branch through `tool/git/safe_pr_head_update.dart`.
3. **Conflict resolutions.** A resolution only reconciles hunks that two sides
   both changed: a real merge conflict, or the mechanical union of changelog
   or doc lines. Anything else, including a fix for a defect found in a
   constituent, goes back to that constituent's PR and is re-audited there.
4. **Integration PR body.** Besides the normal template, it lists:
   - for every constituent, its PR number, risk class, pinned head SHA and
     audit result (or the passing CI run for a standard-risk one);
   - every conflict resolution, listed per hunk, not per file;
   - the closing keywords (`Closes #N`) of every constituent, because a PR
     that is closed without merging does not close its issues.
5. **Integration audit.** One independent auditor reviews the integration PR's
   exact head against current `main`, blocking-only. The auditor took no part
   in implementing any constituent or in the integration; having audited a
   constituent does not disqualify. The audit checks only what is new:
   - the tree is a clean combination of the pinned heads plus the listed
     resolutions and nothing else: each commit's diff matches
     `git diff main...<pinned-head>` of its constituent, for audited and
     standard-risk constituents alike, and every difference is a listed hunk;
   - each listed resolution, reviewed as a change in its own right;
   - the full default suites and the relevant real-model smokes pass on the
     combined tree;
   - the readiness evidence is valid for the integration head (below).

   A constituent audit lets its diff land through a batch
   only together with a passing integration audit of the integration head. It
   stays valid for landing that PR alone at its audited head against the base
   it was audited on, under the normal single-PR rules.
6. **CI** runs once, on the integration head.
7. **Review threads.** Before the merge, every review thread on the
   integration PR and on every constituent PR is replied to and resolved. The
   live unresolved count per constituent, which must be 0, is recorded in the
   integration PR body at merge time.
8. **Merge** with a rebase merge, never squash, so `main` stays linear and
   keeps one commit per constituent. Only then close each constituent PR with
   a link to the integration PR.
9. **Post-merge QA** runs once for the batch. See
   [Post-merge QA scope](#post-merge-qa-scope).

### When the batch has to change

`tool/git/safe_pr_head_update.dart` is fast-forward only, so the integration
branch can only gain commits. Appending a constituent moves the integration
head, so its audit, CI and evidence are redone. Each of these needs a
new integration branch and PR cut from current `main`, and the old integration
PR is closed:

- dropping a constituent;
- replacing a constituent's commit after that constituent was fixed and
  re-audited in its own PR;
- `main` moving after the branch was cut.

The integration branch never takes a history rewrite, a revert commit or a
merge-from-`main` commit. If the integration audit finds a problem caused by
one constituent, that constituent is either fixed in its own PR or dropped;
both lead to a new integration branch. Its audit, CI and evidence are done
against the new integration head; the gates of the untouched constituents
still stand. A PR-caused P1 found in post-merge QA is handled as for any other
merge.

### Evidence for the integration head

The integration PR is an ordinary PR to the evaluator. Its evidence document
binds the integration PR number, author, exact head and current base; its
`independent_audit` is the integration audit; and its surfaces, matrix rows,
impacts and `test_evidence` cover the whole combined diff, which the evaluator
derives from Git as usual. That includes `test_evidence` controls for the
changed `lib/`, `tool/` and `hook/` paths of standard-risk constituents, which
had none of their own. Each high-risk constituent keeps its own evidence
document for its own audited head.

A `test_evidence` control (`control_result`) observed on a constituent's
audited head may be carried over only when every `production_refs` path and
the cited test file are identical on the integration head:

```bash
git diff --exit-code <audited-head> <integration-head> -- <paths>
```

Take the paths from the evidence and check that each exists at both commits; a
mistyped path prints nothing. Re-observe the control on the integration head
when the files differ, or when another constituent, or `main` since the
constituent's audited base, changed anything the test runs through. A cited
`local-only` test is always re-run on the integration head.

The schema has no field for constituent PR numbers, pinned heads, audit
results or conflict resolutions. Those live in the integration PR body, and the
integration audit's `summary` names the constituents it verified. The
readiness tool therefore cannot check the clean-combination claim; it rests on
the integration auditor.

## Post-merge QA scope

Post-merge QA is still required and is never the first adversarial pass. When
the merged tree equals an audited head, it need not repeat checks the
independent audit already ran on that head. Compare the tree of the commit
`main` points to once the merge lands (after a rebase merge, the last rebased
commit) with the audited head's tree:

```bash
git rev-parse <main-after-merge>^{tree} <audited-head>^{tree}
```

QA is then limited to what cannot be checked before merge: workflow runs on
`main`, deployed demos and anything else environment-specific. Local suites
are not repeated. When the trees differ, the checks run on the audited head do
not carry over.

## CLI

```bash
dart run tool/testing/high_risk_readiness.dart \
  --evidence /path/to/evidence.json \
  --repository leehack/llamadart \
  --pr-number <number> \
  --head-sha <observed-pr-head> \
  --base-sha <observed-pr-base> \
  --pr-author <observed-author>
```

The binding values must come from an independent source such as a read-only
GitHub API query. Repeating values copied from the evidence file checks
consistency but does not create trust.

For `--pr-author` and `pr_author`, use the PR's REST `user.login`
(`gh api repos/<owner>/<repo>/pulls/<number> --jq .user.login`). Bot authors
keep their `[bot]` suffix, so `github-actions[bot]` and the human
`github-actions` are different authors. `gh pr view` reports bots as
`app/<slug>`; never strip that prefix or add a suffix by hand. Matching is
case-insensitive, and the output keeps the supplied spelling. Accepting bot
logins grants no auditor authority: auditor identities and self-approval
checks are unchanged.

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Standard-risk diagnostic only. |
| 1 | Evidence or repository-state rejection. |
| 2 | High-risk evidence is internally consistent, but external prerequisites are unavailable. |
| 64-66 | CLI usage, JSON, or file error. |

`--schema` prints the schema. There is deliberately no App credential,
environment trust, supplied changed-file inventory, or `ready` option.

## Trusted-default-branch advisory workflow

`.github/workflows/high_risk_readiness.yml` runs under
`pull_request_target` but checks out only the immutable `github.sha`
revision that supplied the trusted default-branch workflow, with credential
persistence disabled. It has no branch-selectable manual-dispatch trigger. The
workflow grants read-only contents and pull-request permissions, validates the
PR number, fetches metadata/files through the read-only GitHub API, verifies the
complete paginated file count, rejects ambiguous control-character paths, and
classifies both current and previous rename paths.

It does not check out or execute the PR branch and does not consume PR comments,
PR-authored evidence files, workflow artifacts, or PR-authored workflows.

- Standard-risk changes receive a successful, explicitly non-required advisory.
- High-risk changes succeed with a `::warning` and a job summary stating that
  the protected publisher is absent, so readiness must be established by the
  repository-local review, evaluator run, and independent audit described above.
- Invalid PR metadata, GitHub API failures, incomplete or ambiguous file
  inventories, head/base/changed-file drift, and classifier failures still exit
  nonzero.
- No failure is hidden with `|| true`, and no advisory evidence payload is
  fabricated.

The workflow name and job name intentionally say `advisory`. It is not a
required check, so it deliberately does not fail merely because the protected
publisher was never adopted; that absence is reported, not enforced.
Configuring it as a required check could make standard-risk PRs depend on a
gate that is not intended for them.

## Missing external prerequisites

Repository administrators must not add credentials or a required check until a
separate reviewed implementation supplies all of these controls:

1. A dedicated GitHub App installed only on `leehack/llamadart`, with
   read-only contents/pull-request access and only the minimum permission needed
   to publish its own check.
2. A protected execution environment whose branch/actor controls are verified
   independently of ordinary process environment variables.
3. An evidence ingress controlled by the App. PR bodies, comments, PR-authored
   files, PR workflow artifacts, and caller-provided environment values are not
   acceptable trust roots.
4. Authenticated creator binding for the independent auditor, with proof that
   the actor differs from the PR author and is not the retired `qa` identity.
5. Live read-only queries for repository, PR, author, exact head/base, changed
   files, and unresolved review threads immediately before publication.
6. Evaluation using a reviewed immutable revision from the default branch, not
   a mutable PR checkout.
7. Publication bound to the exact head SHA, with stale/pending conclusions
   superseded promptly when head, base, evidence, or review state changes.
8. A tested enforcement design that blocks only classified high-risk changes.
   GitHub required-check behavior must be validated before activation so a
   missing conditional status cannot leave standard-risk PRs pending.
9. Adversarial test PRs proving self-attestation, head/base drift, renamed and
   deleted evidence, malformed JSON, and missing evidence all fail closed.

Only after those controls exist and are verified should a separate change add
protected credentials or ruleset enforcement. This repository-local change
does not request, store, or validate any secret.
