import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/hunyuan_v3_handler.dart';
import 'package:llamadart/src/core/template/tool_call_grammar_utils.dart';
import 'package:test/test.dart';

void main() {
  test('HunyuanV3Handler.toolCallOpening finds calls and the end token', () {
    for (final opening in const [
      '<tool_call:opensource>',
      '<tool_calls:opensource>',
      '<｜hy_eos:opensource｜>',
    ]) {
      expect(HunyuanV3Handler.toolCallOpening('Hi $opening'), 3);
      expect(
        HunyuanV3Handler.toolCallOpening('Hi ${opening.substring(0, 5)}'),
        3,
      );
    }
    expect(HunyuanV3Handler.toolCallOpening('Use <tool> or <x>.'), 18);
  });

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
    final toolRule = ToolCallGrammarUtils.ruleName('get_weather');

    expect(
      grammar,
      contains('$toolRule-units-arg-value ::= "metric" | "imperial" | string'),
    );
    expect(grammar, isNot(contains(r'\"metric\"')));
  });

  test('collision-free rules preserve Hunyuan tool and argument names', () {
    final tools = [
      _tool('a b'),
      ToolDefinition(
        name: 'a-b',
        description: 'Parameter collision coverage',
        parameters: [
          ToolParam.string('x y', required: true),
          ToolParam.string('x-y', required: true),
        ],
        handler: (_) async => null,
      ),
    ];
    final spacedToolRule = ToolCallGrammarUtils.ruleName('a b');
    final dashedToolRule = ToolCallGrammarUtils.ruleName('a-b');
    final spacedParameterRule = ToolCallGrammarUtils.ruleName('x y');
    final dashedParameterRule = ToolCallGrammarUtils.ruleName('x-y');

    expect(spacedToolRule, isNot(dashedToolRule));
    expect(spacedParameterRule, isNot(dashedParameterRule));
    final grammar = HunyuanV3Handler().buildGrammar(tools)!;
    expect(grammar, contains('$spacedToolRule-call ::='));
    expect(grammar, contains('$dashedToolRule-call ::='));
    expect(grammar, contains('$dashedToolRule-$spacedParameterRule-arg ::='));
    expect(grammar, contains('$dashedToolRule-$dashedParameterRule-arg ::='));
    expect(grammar, contains('<tool_call:opensource>a b<tool_sep:opensource>'));
    expect(grammar, contains('<tool_call:opensource>a-b<tool_sep:opensource>'));
    expect(grammar, contains('<arg_key:opensource>x y</arg_key:opensource>'));
    expect(grammar, contains('<arg_key:opensource>x-y</arg_key:opensource>'));

    final parsed = HunyuanV3Handler().parse(
      '<tool_calls:opensource>\n'
      '<tool_call:opensource>a-b<tool_sep:opensource>\n'
      '<arg_key:opensource>x y</arg_key:opensource>\n'
      '<arg_value:opensource>first</arg_value:opensource>\n'
      '<arg_key:opensource>x-y</arg_key:opensource>\n'
      '<arg_value:opensource>second</arg_value:opensource>\n'
      '</tool_call:opensource>\n'
      '</tool_calls:opensource>',
    );
    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.single.function?.name, 'a-b');
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
      'x y': 'first',
      'x-y': 'second',
    });
  });

  test('malformed Hunyuan blocks roll back atomically', () {
    const malformed =
        'before\n'
        '<tool_calls:opensource>\n'
        '<tool_call:opensource>a-b<tool_sep:opensource>\n'
        '<arg_key:opensource>x y</arg_key:opensource>\n'
        '<arg_value:opensource>unterminated\n'
        '</tool_call:opensource>\n'
        '</tool_calls:opensource>';

    final parsed = HunyuanV3Handler().parse(malformed);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, malformed);
  });

  test('preserves ordinary content around valid Hunyuan tool calls', () {
    const output =
        'before\n'
        '<tool_calls:opensource>\n'
        '<tool_call:opensource>inspect<tool_sep:opensource>\n'
        '</tool_call:opensource>\n'
        '</tool_calls:opensource>\n'
        'after<｜hy_eos:opensource｜>';

    final parsed = HunyuanV3Handler().parse(output);

    expect(parsed.content, 'before\n\nafter');
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.single.function?.name, 'inspect');
  });

  test('trailing partial Hunyuan blocks roll back the complete output', () {
    const output =
        'before\n'
        '<tool_calls:opensource>\n'
        '<tool_call:opensource>inspect<tool_sep:opensource>\n'
        '</tool_call:opensource>\n'
        '<tool_call:open';

    final parsed = HunyuanV3Handler().parse(output);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, output);
  });

  test('duplicate Hunyuan argument keys roll back atomically', () {
    const output =
        '<tool_calls:opensource>\n'
        '<tool_call:opensource>inspect<tool_sep:opensource>\n'
        '<arg_key:opensource>mode</arg_key:opensource>\n'
        '<arg_value:opensource>first</arg_value:opensource>\n'
        '<arg_key:opensource>mode</arg_key:opensource>\n'
        '<arg_value:opensource>second</arg_value:opensource>\n'
        '</tool_call:opensource>\n'
        '</tool_calls:opensource>';

    final parsed = HunyuanV3Handler().parse(output);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, output);
  });
}

ToolDefinition _tool(String name) => ToolDefinition(
  name: name,
  description: 'Collision coverage',
  parameters: const [],
  handler: (_) async => null,
);
