@Tags(['real-model', 'inference-controls'])
@TestOn('vm')
library;

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

void main() {
  ({Genkit ai, LlamaDartPlugin plugin}) setup(String path) {
    final plugin = llamaDart(
      models: [
        LlamaModelDefinition(
          name: 'controls',
          modelPath: path,
          supportsEmbeddings: false,
          modelParams: const ModelParams(
            contextSize: 4096,
            device: ComputeDevice.cpu,
          ),
        ),
      ],
    );
    final ai = Genkit(plugins: [plugin], isDevEnv: false);
    addTearDown(() async {
      await plugin.dispose();
      await ai.shutdown();
    });
    return (ai: ai, plugin: plugin);
  }

  test(
    'native prefix reuse, batching and ngram speculation preserve greedy text',
    () async {
      final path = await resolveIntegrationModelPath();
      if (path == null) return;
      final app = setup(path);
      final outputs = <String>[];
      for (final config in [
        const LlamaDartGenerationConfig(
          temperature: 0,
          seed: 42,
          maxTokens: 32,
          penalty: 1,
        ),
        const LlamaDartGenerationConfig(
          temperature: 0,
          seed: 42,
          maxTokens: 32,
          penalty: 1,
          reusePromptPrefix: false,
          streamBatchTokenThreshold: 1,
          streamBatchByteThreshold: 1,
        ),
        const LlamaDartGenerationConfig(
          temperature: 0,
          seed: 42,
          maxTokens: 32,
          penalty: 1,
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(
            ngramSizeN: 3,
            ngramSizeM: 4,
            ngramMinHits: 1,
          ),
        ),
      ]) {
        final timer = Stopwatch()..start();
        final stream = app.ai
            .generateStream<Object?, LlamaDartGenerationConfig>(
              model: llamaDart.model('controls'),
              prompt: 'Count from one to ten in words.',
              config: config,
            );
        var chunks = 0;
        await for (final _ in stream) {
          chunks++;
        }
        final result = await stream.onResult;
        expect(
          result.finishReason,
          isNot(FinishReason.failed),
          reason: '${result.error}',
        );
        expect(result.text, isNotEmpty);
        expect(chunks, greaterThan(0));
        outputs.add(result.text);
        print(
          'native controls: ${config.toJson()} elapsedMs=${timer.elapsedMilliseconds} chunks=$chunks output=${result.text}',
        );
      }
      expect(outputs[1], outputs[0]);
      expect(outputs[2], outputs[0]);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'Qwen3 thinking budget closes reasoning in chat and constrained JSON',
    () async {
      final path = await resolveIntegrationToolModelPath();
      if (path == null) return;
      final app = setup(path);
      const config = LlamaDartGenerationConfig(
        temperature: 0,
        seed: 42,
        maxTokens: 128,
        enableThinking: true,
        thinkingBudget: ThinkingBudget(maxTokens: 0),
      );
      final chat = await app.ai.generate(
        model: llamaDart.model('controls'),
        prompt: 'What is two plus two? Reply with only the number.',
        config: config,
      );
      expect(chat.finishReason, FinishReason.stop, reason: '${chat.error}');
      expect(chat.text.trim(), contains('4'));
      expect(
        chat.messages.last.content
            .where((p) => p.isReasoning)
            .map((p) => p.reasoning)
            .join()
            .trim(),
        isEmpty,
      );
      final structured = await app.ai
          .generate<String, LlamaDartGenerationConfig>(
            model: llamaDart.model('controls'),
            prompt: 'Return the word hello as a JSON string.',
            config: config,
            outputSchema: SchemanticType.from<String>(
              jsonSchema: {
                'type': 'string',
                'enum': ['hello'],
              },
              parse: (value) => value as String,
            ),
            outputFormat: 'json',
            outputConstrained: true,
          );
      expect(
        structured.finishReason,
        FinishReason.stop,
        reason: '${structured.error}',
      );
      expect(structured.output, 'hello');
      expect(
        structured.messages.last.content
            .where((p) => p.isReasoning)
            .map((p) => p.reasoning)
            .join()
            .trim(),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'Qwen3.5 runs recommended nonthinking sampling with presence penalty',
    () async {
      final path = await resolveIntegrationQwen35ModelPath();
      if (path == null) return;
      final app = setup(path);
      final timer = Stopwatch()..start();
      final result = await app.ai.generate(
        model: llamaDart.model('controls'),
        prompt: 'Name three primary colors. Keep your reply short.',
        config: const LlamaDartGenerationConfig(
          temperature: 1,
          topP: 1,
          topK: 20,
          minP: 0,
          penalty: 1,
          presencePenalty: 2,
          enableThinking: false,
          seed: 42,
          maxTokens: 96,
        ),
      );
      expect(result.finishReason, FinishReason.stop, reason: '${result.error}');
      expect(result.text, isNotEmpty);
      expect(result.text.toLowerCase(), contains('red'));
      expect(result.text.toLowerCase(), contains('blue'));
      print(
        'Qwen3.5 sampler elapsedMs=${timer.elapsedMilliseconds} output=${result.text}',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
