# LocalMind

**Your AI. Your Device. Your Rules.**

LocalMind is a premium Flutter mobile application designed to provide a beautiful, fast, and privacy-respecting interface for local LLM servers and cloud providers.

![LocalMind Header Image](docs/cover.webp)
![LocalMind Screenshot](docs/app_screenshots.webp)

<p align="center">
  <a href="https://apps.apple.com/us/app/localmind-ollama-lm-studio/id6777025480">
    <img src="docs/appstore_download_button.svg" width="200" />
  </a>
  <a href="https://play.google.com/store/apps/details?id=pro.momin.localmind">
    <img src="docs/playstore_download_button.webp" width="200" />
  </a>
  <a href="https://github.com/abdulmominsakib/localmind/releases">
    <img src="docs/github_download_button.webp" width="200" />
  </a>
</p>

## Vision

Built for those who value privacy and performance, LocalMind connects directly to your local inference servers like **LM Studio** or **Ollama**, as well as cloud providers like **OpenRouter**. No middleware, no tracking, and no hidden subscriptions. Just you and your models.

## Key Features

- **On-Device AI Support (iOS & Android)**: Private, fast, and offline. Run powerful GGUF and LiteRT models (Gemma, Qwen, DeepSeek R1) directly on your device via `llamadart` and `flutter_gemma`. No internet connection required.
- **Model Context Protocol (MCP)**: Seamlessly connect to local or remote MCP servers. Grant models access to custom tools and integrations (e.g., file access, web APIs, shell actions) with fine-grained global and chat-level toggles.
- **Model Manager**: Download curated models or download GGUF models directly from HuggingFace. Manage model files directly within the app.
- **Multi-Server Connection**: Connect to Ollama, LM Studio, OpenRouter, or any OpenAI-compatible API with real-time server health and speed monitoring.
- **Premium Chat Experience**: A polished, Claude/ChatGPT-inspired user interface featuring:
  - **Streaming Responses**: Real-time SSE support for instant generation.
  - **Markdown Rendering**: Beautiful rendering of text and code with rich syntax highlighting.
  - **Expandable Reasoning Logs**: Collapsible, step-by-step visualization of thought processes for reasoning models like DeepSeek R1.
  - **Edit & Regenerate**: Edit past user prompts to truncate the conversation history and regenerate responses.
  - **Saved Messages Picker**: Quick-access shortcut in the input bar to store, organize, and reuse prompts or templates.
  - **Message Variants**: Swipe and navigate through alternative model replies/variations.
  - **Temporary Chats**: Incognito mode that allows conversations to run in-memory without saving logs to local history.
  - **Smart Suggested Replies**: Context-aware follow-up prompts to keep conversations going.
- **Voice & Audio (STT & TTS)**:
  - **Speech-to-Text (STT)**: Dictate your prompts directly via native voice input.
  - **Text-to-Speech (TTS)**: Listen to model responses with custom playback speeds, replay caching, and background play.
- **Multimodal & Attachments**: Attach photos, documents, and other files to prompt vision-capable models.
- **Persona Management**: Easily switch between specialized AI personas (Code Assistant, Math Tutor, etc.) or create your own with custom system instructions.
- **Live Model Swapping**: Swap active models mid-conversation without breaking context or losing chat history.
- **Conversation History**: Full-text search through your chats, folder grouping, pinning, and local-only storage.
- **Backup & Restore**: Export and import complete backup archives (including chat history, personas, and app settings) locally.
- **Deep Customization**:
  - **Theming**: Premium dark-first interface with full light mode support.
  - **Chat Parameters**: Fine-tune temperature, top_p, max token limits, and context window size.

## Tech Stack

LocalMind is built with modern, scalable technologies:

- **Framework**: [Flutter](https://flutter.dev/) (Latest Stable)
- **On-Device AI**: `llamadart` + `flutter_gemma` (supporting llama.cpp & LiteRT) for native, high-performance localized inference.
- **UI Components**: Shadcn-inspired design system (`shadcn_ui`)
- **State Management**: [Riverpod](https://riverpod.dev/) for robust, testable state.
- **Local Storage**: [ObjectBox](https://objectbox.io/) (and Hive) for high-performance on-device persistence.
- **Networking**: [Dio](https://pub.dev/packages/dio) for optimized REST API handling.
- **Rendering**: `gpt_markdown` + `syntax_highlight` for rich content.

## Privacy First

- **Zero Analytics**: We don't track how you use the app.
- **Local Storage**: Your conversations are stored only on your device, encrypted via Hive.
- **Direct Traffic**: Network requests go directly to _your_ servers. LocalMind never sees your data.

## Contributors

We are incredibly grateful to the developers who have helped build LocalMind:

<p align="left">
  <a href="https://github.com/abdulmominsakib">
    <img src="https://github.com/abdulmominsakib.png?size=100" width="50" height="50" style="border-radius: 50%; margin-right: 4px;" title="Abdul Momin Sakib (abdulmominsakib)" alt="Abdul Momin Sakib"/>
  </a>
  <a href="https://github.com/onlypuppy7">
    <img src="https://github.com/onlypuppy7.png?size=100" width="50" height="50" style="border-radius: 50%; margin-right: 4px;" title="onlypuppy7" alt="onlypuppy7"/>
  </a>
  <a href="https://github.com/leo-rnl">
    <img src="https://github.com/leo-rnl.png?size=100" width="50" height="50" style="border-radius: 50%; margin-right: 4px;" title="Léo Reynal (leo-rnl)" alt="Léo Reynal"/>
  </a>
  <a href="https://github.com/dtrknt15">
    <img src="https://github.com/dtrknt15.png?size=100" width="50" height="50" style="border-radius: 50%; margin-right: 4px;" title="dtrknt15" alt="dtrknt15"/>
  </a>
  <a href="https://github.com/NJannasch">
    <img src="https://github.com/NJannasch.png?size=100" width="50" height="50" style="border-radius: 50%; margin-right: 4px;" title="Nils Jannasch (NJannasch)" alt="Nils Jannasch"/>
  </a>
  <a href="https://github.com/ystartgo">
    <img src="https://github.com/ystartgo.png?size=100" width="50" height="50" style="border-radius: 50%; margin-right: 4px;" title="ystartgo" alt="ystartgo"/>
  </a>
</p>

## Roadmap (Future Plans)

LocalMind is rapidly evolving. Here is what's coming next:

- [x] **AI Voice (Text-to-Speech)**: Listen to your AI's responses with high-quality TTS.
- [x] **Context Smart Replies**: Integrated suggested follow-ups to keep the conversation flowing.
- [x] **Multimodal Support**: Attach images and documents for vision-capable models.
- [x] **Tablet/Desktop Optimization**: A split-view layout for large-screen productivity.
- [x] **Export Options**: Export your chats to Markdown or PDF to share or archive.
- [ ] **Quick Shortcuts**: OS-level widgets and shortcuts for launching new chats instantly.
- [x] **Voice-to-Voice Mode**: Engage in real-time, low-latency spoken conversations with local models.
- [x] **S3 Cloud Sync**: End-to-end encrypted cloud sync for settings, custom personas, and chats in your own S3 server.

## Getting Started

### Prerequisites

- Flutter SDK (latest stable)
- A running local LLM server (e.g., [Ollama](https://ollama.com/) or [LM Studio](https://lmstudio.ai/))

### Installation

1. Clone the repository: `git clone https://github.com/abdulmominsakib/localmind.git`
2. Install dependencies: `flutter pub get`
3. Run the app: `flutter run`

---

## License

LocalMind is open source and available under the MIT License. Contributions are welcome!
