import 'dart:async';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test('cancelActiveGeneration reaches the runtime without waiting behind a '
      'queued operation', () async {
    final runtime = FakeRuntime();
    final registry = EngineRegistry(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'local', modelPath: '/tmp/model.gguf'),
      ],
      runtimeFactory: () => runtime,
    );

    await registry.withRuntime('local', (_) async {});

    // Occupy the operation queue with a request that never completes on its
    // own. A cancel routed through the queue would block behind this.
    final blocker = Completer<void>();
    final queued = registry.withRuntime('local', (_) => blocker.future);
    await Future<void>.delayed(Duration.zero); // let the queued op start

    registry.cancelActiveGeneration('local');

    expect(runtime.cancelGenerationCount, 1);

    blocker.complete();
    await queued;
  });
}
