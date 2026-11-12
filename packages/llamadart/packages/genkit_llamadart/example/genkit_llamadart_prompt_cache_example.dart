import 'package:genkit_llamadart/genkit_llamadart.dart';

import 'support/model_downloads.dart';

Future<void> main(List<String> args) async {
  if (args.length > 1) throw ArgumentError('Supply at most one model source.');
  final modelPath = await resolveExampleModel(
    args.firstOrNull ??
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf?revision=9e6855bc4be717fca1ef21360a1db4b29d5c559a',
  );
  final pool = LlamaDartRuntimePool(
    model: LlamaModelDefinition(
      name: 'raw',
      modelPath: modelPath,
      modelParams: const LlamaCppModelParams(
        device: ComputeDevice.cpu,
        contextSize: 512,
        numberOfThreads: 1,
        numberOfThreadsBatch: 1,
      ),
    ),
    enablePromptCache: true,
    maxOwners: 1,
    maxPromptCaches: 1,
  );
  try {
    final first = await pool.open();
    final cache = await first.cachePrompt(
      'Once upon a time, in a quiet village near the mountains',
    );
    await first.close();
    final replacement = await pool.open();
    print(
      await replacement.generateFromCache(
        cache,
        params: const GenerationParams(maxTokens: 16, temp: 0, seed: 42),
      ),
    );
    cache.dispose();
  } finally {
    await pool.close();
  }
}
