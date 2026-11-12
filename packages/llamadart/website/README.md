# llamadart docs site

The [Jaspr](https://jaspr.site) static site published at
https://llamadart.leehack.com. Use the Flutter SDK pinned in
`../.flutter-version`; the search index step also needs Node.js for `npx`.

## Develop

```bash
cd website
dart pub get
DOCS_ARCHIVED=0 dart run jaspr_cli:jaspr serve
```

`DOCS_ARCHIVED=<n>` limits the build to the newest `n` archived releases.

## Build, check and preview (repo root)

```bash
./tool/docs/build_site.sh
(cd website && dart analyze --fatal-infos && dart test)
(cd website && dart run tool/serve_site.dart --port 8080)
```

The build fails on any broken internal link or anchor.

## Content

- `docs/` and `sidebars.json`: docs for the next release (`/docs/next`).
- `versioned_docs/`, `versioned_sidebars/`, `versions.json`: released
  snapshots; the first version is the latest and is served at `/docs`.
- `web/`: static assets. Put images in `web/img/` and link them as
  `/img/<name>`.

API references link to https://pub.dev/documentation/llamadart/latest/.

## Versioning

Release tags run `.github/workflows/docs_version_cut.yml`. To cut a version by
hand:

```bash
cd website
dart run tool/cut_version.dart <version>
```

See `docs/maintainers/docs-site.md` for the full maintainer guide.
