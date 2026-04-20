import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/storage_providers.dart';
import '../data/models/download_progress_info.dart';
import '../data/models/download_status.dart';
import 'on_device_providers.dart';

final foregroundDownloadNotifierProvider =
    NotifierProvider<
      ForegroundDownloadNotifier,
      Map<String, DownloadProgressInfo>
    >(() {
      return ForegroundDownloadNotifier();
    });

class ForegroundDownloadNotifier
    extends Notifier<Map<String, DownloadProgressInfo>> {
  final Map<String, StreamSubscription<DownloadStatusUpdate>> _subscriptions =
      {};
  static const _storageKey = 'model_downloads_state';

  @override
  Map<String, DownloadProgressInfo> build() {
    ref.onDispose(() {
      for (final sub in _subscriptions.values) {
        sub.cancel();
      }
      _subscriptions.clear();
    });

    return _loadState();
  }

  Map<String, DownloadProgressInfo> _loadState() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final Map<String, dynamic> data = json.decode(jsonStr);
        return data.map((k, v) {
          final info = DownloadProgressInfo.fromJson(v);
          // If status was active, mark as paused on app restart
          if (info.status == DownloadStatus.running ||
              info.status == DownloadStatus.pending) {
            return MapEntry(k, info.copyWith(status: DownloadStatus.paused));
          }
          return MapEntry(k, info);
        });
      }
    } catch (e) {
      // Ignore errors loading state
    }
    return {};
  }

  void _saveState() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final data = state.map((k, v) => MapEntry(k, v.toJson()));
      prefs.setString(_storageKey, json.encode(data));
    } catch (e) {
      // Ignore errors saving state
    }
  }

  Future<void> startDownload(String modelId) async {
    final models = ref.read(onDeviceModelsProvider);
    final model = models.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );

    // If we have existing progress, preserve it but set status to running
    final existingInfo = state[modelId];
    state = {
      ...state,
      modelId:
          existingInfo?.copyWith(status: DownloadStatus.running) ??
          DownloadProgressInfo(
            modelId: modelId,
            status: DownloadStatus.running,
            progress: 0.0,
          ),
    };
    _saveState();

    final downloadService = ref.read(foregroundDownloadServiceProvider);

    // Listen to status updates for this model
    _subscriptions[modelId]?.cancel();
    _subscriptions[modelId] = downloadService.getStatusStream(modelId).listen((
      update,
    ) {
      final currentInfo = state[update.modelId];
      
      // Merge progress: if update has 0 progress but we have current progress (e.g. from pause),
      // we might want to keep the current one unless it's a real restart.
      // Actually, service sends 0 for terminal states like failed/canceled.
      
      final info = DownloadProgressInfo(
        modelId: update.modelId,
        status: update.status,
        progress: update.status == DownloadStatus.paused || update.status == DownloadStatus.canceled
            ? (currentInfo?.progress ?? 0.0)
            : update.progress / 100.0,
        taskId: update.taskId,
        receivedBytes: update.status == DownloadStatus.paused || update.status == DownloadStatus.canceled
            ? (currentInfo?.receivedBytes ?? 0)
            : update.receivedBytes,
        totalBytes: update.status == DownloadStatus.paused || update.status == DownloadStatus.canceled
            ? (currentInfo?.totalBytes ?? 0)
            : update.totalBytes,
        bytesPerSecond: update.bytesPerSecond,
        etaSeconds: update.etaSeconds,
        isResumed: update.isResumed,
      );
      
      state = {...state, update.modelId: info};
      _saveState();

      if (update.status == DownloadStatus.complete) {
        ref.invalidate(downloadedModelsProvider);
        _removeCompletedDownload(update.modelId);
      } else if (update.status == DownloadStatus.failed ||
          update.status == DownloadStatus.canceled ||
          update.status == DownloadStatus.paused) {
        state = {
          ...state,
          update.modelId: info.copyWith(
            status: update.status,
            error: update.status == DownloadStatus.failed
                ? 'Download failed'
                : null,
          ),
        };
        _saveState();
      }
    });

    try {
      await downloadService.downloadModel(model);
    } catch (e) {
      // Error handled via stream
    }
  }

  void _removeCompletedDownload(String modelId) {
    // Small delay to let UI show 100%
    Future.delayed(const Duration(seconds: 1), () {
      if (state.containsKey(modelId)) {
        final current = Map<String, DownloadProgressInfo>.from(state);
        current.remove(modelId);
        state = current;
        _saveState();
        _subscriptions[modelId]?.cancel();
        _subscriptions.remove(modelId);
      }
    });
  }

  Future<void> cancelDownload(String modelId) async {
    final downloadService = ref.read(foregroundDownloadServiceProvider);
    await downloadService.cancelDownload(modelId);
    state = {...state}..remove(modelId);
    _saveState();
    _subscriptions[modelId]?.cancel();
    _subscriptions.remove(modelId);
  }

  Future<void> pauseDownload(String modelId) async {
    final downloadService = ref.read(foregroundDownloadServiceProvider);
    downloadService.pauseDownload(modelId);
  }

  Future<void> resumeDownload(String modelId) async {
    await startDownload(modelId);
  }

  Future<void> retryDownload(String modelId) async {
    await cancelDownload(modelId);
    await startDownload(modelId);
  }

  DownloadProgressInfo? getProgressForModel(String modelId) {
    return state[modelId];
  }

  bool isDownloading(String modelId) {
    final info = state[modelId];
    return info != null &&
        (info.status == DownloadStatus.running ||
            info.status == DownloadStatus.pending);
  }
}
