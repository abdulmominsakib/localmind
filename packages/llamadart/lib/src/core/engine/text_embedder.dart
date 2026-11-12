import 'dart:math' as math;

import '../exceptions.dart';
import 'engine.dart';

/// An explicit text formatting and output contract, not model auto-detection.
enum LlamaEmbeddingProfile {
  /// Verbatim input and the backend's existing normalization behavior.
  raw,

  /// EmbeddingGemma-2 task prefixes and its 768/512/256/128 output dimensions.
  ///
  /// Selecting this asserts that the caller loaded a compatible model. Output
  /// width is checked, but does not authenticate a model or qualify a quantization.
  embeddingGemma2,
}

/// EmbeddingGemma-2 text tasks. Symmetric tasks use the same task on both sides.
enum LlamaEmbeddingTask {
  /// Search queries, compared with document embeddings.
  search,

  /// Questions, compared with passage embeddings.
  questionAnswering,

  /// Claims, compared with evidence embeddings.
  factChecking,

  /// Natural language queries, compared with code document embeddings.
  codeRetrieval,

  /// Classification inputs.
  classification,

  /// Clustering inputs.
  clustering,

  /// Sentence similarity inputs.
  sentenceSimilarity,
}

/// An explicitly prepared, task, or document text input.
///
/// Use [LlamaEmbeddingText.prepared] for already-prefixed text; no prefix
/// detection or removal is performed. These helpers accept no media parts.
final class LlamaEmbeddingText {
  /// Verbatim text, including any instructions already supplied by the caller.
  const LlamaEmbeddingText.prepared(this.text)
    : task = null,
      _document = false,
      title = null;

  /// Unprefixed query or symmetric-task content.
  const LlamaEmbeddingText.query(
    this.text, {
    LlamaEmbeddingTask this.task = LlamaEmbeddingTask.search,
  }) : _document = false,
       title = null;

  /// Unprefixed document content, with an optional real title or code filename.
  ///
  /// An absent title uses the model's literal `none`. Supplied titles and text
  /// are preserved verbatim, including whitespace.
  const LlamaEmbeddingText.document(this.text, {this.title})
    : task = null,
      _document = true;

  /// The original caller text.
  final String text;

  /// The query or symmetric task; null for documents and prepared text.
  final LlamaEmbeddingTask? task;

  /// Optional document title.
  final String? title;

  final bool _document;

  String _format(LlamaEmbeddingProfile profile) {
    if (!_document && task == null) return text;
    if (profile != LlamaEmbeddingProfile.embeddingGemma2) {
      throw LlamaUnsupportedException(
        'Embedding task and document formatting requires the explicit '
        'EmbeddingGemma-2 profile; the raw profile accepts prepared text only.',
      );
    }
    if (_document) return 'title: ${title ?? 'none'} | text: $text';
    final instruction = switch (task!) {
      LlamaEmbeddingTask.search => 'search result',
      LlamaEmbeddingTask.questionAnswering => 'question answering',
      LlamaEmbeddingTask.factChecking => 'fact checking',
      LlamaEmbeddingTask.codeRetrieval => 'code retrieval',
      LlamaEmbeddingTask.classification => 'classification',
      LlamaEmbeddingTask.clustering => 'clustering',
      LlamaEmbeddingTask.sentenceSimilarity => 'sentence similarity',
    };
    return 'task: $instruction | query: $text';
  }
}

/// Opt-in text retrieval helpers around an existing [LlamaEngine].
///
/// The default [LlamaEmbeddingProfile.raw] preserves prepared text and delegates
/// normalization unchanged. The explicit EmbeddingGemma-2 profile requests raw
/// 768-component vectors, keeps the leading [dimensions], then optionally L2
/// normalizes. It rejects nonfinite vectors and a zero retained vector when
/// normalization is requested. With [normalize] false, finite zero vectors are
/// returned unchanged apart from slicing.
///
/// This wrapper neither owns nor disposes [engine], authenticates its model,
/// adds media instructions, nor changes existing engine APIs. Choose the same
/// model, profile and dimensions for every query and corpus item. Backend
/// unsupported errors and cancellation retain the engine's existing contract.
final class LlamaTextEmbedder {
  /// Creates a helper. Raw output cannot request a model-specific dimension.
  ///
  /// Unsupported profile/dimension combinations throw [LlamaUnsupportedException]
  /// before inference. EmbeddingGemma-2 allows 768 (default), 512, 256 or 128.
  LlamaTextEmbedder(
    this.engine, {
    this.profile = LlamaEmbeddingProfile.raw,
    this.dimensions,
    this.normalize = true,
  }) {
    if (dimensions != null && profile == LlamaEmbeddingProfile.raw) {
      throw LlamaUnsupportedException(
        'Embedding dimension reduction requires an explicit compatible model '
        'profile; it is unavailable for the raw profile.',
      );
    }
    if (profile == LlamaEmbeddingProfile.embeddingGemma2 &&
        dimensions != null &&
        !const [768, 512, 256, 128].contains(dimensions)) {
      throw LlamaUnsupportedException(
        'EmbeddingGemma-2 output dimensions must be 768, 512, 256 or 128.',
      );
    }
  }

  /// Existing engine; await embedding futures before switching or unloading it.
  final LlamaEngine engine;

  /// Caller-selected model contract. No filename-based detection is performed.
  final LlamaEmbeddingProfile profile;

  /// Leading output width; null keeps the profile's full width.
  final int? dimensions;

  /// Whether to L2 normalize, after any dimension reduction.
  final bool normalize;

  /// Embeds one text through the engine's single-input production path.
  Future<List<double>> embed(LlamaEmbeddingText input) async {
    final vector = await engine.embed(
      input._format(profile),
      normalize: profile == LlamaEmbeddingProfile.raw && normalize,
    );
    return _process(vector);
  }

  /// Embeds texts in order, retaining native batching or the engine's fallback.
  ///
  /// Formatting is validated for the whole batch before inference. A wrong
  /// vector count or invalid output throws [LlamaInferenceException], returning
  /// no partial results. Empty batches retain the engine's readiness check.
  Future<List<List<double>>> embedBatch(List<LlamaEmbeddingText> inputs) async {
    final texts = [for (final input in inputs) input._format(profile)];
    final vectors = await engine.embedBatch(
      texts,
      normalize: profile == LlamaEmbeddingProfile.raw && normalize,
    );
    if (vectors.length != texts.length) {
      throw LlamaInferenceException(
        'Text embedding returned ${vectors.length} vectors; '
        'expected ${texts.length}.',
      );
    }
    return [for (final vector in vectors) _process(vector)];
  }

  List<double> _process(List<double> vector) {
    if (profile == LlamaEmbeddingProfile.raw) return vector;
    if (vector.length != 768) {
      throw LlamaUnsupportedException(
        'The EmbeddingGemma-2 profile requires 768-component source vectors; '
        'the loaded model/runtime returned ${vector.length}.',
      );
    }
    var maximum = 0.0;
    for (final value in vector) {
      if (!value.isFinite) {
        throw LlamaInferenceException(
          'EmbeddingGemma-2 returned a nonfinite vector.',
        );
      }
    }
    final output = vector.sublist(0, dimensions ?? 768);
    if (!normalize) return output;
    for (final value in output) {
      maximum = math.max(maximum, value.abs());
    }
    if (maximum == 0) {
      throw LlamaInferenceException(
        'Cannot L2 normalize a zero EmbeddingGemma-2 output vector.',
      );
    }
    // Scale before summing squares to avoid overflow and subnormal underflow.
    var sum = 0.0;
    for (final value in output) {
      final scaled = value / maximum;
      sum += scaled * scaled;
    }
    final norm = math.sqrt(sum);
    return [for (final value in output) (value / maximum) / norm];
  }
}
