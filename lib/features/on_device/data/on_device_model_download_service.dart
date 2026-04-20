import 'dart:async';
import 'dart:io';

import '../../../core/logger/app_logger.dart';
import 'model_downloader.dart';
import 'models/model_download_progress.dart';
import 'models/on_device_model.dart';
import 'on_device_engine_service.dart';

/// Downloads `.litertlm` model files from HuggingFace using [ModelDownloader].
///
/// Handles file management tasks like deleting and listing downloaded models.
class OnDeviceModelDownloadService {
  final ModelDownloader _downloader;

  OnDeviceModelDownloadService(this._downloader);

  /// Downloads [model] from HuggingFace, emitting progress updates.
  ///
  /// [token] is an optional HuggingFace access token for gated models.
  Stream<ModelDownloadProgress> downloadModel(
    OnDeviceModel model, {
    String? token,
  }) {
    return _downloader.downloadModel(model, token: token);
  }

  /// Cancel an in-flight download for [modelId].
  void cancelDownload(String modelId) {
    _downloader.cancelDownload(modelId);
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
