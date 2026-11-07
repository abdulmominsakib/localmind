# Test Suite Layout

This project organizes tests into three layers:

- `test/unit/`: fast, deterministic tests that mirror `lib/src/` structure.
- `test/integration/`: multi-component scenarios that still run in CI.
- `test/e2e/`: slow or resource-heavy scenarios tagged `local-only`.

## Running tests

```bash
# Default suite (VM + Chrome-compatible tests)
dart test

# Only VM tests
dart test -p vm

# Only browser tests
dart test -p chrome

# Local-only E2E tests
dart test --run-skipped -t local-only

# Enumerate repeatable local browser/device smoke scenarios
dart run tool/testing/run_local_e2e.dart --list

# Print the contributor validation matrix and PR evidence table
dart run tool/testing/test_matrix.dart --list
dart run tool/testing/test_matrix.dart --pr-template
dart run tool/testing/test_matrix.dart --tier platform

# Real Gemma 4 LiteRT-LM web smoke
dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-litert-gemma4-smoke

# Template parity suites (sequential, local-only e2e included)
tool/testing/run_template_parity_suites.sh
```

## Conventions

- `test/unit/` is strictly mirrored to `lib/src/` (except the structure guard test itself).
- The mirrored mapping is enforced by `test/unit/test_structure/mirrored_unit_structure_test.dart`.
- Files marked as generated (`// coverage:ignore-file` or `AUTO GENERATED FILE, DO NOT EDIT.`) are excluded from strict mirroring.
- Cross-file regressions and diagnostics belong in `test/integration/`.
- Mark platform-specific files with `@TestOn('vm')` or `@TestOn('browser')`.
- Use `@Tags(['local-only'])` for tests that should not run in default/CI flows.
