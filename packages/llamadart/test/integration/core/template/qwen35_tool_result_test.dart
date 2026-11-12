@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:test/test.dart';

import '../../../support/qwen35_tool_result_fixture.dart';

void main() {
  test('exact Qwen3.5 template accepts structured typed tool results', () {
    final source = File(
      'test/fixtures/templates/Qwen3_5-0_8B.jinja',
    ).readAsStringSync();
    final payload = {
      'city': 'Montréal 👋',
      'temperature_celsius': 17,
      'nested': [true, null],
      'escaped': '"quoted"\nline',
    };
    final messages = [
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Call get_weather for Montréal.',
      ),
      const LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          LlamaToolCallContent(
            id: 'call_0',
            name: 'get_weather',
            arguments: {'city': 'Montréal'},
            rawJson: '{"city":"Montréal"}',
          ),
        ],
      ),
      LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [
          LlamaToolResultContent(
            id: 'call_0',
            name: 'get_weather',
            result: payload,
          ),
        ],
      ),
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'What is the temperature_celsius?',
      ),
    ];
    final output = ChatTemplateEngine.render(
      templateSource: source,
      messages: messages,
      metadata: const {},
      toolChoice: ToolChoice.none,
      enableThinking: false,
    );
    expect(
      output.prompt,
      contains('<tool_response>\n${jsonEncode(payload)}\n</tool_response>'),
    );
    expect(output.prompt, contains('<function=get_weather>'));
    expect(output.prompt, contains('Montréal'));
    expect(messages[2].toJson()['content'], same(payload));
    expect(output.prompt, isNot(contains('{city:')));
  });

  test('typed result history preserves tool choices and thinking prefixes', () {
    for (final choice in ToolChoice.values) {
      for (final thinking in [true, false]) {
        final actual = renderQwenResultHistory(
          choice: choice,
          thinking: thinking,
        );
        final control = renderQwenResultHistory(
          choice: choice,
          thinking: thinking,
          stringControl: true,
        );
        expect(actual.prompt, control.prompt);
        expect(actual.prompt, contains(jsonEncode(qwenResultPayload)));
        expect(actual.grammar, control.grammar);
        expect(actual.grammar, choice == ToolChoice.none ? isNull : isNotNull);
        expect(actual.grammarLazy, choice == ToolChoice.auto);
        expect(actual.thinkingForcedOpen, thinking);
        expect(actual.preservedTokens, control.preservedTokens);
        expect(actual.additionalStops, control.additionalStops);
      }
    }
  });

  // Keep strict reconstruction and rollback oracles for typed result histories.
  for (final malformed in [false, true]) {
    test(
      'typed result history ${malformed ? 'rolls back undeclared tools' : 'preserves schema-directed scalar and container types'}',
      () async {
        for (final choice in [ToolChoice.auto, ToolChoice.required]) {
          for (final thinking in [true, false]) {
            final rendered = renderQwenResultHistory(
              choice: choice,
              thinking: thinking,
            );
            final body = malformed
                ? qwenResultEnvelope.replaceFirst(
                    '<function=inspect>',
                    '<function=unknown>',
                  )
                : qwenResultEnvelope;
            final prefix = thinking ? 'reason</think>\n\n' : '';
            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.fromIterable([prefix, ...body.split('')]),
              templateResult: rendered,
              parseToolCallsEnabled: true,
              enableThinking: thinking,
              modelName: 'qwen-typed-result-history',
              completionId: 'typed-result-$choice-$thinking-$malformed',
              tools: [qwenResultTool],
            ).toList();
            final contentChunks = chunks
                .map((c) => c.choices.single.delta.content ?? '')
                .where((c) => c.isNotEmpty)
                .toList();
            final reasoning = chunks
                .map((c) => c.choices.single.delta.thinking ?? '')
                .join();
            final calls = chunks
                .expand(
                  (c) =>
                      c.choices.single.delta.toolCalls ??
                      const <LlamaCompletionChunkToolCall>[],
                )
                .toList();
            expect(reasoning.trim(), thinking ? 'reason' : '');
            if (malformed) {
              // As in llama.cpp, the reply ends before the invalid call.
              expect(calls, isEmpty);
              expect(contentChunks, isEmpty);
              expect(chunks.last.choices.single.finishReason, 'stop');
            } else {
              expect(contentChunks, isEmpty);
              expect(calls, hasLength(1));
              expect(calls.single.function!.name, 'inspect');
              expect(
                jsonDecode(calls.single.function!.arguments!),
                qwenResultPayload,
              );
              expect(chunks.last.choices.single.finishReason, 'tool_calls');
            }
          }
        }
      },
    );
  }
}
