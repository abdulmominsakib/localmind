import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

import 'support/model_downloads.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 && args.length != 3) {
    throw ArgumentError(
      'Supply IMAGE, or MODEL_SOURCE PROJECTOR_SOURCE IMAGE (paths, hf:// or HTTPS).',
    );
  }
  final prepared = await llamaDart.prepareModel(
    name: 'vision',
    source: ModelSource.parse(
      args.length == 3
          ? args[0]
          : 'hf://unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_K_M.gguf?revision=6ab461498e2023f6e3c1baea90a8f0fe38ab64d0',
    ),
    mmprojSource: ModelSource.parse(
      args.length == 3
          ? args[1]
          : 'hf://unsloth/Qwen3.5-0.8B-GGUF/mmproj-F16.gguf?revision=6ab461498e2023f6e3c1baea90a8f0fe38ab64d0',
    ),
    downloadManager: exampleDownloads,
    modelParams: const ModelParams(
      contextSize: 4096,
      device: ComputeDevice.cpu,
    ),
    supportsEmbeddings: false,
  );
  final ai = prepared.createGenkit();
  try {
    final response = await ai.generate(
      messages: [
        Message(
          role: Role.user,
          content: [
            TextPart(text: 'Describe this image in one sentence.'),
            MediaPart(
              media: Media(url: File(args.last).absolute.uri.toString()),
            ),
          ],
        ),
      ],
      config: const LlamaDartGenerationConfig(maxTokens: 128, temperature: 0),
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Image description did not complete.');
    }
    print(response.text);
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
