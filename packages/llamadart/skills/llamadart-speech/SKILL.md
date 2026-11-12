---
name: llamadart-speech
description: >-
  Use when adding speech to a llamadart app: transcribing audio files with
  Qwen3-ASR through SpeechToTextEngine, streaming live PCM dictation with
  LiteRT-LM ASR, synthesizing speech with Qwen3-TTS, LFM3-Audio, Soprano,
  Chatterbox or Pocket TTS through TextToSpeechEngine, selecting predefined voices, saving WAV output, handling LlamaAudioFormatException or
  LlamaSpeechTranscriptTruncatedException, or checking speech support on
  native and Web runtimes.
---

# Speech to text and text to speech with llamadart

## Guidelines

- Native LiteRT-LM speech probes and workers share the text client's ABI-aware
  discovery. Public selection admits legacy runtimes and C API 1.0.x; the
  pinned runtime is published native v0.19.1-4. The selector checks macOS 14+
  before owned loads, including legacy libraries and custom paths. ASR also
  requires its independent bridge version, layout and complete export group; a
  text C API version proves none of those capabilities.

- Speech uses the experimental typed `SpeechToTextEngine` and
  `TextToSpeechEngine`, not chat. `LlamaAudioContent` in `engine.create` is
  plain audio chat with no transcript contract (see the multimodal guide).
- Create a speech engine with `load` or `attach`:
  - `SpeechToTextEngine.load(SpeechToTextModel(source, projector:,
    tokenizer:, adapter:), params:, download:, onProgress:, store:,
    backend:)` and `TextToSpeechEngine.load(TextToSpeechModel(source,
    projector:, adapter:), ...)` download each `ModelSource` (path, URL or
    `hf://owner/repo/file`) into the model cache, load it, check
    `capabilities`, and own what they load. They throw
    `LlamaUnsupportedException` when the model cannot do the task; when they
    throw, nothing stays loaded. `ModelLoadOptions.sha256` is rejected for
    multi-file models. A local file gets only the cancel token; `bearerToken`
    and `headers` reach one host only, so remote files on two hosts with
    them set throw `LlamaArgumentException`. A `backend:` passed to `load` is
    owned and disposed with the engine.
  - `SpeechToTextEngine.attach(engine, adapter: const Qwen3AsrAdapter())` and
    `TextToSpeechEngine.attach(engine, adapter: const Qwen3TtsAdapter())`
    borrow a `LlamaEngine` you loaded; check `capabilities` yourself. Once
    that `LlamaEngine` is disposed, requests throw `LlamaStateException`:
    attach a new speech engine to a new `LlamaEngine`.
  - Always `await dispose()`. It cancels a running task or stream and
    disposes the engine `load` created; an attached engine stays loaded.
  - The `SpeechToTextEngine(engine, modelProfile:)`,
    `SpeechToTextEngine.liteRtLm` and `TextToSpeechEngine(engine,
    modelProfile:)` constructors and the `*ModelProfile` enums are
    deprecated; do not use them. Load LiteRT-LM ASR files, local or remote,
    with `SpeechToTextEngine.load`; `LiteRtLmAsrRuntimeConfig` is only the
    low-level runtime config of local files.
- Pick the adapter by model family. The adapter is a required declaration;
  audio support alone never makes a model ASR:
  - Qwen3-ASR (whole file, one final transcript): `Qwen3AsrAdapter` with the
    Qwen3-ASR GGUF as `source` and its mmproj as `projector`. Native
    llama.cpp, or WebGPU (pinned bridge assets).
  - Another audio chat model on `LlamaEngine`: extend
    `SpeechToTextPromptAdapter` with `name`, `promptFor(request)` (the text
    sent before the audio) and `parseTranscript(output)` (returns a
    `SpeechToTextTranscript`); override `supportsLanguageHints`,
    `supportsContextPrompt` or `supportsLanguageDetection` as needed.
  - LiteRT-LM ASR (live partials, then a final transcript):
    `LiteRtLmAsrAdapter(preset)` with the `.tflite` model, or a dedicated ASR
    `.litertlm` container such as Whisper tiny, as `source` and its tokenizer
    JSON as `tokenizer` (still required for a container, which uses its
    embedded tokenizer). Apple apps use the `llamadart_litert_lm_flutter`
    companion with the core's `MAJOR.MINOR`. Native only, CPU only
    (`LiteRtLmAsrBackend.cpu`); runtime settings go on the adapter, and
    `params`/`backend` must be null. `load` throws
    `LlamaUnsupportedException` where the runtime is unavailable, including
    Web. Presets: `parakeetTdt0_6bV3`, `parakeetCtc0_6b`, `moonshineTiny`,
    `whisperTiny`, `qwen3Asr0_6b`; the files must match the preset.
    Boundary and recognition errors can remain.
  - Qwen3-TTS: `Qwen3TtsAdapter` with the Qwen3-TTS GGUF and its
    audio-generation mmproj. Native llama.cpp, or WebGPU (pinned
    bridge assets). LiteRT-LM (native and Web) has no TTS. Synthesis is
    runtime-native, so a custom `TextToSpeechAdapter` can target only a model
    the runtime reports as a `BackendTextToSpeechModel`.
  - LFM3-Audio / LFM3-Omni: `Lfm3AudioTtsAdapter` with the LFM3 model that has
    the `tts` chat template and its mmproj; voices `female` (default) and
    `male`; `language` is passed through unvalidated; request sampling
    settings are validated but unused (the GGUF's own apply); no speaker
    reference. 24 kHz.
  - Soprano: `SopranoTtsAdapter`; no language, voice or speaker reference;
    default `temperature` 0.8, pass 0 to match upstream's greedy example.
    32 kHz. No published llama.cpp GGUF: convert it (text-to-speech guide).
  - Chatterbox Turbo / Multilingual: `ChatterboxTtsAdapter`; voice
    `default` or a speaker reference (about 10 s; not both); request sampling
    settings apply. Turbo takes no language. Multilingual takes a code such as
    `fr` (unvalidated) and needs `ModelParams(maxParallelSequences: 2)`, else
    it is reported unsupported. 24 kHz.
  - Pocket TTS: `PocketTtsAdapter`; the projector's voices (25 in the Kyutai
    English pack, first is the default); no language; speaker reference only
    with a voice-encoder projector; request sampling validated but unused.
    24 kHz.
  - All but Qwen3-TTS are native llama.cpp only. LFM3-Audio and Soprano need
    llamadart-native v0.8.0 or later, Chatterbox and Pocket TTS v0.9.0. On an
    older runtime (or Apple companion lock) `load` throws
    `LlamaUnsupportedException` naming the release before loading any file.
    Web drives Qwen3-TTS only.
- After `attach`, `await recognizer.capabilities` /
  `synthesizer.capabilities` and gate on `isSupported`, showing
  `unsupportedReason`. A loaded projector does not prove audio support or a
  matching model. With `Qwen3AsrAdapter`, native `capabilities` reads the
  projector's GGUF header and reports a non-`qwen3a` audio projector, such as
  Qwen3-TTS's `qwen3tts_spkenc`, as unsupported; an unreadable type (Web, or
  none in the file) stays supported. A chat-model LiteRT-LM engine reports
  unsupported for STT.
- Use the capability fields instead of assuming: `inputKinds`,
  `encodedAudioFormats`, `supportsPartialResults`, `supportsStreamingInput`
  (STT); `sampleRateHz`, `supportedLanguages`, `supportsSpeakerReference`,
  `speakerReferenceInputKinds`, `supportsVoice`, `voices` (TTS).
- Audio input types are `SpeechAudioFileInput(path)`,
  `SpeechAudioBytesInput(bytes)` and `SpeechAudioPcmInput(Float32List)`, each
  with optional `SpeechAudioFormat(sampleRateHz, channelCount, encoding,
  mimeType)`.
  - Qwen3-ASR takes encoded WAV, MP3 or FLAC files or bytes; raw PCM throws
    `LlamaUnsupportedException`.
  - On Web, file paths are rejected; pass bytes with
    `SpeechAudioFormat(encoding: 'wav' | 'mp3' | 'flac')`. Missing or other
    encodings throw `LlamaAudioFormatException`.
  - LiteRT-LM takes mono 16 kHz `pcm-f32le` samples in -1.0..1.0 only
    (`SpeechAudioPcmInput`'s default format). Other formats or empty samples
    throw `LlamaAudioFormatException`. The API does not record or resample.
- `transcribe` / `synthesize` throw typed errors during preflight (invalid
  input, `LlamaUnsupportedException`, `LlamaStateException` when a speech task
  is already active). After a task starts, the single-subscription
  `task.events` stream carries progress only and never emits an error.
  `await task.result` returns the result, or throws the task's failure, or
  `LlamaStateException` when cancelled; `task.done` reports the same outcome
  (`SpeechToTextCompletionState` / `TextToSpeechCompletionState` with `error`)
  and never throws. `transcribeOnce` / `synthesizeOnce` are
  `(await start(request)).result`. After `dispose()`, starting a task throws
  `LlamaStateException`.
- Qwen3-ASR limits:
  - It is validated only up to 30 seconds per input; longer audio can
    silently drop or repeat sentences. Split recordings into windows of 30
    seconds or less.
  - The audio prompt costs about 13 tokens per second and shares context
    with the transcript. On native llama.cpp, reaching the context size or
    `maxOutputTokens` (default 1024) fails with
    `LlamaSpeechTranscriptTruncatedException`. Read `limit`
    (`LlamaSpeechTranscriptLimit.maxOutputTokens` or `.contextSize`) and
    `partialTranscript`. On Web, bridge assets with
    `supportsCompletionUsage` report truncation with `.runtime`:
    the bridge combines output, context and media caps, so do not diagnose
    the exact cause from token counts. Older assets without a termination
    signal retain their existing completion behavior.
  - An empty transcript (for example silence) fails with
    `LlamaSpeechException`. Its `details` say the model may not match the
    adapter unless the projector was verified as the adapter's.
  - A nonempty `languageHint` throws `LlamaUnsupportedException`; use
    `contextPrompt` for vocabulary. LiteRT-LM rejects `contextPrompt`.
- Results carry no timestamps, confidence or diarization. Qwen3-ASR returns
  one untimed segment. Only LiteRT-LM emits `SpeechToTextPartialEvent`:
  `confirmedText` is stable, while `pendingText` can change on the next
  window.
- LiteRT-LM initialization failures settle with a `LlamaSpeechException` and
  release the task slot, so `startStream()` or `transcribe()` can be retried.
  Await `transcribe()` and then `task.result`; startup can fail before a task
  is returned.
  Inspect the diagnostics and correct missing runtime/model assets before retrying.
- LiteRT-LM streaming: `await recognizer.startStream()`, then `await` every
  `session.addPcm(chunk)` so native backpressure throttles the producer.
  Call `await session.finish()` to flush the last window, then
  `await session.done`. Inference runs in a worker isolate; direct
  `LiteRtLmRuntimeClient` / `LiteRtLmAsrRuntimeSession` calls (from
  `package:llamadart/backend.dart`) are synchronous and must stay off a
  Flutter UI isolate.
- Cancellation is cooperative: `task.cancel()` or `await session.cancel()`.
  `done` then reports `cancelled`, and `task.result` throws
  `LlamaStateException`. `task.cancel()` stops only that task; it does not
  cancel other requests on the same `LlamaEngine`. With the pinned Web bridge,
  this includes queued STT generation and TTS startup waiting for a capability probe.
  Use `task.cancel()` for one task; `engine.cancelGeneration()` requests global generation cancellation.
  A streaming session's `events` still report a failure as a stream error (also on `session.done`), so give
  its `listen` an `onError`. Cancelling or pausing the `events`
  subscription does not stop or throttle inference. The speech engine's
  `dispose()`, and `unloadModel()` and `dispose()` on its `LlamaEngine`,
  cancel an active task.
- One typed speech task per `LlamaEngine`: all STT and TTS wrappers over an
  engine share a lease. Do not start chat generation on an attached engine
  until `task.done` completes. A LiteRT-LM recognizer allows one task per instance.
- TTS returns one complete buffer of interleaved float32 PCM (24 kHz mono for
  Qwen3-TTS, LFM3-Audio, Chatterbox and Pocket TTS, 32 kHz for Soprano; read
  `result.sampleRateHz` and `channelCount` rather than hard-coding). There are
  no playable chunks (`supportsIncrementalAudio` is false).
  - `TextToSpeechProgressEvent` (`phase`, `promptTokensRemaining`,
    `framesGenerated`) is for status UI only.
  - `result.truncated` is true when generation hit `maxFrames` (default
    512); it is not an error.
  - Use `result.toWavBytes()` for 16-bit WAV and `result.duration` for
    length.
- TTS `language` accepts the codes in `supportedLanguages` (`zh`, `en`, `ja`,
  `ko`, `de`, `fr`, `ru`, `pt`, `es`, `it`) or their English names
  (`'English'` becomes `en`). Anything else, empty text, or bad sampling values
  throw `LlamaTextToSpeechException` before the task starts.
- `TextToSpeechRequest.voice` names one of `capabilities.voices` (any case;
  null speaks the first). An unlisted name, or a voice with a speaker
  reference, throws `LlamaTextToSpeechException`; a voice for a model without
  `supportsVoice` throws `LlamaUnsupportedException`. Runtimes before
  llamadart-native v0.9.0 report `supportsVoice` with empty `voices` and check
  the name at startup.
- Speaker references must be encoded audio (`SpeechAudioBytesInput` is
  portable; file paths are native only; PCM throws). Treat them as sensitive
  user data.
- Web needs enough browser memory. The Qwen3-ASR 0.6B Q8_0 pair is about
  1.02 GB. The Qwen3-TTS pair is about 1.48 GB and also needs WebAssembly
  memory64. Model loading itself is covered by the llamadart-getting-started
  skill.

## Examples

Load Qwen3-ASR, transcribe a file and handle truncation:

```dart
import 'package:llamadart/llamadart.dart';

Future<String> transcribeFile(
  String modelPath,
  String projectorPath,
  String wavPath,
) async {
  final SpeechToTextEngine recognizer = await SpeechToTextEngine.load(
    SpeechToTextModel(
      ModelSource.path(modelPath),
      projector: ModelSource.path(projectorPath),
      adapter: const Qwen3AsrAdapter(),
    ),
  );
  try {
    final SpeechToTextResult result = await recognizer.transcribeOnce(
      SpeechToTextRequest(
        audio: SpeechAudioFileInput(wavPath),
        contextPrompt: 'llamadart, Qwen3-ASR',
      ),
    );
    return result.text;
  } on LlamaSpeechTranscriptTruncatedException catch (error) {
    print('Stopped at ${error.limit.name}; split the audio into shorter windows.');
    return error.partialTranscript;
  } on LlamaAudioFormatException catch (error) {
    print('Unsupported audio: $error');
    rethrow;
  } finally {
    await recognizer.dispose();
  }
}
```

A custom prompt adapter on an engine the caller loaded and keeps:

```dart
import 'package:llamadart/llamadart.dart';

class MyAsrAdapter extends SpeechToTextPromptAdapter {
  const MyAsrAdapter();

  @override
  String get name => 'My-ASR';

  @override
  String promptFor(SpeechToTextRequest request) => 'Transcribe the audio.';

  @override
  SpeechToTextTranscript parseTranscript(String output) =>
      SpeechToTextTranscript(output.trim());
}

Future<String> transcribeWith(LlamaEngine engine, String wavPath) async {
  final SpeechToTextEngine recognizer = SpeechToTextEngine.attach(
    engine,
    adapter: const MyAsrAdapter(),
  );
  try {
    final SpeechToTextCapabilities capabilities =
        await recognizer.capabilities;
    if (!capabilities.isSupported) {
      throw LlamaUnsupportedException(capabilities.unsupportedReason!);
    }
    final SpeechToTextResult result = await recognizer.transcribeOnce(
      SpeechToTextRequest(audio: SpeechAudioFileInput(wavPath)),
    );
    return result.text;
  } finally {
    await recognizer.dispose(); // The engine stays loaded.
  }
}
```

Live dictation with LiteRT-LM (native only):

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

Future<String?> dictate(Stream<Float32List> mono16KhzChunks) async {
  // Throws LlamaUnsupportedException where the runtime is unavailable.
  final SpeechToTextEngine recognizer = await SpeechToTextEngine.load(
    SpeechToTextModel(
      ModelSource.path('/models/moonshine_tiny.tflite'),
      tokenizer: ModelSource.path('/models/tokenizer.json'),
      adapter: const LiteRtLmAsrAdapter(LiteRtLmAsrModelPreset.moonshineTiny),
    ),
  );

  final SpeechToTextStreamingSession session = await recognizer.startStream();
  final StreamSubscription<SpeechToTextEvent> events = session.events.listen(
    (SpeechToTextEvent event) {
      if (event is SpeechToTextPartialEvent) {
        print('stable=${event.confirmedText} pending=${event.pendingText}');
      }
    },
    onError: (Object error) => print('Recognition failed: $error'),
  );

  try {
    await for (final Float32List chunk in mono16KhzChunks) {
      await session.addPcm(chunk);
    }
    await session.finish();
  } catch (_) {
    await session.cancel();
  }

  final SpeechToTextCompletion completion = await session.done;
  await events.cancel();
  await recognizer.dispose();
  print(completion.state);
  return completion.result?.text;
}
```

Synthesize speech with Qwen3-TTS and save a WAV file (native):

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

Future<void> speak(
  ModelSource model,
  ModelSource projector,
  String text,
  String outPath,
) async {
  final TextToSpeechEngine synthesizer = await TextToSpeechEngine.load(
    TextToSpeechModel(
      model,
      projector: projector,
      adapter: const Qwen3TtsAdapter(),
    ),
    onProgress: (ModelDownloadProgress progress) =>
        print('Downloading: ${progress.fraction}'),
  );

  try {
    final TextToSpeechTask task = await synthesizer.synthesize(
      TextToSpeechRequest(text: text, language: 'English', maxFrames: 1024),
    );
    task.events.listen((TextToSpeechEvent event) {
      if (event is TextToSpeechProgressEvent) {
        print('${event.phase.name}: ${event.framesGenerated} frames');
      }
    });
    final TextToSpeechResult result = await task.result;
    if (result.truncated) {
      print('Hit maxFrames; audio may end early.');
    }
    final Uint8List wav = result.toWavBytes();
    await File(outPath).writeAsBytes(wav);
    print('Wrote ${result.duration} at ${result.sampleRateHz} Hz');
  } on LlamaException catch (error) {
    print('Synthesis failed or was cancelled: $error');
  } finally {
    await synthesizer.dispose();
  }
}
```

Speak with an LFM3-Audio voice (native llama.cpp, llamadart-native v0.8.0 or
later):

```dart
import 'package:llamadart/llamadart.dart';

Future<TextToSpeechResult> speakAsMale(
  ModelSource model,
  ModelSource projector,
  String text,
) async {
  final TextToSpeechEngine synthesizer = await TextToSpeechEngine.load(
    TextToSpeechModel(
      model,
      projector: projector,
      adapter: const Lfm3AudioTtsAdapter(),
    ),
  );
  try {
    final TextToSpeechCapabilities capabilities =
        await synthesizer.capabilities;
    final String? voice = capabilities.voices.contains('male') ? 'male' : null;
    return await synthesizer.synthesizeOnce(
      TextToSpeechRequest(text: text, voice: voice),
    );
  } finally {
    await synthesizer.dispose();
  }
}
```

## More

- Speech to text: https://llamadart.leehack.com/docs/guides/speech-to-text
- Text to speech: https://llamadart.leehack.com/docs/guides/text-to-speech
- Multimodal audio chat: https://llamadart.leehack.com/docs/guides/multimodal
- WebGPU bridge: https://llamadart.leehack.com/docs/platforms/webgpu-bridge
- Support matrix: https://llamadart.leehack.com/docs/platforms/support-matrix
