@TestOn('vm')
@Timeout(Duration(minutes: 10))
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import '../test_helper.dart';

void main() {
  group('Inference Smoke Test (Desktop)', () {
    test('Verify native library load and basic inference', () async {
      try {
        // 1. Basic Init Check
        // (Removed manual init, LlamaEngine handles it via worker isolate)

        // Debugging: Set log level to INFO to see backend init logs
        LlamaCppService().setLogLevel(LlamaLogLevel.info);
        print('Backends: ${LlamaCppService().getBackendInfo()}');

        // 2. Ensure tiny model
        final modelFile = await TestHelper.getTestModel();

        // 3. Full Inference Pipeline Test
        final backend = LlamaBackend();
        final engine = LlamaEngine(backend);
        print('Loading model...');
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(
            contextSize: 128,
            gpuLayers: 0,
            numberOfThreads: 1,
            numberOfThreadsBatch: 1,
            chatTemplate:
                "{% for message in messages %}{{ message['role'] }}: {{ message['content'] }}\n{% endfor %}",
          ),
        );
        expect(engine.isReady, isTrue);
        print('Model loaded successfully.');
        print('Running 5-token generation check...');
        const grammarParams = GenerationParams(
          maxTokens: 5,
          penalty: 1.2,
          grammar: 'root ::= "World"',
        );
        final imageMessage = LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaTextContent('Hello'),
            LlamaImageContent(
              bytes: Uint8List.fromList([0, 0, 0]),
              width: 1,
              height: 1,
            ),
          ],
        );
        await expectLater(
          engine.create([imageMessage], params: grammarParams),
          emitsError(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              contains('needs a multimodal projector'),
            ),
          ),
        );

        final stream = engine.create([
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello'),
        ], params: grammarParams);

        final tokens = <String>[];
        await for (final chunk in stream.timeout(const Duration(seconds: 60))) {
          final token = chunk.choices.first.delta.content ?? '';
          tokens.add(token);
        }
        expect(tokens.join(), 'World');

        // 4b. Verify chat with streaming
        final messages = [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Once upon a time',
          ),
        ];

        print('Running generation check...');
        final fullContent = StringBuffer();
        await for (final chunk in engine.create(messages)) {
          final delta = chunk.choices.first.delta.content;
          if (delta != null) {
            fullContent.write(delta);
          }
        }
        print('Generation completed.');
        expect(fullContent.isNotEmpty, isTrue);

        // 4. Tokenizer test
        final encoded = await engine.tokenize('Hello world');
        expect(encoded, isNotEmpty);
        final decoded = await engine.detokenize(encoded);
        expect(decoded, contains('Hello world'));

        // 5. Metadata test
        final metadata = await engine.getMetadata();
        expect(metadata, isNotEmpty);
        expect(metadata.containsKey('general.architecture'), isTrue);

        // 6. Context Size
        final ctxSize = await engine.getContextSize();
        expect(ctxSize, greaterThan(0));

        // 7. Log level test (Silencer)
        await LlamaLogging.configure();
        await LlamaLogging.configure(level: LlamaLogLevel.warn);

        // 8. LoRA (a missing adapter file must surface as a typed error)
        await expectLater(
          engine.setLora('non_existent.bin'),
          throwsA(
            isA<LlamaModelException>().having(
              (e) => e.message,
              'message',
              contains('Failed to load LoRA'),
            ),
          ),
        );
        await engine.clearLoras();

        // 9. Projector load failures are typed
        await expectLater(
          engine.loadMultimodalProjector('non_existent_path.gguf'),
          throwsA(
            isA<LlamaModelException>().having(
              (e) => e.message,
              'message',
              'Multimodal projector file not found.',
            ),
          ),
        );
        await expectLater(
          engine.loadMultimodalProjector(modelFile.path),
          throwsA(
            isA<LlamaModelException>().having(
              (e) => e.message,
              'message',
              startsWith(
                'The native runtime could not load the multimodal projector',
              ),
            ),
          ),
        );
        expect(engine.hasMultimodalProjector, isFalse);

        await engine.dispose();
        print('SMOKE TEST SUCCESS');
      } catch (e) {
        print('SMOKE TEST FAILED: $e');
        rethrow;
      }
    });
  });
}
