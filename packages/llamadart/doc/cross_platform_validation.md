# Cross-platform validation runbook

The first implementation supplies the quick core, shared reports, portable
builds, and explicit Firebase/GCE orchestration. It uses the current checkout's
runtime pins. It does not replace the release matrix, qualify unrun platforms,
or schedule paid work. The broader [validation plan](cross_platform_validation_plan.md)
retains the later feature and device milestones.

Firebase is the primary physical Android/iOS qualification route. The personal
Pixel and iPad are optional debugging devices; the Mac remains the local build,
iOS signing and desktop/browser test host. The next milestone includes Firebase
NPU qualification on Galaxy S24 (Qualcomm SM8650) and Pixel 10 (Tensor G5).
The two SoC-specific model locks and offline input preflight are implemented.
The Android builder now embeds verified model/vendor inputs, and the installed
app checks its SoC before loading. Public-Dart and direct-native control paths
capture per-generation dispatch evidence. S24 execution is verified, but strict
history qualification remains failed; Pixel 10 hardware execution is NOT_RUN.

## Current readiness

The quick diagnostic core is usable; the full platform/release suite is incomplete.
Model-backed Mac, browser and Firebase runs have exposed actual product failures,
and the reports retain failed assertions alongside useful timing and device evidence.
Catalog 4 has 129 passing private harness tests at the reviewed pre-integration
head `b13c545f`; fresh head/base checks remain required after merging main.
Draft [PR #515](https://github.com/leehack/llamadart/pull/515) builds Linux x64,
Windows x64 and macOS arm64 desktop bundles plus Android, Web and iOS inputs.
Follow its current CI for exact-head results; build success and extracted CLI
startup are not model execution or complete device qualification.
Native GGUF Unicode corruption was fixed in merged
[PR #516](https://github.com/leehack/llamadart/pull/516). Earlier failed journals
remain historical evidence; reruns must identify the fixed source commit.

| Area | Current evidence | Remaining qualification |
| --- | --- | --- |
| Quick public API core | Load, Unicode round-trip, raw/chat, history, cancellation/recovery, reload, token bound and short TPS sampling | Catalog 4 adds separate Unicode generation; catalog 5 adds early cancel, GGUF restart/overlap and invalid grammar; retain model/backend failures |
| Report integrity | Canonical profile-derived cases/configuration/proof requirements; missing, contradictory, duplicate and interrupted records fail closed | Paired native/public/reference aggregation and optional trend views |
| Portable apps | Local macOS bundle and Android/iOS/Web paths exercised | Refresh exact-head CI and real portable execution evidence; primary-model/device qualification and iOS signing remain separate |
| Cloud lifecycle | Firebase lifecycle exercised; Linux/Windows bootstrap runs collected and resources deleted; provider failure controls tested locally | Bootstrap execution is not end-to-end qualification of the maintained GCE adapter and custom image |
| Accelerators | GGUF native-log proof, S24 per-generation NPU dispatch evidence and Android LiteRT GPU per-load delegate-initialization evidence | LiteRT GPU per-request execution, iOS/desktop/Web LiteRT GPU proof, Pixel 10 NPU and the remaining device rotation |
| Critical feature packs | Catalog 4 executes Unicode generation, thinking on/off, tool choice/result roundtrips, stop markers, unloaded-engine guards and batching/lifecycle controls; native embeddings have a separate locked pack; catalog 8 adds the structured-output pack | Exact-model/device feature qualification, thinking budgets, tool-bearing batching, broader guards, multimodal and speech qualification |

Do not weaken semantic predicates to obtain a green run. The Gemma original-model
control below passes the strict history predicate; the LiteRT results remain failed.
Three benchmark samples support diagnosis, not a performance regression threshold
or a device ranking. First qualify the portable build workflow, then expand the
critical feature packs with representative locked models before broadening devices.

## LiteRT-LM GPU qualification history

Linux x64 and Windows x64 keep CPU for automatic LiteRT-LM selection; explicit
GPU uses the LiteRT-LM GPU backend, not CUDA.

- Desktop, `v0.17.0-5`: passed on NVIDIA L4 with Qwen3 0.6B (repaired
  tokenizer) and Gemma 4 E2B, on CPU and GPU. Windows used Direct3D 12 with
  driver 582.53; Linux used Vulkan with driver 580.173.02. Checks covered text
  answers, cancellation and reuse without runtime library search-path
  workarounds. This does not establish support for every GPU, driver or model.
  Linux arm64 remains CPU-only.
- Windows x64 GPU, `v0.17.0-5` vs `v0.17.0-6`: `v0.17.0-6` bundles `dxil.dll`
  and `dxcompiler.dll`, which Dawn's D3D12 backend loads at GPU engine
  creation. The published `v0.17.0-5` Windows archive omits them and fails GPU
  engine creation on a clean host. `v0.17.0-6` passed on NVIDIA L4 (driver
  582.53) with Qwen3 0.6B and Gemma 4 E2B: GPU answers matched CPU, and
  cancellation and reuse passed with the runtime directory off `PATH`.
- Linux x64 GPU, `v0.17.0-6`, Mesa llvmpipe only (`Selected adapter: llvmpipe
  ... adapterType=CPU / Software`): loads and answers the first prompts, then
  segfaults in `libvulkan_lvp.so`
  ([#572](https://github.com/leehack/llamadart/issues/572)).
- Pixel 9 Pro: the `v0.17.0-3` Android Dawn correction targets the Mali/Vulkan
  device-loss regression seen with Qwen3 0.6B and Gemma 4 E2B. Qwen3.5 0.8B
  int8 GPU initialization still fails with out-of-memory, also reproduced on
  the previous runtime. An OpenCL diagnostic crashed and is not qualified by
  the Vulkan tests. `v0.18.0` keeps that Dawn build: in the owner's candidate
  runs, upstream's `v0.18` Dawn lost the Vulkan device during Qwen3 0.6B
  inference on a Pixel 9 Pro (API 35, Mali-G715), and Qwen3 0.6B and Gemma 4
  E2B passed with the kept one
  ([owner record](https://github.com/leehack/litert-lm-native/blob/v0.18.0/docs/android_gpu_qualification.md)).
  llamadart at this pin passed both models on that GPU with no Dawn
  validation error ([2026-10-08 runs](#litert-lm-v0180-device-and-gpu-host-runs-2026-10-08)).
- Galaxy S24 (Adreno 750, WebGPU over Vulkan): Qwen3 0.6B cannot run on this
  GPU. One of its weight buffers is 155582464 bytes and the adapter's storage
  buffer binding limit is 134217728 (128 MiB). CPU on the same device is
  correct. `ComputeDevice.auto` selects the GPU for LiteRT-LM on Android, so
  the default load of this model on this GPU is affected. From 0.17.0,
  `auto` retries a GPU engine that fails to start on the CPU and logs a
  warning ([#1034](https://github.com/leehack/llamadart/issues/1034)), which
  covers the `v0.18.0` failure below but not the earlier wrong-text runtimes;
  `ComputeDevice.cpu` skips the GPU attempt
  ([#553](https://github.com/leehack/llamadart/issues/553),
  [litert-lm-native#51](https://github.com/leehack/litert-lm-native/issues/51),
  upstream
  [LiteRT-LM#3866](https://github.com/google-ai-edge/LiteRT-LM/issues/3866)).
  - `v0.17.0-6` through `v0.17.0-8`: Dawn logs `Binding size (155582464) ...
    is larger than the maximum storage buffer binding size (134217728)`, the
    engine is created anyway, and generation returns wrong text (one token
    repeated up to the output limit in the `v0.17.0-8` run).
  - `v0.18.0`: GPU engine creation fails on the same buffer, with the same
    Dawn line, in the owner's Test Lab run of the `v0.18` candidate
    ([owner record](https://github.com/leehack/litert-lm-native/blob/v0.18.0/docs/android_gpu_qualification.md))
    and with llamadart at this pin on the device
    ([2026-10-08 runs](#litert-lm-v0180-device-and-gpu-host-runs-2026-10-08)).
    The model load returns, because llamadart creates the engine at first use,
    and every later case throws: `LlamaUnsupportedException` when
    `ComputeDevice.gpu` was requested, and, before 0.17.0,
    `LlamaModelException` under `auto`. The run ends normally, with no crash
    or process death in logcat.
    `test/integration/backends/litert_lm/engine_create_failure_test.dart`
    pins the `gpu` failure and the 0.17.0 `auto` CPU retry with a runtime
    client that returns no engine. Qwen3 0.6B on the
    CPU and Gemma 4 E2B on this GPU pass on the same device.
  - `v0.19.1-2`: the runtime refuses the GPU engine for this exact model
    file on this driver with `FAILED_PRECONDITION` ("Android GPU safety
    restriction ... Use CPU"), and `auto` retries it on the CPU
    ([2026-11-10 run](#litert-lm-auto-cpu-retry-on-galaxy-s24-2026-11-10)).
  - The runtime keeps its own Android Dawn build: upstream's `v0.17`
    `libwebgpu_dawn.so` is reported to crash in the Qualcomm shader compiler
    on this device
    ([LiteRT-LM#3867](https://github.com/google-ai-edge/LiteRT-LM/issues/3867)),
    and replacing Dawn alone does not change the `v0.18` result.
- Galaxy S24, GPU engine reloads: with `v0.17.0-6` and `v0.17.0-7`, deleting
  a GPU engine kept its graphics memory (`v0.17.0-7`: `dumpsys meminfo`
  Graphics 55 MB before the first engine, 2058 MB after its delete) and lmkd
  killed the app during the second or third engine. `v0.17.0-8` records the WebGPU destroy callback when OpenCL cannot
  load: with its android-arm64 `libLiteRtLm.so`, Graphics returned to 55 MB
  after each of four Qwen3 0.6B GPU engine deletes and open descriptors did
  not grow ([litert-lm-native#59](https://github.com/leehack/litert-lm-native/issues/59),
  [litert-lm-native#67](https://github.com/leehack/litert-lm-native/pull/67)).
  Measured with the `chat-app-litert-reload-memory` scenario under Test Lab
  instrumentation. No other Android GPU, Mali included, and no Android x64
  device has run it. Upstream `v0.18` has the same ordering fix, so `v0.18.0`
  builds without the owner patch; the Qwen3 0.6B row cannot be repeated on
  this device with `v0.18.0`, which creates no GPU engine for that model.
- ARM64 iOS simulator, `v0.17.0-2`: Qwen3 and Qwen3.5 CPU/GPU tests passed;
  Gemma 4 E2B GPU hit a Metal texture-binding limit also present in the
  previous runtime. Simulator evidence does not establish physical iOS GPU
  coverage.

These rows are not claims that every model works on every backend.

## Source and generated artifacts

- `packages/llamadart_validation/`: private Dart suite, locked profiles, desktop
  runner/reporter, JSONL validation and JSON/JUnit/CSV/HTML rendering.
- `example/chat_app/lib/validation_main.dart`: interactive QA app. Run with
  `flutter run -t lib/validation_main.dart` from `example/chat_app`. It lists
  every bundled profile except `npu-*`; an NPU build lists only its own.
- `example/chat_app/integration_test/validation_test.dart`: unattended entrypoint;
  Android instrumentation and iOS XCTest invoke the same controller.
- `tool/testing/validation.dart`: build, local, report, npu-preflight, plan, run, status, collect,
  reconcile, cleanup. Provider helpers live beside it under `tool/testing/validation/`.
- `.github/workflows/validation_bundles.yml`: build-only workflow on relevant PR
  changes and `main` pushes (tiny CPU profile) or explicit manual selection.
  PRs defer the macOS desktop and Android builds to `main` unless they change
  those builds' inputs (`doc/ci_selection.md`). No cloud
  credentials, model runs, VM creation or Firebase submission in CI.
  Desktop jobs extract the transport archive outside the checkout and verify
  command startup and bundled profile discovery without loading a model.
- `.dart_tool/validation/`: ignored local models, bundles and journals. Do not
  commit weights, signing files, account configs, results or credentials.

Use Flutter **3.47.1**, its Dart executable, and Python 3.10+ (Windows: `python`,
other hosts: `python3`). On macOS, Python before 3.13 has no `os.waitid`, so the
command host cannot hold a finished child unreaped while it retires the child's
process group and falls back to signalling that group directly. Android uses the
installed Android SDK/JDK; XCTest needs Xcode, configured local signing and the
owned Mac. gcloud is needed only for provider operations. Normal chat-app behavior is unchanged.
The `local` command records source/runtime pins for diagnostics. Desktop JIT and
Flutter desktop runs cannot qualify without verified portable payload evidence;
use the built CLI bundle for desktop qualification. Plain `flutter run` without
the builder's identity defines also remains diagnostic. Dirty builds retain all
assertion results and metrics; qualification requires clean committed source,
known runtime identities, and verified model hash/size evidence matching the lock.

Desktop launch verifies the bundle inventory, runtime files and environment,
rejects runtime overrides and unlisted loader sidecars, then anchors native cache
discovery to the bundle directory. Caller model/cache/output paths retain their
original meaning. `runtime_payload_verified` and `runtime_bundle_sha256` record
this check separately from accelerator placement. The builder rejects local pub
overrides; explicit native library overrides are rejected by the public adapter.
Dart tooling's JIT library search paths remain usable only for diagnostics.
This is payload integrity verification, not code signing or a signature over an
untrusted producer's report.

## Quick model profiles and cases

| Profiles | Locked fixture | Use |
| --- | --- | --- |
| `tiny-gguf-{cpu,metal,vulkan,cuda}` | stories15M, 98,357,920 bytes | Packaging, native loading, lifecycle; throughput is a tiny-model diagnostic |
| `tiny-gguf-lifecycle` | Same stories15M lock / CPU | Quick core plus the second dispose/load/generate cycle |
| `tiny-gguf-batching` | Same stories15M lock / CPU | Quick core plus C11 default/adjusted/default batching parity |
| `chat-gguf-{cpu,metal,vulkan,cuda,webgpu}` | Qwen3.5 0.8B Q4_0, 563,036,064 bytes | GGUF chat, history, instruction and C07 tool checks |
| `chat-litert-{cpu,gpu}` | Qwen3 0.6B LiteRT-LM, 614,236,160 bytes | Native LiteRT public path; explicit GPU proof remains incomplete |
| `gemma3-litert-cpu` | Gemma3 1B IT q4 LiteRT-LM, 584,417,280 bytes | CPU semantic counterpart to the S24 NPU fixture; gated, supply a local authorized model |
| `decision-gguf-{cpu,metal,vulkan,cuda,webgpu}` | Laya ModernBERT F16, 791,461,088 bytes (`webgpu`: Q8_0, 421,407,968 bytes), plus head, 106,052,840 bytes | `DecisionEngine` parity with Laya 0.3.5; see [Decision profiles](#decision-profiles) |

Full revisions and SHA256 values live in profile JSON. The instruction GGUF is
[ggml-org's Q4_0 artifact](https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF/blob/8fea620810c4afa23dd6443f999a48574c1611a3/Qwen3.5-0.8B-Q4_0.gguf),
so its results are a distinct cohort from the Q4_K_M candidate in the original plan.
Native LiteRT files cannot qualify LiteRT Web; that requires a Web model bundle.
The app reports this explicitly before downloading a native LiteRT fixture in Web.

The Gemma CPU profile uses the same pinned model repository revision as the NPU
profile, with a distinct CPU artifact hash and conversion. It aligns context
1280, four threads, 32 output tokens and thinking enabled. CPU uses the requested
greedy sampler; NPU uses unknown compiled defaults. These are semantic controls,
not an identical-artifact speed comparison. The CPU profile adds the same four
strict history variants as the native NPU diagnostic, producing 17 cases:
canonical, the original literal-system representation, no system and a combined
user prompt. `enable_thinking` is an explicit boolean profile override;
`history_controls` opts LiteRT CPU chat profiles into the extra diagnostic cases.
Other core profiles retain their original inventory and settings.

```bash
dart run tool/testing/validation.dart local --profile gemma3-litert-cpu \
  --model /path/to/gemma3-1b-it-int4.litertlm \
  --out .dart_tool/validation/runs/gemma-cpu-control-1
```

Use fresh output directories for repetitions. The CPU artifact has native context
capacity 4096 but is loaded with the matched 1280 limit. A Mac result is a desktop
semantic control; it does not fill the separate S24 CPU device obligation.
The builder rejects this gated profile for mobile/Web, and remote submission
rejects it before spending quota. Desktop bundles remain usable with `--model`;
private mobile model transfer must be implemented before enabling that lane.

The quick inventory is C01 load/diagnostics, C02 Unicode tokenize/detokenize,
C03 raw generation, C04 hello/arithmetic and C06 multi-turn history for chat
fixtures, C08 cancellation/control/recovery and early cancel, C09 dispose/new
engine/reload, C10 one-token limit, C12 missing-model rejection/recovery, and
B01 one warmup plus three measured generations. GGUF profiles also run C08
restart/overlap and C12 invalid grammar
([catalog 5](#catalog-5-cancellation-grammar-and-tool-cases)). Independent
assertion failures do not suppress later metrics; load failure or timeout
prevents unsafe later inference.

Sampling is temperature 0, seed 1, top-k 40, top-p .9, repeat penalty 1.1,
context 1024, four threads, 32 generated tokens, thinking disabled, prompt reuse
disabled. Case overrides (one-token limit and 256-token cancellation) are recorded.
C08 compares the same prompt against an uncancelled control; the pinned WASM
delegate's explicit cancellation AbortError is also recorded as interruption evidence. Merely calling cancel
is not a pass; missing interruption evidence is NOT_RUN. Case timeouts are 60s;
disposal has a 10s bound and unresolved work cannot report successful cleanup.
A LiteRT CPU or GPU profile may set `engine_create_case_timeout_ms`
(60000 to 180000), which replaces the 60s bound only for the cases that include an engine create:
the first case executed after C01.load (LiteRT defers creation to first use) and
C09.reload, C09.reload.second, C12.guards and C12.recovery. A timeout there still
records `case_timeout` with the applied `timeout_ms`. `qwen35-litert-gpu` sets
it to 120000: on macOS arm64 (M4 Max, LiteRT-LM 0.17.0-6) those cases took
48.7 to 51.9 s, about 32 s of it WebGPU shader initialization for the one engine
create, so 120 s is 2.3 times the slowest measured case (#521).
`qwen35-litert-cpu` sets it to 180000, the maximum: on Linux arm64 t2a-standard-8
(Neoverse-N1, LiteRT-LM 0.18.1-2) those cases took 75.4 to 80.5 s over eight runs
with cold and warm page cache, against 21.2 to 22.9 s on c4a-standard-8, so 180 s
is 2.2 times the slowest (#760). On t2a, `gemma4-litert-cpu` engine creates took
at most 20.8 s and the first `chat-litert-cpu` one 2.6 s, so both keep 60 s; the
gated `gemma3-litert-cpu` was not measured.
The field is part of the profile hash.
Native Flutter model acquisition has a ten-minute deadline within the
18-minute integration test and 20-minute Test Lab execution limits. CLI downloads
retain their five-minute default. Download deadline failures report received and
expected bytes, remove partial weights and never become inference/TPS samples.

Prompts, regex expectations, exact output/thinking, ordered terminal case IDs,
configuration hashes, model hashes, source/runtime pins and environment all appear
in the journal. The raw tiny fixture does not claim chat capability.

### Decision profiles

`decision-gguf-{cpu,metal,vulkan,cuda}` lock the `fr0stbit3/laya-gguf`
`laya-F16.gguf` encoder and `decision-gguf-webgpu` its `laya-Q8_0.gguf`, both
model kind `decision`, and, under `decision.head`, the `laya-head.safetensors`
head. An optional `decision.config` lock takes the
same fields for heads without embedded config. They load with context 512 and
four threads, run `C01.load`, then:

| Case | Public API | Passes when |
| --- | --- | --- |
| `D01.head` | `DecisionEngine.capabilitiesFor`, `DecisionEngine.attach` | Supported; head device `CPU` for the CPU profile, otherwise not `CPU` and the backend name contains the profile backend |
| `D02.tokenizer` | `LlamaEngine.tokenize(addSpecial: false)` | Exact ids for all 97 reference texts |
| `D03.logits` | `LlamaEngineBackendHooks.loadDecisionHeadBackend`, `runDecisionBackend` (`package:llamadart/backend.dart`) | The 24 reference sequences, run in one call, give every marker logit within 0.25 |
| `D04.answers` | `systemOne`, one call per reference case (15 calls, 24 questions) | Answers match, as below |
| `D05.batch` | `systemOneBatch` with the 15 requests | Answers match, as below |
| `D06.reload` | `dispose`, `attach`, `unloadModel`, `setModel`, `attach` | `LlamaStateException` after the dispose and after the unload; the first case's answers match after each reload |
| `D07.guards` | `attach` with a missing head, `systemOne` with U+0000 in the state | `LlamaModelException`, `LlamaDecisionException`, then the first case's answers match |

Answers match when the type, probability key order, model `laya-rl-agent`
and `usage.input_tokens` are exact; confidence, act probability, each
probability and noul are within 0.05; the score is within 0.1; and the choice
is the reference's unless the reference top-2 gap is within 0.05. These are the
`decision-model-smoke` defaults. Q8_0 rounding alone can use most of them, so
native profiles use F16, whose drift stayed within a quarter of each tolerance
in the runs below. The reference is
`packages/llamadart_validation/assets/decision/laya_0_3_5_reference.json`, the
decision E2E fixture, pinned by SHA256: a missing or altered copy makes every
decision case ERROR. Chat cases are unselected with
`decision_model_has_no_text_generation`. Decision catalogs require the current
catalog version and journal schema 2; chat catalogs are unchanged.

GGUF accelerator proof for these profiles expects two model loads (`C01.load`,
`D06.reload`) and six compute buffers: one per model load plus one encoder
context per successful head load (`D01`, `D03`, two in `D06`). Every head
device must name the backend, such as `MTL0`. Reports also require the verified
head hash and size. The Web host keeps no native log, so `decision-gguf-webgpu`
reports cannot verify placement and do not qualify.

Desktop, Android and iOS hosts download and verify the head beside the model,
each file within the host's download deadline. The Web host verifies both in
the page and passes the head URL to the bridge. Backend `webgpu` loads with
every layer on WebGPU and runs only on the Web host and in Web bundles. It
keeps Q8_0 because each F16 model load in the browser takes 45 to 51 s, which
leaves `D06.reload` no margin under the 60 s case deadline. The Web host and
Web bundles reject every other decision profile: decision cases on the WASM
CPU exceed the case deadline. GCE accepts `decision-gguf-cuda`.
`validation.dart coverage --use-case decision` lists the rows; Web WASM is
`UNSUPPORTED`.

Observed on an Apple Silicon Mac shared with other work. With `laya-F16.gguf`
at load averages of 10 to 14, `local` CPU and Metal runs passed all eight
cases, and Metal verified placement. Worst logit/probability/score differences
were 0.052/0.011/0.010 on the CPU and 0.012/0.003/0.003 on Metal, against
0.142/0.036/0.061 and 0.164/0.044/0.025 with `laya-Q8_0.gguf` (load averages
15 to 210). No `local` run qualifies, since it is not a portable bundle.

In headless Chromium with WebGPU on Metal and the bridge assets from
[#665](https://github.com/leehack/llamadart/pull/665), every
`decision-gguf-webgpu` run kept the head on `WebGPU: WebGPU`. With Q8_0, two
runs at load averages of 6 to 28 passed with worst differences of
0.164/0.044/0.025 and `D06.reload` at 25 and 32 s; a third, at 33 to 40,
passed with model loads of 33 and 36 s and `D06.reload` at 49 s. With F16, at
14 to 17, worst differences were 0.017/0.005/0.001, but model loads took 45 to
51 s: `D06.reload` passed at 57 s in one run and hit the 60 s case deadline in
the other. On the WASM CPU, in builds without the Web host's rejection, F16 (at
33 to 75) and Q8_0 both stopped at `D03.logits` on the 60 s deadline. With a
20-minute timeout, Q8_0 took 77 to 86 s for each of `D03` to `D06`, and `D04`
and `D05` failed on `plain_text/urgency5` (probability 0.0628, score 0.1224).

```bash
dart run tool/testing/validation.dart local --profile decision-gguf-metal
```

### Multimodal embedding pack

[Issue #1194](https://github.com/leehack/llamadart/issues/1194) adds a separate
embedding-only inventory under catalog 5. `embedding-gguf-cpu` runs on native
desktops, Android CPU and iOS CPU. `embedding-gguf-metal` is the macOS/iOS Metal
counterpart, following the existing backend-specific profile convention. Both
use context/batch/microbatch 2048, four threads, no generation or benchmark cases,
and the same immutable model/projector pair:

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| `embeddinggemma-2-BF16.gguf` | 557,950,176 | `68bae29d62fb8c7d23e98d21fd4662753ddd636e6b62b8a70dfe059a9844f216` |
| `mmproj-embeddinggemma-2-BF16.gguf` | 982,074,784 | `d2033b3cd0223cfb2e7a2b50dc80a664c78c816d375f5b017ec3ef80ee0bc766` |

The profile URLs pin
`ggml-org/embeddinggemma-2-GGUF@bfcd298762cc34d0357ece5ebdd31791a3a374d8`.
Hugging Face API/LFS metadata was inspected without downloading weights. A
matched Q8_0 pair exists (864,676,480 bytes total); BF16 was chosen to generate
independent CPU references from the available local files without downloading
weights. Q8_0 needs its own reference cohort; it must not reuse BF16 vectors.

| Case | Contract |
| --- | --- |
| `C01.load` | Public model/projector load and diagnostics |
| `E01.capabilities` | `embeddingCapabilities` advertises text/image/audio and `mediaUnsupportedReason` is null |
| `E02.text`, `E03.image`, `E04.audio` | One normalized vector matches its native CPU reference |
| `E05.mixed` | Text/image/audio interleaving matches its reference (one image encode) |
| `E06.batch` | `embedContentBatch` returns audio/text/reversed-mixed/audio, checking the other media order and a repeated item (one image encode) |
| `E07.normalization` | Unit normalized audio output; non-unit raw audio output normalizes to the reference |
| `E08.guards` | Video input, an image without a source and reserved `<__media__>` with media throw `LlamaUnsupportedException`; text reuse succeeds |
| `E09.cancel.before` | Immediate `cancelGeneration` before backend SPI dispatch; typed cancellation and text/media reuse |
| `E10.cancel.after` | Cancellation after backend SPI dispatch while pending; typed cancellation and text/media reuse |

Cancellation uses a forwarding backend at the exported SPI to observe dispatch;
it does not claim that the worker has started native encoding. The latter is
synchronous and cannot be forcibly interrupted. Both cases await settlement,
require a `LlamaInferenceException` containing cancellation, cap latency at 5 s,
and compare subsequent text/image calls with the CPU references. If work already
completed or the dispatch precondition was missed, the case is NOT_RUN and the
run cannot qualify.

The deterministic PNG checkerboard, PCM WAV square tone, native C++ reference
program, generation procedure and measured spread are in
[the version-one fixture README](../packages/llamadart_validation/assets/embeddings/README.md).
The five 768-dimensional CPU vectors use pinned upstream headers and the
published v0.7.0-1 macOS arm64 archive/dylib, independently of Dart. The fixture
README records their reproducible hashes; hook-processed dylib bytes are not
portable runtime identities. Separate CPU and Metal threshold entries both
require cosine ≥ **0.999**, max-abs ≤ **0.01**, allowing roughly 10x/6x headroom
over measured kernel-path error. The original Metal audio cosine was 0.999900635;
fusion/concurrency and CPU thread-count measurements and negative controls are
recorded in that README. CPU one/four-thread vectors reproduced the reference
exactly; Metal default and concurrency-disabled audio had cosine
0.999900635/max-abs 0.001568219, while fusion-disabled and both-disabled had
0.999906460/0.001644426. LAST pooling (cosine 0.867617), missing normalization
(max-abs 490.59) and swapped media order (cosine 0.988408, max-abs 0.018698)
fail these gates; a mismatched projector hash errors before inference.

Embedding Metal placement counts real contexts rather than compute-log lines:
one llama context and one full positive offload record per expected load, plus
exactly two MTL0 projector contexts (`gemma4v`, `gemma4a`). Every complete
`sched_reserve` and projector `reserve_compute_meta` block needs exactly one
positive MTL0 allocation; positive CPU scratch buffers may accompany it. All
compute records must be attributed to those blocks. Pooled embedding toggles
change the graph shape and reserve the same context again, so the number of
complete reservations is request-dependent, with no fixed ceiling. Unknown,
extra or missing contexts, malformed/unattributed records, CPU-only blocks,
wrong devices, zero sizes and partial/zero/missing offload remain unverified.
Non-embedding placement rules and effective-config hashes are unchanged.

Both embedding profiles lock `embedding.case_timeout_ms: 300000`, bound into
their effective configuration hashes and applied to every selected case,
including load. Existing non-embedding profile hashes/deadlines are unchanged.
Each of E05/E06 encodes one image; E07 uses audio. The 224×224 PNG actually
encodes at 432×432; 768×768 is the projector's warmup allocation. CPU peak
footprint is approximately **1.4 GB**, with **1.9 GB max RSS**; the projector
is not mmapped. Choose **≥6 GB RAM** devices for Firebase runs. The 300-second
deadline accommodates slower CPUs but does not prove a particular phone passes.
The prior Web audit's floor is not transferred to an unrun pack.

All three fixture files have compiled hashes in `case_catalog.dart`. They are
verified before every embedding case, bound through each case's fixture hash and
`feature_id: embeddings`, and included in the canonical catalog hash. Missing or
changed inputs/references cause ERROR; the reporter independently rechecks PASS
metrics, capability/error/cancel evidence and verified projector preparation.
Historical and other model catalogs keep their original inventories.

```sh
# Existing files are streamed and SHA256/size-verified; no copy or download.
dart run tool/testing/validation.dart local --profile embedding-gguf-cpu \
  --model /path/to/embeddinggemma-2-BF16.gguf \
  --projector /path/to/mmproj-embeddinggemma-2-BF16.gguf \
  --out .dart_tool/validation/runs/embedding-cpu
# Omit supplied paths only when explicitly allowing the two locked downloads.

# Build without submitting; Flutter assets include the reference and media.
dart run tool/testing/validation.dart build --target android \
  --profile embedding-gguf-cpu --out .dart_tool/validation/bundles/android-embedding
dart run tool/testing/validation.dart build --target ios \
  --profile embedding-gguf-metal --out .dart_tool/validation/bundles/ios-embedding
```

Use the normal Firebase plan/run/collect/cleanup procedure below, with one
explicit device and the existing quota/budget receipts. For example, `plan
--target firebase-android --config <receipt-config> --bundle
.dart_tool/validation/bundles/android-embedding --out <new-plan>`; only a separately
authorized `run --plan <new-plan>` submits. A device downloads and verifies both
locked files under the existing ten-minute per-artifact deadline. iOS CPU uses
`embedding-gguf-cpu`; Metal requires the usual bound native offload log. No
Firebase device, Windows/Linux host or portable bundle is qualified by the Mac
JIT smoke. LiteRT-LM has no pack profile/reference adapter, and Web builds reject
this native pack before preparation; their pack coverage remains **NOT_RUN**
with those explicit reasons. A directly invoked shared runner on Web journals
all pack cases as NOT_RUN without loading a model.

Release 0.15.0 runs passed 11/11 on macOS CPU and Metal, Linux x64 CPU and
Windows x64 CPU (GCE), Galaxy S24 CPU and iPhone 16 Pro CPU.

### Focused selections and replay metadata

The shared runner accepts three profile selections:

- `quick`: the original short core and one three-sample benchmark series.
- `focused`: the quick core plus cases matching the profile's nonempty, unique
  `focus_features` list. Valid IDs are `text`, `unicode`, `thinking`, `history`,
  `tools`, `streaming`, `batching`, `lifecycle`, `guards`, `performance` and,
  from catalog 8, `structured_output`, and from catalog 9, `tokenization`.
  Text/history/performance are already
  covered by the applicable quick cases.
- `release`: every current extended core obligation, including unfinished cases.

For example, `"selection": "focused", "focus_features": ["streaming", "tools"]`
adds C07 tools, C10 stop markers and C11 batching. Catalog 4 executes C07;
catalog 3 executes C10 control/stop/recovery, and C11 executes the parity or
rejection contracts below.
`tiny-gguf-lifecycle` is a runnable focused CPU profile: it adds
`C09.reload.second` after the first reload, invalid-input recovery and benchmark.
It is available in the QA app, portable bundles and manual build workflow:

```bash
dart run tool/testing/validation.dart local --profile tiny-gguf-lifecycle \
  --out .dart_tool/validation/runs/tiny-lifecycle
```

`tiny-gguf-batching` selects C11 without also selecting the separate stop-marker
case. It runs the same short prompt with default worker thresholds (8 pieces /
512 bytes), then 1 piece / 1 byte, then defaults again. Content, thinking and
finish reasons must match, every stream must complete in order, and the recorded
options must match each trial. Chunk counts may differ. All three requests retain
output, effective batching thresholds and timing/TPS; they are parity trials,
not extra benchmark samples.

LiteRT Web separately checks that each nondefault option produces a named
`LlamaUnsupportedException` before inference, then verifies default-request
recovery. This is negative-contract coverage, not native batching qualification.
GGUF Web, direct-native controls and NPU runtime-default sampling remain NOT_RUN
for C11. Tool-bearing parity requires the qualified C07 fixture; unexpected tool
emissions remain visible and cannot pass the text/thinking case.

Journal/report schema 2 exports catalog version 2, per-feature and per-case
versions, resolved synthetic prompts/tool schemas/predicates, selected cases and
omission reasons. The runner reads the same compiled fixture definitions that it
exports; model-specific text/predicate overrides are explicit hashed profile
fields. Each terminal record binds its case version and fixture hash. Reports
reject missing or rehashed conflicting catalog data, and HTML shows selection
and unselected cases separately from verdicts. Future media/model packs still
need their own fixture locks and reference qualification.

Schema-1 journals remain readable with their original case inventory; missing
catalog metadata stays unavailable. Catalog-version-1 schema-2 reports are also imported against their original
definitions, with C11 still unimplemented. Unknown versions or new batching
selections claiming the old catalog fail closed. A legacy report is not evidence that the
newer extended selection ran. Focused selection requires schema 2.

Thinking budgets, tool-bearing batching, expanded unsupported guards,
multimodal/speech packs, embedding device qualification and full browser/device
rotation remain subsequent work. The native embedding pack above now supplies
its locked fixtures and executable cases. NPU requires the verified Android packaging
described below; selecting `npu` alone cannot supply vendor libraries or evidence.
Catalog 4 executes all currently selected core release cases. This does not
qualify the broader planned feature packs or historical runs: existing journals
retain their original catalog and NOT_RUN results. Direct-native controls keep
public-only feature cases NOT_RUN.

## NPU input preparation

`npu-qualcomm-sm8650` and `npu-tensor-g5` are **unqualified candidate locks**
with opt-in Android build support. Each records Gemma 3 1B IT revision
`a6306a4e292016480083b73b8dc6f3f939ae04c3`, the SoC-specific file/hash/size,
context 1280, max output 32 and required library architectures. The Qualcomm
file is 690,094,080 bytes; Tensor G5 is 1,678,542,365 bytes. Model access is gated:
stage an authorized copy locally without embedding tokens or signed URLs in
the APK, kit manifest or report. The preflight never downloads a model.

```sh
dart run tool/testing/validation.dart npu-preflight \
  --profile npu-qualcomm-sm8650 \
  --model /path/to/Gemma3-1B-IT_q4_ekv1280_sm8650.litertlm \
  --kit /path/to/qualcomm-kit \
  --out .dart_tool/validation/npu-preflight.json
```

Omit `--model` or `--kit` to obtain the missing-input inventory. `--out` must be
a new file. The command writes hashes, sizes, SoC/runtime identities and checks;
it does not export supplied local paths. Exit 1 and `status: NOT_RUN` remain
intentional even when `inputs_verified: true`: file integrity is not native
execution or qualification. It creates no remote resources and uses no quota.

The kit contains flat regular library files and `npu-kit.json` with schema 1,
`target`, `runtime_tag`, `litert_revision`, `dispatch_header_sha256`, and a
`libraries` map from basename to `sha256`/`bytes`. Host libraries must be
AArch64 ELF64; the Qualcomm V75 skeleton is Hexagon ELF32. The lock includes
QAIRT 2.47.0.260601 host/DSP hashes, audited vendor dispatch hashes and the
matching diagnostic proxy hashes. Rebuilding a proxy requires reviewing and
updating its lock; a caller-supplied manifest cannot bless a different probe.
An older prebuilt, different SoC, tampered file, missing file or symlink fails
the input check. Dynamic dependency resolution still needs final-APK/device
verification; this inventory check does not execute or resolve a shared library.
The inspected S24 stub needs device `libcdsprpc.so`; its DSP skeleton needs
Hexagon `libc++.so.1` and `libc++abi.so.1`. The 2026-09-17 installed S24 pilot
initialized and executed the NPU through both adapters, establishing access for
that exact device/runtime/kit combination. Other targets remain unverified.
Android host libraries cannot substitute for DSP libraries with the same basename.

For runtimes `0.17.0-3`, `0.17.0-5` and `0.17.0-6`, the actual LiteRT dependency is
`9fe5be45564c868408e6514c8aabb83e211a0911`. Its dispatch header adds `get_hooks`
to the nested interface relative to LiteRT v2.2.0 while retaining the same API
version. The version string alone cannot establish table-layout compatibility.
The native owner repository's diagnostic proxy is built against the exact
headers and accepts only the audited same-source vendor binaries. It preserves
vendor calls and exports lifetime counters for synchronous completions/failures,
async submissions/failures and synchronous calls in flight. Async submission is
not completion; positive counts establish some NPU work, never all-NPU placement.

The builder stages the model as an uncompressed APK asset and the verified kit
as extracted native libraries. The final APK checker streams every model/library
entry and rechecks sizes/hashes; remote upload repeats this check. The Android
host checks `Build.SOC_MODEL`, API and ABI before loading, checks installed library
hashes, copies the model to the app's private cache, and verifies its hash again.
It declares the required device library (`libcdsprpc.so` or
`libedgetpu_litert.so`) and configures the app-local DSP search directory. These
checks cannot prove that the Firebase sandbox grants access to its device driver.
Use the dated device results below for actual execution evidence.

Build separate bundles from clean committed source; each contains interactive
`qa-app.apk`, unattended `app.apk` and instrumentation `test.apk`:

```sh
dart run tool/testing/validation.dart build --target android \
  --profile npu-qualcomm-sm8650 \
  --kit /path/to/qualcomm-kit \
  --model /path/to/Gemma3-1B-IT_q4_ekv1280_sm8650.litertlm \
  --execution-path native_c_api \
  --out .dart_tool/validation/bundles/s24-npu-native
# Repeat with --execution-path public_api and a separate output directory.
```

These locally staged bundles contain authorized model weights and licensed vendor
libraries. Keep them private; the public CI bundle workflow does not accept NPU
kit/model inputs. No Hugging Face token, signed download URL or SDK credential is
packaged. Kit `license-*` files are retained in the APK.

The direct native control bypasses `LlamaEngine` and its backend/worker bindings,
calling the pinned C API on a dedicated isolate. It now runs twelve cases: load,
hello, arithmetic, four history controls, reload, warmup and three throughput
repetitions. The history controls use the exact, case-sensitive `K7Q2` oracle
(see the 2026-09-23 quantization control) and compare
canonical native system/history seeding, the former public path's literal JSON system
content, history without a system message, and one combined user prompt. Each
records the JSON bytes supplied to the C API, response, timing and dispatch
counters. The native system setter receives JSON content, not a complete message
object; the literal-JSON variant deliberately preserves the original incorrect
public serialization for regression diagnosis. Setup timing and its dispatch snapshot are separate
from send/decode timing; total dispatch proof includes preface initialization.
It uses the
same Gemma artifact, dispatch kit, context 1280, four threads and per-request
output cap 32 as the public LiteRT service. The public NPU runtime skips session
sampler overrides, so both paths retain compiled model/runtime defaults. Requested
seed/temperature/top-k/top-p remain recorded, but effective NPU sampling is
explicitly unknown; these runs cannot claim seeded deterministic sampling.
Gemma keeps the native conversation default for thinking; the Qwen pilot's
explicit thinking-disable setting is not reused. The public NPU path runs the
14-case quick chat inventory, including Unicode tokenization, raw/history,
cancel/control/recovery, one-token limit and missing-model recovery.

Every generation records before/after probe counters. The reporter recomputes
deltas and rejects absent, reset, failed, in-flight or async-only proof. Positive
proof means **NPU participation; CPU partition coverage unknown**, never all-NPU.
Native controls are labelled separately and do not qualify the public Dart path.
Native decode TPS/token counts and native TTFT are separate from wall throughput;
the blocking native control cannot observe visible-answer TTFA, so that field
is null. Warmup is retained but excluded from the three-sample charts.

Main `21135e37dadf60882ea427db6078ccc90f84a28a` adopts runtime `0.17.0-5`.
Its published manifest retains upstream LiteRT-LM
`e9fd8c53ff968071774206163027dd84bedfe925` and the same LiteRT dependency above.
The NPU input guard now requires this runtime and a separately recorded kit
audit; preserve the old kit and reports. The new runtime's desktop linkage fixes
do not establish that Gemma NPU history is fixed. The native repository's
[Qwen tokenizer repair](https://github.com/leehack/litert-lm-native/blob/3eb4079397d19e2058e176fcdb5ab15b28a70ad0/docs/qwen3_tokenizer_repair.md)
creates a distinct model artifact; the locked original Qwen fixture is unchanged.

Use the normal Firebase `plan`/`run`/`collect`/`cleanup` flow below with the exact
S24 or Pixel 10 profile/device pairing. Run the native control first and stop if
it cannot initialize. Do not automatically submit both bundles or bypass the
selected Spark quota or Blaze budget guard. The compatible S24 CPU Gemma semantic control, separate Unicode
generation fixture and aggregate paired-control qualification remain future
work; the existing Qwen CPU retry is not a matched Gemma control. A per-run green
report is not completion of the full NPU pack. The `validation-harness` row covers
the model-free identity/proof/input checks and APK tampering tests.

## Build and run

```sh
# Model-free safety and report regression tests.
dart run tool/testing/run_local_e2e.dart --scenario validation-harness

# Uses a shared verified model cache; creates a fresh output directory.
dart run tool/testing/validation.dart local --profile chat-litert-cpu

# Build on each native OS/architecture; weights are downloaded when running.
dart run tool/testing/validation.dart build --target desktop --profile tiny-gguf-cpu --out .dart_tool/validation/bundles/desktop
dart run tool/testing/validation.dart build --target android --profile tiny-gguf-vulkan --out .dart_tool/validation/bundles/android
dart run tool/testing/validation.dart build --target web --out .dart_tool/validation/bundles/web
dart run tool/testing/validation.dart build --target ios-inputs --out .dart_tool/validation/bundles/ios-inputs
# On the owned Mac with existing local Xcode signing configured:
dart run tool/testing/validation.dart build --target ios --profile tiny-gguf-cpu --out .dart_tool/validation/bundles/ios
```

Android bundles run Gradle (`./gradlew`, or `gradlew.bat` on Windows) with
`JAVA_HOME` set to the JDK Flutter builds with: `flutter config --jdk-dir`,
else the `Java binary at:` JDK that `flutter doctor -v` reports (such as the
Android Studio JBR), else `JAVA_HOME`. Like Flutter, this replaces a different
`JAVA_HOME`. The build fails before compiling when none is a JDK.

Desktop bundles include `bin/llamadart-validate`, `bin/llamadart-report`, native
code assets, profiles and remote wrappers.
The hidden `.dart_tool/llamadart/litert_lm/` directory inside desktop bundles
contains the pinned LiteRT runtime, re-extracted from its SHA256-verified archive.
Preserve it when copying or extracting a bundle; the public runtime discovers it
relative to the executable. This avoids depending on the build machine's cache.
Windows arm64 bundles retain GGUF only; the manifest records LiteRT unavailable,
and an explicitly selected LiteRT build profile is rejected on that ABI.
Run outside the repository:

```sh
bin/llamadart-validate --profile tiny-gguf-cpu --environment-file environment.json --out results
bin/llamadart-report results
# Give the launcher its redirected native stderr so its exit code includes
# the same required accelerator proof as the subsequent reporter:
bin/llamadart-validate --profile tiny-gguf-cuda --environment-file environment.json --out results --native-log native.stderr.log 2>native.stderr.log
# Explicit GGUF accelerator evidence can also be derived after execution:
bin/llamadart-report results --native-log results/stderr.log
```

Windows executables have `.exe`. Keep the complete bundle layout. GitHub artifacts
contain `bundle.tar.gz` so executable permissions survive download; extract it
before use. Bundle manifests enumerate every shipped byte and record build OS/ABI,
SDKs, source commit/dirty state, native pins and the compiled mobile profile.
Resolved suite/app dependency locks are included as provenance too.
Remote dispatch rejects changed, dirty, wrong-OS or wrong-profile bundles.

Android produces `qa-app.apk` for interactive installation and a matched
`app.apk`/`test.apk` instrumentation pair. These are Debug builds, explicitly
labelled; do not compare their TPS to Release builds. Both native runtimes are
bundled, making APKs larger than a single-runtime deployment.

`ios-inputs` contains committed source, no signing credentials. `ios` invokes
`build-for-testing` and packages `tests.zip`; signing must already be configured. The unique existing project team is applied
to the test target too; use `--team TEAMID` when selecting another configured team.
Building the iOS bundle does not submit a test; use the explicit Firebase
`plan`/`run` steps below. Web builds use the maintained bridge-staging script. Serve with isolation
headers, for example:

```sh
python3 tool/testing/serve_static_with_headers.py --directory .dart_tool/validation/bundles/web --port 7367
```

The Web host hashes each model and decision file as it streams, so a file
larger than one browser buffer (about 2 GiB) verifies. A status other than
200, more or fewer bytes than locked, a SHA256 mismatch or an interrupted
stream fails preparation. The bridge then downloads the URL again itself.
`chat-gguf-webgpu` loads every layer on WebGPU and, like
`decision-gguf-webgpu`, runs only on the Web host and in Web bundles; other
bundles, Firebase and GCE reject it before any build, download or
submission. The Web host does not capture the bridge's native log, which
goes to the browser console, so its reports cannot verify placement and do
not qualify.

Observed on an Apple Silicon Mac in headless Chromium with WebGPU on Metal and
the pinned bridge assets, at load averages of 7 to 57, with catalog 4 and
`quick` selection (before this profile selected `tools`): a clean
`chat-gguf-webgpu` bundle passed 12 cases; `C06.history` failed (`17` for `cedar17`) and
`C10.limit` was NOT_RUN. The bridge capped Qwen3.5 0.8B at 2 WebGPU layers.
A `gemma4-gguf-webgpu` draft (those settings with the Gemma 4 GGUF) verified
its 3,043,932,288-byte model in 70 to 71 s, but `C01.load` hit the 60 s case
timeout. A dirty build with a 10-minute case timeout passed 13 cases with
36/36 layers on WebGPU; its three loads took 218 to 264 s each, and the
bridge reported `model_cache_store_failed`. There is no Gemma 4 WebGPU
profile until its loads fit a case bound.

## Firebase setup, submission and collection

The [device rotation and NPU cases](cross_platform_validation_plan.md#8-firebase-device-selection-and-free-rotation)
include S24, Tab P12, iPhone 16 Pro, iPhone SE 3, Pixel 10 and iPad 10. The planned
initial selection is 16 CPU/GPU core executions, six NPU reference/public-Dart/CPU
control executions and two targeted iPad GPU/lifecycle executions: **24 across
at least seven Spark quota days**, with at most four planned physical executions/day.
NPU submissions require the verified APK packaging and preflight first. iOS cases
cover CPU/Metal/LiteRT GPU; Apple NPU is not exposed by the current backend.
Native XCTest coverage does not qualify Safari/iPadOS browser execution.

By default, use an explicitly selected **unbilled Spark project** and account. Preflight checks
billing is disabled and the selected physical model/OS exists in the live catalog.
Pick one row per submission; never use an implicit device matrix. Check available
physical quota in Firebase before creating a receipt. Receipt evidence expires
after 15 minutes. The local journal permits at most four physical submissions in
a rolling 24 hours; other clients still share the provider's quota.

Copy `tool/testing/validation/firebase.example.json` to an ignored local path and
fill account, project, exact device/OS and a freshly checked quota receipt.

```sh
dart run tool/testing/validation.dart plan --target firebase-android --config .dart_tool/validation/firebase.json --bundle .dart_tool/validation/bundles/android --out .dart_tool/validation/plan.json
dart run tool/testing/validation.dart run --plan .dart_tool/validation/plan.json
```

Use `firebase-ios` with the signed `ios` bundle. Plan creation is local/read-only;
`run` rechecks identity, budget evidence and live provider state before submission.
The CLI uses explicit `--project` and `--account`, one execution capped at 20 minutes, no
flaky retries and no video. It records the matrix ID, polls terminal state, copies
the default Test Lab results, then verifies completion or cancellation. It does
not enable billing or create a custom result bucket.

### Explicit Blaze runs

Blaze is an opt-in mode for separately authorized runs. Copy
`tool/testing/validation/firebase_blaze.example.json` to an ignored local path.
The operator links billing separately; the runner never upgrades a project.
Preflight requires `billing_mode: "blaze"`, an enabled billing link to the exact
`billing_account`, and current physical execution quota. Spark plans still reject
billed projects. A quota receipt proves execution capacity, not free minutes.

Supply a fresh `budget` receipt with an authorization/pricing evidence reference,
fixed `window_start`, `expires_at` no more than 24 hours later, and positive
`maximum_run_usd` and `maximum_total_usd`. At least one hour must remain before
dispatch. Refresh `verified_at` within 15 minutes of each run, without moving
the authorized window or increasing its cap. All amounts are USD: record any
conservative conversion, tax and auxiliary-cost allowance in the evidence.
Do not copy a CAD credit balance into `available_usd`. Decimal USD reservations
round fractional cents up and the batch cap rounds them down; exact cent values
stay exact (two $1.10 reservations fit a $2.20 cap). Existing journal reservations
remain unchanged when a later run checks the cap.

`funding: "credit"` also requires a fresh credit receipt that verifies Test Lab
eligibility, at least twice the entire batch budget available, and two hours
before credit expiry. A balance alone or a scope of "certain usage" does not
establish eligibility. `funding: "approved_charges"` is only for an explicit
user authorization covering out-of-pocket charges; it is not implied by having
a payment method or requesting a credit-funded upgrade.

For free execution on Blaze, select `funding: "free_allowance"` and supply a fresh
`free_allowance` receipt (`verified_at`, `evidence`, `remaining_physical_minutes`).
Verify the full project inventory, including other clients and pre-upgrade use;
round each physical test's **test-process duration** up to whole minutes. Queue,
installation and result-collection durations are not the billable test duration.
Subtract this usage from the published 30-minute daily physical allowance. Unknown
or active executions prevent relying on that calculation. The receipt must be
within the budget window. This mode needs no assumed credit eligibility or paid
authorization; gross USD reservations remain for traceability.

Set `test_timeout_minutes` to an integer from 1 to 20 (default 20). Verified free
minutes must cover that timeout plus a one-minute rounding reserve. The journal
also reserves minutes for submissions made after the receipt was checked, so
reusing a receipt cannot spend those minutes twice. Refresh the full project
inventory after each completed execution before reclaiming unused reserved time;
do not simply update its timestamp. These controls cannot exclude submissions
from another client after the check, so keep this dedicated project serialized.

The journal reserves the full per-run estimate before any submission, rounding
up to cents, and rejects runs exceeding the batch cap. Earlier Blaze submissions
for the same project within that window consume the cap even when failed or
cancelled; preflight failures do not. An uncertain submission still blocks all
new remote work until reconciled. Keep one shared run journal for the batch;
do not delete it or move the window to reset the allowance.

Each run remains one physical device, at most a 20-minute provider timeout and zero
flaky retries. The estimate must cover at least the full timeout at the current
[$5/device-hour rate](https://firebase.google.com/docs/test-lab/usage-quotas-pricing),
before deducting any free minutes or credits. For example, a $2/run reservation
and $6 batch cap permit three runs. Check current prices and add other costs
where applicable. This is a local submission guard, not a Cloud Billing hard
cap: it cannot control other clients, determine promotional eligibility, or
reconcile the provider invoice. Actual usage, applied credits and charged cost
remain separate evidence. Budget alerts also do not cap charges.

The gcloud asynchronous response contains a console URL, not a matrix object.
The adapter reads the matrix creation receipt and verifies its project and unique
run label through the Testing API before using it. If submission is interrupted,
recover the existing matrix with `reconcile`; never repeat `run` to find out
whether a submission succeeded. An unverified candidate ID is diagnostic only.

Android pulls external app result files. The first live S24 run recovered a
complete journal through this path, but its collected console log contained no
validation JSONL; console-only recovery is not yet qualified on Flutter devices.
iOS attaches bounded result files to XCTest; collection exports `.xcresult`
attachments on macOS. Missing, truncated or conflicting evidence remains incomplete.
iOS writes no `stderr.log`; its native log is in `xcodebuild_output.log`.
Collection keeps the lines between that log's first and last
`LLAMADART_VALIDATION` records, only if those records are exactly the
collected journal, writes them to `report/native.log` and passes that to the
reporter. With no such log, or more than one native log source, GGUF reports
keep `accelerator_evidence_missing`. Trimmed iPhone 16 Pro Firebase logs in
`packages/llamadart_validation/test/fixtures/ios_xctest/` pin this (their
`bridge_tag` reads `fixture-bridge`); the `decision-gguf-metal` log yields
both 29/29-layer `MTL0` loads and verifies placement.

Firebase Android writes neither file. Its device `logcat` holds every process
of the device session, so collection uses it only for a LiteRT GPU profile, and
only when the run has no `stderr.log` or `xcodebuild_output.log` at all: such a
capture, bound or not, still decides alone and the device log never overrides
or supplements it. Collection streams the single `logcat` under
`remote-results` (at most 128 MiB) and writes the app process's lines from its
test start record onward (at most 8 MiB, dropped lines included) to
`report/native.log`, replacing any earlier one. A Dart VM service announcement,
whose URL carries an auth code, is dropped wherever the process logs it, unless
it also carries a GPU failure marker, which leaves the log unbound. The
log is bound to the journal only if all of these hold:

- exactly one `flutter` record `00:00 +0: shared validation: <profile id>`
  exists, and every other mention of a shared validation test is that process
  naming that profile;
- every `Model ... loaded from` record of that process names
  `validation/models/<profile model sha256>/`, and there is at least one;
- every native epoch timestamp of that process is at or after the manifest's
  `started_at`, and there is at least one. The manifest is written before the
  first load on the same device clock, so no skew is allowed;
- the first of those timestamps is at most 10 seconds after `started_at`. It
  followed by 0.14 and 0.17 seconds in the collected runs;
- the manifest's `run_id` is `app-<epoch microseconds>`, is not after
  `started_at`, and is at most 10 seconds after the test start record, with
  0.1 seconds of slack before it. It followed by 0.38 and 0.34 seconds in the
  collected runs.

The device log never prints the run id, so the run id is bound by the time it
encodes, not by a match. Device-log times have no year or zone, so the start
record is placed on the epoch clock from the log alone: the first native epoch
timestamp less the device-log time elapsed between the two records. The log
cannot show a daylight saving change between them, so the run id may instead
fall in the window moved by half an hour or an hour either way. Ten
seconds leaves a slow cold start room and is far shorter than a run, whose
cases alone took 68 and 48 seconds after `started_at`, so the device log of a
later run cannot fall inside it.

Two device logs, a second start record, another model directory, an earlier
timestamp, the device log of a later run or of another device's run, a journal
of another day, a run id outside its window, any other line of the process
with a Dart VM service or DevTools URL or a URL whose host is `localhost` or an
IP literal in any spelling, or an Android journal for any other runtime or
backend leave no native log, and the report keeps
`accelerator_evidence_missing`. A journal of another run whose run id and start
time both fall inside those windows is not told apart. Trimmed Pixel 9 Pro and
Galaxy S24 Firebase logs in
`packages/llamadart_validation/test/fixtures/android_logcat/` pin this.
Physical device export/crash behavior is an explicit live-qualification step;
a build and fake-provider tests alone do not prove it.

A model-preparation error can occur before the suite manifest exists. The current
collector retains those raw device files under `remote-results`, but cannot
produce a validated suite report from them. Record preparation as ERROR and
inference as NOT_RUN, with TPS unavailable. Zero cases and successful artifact
collection are not a passing run; a structured preparation-error envelope remains
a follow-up. Do not insert requested bundle metadata as observed runtime evidence.

### Image-generation profiles

`packages/llamadart_validation/assets/image_profiles/` holds the image device
checks: `image-sdxs-cpu` (Android, CPU) and `image-sdxs-metal` (iOS, Metal).
The stable-diffusion-native `v0.3.0-2` pin provides the intrinsic tiny-decoder
v1 context policy required by the iOS Metal SDXS profile. Its physical-device
qualification must still use this exact runtime and consumer build. Full-VAE
and external-decoder Metal paths remain refused; use CPU VAE placement for
those models ([#1047](https://github.com/leehack/llamadart/issues/1047)).

They run the chat-app test `integration_test/image_generation_e2e_test.dart`
(SDXS download through the image screen, one seeded 512x512 image, and a
verified receipt with both PNGs), not the shared text suite. The
`image-settings-cpu`, `image-settings-cpu-vae` (Android), `image-settings-metal`,
`image-settings-metal-taesd` and `image-settings-metal-vae` (iOS) profiles
(`suite` `settings-comparison`) run
`integration_test/image_settings_comparison_e2e_test.dart` instead: the
automatic attention and VAE settings against explicit overrides for SDXS and
SD-Turbo with and without TAESD, with time per image and peak memory per arm
([#805](https://github.com/leehack/llamadart/issues/805); see the chat app
README). Their `variants` list is compiled in as `IMAGE_SETTINGS_VARIANTS`
and must match the receipt, as must the optional `rounds` and
`measured_per_load`. The optional `expected_refusals` lists the variants its
devices may see refused by the load-time memory check
(`IMAGE_SETTINGS_EXPECTED_REFUSALS`), for a device-specific profile whose
expected outcome is a refusal. The shipped profiles list none: they run on
phones that must measure every variant. The variants are split over several runs to stay
inside a 20-minute Test Lab run on Android, and on iOS inside the few minutes
an XCTest run tolerates before its first test case (see the chat app README). They live outside
`assets/profiles/` because that directory is bundled into the QA app and every
file in it must parse as a text profile; an ID names one file in either
directory. Each profile locks exactly the chat app's SDXS model (a settings profile
locks its SDXS, SD-Turbo and TAESD files, in that order); the builder
and the upload check reject any other lock, an unknown backend, and a target
the backend is not routed on (CPU is Android only, Metal iOS only; desktop,
Web and `ios-inputs` are rejected).

```sh
dart run tool/testing/validation.dart build --target android --profile image-sdxs-cpu --out .dart_tool/validation/bundles/android-image
dart run tool/testing/validation.dart plan --target firebase-android --config .dart_tool/validation/firebase.json --bundle .dart_tool/validation/bundles/android-image --out .dart_tool/validation/plan-android-image.json
dart run tool/testing/validation.dart run --plan .dart_tool/validation/plan-android-image.json
# iOS, on a Mac with signing configured:
dart run tool/testing/validation.dart build --target ios --profile image-sdxs-metal --out .dart_tool/validation/bundles/ios-image
```

The build compiles the image test into `app.apk` (or `tests.zip`) with the
same `VALIDATION_COMMIT` and `VALIDATION_SOURCE_DIRTY` defines as text bundles,
passed to both the `flutter build apk` step and the Gradle `-Pdart-defines`
step; `test.apk` only carries the Java instrumentation runner. It records
`test_target` and the pinned
`stable_diffusion_tag` in the bundle manifest. There is no `qa-app.apk`.
The test reads the commit and clean flag from those defines, so only a clean
committed build can produce evidence that verifies.

Android pulls `files/image_generation_e2e` (`files/image_settings` for a
settings profile) instead of `files/validation`.
iOS Test Lab does not collect the app cache directory the test writes to, so
the XCTest runner attaches the latest `image_generation_e2e/run-*` and
`image_settings/run-*` receipts, journals and PNGs (each at most 16 MiB) to
the result; collection exports them on macOS.
Collection then grades with the maintained image verifier
(`verifyImageEvidence`) instead of the text report and writes
`report/image-verdict.json`. It verifies only when exactly one run's evidence
was collected and the receipt matches the bundle: its exact clean source
commit, the profile's backend device (`CPU` or `MTL0`), the bundle's
`stable_diffusion_tag`, the profile's model lock, seed 42 and 512x512, with
both PNGs structurally valid and matching the receipt's sizes and SHA256.
A settings receipt is graded by `verifyImageSettingsEvidence` against the
same identity and the profile's three model locks: its summary must be the one
its per-load records give, every variant must have loaded each arm once per
round with `measured_per_load` images per load, or been refused once by the
load-time memory check (a `LlamaModelException` naming
`ImageModelParams.checkMemory`) when the profile's `expected_refusals` lists
it, at least one arm must have measured, every measured arm must be
deterministic, and each generating arm's 512x512 PNG must match the arm's
image hash. `report/image-verdict.json` then carries
the summary table (`kind` `image_settings_comparison`).
As for text profiles, the run qualifies only if the provider outcome is also
SUCCESS and cleanup is verified. PNG checks are structural; they do not judge
image quality, and the backend is the device the runtime reported, not proof
of per-step GPU execution.

## GCE setup and teardown

Run the GCE controller from the owned Mac or Linux. Windows is supported as the
CUDA test guest; Windows-hosted GCE orchestration is not yet qualified.

Copy `tool/testing/validation/gce.example.json` to an ignored path. Configure an
immutable **GPU-ready image**, exact expected driver, compatible machine/accelerator,
zone, an existing network and a targeted IAP TCP/22 firewall tag. Linux needs
Python, `timeout` and `sha256sum`; Windows needs Google-supported SSH and PowerShell.
This initial adapter consumes an already qualified image; it does not install GPU
drivers or change project networking. Check quotas and image/machine compatibility
before the first approved run. Instance readiness rechecks the actual driver.

The GCE profile must explicitly select GGUF CUDA and the uploaded desktop bundle
must be built for the destination x64 OS. Each run requires fresh evidence that
promotional credit applies to **all** expected costs, has at least twice the
estimated run cost available, and expires at least two hours after dispatch.
The receipt is an operator-verified billing-console record, not an automatic
credit API lookup. A budget alert is not a guarantee against charges.

```sh
dart run tool/testing/validation.dart plan --target gce-linux-cuda --profile tiny-gguf-cuda --config .dart_tool/validation/gce.json --bundle .dart_tool/validation/bundles/linux --out .dart_tool/validation/plan.json
dart run tool/testing/validation.dart run --plan .dart_tool/validation/plan.json
```

Use `gce-windows-cuda` with a Windows x64 bundle and Windows-ready image. The
adapter records intent before creating one VM, requires provider-confirmed deletion
after 60 minutes, persists instance/disk IDs before setup, verifies the driver,
uploads/checks the bundle over IAP, runs under a 20-minute watchdog, collects
results, deletes the owned VM/boot disk, and reads the inventories back.
It creates no reusable volumes, static IPs or service accounts. An ephemeral
public IP provides outbound model download access and belongs in the cost estimate.

Deletion is the default cleanup. **Stopped VMs can retain charged disks**; stopping
also clears the runtime deadline. Provider deletion deadlines and local finally
cleanup are complementary, not a zero-cost guarantee. If identity is uncertain,
cleanup refuses to delete a potentially unrelated resource, records UNKNOWN and
blocks another run. No cloud run is permitted under the $0-out-of-pocket policy
when applicable credit cannot be verified.

- The GCE `ubuntu-accelerator-2404-amd64-with-nvidia-580` image ships the
  NVIDIA driver but not the CUDA 12 runtime libraries (`libcudart.so.12`,
  `libcublas.so.12`) that `libggml-cuda.so` links; without them the CUDA module
  fails to load and llama.cpp runs on CPU. The stock image also lacks
  `libgomp1`, which every llama.cpp load needs.
- On the same image (g2-standard-4, L4), the NVIDIA Vulkan driver
  (`libnvidia-gl-580-server`) also needs `libglvnd0 libgl1 libegl1 libglx0`.
  Without them `vulkaninfo` finds no NVIDIA device and llama.cpp silently runs
  on CPU.
- Container link checks for the CUDA and HIP modules:
  `docker/validation/Dockerfile.cuda-linkcheck`,
  `docker/validation/Dockerfile.hip-linkcheck`, and
  `scripts/check_native_link_deps.sh <native-lib-dir> <lib-name> [<lib-name> ...]`.

## Recovery and evidence

Offline reassessment of a saved remote run uses the prepared dependency graph:

```sh
# Prepare while online, before replay (root preparation is also required):
(cd packages/llamadart_validation && dart pub get)
# Invoke the source directly: `dart run` can implicitly resolve dependencies.
dart --packages=.dart_tool/package_config.json tool/testing/validation.dart reassess \
  --run-id qa-EXACT-ID --out /path/to/new-reassessment
```

`reassess` verifies the saved plan and complete bundle inventory, then copies raw
collections and previously extracted XCTest attachments into a new directory.
It uses the same journal normalization, runtime/profile binding, Android log
window and report policy as collection. It never calls a provider, resolves
packages, downloads inputs or invokes `xcrun`; xcresult attachments must already
be extracted. Missing package configuration fails with a preparation prerequisite.
The destination must be new and outside the saved run and bundle; original
journals, reports and lifecycle records remain unchanged. Old derived
`report/native.log` files are excluded and native evidence is rebound from raw logs.

`reassessment.json` separates replayed `assertions_passed` from `historical`
provider, collection, cleanup and error observations. Its combined `qualified`
requires both the replay and successful saved provider/completed collection/
verified cleanup without saved errors. This is no provider refresh or new device
run. An old catalog remains historical; Android LiteRT GPU proof remains
load-time delegate initialization, with no per-request GPU execution attribution.
This implements only #1019's offline entry point.


```sh
dart run tool/testing/validation.dart status --run-id qa-EXACT-ID
dart run tool/testing/validation.dart collect --run-id qa-EXACT-ID
dart run tool/testing/validation.dart cleanup --run-id qa-EXACT-ID
# Only after finding the exact ID in the provider console:
dart run tool/testing/validation.dart reconcile --run-id qa-EXACT-ID --remote-id EXACT-PROVIDER-ID
```

Use the ID printed in the saved plan (the placeholder above is not a valid ID).
OS locks serialize provider operations and release if the controlling process dies.
SIGINT requests cancellation; cleanup still runs after the current bounded provider
operation. Reusing a run ID cannot submit twice. A missing creation/submission
response is UNKNOWN, never permission to retry. If no remote ID was received,
inspect the provider console using the exact project/run label, preserve the
journal, and use `reconcile` before recovery; do not delete the journal to bypass
the blocker. Reconciliation checks the Firebase project/matrix/run label, or the
GCE numeric instance ID, zone, label and owned automatic boot disk. It cannot
replace an established identity and does not erase the original failure. Then
run `status`, `collect` and `cleanup`. Recovery commands never submit a replacement.

`orchestration.json` stores phase, exact IDs, provider state and collection state;
`cleanup.json` stores verified/unknown cleanup. `remote-summary.json` is the
combined verdict: provider success **and** validated Dart assertions/provenance
**and** complete retrieval **and** verified cleanup. Test-only report success
cannot override provider failure or unresolved infrastructure. Collection also
matches the source commit, cleanliness, hook hash and all runtime pins against
the uploaded bundle; desktop evidence must match its bundle manifest hash.

Each run exports `events.jsonl`, `manifest.json`, `results.json`, `junit.xml`,
`samples.csv`, and `summary.html`. HTML has case status/output, native decode TPS,
estimated visible-output TPS, TTFA, and median/min/max for three measured samples.
Warmup is retained but excluded from these comparisons. Missing counters are null;
chunks are never called tokens. Backend-native decode timing and retokenized
wall-time estimates stay in separate series. Three samples are informational,
not a performance regression gate or a cross-device ranking.

The reporter validates the embedded profile, derives its canonical mandatory case
inventory and effective configuration, and checks the journal against both. Hash
consistency alone is insufficient. Accelerator proof is derived from the backend;
an event flag cannot waive it. The current catalog grants no expected-unsupported
exemptions, so a producer cannot qualify a skipped case by setting
`expected_unsupported: true`. Old reports are evidence snapshots; revalidation
with a newer catalog must preserve the original and write a separate result.
Reimport requires `preparation.verified == true` and the exact model SHA256/byte
size from the profile. Historical desktop journals without runtime payload proof
retain their assertion results but are incomplete under the current qualification
gate; do not copy new verification flags into old journals.

Explicit CPU rows reject contradictory GPU diagnostics. GGUF accelerator reports
require matching backend diagnostics plus positive native tensor offload and
compute allocations for all three successful loads. Device presence or requested
GPU layers alone does not qualify execution. LiteRT NPU uses the checked per-generation dispatch adapter described above.

LiteRT GPU on Android has load-time evidence only. Given a bound device log,
the reporter verifies placement as
`gpu_delegate_initialized_per_load_execution_unobserved` when the journal's
environment is Android and states `web: false`, its LiteRT-LM tag is
source-qualified (`0.18.0`, `0.18.0-1`, `0.18.0-2`, `0.18.0-3`, `0.18.1`, `0.18.1-1`, `0.18.1-2`, `0.18.1-3` or `0.18.1-4`), every
expected load case passes exactly once reporting a GPU backend, and the log holds N GPU
delegate initializations for the N expected load cases. Each of them has:

- one `Selected adapter` record, identical across loads, naming a recognized
  hardware vendor with `backend=Vulkan` and an `Integrated GPU` or
  `Discrete GPU` adapter type, and no software, CPU or basic-render name;
- one `Created a WebGPU environment.` record;
- as many delegate-kernel records (`Total N external tensors are used for
  delegate inputs and outputs`) as the `num_signatures` of that load's
  main-model `Loaded:` record. That record is the last one before the adapter
  selection and must declare more signatures than any other `Loaded:` record
  in the log; the embedding models' single-signature records follow it.

The log must be logcat `threadtime` records (`MM-DD HH:MM:SS.mmm PID TID L
tag: message`), which is what collection retains and what `--native-log` must
name for such a journal. Adapter and delegate-kernel records count only under
the `native` tag and `Loaded:` and environment records only under `litert`, as
LiteRT-LM 0.18.0 logs them on both devices. The same text under another tag,
such as a Dart `print` under `flutter`, a record without that prefix, or a
signature count that cannot be parsed leaves placement unverified.

Any of `GPU accelerator could not be loaded and registered`, `Some ops are not
accelerated`, `Failed to modify graph with delegate`, `VK_ERROR_`, `Validation
error` or `Falling back to CPU` anywhere in the log, under any tag, leaves
placement unverified. The list is not exhaustive: a failed load or generation
is expected to surface as a failed case. Accelerator registration and XNNPACK
records are ignored in both directions: a CPU run logs the same GPU
registration.

The evidence rests on two source rules read at LiteRT-LM
`b2f686e2ed4718fb84ec398a61dd59ca0f0aff27` and LiteRT
`26895c9fbcc25c43faa8c1a98cd1fd28951602c3`: the GPU executor requests the GPU
accelerator alone (`runtime/executor/llm_executor_settings_utils.cc`), and
LiteRT refuses to compile a model that leaves a node undelegated unless the CPU
accelerator was requested (`litert/runtime/compiled_model.cc`). Both were
re-read for `0.18.1` at LiteRT-LM `bda624851d74be34d4e1f7fac1fc4155939539c7` and
LiteRT `ca21dc99de51c76bdcc572afeea1dd937d3c9e5c`: the LiteRT-LM file is
unchanged, and LiteRT now counts every node that is neither a delegate nor a
dispatch op as undelegated, which can only fail more compilations. The
`0.18.1` Android WebGPU accelerator and Dawn libraries are byte-identical to
`0.18.0-3`; `0.18.1-1` and `0.18.1-2` add only XNNPACK CPU kernel patches;
`0.18.1-3` changes only the Windows runtime, and `0.18.1-4` patches only
LiteRT's CPU options identifier, which the compile rule reads only when the CPU
accelerator is requested. Re-read both rules before qualifying another LiteRT-LM tag. It
therefore shows that the main model
was fully delegated to that adapter at every expected load. The delegate-kernel
count is a consistency check on top of that compile rule, not proof by itself:
a `Loaded:` record does not name its model, so the main model is recognized by
its position and by declaring the most signatures.

The residual limits are:

- no generation request or sampler is observed; a device lost after load is
  visible only through failed cases or a logged marker;
- only the delegate initializations of the expected load cases are counted. A
  CPU engine the process creates elsewhere logs none of these records and is
  not observed;
- the accelerator mask is not logged. It is inferred from the requested
  backend and from the LiteRT-LM tag the journal reports about itself;
- LiteRT's undelegated-node check does not count subgraphs that delegation may
  skip;
- the ML Drift delegate is closed source, so what a delegate kernel executes
  on the adapter is not read;
- the shipped binary is not attested against the sources that were read;
- the embedding and end-of-audio/end-of-image models LiteRT-LM loads beside
  the main model are not covered: the fixture logs show an XNNPACK CPU
  delegate and no GPU delegate for them. Audio and vision encoders, which
  these runs did not load, are outside this evidence too.

iOS (Metal, no adapter record), OpenCL, desktop and Web LiteRT GPU and browser
accelerator proof still require qualified evidence adapters; they remain
incomplete.

Normal model runs are opt-in. Model-free suite/provider tests run in CI. Before
claiming another platform qualified, attach the exact commit, model/backend,
command, provider/device identity, combined verdict, cleanup and native evidence.

LiteRT-LM interrupted cleanup: a Dart timeout or killed isolate does not forcibly interrupt a blocking native
call. CLI validation should use an outer process deadline and retain the timeout
and cleanup error in its results. Closing response ports must not be counted as
successful native cleanup. Requested GPU selection remains separate from verified
accelerator placement.

## Initial owned-machine observations (2026-09-17)

The portable macOS arm64 bundle ran outside the repository. Tiny GGUF CPU/Metal
completed inference/lifecycle/TPS, while native Unicode corruption remains tracked
in [#511](https://github.com/leehack/llamadart/issues/511). The tiny model's expected
SentencePiece leading space is an explicit fixture normalization; corrupted
Unicode is still a failure. A Web/WASM UI run preserved Unicode and proved
cancellation through the pinned delegate's explicit AbortError and successful
recovery. The CPU identity check recognizes the pinned WASM name only with zero
GPU layers and its CPU core metadata.
Web native-token counters were unavailable, so C10 stayed NOT_RUN.

Qwen3.5 GGUF also exposed native Unicode corruption and returned `Cedar17` for the
case-sensitive `cedar17` history oracle. LiteRT CPU ran 13/14 cases successfully
but answered `2` for `2 + 2`; retain the semantic failure and relate it to
[#509](https://github.com/leehack/llamadart/issues/509), without inferring the same
cause before a native reference comparison. These runs are diagnostics, not
release qualification or stable performance baselines.

## Maintained Firebase CPU pilot (2026-09-17)

Four physical executions used the unbilled Spark project. All reached terminal
provider states, artifacts were collected, and completion was verified. No GCE
VM was created. Android file pulls and iOS XCTest attachment export both recovered
complete quick-core journals when model preparation succeeded.

| Device / profile | Outcome | Median native decode TPS |
| --- | --- | ---: |
| Galaxy S24 / tiny GGUF CPU | 10 PASS, 1 FAIL: C02 Unicode corruption | 538.5 |
| iPhone 16 Pro / tiny GGUF CPU | 10 PASS, 1 FAIL: C02 Unicode corruption | 708.3 |
| Galaxy S24 / Qwen3 LiteRT CPU | Preparation ERROR; inference NOT_RUN | Unavailable |
| iPhone 16 Pro / Qwen3 LiteRT CPU | 13 PASS, 1 FAIL: C04 arithmetic returned `2` | 8.9 |

GGUF used native `v0.4.0`; LiteRT used `0.17.0-3`. Unicode matches
[#511](https://github.com/leehack/llamadart/issues/511); the arithmetic observation
matches [#509](https://github.com/leehack/llamadart/issues/509) and does not by
itself establish a Dart-layer defect. The three benchmark samples after warmup
remain available despite those independent assertion failures. Android is Debug
and iOS is Release; the tiny GGUF model is a packaging fixture, so these numbers
are not a device ranking or a comparison of backend performance.

The Android LiteRT attempt ended after 302 seconds during model download, before
any suite manifest or inference. Its old diagnostic recorded a closed connection
without partial byte progress. The corrected mobile host now has a ten-minute
download deadline and reports byte counts on timeout. The final iOS bundle used
that host, downloaded and verified the 614 MB fixture in about 65 seconds, then
ran the suite. The original failed Android attempt remains in the evidence;
the separately selected retry below establishes download recovery for one run.

The remaining mobile milestones are reliable preparation-error envelopes,
semantic-failure investigation, and the planned accelerator qualification packs.
These CPU observations do not qualify accelerator paths or a release.

### Android LiteRT CPU retry after Blaze upgrade

Run `qa-1789668430755373` / `matrix-2thou79z4k2ud` used the corrected clean
`b860bfe6c13958bede6df7088d1f53e05eac8f7c` Debug bundle on S24/API 36. It
downloaded the 614,236,160-byte Qwen3 model in 169.332 seconds, verified its locked
SHA256, and finished preparation in 175.961 seconds within the ten-minute
download deadline. This is one successful retry, not a network reliability rate.

The result was **13 PASS, 1 FAIL**: C04 arithmetic again returned `2` for `2 + 2`,
matching [#509](https://github.com/leehack/llamadart/issues/509). Median native
decode throughput was 12.34 TPS, estimated wall throughput 8.53 TPS, and visible
TTFA 2,054.97 ms across three measured samples after warmup. The provider recorded
232 seconds of test process time (four rounded free minutes), and collection and
completion were verified. The scheduled September 18 retry was paused to prevent
a duplicate. Qwen CPU is not the matched Gemma CPU control for the NPU pack.

## Galaxy S24 NPU pilot (2026-09-17)

Both installed apps used clean bundle source `2288eed19c482e7774df2c93b1e7d9a96e6e9c4e`,
Flutter 3.47.1, Debug mode, LiteRT-LM `0.17.0-3`, QAIRT `2.47.0.260601`, and the
locked `Gemma3-1B-IT_q4_ekv1280_sm8650.litertlm` model. The device reported
`SC-51E`, `SM8650`, arm64-v8a and API 36. Model and kit hashes were verified on
installation and per-generation synchronous vendor-call completions established
**NPU participation; CPU partition coverage unknown**.

| Execution path | Result | Native decode TPS, median | Estimated wall TPS, median | Collection/completion |
| --- | --- | ---: | ---: | --- |
| Direct native C API control | 8 PASS; NPU proof in 7 generations | 80.08 | 72.45 | COMPLETE / VERIFIED |
| Public llamadart API | 13 PASS, 1 FAIL; NPU proof in 14 generations | 82.27 | 72.24 | COMPLETE / VERIFIED |

These are three short 32-token measured generations after warmup, not a sustained
benchmark or evidence that one adapter is faster. Both use compiled NPU sampling
defaults: requested temperature/seed overrides are not applied, and effective
sampler values remain unknown. Native-control TTFT median was 36.37 ms; public
visible-answer TTFA median was 135.56 ms. They measure different boundaries and
must not be substituted for each other.

The public history case expected `cedar17` and returned 32 repeated `7` characters.
It remains FAIL and blocks public NPU qualification. Load, Unicode tokenizer
round-trip, raw generation, hello, arithmetic, cancellation/recovery, reload,
one-token output limit and invalid-path recovery passed. Track the exact inputs
and controls in [history investigation #513](https://github.com/leehack/llamadart/issues/513).
The native control does not yet test this history input, so its success does not
establish whether the failure belongs to Dart, the runtime, or the compiled model.

Native run `qa-1789667329901788` / `matrix-pt34kzd9mgxsa` used six seconds of test
process time; public run `qa-1789667821365130` / `matrix-21m98jmyipzo2` used 45 seconds.
Both were capped at ten minutes after a fresh project-wide free-minute check.
Each consumes one rounded free physical minute. All raw outputs, configuration,
provenance, timing samples and dispatch counters are retained with the run reports.
The matched Gemma CPU control, separate Unicode generation fixture and aggregate
NPU pack qualification remain outstanding; the Qwen CPU retry is independent.

The final project-wide inventory at 18:15 UTC found all seven September 17
physical executions complete, with no unresolved executions. Individually
rounded test times totalled **17 of the 30 free physical minutes**: 11 from the
earlier Spark runs and six from this three-run batch. The gross USD 6 journal
reservation is a dispatch guard, not a charge. No VM or custom storage bucket was
created. The default Test Lab result bucket is
[provided at no charge](https://docs.cloud.google.com/sdk/gcloud/reference/firebase/test/android/run#description),
and complete copies of the reports are retained locally.

### Native history replay on current main / LiteRT-LM 0.17.0-5

The follow-up control used clean source
`fb8d2beb4db65f1b8987d69022049b4d0ae4fbda`, including main
`21135e37dadf60882ea427db6078ccc90f84a28a`, with the same Gemma model, QAIRT kit
and S24/API 36. Runtime `0.17.0-5` was verified from the release archive through
the APK: its core SHA256 `502d017d8375c0796adf5f720da29fb1915b2a70103e3cf8f6e8e8880ac0f614`
becomes `5424262e8a396b1cc32813a5d3f061c0ccba06cdff2ddc61d5bfdc40a249d2c4`
after the reproduced Android NDK symbol-stripping operation.

Run `qa-1789670325547288` / `matrix-1serhazjregr5` completed **8 PASS, 4 FAIL**,
with no ERROR/NOT_RUN and NPU participation verified in all eleven generations.
Every history variant retained the exact, case-sensitive `cedar17` oracle:

| Direct native history control | Output | Verdict |
| --- | --- | --- |
| Normal system content plus prior messages | `Cedar17` | FAIL: capitalization |
| Public path's literal-JSON system content, same prior messages | 32 repeated `7` characters | FAIL |
| Prior messages without system content | `Cedar17` | FAIL: capitalization |
| Four text contents joined into one user prompt | `7777\n` | FAIL |

This reproduces degeneration without the public worker/streaming adapter on the
new runtime. The literal-system input conflicts with the C API's system-content
contract; normal content removed degeneration in this observed comparison, but
strict recall still failed. One generation per variant and unknown compiled
sampling do not establish a failure rate or isolate every cause. The native
conversation-creation snapshots showed no vendor calls for these controls, so
this result does not establish a separate initialization-prefill defect.
[#513](https://github.com/leehack/llamadart/issues/513) retains the exact setter
JSON and next controls: correct the serialization boundary, replay public Dart,
and compare a compatible Gemma CPU/model reference. No public `0.17.0-5` rerun
or production serialization change is claimed by this control.

The independent short benchmarks had median native decode 80.58 TPS, estimated
wall 71.71 TPS and native TTFT 37.05 ms. Collection was COMPLETE and terminal
cleanup VERIFIED. The provider recorded 46 seconds, consuming one rounded free
minute. The final 18:52 UTC project inventory found eight completed physical
executions, **18 of 30 free minutes used**, twelve remaining and no unresolved
executions. No VM was created or additional run scheduled.

### Public history replay after the system-content fix

Clean source `d0bd029b07e31649ab5760756dcc1841ba487282` corrects the service's
system-message boundary: pass plain joined text to the runtime, which JSON-encodes
it once for the C API. Literal JSON, quotes, newlines, Unicode, multiple and
empty system messages are covered; the existing history-order and unsupported
system-media assertions remain. Three regression assertions failed against the
old service. All 161 LiteRT VM tests, full repository analysis and changed-file
format checks pass, with every executable history-seeding line covered.

The one public API retest used the same S24, model hash, QAIRT kit and audited
`0.17.0-5` core as the preceding native control. Run `qa-1789672372212252`,
matrix `matrix-23gzng6la12qr`, completed **13 PASS, 1 FAIL**, with no ERROR/NOT_RUN,
complete provenance and NPU participation verified across fourteen generations.
`C06.history` now returns **`Cedar17`**, matching the canonical native control,
instead of the original repeated `7` output. The exact lowercase `cedar17`
oracle remains unchanged and failed; the NPU profile remains unqualified and
[#513](https://github.com/leehack/llamadart/issues/513) stays open. The history
request recorded 52 prompt tokens, four decoded tokens, two public chunks and
five completed vendor calls; CPU partition coverage is still unknown.

This fixes the demonstrated serialization contract mismatch and removes the
degeneration in this single public observation. It does not establish a failure
rate or attribute the remaining capitalization and combined-prompt failures to
model behavior, model conversion or the NPU runtime. A compatible Gemma CPU/model
reference and repeated controlled comparison remain the next diagnostic steps.
Compiled NPU sampling defaults are unknown; requested temperature/seed are not
applied by this path.

Three measured short benchmark samples after warmup gave median native decode
**77.84 TPS**, estimated wall **66.13 TPS** and time to first public output
**152.17 ms**. Native TTFT is unavailable on this public path. These benchmarks
assert bounded nonempty output, not number-list semantics, and the earlier
82.27 TPS sample is not a statistically controlled performance baseline.

Collection is COMPLETE and terminal cleanup VERIFIED. The test process took
46 seconds, consuming **one rounded free minute**. The 19:22 UTC project audit
found nine completed physical executions, **19 of 30 free minutes used**, eleven
remaining and zero unresolved executions. No paid test minutes were needed, no
VM was created and no further run was scheduled. The interactive report, exact
JSON, immutable usage receipt and runtime audit are retained under
`.dart_tool/validation/system-fix-20260917/` and the run's `report/` directory.

### Repeated Gemma CPU controls on macOS

The local CPU comparison uses clean source
`2b604775ac49f0532e2a0a9f34024c93d3998c10`, Apple M4 Max/macOS 26.6.2 arm64,
and LiteRT-LM `0.17.0-5`. The CPU artifact from the same pinned model repository
is `gemma3-1b-it-int4.litertlm`, 584,417,280 bytes, SHA256
`1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be`.
The core library SHA256 is
`42a1fa7cc0666ceda1bb00f864065e7b6bcae041234bd501ecc1c56de54b7530`, matching
the cached release archive and published release manifest's macOS smoke record.

Three fresh public-API processes each completed **13 PASS, 4 FAIL**, with no
ERROR/NOT_RUN and complete provenance. A separate local Python/ctypes diagnostic
used the upstream C API directly, without Dart, and repeated all four history
inputs three times with fresh engines. Its exact setter JSON matches the prior
NPU controls; its outputs match the public CPU path in all twelve comparisons.

| Input | Public CPU, each of three runs | Direct-native CPU, each of three repetitions |
| --- | --- | --- |
| Canonical system and prior history | `Cedar17` | `Cedar17` |
| Former public literal-JSON system content | 32 repeated `7` characters | 32 repeated `7` characters |
| History without system content | `Cedar17` | `Cedar17` |
| Combined user prompt | 32 repeated `7` characters | 32 repeated `7` characters |

Every row still fails exact `cedar17`. These failures therefore occur without
Qualcomm/NPU execution and without the Dart service, worker or streaming adapter.
This narrowed attribution but did not distinguish the converted model/tokenizer,
shared LiteRT runtime, and original model behavior. The subsequent original-model
and prompt comparison below narrows that boundary further; keep
[#513](https://github.com/leehack/llamadart/issues/513) open.

Both CPU paths use context 1280, four threads, max output 32, thinking enabled
and greedy decoding. The public requested top-k 40/temperature zero resolves to
top-k 1 in the service; the direct C API used TopP sampler type 2, top-k 1,
top-p 0.9, temperature zero and seed 1. NPU still has unknown compiled sampling.
Platform, artifact/conversion, maximum native context capacity, and sampling
differ between CPU and NPU. Do not treat their TPS ratio as accelerator speedup
or fill the S24 CPU row with this Mac evidence.

Across nine short public benchmark samples (three per run after separate
warmups), median native decode was **74.06 TPS**, estimated wall **67.46 TPS**,
and time to first public output **137.33 ms**. This is diagnostic throughput,
not semantic qualification. No Firebase run, VM or paid resource was created;
no cloud test minutes were consumed. The three run directories are
`.dart_tool/validation/runs/gemma-cpu-20260917-{1,2,3}`; comparison JSON,
direct-native script/results/logs and runtime/model audit are under
`.dart_tool/validation/gemma-cpu-20260917/`.

### Original Gemma and tokenizer reference (2026-09-17)

The original `google/gemma-3-1b-it` model at revision
`dcc83ea841ab6100d6b47a070329e1ba4cf78752` was acquired through existing authorized
access and verified against repository Git blobs/LFS hashes. Its safetensors file
is 1,999,811,208 bytes, SHA256
`3d4ef8d71c14db7e448a09ebe891cfb6bf32c57a9b44499ae0d1c098e48516b6`.
The local reference used Transformers 5.17.0, PyTorch 2.14.0, Tokenizers 0.23.2,
CPU float32, four threads, eager attention, greedy decoding, seed 1 and at most
32 new tokens. It used the model's original chat template and the exact four
role/content inputs from the prior direct-native control.

All four variants returned `cedar17\n` in each of three repetitions: **12/12 PASS**
under the existing trimmed, case-sensitive predicate. No assertion was relaxed.
This is a semantic reference, not a comparable speed or quantization benchmark.

The CPU LiteRT model embeds a SentencePiece tokenizer byte-identical to the
original: SHA256
`1299c11d7cf632ef3b4e11937501358ada021bbdf7c47638d13c0ee982f2e79c`.
For every input, the native conversation render exactly matches the original
prompt after accounting for BOS. The native tokenizer IDs plus metadata BOS ID 2
match the original Transformers input IDs. The pinned upstream session code adds
that BOS separately on the first turn; this comparison checks rendering and the
tokenizer API, not a trace of tensors passed to the executor.

The NPU tokenizer differs in IDs 256000–262143 (6,144 vocabulary entries), with
the same normalizer and core special-token IDs. None of the observed input IDs
uses those changed entries. That difference is not evidence of the cause; actual
NPU prompt tokenization was not captured in this local comparison. Both LiteRT
files use non-Jinja role affixes with BOS ID 2; the NPU metadata additionally
specifies the 1280-token limit.

These results rule out an impossible oracle and a mismatched CPU tokenizer file
for these inputs. They do not separate quantization/conversion effects from
LiteRT executor/runtime behavior. Continue #513 with a controlled alternative
conversion or upstream execution comparison; keep the strict failures and S24 CPU
gap open. No Firebase execution, VM or paid resource was used. Hash audits,
original inputs/token IDs/outputs, native rendered prompts, extracted tokenizer
metadata, dependency versions and comparison JSON are retained privately under
`.dart_tool/validation/gemma-reference-20260917/`.

The report validator was also tightened after five regression tests demonstrated
false qualifications from omitted obligations, conflicting rehashed settings,
invalid profiles, waived accelerator flags and self-granted unsupported status.
All 43 harness tests and 44 provider/input tests pass. Revalidating copies of the
three CPU journals and latest public/native S24 journals preserves their exact
verdicts and counts, with no new integrity problems; originals remain unchanged.

### Gemma3 quantization control and history fixture (2026-09-23)

Upstream `litert-lm-api==0.17.0` (macOS arm64 wheel, no llamadart code) ran the
four history variants on two files from the same repository revision, with a
greedy sampler, thinking enabled, context 1280 and 32 output tokens. The int4
`gemma3-1b-it-int4.litertlm` failed 12/12 exactly as above; the q8
`Gemma3-1B-IT_multi-prefill-seq_q8_ekv4096.task` (SHA256
`9fc939cf525890ea060a815c5cd4395a1496161e3930c3891891be9e255ac09f`) returned
`cedar17\n` 12/12, like the original model. The failures come from the int4
artifact, not the LiteRT executor. q8 ships only as `.task`, so this compares
published artifacts rather than one conversion varied by bit width.

The int4 artifact capitalizes lowercase word codes and degenerates on `cedar17`;
it recalls non-word codes exactly. `gemma3-litert-cpu` and `npu-qualcomm-sm8650`
therefore use code `K7Q2` with the same system, acknowledgement and question.
The original model and the int4 artifact each return `K7Q2` for all four
variants in three repetitions, and the public `gemma3-litert-cpu` run passes all
17 cases. The q4 SM8650 NPU artifact has not run this fixture.

## LiteRT-LM v0.18.0 device and GPU-host runs (2026-10-08)

Source `c385ef656`, LiteRT-LM `v0.18.0`, 15 validation cases per row. The
phones ran under Firebase Test Lab (Android Debug, iOS Release); the Windows
host was a GCE Windows Server 2022 x64 VM with an NVIDIA L4.

| Device / profile | Outcome |
| --- | --- |
| Galaxy S24 (API 36, Adreno 750) / Qwen3 0.6B LiteRT GPU | 1 PASS (load), 14 ERROR: `LlamaUnsupportedException`; cleanup PASS |
| Galaxy S24 / Qwen3 0.6B LiteRT `auto` (resolved GPU) | 1 PASS (load), 14 ERROR: `LlamaModelException`; cleanup PASS |
| Galaxy S24 / Qwen3 0.6B LiteRT CPU | 15 PASS |
| Galaxy S24 / Gemma 4 E2B LiteRT GPU | 15 PASS on the third attempt |
| Pixel 9 Pro (API 35, Mali-G715) / Qwen3 0.6B LiteRT GPU | 15 PASS |
| Pixel 9 Pro / Gemma 4 E2B LiteRT GPU | 15 PASS |
| iPhone 16 Pro (iOS 18.3) / Qwen3 0.6B LiteRT GPU | 15 PASS |
| iPhone 16 Pro / Gemma 4 E2B LiteRT GPU | 15 PASS |
| Windows x64, NVIDIA L4 (Direct3D 12) / Qwen3 0.6B LiteRT GPU, `dart run` | 15 PASS |
| Windows x64, NVIDIA L4 / Qwen3 0.6B LiteRT GPU, `dart build cli` bundle | 15 PASS |
| Windows x64 / Qwen3 0.6B LiteRT CPU | 15 PASS |

Both Galaxy S24 Qwen3 GPU failures log `Validation error: Binding size
(155582464) ... is larger than the maximum storage buffer binding size
(134217728)` and end the run normally, with no crash or process death in
logcat. The `auto` row used a local harness profile, so its journal records a
modified source tree. The first two Galaxy S24 Gemma 4 attempts stopped at the
harness's 10-minute deadline for the 2.6 GB model download, before any case.

No GPU row was harness-qualified when collected: none carried native placement
evidence the harness could consume, and the `dart run` Windows rows have no
portable-bundle payload verification. An Android run collected with a bound device log can now
carry the load-time delegate evidence described under Recovery and evidence;
these rows were not re-graded, and the iPhone and Windows rows have no such
evidence. The adapter is read from the native log on Android (`Adreno (TM)
750` and `Mali-G715`, both Vulkan) and Windows (`NVIDIA L4 ... Direct3D 12 ...
Discrete GPU`); the iPhone logs name no adapter. On Windows the GPU
accelerator and sampler import `webgpu_dawn.dll`, the packaged process mapped
it, and the native log has no Dawn validation error and the event log no
application crash.

Not run: a Flutter Windows desktop app, Linux GPU, Linux without a Vulkan ICD
([#572](https://github.com/leehack/llamadart/issues/572)), Android x64 and
iOS 16.

## LiteRT-LM `auto` CPU retry on Galaxy S24 (2026-11-10)

`chat-litert-auto` on a Galaxy S24 (`SC-51E`, API 36, Adreno 750) under
Firebase Test Lab: source `3f6338b50` (clean), LiteRT-LM `0.19.1-2`, Android
Debug, legacy Qwen3 0.6B artifact `555579ff…`, matrix `matrix-1da3zj25gmeu1`
([#1458](https://github.com/leehack/llamadart/issues/1458)).

- Each of the three engine creations (first use, `C09.reload`,
  `C12.recovery`) tried the GPU first. The runtime refused it with
  `FAILED_PRECONDITION`: an "Android GPU safety restriction" naming this
  driver's 134217728-byte `maxStorageBufferRange` and the model's
  155582464-byte constant. llamadart logged one
  `LiteRT-LM could not create a GPU engine under ComputeDevice.auto; retrying
  on the CPU` warning per engine and created a CPU engine. The warning came
  0.5-0.9 s after the load.
- `C01.load` reports `LiteRT-LM gpu` because engine creation is deferred; after
  the retry the model reports `LiteRT-LM cpu` with 0 GPU layers.
- 16 PASS and 1 NOT_RUN of 17 cases, with no crash or process death in logcat.
  Throughput about 8 tokens/s wall for 32-token outputs. `C08.cancel` is NOT_RUN because the cancelled request has no
  native counters; macOS CPU at this pin shows the same, so the CPU retry does
  not cause it ([#1903](https://github.com/leehack/llamadart/issues/1903)).
- An earlier attempt (`matrix-1tcmnx5y9bnqv`) stopped at the 10-minute model
  download deadline with 260777210 of 614236160 bytes, before any case.

## Planned platform/backend coverage

Inspect the model/use-case coverage catalog without downloading models or
starting cloud resources:

```bash
dart run tool/testing/validation.dart coverage
dart run tool/testing/validation.dart coverage --platform android-arm64 --backend npu
dart run tool/testing/validation.dart coverage --use-case stt
dart run tool/testing/validation.dart coverage --use-case tts
```

This JSON is a planning inventory, not a qualification report. `NOT_RUN` means
execution evidence is still required; `UNVERIFIED` identifies an artifact or
compatibility gap; `UNSUPPORTED` identifies a current runtime/API boundary.
Actual results remain in collected run reports. The catalog never emits PASS.

Gemma 4 E2B and Qwen3.5 0.8B are primary chat families. Gemma 4 Tensor G5 and
Qualcomm SM8750 NPU rows require immutable artifacts and matched vendor kits
before executable profiles can be added. SM8750 does not qualify S24 SM8650.
Existing Gemma 3 NPU profiles remain separate legacy controls. No Qwen3.5 NPU
combination is established; Apple, desktop and Web NPU paths are unsupported.

Dedicated STT/TTS models are required exceptions to the primary chat families.
GGUF Qwen3-ASR and Qwen3-TTS need separate platform/backend execution evidence.
Typed LiteRT ASR is native CPU-only; LiteRT TTS and NPU speech are unsupported.
Current TTS produces complete audio, not playable streaming chunks. Speech
quality, real-time factor and app microphone/playback checks remain separate
from chat token throughput and accelerator availability.

The catalog regressions run in the existing `validation-harness` local E2E
scenario and private package tests. Candidate rows cannot be passed to the
builder as runnable profiles; existing model-lock and NPU preflight requirements
remain mandatory. Browser/delegate and device-specific model memory checks are
still required for every actual run.

### Native video input

The pinned `llamadart-native` `v0.7.0-2` macOS, Linux and Windows archives are
built with `LLAMA_SUBPROCESS`/`MTMD_VIDEO`, so `mtmd_helper_support_video`
there reports whether the loaded projector has a vision encoder (an audio-only
projector reports `false`). The Android and iOS archives are built without
video, so it always reports `false`. FFmpeg/ffprobe is not packaged, and the
public Dart path stays unsupported until frame-lifecycle validation exists.
Native LiteRT-LM direct media accepts image and audio only; WebGPU and Web
LiteRT-LM have no validated video transport or frame-lifetime contract.
`LlamaVideoContent` throws `LlamaUnsupportedException` naming either the
missing video support (a projector without a vision encoder, or a runtime built
without video) or, for a video-enabled runtime, the remaining Dart
frame-ingestion/lifetime blocker. Do not infer support from the exported
symbols.

### Primary model profiles and runnable speech packs

Gemma 4 E2B now has immutable `gemma4-gguf-{cpu,metal,vulkan,cuda}` and
`gemma4-litert-{cpu,gpu}` text profiles. Qwen3.5 0.8B retains the existing
`chat-gguf-*` Q4_0 profiles and adds `qwen35-litert-{cpu,gpu}` INT8 profiles.
The new profiles disable thinking, retain strict core predicates, and record
resolved sampling and TPS with the existing reporter. The GGUF chat profiles
select `focused` with `tools`, adding C07.tools and C07.tools.auto_text. Native
LiteRT profiles are not Web or NPU artifacts. Multimodal/projector profiles
remain separate work.

```bash
dart run tool/testing/validation.dart local --profile gemma4-gguf-cpu --model /models/gemma-4-E2B-it-Q4_K_S.gguf
dart run tool/testing/validation.dart speech --pack stt --backend cpu --out /tmp/new-stt-run
dart run tool/testing/validation.dart speech --pack tts --backend cpu --out /tmp/new-tts-run
dart run tool/testing/validation.dart speech --pack litert-asr --backend cpu --model /models/moonshine_tiny_5s_i8.tflite --tokenizer /models/moonshine_tokenizer.json --out /tmp/new-litert-asr-run
dart run tool/testing/validation.dart voice --chat-profile gemma4-gguf-cpu --chat-model /models/gemma-4-E2B-it-Q4_K_S.gguf --out /tmp/new-voice-run
```

GGUF speech downloads or verifies the locked Qwen3-ASR/Qwen3-TTS model and
projector. Dedicated LiteRT ASR requires supplied files matching the checked-in
Moonshine model/tokenizer hashes; immutable source URLs are in
`packages/llamadart_validation/assets/speech/litert-asr.json`.
Every entry point runs under the existing subprocess host's 15-minute deadline.
The `validation-speech-stt`, `validation-speech-tts`,
`validation-speech-litert-asr` and `validation-voice-round-trip` scenarios are
registered in the local E2E runner; use `--model-path`, `--mmproj-path`, or
`--tokenizer-path` to reuse local inputs. The voice scenario uses Gemma 4 CPU;
the direct command also accepts the other primary CPU chat profiles.

Speech reports contain per-case PASS/FAIL/SKIP/NOT_RUN, exact locks and fixture identity,
raw/reference transcript, WER, processing time, first partial/first playable
audio timing where available, real-time factor, and generated WAV artifacts.
Cases cover generation, cancellation, subsequent request, invalid
input/recovery, independent reload and cleanup. Eight further
cancel/dispose/load/generate cycles then run, and a `bounds` block records the
measured cancellation latency, peak memory footprint and the least-squares
footprint slope over cleanup cycles 1-8 against the budgets described in
`packages/llamadart_validation/assets/speech/README.md`. The footprint is
`phys_footprint` on macOS and iOS, `RssAnon + RssShmem + VmSwap` on Linux and
Android, read after `malloc_trim(0)` where the C library provides it (glibc,
not Android), and `PrivateUsage + SharedCommitUsage` on Windows, or `PrivateUsage`
alone on Windows builds without `PROCESS_MEMORY_COUNTERS_EX2`. None counts
file-backed pages, such as the mmapped weights, so evicting them under memory
pressure does not shrink it
([#633](https://github.com/leehack/llamadart/issues/633)); the speech README
lists what each counter includes and misses. The peak ratio is
not applied on Linux CUDA, whose host memory excludes the weights; the slope
bound applies on every backend but misses a leak of 7 MiB or less per cycle, so
a leak that small passes on Linux CUDA
([#686](https://github.com/leehack/llamadart/issues/686)). The
single-shot checks and every cycle each cancel twice: once as soon as the task
is handed back, the window in which `tts` cancellations were dropped until
[#596](https://github.com/leehack/llamadart/pull/596), and once after a wait.
The second must report `cancel_in_flight`, which is true only if the adapter
had not seen the task finish when it cancelled; it cannot show that the
generation had begun; `tts` also records where it landed (see the speech README, [#627](https://github.com/leehack/llamadart/issues/627)). Exceeding any budget fails the run; if the footprint
cannot be sampled, the memory bounds record `SKIP` with a reason, and they
are the only checks a passing run may leave unmeasured or unapplied.
GGUF STT additionally compares file and bytes inputs and runs four generated
edge fixtures: digital silence must fail with the typed empty-transcript
`LlamaSpeechException`, a truncated RIFF must yield an inexact non-empty
transcript or `LlamaAudioFormatException`, a 44.1 kHz stereo copy of
`jfk.wav` must yield the reference, and three concatenated copies (33 s) must
yield it three times. Two truncation checks follow: `jfk.wav` with
`maxOutputTokens` at half the reference's token count, and the 33 s input on a
512-token context, must each fail with
`LlamaSpeechTranscriptTruncatedException` at that limit and a partial
transcript that is a strict prefix of the expected one, and the next
recognition on the same engine must pass.
GGUF TTS adds three interrupt checks after `leak_slope_bound`, then
`interrupt_memory_bound`. `unload_during_synthesis` and
`dispose_during_synthesis` call `unloadModel()` or `dispose()` once a progress
event reports a frame; the task must end cancelled within the 500 ms budget,
and a synthesis after the reload must pass. After one untimed warm-up,
`decode_cancel` times the audio decode of eight uncancelled 12-frame
syntheses, four before and four after a ninth that it cancels a tenth of the
shortest earlier decode time after its twelfth frame is reported. Timed from
that report, the cancelled synthesis must end sooner than the shortest
reference by more than a margin: 0.9 times the spread of the eight decode
times, or a tenth of that decode if larger. With eight references, that
margin lets a cancellation that saves nothing pass no more often than twice
the spread of four did ([#759](https://github.com/leehack/llamadart/issues/759)). If the
decode left after the cancel, less the largest latency of three syntheses
cancelled on hand-back, is within that margin, even an immediate cancellation
could not pass, so the check records `NOT_RUN`, as it does for any unmet
precondition, with the reason and measured numbers; `NOT_RUN` fails the run.
It targets the chunk-boundary decode cancellation of native `v0.4.1-1`
([#322](https://github.com/leehack/llamadart/issues/322)).
`interrupt_memory_bound` holds the footprint after the three checks to
1.10x the sample taken after `leak_slope_bound`. Running them after the
lifecycle bounds keeps their reloads out of the lifecycle baselines and peak,
and puts the lifecycle's own reload overhead in their baseline. Like the peak
ratio, it records `SKIP` on Linux CUDA, where the interrupt checks then have
no memory bound. A run executes 28 checks for `stt`, 25 for `tts` and 21 for
`litert-asr`.
TTS rejects silent, nonfinite or truncated output; playability is not a
listening-quality assertion. Its first playable audio is
the final buffer, never a progress callback. The voice report preserves the
transcript and chat response and writes the synthesized response WAV.

These new speech commands are **diagnostic local runners**, not yet portable
bundle/Firebase adapters or accepted qualification-report imports. They never
set `qualified=true`. Exit zero means the selected functional assertions passed,
not accelerator or perceptual qualification. Full microphone/playback,
noise/language/voice fixtures, mobile/Web speech packaging, and historical
speech dashboards remain open. A supported backend request still requires
actual hardware execution evidence before marking a platform/backend row green.

### Speech to text: validated behavior

The `validation-speech-stt` pack
(`dart run tool/testing/run_local_e2e.dart --scenario validation-speech-stt`)
runs the checksum-locked Qwen3-ASR 0.6B Q8_0 model and projector on `jfk.wav`,
an 11-second English WAV, as a file and as bytes. It scores each transcript
against the reference by word error rate, after lowercasing both and replacing
`.,!?:;"—–` with spaces. It also sends four generated WAV inputs as bytes:

| Input | Required outcome |
| --- | --- |
| 3 s of digital silence | `LlamaSpeechException` with the message `Speech recognition produced an empty transcript.` |
| The first 20,044 bytes of `jfk.wav`, whose RIFF header declares more audio than the bytes carry | A non-empty transcript that is not the reference, or `LlamaAudioFormatException`. Every recorded run returned a short transcript and no error. |
| `jfk.wav` resampled to 44.1 kHz stereo | The reference transcript |
| `jfk.wav` three times (33 s) | The reference three times |

It then sends `jfk.wav` with `maxOutputTokens` at half the reference's token
count, and the 33 s input on a 512-token context. Each must fail with
`LlamaSpeechTranscriptTruncatedException` at that limit, with a partial
transcript that starts the expected one, and the next recognition on the same
engine must return the reference.

Each run then repeats eight cancel/dispose/load/generate cycles. It fails if
any budget is exceeded:

- **Cancellation, 500 ms**: from `cancel()` to the task's terminal state, for
  every cancel issued as soon as `transcribe` returns and every cancel issued
  after half the duration of the most recent completed generation. This bounds
  when the task ends for its caller, not when native work stops.
- **Memory, 1.10x**: the largest whole-process memory footprint sampled after
  the checks that follow the first generation, as a multiple of the one sampled
  right after that generation. Not applied on Linux CUDA, where the weights
  stay in device memory
  ([#686](https://github.com/leehack/llamadart/issues/686)).
- **Memory growth, 7 MiB per cycle**: the run fails if the footprint grows
  by more than 7 MiB in every one of the seven cycles after the first. A
  plateau passes; a steady leak fails. Slower growth passes this check.

With native `v0.4.1-1` (before the `v0.5.0` pin), the pack has passed
on macOS arm64 with CPU and with Metal, and on Linux x64 with CPU (AMD EPYC
7B12). The Metal runs report the Metal backend; the pack does not verify GPU
execution.

### Preparation progress on interrupted runs

Native desktop and Flutter validation write a separate `preparation.jsonl` with `preparation_progress`
records before inference: download started/finished, checksum started/verified
(or rejected), and ready only after size and SHA256 verification. Active byte
processing emits at most one progress update per ten seconds per stage; a stalled
network does not emit a heartbeat. Records contain profile ID, locked model hash,
processed/expected bytes and elapsed preparation milliseconds, never a URL or
local model path. Subtract stage timestamps to separate transfer from verification
cost. Existing completed-run `download_ms` and `checksum_ms` remain available.

These flushed JSONL records also appear in provider logs with the
`LLAMADART_PREPARATION` prefix. They leave the manifest-first suite protocol
unchanged and survive a provider timeout where no suite
manifest was written, but cannot qualify a run or replace missing test results.
The eight-minute S24 Gemma 4 attempt reached model loading only after about 7m44s;
its old logs do not distinguish transfer and checksum cost. Use these records
before choosing a longer timeout or another model delivery strategy, and recheck
free allowance before any device dispatch.

### Desktop CUDA payloads

Linux x64 and Windows x64 validation bundles explicitly include CPU, Vulkan and
CUDA modules through the private harness hook configuration. Bundling fails if
any is missing; selecting a CUDA profile alone does not override Dart build-hook
defaults. The GPU driver remains a host prerequisite, and a shipped CUDA module
is not execution or placement evidence. On Linux the CUDA 12 runtime
(`libcudart.so.12`, `libcublas.so.12`) is a host prerequisite too, and the
portable bundle refuses `LD_LIBRARY_PATH`, so the runtime must resolve through
the default loader path (an `/etc/ld.so.conf.d` entry, then `ldconfig`).
Without it the CUDA module fails to load, the cases run on CPU, and the run
reports `accelerator_evidence_missing`. Earlier 31867c10c CI bundles use the
CPU/Vulkan defaults and must not be used for CUDA qualification.

### Terminal Firebase recovery and release catalog 3

Firebase polling retains safe failure categories and HTTP status codes without
response bodies, authentication values or request URLs. Transient read failures
retry at most three consecutive attempts under the original run deadline; the
controller never retries submission. Interrupted runs stay unqualified. Failed
Firebase runs cancel/verify terminal state before collecting final artifacts;
pre-terminal snapshots cannot be labelled complete. GCE still collects before
VM/disk deletion. An unknown cleanup state continues to block new submissions.
Manual Firebase cleanup invalidates earlier collections and refreshes provider
status. Follow it with `collect`, which refreshes terminal status again before
retrieval. A failed recovery persists an incomplete, unqualified assessment;
cancelled preparation-only runs cannot qualify from old artifacts.

Windows compiled CLI bundles resolve native backends from their verified
`bin/../lib` layout, before unrelated working-directory or hook caches.
Explicit native overrides and executable-adjacent bundles retain precedence.

Windows VM uploads and result collection explicitly use legacy SCP (`-O`),
because the Google Windows SSH image used in live validation closed the default
SFTP-based transfer. Linux retains the default protocol. Both remain IAP-tunneled.

Vulkan offload and compute-buffer records do not establish physical GPU use when
the log identifies a software device such as llvmpipe, lavapipe or SwiftShader.
Those runs remain unverified, including mixed software/hardware inventories.
Each Vulkan compute-buffer device also needs matching, unambiguous native
discovery or selected-model evidence identifying recognized GPU hardware.
Both sources must agree when present. Discovery capability columns are stripped
only after checking the original device text for software identities; absent,
conflicting or unknown device names fail closed. CUDA-ready VM images need a Vulkan
loader and a hardware ICD before they can qualify Vulkan or LiteRT WebGPU lanes.

Catalog 3 executes C10 stop-marker comparison and C12 unloaded-engine readiness
rejection/reload recovery. Stop tests retain an unrestricted control, exact
pre-marker output, forwarded stop configuration and subsequent-request recovery;
a model that does not emit the control marker fails the oracle. Readiness tests
require the public `LlamaContextException` contract. Direct native reference
controls do not stand in for either public API case. Catalogs 1 and 2 retain
these cases as unimplemented and cannot claim their execution. Catalog 4 adds
Unicode generation, thinking on/off and tool choice/result controls. Thinking
budgets, tool-bearing batching and model-specific qualification remain separate.


### Catalog 8 structured-output pack

Catalog 8 adds the `structured_output` feature and cases `S01`–`S08`
([#1196](https://github.com/leehack/llamadart/issues/1196)). Focused
`structured_output` or release selection picks them. Every request goes
through public API with thinking off and a 256-token cap.

| Case | Request | Passes when |
| --- | --- | --- |
| `S01.capabilities` | `LlamaEngine.capabilities` | `supportsGrammar`, `supportsLazyGrammar` and `supportsStructuredOutput` match the runtime: all true on native llama.cpp, lazy false on WebGPU, all false on LiteRT-LM |
| `S02.json_object` | Prose prompt, then `{'type': 'json_object'}` | The constrained reply is a JSON object that `parseStructuredJson` returns |
| `S03.json_schema` | Prose prompt, then a `json_schema` with scalars, `null`, enum, nested object and array, required and optional properties, a pattern and forced-empty array, string and object; then `createStructuredJson` | Both replies satisfy the schema |
| `S04.grammar` | Prose prompt, then GBNF `root ::= "cedar-" [0-9] [0-9] [0-9]` | The reply is exactly `cedar-` and three digits |
| `S05.grammar.lazy` | Prompt that asks for a sentence then `ANSWER:` and a color, with a lazy grammar triggered by the word `ANSWER:` | Free text precedes the trigger, and the reply ends `ANSWER: alpha` or `ANSWER: omega` |
| `S06.reject` | Unconstrained prose parsed as JSON; a `{city}` schema reply parsed against a `{zip_code}` schema; a `multipleOf` schema; `responseFormat` type `yaml`; then the hello prompt | `LlamaInferenceException` `Malformed structured JSON output.` and `Structured JSON output did not match the requested schema.`, `LlamaUnsupportedException` for both unsupported requests before any chunk, then a completed reply |
| `S07.stream` | The `S03` schema, streamed | At least two content deltas; every accumulated partial is rejected by `parse` with `LlamaInferenceException`; the final value satisfies the schema |
| `S08.tools.schema` | `ToolDefinition.fromJsonSchema` with an enum unit and enum days, `ToolChoice.required`, asking for fahrenheit and 30 days | One `tool_calls` call whose arguments satisfy the schema |

`S02`–`S05` first send the same prompt unconstrained; if that control
already satisfies the predicate, the case is NOT_RUN. Other constrained
prompts ask for output the constraint forbids. A harness-side schema check
independent of the library's validator decides conformance, and the journal
importer reruns it on every passing record. LiteRT profiles select only `S01`
(`litert_grammar_unsupported`), WebGPU omits `S05`
(`webgpu_lazy_grammar_unsupported`) and direct-native controls omit the pack.
Catalog 1–7 journals keep their inventories, features and fixtures; a
structured-output selection cannot claim an older catalog.

`structured-gguf-cpu` and `structured-gguf-metal` lock Qwen3-0.6B Q8_0.
Qwen3.5-0.8B renders tools as `qwen3CoderXml`, which rejects canonical JSON
Schema tools, so it cannot run `S08`.

```bash
dart run tool/testing/validation.dart local --profile structured-gguf-metal \
  --out .dart_tool/validation/runs/structured-metal
```

The profiles use the `3 + 4` arithmetic fixture of the LiteRT Qwen3-0.6B
profiles: with thinking off, Qwen3-0.6B answers `2` for `2 + 2`
([#509](https://github.com/leehack/llamadart/issues/509)).

Local macOS arm64 (M4 Max) JIT runs on 2026-10-24 with clean source
(diagnostic, not qualification): `structured-gguf-metal` and
`structured-gguf-cpu` each passed 26/26. The grammar reply was `cedar-201`, the
lazy reply ended `ANSWER: omega` after free text, the stream had 16 content
deltas with 14 rejected partials, and the tool call was
`{"city":"Montréal","unit":"celsius","days":3}`. Each unconstrained control
answered in prose (or `ANSWER: BLUE`). With the native grammar setup in
`LlamaCppService` skipped (no grammar sampler is created, so an invalid grammar
is not rejected either), `S02`–`S08` and `C12.grammar` fail and `S01` still
passes.

### Catalog 7 LiteRT-LM restart and overlap

Catalog 7 selects `C08.cancel.restart` and `C08.overlap` for LiteRT profiles
([#1115](https://github.com/leehack/llamadart/issues/1115)). Since
[#656](https://github.com/leehack/llamadart/issues/656), a LiteRT-LM generation
requested after a cancel waits for the cancelled run to end, and one requested
during an uncancelled run throws `LlamaStateException`, on native and Web. Case
versions, fixtures and predicates are unchanged. LiteRT journals from catalogs
5 and 6 keep both cases omitted as `litert_restart_contract_undefined`. The Web
host rejects native LiteRT fixtures, so no LiteRT Web profile runs them yet.

Local macOS arm64 (M4 Max) JIT runs on 2026-10-24 with Qwen3-0.6B, clean
source and LiteRT-LM `0.18.1-2` (diagnostic, not qualification):
`chat-litert-cpu` and `chat-litert-gpu` each passed 17/17. In
`C08.cancel.restart` the second request, issued right after the cancel, began
streaming after the cancelled stream ended (CPU 656 ms after 336 ms; GPU 159 ms
after 86 ms). In `C08.overlap` the timed second request was rejected with
`LlamaStateException` within 4 ms, and the first stream delivered two more
deltas and ended cleanly. The GPU run's placement stayed unverified. When the
native backend starts a post-cancel request without waiting, GPU
`C08.cancel.restart` fails with the wrapped `generation is already in
progress` error; when it queues an uncancelled overlap instead of rejecting it,
`C08.overlap` stays NOT_RUN and the run does not qualify.

### Catalog 6 in-flight cancellation and overlap

Catalog 6 versions `C08.cancel` and `C08.overlap` to 2. Native GGUF runs
measure an uncancelled control and arm a timer, after listening, at one quarter
of its wall duration. This lets the harness exercise native work while a chat
parser withholds protocol-framed output until EOF ([#1217](https://github.com/leehack/llamadart/issues/1217)).
Timers are disarmed when their stream ends; a missed window stays NOT_RUN.

Cancellation still needs fewer native decoded tokens than the same seeded
control, with a positive cancelled token count, matching visible prefix,
ordered completion, recovery and the 5 s deadline. Empty visible output is
valid only with that native interruption proof. Merely firing the timer,
shorter wall time, zero decoded tokens or unchanged native counters cannot
qualify. Web GGUF and LiteRT retain the first-content trigger; the pinned
WASM delegate's explicit cancellation abort remains Web-only evidence.

Overlap must reject the second request with `LlamaStateException` before the
first stream ends, deliver at least one later first-stream delta, preserve
completion order and recover. A successful second request fails the case.
The journal importer rechecks both version-2 success predicates. Catalogs 1–5
keep their original fixture hashes, case versions and classifications;
decision and embedding journals from catalog 5 remain readable.

`C08.cancel.restart` keeps its version-1 contract below: it proves queueing
and completion after cancelling a still-open public stream. With EOF-gated
output it does not separately prove native decoding was interrupted.

### Catalog 5 cancellation, grammar and tool cases

Catalog 5 adds these cases. Each records the precondition it needs and its
timings; a missed precondition is NOT_RUN, never PASS.

| Case | Request | Passes when | Runs on |
| --- | --- | --- | --- |
| `C08.cancel.early` | `cancelGeneration()` right after listening to the short request, before any delta ([#602](https://github.com/leehack/llamadart/issues/602)) | The stream ends without content, thinking or tool calls within the 5 s cancel deadline; the same request then completes with output | Every public-API profile |
| `C08.cancel.restart` | At the first delta of the 256-token cancel request, `cancelGeneration()`, then the short request without waiting ([#655](https://github.com/leehack/llamadart/issues/655)) | The short request, issued before the cancelled stream ended, completes with output and its first delta follows that end | GGUF quick core; LiteRT quick core from catalog 7 |
| `C08.overlap` | The short request at the first delta of the uncancelled 256-token request | It fails with `LlamaStateException` before the first ends, the first streams at least one more delta and ends cleanly after the harness cancels it, and a later request completes | GGUF quick core; LiteRT quick core from catalog 7 |
| `C12.grammar` | Raw request with GBNF `root ::= "unterminated` | Native: `LlamaInferenceException` `llama.cpp failed to initialize the requested grammar sampler.`; Web: `LlamaInferenceException` whose details contain `(invalid grammar)`; then a request completes | GGUF quick core |
| `C07.tools.auto_text` | `ToolChoice.auto` with `get_weather` on the hello prompt ([#654](https://github.com/leehack/llamadart/issues/654)) | Text finish matching the hello regex, no tool call | `tools` selection |

Of the GGUF runtimes, only native llama.cpp defines restart and overlap, so
GGUF Web records both as NOT_RUN. LiteRT profiles run both from catalog 7 and
omit them in catalogs 5 and 6 (`litert_restart_contract_undefined`). LiteRT
profiles also omit `C12.grammar` (`litert_grammar_unsupported`: LiteRT-LM
rejects every grammar). C07.tools version 3 also binds the hello fixture its recovery uses.
On Web, a required trial rejected with the documented
`LlamaUnsupportedException` for a lazy required-tool grammar counts as that
trial's result; elsewhere the rejection stays ERROR. Catalog 1 to 4 reports
keep their inventories, C07.tools version 2 and fixtures; a catalog 5 case in
them fails the report.

The `chat-gguf-*` and `gemma4-gguf-*` profiles select `focused` with `tools`.
Their C07 fixtures are reference-qualified against unmodified upstream
`llama-server` at native v0.5.0's llama.cpp commit
`7fe450e19305b828c199d602c23a8337aaa1f03b` (CPU build, same sampler, thinking
off). For both locked models it calls `get_weather` with `{"city":"Montréal"}`
under `auto` and `required`, answers `17` after the tool result, emits no tool
call under `none`, and answers the hello prompt in text under `auto`. The LiteRT
chat profiles do not select tools: LiteRT-LM rejects `ToolChoice.required` for
Qwen tool calling, and no LiteRT reference emission exists.

Local macOS arm64 JIT runs (2026-09-24, dirty source, not qualification):
`tiny-gguf-cpu` 15/15 PASS; `chat-gguf-cpu` 19 PASS with the known C06 failure;
`gemma4-gguf-cpu` 19 PASS with C07.tools FAIL, because llamadart renders the
Gemma 4 tool result as `response:None{value:}` and the model answers `null`
where upstream renders the result and answers `17`; `chat-litert-cpu` 15/15
PASS. Every catalog 5 case passed on every profile that selects it. With the
native backend reverted to its pre-#657 source, C08.cancel.restart and
C08.overlap fail with the wrapped `generation is already in progress` error;
with the engine-level cancel record disabled, C08.cancel.early fails with full
output.

### Current Qwen tool and history reference (2026-09-19)

The unchanged catalog-4 Qwen CPU profile from suite `b13c545f`, run in an
isolated setup against main `699969b0` after PRs #531 and #529, records
**16 PASS, 1 FAIL, 0 ERROR**. C07 auto/required/none, exact tool arguments,
typed-Map result follow-ups and recovery pass. C06 still returns `Cedar17`
instead of the strict expected `cedar17`; no predicate was relaxed. This is JIT
diagnostic evidence, not a sealed current-PR portable qualification report.

For the locked Qwen3.5-0.8B-Q4_0 model (SHA256
`57d1997790d1744fba5b40a7317df71ea5e2acee28c47e78f0cce39c0703f8cf`),
unmodified upstream `llama-server` at native v0.4.1's exact upstream commit
`b29c606e28a01b1bc8c1351026a0fa6e616bf6c4` matches all 11 diagnostic trials:
rendered prompts, input token IDs and public/raw Dart outputs. The original
history remains intact. Three baseline repetitions return `Cedar17`; disabling
the repetition penalty returns `17`, while changing the stored code to `maple42`
returns `maple42` and removing history produces a different output. The same
explicit-case instruction still returns `Cedar17` on both paths.

This does not demonstrate a Dart history-loss or parser defect, and it does not
distinguish original model behavior, quantization or upstream numerical execution.
Keep the exact conformance failure and `qualified=false`. A separate multi-secret
history-transport diagnostic, if added, must not replace this obligation.
The [tracking diagnosis](https://github.com/leehack/llamadart/issues/514#issuecomment-5738623925)
records source/model/settings and attribution limits. Gemma3 LiteRT issue #513
remains a distinct investigation; this CPU GGUF control does not qualify other
models, runtime backends or devices.

## Android trace collection capability

The private [A35/Pixel native-public diagnostic harness](../packages/llamadart_validation/native/android_qualification/README.md)
retains exact #1092 generation and #1304 EG2 Q8 controls, owned native deadlines,
raw capture and correctness gates. Its diagnostic envelopes never grant portable
suite or release qualification; Android launch, placement and provider cleanup
remain separate admission and evidence requirements.

The maintained [model-free Perfetto probe](android_perfetto_capability.md)
collects registered producer descriptors and a fresh trace with CPU/idle
controls on Android/API 34+. Use its separate A6-capability row, exact reviewed
APK source and digest evidence, bounded cloud reservation and no retry. It
qualifies trace collection only; GPU model placement remains unqualified.

### Android internal diagnostic reports

The maintained Android builder can opt into a fixed app-private report directory:

```sh
dart run tool/testing/validation.dart build --target android --profile tiny-gguf-cpu --out /tmp/validation-android --internal-diagnostic-run-id attempt-one
```

Use a new run ID of 1–80 ASCII letters, digits, underscores or hyphens, starting
with a letter or digit. This option requires clean committed source and the
public API execution path. The builder supplies the exact executable profile,
model hash and size, ordered case IDs, commit, tracked-source inventory hash,
hook hash and LiteRT tag to both APKs. It checks source identity again before
sealing the bundle. `environment.json` records the complete binding. Ordinary
builds retain their existing report location.

The opt-in report directory is `files/validation/runs/<run-id>` relative to the
app-private `run-as` directory. Collect only that exact admitted ID. It contains
`events.jsonl`, `manifest.json`, `results.json`, `junit.xml`, `samples.csv`,
`summary.html`, optional `preparation.jsonl`, and `diagnostic-seal.json`. The
seal binds source/profile/model/cases and each payload's byte size and SHA256.
Limits are 8 MiB total including the seal, 2 MiB per file, 256 KiB preparation,
and 64 KiB per event. Existing runs, links and unexpected entries are rejected.
The app-private directory must have no concurrent independent writer; Dart
filesystem checks do not provide atomic protection against a same-UID racer.

Failed tests still produce diagnostics where possible. `complete` describes
report structure; `assertions_passed` describes functional checks. Neither ADB
transport exit zero nor a partial seal establishes passing instrumentation or
model qualification. A collector must validate the full binding, fixed inventory,
checksums and maintained report, and retain failed or incomplete evidence.
This option requires newly built, separately reviewed app/test APKs; it cannot
recover reports from historical APKs or authorize another device attempt.

### Catalog 9 tokenization pack

Catalog 9 adds public-engine `tokenization` focus and release cases. The
locked `tokenization-gguf-cpu` profile reuses the tiny Stories15M model and its
known decoder space prefix. The fixed corpus contains empty input, ASCII,
repeated and edge spaces, newlines/tabs, accented text, emoji, Korean,
combining marks, Chinese and Arabic. Fixture identity is hashed with each case.

| Case | Public path | Passing evidence |
| --- | --- | --- |
| `T01.roundtrip` | `tokenize(addSpecial: false)` twice, then `detokenize(special: false)` | Nonnegative integer IDs, nonempty encoding of nonempty text, identical repeated IDs and exact decoded text; only the locked prefix may precede nonempty input, while empty input decodes to empty text |
| `T02.count` | `tokenize(addSpecial: false)` and `getTokenCount` | Integer count equals the encoded list length for every input, including empty input |

The importer rechecks the complete ordered corpus and options against the
locked profile; missing rows, changed inputs, invalid IDs, unstable results,
lost whitespace and incorrect counts invalidate a claimed PASS. A reference
adapter without public `getTokenCount` records T02 NOT_RUN. Direct native-C
reference profiles omit both cases because they bypass the public API.
Catalogs 1–8 retain their original inventories, features and fixture hashes;
a tokenization focus or prefix override cannot claim an older catalog.

```sh
dart run tool/testing/validation.dart local --profile tokenization-gguf-cpu \
  --model /path/to/stories15M.gguf --out /tmp/tokenization-cpu-run
```

Model-free byte-tokenizer tests verify the production engine/adapter wiring and
journal checks only. Exact upstream token IDs, special-token insertion/rendering,
normalization-specific tokenizers, other model families, Web, LiteRT-LM and
physical devices require their own runs and any needed model-specific oracles.
The pack adds no blanket platform qualification or device campaign.

## Catalog 10: native JSON Schema capability

S01.capabilities version 2 adds a fixed, versioned predicate for the corrected
Qwen3-0.6B CPU profile on macOS arm64 with the verified v0.18.1-4 payload and
actual LiteRT-LM CPU diagnostics. It expects structured output true with GBNF
and lazy grammar false. Provider admission cannot waive that expectation.
Known excluded hosts/delegates expect false; unprofiled models or insufficient
provenance produce NOT_RUN/incomplete. The importer reconstructs this predicate
from the journal identity and load diagnostics; altered identities or a forced
capability/admission cannot establish PASS. Catalogs 1–9 remain unchanged.

This case checks capability reporting, not schema enforcement. The maintained
`litert-lm-json-schema` local scenario separately qualifies native schema
enforcement per model and CPU/GPU backend: adversarial control, the shared
GBNF/LLGuidance contract, Gemma 4 thinking, request reset, system/history,
cancellation/reuse and length cutoff. See [the matrix](testing_matrix.md).


## Catalog 11: state persistence pack

Catalog 11 adds the bounded public `state_persistence` pack for
[#1196](https://github.com/leehack/llamadart/issues/1196). It depends on the
catalog-10 schema capability contract and the typed state-capacity error fix;
older catalogs retain their exact fixture and case contracts.

| Case | Required proof |
| --- | --- |
| `P01.capability` | Independently expected capability; known unsupported runtimes reject both operations with `LlamaUnsupportedException` and still generate |
| `P02.roundtrip` | Prompt-only save returns true and has a nontrivial payload; disposed source and fresh target return the exact IDs |
| `P03.restore_reuse` | Cold exact/suffix score vectors match full references within 0.01 natural-log probability; full vs suffix-only separation is at least 0.10; generation counters prove KV reuse against full-work controls |
| `P04.invalid_recovery` | Missing, garbage, seven-byte header, incompatible version, zero/oversized capacity and below-token-count capacity reject with typed errors; fresh score and generation engines restore correctly after each |

The fixed Stories15M profile uses CPU, context 256, four threads and batch and
micro-batch 8. Source top-K16 IDs define all scored candidates. Save occurs
after prefix scoring with special-token-aware IDs and before any generation.
Every target has its own disposed engine lifetime. Exact reuse evaluates one
token; suffix reuse evaluates the uncached suffix after the token arrays'
common prefix. A no-load control and a loaded reuse-disabled control evaluate
the full prompt. Public generation observers supply usage; immediate
`getPerformanceContext` supplies native prompt work. Scoring disables those
counters for its lifetime, so scoring engines never supply generation proof.

```sh
dart run tool/testing/validation.dart local --profile state-gguf-cpu \
  --model /path/to/stories15M.gguf --out /tmp/state-cpu-run
```

The locked model SHA256 is
`61b50d457809a5194818fd22e6724b456cd7bb9a6264c52c8110684c53f3704a`.
Host preparation verifies model bytes. The importer binds CPU diagnostics,
model/configuration identity, snapshot hashes, ordered distinct lifetimes,
raw finite score vectors, public usage and native work. Corrupt loads may
mutate their context, so recovery uses fresh engines. File format/version
negatives establish header rejection; they do not prove payload rollback.
Same-model/build remains a caller constraint. Arbitrary same-architecture
weights are not guaranteed to be rejected by the native session format.

A missing host workspace or public counter is NOT_RUN/incomplete. The initial
positive profile does not qualify Web, LiteRT, accelerators, other models or
physical devices. KV persistence does not restore sampler/RNG/live logits or
promise exact continuations. Pure journal checks reject inconsistent evidence;
a self-consistent fabricated transcript cannot be disproved without trusted
external artifacts or runtime attestation. The original pre-fix pilot remains
UNQUALIFIED because its typed capacity-error assertion failed; this pack does
not rewrite that result.


Catalog 14 adds `P05.identity` to `state-gguf-cpu`. It calls exported
`stateIdentity()` on the loaded source before saving and on a separately loaded
target before and after restoring. The journal retains runtime build, session
format version, allocated context size and context configuration digest. Import
rechecks the four raw fields, their equality, and the model/configuration/snapshot
bindings; a producer's `matches: true` cannot establish equality. Catalogs 1–13
retain their original definitions and inventories.

The identity unsupported contract is independent of persistence: Web can persist
state but has no native build identity. The identity case checks typed
`LlamaUnsupportedException` and generation recovery for a known unsupported
route; accepting identity there fails. Only the maintained CPU profile is mapped
here. Unsupported-route replay is contract coverage, not Web or LiteRT model
qualification. Missing build identity on old native runtimes remains unsupported.
Old P01–P04 receipts do not qualify P05; it requires a fresh run. Identity equality
does not identify model weights, guarantee exact continuation or establish
cross-build, sampler/RNG, GPU or device compatibility.

## Catalog 12: tool-result media

Catalog 12 adds `M01.tool_result_image` (feature `tool_result_media`) to the
tools coverage for [#1008](https://github.com/leehack/llamadart/issues/1008).
A profile selects it by locking a vision projector next to its chat model and
focusing `tool_result_media`; a profile without a projector omits it as
`no_vision_projector_locked`. Catalogs 1-11 keep their inventories and hashes.

| Step | Required proof |
| --- | --- |
| Capability | `LlamaEngineCapabilities.toolResultMedia` contains `image` |
| Call | With `ToolChoice.required` the model emits one `take_photo` call (`tool_calls` finish) |
| Red, then blue | A history of that call and a `LlamaToolResultContent` carrying a solid-color PNG makes the next turn name that color and not the other |

The two 128x128 PNGs are embedded in the catalog fixture and checked against
their SHA-256. The importer rechecks that the recorded request holds the
fixture image as the only image part of the tool message, so a text-only
answer or a constant guess cannot pass.

```sh
dart run tool/testing/validation.dart local --profile qwen3vl-gguf-cpu \
  --model /path/to/Qwen3-VL-2B-Instruct-Q8_0.gguf \
  --projector /path/to/mmproj-Qwen3-VL-2B-Instruct-Q8_0.gguf \
  --out /tmp/qwen3vl-cpu-run
```

`qwen3vl-gguf-cpu` and `qwen3vl-gguf-metal` lock `ggml-org/Qwen3-VL-2B-Instruct-GGUF`
at `ea6a11058182570be6436b9a2e4ee7f7b49f908d`: `Q8_0` model SHA-256
`b7802e29f71a9e5b5e3f83f613df898a2204342dcea71a231ea501d481813c39` and `Q8_0`
projector `69066c8f279ec85ff48ab4059f6ebba0d2932ca57667f2bbdac7d9805bca9e7b`,
context 4096, with the model's own chat template. Host preparation verifies both
files and the importer requires the projector's hash and size. Only the native
desktop runner prepares the projector; the Web builder and the Flutter app
host reject these profiles before loading with `LlamaUnsupportedException`.
On Metal the placement check counts one llama and one CLIP compute buffer for
each load. Audio, video, URL media, other chat formats,
backends and devices are not qualified by this pack.

## Catalog 13: next-token scoring

Catalog 13 adds the bounded public `next_token_scoring` pack for
[#1196](https://github.com/leehack/llamadart/issues/1196). Catalogs 1-12 keep
their inventories and hashes.

| Case | Required proof |
| --- | --- |
| `N01.capability` | Independently expected capability; LiteRT-LM rejects `scoreNextToken` with `LlamaUnsupportedException` and still generates |
| `N02.top_k` | Two fixed prompts return exactly eight distinct finite log-probabilities, most probable first, with total probability at most 1.001, a `promptTokens` equal to the special-token-aware tokenization and the same result on repeat |
| `N03.candidates` | Candidates (top ranks 0, 2, 5 and the smallest ID outside the top eight) return in request order; each matches its top entry within 0.01, the outsider is no likelier than the least likely top token, and candidates alone return an empty top list; the combined candidates/top-K request preserves the baseline top IDs and scores within 0.01 and the same mass bound |
| `N04.reuse` | After scoring a prefix with prefix reuse on, the extended prompt scores within 0.01 of a no-reuse run, with at least 8 shared and 2 new tokens |
| `N05.guards` | An empty prompt, a negative candidate, a negative `topK` and neither candidates nor `topK` throw `ArgumentError`, and the next score equals the baseline |

```sh
dart run tool/testing/validation.dart local --profile scoring-gguf-cpu \
  --model /path/to/stories15M.gguf --out /tmp/scoring-cpu-run
dart run tool/testing/validation.dart local --profile scoring-litert-cpu \
  --model /path/to/Qwen3-0.6B.litertlm --out /tmp/scoring-litert-cpu-run
```

The profile locks Stories15M (SHA256
`61b50d457809a5194818fd22e6724b456cd7bb9a6264c52c8110684c53f3704a`) on CPU,
context 256 and four threads; other runtimes are `NOT_RUN` until they have an
independent oracle, and non-CPU or non-GGUF profiles omit `N02`-`N05` as
`outside_initial_native_cpu_scoring_scope`.
`scoring-litert-cpu` (Qwen3-0.6B on LiteRT-LM CPU) runs only `N01`, as an
expected-unsupported profile: the importer requires the typed
`LlamaUnsupportedException` plus a working generation afterwards. LiteRT-LM
next-token scoring has an unresolved API/semantic contract
([#1158](https://github.com/leehack/llamadart/issues/1158)); the runtime upgrade
is tracked separately in [litert-lm-native#75](https://github.com/leehack/litert-lm-native/issues/75)
and does not establish scoring support. Until the contract is implemented and
qualified, no LiteRT profile may claim `N02`-`N05`. Among passing records, the
importer also requires N02 trial 0, the N03 baseline and the N05 baseline,
which score the same fresh prompt, to agree on tokens, top IDs and scores
within 0.01. Non-PASS records do not enter that comparison. N04 shows reuse does not change
scores; it does not prove the cache was used (see P03 for counters). Scores
are raw logits, so no sampler setting is covered. The pack does not qualify
Web, accelerators, other models or physical devices.

## Catalog 15: sampler controls

Catalog 15 adds the bounded public `sampler_controls` pack for
[#1196](https://github.com/leehack/llamadart/issues/1196). Catalogs 1-14 keep
their inventories and hashes. Every case decodes raw text with top-K and top-P
disabled, so only the control under test differs from the greedy baseline.

| Case | Required proof |
| --- | --- |
| `G01.capability` | Reported `supportsPenalty`, `supportsPresencePenalty`, `supportsMinP` and `supportsThinkingBudget` match the independent expectation; an expected-unsupported control (LiteRT-LM Min-P) throws `LlamaUnsupportedException` and the engine still generates |
| `G02.min_p` | At temperature 1.5, Min-P 1.0 returns the greedy text for seeds 1-4, and at least one seed without Min-P does not |
| `G03.repeat_penalty` | Repetition penalty 1.5 is reproducible, differs from the greedy baseline and repeats fewer word trigrams |
| `G04.presence_penalty` | Presence penalty 2.0, under the same rules as G03 |
| `G05.thinking_budget` | After a prompt ending in `<think>`, budgets 0 and 4 keep exactly the first 0 or 4 greedy tokens, then force `Time is up.</think>`; the unbudgeted text never closes the block, a budget without tags is rejected, and a rerun matches |

```sh
dart run tool/testing/validation.dart local --profile sampler-gguf-cpu \
  --model /path/to/stories15M.gguf --out /tmp/sampler-cpu-run
```

The profile locks Stories15M (SHA256
`61b50d457809a5194818fd22e6724b456cd7bb9a6264c52c8110684c53f3704a`) on CPU,
context 256 and two threads. Non-CPU or non-GGUF profiles omit `G02`-`G05` as
`outside_initial_native_cpu_sampler_scope`; Web and unsealed hosts are
`NOT_RUN`. On LiteRT-LM, `G01` asserts only that Min-P is unsupported, because
its penalty and budget support depend on the runtime and bundle. Among passing
records, the importer requires the G02, G03 and G04 greedy baselines to agree.
G05 passes explicit tags to raw generation; tags derived from a chat template,
WebGPU bridge capability skew and the LiteRT-LM Qwen3 thinking switch remain
unqualified, as do accelerators, other models and physical devices.
