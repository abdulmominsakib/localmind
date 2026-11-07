import 'dart:async';

/// A terminal callback may arrive while send_message_stream is still returning
/// on its worker. Neither event alone permits releasing its native arguments.
class NativeStreamLifetime {
  final _done = Completer<void>();
  bool _returned = false;
  bool _terminal = false;

  Future<void> get done => _done.future;
  bool get isComplete => _done.isCompleted;
  bool get hasTerminalCallback => _terminal;

  void callReturned() {
    _returned = true;
    _completeIfReady();
  }

  void terminalCallback() {
    _terminal = true;
    _completeIfReady();
  }

  void _completeIfReady() {
    if (_returned && _terminal && !_done.isCompleted) _done.complete();
  }
}
