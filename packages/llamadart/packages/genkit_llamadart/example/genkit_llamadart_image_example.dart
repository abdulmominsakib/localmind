import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;

Future<void> main(List<String> args) async {
  if (args.length != 1 && args.length != 2) {
    throw ArgumentError(
      'Supply a PNG output path, optionally followed by an SDXS model source (path, hf:// or HTTPS).',
    );
  }
  final engine = await llama.ImageGenerationEngine.load(
    llama.ImageGenerationModel(
      args.length == 2
          ? ModelSource.parse(args[1])
          : ModelSource.huggingFace(
              repoId: 'concedo/sdxs-512-tinySDdistilled-GGUF',
              revision: '3144d898d61492f8382ffcabec055733fc5b2a0e',
              filePath: 'sdxs-512-tinySDdistilled_Q8_0.gguf',
            ),
    ),
    params: const llama.ImageModelParams(device: ComputeDevice.cpu),
  );
  final plugin = LlamaDartMediaPlugin(
    models: [
      LlamaDartImageModel(name: 'image', engine: engine, ownsEngine: true),
    ],
  );
  final ai = Genkit(plugins: [plugin]);
  try {
    final response = await ai.generate(
      model: LlamaDartMediaPlugin.modelRef('image'),
      prompt: 'A red apple on a plain blue background.',
      config: {
        'width': 256,
        'height': 256,
        'steps': 1,
        'guidanceScale': 1,
        'seed': 42,
        'sampler': 'eulerAncestral',
        'scheduler': 'discrete',
      },
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Image generation did not complete.');
    }
    await File(
      args[0],
    ).writeAsBytes(UriData.parse(response.media!.url).contentAsBytes());
    print('Saved PNG.');
  } finally {
    try {
      await plugin.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
