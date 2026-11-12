import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;

Future<void> main(List<String> args) async {
  if (args.length != 1 && args.length != 3) {
    throw ArgumentError(
      'Supply a WAV path, optionally followed by model and projector sources (paths, hf:// or HTTPS).',
    );
  }
  const revision = 'ca27d74bc954b73dadab5b71ca265d87fc861a7c';
  final engine = await llama.TextToSpeechEngine.load(
    llama.TextToSpeechModel(
      args.length == 3
          ? ModelSource.parse(args[1])
          : ModelSource.huggingFace(
              repoId: 'ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF',
              revision: revision,
              filePath: 'Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf',
            ),
      projector: args.length == 3
          ? ModelSource.parse(args[2])
          : ModelSource.huggingFace(
              repoId: 'ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF',
              revision: revision,
              filePath: 'mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf',
            ),
      adapter: const llama.Qwen3TtsAdapter(),
    ),
    params: const ModelParams(contextSize: 4096, device: ComputeDevice.cpu),
  );
  final plugin = LlamaDartMediaPlugin(
    models: [
      LlamaDartTextToSpeechModel(
        name: 'speech',
        engine: engine,
        ownsEngine: true,
      ),
    ],
  );
  final ai = Genkit(plugins: [plugin]);
  try {
    final response = await ai.generate(
      model: LlamaDartMediaPlugin.modelRef('speech'),
      prompt: 'Hello from Genkit.',
      config: {'language': 'en', 'maxFrames': 384, 'seed': 1},
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Media generation did not complete.');
    }
    await File(
      args[0],
    ).writeAsBytes(UriData.parse(response.media!.url).contentAsBytes());
    print('Saved WAV.');
  } finally {
    try {
      await plugin.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
