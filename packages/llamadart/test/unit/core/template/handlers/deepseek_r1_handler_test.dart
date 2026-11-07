import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/deepseek_r1_handler.dart';
import 'package:test/test.dart';

void main() {
  test('DeepseekR1Handler renders assistant content after think blocks', () {
    final handler = DeepseekR1Handler();
    final rendered = handler.render(
      templateSource:
          "{% if not add_generation_prompt is defined %}{% set add_generation_prompt = false %}{% endif %}"
          "{% if not bos_token is defined %}{% set bos_token = '<｜begin▁of▁sentence｜>' %}{% endif %}"
          "{% if not eos_token is defined %}{% set eos_token = '<｜end▁of▁sentence｜>' %}{% endif %}"
          "{{ bos_token }}"
          "{% for message in messages %}"
          "{% if message['role'] == 'user' %}"
          "{{ '<｜User｜>' + message['content'] }}"
          "{% elif message['role'] == 'assistant' and message['content'] is not none %}"
          "{% set content = message['content'] %}"
          "{% if '</think>' in content %}"
          "{% set content = content.split('</think>')[-1] %}"
          "{% endif %}"
          "{{ '<｜Assistant｜>' + content + eos_token }}"
          "{% endif %}"
          "{% endfor %}"
          "{% if add_generation_prompt %}"
          "{{ '<｜Assistant｜>' }}"
          "{% endif %}",
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello!'),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            LlamaTextContent('I am thinking... '),
            LlamaTextContent('<think>Reasoning here</think> Answer.'),
          ],
        ),
      ],
      metadata: const {},
    );

    expect(rendered.prompt, contains('<｜User｜>Hello!'));
    expect(rendered.prompt, contains('<｜Assistant｜> Answer.'));
    expect(rendered.prompt, endsWith('<｜Assistant｜>'));
  });

  test('DeepseekR1Handler renders grammar and parses modern tool block', () {
    final handler = DeepseekR1Handler();
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

    expect(handler.format, isA<ChatFormat>());
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammar, contains('<｜tool▁calls▁begin｜>'));
    expect(rendered.grammar, contains('city'));
    expect(rendered.prompt, endsWith('</think>\n'));
    expect(rendered.additionalStops, contains('<｜tool▁calls▁end｜>'));
    expect(rendered.grammarTriggers, hasLength(1));
    expect(
      rendered.grammarTriggers.first.value,
      contains(r'<｜tool\\_calls\\_begin｜>'),
    );

    final parsed = handler.parse(
      '<think>reasoning</think>answer '
      '<｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>function<｜tool▁sep｜>get_weather\n```json\n{"city":"Seoul"}\n```<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
    );

    expect(parsed.reasoningContent, equals('reasoning'));
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
      '<｜tool▁call▁begin｜>get_weather<｜tool▁sep｜>{"city":"Seoul"}<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
    );
    expect(malformedBlock.toolCalls, isEmpty);
    expect(malformedBlock.content, contains('<｜tool▁calls▁begin｜>'));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
