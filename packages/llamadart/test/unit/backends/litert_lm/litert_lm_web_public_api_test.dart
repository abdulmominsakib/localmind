@TestOn('browser')
// ignore_for_file: deprecated_member_use_from_same_package
library;

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('exports LiteRT-LM runtime value types on web', () {
    const metrics = LiteRtLmRuntimeMetrics(
      inputTokens: 1,
      outputTokens: 2,
      timeToFirstTokenSeconds: null,
      initSeconds: null,
      prefillTokensPerSecond: null,
      decodeTokensPerSecond: null,
      wallMilliseconds: 3,
    );
    const result = LiteRtLmRuntimeResult(text: 'web', metrics: metrics);

    expect(result.text, 'web');
    expect(result.metrics.toJson(), {
      'inputTokens': 1,
      'outputTokens': 2,
      'timeToFirstTokenSeconds': null,
      'initSeconds': null,
      'prefillTokensPerSecond': null,
      'decodeTokensPerSecond': null,
      'wallMilliseconds': 3,
    });
  });

  test('reports native-only LiteRT-LM runtime APIs as unsupported on web', () {
    expect(LiteRtLmRuntimeClient.new, throwsUnsupportedError);
    expect(LiteRtLmBenchmarkClient.new, throwsUnsupportedError);
  });

  test('exports LiteRT-LM web backend constructor on web', () async {
    final backend = LiteRtLmBackend(
      initialSendPort: null,
      preferredBackend: 'cpu',
    );

    expect(backend.supportsUrlLoading, isTrue);
    expect(await backend.getBackendName(), 'LiteRT-LM web cpu');
  });
}
