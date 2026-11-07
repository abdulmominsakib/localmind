import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/hunyuan_v3_handler.dart';
import 'package:test/test.dart';

void main() {
  const template = '''
{%- set HYTK = ':opensource' -%}
{%- set assistant = '<｜hy_Assistant{}｜>'.format(HYTK) -%}
{%- set think = '<think{}>'.format(HYTK) -%}
{{- messages[0].content -}}
{%- if add_generation_prompt -%}
{{- assistant -}}
{%- if reasoning_effort == 'high' -%}{{- think -}}{%- endif -%}
{%- endif -%}
''';

  test('renders Python-style format calls and tracks forced thinking', () {
    final handler = HunyuanV3Handler();
    final result = handler.render(
      templateSource: template,
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      enableThinking: true,
    );

    expect(
      result.prompt,
      equals('hello<｜hy_Assistant:opensource｜><think:opensource>'),
    );
    expect(result.thinkingForcedOpen, isTrue);
  });

  test('parses namespaced reasoning and parallel tool calls', () {
    final parsed = HunyuanV3Handler().parse(
      '<think:opensource>plan</think:opensource>'
      '<tool_calls:opensource>\n'
      '<tool_call:opensource>get_weather<tool_sep:opensource>\n'
      '<arg_key:opensource>city</arg_key:opensource>\n'
      '<arg_value:opensource>Seoul</arg_value:opensource>\n'
      '<arg_key:opensource>days</arg_key:opensource>\n'
      '<arg_value:opensource>2</arg_value:opensource>\n'
      '</tool_call:opensource>\n'
      '<tool_call:opensource>get_time<tool_sep:opensource>\n'
      '<arg_key:opensource>zone</arg_key:opensource>\n'
      '<arg_value:opensource>UTC</arg_value:opensource>\n'
      '</tool_call:opensource>\n'
      '</tool_calls:opensource>',
    );

    expect(parsed.reasoningContent, equals('plan'));
    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(2));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      equals({'city': 'Seoul', 'days': 2}),
    );
    expect(parsed.toolCalls.last.function?.name, equals('get_time'));
  });

  test('builds lazy grammar around the Hunyuan tool envelope', () {
    final tool = ToolDefinition(
      name: 'get_weather',
      description: 'Get weather',
      parameters: [ToolParam.string('city', required: true)],
      handler: (_) async => null,
    );

    final grammar = HunyuanV3Handler().buildGrammar([tool]);

    expect(grammar, contains('<tool_calls:opensource>'));
    expect(grammar, contains('<tool_sep:opensource>'));
    expect(grammar, contains('<arg_key:opensource>city'));
  });

  test('emits enum values as raw GBNF literals', () {
    final tool = ToolDefinition(
      name: 'get_weather',
      description: 'Get weather',
      parameters: [
        ToolParam.enumType(
          'units',
          values: ['metric', 'imperial'],
          required: true,
        ),
      ],
      handler: (_) async => null,
    );

    final grammar = HunyuanV3Handler().buildGrammar([tool]);

    expect(
      grammar,
      contains(
        'get-weather-units-arg-value ::= "metric" | "imperial" | string',
      ),
    );
    expect(grammar, isNot(contains(r'\"metric\"')));
  });
}
