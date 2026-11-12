---
title: WebGPU Bridge
---

Web mode uses an external JavaScript bridge runtime consumed by `llamadart`.

## Ownership

- Bridge source and build: `leehack/llama-web-bridge`
- Published bridge assets: `leehack/llama-web-bridge-assets`
- This repository consumes those artifacts

## Runtime load order

`example/chat_app/web/index.html` uses local-first loading on localhost for
development validation, and CDN-first loading for normal hosted deployments:

1. On localhost: local asset first, then CDN fallback
2. On hosted deployments: CDN asset first, then local fallback

Fetch pinned local assets with:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=v0.1.14 ./scripts/fetch_webgpu_bridge_assets.sh
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
- CPU fallback is available through bridge runtime routing.
- Safari compatibility guard and fallback behavior are integrated in this repo.
- Legacy bridge assets may be forced to CPU in Safari when GPU layers are
  requested.

Large single-file web model loading requires a cross-origin isolated page:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp` (or `credentialless`)
- Runtime check: `window.crossOriginIsolated === true`

## Runtime overrides

You can override bridge asset source/version before loader startup:

```html
<script>
  window.__llamadartBridgeAssetsRepo = 'leehack/llama-web-bridge-assets';
  window.__llamadartBridgeAssetsTag = 'v0.1.14';
  // Optional knobs:
  // window.__llamadartBridgeEnableMem64 = false;
  // window.__llamadartBridgeAllowAutoRemoteFetchBackend = false;
  // window.__llamadartBridgeRemoteFetchChunkBytes = 4 * 1024 * 1024;
  // window.__llamadartBridgeThreadPoolSize = 2;
  // window.__llamadartBridgeBootstrapVerbose = true;
</script>
```

## Contract reference

Bridge contract details (global shape, required methods, compatibility targets):

- [`doc/webgpu_bridge.md`](https://github.com/leehack/llamadart/blob/main/doc/webgpu_bridge.md)
