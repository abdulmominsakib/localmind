---
name: llamadart-embeddings
description: >-
  Use when generating text or multimodal embeddings with llamadart (engine.embed,
  engine.embedBatch, engine.embedContent, engine.embedContentBatch,
  LlamaEmbeddingInput, embeddingCapabilities), embedding images or audio with
  EmbeddingGemma-2 or a LiteRT-LM embedding bundle, ranking documents by cosine
  similarity, cross-encoder reranking with LlamaReranker, building a local retrieval-augmented generation (RAG) loop, storing
  vectors, or tuning ModelParams batch sizes and input length limits for embedding
  models.
---

# Embeddings and retrieval with llamadart

With a llama.cpp runtime older than ggml `0.28.0` (llamadart-native
`v0.8.0`), native Android Vulkan Qwen3.5 (`general.architecture=qwen35`) on a
GPU with a subgroup size below 32 other than 8 permits only ordinary text with
`microBatchSize` unset or `1..8`; media, speculation and embeddings are typed
unsupported (#948). The bundled runtime lifts this. Probe loaded-model
modalities and speculative strategies before offering them.

## Guidelines

- For cross-encoder reranking, use a separate loaded rank-pooled GGUF engine and
  `LlamaReranker(engine)` for an already rank-pooled context, or own a model with
  `await LlamaReranker.load(model, params: ...)`. The owning loader verifies a
  classifier tensor/count before selecting RANK for BERT/Jina files missing
  rank metadata; it rejects LoRA/projector inputs. `dispose()` frees an owned
  engine and leaves a borrowed one alive. Probe `await reranker.capabilities`; only native
  llama.cpp is supported, and ordinary embeddings/chat models are rejected.
  Call `reranker.rerank(query, documents, topN: 5)` and use each result's original
  `index` to select the candidate. All native class scores and nullable labels
  are retained. Default `scoreIndex: 0` matches llama-server; explicitly select
  another label's index if needed. Never infer a positive class or normalize:
  Qwen3 returns probabilities while other rerankers can return raw scores.
  Complete framed pairs must fit the probed context/batch/micro-batch limit;
  overflow rejects the whole request before inference. Increase those load
  limits to fit input and set `maxParallelSequences` above one for independent
  sequence batching. `topN` does not reduce scoring compute. Cancellation via
  `reranker.cancel()` affects the borrowed engine and waits for a native pass;
  await operations before model changes, then dispose the owning helper or
  the caller-owned engine.

- For a known EmbeddingGemma-2 model, opt into `LlamaTextEmbedder` with
  `profile: LlamaEmbeddingProfile.embeddingGemma2` and common query/corpus
  `dimensions` of 768 (default), 512, 256 or 128. Pass
  `LlamaEmbeddingText.query(text, task: LlamaEmbeddingTask.search)`,
  `.document(text, title: title)` or `.prepared(alreadyFormattedText)`.
  Documents use `title: none | text: ...` without a title; queries use
  `task: search result | query: ...`. Prepared text is always verbatim.
  The profile is a caller assertion, not model auto-detection or quantization
  qualification. It validates full 768-wide finite vectors, truncates first,
  then L2-normalizes. A zero retained vector fails normalization; with
  `normalize: false`, finite zero output is preserved. The default raw profile
  accepts prepared inputs only and forbids dimensions. Existing engine methods
  retain their defaults and media receives no automatic prefix. Never infer
  compatibility from a vector's width. Re-index when dimensions/profile/model
  change; this helper does not own or dispose its engine.
- Use `engine.embed(text)` for one vector and `engine.embedBatch(texts)` for
  many; both return `List<double>` vectors (one per input, in input order) and
  take `normalize` (default `true`, L2-normalized). With normalized vectors,
  cosine similarity is the dot product. Pass `normalize: false` only when you
  need raw vectors, and then compute full cosine similarity.
- `LlamaEmbeddingInput` and `embedContent` / `embedContentBatch` accept ordered
  text/image/audio content parts. Probe `await engine.embeddingCapabilities`
  after loading: native llama.cpp v0.7.0-1 supports EmbeddingGemma-2 image/audio
  embeddings with its matching projector (BF16 qualified on CPU on macOS,
  Linux x64, Windows x64, Android and iOS, plus macOS Metal), and reports text
  only without one. Web llama.cpp probes image/audio embeddings
  through the bridge's embedding API (pinned assets include it) and a
  compatible model/projector. EmbeddingGemma-2 vectors are qualified on Chrome CPU wasm memory64 against
  native CPU/Metal; repeated media batches are qualified only on memory64
  (wasm32 is unqualified). Hardware WebGPU is unqualified. Image bytes are encoded; width/height are ignored. LiteRT-LM
  embedding engines probe text/image/audio on native CPU. Native llama.cpp
  expanded inputs must fit one context/batch/micro-batch; no chunking or implicit
  task prefixes. M-RoPE projectors and image URLs are unsupported. Use exactly
  one media source per part: encoded bytes/local file or mono 16 kHz audio PCM.
  Text-only native and Web content follows `embed`, including causal unpooled models.
  Missing media symbols leave text available; native media errors name v0.7.0-1.
  Windows needs the complete native DLL bundle.
  `cancelGeneration()` cancels content calls even during capability checks,
  with `LlamaInferenceException` before inference. Web content calls also discard
  a late successful bridge result after cancellation. Await the future before reuse;
  later calls start independently. Native LiteRT-LM also checks after worker
  startup for content and string calls. Native llama.cpp and Web legacy string
  cancellation contracts are unchanged.
  Adjacent text parts form one verbatim-concatenated text segment on every
  backend, including within mixed inputs. Add no separators or task prefixes.
  The modality enum may gain values; include a default in switches.
  Video and chat-only parts are unsupported. Content observers retain only part kinds/counts.
- `LiteRtLmModelParams(embeddingEngine: true)` is the explicit LiteRT-LM
  embedding-engine selector. Select `ComputeDevice.cpu` on macOS, iOS or
  Android arm64, Linux x64 or arm64, or Windows x64. Native GPU, Android x86_64
  and all LiteRT-LM Web paths throw typed unsupported errors at load, whatever
  runtime library is loaded; use llama.cpp embeddings there. On Linux and
  Windows a custom runtime older than litert-lm-native v0.19.1-2 is refused
  the same way. Keep the
  default false for existing users; llama.cpp GGUF loaders reject true and use
  their existing per-call embedding mode.
- Load a dedicated embedding GGUF (for example
  `hf://ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf`). No
  special `ModelParams` flag is needed: the engine switches the context into
  embedding mode per call. Loading and disposal work as in the
  llamadart-getting-started skill.
- Native v0.7.0 supports EmbeddingGemma-2 text embeddings with 768-dimensional output.
- Give the embedding model and the chat model separate `LlamaEngine`s. An
  engine holds one model, and switching models per query reloads weights.
- LiteRT-LM requires an embedding bundle and the explicit selector above;
  conversation mode has no embeddings. Probe `await engine.embeddingCapabilities`
  before offering media. Use PNG/JPEG bytes, mono 16 kHz Float32 samples or
  mono 16 kHz PCM16/Float32 WAV bytes; paths/URLs and video are unsupported.
  Native CPU qualification covers macOS arm64, iOS arm64, Linux x64 and arm64,
  and Windows x64; Android arm64 is verified on a Galaxy S24 without SME and on
  arm64 emulators. Concurrent embeds queue;
  cancellation/unload/dispose settle the current item and discard all active and
  queued batches. A timeout discards only its own batch; other queued callers
  retain their own deadlines.
  Timeouts throw `LlamaInferenceException`. `contextSize` selects the encoder
  signature without truncation; conversation tuning options are rejected.
  Preflight checks modalities, sources and media decoding across the whole batch
  in a helper isolate.
  Without a token-count API, LiteRT-LM may detect overflow during computation;
  the whole call fails with `LlamaInferenceException` and no vectors. Earlier
  items can waste compute; never truncate or return partial results. Still treat
  `LlamaUnsupportedException` from `embed` as a configuration error, not
  something to retry or swallow.
- Rank-pooled reranker GGUFs (such as Qwen3-Reranker) produce classifier
  scores, not embeddings; `embed`/`embedBatch` throw
  `LlamaUnsupportedException` for them, as do encoder-decoder models such as
  T5. On Web, rerankers throw it too.
- Web embeddings need llama.cpp bridge assets with the embedding API (the
  pinned ones have it). When older assets lack it, calls throw
  `LlamaUnsupportedException`. Web throws
  `LlamaEmbeddingInputTooLongException` for input over the one-pass limit;
  other web embedding failures surface as `LlamaInferenceException`.
- Nothing is truncated for you. Native encoder-only, no-memory and
  non-causal models (BERT, ModernBERT, EmbeddingGemma), plus MEAN/CLS-pooled
  models even with a KV cache, need one micro-batch per input. Exceeding the
  context's actual micro-batch capacity throws
  `LlamaEmbeddingInputTooLongException` before decoding. It extends
  `LlamaInferenceException` and exposes `maxInputTokens` and, when known,
  `actualTokens`, including special tokens or expanded multimodal rows.
  Chunk documents into passages, measure with
  `engine.getTokenCount(text)`, or raise `microBatchSize` and `batchSize`
  together (and `contextSize` past its value). Causal LAST/unpooled models
  with memory retain chunked input support.
- Native diffusion capability and EmbeddingGemma's forced non-causal mode
  override attention metadata. Other models follow the pinned `v0.9.0`
  boolean attention metadata, whose absent key defaults to causal. Missing
  architecture, invalid metadata or a missing required runtime probe fails
  with `LlamaUnsupportedException` before decoding; use a compatible runtime.
- `embedBatch` runs true multi-sequence batches only when
  `ModelParams.maxParallelSequences` is greater than 1 (default `1`, which
  embeds inputs one at a time). Set it to the expected batch width (for
  example 4 or 8); llama.cpp keeps the full per-sequence context, and inputs
  that do not fit a logical batch fall back to single calls automatically.
  One-pass models still require each input and each grouped decode to fit
  the micro-batch capacity; a later invalid input is rejected before any
  earlier group is decoded.
- For throughput on a known workload, set `batchSize` and `microBatchSize`
  explicitly (for example 2048/2048 with `maxParallelSequences: 8`), starting
  with `microBatchSize: 512` on memory-constrained devices and measuring.
- Embed documents once and persist the vectors with the text and the model
  identity; vectors from different embedding models are not comparable, so
  re-index when the model changes. `embedBatch([])` returns an empty list.
- Keep retrieval results visible to users and bound the prompt: take the top
  few chunks, and budget them with `engine.getTokenCount` against the chat
  model's context. Generation itself (`engine.create`, streaming) is covered
  in the llamadart-chat-streaming skill.
- For larger corpora, store vectors in a database with a vector index instead
  of scanning a Dart list. The `example/basic_app` sqlite-vector demo stores
  `embed` output in SQLite via the `sqlite_vector` package and runs
  nearest-neighbour search there.

## Examples

Embed an EG2 query and titled document with the same output dimension:

```dart
import 'package:llamadart/llamadart.dart';

Future<List<List<double>>> embedEg2Retrieval(LlamaEngine engine) {
  final LlamaTextEmbedder embedder = LlamaTextEmbedder(
    engine,
    profile: LlamaEmbeddingProfile.embeddingGemma2,
    dimensions: 256,
  );
  return embedder.embedBatch(<LlamaEmbeddingText>[
    const LlamaEmbeddingText.query('What causes the northern lights?'),
    const LlamaEmbeddingText.document(
      'Charged particles from the Sun interact with atmospheric gases.',
      title: 'Aurora',
    ),
  ]);
}
```

Embed an image with its caption after probing the loaded model/runtime:

```dart
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<List<double>?> embedCaptionedImage(
  LlamaEngine embedder,
  String caption,
  String imagePath,
) async {
  final capabilities = await embedder.embeddingCapabilities;
  if (!capabilities.image) {
    print(capabilities.mediaUnsupportedReason);
    return null;
  }
  return embedder.embedContent(
    LlamaEmbeddingInput(<LlamaContentPart>[
      LlamaTextContent(caption),
      LlamaImageContent(bytes: await File(imagePath).readAsBytes()),
    ]),
  );
}
```

Index documents and rank them for a query:

```dart
import 'package:llamadart/llamadart.dart';

double dot(List<double> a, List<double> b) {
  double sum = 0;
  for (int i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

Future<List<({String text, double score})>> search(
  LlamaEngine embedder,
  List<String> documents,
  String query, {
  int topK = 3,
}) async {
  final List<List<double>> index = await embedder.embedBatch(documents);
  final List<double> queryVector = await embedder.embed(query);
  final List<({String text, double score})> ranked =
      <({String text, double score})>[
        for (int i = 0; i < documents.length; i++)
          (text: documents[i], score: dot(queryVector, index[i])),
      ]..sort((a, b) => b.score.compareTo(a.score));
  return ranked.take(topK).toList();
}

Future<void> main() async {
  final LlamaEngine embedder = await LlamaEngine.load(
    LlamaModel(
      ModelSource.parse(
        'hf://ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf',
      ),
    ),
    params: const ModelParams(contextSize: 2048, maxParallelSequences: 8),
  );
  try {
    final List<({String text, double score})> hits = await search(
      embedder,
      <String>[
        'Increase maxParallelSequences for wider embedding batches.',
        'Tune batchSize and microBatchSize together.',
        'Use CPU fallback on constrained devices.',
      ],
      'How do I improve embedding throughput?',
    );
    for (final ({String text, double score}) hit in hits) {
      print('${hit.score.toStringAsFixed(3)}  ${hit.text}');
    }
  } on LlamaUnsupportedException catch (error) {
    print('This model or runtime cannot embed: ${error.message}');
  } finally {
    await embedder.dispose();
  }
}
```

Answer a question grounded in retrieved chunks (two engines):

```dart
import 'package:llamadart/llamadart.dart';

Future<String> answer({
  required LlamaEngine embedder,
  required LlamaEngine generator,
  required List<String> chunks,
  required List<List<double>> chunkVectors,
  required String question,
}) async {
  final List<double> query = await embedder.embed(question);
  final List<int> order = List<int>.generate(chunks.length, (int i) => i)
    ..sort((int a, int b) {
      double scoreA = 0;
      double scoreB = 0;
      for (int d = 0; d < query.length; d++) {
        scoreA += query[d] * chunkVectors[a][d];
        scoreB += query[d] * chunkVectors[b][d];
      }
      return scoreB.compareTo(scoreA);
    });
  final String context = order.take(2).map((int i) => '- ${chunks[i]}').join(
    '\n',
  );

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

  return generator
      .create(
        messages,
        params: const GenerationParams(maxTokens: 128, temp: 0.2),
        enableThinking: false,
      )
      .text();
}
```

Split long text into passages that fit one embedding pass:

```dart
import 'package:llamadart/llamadart.dart';

Future<List<String>> chunkByTokens(
  LlamaEngine embedder,
  String text, {
  int maxTokens = 400,
}) async {
  final List<String> chunks = <String>[];
  final StringBuffer current = StringBuffer();
  for (final String paragraph in text.split(RegExp(r'\n\s*\n'))) {
    final String candidate = current.isEmpty
        ? paragraph
        : '$current\n\n$paragraph';
    if (current.isNotEmpty &&
        await embedder.getTokenCount(candidate) > maxTokens) {
      chunks.add(current.toString());
      current
        ..clear()
        ..write(paragraph);
    } else {
      current
        ..clear()
        ..write(candidate);
    }
  }
  if (current.isNotEmpty) chunks.add(current.toString());
  return chunks;
}
```

A single paragraph longer than `maxTokens` still needs splitting (for example
by sentence) before `embed`, or native llama.cpp (and Web for one-pass models) throws
`LlamaEmbeddingInputTooLongException`. Other runtimes may report
`LlamaInferenceException` without structured counts.

## More

- Embeddings: https://llamadart.leehack.com/docs/guides/embeddings
- Retrieval (RAG) tutorial: https://llamadart.leehack.com/docs/tutorials/rag
- Basic app example (sqlite-vector search): https://llamadart.leehack.com/docs/examples/basic-app
- Performance tuning: https://llamadart.leehack.com/docs/guides/performance-tuning
