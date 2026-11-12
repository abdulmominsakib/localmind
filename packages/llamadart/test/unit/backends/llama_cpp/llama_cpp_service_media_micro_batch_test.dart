@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _greedy = GenerationParams(maxTokens: 4, temp: 0, topK: 1, seed: 1);
const _imageText = 'abcdefgh';
const _imageCalls = [
  'mtmd_tokenize',
  'mtmd_encode_chunk',
  'mtmd_helper_decode_image_chunk',
];

String _splitWarning(int microBatch) =>
    'llama_cpp_service: the image input has 12 tokens, more than the '
    "context's micro-batch of $microBatch tokens (n_ubatch), so it is "
    'decoded in several non-causal batches, which can reduce accuracy. Load '
    'the model with ModelParams.microBatchSize and ModelParams.batchSize of '
    'at least 12 to decode it in one.';

// Runs the real llama.cpp runtime on the CPU with a stand-in projector whose
// non-causal image decode is a real non-causal llama_decode: one above
// n_ubatch aborts the process on llama.cpp's own assertion.
void main() {
  late Directory dir;
  late LlamaCppService service;
  late FakeMtmd mtmd;
  late int context;
  late List<String> warnings;
  // Token count of each batch the image decode gave llama.cpp.
  late List<int> decoded;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_media_ubatch_');
    writeSyntheticLlamaGguf('${dir.path}/model.gguf');
    File('${dir.path}/mmproj.gguf').writeAsStringSync('GGUF');
    service = LlamaCppService(objectCalls: LlamaCppObjectCalls.upstream)
      ..initializeBackend();
    warnings = [];
    decoded = [];
    LlamaLogger.instance
      ..setLevel(LlamaLogLevel.warn)
      ..setHandler((record) {
        if (record.level == LlamaLogLevel.warn) warnings.add(record.message);
      });
  });

  tearDown(() {
    LlamaLogger.instance
      ..setLevel(LlamaLogLevel.none)
      ..setHandler(null);
    service.dispose();
    mtmd.dispose();
    dir.deleteSync(recursive: true);
  });

  /// Loads the model with a projector whose one image has the 12 tokens of
  /// [_imageText] and a BOS.
  void load({
    required int batchSize,
    required int microBatchSize,
    FakeMtmdChunk chunk = FakeMtmdChunk.nonCausalImage,
    bool chunkEval = true,
  }) {
    final params = ModelParams(
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
      gpuLayers: 0,
      contextSize: 64,
      batchSize: batchSize,
      microBatchSize: microBatchSize,
    );
    final model = service.loadModel('${dir.path}/model.gguf', params);
    context = service.createContext(model, params);
    mtmd = FakeMtmd.install(
      service,
      tokens: service.tokenize(model, _imageText, true),
      chunkEval: chunkEval,
      chunk: chunk,
      decode: (context, batch) {
        decoded.add(batch.n_tokens);
        return llama_decode(context, batch);
      },
    );
    expect(mtmd.tokens, hasLength(12));
    service.createMultimodalContext(model, '${dir.path}/mmproj.gguf');
    mtmd.calls.clear();
    warnings.clear();
  }

  Future<List<int>> generate(String prompt, {bool image = false}) async {
    final cancel = calloc<Int8>();
    try {
      final chunks = await service
          .generate(
            context,
            prompt,
            _greedy,
            cancel.address,
            parts: image ? mtmd.parts : null,
          )
          .toList();
      return [for (final chunk in chunks) ...chunk];
    } finally {
      calloc.free(cancel);
    }
  }

  test('a non-causal image above a micro-batch below the batch is a typed '
      'error before any evaluation, and the context still generates', () async {
    load(batchSize: 16, microBatchSize: 8);

    await expectLater(
      generate('<__media__>', image: true),
      throwsA(
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          'The image input has 12 tokens, more than the context\'s '
              'micro-batch of 8 tokens (n_ubatch), and this projector '
              'decodes it with non-causal attention, which llama.cpp cannot '
              'split across micro-batches. Raise ModelParams.microBatchSize '
              'to at least 12, and ModelParams.batchSize with it, or pass a '
              'smaller image if the projector sizes its output by the input.',
        ),
      ),
    );

    expect(mtmd.calls, ['mtmd_tokenize']);
    expect(decoded, isEmpty);
    expect(warnings, isEmpty);
    await generate('ab');
  });

  for (final (name, batchSize, microBatchSize) in [
    ('equal to the batch', 8, 8),
    ('left unset under a smaller batch', 8, 0),
    ('set above the batch', 8, 16),
  ]) {
    test('a non-causal image above a micro-batch $name is decoded in '
        'batch-sized non-causal pieces with one warning', () async {
      load(batchSize: batchSize, microBatchSize: microBatchSize);

      await generate('<__media__>', image: true);

      expect(mtmd.calls, _imageCalls);
      expect(decoded, [8, 4]);
      expect(warnings, [_splitWarning(8)]);
    });
  }

  test('a later turn that holds the split image again answers as the first '
      'did, with one warning a request', () async {
    load(batchSize: 8, microBatchSize: 8);

    final first = await generate('<__media__>', image: true);
    final second = await generate('<__media__>', image: true);
    await generate('ab');

    expect(second, first);
    expect(decoded, [8, 4, 8, 4]);
    expect(warnings, [_splitWarning(8), _splitWarning(8)]);
  });

  test('a non-causal image of exactly the micro-batch is decoded in one '
      'pass', () async {
    load(batchSize: 16, microBatchSize: 12);

    await generate('<__media__>', image: true);

    expect(mtmd.calls, _imageCalls);
    expect(decoded, [12]);
    expect(warnings, isEmpty);
  });

  test('a causal image above the micro-batch is decoded', () async {
    load(batchSize: 8, microBatchSize: 4, chunk: FakeMtmdChunk.causalImage);

    await generate('<__media__>', image: true);

    expect(mtmd.calls, _imageCalls);
    expect(decoded, [8, 4]);
    expect(warnings, isEmpty);
  });

  test('a runtime without the chunk-level functions evaluates the prompt '
      'unchecked', () async {
    load(batchSize: 8, microBatchSize: 8, chunkEval: false);

    await generate('<__media__>', image: true);

    expect(mtmd.calls, ['mtmd_tokenize', 'mtmd_helper_eval_chunks']);
    expect(warnings, isEmpty);
  });
}
