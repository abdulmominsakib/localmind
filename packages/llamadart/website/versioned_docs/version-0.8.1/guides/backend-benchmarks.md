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
