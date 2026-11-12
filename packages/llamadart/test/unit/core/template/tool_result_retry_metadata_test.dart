@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:test/test.dart';

// A custom Ministral-format template that rejects tool turns exercises fields
// Gemma's generic handler leaves empty, including the PEG parser.
const _ministralTemplate = '''
{# [SYSTEM_PROMPT][TOOL_CALLS][ARGS] #}
{%- for message in messages -%}
  {%- if message.role != 'user' and message.role != 'assistant' -%}
    {{- raise_exception('Only user and assistant roles are supported') -}}
  {%- endif -%}
  {{- '<' + message.role + '>' + message.content|string -}}
{%- endfor -%}
{%- if add_generation_prompt -%}{{- '[THINK]' -}}{%- endif -%}
''';

const _history = [
  LlamaChatMessage.fromText(
    role: LlamaChatRole.user,
    text: 'Weather in Paris?',
  ),
  LlamaChatMessage.withContent(
    role: LlamaChatRole.assistant,
    content: [
      LlamaToolCallContent(
        id: 'call00001',
        name: 'get_weather',
        arguments: {'city': 'Paris'},
        rawJson: '{"city":"Paris"}',
      ),
    ],
  ),
  LlamaChatMessage.withContent(
    role: LlamaChatRole.tool,
    content: [
      LlamaToolResultContent(
        id: 'call00001',
        name: 'get_weather',
        result: 'sunny',
      ),
    ],
  ),
];

void main() {
  final tools = [
    ToolDefinition(
      name: 'get_weather',
      description: 'Get weather',
      parameters: [ToolParam.string('city', required: true)],
      handler: (_) async => 'sunny',
    ),
  ];
  final templates = {
    'Gemma 3 fixture': (
      File('test/fixtures/templates/gemma-3-4b-it.jinja').readAsStringSync(),
      ChatFormat.generic,
      '<start_of_turn>user\n',
      '<end_of_turn>',
    ),
    'legacy Mistral fixture': (
      File(
        'test/fixtures/templates/Mistral-7B-Instruct-v0_2.jinja',
      ).readAsStringSync(),
      ChatFormat.generic,
      '[INST] ',
      '<|im_end|>',
    ),
    'custom Ministral template': (
      _ministralTemplate,
      ChatFormat.ministral,
      '<user>',
      '</s>',
    ),
  };

  for (final MapEntry(key: name, value: (source, format, userTurn, stop))
      in templates.entries) {
    group(name, () {
      test('rejects the original tool role before the engine retries', () {
        expect(TemplateCaps.detect(source).supportsToolResponses, isFalse);
        expect(
          () => ChatTemplateEngine.handlerFor(format).render(
            templateSource: source,
            messages: _history,
            metadata: const {},
            tools: tools,
          ),
          throwsException,
        );
      });

      for (final choice in ToolChoice.values) {
        test(
          'retry keeps handler metadata with tool_choice ${choice.name}',
          () {
            LlamaChatTemplateResult render(List<LlamaChatMessage> messages) =>
                ChatTemplateEngine.render(
                  templateSource: source,
                  messages: messages,
                  metadata: const {},
                  tools: tools,
                  toolChoice: choice,
                );

            final control = render(_history.take(1).toList());
            final retried = render(_history);
            final resultTurn = retried.prompt.substring(
              retried.prompt.lastIndexOf(userTurn),
            );
            expect(resultTurn, contains('"tool_response"'));
            expect(resultTurn, contains('"tool": "get_weather"'));
            expect(resultTurn, contains('"content": "sunny"'));
            expect(resultTurn, contains('"tool_call_id": "call00001"'));
            expect(
              retried.format,
              choice == ToolChoice.none && format == ChatFormat.generic
                  ? ChatFormat.contentOnly.index
                  : format.index,
            );
            expect(retried.grammar, control.grammar);
            expect(retried.grammarLazy, control.grammarLazy);
            expect(retried.additionalStops, control.additionalStops);
            expect(retried.preservedTokens, control.preservedTokens);
            expect(_triggers(retried), _triggers(control));
            expect(retried.parser, control.parser);
            expect(retried.thinkingForcedOpen, control.thinkingForcedOpen);
            expect(retried.additionalStops, contains(stop));

            final hasTools = choice != ToolChoice.none;
            expect(retried.grammar, hasTools ? isNotEmpty : isNull);
            final isMinistral = format == ChatFormat.ministral;
            expect(
              retried.grammarLazy,
              isMinistral && choice == ToolChoice.auto,
            );
            expect(
              _triggers(retried),
              isMinistral && choice == ToolChoice.auto
                  ? [(0, '[TOOL_CALLS]', null)]
                  : isEmpty,
            );
            expect(
              retried.preservedTokens,
              isMinistral
                  ? ['[THINK]', '[/THINK]', '[TOOL_CALLS]', '[ARGS]']
                  : isEmpty,
            );
            expect(retried.parser, isMinistral ? isNotEmpty : isNull);
            if (isMinistral) {
              expect(retried.thinkingForcedOpen, isTrue);
            }

            final output = isMinistral
                ? '[TOOL_CALLS]get_weather[ARGS]{"city":"Rome"}'
                : '{"tool_call":{"name":"get_weather",'
                      '"arguments":{"city":"Rome"}}}';
            final parsed = ChatTemplateEngine.parse(
              retried.format,
              output,
              parser: retried.parser,
              parseToolCalls: hasTools,
              tools: tools,
            );
            if (hasTools) {
              expect(parsed.toolCalls.single.function?.name, 'get_weather');
              expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
                'city': 'Rome',
              });
              expect(parsed.content, isEmpty);
            } else {
              expect(parsed.toolCalls, isEmpty);
              expect(parsed.content, output);
            }
          },
        );
      }
    });
  }
}

List<(int, String, int?)> _triggers(LlamaChatTemplateResult result) => [
  for (final trigger in result.grammarTriggers)
    (trigger.type, trigger.value, trigger.token),
];
