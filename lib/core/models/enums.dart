enum ServerType { lmStudio, openAICompatible, ollama, openRouter, onDevice }

enum ConnectionStatus { connected, disconnected, checking, error }

enum MessageRole { user, assistant, system, tool }

enum MessageStatus { sending, streaming, complete, error }

enum ModelStatus { unloaded, loading, loaded, preloaded, thinking }

enum EngineStatus { notLoaded, loading, loaded, error }

enum LiteLmBackendType { cpu, gpu, npu }

enum OnDeviceModelState {
  notDownloaded,
  downloading,
  downloaded,
  loading,
  loaded,
  error,
}
