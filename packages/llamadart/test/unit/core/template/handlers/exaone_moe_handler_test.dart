import 'dart:convert';

import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/exaone_moe_handler.dart';
import 'package:test/test.dart';

void main() {
  test('ExaoneMoeHandler exposes chat format', () {
    final handler = ExaoneMoeHandler();
    expect(handler.format, isA<ChatFormat>());
  });

  test('ExaoneMoeHandler parses tool calls from tagged JSON blocks', () {
    final handler = ExaoneMoeHandler();

    final parsed = handler.parse(
      '<tool_call>{"name":"get_weather","arguments":{"city":"Seoul"}}</tool_call> tail',
    );

    expect(parsed.content, 'tail');
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, 'get_weather');
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });

  test('ExaoneMoeHandler parses nested function payloads in code fences', () {
    final handler = ExaoneMoeHandler();

    final parsed = handler.parse(
      '<tool_call>```json\n'
      '{"id":"call_1","function":{"name":"get_weather","arguments":{"city":"Seoul"}}}\n'
      '```</tool_call>',
    );

    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.id, 'call_1');
    expect(parsed.toolCalls.first.function?.name, 'get_weather');
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });

  test('ExaoneMoeHandler keeps malformed tool blocks as content', () {
    final handler = ExaoneMoeHandler();
    const input = '<tool_call>{"arguments":{"city":"Seoul"}}</tool_call>';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });
}
