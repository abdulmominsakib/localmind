# Feature 00 — Project Setup & Scaffolding

> **Phase:** 0 — Setup  
> **Status:** Pending  
> **Est. Time:** 1 week  

---

## Goal

Transform the default Flutter counter app into a production-ready project shell with:
- Feature-based folder structure
- ShadCN UI theme integration
- Riverpod provider scope
- Hive CE local storage initialization
- App-wide routing (GoRouter)
- Base app shell (navigation scaffold)

---

## Dependencies Used

| Package              | Purpose                          |
| -------------------- | -------------------------------- |
| `flutter_riverpod`   | State management (ProviderScope) |
| `hive_ce`            | Local encrypted storage          |
| `hive_ce_flutter`    | Hive Flutter initialization      |
| `shadcn_ui`          | Component library & theming      |
| `path_provider`      | App directory paths              |
| `go_router`          | Declarative routing             |

---

## Folder Structure

Create the full directory skeleton under `lib/`:

```
lib/
├── main.dart                  # Entry point — init Hive, wrap with ProviderScope
├── app.dart                   # MaterialApp / ShadCN App root with routing
│
├── core/                      # SHARED, CROSS-CUTTING CONCERNS
│   ├── constants/
│   │   └── app_constants.dart
│   ├── models/
│   │   ├── server.dart
│   │   ├── message.dart
│   │   ├── conversation.dart
│   │   ├── persona.dart
│   │   ├── model_info.dart
│   │   ├── chat_parameters.dart
│   │   └── app_settings.dart
│   ├── providers/
│   │   └── app_providers.dart
│   ├── repository/
│   │   └── storage/
│   │       ├── hive_initializer.dart
│   │       ├── hive_keys.dart
│   │       └── hive_boxes.dart
│   ├── routes/
│   │   └── app_router.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   ├── colors.dart
│   │   └── typography.dart
│   ├── components/
│   │   ├── app_button.dart
│   │   ├── app_card.dart
│   │   └── app_text_field.dart
│   └── utils/
│       └── uuid.dart
│
├── features/                  # FEATURE MODULES (vertical slices)
│   ├── server_connection/
│   │   ├── data/
│   │   │   └── models/
│   │   ├── providers/
│   │   │   └── server_connection_providers.dart
│   │   └── views/
│   │       ├── server_list_page.dart
│   │       ├── add_server_page.dart
│   │       └── components/
│   │           ├── server_card.dart
│   │           ├── connection_status_indicator.dart
│   │           └── server_type_selector.dart
│   │
│   ├── chat/
│   │   ├── data/
│   │   │   └── models/
│   │   ├── providers/
│   │   │   └── chat_providers.dart
│   │   └── views/
│   │       ├── chat_page.dart
│   │       └── components/
│   │           ├── chat_bubble.dart
│   │           ├── chat_input_bar.dart
│   │           ├── typing_indicator.dart
│   │           ├── message_action_bar.dart
│   │           └── code_block.dart
│   │
│   ├── model_management/
│   │   ├── data/
│   │   │   └── models/
│   │   ├── providers/
│   │   │   └── model_management_providers.dart
│   │   └── views/
│   │       ├── model_picker_sheet.dart
│   │       └── components/
│   │           ├── model_tile.dart
│   │           └── model_metadata_chip.dart
│   │
│   ├── conversation/
│   │   ├── data/
│   │   │   └── models/
│   │   ├── providers/
│   │   │   └── conversation_providers.dart
│   │   └── views/
│   │       ├── conversation_drawer.dart
│   │       └── components/
│   │           ├── conversation_tile.dart
│   │           ├── conversation_search_bar.dart
│   │           └── date_section_header.dart
│   │
│   ├── persona/
│   │   ├── data/
│   │   │   └── models/
│   │   ├── providers/
│   │   │   └── persona_providers.dart
│   │   └── views/
│   │       ├── persona_list_page.dart
│   │       ├── create_persona_page.dart
│   │       └── components/
│   │           ├── persona_card.dart
│   │           └── persona_category_chips.dart
│   │
│   └── settings/
│       ├── data/
│       │   └── models/
│       ├── providers/
│       │   └── settings_providers.dart
│       └── views/
│           ├── settings_page.dart
│           └── components/
│               ├── settings_section.dart
│               ├── settings_slider.dart
│               ├── settings_toggle.dart
│               ├── settings_dropdown.dart
│               ├── theme_toggle.dart
│               └── font_size_preview.dart
```

---

## Implementation Tasks

### 1. `main.dart` — Entry Point

**Responsibilities:**
1. Initialize Hive CE with encryption
2. Open required Hive boxes (servers, conversations, personas, settings, messages)
3. Wrap app with `ProviderScope` (Riverpod)
4. Launch `App` widget from `app.dart`

**Implementation details:**

- Call `WidgetsFlutterBinding.ensureInitialized()` before any async work.
- Initialize Hive via `HiveFlutter.init()` using `path_provider`'s app documents directory.
- Generate or retrieve an encryption key stored in device secure storage (for encrypted Hive boxes).
- Register all Hive type adapters for custom data models.
- Open boxes: `serversBox`, `conversationsBox`, `personasBox`, `settingsBox`, `messagesBox`.
- Wrap the `App()` widget with `ProviderScope()`.

### 2. `app.dart` — App Root

**Responsibilities:**
1. Configure ShadCN theme (dark-first, with light mode support)
2. Set up GoRouter routing
3. Define the app shell (drawer-based navigation)

**Routes to define:**

| Route                  | Screen                    |
| ---------------------- | ------------------------- |
| `/`                    | ChatPage (home)           |
| `/conversations`       | ConversationDrawer         |
| `/servers`             | ServerListPage            |
| `/servers/add`         | AddServerPage             |
| `/servers/edit/:id`    | AddServerPage (edit mode) |
| `/models`              | ModelPickerSheet          |
| `/personas`            | PersonaListPage           |
| `/personas/create`     | CreatePersonaPage         |
| `/personas/edit/:id`   | CreatePersonaPage (edit)  |
| `/settings`            | SettingsPage              |

**Navigation approach:**
- Use a **drawer / sidebar** for conversation list (like ChatGPT).
- Primary view is always the Chat screen.
- Settings, servers, personas accessible from drawer or app bar actions.

### 3. ShadCN Theme Setup

Create `core/theme/colors.dart`:

```dart
class AppColors {
  // --- Dark Theme (Default) ---
  static const Color darkBackground = Color(0xFF0A0A0A);
  static const Color darkSurface = Color(0xFF171717);
  static const Color darkBorder = Color(0xFF262626);
  static const Color darkPrimaryText = Color(0xFFFAFAFA);
  static const Color darkMutedText = Color(0xFFA1A1AA);
  static const Color darkAccent = Color(0xFF3B82F6);

  // --- Light Theme ---
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE5E5E5);
  static const Color lightPrimaryText = Color(0xFF0A0A0A);
  static const Color lightMutedText = Color(0xFF71717A);
  static const Color lightAccent = Color(0xFF2563EB);
}
```

Create `core/theme/app_theme.dart`:
- **Dark theme (primary):** Background `#0A0A0A`, Surface `#171717`, Border `#262626`, Primary `#FAFAFA`, Muted `#A1A1AA`, Accent blue.
- **Light theme (secondary):** Background `#FAFAFA`, Surface `#FFFFFF`, Border `#E5E5E5`, Primary `#0A0A0A`, Muted `#71717A`.
- **Typography:** Use `Inter` font family.
- **Corner radius:** Default `8px` for cards/buttons, `12px` for sheets/dialogs.
- **Transitions:** Default 200ms ease-in-out.

### 4. Riverpod Provider Structure

Create `core/providers/app_providers.dart`:

```dart
// Theme provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

// Current active server
final activeServerProvider = StateNotifierProvider<ActiveServerNotifier, Server?>((ref) {
  return ActiveServerNotifier();
});

// Current active conversation
final activeConversationProvider = StateNotifierProvider<ActiveConversationNotifier, Conversation?>((ref) {
  return ActiveConversationNotifier();
});

// Hive boxes (initialized in main.dart, overridden here)
final hiveBoxesProvider = Provider<HiveBoxes>((ref) {
  throw UnimplementedError('Must be overridden with actual HiveBoxes');
});
```

### 5. Hive Storage Initialization

Create `core/repository/storage/hive_keys.dart`:

```dart
class HiveKeys {
  static const String servers = 'servers';
  static const String messages = 'messages';
  static const String conversations = 'conversations';
  static const String personas = 'personas';
  static const String settings = 'settings';
}
```

Create `core/repository/storage/hive_boxes.dart`:

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

Create `core/repository/storage/hive_initializer.dart`:

```dart
class HiveInitializer {
  static Future<HiveBoxes> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDir.path);

    // Register adapters (Server, Message, Conversation, Persona, AppSettings)
    // ...

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

### 6. App Constants

Create `core/constants/app_constants.dart`:

```dart
class AppConstants {
  static const String appName = 'LocalMind';
  static const String appTagline = 'Your AI. Your Device. Your Rules.';
  static const String version = '1.0.0';

  // Default chat parameters
  static const double defaultTemperature = 0.7;
  static const double defaultTopP = 0.9;
  static const int defaultMaxTokens = 2048;
  static const int defaultContextLength = 4096;

  // API defaults
  static const int connectionTimeoutMs = 5000;
  static const int receiveTimeoutMs = 60000;
}
```

### 7. GoRouter Setup

Create `core/routes/app_router.dart`:

```dart
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ChatPage(),
      routes: [
        GoRoute(path: 'servers', builder: (context, state) => const ServerListPage()),
        GoRoute(path: 'servers/add', builder: (context, state) => const AddServerPage()),
        GoRoute(path: 'personas', builder: (context, state) => const PersonaListPage()),
        GoRoute(path: 'personas/create', builder: (context, state) => const CreatePersonaPage()),
        GoRoute(path: 'settings', builder: (context, state) => const SettingsPage()),
      ],
    ),
  ],
);
```

---

## Core Models (Stubs)

Create stub model files in `core/models/` with minimal implementations. Full implementations come in Feature 07.

**Models to create (stubs):**
- `server.dart` — ServerType enum, ConnectionStatus enum, Server class
- `message.dart` — MessageRole enum, MessageStatus enum, Message class
- `conversation.dart` — Conversation class
- `persona.dart` — Persona class
- `model_info.dart` — ModelInfo class
- `chat_parameters.dart` — ChatParameters class
- `app_settings.dart` — AppSettings class

Each stub should have:
- All required fields
- `fromMap()` / `toMap()` methods
- `copyWith()` method
- Hive annotations (`@HiveType`, `@HiveField`)

---

## Core Components (Stubs)

Create stub reusable components in `core/components/`:

- `app_button.dart` — PrimaryButton, OutlineButton variants
- `app_card.dart` — Card with standard styling
- `app_text_field.dart` — Standard text input

These get fully implemented in Feature 08 (Design System).

---

## Acceptance Criteria

- [ ] `flutter run` launches the app with ShadCN dark theme (no counter app).
- [ ] App shell shows a chat screen placeholder with a working drawer/sidebar.
- [ ] Hive initializes without errors and boxes are accessible.
- [ ] Riverpod `ProviderScope` wraps the entire app.
- [ ] All feature folders exist with placeholder files.
- [ ] Routing works — navigating to `/settings` shows a settings placeholder.
- [ ] Both dark and light themes render correctly when toggled.

---

## Notes

- Do NOT implement any feature logic in this phase. Only scaffolding.
- The ShadCN theme should be the single source of truth for all colors/typography.
- Prefer `ConsumerWidget` / `ConsumerStatefulWidget` for all screens from the start.
- Feature imports are **forbidden** — features must not import from other features.
