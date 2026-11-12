---
title: Apple setup
description: Set up Flutter iOS and macOS apps for llamadart with Swift Package Manager companion packages, the Apple privacy manifest, Intel Macs and the macOS LiteRT-LM build phase.
---

Flutter iOS and macOS apps link llamadart's native runtimes through Swift
Package Manager (SwiftPM) companion packages. Without a companion, the build
hook bundles bare dylibs instead. For the hook's keys and the other platforms,
see [Native runtime configuration](./native-build-hooks).

## Deployment target

Set the app's deployment target before running: iOS `16.4` or newer, macOS
`14.0` or newer. In Xcode, set `IPHONEOS_DEPLOYMENT_TARGET = 16.4` or
`MACOSX_DEPLOYMENT_TARGET = 14.0` for the Runner configurations. An iOS app that
still uses CocoaPods also needs the Podfile platform:

```ruby
platform :ios, '16.4'
```

The deployment target is a build requirement, not a tested floor for every
runtime. LiteRT-LM has run on a device only on iOS 18.3.2; see
[Known platform issues](./known-platform-issues).

## Companion packages

Add the companions you need next to `llamadart`; the dependency snippet is in
[Installation](../getting-started/installation#flutter-ios-and-macos-setup).

- `llamadart_llama_cpp_flutter` links the llama.cpp XCFrameworks (GGUF).
- `llamadart_litert_lm_flutter` links the LiteRT-LM iOS and macOS
  XCFrameworks (`.litertlm` models), including the macOS WebGPU accelerator,
  sampler and Dawn. The Metal accelerator and sampler stay iOS-only; the macOS
  GPU path uses WebGPU.
- `llamadart_stable_diffusion_flutter` links the stable-diffusion.cpp
  XCFramework for [image generation](../guides/image-generation). It is opt-in:
  adding it opts iOS and macOS builds into the image generation runtime (about
  37 MB per Apple target) on its own and leaves the other runtimes on their
  current path, so leave it out unless the app uses `ImageGenerationEngine`. An
  app that uses image generation without it gets the hook-bundled runtime,
  whose iOS framework `MinimumOSVersion` App Store Connect rejects; only Xcode
  and `xcodebuild` show the build warning about it.

A companion counts when the app's `dependencies` reach it, directly or
through another package such as a shared app package, because Flutter links
it either way. One reached only through `dev_dependencies` does not count, and
without a readable `.dart_tool/package_graph.json` only direct dependencies
do.

When the llama.cpp or LiteRT-LM companion is present, the installed companions
choose the Apple `llama_cpp` and `litert_lm` families and the rest of
`llamadart_native_runtimes` is ignored with a warning. `stable_diffusion` is
decided on its own: its companion selects it, and otherwise the hook bundles it
when `llamadart_native_runtimes` names it, not when `all` only implies it.
Adding only the stable_diffusion companion leaves llama.cpp and LiteRT-LM on
the hook. The tag, repository, path and backend keys do not change SwiftPM
binaries; their pins live in each companion's `Package.swift`, so use a path or
git override or a fork of the companion.

### Versions

Companion versions released with core `0.13.0` and later share its
`MAJOR.MINOR`, depend on `llamadart`, and constrain it to that core minor, so
pub refuses a mismatched pair instead of the Apple build failing. Companion
patch versions move independently of the core's.

The build also checks the resolved companions' runtime pins and fails on a
mismatch or on an unverified local `Artifacts` override. The llama.cpp error
names the companion release to depend on, such as `^0.17.1` with core `0.17.1`.
A llama.cpp companion pinning an earlier release is accepted, with an upgrade
warning, only when the core explicitly lists that pin as ABI-compatible; any
other earlier pin is rejected. The stable_diffusion check accepts only the
core's own pin.

### Git and path dependencies

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

### macOS LiteRT-LM

On macOS, `llamadart_litert_lm_flutter` links and embeds the complete LiteRT-LM
runtime, including the GPU accelerators. The hook hands LiteRT-LM to the
companion only when the resolved companion's `Package.swift` is the maintained
manifest pinning the core's LiteRT-LM release. Any other companion keeps macOS
LiteRT-LM in the hook cache with a build warning; a sandboxed, copied or
distributed app cannot read that cache and needs the
[build phase](#flutter-macos-litert-lm-build-phase). A companion with the
maintained manifest pinning an earlier build of the same LiteRT-LM release
still embeds the complete macOS arm64 runtime, which the app loads from its
bundle and needs no build phase, so the build only warns to upgrade the
companion. A maintained manifest pinning any other LiteRT-LM release or a later
build of the same release warns to upgrade the core and companion together. On
iOS the build does not check the LiteRT-LM companion pin.

The companion's macOS XCFrameworks are published for arm64 only, so a
universal `flutter build macos` prints
`ld: warning: ignoring file ... found architecture 'arm64', required
architecture 'x86_64'` for each of them. The arm64-only build that
[Intel Macs](#intel-macs) describes removes those warnings.

Without a companion, and for non-Flutter or non-Apple builds, the hook path
applies. Standalone Dart on macOS keeps LiteRT-LM libraries in the hook cache.
A custom launcher can set `LLAMADART_LITERT_LM_LIB_DIR` to the extracted
LiteRT-LM directory.

### Pub workspaces and host tests

In a pub workspace, pub passes the hook the root `pubspec.yaml`. A root that
is itself a Flutter app is the app: its companions are the ones its
`dependencies` reach, as above, including through members it depends on, and
other members are not consulted. Otherwise the hook reads the companions from the member
app: the member that reaches llamadart through its dependencies or dev
dependencies and that no other member lists under `dependencies`, found
through the root `.dart_tool/package_graph.json`. A `dev_dependencies` entry
on another member does not make a member a library. Debug and profile builds
include the app's dev dependencies, so those count on every target; only
Flutter builds target iOS, so for iOS the hook ignores non-Flutter members.
The app's companions are the ones its `dependencies` reach, as above,
including through other members. Every member shares the hook's output, so
when several such members exist they must be Flutter apps reaching the same
companions. Otherwise, or when the graph cannot be read, the build writes a
`warning: llamadart:` line and bundles the hook's Apple assets without
checking or linking any companion; give the apps the same companions or move
them into separate workspaces. `flutter build ios` does not show hook
warnings; Xcode and `xcodebuild` do. A workspace with no Flutter member that
uses llamadart bundles the hook's assets.

Host `flutter test` on macOS runs in `flutter_tester`, which links no
companion. A test that loads llama.cpp or stable_diffusion where a companion
provides it cannot resolve the runtime's symbols; macOS LiteRT-LM falls back to
the hook cache. In a pub workspace this covers the host tests of every member,
library members included, because they share the app's hook output.

## Apple privacy manifest

The llama.cpp and stable-diffusion.cpp runtimes call `stat` and `fstat`, which
Apple lists as File Timestamp
[required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
A privacy manifest for that use reaches an app inside the XCFramework a
companion package links. The hook path cannot carry one: it bundles bare
dylibs, which Flutter wraps in frameworks it generates. An app bound for the
App Store should use the companion for each runtime it ships; its XCFramework
carries the manifest.

An app declares the use in its own `PrivacyInfo.xcprivacy` when it runs
llama.cpp or stable_diffusion on the hook path, or when the built app has no
`PrivacyInfo.xcprivacy` inside the embedded `llama.framework` or
`stable_diffusion.framework`:

| Runtime | Category | Reasons |
| --- | --- | --- |
| llama.cpp | `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` |
| stable-diffusion.cpp | `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1`, `3B52.1` |

Put the entry inside the top-level `<dict>` of a `PrivacyInfo.xcprivacy` in
the app (Runner) target, merged with the reasons the rest of the app needs. An
app that also runs LiteRT-LM on the hook path adds that runtime's categories,
listed below.
For an app that ships llama.cpp without stable_diffusion:

```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
      <string>C617.1</string>
    </array>
  </dict>
</array>
```

Only an app that ships stable_diffusion adds `<string>3B52.1</string>` to the
reasons array.

Apple's requirement covers iOS, iPadOS, tvOS, visionOS and watchOS apps. The
app-level declaration is a workaround for a runtime without its own manifest;
llamadart has not verified it with an App Store Connect upload.

The LiteRT-LM iOS frameworks reference required-reason API in three
categories: File Timestamp (`stat`, `fstat`, `lstat`), System Boot Time
(`mach_absolute_time`) and User Defaults (`NSUserDefaults`, in the Metal
accelerator and sampler). Each framework
the companion links on iOS carries a manifest for what that framework
references:

| Framework | Category | Reasons |
| --- | --- | --- |
| `LiteRtLm` | `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1`, `3B52.1` |
| `LiteRtLm` | `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` |
| `LiteRtMetalAccelerator` | `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1`, `3B52.1` |
| `LiteRtMetalAccelerator` | `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` |
| `LiteRtTopKMetalSampler` | `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` |
| `CLiteRTLM` | None: its manifest declares no API | |

An app declares those three categories, with the same reasons, in its own
`PrivacyInfo.xcprivacy` when it runs LiteRT-LM on the hook path, or when the
built app has no `PrivacyInfo.xcprivacy` inside the embedded LiteRT-LM
frameworks. On macOS, which Apple's requirement does not cover, the
companion's `LiteRtLm.framework` carries a File Timestamp manifest, while its
flat dylibs
(`libCLiteRTLM_mac`, `libLiteRt`, the WebGPU accelerator and sampler, and
`libwebgpu_dawn`) and the hook-managed runtime dylibs are bare libraries
without one. The reasons come from the runtime owner's
[audit of the binaries](https://github.com/leehack/litert-lm-native/blob/v0.17.0-8/docs/apple_privacy_manifest.md)
([litert-lm-native#65](https://github.com/leehack/litert-lm-native/issues/65));
llamadart has not verified them, or an app-level declaration, with an App
Store Connect upload.

## Intel Macs

LiteRT-LM is not available on x86_64 macOS, on an Intel Mac or under Rosetta.
`litert-lm-native` publishes macOS runtimes for arm64 only
([litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)).
llama.cpp runs on both architectures. On x86_64, Rosetta included,
llama.cpp `GpuBackend.auto` runs on the CPU, because Metal returns garbled
output on Intel Macs with AMD GPUs ([#1597](https://github.com/leehack/llamadart/issues/1597)); `GpuBackend.metal` or
`ComputeDevice.gpu` still loads on Metal, with a warning.

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

## Fresh macOS SwiftPM bootstrap

If a fresh build reports that a companion requires macOS 14.0 but
`FlutterGeneratedPluginSwiftPackage` supports 12.0, use this bootstrap with
Flutter 3.47.1 ([#1139](https://github.com/leehack/llamadart/issues/1139)).
Keep Runner's deployment target at **14.0 or newer** for every configuration.
The companions' 14.0 requirement reflects the shipped binaries.

Flutter generates the plugin package at 12.0, then queries Xcode project
information and build settings before raising that package's floor to Runner's
target. Those queries resolve Swift packages too. If resolution rejects the
12.0 package, Flutter cannot reach its deployment-target update. Runner settings
and a CocoaPods Podfile do not set the generated Swift package's platform.
Changing the companions' metadata to 12.0 would misrepresent their requirements.

Run the following from the **consumer app directory** (the chat example uses
`example/chat_app`). It requires Python 3 and changes only the ignored generated
package, preserving all companion manifests, URLs and checksums:

```bash
(
set -e
flutter pub get
python3 - <<'PY'
from pathlib import Path

manifest = Path("macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift")
contents = manifest.read_text()
old = '.macOS("12.0")'
if contents.count(old) != 1:
    raise SystemExit("Expected one generated macOS 12.0 floor; inspect the manifest and Flutter version.")
manifest.write_text(contents.replace(old, '.macOS("14.0")', 1))
PY
flutter build macos --debug --no-pub
)
```

Use `--no-pub` for this build: ordinary Flutter commands can regenerate the
12.0 manifest before building. Run the **whole sequence** again after
`flutter clean`, deleting `macos/Flutter/ephemeral`, changing dependencies or
running `flutter pub get`; do not commit generated files. The guard stops on
an unexpected SDK manifest instead of silently claiming to repair it. This is
a consumer bootstrap, not a Flutter SDK fix; the upstream defect is tracked in
[flutter/flutter#186804](https://github.com/flutter/flutter/issues/186804) and
[flutter/flutter#162196](https://github.com/flutter/flutter/issues/162196).

A fresh ordinary `flutter build macos --debug` succeeds on our Xcode 27.1 host
with Flutter 3.47.1. The original first-build failure was reported with Xcode
27; the bootstrap is for affected toolchains and direct Xcode builds before
Flutter has updated the generated floor. iOS still requires Runner's 16.4 floor;
no iOS manifest workaround is needed for the verified fresh
`flutter build ios --simulator`. Direct Xcode iOS builds are unverified.

## Flutter macOS LiteRT-LM build phase

Skip this section if the app depends on `llamadart_litert_lm_flutter`; it
embeds the runtime. Only without that companion, the build hook leaves the
LiteRT-LM libraries in its cache inside the resolved `llamadart` package, and
the app loads them from there only when it runs unsandboxed, on the build
machine, from inside the project. Under the App Sandbox, which `flutter create`
turns on, and in any copied or distributed app, the first LiteRT-LM generation
on CPU or GPU throws `Failed to load dynamic library 'libCLiteRTLM_mac.dylib'`
([#1029](https://github.com/leehack/llamadart/issues/1029)). llama.cpp is not
affected.

Add a build phase that copies the runtime into the app:

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
signing identity, and replaces a runtime already copied by an earlier
version. It picks the architecture from Xcode's `ARCHS`, or from the
build Mac when `ARCHS` is unset, so a universal build on an Intel Mac gets the
arm64 runtime. A build for x86_64 only, such as a Debug build on an Intel Mac,
gets a `warning:` line naming
[litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)
and no LiteRT-LM runtime. Once the companion embeds
the runtime, the script detects it and copies nothing, so the phase can be
removed.
