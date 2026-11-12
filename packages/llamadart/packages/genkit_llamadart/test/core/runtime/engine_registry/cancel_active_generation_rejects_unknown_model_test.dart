import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test('cancelActiveGeneration rejects unknown model names', () {
    final registry = EngineRegistry(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'local', modelPath: '/tmp/model.gguf'),
      ],
      runtimeFactory: () => FakeRuntime(),
    );

    expect(
      () => registry.cancelActiveGeneration('missing'),
      throwsA(isA<StateError>()),
    );
  });
}
