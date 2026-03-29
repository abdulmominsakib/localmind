# Feature 01 — Server Connection & Management

> **Phase:** 1 — Core  
> **Status:** Pending  
> **Depends on:** `00_project_setup`, `07_core_architecture`  

---

## Goal

Allow users to configure and manage connections to local LLM servers (LM Studio, Ollama) and cloud providers (OpenRouter). This is the foundational feature — no chat works without a connected server.

---

## Feature Folder Structure

```
features/server_connection/
├── data/
│   └── models/                      # (Uses core/models/server.dart)
│
├── providers/
│   └── server_connection_providers.dart
│
└── views/
    ├── server_list_page.dart         # Main page
    ├── add_server_page.dart          # Add/Edit server
    └── components/
        ├── server_card.dart
        ├── connection_status_indicator.dart
        └── server_type_selector.dart
```

---

## Dependencies Used

| Package | Purpose                                              |
| ------- | ---------------------------------------------------- |
| `dio`   | HTTP client for REST API calls and connection testing |
| `hive_ce` | Persist server profiles locally                     |
| `flutter_riverpod` | State management for server list & active server |

---

## Data Model

The `Server` model and enums (`ServerType`, `ConnectionStatus`) are defined in `core/models/server.dart`.

---

## API Service

`ServerRepository` is defined in `core/repository/server/server_repository.dart`.

```dart
class ServerRepository {
  final Dio _dio;

  Future<bool> testConnection(Server server);
  Future<List<ModelInfo>> fetchModels(Server server);
  Future<int?> pingServer(Server server);
}
```

**LM Studio specifics:**
- Models: `GET /v1/models` → OpenAI-compatible model list
- Health: `GET /v1/models` returning 200 = healthy

**Ollama specifics:**
- Models: `GET /api/tags` → `{ models: [...] }`
- Health: `GET /api/tags` returning 200 = healthy

**OpenRouter specifics:**
- Models: `GET /models` with `Authorization: Bearer {apiKey}`
- Health: `GET /models` returning 200 = healthy

---

## Providers

Location: `features/server_connection/providers/server_connection_providers.dart`

### Provider Organization

```dart
// 1. Repository Provider
final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  return ServerRepository(ref.read(dioProvider));
});

// 2. All saved servers
final serversProvider = StateNotifierProvider<ServersNotifier, List<Server>>((ref) {
  final repository = ref.watch(serverRepositoryProvider);
  return ServersNotifier(repository, ref.read(hiveBoxesProvider).servers);
});

// 3. Active server
final activeServerProvider = StateNotifierProvider<ActiveServerNotifier, Server?>((ref) {
  return ActiveServerNotifier(ref.read(hiveBoxesProvider).settings);
});

// 4. Connection status for a specific server
final connectionStatusProvider = FutureProvider.family<ConnectionStatus, String>((ref, serverId) async {
  final server = ref.read(serversProvider).firstWhere((s) => s.id == serverId);
  final repo = ref.read(serverRepositoryProvider);
  final isConnected = await repo.testConnection(server);
  return isConnected ? ConnectionStatus.connected : ConnectionStatus.disconnected;
});
```

### `ServersNotifier` StateNotifier

```dart
class ServersNotifier extends StateNotifier<List<Server>> {
  final ServerRepository _repository;
  final Box<Server> _box;

  ServersNotifier(this._repository, this._box) : super([]) {
    loadServers();
  }

  void loadServers() {
    state = _box.values.toList();
  }

  Future<void> addServer(Server server) async { ... }
  Future<void> updateServer(Server server) async { ... }
  Future<void> deleteServer(String serverId) async { ... }
  Future<void> setDefault(String serverId) async { ... }
  Future<ConnectionStatus> testConnection(String serverId) async { ... }
}
```

### `ActiveServerNotifier` StateNotifier

```dart
class ActiveServerNotifier extends StateNotifier<Server?> {
  final Box<AppSettings> _settingsBox;

  ActiveServerNotifier(this._settingsBox) : super(null) {
    _loadActiveServer();
  }

  void _loadActiveServer() { ... }
  Future<void> setActiveServer(String? serverId) async { ... }
}
```

---

## Views

### `server_list_page.dart`

**Layout:**
- App bar with title "Servers" and "+" add button
- List of server cards showing:
  - Server name (bold)
  - Server type icon (LM Studio / Ollama / OpenRouter)
  - Host:Port or "Cloud" for OpenRouter
  - Connection status indicator
  - "Default" badge if marked as default
- Empty state: illustration + "Add your first server" CTA
- Pull-to-refresh to re-test all connections

**Interactions:**
- Tap card → navigate to edit server
- Long-press → context menu (Edit, Delete, Set Default, Test Connection)
- Swipe left → delete with confirmation

### `add_server_page.dart`

**Layout:**
- Server type selector (3 segmented buttons: LM Studio, Ollama, OpenRouter)
- Form fields that change based on type:

**For LM Studio / Ollama:**
| Field       | Type        | Validation                    |
| ----------- | ----------- | ----------------------------- |
| Name        | Text        | Required, 1–50 chars          |
| Host/IP     | Text        | Required, valid IP or hostname|
| Port        | Number      | Required, 1–65535             |
| API Key     | Text (opt)  | Optional                      |

**For OpenRouter:**
| Field       | Type        | Validation                    |
| ----------- | ----------- | ----------------------------- |
| Name        | Text        | Required, 1–50 chars          |
| API Key     | Text        | Required, starts with `sk-`   |

- "Test Connection" button → shows result toast
- "Save" button → validates, tests connection, saves to Hive
- Auto-fill defaults: LM Studio port = 1234, Ollama port = 11434

**Error handling:**
- Connection refused → "Cannot reach server. Is it running?"
- Timeout → "Server took too long to respond. Check the address."
- 401 → "Invalid API key."
- Generic → show raw error message

---

## Components

### `server_card.dart`

A card showing:
- Leading: Server type icon
- Title: Server name
- Subtitle: `host:port` or `openrouter.ai`
- Trailing: `ConnectionStatusIndicator` + chevron
- Default badge (if applicable)

### `connection_status_indicator.dart`

Animated dot:
- Green (pulsing) = Connected
- Red (static) = Error
- Grey = Not checked
- Loading spinner = Checking

### `server_type_selector.dart`

Three-segment toggle:
- LM Studio (terminal icon)
- Ollama (llama emoji)
- OpenRouter (cloud icon)

---

## Background Connection Monitoring

- When app is in foreground, periodically ping the active server every 30 seconds.
- Update `connectionStatusProvider` accordingly.
- Show a subtle banner at top of chat if connection is lost.

---

## Acceptance Criteria

- [ ] User can add an LM Studio server with IP + port and test connection.
- [ ] User can add an Ollama server with IP + port and test connection.
- [ ] User can add an OpenRouter server with API key and test connection.
- [ ] Server list displays all saved servers with connection status.
- [ ] User can edit and delete servers.
- [ ] User can set a default server.
- [ ] Connection status auto-updates with visual indicator.
- [ ] Server profiles persist across app restarts (Hive).
- [ ] Connection errors show meaningful error messages.
- [ ] Empty state is handled gracefully.
