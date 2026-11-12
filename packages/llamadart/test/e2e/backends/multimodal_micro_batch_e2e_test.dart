@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

/// An image whose projector decodes it non-causally against a context whose
/// micro-batch is smaller than the image, as in issue #958.
///
/// Set `MULTIMODAL_MICRO_BATCH_MODEL` to a chat GGUF whose projector is
/// non-causal (Gemma 3, or a Gemma 4 model other than E2B and E4B) and
/// `MULTIMODAL_MICRO_BATCH_MMPROJ` to that projector.
/// `MULTIMODAL_MICRO_BATCH_BACKEND` is a `GpuBackend` name and defaults to
/// `cpu`.
void main() {
  final modelPath = Platform.environment['MULTIMODAL_MICRO_BATCH_MODEL'] ?? '';
  final mmprojPath =
      Platform.environment['MULTIMODAL_MICRO_BATCH_MMPROJ'] ?? '';
  final backend = GpuBackend.values.byName(
    Platform.environment['MULTIMODAL_MICRO_BATCH_BACKEND'] ?? 'cpu',
  );
  final skip = modelPath.isEmpty || mmprojPath.isEmpty
      ? 'Set MULTIMODAL_MICRO_BATCH_MODEL and MULTIMODAL_MICRO_BATCH_MMPROJ '
            'to a model with a non-causal projector.'
      : null;
  const greedy = GenerationParams(maxTokens: 8, temp: 0, seed: 1);
  const question = LlamaTextContent(
    'What single color fills this image? Answer with one word.',
  );
  final smallImage = _redBitmap(336);
  final largeImage = _redBitmap(2016);
  final splitWarnings = <String>[];

  setUpAll(
    () => LlamaLogging.configure(
      level: LlamaLogLevel.warn,
      nativeLevel: LlamaLogLevel.none,
      handler: (record) {
        if (record.message.contains('non-causal batches')) {
          splitWarnings.add(record.message);
        }
      },
    ),
  );

  setUp(splitWarnings.clear);

  tearDownAll(LlamaLogging.configure);

  Future<LlamaEngine> load({int batchSize = 0, int microBatchSize = 0}) =>
      LlamaEngine.load(
        LlamaModel(
          ModelSource.path(modelPath),
          projector: ModelSource.path(mmprojPath),
        ),
        params: ModelParams(
          contextSize: 4096,
          gpuLayers: backend == GpuBackend.cpu ? 0 : ModelParams.maxGpuLayers,
          preferredBackend: backend,
          batchSize: batchSize,
          microBatchSize: microBatchSize,
        ),
      );

  Future<String> colorOf(LlamaEngine engine, Uint8List image) async {
    final reply = await engine.complete(
      [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaImageContent(bytes: image),
            question,
          ],
        ),
      ],
      params: greedy,
      enableThinking: false,
    );
    return reply.text.trim().toLowerCase();
  }

  void report(String name, Map<String, Object?> result) {
    // ignore: avoid_print
    print(
      'MULTIMODAL_MICRO_BATCH ${jsonEncode({'case': name, 'backend': backend.name, ...result})}',
    );
  }

  /// The image token count and the micro-batch a message names.
  (int imageTokens, int microBatch) limits(String message) {
    final match = RegExp(
      r'image input has (\d+) tokens, more than the context.s micro-batch '
      r'of (\d+) tokens',
    ).firstMatch(message);
    expect(match, isNotNull, reason: message);
    return (int.parse(match!.group(1)!), int.parse(match.group(2)!));
  }

  /// The typed error [engine] gives [image], after reporting it as [name].
  Future<LlamaInferenceException> rejection(
    String name,
    LlamaEngine engine,
    Uint8List image,
  ) async {
    Object? error;
    String? answer;
    try {
      answer = await colorOf(engine, image);
    } on LlamaException catch (caught) {
      error = caught;
    }
    report(name, {'answer': answer, 'error': error?.toString()});
    expect(error, isA<LlamaInferenceException>());
    expect(splitWarnings, isEmpty);
    return error! as LlamaInferenceException;
  }

  test('an image that fits the default micro-batch is answered', () async {
    final engine = await load();
    addTearDown(engine.dispose);

    final answer = await colorOf(engine, smallImage);

    report('default sizes, small image', {'answer': answer});
    expect(answer, contains('red'));
    expect(splitWarnings, isEmpty);
  }, skip: skip);

  test('an image above an explicit micro-batch below the batch is a typed '
      'error and the engine keeps working', () async {
    final engine = await load(microBatchSize: 32);
    addTearDown(engine.dispose);

    final error = await rejection(
      'microBatchSize 32, small image',
      engine,
      smallImage,
    );

    final (imageTokens, microBatch) = limits(error.message);
    expect(microBatch, 32);
    expect(imageTokens, greaterThan(32));
    expect(error.message, contains('ModelParams.microBatchSize'));
    final text = await engine.complete(const [
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Reply with the word ready.',
      ),
    ], params: greedy);
    expect('${text.thinking}${text.text}', isNotEmpty);
  }, skip: skip);

  for (final (batchSize, microBatchSize, image, name) in [
    (32, 32, smallImage, 'small image'),
    (32, 0, smallImage, 'small image'),
    (256, 256, largeImage, 'large image'),
    (512, 512, largeImage, 'large image'),
  ]) {
    test('an image above a micro-batch equal to the batch '
        '($batchSize/$microBatchSize, $name) is answered in several '
        'non-causal batches, with a warning', () async {
      final engine = await load(
        batchSize: batchSize,
        microBatchSize: microBatchSize,
      );
      addTearDown(engine.dispose);

      final answer = await colorOf(engine, image);

      report('batchSize $batchSize, microBatchSize $microBatchSize, $name', {
        'answer': answer,
        'warnings': splitWarnings,
      });
      expect(answer, contains('red'));
      expect(splitWarnings, hasLength(1));
      final (imageTokens, microBatch) = limits(splitWarnings.single);
      expect(microBatch, batchSize);
      expect(imageTokens, greaterThan(batchSize));
    }, skip: skip);
  }

  test('a text turn after an image turn answers on a context that splits '
      'the image', () async {
    final engine = await load(batchSize: 32, microBatchSize: 32);
    addTearDown(engine.dispose);
    final session = ChatSession(engine);

    Future<String> turn(List<LlamaContentPart> parts) => session
        .create(parts, params: greedy, enableThinking: false)
        .map((chunk) => chunk.choices.first.delta.content ?? '')
        .join();

    final first = await turn([LlamaImageContent(bytes: smallImage), question]);
    final second = await turn(const [
      LlamaTextContent('Answer again with the same one word.'),
    ]);

    report('32/32, image turn then text turn', {
      'first': first,
      'second': second,
      'warnings': splitWarnings.length,
    });
    expect(first.toLowerCase(), contains('red'));
    expect(second.toLowerCase(), contains('red'));
    expect(splitWarnings, hasLength(2));
  }, skip: skip);

  test('an image above the default micro-batch is a typed error, and the '
      'micro-batch the error names answers it in one pass', () async {
    final engine = await load();
    addTearDown(engine.dispose);

    final error = await rejection(
      'default sizes, large image',
      engine,
      largeImage,
    );
    final (imageTokens, microBatch) = limits(error.message);
    expect(microBatch, ModelParams.defaultMicroBatchSize);
    expect(imageTokens, greaterThan(microBatch));
    await engine.dispose();

    final roomy = await load(batchSize: 2048, microBatchSize: imageTokens);
    addTearDown(roomy.dispose);
    final roomyAnswer = await colorOf(roomy, largeImage);

    report('microBatchSize $imageTokens, large image', {'answer': roomyAnswer});
    expect(roomyAnswer, contains('red'));
    expect(splitWarnings, isEmpty);
  }, skip: skip);
}

/// A [side] by [side] 24-bit BMP filled with red.
Uint8List _redBitmap(int side) {
  final rowBytes = (side * 3 + 3) & ~3;
  final bytes = Uint8List(54 + rowBytes * side);
  final header = ByteData.sublistView(bytes);
  header.setUint8(0, 0x42);
  header.setUint8(1, 0x4d);
  header.setUint32(2, bytes.length, Endian.little);
  header.setUint32(10, 54, Endian.little);
  header.setUint32(14, 40, Endian.little);
  header.setInt32(18, side, Endian.little);
  header.setInt32(22, side, Endian.little);
  header.setUint16(26, 1, Endian.little);
  header.setUint16(28, 24, Endian.little);
  header.setUint32(34, rowBytes * side, Endian.little);
  for (var row = 0; row < side; row++) {
    final start = 54 + row * rowBytes;
    for (var column = 0; column < side; column++) {
      bytes[start + column * 3 + 2] = 0xff;
    }
  }
  return bytes;
}
