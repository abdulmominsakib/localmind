@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import '../test_helper.dart';

void main() {
  group('Engine Reloading', () {
    late LlamaEngine engine;
    late String modelPath;

    setUp(() async {
      engine = LlamaEngine(LlamaBackend());
      final modelFile = await TestHelper.getTestModel();
      modelPath = modelFile.path;
    });

    tearDown(() async {
      await engine.dispose();
    });

    test(
      'should be able to unload and reload a model',
      () async {
        // First load
        await engine.loadModel(
          modelPath,
          modelParams: const ModelParams(
            contextSize: 128,
            gpuLayers: 0,
            numberOfThreads: 1,
            numberOfThreadsBatch: 1,
          ),
        );
        expect(engine.isReady, isTrue);

        // Simple generation to ensure it works
        var response1 = await engine.create([
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Hello, say hi!',
          ),
        ]).join();
        expect(response1, isNotEmpty);

        // Unload
        await engine.unloadModel();
        expect(engine.isReady, isFalse);

        // Second load
        await engine.loadModel(
          modelPath,
          modelParams: const ModelParams(
            contextSize: 128,
            gpuLayers: 0,
            numberOfThreads: 1,
            numberOfThreadsBatch: 1,
          ),
        );
        expect(engine.isReady, isTrue);

        // Verify inference works again
        var response2 = await engine.create([
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Say hello again!',
          ),
        ]).join();
        expect(response2, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
