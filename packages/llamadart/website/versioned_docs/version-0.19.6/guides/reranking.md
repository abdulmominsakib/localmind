---
title: Cross-encoder reranking
sidebar_label: Reranking
description: Re-score retrieved candidates locally with a rank-pooled GGUF cross-encoder using LlamaReranker, including score semantics, input limits and cancellation.
---

Retrieve a candidate set with [embeddings](./embeddings), then score
query/document pairs with a separate rank-pooled GGUF reranker.
`LlamaReranker(engine)` borrows an already rank-pooled engine. For published
BERT/Jina rerankers that omit rank metadata, use the owning factory:

```dart
import 'package:llamadart/llamadart.dart';

Future<void> rerankLocal(String modelPath) async {
  final reranker = await LlamaReranker.load(
    LlamaModel(ModelSource.path(modelPath)),
    params: const LlamaCppModelParams(
      contextSize: 2048, batchSize: 2048, microBatchSize: 2048,
      maxParallelSequences: 4,
    ),
  );
  try {
    final results = await reranker.rerank('capital of France', [
      'Paris is the capital of France.', 'Rome is the capital of Italy.',
    ]);
    print(results.first.index);
  } finally {
    await reranker.dispose();
  }
}
```

## Owning and borrowed engines

The factory verifies a bounded GGUF classifier tensor directory and matching
output width before explicitly selecting RANK. It rejects unverified or ordinary
models, LoRA adapters and multimodal projectors. Normal engine loads retain
their original pooling configuration. `dispose()` releases an owned engine;
on a borrowed helper it leaves the caller's engine alive. Existing engine and
backend interfaces gain no required members.

```dart
import 'package:llamadart/llamadart.dart';

Future<List<LlamaRerankResult>> rankCandidates(
  LlamaEngine rerankerEngine,
  String query,
  List<String> documents,
) async {
  final reranker = LlamaReranker(rerankerEngine);
  final support = await reranker.capabilities;
  if (!support.isSupported) {
    throw LlamaUnsupportedException(support.unsupportedReason!);
  }
  return reranker.rerank(query, documents, topN: 5);
}
```

## Support and scores

Native llama.cpp supports RANK-pooled models such as Qwen3-Reranker and Jina/BGE
rerankers. WebGPU and LiteRT-LM report unsupported. Ordinary embedding and chat
models are rejected; `embed` continues to reject classifier output.

Results sort descending, retain the original document `index`, and keep
`classifierScores` and nullable `classifierLabels` in model order. The default
`scoreIndex: 0` matches upstream llama-server. For another class, inspect the
labels and pass its index explicitly. No positive label is inferred. Qwen3
returns native softmax probabilities; other models can return unbounded raw
scores. No sigmoid, L2 normalization or further softmax is applied.

## Templates and input limits

The model's named `rerank` template substitutes `{query}`, then `{document}`,
and parses its embedded special tokens. Without that template, query and
document are tokenized separately as literal text and framed with the
vocabulary's BOS/EOS/SEP flags. Inputs are not sent through the ordinary chat
renderer, and an ordinary chat-template override does not override reranking.

Every complete pair, including framing, must fit `maxInputTokens` from the
probe: the minimum of allocated context, per-sequence context, logical batch
and micro-batch limits. All pairs are checked before inference. Oversized input
throws `LlamaInferenceException`; it is never truncated and no partial result
is returned. Set `contextSize`, `batchSize` and `microBatchSize` at load to fit
your inputs. `maxParallelSequences > 1` enables independent sequence batching
within those limits; the default one scores documents sequentially.

## Ordering and cancellation

Ties preserve input order and duplicate documents retain separate indices.
`topN` limits results after all pairs are scored. Empty batches return no results
on a supported, loaded engine. Invalid score indices and negative `topN` throw
`LlamaArgumentException`. Call `reranker.cancel()` or `engine.cancelGeneration()`
to cancel this engine's inference; cancellation waits for its current native
pass before returning `LlamaInferenceException`. Await pending calls before
unloading or switching the engine's model, and always dispose the engine.

## Examples and validation

See the [CPU command-line example](https://github.com/leehack/llamadart/blob/main/example/basic_app/bin/llamadart_reranking_example.dart).
Native API availability alone does not qualify every model, quantization or
platform. Validation evidence: [Feature validation evidence](../maintainers/feature-validation#qualification-procedures).
