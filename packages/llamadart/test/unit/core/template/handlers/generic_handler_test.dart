import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/template/handlers/generic_handler.dart';
import 'package:test/test.dart';

void main() {
  group('GenericHandler', () {
    const metadata = <String, String>{
      'tokenizer.ggml.bos_token': '<s>',
      'tokenizer.ggml.eos_token': '</s>',
    };

    const messages = [LlamaChatMessage(role: 'user', content: 'hello')];

    test('uses ChatML stop when template includes <|im_end|>', () {
      const template =
          '<|im_start|>user\n{{ messages[0]["content"] }}<|im_end|>';
      final handler = GenericHandler();

      final result = handler.render(
        templateSource: template,
        messages: messages,
        metadata: metadata,
      );

      expect(result.additionalStops, contains('<|im_end|>'));
      expect(result.additionalStops, isNot(contains('<|end|>')));
    });

    test('uses Phi stop when template includes <|end|>', () {
      const template =
          '<|user|>{{ messages[0]["content"] }}<|end|><|assistant|>';
      final handler = GenericHandler();

      final result = handler.render(
        templateSource: template,
        messages: messages,
        metadata: metadata,
      );

      expect(result.additionalStops, contains('<|end|>'));
      expect(result.additionalStops, isNot(contains('<|im_end|>')));
    });

    test('uses Gemma stop when template includes <end_of_turn>', () {
      const template =
          '<start_of_turn>user\n{{ messages[0]["content"] }}<end_of_turn>\n';
      final handler = GenericHandler();

      final result = handler.render(
        templateSource: template,
        messages: messages,
        metadata: metadata,
      );

      expect(result.additionalStops, contains('<end_of_turn>'));
      expect(result.additionalStops, isNot(contains('<|im_end|>')));
    });

    test('parses generic tool_call envelope JSON', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_call":{"name":"get_weather","arguments":{"city":"Seoul"}}}',
      );
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    });

    test('keeps malformed generic tool_calls array as content', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_calls":[{"name":"get_weather","arguments":{"city":"Seoul"}},{"arguments":{"city":"Busan"}}]}',
      );

      expect(parsed.toolCalls, isEmpty);
      expect(
        parsed.content,
        equals(
          '{"tool_calls":[{"name":"get_weather","arguments":{"city":"Seoul"}},{"arguments":{"city":"Busan"}}]}',
        ),
      );
    });

    test('keeps malformed generic tool_call object as content', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_call":{"arguments":{"city":"Seoul"}}}',
      );

      expect(parsed.toolCalls, isEmpty);
      expect(
        parsed.content,
        equals('{"tool_call":{"arguments":{"city":"Seoul"}}}'),
      );
    });

    test('parses partial generic tool_call with missing arguments', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{ "tool_call" : { "name" : "special_function"',
        isPartial: true,
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('special_function'));
      expect(parsed.toolCalls.first.function?.arguments, equals(''));
      expect(parsed.content, isEmpty);
    });

    test('does not stream raw partial JSON envelopes as content', () {
      final handler = GenericHandler();

      final parsed = handler.parse('{', isPartial: true);

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, isEmpty);
    });

    test('parses partial generic tool_call with partial arguments object', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_call":{"name":"puppeteer_screenshot","arguments":{"name":"servethehome_homepage",',
        isPartial: true,
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(
        parsed.toolCalls.first.function?.name,
        equals('puppeteer_screenshot'),
      );
      expect(
        parsed.toolCalls.first.function?.arguments,
        equals('{"name":"servethehome_homepage",'),
      );
      expect(parsed.content, isEmpty);
    });

    test('does not treat nested arguments.name as tool_call name', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_call":{"arguments":{"name":"inner"},"id":"x"',
        isPartial: true,
      );

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, isEmpty);
    });

    test('uses top-level tool_call name when nested name appears first', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_call":{"metadata":{"name":"inner"},"name":"outer","arguments":{"city":"Se"',
        isPartial: true,
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('outer'));
      expect(
        parsed.toolCalls.first.function?.arguments,
        equals('{"city":"Se"'),
      );
      expect(parsed.content, isEmpty);
    });

    test('parses partial generic tool_calls array envelope', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_calls":[{"name":"get_weather","arguments":{"city":"Seo',
        isPartial: true,
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        parsed.toolCalls.first.function?.arguments,
        equals('{"city":"Seo'),
      );
      expect(parsed.content, isEmpty);
    });

    test('ignores nested arguments.name in partial tool_calls arrays', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_calls":[{"name":"outer","arguments":{"name":"inner"}}',
        isPartial: true,
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('outer'));
      expect(parsed.content, isEmpty);
    });

    test('parses escaped partial string arguments in tool_call', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        r'{"tool_call":{"name":"get_weather","arguments":"{\"city\":\"Se"}}',
        isPartial: true,
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(parsed.toolCalls.first.function?.arguments, equals('{"city":"Se'));
      expect(parsed.content, isEmpty);
    });

    test('parses multiple partial generic tool_calls entries', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_calls":[{"name":"get_weather","arguments":{"city":"Seoul"}},{"name":"get_time","arguments":{"city":"Busan"}}',
        isPartial: true,
      );

      expect(parsed.toolCalls, hasLength(2));
      expect(parsed.toolCalls[0].function?.name, equals('get_weather'));
      expect(parsed.toolCalls[1].function?.name, equals('get_time'));
      expect(parsed.content, isEmpty);
    });

    test('keeps non-native tool_call shape as plain content', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        '{"tool_call":{"function":{"name":"get_weather","arguments":{"city":"Seoul"}}}}',
      );
      expect(parsed.toolCalls, isEmpty);
      expect(
        parsed.content,
        '{"tool_call":{"function":{"name":"get_weather","arguments":{"city":"Seoul"}}}}',
      );
    });

    test('parses generic response envelope JSON', () {
      final handler = GenericHandler();

      final parsed = handler.parse('{"response":"hello"}');
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals('hello'));
    });

    test('decodes escaped partial generic response content', () {
      final handler = GenericHandler();

      final parsed = handler.parse(
        r'{"response":"line1\nline2\"quoted\"\u0041',
        isPartial: true,
      );

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals('line1\nline2"quoted"A'));
    });

    test('stops partial response decoding on incomplete escape', () {
      final handler = GenericHandler();

      final parsed = handler.parse(r'''{"response":"hello\''', isPartial: true);

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals('hello'));
    });

    test('keeps invalid JSON as plain content', () {
      final handler = GenericHandler();

      final parsed = handler.parse('weatherlookup');
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals('weatherlookup'));
    });
  });
}
