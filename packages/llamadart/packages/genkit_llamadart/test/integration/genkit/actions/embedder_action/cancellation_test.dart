import 'dart:async';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:genkit_llamadart/src/integration/genkit/actions/embedder_action.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  late _WaitingRuntime runtime;
  late EngineRegistry registry;
  late genkit.Embedder<LlamaDartEmbedConfig> action;
  final request = genkit.EmbedRequest(
    input: [
      genkit.DocumentData(
        content: [genkit.TextPart(text: 'hello')],
        metadata: {'id': 'doc'},
      ),
    ],
    options: {'normalize': false},
  );

  setUp(() {
    runtime = _WaitingRuntime();
    final definition = testModelDefinition();
    registry = testRegistry(definition: definition, runtime: runtime);
    action = buildEmbedderAction(definition: definition, registry: registry);
  });
  tearDown(() async {
    runtime.releaseAll();
    await registry.dispose();
  });

  test('pre-cancelled embedding never initializes or evaluates', () async {
    final controller = genkit.CancellationController()..cancel();
    await expectLater(
      action(request, cancel: controller.token),
      throwsA(isA<genkit.CancelledException>()),
    );
    expect(runtime.initializeCount, 0);
    expect(runtime.embedBatchCallCount, 0);
  });

  test('legacy text is captured before initialization waits', () async {
    runtime.blockInitialization = true;
    final document = genkit.DocumentData(
      content: [genkit.TextPart(text: 'original')],
    );
    final pending = action(genkit.EmbedRequest(input: [document]));
    await runtime.initializationStarted.future;
    document.content = [genkit.TextPart(text: 'changed')];
    runtime.initializationRelease.complete();
    await pending;
    expect(runtime.lastTexts, ['original']);
  });

  test('queued cancellation skips capability checks and embedding', () async {
    runtime.blockEmbedding = true;
    final first = action(request);
    await runtime.embeddingStarted.future;
    final controller = genkit.CancellationController();
    final second = action(request, cancel: controller.token);
    final cancelled = expectLater(
      second,
      throwsA(isA<genkit.CancelledException>()),
    );
    await Future<void>(() {});
    controller.cancel();
    runtime.embeddingRelease.complete();
    final response = await first;
    await cancelled;
    expect(runtime.embedBatchCallCount, 1);
    expect(runtime.capabilityReadCount, 1);
    expect(runtime.cancelGenerationCount, 0);
    expect(response.embeddings.single.metadata, {'id': 'doc'});
    final next = await action(request);
    expect(next.embeddings.single.embedding, [1.0, 0.0]);
    expect(runtime.embedBatchCallCount, 2);
    expect(runtime.initializeCount, 1);
    expect(runtime.lastNormalize, false);
  });

  test('cancellation during initialization prevents embedding', () async {
    runtime.blockInitialization = true;
    final controller = genkit.CancellationController();
    final pending = action(request, cancel: controller.token);
    final cancelled = expectLater(
      pending,
      throwsA(isA<genkit.CancelledException>()),
    );
    await runtime.initializationStarted.future;
    controller.cancel();
    runtime.initializationRelease.complete();
    await cancelled;
    expect(runtime.embedBatchCallCount, 0);
    expect(runtime.cancelGenerationCount, 0);
    await action(request);
    expect(runtime.embedBatchCallCount, 1);
    expect(runtime.initializeCount, 1);
  });

  for (final fail in [false, true]) {
    test(
      'active cancellation drains before reporting; backend error=$fail',
      () async {
        runtime
          ..blockEmbedding = true
          ..failEmbedding = fail;
        final controller = genkit.CancellationController();
        var settled = false;
        final pending = action(request, cancel: controller.token);
        final cancelled = expectLater(
          pending.whenComplete(() => settled = true),
          throwsA(isA<genkit.CancelledException>()),
        );
        await runtime.embeddingStarted.future;
        controller.cancel();
        await Future<void>(() {});
        expect(settled, isFalse);
        expect(runtime.cancelGenerationCount, 0);
        runtime.embeddingRelease.complete();
        await cancelled;
        runtime.failEmbedding = false;
        final next = await action(request);
        expect(next.embeddings.single.embedding, [1.0, 0.0]);
        expect(runtime.embedBatchCallCount, 2);
      },
    );
  }

  test(
    'queued embedding cancellation does not stop another generation',
    () async {
      final first = registry.withRuntime(
        testModelDefinition().name,
        (runtime) => runtime.generate('busy').toList(),
      );
      await runtime.generationStarted.future;
      final controller = genkit.CancellationController();
      final cancelled = expectLater(
        action(request, cancel: controller.token),
        throwsA(isA<genkit.CancelledException>()),
      );
      await Future<void>(() {});
      controller.cancel();
      expect(runtime.cancelGenerationCount, 0);
      runtime.generationRelease.complete();
      expect(await first, ['ok']);
      await cancelled;
      expect(runtime.embedBatchCallCount, 0);
      expect(runtime.capabilityReadCount, 1);
    },
  );
}

class _WaitingRuntime extends FakeRuntime {
  final initializationStarted = Completer<void>();
  final initializationRelease = Completer<void>();
  final embeddingStarted = Completer<void>();
  final embeddingRelease = Completer<void>();
  final generationStarted = Completer<void>();
  final generationRelease = Completer<void>();
  bool blockInitialization = false;
  bool blockEmbedding = false;
  bool failEmbedding = false;
  List<String>? lastTexts;

  @override
  Future<void> initialize(LlamaModelDefinition definition) async {
    await super.initialize(definition);
    if (blockInitialization) {
      blockInitialization = false;
      initializationStarted.complete();
      await initializationRelease.future;
    }
  }

  @override
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    bool normalize = true,
  }) async {
    lastTexts = texts;
    await super.embedBatch(texts, normalize: normalize);
    if (blockEmbedding) {
      blockEmbedding = false;
      embeddingStarted.complete();
      await embeddingRelease.future;
    }
    if (failEmbedding) throw llama.LlamaStateException('Embedding failed.');
    return [
      for (final _ in texts) [1.0, 0.0],
    ];
  }

  @override
  Stream<String> generate(
    String prompt, {
    llama.GenerationParams params = const llama.GenerationParams(),
    List<llama.LlamaContentPart>? parts,
  }) async* {
    generationStarted.complete();
    await generationRelease.future;
    yield 'ok';
  }

  void releaseAll() {
    for (final gate in [
      initializationRelease,
      embeddingRelease,
      generationRelease,
    ]) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}
