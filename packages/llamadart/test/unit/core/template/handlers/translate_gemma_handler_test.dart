import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/translate_gemma_handler.dart';
import 'package:test/test.dart';

void main() {
  group('TranslateGemmaHandler', () {
    const template =
        '[source_lang_code]\n'
        '[target_lang_code]\n'
        '{%- for message in messages -%}'
        '{%- if message["role"] == "user" -%}'
        '{{- message["content"][0]["source_lang_code"] + "->" + message["content"][0]["target_lang_code"] + ":" + message["content"][0]["text"] -}}'
        '{%- endif -%}'
        '{%- endfor -%}';

    test('renders user content with default language codes', () {
      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        metadata: const {},
        addAssistant: false,
      );

      expect(result.format, equals(ChatFormat.translateGemma.index));
      expect(result.prompt, contains('en-GB->en-GB:hello'));
    });

    test('renders user content with metadata language overrides', () {
      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: '안녕하세요'),
        ],
        metadata: const {
          'source_lang_code': 'ko-KR',
          'target_lang_code': 'en-US',
        },
        addAssistant: false,
      );

      expect(result.format, equals(ChatFormat.translateGemma.index));
      expect(result.prompt, contains('ko-KR->en-US:안녕하세요'));
    });

    test('renders user content with chatTemplateKwargs language codes', () {
      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: '안녕하세요'),
        ],
        metadata: const {},
        chatTemplateKwargs: const {
          'source_lang_code': 'ko-KR',
          'target_lang_code': 'en-US',
        },
        addAssistant: false,
      );

      expect(result.format, equals(ChatFormat.translateGemma.index));
      expect(result.prompt, contains('ko-KR->en-US:안녕하세요'));
    });

    test('prefers chatTemplateKwargs over metadata language codes', () {
      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {
          'source_lang_code': 'ko-KR',
          'target_lang_code': 'en-US',
        },
        chatTemplateKwargs: const {'target_lang_code': 'fr'},
        addAssistant: false,
      );

      expect(result.prompt, contains('ko-KR->fr:hi'));
    });

    test('rejects a non-string chatTemplateKwargs language code', () {
      expect(
        () => ChatTemplateEngine.render(
          templateSource: template,
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
          ],
          metadata: const {},
          chatTemplateKwargs: const {'source_lang_code': 7},
          addAssistant: false,
        ),
        throwsA(
          isA<LlamaArgumentException>()
              .having((e) => e.name, 'name', 'chatTemplateKwargs')
              .having(
                (e) => e.message,
                'message',
                contains('source_lang_code'),
              ),
        ),
      );
    });

    test('passes typed tool results to the template as JSON text', () {
      final result = ChatTemplateEngine.handlerFor(ChatFormat.translateGemma)
          .render(
            templateSource:
                '{%- for message in messages -%}'
                "{%- if message.role == 'tool' -%}{{ message.content }}|"
                '{%- endif -%}'
                '{%- endfor -%}',
            messages: const [
              LlamaChatMessage.withContent(
                role: LlamaChatRole.tool,
                content: [
                  LlamaToolResultContent(
                    id: 'call_0',
                    name: 'get_weather',
                    result: {'temp': 21.5, 'sky': 'clear', 'note': "it's"},
                  ),
                  LlamaToolResultContent(
                    id: 'call_1',
                    name: 'get_weather',
                    result: [
                      1,
                      'a',
                      {'k': true},
                    ],
                  ),
                ],
              ),
            ],
            metadata: const {},
            addAssistant: false,
          );

      expect(
        result.prompt,
        '{"temp":21.5,"sky":"clear","note":"it\'s"}|[1,"a",{"k":true}]|',
      );
    });

    test('parses output as plain content', () {
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.translateGemma.index,
        'Hello there',
      );

      expect(parsed.content, equals('Hello there'));
      expect(parsed.reasoningContent, isNull);
      expect(parsed.toolCalls, isEmpty);
    });
  });

  group('chatTemplateKwargsWithLanguageCodes', () {
    test('returns the kwargs unchanged without codes', () {
      const kwargs = {'locale': 'en_CA'};

      expect(chatTemplateKwargsWithLanguageCodes(null), isNull);
      expect(
        chatTemplateKwargsWithLanguageCodes(
          kwargs,
          sourceLangCode: '',
          targetLangCode: '',
        ),
        same(kwargs),
      );
    });

    test('adds codes, replacing the same kwargs keys', () {
      expect(
        chatTemplateKwargsWithLanguageCodes(
          const {'locale': 'en_CA', 'source_lang_code': 'de'},
          sourceLangCode: 'en',
          targetLangCode: 'ko',
        ),
        {'locale': 'en_CA', 'source_lang_code': 'en', 'target_lang_code': 'ko'},
      );
      expect(chatTemplateKwargsWithLanguageCodes(null, targetLangCode: 'ko'), {
        'target_lang_code': 'ko',
      });
    });
  });
}
