// coverage:ignore-file

import '../../backends/litert_lm/litert_lm_runtime_stub.dart';

/// Deprecated compatibility name for [LiteRtLmRuntimeMetrics].
@Deprecated('Use LiteRtLmRuntimeMetrics from the LiteRT-LM runtime API.')
class LiteRtLmBenchmarkMetrics extends LiteRtLmRuntimeMetrics {
  /// Creates benchmark metrics.
  const LiteRtLmBenchmarkMetrics({
    required super.inputTokens,
    required super.outputTokens,
    required super.timeToFirstTokenSeconds,
    required super.initSeconds,
    required super.prefillTokensPerSecond,
    required super.decodeTokensPerSecond,
    required super.wallMilliseconds,
  });

  /// Converts stable runtime metrics to the deprecated compatibility type.
  factory LiteRtLmBenchmarkMetrics.fromRuntime(LiteRtLmRuntimeMetrics metrics) {
    return LiteRtLmBenchmarkMetrics(
      inputTokens: metrics.inputTokens,
      outputTokens: metrics.outputTokens,
      timeToFirstTokenSeconds: metrics.timeToFirstTokenSeconds,
      initSeconds: metrics.initSeconds,
      prefillTokensPerSecond: metrics.prefillTokensPerSecond,
      decodeTokensPerSecond: metrics.decodeTokensPerSecond,
      wallMilliseconds: metrics.wallMilliseconds,
    );
  }
}

/// Deprecated compatibility name for [LiteRtLmRuntimeResult].
@Deprecated('Use LiteRtLmRuntimeResult from the LiteRT-LM runtime API.')
class LiteRtLmBenchmarkResult extends LiteRtLmRuntimeResult {
  /// Creates a benchmark result.
  const LiteRtLmBenchmarkResult({
    required super.text,
    required LiteRtLmBenchmarkMetrics metrics,
  }) : super(metrics: metrics);

  /// Converts a stable runtime result to the deprecated compatibility type.
  factory LiteRtLmBenchmarkResult.fromRuntime(LiteRtLmRuntimeResult result) {
    return LiteRtLmBenchmarkResult(
      text: result.text,
      metrics: LiteRtLmBenchmarkMetrics.fromRuntime(result.metrics),
    );
  }

  @override
  LiteRtLmBenchmarkMetrics get metrics =>
      super.metrics as LiteRtLmBenchmarkMetrics;
}

/// Deprecated compatibility name for [LiteRtLmRuntimeClient].
@Deprecated('Use LiteRtLmRuntimeClient from the LiteRT-LM runtime API.')
class LiteRtLmBenchmarkClient extends LiteRtLmRuntimeClient {
  /// Creates a placeholder client on platforms without `dart:ffi`.
  LiteRtLmBenchmarkClient();

  /// Runs the benchmark.
  @override
  Future<LiteRtLmBenchmarkResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,
  }) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Reads benchmark metrics for the active conversation.
  @override
  LiteRtLmBenchmarkMetrics readMetrics({required int wallMilliseconds}) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }
}
