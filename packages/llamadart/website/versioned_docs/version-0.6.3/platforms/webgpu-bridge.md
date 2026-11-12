---
title: WebGPU Bridge
---

Web mode uses an external JavaScript bridge runtime consumed by `llamadart`.

## Ownership

- Bridge source and build: `leehack/llama-web-bridge`
- Published bridge assets: `leehack/llama-web-bridge-assets`
- This repository consumes those artifacts

## Runtime load order

`example/chat_app/web/index.html` follows local-first loading:

1. Local asset (generated via fetch script): `./webgpu_bridge/llama_webgpu_bridge.js`
2. CDN fallback (jsDelivr)

Fetch pinned local assets with:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=v0.1.4 ./scripts/fetch_webgpu_bridge_assets.sh
```

## Compatibility and safeguards

- Web backend remains experimental.
- CPU fallback is available through bridge runtime routing.
- Safari compatibility guard and fallback behavior are integrated in this repo.
- Legacy bridge assets may be forced to CPU in Safari when GPU layers are
  requested.

## Runtime overrides

You can override bridge asset source/version before loader startup:

```html
<script>
  window.__llamadartBridgeAssetsRepo = 'leehack/llama-web-bridge-assets';
  window.__llamadartBridgeAssetsTag = 'v0.1.4';
</script>
```

## Contract reference

Bridge contract details (global shape, required methods, compatibility targets):

- [`doc/webgpu_bridge.md`](https://github.com/leehack/llamadart/blob/main/doc/webgpu_bridge.md)
