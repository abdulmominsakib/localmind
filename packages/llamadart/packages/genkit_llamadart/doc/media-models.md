# Batch speech and image generation

`LlamaDartMediaPlugin` exposes dedicated speech and image engines as standard
Genkit models. It can coexist with the chat plugin. This native preview supports
whole-file Qwen3-ASR transcription, complete Qwen3-TTS WAV synthesis and
stable-diffusion PNG generation. Browser requests fail with `UNIMPLEMENTED`.

Add both packages to your app when using llamadart's typed engines:

```bash
dart pub add genkit_llamadart llamadart
```

Load the engine first with llamadart's typed `load` API. Model sources, loading
parameters, cache policy, component files, download progress and cancellation
remain available there. Register the loaded engine with `ownsEngine: true` to
let the plugin dispose it, or leave the default borrowed ownership and dispose
it yourself. Registration/listing performs no loading or probing. Every request
checks the engine's live capabilities.

## Transcribe an audio file

This example downloads the pinned Qwen3-ASR model/projector through llamadart's
cache. The pair uses about 1 GB of disk. Replace `input.wav` with your audio file.

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;

Future<void> main() async {
  const revision = '928ab958557df9aa2ef1c93e0e83c7ad0933fae2';
  final engine = await llama.SpeechToTextEngine.load(
    llama.SpeechToTextModel(
      ModelSource.huggingFace(
        repoId: 'ggml-org/Qwen3-ASR-0.6B-GGUF',
        revision: revision,
        filePath: 'Qwen3-ASR-0.6B-Q8_0.gguf',
      ),
      projector: ModelSource.huggingFace(
        repoId: 'ggml-org/Qwen3-ASR-0.6B-GGUF',
        revision: revision,
        filePath: 'mmproj-Qwen3-ASR-0.6B-Q8_0.gguf',
      ),
      adapter: const llama.Qwen3AsrAdapter(),
    ),
    params: const ModelParams(contextSize: 4096, device: ComputeDevice.cpu),
  );
  final plugin = LlamaDartMediaPlugin(models: [
    LlamaDartSpeechToTextModel(name: 'asr', engine: engine, ownsEngine: true),
  ]);
  final ai = Genkit(plugins: [plugin]);
  try {
    final result = await ai.generate(
      model: LlamaDartMediaPlugin.modelRef('asr'),
      messages: [Message(role: Role.user, content: [
        MediaPart(media: Media(url: 'input.wav', contentType: 'audio/wav')),
      ])],
      config: {'maxOutputTokens': 1024},
    );
    if (result.finishReason == FinishReason.failed) {
      throw StateError('Transcription failed: ${result.error}');
    }
    print(result.text);
  } finally {
    await plugin.dispose();
    await ai.shutdown();
  }
}
```

Recognition accepts exactly one audio media part. Local files, `file:` URLs and
encoded `data:` URLs work without a resolver. HTTP(S) audio requires an explicit
`mediaResolver` with application-owned policy and transport, as in the
[remote media guide](usage.md).

| Recognition option | Accepted values |
| --- | --- |
| `contextPrompt` | Nonempty context, up to 16,384 characters |
| `languageHint` | Same limit; only when the engine reports support. Qwen3-ASR rejects it. |
| `maxOutputTokens` | Integer 1–16,384; default 1,024 |

The result is a final transcript. Microphone input streaming, partial transcripts,
timestamps and diarization are outside this contract. Model context/token limits
still apply; increasing an adapter limit cannot bypass them.

## Synthesize a complete WAV

Load `TextToSpeechEngine` with `TextToSpeechModel`, its matching projector and
`const Qwen3TtsAdapter()`. The qualified model pair is
[`ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF`](https://huggingface.co/ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF)
at revision `ca27d74bc954b73dadab5b71ca265d87fc861a7c`: main
`Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf` and projector
`mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf`.
Register it with `LlamaDartTextToSpeechModel`. Generate with one user message
containing text, and optionally one reference audio part when the loaded engine
supports speaker references. Use `result.media` to read the complete
`audio/wav` data URL; decode it with `UriData.parse(media.url).contentAsBytes()`.

| Synthesis option | Accepted values; default |
| --- | --- |
| `language` | Nonempty language supported by the adapter; omitted by default |
| `maxFrames` | Integer 1–8,192; 512 |
| `promptBatchSize` | Integer 1–8,192; 512 |
| `topK` | Integer 1–100,000; 40 |
| `topP` | Greater than 0, at most 1; 0.95 |
| `minP` | 0–1; 0 |
| `temperature` | 0–10; 0.8 |
| `seed` | Integer 0–4,294,967,295; the default requests a random seed |

Non-finite PCM, invalid sample metadata and truncated synthesis fail without
publishing audio. If `maxFrames` is reached, shorten the text or increase the
limit. This contract does not provide incrementally playable audio.

## Generate PNG images

Enable the optional image runtime in your app's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp, stable_diffusion]
```

Load `ImageGenerationEngine` with `ImageGenerationModel` and any required
components. Register it with `LlamaDartImageModel`. Generate with one user
message containing text. The result contains one complete `image/png` data URL
per image in `result.message.content`. The qualified preview fixture is
[`concedo/sdxs-512-tinySDdistilled-GGUF`](https://huggingface.co/concedo/sdxs-512-tinySDdistilled-GGUF),
revision `3144d898d61492f8382ffcabec055733fc5b2a0e`, file
`sdxs-512-tinySDdistilled_Q8_0.gguf`, using one step and guidance 1.

| Image option | Accepted values; default |
| --- | --- |
| `negativePrompt` | Up to 16,384 characters; empty |
| `width`, `height` | Multiples of 8 from 64–2,048; engine/model defaults |
| `steps` | Integer 1–150; engine/model default |
| `guidanceScale` | 0–30; engine/model default |
| `seed` | Integer 0–2,147,483,647; random when omitted |
| `count` | Integer 1–16; 1 |
| `sampler` | `euler`, `eulerAncestral`, `dpmpp2m`, `lcm`; runtime default when omitted |
| `scheduler` | `discrete`, `karras`, `sgmUniform`, `simple`; runtime default when omitted |
| `flowShift` | Greater than 0, at most 100; omitted |

Model/component support and platform/backend availability remain governed by
the loaded engine. Image
runtime operations also share a process-wide slot; avoid using other image
engines or model loads concurrently.

## Limits, cancellation and ownership

Each definition defaults to 20 MiB of encoded audio input and 20 MiB of output
bytes (total across generated PNGs). Set `maxInputBytes`/`maxOutputBytes` on the
appropriate definition to change these bounds. They bound encoded transfers,
not decoded audio duration or native memory. Use short, trusted clips and the
runtime's own resource controls. Text prompts are capped at 16,384 characters.

The plugin serializes its media requests, checks cancellation before starting a
task and connects the Genkit token to that task's cooperative cancellation.
`generateStream` emits optional progress through chunk
`custom.llamadartProgress`, then complete validated content. Failed requests can
have progress chunks but never final media content. Core runtime errors are
sanitized to avoid exposing input URLs or paths. Always inspect Genkit's
`finishReason` and `error` before using the result.

`plugin.dispose()` is terminal and idempotent: it drains accepted work and
releases owned engines. Borrowed engines and the optional HTTP client remain
caller-owned. Avoid direct engine calls while plugin operations are queued;
those calls are outside its queue. Loading/probing/generation APIs in llamadart
remain experimental; this adapter does not broaden their platform claims.
