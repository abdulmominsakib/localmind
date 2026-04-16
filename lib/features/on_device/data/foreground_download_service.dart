import 'dart:async';
import 'dart:io';

import '../../../core/logger/app_logger.dart';
import 'models/download_status.dart';
import 'models/on_device_model.dart';
import 'on_device_engine_service.dart';
import 'on_device_model_download_service.dart';

/// Wraps [OnDeviceModelDownloadService] with broadcast streams for UI consumption.
///
/// Progress updates are emitted as [DownloadStatusUpdate] via [getStatusStream].
class ForegroundDownloadService {
  final OnDeviceModelDownloadService _downloadService;
  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, StreamController<DownloadStatusUpdate>>
  _progressControllers = {};

  ForegroundDownloadService(this._downloadService);

  /// Returns a broadcast stream of status updates for [modelId].
  /// Creates the stream controller if one doesn't exist yet.
  Stream<DownloadStatusUpdate> getStatusStream(String modelId) {
    return _progressControllers
        .putIfAbsent(
          modelId,
          () => StreamController<DownloadStatusUpdate>.broadcast(),
        )
        .stream;
  }

  /// Start downloading [model]. Progress is emitted via [getStatusStream].
  ///
  /// Call [getStatusStream] before this method to subscribe to progress updates.
  /// Returns the absolute path to the downloaded file on success.
  Future<String> downloadModel(OnDeviceModel model, {String? token}) async {
    final modelsDir = await OnDeviceEngineService.getModelDirectory();
    final filePath = '$modelsDir/${model.fileName}';
    final file = File(filePath);

    if (await file.exists()) {
      Log.info('Model ${model.id} already downloaded at $filePath');
      // Signal already downloaded via the stream
      final controller = _progressControllers[model.id];
      if (controller != null && !controller.isClosed) {
        controller.add(
          DownloadStatusUpdate(
            modelId: model.id,
            taskId: model.id,
            status: DownloadStatus.complete,
            progress: 100,
          ),
        );
        await _cleanup(model.id);
      }
      return filePath;
    }

    // Ensure the stream controller exists (created by getStatusStream)
    final controller = _progressControllers.putIfAbsent(
      model.id,
      () => StreamController<DownloadStatusUpdate>.broadcast(),
    );

    // Emit initial pending status
    if (!controller.isClosed) {
      controller.add(
        DownloadStatusUpdate(
          modelId: model.id,
          taskId: model.id,
          status: DownloadStatus.pending,
          progress: 0,
        ),
      );
    }

    // Listen to the underlying download stream
    final completer = Completer<String>();

    final subscription = _downloadService
        .downloadModel(model, token: token)
        .listen(
          (progress) {
            if (controller.isClosed) return;
            final percent = progress.total > 0
                ? (progress.received / progress.total * 100).round()
                : 0;
            controller.add(
              DownloadStatusUpdate(
                modelId: model.id,
                taskId: model.id,
                status: DownloadStatus.running,
                progress: percent,
              ),
            );
          },
          onError: (Object e) {
            if (!controller.isClosed) {
              controller.add(
                DownloadStatusUpdate(
                  modelId: model.id,
                  taskId: model.id,
                  status: DownloadStatus.failed,
                  progress: 0,
                ),
              );
            }
            _cleanup(model.id);
            completer.completeError(e);
          },
          onDone: () {
            if (!completer.isCompleted) {
              if (!controller.isClosed) {
                controller.add(
                  DownloadStatusUpdate(
                    modelId: model.id,
                    taskId: model.id,
                    status: DownloadStatus.complete,
                    progress: 100,
                  ),
                );
              }
              _cleanup(model.id);
              completer.complete(filePath);
            }
          },
          cancelOnError: true,
        );

    _subscriptions[model.id] = subscription;

    return completer.future;
  }

  /// Cancel an in-flight download for [modelId].
  Future<void> cancelDownload(String modelId) async {
    _downloadService.cancelDownload(modelId);
    await _cleanup(modelId);
  }

  Future<void> _cleanup(String modelId) async {
    await _subscriptions.remove(modelId)?.cancel();
    final controller = _progressControllers.remove(modelId);
    await controller?.close();
  }

  /// Pause is not supported — downloads are continuous streams.
  void pauseDownload(String modelId) {
    Log.warning('Pause not supported for foreground downloads');
  }

  /// Resume is not supported — start a new download instead.
  void resumeDownload(String modelId) {
    Log.warning('Resume not supported for foreground downloads');
  }

  /// Cancel and let the UI restart the download.
  Future<void> retryDownload(String modelId) async {
    await cancelDownload(modelId);
  }
}
