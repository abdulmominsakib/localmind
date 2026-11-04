@TestOn('vm')
library;

import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Gemma4Handler', () {
    test('renders thinking flag into Gemma 4 template context', () {
      const template =
          '{% if enable_thinking %}<|turn>system\n<|think|><turn|>\n{% endif %}'
          '<|turn>user\n{{ messages[0]["content"] }}<turn|>';

      final enabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        addAssistant: false,
        enableThinking: true,
      );
      final disabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        addAssistant: false,
        enableThinking: false,
      );

      expect(enabled.prompt, contains('<|think|>'));
      expect(disabled.prompt, isNot(contains('<|think|>')));
    });

    test('marks prompts ending with a thought channel as forced open', () {
      const template =
          '<|turn>user\n{{ messages[0]["content"] }}<turn|>\n'
          '{% if add_generation_prompt %}<|turn>model\n'
          '{% if enable_thinking %}<|channel>thought\n{% endif %}'
          '{% endif %}';

      final enabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        enableThinking: true,
      );
      final disabled = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        enableThinking: false,
      );

      expect(enabled.thinkingForcedOpen, isTrue);
      expect(enabled.prompt, endsWith('<|channel>thought\n'));
      expect(disabled.thinkingForcedOpen, isFalse);
      expect(disabled.prompt, isNot(contains('<|channel>thought')));
    });

    test('parses reasoning blocks and pseudo-json tool arguments', () {
      const output =
          '<|channel>thought\nNeed weather data.<channel|>'
          '<|tool_call>call:get_weather{location:<|"|>Seoul<|"|>}<tool_call|>';

      final parsed = ChatTemplateEngine.parse(ChatFormat.gemma4.index, output);

      expect(parsed.reasoningContent, equals('Need weather data.'));
      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'location': 'Seoul'}),
      );
    });

    test('parses nested arguments with braces inside quoted values', () {
      const output =
          '<|tool_call>call:get_weather{location:<|"|>A {B}<|"|>,options:{unit:<|"|>celsius<|"|>}}<tool_call|>';

      final parsed = ChatTemplateEngine.parse(ChatFormat.gemma4.index, output);

      expect(parsed.toolCalls, hasLength(1));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({
          'location': 'A {B}',
          'options': {'unit': 'celsius'},
        }),
      );
    });

    test('parses loose function call syntax emitted by Gemma 4 LiteRT-LM', () {
      const output = 'get_weather(location="Seoul")';

      final parsed = ChatTemplateEngine.parse(ChatFormat.gemma4.index, output);

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'location': 'Seoul'}),
      );
    });

    test('streams an open thought channel as partial reasoning', () {
      const output = '<|channel>thought\nNeed weather';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.gemma4.index,
        output,
        isPartial: true,
      );

      expect(parsed.reasoningContent, equals('Need weather'));
      expect(parsed.content, isEmpty);
    });

    test('parses output after a force-opened thought channel', () {
      final thinkingOnly = ChatTemplateEngine.parse(
        ChatFormat.gemma4.index,
        'Need a short calculation.',
        thinkingForcedOpen: true,
      );
      final closed = ChatTemplateEngine.parse(
        ChatFormat.gemma4.index,
        'Need a short calculation.<channel|>391',
        thinkingForcedOpen: true,
      );

      expect(
        thinkingOnly.reasoningContent,
        equals('Need a short calculation.'),
      );
      expect(thinkingOnly.content, isEmpty);
      expect(closed.reasoningContent, equals('Need a short calculation.'));
      expect(closed.content, equals('391'));
    });

    test('serializes tool responses for Gemma 4 templates', () {
      const template =
          '<|turn>tool\n'
          '{% for response in messages[0]["tool_responses"] %}'
          '{{ response["name"] }}={{ response["response"]["timestamp"] }}'
          '{% endfor %}'
          '<turn|>';

      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: 'call_0',
                name: 'get_current_time',
                result: '{"timestamp":"2026-04-02T13:10:00"}',
              ),
            ],
          ),
        ],
        metadata: const {},
        addAssistant: false,
      );

      expect(result.format, equals(ChatFormat.gemma4.index));
      expect(result.prompt, contains('get_current_time=2026-04-02T13:10:00'));
    });
  });
}
