@TestOn('vm')
library;

import 'package:llamadart/src/backends/llama_cpp/stream_batcher.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:test/test.dart';

void main() {
  group('NativeTokenStreamBatcher', () {
    test('uses defaults for non-positive thresholds', () {
      final batcher = NativeTokenStreamBatcher(
        tokenThreshold: 0,
        byteThreshold: -1,
      );

      expect(
        batcher.tokenThreshold,
        GenerationParams.defaultStreamBatchTokenThreshold,
      );
      expect(
        batcher.byteThreshold,
        GenerationParams.defaultStreamBatchByteThreshold,
      );
    });

    test('emits first non-empty chunk immediately', () {
      final batcher = NativeTokenStreamBatcher(
        tokenThreshold: 8,
        byteThreshold: 512,
      );

      final emitted = batcher.add([1, 2, 3]);
      expect(emitted, [
        [1, 2, 3],
      ]);
      expect(batcher.flush(), isNull);
    });

    test('flushes buffered chunks by token threshold', () {
      final batcher = NativeTokenStreamBatcher(
        tokenThreshold: 3,
        byteThreshold: 512,
      );

      expect(batcher.add([1]), [
        [1],
      ]);
      expect(batcher.add([2]), isEmpty);
      expect(batcher.add([3]), isEmpty);
      expect(batcher.add([4]), [
        [2, 3, 4],
      ]);
    });

    test('flushes buffered chunks by byte threshold', () {
      final batcher = NativeTokenStreamBatcher(
        tokenThreshold: 99,
        byteThreshold: 4,
      );

      expect(batcher.add([1]), [
        [1],
      ]);
      expect(batcher.add([2, 3]), isEmpty);
      expect(batcher.add([4, 5]), [
        [2, 3, 4, 5],
      ]);
    });

    test('flush emits remaining buffered bytes at end', () {
      final batcher = NativeTokenStreamBatcher(
        tokenThreshold: 99,
        byteThreshold: 99,
      );

      expect(batcher.add([1]), [
        [1],
      ]);
      expect(batcher.add([2]), isEmpty);
      expect(batcher.add([3]), isEmpty);
      expect(batcher.flush(), [2, 3]);
      expect(batcher.flush(), isNull);
    });
  });
}
