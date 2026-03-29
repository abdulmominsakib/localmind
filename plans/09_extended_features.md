# Feature 09 — Extended Features

> **Phase:** 4 — Extended  
> **Status:** Pending  
> **Depends on:** `02_chat_interface`  

---

## Goal

Add advanced capabilities that elevate LocalMind from a basic chat client to a premium AI assistant tool.

---

## Features

### 1. AI Voice (Text-to-Speech)

**Package:** `flutter_tts`

**Implementation:**
- Add "Read Aloud" action to assistant messages (in action bar)
- Highlight text as it is being read (if feasible)
- Global setting to auto-read assistant responses
- TTS stops when navigating away or starting new generation
- Voice selection in settings (OS-dependent)

### 2. Context Smart Replies

**Implementation:**
- When assistant message completes, generate 2-3 suggested follow-up prompts
- Show as selectable chips above input bar
- Generation method: lightweight background prompt or rule-based suggestions
- Rule-based fallbacks: "Tell me more", "Explain simply", "Give an example"

### 3. Multimodal Support (Images/Documents)

**Packages:** `file_picker`, `image_picker`

**Implementation:**
- Update `Message` model to support `attachmentPaths`
- Add paperclip `[📎]` icon to `ChatInputBar`
- Allow selecting images (`.png`, `.jpg`)
- If model is multimodal (LLaVA, GPT-4o, Claude 3.5 Sonnet), encode image as Base64
- Display image thumbnails in user chat bubble

### 4. Tablet & Desktop Optimized Layout

**Implementation:**
- Detect screen width (`MediaQuery.of(context).size.width`)
- If width > 600px (tablet) or 900px (desktop):
  - Pin conversation drawer to left side permanently
  - Show `ChatPage` in remaining space
- Limit chat bubble width to ~800px, centered on wide screens

### 5. Export Conversation

**Implementation:**
- Add "Export Chat" option to conversation context menu
- Formats:
  - **Markdown (.md)**: Plain text export
  - **PDF**: Use `pdf` package to render chat history
- Use `share_plus` to share to other apps

### 6. Quick-Launch Shortcut / Widget

**Implementation:**
- Use `quick_actions` package for home screen shortcuts
- Add "New Chat" shortcut from OS launcher icon

---

## Feature Folder Structure

Extended features are organized within existing features or as new sub-features:

```
features/
├── chat/
│   └── views/components/
│       └── smart_reply_chips.dart     # Feature 2
│
├── settings/
│   └── views/
│       └── components/
│           └── voice_settings.dart    # Feature 1 (settings portion)
│
├── extended/                          # New feature for multimodal/export
│   ├── data/
│   ├── providers/
│   └── views/
│       ├── image_attachment_sheet.dart # Feature 3
│       └── export_dialog.dart         # Feature 5
```

---

## Implementation Notes

### TTS Integration

```dart
class TTSService {
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> speak(String text);
  Future<void> stop();
  Future<void> setVoice(String voiceId);

  // Events
  Stream<void> get onStart;
  Stream<void> get onComplete;
}
```

### Smart Reply Generation

```dart
class SmartReplyService {
  final ChatService _chatService;

  Future<List<String>> generateReplies({
    required Server server,
    required String modelId,
    required List<Message> conversation,
    required Persona? persona,
  });

  // Fallback suggestions
  static const List<String> fallbackSuggestions = [
    "Tell me more",
    "Can you explain this more simply?",
    "Give me an example",
    "What are the pros and cons?",
    "How does this work?",
  ];
}
```

### Image Attachment

```dart
class ImageAttachmentService {
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickImage();
  Future<String> encodeImageToBase64(String path);
  bool isMultimodalModel(String? modelId);
}
```

### Responsive Layout

```dart
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.chatPage,
    required this.drawer,
  });

  final Widget chatPage;
  final Widget drawer;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 900) {
      // Tablet/Desktop: Permanent drawer
      return Row(children: [drawer, Expanded(child: chatPage)]);
    }
    // Mobile: Drawer in scaffold
    return chatPage;
  }
}
```

---

## Acceptance Criteria

- [ ] TTS button reads message text aloud; can be stopped.
- [ ] Smart reply chips appear after completion and populate input when tapped.
- [ ] User can attach image and send to multimodal model.
- [ ] UI scales responsively on larger screens (persistent sidebar).
- [ ] User can export conversation to Markdown and share it.
- [ ] Quick action shortcuts available from OS launcher.
