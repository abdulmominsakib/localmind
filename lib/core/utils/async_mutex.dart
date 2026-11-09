import 'dart:async';

/// Serializes asynchronous work so repository metadata writes cannot interleave.
///
/// Note: this mutex is not reentrant. A locked action must not call [run] on
/// the same instance again.
class AsyncMutex {
  Future<void> _queue = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _queue;
    final next = previous.then((_) => action());
    // Keep the queue moving even if [action] throws.
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}
