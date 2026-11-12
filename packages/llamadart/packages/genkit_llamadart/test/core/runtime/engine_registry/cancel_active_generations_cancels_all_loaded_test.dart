import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test('cancelActiveGenerations cancels every loaded runtime', () async {
    final runtimes = <FakeRuntime>[];
    final registry = EngineRegistry(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'a', modelPath: '/tmp/a.gguf'),
        LlamaModelDefinition(name: 'b', modelPath: '/tmp/b.gguf'),
      ],
      runtimeFactory: () {
        final runtime = FakeRuntime();
        runtimes.add(runtime);
        return runtime;
      },
    );

    await registry.withRuntime('a', (_) async {});
    await registry.withRuntime('b', (_) async {});

    registry.cancelActiveGenerations();

    expect(runtimes.length, 2);
    expect(runtimes.every((r) => r.cancelGenerationCount == 1), isTrue);
  });
}
