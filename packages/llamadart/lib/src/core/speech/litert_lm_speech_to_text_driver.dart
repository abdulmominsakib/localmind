import 'dart:typed_data';

import '../../backends/litert_lm/litert_lm_asr_types.dart';

/// Internal capability result for the dedicated LiteRT-LM ASR runtime.
class LiteRtLmSpeechToTextSupport {
  /// Whether the packaged runtime exposes the required ASR ABI.
  final bool isSupported;

  /// Actionable diagnostic when [isSupported] is false.
  final String? unsupportedReason;

  /// Creates an internal capability result.
  const LiteRtLmSpeechToTextSupport({
    required this.isSupported,
    this.unsupportedReason,
  });
}

/// Internal cumulative transcript update emitted by the ASR worker.
class LiteRtLmSpeechToTextUpdate {
  /// Stable transcript prefix.
  final String confirmedText;

  /// Replaceable hypothesis for the current inference window.
  final String pendingText;

  /// Whether this update completes the input stream.
  final bool isFinal;

  /// Total mono samples accepted by the native session.
  final int acceptedSamples;

  /// Creates an internal transcript update.
  const LiteRtLmSpeechToTextUpdate({
    required this.confirmedText,
    required this.pendingText,
    required this.isFinal,
    required this.acceptedSamples,
  });
}

/// Platform-specific dedicated LiteRT-LM ASR driver.
abstract interface class LiteRtLmSpeechToTextDriver {
  /// Probes the packaged runtime without loading an ASR model.
  Future<LiteRtLmSpeechToTextSupport> probeSupport({String? libraryPath});

  /// Creates one worker-isolated native session.
  Future<LiteRtLmSpeechToTextWorker> start(
    LiteRtLmAsrRuntimeConfig config, {
    String? libraryPath,
  });
}

/// Worker-isolated dedicated LiteRT-LM ASR session.
abstract interface class LiteRtLmSpeechToTextWorker {
  /// Cumulative confirmed and replaceable pending transcript updates.
  Stream<LiteRtLmSpeechToTextUpdate> get updates;

  /// Pushes mono 16 kHz float PCM with bounded asynchronous backpressure.
  Future<int> pushAudio(Float32List samples);

  /// Flushes the final partial inference window and returns final text.
  Future<String> finish();

  /// Requests cooperative cancellation between inference windows.
  Future<void> cancel();

  /// Releases the worker isolate and native resources.
  Future<void> dispose();
}

/// Test-only driver override used by focused public API tests.
LiteRtLmSpeechToTextDriver? debugLiteRtLmSpeechToTextDriverOverride;
