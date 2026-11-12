import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

import 'support/model_downloads.dart';

Future<void> main() async {
  final modelPath =
      Platform.environment['LLAMADART_MODEL_SOURCE'] ??
      Platform.environment['LLAMADART_MODEL_PATH'];
  final inputText =
      Platform.environment['LLAMADART_EMBED_TEXT'] ??
      'hello world from genkit_llamadart';

  final prepared = await llamaDart.prepareModel(
    name: 'local-embed',
    downloadManager: exampleDownloads,
    source: ModelSource.parse(
      modelPath ??
          'hf://second-state/jina-embeddings-v2-small-en-GGUF/jina-embeddings-v2-small-en-Q2_K.gguf?revision=ce1d7885a6c52267f47f4793bc312ae5f71e8aca',
    ),
    modelParams: const ModelParams(contextSize: 512, device: ComputeDevice.cpu),
    supportsTools: false,
    supportsConstrainedOutput: false,
  );
  final ai = prepared.createGenkit();

  try {
    final embeddings = await ai.embed(
      embedder: llamaDart.embedder('local-embed'),
      document: DocumentData(
        content: <Part>[TextPart(text: inputText)],
        metadata: <String, dynamic>{'source': 'example'},
      ),
      options: const LlamaDartEmbedConfig(normalize: true),
    );

    final vector = embeddings.single.embedding;
    stdout.writeln('Input: $inputText');
    stdout.writeln('Dimensions: ${vector.length}');
    stdout.writeln(
      'First values: ${vector.take(8).map((v) => v.toStringAsFixed(4)).join(', ')}',
    );
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
