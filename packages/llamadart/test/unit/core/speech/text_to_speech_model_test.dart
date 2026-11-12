import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('Qwen3TtsAdapter', () {
    const adapter = Qwen3TtsAdapter();

    test('drives the Qwen3-TTS audio-generation model only', () {
      expect(adapter.name, 'Qwen3-TTS');
      expect(adapter.supportsModel(BackendTextToSpeechModel.qwen3Tts), isTrue);
      expect(adapter.supportsModel(null), isFalse);
    });

    test('maps codes and English names to its ten codes', () {
      expect(adapter.supportedLanguages, <String>{
        'zh',
        'en',
        'ja',
        'ko',
        'de',
        'fr',
        'ru',
        'pt',
        'es',
        'it',
      });
      expect(adapter.normalizeLanguage('English'), 'en');
      expect(adapter.normalizeLanguage('KOREAN'), 'ko');
      expect(adapter.normalizeLanguage('Ja'), 'ja');
    });

    test('rejects other languages, naming the accepted codes', () {
      expect(
        () => adapter.normalizeLanguage('Klingon'),
        throwsA(
          isA<LlamaTextToSpeechException>().having(
            (error) => error.message,
            'message',
            'Unsupported Qwen3-TTS language `Klingon`. Use one of: '
                'zh, en, ja, ko, de, fr, ru, pt, es, it.',
          ),
        ),
      );
    });
  });

  test('the LFM3-Audio and Soprano adapters drive their models only', () {
    const lfm3 = Lfm3AudioTtsAdapter();
    const soprano = SopranoTtsAdapter();

    expect(lfm3.name, 'LFM3-Audio');
    expect(soprano.name, 'Soprano');
    for (final model in BackendTextToSpeechModel.values) {
      expect(
        lfm3.supportsModel(model),
        model == BackendTextToSpeechModel.lfm3Audio,
      );
      expect(
        soprano.supportsModel(model),
        model == BackendTextToSpeechModel.soprano,
      );
    }
    expect(lfm3.supportsModel(null), isFalse);
    expect(lfm3.normalizeLanguage('English'), 'English');
    expect(lfm3.supportedLanguages, isEmpty);
  });

  test('the Chatterbox and Pocket TTS adapters drive their models only', () {
    const chatterbox = ChatterboxTtsAdapter();
    const pocket = PocketTtsAdapter();

    expect(chatterbox.name, 'Chatterbox');
    expect(pocket.name, 'Pocket TTS');
    for (final model in BackendTextToSpeechModel.values) {
      expect(
        chatterbox.supportsModel(model),
        model == BackendTextToSpeechModel.chatterbox,
      );
      expect(
        pocket.supportsModel(model),
        model == BackendTextToSpeechModel.pocketTts,
      );
    }
    expect(chatterbox.supportsModel(null), isFalse);
    expect(chatterbox.normalizeLanguage('FR'), 'fr');
    expect(pocket.supportedLanguages, isEmpty);
  });

  test('a minimal adapter lowercases languages and lists none', () {
    const adapter = _MinimalAdapter();

    expect(adapter.normalizeLanguage('Pt-BR'), 'pt-br');
    expect(adapter.supportedLanguages, isEmpty);
  });

  test('TextToSpeechModel keeps its files and adapter', () {
    final source = ModelSource.path('tts.gguf');
    final projector = ModelSource.path('mmproj.gguf');
    final model = TextToSpeechModel(
      source,
      projector: projector,
      adapter: const Qwen3TtsAdapter(),
    );

    expect(model.source, same(source));
    expect(model.projector, same(projector));
    expect(model.adapter, isA<Qwen3TtsAdapter>());
  });
}

class _MinimalAdapter extends TextToSpeechAdapter {
  const _MinimalAdapter();

  @override
  String get name => 'Minimal';

  @override
  bool supportsModel(BackendTextToSpeechModel? model) => true;
}
