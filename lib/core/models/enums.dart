import '../constants/app_constants.dart';

enum EngineId { system, kitten, piper, melo, kokoro }

class EngineMeta {
  final String name;
  final String tagline;
  final int sizeMb;
  final int ramMb;
  final int voiceCount;
  final int accentColor;

  const EngineMeta({
    required this.name,
    required this.tagline,
    required this.sizeMb,
    required this.ramMb,
    required this.voiceCount,
    required this.accentColor,
  });

  static const system = EngineMeta(
    name: 'System TTS',
    tagline: 'Built-in device engine',
    sizeMb: 0,
    ramMb: 0,
    voiceCount: 0,
    accentColor: 0xFF9E9E9E,
  );

  static const kitten = EngineMeta(
    name: 'Kitten TTS',
    tagline: 'High-speed neural TTS',
    sizeMb: 57,
    ramMb: 120,
    voiceCount: 8,
    accentColor: 0xFFFF9800,
  );

  static const piper = EngineMeta(
    name: 'Sherpa ONNX VITS',
    tagline: 'Offline Piper voices',
    sizeMb: 50,
    ramMb: 100,
    voiceCount: 2,
    accentColor: 0xFF4CAF50,
  );

  static const melo = EngineMeta(
    name: 'Melo TTS',
    tagline: 'Chinese-English VITS',
    sizeMb: 170,
    ramMb: 400,
    voiceCount: 1,
    accentColor: 0xFFE91E63,
  );

  static const kokoro = EngineMeta(
    name: 'Kokoro TTS',
    tagline: 'Chinese-English neural voices',
    sizeMb: 115,
    ramMb: 300,
    voiceCount: 15,
    accentColor: 0xFF3F51B5,
  );

  static EngineMeta forEngine(EngineId engine) {
    switch (engine) {
      case EngineId.kitten:
        return kitten;
      case EngineId.piper:
        return piper;
      case EngineId.melo:
        return melo;
      case EngineId.kokoro:
        return kokoro;
      default:
        return system;
    }
  }
}

class Voice {
  final String id;
  final String name;
  final EngineId engine;
  final String family;
  final String? language;
  final String gender;

  /// The model's speaker index this voice maps to. List position alone is not
  /// enough once an engine ships a curated subset (Kokoro) of a larger
  /// speaker table; Kitten voices carry their historical index explicitly.
  final int speakerId;

  const Voice({
    required this.id,
    required this.name,
    required this.engine,
    required this.family,
    this.language,
    required this.gender,
    this.speakerId = 0,
  });
}

List<Voice> voicesForEngine(EngineId engine) {
  switch (engine) {
    case EngineId.kitten:
      return kittenVoices;
    case EngineId.piper:
      return piperVoices;
    case EngineId.melo:
      return meloVoices;
    case EngineId.kokoro:
      return kokoroVoices;
    default:
      return [];
  }
}

Map<String, List<Voice>> voicesGroupedByFamily(EngineId engine) {
  final result = <String, List<Voice>>{};
  for (final voice in voicesForEngine(engine)) {
    result.putIfAbsent(voice.family, () => <Voice>[]).add(voice);
  }
  return result;
}

const List<Voice> kittenVoices = [
  Voice(
    id: 'Jasper',
    name: 'Jasper',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'm',
    speakerId: 0,
  ),
  Voice(
    id: 'Bella',
    name: 'Bella',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'f',
    speakerId: 1,
  ),
  Voice(
    id: 'Bruno',
    name: 'Bruno',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'm',
    speakerId: 2,
  ),
  Voice(
    id: 'Luna',
    name: 'Luna',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'f',
    speakerId: 3,
  ),
  Voice(
    id: 'Hugo',
    name: 'Hugo',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'm',
    speakerId: 4,
  ),
  Voice(
    id: 'Rosie',
    name: 'Rosie',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'f',
    speakerId: 5,
  ),
  Voice(
    id: 'Leo',
    name: 'Leo',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'm',
    speakerId: 6,
  ),
  Voice(
    id: 'Kiki',
    name: 'Kiki',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'f',
    speakerId: 7,
  ),
];

const List<Voice> meloVoices = [
  Voice(
    id: 'mei',
    name: 'Mei',
    engine: EngineId.melo,
    family: 'Melo',
    language: 'zh',
    gender: 'f',
    speakerId: 0,
  ),
];

/// Curated Chinese-first subset of kokoro-multi-lang-v1_1's 103 speakers.
/// sid ranges follow sherpa-onnx PR #1942: 0-2 English female
/// (af_maple / af_sol / bf_vale), 3-57 Chinese female (`zf_<sid-2>`),
/// 58-102 Chinese male (`zm_<sid-57>`).
const List<Voice> kokoroVoices = [
  Voice(
    id: 'zf_001',
    name: 'zf_001',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'f',
    speakerId: 3,
  ),
  Voice(
    id: 'zf_005',
    name: 'zf_005',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'f',
    speakerId: 7,
  ),
  Voice(
    id: 'zf_011',
    name: 'zf_011',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'f',
    speakerId: 13,
  ),
  Voice(
    id: 'zf_021',
    name: 'zf_021',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'f',
    speakerId: 23,
  ),
  Voice(
    id: 'zf_051',
    name: 'zf_051',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'f',
    speakerId: 53,
  ),
  Voice(
    id: 'zf_055',
    name: 'zf_055',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'f',
    speakerId: 57,
  ),
  Voice(
    id: 'zm_001',
    name: 'zm_001',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'm',
    speakerId: 58,
  ),
  Voice(
    id: 'zm_007',
    name: 'zm_007',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'm',
    speakerId: 64,
  ),
  Voice(
    id: 'zm_017',
    name: 'zm_017',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'm',
    speakerId: 74,
  ),
  Voice(
    id: 'zm_027',
    name: 'zm_027',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'm',
    speakerId: 84,
  ),
  Voice(
    id: 'zm_037',
    name: 'zm_037',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'm',
    speakerId: 94,
  ),
  Voice(
    id: 'zm_045',
    name: 'zm_045',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'zh',
    gender: 'm',
    speakerId: 102,
  ),
  Voice(
    id: 'af_maple',
    name: 'Maple (EN)',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'en',
    gender: 'f',
    speakerId: 0,
  ),
  Voice(
    id: 'af_sol',
    name: 'Sol (EN)',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'en',
    gender: 'f',
    speakerId: 1,
  ),
  Voice(
    id: 'bf_vale',
    name: 'Vale (EN)',
    engine: EngineId.kokoro,
    family: 'Kokoro',
    language: 'en',
    gender: 'f',
    speakerId: 2,
  ),
];

const List<Voice> piperVoices = [
  Voice(
    id: 'en_US-lessac-medium',
    name: 'Lessac (US)',
    engine: EngineId.piper,
    family: 'Piper',
    language: 'en',
    gender: 'f',
  ),
  Voice(
    id: 'en_US-ryan-medium',
    name: 'Ryan (US)',
    engine: EngineId.piper,
    family: 'Piper',
    language: 'en',
    gender: 'm',
  ),
];

EngineId engineIdFromString(String value) {
  switch (value) {
    case 'kitten':
      return EngineId.kitten;
    case 'piper':
      return EngineId.piper;
    case 'melo':
      return EngineId.melo;
    case 'kokoro':
      return EngineId.kokoro;
    default:
      return EngineId.system;
  }
}

Voice? voiceFromSettings(String? voiceId, EngineId engine) {
  if (voiceId == null || voiceId.isEmpty) return null;
  final voices = voicesForEngine(engine);
  try {
    return voices.firstWhere((v) => v.id == voiceId);
  } catch (_) {
    return null;
  }
}

enum ServerType {
  lmStudio,
  openAICompatible,
  ollama,
  ollamaCloud,
  openRouter,
  onDevice,
  requesty,
}

extension ServerTypeLogoExtension on ServerType {
  String? get logoAsset {
    switch (this) {
      case ServerType.lmStudio:
        return AppConstants.lmStudioLogoAsset;
      case ServerType.ollama:
      case ServerType.ollamaCloud:
        return AppConstants.ollamaLogoAsset;
      case ServerType.openRouter:
        return AppConstants.openRouterLogoAsset;
      case ServerType.requesty:
        return AppConstants.requestyLogoAsset;
      case ServerType.openAICompatible:
      case ServerType.onDevice:
        return null;
    }
  }

  bool get hasLogo => logoAsset != null;
}

enum ConnectionStatus { connected, disconnected, checking, error }

enum MessageRole { user, assistant, system, tool }

enum MessageStatus { sending, streaming, complete, error, cancelled }

enum ModelStatus { unloaded, loading, loaded, preloaded, thinking }

enum OnDeviceEngineStatus { notLoaded, loading, loaded, error }

enum OnDeviceModelState {
  notDownloaded,
  downloading,
  downloaded,
  loading,
  loaded,
  error,
}
