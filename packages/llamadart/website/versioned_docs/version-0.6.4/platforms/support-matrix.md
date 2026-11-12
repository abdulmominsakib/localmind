---
title: Platform & Backend Matrix
---

This page combines platform support and backend-module configuration for
`llamadart`.

The native-assets hook currently pins `llamadart-native` tag `b8157`
(`hook/build.dart`). Module availability below is for that pinned tag.

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
| Web (browser) | N/A (JS bridge path) | N/A | Bridge router: `webgpu`, `cpu` fallback | Experimental |

## Current module availability by bundle (`b8157`)

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

Use `hooks.user_defines.llamadart.llamadart_native_backends`:

```yaml
hooks:
  user_defines:
    llamadart:
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
- `cpu` is auto-added as fallback when present in the bundle.
- Android arm64 defaults to `cpu_profile: full`.
- `cpu_variants` (if provided) takes precedence over `cpu_profile` for Android
  arm64.
- If requested modules are unavailable for a bundle, the hook warns and falls
  back to defaults.
- If defaults are also unavailable, all available modules in that bundle are
  used as fallback.
- Apple targets (`ios-*`, `macos-*`) support `cpu` + `metal`, but ignore
  per-backend module config in this hook path because runtime libraries are
  consolidated.
- `windows-x64` performs extra runtime dependency validation:
  - `cuda` requires `cudart` and `cublas` DLLs.
  - `blas` requires OpenBLAS DLL.
- If you change `llamadart_native_backends`, run `flutter clean` once to clear
  stale native-asset outputs.

## Related docs

- [Native Build Hooks](./native-build-hooks)
- [Linux Prerequisites](./linux-prerequisites)
- [WebGPU Bridge](./webgpu-bridge)
