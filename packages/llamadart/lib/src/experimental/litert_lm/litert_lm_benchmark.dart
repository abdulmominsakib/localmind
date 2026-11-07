// ignore_for_file: public_member_api_docs

import '../../backends/litert_lm/litert_lm_runtime.dart';

@Deprecated('Use LiteRtLmRuntimeMetrics from the LiteRT-LM runtime API.')
class LiteRtLmBenchmarkMetrics extends LiteRtLmRuntimeMetrics {
  const LiteRtLmBenchmarkMetrics({
    required super.inputTokens,
    required super.outputTokens,
    required super.timeToFirstTokenSeconds,
    required super.initSeconds,
    required super.prefillTokensPerSecond,
    required super.decodeTokensPerSecond,
    required super.wallMilliseconds,
  });

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

@Deprecated('Use LiteRtLmRuntimeResult from the LiteRT-LM runtime API.')
class LiteRtLmBenchmarkResult extends LiteRtLmRuntimeResult {
  const LiteRtLmBenchmarkResult({
    required super.text,
    required LiteRtLmBenchmarkMetrics metrics,
  }) : super(metrics: metrics);

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

@Deprecated('Use LiteRtLmRuntimeClient from the LiteRT-LM runtime API.')
class LiteRtLmBenchmarkClient extends LiteRtLmRuntimeClient {
  @override
  Future<LiteRtLmBenchmarkResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,
  }) async {
    return LiteRtLmBenchmarkResult.fromRuntime(
      await super.run(
        prompt: prompt,
        warmupRuns: warmupRuns,
        measuredRuns: measuredRuns,
      ),
    );
  }

  @override
  LiteRtLmBenchmarkMetrics readMetrics({required int wallMilliseconds}) {
    return LiteRtLmBenchmarkMetrics.fromRuntime(
      super.readMetrics(wallMilliseconds: wallMilliseconds),
    );
  }
}
