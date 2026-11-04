@TestOn('vm')
// ignore_for_file: deprecated_member_use_from_same_package
library;

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('exports stable LiteRT-LM runtime types from package API', () {
    const metrics = LiteRtLmRuntimeMetrics(
      inputTokens: 3,
      outputTokens: 5,
      timeToFirstTokenSeconds: 0.25,
      initSeconds: 1.0,
      prefillTokensPerSecond: 10.0,
      decodeTokensPerSecond: 20.0,
      wallMilliseconds: 1250,
    );
    const result = LiteRtLmRuntimeResult(text: 'hello', metrics: metrics);
    final client = LiteRtLmRuntimeClient();

    expect(result.text, 'hello');
    expect(result.metrics, same(metrics));
    expect(client, isA<LiteRtLmRuntimeClient>());

    client.dispose();
  });

  test('keeps deprecated LiteRT-LM benchmark names exported', () {
    const metrics = LiteRtLmBenchmarkMetrics(
      inputTokens: 3,
      outputTokens: 5,
      timeToFirstTokenSeconds: null,
      initSeconds: null,
      prefillTokensPerSecond: null,
      decodeTokensPerSecond: null,
      wallMilliseconds: 1250,
    );
    const result = LiteRtLmBenchmarkResult(text: 'hello', metrics: metrics);

    expect(metrics, isA<LiteRtLmRuntimeMetrics>());
    expect(result, isA<LiteRtLmRuntimeResult>());
    expect(result.metrics, same(metrics));
  });
}
