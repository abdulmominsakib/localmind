# LocalMind — Project Plan

## App Name: **LocalMind**

**Tagline:** _Your AI. Your Device. Your Rules._

The name "LocalMind" communicates two things immediately:

- **Local** — runs on your network, no cloud, no tracking, no subscriptions
- **Mind** — intelligent, conversational, thoughtful

It's short, memorable, and instantly signals privacy-first, offline-capable AI.

---

## Vision

LocalMind is a premium Flutter mobile app that acts as a beautiful, fast, and privacy-respecting interface for local LLM servers (LM Studio, Ollama) and optional cloud providers (OpenRouter). Inspired by the polish of ChatGPT and Claude's UI, but built for power users who want full control over their AI stack.

---

## Tech Stack

| Layer              | Technology                                                           |
| ------------------ | -------------------------------------------------------------------- |
| Framework          | Flutter (latest stable)                                              |
| UI Components      | shadcn-inspired Flutter package (`flutter_shadcn_ui` or custom port) |
| State Management   | Riverpod                                                             |
| Local Storage      | Hive CE Edition                                                      |
| Networking         | Dio (HTTP client for LM Studio / Ollama REST APIs)                   |
| Markdown Rendering | `flutter_markdown`                                                   |
| Code Highlighting  | `flutter_highlight`                                                  |
| TTS                | `flutter_tts`                                                        |
| File Handling      | `file_picker` + `path_provider`                                      |
| Platform           | Android first, iOS later                                             |

---

## Architecture: Feature-Based with Riverpod

This project follows the **Feature-Based Architecture** where code is organized by feature (vertical slices) rather than by technical layer. Shared, cross-cutting concerns live in a `core/` directory. State management is handled exclusively with **Riverpod**.

### Core Principles

- **Feature Isolation:** Each feature owns its data, providers, and views. Features must **never** import from other features. If two features need the same code, move it to `core/`.
- **Riverpod-First State Management:** All state is managed via Riverpod providers. No `ChangeNotifier`, `Bloc`, or raw `setState` for business logic.
- **Core for Shared Code:** Anything used by 2+ features belongs in `core/`. This includes shared models, repositories, providers, components, constants, utilities, and infrastructure.
- **Unidirectional Data Flow:** Data flows from Repository → Provider/StateNotifier → View. User events flow from View → Provider/StateNotifier → Repository.
- **Single Source of Truth (SSOT):** Each piece of data has exactly one authoritative source — the Repository. Providers expose that data reactively to the UI.

---

## Project Structure

```
lib/
├── main.dart                           # Entry point
├── app.dart                            # App root (MaterialApp / ShadCN App)
│
├── core/                               # Shared, cross-cutting concerns (GLOBAL)
│   ├── constants/                      # App-wide constants (colors, URLs, config)
│   │   └── app_constants.dart
│   ├── models/                        # Shared domain models
│   │   ├── server.dart                # Server model + enums (ServerType, ConnectionStatus)
│   │   ├── message.dart               # Message model + enums (MessageRole, MessageStatus)
│   │   ├── conversation.dart          # Conversation model
│   │   ├── persona.dart               # Persona model
│   │   ├── model_info.dart            # LLM model metadata
│   │   ├── chat_parameters.dart       # Chat parameter config
│   │   └── app_settings.dart          # App settings model
│   ├── providers/                    # Shared Riverpod providers
│   │   └── app_providers.dart         # Theme, active server, active conversation
│   ├── repository/                    # Shared repositories & services
│   │   ├── storage/                   # Hive storage (init, adapters, box references)
│   │   │   ├── hive_initializer.dart
│   │   │   ├── hive_keys.dart
│   │   │   └── hive_boxes.dart
│   │   ├── server/                    # Server API service
│   │   │   └── server_repository.dart
│   │   └── chat/                      # Chat service + implementations
│   │       ├── chat_service.dart
│   │       ├── lm_studio_chat_service.dart
│   │       ├── ollama_chat_service.dart
│   │       └── openrouter_chat_service.dart
│   ├── routes/                        # App routing (GoRouter config)
│   │   └── app_router.dart
│   ├── theme/                         # App theme data
│   │   ├── app_theme.dart
│   │   ├── colors.dart
│   │   └── typography.dart
│   ├── components/                    # Reusable UI widgets (shared across features)
│   │   ├── app_button.dart
│   │   ├── app_card.dart
│   │   ├── app_text_field.dart
│   │   └── ...
│   └── utils/                         # General-purpose utilities
│       ├── uuid.dart
│       └── date_utils.dart
│
├── features/                           # Feature modules (vertical slices)
│   ├── server_connection/             # Server setup & management
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
│   ├── chat/                          # Chat interface
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
│   ├── model_management/              # Model browsing & selection
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
│   ├── conversation/                  # Conversation history management
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
│   ├── persona/                       # Templates & personas
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
│   └── settings/                     # App settings
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
│               ├── theme_toggle.dart
│               └── font_size_preview.dart
│
└── loc/                               # Localization (optional, future)
```

---

## Core (Global) Layer

The `core/` directory holds code that is **shared across multiple features**. The rule is simple: _if it's used by 2+ features, it belongs in `core/`_.

### `core/constants/`

App-wide constant values.

| What to put here | Example |
|-----------------|---------|
| Color constants | `AppColors` with static `Color` fields |
| URL constants | `AppUrls` with static URL strings (API base, privacy policy) |
| Size/spacing constants | `AppSizes` with static doubles for padding, radius |
| Config values | API timeouts, pagination limits |

### `core/models/`

Domain models shared across features. All Hive models live here:
- `Server` — server connection profiles
- `Message` — chat messages
- `Conversation` — conversation threads
- `Persona` — AI personas
- `ModelInfo` — LLM model metadata
- `ChatParameters` — chat configuration
- `AppSettings` — app preferences

### `core/providers/`

Riverpod providers consumed by multiple features:
- `themeProvider` — current theme mode
- `activeServerProvider` — currently selected server
- `activeConversationProvider` — currently active conversation
- `hiveBoxesProvider` — opened Hive boxes

### `core/repository/`

Repositories and services for shared data domains:

```
core/repository/
├── storage/              # Hive initialization, adapters, box access
├── server/              # ServerApiService (connection testing, model fetching)
└── chat/                # ChatService + implementations (LM Studio, Ollama, OpenRouter)
```

### `core/routes/`

App-level routing and navigation configuration (GoRouter setup, route constants).

### `core/theme/`

App theme data — `ThemeData`, text styles, component themes. Color definitions reference `core/constants/`.

### `core/components/`

Reusable UI widgets consumed by multiple features. These are **presentational** widgets that receive data via constructor params — no business logic.

### `core/utils/`

General-purpose utility classes and functions (UUID generation, date formatters, etc.).

---

## Feature Layer

Each feature directory follows a **consistent internal structure**:

```
features/<feature_name>/
├── data/                    # Data layer
│   └── models/              # Feature-specific models (if any, beyond core models)
│
├── providers/               # State management
│   └── <feature>_providers.dart   # All Riverpod providers for this feature
│
└── views/                   # UI layer
    ├── <feature>_page.dart         # Main page widget(s)
    ├── add_<feature>_page.dart     # Create/edit page (if applicable)
    └── components/                 # Feature-specific UI components
        └── <component>.dart
```

### Rules

1. **Never import from another feature.** If feature A needs something from feature B, extract it to `core/`.
2. **Keep views lean.** Views (`ConsumerWidget` / `ConsumerStatefulWidget`) should only handle UI concerns — layout, animations, navigation. All business logic lives in providers.
3. **One provider file per feature** is the default. Split only when the file exceeds ~400 lines.
4. **Models must have serialization.** Every model needs `fromMap()` / `fromJson()` and `toMap()` / `toJson()` along with `copyWith()`.

---

## State Management with Riverpod

### Provider Types Used

| Provider Type | When to Use | Example |
|---------------|-------------|---------|
| `Provider` | Expose a stateless repository or service instance | `final repoProvider = Provider<Repo>((ref) => Repo());` |
| `StateProvider` | Simple mutable state (filters, toggles, search query) | `final searchProvider = StateProvider<String>((ref) => '');` |
| `StateNotifierProvider` | Complex state with methods (CRUD controllers, paginated lists) | `final listProvider = StateNotifierProvider<Notifier, State>((ref) { ... });` |
| `FutureProvider` | One-shot async data fetching | `final dataProvider = FutureProvider<List<Item>>((ref) async { ... });` |
| `FutureProvider.family` | Parameterized async data fetching | `final itemProvider = FutureProvider.family<Item?, String>((ref, id) async { ... });` |
| `StreamProvider` | Real-time data streams | `final streamProvider = StreamProvider<List<Item>>((ref) { ... });` |

### Provider File Organization

Each feature's `providers/` file is organized in this order:

1. **Repository Providers** — `Provider<XRepository>`
2. **Filter/UI State Providers** — `StateProvider<String>`, `StateProvider<bool>`
3. **State Classes** — Immutable state objects with `copyWith()`
4. **StateNotifier Classes** — Business logic
5. **StateNotifierProvider declarations** — Wiring notifiers to their dependencies

### Use `autoDispose` by Default

Prefer `.autoDispose` on providers scoped to a screen or feature:

```dart
final featureListProvider = StateNotifierProvider.autoDispose<
  FeatureListNotifier, FeatureListState
>((ref) { ... });
```

---

## Core Features (MVP)

### 1. Server Connection (`features/server_connection/`)

- Add LM Studio server (IP + port)
- Add Ollama server (IP + port)
- Add OpenRouter (API key)
- Connection health indicator (ping status)
- Multiple server profiles

### 2. Chat Interface (`features/chat/`)

- ChatGPT/Claude-like chat bubbles
- Markdown rendering with syntax highlighting
- Streaming responses (SSE support)
- Copy, retry, delete individual messages
- Long-press context menu on messages

### 3. Model Management (`features/model_management/`)

- Fetch and list available models from connected server
- Swap models mid-chat
- Display model metadata (size, context length, etc.)

### 4. Conversation Management (`features/conversation/`)

- Create, rename, delete conversations
- Conversation history with search
- Pin important chats

### 5. Persona Management (`features/persona/`)

- Built-in presets: Code Assistant, Math Tutor, Story Writer, General Tutor
- Create custom persona (system prompt + name + avatar emoji)
- Apply persona per conversation

### 6. Settings (`features/settings/`)

- Chat parameters: temperature, top_p, max tokens, context length
- UI preferences: theme (dark/light), font size
- Default server selection

---

## Extended Features (Post-MVP)

| Feature                                      | Priority |
| -------------------------------------------- | -------- |
| AI Voice (TTS) — read responses aloud        | High     |
| Context Smart Replies — suggested follow-ups | High     |
| Multimodal — attach images/documents         | Medium   |
| Tablet-optimized split layout                | Medium   |
| Export conversation (Markdown, PDF)          | Medium   |
| Widget / quick-launch shortcut               | Low      |
| Haptic feedback                              | Low      |

---

## Design Philosophy

- **Shadcn-inspired**: Clean, neutral, component-driven. Cards, popovers, command palettes, sheets.
- **Dark-first**: Primary theme is a deep neutral dark (not pure black). Light mode optional.
- **Density-aware**: Comfortable padding on phone, denser on tablet.
- **No fluff**: Every UI element serves a purpose. No splash screens, no onboarding carousels beyond essentials.

---

## Privacy Commitments

- No analytics by default
- Conversations stored only on-device (Hive encrypted)
- Network requests go only to user-configured servers
- "LocalMind never sees your data" — shown in onboarding and settings
- Optional: show a live indicator of where data is going (local vs. cloud)

---

## Milestones

| Phase           | Deliverable                              | Est. Time |
| --------------- | ---------------------------------------- | --------- |
| 0 — Setup       | Flutter project, core folder structure, shadcn theme, routing   | 1 week    |
| 1 — Core        | Server config + basic chat (LM Studio)   | 2 weeks   |
| 2 — Chat Polish | Streaming, markdown, model swap          | 2 weeks   |
| 3 — Features    | Personas, conversation history, settings | 2 weeks   |
| 4 — Extended    | TTS, smart replies, multimodal           | 3 weeks   |
| 5 — Release     | Polish, Play Store prep, beta testing    | 2 weeks   |

---

## Monetization (Optional)

- Free: Core chat, 1 server, basic personas
- One-time unlock (~$3–5): Unlimited servers, TTS, smart replies, multimodal, no ads
- No subscriptions. Ever.

---

## Tracking Checklist

Follow these detailed breakdown documents to implement the project:

- [ ] [Feature 00 — Project Setup & Scaffolding](00_project_setup.md)
- [ ] [Feature 01 — Server Connection & Management](01_server_connection.md)
- [ ] [Feature 02 — Chat Interface](02_chat_interface.md)
- [ ] [Feature 03 — Model Management](03_model_management.md)
- [ ] [Feature 04 — Conversation Management](04_conversation_management.md)
- [ ] [Feature 05 — Templates & Personas](05_templates_personas.md)
- [ ] [Feature 06 — Settings](06_settings.md)
- [ ] [Feature 07 — Core Architecture](07_core_architecture.md)
- [ ] [Feature 08 — Design System](08_design_system.md)
- [ ] [Feature 09 — Extended Features](09_extended_features.md)
