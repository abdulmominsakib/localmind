import 'package:llamadart/src/core/template/handlers/specialized_handler_utils.dart';
import 'package:test/test.dart';

void main() {
  group('shared invoke scope parsing', () {
    ParsedInvokeCalls parse(String input, {bool isPartial = false}) =>
        parseInvokeScope(
          input,
          scopeStart: '<calls>',
          scopeEnd: '</calls>',
          invokeStartPattern: RegExp(r'<invoke name="([^"]+)">'),
          invokeEnd: '</invoke>',
          parseArguments: (_, body) => body.isEmpty ? {} : null,
          isPartial: isPartial,
        );

    test('preserves surrounding text and decodes canonical tool names', () {
      final parsed = parse(
        'before<calls><invoke name="weather&amp;alerts"></invoke></calls>after',
      );

      expect(parsed.success, isTrue);
      expect(parsed.remaining, 'beforeafter');
      expect(parsed.calls.single.function?.name, 'weather&alerts');
    });

    test('suppresses partial markers and rolls back malformed finals', () {
      expect(parse('before<cal', isPartial: true).remaining, 'before');
      const unfinished = '<calls><invoke name="weather"></invoke><invoke';
      final partial = parse(unfinished, isPartial: true);
      expect(partial.success, isTrue);
      expect(partial.calls, hasLength(1));
      expect(partial.remaining, isEmpty);

      final finalResult = parse(unfinished);
      expect(finalResult.success, isFalse);
      expect(finalResult.calls, isEmpty);
    });

    test('rejects noncanonical attribute escaping', () {
      final parsed = parse(
        '<calls><invoke name="weather&alerts"></invoke></calls>',
      );
      expect(parsed.success, isFalse);
      expect(parsed.calls, isEmpty);
    });
  });
}
