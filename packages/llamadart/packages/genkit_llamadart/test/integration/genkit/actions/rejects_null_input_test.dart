import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/actions/embedder_action.dart';
import 'package:genkit_llamadart/src/integration/genkit/actions/model_action.dart';
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';
import 'test_support/action_harness.dart';

void main() {
  for (final embedding in [false, true]) {
    test('rejects null raw input with embedding=$embedding', () async {
      final runtime = FakeRuntime();
      final definition = testModelDefinition();
      final registry = testRegistry(definition: definition, runtime: runtime);
      addTearDown(registry.dispose);

      final result = embedding
          ? buildEmbedderAction(
              definition: definition,
              registry: registry,
            ).runRaw(null)
          : buildModelAction(
              definition: definition,
              registry: registry,
            ).runRaw(null);

      await expectLater(
        result,
        throwsA(
          isA<genkit.GenkitException>().having(
            (error) => error.status,
            'status',
            genkit.StatusCode.invalidArgument,
          ),
        ),
      );
      expect(runtime.initializeCount, 0);
      expect(runtime.createCallCount, 0);
      expect(runtime.embedBatchCallCount, 0);
    });
  }
}
