import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/gemma_handler.dart';
import 'package:test/test.dart';

void main() {
  group('GemmaHandler', () {
    test('exposes chat format', () {
      final handler = GemmaHandler();
      expect(handler.format, isA<ChatFormat>());
    });

    test('parses args from alias keys', () {
      final handler = GemmaHandler();
      final parsed = handler.parse(
        '{"tool_call":{"name":"get_weather","args":{"city":"Seoul","unit":"celsius"}}}',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, 'get_weather');
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        <String, dynamic>{'city': 'Seoul', 'unit': 'celsius'},
      );
    });

    test('parses inline tool_call fields as arguments', () {
      final handler = GemmaHandler();
      final parsed = handler.parse(
        '{"tool_call":{"name":"get_weather","city":"Seoul","unit":"celsius"}}',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, 'get_weather');
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        <String, dynamic>{'city': 'Seoul', 'unit': 'celsius'},
      );
    });

    test('parses nested function object payload', () {
      final handler = GemmaHandler();
      final parsed = handler.parse(
        '{"tool_call":{"function":{"name":"get_weather","arguments":{"city":"Seoul"}}}}',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, 'get_weather');
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        <String, dynamic>{'city': 'Seoul'},
      );
    });

    test('preserves placeholder tool name from model output', () {
      final handler = GemmaHandler();
      final parsed = handler.parse(
        '{"tool_call":{"name":"call","arguments":{"city":"Seoul","unit":"celsius"}}}',
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, 'call');
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        <String, dynamic>{'city': 'Seoul', 'unit': 'celsius'},
      );
    });

    test('keeps non-json alias text as content', () {
      final handler = GemmaHandler();
      final parsed = handler.parse('weather');

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, 'weather');
    });

    test('keeps fenced tool_code text as content', () {
      final handler = GemmaHandler();
      final parsed = handler.parse(
        '```tool_code\nweather_tool.get_weather_and_local_time(location="Seoul")\n```',
      );

      expect(parsed.toolCalls, isEmpty);
      expect(
        parsed.content,
        '```tool_code\nweather_tool.get_weather_and_local_time(location="Seoul")\n```',
      );
    });

    test('builds wrapped grammar when tools are provided', () {
      final handler = GemmaHandler();
      final rendered = handler.render(
        templateSource: '{{ messages[0]["content"] }}',
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        metadata: const {},
        tools: [
          ToolDefinition(
            name: 'get_weather',
            description: 'Get weather.',
            parameters: [ToolParam.string('city', required: true)],
            handler: _noop,
          ),
        ],
      );

      expect(rendered.grammar, isNotNull);
      expect(rendered.grammar, contains('tool_call'));
      expect(rendered.grammarLazy, isFalse);
    });
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
