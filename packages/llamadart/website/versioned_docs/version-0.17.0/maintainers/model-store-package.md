---
title: Maintain the model store package
description: Versioning, CI and release status of the independently versioned llamadart_model_store package.
---

`packages/llamadart_model_store` is an independently versioned Flutter
package, as decided in
[#160](https://github.com/leehack/llamadart/issues/160#issuecomment-6432945840).
The dependency is one-way: `llamadart_model_store` → `llamadart`. Never add it
to core dependencies or align its version with core or the Apple companions.

## Versioning and publication

- It starts at `0.1.0` and moves on its own semantic versions. Its
  `llamadart` constraint names the core minor it needs, today `^0.17.0`.
- It is not published and has no release routing: no prep branch pattern,
  tag prefix or publisher workflow. Publication needs maintainer approval and
  its own routing, modeled on the [Genkit package](./genkit-package): a
  package-only prep PR, a `llamadart_model_store-vX.Y.Z` tag that neither the
  core nor the companion publishers match, and a standalone staged archive.
- The core archive excludes the package (`.pubignore`,
  `tool/release/check_core_archive.py`).

## Local checks and CI

Root preparation, analysis and tests skip the package. It resolves with
Flutter against checkout core through its committed `pubspec_overrides.yaml`.
From `packages/llamadart_model_store`:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
TMPDIR="$(mktemp -d)" flutter test
flutter test --platform chrome test/model_store_web_test.dart
```

The `model-store` CI job runs these and a publish dry-run against checkout
core. The selector runs it for package and guide changes, and for every core
or shared change, which selects the full graph. Package-only changes select
no core lane. A lower-bound lane against published core is added once
`llamadart` 0.17.0 is on pub.dev.
