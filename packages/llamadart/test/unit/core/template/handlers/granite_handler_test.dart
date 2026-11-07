import 'dart:convert';

import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/granite_handler.dart';
import 'package:test/test.dart';

void main() {
  test('GraniteHandler exposes chat format', () {
    final handler = GraniteHandler();
    expect(handler.format, isA<ChatFormat>());
  });

  test('parses tool-call array with whitespace after marker', () {
    final handler = GraniteHandler();
    final parsed = handler.parse(
      '<|tool_call|>\n[{"name":"weather","arguments":{"city":"Seoul"}}]',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );

    final malformed = handler.parse(
      '<|tool_call|>[{"arguments":{"city":"Seoul"}}]',
    );
    expect(malformed.toolCalls, isEmpty);
    expect(
      malformed.content,
      equals('<|tool_call|>[{"arguments":{"city":"Seoul"}}]'),
    );
  });
}
