/// Reranking support and limits of the currently loaded model/context.
final class LlamaRerankingCapabilities {
  /// Creates an immutable capability snapshot. Unsupported contexts have no outputs.
  LlamaRerankingCapabilities({
    required this.isSupported,
    this.unsupportedReason,
    List<String?> classifierLabels = const [],
    this.maxInputTokens = 0,
    this.maxParallelSequences = 0,
  }) : classifierLabels = List<String?>.unmodifiable(classifierLabels);

  /// Whether the loaded context can score query/document pairs.
  final bool isSupported;

  /// Actionable reason when support is unavailable.
  final String? unsupportedReason;

  /// One label per native classifier output; null means the model has no label.
  final List<String?> classifierLabels;

  /// Maximum tokens in a complete formatted query/document pair.
  ///
  /// Includes template and special tokens. This conservative API requires a
  /// complete pair to fit the context, logical batch and micro-batch.
  final int maxInputTokens;

  /// Allocated sequence slots; one uses sequential document scoring.
  final int maxParallelSequences;
}

/// One document's native classifier output, after sorting by a selected score.
final class LlamaRerankResult {
  /// Creates an immutable result. [index] identifies the original document.
  LlamaRerankResult({
    required this.index,
    required this.score,
    required List<double> classifierScores,
    required List<String?> classifierLabels,
  }) : classifierScores = List<double>.unmodifiable(classifierScores),
       classifierLabels = List<String?>.unmodifiable(classifierLabels);

  /// Original zero-based document index, preserving duplicate documents.
  final int index;

  /// Native output selected by the call's score index; higher sorts first.
  ///
  /// Values are model-specific: Qwen3 returns probabilities, while other
  /// rerankers can return unbounded raw scores. No normalization is applied.
  final double score;

  /// Every native classifier output in model order, without normalization.
  final List<double> classifierScores;

  /// Labels in the same order as [classifierScores], null where absent.
  final List<String?> classifierLabels;
}
