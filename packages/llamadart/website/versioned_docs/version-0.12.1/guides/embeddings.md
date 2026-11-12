---
title: On-device text embeddings
sidebar_label: Embeddings
description: Generate local embeddings with llamadart, understand backend support, and build retrieval-style workflows.
---

`llamadart` supports local embedding generation through `LlamaEngine` on
native and web runtimes.

## Basic usage

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = await LlamaEngine.load(
    LlamaModel(ModelSource.path('path/to/embedding-model.gguf')),
  );

  try {
    if (!(await engine.capabilities).supportsEmbeddings) {
      print('This backend cannot embed.');
      return;
    }

    final List<double> vector = await engine.embed('hello world');
    final List<List<double>> batch = await engine.embedBatch([
      'semantic search',
      'document retrieval',
    ]);

    print('single dims=${vector.length}');
    print('batch count=${batch.length}');
  } finally {
    await engine.dispose();
  }
}
```

## Backend support and compatibility

- Embeddings are an optional backend capability. After loading a model,
  `(await engine.capabilities).supportsEmbeddings`, like the synchronous
  `engine.supportsEmbeddings`, reports whether the active backend supports
  them; when it is false, `LlamaEngine.embed(...)` and
  `embedBatch(...)` throw `LlamaUnsupportedException`. It does not inspect the
  model, so the model limits below still apply.
- Native llama.cpp/GGUF backends support embeddings, including batched
  embeddings, when the loaded model was built for embedding output.
- On native, rank-pooled reranker GGUFs (such as Qwen3-Reranker) return
  classifier scores rather than embeddings, so `embed(...)` and
  `embedBatch(...)` throw `LlamaUnsupportedException` for them. Reranking is
  tracked in [#323](https://github.com/leehack/llamadart/issues/323).
- On native, encoder-decoder GGUFs (such as T5) throw
  `LlamaUnsupportedException`; use an encoder-only or decoder-only embedding
  model.
- On native, an input with more tokens than the context holds per sequence
  throws `LlamaInferenceException`; shorten it or raise `contextSize`. With
  `kvUnified: false`, the context is split across `maxParallelSequences`.
- On native, encoder-only models, models without a KV cache, non-causal
  models and MEAN/CLS-pooled models embed each input in one pass. This also
  applies when the model has a KV cache. An input longer than the context's
  actual micro-batch capacity throws `LlamaInferenceException` before decoding;
  shorten the input or raise `microBatchSize` and `batchSize` together.
  Causal models with a KV cache retain chunked LAST or unpooled embedding
  support. Batched one-pass inputs are grouped only within the micro-batch
  capacity, and every input is validated before any group is decoded.
- Native causal-attention detection follows the pinned llama.cpp `v0.6.0`
  contract: the runtime's diffusion-model probe and EmbeddingGemma's forced
  non-causal attention take precedence over metadata. Other loaded models
  use their boolean `<architecture>.attention.causal` value, defaulting to
  causal attention when that optional key is absent. Missing architecture,
  invalid attention metadata or an unavailable required runtime probe throws
  `LlamaUnsupportedException` before decoding. Use the pinned native runtime
  or a compatible runtime that exposes the required model information.
- Web backend supports embeddings when bridge assets expose embedding APIs
  (`v0.1.7` or newer).
- If web bridge assets are older than `v0.1.7`, embedding calls can fail with
  an unsupported/runtime error. Update bridge assets to a newer tag.
- `LlamaEngine.embedBatch(...)` uses true backend batching when available and
  otherwise falls back to repeated `embed(...)` calls.

## Retrieval-style flow (query + candidate ranking)

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = await LlamaEngine.load(
    LlamaModel(ModelSource.path('path/to/embedding-model.gguf')),
  );

  try {
    const query = 'How do I improve embedding throughput?';
    final candidates = <String>[
      'Increase maxParallelSequences for wider embedding batches.',
      'Tune batchSize and microBatchSize together.',
      'Use CPU fallback on constrained devices.',
    ];

    final queryVector = await engine.embed(query, normalize: true);
    final candidateVectors = await engine.embedBatch(
      candidates,
      normalize: true,
    );

    final scored = <MapEntry<String, double>>[];
    for (var i = 0; i < candidates.length; i++) {
      final score = dotProduct(queryVector, candidateVectors[i]);
      scored.add(MapEntry(candidates[i], score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    for (final result in scored.take(3)) {
      print('${result.value.toStringAsFixed(4)}  ${result.key}');
    }
  } finally {
    await engine.dispose();
  }
}

double dotProduct(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}
```

With `normalize: true`, dot-product scores correspond to cosine similarity,
which is usually the simplest ranking baseline for local retrieval.

## Throughput tuning for `embedBatch(...)`

`ModelParams` controls batching behavior at context creation time:

```dart
const params = ModelParams(
  contextSize: 4096,
  batchSize: 2048,
  microBatchSize: 2048,
  maxParallelSequences: 8,
);
```

These `2048` / `2048` values are explicit encoder-throughput settings, not the
decoder/generative defaults. Start with a smaller `microBatchSize` such as
`512` on memory-constrained devices and increase it only after measuring.
Web retains full-context automatic batching on CPU and WebGPU because model
architecture is not available before bridge context creation. Known decoder
presets can use smaller batches; see [Performance tuning](./performance-tuning).
An embedding input must fit its model's context and, for encoder-only,
no-memory, non-causal or MEAN/CLS-pooled models, one micro-batch. Set both
batch values explicitly only when tuning a known workload; selecting memory64 does not remove this micro-batch requirement.

- `batchSize` (`n_batch`): max logical tokens per forward pass.
- `microBatchSize` (`n_ubatch`): scheduler micro-batch size.
- `maxParallelSequences` (`n_seq_max`): parallel sequence slots for true
  multi-sequence embedding batches.

Start with `maxParallelSequences` matching expected concurrent batch width (for
example `4` or `8`), then tune based on memory and latency/throughput tradeoffs.

To measure sequential vs batch throughput, see
[Backend benchmarks](./backend-benchmarks#embedding-throughput).
