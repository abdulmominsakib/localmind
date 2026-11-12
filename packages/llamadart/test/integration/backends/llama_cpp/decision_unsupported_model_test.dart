@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../test_helper.dart';

void main() {
  group('DecisionEngine on a llama-architecture GGUF', () {
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

    final namesArchitecture = allOf(
      contains('general.architecture "modern-bert"'),
      contains('architecture "llama"'),
    );

    test('capabilitiesFor reports the model architecture', () async {
      final capabilities = await DecisionEngine.capabilitiesFor(engine);

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, namesArchitecture);
    });

    test('loading a head fails before the head file is read', () async {
      const headPath = 'missing-decision-head.safetensors';
      Matcher unsupported() => throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          namesArchitecture,
        ),
      );

      await expectLater(
        DecisionEngine.attach(engine, head: ModelSource.path(headPath)),
        unsupported(),
      );
      await expectLater(
        engine.loadDecisionHeadBackend(headPath),
        unsupported(),
      );
      await expectLater(
        engine.runDecisionBackend(1, const []),
        throwsA(isA<LlamaStateException>()),
      );
    });
  });
}
