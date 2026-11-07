/// Serializes native resource ownership changes without poisoning later work
/// when an operation fails. Internal operations must not re-enter the queue.
class AsyncOperationQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
