import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:background_downloader/background_downloader.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/review_prompt_providers.dart';
import '../../../core/providers/storage_providers.dart';
import '../data/models/download_progress_info.dart';
import '../data/models/download_status.dart';
import '../data/models/on_device_model.dart';
import '../utils/on_device_error_formatter.dart';
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
  final Map<String, bool> _activeDownloads = {};
  final Map<String, DateTime> _downloadStartTimes = {};
  final Set<String> _pausedDownloads = {};
  final Map<String, CancelToken> _cancelTokens = {};
  static const _storageKey = 'model_downloads_state';

  @override
  Map<String, DownloadProgressInfo> build() {
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

  Future<String?> startDownload(String modelId) async {
    final models = ref.read(onDeviceModelsProvider);
    final model = models.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );

    if (model.requiresHuggingFaceToken) {
      final hfToken = ref.read(
        settingsProvider.select((s) => s.huggingFaceToken),
      );
      if (hfToken == null || hfToken.isEmpty) {
        return 'missing_huggingface_token';
      }
    }

    if (_activeDownloads[modelId] == true) {
      return null;
    }
    _activeDownloads[modelId] = true;
    _downloadStartTimes[modelId] = DateTime.now();

    final existingInfo = state[modelId];
    state = {
      ...state,
      modelId: DownloadProgressInfo(
        modelId: modelId,
        status: DownloadStatus.running,
        progress: existingInfo?.progress ?? 0.0,
        receivedBytes: existingInfo?.receivedBytes ?? 0,
        totalBytes: existingInfo?.totalBytes ?? model.fileSizeBytes,
      ),
    };
    _saveState();

    final gemmaService = ref.read(onDeviceGemmaServiceProvider);
    final mlxService = ref.read(onDeviceMlxServiceProvider);
    final hfToken = ref.read(
      settingsProvider.select((s) => s.huggingFaceToken),
    );

    try {
      if (model.runtime == OnDeviceModelRuntime.mlx) {
        await mlxService.downloadModel(
          model,
          huggingFaceToken: (hfToken != null && hfToken.isNotEmpty)
              ? hfToken
              : null,
          onProgress: (received, total) {
            if (!ref.mounted || _activeDownloads[modelId] != true) return;
            if (_pausedDownloads.contains(modelId)) return;

            final startTime = _downloadStartTimes[modelId] ?? DateTime.now();
            final elapsed = DateTime.now().difference(startTime).inSeconds;
            final bytesPerSecond = elapsed > 0
                ? (received / elapsed).round()
                : 0;
            final etaSeconds = bytesPerSecond > 0
                ? ((total - received) / bytesPerSecond).round()
                : null;

            final progress = total > 0 ? (received / total) : 0.0;

            state = {
              ...state,
              modelId: DownloadProgressInfo(
                modelId: modelId,
                status: DownloadStatus.running,
                progress: progress.clamp(0.0, 1.0),
                receivedBytes: received.clamp(0, total > 0 ? total : received),
                totalBytes: total,
                bytesPerSecond: bytesPerSecond,
                etaSeconds: etaSeconds,
              ),
            };
            _saveState();
          },
        );
      } else if (model.isImported && model.isLlamaCpp) {
        final repository = ref.read(importedGgufModelRepositoryProvider);
        final cancelToken = CancelToken();
        _cancelTokens[modelId] = cancelToken;
        await repository.download(
          model.id,
          token: (hfToken != null && hfToken.isNotEmpty) ? hfToken : null,
          cancelToken: cancelToken,
          onProgress: (received, total) {
            if (!ref.mounted || _activeDownloads[modelId] != true) return;
            if (_pausedDownloads.contains(modelId)) return;

            final startTime = _downloadStartTimes[modelId] ?? DateTime.now();
            final elapsed = DateTime.now().difference(startTime).inSeconds;
            final bytesPerSecond = elapsed > 0
                ? (received / elapsed).round()
                : 0;
            final etaSeconds = bytesPerSecond > 0
                ? ((total - received) / bytesPerSecond).round()
                : null;
            final progress = total > 0 ? (received / total) : 0.0;

            state = {
              ...state,
              modelId: DownloadProgressInfo(
                modelId: modelId,
                status: DownloadStatus.running,
                progress: progress.clamp(0.0, 1.0),
                receivedBytes: received.clamp(0, total > 0 ? total : received),
                totalBytes: total > 0 ? total : model.fileSizeBytes,
                bytesPerSecond: bytesPerSecond,
                etaSeconds: etaSeconds,
              ),
            };
            _saveState();
          },
        );
        await ref.read(importedGgufModelsProvider.notifier).pruneMissing();
      } else if (model.isImported &&
          model.runtime == OnDeviceModelRuntime.gemma) {
        final repository = ref.read(importedLitertModelRepositoryProvider);
        final status = await repository.download(
          model.id,
          token: (hfToken != null && hfToken.isNotEmpty) ? hfToken : null,
          onProgress: (received, total) {
            if (!ref.mounted || _activeDownloads[modelId] != true) return;
            if (_pausedDownloads.contains(modelId)) return;

            final clampedReceived = received.clamp(0, total > 0 ? total : received);
            final startTime = _downloadStartTimes[modelId] ?? DateTime.now();
            final elapsed = DateTime.now().difference(startTime).inSeconds;
            final bytesPerSecond = elapsed > 0
                ? (clampedReceived / elapsed).round()
                : 0;
            final etaSeconds = bytesPerSecond > 0 && total > clampedReceived
                ? ((total - clampedReceived) / bytesPerSecond).round()
                : null;
            final progress = total > 0 ? (clampedReceived / total) : 0.0;

            state = {
              ...state,
              modelId: DownloadProgressInfo(
                modelId: modelId,
                status: DownloadStatus.running,
                progress: progress.clamp(0.0, 1.0),
                receivedBytes: clampedReceived,
                totalBytes: total > 0 ? total : model.fileSizeBytes,
                bytesPerSecond: bytesPerSecond,
                etaSeconds: etaSeconds,
              ),
            };
            _saveState();
          },
        );
        if (status == TaskStatus.paused) {
          // Paused by user; state already reflects paused. Do not mark complete.
          return null;
        }
        await ref.read(importedLitertModelsProvider.notifier).pruneMissing();
      } else {
        await gemmaService.installModel(
          model,
          token: (hfToken != null && hfToken.isNotEmpty) ? hfToken : null,
          onProgress: (progress) {
            final startTime = _downloadStartTimes[modelId] ?? DateTime.now();
            final elapsed = DateTime.now().difference(startTime).inSeconds;
            final total = model.fileSizeBytes > 0 ? model.fileSizeBytes : 100;
            final received = model.fileSizeBytes > 0
                ? ((progress / 100.0) * total).round()
                : progress;

            final bytesPerSecond = elapsed > 0
                ? (received / elapsed).round()
                : 0;
            final etaSeconds = bytesPerSecond > 0
                ? ((total - received) / bytesPerSecond).round()
                : null;

            state = {
              ...state,
              modelId: DownloadProgressInfo(
                modelId: modelId,
                status: DownloadStatus.running,
                progress: progress / 100.0,
                receivedBytes: received.clamp(0, total > 0 ? total : received),
                totalBytes: total,
                bytesPerSecond: bytesPerSecond,
                etaSeconds: etaSeconds,
              ),
            };
            _saveState();
          },
        );
      }

      // Download completed
      if (_activeDownloads[modelId] == true) {
        if (ref.mounted) {
          state = {
            ...state,
            modelId: DownloadProgressInfo(
              modelId: modelId,
              status: DownloadStatus.complete,
              progress: 1.0,
              receivedBytes: model.fileSizeBytes > 0
                  ? model.fileSizeBytes
                  : 100,
              totalBytes: model.fileSizeBytes > 0 ? model.fileSizeBytes : 100,
            ),
          };
          _saveState();

          ref.invalidate(downloadedModelsProvider);
          try {
            await ref
                .read(reviewPromptServiceProvider)
                .markModelDownloadCompleted(modelId);
          } catch (e) {
            Log.error('Failed to record model download review signal: $e');
          }
          _removeCompletedDownload(modelId);
        }
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isPaused = msg.contains('paused');
      final isCanceled = msg.contains('canceled') || msg.contains('cancelled');
      if (!isPaused) {
        Log.error('Download failed for $modelId: $e');
      }
      if (_activeDownloads[modelId] == true && ref.mounted) {
        final current = state[modelId];
        if (isPaused) {
          state = {
            ...state,
            modelId: (current ?? DownloadProgressInfo(modelId: modelId)).copyWith(
              status: DownloadStatus.paused,
            ),
          };
        } else if (isCanceled) {
          state = {...state}..remove(modelId);
        } else {
          final formattedError = formatOnDeviceError(
            e,
            isBuiltIn: model.isBuiltIn,
          );
          state = {
            ...state,
            modelId: DownloadProgressInfo(
              modelId: modelId,
              status: DownloadStatus.failed,
              progress: state[modelId]?.progress ?? 0.0,
              receivedBytes: state[modelId]?.receivedBytes ?? 0,
              totalBytes: state[modelId]?.totalBytes ?? 0,
              error: formattedError,
            ),
          };
        }
        _saveState();
      }
    } finally {
      final wasPaused = _pausedDownloads.contains(modelId);
      if (!wasPaused) {
        _activeDownloads.remove(modelId);
        _downloadStartTimes.remove(modelId);
      }
      _cancelTokens.remove(modelId);
    }
    return null;
  }

  void _removeCompletedDownload(String modelId) {
    Future.delayed(const Duration(seconds: 1), () {
      if (!ref.mounted || !state.containsKey(modelId)) return;
      final current = Map<String, DownloadProgressInfo>.from(state);
      current.remove(modelId);
      state = current;
      _saveState();
    });
  }

  Future<void> cancelDownload(String modelId) async {
    final mlxService = ref.read(onDeviceMlxServiceProvider);
    mlxService.cancelDownload(modelId);
    final cancelToken = _cancelTokens.remove(modelId);
    cancelToken?.cancel('Canceled by user');

    final models = ref.read(onDeviceModelsProvider);
    final model = models.where((m) => m.id == modelId).firstOrNull;
    if (model != null &&
        model.isImported &&
        model.runtime == OnDeviceModelRuntime.gemma) {
      final repository = ref.read(importedLitertModelRepositoryProvider);
      await repository.cancelDownload(modelId);
    }

    _activeDownloads.remove(modelId);
    _downloadStartTimes.remove(modelId);
    state = {...state}..remove(modelId);
    _saveState();
  }

  Future<void> pauseDownload(String modelId) async {
    _pausedDownloads.add(modelId);
    final models = ref.read(onDeviceModelsProvider);
    final model = models.where((m) => m.id == modelId).firstOrNull;
    var paused = false;
    if (model != null && model.isImported) {
      if (model.runtime == OnDeviceModelRuntime.gemma) {
        final repository = ref.read(importedLitertModelRepositoryProvider);
        paused = await repository.pauseDownload(modelId);
      } else if (model.isLlamaCpp) {
        final repository = ref.read(importedGgufModelRepositoryProvider);
        final token = _cancelTokens.remove(modelId);
        token?.cancel('Paused by user');
        paused = await repository.pauseDownload(modelId);
      }
    }
    final info = state[modelId];
    if (info != null) {
      state = {
        ...state,
        modelId: info.copyWith(status: DownloadStatus.paused),
      };
      _saveState();
    }
    if (!paused) {
      _pausedDownloads.remove(modelId);
    }
  }

  Future<void> resumeDownload(String modelId) async {
    final models = ref.read(onDeviceModelsProvider);
    final model = models.where((m) => m.id == modelId).firstOrNull;
    if (model == null) return;

    // Allow startDownload to re-run the full flow (it has a single-flight guard).
    _pausedDownloads.remove(modelId);
    _activeDownloads[modelId] = false;
    _activeDownloads.remove(modelId);

    final info = state[modelId];
    if (info != null) {
      state = {
        ...state,
        modelId: info.copyWith(status: DownloadStatus.running),
      };
      _saveState();
    }

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
