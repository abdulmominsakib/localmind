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
            'test/fixtures/forced_open_thought_upstream.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'weather',
  description: 'w',
  parameters: [ToolParam.string('city', required: true)],
  handler: (_) async => 'Sunny',
);

List<String> _calls(Iterable<({String? name, String? arguments})> calls) => [
  for (final call in calls) '${call.name} ${jsonDecode(call.arguments!)}',
];

void main() {
  for (final entry
      in (_fixture['templates'] as List).cast<Map<String, dynamic>>()) {
    final templatePath = entry['template'] as String;
    group(templatePath.split('/').last, () {
      late LlamaChatTemplateResult rendered;

      LlamaChatTemplateResult render({
        ToolChoice toolChoice = ToolChoice.auto,
        bool parallelToolCalls = false,
      }) => ChatTemplateEngine.render(
        templateSource: File(templatePath).readAsStringSync(),
        messages: [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: _fixture['user_prompt'] as String,
          ),
        ],
        metadata: const {},
        tools: [_weatherTool],
        toolChoice: toolChoice,
        parallelToolCalls: parallelToolCalls,
        chatTemplateKwargs:
            entry['chat_template_kwargs'] as Map<String, dynamic>?,
      );

      setUpAll(() => rendered = render());

      test('forces the thought open as llama.cpp does', () {
        expect(
          rendered.format,
          ChatFormat.values.byName(entry['format'] as String).index,
        );
        expect(rendered.prompt, endsWith(entry['generation_prompt'] as String));
        expect(rendered.thinkingForcedOpen, isTrue);
      });

      // An unended thought parses as reasoning, so a required call that the
      // grammar let the model start inside it would be lost. A Qwen3-Coder XML
      // call ends the thought itself.
      test('a required call must end the thought first', () {
        final required = render(toolChoice: ToolChoice.required);
        expect(required.thinkingForcedOpen, isTrue);
        expect(required.grammarLazy, isFalse);
        expect(
          required.grammar,
          startsWith(
            entry['required_grammar_start'] as String? ??
                'root ::= think-body "</think>" think-space (',
          ),
        );
      });

      for (final c in (entry['cases'] as List).cast<Map<String, dynamic>>()) {
        final output = c['output'] as String;
        final upstream = c['upstream'] as Map<String, dynamic>;
        final upstreamPartial = c['upstream_partial'] as Map<String, dynamic>?;
        if (upstreamPartial != null) {
          // While output may still follow, llama.cpp drops the start of a tag
          // that it may complete.
          test('${c['name']} parses as llama.cpp while partial', () {
            final parsed = ChatTemplateEngine.parseRendered(
              rendered,
              output,
              isPartial: true,
              tools: [_weatherTool],
            );
            expect(
              parsed.content.trim(),
              (upstreamPartial['content'] as String).trim(),
            );
            expect(
              (parsed.reasoningContent ?? '').trim(),
              (upstreamPartial['reasoning_content'] as String).trim(),
            );
            expect(parsed.toolCalls, isEmpty);
          });
        }
        test('${c['name']} parses and streams as llama.cpp parses', () async {
          final caseRendered = c['parallel_tool_calls'] == true
              ? render(parallelToolCalls: true)
              : rendered;
          final ChatParseResult parsed = ChatTemplateEngine.parse(
            caseRendered.format,
            output,
            thinkingForcedOpen: caseRendered.thinkingForcedOpen,
            tools: [_weatherTool],
          );
          // llamadart trims some whitespace around reasoning and content that
          // llama.cpp keeps.
          expect(parsed.content.trim(), (upstream['content'] as String).trim());
          expect(
            (parsed.reasoningContent ?? '').trim(),
            (upstream['reasoning_content'] as String).trim(),
          );
          final upstreamCalls = _calls([
            for (final call
                in (upstream['tool_calls'] as List)
                    .cast<Map<String, dynamic>>())
              (
                name: call['name'] as String,
                arguments: call['arguments'] as String,
              ),
          ]);
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
          ]) {
            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.fromIterable(tokens),
              templateResult: caseRendered,
              parseToolCallsEnabled: true,
              enableThinking: true,
              modelName: 'test-model',
              completionId: 'forced-open-upstream',
              tools: [_weatherTool],
            ).toList();
            final deltas = chunks.map((chunk) => chunk.choices.single.delta);
            final reason = '${tokens.length} tokens';
            expect(
              deltas.map((delta) => delta.content ?? '').join(),
              parsed.content,
              reason: reason,
            );
            expect(
              deltas.map((delta) => delta.thinking ?? '').join(),
              parsed.reasoningContent ?? '',
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

          // Without tools the stream takes another path; it still matches the
          // parse.
          final textParse = ChatTemplateEngine.parse(
            caseRendered.format,
            output,
            parseToolCalls: false,
            thinkingForcedOpen: caseRendered.thinkingForcedOpen,
          );
          for (final tokens in [
            [output],
            output.split(''),
          ]) {
            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.fromIterable(tokens),
              templateResult: caseRendered,
              parseToolCallsEnabled: false,
              enableThinking: true,
              modelName: 'test-model',
              completionId: 'forced-open-upstream-text',
            ).toList();
            final deltas = chunks.map((chunk) => chunk.choices.single.delta);
            final reason = '${tokens.length} tokens without tools';
            expect(
              deltas.map((delta) => delta.content ?? '').join(),
              textParse.content,
              reason: reason,
            );
            expect(
              deltas.map((delta) => delta.thinking ?? '').join(),
              textParse.reasoningContent ?? '',
              reason: reason,
            );
          }
        });
      }
    });
  }
}
