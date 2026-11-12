# Runnable examples

Run these commands from the repository root after `dart pub get`. The examples
are native Dart CLIs. CPU defaults avoid GPU setup; they do not qualify a
Flutter Web deployment. The first run downloads weights when a default source
is listed; later runs reuse llamadart's cache.

## Start here

Start with chat, streaming, text embeddings and JSON. Owner/cache/bidi, LoRA
and telemetry are advanced examples that expose lifecycle or instrumentation.

```bash
dart run example/genkit_llamadart_example.dart
```

The [pub.dev example](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_example.dart) is a standalone Qwen3.5
quickstart with a pinned Hugging Face revision, 4,096-token context and model
sampling settings. It downloads about 533 MB. To use an existing model instead:

```bash
dart run example/genkit_llamadart_example.dart /models/chat.gguf
```

The streaming, agent, JSON, retrieval, resource and inspection examples use that same
Qwen3.5 default. Set `LLAMADART_MODEL_SOURCE` to a local instruct GGUF,
`hf://` source or HTTPS URL. `LLAMADART_MMPROJ_SOURCE` selects its matching
projector. The older `*_PATH` environment variables still work.
Model quality and supported options can differ with that override.

| Example | Run with `dart run example/…` | What it demonstrates |
| --- | --- | --- |
| [Streaming](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_streaming_example.dart) | `genkit_llamadart_streaming_example.dart` | Incremental text plus the final `onResult` outcome |
| [Agent](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_agent_example.dart) | `genkit_llamadart_agent_example.dart` | Typed city arguments, deterministic sampling, a Genkit tool loop and multi-turn history; fixtures are **demo data**, not live weather |
| [Rich tool schemas](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_tool_schema_example.dart) | `genkit_llamadart_tool_schema_example.dart` | Nullable input, numeric enums, closed objects and a native Genkit handler loop; downloads pinned Qwen3-1.7B, about 1.1 GB |
| [Structured JSON](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_json_example.dart) | `genkit_llamadart_json_example.dart` | Grammar-constrained streaming and parsed output; native grammar support required |
| [Local retrieval](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_retrieval_example.dart) | `genkit_llamadart_retrieval_example.dart` | Search three local text files, bound context and return an answer with source IDs |
| [Resource/data input](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_resources_example.dart) | `genkit_llamadart_resources_example.dart` | Explicitly resolve an approved resource and render bounded JSON data before generation |
| [Inspection and scoring](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_inspection_example.dart) | `genkit_llamadart_inspection_example.dart` | Loaded backend/context, raw token counts and next-token probabilities; native decoder required |
| [Embeddings](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_embedding_example.dart) | `genkit_llamadart_embedding_example.dart` | Normalized text vectors; downloads a pinned Jina embedding GGUF, about 20 MB |
| [Multimodal embeddings](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_multimodal_embedding_example.dart) | `genkit_llamadart_multimodal_embedding_example.dart image.png audio.wav` (or `--litert image.png audio.wav`) | Ordered text/image/audio to one normalized vector; downloads pinned EmbeddingGemma-2 GGUF + projector (about 1.54 GB), or LiteRT CPU bundle (485 MB); supply your own media |
| [Download/cache](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_source_prepare_example.dart) | `genkit_llamadart_source_prepare_example.dart` | Source preparation and cache reuse; pinned SmolLM2, about 88 MB |
| [Preparation UI](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_preparation_task_example.dart) | `genkit_llamadart_preparation_task_example.dart` | Download/load snapshots and warm-up; pinned SmolLM2, about 88 MB |
| [Decisions](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_decision_example.dart) | `genkit_llamadart_decision_example.dart` | Non-generative Laya choice, score and yes/no in a typed flow; downloads encoder/head, about 380 MB |
| [Dedicated owner](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_owner_example.dart) | `genkit_llamadart_owner_example.dart` | Application-owned raw completion and cancellation in a Genkit flow; downloads pinned SmolLM2, 88 MB |
| [Raw-prompt cache](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_prompt_cache_example.dart) | `genkit_llamadart_prompt_cache_example.dart` | Same-pool native KV reuse after owner replacement; pinned SmolLM2, 88 MB; no chat/RNG resume |
| [Experimental bidi](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_bidi_example.dart) | `genkit_llamadart_bidi_example.dart` | Two bounded native text turns through real Genkit `generateBidi`; pinned SmolLM2, 88 MB |
| [Live LoRA](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_lora_example.dart) | `genkit_llamadart_lora_example.dart /models/base.gguf /models/adapter.gguf` | Explicit matching base/adapter sources (local, hf:// or HTTPS); no generic safe default pair; apply/clear without reloading weights |

For a one-shot agent request instead of the interactive prompt:

```bash
LLAMADART_PROMPT='What is the demo temperature in Seoul?' \
  dart run example/genkit_llamadart_agent_example.dart
```

Use `clear` in the interactive agent to reset history. History consumes the
4,096-token context; long chats need application-level history management.
Source/preparation examples use compile-time overrides:

```bash
dart run -DLLAMADART_MODEL_SOURCE=/models/chat.gguf \
  -DLLAMADART_MODEL_CACHE=/tmp/model-cache \
  example/genkit_llamadart_source_prepare_example.dart
```

An embedding override must be an **embedding** GGUF, not the chat model:

```bash
LLAMADART_MODEL_SOURCE=/models/embedding.gguf \
  dart run example/genkit_llamadart_embedding_example.dart
```

Raw token counts omit the chat template, tools and media. Scoring measures
immediate raw continuation probabilities; it is not chat confidence or a
multi-token answer score. See [inspection](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/model-inspection.md),
[scoring](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/next-token-scoring.md), [decisions](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/decision-flows.md)
and [owner/LoRA limitations](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/runtime-owners.md).

## Model sources and local data

Most examples now run without model arguments. The default Hugging Face sources
pin a full commit revision and reuse llamadart's download cache. They run inference
locally; Hugging Face supplies weights, not a hosted model API.

Owner, prompt-cache, bidi and rich-tool examples accept one optional model source:

```bash
dart run example/genkit_llamadart_owner_example.dart 'hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf?revision=9e6855bc4be717fca1ef21360a1db4b29d5c559a'
```

The same argument can be a local path or a complete HTTPS model URL. Image input
accepts `MODEL_SOURCE PROJECTOR_SOURCE IMAGE`; multimodal embeddings accept
`MODEL_SOURCE PROJECTOR_SOURCE IMAGE AUDIO`, or
`--litert MODEL_SOURCE IMAGE AUDIO`. Keep model and projector from a compatible
pair. LoRA intentionally needs an explicit compatible base/adapter pair; the
[qualification pair](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/live-lora-qualification.md) requires conversion and has no published GGUF default.

Image/audio input files and generated output paths remain local. These are your
data, not model locations. LiteRT embedding examples read local PNG/WAV files
into encoded inputs because its embedding engine rejects unresolved paths.
`LLAMADART_EXAMPLE_CACHE` optionally selects the cache for examples using the
shared download helper; leaving it unset uses llamadart's normal cache.

## What is verified

Every Dart example is analyzed, and Dart snippets in README/guides/skills are
compiled by the documentation test. Real-model execution is separate and opt-in:

| Example group | Maintained runtime verification |
| --- | --- |
| Chat, streaming, agent, JSON, resources, retrieval, inspection | `real_model_examples_test.dart` executes the actual CLIs with checksum-pinned Qwen3.5 |
| Owner, prompt-cache, bidi, source/preparation UI, text embeddings, rich tools, image input, multimodal embeddings | `real_model_source_examples_test.dart` executes their default Hugging Face sources using an isolated cache seeded with checksum-verified fixtures; no extra downloads |
| Observability | `observability_example_test.dart` executes the CLI against a loopback collector and checks correlated spans, usage and privacy |
| LoRA, decision, transcription, speech synthesis, image generation | `real_model_specialty_examples_test.dart` executes the actual CLIs with checksum-pinned local overrides; checks adapter output changes, decision JSON, the JFK transcript, PCM WAV and decoded PNG |

All 22 CLI entry points have been executed on macOS arm64 CPU with llamadart
0.15.0. The generated speech was also transcribed back as “Hello from Jen Kit.”;
the generated image was visually checked for the requested red apple on blue.
Separate engine/adapter proofs cover deeper owner/cache/bidi/LoRA and media
behavior beyond these CLI checks.

These are bounded native CPU checks, not model-quality benchmarks or Web/mobile
qualification. Optional fixtures are skipped explicitly when absent; a skip is
not a pass. The cache-backed CLI tests verify source selection/cache reuse and
inference. A fresh-cache owner run separately checks real downloading.
See [the commands and exact fixtures](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/CONTRIBUTING.md#runnable-example-qualification).

## Images and speech

These preview examples require compatible native engines. They emit complete
results; transcription is whole-file, WAV synthesis is not incrementally
playable audio, and image generation returns a complete PNG. For typed-engine
imports in your own application, add `llamadart` explicitly as well as
`genkit` and `genkit_llamadart`.

| Example | Command | Models/setup |
| --- | --- | --- |
| [Image input](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_multimodal_example.dart) | `dart run example/genkit_llamadart_multimodal_example.dart image.png` | Downloads pinned Qwen3.5-0.8B + matching F16 projector (about 738 MB); supply your own image |
| [Transcription](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_transcription_example.dart) | `dart run example/genkit_llamadart_transcription_example.dart input.wav` | Downloads pinned Qwen3-ASR model/projector, about 1 GB; use a short trusted WAV |
| [Speech synthesis](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_speech_example.dart) | `dart run example/genkit_llamadart_speech_example.dart output.wav` | Downloads pinned Qwen3-TTS model/projector, about 1.5 GB; writes “Hello from Genkit.” as a complete WAV |
| [Image generation](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_image_example.dart) | `dart run example/genkit_llamadart_image_example.dart output.png` | Downloads pinned SDXS, about 683 MB; enable its native runtime first |

Transcription/speech accept model and projector sources after the WAV path;
image generation accepts an SDXS source after the output path. Every override
accepts a local path, `hf://` source or HTTPS URL. The output
commands overwrite the named file, so choose a new path when retaining outputs.
Image input accepts local PNG/JPEG files; remote input needs an explicit resolver
and URL policy. See [media input](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#image-and-audio-input).

For image generation, add this hook configuration to the application's
`pubspec.yaml`, then run `dart pub get` before the image command:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp, stable_diffusion]
```

The model pairs, backend requirements, output limits and supported controls are
in the [speech/image guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/media-models.md). These examples do not add
browser support or accept arbitrary model families through the Qwen adapters.

## Telemetry

The [observability example](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_observability_example.dart) needs
an application-configured OTLP collector. It records model and runtime spans,
token usage and timing metrics, with prompt/output capture disabled:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
  dart run example/genkit_llamadart_observability_example.dart
```

See [collector setup and privacy](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/observability.md). When copying this
example into an app, add `genkit_otel` and `dartastic_opentelemetry` to its
package dependencies.
