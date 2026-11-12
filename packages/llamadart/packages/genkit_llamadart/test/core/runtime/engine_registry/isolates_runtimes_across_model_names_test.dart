import 'dart:async';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test('EngineRegistry isolates runtimes across model names', () async {
    var factoryCalls = 0;
    final runtimes = <FakeRuntime>[FakeRuntime(), FakeRuntime()];
    final registry = EngineRegistry(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'alpha', modelPath: '/tmp/alpha.gguf'),
        LlamaModelDefinition(name: 'beta', modelPath: '/tmp/beta.gguf'),
      ],
      runtimeFactory: () => runtimes[factoryCalls++],
    );

    var activeOperations = 0;
    var maxActiveOperations = 0;

    Future<String> runOperation(String modelName) {
      return registry.withRuntime(modelName, (_) async {
        activeOperations += 1;
        maxActiveOperations = activeOperations > maxActiveOperations
            ? activeOperations
            : maxActiveOperations;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        activeOperations -= 1;
        return modelName;
      });
    }

    final results = await Future.wait<String>(<Future<String>>[
      runOperation('alpha'),
      runOperation('beta'),
    ]);

    expect(results, <String>['alpha', 'beta']);
    expect(maxActiveOperations, 2);
    expect(factoryCalls, 2);
    expect(runtimes[0].initializeCount, 1);
    expect(runtimes[1].initializeCount, 1);
  });
}
