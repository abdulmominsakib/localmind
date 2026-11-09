import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_providers.dart';
import '../features/settings/data/models/app_settings.dart';
import '../features/on_device/data/models/download_status.dart';
import '../features/on_device/data/models/download_progress_info.dart';
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
  ProviderSubscription<AppSettings>? _settingsSub;
  ProviderSubscription<Map<String, DownloadProgressInfo>>? _stateSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsSub = ref.listenManual(settingsProvider, (prev, next) {
      _applyWifiPolicy(next.downloadOverWifiOnly);
      // Apply background toggle changes to in-flight downloads.
      if (prev != null &&
          prev.allowBackgroundDownloads != next.allowBackgroundDownloads) {
        if (next.allowBackgroundDownloads) {
          _resumePolicyPaused();
        } else {
          _pauseActiveDownloads();
        }
      }
    });
    // Apply initial WiFi policy.
    final wifiOnly = ref.read(settingsProvider).downloadOverWifiOnly;
    _applyWifiPolicy(wifiOnly);

    // Cold-start: resume background-policy-paused downloads once hydrated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resumePolicyPaused();
    });
  }

  void _applyWifiPolicy(bool wifiOnly) {
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
      _resumePolicyPaused();
    }
  }

  void _pauseActiveDownloads() {
    final notifier = ref.read(foregroundDownloadNotifierProvider.notifier);
    final current = ref.read(foregroundDownloadNotifierProvider);
    for (final entry in current.entries) {
      final info = entry.value;
      if (info.status == DownloadStatus.running) {
        // ignore: unawaited_futures
        notifier.pauseDownload(entry.key, reason: DownloadPauseReason.backgroundPolicy);
      }
    }
  }

  void _resumePolicyPaused() {
    final notifier = ref.read(foregroundDownloadNotifierProvider.notifier);
    final state = ref.read(foregroundDownloadNotifierProvider);
    for (final entry in state.entries) {
      final info = entry.value;
      if (info.status != DownloadStatus.paused) continue;
      if (info.pauseReason != DownloadPauseReason.backgroundPolicy) continue;
      // ignore: unawaited_futures
      notifier.resumeDownload(entry.key);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settingsSub?.close();
    _stateSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
