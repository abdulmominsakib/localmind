enum ServerType { lmStudio, openAICompatible, ollama, openRouter, onDevice }

enum ConnectionStatus { connected, disconnected, checking, error }

enum MessageRole { user, assistant, system, tool }

enum MessageStatus { sending, streaming, complete, error }

enum ModelStatus { unloaded, loading, loaded, preloaded, thinking }

enum EngineStatus { notLoaded, loading, loaded, error }

enum LiteLmBackendType { cpu, gpu, npu }

enum TtsEngine { system, kitten }

enum KittenTtsVoice {
  bella,
  jasper,
  luna,
  bruno,
  rosie,
  hugo,
  kiki,
  leo;

  String get displayName {
    switch (this) {
      case KittenTtsVoice.bella:
        return 'Bella';
      case KittenTtsVoice.jasper:
        return 'Jasper';
      case KittenTtsVoice.luna:
        return 'Luna';
      case KittenTtsVoice.bruno:
        return 'Bruno';
      case KittenTtsVoice.rosie:
        return 'Rosie';
      case KittenTtsVoice.hugo:
        return 'Hugo';
      case KittenTtsVoice.kiki:
        return 'Kiki';
      case KittenTtsVoice.leo:
        return 'Leo';
    }
  }
}

enum OnDeviceModelState {
  notDownloaded,
  downloading,
  downloaded,
  loading,
  loaded,
  error,
}
