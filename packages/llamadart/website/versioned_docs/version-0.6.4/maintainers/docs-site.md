---
title: Maintainer Overview
---

This section is for `llamadart` maintainers, not general Docusaurus usage.

## Repository ownership map

- `llamadart` (this repo): Dart API surface, hooks integration, docs/tests.
- `llamadart-native`: native build graph, runtime bundle matrix, release assets.
- `llama-web-bridge`: web bridge runtime source/build behavior.
- `llama-web-bridge-assets`: published bridge artifacts consumed by this repo.

## Local maintainer workspace convention

Many maintainers keep sibling checkouts one level above this repo:

```text
../llamadart
../llamadart-native
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
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
./tool/docs/build_site.sh
./tool/docs/validate_links.sh
```

Use targeted test commands when iterating quickly, then run full checks before
release-related merges.
