---
title: Embeddings
description: Generate local embeddings with llamadart, understand backend support, and build retrieval-style workflows.
---

`llamadart` supports local embedding generation through `LlamaEngine` on
native and web runtimes.

## Basic usage

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModel('path/to/embedding-model.gguf');

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

- Embeddings are an optional backend capability.
- If the active backend does not support embeddings, `LlamaEngine.embed(...)`
  and `embedBatch(...)` throw `LlamaUnsupportedException`.
- Native backend supports embeddings, including batched embeddings.
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
  final engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModel('path/to/embedding-model.gguf');

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

- `batchSize` (`n_batch`): max logical tokens per forward pass.
- `microBatchSize` (`n_ubatch`): scheduler micro-batch size.
- `maxParallelSequences` (`n_seq_max`): parallel sequence slots for true
  multi-sequence embedding batches.

Start with `maxParallelSequences` matching expected concurrent batch width (for
example `4` or `8`), then tune based on memory and latency/throughput tradeoffs.

## Benchmarking

Use the built-in scripts to compare sequential vs batch embedding throughput and
to sweep `max-seq` values.

```bash
# Single benchmark report
dart run tool/testing/native_embedding_benchmark.dart \
  --model path/to/model.gguf \
  --cpu \
  --mode both \
  --input-count 8 \
  --max-seq 8

# max-seq sweep with CSV output
dart run tool/testing/native_embedding_sweep.dart \
  --model path/to/model.gguf \
  --cpu \
  --max-seq-values 1,2,4,8 \
  --csv-out embedding_speedup.csv
```
