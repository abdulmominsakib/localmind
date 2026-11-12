import 'dart:convert';
import 'dart:math';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/hermes_handler.dart';
import 'package:llamadart/src/core/template/tool_call_grammar_utils.dart';
import 'package:test/test.dart';

void main() {
  group('cancelled Qwen tool envelopes', () {
    const complete =
        '<tool_call>{"name":"weather","arguments":{"city":"Paris"}}'
        '</tool_call>';
    const payload =
        '<tool_call>{"name":"weather","arguments":{"city":"Seoul"}}';
    final handler = HermesHandler();

    for (final partial in [false, true]) {
      test('drops every unfinished envelope (partial=$partial)', () {
        // llama.cpp b10549's Qwen3-4B parser keeps only preceding content
        // at these cut points with its `<tool_call>\n` delimiter. Hermes
        // also accepts the same wire form without the newline.
        for (final call in [
          complete,
          complete.replaceFirst('<tool_call>', '<tool_call>\n'),
        ]) {
          for (var end = '<tool_call>'.length; end < call.length; end++) {
            final parsed = handler.parse(
              'Checking. ${call.substring(0, end)}',
              isPartial: partial,
              cancelled: true,
            );
            expect(parsed.content, 'Checking.', reason: 'cut at $end');
            expect(parsed.toolCalls, isEmpty, reason: 'cut at $end');
          }
        }
      });

      test('keeps earlier complete calls (partial=$partial)', () {
        for (final tail in ['<tool_call>', '<tool_call>{"na', payload]) {
          final parsed = handler.parse(
            'Checking. $complete$tail',
            isPartial: partial,
            cancelled: true,
          );
          expect(parsed.content, 'Checking.', reason: tail);
          expect(parsed.toolCalls, hasLength(1), reason: tail);
          expect(parsed.toolCalls.single.function?.name, 'weather');
          expect(
            parsed.toolCalls.single.function?.arguments,
            '{"city":"Paris"}',
          );
        }
      });

      test('keeps complete output and quoted markers (partial=$partial)', () {
        const call =
            '<tool_call>{"name":"echo","arguments":{"text":"<tool_call>"}}'
            '</tool_call>';
        final parsed = handler.parse(
          'Before. $call After.',
          isPartial: partial,
          cancelled: true,
        );
        expect(parsed.content, 'Before. After.');
        expect(
          parsed.toolCalls.single.function?.arguments,
          '{"text":"<tool_call>"}',
        );
      });
    }

    test('a quoted closing tag cannot complete an interrupted call', () {
      for (final suffix in [
        '</tool_call>"}}',
        '</tool_call>',
        '</tool_call>\\',
        r'\"</tool_call>',
      ]) {
        final output =
            'Checking. <tool_call>{"name":"echo",'
            '"arguments":{"text":"$suffix';
        for (final partial in [false, true]) {
          final parsed = handler.parse(
            output,
            isPartial: partial,
            cancelled: true,
          );
          expect(parsed.content, 'Checking.', reason: output);
          expect(parsed.toolCalls, isEmpty, reason: output);
        }
      }
    });

    test('natural EOS retains raw unfinished and malformed output', () {
      for (final output in [
        'Let me check. <tool_call>\n{...}\n',
        '<tool_call>\n{"name":"weather","arguments":{"city":"Paris"}}',
        '<tool_call>\n{"name": "weather", "arguments": {"city": "Pa}}\n</tool_call>',
        'For tool calls, write <tool_call>{"name": "x"} as shown.',
      ]) {
        expect(handler.parse(output).content, output.trim(), reason: output);
        expect(handler.parse(output).toolCalls, isEmpty, reason: output);
      }
    });

    test('schema-backed final parsing stays strict for interrupted calls', () {
      final tool = ToolDefinition.fromJsonSchema(
        name: 'weather',
        description: 'Get weather',
        schema: {'type': 'object', 'properties': <String, dynamic>{}},
      );
      for (final tail in ['<tool_call>', '<tool_call>{"name":"weather",']) {
        expect(
          () => ChatTemplateEngine.parse(
            ChatFormat.hermes.index,
            'Checking. $tail',
            tools: [tool],
          ),
          throwsA(isA<LlamaInferenceException>()),
        );
        final partial = ChatTemplateEngine.parse(
          ChatFormat.hermes.index,
          'Checking. $tail',
          tools: [tool],
          isPartial: true,
        );
        expect(partial.content, 'Checking.');
        expect(partial.toolCalls, isEmpty);
      }
    });

    final schemaTool = ToolDefinition.fromJsonSchema(
      name: 'weather',
      description: 'Get weather',
      schema: {
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
        'required': ['city'],
      },
    );
    for (final (label, output, completeCalls) in [
      (
        'unfinished arguments',
        'Checking. <tool_call>\n{"name":"weather","arguments":{"city":"Par',
        0,
      ),
      ('unfinished name', 'Checking. <tool_call>\n{"name":"weather"', 0),
      (
        'unfinished second call',
        'Checking. $complete<tool_call>\n{"name":"weather"',
        1,
      ),
    ]) {
      test('cancelled named envelope stays schema-strict: $label', () {
        expect(
          () => ChatTemplateEngine.parse(
            ChatFormat.hermes.index,
            output,
            tools: [schemaTool],
            cancelled: true,
          ),
          throwsA(isA<LlamaInferenceException>()),
        );
        final partial = ChatTemplateEngine.parse(
          ChatFormat.hermes.index,
          output,
          tools: [schemaTool],
          cancelled: true,
          isPartial: true,
        );
        expect(partial.content, 'Checking.');
        expect(partial.toolCalls, hasLength(completeCalls));
        final legacy = ChatTemplateEngine.parse(
          ChatFormat.hermes.index,
          output,
          cancelled: true,
        );
        expect(legacy.content, 'Checking.');
        expect(legacy.toolCalls, hasLength(completeCalls));
        if (completeCalls > 0) {
          expect(legacy.toolCalls.single.function?.name, 'weather');
          expect(
            legacy.toolCalls.single.function?.arguments,
            '{"city":"Paris"}',
          );
        }
      });
    }

    test('partial cancel drops an unclosed schema-valid second call', () {
      const output =
          'Checking. $complete<tool_call>\n'
          '{"name":"weather","arguments":{"city":"Rome"}}';
      final partial = ChatTemplateEngine.parse(
        ChatFormat.hermes.index,
        output,
        tools: [schemaTool],
        cancelled: true,
        isPartial: true,
      );
      expect(partial.content, 'Checking.');
      expect(partial.toolCalls, hasLength(1));
      expect(partial.toolCalls.single.function?.arguments, '{"city":"Paris"}');
    });

    test('cancelled double-brace calls retain legacy recovery', () {
      const output =
          '<tool_call>\n{{"name":"weather","arguments":{"city":"Paris"}}}';
      for (final cancelled in [false, true]) {
        final parsed = handler.parse(output, cancelled: cancelled);
        expect(parsed.content, '<tool_call>\n{}');
        expect(parsed.toolCalls, hasLength(1));
        expect(parsed.toolCalls.single.function?.name, 'weather');
        expect(parsed.toolCalls.single.function?.arguments, '{"city":"Paris"}');
      }

      final singleBrace = handler.parse(
        '<tool_call>\n{"name":"weather","arguments":{"city":"Paris"}}',
        cancelled: true,
      );
      expect(singleBrace.content, isEmpty);
      expect(singleBrace.toolCalls, isEmpty);
    });

    test(
      'cancelled schema final rejects a pending tail after a complete call',
      () {
        final schemaTool = ToolDefinition.fromJsonSchema(
          name: 'weather',
          description: 'Get weather',
          schema: {'type': 'object', 'properties': <String, dynamic>{}},
        );
        final legacyTool = ToolDefinition(
          name: 'weather',
          description: 'Get weather',
          parameters: [ToolParam.string('city')],
          handler: _noop,
        );
        for (final tail in ['<tool_call>', '<tool_call>{"na']) {
          final output = 'Checking. $complete$tail';
          for (final cancelled in [false, true]) {
            expect(
              () => ChatTemplateEngine.parse(
                ChatFormat.hermes.index,
                output,
                tools: [schemaTool],
                cancelled: cancelled,
              ),
              throwsA(isA<LlamaInferenceException>()),
              reason: 'cancelled=$cancelled, tail=$tail',
            );
          }
          for (final (tool, partial) in [
            (schemaTool, true),
            (legacyTool, false),
          ]) {
            final parsed = ChatTemplateEngine.parse(
              ChatFormat.hermes.index,
              output,
              tools: [tool],
              isPartial: partial,
              cancelled: true,
            );
            expect(parsed.content, 'Checking.');
            expect(parsed.toolCalls, hasLength(1));
            expect(parsed.toolCalls.single.function?.name, 'weather');
            expect(
              parsed.toolCalls.single.function?.arguments,
              '{"city":"Paris"}',
            );
          }
        }
      },
    );

    test('keeps literal content when tool parsing is disabled', () {
      for (final partial in [false, true]) {
        final parsed = handler.parse(
          'Checking. $payload',
          isPartial: partial,
          cancelled: true,
          parseToolCalls: false,
        );
        expect(parsed.content, 'Checking. $payload');
        expect(parsed.toolCalls, isEmpty);
      }
    });

    test('keeps closed malformed envelopes and unrelated text', () {
      for (final text in [
        '<tool_call>{"arguments":{}}</tool_call>',
        '<tool_call>\n{"name": "weather", "arguments": {"city": "Pa}}\n</tool_call>',
        'Use <tool_calling> for an example.',
        'Use <tool_call> to start a call.',
        '{"text":"<tool_call>"}',
        'Here is {"name":"weather",',
      ]) {
        expect(handler.parse(text).content, text);
        expect(handler.parse(text, cancelled: true).content, text);
      }
    });
  });

  test('HermesHandler renders valid grammar and parses tool calls', () {
    final handler = HermesHandler();
    final tools = [
      ToolDefinition(
        name: 'get_current_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('location', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
      ],
      metadata: const {},
      tools: tools,
    );

    expect(handler.format, isA<ChatFormat>());
    expect(rendered.grammar, isNotNull);
    expect(
      rendered.grammar,
      contains(r'string ::= "\"" ([^"\\] | "\\\\" .)* "\""'),
    );
    expect(rendered.grammar, isNot(contains(r'string ::= "\\\""')));

    final parsed = handler.parse(
      '<tool_call>{"name":"get_current_weather","arguments":{"location":"Seoul"}}</tool_call> tail',
    );
    expect(parsed.toolCalls, hasLength(1));
    expect(
      parsed.toolCalls.first.function?.name,
      equals('get_current_weather'),
    );
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('location', 'Seoul'),
    );
    expect(parsed.content, equals('tail'));
  });

  test('passes enableThinking into the template context', () {
    final handler = HermesHandler();
    const template =
        '{% if enable_thinking is defined and enable_thinking is false %}'
        'thinking-off'
        '{% else %}'
        'thinking-on'
        '{% endif %}';
    const messages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
    ];

    final disabled = handler.render(
      templateSource: template,
      messages: messages,
      metadata: const {},
      enableThinking: false,
    );
    final enabled = handler.render(
      templateSource: template,
      messages: messages,
      metadata: const {},
      enableThinking: true,
    );

    expect(disabled.prompt, 'thinking-off');
    expect(enabled.prompt, 'thinking-on');
  });

  test('parses tool call with space between tag and JSON', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '<tool_call> {"name":"get_current_weather","arguments":{"location":"Seoul"}}</tool_call>',
    );
    expect(parsed.toolCalls, hasLength(1));
    expect(
      parsed.toolCalls.first.function?.name,
      equals('get_current_weather'),
    );
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('location', 'Seoul'),
    );
    expect(parsed.content, isEmpty);
  });

  test('parses tool call with newline between tag and JSON', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '<tool_call>\n{"name":"get_current_weather","arguments":{"location":"Seoul"}}\n</tool_call>',
    );
    expect(parsed.toolCalls, hasLength(1));
    expect(
      parsed.toolCalls.first.function?.name,
      equals('get_current_weather'),
    );
    expect(parsed.content, isEmpty);
  });

  test('keeps partial bare JSON tool calls out of content', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '{"name":"get_current_weather",',
      isPartial: true,
    );

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, isEmpty);
  });

  test('keeps partial XML tool-call envelopes out of content', () {
    final handler = HermesHandler();
    final parsed = handler.parse('<tool_call>{"na', isPartial: true);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, isEmpty);
  });

  test(
    'parses tool call with multiple whitespace chars between tag and JSON',
    () {
      final handler = HermesHandler();
      final parsed = handler.parse(
        '<tool_call>  \n  {"name":"get_current_weather","arguments":{"location":"Seoul"}}\n</tool_call>',
      );
      expect(parsed.toolCalls, hasLength(1));
      expect(
        parsed.toolCalls.first.function?.name,
        equals('get_current_weather'),
      );
      expect(parsed.content, isEmpty);
    },
  );

  test('parses <function=name> JSON </function> tool call', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '<function=get_current_weather>{"location":"Seoul"}</function>',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(
      parsed.toolCalls.first.function?.name,
      equals('get_current_weather'),
    );
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('location', 'Seoul'),
    );
  });

  test('parses <function name="..."> JSON </function> tool call', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '<function name="get_current_weather">{"location":"Seoul"}</function>',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(
      parsed.toolCalls.first.function?.name,
      equals('get_current_weather'),
    );
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('location', 'Seoul'),
    );
  });

  test('parses fenced <tool_call> JSON block', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '```xml\n'
      '<tool_call>{"name":"bad","arguments":{"k":"v"}}</tool_call>\n'
      '```',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('bad'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('k', 'v'),
    );
    expect(parsed.content, isEmpty);
  });

  test('preserves string arguments in <tool_call> payloads', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '<tool_call>{"name":"get_current_weather","arguments":"{\\"location\\":\\"Seoul\\"}"}</tool_call>',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(
      parsed.toolCalls.first.function?.arguments,
      equals('{"location":"Seoul"}'),
    );
  });

  test('keeps malformed tagged payload as content', () {
    final handler = HermesHandler();
    const input = '<tool_call>{"arguments":{"location":"Seoul"}}</tool_call>';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });

  test('collision-free grammar rules preserve Hermes wire names', () {
    final handler = HermesHandler();
    final tools = [_tool('a b'), _tool('a-b')];
    final spacedRule = ToolCallGrammarUtils.ruleName('a b');
    final dashedRule = ToolCallGrammarUtils.ruleName('a-b');

    expect(spacedRule, isNot(dashedRule));
    final grammar = handler.buildGrammar(tools)!;
    expect(grammar, contains('$spacedRule-call ::='));
    expect(grammar, contains('$dashedRule-call ::='));
    expect(grammar, contains(r'\"name\": \"a b\"'));
    expect(grammar, contains(r'\"name\": \"a-b\"'));

    const output =
        'before '
        '<tool_call>{"name":"a-b","arguments":{}}</tool_call>'
        ' after';
    final parsed = handler.parse(output);
    expect(parsed.content, 'before after');
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.single.function?.name, 'a-b');
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), isEmpty);
  });

  test('keeps non-tagged payload as content', () {
    final handler = HermesHandler();
    final parsed = handler.parse(
      '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}; '
      '{"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
    );

    expect(parsed.toolCalls, isEmpty);
    expect(
      parsed.content,
      '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}; '
      '{"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
    );
  });

  group('double-brace <tool_call> payloads', () {
    const doubleBrace =
        '<tool_call>\n{{"name": "get_weather", "arguments": {"city": "Paris"}}\n</tool_call>';
    const balancedDoubleBrace =
        '<tool_call>\n{{"name": "get_weather", "arguments": {"city": "Paris"}}}\n</tool_call>';

    void expectWeatherCall(ChatParseResult parsed) {
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.single.function?.name, 'get_weather');
      expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
        'city': 'Paris',
      });
    }

    for (final (name, output) in [
      ('without', doubleBrace),
      ('with', balancedDoubleBrace),
    ]) {
      test('extracts the call $name the outer closing brace', () {
        final parsed = HermesHandler().parse(output);

        expectWeatherCall(parsed);
        expect(parsed.content, isEmpty);
      });

      test('streams no brace $name the outer closing brace', () {
        final handler = HermesHandler();
        for (var end = 1; end <= output.length; end++) {
          final parsed = handler.parse(
            output.substring(0, end),
            isPartial: true,
          );
          expect(
            parsed.content,
            isNot(matches(RegExp('[{}]'))),
            reason: '$end',
          );
        }

        final complete = handler.parse(output, isPartial: true);
        expectWeatherCall(complete);
        expect(complete.content, isEmpty);
      });
    }

    test('keeps the text around the call', () {
      final parsed = HermesHandler().parse(
        'Checking {weather}.\n$doubleBrace\nDone: {"ok": true}',
      );

      expectWeatherCall(parsed);
      expect(parsed.content, 'Checking {weather}.\nDone: {"ok": true}');
    });

    test('extracts several single- and double-brace calls', () {
      final parsed = HermesHandler().parse(
        '$doubleBrace\n'
        '<tool_call>\n{"name": "get_time", "arguments": {}}\n</tool_call>\n'
        '$balancedDoubleBrace',
      );

      expect(parsed.toolCalls.map((call) => call.function?.name), [
        'get_weather',
        'get_time',
        'get_weather',
      ]);
      expect(parsed.content, isEmpty);
    });

    test('keeps literal braces that are not a tagged call as content', () {
      const output = 'Use {{name}} in Jinja and {"name"} is not JSON.';

      final parsed = HermesHandler().parse(output);

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    });

    test('consumes no outer brace without a tool tag', () {
      final parsed = HermesHandler().parse(
        'Use {{"name": "get_weather", "arguments": {}}} here',
      );

      expect(parsed.toolCalls.single.function?.name, 'get_weather');
      expect(parsed.content, 'Use {} here');
    });

    for (final output in [
      '<tool_call>\n{{"name": "get_weather", "arguments": {"city": "Par',
      '<tool_call>\n{{"name": "get_weather", "arguments": {"city": "Par\n</tool_call>',
      '<tool_call>\n{{"name": 5, "arguments": {}}}\n</tool_call>',
      '<tool_call>\n{{"arguments": {"city": "Paris"}}}\n</tool_call>',
      '<tool_call>\n{"name": "get_weather", "arguments": {}}}\n</tool_call>',
    ]) {
      test('keeps malformed ${jsonEncode(output)} as content', () {
        final parsed = HermesHandler().parse(output);

        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, output);
      });
    }

    test('consumes any number of extra closing braces', () {
      for (final closing in ['}}}', '}}}}', '}} } }', '}}}}}\n']) {
        final parsed = HermesHandler().parse(
          '<tool_call>\n{{"name": "get_weather", '
          '"arguments": {"city": "Paris"}$closing\n</tool_call>',
        );

        expectWeatherCall(parsed);
        expect(parsed.content, isEmpty, reason: closing);
      }
    });

    for (final (name, output, content) in [
      (
        'text before the close tag',
        '<tool_call>\n{{"name": "get_weather", "arguments": {"city": "Paris"}}} x\n</tool_call>',
        '<tool_call>\n{} x\n</tool_call>',
      ),
      (
        'no close tag',
        '<tool_call>\n{{"name": "get_weather", "arguments": {"city": "Paris"}}}',
        '<tool_call>\n{}',
      ),
      (
        'a mismatched close tag',
        '<tool_call>\n{{"name": "get_weather", "arguments": {"city": "Paris"}}}\n</function_call>',
        '<tool_call>\n{}\n</function_call>',
      ),
      (
        'an unclosed code fence',
        '```xml\n<tool_call>\n{{"name": "get_weather", "arguments": {"city": "Paris"}}}\n</tool_call>',
        '```xml\n<tool_call>\n{}\n</tool_call>',
      ),
    ]) {
      test('keeps the call and the envelope text with $name', () {
        final parsed = HermesHandler().parse(output);

        expectWeatherCall(parsed);
        expect(parsed.content, content);
      });
    }

    test('keeps other calls after a malformed double-brace envelope', () {
      final parsed = HermesHandler().parse(
        '<tool_call>\n{{"name": "get_time", "arguments": {}}} x\n</tool_call>\n'
        '$doubleBrace\n'
        '<tool_call>\n{"name": "get_date", "arguments": {}}\n</tool_call>',
      );

      expect(parsed.toolCalls.map((call) => call.function?.name), [
        'get_time',
        'get_weather',
        'get_date',
      ]);
      expect(parsed.content, '<tool_call>\n{} x\n</tool_call>');
    });
  });

  group('HermesHandler.toolCallOpening', () {
    // The opening pattern of HermesHandler.parse.
    final opening = RegExp(
      r'(?:(```(?:xml|json)?\n\s*)?(?:(<tool_call>|<function_call>|<tool>|<tools>|<response>|<json>|<xml>|<JSON>)(\s*\{)?)?(\s*\{\s*"name"))|<function=([^>]+)>|<function name="([^"]+)">',
    );

    test('finds where an opening starts or may start', () {
      for (final (text, index) in const [
        ('If a < b, then b > a.', 21),
        ('Use {x} or {"a": 1}.', 20),
        ('Let me check.\n<', 14),
        ('Let me check.\n<tool', 14),
        ('Let me check.\n<tool_call>', 14),
        ('Let me check.\n<tool_call>\n{"na', 14),
        ('Let me check.\n<tool_call>\n{"name"', 14),
        ('Let me check.\n<tool_call>\n{{"name"', 14),
        ('Sure: {"name"', 5),
        ('Sure:\n```', 6),
        ('Sure:\n```python\nx = 1', 21),
        ('Sure:\n```json\n', 6),
        ('<function=get_weather', 0),
        ('<function=get_weather>', 0),
        ('<function name="a"b', 19),
        ('Text ends with spaces  ', 21),
      ]) {
        expect(HermesHandler.toolCallOpening(text), index, reason: text);
      }
    });

    test('is never after where the parse pattern matches', () {
      const fragments = [
        'a',
        ' ',
        '\n',
        '<',
        '>',
        '{',
        '}',
        '"',
        '"name"',
        'name',
        '`',
        '```',
        'json',
        'xml',
        '\n',
        '=',
        '<tool_call>',
        '<tool',
        '<function=',
        '<function name="',
        '<JSON>',
        '<response>',
        '_call>',
      ];
      final random = Random(701);
      for (var run = 0; run < 5000; run++) {
        final text = [
          for (var i = random.nextInt(8); i >= 0; i--)
            fragments[random.nextInt(fragments.length)],
        ].join();
        final extension = [
          for (var i = random.nextInt(6); i >= 0; i--)
            fragments[random.nextInt(fragments.length)],
        ].join();
        final found = HermesHandler.toolCallOpening(text);
        for (final candidate in [text, text + extension]) {
          final match = opening.firstMatch(candidate);
          if (match != null) {
            expect(
              match.start,
              greaterThanOrEqualTo(found),
              reason: jsonEncode([text, extension]),
            );
          }
        }
      }
    });
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}

ToolDefinition _tool(String name) => ToolDefinition(
  name: name,
  description: 'Collision coverage',
  parameters: const [],
  handler: _noop,
);
