# PR Branch Writer Inventory

This inventory bounds tracked repository-local paths at
`b6af5a8b5d1973bc72d4e5283f1c7d728a679cb7` plus the integrity changes in this
worktree. It covers workflow files with either `.yml` or `.yaml`, tracked
non-test executable-source and task-manifest files throughout the repository,
repository bot configuration, and all tracked Markdown instructions. Static
regression tests keep those surfaces free of an unregistered direct PR-ref push
or ref-update API; the helper's own bare-repository tests mutate only temporary
local fixtures.

| Path | Principal | Trigger | Expected old SHA | Update mechanism |
| --- | --- | --- | --- | --- |
| `tool/git/safe_pr_head_update.dart` | Caller-supplied, validated `writer` identifier | Explicit CLI invocation | Required full SHA; all-zero means the ref must be absent | Validates exact ref and ancestry, then performs a normal push with an in-connection advertised-OID guard and exact-ref read-back |
| `.github/workflows/sync_native_bindings.yml` | `github-actions-native-sync` using `GITHUB_TOKEN` | Maintainer `workflow_dispatch` | Exact automation ref from `git ls-remote`, rechecked by the helper | Builds on current `main`; fast-forwards either line when already integrated or performs a real merge that retains both lines and fails on conflicts, then invokes the guarded helper before using `gh pr` |
| `AGENTS.md` and `doc/testing_matrix.md` | Maintainer, contributor, or authorized agent named in `writer` | Manual PR creation or follow-up task | Exact verified PR head at the start of the mutation | Required to invoke the guarded helper; ordinary blind `git push` is not an authorized open-PR update path |
| `CONTRIBUTING.md` | Contributor named in `writer`, using a credentialed fork remote | Initial fork-branch publication, then any update after the PR opens | All-zero for initial branch creation; exact verified fork-branch head for an open PR | Initial publication may invoke the helper with the all-zero expectation; every later open-PR update must invoke the helper with the observed full SHA |
| `.github/dependabot.yml` | GitHub Dependabot | Weekly GitHub-managed schedule | Managed inside GitHub; not exposed to checkout-local code | Server-side creation/update of Dependabot PR branches; bounded but not enforced by the local helper |

The repository also contains a direct HEAD-to-main push in
`.github/workflows/docs_version_cut.yml`, tag creation in `release_on_prep_merge.yml` and
`release_genkit_on_prep_merge.yml` (the latter creates only
`genkit_llamadart-vX.Y.Z` tags),
`tool/release/nonpublishing_auth_probe.py` diagnostic tag creation and cleanup,
historical companion tag-push examples under `website/versioned_docs/`, a
forced local detached checkout for an upstream test fixture, `codesign --force`,
and `pub publish --force`. None writes an open PR head ref. The static test
distinguishes these from remote `refs/heads/*` mutation rather than banning
unrelated uses of the word `force`.

## Diagnostic tag-only writer

`tool/release/nonpublishing_auth_probe.py`, invoked by
`.github/workflows/nonpublishing_release_auth_probe.yml`, is an explicit
nonrelease tag-only writer. An approved operator dispatches it on reviewed
`main` with the exact expected commit. Its read-only `GITHUB_TOKEN` attempts a
negative create; `RELEASE_AUTOMATION_TOKEN` creates the positive diagnostic tag
and cleans up invocation-owned tags. The only write API operations are POST
create and DELETE under `refs/tags/ci-auth-probe-<runid>-<32hex>`, with a positive
decimal sender run ID and 32 lowercase random hexadecimal characters. No
release tag or open PR head is writable through this helper.

Creation requires absence and reads back the exact commit. Cleanup accepts only
one of that invocation's generated tags and verifies its commit before DELETE,
then verifies absence. The read-before-delete movement guard is **not atomic
compare-and-swap**; an intervening ref change remains a race. Ambiguous outcomes
retain inspection evidence for operator follow-up rather than report success.
This registration grants no general branch or ref-update exception.

## PR #434 evidence and consequence

Verified local facts:

- `git show 00f93916e6dcc51d3233580aea044d5cf476981b` identifies the merged change as
  `fix: restore a self-consistent chat app lockfile SDK bound (#434)`.
- The local reflog for `fix/chat-app-lockfile-sdk-bound` records head
  `781285446177670c9a83204efc79771f070a0d87`, then a reset to ancestor
  `135e0957198499e6577ad859b344655583c67864`, followed by rebuilt heads
  `60ec278c529c646b66e8e08b762c830f4939347c` and
  `818e6cad15ef7248ef3564ff449fa3d4dc49be7b`.
- `781285446177670c9a83204efc79771f070a0d87` and
  `60ec278c529c646b66e8e08b762c830f4939347c` have the same tree
  `49368f297e580fa81a3ac81005f8e5c3cd60a3cb` but different parents. The latter
  no longer descends from the former.

Inference, explicitly not established by the retained local evidence: the
reflog proves a local stale-ancestor reset and replacement history, but does not
identify which actor or API, if any, applied the corresponding remote branch
transition. If a validated PR head changes in that way, CI, approvals, and
independent QA attached to the former SHA no longer qualify the new head and
must be rerun.

## Residual server-side boundary

The helper's normal Git push is a server-side ref transaction for that one
invocation: the pre-push guard checks the server-advertised old OID, and the
receive side rejects a ref race after advertisement. This does not make all
GitHub writers atomic with the helper. GitHub web UI update-branch operations,
Dependabot, installed or third-party GitHub Apps, merges, and direct pushes that
bypass this checkout remain outside local enforcement.
Untracked checkout-local hooks, aliases, and tools are likewise outside the
tracked inventory. The helper preserves the configured `pre-push` hook and
classifies its rejection, but cannot authorize or constrain separate mutations
that hook performs.

The native-sync workflow deliberately grants its job-scoped `GITHUB_TOKEN` only
`contents: write` and `pull-requests: write`. GitHub may leave the resulting
`pull_request` workflow runs awaiting maintainer approval; creating or updating
the PR is therefore not evidence that its CI started or passed.

Repository owners must enforce that residual boundary with GitHub branch
protection or rulesets that block force pushes, require linear history and
required checks, require CODEOWNERS review where applicable, and dismiss or
renew stale approvals after a head change. Those settings are privileged
external state and are not asserted merely because this repository documents
them.
