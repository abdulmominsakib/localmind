import 'package:llamadart/src/core/grammar/json_value_depth.dart';
import 'package:test/test.dart';

void main() {
  group('jsonValueDepth', () {
    test('counts container nesting', () {
      expect(jsonValueDepth(null), 0);
      expect(jsonValueDepth('x'), 0);
      expect(jsonValueDepth(<String, dynamic>{}), 1);
      expect(
        jsonValueDepth({
          'a': [
            1,
            {'b': true},
          ],
        }),
        3,
      );
    });

    test('walks deep values without recursion', () {
      Object value = 1;
      for (var i = 0; i < 200000; i++) {
        value = [value];
      }
      expect(jsonValueDepth(value), 200000);
    });

    test('accepts a container shared by sibling values', () {
      final shared = [1];
      expect(jsonValueDepth({'a': shared, 'b': shared}), 2);
    });

    test('returns null for values that are not JSON', () {
      final cycle = <String, dynamic>{};
      cycle['self'] = cycle;
      for (final value in <Object?>[
        cycle,
        {1: 'x'},
        [double.infinity],
        {'a': DateTime(2026)},
      ]) {
        expect(jsonValueDepth(value), isNull, reason: '$value');
      }
    });
  });
}
