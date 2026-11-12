import 'dart:typed_data';

import 'package:llamadart/src/core/engine/chat_template_renderer.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:test/test.dart';

void main() {
  group('ChatTemplateRenderer', () {
    test('renders a template and counts tokens when requested', () async {
      var tokenizeAddSpecial = true;
      final result = await ChatTemplateRenderer.render(
        loadMetadata: () async => const {},
        tokenize: (text, {bool addSpecial = true}) async {
          tokenizeAddSpecial = addSpecial;
          return [1, 2, 3];
        },
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        customTemplate:
            '{{ messages[0]["role"] }}: {{ messages[0]["content"] }}'
            '{% if add_generation_prompt %} assistant:{% endif %}',
      );

      expect(result.prompt, contains('user: hello'));
      expect(result.prompt, contains('assistant:'));
      expect(result.tokenCount, 3);
      expect(tokenizeAddSpecial, isFalse);
    });

    test('skips token count when tokenization is unsupported', () async {
      final result = await ChatTemplateRenderer.render(
        loadMetadata: () async => const {},
        tokenize: (text, {bool addSpecial = true}) async {
          throw UnsupportedError('tokenization unavailable');
        },
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        customTemplate: '{{ messages[0]["content"] }}',
      );

      expect(result.prompt, 'hello');
      expect(result.tokenCount, isNull);
    });

    test('modelTemplate replaces the metadata template and its tool_use '
        'variant', () async {
      Future<String> render({
        String? modelTemplate,
        String? customTemplate,
        List<ToolDefinition>? tools,
      }) async {
        final result = await ChatTemplateRenderer.render(
          loadMetadata: () async => {
            'tokenizer.chat_template': 'METADATA:{{ messages[0]["content"] }}',
            'tokenizer.chat_template.tool_use':
                'TOOL_USE:{{ messages[-1]["content"] }}',
          },
          tokenize: (text, {bool addSpecial = true}) async => const [],
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
          ],
          tools: tools,
          modelTemplate: modelTemplate,
          customTemplate: customTemplate,
          includeTokenCount: false,
        );
        return result.prompt;
      }

      final tools = [
        ToolDefinition(
          name: 'noop',
          description: 'Does nothing',
          parameters: const [],
          handler: (_) async => null,
        ),
      ];
      const modelTemplate = 'MODEL:{{ messages[-1]["content"] }}';

      expect(await render(), 'METADATA:hello');
      expect(await render(tools: tools), startsWith('TOOL_USE:'));
      expect(await render(modelTemplate: ''), 'METADATA:hello');
      expect(await render(modelTemplate: modelTemplate), 'MODEL:hello');
      expect(
        await render(modelTemplate: modelTemplate, tools: tools),
        startsWith('MODEL:'),
      );
      expect(
        await render(
          modelTemplate: modelTemplate,
          customTemplate: 'CUSTOM:{{ messages[0]["content"] }}',
        ),
        'CUSTOM:hello',
      );
    });

    test('a render failure names the template that failed', () async {
      const raising = "{{ raise_exception('roles must alternate') }}";
      Future<void> expectNamed(
        String name, {
        Map<String, String> metadata = const {
          'tokenizer.chat_template': raising,
          'tokenizer.chat_template.tool_use': raising,
        },
        String? modelTemplate,
        String? customTemplate,
        List<ToolDefinition>? tools,
      }) async {
        await expectLater(
          ChatTemplateRenderer.render(
            loadMetadata: () async => metadata,
            tokenize: (text, {bool addSpecial = true}) async => const [],
            messages: const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: tools,
            modelTemplate: modelTemplate,
            customTemplate: customTemplate,
            includeTokenCount: false,
          ),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              'The chat template from $name failed to render: '
                  'roles must alternate',
            ),
          ),
        );
      }

      final tools = [
        ToolDefinition(
          name: 'noop',
          description: 'Does nothing',
          parameters: const [],
          handler: (_) async => null,
        ),
      ];

      await expectNamed("the model's tokenizer.chat_template");
      await expectNamed(
        "the model's tokenizer.chat_template.tool_use",
        tools: tools,
      );
      await expectNamed('ModelParams.chatTemplate', modelTemplate: raising);
      await expectNamed(
        'ModelParams.chatTemplate',
        modelTemplate: raising,
        tools: tools,
      );
      await expectNamed(
        'customTemplate',
        metadata: const {'tokenizer.chat_template': '{{ "ok" }}'},
        modelTemplate: '{{ "ok" }}',
        customTemplate: raising,
      );
    });

    for (final metadata in <Map<String, String>>[
      const {},
      const {'tokenizer.chat_template': ''},
    ]) {
      test('render failure names the ChatML fallback for $metadata', () async {
        await expectLater(
          ChatTemplateRenderer.render(
            loadMetadata: () async => metadata,
            tokenize: (text, {bool addSpecial = true}) async => const [],
            messages: const [_UnrenderableMessage()],
            includeTokenCount: false,
          ),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              'The chat template from the built-in ChatML fallback template '
                  'failed to render: fallback content failed',
            ),
          ),
        );
      });

      test('render uses the ChatML fallback for $metadata', () async {
        final result = await ChatTemplateRenderer.render(
          loadMetadata: () async => metadata,
          tokenize: (text, {bool addSpecial = true}) async => const [],
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
          ],
          includeTokenCount: false,
        );
        expect(
          result.prompt,
          '<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n',
        );
      });
    }

    test('templateSourceName names the ChatML fallback when no template '
        'is set', () {
      expect(
        ChatTemplateRenderer.templateSourceName(),
        'the built-in ChatML fallback template',
      );
      expect(
        ChatTemplateRenderer.templateSourceName(modelTemplate: ''),
        'the built-in ChatML fallback template',
      );
      expect(
        ChatTemplateRenderer.templateSourceName(metadataTemplate: 'm'),
        "the model's tokenizer.chat_template",
      );
      expect(
        ChatTemplateRenderer.templateSourceName(
          modelTemplate: 'o',
          metadataTemplate: 'm',
        ),
        'ModelParams.chatTemplate',
      );
    });

    group('with a parsing template', () {
      const parsing =
          '{# <tool_call> #}{% for m in messages %}PARSE:{{ m["content"] }}'
          '{% endfor %}';
      const runtime =
          '{% for m in messages %}RUNTIME:{{ m["content"] }}{% endfor %}'
          '{% if tools %} TOOLS{% endif %}'
          '{% if enable_thinking %} THINK{% endif %}';
      const metadata = {
        'tokenizer.chat_template': runtime,
        parsingChatTemplateMetadataKey: parsing,
      };
      final tools = [
        ToolDefinition(
          name: 'noop',
          description: 'Does nothing',
          parameters: const [],
          handler: (_) async => null,
        ),
      ];

      Future<LlamaChatTemplateResult> render({
        Map<String, String> metadata = metadata,
        bool runtimePrompt = false,
        String? modelTemplate,
        String? customTemplate,
        List<ToolDefinition>? tools,
        List<LlamaChatMessage> messages = const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        bool enableThinking = true,
        Map<String, dynamic>? chatTemplateKwargs,
        DateTime? templateNow,
      }) => ChatTemplateRenderer.render(
        loadMetadata: () async => metadata,
        tokenize: (text, {bool addSpecial = true}) async =>
            List.filled(text.length, 0),
        messages: messages,
        tools: tools,
        modelTemplate: modelTemplate,
        customTemplate: customTemplate,
        renderRuntimePrompt: runtimePrompt,
        enableThinking: enableThinking,
        chatTemplateKwargs: chatTemplateKwargs,
        templateNow: templateNow,
      );

      Future<String> runtimePromptOf(
        String runtimeTemplate, {
        List<ToolDefinition>? tools,
        List<LlamaChatMessage> messages = const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        bool enableThinking = true,
        Map<String, dynamic>? chatTemplateKwargs,
        DateTime? templateNow,
      }) async => (await render(
        metadata: {
          'tokenizer.chat_template': runtimeTemplate,
          parsingChatTemplateMetadataKey: parsing,
        },
        runtimePrompt: true,
        tools: tools,
        messages: messages,
        enableThinking: enableThinking,
        chatTemplateKwargs: chatTemplateKwargs,
        templateNow: templateNow,
      )).prompt;

      test('renders the runtime prompt with the request thinking, kwargs '
          'and time', () async {
        expect(
          await runtimePromptOf(runtime, enableThinking: false),
          'RUNTIME:hello',
        );
        expect(
          await runtimePromptOf(
            '{{ greeting }}',
            chatTemplateKwargs: {'greeting': 'KWARG'},
          ),
          'KWARG',
        );
        expect(
          await runtimePromptOf(
            "{{ strftime_now('%Y') }}",
            templateNow: DateTime.utc(2001, 2, 3),
          ),
          '2001',
        );
      });

      test('renders the runtime prompt without a tool_use variant', () async {
        final shown = await render(
          metadata: const {
            'tokenizer.chat_template': runtime,
            'tokenizer.chat_template.tool_use': 'TOOL_USE',
            parsingChatTemplateMetadataKey: parsing,
          },
          runtimePrompt: true,
          tools: tools,
        );

        expect(shown.prompt, 'RUNTIME:hello TOOLS THINK');
      });

      test('renders the runtime prompt for requests the parsing format '
          'qualifies and plain rendering does not', () async {
        expect(
          await runtimePromptOf(
            runtime,
            tools: [
              ToolDefinition.fromJsonSchema(
                name: 'lookup',
                description: 'Looks up a city.',
                schema: const {
                  'type': 'object',
                  'properties': {
                    'city': {'type': 'string'},
                  },
                },
              ),
            ],
          ),
          'RUNTIME:hello TOOLS THINK',
        );
        expect(
          await runtimePromptOf(
            '{% for m in messages %}RUNTIME:{{ m["role"] }} {% endfor %}',
            messages: const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'look'),
              LlamaChatMessage.withContent(
                role: LlamaChatRole.tool,
                content: [
                  LlamaToolResultContent(
                    id: 'call_0',
                    name: 'lookup',
                    result: null,
                    content: [LlamaTextContent('sunny')],
                  ),
                ],
              ),
            ],
          ),
          'RUNTIME:user RUNTIME:tool ',
        );
      });

      test(
        'parses and renders with it instead of tokenizer.chat_template',
        () async {
          final result = await render(tools: tools);
          final reference = await render(
            metadata: const {'tokenizer.chat_template': parsing},
            tools: tools,
          );

          expect(result.prompt, 'PARSE:hello');
          expect(result.format, ChatFormat.hermes.index);
          expect(result.prompt, reference.prompt);
          expect(result.grammar, reference.grammar);
          expect(result.parser, reference.parser);
        },
      );

      test('yields to ModelParams.chatTemplate and customTemplate', () async {
        const model = 'MODEL:{{ messages[0]["content"] }}';
        const custom = 'CUSTOM:{{ messages[0]["content"] }}';

        expect((await render(modelTemplate: model)).prompt, 'MODEL:hello');
        expect(
          (await render(modelTemplate: model, customTemplate: custom)).prompt,
          'CUSTOM:hello',
        );
        expect(
          (await render(
            modelTemplate: model,
            customTemplate: custom,
            runtimePrompt: true,
          )).prompt,
          'CUSTOM:hello',
        );
      });

      test(
        'shows the runtime template prompt and token count on request',
        () async {
          final parsed = await render(tools: tools);
          final shown = await render(tools: tools, runtimePrompt: true);

          expect(shown.prompt, 'RUNTIME:hello TOOLS THINK');
          expect(shown.tokenCount, shown.prompt.length);
          expect(shown.format, parsed.format);
          expect(shown.grammar, parsed.grammar);
          expect(shown.parser, parsed.parser);
          expect(shown.additionalStops, parsed.additionalStops);
        },
      );

      test('counts only a runtime prompt with the runtime prompt '
          'tokenizer', () async {
        final counted = <String>[];
        Future<LlamaChatTemplateResult> show({
          Map<String, String> metadata = metadata,
          bool runtimePrompt = true,
        }) => ChatTemplateRenderer.render(
          loadMetadata: () async => metadata,
          tokenize: (text, {bool addSpecial = true}) async =>
              List.filled(text.length, 0),
          tokenizeRuntimePrompt: (prompt) async {
            counted.add(prompt);
            return const [1, 2];
          },
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
          ],
          renderRuntimePrompt: runtimePrompt,
        );

        expect((await show()).tokenCount, 2);
        expect(counted, ['RUNTIME:hello THINK']);
        expect((await show(runtimePrompt: false)).tokenCount, 11);
        expect(
          (await show(
            metadata: const {
              'tokenizer.chat_template': '{% if %}',
              parsingChatTemplateMetadataKey: parsing,
            },
          )).tokenCount,
          11,
        );
        expect(counted, hasLength(1));
      });

      test('shows the runtime prompt with ModelParams.chatTemplate', () async {
        final shown = await render(
          modelTemplate: 'MODEL:{{ messages[0]["content"] }}',
          runtimePrompt: true,
        );

        expect(shown.prompt, 'RUNTIME:hello THINK');
        expect(shown.format, ChatFormat.contentOnly.index);
      });

      test(
        'ignores the runtime prompt request without a parsing template',
        () async {
          final shown = await render(
            metadata: const {'tokenizer.chat_template': runtime},
            runtimePrompt: true,
          );

          expect(shown.prompt, 'RUNTIME:hello THINK');
          expect(shown.format, ChatFormat.contentOnly.index);
        },
      );

      test('places media markers in the runtime prompt', () async {
        final shown = await render(
          runtimePrompt: true,
          messages: [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [
                const LlamaTextContent('look '),
                LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
              ],
            ),
          ],
        );

        expect(shown.prompt, 'RUNTIME:look <__media__> THINK');
      });

      test('keeps the parsing prompt and warns when the runtime template '
          'cannot render', () async {
        final records = <LlamaLogRecord>[];
        final logger = LlamaLogger.instance;
        final level = logger.level;
        logger
          ..setLevel(LlamaLogLevel.warn)
          ..setHandler(records.add);
        addTearDown(() {
          logger
            ..setLevel(level)
            ..setHandler(null);
        });
        final shown = await render(
          metadata: const {
            'tokenizer.chat_template': '{% if %}',
            parsingChatTemplateMetadataKey: parsing,
          },
          runtimePrompt: true,
        );

        expect(shown.prompt, 'PARSE:hello');
        expect(shown.tokenCount, 'PARSE:hello'.length);
        expect(records.where((record) => record.level == LlamaLogLevel.warn), [
          isA<LlamaLogRecord>().having(
            (record) => record.message,
            'message',
            contains('runtime template did not render'),
          ),
        ]);
      });

      for (final expression in ['10 // 0', '10 % 0']) {
        test('keeps the parsing prompt when the runtime template raises an '
            'Error ($expression)', () async {
          expect(await runtimePromptOf('{{ $expression }}'), 'PARSE:hello');
        });
      }

      test('names the parsing template in render failures', () {
        expect(
          ChatTemplateRenderer.templateSourceName(
            modelTemplate: 'o',
            metadataTemplate: 'm',
            parsingTemplate: 'p',
          ),
          'ModelParams.chatTemplate',
        );
        expect(
          ChatTemplateRenderer.templateSourceName(
            metadataTemplate: 'm',
            parsingTemplate: 'p',
          ),
          "the model's $parsingChatTemplateMetadataKey",
        );
        expect(
          () => render(
            metadata: const {
              'tokenizer.chat_template': runtime,
              parsingChatTemplateMetadataKey: '{% if %}',
            },
          ),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              contains(parsingChatTemplateMetadataKey),
            ),
          ),
        );
      });
    });

    test('modelTemplate renders when metadata cannot be read', () async {
      final result = await ChatTemplateRenderer.render(
        loadMetadata: () async => throw StateError('no metadata'),
        tokenize: (text, {bool addSpecial = true}) async => const [],
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        modelTemplate: 'MODEL:{{ messages[0]["content"] }}',
        includeTokenCount: false,
      );

      expect(result.prompt, 'MODEL:hello');
    });
  });
}

// Fail inside Jinja's context conversion, after the production renderer has
// selected its fallback; replacing the template would change the source label.
class _UnrenderableMessage extends LlamaChatMessage {
  const _UnrenderableMessage()
    : super.fromText(role: LlamaChatRole.user, text: 'hi');

  @override
  Map<String, dynamic> toJson() => {
    'role': 'user',
    'content': _UnrenderableContent(),
  };
}

class _UnrenderableContent {
  @override
  String toString() => throw Exception('fallback content failed');
}
