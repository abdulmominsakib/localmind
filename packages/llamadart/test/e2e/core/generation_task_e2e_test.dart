@Tags(['local-only', 'e2e'])
library;

import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../test_helper.dart';

void main() {
  test(
    'native CPU tasks finish without observation and cancel through source cleanup',
    () async {
      final model = await TestHelper.getTestModel();
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.path(model.path)),
        params: const ModelParams(
          contextSize: 512,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
        ),
      );
      addTearDown(engine.dispose);
      final raw = engine.generateTask(
        'Once upon a time',
        params: const GenerationParams(maxTokens: 8, temp: 0),
      );
      expect((await raw.done).state, GenerationTaskState.completed);
      expect(await raw.result, isNotEmpty);
      await raw.events.drain<void>();

      final chat = engine.createTask(
        [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Once upon a time',
          ),
        ],
        params: const GenerationParams(maxTokens: 8, temp: 0),
        enableThinking: false,
      );
      expect((await chat.done).state, GenerationTaskState.completed);
      expect((await chat.result).text, isNotEmpty);
      await chat.events.drain<void>();

      final running = engine.generateTask(
        'Once upon a time',
        params: const GenerationParams(maxTokens: 4096, temp: 0),
      );
      final first = Completer<void>();
      final events = running.events.listen((_) {
        if (!first.isCompleted) first.complete();
      });
      await first.future;
      running.cancel();
      expect((await running.done).state, GenerationTaskState.cancelled);
      await events.cancel();
      expect(engine.isDisposed, isFalse);
      final next = engine.generateTask(
        'Once upon a time',
        params: const GenerationParams(maxTokens: 4, temp: 0),
      );
      expect((await next.done).state, GenerationTaskState.completed);
      expect(await next.result, isNotEmpty);
      await next.events.drain<void>();
    },
  );
}
