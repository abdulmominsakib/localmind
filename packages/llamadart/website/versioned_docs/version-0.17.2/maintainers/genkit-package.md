---
title: Maintain the Genkit package
description: Source provenance, completed repository cutover, and independent maintenance and releases for genkit_llamadart.
---

`packages/genkit_llamadart` is a separately versioned published package, not an
Apple runtime companion. Its imports, license, tests, examples and consumer
skills stay in that package. The dependency is one-way:
`genkit_llamadart` → `llamadart`. Never add Genkit to core dependencies, raise
core's SDK floor for this adapter, or align its release number with core.

## Source and history

The original source baseline is
`leehack/genkit-llamadart@5b15fb9d9a794208f43b89723a8465e3d2473429`, published as
3.4.0 on 2026-10-18. The subtree merge retains that original parent and full
history. Keep the import merge in history; **do not squash or rebase away the
source parent**. See the package's
[provenance record](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/PROVENANCE.md).
Old issue/release links intentionally remain in the original repository.
The manifest's `repository` now points to
`https://github.com/leehack/llamadart/tree/main/packages/genkit_llamadart`.
Source navigation and new issues also point here.

Pana checks a repository's default branch and requires its manifest to name that
same repository. During same-repository PR validation, CI provides an isolated
Git mirror of GitHub's exact tested merge commit for that source lookup. The
staged manifest must match the candidate Git blob; its archive is not edited.
Pana still checks public URL availability and requires every point. This
validates candidate source metadata without claiming it is already on main.
Fork PRs, main builds and publication keep the ordinary public default-branch
check.

Native and bridge owners remain separate repositories. Flutter Edge AI's GGUF
connector remains upstream; its pending embedding/upgrade work is not part of
this move.

## Completed repository cutover

[Version 3.4.1 on pub.dev](https://pub.dev/packages/genkit_llamadart/versions/3.4.1)
was the first release from this repository, published on 2026-10-18. The
[`genkit_llamadart-v3.4.1` release](https://github.com/leehack/llamadart/releases/tag/genkit_llamadart-v3.4.1)
is tagged at release-prep merge
[`8be3082f64a82ce6d65c6f34847af573998b9beb`](https://github.com/leehack/llamadart/commit/8be3082f64a82ce6d65c6f34847af573998b9beb).
The provenance record above retains both the original 3.4.0 archive digest and
the first monorepo release's digest.

The cutover retained the existing pub.dev package identity and separate release
numbering. The core and Apple companion publishers were skipped for this adapter
release.

## Local checks and CI

Root `prepare_workspace.dart` classifies the adapter but does not resolve it.
Root analysis/test discovery excludes packages. Each package retains its own
resolution rather than adding a Pub workspace. Root formatting uses Flutter
3.47.1; the adapter keeps Dart 3.12 as its independent minimum.

From `packages/genkit_llamadart`:

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
python3 .github/check_docs.py
dart test -x real-model
# Choose a new staging directory outside the checkout:
python3 ../../tool/release/stage_genkit_package.py /tmp/genkit-publish-check
(cd /tmp/genkit-publish-check && dart pub get && dart pub publish --dry-run)
```

The root CI selector runs adapter lanes for any adapter change and conservatively
for shared/core changes. Genkit-only changes do not select core, companion or
application build lanes. Both endpoints of renames/deletions count. Every
selected lane participates in the existing truthful aggregate.

The adapter CI job first checks lower bounds: on Dart 3.12.0, before Flutter is
set up, it uses exact runtime dependency minima, including published llamadart
0.17.0, then restores the package. It then resolves published dependencies and
checks docs, tests and publication. It then creates an ignored `pubspec_overrides.yaml` to
test against checkout core, analyzes/tests again, and checks browser contracts.
It deletes that override even on failure. Neither override nor package lockfile ships in either archive.

For model-backed qualification, reuse the adapter's existing real-model tests
and local fixture environment variables described in its
[contributing guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/CONTRIBUTING.md).
Use an isolated `TMPDIR` for native tests and record model/backend/platform,
command and result. Browser guards establish routing and rejections, not a full
Genkit browser deployment.

## Independent release routing

| Package | Prep branch / label | Tag | Publisher |
| --- | --- | --- | --- |
| Core and existing Apple companions | Existing core prep patterns / `release-prep`; root pubspec must change and Genkit paths must be absent | Existing `vX.Y.Z` and companion patterns | Existing core/companion workflows and preflights |
| Genkit | `release/genkit_llamadart-vX.Y.Z` or `release-prep:genkit_llamadart`, from this repository | `genkit_llamadart-vX.Y.Z` | `release_genkit_on_prep_merge.yml` → `publish_genkit_pubdev.yml` |

Genkit prep may modify **only** its existing `pubspec.yaml` and `CHANGELOG.md`.
The branch version must match the manifest and dated changelog heading. A
conflicting existing tag, failed HTTP lookup, partial file-list API failure,
fork prep or invalid wait setting stops before mutation. Retry reuses a tag only
at the exact merge SHA and waits for an active publisher rather than dispatching
another. Publication stages a standalone copy, as the Apple companion publishers do;
ancestor `.pubignore` rules would otherwise hide the nested adapter. The staged
package resolves hosted dependencies without a local override, and uses
`setup-dart` OIDC authentication. Genkit releases set
`--latest=false` so the repository's latest core release stays selected.

A generic core release label cannot publish a Genkit-only change. A Genkit tag
matches neither core nor companion publisher. The source import did not bump
the adapter version or publish a package; the separate release-prep merge
approved publication.

## Maintainer checklist for future releases

Each release requires its own approval. Publisher settings, protected
environments, credentials and repository protections remain owner-controlled.

1. Review the candidate archive, extracted-package consumers,
   published/local-core/minimum/lower-bound tests, exact-head independent audit,
   hosted CI and resolved review threads. Preserve the original source-history
   merge.
2. Verify the existing `genkit_llamadart` pub.dev automated publisher still uses
   repository `leehack/llamadart` and pattern
   `genkit_llamadart-v{{version}}`. Retain any required protected environment
   and configure the publishing job's matching `environment` before
   approving publication. Verify owner permissions; do not create a replacement
   package, token or publisher.
3. Confirm the existing repository token permits the new release workflow's
   reviewed tag/dispatch operations, and apply the owner's existing tag and
   environment protections to the Genkit prefix. Do not weaken any core protection.
   Automated publishing configuration follows
   [Dart's official procedure](https://dart.dev/tools/pub/automated-publishing).
4. With separate release approval, prepare a new adapter version only. Keep
   the canonical repository URL above and date the matching changelog entry.
   Review its two-file prep PR, then merge it to authorize package-specific
   automation. Never reuse a published version or manually push release tags.
5. Verify exact tag-to-merge SHA, publisher verify/lower-bound/publish jobs,
   pub.dev version/archive SHA/metadata, clean hosted installation, package skills
   and GitHub Release. Confirm core/companion publishers did not run.
6. Preserve old repository history, issues and release links. Retirement or
   archival needs separate explicit approval. Coordinate open old issues by
   links; do not silently transfer or close them.
