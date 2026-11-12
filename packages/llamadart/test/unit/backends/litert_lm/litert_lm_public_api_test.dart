@TestOn('vm')
library;

import 'package:llamadart/backend.dart';
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
    expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);

    client.configureResponseThinkingTags(
      startTag: '<thought>',
      endTag: '</thought>',
    );

    client.dispose();
  });
}
