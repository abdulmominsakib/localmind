import 'package:test/test.dart';
import 'package:llamadart/src/core/exceptions.dart';

void main() {
  group('LlamaException Tests', () {
    test('LlamaModelException properties', () {
      final ex = LlamaModelException('Fail to load', 'err_code_1');
      expect(ex.message, 'Fail to load');
      expect(ex.details, 'err_code_1');
      expect(
        ex.toString(),
        contains('LlamaException: Fail to load (err_code_1)'),
      );
    });

    test('LlamaContextException properties', () {
      final ex = LlamaContextException('Context full');
      expect(ex.message, 'Context full');
      expect(ex.details, isNull);
      expect(ex.toString(), 'LlamaException: Context full');
    });

    test('LlamaInferenceException properties', () {
      final ex = LlamaInferenceException('Gen failed');
      expect(ex.message, 'Gen failed');
      expect(ex.toString(), contains('Gen failed'));
    });

    test('LlamaUnsupportedException properties', () {
      final ex = LlamaUnsupportedException('No CUDA');
      expect(ex.message, 'No CUDA');
      expect(ex.toString(), contains('No CUDA'));
    });

    test('LlamaStateException properties', () {
      final ex = LlamaStateException('Not loaded');
      expect(ex.message, 'Not loaded');
      expect(ex.toString(), contains('Not loaded'));
    });
  });
}
