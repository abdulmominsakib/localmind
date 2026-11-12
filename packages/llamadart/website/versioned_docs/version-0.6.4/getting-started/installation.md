---
title: Installation
---

## Prerequisites

- Dart SDK `>= 3.10.7`
- Flutter SDK `>= 3.38.0` (if you build Flutter apps)

## Add dependency

```yaml
dependencies:
  llamadart: ^0.6.4
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

## Optional backend selection (non-Apple)

You can configure backend modules per target in your `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_backends:
        platforms:
          android-arm64:
            backends: [vulkan]
            cpu_profile: full # default: full; use compact for baseline-only CPU
          linux-x64: [vulkan, cuda]
          windows-x64: [vulkan, cuda]
```

Module availability is platform/arch specific and tied to the pinned native
bundle tag. See [Platform & Backend Matrix](../platforms/support-matrix) for
the current per-target module list.

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
