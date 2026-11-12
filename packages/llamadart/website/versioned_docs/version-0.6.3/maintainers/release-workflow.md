---
title: Release Checklist
---

Use this checklist when releasing `llamadart`.

## 1. Pre-release validation

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
./tool/docs/build_site.sh
./tool/docs/validate_links.sh
```

Ensure migration/changelog docs reflect behavior in the release branch.

## 2. Version and docs updates

- Update `pubspec.yaml` version.
- Update `CHANGELOG.md`.
- Update `MIGRATION.md` if breaking behavior changed.
- Keep docs pages aligned with new defaults/options.

## 3. Publish flow

Tag with `vX.Y.Z` and push tag.

Current workflows involved:

- `publish_pubdev.yml`: publishes package release on version tags.
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
