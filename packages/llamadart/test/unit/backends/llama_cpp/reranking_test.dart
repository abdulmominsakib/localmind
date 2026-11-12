@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:test/test.dart';

import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_embedding_gguf.dart';

void main() {
  late Directory dir;
  late LlamaCppService service;
  late RecordingExitTeardown recorder;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('reranking_');
    recorder = RecordingExitTeardown(
      ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
      recordTokenRows: true,
    );
    service = LlamaCppService(
      objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
    )..initializeBackend();
  });
  tearDown(() {
    service.dispose();
    expect(recorder.unfreed, isEmpty);
    dir.deleteSync(recursive: true);
  });
  int load({
    String? template,
    int slots = 2,
    int microBatch = 128,
    int? pooling = 4,
  }) {
    final path = '${dir.path}/model.gguf';
    writeSyntheticModernBertGguf(
      path,
      poolingType: pooling,
      classifierLabels: ['yes', 'no'],
      rerankTemplate: template,
    );
    final params = ModelParams(
      gpuLayers: 0,
      contextSize: 128,
      batchSize: 128,
      microBatchSize: microBatch,
      maxParallelSequences: slots,
    );
    final model = service.loadModel(path, params);
    return service.createContext(model, params);
  }

  test('probes loaded RANK context; ordinary model remains unsupported', () {
    expect(service.getRerankingCapabilities(-1).isSupported, isFalse);
    final context = load(pooling: 1);
    expect(service.getRerankingCapabilities(context).isSupported, isFalse);
    expect(
      () => service.rerank(context, 'q', ['d']),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(recorder.decodedTokens, isEmpty);
  });
  test(
    'named placeholders parse special tokens and independent sequence IDs',
    () {
      final context = load(template: '<s>{query}</s>{document}</s>');
      final support = service.getRerankingCapabilities(context);
      expect(support.classifierLabels, ['yes', 'no']);
      expect(support.maxParallelSequences, 2);
      final output = service.rerank(context, 'q', ['a', 'b']);
      expect(output.scores, hasLength(2));
      expect(
        output.scores.every(
          (row) => row.length == 2 && row.every((x) => x.isFinite),
        ),
        isTrue,
      );
      expect(recorder.decodedTokenIds.single, [
        1,
        229,
        153,
        132,
        116,
        2,
        229,
        153,
        132,
        100,
        2,
        1,
        229,
        153,
        132,
        116,
        2,
        229,
        153,
        132,
        101,
        2,
      ]);
      expect(recorder.decodedSequenceIds.single, [
        ...List.filled(11, 0),
        ...List.filled(11, 1),
      ]);
      expect(
        recorder.calls.where((c) => c == 'llama_dart_decode'),
        hasLength(1),
      );
      expect(recorder.calls, contains('llama_dart_synchronize'));
      expect(
        () => service.embed(context, 'q'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );
  test(
    'explicit classifier load creates RANK without changing the normal context',
    () {
      final ordinary = load(pooling: 1);
      final params = const ModelParams(
        gpuLayers: 0,
        contextSize: 128,
        batchSize: 128,
        microBatchSize: 128,
        maxParallelSequences: 2,
      );
      // The fixture is the first model allocated by this service.
      final explicit = service.createRerankingContext(1, params);
      expect(service.getRerankingCapabilities(ordinary).isSupported, isFalse);
      expect(service.getRerankingCapabilities(explicit).isSupported, isTrue);
      expect(service.rerank(explicit, 'q', ['a']).scores.single, hasLength(2));
    },
  );
  test('explicit load rejects a normal model without a classifier head', () {
    final path = '${dir.path}/ordinary.gguf';
    writeSyntheticLlamaGguf(path);
    const params = ModelParams(gpuLayers: 0, contextSize: 64);
    final model = service.loadModel(path, params);
    expect(
      () => service.createRerankingContext(model, params),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
  test(
    'owning public loader handles and disposes a verified non-RANK classifier',
    () async {
      final path = '${dir.path}/owning.gguf';
      writeSyntheticModernBertGguf(
        path,
        poolingType: 1,
        classifierLabels: ['positive'],
      );
      final helper = await LlamaReranker.load(
        LlamaModel(ModelSource.path(path)),
        params: const LlamaCppModelParams(
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
          contextSize: 128,
          batchSize: 128,
          microBatchSize: 128,
        ),
      );
      expect((await helper.capabilities).isSupported, isTrue);
      expect(
        (await helper.rerank('q', ['d'])).single.classifierScores,
        hasLength(1),
      );
      await helper.dispose();
      await helper.dispose();
      expect(helper.engine.isDisposed, isTrue);
    },
  );
  test('fallback vocabulary framing treats user special strings literally', () {
    final context = load(slots: 1);
    service.rerank(context, '<s>', ['</s>']);
    // Synthetic SentencePiece defaults: BOS enabled, EOS disabled.
    expect(recorder.decodedTokenIds.single, [
      1,
      229,
      153,
      132,
      63,
      118,
      65,
      229,
      153,
      132,
      63,
      50,
      118,
      65,
    ]);
  });
  test('all pairs preflight before inference or synchronization', () {
    final context = load(template: '{query}{document}', microBatch: 16);
    expect(
      () => service.rerank(context, 'q', ['a', 'long ' * 20]),
      throwsA(isA<LlamaInferenceException>()),
    );
    expect(recorder.decodedTokens, isEmpty);
    expect(recorder.calls.where((c) => c == 'llama_dart_synchronize'), isEmpty);
    expect(service.rerank(context, 'q', ['a']).scores, hasLength(1));
  });
  test(
    'batch, split groups and sequential scoring agree with identical outputs',
    () {
      final context = load(template: '{query}{document}');
      final batch = service.rerank(context, 'q', ['a', 'b', 'a']);
      final sequential = [
        for (final doc in ['a', 'b', 'a'])
          service.rerank(context, 'q', [doc]).scores.single,
      ];
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 2; j++) {
          expect(batch.scores[i][j], closeTo(sequential[i][j], 1e-5));
        }
      }
      for (var j = 0; j < 2; j++) {
        expect(batch.scores[0][j], closeTo(batch.scores[2][j], 1e-6));
      }
    },
  );
  test(
    'cancellation before dispatch and after a native pass returns no partial scores, then reuses context',
    () {
      final context = load(template: '{query}{document}', slots: 1);
      final flag = calloc<Int8>()..value = 1;
      addTearDown(() => calloc.free(flag));
      expect(
        () => service.rerank(context, 'q', ['a'], cancelToken: flag),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(recorder.decodedTokens, isEmpty);
      flag.value = 0;
      recorder.onCall = (name) {
        if (name == 'llama_dart_decode') flag.value = 1;
      };
      expect(
        () => service.rerank(context, 'q', ['a', 'b'], cancelToken: flag),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(recorder.decodedTokens, hasLength(1));
      recorder.onCall = null;
      flag.value = 0;
      expect(service.rerank(context, 'q', ['a']).scores, hasLength(1));
    },
  );
}
