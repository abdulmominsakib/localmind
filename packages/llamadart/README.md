# llamadart

[![pub package](https://img.shields.io/pub/v/llamadart.svg)](https://pub.dev/packages/llamadart)
[![API docs](https://img.shields.io/badge/API-pub.dev-blue.svg)](https://pub.dev/documentation/llamadart/latest/)
[![Docs](https://img.shields.io/badge/docs-website-blue.svg)](https://llamadart.leehack.com/docs/intro)

Run local LLMs from Dart and Flutter with one API across native and web
runtimes. `llamadart` routes GGUF models through llama.cpp and `.litertlm`
models through LiteRT-LM.

## Start Here

| Need | Link |
| --- | --- |
| Install the package | [Installation](https://llamadart.leehack.com/docs/getting-started/installation) |
| Load a first model | [Quickstart](https://llamadart.leehack.com/docs/getting-started/quickstart) |
| Build chat history | [First chat session](https://llamadart.leehack.com/docs/getting-started/first-chat-session) |
| Check runtime support | [Platform & backend matrix](https://llamadart.leehack.com/docs/platforms/support-matrix) |
| Read API reference | [pub.dev API docs](https://pub.dev/documentation/llamadart/latest/) |
| Try the Flutter demo | [Hosted chat app](https://llamadart.leehack.com/) |

## What It Supports

- GGUF model loading and generation through llama.cpp.
- `.litertlm` model loading and generation through LiteRT-LM.
- Native Dart and Flutter targets with downloaded runtime assets.
- Flutter Web through the experimental WebGPU bridge and LiteRT-LM web runtime.
- Streaming chat completions, llama.cpp thinking budgets, tool-call parsing,
  multimodal GGUF projectors, structured JSON output, embeddings, LoRA, state
  persistence, and runtime diagnostics where the active backend supports them.

Unsupported runtime/option combinations are rejected explicitly instead of
silently degrading. Check the support matrix before relying on a capability for
a specific model format or platform.

## Requirements

- Dart SDK `>=3.10.7`
- Flutter SDK `>=3.38.0` for Flutter apps
- iOS deployment target `16.4` or newer for Flutter iOS apps
- macOS deployment target `14.0` or newer for Flutter macOS apps

Consumers do not need a local C++ toolchain. Native runtime archives are
resolved by the package build hook on first build or run.

## Install

For Dart or Flutter apps:

```yaml
dependencies:
  llamadart: ^0.8.18
```

Flutter iOS/macOS apps that should link Apple XCFrameworks through Swift
Package Manager should also add the runtime companion packages they need:

```yaml
dependencies:
  llamadart: ^0.8.18
  llamadart_llama_cpp_flutter: ^0.0.12 # GGUF / llama.cpp
  llamadart_litert_lm_flutter: ^0.0.8 # Apple .litertlm / LiteRT-LM targets
```

The LiteRT-LM companion manifest includes consolidated iOS and macOS SwiftPM
runtime targets. Llamadart uses that SwiftPM path for iOS; Flutter macOS
LiteRT-LM builds currently keep the core package's native-assets fallback while
the hook path remains responsible for the complete runtime.

Then run:

```bash
dart pub get
# or
flutter pub get
```

## First Generation

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModelSource(
      ModelSource.parse(
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
        'SmolLM2-135M-Instruct-Q2_K.gguf',
      ),
    );

    final output = StringBuffer();
    await for (final chunk in engine.create(
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Explain local inference in one sentence.',
        ),
      ],
      params: const GenerationParams(maxTokens: 48),
    )) {
      final text = chunk.choices.first.delta.content;
      if (text != null) {
        output.write(text);
      }
    }
    print(output.toString());
  } finally {
    await engine.dispose();
  }
}
```

For multi-turn chat, wrap the same engine in `ChatSession` and let it maintain
history:
[First chat session](https://llamadart.leehack.com/docs/getting-started/first-chat-session).

## Choosing a Runtime

| Model format | Typical use | Runtime |
| --- | --- | --- |
| GGUF | Broad llama.cpp compatibility, Metal/Vulkan/CUDA/CPU, WebGPU bridge | llama.cpp |
| `.litertlm` | LiteRT-LM deployments, Android GPU/NPU-oriented bundles, Gemma-family LiteRT packages | LiteRT-LM |

`LlamaBackend()` routes by model file type. Use `ModelParams` for load-time
controls such as context size, GPU layers, backend preference, LiteRT-LM backend
selection, and WebGPU mem64 hints. See
[Runtime Parameters](https://llamadart.leehack.com/docs/configuration/runtime-parameters)
for the full list.

Current default runtime pins:

| Runtime | Pin |
| --- | --- |
| Native llama.cpp / GGUF | `leehack/llamadart-native@b10276` |
| Native LiteRT-LM / `.litertlm` | `leehack/litert-lm-native@v0.15.0-native.3` |
| Web llama.cpp / GGUF | `leehack/llama-web-bridge-assets@v0.1.26` |
| Web LiteRT-LM / `.litertlm` | `@litert-lm/core@0.15.0` |

## Common Tasks

| Task | Docs |
| --- | --- |
| Resolve local paths, URLs, and Hugging Face sources | [Finding models](https://llamadart.leehack.com/docs/getting-started/finding-models) |
| Pick native/Web/LiteRT backends | [Backend selection](https://llamadart.leehack.com/docs/guides/backend-selection) |
| Stream text and collect output | [Generation and streaming](https://llamadart.leehack.com/docs/guides/generation-and-streaming) |
| Generate typed JSON | [Structured output](https://llamadart.leehack.com/docs/guides/generation-and-streaming#structured-json-output) |
| Use tool calling | [Tool calling](https://llamadart.leehack.com/docs/guides/tool-calling) |
| Use images, audio, or projectors | [Multimodal](https://llamadart.leehack.com/docs/guides/multimodal) |
| Generate embeddings | [Embeddings](https://llamadart.leehack.com/docs/guides/embeddings) |
| Load LoRA adapters | [LoRA adapters](https://llamadart.leehack.com/docs/guides/lora-adapters) |
| Save and restore KV state | [API levels](https://llamadart.leehack.com/docs/guides/api-levels) |
| Run Flutter Web / WebGPU | [WebGPU bridge](https://llamadart.leehack.com/docs/platforms/webgpu-bridge) |
| Tune performance | [Performance tuning](https://llamadart.leehack.com/docs/guides/performance-tuning) |

## Examples

- [Basic Dart CLI](https://github.com/leehack/llamadart/tree/main/example/basic_app)
- [Flutter chat app](https://github.com/leehack/llamadart/tree/main/example/chat_app)
- [HTTP server example](https://github.com/leehack/llamadart/tree/main/example/llamadart_server)
- [TUI coding agent example](https://github.com/leehack/llamadart/tree/main/example/tui_coding_agent)

## Validate Changes

For package changes:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
dart test -p vm -j 1 --exclude-tags local-only
dart test -p chrome --exclude-tags local-only
```

For docs changes:

```bash
dart run tool/testing/verify_release_docs_versions.dart
./tool/docs/build_site.sh
./tool/docs/validate_links.sh
```

For heavier local model checks, list the discoverable scenarios:

```bash
dart run tool/testing/run_local_e2e.dart --list
dart run tool/testing/test_matrix.dart --list
```

## Contributing

Keep public behavior, examples, README, website docs, support matrices, and
changelog entries aligned. For non-trivial PRs, record the relevant testing
matrix rows and exact validation evidence in the PR body.

## License

MIT. See [LICENSE](https://github.com/leehack/llamadart/blob/main/LICENSE).
