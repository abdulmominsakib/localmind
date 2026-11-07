import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/ministral_handler.dart';
import 'package:test/test.dart';

void main() {
  test('MinistralHandler renders and parses ARGS payload', () {
    final handler = MinistralHandler();
    final tools = [
      ToolDefinition(
        name: 'search',
        description: 'Search docs',
        parameters: [ToolParam.string('query', required: true)],
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

    expect(handler.format, equals(ChatFormat.ministral));
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammarLazy, isTrue);
    expect(rendered.additionalStops, contains('[TOOL_CALLS]'));
    expect(rendered.preservedTokens, contains('[ARGS]'));
    expect(rendered.grammarTriggers.first.value, equals('[TOOL_CALLS]'));
    expect(rendered.parser, isNotNull);
    expect(rendered.parser, isNotEmpty);

    final parsed = handler.parse(
      '[TOOL_CALLS]get_weather[ARGS]{"location":"Seoul"}',
    );
    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('location', 'Seoul'),
    );
  });

  test('parses Ministral ARGS with whitespace and nested objects', () {
    final handler = MinistralHandler();
    final parsed = handler.parse(
      '[TOOL_CALLS]query_user[ARGS]\n'
      '{"filter":{"age":{"gte":18},"active":true}}',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('query_user'));
    final args =
        jsonDecode(parsed.toolCalls.first.function!.arguments!)
            as Map<String, dynamic>;
    final filter = args['filter'] as Map<String, dynamic>;
    expect((filter['age'] as Map<String, dynamic>)['gte'], equals(18));
    expect(filter['active'], isTrue);
  });

  test('parses multiple ARGS tool calls and preserves prior content', () {
    final handler = MinistralHandler();
    final parsed = handler.parse(
      '[THINK]t[/THINK]before '
      '[TOOL_CALLS]get_weather[ARGS]{"city":"Seoul"}'
      '[TOOL_CALLS]get_time[ARGS]{"city":"Seoul"}',
    );

    expect(parsed.reasoningContent, equals('t'));
    expect(parsed.content, equals('before'));
    expect(parsed.toolCalls, hasLength(2));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(parsed.toolCalls.last.function?.name, equals('get_time'));
  });

  test('parses bare JSON array tool payload when marker is missing', () {
    final handler = MinistralHandler();
    final parsed = handler.parse(
      '[{"name":"get_weather","arguments":{"city":"Seoul"}}]',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
  });

  test('parses bare name+json payload when marker is missing', () {
    final handler = MinistralHandler();
    final parsed = handler.parse('get_time{"city":"Seoul"}');

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_time'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });

  test('keeps content when ARGS JSON is malformed', () {
    final handler = MinistralHandler();
    const input = '[TOOL_CALLS]get_weather[ARGS]{"city":"Seoul"';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });

  test('keeps content when bare name+json payload has trailing junk', () {
    final handler = MinistralHandler();
    const input = 'get_time{"city":"Seoul"} trailing';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
