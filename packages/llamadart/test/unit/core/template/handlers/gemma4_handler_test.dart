@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Gemma4Handler', () {
    test('renders audio inside the user turn for audio-only templates', () {
      const template = '''
<|begin_of_text|>
{% for message in messages %}
<|turn>{{ message['role'] }}
{% if message['content'] is string %}{{ message['content'] }}{% else %}
{% for item in message['content'] %}
{% if item['type'] == 'audio' %}<|audio|>{% elif item['type'] == 'text' %}{{ item['text'] }}{% endif %}
{% endfor %}{% endif %}<turn|>
{% endfor %}
{% if add_generation_prompt %}<|turn>model
{% endif %}
''';
      final audioBytes = Uint8List.fromList(<int>[82, 73, 70, 70]);

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: <LlamaChatMessage>[
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: <LlamaContentPart>[
              LlamaAudioContent(bytes: audioBytes),
              const LlamaTextContent('answer the recording'),
            ],
          ),
        ],
        metadata: const <String, String>{},
      );

      final userTurn = result.prompt.indexOf('<|turn>user');
      final audioMarker = result.prompt.indexOf('<__media__>');
      final instruction = result.prompt.indexOf('answer the recording');
      final assistantTurn = result.prompt.indexOf('<|turn>model');
      expect(userTurn, greaterThanOrEqualTo(0));
      expect(audioMarker, greaterThan(userTurn));
      expect(instruction, greaterThan(audioMarker));
      expect(assistantTurn, greaterThan(instruction));
      expect(result.prompt.lastIndexOf('<__media__>'), audioMarker);
      expect(result.prompt, isNot(contains('<|audio|>')));
    });

    test('renders thinking flag into Gemma 4 template context', () {
      const template =
          '{% if enable_thinking %}<|turn>system\n<|think|><turn|>\n{% endif %}'
          '<|turn>user\n{{ messages[0]["content"] }}<turn|>';

      final enabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        addAssistant: false,
        enableThinking: true,
      );
      final disabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        addAssistant: false,
        enableThinking: false,
      );

      expect(enabled.prompt, contains('<|think|>'));
      expect(disabled.prompt, isNot(contains('<|think|>')));
    });

    test('marks prompts ending with a thought channel as forced open', () {
      const template =
          '<|turn>user\n{{ messages[0]["content"] }}<turn|>\n'
          '{% if add_generation_prompt %}<|turn>model\n'
          '{% if enable_thinking %}<|channel>thought\n{% endif %}'
          '{% endif %}';

      final enabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        enableThinking: true,
      );
      final disabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        enableThinking: false,
      );

      expect(enabled.thinkingForcedOpen, isTrue);
      expect(enabled.prompt, endsWith('<|channel>thought\n'));
      expect(disabled.thinkingForcedOpen, isFalse);
      expect(disabled.prompt, isNot(contains('<|channel>thought')));
    });

    test('parses reasoning blocks and pseudo-json tool arguments', () {
      const output =
          '<|channel>thought\nNeed weather data.<channel|>'
          '<|tool_call>call:get_weather{location:<|"|>Seoul<|"|>}<tool_call|>';

      final parsed = ChatTemplateEngine.parse(ChatFormat.gemma4.index, output);

      expect(parsed.reasoningContent, equals('Need weather data.'));
      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'location': 'Seoul'}),
      );
    });

    test('parses nested arguments with braces inside quoted values', () {
      const output =
          '<|tool_call>call:get_weather{location:<|"|>A {B}<|"|>,options:{unit:<|"|>celsius<|"|>}}<tool_call|>';

      final parsed = ChatTemplateEngine.parse(ChatFormat.gemma4.index, output);

      expect(parsed.toolCalls, hasLength(1));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({
          'location': 'A {B}',
          'options': {'unit': 'celsius'},
        }),
      );
    });

    test('parses loose function call syntax emitted by Gemma 4 LiteRT-LM', () {
      const output = 'get_weather(location="Seoul")';

      final parsed = ChatTemplateEngine.parse(ChatFormat.gemma4.index, output);

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'location': 'Seoul'}),
      );
    });

    test('streams an open thought channel as partial reasoning', () {
      const output = '<|channel>thought\nNeed weather';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.gemma4.index,
        output,
        isPartial: true,
      );

      expect(parsed.reasoningContent, equals('Need weather'));
      expect(parsed.content, isEmpty);
    });

    test('strips channel controls while preserving public channel text', () {
      const output =
          '<|channel>thought\ninternal draft<channel|>'
          '<|channel>final\nVisible answer.<channel|><channel|>';

      final parsed = ChatTemplateEngine.parse(ChatFormat.gemma4.index, output);

      expect(parsed.reasoningContent, 'internal draft');
      expect(parsed.content, 'Visible answer.');
      expect(parsed.content, isNot(contains('<|channel>')));
      expect(parsed.content, isNot(contains('<channel|>')));
    });

    test('preserves whitespace inside public channel content', () {
      const output = '<|channel>final\n \tVisible answer.  \n<channel|>';

      final parsed = ChatTemplateEngine.parse(ChatFormat.gemma4.index, output);

      expect(parsed.content, ' \tVisible answer.  \n');
      expect(parsed.reasoningContent, isNull);
    });

    test('preserves ordinary raw content whitespace exactly', () {
      const output = ' \tVisible answer.  \n';

      for (final parseToolCalls in <bool>[true, false]) {
        final parsed = ChatTemplateEngine.parse(
          ChatFormat.gemma4.index,
          output,
          parseToolCalls: parseToolCalls,
        );

        expect(parsed.content, output, reason: 'parse tools: $parseToolCalls');
        expect(parsed.toolCalls, isEmpty);
      }
    });

    test('parses output after a force-opened thought channel', () {
      final thinkingOnly = ChatTemplateEngine.parse(
        ChatFormat.gemma4.index,
        'Need a short calculation.',
        thinkingForcedOpen: true,
      );
      final closed = ChatTemplateEngine.parse(
        ChatFormat.gemma4.index,
        'Need a short calculation.<channel|>391',
        thinkingForcedOpen: true,
      );

      expect(
        thinkingOnly.reasoningContent,
        equals('Need a short calculation.'),
      );
      expect(thinkingOnly.content, isEmpty);
      expect(closed.reasoningContent, equals('Need a short calculation.'));
      expect(closed.content, equals('391'));
    });

    test('forced thinking stays private before later channel blocks', () {
      const output =
          'first draft<channel|>'
          '<|channel>thought\nsecond draft<channel|>'
          '<|channel>final\nVisible answer.<channel|>';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.gemma4.index,
        output,
        thinkingForcedOpen: true,
      );

      expect(parsed.reasoningContent, 'first draft\nsecond draft');
      expect(parsed.content, 'Visible answer.');
      expect(parsed.content, isNot(contains('draft')));
      expect(parsed.content, isNot(contains('<|channel>')));
      expect(parsed.content, isNot(contains('<channel|>')));
    });

    test('serializes tool responses for Gemma 4 templates', () {
      const template =
          '{% for message in messages %}'
          '<|turn>{{ message["role"] }}\n'
          '{% for response in message["tool_responses"] %}'
          '{{ response["name"] }}={{ response["response"]["timestamp"] }}'
          '{% endfor %}'
          '<turn|>'
          '{% endfor %}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [
              LlamaToolCallContent(
                id: 'call_0',
                name: 'get_current_time',
                arguments: {},
                rawJson: '{}',
              ),
            ],
          ),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: 'call_0',
                name: 'get_current_time',
                result: '{"timestamp":"2026-04-02T13:10:00"}',
              ),
            ],
          ),
        ],
        metadata: const {},
        addAssistant: false,
      );

      expect(result.format, equals(ChatFormat.gemma4.index));
      expect(
        result.prompt,
        '<|turn>assistant\nget_current_time=2026-04-02T13:10:00<turn|>',
      );
    });

    group('matches llama.cpp tool turns', () {
      final upstream =
          jsonDecode(
                File(
                  'test/fixtures/gemma4_tool_render_upstream.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final templates = upstream['templates'] as Map<String, dynamic>;

      ToolDefinition tool(String name, String description) => ToolDefinition(
        name: name,
        description: description,
        parameters: [ToolParam.string('city', required: true)],
        handler: (_) async => null,
      );
      final tools = [
        tool('get_weather', 'Return the weather for a city.'),
        tool('get_time', 'Return the local time for a city.'),
      ];

      const weatherCall = LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          LlamaToolCallContent(
            id: 'call_0',
            name: 'get_weather',
            arguments: {'city': 'Montréal'},
            rawJson: '{"city":"Montréal"}',
          ),
        ],
      );
      const prompt = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Call get_weather for Montréal.',
      );
      const followUp = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text:
            'What is the temperature_celsius from the tool result? '
            'Reply with only the number.',
      );
      LlamaChatMessage weatherResult(Object result) =>
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: 'call_0',
                name: 'get_weather',
                result: result,
              ),
            ],
          );
      const parallelResults = [
        LlamaToolResultContent(
          id: 'call_0',
          name: 'get_weather',
          result: {'temperature_celsius': 17},
        ),
        LlamaToolResultContent(id: 'call_1', name: 'get_time', result: '09:30'),
      ];
      List<LlamaChatMessage> parallel(List<LlamaChatMessage> results) => [
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Weather and time in Montréal?',
        ),
        const LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            LlamaToolCallContent(
              id: 'call_0',
              name: 'get_weather',
              arguments: {
                'city': 'Montréal',
                'days': 2,
                'metric': true,
                'units': {'temp': 'C'},
                'tags': ['now', 'hourly'],
              },
              rawJson:
                  '{"city":"Montréal","days":2,"metric":true,'
                  '"units":{"temp":"C"},"tags":["now","hourly"]}',
            ),
            LlamaToolCallContent(
              id: 'call_1',
              name: 'get_time',
              arguments: {'city': 'Montréal'},
              rawJson: '{"city":"Montréal"}',
            ),
          ],
        ),
        ...results,
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: 'It is 17 °C at 09:30.',
        ),
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Thanks.',
        ),
      ];

      final cases = <String, (String, List<LlamaChatMessage>)>{
        'map result': (
          'map_result',
          [
            prompt,
            weatherCall,
            weatherResult({'city': 'Montréal', 'temperature_celsius': 17}),
            followUp,
          ],
        ),
        'string result': (
          'string_result',
          [prompt, weatherCall, weatherResult('Sunny, 17 °C'), followUp],
        ),
        'parallel results in one tool message': (
          'parallel_results',
          parallel([
            const LlamaChatMessage.withContent(
              role: LlamaChatRole.tool,
              content: parallelResults,
            ),
          ]),
        ),
        'parallel results in separate tool messages': (
          'parallel_results',
          parallel([
            for (final result in parallelResults)
              LlamaChatMessage.withContent(
                role: LlamaChatRole.tool,
                content: [result],
              ),
          ]),
        ),
      };

      for (final MapEntry(key: fixture, value: expected) in templates.entries) {
        final source = File('test/fixtures/$fixture').readAsStringSync();
        final prompts = (expected as Map<String, dynamic>)['prompts'] as Map;
        for (final MapEntry(key: name, value: (key, messages))
            in cases.entries) {
          test('$fixture: $name', () {
            final result = ChatTemplateEngine.render(
              templateSource: source,
              messages: messages,
              metadata: const {'tokenizer.ggml.bos_token': '<bos>'},
              tools: tools,
              enableThinking: false,
            );

            expect(result.format, ChatFormat.gemma4.index);
            // llama.cpp drops the leading BOS text; its tokenizer adds BOS.
            expect(result.prompt, '<bos>${prompts[key]}');
          });
        }
      }
    });

    test('rejects tool-call arguments that are not a JSON object', () {
      expect(
        () => ChatTemplateEngine.render(
          templateSource: File(
            'test/fixtures/templates/gemma-4-E2B-it.jinja',
          ).readAsStringSync(),
          messages: const [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.assistant,
              content: [
                LlamaToolCallContent(
                  name: 'get_weather',
                  arguments: {},
                  rawJson: 'not json',
                ),
              ],
            ),
          ],
          metadata: const {},
        ),
        throwsA(isA<LlamaInferenceException>()),
      );
    });

    group('tool-call grammar', () {
      const toolTemplate =
          '<|turn>user\n{{ messages[0]["content"] }}<turn|>\n'
          '{% if add_generation_prompt %}<|turn>model\n{% endif %}';

      final weatherTool = ToolDefinition(
        name: 'get_weather',
        description: 'Weather',
        parameters: [ToolParam.string('location', required: true)],
        handler: (_) async => null,
      );

      LlamaChatTemplateResult renderWithChoice(
        ToolChoice toolChoice, {
        bool enableThinking = true,
      }) {
        return ChatTemplateEngine.render(
          templateSource: toolTemplate,
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
          ],
          metadata: const {},
          tools: [weatherTool],
          toolChoice: toolChoice,
          enableThinking: enableThinking,
        );
      }

      Map<String, String> rulesOf(String grammar) {
        final rules = <String, String>{};
        for (final line in grammar.split('\n')) {
          final separator = line.indexOf(' ::= ');
          if (separator == -1) {
            continue;
          }
          rules[line.substring(0, separator).trim()] = line
              .substring(separator + ' ::= '.length)
              .trim();
        }
        return rules;
      }

      test('required tool choice renders an eager envelope grammar', () {
        final result = renderWithChoice(ToolChoice.required);

        expect(result.format, equals(ChatFormat.gemma4.index));
        expect(result.grammar, isNotNull);
        expect(result.grammarLazy, isFalse);
        expect(result.grammarTriggers, isEmpty);
        expect(
          renderWithChoice(ToolChoice.required, enableThinking: false).grammar,
          result.grammar,
        );

        final rules = rulesOf(result.grammar!);
        expect(rules, contains('root'));

        // Every root alternative must start by committing to the tool-call
        // envelope, so no leading prose can be generated before it.
        for (final alternative in rules['root']!.split('|')) {
          final head = alternative.trim().split(RegExp(r'\s+')).first;
          final expansion = head.startsWith('"') ? head : rules[head];
          expect(
            expansion,
            isNotNull,
            reason: 'root alternative "$alternative" has no rule for $head',
          );
          expect(
            expansion!.startsWith('"<|tool_call>call:'),
            isTrue,
            reason: 'root alternative "$alternative" admits leading prose',
          );
        }
      });

      test('required grammar constrains tool names and argument schema', () {
        final grammar = renderWithChoice(ToolChoice.required).grammar!;

        expect(grammar, contains('"<|tool_call>call:get_weather"'));
        expect(grammar, contains(r'"<tool_call|>"'));
        expect(grammar, contains(r'\"location\"'));
        expect(grammar, isNot(contains('call:other_tool')));
      });

      test('parser accepts the standard JSON arguments the grammar emits', () {
        const output =
            '<|tool_call>call:get_weather{"location": "Seoul"}<tool_call|>';

        final parsed = ChatTemplateEngine.parse(
          ChatFormat.gemma4.index,
          output,
        );

        expect(parsed.content, isEmpty);
        expect(parsed.toolCalls, hasLength(1));
        expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
        expect(
          jsonDecode(parsed.toolCalls.first.function!.arguments!),
          equals({'location': 'Seoul'}),
        );
      });

      test('parser preserves exact escaped tool and schema names', () {
        final tool = ToolDefinition(
          name: r'weather&"alerts\route|primary',
          description: 'Escaped identity coverage',
          parameters: [ToolParam.string(r'city&"zone\path', required: true)],
          handler: (_) async => null,
        );
        final arguments = <String, dynamic>{
          r'city&"zone\path': 'Montréal {north}',
        };
        final output =
            '<|tool_call>call:${tool.name}'
            '${jsonEncode(arguments)}<tool_call|>';

        final parsed = ChatTemplateEngine.parse(
          ChatFormat.gemma4.index,
          output,
          tools: [tool],
        );

        expect(parsed.content, isEmpty);
        expect(parsed.toolCalls, hasLength(1));
        expect(parsed.toolCalls.single.function?.name, tool.name);
        expect(
          jsonDecode(parsed.toolCalls.single.function!.arguments!),
          arguments,
        );
      });

      test('parser preserves an undeclared tool envelope without markup', () {
        const output =
            '<|tool_call>call:unknown tool{"city":"Seoul"}<tool_call|>';

        final parsed = ChatTemplateEngine.parse(
          ChatFormat.gemma4.index,
          output,
          tools: [weatherTool],
        );

        expect(parsed.content, isEmpty);
        expect(parsed.toolCalls, hasLength(1));
        expect(parsed.toolCalls.single.function?.name, 'unknown tool');
        expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
          'city': 'Seoul',
        });
      });

      test('malformed tool envelopes fail closed without visible markup', () {
        const output =
            'Visible answer.'
            '<|tool_call>call:get_weather{"location":<tool_call|>';

        final parsed = ChatTemplateEngine.parse(
          ChatFormat.gemma4.index,
          output,
          tools: [weatherTool],
        );

        expect(parsed.content, 'Visible answer.');
        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, isNot(contains('<|tool_call>')));
        expect(parsed.content, isNot(contains('<tool_call|>')));
      });

      test('pure tool-call protocol whitespace stays non-visible', () {
        const output =
            ' \n<|tool_call>call:get_weather{"location":"Seoul"}'
            '<tool_call|>\t ';

        for (final parseToolCalls in <bool>[true, false]) {
          final parsed = ChatTemplateEngine.parse(
            ChatFormat.gemma4.index,
            output,
            parseToolCalls: parseToolCalls,
            tools: [weatherTool],
          );

          expect(parsed.content, isEmpty);
          expect(parsed.toolCalls, parseToolCalls ? hasLength(1) : isEmpty);
        }
      });

      test('partial parser withholds every split control marker prefix', () {
        const channelMarker = '<|channel>';
        for (var length = 1; length < channelMarker.length; length++) {
          final parsed = ChatTemplateEngine.parse(
            ChatFormat.gemma4.index,
            'visible${channelMarker.substring(0, length)}',
            isPartial: true,
          );
          expect(
            parsed.content,
            'visible',
            reason: 'channel prefix length $length',
          );
          expect(
            parsed.reasoningContent,
            isNull,
            reason: 'channel prefix length $length',
          );
        }

        const marker = '<|tool_call>';
        for (var length = 1; length < marker.length; length++) {
          final parsed = ChatTemplateEngine.parse(
            ChatFormat.gemma4.index,
            'visible${marker.substring(0, length)}',
            isPartial: true,
          );
          expect(parsed.content, 'visible', reason: 'prefix length $length');
          expect(parsed.toolCalls, isEmpty, reason: 'prefix length $length');

          final afterThinking = ChatTemplateEngine.parse(
            ChatFormat.gemma4.index,
            'reasoning<channel|>${marker.substring(0, length)}',
            isPartial: true,
            thinkingForcedOpen: true,
            tools: [weatherTool],
          );
          expect(
            afterThinking.reasoningContent,
            'reasoning',
            reason: 'thinking prefix length $length',
          );
          expect(
            afterThinking.content,
            isEmpty,
            reason: 'thinking prefix length $length',
          );
        }

        const completeEnvelope =
            '<|tool_call>call:get_weather{"location":"Seoul"}<tool_call|>';
        for (var length = 1; length <= completeEnvelope.length; length++) {
          final parsed = ChatTemplateEngine.parse(
            ChatFormat.gemma4.index,
            'reasoning<channel|>${completeEnvelope.substring(0, length)}',
            isPartial: true,
            thinkingForcedOpen: true,
            tools: [weatherTool],
          );
          expect(
            parsed.reasoningContent,
            'reasoning',
            reason: 'envelope prefix length $length',
          );
          expect(
            parsed.content,
            isEmpty,
            reason: 'envelope prefix length $length',
          );
        }

        final finalParsed = ChatTemplateEngine.parse(
          ChatFormat.gemma4.index,
          'visible<|tool_',
        );
        expect(finalParsed.content, 'visible');

        final contentOnly = ChatTemplateEngine.parse(
          ChatFormat.gemma4.index,
          'visible$completeEnvelope',
          parseToolCalls: false,
        );
        expect(contentOnly.content, 'visible');
        expect(contentOnly.toolCalls, isEmpty);
      });

      test('required grammar rejects duplicate tool identities', () {
        final duplicate = ToolDefinition(
          name: weatherTool.name,
          description: 'Duplicate',
          parameters: const [],
          handler: (_) async => null,
        );

        expect(
          () => ChatTemplateEngine.render(
            templateSource: toolTemplate,
            messages: const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            metadata: const {},
            tools: [weatherTool, duplicate],
            toolChoice: ToolChoice.required,
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      });

      test('auto and none tool choice stay unconstrained', () {
        expect(renderWithChoice(ToolChoice.auto).grammar, isNull);
        expect(renderWithChoice(ToolChoice.none).grammar, isNull);
      });
    });
  });
}
