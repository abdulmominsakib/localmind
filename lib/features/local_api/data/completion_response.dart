import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// HttpServer pauses reading from the socket while a response is pending.
/// After parsing an authenticated completion request, take ownership of its
/// connection so EOF can cancel inference even before the first model token.
class CompletionResponse {
  CompletionResponse(this._socket, this._onDisconnect) {
    _incoming = _socket.listen(
      (_) {}, // Completions close the connection; ignore pipelined input.
      onDone: abort,
      onError: (Object _) => abort(),
    );
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) => abort()));
  }

  final Socket _socket;
  final void Function() _onDisconnect;
  late final StreamSubscription<List<int>> _incoming;
  bool _streaming = false;
  bool _disconnected = false;
  static const _timeout = Duration(seconds: 10);

  void abort() {
    if (_disconnected) return;
    _disconnected = true;
    _onDisconnect();
    _socket.destroy();
  }

  void startStream() {
    _streaming = true;
    _headers(200, 'OK', 'text/event-stream; charset=utf-8');
  }

  Future<void> event(Object body) {
    _socket.write('data: ${jsonEncode(body)}\n\n');
    return _socket.flush().timeout(_timeout);
  }

  void endStream() => _socket.write('data: [DONE]\n\n');

  void json(Object body, {int status = 200}) {
    final bytes = utf8.encode(jsonEncode(body));
    _headers(
      status,
      switch (status) {
        200 => 'OK',
        503 => 'Service Unavailable',
        504 => 'Gateway Timeout',
        _ => 'Internal Server Error',
      },
      'application/json; charset=utf-8',
      length: bytes.length,
    );
    _socket.add(bytes);
  }

  Future<void> error(int status, Object body) async {
    if (_disconnected) return;
    if (_streaming) {
      await event(body);
    } else {
      json(body, status: status);
    }
  }

  Future<void> close() async {
    try {
      if (!_disconnected) {
        await _socket.flush().timeout(_timeout);
        await _socket.close().timeout(_timeout);
      }
    } finally {
      _socket.destroy();
      await _incoming.cancel();
    }
  }

  void _headers(int status, String reason, String contentType, {int? length}) {
    _socket.write(
      'HTTP/1.1 $status $reason\r\n'
      'Connection: close\r\n'
      'Cache-Control: no-store\r\n'
      'Content-Type: $contentType\r\n'
      '${length == null ? '' : 'Content-Length: $length\r\n'}'
      '\r\n',
    );
  }
}
