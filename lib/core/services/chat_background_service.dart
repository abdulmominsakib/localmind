import 'dart:io';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../logger/app_logger.dart';

class ChatBackgroundService {
  static const _channel = MethodChannel('localmind/chat_background');
  bool _isActive = false;
  bool _isMicActive = false;

  Future<void> start() async {
    if (_isActive) return;
    try {
      Log.info('Starting background chat service');
      if (Platform.isAndroid) {
        await _channel.invokeMethod('startForeground');
      }
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
      if (Platform.isAndroid) {
        await _channel.invokeMethod('stopForeground');
      }
      await WakelockPlus.disable();
      _isActive = false;
    } catch (e) {
      Log.error('Failed to stop background chat service: $e');
    }
  }

  /// Start a microphone-typed foreground service so that voice capture
  /// survives when the app is backgrounded (Android 14+ requirement).
  /// Does not toggle Wakelock — STT is short-lived and the overlay is
  /// already on-screen when listening starts.
  Future<void> startMic() async {
    if (_isMicActive) return;
    try {
      Log.info('Starting background mic service');
      if (Platform.isAndroid) {
        await _channel.invokeMethod('startForegroundMic');
      }
      _isMicActive = true;
    } catch (e) {
      Log.error('Failed to start background mic service: $e');
    }
  }

  /// Stop the microphone-typed foreground service. Safe to call multiple
  /// times and from `endSession()`.
  Future<void> stopMic() async {
    if (!_isMicActive) return;
    try {
      Log.info('Stopping background mic service');
      if (Platform.isAndroid) {
        await _channel.invokeMethod('stopForegroundMic');
      }
      _isMicActive = false;
    } catch (e) {
      Log.error('Failed to stop background mic service: $e');
    }
  }
}
