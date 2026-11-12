import 'dart:typed_data';

import 'package:dinja/dinja.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_templates.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_template.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:test/test.dart';

/// Mirrors `LiteRtLmService._resolveBuiltinTemplate`: first match wins.
String? resolveId(String fileName) {
  return resolveTemplate(fileName)?.id;
}

LiteRtLmChatTemplate? resolveTemplate(String fileName) {
  final normalized = fileName.toLowerCase().replaceAll('_', '-');
  for (final template in kLiteRtLmChatTemplates) {
    if (template.matches(normalized)) {
      return template;
    }
  }
  return null;
}

void main() {
  group('LiteRT-LM chat template registry', () {
    for (final thinking in [false, true]) {
      for (final tools in [false, true]) {
        test(
          'Qwen content arrays preserve string prompts: thinking=$thinking tools=$tools',
          () {
            final template = Template(
              resolveTemplate('Qwen3-0.6B.litertlm')!.template,
            );
            final messages = <Map<String, dynamic>>[
              {'role': 'system', 'content': 'Remember the code.'},
              {'role': 'user', 'content': 'The code is cedar17.'},
              {
                'role': 'assistant',
                'content': '<think>Remember it.</think>\nI will.',
              },
              {'role': 'tool', 'content': 'cedar17'},
              {'role': 'user', 'content': 'What is the code?'},
            ];
            final context = <String, dynamic>{
              'messages': messages,
              'tools': tools
                  ? [
                      {
                        'type': 'function',
                        'function': {'name': 'lookup'},
                      },
                    ]
                  : null,
              'add_generation_prompt': true,
              'enable_thinking': thinking,
            };
            final expected = template.render(context);
            final normalized = messages
                .map(
                  (message) => <String, dynamic>{
                    ...message,
                    'content': [
                      {'type': 'text', 'text': message['content']},
                    ],
                  },
                )
                .toList();
            expect(
              template.render({...context, 'messages': normalized}),
              expected,
            );
            expect(expected, contains('cedar17'));
            if (!thinking) {
              expect(expected, endsWith('<think>\n\n</think>\n\n'));
            }
            expect(expected, isNot(contains("'type': 'text'")));
          },
        );
      }
    }
    test('Qwen joins multiple normalized text parts', () {
      final template = Template(
        resolveTemplate('Qwen3-0.6B.litertlm')!.template,
      );
      expect(
        template.render({
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'hello '},
                {'type': 'text', 'text': 'world'},
              ],
            },
          ],
          'add_generation_prompt': false,
        }),
        '<|im_start|>user\nhello world<|im_end|>\n',
      );
    });

    test('Qwen preserves actual native tool response payloads', () {
      final template = Template(
        resolveTemplate('Qwen3-0.6B.litertlm')!.template,
      );
      final responses = [
        {
          'type': 'tool_response',
          'name': 'get_weather',
          'response': {'city': 'Montréal', 'temperature_celsius': 17},
        },
        {
          'type': 'tool_response',
          'name': 'lookup',
          'response': ['cedar17', 'oak22'],
        },
        {
          'type': 'tool_response',
          'name': 'scalar',
          'response': 'plain response',
        },
      ];
      final output = template.render({
        'messages': [
          {'role': 'user', 'content': 'Use the tools.'},
          {'role': 'tool', 'content': responses},
        ],
        'add_generation_prompt': true,
        'enable_thinking': false,
      });
      expect(output, contains(RegExp(r'"temperature_celsius"\s*:\s*17')));
      expect(output, contains('Montréal'));
      expect(output, contains('cedar17'));
      expect(output, contains('oak22'));
      expect(output, contains('plain response'));
    });
    for (final part in [
      {'type': 'image', 'image_path': 'image.png'},
      {'type': 'image'},
      {'type': 'audio'},
      {'type': 'unknown'},
      {'text': 'missing type'},
      {'type': 'text'},
      {'type': 'text', 'text': 42},
      {'type': 'tool_response', 'name': 'missing_response'},
    ]) {
      test(
        'Qwen rejects unsupported or malformed normalized content: $part',
        () {
          final template = Template(
            resolveTemplate('Qwen3-0.6B.litertlm')!.template,
          );
          expect(
            () => template.render({
              'messages': [
                {
                  'role': 'user',
                  'content': [part],
                },
              ],
            }),
            throwsA(anything),
          );
        },
      );
    }

    for (final (kind, media) in <(String, LlamaContentPart)>[
      ('image', LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3]))),
      ('audio', LlamaAudioContent(bytes: Uint8List.fromList([4, 5, 6]))),
      ('video', LlamaVideoContent(bytes: Uint8List.fromList([7, 8, 9]))),
    ]) {
      for (final bundle in ['Qwen3-0.6B.litertlm', 'Qwen3.5-2B.litertlm']) {
        test('Dart rendering gives the $bundle text template the media '
            'marker for $kind, never a media part', () {
          final template = resolveTemplate(bundle)!;
          expect(TemplateCaps.detect(template.template).toMap(), {
            'supports_system_role': true,
            'supports_tool_calls': true,
            'supports_tools': true,
            'supports_parallel_tool_calls': true,
            'supports_string_content': true,
            'supports_typed_content': false,
            'supports_thinking': true,
            'supports_object_arguments': true,
          });
          final rendered = ChatTemplateEngine.render(
            templateSource: template.template,
            messages: [
              LlamaChatMessage.withContent(
                role: LlamaChatRole.user,
                content: [const LlamaTextContent('Describe this.'), media],
              ),
            ],
            metadata: {
              'tokenizer.chat_template': template.template,
              'tokenizer.ggml.bos_token': template.bosToken,
              'tokenizer.ggml.eos_token': template.eosToken,
            },
            enableThinking: false,
          );
          expect(
            rendered.prompt,
            '<|im_start|>user\nDescribe this.<__media__><|im_end|>\n'
            '<|im_start|>assistant\n<think>\n\n</think>\n\n',
          );
          expect(rendered.format, ChatFormat.hermes.index);
        });
      }
    }

    test('resolves each seeded family from representative bundle names', () {
      expect(resolveId('gemma-4-E2B-it.litertlm'), 'gemma4');
      expect(resolveId('gemma-4-E4B-it.litertlm'), 'gemma4');
      expect(resolveId('gemma-3n-E2B-it.litertlm'), 'gemma3n');
      expect(resolveId('gemma-3n-E4B-it.litertlm'), 'gemma3n');
      expect(resolveId('gemma-3-4b-it.litertlm'), 'gemma');
      expect(resolveId('gemma-2-2b-it.litertlm'), 'gemma');
      expect(resolveId('Qwen3-0.6B.litertlm'), 'qwen3');
      expect(resolveId('Qwen3.5-2B.litertlm'), 'qwen3');
      expect(resolveId('Qwen2.5-1.5B-Instruct.litertlm'), 'qwen25');
    });

    test('precedence: specific families win over broader ones', () {
      // gemma-4 / gemma-3n must not be swallowed by the gemma-3 entry, and
      // qwen3 must not be swallowed by the qwen entry.
      expect(resolveId('gemma-4-E2B-it.litertlm'), isNot('gemma'));
      expect(resolveId('gemma-3n-E4B-it.litertlm'), isNot('gemma'));
      expect(resolveId('Qwen3-0.6B.litertlm'), isNot('qwen25'));
    });

    test(
      'returns null for unseeded models (caller falls back / overrides)',
      () {
        expect(resolveId('phi-4-mini-instruct.litertlm'), isNull);
        expect(resolveId('some-unknown-model.litertlm'), isNull);
      },
    );

    test('does not mis-route qwen-derived models to the Qwen 2.5 template', () {
      // DeepSeek-R1-Distill-Qwen needs its own handler; the bare `qwen` rule
      // must not greedily claim it.
      expect(resolveId('DeepSeek-R1-Distill-Qwen-1.5B.litertlm'), isNull);
    });

    test('templates omit a leading BOS token (native runtime adds it)', () {
      for (final template in kLiteRtLmChatTemplates) {
        expect(
          template.template,
          isNot(contains('bos_token')),
          reason: '${template.id} must not emit bos_token',
        );
      }
    });

    test(
      'uses parser-compatible thought markers for Qwen/Hermes templates',
      () {
        final gemma4 = resolveTemplate('gemma-4-E2B-it.litertlm')!;
        final qwen3 = resolveTemplate('Qwen3-0.6B.litertlm')!;
        final qwen25 = resolveTemplate('Qwen2.5-1.5B-Instruct.litertlm')!;

        expect(gemma4.thinkingStartTag, '<|channel>thought\n');
        expect(gemma4.thinkingEndTag, '<channel|>');
        expect(qwen3.thinkingStartTag, '<think>');
        expect(qwen3.thinkingEndTag, '</think>');
        expect(qwen25.thinkingStartTag, '<think>');
        expect(qwen25.thinkingEndTag, '</think>');
      },
    );
  });
}
