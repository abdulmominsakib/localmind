@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/synthetic_embedding_gguf.dart';

void main() {
  test('native worker preserves context overflow and remains usable', () async {
    final dir = Directory.systemTemp.createTempSync(
      'typed_embedding_overflow_',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = writeSyntheticLlamaGguf(
      '${dir.path}/model.gguf',
      poolingType: 3,
    );
    final engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(file.path)),
      params: const ModelParams(
        contextSize: 256,
        batchSize: 256,
        microBatchSize: 256,
        gpuLayers: 0,
        device: ComputeDevice.cpu,
      ),
    );
    addTearDown(engine.dispose);
    for (final content in [false, true]) {
      final text = 'a' * 512;
      await expectLater(
        content
            ? engine.embedContent(LlamaEmbeddingInput([LlamaTextContent(text)]))
            : engine.embed(text),
        throwsA(
          isA<LlamaEmbeddingInputTooLongException>()
              .having((e) => e.maxInputTokens, 'capacity', 256)
              .having((e) => e.actualTokens, 'input tokens', greaterThan(256)),
        ),
      );
    }
    expect(await engine.embed('short'), hasLength(16));
  });

  test('micro-batch overflow reports its own effective limit', () async {
    final dir = Directory.systemTemp.createTempSync('typed_embedding_batch_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = writeSyntheticModernBertGguf(
      '${dir.path}/model.gguf',
      poolingType: 1,
    );
    final engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(file.path)),
      params: const ModelParams(
        contextSize: 1024,
        batchSize: 1024,
        microBatchSize: 64,
        gpuLayers: 0,
        device: ComputeDevice.cpu,
      ),
    );
    addTearDown(engine.dispose);
    await expectLater(
      engine.embed('a' * 96),
      throwsA(
        isA<LlamaEmbeddingInputTooLongException>()
            .having((e) => e.maxInputTokens, 'capacity', 64)
            .having((e) => e.actualTokens, 'tokens', greaterThan(64)),
      ),
    );
    expect(await engine.embed('short'), hasLength(16));
  });
}
