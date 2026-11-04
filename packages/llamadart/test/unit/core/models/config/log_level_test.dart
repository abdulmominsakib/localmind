import 'package:test/test.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';

void main() {
  group('LlamaLogLevel Tests', () {
    test('fromValue maps correctly', () {
      expect(LlamaLogLevel.fromValue(0), LlamaLogLevel.none);
      expect(LlamaLogLevel.fromValue(1), LlamaLogLevel.debug);
      expect(LlamaLogLevel.fromValue(2), LlamaLogLevel.info);
      expect(LlamaLogLevel.fromValue(3), LlamaLogLevel.warn);
      expect(LlamaLogLevel.fromValue(4), LlamaLogLevel.error);
      expect(LlamaLogLevel.fromValue(5), LlamaLogLevel.none);
    });

    test('enum names match', () {
      expect(LlamaLogLevel.debug.name, 'debug');
      expect(LlamaLogLevel.error.name, 'error');
    });
  });
}
