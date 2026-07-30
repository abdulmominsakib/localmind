enum EngineId { system, kitten, piper }

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

  static EngineMeta forEngine(EngineId engine) {
    switch (engine) {
      case EngineId.kitten:
        return kitten;
      case EngineId.piper:
        return piper;
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

  const Voice({
    required this.id,
    required this.name,
    required this.engine,
    required this.family,
    this.language,
    required this.gender,
  });
}

List<Voice> voicesForEngine(EngineId engine) {
  switch (engine) {
    case EngineId.kitten:
      return kittenVoices;
    case EngineId.piper:
      return piperVoices;
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
  ),
  Voice(
    id: 'Bella',
    name: 'Bella',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'f',
  ),
  Voice(
    id: 'Bruno',
    name: 'Bruno',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'm',
  ),
  Voice(
    id: 'Luna',
    name: 'Luna',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'f',
  ),
  Voice(
    id: 'Hugo',
    name: 'Hugo',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'm',
  ),
  Voice(
    id: 'Rosie',
    name: 'Rosie',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'f',
  ),
  Voice(
    id: 'Leo',
    name: 'Leo',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'm',
  ),
  Voice(
    id: 'Kiki',
    name: 'Kiki',
    engine: EngineId.kitten,
    family: 'Kitten',
    language: 'en',
    gender: 'f',
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
