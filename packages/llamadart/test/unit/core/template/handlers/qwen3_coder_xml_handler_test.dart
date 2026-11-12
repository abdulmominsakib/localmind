import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/qwen3_coder_xml_handler.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:test/test.dart';

import '../../../../support/gbnf_recognizer.dart';

void main() {
  _requiredArgumentOrderTests();
  _enumGrammarTests();
  _stringOrIntegerValueTests();
  _valueEndCollisionTests();

  test('Qwen3CoderXmlHandler parses qwen XML tool calls', () {
    final handler = Qwen3CoderXmlHandler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
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
    expect(rendered.grammarTriggers, isNotEmpty);
    expect(rendered.additionalStops, contains('<|im_end|>'));

    final parsed = handler.parse(
      '<tool_call>\n'
      '<function=get_weather>\n'
      '<parameter=city>\n"Seoul"\n</parameter>\n'
      '</function>\n'
      '</tool_call>',
    );
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );

    final noTool = handler.parse('plain', parseToolCalls: false);
    expect(noTool.content, equals('plain'));
  });

  // llama.cpp (`cd959bae9`) holds back the start of a `<tool_call>` a
  // partial reply may still complete, and keeps it once the reply ends.
  test('a partial reply holds back the start of a tool-call scope', () {
    final handler = Qwen3CoderXmlHandler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];
    for (final (output, partial) in [
      ('See <tool_', 'See'),
      ('Use 3 <', 'Use 3'),
      ('See <tool_call', 'See'),
      ('See <tool', 'See'),
      ('a < b', 'a < b'),
    ]) {
      expect(
        handler.parseWithTools(output, tools: tools, isPartial: true).content,
        partial,
        reason: output,
      );
      expect(handler.parseWithTools(output, tools: tools).content, output);
    }
  });

  test('Qwen3CoderXmlHandler drops a malformed XML tool scope', () {
    final handler = Qwen3CoderXmlHandler();
    const input =
        'Checking.\n<tool_call>\n<function=get_weather>\n<parameter=city>\n"Seoul"\n</tool_call>';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, 'Checking.');
  });

  // llama.cpp (`cd959bae9`) parses Nemotron-3-Nano with its Qwen3-Coder
  // parser.
  test('Qwen3CoderXmlHandler parses Nemotron v3 as Qwen3-Coder XML', () {
    final handler = Qwen3CoderXmlHandler();
    final tools = [
      ToolDefinition(
        name: 'python',
        description: 'Run Python',
        parameters: [ToolParam.string('code', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource:
          '{% set truncate_history_thinking = true %}'
          '<tool_call><function><function=python><parameters><parameter=code>'
          '<think>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
      enableThinking: true,
    );

    expect(rendered.format, equals(ChatFormat.qwen3CoderXml.index));
    expect(rendered.thinkingForcedOpen, isTrue);
    expect(rendered.parser, isNull);
    expect(rendered.grammarTriggers.map((trigger) => trigger.value), [
      '<tool_call>',
    ]);
    expect(rendered.preservedTokens, contains('<think>'));
    expect(rendered.preservedTokens, contains('</think>'));

    ChatParseResult parse(String output) =>
        ChatTemplateEngine.parseRendered(rendered, output, tools: tools);
    const code =
        'def hello():\n'
        '    print("Hello, world!")\n'
        '\n'
        'hello()';
    final parsed = parse(
      'I am thinking\n'
      '</think>\n'
      '<tool_call>\n'
      '<function=python>\n'
      '<parameter=code>\n'
      '$code\n'
      '</parameter>\n'
      '</function>\n'
      '</tool_call>',
    );
    expect(parsed.reasoningContent, equals('I am thinking'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('python'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      equals({'code': code}),
    );

    // llama.cpp returns a call without `</parameter>` with unterminated JSON
    // arguments.
    expect(
      parse(
        'plan\n</think>\n<tool_call>\n<function=python>\n<parameter=code>\n'
        'print("hi")\n</function>\n</tool_call>',
      ).toolCalls,
      isEmpty,
    );
  });

  test('Qwen3/Nemotron preserved tokens are retained without tools', () {
    final handler = Qwen3CoderXmlHandler();

    final qwen = handler.render(
      templateSource:
          '<tool_call><function><function=x><parameters><parameter=x>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: null,
    );
    expect(qwen.preservedTokens, contains('<tool_call>'));
    expect(qwen.preservedTokens, contains('<function='));

    final nemotron = handler.render(
      templateSource:
          '{% set truncate_history_thinking = true %}'
          '<tool_call><function><function=x><parameters><parameter=x><think>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: null,
    );
    expect(nemotron.preservedTokens, contains('<think>'));
    expect(nemotron.preservedTokens, contains('</think>'));
    expect(nemotron.format, equals(ChatFormat.qwen3CoderXml.index));
    expect(nemotron.parser, isNull);
  });

  test('Qwen3.6 renders its thinking control without Nemotron parsing', () {
    const template = '''
{%- if add_generation_prompt %}
{{- '<|im_start|>assistant\\n' }}
{%- if enable_thinking is defined and enable_thinking is false %}
{{- '<think>\\n\\n</think>\\n\\n' }}
{%- else %}
{{- '<think>\\n' }}
{%- endif %}
{%- endif %}
''';
    final handler = Qwen3CoderXmlHandler();
    const messages = <LlamaChatMessage>[
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
    ];

    final thinking = handler.render(
      templateSource: template,
      messages: messages,
      metadata: const {},
      enableThinking: true,
    );

    expect(thinking.format, equals(ChatFormat.qwen3CoderXml.index));
    expect(thinking.parser, isNull);
    expect(thinking.thinkingForcedOpen, isTrue);
    expect(thinking.preservedTokens, contains('</think>'));

    final parsed = ChatTemplateEngine.parse(
      thinking.format,
      'unfinished reasoning',
      thinkingForcedOpen: thinking.thinkingForcedOpen,
    );
    expect(parsed.reasoningContent, equals('unfinished reasoning'));
    expect(parsed.content, isEmpty);

    final nonThinking = handler.render(
      templateSource: template,
      messages: messages,
      metadata: const {},
      enableThinking: false,
    );
    expect(nonThinking.format, equals(ChatFormat.qwen3CoderXml.index));
    expect(nonThinking.parser, isNull);
    expect(nonThinking.thinkingForcedOpen, isFalse);
    expect(nonThinking.prompt, contains('<think>\n\n</think>'));
  });

  test('grammar root repeats tool-call scopes only with parallel tool '
      'calls', () {
    final handler = Qwen3CoderXmlHandler();
    final tools = [
      ToolDefinition(
        name: 'search',
        description: 'Search docs',
        parameters: [ToolParam.string('query', required: true)],
        handler: _noop,
      ),
    ];
    const qwenTemplate = '{{ messages[0]["content"] }}';
    const nemotronTemplate =
        '{% set truncate_history_thinking = true %}'
        '<tool_call><function><parameters><think>';
    String rootOf(String grammar) {
      return grammar
          .split('\n')
          .singleWhere((line) => line.startsWith('root ::='));
    }

    String rootFor(String templateSource, Map<String, String> metadata) {
      final rendered = handler.render(
        templateSource: templateSource,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        metadata: metadata,
        tools: tools,
      );
      return rootOf(rendered.grammar!);
    }

    const single = 'root ::= tool-call';
    const repeated = 'root ::= tool-call tool-call*';
    const parallelOff = {internalParallelToolCallsMetadataKey: 'false'};
    const parallelOn = {internalParallelToolCallsMetadataKey: 'true'};
    expect(rootFor(nemotronTemplate, const {}), equals(single));
    expect(rootFor(nemotronTemplate, parallelOff), equals(single));
    expect(rootFor(nemotronTemplate, parallelOn), equals(repeated));
    expect(rootFor(qwenTemplate, const {}), equals(single));
    expect(rootFor(qwenTemplate, parallelOff), equals(single));
    expect(rootFor(qwenTemplate, parallelOn), equals(repeated));
    expect(rootOf(handler.buildGrammar(tools)!), equals(repeated));
  });
}

// llama.cpp (`cd959bae9`) reads a value that may be a string as JSON only
// when it is a JSON value of another type the schema allows.
void _stringOrIntegerValueTests() {
  test('a string-or-integer value is JSON only as an integer', () {
    final tools = [
      ToolDefinition.fromJsonSchema(
        name: 'f',
        description: 'f',
        schema: {
          'type': 'object',
          'properties': {
            'v': {
              'type': ['string', 'integer'],
            },
          },
          'required': ['v'],
        },
      ),
    ];
    for (final (raw, value) in [
      ('"Paris"', '"Paris"'),
      ('3', 3),
      ('Paris', 'Paris'),
      ('[1]', '[1]'),
      ('true', 'true'),
      ('null', 'null'),
      (' 3', ' 3'),
    ]) {
      final parsed = Qwen3CoderXmlHandler().parseWithTools(
        '<tool_call>\n<function=f>\n<parameter=v>\n$raw\n</parameter>\n'
        '</function>\n</tool_call>',
        tools: tools,
      );
      expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
        'v': value,
      }, reason: raw);
    }
  });
}

// llama.cpp (`cd959bae9`) takes up to six required arguments in any order,
// and more only in declaration order, in its parser and its grammar. A
// repeated required argument drops the call.
void _requiredArgumentOrderTests() {
  ToolDefinition requiredStrings(String name, int count) => ToolDefinition(
    name: name,
    description: name,
    parameters: [
      for (var i = 0; i < count; i++) ToolParam.string('p$i', required: true),
    ],
    handler: _noop,
  );
  String call(String name, List<int> order) =>
      '<tool_call>\n<function=$name>\n'
      '${order.map((i) => '<parameter=p$i>\nv$i\n</parameter>\n').join()}'
      '</function>\n</tool_call>';
  final tools = [requiredStrings('two', 2), requiredStrings('seven', 7)];

  test('required arguments come in any order up to six of them', () {
    final rendered = Qwen3CoderXmlHandler().render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
    );
    final grammar = GbnfRecognizer(rendered.grammar!);
    for (final (output, valid) in [
      (call('two', [1, 0]), true),
      (call('two', [0, 1]), true),
      (call('two', [0, 0, 1]), false),
      (call('two', [0, 1, 0]), false),
      (call('two', [1, 0, 0]), false),
      (call('seven', [0, 1, 2, 3, 4, 5, 6]), true),
      (call('seven', [1, 0, 2, 3, 4, 5, 6]), false),
      (call('seven', [6, 5, 4, 3, 2, 1, 0]), false),
    ]) {
      final parsed = ChatTemplateEngine.parseRendered(
        rendered,
        output,
        tools: tools,
      );
      expect(parsed.toolCalls, hasLength(valid ? 1 : 0), reason: output);
      expect(grammar.accepts(output), valid, reason: output);
    }
  });
}

// llama.cpp (`cd959bae9`) takes a string-typed value, enum or not, as any text
// in its grammar.
void _enumGrammarTests() {
  test('grammar takes a string enum value as any text', () {
    final tools = [
      ToolDefinition(
        name: 'set_unit',
        description: 'set_unit',
        parameters: [
          ToolParam.enumType(
            'unit',
            values: const ['celsius', 'fahrenheit'],
            required: true,
          ),
        ],
        handler: _noop,
      ),
    ];
    final rendered = Qwen3CoderXmlHandler().render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
    );
    final grammar = GbnfRecognizer(rendered.grammar!);
    String call(String value) =>
        '<tool_call>\n<function=set_unit>\n'
        '<parameter=unit>\n$value\n</parameter>\n</function>\n</tool_call>';
    expect(grammar.accepts(call('celsius')), isTrue);
    expect(grammar.accepts(call('kelvin')), isTrue);
  });
}

void _valueEndCollisionTests() {
  test(
    'grammar accepts a call whose nested property is named at-value-end',
    () {
      final tools = [
        ToolDefinition.fromJsonSchema(
          name: 'configure',
          description: 'configure',
          schema: {
            'type': 'object',
            'properties': {
              'plain': {
                'type': 'object',
                'properties': {
                  'at-value-end': {
                    'type': 'object',
                    'properties': {
                      'n': {'type': 'integer'},
                    },
                    'required': ['n'],
                  },
                },
                'required': ['at-value-end'],
              },
              'opts': {
                'anyOf': [
                  {'type': 'integer'},
                  {
                    'type': 'object',
                    'properties': {
                      'at-value-end': {
                        'type': 'object',
                        'properties': {
                          'n': {'type': 'integer'},
                        },
                        'required': ['n'],
                      },
                    },
                    'required': ['at-value-end'],
                  },
                ],
              },
            },
            'required': ['plain', 'opts'],
          },
          handler: _noop,
        ),
      ];
      final rendered = Qwen3CoderXmlHandler().render(
        templateSource: '{{ messages[0]["content"] }}',
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        metadata: const {},
        tools: tools,
      );
      const output =
          '<tool_call>\n<function=configure>\n'
          '<parameter=plain>\n{"at-value-end": {"n": 1}}\n</parameter>\n'
          '<parameter=opts>\n{"at-value-end": {"n": 1}}\n</parameter>\n'
          '</function>\n</tool_call>';
      expect(GbnfRecognizer(rendered.grammar!).accepts(output), isTrue);
    },
  );
}

Future<Object?> _noop(_) async {
  return 'ok';
}
