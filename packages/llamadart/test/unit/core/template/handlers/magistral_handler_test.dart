import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/magistral_handler.dart';
import 'package:test/test.dart';

void main() {
  test('MagistralHandler renders and parses TOOL_CALLS payload', () {
    final handler = MagistralHandler();
    final tools = [
      ToolDefinition(
        name: 'search',
        description: 'Search docs',
        parameters: [ToolParam.string('query', required: true)],
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
    expect(rendered.additionalStops, contains('[TOOL_CALLS]'));
    expect(rendered.preservedTokens, contains('[THINK]'));
    expect(rendered.grammarTriggers.first.value, equals('[TOOL_CALLS]'));

    final parsed = handler.parse(
      '[TOOL_CALLS][{"name":"search","arguments":{"query":"llama"}}]',
    );
    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('search'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('query', 'llama'),
    );
  });

  test('keeps Ministral [ARGS] payload as plain content', () {
    final handler = MagistralHandler();
    const input = '[TOOL_CALLS]get-weather[ARGS]{"location":"Seoul"}';
    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });

  test('parses tool-call JSON array when marker is missing', () {
    final handler = MagistralHandler();
    final parsed = handler.parse(
      '[{"name":"get_weather","arguments":{"city":"Seoul"}}]',
    );

    expect(parsed.toolCalls, isEmpty);
    expect(
      parsed.content,
      equals('[{"name":"get_weather","arguments":{"city":"Seoul"}}]'),
    );
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
