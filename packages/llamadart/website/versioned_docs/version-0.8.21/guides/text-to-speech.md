---
title: Text to Speech
description: Generate complete PCM and WAV audio with the experimental typed llama.cpp Qwen3-TTS API on native and WebGPU runtimes.
---

`TextToSpeechEngine` is the typed API for speech synthesis. It is separate from
`LlamaEngine.create` because audio sample metadata, speaker reference input,
progress, cancellation, and output buffering are not chat-token semantics.

The first implementation is experimental and deliberately narrow. It supports
Qwen3-TTS through native llama.cpp or WebGPU bridge assets `v0.1.33+` with the
matching audio-generation projector. It reports prompt/frame progress, then
returns one complete 24 kHz mono float32 PCM buffer. It does not stream playable
audio chunks yet.

## Current support matrix

| Runtime | Typed `TextToSpeechEngine` | Output |
| --- | --- | --- |
| Native llama.cpp / GGUF | Experimental Qwen3-TTS adapter | Complete float32 PCM; WAV helper |
| WebGPU / GGUF | Experimental Qwen3-TTS adapter with bridge assets `v0.1.33+` | Complete float32 PCM; WAV helper |
| Native LiteRT-LM / `.litertlm` | Unsupported by the pinned native artifact | None |
| LiteRT-LM Web | Unsupported | None |

## Load Qwen3-TTS

Use a matching model and projector pair. The chat example pins the Q4_K_M base
model and Q8_0 projector from
[`ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF`](https://huggingface.co/ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF).

The structured model-source APIs keep the loading flow portable. Native
runtimes download and cache remote sources before loading their local files;
Web passes the same sources to the browser runtime and its cache.

```dart
final engine = LlamaEngine(LlamaBackend());
const revision = 'ca27d74bc954b73dadab5b71ca265d87fc861a7c';
await engine.loadModelSource(
  ModelSource.huggingFace(
    repoId: 'ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF',
    revision: revision,
    filePath: 'Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf',
  ),
);
await engine.loadMultimodalProjectorSource(
  ModelSource.huggingFace(
    repoId: 'ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF',
    revision: revision,
    filePath: 'mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf',
  ),
);

final synthesizer = TextToSpeechEngine(
  engine,
  modelProfile: TextToSpeechModelProfile.qwen3Tts,
);
final capabilities = await synthesizer.capabilities;
if (!capabilities.isSupported) {
  throw StateError(capabilities.unsupportedReason!);
}
```

Always probe capabilities after both artifacts are loaded. Loading a projector
does not prove that the active native or Web runtime exports the required TTS
ABI or that the projector matches the model.

## Synthesize and save WAV

```dart
final task = await synthesizer.synthesize(
  const TextToSpeechRequest(
    text: 'Hello from llamadart.',
    language: 'English',
  ),
);

try {
  await for (final event in task.events) {
    if (event is TextToSpeechProgressEvent) {
      print('Generated ${event.framesGenerated} frames');
    }
    if (event is TextToSpeechFinalEvent) {
      final result = event.result;
      final wavBytes = result.toWavBytes();
      print('${result.duration}: ${wavBytes.length} WAV bytes');
    }
  }
} on LlamaException catch (error) {
  print('Synthesis failed: $error');
}

final completion = await task.done;
print(completion.state);
```

`synthesize` throws typed validation, state, or unsupported errors when
preflight fails before a task starts. After startup, failures are emitted as a
stream error and also reported through `task.done`. The event stream is
single-subscription.

For models that advertise speaker-reference support, encoded bytes are the
portable representation. In this example, `referenceWavBytes` is a
`Uint8List` obtained through the host application's file picker or recorder:

```dart
final task = await synthesizer.synthesize(
  TextToSpeechRequest(
    text: 'This utterance uses the supplied reference voice.',
    language: 'English',
    speakerReference: SpeechAudioBytesInput(referenceWavBytes),
  ),
);
```

Native applications may alternatively use
`SpeechAudioFileInput('/recordings/reference.wav')`. Browser runtimes cannot
read arbitrary local filesystem paths.

For Qwen3-TTS, the canonical language codes are `zh`, `en`, `ja`, `ko`, `de`,
`fr`, `ru`, `pt`, `es`, and `it`. Common English names are normalized to those
codes, so `language: 'English'` is equivalent to `language: 'en'`. Other values
fail during typed preflight instead of reaching the backend model as an invalid
prompt.

Treat reference recordings as sensitive input. The typed API does not retain
them after the backend request completes, but application code remains
responsible for its own files, byte buffers, permissions, and disclosures.

## Cancellation, concurrency, and buffering

Call `task.cancel()` to request cooperative cancellation. Cancelling only the
event-stream subscription does not cancel synthesis.

All typed STT and TTS wrappers over one `LlamaEngine` share a one-task speech
lease. Do not run chat generation, transcription, or another synthesis on the
same engine until the active speech task completes.

The current native and Web wrappers produce PCM only after all requested audio-codec
frames have been generated. `supportsIncrementalAudio` and
`supportsOutputBackpressure` are therefore false. Progress events are useful
for status and cancellation, but are not playable audio chunks.

## Chat example

The cross-platform catalog contains a checksum-pinned **Qwen3-TTS 1.7B Base**
model/projector pair. Selecting it switches the composer into a dedicated TTS
mode:

- type the utterance instead of sending a chat message;
- optionally choose a language and select or record a speaker reference;
- cancel while frames are being generated;
- automatically play the completed output, replay it, or save it as a WAV file.

Native microphone references are capped at 30 seconds. Web users can select an
existing audio file, which is read as encoded bytes. The example reads the
completed WAV into memory for synthesis and best-effort deletes the temporary
recording. Selecting an existing audio file remains available as a separate
option.

The TTS model is not presented as a general chat assistant, and the example
does not automatically read arbitrary assistant responses. Automatic
read-aloud would require a separate model-lifecycle policy, especially on
memory-constrained mobile devices.

## Known limits

- The first backend returns complete 24 kHz mono output only; no incremental
  audio chunks, timestamps, or output backpressure are available.
- Qwen3-TTS and llama.cpp audio generation are experimental. Voice quality,
  latency, supported reference formats, and accelerator behavior remain
  model/device dependent.
- Web requires published bridge assets `v0.1.33+`, WebAssembly memory64 for the
  pinned roughly 1.48 GB model/projector pair, and a browser/device with enough
  memory. Older bridge assets fail capability discovery clearly.
- The chat example pins `v0.1.39`, which retains the `v0.1.34` recovery that
  retries a worker WebGPU abort or device failure once on CPU using the cached
  model and projector. Recovery is slower and is not a substitute for
  sufficient browser memory. Qwen3-TTS accelerator behavior remains
  device-dependent; validate the target browser and device for queue-watchdog
  timeouts before relying on it in production.
- Web speaker references are selected-file bytes only; microphone speaker
  recording remains a native chat-example feature.
