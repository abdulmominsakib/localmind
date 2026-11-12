import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test(
    'failed initialization cleanup blocks replacement and stays observable',
    () async {
      final failed = FakeRuntime()
        ..initializeError = StateError('/SECRET/load')
        ..disposeError = StateError('/SECRET/cleanup');
      final replacement = FakeRuntime();
      var allocations = 0;
      final registry = EngineRegistry(
        models: const [
          LlamaModelDefinition(name: 'local', modelPath: '/unused.gguf'),
        ],
        runtimeFactory: () => allocations++ == 0 ? failed : replacement,
      );
      await expectLater(
        registry.withRuntime('local', (_) async {}),
        throwsA(anything),
      );
      await expectLater(
        registry.withRuntime('local', (_) async {}),
        throwsA(isA<LlamaStateException>()),
      );
      expect(allocations, 1);
      expect(replacement.initializeCount, 0);
      registry.cancelActiveGeneration('local');
      expect(failed.cancelGenerationCount, 0);
      await expectLater(registry.dispose(), throwsA(isA<ParallelWaitError>()));
      await expectLater(registry.dispose(), throwsA(isA<ParallelWaitError>()));
      expect(failed.disposeCount, 1);
    },
  );
}
