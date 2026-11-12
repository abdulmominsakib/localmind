import 'dart:math' as math;

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'engine_test.dart';

class _SingleBackend extends MockLlamaBackend implements BackendEmbeddings {
  final texts = <String>[];
  final normalizations = <bool>[];
  List<double> output = [for (var i = 0; i < 768; i++) i + 1.0];
  Object? failure;

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    texts.add(text);
    normalizations.add(normalize);
    if (failure != null) throw failure!;
    return output;
  }
}

class _BatchBackend extends _SingleBackend implements BackendBatchEmbeddings {
  int batches = 0;
  List<List<double>>? batchOutput;

  @override
  Future<List<List<double>>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  }) async {
    batches++;
    this.texts.addAll(texts);
    normalizations.add(normalize);
    return batchOutput ?? [for (final _ in texts) output];
  }
}

void main() {
  Future<LlamaEngine> load(_SingleBackend backend) async {
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('fake.gguf');
    return engine;
  }

  test(
    'raw default preserves prepared bytes, vector and backend normalization',
    () async {
      final backend = _SingleBackend()..output = [2, 3];
      final engine = await load(backend);
      const text = ' task: search result | query: already prepared\n한글 ';
      final helper = LlamaTextEmbedder(engine);
      expect(
        await helper.embed(const LlamaEmbeddingText.prepared(text)),
        same(backend.output),
      );
      expect(backend.texts, [text]);
      expect(backend.normalizations, [true]);
      await LlamaTextEmbedder(
        engine,
        normalize: false,
      ).embed(const LlamaEmbeddingText.prepared(''));
      expect(backend.texts.last, '');
      expect(backend.normalizations.last, false);
      // Existing engine calls remain verbatim and bypass the new profile.
      expect(await engine.embed(text), same(backend.output));
      expect(backend.texts.last, text);
    },
  );

  test(
    'raw profile rejects model-specific formatting and dimensions before compute',
    () async {
      final backend = _BatchBackend();
      final helper = LlamaTextEmbedder(await load(backend));
      for (final input in [
        const LlamaEmbeddingText.query('secret'),
        const LlamaEmbeddingText.document('secret'),
      ]) {
        await expectLater(
          helper.embed(input),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await expectLater(
          helper.embedBatch([
            const LlamaEmbeddingText.prepared('valid'),
            input,
          ]),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }
      expect(
        () => LlamaTextEmbedder(helper.engine, dimensions: 128),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(backend.texts, isEmpty);
      expect(backend.batches, 0);
    },
  );

  test(
    'all official task prefixes and document titles reach production calls',
    () async {
      final backend = _BatchBackend();
      final helper = LlamaTextEmbedder(
        await load(backend),
        profile: LlamaEmbeddingProfile.embeddingGemma2,
      );
      const names = [
        'search result',
        'question answering',
        'fact checking',
        'code retrieval',
        'classification',
        'clustering',
        'sentence similarity',
      ];
      await helper.embedBatch([
        for (final task in LlamaEmbeddingTask.values)
          LlamaEmbeddingText.query(' a\n한글 ', task: task),
        const LlamaEmbeddingText.document('body'),
        const LlamaEmbeddingText.document(' body ', title: ' title '),
        const LlamaEmbeddingText.document('', title: ''),
        const LlamaEmbeddingText.prepared(
          'task: search result | query: unchanged',
        ),
      ]);
      expect(backend.texts, [
        for (final name in names) 'task: $name | query:  a\n한글 ',
        'title: none | text: body',
        'title:  title  | text:  body ',
        'title:  | text: ',
        'task: search result | query: unchanged',
      ]);
      expect(backend.normalizations, [false]);
      expect(backend.batches, 1);
    },
  );

  for (final batch in [false, true]) {
    for (final dimensions in [768, 512, 256, 128]) {
      test(
        'truncate before normalization: batch=$batch dims=$dimensions',
        () async {
          final backend = batch ? _BatchBackend() : _SingleBackend();
          final helper = LlamaTextEmbedder(
            await load(backend),
            profile: LlamaEmbeddingProfile.embeddingGemma2,
            dimensions: dimensions,
          );
          final inputs = [
            const LlamaEmbeddingText.query('one'),
            const LlamaEmbeddingText.document('two'),
          ];
          final results = await helper.embedBatch(inputs);
          final norm = math.sqrt(
            List.generate(
              dimensions,
              (i) => (i + 1.0) * (i + 1.0),
            ).reduce((a, b) => a + b),
          );
          expect(results, hasLength(2));
          for (final vector in results) {
            expect(vector, hasLength(dimensions));
            expect(vector.first, closeTo(1 / norm, 1e-15));
            expect(vector.last, closeTo(dimensions / norm, 1e-15));
            expect(
              vector.fold(0.0, (sum, x) => sum + x * x),
              closeTo(1, 1e-12),
            );
          }
          expect(backend.output, hasLength(768));
          expect(backend.output.last, 768);
          expect(backend.normalizations, everyElement(false));
          if (backend is _BatchBackend) {
            expect(backend.batches, 1);
          } else {
            expect(backend.texts, [
              'task: search result | query: one',
              'title: none | text: two',
            ]);
          }
          expect(await helper.embed(inputs.first), results.first);
        },
      );
    }
  }

  test('finite extremes normalize without overflow or underflow', () async {
    final backend = _SingleBackend();
    final helper = LlamaTextEmbedder(
      await load(backend),
      profile: LlamaEmbeddingProfile.embeddingGemma2,
      dimensions: 128,
    );
    for (final scale in [1e308, 1e-308]) {
      backend.output = List.filled(768, scale);
      final vector = await helper.embed(const LlamaEmbeddingText.prepared('x'));
      expect(vector, everyElement(closeTo(1 / math.sqrt(128), 1e-15)));
    }
  });

  test(
    'unnormalized output slices without altering finite zero vectors',
    () async {
      final backend = _SingleBackend()..output = List.filled(768, 0);
      final helper = LlamaTextEmbedder(
        await load(backend),
        profile: LlamaEmbeddingProfile.embeddingGemma2,
        dimensions: 128,
        normalize: false,
      );
      expect(
        await helper.embed(const LlamaEmbeddingText.prepared('x')),
        List.filled(128, 0),
      );
      backend.output = List.generate(768, (i) => i + 1.0);
      expect(
        await helper.embed(const LlamaEmbeddingText.prepared('x')),
        backend.output.take(128),
      );
    },
  );

  test(
    'batch output order and default full EG2 dimension are preserved',
    () async {
      final backend = _BatchBackend()
        ..batchOutput = [
          [1, ...List<double>.filled(767, 0)],
          [-1, ...List<double>.filled(767, 0)],
        ];
      final helper = LlamaTextEmbedder(
        await load(backend),
        profile: LlamaEmbeddingProfile.embeddingGemma2,
      );
      final output = await helper.embedBatch([
        const LlamaEmbeddingText.query('one'),
        const LlamaEmbeddingText.document('two'),
      ]);
      expect(output.map((v) => v.first), [1, -1]);
      expect(output.map((v) => v.length), [768, 768]);
    },
  );

  test('invalid dimensions fail before any inference', () async {
    final backend = _SingleBackend();
    final engine = await load(backend);
    for (final dimensions in [-1, 0, 1, 127, 129, 767, 769]) {
      expect(
        () => LlamaTextEmbedder(
          engine,
          profile: LlamaEmbeddingProfile.embeddingGemma2,
          dimensions: dimensions,
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    }
    expect(backend.texts, isEmpty);
  });

  test(
    'bad width, nonfinite full vector and zero retained norm fail closed',
    () async {
      final backend = _SingleBackend();
      final engine = await load(backend);
      final helper = LlamaTextEmbedder(
        engine,
        profile: LlamaEmbeddingProfile.embeddingGemma2,
        dimensions: 128,
      );
      backend.output = List.filled(512, 1);
      await expectLater(
        helper.embed(const LlamaEmbeddingText.prepared('secret')),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        // Validate even discarded components, including when normalization is off.
        backend.output = List.filled(768, 1)..[767] = value;
        for (final normalize in [true, false]) {
          await expectLater(
            LlamaTextEmbedder(
              engine,
              profile: LlamaEmbeddingProfile.embeddingGemma2,
              dimensions: 128,
              normalize: normalize,
            ).embed(const LlamaEmbeddingText.prepared('secret')),
            throwsA(
              isA<LlamaInferenceException>().having(
                (e) => e.message,
                'redacted',
                isNot(contains('secret')),
              ),
            ),
          );
        }
      }
      backend.output = List.filled(768, 0)..[767] = 1;
      await expectLater(
        helper.embed(const LlamaEmbeddingText.prepared('x')),
        throwsA(isA<LlamaInferenceException>()),
      );
    },
  );

  test('whole-batch invalid outputs never return partial vectors', () async {
    final backend = _BatchBackend();
    final helper = LlamaTextEmbedder(
      await load(backend),
      profile: LlamaEmbeddingProfile.embeddingGemma2,
    );
    backend.batchOutput = [List.filled(768, 1)];
    await expectLater(
      helper.embedBatch([
        const LlamaEmbeddingText.query('one'),
        const LlamaEmbeddingText.query('two'),
      ]),
      throwsA(isA<LlamaInferenceException>()),
    );
    backend.batchOutput = [List.filled(768, 1), List.filled(768, 0)];
    await expectLater(
      helper.embedBatch([
        const LlamaEmbeddingText.query('one'),
        const LlamaEmbeddingText.query('two'),
      ]),
      throwsA(isA<LlamaInferenceException>()),
    );
    expect(await helper.embedBatch([]), isEmpty);
  });

  test(
    'unsupported backends and inference cancellation propagate unchanged',
    () async {
      final unsupported = LlamaEngine(MockLlamaBackend());
      addTearDown(unsupported.dispose);
      await unsupported.loadModel('fake.gguf');
      await expectLater(
        LlamaTextEmbedder(
          unsupported,
          profile: LlamaEmbeddingProfile.embeddingGemma2,
        ).embed(const LlamaEmbeddingText.query('x')),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      final backend = _SingleBackend();
      final helper = LlamaTextEmbedder(
        await load(backend),
        profile: LlamaEmbeddingProfile.embeddingGemma2,
      );
      final cancelled = LlamaInferenceException('cancelled');
      backend.failure = cancelled;
      await expectLater(
        helper.embed(const LlamaEmbeddingText.query('x')),
        throwsA(same(cancelled)),
      );
      backend.failure = null;
      expect(
        await helper.embed(const LlamaEmbeddingText.query('x')),
        hasLength(768),
      );
    },
  );
}
