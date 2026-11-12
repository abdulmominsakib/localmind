import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';

import 'support/model_downloads.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Supply a base GGUF source and its compatible ordinary LoRA GGUF source (path, hf:// or HTTPS).',
    );
  }
  final basePath = await resolveExampleModel(args[0]);
  final adapterPath = await resolveExampleModel(args[1]);
  final pool = LlamaDartRuntimePool(
    model: LlamaModelDefinition(
      name: 'lora',
      modelPath: basePath,
      modelParams: const ModelParams(
        contextSize: 512,
        device: ComputeDevice.cpu,
      ),
    ),
    maxOwners: 1,
  );
  final ai = Genkit(isDevEnv: false);
  try {
    final owner = await pool.open();
    final adapt = ai.defineFlow<String, String, void, void>(
      name: 'adaptedCompletion',
      inputSchema: SchemanticType.string(minLength: 1),
      outputSchema: SchemanticType.string(),
      fn: (prompt, context) => owner.generate(
        prompt,
        params: const GenerationParams(maxTokens: 32, temp: 0),
        cancellation: context.cancel,
      ),
    );
    // Resolve with the same cache policy, then apply without reloading the base.
    await owner.setLoraSource(ModelSource.path(adapterPath), scale: 0.5);
    print('With adapter: ${await adapt('Once upon a time')}');
    await owner.clearLoras();
    print('Base model: ${await adapt('Once upon a time')}');
  } finally {
    try {
      await pool.close();
    } finally {
      await ai.shutdown();
    }
  }
}
