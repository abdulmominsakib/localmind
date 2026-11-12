---
title: Introduction
slug: /intro
---

`llamadart` is a Dart and Flutter plugin for running `llama.cpp` models with
GGUF files across native and web targets.

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
- Function calling: [Tool Calling](./guides/tool-calling)
- Template diagnostics: [Chat Templates and Parsing](./guides/chat-template-and-parsing)
- Template internals: [Template Engine Internals](./guides/template-engine-internals)
- LoRA runtime workflows: [LoRA Adapters](./guides/lora-adapters)
- Performance work: [Performance Tuning](./guides/performance-tuning)
- Platform/backend planning: [Platform & Backend Matrix](./platforms/support-matrix)
- Upgrade planning: [Upgrade Checklist](./migration/upgrade-checklist)
- Maintainer operations: [Maintainer Overview](./maintainers/docs-site)
