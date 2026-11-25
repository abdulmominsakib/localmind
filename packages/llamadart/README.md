# llamadart

[![pub package](https://img.shields.io/pub/v/llamadart.svg)](https://pub.dev/packages/llamadart)
[![API docs](https://img.shields.io/badge/API-pub.dev-blue.svg)](https://pub.dev/documentation/llamadart/latest/)
[![Docs](https://img.shields.io/badge/docs-website-blue.svg)](https://llamadart.leehack.com/docs/intro)

`llamadart` is a Dart package for on-device inference. It runs GGUF models
through `llama.cpp` and `.litertlm` bundles through LiteRT-LM, on Android, iOS,
macOS, Linux, Windows and the web, behind one Dart API. Web support is
experimental. Native targets need no network once the model is on the device.

- Streaming chat and text generation, with structured JSON output and cancellable task handles.
- Tool calling driven by the model's chat template.
- Embeddings, reranking, and image and audio input with multimodal models.
- Speech to text (including incremental live PCM streaming on native `llama.cpp` via `LlamaCppLiveAsrAdapter` for Voxtral Realtime and LFM3-Audio, opt-in bounded windowed live PCM via `Qwen3WindowedAsrAdapter` for Qwen3-ASR, and on native LiteRT-LM), text to speech (Qwen3-TTS; LFM3-Audio, Soprano, Chatterbox and Pocket TTS on native; experimental PCM streaming for Qwen3-TTS, LFM3-Audio and Pocket TTS), and decision models with cooperative task cancellation.
- Image generation from text prompts on native platforms (Preview).
- Runtime LoRA adapters for llama.cpp, observability hooks and typed capability checks.

Choose [direct llamadart, Genkit, or Flutter Edge AI](https://llamadart.leehack.com/docs/integrations/choosing-an-api)
for your application. Genkit is a
[separate package](https://github.com/leehack/llamadart/tree/main/packages/genkit_llamadart);
the Flutter Edge AI connector is owned upstream and pins its own llamadart
version.

All five engine types implement `LlamadartEngine<C extends EngineCapabilities>`
for shared capability inspection and disposal. Keep loading and requests on the
concrete engine; see [shared lifecycle ownership](https://llamadart.leehack.com/docs/guides/model-lifecycle#shared-engine-ownership).

LFM2 Python-style tool calls use declared argument types and preserve copied string backslashes; see [tool calling](https://llamadart.leehack.com/docs/guides/tool-calling). The automatic grammar preserves copied singleton string spellings and can use an existing Python arguments wrapper for unambiguous JSON-escaped string values. Foreign XML closing tags remain raw diagnostics with no executable calls.
Native llama.cpp applies schema-directed lazy grammar to LFM2 automatic Python tool calls. Web additionally requires bridge assets v0.1.82+ with a loaded-core prompt-penalty capability; older runtimes reject before inference.
Native LiteRT-LM enforces strict JSON Schema output for Qwen3 and Gemma 4 on the macOS arm64 CPU and GPU, the iOS arm64 CPU, the Android arm64 CPU and GPU, the Linux x64 and Windows x64 GPU and CPU, and the Linux arm64 CPU, and for Qwen3 on the iOS arm64 GPU (Gemma 4 cannot create a GPU engine there; per-host model evidence in the structured-output guide), for the schemas llama.cpp's GBNF converter also enforces; see [structured output](https://llamadart.leehack.com/docs/guides/generation-and-streaming#structured-json-output) and the [support matrix](https://llamadart.leehack.com/docs/platforms/support-matrix).
LFM2 replies cut off at a reported length limit expose raw `partialToolCalls` diagnostics separately from executable calls and history. LFM2 tool markers inside reasoning stay in reasoning and produce no executable calls. Explicit parallel-tool requests reach supported Dart tool grammars even when template probes do not recognize parallel history.

## Install

```yaml
dependencies:
  llamadart: ^0.20.8
```

```bash
dart pub get
# or
flutter pub get
```

Requirements: Dart SDK `>=3.10.7`; for Flutter apps, Flutter SDK `>=3.38.6`,
iOS deployment target `16.4` and macOS deployment target `14.0` or newer.
Consumers need no local C++ toolchain: the package build hook resolves native
runtime archives on first build or run. Windows and other per-platform notes:
[Installation](https://llamadart.leehack.com/docs/getting-started/installation).

Flutter iOS and macOS apps that link the Apple XCFrameworks through Swift
Package Manager add the companion packages for the runtimes they use. A
companion shares its core's `MAJOR.MINOR` and constrains `llamadart` to it.

```yaml
dependencies:
  llamadart: ^0.20.8
  llamadart_llama_cpp_flutter: ^0.20.8 # GGUF / llama.cpp
  llamadart_litert_lm_flutter: ^0.20.8 # Apple .litertlm / LiteRT-LM targets
  llamadart_stable_diffusion_flutter: ^0.20.8 # Apple image generation, opt-in
```

Pairing rules, the SwiftPM bootstrap and the privacy manifest are in
[Installation](https://llamadart.leehack.com/docs/getting-started/installation) and
[Apple setup](https://llamadart.leehack.com/docs/platforms/apple-setup).
Web apps run `dart run llamadart:web_setup` once; see the
[WebGPU bridge](https://llamadart.leehack.com/docs/platforms/webgpu-bridge).
Pages with neither cross-origin isolation nor usable `SharedArrayBuffer`
automatically use the single-threaded GGUF core with bridge assets v0.1.93+.
It uses one CPU
thread and supports WebGPU offload. Serve COOP/COEP headers to enable shared
memory for the threaded core and fetch-backed model loading. Set
`window.__llamadartBridgeAllowSingleThreadCore = false` before the first model
load to require the threaded core. Lazy tool-call grammars and
custom grammar roots follow the loaded core's `lazyGrammar` capability.
With bridge assets v0.1.93+, Chromium automatically uses JavaScript-backed
GGUF and projector staging on confirmed memory64 cores when `modelBytesHint`
is at most 4 GiB. On confirmed wasm32 single-thread cores, the automatic policy
uses JavaScript-backed staging for hints above 960 MiB through 3.75 GiB and
rejects larger hints before downloading. Other loads follow the bridge's
browser policy.
Set `ModelParams.jsBackedModelStaging: false` to disable staging or `true` to
require it with staging-capable v0.1.92+ assets.

llamadart also ships [agent skills](https://dart.dev/tools/pub/package-skills)
that teach coding agents its APIs. Install them from your app's root:

```bash
dart run skills@ get
```

To check a desktop setup without a model, run `dart run llamadart:doctor`; see
[setup report scope](https://llamadart.leehack.com/docs/platforms/diagnose-setup#desktop-setup-report).

Hosts bundling a Linux Vulkan runtime can preflight the system loader with
`probeLinuxVulkanUnavailableReason()` from `package:llamadart/backend.dart`;
see [API levels](https://llamadart.leehack.com/docs/guides/api-levels).
Native llama.cpp automatically skips unavailable Vulkan initialization on Linux
under `GpuBackend.auto`, retaining the other bundled backends. An explicit
`GpuBackend.vulkan` load reports `LlamaUnsupportedException` with a remedy.

## First generation

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = await LlamaEngine.load(
    LlamaModel(
      ModelSource.parse(
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
        'SmolLM2-135M-Instruct-Q2_K.gguf',
      ),
    ),
  );

  try {
    final reply = await engine.create(
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Explain local inference in one sentence.',
        ),
      ],
      params: const GenerationParams(maxTokens: 48),
    ).text();
    print(reply);
  } finally {
    await engine.dispose();
  }
}
```

Dispose every engine before a native host calls C `exit()`; see
[Model lifecycle](https://llamadart.leehack.com/docs/guides/model-lifecycle). For multi-turn chat, wrap the
engine in `ChatSession`:
[First chat session](https://llamadart.leehack.com/docs/getting-started/first-chat-session).

## Runtimes and platforms

`LlamaBackend()` routes by model file type. After a model loads,
`engine.runtime` names the runtime and `await engine.capabilities` reports what
it supports, so branch on those instead of the file extension. Unsupported
runtime and option combinations are rejected with `LlamaUnsupportedException`
instead of silently degrading.

| Model format | Typical use | Runtime |
| --- | --- | --- |
| GGUF | Broad llama.cpp compatibility, Metal/Vulkan/CUDA/CPU, WebGPU bridge | llama.cpp |
| `.litertlm` | LiteRT-LM deployments, Android GPU/NPU-oriented bundles, Gemma-family LiteRT packages | LiteRT-LM |

llama.cpp uses Metal on Apple platforms, Vulkan on Linux and Windows, and
WebGPU in the browser. Android Vulkan is experimental and opt-in.

A llama.cpp runtime older than ggml `0.28.0` (llamadart-native `v0.8.0`)
limits native Qwen3.5 on Android Vulkan to ordinary text on some GPUs; the
bundled runtime does not. See [Android Vulkan](https://llamadart.leehack.com/docs/platforms/known-platform-issues#android).

LiteRT-LM can also use GPU and, on compatible Android deployments, NPU.
Android 12+ apps targeting API 31+ must request the optional vendor OpenCL
library in their manifest; see [Android LiteRT-LM setup](https://llamadart.leehack.com/docs/getting-started/installation#android-litert-lm-setup).
The opt-in llama.cpp `opencl` module on Android needs the same declaration;
without it the module cannot load, `ComputeDevice.auto` runs elsewhere and
`ComputeDevice.gpu` with `GpuBackend.opencl` throws. ggml-opencl admits only
Adreno (and Intel) GPUs.
GPU support still depends on the device, driver and model. If GPU engine
creation fails, `ComputeDevice.auto` retries on the CPU with a warning;
`ComputeDevice.gpu` fails instead.

Image generation is not available on the web. The Windows x64 image
runtime bundles its Visual C++ runtime DLLs. On iOS, use
`ImageModelPlacement(vaeOnCpu: true)` for CPU VAE decoding with Metal
diffusion, or choose CPU generation. The pinned `v0.4.0` runtime splits Metal graphs, so a full VAE
is admitted on iOS Metal. Device qualification for v0.4.0 is pending.
SD `v0.3.0-6` passed four full-VAE load/dispose cycles and eight decodes per device on iPhone 16 Pro (iOS 18.3.2) and iPhone 17 Pro (iOS 26.5.1), tested at `6b191b28`. Small nonzero residual memory remains; this single session is not proof of zero leaks (#2004).

Per-target support, device limitations and runtime options:

- [Platform and backend support matrix](https://llamadart.leehack.com/docs/platforms/support-matrix), including
  [known limitations](https://llamadart.leehack.com/docs/platforms/known-platform-issues)
- [Backend selection](https://llamadart.leehack.com/docs/guides/backend-selection)
- [Runtime parameters](https://llamadart.leehack.com/docs/configuration/runtime-parameters)
- [Native runtime configuration](https://llamadart.leehack.com/docs/platforms/native-build-hooks)

Current default runtime pins:

| Runtime | Pin |
| --- | --- |
| Native llama.cpp / GGUF | `leehack/llamadart-native@v1.0.0-4` |
| Native LiteRT-LM / `.litertlm` | `leehack/litert-lm-native@v0.19.1-7` |
| Web llama.cpp / GGUF | `leehack/llama-web-bridge-assets@v0.1.94` |

The Web backend reuses cached HTTP(S) projectors through the pinned bridge.
If a direct WebAssembly core abort unloads the model, catch
`LlamaModelUnloadedException` and reload it before retrying.

On thinking-capable Qwen3-Coder XML templates, a generated `<tool_call>`
ends the thinking budget and generation continues into the call. This needs
llamadart-native `v1.0.0-4` or a WebGPU bridge core reporting
`thinkingBudgetMultiEnd` (assets `v0.1.87+`). An explicit
`ThinkingBudget.endTag` selects a single delimiter.
| Web LiteRT-LM / `.litertlm` | `@litert-lm/core@0.19.0` |

Native LiteRT-LM uses a lazy ABI-aware client for direct calls, services and
speech. The public selector admits legacy runtimes and C API 1.0.x; unknown or
future versions are refused before engine calls. The pinned runtime is
published native
[v0.19.1-7](https://github.com/leehack/litert-lm-native/releases/tag/v0.19.1-7),
owner source `930a3e29` / upstream `7a03724c`. The selected loader requires
macOS 14+ before owned library loads, including legacy libraries and custom
paths. Web LiteRT-LM uses `@litert-lm/core@0.19.0`; through
`LlamaBackend.withTextHistory()` it forwards chat history, supports tool
calling and reports replies cut off at a token limit.

Native overrides accept stable `vMAJOR.MINOR.PATCH` releases and explicit
historical or nightly `bNNNN` artifacts. New nightly wrapper rebuilds use
`bNNNN-N`; existing `bNNNN-llamadart.N` artifacts stay valid as
consumption-only overrides. Nightly cores use canonical decimal spelling, and
rebuild counters start at 1 without leading zeros. Build-hook overrides must
always name an explicit tag; `latest` is limited to maintainer synchronization
and header/binding regeneration. On Windows, runtime environment directory
overrides select backend modules; use `llamadart_native_path` to replace the
complete runtime. The full override rules are in [Native runtime configuration](https://llamadart.leehack.com/docs/platforms/native-build-hooks#override-the-llamacpp-release).

Await engine disposal before host shutdown. Forced worker cleanup during
native creation uses owner API v1 in the pinned `v1.0.0` runtime. Raw
allocation-to-registration gaps remain; see the
[shutdown contract](https://github.com/leehack/llamadart/blob/main/doc/llama_cpp_exit_teardown.md#creation-time-owner-preparation).

## Guides

| Task | Docs |
| --- | --- |
| Resolve local paths, URLs, and Hugging Face sources | [Finding models](https://llamadart.leehack.com/docs/getting-started/finding-models) |
| Stream text and collect output | [Generation and streaming](https://llamadart.leehack.com/docs/guides/generation-and-streaming) |
| Generate typed JSON | [Structured output](https://llamadart.leehack.com/docs/guides/generation-and-streaming#structured-json-output) |
| Use tool calling | [Tool calling](https://llamadart.leehack.com/docs/guides/tool-calling) |
| Use images, audio, or projectors | [Multimodal](https://llamadart.leehack.com/docs/guides/multimodal) |
| Transcribe speech on device | [Speech to text](https://llamadart.leehack.com/docs/guides/speech-to-text) |
| Synthesize speech on device | [Text to speech](https://llamadart.leehack.com/docs/guides/text-to-speech) |
| Generate images on device (Preview) | [Image generation](https://llamadart.leehack.com/docs/guides/image-generation) |
| Answer typed questions with a decision model | [Decision models](https://llamadart.leehack.com/docs/guides/decision-models) |
| Generate embeddings and rerank | [Embeddings](https://llamadart.leehack.com/docs/guides/embeddings) |
| Load LoRA adapters | [LoRA adapters](https://llamadart.leehack.com/docs/guides/lora-adapters) |
| Save and restore KV state, write a custom backend | [API levels](https://llamadart.leehack.com/docs/guides/api-levels) |
| Trace and measure requests | [Observability](https://llamadart.leehack.com/docs/guides/observability) |
| Run Flutter Web / WebGPU | [WebGPU bridge](https://llamadart.leehack.com/docs/platforms/webgpu-bridge) |
| Tune performance | [Performance tuning](https://llamadart.leehack.com/docs/guides/performance-tuning) |
| Upgrade from 0.16.x | [0.17 migration guide](https://llamadart.leehack.com/docs/migration/upgrade-to-0-17) |

## Examples

Run the Flutter chat app from a
[repository checkout](https://github.com/leehack/llamadart/tree/main/example/chat_app),
try the [hosted chat app](https://leehack-llamadart.static.hf.space), or
[chat with GGUF models (SmolLM2 135M, Qwen3.5 0.8B, or desktop Chrome Gemma 4 E2B) on preview.dartpad.dev](https://preview.dartpad.dev/?package=llamadart&root=example/dartpad_gguf&file=example/dartpad_gguf/lib/main.dart).

- [Basic Dart CLI](https://github.com/leehack/llamadart/tree/main/example/basic_app)
- [Flutter chat app](https://github.com/leehack/llamadart/tree/main/example/chat_app)
- [Experimental Studio app and reusable core](https://github.com/leehack/llamadart/tree/main/packages/llamadart_studio), with Chat, Notes, Coding (including app-owned local workspaces on iOS/Android), model management, speech, images, and runtime exploration
- [Laya Tetris, a Flutter game played by a decision model](https://github.com/leehack/llamadart/tree/main/example/laya_tetris)
- [HTTP server example](https://github.com/leehack/llamadart/tree/main/example/llamadart_server)
- [TUI coding agent example](https://github.com/leehack/llamadart/tree/main/example/tui_coding_agent)

## Contributing

Repository checks, validation commands, and PR expectations are in
[AGENTS.md](https://github.com/leehack/llamadart/blob/main/AGENTS.md) and the
[maintainer docs](https://llamadart.leehack.com/docs/maintainers/docs-site#validating-changes).

## License

MIT. See [LICENSE](https://github.com/leehack/llamadart/blob/main/LICENSE).
