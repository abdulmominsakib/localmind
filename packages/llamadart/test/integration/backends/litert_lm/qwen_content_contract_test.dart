import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:test/test.dart';

import '../../../support/litert_qwen_content_fixture.dart';
import '../../../support/qwen_tool_schema_fixture.dart';

void main() {
  for (final choice in ToolChoice.values) {
    for (final thinking in [false, true]) {
      test(
        'LiteRT Qwen normalized history preserves $choice thinking=$thinking',
        () async {
          final history = renderLiteRtQwenHistory(
            choice: choice,
            thinking: thinking,
          );
          expect(history.normalized, history.legacy);
          expect(history.normalized, contains(jsonEncode(qwenResultPayload)));
          final output = choice == ToolChoice.none
              ? 'Visible answer.'
              : litertQwenEnvelope;
          final chunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable([
              if (thinking) '<think>Check values.</think>',
              ...output.split(''),
            ]),
            templateResult: history.rendered,
            parseToolCallsEnabled: choice != ToolChoice.none,
            enableThinking: thinking,
            modelName: 'Qwen3-0.6B',
            completionId: 'normalized-history',
            tools: [qwenResultTool],
          ).toList();
          final content = chunks
              .map((chunk) => chunk.choices.single.delta.content ?? '')
              .join();
          final calls = chunks
              .expand(
                (chunk) =>
                    chunk.choices.single.delta.toolCalls ??
                    const <LlamaCompletionChunkToolCall>[],
              )
              .toList();
          if (choice == ToolChoice.none) {
            expect(calls, isEmpty);
            expect(content, output);
            expect(history.rendered.grammar, isNull);
          } else {
            expect(
              content,
              isEmpty,
              reason: 'Partial tool envelopes must stay hidden.',
            );
            expect(calls, hasLength(1));
            expect(
              jsonDecode(calls.single.function!.arguments!),
              qwenResultPayload,
            );
            expect(history.rendered.grammar, isNotEmpty);
            expect(history.rendered.grammarLazy, choice == ToolChoice.auto);
          }
        },
      );
    }
  }
  test(
    'LiteRT Qwen normalized history rolls malformed final back to text',
    () async {
      final history = renderLiteRtQwenHistory(
        choice: ToolChoice.auto,
        thinking: false,
      );
      expect(history.normalized, history.legacy);
      const malformed =
          '<tool_call>{"name":"inspect","arguments":broken}</tool_call>';
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(malformed.split('')),
        templateResult: history.rendered,
        parseToolCallsEnabled: true,
        enableThinking: false,
        modelName: 'Qwen3-0.6B',
        completionId: 'malformed-history',
        tools: [qwenResultTool],
      ).toList();
      expect(
        chunks.map((chunk) => chunk.choices.single.delta.content ?? '').join(),
        malformed,
      );
      expect(
        chunks.expand(
          (chunk) => chunk.choices.single.delta.toolCalls ?? const [],
        ),
        isEmpty,
      );
    },
  );
}
