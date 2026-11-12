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
  const revision = '928ab958557df9aa2ef1c93e0e83c7ad0933fae2';
  final engine = await llama.SpeechToTextEngine.load(
    llama.SpeechToTextModel(
      args.length == 3
          ? ModelSource.parse(args[1])
          : ModelSource.huggingFace(
              repoId: 'ggml-org/Qwen3-ASR-0.6B-GGUF',
              revision: revision,
              filePath: 'Qwen3-ASR-0.6B-Q8_0.gguf',
            ),
      projector: args.length == 3
          ? ModelSource.parse(args[2])
          : ModelSource.huggingFace(
              repoId: 'ggml-org/Qwen3-ASR-0.6B-GGUF',
              revision: revision,
              filePath: 'mmproj-Qwen3-ASR-0.6B-Q8_0.gguf',
            ),
      adapter: const llama.Qwen3AsrAdapter(),
    ),
    params: const ModelParams(contextSize: 4096, device: ComputeDevice.cpu),
  );
  final plugin = LlamaDartMediaPlugin(
    models: [
      LlamaDartSpeechToTextModel(
        name: 'transcription',
        engine: engine,
        ownsEngine: true,
      ),
    ],
  );
  final ai = Genkit(plugins: [plugin]);
  try {
    final response = await ai.generate(
      model: LlamaDartMediaPlugin.modelRef('transcription'),
      messages: [
        Message(
          role: Role.user,
          content: [
            MediaPart(
              media: Media(
                url: File(args[0]).absolute.uri.toString(),
                contentType: 'audio/wav',
              ),
            ),
          ],
        ),
      ],
      config: {'maxOutputTokens': 256},
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Media generation did not complete.');
    }
    print(response.text);
  } finally {
    try {
      await plugin.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
