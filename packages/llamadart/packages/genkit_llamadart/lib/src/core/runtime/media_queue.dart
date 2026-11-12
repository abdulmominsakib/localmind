import 'dart:async';

class MediaQueue {
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposal;
  bool _closed = false;

  Future<T> run<T>(Future<T> Function() operation) {
    if (_closed) {
      return Future<T>.error(StateError('Media plugin is disposed.'));
    }
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> dispose(Future<void> Function() release) {
    _closed = true;
    return _disposal ??= _tail.then((_) => release());
  }
}
