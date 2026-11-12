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
not replace SwiftPM frameworks and cannot bypass this check. A companion must
also declare the qualified current tag's exact XCFramework checksum (`llamaCppCompatibleAppleCompanionChecksums`,
`stableDiffusionAppleCompanionChecksums`). Earlier admitted tags
(`llamaCppCompatibleAppleCompanionTags`,
`stableDiffusionCompatibleAppleCompanionTags`) require their own exact checksum.
Native pin sync rejects a changed same-tag checksum, and replaces the current
checksum and clears earlier compatibility when the pin moves.

Local `Artifacts` overrides in that companion are rejected because their ABI
provenance is unverified. Remove the override and use the pinned remote
framework. Non-Apple native-assets and LiteRT selection are unchanged.

## Default consumer and AOT acceptance

Use the explicit `native-default-consumer-aot` scenario and dedicated manual
workflow to qualify ordinary default-hook consumers on macOS arm64 and Windows
x64. See the [test matrix](https://github.com/leehack/llamadart/blob/main/doc/testing_matrix.md#default-native-consumer-and-distributed-aot)
for the exact source/model identity and invocation. The expected native tag is
verification-only and must equal the checked-in pin; no runtime override is
introduced. Reviewed unmerged source may be tested without landing the pin first.

A new dispatch workflow must first exist on the default branch. For its initial
premerge validation, the registered `ci.yml` offers an explicit manual-only
`native_default_qualification` bridge. It calls the same-commit reusable
workflow, passes reviewed SHA/tag inputs, and skips ordinary CI/deployment only
in that mode. The flag defaults to false; the dedicated dispatch route remains
available after registration. See the test matrix for the bootstrap command.

`v0.8.0-2` establishes pipeline behavior only. `v0.8.0-3` needs its own complete
owner/public-artifact gates, actual provider identity, inference and distributed
AOT receipts and independent acceptance. Historical Windows 16-case evidence
uses `v0.8.0-1`; help/list/build success cannot replace these runtime gates.
Acceptance is tracked in [#1762](https://github.com/leehack/llamadart/issues/1762);
source integration alone does not close it. This maintainer infrastructure adds
no public capability or publication approval.

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

The schema-2 reader preserves historical callback ABI 1 declarations, including
published `v0.19.0` metadata, and accepts integer ABI 2 only for upstream
compatibility `v0.15.0` or later with the required stream-chunk capability.
This compatibility reader does not qualify a new candidate: the owner's
new-manifest validator requires the version-correct declaration
([owner issue #107](https://github.com/leehack/litert-lm-native/issues/107)).
Reading either declaration does not replace live runtime probes: C API 1.0
still requires callback ABI 2 and independent allocation-failure ABI 1;
finish-reason ABI 1 and ASR bridge ABI 1 keep their separate contracts.
Corrected artifact verification and a pin update remain separate work.

Schema 2 optionally accepts `upstream.sourcePatches` as a non-empty list of
objects with exactly `id`, `path`, `sha256`, `source`, `preimageSha256Lf`,
`postimageSha256Lf` and `scope`. All fields are non-empty strings; the three
hashes must be lowercase 64-hex SHA-256 digests. The owner validates patch
contents and applicability; sync validates the declared provenance shape.

Schema-2 sync updates the runtime discovery table selected by the validated
upstream compatibility tag: `v0.19.0` and `v0.19.1` update the admitted C API
1.0 table; earlier versions update the legacy table. `v0.19.1` keeps C API
1.0.0 with the same exports, so it shares the `v0.19.0` mapping. Library,
macOS framework and native SwiftPM inventories stay separate, so repinning
cannot relax discovery of an explicit older runtime. Unknown newer
compatibility tags require a reviewed API mapping before generation. The sync
tests compile and execute both discovery paths after generation, including
missing-companion refusal.

For schema 2, Apple target selection follows the per-platform owner inventory.
Sync removes a formerly required iOS Gemma constraint-provider target from a
modern Swift manifest when the new iOS bundles no longer require it. An optional
provider XCFramework asset alone does not add an iOS dependency. The separate
macOS compatibility target and all required macOS provider/runtime files remain
in the generated inventories. Releases whose iOS bundles still require the
provider retain it; malformed or ambiguous Swift target layouts fail before
pin files are replaced. Updating the sync tool does not change the current pins
or publish a runtime.

The reviewed `v0.19.0` and `v0.19.1` owners link both TopK samplers from
source, so their Apple inventory no longer requires the prebuilt iOS `LiteRtTopKMetalSampler`
or macOS `LiteRtTopKWebGpuSampler`. Earlier core requirements for those 0.19
artifacts were stale. Sync removes both targets only from the known nine-target
layout after validating every canonical artifact and platform dependency, and
only when the owner bundles no longer require either library. The same checks
apply when refreshing an already converted seven-target manifest. It preserves the
Metal accelerator and other runtime targets. Versions 0.16 through 0.18 retain
their prebuilt sampler requirements. This removal does not apply to other
versions or layouts, which need a reviewed transition before pin files change.

v0.19 Apple `LiteRtLm` also links its GPU accelerator, so LiteRT never opens
the prebuilt Metal one, and owner releases after `v0.19.1-2` stop shipping it
([#1798](https://github.com/leehack/llamadart/issues/1798)). For v0.19 the
iOS bundles decide: sync keeps the `LiteRtMetalAccelerator` target while every
iOS bundle ships it, removes it from the seven-target layout once none does,
and refuses a release that ships it for only some iOS bundles.

Owner releases after `v0.19.1-3` also stop shipping the macOS `libLiteRt` and
WebGPU accelerator and the iOS loose `libLiteRt`, because `LiteRtLm` embeds
LiteRT ([#1911](https://github.com/leehack/llamadart/issues/1911)). Sync drops
the `LiteRt` and `LiteRtWebGpuAccelerator` targets (four binary targets
remain) once the manifest ships neither, refuses a release that drops only
one, and matches the targets by exact `name: "LiteRt"` because that is a
substring of other target names.

LiteRT-LM sync also stages the hook's accepted full-manifest template hash from
the same rendered `Package.swift`. The original manifest must already match the
hook's reviewed template; a stale hash or a hand-edited manifest fails before any
file is written. Dry-run prints the prospective hash. This keeps the known
v0.19 seven-target transition on the macOS app-bundle path without relaxing the
manifest contract or changing the currently pinned runtime.

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
`llvm-dev`, `libclang-dev` and `clang`). `ggml.h` pulls in libc's `FILE`, whose
name and layout differ on macOS. `ffigen.yaml` explicitly excludes Linux's
`_IO_FILE` from direct inclusion and makes pointer-only struct dependencies
opaque, preserving the committed `Pointer<FILE>` contract without exposing
libc internals. The unused libc dependency closure is excluded as well.
Directly included native structs and structs required by value
retain their fields. Do not normalize generated Dart by hand: regenerate with
the pinned SDK and lockfile, and inspect the entire diff for unrelated layout
changes. The tooling policy test exercises ffigen's actual configuration and
AST transformation without libclang; real header generation remains a separate
validation step.

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

## Speculative ABI preparation

The handwritten llama.cpp service uses `llama_dart_speculative_*` for MTP and
n-gram strategies. Native initialization enables the target outputs each
strategy consumes, so the service does not require the legacy
`llama_dart_speculative_need_embd` or `need_embd_nextn` queries. The native
`v0.8.0-3` header removes the unused `need_embd` query; generated
bindings and direct symbol tests follow that header. The genuine
`llama_dart_speculative_need_embd_nextn` export and its null-false check remain.

Direct, Windows wrapper code-asset, and dynamic-library resolution require the
remaining generic API. Direct and Windows probes call it only with null
handles; an incomplete API fails with `LlamaUnsupportedException` before
session creation or prompt decoding. Dynamic resolution requires every symbol
before returning an API. This checks available symbols, not struct-layout or
behavior compatibility: custom overrides still need the ABI-compatible runtime
described in [native build hooks](../platforms/native-build-hooks).

[Native #51](https://github.com/leehack/llamadart-native/issues/51) coordinates
retirement of the constant-false `need_embd` query. The published `v0.8.0-3`
wrapper rebuild retains upstream `v0.8.0` and the genuine `need_embd_nextn`
export. Owner publication readback permits mechanical adoption; it does not
qualify this core's ordinary default acquisition or whole distributed AOT.
Fresh macOS ARM64 and Windows x64 consumer/AOT evidence remains required
against the adopted source and published artifacts. This adds no manifest
version or runtime handshake.

The llama.cpp hook writer, Windows fallback scanner and Linux dependency-copy
reader all use the sibling `native_bundles_v2` cache. New default acquisitions
and compatible explicit tag/repository/local-archive acquisitions stay outside
legacy `native_bundles`, which older consumers scan in reused checkouts and
working-directory ancestors. Leave those old caches and immutable release
assets intact; never migrate or copy new bundles into them. There is no legacy
cache fallback in the new core. LiteRT-LM, stable-diffusion and model caches keep
their existing namespaces.

Published package versions already have distinct package roots and exact
release pins. Explicit incompatible overrides remain outside the documented
ABI- and symbol-compatible override contract. Older dynamic speculative lookup
can refuse missing queries with a typed error, while older Windows code-asset
factories probe only `free` and can fail at a late untyped query lookup. Cache
isolation protects automatic shared-checkout fallback; it does not retrofit
that factory or isolate arbitrary system-loader substitutions.

Before accepting the adoption, qualify old/new delivery and shared-root cache
isolation,
exact current-tag Apple checksum refusal, generic missing-symbol refusal, and
retained `need_embd_nextn` behavior against the final owner artifact. Keep
Windows host/AOT and packaged Apple evidence separate from host VM fixtures.

Run the model-free export-set checks with:

```sh
dart test -p vm test/unit/backends/llama_cpp/speculative_api_skew_test.dart
```

The tests exercise both the legacy and retired-query export sets, retaining
nextn in both, plus a missing required generic export through all three
resolution paths. Real-runtime
old/new controls, representative n-gram/MTP/DFlash generation, and packaged
platform qualification remain required for the coordinated ABI release.

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

LiteRT-LM 0.19 changes C function signatures to status returns and output
parameters. The public lazy facade, service metadata/finish probes and speech
worker share discovery and ABI selection. `_liteRtLmV1ProductionSelection` in
`litert_lm_runtime_facade.dart` enables public C API 1.0.x dispatch. The native
hook and Apple companion source now pin published
[v0.19.1-4](https://github.com/leehack/litert-lm-native/releases/tag/v0.19.1-4),
owner `5da99205` / upstream `7a03724c`, which keeps C API 1.0.0 and the
`v0.19.0` exports and adds the in-process LiteRT marker
`litert_lm_native_in_process_litert_abi_version` (1 on every platform); the
`LiteRT-LM Smoke` library step fails when the bundled Linux x64 or Windows
x64 runtime lacks the export or does not report 1, and prints the value as
`inProcessLiteRtAbi`; Linux arm64 has no CI runner for it. Rolling the pin back
to a pre-marker tag (`v0.18.1-4`, `v0.19.0`, `v0.19.1`, `v0.19.1-1`) therefore
fails the smoke on Linux and Windows by design. The
earlier `-1` rebuild links LiteRT into the Linux and Windows
`libLiteRtLm` ([litert-lm-native#112](https://github.com/leehack/litert-lm-native/pull/112));
its Apple and Android binaries are identical to `v0.19.1`. Upstream
`v0.19.1`'s only runtime change makes the main executor default
`max_num_images` to 4 when unset; the v1 client never sets it, and every macOS
arm64 LiteRT-LM consumer scenario, including a multi-image probe, matched
`v0.19.0` output. `v0.19.0` (owner `f173fe9b` / upstream `83ce6067`) was
adopted after independent readback matched all 21 public assets to qualified
bytes; GitHub reports `immutable: false` for both, so this is verified snapshot
evidence, not enforced immutability. Public selection retains legacy
overrides when the version marker is absent; a present marker must report C API
1.0.x. Failed, malformed and future versions never retry legacy arities, and
optional capabilities still require their complete export/probe groups. The
selected path checks macOS 14+ before core or companion discovery, including
legacy libraries and explicit paths. A caller-opened library cannot retroactively
prevent dlopen, so the direct v1 adapter also checks the floor before native
operations. Replacing the native pin or generated embedding bindings alone is
unsafe. Preserve tested legacy compatibility and complete affected default
consumers, SwiftPM/Apple embedding/signature checks and exact-head CI/audit before
merge or release. Source pin adoption does not publish core or Apple packages.

Worker request completion and native settlement are separate. An errored v1
turn is safe to release only after its actual final callback and successful
`litert_lm_conversation_wait_until_done`. Cancellation status failures do not
settle callbacks. A failed drain, missing final, worker timeout or failed native
cleanup retains the worker, callback, engine family, model link and cache lease;
queued work fails and that backend requires a process restart. Retention is
bounded to the failed backend; disposal never reports successful cleanup in this
state. Do not kill the retained isolate or release its lease to make teardown
appear complete.

Free and dispose time out only until the worker starts native teardown: a free
waits for earlier queued requests, a dispose for the in-flight request and its
callbacks to settle. Once teardown starts, the backend waits for it without a
bound, as the llama.cpp backend does, so a stalled GPU or NPU engine delete
blocks unload and dispose. On Linux ext4, releasing a freshly written CPU
XNNPACK weight cache flushes it to disk, about 4 s for Qwen3 0.6B's 600 MB
cache on CI disks ([#1814](https://github.com/leehack/llamadart/issues/1814)).

Public ABI-aware selection and the v0.19.1-4 source pin are enabled; remaining
consumer, feature and platform gates are recorded in
`doc/litert_lm_v1_adoption.md`. This transport contract alone does not qualify a
model or device. The owner proxy's
callback ABI 2 and finish-reason ABI 1 alone do not establish lossless callback
delivery under allocation failure. Owner
[issue #97](https://github.com/leehack/litert-lm-native/issues/97) defines the
separate allocation-failure status contract. The internal conversation adapter
requires both status exports and exactly allocation-failure ABI 1 before child
or proxy allocation. After the actual final callback and successful drain, it
reads the sticky status while the proxy is alive. Copy loss rejects the turn
with its actual native finish reason, discards the child, and leaves the parent
settled for a fresh child. Even native cancellation cannot normalize copy loss
into success. Failed drain retains the entire native family without reading the
status or freeing the proxy.

### Historical v1 adapter preparation

The following snapshots describe earlier internal slices, when public routing
and several feature families were still pending. They are retained for ABI and
ownership context, not as the current capability list. Public direct calls,
default services and speech now share ABI-aware selection; current coverage and
remaining artifact/model/platform gates are in `doc/litert_lm_v1_adoption.md`.
At that stage, owner pins and companion assets were unchanged pending qualified
adoption.

The [owner PR #98](https://github.com/leehack/litert-lm-native/pull/98) snapshot
was fixture-backed consumer preparation, not adoption of a published owner
artifact. Owner source/release qualification and ASR, media, tools, schema and
embedding migration were still public adoption gates. The ASR bridge already
had its own versioned ABI, but the Dart loader at that stage still passed
through the legacy C API refusal. The current speech worker uses the shared
ABI-aware facade and independently checks the ASR bridge version, layout and
complete exports; the historical refusal is not its current capability status.

Internal v1 `loadConfigured` transports resolved engine options through the
status-returning API. Its typed settings use the existing compute-device and
activation enums. CPU/GPU/NPU strings and optional vision/audio executor strings
are passed unchanged, with no automatic device selection or fallback. This is
ABI preparation, not device or media qualification. The service still owns
platform defaults, ModelParams validation, thread-zero normalization, cache
leases/pruning and retry policy; none is selected by this adapter.

The configuration defaults to context 4096, benchmark metrics enabled, and
speculation off, as the maintained service does. Nullable threads, prefill
chunks, cache/dispatch paths, activation and parallel loading remain unset in
native settings. The older `load` helper retains its four explicit CPU threads
and required cache path. Benchmark prefill counts are separate from response
limits; no benchmark decode-step override or single-threaded execution is set.
Speculation uses the new owned v1 config and its copied engine setting, with
status checks and cleanup on every failure.

Explicit CPU thread/prefill-chunk requests on another main backend are refused:
the native setters otherwise report success without applying them. Dispatch
paths require NPU, and NPU speculation is refused. Explicit `maxNumImages` is
also refused: the v1 header documents it as legacy-engine-only, with no current
consumer capability proof for the active engine implementation. This remains a
required migration gap, needing supported-engine proof or an explicit release
scope decision. Auxiliary backend strings alone do not enable media input.
Logging/status and complete worker/service dispatch remain separate migration
work; the following internal slices do not select v1 publicly.

Internal `openConfiguredConversation` adds snapshotted text/tool prefaces and
explicit TOP_P sampler settings. The convenience `openConversation` retains its
32-token, zero-temperature, top-k 1, top-p 0.95, seed 0 preparation defaults.
Zero temperature uses the shared top-k normalization; nonzero sampling preserves
requested top-k and signed int32 seed. Sampler floats reject non-finite values,
overflow and positive underflow to native zero. Null sampler inherits the native
configuration, including on NPU; explicit NPU overrides are refused. The selected
backend is recorded only after successful engine replacement.

System content is plain text encoded exactly once, even when it looks like JSON.
Initial message and tool arrays, context objects and raw Jinja overrides are
validated and snapshotted before native allocation: upstream preface setters
copy strings but creation can log malformed containers and continue without them.
The supported preparation subset has system/user/assistant/tool roles; string or
text-part content; assistant reasoning text and function calls with string/object
arguments; named tool-response parts with JSON values; and function descriptors
with object parameter schemas. Media, unknown message/tool fields, strict-tool
requests, boolean/tuple schema items and empty/NUL raw templates are refused.
This checks descriptor structure, not full JSON Schema semantics or enforcement.
All setters use v1 status signatures and owned temporaries are released on failure.
Constrained decoding stays explicitly disabled. Active structured messages,
required/parallel tool choice, LoRA, thinking budgets, broader per-turn controls and
schema providers still need separate migration; raw chunk delivery does not
claim tool execution or template/model qualification.

Internal `sendText` accepts nullable per-turn output limits and repetition/presence
penalties. Omitted or empty settings keep null native optional arguments: there
is no implicit default penalty. The total output cap includes thinking tokens;
penalties count only the current send's generated tokens. Explicit penalties
with speculative decoding are refused, preserving the service's unqualified
combination restriction. Each send copies its options into native decode state,
then frees owned option/config temporaries after the start call returns. This
does not settle callbacks: failed drain still retains their native family.

Requested thinking budgets are explicitly refused until model/channel admission
exists. Upstream can report successful setters and then ignore a budget without
thinking end tokens. Sampler and seed remain conversation-scoped; adapting public
per-request sampling still requires conversation recreation or another proven
native contract. Structured active messages, media, per-turn template context,
schema constraints and additional penalty controls remain separate work. This
preparation changes no public routing, capability or runtime pin.

Internal v1 tokenization and detokenization now use status/out signatures and
`size_t` counts. `addSpecial: false` skips BOS lookup; the default prepends the
configured ID sequence or separately tokenizes its string, preserving the legacy
client's ordering. A missing or empty BOS adds nothing. Borrowed arrays and UTF-8
strings are copied before their result/union owner is deleted, including when
BOS text requires a second tokenizer call. Empty detokenization returns `''`
without a native call, after checking the engine lifetime.

The whole tokenizer symbol group is checked before nonempty/native operations;
legacy/version-skew libraries remain refused by the adapter's existing version
admission. Failed statuses copy the calling thread's diagnostic before cleanup.
Invalid native union types, null nonempty arrays/strings, and counts exceeding
the adapter's signed 32-bit safety bound are refused. NUL text and out-of-C-int
input IDs reject instead of being truncated. An idle conversation may stay open;
pending or quarantined native work prohibits tokenizer access. These are internal
migration controls, not model-tokenizer qualification or public v1 selection.
Embeddings and complete service dispatch remain gaps.

Internal `bundleCapabilities` reads text/vision/audio/video, speculation, thinking
and function-calling declarations through `model_info.h` status/out APIs. Each
query owns a loaded-file handle and frees it after copying the flags. Missing
metadata exports, failed statuses and success without a handle are refused.
These flags describe a file; they do not qualify an executor, enable media or
admit thinking budgets. `supports_thinking` reads only the model-info boolean,
whereas native budget enforcement needs channel end tokens that this C metadata
API does not expose. The existing budget refusal remains even for a true flag.

Settled internal conversations can render the already validated text/tool message
subset and copy its conversation-owned UTF-8 buffer before another render.
Their benchmark snapshots are owned and deleted after every read or failure.
Metrics preserve legacy aggregation: sum all prefill/decode token counts, use
the last throughput in each phase, retain native zero timings and use null
throughput for empty histories. Counts and indices use `size_t`; every getter
status is checked before cleanup can replace its thread-local error. Invalid
metrics, signed token-total overflow, null successful results and histories over
one million turns are refused instead of truncated. Pending or quarantined
native work prohibits metadata, render and benchmark calls. These remain
fixture-backed ABI/lifetime controls without model or device qualification.

At that stage, the internal v1 client could be explicitly injected through
`LiteRtLmService` for text/tool chat, response assembly, metrics and lifetime
checks. That slice left the public client and Web stub unchanged and did not
select v1 publicly. Current public selection and the remaining feature-family
and consumer gates are tracked in `doc/litert_lm_v1_adoption.md`.

### Current v1 discovery

C API 1.0 discovery accepts the owner's sampler-free 0.19 desktop
inventory only after probing the selected primary library's supported C API.
An absent marker still requires every legacy TopK companion. Common companions
load before that probe; legacy-only samplers load after admission. macOS flat,
versioned-framework and native-SPM layouts follow the same rule. A staged
concrete directory keeps its own primary handle rather than falling back to the
process image; iOS wrapper/process discovery is unchanged. From `v0.19.1-1`,
`sync_native_release_pins.py` leaves the Linux and Windows prebuilt
`libLiteRt` out of the required inventory: those hosts link LiteRT in
([litert-lm-native#112](https://github.com/leehack/litert-lm-native/pull/112)),
so the hook neither ships nor opens it. Syncing an earlier release keeps it.
An explicit `LLAMADART_LITERT_LM_LIB_DIR` opens it before the primary
library whenever the directory holds it, because older hosts (`v0.18.x`,
`v0.19.0`, `v0.19.1`) import it and Windows does not search a DLL's own
directory for imports; legacy inventories also still require it.

`LLAMADART_LITERT_LM_LIB_DIR` takes precedence over packaged and cached desktop
runtimes. An incomplete directory or an unloadable explicit library now fails
with a typed unsupported error instead of substituting another runtime. These
controls preserve public ABI-aware selection and do not change pinned artifacts.

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

Core `0.19.1` preparation moves LiteRT-LM to `v0.19.1-2`, which adds the
in-process LiteRT marker, and pairs all three Apple companions at `0.19.1`
with a Flutter floor of `>=3.38.6`. `llamadart_litert_lm_flutter` `0.19.1`
requires `llamadart: '>=0.19.1 <0.20.0'`: core `0.19.0` treats a companion
pinning `v0.19.1-2` as a later build and keeps macOS LiteRT-LM in the hook
cache. Core `0.19.1` accepts the published `0.19.0` companion (pinning
`v0.19.1-1`) with an upgrade warning. The llama.cpp and SD companions keep
`llamadart: '>=0.19.0 <0.20.0'`; their pins are unchanged, so core `0.19.0`
still accepts them.

After core `0.18.0`, the LiteRT-LM pin moved to `v0.19.1-1`. It ships in core
`0.19.0`, which re-releases all three Apple companions at `0.19.0` with
`llamadart: '>=0.19.0 <0.20.0'`; the LiteRT-LM companion pins `v0.19.1-1`. Pub
cannot resolve a `0.19.x` core beside a `0.18.x` companion, so no mixed pair
exists. A `0.18.x` patch from `main` would accept only `v0.19.1-1`, while the
published `0.18.0` companion it resolves beside pins `v0.19.0`; release prep
rejects that pair, so `main` can no longer ship a `0.18.x` patch.

The llama.cpp pin moved to `v0.9.0` in the same cycle, and the llama.cpp
companion `0.19.0` pins it. No older Apple llama.cpp runtime is admitted:
earlier frameworks lack the ARM F16 accumulation fix
([llamadart-native#174](https://github.com/leehack/llamadart-native/issues/174)).
Web runs it too through the pinned bridge assets.

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

Historically, core `0.17.1` moved the llama.cpp pin to `v0.8.0-1`, built from upstream `v0.8.0`, inside
the `0.17` minor. It kept companion `0.17.0` (`v0.7.0-3`) through
`llamaCppCompatibleAppleCompanionTags` because that core called no symbol that
framework lacked; `test/fixtures/native/llama_cpp_apple_compatibility.json` records
the historical per-slice check. The
reverse pair is unsafe (`mtmd_helper_init_opt` grows to 32 bytes), so companion
`0.17.1` needs `llamadart: '>=0.17.1 <0.18.0'`.

The 0.18.0 preparation moves to `v0.8.0-3` and requires its matching Apple
companion. Older runtimes are no longer admitted: they lack the speculative
rollback and model-creation ownership fixes. All three Apple companions are
prepared at `0.18.0`, constrained to
`llamadart: ">=0.18.0 <0.19.0"`, with SwiftPM pins `v0.8.0-3`, `v0.19.0`
and `v0.3.0-3`. Package publication still requires explicit release approval.

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
