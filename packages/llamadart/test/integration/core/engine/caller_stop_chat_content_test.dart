import 'dart:convert';

import 'package:llamadart/src/backends/llama_cpp/stop_sequence_buffer.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/completion_chunk.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

// Qwen3.5 splits "alpha cedar17 omega" this way (#951): each caller stop
// below starts inside a piece or right after one that ends in whitespace.
const _reply = ['alpha', ' cedar', '1', '7', ' omega'];

final _weatherTool = ToolDefinition(
  name: 'weather',
  description: 'Weather',
  parameters: [ToolParam.string('city', required: true)],
  handler: (_) async => null,
);

/// The text chunks a backend streams for [pieces] cut at the first of
/// [stops], with [batch] pieces per chunk.
List<String> _stoppedChunks(
  List<String> pieces,
  List<String> stops, {
  required int batch,
}) {
  final buffer = StopSequenceBuffer(stops);
  final chunks = <String>[];
  var pending = <int>[];
  var batched = 0;
  void flush() {
    if (pending.isNotEmpty) chunks.add(utf8.decode(pending));
    pending = <int>[];
    batched = 0;
  }

  for (final piece in pieces) {
    pending.addAll(buffer.add(utf8.encode(piece)));
    if (buffer.isStopped) break;
    if (++batched == batch) flush();
  }
  if (!buffer.isStopped) pending.addAll(buffer.finish());
  flush();
  return chunks;
}

Future<List<LlamaCompletionChunk>> _chat(
  ChatFormat format,
  List<String> chunks, {
  bool tools = false,
  bool forcedOpen = false,
}) {
  return ChatCompletionStreamParser.parse(
    tokenStream: Stream.fromIterable(chunks),
    templateResult: LlamaChatTemplateResult(
      prompt: 'prompt',
      format: format.index,
      thinkingForcedOpen: forcedOpen,
    ),
    parseToolCallsEnabled: tools,
    enableThinking: true,
    modelName: 'test-model',
    completionId: 'caller-stop',
    tools: tools ? [_weatherTool] : null,
  ).toList();
}

String _content(List<LlamaCompletionChunk> chunks) =>
    chunks.map((chunk) => chunk.choices.single.delta.content ?? '').join();

String _thinking(List<LlamaCompletionChunk> chunks) =>
    chunks.map((chunk) => chunk.choices.single.delta.thinking ?? '').join();

void main() {
  final handlerFormats = [
    for (final format in ChatFormat.values)
      if (!format.name.startsWith('peg')) format,
  ];

  group('chat content before a caller stop', () {
    test('keeps the whitespace of the piece the stop starts in', () async {
      for (final (stops, expected) in const [
        (['cedar17'], 'alpha '),
        (['omega'], 'alpha cedar17 '),
        (['zzz', 'omega', 'cedar17'], 'alpha '),
        (['17'], 'alpha cedar'),
        (<String>[], 'alpha cedar17 omega'),
      ]) {
        for (final batch in const [1, 2, 8]) {
          final chunks = _stoppedChunks(_reply, stops, batch: batch);
          expect(chunks.join(), expected, reason: '$stops batch: $batch');
          for (final format in handlerFormats) {
            for (final tools in const [false, true]) {
              final reason =
                  '${format.name} $stops batch: $batch tools: $tools';
              final streamed = await _chat(format, chunks, tools: tools);
              expect(_content(streamed), expected, reason: reason);
              expect(
                streamed.last.choices.single.finishReason,
                'stop',
                reason: reason,
              );
              expect(
                ChatTemplateEngine.parse(
                  format.index,
                  chunks.join(),
                  parseToolCalls: tools,
                ).content,
                expected,
                reason: reason,
              );
            }
          }
        }
      }
    });

    test(
      'keeps a stop marker split across chunks out of the content',
      () async {
        final chunks = _stoppedChunks(
          const ['alpha', ' \n', 'ce', 'dar', '17 omega'],
          const ['cedar17'],
          batch: 1,
        );
        expect(chunks, ['alpha', ' \n']);
        expect(_content(await _chat(ChatFormat.hermes, chunks)), 'alpha \n');
      },
    );

    test('follows a thought', () async {
      for (final batch in const [1, 8]) {
        final chunks = _stoppedChunks(
          ['<think>', 'Plan', '.\n', '</think>', '\n\n', ..._reply],
          const ['cedar17'],
          batch: batch,
        );
        for (final tools in const [false, true]) {
          final streamed = await _chat(ChatFormat.hermes, chunks, tools: tools);
          expect(_thinking(streamed), 'Plan.');
          expect(_content(streamed), 'alpha ');
        }
      }
    });

    test('is empty when the stop is inside a thought', () async {
      for (final batch in const [1, 8]) {
        final chunks = _stoppedChunks(
          const ['<think>', 'Say', ' alpha', ' cedar', '1', '7', '</think>'],
          const ['cedar17'],
          batch: batch,
        );
        expect(chunks.join(), '<think>Say alpha ');
        final streamed = await _chat(ChatFormat.hermes, chunks);
        expect(_content(streamed), isEmpty);
        expect(_thinking(streamed), 'Say alpha');

        final forced = await _chat(
          ChatFormat.hermes,
          _stoppedChunks(_reply, const ['cedar17'], batch: batch),
          forcedOpen: true,
        );
        expect(_content(forced), isEmpty);
        expect(_thinking(forced), 'alpha');
      }
    });

    test('is the text of a tool call the stop cuts', () async {
      const call = [
        'Let me check. ',
        '<tool_call>',
        '\n{"name": "weather", ',
        '"arguments": {"city": "',
        'Paris',
        '"}}\n',
        '</tool_call>',
      ];
      for (final batch in const [1, 8]) {
        final whole = await _chat(
          ChatFormat.hermes,
          _stoppedChunks(call, const [], batch: batch),
          tools: true,
        );
        expect(_content(whole), 'Let me check.');
        expect(whole.last.choices.single.finishReason, 'tool_calls');

        for (final (stop, expected) in const [
          (
            'Paris',
            'Let me check. <tool_call>\n{"name": "weather", "arguments": {"city": "',
          ),
          ('"arguments"', 'Let me check. <tool_call>\n{"name": "weather", '),
        ]) {
          final cut = await _chat(
            ChatFormat.hermes,
            _stoppedChunks(call, [stop], batch: batch),
            tools: true,
          );
          expect(
            cut.expand((chunk) => chunk.choices.single.delta.toolCalls ?? []),
            isEmpty,
          );
          expect(cut.last.choices.single.finishReason, 'stop');
          expect(_content(cut), expected);
        }
      }
    });
  });
}
