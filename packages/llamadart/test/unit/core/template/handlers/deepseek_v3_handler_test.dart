import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/deepseek_v3_handler.dart';
import 'package:test/test.dart';

void main() {
  group('DeepseekV3Handler tool-call openings', () {
    const openings = [
      '<｜tool▁calls▁begin｜>',
      '<｜tool_calls_begin｜>',
      '<｜tool calls begin｜>',
      r'<｜tool\_calls\_begin｜>',
      '<｜tool▁calls｜>',
    ];

    test('toolCallOpening finds each whole or partial opening', () {
      for (final opening in openings) {
        expect(
          DeepseekV3Handler.toolCallOpening('Hi $opening'),
          3,
          reason: opening,
        );
        expect(
          DeepseekV3Handler.toolCallOpening('Hi ${opening.substring(0, 5)}'),
          3,
          reason: opening,
        );
      }
      expect(DeepseekV3Handler.toolCallOpening('Use <x> or <｜y｜>.'), 17);
    });

    test('parse extracts a call after each opening', () {
      for (final opening in openings) {
        final parsed = DeepseekV3Handler().parse(
          'Hi $opening<｜tool▁call▁begin｜>'
          '${'weather<｜tool▁sep｜>{"city": "Paris"}'}<｜tool▁call▁end｜><｜tool▁calls▁end｜>',
        );
        expect(parsed.content, 'Hi', reason: opening);
        expect(parsed.toolCalls.single.function?.name, 'weather');
      }
    });
  });

  test('DeepseekV3Handler supports system prepend and tool_call parsing', () {
    final handler = DeepseekV3Handler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource:
          '{{ messages[0]["content"] }}|{{ messages[1]["content"] }}<think>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.system, text: 'sys'),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {'tokenizer.ggml.bos_token': '<BOS>'},
      tools: tools,
      enableThinking: false,
    );

    expect(rendered.prompt, contains('<BOS>sys|hello'));
    expect(rendered.prompt, endsWith('</think>\n'));
    expect(rendered.grammar, contains('<｜tool▁calls▁begin｜>'));
    expect(rendered.grammar, contains('city'));
    expect(rendered.grammarTriggers, isNotEmpty);
    expect(
      rendered.grammarTriggers.first.value,
      contains(r'<｜tool\\_calls\\_begin｜>'),
    );

    final parsed = handler.parse(
      '<think>reasoning</think>'
      'answer '
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>get_weather<｜tool▁sep｜>{"city":"Seoul"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
    );

    expect(parsed.reasoningContent, contains('reasoning'));
    expect(parsed.content, equals('answer'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );

    final tokenParsed = handler.parse(
      '<｜tool calls begin｜>'
      'function<｜tool▁sep｜>get_weather\n```json\n{"city":"Seoul"}\n```'
      '<｜tool▁call▁end｜>',
    );
    expect(tokenParsed.toolCalls, isEmpty);

    final truncatedTokenParsed = handler.parse(
      '<｜tool▁call▁begin｜>function<｜tool▁sep｜>'
      'get_weather\n{"city":"Seoul"}',
    );
    expect(truncatedTokenParsed.toolCalls, isEmpty);

    final functionStylePayload = handler.parse(
      '<｜tool▁call▁begin｜>function<｜tool▁sep｜>'
      'weather_tool.get_weather_and_local_time(location="Seoul")'
      '<｜tool▁call▁end｜>',
    );
    expect(functionStylePayload.toolCalls, isEmpty);

    final malformedBlock = handler.parse(
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>{"city":"Seoul"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
    );
    expect(malformedBlock.toolCalls, isEmpty);
    expect(malformedBlock.content, contains('<｜tool▁calls▁begin｜>'));

    final noToolParse = handler.parse('plain', parseToolCalls: false);
    expect(noToolParse.content, equals('plain'));
  });

  test('DeepseekV3Handler matches llama.cpp forced-open edge semantics', () {
    final handler = DeepseekV3Handler();

    final multiple = handler.parse(
      'CONTENT'
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>get_time<｜tool▁sep｜>{"city":"Paris"}<｜tool▁call▁end｜>'
      '<｜tool▁call▁begin｜>get_weather<｜tool▁sep｜>{"city":"Paris"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
    );
    expect(multiple.content, equals('CONTENT'));
    expect(multiple.reasoningContent, isNull);
    expect(multiple.toolCalls, hasLength(2));
    expect(multiple.toolCalls[0].function?.name, equals('get_time'));
    expect(
      jsonDecode(multiple.toolCalls[0].function!.arguments!),
      equals({'city': 'Paris'}),
    );
    expect(multiple.toolCalls[1].function?.name, equals('get_weather'));
    expect(
      jsonDecode(multiple.toolCalls[1].function!.arguments!),
      equals({'city': 'Paris'}),
    );

    final forcedOpenFinal = handler.parse(
      'REASONING'
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>get_time<｜tool▁sep｜>{"city":"Tokyo"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
      thinkingForcedOpen: true,
      isPartial: false,
    );
    // llama.cpp `7fe450e1` with the DeepSeek V3.1 template returns this
    // unended forced-open thought as reasoning, with no tool call.
    expect(forcedOpenFinal.content, isEmpty);
    expect(
      forcedOpenFinal.reasoningContent,
      'REASONING'
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>get_time<｜tool▁sep｜>{"city":"Tokyo"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
    );
    expect(forcedOpenFinal.toolCalls, isEmpty);

    final forcedOpenPartial = handler.parse(
      'REASONING'
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>get_time<｜tool▁sep｜>{"city":"Tokyo"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
      thinkingForcedOpen: true,
      isPartial: true,
    );
    expect(forcedOpenPartial.content, equals(''));
    expect(
      forcedOpenPartial.reasoningContent,
      contains('<｜tool▁calls▁begin｜>'),
    );
    expect(forcedOpenPartial.toolCalls, isEmpty);

    final toolInReasoning = handler.parse(
      'REASONING'
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>get_time2<｜tool▁sep｜>{"city":"Tokyo2"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>'
      'REASONING'
      '</think>'
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>get_time<｜tool▁sep｜>{"city":"Tokyo"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
      thinkingForcedOpen: true,
      isPartial: false,
    );
    expect(toolInReasoning.content, equals(''));
    expect(toolInReasoning.toolCalls, hasLength(1));
    expect(toolInReasoning.toolCalls.first.function?.name, equals('get_time'));
    expect(
      jsonDecode(toolInReasoning.toolCalls.first.function!.arguments!),
      equals({'city': 'Tokyo'}),
    );
    expect(toolInReasoning.reasoningContent, contains('get_time2'));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
