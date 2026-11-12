import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main(List<String> args) async {
  final prepared = await llamaDart.prepareModel(
    name: 'local-chat',
    source: ModelSource.parse(
      args.isEmpty
          ? 'hf://unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_K_M.gguf?revision=6ab461498e2023f6e3c1baea90a8f0fe38ab64d0'
          : args.single,
    ),
    modelParams: const ModelParams(
      contextSize: 4096,
      device: ComputeDevice.cpu,
    ),
  );
  final ai = prepared.createGenkit();
  const config = LlamaDartGenerationConfig(
    temperature: 1.0,
    topP: 1.0,
    topK: 20,
    penalty: 1.0,
    presencePenalty: 2.0,
    maxTokens: 128,
  );
  try {
    final response = await ai.generate(
      prompt: 'Say hello in one sentence.',
      config: config,
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Generation did not complete.');
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
