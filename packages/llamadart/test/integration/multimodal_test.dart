@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import '../test_helper.dart';

void main() {
  group('Multimodal Integration Tests', () {
    late LlamaEngine engine;
    late LlamaBackend backend;

    setUp(() {
      backend = LlamaBackend();
      engine = LlamaEngine(backend);
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('Multimodal initialization and property checks', () async {
      final modelFile = await TestHelper.getTestModel();
      await engine.loadModel(modelFile.path, modelParams: const ModelParams());

      // We don't have a real mmproj file in the test assets,
      // but we can verify that the method exists and handles invalid paths.
      expect(
        () => engine.loadMultimodalProjector('non_existent_path.gguf'),
        throwsException,
      );

      // Check supports getters (should be false for base stories model)
      expect(await engine.supportsVision, isFalse);
      expect(await engine.supportsAudio, isFalse);
    });

    test('Multimodal message structure', () async {
      final msg = LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [
          const LlamaTextContent('Describe this image:'),
          const LlamaImageContent(path: 'test_image.jpg'),
        ],
      );

      expect(msg.role, LlamaChatRole.user);
      expect(msg.parts.length, 2);
      expect(msg.parts[0], isA<LlamaTextContent>());
      expect(msg.parts[1], isA<LlamaImageContent>());
      expect(msg.content, 'Describe this image:');
    });

    test('Backward compatibility with legacy messages', () {
      // ignore: deprecated_member_use_from_same_package
      const msg = LlamaChatMessage(role: 'user', content: 'hello');

      expect(msg.role, LlamaChatRole.user);
      expect(msg.content, 'hello');
      expect(msg.parts.length, 1);
      expect(msg.parts[0], isA<LlamaTextContent>());
      expect((msg.parts[0] as LlamaTextContent).text, 'hello');
    });
  });
}
