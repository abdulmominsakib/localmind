import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  Map<String, DownloadProgressInfo> build() {
    ref.onDispose(() {
      for (final sub in _subscriptions.values) {
        sub.cancel();
      }
      _subscriptions.clear();
    });
    return {};
  }

  Future<void> startDownload(String modelId) async {
    final models = ref.read(onDeviceModelsProvider);
    final model = models.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );

    state = {
      ...state,
      modelId: DownloadProgressInfo(
        modelId: modelId,
        status: DownloadStatus.running,
        progress: 0.0,
      ),
    };

    final downloadService = ref.read(foregroundDownloadServiceProvider);

    // Listen to status updates for this model
    _subscriptions[modelId]?.cancel();
    _subscriptions[modelId] = downloadService.getStatusStream(modelId).listen((
      update,
    ) {
      final info = DownloadProgressInfo(
        modelId: update.modelId,
        status: update.status,
        progress: update.progress / 100.0,
        taskId: update.taskId,
      );
      state = {...state, update.modelId: info};

      if (update.status == DownloadStatus.complete) {
        ref.invalidate(downloadedModelsProvider);
        state = {...state}..remove(update.modelId);
        _removeCompletedDownload(update.modelId);
      } else if (update.status == DownloadStatus.failed ||
          update.status == DownloadStatus.canceled) {
        state = {
          ...state,
          update.modelId: info.copyWith(
            status: update.status,
            error: update.status == DownloadStatus.failed
                ? 'Download failed'
                : 'Download canceled',
          ),
        };
        _removeCompletedDownload(update.modelId);
      }
    });

    try {
      await downloadService.downloadModel(model);
    } catch (e) {
      // Error already handled via stream
    }
  }

  void _removeCompletedDownload(String modelId) {
    final current = Map<String, DownloadProgressInfo>.from(state);
    current.remove(modelId);
    state = current;
    _subscriptions[modelId]?.cancel();
    _subscriptions.remove(modelId);
  }

  Future<void> cancelDownload(String modelId) async {
    final downloadService = ref.read(foregroundDownloadServiceProvider);
    await downloadService.cancelDownload(modelId);
    state = {...state}..remove(modelId);
    _subscriptions[modelId]?.cancel();
    _subscriptions.remove(modelId);
  }

  // Pause and resume are not supported
  Future<void> pauseDownload(String modelId) async {
    // No-op
  }

  Future<void> resumeDownload(String modelId) async {
    // No-op
  }

  Future<void> retryDownload(String modelId) async {
    final downloadService = ref.read(foregroundDownloadServiceProvider);
    await downloadService.retryDownload(modelId);
    // Restart download
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
