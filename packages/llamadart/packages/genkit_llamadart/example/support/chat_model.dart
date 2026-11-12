import 'dart:io';

import 'package:genkit_llamadart/genkit_llamadart.dart';

import 'model_downloads.dart';

/// Qwen3.5's nonthinking text settings; examples bound output to 256 tokens.
const LlamaDartGenerationConfig exampleChatConfig = LlamaDartGenerationConfig(
  temperature: 1,
  topP: 1,
  topK: 20,
  penalty: 1,
  presencePenalty: 2,
  maxTokens: 256,
);

/// Prepares a native CPU chat model, optionally overridden by a model source.
///
/// Without a source override, downloads pinned Qwen3.5-0.8B (533 MB).
/// `LLAMADART_MODEL_SOURCE` / `LLAMADART_MMPROJ_SOURCE` accept hf://, HTTPS or
/// local paths; the older *_PATH environment variables remain supported.
Future<LlamaPreparedModel> prepareExampleChat(
  String name, {
  Iterable<LlamaEngineObserver> observers = const [],
}) {
  final path =
      Platform.environment['LLAMADART_MODEL_SOURCE'] ??
      Platform.environment['LLAMADART_MODEL_PATH'];
  final projector =
      Platform.environment['LLAMADART_MMPROJ_SOURCE'] ??
      Platform.environment['LLAMADART_MMPROJ_PATH'];
  return llamaDart.prepareModel(
    name: name,
    observers: observers,
    downloadManager: exampleDownloads,
    source: ModelSource.parse(
      path ??
          'hf://unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_K_M.gguf?revision=6ab461498e2023f6e3c1baea90a8f0fe38ab64d0',
    ),
    mmprojSource: projector == null ? null : ModelSource.parse(projector),
    modelParams: const ModelParams(
      contextSize: 4096,
      device: ComputeDevice.cpu,
    ),
    supportsEmbeddings: false,
  );
}
