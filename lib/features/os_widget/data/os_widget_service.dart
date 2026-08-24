import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../../core/logger/app_logger.dart';
import 'models/os_widget_models.dart';

class OsWidgetService {
  OsWidgetService({this.isSupportedOverride});

  final bool? isSupportedOverride;
  final StreamController<OsWidgetInvocation> _invocations =
      StreamController<OsWidgetInvocation>.broadcast();

  StreamSubscription<Uri?>? _widgetClickSubscription;
  bool _initialized = false;
  bool _disposed = false;

  static const String androidWidgetName = 'LocalMindWidgetProvider';
  static const String iOSWidgetName = 'LocalMindWidget';
  static const String appGroupId = 'group.pro.momin.localmind';

  bool get isSupportedPlatform =>
      isSupportedOverride ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));

  Stream<OsWidgetInvocation> get invocations => _invocations.stream;

  Future<void> initialize() async {
    if (!isSupportedPlatform || _initialized || _disposed) return;
    _initialized = true;

    try {
      await HomeWidget.setAppGroupId(appGroupId);

      // Handle initial launch from widget
      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initialUri != null && !_disposed) {
        Log.info('App initially launched from widget: $initialUri');
        _invocations.add(OsWidgetInvocation.fromUri(initialUri));
      }

      // Listen to subsequent clicks while app is alive
      _widgetClickSubscription = HomeWidget.widgetClicked.listen((uri) {
        if (uri != null && !_disposed) {
          Log.info('Widget clicked: $uri');
          _invocations.add(OsWidgetInvocation.fromUri(uri));
        }
      });
    } catch (e) {
      Log.error('Failed to initialize OsWidgetService: $e');
    }
  }

  Future<void> updateWidgetSnapshot({
    required String? modelName,
    required bool isConfigured,
  }) async {
    if (!isSupportedPlatform) return;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      await HomeWidget.saveWidgetData<String>('model_name', modelName ?? '');
      await HomeWidget.saveWidgetData<bool>('is_configured', isConfigured);

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        iOSName: iOSWidgetName,
      );
    } catch (e) {
      Log.warning('Failed to update OS widget snapshot: $e');
    }
  }

  void dispatchInvocation(OsWidgetInvocation invocation) {
    if (!_disposed) {
      _invocations.add(invocation);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _widgetClickSubscription?.cancel();
    await _invocations.close();
  }
}
