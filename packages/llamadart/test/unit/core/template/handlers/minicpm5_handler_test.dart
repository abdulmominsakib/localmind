import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  group('MiniCPM5 template support', () {
    const templateSource = '''
{{- bos_token }}
{# Tool usage guidelines: <function name="x"><param name="y"></param></function> #}
{%- for message in messages %}
  {%- if message.role == "user" %}
    {{- '<|im_start|>user\n' + message.content + '<|im_end|>\n' }}
  {%- elif message.role == "assistant" %}
    {{- '<|im_start|>assistant\n' + message.content }}
    {%- if message.tool_calls and not has_tool_sep %}
      {%- for tool_call in message.tool_calls %}
        {%- if tool_call.function %}
          {%- set tool_call = tool_call.function %}
        {%- endif %}
        {{- '<function name="' ~ tool_call.name ~ '">' }}
        {%- if tool_call.arguments %}
          {%- for param_name, param_value in tool_call.arguments.items() %}
            {{- '<param name="' ~ param_name ~ '">' ~ param_value ~ '</param>' }}
          {%- endfor %}
        {%- endif %}
        {{- '</function>' }}
      {%- endfor %}
    {%- endif %}
    {{- '<|im_end|>\n' }}
  {%- endif %}
{%- endfor %}
{%- if add_generation_prompt %}
  {{- '<|im_start|>assistant\n' }}
  {%- if enable_thinking is true %}
    {{- '<think>\n' }}
  {%- endif %}
{%- endif %}
''';

    test('detects MiniCPM5 template markers', () {
      expect(detectChatFormat(templateSource), ChatFormat.minicpm5);
    });

    test('renders native MiniCPM5 XML tool-call context', () {
      final result = ChatTemplateEngine.render(
        templateSource: templateSource,
        metadata: const {'tokenizer.ggml.bos_token': '<s>'},
        messages: [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: const [
              LlamaTextContent('checking'),
              LlamaToolCallContent(
                name: 'get_weather',
                arguments: {'location': 'Seoul'},
                rawJson: '{"location":"Seoul"}',
              ),
            ],
          ),
        ],
        tools: [
          ToolDefinition(
            name: 'get_weather',
            description: 'Get weather',
            parameters: [ToolParam.string('location')],
            handler: (_) async => null,
          ),
        ],
      );

      expect(result.format, ChatFormat.minicpm5.index);
      expect(result.prompt, contains('<function name="get_weather">'));
      expect(result.prompt, contains('<param name="location">Seoul</param>'));
      expect(result.grammar, contains('minicpm-value ::= raw-text | value'));
      expect(result.grammar, contains('raw-text ::= ([^<])*'));
      expect(result.grammarTriggers.map((trigger) => trigger.value), [
        '<function name="',
      ]);
      expect(result.thinkingForcedOpen, isTrue);
    });

    test('closes disabled thinking without adding an extra blank line', () {
      const falseClosingTemplate = '''
{{- bos_token }}
{# Tool usage guidelines: <function name="x"><param name="y"></param></function> #}
{%- for message in messages %}
  {{- '<|im_start|>' + message.role + '\n' + message.content + '<|im_end|>\n' }}
{%- endfor %}
{%- if add_generation_prompt %}{{- '<|im_start|>assistant\n<think>\n' }}{%- endif %}
''';
      final result = ChatTemplateEngine.render(
        templateSource: falseClosingTemplate,
        metadata: const {'tokenizer.ggml.bos_token': '<s>'},
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        enableThinking: false,
      );

      expect(result.prompt, endsWith('<think>\n</think>\n\n'));
      expect(result.prompt, isNot(contains('<think>\n\n</think>')));
      expect(result.thinkingForcedOpen, isFalse);
    });

    test('parses MiniCPM5 XML tool calls and reasoning', () {
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.minicpm5.index,
        '<think>\nplan\n</think>\n\n'
        'checking\n'
        '<function name="get_weather"><param name="location">Seoul</param></function>',
      );

      expect(parsed.reasoningContent, 'plan');
      expect(parsed.content, 'checking');
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.single.function?.name, 'get_weather');
      expect(
        parsed.toolCalls.single.function?.arguments,
        '{"location":"Seoul"}',
      );
    });

    test('parses MiniCPM5 CDATA tool argument values', () {
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.minicpm5.index,
        '<function name="write_note">'
        '<param name="body"><![CDATA[use </param> literally]]></param>'
        '</function>',
      );

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.single.function?.name, 'write_note');
      expect(
        parsed.toolCalls.single.function?.arguments,
        '{"body":"use </param> literally"}',
      );
    });

    test(
      'keeps pre-close streaming text in reasoning when thinking is forced open',
      () {
        final parsed = ChatTemplateEngine.parse(
          ChatFormat.minicpm5.index,
          'still planning',
          thinkingForcedOpen: true,
        );

        expect(parsed.content, isEmpty);
        expect(parsed.reasoningContent, 'still planning');
        expect(parsed.toolCalls, isEmpty);
      },
    );
  });
}
