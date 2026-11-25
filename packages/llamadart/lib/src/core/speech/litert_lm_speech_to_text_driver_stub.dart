import '../../backends/litert_lm/litert_lm_asr_types.dart';
import 'litert_lm_speech_to_text_driver.dart';

/// Creates the unsupported non-native LiteRT-LM speech driver.
LiteRtLmSpeechToTextDriver createLiteRtLmSpeechToTextDriver() =>
    const _UnsupportedLiteRtLmSpeechToTextDriver();

class _UnsupportedLiteRtLmSpeechToTextDriver
    implements LiteRtLmSpeechToTextDriver {
  const _UnsupportedLiteRtLmSpeechToTextDriver();

  @override
  Future<LiteRtLmSpeechToTextSupport> probeSupport({
    String? libraryPath,
  }) async => const LiteRtLmSpeechToTextSupport(
    isSupported: false,
    unsupportedReason:
        'Dedicated LiteRT-LM speech recognition requires a native runtime.',
  );

  @override
  Future<LiteRtLmSpeechToTextWorker> start(
    LiteRtLmAsrRuntimeConfig config, {
    String? libraryPath,
  }) {
    throw UnsupportedError(
      'Dedicated LiteRT-LM speech recognition requires a native runtime.',
    );
  }
}
