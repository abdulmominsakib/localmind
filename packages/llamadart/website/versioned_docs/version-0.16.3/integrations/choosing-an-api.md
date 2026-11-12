---
title: Choose an integration
sidebar_label: Choose an API
description: Choose direct llamadart, Genkit flows, or Flutter Edge AI orchestration without changing runtime ownership.
---

Choose the application API first, then choose a model and runtime. All three
routes use llamadart for GGUF inference; direct and Genkit APIs also support
compatible LiteRT-LM bundles; adding an orchestration layer does not
make a model support tools, strict JSON, images or embeddings.

| Start with | When it fits | First request |
| --- | --- | --- |
| Direct `llamadart` | You want engine control, a small dependency graph, or your own chat/history policy. `ChatSession` adds managed history. | [Core quickstart](../getting-started/quickstart) |
| `genkit_llamadart` | You already use Genkit, or want its flows, tools, retrieval and telemetry around local inference. | [Genkit setup](./genkit) |
| `flutter_edge_ai` with `flutter_edge_ai_llama` | You want Flutter Edge AI to own model installation, selection and app chat lifecycle, with GGUF as an additional engine. | [Flutter Edge AI source quickstart](./flutter-edge-ai) |

## Versions and availability

Checked on 2026-10-23:

| Route | Available combination | Qualification boundary |
| --- | --- | --- |
| Direct | Published `llamadart 0.16.x`; matching `0.16.x` Apple companions for each selected runtime | See the [runtime support matrix](../platforms/support-matrix); devices, models and backends have separate limits. |
| Genkit | Published `genkit_llamadart 3.5.0`, `genkit 1.0.0`, `llamadart 0.16.1`; Dart 3.12+ | Adapter fake/browser guards and selected native model tests cover specific paths. They do not qualify every Genkit Web deployment. |
| Flutter Edge AI | Upstream source connector `0.0.1`, core `2.4.0`, `llamadart 0.13.1`, GGUF Apple companion `0.13.0` | Connector remains `publish_to: none`. Use its pinned source example. The `0.15.0` upgrade [PR #684](https://github.com/DenisovAV/flutter_edge_ai/pull/684) and embedding SPI [PR #685](https://github.com/DenisovAV/flutter_edge_ai/pull/685) are pending, not released setup. |

The Genkit package now lives under `packages/genkit_llamadart` in this repository.
Its package name, `package:genkit_llamadart/...` imports, version and changelog
remain independent. Published 3.4.0 came from the original repository; the move
does not republish it. Detailed adapter guides remain in the
[package documentation](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/README.md).
Flutter Edge AI and its connector remain owned by their upstream repository.

## Ownership and feature boundaries

Use one owner for chat history and runtime lifetime. A direct `ChatSession`
can own history in a direct app; Genkit and Flutter Edge AI integrations already
manage their own history. Avoid putting a second session/history manager around
them. Cancel through the active adapter and dispose its model/plugin owner
when your app finishes using it.

| Feature | Direct | Genkit | Flutter Edge AI GGUF connector |
| --- | --- | --- | --- |
| Generation and streaming | `LlamaEngine.create`, optional `ChatSession` | `generate`, `generateStream`; inspect the final result | Installed model, chat session, typed streamed responses |
| Tools | Model/template/runtime dependent | Genkit tool loop, runtime capability checks; [tool guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#tool-calling) | Model dependent typed tools; [advanced guide](https://github.com/DenisovAV/flutter_edge_ai/blob/main/packages/flutter_edge_ai_llama/doc/advanced_usage.md) |
| Strict structured output | Grammar-capable runtime; see [structured output](../guides/generation-and-streaming#structured-json-output) | Grammar required; strict JSON with tools has additional native/template limits | Check the connector's response/schema API; a tool schema is not a promise of a Genkit-style strict JSON API |
| RAG and embeddings | [Embeddings](../guides/embeddings), [RAG tutorial](../tutorials/rag) | Text and capability-probed image/audio embeddings; [local retrieval](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/local-retrieval.md) | GGUF embedding integration is deferred; #685 is not shipped support |
| Image/audio chat and media tasks | Compatible model and runtime required | [Media guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/media-models.md); batch transcription, synthesis and image generation have distinct native owners | Compatible projector and model; connector capabilities differ from other Edge AI engines |

## Runtime setup still applies

Native build hooks download and bundle the selected runtime. Apple Flutter apps
need the matching direct runtime companion and deployment targets; Web apps need
bridge assets, workers, CORS and the required cross-origin headers. Follow
[installation](../getting-started/installation),
[native build hooks](../platforms/native-build-hooks) and
[Web bridge setup](../platforms/webgpu-bridge).

When combining Edge AI's LiteRT-LM engine with llamadart, keep llama.cpp as the
only llamadart native runtime. Selecting both LiteRT-LM distributions can cause
native symbol/library collisions. The [Edge AI guide](./flutter-edge-ai) links
the application-level hook configuration. Runtime owners and published artifacts
remain separate from these adapters; source support is not artifact qualification.
