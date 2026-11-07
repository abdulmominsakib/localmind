import 'package:llamadart/src/backends/backend.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaBackend interface is available', () {
    expect(LlamaBackend, isNotNull);
  });

  test('BackendEmbeddings capability interface is available', () {
    expect(BackendEmbeddings, isNotNull);
  });

  test('BackendEmbeddingsSupport capability interface is available', () {
    expect(BackendEmbeddingsSupport, isNotNull);
  });

  test('BackendBatchEmbeddings capability interface is available', () {
    expect(BackendBatchEmbeddings, isNotNull);
  });

  test('BackendStatePersistence capability interface is available', () {
    expect(BackendStatePersistence, isNotNull);
  });

  group('BackendPerfContextData', () {
    test('computes speculative acceptance rate when counts are available', () {
      const perf = BackendPerfContextData(
        loadMs: 0,
        promptEvalMs: 0,
        evalMs: 0,
        sampleMs: 0,
        promptEvalTokens: 0,
        evalTokens: 0,
        sampleCount: 0,
        reusedGraphs: 0,
        speculativeDraftTokens: 8,
        speculativeAcceptedDraftTokens: 6,
      );

      expect(perf.speculativeAcceptanceRate, 0.75);
    });

    test('returns null speculative acceptance rate without draft count', () {
      const perf = BackendPerfContextData(
        loadMs: 0,
        promptEvalMs: 0,
        evalMs: 0,
        sampleMs: 0,
        promptEvalTokens: 0,
        evalTokens: 0,
        sampleCount: 0,
        reusedGraphs: 0,
      );

      expect(perf.speculativeAcceptanceRate, isNull);
    });

    test('keeps explicit zero speculative counters', () {
      const perf = BackendPerfContextData(
        loadMs: 0,
        promptEvalMs: 0,
        evalMs: 0,
        sampleMs: 0,
        promptEvalTokens: 0,
        evalTokens: 0,
        sampleCount: 0,
        reusedGraphs: 0,
        speculativeDraftTokens: 0,
        speculativeAcceptedDraftTokens: 0,
        speculativeDraftAttempts: 0,
        speculativeVerifyTokens: 0,
        speculativeReplayTokens: 0,
        speculativeDraftMs: 0,
        speculativeVerifyMs: 0,
      );

      expect(perf.speculativeDraftTokens, 0);
      expect(perf.speculativeAcceptedDraftTokens, 0);
      expect(perf.speculativeDraftAttempts, 0);
      expect(perf.speculativeVerifyTokens, 0);
      expect(perf.speculativeReplayTokens, 0);
      expect(perf.speculativeDraftMs, 0);
      expect(perf.speculativeVerifyMs, 0);
      expect(perf.speculativeAcceptanceRate, isNull);
    });
  });

  group('StateLoadResult', () {
    test('exposes the recovered token sequence', () {
      const result = StateLoadResult(tokens: [1, 2, 3]);
      expect(result.tokens, [1, 2, 3]);
    });

    test('accepts an empty token list', () {
      const result = StateLoadResult(tokens: []);
      expect(result.tokens, isEmpty);
    });
  });
}
