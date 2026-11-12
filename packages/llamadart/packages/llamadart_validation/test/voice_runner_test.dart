import 'package:llamadart_validation/src/speech_runner.dart';
import 'package:llamadart_validation/src/voice_runner.dart';
import 'package:test/test.dart';

class VoiceStage implements SpeechValidationAdapter {
  VoiceStage(this.output);
  final Map<String, Object?> output;
  int disposals = 0;
  bool brokenCleanup = false;
  @override
  Future<void> load() async {}
  @override
  Future<void> dispose() async {
    disposals++;
    if (brokenCleanup) throw StateError('cleanup');
  }

  @override
  Future<Map<String, Object?>> execute({
    bool cancel = false,
    bool cancelImmediately = false,
    bool invalid = false,
    bool bytesInput = false,
  }) async => output;
}

void main() {
  test(
    'actual transcript and response flow through stages; physical QA stays open',
    () async {
      final asr = VoiceStage({
        'predicate_passed': true,
        'transcript': 'known input',
      });
      final tts = VoiceStage({'predicate_passed': true});
      final result = await runVoiceRoundTrip(
        recognizer: asr,
        respond: (text) async {
          expect(text, 'known input');
          expect(asr.disposals, 1);
          return 'generated reply';
        },
        synthesizer: (text) {
          expect(text, 'generated reply');
          return tts;
        },
      );
      expect(result['functional_pass'], true);
      expect(result['response'], 'generated reply');
      expect(result['qualified'], false);
      expect(result['microphone'], 'NOT_RUN');
      expect(tts.disposals, 1);
    },
  );
  test('failed STT prevents chat and TTS from executing', () async {
    final asr = VoiceStage({'predicate_passed': false, 'transcript': 'wrong'});
    final result = await runVoiceRoundTrip(
      recognizer: asr,
      respond: (_) async => throw StateError('must not run'),
      synthesizer: (_) => throw StateError('must not run'),
    );
    expect(result['functional_pass'], false);
    expect(result.containsKey('response'), false);
    expect(asr.disposals, 1);
  });
  test(
    'empty response, failed synthesis and failed cleanup cannot pass',
    () async {
      for (final failure in ['empty', 'synthesis', 'cleanup']) {
        final asr = VoiceStage({
          'predicate_passed': true,
          'transcript': 'known',
        });
        final tts = VoiceStage({'predicate_passed': failure != 'synthesis'})
          ..brokenCleanup = failure == 'cleanup';
        final result = await runVoiceRoundTrip(
          recognizer: asr,
          respond: (_) async => failure == 'empty' ? '' : 'reply',
          synthesizer: (_) => tts,
        );
        expect(result['functional_pass'], false);
        expect(asr.disposals, greaterThan(0));
      }
    },
  );
}
