import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'engine_test.dart';

void main() {
  for (final hook in ['logger', 'cancelGeneration']) {
    for (final operation in ['dispose', 'unload']) {
      test(
        '$operation reentry from $hook shares one disposal and teardown',
        () async {
          final backend = _TeardownBackend();
          final engine = LlamaEngine(backend);
          await engine.loadModel('model.gguf');
          final contextRelease = Completer<void>();
          backend.contextFreeDelay = contextRelease.future;
          addTearDown(() {
            if (!contextRelease.isCompleted) contextRelease.complete();
          });
          addTearDown(LlamaLogging.configure);
          Future<void>? nested;
          Future<void>? repeated;
          bool? disposedAtHook;
          void reenter() {
            disposedAtHook = engine.isDisposed;
            nested = engine.dispose();
            repeated = engine.dispose();
          }

          if (hook == 'logger') {
            var fired = false;
            await LlamaLogging.configure(
              level: LlamaLogLevel.info,
              handler: (record) {
                if (!fired && record.message == 'Unloading model...') {
                  fired = true;
                  reenter();
                }
              },
            );
          } else {
            backend.onCancel = reenter;
          }

          final stopping = operation == 'dispose'
              ? engine.dispose()
              : engine.unloadModel();
          // The callbacks still run synchronously, before the public call returns.
          expect(nested, isNotNull);
          expect(disposedAtHook, operation == 'dispose');
          expect(engine.isDisposed, isTrue);
          expect(repeated, same(nested));
          expect(engine.dispose(), same(nested));
          if (operation == 'dispose') expect(stopping, same(nested));
          expect(backend.freedContexts, [1]);
          expect(backend.freedModels, isEmpty);
          expect(backend.disposeCalls, 0);

          contextRelease.complete();
          await stopping;
          await nested;
          expect(backend.freedContexts, [1]);
          expect(backend.freedModels, [1]);
          expect(backend.cancelGenerationCalls, 1);
          expect(backend.disposeCalls, 1);
          expect(engine.isReady, isFalse);
          expect(backend.events, ['contextFree', 'modelFree', 'dispose']);
        },
      );
    }
  }

  test(
    'healthy disposal keeps synchronous cancellation and one future',
    () async {
      final backend = _TeardownBackend();
      final engine = LlamaEngine(backend);
      await engine.loadModel('model.gguf');
      final first = engine.dispose();
      expect(engine.isDisposed, isTrue);
      expect(backend.cancelGenerationCalls, 1);
      expect(backend.freedContexts, [1]);
      expect(engine.dispose(), same(first));
      await first;
      expect(engine.dispose(), same(first));
      expect(backend.freedModels, [1]);
      expect(backend.disposeCalls, 1);
    },
  );

  for (final failure in [
    'cancel',
    'context',
    'backend',
    'context and backend',
  ]) {
    test('$failure disposal failure stays memoized under reentry', () async {
      final backend = _TeardownBackend();
      final engine = LlamaEngine(backend);
      await engine.loadModel('model.gguf');
      final cause = StateError('teardown failure');
      final secondary = StateError('backend failure');
      if (failure == 'cancel') backend.cancelError = cause;
      if (failure.startsWith('context')) backend.contextError = cause;
      if (failure == 'backend') backend.disposeError = cause;
      if (failure == 'context and backend') backend.disposeError = secondary;
      Future<void>? nested;
      backend.onCancel = () {
        expect(engine.isDisposed, isTrue);
        nested = engine.dispose();
      };
      final first = engine.dispose();
      expect(nested, same(first));
      await expectLater(first, throwsA(same(cause)));
      expect(engine.dispose(), same(first));
      await expectLater(engine.dispose(), throwsA(same(cause)));
      expect(engine.isDisposed, isTrue);
      expect(backend.cancelGenerationCalls, 1);
      expect(backend.freedContexts, failure == 'cancel' ? isEmpty : [1]);
      expect(backend.freedModels, failure == 'backend' ? [1] : isEmpty);
      expect(backend.disposeCalls, 1);
    });
  }

  test('dispose reentered from load logging waits for that load', () async {
    final backend = _TeardownBackend();
    final engine = LlamaEngine(backend);
    Future<void>? disposing;
    addTearDown(LlamaLogging.configure);
    await LlamaLogging.configure(
      level: LlamaLogLevel.info,
      handler: (record) {
        if (record.message == 'Loading model: model.gguf') {
          disposing = engine.dispose();
          expect(engine.isDisposed, isTrue);
          expect(backend.disposeCalls, 0);
        }
      },
    );
    final loading = engine.loadModel('model.gguf');
    expect(disposing, isNotNull);
    await expectLater(loading, throwsA(isA<LlamaStateException>()));
    await disposing;
    expect(engine.dispose(), same(disposing));
    expect(backend.modelLoadCalls, 1);
    expect(backend.freedContexts, [1]);
    expect(backend.freedModels, [1]);
    expect(backend.events, ['contextFree', 'modelFree', 'dispose']);
  });

  for (final operation in ['load', 'unload']) {
    test(
      '$operation rejects a lifecycle overlap from synchronous logging',
      () async {
        final backend = _TeardownBackend();
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        addTearDown(LlamaLogging.configure);
        if (operation == 'unload') await engine.loadModel('model.gguf');
        Future<void>? overlapping;
        Future<void>? rejected;
        var fired = false;
        await LlamaLogging.configure(
          level: LlamaLogLevel.info,
          handler: (record) {
            final message = operation == 'load'
                ? 'Loading model: model.gguf'
                : 'Unloading model...';
            if (!fired && record.message == message) {
              fired = true;
              overlapping = operation == 'load'
                  ? engine.loadModel('second.gguf')
                  : engine.unloadModel();
              rejected = expectLater(
                overlapping,
                throwsA(
                  isA<LlamaStateException>().having(
                    (error) => error.message,
                    'message',
                    contains('another model lifecycle operation'),
                  ),
                ),
              );
            }
          },
        );
        await (operation == 'load'
            ? engine.loadModel('model.gguf')
            : engine.unloadModel());
        expect(overlapping, isNotNull);
        await rejected;
        expect(backend.modelLoadCalls, 1);
        expect(backend.freedContexts, operation == 'load' ? isEmpty : [1]);
        expect(backend.freedModels, operation == 'load' ? isEmpty : [1]);
      },
    );
  }
}

class _TeardownBackend extends MockLlamaBackend {
  void Function()? onCancel;
  Object? cancelError;
  Object? contextError;
  Object? disposeError;
  final freedContexts = <int>[];
  final freedModels = <int>[];
  final events = <String>[];

  @override
  void cancelGeneration() {
    super.cancelGeneration();
    final callback = onCancel;
    onCancel = null;
    callback?.call();
    if (cancelError case final error?) throw error;
  }

  @override
  Future<void> contextFree(int handle) async {
    freedContexts.add(handle);
    events.add('contextFree');
    if (contextError case final error?) throw error;
    await super.contextFree(handle);
  }

  @override
  Future<void> modelFree(int handle) async {
    freedModels.add(handle);
    events.add('modelFree');
    await super.modelFree(handle);
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
    await super.dispose();
    if (disposeError case final error?) throw error;
  }
}
