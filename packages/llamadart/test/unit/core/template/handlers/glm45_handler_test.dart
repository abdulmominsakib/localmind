import 'dart:convert';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/glm45_handler.dart';
import 'package:llamadart/src/core/template/handlers/llama_cpp_specialized_handlers.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/chat_template_handler.dart';
import 'package:test/test.dart';

void main() {
  test('Glm45Handler renders and parses glm xml tool calls', () {
    final handler = Glm45Handler();
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

    expect(rendered.prompt, endsWith('</think>\n'));
    expect(rendered.additionalStops, contains('<|observation|>'));
    expect(rendered.additionalStops, contains('<|user|>'));
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammarTriggers, isNotEmpty);

    final parsed = handler.parse(
      '<think>reasoning</think>\n'
      '<tool_call>\n'
      'get_weather\n'
      '<arg_key>city</arg_key><arg_value>"Seoul"</arg_value>\n'
      '<arg_key>days</arg_key><arg_value>2</arg_value>\n'
      '</tool_call>',
    );

    expect(parsed.reasoningContent, contains('reasoning'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('days', 2),
    );

    final noToolParse = handler.parse('plain response', parseToolCalls: false);
    expect(noToolParse.content, equals('plain response'));
    expect(noToolParse.toolCalls, isEmpty);
  });

  test('production parse preserves GLM schema-directed string values', () {
    final tool = ToolDefinition(
      name: 'inspect',
      description: 'Inspect',
      parameters: [
        ToolParam.enumType(
          'city',
          values: const ['Seoul', 'Paris'],
          required: true,
        ),
        ToolParam.string('code', required: true),
        ToolParam.integer('count', required: true),
      ],
      handler: _noop,
    );
    const output =
        '<tool_call>inspect\n'
        '<arg_key>city</arg_key><arg_value>"Seoul"</arg_value>\n'
        '<arg_key>code</arg_key><arg_value>123</arg_value>\n'
        '<arg_key>count</arg_key><arg_value>7</arg_value>\n'
        '</tool_call>';

    final parsed = ChatTemplateEngine.parse(
      ChatFormat.glm45.index,
      output,
      tools: [tool],
    );

    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
      'city': 'Seoul',
      'code': '123',
      'count': 7,
    });
  });

  test('production parse rolls back all mixed-validity GLM calls', () {
    final tool = ToolDefinition(
      name: 'inspect',
      description: 'Inspect',
      parameters: [ToolParam.string('code', required: true)],
      handler: _noop,
    );
    const valid =
        '<tool_call>inspect\n'
        '<arg_key>code</arg_key><arg_value>first</arg_value>\n'
        '</tool_call>';
    for (final invalid in const [
      '<tool_call>unknown\n</tool_call>',
      '<tool_call>inspect\n'
          '<arg_key>unknown</arg_key><arg_value>ignored</arg_value>\n'
          '</tool_call>',
      '<tool_call>inspect\n'
          '<arg_key>code</arg_key><arg_value>first</arg_value>\n'
          '<arg_key>code</arg_key><arg_value>second</arg_value>\n'
          '</tool_call>',
    ]) {
      final output = '$valid$invalid';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.glm45.index,
        output,
        tools: [tool],
      );
      expect(parsed.toolCalls, isEmpty, reason: invalid);
      expect(parsed.content, output, reason: invalid);
    }
  });

  test('final GLM and Laguna parsing rolls back a truncated later call', () {
    final tool = ToolDefinition(
      name: 'inspect',
      description: 'Inspect',
      parameters: [ToolParam.string('code', required: true)],
      handler: _noop,
    );
    const valid =
        '<tool_call>inspect\n'
        '<arg_key>code</arg_key><arg_value>first</arg_value>\n'
        '</tool_call>';
    const truncated =
        '<tool_call>inspect\n'
        '<arg_key>code</arg_key><arg_value>second';
    const output = '$valid$truncated';

    for (final format in [ChatFormat.glm45, ChatFormat.laguna]) {
      for (final finalOutput in const [
        output,
        '$valid<tool_cal',
        '$valid</arg_val',
      ]) {
        final parsed = ChatTemplateEngine.parse(
          format.index,
          finalOutput,
          tools: [tool],
        );
        expect(parsed.toolCalls, isEmpty, reason: format.name);
        expect(parsed.content, finalOutput, reason: format.name);
      }

      for (final partialOutput in const [
        output,
        '$valid<tool_cal',
        '$valid</arg_val',
      ]) {
        final partial = ChatTemplateEngine.parse(
          format.index,
          partialOutput,
          tools: [tool],
          isPartial: true,
        );
        expect(partial.toolCalls, hasLength(1), reason: format.name);
        expect(partial.content, isEmpty, reason: format.name);
        expect(jsonDecode(partial.toolCalls.single.function!.arguments!), {
          'code': 'first',
        }, reason: format.name);
      }
    }
  });

  test('GLM and Laguna reject empty or duplicate tool identities eagerly', () {
    final empty = ToolDefinition(
      name: '',
      description: 'Empty',
      parameters: const [],
      handler: _noop,
    );
    final duplicateA = ToolDefinition(
      name: 'inspect',
      description: 'First',
      parameters: const [],
      handler: _noop,
    );
    final duplicateB = ToolDefinition(
      name: 'inspect',
      description: 'Second',
      parameters: const [],
      handler: _noop,
    );

    final builders = <String? Function(List<ToolDefinition>?)>[
      Glm45Handler().buildGrammar,
      LagunaHandler().buildGrammar,
    ];
    for (final buildGrammar in builders) {
      expect(
        () => buildGrammar([empty]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('non-empty tool names'),
          ),
        ),
      );
      expect(
        () => buildGrammar([duplicateA, duplicateB]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('unique tool names'),
          ),
        ),
      );
    }
  });

  test('production parse rejects duplicate GLM and Laguna arguments', () {
    final tool = ToolDefinition(
      name: 'inspect',
      description: 'Inspect',
      parameters: [ToolParam.string('code', required: true)],
      handler: _noop,
    );
    const output =
        '<tool_call>inspect\n'
        '<arg_key>code</arg_key><arg_value>first</arg_value>\n'
        '<arg_key>code</arg_key><arg_value>second</arg_value>\n'
        '</tool_call>';

    for (final format in [ChatFormat.glm45, ChatFormat.laguna]) {
      final parsed = ChatTemplateEngine.parse(
        format.index,
        output,
        tools: [tool],
      );
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    }
  });

  test('production parse rejects malformed GLM and Laguna argument bodies', () {
    final tool = ToolDefinition(
      name: 'inspect',
      description: 'Inspect',
      parameters: [ToolParam.string('code', required: true)],
      handler: _noop,
    );
    const validPair = '<arg_key>code</arg_key><arg_value>first</arg_value>';
    const malformedBodies = [
      '$validPair<arg_key> </arg_key><arg_value>ignored</arg_value>',
      '$validPair<arg_key>truncated',
    ];

    for (final format in [ChatFormat.glm45, ChatFormat.laguna]) {
      for (final body in malformedBodies) {
        final output = '<tool_call>inspect\n$body\n</tool_call>';
        final parsed = ChatTemplateEngine.parse(
          format.index,
          output,
          tools: [tool],
        );
        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, output);
      }
    }
  });

  test('GLM raw string states return to the start state once', () {
    // One grammar alternative per character made llama.cpp keep ~18 stacks
    // per value position: about 4 s per sampled token on a 155k vocabulary.
    final grammar = Glm45Handler().buildGrammar([
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ])!;
    final rawRules = grammar
        .split('\n')
        .where((line) => line.startsWith('glm-string-raw-'))
        .toList();

    expect(
      rawRules,
      contains(
        'glm-string-raw-0 ::= ([<] glm-string-raw-1 | [^<] glm-string-raw-0)?',
      ),
    );
    for (final rule in rawRules) {
      final body = rule.substring(rule.indexOf('::='));
      expect(
        RegExp(r'glm-string-raw-0(?!\d)').allMatches(body),
        hasLength(1),
        reason: rule,
      );
    }
  });

  test('GLM grammar leaves layout newlines optional', () {
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [
          ToolParam.string('city', required: true),
          ToolParam.integer('days'),
        ],
        handler: _noop,
      ),
    ];
    final grammar = Glm45Handler().buildGrammar(tools)!.split('\n');

    expect(grammar, LagunaHandler().buildGrammar(tools)!.split('\n'));
    expect(
      grammar,
      containsAll([
        'tool-call ::= "\\n"? "<tool_call>" glm-space tool-choice glm-space '
            '"</tool_call>" glm-space',
        'get-u5f-weather-call ::= "get_weather" glm-space get-u5f-weather-arg-city '
            '(glm-space get-u5f-weather-arg-days)?',
        'get-u5f-weather-arg-city ::= "<arg_key>city</arg_key>" "\\n"? '
            '"<arg_value>" get-u5f-weather-arg-city-value "</arg_value>"',
        'glm-space ::= | " " | "\\n"{1,2} [ \\t]{0,20}',
      ]),
    );
  });

  test('GLM and Laguna parse compact and newline layouts alike', () {
    const compact =
        '<tool_call>weather<arg_key>city</arg_key><arg_value>Seoul</arg_value>'
        '<arg_key>days</arg_key><arg_value>2</arg_value></tool_call>';
    const newline =
        '<tool_call>weather\n<arg_key>city</arg_key>\n'
        '<arg_value>Seoul</arg_value>\n<arg_key>days</arg_key>\n'
        '<arg_value>2</arg_value>\n</tool_call>\n';
    final tools = [
      ToolDefinition(
        name: 'weather',
        description: 'Weather',
        parameters: [
          ToolParam.string('city', required: true),
          ToolParam.integer('days'),
        ],
        handler: _noop,
      ),
    ];
    for (final ToolSchemaAwareChatTemplateHandler handler in [
      Glm45Handler(),
      LagunaHandler(),
    ]) {
      for (final call in [compact, newline]) {
        final parsed = handler.parseWithTools('Checking.$call', tools: tools);
        expect(parsed.content, 'Checking.', reason: call);
        expect(parsed.toolCalls.single.function?.name, 'weather');
        expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
          'city': 'Seoul',
          'days': 2,
        });

        final cut = call.indexOf('Seoul') + 3;
        final partial = handler.parseWithTools(
          'Checking.${call.substring(0, cut)}',
          tools: tools,
          isPartial: true,
        );
        expect(partial.content, 'Checking.', reason: call);
        expect(partial.toolCalls, isEmpty);
      }
    }
  });

  test('hides incomplete GLM tool markup only while streaming', () {
    const output =
        'Visible answer.\n'
        '<tool_call>weather\n'
        '<arg_key>city</arg_key><arg_value>Seo';

    final partial = Glm45Handler().parse(output, isPartial: true);
    expect(partial.content, 'Visible answer.');
    expect(partial.toolCalls, isEmpty);

    final completed = Glm45Handler().parse(output);
    expect(completed.content, output);
    expect(completed.toolCalls, isEmpty);
  });

  test('GLM and Laguna distinguish protocol markers from near-lookalikes', () {
    final tool = ToolDefinition(
      name: 'inspect',
      description: 'Inspect',
      parameters: [ToolParam.string('code', required: true)],
      handler: _noop,
    );
    const markers = [
      '<tool_call>',
      '</tool_call>',
      '<arg_key>',
      '</arg_key>',
      '<arg_value>',
      '</arg_value>',
    ];

    for (final format in [ChatFormat.glm45, ChatFormat.laguna]) {
      for (final marker in markers) {
        final invalidOutput =
            '<tool_call>inspect\n'
            '<arg_key>code</arg_key><arg_value>before$marker after'
            '</arg_value>\n'
            '</tool_call>';
        final invalid = ChatTemplateEngine.parse(
          format.index,
          invalidOutput,
          tools: [tool],
        );
        expect(invalid.toolCalls, isEmpty, reason: '$format $marker');
        expect(invalid.content, invalidOutput, reason: '$format $marker');

        final nearLookalike = '${marker.substring(0, marker.length - 1)}X';
        final validOutput =
            '<tool_call>inspect\n'
            '<arg_key>code</arg_key><arg_value>before$nearLookalike after'
            '</arg_value>\n'
            '</tool_call>';
        final valid = ChatTemplateEngine.parse(
          format.index,
          validOutput,
          tools: [tool],
        );
        expect(valid.toolCalls, hasLength(1), reason: '$format $nearLookalike');
        expect(jsonDecode(valid.toolCalls.single.function!.arguments!), {
          'code': 'before$nearLookalike after',
        }, reason: '$format $nearLookalike');
        expect(valid.content, isEmpty, reason: '$format $nearLookalike');

        for (final output in [
          'before$nearLookalike\n$validOutput',
          '$validOutput\nafter$nearLookalike',
        ]) {
          final surrounded = ChatTemplateEngine.parse(
            format.index,
            output,
            tools: [tool],
          );
          expect(
            surrounded.toolCalls,
            hasLength(1),
            reason: '$format surrounding $nearLookalike',
          );
          expect(
            surrounded.content,
            output.replaceFirst(validOutput, '').trim(),
            reason: '$format surrounding $nearLookalike',
          );
        }
      }
    }
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
