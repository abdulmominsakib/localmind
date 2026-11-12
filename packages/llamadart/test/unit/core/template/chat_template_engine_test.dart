import 'dart:convert';
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
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:llamadart/src/core/template/template_render_context.dart';
import 'package:test/test.dart';

void main() {
  const baseTemplate = '{{ "BASE:" ~ messages[0]["content"] }}';
  const customTemplate = '{{ "CUSTOM:" ~ messages[0]["content"] }}';

  final messages = [const LlamaChatMessage(role: 'user', content: 'hello')];

  group('Ministral terminal reasoning', () {
    const template = '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT][TOOL_CALLS][ARGS]';
    final tool = ToolDefinition(
      name: 'weather',
      description: 'Weather',
      parameters: [],
    );

    for (final choice in ToolChoice.values) {
      final rendered = ChatTemplateEngine.render(
        templateSource: template,
        messages: messages,
        metadata: const {},
        tools: [tool],
        toolChoice: choice,
      );

      for (final suffix in ['', '[/TH']) {
        test('${choice.name} preserves terminal thought policy $suffix', () {
          if (choice == ToolChoice.required) {
            expect(
              () => ChatTemplateEngine.parse(
                rendered.format,
                '[THINK]Check the city.$suffix',
                parser: rendered.parser,
              ),
              throwsA(isA<LlamaInferenceException>()),
            );
            return;
          }
          final parsed = ChatTemplateEngine.parse(
            rendered.format,
            '[THINK]Check the city.$suffix',
            parser: rendered.parser,
          );
          expect(parsed.reasoningContent, 'Check the city.');
          expect(parsed.content, isEmpty);
          expect(parsed.toolCalls, isEmpty);
        });
      }

      if (choice != ToolChoice.none) {
        test('${choice.name} preserves a call after an unclosed thought', () {
          final parsed = ChatTemplateEngine.parse(
            rendered.format,
            '[THINK]a[TOOL_CALLS]weather[ARGS]{"city":"x"}',
            parser: rendered.parser,
          );
          expect(parsed.content, '[THINK]a');
          expect(parsed.reasoningContent, isNull);
          final call = parsed.toolCalls.single;
          expect(call.function?.name, 'weather');
          expect(call.function?.arguments, '{"city":"x"}');
        });
      }

      if (choice != ToolChoice.required) {
        test('${choice.name} keeps a leading-space thought as content', () {
          final parsed = ChatTemplateEngine.parse(
            rendered.format,
            ' [THINK]a',
            parser: rendered.parser,
          );
          expect(parsed.content, ' [THINK]a');
          expect(parsed.reasoningContent, isNull);
          expect(parsed.toolCalls, isEmpty);
        });

        test('${choice.name} preserves a completed thought and answer', () {
          final parsed = ChatTemplateEngine.parse(
            rendered.format,
            '[THINK]Check.[/THINK]Answer [THINK]literally. \n',
            parser: rendered.parser,
          );
          expect(parsed.reasoningContent, 'Check.');
          expect(parsed.content, 'Answer [THINK]literally. \n');
          expect(parsed.toolCalls, isEmpty);
        });
      } else {
        for (final output in [
          'Answer [THINK]literally.',
          '[THINK]a[/THINK]',
          '[THINK]Check.[/THINK][TOOL_CALLS]weather[ARGS]{',
        ]) {
          test('required still rejects malformed completed output $output', () {
            expect(
              () => ChatTemplateEngine.parse(
                rendered.format,
                output,
                parser: rendered.parser,
              ),
              throwsA(isA<LlamaInferenceException>()),
            );
          });
        }
      }
    }

    test('other PEG formats retain their terminal parsing policy', () {
      final rendered = ChatTemplateEngine.render(
        templateSource: template,
        messages: messages,
        metadata: const {},
      );
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.pegNative.index,
        '[THINK]Check.',
        parser: rendered.parser,
      );
      expect(parsed.content, '[THINK]Check.');
      expect(parsed.reasoningContent, isNull);
    });
  });

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

        expect(enabled.prompt, contains('look<__media__><|im_end|>'));
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

    test('every template gets the resolved enable_thinking', () {
      const template =
          '{{ enable_thinking | tojson }}{{ thinking | default("-") }}';
      String render(bool enableThinking, [Map<String, dynamic>? kwargs]) =>
          ChatTemplateEngine.render(
            templateSource: template,
            messages: messages,
            metadata: const {},
            enableThinking: enableThinking,
            chatTemplateKwargs: kwargs,
          ).prompt;

      expect(render(true), 'true-');
      expect(render(false), 'false-');
      expect(render(true, {'enable_thinking': false}), 'false-');
      expect(render(true, {'thinking': false}), 'falseFalse');
      expect(render(false, {'enable_thinking': 'yes'}), 'false-');
    });

    group('a thought the template opens', () {
      const template =
          '{%- for message in messages -%}'
          '{%- for part in message.content -%}{{ part.text }}{%- endfor -%}'
          '{%- endfor -%}'
          '<think>';
      const schema = {
        'type': 'json_schema',
        'json_schema': {
          'schema': {
            'type': 'object',
            'properties': {
              'answer': {'type': 'integer'},
            },
            'required': ['answer'],
          },
        },
      };
      final tool = ToolDefinition(
        name: 'get_weather',
        description: 'Weather',
        parameters: [ToolParam.string('location', required: true)],
      );
      List<LlamaChatMessage> request({required bool media}) => [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            if (media) const LlamaImageContent(path: '/tmp/photo.png'),
            const LlamaTextContent('look'),
          ],
        ),
      ];

      for (final media in [false, true]) {
        final kind = media ? 'media' : 'text';
        for (final enableThinking in [true, false]) {
          test('stays open and forced open in a $kind request with '
              'enableThinking: $enableThinking', () {
            final result = ChatTemplateEngine.render(
              templateSource: template,
              messages: request(media: media),
              metadata: const {},
              enableThinking: enableThinking,
            );
            expect(result.prompt, '${media ? '<__media__>' : ''}look<think>');
            expect(result.thinkingForcedOpen, isTrue);
          });
        }

        test('finishes before the response format in a $kind request', () {
          final result = ChatTemplateEngine.render(
            templateSource: template,
            messages: request(media: media),
            metadata: const {},
            responseFormat: schema,
          );
          expect(result.thinkingForcedOpen, isTrue);
          expect(result.grammarLazy, isFalse);
          expect(
            result.grammar,
            startsWith('root ::= think-body "</think>" think-space ('),
          );

          final parsed = ChatTemplateEngine.parse(
            result.format,
            'plan</think>{"answer": 4}',
            thinkingForcedOpen: result.thinkingForcedOpen,
          );
          expect(parsed.reasoningContent, 'plan');
          expect(parsed.content, '{"answer": 4}');
        });

        test('finishes before a generic tool call in a $kind request', () {
          final result = ChatTemplateEngine.render(
            templateSource: template,
            messages: request(media: media),
            metadata: const {},
            tools: [tool],
          );
          expect(result.format, ChatFormat.generic.index);
          expect(result.thinkingForcedOpen, isTrue);
          expect(result.grammarLazy, isFalse);
          expect(
            result.grammar,
            startsWith('root ::= think-body "</think>" think-space ('),
          );

          final parsed = ChatTemplateEngine.parse(
            result.format,
            'plan</think>{"tool_call": {"name": "get_weather", '
            '"arguments": {"location": "Paris"}}}',
            thinkingForcedOpen: result.thinkingForcedOpen,
            tools: [tool],
          );
          expect(parsed.reasoningContent, 'plan');
          expect(parsed.toolCalls.map((call) => call.function?.name), [
            'get_weather',
          ]);
        });
      }
    });

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
        ChatFormat.kimiK3: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.minimaxM1: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.minimaxM3: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.deepseekV4: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.deepseekV32: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.museGlimmer: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.laguna: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.ling3: TemplateToolCallSerialization.normalizeOnly,
        ChatFormat.gemma4: TemplateToolCallSerialization.normalizeOnly,
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

    group('every handler renders one tool message per tool result', () {
      // The comment keeps Gemma 4 on OpenAI-style tool messages.
      const template =
          '{#- OpenAI Chat Completions: #}{% for m in messages %}'
          '<{{ m.role }}>{{ m.content }}</{{ m.role }}>{% endfor %}';
      const history = [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Paris?'),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            LlamaToolCallContent(
              id: 'call_0',
              name: 'get_weather',
              arguments: {'city': 'Paris'},
              rawJson: '{"city":"Paris"}',
            ),
            LlamaToolCallContent(
              id: 'call_1',
              name: 'get_time',
              arguments: {'city': 'Paris'},
              rawJson: '{"city":"Paris"}',
            ),
          ],
        ),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(
              id: 'call_0',
              name: 'get_weather',
              result: 'RESULT_ONE',
            ),
            LlamaToolResultContent(
              id: 'call_1',
              name: 'get_time',
              result: {'value': 'RESULT_TWO'},
            ),
          ],
        ),
      ];

      for (final format in ChatFormat.values) {
        test('$format', () {
          final handler = ChatTemplateEngine.handlerFor(format);
          final prompts = {
            'render': handler
                .render(
                  templateSource: template,
                  messages: history,
                  metadata: const {},
                )
                .prompt,
            'renderWithMultimodalContent': handler
                .renderWithMultimodalContent(
                  templateSource: template,
                  messages: history,
                  metadata: const {},
                )
                .prompt,
          };
          for (final MapEntry(key: path, value: prompt) in prompts.entries) {
            expect(
              prompt,
              matches(
                '<tool>[^<]*RESULT_ONE[^<]*</tool>'
                '<tool>[^<]*RESULT_TWO[^<]*</tool>',
              ),
              reason: path,
            );
          }
        });
      }
    });

    test(
      'renders a GLM-OCR image as the marker without the template wrappers',
      () {
        const template = '''[gMASK]<sop>
{# GLM detection marker: <arg_key>name</arg_key><arg_value>value</arg_value> #}
{% for m in messages %}
{% if m.role == 'user' %}<|user|>
{% if m.content is string %}{{ m.content }}{% else %}
{% for item in m.content %}
{% if item.type == 'image' %}<|begin_of_image|><|image|><|end_of_image|>{% elif item.type == 'text' %}{{ item.text }}{% endif %}
{% endfor %}
{% endif %}
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
        expect(result.prompt, contains('<__media__>Extract text.'));
        expect(result.prompt, isNot(contains('<|begin_of_image|>')));
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

    test('gives a template the media marker where each image was, whatever '
        'placeholder the template writes for a typed image part', () {
      const template =
          '{% for message in messages %}<{{ message.role }}>'
          '{% if message.content is string %}{{ message.content }}'
          '{% else %}{% for part in message.content %}'
          "{% if part.type == 'image' %}"
          'Picture {{ loop.index }}: [own image placeholder]'
          '{% else %}{{ part.text }}{% endif %}'
          '{% endfor %}{% endif %}'
          '{% endfor %}';
      const image = LlamaImageContent(path: '/tmp/page.png');

      String prompt(List<LlamaChatMessage> messages) =>
          ChatTemplateEngine.render(
            templateSource: template,
            messages: messages,
            metadata: const {},
            addAssistant: false,
          ).prompt;

      expect(
        prompt(const [
          LlamaChatMessage.fromText(role: LlamaChatRole.system, text: 'sys'),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [image, LlamaTextContent('What is this?')],
          ),
        ]),
        '<system>sys<user><__media__>What is this?',
      );
      expect(
        prompt(const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: 'Yes?',
          ),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaTextContent('First:'),
              image,
              LlamaTextContent('Second:'),
              image,
            ],
          ),
        ]),
        '<user>Hi<assistant>Yes?<user>First:<__media__>Second:<__media__>',
      );
    });

    for (final (name, template) in const [
      (
        'a string or a part list',
        '{% for message in messages %}'
            '{% if message.content is string %}{{ message.content }}'
            '{% else %}{% for part in message.content %}{{ part.text }}'
            '{% endfor %}{% endif %}{% endfor %}',
      ),
      (
        'a string',
        '{% for message in messages %}{{ message.content }}{% endfor %}',
      ),
    ]) {
      test('leaves a placeholder a message quotes as text for a template '
          'that reads content as $name', () {
        const quoted =
            'Is <img>, <image>, [IMG], <|image_1|> or <start_of_image> a '
            'tag, and what is <__media__>?';
        String prompt([String? marker]) => ChatTemplateEngine.render(
          templateSource: template,
          messages: const [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [
                LlamaImageContent(path: '/tmp/page.png'),
                LlamaTextContent(quoted),
              ],
            ),
          ],
          metadata: const {},
          addAssistant: false,
          mediaMarker: marker ?? '<__media__>',
        ).prompt;

        expect(prompt(), '<__media__>$quoted');
        expect(prompt('<__media_x__>'), '<__media_x__>$quoted');
      });
    }

    test('renders a video part as the media marker without leaking its '
        'source', () {
      final result = ChatTemplateEngine.render(
        templateSource:
            '{% for message in messages %}'
            '{{ message.role }}: {{ message.content }}\n'
            '{% endfor %}',
        messages: [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              const LlamaTextContent('Describe:'),
              LlamaVideoContent(path: '/tmp/clip.mp4'),
            ],
          ),
        ],
        metadata: const {},
      );

      expect(result.prompt, 'user: Describe:<__media__>\n');
    });

    test('gives the media marker in text to a template that reads part '
        'lists but rejects media parts', () {
      const textParts =
          '{% for message in messages %}'
          '{% if message.content is string %}{{ message.content }}'
          '{% else %}{% for part in message.content %}'
          "{% if part.type == 'text' %}{{ part.text }}"
          "{% else %}{{ raise_exception('text parts only') }}{% endif %}"
          '{% endfor %}{% endif %}'
          '{% endfor %}';

      for (final media in <LlamaContentPart>[
        const LlamaImageContent(path: '/tmp/page.png'),
        const LlamaAudioContent(path: '/tmp/clip.wav'),
      ]) {
        final result = ChatTemplateEngine.render(
          templateSource: textParts,
          messages: [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [const LlamaTextContent('Describe:'), media],
            ),
          ],
          metadata: const {},
        );

        expect(result.prompt, 'Describe:<__media__>');
      }
    });

    group('a chat template that fails to render', () {
      const mustAlternate =
          '{% for message in messages %}'
          '{% if loop.index0 > 0 and '
          'message.role == messages[loop.index0 - 1].role %}'
          "{{ raise_exception('Conversation roles must alternate') }}"
          '{% endif %}{{ message.content }}'
          '{% endfor %}';
      const twoUserTurns = [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'a'),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'b'),
      ];

      Matcher throwsRenderFailure(Object message) => throwsA(
        isA<LlamaInferenceException>().having(
          (e) => e.message,
          'message',
          message,
        ),
      );

      test('throws a typed exception carrying what the template raised', () {
        expect(
          () => ChatTemplateEngine.render(
            templateSource: mustAlternate,
            messages: twoUserTurns,
            metadata: const {},
          ),
          throwsRenderFailure(
            'The chat template from templateSource failed to render: '
            'Conversation roles must alternate',
          ),
        );
      });

      test('throws a typed exception when it raises in a request with '
          'media', () {
        // Reads strings and part lists, so a request with media takes the
        // other handler call.
        const alternatingPartLists =
            '{% for message in messages %}'
            '{% if loop.index0 > 0 and '
            'message.role == messages[loop.index0 - 1].role %}'
            "{{ raise_exception('Conversation roles must alternate') }}"
            '{% endif %}'
            '{% if message.content is string %}{{ message.content }}'
            '{% else %}{% for part in message.content %}{{ part.text }}'
            '{% endfor %}{% endif %}'
            '{% endfor %}';
        const image = LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaTextContent('Describe:'),
            LlamaImageContent(path: '/tmp/page.png'),
          ],
        );

        expect(
          ChatTemplateEngine.render(
            templateSource: alternatingPartLists,
            messages: const [image],
            metadata: const {},
          ).prompt,
          'Describe:<__media__>',
        );
        expect(
          () => ChatTemplateEngine.render(
            templateSource: alternatingPartLists,
            messages: const [image, image],
            metadata: const {},
          ),
          throwsRenderFailure(
            'The chat template from templateSource failed to render: '
            'Conversation roles must alternate',
          ),
        );
      });

      test('throws a typed exception for invalid template syntax', () {
        expect(
          () => ChatTemplateEngine.render(
            templateSource: '{% for message in messages %}{{ message.content',
            messages: twoUserTurns,
            metadata: const {},
          ),
          throwsRenderFailure(
            startsWith(
              'The chat template from templateSource failed to render: '
              'ParserException',
            ),
          ),
        );
      });

      const recursiveTemplate =
          '{% macro recurse() %}{{ recurse() }}{% endmacro %}'
          '{% if messages[0].content == "overflow" %}{{ recurse() }}'
          '{% else %}{{ messages[0].content }}{% endif %}';

      // Stack overflow cannot be caught on dart2wasm.
      test('wraps render stack overflow and preserves its original stack', () {
        try {
          ChatTemplateEngine.render(
            templateSource: recursiveTemplate,
            messages: const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'overflow',
              ),
            ],
            metadata: const {},
          );
          fail('The recursive template must fail to render');
        } on LlamaInferenceException catch (error, stackTrace) {
          expect(error.message, contains('templateSource failed to render'));
          expect(error.message, contains('Stack Overflow'));
          expect(stackTrace.toString(), contains('MacroStatement'));
        }
      }, testOn: '!dart2wasm');

      // Stack overflow cannot be caught on dart2wasm.
      test('does not retry a tool-role stack overflow as a user turn', () {
        const template =
            '{% macro recurse() %}{{ recurse() }}{% endmacro %}'
            '{% for message in messages %}'
            '{% if message.role == "tool" %}{{ recurse() }}'
            '{% else %}{{ message.content }}{% endif %}'
            '{% endfor %}';

        // A user-turn retry would succeed and hide the original overflow.
        expect(
          ChatTemplateEngine.render(
            templateSource: template,
            messages: const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'ok'),
            ],
            metadata: const {},
          ).prompt,
          'ok',
        );
        expect(
          () => ChatTemplateEngine.render(
            templateSource: template,
            messages: const [
              LlamaChatMessage.withContent(
                role: LlamaChatRole.tool,
                content: [
                  LlamaToolResultContent(
                    id: 'call1',
                    name: 'inspect',
                    result: 'ok',
                  ),
                ],
              ),
            ],
            metadata: const {},
          ),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              allOf(contains('templateSource'), contains('Stack Overflow')),
            ),
          ),
        );
      }, testOn: '!dart2wasm');

      test('keeps successful recursive-template renders unchanged', () {
        expect(
          ChatTemplateEngine.render(
            templateSource: recursiveTemplate,
            messages: messages,
            metadata: const {},
          ).prompt,
          'hello',
        );
      });

      test('leaves unrelated render errors unchanged', () {
        expect(
          () => ChatTemplateEngine.render(
            templateSource: '{{ 1 // 0 }}',
            messages: messages,
            metadata: const {},
          ),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('renders the conversation it accepts', () {
        final result = ChatTemplateEngine.render(
          templateSource: mustAlternate,
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'a'),
            LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: 'b'),
          ],
          metadata: const {},
        );

        expect(result.prompt, 'ab');
      });
    });

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

    test('direct-Jinja auto required and none preserve reasoning prefixes', () {
      const templates = <ChatFormat, String>{
        ChatFormat.kimiK3:
            '{# <|open|> <|close|> <|end_of_msg|> #}'
            '{{ "<|open|>think<|sep|>" }}',
        ChatFormat.minimaxM3:
            '{# ]<]minimax[>[ <tool_call> <invoke name= #}'
            '{{ "<mm:think>" }}',
        ChatFormat.deepseekV32:
            '{# dsml_token DSML function_calls #}{{ "<think>" }}',
        ChatFormat.deepseekV4:
            '{# dsml_token DSML tool_calls #}{{ "<think>" }}',
        ChatFormat.museGlimmer:
            '{# <atem:function_calls> <|eom|> #}'
            '{{ "<|start|>assistant" }}',
        ChatFormat.laguna:
            '{# <assistant> </assistant> <tool_response> '
            '<arg_key> <arg_value> #}{{ "<think>" }}',
      };

      for (final entry in templates.entries) {
        for (final enableThinking in [true, false]) {
          final auto = ChatTemplateEngine.render(
            templateSource: entry.value,
            messages: grammarMessages,
            metadata: const {},
            tools: tools,
            toolChoice: ToolChoice.auto,
            enableThinking: enableThinking,
          );
          expect(auto.format, entry.key.index, reason: '${entry.key} auto');
          expect(auto.grammar, isNotNull, reason: '${entry.key} auto');
          expect(auto.grammarLazy, isTrue, reason: '${entry.key} auto');

          final required = ChatTemplateEngine.render(
            templateSource: entry.value,
            messages: grammarMessages,
            metadata: const {},
            tools: tools,
            toolChoice: ToolChoice.required,
            enableThinking: enableThinking,
          );
          expect(
            required.format,
            entry.key.index,
            reason: '${entry.key} required',
          );
          expect(required.grammar, isNotNull, reason: '${entry.key} required');
          expect(
            required.grammarLazy,
            isFalse,
            reason: '${entry.key} required',
          );
          expect(
            required.grammarTriggers,
            isEmpty,
            reason: '${entry.key} required',
          );
          expect(
            required.grammar!.split('\n').first,
            contains('required'),
            reason: '${entry.key} required',
          );

          final none = ChatTemplateEngine.render(
            templateSource: entry.value,
            messages: grammarMessages,
            metadata: const {},
            tools: tools,
            toolChoice: ToolChoice.none,
            enableThinking: enableThinking,
          );
          expect(none.grammar, isNull, reason: '${entry.key} none');
          expect(none.grammarLazy, isFalse, reason: '${entry.key} none');
        }
      }
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

    test('honors parallelToolCalls on LFM2 templates that omit tool_calls', () {
      const template =
          'List of tools: <|tool_list_start|>[{"name":"x"}]<|tool_list_end|>'
          '{% for message in messages %}{{ message["content"] }}{% endfor %}';
      expect(TemplateCaps.detect(template).supportsParallelToolCalls, isFalse);

      String? grammar({required bool parallel}) => ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
        parallelToolCalls: parallel,
      ).grammar;

      expect(grammar(parallel: true), isNot(grammar(parallel: false)));
    });

    test('honors explicit parallelToolCalls when Qwen caps deny it', () {
      const template =
          '{# <tool_call> <function= <parameter= '
          'Function calls MUST follow the specified format #}'
          '{% for message in messages %}{{ message.content }}{% endfor %}';
      expect(TemplateCaps.detect(template).supportsParallelToolCalls, isFalse);

      String? grammar({required bool parallel}) => ChatTemplateEngine.render(
        templateSource: template,
        messages: grammarMessages,
        metadata: const {},
        tools: tools,
        toolChoice: ToolChoice.required,
        parallelToolCalls: parallel,
      ).grammar;

      expect(grammar(parallel: true), isNot(grammar(parallel: false)));
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
      expect(maxCallsFromParser(autoParallel.parser!), equals(-1));

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

    // llama.cpp (`cd959bae9`) parses Nemotron-3-Nano with its Qwen3-Coder
    // parser, where `<tool_call>` also ends a forced-open thought.
    test('routes Nemotron v3 templates to the Qwen3-Coder XML parser', () {
      const template =
          '{% set truncate_history_thinking = true %}'
          '<tool_call><function><function=get_weather><parameters>'
          '<parameter=city><think>'
          '{% if add_generation_prompt %}<think>\n{% endif %}';

      for (final toolChoice in [ToolChoice.auto, ToolChoice.required]) {
        final result = ChatTemplateEngine.render(
          templateSource: template,
          messages: grammarMessages,
          metadata: const {},
          tools: tools,
          toolChoice: toolChoice,
        );

        expect(result.format, equals(ChatFormat.qwen3CoderXml.index));
        expect(result.parser, isNull);
        expect(result.thinkingForcedOpen, isTrue);
        final parsed = ChatTemplateEngine.parseRendered(
          result,
          'I am thinking\n'
          '<tool_call>\n'
          '<function=get_weather>\n'
          '<parameter=city>\n'
          'Seoul\n'
          '</parameter>\n'
          '</function>\n'
          '</tool_call>',
          tools: tools,
        );

        expect(parsed.reasoningContent, equals('I am thinking'));
        expect(parsed.toolCalls, hasLength(1));
        expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
        expect(
          parsed.toolCalls.first.function?.arguments,
          equals('{"city":"Seoul"}'),
        );
      }
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

  group('ChatTemplateEngine tool results for a template without the tool '
      'role', () {
    // llama.cpp models/templates/google-gemma-2-2b-it.jinja, inline so the
    // test runs on Chrome as well.
    const gemma2 =
        "{{ bos_token }}{% if messages[0]['role'] == 'system' %}"
        "{{ raise_exception('System role not supported') }}{% endif %}"
        "{% for message in messages %}"
        "{% if (message['role'] == 'user') != (loop.index0 % 2 == 0) %}"
        "{{ raise_exception('Conversation roles must alternate "
        "user/assistant/user/assistant/...') }}{% endif %}"
        "{% if (message['role'] == 'assistant') %}{% set role = 'model' %}"
        "{% else %}{% set role = message['role'] %}{% endif %}"
        "{{ '<start_of_turn>' + role + '\n' + message['content'] | trim + "
        "'<end_of_turn>\n' }}{% endfor %}"
        "{% if add_generation_prompt %}{{'<start_of_turn>model\n'}}{% endif %}";
    final messages = [
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Weather in Paris?',
      ),
      const LlamaChatMessage.withContent(
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
      const LlamaChatMessage.withContent(
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

    for (final choice in ToolChoice.values) {
      test('sends the result as a user turn with tool_choice '
          '${choice.name}', () {
        final result = ChatTemplateEngine.render(
          templateSource: gemma2,
          messages: messages,
          metadata: const {'tokenizer.ggml.bos_token': ''},
          tools: [
            ToolDefinition(
              name: 'get_weather',
              description: 'Get weather',
              parameters: [ToolParam.string('city')],
              handler: _noopHandler,
            ),
          ],
          toolChoice: choice,
        );

        expect(
          result.prompt,
          endsWith(
            '<start_of_turn>user\n'
            '{\n'
            '  "tool_response": {\n'
            '    "tool": "get_weather",\n'
            '    "content": "sunny",\n'
            '    "tool_call_id": "call00001"\n'
            '  }\n'
            '}<end_of_turn>\n'
            '<start_of_turn>model\n',
          ),
        );
        expect(result.prompt, contains('<start_of_turn>model\n{\n'));
        expect(
          result.format,
          choice == ToolChoice.none
              ? ChatFormat.contentOnly.index
              : ChatFormat.generic.index,
        );
      });
    }
  });

  group('ChatTemplateEngine.parse whitespace after content', () {
    const hermesCall =
        '<tool_call>\n'
        '{"name": "get_weather", "arguments": {"city": "Paris"}}\n'
        '</tool_call>';

    test('stays when the content ends the output, in every format', () {
      for (final format in ChatFormat.values) {
        if (format.name.startsWith('peg')) {
          continue;
        }
        for (final parseToolCalls in const [true, false]) {
          for (final output in const ['Hi there. \n ', 'alpha ', 'Hi.\n\n']) {
            expect(
              ChatTemplateEngine.parse(
                format.index,
                output,
                parseToolCalls: parseToolCalls,
              ).content,
              output,
              reason: '${format.name} parseToolCalls: $parseToolCalls',
            );
          }
        }
      }
    });

    test('stays in a PEG parse', () {
      final result = ChatTemplateEngine.render(
        templateSource:
            '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT]'
            '[TOOL_CALLS]get_weather[ARGS]{}',
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        metadata: const {},
        tools: [
          ToolDefinition(
            name: 'get_weather',
            description: 'Get weather',
            parameters: [ToolParam.string('city')],
            handler: _noopHandler,
          ),
        ],
        toolChoice: ToolChoice.auto,
      );
      expect(result.format, ChatFormat.ministral.index);

      final parsed = ChatTemplateEngine.parse(
        result.format,
        '[THINK]Plan.[/THINK]Sure. \n',
        parser: result.parser,
      );

      expect(parsed.reasoningContent, 'Plan.');
      expect(parsed.content, 'Sure. \n');
    });

    test('stays after a thought and loses only leading whitespace', () {
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.hermes.index,
        '<think>\nPlan.\n</think>\n\n Sure. \n',
      );

      expect(parsed.reasoningContent, 'Plan.');
      expect(parsed.content, 'Sure. \n');
    });

    test('stays after a tool call, which the parse keeps', () {
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.hermes.index,
        '$hermesCall\nDone.\n',
      );

      expect(parsed.content, 'Done.\n');
      final call = parsed.toolCalls.single;
      expect(call.function?.name, 'get_weather');
      expect(jsonDecode(call.function!.arguments!), {'city': 'Paris'});
    });

    test('is dropped when the output does not end with the content', () {
      final beforeCall = ChatTemplateEngine.parse(
        ChatFormat.hermes.index,
        'Let me check. \n$hermesCall\n',
      );
      expect(beforeCall.toolCalls, hasLength(1));
      expect(beforeCall.content, 'Let me check.');

      final callOnly = ChatTemplateEngine.parse(
        ChatFormat.hermes.index,
        '$hermesCall \n',
      );
      expect(callOnly.toolCalls, hasLength(1));
      expect(callOnly.content, isEmpty);

      final thoughtOnly = ChatTemplateEngine.parse(
        ChatFormat.hermes.index,
        '<think>Plan.</think> \n',
      );
      expect(thoughtOnly.reasoningContent, 'Plan.');
      expect(thoughtOnly.content, isEmpty);

      expect(
        ChatTemplateEngine.parse(ChatFormat.hermes.index, ' \n ').content,
        isEmpty,
      );
    });

    test('is dropped from a partial parse', () {
      expect(
        ChatTemplateEngine.parse(
          ChatFormat.hermes.index,
          'Hi there. \n',
          isPartial: true,
        ).content,
        'Hi there.',
      );
    });
  });

  group('ChatTemplateEngine.parseRendered', () {
    final weatherTool = ToolDefinition(
      name: 'get_weather',
      description: 'Get weather',
      parameters: [ToolParam.string('city')],
      handler: _noopHandler,
    );
    LlamaChatTemplateResult render(
      String templateSource, {
      bool enableThinking = true,
      ToolChoice toolChoice = ToolChoice.auto,
    }) => ChatTemplateEngine.render(
      templateSource: templateSource,
      messages: messages,
      metadata: const {},
      tools: [weatherTool],
      toolChoice: toolChoice,
      enableThinking: enableThinking,
    );

    // Values from llama.cpp 620d2225: a Seed-OSS end tag ends a thought only
    // when the prompt opened one.
    test('ends a Seed-OSS thought only where the render opened it', () {
      const stock = '{#- <seed:think> -#}assistant\n';
      const opened = 'assistant\n<seed:think>';
      const output = 'Plan</seed:think>Sunny.';
      for (final (source, enableThinking, reasoning, content) in [
        (stock, true, null, output),
        (stock, false, null, output),
        (opened, true, 'Plan', 'Sunny.'),
        (opened, false, 'Plan', 'Sunny.'),
      ]) {
        final rendered = render(source, enableThinking: enableThinking);
        expect(rendered.format, ChatFormat.seedOss.index);
        final parsed = ChatTemplateEngine.parseRendered(rendered, output);
        final reason = '$source, thinking: $enableThinking';
        expect(parsed.reasoningContent, reasoning, reason: reason);
        expect(parsed.content, content, reason: reason);
        // parse cannot tell the renders apart.
        expect(
          ChatTemplateEngine.parse(
            rendered.format,
            output,
            thinkingForcedOpen: rendered.thinkingForcedOpen,
          ).reasoningContent,
          'Plan',
          reason: reason,
        );
      }
    });

    test('passes isPartial, cancelled and parseToolCalls to the parse', () {
      final hermes = render('<tool_call></tool_call>assistant\n');
      expect(hermes.format, ChatFormat.hermes.index);
      expect(
        ChatTemplateEngine.parseRendered(hermes, 'Hi. \n').content,
        'Hi. \n',
      );
      expect(
        ChatTemplateEngine.parseRendered(
          hermes,
          'Hi. \n',
          isPartial: true,
        ).content,
        'Hi.',
      );

      const unfinished = 'Checking. <tool_call>{"name":"get_weather","ar';
      expect(
        ChatTemplateEngine.parseRendered(hermes, unfinished).content,
        unfinished,
      );
      expect(
        ChatTemplateEngine.parseRendered(
          hermes,
          unfinished,
          cancelled: true,
        ).content,
        'Checking.',
      );

      const call =
          '<tool_call>{"name":"get_weather","arguments":{"city":"Paris"}}'
          '</tool_call>';
      expect(
        ChatTemplateEngine.parseRendered(hermes, call).toolCalls,
        hasLength(1),
      );
      final text = ChatTemplateEngine.parseRendered(
        hermes,
        call,
        parseToolCalls: false,
      );
      expect(text.toolCalls, isEmpty);
      expect(text.content, call);
    });

    test('types arguments from the tools passed', () {
      final xml = render(
        '{#- <tool_call> <function= <parameter= '
        'Function calls MUST follow the specified format -#}assistant\n',
      );
      expect(xml.format, ChatFormat.qwen3CoderXml.index);
      const call =
          '<tool_call>\n<function=get_weather>\n<parameter=city>\n123\n'
          '</parameter>\n</function>\n</tool_call>';
      String arguments(List<ToolDefinition>? tools) =>
          ChatTemplateEngine.parseRendered(
            xml,
            call,
            tools: tools,
          ).toolCalls.single.function!.arguments!;
      expect(jsonDecode(arguments([weatherTool])), {'city': '123'});
      expect(jsonDecode(arguments(null)), {'city': 123});
    });

    test("parses with the render's PEG parser", () {
      final ministral = render(
        '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT][TOOL_CALLS]get_weather[ARGS]{}',
        toolChoice: ToolChoice.required,
      );
      expect(ministral.format, ChatFormat.ministral.index);
      expect(ministral.parser, isNotNull);
      expect(
        ChatTemplateEngine.parse(ministral.format, 'Sure.').content,
        'Sure.',
      );
      expect(
        () => ChatTemplateEngine.parseRendered(ministral, 'Sure.'),
        throwsA(isA<LlamaInferenceException>()),
      );
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
