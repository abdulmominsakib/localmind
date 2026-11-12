---
title: WebGPU Bridge
description: Check browser readiness, bridge asset loading, fallback behavior, and Flutter Web smoke-test paths for llamadart's experimental WebGPU runtime.
---

Web mode uses an external JavaScript bridge runtime consumed by `llamadart`.
The bridge can run llama.cpp through WebGPU when the browser/device supports it,
and can also route through a bridge CPU path when GPU offload is disabled or
fallback is required.

:::warning Experimental web runtime
The WebGPU bridge is still experimental. Treat WebGPU availability as a runtime
capability, not a compile-time promise: a browser can load the app but still lack
an adapter, required device features, memory headroom, or compatible bridge
assets for a specific model/configuration.
:::

## Ownership

- Bridge source and build: `leehack/llama-web-bridge`
- Published bridge assets: `leehack/llama-web-bridge-assets`
- This repository consumes those artifacts and wires them into Dart/Flutter
  examples

## Quick readiness checklist

A page is ready for WebGPU model loading only when all of these checks pass:

1. **Secure browser context**: serve from `https://`, `http://localhost`, or
   `http://127.0.0.1`. WebGPU is not available to arbitrary insecure origins.
2. **Bridge runtime loaded**: `window.LlamaWebGpuBridge` exists and
   `window.__llamadartBridgeLoadError` is empty.
3. **WebGPU is exposed**: `navigator.gpu` exists and `requestAdapter()` returns
   an adapter. If this fails, use CPU fallback or another browser/device.
4. **Large-model threading is available**: for large single-file GGUF loads,
   `window.crossOriginIsolated === true` so the bridge can create worker
   threads and use the fetch-backed loader.
5. **Model/config fits browser limits**: start with a small quantized GGUF and a
   bounded context size before increasing model size, context, or GPU layers.
6. **Runtime status matches expectations**: after load, the chat app runtime
   panel or bridge metadata should show whether the active path is GPU, CPU,
   wasm32/wasm64, CDN/local assets, and cache state.

You can paste this browser-console probe into a running app:

```js
const adapter = await navigator.gpu?.requestAdapter();
console.table({
  secureContext: window.isSecureContext,
  crossOriginIsolated: window.crossOriginIsolated,
  hasNavigatorGpu: !!navigator.gpu,
  hasAdapter: !!adapter,
  adapterFeatures: adapter ? [...adapter.features].join(', ') : '',
  bridgeLoaded: typeof window.LlamaWebGpuBridge === 'function',
  bridgeLoadError: window.__llamadartBridgeLoadError || '',
  bridgeAssetSource: window.__llamadartBridgeAssetSource || '',
  bridgeModuleUrl: window.__llamadartBridgeModuleUrl || '',
  bridgeLocalVersion: window.__llamadartBridgeLocalVersion || '',
  bridgeCoreModuleUrl: window.__llamadartBridgeCoreModuleUrl || '',
  bridgeWorkerUrl: window.__llamadartBridgeWorkerUrl || '',
  prefersMem64: window.__llamadartBridgePreferMemory64,
  threadPoolSize: window.__llamadartBridgeThreadPoolSize,
  workerFallbackReason: window.__llamadartBridgeWorkerFallbackReason || '',
});
```

## Browser support

Current bundled bridge runtime targets:

| Browser family | Target | Notes |
| --- | --- | --- |
| Chrome / Chromium / Edge | 128+ | Best-supported path. Use a secure context and current GPU drivers. |
| Firefox | 129+ | WebGPU availability can depend on user/browser configuration. |
| Safari | 17.4+ | This repo patches the bridge gate to allow Safari 17.4+, but GPU generation can be unstable with legacy bridge assets. |

Browser support still depends on device GPU, driver, OS, enterprise policy,
flags, memory pressure, and model shape. A supported browser version does not
guarantee that a particular GGUF will load with WebGPU offload.

### Adapter/features/limits

Useful checks when a model fails only on WebGPU:

- `navigator.gpu` missing: the browser/runtime does not expose WebGPU. Use CPU
  fallback, enable the browser feature if appropriate, or switch browsers.
- `requestAdapter()` returns `null`: the browser could not find a usable GPU
  adapter for the current device/context.
- `adapter.features` does not include an expected feature such as `shader-f16`:
  try a different browser/device, reduce GPU offload, or run CPU. Some headless
  Chromium setups on macOS need Metal ANGLE to expose the expected feature set.
- Very low limits or memory errors: reduce `contextSize`, use a smaller
  quantization/model, close other tabs, or use native runtime.

## Cross-origin isolation and headers

Large single-file web model loading requires a cross-origin isolated page so the
bridge can create worker threads and avoid excessive main-thread `ArrayBuffer`
pressure.

Required response headers on the app origin:

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

`Cross-Origin-Embedder-Policy: credentialless` can also work for deployments
that need credentialless subresource handling.

Runtime check:

```js
window.crossOriginIsolated === true
```

Without cross-origin isolation, small streamed loads may still work, but the
fetch-backed loader can fail with errors such as `thread constructor failed`,
`error 138`, or notes like `threads_capped_no_coi`. The Dart backend normalizes
these into an `UnsupportedError` that asks you to enable COOP/COEP or use a
smaller/sharded model.

### Hugging Face Static Spaces

For `sdk: static`, set custom headers in Space README frontmatter:

```yaml
custom_headers:
  cross-origin-embedder-policy: require-corp
  cross-origin-opener-policy: same-origin
  cross-origin-resource-policy: cross-origin
```

Header keys and values must be lowercase in Spaces config. The chat app deploy
workflow injects these headers automatically for the hosted demo.

## Runtime load order

`example/chat_app/web/index.html` uses local-first loading on localhost for
development validation, and CDN-first loading for normal hosted deployments:

1. On localhost: local asset first, then CDN fallback.
2. On hosted deployments: CDN asset first, then local fallback.

The example currently pins bridge assets to `v0.1.16`, with local vendored assets
identified as `v0.1.16-local-b9165`.

Fetch pinned local assets with:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=v0.1.16 ./scripts/fetch_webgpu_bridge_assets.sh
```

To verify the loaded runtime in a browser console, inspect:

```js
window.__llamadartBridgeAssetSource;   // "cdn", "local", or "mock"
window.__llamadartBridgeModuleUrl;     // actual bridge module URL
window.__llamadartBridgeCoreModuleUrl; // wasm32 JS core module URL
window.__llamadartBridgeCoreModuleUrlMem64; // optional wasm64 JS core module URL
window.__llamadartBridgeWorkerUrl;     // dedicated worker module, if available
```

## Compatibility and safeguards

- Web backend remains experimental.
- `v0.1.12+` bridge assets forward native-compatible `ModelParams` load
  tuning fields, including multi-sequence slots, KV cache type, flash attention,
  RoPE overrides, split mode, and main GPU.
- `v0.1.13+` bridge assets keep control-token output available for parser
  consumers while narrowing multimodal CPU fallback to recovery paths.
- `v0.1.14+` bridge assets cap automatically selected WebAssembly threads to
  the compiled pthread pool size, preventing BERT-style embedding models from
  aborting on hosts with higher hardware concurrency than the bridge pool.
- `v0.1.15+` bridge assets expose state persistence APIs consumed by
  `LlamaEngine.stateSaveFile(...)` / `stateLoadFile(...)`. Web paths are bridge
  WASMFS virtual paths and are not durable across page reloads. Durable browser
  storage currently requires app-level export/import outside the Dart
  `stateSaveFile` / `stateLoadFile` helpers.
- CPU fallback is available through bridge runtime routing.
- Safari compatibility guard and fallback behavior are integrated in this repo.
- Legacy bridge assets may be forced to CPU in Safari when GPU layers are
  requested.

## Fallback behavior

The web backend retries model loading with safer settings before surfacing a
failure:

- If GPU layers were requested, load attempts include CPU fallback
  (`nGpuLayers = 0`) for the same and then smaller context sizes.
- Context size can step down through bounded candidates when the requested
  context is too large for the browser/runtime.
- Qwen3.5-0.8B WebGPU loads are capped to a small GPU-layer count for stable
  browser output unless CPU is explicitly requested.
- Legacy Safari bridge assets force CPU fallback unless adaptive Safari GPU probe
  support is present or `window.__llamadartAllowSafariWebGpu = true` is set.
- wasm64/wasm32 and remote-fetch loader retries can happen automatically when
  bridge metadata indicates an interop or memory-pressure problem. Large
  wasm32 model-staging aborts, including virtual-filesystem write aborts during
  remote model/projector setup, are treated as memory pressure and retried with
  the wasm64 core when available.

Fallback is not silent success for every unsupported condition. If the bridge
cannot load, the browser blocks worker threads, or the model exceeds browser
memory limits after retries, `llamadart` throws an actionable error with runtime
hints such as `core`, `source`, `nThreads`, `nGpuLayers`, `cache`, and bridge
`notes`.

## Model and configuration guidance

For first WebGPU validation, prefer:

- Small GGUFs such as the chat app's Qwen3.5 0.8B preset.
- Quantized files (`Q4_K_M` or similarly small variants) before larger models.
- `contextSize` around `2048` or lower for the first smoke test.
- `gpuLayers = 0` to prove bridge CPU loading, then increase or use `Auto`.
- One tab and a fresh browser process when testing memory-sensitive loads.

When a failure only appears after increasing model size or context, classify it
as a model/configuration pressure issue first, not a bridge-load failure.

## Flutter Web demo and smoke path

Run the production-style chat app locally:

```bash
cd example/chat_app
flutter pub get
flutter run -d chrome
```

For a built web smoke path that matches how hosted assets are served from the
repo root:

```bash
cd example/chat_app
flutter build web --base-href=/example/chat_app/build/web/
cd ../..
python3 tool/testing/serve_static_with_headers.py --directory . --port 7358

.venv-playwright/bin/python tool/testing/playwright_chat_app_real_model_smoke.py \
  http://127.0.0.1:7358/example/chat_app/build/web/ \
  --model-url http://127.0.0.1:7358/example/llamadart_server/models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --expect 4
```

`serve_static_with_headers.py` provides the COOP/COEP headers needed for large
web model loads. When serving `build/web` under a repo-root path, keep the
`--base-href` value aligned with the URL path, otherwise Flutter and bridge
assets are resolved from the wrong location.

On macOS headless Chromium, use the smoke script's default `--browser-angle auto`
or pass `--browser-angle metal`; without Metal ANGLE the adapter can lack
`shader-f16` and llama.cpp may abort in `ggml-webgpu` even when CPU fallback is
used for `gpuLayers = 0` runs.

## Runtime overrides

You can override bridge asset source/version before loader startup:

```html
<script>
  window.__llamadartBridgeAssetsRepo = 'leehack/llama-web-bridge-assets';
  window.__llamadartBridgeAssetsTag = 'v0.1.16';
  // Prefer local runtime even off localhost:
  // window.__llamadartPreferLocalBridgeRuntime = true;
  // Enable verbose bridge bootstrap console logs:
  // window.__llamadartBridgeBootstrapVerbose = true;
  // Optional runtime knobs:
  // window.__llamadartBridgeEnableMem64 = false;
  // window.__llamadartBridgeAllowAutoRemoteFetchBackend = false;
  // window.__llamadartBridgeRemoteFetchChunkBytes = 4 * 1024 * 1024;
  // window.__llamadartBridgeThreadPoolSize = 2;
</script>
```

Use overrides only for diagnosis or controlled deployments. Keep production apps
on a known bridge asset tag and verify the actual loaded module URL before
reporting runtime behavior.

## Troubleshooting map

| Symptom | Likely class | Next check |
| --- | --- | --- |
| `window.LlamaWebGpuBridge` missing | Bridge asset load | Check `window.__llamadartBridgeLoadError`, CDN/local URLs, base href, and CORS. |
| `navigator.gpu` missing or no adapter | Browser/device capability | Use secure context, update browser/drivers, or run CPU/native. |
| `thread constructor failed` / `error 138` | Cross-origin isolation / worker threads | Add COOP/COEP headers and verify `window.crossOriginIsolated`. |
| Memory/OOM/bad_alloc/abort during load | Model/config pressure | Reduce model size, quantization, context, threads, or GPU layers. |
| Safari forces CPU | Safari safeguard | Use adaptive bridge assets or explicitly opt in with `__llamadartAllowSafariWebGpu` for testing. |
| CDN works locally but not hosted | Deployment headers/path | Check base href, static asset paths, COOP/COEP headers, and cache/service worker state. |
| GPU path unstable but CPU works | Adapter/feature/driver/model issue | Check adapter features/limits, especially `shader-f16`, and lower GPU layers. |

## Contract reference

Bridge contract details (global shape, required methods, compatibility targets):

- [`doc/webgpu_bridge.md`](https://github.com/leehack/llamadart/blob/main/doc/webgpu_bridge.md)
