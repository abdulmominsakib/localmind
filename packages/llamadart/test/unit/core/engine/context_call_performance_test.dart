import 'dart:async';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'engine_test.dart';

class _EmbeddingDispatchBackend extends PerformanceCounterBackend {
  _EmbeddingDispatchBackend() : super(nativeChat: false);

  bool fail = false;
  bool failAsynchronously = false;
  int dispatches = 0;
  Completer<void>? gate;

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) => _dispatch(() => super.embed(contextHandle, text, normalize: normalize));

  Future<T> _dispatch<T>(Future<T> Function() call) {
    dispatches++;
    if (fail) {
      final error = LlamaInferenceException('Dispatch rejected before worker');
      if (failAsynchronously) return Future.error(error);
      throw error;
    }
    return () async {
      await gate?.future;
      return call();
    }();
  }

  @override
  Future<LlamaNextTokenScores> scoreNextToken(
    int contextHandle,
    String prompt, {
    required List<int> candidates,
    required int topK,
    required bool reusePromptPrefix,
  }) => _dispatch(
    () => super.scoreNextToken(
      contextHandle,
      prompt,
      candidates: candidates,
      topK: topK,
      reusePromptPrefix: reusePromptPrefix,
    ),
  );

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress)? onProgress,
  }) => _dispatch(
    () => super.synthesizeTextToSpeech(
      contextHandle,
      mmContextHandle,
      request,
      onProgress: onProgress,
    ),
  );
}

class _ContentDispatchBackend extends _EmbeddingDispatchBackend
    implements BackendMultimodalEmbeddings {
  @override
  Future<LlamaEmbeddingCapabilities> getEmbeddingCapabilities(
    int contextHandle,
  ) async => const LlamaEmbeddingCapabilities(text: true);

  @override
  Future<List<List<double>>> embedContentBatch(
    int contextHandle,
    List<LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  }) async => [
    for (final input in inputs)
      await embed(
        contextHandle,
        input.parts.cast<LlamaTextContent>().map((part) => part.text).join(),
        normalize: normalize,
      ),
  ];
}

Future<void> _cancelEarly(LlamaEngine engine) async {
  final cancelled = engine.generate('cancelled').toList();
  engine.cancelGeneration();
  await cancelled;
  expect(await engine.getPerformanceContext(), isNull);
}

void main() {
  final paths = <String, Future<Object?> Function(LlamaEngine)>{
    'scoring': (engine) => engine.scoreNextToken('hello', topK: 1),
    'TTS': (engine) => engine.synthesizeTextToSpeechBackend(
      const BackendTextToSpeechRequest(text: 'hello'),
    ),
    'embed': (engine) => engine.embed('hello'),
    'embedBatch': (engine) => engine.embedBatch(['hello', 'world']),
    'content fallback': (engine) => engine.embedContent(
      LlamaEmbeddingInput([const LlamaTextContent('hello')]),
    ),
    'content dispatch': (engine) => engine.embedContentBatch([
      LlamaEmbeddingInput([const LlamaTextContent('hello')]),
    ]),
  };

  test(
    'generation restores diagnostics at dispatch even before failure',
    () async {
      final backend = _EmbeddingDispatchBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await engine.generate('first').drain<void>();
      await _cancelEarly(engine);
      final gate = Completer<void>();
      backend.hold = gate.future;
      final pending = engine.generate('dispatched').drain<void>();
      final failure = expectLater(
        pending,
        throwsA(isA<LlamaInferenceException>()),
      );
      await pumpEventQueue();
      final dispatchedGenerations = backend.generations;
      final during = await engine.getPerformanceContext();
      gate.completeError(LlamaInferenceException('Generation failed'));
      await failure;
      expect(dispatchedGenerations, 2);
      expect(during?.evalTokens, 0);
      expect((await engine.getPerformanceContext())?.evalTokens, 0);
    },
  );

  for (final MapEntry(key: path, value: dispatch) in paths.entries) {
    _EmbeddingDispatchBackend newBackend() => path == 'content dispatch'
        ? _ContentDispatchBackend()
        : _EmbeddingDispatchBackend();

    for (final stale in [true, false]) {
      for (final asynchronous in [false, true]) {
        test('$path failed dispatch preserves performance availability: '
            'stale=$stale async=$asynchronous', () async {
          final backend = newBackend();
          final engine = LlamaEngine(backend);
          addTearDown(engine.dispose);
          await engine.loadModel('fake.gguf');
          await engine.loadMultimodalProjector('mmproj.gguf');
          await engine.generate('first').drain<void>();
          expect((await engine.getPerformanceContext())?.evalTokens, 1);
          if (stale) await _cancelEarly(engine);
          backend
            ..fail = true
            ..failAsynchronously = asynchronous;

          await expectLater(
            dispatch(engine),
            throwsA(isA<LlamaInferenceException>()),
          );
          expect(backend.dispatches, 1);
          expect(
            (await engine.getPerformanceContext())?.evalTokens,
            stale ? null : 1,
          );

          backend.fail = false;
          await dispatch(engine);
          expect((await engine.getPerformanceContext())?.evalTokens, 0);
        });
      }
    }

    test('$path restores cancelled performance only after success', () async {
      final backend = newBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await engine.loadMultimodalProjector('mmproj.gguf');
      await engine.generate('first').drain<void>();
      await _cancelEarly(engine);
      final gate = backend.gate = Completer<void>();
      final pending = dispatch(engine);
      await pumpEventQueue();
      expect(backend.dispatches, 1);
      expect(await engine.getPerformanceContext(), isNull);
      gate.complete();
      await pending;
      expect((await engine.getPerformanceContext())?.evalTokens, 0);
    });

    for (final succeeds in [false, true]) {
      test('$path started before early cancellation stays unavailable '
          'until successful completion: success=$succeeds', () async {
        final backend = newBackend();
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('fake.gguf');
        await engine.loadMultimodalProjector('mmproj.gguf');
        await engine.generate('first').drain<void>();
        expect((await engine.getPerformanceContext())?.evalTokens, 1);
        final gate = backend.gate = Completer<void>();
        final pending = dispatch(engine);
        final completion = succeeds
            ? pending
            : expectLater(pending, throwsA(isA<LlamaInferenceException>()));
        await pumpEventQueue();
        expect(backend.dispatches, 1);
        final cancelled = engine.generate('cancelled').toList();
        engine.cancelGeneration();
        await cancelled;
        final during = await engine.getPerformanceContext();
        if (succeeds) {
          gate.complete();
        } else {
          gate.completeError(LlamaInferenceException('Rejected before worker'));
        }
        await completion;
        expect(
          (await engine.getPerformanceContext())?.evalTokens,
          succeeds ? 0 : null,
        );
        expect(during, isNull);
        backend.gate = null;
        await dispatch(engine);
        expect((await engine.getPerformanceContext())?.evalTokens, 0);
      });
    }

    test(
      '$path success after reload cannot revive cancelled counters',
      () async {
        final backend = newBackend();
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('fake.gguf');
        await engine.loadMultimodalProjector('mmproj.gguf');
        await engine.generate('first').drain<void>();
        final gate = backend.gate = Completer<void>();
        final pending = dispatch(engine);
        await pumpEventQueue();
        expect(backend.dispatches, 1);
        final oldHandle = engine.contextHandle;
        await engine.unloadModel();
        await engine.loadModel('fake.gguf');
        await engine.loadMultimodalProjector('mmproj.gguf');
        expect(engine.contextHandle, oldHandle);
        await engine.generate('new model').drain<void>();
        await _cancelEarly(engine);
        gate.complete();
        await pending;
        expect(await engine.getPerformanceContext(), isNull);
        await engine.generate('recovery').drain<void>();
        expect((await engine.getPerformanceContext())?.evalTokens, 1);
      },
    );
  }
}
