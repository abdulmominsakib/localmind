---
title: "Tutorial: build a Flutter chat app"
sidebar_label: Flutter chat app
description: Build a Flutter app that downloads a model on first run, streams replies into a chat UI on the device, and cleans up the engine correctly.
---

This tutorial builds a minimal chat app: it downloads a small model on first
launch, shows download progress, streams the reply token by token, lets you
stop generation, and releases the engine when the screen closes.

## 1. Create the app

```bash
flutter create local_chat
cd local_chat
flutter pub add llamadart
```

Then apply the platform setup:

- **iOS and macOS:** raise the deployment targets as described in
  [Installation](../getting-started/installation#flutter-ios-and-macos-setup).
- **macOS:** the app downloads the model, so add the outgoing network
  entitlement to both `macos/Runner/DebugProfile.entitlements` and
  `macos/Runner/Release.entitlements`:

  ```xml
  <key>com.apple.security.network.client</key>
  <true/>
  ```

- **Android:** release builds need
  `<uses-permission android:name="android.permission.INTERNET"/>` in
  `android/app/src/main/AndroidManifest.xml`.
- **Web:** load the WebGPU bridge in `web/index.html`; see
  [Add the bridge to your app](../platforms/webgpu-bridge#add-the-bridge-to-your-app).

## 2. Replace `lib/main.dart`

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';

const String modelUri =
    'hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf';

void main() {
  runApp(const LocalChatApp());
}

class LocalChatApp extends StatelessWidget {
  const LocalChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local chat',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  ChatMessage({required this.fromUser, this.text = ''});

  final bool fromUser;
  String text;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final LlamaEngine _engine = LlamaEngine(LlamaBackend());
  final ModelDownloadCancelToken _downloadCancel = ModelDownloadCancelToken();
  final TextEditingController _input = TextEditingController();
  final List<ChatMessage> _messages = <ChatMessage>[];

  ChatSession? _session;
  double? _downloadFraction;
  String _status = 'Starting...';
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadModel());
  }

  Future<void> _loadModel() async {
    setState(() => _status = 'Downloading model...');
    try {
      await _engine.loadModelSource(
        ModelSource.parse(modelUri),
        modelParams: const ModelParams(contextSize: 2048),
        // Web backends own the download and reject cancellation tokens.
        options: kIsWeb
            ? ModelLoadOptions.defaults
            : ModelLoadOptions(cancelToken: _downloadCancel),
        onProgress: (ModelDownloadProgress progress) {
          if (mounted) {
            setState(() => _downloadFraction = progress.fraction);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _session = ChatSession(
          _engine,
          systemPrompt: 'You are a helpful, concise assistant.',
        );
        _status = 'Ready';
      });
    } on LlamaException catch (error) {
      if (mounted) {
        setState(() => _status = 'Failed to load model: ${error.message}');
      }
    }
  }

  Future<void> _send() async {
    final ChatSession? session = _session;
    final String text = _input.text.trim();
    if (session == null || text.isEmpty || _generating) return;

    final ChatMessage reply = ChatMessage(fromUser: false);
    setState(() {
      _input.clear();
      _messages
        ..add(ChatMessage(fromUser: true, text: text))
        ..add(reply);
      _generating = true;
    });

    try {
      await for (final LlamaCompletionChunk chunk in session.create(
        <LlamaContentPart>[LlamaTextContent(text)],
        params: const GenerationParams(maxTokens: 256, temp: 0.7),
      )) {
        final String? delta = chunk.choices.first.delta.content;
        if (delta != null && mounted) {
          setState(() => reply.text += delta);
        }
      }
    } on LlamaException catch (error) {
      if (mounted) {
        setState(() => reply.text += '\n[error: ${error.message}]');
      }
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  void _stop() {
    _engine.cancelGeneration();
  }

  @override
  void dispose() {
    _downloadCancel.cancel();
    _engine.cancelGeneration();
    unawaited(_engine.dispose());
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool ready = _session != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Local chat')),
      body: Column(
        children: <Widget>[
          if (!ready) ...<Widget>[
            LinearProgressIndicator(value: _downloadFraction),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_status),
            ),
          ],
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (BuildContext context, int index) {
                final ChatMessage message = _messages[index];
                return Align(
                  alignment: message.fromUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(message.text.isEmpty ? '...' : message.text),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: ready && !_generating,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask something',
                      ),
                    ),
                  ),
                  if (_generating)
                    IconButton(
                      icon: const Icon(Icons.stop),
                      onPressed: _stop,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: ready ? _send : null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Run it with `flutter run`. The first launch downloads the model into the
package cache; later launches load it from there.

## How it works

- **One engine per screen.** `_ChatScreenState` owns the `LlamaEngine`.
  `State.dispose` cancels any running download and generation, then disposes
  the engine. An engine holds one model at a time.
- **Download with progress.** `loadModelSource` resolves the `hf://` reference,
  downloads it with resume support and reports `ModelDownloadProgress`.
  `fraction` is `null` while the total size is unknown, which
  `LinearProgressIndicator` shows as indeterminate. Web backends download
  through the browser and reject a cancel token, so the app passes one only on
  native targets.
- **Multi-turn chat.** `ChatSession` keeps the conversation history and
  applies the model's chat template. Each `create` call streams
  `LlamaCompletionChunk`s; the app appends `delta.content` to the last message.
- **Stop.** `cancelGeneration()` ends the stream normally, without an
  exception. The partial reply stays in the session history, so the next turn
  continues the conversation.
- **Errors.** Load and generation failures throw subclasses of
  `LlamaException`; the app shows `error.message`.

## Next steps

- The model here, SmolLM2 135M, is only good for checking the pipeline. Pick a
  real model in [Finding models](../getting-started/finding-models) and
  [Model families](../getting-started/model-families).
- Reasoning models also stream `delta.thinking`; see
  [Text generation and streaming](../guides/generation-and-streaming).
- For a richer download UI with retry and cache inspection, use
  `ModelDownloadController`; see
  [Download and cache models](../guides/model-downloads).
- The [chat app example](../examples/chat-app) is a full app with model
  management, multimodal input and speech.
