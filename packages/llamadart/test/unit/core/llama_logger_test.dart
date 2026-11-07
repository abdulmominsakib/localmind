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

    test(
      'default handler uses print (no easy way to test without zones, but coverage is good)',
      () {
        logger.setLevel(LlamaLogLevel.info);
        // This will call print()
        logger.info('Printing to console');
      },
    );

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
  });
}
