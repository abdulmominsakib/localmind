import 'dart:async';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test('EngineRegistry reports every runtime disposal error', () async {
    final firstError = StateError('first disposal failed');
    final secondError = ArgumentError('second disposal failed');
    final runtimes = <FakeRuntime>[
      FakeRuntime()..disposeError = firstError,
      FakeRuntime(),
      FakeRuntime()..disposeError = secondError,
    ];
    var nextRuntime = 0;
    final registry = EngineRegistry(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'first', modelPath: '/tmp/first.gguf'),
        LlamaModelDefinition(name: 'second', modelPath: '/tmp/second.gguf'),
        LlamaModelDefinition(name: 'third', modelPath: '/tmp/third.gguf'),
      ],
      runtimeFactory: () => runtimes[nextRuntime++],
    );

    await Future.wait(<Future<void>>[
      registry.withRuntime('first', (_) async {}),
      registry.withRuntime('second', (_) async {}),
      registry.withRuntime('third', (_) async {}),
    ]);

    final reportsBothErrors = throwsA(
      isA<ParallelWaitError<dynamic, dynamic>>().having(
        (error) => (error.errors as List<AsyncError?>)
            .whereType<AsyncError>()
            .map((error) => error.error),
        'errors',
        containsAll(<Object>[firstError, secondError]),
      ),
    );
    await expectLater(registry.dispose(), reportsBothErrors);
    await expectLater(registry.dispose(), reportsBothErrors);
    expect(runtimes.map((runtime) => runtime.disposeCount), everyElement(1));
  });
}
