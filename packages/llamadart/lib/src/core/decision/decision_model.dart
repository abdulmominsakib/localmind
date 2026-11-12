import '../models/model_source.dart';

/// A Laya-style decision model: an encoder GGUF, a decision head and,
/// for heads without embedded config, the head's config file.
///
/// Each file is a `ModelSource` (local path, HTTP(S) URL or Hugging Face
/// file) that `DecisionEngine.load` downloads if needed. On Web a local path
/// is a URL relative to the document base URL.
///
/// ```dart
/// final laya = DecisionModel(
///   encoder: ModelSource.parse('hf://fr0stbit3/laya-gguf/laya-Q8_0.gguf'),
///   head: ModelSource.parse(
///     'hf://fr0stbit3/laya-gguf/laya-head.safetensors',
///   ),
/// );
/// ```
///
/// Building a model does no network or file access.
class DecisionModel {
  /// The bidirectional encoder (backbone) GGUF, such as `laya-Q8_0.gguf`.
  final ModelSource encoder;

  /// The decision head safetensors file.
  final ModelSource head;

  /// Laya's `rl_agent_config.json`, for a head file without `laya.config`
  /// metadata, such as the official checkpoint; `null` reads the config
  /// from the head.
  final ModelSource? config;

  /// Creates a model from its [encoder], [head] and optional [config].
  const DecisionModel({required this.encoder, required this.head, this.config});
}
