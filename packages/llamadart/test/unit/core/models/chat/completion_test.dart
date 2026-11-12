import 'dart:async';

import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/completion.dart';
import 'package:llamadart/src/core/models/chat/completion_chunk.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/generation_usage.dart';
import 'package:test/test.dart';

LlamaCompletionChunk _chunk({
  String? content,
  String? thinking,
  List<LlamaCompletionChunkToolCall>? toolCalls,
  String? finishReason,
  LlamaGenerationUsage? usage,
}) => LlamaCompletionChunk(
  id: 'c',
  object: 'chat.completion.chunk',
  created: 1,
  model: 'm',
  choices: [
    LlamaCompletionChunkChoice(
      index: 0,
      delta: LlamaCompletionChunkDelta(
        content: content,
        thinking: thinking,
        toolCalls: toolCalls,
      ),
      finishReason: finishReason,
    ),
  ],
  usage: usage,
);

LlamaCompletionChunkToolCall _toolCall(
  int index, {
  String? id,
  String? name,
  String? arguments,
}) => LlamaCompletionChunkToolCall(
  index: index,
  id: id,
  type: id == null ? null : 'function',
  function: LlamaCompletionChunkFunction(name: name, arguments: arguments),
);

void main() {
  final emptyChoices = LlamaCompletionChunk(
    id: 'c',
    object: 'chat.completion.chunk',
    created: 1,
    model: 'm',
    choices: const [],
  );

  group('LlamaCompletionStreamExtension', () {
    test('textDeltas skips empty and content-free chunks', () async {
      final deltas = await Stream.fromIterable([
        _chunk(thinking: 'hmm'),
        _chunk(content: 'Hel'),
        _chunk(content: ''),
        emptyChoices,
        _chunk(content: 'lo'),
        _chunk(finishReason: 'stop'),
      ]).textDeltas().toList();

      expect(deltas, ['Hel', 'lo']);
    });

    test('text joins the content deltas', () async {
      final text = await Stream.fromIterable([
        _chunk(content: 'Hel'),
        _chunk(content: 'lo'),
        _chunk(finishReason: 'stop'),
      ]).text();

      expect(text, 'Hello');
    });

    test('text of a stream without content is empty', () async {
      expect(await Stream.fromIterable([_chunk(thinking: 'x')]).text(), '');
    });

    test('text forwards a stream error', () async {
      final error = StateError('backend failed');
      final stream = Stream<LlamaCompletionChunk>.multi((controller) {
        controller
          ..add(_chunk(content: 'partial'))
          ..addError(error)
          ..close();
      });

      await expectLater(stream.text(), throwsA(same(error)));
    });

    test('collect assembles text, thinking, finish reason and usage', () async {
      const usage = LlamaGenerationUsage(promptTokens: 4, completionTokens: 2);
      final completion = await Stream.fromIterable([
        _chunk(thinking: 'Let me '),
        _chunk(thinking: 'think.'),
        _chunk(content: 'Hi'),
        emptyChoices,
        _chunk(content: ' there'),
        _chunk(finishReason: 'length', usage: usage),
      ]).collect();

      expect(completion.text, 'Hi there');
      expect(completion.thinking, 'Let me think.');
      expect(completion.toolCalls, isEmpty);
      expect(completion.finishReason, LlamaFinishReason.length);
      expect(completion.usage, same(usage));
    });

    test('collect merges tool-call fragments by index', () async {
      final completion = await Stream.fromIterable([
        _chunk(
          toolCalls: [
            _toolCall(1, id: 'call_b', name: 'second', arguments: '{"n":'),
            _toolCall(0, id: 'call_a', name: 'first', arguments: '{}'),
          ],
        ),
        _chunk(toolCalls: [_toolCall(1, arguments: '2}')]),
        _chunk(finishReason: 'tool_calls'),
      ]).collect();

      expect(completion.finishReason, LlamaFinishReason.toolCalls);
      expect(completion.toolCalls.map((call) => call.id), ['call_a', 'call_b']);
      expect(completion.toolCalls.map((call) => call.name), [
        'first',
        'second',
      ]);
      expect(completion.toolCalls[1].arguments, {'n': 2});
      expect(completion.toolCalls[1].rawJson, '{"n":2}');
    });

    test('collect keeps arguments that are not a JSON object raw', () async {
      final completion = await Stream.fromIterable([
        _chunk(
          toolCalls: [
            _toolCall(0, id: 'a', name: 'bad', arguments: '{"n":'),
            _toolCall(1, id: 'b', name: 'list', arguments: '[1]'),
            _toolCall(2, id: 'c', name: 'none'),
          ],
        ),
      ]).collect();

      expect(completion.toolCalls.map((call) => call.arguments), [
        isEmpty,
        isEmpty,
        isEmpty,
      ]);
      expect(completion.toolCalls.map((call) => call.rawJson), [
        '{"n":',
        '[1]',
        '',
      ]);
    });

    test(
      'collect of a stream without a final chunk has no finish reason',
      () async {
        final completion = await Stream.fromIterable([
          _chunk(content: 'cut'),
        ]).collect();

        expect(completion.text, 'cut');
        expect(completion.finishReason, isNull);
      },
    );

    test('collect of an empty stream is empty', () async {
      final completion = await const Stream<LlamaCompletionChunk>.empty()
          .collect();

      expect(completion.text, isEmpty);
      expect(completion.thinking, isEmpty);
      expect(completion.toolCalls, isEmpty);
      expect(completion.finishReason, isNull);
      expect(completion.usage, isNull);
    });
  });

  group('LlamaCompletion.message', () {
    test('orders thinking, text and tool calls', () {
      const call = LlamaToolCallContent(
        id: 'call_0',
        name: 'f',
        arguments: {},
        rawJson: '{}',
      );
      final message = const LlamaCompletion(
        text: 'answer',
        thinking: 'reasoning',
        toolCalls: [call],
      ).message;

      expect(message.role, LlamaChatRole.assistant);
      expect(message.parts, hasLength(3));
      expect((message.parts[0] as LlamaThinkingContent).thinking, 'reasoning');
      expect((message.parts[1] as LlamaTextContent).text, 'answer');
      expect(message.parts[2], same(call));
    });

    test('leaves out empty thinking and text', () {
      final message = const LlamaCompletion(text: '').message;

      expect(message.role, LlamaChatRole.assistant);
      expect(message.parts, isEmpty);
    });
  });
}
