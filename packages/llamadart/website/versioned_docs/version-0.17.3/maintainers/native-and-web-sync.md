---
title: Native and web sync flows
description: Follow the correct workflow when syncing native bindings, companion package pins, or published web bridge assets.
---

## Apple companion compatibility

The hook binds the complete maintained SwiftPM template, normalizing only its
release tag, checksum and CRLF line endings. A companion manifest code change
requires a reviewed hook contract update; copied tag declarations cannot
authorize alternate framework URLs or target code.

Apple llama.cpp and stable_diffusion companion selection validates the
**resolved** package from the consumer/workspace `package_config.json`,
including path and dependency overrides. Its package identity and maintained
SwiftPM native pin must match the core hook pin (`llamaCppTag` or
`stableDiffusionReleaseTag`) before any in-process native asset is emitted.
Each companion has its own template hash in `hook/build.dart`. Updating a
declared dependency constraint alone is insufficient: rerun `flutter pub get`
and resolve the matching companion. Core native tag/path/backend overrides do
not replace SwiftPM frameworks and cannot bypass this check. A companion that
pins an earlier compatible tag (`llamaCppCompatibleAppleCompanionTags`,
`stableDiffusionCompatibleAppleCompanionTags`) must also declare that tag's
exact XCFramework checksum (`llamaCppCompatibleAppleCompanionChecksums`,
`stableDiffusionAppleCompanionChecksums`); the native pin sync clears both
when the pin moves.

Local `Artifacts` overrides in that companion are rejected because their ABI
provenance is unverified. Remove the override and use the pinned remote
framework. Non-Apple native-assets and LiteRT selection are unchanged.

## Native sync flow

When native behavior or bindings need updates:

1. Make and release changes in `llamadart-native`, `litert-lm-native` or
   `stable-diffusion-native` first.
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
| llama.cpp / GGUF | `lib/src/hook/native_release_pins.dart` `llamaCppTag` and per-bundle checksums (`llamaCppBundleSha256`), default repository `leehack/llamadart-native` | `packages/llamadart_llama_cpp_flutter/.../Package.swift` binary target URL/checksum |
| LiteRT-LM / `.litertlm` | `lib/src/hook/native_release_pins.dart` `liteRtLmReleaseTag` and per-bundle checksums, repository `leehack/litert-lm-native` | `packages/llamadart_litert_lm_flutter/.../Package.swift` binary target URLs/checksums |
| stable-diffusion.cpp (opt-in `stable_diffusion`) | `lib/src/hook/native_release_pins.dart` `stableDiffusionReleaseTag` and per-bundle checksums, repository `leehack/stable-diffusion-native` | `packages/llamadart_stable_diffusion_flutter/.../Package.swift` binary target URL/checksum |

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

Schema 2 optionally accepts `upstream.sourcePatches` as a non-empty list of
objects with exactly `id`, `path`, `sha256`, `source`, `preimageSha256Lf`,
`postimageSha256Lf` and `scope`. All fields are non-empty strings; the three
hashes must be lowercase 64-hex SHA-256 digests. The owner validates patch
contents and applicability; sync validates the declared provenance shape.

For schema 2, Apple target selection follows the per-platform owner inventory.
Sync removes a formerly required iOS Gemma constraint-provider target from a
modern Swift manifest when the new iOS bundles no longer require it. An optional
provider XCFramework asset alone does not add an iOS dependency. The separate
macOS compatibility target and all required macOS provider/runtime files remain
in the generated inventories. Releases whose iOS bundles still require the
provider retain it; malformed or ambiguous Swift target layouts fail before
pin files are replaced. Updating the sync tool does not change the current pins
or publish a runtime.

Changing between stable and development channels requires
`--allow-litert-channel-transition`; changing between two distinct `g<sha>`
lines requires `--allow-litert-development-line-transition`. Both flags default
off and represent explicit review of the owner-validated ancestry evidence.
Entering a newer stable version at a qualified rebuild instead of its base
release requires `--allow-litert-stable-rebuild-entry`. Use this only after
reviewing the corrected owner artifact; full manifest validation still applies.
This flag does not permit rollbacks, same-version rebuild skips, or channel
changes. For example, a qualified `v0.17.0-1` can replace `v0.16.0-native.2`
without first consuming the superseded `v0.17.0` artifact.
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

Run the header and bindings step on Linux, as the workflow does (Ubuntu with
`llvm-dev`, `libclang-dev` and `clang`): `ggml.h` pulls in the C library's
`FILE`, so a macOS run of the same `ffigen.yaml` rewrites that struct and
nothing else.

The pin sync rejects same-channel rollback and release/manifest version skew.
After the default pin moves to the stable channel, an intentional compatibility
test against a `bNNNN`, `bNNNN-N`, or legacy `bNNNN-llamadart.N` artifact must
name that tag and pass `--allow-legacy-tag`; the compatibility-named flag does
not allow rollback within either channel. The manual sync workflow exposes the
same gate as its `allow_nightly_channel` checkbox and leaves it disabled by
default.
Stable releases must provide `assets.json`, `SHA256SUMS`, every supported bundle,
and hook contract version 1 or 2. Contract 2 publishes backend sidecars
(`module: backend-*`, such as `windows-x64-cuda12`); the sync pins each one in
`llamaCppBackendSidecarSpecs` from its release digest and records the contract
in `llamaCppHookContractVersion`, so the hook fetches a sidecar only when its
backend is selected. New stable or nightly wrapper forms require
`assets.json`, `native_release_tag`, and the retained `tag` compatibility alias;
older base or legacy-wrapper manifests with only `tag` remain valid.
Manifest checksums must agree with both `SHA256SUMS` and GitHub release asset
digests before any pin files are written. The sync rewrites
`llamaCppBundleSha256` from each bundle archive's release digest and fails
without writing when the release lacks a pinned bundle.
Any PR or push that changes the pin file also runs the Native Release Digests
workflow. It compares `llamaCppBundleSha256` and `stableDiffusionBundleSpecs`
with their pinned releases' `SHA256SUMS`, and `liteRtLmBundleSpecs` with the
pinned LiteRT-LM release's GitHub asset digests, since that release's
`SHA256SUMS` lists only the extracted libraries. That catches a manual edit or
conflict resolution that left stale digests. Run it locally with
`dart run tool/testing/check_native_release_digests.dart`; set `GH_TOKEN` if
the unauthenticated GitHub API rate limit is exhausted.
Re-syncing the exact current tag remains idempotent for recovery and validation;
the owning native release workflow is responsible for rejecting publication
collisions.

After sync, run analyze/tests/docs checks before merge. Also run the Python
suites that only CI's Analyze & Lint job runs, since the Dart checks do not
cover a pin change:

```bash
python3 tool/native/test_sync_native_release_pins.py
python3 tool/native/test_native_header_archive.py
python3 tool/native/test_sync_native_headers_and_bindings.py
python3 tool/native/test_sync_stable_diffusion_bindings.py
```

CI runs them with the Ubuntu runner's `python3` (3.12). Use Python 3.10 or
newer: under macOS's system Python 3.9 the pin suite reports three
`KeyError: 'file'` errors in `ReleaseTransportFailureTest`. For Apple SPM pin
changes, verify the companion package changes under `packages/`, then run at
least one Flutter iOS build and one macOS build with those packages enabled.
Inspect the packaged frameworks to confirm the expected native release artifacts
are present.

App overrides through `llamadart_native_tag` accept the same tag forms as the
sync, never `latest`, and do not regenerate bindings. The symbols and wrapper
fixes a replacement runtime must provide are listed in
[Override the llama.cpp release](../platforms/native-build-hooks#override-the-llamacpp-release).

## stable_diffusion runtime sync

The opt-in `stable_diffusion` runtime syncs through the
`stable_diffusion_tag` input of `sync_native_bindings.yml` (default `keep`). A
non-`keep` tag runs the pin sync, then `sync_stable_diffusion_bindings.py`, and
puts the bindings and companion files in the automation commit; its branch is
`automation/native-sync-<native tag>-sd-<stable_diffusion tag>`.
`stable-diffusion-native` tags are `vMAJOR.MINOR.PATCH`, or
`vMAJOR.MINOR.PATCH-N` for a rebuild; name the tag explicitly, since `latest`
skips GitHub prereleases. For a stable_diffusion-only sync, pass the current
llama.cpp tag as `native_tag`: it defaults to `latest` and cannot be `keep`.
By hand:

```bash
python3 tool/native/sync_native_release_pins.py \
  --stable-diffusion-tag v0.3.0 \
  --dry-run
python3 tool/native/sync_native_release_pins.py \
  --stable-diffusion-tag v0.3.0
python3 tool/native/sync_stable_diffusion_bindings.py
```

The pin sync reads the release `manifest.json`, requires it to match its GitHub
asset digest, requires every runtime archive's manifest SHA-256 to match its
GitHub digest, and rewrites `stableDiffusionReleaseTag`,
`stableDiffusionVersion` and each pinned bundle's checksum and library. It
also rewrites the `llamadart_stable_diffusion_flutter` `Package.swift` tag and
checksum from the manifest's `xcframework` artifact, after checking that
artifact against its GitHub digest, and records the pin in the companion
README and CHANGELOG. It does not touch other docs: update the pin in
`website/docs/platforms/support-matrix.md` by hand. It
fails if a pinned bundle is no longer published or the tag moves backwards,
and only notes new targets: a new target needs a `StableDiffusionBundleSpec`
and a `stableDiffusionBundleForNativeBundle` mapping by hand.

`sync_stable_diffusion_bindings.py` downloads the pinned `linux-x64` archive
(or takes `--archive`), checks it against the pin, stages
`include/stable-diffusion.h` and `include/sd_dart_wrapper.h` under
`.dart_tool/llamadart/ffigen_headers_stable_diffusion/`, and regenerates
`lib/src/backends/stable_diffusion/stable_diffusion_bindings.dart` with
`ffigen_stable_diffusion.yaml`. The bindings resolve the library through the
`package:llamadart/stable_diffusion` native-asset id that the hook emits.
That config leaves five `sd_dart_exit_` functions unbound and marks
`sd_dart_progress_read` as the only leaf call. A new `sd_dart_` function the
image worker calls also goes into `StableDiffusionCalls`, whose probe decides
whether the runtime is supported, or, when llamadart also has to run on a
runtime without it, into one of its optional groups, which is `null` there
([exit teardown](https://github.com/leehack/llamadart/blob/main/doc/llama_cpp_exit_teardown.md#image-models)).

After a sync, run
`dart test -p vm --run-skipped -t local-only test/integration/stable_diffusion_runtime_hook_test.dart`
on macOS: it builds a throwaway consumer against the new pin and probes the
runtime it bundles. Then run the `image-generation-smoke` and
`image-exit-teardown` rows of `doc/testing_matrix.md`.

## Native version update checklist

Use this checklist in native sync PRs:

- Confirm `llamadart-native`, `litert-lm-native` or `stable-diffusion-native`
  has published the target release and the required per-platform
  native-assets archives.
- For a stable-channel llama.cpp native sync, confirm the release tag is an
  upstream-aligned `vMAJOR.MINOR.PATCH` or an explicitly selected wrapper rebuild,
  `assets.json` records the correct distinct native/upstream tags and hook
  contract version 1 or 2, and its artifact checksums match the release
  assets.
- For LiteRT-LM schema 2 releases, confirm the manifest's exact upstream and
  native commits, ABI/capabilities, platform list, artifact digests, and
  Linux/Windows real-model smoke evidence before changing any pin.
- Confirm the schema-2 bytes match the owner-generated fixture contract under
  `tool/native/fixtures/`; do not add a downstream-only manifest variant.
- For a LiteRT-LM release on a new upstream version, first mirror that
  version's entry of the owner's `tools/prebuilt_overrides.py` in
  `LITERT_PREBUILT_OVERRIDES` (`tool/native/sync_native_release_pins.py`). The
  table is kept by hand, and the sync rejects a manifest whose prebuilt
  overrides it does not list.
- Confirm the same release provides Apple SPM-compatible XCFramework zip
  artifacts when companion package pins should move.
- Update `lib/src/hook/native_release_pins.dart` native pins with
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
  `llamadart-native` header bundle changed. Only
  `package:llamadart/llama_cpp_bindings.dart` exports it, outside semantic
  versioning, so a regeneration never changes the app API.
- Update public docs that mention the pinned native versions or source table.

## Companion package release handoff

Core `0.17.1` preparation pairs all three Apple companions at `0.17.1`, with
SwiftPM pins `v0.8.0-1`, `v0.18.1-4` and `v0.3.0-1`. The llama.cpp companion
requires `llamadart: '>=0.17.1 <0.18.0'`. The LiteRT-LM and SD companions keep
`llamadart: '>=0.17.0 <0.18.0'`: their manifests are unchanged from `0.17.0`, so
core `0.17.0` still accepts them. Merge remains the approval boundary for
publication.

Core `0.17.0` preparation pairs all three Apple companions at `0.17.0`, with
SwiftPM pins `v0.7.0-3`, `v0.18.1-4` and `v0.3.0-1`, and constrains them to
`llamadart: '>=0.17.0 <0.18.0'`. Core `0.17.0` lists no earlier llama.cpp or
SD companion pins, so a git or path override that keeps a `0.16.0` llama.cpp
or SD companion fails its build; the LiteRT-LM pin is unchanged from companion
`0.16.2`.

Core `0.16.2` preparation moves LiteRT-LM to `v0.18.1-4`, which ships the
Visual C++ runtime in the Windows bundle and makes Linux and Windows CPU
inference honour the thread count, and pairs it with
`llamadart_litert_lm_flutter` `0.16.2`, constrained to
`llamadart: '>=0.16.2 <0.17.0'`: core `0.16.1` treats a companion pinning
`v0.18.1-4` as a later build and keeps macOS LiteRT-LM in the hook cache. Core
`0.16.2` accepts the published `0.16.1` (`v0.18.1-2`) and `0.16.0`
(`v0.18.1`) companions with an upgrade warning. The llama.cpp and SD
companions stay `0.16.0`.

Core `0.16.1` preparation moves LiteRT-LM to `v0.18.1-2`, which restores
deterministic CPU output and Gemma 4 CPU decode speed on SME2 CPUs, and pairs
it with `llamadart_litert_lm_flutter` `0.16.1`, constrained to
`llamadart: '>=0.16.1 <0.17.0'`. Published core `0.16.0` hands macOS LiteRT-LM
to a companion only when it pins `v0.18.1`; with `v0.18.1-2` it keeps
LiteRT-LM in the hook cache with a warning to upgrade both. Core `0.16.1`
accepts the published `0.16.0` companion (pinning `v0.18.1`) with an upgrade
warning. The llama.cpp and SD companions stay `0.16.0`.

Core `0.16.0` preparation pairs all three Apple companions at `0.16.0`, with
SwiftPM pins `v0.7.0-2`, `v0.18.1` and `v0.3.0`, and constrains them to
`llamadart: '>=0.16.0 <0.17.0'`. Merge remains the approval boundary for
publication.

Core `0.15.6` preparation pairs the llama.cpp and LiteRT-LM companions at
`0.15.2`, with SwiftPM pins `v0.7.0-2` and `v0.18.0-3`, and constrains both to
`llamadart: '>=0.15.6 <0.16.0'`: cores `0.15.0` to `0.15.5` reject the
llama.cpp pin and keep macOS LiteRT-LM in the hook cache for the LiteRT-LM pin.
Core `0.15.6` still accepts locked `0.15.0`/`0.15.1` companions, which pin
`v0.7.0-1` and `v0.18.0-2`, with an upgrade warning. The SD companion stays
`0.15.2`.

Core `0.15.0` preparation pairs all three Apple companions at `0.15.0`,
with SwiftPM pins `v0.7.0-1`, `v0.18.0-2` and `v0.2.0-3`, respectively.
Merge remains the approval boundary for publication.

Core `0.14.0` adoption preparation pairs all three Apple companions at `0.14.0`,
with SwiftPM pins `v0.7.0`, `v0.18.0-2` and `v0.2.0-3`, respectively. This
metadata does not publish packages; matching published Web assets and consumer
qualification remain adoption gates.

Core `0.13.2`, `0.13.1` and `0.13.0` pair with companions `llamadart_llama_cpp_flutter`,
`llamadart_litert_lm_flutter` and `llamadart_stable_diffusion_flutter`
`0.13.0`, whose SwiftPM pins are `v0.6.0-3`, `v0.18.0-1` and `v0.2.0-3`,
respectively. Repository manifests alone do not prove pub.dev publication.
Core `0.12.2` pairs with companions `0.0.23`, `0.0.16` and `0.0.3`, which pin
the same runtimes.
Companion `llamadart_llama_cpp_flutter` `0.0.22` pairs with core `0.12.1`
and `0.12.0`. Companion `llamadart_litert_lm_flutter` `0.0.15` pairs with core
`0.12.1`, `0.0.14` with core `0.12.0`, and `0.0.13` retains `v0.17.0-8` for
core `0.11.1` and `0.11.0`. The iOS
artifacts meet the declared 16.4 deployment floor, but runtime execution at
16.4 remains unqualified; keep [#831](https://github.com/leehack/llamadart/issues/831) open.

Core `0.16.0` moves SD to `v0.3.0`, whose `sd_ctx_params_t` grew from 320 to
336 bytes, so it accepts no older Apple SD companion and `0.15.x` cores reject
the companion pinning `v0.3.0`. The runtime treats a null `flash_attn_mode` or
`conv_direct_mode` as automatic per-module selection, which changes images and
is not seed-reproducible on Metal; `applyStableDiffusionContextParams` always
writes both modes from the legacy flags, and `batched_cfg=false`. Map any new
field whose initializer selects automatic behavior the same way.

SD `v0.3.0-1` moves upstream to master-1017 and carries the FP8-on-Metal load
fix as a patch. Upstream `generate_image` now returns owned results;
`sd_dart_generate_image` keeps its image-array contract, and the removed
`sd_ctx_supports_ref_image_conditioning` must not be bound. The patch adds no
export and `sd_commit` names the upstream commit, so
`StableDiffusionCalls.loadsFp8AsF16OnMetal` requires the hook-pinned tag at or
after `fp8MetalNativeRelease` and the upstream-1017 `fp8MetalSymbols`. The
bounded image recipes gate on the upstream commit
(`ImageGenerationEngine._isQualifiedRuntime`): a repin that moves it reruns
their `run_local_e2e.dart` scenarios before moving that gate.

Core `0.17.1` moves the llama.cpp pin to `v0.8.0-1`, built from upstream `v0.8.0`, inside
the `0.17` minor. It keeps companion `0.17.0` (`v0.7.0-3`) through
`llamaCppCompatibleAppleCompanionTags` because the core calls no symbol that
framework lacks; `test/fixtures/native/llama_cpp_apple_compatibility.json` records
the per-slice check and a test keeps the core off the listed v0.8.0-only names. The
reverse pair is unsafe (`mtmd_helper_init_opt` grows to 32 bytes), so companion
`0.17.1` needs `llamadart: '>=0.17.1 <0.18.0'`.

Native sync PRs can leave the repository in a state where the companion package
source under `packages/` is ready, but the corresponding pub.dev package version
does not exist yet. That is expected before merge, but it must be resolved by
the next core `llamadart` release.

Companion native pins may move within a core minor only when both directions
of dependency resolution remain safe. The release-prep verifier checks every
published companion whose constraint admits the new core against its accepted
pins, and checks each new companion against every published core its constraint
admits. It rejects an old core/new pin pairing until the companion's lower
bound excludes the rejecting core. Full release-tag history is required.

Keep legacy compatibility explicit and tied to exact artifact checksums. A tag
prefix or rebuild number alone establishes no ABI compatibility. SD pin syncs
clear the older-pin list and checksum proof when the target changes; same-tag
refreshes preserve it and reject a changed checksum. Requalify before adding
an older artifact back. A minor release remains necessary when older admitted
companions cannot remain supported safely.

Keep checksum maps in the generated literal format, with explanatory comments
outside the map. Sync rejects duplicate declarations or tags, computed or
commented checksum entries, and interpolated strings in the native pin file.
Declarations inside comments or strings cannot supply proof and are never
rewritten as live contracts.

Companion versions share the core's `MAJOR.MINOR` and move only their patch
independently, so a core minor release sets every companion to `M.m.0` and a
companion change within a minor bumps its patch. The release docs verifier
fails on a mismatch from core `0.13.0` on.

For every companion package whose `pubspec.yaml` version changed, or whose
version is newly referenced by current install docs:

1. Confirm the `Package.swift` binary targets point at published native GitHub
   release assets and that the pinned checksums match those assets.
2. Merge the sync/release-prep PR first. The PR itself must not publish the
   companion or core package.
3. After merge, `release_on_prep_merge.yml` uses the release-prep PR merge as
   the publishing approval boundary, pushes the core `vX.Y.Z` release tag and
   waits for that core on pub.dev, because each companion's `llamadart`
   constraint must resolve there.
4. The automation then pushes each missing package-specific companion tag:
   `llamadart_llama_cpp_flutter-v{{version}}`,
   `llamadart_litert_lm_flutter-v{{version}}` or
   `llamadart_stable_diffusion_flutter-v{{version}}`. A package's first
   version must already be published by hand; see
   [Release workflow](./release-workflow).
5. Wait for `publish_companion_pubdev.yml` to pass.
6. Verify the version URL on pub.dev, for example
   `https://pub.dev/api/packages/llamadart_llama_cpp_flutter/versions/{{version}}`.

## Web bridge asset sync flow

When web bridge runtime behavior changes:

1. Update and release in `llama-web-bridge`.
2. Publish assets in `llama-web-bridge-assets`.
3. Update pinned assets in this repo.

Fetch pinned assets for local app web files:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=<tag> ./scripts/fetch_webgpu_bridge_assets.sh
```

A repin updates the release id, tag commit and bridge source in
`tool/testing/check_webgpu_bridge_tag.dart`, the tag and manifest SHA-256 in
`lib/src/web_setup/web_bridge_setup.dart` (which `dart run
llamadart:web_setup` trusts), and the docs that restate them.
Before opening the PR, check them against the published release:

```bash
dart run tool/testing/check_webgpu_bridge_tag.dart --verify-manifest
```

It fails unless GitHub reports the pinned release id for the tag, the release
is immutable and not a draft, the tag (peeled through any annotated tags)
points at the pinned commit, and the CDN manifest bytes and provenance match.
Unauthenticated GitHub API calls are rate limited; set `GH_TOKEN` or
`GITHUB_TOKEN` to authenticate (`GH_TOKEN` wins when both are set, as in `gh`).
The token is sent only as a request header and never printed.

## Validation after sync

Use the contributor matrix to choose exact rows and record PR evidence:

```bash
dart run tool/testing/test_matrix.dart --list
```

- Native: model load/generation smoke checks on relevant platforms.
- Web: bridge load/fallback checks in `example/chat_app`.
- Docs: ensure version/platform notes match newly pinned runtime behavior.
