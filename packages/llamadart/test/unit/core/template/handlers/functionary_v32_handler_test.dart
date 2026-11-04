import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/functionary_v32_handler.dart';
import 'package:test/test.dart';

void main() {
  group('FunctionaryV32Handler', () {
    test('exposes chat format', () {
      final handler = FunctionaryV32Handler();
      expect(handler.format, isA<ChatFormat>());
    });

    test('parses JSON tool calls with >>>name markers', () {
      final handler = FunctionaryV32Handler();
      final parsed = handler.parse('>>>weather\n{"city":"Seoul"}');

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('weather'));
      expect(
        parsed.toolCalls.first.function?.arguments,
        equals('{"city":"Seoul"}'),
      );
      expect(parsed.content, isEmpty);
    });

    test('treats leading >>>all as content channel', () {
      final handler = FunctionaryV32Handler();
      final parsed = handler.parse('>>>all\nhello from assistant');

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals('hello from assistant'));
    });

    test('parses raw python channel without JSON body', () {
      final handler = FunctionaryV32Handler();
      final parsed = handler.parse('>>>python\nprint("hi")');

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('python'));
      expect(
        parsed.toolCalls.first.function?.arguments,
        equals('{"code":"print(\\"hi\\")"}'),
      );
      expect(parsed.content, isEmpty);
    });

    test('falls back to content-only on malformed full tool call', () {
      final handler = FunctionaryV32Handler();
      final parsed = handler.parse('>>>weather\n{"city":"Seoul"');

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals('>>>weather\n{"city":"Seoul"'));
    });

    test('rolls back earlier tool calls when a later one is malformed', () {
      final handler = FunctionaryV32Handler();
      const output = '>>>weather\n{"city":"Seoul"}>>>time\n{"zone":"KST"';

      final parsed = handler.parse(output);

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals(output));
    });

    test(
      'keeps leading all-channel content when later tool call is malformed',
      () {
        final handler = FunctionaryV32Handler();
        const output = '>>>all\nhello\n>>>weather\n{"city":"Seoul"';

        final parsed = handler.parse(output);

        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, equals(output));
      },
    );
  });
}
