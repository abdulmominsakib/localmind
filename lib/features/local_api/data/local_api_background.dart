import 'package:flutter/services.dart';

class LocalApiBackground {
  LocalApiBackground({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('localmind/local_api');

  final MethodChannel _channel;

  void listen(Future<void> Function() stop) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopLocalApiFromNotification' ||
          call.method == 'localApiServiceEnded') {
        await stop();
      }
    });
  }

  void dispose() => _channel.setMethodCallHandler(null);

  Future<void> start({required String text, required String stop}) =>
      _channel.invokeMethod<void>('start', {'text': text, 'stop': stop});

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
