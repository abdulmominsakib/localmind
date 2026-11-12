import 'package:llamadart/llamadart.dart';

import 'entry_id.dart';
import 'model_store_entry.dart';

/// A model library that every app able to open the same directory shares.
///
/// This platform has no file system to share, so [open] throws
/// [LlamaUnsupportedException]; browser model caches are origin-scoped.
final class ModelStore extends ThrowingModelDownloadManager {
  ModelStore._();

  /// Throws [LlamaUnsupportedException]: this platform has no file-backed
  /// model store.
  static Future<ModelStore> open({
    required String directory,
    required String appId,
  }) async {
    throw LlamaUnsupportedException(
      'ModelStore needs a file system shared between apps, which this '
      'platform does not have; browser model caches are origin-scoped.',
    );
  }

  /// The identifier of the entry that holds [model]'s files.
  static String entryIdFor(LlamaModel model) => modelStoreEntryId(model);

  /// The store's root directory.
  String get directory => throw unsupported('directory');

  /// The app this store handle records references for.
  String get appId => throw unsupported('appId');

  /// Unsupported on this platform.
  Future<ModelStoreEntry> ensure(
    LlamaModel model, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    throw unsupported('ensure');
  }

  /// Unsupported on this platform.
  Future<List<ModelStoreEntry>> entries() async {
    throw unsupported('entries');
  }

  /// Unsupported on this platform.
  Future<void> release(String entryId) async {
    throw unsupported('release');
  }
}
