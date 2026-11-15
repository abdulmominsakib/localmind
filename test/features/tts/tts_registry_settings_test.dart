import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';

void main() {
  group('engineIdFromString', () {
    test('parses the new Chinese engines', () {
      expect(engineIdFromString('melo'), EngineId.melo);
      expect(engineIdFromString('kokoro'), EngineId.kokoro);
    });

    test('keeps legacy values and unknown fallback', () {
      expect(engineIdFromString('kitten'), EngineId.kitten);
      expect(engineIdFromString('piper'), EngineId.piper);
      expect(engineIdFromString('system'), EngineId.system);
      expect(engineIdFromString('nonsense'), EngineId.system);
    });
  });

  group('voice registry', () {
    test('Melo ships a single Chinese voice at sid 0', () {
      final voices = voicesForEngine(EngineId.melo);
      expect(voices, hasLength(1));
      expect(voices.first.id, 'mei');
      expect(voices.first.speakerId, 0);
      expect(voices.first.language, 'zh');
    });

    test('Kokoro curated subset has stable unique ids and valid sids', () {
      final voices = voicesForEngine(EngineId.kokoro);
      expect(voices.length, EngineMeta.kokoro.voiceCount);
      expect(voices.map((v) => v.id).toSet(), hasLength(voices.length));
      for (final voice in voices) {
        expect(voice.speakerId, inInclusiveRange(0, 102), reason: voice.id);
      }
      // Chinese-first: the subset contains zh voices of both genders.
      expect(voices.any((v) => v.language == 'zh' && v.gender == 'f'), isTrue);
      expect(voices.any((v) => v.language == 'zh' && v.gender == 'm'), isTrue);
    });

    test('voicesGroupedByFamily keeps one family per new engine', () {
      expect(voicesGroupedByFamily(EngineId.melo).keys, ['Melo']);
      expect(voicesGroupedByFamily(EngineId.kokoro).keys, ['Kokoro']);
    });

    test('voiceFromSettings resolves only within the engine', () {
      expect(voiceFromSettings('mei', EngineId.melo)?.id, 'mei');
      expect(voiceFromSettings('mei', EngineId.kokoro), isNull);
    });
  });

  group('EngineMeta', () {
    test('new engines resolve their metadata', () {
      expect(EngineMeta.forEngine(EngineId.melo).name, 'Melo TTS');
      expect(EngineMeta.forEngine(EngineId.kokoro).name, 'Kokoro TTS');
    });
  });

  group('AppSettings roundtrip', () {
    test('persists and restores a Chinese engine selection', () {
      final settings = AppSettings(
        ttsEngine: EngineId.melo,
        ttsVoiceId: 'mei',
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.ttsEngine, EngineId.melo);
      expect(restored.ttsVoiceId, 'mei');

      final kokoro = restored.copyWith(
        ttsEngine: EngineId.kokoro,
        ttsVoiceId: 'zf_001',
      );
      final restoredKokoro = AppSettings.fromJson(kokoro.toJson());
      expect(restoredKokoro.ttsEngine, EngineId.kokoro);
      expect(restoredKokoro.ttsVoiceId, 'zf_001');
    });
  });
}
