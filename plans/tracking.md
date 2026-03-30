# LocalMind — Implementation Tracking

> Last updated: 2026-03-30 (v3 — Steps 1-5 complete)

---

## Legend

- ✅ **Done** — Fully implemented and functional
- 🔶 **Partial** — Exists but incomplete (stubs, placeholders, missing pieces)
- ❌ **Not Done** — Does not exist or is just a placeholder

---

## Phase 0 — Setup & Core

### Feature 00: Project Setup

| Task | Status |
|------|--------|
| `main.dart` — Hive init, ProviderScope, routing | ✅ Done |
| `app.dart` — App root with ShadCN + GoRouter | ✅ Done |
| Folder structure (core + features) | ✅ Done |
| `pubspec.yaml` — all dependencies configured | ✅ Done |

### Feature 07: Core Architecture

| Task | Status |
|------|--------|
| `core/constants/app_constants.dart` — app-wide constants | ✅ Done |
| `core/models/enums.dart` — ServerType, ConnectionStatus, MessageRole, MessageStatus | ✅ Done |
| `core/providers/app_providers.dart` — active server, active conversation, settings | ✅ Done |
| `core/providers/service_providers.dart` — Dio, ServerApiService, SettingsProvider | ✅ Done |
| `core/providers/storage_providers.dart` — Hive boxes access, personas, conversations | ✅ Done |
| `core/storage/hive_initializer.dart` — box opening, adapter registration | ✅ Done |
| `core/storage/hive_keys.dart` — box name constants | ✅ Done |
| `core/routes/app_routes.dart` — route definitions | ✅ Done |
| UUID generation utility | ✅ Done (inline in chat/conversation providers) |
| `core/repository/server/server_repository.dart` — abstract server repo | ❌ Not Done (logic is in `server_api_service.dart` under features — cross-feature import) |
| `core/repository/chat/chat_service.dart` — abstract chat service | ✅ Done (located in `features/chat/data/`) |
| `core/utils/date_utils.dart` — date formatting | ❌ Not Done (date formatting is inline) |
| `AppException` / `AppErrorType` error model | ❌ Not Done |

### Feature 08: Design System

| Task | Status |
|------|--------|
| `core/theme/colors.dart` — AppColors dark + light | ✅ Done |
| `core/theme/typography.dart` — Inter + Fira Code text styles | ✅ Done |
| `core/theme/app_theme.dart` — ThemeData dark + light | ✅ Done |
| `core/components/app_button.dart` — button variants | ❌ Not Done |
| `core/components/app_card.dart` — card component | ❌ Not Done |
| `core/components/app_text_field.dart` — text input component | ❌ Not Done |
| `core/components/app_sheet.dart` — bottom sheet wrapper | ❌ Not Done |
| `core/components/app_dialog.dart` — dialog wrapper | ❌ Not Done |
| `core/components/app_loading_indicator.dart` — spinner | ❌ Not Done |
| Haptic feedback integration | ✅ Done (in chat input bar) |
| Spacing & radius constants (`AppSizes`) | ❌ Not Done |

---

## Phase 1 — Core Features

### Feature 01: Server Connection

| Task | Status | Notes |
|------|--------|-------|
| **DATA & MODELS** | | |
| `server.dart` model with Hive annotations | ✅ Done | `features/servers/data/models/` |
| `server.g.dart` — generated Hive adapter | ✅ Done | |
| **LOGIC (PROVIDERS)** | | |
| `ServersNotifier` — add/update/delete server | ✅ Done | `features/servers/providers/server_providers.dart` |
| `ActiveServerNotifier` — active server selection + persistence | ✅ Done | |
| `ConnectionStatusNotifier` — connection check on server change | ✅ Done | |
| `availableModelsProvider` — fetch models per server | ✅ Done | |
| Background connection monitoring (30s ping) | ❌ Not Done | Manual refresh only |
| **SERVICES** | | |
| `ServerApiService` — testConnection (LM Studio) | ✅ Done | `features/servers/data/server_api_service.dart` |
| `ServerApiService` — testConnection (Ollama) | ✅ Done | |
| `ServerApiService` — testConnection (OpenRouter) | ✅ Done | |
| `ServerApiService` — fetchModels (LM Studio) | ✅ Done | |
| `ServerApiService` — fetchModels (Ollama) | ✅ Done | |
| `ServerApiService` — fetchModels (OpenRouter) | ✅ Done | |
| `ServerApiService` — pingServer | ✅ Done | |
| **UI** | | |
| `server_list_screen.dart` — list + empty state + FAB | ✅ Done | |
| `server_card.dart` — server info card | ✅ Done | |
| `add_server_screen.dart` — form with validation + test + save | ✅ Done | |
| `server_type_selector.dart` — LM Studio / Ollama / OpenRouter toggle | ✅ Done | |
| `connection_status_indicator.dart` — animated status dot | ✅ Done | |
| `server_icon_picker.dart` — icon picker sheet | ✅ Done | |

### Feature 02: Chat Interface

| Task | Status | Notes |
|------|--------|-------|
| **DATA & MODELS** | | |
| `message.dart` model with Hive annotations | ✅ Done | `features/chat/data/models/message.dart` |
| `message.g.dart` — generated Hive adapter | ✅ Done | |
| `chat_parameters.dart` — ChatParameters model | ✅ Done | |
| **LOGIC (PROVIDERS)** | | |
| `ChatNotifier` — sendMessage with streaming | ✅ Done | `features/chat/providers/chat_providers.dart` |
| `ChatNotifier` — loadConversation | ✅ Done | |
| `ChatNotifier` — retryLastMessage | ✅ Done | |
| `ChatNotifier` — deleteMessage | ✅ Done | |
| `ChatNotifier` — clearConversation | ✅ Done | |
| `ChatNotifier` — cancelStream | ✅ Done | |
| `ChatNotifier` — startNewConversation | ✅ Done | |
| Context window truncation logic | ✅ Done | |
| System prompt injection (persona + default) | ✅ Done | `chat_providers.dart` — `_getPersonaSystemPrompt()` + default |
| **SERVICES** | | |
| `ChatService` abstract class | ✅ Done | `features/chat/data/chat_service.dart` |
| `LMStudioChatService` — SSE streaming | ✅ Done | |
| `OllamaChatService` — NDJSON streaming | ✅ Done | |
| `OpenRouterChatService` — SSE with API key | ✅ Done | |
| **UI** | | |
| `chat_screen.dart` — full chat page with messages + input | ✅ Done | |
| `chat_bubble.dart` — user / assistant / system bubbles | ✅ Done | |
| `chat_bubble.dart` — markdown rendering | ✅ Done | |
| `chat_bubble.dart` — streaming indicator (blinking cursor) | ✅ Done | `StreamingIndicator` in `typing_indicator.dart` |
| `chat_input_bar.dart` — multi-line input + send/stop | ✅ Done | |
| `typing_indicator.dart` — 3 bouncing dots | ✅ Done | |
| `message_action_bar.dart` — copy/retry/delete buttons | ✅ Done | |
| `code_block.dart` — syntax highlighting + copy | ✅ Done | |
| Empty state with quick prompts | ✅ Done | |
| "New messages ↓" scroll-to-bottom FAB | ✅ Done | |
| Connection error banner | ✅ Done | |
| Recent conversations on empty state | ✅ Done | |
| Haptic feedback on send | ✅ Done | |

### Feature 03: Model Management

| Task | Status | Notes |
|------|--------|-------|
| **DATA & MODELS** | | |
| `model_info.dart` — ModelInfo model | ✅ Done | `features/models/data/models/model_info.dart` |
| **LOGIC** | | |
| `selectedModelProvider` — track selected model | ✅ Done | In `chat_providers.dart` |
| Model cache with 5-min TTL | ❌ Not Done | No caching |
| `modelSearchQueryProvider` — search/filter | ✅ Done | In `model_picker_sheet.dart` |
| **UI** | | |
| `model_picker_sheet.dart` — full model list + search + selection | ✅ Done | |
| `_ModelTile` — model row with name + metadata | ✅ Done | |
| `_MetadataChip` — pills for params/size/quantization/context | ✅ Done | |
| Model search bar | ✅ Done | |
| Selected model indicator (checkmark) | ✅ Done | |
| Loading skeleton + error state + retry | ✅ Done | |
| Refresh models button | ✅ Done | |

---

## Phase 3 — Features

### Feature 04: Conversation Management

| Task | Status | Notes |
|------|--------|-------|
| **DATA & MODELS** | | |
| `conversation.dart` model with Hive annotations | ✅ Done | `features/conversations/data/models/conversation.dart` |
| `conversation.g.dart` — generated Hive adapter | ✅ Done | |
| **LOGIC (PROVIDERS)** | | |
| `ConversationsNotifier` — create | ✅ Done | `features/conversations/providers/conversation_providers.dart` |
| `ConversationsNotifier` — rename | ✅ Done | |
| `ConversationsNotifier` — delete | ✅ Done | |
| `ConversationsNotifier` — togglePin | ✅ Done | |
| `ConversationsNotifier` — updatePreview | ✅ Done | |
| `ConversationsNotifier` — deleteAll | ✅ Done | |
| `ActiveConversationNotifier` — active conversation tracking | ✅ Done | |
| `ConversationSearchNotifier` — search query state | ✅ Done | |
| `filteredConversationsProvider` — filter by title/preview | ✅ Done | |
| `groupedConversationsProvider` — date grouping (Pinned/Today/Yesterday/7d/30d/Older) | ✅ Done | |
| **UI** | | |
| `conversation_drawer.dart` — Drawer wrapper | ✅ Done | |
| `conversation_sidebar.dart` — full sidebar with conversations + nav | ✅ Done | |
| `conversation_drawer_header.dart` — "LocalMind" header | ✅ Done | |
| `conversation_list.dart` — grouped list view | ✅ Done | |
| `conversation_tile.dart` — single conversation row | ✅ Done | |
| `conversation_search_bar.dart` — search input | ✅ Done | |
| `conversation_empty_state.dart` — no conversations state | ✅ Done | |
| `date_section_header.dart` — TODAY/YESTERDAY/OLDER headers | ✅ Done | |
| `drawer_nav_item.dart` — Chat/Servers/Personas nav | ✅ Done | |
| `new_chat_button.dart` — "New Chat" CTA | ✅ Done | |
| Long-press context menu (Rename/Pin/Delete) | ❌ Not Done | Delete only, no rename/pin from sidebar |
| Swipe-to-delete with undo snackbar | ❌ Not Done | |
| Auto-title generation after first exchange | ❌ Not Done | Uses truncated first message |

### Feature 05: Personas

| Task | Status | Notes |
|------|--------|-------|
| **DATA & MODELS** | | |
| `persona.dart` model with Hive annotations | ✅ Done | `features/personas/data/models/persona.dart` |
| `persona.g.dart` — generated Hive adapter | ✅ Done | |
| **LOGIC** | | |
| `PersonasNotifier` — CRUD operations | ✅ Done | `features/personas/providers/personas_providers.dart` |
| `seedBuiltInPersonas()` — 7 presets on first launch | ✅ Done | Auto-seeded on first build |
| `personaCategoryFilterProvider` — category filter | ✅ Done | |
| `filteredPersonasProvider` — filter by category + search | ✅ Done | |
| `personaSearchQueryProvider` — search query | ✅ Done | |
| `builtInPersonasProvider` / `userPersonasProvider` | ✅ Done | |
| `personaByIdProvider` — lookup by ID | ✅ Done | |
| Persona clone functionality | ✅ Done | |
| Persona system prompt injection into chat | ✅ Done | In `chat_providers.dart` |
| **UI** | | |
| `persona_list_screen.dart` — full list with sections | ✅ Done | |
| `_PersonaCard` — persona display card | ✅ Done | |
| Category filter chips (All/General/Coding/Education/Creative) | ✅ Done | |
| Built-in vs My Personas sections | ✅ Done | |
| Long-press actions (Edit/Delete/Clone) | ✅ Done | |
| Persona emoji display | ✅ Done | |
| Empty state | ✅ Done | |
| `create_persona_screen.dart` — full form | ✅ Done | |
| Emoji picker (horizontal scroll) | ✅ Done | |
| Category dropdown | ✅ Done | |
| System prompt field with character count | ✅ Done | |
| Preview mode toggle | ✅ Done | |
| Advanced settings (temperature/topP overrides) | ✅ Done | |
| Edit mode (pre-filled from persona) | ✅ Done | |

### Feature 06: Settings

| Task | Status | Notes |
|------|--------|-------|
| **DATA & MODELS** | | |
| `app_settings.dart` model with Hive annotations | ✅ Done | `features/settings/data/models/app_settings.dart` |
| `app_settings.g.dart` — generated Hive adapter | ✅ Done | |
| **LOGIC** | | |
| `SettingsNotifier` — load, update individual fields, persist | ✅ Done | In `app_providers.dart` |
| `setTemperature` / `setTopP` / `setMaxTokens` / `setContextLength` | ✅ Done | |
| `setFontSize` / `setShowSystemMessages` / `setHapticFeedback` | ✅ Done | |
| `setSendOnEnter` / `setDefaultServer` / `setDefaultPersona` | ✅ Done | |
| `setStreamingEnabled` / `setAutoGenerateTitle` / `setShowDataIndicator` | ✅ Done | |
| `resetToDefaults` | ✅ Done | |
| **UI** | | |
| `settings_screen.dart` — full scrollable settings page | ✅ Done | |
| Temperature slider (0.0–2.0) + explanation | ✅ Done | |
| Top P slider (0.0–1.0) + explanation | ✅ Done | |
| Max Tokens input (bounded) + explanation | ✅ Done | |
| Context Length input (bounded) + explanation | ✅ Done | |
| Theme toggle (System/Light/Dark/Claude) | ✅ Done | |
| Font size slider + live preview | ✅ Done | |
| Toggles: streaming, auto-title, send-on-enter, system messages, haptic | ✅ Done | |
| Default server dropdown | ✅ Done | |
| Default persona dropdown | ✅ Done | |
| Privacy section with data indicator toggle | ✅ Done | |
| Delete all conversations button + confirmation | ✅ Done | |
| Reset settings button + confirmation | ✅ Done | |
| About section | ✅ Done | |
| **UI** | | |
| `settings_screen.dart` — main settings page | ❌ Not Done | Placeholder only — "Settings - Placeholder" |
| `settings_section.dart` — section group + header | ❌ Not Done | |
| `settings_slider.dart` — label + slider + value | ❌ Not Done | |
| `settings_toggle.dart` — label + switch | ❌ Not Done | |
| `settings_dropdown.dart` — server/persona picker | ❌ Not Done | |
| `theme_toggle.dart` — System/Light/Dark visual toggle | ❌ Not Done | |
| `font_size_preview.dart` — live text preview | ❌ Not Done | |
| Chat parameter explanations | ❌ Not Done | |
| Dangerous actions with confirmation | ❌ Not Done | |

---

## Phase 4 — Extended Features

### Feature 09: Extended Features

| Task | Status |
|------|--------|
| AI Voice (TTS) — read aloud | ❌ Not Done |
| Context Smart Replies — follow-up chips | ❌ Not Done |
| Multimodal — image attachment (button exists but disabled) | ❌ Not Done |
| Tablet/Desktop responsive layout | ✅ Done | `AppShell` in `app.dart` — persistent sidebar on `>= md` breakpoint |
| Export conversation (Markdown/PDF) | ❌ Not Done |
| Quick-launch shortcut | ❌ Not Done |

---

## Phase Extra: Onboarding (Not in original plan)

| Task | Status | Notes |
|------|--------|-------|
| `onboarding_server_type_screen.dart` — pick LM Studio/Ollama/OpenRouter | ✅ Done | |
| `onboarding_server_setup_screen.dart` — configure first server | ✅ Done | |
| `onboarding_theme_screen.dart` — pick dark/light | ✅ Done | |

---

## Summary

| Category | Done | Partial | Not Done | Total |
|----------|------|---------|----------|-------|
| **Phase 0** — Setup & Core | 10 | 0 | 5 | 15 |
| **Phase 1** — Server Connection | 14 | 0 | 1 | 15 |
| **Phase 1** — Chat Interface | 19 | 0 | 0 | 19 |
| **Phase 2** — Model Management | 10 | 0 | 1 | 11 |
| **Phase 3** — Conversations | 13 | 0 | 3 | 16 |
| **Phase 3** — Personas | 21 | 0 | 0 | 21 |
| **Phase 3** — Settings | 17 | 0 | 0 | 17 |
| **Phase 4** — Extended | 1 | 0 | 5 | 6 |
| **Extra** — Onboarding | 3 | 0 | 0 | 3 |
| **TOTAL** | **108** | **0** | **15** | **123** |

---

## What to Build Next (Ordered Build Plan)

> Follow this order. Each step depends on the previous one.

### Step 1: Settings Screen (UI + Logic) ✅ DONE
**Why first:** Everything else (chat params, theme, defaults) flows through settings.

| Sub-task | Type |
|----------|------|
| `SettingsNotifier` — load, update individual fields, persist | Logic |
| Temperature slider (0.0–2.0) + explanation | UI |
| Top P slider (0.0–1.0) + explanation | UI |
| Max Tokens input (bounded) + explanation | UI |
| Context Length input (bounded) + explanation | UI |
| Theme toggle (System/Light/Dark/Claude) — wire to existing `themeModeProvider` | UI |
| Font size slider + live preview | UI |
| Toggles: streaming, auto-title, send-on-enter, system messages, haptic | UI |
| Default server dropdown — wire to `serversProvider` | UI |
| Default persona dropdown — wire to `personasProvider` | UI |
| Delete all conversations button + confirmation | UI |
| Reset settings button + confirmation | UI |
| Settings sections + scrollable layout | UI |

### Step 2: Model Picker Sheet (UI) ✅ DONE
**Why second:** Chat screen already passes selected model to API — just needs the picker UI.

| Sub-task | Type |
|----------|------|
| Wire `availableModelsProvider` to model picker | Logic |
| Model list with metadata chips (params, size, quantization, context) | UI |
| Search/filter bar | UI |
| Selected model checkmark | UI |
| Loading skeleton + error state + retry | UI |
| Refresh models button | UI |
| Tap to select + dismiss | UI |

### Step 3: Persona Providers (Logic) ✅ DONE
**Why third:** Persona UI needs providers to read from.

| Sub-task | Type |
|----------|------|
| `PersonasNotifier` — load, create, update, delete, clone | Logic |
| Seed 7 built-in personas on first launch | Logic |
| `selectedPersonaProvider` — current persona for new chat | Logic |
| `personaCategoryFilterProvider` + `filteredPersonasProvider` | Logic |
| Persona CRUD with Hive persistence | Logic |

### Step 4: Persona List Screen (UI) ✅ DONE
**Why fourth:** Depends on providers from step 3.

| Sub-task | Type |
|----------|------|
| Persona cards (emoji, name, description, category chip) | UI |
| Built-in vs My Personas sections | UI |
| Category filter chips (All/Coding/Education/Creative/General) | UI |
| Tap persona → apply to current conversation | UI |
| Long-press → Edit/Delete/Clone | UI |
| "Create Custom Persona" FAB | UI |

### Step 5: Create Persona Screen (UI) ✅ DONE
**Why fifth:** Create/edit flow for personas.

| Sub-task | Type |
|----------|------|
| Form: name, emoji picker, category dropdown, description, system prompt | UI |
| Character count on system prompt | UI |
| Preview mode toggle | UI |
| Advanced settings: temperature/topP overrides | UI |
| Save + validation | UI |
| Edit mode (pre-filled) | Logic |

### Step6: Persona → Chat Integration (Logic + UI)
**Why sixth:** Connects personas to actual chat behavior.

| Sub-task | Type |
|----------|------|
| Persona system prompt injection in `_buildMessagesForApi` (already done ✅) | Logic |
| Persona parameter overrides applied to `chatParamsProvider` | Logic |
| Persona emoji shown in chat app bar | UI |
| "Change Persona" in chat overflow menu | UI |
| "Remove Persona" option | UI |
| Conversation `personaId` set when persona selected | Logic |

### Step 7: Conversation Enhancements (UI + Logic)
**Why seventh:** Polish existing working features.

| Sub-task | Type |
|----------|------|
| Long-press context menu (Rename, Pin/Unpin, Delete) | UI |
| Swipe-to-delete with undo snackbar | UI |
| Auto-title generation (LLM-based after first exchange) | Logic |
| Inline rename dialog | UI |

### Step 8: Design System Components (UI)
**Why eighth:** Reusable building blocks for polish.

| Sub-task | Type |
|----------|------|
| `AppButton` — primary, outline, ghost, destructive, loading, icon | Component |
| `AppCard` — standard card with border, tap, padding | Component |
| `AppTextField` — styled text input | Component |
| `AppSheet` — bottom sheet wrapper with drag handle | Component |
| `AppDialog` — dialog wrapper | Component |
| `AppLoadingIndicator` — accent-colored spinner | Component |
| `AppSizes` — spacing and radius constants | Constants |

### Step 9: Error Handling (Logic)
**Why ninth:** Centralizes error messages.

| Sub-task | Type |
|----------|------|
| `AppException` model with type, message, detail | Model |
| `AppErrorType` enum mapping to user-friendly strings | Model |
| Wire into chat, server, and model services | Logic |

### Step 10: Extended Features (UI + Logic)
**Why last:** Polished app first, then extra features.

| Sub-task | Type |
|----------|------|
| TTS — read aloud button + voice settings | Feature |
| Smart Replies — follow-up chips after assistant response | Feature |
| Multimodal — image attachment (wire existing button) | Feature |
| Export — Markdown + PDF + share | Feature |
| Quick-launch shortcuts | Feature |
