# LocalMind

**Your AI. Your Device. Your Rules.**

LocalMind is a premium Flutter mobile application designed to provide a beautiful, fast, and privacy-respecting interface for local LLM servers and cloud providers.

![LocalMind Header Image](docs/cover.webp)
![LocalMind Screenshot](docs/app_screenshots.webp)

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=pro.momin.localmind">
    <img src="docs/playstore_download_button.webp" width="200" />
  </a>
  <a href="https://github.com/abdulmominsakib/localmind/releases">
    <img src="docs/github_download_button.webp" width="200" />
  </a>
</p>

## 🚀 Vision

Built for those who value privacy and performance, LocalMind connects directly to your local inference servers like **LM Studio** or **Ollama**, as well as cloud providers like **OpenRouter**. No middleware, no tracking, and no hidden subscriptions. Just you and your models.

## ✨ Key Features

- 📲 **On-Device AI Support (Android)**: Private, fast, and offline. Run powerful AI models directly on your device with no internet required.
- 📂 **Model Manager**: Download and manage curated models like Qwen 3 (0.6B), DeepSeek R1, and Gemma 4 directly within the app.
- 🖥️ **Multi-Server Connection**: Seamlessly connect to LM Studio, Ollama, or OpenRouter with real-time health monitoring.
- 💬 **Premium Chat Experience**: A polished, ChatGPT/Claude-inspired interface with:
  - **Streaming Responses**: Real-time SSE support for instant feedback.
  - **Markdown Rendering**: Beautiful rendering of text and code with syntax highlighting.
  - **Message Actions**: Copy, retry, or delete individual messages with a long-press menu.
- 🎨 **Revamped Sidebar**: A cleaner, more intuitive, and feature-rich navigation experience.
- 🧠 **Persona Management**: Switch between specialized AI personas (Code Assistant, Math Tutor, etc.) or create your own with custom system prompts.
- 🔄 **Live Model Swapping**: Change the active model mid-conversation without losing context.
- 📦 **Conversation History**: Full-text search through your past chats, pinning important conversations, and local-only storage.
- 🎨 **Deep Customization**:
  - **Theming**: Premium dark-first design (with light mode support).
  - **Chat Parameters**: Fine-tune temperature, top_p, max tokens, and context length.

## 🛠️ Tech Stack

LocalMind is built with modern, scalable technologies:

- **Framework**: [Flutter](https://flutter.dev/) (Latest Stable)
- **On-Device AI**: [LiteRT (TensorFlow Lite)](https://ai.google.dev/edge/litert) for high-performance localized inference.
- **UI Components**: Shadcn-inspired design system (`shadcn_ui`)
- **State Management**: [Riverpod](https://riverpod.dev/) for robust, testable state.
- **Local Storage**: [ObjectBox](https://objectbox.io/) (and Hive) for high-performance on-device persistence.
- **Networking**: [Dio](https://pub.dev/packages/dio) for optimized REST API handling.
- **Rendering**: `flutter_markdown` + `flutter_highlight` for rich content.

## 🛡️ Privacy First

- **Zero Analytics**: We don't track how you use the app.
- **Local Storage**: Your conversations are stored only on your device, encrypted via Hive.
- **Direct Traffic**: Network requests go directly to _your_ servers. LocalMind never sees your data.

## 🗺️ Roadmap (Future Plans)

LocalMind is rapidly evolving. Here is what's coming next:

- [ ] **AI Voice (Text-to-Speech)**: Listen to your AI's responses with high-quality TTS.
- [ ] **Context Smart Replies**: Integrated suggested follow-ups to keep the conversation flowing.
- [ ] **Multimodal Support**: Attach images and documents for vision-capable models.
- [ ] **Tablet/Desktop Optimization**: A split-view layout for large-screen productivity.
- [ ] **Export Options**: Export your chats to Markdown or PDF to share or archive.
- [ ] **Quick Shortcuts**: OS-level widgets and shortcuts for launching new chats instantly.

## 🛠️ Getting Started

### Prerequisites

- Flutter SDK (latest stable)
- A running local LLM server (e.g., [Ollama](https://ollama.com/) or [LM Studio](https://lmstudio.ai/))

### Installation

1. Clone the repository: `git clone https://github.com/abdulmominsakib/localmind.git`
2. Install dependencies: `flutter pub get`
3. Run the app: `flutter run`

---

## 📄 License

LocalMind is open source and available under the MIT License. Contributions are welcome!
