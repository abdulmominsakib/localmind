import 'package:llamadart/src/core/template/thinking_utils.dart';
import 'package:test/test.dart';

void main() {
  test('extractThinking separates reasoning and content', () {
    final result = extractThinking('<think>Reason</think>Answer');
    expect(result.reasoning, 'Reason');
    expect(result.content, 'Answer');
  });

  test('extractThinking strips multiple think blocks', () {
    final result = extractThinking(
      '<think>first</think>A<think>second</think>B',
    );
    expect(result.content, 'AB');
    expect(result.reasoning, 'first\nsecond');
  });

  test('extractThinking preserves whitespace between stripped blocks', () {
    final result = extractThinking(
      'Hello<think>x</think> world<think>y</think>!',
    );
    expect(result.content, 'Hello world!');
    expect(result.reasoning, 'x\ny');
  });

  test('extractThinking handles pre-opened reasoning', () {
    final result = extractThinking('\nI am thinking\n</think>\nHello!');

    expect(result.content, 'Hello!');
    expect(result.reasoning, 'I am thinking');
  });

  test('extractThinking handles open reasoning without an end tag', () {
    final result = extractThinking('<think>\nStill thinking');

    expect(result.content, '');
    expect(result.reasoning, 'Still thinking');
  });

  test('extractThinking treats forced-open output as reasoning', () {
    final result = extractThinking('Still thinking', thinkingForcedOpen: true);

    expect(result.content, '');
    expect(result.reasoning, 'Still thinking');
  });

  test('isThinkingForcedOpen detects trailing think tag', () {
    expect(isThinkingForcedOpen('<think>\n'), isTrue);
    expect(isThinkingForcedOpen('hello'), isFalse);
  });
}
