# WebGPU Bridge Contract (Experimental)

This document defines the JavaScript contract expected by
`WebGpuLlamaBackend` in `llamadart`.

## Ownership

- Bridge source/build CI: `leehack/llama-web-bridge`
- Published CDN assets: `leehack/llama-web-bridge-assets`

`llamadart` is a bridge consumer. It does not own bridge build/publish
pipelines.

## Distribution Model (CDN First + Local Fallback)

`example/chat_app/web/index.html` loads bridge runtime in this order:

1. CDN:
   `https://cdn.jsdelivr.net/gh/leehack/llama-web-bridge-assets@<tag>/llama_webgpu_bridge.js`
2. Local fallback: `./webgpu_bridge/llama_webgpu_bridge.js`

Default pinned tag in the example is `v0.1.26`.

For broader browser coverage in this repository, fetched/local assets are patched
to a universal Safari-compatible gate by default (`MIN_SAFARI_VERSION=170400`).
`example/chat_app/web/index.html` also applies the same Safari guard patch at
runtime before bridge initialization, covering CDN fallback paths.
The fetch patch flow also updates legacy bridge stream chunk assembly to clone
read chunks, preventing Safari reader buffer reuse from corrupting downloaded
model bytes.

To vendor pinned assets into local app web files:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=v0.1.26 ./scripts/fetch_webgpu_bridge_assets.sh
```

Optional compatibility env vars:

- `WEBGPU_BRIDGE_PATCH_SAFARI_COMPAT=1|0` (default `1`)
- `WEBGPU_BRIDGE_MIN_SAFARI_VERSION=<packed>` (default `170400`)

## Model Caching

Bridge model fetches use browser Cache Storage by default (`useCache: true` in
web backend load options).

- First load of a model URL fetches from network and stores into cache.
- Subsequent loads of the same URL can be served from cache.
- Model URLs with userinfo, query strings, or fragments are treated as
  credential-sensitive; `llamadart` passes `useCache: false` so the bridge loads
  them directly with no persistent Cache Storage request key.
- Multimodal projector loads are direct bridge fetches and should not rely on
  model Cache Storage for reuse.
- Cache behavior/availability depends on browser storage quota and private mode
  policies.

## Large Model Runtime Requirements

Large single-file GGUF loads on web are only reliable when the page is
cross-origin isolated and the browser can create worker threads.

- Required response headers on the app origin:
  - `Cross-Origin-Opener-Policy: same-origin`
  - `Cross-Origin-Embedder-Policy: require-corp` (or `credentialless`)
- Runtime check: `window.crossOriginIsolated === true`
- WebGPU must be available for WebGPU inference paths.

Without cross-origin isolation, the bridge can fail with thread-constructor
errors in fetch-backed loading flows.

### Hugging Face Static Spaces

For `sdk: static`, set custom headers in Space README frontmatter:

```yaml
custom_headers:
  cross-origin-embedder-policy: require-corp
  cross-origin-opener-policy: same-origin
  cross-origin-resource-policy: cross-origin
```

Header keys and values must be lowercase in Spaces config.

For `example/chat_app` CI deployment (`.github/workflows/chat_app_hf_static_deploy.yml`),
these headers are injected automatically into the generated Space README.

## Browser Compatibility Targets

Current bundled bridge runtime targets:

- Chrome >= 128
- Firefox >= 129
- Safari >= 17.4 (patched universal gate in this repo)

WebGPU availability still depends on browser/device capabilities and local user
settings. CPU mode remains available through the same bridge runtime path.

Current safeguard in `llamadart` web backend:

- Legacy bridge assets (without adaptive Safari probe support) are forced to
  CPU by default on Safari when GPU layers are requested.
- Adaptive bridge assets can keep Safari GPU enabled and run a short generation
  probe; if output looks unstable, they cap GPU layers and/or auto-fallback to
  CPU.
- You can still bypass the legacy safeguard by setting
  `window.__llamadartAllowSafariWebGpu = true` before model load.

## Runtime Override Knobs

You can override CDN source/version before the bridge loader runs:

```html
<script>
  window.__llamadartBridgeAssetsRepo = 'leehack/llama-web-bridge-assets';
  window.__llamadartBridgeAssetsTag = 'v0.1.26';
</script>
```

## Bridge Readiness Signal

`example/chat_app/web/index.html` exposes deterministic readiness globals while
bootstrapping the CDN/local bridge assets:

- `window.__llamadartBridgeReadyPromise` resolves after the bridge runtime is
  loaded and rejects if bootstrap fails or times out.
- `window.__llamadartBridgeReady` is `true` only after successful bootstrap.
- `window.__llamadartBridgeLoadError` contains the failure detail when bootstrap
  fails.

Custom browser integrations that call bridge methods directly, especially
`prefetchModelToCache(...)`, should await the readiness promise before checking
`window.LlamaWebGpuBridge`.

## Expected Global

```js
window.LlamaWebGpuBridge = class LlamaWebGpuBridge {
  constructor(config) {}
};
```

## Required Methods

`WebGpuLlamaBackend` can use these methods if present:

- `loadModelFromUrl(url, { nCtx, nThreads, nThreadsBatch, nBatch, nUbatch, nGpuLayers, nSeqMax, flashAttention, cacheTypeK, cacheTypeV, kvUnified, ropeFrequencyBase, ropeFrequencyScale, splitMode, mainGpu, useCache, forceRemoteFetchBackend, remoteFetchChunkBytes, progressCallback })`
- `prefetchModelToCache(url, { useCache, force, cacheName, progressCallback })`
- `evictModelFromCache(url, { cacheName })`
- `loadMultimodalProjector(url)`
- `unloadMultimodalProjector()`
- `supportsVision()`
- `supportsAudio()`
- `createCompletion(prompt, { nPredict, temp, topK, topP, penalty, seed, grammar, onToken, parts, signal })`
- `tokenize(text, addSpecial)`
- `detokenize(tokens, special)`
- `stateSaveFile(path, tokens)`
- `stateLoadFile(path, tokenCapacity)`
- `embed(text, { normalize })`
- `embedBatch(texts, { normalize })`
- `getModelMetadata()`
- `getContextSize()`
- `cancel()`
- `dispose()`
- `applyChatTemplate(messages, addAssistant, customTemplate)`
- `isGpuActive()`
- `getBackendName()`

## Notes

- Web backend remains GGUF URL-based (`modelLoadFromUrl`).
- If bridge activation fails, model loading fails (no alternate web backend).
- Embeddings on web require bridge assets with embedding APIs (`v0.1.7+`).
- State persistence on web requires bridge assets with state APIs (`v0.1.15+`);
  paths are bridge WASMFS virtual paths and are not durable across page reloads.
  Durable browser storage currently requires app-level export/import outside the
  Dart `stateSaveFile` / `stateLoadFile` helpers.
- During this experimental phase, bridge can be supplied by:
  - preloaded global `window.LlamaWebGpuBridge`, or
  - dynamic import URL via `WebGpuLlamaBackend(bridgeScriptUrl: ...)`.
- `loadMultimodalProjector` and `supportsVision` / `supportsAudio` are active on web.
- Large model URL loads may use a worker-thread fetch-backed path in bridge runtimes to reduce contiguous `ArrayBuffer` pressure.
- Bridge runtimes can optionally provide `llama_webgpu_core_mem64.js/.wasm`; when available and supported by the browser, bridge may prefer wasm64 core and fall back to wasm32 core automatically.

## Performance Tuning Knobs

- `window.__llamadartBridgeEnableMem64` (default effectively off in chat app)
  - Set to `true` to prefer wasm64 core when available.
- `window.__llamadartBridgeAllowAutoRemoteFetchBackend`
  - Default `false`; streamed network staging remains the safe default.
  - Set to `true` only for a controlled origin that serves valid GGUF byte
    ranges. This also permits Dart recovery paths to retry with fetch-backed
    loading after a streamed staging failure.
- `window.__llamadartBridgeForceRemoteFetchBackend`
  - Default `false`.
  - Set to `true` only for controlled diagnostics that must use fetch-backed
    loading from the first attempt. Prefer
    `__llamadartBridgeAllowAutoRemoteFetchBackend` for ordinary opt-in because
    it preserves streamed loading when the fetch-backed path is unnecessary.
- `window.__llamadartBridgeRemoteFetchChunkBytes`
  - Optional positive integer bytes.
  - Defaults to `4 * 1024 * 1024` in `llamadart` web backend; clamped to
    `4KiB..16MiB`.
  - Applies to fetch-backed model loading path.
- `window.__llamadartBridgeThreadPoolSize`
  - Optional positive integer thread count hint.
  - Used by bridge/runtime thread capping to avoid pthread pool exhaustion.
  - Set this to match your bridge build `PTHREAD_POOL_SIZE` when known.
- `window.__llamadartBridgeBootstrapVerbose`
  - Default `false` in chat app bootstrap.
  - Set to `true` to enable verbose bridge bootstrap `console.*` logs.
