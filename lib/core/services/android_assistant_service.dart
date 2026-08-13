import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logger/app_logger.dart';

enum AndroidAssistantStatus { unsupported, available, active, manual, unknown }

class AndroidAssistantService {
  AndroidAssistantService({MethodChannel? channel, bool? supportedPlatform})
    : _channel = channel ?? const MethodChannel(_channelName),
      _supportedPlatformOverride = supportedPlatform;

  static const _channelName = 'localmind/android_assistant';

  final MethodChannel _channel;
  final bool? _supportedPlatformOverride;
  final StreamController<void> _invocations =
      StreamController<void>.broadcast();

  bool _initialized = false;
  bool _disposed = false;

  bool get isSupportedPlatform =>
      _supportedPlatformOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Stream<void> get invocations => _invocations.stream;

  Future<void> initialize() async {
    if (!isSupportedPlatform || _initialized || _disposed) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleNativeCall);

    try {
      final pending =
          await _channel.invokeMethod<bool>('consumePendingInvocation') ??
          false;
      if (pending && !_disposed) {
        _invocations.add(null);
      }
    } on PlatformException catch (error) {
      Log.error('Android assistant initialization failed: $error');
    }
  }

  Future<AndroidAssistantStatus> getStatus() async {
    if (!isSupportedPlatform) return AndroidAssistantStatus.unsupported;

    try {
      final value = await _channel.invokeMethod<String>('getAssistantStatus');
      return switch (value) {
        'active' => AndroidAssistantStatus.active,
        'available' => AndroidAssistantStatus.available,
        'manual' => AndroidAssistantStatus.manual,
        'unsupported' => AndroidAssistantStatus.unsupported,
        _ => AndroidAssistantStatus.unknown,
      };
    } on PlatformException catch (error) {
      Log.error('Unable to read Android assistant status: $error');
      return AndroidAssistantStatus.unknown;
    }
  }

  Future<bool> requestRole() async {
    if (!isSupportedPlatform) return false;
    return await _channel.invokeMethod<bool>('requestAssistantRole') ?? false;
  }

  Future<void> openSettings() async {
    if (!isSupportedPlatform) return;
    await _channel.invokeMethod<void>('openAssistantSettings');
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'assistantInvoked') {
      throw MissingPluginException(
        'Unknown Android assistant call: ${call.method}',
      );
    }

    if (!_disposed) {
      _invocations.add(null);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _invocations.close();
  }
}

final androidAssistantServiceProvider = Provider<AndroidAssistantService>((
  ref,
) {
  final service = AndroidAssistantService();
  ref.onDispose(service.dispose);
  return service;
});
