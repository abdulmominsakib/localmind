import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/qwen3_coder_xml_handler.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:test/test.dart';

void main() {
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

  test('Qwen3CoderXmlHandler keeps malformed XML tool scope as content', () {
    final handler = Qwen3CoderXmlHandler();
    const input =
        '<tool_call>\n<function=get_weather>\n<parameter=city>\n"Seoul"\n</tool_call>';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });

  test('Qwen3CoderXmlHandler emits PEG-constructed parser for Nemotron v3', () {
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

    expect(rendered.format, equals(ChatFormat.pegConstructed.index));
    expect(rendered.thinkingForcedOpen, isTrue);
    expect(rendered.parser, isNotNull);
    expect(rendered.parser, isNotEmpty);
    expect(rendered.grammarTriggers, hasLength(1));
    expect(rendered.grammarTriggers.first.value, equals('<tool_call>'));
    expect(rendered.preservedTokens, contains('<think>'));
    expect(rendered.preservedTokens, contains('</think>'));

    final parsed = ChatTemplateEngine.parse(
      rendered.format,
      'I am thinking\n'
      '</think>\n'
      '<tool_call>\n'
      '<function=python>\n'
      '<parameter=code>\n'
      'def hello():\n'
      '    print("Hello, world!")\n'
      '\n'
      'hello()\n'
      '</function>\n'
      '</tool_call>',
      parser: rendered.parser,
      thinkingForcedOpen: rendered.thinkingForcedOpen,
    );

    expect(parsed.reasoningContent, equals('I am thinking'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('python'));
    expect(
      parsed.toolCalls.first.function?.arguments,
      equals(
        '{"code":"def hello():\\n    print(\\"Hello, world!\\")\\n\\nhello()"}',
      ),
    );
  });

  test(
    'Nemotron v3 parser supports missing parameter close and parallel calls',
    () {
      final handler = Qwen3CoderXmlHandler();
      final tools = [
        ToolDefinition(
          name: 'python',
          description: 'Run Python',
          parameters: [ToolParam.string('code', required: true)],
          handler: _noop,
        ),
        ToolDefinition(
          name: 'get_weather',
          description: 'Get weather',
          parameters: [ToolParam.string('city', required: true)],
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
        metadata: const {internalParallelToolCallsMetadataKey: 'true'},
        tools: tools,
        enableThinking: true,
      );

      final parsed = ChatTemplateEngine.parse(
        rendered.format,
        'plan\n'
        '</think>\n'
        '<tool_call>\n'
        '<function=python>\n'
        '<parameter=code>\n'
        'print("hi")\n'
        '</function>\n'
        '</tool_call>\n'
        '<tool_call>\n'
        '<function=get_weather>\n'
        '<parameter=city>\n'
        'Seoul\n'
        '</parameter>\n'
        '</function>\n'
        '</tool_call>',
        parser: rendered.parser,
        thinkingForcedOpen: rendered.thinkingForcedOpen,
      );

      expect(parsed.reasoningContent, equals('plan'));
      expect(parsed.toolCalls, hasLength(2));
      expect(parsed.toolCalls[0].function?.name, equals('python'));
      expect(
        parsed.toolCalls[0].function?.arguments,
        equals('{"code":"print(\\"hi\\")"}'),
      );
      expect(parsed.toolCalls[1].function?.name, equals('get_weather'));
      expect(
        parsed.toolCalls[1].function?.arguments,
        equals('{"city":"Seoul"}'),
      );
    },
  );

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
    expect(nemotron.format, equals(ChatFormat.pegConstructed.index));
    expect(nemotron.parser, isNotNull);
    expect(nemotron.parser, isNotEmpty);
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
}

Future<Object?> _noop(_) async {
  return 'ok';
}
