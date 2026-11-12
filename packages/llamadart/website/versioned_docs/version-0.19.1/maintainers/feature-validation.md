---
title: Feature validation evidence
description: Where feature qualification evidence lives for maintainers - qualification procedures, local-only scenarios, device calibration data and owner-repository trackers that user pages cite only as "Qualified on" lines.
---

User guides state what a feature was qualified on and link here once. The
procedures, receipts and calibration data below back those statements. Re-run
the relevant scenario when you change the behavior a line describes, and keep
the user page's "Qualified on" line in step with what you can reproduce.

## Qualification procedures

| Feature | Procedure |
| --- | --- |
| Native multimodal embeddings | [`doc/multimodal_embeddings_native.md`](https://github.com/leehack/llamadart/blob/main/doc/multimodal_embeddings_native.md) |
| Text embedding helpers (EmbeddingGemma-2 retrieval comparison) | [`doc/embedding_text_helpers.md`](https://github.com/leehack/llamadart/blob/main/doc/embedding_text_helpers.md) |
| Native reranking | [`doc/native_reranking.md`](https://github.com/leehack/llamadart/blob/main/doc/native_reranking.md) |
| Decision models (timings, parity, web check) | [`doc/decision_engine.md`](https://github.com/leehack/llamadart/blob/main/doc/decision_engine.md) |
| LiteRT-LM chat templates | [`doc/litert_lm_templates.md`](https://github.com/leehack/llamadart/blob/main/doc/litert_lm_templates.md) |
| Image seamless textures | [`doc/image_seamless_textures.md`](https://github.com/leehack/llamadart/blob/main/doc/image_seamless_textures.md) |
| Local image sets | [`doc/local_image_sets.md`](https://github.com/leehack/llamadart/blob/main/doc/local_image_sets.md) |
| Image editing | [`doc/image_editing.md`](https://github.com/leehack/llamadart/blob/main/doc/image_editing.md) |
| ControlNet | [`doc/image_controlnet.md`](https://github.com/leehack/llamadart/blob/main/doc/image_controlnet.md) |
| Hires fix | [`doc/image_hires_fix.md`](https://github.com/leehack/llamadart/blob/main/doc/image_hires_fix.md) |
| Reference image editing | [`doc/image_reference_editing.md`](https://github.com/leehack/llamadart/blob/main/doc/image_reference_editing.md) |

Run a scenario with `dart run tool/testing/run_local_e2e.dart --list`, then
`--scenario <name> --dry-run`, as in the repository's `AGENTS.md`.

## Local-only scenarios and receipts

- **Reranking.** The local-only `native-reranking` scenario compares against
  the pinned upstream oracle. Its receipts identify the model hashes, runtime
  revision and tested device and backend. Native API availability alone does
  not qualify a model, quantization or platform.
- **Chat app on Web.** `chat-app-web-mock-smoke` runs the chat app against a
  mock bridge with no model download:
  `dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-mock-smoke`.
  `tool/testing/serve_static_with_headers.py` serves a built app with the
  cross-origin isolation headers.
- **Command-line example.** The real-model parity gates in
  `example/llamadart_cli` are tagged `local-only` and need local llama.cpp
  builds and model files. The parity harness setup and environment overrides
  are in the example README.
- **Observability example.** Dart VM tests cover the adapter and OTLP/HTTP
  export; Flutter mobile and browser export are not qualified.
- **Image generation.** The `image-generation-smoke` checks cover the
  conditioning cache (disabled, default and one-entry caches with SDXS and
  SD-Turbo, repeated and changed prompts, eviction, cancellation and reload,
  on macOS arm64 CPU and Metal) and module placement (they read where the
  runtime put each module's weights, from `total params memory size` in its
  debug log, and compare pixels with the default placement). The
  `image-local-checkpoint-sets` scenario builds two unchanged shards from the
  fixed complete checkpoint, compares the public directory and index output
  with the pinned C settings, and checks source-removal lifetime, cache reuse,
  cancellation cleanup and recovery. `example/basic_app/bin/local_image_set.dart`
  is its runnable consumer. Approximation-cache modes are tracked in
  [#1233](https://github.com/leehack/llamadart/issues/1233).
- **Tool results with media.** The Hermes-style `<tool_call>` path was
  smoke-tested on macOS CPU and Metal with Qwen3.5-0.8B weights, a
  `qwen3vl_merger` projector and the Qwen3-VL template.

## LiteRT-LM Qwen3 bundles

The updated Qwen3-0.6B bundle is verified on macOS CPU, and Linux and Windows
CPU qualification runs in the maintained smoke workflow. GPU, iOS, Android and
Web adoption still need separate validation
([#554](https://github.com/leehack/llamadart/issues/554)). The registry
coverage, smoke commands and contribution notes for LiteRT-LM chat templates
are in `doc/litert_lm_templates.md`.

## Speech to text

Qwen3-ASR 0.6B Q8_0 was validated on WAV up to 33 s, and on MP3 and FLAC
copies of the 11 s `jfk.wav`, on native macOS and in headless Chromium.
Language-marker behavior has no dedicated validation contract yet. Built-in
windowing for inputs over 30 s is tracked in
[#327](https://github.com/leehack/llamadart/issues/327).

## Image generation

### Android memory-check calibration

The memory check's Android allowance comes from Firebase Test Lab runs of the
chat app's settings comparison. An app that kept touching all of its memory
was killed only after allocating 0.9 to 3.6 GiB more than `MemAvailable`:

| Phone (RAM) | `MemTotal` | `MemAvailable` at idle | Allocated when killed | Half of `MemTotal` less the app |
| --- | --- | --- | --- | --- |
| Moto G Play 2024 (4 GB) | 3.57 GiB | 1.38 GiB | 2.31 GiB | 1.45 GiB |
| Galaxy A53 (6 GB) | 5.26 GiB | 1.81 GiB | 2.81 GiB | 2.31 GiB |
| Pixel 6a (6 GB) | 5.45 GiB | 1.87 GiB | 3.63 GiB | 2.37 GiB |
| Galaxy S24 (8 GB) | 6.95 GiB | 2.38 GiB | 3.88 GiB | 3.10 GiB |
| Pixel 8a (8 GB) | 7.38 GiB | 2.56 GiB | 4.81 GiB | 3.29 GiB |
| Pixel 9 Pro (16 GB) | 15.19 GiB | 9.13 GiB | 12.75 GiB | 7.18 GiB |

With the check off, no SD-Turbo variant was killed on these phones, but the
Galaxy A53 swapped most of the app out: a one-step image took 65 s with TAESD
and 282 s with the full VAE, against 18 s and 67 s on the Pixel 6a. The
Android memory figure varied by up to a gigabyte between idle readings.

The GPU memory rules are tested on reported figures. The call that reads them
is checked on macOS Metal, where its total equals the working set. On an
NVIDIA L4 under Vulkan, one GPU each on Linux and Windows, the figures, the
device facts and the device selection were checked. The warning, the refusal
and the two-GPU paths have not been checked on a physical GPU yet
([#1024](https://github.com/leehack/llamadart/issues/1024)).

### Attention and VAE measurements

The phone figures in the user guide's attention and VAE table are Firebase
Test Lab runs of the chat app's settings comparison. Peak memory is the
`phys_footprint` interval peak on the iPhone and a 20 ms sampled `VmRSS` peak
on Android, where Test Lab refused the `VmHWM` reset on all three phones. The
Galaxy A53's memory check refused SD-Turbo (about 2.9 GiB needed, 2.5 GiB
available), so it has no SD-Turbo figures, and its SDXS figures come from a run
that does not verify because of that refusal: they are an observation, not
verified evidence. The iPhone full-VAE arm has not been measured, because its
decode trips the GPU watchdog
([#1047](https://github.com/leehack/llamadart/issues/1047)).

### Full-checkpoint container checks

Earlier `v0.2.0-4` checks rejected the 2.6-GB legacy file and timed out on full
ZIP inputs. The current legacy result verifies the published reader repair;
ZIP's earlier timeout cause remains unresolved
([stable-diffusion-native#24](https://github.com/leehack/stable-diffusion-native/issues/24)).
Passing the selected ZIP inputs is a later non-reproduction, not proof of a
causal ZIP fix.

### Owner-repository trackers

- Newer upstream and FP8 CPU qualification:
  [stable-diffusion-native#20](https://github.com/leehack/stable-diffusion-native/issues/20).
- Process abort in `new_sd_ctx` when the GPU budget is below the weights:
  [stable-diffusion-native#34](https://github.com/leehack/stable-diffusion-native/issues/34).
- Android GPU backends (ggml Vulkan and OpenCL crashed or ran slower on the
  phones tried):
  [stable-diffusion-native#2](https://github.com/leehack/stable-diffusion-native/issues/2).

## Chat templates

Flint's `\x` escape repair does not qualify the architecture for the pinned
native runtime; see
[llamadart-native#112](https://github.com/leehack/llamadart-native/issues/112).
