import 'dart:async';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test('EngineRegistry rejects new work once disposal starts', () async {
    final runtimes = <FakeRuntime>[];
    final registry = EngineRegistry(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'local', modelPath: '/tmp/model.gguf'),
      ],
      runtimeFactory: () {
        final runtime = FakeRuntime();
        runtimes.add(runtime);
        return runtime;
      },
    );
    final operationStarted = Completer<void>();
    final releaseOperation = Completer<void>();
    final operation = registry.withRuntime('local', (_) async {
      operationStarted.complete();
      await releaseOperation.future;
    });
    await operationStarted.future;

    final disposal = registry.dispose();

    expect(
      () => registry.withRuntime('local', (_) async {}),
      throwsA(isA<StateError>()),
    );

    releaseOperation.complete();
    await operation;
    await disposal;
    await registry.dispose();

    expect(runtimes, hasLength(1));
    expect(runtimes.single.disposeCount, 1);
  });
}
