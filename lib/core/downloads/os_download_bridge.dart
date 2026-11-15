import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/logger/app_logger.dart';

/// Payload handed to the native OS downloader (iOS background URLSession /
/// Android WorkManager worker). Native resumes via `Range: bytes=<offset>-`
/// into [partPath] and follows the resolve redirect itself.
class OsDownloadHandOff {
  final String taskId;
  /// Normalized Hugging Face resolve URL — never a signed CDN URL.
  final String url;
  final String? authToken;
  final int offset;
  final int totalBytes;
  final String partPath;
  final String finalPath;

  const OsDownloadHandOff({
    required this.taskId,
    required this.url,
    required this.authToken,
    required this.offset,
    required this.totalBytes,
    required this.partPath,
    required this.finalPath,
  });

  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'url': url,
        'authToken': authToken,
        'offset': offset,
        'totalBytes': totalBytes,
        'partPath': partPath,
        'finalPath': finalPath,
      };
}

/// One event reported back by the native downloader.
class OsDownloadEvent {
  final String taskId;
  /// Bytes received so far (progress events).
  final int? receivedBytes;
  /// True when the native side finished and the partial file is complete.
  final bool completed;
  /// Failure text (empty when not a failure).
  final String? error;

  const OsDownloadEvent({
    required this.taskId,
    this.receivedBytes,
    this.completed = false,
    this.error,
  });

  static OsDownloadEvent fromMap(Map<String, dynamic> map) {
    return OsDownloadEvent(
      taskId: map['taskId'] as String,
      receivedBytes: map['receivedBytes'] as int?,
      completed: map['completed'] as bool? ?? false,
      error: map['error'] as String?,
    );
  }
}

/// Platform-channel bridge to the native OS downloaders.
class OsDownloadBridge {
  static const _channel = MethodChannel('localmind/os_downloads');

  final void Function(OsDownloadEvent event)? onEvent;

  OsDownloadBridge({this.onEvent}) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Whether this platform ships an OS downloader implementation.
  bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onEvent') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final event = OsDownloadEvent.fromMap(
      Map<String, dynamic>.from(args),
    );
    final handler = onEvent;
    if (handler != null) {
      handler(event);
    }
    return null;
  }

  /// Hands a task to the native downloader. Returns false when unsupported
  /// or the hand-off fails (caller falls back to the in-app path).
  Future<bool> handOff(OsDownloadHandOff payload) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'handOff',
        payload.toMap(),
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      Log.warning('OS download hand-off failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Asks the native downloader to stop and drop a task (engine delete).
  Future<void> cancelNative(String taskId) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'taskId': taskId});
    } on PlatformException catch (e) {
      Log.warning('OS download cancel failed: $e');
    } on MissingPluginException {
      // No native implementation — nothing to cancel.
    }
  }
}
