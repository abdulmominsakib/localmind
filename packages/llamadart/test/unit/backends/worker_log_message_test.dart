@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:llamadart/src/backends/worker_log_message.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:test/test.dart';

void main() {
  final records = <LlamaLogRecord>[];

  setUp(() {
    records.clear();
    LlamaLogger.instance.setLevel(LlamaLogLevel.debug);
    LlamaLogger.instance.setHandler(records.add);
  });

  tearDown(() {
    LlamaLogger.instance.setLevel(LlamaLogLevel.none);
    LlamaLogger.instance.setHandler(null);
  });

  group('WorkerLogMessage.emit', () {
    test('re-logs at the forwarded level with the error text', () {
      WorkerLogMessage(LlamaLogLevel.debug, 'd').emit();
      WorkerLogMessage(LlamaLogLevel.info, 'i').emit();
      WorkerLogMessage(LlamaLogLevel.warn, 'w', error: 'boom').emit();
      WorkerLogMessage(LlamaLogLevel.error, 'e', error: 'bang').emit();
      WorkerLogMessage(LlamaLogLevel.none, 'n').emit();

      expect(records.map((r) => r.level), [
        LlamaLogLevel.debug,
        LlamaLogLevel.info,
        LlamaLogLevel.warn,
        LlamaLogLevel.error,
      ]);
      expect(records.map((r) => r.message), ['d', 'i', 'w', 'e']);
      expect(records.map((r) => r.error), [null, null, 'boom', 'bang']);
    });

    test('honors the main logger level', () {
      LlamaLogger.instance.setLevel(LlamaLogLevel.error);
      WorkerLogMessage(LlamaLogLevel.warn, 'w').emit();
      expect(records, isEmpty);
    });

    test('rebuilds the stack trace from its text', () {
      WorkerLogMessage(
        LlamaLogLevel.error,
        'e',
        error: 'bang',
        stackTrace: '#0 worker',
      ).emit();
      WorkerLogMessage(LlamaLogLevel.warn, 'w').emit();
      expect(records.first.error, 'bang');
      expect(records.first.stackTrace.toString(), '#0 worker');
      expect(records.last.stackTrace, isNull);
    });

    test('prints instead of throwing when the handler throws', () {
      LlamaLogger.instance.setHandler((_) => throw StateError('handler'));
      final printed = <String>[];
      runZoned(
        () => WorkerLogMessage(LlamaLogLevel.warn, 'w').emit(),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );
      expect(printed.single, contains('warn record: Bad state: handler'));
    });
  });

  group('installWorkerLogForwarding', () {
    test('forwards records at or above the level with error text', () async {
      final port = ReceivePort();
      final received = <WorkerLogMessage>[];
      final sub = port.listen((m) => received.add(m as WorkerLogMessage));
      installWorkerLogForwarding(port.sendPort, LlamaLogLevel.warn);
      try {
        expect(LlamaLogger.instance.level, LlamaLogLevel.warn);
        LlamaLogger.instance.info('dropped');
        LlamaLogger.instance.warn('kept', StateError('why'));
        LlamaLogger.instance.error('also kept');
        await Future<void>.delayed(Duration.zero);
        expect(received.map((m) => m.level), [
          LlamaLogLevel.warn,
          LlamaLogLevel.error,
        ]);
        expect(received.first.message, 'kept');
        expect(received.first.error, 'Bad state: why');
        expect(received.last.error, isNull);
        expect(records, isEmpty);
      } finally {
        await sub.cancel();
        port.close();
      }
    });

    test('forwards the stack trace as text', () async {
      final port = ReceivePort();
      final received = <WorkerLogMessage>[];
      final sub = port.listen((m) => received.add(m as WorkerLogMessage));
      installWorkerLogForwarding(port.sendPort, LlamaLogLevel.error);
      try {
        LlamaLogger.instance.error(
          'traced',
          StateError('why'),
          StackTrace.fromString('#0 worker'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(received.single.stackTrace, '#0 worker');
      } finally {
        await sub.cancel();
        port.close();
      }
    });

    test('sends nothing at level none', () async {
      final port = ReceivePort();
      final received = <Object?>[];
      final sub = port.listen(received.add);
      installWorkerLogForwarding(port.sendPort, LlamaLogLevel.none);
      try {
        LlamaLogger.instance.error('dropped');
        await Future<void>.delayed(Duration.zero);
        expect(received, isEmpty);
      } finally {
        await sub.cancel();
        port.close();
      }
    });

    test('caps forwarded debug records and announces the cap', () async {
      final port = ReceivePort();
      final received = <WorkerLogMessage>[];
      final sub = port.listen((m) => received.add(m as WorkerLogMessage));
      installWorkerLogForwarding(port.sendPort, LlamaLogLevel.debug);
      try {
        for (var i = 0; i < workerForwardedDebugRecordCap + 5; i++) {
          LlamaLogger.instance.debug('debug $i');
        }
        LlamaLogger.instance.info('info after cap');
        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(workerForwardedDebugRecordCap + 1));
        final last = received[workerForwardedDebugRecordCap - 1];
        expect(last.level, LlamaLogLevel.debug);
        expect(
          last.message,
          allOf(
            startsWith('debug ${workerForwardedDebugRecordCap - 1}'),
            contains('$workerForwardedDebugRecordCap forwarded debug records'),
          ),
        );
        expect(received.last.level, LlamaLogLevel.info);
        expect(received.last.message, 'info after cap');
      } finally {
        await sub.cancel();
        port.close();
      }
    });
  });
}
