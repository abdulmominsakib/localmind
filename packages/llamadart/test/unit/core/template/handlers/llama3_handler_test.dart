import 'dart:convert';

import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/llama3_handler.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:test/test.dart';

void main() {
  final messages = [const LlamaChatMessage(role: 'user', content: 'hello')];

  test('returns content-only format when no tools are provided', () {
    final handler = Llama3Handler();
    final result = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: messages,
      metadata: const {},
      tools: const [],
    );

    expect(result.format, ChatFormat.contentOnly.index);
  });

  test('returns builtin-tools format when builtin tools are available', () {
    final handler = Llama3Handler();
    final result = handler.render(
      templateSource:
          '<|start_header_id|>ipython<|end_header_id|><|python_tag|>{{ messages[0]["content"] }}',
      messages: messages,
      metadata: const {},
      tools: [
        ToolDefinition(
          name: 'code_interpreter',
          description: 'Execute Python code',
          parameters: [ToolParam.string('code')],
          handler: _noopHandler,
        ),
      ],
    );

    expect(result.format, ChatFormat.llama3BuiltinTools.index);
    expect(result.grammar, isNull);
  });

  test('returns JSON tool grammar for non-builtin tools', () {
    final handler = Llama3Handler();
    final result = handler.render(
      templateSource:
          '<|start_header_id|>ipython<|end_header_id|>{{ messages[0]["content"] }}',
      messages: messages,
      metadata: const {},
      tools: [
        ToolDefinition(
          name: 'get_weather',
          description: 'Get weather information',
          parameters: [ToolParam.string('city', required: true)],
          handler: _noopHandler,
        ),
      ],
    );

    expect(result.format, ChatFormat.llama3.index);
    expect(result.grammar, isNotNull);
    expect(result.grammar, contains('name-kv'));
    expect(result.grammar, contains('parameters-kv'));
  });

  test('renders date_string in llama.cpp format', () {
    final handler = Llama3Handler();
    final result = handler.render(
      templateSource: '{{ date_string }}',
      messages: messages,
      metadata: {
        internalTemplateNowMetadataKey: DateTime(
          2026,
          2,
          17,
          13,
          5,
          9,
        ).toIso8601String(),
      },
      tools: const [],
    );

    expect(result.prompt, equals('17 Feb 2026'));
  });

  test('parses strict llama3 json tool payload', () {
    final handler = Llama3Handler();

    final strict = handler.parse(
      '{"name":"get_weather","parameters":{"city":"Seoul"}}',
    );
    expect(strict.toolCalls, hasLength(1));
    expect(strict.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(strict.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
    expect(strict.content, isEmpty);

    final semicolon = handler.parse(
      '{"type":"function","name":"get_weather","parameters":{"city":"Seoul"}}; '
      '{"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
    );
    expect(semicolon.toolCalls, hasLength(1));
    expect(semicolon.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(semicolon.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
    expect(
      semicolon.content,
      equals(
        '; {"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
      ),
    );

    final array = handler.parse(
      '[{"name":"get_weather","parameters":{"city":"Seoul"}}]',
    );
    expect(array.toolCalls, isEmpty);
    expect(
      array.content,
      equals('[{"name":"get_weather","parameters":{"city":"Seoul"}}]'),
    );

    final wrongKey = handler.parse(
      '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}',
    );
    expect(wrongKey.toolCalls, isEmpty);
    expect(
      wrongKey.content,
      equals(
        '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}',
      ),
    );
  });

  test('parses builtin python tag calls into tool chunks', () {
    final handler = Llama3Handler();

    final parsed = handler.parse(
      '<|python_tag|>math.call(code="print(1)", retries=2)',
    );

    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('math'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      equals({'code': 'print(1)', 'retries': 2}),
    );
  });

  test('partial parses withhold possible calls and release other text', () {
    final handler = Llama3Handler();
    for (final (output, content) in [
      ('{', ''),
      ('{"na', ''),
      ('{"name": "weather", "param', ''),
      ('{"type":"function","name":"weather"', ''),
      ('{"name":"weather","parameters":{"city":"Par', ''),
      ('{"name":"weather","parameters":{"city":"Paris"}', ''),
      ('{"name":"Bob","age":3', '{"name":"Bob","age":3'),
      ('{"type":"text"', '{"type":"text"'),
      ('{"name":""', '{"name":""'),
      ('Let me check. {"name":"weather"', 'Let me check. {"name":"weather"'),
      ('Let me check.\n<|python_', 'Let me check.\n'),
      (
        'Let me check.\n<|python_tag|>code_interpreter.call(',
        'Let me check.\n',
      ),
      ('Hi <|python_tag|>print(1)', 'Hi '),
      ('{"name":\u00a0"weather","param', ''),
    ]) {
      final parsed = handler.parse(output, isPartial: true);
      expect(parsed.content, content, reason: output);
      expect(parsed.toolCalls, isEmpty, reason: output);
    }
  });

  test('final parses keep unfinished calls as content', () {
    final handler = Llama3Handler();
    for (final output in [
      '{"name":"weather","parameters":{"city":"Par',
      '{"name":"weather","parameters":{"city":"Paris"}',
      'Hi <|python_tag|>print(1)',
      'Let me check.\n<|python_',
    ]) {
      final parsed = handler.parse(output);
      expect(parsed.content, output, reason: output);
      expect(parsed.toolCalls, isEmpty, reason: output);
    }
  });

  test('parses typed function envelopes', () {
    final parsed = Llama3Handler().parse(
      '{"type":"function","name":"weather","parameters":{"city":"Paris"}}\n'
      'Done.',
    );
    expect(parsed.content, 'Done.');
    expect(parsed.toolCalls.single.function?.name, 'weather');
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
      'city': 'Paris',
    });
  });
}

Future<Object?> _noopHandler(_) async {
  return null;
}
