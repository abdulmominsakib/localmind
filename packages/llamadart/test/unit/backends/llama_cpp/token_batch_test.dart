@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/token_batch.dart';

final class _RecordingAllocator implements Allocator {
  final requested = <int>[];

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    requested.add(byteCount);
    return malloc.allocate<T>(byteCount, alignment: alignment);
  }

  @override
  void free(Pointer<NativeType> pointer) => malloc.free(pointer);
}

void main() {
  test('lays the batch out as llama_batch_init does', () {
    const tokens = 5;
    const sequences = 3;
    final reference = llama_batch_init(tokens, 0, sequences);
    addTearDown(() => llama_batch_free(reference));
    final owned = TokenBatch.allocate(tokens, sequences);
    addTearDown(owned.free);
    final batch = owned.batch;

    expect(batch.n_tokens, reference.n_tokens);
    expect(batch.embd, nullptr);
    expect(reference.embd, nullptr);
    for (var i = 0; i < tokens; i++) {
      expect(batch.seq_id[i], isNot(nullptr));
      expect(reference.seq_id[i], isNot(nullptr));
    }
    expect(batch.seq_id[tokens], nullptr);
    expect(reference.seq_id[tokens], nullptr);
  });

  test('packs the header and every array into the block without overlap', () {
    const tokens = 7;
    const sequences = 2;
    final owned = TokenBatch.allocate(tokens, sequences);
    addTearDown(owned.free);
    final batch = owned.batch;
    final writes = <(Pointer<NativeType>, int)>[
      for (var i = 0; i < tokens; i++) ...[
        (batch.token + i, sizeOf<Int32>()),
        (batch.pos + i, sizeOf<Int32>()),
        (batch.n_seq_id + i, sizeOf<Int32>()),
        (batch.logits + i, sizeOf<Int8>()),
        (batch.seq_id + i, sizeOf<Pointer<llama_seq_id>>()),
        for (var s = 0; s < sequences; s++)
          (batch.seq_id[i] + s, sizeOf<Int32>()),
      ],
      (batch.seq_id + tokens, sizeOf<Pointer<llama_seq_id>>()),
    ];
    final start = owned.block.address;
    final ranges = [
      (start, start + sizeOf<llama_batch>()),
      for (final (pointer, size) in writes)
        (pointer.address, pointer.address + size),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    expect(ranges.first.$1, start);
    for (var i = 1; i < ranges.length; i++) {
      expect(ranges[i].$1, ranges[i - 1].$2, reason: 'no overlap, no gap');
    }
  });

  test('allocates exactly up to the end of the last array', () {
    for (final (tokens, sequences) in [(1, 1), (5, 3), (512, 1), (64, 8)]) {
      final allocator = _RecordingAllocator();
      final owned = TokenBatch.allocate(
        tokens,
        sequences,
        allocator: allocator,
      );
      addTearDown(owned.free);
      final lastArrayEnd =
          owned.batch.logits.address + tokens - owned.block.address;

      expect(allocator.requested, [
        lastArrayEnd,
      ], reason: '$tokens tokens, $sequences sequences');
    }
  });

  test('keeps writes to the batch in the block', () {
    final owned = TokenBatch.allocate(4, 1);
    addTearDown(owned.free);

    owned.batch.n_tokens = 3;
    owned.batch.token[2] = 42;

    expect(owned.batch.n_tokens, 3);
    expect(owned.block.cast<llama_batch>().ref.token[2], 42);
  });

  test('is freed by malloc, so a finalizer can free it', () {
    expect(TokenBatch.freeAddress, malloc.nativeFree);
  });
}
