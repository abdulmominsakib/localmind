---
title: Native and Web Sync Flows
description: Follow the correct workflow when syncing native bindings, companion package pins, or published web bridge assets.
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
native hook pins, updates companion package SPM pins, refreshes current
README/website native pin docs, and opens a PR. It does not bump companion
package versions by default. Use the sync script's explicit
`--bump-companion-versions` option only when the same change intentionally
prepares companion package releases. The `native_tag` input controls the
`llamadart-native` release. Stable distribution tags use strict
`vMAJOR.MINOR.PATCH`; historical/nightly artifacts remain consumable through an
explicit `bNNNN` tag. New nightly wrapper releases use `bNNNN-N`; existing
`bNNNN-llamadart.N` artifacts remain explicit consumption-only inputs. `latest`
accepts only an unsuffixed `vMAJOR.MINOR.PATCH` regardless of GitHub metadata.
New wrapper and nightly releases are GitHub prereleases and must be named
explicitly. Immutable historical `bNNNN` and `bNNNN-llamadart.N` artifacts may
retain older `prerelease=false` metadata, but remain explicit compatibility
inputs. Nightly cores use canonical decimal spelling (`b0` or a nonzero first
digit), and rebuild counters start at 1 without leading zeros.
The `litert_lm_tag` input defaults to `keep`; set it to a
`litert-lm-native` tag or `latest` only when the LiteRT-LM native release should
move in the same PR.

For a wrapper-only rebuild of upstream stable `vM.m.p`, the native release uses
`vM.m.p-N`: for example upstream `v0.2.0` maps to native `v0.2.0-1`, then
`v0.2.0-2`. The native release policy orders that sequence after `v0.2.0` and
before upstream `v0.2.1`, despite generic SemVer prerelease ordering. The suffix
belongs only to `native_release_tag`; `llama_cpp_tag`/`llama_cpp_ref` in
`assets.json` must remain the exact unsuffixed upstream prefix. GitHub classifies
the rebuild as a prerelease, so automatic `latest` discovery must not select it.

LiteRT-LM native tags follow four writable forms: stable `vMAJOR.MINOR.PATCH`,
stable rebuild `vMAJOR.MINOR.PATCH-N`, development `g<12hex>`, and development
rebuild `g<12hex>-N`. Historical `vMAJOR.MINOR.PATCH-native.N` tags remain
explicitly consumable but read-only. The sync tool validates schema 2 release,
upstream, native commit, ABI/capability, platform, digest, and real-model
evidence fields before it prepares changes for a new compact or development tag.
The release artifact tag is stored separately from the runtime/cache version,
so development assets use `g<sha>` directly and never synthesize `vg<sha>` URLs.
Schema 1 manifests remain accepted only when the downloaded bytes, GitHub asset
digest, and immutable tag commit match the checked-in historical allowlist.

Changing between stable and development channels requires
`--allow-litert-channel-transition`; changing between two distinct `g<sha>`
lines requires `--allow-litert-development-line-transition`. Both flags default
off and represent explicit review of the owner-validated ancestry evidence.
Legacy and compact tags with the same version and rebuild ordinal are aliases
and are rejected. All pin edits are staged before a recoverable multi-file
replacement, so a partial filesystem failure restores every prior pin.

Local fallback:

```bash
python3 tool/native/sync_native_release_pins.py \
  --llama-cpp-tag latest \
  --litert-lm-tag keep \
  --dry-run
tool/native/sync_native_headers_and_bindings.sh --tag latest
python3 tool/native/sync_native_release_pins.py \
  --llama-cpp-tag latest \
  --litert-lm-tag keep
```

The pin sync rejects same-channel rollback and release/manifest version skew.
After the default pin moves to the stable channel, an intentional compatibility
test against a `bNNNN`, `bNNNN-N`, or legacy `bNNNN-llamadart.N` artifact must
name that tag and pass `--allow-legacy-tag`; the compatibility-named flag does
not allow rollback within either channel. The manual sync workflow exposes the
same gate as its `allow_nightly_channel` checkbox and leaves it disabled by
default.
Stable releases must provide `assets.json`, `SHA256SUMS`, every supported bundle,
and hook contract version 1. New stable or nightly wrapper forms require
`assets.json`, `native_release_tag`, and the retained `tag` compatibility alias;
older base or legacy-wrapper manifests with only `tag` remain valid.
Manifest checksums must agree with both `SHA256SUMS` and GitHub release asset
digests before any pin files are written.
Re-syncing the exact current tag remains idempotent for recovery and validation;
the owning native release workflow is responsible for rejecting publication
collisions.

After sync, run analyze/tests/docs checks before merge. For Apple SPM pin
changes, verify the companion package changes under `packages/`, then run at
least one Flutter iOS build and one macOS build with those packages enabled.
Inspect the packaged frameworks to confirm the expected native release artifacts
are present.

## Native version update checklist

Use this checklist in native sync PRs:

- Confirm `llamadart-native` or `litert-lm-native` has published the target
  release and the required per-platform native-assets archives.
- For a stable-channel llama.cpp native sync, confirm the release tag is an
  upstream-aligned `vMAJOR.MINOR.PATCH` or an explicitly selected wrapper rebuild,
  `assets.json` records the correct distinct native/upstream tags and hook
  contract version 1, and its artifact checksums match the release assets.
- For LiteRT-LM schema 2 releases, confirm the manifest's exact upstream and
  native commits, ABI/capabilities, platform list, artifact digests, and
  Linux/Windows real-model smoke evidence before changing any pin.
- Confirm the schema-2 bytes match the owner-generated fixture contract under
  `tool/native/fixtures/`; do not add a downstream-only manifest variant.
- Confirm the same release provides Apple SPM-compatible XCFramework zip
  artifacts when companion package pins should move.
- Update `hook/build.dart` native pins with
  `.github/workflows/sync_native_bindings.yml` or
  `tool/native/sync_native_release_pins.py`.
- Update companion package `Package.swift` URL/checksum pins under `packages/`
  when Apple XCFramework releases changed.
- Bump changed companion package versions only when that PR is intentionally
  preparing companion package releases; otherwise leave companion pub versions
  unchanged and let release prep own the version bump.
- Ensure each changed companion package README and CHANGELOG native-pin note
  names the new native repo tag when package contents change.
- Regenerate `lib/src/backends/llama_cpp/bindings.dart` whenever the
  `llamadart-native` header bundle changed.
- Update public docs that mention the pinned native versions or source table.

## Companion package release handoff

Native sync PRs can leave the repository in a state where the companion package
source under `packages/` is ready, but the corresponding pub.dev package version
does not exist yet. That is expected before merge, but it must be resolved before
tagging the next core `llamadart` release.

For every companion package whose `pubspec.yaml` version changed, or whose
version is newly referenced by current install docs:

1. Confirm the `Package.swift` binary targets point at published native GitHub
   release assets and that the pinned checksums match those assets.
2. Merge the sync/release-prep PR first. The PR itself must not publish the
   companion or core package.
3. After merge, `release_on_prep_merge.yml` uses the release-prep PR merge as
   the publishing approval boundary and pushes each missing package-specific
   companion tag:
   `llamadart_llama_cpp_flutter-v{{version}}` or
   `llamadart_litert_lm_flutter-v{{version}}`.
4. Wait for `publish_companion_pubdev.yml` to pass.
5. Verify the version URL on pub.dev, for example
   `https://pub.dev/api/packages/llamadart_llama_cpp_flutter/versions/{{version}}`.
6. Only after the companion version is live, the automation pushes the core
   `vX.Y.Z` release tag that documents or depends on that companion version.

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
