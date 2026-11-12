import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test(
    'cancelActiveGeneration is a no-op for a registered model with no runtime '
    'loaded',
    () {
      final runtime = FakeRuntime();
      final registry = EngineRegistry(
        models: const <LlamaModelDefinition>[
          LlamaModelDefinition(name: 'local', modelPath: '/tmp/model.gguf'),
        ],
        runtimeFactory: () => runtime,
      );

      registry.cancelActiveGeneration('local');

      expect(runtime.cancelGenerationCount, 0);
      expect(runtime.initializeCount, 0);
    },
  );
}
