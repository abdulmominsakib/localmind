@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../test_helper.dart';

void main() {
  group('Native GGUF tokenizer', () {
    late LlamaEngine engine;

    setUpAll(() async {
      final model = await TestHelper.getTestModel();
      engine = LlamaEngine(LlamaBackend());
      addTearDown(engine.dispose);
      await engine.loadModel(
        model.path,
        modelParams: const ModelParams(
          contextSize: 128,
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
          numberOfThreads: 1,
          numberOfThreadsBatch: 1,
        ),
      );
    });

    // The tiny Llama SentencePiece vocabulary adds one leading space. Keep
    // that normalization explicit so trimming cannot hide damaged output.
    const samples = {
      'ASCII and newline': 'Hello world\n123',
      'accented Latin': 'Montréal café',
      'emoji': '👋',
      'Korean': '한글',
      'mixed Unicode': 'Montréal 👋\n한글 café',
    };
    for (final sample in samples.entries) {
      test('round-trips ${sample.key}', () async {
        final tokens = await engine.tokenize(sample.value, addSpecial: false);
        expect(tokens, isNotEmpty);
        expect(await engine.detokenize(tokens), ' ${sample.value}');
      });
    }

    test('joins UTF-8 bytes across token boundaries before decoding', () async {
      final tokens = await engine.tokenize('👋', addSpecial: false);
      final pieces = await Future.wait(
        tokens.map((token) => engine.detokenize([token])),
      );

      // This vocabulary emits individual byte tokens for this emoji. A lone
      // partial sequence is malformed, but the full token sequence is valid.
      expect(pieces.join(), contains('\uFFFD'));
      expect(await engine.detokenize(tokens), ' 👋');
    });

    test('preserves special-token visibility', () async {
      final tokens = await engine.tokenize('<s>', addSpecial: false);
      expect(tokens, hasLength(1));
      expect(await engine.detokenize(tokens), isEmpty);
      expect(await engine.detokenize(tokens, special: true), '<s>');
    });

    test('detokenizes an empty token list', () async {
      expect(await engine.detokenize([]), isEmpty);
    });
  });
}
