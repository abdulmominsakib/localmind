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
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

final Map<String, dynamic> _fixture =
    jsonDecode(
          File(
            'test/fixtures/seed_oss_tool_call_upstream.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

final List<ToolDefinition> _tools = [
  ToolDefinition(
    name: 'get_weather',
    description: 'w',
    parameters: [ToolParam.string('location', required: true)],
  ),
];

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
) async {
  final chunks = await ChatCompletionStreamParser.parse(
    tokenStream: Stream.fromIterable(tokens),
    templateResult: rendered,
    parseToolCallsEnabled: true,
    enableThinking: true,
    modelName: 'test-model',
    completionId: 'seed-oss-tool-call-upstream',
    tools: _tools,
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

// llama.cpp takes the complete call of a finished Seed-OSS reply that ends
// inside its last scope, drops a scope that ends before its call does, and
// keeps a declared string value as generated.
void main() {
  test('the fixture declares the tools of the test', () {
    expect(_fixture['tools'], [
      for (final tool in _tools) jsonDecode(jsonEncode(tool.toJson())),
    ]);
  });

  for (final entry
      in (_fixture['templates'] as List).cast<Map<String, dynamic>>()) {
    final templatePath = entry['template'] as String;
    final enableThinking = entry['enable_thinking'] as bool;
    final parallelToolCalls = entry['parallel_tool_calls'] as bool;
    final toolChoice = ToolChoice.values.byName(
      entry['tool_choice'] as String? ?? 'auto',
    );
    group('${templatePath.split('/').last}, thinking $enableThinking, '
        'parallel $parallelToolCalls, ${toolChoice.name}', () {
      late LlamaChatTemplateResult rendered;

      setUpAll(
        () => rendered = ChatTemplateEngine.render(
          templateSource: File(templatePath).readAsStringSync(),
          messages: [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: _fixture['user_prompt'] as String,
            ),
          ],
          metadata: const {},
          tools: _tools,
          toolChoice: toolChoice,
          parallelToolCalls: parallelToolCalls,
          enableThinking: enableThinking,
        ),
      );

      for (final c in (entry['cases'] as List).cast<Map<String, dynamic>>()) {
        final output = c['output'] as String;
        test('${c['name']} parses and streams as llama.cpp parses', () async {
          expect(rendered.format, ChatFormat.seedOss.index);
          final parsed = _parsed(
            ChatTemplateEngine.parseRendered(rendered, output, tools: _tools),
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
                  tools: _tools,
                ),
              ),
              _upstream(upstreamPartial as Map<String, dynamic>),
              reason: 'partial',
            );
          }
          for (final tokens in _chunkings(output)) {
            expect(
              await _streamed(rendered, tokens),
              parsed,
              reason: jsonEncode(tokens),
            );
          }
        });
      }
    });
  }
}
