import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/laguna_handler.dart';
import 'package:test/test.dart';

import 'specialized_handler_test_fixtures.dart';

void main() {
  group('Poolside Laguna', () {
    test('escapes the newline delimiter inside required GBNF classes', () {
      final grammar = LagunaHandler().buildRequiredGrammar([schemaTool])!;

      expect(grammar, contains(r'[^\n<'));
      expect(grammar, isNot(contains('[^\n')));
    });

    test('parses reasoning and GLM-style tool calls with raw strings', () {
      const output =
          '<think>check</think>On it.\n'
          '<tool_call>weather\n'
          '<arg_key>city</arg_key>\n'
          '<arg_value> New York </arg_value>\n'
          '</tool_call>';
      final handler = LagunaHandler();
      final parsed = handler.parse(output);
      expect(parsed.reasoningContent, 'check');
      expect(parsed.content, 'On it.');
      expect(arguments(parsed), {'city': 'New York'});
      expect(handler.additionalStops, contains('</assistant>'));
    });

    test('preserves malformed tool blocks as non-tool content', () {
      const output =
          '<tool_call>weather<arg_key>city</arg_key>Seoul</tool_call>';
      final parsed = LagunaHandler().parse(output);
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    });

    test('hides an incomplete Laguna tool block while streaming', () {
      const output =
          'Visible answer.\n'
          '<tool_call>weather\n'
          '<arg_key>city</arg_key><arg_value>Seo';
      final parsed = LagunaHandler().parse(output, isPartial: true);

      expect(parsed.content, 'Visible answer.');
      expect(parsed.toolCalls, isEmpty);
    });

    test('keeps completed Laguna calls before an incomplete next call', () {
      const output =
          'Visible answer.\n'
          '<tool_call>weather\n'
          '<arg_key>city</arg_key><arg_value>Seoul</arg_value>\n'
          '</tool_call>\n'
          '<tool_call>weather\n<arg_key>city</arg_key><arg_value>Tor';
      final parsed = LagunaHandler().parse(output, isPartial: true);

      expect(parsed.content, 'Visible answer.');
      expect(parsed.toolCalls, hasLength(1));
      expect(arguments(parsed), {'city': 'Seoul'});
    });

    test('hides a partial Laguna opening marker while streaming', () {
      const output = 'Visible answer.<tool_cal';
      final parsed = LagunaHandler().parse(output, isPartial: true);

      expect(parsed.content, 'Visible answer.');
      expect(parsed.toolCalls, isEmpty);
    });

    test('keeps incomplete Laguna markup when parsing is disabled', () {
      const output = 'Visible answer.<tool_call>weather';
      final parsed = LagunaHandler().parse(
        output,
        isPartial: true,
        parseToolCalls: false,
      );

      expect(parsed.content, output);
      expect(parsed.toolCalls, isEmpty);
    });

    test('production parse preserves schema-directed Laguna values', () {
      const output =
          '<tool_call>inspect\n'
          '<arg_key>code</arg_key><arg_value>123</arg_value>\n'
          '<arg_key>options</arg_key><arg_value>{}</arg_value>\n'
          '<arg_key>items</arg_key><arg_value>[]</arg_value>\n'
          '<arg_key>count</arg_key><arg_value>7</arg_value>\n'
          '<arg_key>active</arg_key><arg_value>true</arg_value>\n'
          '<arg_key>empty</arg_key><arg_value>null</arg_value>\n'
          '</tool_call>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.laguna.index,
        output,
        tools: [schemaTool],
      );

      expect(arguments(parsed), {
        'code': '123',
        'options': <String, dynamic>{},
        'items': <Object?>[],
        'count': 7,
        'active': true,
        'empty': null,
      });
    });
  });
}
