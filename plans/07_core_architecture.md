# Feature 07 — Core Architecture (Models, Services, Storage, Providers)

> **Phase:** 0–1  
> **Status:** Pending  
> **Depends on:** None (foundational)  
> **Replaces:** Original `core/` structure

---

## Goal

Define the core data models, service interfaces, storage layer, and global providers that all features depend on. This is the application's backbone.

---

## Overview

This document details the `core/` layer — code that is shared across multiple features. Each feature's internal structure is defined in its respective plan file.

### Core Folder Structure

```
core/
├── constants/
│   └── app_constants.dart              # App-wide constants
├── models/
│   ├── server.dart                    # Server model + enums
│   ├── message.dart                   # Message model + enums
│   ├── conversation.dart              # Conversation model
│   ├── persona.dart                   # Persona model
│   ├── model_info.dart                # LLM model metadata
│   ├── chat_parameters.dart           # Chat parameter config
│   └── app_settings.dart              # Settings model
├── providers/
│   └── app_providers.dart             # Global Riverpod providers
├── repository/
│   ├── storage/
│   │   ├── hive_initializer.dart
│   │   ├── hive_keys.dart
│   │   └── hive_boxes.dart
│   ├── server/
│   │   └── server_repository.dart
│   └── chat/
│       ├── chat_service.dart
│       ├── lm_studio_chat_service.dart
│       ├── ollama_chat_service.dart
│       └── openrouter_chat_service.dart
├── routes/
│   └── app_router.dart
├── theme/
│   ├── app_theme.dart
│   ├── colors.dart
│   └── typography.dart
├── components/
│   ├── app_button.dart
│   ├── app_card.dart
│   └── app_text_field.dart
└── utils/
    ├── uuid.dart
    └── date_utils.dart
```

---

## Hive Type IDs

| Type ID | Model           |
| ------- | --------------- |
| 0       | Server          |
| 1       | Message         |
| 2       | Conversation    |
| 3       | Persona         |
| 4       | AppSettings     |
| 10      | ServerType      |
| 11      | ConnectionStatus|
| 12      | MessageRole     |
| 13      | MessageStatus   |

---

## Models — Full Specifications

### `core/models/server.dart`

```dart
@HiveType(typeId: 10)
enum ServerType { lmStudio, ollama, openRouter }

@HiveType(typeId: 11)
enum ConnectionStatus { connected, disconnected, checking, error }

@HiveType(typeId: 0)
class Server extends HiveObject {
  @HiveField(0)
  String id;              // UUID

  @HiveField(1)
  String name;            // User-defined label

  @HiveField(2)
  ServerType type;

  @HiveField(3)
  String host;            // IP address or hostname

  @HiveField(4)
  int port;               // Port number

  @HiveField(5)
  String? apiKey;         // Required for OpenRouter

  @HiveField(6)
  bool isDefault;

  @HiveField(7)
  DateTime createdAt;

  @HiveField(8)
  DateTime lastConnectedAt;

  @HiveField(9)
  ConnectionStatus status;

  String get baseUrl {
    if (type == ServerType.openRouter) return 'https://openrouter.ai/api/v1';
    return 'http://$host:$port';
  }

  String get chatEndpoint {
    switch (type) {
      case ServerType.lmStudio: return '$baseUrl/v1/chat/completions';
      case ServerType.ollama: return '$baseUrl/api/chat';
      case ServerType.openRouter: return '$baseUrl/chat/completions';
    }
  }

  String get modelsEndpoint {
    switch (type) {
      case ServerType.lmStudio: return '$baseUrl/v1/models';
      case ServerType.ollama: return '$baseUrl/api/tags';
      case ServerType.openRouter: return '$baseUrl/models';
    }
  }

  // ... fromMap(), toMap(), copyWith()
}
```

### `core/models/message.dart`

```dart
@HiveType(typeId: 12)
enum MessageRole { user, assistant, system }

@HiveType(typeId: 13)
enum MessageStatus { sending, streaming, complete, error }

@HiveType(typeId: 1)
class Message extends HiveObject {
  @HiveField(0)
  String id;                // UUID

  @HiveField(1)
  String conversationId;    // FK to Conversation

  @HiveField(2)
  MessageRole role;

  @HiveField(3)
  String content;           // Message text (markdown)

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  MessageStatus status;

  @HiveField(6)
  String? modelId;          // Which model generated this

  @HiveField(7)
  int? tokenCount;

  @HiveField(8)
  String? errorMessage;

  @HiveField(9)
  List<String>? attachmentPaths;

  @HiveField(10)
  int? generationTimeMs;

  // ... fromMap(), toMap(), copyWith()
}
```

### `core/models/conversation.dart`

```dart
@HiveType(typeId: 2)
class Conversation extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  DateTime createdAt;

  @HiveField(3)
  DateTime updatedAt;

  @HiveField(4)
  bool isPinned;

  @HiveField(5)
  String? personaId;

  @HiveField(6)
  String? serverId;

  @HiveField(7)
  String? modelId;

  @HiveField(8)
  int messageCount;

  @HiveField(9)
  String? lastMessagePreview;

  @HiveField(10)
  String? systemPrompt;

  // ... fromMap(), toMap(), copyWith()
}
```

### `core/models/persona.dart`

```dart
@HiveType(typeId: 3)
class Persona extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String emoji;

  @HiveField(3)
  String systemPrompt;

  @HiveField(4)
  String? description;

  @HiveField(5)
  bool isBuiltIn;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  DateTime updatedAt;

  @HiveField(8)
  String? category;

  @HiveField(9)
  Map<String, dynamic>? preferredParams;

  // ... fromMap(), toMap(), copyWith()
}
```

### `core/models/app_settings.dart`

```dart
@HiveType(typeId: 4)
class AppSettings extends HiveObject {
  @HiveField(0)
  double temperature;

  @HiveField(1)
  double topP;

  @HiveField(2)
  int maxTokens;

  @HiveField(3)
  int contextLength;

  @HiveField(4)
  ThemeMode themeMode;

  @HiveField(5)
  double fontSize;

  @HiveField(6)
  bool showSystemMessages;

  @HiveField(7)
  bool hapticFeedbackEnabled;

  @HiveField(8)
  bool sendOnEnter;

  @HiveField(9)
  String? defaultServerId;

  @HiveField(10)
  bool showDataIndicator;

  @HiveField(11)
  bool autoGenerateTitle;

  @HiveField(12)
  bool streamingEnabled;

  @HiveField(13)
  String? defaultPersonaId;

  // ... fromMap(), toMap(), copyWith()
}
```

### `core/models/model_info.dart` (Non-Hive)

```dart
class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final int? parameterCount;
  final int? contextLength;
  final int? fileSize;
  final String? quantization;
  final String? architecture;
  final ServerType serverType;
  final String serverId;
  final DateTime? modifiedAt;

  // ... fromMap(), toMap(), copyWith()
}
```

### `core/models/chat_parameters.dart` (Non-Hive)

```dart
class ChatParameters {
  final double temperature;
  final double topP;
  final int maxTokens;
  final int contextLength;

  factory ChatParameters.defaults() => ChatParameters(
    temperature: 0.7,
    topP: 0.9,
    maxTokens: 2048,
    contextLength: 4096,
  );

  // ... copyWith()
}
```

---

## Repository Layer

### `core/repository/storage/hive_keys.dart`

```dart
class HiveKeys {
  static const String servers = 'servers';
  static const String messages = 'messages';
  static const String conversations = 'conversations';
  static const String personas = 'personas';
  static const String settings = 'settings';
}
```

### `core/repository/storage/hive_boxes.dart`

```dart
class HiveBoxes {
  final Box<Server> servers;
  final Box<Message> messages;
  final Box<Conversation> conversations;
  final Box<Persona> personas;
  final Box<AppSettings> settings;

  const HiveBoxes({
    required this.servers,
    required this.messages,
    required this.conversations,
    required this.personas,
    required this.settings,
  });
}
```

### `core/repository/storage/hive_initializer.dart`

```dart
class HiveInitializer {
  static Future<HiveBoxes> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDir.path);

    // Register ALL adapters
    Hive.registerAdapter(ServerAdapter());
    Hive.registerAdapter(ServerTypeAdapter());
    Hive.registerAdapter(ConnectionStatusAdapter());
    Hive.registerAdapter(MessageAdapter());
    Hive.registerAdapter(MessageRoleAdapter());
    Hive.registerAdapter(MessageStatusAdapter());
    Hive.registerAdapter(ConversationAdapter());
    Hive.registerAdapter(PersonaAdapter());
    Hive.registerAdapter(AppSettingsAdapter());

    final servers = await Hive.openBox<Server>(HiveKeys.servers);
    final messages = await Hive.openBox<Message>(HiveKeys.messages);
    final conversations = await Hive.openBox<Conversation>(HiveKeys.conversations);
    final personas = await Hive.openBox<Persona>(HiveKeys.personas);
    final settings = await Hive.openBox<AppSettings>(HiveKeys.settings);

    return HiveBoxes(
      servers: servers,
      messages: messages,
      conversations: conversations,
      personas: personas,
      settings: settings,
    );
  }
}
```

---

## Services

### `core/repository/chat/chat_service.dart`

```dart
abstract class ChatService {
  Stream<String> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  });

  void cancelStream();

  static ChatService forServer(ServerType type, Dio dio) {
    switch (type) {
      case ServerType.lmStudio: return LMStudioChatService(dio);
      case ServerType.ollama: return OllamaChatService(dio);
      case ServerType.openRouter: return OpenRouterChatService(dio);
    }
  }
}
```

**Implementations:**
- `lm_studio_chat_service.dart` — OpenAI-compatible SSE streaming
- `ollama_chat_service.dart` — NDJSON streaming
- `openrouter_chat_service.dart` — OpenAI-compatible SSE with API key auth

### `core/repository/server/server_repository.dart`

```dart
class ServerRepository {
  final Dio _dio;

  Future<bool> testConnection(Server server);
  Future<List<ModelInfo>> fetchModels(Server server);
  Future<int?> pingServer(Server server);
}
```

---

## Providers

### `core/providers/app_providers.dart`

```dart
// Hive boxes (initialized in main.dart)
final hiveBoxesProvider = Provider<HiveBoxes>((ref) {
  throw UnimplementedError('Must be overridden with actual HiveBoxes');
});

// Dio HTTP client
final dioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: Duration(milliseconds: AppConstants.connectionTimeoutMs),
    receiveTimeout: Duration(milliseconds: AppConstants.receiveTimeoutMs),
  ));
});

// Theme
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

// Active Server
final activeServerProvider = StateNotifierProvider<ActiveServerNotifier, Server?>((ref) {
  return ActiveServerNotifier();
});

// Active Conversation
final activeConversationProvider = StateNotifierProvider<ActiveConversationNotifier, Conversation?>((ref) {
  return ActiveConversationNotifier();
});
```

---

## Utilities

### `core/utils/uuid.dart`

```dart
String generateUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return [
    bytes.sublist(0, 4), bytes.sublist(4, 6),
    bytes.sublist(6, 8), bytes.sublist(8, 10),
    bytes.sublist(10, 16),
  ].map((b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join())
   .join('-');
}
```

---

## Error Handling Strategy

```dart
class AppException implements Exception {
  final String message;
  final String? technicalDetail;
  final AppErrorType type;
}

enum AppErrorType {
  connectionRefused,
  timeout,
  unauthorized,
  serverError,
  modelNotFound,
  contextOverflow,
  streamInterrupted,
  rateLimited,
  unknown,
}
```

Each `AppErrorType` maps to a user-friendly message (see `02_chat_interface.md` error table).

---

## Acceptance Criteria

- [ ] All Hive models compile and their adapters are generated.
- [ ] `HiveInitializer` successfully opens all boxes on app launch.
- [ ] `ChatService` correctly routes to the right implementation per server type.
- [ ] `ServerRepository` can test connections and fetch models.
- [ ] All providers are defined and accessible.
- [ ] `AppException` provides user-friendly error messages.
- [ ] UUID generation produces valid unique IDs.
