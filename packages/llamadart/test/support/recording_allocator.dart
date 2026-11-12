import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

/// A [malloc] allocator that records each allocation, so a test can check
/// what the code under test allocated and that it freed all of it.
final class RecordingAllocator implements Allocator {
  /// Records allocations; with [poison], fills each one with nonzero bytes,
  /// so code that relies on zeroed memory fails instead of passing by luck.
  RecordingAllocator({this.poison = false});

  /// Whether each allocation starts as nonzero bytes.
  final bool poison;

  /// The allocations not freed yet.
  final Set<Pointer<NativeType>> live = {};

  /// The byte count of each allocation, in order.
  final List<int> byteCounts = [];

  /// The number of allocations so far.
  int get allocations => byteCounts.length;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final pointer = malloc.allocate<T>(byteCount, alignment: alignment);
    if (poison) {
      pointer
          .cast<Uint8>()
          .asTypedList(byteCount)
          .fillRange(0, byteCount, 0xa5);
    }
    byteCounts.add(byteCount);
    live.add(pointer);
    return pointer;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    expect(live.remove(pointer), isTrue, reason: 'No unowned or double frees.');
    malloc.free(pointer);
  }

  /// Fails unless every allocation came back through [free]. A pointer left
  /// in [live] stays allocated: the code under test may have freed it some
  /// other way, and freeing it again would abort the VM.
  void expectAllFreed() => expect(
    live,
    isEmpty,
    reason: 'an allocation was leaked or freed outside this allocator',
  );
}
