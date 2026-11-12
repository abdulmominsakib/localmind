---
title: Introduction
slug: /intro
description: Learn what llamadart provides and where to start when building local AI features in Dart and Flutter.
---

`llamadart` is a Dart and Flutter plugin for local LLMs. It runs GGUF models
through `llama.cpp` across native and web targets, and routes `.litertlm`
bundles through LiteRT-LM native and web runtimes.

## Who this is for

- App developers building local-first AI features in Dart/Flutter.
- Teams that need OpenAI-style HTTP compatibility from local models.
- Maintainers who need predictable native/web runtime integration.

## Core primitives

- `LlamaEngine`: stateless generation API.
- `ChatSession`: stateful chat wrapper over `LlamaEngine`.
- `LlamaBackend`: platform backend abstraction used by the engine.

## Read by workflow

- First setup: [Installation](./getting-started/installation)
- First inference: [Quickstart](./getting-started/quickstart)
- Multi-turn chat: [First Chat Session](./getting-started/first-chat-session)
- Backend choice: [Choosing llama.cpp or LiteRT-LM](./guides/backend-selection)
- Embedding pipelines: [Embeddings](./guides/embeddings)
- Function calling: [Tool Calling](./guides/tool-calling)
- Template diagnostics: [Chat Templates and Parsing](./guides/chat-template-and-parsing)
- Template internals: [Template Engine Internals](./guides/template-engine-internals)
- LoRA runtime workflows: [LoRA Adapters](./guides/lora-adapters)
- Performance work: [Performance Tuning](./guides/performance-tuning)
- Backend benchmark results: [Backend Benchmarks](./guides/backend-benchmarks)
- Platform/backend planning: [Platform & Backend Matrix](./platforms/support-matrix)
- Upgrade planning: [Upgrade Checklist](./migration/upgrade-checklist)
- Maintainer operations: [Maintainer Overview](./maintainers/docs-site)
