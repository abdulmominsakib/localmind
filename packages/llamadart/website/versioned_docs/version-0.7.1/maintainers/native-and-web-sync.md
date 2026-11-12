---
title: Native and Web Sync Flows
description: Follow the correct cross-repo workflow when syncing native bindings or published web bridge assets.
unlisted: true
---

## Native sync flow

When native behavior or bindings need updates:

1. Make and release changes in `llamadart-native` or `litert-lm-native` first.
2. Sync native version, bindings, and Apple SPM pins in this repo.

The invariant is that native-assets and Apple Swift Package Manager builds
must resolve the same bridge runtime release. Do not point the native-assets
hook at `leehack/*-native` artifacts while `darwin/llamadart/Package.swift`
points at unrelated upstream Apple binaries; that creates different bridge
behavior between pure Dart/macOS fallback and Flutter Apple builds.

| Runtime | Native-assets pin | Apple SPM pin |
| --- | --- | --- |
| llama.cpp / GGUF | `hook/build.dart` `_llamaCppTag`, default repository `leehack/llamadart-native` | `darwin/llamadart/Package.swift` binary target URL/checksum for the matching `llamadart-native` Apple XCFramework release asset |
| LiteRT-LM / `.litertlm` | `hook/build.dart` `_litertLmVersion`, repository `leehack/litert-lm-native` | `darwin/llamadart/Package.swift` binary target URL/checksum for the matching `litert-lm-native` Apple XCFramework release asset |

Preferred in-repo workflow:

- `.github/workflows/sync_native_bindings.yml`

That workflow syncs llama.cpp headers, regenerates ffigen bindings, updates the
native hook pins, updates Apple SPM URL/checksum pins from GitHub release asset
digests, and opens a PR. The `native_tag` input controls the `llamadart-native`
release. The `litert_lm_tag` input defaults to `keep`; set it to a
`litert-lm-native` tag or `latest` only when the LiteRT-LM native release should
move in the same PR.

Local fallback:

```bash
tool/native/sync_native_headers_and_bindings.sh --tag latest
python3 tool/native/sync_native_release_pins.py \
  --llama-cpp-tag latest \
  --litert-lm-tag keep
```

After sync, run analyze/tests/docs checks before merge. For Apple SPM pin
changes, also run at least one Flutter iOS build and one macOS build with SPM
enabled, then inspect the packaged frameworks to confirm the expected native
release artifacts are present.

## Native version update checklist

Use this checklist in native sync PRs:

- Confirm `llamadart-native` or `litert-lm-native` has published the target
  release and the required per-platform native-assets archives.
- Confirm the same release provides Apple SPM-compatible XCFramework zip
  artifacts, or explicitly document that Apple SPM pins are unchanged.
- Update `hook/build.dart` native pins and `darwin/llamadart/Package.swift`
  URL/checksum pins with `.github/workflows/sync_native_bindings.yml` or
  `tool/native/sync_native_release_pins.py`.
- Regenerate `lib/src/backends/llama_cpp/bindings.dart` whenever the
  `llamadart-native` header bundle changed.
- Update public docs that mention the pinned native versions or source table.

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

Use the contributor matrix to choose exact rows and record PR evidence:

```bash
dart run tool/testing/test_matrix.dart --list
```

- Native: model load/generation smoke checks on relevant platforms.
- Web: bridge load/fallback checks in `example/chat_app`.
- Docs: ensure version/platform notes match newly pinned runtime behavior.
