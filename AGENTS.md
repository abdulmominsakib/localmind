# Repository Guidelines

## Project Structure & Module Organization

App setup lives in `lib/main.dart`, `lib/app.dart`, and `lib/bootstrap/`. Shared code belongs in `lib/core/`. Organize product code as vertical slices under `lib/features/<feature>/`, using `data/`, `providers/`, `views/`, and `utils/` as needed.

Localization sources are `lib/l10n/app_*.arb`; resources live in `assets/`. Tests mirror production areas under `test/core/` and `test/features/`. Native projects are in `android/` and `ios/`; store media belongs in `docs/`.

## Build, Test, and Development Commands

Use FVM so development matches `.fvmrc` (Flutter 3.44.2):

- `fvm flutter pub get` installs dependencies.
- `fvm flutter run` launches the selected device.
- `fvm flutter analyze` runs lints and analyzer checks.
- `fvm dart format .` formats Dart sources.
- `fvm flutter test [path]` runs all tests or a focused file.
- `fvm flutter gen-l10n` regenerates localization output.
- `fvm dart run build_runner build --delete-conflicting-outputs` refreshes ObjectBox output after entity changes.

## Architecture, Style & UI Libraries

Follow `.agents/skills/flutter-feature-based-architecture/SKILL.md` for every feature or refactor. A feature may import itself and `core/`, never a sibling feature. Keep views thin; place business rules, async work, persistence, and mutations in Riverpod notifiers or repositories. Extract UI sections into named `StatelessWidget` classes under `views/components/`, not private `_build...` helpers. Keep models and providers handwritten; ObjectBox is the existing generation exception.

Use two-space indentation and `dart format`. Name files `snake_case.dart`, types `UpperCamelCase`, and members and providers `lowerCamelCase`. Render every icon with `HugeIcon` and a `HugeIcons.*` constant; do not use Flutter `Icon` or `Icons.*`. For animation, prefer Cue, provide an explicit motion, and use one `Cue` per coordinated scene with `Actor` delays for stagger. Follow `.agents/skills/hugeicons-usage/SKILL.md` and `.agents/skills/cue-animations/SKILL.md`. Do not hand-edit generated files.

## Testing Guidelines

Tests use `flutter_test` and end in `_test.dart`. Add regression tests beside the feature; use widget tests for navigation and provider-driven UI. Run tests and analysis before a PR. The MinIO test requires `LOCALMIND_MINIO_*` variables. No numeric coverage threshold is enforced, but changed behavior should be covered.

## Commit & Pull Request Guidelines

Use Conventional Commit-style prefixes: `feat:`, `fix:`, `refactor:`, and `chore:`, with optional scopes such as `fix(providers):`. Keep subjects imperative and reference issues when relevant. PRs should explain impact and verification, link issues, include before/after UI screenshots, and call out localization, permissions, schema, or generated-file updates.

## Security & Configuration

Never commit API keys, signing material, model data, or user conversations. `private/` and `playstore_keys/` are intentionally ignored. Treat server URLs and cloud-sync credentials as sensitive test data.
