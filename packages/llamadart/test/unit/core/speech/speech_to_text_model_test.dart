import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('Qwen3AsrAdapter', () {
    const adapter = Qwen3AsrAdapter();
    const audio = SpeechAudioFileInput('speech.wav');

    test('asks for a transcription and adds context', () {
      expect(adapter.name, 'Qwen3-ASR');
      expect(
        adapter.promptFor(const SpeechToTextRequest(audio: audio)),
        'Transcribe this audio accurately.',
      );
      expect(
        adapter.promptFor(
          const SpeechToTextRequest(audio: audio, contextPrompt: ' llamadart '),
        ),
        'Transcribe this audio accurately. Context: llamadart',
      );
    });

    test('strips the language prefix and the bare transcript marker', () {
      final prefixed = adapter.parseTranscript(
        ' language English<asr_text> Hello there. ',
      );
      expect(prefixed.text, 'Hello there.');
      expect(prefixed.language, isNull);
      expect(adapter.parseTranscript('<ASR_TEXT>Hi.').text, 'Hi.');
      expect(adapter.parseTranscript('  plain text ').text, 'plain text');
      expect(adapter.parseTranscript('language English<asr_text>').text, '');
    });

    test('takes context prompts but no language hints', () {
      expect(adapter.supportsContextPrompt, isTrue);
      expect(adapter.supportsLanguageHints, isFalse);
      expect(adapter.supportsLanguageDetection, isFalse);
    });
  });

  test('LiteRtLmAsrAdapter defaults match the runtime config', () {
    const adapter = LiteRtLmAsrAdapter(LiteRtLmAsrModelPreset.moonshineTiny);
    const config = LiteRtLmAsrRuntimeConfig(
      modelPath: 'model.tflite',
      tokenizerPath: 'tokenizer.json',
      modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
    );

    expect(adapter.name, 'LiteRT-LM ASR');
    expect(adapter.numberOfThreads, config.numberOfThreads);
    expect(adapter.maxBufferedAudio, config.maxBufferedAudio);
    expect(adapter.overlapRatio, config.overlapRatio);
    expect(adapter.libraryPath, isNull);
  });

  test('SpeechToTextModel keeps its files and adapter', () {
    final source = ModelSource.path('asr.gguf');
    final projector = ModelSource.path('mmproj.gguf');
    final model = SpeechToTextModel(
      source,
      projector: projector,
      adapter: const Qwen3AsrAdapter(),
    );

    expect(model.source, same(source));
    expect(model.projector, same(projector));
    expect(model.tokenizer, isNull);
    expect(model.adapter, isA<SpeechToTextPromptAdapter>());
  });

  test('a minimal prompt adapter keeps the defaults', () {
    const adapter = _MinimalAdapter();

    expect(adapter.supportsContextPrompt, isTrue);
    expect(adapter.supportsLanguageHints, isFalse);
    expect(adapter.supportsLanguageDetection, isFalse);
  });
}

class _MinimalAdapter extends SpeechToTextPromptAdapter {
  const _MinimalAdapter();

  @override
  String get name => 'Minimal';

  @override
  String promptFor(SpeechToTextRequest request) => 'Transcribe.';

  @override
  SpeechToTextTranscript parseTranscript(String output) =>
      SpeechToTextTranscript(output);
}
