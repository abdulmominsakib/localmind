import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/tts/utils/tts_text_processor.dart';

void main() {
  group('TtsTextProcessor.splitIntoChunks', () {
    test('short text passes through as a single chunk', () {
      final text = '一句话很短。';
      expect(TtsTextProcessor.splitIntoChunks(text), [text]);
    });

    test('splits long Chinese text at 。！？； boundaries', () {
      final sentence = '这是用来填充长度的中文句子。';
      final text = sentence * 25; // 325 chars, 25 sentences
      final chunks = TtsTextProcessor.splitIntoChunks(text);

      expect(chunks.length, greaterThan(1));
      // Every chunk boundary lands after a terminal punctuation mark.
      for (final chunk in chunks) {
        expect(chunk.endsWith('。'), isTrue, reason: chunk);
      }
      // No content lost and order preserved.
      expect(chunks.join(), contains(sentence));
      final index = chunks.join().indexOf(sentence);
      expect(index, 0);
    });

    test('splits long mixed Chinese-English text preserving order', () {
      final parts = List.generate(10, (i) {
        return i.isEven
            ? '第$i句这是用来填充长度的中文内容！'
            : 'Sentence $i pads this mixed reply past the chunk limit. ';
      });
      final text = parts.join();
      final chunks = TtsTextProcessor.splitIntoChunks(text);

      expect(chunks.length, greaterThan(1));
      final rejoined = chunks.join();
      // Relative order survives: every numbered sentence appears in order.
      var searchFrom = 0;
      for (var i = 0; i < parts.length; i++) {
        final marker = i.isEven ? '第$i句' : 'Sentence $i';
        final at = rejoined.indexOf(marker, searchFrom);
        expect(at, greaterThanOrEqualTo(0), reason: marker);
        searchFrom = at;
      }
    });

    test('sub-splits an oversized sentence at CJK commas', () {
      final clause = '这是一个非常长的从句，';
      final sentence = clause * 30; // one giant "sentence", 330 chars
      final chunks = TtsTextProcessor.splitIntoChunks(sentence);

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(280), reason: chunk);
      }
    });

    test('keeps Latin punctuation splitting behavior', () {
      final text =
          'First sentence pads the reply. ' * 12; // > 250 chars
      final chunks = TtsTextProcessor.splitIntoChunks(text);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.endsWith('.'), isTrue, reason: chunk);
      }
    });

    test('oversized text without punctuation lands in one chunk', () {
      final text = 'a' * 400;
      expect(TtsTextProcessor.splitIntoChunks(text), [text]);
    });
  });
}
