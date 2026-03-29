# Feature 04 — Conversation Management

> **Phase:** 3 — Features  
> **Status:** Pending  
> **Depends on:** `00_project_setup`, `02_chat_interface`, `07_core_architecture`  

---

## Goal

Provide a full conversation lifecycle: create, rename, delete, search, and pin conversations. Build a ChatGPT-style sidebar/drawer for browsing conversation history.

---

## Feature Folder Structure

```
features/conversation/
├── data/
│   └── models/                      # (Uses core/models/conversation.dart)
│
├── providers/
│   └── conversation_providers.dart
│
└── views/
    ├── conversation_drawer.dart     # Sidebar navigation
    └── components/
        ├── conversation_tile.dart
        ├── conversation_search_bar.dart
        └── date_section_header.dart
```

---

## Dependencies Used

| Package             | Purpose                          |
| ------------------- | -------------------------------- |
| `hive_ce`           | Persist conversations locally    |
| `flutter_riverpod`  | Conversation state management    |

---

## Data Model

The `Conversation` model is defined in `core/models/conversation.dart`.

---

## Providers

Location: `features/conversation/providers/conversation_providers.dart`

### Provider Organization

```dart
// 1. All conversations
final conversationsProvider = StateNotifierProvider<ConversationsNotifier, List<Conversation>>((ref) {
  final box = ref.watch(hiveBoxesProvider).conversations;
  return ConversationsNotifier(box);
});

// 2. Currently active conversation
final activeConversationProvider = StateNotifierProvider<ActiveConversationNotifier, Conversation?>((ref) {
  final conversationsBox = ref.watch(hiveBoxesProvider).conversations;
  final settingsBox = ref.watch(hiveBoxesProvider).settings;
  return ActiveConversationNotifier(conversationsBox, settingsBox);
});

// 3. Search query
final conversationSearchProvider = StateProvider<String>((ref) => '');

// 4. Filtered conversations based on search
final filteredConversationsProvider = Provider<List<Conversation>>((ref) {
  final convos = ref.watch(conversationsProvider);
  final query = ref.watch(conversationSearchProvider).toLowerCase();
  if (query.isEmpty) return convos;
  return convos.where((c) =>
    c.title.toLowerCase().contains(query) ||
    (c.lastMessagePreview?.toLowerCase().contains(query) ?? false)
  ).toList();
});
```

### `ConversationsNotifier`

```dart
class ConversationsNotifier extends StateNotifier<List<Conversation>> {
  final Box<Conversation> _box;

  ConversationsNotifier(this._box) : super([]) {
    loadConversations();
  }

  Future<void> loadConversations();
  Future<Conversation> createConversation({String? title, String? personaId, String? systemPrompt});
  Future<void> renameConversation(String id, String newTitle);
  Future<void> deleteConversation(String id);
  Future<void> togglePin(String id);
  Future<void> updatePreview(String id, String preview, DateTime updatedAt);
  Future<void> deleteAll();
}
```

### `ActiveConversationNotifier`

```dart
class ActiveConversationNotifier extends StateNotifier<Conversation?> {
  final Box<Conversation> _conversationsBox;
  final Box<AppSettings> _settingsBox;

  ActiveConversationNotifier(this._conversationsBox, this._settingsBox) : super(null) {
    _loadActiveConversation();
  }

  void _loadActiveConversation() { ... }
  Future<void> setActiveConversation(String? id) async { ... }
}
```

---

## Auto-Title Generation

When a new conversation is started:

1. First message sent with title "New Chat"
2. After first assistant response, auto-generate title
3. **Method A (preferred):** Send lightweight title generation request:
   ```
   System: Generate a short title (max 6 words) for the following conversation.
   Respond with ONLY the title, no quotes or punctuation.
   User: {first user message}
   Assistant: {first assistant response (truncated to 200 chars)}
   ```
4. **Method B (fallback):** Use first 50 chars of first user message
5. Update conversation title in Hive

---

## Views

### `conversation_drawer.dart`

Primary navigation element, opened from hamburger menu.

**Layout:**

```
┌──────────────────────────────────────┐
│  LocalMind                     [⚙️]  │
│                                      │
│  [+ New Chat]                        │
│                                      │
│  [🔍 Search conversations...  ]     │
│                                      │
│  ── PINNED ──                        │
│  📌 Project Brainstorm              │
│      "Let me help you with..."       │
│      3 hours ago                     │
│                                      │
│  ── TODAY ──                         │
│  💬 How to cook pasta               │
│      "Here's a simple recipe..."     │
│      2 hours ago                     │
│                                      │
│  ── YESTERDAY ──                     │
│  💬 Explain quantum computing        │
│      "At its core, quantum..."       │
│      Yesterday                       │
│                                      │
│  ─────────────────────               │
│  [🖥 Servers]  [👤 Personas]         │
│  [⚙️ Settings]                       │
└──────────────────────────────────────┘
```

**Section grouping:**
- Pinned (always on top)
- Today
- Yesterday
- Previous 7 Days
- Previous 30 Days
- Older

**Interactions:**
- Tap → load and switch to conversation
- Long-press → context menu: Rename, Pin/Unpin, Delete
- Swipe left → delete with undo snackbar
- Active conversation highlighted

---

## Components

### `conversation_tile.dart`

- Leading: Pin icon (if pinned) or message icon
- Title: Conversation title (single line, ellipsis)
- Subtitle: Last message preview (single line, muted)
- Trailing: Relative timestamp ("2h ago", "Yesterday")
- Active state: subtle accent background
- Slidable: swipe-to-delete

### `conversation_search_bar.dart`

- ShadCN-styled search input
- Clear button when text present
- Debounced search (300ms)

### `date_section_header.dart`

- Uppercase, small text, muted color
- "TODAY", "YESTERDAY", "PREVIOUS 7 DAYS", etc.

---

## Conversation Lifecycle

### Create
1. User taps "+ New Chat"
2. Create new `Conversation` with title "New Chat"
3. Save to Hive
4. Set as active conversation
5. Navigate to chat screen
6. Auto-title after first exchange

### Switch
1. User taps conversation in drawer
2. Set as active conversation
3. Load messages from Hive
4. Restore model selection if stored
5. Close drawer, show chat

### Delete
1. User swipes or selects delete
2. Show confirmation dialog
3. Delete conversation + all messages
4. If deleting active, switch to most recent or create new
5. Show undo snackbar (5 seconds)

### Rename
1. Select rename from context menu
2. Show inline edit or dialog
3. Save on confirm

---

## Storage

- Conversations in `Hive.box<Conversation>('conversations')`
- Messages in `Hive.box<Message>('messages')` with `conversationId` field
- Cascade delete messages on conversation delete
- Order by: `isPinned DESC, updatedAt DESC`

---

## Acceptance Criteria

- [ ] User can create a new conversation.
- [ ] User can switch between conversations.
- [ ] User can rename a conversation.
- [ ] User can delete a conversation (with confirmation).
- [ ] User can pin/unpin a conversation.
- [ ] Conversations grouped by date in sidebar.
- [ ] Search filters by title and message preview.
- [ ] Auto-title generates after first exchange.
- [ ] Active conversation highlighted in sidebar.
- [ ] Empty state shows "No conversations yet" CTA.
- [ ] Deleting active conversation switches or creates new.
- [ ] Conversation data persists across restarts.
