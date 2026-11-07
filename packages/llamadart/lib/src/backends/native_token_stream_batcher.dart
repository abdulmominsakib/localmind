import '../core/models/inference/generation_params.dart';

/// Batches generated token bytes before sending through isolate messages.
class NativeTokenStreamBatcher {
  /// Effective chunk threshold by token pieces.
  final int tokenThreshold;

  /// Effective chunk threshold by accumulated bytes.
  final int byteThreshold;

  final List<int> _pendingBytes = <int>[];
  int _pendingTokenChunks = 0;
  bool _sentFirstChunk = false;

  /// Creates a stream batcher with validated thresholds.
  NativeTokenStreamBatcher({
    required int tokenThreshold,
    required int byteThreshold,
  }) : tokenThreshold = tokenThreshold > 0
           ? tokenThreshold
           : GenerationParams.defaultStreamBatchTokenThreshold,
       byteThreshold = byteThreshold > 0
           ? byteThreshold
           : GenerationParams.defaultStreamBatchByteThreshold;

  /// Adds [tokens] and returns zero or more chunks ready to emit.
  List<List<int>> add(List<int> tokens) {
    if (tokens.isEmpty) {
      return const <List<int>>[];
    }

    if (!_sentFirstChunk) {
      _sentFirstChunk = true;
      return <List<int>>[tokens];
    }

    _pendingBytes.addAll(tokens);
    _pendingTokenChunks += 1;

    if (_pendingTokenChunks >= tokenThreshold ||
        _pendingBytes.length >= byteThreshold) {
      return <List<int>>[_drainPending()];
    }

    return const <List<int>>[];
  }

  /// Flushes pending buffered bytes.
  List<int>? flush() {
    if (_pendingBytes.isEmpty) {
      return null;
    }

    return _drainPending();
  }

  List<int> _drainPending() {
    final drained = List<int>.from(_pendingBytes);
    _pendingBytes.clear();
    _pendingTokenChunks = 0;
    return drained;
  }
}
