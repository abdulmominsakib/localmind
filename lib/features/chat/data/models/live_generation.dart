/// Phase of the active reply shown in the composer status bar.
enum LiveGenerationPhase { processingPrompt, generating, completed }

/// Snapshot of the reply currently in flight, surfaced to the composer.
class LiveGeneration {
  const LiveGeneration({
    required this.phase,
    required this.startedAt,
    required this.estimatedPrefillMs,
    this.realPrefillProgress,
    this.firstTokenAt,
    this.completedAt,
    this.outputTokens,
    this.tokensPerSecond,
    this.generationTimeMs,
  });

  final LiveGenerationPhase phase;
  final DateTime startedAt;

  /// Estimated time, in milliseconds, that prompt prefill should take.
  final int estimatedPrefillMs;

  /// Real 0..1 prefill progress when a backend reports it (LM Studio),
  /// otherwise null and the UI animates the estimate.
  final double? realPrefillProgress;
  final DateTime? firstTokenAt;
  final DateTime? completedAt;
  final int? outputTokens;
  final double? tokensPerSecond;
  final int? generationTimeMs;

  LiveGeneration copyWith({
    LiveGenerationPhase? phase,
    DateTime? startedAt,
    int? estimatedPrefillMs,
    double? realPrefillProgress,
    bool clearRealPrefillProgress = false,
    DateTime? firstTokenAt,
    DateTime? completedAt,
    int? outputTokens,
    double? tokensPerSecond,
    int? generationTimeMs,
  }) {
    return LiveGeneration(
      phase: phase ?? this.phase,
      startedAt: startedAt ?? this.startedAt,
      estimatedPrefillMs: estimatedPrefillMs ?? this.estimatedPrefillMs,
      realPrefillProgress: clearRealPrefillProgress
          ? null
          : (realPrefillProgress ?? this.realPrefillProgress),
      firstTokenAt: firstTokenAt ?? this.firstTokenAt,
      completedAt: completedAt ?? this.completedAt,
      outputTokens: outputTokens ?? this.outputTokens,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      generationTimeMs: generationTimeMs ?? this.generationTimeMs,
    );
  }
}

/// Estimates how long prompt prefill will take when the backend does not
/// report progress. Prompt-size aware: longer inputs take visibly longer.
/// These are UX heuristics, not measurements.
class PrefillEstimator {
  const PrefillEstimator._();

  static const double _charsPerToken = 4.0;
  static const double _onDeviceTokensPerSecond = 120.0;
  static const double _remoteTokensPerSecond = 800.0;
  static const int _minMs = 500;
  static const int _maxMs = 15000;

  static int estimatePrefillMs({
    required int inputChars,
    required bool isOnDevice,
  }) {
    final tokens = (inputChars / _charsPerToken).ceil();
    final speed = isOnDevice
        ? _onDeviceTokensPerSecond
        : _remoteTokensPerSecond;
    final ms = (tokens / speed * 1000).round();
    return ms.clamp(_minMs, _maxMs);
  }
}
