import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/apertus_handler.dart';
import 'package:test/test.dart';

void main() {
  test('ApertusHandler renders lazy wrapped grammar and parses tool calls', () {
    final handler = ApertusHandler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
    );

    expect(handler.format, isA<ChatFormat>());
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammar, contains('"<|tools_prefix|>"'));
    expect(rendered.grammar, contains('"<|tools_suffix|>"'));
    expect(rendered.grammarLazy, isTrue);
    expect(rendered.preservedTokens, contains('<|tools_prefix|>'));
    expect(rendered.grammarTriggers, hasLength(1));

    final parsed = handler.parse(
      '<|tools_prefix|>[{"get_weather":{"city":"Seoul"}}]<|tools_suffix|> tail',
    );
    expect(parsed.content, equals('tail'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });

  test('ApertusHandler keeps malformed tool arrays as content', () {
    final handler = ApertusHandler();
    const input =
        '<|tools_prefix|>[{"get_weather":{"city":"Seoul"}},{"bad":{},"extra":true}]<|tools_suffix|>';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });

  test(
    'ApertusHandler keeps malformed prefixed payload when suffix is missing',
    () {
      final handler = ApertusHandler();
      const input = '<|tools_prefix|>[{"get_weather":{"city":"Seoul"}}]';

      final parsed = handler.parse(input);

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals(input));
    },
  );
}

Future<Object?> _noop(_) async {
  return 'ok';
}
