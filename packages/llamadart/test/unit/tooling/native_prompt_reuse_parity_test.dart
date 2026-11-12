@TestOn('vm')
library;

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../tool/testing/native_prompt_reuse_parity.dart';

LlamaCompletionChunk _chunk(LlamaCompletionChunkDelta delta) {
  return LlamaCompletionChunk(
    id: 'c',
    object: 'chat.completion.chunk',
    created: 0,
    model: 'm',
    choices: [LlamaCompletionChunkChoice(index: 0, delta: delta)],
  );
}

void main() {
  group('native_prompt_reuse_parity', () {
    test('a run with only role and empty deltas is empty', () async {
      final output = await collectParityOutput(
        Stream.fromIterable([
          _chunk(LlamaCompletionChunkDelta(role: 'assistant')),
          _chunk(LlamaCompletionChunkDelta(content: '')),
        ]),
      );

      expect(output.isEmpty, isTrue);
      expect(
        parityExitCode(mismatches: 0, emptyRuns: 1, failOnMismatch: true),
        1,
      );
      expect(
        parityExitCode(mismatches: 0, emptyRuns: 1, failOnMismatch: false),
        1,
      );
    });

    test('thinking-only and tool-call-only runs are not empty', () async {
      final thinking = await collectParityOutput(
        Stream.value(_chunk(LlamaCompletionChunkDelta(thinking: 'hmm'))),
      );
      final toolCall = await collectParityOutput(
        Stream.value(
          _chunk(
            LlamaCompletionChunkDelta(
              toolCalls: [
                LlamaCompletionChunkToolCall(
                  index: 0,
                  function: LlamaCompletionChunkFunction(
                    name: 'f',
                    arguments: '{}',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(thinking.isEmpty, isFalse);
      expect(toolCall.isEmpty, isFalse);
    });

    test('reasoning differences are mismatches', () async {
      Future<ParityOutput> run(String thinking) => collectParityOutput(
        Stream.fromIterable([
          _chunk(LlamaCompletionChunkDelta(content: 'same')),
          _chunk(LlamaCompletionChunkDelta(thinking: thinking)),
        ]),
      );

      final one = await run('one');

      expect(one.comparable, isNot((await run('two')).comparable));
      expect(one.comparable, (await run('one')).comparable);
    });

    test('first output callback ignores empty deltas', () async {
      var calls = 0;
      await collectParityOutput(
        Stream.fromIterable([
          _chunk(LlamaCompletionChunkDelta(role: 'assistant')),
          _chunk(LlamaCompletionChunkDelta(content: 'a')),
          _chunk(LlamaCompletionChunkDelta(content: 'b')),
        ]),
        onFirstOutput: () => calls++,
      );

      expect(calls, 1);
    });

    test('exit code follows mismatches only with fail-on-mismatch', () {
      expect(
        parityExitCode(mismatches: 1, emptyRuns: 0, failOnMismatch: true),
        1,
      );
      expect(
        parityExitCode(mismatches: 1, emptyRuns: 0, failOnMismatch: false),
        0,
      );
      expect(
        parityExitCode(mismatches: 0, emptyRuns: 0, failOnMismatch: true),
        0,
      );
    });
  });
}
