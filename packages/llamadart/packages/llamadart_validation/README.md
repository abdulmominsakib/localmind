# llamadart validation

Private maintainer package (`publish_to: none`). It exercises the exported
llamadart API through the same core on desktop, Flutter mobile, and Web.
It is independent of the public package's implementation and exports.

## Public capability coverage

`assets/capability_coverage.json` maps source-derived public engine APIs,
capability report members and the support matrix's runtime-feature rows to an
existing feature/case/profile binding or an explicit exemption. From the root:

```sh
dart test -p vm test/unit/tooling/validation_coverage_test.dart
```

CI rejects missing/stale/duplicate mappings, invented cases, missing profiles
and cases that no declared profile selects. Exemptions need a concrete reason
and a GitHub issue. The test prints the current gap inventory; do not maintain
a second copied list. Multimodal chat, LoRA and speculative
decoding still need dedicated pack work.
Speech/image profiles exist, while their individual reported capability
contracts remain explicitly exempt pending case-ID bindings.

A mapping is not a test run or qualification result. It does not waive
unsupported-path negatives, physical-device evidence, provenance or release
gates. Review new exemptions; do not hide a missing pack behind a generic
reason. The registry authorizes no Firebase/GCE runs.

This private harness and the chat app that imports it are both excluded from
the core pub archive. Run them from a repository checkout.

## Tool-stream replay regressions

`test/public_tool_streaming_test.dart` feeds the #740 GPT-OSS text-first frame
and #741 Gemma 4 post-call answer through the real public `LlamaEngine.create`
path and `PublicValidationEngine`. It asserts exact content, tool arguments,
completion order, native GPT-OSS header continuations, hidden reasoning with
`none`, literal thought markers and `auto`/`required`/`none`
controls under split UTF-8 delivery.
Run it from this package with `dart test -p vm test/public_tool_streaming_test.dart`;
the validation-harness CI lane runs it too.

These are deterministic adapter regressions supporting the existing tools pack,
not inference or grammar-enforcement evidence. They do not qualify a model,
backend or physical device. The other family cases under #740 and #741 remain
open.

Catalog 6 also tests native cancellation and overlap independently of visible
output, including EOF-gated GPT-OSS streams. A measured control calibrates the
trigger; native token reduction or an actual overlap rejection proves the
in-flight condition. A missed condition stays NOT_RUN, and older journals keep
their original results. See [the case contract](../../doc/cross_platform_validation.md#catalog-6-in-flight-cancellation-and-overlap).

Catalog 7 runs `C08.cancel.restart` and `C08.overlap` on LiteRT profiles too;
LiteRT journals from older catalogs keep both omitted. See
[the catalog 7 notes](../../doc/cross_platform_validation.md#catalog-7-litert-lm-restart-and-overlap).

## Structured-output pack

Catalog 8 adds `S01`–`S08`, selected by `structured_output` focus or release
selection. `structured-gguf-cpu` and `structured-gguf-metal` lock Qwen3-0.6B
Q8_0, whose Hermes tool format accepts canonical JSON Schema tools. The cases
use only public API: capability flags, `json_object` and `json_schema`
`responseFormat`, `createStructuredJson`, a strict GBNF grammar, a word-triggered
lazy grammar, typed rejection of malformed, mismatched and unsupported output,
streamed partial/final parsing and a JSON Schema tool. Each constrained request
asks for output an unconstrained model would not produce; an unconstrained
control that already conforms leaves the case NOT_RUN. The importer rechecks
passing evidence with an independent schema check. LiteRT profiles run only
`S01` (catalogs 8–9 retain their all-false expectation) and WebGPU omits the lazy-grammar case. Older journals
keep their catalogs. See
[the runbook](../../doc/cross_platform_validation.md#catalog-8-structured-output-pack).

## Catalog 10 native schema capability

`S01.capabilities` version 2 keeps grammar/lazy flags false for LiteRT-LM and
computes the structured-output expectation from the locked corrected Qwen3
CPU profile, verified macOS arm64/runtime payload identity and actual CPU
delegate diagnostics. Provider admission is supplemental, never the oracle.
Known excluded hosts/delegates expect false; unprofiled model bytes or missing
provenance remain NOT_RUN/incomplete, not evidence of unsupported behavior.
An unexpected refusal on the known-supported profile fails. The importer
recomputes the expectation and binds diagnostics to the load case. Catalogs
1–9 and their fixture hashes retain their original contracts.

S01 is capability evidence only. Native enforcement and lifecycle coverage is
the `litert-lm-json-schema` local scenario; no broader schema, Web, GPU or
other-model qualification follows from a capability flag.

## Tokenization pack

Catalog 9 adds `T01.roundtrip` and `T02.count`, selected by `tokenization`
focus or release selection. `tokenization-gguf-cpu` locks the existing tiny
Stories15M GGUF. Both cases call the public engine without injected special
tokens over a fixed corpus: empty input, ASCII, repeated/edge whitespace,
newlines/tabs, accented text, emoji, Korean, combining marks, Chinese and Arabic.
The first requires repeated IDs and exact decoded text; a locked model prefix
is permitted only for nonempty input. The second calls public `getTokenCount`
and compares it with `tokenize(addSpecial: false).length`. The importer checks
all rows independently. A reference adapter without public token count records
that case NOT_RUN; direct native-reference profiles omit this public API pack.

Catalogs 1–8 retain their inventories. Model-free tests exercise the production
engine/adapter and reject corrupted evidence; they qualify no tokenizer, model,
backend or device. Exact upstream token IDs, `addSpecial: true`, special-token
rendering and normalization-specific model families need separate evidence.
See [the case contract](../../doc/cross_platform_validation.md#catalog-9-tokenization-pack).

## Running validation

Start from the repository root:

```sh
dart run tool/testing/run_local_e2e.dart --scenario validation-harness
dart run tool/testing/validation.dart local --profile tiny-gguf-cpu
dart run tool/testing/validation.dart local --profile tiny-gguf-lifecycle
dart run tool/testing/validation.dart build --target desktop --out .dart_tool/validation/bundles/desktop
```

See [the runbook](../../doc/cross_platform_validation.md) for models, bundles,
Firebase/GCE setup, run/recovery commands, evidence and cost boundaries.
See [the full plan](../../doc/cross_platform_validation_plan.md) for subsequent
platform and feature qualification. A quick run does not qualify a release.

`assets/profiles/` locks each model URL/revision/SHA256/size and inference
configuration. The `chat-litert-cpu` profile uses the corrected Qwen3-0.6B
bundle (`e6687177`, SHA-256 `c5f39b41…`) checked by the maintained
`qwen3-litert-cpu-unicode` root scenario. The `chat-litert-gpu` profile retains
the legacy artifact pending separate qualification of the updated bundle; CPU
checks do not qualify GPU/device/Web adoption.
A LiteRT profile with `backend: auto` passes `ComputeDevice.auto` and
`GpuBackend.auto`, allowing the runtime's platform default and GPU-to-CPU
fallback. It does not force CPU placement or prove accelerator execution;
explicit `cpu`, `gpu` and `npu` profiles retain their device requests.
`chat-litert-auto` is `chat-litert-gpu` under `auto`, for the Galaxy S24 GPU
engine failure and CPU retry
([#1458](https://github.com/leehack/llamadart/issues/1458)).

`lib/llamadart_validation.dart` is the platform-neutral suite; conditional native
adapters and `lib/io.dart` handle filesystem/runtime checks. `bin/run.dart` and `bin/report.dart` are the
CLI entrypoints. Flutter uses the package's profile assets and shared runner.
Native wrappers persist JSONL per event; reports always derive from that journal.
`assets/image_profiles/` holds the Firebase image-generation device checks, which
run the chat app's image test (or, for `image-settings-*`, its image settings
comparison) and are graded by its image evidence verifier
([image-generation profiles](../../doc/cross_platform_validation.md#image-generation-profiles)).

The two `npu-*` profiles are locked candidates. Inspect their local prerequisites
with `validation.dart npu-preflight`; the opt-in Android builder packages verified
local model/vendor inputs and the installed app checks its SoC and captures
per-generation execution proof. S24 NPU execution is verified but semantic
qualification still fails; Pixel 10 hardware execution remains NOT_RUN.

Exit 0 means this selected run qualified, 1 means failed/incomplete.
Unknown/dirty source provenance, missing counters, unknown backend placement, skipped mandatory cases and missing
records remain incomplete. Imported model preparation must prove the locked
SHA256 and byte size. Desktop qualification additionally requires the portable
CLI's verified runtime inventory and bundle manifest hash; JIT remains diagnostic.
The CLI rejects runtime overrides, validates its environment and runtime payload,
and anchors native discovery to the bundle. Older desktop journals without this
proof preserve assertions but no longer qualify when reimported. `release` selection deliberately records unimplemented
feature packs as NOT_RUN until their fixtures and wrappers are qualified.
The reporter derives mandatory cases, effective settings and accelerator-proof
requirements from the validated profile. Self-declared inventory, rehashed
conflicting settings and per-record unsupported exemptions cannot waive them.

Reports expose independent `summary.qualification_gaps`: assertion failures,
execution errors, unexecuted cases, missing accelerator evidence, incomplete
provenance, and journal/lifecycle problems. Multiple gaps can coexist. An
unverified accelerator does not establish model or platform incompatibility;
successful inference also does not prove GPU/NPU execution. Execution errors
require diagnosis against the retained native logs and host setup. The HTML
report shows these distinctions and the placement verifier's reason. These
diagnostics do not relax qualification requirements or replace case results.

`C01.load` measures public load/readiness, which can precede native engine
initialization. In LiteRT, the first `C02.unicode` tokenization call can include
deferred engine creation. Its `tokenize_call_ms` is therefore not isolated
tokenizer latency. The runner records this timing scope, separate detokenization
latency, and the active public operation on errors/timeouts. A first-use timeout
does not establish a tokenizer defect. Case deadlines remain 60s unless the embedding pack locks its 300s deadline or a LiteRT
CPU or GPU profile sets `engine_create_case_timeout_ms` for engine-create
cases; provider process deadlines can additionally include model preparation and host startup.

Profiles select `quick`, `focused` or `release`. Focused profiles require a
nonempty, unique `focus_features` list; `tiny-gguf-lifecycle` adds the second
dispose/load/generate cycle to the quick CPU run. Core feature IDs are `text`,
`unicode`, `thinking`, `history`, `tools`, `streaming`, `batching`, `lifecycle`, `guards`, `performance` and,
from catalog 8, `structured_output`. Unimplemented selected cases stay NOT_RUN.

Journal schema 2 includes the versioned case/feature catalog, resolved synthetic
fixtures, explicit omissions and a catalog hash. Each terminal case carries its
case version and fixture hash. Defaults live in `lib/src/case_catalog.dart` and
compile into every host; model overrides remain in the locked JSON profiles.
The reporter validates metadata against the executable catalog and still imports
schema-1 journals with their original inventory. It does not invent missing
catalog provenance for those older runs.

`tiny-gguf-batching` adds C11 text/thinking parity across default, 1-piece/1-byte,
and recovered default worker settings. Trial outputs/configuration/finish order
and metrics are retained; chunk counts may differ. LiteRT Web checks each native
option's typed rejection instead. NPU deterministic parity, GGUF Web controls and
tool-bearing fixtures remain unqualified. Catalog version 2 preserves imports of
version-1 journals against their original case/fixture definitions.

Catalog 4 adds executable C02 Unicode generation (exact output, no trimming),
C05 thinking enabled/disabled (512 output-token bound, separated nonempty thinking
when enabled and none when disabled), and C07 tool choice (`auto`, `required`,
`none`, 128 output-token bound). C07 checks one weather call with exact city
arguments, public completion semantics, synthetic tool-result consumption and
default recovery. The actual tools, choices, prompts, messages and per-call
settings are logged; tool schemas are produced by the public ToolDefinition API.
Failures are strict model/runtime observations, not automatic diagnoses.
Thinking-budget controls and tool-bearing batching remain separate planned work.
Native C API controls do not execute these public feature cases. Catalogs 1–3
retain their original fixtures and unimplemented obligations on import. No
existing device/model run is upgraded by this implementation.

For portable GGUF GPU runs, pass `--native-log <captured-stderr-path>` to the
validation launcher and redirect stderr to that path before starting it. The
launcher uses those bytes for the same placement checks as the standalone
reporter. Missing or invalid UTF-8 captures fail; supplying a log never waives
failed cases, missing records or runtime identity requirements.

For Firebase Android LiteRT GPU runs, remote collection binds the device
`logcat` to the journal and the reporter verifies N GPU delegate
initializations on one hardware Vulkan adapter for the N expected load cases.
The placement is reported as
`gpu_delegate_initialized_per_load_execution_unobserved`: it is not
per-request execution proof, its delegate-kernel count is a consistency check
on top of the upstream compile rule, and its failure-marker list is not
exhaustive. `--native-log` for such a journal must name logcat `threadtime`
records; evidence counts only under the `native` and `litert` tags.

It does not observe CPU engines created elsewhere in the process, the
accelerator mask (inferred from the requested backend and the self-reported
LiteRT-LM tag), subgraphs LiteRT lets delegation skip, the closed ML Drift
delegate internals, or the identity of the shipped binary, and the embedding
and other side models run on the XNNPACK CPU delegate, not the GPU. The
predicate and its limits are in `doc/cross_platform_validation.md`.

## Multimodal embeddings

`embedding-gguf-cpu` (native desktop/Android/iOS) and `embedding-gguf-metal`
(macOS/iOS) lock EmbeddingGemma-2 BF16 plus its matching projector. They select
load plus ten embedding cases: capabilities, text/image/audio, image→audio and
audio→image across the mixed and batch cases, repeated/reordered batch items,
audio normalization, typed unsupported/marker
errors, cancellation before/after backend SPI dispatch and text/media reuse.
They produce no token-throughput samples.

```sh
dart run tool/testing/validation.dart local --profile embedding-gguf-cpu \
  --model /path/to/embeddinggemma-2-BF16.gguf \
  --projector /path/to/mmproj-embeddinggemma-2-BF16.gguf \
  --out .dart_tool/validation/runs/embedding-cpu
```

The [fixture README](assets/embeddings/README.md) records deterministic PNG/WAV
regeneration, upstream-only native CPU reference generation and measured
CPU/Metal kernel spread and negative controls. Separate CPU and Metal entries
both require cosine ≥ 0.999 and max-abs ≤ 0.01, allowing about 10x/6x headroom
over the measured errors while rejecting wrong pooling, missing normalization
and swapped media order. Wrong-projector cohort hashes fail before inference.
CPU one/four-thread vectors reproduced the reference exactly; Metal default and
concurrency-disabled audio had cosine 0.999900635/max-abs 0.001568219, while
fusion-disabled and both-disabled had 0.999906460/0.001644426.
The published archive and contained dylib hashes identify the reference runtime;
a hook-processed local dylib hash does not.

Metal placement requires one full positive tensor-offload record and one
`llama_context` per expected load, plus exactly two MTL0 projector contexts
(`gemma4v`, then `gemma4a`). Each complete llama graph reservation and each
projector reservation must contain exactly one positive MTL0 compute allocation;
CPU scratch allocations may accompany it. Every compute record must belong to
one of those reservations. Pooled embedding toggles can reserve the same llama
context repeatedly, so reservation count has no fixed ceiling; context count
stays exact. CPU-only, partial/zero/missing offload, wrong-device, zero-size,
unattributed or incomplete records remain unverified. Other profiles retain
their existing placement rule and effective-config hashes.

Both profiles lock `embedding.case_timeout_ms: 300000`, included in their
effective-config hashes. E05/E06 each encode one image, and E07 uses audio;
both mixed orders and the batch's repeated item remain checked. The 224×224
fixture encodes at 432×432; the logged 768×768 is projector warmup allocation.
CPU peak footprint is about 1.4 GB (max RSS about 1.9 GB); the projector is not
mmapped. Use ≥6 GB devices for Firebase runs.
Every case verifies all fixture hashes; a missing or changed reference errors
rather than skips. The journal binds `feature_id: embeddings`, case/fixture and
catalog hashes; report import rechecks successful numerical and contract
metrics and projector SHA256/size evidence. Existing catalogs are preserved.

The [runbook](../../doc/cross_platform_validation.md#multimodal-embedding-pack)
has the mobile/Firebase commands and qualification limits. Web and LiteRT-LM
pack coverage remains NOT_RUN until locked inputs and adapters are qualified;
the Web builder rejects these native profiles before downloading. Local JIT
runs cannot supply portable runtime evidence. This private pack changes no
public core API or release changelog.

## Tool-result media pack

Catalog 12 adds `tool_result_media` and `M01.tool_result_image`.
`qwen3vl-gguf-cpu` and `qwen3vl-gguf-metal` lock Qwen3-VL-2B-Instruct Q8_0
and its projector. The case checks the public `toolResultMedia` capability,
has the model call a tool, then sends a tool result that carries a red and a
blue PNG in turn: each answer must name its own color only. A profile without a
locked projector omits the case. See
[the runbook](../../doc/cross_platform_validation.md#catalog-12-tool-result-media).

## State persistence pack

Catalog 11 adds `state_persistence` and P01–P04. `state-gguf-cpu` locks
Stories15M, CPU, context 256 and batch/micro-batch 8. The exported API saves
prompt-only KV, disposes its source, and restores on fresh engines. Tolerant
next-token score comparisons and context sensitivity prove retained history;
observer usage and native prompt-evaluation counters prove reduced work.
Scoring and generation use separate engine lifetimes. Full-work controls
run without a snapshot and with reuse disabled.

Missing storage/counters, unknown model configuration and unqualified host
identity stay NOT_RUN. Known unsupported runtimes run typed rejection and
recovery under P01; positive storage cases are scoped to native GGUF CPU.
IO hosts supply a temporary workspace; browser/common imports stay IO-free.
Each invalid load is followed by fresh score and generation recovery engines,
because corrupt loads need not preserve their context. Negative cases cover
missing, garbage, short and incompatible headers, zero/oversized capacity and
capacity below the saved token count. The importer reconstructs raw score,
usage, counter, artifact recipe, identity and lifetime checks.

Run the [CPU procedure](../../doc/cross_platform_validation.md#catalog-11-state-persistence-pack).
This proves KV persistence only: no RNG/sampler/logit checkpoint, exact greedy
continuation, cross-build compatibility or arbitrary different-model refusal.
A journal is evidence within the harness trust model, not binary attestation;
artifact hashes/recipes do not authenticate bytes without an external resolver.
Catalogs 1–10 retain their existing inventories, hashes and contracts.

## Offline evidence reassessment

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

## State identity

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

## Prospective S24 LiteRT native/public qualifier

The [fixed S24 case graph](native/android_litert/README.md) prepares one reviewed
SC-51E/API36 run against the eventual final 0.19 artifact. It keeps legacy GPU
refusal/fallback evidence separate from corrected CPU correctness, isolates the
corrected GPU attempt in an owned native child, and gates corrected public auto
on that control. Corrected public auto must then retain GPU placement and
fresh native initialization across both lifetimes; CPU fallback fails this
GPU gate while remaining normal product behavior. Source/model-free checks establish no device result and do not
authorize an APK, cloud run or additional budget reservation.

## Original SD24 diagnostic

The maintained `image-original-containers` local E2E scenario uses the private
[original-mode operator](native/sd_original_mode/README.md) for six bounded
native/public same-weight RGB cases. It preserves the original external TAESD,
cache4/flash-attention settings and failed-history evidence. PR41 artifact,
consumer bindings/build receipts and exact plan need independent admission;
model-free source tests are not generation or final-published qualification.

## Android consumer CPU release profiles

The [full/compact release smoke](native/android_qualification/README.md#android-fullcompact-consumer-release-smoke)
uses separately bound consumer configurations and release instrumentation APKs
for old/modern arm64 public CPU load, deterministic generation and full reload.
It reuses raw capture, installed runtime verification and the independent Java
watchdog. Source checks do not qualify any device/profile combination or replace
the existing native/public issue controls.
