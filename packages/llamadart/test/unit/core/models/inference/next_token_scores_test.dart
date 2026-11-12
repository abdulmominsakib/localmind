import 'dart:math' as math;

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('decodes token bytes, replacing a partial character', () {
    final whole = LlamaTokenLogprob(
      token: 1,
      bytes: const [0xEC, 0x95, 0x88],
      logprob: 0,
    );
    final partial = LlamaTokenLogprob(
      token: 2,
      bytes: const [0xEC, 0x95],
      logprob: 0,
    );

    expect(whole.text, '안');
    expect(partial.text, '�');
  });

  test('derives probability from the log-probability', () {
    final token = LlamaTokenLogprob(
      token: 1,
      bytes: const [],
      logprob: math.log(0.25),
    );

    expect(token.probability, closeTo(0.25, 1e-12));
  });

  test('copies its lists', () {
    final bytes = [65];
    final candidates = [LlamaTokenLogprob(token: 1, bytes: bytes, logprob: 0)];
    final token = candidates.first;
    final scores = LlamaNextTokenScores(
      candidates: candidates,
      top: candidates,
      promptTokens: 1,
    );
    bytes.add(66);
    candidates.clear();

    expect(token.bytes, [65]);
    expect(scores.candidates, [token]);
    expect(scores.top, [token]);
    expect(() => scores.top.add(token), throwsUnsupportedError);
  });
}
