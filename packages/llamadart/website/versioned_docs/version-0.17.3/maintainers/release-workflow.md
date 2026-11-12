---
title: Release checklist
description: Use this checklist to cut a llamadart release, snapshot docs, and verify the published artifacts afterward.
---

Use this checklist when releasing `llamadart`. The independently versioned
Genkit adapter follows [its own procedure](./genkit-package); it is not an Apple
companion and is not released by this checklist.

## 1. Pre-release validation

```bash
# Print release-tier rows for evidence planning; this does not run validation.
dart run tool/testing/test_matrix.dart --tier release
dart run tool/prepare_workspace.dart
dart format --output=none --set-exit-if-changed .
dart analyze
dart run tool/testing/check_platform_boundaries.dart
dart test -p vm -j 1 --exclude-tags local-only
dart test -p chrome --exclude-tags local-only
dart test -p vm test/unit/tooling/validation_coverage_test.dart
dart run tool/testing/verify_release_docs_versions.dart --release-prep
python3 tool/release/check_core_archive.py
./tool/docs/build_site.sh # fails on broken internal links
```

Ensure migration/changelog docs reflect behavior in the release branch.

Review the capability inventory's printed exemptions against the release scope.
Pack/case/profile bindings do not establish device qualification or waive
existing evidence requirements. This model-free gate adds no blanket
Firebase/GCE run requirement; choose affected validation rows and retain the
existing cost/approval boundaries.

The archive check uses pub's actual selected-file inventory, stages that file
set, and resolves/analyzes a fresh consumer plus the packaged basic example.
The chat app and its private validation harness stay together in a repository
checkout, outside the core archive. Run this check from a clean checkout after
workspace preparation, with the pinned SDK on PATH.

Before publishing a release that changes native runtime pins, verify native
version alignment:

- `lib/src/hook/native_release_pins.dart` native-assets pins and companion
  package `Package.swift` Apple SPM pins should reference compatible native repo
  releases.
- Companion package README and CHANGELOG files should name the native repo tags
  they publish.
- `llamadart-native` owns llama.cpp bridge artifacts for native-assets and
  Apple SPM-compatible companion packages.
- `litert-lm-native` owns LiteRT-LM bridge artifacts for native-assets and
  Apple SPM-compatible companion packages.
- `stable-diffusion-native` owns stable-diffusion.cpp runtime artifacts for
  native-assets and the Apple SPM-compatible companion package.
- If native versions changed, prefer the `Sync Native Version & Bindings`
  workflow PR over hand-editing core pins. It also updates Apple SPM companion
  package pins under `packages/` when Apple XCFramework releases changed.
- Stable llama.cpp native pins use strict `vMAJOR.MINOR.PATCH`; historical
  `bNNNN` pins remain explicit compatibility inputs. Verify `assets.json`,
  `SHA256SUMS`, hook contract version, bundle coverage, and manifest/release
  checksum agreement before accepting a stable pin change. `SHA256SUMS`, the
  manifest, and GitHub asset digests must agree. Stable wrapper-only rebuilds
  use `vM.m.p-N` for upstream `vM.m.p`; the suffix advances the native sequence
  but must never appear in the manifest's upstream llama.cpp ref. GitHub marks
  newly published wrapper and nightly releases as prereleases, so select them
  explicitly. Historical `bNNNN` and `bNNNN-llamadart.N` artifacts may retain
  older `prerelease=false` metadata, but remain explicit compatibility inputs;
  `latest` accepts only unsuffixed `vMAJOR.MINOR.PATCH` regardless of GitHub
  metadata. Nightly cores and positive rebuild counters must use canonical
  decimal spelling without leading zeros.

## 2. Version and docs updates

- Update `pubspec.yaml` version.
- Update `CHANGELOG.md`.
- Regenerate tracked path-dependency locks after the core bump. Workspace
  preparation updates the chat-app lock; run `dart pub get` in
  `packages/llamadart_validation` and `website/examples/observability` too.
  A stale validation-harness lock changes during a desktop bundle build and
  fails its clean-source provenance check. The bounded core-patch metadata
  evidence route requires all three generated locks and permits only their
  local core version changes; it does not admit other dependency churn.
- Companion versions share the core's `MAJOR.MINOR`; their patch numbers move
  independently. Core `0.13.0` ships with every companion at `0.13.0`, and a
  later companion change within that minor bumps only the companion patch.
  From core `0.13.0` on, `verify_release_docs_versions.dart` fails, with or
  without `--release-prep`, when a companion's `MAJOR.MINOR` differs from the
  core's; the `0.0.x` companions released beside earlier cores predate the
  rule. Native pin sync records changed companion native pins under
  `Unreleased` but does not bump companion package versions by default.
- Release automation publishes only stable core versions and stops before any
  tag on a prerelease such as `0.13.0-dev.1`: no companion constraint
  `>=M.m.0 <M.(m+1).0` admits a prerelease of `M.m.0`. Build metadata, as in
  `0.13.0+1`, is not a prerelease.
- A companion-only release still needs a new core version: the release
  workflow publishes only for a core version that has no release tag at
  another commit, so bump the core patch with the companion.
- Each companion constrains the core to the core's own minor, for example
  `llamadart: '>=0.13.0 <0.14.0'` for core `0.13.x`, so pub refuses to pair it
  with a core minor whose native pins it does not match. A release that bumps
  the core minor must therefore set that constraint in every companion and
  bump every companion version, even one whose native pin did not move:
  pub.dev never changes a published version's constraint, and the release
  workflow skips a companion version that is already published.
- A companion native repin can ship in a core patch only with verified
  compatibility for every older companion whose published constraint admits
  that patch. Keep accepted older artifacts explicit, with warning/limitations
  and exact identity checks; otherwise use a new core minor.
- With `--release-prep`, the verifier checks both published companion -> new
  core and new companion -> published core pairings from full tag history.
  Narrow a new companion's core lower bound past every core whose hook rejects
  its pin, and bump the companion version: published constraints are immutable.
  For SD `v0.2.0-4`, prepare companion `0.15.2` with
  `llamadart: '>=0.15.2 <0.16.0'`. Core `0.15.2` retains explicitly qualified
  SD `v0.2.0-3` companions with an upgrade warning and a Dart backstop for
  recorded Metal backend failures. Updating core alone retains the old native
  payload; use the new companion to obtain the native failure guard.
- In the release-prep PR, bump only companion packages whose native pins or
  publishable package contents changed, move their accumulated `Unreleased`
  notes into the new version section, and keep unchanged companion package
  versions as-is.
- Companion packages publish only after the release-prep PR is merged. The
  release-prep PR merge is the approval boundary; automation pushes the relevant
  package-specific tags, and the publish workflow skips a companion package
  version that already exists on pub.dev.
- Keep current install snippets aligned with root and companion `pubspec.yaml`
  versions. Run
  `dart run tool/testing/verify_release_docs_versions.dart --release-prep`
  before opening or merging the release-prep PR. Without `--release-prep` the
  gate only reports pending companion bumps; with it, a companion whose
  `Package.swift` pin is still recorded under `## Unreleased` fails the run.
  `release_on_prep_merge.yml` runs the same strict check, so an unresolved
  pending bump aborts the release before any tag is pushed instead of shipping
  the previous pin.
- Before any tag is pushed, `tool/release/companion_pub_preflight.dart` also
  fails when a companion's checked-out version is already on pub.dev with a
  different `llamadart` constraint; bump that companion's version.
- Move accumulated `Unreleased` entries in `CHANGELOG.md` and
  `website/docs/changelog/recent-releases.md` into the new version section and
  remove the heading. `--release-prep` fails while either keeps
  `## Unreleased`; after the release, `docs_version_cut.yml` puts an empty one
  back on `main`, so the next change only adds a bullet.
- In a release that opens a new minor, trim
  `website/docs/changelog/recent-releases.md` to the new current and previous
  minor by deleting the sections older than that, so `0.18.0` keeps `0.18.x`
  and `0.17.x` and drops `0.16.x`. Patch releases trim nothing, and
  `CHANGELOG.md` keeps every release. The trim is a manual step:
  `verify_release_docs_versions.dart` fails, with or without `--release-prep`,
  when the page keeps a release older than the previous minor of the
  `pubspec.yaml` version, and names the headings to remove.
- Each current core release section must state the pinned WebGPU bridge tag.
  If it is unchanged, use an explicit baseline instead of repeating the old
  release's fixes. In `CHANGELOG.md`, use:

  ```markdown
  * Keep the default WebGPU bridge assets at `vX.Y.Z` (unchanged from A.B.C).
  ```

  In `website/docs/changelog/recent-releases.md`, use:

  ```markdown
  - Keep default WebGPU bridge assets at `vX.Y.Z` (unchanged from A.B.C).
  ```

  Replace `vX.Y.Z` with the pinned asset tag and `A.B.C` with the published core
  version it is retained from. Keep a separate runtime-baseline paragraph with
  the existing upstream llama.cpp tag and commit, native tag, Web LiteRT-LM
  module version and manifest SHA-256; the release-note tests still require
  that provenance in the current section. This records retained versions, not
  newly shipped fixes. The bridge-tag gate checks the complete baseline wording,
  rejects missing, stale or multiple claims, and never borrows a baseline from
  an older release when the promoted current section omits it.
- Both core changelogs union-merge (see [Changelog merges](#changelog-merges)).
  Turn union off before rebasing or merging the release-prep branch.
- Update `MIGRATION.md` if breaking behavior changed.
- Keep docs pages aligned with new defaults/options.
- Keep local SwiftPM artifact caches out of pub archives. Apple SPM binary
  target pins live in the Flutter runtime companion packages, not in the core
  `llamadart` package.

## 3. Publish flow

A release-prep PR updates versions, changelogs, docs, and pins only; it must not
publish companion packages or the core package before merge. Merging a
release-prep PR is the explicit approval boundary for publishing. After merge,
`release_on_prep_merge.yml` owns companion package tag ordering, the core
`vX.Y.Z` tag, pub.dev publication, docs versioning, and GitHub Release creation.

For automation to run, the merged PR must either carry the `release-prep` label
or use a versioned release-prep branch name such as `release/prep-0.8.12` or
`release/0.8.12-prep`. The automation requires a `RELEASE_AUTOMATION_TOKEN`
repository secret containing a fine-scoped PAT or GitHub App token that can push
tags and trigger tag-based workflows. Do not use the default `GITHUB_TOKEN` for
this step because GitHub suppresses most workflow runs caused by that token.
Prefer a GitHub App token or fine-scoped PAT with only the repository permissions
needed to create tags, and rotate it on a regular maintainer cadence. Never echo
the token or derived credential-bearing URLs in workflow logs.

Release automation and publication-sensitive files are covered by
`.github/CODEOWNERS`. CODEOWNERS is only advisory until the repository's branch
protection or ruleset requires code-owner review, so keep that setting enabled
before relying on the post-merge workflow as the publication approval boundary.
When adding new workflow, release, version, or native-runtime publication
surfaces, update `.github/CODEOWNERS` in the same PR.

The post-merge workflow waits for pub.dev and GitHub Release propagation using
repository-variable defaults that can be tuned without editing the workflow:

| Variable | Default | Meaning |
| --- | --- | --- |
| `RELEASE_AUTOMATION_PUBDEV_WAIT_ATTEMPTS` | `180` | Number of pub.dev version URL checks. |
| `RELEASE_AUTOMATION_PUBDEV_WAIT_INTERVAL_SECONDS` | `10` | Delay between pub.dev checks. |
| `RELEASE_AUTOMATION_GITHUB_RELEASE_WAIT_ATTEMPTS` | `180` | Number of GitHub Release existence checks. |
| `RELEASE_AUTOMATION_GITHUB_RELEASE_WAIT_INTERVAL_SECONDS` | `10` | Delay between GitHub Release checks. |

Companions depend on the core version they constrain, and `pub publish`
resolves that dependency from pub.dev, so release automation publishes the core
first and every missing companion version right after it. For the few minutes
in between, the core's install docs name a companion version that is not on
pub.dev yet. The release sequence is:

1. Confirm the native GitHub releases referenced by `Package.swift` are live and
   include the pinned XCFramework zip/checksum assets.
2. For each companion package named in current install docs, check whether its
   `pubspec.yaml` version exists on pub.dev:

   ```bash
   package_path=packages/llamadart_llama_cpp_flutter
   package_name="$(awk '/^name:[[:space:]]*/ {print $2; exit}' "$package_path/pubspec.yaml")"
   package_version="$(awk '/^version:[[:space:]]*/ {print $2; exit}' "$package_path/pubspec.yaml")"
   curl -fsSL "https://pub.dev/api/packages/$package_name/versions/$package_version"
   ```

   For each missing companion version, also confirm on
   `https://pub.dev/packages/<package>/admin` that automated publishing from
   GitHub Actions is enabled for `leehack/llamadart` with tag pattern
   `<package>-v{{version}}`. The preflight cannot see that setting, and without
   it the companion's publish run fails after the core has shipped.

3. If a changed companion version is missing, keep the PR scoped to release
   prep and merge it only when the release is approved. The post-merge release
   workflow pushes the core `vX.Y.Z` tag and waits until the pub.dev package
   listing, which pub resolves against, includes the new core.
4. The workflow then pushes each missing companion's package-specific tag,
   waits for `publish_companion_pubdev.yml` to publish it, and re-checks the
   pub.dev listing. Pub.dev serves that listing with `max-age=120`, so the
   companion publish retries `flutter pub get` twice, a minute apart, when
   its first resolution misses the new core.
5. A rerun at the same merge commit finds the core tag already there, skips
   pushing it, and publishes the companions still missing; a core tag at any
   other commit stops the run.
   - If `publish_pubdev.yml` failed after the core tag was pushed, a rerun of
     `release_on_prep_merge.yml` alone waits for the core on pub.dev and fails.
     Rerun the tag's failed `publish_pubdev.yml` run first, wait for the core
     version on pub.dev, then rerun `release_on_prep_merge.yml`.
   - A companion tag at another commit whose version is not on pub.dev stops
     the run: rerunning its publish would ship that commit's package. Release
     it from a new release-prep PR that bumps the core version and the
     companion's patch version.

   A companion whose tag exists at the release commit but whose version is
   not on pub.dev also stops the rerun, because that tag already ran
   `publish_companion_pubdev.yml`:
   - For a transient failure, such as a pub.dev or runner outage, or
     automated publishing not yet enabled for the package, fix the cause,
     rerun that tag's failed `publish_companion_pubdev.yml` run, wait for the
     version on pub.dev, then rerun `release_on_prep_merge.yml`.
   - For a cause in the repository, such as a package that fails
     `pub publish` validation, the tagged commit cannot publish that version.
     Fix it in a new release-prep PR that bumps the core version and the
     companion's patch version; what already published stays as it is.

Current workflows involved:

- `publish_pubdev.yml`: publishes the core package on version tags, creates or
  updates the GitHub Release after pub.dev publishing succeeds, and does not
  publish companion packages.
- `publish_companion_pubdev.yml`: publishes one companion package from a
  package-specific version tag after that package already exists on pub.dev:
  `llamadart_llama_cpp_flutter-v{{version}}`,
  `llamadart_litert_lm_flutter-v{{version}}` or
  `llamadart_stable_diffusion_flutter-v{{version}}`. Pub.dev automated publishing
  cannot create a new package, so publish each companion's first version
  manually from a temporary copy, then configure automated publishing on that
  package's pub.dev Admin tab with the matching tag pattern. Use the same
  temp-copy shape as the publish workflow before running `flutter pub publish`.
  Leaving out the checkout's `pubspec_overrides.yaml` makes pub resolve the
  companion's `llamadart` constraint from pub.dev, so a new companion can first
  publish only against a core minor that is already released:

```bash
package_path=packages/llamadart_llama_cpp_flutter
tmp_package="$(mktemp -d)"
rsync -a --delete \
  --exclude='.dart_tool' \
  --exclude='build' \
  --exclude='pubspec.lock' \
  --exclude='pubspec_overrides.yaml' \
  "$package_path/" "$tmp_package/"
(cd "$tmp_package" && flutter pub publish)
```

- Each companion commits a `pubspec_overrides.yaml` that resolves `llamadart`
  from this checkout, because a release-prep PR constrains companions to a
  core version pub.dev does not have yet. Pub leaves the file out of published
  archives. CI's companion publish dry-run points the same override at the
  checkout; the real publish drops it.

- `docs_version_cut.yml`: creates versioned docs snapshot on `v*` tags,
  restores an empty `## Unreleased` heading in both core changelogs with
  `tool/release/reopen_unreleased_changelog.dart` in the same commit, and
  pushes it to `main` with `GITHUB_TOKEN`, so that commit starts no CI or demo
  deploy run. Genkit and companion tags do not match `v*`.
- `docs_pages.yml`: deploys docs to GitHub Pages after successful
  `docs_version_cut.yml` runs (and can be manually triggered).
- `ci.yml` (`deploy-chat-app`) and `laya_tetris_hf_static_deploy.yml`: the
  release-prep merge commit redeploys the hosted chat app and Laya Tetris
  demos. Each upload is skipped, without failing, only when a newer `main`
  commit changes that demo's inputs; the docs snapshot commit does not.
- `release_on_prep_merge.yml`: runs after a release-prep PR is merged into
  `main`, validates the prepared version, pushes the core release tag, waits
  for pub.dev, publishes any missing companion package versions, and confirms
  the GitHub Release exists. Before pushing any tag,
  `tool/release/companion_pub_preflight.dart` checks that every companion
  under `packages/` exists on pub.dev and otherwise stops with the
  first-publish steps above; publish the package, then rerun the run. It
  retries each pub.dev request once after a timeout, including a stalled
  body, or a 5xx answer.

## 4. Post-release verification

- Verify `release_on_prep_merge.yml`, `publish_pubdev.yml`,
  `publish_companion_pubdev.yml` when relevant, `docs_version_cut.yml`, and
  `docs_pages.yml` all completed successfully.
- Verify pub.dev package page and API docs for the new version.
- Verify the GitHub Release exists and is marked latest.
- Verify docs version selector includes the new release.
- Verify both hosted demos serve the release commit. The chat app deploys at
  the end of the release commit's CI run, the Laya Tetris demo a few minutes
  after the merge:

  ```bash
  git rev-list -n 1 v<release-version>
  curl -fsS https://leehack-llamadart.static.hf.space/llamadart-build.json
  curl -fsS https://leehack-flutter-laya-tetris.static.hf.space/deploy-sha.txt
  ```

  A later commit is fine when it changed no demo input. If a demo is behind,
  for example because its deployment failed, redeploy `main` by hand. The CI
  run tests `main`'s tip in full before it deploys the chat app. Its unique
  concurrency group retains other main CI runs, including pending runs;
  deployment serialization and stale-input guards still apply:

  ```bash
  gh workflow run ci.yml --ref main
  gh workflow run laya_tetris_hf_static_deploy.yml --ref main
  ```

- Re-run smoke checks for representative examples.

## 5. If automation is blocked

If `docs_version_cut.yml` cannot push directly to `main` (for example due to
branch protections), run the version cut locally and open a PR:

```bash
dart tool/release/reopen_unreleased_changelog.dart
cd website
dart pub get
dart run tool/cut_version.dart <release-version>
```

## Changelog merges

`.gitattributes` sets `merge=union` on `CHANGELOG.md` and
`website/docs/changelog/recent-releases.md`. When two branches add bullets
under `## Unreleased`, a local rebase or merge keeps both instead of
conflicting. GitHub may still report the conflict; rebase locally and update
the PR branch with `tool/git/safe_pr_head_update.dart`.

Union never conflicts: it keeps both sides of any edit, so it cannot tell
a new bullet from a heading rename. A branch that added a bullet before a
release and is rebased after it can end up with that bullet, and stale copies
of the released bullets, inside the new `## X.Y.Z` section. CI's
`check_released_changelog_sections.dart` (in the Analyze and docs-version
jobs) fails such a PR: everything from the first `## <version>` heading down
must match the merge base with the PR's base branch byte-for-byte, and the
error names the file and first differing line. Move the bullet back under
`## Unreleased`. Release-prep PRs, detected by the same label and branch rules
as `release_on_prep_merge.yml`, are exempt. CI reads labels from the event
that started the run, so push again after adding the `release-prep` label.

One change to a released section is allowed outside release prep: the docs
changelog may lose its oldest sections. It passes when what remains is an
exact prefix of the base's released sections and the first removed line is a
`## <version>` heading, so a trim cannot cut a section in half or edit one
that stays. `CHANGELOG.md` has no such allowance.

Turn union off for release prep, which renames `## Unreleased` and rewrites
its bullets, and for any rebase across a release-prep commit whose result you
would rather resolve by hand. `.git/info/attributes` overrides `.gitattributes`
for every worktree of the clone:

```bash
attributes="$(git rev-parse --git-path info/attributes)"
printf '%s\n' '/CHANGELOG.md merge=text' \
  '/website/docs/changelog/recent-releases.md merge=text' >> "$attributes"
# ... rebase or merge, resolving conflicts by hand ...
# then remove those two lines from "$attributes".
```

`verify_release_docs_versions.dart` fails when `## Unreleased` appears twice
or below a released section, and with `--release-prep` whenever it remains,
which catches the stray headings union can leave.
