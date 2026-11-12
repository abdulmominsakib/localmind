---
title: Basic app example
sidebar_label: Basic app
description: Minimal Dart console apps for chat, embeddings, SQLite vector retrieval and decision models, the quickest way to see the core llamadart API.
---

Path: `example/basic_app` · Platforms: Dart console on macOS, Linux and
Windows · First-run download: `Qwen3.5-0.8B-Q4_K_M.gguf` (533 MB)

Dart console apps that show the core API: chat, embeddings, vector retrieval
and decision models, without Flutter.

## Run

```bash
cd example/basic_app
dart pub get
dart run
```

Variants:

```bash
# Embeddings (downloads embeddinggemma-300M-Q8_0.gguf, 334 MB)
dart run bin/llamadart_embedding_example.dart -i "hello world" -i "rag"

# Retrieval: embeddings stored and searched in SQLite with sqlite_vector
dart run bin/llamadart_sqlite_vector_example.dart \
  -q "How do I improve embedding throughput?" \
  -d "Increase maxParallelSequences for wider embedding batches." \
  -d "Tune batchSize and ubatchSize together."

# Decision model: triage a support ticket
# (downloads laya-Q8_0.gguf, 421 MB, and laya-head.safetensors, 106 MB)
dart run bin/llamadart_decision_example.dart
```

## What it demonstrates

- Loading a model from an `hf://` source into the shared cache, streaming a
  chat reply, and disposing the engine
  ([Generation and streaming](../guides/generation-and-streaming)).
- LoRA adapters (`--lora`), GBNF-constrained output (`--grammar`) and a
  sample tool call (`--tool-test`) in the chat CLI
  ([LoRA adapters](../guides/lora-adapters),
  [Tool calling](../guides/tool-calling)).
- Single and batched embeddings, and query-versus-candidate probes
  ([Embeddings](../guides/embeddings)).
- Local retrieval with SQLite vector search, exact or quantized, with a
  recall check against exact search ([Embeddings](../guides/embeddings)).
- Typed choice, score and yes/no answers from a decision model with
  `ChoiceKey.enumOf`, `ScoreKey.of`, `NoulKey.of` and `answerOf`
  ([Decision models](../guides/decision-models#typed-questions)).

## Test

```bash
cd example/basic_app
dart test
```

Full options: every flag of the four CLIs, the retrieval result fields and
the decision-model head options are in the
[example README](https://github.com/leehack/llamadart/tree/main/example/basic_app).
