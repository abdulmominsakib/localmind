---
name: genkit-llamadart-model-preparation
description: >-
  Use when a genkit_llamadart app downloads or caches its model: resolving
  local, HTTP(S) or hf:// ModelSource values with llamaDart.prepareModel or
  prepareModelTask, showing download progress in a loading screen, cancelling
  preparation, cache policies, checksums, private sources, multimodal
  projectors, LiteRT-LM bundles, and warming up the model.
---

# Model preparation with genkit_llamadart

## Guidelines

- Use `llamaDart.prepareModel(...)` or `llamaDart.prepareModelTask(...)` when
  the app should let llamadart own model files. Construct
  `LlamaModelDefinition(modelPath: ...)` directly only when the app already
  owns download and cache policy.
- Build sources with `ModelSource.parse(...)`: a local path, an HTTP(S) URL, or
  `hf://owner/repo/path/file.gguf`. Pin a Hugging Face revision with
  `hf://owner/repo@revision/file.gguf`, or use
  `ModelSource.huggingFace(repoId:, filePath:, revision:)`.
- Configure remote sources with `ModelLoadOptions`:
  - `cachePolicy`: `preferCached` (default), `refresh`, `cacheOnly` (fail when
    not cached, for offline mode) or `noCache`.
  - `cacheDirectory`: an app-owned directory, for example from
    `path_provider` in Flutter.
  - `sha256`: a 64-character hex digest; invalid digests throw
    `ArgumentError`.
  - `bearerToken` / `headers` for private sources, plus `resume` and
    `maxRetries`.
  Local path sources reject remote-only options instead of ignoring them.
  On web, URL-loading backends fetch models directly and reject options that
  need native cache IO (headers, checksums, cache policy changes).
- `prepareModel` returns a `Future<LlamaPreparedModel>`; pass
  `onModelProgress` for simple progress callbacks. Use `prepareModelTask` for
  a UI: it exposes `task.snapshots` (a stream), `task.snapshot` (the latest),
  `task.result`, `task.cancel()` and `task.dispose()`. The task starts on the
  next microtask, so subscribe right after creating it.
- Snapshot stages are `idle`, `resolving`, `checkingCache`, `downloading`,
  `verifying`, `loading`, `ready`, `failed` and `cancelled`. Use
  `snapshot.isRunning` for spinners, `snapshot.fraction` (null when unknown,
  `1.0` when ready) for progress bars, `snapshot.sourceRole` to tell model and
  `mmproj` downloads apart, and `snapshot.errorMessage` for failures; it has
  URLs and credentials redacted.
- `task.result` completes with an error on failure, cancellation or disposal.
  Always await it in `try`/`catch`.
- `ready` means files are resolved and the plugin is built; the native model
  still loads lazily on the first request, inspection or tokenization. Call
  `await prepared.warmUp(ai)` to load it behind the loading screen.
  `warmUp` throws on failure or cancellation.
- Ownership: `task.dispose()` closes snapshot resources; `prepared.dispose()`
  releases the runtime; `prepared.createGenkit()` returns a `Genkit` the app
  must `shutdown()`. Dispose all three when the screen or app closes.
- For llama.cpp image or audio input, pass `mmprojSource` (and `mmprojOptions`);
  the loaded projector must confirm support. Native LiteRT-LM can use built-in
  encoders without a projector; a custom runtime older than LiteRT-LM v0.18.0 can
  under-report media, so native media requests retain best-effort runtime
  validation.
- `.litertlm` LiteRT-LM bundles work for chat and tools where llamadart
  supports LiteRT-LM, but have no grammar constraints: prepare them with
  `supportsConstrainedOutput: false`.
- Set `supportsEmbeddings`, `supportsTools` and `supportsConstrainedOutput` to
  match the model; they all default to `true`.

For multimodal embeddings, load an embedding model, not a chat model. GGUF
requires the matching projector source. Native LiteRT-LM uses
`LiteRtLmModelParams(device: ComputeDevice.cpu, embeddingEngine: true)` and no
projector. LiteRT embedding inputs need PNG/JPEG and WAV bytes (data URLs or
resolved media), not unresolved file paths/URLs. Check `prepared.inspect()`'s `embeddingCapabilities` for each required
modality; chat vision/audio flags do not establish embedding support. Set
`supportsTools: false` and `supportsConstrainedOutput: false` for embedding-only
models. See [embedding usage](../../doc/usage.md#multimodal-embeddings).

## Examples

Prepare a model behind a loading screen with progress, cancel and warm-up.
Bind `state` into Flutter state (`ChangeNotifier`, Bloc, Riverpod) as needed:

```dart
import 'dart:async';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

class ModelLoader {
  ModelLoader(this.cacheDirectory);

  final String cacheDirectory;
  final StreamController<String> _state = StreamController<String>.broadcast();
  LlamaModelPreparationTask? _task;
  LlamaPreparedModel? prepared;
  Genkit? ai;

  Stream<String> get state => _state.stream;

  Future<bool> load() async {
    final task = llamaDart.prepareModelTask(
      name: 'local-chat',
      source: ModelSource.parse(
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf',
      ),
      modelParams: const ModelParams(contextSize: 4096),
      options: ModelLoadOptions(
        cachePolicy: ModelCachePolicy.preferCached,
        cacheDirectory: cacheDirectory,
      ),
      supportsEmbeddings: false,
    );
    _task = task;

    final subscription = task.snapshots.listen((snapshot) {
      final fraction = snapshot.fraction;
      final percent = fraction == null
          ? ''
          : ' ${(fraction * 100).toStringAsFixed(0)}%';
      _state.add(snapshot.errorMessage ?? '${snapshot.stage.name}$percent');
    });

    try {
      final model = await task.result;
      prepared = model;
      final genkit = model.createGenkit();
      ai = genkit;
      _state.add('warming up');
      await model.warmUp(genkit);
      _state.add('ready');
      return true;
    } catch (_) {
      return false;
    } finally {
      await subscription.cancel();
    }
  }

  void cancel() => _task?.cancel();

  Future<String> ask(String prompt) async {
    final response = await ai!.generate(
      model: prepared!.modelRef,
      prompt: prompt,
    );
    return response.text;
  }

  Future<void> dispose() async {
    await _task?.dispose();
    await prepared?.dispose();
    await ai?.shutdown();
    await _state.close();
  }
}
```

Prepare a private, checksum-verified vision model with its projector, or fail
fast when offline and nothing is cached:

```dart
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<LlamaPreparedModel> prepareVisionModel({
  required String cacheDirectory,
  required String modelSha256,
  required String? token,
  required bool offline,
}) {
  final cachePolicy = offline
      ? ModelCachePolicy.cacheOnly
      : ModelCachePolicy.preferCached;

  return llamaDart.prepareModel(
    name: 'local-vision',
    source: ModelSource.parse('hf://my-org/private-vlm@v1/model-Q4_K_M.gguf'),
    mmprojSource: ModelSource.parse('hf://my-org/private-vlm@v1/mmproj.gguf'),
    modelParams: const ModelParams(contextSize: 8192),
    options: ModelLoadOptions(
      cachePolicy: cachePolicy,
      cacheDirectory: cacheDirectory,
      sha256: modelSha256,
      bearerToken: token,
    ),
    mmprojOptions: ModelLoadOptions(
      cachePolicy: cachePolicy,
      cacheDirectory: cacheDirectory,
      bearerToken: token,
    ),
    onModelProgress: (progress) {
      print('model ${progress.receivedBytes}/${progress.totalBytes ?? '?'}');
    },
    supportsEmbeddings: false,
  );
}
```

## Inspect before inference

Call `prepared.inspect()` to explicitly load the prepared model without
inference, then read nullable `contextSize` and
`capabilities`. These report runtime measurements rather than requested load
settings. `prepared.countTokens(text)` and `prepared.tokenize(text)` count/encode
raw text, without adding tokenizer special tokens by default. `tokenize` accepts
`addSpecial: true` when needed. These calls share the generation queue and the
prepared plugin's disposal lifecycle.

Raw counts do not include chat-template overhead, tool schemas or media and
must not be presented as complete conversation budgets. Unsupported tokenizers
throw `LlamaUnsupportedException`; unknown context capacity remains null.
Web and LiteRT-LM actual context measurement is unavailable in this adapter. For direct
plugins use `inspectModel(name)`, `countTokens(name, text)` and
`tokenize(name, text)` instead. Registration and listing remain lazy.

## More

- Preparation task example:
  https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_preparation_task_example.dart
- Model sources, caching and platform limits:
  https://llamadart.leehack.com/
