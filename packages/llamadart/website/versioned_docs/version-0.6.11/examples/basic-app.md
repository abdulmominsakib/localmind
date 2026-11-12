---
title: Basic App Example
---

Path: `example/basic_app`

This example is the fastest way to inspect core API usage in a console app.

## Run

```bash
cd example/basic_app
dart pub get
dart run

# Embedding example
dart run bin/llamadart_embedding_example.dart -i "hello world" -i "rag"

# Embedding retrieval-style probe (query first, candidates next)
dart run bin/llamadart_embedding_example.dart \
  -i "how do I improve embedding throughput?" \
  -i "Increase maxParallelSequences for wider batches." \
  -i "Tune batchSize and ubatchSize together."

# Embedding parity-oriented run (CPU + explicit knobs)
dart run bin/llamadart_embedding_example.dart \
  --cpu --ctx-size 2048 --threads 12 --threads-batch 12 \
  --batch-size 2048 --ubatch-size 2048 --max-seq 2 \
  -i "hello world" -i "semantic search"

# SQLite vector retrieval example (llamadart embeddings + sqlite_vector)
dart run bin/llamadart_sqlite_vector_example.dart \
  -q "How do I improve embedding throughput?" \
  -d "Increase maxParallelSequences for wider embedding batches." \
  -d "Tune batchSize and ubatchSize together."

# SQLite vector retrieval (quantized ANN mode)
dart run bin/llamadart_sqlite_vector_example.dart \
  --quantized --top-k 5 \
  -q "How do I improve embedding throughput?" \
  -d "Increase maxParallelSequences for wider embedding batches." \
  -d "Tune batchSize and ubatchSize together."

# Quantized quality check (ANN vs exact recall)
dart run bin/llamadart_sqlite_vector_example.dart \
  --quantized --compare-exact --quantized-qtype INT8 \
  --quantized-max-memory 64MB --top-k 5 --min-similarity 0.45 \
  -q "How do I improve embedding throughput?" \
  -d "Increase maxParallelSequences for wider embedding batches." \
  -d "Tune batchSize and ubatchSize together."
```

The embedding CLI prints runtime backend, vector dimensions, and a short
numeric preview per input.
By default, embedding CLIs use
`ggml-org/embeddinggemma-300M-GGUF` (`embeddinggemma-300M-Q8_0.gguf`); pass
`--model` to use a different embedding GGUF.
The SQLite vector CLI stores embeddings as BLOB vectors in SQLite and supports
exact `vector_full_scan(...)` plus optional quantized `vector_quantize_scan(...)`.

Result interpretation:

- Lower `distance` is better.
- With default normalized embeddings (COSINE), similarity is reported as
  approximately `1 - distance`.
- With non-normalized embeddings (L2), similarity is reported as
  `1 / (1 + distance)`.
- `relevance` labels are convenience buckets derived from similarity.
- `--min-similarity` hides low-similarity rows from output.
- `--compare-exact` reports recall@k and distance deltas for quantized results.
- `--quantized-qtype` and `--quantized-max-memory` tune ANN quantization.

## Test

```bash
cd example/basic_app
dart test
```

## What it demonstrates

- Engine initialization.
- Model loading and teardown.
- Streaming token generation.
- Single and batched embeddings.
- Quick query/candidate embedding probes for retrieval experiments.
- End-to-end local retrieval with SQLite vector search.
- Optional quantized ANN retrieval mode for larger corpora.
- Quantized-vs-exact quality checks with recall metrics.
- Small-footprint project setup for non-Flutter Dart apps.
