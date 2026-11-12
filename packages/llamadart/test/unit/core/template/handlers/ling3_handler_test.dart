@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/ling3_handler.dart';
import 'package:test/test.dart';

import '../../../../support/ling3_tools.dart';

String _call(String name, [Map<String, String> arguments = const {}]) =>
    '<tool_call>$name\n'
    '${arguments.entries.map((a) => '<arg_key>${a.key}</arg_key>\n<arg_value>${a.value}</arg_value>\n').join()}'
    '</tool_call>';

final String _weather = _call('get_weather', {'location': 'Paris'});

void main() {
  final handler = Ling3Handler();
  final templateSource = File(
    'test/fixtures/llama_cpp_templates/inclusionai-ling-3.0-flash.jinja',
  ).readAsStringSync();

  Map<String, Object?> parse(
    String output, {
    bool thinkingForcedOpen = true,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool singleToolCall = false,
    bool schemaTools = false,
  }) {
    final result = handler.parseWithTools(
      output,
      tools: schemaTools ? ling3SchemaTools : ling3Tools,
      isPartial: isPartial,
      parseToolCalls: parseToolCalls,
      thinkingForcedOpen: thinkingForcedOpen,
      singleToolCall: singleToolCall,
    );
    return {
      'content': result.content,
      'reasoning': result.reasoningContent,
      'calls': [
        for (final call in result.toolCalls)
          '${call.function!.name} ${jsonDecode(call.function!.arguments!)}',
      ],
    };
  }

  group('detection and rendering', () {
    test('a <role> template with argument tags is Ling 3', () {
      expect(detectChatFormat(templateSource), ChatFormat.ling3);
    });

    test('a <role> template without argument tags is not Ling 3', () {
      expect(
        detectChatFormat(
          '<role>ASSISTANT</role>{{ messages[0]["content"] }}<|role_end|>',
        ),
        isNot(ChatFormat.ling3),
      );
    });

    for (final enableThinking in [true, false]) {
      test('renders thinking $enableThinking', () {
        final rendered = ChatTemplateEngine.render(
          templateSource: templateSource,
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
          ],
          metadata: const {},
          tools: ling3Tools,
          enableThinking: enableThinking,
        );
        expect(
          rendered.prompt,
          endsWith(
            enableThinking
                ? '<role>ASSISTANT</role>\n<think>'
                : '<role>ASSISTANT</role>\n<think></think>',
          ),
        );
        expect(rendered.thinkingForcedOpen, enableThinking);
        expect(rendered.additionalStops, ['<|role_end|>']);
        expect(rendered.preservedTokens, contains('<arg_value>'));
        expect(rendered.grammarLazy, isTrue);
        expect(rendered.grammarTriggers.single.value, '<tool_call>');
      });
    }

    test('a request without tools has no grammar or preserved tokens', () {
      final rendered = ChatTemplateEngine.render(
        templateSource: templateSource,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
        ],
        metadata: const {},
      );
      expect(rendered.format, ChatFormat.ling3.index);
      expect(rendered.grammar, isNull);
      expect(rendered.preservedTokens, isEmpty);
    });

    test('a required call is not lazy and takes the thought and text', () {
      final rendered = ChatTemplateEngine.render(
        templateSource: templateSource,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
        ],
        metadata: const {},
        tools: ling3Tools,
        toolChoice: ToolChoice.required,
      );
      expect(rendered.grammarLazy, isFalse);
      expect(
        rendered.grammar,
        contains('root ::= ling3-thought "</think>"? ling3-content? '),
      );
    });

    test('the handler renders the grammar a request asks for', () {
      LlamaChatTemplateResult render(ToolChoice choice, bool parallel) =>
          handler.render(
            templateSource: templateSource,
            messages: const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
            ],
            metadata: {
              'llamadart.internal.tool_choice': choice.name,
              'llamadart.internal.parallel_tool_calls': '$parallel',
            },
            tools: ling3Tools,
          );
      expect(render(ToolChoice.auto, false).grammarLazy, isTrue);
      expect(render(ToolChoice.required, false).grammarLazy, isFalse);
      expect(
        render(ToolChoice.auto, false).grammar,
        isNot(contains('(space ')),
      );
      expect(render(ToolChoice.auto, true).grammar, contains('(space ('));
    });

    test('canonical JSON Schema tools are not qualified', () {
      expect(
        () => ChatTemplateEngine.render(
          templateSource: templateSource,
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
          ],
          metadata: const {},
          tools: ling3SchemaTools,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('parse', () {
    test('a call ends the thought and takes typed arguments', () {
      expect(parse('Plan ${_call('get_time', {'tz': 'UTC', 'days': '3'})}'), {
        'content': '',
        'reasoning': 'Plan',
        'calls': ['get_time {tz: UTC, days: 3}'],
      });
    });

    test('after a closed thought everything is content', () {
      expect(
        parse('<think>Plan</think>Hi $_weather', thinkingForcedOpen: false),
        {
          'content': '<think>Plan</think>Hi',
          'reasoning': null,
          'calls': ['get_weather {location: Paris}'],
        },
      );
    });

    test('a Hermes JSON call stays content', () {
      const hermes =
          '<tool_call>\n{"name": "get_weather", "arguments": {}}\n</tool_call>';
      expect(parse('Plan</think>$hermes'), {
        'content': hermes,
        'reasoning': 'Plan',
        'calls': <String>[],
      });
    });

    test('the end-of-turn token is consumed after a call', () {
      expect(parse('$_weather<|role_end|>'), {
        'content': '',
        'reasoning': null,
        'calls': ['get_weather {location: Paris}'],
      });
    });

    test('without tools the thought still ends at a call opening', () {
      expect(parse('Plan $_weather<|role_end|>', parseToolCalls: false), {
        'content': _weather,
        'reasoning': 'Plan',
        'calls': <String>[],
      });
    });

    test('a repeated optional argument keeps its last value', () {
      expect(
        parse(
          '<tool_call>get_time\n'
          '<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n'
          '<arg_key>days</arg_key>\n<arg_value>1</arg_value>\n'
          '<arg_key>days</arg_key>\n<arg_value>2</arg_value>\n'
          '</tool_call>',
        )['calls'],
        ['get_time {tz: UTC, days: 2}'],
      );
    });

    test('a string value keeps its whitespace and markup', () {
      expect(
        parse(_call('get_weather', {'location': '  a<arg_key>b\n'}))['calls'],
        ['get_weather {location:   a<arg_key>b\n}'],
      );
    });

    test('a value of a mixed type is JSON, or else text', () {
      String level(String value) => _call('mixed', {'level': value});
      expect(parse(level('5'), schemaTools: true)['calls'], [
        'mixed {level: 5}',
      ]);
      expect(parse(level('"5"'), schemaTools: true)['calls'], [
        'mixed {level: 5}',
      ]);
      expect(parse(level('5 apples'), schemaTools: true)['calls'], [
        'mixed {level: 5 apples}',
      ]);
      expect(parse(level('"a</arg_value>b"'), schemaTools: true)['calls'], [
        'mixed {level: a</arg_value>b}',
      ]);
    });

    test('only the first call counts without parallel tool calls', () {
      final second = _call('get_weather', {'location': 'Rome'});
      expect(parse('$_weather\n$second', singleToolCall: true), {
        'content': second,
        'reasoning': null,
        'calls': ['get_weather {location: Paris}'],
      });
      expect(parse('$_weather\n$second')['calls'], [
        'get_weather {location: Paris}',
        'get_weather {location: Rome}',
      ]);
    });

    test('a second end-of-turn token is dropped and the text joined', () {
      expect(
        parse('$_weather<|role_end|>a<|role_end|>b', thinkingForcedOpen: false),
        {
          'content': 'ab',
          'reasoning': null,
          'calls': ['get_weather {location: Paris}'],
        },
      );
    });

    test('text after a call is content up to the end-of-turn token', () {
      expect(
        parse('Sure.$_weather\nDone.<|role_end|>', thinkingForcedOpen: false),
        {
          'content': 'Sure.Done.',
          'reasoning': null,
          'calls': ['get_weather {location: Paris}'],
        },
      );
    });
  });

  group('partial parse', () {
    test('an unfinished first call is held back', () {
      for (var cut = _weather.length - 1; cut > 0; cut--) {
        final partial = parse(
          'Hello</think>${_weather.substring(0, cut)}',
          isPartial: true,
        );
        expect(partial['content'], '', reason: '$cut');
        expect(partial['calls'], isEmpty, reason: '$cut');
      }
    });

    test('a thought holds back the start of an ending tag', () {
      expect(parse('Plan </th', isPartial: true)['reasoning'], 'Plan');
      expect(parse('Plan <tool_ca', isPartial: true)['reasoning'], 'Plan');
      expect(parse('Plan <tool_ca')['reasoning'], 'Plan <tool_ca');
    });

    test('content holds back the start of a call opening or turn end', () {
      expect(parse('Hi <tool', isPartial: true, thinkingForcedOpen: false), {
        'content': 'Hi',
        'reasoning': null,
        'calls': <String>[],
      });
      expect(parse('$_weather<|role', isPartial: true)['content'], '');
    });

    test('a second call that may start is held back, other text is not', () {
      final held = parse('$_weather\n<tool_c', isPartial: true);
      expect(held['content'], '');
      expect(held['calls'], ['get_weather {location: Paris}']);
      expect(parse('$_weather\nDone', isPartial: true)['content'], 'Done');
    });

    test('an unfinished first call is dropped from a final parse', () {
      expect(parse(_weather.substring(0, _weather.length - 4)), {
        'content': '',
        'reasoning': null,
        'calls': <String>[],
      });
    });
  });
}
