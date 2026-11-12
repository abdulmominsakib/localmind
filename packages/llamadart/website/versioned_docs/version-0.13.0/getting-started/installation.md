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
  llamadart: ^0.13.0
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
  llamadart: ^0.13.0
  llamadart_llama_cpp_flutter: ^0.13.0 # GGUF / llama.cpp
  llamadart_litert_lm_flutter: ^0.13.0 # Apple .litertlm / LiteRT-LM targets
  llamadart_stable_diffusion_flutter: ^0.13.0 # Apple image generation, opt-in
```

Companion versions released with core `0.13.0` and later share its
`MAJOR.MINOR`, depend on `llamadart`, and constrain it to that core minor, so
pub refuses a mismatched pair instead of the Apple build failing. Companion
patch versions move independently of the core's.

The companions depend on the hosted `llamadart`, and pub ignores a
dependency's own `pubspec_overrides.yaml`. An app that takes `llamadart` from
git or a path, for example with a companion from the same checkout, therefore
repeats that `llamadart` source under its own `dependency_overrides`:

```yaml
dependencies:
  llamadart:
    git: https://github.com/leehack/llamadart.git
  llamadart_llama_cpp_flutter:
    git:
      url: https://github.com/leehack/llamadart.git
      path: packages/llamadart_llama_cpp_flutter

dependency_overrides:
  llamadart:
    git: https://github.com/leehack/llamadart.git
```

Pair companion `0.13.0` with core `0.13.0` and `0.0.23` with core `0.12.2`;
keep `0.0.22` with core `0.12.1`
and `0.12.0`, and `0.0.21` with core `0.11.1` and `0.11.0`. The build checks the resolved llama.cpp and stable_diffusion companions' runtime pins and fails on
a mismatch or on an unverified local `Artifacts` override; the llama.cpp error
names the companion release of your core's minor to depend on, such as
`^0.13.0` with core `0.13.0`. That check also accepts, with a
build warning, a companion whose pin is an earlier build of the same llama.cpp
release: companion `0.0.22` (`v0.6.0-2`) still builds with core `0.12.2` and `0.13.0`,
but its frameworks lack the minimum OS version keys that App Store validation
checks, so move to the companion paired with your core before you ship. On macOS,
`llamadart_litert_lm_flutter` links and embeds the complete LiteRT-LM runtime,
including the GPU accelerators. The build uses it only when the resolved
companion's `Package.swift` is the one this core release expects; any other
companion keeps macOS LiteRT-LM in the hook cache with a build warning, and the
app then needs the [build phase below](#flutter-macos-litert-lm-build-phase).
Companion `0.0.15` is the exception: it pins `v0.18.0` rather than this core's
`v0.18.0-1`, but the app still embeds and loads the companion's complete macOS
arm64 runtime and needs no build phase, so the build only warns to upgrade the
companion to `0.0.16` or later, the releases pinning `v0.18.0-1`.
On iOS the build does not check the LiteRT-LM companion pin. `v0.18.0-1`
rebuilds the same LiteRT-LM release with arm64-only macOS XCFrameworks.

The companion's macOS XCFrameworks are published for arm64 only, so a
universal `flutter build macos` prints
`ld: warning: ignoring file ... found architecture 'arm64', required
architecture 'x86_64'` for each of them. The arm64-only build that
[Intel Macs](#intel-macs) describes removes those warnings.

Pair `llamadart_stable_diffusion_flutter` `0.13.0` with core `0.13.0`, and
`0.0.3` with core `0.12.2`, `0.12.1` and `0.12.0`. Keep `0.0.2` with core `0.11.1` and `0.11.0`, and `0.0.1` with core
`0.10.0`; older cores, including `0.9.x`, ignore it. Adding it opts iOS and
macOS builds into the image generation runtime (about 37 MB per Apple
target) on its own and leaves the other
runtimes on their current path, so leave it out unless the app uses
`ImageGenerationEngine`. An app that uses image generation without it gets the
hook-bundled runtime, whose iOS framework `MinimumOSVersion` App Store Connect
rejects; only Xcode and `xcodebuild` show the build warning about it.

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

### Intel Macs

LiteRT-LM is not available on x86_64 macOS, on an Intel Mac or under Rosetta.
From `v0.18.0-1`, `litert-lm-native` publishes macOS runtimes for arm64 only
([litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)).
llama.cpp runs on both architectures.

A universal Flutter macOS app that depends on `llamadart_litert_lm_flutter`
builds and launches on x86_64. The build hook leaves LiteRT-LM out of the
x86_64 slice and prints a `warning: llamadart:` build warning. On x86_64,
loading a `.litertlm` model or LiteRT-LM speech recognition throws
`LlamaUnsupportedException`. A Dart program on x86_64 macOS gets the same
exception. The build fails only when a `macos-x86_64` or `macos-x64` entry in
`llamadart_native_runtimes` names `litert_lm`. The same holds for an app
without the companion that uses the
[build phase](#flutter-macos-litert-lm-build-phase).

Building for arm64 only is optional. It only silences the
`ignoring file ... required architecture 'x86_64'` linker warnings for the
arm64-only LiteRT-LM XCFrameworks. To do it, add this line to
`macos/Runner/Configs/Release.xcconfig`, which the Release and Profile
configurations use:

```
EXCLUDED_ARCHS = x86_64
```

An Intel Mac then refuses to open the app. Debug builds already target only
the build Mac's architecture. For a one-off build,
`FLUTTER_MACOS_ARM64_ONLY=true flutter build macos` has the same effect.

### Flutter macOS LiteRT-LM build phase

A Flutter macOS app gets the LiteRT-LM runtime in its bundle only from a
`llamadart_litert_lm_flutter` that matches the core. With llamadart `0.12.0`
and earlier, with companion `0.0.14` or earlier, or without the companion,
the build hook leaves the libraries in its cache inside the resolved
`llamadart` package, and the app loads them from there only when it runs unsandboxed, on
the build machine, from inside the project. Under the App Sandbox, which
`flutter create` turns on, and in any copied or distributed app, the first
LiteRT-LM generation on CPU or GPU throws
`Failed to load dynamic library 'libLiteRt.dylib'`, or
`'libLiteRtMetalAccelerator.dylib'` with llamadart `0.12.0` and a newer
companion
([#1029](https://github.com/leehack/llamadart/issues/1029)). llama.cpp is not
affected.

Upgrade the core and the companion together. Until then, add a build phase
that copies the runtime into the app:

1. Open `macos/Runner.xcworkspace` in Xcode and select the **Runner** target.
2. In **Build Phases**, add a **New Run Script Phase** and drag it to the end
   of the list, after **Bundle Framework** and Flutter's own script phase.
3. Set **Shell** to `/bin/bash`, clear **Based on dependency analysis**, and
   paste:

```bash
set -euo pipefail
config=
dir="$PROJECT_DIR"
while [ "$dir" != / ]; do
  if [ -f "$dir/.dart_tool/package_config.json" ]; then
    config="$dir/.dart_tool/package_config.json"
    break
  fi
  dir="$(dirname "$dir")"
done
if [ -z "$config" ]; then
  echo "error: no .dart_tool/package_config.json above $PROJECT_DIR; run flutter pub get" >&2
  exit 1
fi
root=
count="$(plutil -extract packages raw -o - "$config")"
for ((i = 0; i < count; i++)); do
  if [ "$(plutil -extract "packages.$i.name" raw -o - "$config")" = llamadart ]; then
    root="$(plutil -extract "packages.$i.rootUri" raw -o - "$config")"
    break
  fi
done
if [ -z "$root" ]; then
  echo "error: llamadart is not resolved in $config" >&2
  exit 1
fi
case "$root" in
  file://*) root="${root#file://}" ;;
  *) root="$(dirname "$config")/$root" ;;
esac
root="$(printf '%b' "${root//%/\\x}")"
bash "$root/tool/macos_litert_lm_prepare_app.sh" "$TARGET_BUILD_DIR/$WRAPPER_NAME"
```

The script finds the resolved `llamadart` package through
`.dart_tool/package_config.json`, so it works for hosted, path and git
dependencies and in pub workspaces, and runs that package's
`tool/macos_litert_lm_prepare_app.sh`. That script copies the arm64 libraries
into `Contents/Frameworks/LiteRtLmRuntime` and signs them with the build's
signing identity. It picks the architecture from Xcode's `ARCHS`, or from the
build Mac when `ARCHS` is unset, so a universal build on an Intel Mac gets the
arm64 runtime. A build for x86_64 only, such as a Debug build on an Intel Mac,
gets a `warning:` line naming
[litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)
and no LiteRT-LM runtime. Once the companion embeds
the runtime, the script detects it and copies nothing, so the phase can be
removed.

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
   without the LiteRT-LM companion, Flutter macOS LiteRT-LM keeps its libraries
   in the hook cache and needs the
   [build phase](#flutter-macos-litert-lm-build-phase) in the app. The
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
      # llamadart_native_tag: v0.6.0-3
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
`leehack/llamadart-native@v0.6.0-3` runtime.

Every key, per-target backend and Android CPU variant selection, local bundle
paths, and fallback rules:
[Configuring native backend modules](../platforms/native-build-hooks#choose-llamacpp-backend-modules).
How the hook resolves runtimes and the Apple SwiftPM path:
[Native build hooks](../platforms/native-build-hooks).
