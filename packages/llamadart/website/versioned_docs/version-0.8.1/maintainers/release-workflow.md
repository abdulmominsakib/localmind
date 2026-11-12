---
title: Release Checklist
description: Use this checklist to cut a llamadart release, snapshot docs, and verify the published artifacts afterward.
unlisted: true
---

Use this checklist when releasing `llamadart`.

## 1. Pre-release validation

```bash
# Print release-tier rows for evidence planning; this does not run validation.
dart run tool/testing/test_matrix.dart --tier release
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
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
  package. Native pin sync bumps only the changed companion package patch
  version, updates its `pubspec.yaml`, and writes a versioned changelog entry
  that includes the native repo tag.
- Leave unchanged companion package versions as-is. Companion packages publish
  from package-specific tags after their first manual pub.dev publish; the
  workflow skips a companion package version that already exists on pub.dev.
- Move accumulated `Unreleased` entries into the new version section; remove
  the `Unreleased` heading when it would otherwise be empty. Add it back only
  when the next unreleased change is documented.
- Update `MIGRATION.md` if breaking behavior changed.
- Keep docs pages aligned with new defaults/options.
- Keep local SwiftPM artifact caches out of pub archives. Apple SPM binary
  target pins live in the Flutter runtime companion packages, not in the core
  `llamadart` package.

## 3. Publish flow

Tag with `vX.Y.Z` and push tag.

Current workflows involved:

- `publish_pubdev.yml`: publishes the core package on version tags, and
  does not publish companion packages.
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

## 4. Post-release verification

- Verify pub.dev package page and API docs for the new version.
- Verify docs version selector includes the new release.
- Re-run smoke checks for representative examples.

## 5. If automation is blocked

If `docs_version_cut.yml` cannot push directly to `main` (for example due to
branch protections), run the version cut locally and open a PR:

```bash
cd website
npm ci
npm run docusaurus docs:version 0.6.2
```
