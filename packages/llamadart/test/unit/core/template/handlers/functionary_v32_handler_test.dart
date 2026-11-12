import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/functionary_v32_handler.dart';
import 'package:test/test.dart';

void main() {
  group('FunctionaryV32Handler', () {
    test('grammar ends the function name with a GBNF newline', () {
      final grammar = FunctionaryV32Handler().buildGrammar([
        ToolDefinition(
          name: 'get_weather',
          description: 'Get weather',
          parameters: [ToolParam.string('city', required: true)],
          handler: (_) async => null,
        ),
      ]);

      expect(grammar, contains(r'tool-0-call ::= "get_weather\n" tool-0-args'));
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
      'keeps content but drops the all header when a later call is malformed',
      () {
        final handler = FunctionaryV32Handler();
        const output = '>>>all\nhello\n>>>weather\n{"city":"Seoul"';

        final parsed = handler.parse(output);

        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, equals(output.substring('>>>all\n'.length)));
      },
    );

    test('partial parse keeps a closing angle bracket before a marker', () {
      final parsed = FunctionaryV32Handler().parse(
        'See <b>x</b>>>>weather\n{"city":5',
        isPartial: true,
      );
      expect(parsed.content, 'See <b>x</b>');
    });
  });
}
