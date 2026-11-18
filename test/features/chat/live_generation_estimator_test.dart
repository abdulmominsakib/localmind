import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/models/live_generation.dart';

void main() {
  group('PrefillEstimator.estimatePrefillMs', () {
    test('small input is clamped to at least 500 ms', () {
      final ms = PrefillEstimator.estimatePrefillMs(
        inputChars: 8,
        isOnDevice: false,
      );
      expect(ms, greaterThanOrEqualTo(500));
      expect(ms, 500);
    });

    test('a very large input is clamped to at most 15000 ms', () {
      final ms = PrefillEstimator.estimatePrefillMs(
        inputChars: 10 * 1000 * 1000,
        isOnDevice: true,
      );
      expect(ms, lessThanOrEqualTo(15000));
      expect(ms, 15000);
    });

    test('a larger input returns a value >= a smaller input', () {
      final small = PrefillEstimator.estimatePrefillMs(
        inputChars: 100,
        isOnDevice: false,
      );
      final large = PrefillEstimator.estimatePrefillMs(
        inputChars: 2000,
        isOnDevice: false,
      );
      expect(large, greaterThanOrEqualTo(small));
    });

    test('isOnDevice is >= the remote estimate for the same input', () {
      final onDevice = PrefillEstimator.estimatePrefillMs(
        inputChars: 2000,
        isOnDevice: true,
      );
      final remote = PrefillEstimator.estimatePrefillMs(
        inputChars: 2000,
        isOnDevice: false,
      );
      expect(onDevice, greaterThanOrEqualTo(remote));
    });
  });

  group('LiveGeneration.copyWith', () {
    test('changes phase and can clear realPrefillProgress', () {
      final startedAt = DateTime(2026);
      final generation = LiveGeneration(
        phase: LiveGenerationPhase.processingPrompt,
        startedAt: startedAt,
        estimatedPrefillMs: 1000,
        realPrefillProgress: 0.5,
      );

      final updated = generation.copyWith(
        phase: LiveGenerationPhase.generating,
        clearRealPrefillProgress: true,
      );

      expect(updated.phase, LiveGenerationPhase.generating);
      expect(updated.realPrefillProgress, isNull);
      expect(updated.startedAt, startedAt);
      expect(updated.estimatedPrefillMs, 1000);
    });
  });
}
