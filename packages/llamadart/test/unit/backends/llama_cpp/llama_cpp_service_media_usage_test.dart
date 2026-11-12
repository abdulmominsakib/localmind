@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(gpuLayers: 0, contextSize: 64);
const _greedy = GenerationParams(maxTokens: 1, temp: 0, topK: 1, seed: 1);
const _mediaText = 'abcdefgh';
const _mediaTokens = 40;

// Runs the real llama.cpp runtime on the CPU with a stand-in projector whose
// image chunk reports more tokens than the positions it evaluates, as an
// M-RoPE projector's image does.
void main() {
  late Directory dir;
  late LlamaCppService service;
  late int model;
  late int context;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_media_usage_');
    writeSyntheticLlamaGguf('${dir.path}/model.gguf');
    File('${dir.path}/mmproj.gguf').writeAsStringSync('GGUF');
    service = LlamaCppService(objectCalls: LlamaCppObjectCalls.upstream)
      ..initializeBackend();
    model = service.loadModel('${dir.path}/model.gguf', _params);
    context = service.createContext(model, _params);
  });

  tearDown(() {
    service.dispose();
    dir.deleteSync(recursive: true);
  });

  FakeMtmd install({required bool chunkEval, int chunkCount = 1}) {
    final fake = FakeMtmd.install(
      service,
      tokens: service.tokenize(model, _mediaText, true),
      chunkEval: chunkEval,
      chunk: FakeMtmdChunk.causalImage,
      chunkTokenCount: _mediaTokens,
      chunkCount: chunkCount,
    );
    addTearDown(fake.dispose);
    service.createMultimodalContext(model, '${dir.path}/mmproj.gguf');
    return fake;
  }

  Future<int?> promptTokensAfter(
    String prompt, {
    FakeMtmd? media,
    bool cancelled = false,
  }) async {
    final cancel = calloc<Int8>()..value = cancelled ? 1 : 0;
    try {
      await service
          .generate(
            context,
            prompt,
            _greedy,
            cancel.address,
            parts: media?.parts,
          )
          .drain<void>();
    } finally {
      calloc.free(cancel);
    }
    return service.lastGenerationTokenCounts(context)?.promptTokens;
  }

  test('reports the media chunk tokens, not its positions', () async {
    final fake = install(chunkEval: true);

    expect(await promptTokensAfter('<__media__>', media: fake), _mediaTokens);
    expect(fake.evaluations, 1);
  });

  test('sums the tokens of every media chunk', () async {
    final fake = install(chunkEval: true, chunkCount: 2);

    expect(
      await promptTokensAfter('<__media__>', media: fake),
      2 * _mediaTokens,
    );
    expect(fake.evaluations, 2);
  });

  test('reports no tokens for a media prompt cancelled before its first '
      'chunk', () async {
    final fake = install(chunkEval: true);

    expect(
      await promptTokensAfter('<__media__>', media: fake, cancelled: true),
      0,
    );
    expect(fake.evaluations, 0);
  });

  test('falls back to the positions without chunk-level functions', () async {
    final fake = install(chunkEval: false);

    expect(
      await promptTokensAfter('<__media__>', media: fake),
      service.tokenize(model, _mediaText, true).length,
    );
    expect(fake.calls, contains('mtmd_helper_eval_chunks'));
  });

  test('reports the tokens of a text prompt', () async {
    install(chunkEval: true);

    expect(
      await promptTokensAfter(_mediaText),
      service.tokenize(model, _mediaText, true).length,
    );
  });
}
