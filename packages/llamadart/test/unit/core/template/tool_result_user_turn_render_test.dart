@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

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
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:test/test.dart';

/// Templates whose role-alternation check rejects a `tool` message.
///
/// `tool/litert_lm_templates/gemma{,3n}.jinja` are byte-identical to the
/// Gemma 3 fixtures here.
const _rejectingTemplates = <String>[
  'test/fixtures/templates/gemma-3-4b-it.jinja',
  'test/fixtures/templates/gemma-3n-E4B-it.jinja',
  'test/fixtures/templates/Mistral-7B-Instruct-v0_2.jinja',
  'test/fixtures/llama_cpp_templates/google-gemma-2-2b-it.jinja',
];

/// Templates that render the `tool` role themselves.
const _toolRoleTemplates = <String>[
  'test/fixtures/templates/Qwen3-4B.jinja',
  'test/fixtures/templates/Qwen3_5-0_8B.jinja',
  'test/fixtures/templates/Llama-3_2-3B-Instruct.jinja',
  'test/fixtures/templates/Ministral-3-3B-Reasoning.jinja',
  'test/fixtures/templates/Phi-4-mini-instruct-reasoning.jinja',
];

final _tool = ToolDefinition(
  name: 'get_weather',
  description: 'Get the current weather for a city',
  parameters: [ToolParam.string('city', required: true)],
  handler: (_) async => null,
);

const _user = LlamaChatMessage.fromText(
  role: LlamaChatRole.user,
  text: 'What is the weather in Paris and Rome?',
);

LlamaToolCallContent _call(String id, String city) => LlamaToolCallContent(
  id: id,
  name: 'get_weather',
  arguments: {'city': city},
  rawJson: jsonEncode({'city': city}),
);

LlamaChatMessage _calls(List<LlamaToolCallContent> calls) =>
    LlamaChatMessage.withContent(role: LlamaChatRole.assistant, content: calls);

LlamaToolResultContent _result(String id, Object? value) =>
    LlamaToolResultContent(id: id, name: 'get_weather', result: value);

LlamaChatMessage _results(List<LlamaToolResultContent> results) =>
    LlamaChatMessage.withContent(role: LlamaChatRole.tool, content: results);

final _oneResult = <LlamaChatMessage>[
  _user,
  _calls([_call('call00001', 'Paris')]),
  _results([
    _result('call00001', {'city': 'Paris', 'temperature_c': 21}),
  ]),
];

const _firstResponse = '''
{
  "tool_response": {
    "tool": "get_weather",
    "content": "{\\"temperature_c\\":21}",
    "tool_call_id": "call00001"
  }
}''';

const _secondResponse = '''
{
  "tool_response": {
    "tool": "get_weather",
    "content": "{\\"temperature_c\\":25}",
    "tool_call_id": "call00002"
  }
}''';

LlamaChatTemplateResult _render(
  String path,
  List<LlamaChatMessage> messages, {
  bool tools = true,
  ToolChoice toolChoice = ToolChoice.auto,
  bool enableThinking = true,
}) => ChatTemplateEngine.render(
  templateSource: File(path).readAsStringSync(),
  messages: messages,
  metadata: const {
    'tokenizer.ggml.bos_token': '',
    'tokenizer.ggml.eos_token': '</s>',
  },
  tools: tools ? [_tool] : null,
  toolChoice: toolChoice,
  enableThinking: enableThinking,
);

String _name(String path) => path.split('/').last;

void main() {
  group('matches llama.cpp b6000 for one tool result', () {
    final reference =
        jsonDecode(
              File(
                'test/fixtures/tool_result_user_turn_render_upstream.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final render
        in (reference['renders'] as List).cast<Map<String, dynamic>>()) {
      final path = render['template'] as String;
      final tools = render['tools'] as bool;
      final upstream = render['prompt'] as String;
      test('${_name(path)} ${tools ? 'with' : 'without'} tools', () {
        final prompt = _render(path, _oneResult, tools: tools).prompt;
        if (tools) {
          String fromQuestion(String text) =>
              text.substring(text.indexOf(_user.content));
          expect(fromQuestion(prompt), fromQuestion(upstream));
        } else {
          expect(prompt, upstream);
        }
      });
    }
  });

  group('follow-up matches pinned upstream merged rendering', () {
    final reference =
        jsonDecode(
              File(
                'test/fixtures/tool_result_follow_up_render_upstream.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final render
        in (reference['renders'] as List).cast<Map<String, dynamic>>()) {
      final path = render['template'] as String;
      test(_name(path), () {
        final prompt = _render(path, [
          ..._oneResult,
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'And Rome? Keep the units in Celsius.',
          ),
        ], tools: false).prompt;
        expect(prompt, render['prompt']);
      });
    }
  });

  for (final path in _rejectingTemplates) {
    group(_name(path), () {
      for (final choice in ToolChoice.values) {
        test('sends the result as a user turn with tool_choice '
            '${choice.name}', () {
          final results = [
            for (final thinking in [true, false])
              _render(
                path,
                _oneResult,
                toolChoice: choice,
                enableThinking: thinking,
              ),
          ];
          final result = results.first;
          expect(results.last.prompt, result.prompt);
          expect(result.prompt, contains('"tool_response": {'));
          expect(
            result.prompt,
            contains(r'"content": "{\"city\":\"Paris\",\"temperature_c\":21}"'),
          );
          expect(result.prompt, contains('"tool_calls": ['));
          if (choice == ToolChoice.none) {
            expect(result.format, ChatFormat.contentOnly.index);
            expect(result.grammar, isNull);
          } else {
            expect(result.format, ChatFormat.generic.index);
            expect(result.grammar, isNotNull);
          }
        });
      }

      test('sends several results as one user turn', () {
        final call = _calls([
          _call('call00001', 'Paris'),
          _call('call00002', 'Rome'),
        ]);
        final separate = _render(path, [
          _user,
          call,
          _results([
            _result('call00001', {'temperature_c': 21}),
          ]),
          _results([
            _result('call00002', {'temperature_c': 25}),
          ]),
        ]).prompt;
        final together = _render(path, [
          _user,
          call,
          _results([
            _result('call00001', {'temperature_c': 21}),
            _result('call00002', {'temperature_c': 25}),
          ]),
        ]).prompt;

        expect(together, separate);
        expect(separate, contains('$_firstResponse\n$_secondResponse'));
      });

      for (final tools in [false, true]) {
        test('merges a user directly after tool results (tools=$tools)', () {
          const followUp = 'And Rome? Keep the units in Celsius.';
          final history = [
            ..._oneResult,
            const LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: followUp,
            ),
          ];
          for (final choice in ToolChoice.values) {
            for (final thinking in [false, true]) {
              final original = _render(
                path,
                _oneResult,
                tools: tools,
                toolChoice: choice,
                enableThinking: thinking,
              ).prompt;
              final prompt = _render(
                path,
                history,
                tools: tools,
                toolChoice: choice,
                enableThinking: thinking,
              ).prompt;
              // Only the retry's result turn gains the following user text.
              final resultEnd =
                  original.indexOf('\n}', original.indexOf('"tool_response"')) +
                  2;
              expect(resultEnd, greaterThan(1));
              expect(
                prompt,
                original.replaceRange(resultEnd, resultEnd, '\n$followUp'),
              );
              expect(history.last.content, followUp);
              expect(history[2].role, LlamaChatRole.tool);
            }
          }
        });
      }

      test('renders the turns after a tool round', () {
        final prompt = _render(path, [
          ..._oneResult,
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: 'It is 21C.',
          ),
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'And Rome?',
          ),
          _calls([_call('call00002', 'Rome')]),
          _results([
            _result('call00002', {'temperature_c': 25}),
          ]),
        ]).prompt;

        expect(prompt, contains('It is 21C.'));
        expect(prompt, contains('And Rome?'));
        expect(prompt, contains(_secondResponse));
        expect('"tool_response"'.allMatches(prompt), hasLength(2));
      });

      test('keeps a tool call without a result as it was', () {
        final prompt = _render(path, [
          _user,
          _calls([_call('call00001', 'Paris')]),
        ], tools: false).prompt;

        expect(prompt, isNot(contains('tool_calls')));
      });
    });
  }

  for (final path in _toolRoleTemplates) {
    test('${_name(path)} keeps its own tool-result rendering', () {
      final source = File(path).readAsStringSync();
      expect(TemplateCaps.detect(source).supportsToolResponses, isTrue);

      final prompt = _render(path, _oneResult).prompt;
      expect(prompt, isNot(contains('"tool_response": {')));
      expect(prompt, contains('temperature_c'));
    });
  }

  group('gemma-3-4b-it.jinja renders a tool message as given when it can', () {
    const result = LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(
          id: 'call00001',
          name: 'get_weather',
          result: '21C',
        ),
      ],
    );
    const next = LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'And Rome?',
    );
    const instruction =
        'Respond in JSON format, either with `tool_call` (a request to call '
        "tools) or with `response` reply to the user's request\n\n";
    for (final (name, messages, tail) in [
      ('[user, tool]', const [_user, result], ''),
      (
        '[user, tool, user]',
        const [_user, result, next],
        '<start_of_turn>user\nAnd Rome?<end_of_turn>\n',
      ),
    ]) {
      for (final tools in [false, true]) {
        test('$name ${tools ? 'with' : 'without'} tools', () {
          final prompt = _render(
            'test/fixtures/templates/gemma-3-4b-it.jinja',
            messages,
            tools: tools,
          ).prompt;

          expect(
            prompt,
            '<start_of_turn>user\n'
            '${tools ? instruction : ''}'
            'What is the weather in Paris and Rome?<end_of_turn>\n'
            '<start_of_turn>tool\n21C<end_of_turn>\n'
            '$tail'
            '<start_of_turn>model\n',
          );
        });
      }
    }
  });

  test('reports the first error when the user-turn retry fails too', () {
    const template = '''
{%- set ns = namespace(last='') -%}
{%- for message in messages -%}
{%- if message.role == 'tool' -%}{{ raise_exception('no tool role') }}{%- endif -%}
{%- if message.role == 'user' and ns.last == 'user' -%}{{ raise_exception('no two user turns') }}{%- endif -%}
{%- set ns.last = message.role -%}
{{- message.content -}}
{%- endfor -%}''';
    expect(TemplateCaps.detect(template).supportsToolResponses, isFalse);

    expect(
      () => ChatTemplateEngine.render(
        templateSource: template,
        messages: [
          ..._oneResult,
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'And Rome?',
          ),
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Another consecutive user turn still fails.',
          ),
        ],
        metadata: const {},
      ),
      throwsA(
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          allOf(contains('no tool role'), isNot(contains('no two user'))),
        ),
      ),
    );
  });

  test('reports the first error when the user-turn retry throws an Error', () {
    const template = '''
{%- for m in messages -%}
{%- if m.role == 'tool' -%}{{ raise_exception('no tool role') }}{%- endif -%}
{%- if m.role == 'user' and 'tool_response' in m.content -%}{{ 1 // 0 }}{%- endif -%}
{{ m.role }}: {{ m.content }}
{% endfor -%}''';
    expect(TemplateCaps.detect(template).supportsToolResponses, isFalse);

    expect(
      () => ChatTemplateEngine.render(
        templateSource: template,
        messages: _oneResult,
        metadata: const {},
      ),
      throwsA(
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          contains('no tool role'),
        ),
      ),
    );
  });

  group('gemma-3-4b-it.jinja retries every form of tool result', () {
    const path = 'test/fixtures/templates/gemma-3-4b-it.jinja';
    final call = _calls([_call('call00001', 'Paris')]);
    for (final (name, message) in [
      (
        'a text tool message',
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.tool,
          text: 'raw 21C',
        ),
      ),
      (
        'a legacy tool message',
        // ignore: deprecated_member_use_from_same_package
        const LlamaChatMessage(role: 'tool', content: 'raw 21C'),
      ),
      (
        'a tool result in a user message',
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [_result('call00001', 'raw 21C')],
        ),
      ),
    ]) {
      for (final tools in [false, true]) {
        test('$name ${tools ? 'with' : 'without'} tools', () {
          final prompt = _render(path, [
            _user,
            call,
            message,
          ], tools: tools).prompt;

          expect(
            prompt,
            contains('<start_of_turn>user\n{\n  "tool_response": {\n'),
          );
          expect(prompt, contains('"content": "raw 21C"'));
        });
      }
    }

    test('with an image in the request', () {
      final prompt = _render(path, [
        const LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaImageContent(url: 'http://example.com/a.png'),
            LlamaTextContent('Where is this? What is the weather there?'),
          ],
        ),
        call,
        _results([_result('call00001', 'sunny')]),
      ]).prompt;

      expect(prompt, contains('<__media__>'));
      expect(prompt, contains('"tool_response": {'));
      expect(prompt, contains('"content": "sunny"'));
    });

    test('but not a render-context error on the generic route', () {
      expect(
        () => _render(path, [
          _user,
          const LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [
              LlamaToolCallContent(
                id: 'call00001',
                name: 'get_weather',
                arguments: {},
                rawJson: '[1,2]',
              ),
            ],
          ),
          _results([_result('call00001', '21C')]),
        ]),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            startsWith('Failed to build render context'),
          ),
        ),
      );
    });
  });

  test('keeps tool calls a template renders itself on the retry', () {
    const template = '''
{%- for m in messages -%}
{%- if m.role == 'tool' and loop.last -%}{{ raise_exception('answer the result first') }}{%- endif -%}
{{ m.role }}: {{ m.content }}
{%- for call in m.tool_calls or [] %} CALL {{ call.function.name }}{% endfor %}
{% endfor -%}
{%- for tool in tools or [] %}{{ tool.function.name }}{% endfor -%}''';
    final caps = TemplateCaps.detect(template);
    expect(caps.supportsToolCalls, isTrue);
    expect(caps.supportsToolResponses, isFalse);

    final prompt = ChatTemplateEngine.render(
      templateSource: template,
      messages: _oneResult,
      metadata: const {},
    ).prompt;

    expect(prompt, contains('assistant:  CALL get_weather'));
    expect(prompt, isNot(contains('"tool_calls"')));
    expect(prompt, contains('"tool_response": {'));
  });

  test('keeps the error of a template that renders the tool role', () {
    const template = '''
{%- for message in messages -%}
{%- if message.role == 'tool' and loop.previtem.role == 'tool' -%}
{{ raise_exception('one result per turn') }}
{%- endif -%}
{{- message.role }}: {{ message.content }}
{% endfor -%}''';
    expect(TemplateCaps.detect(template).supportsToolResponses, isTrue);

    expect(
      () => ChatTemplateEngine.render(
        templateSource: template,
        messages: [
          _user,
          _calls([_call('call00001', 'Paris'), _call('call00002', 'Rome')]),
          _results([
            _result('call00001', {'temperature_c': 21}),
            _result('call00002', {'temperature_c': 25}),
          ]),
        ],
        metadata: const {},
      ),
      throwsA(
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          contains('one result per turn'),
        ),
      ),
    );
  });

  test('keeps the error of a template that rejects user turns too', () {
    const template = '''
{%- for message in messages -%}
{%- if loop.index0 == 2 -%}{{ raise_exception('only two messages') }}{%- endif -%}
{{- message.content -}}
{%- endfor -%}''';
    expect(TemplateCaps.detect(template).supportsToolResponses, isTrue);
    expect(
      () => ChatTemplateEngine.render(
        templateSource: template,
        messages: _oneResult,
        metadata: const {},
      ),
      throwsA(
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          contains('only two messages'),
        ),
      ),
    );
  });

  test('leaves a template that skips tool messages unchanged', () {
    const template = '''
{%- for message in messages -%}
{%- if message.role != 'tool' -%}{{ message.role }}: {{ message.content }}
{% endif -%}
{%- endfor -%}''';
    expect(TemplateCaps.detect(template).supportsToolResponses, isTrue);
    final prompt = ChatTemplateEngine.render(
      templateSource: template,
      messages: _oneResult,
      metadata: const {},
    ).prompt;
    expect(prompt, isNot(contains('tool_response')));
  });
}
