import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/template_render_context.dart';
import 'package:test/test.dart';

void main() {
  const baseTemplate = '{{ "BASE:" ~ messages[0]["content"] }}';
  const customTemplate = '{{ "CUSTOM:" ~ messages[0]["content"] }}';

  final messages = [const LlamaChatMessage(role: 'user', content: 'hello')];

  group('ChatTemplateEngine template routing', () {
    test('supports per-call custom template override', () {
      final result = ChatTemplateEngine.render(
        templateSource: baseTemplate,
        messages: messages,
        metadata: const {},
        customTemplate: customTemplate,
      );

      expect(result.prompt, contains('CUSTOM:hello'));
      expect(result.prompt, isNot(contains('BASE:hello')));
    });

    test(
      'does not apply generic tool-call serialization to content-only routing',
      () {
        const template = '{{ "CONTENT:" ~ messages[0]["content"] }}';
        const history = [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [
              LlamaTextContent('done'),
              LlamaToolCallContent(
                name: 'weather',
                arguments: {'city': 'Seoul'},
                rawJson: '{"city":"Seoul"}',
              ),
            ],
          ),
        ];

        final result = ChatTemplateEngine.render(
          templateSource: template,
          messages: history,
          metadata: const {},
        );

        expect(result.format, equals(ChatFormat.contentOnly.index));
        expect(result.prompt, contains('CONTENT:done'));
        expect(result.prompt, isNot(contains('"tool_calls"')));
        expect(result.prompt, isNot(contains('weather')));
      },
    );

    test(
      'multimodal templates propagate enableThinking and force-open state',
      () {
        const template = '''
{%- macro render_content(content) -%}
  {%- if content is string -%}
    {{- content -}}
  {%- elif content is iterable and content is not mapping -%}
    {%- for item in content -%}
      {%- if 'image' in item or item.type == 'image' -%}
        {{- '<|vision_start|><|image_pad|><|vision_end|>' -}}
      {%- elif 'text' in item -%}
        {{- item.text -}}
      {%- endif -%}
    {%- endfor -%}
  {%- endif -%}
{%- endmacro -%}
{%- for message in messages -%}
  {{- '<|im_start|>' + message.role + '\n' + render_content(message.content) + '<|im_end|>\n' -}}
{%- endfor -%}
{%- if add_generation_prompt -%}
  {{- '<|im_start|>assistant\n' -}}
  {%- if enable_thinking is defined and enable_thinking is true -%}
    {{- '<think>\n' -}}
  {%- else -%}
    {{- '<think>\n\n</think>\n\n' -}}
  {%- endif -%}
{%- endif -%}
''';
        final multimodalMessages = [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              const LlamaTextContent('look'),
              LlamaImageContent(
                bytes: Uint8List.fromList([0]),
                width: 1,
                height: 1,
              ),
            ],
          ),
        ];

        final enabled = ChatTemplateEngine.render(
          templateSource: template,
          messages: multimodalMessages,
          metadata: const {},
          enableThinking: true,
        );

        expect(
          enabled.prompt,
          contains('look<|vision_start|><|image_pad|><|vision_end|>'),
        );
        expect(enabled.prompt, endsWith('<|im_start|>assistant\n<think>\n'));
        expect(enabled.thinkingForcedOpen, isTrue);

        final disabled = ChatTemplateEngine.render(
          templateSource: template,
          messages: multimodalMessages,
          metadata: const {},
          enableThinking: false,
        );

        expect(disabled.prompt, contains('<think>\n\n</think>\n\n'));
        expect(disabled.thinkingForcedOpen, isFalse);
      },
    );

    test('multimodal thinking uses handler-specific reasoning tags', () {
      const template = '''
{%- macro render_content(content) -%}
  {%- if content is string -%}
    {{- content -}}
  {%- elif content is iterable and content is not mapping -%}
    {%- for item in content -%}
      {%- if item.type == 'image' -%}
        {{- '<|image|>' -}}
      {%- elif item.type == 'text' -%}
        {{- item.text -}}
      {%- endif -%}
    {%- endfor -%}
  {%- endif -%}
{%- endmacro -%}
{%- for message in messages -%}
  {{- '[INST]' + render_content(message.content) + '[/INST]' -}}
{%- endfor -%}
{%- if add_generation_prompt -%}
  {%- if enable_thinking is defined and enable_thinking is true -%}
    {{- '[THINK]\n' -}}
  {%- else -%}
    {{- '[THINK]\n[/THINK]\n' -}}
  {%- endif -%}
{%- endif -%}
''';
      final multimodalMessages = [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            const LlamaTextContent('look'),
            LlamaImageContent(
              bytes: Uint8List.fromList([0]),
              width: 1,
              height: 1,
            ),
          ],
        ),
      ];

      final enabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: multimodalMessages,
        metadata: const {},
        enableThinking: true,
      );

      expect(enabled.format, ChatFormat.magistral.index);
      expect(enabled.prompt, endsWith('[THINK]\n'));
      expect(enabled.thinkingForcedOpen, isTrue);

      final disabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: multimodalMessages,
        metadata: const {},
        enableThinking: false,
      );

      expect(disabled.prompt, contains('[THINK]\n[/THINK]\n'));
      expect(disabled.prompt, isNot(contains('</think>')));
      expect(disabled.thinkingForcedOpen, isFalse);
    });

    test('keeps old workaround format matrix in handler policies', () {
      final expectedPolicies = <ChatFormat, TemplateToolCallSerialization>{
        for (final format in ChatFormat.values)
          format: TemplateToolCallSerialization.none,
        ChatFormat.generic:
            TemplateToolCallSerialization.genericSchemaInContent,
        ChatFormat.granite:
            TemplateToolCallSerialization.genericSchemaInContent,
        ChatFormat.mistralNemo: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.llama3: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.llama3BuiltinTools:
            TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.commandR7B: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.cohere2Moe: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.glm45: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.hunyuanV3: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.minimaxM2: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.minicpm5: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.qwen3CoderXml: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.seedOss: TemplateToolCallSerialization.normalizeOnly,
      };

      for (final MapEntry(key: format, value: expected)
          in expectedPolicies.entries) {
        final actual = ChatTemplateEngine.handlerFor(
          format,
        ).toolCallSerialization;
        _expectToolCallSerialization(
          actual,
          expected,
          reason: 'Unexpected tool-call serialization for $format',
        );
      }
    });

    test(
      'preserves GLM-OCR image markers through render-context serialization',
      () {
        const template = '''[gMASK]<sop>
{# GLM detection marker: <arg_key>name</arg_key><arg_value>value</arg_value> #}
{% for m in messages %}
{% if m.role == 'user' %}<|user|>
{% for item in m.content %}
{% if item.type == 'image' %}<|begin_of_image|><|image|><|end_of_image|>{% elif item.type == 'text' %}{{ item.text }}{% endif %}
{% endfor %}
{% endif %}
{% endfor %}
{% if add_generation_prompt %}<|assistant|>{% endif %}''';
        const multimodalMessages = [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaImageContent(path: '/tmp/page.png'),
              LlamaTextContent('Extract text.'),
            ],
          ),
        ];

        final result = ChatTemplateEngine.render(
          templateSource: template,
          messages: multimodalMessages,
          metadata: const {},
        );

        expect(result.format, equals(ChatFormat.glm45.index));
        expect(
          result.prompt,
          contains('<|begin_of_image|><__media__><|end_of_image|>'),
        );
        expect(result.prompt, contains('Extract text.'));
      },
    );

    test(
      'renders actual GLM-OCR image prompt without leaking image source',
      () {
        const multimodalMessages = [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaImageContent(path: '/tmp/page.png'),
              LlamaTextContent('Text Extraction:'),
            ],
          ),
        ];

        final result = ChatTemplateEngine.render(
          templateSource: _actualGlmOcrTemplate,
          messages: multimodalMessages,
          metadata: const {},
        );

        expect(result.format, equals(ChatFormat.glm45.index));
        expect(result.prompt, startsWith('[gMASK]<sop>'));
        expect(result.prompt, contains('<|user|>'));
        expect(_mediaPlaceholderCount(result.prompt), equals(1));
        expect(result.prompt, contains('Text Extraction:'));
        expect(result.prompt, contains('<|assistant|>'));
        expect(result.prompt, isNot(contains('file:///tmp/page.png')));
        expect(result.prompt, isNot(contains('image_url')));
        expect(result.prompt, isNot(contains('data:image')));
      },
    );

    test('keeps GLM-OCR image marker when GLM tool-call policy runs', () {
      const history = [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaImageContent(path: '/tmp/page.png'),
            LlamaTextContent('Text Extraction:'),
          ],
        ),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            LlamaToolCallContent(
              name: 'ocr_hint',
              arguments: {'language': 'ko'},
              rawJson: '{"language":"ko"}',
            ),
          ],
        ),
      ];

      final result = ChatTemplateEngine.render(
        templateSource: _actualGlmOcrTemplate,
        messages: history,
        metadata: const {},
      );

      expect(result.format, equals(ChatFormat.glm45.index));
      expect(_mediaPlaceholderCount(result.prompt), equals(1));
      expect(result.prompt, contains('Text Extraction:'));
      expect(result.prompt, contains('<tool_call>ocr_hint'));
      expect(result.prompt, contains('<arg_key>language</arg_key>'));
      expect(result.prompt, contains('<arg_value>ko</arg_value>'));
    });

    test('tool_choice none disables GLM tool rendering and grammar', () {
      const baseTemplate = '''[gMASK]<sop>
{# GLM detection marker: <arg_key>name</arg_key><arg_value>value</arg_value> #}
{% if tools %}TOOLS:{{ tools[0]["function"]["name"] }}{% endif %}
{% for m in messages %}{% if m.role == 'user' %}<|user|>{{ m.content }}{% endif %}{% endfor %}
{% if add_generation_prompt %}<|assistant|>{% endif %}''';
      const toolUseTemplate = 'TOOL_USE_VARIANT\n$baseTemplate';
      final tools = [
        ToolDefinition(
          name: 'get_weather',
          description: 'Get weather',
          parameters: [ToolParam.string('city')],
          handler: _noopHandler,
        ),
      ];

      final result = ChatTemplateEngine.render(
        templateSource: baseTemplate,
        messages: messages,
        metadata: const {'tokenizer.chat_template.tool_use': toolUseTemplate},
        tools: tools,
        toolChoice: ToolChoice.none,
      );

      expect(result.format, equals(ChatFormat.glm45.index));
      expect(result.prompt, isNot(contains('TOOL_USE_VARIANT')));
      expect(result.prompt, isNot(contains('TOOLS:get_weather')));
      expect(result.grammar, isNull);
      expect(result.grammarLazy, isFalse);
      expect(result.preservedTokens, isEmpty);
      expect(result.grammarTriggers, isEmpty);
    });

    test(
      'keeps system text before media for templates without system role',
      () {
        const template = '''[gMASK]<sop>
{# GLM detection marker: <arg_key>name</arg_key><arg_value>value</arg_value> #}
{% for m in messages %}
{% if m.role == 'user' %}<|user|>
{% for item in m.content %}
{% if item.type == 'image' %}<|begin_of_image|><|image|><|end_of_image|>{% elif item.type == 'text' %}{{ item.text }}{% endif %}
{% endfor %}
{% endif %}
{% endfor %}
{% if add_generation_prompt %}<|assistant|>{% endif %}''';
        const multimodalMessages = [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.system,
            text: 'Use OCR mode.',
          ),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaImageContent(path: '/tmp/page.png'),
              LlamaTextContent('Extract text.'),
            ],
          ),
        ];

        final result = ChatTemplateEngine.render(
          templateSource: template,
          messages: multimodalMessages,
          metadata: const {},
        );

        expect(result.format, equals(ChatFormat.glm45.index));
        final systemIndex = result.prompt.indexOf('Use OCR mode.');
        final mediaIndex = result.prompt.indexOf('<__media__>');
        final taskIndex = result.prompt.indexOf('Extract text.');
        expect(systemIndex, isNonNegative);
        expect(mediaIndex, isNonNegative);
        expect(taskIndex, isNonNegative);
        expect(systemIndex, lessThan(mediaIndex));
        expect(mediaIndex, lessThan(taskIndex));
      },
    );

    test(
      'generic tool instruction injection preserves multimodal user parts',
      () {
        const template = '''{% for m in messages %}
{% if m.role == 'user' %}
{% for item in m.content %}{% if item.type == 'image' %}<image>{% elif item.type == 'text' %}{{ item.text }}{% endif %}{% endfor %}
{% endif %}
{% endfor %}''';
        final tools = [
          ToolDefinition(
            name: 'get_weather',
            description: 'Get weather',
            parameters: [ToolParam.string('city')],
            handler: _noopHandler,
          ),
        ];

        final result = ChatTemplateEngine.render(
          templateSource: template,
          messages: const [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [
                LlamaImageContent(path: '/tmp/page.png'),
                LlamaTextContent('Extract text.'),
              ],
            ),
          ],
          metadata: const {},
          tools: tools,
        );

        expect(result.format, equals(ChatFormat.generic.index));
        expect(result.prompt, contains('Respond in JSON format'));
        expect(result.prompt, contains('<__media__>'));
        expect(result.prompt, contains('Extract text.'));
        expect(
          result.prompt.indexOf('Respond in JSON format'),
          lessThan(result.prompt.indexOf('<__media__>')),
        );
        expect(
          result.prompt.indexOf('<__media__>'),
          lessThan(result.prompt.indexOf('Extract text.')),
        );
      },
    );

    test('fails loudly when required tool-call serialization is invalid', () {
      const template = '{{ messages[0]["content"] }}';
      final tools = [
        ToolDefinition(
          name: 'get_weather',
          description: 'Get weather',
          parameters: [ToolParam.string('city')],
          handler: _noopHandler,
        ),
      ];

      expect(
        () => ChatTemplateEngine.render(
          templateSource: template,
          messages: const [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.assistant,
              content: [
                LlamaToolCallContent(
                  name: 'get_weather',
                  arguments: {},
                  rawJson: '["not", "an", "object"]',
                ),
              ],
            ),
          ],
          metadata: const {},
          tools: tools,
        ),
        throwsA(
          isA<LlamaInferenceException>()
              .having(
                (error) => error.details.toString(),
                'details',
                isNot(contains('stackTrace')),
              )
              .having(
                (error) => error.details.toString(),
                'details',
                contains('cause'),
              ),
        ),
      );
    });
  });

  group('ChatTemplateEngine grammar routing', () {
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city')],
        handler: _noopHandler,
      ),
    ];

    const grammarMessages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
    ];

    test('applies generic tool grammar for generic templates', () {
      const template =
          '<|im_start|>user\n{{ messages[0]["content"] }}<|im_end|>\n<|im_start|>assistant\n';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
      );

      expect(result.format, equals(ChatFormat.generic.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isFalse);
    });

    test('uses format-native grammar for format-specific handlers', () {
      const template = '>>>all\n{{ messages[0]["content"] }}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
      );

      expect(result.format, equals(ChatFormat.functionaryV32.index));
      expect(result.grammar, isNotNull);
      expect(result.grammar!, contains('tool-0-call'));
    });

    test('uses generic routing for tools + schema requests', () {
      const template =
          '<|END_THINKING|><|START_ACTION|>{{ messages[0]["content"] }}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        responseFormat: const {
          'type': 'json_schema',
          'json_schema': {
            'schema': {
              'type': 'object',
              'properties': {
                'ok': {'type': 'boolean'},
              },
              'required': ['ok'],
            },
          },
        },
      );

      expect(result.format, equals(ChatFormat.generic.index));
    });

    test('uses content-only routing for schema-disabled formats', () {
      const template = '<tool_call>{{ messages[0]["content"] }}</tool_call>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        responseFormat: const {'type': 'json_object'},
      );

      expect(result.format, equals(ChatFormat.contentOnly.index));
    });

    test('uses content-only schema routing for Cohere2 MoE templates', () {
      const template =
          '<|START_TEXT|>{{ messages[0]["content"] }}<|END_TEXT|>'
          '<|START_ACTION|>[]<|END_ACTION|>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        responseFormat: const {'type': 'json_object'},
      );

      expect(result.format, equals(ChatFormat.contentOnly.index));
    });

    test('disables lazy grammar for required tool choice when needed', () {
      const template =
          '<tool_call>\n<function=\n<function>\n<parameters>\n<parameter=\n{{ messages[0]["content"] }}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );

      expect(result.format, equals(ChatFormat.qwen3CoderXml.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isFalse);
    });

    test('routes LFM2 tool requests to generic tool grammar', () {
      const template =
          '{%- set keep_past_thinking = true -%}\n'
          '<|im_start|>user\n{{ messages[0]["content"] }}<|im_end|>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );

      expect(result.format, equals(ChatFormat.generic.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isFalse);
    });

    test('uses LFM2 grammar for strict LFM2 required tool choice', () {
      const template =
          'List of tools: <|tool_list_start|>[{"name":"x"}]<|tool_list_end|>'
          '<|im_start|>user\n{{ messages[0]["content"] }}<|im_end|>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );

      expect(result.format, equals(ChatFormat.lfm2.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isFalse);
    });

    test('keeps lazy grammar for strict LFM2 force-json-schema mode', () {
      const template =
          'List of tools: <|tool_list_start|>[{"name":"x"}]<|tool_list_end|>'
          '{% if messages[0]["role"] == "system" %}'
          '<|im_start|>system\n{{ messages[0]["content"] }}<|im_end|>'
          '{% endif %}'
          '<|im_start|>user\n{{ messages[1]["content"] }}<|im_end|>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.system,
            text: 'Force JSON schema.\nSystem prompt',
          ),
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'ping'),
        ],
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.auto,
      );

      expect(result.format, equals(ChatFormat.lfm2.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isTrue);
    });

    test('routes Gemma tool requests to generic tool grammar', () {
      const template =
          '{%- if messages -%}<start_of_turn>user\n'
          '{{ messages[0]["content"] }}<end_of_turn>\n'
          '<start_of_turn>model\n{%- endif -%}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.auto,
      );

      expect(result.format, equals(ChatFormat.generic.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isFalse);
      expect(result.additionalStops, contains('<end_of_turn>'));
      expect(result.additionalStops, isNot(contains('<|im_end|>')));
    });

    test('routes Gemma no-tool requests to content-only', () {
      const template =
          '{%- if messages -%}<start_of_turn>user\n'
          '{{ messages[0]["content"] }}<end_of_turn>\n'
          '<start_of_turn>model\n{%- endif -%}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: const [],
      );

      expect(result.format, equals(ChatFormat.contentOnly.index));
    });

    test('routes Gemma tool_choice none requests to content-only', () {
      const template =
          '{%- if messages -%}<start_of_turn>user\n'
          '{{ messages[0]["content"] }}<end_of_turn>\n'
          '<start_of_turn>model\n{%- endif -%}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.none,
      );

      expect(result.format, equals(ChatFormat.contentOnly.index));
      expect(result.grammar, isNull);
      expect(result.prompt, isNot(contains('Respond in JSON format')));
    });

    test('routes FunctionGemma-like templates to the FunctionGemma handler', () {
      const template =
          '<start_of_turn>user\n{{ messages[0]["content"] }}<end_of_turn>\n'
          '<start_of_turn>model\n'
          '<start_function_call>call:get_weather{location:<escape>Seoul<escape>}'
          '<end_function_call>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
      );
      expect(result.format, equals(ChatFormat.functionGemma.index));
      expect(result.grammar, isNull);
    });

    test('routes Gemma 4 templates to the Gemma 4 handler', () {
      const template =
          '<|turn>user\n{{ messages[0]["content"] }}<turn|>\n'
          '<|turn>model\n'
          '{% if tools %}<|tool_call>call:get_weather{location:<|"|>Seoul<|"|>}<tool_call|>{% endif %}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
      );

      expect(result.format, equals(ChatFormat.gemma4.index));
      expect(result.grammar, isNull);
      expect(result.additionalStops, contains('<tool_call|>'));
      expect(result.additionalStops, contains('<turn|>'));
    });

    test('routes generic templates to content-only for tool_choice none', () {
      const template =
          '<|im_start|>user\n{{ messages[0]["content"] }}<|im_end|>\n'
          '<|im_start|>assistant\n';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.none,
      );

      expect(result.format, equals(ChatFormat.contentOnly.index));
      expect(result.grammar, isNull);
      expect(result.prompt, isNot(contains('Respond in JSON format')));
    });

    test(
      'routes Mistral Nemo templates to content-only for tool_choice none',
      () {
        const template = '[TOOL_CALLS]{{ messages[0]["content"] }}';

        final result = ChatTemplateEngine.render(
          templateSource: template,
          messages: grammarMessages,
          metadata: const {},
          tools: tools,
          toolChoice: ToolChoice.none,
        );

        expect(result.format, equals(ChatFormat.contentOnly.index));
        expect(result.grammar, isNull);
      },
    );

    test('routes Ministral templates to Ministral handler', () {
      const template =
          '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT]'
          '[TOOL_CALLS]get_weather[ARGS]{}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.auto,
      );

      expect(result.format, equals(ChatFormat.ministral.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isTrue);
      expect(result.parser, isNotNull);
      expect(result.parser, isNotEmpty);
    });

    test('parses Ministral output through PEG parser payload', () {
      const template =
          '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT]'
          '[TOOL_CALLS]get_weather[ARGS]{}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.auto,
      );

      final parsed = ChatTemplateEngine.parse(
        result.format,
        '[THINK]t[/THINK]'
        '[TOOL_CALLS]get_weather[ARGS]{"location":"Seoul"}',
        parser: result.parser,
      );

      expect(parsed.reasoningContent, equals('t'));
      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        parsed.toolCalls.first.function?.arguments,
        equals('{"location":"Seoul"}'),
      );
    });

    test('Ministral tool_choice none keeps parser in content mode', () {
      const template =
          '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT]'
          '[TOOL_CALLS]get_weather[ARGS]{}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.none,
      );

      final parsed = ChatTemplateEngine.parse(
        result.format,
        '[TOOL_CALLS]get_weather[ARGS]{"location":"Seoul"}',
        parser: result.parser,
      );

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, contains('[TOOL_CALLS]'));
      expect(parsed.content, contains('get_weather[ARGS]'));
    });

    test('Ministral parser respects required/parallel bounds', () {
      const template =
          '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT]'
          '[TOOL_CALLS]get_weather[ARGS]{}';
      const templateParallel =
          '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT]'
          '[TOOL_CALLS]get_weather[ARGS]{}'
          '{% if tools %}{% for tool in tools %}{{ tool["function"]["name"] }}{% endfor %}{% endif %}';

      int maxCallsFromParser(String parser) {
        final decoded = jsonDecode(parser) as Map<String, dynamic>;
        final parsers = (decoded['parsers'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final toolCallRoot = parsers.firstWhere(
          (node) => node['type'] == 'rule' && node['name'] == 'tool-call',
        );
        final repetition = parsers[(toolCallRoot['child'] as num).toInt()];
        return (repetition['max_count'] as num).toInt();
      }

      int minCallsFromParser(String parser) {
        final decoded = jsonDecode(parser) as Map<String, dynamic>;
        final parsers = (decoded['parsers'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final toolCallRoot = parsers.firstWhere(
          (node) => node['type'] == 'rule' && node['name'] == 'tool-call',
        );
        final repetition = parsers[(toolCallRoot['child'] as num).toInt()];
        return (repetition['min_count'] as num).toInt();
      }

      final autoSingle = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.auto,
      );
      expect(minCallsFromParser(autoSingle.parser!), equals(0));
      expect(maxCallsFromParser(autoSingle.parser!), equals(1));

      final autoParallel = ChatTemplateEngine.render(
        templateSource: templateParallel,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.auto,
        parallelToolCalls: true,
      );
      expect(minCallsFromParser(autoParallel.parser!), equals(0));
      // Parallel stays disabled unless template capability detection
      // confirms tool-call list emission support.
      expect(maxCallsFromParser(autoParallel.parser!), equals(1));

      final requiredSingle = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );
      expect(minCallsFromParser(requiredSingle.parser!), equals(1));
      expect(maxCallsFromParser(requiredSingle.parser!), equals(1));
    });

    test('routes Nemotron v3 templates to PEG-constructed parser path', () {
      const template =
          '{% set truncate_history_thinking = true %}'
          '<tool_call><function><function=get_weather><parameters>'
          '<parameter=city><think>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.auto,
      );

      expect(result.format, equals(ChatFormat.pegConstructed.index));
      expect(result.parser, isNotNull);
      expect(result.parser, isNotEmpty);
      expect(result.grammarTriggers, hasLength(1));
      expect(result.grammarTriggers.first.value, equals('<tool_call>'));

      final parsed = ChatTemplateEngine.parse(
        result.format,
        'I am thinking\n'
        '</think>\n'
        '<tool_call>\n'
        '<function=get_weather>\n'
        '<parameter=city>\n'
        'Seoul\n'
        '</parameter>\n'
        '</function>\n'
        '</tool_call>',
        parser: result.parser,
        thinkingForcedOpen: result.thinkingForcedOpen,
      );

      expect(parsed.reasoningContent, equals('I am thinking'));
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        parsed.toolCalls.first.function?.arguments,
        equals('{"city":"Seoul"}'),
      );
    });

    test('Nemotron v3 tool_choice none uses content-only parser behavior', () {
      const template =
          '{% set truncate_history_thinking = true %}'
          '<tool_call><function><function=get_weather><parameters>'
          '<parameter=city><think>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.none,
      );

      expect(result.format, equals(ChatFormat.pegConstructed.index));
      expect(result.parser, isNotNull);
      expect(result.parser, isNotEmpty);
      expect(result.grammar, isNull);
      expect(result.grammarLazy, isFalse);
      expect(result.grammarTriggers, isEmpty);

      final parsed = ChatTemplateEngine.parse(
        result.format,
        'I am thinking\n'
        '</think>\n'
        '<tool_call>\n'
        '<function=get_weather>\n'
        '<parameter=city>\n'
        'Seoul\n'
        '</parameter>\n'
        '</function>\n'
        '</tool_call>',
        parser: result.parser,
        thinkingForcedOpen: result.thinkingForcedOpen,
      );

      expect(parsed.reasoningContent, equals('I am thinking'));
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, contains('<tool_call>'));
      expect(parsed.content, contains('<function=get_weather>'));
    });

    test('Nemotron v3 parser respects required/parallel tool call bounds', () {
      const template =
          '{% set truncate_history_thinking = true %}'
          '<tool_call><function><function=get_weather><parameters>'
          '<parameter=city><think>';
      const templateParallel =
          '{% set truncate_history_thinking = true %}'
          '<tool_call><function><function=get_weather><parameters>'
          '<parameter=city><think>'
          '{% if tools %}{% for tool in tools %}'
          '{{ tool["function"]["name"] }}'
          '{% endfor %}{% endif %}';

      int maxCallsFromParser(String parser) {
        final decoded = jsonDecode(parser) as Map<String, dynamic>;
        final parsers = (decoded['parsers'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final toolCallRoot = parsers.firstWhere(
          (node) => node['type'] == 'rule' && node['name'] == 'tool-call-root',
        );
        final repetition = parsers[(toolCallRoot['child'] as num).toInt()];
        return (repetition['max_count'] as num).toInt();
      }

      int minCallsFromParser(String parser) {
        final decoded = jsonDecode(parser) as Map<String, dynamic>;
        final parsers = (decoded['parsers'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final toolCallRoot = parsers.firstWhere(
          (node) => node['type'] == 'rule' && node['name'] == 'tool-call-root',
        );
        final repetition = parsers[(toolCallRoot['child'] as num).toInt()];
        return (repetition['min_count'] as num).toInt();
      }

      final autoSingle = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.auto,
      );
      expect(minCallsFromParser(autoSingle.parser!), equals(0));
      expect(maxCallsFromParser(autoSingle.parser!), equals(1));

      final autoParallel = ChatTemplateEngine.render(
        templateSource: templateParallel,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.auto,
        parallelToolCalls: true,
      );
      expect(minCallsFromParser(autoParallel.parser!), equals(0));
      // Parallel stays disabled unless template capability detection
      // confirms tool-call list emission support.
      expect(maxCallsFromParser(autoParallel.parser!), equals(1));

      final requiredSingle = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );
      expect(minCallsFromParser(requiredSingle.parser!), equals(1));
      expect(maxCallsFromParser(requiredSingle.parser!), equals(1));
    });

    test('keeps Ministral handler but strips grammar for tool_choice none', () {
      const template =
          '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT]'
          '[TOOL_CALLS]get_weather[ARGS]{}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.none,
      );

      expect(result.format, equals(ChatFormat.ministral.index));
      expect(result.grammar, isNull);
      expect(result.grammarLazy, isFalse);
      expect(result.grammarTriggers, isEmpty);
      expect(result.preservedTokens, contains('[TOOL_CALLS]'));
      expect(result.preservedTokens, contains('[ARGS]'));
    });

    test('keeps generic routing for LFM2 required tool choice', () {
      const template =
          '{%- set keep_past_thinking = true -%}\n'
          '<|im_start|>system\n{{ messages[0]["content"] }}<|im_end|>'
          '<|im_start|>user\n{{ messages[1]["content"] }}<|im_end|>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.system,
            text: 'force json schema.\nSystem prompt',
          ),
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'ping'),
        ],
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );

      expect(result.format, equals(ChatFormat.generic.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isFalse);
    });

    test('keeps lazy grammar for formats that always use lazy mode', () {
      const template =
          '<|system_start|>{{ messages[0]["content"] }}<|system_end|><|tools_prefix|>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );

      expect(result.format, equals(ChatFormat.apertus.index));
      expect(result.grammar, isNotNull);
      expect(result.grammarLazy, isTrue);
    });

    test('routes unknown templates with tools to generic handler', () {
      const template = '{{ messages[0]["content"] }}';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
      );

      expect(result.format, equals(ChatFormat.generic.index));
      expect(result.grammar, isNotNull);
    });
  });
}

int _mediaPlaceholderCount(String prompt) {
  return '<__media__>'.allMatches(prompt).length;
}

const _actualGlmOcrTemplate = r'''[gMASK]<sop>
{%- if tools -%}
<|system|>
# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
{% for tool in tools %}
{{ tool | tojson(ensure_ascii=False) }}
{% endfor %}
</tools>

For each function call, output the function name and arguments within the following XML format:
<tool_call>{function-name}
<arg_key>{arg-key-1}</arg_key>
<arg_value>{arg-value-1}</arg_value>
<arg_key>{arg-key-2}</arg_key>
<arg_value>{arg-value-2}</arg_value>
...
</tool_call>{%- endif -%}
{%- macro visible_text(content) -%}
    {%- if content is string -%}
        {{- content }}
    {%- elif content is iterable and content is not mapping -%}
        {%- for item in content -%}
            {%- if item is mapping and item.type == 'text' -%}
                {{- item.text }}
            {%- elif item is mapping and (item.type == 'image' or 'image' in item) -%}
                <|begin_of_image|><|image|><|end_of_image|>
            {%- elif item is mapping and (item.type == 'video' or 'video' in item) -%}
                <|begin_of_video|><|video|><|end_of_video|>
            {%- elif item is string -%}
                {{- item }}
            {%- endif -%}
        {%- endfor -%}
    {%- else -%}
        {{- content }}
    {%- endif -%}
{%- endmacro -%}
{%- set ns = namespace(last_user_index=-1) %}
{%- for m in messages %}
    {%- if m.role == 'user' %}
        {% set ns.last_user_index = loop.index0 -%}
    {%- endif %}
{%- endfor %}
{% for m in messages %}
{%- if m.role == 'user' -%}<|user|>
{% if m.content is string %}
{{ m.content }}
{%- else %}
{%- for item in m.content %}
{% if item.type == 'video' or 'video' in item %}
<|begin_of_video|><|video|><|end_of_video|>{% elif item.type == 'image' or 'image' in item %}
<|begin_of_image|><|image|><|end_of_image|>{% elif item.type == 'text' %}
{{ item.text }}
{%- endif %}
{%- endfor %}
{%- endif %}
{{- '/nothink' if (enable_thinking is defined and not enable_thinking and not visible_text(m.content).endswith("/nothink")) else '' -}}
{%- elif m.role == 'assistant' -%}
<|assistant|>
{%- set reasoning_content = '' %}
{%- set content = visible_text(m.content) %}
{%- if m.reasoning_content is string %}
    {%- set reasoning_content = m.reasoning_content %}
{%- else %}
    {%- if '</think>' in content %}
        {%- set reasoning_content = content.split('</think>')[0].rstrip('\n').split('<think>')[-1].lstrip('\n') %}
        {%- set content = content.split('</think>')[-1].lstrip('\n') %}
    {%- endif %}
{%- endif %}
{%- if loop.index0 > ns.last_user_index and reasoning_content -%}
{{ '\n<think>' + reasoning_content.strip() +  '</think>'}}
{%- else -%}
{{ '\n<think></think>' }}
{%- endif -%}
{%- if content.strip() -%}
{{ '\n' + content.strip() }}
{%- endif -%}
{% if m.tool_calls %}
{% for tc in m.tool_calls %}
{%- if tc.function %}
    {%- set tc = tc.function %}
{%- endif %}
{{ '\n<tool_call>' + tc.name }}
{% set _args = tc.arguments %}
{% for k, v in _args.items() %}
<arg_key>{{ k }}</arg_key>
<arg_value>{{ v | tojson(ensure_ascii=False) if v is not string else v }}</arg_value>
{% endfor %}
</tool_call>{% endfor %}
{% endif %}
{%- elif m.role == 'tool' -%}
{%- if m.content is string -%}
{%- if loop.first or (messages[loop.index0 - 1].role != "tool") %}
    {{- '<|observation|>' }}
{%- endif %}
{{- '\n<tool_response>\n' }}
{{- m.content }}
{{- '\n</tool_response>' }}
{% elif m.content is iterable and m.content is not mapping %}
{%- if loop.first or (messages[loop.index0 - 1].role != "tool") %}
{{- '<|observation|>' }}
{%- endif %}
{{- '\n<tool_response>\n' }}
{%- for tr in m.content -%}
  {%- if tr is mapping and tr.type is defined -%}
    {%- set t = tr.type | lower -%}
    {%- if t == 'text' and tr.text is defined -%}
{{ tr.text }}
    {%- elif t in ['image', 'image_url'] -%}
<|begin_of_image|><|image|><|end_of_image|>
    {%- elif t in ['video', 'video_url'] -%}
<|begin_of_video|><|video|><|end_of_video|>
    {%- else -%}
{{ tr | tojson(ensure_ascii=False) }}
    {%- endif -%}
  {%- else -%}
{{ tr.output if tr.output is defined else tr }}
  {%- endif -%}
{%- endfor -%}
{{- '\n</tool_response>' }}
{%- else -%}
<|observation|>{% for tr in m.content %}

<tool_response>
{{ tr.output if tr.output is defined else tr }}
</tool_response>{% endfor -%}
{% endif -%}
{%- elif m.role == 'system' -%}
<|system|>
{{ visible_text(m.content) }}
{%- endif -%}
{%- endfor -%}
{%- if add_generation_prompt -%}
<|assistant|>
{{'<think></think>\n' if (enable_thinking is defined and not enable_thinking) else ''}}
{%- endif -%}''';

void _expectToolCallSerialization(
  TemplateToolCallSerialization actual,
  TemplateToolCallSerialization expected, {
  String? reason,
}) {
  expect(
    actual.normalizeArguments,
    equals(expected.normalizeArguments),
    reason: reason,
  );
  expect(
    actual.useGenericSchema,
    equals(expected.useGenericSchema),
    reason: reason,
  );
  expect(
    actual.moveToolCallsToContent,
    equals(expected.moveToolCallsToContent),
    reason: reason,
  );
}

Future<Object?> _noopHandler(_) async {
  return 'ok';
}
