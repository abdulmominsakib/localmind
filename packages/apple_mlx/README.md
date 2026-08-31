# Apple MLX Support (`apple_mlx`)

Local package integrating Apple's **MLX** ecosystem (`lib_mlx`, `speech_mlx`, `mlx_audio`, and `mlx-c`) with Dart & Flutter to run LLM Text Generation, Speech-to-Text, and Text-to-Speech natively on Apple Silicon (iOS and macOS).

## Capabilities

### 1. LLM Text Generation (`AppleMlxLlmManager` & `lib_mlx`)
- **Native Apple Silicon Inference**: Runs quantized MLX models (Gemma, Llama 3.2, Qwen 2.5, SmolLM2) directly on device via Unified Memory and Metal.
- **OpenAI-Compatible Local Endpoint**: Zero-overhead localhost HTTP/SSE streaming client.
- **Reasoning / Thinking Support**: Separates `<thinking>` tokens from final assistant content.
- **Tool Calling Support**: Function and tool calling protocol.

### 2. Speech-To-Text (`AppleMlxSpeechManager` & `speech_mlx` / `mlx_audio`)
- **Parakeet-TDT & Whisper**: High-accuracy local speech recognition.
- **Isolate Offloading**: Dedicated worker isolates keep audio processing and resampling off the UI isolate.

### 3. Text-To-Speech (`PocketTTS`)
- **Neural Voice Synthesis**: Real-time voice generation with incremental PCM streaming.
- **Voices**: Built-in multi-voice support (`alba`, `marius`, `javert`, `jean`).

### 4. Conversational Turn Detection (`SmartTurn`)
- **Smart Turn v3.2**: Sub-millisecond endpoint classifier to determine whether a speaker finished speaking during a voice conversation.

---

## Quickstart

### LLM Text Generation

```dart
import 'package:apple_mlx/apple_mlx.dart';

Future<void> main() async {
  final llm = AppleMlxLlmManager();

  // 1. Load MLX model and launch local server
  final serverInfo = await llm.loadAndStartServer(
    modelPath: '/path/to/mlx-community/gemma-4-e2b-it-4bit',
    modelId: AppleMlxModelIds.gemma4E2b,
    thinkingEnabled: true,
  );
  print('MLX Server running on ${serverInfo.baseUrl}');

  // 2. Stream generation
  final stream = llm.generateStream(
    messages: [
      {'role': 'user', 'content': 'Explain quantum computing in simple terms.'},
    ],
    temperature: 0.7,
  );

  await for (final delta in stream) {
    if (delta.reasoningContent != null) {
      print('[Thinking] ${delta.reasoningContent}');
    }
    if (delta.content != null) {
      print(delta.content);
    }
  }

  // 3. Clean up
  await llm.dispose();
}
```

### STT and TTS Audio

```dart
import 'package:apple_mlx/apple_mlx.dart';

Future<void> main() async {
  final speech = AppleMlxSpeechManager();
  await speech.initialize();

  // Transcribe audio
  final text = await speech.transcribeWavFile('input.wav');
  print('Transcript: $text');

  // Synthesize voice
  await speech.synthesizeToWav(
    text: 'Hello from Apple MLX on LocalMind!',
    outputPath: 'output.wav',
    voice: 'alba',
  );

  await speech.dispose();
}
```
