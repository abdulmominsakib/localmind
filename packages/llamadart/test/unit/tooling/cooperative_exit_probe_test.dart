@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../support/cooperative_exit_probe.dart';

void main() {
  test(
    'a state failure after the first token fails shutdown qualification',
    () async {
      final events = StreamController<int>();
      final failure = LlamaStateException('The worker exited unexpectedly.');
      final probe = disposeAfterProbeGenerationStarts(events.stream, () async {
        events.addError(failure);
        await Future<void>.delayed(Duration.zero);
      });
      events.add(1);
      await expectLater(probe, throwsA(same(failure)));
      await events.close();
    },
  );

  test('clean disposal waits for subscription cleanup', () async {
    var cleaned = false;
    final events = StreamController<int>(
      onCancel: () async {
        await Future<void>.delayed(Duration.zero);
        cleaned = true;
      },
    );
    final probe = disposeAfterProbeGenerationStarts(events.stream, () async {});
    events.add(1);
    await probe;
    expect(cleaned, isTrue);
    await events.close();
  });

  test(
    'completion waits for the worker exit, beyond its disposal notice',
    () async {
      final elapsed = Stopwatch()..start();
      await runCooperativeExitProbe(
        _delayedExit,
        const [],
        completedMarker: 'TEST_HOST_SHUTDOWN_COMPLETE',
      );
      expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(60));
    },
  );

  test('an exit without completed disposal fails', () async {
    await expectLater(
      runCooperativeExitProbe(
        _incompleteExit,
        const [],
        completedMarker: 'TEST_HOST_SHUTDOWN_COMPLETE',
      ),
      throwsStateError,
    );
  });

  test('a worker error after its disposal notice still fails', () async {
    await expectLater(
      runCooperativeExitProbe(
        _failedExit,
        const [],
        completedMarker: 'TEST_HOST_SHUTDOWN_COMPLETE',
      ),
      throwsA(isA<RemoteError>()),
    );
  });
}

Future<void> _delayedExit((SendPort, List<String>) message) async {
  message.$1.send(true);
  await Future<void>.delayed(const Duration(milliseconds: 80));
}

void _incompleteExit((SendPort, List<String>) message) {}

void _failedExit((SendPort, List<String>) message) {
  message.$1.send(true);
  throw StateError('late worker failure');
}
