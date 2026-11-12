@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_templates.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/template_caps_cache.dart';
import 'package:test/test.dart';

const List<LlamaChatMessage> _conversation = <LlamaChatMessage>[
  LlamaChatMessage.fromText(
    role: LlamaChatRole.user,
    text: 'Weather in Paris?',
  ),
  LlamaChatMessage.withContent(
    role: LlamaChatRole.assistant,
    content: <LlamaContentPart>[
      LlamaToolCallContent(
        id: 'call00001',
        name: 'get_weather',
        arguments: <String, dynamic>{'city': 'Paris'},
        rawJson: '{"city":"Paris"}',
      ),
    ],
  ),
  LlamaChatMessage.withContent(
    role: LlamaChatRole.tool,
    content: <LlamaContentPart>[
      LlamaToolResultContent(
        id: 'call00001',
        name: 'get_weather',
        result: 'sunny',
      ),
    ],
  ),
  LlamaChatMessage.fromText(
    role: LlamaChatRole.assistant,
    text: 'It is sunny.',
  ),
  LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'And Rome?'),
];

LlamaChatTemplateResult _render(String fixture, {required bool parallel}) {
  return ChatTemplateEngine.render(
    templateSource: File('test/fixtures/templates/$fixture').readAsStringSync(),
    messages: _conversation,
    metadata: const <String, String>{},
    tools: <ToolDefinition>[
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: <ToolParam>[ToolParam.string('city')],
        handler: _noopHandler,
      ),
    ],
    parallelToolCalls: parallel,
    now: DateTime(2026, 1, 2, 12),
  );
}

void main() {
  late List<String> messages;

  setUp(() {
    TemplateCapsCache.shared.clear();
    messages = <String>[];
    LlamaLogger.instance.setLevel(LlamaLogLevel.debug);
    LlamaLogger.instance.setHandler((record) => messages.add(record.message));
  });

  tearDown(() {
    TemplateCapsCache.shared.clear();
    LlamaLogger.instance.setHandler(null);
    LlamaLogger.instance.setLevel(LlamaLogLevel.none);
  });

  test('Llama 3.2 renders a tool-call conversation', () {
    final result = _render('Llama-3_2-3B-Instruct.jinja', parallel: true);

    expect(result.format, ChatFormat.llama3.index);
    expect(result.prompt, contains('"name": "get_weather"'));
    expect(
      result.prompt,
      contains(
        'Weather in Paris?<|eot_id|>'
        '<|start_header_id|>assistant<|end_header_id|>\n\n'
        '{"name": "get_weather", "parameters": {"city": "Paris"}}<|eot_id|>'
        '<|start_header_id|>ipython<|end_header_id|>\n\n'
        '"sunny"<|eot_id|>'
        '<|start_header_id|>assistant<|end_header_id|>\n\n'
        'It is sunny.<|eot_id|>'
        '<|start_header_id|>user<|end_header_id|>\n\n'
        'And Rome?<|eot_id|>'
        '<|start_header_id|>assistant<|end_header_id|>\n\n',
      ),
    );
    expect(result.grammar, isNotNull);
    expect(
      messages,
      isNot(
        contains(contains('ChatTemplateEngine: Disabling parallelToolCalls')),
      ),
    );
    expect(
      messages,
      isNot(contains(contains('does not advertise tool definitions'))),
    );
  });

  test('Ministral 3 renders a tool-call conversation', () {
    final result = _render('Ministral-3-3B-Reasoning.jinja', parallel: true);

    expect(result.format, ChatFormat.ministral.index);
    expect(
      result.prompt,
      contains(
        '[AVAILABLE_TOOLS][{"type": "function", "function": '
        '{"name": "get_weather", "description": "Get weather", "parameters": '
        '{"type": "object", "properties": {"city": {"type": "string"}}}}}]'
        '[/AVAILABLE_TOOLS]'
        '[INST]Weather in Paris?[/INST]'
        '[TOOL_CALLS]get_weather[ARGS]{"city": "Paris"}</s>'
        '[TOOL_RESULTS]sunny[/TOOL_RESULTS]'
        'It is sunny.</s>'
        '[INST]And Rome?[/INST]',
      ),
    );
    expect(result.grammar, isNotNull);
    expect(
      messages,
      isNot(
        contains(contains('ChatTemplateEngine: Disabling parallelToolCalls')),
      ),
    );
    expect(
      messages,
      isNot(contains(contains('does not advertise tool definitions'))),
    );
  });

  test('FunctionGemma keeps string tool-call arguments verbatim', () {
    final result = _render('functiongemma-270m-it.jinja', parallel: false);

    // llama-server 7fe450e19 /apply-template output for this conversation;
    // it reports supports_object_arguments=false for this template and drops
    // the leading BOS text that its tokenizer adds.
    expect(
      result.prompt,
      '<bos><start_of_turn>developer\n'
      'You are a model that can do function calling with the following '
      'functions<start_function_declaration>declaration:get_weather'
      '{description:<escape>Get weather<escape>,parameters:{properties:'
      '{city:{description:<escape><escape>,type:<escape>STRING<escape>}},'
      'type:<escape>OBJECT<escape>}}<end_function_declaration>'
      '<end_of_turn>\n'
      '<start_of_turn>user\nWeather in Paris?<end_of_turn>\n'
      '<start_of_turn>model\n'
      '<start_function_call>call:get_weather{                    '
      '{"city":"Paris"}}<end_function_call>'
      '<start_function_response>response:get_weather{value:<escape>sunny'
      '<escape>}<end_function_response>It is sunny.<end_of_turn>\n'
      '<start_of_turn>user\nAnd Rome?<end_of_turn>\n'
      '<start_of_turn>model\n',
    );
  });

  test('Ministral 3 allows one tool call unless parallel calls are on', () {
    final single = _render('Ministral-3-3B-Reasoning.jinja', parallel: false);
    final parallel = _render('Ministral-3-3B-Reasoning.jinja', parallel: true);

    expect(single.prompt, parallel.prompt);
    expect(single.parser, isNot(parallel.parser));
  });

  test('Functionary v3.1 without tools renders no tool instructions', () {
    final result = ChatTemplateEngine.render(
      templateSource: File(
        'test/fixtures/llama_cpp_templates/meetkai-functionary-medium-v3.1.jinja',
      ).readAsStringSync(),
      messages: const <LlamaChatMessage>[
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: 'You are terse.',
        ),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
      ],
      metadata: const <String, String>{},
    );

    // llama-server 7fe450e19 /apply-template output, which drops the leading
    // BOS text.
    expect(
      result.prompt,
      '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\n'
      'Cutting Knowledge Date: December 2023\n\n<|eot_id|>'
      '<|start_header_id|>system<|end_header_id|>\n\nYou are terse.<|eot_id|>'
      '<|start_header_id|>user<|end_header_id|>\n\nHi<|eot_id|>'
      '<|start_header_id|>assistant<|end_header_id|>\n\n',
    );
  });

  group('Qwen3 tool-call turn matches llama.cpp', () {
    final upstream =
        jsonDecode(
              File(
                'test/fixtures/qwen3_tool_turn_render_upstream.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final expected = upstream['prompt'] as String;
    final templates = <String, String>{
      'fixture template': File(
        'test/fixtures/${upstream['template']}',
      ).readAsStringSync(),
      'LiteRT-LM built-in template': kLiteRtLmChatTemplates
          .singleWhere((template) => template.id == 'qwen3')
          .template,
    };
    List<LlamaChatMessage> conversation(List<LlamaContentPart> reasoning) =>
        <LlamaChatMessage>[
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'What is the weather in Paris?',
          ),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: <LlamaContentPart>[
              ...reasoning,
              const LlamaToolCallContent(
                id: 'call_0',
                name: 'get_weather',
                arguments: <String, dynamic>{'city': 'Paris'},
                rawJson: '{"city": "Paris"}',
              ),
            ],
          ),
          const LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: <LlamaContentPart>[
              LlamaToolResultContent(
                id: 'call_0',
                name: 'get_weather',
                result: 'sunny',
              ),
            ],
          ),
        ];
    final conversations = <String, List<LlamaChatMessage>>{
      'empty reasoning': conversation(const <LlamaContentPart>[
        LlamaThinkingContent(''),
      ]),
      'no reasoning': conversation(const <LlamaContentPart>[]),
    };

    for (final MapEntry(key: templateName, value: source)
        in templates.entries) {
      for (final MapEntry(key: name, value: messages)
          in conversations.entries) {
        test('$templateName: $name', () {
          final result = ChatTemplateEngine.render(
            templateSource: source,
            messages: messages,
            metadata: const <String, String>{},
          );

          expect(result.prompt, expected);
        });
      }
    }
  });

  group('parallel tool results match llama.cpp', () {
    final upstream =
        jsonDecode(
              File(
                'test/fixtures/multi_tool_result_render_upstream.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final templates = upstream['templates'] as Map<String, dynamic>;

    // Where each template opens its first tool result.
    const cases = <String, (ChatFormat, String)>{
      'templates/Qwen3-4B.jinja': (
        ChatFormat.hermes,
        '<|im_start|>user\n<tool_response>',
      ),
      'templates/Qwen3_5-0_8B.jinja': (
        ChatFormat.qwen3CoderXml,
        '<|im_start|>user\n<tool_response>',
      ),
      'templates/Ministral-3-3B-Reasoning.jinja': (
        ChatFormat.ministral,
        '[TOOL_RESULTS]',
      ),
      'templates/functiongemma-270m-it.jinja': (
        ChatFormat.functionGemma,
        '<start_function_response>',
      ),
      'templates/Phi-4-mini-instruct-reasoning.jinja': (
        ChatFormat.generic,
        '<|tool|>',
      ),
      'templates/LFM2_5-1_2B-Thinking.jinja': (
        ChatFormat.lfm2,
        '<|im_start|>tool',
      ),
    };

    ToolDefinition tool(String name, String description) => ToolDefinition(
      name: name,
      description: description,
      parameters: <ToolParam>[ToolParam.string('city', required: true)],
      handler: _noopHandler,
    );
    final tools = <ToolDefinition>[
      tool('get_weather', 'Return the weather for a city.'),
      tool('get_time', 'Return the local time for a city.'),
    ];
    const results = <LlamaToolResultContent>[
      LlamaToolResultContent(
        id: 'call_0',
        name: 'get_weather',
        result: 'RESULT_ONE',
      ),
      LlamaToolResultContent(
        id: 'call_1',
        name: 'get_time',
        result: 'RESULT_TWO',
      ),
    ];
    List<LlamaChatMessage> conversation(List<LlamaChatMessage> toolMessages) =>
        <LlamaChatMessage>[
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'What are the weather and the local time in Paris?',
          ),
          const LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: <LlamaContentPart>[
              LlamaToolCallContent(
                id: 'call_0',
                name: 'get_weather',
                arguments: <String, dynamic>{'city': 'Paris'},
                rawJson: '{"city":"Paris"}',
              ),
              LlamaToolCallContent(
                id: 'call_1',
                name: 'get_time',
                arguments: <String, dynamic>{'city': 'Paris'},
                rawJson: '{"city":"Paris"}',
              ),
            ],
          ),
          ...toolMessages,
        ];
    final layouts = <String, List<LlamaChatMessage>>{
      'one tool message': conversation(const <LlamaChatMessage>[
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: results,
        ),
      ]),
      'one tool message per result': conversation(<LlamaChatMessage>[
        for (final result in results)
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: <LlamaContentPart>[result],
          ),
      ]),
    };

    for (final MapEntry(key: fixture, value: (format, anchor))
        in cases.entries) {
      final expected =
          (templates[fixture] as Map<String, dynamic>)['prompt'] as String;
      for (final MapEntry(key: layout, value: messages) in layouts.entries) {
        test('$fixture: $layout', () {
          final result = ChatTemplateEngine.render(
            templateSource: File('test/fixtures/$fixture').readAsStringSync(),
            messages: messages,
            metadata: const <String, String>{},
            tools: tools,
            parallelToolCalls: true,
            enableThinking: false,
          );

          expect(result.format, format.index);
          expect(result.prompt, contains('RESULT_ONE'));
          expect(result.prompt, contains('RESULT_TWO'));
          expect(
            result.prompt.substring(result.prompt.indexOf(anchor)),
            expected.substring(expected.indexOf(anchor)),
          );
        });
      }
    }
  });
}

Future<Object?> _noopHandler(_) async {
  return 'ok';
}
