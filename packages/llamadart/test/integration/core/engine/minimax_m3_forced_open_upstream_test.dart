@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/completion_chunk.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

final _fixture =
    jsonDecode(
          File(
            'test/fixtures/minimax_m3_forced_open_upstream.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
final _tool = ToolDefinition(
  name: 'weather',
  description: 'w',
  handler: (params) async => '',
  parameters: [ToolParam.string('city', required: true)],
);

LlamaChatTemplateResult _render(ToolChoice toolChoice) {
  final rendered = ChatTemplateEngine.render(
    templateSource: File(_fixture['template'] as String).readAsStringSync(),
    messages: const [],
    metadata: const {},
    tools: [_tool],
    toolChoice: toolChoice,
    enableThinking: true,
    chatTemplateKwargs: Map<String, dynamic>.from(_fixture['kwargs'] as Map),
  );
  expect(rendered.format, ChatFormat.minimaxM3.index);
  expect(rendered.thinkingForcedOpen, isTrue);
  return rendered;
}

Future<List<LlamaCompletionChunk>> _stream(
  LlamaChatTemplateResult rendered,
  ToolChoice toolChoice,
  List<String> tokens,
) => ChatCompletionStreamParser.parse(
  tokenStream: Stream.fromIterable(tokens),
  templateResult: rendered,
  parseToolCallsEnabled: toolChoice != ToolChoice.none,
  enableThinking: true,
  modelName: 'minimax-m3',
  completionId: 'forced-open',
  tools: [_tool],
).toList();

List<String> _calls(List<LlamaCompletionChunk> chunks) => [
  for (final call in chunks.expand(
    (c) => c.choices.single.delta.toolCalls ?? const [],
  ))
    '${call.function?.name} ${call.function?.arguments}',
];

void main() {
  final cases = (_fixture['cases'] as List).cast<Map<String, dynamic>>();
  for (final toolChoice in [ToolChoice.auto, ToolChoice.none]) {
    final choice = toolChoice == ToolChoice.auto ? 'auto' : 'none';
    group('MiniMax M3 forced-open upstream parity, tool choice $choice', () {
      late LlamaChatTemplateResult rendered;
      setUpAll(() => rendered = _render(toolChoice));
      for (final c in cases) {
        final output = c['output'] as String;
        final upstream = c[choice] as Map<String, dynamic>;
        final partial = c['partial'] == true;
        final reasoning = upstream['reasoning_content'] as String;
        final content = (upstream['content'] as String).trim();
        final calls = [
          for (final call in upstream['tool_calls'] as List)
            '${call['name']} ${call['arguments']}',
        ];

        test('${c['name']} parses as llama.cpp does', () {
          final parsed = ChatTemplateEngine.parseRendered(
            rendered,
            output,
            isPartial: partial,
            parseToolCalls: toolChoice != ToolChoice.none,
            tools: [_tool],
          );
          expect(parsed.reasoningContent ?? '', reasoning);
          expect(parsed.content.trim(), content);
          expect(
            parsed.toolCalls.map(
              (call) => '${call.function?.name} ${call.function?.arguments}',
            ),
            calls,
          );
        });

        if (partial) continue;
        final partitions = <String, List<String>>{
          'whole': [output],
          'characters': output.split(''),
          for (var at = 1; at < output.length; at++)
            'split at $at': [output.substring(0, at), output.substring(at)],
        };
        test('${c['name']} streams as it parses at every split', () async {
          for (final partition in partitions.entries) {
            final chunks = await _stream(rendered, toolChoice, partition.value);
            final context = '${partition.key} of ${jsonEncode(output)}';
            expect(
              chunks
                  .map((c) => c.choices.single.delta.thinking ?? '')
                  .join()
                  .trim(),
              reasoning,
              reason: context,
            );
            expect(
              chunks
                  .map((c) => c.choices.single.delta.content ?? '')
                  .join()
                  .trim(),
              content,
              reason: context,
            );
            expect(_calls(chunks), calls, reason: context);
          }
        });
      }
    });
  }
}
