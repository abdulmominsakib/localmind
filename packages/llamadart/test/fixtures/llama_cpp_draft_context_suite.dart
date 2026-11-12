// Subprocess suite run by llama_cpp_service_speculative_draft_test.dart. It
// drives the real llama.cpp runtime on the CPU, where a missing draft block
// rejection aborts the process at a GGML_ASSERT; in a child process that fails
// one test instead of ending the whole test runner.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:test/test.dart';

import '../support/synthetic_embedding_gguf.dart';

Matcher _argumentError(String message, {String name = 'draftMicroBatchSize'}) =>
    throwsA(
      isA<LlamaArgumentException>()
          .having((error) => error.name, 'name', name)
          .having((error) => error.message, 'message', contains(message)),
    );

ModelParams _contextParams({int microBatchSize = 32}) => ModelParams(
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  gpuLayers: 0,
  contextSize: 64,
  batchSize: 64,
  microBatchSize: microBatchSize,
);

void main() {
  // A draft-simple session whose synthetic draft model is the target's own
  // file.
  group('draft context', () {
    late Directory dir;
    late LlamaCppService service;
    late int model;
    late int context;
    late List<int> draftMicroBatches;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('llamadart_draft_ubatch_');
      writeSyntheticLlamaGguf('${dir.path}/model.gguf');
      service = LlamaCppService(objectCalls: LlamaCppObjectCalls.upstream)
        ..initializeBackend();
      model = service.loadModel('${dir.path}/model.gguf', _contextParams());
      context = service.createContext(model, _contextParams());
      draftMicroBatches = [];
      service.debugOnSpeculativeDraftContextForTesting = (draft) =>
          draftMicroBatches.add(llama_n_ubatch(draft));
    });

    tearDown(() {
      service.dispose();
      dir.deleteSync(recursive: true);
    });

    Future<List<int>> generate(
      int? draftMicroBatchSize, {
      SpeculativeDecodingConfig? speculative,
      int? targetContext,
    }) async {
      final cancel = calloc<Int8>();
      try {
        final bytes = <int>[];
        await for (final chunk in service.generate(
          targetContext ?? context,
          'abababab',
          GenerationParams(
            maxTokens: 12,
            temp: 0,
            topK: 1,
            seed: 1,
            penalty: 1,
            speculativeDecodingConfig:
                speculative ??
                SpeculativeDecodingConfig.draftSimple(
                  draftModel: ModelSource.path('${dir.path}/model.gguf'),
                  draftTokenMax: 4,
                  draftMicroBatchSize: draftMicroBatchSize,
                ),
          ),
          cancel.address,
        )) {
          bytes.addAll(chunk);
        }
        return bytes;
      } finally {
        calloc.free(cancel);
      }
    }

    test('runs the draft context on the capped default threads', () async {
      final capped = LlamaCppService(
        objectCalls: LlamaCppObjectCalls.upstream,
        availableCores: 2,
      )..initializeBackend();
      addTearDown(capped.dispose);
      final threads = <List<int>>[];
      capped.debugOnSpeculativeDraftContextForTesting = (draft) =>
          threads.add([llama_n_threads(draft), llama_n_threads_batch(draft)]);
      const params = ModelParams(gpuLayers: 0, contextSize: 64);
      final handle = capped.loadModel('${dir.path}/model.gguf', params);
      final cancel = calloc<Int8>();
      addTearDown(() => calloc.free(cancel));
      await capped
          .generate(
            capped.createContext(handle, params),
            'abab',
            GenerationParams(
              maxTokens: 2,
              temp: 0,
              topK: 1,
              seed: 1,
              penalty: 1,
              speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
                draftModel: ModelSource.path('${dir.path}/model.gguf'),
                draftTokenMax: 2,
              ),
            ),
            cancel.address,
          )
          .drain<void>();

      expect(threads, [
        [2, 2],
      ]);
    });

    String liliCorrDraft(Map<String, int> metadata) {
      final path = '${dir.path}/lilicorr_${metadata.length}.gguf';
      writeSyntheticLlamaGguf(path, uint32Metadata: metadata);
      return path;
    }

    test('takes the draft micro-batch size, and the target size unset, '
        'with the same output', () async {
      final unset = await generate(null);
      final reduced = await generate(2);

      expect(draftMicroBatches, [32, 2]);
      expect(unset, isNotEmpty);
      expect(reduced, unset);
    });

    test("rejects a size above the context's logical batch before creating "
        'a session', () async {
      await expectLater(generate(65), _argumentError('(64)'));
      expect(draftMicroBatches, isEmpty);
    });

    // A Llama draft cannot start a DFlash session, so the block tests cover
    // only rejections, which must come before llama.cpp aborts on the block.
    test('reads the LiliCorr block size from the draft model before creating '
        'a session', () async {
      for (final (metadata, size, blockSize) in [
        (const {'lilicorr.candidate_topk': 4, 'dflash.block_size': 8}, 7, 8),
        (const {'lilicorr.candidate_topk': 4}, 15, 16),
      ]) {
        await expectLater(
          generate(
            null,
            speculative: SpeculativeDecodingConfig.draftDflash(
              draftModel: ModelSource.path(liliCorrDraft(metadata)),
              draftTokenMax: 4,
              draftMicroBatchSize: size,
            ),
          ),
          _argumentError('dflash.block_size ($blockSize)'),
          reason: '$metadata',
        );
      }
      expect(draftMicroBatches, isEmpty);
    });

    test('rejects an inherited target micro-batch below the draft block '
        'before creating a session', () async {
      final smallContext = service.createContext(
        model,
        _contextParams(microBatchSize: 3),
      );
      await expectLater(
        generate(
          null,
          targetContext: smallContext,
          speculative: SpeculativeDecodingConfig.draftDspark(
            draftModel: ModelSource.path('${dir.path}/model.gguf'),
            draftTokenMax: 4,
          ),
        ),
        _argumentError('the 4-token draft block', name: 'microBatchSize'),
      );
      await expectLater(
        generate(
          null,
          speculative: SpeculativeDecodingConfig.draftDflash(
            draftModel: ModelSource.path(
              liliCorrDraft(const {
                'lilicorr.candidate_topk': 4,
                'dflash.block_size': 33,
              }),
            ),
            draftTokenMax: 4,
          ),
        ),
        _argumentError('dflash.block_size (33)', name: 'microBatchSize'),
      );
      expect(draftMicroBatches, isEmpty);
    });
  });
}
