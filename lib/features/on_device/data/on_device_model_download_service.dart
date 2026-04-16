import 'dart:async';
import 'dart:io';

import '../../../core/logger/app_logger.dart';
import 'models/on_device_model.dart';
import 'on_device_engine_service.dart';

/// Snapshot of an in-flight download.
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});

  final int received;
  final int total;

  double get fraction => total <= 0 ? 0 : received / total;
}

/// Downloads `.litertlm` model files from HuggingFace using `dart:io HttpClient`.
///
/// Follows redirects manually so the `Authorization` header is only sent to
/// the original HuggingFace host (not the CDN). Downloads stream to a `.part`
/// file and are renamed atomically on success.
class OnDeviceModelDownloadService {
  final Map<String, HttpClient> _activeClients = {};

  /// Downloads [model] from HuggingFace, emitting progress updates.
  ///
  /// [token] is an optional HuggingFace access token for gated models.
  Stream<DownloadProgress> downloadModel(
    OnDeviceModel model, {
    String? token,
  }) async* {
    final modelsDir = await OnDeviceEngineService.getModelDirectory();
    final finalPath = '$modelsDir/${model.fileName}';
    final partialPath = '$finalPath.part';

    // Already downloaded
    if (await File(finalPath).exists()) {
      Log.info('Model ${model.id} already downloaded at $finalPath');
      return;
    }

    // Clean up any stale partial file from a previous attempt
    final partialFile = File(partialPath);
    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    final client = HttpClient();
    _activeClients[model.id] = client;
    IOSink? sink;

    try {
      final response = await _resolveWithRedirects(
        client: client,
        url: Uri.parse(model.huggingFaceUrl),
        token: token,
      );

      final total = response.contentLength > 0
          ? response.contentLength
          : model.fileSizeBytes;
      var received = 0;

      sink = partialFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgress(received: received, total: total);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // Atomically promote .part file to final name
      await partialFile.rename(finalPath);

      Log.info('Model ${model.id} downloaded successfully to $finalPath');
    } catch (e) {
      // Clean up partial file on failure
      try {
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) {}
      Log.error('Failed to download model ${model.id}: $e');
      rethrow;
    } finally {
      _activeClients.remove(model.id);
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }

  /// Cancel an in-flight download for [modelId].
  void cancelDownload(String modelId) {
    final client = _activeClients[modelId];
    if (client != null) {
      client.close(force: true);
      _activeClients.remove(modelId);
    }
  }

  /// Manually follow redirects, passing the HF `Authorization` header
  /// only on the original host. The CDN URLs returned by HuggingFace are
  /// pre-signed and may reject extra auth headers.
  Future<HttpClientResponse> _resolveWithRedirects({
    required HttpClient client,
    required Uri url,
    required String? token,
  }) async {
    var current = url;
    final originHost = url.host;

    for (var hop = 0; hop < 6; hop++) {
      final request = await client.getUrl(current);
      request.followRedirects = false;

      // Only send bearer token to the original HuggingFace host
      final cleanedToken = token?.trim();
      if (cleanedToken != null &&
          cleanedToken.isNotEmpty &&
          current.host == originHost) {
        request.headers.set('Authorization', 'Bearer $cleanedToken');
      }

      final response = await request.close();

      if (response.statusCode == 200) {
        return response;
      }

      if (response.isRedirect) {
        final location = response.headers.value('location');
        await response.drain<void>();
        if (location == null) {
          throw HttpException(
            'Redirect with no Location header (status ${response.statusCode})',
          );
        }
        current = current.resolve(location);
        continue;
      }

      // Read a small preview of the error body
      final body = await _readBodyPreview(response);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw HttpException(
          'Access denied (HTTP ${response.statusCode}). '
          '${body.isNotEmpty ? "Server said: $body" : ""}',
        );
      }
      throw HttpException(
        'Download failed: HTTP ${response.statusCode}'
        '${body.isNotEmpty ? " — $body" : ""}',
      );
    }

    throw const HttpException('Too many redirects');
  }

  /// Read at most ~512 bytes of the response body for error messages.
  Future<String> _readBodyPreview(HttpClientResponse response) async {
    try {
      final buffer = StringBuffer();
      var read = 0;
      await for (final chunk in response) {
        buffer.write(String.fromCharCodes(chunk));
        read += chunk.length;
        if (read >= 512) break;
      }
      return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
    } catch (_) {
      return '';
    }
  }

  /// Delete a downloaded model from disk.
  Future<void> deleteModel(String modelId) async {
    final modelsDir = await OnDeviceEngineService.getModelDirectory();
    final file = File('$modelsDir/$modelId.litertlm');
    if (await file.exists()) {
      await file.delete();
      Log.info('Model $modelId deleted');
    }
  }

  /// List all downloaded models.
  Future<List<DownloadedModel>> getDownloadedModels() async {
    final modelsDir = await OnDeviceEngineService.getModelDirectory();
    final dir = Directory(modelsDir);
    if (!await dir.exists()) {
      return [];
    }

    final List<DownloadedModel> result = [];
    final entities = dir.listSync();
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.litertlm')) {
        final fileName = entity.path.split('/').last;
        final modelId = fileName.replaceAll('.litertlm', '');
        final stat = await entity.stat();
        result.add(
          DownloadedModel(
            modelId: modelId,
            filePath: entity.path,
            downloadedAt: stat.modified,
          ),
        );
      }
    }
    return result;
  }

  /// Check if a model has been downloaded.
  Future<bool> isModelDownloaded(String modelId) async {
    final modelsDir = await OnDeviceEngineService.getModelDirectory();
    final file = File('$modelsDir/$modelId.litertlm');
    return file.exists();
  }

  /// Get total size of all downloaded models.
  Future<int> getModelsTotalSizeBytes() async {
    final models = await getDownloadedModels();
    int total = 0;
    for (final model in models) {
      final file = File(model.filePath);
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }
}

class DownloadedModel {
  final String modelId;
  final String filePath;
  final DateTime downloadedAt;

  const DownloadedModel({
    required this.modelId,
    required this.filePath,
    required this.downloadedAt,
  });
}
