import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/glm45_handler.dart';
import 'package:test/test.dart';

void main() {
  test('Glm45Handler renders and parses glm xml tool calls', () {
    final handler = Glm45Handler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}<think>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
      enableThinking: false,
    );

    expect(rendered.prompt, endsWith('</think>\n'));
    expect(rendered.additionalStops, contains('<|observation|>'));
    expect(rendered.additionalStops, contains('<|user|>'));
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammarTriggers, isNotEmpty);

    final parsed = handler.parse(
      '<think>reasoning</think>\n'
      '<tool_call>\n'
      'get_weather\n'
      '<arg_key>city</arg_key><arg_value>"Seoul"</arg_value>\n'
      '<arg_key>days</arg_key><arg_value>2</arg_value>\n'
      '</tool_call>',
    );

    expect(parsed.reasoningContent, contains('reasoning'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('days', 2),
    );

    final noToolParse = handler.parse('plain response', parseToolCalls: false);
    expect(noToolParse.content, equals('plain response'));
    expect(noToolParse.toolCalls, isEmpty);
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
