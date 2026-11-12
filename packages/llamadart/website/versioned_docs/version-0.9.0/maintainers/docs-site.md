---
title: Maintainer overview
description: Repo-specific maintenance checklist for the llamadart docs site, releases, and verification flow.
---

This section is for `llamadart` maintainers: repository ownership, routine
checks, and how the docs site is built and published.

## Repository ownership

Which repository owns which runtime change is listed once, in
[Runtime ownership](./runtime-ownership).

Many maintainers keep the owning repositories as sibling checkouts one level
above this repo:

```text
../llamadart
../llamadart-native
../litert-lm-native
../llama-web-bridge
../llama-web-bridge-assets
```

Verify these paths before running cross-repo workflows.

## Core maintainer responsibilities in this repo

1. Keep public Dart APIs stable and documented.
2. Keep runtime wiring aligned with native/web owning repos.
3. Keep docs, migration notes, and examples aligned to actual behavior.
4. Keep CI green on format, analyze, tests, and docs checks.

## Daily verification commands

From repo root:

```bash
dart run tool/prepare_workspace.dart
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
./tool/docs/build_site.sh
```

Preparation resolves the root package and every maintained example. It also
fails if any example or companion package is missing or unclassified. The root
analyzer covers the root package and examples; companion packages own separate
dependency, analysis, test, SwiftPM, and publish-validation lanes. Generated
`.dart_tool`, `build`, CocoaPods `Pods`, Flutter platform `ephemeral`, and
plugin `.symlinks` trees are not workspace packages. Vendored, archived docs,
or local-only trees outside `example/` and `packages/` are not discovered by
the workspace bootstrap.

Use the Flutter SDK pinned in `.flutter-version` (`3.47.1`), the same version
CI installs, for repository-wide quality gates. Other Dart formatters produce
different source layouts even after the same dependency bootstrap.

Use targeted test commands when iterating quickly, then run full checks before
release-related merges.

## Docs site

`website/` is a [Jaspr](https://jaspr.site) static site. It is its own Dart
package with its own analyze and test lane; the root analyzer skips it.

| Path | Purpose |
| --- | --- |
| `docs/`, `sidebars.json` | Next-release docs and their sidebars (`docsSidebar`, `maintainersSidebar`) |
| `versioned_docs/`, `versioned_sidebars/`, `versions.json` | Released snapshots; the first entry of `versions.json` is the latest release |
| `content/` | Homepage, 404 page and the `/api` redirect |
| `lib/` | Loaders, layouts, components and syntax highlighting |
| `web/` | Static assets copied as-is (`styles.css`, `site.js`, `img/`, `robots.txt`, `CNAME`) |
| `tool/` | Post-build finalizer, preview server, and version cut |

URLs: the latest release is served at `/docs/...`, the next release at
`/docs/next/...`, and each older release at `/docs/<version>/...`.

`./tool/docs/build_site.sh` runs `jaspr build`, then `tool/finalize_site.dart`,
which writes `route.html` files, `404.html` and `sitemap.xml` and fails on any
broken internal link or anchor, then indexes search with Pagefind (via `npx`).
Preview the result as GitHub Pages serves it:

```bash
cd website
dart run tool/serve_site.dart --port 8080
```

For live editing, `dart run jaspr_cli:jaspr serve` in `website/` renders pages
on demand; set `DOCS_ARCHIVED=0` to skip archived releases and start faster.

Writing docs:

- Link to other docs with relative paths (`../guides/tool-calling`); `.md`
  suffixes and `#anchors` work.
- Admonitions use `:::note|tip|info|warning|caution|danger Optional title`.
- ` ```mermaid ` fences render as diagrams. Code fences for Dart, bash, YAML,
  JSON, JS, HTML, Ruby, PowerShell and HTTP are highlighted at build time.
- Put images under `website/web/img/` and reference them as `/img/<name>`.
- Add every new doc to `sidebars.json`: `website/test/site_model_test.dart`
  fails unless each doc without `unlisted: true` appears there exactly once.

`dart run tool/cut_version.dart <version>` in `website/` snapshots `docs/` and
`sidebars.json` for a release and makes it the latest; `docs_version_cut.yml`
runs it on release tags.

## Analytics and SEO maintenance

- GA4 is added at build time when `DOCS_GA_MEASUREMENT_ID` is set, as the docs
  deployment workflow does from the repository variable of the same name.
  Update that variable when rotating the docs site's GA4 stream.
- Page metadata and structured data live in
  `website/lib/src/layouts/site_layout.dart`. Keep `website/web/robots.txt`,
  the social card and those URLs in sync with the production domain
  `https://llamadart.leehack.com`.
- Only the latest release is indexed: `/docs/next`, archived versions and
  `unlisted: true` docs carry `noindex`, and stay out of `sitemap.xml` and
  site search.
- The header version menu lists the next docs and every published version in
  `website/versions.json`, and keeps the reader on the same page when the
  target version has it. After a docs cut, verify it opens the matching latest
  and archived installation pages without changing their package pins or the
  latest-stable default route.
