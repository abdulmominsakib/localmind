---
title: Native runtime configuration
sidebar_label: Runtime configuration
description: Configure which prebuilt llama.cpp and LiteRT-LM runtimes and backend modules the llamadart build hook bundles, and how to override the native release.
---

The `llamadart` build hook (`hook/build.dart`) downloads prebuilt llama.cpp and
LiteRT-LM runtimes for the target platform, so apps never compile C++. The hook
reports the downloaded `.so`, `.dylib` and `.dll` files as `package:code_assets`
code assets, and the Flutter or Dart build bundles them into the APK, IPA or
desktop app. On macOS, the hook does not report LiteRT-LM libraries: they stay
in the hook cache inside the resolved `llamadart` package. `dart run` loads
them from there and a `dart build cli` bundle needs
`LLAMADART_LITERT_LM_LIB_DIR`. A Flutter macOS app gets them from the
`llamadart_litert_lm_flutter` companion instead
([Flutter Apple apps](#flutter-apple-apps)); without it, the app needs the
[LiteRT-LM build phase](../getting-started/installation#flutter-macos-litert-lm-build-phase)
to copy them into the app bundle.

Configure the hook under `hooks.user_defines.llamadart` in the app's
`pubspec.yaml`. Every key is optional:

| Key | Selects | Default |
| --- | --- | --- |
| `llamadart_native_runtimes` | Runtime families to bundle: `llama_cpp`, `litert_lm`, and the opt-in `stable_diffusion` | `llama_cpp` and `litert_lm` where published; `llama_cpp` only [alongside Flutter Edge AI](#alongside-flutter-edge-ai) |
| `llamadart_native_backends` | llama.cpp backend modules, and Android arm64 CPU variants | `cpu` and `vulkan` where present |
| `llamadart_stable_diffusion_backends` | The `stable_diffusion` build on Linux and Windows: `cpu` or `vulkan` | Follows `llamadart_native_backends` |
| `llamadart_native_tag` | `leehack/llamadart-native` release to download | The [pinned release](./support-matrix#pinned-runtimes) |
| `llamadart_native_repository` | GitHub repository to download llama.cpp bundles from | `leehack/llamadart-native` |
| `llamadart_native_path` | Local archive or bundle directory used instead of a download | Unset |

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp]
      llamadart_native_backends:
        platforms:
          android-arm64:
            backends: [vulkan]
            cpu_profile: compact
          linux-x64: [vulkan, cuda]
          windows-x64: [vulkan, cuda, blas]
```

After changing any of these keys, or after a native release tag is republished
with new assets, run `flutter clean` once so stale native assets are not
reused.

## Choose runtime families

`llamadart_native_runtimes` keeps whole runtimes out of the app when it ships
only one model format. The value is a list, or a map with a top-level
`runtimes` list and per-platform overrides under `platforms`:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes:
        runtimes: [llama_cpp, litert_lm]
        platforms:
          ios: [llama_cpp]
          android-arm64: [litert_lm]
```

- Platform keys are OS names (`android`, `ios`, `linux`, `macos`, `windows`) or
  bundle keys: `android-arm64`, `android-x64`, `ios-arm64`, `ios-arm64-sim`,
  `ios-x86_64-sim`, `linux-arm64`, `linux-x64`, `macos-arm64`,
  `macos-x86_64`, `windows-arm64` and `windows-x64`. For each bundle the
  exact bundle key wins, then its OS key, then `runtimes`, then the default
  `llama_cpp` and `litert_lm`.
- Aliases: `gguf`, `llama`, `llama.cpp` for `llama_cpp`; `litert`,
  `litert-lm`, `litertlm`, `.litertlm` for `litert_lm`; `stable-diffusion` for
  `stable_diffusion`. `all` selects every family, the opt-in
  `stable_diffusion` included; `both` selects `llama_cpp` and `litert_lm`, the
  same as leaving the key unset. Unknown names are dropped with a warning.
- Selecting `litert_lm` by name for a target without a LiteRT-LM runtime, such
  as the iOS x86_64 simulator or Windows arm64, fails the build. When it is only
  implied by the default, `both` or `all`, the hook drops it with a warning.
- macOS x86_64 is the exception, because a universal build runs the hook for
  x86_64 too
  ([litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)).
  Only a `macos-x86_64` or `macos-x64` entry that names `litert_lm` fails the
  build. A `runtimes` or `macos` entry that names it gets a warning and no
  LiteRT-LM in the x86_64 slice. `[litert_lm]` alone leaves that slice with no
  native assets, and loading a `.litertlm` model there throws
  `LlamaUnsupportedException`. `LLAMADART_LITERT_LM_LIB_DIR` does not lift
  that error on x86_64; a `libraryPath` passed to `LiteRtLmRuntimeClient`
  does.
- An empty or all-unknown selection falls back to `llama_cpp` and
  `litert_lm`; one that leaves no runtime, such as `none`, fails the build.

### Alongside Flutter Edge AI

`flutter_edge_ai_litertlm` ships its own copy of the LiteRT-LM libraries
llamadart bundles, and `flutter_edge_ai_llama` uses only the llama.cpp
runtime. When the app depends on llamadart together with either package:

- An unset key, `both` and `all` leave `litert_lm` out, and the hook writes a
  `warning: llamadart:` line that names the package to the build's error
  output. `all` still bundles `stable_diffusion`. Flutter's `--fatal-warnings`
  fails a build that prints the line; `llamadart_native_runtimes: [llama_cpp]`
  selects the same runtimes without it.
- Naming `litert_lm` keeps it next to `flutter_edge_ai_llama`.
- Naming `litert_lm` next to `flutter_edge_ai_litertlm` fails the build before
  anything is downloaded. On iOS and macOS, depending on
  `llamadart_litert_lm_flutter` counts as naming it. Set
  `llamadart_native_runtimes: [llama_cpp]` and remove that companion.

The build does not tell the hook which app it is building, and every package
resolved into one `.dart_tool` shares the hook's output: one app, or all
members of a pub workspace. The hook therefore reads
`.dart_tool/package_graph.json` and applies the rules above when any root
package there reaches both llamadart and one of the two packages through its
dependencies. A root's `dev_dependencies` count, because `dart run`,
`dart test` and non-release Flutter builds bundle them. In a pub workspace:

- The build reads `hooks.user_defines` from the workspace root `pubspec.yaml`
  only, so set `llamadart_native_runtimes` there.
- One member that combines llamadart with such a package changes the default
  for every member. A member that loads `.litertlm` models through llamadart
  needs `litert_lm` named at the root, which fails while any member combines
  llamadart with `flutter_edge_ai_litertlm`; move one of the two out of the
  workspace.

If the hook cannot read the graph file it keeps the configured runtimes and
logs a warning. Web builds bundle no native runtime and are unaffected.

### Opt-in stable_diffusion runtime (experimental)

`stable_diffusion` bundles the
[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) runtime
from `leehack/stable-diffusion-native` for the experimental
[`ImageGenerationEngine`](../guides/image-generation). It adds about 40 to
70 MB per target, so it is never bundled by default or by `both`; name it, or
select `all`. Unset, `llamadart_native_runtimes` bundles `llama_cpp` and
`litert_lm`, or `llama_cpp` only
[alongside Flutter Edge AI](#alongside-flutter-edge-ai); a list replaces those
defaults, so it names every runtime the app loads:

| The app loads | `llamadart_native_runtimes` |
| --- | --- |
| GGUF and `.litertlm` models | unset |
| Images only | `[stable_diffusion]` |
| GGUF models and images | `[llama_cpp, stable_diffusion]` |
| Every runtime published for the target | `all` |

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: all
```

- `all` only implies its runtimes, so a target without a LiteRT-LM or
  `stable_diffusion` build skips that runtime with a warning.
  `[llama_cpp, litert_lm, stable_diffusion]` names `litert_lm` and fails the
  build on a target without it, except macOS x86_64, which only warns unless a
  `macos-x86_64` or `macos-x64` entry names it.
- In a Flutter iOS or macOS app, `all` includes `stable_diffusion` only when
  the `llamadart_stable_diffusion_flutter` companion is a dependency. Without
  it the hook leaves the runtime out with a build warning that names the
  companion, and `ImageGenerationEngine.checkRuntime()` reports it as not
  bundled. `flutter build macos`, Xcode and `xcodebuild` show the warning;
  `flutter build ios` output does not. Naming `stable_diffusion` still bundles
  it through the hook there.
  The hook reads the pubspec that carries the user-defines, so a Flutter app
  that is a pub workspace member, whose user-defines live in the workspace
  root pubspec, is not recognised as a Flutter app: `all` at the root bundles
  the runtime through the hook with no warning.
- Published for `android-arm64`, `ios-arm64`, `ios-arm64-sim`,
  `ios-x86_64-sim`, `macos-arm64`, `macos-x86_64`, `linux-arm64`, `linux-x64`
  and `windows-x64`, built for iOS
  16.4 and macOS 13.3 or newer. At run time the engine checks the CPU before
  loading the library: Android needs an Armv8.2 CPU with dot-product and fp16
  (`asimddp`, `fphp`, `asimdhp`), and Linux and Windows x64 need AVX2, FMA,
  F16C and BMI2. Otherwise `ImageGenerationEngine.load` throws
  `LlamaUnsupportedException` instead of crashing on an illegal
  instruction. On Windows the runtime also needs the latest Microsoft Visual
  C++ v14 Redistributable (x64); stock Windows Server lacks it, and the
  error names the DLL that failed to load.
- Apple builds use the Metal build and Android the CPU build. Linux and Windows
  publish a CPU build (about 38 MB) and a Vulkan build (about 72 MB) that needs
  the system Vulkan loader (`libvulkan.so.1` or `vulkan-1.dll`) at run time.
  `llamadart_stable_diffusion_backends` picks one, as a list for every
  platform or a `platforms` map like `llamadart_native_backends`:

  ```yaml
  hooks:
    user_defines:
      llamadart:
        llamadart_stable_diffusion_backends: [cpu]
        # or per platform:
        # llamadart_stable_diffusion_backends:
        #   platforms:
        #     linux: [vulkan]
        #     windows: [cpu]
  ```

  It accepts `cpu` and `vulkan` (alias `vk`) and leaves the llama.cpp
  backends unchanged. A list naming `vulkan` selects the Vulkan build even
  when it also names `cpu`. Without an entry for the platform, or with an
  empty one, the build follows `llamadart_native_backends` for the same
  platform: Vulkan when Vulkan is selected there, which is the default, and
  CPU otherwise. A value naming neither `cpu` nor `vulkan` is ignored with a
  build warning and the same fallback applies.
- Other targets, such as `android-x64` or Windows arm64, are skipped with a
  warning. Naming it for that exact bundle key, for example
  `android-x64: [stable_diffusion]`, fails the build instead.
- Flutter iOS and macOS apps should add the `llamadart_stable_diffusion_flutter`
  companion instead; see [Flutter Apple apps](#flutter-apple-apps). Without it
  a list naming `stable_diffusion` makes the hook bundle the runtime, and App
  Store Connect rejects that iOS framework: Flutter writes `MinimumOSVersion`
  13.0 into it, while the library needs iOS 16.4. The hook reports this as an
  Xcode build warning, which Xcode and `xcodebuild` show but plain
  `flutter build` and `flutter run` output does not.

## Choose llama.cpp backend modules

`llamadart_native_backends` filters the split llama.cpp modules inside the
`llama_cpp` family; it does not affect LiteRT-LM. It is set per platform,
under `platforms` or as a map keyed by platform. A platform value is a list, a
comma-separated string, or a map with a `backends` list. A bare top-level list
applies to no platform.

Modules in the pinned bundles:

| Bundle | Modules |
| --- | --- |
| `android-arm64`, `android-x64` | `cpu`, `vulkan`, `opencl` |
| `linux-arm64` | `cpu`, `vulkan`, `blas` |
| `linux-x64` | `cpu`, `vulkan`, `blas`, `cuda`, `hip` |
| `windows-arm64` | `cpu`, `vulkan`, `blas` |
| `windows-x64` | `cpu`, `vulkan`, `blas`, `cuda` |
| `ios-*`, `macos-*` | One consolidated CPU and Metal runtime; not configurable |

Aliases: `vk` for `vulkan`; `ocl` and `open-cl` for `opencl`.
`GpuBackend.metal` still selects Metal at runtime on Apple targets.

Selection rules:

- With no request, the hook bundles `cpu` and `vulkan`, where present.
- `cpu` is always added when the bundle has it.
- A request that names any module the bundle lacks is rejected whole: the hook
  warns and uses the defaults. If the defaults are missing too, it bundles every
  module.
- CUDA runtime DLLs (`cudart64_*`, `cublas64_*`, `cublaslt64_*`) ship only with
  `cuda`, and OpenBLAS libraries only with `blas`.
- On `windows-x64`, the hook rejects a bundle whose `cuda` module lacks the
  cudart and cuBLAS DLLs, or whose `blas` module lacks OpenBLAS.

Linux modules need system libraries; see
[Linux prerequisites](./linux-prerequisites).

On Windows every module needs the latest Microsoft Visual C++ v14
Redistributable (x64 or arm64), at least as new as the build tools of the
bundled DLLs. The bundles ship only the OpenMP runtime
(`vcomp140.dll` on x64, `libomp140.aarch64.dll` on arm64), not
`msvcp140.dll` or `vcruntime140.dll`. `vulkan` also needs a GPU driver that
provides the Vulkan loader, `vulkan-1.dll`, and `cuda` an NVIDIA driver,
which provides `nvcuda.dll`. When one of those is missing, the module's
startup diagnostic, which a failed model load reports, names it.

### When a requested backend is not bundled

`ModelParams.preferredBackend` selects only a module the app has. With the
default `cpu` and `vulkan`, `GpuBackend.cuda` has no module to load, so on
Linux and Windows the model loads on CPU with 0 GPU layers rather than on
another GPU backend. llamadart logs a `LlamaLogLevel.warn` record through the
Dart logger that names the backend and this user-define, and
`getBackendName()` reports `CPU`. To use CUDA, add it for the platform:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_backends:
        platforms:
          linux-x64: [cpu, vulkan, cuda]
          windows-x64: [cpu, vulkan, cuda]
```

- On Windows, `dart run` and `dart test` load only the modules the app
  bundles, as does a Linux app built with `dart build cli` and run from
  another directory.
- On Linux, a process whose working directory is the package root, as with
  `dart run` and `dart test`, copies each backend module missing from
  `.dart_tool/lib` out of the hook's download cache,
  `.dart_tool/llamadart/native_bundles/<tag>/linux-<arch>/extracted`, when the
  backend starts. The cache holds every module in the release, `cuda` and
  `hip` included on x64, so there CUDA loads without the user-define when its
  [system libraries](./linux-prerequisites) are installed.

### Android arm64 CPU variants

The `android-arm64` map form also takes `cpu_profile` and `cpu_variants`:

- `cpu_profile: full` (default) bundles all seven CPU variant modules.
- `cpu_profile: compact` bundles only the baseline `android_armv8.0_1`.
- `cpu_variants: [...]` lists variants explicitly and overrides `cpu_profile`.
  Unknown entries are dropped with a warning; if none remain, `cpu_profile`
  applies.

| Variant | Optional CPU features |
| --- | --- |
| `android_armv8.0_1` | Baseline |
| `android_armv8.2_1` | `DOTPROD` |
| `android_armv8.2_2` | `DOTPROD`, `FP16_VECTOR_ARITHMETIC` |
| `android_armv8.6_1` | `DOTPROD`, `FP16_VECTOR_ARITHMETIC`, `MATMUL_INT8` |
| `android_armv9.0_1` | `DOTPROD`, `FP16_VECTOR_ARITHMETIC`, `MATMUL_INT8`, `SVE2` |
| `android_armv9.2_1` | `DOTPROD`, `FP16_VECTOR_ARITHMETIC`, `MATMUL_INT8`, `SVE`, `SME` |
| `android_armv9.2_2` | `DOTPROD`, `FP16_VECTOR_ARITHMETIC`, `MATMUL_INT8`, `SVE`, `SVE2`, `SME` |

Variant names are normalized, so `baseline`, `armv8_6_1`, `v9_0_1`,
`android-armv9.2_2` and `libggml-cpu-android_armv8.2_2.so` are all accepted.

## Override the llama.cpp release

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_tag: vX.Y.Z
      llamadart_native_repository: leehack/llamadart-native
      # llamadart_native_path: ./native-bundles
```

- `llamadart_native_tag` names a `llamadart-native` release tag, not a
  `llamadart` package version. The hook accepts `vMAJOR.MINOR.PATCH`,
  `vMAJOR.MINOR.PATCH-N`, `bNNNN`, `bNNNN-N` and `bNNNN-llamadart.N`, never
  `latest`. List releases with
  `gh release list --repo leehack/llamadart-native --limit 20`.
- The release must contain `llamadart-native-<bundle>-<tag>.tar.gz` for the
  target and a `SHA256SUMS` that lists it; otherwise the build fails before
  using the archive. The pinned release is verified against digests in
  `lib/src/hook/native_release_pins.dart` instead.
- `llamadart_native_repository` takes an `owner/repo` slug or a
  `https://github.com/owner/repo` URL.
- `llamadart_native_path` wins over downloads. It can point at an archive, an
  extracted bundle directory, or a directory containing `<tag>/<bundle>/`,
  `<bundle>/`, or the expected archive. Relative paths resolve from the
  `pubspec.yaml` that sets them. Local bundles are trusted as given; the hook
  does not check their digests.

Overrides do not regenerate the Dart FFI bindings, so the binary must stay ABI-
and symbol-compatible with the pinned release; the hook logs a warning when an
override is active. A runtime older than `v0.5.0-1` has no exit teardown:
llamadart then creates models and contexts with the upstream llama.cpp
functions and logs a warning at the first model load, and the exits that
teardown covers abort on Apple Metal as they did before
([Exiting with a model loaded](../guides/model-lifecycle#exiting-with-a-model-loaded)).
`v0.5.0-1` has exit teardown but can still abort when a native host calls C
`exit()` during the free of the last object; use `v0.5.0-2` or later.
A runtime older than `v0.6.0-1` has no exception barrier and no Vulkan device
facts: a C++ exception llama.cpp throws ends the process instead of becoming
a typed `LlamaException` (llamadart logs a warning at the first model load),
every Android Vulkan context keeps the 8-token text-prompt decode cap, and no
Vulkan GPU is refused for a driver below Vulkan 1.2. State files are tied to
the llama.cpp release of the runtime that wrote them
([Save and restore prompt state](../guides/model-lifecycle#save-and-restore-prompt-state)).
Two checks fail closed:

- LoRA adapters need both `llama_adapter_get_alora_n_invocation_tokens` and
  `llama_adapter_get_alora_invocation_tokens`. Without a compatible pair,
  `setLoraSource` and loads with `ModelParams.loras` throw
  `LlamaUnsupportedException` rather than activate an adapter whose type it
  cannot check.
- DSpark speculative decoding (`SpeculativeDecodingConfig.draftDspark`) needs
  at least the `b10356-llamadart.1` wrapper fix; the pinned release has it.

LiteRT-LM has no override keys; the hook always downloads the pinned
`litert-lm-native` release and verifies its checksum. Tag grammar for
maintainers: [Native and web sync](../maintainers/native-and-web-sync).

## Flutter Apple apps

Flutter iOS and macOS apps link runtimes through Swift Package Manager when a
companion package is a dependency:

- `llamadart_llama_cpp_flutter` links the llama.cpp XCFrameworks.
- `llamadart_litert_lm_flutter` links the LiteRT-LM iOS and macOS
  XCFrameworks, including the macOS WebGPU accelerator, sampler and Dawn. The
  Metal accelerator and sampler stay iOS-only: their `v0.18.0` macOS slices
  carry an invalid code signature, and the macOS GPU path uses WebGPU.
- `llamadart_stable_diffusion_flutter` links the stable-diffusion.cpp
  XCFramework for [image generation](../guides/image-generation).

When the llama.cpp or LiteRT-LM companion is present, the installed companions
choose the Apple `llama_cpp` and `litert_lm` families and the rest of
`llamadart_native_runtimes` is ignored with a warning. `stable_diffusion` is
decided on its own: its companion selects it, and otherwise the hook bundles it
when `llamadart_native_runtimes` names it, not when `all` only implies it;
a pub workspace member is the exception described under
[Opt-in stable_diffusion runtime](#opt-in-stable_diffusion-runtime-experimental).
Adding only the stable_diffusion
companion leaves llama.cpp and LiteRT-LM on the hook. The build checks the
resolved llama.cpp and stable_diffusion companions' pins against the core
package and rejects local `Artifacts` overrides. A llama.cpp companion pinning
an earlier build of the same llama.cpp release that the core lists as
ABI-identical, such as `0.0.22` (`v0.6.0-2`), builds with a warning to upgrade
the companion. The tag,
repository, path and backend keys do not change SwiftPM binaries; their pins
live in each companion's `Package.swift`, so use a path or git override or a
fork of the companion. On macOS the hook hands LiteRT-LM to the companion
only when the resolved companion's `Package.swift` is the maintained manifest
pinning the core's LiteRT-LM release. Any other companion, including `0.0.14`
and earlier, keeps macOS LiteRT-LM in the hook cache with a build warning; a
sandboxed, copied or distributed app cannot read that cache and needs the
[LiteRT-LM build phase](../getting-started/installation#flutter-macos-litert-lm-build-phase).
A companion with the maintained manifest pinning an earlier build of the same
LiteRT-LM release, such as `0.0.15` (`v0.18.0`), still embeds the complete
macOS runtime, which the app loads from its bundle, so the build only warns to
upgrade the companion to `0.0.16` or later (`v0.18.0-1`). A maintained manifest pinning
any other LiteRT-LM release or a later build of the same release, such as
`v0.18.0-2`, warns to upgrade the core and companion together.
Without a companion, and for non-Flutter or non-Apple builds, the hook
path above applies.

Standalone Dart on macOS keeps LiteRT-LM libraries in the hook cache. A custom
launcher can set `LLAMADART_LITERT_LM_LIB_DIR` to the extracted LiteRT-LM
directory.

### Apple privacy manifest

The llama.cpp and stable-diffusion.cpp runtimes call `stat` and `fstat`, which
Apple lists as File Timestamp
[required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
A privacy manifest for that use reaches an app inside the XCFramework a
companion package links. The hook path cannot carry one: it bundles bare
dylibs, which Flutter wraps in frameworks it generates. An app bound for the
App Store should use the companion for each runtime it ships.

Runtime releases built before the manifest was added do not contain it:

| Runtime | XCFramework with a manifest |
| --- | --- |
| llama.cpp | `llamadart-native` `v0.5.0-1` and later, which `llamadart_llama_cpp_flutter` releases after `0.0.20` link; `0.0.20` and earlier link `v0.5.0` or older, without one |
| stable-diffusion.cpp | `stable-diffusion-native` `v0.2.0-1` and later, which `llamadart_stable_diffusion_flutter` releases after `0.0.1` link; `0.0.1` links `v0.2.0`, without one |
| LiteRT-LM | `litert-lm-native` `v0.17.0-8` and later, which `llamadart_litert_lm_flutter` releases after `0.0.12` link; `0.0.12` and earlier link `v0.17.0-6` or older, without one |

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
accelerator and sampler). From `litert-lm-native` `v0.17.0-8`, each framework
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

## How the hook resolves a build

```mermaid
sequenceDiagram
    autonumber
    participant Build as flutter build / dart run
    participant Hook as hook/build.dart
    participant Cache as Local bundle cache
    participant Release as GitHub release asset
    participant Assets as code_assets

    Build->>Hook: invoke native-assets hook
    Hook->>Hook: resolve bundle key and runtime families
    Hook->>Cache: check cached bundle
    alt cache miss or stale
        Hook->>Release: download bundle archive
        Hook->>Hook: verify SHA-256, extract and validate libraries
    end
    Hook->>Hook: select llama.cpp modules
    Hook->>Assets: report code assets
```

Runtime sources: llama.cpp bundles come from
[`leehack/llamadart-native`](https://github.com/leehack/llamadart-native) and
LiteRT-LM bundles from
[`leehack/litert-lm-native`](https://github.com/leehack/litert-lm-native).
The hook checks every downloaded or cached llama.cpp, LiteRT-LM and
stable-diffusion.cpp archive against its SHA-256 before extracting it, and
downloads it again when a cached copy does not match; a fresh download that
does not match fails the build with `NativeArchiveDigestException`. An
already-extracted bundle in the cache is reused without hashing it again.
The hook also checks each LiteRT-LM archive for its required libraries and
downloads it again when a cached copy is incomplete. Which
repository owns which change: [Runtime ownership](../maintainers/runtime-ownership).
