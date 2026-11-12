import 'package:llamadart/src/backends/litert_lm/litert_lm_asr_types.dart';
import 'package:llamadart/src/core/speech/litert_lm_speech_to_text_driver_stub.dart';
import 'package:test/test.dart';

void main() {
  test('stub reports dedicated ASR as native-only', () async {
    final driver = createLiteRtLmSpeechToTextDriver();

    final support = await driver.probeSupport();

    expect(support.isSupported, isFalse);
    expect(support.unsupportedReason, contains('native runtime'));
    expect(
      () => driver.start(
        const LiteRtLmAsrRuntimeConfig(
          modelPath: '/models/moonshine.tflite',
          tokenizerPath: '/models/tokenizer.json',
          modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
