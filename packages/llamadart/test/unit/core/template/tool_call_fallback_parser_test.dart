import 'dart:convert';

import 'package:llamadart/src/core/template/tool_call_fallback_parser.dart';
import 'package:test/test.dart';

void main() {
  group('tool_call_fallback_parser', () {
    test('parses JSON array payload', () {
      final parsed = parseToolCallsFromLooseText(
        '[{"name":"get_weather","arguments":{"city":"Seoul"}}]',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        containsPair('city', 'Seoul'),
      );
      expect(parsed.content, isEmpty);
    });

    test('parses loose JSON object with unquoted name', () {
      final parsed = parseToolCallsFromLooseText(
        '{"name": get_weather, "arguments": {"city": "Seoul"}}',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        containsPair('city', 'Seoul'),
      );
    });

    test('parses function syntax and preserves location argument key', () {
      final parsed = parseToolCallsFromLooseText(
        'weather_tool.get_weather_and_local_time(location="Seoul")',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(
        parsed.toolCalls.first.function?.name,
        equals('weather_tool.get_weather_and_local_time'),
      );
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        containsPair('location', 'Seoul'),
      );
    });

    test('keeps commas inside quoted function argument values', () {
      final parsed = parseToolCallsFromLooseText(
        "send_note(to='Alice', body='hello, world')",
      );

      expect(parsed.toolCalls, hasLength(1));
      final args = jsonDecode(parsed.toolCalls.first.function!.arguments!);
      expect(args, containsPair('to', 'Alice'));
      expect(args, containsPair('body', 'hello, world'));
    });

    test('does not coerce bare weather-like alias', () {
      final parsed = parseToolCallsFromLooseText('weatherlookup');

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals('weatherlookup'));
    });

    test('preserves explicit location key from json arguments', () {
      final parsed = parseToolCallsFromLooseText(
        '{"name":"weather_lookup","arguments":{"location":"Seoul"}}',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('weather_lookup'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        containsPair('location', 'Seoul'),
      );
    });

    test('parses semicolon-separated JSON tool objects', () {
      final parsed = parseToolCallsFromLooseText(
        '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}; '
        '{"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
      );

      expect(parsed.toolCalls, hasLength(2));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(parsed.toolCalls.last.function?.name, equals('get_time'));
    });

    test('parses nested function.parameters object', () {
      final parsed = parseToolCallsFromLooseText(
        '{"type":"function","function":{"name":"get_weather","parameters":{"city":"Seoul"}}}',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        containsPair('city', 'Seoul'),
      );
    });

    test('parses first JSON object when trailing junk exists', () {
      final parsed = parseToolCallsFromLooseText(
        '{"name":"get_time","arguments":{"city":"Seoul"}}\n\n  }',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_time'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        containsPair('city', 'Seoul'),
      );
    });

    test('decodeToolArgumentsObject extracts first object from mixed text', () {
      final decoded = decodeToolArgumentsObject(
        'before {"city":"Seoul","unit":"celsius"} after',
      );

      expect(decoded, containsPair('city', 'Seoul'));
      expect(decoded, containsPair('unit', 'celsius'));
    });

    test('normalizeFallbackToolArguments unwraps argument containers', () {
      final normalized = normalizeFallbackToolArguments(<String, dynamic>{
        'arguments': <String, dynamic>{'city': 'Seoul'},
      });

      expect(normalized, equals(<String, dynamic>{'city': 'Seoul'}));
    });

    test('parses top-level tool_call object with explicit id', () {
      final parsed = parseToolCallsFromLooseText(
        '{"id":"call_7","tool_call":{"name":"get_weather","arguments":{"city":"Seoul"}}}',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.single.id, 'call_7');
      expect(parsed.toolCalls.single.function?.name, 'get_weather');
      expect(
        jsonDecode(parsed.toolCalls.single.function!.arguments!),
        containsPair('city', 'Seoul'),
      );
    });
  });
}
