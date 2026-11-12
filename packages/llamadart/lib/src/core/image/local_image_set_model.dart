import '../exceptions.dart';
import '../models/model_source.dart';
import 'image_generation_model.dart';

/// Internal data for the opt-in local checkpoint-set factory.
final class LocalImageSetModel extends ImageGenerationModel {
  /// Immutable expected identity of every source file, including the index.
  final Map<String, String> sha256;

  /// App-private directory reserved for owned content snapshots.
  final String cacheDirectory;

  /// Creates the internal data used by the public additive factory.
  LocalImageSetModel(
    String path, {
    required Map<String, String> sha256,
    required this.cacheDirectory,
  }) : sha256 = _identities(sha256),
       super(
         _localSource(path, cacheDirectory),
         role: ImageModelRole.checkpoint,
       );
}

ModelSource _localSource(String path, String cacheDirectory) {
  if (path.isEmpty || path.contains('://') || cacheDirectory.trim().isEmpty) {
    throw LlamaArgumentException(
      'Local image sets require a local path and an app-private cache directory.',
    );
  }
  return ModelSource.path(path);
}

Map<String, String> _identities(Map<String, String> values) {
  if (values.length < 2 || values.length > 17) {
    throw LlamaArgumentException(
      'A local image set requires an index and 1..16 shard identities.',
    );
  }
  final result = <String, String>{};
  for (final entry in values.entries) {
    if ((entry.key != 'model.safetensors.index.json' &&
            !RegExp(
              r'^model-[0-9]{5}-of-[0-9]{5}\.safetensors$',
            ).hasMatch(entry.key)) ||
        entry.key.contains('..') ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(entry.value)) {
      throw LlamaArgumentException(
        'Local image-set identities require the standard index, canonical numbered shard basenames and SHA-256 digests.',
      );
    }
    result[entry.key] = entry.value.toLowerCase();
  }
  if (!result.containsKey('model.safetensors.index.json')) {
    throw LlamaArgumentException(
      'Include the identity of model.safetensors.index.json.',
    );
  }
  return Map.unmodifiable(result);
}
