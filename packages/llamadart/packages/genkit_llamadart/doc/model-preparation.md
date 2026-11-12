# Model preparation

## Choosing a model

Pass an existing local path with `LlamaModelDefinition(modelPath: ...)`, or let
`llamaDart.prepareModel(...)` resolve a local, HTTP(S), or Hugging Face
`ModelSource` into the package-managed cache. Good places to find models:

- [`llamadart` documentation](https://llamadart.leehack.com/)
- [Hugging Face GGUF search](https://huggingface.co/models?search=gguf)
- [LiteRT community models](https://huggingface.co/litert-community) for
  `.litertlm` bundles, on `llamadart` targets that support LiteRT-LM

What to look for:

- chat and agents: an instruct or chat GGUF model
- LiteRT-LM chat on supported targets: a `.litertlm` bundle such as Gemma 4 E2B
- embeddings: an embedding GGUF model
- multimodal input: a vision-capable GGUF model and, when required, a matching
  `mmproj` file

Before downloading a model, check its model card for:

- quantization level and expected RAM or CPU requirements
- chat template or instruct formatting
- context length
- whether tool calling or JSON-style output works well
- whether a separate projector file is required for image input

For tiny CPU-friendly smoke-test models, use
`hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf` for
chat and
`hf://second-state/jina-embeddings-v2-small-en-GGUF/jina-embeddings-v2-small-en-Q2_K.gguf`
for embeddings.

## Downloading and caching

If your app does not already manage model files itself, use
`llamaDart.prepareModel(...)` with `llamadart`'s `ModelSource` and
package-managed cache/download options. The helper resolves the source to a
local file, builds the normal `LlamaModelDefinition`, and returns a plugin plus
typed model/embedder refs for standard Genkit calls.

```dart
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
    supportsEmbeddings: false,
  );

  final ai = prepared.createGenkit();
  try {
    final response = await ai.generate(
      model: prepared.modelRef,
      prompt: 'Say hello in one sentence.',
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Generation did not complete.');
    }
    print(response.text);
  } finally {
    await prepared.dispose();
    await ai.shutdown();
  }
}
```

Use this path for HTTP(S), Hugging Face, or local `ModelSource` values when you
want `llamadart` to own cache lookup, download, checksum verification, and
authenticated downloads. For reproducible Hugging Face downloads, use
`ModelSource.huggingFace(..., revision: commit)` or
`ModelSource.parse('hf://owner/repo@commit/file.gguf')`.
Supply `sha256` when you have a trusted checksum,
and `bearerToken` or `headers` for private remote sources; keep credentials out
of logs and source control. Keep constructing `LlamaModelDefinition` manually
when your application already has a local filesystem path and owns all download
or cache policy itself.

For multimodal models, pass `mmprojSource` and optional `mmprojOptions`; the
resolved projector file path is wired into `LlamaModelDefinition.mmprojPath`.
Local `ModelSource.path(...)` values use `llamadart`'s local-path semantics:
remote-only options such as cache policy overrides, cache directories, bearer
tokens, headers, resume, and retry settings are rejected instead of silently
ignored.

## LiteRT model settings

`ModelFormat` and `LiteRtLmActivationDataType` are available from the adapter
import for source and model configuration. Prepared native models load the
resolved local file and detect its format from the contents. Activation data types
apply to LiteRT-LM and must be supported by the selected bundle and device:

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main() async {
  final prepared = await llamaDart.prepareModel(
    name: 'litert-chat',
    source: ModelSource.path('/models/chat.litertlm', format: ModelFormat.liteRtLm),
    modelParams: const LiteRtLmModelParams(
      device: ComputeDevice.cpu,
      activationDataType: LiteRtLmActivationDataType.float32,
    ),
    supportsEmbeddings: false,
    supportsConstrainedOutput: false,
  );
  final ai = prepared.createGenkit();
  try {
    final response = await ai.generate(model: prepared.modelRef, prompt: 'Hello');
    if (response.finishReason == FinishReason.failed) {
      throw response.cause ?? StateError('Generation failed.');
    }
    print(response.text);
  } finally {
    await prepared.dispose();
    await ai.shutdown();
  }
}
```

## Progress, cancellation and warm-up

Flutter and other client apps can use `prepareModelTask(...)` when they need
deterministic loading UI for source resolution, cache checks, downloads,
verification, Genkit setup, failures, and cancellation.

```dart
import 'package:genkit/genkit.dart';

import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main() async {
  final task = llamaDart.prepareModelTask(
    name: 'local-chat',
    source: ModelSource.parse(
      'hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf',
    ),
    modelParams: const ModelParams(contextSize: 4096),
    options: ModelLoadOptions(
      cachePolicy: ModelCachePolicy.preferCached,
      cacheDirectory: '/path/to/app/model-cache',
    ),
    supportsEmbeddings: false,
  );

  final subscription = task.snapshots.listen((snapshot) {
    final stage = snapshot.stage;
    final fraction = snapshot.fraction;
    final modelPath = snapshot.modelEntry?.filePath;
    final errorText = snapshot.errorMessage;
    print('$stage ${fraction ?? '-'} ${modelPath ?? errorText ?? ''}');
  });

  LlamaPreparedModel? prepared;
  Genkit? ai;
  try {
    prepared = await task.result;
    ai = prepared.createGenkit();

    await prepared.warmUp(
      ai,
      systemPrompt: 'Use terse, app-friendly answers.',
      prompt: 'Reply with one token: ready',
      config: const LlamaDartGenerationConfig(
        maxTokens: 1,
        temperature: 0.0,
        enableThinking: false,
      ),
    );

    final response = await ai.generate(
      model: prepared.modelRef,
      prompt: 'Say hello in one sentence.',
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Generation did not complete.');
    }
    print(response.text);
  } finally {
    await subscription.cancel();
    await task.dispose();
    if (prepared != null) {
      await prepared.dispose();
    }
    if (ai != null) {
      await ai.shutdown();
    }
  }
}
```

Call `task.cancel()` to request cooperative cancellation while preparation is in
flight. Disposing the task closes snapshot resources; disposing the returned
`LlamaPreparedModel` releases plugin/runtime resources owned by this package.
`prepared.createGenkit()` is a convenience for registering the plugin, but the
returned `Genkit` instance remains caller-owned and should still be shut down by
the app.

## UI and server apps

Prepare the model once, register `prepared.plugin` in Genkit and pass
`prepared.modelRef` through your UI or server adapter. The same typed reference
works with ordinary `ai.generate()` and `ai.generateStream()` calls.

For progress UI, render `task.snapshot` initially and subscribe to
`task.snapshots` for subsequent changes. `loading` means plugin setup; the native
model loads on the first request, `prepared.warmUp(ai)` or an explicit
[inspection/tokenization call](model-inspection.md).

For a long-lived server, reuse one plugin and Genkit instance across requests.
Stop accepting requests before disposing the plugin and shutting down Genkit.
HTTP routing, authentication and UI catalogs belong to the application.
