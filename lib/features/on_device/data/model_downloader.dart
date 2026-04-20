import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/logger/app_logger.dart';
import 'download_notification_service.dart';
import 'models/model_download_progress.dart';
import 'models/on_device_model.dart';
import 'on_device_engine_service.dart';

class ModelDownloader {
  final DownloadNotificationService _notificationService;
  final Dio _dio = Dio();
  final Map<String, CancelToken> _activeDownloads = {};

  ModelDownloader(this._notificationService);

  Stream<ModelDownloadProgress> downloadModel(
    OnDeviceModel model, {
    String? token,
  }) async* {
    final modelsDir = await OnDeviceEngineService.getModelDirectory();
    final finalPath = '$modelsDir/${model.fileName}';
    final partialPath = '$finalPath.part';

    // 1. Check if already complete
    if (await File(finalPath).exists()) {
      Log.info('Model ${model.id} already exists at $finalPath');
      return;
    }

    final partialFile = File(partialPath);
    final cancelToken = CancelToken();
    _activeDownloads[model.id] = cancelToken;

    // 2. Prevent sleep
    await WakelockPlus.enable();

    int receivedBytes = 0;
    bool isResumed = false;

    // 3. Check for partial file to resume
    if (await partialFile.exists()) {
      receivedBytes = await partialFile.length();
      isResumed = receivedBytes > 0;
      Log.info('Resuming download for ${model.id} from $receivedBytes bytes');
    }

    final startTime = DateTime.now();
    DateTime lastProgressUpdate = DateTime.now();
    int bytesSinceLastUpdate = 0;

    try {
      // 4. Resolve redirects manually to handle Auth header safety
      final response = await _resolveWithRedirects(
        url: model.huggingFaceUrl,
        token: token,
        startByte: receivedBytes,
        cancelToken: cancelToken,
      );

      final totalBytes = (response.headers.value(Headers.contentLengthHeader) != null)
          ? int.parse(response.headers.value(Headers.contentLengthHeader)!) + receivedBytes
          : model.fileSizeBytes;

      final IOSink sink = partialFile.openWrite(mode: FileMode.append);

      final stream = response.data?.stream;
      if (stream == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          error: 'Response data stream is null',
        );
      }

      await for (final List<int> chunk in stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        bytesSinceLastUpdate += chunk.length;

        final now = DateTime.now();
        final elapsedSinceLastUpdate = now.difference(lastProgressUpdate);

        // Update progress every 500ms
        if (elapsedSinceLastUpdate.inMilliseconds >= 500) {
          final totalElapsed = now.difference(startTime);
          final bytesDownloadedInThisSession = receivedBytes - (isResumed ? (await partialFile.length() - bytesSinceLastUpdate) : 0);
          
          // Use a simple bytes per second based on the current session's progress
          final bytesPerSecond = (bytesDownloadedInThisSession / totalElapsed.inMilliseconds * 1000).toInt();
          
          final remainingBytes = totalBytes - receivedBytes;
          final etaSeconds = bytesPerSecond > 0 ? (remainingBytes / bytesPerSecond).toInt() : null;

          final progress = ModelDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            fraction: receivedBytes / totalBytes,
            bytesPerSecond: bytesPerSecond,
            estimatedSecondsRemaining: etaSeconds,
            isResumed: isResumed,
          );

          yield progress;

          // 5. Update Notification
          await _notificationService.showProgressNotification(
            id: model.id.hashCode,
            modelName: model.name,
            progress: progress,
          );

          lastProgressUpdate = now;
          bytesSinceLastUpdate = 0;
        }
      }

      await sink.flush();
      await sink.close();

      // 6. Promote .part to final
      await partialFile.rename(finalPath);
      Log.info('Model ${model.id} downloaded successfully');

      // 7. Final notification
      await _notificationService.showCompleteNotification(
        id: model.id.hashCode,
        modelName: model.name,
      );
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        Log.info('Download cancelled for ${model.id}');
      } else {
        Log.error('Failed to download model ${model.id}: $e');
        await _notificationService.showFailedNotification(
          id: model.id.hashCode,
          modelName: model.name,
          error: e.toString(),
        );
        rethrow;
      }
    } finally {
      _activeDownloads.remove(model.id);
      
      // 8. Restore sleep behavior if no other downloads active
      if (_activeDownloads.isEmpty) {
        await WakelockPlus.disable();
      }
    }
  }

  void cancelDownload(String modelId) {
    _activeDownloads[modelId]?.cancel();
  }

  /// Manually follows redirects to ensure Authorization header is only sent to HF.
  Future<Response<ResponseBody>> _resolveWithRedirects({
    required String url,
    required String? token,
    required int startByte,
    required CancelToken cancelToken,
  }) async {
    String currentUrl = url;
    final Uri originalUri = Uri.parse(url);

    for (int hop = 0; hop < 5; hop++) {
      final options = Options(
        responseType: ResponseType.stream,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          if (startByte > 0) 'Range': 'bytes=$startByte-',
        },
      );

      // Only add Auth header if we are on the original host
      final currentUri = Uri.parse(currentUrl);
      if (token != null && currentUri.host == originalUri.host) {
        options.headers!['Authorization'] = 'Bearer ${token.trim()}';
      }

      final response = await _dio.get<ResponseBody>(
        currentUrl,
        options: options,
        cancelToken: cancelToken,
      );

      if (response.statusCode == 200 || response.statusCode == 206) {
        return response;
      }

      if (response.statusCode! >= 300 && response.statusCode! < 400) {
        final location = response.headers.value('location');
        if (location == null) {
          throw DioException(
            requestOptions: response.requestOptions,
            error: 'Redirect without location header',
          );
        }
        currentUrl = Uri.parse(currentUrl).resolve(location).toString();
        continue;
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Server returned ${response.statusCode}',
      );
    }

    throw DioException(
      requestOptions: RequestOptions(path: url),
      error: 'Too many redirects',
    );
  }
}
