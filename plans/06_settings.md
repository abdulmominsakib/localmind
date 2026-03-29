# Feature 06 — Settings

> **Phase:** 3 — Features  
> **Status:** Pending  
> **Depends on:** `00_project_setup`, `07_core_architecture`  

---

## Goal

Provide a comprehensive settings screen for configuring chat parameters, UI preferences, default server, and reviewing app/privacy information.

---

## Feature Folder Structure

```
features/settings/
├── data/
│   └── models/                      # (Uses core/models/app_settings.dart)
│
├── providers/
│   └── settings_providers.dart
│
└── views/
    ├── settings_page.dart           # Main settings screen
    └── components/
        ├── settings_section.dart
        ├── settings_slider.dart
        ├── settings_toggle.dart
        ├── settings_dropdown.dart
        ├── theme_toggle.dart
        └── font_size_preview.dart
```

---

## Dependencies Used

| Package             | Purpose                     |
| ------------------- | --------------------------- |
| `hive_ce`           | Persist settings locally    |
| `flutter_riverpod`  | Settings state management   |

---

## Data Model

`AppSettings` is defined in `core/models/app_settings.dart`.

---

## Providers

Location: `features/settings/providers/settings_providers.dart`

### Provider Organization

```dart
// 1. Settings state
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref.read(hiveBoxesProvider).settings);
});

// 2. Convenience providers
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(settingsProvider).themeMode;
});

final fontSizeProvider = Provider<double>((ref) {
  return ref.watch(settingsProvider).fontSize;
});

final chatParamsProvider = Provider<ChatParameters>((ref) {
  final settings = ref.watch(settingsProvider);
  return ChatParameters(
    temperature: settings.temperature,
    topP: settings.topP,
    maxTokens: settings.maxTokens,
    contextLength: settings.contextLength,
  );
});
```

### `SettingsNotifier`

```dart
class SettingsNotifier extends StateNotifier<AppSettings> {
  final Box<AppSettings> _box;

  SettingsNotifier(this._box) : super(AppSettings()) {
    loadSettings();
  }

  Future<void> loadSettings();
  void setTemperature(double value);
  void setTopP(double value);
  void setMaxTokens(int value);
  void setContextLength(int value);
  void setThemeMode(ThemeMode mode);
  void setFontSize(double size);
  void setHapticFeedback(bool enabled);
  void setSendOnEnter(bool enabled);
  void setShowSystemMessages(bool show);
  void setDefaultServer(String? serverId);
  void setAutoGenerateTitle(bool enabled);
  void setStreamingEnabled(bool enabled);
  void setDefaultPersona(String? personaId);
  void setShowDataIndicator(bool show);
  Future<void> resetToDefaults();
  Future<void> _persist();
}
```

---

## Views

### `settings_page.dart`

**Layout:**

```
┌──────────────────────────────────────┐
│  ← Settings                          │
│                                      │
│  ── CHAT PARAMETERS ──               │
│                                      │
│  Temperature                    0.7  │
│  ├──────────●──────────────────┤     │
│  Controls randomness. Lower =        │
│  focused, Higher = creative.         │
│                                      │
│  Top P                          0.9  │
│  ├──────────────────●──────────┤     │
│  Nucleus sampling threshold.         │
│                                      │
│  Max Tokens                    2048  │
│  [          2048            ]        │
│  Maximum response length.            │
│                                      │
│  Context Length                 4096  │
│  [          4096            ]        │
│  Conversation history window.        │
│                                      │
│  ── APPEARANCE ──                    │
│                                      │
│  Theme                               │
│  [System] [Light] [Dark ✓]          │
│                                      │
│  Font Size                      16   │
│  A ├────────●──────────────┤ A      │
│  Preview: The quick brown fox...     │
│                                      │
│  ── BEHAVIOR ──                      │
│                                      │
│  Streaming Responses          [✓]    │
│  Auto-generate Titles         [✓]    │
│  Send on Enter                [ ]    │
│  Show System Messages         [ ]    │
│  Haptic Feedback              [✓]    │
│                                      │
│  ── DEFAULT SERVER ──                │
│                                      │
│  [My Desktop LM Studio    ▼]        │
│                                      │
│  ── DEFAULT PERSONA ──               │
│                                      │
│  [🤖 General Assistant     ▼]       │
│                                      │
│  ── PRIVACY ──                       │
│                                      │
│  Show Data Indicator          [✓]    │
│  "LocalMind never sees your data"    │
│                                      │
│  ── DATA MANAGEMENT ──               │
│                                      │
│  [Export All Conversations]          │
│  [Delete All Conversations]  ⚠️      │
│  [Reset Settings to Defaults]        │
│                                      │
│  ── ABOUT ──                         │
│                                      │
│  LocalMind v1.0.0                    │
│  Your AI. Your Device. Your Rules.   │
│                                      │
│  [Privacy Policy]                    │
│  [Open Source Licenses]              │
│                                      │
└──────────────────────────────────────┘
```

---

## Components

### `settings_section.dart`

Groups related settings with uppercase section header.

### `settings_slider.dart`

- Label with current value display
- Slider control
- Description text below
- Used for: Temperature, Top P, Font Size

### `settings_toggle.dart`

- Label on left
- Switch on right
- Used for: Streaming, Auto-title, Send on Enter, etc.

### `settings_dropdown.dart`

- Label on left
- Dropdown selector on right
- Used for: Default Server, Default Persona

### `theme_toggle.dart`

Visual toggle between System, Light, Dark with icons (🌐 ☀️ 🌙).

### `font_size_preview.dart`

Live preview text that updates as font size slider moves.

---

## Chat Parameter Explanations

| Parameter       | Description                                                  |
| --------------- | ------------------------------------------------------------ |
| Temperature     | Controls randomness. 0 = deterministic, 2 = very random.      |
| Top P           | Nucleus sampling. 0.1 = conservative, 1.0 = all options.    |
| Max Tokens      | Maximum number of tokens in the response.                    |
| Context Length  | How many tokens of conversation history to send.             |

---

## Dangerous Actions

### Delete All Conversations

1. Tap "Delete All Conversations"
2. Show confirmation with red accent
3. On confirm: delete all, clear providers, navigate to empty chat

### Reset Settings

1. Tap "Reset Settings to Defaults"
2. Show confirmation dialog
3. On confirm: reset to factory defaults

---

## Settings Persistence

- All settings saved immediately (no "Save" button)
- `_persist()` called after every state update
- On launch, `loadSettings()` reads from Hive or creates defaults

---

## Acceptance Criteria

- [ ] Temperature slider works and updates chat behavior.
- [ ] Top P slider works and updates chat behavior.
- [ ] Max Tokens input validates and restricts to bounds.
- [ ] Context Length input validates and restricts to bounds.
- [ ] Theme toggle switches System/Light/Dark and persists.
- [ ] Font size slider adjusts chat text size with live preview.
- [ ] All toggle switches work and persist.
- [ ] Default server dropdown shows all saved servers.
- [ ] Default persona dropdown shows all personas.
- [ ] "Delete All Conversations" works with confirmation.
- [ ] "Reset Settings" restores all defaults.
- [ ] All settings persist across restarts.
- [ ] Settings screen scrolls smoothly.
- [ ] Each parameter has helpful description.
