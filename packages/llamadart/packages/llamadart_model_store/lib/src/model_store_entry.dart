import 'package:llamadart/llamadart.dart';

/// One app's claim on a [ModelStoreEntry].
///
/// A store deletes an entry's files only once no app holds a reference.
final class ModelStoreReference {
  /// Creates a reference held by [appId], last used at [lastUsedAt].
  const ModelStoreReference({required this.appId, required this.lastUsedAt});

  /// The `appId` the referencing app passed to `ModelStore.open`.
  final String appId;

  /// When that app last ensured the entry.
  final DateTime lastUsedAt;
}

/// A model, with its multimodal projector when it has one, kept in a
/// `ModelStore` as one logical entry.
final class ModelStoreEntry {
  /// Creates an entry from its files and references.
  ModelStoreEntry({
    required this.id,
    required this.model,
    this.projector,
    required List<ModelStoreReference> references,
  }) : references = List<ModelStoreReference>.unmodifiable(references);

  /// Stable identifier of the entry; see `ModelStore.entryIdFor`.
  final String id;

  /// The cached model file.
  final ModelCacheEntry model;

  /// The cached multimodal projector file, or null.
  final ModelCacheEntry? projector;

  /// The apps that reference this entry, most recently used first.
  final List<ModelStoreReference> references;

  /// The entry's files as a [LlamaModel] of local paths, ready for
  /// `LlamaEngine.load` or `LlamaEngine.setModel`.
  LlamaModel toLlamaModel() {
    final projectorFile = projector;
    return LlamaModel(
      ModelSource.path(model.filePath),
      projector: projectorFile == null
          ? null
          : ModelSource.path(projectorFile.filePath),
    );
  }
}
