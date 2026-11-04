import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/xiaomi_mimo_handler.dart';
import 'package:test/test.dart';

void main() {
  test('XiaomiMimoHandler keeps lazy trigger and parses tool_call blocks', () {
    final handler = XiaomiMimoHandler();
    final tools = [
      ToolDefinition(
        name: 'weather',
        description: 'Weather lookup',
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
    expect(rendered.grammarLazy, isTrue);
    expect(
      rendered.grammarTriggers.first.value,
      equals('<tool_call>\n{"name": "'),
    );

    final parsed = handler.parse(
      '<tool_call>\n'
      '{"name": "weather", "arguments": {"city": "Seoul"}\n'
      '</tool_call> tail',
    );
    expect(parsed.content, equals('tail'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
