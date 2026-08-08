import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/utils/bpe_decoder.dart';

void main() {
  group('BpeDecoder', () {
    test('handles standard UTF-8 decoded text with Turkish characters', () {
      final decoder = BpeDecoder();
      const input = 'İstersen, biraz Türkçe konuşalım!';
      final result = decoder.decodeChunk(input);
      expect(result, equals('İstersen, biraz Türkçe konuşalım!'));
    });

    test('handles empty chunks and flushes cleanly', () {
      final decoder = BpeDecoder();
      expect(decoder.decodeChunk(''), equals(''));
      expect(decoder.flush(), equals(''));
    });

    test('handles chunked standard UTF-8 text', () {
      final decoder = BpeDecoder();
      final chunk1 = decoder.decodeChunk('İstersen, ');
      final chunk2 = decoder.decodeChunk('biraz');
      expect(chunk1, equals('İstersen, '));
      expect(chunk2, equals('biraz'));
    });
  });
}
