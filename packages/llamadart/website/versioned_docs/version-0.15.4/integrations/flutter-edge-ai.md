---
title: Flutter Edge AI with GGUF
sidebar_label: Flutter Edge AI
description: Try the upstream source-only flutter_edge_ai_llama connector and understand its runtime and version boundaries.
---

Flutter Edge AI owns installation, active-model selection and app chat lifecycle.
Its optional `flutter_edge_ai_llama` provider uses llamadart for GGUF generation,
templates and runtime capabilities. The connector stays in
[DenisovAV/flutter_edge_ai](https://github.com/DenisovAV/flutter_edge_ai/tree/main/packages/flutter_edge_ai_llama);
it is not moved into this repository.

## Use the source example

As checked on **2026-10-18**, `flutter_edge_ai_llama 0.0.1` has `publish_to: none`
and no pub.dev release. There is no `flutter pub add flutter_edge_ai_llama`
installation route yet. Use the upstream workspace example, which supplies the
companion, platform runners and runtime configuration together.

The source baseline below is upstream main
`8a38ed4fff36714c038284ab9b0de79854bd829c`: Flutter Edge AI **2.4.0**,
llamadart **0.13.1**, GGUF Apple companion **0.13.0**. Its package floor is
Flutter **3.44 / Dart 3.12**; connector qualification uses Flutter **3.47.1 /
Dart 3.13.1**. Do not replace its constraint with 0.15.0: the separately reviewed
[upgrade PR #684](https://github.com/DenisovAV/flutter_edge_ai/pull/684) is still
pending. Its evidence does not make that combination an upstream release.

```bash
git clone https://github.com/DenisovAV/flutter_edge_ai.git
cd flutter_edge_ai
git switch --detach 8a38ed4fff36714c038284ab9b0de79854bd829c
cd packages/flutter_edge_ai_llama
python3 tool/fetch_test_model.py
cd example
flutter pub get
flutter run -d macos
```

For another supported native host, choose an available platform from
`flutter devices` and follow the
[pinned connector README](https://github.com/DenisovAV/flutter_edge_ai/blob/8a38ed4fff36714c038284ab9b0de79854bd829c/packages/flutter_edge_ai_llama/README.md).
The model fetcher downloads a checksum-verified 145 MB SmolLM2 smoke fixture
to `tool/fixtures/chat.gguf` in the connector directory.
You can use an existing compatible GGUF instead. Select the file, wait for
**Ready**, send “Say hello,” then try a follow-up, **Stop**, **New chat**, and
reopen the app. This exercises installation, generation, cancellation and reuse;
it does not qualify model quality or every device/GPU.

## API shape: register, install, stream, close

This excerpt matches the pinned source API. It requires Flutter initialization
and a real existing GGUF path; use the example app above for a complete UI.

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_llama/flutter_edge_ai_llama.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterEdgeAi.initialize(
    inferenceEngines: const [LlamaEngineProvider()],
  );
  await FlutterEdgeAi.installModel(
    modelType: ModelType.general,
    fileType: ModelFileType.gguf,
  ).fromFile('/absolute/path/to/chat.gguf').install();
  final model = await FlutterEdgeAi.getActiveModel(
    maxTokens: 2048,
    preferredBackend: PreferredBackend.cpu,
  );
  try {
    final chat = await model.openChat(maxOutputTokens: 128);
    await chat.addQuery(Message.text(text: 'Hello!', isUser: true));
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) print(response.token);
    }
  } finally {
    await model.close();
  }
}
```

`maxTokens` is the complete context budget, while `maxOutputTokens` bounds one
response. A Stop button calls `await chat.session.stopGeneration()` during
generation. Close the model when finished; let Edge AI own history rather than
nesting a llamadart `ChatSession`. Declare `ModelFileType.gguf` explicitly so
engine routing is unambiguous, even for extensionless paths.

## Platform setup and collisions

Use the pinned connector's
[platform guide](https://github.com/DenisovAV/flutter_edge_ai/blob/8a38ed4fff36714c038284ab9b0de79854bd829c/packages/flutter_edge_ai_llama/doc/platforms.md)
and [app setup](https://github.com/DenisovAV/flutter_edge_ai/blob/8a38ed4fff36714c038284ab9b0de79854bd829c/packages/flutter_edge_ai_llama/README.md#add-it-to-your-app)
when adapting the example. The configuration belongs in the **application** or
workspace root; dependency hook settings do not propagate.

- Select `llamadart_native_runtimes: [llama_cpp]`. Avoid loading llamadart's
  LiteRT-LM distribution alongside `flutter_edge_ai_litertlm`; native symbols
  and libraries can collide. A GGUF-only app omits both LiteRT-LM plugins.
- Apple apps add the direct GGUF companion matching the SDK minor, enable
  SwiftPM and use iOS 16.4+ / macOS 14+. The pinned example includes its
  entitlements. Mixed LiteRT-LM macOS CocoaPods/SwiftPM setup and App Store
  submission are not qualified by this recipe.
- The example uses Android API 28, arm64-v8a and x86_64; exclude armeabi-v7a.
  Windows needs the Visual C++ runtime for its architecture.
- For Web, run `python3 tool/fetch_web_assets.py` from the connector directory,
  then use its documented Chrome runner and deployment build. Serve HTML,
  workers and Wasm with COOP/COEP, allow CORS on model URLs, and install with
  `.fromNetwork(...)`. The connector does not accept OPFS streaming handles;
  `cacheApi`/network paths buffer models, with a roughly 2 GB ceiling that may
  be lower on a specific browser. Memory64 does not remove that storage limit.

## Supported features and pending work

The [advanced guide](https://github.com/DenisovAV/flutter_edge_ai/blob/8a38ed4fff36714c038284ab9b0de79854bd829c/packages/flutter_edge_ai_llama/doc/advanced_usage.md)
covers tools, thinking, compatible image/audio projectors and native LoRA.
These depend on the selected model/runtime; typed tool history is not a promise
of arbitrary strict JSON response-schema support. See the
[direct structured-output guide](../guides/generation-and-streaming#structured-json-output) when that is the
requirement.

GGUF embeddings/RAG through this connector are deferred. The upstream
[embedding SPI PR #685](https://github.com/DenisovAV/flutter_edge_ai/pull/685)
remains separate from this chat quickstart. Core's typed embedding-overflow
error ships in 0.15.1, while the pinned connector recipe still uses 0.13.1.
Neither establishes GGUF embeddings through this connector. Use
[direct embeddings](../guides/embeddings) or the
[Genkit retrieval guide](./genkit) for the available routes.
