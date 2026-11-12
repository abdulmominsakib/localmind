import 'dart:async';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:test/test.dart';

import '../test_support/fake_runtime.dart';

void main() {
  test('EngineRegistry disposes independent runtimes concurrently', () async {
    final releaseDisposals = Completer<void>();
    final runtimes = <_BlockingDisposeRuntime>[
      _BlockingDisposeRuntime(releaseDisposals.future),
      _BlockingDisposeRuntime(releaseDisposals.future),
    ];
    var nextRuntime = 0;
    final registry = EngineRegistry(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'first', modelPath: '/tmp/first.gguf'),
        LlamaModelDefinition(name: 'second', modelPath: '/tmp/second.gguf'),
      ],
      runtimeFactory: () => runtimes[nextRuntime++],
    );

    await Future.wait(<Future<void>>[
      registry.withRuntime('first', (_) async {}),
      registry.withRuntime('second', (_) async {}),
    ]);

    final disposal = registry.dispose();
    try {
      await Future.wait(
        runtimes.map((runtime) => runtime.disposeStarted.future),
      ).timeout(const Duration(seconds: 1));
    } finally {
      releaseDisposals.complete();
      await disposal;
    }

    expect(runtimes.map((runtime) => runtime.disposeCount), everyElement(1));
  });
}

class _BlockingDisposeRuntime extends FakeRuntime {
  _BlockingDisposeRuntime(this._releaseDisposal);

  final Future<void> _releaseDisposal;
  final Completer<void> disposeStarted = Completer<void>();

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    disposeStarted.complete();
    await _releaseDisposal;
  }
}
