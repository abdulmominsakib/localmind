---
name: genkit-llamadart-getting-started
description: >-
  Use when running a local GGUF or LiteRT-LM model in a Genkit Dart app with
  genkit_llamadart: registering models with llamaDart(...) or
  llamaDart.prepareModel(...), calling ai.generate or ai.generateStream,
  embeddings, generation config, cancellation, failed or aborted responses,
  and disposing the plugin.
---

# Getting started with genkit_llamadart

## Guidelines

- Add `genkit` and `genkit_llamadart` (`dart pub add genkit genkit_llamadart`).
  Import `package:genkit_llamadart/genkit_llamadart.dart`; it re-exports the
  llamadart types this plugin needs (`ModelParams`, `ModelSource`,
  `ModelLoadOptions`, `ModelCachePolicy`, observers, exceptions). Native
  runtime setup and platform notes live at https://llamadart.leehack.com/.
- Register models in one of two ways:
  - The app already has a local file: `llamaDart(models: [LlamaModelDefinition(name: ..., modelPath: ...)])`,
    then `Genkit(plugins: [plugin])` and reference it with
    `llamaDart.model(name)`.
  - Resolve a local path, HTTP(S) URL or `hf://owner/repo/file.gguf` source
    through llamadart's cache: `await llamaDart.prepareModel(name: ..., source: ModelSource.parse(...))`.
    It returns a `LlamaPreparedModel` with `plugin`, `modelRef`, optional
    `embedderRef` and `createGenkit()`. Use `llamaDart.prepareModelTask(...)`
    instead when a UI needs progress snapshots and cancellation.
- Set the capability flags on every definition. `supportsEmbeddings`,
  `supportsTools` and `supportsConstrainedOutput` all default to `true`; set
  them to `false` for what the model should not serve (for example
  `supportsEmbeddings: false` for a chat model). Requests that use a disabled
  capability fail with `FAILED_PRECONDITION`.
- Definition flags grant permission; the loaded runtime must confirm support.
  Discovery never loads models and starts with false support booleans. Inspect
  `llamadartCapabilities.state` (`unloaded`, `unverified`, `verified`) and `ready`;
  request probes update cached support metadata while preserving model labels,
  schemas and annotations. Unsupported runtime features fail with
  `UNIMPLEMENTED`. Custom runtime factories need `LlamaRuntimeCapabilityProvider`
  for advanced requests; without it, only single-turn text is accepted.
- Native remote image/audio input requires an explicit `mediaResolver` on the
  plugin or preparation helper. `HttpLlamaDartMediaResolver` takes a caller-owned
  `http.Client` and mandatory destination policy; it bounds size/time/redirects,
  validates MIME headers and aborts on Genkit cancellation. No default fetcher
  or disk cache exists. Web image URLs retain existing runtime routing and Web
  remote audio remains unsupported. See `doc/usage.md#image-and-audio-input`.
- Set the context window with `modelParams: ModelParams(contextSize: ...)`.
  Tune a request with `LlamaDartGenerationConfig` (`temperature`, `topP`,
  `topK`, `minP`, `penalty`, `presencePenalty`, `maxTokens`, `stop`, `seed`, `enableThinking`,
  `parallelToolCalls`, `chatTemplateKwargs`). Defaults: temperature 0.8,
  maxTokens 4096, thinking off.
- Thinking budgets use `ThinkingBudget(maxTokens: ...)`, separate from
  `enableThinking`. Delimiters are resolved from the template for chat and JSON.
  `SpeculativeDecodingConfig` selects core strategies; the legacy-style boolean
  selects the backend default. Speculation cannot be combined with constrained
  JSON, active tools, media or thinking budgets. Never put draft download tokens
  or signed URLs into Genkit config: download first and use `ModelSource.path`.
- Native performance controls are `reusePromptPrefix`,
  `streamBatchTokenThreshold` and `streamBatchByteThreshold`; defaults stay
  true, 8 and 512. Overrides require confirmed runtime support. Discovery
  exposes `model.configSchema` and `llamadartCapabilities.generation` without
  loading a model. See [generation controls](../../doc/usage.md#generation-settings).
- `ModelFormat` and `LiteRtLmActivationDataType` are re-exported for source/load
  configuration; use `ComputeDevice` instead of deprecated device selectors.
- Stream with `ai.generateStream<Object?, LlamaDartGenerationConfig>(...)`:
  iterate the chunks for `chunk.text`, then `await stream.onResult` for the
  final response.
- Model and tool errors do not throw from `generate`: the response has
  `finishReason == FinishReason.failed`, and a cancel or exhausted `maxTurns`
  yields `FinishReason.aborted`. Check `finishReason`, then read
  `response.error` / `response.cause`, before using `text` or `output`.
- Cancel cooperatively by passing `cancel: controller.token` from a Genkit
  `CancellationController`. For a stop button, `plugin.cancelActiveGeneration(name)`
  or `prepared.cancelActiveGeneration()` requests cancellation of active generation or typed embedding;
  queued requests still run.
- Models load lazily on first use, and requests to the same model run one at a
  time. Call `prepared.warmUp(ai)` to load ahead of the first user request.
- Always `await plugin.dispose()` (or `prepared.dispose()`) and
  `await ai.shutdown()` in a `finally`. Disposal is terminal: create a new
  plugin instead of reusing one.
- Embeddings use `llamaDart.embedder(name)` with `ai.embed(...)`, need an
  embedding model with `supportsEmbeddings: true`,
  and accept ordered text/image/audio parts when embedding-specific probes allow
  them. Each document produces one vector and retains its metadata. GGUF media
  embeddings need the matching projector; native LiteRT-LM requires CPU and
  `LiteRtLmModelParams(embeddingEngine: true)`. Web LiteRT-LM is unsupported.
  Inspect `prepared.inspect()` / `plugin.inspectModel(name)` for
  `embeddingCapabilities`; never infer these from chat vision/audio flags.
  Media codecs/size limits remain runtime-specific; video is rejected.
  LiteRT embedding media requires encoded PNG/JPEG and WAV data URLs or
  resolver bytes; unresolved local paths/URLs are unsupported. Native remote
  inputs use the explicit application-owned media resolver.
  Custom text runtimes keep `embedBatch`; media needs `LlamaRuntimeEmbeddingProvider`.
- Direct embedder actions accept Genkit cancellation tokens; queued calls skip
  work. Embedding on modality-aware runtimes signals cancellation and drains before the queue
  advances; legacy custom text embedding drains without signalling the backend. Genkit 1.0
  `ai.embed()` has no cancellation argument.
- Final `usage` can include character/image/audio counts even when token counts
  are unavailable. Read individual token fields rather than treating a nonnull
  usage object as proof of token measurements. See [observability](../../doc/observability.md).
- Genkit retains output reasoning in history, but the adapter omits incoming
  reasoning from model prompts. Reasoning replay is not qualified.
- Opt-in same-process raw-prompt caches use `LlamaDartRuntimePool(enablePromptCache: true)`,
  `owner.cachePrompt` and `owner.generateFromCache`. Handles stay in one pool/process;
  only default native GGUF owners without projectors/LoRA are supported. No chat,
  RNG or cross-process checkpoint is implied. See `doc/prompt-caches.md`.
- Experimental `generateBidi` text sessions require the separate
  `package:genkit_llamadart/experimental.dart` import and `LlamaDartBidiPlugin`.
  Use `llamadart-bidi/<name>`, await one complete response before the next send,
  close/cancel sessions explicitly and dispose the plugin. Tools/media/history
  injection and Web/LiteRT are unsupported. See `doc/bidi-sessions.md`.
- Normalize approved resource/data input explicitly using the
  [application recipe](../../doc/resource-input.md); direct generic parts remain
  unsupported. The recipe belongs in user input, not system instructions.

Runnable examples use revision-pinned Hugging Face defaults where a suitable
model pair exists. Model overrides accept local paths, `hf://` and HTTPS;
owner/cache/bidi resolve sources before opening local runtimes. LoRA requires
an explicit compatible base/adapter pair. Media input/output paths remain local.
The [example index](../../example/README.md#what-is-verified) distinguishes static
analysis, actual CLI execution, cached-source proofs and optional engine tests.

## Examples

Register a local model file and stream a reply:

```dart
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main() async {
  final plugin = llamaDart(
    models: const <LlamaModelDefinition>[
      LlamaModelDefinition(
        name: 'local-chat',
        modelPath: '/models/chat.gguf',
        modelParams: ModelParams(contextSize: 8192),
        supportsEmbeddings: false,
      ),
    ],
  );
  final ai = Genkit(plugins: <LlamaDartPlugin>[plugin]);

  try {
    final stream = ai.generateStream<Object?, LlamaDartGenerationConfig>(
      model: llamaDart.model('local-chat'),
      prompt: 'Say hello in one short sentence.',
      config: const LlamaDartGenerationConfig(
        temperature: 0.2,
        maxTokens: 128,
        enableThinking: false,
      ),
    );
    await for (final chunk in stream) {
      stdout.write(chunk.text);
    }
    stdout.writeln();

    final response = await stream.onResult;
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      stderr.writeln('Generation stopped: ${response.error?.message}');
    }
  } finally {
    await plugin.dispose();
    await ai.shutdown();
  }
}
```

Download a model through llamadart's cache, warm it up, generate with a
timeout-driven cancel:

```dart
import 'dart:async';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main() async {
  final prepared = await llamaDart.prepareModel(
    name: 'local-chat',
    source: ModelSource.parse(
      'hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf',
    ),
    modelParams: const ModelParams(contextSize: 4096),
    options: ModelLoadOptions(
      cachePolicy: ModelCachePolicy.preferCached,
      cacheDirectory: '/path/to/app/model-cache',
    ),
    onModelProgress: (progress) => print(progress),
    supportsEmbeddings: false,
  );
  final ai = prepared.createGenkit();
  final cancellation = CancellationController();
  final timer = Timer(const Duration(seconds: 30), cancellation.cancel);

  try {
    await prepared.warmUp(ai);
    final response = await ai.generate(
      model: prepared.modelRef,
      prompt: 'Name three uses for an on-device model.',
      cancel: cancellation.token,
    );
    if (response.finishReason == FinishReason.aborted) {
      print('Cancelled.');
    } else if (response.finishReason == FinishReason.failed) {
      print('Failed: ${response.cause ?? response.error?.message}');
    } else {
      print(response.text);
    }
  } finally {
    timer.cancel();
    await prepared.dispose();
    await ai.shutdown();
  }
}
```

Embed text with an embedding model:

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<List<double>> embedText(String text) async {
  final plugin = llamaDart(
    models: const <LlamaModelDefinition>[
      LlamaModelDefinition(
        name: 'local-embed',
        modelPath: '/models/embed.gguf',
        supportsTools: false,
        supportsConstrainedOutput: false,
      ),
    ],
  );
  final ai = Genkit(plugins: <LlamaDartPlugin>[plugin]);

  try {
    final embeddings = await ai.embed(
      embedder: llamaDart.embedder('local-embed'),
      document: DocumentData(content: <Part>[TextPart(text: text)]),
      options: const LlamaDartEmbedConfig(normalize: true),
    );
    return embeddings.single.embedding;
  } finally {
    await plugin.dispose();
    await ai.shutdown();
  }
}
```

## More

- README (preparation tasks, multimodal input, observability, limitations):
  https://pub.dev/packages/genkit_llamadart
- llamadart runtime and platform setup: https://llamadart.leehack.com/
