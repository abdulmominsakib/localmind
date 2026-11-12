---
title: Installation
description: Install llamadart, add the package to your app, and understand the native runtime bundle setup on first run.
---

## Prerequisites

- Dart SDK `>= 3.10.7`
- Flutter SDK `>= 3.38.0` (if you build Flutter apps)
- iOS builds require a minimum deployment target of `16.4` or newer

## iOS deployment target

If you build for iOS, set your app project and Podfile to `16.4` or newer
before running the app.

```ruby
platform :ios, '16.4'
```

In Xcode, set `IPHONEOS_DEPLOYMENT_TARGET = 16.4` for the relevant Runner
configurations.

## Add dependency

```yaml
dependencies:
  llamadart: ^0.7.0
```

Then resolve packages:

```bash
dart pub get
# or
flutter pub get
```

## What happens on first run/build

On the first `dart run` / `flutter run` for a native target, `llamadart`:

1. Detects platform and architecture.
2. Resolves the matching runtime bundle from `leehack/llamadart-native`.
3. Wires native assets into your app process.

No local C++ toolchain setup is required for consumers.

## Optional native source and backend selection

You can configure the native runtime source and backend modules per target in
your `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    llamadart:
      # Optional. Defaults to llamadart's tested native runtime pin.
      # Use a leehack/llamadart-native release tag when testing another build.
      llamadart_native_tag: b9371

      # Optional. GitHub repository slug or github.com URL.
      llamadart_native_repository: leehack/llamadart-native

      # Optional. Takes precedence over GitHub downloads when set.
      # Relative paths are resolved from the pubspec defining this config.
      # llamadart_native_path: ./native-bundles

      llamadart_native_backends:
        platforms:
          android-arm64:
            backends: [vulkan]
            cpu_profile: full # default: full; use compact for baseline-only CPU
          linux-x64: [vulkan, cuda]
          windows-x64: [vulkan, cuda]
```

Module availability is platform/arch specific and tied to the selected native
bundle tag. If `llamadart_native_tag` points at a release without a matching
bundle asset, the native-assets hook fails while downloading that asset. See
[Platform & Backend Matrix](../platforms/support-matrix) for the current
per-target module list.

Native source overrides are for compatibility testing. They do not regenerate
Dart FFI bindings or symbol lookups, so the selected binary still must be ABI-
and symbol-compatible with the default `leehack/llamadart-native@b9371` runtime.

Available native tags are published on the
[`leehack/llamadart-native` releases page](https://github.com/leehack/llamadart-native/releases).
You can also list them with the GitHub CLI:

```bash
gh release list --repo leehack/llamadart-native --limit 20
```

Before overriding, confirm the release includes the asset for your target. The
hook downloads files named `llamadart-native-<bundle>-<tag>.tar.gz`, for example
`llamadart-native-windows-x64-b9371.tar.gz`.
For local testing, `llamadart_native_path` may point directly at a bundle
archive, at an extracted bundle directory, or at a directory containing
`<tag>/<bundle>/`, `<bundle>/`, or the expected archive file.

For `android-arm64`, CPU variant policy is configurable:

- `cpu_profile: full` (default) includes all Android ARM CPU variants.
- `cpu_profile: compact` keeps baseline CPU variant only.
- `cpu_variants: [...]` (advanced) selects exact variants and overrides profile.

Canonical `cpu_variants` values:

- `android_armv8.0_1`
- `android_armv8.2_1`
- `android_armv8.2_2`
- `android_armv8.6_1`
- `android_armv9.0_1`
- `android_armv9.2_1`
- `android_armv9.2_2`

Key differences:

- `android_armv8.2_1`: `DOTPROD`
- `android_armv8.2_2`: `DOTPROD` + `FP16_VECTOR_ARITHMETIC`
- `android_armv9.2_1`: `DOTPROD` + `FP16_VECTOR_ARITHMETIC` + `MATMUL_INT8` +
  `SVE` + `SME`
- `android_armv9.2_2`: `android_armv9.2_1` + `SVE2`

Selection precedence:

1. `cpu_variants` (if present and valid)
2. `cpu_profile`
3. default `cpu_profile: full`

If requested modules are unavailable for a target, `llamadart` falls back to
safe defaults and logs warnings.

## Verify installation quickly

Run a minimal script that loads a GGUF model and generates 1 token:

```bash
dart run your_app.dart
```

If the runtime initializes and model loads successfully, your setup is complete.
