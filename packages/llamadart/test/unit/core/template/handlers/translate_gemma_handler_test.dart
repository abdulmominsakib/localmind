import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
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
}
