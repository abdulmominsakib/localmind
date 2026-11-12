---
title: "Tutorial: retrieval-augmented generation"
sidebar_label: Retrieval (RAG)
description: Embed documents on the device, retrieve the best matches for a question by cosine similarity, and answer with a local chat model grounded in them.
---

Retrieval-augmented generation (RAG) answers questions from your own documents:
embed the documents once, embed each question, pick the closest documents,
and pass them to a chat model as context. Everything here runs on the device.

This tutorial is a Dart console program. The same calls work in a Flutter app.

## The program

Create a package with `dart create local_rag`, run `dart pub add llamadart`,
and replace `bin/local_rag.dart`:

```dart
import 'dart:io';
import 'dart:math' as math;

import 'package:llamadart/llamadart.dart';

const String embeddingModel =
    'hf://ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf';
const String chatModel =
    'hf://unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_K_M.gguf';

const List<String> documents = <String>[
  'The Harbor Street library opens at 9 AM and closes at 6 PM on weekdays.',
  'On Saturdays the Harbor Street library is open from 10 AM to 2 PM. '
      'It is closed on Sundays.',
  'Library members can borrow up to 12 books at once for three weeks.',
  'Late returns cost 25 cents per book per day, capped at 5 dollars.',
  'The library cafe on the second floor serves coffee and sandwiches.',
  'Study rooms can be booked online up to seven days in advance.',
];

Future<void> main(List<String> args) async {
  final String question = args.isNotEmpty
      ? args.join(' ')
      : 'When is the library open on Saturday?';

  final LlamaEngine embedder = LlamaEngine(LlamaBackend());
  final LlamaEngine generator = LlamaEngine(LlamaBackend());

  try {
    // 1. Load an embedding model and index the documents.
    await embedder.loadModelSource(
      ModelSource.parse(embeddingModel),
      modelParams: ModelParams(
        contextSize: 2048,
        maxParallelSequences: documents.length,
      ),
      onProgress: _printProgress('embedding model'),
    );
    final List<List<double>> index = await embedder.embedBatch(documents);

    // 2. Embed the question and rank the documents by cosine similarity.
    final List<double> query = await embedder.embed(question);
    final List<({String text, double score})> ranked =
        <({String text, double score})>[
          for (int i = 0; i < documents.length; i++)
            (text: documents[i], score: cosineSimilarity(query, index[i])),
        ]..sort((a, b) => b.score.compareTo(a.score));
    final List<({String text, double score})> top = ranked.take(2).toList();

    print('Question: $question');
    for (final ({String text, double score}) hit in top) {
      print('  ${hit.score.toStringAsFixed(3)}  ${hit.text}');
    }

    // 3. Answer with a chat model, grounded in the retrieved chunks.
    await generator.loadModelSource(
      ModelSource.parse(chatModel),
      modelParams: const ModelParams(contextSize: 2048),
      onProgress: _printProgress('chat model'),
    );
    final String context = top.map((hit) => '- ${hit.text}').join('\n');
    final List<LlamaChatMessage> messages = <LlamaChatMessage>[
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text:
            'Answer using only the context. '
            'If the context does not contain the answer, say you do not know.',
      ),
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Context:\n$context\n\nQuestion: $question',
      ),
    ];

    stdout.write('Answer: ');
    await for (final LlamaCompletionChunk chunk in generator.create(
      messages,
      params: const GenerationParams(maxTokens: 128, temp: 0.2),
      enableThinking: false,
    )) {
      stdout.write(chunk.choices.first.delta.content ?? '');
    }
    stdout.writeln();
  } finally {
    await generator.dispose();
    await embedder.dispose();
  }
}

double cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0;
  double normA = 0;
  double normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}

ModelDownloadProgressCallback _printProgress(String label) {
  int lastPercent = -1;
  return (ModelDownloadProgress progress) {
    final double? fraction = progress.fraction;
    if (fraction == null) return;
    final int percent = (fraction * 100).floor();
    if (percent != lastPercent && percent % 10 == 0) {
      lastPercent = percent;
      stderr.writeln('Downloading $label: $percent%');
    }
  };
}
```

Run it with `dart run`, optionally passing a question:

```bash
dart run bin/local_rag.dart "How much is the late fee?"
```

The first run downloads both models (about 330 MB and 530 MB). On an Apple
Silicon Mac, the default question retrieves the right two documents:

```text
Question: When is the library open on Saturday?
  0.755  On Saturdays the Harbor Street library is open from 10 AM to 2 PM. It is closed on Sundays.
  0.624  The Harbor Street library opens at 9 AM and closes at 6 PM on weekdays.
```

## How it works

1. **Two engines.** An engine holds one model, so the embedding model and the
   chat model each get their own `LlamaEngine`.
2. **Indexing.** `embedBatch` embeds all documents. Setting
   `maxParallelSequences` lets llama.cpp embed them in one batch; with the
   default of `1`, `embedBatch` embeds them one at a time.
3. **Retrieval.** `embed` and `embedBatch` return L2-normalized vectors by
   default, so cosine similarity equals the dot product. The program keeps the
   two best matches.
4. **Generation.** The retrieved text goes into the user message with an
   instruction to answer only from it. `enableThinking: false` turns off
   Qwen3.5's reasoning so the reply streams straight away.

## Limits to plan for

- **Chunk your documents.** EmbeddingGemma embeds its input in one pass of at
  most `microBatchSize` tokens (512 by default). Longer input fails, with
  `LlamaInferenceException` while it fits the context; nothing is truncated for
  you. Split documents into passages, or raise `microBatchSize`, `batchSize`
  and, past 2048 tokens, `contextSize`.
- **Answer quality depends on the chat model.** Retrieval scores were sensible
  in every test run, but the 0.8B chat model still misread the retrieved text
  on some questions. Use a larger model when answers matter, and show the
  retrieved sources to the user.
- **Store the index.** This program re-embeds the documents on every run. A
  real app stores the vectors, for example in SQLite; the
  [basic app example](../examples/basic-app) includes a sqlite-vector search.
- **Runtime support.** Embeddings run on llama.cpp (native and web). LiteRT-LM
  models do not provide embeddings. See [Embeddings](../guides/embeddings).
