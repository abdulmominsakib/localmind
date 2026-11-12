---
title: On-device text to speech
sidebar_label: Text to speech
description: Generate complete PCM and WAV audio with the experimental typed llama.cpp text-to-speech API (Qwen3-TTS, LFM3-Audio, Soprano, Chatterbox, Pocket TTS) on native and WebGPU runtimes.
---

`TextToSpeechEngine` is the typed API for speech synthesis. It is separate from
`LlamaEngine.create` because audio sample metadata, speaker reference input,
progress, cancellation, and output buffering are not chat-token semantics.

Text to speech is experimental and deliberately narrow. It supports
Qwen3-TTS through native llama.cpp or WebGPU (pinned bridge assets), and
LFM3-Audio, Soprano, Chatterbox Turbo, Chatterbox Multilingual and Pocket TTS
through native llama.cpp, each with the matching
audio-generation projector. It reports prompt/frame progress, then returns one
complete mono float32 PCM buffer. It does not stream playable audio chunks yet.

## Current support matrix

| Runtime | Typed `TextToSpeechEngine` | Output |
| --- | --- | --- |
| Native llama.cpp / GGUF | Experimental Qwen3-TTS, LFM3-Audio, Soprano, Chatterbox and Pocket TTS adapters | Complete float32 PCM; WAV helper |
| WebGPU / GGUF | Experimental Qwen3-TTS adapter (pinned bridge assets) | Complete float32 PCM; WAV helper |
| Native LiteRT-LM / `.litertlm` | Unsupported by the pinned native artifact | None |
| LiteRT-LM Web | Unsupported | None |

## Models

Pick the adapter for the model; `capabilities` reports what the loaded pair
takes, and a request that asks for anything else throws before synthesis.

| Model | Adapter | Output | Language | Voices | Speaker reference | Sampling |
| --- | --- | --- | --- | --- | --- | --- |
| Qwen3-TTS | `Qwen3TtsAdapter` | 24 kHz | 10 codes, see below | None | Yes | Request settings |
| LFM3-Audio, LFM3-Omni | `Lfm3AudioTtsAdapter` | 24 kHz | Any, not validated | `female` (default), `male` | No | The GGUF's own; request settings are validated, unused |
| Soprano | `SopranoTtsAdapter` | 32 kHz | No | None | No | Request settings |
| Chatterbox Turbo | `ChatterboxTtsAdapter` | 24 kHz | No | `default` | Yes | Request settings |
| Chatterbox Multilingual | `ChatterboxTtsAdapter` | 24 kHz | Code such as `fr`, not validated | `default` | Yes | Request settings |
| Pocket TTS | `PocketTtsAdapter` | 24 kHz | No (the weights' language) | The projector's, such as 25 in the Kyutai English pack | Only with a voice encoder | The weights' own; request settings are validated, unused |

LFM3-Audio and Soprano need native llama.cpp from llamadart-native v0.8.0, the
release that added the model-type opt-in (`llama_dart_tts_init_ext`);
Chatterbox and Pocket TTS need v0.9.0. An older runtime, such as an older
Apple companion lock, keeps Qwen3-TTS working: `load` asks it which models it
drives and throws `LlamaUnsupportedException` naming the required release
before loading any file, and `capabilities` on an attached engine reports the
same in `unsupportedReason`. Web drives Qwen3-TTS only.

On Android, GPU work stays off on the Adreno 750 driver that llama.cpp Vulkan
miscomputes on ([llamadart-native#79](https://github.com/leehack/llamadart-native/issues/79)):
there Soprano returns the same non-speech audio for every input and LFM3-Audio
fails to create its pipelines, and Chatterbox and Pocket TTS are unqualified
on it. On that driver automatic device selection
falls back to the CPU with a warning, and `ComputeDevice.gpu` throws.

### LFM3-Audio

Load the LFM3-Audio (or LFM3-Omni) model with its projector, for example
`LFM3-Audio-2B-Q4_K_M.gguf` and `mmproj-LFM3-Audio-2B-Q8_0.gguf` from
[`LiquidAI/LFM3-Audio-2B-GGUF`](https://huggingface.co/LiquidAI/LFM3-Audio-2B-GGUF).
It speaks through the model's `tts` chat template; a model without one is
reported unsupported. `language` is rendered into that template as given (a
code such as `en` or a language name) and is not validated, so check it
against the model card; without one the template's default, English, applies.
The model samples audio codes with its own GGUF settings, so `topK`, `topP`,
`minP` and `temperature` are validated but unused; `seed` still makes a
synthesis repeatable.

### Soprano

Soprano takes no language, voice or speaker reference. It samples with the
request's settings; the default temperature is 0.8, while upstream's example
decodes greedily, so pass `temperature: 0` to match it. Fewer than two
generated frames fail the synthesis.

No llama.cpp-format Soprano GGUF is published. Convert
[`ekwek/Soprano-1.1-80M`](https://huggingface.co/ekwek/Soprano-1.1-80M) (or
Soprano-80M) with `convert_hf_to_gguf.py` from the llama.cpp revision the
runtime pins, both files from the same model directory, including
`decoder.pth`:

```sh
python convert_hf_to_gguf.py path/to/Soprano-1.1-80M --outtype f16 --outfile soprano.gguf
python convert_hf_to_gguf.py path/to/Soprano-1.1-80M --mmproj --outtype f16 --outfile mmproj-soprano.gguf
```

Upstream's README converts the backbone as `f32`; an `f16` backbone also
passes the ASR round trip at half the size. With torch 2.10 and later the
projector conversion can fail with `Soprano requires a periodic Hann window`:
the published decoder's ISTFT window differs from `torch.hann_window` by one
float32 ulp (about 6e-8), and the converter compares them exactly. Replace
that `torch.equal` in `conversion/soprano.py` with
`torch.allclose(..., atol=1e-6)` for the conversion; the window itself is not
stored, since the runtime builds its own.

## Load Qwen3-TTS

Use a matching model and projector pair. The chat example pins the Q4_K_M base
model and Q8_0 projector from
[`ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF`](https://huggingface.co/ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF).

A `TextToSpeechModel` names the model and projector, each a `ModelSource`,
and the adapter that drives them. Native runtimes download and cache remote
sources before loading their local files; Web passes the same sources to the
browser runtime and its cache.

```dart
const revision = 'ca27d74bc954b73dadab5b71ca265d87fc861a7c';
final synthesizer = await TextToSpeechEngine.load(
  TextToSpeechModel(
    ModelSource.huggingFace(
      repoId: 'ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF',
      revision: revision,
      filePath: 'Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf',
    ),
    projector: ModelSource.huggingFace(
      repoId: 'ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF',
      revision: revision,
      filePath: 'mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf',
    ),
    adapter: const Qwen3TtsAdapter(),
  ),
);
try {
  final result = await synthesizer.synthesizeOnce(
    const TextToSpeechRequest(text: 'Hello from llamadart.', language: 'en'),
  );
  print(result.duration);
} finally {
  await synthesizer.dispose();
}
```

`load` creates a `LlamaEngine`, loads the model with `params:` and then the
projector, checks `capabilities`, and throws `LlamaUnsupportedException` with
the reason when they cannot synthesize speech with the adapter. Loading a
projector alone does not prove that the active native or Web runtime exports
the required TTS ABI or that the projector matches the model. `download:`
takes `ModelLoadOptions` for every remote file, `onProgress:` reports both
files together (on Web, where the browser fetches each file, only the model's
fetch reports progress, up to 0.5, and progress reaches 1 once the projector
has loaded), `store:` takes a `ModelFileStore` with your own resolver or
download manager, and `backend:` the `LlamaBackend` (by default
`LlamaBackend()`). Both files resolve, model first, before anything loads;
a local file takes only the cancel token. The bearer token and headers are
never sent across hosts: when they are set and the two remote files are on
different origins (scheme, host and port), `load` throws
`LlamaArgumentException` before downloading from another host. `ModelLoadOptions.sha256` throws
`LlamaUnsupportedException`, since one checksum cannot cover both files. The
load is atomic: when it throws, the engine is disposed, and downloaded files
stay in the cache.

The synthesizer owns the engine `load` created and a `backend:` you passed,
and `dispose()`, or a failed load, disposes both.
To share a `LlamaEngine` you loaded yourself, attach the adapter instead and
check `capabilities` yourself; `dispose()` then leaves your engine loaded:

```dart
final synthesizer = TextToSpeechEngine.attach(
  engine,
  adapter: const Qwen3TtsAdapter(),
);
final capabilities = await synthesizer.capabilities;
if (!capabilities.isSupported) {
  throw StateError(capabilities.unsupportedReason!);
}
```

Once the attached `LlamaEngine` is disposed, `capabilities` reports
unsupported with that reason and `synthesize` throws `LlamaStateException`: create a new
`LlamaEngine` and attach a new synthesizer
([The LlamaEngine is disposed](../troubleshooting/common-issues#the-llamaengine-is-disposed-create-a-new-llamaengine)).

The runtime generates the audio itself and reports which audio-generation
model it loaded, so an adapter can target only a model the runtime supports.
`Qwen3TtsAdapter` accepts Qwen3-TTS and maps request languages to its codes;
`Lfm3AudioTtsAdapter`, `SopranoTtsAdapter`, `ChatterboxTtsAdapter` and
`PocketTtsAdapter` accept their models.
`TextToSpeechAdapter` is open for another family once a runtime reports it:
`supportsModel` accepts the `BackendTextToSpeechModel` it drives,
`supportedLanguages` lists its codes, and `normalizeLanguage` maps a request
language to one of them.

### Chatterbox

`ChatterboxTtsAdapter` drives Chatterbox Turbo and Chatterbox Multilingual,
for example the Q8_0 model and F16 projector from
[`ggml-org/chatterbox-turbo-GGUF`](https://huggingface.co/ggml-org/chatterbox-turbo-GGUF)
or [`ggml-org/chatterbox-GGUF`](https://huggingface.co/ggml-org/chatterbox-GGUF).
Both speak with the projector's predefined voice (`default` in these
conversions) or clone a speaker reference of about 10 seconds; a short clip
can make the model run on to `maxFrames`. They sample with the request's
settings; the GGUFs store upstream's defaults (Turbo `topK: 1000`,
`topP: 0.95`, `minP: 0`; Multilingual `topP: 1`, `minP: 0.05`; both
`temperature: 0.8`), which you can pass to match upstream `llama-tts`.

Turbo takes no language. Multilingual reports `supportsLanguage`: pass a code
such as `fr`, which is lower-cased and not validated (check it against the
model card; upstream does not yet normalize text, so some diacritics drop).
Multilingual decodes a second sequence for classifier-free guidance, so load
it with two sequences, or it is reported unsupported:

```dart
final synthesizer = await TextToSpeechEngine.load(
  TextToSpeechModel(
    ModelSource.parse('hf://ggml-org/chatterbox-GGUF/chatterbox-Q8_0.gguf'),
    projector: ModelSource.parse(
      'hf://ggml-org/chatterbox-GGUF/mmproj-chatterbox-F16.gguf',
    ),
    adapter: const ChatterboxTtsAdapter(),
  ),
  params: const ModelParams(maxParallelSequences: 2),
);
final result = await synthesizer.synthesizeOnce(
  const TextToSpeechRequest(
    text: "Bonjour, comment allez-vous aujourd'hui?",
    language: 'fr',
  ),
);
```

### Pocket TTS

`PocketTtsAdapter` drives Pocket TTS, for example
`english/pocket-tts-english.gguf` and its projector from
[`macolomb/pocket-tts-without-voice-cloning`](https://huggingface.co/macolomb/pocket-tts-without-voice-cloning).
It speaks with a predefined voice (that pack lists 25, from `alba` to `vera`),
the first one when a request names none, and speaks unconditioned when the
projector has none. A speaker reference needs a projector with a voice
encoder, which that pack lacks. The language is that of the weights. It
samples with the weights' own settings, so `topK`, `topP`, `minP` and
`temperature` are validated but unused; `seed` seeds the decoder. Long text is
split into chunks that all count towards `maxFrames`.

## Synthesize and save WAV

```dart
final task = await synthesizer.synthesize(
  const TextToSpeechRequest(
    text: 'Hello from llamadart.',
    language: 'English',
  ),
);

task.events.listen((event) {
  if (event is TextToSpeechProgressEvent) {
    print('Generated ${event.framesGenerated} frames');
  }
});

try {
  final result = await task.result;
  final wavBytes = result.toWavBytes();
  print('${result.duration}: ${wavBytes.length} WAV bytes');
} on LlamaException catch (error) {
  print('Synthesis failed or was cancelled: $error');
}
```

`synthesize` throws typed validation, state, or unsupported errors when
preflight fails before a task starts. After startup, the single-subscription
event stream carries progress, then one `TextToSpeechFinalEvent` with the PCM,
and never emits an error. `task.result` returns the audio or throws the
failure, or `LlamaStateException` when the task is cancelled; `task.done`
reports the same outcome as a `TextToSpeechCompletion` and never throws.

`task.cancel()` stops its own synthesis request. With the pinned Web bridge
assets this also preserves another active request when synthesis is still
awaiting a queued capability probe. Await `task.done` before reusing its speech context; cancellation is
cooperative and does not promise a latency bound.
`synthesizeOnce` skips the events: it is
`(await synthesizer.synthesize(request)).result`.

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

## Voices

A model with predefined voices reports `supportsVoice`, and `voices` lists
them in the model's order; the first one speaks when a request names none.
Select one by name:

```dart
final capabilities = await synthesizer.capabilities;
if (capabilities.voices.contains('male')) {
  final result = await synthesizer.synthesizeOnce(
    const TextToSpeechRequest(text: 'Hello from llamadart.', voice: 'male'),
  );
}
```

A name matches in any case. One the model does not list throws
`LlamaTextToSpeechException` before synthesis, never falling back to the
default; a voice together with a speaker reference does too, and a voice for a
model without voices throws `LlamaUnsupportedException`. For Chatterbox and
Pocket TTS, a request without a voice or reference gives the same audio as
one naming the first voice. Runtimes before llamadart-native v0.9.0 can select
an LFM3-Audio voice but not list it: `voices` is then empty while
`supportsVoice` is true, and the runtime checks the name when synthesis
starts.

For Qwen3-TTS, the canonical language codes are `zh`, `en`, `ja`, `ko`, `de`,
`fr`, `ru`, `pt`, `es`, and `it`. Common English names are normalized to those
codes, so `language: 'English'` is equivalent to `language: 'en'`. Other values
fail during typed preflight instead of reaching the backend model as an invalid
prompt.

Treat reference recordings as sensitive input. The typed API does not retain
them after the backend request completes, but application code remains
responsible for its own files, byte buffers, permissions, and disclosures.

## Cancellation, concurrency, and buffering

Call `task.cancel()` to request cooperative cancellation of that synthesis.
Cancelling only the event-stream subscription does not cancel synthesis. On native llama.cpp, a cancel
stops a Qwen3-TTS audio decode in progress at its next chunk boundary.
`LlamaEngine.unloadModel()` and `dispose()` cancel an active synthesis the same
way, and its task reports `cancelled`.

`TextToSpeechEngine.dispose()` cancels a running task, waits for it to stop,
and disposes the engine that `load` created; an attached engine stays loaded.
Calling it again is safe, and `isDisposed` reports it. After `dispose()`,
`synthesize` throws `LlamaStateException` and `capabilities` reports
unsupported.

All typed STT and TTS wrappers over one `LlamaEngine` share a one-task speech
lease. Do not run chat generation, transcription, or another synthesis on the
same engine until the active speech task completes.

Native llama.cpp rejects embeddings (including content and batch embeddings),
next-token scoring, text generation, state save/load and LoRA changes on a
context while text-to-speech is active with `LlamaStateException`. Await the
synthesis task, including cancellation, before reusing that context. The
reservation starts before speaker-reference loading.

The current native and Web wrappers produce PCM only after all requested audio-codec
frames have been generated. `supportsIncrementalAudio` and
`supportsOutputBackpressure` are therefore false. Progress events are useful
for status and cancellation, but are not playable audio chunks.

The [chat app](../examples/chat-app) has a Qwen3-TTS mode built on this API.

## Known limits

- Output is complete mono PCM at the model's rate (`sampleRateHz`); no
  incremental audio chunks, timestamps, or output backpressure are available.
- Qwen3-TTS, LFM3-Audio, Soprano, Chatterbox, Pocket TTS and llama.cpp audio
  generation are experimental. The models other than Qwen3-TTS were checked on
  macOS arm64 (CPU) with an ASR round trip; other hosts are unqualified. Voice
  quality,
  latency, supported reference formats, and accelerator behavior remain
  model/device dependent.
- Web requires the pinned bridge assets, WebAssembly memory64 for the
  roughly 1.48 GB model/projector pair, and a browser/device with enough
  memory. Older assets fail capability discovery clearly
  ([Older bridge assets](../platforms/webgpu-bridge#older-bridge-assets)).
- The pinned bridge retries a synthesis once on
  the main thread, more slowly, after eligible WebGPU errors and worker
  timeouts; see
  [WebGPU bridge fallback behavior](../platforms/webgpu-bridge#fallback-behavior).
- Web speaker references are selected-file bytes only; microphone speaker
  recording remains a native chat-example feature.
