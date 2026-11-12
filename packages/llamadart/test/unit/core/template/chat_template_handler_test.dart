import 'dart:typed_data';

import 'package:dinja/dinja.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/chat_template_handler.dart';
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:llamadart/src/core/template/tool_call_grammar_utils.dart';
import 'package:test/test.dart';

void main() {
  test('fixed strftime_now renders do not change the default clock', () {
    final handler = _FakeHandler();
    final template = Template("{{ strftime_now('%Y-%m-%d') }}");
    String render(Map<String, String> metadata) =>
        handler.renderTemplate(template, metadata: metadata, context: const {});
    final before = DateTime.now();
    expect(
      render({internalTemplateNowMetadataKey: '1984-06-01T12:34:56.000Z'}),
      '1984-06-01',
    );
    final defaultOutput = render(const {});
    final invalidOutput = render({internalTemplateNowMetadataKey: 'invalid'});
    final after = DateTime.now();
    String date(DateTime time) =>
        '${time.year.toString().padLeft(4, '0')}-'
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')}';
    expect(defaultOutput, anyOf(date(before), date(after)));
    expect(invalidOutput, anyOf(date(before), date(after)));
  });

  test('fixed strftime_now retains escaping of a user supplied format', () {
    final handler = _FakeHandler();
    final template = Template('{{ strftime_now(format) }}');
    final context = {'format': JinjaString.user('<tag>%Y</tag>')};
    final fixed = handler.renderTemplate(
      template,
      metadata: {internalTemplateNowMetadataKey: '1984-06-01T12:34:56.000Z'},
      context: context,
    );
    expect(fixed, '&lt;tag&gt;1984&lt;/tag&gt;');
  });

  test('renderTemplate injects chat_template_kwargs metadata', () {
    final handler = _FakeHandler();
    final output = handler.renderTemplate(
      Template('{{ foo }} {{ bar }}'),
      metadata: const {
        internalChatTemplateKwargsMetadataKey: '{"foo":"from-metadata"}',
      },
      context: const {'bar': 'from-context'},
    );

    expect(output, 'from-metadata from-context');
  });

  test('renderTemplate ignores invalid chat_template_kwargs metadata', () {
    final handler = _FakeHandler();
    final output = handler.renderTemplate(
      Template('{{ bar }}'),
      metadata: const {internalChatTemplateKwargsMetadataKey: '{not-json'},
      context: const {'bar': 'from-context'},
    );

    expect(output, 'from-context');
  });

  test('gives empty content as a text part only to templates that read '
      'content only as parts', () {
    const typedOnly =
        '{%- for message in messages -%}'
        '{%- if message.content is string -%}'
        "{{ raise_exception('string content') }}"
        '{%- endif -%}'
        '{{ message.role }}:'
        '{%- for part in message.content -%}[{{ part.text }}]{%- endfor -%};'
        '{%- endfor -%}';
    const messages = <LlamaChatMessage>[
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Weather?'),
      LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: <LlamaContentPart>[
          LlamaToolCallContent(
            id: 'call_0',
            name: 'get_weather',
            arguments: <String, dynamic>{'city': 'Paris'},
            rawJson: '{"city":"Paris"}',
          ),
        ],
      ),
    ];
    final caps = TemplateCaps.detect(typedOnly);
    expect(caps.supportsTypedContent, isTrue);
    expect(caps.supportsStringContent, isFalse);

    final result = ChatTemplateEngine.handlerFor(ChatFormat.contentOnly)
        .renderWithMultimodalContent(
          templateSource: typedOnly,
          messages: messages,
          metadata: const <String, String>{},
          addAssistant: false,
        );

    expect(result.prompt, 'user:[Weather?];assistant:[];');
  });

  test('templateMessages turns media in a tool result into the marker when '
      'called directly', () {
    // Public callers pass messages the engine has not converted.
    final rendered = ChatTemplateEngine.handlerFor(ChatFormat.hermes)
        .templateMessages([
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: 'call_0',
                name: 'screenshot',
                result: 'ok',
                content: [
                  LlamaImageContent(bytes: Uint8List.fromList([1])),
                ],
              ),
            ],
          ),
        ]);

    expect(rendered.single['content'], 'ok<__media__>');
  });

  group('required calls after a forced-open thought', () {
    final tools = [
      ToolDefinition(
        name: 'weather',
        description: 'w',
        parameters: [ToolParam.string('city', required: true)],
      ),
    ];

    for (final format in [
      ChatFormat.deepseekV3,
      ChatFormat.hermes,
      ChatFormat.seedOss,
      ChatFormat.minimaxM2,
      ChatFormat.apriel15,
      ChatFormat.exaoneMoe,
      ChatFormat.commandR7B,
      ChatFormat.cohere2Moe,
      ChatFormat.minicpm5,
      ChatFormat.hunyuanV3,
    ]) {
      final handler = ChatTemplateEngine.handlerFor(format);
      LlamaChatTemplateResult render(
        String toolChoice, {
        bool thinking = true,
      }) => handler.render(
        templateSource:
            '{{ messages[0]["content"] }}${handler.thinkingStartTag}\n',
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: {internalToolChoiceMetadataKey: toolChoice},
        tools: tools,
        enableThinking: thinking,
      );

      test('${format.name} grammar closes the thought before the calls', () {
        final required = render('required');
        expect(required.thinkingForcedOpen, isTrue);
        expect(
          required.grammar,
          contains(
            'root ::= think-body '
            '${ToolCallGrammarUtils.literal(handler.thinkingEndTag)} '
            'think-space (',
          ),
        );
        for (final other in [
          render('auto'),
          render('required', thinking: false),
        ]) {
          expect(other.grammar, isNot(contains('think-body')));
        }
      });
    }
  });

  group('templates that read tool-call arguments as objects', () {
    const template =
        '{%- for message in messages -%}'
        '{%- for call in message.tool_calls or [] -%}'
        '{{ call.function.name }}:{{ call.function.arguments | tojson }};'
        '{%- endfor -%}'
        '{%- endfor -%}';
    const messages = <LlamaChatMessage>[
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Weather?'),
      LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: <LlamaContentPart>[
          LlamaToolCallContent(
            id: 'call_0',
            name: 'get_weather',
            arguments: <String, dynamic>{'city': 'Paris'},
            rawJson: '{"city":"Paris"}',
          ),
        ],
      ),
    ];
    // These handlers move tool calls into message content as JSON text.
    const toolCallsInContent = <ChatFormat>{
      ChatFormat.generic,
      ChatFormat.granite,
    };

    for (final format in ChatFormat.values) {
      if (toolCallsInContent.contains(format)) continue;
      test('get parsed arguments from the ${format.name} handler', () {
        final result = ChatTemplateEngine.handlerFor(format).render(
          templateSource: template,
          messages: messages,
          metadata: const <String, String>{},
          addAssistant: false,
        );

        expect(result.prompt, contains('get_weather:{"city": "Paris"};'));
      });
    }
  });
}

class _FakeHandler extends ChatTemplateHandler {
  @override
  List<String> get additionalStops => const <String>[];

  @override
  ChatFormat get format => ChatFormat.generic;

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    return ChatParseResult(content: output);
  }

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    throw UnimplementedError();
  }
}
