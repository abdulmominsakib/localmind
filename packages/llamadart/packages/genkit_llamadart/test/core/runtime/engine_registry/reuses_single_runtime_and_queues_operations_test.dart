import 'dart:async';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test(
    'EngineRegistry reuses a single runtime and queues operations',
    () async {
      var factoryCalls = 0;
      final runtime = FakeRuntime();
      final registry = EngineRegistry(
        models: const <LlamaModelDefinition>[
          LlamaModelDefinition(name: 'local', modelPath: '/tmp/model.gguf'),
        ],
        runtimeFactory: () {
          factoryCalls += 1;
          return runtime;
        },
      );

      var activeOperations = 0;
      var maxActiveOperations = 0;
      final executionOrder = <int>[];

      Future<int> runOperation(int index) {
        return registry.withRuntime('local', (_) async {
          activeOperations += 1;
          maxActiveOperations = activeOperations > maxActiveOperations
              ? activeOperations
              : maxActiveOperations;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          executionOrder.add(index);
          activeOperations -= 1;
          return index;
        });
      }

      final results = await Future.wait(<Future<int>>[
        runOperation(1),
        runOperation(2),
        runOperation(3),
      ]);

      expect(results, <int>[1, 2, 3]);
      expect(executionOrder, <int>[1, 2, 3]);
      expect(maxActiveOperations, 1);
      expect(factoryCalls, 1);
      expect(runtime.initializeCount, 1);
    },
  );
}
