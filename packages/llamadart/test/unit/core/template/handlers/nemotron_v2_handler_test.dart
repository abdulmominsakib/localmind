import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/nemotron_v2_handler.dart';
import 'package:test/test.dart';

void main() {
  test('NemotronV2Handler renders lazy grammar and parses TOOLCALL blocks', () {
    final handler = NemotronV2Handler();
    final tools = [
      ToolDefinition(
        name: 'lookup',
        description: 'Lookup value',
        parameters: [ToolParam.string('key', required: true)],
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
    expect(rendered.grammar, contains('"<TOOLCALL>"'));
    expect(rendered.grammarLazy, isTrue);
    expect(rendered.grammarTriggers, hasLength(1));

    final parsed = handler.parse(
      '<TOOLCALL>[{"name":"lookup","arguments":{"key":"abc"}}]</TOOLCALL>tail',
    );
    expect(parsed.content, equals('tail'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('lookup'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('key', 'abc'),
    );

    final malformed = handler.parse(
      '<TOOLCALL>[{"arguments":{"key":"abc"}}]</TOOLCALL>',
    );
    expect(malformed.toolCalls, isEmpty);
    expect(
      malformed.content,
      equals('<TOOLCALL>[{"arguments":{"key":"abc"}}]</TOOLCALL>'),
    );
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
