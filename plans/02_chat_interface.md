# Feature 02 — Chat Interface

> **Phase:** 1–2 — Core + Chat Polish  
> **Status:** Pending  
> **Depends on:** `00_project_setup`, `01_server_connection`, `07_core_architecture`  

---

## Goal

Build a ChatGPT/Claude-quality chat interface with:
- Beautiful message bubbles with markdown rendering
- Real-time streaming responses (SSE / chunked transfer)
- Rich input bar with actions
- Message interactions (copy, retry, delete, edit)
- Typing indicators and loading states

---

## Feature Folder Structure

```
features/chat/
├── data/
│   └── models/                      # (Uses core/models/message.dart)
│
├── providers/
│   └── chat_providers.dart
│
└── views/
    ├── chat_page.dart               # Main chat screen
    └── components/
        ├── chat_bubble.dart
        ├── chat_input_bar.dart
        ├── typing_indicator.dart
        ├── message_action_bar.dart
        └── code_block.dart
```

---

## Dependencies Used

| Package                  | Purpose                         |
| ------------------------ | ------------------------------- |
| `dio`                    | HTTP client with streaming      |
| `flutter_markdown`        | Render markdown in messages     |
| `flutter_highlight`       | Code block syntax highlighting  |
| `haptic_feedback`         | Tactile feedback on actions     |

---

## Data Model

The `Message` model and enums (`MessageRole`, `MessageStatus`) are defined in `core/models/message.dart`.

---

## API Integration — Streaming Chat Completions

### LM Studio & OpenRouter (OpenAI-compatible)

```
POST /v1/chat/completions
Headers:
  Content-Type: application/json
  Authorization: Bearer {apiKey}  // OpenRouter only
Body:
{
  "model": "model-id",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "..."}
  ],
  "temperature": 0.7,
  "top_p": 0.9,
  "max_tokens": 2048,
  "stream": true
}
```

**Streaming response format (SSE):**
```
data: {"choices":[{"delta":{"content":"Hello"}}]}
data: {"choices":[{"delta":{"content":" world"}}]}
data: [DONE]
```

### Ollama

```
POST /api/chat
Body:
{
  "model": "model-name",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "stream": true,
  "options": {
    "temperature": 0.7,
    "top_p": 0.9,
    "num_predict": 2048
  }
}
```

**Streaming response format (NDJSON):**
```json
{"message":{"role":"assistant","content":"Hello"},"done":false}
{"message":{"role":"assistant","content":" world"},"done":false}
{"message":{"role":"assistant","content":""},"done":true,"total_duration":...}
```

---

## Chat Services

`ChatService` and implementations are defined in `core/repository/chat/`.

```dart
abstract class ChatService {
  Stream<String> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  });

  void cancelStream();
}
```

### Streaming Implementation Details

1. **Context window management:** Truncate message history to fit within `contextLength`. Keep system prompt + last N messages.
2. **Token estimation:** Use 4 chars ≈ 1 token heuristic.
3. **Error recovery:** If stream breaks, save partial and mark as error.
4. **Cancel token:** Pass `CancelToken` to Dio for user cancellation.

---

## Providers

Location: `features/chat/providers/chat_providers.dart`

### Provider Organization

```dart
// 1. Chat Service (factory based on active server type)
final chatServiceProvider = Provider<ChatService>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) throw StateError('No active server');
  return ChatService.forServer(server.type, ref.read(dioProvider));
});

// 2. Chat Parameters (from settings)
final chatParamsProvider = Provider<ChatParameters>((ref) {
  final settings = ref.watch(settingsProvider);
  return ChatParameters(
    temperature: settings.temperature,
    topP: settings.topP,
    maxTokens: settings.maxTokens,
    contextLength: settings.contextLength,
  );
});

// 3. Selected model for current chat
final selectedModelProvider = StateProvider<ModelInfo?>((ref) => null);

// 4. Streaming state
final isStreamingProvider = StateProvider<bool>((ref) => false);

// 5. Messages for current conversation
final messagesProvider = StateNotifierProvider<MessagesNotifier, List<Message>>((ref) {
  final repository = ref.watch(messageRepositoryProvider);
  final conversation = ref.watch(activeConversationProvider);
  return MessagesNotifier(repository, conversation?.id);
});

// 6. Message list state
class MessagesNotifier extends StateNotifier<List<Message>> {
  final MessageRepository _repository;
  final String? _conversationId;

  MessagesNotifier(this._repository, this._conversationId) : super([]) {
    if (_conversationId != null) loadMessages();
  }

  Future<void> loadMessages() async { ... }
  Future<void> sendMessage(String content) async { ... }
  Future<void> retryLastMessage() async { ... }
  Future<void> editMessage(String messageId, String newContent) async { ... }
  Future<void> deleteMessage(String messageId) async { ... }
  void cancelStream() { ... }
  Future<void> clearConversation() async { ... }
}
```

---

## Views

### `chat_page.dart`

**Layout (top to bottom):**

```
┌──────────────────────────────────────┐
│  AppBar                              │
│  [☰ Drawer] [Model: GPT-4] [⋮ Menu]│
├──────────────────────────────────────┤
│                                      │
│  Message List (scrollable)           │
│                                      │
│  ┌─────────────────────────────┐     │
│  │ 👤 User message             │     │
│  └─────────────────────────────┘     │
│                                      │
│  ┌─────────────────────────────┐     │
│  │ 🤖 Assistant response       │     │
│  │ (markdown rendered)         │     │
│  │ [Copy] [Retry] [⋮]        │     │
│  └─────────────────────────────┘     │
│                                      │
│  ┌─────────────────────────────┐     │
│  │ ⏳ Streaming indicator...   │     │
│  └─────────────────────────────┘     │
│                                      │
├──────────────────────────────────────┤
│  Input Bar                           │
│  [📎] [  Type a message...   ] [▶]  │
│  [Stop Generating] (if streaming)    │
└──────────────────────────────────────┘
```

**App bar details:**
- Left: Hamburger menu to open conversation drawer
- Center: Current model name (tappable → opens model picker)
- Right: overflow menu (New Chat, Clear, Chat Settings)

**Empty state (new conversation):**
- Show LocalMind logo centered
- "Start a conversation" subtitle
- Quick-start prompt suggestions as tappable chips

---

## Components

### `chat_bubble.dart`

**User messages:**
- Right-aligned, filled background
- Plain text or light markdown
- Timestamp on bottom-right

**Assistant messages:**
- Left-aligned, transparent/subtle surface background
- Full markdown rendering (headers, bold, italic, lists, code blocks, links, tables)
- Action buttons: Copy | Retry | ⋮

**System messages:**
- Centered, muted text, italic
- Toggleable in settings

**Streaming state:**
- Show text as it arrives
- Blinking cursor at end
- Auto-scroll to bottom

### `chat_input_bar.dart`

**Layout:**
- Multi-line text field (max 6 lines, expanding)
- Left: attachment button (📎) — future multimodal
- Right: send button (▶) → stop button (⏹) when streaming
- Placeholder: "Message LocalMind..."

**Behavior:**
- Send on button tap or keyboard send action
- Disable when input empty or disconnected
- Character/token count near limits
- Haptic feedback on send

### `typing_indicator.dart`

- Three bouncing dots animation
- Shown while waiting for first token

### `message_action_bar.dart`

- **Copy** — copy full text to clipboard
- **Retry** — regenerate response
- **Edit** (user messages) — open edit mode
- **Delete** — remove with confirmation
- **More (⋮)** — bottom sheet:
  - "Copy as Markdown"
  - "Share"
  - "View raw"
  - "Token count: {n}"

### `code_block.dart`

- Language detection from fence info string
- Syntax highlighting via `flutter_highlight`
- Header bar: language name + copy button
- Dark background, horizontal scroll
- Monospace font (Fira Code / JetBrains Mono)

---

## Scroll Behavior

- Auto-scroll to bottom on new message (if user already near bottom)
- If user scrolled up, show "New messages ↓" floating button
- Smooth scroll animation
- Scroll-to-bottom FAB when away from bottom

---

## Error Handling

| Error                        | User-facing message                                      |
| ---------------------------- | -------------------------------------------------------- |
| Server unreachable           | "Can't reach {server name}. Check your connection."      |
| Model not found              | "Model '{name}' is no longer available."                 |
| Context length exceeded      | "Conversation too long. Some older messages were trimmed."|
| Stream interrupted           | "Response was interrupted. Tap retry to try again."      |
| Rate limit (OpenRouter)      | "Rate limit reached. Please wait a moment."              |
| Generic API error           | Show raw error + "Tap to retry"                          |

---

## Performance Considerations

- **ListView.builder** for message list — only render visible
- **Markdown rendering** — lazy, only visible messages
- **Syntax highlighting** — cache highlighted blocks
- **Long conversations** — for 500+ messages, consider pagination

---

## Acceptance Criteria

- [ ] User can type and send a message.
- [ ] Response streams in real-time (LM Studio).
- [ ] Response streams in real-time (Ollama).
- [ ] Response streams in real-time (OpenRouter).
- [ ] Markdown renders correctly.
- [ ] Code blocks have syntax highlighting and copy button.
- [ ] User can copy a full message.
- [ ] User can retry a failed response.
- [ ] User can delete individual messages.
- [ ] Typing indicator shows while waiting.
- [ ] "Stop generating" button cancels stream.
- [ ] Scroll behavior follows spec.
- [ ] Long conversations (100+ messages) scroll smoothly.
- [ ] Errors display user-friendly messages with retry.
- [ ] Haptic feedback on send.
