---
title: Installation
---

## Prerequisites

- Dart SDK `>= 3.10.7`
- Flutter SDK `>= 3.38.0` (if you build Flutter apps)

## Add dependency

```yaml
dependencies:
  llamadart: ^0.6.2
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
          android-arm64: [vulkan]
          linux-x64: [vulkan, cuda]
          windows-x64: [vulkan, cuda]
```

Module availability is platform/arch specific and tied to the pinned native
bundle tag. See [Platform & Backend Matrix](../platforms/support-matrix) for
the current per-target module list.

If requested modules are unavailable for a target, `llamadart` falls back to
safe defaults and logs warnings.

## Verify installation quickly

Run a minimal script that loads a GGUF model and generates 1 token:

```bash
dart run your_app.dart
```

If the runtime initializes and model loads successfully, your setup is complete.
