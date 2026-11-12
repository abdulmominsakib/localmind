# Contributor Test Matrix

This repository uses a layered test matrix so contributors can validate the
essential runtime, model, feature, and platform paths without forcing every pull
request to run large local models or device-only checks.

The proposed [cross-platform validation plan](cross_platform_validation_plan.md)
details reusable test apps, model/backend cases, metrics, a free Firebase
physical-device rotation, and VM/Firebase upload, execution and cleanup. It is
planning work; implementation is deferred until
the current release additions are complete, and its proposed rows are not yet
implemented by the runners below.

Use the matrix for every non-trivial PR:

```bash
dart run tool/testing/test_matrix.dart --list
dart run tool/testing/test_matrix.dart --pr-template
dart run tool/testing/test_matrix.dart --tier platform
dart run tool/testing/run_local_e2e.dart --list
```

Copy the PR evidence table into the pull request, keep the rows that apply to
the change, and mark skipped rows as `N/A` with a concrete reason.

## Matrix Tiers

| Tier | Meaning | Expected use |
| --- | --- | --- |
| `essential` | Cheap baseline package health checks. | Run for most code PRs and expect CI to cover them. |
| `targeted` | Runtime/model/feature checks selected by touched code. | Run locally or cite the matching CI workflow when the PR touches that path. |
| `high-risk` | Exact-head independent QA and adversarial production-path evidence. | Required before mark-ready for parser/grammar/streaming, backend/runtime, capability, artifact-consumer, release-automation, or regression-policy changes. |
| `platform` | Supported platform or architecture validation rows. | Use when a PR affects runtime packaging, native pins, backend selection, app launch, or release confidence for a platform. |
| `release` | Device or representative smoke checks that are too heavy for every PR. | Run for release candidates, native bundle changes, or high-risk runtime changes. |

## Evidence Standard

Each PR should answer four questions:

| Question | Evidence to include |
| --- | --- |
| What changed? | User-facing scope and touched runtime or feature path. |
| Which rows apply? | Matrix row IDs from `tool/testing/test_matrix.dart`. |
| What ran? | Exact command, CI workflow/check name, device, model, and backend. |
| What happened? | PASS/FAIL/N/A plus failure logs, artifact links, or a reason for N/A. |

Prefer exact model names and backend selections over broad phrases. For example:
`Gemma 4 E2B GGUF, WebGPU/llama.cpp, mem64, gpuLayers=0, contextSize=2048`.

## Essential Baseline

The baseline rows are:

```bash
dart run tool/testing/test_matrix.dart --tier essential
```

For a typical code PR, include:

- `static-format-analyze`
- `root-vm`
- `root-chrome` when shared, web, template, or public API code changed
- `coverage-lib` when `lib/` behavior changed or coverage is in doubt: PR CI
  runs no coverage, and `main` enforces the 70% threshold after merge
  (`doc/ci_selection.md`)

On macOS, run `root-vm` and other local VM rows with an isolated temp directory
(`TMPDIR="$(mktemp -d)"`). LiteRT-LM engines without `liteRtLmCacheDir` prune
the shared program caches in `$TMPDIR/llamadart_litert_lm`; local-only
LiteRT-LM E2E rows prune that real cache like any 0.13 app. CI runs the VM
lanes against a scratch temp directory and fails when a test deletes the
oversized canary cache seeded there (`tool/ci/litert_lm_temp_canary.sh`).

Docs-only PRs can mark runtime rows `N/A`, but should run `docs-site` when docs
or website files changed.

## High-Risk Pre-Merge Review

Discover the high-risk rows with:

```bash
# Replace upstream/main with the remote/ref for the current PR base.
PR_BASE_REF=upstream/main
git diff --name-only --no-renames "$PR_BASE_REF"...HEAD | \
  dart run tool/testing/classify_high_risk_changes.dart
dart run tool/testing/test_matrix.dart --tier high-risk
```

Before mark-ready, assign an independent blocking-only adversarial review pass:
an operator, or a fresh agent session that took no part in the
implementation, never the PR author or the retired `qa` identity. It must
review the exact head against the current base, inspect the actual production
call sites, and verify positive and negative tests that fail if the relevant
branch is deleted, bypassed, or miswired.
Validate the evidence payload with `tool/testing/high_risk_readiness.dart`,
supplying repository, PR, author, exact head, and exact base values from an
independent source as documented in `doc/high_risk_pre_merge_readiness.md`.
The evaluator derives the rename-aware changed-file inventory from Git and
rejects deleted, renamed-old, non-test, and phantom evidence paths. Existing
tests are accepted with independently reviewed production reachability and causal
before-fix or mutation evidence; changed filenames alone are insufficient.
Fill the PR template's high-risk block with the task identities, exact head/base,
affected-family evidence or precise N/A, zero known PR-caused P1 regressions,
and the live unresolved-thread count. A known PR-caused P1 or any unresolved
thread blocks readiness.

For structured output, use evidence v2 and review three behavioral impacts:

- Input rendering/history: byte, role, content, typed tool-result and history
  preservation plus affected-family upstream comparison.
- Output parsing/streaming: scalar/container schema reconstruction, partial
  suppression, malformed-final rollback, tool choice/thinking, and upstream parity.
- Grammar/schema enforcement: compiled acceptance/rejection, reconstruction,
  tool choice/thinking, and upstream parity.

The independent exact-head/base audit records source-grounded exclusions for
unaffected impacts. Shared handlers and unknown/mixed changes require all axes.
See `doc/high_risk_pre_merge_readiness.md` for the evidence contract. Do not edit
unrelated grammar tests just to satisfy a rendering-only change.

Use the closest affected-family real model or artifact. When it is unavailable,
name every unavailable family and substitute primary upstream emissions plus
durable fixtures. An unrelated representative model can validate the shared
pipeline only; it cannot be reported as affected-family evidence.

The readiness evaluator validates the repository-local portion of these rules;
it never emits operational readiness. External auditor authentication, GitHub
App status publication, protected-environment provenance, and conditional
ruleset enforcement remain unavailable and fail closed. The default-branch
workflow is a non-required advisory that warns on high-risk paths instead of
failing. See
`doc/high_risk_pre_merge_readiness.md`.

The structured-output requirements encode the regression classes found after
the broad parser rollout: envelope/name escaping and quoting (#394/#399),
schema exactness and wrong-type rejection (#395/#396/#407), partial-protocol
leakage and malformed-final content loss (#397/#398), thinking/tool-choice
prefix handling (#402/#406), and empty/schema-directed value reconstruction
(#408/#410). The compiled production-path coverage added separately to `main`
is the durable execution proof; this policy slice does not duplicate it.

## Targeted Runtime and Model Rows

Pick targeted rows based on the touched surface:

| Change area | Matrix rows to consider |
| --- | --- |
| Genkit adapter, its gateway docs, or independent publication | `genkit-contracts`, `genkit-native-cpu`, `genkit-release`; see [package maintenance](../website/docs/maintainers/genkit-package.md) |
| Shared model store package or its guide | `model-store-contracts` |
| Native sync tooling under `tool/native/`, `lib/src/hook/native_release_pins.dart`, `sync_native_bindings.yml`, an Apple companion `Package.swift`, or a runtime pin constant | `native-sync-python-suites`, `native-release-digests` |
| Native-assets hook, runtime pin, bundle layout | `native-hook-bundles`, `litert-lm-engine-smoke`, and relevant `platform` rows such as `android-arm64-device-smoke` |
| Ordinary default llama.cpp consumer and distributed AOT | `native-default-consumer-aot` (explicit local/manual macOS arm64 and Windows x64; native2 pipeline-only, exact native3 qualification separately accepted) |
| Windows llama.cpp registry or native-module override loading | `root-vm`, including `test/integration/windows_ggml_registry_test.dart`; fresh-process Windows model/context load with normal assets and the #1649 override matrix below |
| llama.cpp / GGUF generation, prompt reuse, context reuse | `native-prompt-reuse-parity`, `native-inference-benchmark`, `gguf-chat-features-smoke`, `native-prompt-cancel` |
| Generation cancel or engine stream forwarding | `native-prompt-cancel`, plus `web-speech-task-cancel` for browser speech task isolation |
| llama.cpp native pin, object creation and free paths, exit or isolate shutdown | `native-exit-teardown` |
| Speculative decoding, bundled MTP, or n-gram drafting | `llama-cpp-speculative-benchmark`, `gemma4-mtp-smoke` |
| Embedding API, `embedBatch`, or embedding throughput | `native-embedding-benchmark`, `native-embedding-sweep` |
| Text embedding profiles, task/document titles or output dimensions | `text-embedding-retrieval` |
| Chat template, parser, tools, thinking extraction | `template-parity`, `llama-cpp-chat-template-smoke`, `gguf-chat-features-smoke`, `litert-lm-chat-features-smoke` |
| Tool-result media (`LlamaToolResultContent.content`, `LlamaToolOutput`) | `root-vm`, `tool-result-image-smoke`, validation `qwen3vl-gguf-cpu` / `-metal` (`M01`) |
| LiteRT-LM embedding engine | `litert-lm-multimodal-embedding`; includes the documented local-only upstream WebGPU parity diagnostic |
| LiteRT-LM native backend | `litert-lm-lifecycle`, `litert-lm-engine-smoke`, `litert-lm-chat-features-smoke`, `litert-lm-json-schema`, `litert-lm-asr-smoke`, `litert-lm-asr-preservation`, `litert-lm-media-preservation`, `litert-lm-utility-preservation` |
| Web bridge bootstrap or interop | `web-bridge-smoke`, `web-mock-chat-smoke`, `web-real-model-smoke`, `web-tool-penalty-smoke`, `web-lazy-grammar` |
| WebGPU multimodal | `webgpu-multimodal-regression`, `web-speech-task-cancel`, plus `web-speech-to-text-smoke` for typed Qwen3-ASR and `web-text-to-speech-smoke` for typed Qwen3-TTS |
| Large WebGPU GGUF / wasm64 selection | `gemma4-webgpu-mem64` |
| LiteRT-LM web / Gemma 4 web bundle | `gemma4-litert-web` |
| Chat app model cache/download/projector | `chat-app-device-cache` |
| LiteRT-LM native JSON Schema on a device | `chat-app-litert-json-schema` |
| LiteRT-LM engine reload memory on a device | `chat-app-litert-reload-memory` |
| LiteRT-LM bundle in a read-only directory on a device | `chat-app-litert-read-only-bundle` |
| Android Vulkan prompt cap, Vulkan device facts or the Vulkan 1.2 load refusal on a device | `chat-app-micro-batch-sweep` |
| Isolate shutdown releases, exit teardown, a Flutter pin bump, or app-exit guidance | `chat-app-macos-quit` |
| Speech-to-text API or adapter | `speech-to-text-smoke`, `web-speech-to-text-smoke`, plus `litert-lm-asr-smoke` and `litert-lm-asr-preservation` for the dedicated LiteRT-LM streaming engine |
| Text-to-speech API or adapter | `text-to-speech-smoke`, `text-to-speech-models-smoke` for LFM3-Audio, Soprano, Chatterbox and Pocket TTS, plus `web-text-to-speech-smoke` for browser synthesis/playback/export |
| Decision engine, decision head, or safetensors reader | `decision-model-smoke`, plus `decision-model-web-smoke` for the Web decision head or bridge pin |
| Image generation API or `stable_diffusion` runtime | `image-generation-smoke`, `native-hook-bundles` |
| Complete image checkpoint formats or explicit role transport | `image-container-formats` (local hashed inputs and independent CPU references) |
| `stable_diffusion` runtime pin, image worker native calls, progress polling, exit or isolate shutdown | `image-exit-teardown`, `image-generation-smoke` |
| Chat-app image screen or image model downloads | `chat-app-image-generation-smoke` |
| Physical-device image evidence on Firebase, or image evidence grading | `firebase-image-generation-e2e`, `validation-harness` |
| llama.cpp and `stable_diffusion` loaded in one process on a device | `chat-app-text-image-coexistence` |
| Automatic image `flashAttention` or `vaeDirectConvolution` defaults, or re-measuring them on a device | `chat-app-image-settings-comparison` |
| Chat-app microphone transcription flow | `chat-app-microphone-transcription-smoke` |
| Chat-app live LiteRT-LM dictation | `litert-lm-asr-smoke`, `chat-app-live-speech-smoke` |
| Chat-app Ask with voice | `gguf-audio-chat-smoke`, `litert-lm-chat-features-smoke`, `chat-app-voice-question-smoke` |
| Example app, CLI, or server package | `examples-tests` |

`litert-lm-asr-preservation` is a local-only CPU campaign using the public
`SpeechToTextEngine` and normal published native assets, with Whisper Tiny
(`92f194600d98e1d94b1ff6f636d109c0f4ac66f3f6a1803f7a665e93daf78012`), its
tokenizer (`27fc476bfe7f17299480be2273fc0608e4d5a99aba2ab5dec5374b4482d1a566`)
and the JFK mono 16 kHz PCM16 WAV
(`59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e`).
Pass those files with `--model-path`, `--tokenizer-path` and `--audio-path`;
the scenario fixes the preset and expected transcript. It checks streaming
partials and final text, three seconds of empty silence through stream and task,
active stream/task cancellation, same-engine reuse and fresh recognizer reload.
Each case is bounded to 30 seconds and the suite to three minutes. JSON evidence
includes fixture hashes, completion states, text and event counts. This row does
not qualify GPU placement, microphone UI, latency or other model families.

Apple companion hook changes also require
`dart test -p vm --run-skipped test/integration/apple_companion_flutter_cache_test.dart` on
macOS with the pinned Flutter SDK. This explicit `local-only` test runs in a
temporary clone and exercises fresh/warm Flutter tests, rejects a newly added
local `Artifacts` override, then verifies recovery after removal without
clearing caches. The macOS `Companion Packages` CI job runs it explicitly, on the
same selection as `Test Native`.

The required `Web Chat Contract` check runs the chat app tests on VM and
Chrome, validates the final Flutter Web artifact, exercises deterministic UI
behavior, and loads a tiny real GGUF through the packaged worker and WASM core.
Large Gemma 4 GGUF and LiteRT-LM downloads remain targeted rows so transient
model-host availability does not make every pull request flaky.
`Example Package Tests` runs the other example packages' model-free tests on
full-graph changes, which include any non-Markdown change under `example/`
outside `example/chat_app`. Chat app changes and Markdown under `example/`
do not select it.

## Coverage Map

Public capability obligations live in
[`capability_coverage.json`](../packages/llamadart_validation/assets/capability_coverage.json).
Run `dart test -p vm test/unit/tooling/validation_coverage_test.dart` for the
source-derived engine API/capability/runtime-row inventory and its current
exemptions. A mapping is not evidence of execution or qualification; use the
affected runtime/model/platform rows for that evidence.

The matrix is designed to cover these essential axes:

| Axis | Covered by |
| --- | --- |
| llama.cpp native GGUF | `root-vm`, `native-prompt-reuse-parity`, `native-inference-benchmark`, `gguf-chat-features-smoke`, `gguf-audio-chat-smoke`, `decision-model-smoke` |
| llama.cpp WebGPU GGUF | `web-bridge-smoke`, `web-mock-chat-smoke`, `web-real-model-smoke`, `web-tool-penalty-smoke`, `web-lazy-grammar`, `webgpu-multimodal-regression`, `web-speech-to-text-smoke`, `web-text-to-speech-smoke`, `web-speech-task-cancel`, `gemma4-webgpu-mem64`, `decision-model-web-smoke` |
| LiteRT-LM native `.litertlm` | `litert-lm-engine-smoke`, `litert-lm-chat-features-smoke`, `native-hook-bundles` |
| LiteRT-LM web `.litertlm` | `gemma4-litert-web` |
| Model families | Qwen 2.5 prompt reuse, Qwen 3/3.5 chat/multimodal, Gemma 4 tool/thinking/mem64/LiteRT-LM/audio, Laya ModernBERT decision encoder and head |
| Feature paths | load/generate, prompt reuse, chat templates, streaming, tool calls, thinking, multimodal image/audio, model cache, native hook packaging |
| Platforms | See `dart run tool/testing/test_matrix.dart --tier platform`; each supported family/architecture is marked as CI, local, manual/device, or hook-only. |

## Web Speech Task Cancellation

`web-speech-task-cancel` runs real Qwen3-ASR and Qwen3-TTS cancellation
isolation and subsequent engine reuse through both direct and worker bridge
paths. It fetches the pinned bridge into
`build/web_speech_task_cancel/bridge/`. Stage compatible model/projector pairs
and a WAV with a known exact transcript under `build/web_speech_task_cancel/`,
then create `config.json` there (all paths are relative to that config):

```json
{
  "assets": "bridge/",
  "asrModel": "asr.gguf",
  "asrProjector": "asr-projector.gguf",
  "audio": "speech.wav",
  "expectedText": "The exact transcript of speech.wav",
  "ttsModel": "tts.gguf",
  "ttsProjector": "tts-projector.gguf",
  "manifestSha256": "<SHA-256 of bridge/manifest.json>",
  "ttsBatchSize": 512,
  "ttsMicroBatchSize": 256,
  "sha256": {
    "asrModel": "<SHA-256>",
    "asrProjector": "<SHA-256>",
    "audio": "<SHA-256>",
    "ttsModel": "<SHA-256>",
    "ttsProjector": "<SHA-256>"
  }
}
```

Verify the staged files outside the browser and put their digests in `sha256`:

```bash
cd build/web_speech_task_cancel
shasum -a 256 asr.gguf asr-projector.gguf speech.wav tts.gguf tts-projector.gguf
```

Use the file names in your config. The suite checks the bridge manifest and WAV
digests; the model/projector digests are externally verified provenance, printed
from the config, rather than browser-verified multi-gigabyte copies. No models
are downloaded by this scenario. Run `--list`, then
`--scenario web-speech-task-cancel --dry-run` before the real run:

```bash
dart run tool/testing/run_local_e2e.dart --scenario web-speech-task-cancel
```

The default `gpuLayers` is zero: this qualifies browser CPU execution, including
worker isolation, rather than GPU inference. Add a positive `gpuLayers` value
only on a WebGPU-capable machine; GPU qualification requires the test's WebGPU
backend assertion to pass. A worker fallback cannot qualify the worker path.

The Qwen3-TTS profile uses context 4096, batch 512 and micro-batch 256, matching
the batch settings in the pinned bridge owner's speech smoke. The optional
`ttsBatchSize` and `ttsMicroBatchSize` config values change only this test recipe, not public
`ModelParams` defaults. TTS controls synthesize one and eight frames without
cancellation, then check a first-progress cancellation with one-frame reuse
and a cancellation after the first generated frame with eight-frame reuse.
A separate startup control holds delivery of a real TTS capability result until
another raw generation owns the bridge, cancels the pending typed task, and
compares that generation with its exact baseline before reusing TTS.
These bounded controls do not qualify every output length or load setting.

The `chrome-webgpu` test pages enable SharedArrayBuffer with browser flags but
remain non-isolated (`crossOriginIsolated == false`), so the bridge caps native
threads at one. In the [#1371 controls recorded in PR #1418](https://github.com/leehack/llamadart/pull/1418),
with that run's staged Qwen3-TTS fixture and bridge manifest, the 4096/4096 batch
profile aborted even on fresh one- and eight-frame synthesis, before
cancellation. The 512/256 fresh controls succeeded. This historical diagnostic
does not establish the behavior of other artifacts, an ordinary isolated
production page or the native cause of the abort. To repeat it, use the recorded
artifacts, set both optional batch values to 4096 and run the maintained
`TTS 1-frame baseline without cancellation` test.

## Qwen3 LiteRT-LM CPU Unicode fixture

List and dry-run before executing the scenario:

```bash
dart run tool/testing/run_local_e2e.dart --list
dart run tool/testing/run_local_e2e.dart --scenario qwen3-litert-cpu-unicode \
  --model-path <Qwen3-0.6B.litertlm> --backend cpu --dry-run
dart run tool/testing/run_local_e2e.dart --scenario qwen3-litert-cpu-unicode \
  --model-path <Qwen3-0.6B.litertlm> --backend cpu
```

It verifies the immutable
Qwen3-0.6B artifact hash, checks public `detokenize([9707, 0, 26525, 232])`
against `Hello! 😊`, checks Unicode and literal `ĠðŁĺĬ` round trips, then runs
the maintained chat/thinking/tool/cutoff campaign. Round trips alone can
miss the split-token conversion defect.

The updated artifact has revision `e6687177e00897731e7716267eebd4eba0dde7c2`
and SHA-256 `c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108`.
The legacy `8414150f` artifact is accepted only as a negative control and must
fail the decoded-text assertion. Other artifacts are rejected before applying
Qwen token IDs. Generic `litert-lm-chat-features-smoke` remains available for
other models without the fixture. The native smoke workflow runs this CPU
scenario on Linux and Windows; GPU and mobile/Web adoption remain separate.

## Platform Rows

The platform tier is intentionally explicit about what is runtime-tested versus
only hook/package-tested:

```bash
dart run tool/testing/test_matrix.dart --tier platform
```

| Platform target | Matrix row | Current evidence level |
| --- | --- | --- |
| Linux x64 | `linux-x64-ci-runtime` | CI runtime plus real-model smoke. |
| Linux arm64 | `linux-arm64-runtime-smoke` | Local/self-hosted runtime row; hook coverage in `native-hook-bundles`. |
| Windows x64 | `windows-x64-ci-runtime` | CI runtime plus LiteRT-LM smoke. |
| Windows arm64 | `windows-arm64-hook-coverage` | Hook coverage; runtime proof needs Windows arm64 hardware. |
| macOS arm64 | `macos-arm64-runtime-smoke` | Local/device runtime row. |
| macOS x64 | `macos-x64-runtime-smoke` | Local/device runtime row; LiteRT-LM is arm64-only and must fail with `LlamaUnsupportedException`. |
| iOS arm64 device | `ios-arm64-device-smoke` | Manual/device runtime row. |
| iOS arm64/x86_64 simulator | `ios-simulator-smoke` | Manual/simulator runtime row; LiteRT-LM is arm64-only. |
| Android arm64 | `android-arm64-device-smoke` | Manual/device runtime row and release smoke plan. |
| Android x64 | `android-x64-emulator-smoke` | Manual/emulator runtime row. |
| Web browser | `web-chrome-runtime-smoke` | Chrome CI plus the required real-GGUF `Web Chat Contract`; large WebGPU/LiteRT-LM smokes remain targeted. |

Rows that say `hook-only` must not be used as full runtime proof. They only show
that package/bundle selection is covered; PR evidence still needs a hardware or
emulator run when the runtime behavior itself is at risk.

## Release Rows

Release candidates should include the release tier:

```bash
dart run tool/testing/test_matrix.dart --tier release
```

For releases that change or newly document Flutter Apple SwiftPM companion
package versions, include `release-companion-pub-gate` in the release evidence.
That row requires checking each referenced companion version on pub.dev before
the release-prep PR is merged. If a companion version is missing, keep the PR
scoped to release prep; after merge, `release_on_prep_merge.yml` pushes the
core release tag, waits for the core on pub.dev, then publishes missing
companion versions, waits for `publish_companion_pubdev.yml`, and verifies the
pub.dev listing. Companions publish after the core because each constrains the
core version it pairs with.

## Local Model Scenarios

Real model checks are intentionally local-only. They can use the unified runner:

The native speech smoke checks the same encoded WAV as file and in-memory bytes,
requires the exact supplied transcript, bounds prompt tokens, and verifies
cancellation followed by successful transcription for both inputs, plus malformed
byte rejection and recovery.

```bash
dart run tool/testing/run_local_e2e.dart --scenario gguf-chat-features-smoke \
  --model-path models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --backend auto

dart run tool/testing/run_local_e2e.dart --scenario gguf-chat-features-smoke \
  --model-path models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --backend cpu \
  --mmproj-path models/Qwen3.5-0.8B-mmproj-F16.gguf \
  --image-path test/fixtures/image.png

dart run tool/testing/run_local_e2e.dart --scenario tool-result-image-smoke \
  --model-path /path/to/Qwen3VL-2B-Instruct-Q4_K_M.gguf \
  --mmproj-path /path/to/mmproj-Qwen3VL-2B-Instruct-F16.gguf \
  --backend cpu

dart run tool/testing/run_local_e2e.dart --scenario gguf-audio-chat-smoke \
  --model-path /path/to/gemma-4-E2B-it-Q4_K_S.gguf \
  --backend metal \
  --mmproj-path /path/to/gemma-4-E2B-it-mmproj-F16.gguf \
  --audio-path /path/to/known-question.wav \
  --expect 4

dart run tool/testing/run_local_e2e.dart --scenario litert-lm-chat-features-smoke \
  --model-path /path/to/gemma-4-E2B-it.litertlm \
  --backend auto \
  --audio-path /path/to/known-question.wav \
  --expect 4

dart run tool/testing/run_local_e2e.dart --scenario speech-to-text-smoke \
  --model-path /path/to/Qwen3-ASR-0.6B-Q8_0.gguf \
  --mmproj-path /path/to/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf \
  --audio-path /path/to/known-speech.wav \
  --expect "Exact expected transcript."

dart run tool/testing/run_local_e2e.dart \
  --scenario chat-app-web-speech-to-text-smoke \
  --audio-path /path/to/known-speech.wav \
  --expect "Exact expected transcript."

# The Web scenario validates file selection and, for a WAV fixture, Chromium's
# fake microphone path with the same file. An MP3 or FLAC fixture runs file
# selection only. The selected-file transcript must contain the expected text
# (case-insensitive); the fake microphone only needs a non-empty transcript
# because its artificial input can loop at the capture boundary.

dart run tool/testing/run_local_e2e.dart --scenario text-to-speech-smoke \
  --model-path /path/to/Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf \
  --mmproj-path /path/to/mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf

dart run tool/testing/run_local_e2e.dart \
  --scenario chat-app-web-text-to-speech-smoke \
  [--audio-path /path/to/speaker-reference.wav]

# Each model whose two variables are set runs; the Qwen3-ASR pair checks that
# the speech transcribes back to its text. Soprano has no published GGUF:
# convert it as the text-to-speech guide describes. WAVs go to
# build/text-to-speech-models.
LLAMADART_TTS_LFM3_MODEL_PATH=/path/to/LFM3-Audio-2B-Q4_K_M.gguf \
LLAMADART_TTS_LFM3_MMPROJ_PATH=/path/to/mmproj-LFM3-Audio-2B-Q8_0.gguf \
LLAMADART_TTS_SOPRANO_MODEL_PATH=/path/to/soprano.gguf \
LLAMADART_TTS_SOPRANO_MMPROJ_PATH=/path/to/mmproj-soprano.gguf \
LLAMADART_TTS_CHATTERBOX_TURBO_MODEL_PATH=/path/to/chatterbox-turbo-Q8_0.gguf \
LLAMADART_TTS_CHATTERBOX_TURBO_MMPROJ_PATH=/path/to/mmproj-chatterbox-turbo-F16.gguf \
LLAMADART_TTS_CHATTERBOX_MULTILINGUAL_MODEL_PATH=/path/to/chatterbox-Q8_0.gguf \
LLAMADART_TTS_CHATTERBOX_MULTILINGUAL_MMPROJ_PATH=/path/to/mmproj-chatterbox-F16.gguf \
LLAMADART_TTS_POCKET_MODEL_PATH=/path/to/pocket-tts-english.gguf \
LLAMADART_TTS_POCKET_MMPROJ_PATH=/path/to/mmproj-pocket-tts-english.gguf \
LLAMADART_TTS_SPEAKER_REFERENCE_PATH=/path/to/ten-second-speech.wav \
LLAMADART_STT_MODEL_PATH=/path/to/Qwen3-ASR-0.6B-Q8_0.gguf \
LLAMADART_STT_MMPROJ_PATH=/path/to/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf \
dart run tool/testing/run_local_e2e.dart --scenario text-to-speech-models-smoke

# Runs in example/basic_app, which opts into the stable_diffusion runtime, and
# writes PNGs to build/image-generation-smoke. Export LLAMADART_SD_TURBO_MODEL
# (and optionally LLAMADART_TAESD) first to add the SD-Turbo cases, including
# its full VAE decoded untiled and with VAE tiling on the default device and
# the CPU, and on a GPU where ImageModelPlacement puts each module's weights
# and which placements change pixels, LLAMADART_SDXL_LIGHTNING_MODEL (and optionally LLAMADART_TAESDXL) to
# add the SDXL-Lightning warm-up and 1024x1024 case, and LLAMADART_IMAGE_HF_CACHE
# (a model cache directory) to load SDXS from its pinned Hugging Face file
# through the resolver, 683 MB on the first run, and
# LLAMADART_IMAGE_SPLIT_MODEL (a split model's files, comma separated in any
# order) to check role detection on a real split model. It also checks the
# disabled/default/one-entry conditioning-cache pixel parity, hits, eviction,
# cancellation/reuse and reload on CPU and the automatic device; the
# runtime's reason in the error of a rejected load, the runtime's messages in
# the log handler, and on macOS the runtime's GPU memory figure.
dart run tool/testing/run_local_e2e.dart --scenario image-generation-smoke \
  --model-path /path/to/sdxs-512-tinySDdistilled_Q8_0.gguf


# Runs the 24 Laya 0.3.5 fixture rows: exact token ids and markers, raw
# marker logits within LLAMADART_DECISION_LOGIT_TOLERANCE (default 0.25), and
# probabilities, confidence, act probability and noul within
# LLAMADART_DECISION_PROB_TOLERANCE (default 0.05). Scores may differ by twice
# that tolerance, and a choice may differ from Laya's when Laya's top two
# probabilities are within the tolerance. Raw action logits must be within
# LLAMADART_DECISION_ACT_LOGIT_TOLERANCE (default 0.05) of each row's largest
# reference action logit, since act_probability saturates. It also checks that the head runs on
# the CPU when the model offloads no layers, and disposes an engine with a head
# still loaded; a leaked Metal buffer then aborts the exit and fails the run.
# The E2E uses CPU unless --backend is given. For the official checkpoint, pass
# its model.safetensors as --head-path and rl_agent_config.json as
# --config-path.
dart run tool/testing/run_local_e2e.dart --scenario decision-model-smoke \
  --model-path /path/to/laya-Q8_0.gguf \
  --head-path /path/to/laya-head.safetensors

# Runs the same rows and default tolerances in Chrome through
# LlamaEngine(LlamaBackend()) and the pinned bridge worker, and requires the
# model and head on WebGPU. It fetches the pinned bridge assets into
# build/decision_web_e2e/bridge/, and the bridge downloads the
# decision-gguf-webgpu profile's laya-Q8_0.gguf and laya-head.safetensors
# (527 MB) from Hugging Face on every run. The `chrome-webgpu` platform in
# dart_test.yaml starts Chrome headless without --disable-gpu and with
# SharedArrayBuffer enabled; a machine without a WebGPU adapter fails the load.
dart run tool/testing/run_local_e2e.dart --scenario decision-model-web-smoke

dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-mock-smoke

dart run tool/testing/native_inference_benchmark.dart \
  --model models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --gpu-layers 0 \
  --mode all \
  --runs 3 \
  --max-tokens 128

dart run tool/testing/run_local_e2e.dart \
  --scenario llama-cpp-speculative-benchmark \
  --model-path models/non-recurrent-target.gguf \
  --draft-model-path path/to/dspark-draft.gguf \
  --speculative-cases baseline,draft-dspark,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,ngram-cache,mixed-ngram \
  --backend cpu \
  --benchmark-gpu-layers 0 \
  --benchmark-max-tokens 128 \
  --benchmark-runs 3 \
  --draft-token-max 1,2 \
  --ngram-size-m 8,16 \
  --benchmark-warmups 1 \
  --ngram-cache-build-static-path /tmp/llamadart-ngram-cache.bin

dart run tool/testing/run_local_e2e.dart \
  --scenario gemma4-mtp-smoke \
  --model-path models/gemma-4-e2b-mtp-Q4_K_M.gguf \
  --benchmark-max-tokens 32 \
  --draft-token-max 1

dart run tool/testing/run_local_e2e.dart \
  --scenario native-embedding-benchmark \
  --model-path models/embedding-model.gguf \
  --benchmark-runs 3 \
  --benchmark-warmups 1 \
  --benchmark-gpu-layers 0

dart run tool/testing/run_local_e2e.dart \
  --scenario native-embedding-sweep \
  --model-path models/embedding-model.gguf \
  --benchmark-runs 3 \
  --benchmark-warmups 1 \
  --benchmark-gpu-layers 0
```

The image scenario selects its dedicated test configuration instead of
`--run-skipped`: it admits the `local-only` suite while preserving platform and
unavailable-model skips. The default test configuration continues to skip
heavy local checks.

The first-image warm-up comparison applies to the loaded GPU backend. It uses
two distinct short SDXS/CLIP prompts with the same padded encoder shape and
identical sampling, dimensions and seed, so both measured requests miss the
conditioning cache. Repeating one prompt would compare uncached conditioning
with a cache hit; see the pinned stable-diffusion.cpp
[conditioning cache](https://github.com/leejet/stable-diffusion.cpp/blob/0518b34374761cb82aeda5ad3c2f0686fdad2cec/src/conditioning/conditioning_cache.h).
The original `first < second * 2 + 250ms` budget is unchanged. CPU/BLAS warm-up
validates state and performs no GPU compile, so it has no GPU latency assertion;
other image-generation smoke checks still run on those backends. Durable fake
pipeline/cache controls run in the normal VM suite; real weight/device timings
remain this opt-in scenario and do not imply physical-device qualification.

Use a non-recurrent target for speculative benchmark cases that reserve
rollback slots. Native recurrent/hybrid models reject nonzero
`speculativeRollbackTokenMax`; a baseline-only run reserves no rollback slots
and can still validate ordinary generation on those models.

Speech evidence outside the `validation-speech-stt` pack
(`doc/cross_platform_validation.md`):

- Chat-app microphone transcription on CPU has passed on a physical Pixel and
  in the iOS Simulator ([#328](https://github.com/leehack/llamadart/pull/328)),
  and CPU file transcription plus chat-app microphone transcription have passed
  on a physical iPad ([#462](https://github.com/leehack/llamadart/pull/462)).
  No Qwen3-ASR run covers Android x64, Linux arm64, Windows arm64 or x64, macOS
  x86_64, or a physical iPhone, nor the Vulkan, CUDA, HIP, OpenCL, or BLAS
  backends.
- `web-speech-to-text-smoke` verifies browser file selection of a WAV, MP3 or
  FLAC fixture and, for a WAV, Chromium fake-device microphone capture with the
  same file. File selection returns a transcript containing the expected text
  (case-insensitive); the microphone assertion requires only a non-empty
  transcript without raw `<asr_text>` markers, because Chromium loops its
  artificial input at the capture boundary. Real microphone hardware and
  browser/device combinations remain deployment-specific checks.
- **Ask with voice**: the experimental llama.cpp GGUF voice path has
  engine-level Metal evidence on macOS, while current packaged microphone UI
  evidence is LiteRT-LM on macOS. Android, iOS, and Windows still require
  real-model/device evidence through the `chat-app-voice-question-smoke` row
  before making a platform validation claim.

`native-embedding-benchmark` compares sequential embedding calls against
`embedBatch(...)` at a fixed `--max-seq`, while `native-embedding-sweep` runs the
same benchmark across `1,2,4,8` and writes
`build/embedding_speedup_sweep.csv` for plotting. Use the sweep when choosing or
defending a default `maxParallelSequences`, and the single benchmark when one
data point is enough. Both are `local-only` and need a real embedding-capable
GGUF model; `website/docs/guides/embeddings.md` documents the underlying scripts
directly for ad hoc runs.

`tool-result-image-smoke` checks that a photo in a tool result reaches the
model: the model names the color of a red and a blue tool-turn photo, and a
`sendWithTools` handler's `LlamaToolOutput` photo reaches the next round. For
a closest-family model without Qwen3-VL weights, set
`LLAMADART_TOOL_MEDIA_CHAT_TEMPLATE=test/fixtures/templates/Qwen3-VL-2B-Instruct.jinja`
so the Qwen3-VL template is used. Its prompts match llama-server
(`test/fixtures/qwen3_vl_tool_media_upstream.md`).

The dedicated `gguf-audio-chat-smoke` scenario validates byte-backed audio
question answering against `--expect` after model and projector initialization.
Run `gguf-chat-features-smoke` separately for chat, tool-call, thinking, and
optional image checks. Both GGUF and LiteRT-LM audio results report the encoded
byte length and a stable SHA-256 fixture ID, but not the fixture path or raw
audio bytes.

`gemma4-mtp-smoke` is a fast correctness companion to
`llama-cpp-speculative-benchmark`: it checks that bundled MTP still produces
coherent Gemma 4 output before the fuller throughput and acceptance run. For MTP
and n-gram *performance* numbers, use `llama-cpp-speculative-benchmark` with
`--speculative-cases draft-mtp,ngram-simple`, which supersedes the older
env-var-driven benchmark script. Like every `local-only` row, neither runs in CI.

In the local E2E scenario, external draft-model strategies require
`--draft-model-path`; select `draft-dspark` to validate DSpark against the same
target baseline. Bundled MTP uses `draft-mtp` without that option; the runner
then loads the target with `ModelParams.loadMtp` automatically. The n-gram
cache strategy can use existing cache paths or build a static cache with
`--ngram-cache-build-static-path`.
For `ngram-simple`, `ngram-map-k`, and `ngram-map-k4v`, `--ngram-size-m`
sweeps the effective n-gram draft length; `--draft-token-max` is still useful
for draft-model, ngram-cache, and mixed draft-model cases. Use
`--ngram-token-max` to cap ngram-mod when it should differ from
`--draft-token-max`.
Speculative benchmark prompts use the loaded model's chat template by default;
use raw-prompt options only for intentional raw-vs-template comparisons.
When investigating output-hash mismatches for n-gram speculation, compare the
same prompt and sampling settings against upstream `llama-server` before
classifying the mismatch as a Dart-only regression; upstream `ngram-map-k` can
diverge from baseline once repeat penalties and accepted drafts are involved.
Use `--include-output` when the exact divergence text is needed in the JSON
report.
When a speculative performance issue is being closed, include the matching
upstream `llama-cli` or `llama-server` command where a comparable tool binary is
available. If the exact packaged native tag does not publish standalone tools,
state the closest upstream build used and keep any remaining artifact-parity gap
linked as a follow-up.

```bash
dart run tool/testing/run_local_e2e.dart \
  --scenario llama-cpp-chat-template-smoke \
  --model-path models/Qwen3.5-0.8B-Q4_K_M.gguf
```

Use `--dry-run` first when a scenario starts servers, builds Flutter web, or
requires local model URLs.

## PR Evidence Template

Generate the current template instead of hand-copying from this doc:

```bash
dart run tool/testing/test_matrix.dart --pr-template
```

Example filled row:

| Matrix row | Scope covered | Platform / model / backend | Result | Evidence / notes |
| --- | --- | --- | --- | --- |
| `gguf-chat-features-smoke` | base GGUF chat/tool/thinking | macOS arm64, Qwen3.5-0.8B-Q4_K_M.gguf, llama.cpp auto/cpu | PASS | Base `RESULT gguf_chat_features ...`, no thinking marker leak, and one `get_weather` tool call. |
| `gguf-audio-chat-smoke` | byte-backed exact audio answer | macOS arm64, Gemma 4 E2B GGUF + projector, llama.cpp Metal | PASS | Audio-only result with `variant: audioAnswer`, exact expected text, and fixture SHA-256. Experimental engine evidence is not microphone UI or mobile validation. |

## Agentic Workflow

When an agent creates or updates a PR:

1. Run `dart run tool/testing/test_matrix.dart --list` and choose rows from the
   touched surfaces.
2. Run essential rows first, then targeted local-only rows with `--dry-run`
   before heavy execution.
3. If a row cannot run locally, record why and whether CI, device availability,
   or a follow-up issue covers it.
4. Paste or update the PR matrix evidence table before asking for review.
5. Do not leave one-off repro scripts behind. Promote durable checks into
   `test/unit/`, `test/integration/`, or `test/e2e/`; wire heavyweight manual
   checks through `tool/testing/run_local_e2e.dart` and
   `tool/testing/test_matrix.dart`.
6. When updating an open PR branch, enforce expected-head CAS and fast-forward
   ancestry with `tool/git/safe_pr_head_update.dart` to prevent stale head
   rewinds. Consult `doc/pr_branch_writer_inventory.md` for writer scope and the
   remaining GitHub-managed governance boundary.

The executable quick suite and provider commands are documented in the
[cross-platform validation runbook](cross_platform_validation.md). Discover the
model-free `validation-harness` and opt-in `validation-model-core` matrix rows.


### LiteRT-LM public utility preservation

```bash
dart run tool/testing/run_local_e2e.dart --scenario litert-lm-utility-preservation \
  --model-path /path/to/Qwen3-0.6B.litertlm --backend cpu --dry-run
```

Remove `--dry-run` to run this local-only, download-free row. Use the corrected
Qwen3-0.6B bundle (613,722,264 bytes, SHA-256
`c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108`);
direct execution uses `LITERT_LM_UTILITY_MODEL`. The test uses the public
`LiteRtLmRuntimeClient()` with default runtime discovery, CPU, context 1024,
output limit 32, native speculation disabled, and canonical `minLogLevel: 3`.

The tokenizer checks the established split-token `Hello! 😊` fixture, four
Unicode round trips, and the configured start-token prefix with `addSpecial`.
It records that prefix and both token sequences, allowing an empty configured
prefix without claiming a nonempty BOS token. A real `run` performs one warmup and two measured runs, followed by a second
call with zero warmups and one measured run on the same client. Both calls
require nonempty raw output, native settlement, positive token counts and
positive finite TTFT, prefill throughput and decode throughput. The oracle
does not require a semantic greeting from a short thinking-enabled response.
Async operations have 30-second bounds and the test a three-minute limit;
the suite owns its temporary cache and disposes the client.

Record source revision, runtime artifact identity and device with the result.
This row covers tokenizer and benchmark utility preservation on Qwen3 CPU; it
does not establish other logging levels, devices, model families or media.

### LiteRT-LM generative image preservation

```bash
dart run tool/testing/run_local_e2e.dart --scenario litert-lm-media-preservation \
  --model-path /path/to/Qwen3.5-0.8B-VL_int8.litertlm --backend cpu --dry-run
```

Remove `--dry-run` to run this local-only row; it downloads nothing. Use
`litert-community/Qwen3.5-0.8B` revision
`10243c0a01d24e6b122a0e814f8c4d984c9c92d6`, file
`Qwen3.5-0.8B-VL_int8.litertlm` (1,302,262,448 bytes, SHA-256
`e3360b658c929ff35ab740a21f5e4b688096a72e351b8d347e26ccda314121b7`).
The test verifies these bytes before loading through public runtime discovery
with CPU, context 2048 and native speculation disabled. Direct execution uses
`LITERT_LM_VISION_MODEL`.

The shared deterministic 32-pixel checker PNG is 117 bytes, SHA-256
`608559c1cef09a7d4669ea459ee1e8825771634f543fb1a93a6e768a48da9b09`.
The row requires the supported vision probe, visible `checkerboard` output,
greedy path/bytes parity, image/assistant/follow-up history, same-engine reuse
after first-chunk cancellation, and dispose/reload reproduction. Operations
have 30-second bounds and the test a three-minute limit; caches and fixture
files stay in its suite-owned temporary directory.

Record source revision, runtime artifact identity and device with the result.
This row qualifies image wiring, history and lifecycle for this model and CPU;
it does not qualify audio, thinking, GPU or perceptual quality generally. The
independent `litert-lm-chat-features-smoke` retains its thinking oracle. It
records the thinking row as `not_applicable` (with the reason) when the loaded
bundle's chat template never reads `enable_thinking` and always closes the
think block, as the Qwen3.5 `_int8`, `-VL_int8` and `_int8_gpu_composite_v0190`
bundles do.

### LiteRT-LM lifecycle regression

```bash
dart run tool/testing/run_local_e2e.dart --scenario litert-lm-lifecycle \
  --model-path /path/to/Qwen3.5-0.8B_int8.litertlm --backend gpu
```

This local-only row runs public engine reload/recovery and forced initialization
timeout in separate child processes. Recovery retains a 60-second generation
budget and requires the hello fixture after each reload; the parent enforces
240-second recovery and 120-second timeout-process deadlines. The timeout case
requires the abandoned request to settle within one second of `dispose`: either
`dispose` succeeds and the request completes or fails, or `dispose` reports an
explicit cleanup error and the request fails. Outer deadline expiry kills only the owned child and fails the test.
Logs and process results go to `.dart_tool/litert_lm_lifecycle`, or
`LITERT_LM_LIFECYCLE_LOG_DIR`. Record source commit, model hash/revision, runtime
artifact identity, requested backend, and device with these logs. A GPU request
alone does not prove accelerator placement.

### Native GGUF stop sequences

`dart test -p vm test/integration/stop_sequences_test.dart` uses the small test
GGUF to cover ordinary and speculative stop handling, Unicode, token boundaries,
completion, cancellation, and subsequent generation. Ordinary tests constrain
output with grammar; speculative tests use deterministic unrestricted controls
because grammar sampling is unsupported there, and assert actual draft acceptance.

Use a compliant chat model (Gemma 4 E2B or Qwen3.5 0.8B) for the unforced public
chat fixture; the control must emit `alpha cedar17 omega` and caller stop
`cedar17` must leave exactly `alpha `, under single-piece and default batching:

```bash
dart run tool/testing/run_local_e2e.dart --scenario gguf-stop-sequences \
  --model-path /path/to/chat.gguf --backend cpu
```

Repeat with `--backend metal` on macOS when available. Record the source commit,
native runtime tag, printed model SHA-256, and native offload logs with results.

### Model lifecycle cancellation and projector ownership

```bash
LLAMADART_LOAD_MODEL_PATH=/path/to/chat.gguf \
LLAMADART_LOAD_MMPROJ_PATH=/path/to/mmproj.gguf \
dart test -p vm -j 1 --run-skipped \
  test/e2e/backends/llama_engine_load_e2e_test.dart \
  --name 'cancels a real GGUF'
```

These local-only tests unload, dispose, and replace the model after a real
tool-loop answer starts on the default device and CPU. They require a
`cancelled` result, preserve the partial reply, and verify another request
after reload or replacement. Pair them with
`test/unit/core/engine/engine_lifecycle_cancellation_test.dart`, which controls
pre-output stops, buffered tool calls, running handlers, projector creation
and teardown races, and speech parameter validation before file resolution.

### Image above the context micro-batch

```bash
MULTIMODAL_MICRO_BATCH_MODEL=/path/to/gemma-4-12B-it.gguf \
MULTIMODAL_MICRO_BATCH_MMPROJ=/path/to/mmproj.gguf \
MULTIMODAL_MICRO_BATCH_BACKEND=cpu \
dart test -p vm -j 1 --run-skipped \
  test/e2e/backends/multimodal_micro_batch_e2e_test.dart
```

These local-only tests need a model whose projector decodes an image with
non-causal attention: Gemma 3, or Gemma 4 other than E2B and E4B. They answer
a small image at the default batch sizes; require a typed error and a working
engine for an image above a micro-batch that is below the batch, explicit or
default, and answer the large image with the micro-batch the error names; and
require an answer and one warning per request where the batch equals the
micro-batch (32/32, batch 32 alone, 256/256, 512/512, and a text turn after
an image turn). Repeat with `MULTIMODAL_MICRO_BATCH_BACKEND=metal` on macOS.
Without the check the first group aborts the process on llama.cpp's
`non-causal attention requires n_ubatch >= n_tokens` assertion. `test/unit/backends/llama_cpp/llama_cpp_service_media_micro_batch_test.dart`
covers the same paths in default CI with a stand-in projector on the real
runtime.

### Native exit teardown

```bash
dart run tool/testing/run_local_e2e.dart --scenario native-exit-teardown \
  --model-path /path/to/chat.gguf
```

On Linux, this local-only row requires `host-shutdown-loaded`,
`host-shutdown-generating` and `host-shutdown-loading` to pass. A model-owning
isolate disposes its engine; the control isolate waits for its actual VM exit
notification before calling C `exit`. A shutdown requested during load waits
for the pending load before disposal. `--backend cpu` is the default; use
`--backend vulkan` or `--backend cuda` with the corresponding runtime build.
Every run must report its requested backend and `EXIT_PROBE_HOST_SHUTDOWN_COMPLETE`.
Raw C exit with live isolates remains a separately invocable diagnostic and
is excluded from Linux qualification. These subprocess checks do not prove
Flutter engine shutdown ordering.

On macOS, `EXIT_TEARDOWN_TTS_MODEL`, `EXIT_TEARDOWN_TTS_MMPROJ` and
`EXIT_TEARDOWN_TTS_ADAPTER` (`qwen3-tts`, `lfm3-audio`, `soprano`,
`chatterbox` or `pocket-tts`) add
`quit-speaking`, which calls C `exit` once synthesis has generated a frame.

On macOS, the row runs `test/fixtures/llama_cpp_exit_probe.dart` as a
child process and ends it while llama.cpp objects are alive on Metal: C `exit`
through FFI from the main isolate with a model idle, generating or loading;
an unhandled error while generating or loading; an isolate killed inside the
native load; and an isolate that ends without freeing anything. The C `exit`
scenarios model a native host that exits without shutting Dart down, while
the owning isolate is idle or inside a guarded call. They do not model a
Flutter macOS quit, which shuts the isolates down first, and they do not
cover an exit during an unguarded call or a guarded call longer than two
seconds ([llama.cpp exit teardown](llama_cpp_exit_teardown.md)). Each run
must reach its exit point, print no `GGML_ASSERT`, and end
with exit code 0, or 255 for the unhandled errors. The engine scenarios also
require the Metal backend, so use a model the GPU loads. `EXIT_TEARDOWN_RUNS`
sets the runs of each scenario (default 3). A run fails when the process is
still alive after three minutes. Three of the ten scenarios are reported as
skipped unless their files are set in the environment: `EXIT_TEARDOWN_MMPROJ`,
the model's projector, enables `quit-projector` (a C `exit` with the projector
loaded) and `quit-disposing` (one while its service disposes,
`EXIT_PROBE_DISPOSE_DELAY_US` microseconds after the dispose starts, default
1000), and `EXIT_TEARDOWN_DECISION_MODEL` with `EXIT_TEARDOWN_DECISION_HEAD`
enables `quit-decision` (one with a decision head loaded).

`dart:io`'s `exit` is not one of the scenarios: it does not run the static
destructors that make ggml-metal abort.

### Image model exit teardown

```bash
dart run tool/testing/run_local_e2e.dart --scenario image-exit-teardown \
  --model-path /path/to/sdxs-512-tinySDdistilled_Q8_0.gguf
```

On Linux, this local-only row requires cooperative idle, generation and
pending-load shutdown, with logging enabled and disabled, and optionally both
runtimes loaded. It waits for engine disposal and the owning isolate's actual
exit before C `exit`, requiring `IMAGE_PROBE_HOST_SHUTDOWN_COMPLETE` and zero
tracked image contexts. Generation uses two steps at 256×256 so shutdown is
bounded on the CPU. Use `--backend cpu` or `--backend vulkan`; both-runtime
coverage additionally needs `IMAGE_EXIT_GGUF`. Raw live-isolate exits remain
diagnostic and are excluded from Linux qualification. Batch progress checks
still run on both platforms.

On macOS, this row runs in `example/basic_app`, which opts into the
stable_diffusion runtime. It runs
`example/basic_app/test/fixtures/image_exit_probe.dart` as a child process and
ends it while an image model is alive on Metal: C `exit` through FFI from the
main isolate with the model idle, generating, loading, or already disposed;
an unhandled error while generating or loading; and an isolate killed inside
the native load. The idle, generating and loading exits run a second time
with the runtime's log forwarded at debug level (`-logging`), so the worker
reads the log around the exit, and `quiet` loads, generates and disposes at
the default log levels and must leave no `ggml_` line on stderr. Each run
must reach its exit point, print neither
`GGML_ASSERT` nor `GetFfiCallbackMetadata`, and end with exit code 0, or 255
for the unhandled errors. The loading scenarios time a second load of the
model and exit halfway through a third, because the first load of a process
also sets up Metal. As in the llama.cpp row, the C `exit` scenarios model a
native host that exits without shutting Dart down, not a Flutter quit
([exit teardown](llama_cpp_exit_teardown.md#image-models)).

The row also checks that each `sd_dart_` function `StableDiffusionCalls`
looks up, the optional log and device memory functions included, resolves to
the runtime's own export of that name, which default CI
cannot (the root package does not bundle the runtime), and that batches of
two and three images report every sampling step in order and end with the
`decoding` event.

`IMAGE_EXIT_RUNS` sets the runs of each exit scenario (default 3). A run fails
when the process is still alive after two minutes. `quit-both-loaded`, a C
`exit` with a llama.cpp model loaded as well, is reported as skipped unless
`IMAGE_EXIT_GGUF` names a GGUF chat model the GPU loads.

### Flutter macOS quit

```bash
dart run tool/testing/run_local_e2e.dart --scenario chat-app-macos-quit \
  --model-path /path/to/chat.gguf
```

This local-only macOS row is the Flutter counterpart of the two rows above:
it quits a real Flutter macOS app instead of calling C `exit`.
`example/chat_app/test/macos_quit_e2e_test.dart` builds
`integration_test/macos_quit_probe.dart` into the chat app's Runner, debug
and release, and starts the built executable itself, so it reads the app's
exit status. The probe loads a llama.cpp model on Metal and generates a few
tokens, disposes nothing, registers no `onExitRequested` listener, and quits
through one path:

| Path | How it is driven |
| --- | --- |
| `apple-event` | `osascript` sends the Quit Apple event to the app's process id |
| `terminate` | the probe sends `terminate:` to `NSApp`, the action of the Quit menu item |
| `close-window` | the probe sends `performClose:` to its window; the Runner quits when its last window closes |
| `exit-required`, `exit-cancelable` | `ServicesBinding.exitApplication` |

Each path runs `MACOS_QUIT_RUNS` times (default 3) and must end with exit
status 0, no `GGML_ASSERT`, and no crash report of that process in
`~/Library/Logs/DiagnosticReports`, with the runtimes' tracked-object counts
above zero before the quit. In the debug build, one more case attaches
`flutter attach`, hot restarts the app, waits for the models to load again
and quits: the tracked counts after the restart must equal the ones before
it, which is what shows that the discarded isolates freed their models.

Every path also runs once with a model loaded through the upstream loader,
which no isolate holds and no runtime tracks. That run must abort
(`SIGABRT` with `GGML_ASSERT`); without it a path that skipped the static
destructors would pass with nothing freed. An abort can leave a crash report
of `llamadart_chat_example`, up to ten for one run of the row, and the test
logs whether it found one (`"crashReport"`) instead of requiring it: macOS
may stop writing crash reports, or write only some, for a process that
aborts repeatedly. The check that a clean quit left no crash report is
therefore supporting evidence, and the exit status carries the row.

`MACOS_QUIT_IMAGE_MODEL` (an image checkpoint such as SDXS) loads an image
model too, and `MACOS_QUIT_DECISION_MODEL` with `MACOS_QUIT_DECISION_HEAD`
a decision engine; both must report a Metal device. `MACOS_QUIT_BUILD_MODES`
picks the builds (default `debug,release`).

Limits:

- The Cmd-Q keystroke is not sent: a synthetic keystroke needs the
  Accessibility permission and goes to whichever app is frontmost, which
  the probe need not be. `terminate` is the action that keystroke triggers.
- The models are idle when the app quits. A quit during a load or a
  generation is not part of the row; the measurements are in
  [exit teardown](llama_cpp_exit_teardown.md).
- The test signs the probe with the Runner's entitlements plus read access
  to the model files (the sandbox refuses paths outside the container), and
  the build replaces `example/chat_app/build/macos`. The app's window opens
  for each run.

### Flutter shutdown during active native work

```bash
FLUTTER_SHUTDOWN_HEADERS=/path/to/extracted/native/headers \
  dart run tool/testing/run_local_e2e.dart \
  --scenario chat-app-flutter-active-shutdown --model-path /path/to/chat.gguf
```

This local-only macOS/Linux row builds the actual Flutter Runner in debug and
release. macOS drives the five quit paths above; Linux drives required and
cancelable `ServicesBinding.exitApplication`. Each path runs three times
(`MACOS_QUIT_RUNS`), once a generation has delivered a token and separately
while the real tracked native loader is inside a two-second native progress
callback. That callback never enters Dart. Load cleanup stays inside the same
native call so killing its isolate cannot skip cleanup after the call returns.

An ordinary native host `atexit` observer requires the native load to have
returned and the tracked-object registry to be empty, and writes buffered C
stdout that normal process exit must flush. The row requires exit zero and
rejects native/Dart VM assertions and generation errors. It uses the exact
runtime's header bundle to compile the observer. The generation must still
be active at the quit request; completion before that point fails the test.

The `startup` case instead forwards the native loader through a test-only
C shim while the production service and worker own its returned model. A
shutdown request during native progress awaits the real `LlamaEngine.load`
future, starts disposal, and awaits it from a second caller before quitting.
That cooperative host ordering is distinct from the raw `loading` case, which
keeps cleanup in one C call. `FLUTTER_SHUTDOWN_WORK_STATES` selects a nonempty
comma-separated subset of `loading,generating,startup`; all run by default.
This does not qualify arbitrary embeddings or production SwiftPM linkage
when the test app uses a native-assets override.

The Linux Runner explicitly disposes its engines during `GApplication`
shutdown. Destroying the detached windows alone is insufficient when plugins
retain engine references. Keep the zero-tracked-object and completed-native-call
assertions; an exit code of zero alone does not satisfy this row.

### Native prompt-evaluation cancel

```bash
dart run tool/testing/run_local_e2e.dart --scenario native-prompt-cancel \
  --model-path /path/to/qwen2.5-0.5b-instruct-q4_k_m.gguf --backend cpu
```

This local-only row builds a prompt of at least 1,600 tokens and times an
uncancelled run's first token. It then cancels four runs at 20% of that time.
`cancelGeneration()` and awaited subscription cancels of `generate()` and
`create()` must each end in under 60% of it, the subscription cancels must
deliver no events after the cancel is called, and the run after each cancel
must produce the uncancelled output.
It prints each latency as JSON. `PROMPT_CANCEL_THREADS` sets the CPU threads
(default 4). Repeat with `--backend metal` on macOS. The timings depend on
machine load, so record `uptime` with the results and rerun a timing failure
once before treating it as a regression.

### Flutter image startup and sampling shutdown

```bash
FLUTTER_SHUTDOWN_HEADERS=/path/to/extracted/native/headers \
  dart run tool/testing/run_local_e2e.dart \
  --scenario chat-app-flutter-image-shutdown --model-path /path/to/image.gguf
```

Run workspace and chat app dependency preparation first: this scenario uses
`--no-pub` so launching an already prepared test cannot change dependencies.
This local-only row drives the same five macOS and two Linux quit paths in
debug/release, three times each. The loading request follows an actual native
progress record while `ImageGenerationEngine.load` is pending. Sampling
requests follow an intermediate native sampling event while generation is
still pending. The host awaits startup and repeated disposal before quitting;
disposal cancels sampling and joins the worker. Native C observers require
both registries to be empty and buffered C output to flush at actual host exit.
The native progress recorder never calls Dart. Completion before the request
fails the check. `FLUTTER_SHUTDOWN_WORK_STATES` may select `image-loading` or
`image-generating`, with both enabled by default. This is cooperative host
shutdown evidence, not direct C exit with live isolates or arbitrary forced
Flutter engine termination. Source-built runtime checks do not qualify
published artifacts. Physical devices, other image families and production
SwiftPM linkage require their own evidence.

The image row also launches a standalone Dart fixture for pending loading and
sampling. It awaits repeated disposal and worker exit, returns naturally from
`main`, and requires empty native registries and C output at process shutdown.
Each state runs three times per platform. This qualifies cooperative natural
VM termination; fatal errors with pending startup or forced termination that
skips disposal remain outside this evidence.

## Native multimodal embeddings

For text task/profile or Matryoshka changes, use the distinct
`text-embedding-retrieval` row. It compares all four EG2 dimensions with the
pinned official float32 CPU reference through production helper calls, using
BF16 GGUF CPU output. Follow [text helper qualification](embedding_text_helpers.md).
This establishes no media, GPU, Web, LiteRT-bundle or quantized retrieval claim.

The `native-multimodal-embeddings` local-only row qualifies EmbeddingGemma-2
BF16 with the matching vision/audio projector on macOS CPU and Metal. It
compares six ordered vectors with a pinned upstream-only C reference, checks
raw/normalized output, adjacent-text parity, ordering, expanded capacity,
cancellation and reuse. It never downloads weights. Set the environment and
follow [the native embedding procedure](multimodal_embeddings_native.md), then
run `run_local_e2e.dart --scenario native-multimodal-embeddings --dry-run`
before the real scenario.

### Native reranking

Run `dart run tool/testing/run_local_e2e.dart --scenario native-reranking`
after its `--dry-run`, with the exact local model and oracle paths described
in [Native reranking qualification](native_reranking.md). This local-only row
compares Qwen3 named-template/multiclass and Jina fallback/single-output scoring
with upstream, including batching, overflow, cancellation, reuse and disposal.
Record CPU and Metal receipts separately; other platforms remain unqualified
until their model-backed runs pass.

## Seamless texture qualification

`image-seamless-textures` runs the maintained local-only SDXS recipe through
`example/basic_app/test/image_seamless_textures_e2e_test.dart`. See
[the recipe and native-reference procedure](image_seamless_textures.md).
Set `LLAMADART_TEXTURE_DEVICES=cpu` on a host without Metal; this qualifies
CPU only. The default `cpu,metal` requires an actual `MTL` backend for Metal.

## Test timing and shards

Every root test lane (Linux VM, Chrome, macOS and Windows `Test Native`) also
writes a JSON file reporter; the ordinary reporter and test exit status are
unchanged. `test-timing-<lane>-<shard>-<attempt>` artifacts
contain sanitized suite paths, source lines, test IDs, intervals, hidden/skip
flags and results. Test names, printed messages and errors stay out of the
uploaded summary. Hidden intervals include suite loading and group setup or
teardown; they are not separately classified as build-hook time.

To summarize a local run, use an isolated system temp directory on macOS and run:

```bash
dart test -p vm -j 1 --exclude-tags local-only --file-reporter=json:.dart_tool/test_events.jsonl
dart tool/ci/native_test_timing.dart .dart_tool/test_events.jsonl .dart_tool/test_timing.json
```

The summary marks missing terminal results or unfinished tests incomplete.
Malformed/truncated JSON produces no report. Intervals can overlap, and the
reporter excludes startup before its initialization. Compare them with the
test step's hosted timestamps; neither their sum nor the difference
isolates build-hook cost, CPU time, billing or a causal speedup. This advances
[#532's measurement work](https://github.com/leehack/llamadart/issues/532);
the full-gate median targets and integration policy remain separate.

`tool/ci/test_shards.dart` splits each lane's files across its jobs by the
suite times in `tool/ci/test_shard_weights.json`. macOS and Windows run only
the host tests (`doc/ci_selection.md`, "Host OS lanes"); `dart
tool/ci/test_shards.dart hosts <file>` shows where a test runs and why.
Rebalance a lane from one full CI run's timing artifacts; take `linux-vm`
from a pull request run, which runs without coverage like the PRs it
balances:

```bash
gh run download <run-id> -p 'test-timing-macos-*' -D /tmp/timing
dart tool/ci/test_shards.dart weights macos /tmp/timing/*/test_timing.json
```

## LiteRT-LM Web text history

`litert-lm-web-text-history` serves an existing local model on loopback port
5198 and runs Chrome with the `chrome-webgpu` test configuration. It downloads
no model. `--browser safari` runs the same test in the Safari app through
`dart test -p safari` (safaridriver), and runs
`chat-app-web-litert-gemma4-smoke` through `tool/testing/safari_webdriver.py`.
Enable Settings > Developer > Allow Remote Automation first, and run with the
screen unlocked: a locked screen hides the page, which then renders no Flutter
frames and can be terminated while a large model loads. The chat-app smoke
checks this and fails early. List scenarios and dry-run before execution:

```bash
dart run tool/testing/run_local_e2e.dart --scenario litert-lm-web-text-history \
  --model-path /path/to/gemma-4-E2B-it-web.litertlm --backend gpu --dry-run
```

Remove `--dry-run` for the real run. The model must match the requested JS
backend; native bundles are not automatically Web-compatible. The test records
the model SHA-256/size, pinned JS module URL, browser and (when requested) WebGPU
adapter. Direct JS and Dart wrapper engines run serially with matching settings.
Ordered recall and system forwarding require positive results and no-history /
no-system controls that fail if the preface is bypassed. Session reset and
cancel/reuse must pass. A load failure on either route leaves semantic paths
unqualified; a browser adapter alone establishes no model GPU execution.
The model-free Chrome suite separately checks routing, API skew and typed
unsupported roles/options.

### LiteRT-LM Web tool calling

`litert-lm-web-tool-calling` runs the same local server and Chrome
configuration with `test/e2e/backends/litert_lm_tool_calling_web_e2e_test.dart`.
It downloads no model. The published runtime alone must parse a `get_weather`
call into `tool_calls`, emit none without tools, and answer from a 0.19.0 tool
message; the adapter must then return that call from `ChatSession.create`,
answer from the `LlamaToolResultContent`, and pass cancel-after-first-chunk,
reset and reuse. Dry-run before execution:

```bash
dart run tool/testing/run_local_e2e.dart --scenario litert-lm-web-tool-calling \
  --model-path /path/to/Qwen3-0.6B.litertlm --backend cpu --dry-run
```

Use `--backend gpu` with a `-web.litertlm` bundle for WebGPU.

### LiteRT-LM Web truncation

`litert-lm-web-truncation` runs the same local server and Chrome
configuration with `test/e2e/backends/litert_lm_truncation_web_e2e_test.dart`
([#919](https://github.com/leehack/llamadart/issues/919)). It downloads no
model. The published runtime alone, with `benchmarkEnabled`, measures a
natural reply's decode steps `n` and replays it at budgets `n + 1`, `n`,
`n - 1` and `n - 2`, then fills a 1024-token context. The adapter must report
`stop` above `n`, `length`/`maxTokens` at and below it, `length`/`contextSize`
for the filled context, complete an automatic `get_weather` loop, and stop a
3-token loop as `truncated` without running the tool. A last phase requests a
65536-token context, above a fixed KV cache such as Qwen3 0.6B's 4096 on WASM
CPU: the runtime's own over-long-prompt rejection names the executor's limit,
and the adapter must report the long reply as `length` at that limit or at
`maxTokens` 8192. Dry-run before
execution:

```bash
dart run tool/testing/run_local_e2e.dart --scenario litert-lm-web-truncation \
  --model-path /path/to/Qwen3-0.6B.litertlm --backend cpu --dry-run
```

Use `--backend gpu` with a `-web.litertlm` bundle for WebGPU. Rerun it when
the `@litert-lm/core` pin changes.

### Native LiteRT-LM JSON Schema

`litert-lm-json-schema` runs the public native path with `--backend cpu` or
`--backend gpu` against a fixed Qwen3-0.6B (SHA-256 `c5f39b41…`) or Gemma 4
E2B (SHA-256 `18193810…`) bundle. It compares adversarial
unconstrained/constrained output, sentinel and scalar schemas, a nested
object/array/`$ref`/`anyOf`/pattern/format/tuple schema checked by the Dart
validator, a Unicode enum and length, a typed contract refusal (`oneOf`) and
recovery, thinking (Gemma 4 reasons and still returns the constrained reply;
Qwen3 is refused), system/history, before/after-content cancellation and a
`length` finish cut off inside a constrained string. Run it per model and
backend; `--list` and `--dry-run` first. Each host platform needs its own run.
`chat-app-litert-json-schema` runs the same checks in the chat app on an
Android or iOS device, simulator or emulator. `--model-path` is a path the app
can read (a host path works on the iOS simulator; the sandboxed macOS app
reads only its own container,
`~/Library/Containers/com.example.llamaDartChatExample/Data/...`; a model
under `/opt` fails with EPERM, so copy it into the container first) or a plain
`http(s)` URL the app downloads into its support directory; for an Android emulator, serve the bundle on the
host and use `http://10.0.2.2:<port>/<bundle>`. URLs with credentials, a query
or a fragment are refused, since the URL is printed and compiled into the app.


### Complete image checkpoint containers

`image-container-formats` strengthens the existing checkpoint-container case
with hashed complete local inputs, automatic/explicit roles and mandatory
independent direct-C CPU references. It generates no downloads and executes no
Python checkpoint objects. The selected SD-Turbo F16 GGUF/Safetensors and
restricted PyTorch layouts are macOS arm64 CPU evidence; the historical ZIP
timeout cause stays unresolved. See [Image weight formats](image_weight_formats.md)
for the exact recipe, fixture producers, identities and reproduction steps.


### Local complete image checkpoint sets

`image-local-checkpoint-sets` exercises the bounded complete SD-Turbo F16/F32
local index/directory recipe on macOS CPU. It builds owned two-shard fixtures,
checks public/native-reference pixels, aggregate accounting, source-removal
lifetime, cache reuse and cancellation cleanup/recovery. See
[the fixed recipe and cache contract](local_image_sets.md). No generic Diffusers,
new-family, editing/tiling/seamless, GPU or device qualification is inferred.

### Bounded image editing

`image-editing` runs the maintained local-only SD-Turbo full-VAE macOS CPU
recipe: owned RGB inputs, binary-mask polarity, strength, ordinary defaults
reset, cancellation/reuse and reload, with optional exact direct-C references.
See [the fixture, gates and provenance](image_editing.md). No GPU/device or
other SD 2.x model qualification is inferred.

### Bounded ControlNet

`image-controlnet` runs the maintained local-only SD 1.x checkpoint plus
original-layout SD 1.x ControlNet macOS CPU recipe: control image and strength
effects, strength-0 and ordinary reset equivalence, cancellation/reuse and
reload, with optional exact direct-C references. See
[the fixture, gates and provenance](image_controlnet.md). No GPU/device,
SD 2.x/SDXL or Diffusers-layout ControlNet qualification is inferred.

### Bounded hires fix

`image-hires-fix` runs the maintained local-only two-pass latent hires fix
with an SD 1.x (`LLAMADART_HIRES_RECIPE=sd15`) or SD 2.x (`turbo`) full-VAE
checkpoint on macOS CPU or Metal (`LLAMADART_HIRES_DEVICE=cpu` or `gpu`):
final size, size/scale agreement, one-pass reset, composition kept,
second-pass cancellation/reuse and reload, with optional exact direct-C
references. See [the fixture, gates and provenance](image_hires_fix.md). No
other family, decoder, host, device or upscaler qualification is inferred.

### Reference image editing

`image-reference-editing` runs the maintained local-only FLUX.1 Kontext
[dev] reference edit on macOS Metal: a visible requested edit with preserved
content, a reference effect against ordinary text-to-image, cancellation,
ordinary reset and reload, with optional exact direct-C references. See
[the fixture, gates and provenance](image_reference_editing.md). No other
family, component, host, device or reference-count qualification is
inferred.

## Windows native override registry

For [#1649](https://github.com/leehack/llamadart/issues/1649), the default Windows
VM suite includes `test/integration/windows_ggml_registry_test.dart`. It copies
registry DLLs to a separate module directory, resolves through the production
fallback, checks the hook registry count, and passively checks that the alternate
`ggml.dll` was not loaded. It requires no model or GPU.

Model qualification uses fresh processes with the same published runtime, SDK,
model and CPU settings. Vary these three switches independently: hook
`llamadart_native_path`, `LLAMADART_NATIVE_LIB_DIR`, and a runtime directory
prefixed to `PATH`. The eight combinations isolate the minimal trigger; retain
the known triple-override failure as the pre-fix control. Also check
`LLAMADART_BACKEND_MODULE_DIR` alone and with the hook override. Do not rerun
the old release baseline merely to re-establish the already verified failure.

For each fixed combination require successful model/context creation and unload,
and retain actual loaded DLL paths/hashes plus the model loader's ggml import
identity. Observe modules after the unmodified production outcome; registry
getters can initialize state. Run normal published-assets JIT and a compiled
`dart build cli` bundle outside the checkout as controls. Unit probes and a
model-free DLL test do not replace these Windows model checks.

## Default native consumer and distributed AOT

`native-default-consumer-aot` exercises the ordinary checkout consumer, default
native hooks and distributed AOT on macOS arm64 and Windows x64. It is heavy and
runs only through explicit local execution or the dedicated
[`native_default_consumer_qualification.yml`](../.github/workflows/native_default_consumer_qualification.yml)
manual workflow. Default CI runs only model-free fixture controls and source/dispatcher/YAML
contracts; it does not fetch the model or execute inference/AOT. The maintained
Dart wrapper discovers `test_*.py` under
`test/fixtures/native_default_consumer_qualification` with bytecode writes
disabled; its synthetic controls require no SDK, native runtime or model.

Inspect first, without executing the driver or reading a model:

```sh
dart run tool/testing/run_local_e2e.dart --list
dart run tool/testing/run_local_e2e.dart --scenario native-default-consumer-aot --dry-run
```

The outer dry-run prints the command with placeholders when inputs are absent;
it produces no qualification result. Before real local execution set all four:

- `LLAMADART_DEFAULT_AOT_EXPECTED_SHA`: reviewed full lowercase checkout commit.
- `LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG`: `v0.8.0-2`, `v0.8.0-3` or `v0.9.0`, which must
  match the source pin. This verifies identity and never overrides the pin.
- `LLAMADART_DEFAULT_AOT_MODEL_PATH`: the admitted local Qwen2.5-1.5B Instruct
  Q4_K_M fixture; local execution downloads nothing through the dispatcher.
- `LLAMADART_DEFAULT_AOT_OUTPUT_ROOT`: a fresh owned evidence directory.

Then remove `--dry-run` to invoke the maintained driver. The manual workflow
accepts a reviewed unmerged branch, requires its exact SHA, and checks both the
source pin and actual host architecture. Its fixed model revision is
`91cad51170dc346986eccefdc2dd33a9da36ead9`, 1,117,320,736 bytes, SHA-256
`6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e`.
It downloads once with streaming size/digest verification, offers no URL input,
and retains per-platform/SHA/run/attempt artifacts for seven days, including
failures. Transport errors never print redirect locations or signed URLs.

Before the dedicated workflow first lands on the default branch, use the
already registered `ci.yml` manual bridge at the reviewed branch commit.
[GitHub requires the dispatch workflow to exist on the default branch](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).
The bridge calls the new workflow from the same commit with read-only
permissions and no secrets:

```sh
gh workflow run ci.yml --ref REVIEWED_BRANCH \
  -f native_default_qualification=true \
  -f native_default_expected_sha=REVIEWED_FULL_SHA \
  -f native_default_expected_native_tag=v0.8.0-2
```

This explicit mode skips normal CI selection/fanout, its aggregate, the older
Windows registry campaign and deployment. The flag defaults to false, retaining
ordinary push, PR and manual CI behavior. The reusable entry accepts only the
same required SHA/tag strings; it adds no automatic model trigger. Direct
`workflow_dispatch` on the dedicated workflow remains available after its
default-branch registration. Reruns are refused by the attempt-1 guard.

Native `v0.8.0-2` is **pipeline baseline only**; it provides no native3 acceptance.
Native3 acceptance remains [#1762](https://github.com/leehack/llamadart/issues/1762).
It requires its own source/artifact/provenance gates, actual provider
identity, model inference and distributed AOT results, plus independent
acceptance. A `--help`, list, build or source-check pass supplies no inference or
AOT evidence. Historical Windows 16-case evidence belongs to native
`v0.8.0-1`; it does not qualify native2 or native3. No GPU/device-family or core
publication claim follows from this bounded consumer campaign.

## Windows registry qualification

`windows-native-override-registry` is a manual Windows 2022 x64 CPU lane for
[#1649](https://github.com/leehack/llamadart/issues/1649). In the existing CI
workflow, enable only the optional `windows_registry_qualification` boolean;
normal full CI still runs, the qualification result is separate, and production
chat deployment is disabled for that run. It uses stock `windows-2022` only.

The [fixture README](../test/fixtures/windows_ggml_registry_qualification/README.md)
documents pinned inputs, source binding, disk preflight,
local execution and evidence verification. The 18 fresh H/E/P and alias cases
retain original failures as data, require all fixed cases, real model/context
creation and unload, passive module/IAT identities, maintained integration and
typed refusal controls, the actual declaration mutant with byte-exact restoration,
and the complete copied AOT distribution run from an empty external directory.
GPU artifacts do not qualify GPU operation. Setup failure, timeout, cancellation,
missing evidence or a failed terminal never count as qualification.

The one-day immutable artifact contains raw logs and manifests, never model
weights, Pub cache or SDK/runtime copies. Download by artifact ID and retain a
verified local copy before expiry; independently verify its outer digest and
inner inventory using the fixture verifier. A passing normal aggregate does not
establish a qualification result or replace independent interpretation.

## Web lazy grammar

Stage existing read-only weights under `build/web_lazy_grammar/models/` and write
`build/web_lazy_grammar/config.json`:

```json
{"assets":"bridge/","model":"models/stories15M.gguf"}
```

Run `dart run tool/testing/run_local_e2e.dart --scenario web-lazy-grammar --dry-run`
first, then omit `--dry-run`. The runner fetches pinned assets into `bridge/` and
uses `chrome-webgpu` for SharedArrayBuffer support. The suite loads CPU Wasm
(`gpuLayers: 0`) in direct and worker modes. Greedy output supplies a visible
prefix and unique two-token trigger; the constrained suffix must match the
requested grammar for word, pattern and pattern-full triggers. A scored token
checks token activation. Custom-root, missing-trigger, invalid-grammar and replay
rejection controls must preserve the runtime and subsequent plain output.

The prompt-penalty control also runs wasm32 and memory64 in both direct and
worker modes, checking actual runtime metadata. It finds a decisive scored
prompt token, verifies unchanged ordinary grammar defaults, and verifies that
explicit prompt penalties change the pick without activating a prompt-matching
lazy trigger. Keep both memory64 assets beside the wasm32 files.

This qualifies the Web grammar plumbing on the selected weights, not hardware
WebGPU or LFM2 auto accuracy/enforcement (#1715). The latter still needs its
separate template contract and false-probe restriction.

### Internal LiteRT C API1 JSON Schema candidate

`litert-lm-v1-json-schema` uses the internal injected v1 service, with the public
factory and runtime pins unchanged. It requires the existing CPU profile model
at revision `e6687177e00897731e7716267eebd4eba0dde7c2`, SHA-256
`c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108`,
613722264 bytes. The separately repaired local #48 artifact is not this input.
Supply the exact candidate library and both SHA256 environment variables shown
by `test_matrix.dart`; run `--list` and `--dry-run` before execution.

The fixed prompt first requests plain `BANANA`, independently of the target
schema. The qualifier requires that unconstrained control before testing a
Unicode-key/string, integer, boolean and null object with no additional fields.
It requires complete raw JSON without thinking delimiters, then repeats the
plain control to detect retained constraints. It cancels a longer fixed-schema
response after content, checks the actual native cancelled cause and settlement,
reuses schema generation, reloads the engine and repeats constrained/plain
requests. Prompt/schema hashes, source/tree identity, compiled-child hash,
runtime/model identity, events and native stderr are retained. The outer owner
bounds the child to 240 seconds and kills only that child if native completion
is uncertain. No automatic retry or accuracy-prompt tuning is performed.

This is schema enforcement and lifecycle evidence. It does not establish general
reasoning/geography accuracy, GPU/media support, public v1 activation or the
native IDs of the earlier malformed-output generation.


### Internal LiteRT v1 thinking budgets

Use `litert-lm-v1-thinking-budget` only for the maintained Gemma4 CPU bundle and
an explicitly admitted candidate runtime. It requires the core SHA256 and a
hash-bound manifest of all adjacent dylib names, byte sizes and SHA256 values.
It records actual loaded payload paths, native metrics/finish, exact output
bytes, native rendered inputs and effective sampler values. One prospectively
reviewed output cap of 1536 preserves both earlier 768-token failures; no automatic
cap escalation is allowed. The fixed train prompt compares unbounded
reasoning with budget 12, then checks no-budget isolation, cancellation, reload
and a false-context refusal. Run `--dry-run` first; the model-job owner schedules
the actual 600-second child. See [the adoption procedure](litert_lm_v1_adoption.md#actual-thinking-qualification)
for the complete environment and unchanged model/oracle identity. Passing this
scenario does not activate the public v1 factory or qualify GPU/media behavior.
