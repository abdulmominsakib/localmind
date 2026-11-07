@TestOn('vm')
// ignore_for_file: deprecated_member_use_from_same_package
library;

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/experimental/litert_lm/litert_lm_benchmark.dart';
import 'package:test/test.dart';

void main() {
  test('LiteRtLmBenchmarkMetrics serializes benchmark counters', () {
    const metrics = LiteRtLmBenchmarkMetrics(
      inputTokens: 12,
      outputTokens: 34,
      timeToFirstTokenSeconds: 0.5,
      initSeconds: 1.25,
      prefillTokensPerSecond: 20.0,
      decodeTokensPerSecond: 30.0,
      wallMilliseconds: 4567,
    );

    expect(metrics.toJson(), {
      'inputTokens': 12,
      'outputTokens': 34,
      'timeToFirstTokenSeconds': 0.5,
      'initSeconds': 1.25,
      'prefillTokensPerSecond': 20.0,
      'decodeTokensPerSecond': 30.0,
      'wallMilliseconds': 4567,
    });
  });

  test('LiteRtLmBenchmarkResult keeps generated text with metrics', () {
    const metrics = LiteRtLmBenchmarkMetrics(
      inputTokens: 1,
      outputTokens: 2,
      timeToFirstTokenSeconds: null,
      initSeconds: null,
      prefillTokensPerSecond: null,
      decodeTokensPerSecond: null,
      wallMilliseconds: 3,
    );

    const result = LiteRtLmBenchmarkResult(text: 'hello', metrics: metrics);

    expect(result.text, 'hello');
    expect(result.metrics, same(metrics));
  });

  test('deprecated benchmark aliases copy runtime metrics and results', () {
    const runtimeMetrics = LiteRtLmRuntimeMetrics(
      inputTokens: 5,
      outputTokens: 6,
      timeToFirstTokenSeconds: 0.25,
      initSeconds: 0.75,
      prefillTokensPerSecond: 10,
      decodeTokensPerSecond: 20,
      wallMilliseconds: 1234,
    );
    const runtimeResult = LiteRtLmRuntimeResult(
      text: 'runtime',
      metrics: runtimeMetrics,
    );

    final metrics = LiteRtLmBenchmarkMetrics.fromRuntime(runtimeMetrics);
    final result = LiteRtLmBenchmarkResult.fromRuntime(runtimeResult);

    expect(metrics.inputTokens, 5);
    expect(metrics.outputTokens, 6);
    expect(metrics.timeToFirstTokenSeconds, 0.25);
    expect(metrics.initSeconds, 0.75);
    expect(metrics.prefillTokensPerSecond, 10);
    expect(metrics.decodeTokensPerSecond, 20);
    expect(metrics.wallMilliseconds, 1234);
    expect(result.text, 'runtime');
    expect(result.metrics, isA<LiteRtLmBenchmarkMetrics>());
    expect(result.metrics.toJson(), metrics.toJson());
  });
}
