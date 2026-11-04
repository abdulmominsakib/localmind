# Contributor Test Matrix

This repository uses a layered test matrix so contributors can validate the
essential runtime, model, feature, and platform paths without forcing every pull
request to run large local models or device-only checks.

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
- `coverage-lib` when `lib/` behavior changed or coverage is in doubt

Docs-only PRs can mark runtime rows `N/A`, but should run `docs-site` when docs
or website files changed.

## Targeted Runtime and Model Rows

Pick targeted rows based on the touched surface:

| Change area | Matrix rows to consider |
| --- | --- |
| Native-assets hook, runtime pin, bundle layout | `native-hook-bundles`, `litert-lm-engine-smoke`, and relevant `platform` rows such as `android-arm64-device-smoke` |
| llama.cpp / GGUF generation, prompt reuse, context reuse | `native-prompt-reuse-parity`, `native-inference-benchmark`, `gguf-chat-features-smoke` |
| Chat template, parser, tools, thinking extraction | `template-parity`, `llama-cpp-chat-template-smoke`, `gguf-chat-features-smoke`, `litert-lm-chat-features-smoke` |
| LiteRT-LM native backend | `litert-lm-engine-smoke`, `litert-lm-chat-features-smoke` |
| Web bridge bootstrap or interop | `web-bridge-smoke`, `web-mock-chat-smoke`, `web-real-model-smoke` |
| WebGPU multimodal | `webgpu-multimodal-regression` |
| Large WebGPU GGUF / wasm64 selection | `gemma4-webgpu-mem64` |
| LiteRT-LM web / Gemma 4 web bundle | `gemma4-litert-web` |
| Chat app model cache/download/projector | `chat-app-device-cache` |
| Example app, CLI, or server package | `examples-tests` |

The required `Web Chat Contract` check runs the chat app tests on VM and
Chrome, validates the final Flutter Web artifact, exercises deterministic UI
behavior, and loads a tiny real GGUF through the packaged worker and WASM core.
Large Gemma 4 GGUF and LiteRT-LM downloads remain targeted rows so transient
model-host availability does not make every pull request flaky.

## Coverage Map

The matrix is designed to cover these essential axes:

| Axis | Covered by |
| --- | --- |
| llama.cpp native GGUF | `root-vm`, `native-prompt-reuse-parity`, `native-inference-benchmark`, `gguf-chat-features-smoke` |
| llama.cpp WebGPU GGUF | `web-bridge-smoke`, `web-mock-chat-smoke`, `web-real-model-smoke`, `webgpu-multimodal-regression`, `gemma4-webgpu-mem64` |
| LiteRT-LM native `.litertlm` | `litert-lm-engine-smoke`, `litert-lm-chat-features-smoke`, `native-hook-bundles` |
| LiteRT-LM web `.litertlm` | `gemma4-litert-web` |
| Model families | Qwen 2.5 prompt reuse, Qwen 3/3.5 chat/multimodal, Gemma 4 tool/thinking/mem64/LiteRT-LM |
| Feature paths | load/generate, prompt reuse, chat templates, streaming, tool calls, thinking, multimodal, model cache, native hook packaging |
| Platforms | See `dart run tool/testing/test_matrix.dart --tier platform`; each supported family/architecture is marked as CI, local, manual/device, or hook-only. |

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
| macOS x64 | `macos-x64-runtime-smoke` | Local/device runtime row. |
| iOS arm64 device | `ios-arm64-device-smoke` | Manual/device runtime row. |
| iOS arm64/x86_64 simulator | `ios-simulator-smoke` | Manual/simulator runtime row. |
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
scoped to release prep; after merge, `release_on_prep_merge.yml` publishes
missing companion versions, waits for `publish_companion_pubdev.yml`, verifies
the pub.dev version URL, and pushes the core release tag after the companion
gate passes.

## Local Model Scenarios

Real model checks are intentionally local-only. They can use the unified runner:

```bash
dart run tool/testing/run_local_e2e.dart --scenario gguf-chat-features-smoke \
  --model-path models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --backend auto

dart run tool/testing/run_local_e2e.dart --scenario gguf-chat-features-smoke \
  --model-path models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --backend cpu \
  --mmproj-path models/Qwen3.5-0.8B-mmproj-F16.gguf \
  --image-path test/fixtures/image.png

dart run tool/testing/run_local_e2e.dart --scenario litert-lm-chat-features-smoke \
  --model-path /path/to/gemma-4-E2B-it.litertlm \
  --backend auto

dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-mock-smoke

dart run tool/testing/native_inference_benchmark.dart \
  --model models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --gpu-layers 0 \
  --mode all \
  --runs 3 \
  --max-tokens 128

dart run tool/testing/run_local_e2e.dart \
  --scenario llama-cpp-speculative-benchmark \
  --model-path models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --speculative-cases baseline,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,ngram-cache,mixed-ngram \
  --backend cpu \
  --benchmark-gpu-layers 0 \
  --benchmark-max-tokens 128 \
  --benchmark-runs 3 \
  --draft-token-max 1,2 \
  --ngram-size-m 8,16 \
  --benchmark-warmups 1 \
  --ngram-cache-build-static-path /tmp/llamadart-ngram-cache.bin
```

In the local E2E scenario, external draft-model strategies require
`--draft-model-path`. Bundled MTP uses `draft-mtp` without that option; the
runner then loads the target with `ModelParams.loadMtp` automatically. The
n-gram cache strategy can use existing cache paths or build a static cache with
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
| `gguf-chat-features-smoke` | real GGUF chat/tool/thinking/multimodal smoke | macOS arm64, Qwen3.5-0.8B-Q4_K_M.gguf, llama.cpp auto/cpu | PASS | `RESULT gguf_chat_features ...`, no thinking marker leak, one `get_weather` tool call, optional image output |

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
