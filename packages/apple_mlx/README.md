# Apple MLX Support (`apple_mlx`)

Local package collecting experimental Dart wrappers around `lib_mlx`,
`speech_mlx`, and `mlx_audio`.

> **Development status:** Native LLM inference is disabled in LocalMind. The
> current `lib_mlx` 0.1.1 dependency ships a mock model core that returns stub
> responses; it does not execute downloaded MLX weights. Its bridge targets
> iOS only. The speech dependencies target macOS Apple Silicon and are not
> integrated into the LocalMind mobile app.

## Capabilities

### 1. LLM Text Generation (`AppleMlxLlmManager` & `lib_mlx`)
- **Prototype only**: Exercises the native lifecycle and local OpenAI-compatible
  HTTP/SSE contract against the upstream mock core.
- **Not user-facing**: `AppleMlxCapabilities.nativeLlmInferenceAvailable` stays
  `false` until a real, device-validated backend replaces the mock.

### 2. Speech-To-Text (`AppleMlxSpeechManager` & `speech_mlx` / `mlx_audio`)
- **macOS only**: These dependencies do not provide iOS speech inference.
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

The following example is for bridge development and contract testing only. It
does not perform real inference with `lib_mlx` 0.1.1.

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
