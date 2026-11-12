---
title: On-device text, image and audio embeddings
sidebar_label: Embeddings
description: Generate local text, image and audio embeddings with llamadart, probe modality support per backend, and build retrieval-style workflows.
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

## Ordered content inputs

`embed(String)` and `embedBatch(List<String>)` are unchanged. The additive
`LlamaEmbeddingInput` accepts a nonempty ordered list of `LlamaTextContent`,
`LlamaImageContent` and `LlamaAudioContent` parts. Use `embedContent(input)`
or `embedContentBatch(inputs)` for one vector per input. Adjacent text parts
form one verbatim-concatenated text segment on every backend, including within mixed inputs; no separator or task prefix is added. An empty
batch returns no vectors; an empty parts list throws `LlamaArgumentException`.

```dart
Future<List<double>> embedContentExample(LlamaEngine engine) async {
  final capabilities = await engine.embeddingCapabilities;
  if (!capabilities.text) {
    throw LlamaUnsupportedException('This loaded runtime cannot embed text.');
  }
  return engine.embedContent(
    LlamaEmbeddingInput([const LlamaTextContent('hello world')]),
  );
}
```

After loading a model and any projector, `await engine.embeddingCapabilities`
reports `text`, `image` and `audio`. Native llama.cpp probes the loaded pooling/
attention mode, mixed-batch ABI and projector encoders. EmbeddingGemma-2 with
its projector supports images/audio on native v0.7.0-1 (BF16 qualified on CPU on
macOS arm64, Linux x64, Windows x64, Android and iOS, and on macOS Metal; other
GPU backends unqualified); without a projector it reports text only. Web llama.cpp probes image/audio
embeddings with bridge assets v0.1.64+
and a compatible model/projector. The default pinned assets include the media API.
EmbeddingGemma-2 vectors are qualified on Chrome CPU wasm memory64 against
native CPU/Metal. Repeated media batches require memory64; hardware WebGPU is
unqualified. Image bytes are encoded data; embedding calls ignore width/height.
LiteRT-LM embedding engines probe text/image/audio processors on native CPU.
Native and Web text-only content follows `embed`, including causal unpooled models;
media gates do not restrict text. `mediaUnsupportedReason` on the capability
report explains native media requirements, including the v0.7.0-1 ABI when
an older override lacks the mixed-batch or input-width symbols.
Chat vision/audio support does not imply embedding support. Custom backends may implement the
optional `BackendMultimodalEmbeddings` SPI from `package:llamadart/backend.dart`
and positively probe each loaded model/runtime modality.

The modality enum may gain values such as video; include a default case in
switches. Video and chat-only parts throw `LlamaUnsupportedException`; a portable
video frame/timestamp sampling contract has not been defined. No media is
silently flattened into text. Source/codec support is runtime-specific;
embedding PCM uses mono 16 kHz Float32 samples. Keep media buffers unchanged
until the future settles. `normalize` and cancellation through
`cancelGeneration()` use the existing `LlamaInferenceException` cancellation
error. Content calls cancelled during capability checks fail before inference;
native LiteRT-LM also checks again after worker startup. Web content calls
discard late successful bridge results after cancellation; synchronous WASM
compute may still finish before the future throws. Await the future before
reuse; a later call starts independently. Native llama.cpp and Web legacy
string embedding cancellation contracts are unchanged. Content-call
observers receive only ordered part kinds/counts, with no text, paths, URLs
or media payloads; old string calls retain their existing text observations.

GGUF embeddings reuse the existing model and its `LlamaModel.projector` or
`loadMultimodalProjector` loading path. `LiteRtLmModelParams(embeddingEngine: true)`
selects the separate LiteRT-LM embedding engine. Use `ComputeDevice.cpu` on
macOS arm64, iOS arm64 or Android arm64 (verified on a Galaxy S24 without SME and on arm64 emulators). Native GPU, Linux, Windows, Android x86_64
and all LiteRT-LM Web paths throw `LlamaUnsupportedException` at load, before
native engine creation, whatever runtime library is loaded
([#1367](https://github.com/leehack/llamadart/issues/1367)). This flag
is LiteRT-LM-only: llama.cpp GGUF loaders reject true; the default false preserves
existing loading. The qualified bundle is EmbeddingGemma-2 740M; probe it rather
than inferring modality support from its name. Follow
[the multimodal tracker](https://github.com/leehack/llamadart/issues/1072);
[task-prefix and Matryoshka helpers](https://github.com/leehack/llamadart/issues/1126)
are explicit opt-in text operations described below.

### LiteRT-LM embedding engine

```dart
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

Future<List<double>> embedLiteRtImage(LlamaEngine engine, Uint8List png) async {
  await engine.setModel(
    LlamaModel(ModelSource.path('embeddinggemma-2-740m.litertlm')),
    params: const LiteRtLmModelParams(
      embeddingEngine: true,
      device: ComputeDevice.cpu,
      contextSize: 1024,
    ),
  );
  return engine.embedContent(LlamaEmbeddingInput([LlamaImageContent(bytes: png)]));
}
```

LiteRT-LM Web embeddings remain unsupported: Web CPU cannot load external text-encoder
weights, and pinned WebGPU vectors missed the native CPU parity gate. Media inputs accept encoded PNG/JPEG bytes,
mono 16 kHz PCM16/Float32 WAV bytes, or mono 16 kHz Float32 samples. Paths,
image URLs, video and multiple sources per part are unsupported. All parts are
decoded before inference.
No task prefix is inserted. Embedding mode rejects generation and tokenizer APIs.

LiteRT-LM selects overflow-error behavior. It has no expanded-token count API,
so overflow may be discovered after earlier batch items consumed compute; the
whole call throws `LlamaInferenceException` and returns no vectors. It never
truncates or returns partial results. llama.cpp still validates actual expanded
context/batch/micro-batch capacity before inference.

## Native overflow errors

Native llama.cpp throws `LlamaEmbeddingInputTooLongException` when a complete
input exceeds its context or single-pass capacity. It remains an inference
exception for existing callers. The effective limit can be lower than the model
context because of batch, micro-batch or parallel-sequence settings. For mixed
inputs the counts are expanded rows; no prefix or media content appears in the
structured fields. Web bridge assets `v0.1.73+` throw it too when an input
exceeds the single-pass capacity. Other runtimes retain their existing
inference errors.

```dart
try {
  await engine.embed(text);
} on LlamaEmbeddingInputTooLongException catch (error) {
  print('Input needs ${error.actualTokens} tokens; limit ${error.maxInputTokens}.');
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
- On native and with Web bridge assets `v0.1.73+`, rank-pooled reranker
  GGUFs (such as Qwen3-Reranker) return classifier scores rather than
  embeddings, so `embed(...)` and `embedBatch(...)` throw
  `LlamaUnsupportedException` for them. Reranking is
  tracked in [#323](https://github.com/leehack/llamadart/issues/323).
- On native, encoder-decoder GGUFs (such as T5) throw
  `LlamaUnsupportedException`; use an encoder-only or decoder-only embedding
  model.
- On native, an input with more tokens than the context holds per sequence
  throws `LlamaEmbeddingInputTooLongException` (a `LlamaInferenceException`);
  shorten it or raise `contextSize`. The typed error reports `maxInputTokens`
  and `actualTokens`, including special tokens. With
  `kvUnified: false`, the context is split across `maxParallelSequences`.
- On native, encoder-only models, models without a KV cache, non-causal
  models and MEAN/CLS-pooled models embed each input in one pass. This also
  applies when the model has a KV cache. An input longer than the context's
  actual micro-batch capacity throws `LlamaInferenceException` before decoding;
  shorten the input or raise `microBatchSize` and `batchSize` together.
  Causal models with a KV cache retain chunked LAST or unpooled embedding
  support. Batched one-pass inputs are grouped only within the micro-batch
  capacity, and every input is validated before any group is decoded.
- Native causal-attention detection follows the pinned llama.cpp `v0.7.0`
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

## EmbeddingGemma-2 on native

Windows uses the complete native DLL bundle for media embeddings. Missing media
symbols disable media with a typed unsupported error and leave text embeddings
available. The BF16 model/projector pair is qualified on CPU on macOS arm64,
Linux x64, Windows x64, Android and iOS, and on macOS Metal; other GPU backends
are unqualified.

Native v0.7.0-1 loads the official EmbeddingGemma-2 BF16 GGUF through the existing
`embed` and `embedBatch` APIs. Its projected text output has 768 components;
its 512-wide hidden representation is not the returned vector size. The
local model-backed test covers normalization, distinct inputs, sequential/batch
parity and reuse on macOS CPU and Metal. Load the matching projector through
`LlamaModel.projector` to use `embedContent` with ordered images/audio/text.
Media-only inputs receive no implicit task prefix. Each input is decoded as
one complete mixed micro-batch; its expanded text/media rows must fit the
actual context, batch and micro-batch capacities. Oversized input throws
`LlamaInferenceException` before any input in the batch is encoded.
M-RoPE projectors and image URLs throw `LlamaUnsupportedException`. Use exactly
one source per media part: encoded bytes/local file, or mono 16 kHz audio PCM.
Cancellation settles the worker before releasing its media buffers; await the
embedding future before reuse or unload. Qualification details are in
[the native qualification procedure](https://github.com/leehack/llamadart/blob/main/doc/multimodal_embeddings_native.md).

For example, after downloading the matching model/projector and local media:

```dart
import 'package:llamadart/llamadart.dart';

Future<void> embedNativeMedia() async {
  final engine = await LlamaEngine.load(
    LlamaModel(
      ModelSource.path('embeddinggemma-2-BF16.gguf'),
      projector: ModelSource.path('mmproj-embeddinggemma-2-BF16.gguf'),
    ),
    params: const ModelParams(
      contextSize: 2048,
      batchSize: 2048,
      microBatchSize: 2048,
    ),
  );
  try {
    final capabilities = await engine.embeddingCapabilities;
    if (!capabilities.image || !capabilities.audio) {
      throw LlamaUnsupportedException('This model/runtime cannot embed media.');
    }
    final vector = await engine.embedContent(LlamaEmbeddingInput([
      const LlamaTextContent('A document with an image and audio.'),
      const LlamaImageContent(path: 'image.png'),
      const LlamaAudioContent(path: 'audio.wav'),
    ]));
    print(vector.length); // 768 for EmbeddingGemma-2.
  } finally {
    await engine.dispose();
  }
}
```

For document embeddings, pass the model's task prefix as part of the text:

```dart
final vector = await engine.embed(
  'title: none | text: Paris is the capital of France.',
);
```

Like other non-causal encoders, every input must fit in one micro-batch. Raise
`microBatchSize` and `batchSize` together for longer inputs. The runtime does
not automatically prepend task instructions.

## Text tasks, titles and Matryoshka dimensions

Use `LlamaTextEmbedder` with an explicit `embeddingGemma2` profile after loading
a compatible EG2 model. This is your assertion of model compatibility: the
helper checks output width and values, but does not authenticate the loaded
model or establish quantized-artifact quality. It does not change `LlamaEngine`
or automatically insert text into image/audio inputs.

```dart
Future<List<List<double>>> prepareRetrieval(LlamaEngine engine) async {
  final embedder = LlamaTextEmbedder(
    engine,
    profile: LlamaEmbeddingProfile.embeddingGemma2,
    dimensions: 256,
  );
  return embedder.embedBatch([
    const LlamaEmbeddingText.query('What is the capital of France?'),
    const LlamaEmbeddingText.document(
      'Paris is the capital of France.',
      title: 'France',
    ),
  ]);
}
```

Queries use `task: search result | query: ...`; documents use
`title: {title or none} | text: ...`. Select question answering, fact checking,
code retrieval, classification, clustering or sentence similarity through
`LlamaEmbeddingText.query(text, task: LlamaEmbeddingTask.questionAnswering)`.
Symmetric tasks use the same task on both sides. Text and supplied titles keep
their original whitespace. `LlamaEmbeddingText.prepared(text)` passes already
formatted text verbatim; prefix detection is deliberately absent.

The EG2 profile accepts 768 (default), 512, 256 or 128 components. It requests
the full raw 768-component vector, keeps its leading dimensions, and then
L2-normalizes by default. Query and corpus must use the same model/profile and
dimensions; changing any of them requires rebuilding the index. Invalid
dimensions or source width throw `LlamaUnsupportedException`. Nonfinite output
throws `LlamaInferenceException`; a zero retained vector also throws when
normalization is on. With `normalize: false`, finite zeros and unnormalized
leading components are preserved. Whole batches fail without partial output.

The default raw profile accepts only prepared text and delegates existing
normalization unchanged. It forbids model-specific formatting or dimension
reduction. Existing `engine.embed`, `embedBatch` and content methods keep their
defaults. The helper retains the underlying engine's cancellation/unsupported
contract and does not own or dispose it.

The text retrieval comparison uses the pinned official EG2 float32 reference
and BF16 GGUF CPU output at each dimension; see the
[qualification procedure](https://github.com/leehack/llamadart/blob/main/doc/embedding_text_helpers.md).
That evidence does not qualify quantized models, LiteRT bundles, media, GPU or
Web retrieval. Google recommends [renormalization after truncation](https://huggingface.co/google/embeddinggemma-2#best-practices)
and warns that 128 dimensions has a larger cost for multimodal quality.

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

### LiteRT-LM embedding lifecycle and options

Concurrent embedding calls queue. Whole-batch media decoding runs off the caller
isolate; native inference checks cancellation between items. Cancel, unload and
dispose discard all vectors after the current item settles and cancel queued
requests too. A timeout throws `LlamaInferenceException` and cancels only its own
request; other callers stay queued with their own deadlines. A timed-out queued
request never enters native inference. Reuse waits for any active native item to
settle.

`contextSize` selects the model's encoder signature without truncating inputs.
Embedding mode applies `numberOfThreads`, `cacheDir` and CPU selection;
LoRA, chat templates, activation type, prefill, parallel loading, dispatch paths,
program cache limits, MTP/rollback and Web memory hints throw
`LlamaUnsupportedException` before model I/O. Native CPU qualification is limited
to macOS arm64; GPU/NPU and Web embeddings remain unavailable.

## Cross-encoder reranking

Retrieve a candidate set with embeddings, then score query/document pairs with
a separate rank-pooled GGUF reranker. `LlamaReranker(engine)` borrows an already rank-pooled engine. For published
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

Native llama.cpp supports RANK-pooled models such as Qwen3-Reranker and Jina/BGE
rerankers. WebGPU and LiteRT-LM report unsupported. Ordinary embedding and chat
models are rejected; `embed` continues to reject classifier output.

Results sort descending, retain the original document `index`, and keep
`classifierScores` and nullable `classifierLabels` in model order. The default
`scoreIndex: 0` matches upstream llama-server. For another class, inspect the
labels and pass its index explicitly. No positive label is inferred. Qwen3
returns native softmax probabilities; other models can return unbounded raw
scores. No sigmoid, L2 normalization or further softmax is applied.

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

Ties preserve input order and duplicate documents retain separate indices.
`topN` limits results after all pairs are scored. Empty batches return no results
on a supported, loaded engine. Invalid score indices and negative `topN` throw
`LlamaArgumentException`. Call `reranker.cancel()` or `engine.cancelGeneration()`
to cancel this engine's inference; cancellation waits for its current native
pass before returning `LlamaInferenceException`. Await pending calls before
unloading or switching the engine's model, and always dispose the engine.

See the [CPU command-line example](https://github.com/leehack/llamadart/blob/main/example/basic_app/bin/llamadart_reranking_example.dart).
Real-model qualification uses the local-only `native-reranking` scenario and
the pinned upstream oracle described in `doc/native_reranking.md`. Its receipts
identify the model hashes, runtime revision and tested device/backend; native
API availability alone does not qualify every model, quantization or platform.
