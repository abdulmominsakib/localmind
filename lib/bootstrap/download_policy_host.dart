import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_providers.dart';
import '../features/settings/data/models/app_settings.dart';
import '../features/on_device/data/models/download_status.dart';
import '../features/on_device/providers/foreground_download_providers.dart';

/// Hosts the download policy: applies WiFi policy and pauses/resumes active
/// downloads based on the "allow background downloads" setting and app lifecycle.
class DownloadPolicyHost extends ConsumerStatefulWidget {
  const DownloadPolicyHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DownloadPolicyHost> createState() => _DownloadPolicyHostState();
}

class _DownloadPolicyHostState extends ConsumerState<DownloadPolicyHost>
    with WidgetsBindingObserver {
  final Set<String> _backgroundPaused = <String>{};
  ProviderSubscription<AppSettings>? _settingsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsSub = ref.listenManual(settingsProvider, (prev, next) {
      _applyWifiPolicy(next?.downloadOverWifiOnly ?? true);
    });
    // Apply initial WiFi policy.
    final wifiOnly = ref.read(settingsProvider).downloadOverWifiOnly;
    _applyWifiPolicy(wifiOnly);
  }

  void _applyWifiPolicy(bool wifiOnly) {
    // Fire-and-forget; requireWiFi is async but we don't block UI.
    // ignore: unawaited_futures
    FileDownloader().requireWiFi(
      wifiOnly ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks,
      rescheduleRunningTasks: true,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final allowBg = ref.read(settingsProvider).allowBackgroundDownloads;
    if (allowBg) return; // background downloads allowed — do nothing

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pauseActiveDownloads();
    } else if (state == AppLifecycleState.resumed) {
      _resumePausedDownloads();
    }
  }

  void _pauseActiveDownloads() {
    final notifier = ref.read(foregroundDownloadNotifierProvider.notifier);
    final current = ref.read(foregroundDownloadNotifierProvider);
    for (final entry in current.entries) {
      final info = entry.value;
      if (info.status == DownloadStatus.running) {
        _backgroundPaused.add(entry.key);
        // ignore: unawaited_futures
        notifier.pauseDownload(entry.key);
      }
    }
  }

  void _resumePausedDownloads() {
    if (_backgroundPaused.isEmpty) return;
    final notifier = ref.read(foregroundDownloadNotifierProvider.notifier);
    final toResume = List<String>.from(_backgroundPaused);
    _backgroundPaused.clear();
    for (final id in toResume) {
      // ignore: unawaited_futures
      notifier.resumeDownload(id);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settingsSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
