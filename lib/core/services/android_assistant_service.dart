import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logger/app_logger.dart';

enum AndroidAssistantStatus { unsupported, available, active, manual, unknown }

/// An assistant invocation reach event. [screenshotPath] points at a screen
/// snapshot captured on the native side before the app surfaced, or is null
/// when no capture was available (screen capture disabled or unsupported).
class AssistantInvocation {
  const AssistantInvocation({
    this.screenshotPath,
    this.assistantInvoked = false,
  });

  final String? screenshotPath;

  /// True when this event came from an assistant (ASSIST) invocation rather
  /// than a generic opening of voice mode; used by the UI for context-aware
  /// hints only.
  final bool assistantInvoked;
}

class AndroidAssistantService {
  AndroidAssistantService({MethodChannel? channel, bool? supportedPlatform})
    : _channel = channel ?? const MethodChannel(_channelName),
      _supportedPlatformOverride = supportedPlatform;

  static const _channelName = 'localmind/android_assistant';

  final MethodChannel _channel;
  final bool? _supportedPlatformOverride;
  final StreamController<AssistantInvocation> _invocations =
      StreamController<AssistantInvocation>.broadcast();

  bool _initialized = false;
  bool _disposed = false;

  bool get isSupportedPlatform =>
      _supportedPlatformOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Stream<AssistantInvocation> get invocations => _invocations.stream;

  Future<void> initialize() async {
    if (!isSupportedPlatform || _initialized || _disposed) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleNativeCall);

    try {
      final data =
          await _channel.invokeMethod<Map<Object?, Object?>>(
            'consumePendingInvocation',
          ) ??
          const {};
      final pending = data['pending'] == true;
      if (!pending || _disposed) return;
      // Media capture is still resolving on the native side; the invocation
      // event (with its screenshot path) arrives via assistantScreenshotReady.
      if (data['screenshotPending'] == true) return;
      if (!_disposed) {
        _addInvocation(data, assistantInvoked: true);
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

  /// Whether the screen-capture accessibility service is enabled, i.e. the
  /// assistant's "read the current screen" feature is usable.
  Future<bool> isScreenCaptureEnabled() async {
    if (!isSupportedPlatform) return false;
    return await _channel.invokeMethod<bool>('isScreenshotCaptureEnabled') ??
        false;
  }

  /// Opens the OS accessibility settings so the user can enable the
  /// screen-capture service.
  Future<void> openScreenCaptureSettings() async {
    if (!isSupportedPlatform) return;
    await _channel.invokeMethod<void>('openScreenCaptureSettings');
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'assistantInvoked':
        _addInvocation(call.arguments, assistantInvoked: true);
        return true;
      case 'assistantScreenshotReady':
        _addInvocation(call.arguments, assistantInvoked: true);
        return true;
      default:
        throw MissingPluginException(
          'Unknown Android assistant call: ${call.method}',
        );
    }
  }

  void _addInvocation(Object? arguments, {required bool assistantInvoked}) {
    if (_disposed) return;
    final path = arguments is Map
        ? arguments['screenshotPath'] as String?
        : null;
    _invocations.add(
      AssistantInvocation(
        screenshotPath: path,
        assistantInvoked: assistantInvoked,
      ),
    );
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
