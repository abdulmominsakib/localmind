@TestOn('vm')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_c_api_version.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_embedding.dart';
import 'package:test/test.dart';

import '../../support/embedding_contract.dart';
import '../../support/suite_system_temp.dart';
import 'multimodal_embedding_litert_inputs.dart';

void main() {
  final temp = useSuiteSystemTemp();
  final model = Platform.environment['LITERT_LM_EMBEDDING_MODEL'];
  final gpu = Platform.environment['LITERT_LM_EMBEDDING_BACKEND'] == 'gpu';
  final candidate = Platform.environment['LITERT_LM_V1_LIBRARY'];
  setUpAll(() async {
    if (candidate == null) return;
    for (final entry in {
      'LITERT_LM_V1_LIBRARY': candidate,
      'LITERT_LM_EMBEDDING_MODEL': model,
    }.entries) {
      final expected = Platform.environment['${entry.key}_SHA256'];
      expect(expected, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(entry.value, isNotNull);
      expect(
        (await sha256.bind(File(entry.value!).openRead()).first).toString(),
        expected,
      );
    }
  });
  Future<LlamaEngine> createEngine() async {
    if (candidate == null) return LlamaEngine(LlamaBackend());
    final port = ReceivePort();
    try {
      runLiteRtLmWorkerForTesting(
        port.sendPort,
        LiteRtLmService(
          runtimeClientFactory: () {
            final library = DynamicLibrary.open(candidate);
            return LiteRtLmV1RuntimeClient(
              library,
              inProcessLiteRtAbiVersion: readLiteRtLmInProcessLiteRtAbiVersion(
                library,
              ),
            );
          },
        ),
        exitOnDispose: false,
      );
      return LlamaEngine(
        LiteRtLmBackend(initialSendPort: await port.first as SendPort),
      );
    } finally {
      port.close();
    }
  }

  test(
    'unload and dispose cancel a sixty-item native batch between items',
    () async {
      for (final dispose in [false, true]) {
        final engine = await createEngine();
        addTearDown(engine.dispose);
        await engine.loadModel(
          model!,
          modelParams: ModelParams(
            liteRtLmEmbeddingEngine: true,
            device: ComputeDevice.cpu,
            contextSize: 1024,
            liteRtLmCacheDir: temp().path,
          ),
        );
        await engine.embeddingCapabilities;
        final input = liteRtEmbeddingInputs()['checker']!;
        final rejected = expectLater(
          engine.embedContentBatch(List.filled(60, input)),
          throwsA(isA<LlamaInferenceException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (dispose) {
          await engine.dispose();
        } else {
          await engine.unloadModel();
          await engine.loadModel(
            model,
            modelParams: ModelParams(
              liteRtLmEmbeddingEngine: true,
              device: ComputeDevice.cpu,
              contextSize: 1024,
              liteRtLmCacheDir: temp().path,
            ),
          );
          expect(await engine.embed('reusable'), hasLength(768));
        }
        await rejected;
      }
    },
    skip: model == null ? 'Set LITERT_LM_EMBEDDING_MODEL.' : false,
  );
  test('repeated CPU embeddings of every input are bit-identical '
      '(litert-lm-native#82, llamadart#1340)', () async {
    final engine = await createEngine();
    addTearDown(engine.dispose);
    await engine.loadModel(
      model!,
      modelParams: ModelParams(
        liteRtLmEmbeddingEngine: true,
        device: ComputeDevice.cpu,
        contextSize: 1024,
        liteRtLmCacheDir: temp().path,
      ),
    );
    for (final entry in liteRtEmbeddingInputs().entries) {
      final first = await engine.embedContent(entry.value, normalize: false);
      for (var i = 1; i < 10; i++) {
        expect(
          await engine.embedContent(entry.value, normalize: false),
          orderedEquals(first),
          reason: '${entry.key} call $i',
        );
      }
    }
  }, skip: model == null ? 'Set LITERT_LM_EMBEDDING_MODEL.' : false);
  test('LiteRT embedding-only model text/media/batch/limits/reuse', () async {
    final engine = await createEngine();
    addTearDown(engine.dispose);
    await engine.loadModel(
      model!,
      modelParams: ModelParams(
        liteRtLmEmbeddingEngine: true,
        device: gpu ? ComputeDevice.gpu : ComputeDevice.cpu,
        contextSize: 1024,
        liteRtLmCacheDir: temp().path,
      ),
    );
    final capabilities = await engine.embeddingCapabilities;
    expect(
      [capabilities.text, capabilities.image, capabilities.audio],
      [true, true, true],
    );
    final inputs = liteRtEmbeddingInputs();
    final vectors = <String, List<double>>{};
    for (final entry in inputs.entries) {
      final normalized = await engine.embedContent(entry.value);
      final raw = await engine.embedContent(entry.value, normalize: false);
      expect(normalized, hasLength(768));
      expect(raw, hasLength(768));
      final norm = math.sqrt(
        normalized.fold<double>(0, (sum, v) => sum + v * v),
      );
      expect(norm, closeTo(1, 1e-5));
      expect(embeddingDistance(normalized, raw).cosine, closeTo(1, 1e-5));
      vectors[entry.key] = normalized;
    }
    expect(
      embeddingDistance(vectors['black']!, vectors['checker']!).cosine,
      lessThan(0.999),
    );
    expect(
      embeddingDistance(vectors['silence']!, vectors['tone']!).cosine,
      lessThan(0.999),
    );
    final batch = await engine.embedContentBatch(
      inputs.values.toList().reversed.toList(),
    );
    for (var i = 0; i < batch.length; i++) {
      expect(
        embeddingDistance(
          vectors.values.toList().reversed.toList()[i],
          batch[i],
        ).relL2,
        lessThan(1e-5),
      );
    }
    expect(await engine.embedContentBatch([]), isEmpty);
    final text = await engine.embed('hello world');
    expect(embeddingDistance(text, vectors['text']!).relL2, lessThan(1e-5));
    await expectAdjacentTextEmbeddingEquivalence(engine.embedContent);
    await expectAdjacentTextEmbeddingEquivalence(
      engine.embedContent,
      before: inputs['checker']!.parts,
      after: inputs['tone']!.parts,
    );
    await expectLater(
      engine.generate('chat').toList(),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    await expectLater(
      engine.embed(List.filled(3000, 'hello').join(' ')),
      throwsA(isA<LlamaInferenceException>()),
    );
    var returnedPartial = false;
    await expectLater(
      engine
          .embedBatch(['hello world', List.filled(3000, 'hello').join(' ')])
          .then((vectors) {
            returnedPartial = true;
            return vectors;
          }),
      throwsA(isA<LlamaInferenceException>()),
    );
    expect(returnedPartial, isFalse);
    final pending = engine.embedContent(inputs['mixed']!);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    engine.cancelGeneration();
    await expectLater(pending, throwsA(isA<LlamaInferenceException>()));
    expect(await engine.embed('hello world'), hasLength(768));
    final output = Platform.environment['LITERT_LM_EMBEDDING_OUTPUT'];
    if (output != null) {
      final dir = Directory(output)..createSync(recursive: true);
      File(
        '${dir.path}/native-${gpu ? 'gpu' : 'cpu'}.json',
      ).writeAsStringSync(jsonEncode(vectors));
      for (final entry in inputs.entries) {
        final parts = prepareLiteRtLmEmbedding(entry.value);
        for (var i = 0; i < parts.length; i++) {
          File(
            '${dir.path}/${entry.key}-$i-${parts[i].type}.bin',
          ).writeAsBytesSync(parts[i].bytes);
        }
      }
    }
    await engine.unloadModel();
    await engine.loadModel(
      model,
      modelParams: ModelParams(
        device: ComputeDevice.cpu,
        liteRtLmCacheDir: temp().path,
      ),
    );
    expect((await engine.embeddingCapabilities).text, isFalse);
    await expectLater(
      engine.embed('x'),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  }, skip: model == null ? 'Set LITERT_LM_EMBEDDING_MODEL.' : false);
}
