---
title: Install llamadart
sidebar_label: Installation
description: Add llamadart to a Dart or Flutter app, set up web targets, verify the install, and customize the prebuilt native runtimes.
---

For Genkit or Flutter Edge AI integration setup, see
[Choose an integration](../integrations/choosing-an-api).

## Requirements

- Dart SDK `>= 3.10.7`
- Flutter SDK `>= 3.38.0` (if you build Flutter apps)
- Flutter iOS apps: deployment target `16.4` or newer
- Flutter macOS apps: deployment target `14.0` or newer
- Windows: nothing extra for llama.cpp and LiteRT-LM, which bundle the
  Visual C++ runtime DLLs they need. Machines that run the opt-in
  `stable_diffusion` runtime need the latest Microsoft Visual C++ v14
  Redistributable (x64), which stock Windows Server lacks; see
  [Image generation](../guides/image-generation).

## Add the package

```yaml
dependencies:
  llamadart: ^0.17.4
```

Then resolve packages:

```bash
dart pub get
# or
flutter pub get
```

## Flutter iOS and macOS setup

Set the deployment target (iOS `16.4` or newer, macOS `14.0` or newer), then
add the runtime companion packages you need so Swift Package Manager links the
Apple XCFrameworks:

```yaml
dependencies:
  llamadart: ^0.17.4
  llamadart_llama_cpp_flutter: ^0.17.2 # GGUF / llama.cpp
  llamadart_litert_lm_flutter: ^0.17.2 # Apple .litertlm / LiteRT-LM targets
  llamadart_stable_diffusion_flutter: ^0.17.2 # Apple image generation, opt-in
```

Companions use the core's `MAJOR.MINOR`; pub refuses a mismatched pair.
[Apple setup](../platforms/apple-setup) covers deployment targets, companion
versions and checks, the privacy manifest, Intel Macs, the SwiftPM bootstrap for
a fresh macOS build, and the LiteRT-LM build phase.

## Web

Web apps must load the WebGPU bridge script in their `web/index.html`; the
package does not inject it. From the app root, run:

```bash
dart run llamadart:web_setup
```

It vendors the pinned bridge assets into `web/webgpu_bridge/`, verifies their
checksums and adds the bootstrap to `web/index.html`; rerun it after upgrading
llamadart. See
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
   without the LiteRT-LM companion, Flutter macOS LiteRT-LM keeps its libraries
   in the hook cache and needs the
   [build phase](../platforms/apple-setup#flutter-macos-litert-lm-build-phase)
   in the app. The
   opt-in image generation runtime comes from `leehack/stable-diffusion-native`
   the same way.

No local C++ toolchain setup is required for consumers.

## Customize native runtimes

Native builds bundle llama.cpp and LiteRT-LM by default; image generation is opt-in. To ship only one model
format, or to test another native build, set `hooks.user_defines` in your
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp] # or [litert_lm]
      # Compatibility testing only; omit to use the tested pin.
      # llamadart_native_tag: v0.8.0-1
```

An override tag names a `leehack/llamadart-native` release and must be explicit;
the accepted forms are in
[Override the llama.cpp release](../platforms/native-build-hooks#override-the-llamacpp-release).
An override does not regenerate the Dart bindings, so its binary must stay
ABI-compatible with the default `leehack/llamadart-native@v0.8.0-1` runtime.
Do not point a core before `0.17.1` at native `v0.8.0` or later: its bindings
give `mtmd_helper_init_opt` 24 bytes, and `v0.8.0` writes past them.

Every key, per-target backend and Android CPU variant selection, local bundle
paths, and fallback rules:
[Configuring native backend modules](../platforms/native-build-hooks#choose-llamacpp-backend-modules),
including what happens when
[a requested backend is not bundled](../platforms/native-build-hooks#when-a-requested-backend-is-not-bundled).
How the hook resolves runtimes: [Native runtime configuration](../platforms/native-build-hooks).
Apple SwiftPM path: [Apple setup](../platforms/apple-setup). Setup check:
[Diagnose setup](../platforms/diagnose-setup).

## Moved topics

These sections have moved. Published package README links continue to land here.

### Fresh macOS SwiftPM bootstrap

See [Fresh macOS SwiftPM bootstrap](../platforms/apple-setup#fresh-macos-swiftpm-bootstrap) for the current instructions.

### Flutter macOS LiteRT-LM build phase

See [Flutter macOS LiteRT-LM build phase](../platforms/apple-setup#flutter-macos-litert-lm-build-phase) for the current instructions.
