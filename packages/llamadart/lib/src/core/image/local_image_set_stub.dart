import '../exceptions.dart';
import '../models/download/model_download_manager.dart';
import '../models/model_file_store.dart';
import '../models/model_load_options.dart';
import 'local_image_set_model.dart';

/// Refuses managed filesystem snapshots on platforms without native IO.
Future<({String indexPath, int totalBytes, String layoutSha256})>
resolveLocalImageSet(
  LocalImageSetModel model, {
  required ModelFileStore store,
  required ModelLoadOptions options,
  ModelDownloadProgressCallback? onProgress,
}) => throw LlamaUnsupportedException(
  'Local Safetensors sets require native filesystem IO and the qualified macOS CPU recipe.',
);
