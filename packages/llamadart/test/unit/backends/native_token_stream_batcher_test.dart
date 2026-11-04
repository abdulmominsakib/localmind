@TestOn('vm')
library;

import 'package:llamadart/src/backends/native_token_stream_batcher.dart';
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

    test('emits first chunk immediately and batches subsequent chunks', () {
      final batcher = NativeTokenStreamBatcher(
        tokenThreshold: 3,
        byteThreshold: 99,
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

    test('flushes buffered bytes by byte threshold and final flush', () {
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
      expect(batcher.add([6]), isEmpty);
      expect(batcher.flush(), [6]);
      expect(batcher.flush(), isNull);
    });
  });
}
