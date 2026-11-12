@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/thinking_utils.dart';
import 'package:test/test.dart';

const List<String> _fixtures = [
  'test/fixtures/qwen3_coder_parallel_upstream.json',
  'test/fixtures/seed_oss_parallel_upstream.json',
];

final ToolDefinition _tool = ToolDefinition(
  name: 'get_weather',
  description: 'w',
  parameters: [ToolParam.string('location', required: true)],
  handler: (_) async => 'Sunny',
);

List<String> _calls(Iterable<({String? name, String? arguments})> calls) => [
  for (final call in calls) '${call.name} ${jsonDecode(call.arguments!)}',
];

// With parallel tool calls, llama.cpp parses each call of a Qwen3-Coder XML or
// Seed-OSS reply in its own tool-call scope.
void main() {
  for (final fixturePath in _fixtures) {
    final fixture =
        jsonDecode(File(fixturePath).readAsStringSync())
            as Map<String, dynamic>;
    final format = ChatFormat.values.byName(fixture['format'] as String);
    final callTemplate = fixture['call'] as String;
    String call(String location) =>
        callTemplate.replaceFirst('{location}', location);

    for (final entry
        in (fixture['templates'] as List).cast<Map<String, dynamic>>()) {
      final templatePath = entry['template'] as String;
      final enableThinking = entry['enable_thinking'] as bool;
      group('${templatePath.split('/').last}, thinking $enableThinking', () {
        late LlamaChatTemplateResult rendered;

        setUpAll(
          () => rendered = ChatTemplateEngine.render(
            templateSource: File(templatePath).readAsStringSync(),
            messages: [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: fixture['user_prompt'] as String,
              ),
            ],
            metadata: const {},
            tools: [_tool],
            parallelToolCalls: true,
            enableThinking: enableThinking,
          ),
        );

        for (final c in (entry['cases'] as List).cast<Map<String, dynamic>>()) {
          final cities = (c['cities'] as List).cast<String>();
          final output =
              '${c['prefix']}'
              '${cities.map(call).join(c['separator'] as String)}'
              '${c['suffix']}';
          final upstream = c['upstream'] as Map<String, dynamic>;
          final upstreamCalls = _calls([
            for (final call
                in (upstream['tool_calls'] as List)
                    .cast<Map<String, dynamic>>())
              (
                name: call['name'] as String,
                arguments: call['arguments'] as String,
              ),
          ]);
          test(
            '${cities.length} calls after ${jsonEncode(c['prefix'])}, '
            'separated by ${jsonEncode(c['separator'])}, then '
            '${jsonEncode(c['suffix'])}, parse and stream as llama.cpp parses',
            () async {
              expect(rendered.format, format.index);
              final thinkingForcedClosed =
                  !rendered.thinkingForcedOpen &&
                  thinkingForcedClosedOf(rendered);
              final parsed = ChatTemplateEngine.parse(
                rendered.format,
                output,
                thinkingForcedOpen: rendered.thinkingForcedOpen,
                thinkingForcedClosed: thinkingForcedClosed,
                tools: [_tool],
              );
              // llamadart trims some whitespace around content and reasoning
              // that llama.cpp keeps.
              expect(
                parsed.content.trim(),
                (upstream['content'] as String).trim(),
              );
              expect(
                (parsed.reasoningContent ?? '').trim(),
                (upstream['reasoning_content'] as String).trim(),
              );
              expect(
                _calls([
                  for (final call in parsed.toolCalls)
                    (
                      name: call.function?.name,
                      arguments: call.function?.arguments,
                    ),
                ]),
                upstreamCalls,
              );

              for (final tokens in [
                [output],
                output.split(''),
                [
                  for (var i = 0; i < output.length; i += 3)
                    output.substring(
                      i,
                      i + 3 > output.length ? output.length : i + 3,
                    ),
                ],
              ]) {
                final chunks = await ChatCompletionStreamParser.parse(
                  tokenStream: Stream.fromIterable(tokens),
                  templateResult: rendered,
                  parseToolCallsEnabled: true,
                  enableThinking: enableThinking,
                  modelName: 'test-model',
                  completionId: 'xml-parallel-upstream',
                  tools: [_tool],
                ).toList();
                final deltas = chunks.map(
                  (chunk) => chunk.choices.single.delta,
                );
                final reason = '${tokens.length} tokens';
                expect(
                  deltas.map((delta) => delta.content ?? '').join().trim(),
                  (upstream['content'] as String).trim(),
                  reason: reason,
                );
                expect(
                  deltas.map((delta) => delta.thinking ?? '').join().trim(),
                  (upstream['reasoning_content'] as String).trim(),
                  reason: reason,
                );
                expect(
                  _calls([
                    for (final delta in deltas)
                      for (final call in delta.toolCalls ?? const [])
                        (
                          name: call.function?.name,
                          arguments: call.function?.arguments,
                        ),
                  ]),
                  upstreamCalls,
                  reason: reason,
                );
              }
            },
          );
        }
      });
    }
  }
}
