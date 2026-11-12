@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/src/backends/llama_cpp/reranking_classifier.dart';
import 'package:test/test.dart';

import '../../../support/synthetic_embedding_gguf.dart';

void main() {
  late Directory dir;
  setUp(
    () => dir = Directory.systemTemp.createTempSync('classifier_directory_'),
  );
  tearDown(() => dir.deleteSync(recursive: true));
  test('accepts a real classifier projection with matching output width', () {
    final model = writeSyntheticModernBertGguf(
      '${dir.path}/model.gguf',
      classifierLabels: ['yes', 'no'],
    );
    expect(hasRerankingClassifier(model.path, 2), isTrue);
    expect(hasRerankingClassifier(model.path, 1), isFalse);
    expect(hasRerankingClassifier(model.path, 0), isFalse);
  });
  test('rejects an ordinary model despite a reranker filename', () {
    final model = writeSyntheticLlamaGguf('${dir.path}/reranker.gguf');
    expect(hasRerankingClassifier(model.path, 1), isFalse);
  });
  File header(String name, List<int> shape) {
    final out = BytesBuilder();
    void u32(int value) => out.add(
      (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
    );
    void u64(int value) => out.add(
      (ByteData(8)..setUint64(0, value, Endian.little)).buffer.asUint8List(),
    );
    out.add(utf8.encode('GGUF'));
    u32(3);
    u64(1);
    u64(0);
    final text = utf8.encode(name);
    u64(text.length);
    out.add(text);
    u32(shape.length);
    for (final dim in shape) {
      u64(dim);
    }
    u32(0);
    u64(0);
    return File('${dir.path}/directory.gguf')..writeAsBytesSync(out.toBytes());
  }

  test('accepts Jina direct classifier, rejects wrong rank and width', () {
    expect(
      hasRerankingClassifier(header('cls.weight', [384, 1]).path, 1),
      isTrue,
    );
    expect(
      hasRerankingClassifier(header('cls.weight', [384, 384]).path, 1),
      isFalse,
    );
    expect(
      hasRerankingClassifier(header('cls.output.weight', [384]).path, 2),
      isFalse,
    );
    expect(hasRerankingClassifier(header('cls.weight', [384]).path, 1), isTrue);
    expect(
      hasRerankingClassifier(header('cls.output.weight', [1024]).path, 1),
      isTrue,
    );
    expect(
      hasRerankingClassifier(header('cls.output.weight', [16, 1, 1]).path, 1),
      isFalse,
    );
    expect(
      hasRerankingClassifier(header('cls.output.weight', [0, 1]).path, 1),
      isFalse,
    );
    expect(
      hasRerankingClassifier(header('cls.output.weight', [384, 0]).path, 1),
      isFalse,
    );
    expect(
      hasRerankingClassifier(header('output.weight', [384, 1]).path, 1),
      isFalse,
    );
  });
  test(
    'truncated, missing, invalid and oversized directory counts fail closed',
    () {
      final path = '${dir.path}/bad.gguf';
      for (final bytes in [
        <int>[],
        utf8.encode('GGUF'),
        List<int>.filled(64, 255),
      ]) {
        File(path).writeAsBytesSync(bytes);
        expect(hasRerankingClassifier(path, 1), isFalse);
      }
      expect(hasRerankingClassifier('${dir.path}/missing.gguf', 1), isFalse);
    },
  );
}
