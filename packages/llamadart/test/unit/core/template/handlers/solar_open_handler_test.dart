import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/solar_open_handler.dart';
import 'package:test/test.dart';

void main() {
  test('SolarOpenHandler exposes chat format', () {
    final handler = SolarOpenHandler();
    expect(handler.format, isA<ChatFormat>());
  });

  test('SolarOpenHandler emits parser and preserves tool tokens', () {
    final handler = SolarOpenHandler();
    final tools = <ToolDefinition>[
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: <ToolParam>[ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const <LlamaChatMessage>[
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const <String, String>{},
      tools: tools,
    );

    expect(rendered.parser, isNotNull);
    expect(rendered.parser, isNotEmpty);
    expect(rendered.preservedTokens, contains('<|tool_calls|>'));
    expect(rendered.grammarTriggers, hasLength(1));
    expect(rendered.grammarTriggers.first.type, equals(0));
    expect(rendered.grammarTriggers.first.value, equals('<|tool_calls|>'));
  });

  test('SolarOpen parser extracts reasoning, content, and tool calls', () {
    final handler = SolarOpenHandler();
    final tools = <ToolDefinition>[
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: <ToolParam>[ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const <LlamaChatMessage>[
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const <String, String>{},
      tools: tools,
    );

    final parsedReasoningContent = ChatTemplateEngine.parse(
      ChatFormat.solarOpen.index,
      '<|think|>plan<|end|><|begin|>assistant<|content|>answer',
      parser: rendered.parser,
    );
    expect(parsedReasoningContent.reasoningContent, equals('plan'));
    expect(parsedReasoningContent.content, equals('answer'));

    final parsedToolCall = ChatTemplateEngine.parse(
      ChatFormat.solarOpen.index,
      '<|tool_calls|>'
      '<|tool_call:begin|>0'
      '<|tool_call:name|>get_weather'
      '<|tool_call:args|>{"city":"Seoul"}'
      '<|tool_call:end|>',
      parser: rendered.parser,
    );

    expect(parsedToolCall.toolCalls, hasLength(1));
    expect(
      parsedToolCall.toolCalls.first.function?.name,
      equals('get_weather'),
    );
    expect(
      jsonDecode(parsedToolCall.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
