import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/minimax_m2_handler.dart';
import 'package:test/test.dart';

void main() {
  test('MinimaxM2Handler parses minimax XML tool calls', () {
    final handler = MinimaxM2Handler();
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
    expect(rendered.grammarTriggers, isNotEmpty);

    final parsed = handler.parse(
      '<minimax:tool_call>\n'
      '<invoke name="get_weather">\n'
      '<parameter name="city">"Seoul"</parameter>\n'
      '</invoke>\n'
      '</minimax:tool_call>'
      'tail',
    );
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
    expect(parsed.content, equals('tail'));

    final noTool = handler.parse('plain', parseToolCalls: false);
    expect(noTool.content, equals('plain'));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
