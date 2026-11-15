import 'dart:async';

// The controller field is wired through the named constructor parameter.
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/logger/app_logger.dart';
import 'download_engine.dart';

/// Bridges app lifecycle and connectivity events to the download engine:
/// backgrounding/detachment/network loss gracefully pause all in-app
/// transfers; returning to the foreground (or network return) resumes the
/// system-paused set when auto-resume is enabled.
class DownloadLifecycleObserver with WidgetsBindingObserver {
  DownloadLifecycleObserver({
    required DownloadLifecycleController controller,
    required this.autoResumeEnabled,
    this.resumeDebounce = const Duration(milliseconds: 500),
  }) : _controller = controller;

  final DownloadLifecycleController _controller;
  final bool Function() autoResumeEnabled;
  final Duration resumeDebounce;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _resumeTimer;
  bool _lastKnownOnline = true;
  bool _started = false;

  /// Mobile apps suspend on background — `inactive` precedes it there and is
  /// worth pausing on. Desktop apps merely lose focus on `inactive`; pausing
  /// on every alt-tab would halt downloads needlessly, so it is ignored.
  static bool get _isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(handleConnectivity, onError: (Object e) {
      Log.warning('Connectivity stream error ignored: $e');
    });
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
    _resumeTimer?.cancel();
  }

  @visibleForTesting
  Future<void> handleLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        await _controller.pauseAllRunning();
      case AppLifecycleState.inactive:
        if (_isMobile) {
          await _controller.pauseAllRunning();
        }
      case AppLifecycleState.resumed:
        if (autoResumeEnabled()) {
          await _controller.resumeSystemPaused();
        }
    }
  }

  @visibleForTesting
  Future<void> handleConnectivity(List<ConnectivityResult> results) async {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online == _lastKnownOnline) return;
    _lastKnownOnline = online;
    if (!online) {
      await _controller.pauseAllRunning(note: 'network: connection lost');
      return;
    }
    // Connectivity restored: debounce brief flaps, then resume the
    // system-paused set when auto-resume is enabled.
    _resumeTimer?.cancel();
    _resumeTimer = Timer(resumeDebounce, () async {
      if (autoResumeEnabled()) {
        await _controller.resumeSystemPaused();
      }
    });
  }
}
