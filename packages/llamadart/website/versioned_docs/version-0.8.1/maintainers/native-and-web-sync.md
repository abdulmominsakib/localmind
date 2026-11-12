---
title: Native and Web Sync Flows
description: Follow the correct workflow when syncing native bindings, companion package pins, or published web bridge assets.
unlisted: true
---

## Native sync flow

When native behavior or bindings need updates:

1. Make and release changes in `llamadart-native` or `litert-lm-native` first.
2. Sync native version and bindings in this repo.
3. Sync matching Apple SPM pins in the Flutter runtime companion packages under
   `packages/` when Apple XCFramework releases changed.

The invariant is that core native-assets builds and Flutter Apple companion
Swift Package Manager builds should resolve compatible bridge runtime releases.
Do not point the core hook at `leehack/*-native` artifacts while companion
`Package.swift` files point at unrelated Apple binaries; that creates different
bridge behavior between pure Dart/macOS fallback and Flutter Apple builds.

| Runtime | Core native-assets pin | Apple SPM companion pin |
| --- | --- | --- |
| llama.cpp / GGUF | `hook/build.dart` `_llamaCppTag`, default repository `leehack/llamadart-native` | `packages/llamadart_llama_cpp_flutter/.../Package.swift` binary target URL/checksum |
| LiteRT-LM / `.litertlm` | `hook/build.dart` `_litertLmVersion`, repository `leehack/litert-lm-native` | `packages/llamadart_litert_lm_flutter/.../Package.swift` binary target URLs/checksums |

Preferred in-repo workflow:

- `.github/workflows/sync_native_bindings.yml`

That workflow syncs llama.cpp headers, regenerates ffigen bindings, updates the
native hook pins, updates companion package SPM pins, bumps the changed
companion package patch versions, updates README/CHANGELOG pin notes, and opens
a PR. The `native_tag` input controls the `llamadart-native` release. The
`litert_lm_tag` input defaults to `keep`; set it to a
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
changes, verify the companion package changes under `packages/`, then run at
least one Flutter iOS build and one macOS build with those packages enabled.
Inspect the packaged frameworks to confirm the expected native release artifacts
are present.

## Native version update checklist

Use this checklist in native sync PRs:

- Confirm `llamadart-native` or `litert-lm-native` has published the target
  release and the required per-platform native-assets archives.
- Confirm the same release provides Apple SPM-compatible XCFramework zip
  artifacts when companion package pins should move.
- Update `hook/build.dart` native pins with
  `.github/workflows/sync_native_bindings.yml` or
  `tool/native/sync_native_release_pins.py`.
- Update companion package `Package.swift` URL/checksum pins under `packages/`
  when Apple XCFramework releases changed.
- Bump each changed companion package patch version.
- Ensure each changed companion package README and versioned CHANGELOG section
  names the new native repo tag.
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
