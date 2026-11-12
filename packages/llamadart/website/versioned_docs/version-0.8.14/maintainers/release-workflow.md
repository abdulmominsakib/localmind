---
title: Release Checklist
description: Use this checklist to cut a llamadart release, snapshot docs, and verify the published artifacts afterward.
---

Use this checklist when releasing `llamadart`.

## 1. Pre-release validation

```bash
# Print release-tier rows for evidence planning; this does not run validation.
dart run tool/testing/test_matrix.dart --tier release
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart run tool/testing/verify_release_docs_versions.dart
./tool/docs/build_site.sh
./tool/docs/validate_links.sh
```

Ensure migration/changelog docs reflect behavior in the release branch.

Before publishing a release that changes native runtime pins, verify native
version alignment:

- `hook/build.dart` native-assets pins and companion package `Package.swift`
  Apple SPM pins should reference compatible native repo releases.
- Companion package README and CHANGELOG files should name the native repo tags
  they publish.
- `llamadart-native` owns llama.cpp bridge artifacts for native-assets and
  Apple SPM-compatible companion packages.
- `litert-lm-native` owns LiteRT-LM bridge artifacts for native-assets and
  Apple SPM-compatible companion packages.
- If native versions changed, prefer the `Sync Native Version & Bindings`
  workflow PR over hand-editing core pins. It also updates Apple SPM companion
  package pins under `packages/` when Apple XCFramework releases changed.

## 2. Version and docs updates

- Update `pubspec.yaml` version.
- Update `CHANGELOG.md`.
- Companion packages start at `0.0.1` and move independently from the core
  package. Native pin sync records changed companion native pins under
  `Unreleased` but does not bump companion package versions by default.
- In the release-prep PR, bump only companion packages whose native pins or
  publishable package contents changed, move their accumulated `Unreleased`
  notes into the new version section, and keep unchanged companion package
  versions as-is.
- Companion packages publish only after the release-prep PR is merged. The
  release-prep PR merge is the approval boundary; automation pushes the relevant
  package-specific tags, and the publish workflow skips a companion package
  version that already exists on pub.dev.
- Keep current install snippets aligned with root and companion `pubspec.yaml`
  versions. Run `dart run tool/testing/verify_release_docs_versions.dart` before
  opening or merging the release-prep PR.
- Move accumulated `Unreleased` entries into the new version section; remove
  the `Unreleased` heading when it would otherwise be empty. Add it back only
  when the next unreleased change is documented.
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

Release automation must not push the core `vX.Y.Z` release tag until every
companion package version named in the current install docs is already
published on pub.dev. The release sequence is:

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

3. If a changed companion version is missing, keep the PR scoped to release
   prep and merge it only when the release is approved. The post-merge release
   workflow then pushes that companion's package-specific tag, waits for
   `publish_companion_pubdev.yml` to publish the package, and re-checks the
   pub.dev version URL.
4. Automation pushes the core `vX.Y.Z` tag only after the companion packages
   referenced by the release docs are resolvable from pub.dev.

Current workflows involved:

- `publish_pubdev.yml`: publishes the core package on version tags, creates or
  updates the GitHub Release after pub.dev publishing succeeds, and does not
  publish companion packages.
- `publish_companion_pubdev.yml`: publishes one companion package from a
  package-specific version tag after that package already exists on pub.dev:
  `llamadart_llama_cpp_flutter-v{{version}}` or
  `llamadart_litert_lm_flutter-v{{version}}`. Pub.dev automated publishing
  cannot create a new package, so publish each companion's first version
  manually from a temporary copy, then configure automated publishing on that
  package's pub.dev Admin tab with the matching tag pattern. Use the same
  temp-copy shape as CI before running `flutter pub publish`:

```bash
package_path=packages/llamadart_llama_cpp_flutter
tmp_package="$(mktemp -d)"
rsync -a --delete \
  --exclude='.dart_tool' \
  --exclude='build' \
  --exclude='pubspec.lock' \
  "$package_path/" "$tmp_package/"
(cd "$tmp_package" && flutter pub publish)
```

- `docs_version_cut.yml`: creates versioned docs snapshot on `v*` tags.
- `docs_pages.yml`: deploys docs to GitHub Pages after successful
  `docs_version_cut.yml` runs (and can be manually triggered).
- `release_on_prep_merge.yml`: runs after a release-prep PR is merged into
  `main`, validates the prepared version, publishes any missing companion
  package versions first, pushes the core release tag, waits for pub.dev, and
  confirms the GitHub Release exists.

## 4. Post-release verification

- Verify `release_on_prep_merge.yml`, `publish_pubdev.yml`,
  `publish_companion_pubdev.yml` when relevant, `docs_version_cut.yml`, and
  `docs_pages.yml` all completed successfully.
- Verify pub.dev package page and API docs for the new version.
- Verify the GitHub Release exists and is marked latest.
- Verify docs version selector includes the new release.
- Re-run smoke checks for representative examples.

## 5. If automation is blocked

If `docs_version_cut.yml` cannot push directly to `main` (for example due to
branch protections), run the version cut locally and open a PR:

```bash
cd website
npm ci
npm run docusaurus docs:version <release-version>
```
