---
title: Platform & Backend Matrix
---

This page combines platform support and backend-module configuration for
`llamadart`.

The native-assets hook currently pins `llamadart-native` tag `b8099`
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

## Current module availability by bundle (`b8099`)

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
          android-arm64: [vulkan]
          linux-x64: [vulkan, cuda]
          windows-x64:
            backends: [vulkan, cuda, blas]
```

## Selection and fallback behavior

- Configurable targets start from defaults (`cpu`, `vulkan`) if available.
- `cpu` is auto-added as fallback when present in the bundle.
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
