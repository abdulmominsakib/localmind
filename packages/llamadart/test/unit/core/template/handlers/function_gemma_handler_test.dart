@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  group('FunctionGemmaHandler', () {
    test('parses pseudo-json arguments into valid json object', () {
      const output =
          '<start_function_call>call:get_current_weather{location:<escape>San Francisco, CA<escape>}<end_function_call>';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.functionGemma.index,
        output,
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(
        parsed.toolCalls.first.function?.name,
        equals('get_current_weather'),
      );
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'location': 'San Francisco, CA'}),
      );
    });

    test('parses tool calls when call prefix uses whitespace', () {
      const output =
          '<start_function_call>call getWeather{city:<escape>London<escape>}<end_function_call>';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.functionGemma.index,
        output,
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('getWeather'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'city': 'London'}),
      );
    });

    test('renders template with FunctionGemma routing', () {
      final source = File(
        'test/fixtures/templates/functiongemma-270m-it.jinja',
      ).readAsStringSync();

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: const [
          LlamaChatMessage(role: 'user', content: 'time'),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [
              LlamaToolCallContent(
                id: 'call_0',
                name: 'get_current_time',
                arguments: {},
                rawJson: '{}',
              ),
            ],
          ),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: 'call_0',
                name: 'get_current_time',
                result: '2026-02-12T14:47:00',
              ),
            ],
          ),
        ],
        metadata: const {
          'tokenizer.ggml.bos_token': '<bos>',
          'tokenizer.ggml.eos_token': '<eos>',
        },
        addAssistant: true,
      );

      expect(result.format, equals(ChatFormat.functionGemma.index));
      expect(result.grammar, isNull);
      expect(
        result.prompt,
        contains('<start_function_response>response:get_current_time{'),
      );
      expect(result.prompt, contains('<end_function_response>'));
    });

    test('normalizes JSON-string tool responses when rendering', () {
      final source = File(
        'test/fixtures/templates/functiongemma-270m-it.jinja',
      ).readAsStringSync();

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: const [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: 'call_0',
                name: 'get_current_time',
                result: '{"timestamp":"2026-02-12T14:47:00"}',
              ),
            ],
          ),
        ],
        metadata: const {
          'tokenizer.ggml.bos_token': '<bos>',
          'tokenizer.ggml.eos_token': '<eos>',
        },
        addAssistant: false,
      );

      expect(
        result.prompt,
        contains('timestamp:<escape>2026-02-12T14:47:00<escape>'),
      );
    });
  });
}
