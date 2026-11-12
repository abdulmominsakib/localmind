import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test('EngineRegistry disposes failed initialization and retries', () async {
    var factoryCalls = 0;
    final failedRuntime = FakeRuntime()
      ..initializeError = StateError('failed to initialize');
    final healthyRuntime = FakeRuntime();
    final registry = EngineRegistry(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'local', modelPath: '/tmp/model.gguf'),
      ],
      runtimeFactory: () =>
          factoryCalls++ == 0 ? failedRuntime : healthyRuntime,
    );

    await expectLater(
      () => registry.withRuntime('local', (_) async => 1),
      throwsA(isA<StateError>()),
    );

    final result = await registry.withRuntime('local', (_) async => 42);

    expect(result, 42);
    expect(failedRuntime.disposeCount, 1);
    expect(healthyRuntime.initializeCount, 1);
    expect(factoryCalls, 2);
  });
}
