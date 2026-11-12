import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

import 'support/model_downloads.dart';

/// Embeds ordered text/image/audio, downloading a pinned embedding model once.
///
/// GGUF: `dart run example/genkit_llamadart_multimodal_embedding_example.dart IMAGE AUDIO`
/// LiteRT CPU: add `--litert` before IMAGE AUDIO (no projector).
/// To override weights, prepend MODEL PROJECTOR (GGUF), or MODEL (LiteRT).
Future<void> main(List<String> args) async {
  final liteRt = args.isNotEmpty && args.first == '--litert';
  final paths = liteRt ? args.skip(1).toList() : args;
  if (paths.length != 2 && paths.length != (liteRt ? 3 : 4)) {
    throw ArgumentError(
      'Supply IMAGE AUDIO, optionally preceded by --litert and/or model sources.',
    );
  }
  final hasModelOverrides = paths.length > 2;
  const ggufSource =
      'hf://ggml-org/embeddinggemma-2-GGUF/embeddinggemma-2-BF16.gguf?revision=bfcd298762cc34d0357ece5ebdd31791a3a374d8';
  const projectorSource =
      'hf://ggml-org/embeddinggemma-2-GGUF/mmproj-embeddinggemma-2-BF16.gguf?revision=bfcd298762cc34d0357ece5ebdd31791a3a374d8';
  const liteRtSource =
      'hf://litert-community/embeddinggemma-2-740m-litert-lm/embeddinggemma-2-740m.litertlm?revision=24d962e906c7d332c6428e71c9676855024569e2';
  final prepared = await llamaDart.prepareModel(
    name: 'media-embed',
    source: ModelSource.parse(
      hasModelOverrides
          ? paths[0]
          : liteRt
          ? liteRtSource
          : ggufSource,
    ),
    mmprojSource: liteRt
        ? null
        : ModelSource.parse(hasModelOverrides ? paths[1] : projectorSource),
    downloadManager: exampleDownloads,
    modelParams: liteRt
        ? const LiteRtLmModelParams(
            device: ComputeDevice.cpu,
            embeddingEngine: true,
            contextSize: 2048,
          )
        : const LlamaCppModelParams(
            device: ComputeDevice.cpu,
            contextSize: 2048,
            batchSize: 2048,
            microBatchSize: 2048,
          ),
    supportsTools: false,
    supportsConstrainedOutput: false,
  );
  final ai = prepared.createGenkit(isDevEnv: false);
  try {
    final inspection = await prepared.inspect();
    final modalities = inspection.embeddingCapabilities;
    if (modalities?.text != true ||
        modalities?.image != true ||
        modalities?.audio != true) {
      throw LlamaUnsupportedException(
        'This example needs text, image and audio embedding support.',
      );
    }
    // LiteRT embeddings require encoded bytes rather than unresolved file paths.
    Future<MediaPart> mediaFile(String path, String type) async => MediaPart(
      media: Media(
        url: UriData.fromBytes(
          await File(path).readAsBytes(),
          mimeType: type,
        ).toString(),
        contentType: type,
      ),
    );
    final result = await ai.embed(
      embedder: llamaDart.embedder('media-embed'),
      document: DocumentData(
        content: [
          TextPart(text: 'Compare this scene '),
          await mediaFile(paths[paths.length - 2], 'image/png'),
          TextPart(text: ' with this sound '),
          await mediaFile(paths.last, 'audio/wav'),
        ],
        metadata: {'id': 'scene-and-sound'},
      ),
      options: const LlamaDartEmbedConfig(normalize: true),
    );
    stdout.writeln('Dimensions: ${result.single.embedding.length}');
    stdout.writeln('Source: ${result.single.metadata?['id']}');
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
