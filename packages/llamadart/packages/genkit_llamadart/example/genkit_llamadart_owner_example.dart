import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';

import 'support/model_downloads.dart';

/// Runs an application-owned raw completion through a typed Genkit flow.
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
      modelParams: const ModelParams(
        device: ComputeDevice.cpu,
        contextSize: 1024,
      ),
    ),
    maxOwners: 1,
  );
  final ai = Genkit(isDevEnv: false);
  try {
    final owner = await pool.open();
    final complete = ai.defineFlow<String, String, void, void>(
      name: 'ownedCompletion',
      inputSchema: SchemanticType.string(minLength: 1),
      outputSchema: SchemanticType.string(),
      fn: (prompt, context) => owner.generate(
        prompt,
        params: const GenerationParams(maxTokens: 32, temp: 0),
        cancellation: context.cancel,
      ),
    );
    print(await complete('Once upon a time'));
  } finally {
    try {
      await pool.close();
    } finally {
      await ai.shutdown();
    }
  }
}
