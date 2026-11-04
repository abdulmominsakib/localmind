import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/command_r7b_handler.dart';
import 'package:test/test.dart';

void main() {
  test('CommandR7BHandler renders and parses command-r tool calls', () {
    final handler = CommandR7BHandler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}<|START_THINKING|>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
      enableThinking: false,
    );

    expect(rendered.prompt, endsWith('<|END_THINKING|>\n'));
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammarLazy, isTrue);
    expect(rendered.additionalStops, contains('<|END_ACTION|>'));
    expect(rendered.grammarTriggers.map((trigger) => trigger.value), [
      '<|START_ACTION|>',
    ]);

    final parsed = handler.parse(
      '<|START_THINKING|>reasoning<|END_THINKING|>'
      'answer '
      '<|START_ACTION|>[{"tool_name":"get_weather","parameters":{"city":"Seoul"}}]<|END_ACTION|>',
    );

    expect(parsed.reasoningContent, contains('reasoning'));
    expect(parsed.content, equals('answer'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );

    final noToolParse = handler.parse(
      '<|START_ACTION|>[{"tool_name":"noop","parameters":{}}]<|END_ACTION|>',
      parseToolCalls: false,
    );
    expect(noToolParse.toolCalls, isEmpty);
    expect(noToolParse.content, contains('<|START_ACTION|>'));

    final noToolTextParse = handler.parse(
      '<|START_THINKING|>reasoning<|END_THINKING|>'
      '<|START_TEXT|>plain answer<|END_TEXT|>',
      parseToolCalls: false,
    );
    expect(noToolTextParse.reasoningContent, equals('reasoning'));
    expect(noToolTextParse.content, equals('plain answer'));
    expect(noToolTextParse.toolCalls, isEmpty);
  });

  test('parses action block with whitespace before end marker', () {
    final handler = CommandR7BHandler();
    final parsed = handler.parse(
      '<|START_ACTION|>[{"tool_name":"get_weather","parameters":{"city":"Seoul"}}]\n<|END_ACTION|>',
    );

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });

  test('parses North/Cohere single-object action block', () {
    final handler = CommandR7BHandler();
    final parsed = handler.parse(
      '<|START_ACTION|>{"tool_call_id":"0","tool_name":"inspect_project","parameters":{}}<|END_ACTION|>',
    );

    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.id, equals('0'));
    expect(parsed.toolCalls.first.function?.name, equals('inspect_project'));
    expect(jsonDecode(parsed.toolCalls.first.function!.arguments!), isEmpty);
  });

  test('parses bare North/Cohere action arrays', () {
    final handler = CommandR7BHandler();
    final parsed = handler.parse(
      '[{"tool_name":"inspect_project","parameters":{}}]',
    );

    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('inspect_project'));
    expect(jsonDecode(parsed.toolCalls.first.function!.arguments!), isEmpty);
  });

  test('parses trailing North/Cohere action arrays after prelude text', () {
    final handler = CommandR7BHandler();
    final parsed = handler.parse(
      'I should inspect first.[{"tool_name":"inspect_project","parameters":{}}]',
    );

    expect(parsed.content, equals('I should inspect first.'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('inspect_project'));
    expect(jsonDecode(parsed.toolCalls.first.function!.arguments!), isEmpty);
  });

  test('parses trailing action arrays after earlier bracketed text', () {
    final handler = CommandR7BHandler();
    final parsed = handler.parse(
      'Review [workspace] first.'
      '[{"tool_name":"inspect_project","parameters":{"paths":["lib","test"]}}]',
    );

    expect(parsed.content, equals('Review [workspace] first.'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('inspect_project'));
    expect(jsonDecode(parsed.toolCalls.first.function!.arguments!), {
      'paths': ['lib', 'test'],
    });
  });

  test('keeps bare single-object action-like JSON as content', () {
    final handler = CommandR7BHandler();
    const input =
        'Use this object as an example: {"tool_name":"inspect_project","parameters":{}}';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });

  test('parses Cohere2 MoE START_TEXT content after thinking', () {
    final handler = CommandR7BHandler();
    final parsed = handler.parse(
      'I am thinking<|END_THINKING|><|START_TEXT|>Hello, world!\nWhat\'s up?<|END_TEXT|>',
    );

    expect(parsed.reasoningContent, equals('I am thinking'));
    expect(parsed.content, equals('Hello, world!\nWhat\'s up?'));
    expect(parsed.toolCalls, isEmpty);
  });

  test('preserves prelude spacing before Cohere2 MoE START_TEXT content', () {
    final handler = CommandR7BHandler();
    final parsed = handler.parse('Summary: <|START_TEXT|>all set<|END_TEXT|>');

    expect(parsed.content, equals('Summary: all set'));
    expect(parsed.toolCalls, isEmpty);
  });

  test('parses Cohere2 MoE START_TEXT content when tools are available', () {
    final handler = CommandR7BHandler();
    final parsed = handler.parse(
      '<|END_THINKING|><|START_TEXT|>No tool needed.<|END_TEXT|>',
    );

    expect(parsed.reasoningContent, isNull);
    expect(parsed.content, equals('No tool needed.'));
    expect(parsed.toolCalls, isEmpty);
  });

  test('grammar emits North/Cohere array-shaped action blocks', () {
    final handler = CommandR7BHandler();
    final tools = [
      ToolDefinition(
        name: 'inspect_project',
        description: 'Inspect project',
        parameters: const [],
        handler: _noop,
      ),
    ];

    final grammar = handler.buildGrammar(tools)!;

    expect(grammar, contains('"<|START_ACTION|>"'));
    expect(grammar, contains('action-array ::= "["'));
    expect(grammar, contains('| action-array'));
    expect(grammar, contains('"["'));
    expect(grammar, contains('tool_name'));
    expect(grammar, contains('inspect_project'));
    expect(grammar, contains('"<|END_ACTION|>"'));
  });

  test('grammar preserves required tool argument properties', () {
    final handler = CommandR7BHandler();
    final tools = [
      ToolDefinition(
        name: 'write_file',
        description: 'Write file',
        parameters: [
          ToolParam.string('path', required: true),
          ToolParam.string('content', required: true),
        ],
        handler: _noop,
      ),
    ];

    final grammar = handler.buildGrammar(tools)!;

    expect(grammar, contains('write-file-args ::= "{"'));
    expect(grammar, contains('"\\"path\\": " space string'));
    expect(grammar, contains('"\\"content\\": " space string'));
    expect(grammar, isNot(contains('write-file-args ::= "{" space "}"')));
  });

  test('keeps malformed action block as content', () {
    final handler = CommandR7BHandler();
    const input =
        '<|START_ACTION|>[{"parameters":{"city":"Seoul"}}]<|END_ACTION|>';

    final parsed = handler.parse(input);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, equals(input));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
