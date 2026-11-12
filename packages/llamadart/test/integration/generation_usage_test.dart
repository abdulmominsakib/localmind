@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  late LlamaBackend backend;
  late BackendGenerationUsageReporting usages;
  late int model;
  late int context;

  setUpAll(() async {
    backend = LlamaBackend();
    usages = backend as BackendGenerationUsageReporting;
    final file = await TestHelper.getTestModel();
    const params = ModelParams(
      contextSize: 256,
      gpuLayers: 0,
      preferredBackend: GpuBackend.cpu,
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
    );
    model = await backend.modelLoad(file.path, params);
    context = await backend.contextCreate(model, params);
  });
  tearDownAll(() async {
    await backend.contextFree(context);
    await backend.modelFree(model);
    await backend.dispose();
  });

  const repeating = GenerationParams(
    maxTokens: 5,
    temp: 0,
    seed: 1,
    penalty: 1,
    grammar: 'root ::= "a " root',
  );

  Future<LlamaGenerationUsage> run(
    String prompt,
    GenerationParams params,
  ) async {
    final generation = backend.generate(context, prompt, params);
    await generation.drain<void>();
    return usages.generationUsageOf(generation)!;
  }

  group('llama.cpp generation usage', () {
    test('counts prompt and generated tokens', () async {
      const prompt = 'Once upon a time';
      final promptTokens = await backend.tokenize(model, prompt);

      final usage = await run(
        prompt,
        repeating.copyWith(reusePromptPrefix: false),
      );

      expect(usage.promptTokens, promptTokens.length);
      expect(usage.cachedPromptTokens, 0);
      expect(usage.completionTokens, 5);
      expect(usage.timeToFirstToken, isNotNull);
      expect(usage.timeToFirstToken, greaterThan(Duration.zero));
      expect(usage.duration, greaterThanOrEqualTo(usage.timeToFirstToken!));
    });

    test('counts the prefix reused from the previous prompt', () async {
      const first = 'Once upon a time';
      const second = 'Once upon a time there was a little girl';
      final firstTokens = await backend.tokenize(model, first);
      final secondTokens = await backend.tokenize(model, second);
      var shared = 0;
      while (shared < firstTokens.length &&
          firstTokens[shared] == secondTokens[shared]) {
        shared++;
      }
      expect(shared, greaterThan(1));

      await run(first, repeating);
      final usage = await run(second, repeating);

      expect(usage.promptTokens, secondTokens.length);
      expect(usage.cachedPromptTokens, shared);

      final fullDecode = await run(
        second,
        repeating.copyWith(reusePromptPrefix: false),
      );
      expect(fullDecode.cachedPromptTokens, 0);
    });

    test(
      'has no first-token time when a stop sequence hides all text',
      () async {
        final generation = backend.generate(
          context,
          'Once upon a time',
          repeating.copyWith(maxTokens: 100, stopSequences: <String>['a a a']),
        );
        final chunks = await generation.toList();
        final usage = usages.generationUsageOf(generation)!;

        expect(chunks, isEmpty);
        expect(usage.completionTokens, greaterThan(0));
        expect(usage.timeToFirstToken, isNull);
      },
    );

    test('counts generated tokens whose text piece is empty', () async {
      final bos = (await backend.tokenize(model, '')).single;
      final generation = backend.generate(
        context,
        'Once upon a time',
        repeating.copyWith(maxTokens: 4, grammar: 'root ::= <[$bos]>+'),
      );
      final chunks = await generation.toList();
      final usage = usages.generationUsageOf(generation)!;

      expect(chunks, isEmpty);
      expect(usage.completionTokens, 4);
      expect(usage.timeToFirstToken, isNull);
    });

    test('create puts usage on the final chunk', () async {
      final engine = LlamaEngine(LlamaBackend());
      addTearDown(engine.dispose);
      final file = await TestHelper.getTestModel();
      await engine.loadModel(
        file.path,
        modelParams: const ModelParams(
          contextSize: 256,
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
        ),
      );

      final chunks = await engine.create(const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
      ], params: repeating).toList();

      final usage = chunks.last.usage!;
      expect(usage.promptTokens, greaterThan(0));
      expect(usage.completionTokens, 5);
      expect(
        chunks.take(chunks.length - 1).map((chunk) => chunk.usage),
        everyElement(isNull),
      );
    });
  });
}
