import 'dart:async';

import 'package:test/test.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';

void main() {
  group('LlamaLogger Tests', () {
    late LlamaLogger logger;

    setUp(() {
      logger = LlamaLogger.instance;
      logger.setLevel(LlamaLogLevel.none);
      logger.setHandler(null);
    });

    test('LlamaLogRecord properties', () {
      final now = DateTime.now();
      final record = LlamaLogRecord(
        level: LlamaLogLevel.info,
        message: 'Test msg',
        time: now,
      );
      expect(record.level, LlamaLogLevel.info);
      expect(record.message, 'Test msg');
      expect(record.time, now);
      expect(record.toString(), contains('[INFO] Test msg'));
    });

    test('LlamaLogRecord with error and stackTrace', () {
      final error = Exception('Boom');
      final stack = StackTrace.current;
      final record = LlamaLogRecord(
        level: LlamaLogLevel.error,
        message: 'Fail',
        time: DateTime.now(),
        error: error,
        stackTrace: stack,
      );
      expect(record.toString(), contains('Error: Exception: Boom'));
      expect(
        record.toString(),
        contains('test/unit/core/llama_logger_test.dart'),
      );
    });

    test('setLevel filters messages', () {
      final logs = <LlamaLogRecord>[];
      logger.setHandler((r) => logs.add(r));

      logger.setLevel(LlamaLogLevel.warn);

      logger.debug('debug');
      logger.info('info');
      logger.warn('warn');
      logger.error('error');

      expect(logs.length, 2);
      expect(logs[0].level, LlamaLogLevel.warn);
      expect(logs[1].level, LlamaLogLevel.error);
    });

    test('default handler prints enabled records and drops filtered ones', () {
      final printed = <String>[];
      runZoned(
        () {
          logger.setLevel(LlamaLogLevel.info);
          logger.debug('filtered out');
          logger.info('Printing to console');
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      expect(printed, hasLength(1));
      expect(printed.single, contains('[INFO] Printing to console'));
    });

    test('LlamaLogLevel.none suppresses everything', () {
      final logs = <LlamaLogRecord>[];
      logger.setHandler((r) => logs.add(r));
      logger.setLevel(LlamaLogLevel.none);

      logger.error('critical');
      expect(logs, isEmpty);
    });

    test('instance returns same singleton', () {
      expect(LlamaLogger.instance, same(LlamaLogger.instance));
    });

    test('level reports the configured level', () {
      expect(logger.level, LlamaLogLevel.none);
      logger.setLevel(LlamaLogLevel.info);
      expect(logger.level, LlamaLogLevel.info);
    });
  });
}
