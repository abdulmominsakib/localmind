import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main() async {
  final source = const String.fromEnvironment(
    'LLAMADART_MODEL_SOURCE',
    defaultValue:
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf?revision=9e6855bc4be717fca1ef21360a1db4b29d5c559a',
  );
  final cacheDirectory = const String.fromEnvironment(
    'LLAMADART_MODEL_CACHE',
    defaultValue: '',
  );
  final modelSource = ModelSource.parse(source);

  final task = llamaDart.prepareModelTask(
    name: 'observable-chat',
    source: modelSource,
    modelParams: const ModelParams(
      contextSize: 4096,
      device: ComputeDevice.cpu,
    ),
    options: ModelLoadOptions(
      cachePolicy: ModelCachePolicy.preferCached,
      cacheDirectory: cacheDirectory.isEmpty ? null : cacheDirectory,
    ),
    supportsEmbeddings: false,
    supportsConstrainedOutput: !_isLiteRtLmSource(modelSource),
  );

  final subscription = task.snapshots.listen((snapshot) {
    final fraction = snapshot.fraction == null
        ? ''
        : ' ${(snapshot.fraction! * 100).toStringAsFixed(1)}%';
    final sourceRole = snapshot.sourceRole == null
        ? ''
        : ' ${snapshot.sourceRole!.name}';
    print('${snapshot.stage.name}$sourceRole$fraction');
  });

  LlamaPreparedModel? prepared;
  Genkit? ai;
  try {
    prepared = await task.result;
    ai = prepared.createGenkit();

    await prepared.warmUp(
      ai,
      systemPrompt: 'Use terse answers.',
      prompt: 'Reply with one token: ready',
    );

    final response = await ai.generate(
      model: prepared.modelRef,
      prompt: 'Say hello in one sentence.',
      config: const LlamaDartGenerationConfig(
        maxTokens: 32,
        temperature: 0.0,
        enableThinking: false,
      ),
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Generation did not complete.');
    }
    print(response.text);
  } finally {
    try {
      await subscription.cancel();
    } finally {
      try {
        await task.dispose();
      } finally {
        try {
          await prepared?.dispose();
        } finally {
          await ai?.shutdown();
        }
      }
    }
  }
}

bool _isLiteRtLmSource(ModelSource source) {
  return source.fileName.split('?').first.toLowerCase().endsWith('.litertlm');
}
