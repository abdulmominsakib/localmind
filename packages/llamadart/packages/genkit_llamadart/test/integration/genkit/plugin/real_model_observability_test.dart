@Tags(<String>['real-model'])
library;

import 'dart:async';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit/plugin.dart' as api;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

final traceKey = Object();
const _fixtureModelParams = ModelParams(
  device: ComputeDevice.cpu,
  contextSize: 1024,
  numberOfThreads: 1,
  numberOfThreadsBatch: 1,
);

void main() {
  test(
    'real engine reports usage, structured usage and request-local observer context',
    () async {
      final modelPath = await resolveIntegrationModelPath();
      if (modelPath == null) return;
      final observer = _Observer();
      final plugin = llamaDart(
        models: [
          LlamaModelDefinition(
            name: 'observed',
            modelPath: modelPath,
            modelParams: _fixtureModelParams,
            supportsEmbeddings: false,
          ),
        ],
        observers: [observer],
      );
      final ai = genkit.Genkit(plugins: [plugin], isDevEnv: false);
      try {
        Future<genkit.GenerateResult<Object?>> generate(String trace) =>
            runZoned(
              () => ai.generate(
                model: llamaDart.model('observed'),
                prompt: 'Say hello.',
                config: const LlamaDartGenerationConfig(
                  maxTokens: 8,
                  temperature: 0,
                ),
              ),
              zoneValues: {traceKey: trace},
            );
        final responses = await Future.wait([
          generate('first'),
          generate('queued'),
        ]);
        for (final response in responses) {
          expect(response.text.trim(), isNotEmpty);
          expect(response.usage!.inputTokens, greaterThan(0));
          expect(response.usage!.outputTokens, greaterThan(0));
          expect(response.usage!.inputCharacters, 'Say hello.'.length);
          expect(response.usage!.outputCharacters, response.text.length);
          expect(
            response.raw!['usage']['duration_ms'],
            greaterThanOrEqualTo(0),
          );
        }
        final chats = observer.records
            .where((r) => r.operation is LlamaChatOperation)
            .toList();
        expect(chats.map((r) => r.trace), ['first', 'queued']);
        expect(chats.map((r) => r.endTrace), ['first', 'queued']);
        expect(
          observer.records.where((r) => r.operation is LlamaModelLoadOperation),
          hasLength(1),
        );

        final structured = await ai.generate(
          model: llamaDart.model('observed'),
          prompt: 'Return a JSON object with an answer.',
          outputFormat: 'json',
          config: const LlamaDartGenerationConfig(
            maxTokens: 32,
            temperature: 0,
          ),
        );
        expect(structured.finishReason, isNot(genkit.FinishReason.failed));
        expect(structured.usage!.inputTokens, greaterThan(0));
        expect(
          observer.records.where(
            (r) => r.operation is LlamaTextCompletionOperation,
          ),
          hasLength(1),
        );

        final action = (await plugin.init())
            .whereType<api.Model<LlamaDartGenerationConfig>>()
            .single;
        final cancellation = genkit.CancellationController();
        await expectLater(
          action(
            genkit.ModelRequest(
              messages: [
                genkit.Message(
                  role: genkit.Role.user,
                  content: [
                    genkit.TextPart(text: 'Count from one to one hundred.'),
                  ],
                ),
              ],
              config: const LlamaDartGenerationConfig(maxTokens: 128).toJson(),
            ),
            cancel: cancellation.token,
            onChunk: (_) => cancellation.cancel(),
          ),
          throwsA(isA<genkit.CancelledException>()),
        );
        expect(observer.records.last.result!.cancelled, isTrue);
      } finally {
        await plugin.dispose();
        await ai.shutdown();
      }
    },
  );

  test('prepared model paths preserve observers', () async {
    final path = await resolveIntegrationModelPath();
    if (path == null) return;
    for (final taskBased in [false, true]) {
      final observer = _Observer();
      final prepared = taskBased
          ? await llamaDart
                .prepareModelTask(
                  name: 'prepared',
                  source: ModelSource.path(path),
                  modelParams: _fixtureModelParams,
                  supportsEmbeddings: false,
                  observers: [observer],
                )
                .result
          : await llamaDart.prepareModel(
              name: 'prepared',
              source: ModelSource.path(path),
              modelParams: _fixtureModelParams,
              supportsEmbeddings: false,
              observers: [observer],
            );
      final ai = prepared.createGenkit(isDevEnv: false);
      try {
        await prepared.warmUp(ai);
        expect(
          observer.records.where((r) => r.operation is LlamaModelLoadOperation),
          hasLength(1),
        );
        expect(
          observer.records.where((r) => r.operation is LlamaChatOperation),
          hasLength(1),
        );
      } finally {
        await prepared.dispose();
        await ai.shutdown();
      }
    }
  });

  test('engine observers receive model-load failures', () async {
    final observer = _Observer();
    final plugin = llamaDart(
      models: [
        const LlamaModelDefinition(
          name: 'missing',
          modelPath: '/nonexistent/genkit-observability-model.gguf',
          modelParams: _fixtureModelParams,
          supportsEmbeddings: false,
        ),
      ],
      observers: [observer],
    );
    final ai = genkit.Genkit(plugins: [plugin], isDevEnv: false);
    try {
      final response = await ai.generate(
        model: llamaDart.model('missing'),
        prompt: 'Hi',
      );
      expect(response.finishReason, genkit.FinishReason.failed);
      expect(observer.records.single.result!.error, isNotNull);
    } finally {
      await plugin.dispose();
      await ai.shutdown();
    }
  });
}

final class _Observer extends LlamaEngineObserver {
  final records = <_Operation>[];
  @override
  LlamaOperationObserver onStart(LlamaOperation operation) {
    final record = _Operation(operation, Zone.current[traceKey]);
    records.add(record);
    return record;
  }
}

final class _Operation extends LlamaOperationObserver {
  _Operation(this.operation, this.trace);
  final LlamaOperation operation;
  final Object? trace;
  Object? endTrace;
  LlamaOperationResult? result;
  @override
  void onEnd(LlamaOperationResult result) {
    this.result = result;
    endTrace = Zone.current[traceKey];
  }
}
