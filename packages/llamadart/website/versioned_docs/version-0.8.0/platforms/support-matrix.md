---
title: Platform & Backend Matrix
description: Check which native and web runtimes are supported by llamadart and how backend selection works per platform.
---

This page combines platform support, runtime-family selection, and
backend-module configuration for
`llamadart`.

The native-assets hook currently pins `llamadart-native` tag `b9587` and
`litert-lm-native` release `v0.13.1-native.1` (`hook/build.dart`). Apps can
override the llama.cpp native GitHub source with
`hooks.user_defines.llamadart.llamadart_native_tag` and
`hooks.user_defines.llamadart.llamadart_native_repository`, or use a local
bundle source with `hooks.user_defines.llamadart.llamadart_native_path`. Module
availability below is for the pinned/default artifacts.

Available override tags are published on the
[`leehack/llamadart-native` releases page](https://github.com/leehack/llamadart-native/releases)
or via `gh release list --repo leehack/llamadart-native --limit 20`.
The selected release must include a bundle asset named
`llamadart-native-<bundle>-<tag>.tar.gz` for the target being built.
Native source overrides do not regenerate Dart FFI bindings or symbol lookups,
so the selected binary must remain ABI- and symbol-compatible with the default
runtime revision.

## Platform/architecture coverage

| Platform target | Hook bundle key | `llamadart_native_backends` configurable? | Backend behavior | Status |
| --- | --- | --- | --- | --- |
| Android arm64 | `android-arm64` | Yes | Defaults: `cpu`, `vulkan` (when present) | Supported |
| Android x64 | `android-x64` | Yes | Defaults: `cpu`, `vulkan` (when present) | Supported |
| Linux arm64 | `linux-arm64` | Yes | Defaults: `cpu`, `vulkan` (when present) | Supported |
| Linux x64 | `linux-x64` | Yes | Defaults: `cpu`, `vulkan` (when present) | Supported |
| Windows arm64 | `windows-arm64` | Yes | Defaults: `cpu`, `vulkan` (when present) | Supported |
| Windows x64 | `windows-x64` | Yes | Defaults: `cpu`, `vulkan` (when present) | Supported |
| iOS arm64 (device) | `ios-arm64` | No (fixed in hook) | Consolidated runtime: `cpu`, `metal` | Supported |
| iOS arm64 (simulator) | `ios-arm64-sim` | No (fixed in hook) | Consolidated runtime: `cpu`, `metal` | Supported |
| iOS x86_64 (simulator) | `ios-x86_64-sim` | No (fixed in hook) | Consolidated runtime: `cpu`, `metal` | Supported |
| macOS arm64 | `macos-arm64` | No (fixed in hook) | Consolidated runtime: `cpu`, `metal` | Supported |
| macOS x86_64 | `macos-x86_64` | No (fixed in hook) | Consolidated runtime: `cpu`, `metal` | Supported |
| Web (browser) | N/A (JS bridge path) | N/A | Router: llama.cpp WebGPU/CPU for `.gguf`; LiteRT-LM JS for `.litertlm` URLs | Experimental; see [WebGPU Bridge](./webgpu-bridge) and LiteRT-LM web notes below |

All iOS targets above require the consuming Flutter/Xcode project to use a
minimum deployment target of `16.4` or newer. Flutter macOS targets require
macOS `14.0` or newer. If an iOS app still uses CocoaPods, set the Podfile
platform to `16.4` or newer too.

## Model format routing

`LlamaBackend()` routes by model file format:

- `.gguf` and unknown extensions use llama.cpp. Native targets load the
  bundled native runtime; web targets use the WebGPU bridge router.
- Native `.litertlm` paths use LiteRT-LM and the companion runtime bundles
  from `litert-lm-native`.
- Web `.litertlm` URLs use the browser LiteRT-LM backend, which wraps the
  official `@litert-lm/core` JavaScript API. Apps can preload
  `window.LiteRtLmEngine = module.Engine` or set
  `window.__llamadartLiteRtLmModuleUrl` to an `@litert-lm/core` ESM URL before
  loading the model.

Use the same high-level `LlamaEngine`, `ModelSource`, and download/cache APIs
for both formats. Native/file-backed targets cache remote `.litertlm` sources
before local load and can use `ChatSession` for multi-turn chat. LiteRT-LM web
currently forwards only single-turn text prompts through `@litert-lm/core`, so
it does not preserve `ChatSession` history, system prompts, or tool
declarations with native LiteRT-LM semantics yet.

Select LiteRT-LM CPU/GPU/NPU with `ModelParams.liteRtLmBackend`.
`LiteRtLmBackendPreference.auto` currently maps to GPU on Android, macOS, and
web, and CPU on other LiteRT-LM targets. NPU selection is Android native only;
web rejects it explicitly.

## Configuring native runtime families

Use `llamadart_native_runtimes` to choose which native runtime families are
bundled:

- `llama_cpp`: GGUF model support through llama.cpp.
- `litert_lm`: `.litertlm` model support through LiteRT-LM.

Unset or empty config means all runtime families available for the target. Apps
that only ship one model format can trim package size:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp]
```

Per-platform overrides can use OS keys or the exact bundle keys from the tables
on this page. Exact target keys override OS keys:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes:
        runtimes: [llama_cpp, litert_lm]
        platforms:
          ios: [llama_cpp]
          macos: [llama_cpp, litert_lm]
          android-arm64: [litert_lm]
          linux-x64: [llama_cpp]
```

Accepted aliases include `llama.cpp`, `gguf`, `litert`, and `litert-lm`.
Use `all` or `both` to include every available runtime family for a target.
Explicitly selecting `litert_lm` for a target without a pinned LiteRT-LM
runtime fails during the build hook instead of producing an app that cannot
load `.litertlm` models.

## LiteRT-LM runtime coverage (`v0.13.1-native.1`)

| Platform target | LiteRT-LM bundle key | Selectable backends | Status |
| --- | --- | --- | --- |
| Android arm64 | `android-arm64` | `cpu`, `gpu`, `npu` | Supported |
| Android x64 | `android-x64` | `cpu`, `gpu`, `npu` | Supported for emulator/test targets |
| iOS arm64 (device) | `ios-arm64` | `cpu` | Supported |
| iOS arm64 (simulator) | `ios-arm64-sim` | `cpu` | Supported |
| iOS x86_64 (simulator) | Not published | N/A | Unsupported; exclude `litert_lm` for this target |
| macOS arm64 | `macos-arm64` | `cpu`, `gpu` | Supported |
| macOS x86_64 | `macos-x64` | `cpu`, `gpu` | Supported |
| Linux arm64 | `linux-arm64` | `cpu` | Supported |
| Linux x64 | `linux-x64` | `cpu` | Supported |
| Windows x64 | `windows-x64` | `cpu` | Supported |
| Web (browser) | N/A (`@litert-lm/core`) | `cpu`, `gpu` | Experimental; web-compatible `.litertlm` URLs only |

LiteRT-LM does not currently expose embeddings, state persistence, LoRA, or
multimodal projector APIs through llamadart. On native LiteRT-LM targets,
high-level thinking and tool-call parsing still run through `LlamaEngine` for
compatible templates, but llama.cpp-style GBNF grammar constraints are not
supported for `.litertlm` generation. Native LiteRT-LM can opt into runtime
speculative decoding through `GenerationParams.speculativeDecoding`; Web
LiteRT-LM rejects that option until the browser runtime exposes an equivalent
control. Web LiteRT-LM also does not expose tokenizer operations and is limited
to single-turn text prompts, so it should
not be treated as a multi-turn `ChatSession` or tool-calling backend yet.
`llamadart` rejects unsupported operations explicitly for `.litertlm` loads
instead of silently ignoring llama.cpp-only settings.

Native LiteRT-LM exposes four advanced runtime controls through `ModelParams`.
All are opt-in; `null` keeps the pinned `v0.13.1-native.1` runtime default.

| Native C API | Dart field | Support decision |
| --- | --- | --- |
| `litert_lm_engine_settings_set_activation_data_type` | `liteRtLmActivationDataType` | Exposed for native `.litertlm`; typed as `float32`, `float16`, `int16`, or `int8`. |
| `litert_lm_engine_settings_set_prefill_chunk_size` | `liteRtLmPrefillChunkSize` | Exposed for CPU dynamic models; positive values only. |
| `litert_lm_engine_settings_set_parallel_file_section_loading` | `liteRtLmParallelFileSectionLoading` | Exposed as a nullable boolean; native default remains parallel loading. |
| `litert_lm_engine_settings_set_litert_dispatch_lib_dir` | `liteRtLmDispatchLibDir` | Exposed for Android NPU deployments that need a packaged LiteRT dispatch directory. |

LiteRT-LM web rejects these native-only fields because `@litert-lm/core` does
not expose equivalent runtime controls.

## Runtime capability notes

- **State persistence** (`LlamaEngine.stateSaveFile(...)` /
  `stateLoadFile(...)`) is available on native backends and on WebGPU bridge
  assets `v0.1.15+` that expose `stateSaveFile` / `stateLoadFile` bridge APIs.
  On web, state paths refer to the bridge WASMFS virtual filesystem and are not
  durable across page reloads. Durable browser storage currently requires
  app-level export/import outside the Dart `stateSaveFile` / `stateLoadFile`
  helpers. LiteRT-LM currently reports state persistence as unsupported.
- **WebGPU readiness** is browser/device/runtime dependent. Check secure
  context, `navigator.gpu`, adapter/features, `window.crossOriginIsolated`,
  loaded bridge asset source/version, and model memory pressure before treating
  a web load failure as a package bug. The [WebGPU Bridge](./webgpu-bridge)
  page has the browser-console probe and Flutter Web smoke-test path.

## Current llama.cpp module availability by bundle (`b9587`)

| Bundle key | Available backend modules in bundle |
| --- | --- |
| `android-arm64` | `cpu`, `vulkan`, `opencl` |
| `android-x64` | `cpu`, `vulkan`, `opencl` |
| `linux-arm64` | `cpu`, `vulkan`, `blas` |
| `linux-x64` | `cpu`, `vulkan`, `blas`, `cuda`, `hip` |
| `windows-arm64` | `cpu`, `vulkan`, `blas` |
| `windows-x64` | `cpu`, `vulkan`, `blas`, `cuda` |
| `ios-*`, `macos-*` | Consolidated Apple runtime (`cpu` + `metal` path; no split `ggml-*` module selection in hook) |

## Selector names and aliases

`llamadart_native_backends` values are matched against modules discovered in
the selected bundle. Current configurable-bundle module names are:

- `cpu`
- `vulkan`
- `opencl`
- `cuda`
- `blas`
- `hip`

Aliases:

- `vk` -> `vulkan`
- `ocl` -> `opencl`
- `open-cl` -> `opencl`

`GpuBackend.metal` remains valid as a runtime backend preference on Apple
targets, but Apple targets are non-configurable in
`llamadart_native_backends`.

## Configuring native backend modules

Use `hooks.user_defines.llamadart.llamadart_native_tag` and
`hooks.user_defines.llamadart.llamadart_native_repository` to test another
GitHub release source,
`hooks.user_defines.llamadart.llamadart_native_path` to use a local source, and
`hooks.user_defines.llamadart.llamadart_native_backends` to select split
llama.cpp backend modules:

```yaml
hooks:
  user_defines:
    llamadart:
      # Optional. Defaults to llamadart's tested native runtime pin.
      llamadart_native_tag: b9587

      # Optional. GitHub repository slug or github.com URL.
      llamadart_native_repository: leehack/llamadart-native

      # Optional. Takes precedence over GitHub downloads when set.
      # Relative paths are resolved from the pubspec defining this config.
      # llamadart_native_path: ./native-bundles

      llamadart_native_backends:
        platforms:
          android-arm64:
            backends: [vulkan]
            cpu_profile: full # default; use compact for baseline-only
          linux-x64: [vulkan, cuda]
          windows-x64:
            backends: [vulkan, cuda, blas]
```

Android arm64 CPU policy keys (`platforms.android-arm64`):

- `cpu_profile: full` (default): include all Android ARM CPU variant modules.
- `cpu_profile: compact`: include baseline CPU variant module only.
- `cpu_variants: [...]` (advanced): explicit CPU variant list, overrides
  `cpu_profile`.

Supported canonical `cpu_variants` values:

- `android_armv8.0_1` (baseline)
- `android_armv8.2_1`
- `android_armv8.2_2`
- `android_armv8.6_1`
- `android_armv9.0_1`
- `android_armv9.2_1`
- `android_armv9.2_2`

Variant feature differences:

| Variant | Optional feature set used by that module |
| --- | --- |
| `android_armv8.0_1` | baseline |
| `android_armv8.2_1` | `DOTPROD` |
| `android_armv8.2_2` | `DOTPROD` + `FP16_VECTOR_ARITHMETIC` |
| `android_armv8.6_1` | `DOTPROD` + `FP16_VECTOR_ARITHMETIC` + `MATMUL_INT8` |
| `android_armv9.0_1` | `DOTPROD` + `FP16_VECTOR_ARITHMETIC` + `MATMUL_INT8` + `SVE2` |
| `android_armv9.2_1` | `DOTPROD` + `FP16_VECTOR_ARITHMETIC` + `MATMUL_INT8` + `SVE` + `SME` |
| `android_armv9.2_2` | `DOTPROD` + `FP16_VECTOR_ARITHMETIC` + `MATMUL_INT8` + `SVE` + `SVE2` + `SME` |

Accepted `cpu_variants` input forms are normalized, for example:

- `baseline`
- `armv8_6_1`
- `v9_0_1`
- `android-armv9.2_2`
- `libggml-cpu-android_armv8.2_2.so`

If `cpu_variants` contains unknown entries, they are ignored with warnings. If
no valid entries remain, selection falls back to `cpu_profile` (or default
`full`).

## Selection and fallback behavior

- Configurable targets start from defaults (`cpu`, `vulkan`) if available.
- `llamadart_native_runtimes` controls whole native runtime families:
  `llama_cpp`, `litert_lm`, or both. Unset or empty means all runtime families
  available for the target.
- `llamadart_native_backends` controls only llama.cpp module files inside
  `llama_cpp`; it does not affect LiteRT-LM assets.
- `cpu` is auto-added as fallback when present in the bundle.
- Android arm64 defaults to `cpu_profile: full`.
- `cpu_variants` (if provided) takes precedence over `cpu_profile` for Android
  arm64.
- If requested modules are unavailable for a bundle, the hook warns and falls
  back to defaults.
- If defaults are also unavailable, all available modules in that bundle are
  used as fallback.
- Backend-owned runtime dependencies follow the selected backend module. CUDA
  runtime DLLs (`cudart64_*`, `cublas64_*`, `cublaslt64_*`) are bundled only
  when `cuda` is selected, and OpenBLAS runtime libraries are bundled only when
  `blas` is selected. Unknown runtime libraries are kept for compatibility with
  future native bundle layouts.
- Apple targets (`ios-*`, `macos-*`) support `cpu` + `metal`, but ignore
  per-backend module config in this hook path because runtime libraries are
  consolidated.
- Flutter Apple apps use Swift Package Manager only through runtime companion
  packages: `llamadart_llama_cpp_flutter` for GGUF/llama.cpp and
  `llamadart_litert_lm_flutter` for `.litertlm`/LiteRT-LM.
- For Flutter iOS/macOS apps, installed companion packages choose the Apple SPM
  runtime families and win over `llamadart_native_runtimes`. If neither
  companion package is installed, the core native-assets fallback is used.
- For non-Flutter projects and non-Apple targets, `llamadart_native_runtimes`
  remains the selector even if a Flutter companion package is accidentally
  present in dependencies.
- `llamadart_native_tag`, `llamadart_native_repository`, and
  `llamadart_native_path` customize hook-managed native assets. Apple SPM
  binary target URL/checksum pins are owned by the companion packages under
  `packages/` and can be customized with path/git overrides or forks of those
  packages.
- Standalone Dart macOS runs keep the native-assets path for compatibility.
- Custom standalone Dart macOS launchers can point
  `LLAMADART_LITERT_LM_LIB_DIR` at the extracted LiteRT-LM cache directory when
  the default cache search is not suitable.
- `windows-x64` performs extra runtime dependency validation:
  - `cuda` requires `cudart` and `cublas` DLLs.
  - `blas` requires OpenBLAS DLL.
- If `llamadart_native_tag` points at a release without a matching bundle asset,
  the native-assets hook fails while downloading that asset.
- Available override values are `leehack/llamadart-native` release tags, not
  `llamadart` package versions.
- `llamadart_native_repository` accepts a GitHub `owner/repo` slug or
  `https://github.com/owner/repo` URL.
- `llamadart_native_path` takes precedence over GitHub downloads and can point
  directly at an archive, at an extracted bundle directory, or at a directory
  containing `<tag>/<bundle>/`, `<bundle>/`, or the expected archive file.
- Native source overrides do not regenerate Dart FFI bindings or symbol
  lookups, so they are only safe with compatible native binaries.
- If you change `llamadart_native_tag`, `llamadart_native_repository`,
  `llamadart_native_path`, `llamadart_native_runtimes`, or
  `llamadart_native_backends`, run `flutter clean` once to clear stale
  native-asset outputs.

## Vulkan cooperative matrix driver crashes

Some Vulkan drivers advertise cooperative matrix support but crash inside the
Vulkan property query calls used by upstream `ggml-vulkan`. This is a driver
failure, not a llamadart loader failure. Use upstream ggml-vulkan's opt-out
environment variables before starting the Dart/Flutter process:

```bash
GGML_VK_DISABLE_COOPMAT=1
GGML_VK_DISABLE_COOPMAT2=1
```

On Windows PowerShell:

```powershell
$env:GGML_VK_DISABLE_COOPMAT = "1"
$env:GGML_VK_DISABLE_COOPMAT2 = "1"
flutter run -d windows
```

These variables disable the cooperative matrix optimized Vulkan paths for that
process. They can reduce Vulkan performance, so use them only when the Vulkan
driver crashes or reports device loss in the cooperative matrix path.

## Related docs

- [Native Build Hooks](./native-build-hooks)
- [Linux Prerequisites](./linux-prerequisites)
- [WebGPU Bridge](./webgpu-bridge)
