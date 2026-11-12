@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/ling3_handler.dart';
import 'package:test/test.dart';

import '../../../support/ling3_tools.dart';

final Map<String, dynamic> _fixture =
    jsonDecode(
          File(
            'test/fixtures/ling3_tool_call_upstream.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

typedef _Message = Map<String, Object>;

List<String> _calls(Iterable<({String? name, String? arguments})> calls) => [
  for (final call in calls) '${call.name} ${jsonDecode(call.arguments!)}',
];

// llamadart trims some whitespace around content and reasoning that llama.cpp
// keeps.
_Message _upstream(Map<String, dynamic> message) => {
  'content': (message['content'] as String).trim(),
  'reasoning': (message['reasoning_content'] as String).trim(),
  'calls': _calls([
    for (final call
        in (message['tool_calls'] as List).cast<Map<String, dynamic>>())
      (name: call['name'] as String, arguments: call['arguments'] as String),
  ]),
};

_Message _parsed(ChatParseResult parsed) => {
  'content': parsed.content.trim(),
  'reasoning': (parsed.reasoningContent ?? '').trim(),
  'calls': _calls([
    for (final call in parsed.toolCalls)
      (name: call.function?.name, arguments: call.function?.arguments),
  ]),
};

/// [output] whole, bytewise, in 3-character chunks and split in two at every
/// point.
List<List<String>> _chunkings(String output) => [
  [output],
  output.split(''),
  [
    for (var i = 0; i < output.length; i += 3)
      output.substring(i, i + 3 > output.length ? output.length : i + 3),
  ],
  for (var split = 1; split < output.length; split++)
    [output.substring(0, split), output.substring(split)],
];

Future<_Message> _streamed(
  LlamaChatTemplateResult rendered,
  List<String> tokens,
  List<ToolDefinition> tools,
  bool parseToolCalls,
) async {
  final chunks = await ChatCompletionStreamParser.parse(
    tokenStream: Stream.fromIterable(tokens),
    templateResult: rendered,
    parseToolCallsEnabled: parseToolCalls,
    enableThinking: true,
    modelName: 'test-model',
    completionId: 'ling3-tool-call-upstream',
    tools: tools,
  ).toList();
  final deltas = chunks.map((chunk) => chunk.choices.single.delta).toList();
  return {
    'content': deltas.map((delta) => delta.content ?? '').join().trim(),
    'reasoning': deltas.map((delta) => delta.thinking ?? '').join().trim(),
    'calls': _calls([
      for (final delta in deltas)
        for (final call in delta.toolCalls ?? const [])
          (name: call.function?.name, arguments: call.function?.arguments),
    ]),
  };
}

LlamaChatTemplateResult _render(
  Map<String, dynamic> entry,
  List<ToolDefinition> tools, {
  required bool viaHandler,
}) {
  final choice = ToolChoice.values.byName(
    entry['tool_choice'] as String? ?? 'auto',
  );
  final parallel = entry['parallel_tool_calls'] as bool;
  final enableThinking = entry['enable_thinking'] as bool;
  final templateSource = File(
    _fixture['template'] as String,
  ).readAsStringSync();
  final messages = [
    LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: _fixture['user_prompt'] as String,
    ),
  ];
  if (!viaHandler) {
    return ChatTemplateEngine.render(
      templateSource: templateSource,
      messages: messages,
      metadata: const {},
      tools: tools,
      toolChoice: choice,
      parallelToolCalls: parallel,
      enableThinking: enableThinking,
    );
  }
  return Ling3Handler().render(
    templateSource: templateSource,
    messages: messages,
    metadata: {
      'llamadart.internal.tool_choice': choice.name,
      'llamadart.internal.parallel_tool_calls': '$parallel',
    },
    tools: tools,
    enableThinking: enableThinking,
  );
}

void _cases(
  String section,
  List<dynamic> entries,
  List<ToolDefinition> tools, {
  required bool viaHandler,
}) {
  for (final entry in entries.cast<Map<String, dynamic>>()) {
    final choice = entry['tool_choice'] as String? ?? 'auto';
    final enableThinking = entry['enable_thinking'] as bool;
    final parallel = entry['parallel_tool_calls'] as bool;
    final parseToolCalls = choice != 'none';
    group('$section thinking $enableThinking, parallel $parallel, $choice', () {
      late LlamaChatTemplateResult rendered;

      setUpAll(() => rendered = _render(entry, tools, viaHandler: viaHandler));

      test('renders the prompt and stops as llama.cpp does', () {
        expect(rendered.format, ChatFormat.ling3.index);
        expect(rendered.thinkingForcedOpen, enableThinking);
        expect(rendered.additionalStops, _fixture['additional_stops']);
        if (parseToolCalls) {
          expect(rendered.prompt, entry['prompt']);
          expect(rendered.grammarLazy, entry['grammar_lazy']);
          expect(rendered.preservedTokens, _fixture['preserved_tokens']);
          expect(
            rendered.grammarTriggers.map((trigger) => trigger.value),
            choice == 'required' ? isEmpty : _fixture['grammar_triggers'],
          );
        }
      });

      for (final c in (entry['cases'] as List).cast<Map<String, dynamic>>()) {
        final output = c['output'] as String;
        test('${c['name']} parses and streams as llama.cpp parses', () async {
          final parsed = _parsed(
            ChatTemplateEngine.parseRendered(
              rendered,
              output,
              parseToolCalls: parseToolCalls,
              tools: tools,
            ),
          );
          expect(
            parsed,
            _upstream(c['upstream'] as Map<String, dynamic>),
            reason: 'finished',
          );
          final upstreamPartial = c['upstream_partial'];
          if (upstreamPartial != null) {
            expect(
              _parsed(
                ChatTemplateEngine.parseRendered(
                  rendered,
                  output,
                  isPartial: true,
                  parseToolCalls: parseToolCalls,
                  tools: tools,
                ),
              ),
              _upstream(upstreamPartial as Map<String, dynamic>),
              reason: 'partial',
            );
          }
          for (final tokens in _chunkings(output)) {
            expect(
              await _streamed(rendered, tokens, tools, parseToolCalls),
              parsed,
              reason: jsonEncode(tokens),
            );
          }
        });
      }
    });
  }
}

// llama.cpp ends a forced-open thought at `</think>` or `<tool_call>`, takes a
// call only from a declared tool with its arguments in the grammar's order,
// and keeps every other `<tool_call>` as content.
void main() {
  test('the fixture declares the tools of the test', () {
    expect(_fixture['tools'], [
      for (final tool in ling3Tools) jsonDecode(jsonEncode(tool.toJson())),
    ]);
    expect(_fixture['schema_tools'], [
      for (final tool in ling3SchemaTools)
        jsonDecode(jsonEncode(tool.toJson())),
    ]);
  });

  _cases('', _fixture['templates'] as List, ling3Tools, viaHandler: false);
  _cases(
    'schema tools,',
    _fixture['schema_templates'] as List,
    ling3SchemaTools,
    viaHandler: true,
  );
}
