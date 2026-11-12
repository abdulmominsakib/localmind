@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

const _upstream = '620d2225cc436ab0b001e3200e590e3b286ef9ab';
const _corpus = 'test/fixtures/reranking/cases.json';

void main() {
  useSuiteSystemTemp();
  final env = Platform.environment;
  final oracle = env['LLAMADART_RERANK_ORACLE'];
  final server = env['LLAMADART_RERANK_SERVER'];
  final gpu = env['LLAMADART_RERANK_BACKEND'] == 'metal';
  for (final (family, variable, hash, named) in [
    (
      'qwen3',
      'LLAMADART_RERANK_QWEN_MODEL',
      '22c9979ce4fbcdc5acdc310c6641c32797eff1aa980b8f7a2db8a8ea23429a48',
      true,
    ),
    (
      'bge',
      'LLAMADART_RERANK_BGE_MODEL',
      'a43c7c9b11a4c1517e5bf95151960e1621d1b72f7a493364b01e386cf1aaa1d3',
      false,
    ),
    (
      'jina',
      'LLAMADART_RERANK_JINA_MODEL',
      'ad9f450c1053a431e2e3746d1f9f7768fb9183cf0796e046983a3449dca093c2',
      false,
    ),
  ]) {
    final model = env[variable];
    test(
      '$family full-class and upstream server parity on ${gpu ? 'Metal' : 'CPU'}',
      () async {
        expect(
          (await sha256.bind(File(model!).openRead()).first).toString(),
          hash,
        );
        final corpus = jsonDecode(File(_corpus).readAsStringSync()) as Map;
        final version = await Process.run(server!, ['--version']);
        expect('${version.stdout}${version.stderr}', contains(_upstream));
        final raw = await Process.run(oracle!, [
          model,
          _corpus,
          gpu ? 'metal' : 'cpu',
        ]);
        expect(raw.exitCode, 0, reason: raw.stderr.toString());
        final reference = jsonDecode(raw.stdout.toString()) as Map;
        expect(reference['upstream_commit'], _upstream);
        final helper = await LlamaReranker.load(
          LlamaModel(ModelSource.path(model)),
          params: LlamaCppModelParams(
            contextSize: 2048,
            batchSize: 2048,
            microBatchSize: 2048,
            maxParallelSequences: 4,
            numberOfThreads: 4,
            numberOfThreadsBatch: 4,
            preferredBackend: gpu ? GpuBackend.metal : GpuBackend.cpu,
            gpuLayers: gpu ? 99 : 0,
          ),
        );
        addTearDown(helper.dispose);
        final engine = helper.engine;
        final activeBackend = await engine.getBackendName();
        expect(activeBackend.toLowerCase(), contains(gpu ? 'metal' : 'cpu'));
        final capabilities = await helper.capabilities;
        expect(capabilities.isSupported, isTrue);
        expect(capabilities.classifierLabels, reference['labels']);
        expect(capabilities.classifierLabels, hasLength(named ? 2 : 1));
        final metadata = await engine.getMetadata();
        expect(metadata.containsKey('tokenizer.chat_template.rerank'), named);
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = socket.port;
        await socket.close();
        final process = await Process.start(server, [
          '-m',
          model,
          '--reranking',
          '--host',
          '127.0.0.1',
          '--port',
          '$port',
          '-c',
          '2048',
          '-b',
          '2048',
          '-ub',
          '2048',
          '-ngl',
          gpu ? '99' : '0',
          if (!gpu) ...['--no-op-offload', '--no-kv-offload', '-fa', 'off'],
          '-t',
          '4',
          '-tb',
          '4',
          '-np',
          '1',
          '--no-warmup',
        ]);
        final log = StringBuffer();
        final stdout = process.stdout.transform(utf8.decoder).listen(log.write);
        final stderr = process.stderr.transform(utf8.decoder).listen(log.write);
        final client = HttpClient();
        addTearDown(() async {
          client.close(force: true);
          process.kill();
          await process.exitCode;
          await stdout.cancel();
          await stderr.cancel();
        });
        var ready = false;
        for (var i = 0; i < 300; i++) {
          try {
            final response = await (await client.getUrl(
              Uri.parse('http://127.0.0.1:$port/health'),
            )).close();
            await response.drain<void>();
            if (response.statusCode == 200) {
              ready = true;
              break;
            }
          } on SocketException {
            /* Server is still starting. */
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(ready, isTrue, reason: log.toString());
        var maxError = 0.0;
        var maxSingleError = 0.0;
        var maxBatchSingleDrift = 0.0;
        final cases = corpus['cases'] as List;
        for (var c = 0; c < cases.length; c++) {
          final item = cases[c] as Map;
          final query = item['query'] as String;
          final documents = (item['documents'] as List).cast<String>();
          final expectedCase = (reference['cases'] as List)[c] as Map;
          final expected = expectedCase['grouped'] as List;
          final expectedSingle = expectedCase['single'] as List;
          final batch = await helper.rerank(query, documents);
          final singles = <int, LlamaRerankResult>{};
          for (final result in batch) {
            final values = (expected[result.index] as List).cast<num>();
            for (var j = 0; j < values.length; j++) {
              final error = (result.classifierScores[j] - values[j]).abs();
              if (error > maxError) maxError = error;
              expect(
                result.classifierScores[j],
                closeTo(values[j], 2e-4),
                reason: '${item['id']} document ${result.index} class $j',
              );
            }
            final single = (await helper.rerank(query, [
              documents[result.index],
            ])).single;
            singles[result.index] = single;
            for (var j = 0; j < values.length; j++) {
              final error =
                  (single.classifierScores[j] -
                          ((expectedSingle[result.index] as List)[j] as num))
                      .abs();
              if (error > maxSingleError) maxSingleError = error;
              final drift =
                  (single.classifierScores[j] - result.classifierScores[j])
                      .abs();
              if (drift > maxBatchSingleDrift) maxBatchSingleDrift = drift;
              expect(
                single.classifierScores[j],
                closeTo((expectedSingle[result.index] as List)[j] as num, 2e-4),
              );
            }
          }
          final request = await client.postUrl(
            Uri.parse('http://127.0.0.1:$port/rerank'),
          );
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode({'query': query, 'documents': documents}));
          final response = await request.close();
          final body = await utf8.decoder.bind(response).join();
          expect(response.statusCode, 200, reason: body);
          final upstream = (jsonDecode(body) as Map)['results'] as List;
          for (final row in upstream.cast<Map>()) {
            final index = row['index'] as int;
            expect(
              singles[index]!.score,
              closeTo(row['relevance_score'] as num, 2e-4),
            );
          }
          // Compare ordering except numerical ties, whose order is unspecified upstream.
          for (var i = 1; i < batch.length; i++) {
            expect(
              batch[i - 1].score + 2e-4,
              greaterThanOrEqualTo(batch[i].score),
            );
          }
        }
        await expectLater(
          engine.embed('do not reinterpret class scores as embeddings'),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await expectLater(
          helper.rerank('q', ['valid', 'long input ' * 5000]),
          throwsA(isA<LlamaInferenceException>()),
        );
        final cancelled = helper.rerank('q', ['doc']);
        helper.cancel();
        await expectLater(cancelled, throwsA(isA<LlamaInferenceException>()));
        expect(await helper.rerank('q', ['doc']), hasLength(1));
        await engine.dispose();
        expect((await helper.capabilities).isSupported, isFalse);
        final receipt = {
          'family': family,
          'backend': gpu ? 'metal' : 'cpu',
          'active_backend': activeBackend,
          'model_sha256': hash,
          'upstream_commit': _upstream,
          'corpus_sha256': sha256
              .convert(File(_corpus).readAsBytesSync())
              .toString(),
          'cases': cases.length,
          'max_absolute_grouped_class_score_error': maxError,
          'max_absolute_single_class_score_error': maxSingleError,
          'max_batch_single_drift_informational': maxBatchSingleDrift,
        };
        final outputDir = env['LLAMADART_RERANK_EVIDENCE_DIR'];
        if (outputDir != null) {
          Directory(outputDir).createSync(recursive: true);
          File(
            '$outputDir/$family-${gpu ? 'metal' : 'cpu'}.json',
          ).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(receipt),
          );
        }
        print(jsonEncode(receipt));
      },
      skip: model == null || oracle == null || server == null
          ? 'Set the exact models, upstream oracle and server paths per doc/native_reranking.md.'
          : false,
    );
  }
}
