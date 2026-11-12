---
title: Backend Benchmarks
description: Measured llama.cpp/GGUF and LiteRT-LM results for Gemma 4 on Android, macOS, and web.
---

This page records app-level benchmark results for choosing between
`llama.cpp` / GGUF and LiteRT-LM / `.litertlm` in `llamadart`.

These are deployment benchmarks, not pure kernel benchmarks. The artifacts are
different runtime formats:

- `gemma-4-E2B-it-Q4_K_S.gguf` for `llama.cpp`.
- `gemma-4-E2B-it.litertlm` for native LiteRT-LM.
- `gemma-4-E2B-it-web.litertlm` for LiteRT-LM web.

## Method

All runs used the same long-form prompt, `contextSize` / max context of 4096,
a target output cap of 256 tokens, one warmup run, and three measured runs. The
tables report the median of the measured runs unless noted.

The prompt asked for a practical guide covering privacy, latency, offline
behavior, personalization, battery tradeoffs, model formats, benchmarking,
rollout strategy, and failure modes.

Web runs use the chat app and the benchmark static server, which sets the
COOP/COEP headers required for threaded WebAssembly and supports byte-range
requests for large local model artifacts.

## Results

| Device / target | Backend | Model artifact | Runtime path | Median wall tok/s | Median decode tok/s | Load / init notes |
| --- | --- | --- | --- | ---: | ---: | --- |
| Pixel 9 Pro, Android 16 | LiteRT-LM | `gemma-4-E2B-it.litertlm` | GPU | 15.18 | 15.51 | `loadMilliseconds=261`, backend init about 8.6s |
| Pixel 9 Pro, Android 16 | llama.cpp | `gemma-4-E2B-it-Q4_K_S.gguf` | Vulkan | 1.66 | 1.82 | `loadMilliseconds=8831`; process reached about 7.4 GB RSS |
| Mac, Apple M4 Max, macOS 26.5 | LiteRT-LM | `gemma-4-E2B-it.litertlm` | Metal | 130.08 | 131.90 | `loadMilliseconds=86`, backend init about 4.6s |
| Mac, Apple M4 Max, macOS 26.5 | llama.cpp | `gemma-4-E2B-it-Q4_K_S.gguf` | Metal | 136.15 | 140.48 including sampling | `loadMilliseconds=1883`; backend eval-only counter was much higher |
| Web, Chromium on Apple M4 Max | LiteRT-LM | `gemma-4-E2B-it-web.litertlm` | WebGPU | 48.70 | 49.80 | `loadMilliseconds=7727`; first token 107-114ms |
| Web, Chromium on Apple M4 Max | llama.cpp | `gemma-4-E2B-it-Q4_K_S.gguf` | WebGPU bridge | 23.90 | 24.40 | `loadMilliseconds=58641`; WebGPU worker, wasm64, 99 GPU layers |

Earlier Gemma 4 GGUF web failures were benchmark-harness artifacts, not a chat
app support failure. The current web benchmark uses the same mem64 bootstrap
path as the chat app, selects `GpuBackend.auto`, serves local GGUF files with
byte-range support, and falls back from the fetch-backed loader to streamed
loading when the bridge reports a generic `core_abort`.

The Pixel 9 Pro was explicitly woken and kept awake with `svc power stayon true`.
Thermal status was 0 before the benchmark and 1 after the run, so the Android
numbers should be treated as practical app-level numbers rather than a cooled
lab baseline.

### Speculative decoding check

After `GenerationParams.speculativeDecoding` was exposed for native LiteRT-LM,
the Gemma 4 E2B `.litertlm` path was rerun with the flag off and on. The flag
remains off by default because the measured result was slower for this model on
both devices.

| Device / target | Runtime path | `speculativeDecoding` | Median wall tok/s | Median decode tok/s | Result |
| --- | --- | ---: | ---: | ---: | --- |
| Pixel 9 Pro, Android 16 | LiteRT-LM GPU | `false` | 15.50 | 15.70 | baseline |
| Pixel 9 Pro, Android 16 | LiteRT-LM GPU | `true` | 9.06 | 9.13 | about 42% slower |
| Mac, Apple M4 Max, macOS 26.5 | LiteRT-LM Metal | `false` | 135.02 | 136.70 | baseline |
| Mac, Apple M4 Max, macOS 26.5 | LiteRT-LM Metal | `true` | 118.96 | 120.25 | about 12% slower |

The Pixel NPU path was also attempted for `gemma-4-E2B-it.litertlm`, but native
LiteRT-LM failed engine creation for backend `npu` on this device/model bundle
and reported that the Android NPU delegate may not support the device, OS,
model, or bundle. Use GPU or CPU for this artifact unless a newer LiteRT-LM
bundle/runtime combination validates NPU support.

### llama.cpp upstream speculative parity check

The llama.cpp speculative investigation on 2026-07-05 found no package-level
model-cache issue and no evidence that upstream speculative decoding is
universally faster. It is workload- and knob-sensitive. The clear local speedup
came from an explicit repeated-context workload with smaller n-gram lookup
settings.

At the time of this investigation, the package runtime pin was
`leehack/llamadart-native@b9873`. That release did not publish standalone
`llama-cli` / `llama-server` tool binaries, so upstream CLI comparison used the
closest local llama.cpp tool build available from `llamadart-native`
(`build b1-e3471b3e7`, from the b9571 line). Treat the CLI rows as historical
behavior references, not exact artifact parity for the current runtime pin.

| Runtime | Prompt / config | Backend | Baseline | Speculative | Relative | Notes |
| --- | --- | --- | ---: | ---: | ---: | --- |
| llamadart runner | Raw repeated sequence, `ngram-map-k`, `ngramSizeN=4`, `ngramSizeM=8` | CPU | 135.71 wall tok/s | 222.24 wall tok/s | 1.64x | 112/112 drafts accepted, output hash matched |
| llamadart runner | Same, `ngram-map-k4v`, `ngramSizeN=4`, `ngramSizeM=8` | CPU | 135.71 wall tok/s | 212.21 wall tok/s | 1.56x | 112/112 drafts accepted, output hash matched |
| llamadart runner | Qwen chat-template code prompt, default `ngram-map-k` sizing | CPU | 103.11 wall tok/s | 67.82 wall tok/s | 0.66x | auxiliary observation from the investigation; zero drafts produced |
| llamadart runner | Raw code prompt, default n-gram sizing | Metal | 250.63 wall tok/s | 125.61 wall tok/s | 0.50x | auxiliary observation from the investigation; zero drafts produced |
| upstream `llama-cli` | Same repeated text through `llama-cli` single-turn chat/conversation path, same n-gram knobs as first row | CPU, `--device none` | 138.7 generation tok/s | 164.1 generation tok/s | 1.18x | local b9571 CLI; metric excludes prompt handling |

Conclusion: draftless n-gram speculation can be faster in llamadart when the
prompt has reusable repeated context and the n-gram knobs match the workload.
For natural short prompts or code prompts without a matching recent history,
the draftless n-gram strategies can produce no drafts, so the extra speculative
loop work is slower than baseline. For draft-model and `ngram-cache`
strategies, use `draftTokenMax` as the per-step draft cap. For `ngram-mod`, use
`ngramTokenMax` when set, otherwise `draftTokenMax` or the llama.cpp default.
For `ngram-simple`, `ngram-map-k`, and `ngram-map-k4v`, tune the effective
draft length with `ngramSizeM` to match upstream's n-gram draft window.

Remaining actionable work was split out instead of being folded into this
benchmark documentation. [llamadart-native#26](https://github.com/leehack/llamadart-native/issues/26)
tracks exact native tool artifacts for future same-tag upstream comparisons;
the earlier n-gram rollback and native sampler fixes have landed.

## Interpretation

On Pixel 9 Pro, LiteRT-LM GPU was about 9x faster than llama.cpp Vulkan for this
Gemma 4 E2B deployment comparison. The GGUF/Vulkan path also consumed much more
memory and pushed the device into light thermal pressure by the end of the run.

On the M4 Max, llama.cpp Metal and LiteRT-LM Metal were close for wall-clock
throughput. Use model format, feature needs, and distribution constraints as
the deciding factors on macOS rather than assuming LiteRT-LM is faster.

On web, both Gemma 4 artifacts completed through the chat app. LiteRT-LM WebGPU
was about 2x faster than the GGUF WebGPU bridge on the measured decode counter,
and its cold model load was much shorter. GGUF web still worked, but it was more
sensitive to serving behavior because the large artifact needs a range-capable
server or browser cache path.

## Reproducing

macOS:

```bash
DECODE_TOKENS=256 tool/macos_fair_litert_vs_llamadart.sh

# Native LiteRT-LM speculative decoding off/on check
SPECULATIVE=false DECODE_TOKENS=256 tool/macos_fair_litert_vs_llamadart.sh
SPECULATIVE=true  DECODE_TOKENS=256 tool/macos_fair_litert_vs_llamadart.sh
```

Web:

```bash
DOWNLOAD_LITERT_WEB_MODEL=1 \
DECODE_TOKENS=256 \
WARMUPS=1 \
RUNS=3 \
TARGETS=llamadart,litert_lm \
tool/web_fair_litert_vs_llamadart.sh
```

Pixel / Android:

```bash
ADB=/path/to/adb
DEVICE=<adb-serial>
"$ADB" -s "$DEVICE" shell svc power stayon true
"$ADB" -s "$DEVICE" shell input keyevent KEYCODE_WAKEUP

DEVICE="$DEVICE" \
ADB="$ADB" \
OUTPUT_TOKENS=256 \
WARMUPS=1 \
RUNS=3 \
TARGETS=litert_lm,llamadart \
tool/litert_lm_pixel_benchmark.sh

# Native LiteRT-LM GPU speculative decoding off/on check
DEVICE="$DEVICE" ADB="$ADB" TARGETS=litert_lm BACKEND=gpu \
  SPECULATIVE=false OUTPUT_TOKENS=256 WARMUPS=1 RUNS=3 \
  tool/litert_lm_pixel_benchmark.sh
DEVICE="$DEVICE" ADB="$ADB" TARGETS=litert_lm BACKEND=gpu \
  SPECULATIVE=true OUTPUT_TOKENS=256 WARMUPS=1 RUNS=3 \
  tool/litert_lm_pixel_benchmark.sh
```

For web GGUF experiments, use `TARGETS=llamadart`. If serving local large GGUF
files, use the included benchmark server or another range-capable server; simple
single-threaded file servers can make large browser model loads fail before the
runtime sees real GGUF bytes. `python -m http.server` is not a good substitute
for this benchmark because it does not provide the same browser isolation and
large-file behavior.

Speculative n-gram parity:

Set `MODEL_PATH` to the cached GGUF location on your machine. Set `LLAMA_CLI`
to the upstream `llama-cli` build you are comparing; the table above used a
local b9571-line tool because the b9873 native release did not publish
standalone CLI artifacts.

```bash
MODEL_PATH="${MODEL_PATH:-$HOME/Library/Caches/llamadart/models/Qwen3.5-0.8B-Q4_K_M.gguf}"
LLAMA_CLI="${LLAMA_CLI:-/path/to/llama-cli}"

PROMPT_REPEAT='Repeat and continue this sequence exactly:
alpha beta gamma delta epsilon zeta eta theta
alpha beta gamma delta epsilon zeta eta theta
alpha beta gamma delta epsilon zeta eta theta
alpha beta gamma delta epsilon zeta eta theta
alpha beta gamma delta epsilon zeta eta theta'

dart run tool/testing/llama_cpp_speculative_benchmark.dart \
  --model "$MODEL_PATH" \
  --cases baseline,ngram-map-k,ngram-map-k4v \
  --backend cpu \
  --gpu-layers 0 \
  --context-size 4096 \
  --max-tokens 128 \
  --runs 2 \
  --warmups 1 \
  --draft-token-max 8 \
  --ngram-size-n 4 \
  --ngram-size-m 8,16 \
  --ngram-min-hits 1 \
  --temp 0 \
  --repeat-penalty 1.0 \
  --raw-prompt \
  --prompt "$PROMPT_REPEAT"

"$LLAMA_CLI" \
  -m "$MODEL_PATH" \
  --device none \
  -ngl 0 \
  -c 4096 \
  -n 128 \
  --temp 0 \
  --repeat-penalty 1.0 \
  --top-k 40 \
  --top-p 0.95 \
  --min-p 0.05 \
  --seed 7 \
  --single-turn \
  --no-display-prompt \
  --simple-io \
  -p "$PROMPT_REPEAT"

"$LLAMA_CLI" \
  -m "$MODEL_PATH" \
  --device none \
  -ngl 0 \
  -c 4096 \
  -n 128 \
  --temp 0 \
  --repeat-penalty 1.0 \
  --top-k 40 \
  --top-p 0.95 \
  --min-p 0.05 \
  --seed 7 \
  --single-turn \
  --no-display-prompt \
  --simple-io \
  --spec-type ngram-map-k \
  --spec-draft-n-max 8 \
  --spec-ngram-map-k-size-n 4 \
  --spec-ngram-map-k-size-m 8 \
  --spec-ngram-map-k-min-hits 1 \
  -p "$PROMPT_REPEAT"
```
