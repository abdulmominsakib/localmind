import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/command_r7b_handler.dart';
import 'package:llamadart/src/core/template/tool_call_grammar_utils.dart';
import 'package:test/test.dart';

void main() {
  test('CommandR7BHandler.toolCallOpening finds markers and bare arrays', () {
    for (final opening in const [
      '<|START_ACTION|>',
      '<|START_TEXT|>',
      '<|START_RESPONSE|>',
      '[{',
      '[ \n{',
      '[',
      '[ ',
    ]) {
      expect(CommandR7BHandler.toolCallOpening('Hi $opening'), 3);
    }
    expect(CommandR7BHandler.toolCallOpening('Hi <|START_'), 3);
    expect(CommandR7BHandler.toolCallOpening('Use [x] or [1, {}].'), 19);
  });

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

    expect(rendered.prompt, endsWith('<|START_THINKING|><|END_THINKING|>'));
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

  test('parses a trailing action array whose strings hold brackets', () {
    final handler = CommandR7BHandler();
    final parsed = handler.parse(
      'See [1] "quoted [" here.'
      r'[{"tool_name":"echo","parameters":{"text":"a [\"b\"] \\ ]["}}]',
    );

    expect(parsed.content, equals('See [1] "quoted [" here.'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.single.function?.name, equals('echo'));
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
      'text': r'a ["b"] \ ][',
    });
  });

  test('scans string and escape state backward in a bare action array', () {
    final handler = CommandR7BHandler();

    final escapedQuote = handler.parse(
      r'[{"tool_name":"a","parameters":{"x":"[[[\""}}]',
    );
    expect(escapedQuote.toolCalls, hasLength(1));
    expect(escapedQuote.toolCalls.single.function?.name, equals('a'));
    expect(jsonDecode(escapedQuote.toolCalls.single.function!.arguments!), {
      'x': '[[["',
    });

    final bracketString = handler.parse(
      '[{"tool_name":"a","parameters":{"x":"["}}]',
    );
    expect(bracketString.toolCalls, hasLength(1));
    expect(bracketString.toolCalls.single.function?.name, equals('a'));
    expect(jsonDecode(bracketString.toolCalls.single.function!.arguments!), {
      'x': '[',
    });

    final leadingQuote = handler.parse(
      'p " [{"tool_name":"a","parameters":{}}]',
    );
    expect(leadingQuote.content, equals('p "'));
    expect(leadingQuote.toolCalls, hasLength(1));
    expect(leadingQuote.toolCalls.single.function?.name, equals('a'));
    expect(
      jsonDecode(leadingQuote.toolCalls.single.function!.arguments!),
      isEmpty,
    );
  });

  test('keeps trailing bracketed text that is not an action array', () {
    final handler = CommandR7BHandler();
    for (final input in const [
      '[{"tool_name":"echo","parameters":{}}] then [1]',
      '[{"tool_name":"echo","parameters":{}}] then []',
      '[{"tool_name":"echo","parameters":{}}]]',
      '[{"tool_name":"echo","parameters":{"text":"]"}]',
      '"[{"tool_name":"echo","parameters":{}}]"',
    ]) {
      final parsed = handler.parse(input);

      expect(parsed.toolCalls, isEmpty, reason: input);
      expect(parsed.content, equals(input), reason: input);
    }
  });

  test('scans deeply nested bracket output in linear time', () {
    // Rescanning from every bracket took about 30 s per input at this depth;
    // one pass takes milliseconds, so the bound leaves a wide margin both ways.
    // A test timeout cannot interrupt synchronous parsing, hence the stopwatch.
    const depth = 40000;
    final handler = CommandR7BHandler();
    final stopwatch = Stopwatch()..start();
    for (final input in [
      '${'[' * depth}${']' * depth}',
      '${'[' * depth}${']' * depth} done',
      '[{"tool_name":"echo","parameters":{}}] ${'[' * depth}${']' * depth}',
    ]) {
      final parsed = handler.parse(input);

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, equals(input));
    }
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
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

  test('parses START_RESPONSE content with or without tool parsing and with '
      'its end tag cut by a stop', () {
    final handler = CommandR7BHandler();
    for (final output in const [
      '<|START_THINKING|>plan<|END_THINKING|>'
          '<|START_RESPONSE|>Hello<|END_RESPONSE|>',
      '<|START_THINKING|>plan<|END_THINKING|><|START_RESPONSE|>Hello',
    ]) {
      for (final parseToolCalls in [true, false]) {
        final parsed = handler.parse(output, parseToolCalls: parseToolCalls);

        expect(parsed.reasoningContent, 'plan');
        expect(parsed.content, 'Hello');
      }
    }
  });

  // llama.cpp (`620d2225`) rejects text before the marker; the parse keeps it
  // rather than lose it.
  test('keeps text before START_RESPONSE in the content', () {
    const input = 'Hello <|START_RESPONSE|>Answer<|END_RESPONSE|>';
    for (final parseToolCalls in [true, false]) {
      final parsed = CommandR7BHandler().parse(
        input,
        parseToolCalls: parseToolCalls,
      );

      expect(parsed.content, 'Hello Answer', reason: '$parseToolCalls');
    }
  });

  test('keeps START_RESPONSE output with trailing text as content', () {
    const input = '<|START_RESPONSE|>Hello<|END_RESPONSE|>more';
    final parsed = CommandR7BHandler().parse(input, parseToolCalls: false);

    expect(parsed.content, input);
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
    final writeFileRule = ToolCallGrammarUtils.ruleName('write_file');

    expect(grammar, contains('$writeFileRule-args ::= "{"'));
    expect(grammar, contains('"\\"path\\": " space string'));
    expect(grammar, contains('"\\"content\\": " space string'));
    expect(grammar, isNot(contains('$writeFileRule-args ::= "{" space "}"')));
  });

  test('collision-free grammar rules preserve Command R wire names', () {
    final handler = CommandR7BHandler();
    final tools = [_tool('a b'), _tool('a-b')];
    final spacedRule = ToolCallGrammarUtils.ruleName('a b');
    final dashedRule = ToolCallGrammarUtils.ruleName('a-b');

    expect(spacedRule, isNot(dashedRule));
    final grammar = handler.buildGrammar(tools)!;
    expect(grammar, contains('$spacedRule-call ::='));
    expect(grammar, contains('$dashedRule-call ::='));
    expect(grammar, contains(r'\"tool_name\": \"a b\"'));
    expect(grammar, contains(r'\"tool_name\": \"a-b\"'));

    const output =
        'before '
        '<|START_ACTION|>[{"tool_name":"a b","parameters":{}}]'
        '<|END_ACTION|>';
    final parsed = handler.parse(output);
    expect(parsed.content, 'before');
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.single.function?.name, 'a b');
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), isEmpty);
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

ToolDefinition _tool(String name) => ToolDefinition(
  name: name,
  description: 'Collision coverage',
  parameters: const [],
  handler: _noop,
);
