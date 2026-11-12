# Lightweight cross-platform validation plan

> Model-priority update: Gemma 4 E2B and Qwen3.5 0.8B are the primary
> chat families; STT and TTS remain required dedicated-model exceptions.
> `dart run tool/testing/validation.dart coverage` exposes explicit planned
> platform/backend/use-case rows, including Gemma 4 Tensor G5, SM8750 and
> the SM8650 compatibility gap. Older Gemma 3 NPU profiles below remain
> legacy controls, not Gemma 4 qualification. See
> [the coverage catalog guide](cross_platform_validation.md#planned-platformbackend-coverage)
> and [tracker #514](https://github.com/leehack/llamadart/issues/514) for the
> current priorities and required speech acceptance cases.


Status: **initial quick-core harness implemented; broader qualification remains planned**
(2026-09-17). The maintainer authorized implementation after the earlier deferral.
The implementation starts from current merged main and preserves its runtime pins;
the separate release task still owns pending runtime changes. See the
[implementation runbook](cross_platform_validation.md) for available commands,
actual bundles, verified behavior and remaining qualification work. Pilot
observations below are dated 2026-09-16; the device catalog and maintained-harness
pilot were refreshed on 2026-09-17. The runbook records the newer outcomes.
Proposed later coverage is not an assertion that those rows now pass.

The objective is a small, repeatable test of the **public llamadart package**,
including native-library packaging, model routing and application lifecycle.
Use free CI and the Mac for routine checks, and **Firebase as the primary
physical Android/iOS test route**. The personal Pixel and iPad are optional
debugging devices, never prerequisites for mobile qualification. Include
Qualcomm and Tensor LiteRT-LM NPU qualification in the next milestone. Keep the
operating budget at **$0 out of pocket**, even after promotional GCP credit expires.
The maintainer upgraded the isolated QA project to Blaze on 2026-09-17.
Execution remains conditional on verified remaining free minutes, verified
Test Lab credit coverage or a separate explicit out-of-pocket authorization; the free rotation remains the
sustainable default. See the runbook's [Blaze controls](cross_platform_validation.md#explicit-blaze-runs).

## 1. Deliverables and boundaries

One private shared Dart suite supplies cases, model manifests, assertions and
reporting. A small desktop CLI and thin Flutter test app invoke that suite.
The Flutter app supports local interactive runs and unattended integration tests;
Android instrumentation and iOS XCTest wrap the same cases for Firebase.
The app shows selected model/backend, progress, cancellation, result and export.

CI produces versioned QA bundles with checksums and provenance: desktop CLI
bundles including native code assets, Android app/test APKs, iOS build inputs,
and a deployable Web bundle with its pinned runtime assets. Build each native
target on a supported host/toolchain; do not assume one host cross-compiles all
targets. Initially build/sign physical-iOS XCTest bundles on the owned Mac;
do not add signing credentials to CI as part of this plan.

Register maintained scenarios in `tool/testing/run_local_e2e.dart` and
`tool/testing/test_matrix.dart`; classify any new example/companion with
`tool/prepare_workspace.dart`. Reuse the existing feature smokes and benchmark
helpers. Do not create a parallel collection of unregistered repro scripts.
Tests call public APIs; direct native/upstream calls are **diagnostic controls**
and cannot substitute for a passing public-package case.

Use three selections from one case catalog; do not maintain three suites:

| Selection | Contents | When |
| --- | --- | --- |
| Quick core | Packaging, Unicode, raw/chat stream, history, cancellation/recovery, one reload, token limit and one timing series per representative model/backend | First device qualification and relevant runtime changes; inference target under five minutes, to be measured |
| Change-focused | Quick core plus the thinking/tools/stop/batching or feature-pack cases affected by the change | Relevant PRs; run expensive positive cases on selected devices, cheap negative contracts in CI |
| Release selection | All applicable C01–C12 subcases, affected-family packs and required platform/packaging rows | Release/native-pin qualification; schedule across quota days |

Keep the existing case IDs, expected results and release coverage when reducing
a quick run. Report omitted cases as NOT_RUN with the selection reason. Large
multimodal/speech downloads remain feature packs. The Firebase four-device core
rotation is a useful subset of release evidence, not the full release selection.

The first implementation milestone is deliberately small: manifests, shared
cases, existing CLI/mobile/Web adapters, reliable result capture and a basic
offline report. Reuse the chat app for Flutter/Apple companion packaging checks;
do not require new desktop Flutter UIs in addition to CLI bundles. Advanced
trend charts and model conversion remain later milestones. The next milestone
adds Firebase mobile qualification and NPU packaging/evidence; the current
CPU/GPU harness remains usable while those additions are implemented.

### Proposed repository layout

Keep the suite in the **llamadart repository**, next to the package it validates.
Use one private Dart package named `llamadart_validation`. The package, adapters,
commands and workflow below now exist. The nested `cases/`, `manifest/` and
`results/` directories remain a possible organization as the catalog grows;
the initial implementation keeps these responsibilities in small `lib/src/` files:

```text
packages/llamadart_validation/
  pubspec.yaml                     # publish_to: none; depends on local llamadart
  lib/llamadart_validation.dart     # shared runner and result contract
  lib/src/cases/                    # C01-C12 and optional feature packs
  lib/src/manifest/                 # model/profile validation and selection
  lib/src/results/                  # events, assertions and metric definitions
  assets/                          # pinned manifests, prompts, small media fixtures
  schemas/                         # manifest, event and result JSON schemas
  bin/run.dart                     # desktop CLI; native host adapter
  bin/report.dart                  # single host-side JSON/JUnit/CSV/HTML exporter
  test/                            # fast tests of selection, assertions and reports

example/chat_app/
  lib/validation_main.dart          # dedicated interactive QA entry point
  lib/validation/                   # thin Flutter/device/browser adapters
  integration_test/validation_test.dart  # unattended entry point, same suite
  test_driver/integration_test.dart # reuse existing integration-test driver
  android/                         # app/test APK instrumentation wiring
  ios/                             # physical-device XCTest wiring

tool/testing/validation.dart        # build/plan/run/status/collect/cleanup CLI
tool/testing/validation/            # GCE/Firebase adapters and VM bootstrap inputs
.github/workflows/validation_bundles.yml  # host-specific QA builds and artifacts
doc/cross_platform_validation_plan.md   # scope, matrix and reporting contract
```

The shared `lib/` stays usable from Dart and Flutter Web: platform adapters
provide model/fixture access, storage and device diagnostics. Keep filesystem,
process and Flutter imports in their host adapters. The desktop CLI and Flutter
entry points depend on the shared package, which calls the public `llamadart`
API; the core package has no dependency on the suite. Do not add QA exports to
`lib/llamadart.dart` or QA commands to the user-facing CLI example.

Prompts, model hashes, inference profiles and small licensed fixtures have one
checked-in source under `assets/`. Bundle preparation stages the selected inputs
for desktop, Flutter and Web; adapters resolve them through the same manifest
IDs without assuming a checkout or working directory. Model weights remain
outside Git. Use `.dart_tool/validation/model-cache/<sha256>/` for the local
cache, `.dart_tool/validation/bundles/<build-id>/` for build outputs and
`.dart_tool/validation/runs/<run-id>/` for collected events, logs and reports.
Device adapters write to their sandbox and export into that run directory;
browser adapters provide download/export. These generated paths stay ignored.

Register the private package in `tool/prepare_workspace.dart` and give it
explicit analyze/test coverage, since root analysis currently excludes
`packages/**`. Register orchestration selections in the existing E2E runner and
testing matrix. Keep existing core unit/integration/E2E tests in place; migrate
overlapping smoke logic incrementally once the shared cases preserve its checks.
Extend the current Web build script to accept the QA entry point while retaining
its runtime-asset staging and validation. The bundle workflow builds artifacts;
Firebase submission remains an explicit invocation with the quota preflight.

Native runtime/build fixes remain in their owning sibling repositories; this
package owns public-Dart validation and its adapters. The earlier Firebase
pilot under `.dart_tool/firebase_pilot/20260916/` remains historical evidence,
not the maintained suite location.

### Where to get the built apps

The download location after publication and a successful workflow run will be
**llamadart → GitHub Actions → Validation Bundles → selected run → Artifacts**.
The local `.github/workflows/validation_bundles.yml` implementation names desktop
artifacts `validation-desktop-<runner-os>-<runner-arch>-<commit>` and app artifacts
`validation-<target>-<commit>`. The bundle manifest records the locked profile.
Draft [PR #515](https://github.com/leehack/llamadart/pull/515) publishes this
workflow and runs the tiny CPU build on relevant PR changes. Desktop jobs also
extract the archive into a temporary directory and verify command startup/profile
discovery there without inference. Use a successful run's artifact inventory;
do not infer hosted availability from a local build.

| Target | Download / runnable output |
| --- | --- |
| Android arm64 | Installable QA APK and its matching instrumentation test APK for unattended/Firebase runs |
| Windows x64/arm64, when buildable | CLI bundle containing `llamadart-validate.exe`, required native libraries and run instructions |
| Linux x64/arm64, when buildable | CLI bundle containing `llamadart-validate`, required native libraries and run instructions |
| macOS arm64/x64, when buildable | CLI bundle containing `llamadart-validate`, required native libraries and run instructions |
| Web | Deployable QA site bundle with pinned runtime assets; serve it with the required headers |
| iOS/iPadOS | CI build inputs initially; build/sign the physical-device app and XCTest bundle on the owned Mac |

Local builds stage the same outputs under
`.dart_tool/validation/bundles/<build-id>/<target>/<profile>/`. Each bundle
includes its manifest, checksums, selected small fixtures and model-fetch/run
instructions; model weights are separate. Keep CI artifacts on bounded retention
and regenerate from the recorded revision and pinned inputs when needed. No
separate download server or automatic GitHub Release publication is required.

The interactive app source stays in `example/chat_app/`, using the dedicated
`lib/validation_main.dart` build target. Desktop v1 is the CLI from
`packages/llamadart_validation/bin/run.dart`. Produce target-specific builds on
supported toolchains; a successful build remains separate from running and
qualifying it on actual hardware.

## 2. Pilot findings and tracked work

Pilot source was main `a5df1c4fcbb1766d26efb5b1d9becda191df89a3`, Flutter
3.47.1 / Dart 3.13.1, llama.cpp artifact `v0.4.0`, LiteRT-LM `v0.17.0-3`.
It ran actual Flutter/llamadart code on physical devices, not a model-only service.

| Path | Galaxy S24 SC-51E, API 36, Debug | iPhone 16 Pro, actual iOS 18.3.2, Release |
| --- | --- | --- |
| GGUF CPU | App records passed before a later GPU crash; overall execution failed | Passed |
| GGUF GPU | Vulkan SIGSEGV during compute-pipeline compilation | Metal passed |
| LiteRT CPU | Answer `2` instead of `4` | Answer `2` instead of `4` |
| LiteRT GPU | Incoherent mixed-language output; native WebGPU/Vulkan adapter identified | Answer `2` instead of `4`; Metal identified |

Track the distinct findings:

- [llamadart-native #79](https://github.com/leehack/llamadart-native/issues/79):
  Galaxy S24 GGUF Vulkan crash. The vendor compiler appears in the stack;
  originating driver/runtime/artifact/integration ownership remains unproven.
- [llamadart #509](https://github.com/leehack/llamadart/issues/509): shared
  LiteRT Qwen3 arithmetic failure. The original `Qwen/Qwen3-0.6B` weights also
  answer `2` with thinking disabled, so this is model behavior; `chat-litert`
  now uses the reference-qualified C04 fixture below.
- [litert-lm-native #51](https://github.com/leehack/litert-lm-native/issues/51):
  Android GPU output divergence. OpenCL was unavailable, then WebGPU selected an
  Adreno 750 Vulkan adapter. The fallback is evidence, not an established cause.

Existing [native tokenizer #48](https://github.com/leehack/litert-lm-native/issues/48),
[desktop empty-chat #505](https://github.com/leehack/llamadart/issues/505),
[desktop LiteRT GPU #506](https://github.com/leehack/llamadart/issues/506),
[Windows CUDA helper #504](https://github.com/leehack/llamadart/issues/504), and
[older Android CPU qualification #476](https://github.com/leehack/llamadart/issues/476)
remain separate unless investigation establishes a common cause.

An initial pilot-wrapper mistake set LiteRT `numberOfThreadsBatch=4`; the corrected
runs used zero. Those initial typed rejections are **not runtime bugs**.
The pilot collected no LiteRT TPS because its arithmetic assertion ran before
timing. Android Debug and iOS Release results are not a performance comparison.
These are historical observations on the named commit/artifacts. The three pilot
issues were still open when checked on 2026-09-17; neither an issue's state nor
a different commit's passing result establishes the current candidate's outcome.

## 3. Platform and backend coverage

The [support matrix](../website/docs/platforms/support-matrix.md) and capability
probes remain authoritative. The table below is a test selection plan, not a
promise that every backend/model combination works. Reconcile it with the
active merged pins before qualification. A published library, successful build,
or selectable backend is not inference qualification.

| Target | GGUF profiles | LiteRT profiles | Where / coverage limit |
| --- | --- | --- | --- |
| Android arm64 physical | CPU, Vulkan; OpenCL in targeted pack | CPU, GPU; Qualcomm/Tensor NPU with matched model/dispatch libraries | Firebase device rotation; personal Pixel optional |
| Android arm64 virtual | CPU, install/load, 4K/16K page-size packaging | CPU where artifact supports it; explicit unsupported cases | Free Firebase virtual quota; no physical GPU/ISA qualification |
| Android x64 emulator | CPU; Vulkan and OpenCL targeted if actually exposed | CPU, GPU only with backend proof | Local/free CI emulator; unavailable GPU profiles remain NOT_RUN; current Firebase virtual catalog is arm64 |
| iOS arm64 physical | CPU, Metal | CPU, GPU; no Apple NPU backend | Firebase iPhones and iPad 10; personal iPad optional |
| iOS arm64 simulator | CPU, available Metal path separately labelled simulator | CPU, available GPU path separately labelled simulator | Owned Mac; does not qualify physical-device drivers or memory |
| iOS x86_64 simulator | CPU / available Metal | Negative packaging contract: no LiteRT artifact | Intel host if available, otherwise NOT_RUN |
| macOS arm64 | CPU, Metal | CPU, GPU | Owned Mac if matching architecture; record actual hardware |
| macOS x64 | CPU, available Metal | Negative contract: no LiteRT-LM artifact in `0.18.1` ([litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)); loads throw `LlamaUnsupportedException` | Available free runner or Intel host; GPU gaps explicit |
| Linux x64 | CPU; CUDA, Vulkan, HIP/BLAS targeted | CPU; explicit GPU through Vulkan with `0.17.0-5` | Free CI CPU; GPU requires a compatible driver and suite execution proof |
| Linux arm64 | CPU; Vulkan/BLAS targeted | CPU | Available arm64 runner/hardware; no x64 emulation as arm64 proof |
| Windows x64 | CPU; CUDA, Vulkan/BLAS targeted | CPU; explicit GPU through D3D12 with `0.17.0-5` | Free CI CPU, accessible Windows hardware; GGUF CUDA requires actual NVIDIA GPU |
| Windows arm64 | CPU, Vulkan/BLAS where available | Negative artifact contract unless support is added | Hook/build coverage plus explicit runtime gap without hardware |
| Web, Chrome | WASM CPU and WebGPU separately | Browser CPU/GPU with Web-compatible model | CI WASM; Mac real browser GPU; mobile browser coverage separate |
| Web, Safari/iPadOS | WASM and WebGPU when exposed | Browser runtime capability-dependent | Mac Safari; iPadOS browser lane remains NOT_RUN until a browser adapter or optional device run qualifies it; Firebase native XCTest is not browser evidence |
| Web, Firefox | WASM plus explicit capability checks | Only what active browser runtime exposes | Compatibility lane; unavailable WebGPU is not a GPU pass |

Quick core applies to each selected supported runtime row. Release selection
accounts for the full supported matrix; unavailable hardware remains an explicit
gap. Feature positives require a compatible fixture and runtime. Exhaustive
option/unsupported guards run in cheap unit/integration lanes; device profiles
retain backend probes and one error/recovery check, expanding when those paths
change. Unexpected unsupported behavior in a promised supported row is a failure.

Backend evidence must include requested selector, effective backend name,
loaded native modules, actual adapter/driver and offload/delegate diagnostics.
An echoed `gpuLayers=999`, `availableBackends` list, or GPU preference is
insufficient. An automatic CPU fallback can pass an **auto** policy case but
cannot pass the explicit GPU row. Missing proof leaves GPU qualification
incomplete.

## 4. Models and immutable manifests

Do not multiply every model by every device. Run representative core models on
the device rotation; exercise affected model families and feature packs on
selected capable Firebase devices or desktop hosts. A custom manifest can add a
user's model without silently replacing a failing standard fixture.

| Model ID | Proposed artifact | Purpose / scheduling |
| --- | --- | --- |
| `tiny-gguf` | stories15M.gguf, 98.36 MB | Packaging, raw stream, backend/lifecycle; not an instruction-quality oracle |
| `chat-gguf` | Qwen3.5-0.8B Q4_K_M GGUF | Representative chat/thinking/tools; qualify template and semantic fixtures first |
| `dense-state` | Qwen2.5-0.5B Q4_K_M GGUF | Dense context/state/prompt-reuse checks, targeted pack |
| `chat-litert` | Qwen3-0.6B.litertlm, 614.24 MB | Native LiteRT core plus retained arithmetic/tokenizer diagnostics |
| `npu-qualcomm-sm8650` | Gemma 3 1B IT, Qualcomm SM8650-specific LiteRT bundle, 4-bit per-channel, about 658 MB | Next-milestone S24 NPU qualification; separate artifact from CPU/GPU models |
| `npu-tensor-g5` | Gemma 3 1B IT, Tensor G5-specific LiteRT bundle, 8-bit per-channel, about 1.7 GB | Next-milestone Pixel 10 NPU qualification; separate vendor runtime and artifact |
| `tools-litert` | FunctionGemma 270M compatible LiteRT bundle | Optional native tool fixtures; verify actual template/tool support first |
| `gemma-gguf` | Gemma 4 E2B GGUF + matching projector, about 4 GB total | Vision/audio/thinking/tools and large-memory coverage |
| `gemma-litert-native` | Native Gemma 4 E2B LiteRT bundle, about 2.6 GB | Native multimodal pack |
| `gemma-litert-web` | Web-compatible Gemma 4 bundle, about 2 GB | LiteRT Web single-turn lane; never substitute the native bundle |
| `embedding` | EmbeddingGemma 300M Q8 GGUF, about 334 MB | Embeddings and batch consistency |
| `asr-gguf` | Qwen3-ASR GGUF + matching projector, about 1 GB | File transcription; Web WAV, MP3 or FLAC bytes where supported |
| `asr-litert` | Moonshine tiny INT8 + tokenizer, about 54 MB | Native CPU streaming ASR |
| `tts-gguf` | Qwen3-TTS GGUF + matching projector, about 1.5 GB | Experimental typed synthesis and playback/export |

The pilot fixtures below and the checked-in quick/NPU profiles have immutable
model locks. S24 NPU execution is observed but history qualification fails;
Tensor NPU remains unexecuted. Other artifacts/sizes
are **selection candidates**, not locked or reference-qualified inputs.
Before a row is executable, resolve
the exact repository revision, filename, byte size, SHA256, format, quantization,
tokenizer/template identity, license/access requirements, companion hashes,
supported feature flags and measured memory envelope. Reject a manifest with
missing hashes or floating revisions. Do not download gated assets without access.

Pinned pilot fixtures:

| ID | Repository / revision / filename | SHA256 |
| --- | --- | --- |
| tiny-gguf | `ggml-org/tiny-llamas` / `99dd1a73db5a37100bd4ae633f4cfce6560e1567` / `stories15M.gguf` | `61b50d457809a5194818fd22e6724b456cd7bb9a6264c52c8110684c53f3704a` |
| chat-litert | `litert-community/Qwen3-0.6B` / `8414150f2e9dcc82449bcc9c5abc404b399a4d06` / `Qwen3-0.6B.litertlm` | `555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4` |

Hash downloaded files before load; record cache hit/miss and bytes. Download and
checksum time are separate from inference. Do not assume Firebase preserves app
model caches between executions. Large packs must pass disk/memory preflight and
are excluded from older/constrained-device core unless explicitly qualified.
Within one execution, prepare/hash each immutable model once, then reuse that
verified file for its cases. Load one model at a time; retain it across independent
requests, reset conversation/cache state, and reload only for explicit lifecycle
cases. Hash checks and downloads never run inside timing windows. Start with
tiny-gguf plus chat-gguf for GGUF profiles, and chat-litert for LiteRT profiles;
the full model inventory is not an automatic download list.

## 5. Case catalog and expected results

All cases record expectation, actual output, assertion result and capability
decision before reporting aggregate status. Evaluate independent assertions
without throwing away earlier evidence. Cases below are shared specifications;
the model manifest determines supported positive rows and typed negative rows.

| ID | Input / action | Expected result and scope |
| --- | --- | --- |
| C01 packaging, routing and load | Verify binary/model hashes; load by `.gguf` or `.litertlm`; probe capabilities | Correct runtime family, ready state and effective backend evidence; missing library/corrupt model produces actionable error. Native/Web assets distinguished. |
| C02 tokenizer and Unicode | Encode/decode `Hello, Montréal! 안녕하세요 👋\n  two spaces`; plain-text mode with explicit BOS/special-token policy | Exact round trip where advertised, stable IDs for the pinned tokenizer; capture literal byte-level spellings. LiteRT Web asserts typed unsupported tokenizer path. |
| C03 raw stream | Tiny GGUF: `Once upon a time`, max 32; native chat-capable models use their locked raw fixture | One nonempty valid, finite ordered stream with no crash/hang. Benchmark repetitions are scheduled once separately, not repeated for every case. A stories model need not answer instructions. |
| C04 visible chat and thinking control | `Reply with one short sentence saying hello.` and `What is 2+2? Answer only with the number.`; thinking disabled | Greeting contains `hello` case-insensitively; arithmetic trimmed matches `^4[.!]?$`; no hidden-thinking leakage. `chat-litert` asks `What is 3 + 4? Reply with only the number.` and matches `^(?:3 \+ 4 = )?7[.!]?$`: original Qwen3-0.6B answers `2` to 2 + 2 with thinking disabled ([#509](https://github.com/leehack/llamadart/issues/509)). |
| C05 thinking and budget | Same arithmetic prompt with thinking on, max 256; native GGUF budget 0 and 32 on a qualified reasoning fixture | Final visible answer; correctly separated thinking when emitted; no leaked delimiters. Budget behavior checked against native counters/reference semantics, not character count. LiteRT/Web reject native GGUF-only budget controls. |
| C06 conversation and system messages | System `Answer briefly.`; user `Remember this code: cedar-17.`; assistant acknowledgement; user `What code did I ask you to remember? Reply only with the code.` | Native/GGUF history retains `cedar-17`; captured serialized messages preserve system role. LiteRT Web single-turn limitation is explicitly reported; no claimed history pass. |
| C07 tools | Tool `get_weather(city: string)`; user `Call get_weather for Montréal.`; modes auto, required, none; fixed tool response | Required emits the named tool and parsed `{"city":"Montréal"}` where supported; none emits no tool; auto accepts permitted text or valid call. Tool response continuation tested where supported. Unsupported constrained modes fail explicitly. |
| C08 cancellation and reuse | Start long generation; cancel after first nonempty delta, await completion, then issue hello on a new/reset conversation | Stream terminates within 5 seconds, engine remains usable, no late deltas after completion; regeneration passes. If generation already finished, mark cancel subcase NOT_RUN and use the locked longer fixture. |
| C09 dispose and reload | Load/generate/dispose, then new engine/load/generate once in quick core; twice for lifecycle-focused changes or release selection | Clean shutdown; no live worker/stream handles; repeat completion. Record memory after each cycle without demanding identical RSS. |
| C10 limits and stop markers | Locked fixture reliably emitting a chosen marker, plus max-token limit case | Advertised stop/limit semantics, correct finish classification, marker suppression according to API contract; no uncontrolled continuation. Unsupported stop options rejected. |
| C11 native stream batching | Compare supported defaults with one explicitly supported batching configuration at deterministic settings | Same reconstructed content/tool/thinking, ordered completion; chunk count may differ. LiteRT Web must reject nondefault native batching controls. |
| C12 failure and recovery | Missing file, bad model hash, unsupported option, unsupported feature, cancelled download; reload valid fixture | Typed actionable errors, no false success or permanently stuck worker; valid recovery completes. Package/model format misrouting and missing companion are covered. |

For model-dependent expectations (C04–C07/C10), first obtain reference behavior
from the exact fixture and sampler. Keep semantic failures distinct from transport,
parser and runtime failures. Do not demand exact free-form prose or universal
CPU/GPU token identity. Determinism checks are within a pinned cohort; parity
assertions use the specific contract/reference under test.

LiteRT Web runs C01, applicable single-turn C03/C04, lifecycle C08/C09 and C12,
plus explicit unsupported tokenizer/history/tool/native-control cases. It does
not inherit native conversation capabilities just because both use `.litertlm`.

The catalog enumerates C01–C12; a run manifest expands only its selection into
mandatory device/model/backend/subcase rows before execution:

- Quick core: C01–C04, C06, C08, C09's single reload, C10's token-limit subcase,
  and C12's invalid-input/recovery subcase, plus one benchmark series.
- Change-focused: add C05 for reasoning changes, C07 for tool/template changes,
  C10's stop-marker case and C11 for streaming/stop/batching changes, and the
  applicable feature packs. Load/dispose/worker/lifecycle changes require C09's
  second reload and the relevant full C12 failure/recovery subcases.
  Parser/template changes require affected-family
  fixtures and positive/negative modes, even if that expands the quick selection.
- Release: all applicable C01–C12 subcases and existing required release rows.

Web applies the same selection rules to its documented positive and negative
contracts. A model lacking a runtime-supported feature leaves that positive
subcase NOT_RUN with a fixture reason; it is not runtime UNSUPPORTED. Selecting
only tiny-gguf cannot qualify chat. Missing a mandatory row makes that selection
incomplete; accounting for a missing test never turns it into a pass.

## 6. Feature packs

| Pack | Fixtures / assertions | Selection |
| --- | --- | --- |
| Structured output | Prompt `Return an object with count 3 and ok true.`; schema with required integer `count`, boolean `ok`, no additional properties. Parse exactly; test invalid types/unknown keys, partial-stream suppression, malformed-final rollback and tool modes with thinking prefixes. | Supported GGUF grammar path; compiled grammar acceptance/rejection and affected-family upstream parity remain mandatory existing checks. LiteRT grammar negative case. |
| State and prompt reuse | Dense model: full recomputation vs reused prefix; save/restore same continuation; malformed/version-mismatched state | Native and capable GGUF Web bridge. Web virtual-file persistence is not durable reload storage; test explicit export/import separately. LiteRT unsupported. |
| Embeddings | `A cat sits on a mat.`, `A feline rests on a rug.`, `The engine uses diesel.`; single vs batch | Correct dimension, finite/nonzero vectors, single/batch tolerance; reference-qualified similarity ordering. GGUF supported paths; LiteRT negative. |
| Vision | Bundled synthetic red square on white; `What color is the square? Answer with one word.` | `red`, media reaches model, missing/wrong projector rejected. Native/GGUF Web and native LiteRT compatible bundles; browser LiteRT unsupported as documented. |
| Audio understanding | Fixed WAV saying `The meeting is on Tuesday.`; ask day of meeting | `Tuesday` with model-qualified tolerance; file/blob paths and invalid media errors. No live microphone needed for deterministic lab case. |
| ASR | Fixed licensed PCM WAV `The quick brown fox jumps over the lazy dog.`; batch and chunked streaming where supported | Normalized transcript matches reference, correct sample-rate validation, finalization/cancel/restart; log WER and real-time factor. Moonshine native CPU; Qwen3 native and qualified Web WAV route. |
| TTS | Text `Hello from llamadart.` and a supported speaker configuration | Finite nonempty PCM, valid rate/channels/duration, playable/exportable WAV and cancellation; listening quality remains separate local QA. |
| LoRA | Locked matching base/adapter; baseline, adapter active, reset | Supported load/runtime semantics, reference-qualified output effect; reject incompatible/aLoRA/version-skew cases. Native LiteRT only one default-scale load-time adapter; reject runtime updates/stacking/scaling. |
| Speculative | Same target/prompt/sampler with drafting off/on; locked compatible draft if needed | Output parity against appropriate upstream reference, accepted/drafted counts and speed; distinguish MTP, n-gram, external draft and native LiteRT controls. No unsupported Web substitution. |
| Runtime controls | Threads 1/4, relevant activation type/prefill setting; full/compact CPU packaging; explicit CPU/GPU/fallback | Effective values/backend proof, supported behavior and typed invalid-combination failures. Unsupported/NPU deployments do not silently pass on CPU. |
| App/device/browser | Download cancel/resume/cache, background/foreground, rotation, memory warning, Web worker restart, denied microphone, audio playback/export | App stays responsive, progress/cancel honest, recoverable errors and safe cleanup. Owned hardware covers human audio and sustained thermals; cloud media fixtures cover deterministic paths. |

Run affected-family fixtures when templates/parsers change; a convenient tiny
model is only pipeline evidence. Full and compact Android CPU packages both
need physical lower-ISA and modern-device coverage for the relevant release.
Neither a modern phone running compact nor an emulator closes issue #476.

## 7. Prompt and inference configuration contract

Store case prompts as versioned UTF-8 data. Reports include literal test prompts,
message roles, tool schemas, template identity/options, media fixture hashes,
expected predicates and case version. Use synthetic fixtures only; never collect
personal chat history or microphone content for unattended runs.

Original profile design sketch (the executable JSON contract is now in
`packages/llamadart_validation/assets/profiles/`; this sketch is not CLI input):

```yaml
schema_version: 1
profile: native-quick
model_id: chat-litert
case_ids: [C01, C02, C03, C04, C06, C08, C09, C10.limit, C12.recovery]
load:
  context_size: 1024
  threads: 4
  batch_threads: 0 # LiteRT; GGUF profile uses 4
  backend: cpu # separate execution for explicit gpu
generation:
  max_tokens: 32
  temperature: 0
  seed: 1
  enable_thinking: false
benchmark:
  id: short-generation
  prompt: "List the numbers from one to twenty in English."
  warmups: 1
  measured_runs: 3
timeouts:
  generation_seconds: 60
  model_prepare_seconds: 300 # CLI; native Flutter uses 600
  cloud_execution_minutes: 20
```

GGUF raw timing uses `Once upon a time`; instruction-model timing uses the list
prompt above. C05/C08 and feature packs override token budgets explicitly.
By default benchmark only chat-gguf or chat-litert once per backend, with one
warm-up and three measured samples total; do not multiply repetitions by case
count. Tiny-gguf timings are packaging diagnostics unless explicitly selected as
a separate benchmark cohort. If both models are benchmarked, report two series.
Default context is 1024; tools/feature packs can request 2048 with a distinct
configuration hash. Standard backend comparisons use the same settings and model.
Do not compare this 32-token core smoke to long-context throughput.

At build/run time expand **all** remaining package/runtime defaults into the
effective record (top-k, top-p, min-p, penalties, stop strings, batch thresholds,
cache/prompt-reuse policy, GPU hint, activation type, prefill and speculative
settings). Include unsupported/null provenance rather than inventing values.
The frozen runtime revision plus effective configuration hash identifies the
experiment. Capability validation happens locally before a cloud submission.

For warm measurements, retain the loaded model but start a fresh conversation
and reset request/KV state unless testing reuse. Record actual cache/reuse
behavior; if it cannot be disabled or verified, label the cohort as warm-cache
and do not compare it to uncached prefill. Native initialization may be lazy:
`loadModel` return time and first inference readiness are separate measurements.

## 8. Firebase device selection and free rotation

The live `gcloud firebase test ... models list` catalog on **2026-09-17** contained
205 Android entries (196 physical, nine virtual) and six iOS models. Counts
include device/form-factor variants, not 196 distinct useful inference targets;
capacity is not a reservation. The iOS catalog contained iPad 10, iPhone 8,
11 Pro, 14 Pro, 16 Pro and SE 3. Refresh supported OS/version and capacity before
every submission using the [Android](https://firebase.google.com/docs/test-lab/android/available-testing-devices)
and [iOS](https://firebase.google.com/docs/test-lab/ios/available-testing-devices)
catalog guidance.

Choose for a new driver/SoC generation, CPU instruction baseline, OS boundary or
form factor. Plan coverage independently of access to personal mobile devices.

| Priority | Device ID / catalog OS | Added coverage | Initial cases |
| --- | --- | --- | --- |
| A | Galaxy S24 `SC-51E` / API 36; low capacity | Pilot's verified Adreno 750 crash/output-divergence reproducer | Four isolated GGUF CPU/Vulkan and LiteRT CPU/GPU profiles; #79/#51 diagnostic controls |
| A | Lenovo Tab P12 `TB370FU` / API 35; medium capacity | MediaTek Dimensity 7050 / Mali-G68, non-Pixel/non-Qualcomm driver stack, Android tablet | Same four core profiles; tablet app flow when relevant |
| A | iPhone 16 Pro `iphone16pro` / 18.3; medium capacity | Repeatable pilot Apple reference; actual OS was 18.3.2 | Four CPU/Metal and LiteRT CPU/GPU core profiles |
| A | iPhone SE 3 `iphonese3` / 26.3; medium capacity | Newer catalog OS on a different, older Apple device generation | Four core profiles, lifecycle and small-screen flow; retain 18.4 as optional same-model OS control |
| B | Galaxy A05s `a05s` / API 35; low capacity | Snapdragon 680 / Adreno 610, older/budget CPU and GPU; candidate lower-ISA qualification device | GGUF CPU full + compact first; probe CPU features and selected module before claiming older-ISA coverage; GPU and LiteRT next |
| B | iPhone 8 `iphone8` / 16.6; medium capacity | Older Apple hardware and nearest available OS to current iOS minimum 16.4 | Tiny GGUF CPU/Metal first; representative model only after memory preflight; LiteRT and resource failures explicitly recorded |
| A, targeted | iPad 10 `ipad10` / 16.6; medium capacity | Apple tablet and older-OS coverage without a personal iPad | GGUF Metal and LiteRT GPU core plus layout/lifecycle; CPU rows remain NOT_RUN unless separately selected |
| C | Pixel 5 `redfin` / API 30; high capacity | Older Android OS when installation/runtime compatibility changes | Packaging/CPU core, then affected backend; different purpose from A05s ISA checks |

Hardware family sources: [Lenovo Tab P12 specifications](https://psref.lenovo.com/syspool/Sys/PDF/Lenovo_Tablets/Tab_P12/Tab_P12_Spec.pdf),
[Samsung A05s specifications](https://www.samsung.com/africa_en/smartphones/galaxy-a/galaxy-a05s-silver-128gb-sm-a057fzsgafc/),
and [Qualcomm Snapdragon 680 brief](https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/documents/product_brief_-_snapdragon_680_4g_mobile_platform.pdf).
Probe actual RAM, CPU features, GPU/driver and OS build in each execution; do not
infer a lab SKU's RAM or instruction support from its marketing name. S24 regional
variants can differ; retain `SC-51E`, not just `Galaxy S24`.

Virtual candidates in the current catalog:

- `MediumPhone.arm`, API 29 and 36: older/current Android CPU and installation
  checks, subject to the final test app's minimum SDK.
- `MediumPhone_ps16k.arm`, API 36: real 16K-page emulator packaging/load checks.
- `MediumPhone_ps16k_backcompat.arm`, API 36: separate compatibility-mode case
  when changing native alignment/loading; never substitute it for native 16K.

These are arm64 virtual entries. Keep Android x64 coverage in a local/CI emulator.
GPU-capable virtual infrastructure does not prove a physical Adreno/Mali driver,
device NPU, lower-ISA CPU selection or real-device memory behavior.

### Next-milestone LiteRT-LM NPU test pack

Qualify **Galaxy S24 first, then Pixel 10**. The S24 pilot now establishes NPU
participation through both native and public adapters, but public history fails
([#513](https://github.com/leehack/llamadart/issues/513)); full qualification remains
blocked. See the [dated result](cross_platform_validation.md#galaxy-s24-npu-pilot-2026-09-17).
The later [native replay on current main](cross_platform_validation.md#native-history-replay-on-current-main--litert-lm-0170-5)
reproduced repeated tokens with the public system JSON on `0.17.0-5`; canonical
native history recalled `Cedar17`, still failing exact capitalization. Fixing
serialization alone does not yet qualify the model/path.
The [public replay after the fix](cross_platform_validation.md#public-history-replay-after-the-system-content-fix)
now also returns `Cedar17`: 13 PASS, one strict history FAIL, with NPU
participation verified. The service correction is locally committed; it is not
a merged release fix. [Repeated Mac CPU controls](cross_platform_validation.md#repeated-gemma-cpu-controls-on-macos)
now reproduce all four history failures in three public runs and three direct
C API repetitions, so the behavior is not confined to NPU or Dart. Original-model
and tokenizer/template reference checks remain necessary; the separate S24 CPU
device row remains unrun.
Pixel 10 remains planned. Neither catalog availability nor a built bundle proves
NPU inference on another target.
Google's [LiteRT-LM NPU guide](https://developers.google.com/edge/litert/next/litert_lm_npu)
documents SoC-specific Gemma 3 1B models for Qualcomm SM8650 and Google Tensor G5.
The [Google Tensor SDK](https://developers.google.com/edge/tensor-sdk) remains
labelled beta; verify required SDK/model access before selecting that row.

| Order | Device / catalog OS | Required NPU target | Purpose |
| --- | --- | --- | --- |
| 1 | Galaxy S24 `SC-51E` / API 36 | Qualcomm SM8650, Snapdragon 8 Gen 3; matching Qualcomm dispatch and QAIRT/HTP libraries | NPU participation verified; resolve history failure and finish matched controls before qualification |
| 2 | Pixel 10 `frankel` / API 36 | Google Tensor G5; matching Google Tensor dispatch/runtime | Independent vendor path; catalog snapshot reports high capacity |
| Alternate | Pixel 10 Pro `blazer` / API 36 | Tensor G5, separately recorded device/OS/driver cohort | Use only if the base Pixel 10 is unavailable; snapshot reports low capacity |
| Later | Galaxy S25 Ultra `pa3q` / API 35 or 36; OnePlus 11 `CPH2449` / API 34 | Corresponding SM8750 or SM8550 model/runtime | Optional Qualcomm-generation expansion after the first two paths work |

Device/OS entries are from the 2026-09-17 Firebase catalog snapshot. Confirm the
actual `ro.soc.model`, ABI, OS build and driver on device, then require an exact
manifest match before loading. S24 variants with other SoCs are not substitutes.
See [SC-51E hardware specifications](https://www.docomo.ne.jp/support/product/sc51e/spec.html)
and [Pixel 10 Tensor G5 specifications](https://blog.google/products-and-platforms/devices/pixel/tensor-g5-pixel-10/).
Catalog presence establishes access to a device, not its NPU permissions or
working dispatch libraries inside the Test Lab app sandbox.

The Pixel 9 Pro's Tensor G4 and the Tab P12's Dimensity 7050 are absent from
the documented LLM NPU model table, so they are not positive NPU targets in this
pack. Current llamadart Apple backends expose CPU/GPU only. Existing GPU tests
remain useful and do not qualify any of these devices' NPUs.

**Preparation implemented:** the two immutable SoC-specific candidate profiles
and `validation.dart npu-preflight` now check local model/kit hashes, runtime
identity and host/DSP library architectures. The S24 model was staged and checked;
same-source Qualcomm/Tensor dispatch libraries were compiled in the native owner
worktree. Its diagnostic proxy distinguishes completed synchronous calls from
failures and async submissions, with model-free forwarding/negative tests.
These are input/build checks, not device execution evidence. See the
[NPU input runbook](cross_platform_validation.md#npu-input-preparation).

**Android implementation:** the opt-in builder embeds verified local weights and
vendor libraries, checks final APK entries, and repeats those checks before remote
upload. The installed host verifies SoC/API/ABI and installed file hashes before
loading. Separate `public_api` and `native_c_api` bundles capture raw dispatch
snapshots and retain distinct path identities in the same report contract. Both
NPU paths use compiled runtime sampling defaults: the current public NPU adapter
does not apply requested session sampler overrides. Effective sampler values
remain unknown, so the deterministic cancellation-prefix check may stay NOT_RUN. The
native control calls the C API on a dedicated isolate, bypassing public Dart
backend/worker bindings. Native source/build ownership remains in the native repo.

The public path runs 14 quick chat cases; the control now runs twelve (load,
hello/arithmetic, four history controls, reload, warmup and three measured
generations). The additional controls compare canonical system/history seeding,
the observed public system JSON, history without system content, and a combined
prompt; all use the exact `K7Q2` history oracle and per-generation NPU proof.
The earlier `cedar17` oracle failed on the int4 artifact itself
([#513](https://github.com/leehack/llamadart/issues/513)).
N01/N03/N04/N06
are covered to this bounded scope. N02's additional Unicode generation fixture,
the compatible CPU Gemma control, and aggregate matching of the reference/public
reports remain unimplemented; C02 tokenizer coverage runs only on the public
path. A single passing run cannot complete the whole NPU pack. The installed S24
apps now prove driver access, initialization and NPU participation, and report
measured TPS; the public history failure remains a qualification blocker. Other
device rows remain NOT_RUN until matching installed apps execute. Positive
counters prove NPU participation with CPU partition coverage unknown, not full
NPU placement.

**Preflight before spending a device execution:**

1. Resolve model access and freeze the exact `.litertlm` revision, SHA256,
   quantization, compiled SoC, context limit and tokenizer/template metadata.
   Use the vendor-specific Gemma fixture, not the pilot's generic Qwen3 bundle.
   No gated download or SDK terms acceptance is implied by adding this plan.
2. Resolve compatible native runtime, vendor dispatch library and all dependent
   libraries, including Qualcomm QAIRT/HTP host and DSP libraries where required.
   Pin their versions/checksums and verify permitted packaging. Inspect final
   APK contents and native dependencies; the inspected pilot APK contained no
   Qualcomm NPU/dispatch libraries. A library search path alone cannot supply them.
3. Arrange model/library transfer into the application sandbox through a supported
   test mechanism. The upstream `/data/local/tmp` CLI recipe is a diagnostic
   reference, not proof an installed Flutter app can access the same files or
   DSP libraries. Keep credentials out of APKs, logs and exported artifacts.
4. Use explicit `LiteRtLmBackendPreference.npu` and a validated
   `liteRtLmDispatchLibDir`. Keep llama.cpp-only options at supported defaults
   (`numberOfThreadsBatch=0`). Lock context 1280 for the documented Gemma NPU
   fixtures, max output 32, requested temperature 0 and seed 1, and one warm-up
   plus three measured runs. The current NPU runtime cannot accept the requested
   sampler overrides; record compiled runtime defaults and unknown effective
   sampling explicitly. Do not label these runs greedy or seeded. Do not apply Qwen-specific
   thinking/template options to Gemma. Native automatic controls stay at their
   documented defaults unless the exact NPU artifact supports an override.
5. Build a minimal direct-native reference test and the public Dart test with
   the same model and native/runtime/library inputs. Both must run as installed
   app tests without root, protected vendor-directory writes or special device
   modifications. Missing access/library/model prerequisites leave the row
   NOT_RUN with a concrete reason; do not burn cloud quota on an incomplete APK.

| Case | Action | Required evidence / expected output |
| --- | --- | --- |
| N01 identity and load | Load the exact SoC-matched Gemma artifact through explicit NPU selection | Correct artifact/library hashes; native dispatch initialization and actual NPU graph/partition execution evidence. A selector or `availableBackends` string alone is insufficient. |
| N02 semantic reference | Native reference and public Dart each run C04 hello/arithmetic, the C02 tokenizer encode/decode fixture, and a separate generation prompt `Reply with exactly: Montréal 👋` | Apply C04 semantic oracles and C02 exact tokenizer round-trip rules separately. The generation fixture expects exactly `Montréal 👋` after reference qualification: public chat content keeps the whitespace a reply ends with, so `C02.generate` fails a model that adds any. It cannot substitute for tokenizer coverage. Preserve raw native text and Dart content/finish handling; no corruption or silent empty response. |
| N03 bounded throughput | `List the numbers from one to twenty in English.`; one warm-up, three measured generations | Coherent output and clean finish; cold readiness, TTFA, actual token counts, native prefill/decode TPS when available, estimated wall TPS and memory. Missing counters remain null. |
| N04 lifecycle | Cancel a qualified long fixture after first output; reload and generate again | Bounded stream termination and usable engine, no stale callbacks or native crash; use the C08/C09 rules. |
| N05 failure contracts | Unit/local fixture checks for missing dispatch dependency and mismatched SoC/model manifest | Preflight rejects incompatible manifests; missing native dependency produces actionable diagnostics. Do not deliberately load an incompatible compiled model on the lab device. |
| N06 explicit backend integrity | Inspect native execution/delegate evidence during each successful generation | Record partition placement and any CPU fallback. A CPU-only result fails the requested NPU row; mixed execution is labelled hybrid, never reported as all-NPU. Missing proof leaves qualification incomplete. |

The direct-native control must be compared on the same target device/OS and
exact compiled artifact. A separate CPU Gemma model can help diagnose prompt or
model quality, but its weights/quantization/conversion may differ: log those
differences and do not present its TPS ratio as a pure NPU speedup. Similarly,
do not run an NPU-compiled file on CPU unless the artifact explicitly supports it.

Initially schedule three separate executions per device: **direct-native NPU
reference, public llamadart NPU, and a compatible CPU semantic control**. Each
test adapter can contain multiple cases and timing repetitions within that one
execution. Keep the native reference and Dart path in separate app processes so
a crash or initialization state cannot conceal the difference. In a first smoke,
stop before the Dart cloud submission if the native control cannot initialize;
retain the unspent quota and record Dart qualification as NOT_RUN.

Append S24 on day 5 and Pixel 10 on day 6 of the proposed rotation: **six NPU
qualification executions over two additional quota days**, bringing core plus
this initial NPU pack to 22 executions across at least six days. The targeted
iPad row on day 7 brings the initial mobile selection to **24 executions over
at least seven quota days**. This stays within four planned physical executions/day
and preserves the fifth daily slot for an explicit diagnostic rerun. Do not add
NPU to an already-full four-profile core day.
Further repetitions, alternate devices, or artifact experiments require extra
quota days under Spark; no automatic retries or automatic billing upgrade.

Three controls per device are the initial qualification budget, not an obligation
for every later Dart-only edit. After qualification, rerun current public-Dart
NPU cases on relevant changes; rerun the native control when native/model/vendor
inputs, template/sampling settings, SoC, OS or driver change, or results diverge.
Reuse a CPU semantic reference only when its model/configuration/template and
device/OS identities still match. Show reused
controls as dated reference links, never current-head passes. An explicit release
or issue-verification requirement to rerun a control overrides this optimization.

Reports add NPU/hybrid rows to the existing heatmap and TPS panels, with vendor,
SoC, compiled-model hash, dispatch/QAIRT version, partition placement and proof
links. A usable NPU result requires correct public-package output, lifecycle
completion and verified NPU execution; missing evidence or native failure never
becomes a green backend badge. No NPU run is scheduled by this document update.

### Budget and scheduling

The original rotation below describes Spark, which requires an **unbilled
project**. Project `llamadart-device-qa-20260916` is now on Blaze and uses its
separate free-minute guard; the original Spark execution count is no longer its
free allowance. Firebase currently allows five physical executions and ten virtual
executions per project/day on Spark. Each device configuration, retry and shard
can consume another execution; five devices times four profiles is twenty
executions, not five. See [official quotas](https://firebase.google.com/docs/test-lab/usage-quotas-pricing).

Reserve at most **four planned physical executions/day**, leaving the fifth
for an explicit diagnostic rerun. Disable automatic flaky retries, sharding and
device/OS Cartesian expansion. Inspect remaining quota and other active matrices
before submitting; insufficient quota means NOT_RUN/reschedule, never automatically
enabling billing or creating projects to bypass the allowance.

An explicitly authorized Blaze batch uses the same bundle and cleanup flow with
a live exact-account check and a gross-cost reservation for every submission.
The local cap replaces the Spark four-run guard only for that explicit mode;
free minutes and expected credits are not subtracted from its reservations.
For zero-cost Blaze runs, verify remaining physical minutes against each selected
provider timeout plus a rounding reserve. Spread the rotation across additional
days if its elapsed test time would exceed 30 free physical minutes in one day.
Keep the authorization window fixed, preserve the shared journal, and refresh
quota and funding evidence before each run. No automatic paid retry is permitted.
The first batch completed the S24 native NPU reference, public llamadart NPU
after reference initialization, and the existing Qwen CPU retry. All three were
collected and completion-verified; the public history and CPU arithmetic failures
remain explicit. That retry does not satisfy the matched Gemma CPU control still
required by the NPU pack. The batch consumed six rounded free physical minutes;
the full day's inventory, including earlier Spark tests, totalled 17 of 30.
Credit balances with unspecified service coverage do not authorize paid dispatch.
Blaze's verified free minutes can fund a shorter run: the runner reserves its
full provider timeout plus a rounding minute, then requires a fresh project-wide
usage check before reclaiming the unused reservation. Never treat the upgraded
physical execution-count quota as extra free minutes.

| Day of a release rotation | Device | Planned executions |
| --- | --- | --- |
| 1 | S24 | GGUF CPU, GGUF Vulkan, LiteRT CPU, LiteRT GPU = 4 |
| 2 | Tab P12 | Same four profiles = 4 |
| 3 | iPhone 16 Pro | GGUF CPU, GGUF Metal, LiteRT CPU, LiteRT GPU = 4 |
| 4 | iPhone SE 3 / 26.3 | Same four profiles = 4 |
| 5 | S24 / SM8650 | Native NPU reference, public llamadart NPU, compatible CPU semantic control = 3, after NPU preflight |
| 6 | Pixel 10 / Tensor G5 | Same three NPU qualification/control profiles = 3, after NPU preflight |
| 7 | iPad 10 / 16.6 | GGUF Metal and LiteRT GPU core, each with tablet layout/lifecycle = 2 |

The four-device CPU/GPU core takes **16 executions across at least four
quota days**; including NPU and the targeted iPad checks takes **24 executions
across at least seven quota days**. Missing NPU prerequisites defer those rows
with an explicit NOT_RUN reason; they do not require a personal device or block
independent CPU/GPU checks. This qualifies selected rows only, not the complete
supported platform/release matrix. Older-device, CPU full/compact, OpenCL and
large feature-pack executions extend the rotation on additional days. Do not
spend the reserved rerun automatically. For a narrow runtime change, run its CPU/GPU pair
on two relevant devices in one day instead of all four profiles on one device.

Before dispatch, produce a local selection summary with the exact case/model
rows, model bytes, build artifacts, execution count and quota-day assignment.
For a narrow change, choose one representative of each affected hardware/driver
family first; expand on failure or when release coverage requires it. Apply only
to the changed runtime: a LiteRT-only change does not automatically spend quota
on both GGUF profiles. Preserve the omitted rows as NOT_RUN, with their reason.
The published rotation is the initial coverage schedule, not a recurring job.
A LiteRT-only follow-up across the same four core devices therefore needs eight
CPU/GPU executions over at least two quota days, rather than sixteen for both
runtimes. This saves runs by selecting scope, not by claiming fresh GGUF evidence.

Use the Mac and free CI for frequent checks. Run Firebase as the primary mobile
lane on native pin/backend/packaging changes and release candidates, not on every
documentation or pure-Dart PR. Personal Pixel/iPad runs are optional diagnostics
and never a prerequisite to lab submission. Select virtual packaging cases only
when needed and count them against the shared ten/day limit.

The initial five pilot submissions finished (one intentionally cancelled).
The initial CPU pilot ran with billing disabled and needed no GCP credit. A later
live check on 2026-09-17 verified `billingEnabled: true` after the explicitly
authorized Blaze upgrade. Spark plans correctly reject this billed project;
future tests require the explicit Blaze configuration. Subsequent S24 runs
established native/public NPU participation and CPU download recovery, while
retaining semantic failures. See the [dated run evidence](cross_platform_validation.md#galaxy-s24-npu-pilot-2026-09-17).
Test Lab executions have no idle VM to stop. Any later
Compute Engine CUDA testing is a separate action: verify credit eligibility and
remaining balance first, and account for disks/IP/storage after stopping a VM.
Stopping compute does not guarantee every associated resource is free.

Android Device Streaming is optional interactive debugging, with a separate
30-minute/project/month free allowance at this snapshot; it is not extra
automated execution quota. End a streaming session explicitly. The free rotation
does not require Blaze for either service; Device Streaming is outside the
authorized automated-test batch.

## 9. Remote execution, provisioning and cleanup

The orchestrator owns the full **prepare → upload → run → collect → cleanup**
flow. Start with `gcloud` driven from the owned Mac and a local run journal;
no always-on controller or Terraform deployment is needed for the initial lanes.
CI builds downloadable bundles. It does not automatically create VMs or submit
Firebase tests. A separately authorized remote run consumes those exact bundles
without rebuilding the test app on the destination.

### One command interface and resumable run record

Implement these subcommands in `tool/testing/validation.dart`, with provider
logic under `tool/testing/validation/`. They are **proposed commands**, not
available commands to execute today:

```text
dart run tool/testing/validation.dart plan --target gce-linux-cuda --bundle <bundle-dir> --profile gguf-cuda --out <run-plan.json>
dart run tool/testing/validation.dart plan --target firebase-android --bundle <bundle-dir> --profile litert-cpu --device <model-and-os> --out <run-plan.json>
dart run tool/testing/validation.dart run --plan <run-plan.json>
dart run tool/testing/validation.dart status --run-id <run-id>
dart run tool/testing/validation.dart collect --run-id <run-id>
dart run tool/testing/validation.dart cleanup --run-id <run-id>
```

Also support `gce-windows-cuda` and `firebase-ios` targets. `plan` performs only
local/read-only checks and writes the exact selection, bundle hashes, account,
project, device or VM specification, deadlines, cost/quota preflight and cleanup
policy. Project/account values come from explicit local configuration; never
change the user's default `gcloud` account/project. Require a fresh quota/credit
check immediately before `run` makes remote changes. Missing eligibility or
configuration leaves the selection NOT_RUN with a concrete reason.

`run` uploads and starts the selected tests, collects available evidence and
cleans up automatically, including failure paths. `status`, `collect` and
`cleanup` reconnect to an existing run; they never create a replacement or
silently rerun inference. An explicit retry gets a new attempt ID and preflight.
Cleanup of an active run first cancels it, then attempts bounded collection.

Under `.dart_tool/validation/runs/<run-id>/`, persist `run-plan.json`,
`orchestration.json`, append-only `remote-events.jsonl`, and `cleanup.json` next
to the common manifest and test results. Write mutation intent before each
provider call and save operation, instance, disk, matrix and result-location IDs
as soon as known. Use stable run/attempt IDs and reconcile uncertain submissions
before retrying. Record preparation, execution, evidence collection and cleanup
as separate outcomes; passing inference cannot hide failed or unknown cleanup.

### Disposable Compute Engine CUDA VMs

| Phase | Planned implementation / completion evidence |
| --- | --- |
| Preflight | Require a separate explicitly selected personal GCP project, active applicable credit and expiry, GPU quota, available region/machine, and a conservative per-run estimate covering compute/GPU, Windows licensing where relevant, disks, IP and transfers. Include other known credit use and a reserve. If coverage cannot be established, do not provision. |
| Create | Create one VM per attempt with an immutable OS image ID, pinned driver/bootstrap inputs, run labels and a persisted resource ledger. Set an absolute deletion deadline at creation, default 60 minutes after dispatch, earlier than credit expiry with a margin. Set auto-delete on every newly created disk; avoid snapshots, reserved addresses, buckets and NAT services for this lane. |
| Bootstrap | Linux shell or Windows PowerShell installs only required runtime/driver prerequisites. Verify driver readiness, actual GPU and CUDA compatibility before uploading tests. Bootstrap is restart-safe and bounded to 20 minutes; failure triggers collection and cleanup. Record actual installed versions, image, GPU, driver and bootstrap hashes. |
| Upload | Fetch and verify the exact CI bundle on the controller, then transfer it over authenticated SSH/SFTP, preferably through IAP. On Windows enable Google's supported SSH package in instance metadata/bootstrap. Use a run-specific remote directory; verify checksums again on the VM. No GitHub token or GCP key is embedded in the bundle or startup metadata. |
| Execute | Invoke the packaged CLI through a tracked shell/PowerShell job using the locked manifest/profile. Download and hash selected models with the existing five-minute preparation bound; run with a 20-minute test timeout. Track the remote job identity so reconnecting observes the existing job. CUDA requires actual offload evidence; it does not establish LiteRT GPU support. |
| Collect | Incrementally copy bounded events/diagnostics to the controller, then retrieve complete JSONL, samples, logs and crash evidence. Allow at most ten minutes for final collection, constrained by the deletion deadline. Missing evidence is reported explicitly; it never extends the VM lifetime automatically. |
| Teardown | In a finally path after success, failure, timeout or cancellation, delete this run's disposable VM and owned disks/resources. Wait for provider operations, re-query the recorded resource IDs and report remaining resources. A stopped instance alone does not satisfy this lane's cleanup contract. |

For the deadline use Compute Engine's `--termination-time` with
`--instance-termination-action=DELETE`, then read back the effective scheduling
configuration. An absolute deadline avoids extending the allowance after a
restart. Google's deadline can begin termination up to 30 seconds late, so leave
time/credit margin; it is a provider backstop, not exact billing precision.
See [VM runtime limits](https://docs.cloud.google.com/compute/docs/instances/limit-vm-runtime).
This protects against the controller disconnecting; a shell finally block alone
cannot. Do not rely on this backstop for a VM that stops before its deadline:
Compute Engine clears its termination timestamp when stopped. Reconnect and
delete that VM and its disks through the ledger; stopped/unknown state remains
unresolved cleanup. Never remove or extend the deadline automatically. Partial logs may be
lost if the controller cannot reconnect before deletion; report that evidence
gap instead of retaining a billable disk indefinitely.

Use [IAP forwarding](https://docs.cloud.google.com/iap/docs/using-tcp-forwarding)
for administration and [Windows SSH](https://docs.cloud.google.com/compute/docs/connect/windows-ssh)
for the Windows adapter. Resolve the outbound download path in preflight: if a
temporary external IP is needed, count its cost and restrict administrative
ingress. Do not create a persistent NAT service to hide that dependency.
Keep cloud credentials on the controller using the user's existing login; do
not add cloud secrets or billing permissions to the build workflow.

Stopping a VM leaves potentially billable resources such as disks and static
addresses; see [Compute Engine stop behavior](https://docs.cloud.google.com/compute/docs/reference/rest/v1/instances/stop).
The cleanup ledger must distinguish deleted, still present and unknown resources.
Restrict deletion to exact resources created for this run, verified by IDs and
ownership; never sweep a project or delete an existing user machine. Reconcile
unfinished local run journals before starting another VM, and block new
provisioning while earlier cleanup is unresolved. Do not automatically reprovision
after eviction, capacity failure or a lost connection.

Credit coverage is a dispatch prerequisite, not a claim of guaranteed free GCE
usage. [Alerts-only budgets do not cap spending](https://docs.cloud.google.com/billing/docs/how-to/budgets).
If current credit eligibility/balance cannot be verified with sufficient margin,
use owned hardware/free CPU CI and leave CUDA NOT_RUN. Provider-state cleanup
verification and any later billing reconciliation are separate evidence; no
account balance, current VM state or credit expiry was verified by this plan edit.

### Firebase upload, execution and collection

Use Flutter integration tests as Android instrumentation or iOS XCTest, as
[Firebase documents](https://firebase.google.com/docs/test-lab/flutter/integration-testing-with-flutter).
Robo crawling is not the correctness harness. The maintained quick-core harness
has now executed through both wrappers, with Android app-file retrieval and iOS
XCTest attachment export verified. The broader feature packs remain planned.

1. Freeze source/dependency/model/configuration hashes. Build and locally validate
   supported options, signed iOS inputs and device-specific install requirements.
   Use Release mode for comparable measurements where the integration runner
   supports it; validate that path first. Keep Debug-only measurements in a
   separate cohort if Release instrumentation is unavailable.
2. Refresh catalog and quota, choose an exact device/OS and one backend profile.
   Submit an explicit one-device matrix with a 20-minute execution timeout, no retries
   and video disabled by default. Persist a local run ID and submission state;
   record matrix ID immediately. An uncertain submission is reconciled against
   existing matrices before any retry, to avoid duplicate quota consumption.
3. Run each backend profile in a separate cloud execution/app process. Include
   lifecycle reload tests within that profile. A crash must not prevent the
   other backend profiles from producing their own results.
4. Download pinned public models inside the test or use a verified supported
   fixture-transfer mechanism. No paid custom model bucket. Native Flutter uses
   a ten-minute download deadline within the 18-minute integration test and
   20-minute cloud execution limits; CLI preparation retains five minutes.
   Report received/expected bytes on deadline expiry, remove partial weights,
   and distinguish network preparation failure from inference.
5. Write results incrementally to durable files; capture Android pullable app
   artifacts through a verified Test Lab mechanism and iOS XCTest attachments.
   Prove retrieval on each platform before relying on it. Keep short sequenced
   JSONL summaries in logs as crash fallback, with byte limits and checksums for
   any reconstructed fragments. Never parse a truncated line as valid JSON.
6. Collect JUnit, JSON, logs, native crash/tombstone or XCTest diagnostics and
   manifest. Reconcile app-completed cases with wrapper/matrix status; a process
   crash with zero JUnit cases is still ERROR, not a zero-failure success.
7. Wait for terminal matrix/execution states. On interruption, reconnect via
   saved matrix IDs; cancel unnecessary outstanding tests and verify termination.
   Export evidence promptly rather than depending on the cloud console forever.

The Firebase adapter pushes the local verified APK pair using
`gcloud firebase test android run --type=instrumentation --app=... --test=...`,
or the locally built/signed iOS XCTest zip using
`gcloud firebase test ios run --type=xctest --test=...`. Both specify the exact
project/device, `--async`, `--timeout=20m`, `--num-flaky-test-attempts=0`,
`--no-record-video`, a run/attempt label and a unique `--results-dir` per matrix.
Omit `--results-bucket` to retain default Test Lab storage. APKs/XCTest inputs
carry the selected profile/manifest; prove any runtime configuration injection
before depending on it. See the official
[Android CLI](https://docs.cloud.google.com/sdk/gcloud/reference/firebase/test/android/run)
and [iOS CLI](https://docs.cloud.google.com/sdk/gcloud/reference/firebase/test/ios/run).

A run label or results directory is correlation, not a provider idempotency key.
If the CLI loses its response before the matrix ID is saved, mark submission
UNKNOWN and block replacement submissions until the existing attempt is positively
identified in provider records/console. Do not infer that nothing was submitted
from an empty local journal or an unsuccessful lookup. A later REST adapter can
use a persisted create request ID, but the CLI path must first prove its recovery
behavior; it cannot claim automatic deduplication from labels alone.

The 20-minute flag limits test execution, not provider queue/setup/cleanup time.
Apply a separate 45-minute controller deadline, request cancellation when it is
exceeded, and continue terminal-state reconciliation on reconnect. Capture the
matrix ID/result URI immediately, poll that same matrix and collect from its
returned location. Use the
[testMatrices cancellation API](https://firebase.google.com/docs/test-lab/reference/testing/rest/v1/projects.testMatrices/cancel)
when aborting; sending cancellation alone is not proof that execution has ended.
Android `--directories-to-pull` must name verified accessible output directories
within the supported roots, accounting for scoped storage. iOS uses verified
XCTest attachments. Retain the earlier incremental log fallback for native crashes.

Firebase manages device allocation/install/run and device cleanup; we own
submission, cancellation, evidence retrieval and terminal-state checks. Do not
delete the test project or its default result bucket as per-run teardown. End
any separately opened Device Streaming session. Serialize our submissions within
the selected Spark quota or explicitly authorized Blaze budget, account for other project users, and
never upgrade billing or retry automatically when quota is exhausted. No VM is
created by this adapter.

Keep the default Test Lab result storage for the Spark pilot; do not provision
paid custom Cloud Storage. Store downloaded evidence locally and sanitized small
reports as CI artifacts with bounded retention when that path is implemented.
Do not rely on Flutter per-test Firebase timings or video segmentation: Firebase
documents limitations, so measure durations inside the suite.

## 10. Logs, metrics and result contract

Write `manifest.json`, incremental `events.jsonl`, and bounded `diagnostics/` on
device. One host-side exporter validates those records and derives `results.json`,
`junit.xml`, `samples.csv` and `summary.html`; wrappers must not implement separate
aggregation rules. Firebase's own JUnit remains raw provider evidence and is
reconciled with the derived case report. Preserve samples so reports can be
recomputed without rerunning inference. Common provenance belongs in the manifest;
events reference stable case/model/configuration IDs. Reruns append attempts and
preserve previous failures; never export only the best attempt. The quick-core
exporters are implemented. A preparation failure before the suite manifest is
currently retained as raw evidence and an incomplete run; promoting it into a
structured preparation-error envelope is still a follow-up. It cannot establish
runtime provenance, passing cases or TPS.

The manifest lists every mandatory expanded row and a stable ID; each has one
terminal result per attempt. Detect missing, duplicate or truncated records.
Missing child rows after a process crash become NOT_RUN with the parent ERROR;
missing rows in an apparently successful run make the report incomplete. The
summary shows selected/attempted/passed counts and missing mandatory IDs. It can
be green only when every selected obligation passed (including explicitly
expected unsupported-operation guards); omitted feature packs remain uncovered.

Required identity fields: source commit/dirty patch hash, package/Flutter/Dart
versions, native and Web release tags plus artifact checksums, build mode/ABI,
model/companion hashes, case/profile versions, effective config hash, requested
and resolved backend, CPU features, GPU/driver, device ID/OS build, RAM and page
size where measurable, browser/runtime capabilities, provider and cloud IDs.

Per-case evidence includes monotonic start/end and phase timings; exact synthetic
messages; sanitized rendered prompt/template where observable; generated content,
thinking and tool deltas; token counts with provenance; finish/cancel reason;
expected predicate; actual result; exception type/code/stack; backend initialization
and fallback evidence; output hash; warm-up/sample index; resource availability.
Capture native INFO diagnostics around load/failure, and bounded logs for normal
runs. During timing, buffer bounded text/counters in memory, then serialize after
the stopwatch stops. Keep only small start/phase/crash breadcrumbs on the hot
path; record native logging level and flush overhead so logging changes cannot
masquerade as a speedup. Unknown values are `null` with a reason, never invented
zeroes. Redact credentials, signed URLs, account/device serials and private paths.

| Metric | Definition / interpretation |
| --- | --- |
| Model preparation ms | Download and checksum separately; excluded from inference TPS |
| Public load ms | `loadModel` entry to return; lazy native initialization may remain |
| Cold first-response ms | From entry to the first `loadModel` on a new engine/process to first visible output of its first request; includes load and lazy initialization, excludes prior download/hash time. Record OS file-cache state as unknown unless controlled. |
| TTFA ms | Generation call to first nonempty public content delta; separate first-any-event/thinking times |
| Native TTFT ms | Runtime first-token timing only if exposed; do not relabel TTFA as TTFT |
| End-to-end output TPS | Authoritative generated visible-output token count / stream wall seconds, when available; include first-output latency |
| Estimated wall TPS | Retokenized visible output / stream wall seconds if authoritative count unavailable; label estimated, use null without tokenizer |
| Native prefill/decode TPS | Native token counters / respective native phase seconds; record whether counters are per request or differenced |
| Post-first-token TPS | `(tokens - 1) / (last-token time - first-token time)` only with actual token timestamps; batched Dart chunks are insufficient |
| Memory | Process RSS/peak and GPU allocation where available; provider OS profiler vs in-process sample distinguished |
| Reliability | Cases attempted/completed, crashes/timeouts, backend fallbacks, correctness failures, coverage NOT_RUN counts |
| ASR/TTS | ASR WER plus real-time factor = elapsed seconds from first audio feed to final transcript / input audio seconds. TTS real-time factor = elapsed seconds from synthesis request to final PCM sample / output audio seconds; excludes playback. Record streaming feed pacing; paced live ASR is a different cohort from unpaced file ASR. |

One warm-up plus **three measured repetitions** per benchmark profile; report
median/min/max and individual dots. No p95 from three observations. End-of-sequence
may produce fewer than 32 tokens: record actual count and completion cause, never
divide by the requested maximum. Thinking/tool tokens and visible tokens are
different populations and must be named explicitly.

Continue independent timing cases after semantic assertion failures if the
process is healthy. Retain correctness FAIL and tag their timings
`correctness_failed`; exclude them from passing performance baselines by default.
Crashes/timeouts have missing timings, not zero TPS. Measurement failure does not
erase correctness evidence already written.

Statuses: `PASS`, `FAIL` (an assertion failed), `ERROR` (crash, timeout, harness,
download or infrastructure failure, with a precise reason), `UNSUPPORTED`
(expected contract limitation), `NOT_RUN` (quota, unavailable hardware, missing
fixture or deliberately out of selected scope). A tested unsupported-operation
guard itself can PASS while the positive feature row remains UNSUPPORTED.
Known issues remain failed/error rows linked to their issue; no green XFAIL mask.

Illustrative record shape, using the observed pilot arithmetic failure; timing
values are deliberately absent:

```json
{
  "schema_version": 1,
  "case_id": "C04.arithmetic",
  "device_id": "SC-51E",
  "runtime": "litert_lm",
  "requested_backend": "cpu",
  "model_id": "chat-litert",
  "expected": {"trimmed_regex": "^4[.!]?$"},
  "actual": {"content": "2"},
  "status": "FAIL",
  "reason": "semantic_oracle_mismatch",
  "metrics": {"decode_tps": null, "wall_tps": null},
  "metrics_unavailable_reason": "pilot_assertion_stopped_before_benchmark",
  "issue": "https://github.com/leehack/llamadart/issues/509"
}
```

## 11. Report and graph design

The first report is a portable offline HTML summary with embedded validated data,
status tables, per-sample TPS/latency plots and artifact links. Generate CSV/JSON
from the same records. Add interactive filters, historical trends and quota
visuals after the exporter and physical-device evidence are reliable. No hosted
database, paid dashboard, or GCP service is needed. The views below describe the
complete report design, not six blockers to the first working harness.

| View | Visual / interaction | Reading rule |
| --- | --- | --- |
| Coverage | Device × runtime/backend heatmap; model/feature filters; labels and icons in addition to colors | PASS green, FAIL red, ERROR orange, UNSUPPORTED patterned gray, NOT_RUN empty gray; click opens exact evidence |
| Throughput | Separate small panels for native decode TPS and end-to-end/estimated wall TPS; three dots with median and min/max whiskers | Same model/config/build cohort only; show sample count and failed-output badge; never combine the two TPS definitions |
| Latency | Download, load, cold first response, warm TTFA and total stream duration, separately labelled | No stacking overlapping timings; missing values shown as unavailable |
| Trend | Per-device/model/backend median versus commit, with sample ranges | Compare identical OS/driver/runtime configuration or start a new cohort; annotate pin changes |
| Failures | Exact expectation and output, phase, exception/crash summary, issue link, native/backend evidence | Expose known failures and missing evidence before aggregate pass percentage |
| Cost/coverage | Execution count used/planned and remaining known quota, deferred rows | Show incomplete coverage plainly; no estimated spend presented as billed cost |

The pilot's GGUF medians illustrate why separate charts are necessary: S24 CPU
estimated wall TPS 396.7 vs native decode 475.0; iPhone CPU 674.1 vs 747.5;
iPhone Metal 443.4 vs 5264.0. These are tiny-model diagnostic observations, not
a device ranking. Native compute timing excludes work included in the public
stream. Build modes also differ. Do not put these values in a comparable-platform
leaderboard or infer LiteRT TPS from them.

Performance is initially informational. Establish repeatable per-device/model
Firebase cohorts, recording OS, driver, memory and available thermal information,
before setting thresholds; matching catalog IDs alone do not ensure equal device
conditions. A candidate alert is a >20% median slowdown with matching provenance,
but three lab samples alone cannot prove a regression: confirm in another
quota-approved run, or optionally locally. Correctness/crashes are
blocking independently of speed. No throughput threshold hides a known failure.

## 12. Implementation sequence and completion criteria

1. **Implementation authorized:** use current merged pins; reconcile any later
   release changes before qualification.
   lock reference-qualified core fixtures and resolve model-dependent oracles.
   Reuse the three pilot issues to investigate failures separately from harness work.
2. Implement the smallest shared suite, desktop runner and mobile wrapper, plus
   immutable manifests and incremental JSON. Integrate existing matrix/E2E
   discovery. Validate the shared suite on the Mac and test provider failure paths
   locally before consuming cloud quota; no personal phone or tablet is required.
3. Add separate Android/iOS backend profiles, local preflight, artifact retrieval
   and terminal-state reconciliation. Test the Firebase adapter with fake
   provider responses for uncertain submission, duplicate invocation, quota
   exhaustion, cancellation and missing evidence before any cloud use. Use the
   first approved cloud runs to prove crash recovery and result export, not just
   a happy-path screenshot.
4. Produce offline reports and CI build artifacts; validate Web asset staging and
   one tiny WASM model using the maintained Web E2E path. Keep sign/upload/run
   actions separate from automatic artifact building.
5. Implement the GCE adapter and exercise its failure paths with fake
   provider responses before VM use: uncertain creation, interrupted upload,
   duplicate run invocation, timeout/cancellation, missing evidence, permission
   failure during cleanup, a prematurely stopped VM and a mismatched resource
   owner. Verify that unresolved cleanup blocks another VM. A separately
   authorized short GCE run must prove upload, execution, result retrieval and
   resource deletion before broad CUDA coverage; unavailable credit defers this
   optional lane without blocking the Mac/CI/Firebase harness.
6. **Next mobile milestone:** preserve the demonstrated Android/iOS submission,
   result retrieval and S24 NPU execution. The system-content boundary is now
   covered by the suite branch correction, and the public replay matches canonical native `Cedar17`
   rather than repeated tokens. Keep its strict capitalization failure and the
   native combined-prompt failure explicit. Repeated Mac CPU public/native
   controls reproduce both failure patterns. The original Gemma reference now
   passes all four variants in three repetitions; the CPU tokenizer bytes and
   rendered prompt/token IDs match after accounting for BOS. Separate converted
   weights/quantization from LiteRT runtime execution next, alongside Qwen
   arithmetic and GPU work. Keep those findings separate from NPU attribution.
   Qualify the implemented Unicode generation case, compatible S24 Gemma CPU
   and paired-report controls. Gated CPU
   weights require verified private model transfer before a Firebase run; never
   package an access token or substitute a signed URL in its model lock.
   Qualify S24 then Pixel 10 NPU only after model/library
   preflight and each native reference succeed. Complete the selected Firebase
   rotation including targeted iPad checks, then older-device CPU full/compact
   and feature packs as quota permits.
   Fill every supported-platform row with exact
   PASS/FAIL/ERROR/UNSUPPORTED/NOT_RUN evidence; never equate selected rotation
   completion with whole-release qualification.

The initial harness is usable when its selected bundle runs without the repository,
checks dependencies/models, exercises quick-core public APIs, records proven
backend use, survives independent assertion failures, retains useful crash
evidence, exports valid JSON/JUnit/CSV/basic HTML, and terminates bounded cloud
work. Subsequent milestones expand model/features/platforms; the initial milestone
does not qualify unrun rows. Known product failures remain visible. Full release
readiness still requires the repository's
existing review, platform matrix, affected-family and release gates.

The [current readiness table](cross_platform_validation.md#current-readiness)
records the implementation boundary. Report validation now derives required
cases, expanded configuration and accelerator obligations from the profile;
the journal cannot declare its own exemptions. The next suite acceptance step is
exact-head CI build and portable execution evidence, followed by the missing
critical feature packs. Original-model diagnostics remain private local evidence,
not an extra heavyweight dependency in the default core or CI.

## 13. Remaining work checklist (updated 2026-09-19)

GitHub tracker: [#514](https://github.com/leehack/llamadart/issues/514).

This is the remaining scope from the full plan, not a claim that all rows belong
in the first PR. The initial PR delivers the quick core, reports, portable build
and cloud adapters, NPU diagnostics and the discovered system-message correction.
Its CI and independent review must finish before merge readiness. Device/model
failures remain visible and are investigated separately from harness completion.

| ID | Remaining work | Completion evidence |
| --- | --- | --- |
| R01 | Qualify the PR and bundle workflow on Linux x64, Windows x64 and macOS; build Android APK/test APK, Web and iOS inputs | Exact-head CI green, extracted bundles executable outside a checkout, checksums/manifests retained; independent high-risk review before ready. iOS physical signing remains on the Mac. |
| R02 | Complete C05 thinking/budgets, C07 tool auto/required/none and continuation, C10 stop-marker semantics, C12 guard/recovery subcases, C02 separate Unicode generation and C11 tool-bearing parity | C09's second cycle and C11 native text/thinking parity plus LiteRT Web option rejection are implemented. Catalog 4 now implements Unicode generation, thinking on/off, tool choice/result continuation, stop markers and unloaded-engine guards. Historical catalogs retain their original NOT_RUN records; current exact-model qualification is separate. C11 tool-bearing fixtures, NPU deterministic sampling and GGUF Web worker controls remain unqualified; do not substitute text-only evidence. |
| R03 | Core focused selection and versioned metadata implemented; extend the catalog as future model/media packs land | Schema 2 binds case/feature versions, resolved prompts/tools/predicates and fixture hashes; omitted cases have explicit reasons. `tiny-gguf-lifecycle` and `tiny-gguf-batching` are runnable focused examples. Catalog version 4 imports version-1/2/3 reports against their original definitions. Future pack media hashes and reference qualifications remain with R04/R05. |
| R04 | Add the eleven targeted packs in section 6 | Structured output; state/prompt reuse; embeddings; vision; audio understanding; ASR; TTS; LoRA; speculative decoding; runtime controls; app/device/browser lifecycle. Reuse existing registered tests and keep large models opt-in. |
| R05 | Lock and reference-qualify pack models/media | Primary Qwen3.5 and Gemma 4 GGUF/native/Web bundles; dedicated Qwen3-ASR, Moonshine and Qwen3-TTS exceptions; additional embedding/adaptor/draft fixtures only for their targeted packs; exact revisions/hashes/access and memory limits. Current quick/NPU model locks do not qualify these candidates. |
| R06 | Finish Firebase core device rotation | Isolated GGUF CPU/GPU and LiteRT CPU/GPU on S24, Tab P12, iPhone 16 Pro and SE 3; targeted iPad 10 GPU runs. Existing pilots are partial evidence, not a completed rotation. A05s full/compact, iPhone 8 and Pixel 5 remain later compatibility rows. |
| R07 | Complete S24 NPU qualification, then Tensor G5 | Resolve #513; add N02 Unicode generation/native tokenizer control, compatible S24 CPU Gemma with verified private model transfer, and paired native/public comparison. Require coherent N03 outputs and N04 lifecycle evidence; retain hybrid/unknown placement limits. Pixel 10 needs installed-app vendor-kit/SoC/probe and native/public/CPU runs; a compiled dispatch library is not execution proof. |
| R08 | Fill remaining platform/packaging rows | Android arm64 virtual 4K/16K and separate backcompat, Android x64 emulator, Apple simulators, Linux arm64, Windows arm64, macOS x64 as available; full/compact and lower-ISA physical coverage. Record unavailable hardware explicitly. |
| R09 | Qualify browser and GPU evidence paths | LiteRT GPU adapters with actual driver/delegate proof; Chrome WASM/WebGPU, Safari and Firefox capability rows; a genuine LiteRT Web model bundle and negative native-only contracts. Native Firebase XCTest does not qualify iPadOS Safari. |
| R10 | Exercise the GCE lifecycle and desktop CUDA runs | Historical Linux/Windows bootstrap runs executed GGUF CPU/CUDA/Vulkan and verified cleanup. Still qualify the maintained GCE adapter and reproducible image end to end; bootstrap evidence does not establish that contract or current-head model qualification. Recheck current credit before provisioning. LiteRT desktop GPU is Vulkan/D3D12, not CUDA. No available credit means NOT_RUN, not personal charges. |
| R11 | Complete the required evidence envelope and missing measurements | Model hash/size evidence, portable desktop payload verification, override rejection and collected identity binding are implemented. Preparation stage/byte progress before a model manifest is implemented. Remaining: explicit provenance/availability for artifact and companion hashes, device memory/page size, cold first response, prefill/native TTFT and first-thinking timing where observable. Keep unsupported counters null; local speech reports already record WER/real-time factor, but portable/mobile speech import and quality qualification remain open. |
| R12 | Add aggregate and historical reporting after core evidence is stable | Paired run comparison, device/backend coverage heatmap, comparable-cohort filters, trend and quota views. Existing per-run JSON/JUnit/CSV/HTML and three-sample TPS are usable; a dashboard or performance threshold is not required for the first PR. |

Prioritize R01, then bounded R02/R03 work. R06/R07 use only freshly verified free
Firebase allowance or covered credit; never dispatch the entire rotation at once.
R10 is optional while credit is unavailable. R04/R05 are change-focused feature
coverage, not every-model-by-every-device permutations. R12 visual polish comes
after the mandatory evidence, not before correctness.


The [current Qwen reference diagnosis](cross_platform_validation.md#current-qwen-tool-and-history-reference-2026-09-19)
separates implemented infrastructure from model conformance: C07 passes after
merged runtime fixes, while the original C06 exact-case failure also reproduces
in matched upstream execution. Keep that failure and all unrun device rows
visible; reference agreement does not waive an expected-output predicate.
