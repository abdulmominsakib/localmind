import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/kimi_k2_handler.dart';
import 'package:test/test.dart';

void main() {
  group('KimiK2Handler', () {
    test('parses regular content', () {
      const output = 'Hello, world!\nWhat\'s up?';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.content, equals('Hello, world!\nWhat\'s up?'));
      expect(result.reasoningContent, isNull);
      expect(result.toolCalls, isEmpty);
    });

    test('parses content with thinking block', () {
      const output = '<think>I\'m\nthinking</think>Hello, world!\nWhat\'s up?';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.content, equals('Hello, world!\nWhat\'s up?'));
      expect(result.reasoningContent, equals('I\'m\nthinking'));
      expect(result.toolCalls, isEmpty);
    });

    test('parses tool call with prefixed/indexed function name', () {
      const output =
          '<|tool_calls_section_begin|><|tool_call_begin|>functions.special_function:0<|tool_call_argument_begin|>{"arg1": 1}<|tool_call_end|><|tool_calls_section_end|>';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.content, isEmpty);
      expect(result.reasoningContent, isNull);
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('special_function'));
      expect(
        jsonDecode(result.toolCalls.first.function!.arguments!),
        equals({'arg1': 1}),
      );
    });

    test('keeps non-matching function name format unchanged', () {
      const output =
          '<|tool_calls_section_begin|><|tool_call_begin|>functions.special_function<|tool_call_argument_begin|>{"arg1": 1}<|tool_call_end|><|tool_calls_section_end|>';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.toolCalls, hasLength(1));
      expect(
        result.toolCalls.first.function?.name,
        equals('functions.special_function'),
      );
    });

    test('parses thinking, tool call, and trailing content together', () {
      const output =
          '<think>I\'m\nthinking</think><|tool_calls_section_begin|><|tool_call_begin|>functions.special_function:0<|tool_call_argument_begin|>{"arg1": 1}<|tool_call_end|><|tool_calls_section_end|>Hello, world!\nWhat\'s up?';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.content, equals('Hello, world!\nWhat\'s up?'));
      expect(result.reasoningContent, equals('I\'m\nthinking'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('special_function'));
    });

    test('parses tool call located inside think block', () {
      const output =
          '<think>I\'m thinking<|tool_calls_section_begin|><|tool_call_begin|>functions.complex_function_in_think:0<|tool_call_argument_begin|>{"name":"John Doe","age":30}<|tool_call_end|><|tool_calls_section_end|>I\'m still thinking</think>Hello';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.content, equals('Hello'));
      expect(
        result.reasoningContent,
        equals('I\'m thinkingI\'m still thinking'),
      );
      expect(result.toolCalls, hasLength(1));
      expect(
        result.toolCalls.first.function?.name,
        equals('complex_function_in_think'),
      );
      expect(
        jsonDecode(result.toolCalls.first.function!.arguments!),
        equals({'name': 'John Doe', 'age': 30}),
      );
    });

    test('parses multiple tool calls in one section', () {
      const output =
          '<|tool_calls_section_begin|>'
          '<|tool_call_begin|>functions.read_file:0<|tool_call_argument_begin|>{"path":"a.txt"}<|tool_call_end|>'
          '<|tool_call_begin|>functions.web_search:1<|tool_call_argument_begin|>{"query":"weather"}<|tool_call_end|>'
          '<|tool_calls_section_end|>';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.content, isEmpty);
      expect(result.toolCalls, hasLength(2));
      expect(result.toolCalls[0].function?.name, equals('read_file'));
      expect(result.toolCalls[1].function?.name, equals('web_search'));
      expect(
        jsonDecode(result.toolCalls[0].function!.arguments!),
        equals({'path': 'a.txt'}),
      );
      expect(
        jsonDecode(result.toolCalls[1].function!.arguments!),
        equals({'query': 'weather'}),
      );
    });

    test('parses partial stream without call end token', () {
      const output =
          '<|tool_calls_section_begin|><|tool_call_begin|>functions.weather:0<|tool_call_argument_begin|>{"city":"Seoul"}';

      final result = ChatTemplateEngine.parse(
        ChatFormat.kimiK2.index,
        output,
        isPartial: true,
      );

      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
      expect(
        jsonDecode(result.toolCalls.first.function!.arguments!),
        equals({'city': 'Seoul'}),
      );
    });

    test('keeps partial arguments when JSON object is incomplete', () {
      const output =
          '<|tool_calls_section_begin|><|tool_call_begin|>functions.weather:0<|tool_call_argument_begin|>{"city":"Seo';

      final result = ChatTemplateEngine.parse(
        ChatFormat.kimiK2.index,
        output,
        isPartial: true,
      );

      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
      expect(
        result.toolCalls.first.function?.arguments,
        equals('{"city":"Seo'),
      );
    });

    test('keeps malformed completed tool section as content', () {
      const output =
          '<|tool_calls_section_begin|><|tool_call_begin|>functions.weather:0<|tool_call_argument_begin|>{"city":"Seoul"<|tool_calls_section_end|>';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.toolCalls, isEmpty);
      expect(result.content, equals(output));
    });

    test('keeps entire scope as content when later tool call is malformed', () {
      const output =
          '<|tool_calls_section_begin|>'
          '<|tool_call_begin|>functions.read_file:0<|tool_call_argument_begin|>{"path":"a.txt"}<|tool_call_end|>'
          '<|tool_call_begin|>functions.weather:1<|tool_call_argument_begin|>{"city":"Seoul"<|tool_calls_section_end|>';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.toolCalls, isEmpty);
      expect(result.content, equals(output));
    });

    test('renders tool grammar for Kimi-K2 tool calls', () {
      final handler = KimiK2Handler();
      final tools = [
        ToolDefinition(
          name: 'weather',
          description: 'Weather lookup',
          parameters: [ToolParam.string('city', required: true)],
          handler: _noop,
        ),
      ];

      final rendered = handler.render(
        templateSource: '{{ messages[0]["content"] }}',
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        metadata: const {},
        tools: tools,
      );

      expect(rendered.grammar, isNotNull);
      expect(rendered.grammar, contains('"<|tool_calls_section_begin|>"'));
      expect(rendered.grammarTriggers, isNotEmpty);
      expect(
        rendered.grammarTriggers.first.value,
        equals('<|tool_calls_section_begin|><|tool_call_begin|>'),
      );
    });
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
