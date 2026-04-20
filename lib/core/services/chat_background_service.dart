import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../logger/app_logger.dart';

class ChatBackgroundService {
  static const _channel = MethodChannel('localmind/chat_background');
  bool _isActive = false;

  Future<void> start() async {
    if (_isActive) return;
    try {
      Log.info('Starting background chat service');
      await _channel.invokeMethod('startForeground');
      await WakelockPlus.enable();
      _isActive = true;
    } catch (e) {
      Log.error('Failed to start background chat service: $e');
    }
  }

  Future<void> stop() async {
    if (!_isActive) return;
    try {
      Log.info('Stopping background chat service');
      await _channel.invokeMethod('stopForeground');
      await WakelockPlus.disable();
      _isActive = false;
    } catch (e) {
      Log.error('Failed to stop background chat service: $e');
    }
  }
}
