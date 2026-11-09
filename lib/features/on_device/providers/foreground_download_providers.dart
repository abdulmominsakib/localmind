import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/review_prompt_providers.dart';
import '../../../core/providers/storage_providers.dart';
import '../data/models/download_progress_info.dart';
import '../data/download_operation_store.dart';
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
  final Set<String> _cancelled = {};
  // Operation-scoped state (generation token). Model-scoped state above is
  // retained for compatibility but new code should use these.
  int _opCounter = 0;
  final Map<String, String> _activeOperationIds = {}; // modelId -> opId
  final Set<String> _pausedOperations = {}; // opIds
  final Set<String> _cancelRequested = {}; // opIds
  final Map<String, int> _sessionBaselineBytes = {}; // modelId -> baseline
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, gemma.CancelToken> _gemmaCancelTokens = {};
  final Map<String, Future<String?>> _inFlightDownloads = {};
  final Set<String> _updateInProgress = {};
  Timer? _hydrationPollTimer;
  DownloadOperationStore? _operations;
  bool _isHydrating = false;
  static const _storageKey = 'model_downloads_state';

  @override
  Map<String, DownloadProgressInfo> build() {
    ref.onDispose(() => _hydrationPollTimer?.cancel());
    _operations = ref.read(downloadOperationStoreProvider);
    _operations!.loadSync();
    ref.listen(settingsProvider.select((s) => s.huggingFaceToken), (prev, next) {
      if (prev == next) return;
      // Scrub persisted downloader task records so a cleared/replaced
      // credential does not linger in the task database.
      ref.read(importedLitertModelRepositoryProvider).scrubDownloadTaskRecords();
      ref.read(importedGgufModelRepositoryProvider).scrubDownloadTaskRecords();
    });
    return _loadState();
  }


  String _beginOperation(String modelId, {int baselineBytes = 0}) {
    final opId = '$modelId:${DateTime.now().microsecondsSinceEpoch}:${++_opCounter}';
    _activeOperationIds[modelId] = opId;
    _activeDownloads[modelId] = true;
    _downloadStartTimes[modelId] = DateTime.now();
    _sessionBaselineBytes[modelId] = baselineBytes;
    _cancelled.remove(modelId);
    _pausedDownloads.remove(modelId);
    _pausedOperations.removeWhere((o) => o.startsWith('$modelId:'));
    _cancelRequested.removeWhere((o) => o.startsWith('$modelId:'));
    return opId;
  }

  bool _isActiveOp(String modelId, String opId) =>
      _activeOperationIds[modelId] == opId;

  void _endOperation(String modelId, String opId) {
    if (_activeOperationIds[modelId] != opId) return;
    _activeOperationIds.remove(modelId);
    _activeDownloads.remove(modelId);
    _downloadStartTimes.remove(modelId);
    _sessionBaselineBytes.remove(modelId);
    _pausedOperations.remove(opId);
    _cancelRequested.remove(opId);
  }

  /// Hydrate download state from persisted background tasks. Called from
  /// BootstrapHost after reconcile. Never enqueues or resumes.
  Future<void> hydrateFromBackground() async {
    if (_isHydrating) return;
    _isHydrating = true;
    try {
      const groups = ['localmind_litert_downloads', 'localmind_gguf_downloads'];
      final allRecords = <TaskRecord>[];
      for (final g in groups) {
        try {
          allRecords.addAll(await FileDownloader().database.allRecords(group: g));
        } catch (_) {}
      }

      // Dedupe by (group, taskId) — pick highest progress for same id.
      final byKey = <String, TaskRecord>{};
      for (final r in allRecords) {
        final key = '${r.task.group ?? ''}:${r.task.taskId}';
        final existing = byKey[key];
        if (existing == null || r.progress > existing.progress) {
          byKey[key] = r;
        }
      }

      final models = ref.read(onDeviceModelsProvider);
      final next = Map<String, DownloadProgressInfo>.from(state);

      for (final r in byKey.values) {
        final rawTaskId = r.task.taskId;
        final isUpdate = rawTaskId.endsWith('-update');
        final modelId = isUpdate
            ? rawTaskId.substring(0, rawTaskId.length - '-update'.length)
            : rawTaskId;
        final model = models.where((m) => m.id == modelId).firstOrNull;
        if (model == null) continue; // model removed from list

        // Terminal states.
        if (r.status == TaskStatus.complete) {
          // Reconcile handles filePath; just remove telemetry entry.
          next.remove(modelId);
          continue;
        }
        if (r.status == TaskStatus.canceled) {
          next.remove(modelId);
          continue;
        }
        if (r.status == TaskStatus.failed) {
          next[modelId] = DownloadProgressInfo(
            modelId: modelId,
            status: DownloadStatus.failed,
            progress: 0.0,
            receivedBytes: 0,
            totalBytes: model.fileSizeBytes,
            error: r.exception?.description,
          );
          continue;
        }
        if (r.status == TaskStatus.notFound) {
          next[modelId] = DownloadProgressInfo(
            modelId: modelId,
            status: DownloadStatus.failed,
            progress: 0.0,
            receivedBytes: 0,
            totalBytes: model.fileSizeBytes,
            error: 'File not found (404).',
          );
          continue;
        }

        // Non-terminal: running/enqueued/waitingToRetry/paused.
        final total = (r.expectedFileSize > 0)
            ? r.expectedFileSize
            : (model.fileSizeBytes > 0 ? model.fileSizeBytes : 0);

        double? progress;
        if (r.progress >= 0 && r.progress <= 1) {
          progress = r.progress;
        }

        final received = (progress != null && total > 0)
            ? (progress * total).round().clamp(0, total)
            : 0;

        final isBg = r.status == TaskStatus.running ||
            r.status == TaskStatus.enqueued ||
            r.status == TaskStatus.waitingToRetry;

        final prev = state[modelId];
        next[modelId] = DownloadProgressInfo(
          modelId: modelId,
          status: r.status == TaskStatus.paused
              ? DownloadStatus.paused
              : DownloadStatus.running,
          progress: progress ?? 0.0,
          receivedBytes: received,
          totalBytes: total,
          taskId: rawTaskId,
          isResumed: isBg,
          pauseReason: r.status == TaskStatus.paused
              ? (prev?.pauseReason ?? DownloadPauseReason.interrupted)
              : null,
          errorCategory: prev?.errorCategory,
        );

        if (isBg) {
          _activeDownloads[modelId] = true;
          _downloadStartTimes[modelId] = DateTime.now();
          if (isUpdate) _updateInProgress.add(modelId);
        }
      }

      if (ref.mounted) {
        state = next;
        _saveState();
      }

      // Start polling for active tasks.
      _startHydrationPolling();
    } catch (_) {
      // Hydration failure is non-fatal.
    } finally {
      _isHydrating = false;
    }
  }

  void _startHydrationPolling() {
    _hydrationPollTimer?.cancel();
    _hydrationPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!ref.mounted) return;
      // Collect active model IDs.
      final activeIds = state.entries
          .where((e) =>
              e.value.status == DownloadStatus.running && e.value.isResumed)
          .map((e) => e.key)
          .toList();
      if (activeIds.isEmpty) {
        _hydrationPollTimer?.cancel();
        _hydrationPollTimer = null;
        return;
      }

      // Query records.
      final records = <TaskRecord>[];
      for (final g in ['localmind_litert_downloads', 'localmind_gguf_downloads']) {
        try {
          records.addAll(await FileDownloader().database.allRecords(group: g));
        } catch (_) {}
      }
      final byId = <String, TaskRecord>{};
      for (final r in records) {
        byId[r.task.taskId] = r;
      }

      final next = Map<String, DownloadProgressInfo>.from(state);
      bool changed = false;
      for (final id in activeIds) {
        // Skip if cancelled or removed from state while we awaited.
        if (_cancelled.contains(id) || !state.containsKey(id)) continue;
        final r = byId[state[id]?.taskId ?? id];
        if (r == null) continue;
        if (r.status == TaskStatus.complete ||
            r.status == TaskStatus.failed ||
            r.status == TaskStatus.canceled ||
            r.status == TaskStatus.notFound) {
          // Terminal — remove from active (reconcile handles completion).
          if (r.status == TaskStatus.complete) {
            next.remove(id);
          } else if (r.status == TaskStatus.failed) {
            final model = ref.read(onDeviceModelsProvider).where((m) => m.id == id).firstOrNull;
            next[id] = DownloadProgressInfo(
              modelId: id,
              status: DownloadStatus.failed,
              progress: 0.0,
              receivedBytes: 0,
              totalBytes: model?.fileSizeBytes ?? 0,
              error: r.exception?.description,
            );
          } else {
            next.remove(id);
          }
          _activeDownloads.remove(id);
          changed = true;
          continue;
        }

        // Non-terminal — update progress.
        final cur = next[id];
        if (cur == null) continue;
        double? progress;
        if (r.progress >= 0 && r.progress <= 1) progress = r.progress;
        final total = (r.expectedFileSize > 0)
            ? r.expectedFileSize
            : (cur.totalBytes > 0 ? cur.totalBytes : 0);
        final received = (progress != null && total > 0)
            ? (progress * total).round().clamp(0, total)
            : cur.receivedBytes;
        if (received >= cur.receivedBytes) {
          next[id] = cur.copyWith(
            status: r.status == TaskStatus.paused
                ? DownloadStatus.paused
                : DownloadStatus.running,
            progress: progress ?? cur.progress,
            receivedBytes: received,
            totalBytes: total > 0 ? total : cur.totalBytes,
          );
          changed = true;
        }
      }

      if (changed && ref.mounted) {
        state = next;
        _saveState();
      }
    });
  }

  Map<String, DownloadProgressInfo> _loadState() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final Map<String, dynamic> data = json.decode(jsonStr);
        final result = <String, DownloadProgressInfo>{};
        for (final e in data.entries) {
          final info = DownloadProgressInfo.fromJson(e.value);
          // `canceled` is transient; never persist it across restarts.
          if (info.status == DownloadStatus.canceled) continue;
          if (info.status == DownloadStatus.running ||
              info.status == DownloadStatus.pending) {
            result[e.key] = info.copyWith(
              status: DownloadStatus.paused,
              pauseReason: info.pauseReason ?? DownloadPauseReason.interrupted,
            );
          } else {
            result[e.key] = info;
          }
        }
        return result;
      }
    } catch (e) {
      // Ignore errors loading state
    }
    return {};
  }

  Future<void> _saveState() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final data = state.map((k, v) => MapEntry(k, v.toJson()));
      final ok = await prefs.setString(_storageKey, json.encode(data));
      if (!ok) {
        Log.warning('Failed to persist download state');
      }
    } catch (e) {
      Log.warning('Failed to persist download state: $e');
    }
  }

  Future<void> _persistState() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final data = state.map((k, v) => MapEntry(k, v.toJson()));
      final ok = await prefs.setString(_storageKey, json.encode(data));
      if (!ok) {
        Log.warning('Failed to persist download state');
      }
    } catch (e) {
      Log.warning('Failed to persist download state: $e');
    }
  }

  Future<String?> startDownload(String modelId) {
    final existing = _inFlightDownloads[modelId];
    if (existing != null) return existing;
    final future = _startDownloadImpl(modelId);
    _inFlightDownloads[modelId] = future;
    future.whenComplete(() {
      if (identical(_inFlightDownloads[modelId], future)) _inFlightDownloads.remove(modelId);
    }).catchError((Object e, StackTrace st) {
      Log.error('startDownload failed for $modelId: $e');
      if (identical(_inFlightDownloads[modelId], future)) _inFlightDownloads.remove(modelId);
      return null;
    });
    return future;
  }

  Future<String?> startUpdateDownload(String modelId) {
    if (_updateInProgress.contains(modelId)) {
      final existing = _inFlightDownloads[modelId];
      if (existing != null) return existing;
      // Already in progress but no future tracked — return null.
      return Future.value(null);
    }
    final existing = _inFlightDownloads[modelId];
    if (existing != null) return existing;
    _updateInProgress.add(modelId);
    final future = _startUpdateDownloadImpl(modelId);
    _inFlightDownloads[modelId] = future;
    future.whenComplete(() {
      if (identical(_inFlightDownloads[modelId], future)) _inFlightDownloads.remove(modelId);
      _updateInProgress.remove(modelId);
    }).catchError((Object e, StackTrace st) {
      Log.error('startUpdateDownload failed for $modelId: $e');
      if (identical(_inFlightDownloads[modelId], future)) _inFlightDownloads.remove(modelId);
      _updateInProgress.remove(modelId);
      return null;
    });
    return future;
  }

  Future<String?> _startUpdateDownloadImpl(String modelId) async {
    if (_activeDownloads[modelId] == true && _updateInProgress.contains(modelId)) {
      // Already running; don't start a duplicate.
      return null;
    }
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

    // If the model is currently loaded for inference, unload it before
    // replacing the underlying file.
    final engineState = ref.read(onDeviceEngineProvider);
    final wasLoaded = engineState.loadedModelId == modelId;
    if (wasLoaded) {
      try {
        await ref.read(onDeviceEngineProvider.notifier).unloadModel();
      } catch (_) {}
    }

    // Allocate operation token (generation guard).
    final baselineBytes = state[modelId]?.receivedBytes ?? 0;
    final opId = _beginOperation(modelId, baselineBytes: baselineBytes);
    final opStart = DateTime.now();

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

    final hfToken = ref.read(
      settingsProvider.select((s) => s.huggingFaceToken),
    );
    final token = (hfToken != null && hfToken.isNotEmpty) ? hfToken : null;

    try {
      TaskStatus status;
      if (model.runtime == OnDeviceModelRuntime.gemma) {
        final repository = ref.read(importedLitertModelRepositoryProvider);
        status = await repository.downloadUpdate(
          modelId,
          token: token,
          operationId: opId,
          onProgress: (received, total) {
            if (!ref.mounted) return;
            if (!_isActiveOp(modelId, opId)) return;
            if (_pausedOperations.contains(opId)) return;
            if (_cancelRequested.contains(opId)) return;
            final progress = total > 0 ? (received / total) : 0.0;
            state = {
              ...state,
              modelId: DownloadProgressInfo(
                modelId: modelId,
                status: DownloadStatus.running,
                progress: progress.clamp(0.0, 1.0),
                receivedBytes: received,
                totalBytes: total,
              ),
            };
          },
        );
      } else if (model.isLlamaCpp) {
        final repository = ref.read(importedGgufModelRepositoryProvider);
        status = await repository.downloadUpdate(
          modelId,
          token: token,
          operationId: opId,
          onProgress: (received, total) {
            if (!ref.mounted) return;
            if (!_isActiveOp(modelId, opId)) return;
            if (_pausedOperations.contains(opId)) return;
            if (_cancelRequested.contains(opId)) return;
            final progress = total > 0 ? (received / total) : 0.0;
            state = {
              ...state,
              modelId: DownloadProgressInfo(
                modelId: modelId,
                status: DownloadStatus.running,
                progress: progress.clamp(0.0, 1.0),
                receivedBytes: received,
                totalBytes: total,
              ),
            };
          },
        );
      } else {
        throw Exception('Unsupported runtime for update: ${model.runtime}');
      }

      if (status == TaskStatus.paused) {
        if (ref.mounted) {
          final info = state[modelId];
          if (info != null) {
            state = {
              ...state,
              modelId: info.copyWith(status: DownloadStatus.paused),
            };
            _saveState();
          }
        }
      } else if (status == TaskStatus.complete) {
        _endOperation(modelId, opId);
        if (ref.mounted) {
          state = {...state}..remove(modelId);
          _saveState();
          // Refresh models list.
          ref.invalidate(importedLitertModelsProvider);
          ref.invalidate(importedGgufModelsProvider);
          ref.invalidate(downloadedModelsProvider);
        }
        // Reload model if it was loaded before update.
        if (wasLoaded && ref.mounted) {
          try {
            final settings = ref.read(settingsProvider);
            await ref.read(onDeviceEngineProvider.notifier).loadModel(modelId, settings.preferredBackend);
          } catch (_) {}
        }
      }
      return null;
    } catch (e) {
      final wasCurrent = _isActiveOp(modelId, opId);
      if (!wasCurrent) return null;
      final msg = e.toString().toLowerCase();
      final isCancel = msg.contains('canceled') || msg.contains('cancelled');
      final isPaused = !isCancel && msg.contains('paused');
      final isCanceled = isCancel || _cancelRequested.contains(opId);
      if (ref.mounted) {
        if (isPaused) {
          state = {
            ...state,
            modelId: (state[modelId] ?? DownloadProgressInfo(modelId: modelId)).copyWith(
              status: DownloadStatus.paused,
            ),
          };
        } else if (isCanceled) {
          _cancelled.remove(modelId);
          state = {...state}..remove(modelId);
        } else {
          state = {
            ...state,
            modelId: DownloadProgressInfo(
              modelId: modelId,
              status: DownloadStatus.failed,
              progress: 0.0,
              error: e.toString(),
              errorCategory: categorizeDownloadError(e),
            ),
          };
        }
        _saveState();
      }
      if (wasLoaded && ref.mounted) {
        try {
          final settings = ref.read(settingsProvider);
          await ref.read(onDeviceEngineProvider.notifier).loadModel(modelId, settings.preferredBackend);
        } catch (_) {}
      }
      if (wasCurrent) _endOperation(modelId, opId);
      return isCanceled ? null : e.toString();
    }
  }

  Future<String?> _startDownloadImpl(String modelId) async {
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

    if (_activeOperationIds.containsKey(modelId)) {
      return null;
    }
    final baselineBytes = state[modelId]?.receivedBytes ?? 0;
    final opId = _beginOperation(modelId, baselineBytes: baselineBytes);
    final opStart = DateTime.now();

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
            if (!ref.mounted) return;
            if (!_isActiveOp(modelId, opId)) return;
            if (_pausedOperations.contains(opId)) return;
            if (_cancelRequested.contains(opId)) return;

            final clampedReceived = received.clamp(0, total > 0 ? total : received);
            final startTime = opStart;
            final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
            int? bytesPerSecond;
            if (elapsedMs >= 2000 && clampedReceived > 0 && total > 0) {
              bytesPerSecond = ((clampedReceived - baselineBytes).clamp(0, clampedReceived) * 1000 / elapsedMs).round();
            }
            int? etaSeconds;
            if (bytesPerSecond != null &&
                bytesPerSecond > 0 &&
                total > clampedReceived) {
              etaSeconds = ((total - clampedReceived) / bytesPerSecond).round();
            }
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
      } else if (model.isImported && model.isLlamaCpp) {
        final repository = ref.read(importedGgufModelRepositoryProvider);
        final cancelToken = CancelToken();
        _cancelTokens[modelId] = cancelToken;
        final status = await repository.download(
          model.id,
          token: (hfToken != null && hfToken.isNotEmpty) ? hfToken : null,
          onProgress: (received, total) {
            if (!ref.mounted) return;
            if (!_isActiveOp(modelId, opId)) return;
            if (_pausedOperations.contains(opId)) return;

            final startTime = opStart;
            final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
            int? bytesPerSecond;
            if (elapsedMs >= 2000 && received > 0 && total > 0) {
              bytesPerSecond = ((received - baselineBytes).clamp(0, received) * 1000 / elapsedMs).round();
            }
            int? etaSeconds;
            if (bytesPerSecond != null &&
                bytesPerSecond > 0 &&
                total > received) {
              etaSeconds = ((total - received) / bytesPerSecond).round();
            }
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
        if (status != TaskStatus.complete) {
          // Attached/running/paused/failed — do not mark complete.
          return null;
        }
        await ref.read(importedGgufModelsProvider.notifier).pruneMissing();
      } else if (model.isImported &&
          model.runtime == OnDeviceModelRuntime.gemma) {
        final repository = ref.read(importedLitertModelRepositoryProvider);
        final status = await repository.download(
          model.id,
          token: (hfToken != null && hfToken.isNotEmpty) ? hfToken : null,
          onProgress: (received, total) {
            if (!ref.mounted) return;
            if (!_isActiveOp(modelId, opId)) return;
            if (_pausedOperations.contains(opId)) return;

            final clampedReceived = received.clamp(0, total > 0 ? total : received);
            final startTime = opStart;
            final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
            int? bytesPerSecond;
            if (elapsedMs >= 2000 && clampedReceived > 0 && total > 0) {
              bytesPerSecond = ((clampedReceived - baselineBytes).clamp(0, clampedReceived) * 1000 / elapsedMs).round();
            }
            int? etaSeconds;
            if (bytesPerSecond != null &&
                bytesPerSecond > 0 &&
                total > clampedReceived) {
              etaSeconds = ((total - clampedReceived) / bytesPerSecond).round();
            }
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
        if (status != TaskStatus.complete) {
          // Not finished (e.g. attached to a running background task); do not
          // mark complete. State will update via reconcile/onProgress.
          return null;
        }
        await ref.read(importedLitertModelsProvider.notifier).pruneMissing();
      } else {
        final gemmaCancelToken = gemma.CancelToken();
        _gemmaCancelTokens[modelId] = gemmaCancelToken;
        await gemmaService.installModel(
          model,
          token: (hfToken != null && hfToken.isNotEmpty) ? hfToken : null,
          cancelToken: gemmaCancelToken,
          onProgress: (progress) {
            if (!ref.mounted) return;
            if (!_isActiveOp(modelId, opId)) return;
            if (_pausedOperations.contains(opId)) return;
            if (_cancelRequested.contains(opId)) return;

            final startTime = opStart;
            final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
            final total = model.fileSizeBytes > 0 ? model.fileSizeBytes : 100;
            final received = model.fileSizeBytes > 0
                ? ((progress / 100.0) * total).round()
                : progress;

            int? bytesPerSecond;
            if (elapsedMs >= 2000 && received > 0) {
              bytesPerSecond = ((received - baselineBytes).clamp(0, received) * 1000 / elapsedMs).round();
            }
            int? etaSeconds;
            if (bytesPerSecond != null &&
                bytesPerSecond > 0 &&
                total > received) {
              etaSeconds = ((total - received) / bytesPerSecond).round();
            }

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
      if (_isActiveOp(modelId, opId)) {
        if (_cancelRequested.contains(opId)) {
          // Canceled but install completed anyway; route cleanup by runtime.
          try {
            if (model.runtime == OnDeviceModelRuntime.mlx) {
              await ref.read(onDeviceMlxServiceProvider).deleteModel(modelId);
            } else if (model.isImported && model.isLlamaCpp) {
              await ref.read(importedGgufModelsProvider.notifier).deleteFile(modelId);
            } else if (model.isImported &&
                model.runtime == OnDeviceModelRuntime.gemma) {
              await ref.read(importedLitertModelsProvider.notifier).deleteFile(modelId);
            } else {
              await gemmaService.deleteModel(modelId);
            }
          } catch (e) {
            Log.error('Failed to clean up canceled model $modelId: $e');
          }
          _cancelRequested.remove(opId);
          _endOperation(modelId, opId);
          _inFlightDownloads.remove(modelId);
          final current = Map<String, DownloadProgressInfo>.from(state);
          current.remove(modelId);
          state = current;
          _saveState();
          ref.invalidate(downloadedModelsProvider);
        } else if (ref.mounted) {
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
      final isCancel = gemma.CancelToken.isCancel(e) ||
          e is gemma.DownloadCancelledException ||
          msg.contains('canceled') ||
          msg.contains('cancelled');
      final isPaused = !isCancel && msg.contains('paused');
      final isCanceled = isCancel || _cancelRequested.contains(opId);
      if (!isPaused && !isCanceled) {
        Log.error('Download failed for $modelId: $e');
      }
      if (_isActiveOp(modelId, opId) && ref.mounted) {
        final current = state[modelId];
        if (isPaused) {
          state = {
            ...state,
            modelId: (current ?? DownloadProgressInfo(modelId: modelId)).copyWith(
              status: DownloadStatus.paused,
            ),
          };
        } else if (isCanceled) {
          // Transient: remove entry; do not persist canceled.
          final next = Map<String, DownloadProgressInfo>.from(state);
          next.remove(modelId);
          state = next;
          _cancelled.remove(modelId);
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
              errorCategory: categorizeDownloadError(e),
            ),
          };
        }
        _saveState();
      }
    } finally {
      final wasPaused = _pausedOperations.contains(opId);
      if (!wasPaused && _isActiveOp(modelId, opId)) {
        _endOperation(modelId, opId);
      }
      _cancelTokens.remove(modelId);
      _gemmaCancelTokens.remove(modelId);
      _cancelRequested.remove(opId);
      _pausedOperations.remove(opId);
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
    if (!ref.mounted) return;
    _cancelled.add(modelId);
    final opId = _activeOperationIds[modelId];
    if (opId != null) _cancelRequested.add(opId);
    final mlxService = ref.read(onDeviceMlxServiceProvider);
    mlxService.cancelDownload(modelId);
    final cancelToken = _cancelTokens.remove(modelId);
    cancelToken?.cancel('Canceled by user');
    final gemmaToken = _gemmaCancelTokens.remove(modelId);
    gemmaToken?.cancel('Canceled by user');

    final models = ref.read(onDeviceModelsProvider);
    final model = models.where((m) => m.id == modelId).firstOrNull;
    if (model != null && model.isImported) {
      try {
        if (model.runtime == OnDeviceModelRuntime.gemma) {
          final repository = ref.read(importedLitertModelRepositoryProvider);
          await repository.cancelDownload(modelId);
        } else if (model.isLlamaCpp) {
          final repository = ref.read(importedGgufModelRepositoryProvider);
          await repository.cancelDownload(modelId);
        }
      } catch (_) {
        // Best-effort; still update UI state below.
      }
    }

    final isCurated = model != null && !model.isImported;
    final inflight = _inFlightDownloads[modelId];

    // No-op if no download is in flight AND not tracked in state.
    if (inflight == null &&
        _activeDownloads[modelId] != true &&
        !state.containsKey(modelId)) {
      // Still cancel any tokens we have.
      _cancelTokens.remove(modelId)?.cancel('Canceled by user');
      _gemmaCancelTokens.remove(modelId)?.cancel('Canceled by user');
      return;
    }

    // For curated, keep _activeDownloads alive until the in-flight future
    // settles to prevent a retry race. Imported downloads remove immediately.
    if (!isCurated) {
      if (opId != null) _endOperation(modelId, opId);
    }
    if (!ref.mounted) return;
    if (isCurated) {
      // Transient canceling state; removed on settle. Not persisted.
      state = {
        ...state,
        modelId: DownloadProgressInfo(
          modelId: modelId,
          status: DownloadStatus.canceled,
        ),
      };
    } else {
      state = {...state}..remove(modelId);
    }
    _saveState();

    // Await in-flight settlement with bounded timeout.
    if (inflight != null) {
      try {
        await inflight.timeout(const Duration(seconds: 10));
      } catch (_) {
        // Timeout or error: leave single-flight in place; surface failure.
        Log.error('Cancel did not settle in time for $modelId');
      }
    }
  }

  Future<void> pauseDownload(String modelId, {DownloadPauseReason reason = DownloadPauseReason.user}) async {
    if (!ref.mounted) return;
    final opId = _activeOperationIds[modelId];
    final info = state[modelId];
    if (info == null) return;

    // Write-ahead: persist paused intent before native call.
    _pausedDownloads.add(modelId);
    if (opId != null) _pausedOperations.add(opId);
    state = {
      ...state,
      modelId: info.copyWith(status: DownloadStatus.paused, pauseReason: reason),
    };
    await _persistState();

    final models = ref.read(onDeviceModelsProvider);
    final model = models.where((m) => m.id == modelId).firstOrNull;
    var paused = false;
    if (model != null && model.isImported) {
      if (model.runtime == OnDeviceModelRuntime.gemma) {
        final repository = ref.read(importedLitertModelRepositoryProvider);
        paused = await repository.pauseDownload(modelId);
      } else if (model.isLlamaCpp) {
        final repository = ref.read(importedGgufModelRepositoryProvider);
        paused = await repository.pauseDownload(modelId);
      }
    } else {
      paused = true;
    }
    if (!paused && ref.mounted) {
      Log.warning('Native pause failed for $modelId');
      _pausedDownloads.remove(modelId);
      if (opId != null) _pausedOperations.remove(opId);
      final cur = state[modelId];
      if (cur != null) {
        state = {
          ...state,
          modelId: cur.copyWith(status: DownloadStatus.running, pauseReason: null),
        };
        _saveState();
      }
    }
    if (!paused) {
      _pausedDownloads.remove(modelId);
      if (opId != null) _pausedOperations.remove(opId);
    }
  }

  Future<void> resumeDownload(String modelId) async {
    if (!ref.mounted) return;
    final models = ref.read(onDeviceModelsProvider);
    final model = models.where((m) => m.id == modelId).firstOrNull;
    if (model == null) return;

    final prevOpId = _activeOperationIds[modelId];
    if (prevOpId != null) _pausedOperations.remove(prevOpId);

    _pausedDownloads.remove(modelId);

    if (ref.mounted) {
      final info = state[modelId];
      if (info != null) {
        state = {
          ...state,
          modelId: info.copyWith(status: DownloadStatus.running, pauseReason: null),
        };
        _saveState();
      }
    }

    final hfToken = ref.read(
      settingsProvider.select((s) => s.huggingFaceToken),
    );
    final token = (hfToken != null && hfToken.isNotEmpty) ? hfToken : null;

    final baselineBytes = state[modelId]?.receivedBytes ?? 0;
    // Reuse existing op if present, otherwise allocate new.
    final opId = prevOpId ?? _beginOperation(modelId, baselineBytes: baselineBytes);
    if (prevOpId == null) {
      _sessionBaselineBytes[modelId] = baselineBytes;
    }
    final opStart = DateTime.now();

    if (model.isImported && model.runtime == OnDeviceModelRuntime.gemma) {
      final repository = ref.read(importedLitertModelRepositoryProvider);
      final cancelToken = CancelToken();
      _cancelTokens[modelId] = cancelToken;
      TaskStatus status;
      try {
        status = await repository.resumeDownload(
          modelId,
          token: token,
          onProgress: (received, total) {
          if (!ref.mounted) return;
          if (!_isActiveOp(modelId, opId)) return;
          if (_pausedOperations.contains(opId)) return;
          final clampedReceived = received.clamp(0, total > 0 ? total : received);
          final startTime = opStart;
          final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
          int? bytesPerSecond;
          if (elapsedMs >= 2000 && clampedReceived > 0 && total > 0) {
            bytesPerSecond = ((clampedReceived - baselineBytes).clamp(0, clampedReceived) * 1000 / elapsedMs).round();
          }
          int? etaSeconds;
          if (bytesPerSecond != null &&
              bytesPerSecond > 0 &&
              total > clampedReceived) {
            etaSeconds = ((total - clampedReceived) / bytesPerSecond).round();
          }
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
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('paused')) {
          if (ref.mounted) {
            final cur = state[modelId];
            if (cur != null) {
              state = {...state, modelId: cur.copyWith(status: DownloadStatus.paused)};
              _saveState();
            }
          }
          return;
        }
        if (msg.contains('canceled') || msg.contains('cancelled')) {
          if (ref.mounted) {
            state = {...state}..remove(modelId);
            _saveState();
          }
          return;
        }
        Log.error('resumeDownload failed for $modelId: $e');
        return;
      }
      if (status == TaskStatus.paused) return;
      if (status == TaskStatus.canceled) {
        if (ref.mounted) {
          state = {...state}..remove(modelId);
          _saveState();
        }
        return;
      }
      if (status != TaskStatus.complete) return;
      await ref.read(importedLitertModelsProvider.notifier).pruneMissing();
    } else if (model.isImported && model.isLlamaCpp) {
      final repository = ref.read(importedGgufModelRepositoryProvider);
      final cancelToken = CancelToken();
      _cancelTokens[modelId] = cancelToken;
      try {
        await repository.resumeDownload(
          modelId,
          token: token,
          onProgress: (received, total) {
          if (!ref.mounted) return;
          if (!_isActiveOp(modelId, opId)) return;
          if (_pausedOperations.contains(opId)) return;
          final startTime = opStart;
          final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
          int? bytesPerSecond;
          if (elapsedMs >= 2000 && received > 0 && total > 0) {
            bytesPerSecond = ((received - baselineBytes).clamp(0, received) * 1000 / elapsedMs).round();
          }
          int? etaSeconds;
          if (bytesPerSecond != null &&
              bytesPerSecond > 0 &&
              total > received) {
            etaSeconds = ((total - received) / bytesPerSecond).round();
          }
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
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('paused')) {
          if (ref.mounted) {
            final cur = state[modelId];
            if (cur != null) {
              state = {...state, modelId: cur.copyWith(status: DownloadStatus.paused)};
              _saveState();
            }
          }
          return;
        }
        if (msg.contains('canceled') || msg.contains('cancelled')) {
          if (ref.mounted) {
            state = {...state}..remove(modelId);
            _saveState();
          }
          return;
        }
        Log.error('resumeDownload failed for $modelId: $e');
        return;
      }
      await ref.read(importedGgufModelsProvider.notifier).pruneMissing();
    } else {
      await startDownload(modelId);
      return;
    }

    if (ref.mounted && _activeDownloads[modelId] == true) {
      state = {
        ...state,
        modelId: DownloadProgressInfo(
          modelId: modelId,
          status: DownloadStatus.complete,
          progress: 1.0,
          receivedBytes: model.fileSizeBytes > 0 ? model.fileSizeBytes : 100,
          totalBytes: model.fileSizeBytes > 0 ? model.fileSizeBytes : 100,
        ),
      };
      _saveState();
      ref.invalidate(downloadedModelsProvider);
      _removeCompletedDownload(modelId);
    }
    _activeDownloads.remove(modelId);
    _downloadStartTimes.remove(modelId);
    _cancelTokens.remove(modelId);
  }

  Future<void> retryDownload(String modelId) async {
    await cancelDownload(modelId);
    await startDownload(modelId);
  }

  Future<void> retryUpdateDownload(String modelId) async {
    await cancelDownload(modelId);
    await startUpdateDownload(modelId);
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
