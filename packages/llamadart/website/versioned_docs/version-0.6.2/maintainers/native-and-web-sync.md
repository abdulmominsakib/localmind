---
title: Native and Web Sync Flows
---

## Native sync flow

When native behavior or bindings need updates:

1. Make and release changes in `llamadart-native` first.
2. Sync native version/bindings in this repo.

Preferred in-repo workflow:

- `.github/workflows/sync_native_bindings.yml`

Local fallback:

```bash
tool/native/sync_native_headers_and_bindings.sh --tag latest
```

After sync, run analyze/tests/docs checks before merge.

## Web bridge asset sync flow

When web bridge runtime behavior changes:

1. Update and release in `llama-web-bridge`.
2. Publish assets in `llama-web-bridge-assets`.
3. Update pinned assets in this repo.

Fetch pinned assets for local app web files:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=<tag> ./scripts/fetch_webgpu_bridge_assets.sh
```

## Validation after sync

- Native: model load/generation smoke checks on relevant platforms.
- Web: bridge load/fallback checks in `example/chat_app`.
- Docs: ensure version/platform notes match newly pinned runtime behavior.
