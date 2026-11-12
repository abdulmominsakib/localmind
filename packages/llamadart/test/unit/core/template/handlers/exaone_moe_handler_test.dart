import 'dart:convert';

import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/exaone_moe_handler.dart';
import 'package:test/test.dart';

void main() {
  test('ExaoneMoeHandler.toolCallOpening finds a whole or partial opening', () {
    expect(ExaoneMoeHandler.toolCallOpening('Let me check. <tool_call...'), 14);
    expect(ExaoneMoeHandler.toolCallOpening('Let me check. <tool'), 14);
    expect(ExaoneMoeHandler.toolCallOpening('Use <tool> or <x>.'), 18);
  });

  test('ExaoneMoeHandler parses tool calls from tagged JSON blocks', () {
    final handler = ExaoneMoeHandler();

    final parsed = handler.parse(
      '<tool_call>{"name":"get_weather","arguments":{"city":"Seoul"}}</tool_call> tail',
    );

    expect(parsed.content, 'tail');
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, 'get_weather');
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });

  test('ExaoneMoeHandler parses nested function payloads in code fences', () {
    final handler = ExaoneMoeHandler();

    final parsed = handler.parse(
      '<tool_call>```json\n'
      '{"id":"call_1","function":{"name":"get_weather","arguments":{"city":"Seoul"}}}\n'
      '```</tool_call>',
    );

    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.id, 'call_1');
    expect(parsed.toolCalls.first.function?.name, 'get_weather');
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });

  group('ExaoneMoeHandler.buildGrammar', () {
    Future<Object?> noop(_) async => null;

    String grammarFor(String name) => ExaoneMoeHandler().buildGrammar([
      ToolDefinition(
        name: name,
        description: 'Tool',
        parameters: [ToolParam.string('city')],
        handler: noop,
      ),
    ])!;

    test('quotes the tool name as a JSON string', () {
      expect(
        grammarFor('weather'),
        contains(r'"\"name\"" space ":" space "\"weather\"" space'),
      );
    });

    test('escapes tool names that need JSON escaping', () {
      expect(grammarFor('a"b'), contains(r'space "\"a\\\"b\"" space'));
    });

    test('parses a call body with a quoted name', () {
      final parsed = ExaoneMoeHandler().parse(
        '<tool_call>{"name":"weather","arguments":{"city":"Seoul"}}</tool_call>',
      );

      expect(parsed.toolCalls.single.function?.name, 'weather');
    });
  });

  test('ExaoneMoeHandler keeps malformed tool blocks as content', () {
    final handler = ExaoneMoeHandler();
    const input = '<tool_call>{"arguments":{"city":"Seoul"}}</tool_call>';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });

  test('ExaoneMoeHandler returns a forced-open thought as reasoning', () {
    const call =
        '<tool_call>{"name":"weather","arguments":{"city":"Paris"}}</tool_call>';
    for (final (output, reasoning, calls) in [
      ('Plan it.\n', 'Plan it.\n', 0),
      ('Plan. $call', 'Plan. $call', 0),
      ('Plan.</think>\n$call', 'Plan.', 1),
    ]) {
      final parsed = ExaoneMoeHandler().parse(output, thinkingForcedOpen: true);
      expect(parsed.content, isEmpty, reason: output);
      expect(parsed.reasoningContent, reasoning, reason: output);
      expect(parsed.toolCalls, hasLength(calls), reason: output);
    }
  });
}
