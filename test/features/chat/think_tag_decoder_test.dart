import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/think_tag_decoder.dart';

void main() {
  test('every split point preserves reasoning and answer', () {
    const raw = ' \n<think>Reason 🧠</think>Answer';
    for (var split = 0; split <= raw.length; split++) {
      final decoder = ThinkTagDecoder();
      final parts = [
        ...decoder.add(raw.substring(0, split), nativeThinking: false),
        ...decoder.add(raw.substring(split), nativeThinking: false),
        ...decoder.flush(),
      ];
      expect(
        parts.where((p) => p.isReasoning).map((p) => p.text).join(),
        'Reason 🧠',
      );
      expect(
        parts.where((p) => !p.isReasoning).map((p) => p.text).join(),
        'Answer',
      );
    }
  });

  test('leaves tags inside an ordinary answer intact', () {
    final decoder = ThinkTagDecoder();
    const answer = 'Use <think>reason</think> as an example.';
    expect(decoder.add(answer, nativeThinking: false), [
      (text: answer, isReasoning: false),
    ]);
  });

  test(
    'unclosed reasoning remains reasoning and partial closing text is retained',
    () {
      final decoder = ThinkTagDecoder();
      final parts = [
        ...decoder.add('<think>Reason</thi', nativeThinking: false),
        ...decoder.flush(),
      ];
      expect(parts.every((p) => p.isReasoning), isTrue);
      expect(parts.map((p) => p.text).join(), 'Reason</thi');
    },
  );
}
