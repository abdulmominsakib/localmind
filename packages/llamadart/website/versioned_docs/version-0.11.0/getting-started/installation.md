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
- Windows: the latest Microsoft Visual C++ v14 Redistributable for the app's
  architecture (x64 or arm64) on every machine that runs the app, at least as
  new as the build tools of the bundled DLLs. Stock Windows Server lacks it;
  see
  [Native library won't load](../troubleshooting/common-issues#llamacpp-runtime-could-not-be-loaded-on-windows-x64).

## Add the package

```yaml
dependencies:
  llamadart: ^0.11.0
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

The deployment target is a build requirement, not a tested floor for every
runtime. LiteRT-LM has run on a device only on iOS 18.3.2; see
[Known limitations](../platforms/support-matrix#known-limitations).

To link the Apple XCFrameworks through Swift Package Manager, add the runtime
companion packages you need:

```yaml
dependencies:
  llamadart: ^0.11.0
  llamadart_llama_cpp_flutter: ^0.0.21 # GGUF / llama.cpp
  llamadart_litert_lm_flutter: ^0.0.13 # Apple .litertlm / LiteRT-LM targets
  llamadart_stable_diffusion_flutter: ^0.0.2 # Apple image generation, opt-in
```

Pair companion `0.0.21` with core `0.11.0`. The build checks the resolved
llama.cpp and stable_diffusion companions' runtime pins and fails on a
mismatch or on an unverified local `Artifacts` override; resolve the matching
companion and rerun `flutter pub get`. Flutter macOS LiteRT-LM builds still use
the core package's native-assets runtime rather than SwiftPM.

Pair `llamadart_stable_diffusion_flutter` `0.0.2` with core `0.11.0`, and
`0.0.1` with core `0.10.0`; older cores, including `0.9.x`, ignore it. Adding
it opts iOS and macOS builds into the image generation runtime (about 37 MB
per Apple target) on its own and leaves the other runtimes on their current
path, so leave it out unless the app uses `ImageGenerationEngine`. An app
that uses image generation without it gets the hook-bundled runtime, whose iOS
framework `MinimumOSVersion` App Store Connect rejects; only Xcode and
`xcodebuild` show the build warning about it.

An app bound for the App Store should use the companion for each runtime it
ships, because an Apple privacy manifest reaches an app inside a companion's
XCFramework and never through the hook path. The llama.cpp XCFramework has one
from `llamadart-native` `v0.5.0-1`, and the stable_diffusion one from
`stable-diffusion-native` `v0.2.0-1`.
An app that runs llama.cpp or stable_diffusion on the hook path, or whose
embedded `llama.framework` or `stable_diffusion.framework` has no
`PrivacyInfo.xcprivacy`, declares the runtime's required-reason API use in its
own `PrivacyInfo.xcprivacy`. The LiteRT-LM iOS frameworks have their own
manifests from `litert-lm-native` `v0.17.0-8`; an app that runs LiteRT-LM on
the hook path, or whose embedded LiteRT-LM frameworks have none, declares that
runtime's three categories itself. Copy the categories and codes from
[Apple privacy manifest](../platforms/native-build-hooks#apple-privacy-manifest).

## Web

Web apps must load the WebGPU bridge script in their `web/index.html`; the
package does not inject it. See
[Add the bridge to your app](../platforms/webgpu-bridge#add-the-bridge-to-your-app).

## AI agent skills

The package ships [agent skills](https://dart.dev/tools/pub/package-skills)
that teach coding agents llamadart's APIs. After `pub get`, run this from your
app's root and pick the skills and agent to install them for:

```bash
dart run skills@ get
```

Rerun it after upgrading llamadart to update the installed skills.

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
   Flutter macOS LiteRT-LM can fall back to hook-managed native assets. The
   opt-in image generation runtime comes from `leehack/stable-diffusion-native`
   the same way.

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
      # llamadart_native_tag: v0.5.0-2
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
`leehack/llamadart-native@v0.5.0-2` runtime.

Every key, per-target backend and Android CPU variant selection, local bundle
paths, and fallback rules:
[Configuring native backend modules](../platforms/native-build-hooks#choose-llamacpp-backend-modules).
How the hook resolves runtimes and the Apple SwiftPM path:
[Native build hooks](../platforms/native-build-hooks).
