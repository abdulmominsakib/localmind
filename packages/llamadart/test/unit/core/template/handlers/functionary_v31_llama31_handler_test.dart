import 'dart:convert';

import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/functionary_v31_llama31_handler.dart';
import 'package:test/test.dart';

void main() {
  group('FunctionaryV31Llama31Handler', () {
    test('exposes chat format', () {
      final handler = FunctionaryV31Llama31Handler();
      expect(handler.format, isA<ChatFormat>());
    });

    test('parses function tags and python fallback', () {
      final handler = FunctionaryV31Llama31Handler();
      final parsed = handler.parse(
        '<function=weather>{"city":"Seoul"}</function><|python_tag|>print("hi")',
      );

      expect(parsed.toolCalls, hasLength(2));
      expect(parsed.toolCalls.first.function?.name, 'weather');
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        containsPair('city', 'Seoul'),
      );
      expect(parsed.toolCalls.last.function?.name, 'python');
      expect(
        jsonDecode(parsed.toolCalls.last.function!.arguments!),
        containsPair('code', 'print("hi")'),
      );
      expect(parsed.content, isEmpty);
    });
  });
}
