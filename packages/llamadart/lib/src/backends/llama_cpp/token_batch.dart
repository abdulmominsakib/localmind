import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// A token batch laid out as `llama_batch_init(tokens, 0, sequences)` lays it
/// out, in a single block that [freeAddress] frees.
///
/// `llama_batch_init` allocates each array separately and `llama_batch_free`
/// takes the batch by value, so no native finalizer can free that batch when
/// a killed worker isolate shuts down.
final class TokenBatch {
  TokenBatch._(this.block, this._allocator);

  /// Allocates a batch of up to [tokens] tokens, each in up to [sequences]
  /// sequences, from [allocator], whose blocks [freeAddress] must be able to
  /// free.
  factory TokenBatch.allocate(
    int tokens,
    int sequences, {
    Allocator allocator = malloc,
  }) {
    final header = sizeOf<llama_batch>();
    final seqIdTable = sizeOf<Pointer<llama_seq_id>>() * (tokens + 1);
    final int32Arrays = sizeOf<Int32>() * tokens * (3 + sequences);
    final block = allocator<Uint8>(header + seqIdTable + int32Arrays + tokens);
    final table = (block + header).cast<Pointer<llama_seq_id>>();
    final token = (block + header + seqIdTable).cast<Int32>();
    final pos = token + tokens;
    final nSeqId = pos + tokens;
    final seqIds = nSeqId + tokens;
    for (var i = 0; i < tokens; i++) {
      table[i] = seqIds + i * sequences;
    }
    table[tokens] = nullptr;
    block.cast<llama_batch>().ref
      ..n_tokens = 0
      ..token = token
      ..embd = nullptr
      ..pos = pos
      ..n_seq_id = nSeqId
      ..seq_id = table
      ..logits = (seqIds + tokens * sequences).cast<Int8>();
    return TokenBatch._(block.cast(), allocator);
  }

  /// The block that holds the batch and its arrays.
  final Pointer<Void> block;

  final Allocator _allocator;

  /// The batch, a view of [block].
  llama_batch get batch => block.cast<llama_batch>().ref;

  /// Frees a [block], for a native finalizer: [malloc]'s free.
  static Pointer<NativeFinalizerFunction> get freeAddress => malloc.nativeFree;

  /// Frees the batch; it must not be used afterwards.
  void free() => _allocator.free(block);
}
