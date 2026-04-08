

enum ServerType { lmStudio, openAICompatible, ollama, openRouter }

enum ConnectionStatus { connected, disconnected, checking, error }

enum MessageRole { user, assistant, system, tool }

enum MessageStatus { sending, streaming, complete, error }

enum ModelStatus { unloaded, loading, loaded, preloaded, thinking }
