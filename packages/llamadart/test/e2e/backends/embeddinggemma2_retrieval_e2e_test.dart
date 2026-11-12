@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  final model = Platform.environment['LLAMADART_EMBEDDINGGEMMA2_MODEL_PATH'];
  final referencePath =
      Platform.environment['LLAMADART_EG2_RETRIEVAL_REFERENCE'];
  test(
    'EG2 helpers match official text retrieval at every supported dimension',
    () async {
      final corpusBytes = File(
        'test/fixtures/embeddings/embeddinggemma2_retrieval.json',
      ).readAsBytesSync();
      final corpus =
          jsonDecode(utf8.decode(corpusBytes)) as Map<String, dynamic>;
      final reference =
          jsonDecode(File(referencePath!).readAsStringSync())
              as Map<String, dynamic>;
      expect(reference['model'], 'google/embeddinggemma-2');
      expect(reference['revision'], '914f7f89142e33e77833254d9c9b90c3cef7303b');
      expect(reference['dtype'], 'float32');
      expect(
        reference['weights_sha256'],
        '197a32965d4b1105faf060417baa899e193fb73cd401f42ec9295234d5553d79',
      );
      expect(reference['device'], 'cpu');
      expect(
        reference['corpus_sha256'],
        sha256.convert(corpusBytes).toString(),
      );
      final modelHash = await sha256.bind(File(model!).openRead()).first;
      expect(
        modelHash.toString(),
        '68bae29d62fb8c7d23e98d21fd4662753ddd636e6b62b8a70dfe059a9844f216',
      );
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.path(model)),
        params: const LlamaCppModelParams(
          contextSize: 1024,
          batchSize: 1024,
          microBatchSize: 1024,
          maxParallelSequences: 4,
          preferredBackend: GpuBackend.cpu,
          gpuLayers: 0,
        ),
      );
      addTearDown(engine.dispose);
      final documents = [
        for (final doc in corpus['documents'] as List)
          LlamaEmbeddingText.document(
            doc['text'] as String,
            title: doc['title'] as String?,
          ),
      ];
      final queries = [
        for (final query in corpus['queries'] as List)
          LlamaEmbeddingText.query(query['text'] as String),
      ];
      final expectedTop = [
        for (final query in corpus['queries'] as List) query['document'] as int,
      ];
      final report = <String, Object?>{};
      for (final dimensions in [768, 512, 256, 128]) {
        final helper = LlamaTextEmbedder(
          engine,
          profile: LlamaEmbeddingProfile.embeddingGemma2,
          dimensions: dimensions,
        );
        final actualDocs = await helper.embedBatch(documents);
        final actualQueries = await helper.embedBatch(queries);
        final expected =
            (reference['dimensions'] as Map<String, dynamic>)['$dimensions']
                as Map<String, dynamic>;
        var minimumCosine = 1.0;
        var maximumScoreError = 0.0;
        for (final (actual, key) in [
          (actualDocs, 'documents'),
          (actualQueries, 'queries'),
        ]) {
          final vectors = expected[key] as List;
          for (var i = 0; i < actual.length; i++) {
            expect(actual[i], hasLength(dimensions));
            expect(actual[i].every((x) => x.isFinite), isTrue);
            expect(_dot(actual[i], actual[i]), closeTo(1, 1e-10));
            final referenceVector = [
              for (final x in vectors[i] as List) (x as num).toDouble(),
            ];
            final cosine =
                _dot(actual[i], referenceVector) /
                math.sqrt(_dot(referenceVector, referenceVector));
            minimumCosine = math.min(minimumCosine, cosine);
            expect(cosine, greaterThan(0.999), reason: '$dimensions $key $i');
          }
        }
        final top = <int>[];
        for (var q = 0; q < actualQueries.length; q++) {
          final scores = [
            for (final doc in actualDocs) _dot(actualQueries[q], doc),
          ];
          for (var d = 0; d < scores.length; d++) {
            maximumScoreError = math.max(
              maximumScoreError,
              (scores[d] -
                      ((expected['scores'] as List)[q][d] as num).toDouble())
                  .abs(),
            );
          }
          top.add(scores.indexOf(scores.reduce(math.max)));
        }
        expect(top, expectedTop);
        expect(top, expected['top1']);
        expect(maximumScoreError, lessThan(0.01));
        final single = await helper.embed(queries.first);
        // Separate single/batch GEMMs differ in their accumulation order.
        for (var i = 0; i < single.length; i++) {
          expect(single[i], closeTo(actualQueries.first[i], 1e-6));
        }
        report['$dimensions'] = {
          'minimum_cosine': minimumCosine,
          'maximum_score_error': maximumScoreError,
          'top1': top,
        };
      }
      final prepared =
          'task: search result | query: ${(corpus['queries'] as List).first['text']}';
      final raw = await engine.embed(prepared, normalize: false);
      final helper = LlamaTextEmbedder(
        engine,
        profile: LlamaEmbeddingProfile.embeddingGemma2,
        normalize: false,
      );
      expect(
        await helper.embed(LlamaEmbeddingText.prepared(prepared)),
        orderedEquals(raw),
      );
      expect(await helper.embed(queries.first), orderedEquals(raw));
      // A missing prefix is a causal control, not an equivalent request.
      final unprefixed = await engine.embed(
        (corpus['queries'] as List).first['text'] as String,
        normalize: false,
      );
      expect(raw, isNot(orderedEquals(unprefixed)));
      print('EG2 retrieval qualification: ${jsonEncode(report)}');
    },
    skip: model == null || referencePath == null
        ? 'Set LLAMADART_EMBEDDINGGEMMA2_MODEL_PATH and LLAMADART_EG2_RETRIEVAL_REFERENCE.'
        : false,
  );
}

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}
