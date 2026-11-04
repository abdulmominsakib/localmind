import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:test/test.dart';

void main() {
  test('Lfm2Handler matches llama.cpp force-json-schema semantics', () {
    final handler = Lfm2Handler();
    final tools = [
      ToolDefinition(
        name: 'search',
        description: 'Search',
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
    expect(rendered.grammar, isNull);
    expect(rendered.grammarLazy, isFalse);
    expect(rendered.grammarTriggers, isEmpty);
    expect(rendered.preservedTokens, contains('<|tool_call_start|>'));
    expect(rendered.additionalStops, isEmpty);

    final renderedWithMarker = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: 'Force JSON schema.\nSystem prompt',
        ),
      ],
      metadata: const {},
      tools: tools,
    );
    expect(renderedWithMarker.prompt, equals('System prompt'));
    expect(renderedWithMarker.grammar, isNotNull);
    expect(renderedWithMarker.grammar, contains('"<|tool_call_start|>"'));
    expect(renderedWithMarker.grammarLazy, isTrue);
    expect(renderedWithMarker.grammarTriggers, hasLength(1));

    final renderedWithRequiredChoice = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: {internalToolChoiceMetadataKey: ToolChoice.required.name},
      tools: tools,
    );
    expect(renderedWithRequiredChoice.grammar, isNotNull);
    expect(
      renderedWithRequiredChoice.grammar,
      contains('"<|tool_call_start|>"'),
    );
    expect(renderedWithRequiredChoice.grammarLazy, isFalse);
    expect(renderedWithRequiredChoice.grammarTriggers, hasLength(1));

    final modern = handler.parse(
      '<|tool_call_start|>[{"name":"search","arguments":{"query":"llama"}}]<|tool_call_end|>',
    );
    expect(modern.toolCalls, hasLength(1));
    expect(modern.toolCalls.first.function?.name, equals('search'));
    expect(
      jsonDecode(modern.toolCalls.first.function!.arguments!),
      containsPair('query', 'llama'),
    );

    final pythonStyle = handler.parse(
      '<|tool_call_start|>[search(query=\'llama, dart\', limit=2, exact=true)]<|tool_call_end|>',
    );
    expect(pythonStyle.toolCalls, hasLength(1));
    expect(pythonStyle.toolCalls.first.function?.name, equals('search'));
    expect(jsonDecode(pythonStyle.toolCalls.first.function!.arguments!), {
      'query': 'llama, dart',
      'limit': 2,
      'exact': true,
    });

    final parallelPythonStyle = handler.parse(
      '<|tool_call_start|>[search(query=\'llama\'), search(query=\'dart\')]<|tool_call_end|>',
    );
    expect(parallelPythonStyle.toolCalls, hasLength(2));
    expect(parallelPythonStyle.toolCalls[0].index, 0);
    expect(parallelPythonStyle.toolCalls[1].index, 1);
    expect(parallelPythonStyle.toolCalls[0].function?.name, equals('search'));
    expect(parallelPythonStyle.toolCalls[1].function?.name, equals('search'));

    final inThinking = handler.parse(
      '<think>reasoning <|tool_call_start|>[{"name":"search","arguments":{"query":"llama"}}]<|tool_call_end|></think>',
    );
    expect(inThinking.toolCalls, hasLength(1));
    expect(inThinking.toolCalls.first.function?.name, equals('search'));
    expect(inThinking.reasoningContent, equals('reasoning'));
    expect(inThinking.content, isEmpty);

    final thinkingOnly = handler.parse(
      '<think>plan first</think>final answer',
      parseToolCalls: false,
    );
    expect(thinkingOnly.reasoningContent, equals('plan first'));
    expect(thinkingOnly.content, equals('final answer'));

    final legacy = handler.parse("[search(query='llama')] and text");
    expect(legacy.toolCalls, isEmpty);
    expect(legacy.content, equals("[search(query='llama')] and text"));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
