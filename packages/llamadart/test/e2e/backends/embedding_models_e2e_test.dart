@TestOn('vm')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

const _rerankerModelPathKey = 'LLAMADART_RERANKER_MODEL_PATH';
const _encoderModelPathKey = 'LLAMADART_MODERNBERT_MODEL_PATH';
const _pooledEncoderModelPathKey = 'LLAMADART_POOLED_MODERNBERT_MODEL_PATH';
const _embeddingGemma2ModelPathKey = 'LLAMADART_EMBEDDINGGEMMA2_MODEL_PATH';
const _backendKey = 'LLAMADART_EMBEDDING_BACKEND';
const _wideMicroBatch = ModelParams(
  contextSize: 1024,
  batchSize: 1024,
  microBatchSize: 1024,
);

void main() {
  group('EmbeddingGemma-2', () {
    test('projected text outputs survive sequential and batch reuse', () async {
      final engine = await _load(
        _embeddingGemma2ModelPathKey,
        const ModelParams(
          contextSize: 1024,
          batchSize: 1024,
          microBatchSize: 1024,
          maxParallelSequences: 2,
        ),
      );
      if (engine == null) return;
      addTearDown(engine.dispose);
      const inputs = [
        'title: none | text: Paris is the capital of France.',
        'title: none | text: A cat sleeps beside the window.',
      ];
      final sequential = [
        for (final input in inputs) await engine.embed(input),
      ];
      final batched = await engine.embedBatch(inputs);
      expect(batched, hasLength(inputs.length));
      for (var i = 0; i < inputs.length; i++) {
        // This model projects 512 hidden values to 768 output components.
        expect(sequential[i], hasLength(768));
        expect(batched[i], hasLength(768));
        expect(batched[i].every((value) => value.isFinite), isTrue);
        expect(_norm(batched[i]), closeTo(1.0, 1e-4));
        // Metal's batch GEMMs accumulate differently from single-sequence GEMMs.
        // Match the existing encoder parity budget for normalized components.
        expect(_maxAbsDiff(batched[i], sequential[i]), lessThan(1e-3));
      }
      expect(_maxAbsDiff(sequential[0], sequential[1]), greaterThan(1e-3));
      expect(
        _maxAbsDiff(await engine.embed(inputs.first), sequential.first),
        lessThan(1e-3),
      );
    });
  });

  group('rank-pooled reranker', () {
    for (final parallel in [1, 2]) {
      test('embed and embedBatch reject it with $parallel sequences', () async {
        final engine = await _load(
          _rerankerModelPathKey,
          ModelParams(contextSize: 512, maxParallelSequences: parallel),
        );
        if (engine == null) return;
        addTearDown(engine.dispose);

        Matcher rejectsRank() => throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('rank-pooled'),
          ),
        );
        await expectLater(
          engine.embed('Query: capital of France? Document: Paris.'),
          rejectsRank(),
        );
        await expectLater(
          engine.embedBatch([
            'Query: a? Document: b.',
            'Query: c? Document: d.',
          ]),
          rejectsRank(),
        );
      });
    }
  });

  group('ModernBERT encoder', () {
    test(
      'over 512 tokens in a 1024-token context throw instead of aborting',
      () async {
        final engine = await _load(
          _encoderModelPathKey,
          const ModelParams(contextSize: 1024),
        );
        if (engine == null) return;
        addTearDown(engine.dispose);

        await expectLater(
          engine.embed(await _textOfTokens(engine, 751)),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              contains('at most 512 tokens'),
            ),
          ),
        );
      },
    );

    test('a 1024-token micro-batch embeds over 750 tokens', () async {
      final engine = await _load(_encoderModelPathKey, _wideMicroBatch);
      if (engine == null) return;
      addTearDown(engine.dispose);

      final vector = await engine.embed(await _textOfTokens(engine, 751));

      expect(vector.every((value) => value.isFinite), isTrue);
      expect(_norm(vector), closeTo(1.0, 1e-4));
    });

    test('short input embeds the same with a wider micro-batch', () async {
      final small = await _load(
        _encoderModelPathKey,
        const ModelParams(contextSize: 512),
      );
      if (small == null) return;
      addTearDown(small.dispose);
      final text = await _textOfTokens(small, 300);
      final expected = await small.embed(text, normalize: false);
      await small.dispose();

      final large = await _load(_encoderModelPathKey, _wideMicroBatch);
      addTearDown(large!.dispose);
      final actual = await large.embed(text, normalize: false);

      expect(actual.length, expected.length);
      expect(_maxAbsDiff(actual, expected), lessThan(1e-3));
    });

    test(
      'input above an explicit micro-batch throws instead of aborting',
      () async {
        final engine = await _load(
          _encoderModelPathKey,
          const ModelParams(
            contextSize: 1024,
            batchSize: 1024,
            microBatchSize: 256,
          ),
        );
        if (engine == null) return;
        addTearDown(engine.dispose);
        final text = await _textOfTokens(engine, 300);

        await expectLater(
          engine.embed(text),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              contains('256'),
            ),
          ),
        );
        final short = await engine.embed(await _textOfTokens(engine, 200));
        expect(short.every((value) => value.isFinite), isTrue);
      },
    );

    test('embedBatch keeps each encoder pass within the micro-batch', () async {
      final engine = await _load(
        _pooledEncoderModelPathKey,
        const ModelParams(
          contextSize: 1024,
          batchSize: 1024,
          microBatchSize: 512,
          maxParallelSequences: 2,
        ),
      );
      if (engine == null) return;
      addTearDown(engine.dispose);
      final first = await _textOfTokens(engine, 400);
      final second = await _textOfTokens(engine, 410);

      final batch = await engine.embedBatch([first, second]);

      expect(_maxAbsDiff(batch[0], await engine.embed(first)), lessThan(1e-3));
      expect(_maxAbsDiff(batch[1], await engine.embed(second)), lessThan(1e-3));
    });
  });
}

Future<LlamaEngine?> _load(String modelPathKey, ModelParams params) async {
  final modelPath = Platform.environment[modelPathKey];
  if (modelPath == null || modelPath.isEmpty) {
    markTestSkipped('Set $modelPathKey to run this embedding E2E.');
    return null;
  }
  if (!File(modelPath).existsSync()) {
    throw StateError('$modelPathKey does not exist.');
  }
  final backendName = Platform.environment[_backendKey]?.trim();
  final backend = GpuBackend.values.byName(
    backendName == null || backendName.isEmpty ? 'cpu' : backendName,
  );
  final engine = LlamaEngine(LlamaBackend());
  await engine.loadModel(
    modelPath,
    modelParams: params.copyWith(
      preferredBackend: backend,
      gpuLayers: backend == GpuBackend.cpu ? 0 : ModelParams.maxGpuLayers,
    ),
  );
  return engine;
}

Future<String> _textOfTokens(LlamaEngine engine, int tokens) async {
  final words = <String>[];
  var index = 0;
  while (true) {
    words.add('word$index');
    index += 1;
    final text = words.join(' ');
    final count = (await engine.tokenize(text)).length;
    if (count >= tokens) {
      expect(count, lessThan(tokens + 8));
      return text;
    }
  }
}

double _norm(List<double> vector) =>
    math.sqrt(vector.fold(0.0, (sum, value) => sum + value * value));

double _maxAbsDiff(List<double> a, List<double> b) {
  var worst = 0.0;
  for (var i = 0; i < a.length; i++) {
    worst = math.max(worst, (a[i] - b[i]).abs());
  }
  return worst;
}
