import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test('EngineRegistry rejects unknown model names', () async {
    final registry = EngineRegistry(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'local', modelPath: '/tmp/model.gguf'),
      ],
      runtimeFactory: () => FakeRuntime(),
    );

    expect(
      () => registry.withRuntime('missing', (_) async => 1),
      throwsA(isA<StateError>()),
    );
  });
}
