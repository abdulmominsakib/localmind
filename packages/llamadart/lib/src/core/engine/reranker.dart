import '../../backends/backend.dart';
import '../exceptions.dart';
import '../models/inference/model_params.dart';
import '../models/model_source.dart';
import '../models/inference/reranking.dart';
import 'engine.dart';

/// Ranks documents against a query with a loaded cross-encoder reranker.
///
/// Native llama.cpp rank-pooled GGUF models are supported; [load] also prepares
/// verified BERT/Jina classifiers whose metadata omits RANK. WebGPU, LiteRT-LM
/// and ordinary embedding/chat models report unsupported. The constructor
/// borrows [engine]; [load] owns it until [dispose]. Await calls before changing
/// its model or disposing it. Existing embedding APIs remain unchanged.
final class LlamaReranker {
  /// Borrows an existing engine, including its context and cancellation policy.
  const LlamaReranker(this.engine) : _ownsEngine = false;

  LlamaReranker._owned(this.engine) : _ownsEngine = true;

  final bool _ownsEngine;

  /// Loads and owns a native GGUF reranker, explicitly creating a RANK context.
  ///
  /// Use this for BERT/Jina models that omit rank-pooling metadata. The loader
  /// verifies a real classifier tensor and its output width before selecting
  /// RANK. Ordinary model contexts are unchanged. Unsupported backends or a
  /// missing/unverifiable classifier throw [LlamaUnsupportedException].
  /// Dispose this helper to release its engine; failed preparation also frees it.
  static Future<LlamaReranker> load(
    LlamaModel model, {
    LlamaCppModelParams params = const LlamaCppModelParams(),
  }) async {
    final engine = LlamaEngine(LlamaBackend());
    try {
      if (engine.backend is! BackendReranking) {
        throw LlamaUnsupportedException(
          'Reranker loading requires native llama.cpp; Web and LiteRT-LM are unsupported.',
        );
      }
      if (params.loras.isNotEmpty || model.projector != null) {
        throw LlamaUnsupportedException(
          'The owning reranker loader accepts a text-only classifier without LoRA adapters or a multimodal projector.',
        );
      }
      await engine.setModel(model, params: params);
      await engine.initializeRerankingContext(params);
      return LlamaReranker._owned(engine);
    } catch (_) {
      await engine.dispose();
      rethrow;
    }
  }

  /// Frees an engine created by [load]; borrowed engines remain caller-owned.
  Future<void> dispose() =>
      _ownsEngine ? engine.dispose() : Future<void>.value();

  /// Inference engine, owned by this helper only when created through [load].
  final LlamaEngine engine;

  /// Explicit model/runtime probe; unloaded or disposed engines are unsupported.
  Future<LlamaRerankingCapabilities> get capabilities =>
      engine.backendRerankingCapabilities;

  /// Returns documents sorted by native output [scoreIndex], descending.
  ///
  /// Output zero matches upstream llama-server. Inspect [capabilities] to choose
  /// another classifier label; this API does not infer a positive class. Ties
  /// preserve input order. [topN] limits returned results after all documents
  /// are scored; null returns all. Empty documents lists return no results on
  /// a supported, loaded engine. Query and document text is preserved verbatim.
  ///
  /// Uses the model's named `rerank` placeholder template when present, or its
  /// vocabulary's BOS/SEP/EOS query/document token framing otherwise.
  /// Complete inputs are preflighted before inference; no truncation or partial
  /// result is returned. Oversized pairs throw [LlamaInferenceException].
  /// Unsupported models/runtimes throw [LlamaUnsupportedException], invalid
  /// score indices or negative [topN] throw [LlamaArgumentException]. An
  /// unloaded engine throws [LlamaContextException]; disposal throws
  /// [LlamaStateException]. Cancellation via [cancel] or the engine fails the call with [LlamaInferenceException] after
  /// its current native pass settles, retaining buffers until then.
  Future<List<LlamaRerankResult>> rerank(
    String query,
    List<String> documents, {
    int scoreIndex = 0,
    int? topN,
  }) async {
    if (topN != null && topN < 0) {
      throw LlamaArgumentException('Reranking topN must not be negative.');
    }
    final inputs = List<String>.of(documents);
    final output = await engine.rerankBackend(query, inputs, scoreIndex);
    final labels = output.classifierLabels;
    if (labels.isEmpty || output.scores.length != inputs.length) {
      throw LlamaInferenceException(
        'Reranking returned an invalid output shape.',
      );
    }
    final results = <LlamaRerankResult>[];
    for (var i = 0; i < output.scores.length; i++) {
      final scores = output.scores[i];
      if (scores.length != labels.length ||
          scoreIndex >= scores.length ||
          scores.any((score) => !score.isFinite)) {
        throw LlamaInferenceException(
          'Reranking returned invalid classifier scores.',
        );
      }
      results.add(
        LlamaRerankResult(
          index: i,
          score: scores[scoreIndex],
          classifierScores: scores,
          classifierLabels: labels,
        ),
      );
    }
    results.sort((a, b) {
      final order = b.score.compareTo(a.score);
      return order == 0 ? a.index.compareTo(b.index) : order;
    });
    return List<LlamaRerankResult>.unmodifiable(
      topN == null ? results : results.take(topN),
    );
  }

  /// Cancels this engine's pending inference, including a reranking call.
  ///
  /// The current native pass must settle before its output buffers are freed.
  void cancel() => engine.cancelGeneration();
}
