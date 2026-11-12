---
title: Install llamadart
sidebar_label: Installation
description: Add llamadart to a Dart or Flutter app, set up Apple and web targets, verify the install, and customize the prebuilt native runtimes.
---

## Requirements

- Dart SDK `>= 3.10.7`
- Flutter SDK `>= 3.38.0` (if you build Flutter apps)
- Flutter iOS apps: deployment target `16.4` or newer
- Flutter macOS apps: deployment target `14.0` or newer

## Add the package

```yaml
dependencies:
  llamadart: ^0.9.0
```

Then resolve packages:

```bash
dart pub get
# or
flutter pub get
```

## Flutter iOS and macOS setup

Set the app's deployment target before running: iOS `16.4` or newer, macOS
`14.0` or newer. In Xcode, set `IPHONEOS_DEPLOYMENT_TARGET = 16.4` or
`MACOSX_DEPLOYMENT_TARGET = 14.0` for the Runner configurations. An iOS app that
still uses CocoaPods also needs the Podfile platform:

```ruby
platform :ios, '16.4'
```

To link the Apple XCFrameworks through Swift Package Manager, add the runtime
companion packages you need:

```yaml
dependencies:
  llamadart: ^0.9.0
  llamadart_llama_cpp_flutter: ^0.0.20 # GGUF / llama.cpp
  llamadart_litert_lm_flutter: ^0.0.12 # Apple .litertlm / LiteRT-LM targets
```

Pair companion `0.0.20` with core `0.9.0`. The build checks the resolved
companion's runtime pin and fails on a mismatch or on an unverified local
`Artifacts` override; resolve the matching companion and rerun
`flutter pub get`. Flutter macOS LiteRT-LM builds still use the core package's
native-assets runtime rather than SwiftPM.

## Web

Web apps must load the WebGPU bridge script in their `web/index.html`; the
package does not inject it. See
[Add the bridge to your app](../platforms/webgpu-bridge#add-the-bridge-to-your-app).

## Verify it works

Run the [Quickstart](./quickstart) example with `maxTokens: 1`. If the runtime
initializes and the model loads, your setup is complete.

## What happens on first build

On the first `dart run` / `flutter run` for a native target, `llamadart`:

1. Detects platform and architecture.
2. Resolves matching runtime artifacts from `leehack/llamadart-native` and
   `leehack/litert-lm-native`.
3. Wires them into your app through native assets. Flutter iOS builds use
   SwiftPM-linked XCFrameworks when the matching companion packages are present;
   Flutter macOS LiteRT-LM can fall back to hook-managed native assets.

No local C++ toolchain setup is required for consumers.

## Customize native runtimes

Native builds bundle every available runtime family. To ship only one model
format, or to test another native build, set `hooks.user_defines` in your
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp] # or [litert_lm]
      # Compatibility testing only; omit to use the tested pin.
      # llamadart_native_tag: v0.5.0
```

A `llamadart_native_backends` request that names any backend module the target
bundle lacks is discarded whole: the hook logs a warning and bundles the
defaults instead.

Override tags name a `leehack/llamadart-native` release: stable
`vMAJOR.MINOR.PATCH`, stable wrapper rebuilds `vMAJOR.MINOR.PATCH-N`,
historical `bNNNN`, nightly wrapper rebuilds `bNNNN-N`, or consume-only
`bNNNN-llamadart.N`. Nightly cores are written without leading zeros, and
rebuild counters start at 1. Build-hook overrides must always name an explicit
tag; `latest` is limited to maintainer synchronization and header/binding
regeneration. An override does not regenerate the Dart bindings, so its
binary must stay ABI-compatible with the default
`leehack/llamadart-native@v0.5.0` runtime.

Every key, per-target backend and Android CPU variant selection, local bundle
paths, and fallback rules:
[Configuring native backend modules](../platforms/native-build-hooks#choose-llamacpp-backend-modules).
How the hook resolves runtimes and the Apple SwiftPM path:
[Native build hooks](../platforms/native-build-hooks).
