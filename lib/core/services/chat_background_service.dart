import 'dart:io';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../logger/app_logger.dart';

class ChatBackgroundService {
  ChatBackgroundService({MethodChannel? channel, bool? supportedPlatform})
    : _channel = channel ?? const MethodChannel(_channelName),
      _isAndroid = supportedPlatform ?? Platform.isAndroid;

  static const _channelName = 'localmind/chat_background';

  final MethodChannel _channel;
  final bool _isAndroid;
  int _holders = 0;
  bool _isMicActive = false;

  /// Holds the service until a matching [stop]. Model loads and chat replies
  /// hold it independently, so it stays up until the last of them stops.
  ///
  /// The hold is counted before the platform call so a [stop] issued while
  /// this start is in flight still reaches Android, after the start.
  Future<void> start() async {
    if (_holders++ > 0) return;
    try {
      Log.info('Starting background chat service');
      if (_isAndroid) {
        await _channel.invokeMethod('startForeground');
      }
      await WakelockPlus.enable();
    } catch (e) {
      Log.error('Failed to start background chat service: $e');
    }
  }

  Future<void> stop() async {
    if (_holders == 0) return;
    if (--_holders > 0) return;
    try {
      Log.info('Stopping background chat service');
      if (_isAndroid) {
        await _channel.invokeMethod('stopForeground');
      }
      await WakelockPlus.disable();
    } catch (e) {
      Log.error('Failed to stop background chat service: $e');
    }
  }

  /// Start a microphone-typed foreground service so that voice capture
  /// survives when the app is backgrounded (Android 14+ requirement).
  /// Does not toggle Wakelock — STT is short-lived and the overlay is
  /// already on-screen when listening starts.
  Future<bool> startMic() async {
    if (_isMicActive) return true;
    try {
      Log.info('Starting background mic service');
      if (_isAndroid) {
        await _channel.invokeMethod('startForegroundMic');
      }
      _isMicActive = true;
      return true;
    } catch (e) {
      Log.error('Failed to start background mic service: $e');
      return false;
    }
  }

  /// Stop the microphone-typed foreground service. Safe to call multiple
  /// times and from `endSession()`.
  Future<void> stopMic() async {
    if (!_isMicActive) return;
    try {
      Log.info('Stopping background mic service');
      if (_isAndroid) {
        await _channel.invokeMethod('stopForegroundMic');
      }
      _isMicActive = false;
    } catch (e) {
      Log.error('Failed to stop background mic service: $e');
    }
  }
}
