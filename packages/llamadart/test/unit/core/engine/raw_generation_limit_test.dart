import 'dart:async';
import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/core/engine/engine.dart' show rawGenerationLimit;
import 'package:test/test.dart';

import 'engine_test.dart' show MockLlamaBackend, LimitReportingMockBackend;

void main() {
  for (final observed in [false, true]) {
    for (final limit in BackendGenerationLimit.values) {
      test(
        'raw generation retains $limit only after successful EOF observed=$observed',
        () async {
          final backend = LimitReportingMockBackend()
            ..generationText = 'partial'
            ..nextLimit = limit;
          final observer = _LimitObserver();
          final engine = LlamaEngine(
            backend,
            observers: observed ? [observer] : [],
          );
          addTearDown(engine.dispose);
          await engine.loadModel('qwen-test.gguf');
          final generation = engine.generate('hello');
          expect(rawGenerationLimit(generation), isNull);
          final pieces = <String>[];
          await for (final piece in generation) {
            expect(rawGenerationLimit(generation), isNull);
            pieces.add(piece);
          }
          expect(pieces.join(), 'partial');
          expect(rawGenerationLimit(generation), limit);
          if (observed) {
            expect(observer.operation.results.last.finishReason, 'length');
          }

          backend.nextLimit = null;
          final normal = engine.generate(
            'hello',
            params: const GenerationParams(maxTokens: 1),
          );
          expect(await normal.join(), 'partial');
          expect(rawGenerationLimit(normal), isNull);
          expect(rawGenerationLimit(generation), limit);
        },
      );
    }
  }
  for (final termination in ['cancel', 'error', 'subscription cancel']) {
    test('raw $termination never publishes a backend limit', () async {
      final backend = _InterruptedLimitBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('qwen-test.gguf');
      final generation = engine.generate('hello');
      if (termination == 'subscription cancel') {
        final first = Completer<void>();
        final subscription = generation.listen((_) => first.complete());
        await first.future;
        final cancellation = subscription.cancel();
        backend.release.complete();
        await cancellation;
      } else {
        final done = generation.toList();
        await backend.started.future;
        if (termination == 'cancel') {
          engine.cancelGeneration();
        } else {
          backend.fail = true;
        }
        backend.release.complete();
        if (termination == 'error') {
          await expectLater(done, throwsA(isA<LlamaException>()));
        } else {
          await done;
        }
      }
      expect(rawGenerationLimit(generation), isNull);
    });
  }
}

class _InterruptedLimitBackend extends MockLlamaBackend
    implements BackendGenerationLimitReporting {
  final started = Completer<void>();
  final release = Completer<void>();
  bool fail = false;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    yield utf8.encode('partial');
    started.complete();
    await release.future;
    if (fail) throw StateError('generation failed');
  }

  // Deliberately reports stale metadata even after cancellation or errors,
  // proving the engine does not expose it as a successful raw outcome.
  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      BackendGenerationLimit.runtime;
}

final class _LimitObserver extends LlamaEngineObserver {
  final operation = _LimitOperation();
  @override
  LlamaOperationObserver? onStart(LlamaOperation request) => operation;
}

final class _LimitOperation extends LlamaOperationObserver {
  final results = <LlamaOperationResult>[];
  @override
  void onEnd(LlamaOperationResult result) => results.add(result);
}
