import 'dart:async';
import 'dart:typed_data';

import 'package:llamadart/backend.dart';
import 'package:llamadart/src/backends/backend.dart' as backend_spi;
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/embedding_contract.dart';

import 'engine_test.dart';

class ContentBackend extends MockLlamaBackend
    implements BackendMultimodalEmbeddings {
  LlamaEmbeddingCapabilities supported = const LlamaEmbeddingCapabilities(
    text: true,
    image: true,
    audio: true,
  );
  final List<LlamaEmbeddingInput> received = [];
  bool? normalized;
  Object? failure;
  Object? computeFailure;
  List<List<double>>? outputOverride;
  Completer<void>? probeGate;
  Completer<void>? gate;
  int probes = 0;

  @override
  Future<LlamaEmbeddingCapabilities> getEmbeddingCapabilities(
    int contextHandle,
  ) async {
    probes++;
    await probeGate?.future;
    if (failure != null) throw failure!;
    return supported;
  }

  @override
  Future<List<List<double>>> embedContentBatch(
    int contextHandle,
    List<LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  }) async {
    if (computeFailure != null) throw computeFailure!;
    received.addAll(inputs);
    normalized = normalize;
    await gate?.future;
    if (failure != null) throw failure!;
    return outputOverride ??
        [
          for (final input in inputs) [input.parts.length.toDouble()],
        ];
  }
}

final class Recorder extends LlamaEngineObserver {
  final List<LlamaEmbeddingsOperation> operations = [];
  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) {
    if (operation is LlamaEmbeddingsOperation) operations.add(operation);
    return null;
  }
}

class NormalizationBatchBackend extends MockBatchEmbeddingBackend {
  bool? normalized;

  @override
  Future<List<List<double>>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  }) {
    normalized = normalize;
    return super.embedBatch(contextHandle, texts, normalize: normalize);
  }
}

class MisreportedBackend extends MockLlamaBackend
    implements BackendEmbeddingsSupport {
  @override
  bool get supportsEmbeddings => true;
}

class RuntimeContentBackend extends ContentBackend
    implements backend_spi.BackendRuntimeIdentity {
  RuntimeContentBackend(this.runtime);

  @override
  final LlamaRuntime runtime;
}

void main() {
  for (final single in [false, true]) {
    for (final duringProbe in [false, true]) {
      test(
        'content cancellation before dispatch: single=$single probe=$duringProbe',
        () async {
          final backend = ContentBackend()..probeGate = Completer<void>();
          final engine = LlamaEngine(backend);
          addTearDown(engine.dispose);
          await engine.loadModel('fake.gguf');
          final input = LlamaEmbeddingInput([const LlamaTextContent('text')]);
          final future = single
              ? engine.embedContent(input)
              : engine.embedContentBatch(List.filled(64, input));
          if (duringProbe) await pumpEventQueue();
          engine.cancelGeneration();
          final cancelled = expectLater(
            future,
            throwsA(
              isA<LlamaInferenceException>().having(
                (e) => e.message,
                'cancellation',
                contains('cancel'),
              ),
            ),
          );
          backend.probeGate!.complete();
          await cancelled;
          expect(backend.received, isEmpty);
          expect(await engine.embedContent(input), [1.0]);
        },
      );
    }
  }

  test(
    'native media diagnostics name the guarded ABI and native version',
    () async {
      final backend = RuntimeContentBackend(LlamaRuntime.llamaCpp)
        ..supported = const LlamaEmbeddingCapabilities(
          text: true,
          mediaUnsupportedReason:
              'Native media embeddings require guarded mixed-batch ABI v0.7.0-1.',
        );
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      for (final part in <LlamaContentPart>[
        LlamaAudioContent(samples: Float32List(4)),
        LlamaImageContent(bytes: Uint8List(4)),
      ]) {
        await expectLater(
          engine.embedContent(LlamaEmbeddingInput([part])),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'required ABI',
              allOf(
                contains('mixed-batch'),
                contains('v0.7.0-1'),
                contains(part is LlamaImageContent ? 'image' : 'audio'),
              ),
            ),
          ),
        );
      }
      expect(backend.received, isEmpty);
    },
  );

  test('media requirements never replace a rejected text diagnostic', () async {
    final backend = ContentBackend()
      ..supported = const LlamaEmbeddingCapabilities(
        mediaUnsupportedReason: 'media-only diagnostic',
      );
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('fake.gguf');
    await expectLater(
      engine.embedContent(LlamaEmbeddingInput([const LlamaTextContent('a')])),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'text diagnostic',
          allOf(contains('text'), isNot(contains('media-only'))),
        ),
      ),
    );
  });

  test(
    'unidentified backend diagnostics use a stable unknown runtime',
    () async {
      final engine = LlamaEngine(MockLlamaBackend());
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await expectLater(
        engine.embedContent(LlamaEmbeddingInput([const LlamaTextContent('x')])),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'runtime',
            contains('(unknown)'),
          ),
        ),
      );
    },
  );

  for (final batched in [false, true]) {
    test(
      'adjacent-text contract helper covers legacy batch=$batched',
      () async {
        final engine = LlamaEngine(
          batched ? MockBatchEmbeddingBackend() : MockEmbeddingBackend(),
        );
        addTearDown(engine.dispose);
        await engine.loadModel('fake.gguf');
        await expectAdjacentTextEmbeddingEquivalence(engine.embedContent);
      },
    );
  }

  for (final requested in [1, 2]) {
    for (final returned in [0, 1, 3]) {
      if (requested == returned) continue;
      test('rejects $returned vectors for $requested content inputs', () async {
        final backend = ContentBackend()
          ..outputOverride = List.generate(returned, (_) => [1.0]);
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('fake.gguf');
        final input = LlamaEmbeddingInput([const LlamaTextContent('private')]);
        await expectLater(
          requested == 1
              ? engine.embedContent(input)
              : engine.embedContentBatch([input, input]),
          throwsA(
            isA<LlamaInferenceException>()
                .having(
                  (e) => e.message,
                  'count',
                  contains('expected $requested'),
                )
                .having(
                  (e) => e.message,
                  'redaction',
                  isNot(contains('private')),
                ),
          ),
        );
      });
    }
  }

  final mixed = LlamaEmbeddingInput([
    const LlamaTextContent('private text'),
    LlamaImageContent(bytes: Uint8List.fromList([42]), path: 'secret.png'),
    LlamaAudioContent(samples: Float32List.fromList([0.5]), path: 'secret.wav'),
    const LlamaTextContent('after'),
  ]);

  test(
    'loaded backend probe controls each modality and dispatches ordered batch',
    () async {
      final backend = ContentBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await expectLater(
        engine.embeddingCapabilities,
        throwsA(isA<LlamaContextException>()),
      );
      await expectLater(
        engine.embedContentBatch([]),
        throwsA(isA<LlamaContextException>()),
      );
      await expectLater(
        engine.embedContent(mixed),
        throwsA(isA<LlamaContextException>()),
      );
      await engine.loadModel('fake.gguf');
      expect((await engine.embeddingCapabilities).audio, isTrue);
      expect(
        await engine.embedContent(mixed, normalize: false),
        [
          [4.0],
        ].single,
      );
      expect(backend.received.single, same(mixed));
      expect(backend.normalized, isFalse);
      expect(
        await engine.embedContentBatch([
          mixed,
          LlamaEmbeddingInput([const LlamaTextContent('x')]),
        ]),
        [
          [4.0],
          [1.0],
        ],
      );
      expect(backend.normalized, isTrue);
      expect(await engine.embedContentBatch([]), isEmpty);
      expect(backend.received, hasLength(3));
    },
  );

  for (final modality in LlamaEmbeddingModality.values) {
    test(
      'probe rejects unsupported ${modality.name} before any batch work',
      () async {
        final backend = ContentBackend()
          ..supported = LlamaEmbeddingCapabilities(
            text: modality != LlamaEmbeddingModality.text,
            image: modality != LlamaEmbeddingModality.image,
            audio: modality != LlamaEmbeddingModality.audio,
          );
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('fake.gguf');
        await expectLater(
          engine.embedContentBatch([
            LlamaEmbeddingInput([const LlamaTextContent('first')]),
            mixed,
          ]),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'modality',
              contains(modality.name),
            ),
          ),
        );
        expect(backend.received, isEmpty);
        backend.supported = const LlamaEmbeddingCapabilities(
          text: true,
          image: true,
          audio: true,
        );
        expect(await engine.embedContent(mixed), [4.0]);
      },
    );
  }

  test(
    'legacy text paths retain raw strings and reject media explicitly',
    () async {
      final backend = MockEmbeddingBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      final caps = await engine.embeddingCapabilities;
      expect(caps.text, isTrue);
      expect(caps.image, isFalse);
      expect(caps.audio, isFalse);
      final input = LlamaEmbeddingInput([
        const LlamaTextContent('a'),
        const LlamaTextContent('b'),
      ]);
      expect(await engine.embedContent(input), await engine.embed('ab'));
      expect(
        await engine.embedContent(input, normalize: false),
        await engine.embed('ab', normalize: false),
      );
      await expectLater(
        engine.embedContent(mixed),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test(
    'backend without embeddings reports no modalities and rejects text',
    () async {
      final engine = LlamaEngine(MockLlamaBackend());
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      expect((await engine.embeddingCapabilities).text, isFalse);
      await expectLater(
        engine.embedContent(LlamaEmbeddingInput([const LlamaTextContent('x')])),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test(
    'new observer operations retain only immutable part kinds and counts',
    () async {
      final backend = ContentBackend();
      final recorder = Recorder();
      final engine = LlamaEngine(backend, observers: [recorder]);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await engine.embedContentBatch([mixed, mixed], normalize: false);
      final operation = recorder.operations.single;
      expect(operation.inputs, isEmpty);
      expect(operation.inputPartKinds, [mixed.partKinds, mixed.partKinds]);
      expect(operation.inputCount, 2);
      expect(operation.normalize, isFalse);
      expect(() => operation.inputPartKinds.clear(), throwsUnsupportedError);
      expect(
        () => operation.inputPartKinds.first.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'unsupported probe errors become typed errors without forwarding input',
    () async {
      final backend = ContentBackend()
        ..failure = UnsupportedError('runtime needs embedding ABI');
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await expectLater(
        engine.embedContent(mixed),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(backend.received, isEmpty);
    },
  );

  test(
    'cancelGeneration reaches the backend during an embedding future',
    () async {
      final backend = ContentBackend()..gate = Completer<void>();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      final result = engine.embedContent(mixed);
      await Future<void>.delayed(Duration.zero);
      final before = backend.cancelGenerationCalls;
      engine.cancelGeneration();
      expect(backend.cancelGenerationCalls, before + 1);
      backend.gate!.complete();
      expect(await result, [4.0]);
    },
  );
  test(
    'legacy batched content uses batch dispatch and preserves order',
    () async {
      final backend = MockBatchEmbeddingBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      expect(
        await engine.embedContentBatch([
          LlamaEmbeddingInput([const LlamaTextContent('long')]),
          LlamaEmbeddingInput([const LlamaTextContent('a')]),
        ]),
        [
          [4.0, 99.0],
          [1.0, 99.0],
        ],
      );
      expect(backend.embedBatchCalls, 1);
      expect(backend.embedCalls, 0);
    },
  );

  test(
    'explicit false legacy probe overrides an embedding interface',
    () async {
      final engine = LlamaEngine(
        ProbedEmbeddingBackend(supportsEmbeddings: false),
      );
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      expect((await engine.embeddingCapabilities).text, isFalse);
      await expectLater(
        engine.embedContent(LlamaEmbeddingInput([const LlamaTextContent('x')])),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test(
    'misreported legacy text capability fails with a typed exception',
    () async {
      final engine = LlamaEngine(MisreportedBackend());
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await expectLater(
        engine.embedContent(LlamaEmbeddingInput([const LlamaTextContent('x')])),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test('empty batches bypass even an unavailable capability probe', () async {
    final backend = ContentBackend()..failure = StateError('must not probe');
    expect(
      await backend_spi.BackendEmbeddingDispatch(
        backend,
      ).embedContentWithFallback(1, []),
      isEmpty,
    );
    expect(backend.probes, 0);
  });

  test(
    'unsupported compute and capability calls map UnsupportedError',
    () async {
      final backend = ContentBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      backend.failure = UnsupportedError('missing ABI');
      await expectLater(
        engine.embeddingCapabilities,
        throwsA(isA<LlamaUnsupportedException>()),
      );
      backend.failure = null;
      backend.computeFailure = UnsupportedError('missing mixed-batch API');
      await expectLater(
        engine.embedContent(mixed),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test(
    'input batch list is snapshotted before the asynchronous probe',
    () async {
      final backend = ContentBackend()..probeGate = Completer<void>();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      final inputs = [mixed];
      final result = engine.embedContentBatch(inputs);
      inputs.clear();
      backend.probeGate!.complete();
      expect(await result, [
        [4.0],
      ]);
    },
  );

  test('legacy observer input and kind defaults remain compatible', () async {
    final recorder = Recorder();
    final engine = LlamaEngine(MockEmbeddingBackend(), observers: [recorder]);
    addTearDown(engine.dispose);
    await engine.loadModel('fake.gguf');
    await engine.embedBatch(['first', 'second']);
    final operation = recorder.operations.single;
    expect(operation.inputs, ['first', 'second']);
    expect(operation.inputCount, 2);
    expect(operation.inputPartKinds, [
      [LlamaEmbeddingModality.text],
      [LlamaEmbeddingModality.text],
    ]);
  });
  test(
    'legacy batch normalization is forwarded for raw and normalized outputs',
    () async {
      final backend = NormalizationBatchBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      final inputs = [
        LlamaEmbeddingInput([const LlamaTextContent('text')]),
      ];
      await engine.embedContentBatch(inputs, normalize: false);
      expect(backend.normalized, isFalse);
      await engine.embedContentBatch(inputs);
      expect(backend.normalized, isTrue);
    },
  );
  for (final empty in [true, false]) {
    test(
      'content preflight preserves cancelled performance state: empty=$empty',
      () async {
        final backend = PerformanceCounterBackend(nativeChat: false);
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('fake.gguf');
        await engine.generate('first').drain<void>();
        final cancelled = engine.generate('cancelled').toList();
        engine.cancelGeneration();
        await cancelled;
        expect(await engine.getPerformanceContext(), isNull);
        if (empty) {
          expect(await engine.embedContentBatch([]), isEmpty);
        } else {
          await expectLater(
            engine.embedContent(mixed),
            throwsA(isA<LlamaUnsupportedException>()),
          );
        }
        expect(await engine.getPerformanceContext(), isNull);
      },
    );
  }

  test(
    'content compute after cancellation reports fresh embedding counters',
    () async {
      final engine = LlamaEngine(PerformanceCounterBackend(nativeChat: false));
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await engine.generate('first').drain<void>();
      final cancelled = engine.generate('cancelled').toList();
      engine.cancelGeneration();
      await cancelled;
      expect(await engine.getPerformanceContext(), isNull);
      await engine.embedContent(
        LlamaEmbeddingInput([const LlamaTextContent('text')]),
      );
      expect((await engine.getPerformanceContext())?.evalTokens, 0);
    },
  );
}
