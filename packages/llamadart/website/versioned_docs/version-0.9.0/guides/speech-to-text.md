---
title: On-device speech to text
sidebar_label: Speech to text
description: Transcribe audio files with Qwen3-ASR or stream live PCM with LiteRT-LM through the experimental typed SpeechToTextEngine API.
---

`SpeechToTextEngine` is the typed, experimental API for speech recognition. It
is separate from `LlamaEngine` because transcript events, cancellation, and
audio metadata have a different contract from chat-completion tokens.
Recognition quality and language behavior are model dependent. For speech
synthesis, see [Text to Speech](./text-to-speech).

## Choose an approach

| Approach | API | Runtimes | Input | Output |
| --- | --- | --- | --- | --- |
| Qwen3-ASR, whole file | `SpeechToTextEngine(engine, modelProfile: SpeechToTextModelProfile.qwen3Asr)` | Native llama.cpp; WebGPU with bridge assets `v0.1.30+` | A complete WAV, MP3, or FLAC file or bytes; bytes only on Web | One final transcript |
| LiteRT-LM, live streaming | `SpeechToTextEngine.liteRtLm(...)` | Native LiteRT-LM, CPU only | Mono 16 kHz float PCM, pushed incrementally or as one buffer | Replaceable partial text, then a final transcript |
| Generic audio chat | `LlamaAudioContent` in `engine.create` | Audio-capable GGUF projectors; `.litertlm` bundles with audio | Audio as a chat content part | Ordinary chat output, no transcript contract |

LiteRT-LM Web supports none of these. The Qwen3-ASR adapter reports
`SpeechToTextImplementation.multimodalPromptAdapter`: it runs whole-audio
generation internally. LiteRT-LM reports
`SpeechToTextImplementation.dedicatedBackend` and does not use the loaded chat
model.

## Transcribe a file with Qwen3-ASR

Use a matching model and multimodal projector pair. llama.cpp documents
Qwen3-ASR in its
[multimodal model list](https://github.com/ggml-org/llama.cpp/blob/b10356/docs/multimodal.md),
and published GGUF pairs are available from
[`ggml-org/Qwen3-ASR-0.6B-GGUF`](https://huggingface.co/ggml-org/Qwen3-ASR-0.6B-GGUF).

```dart
final engine = LlamaEngine(LlamaBackend());
await engine.loadModel('/models/Qwen3-ASR-0.6B-Q8_0.gguf');
await engine.loadMultimodalProjector(
  '/models/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf',
);

final recognizer = SpeechToTextEngine(
  engine,
  modelProfile: SpeechToTextModelProfile.qwen3Asr,
);
final capabilities = await recognizer.capabilities;
if (!capabilities.isSupported) {
  throw StateError(capabilities.unsupportedReason!);
}
```

Always check `capabilities` after both artifacts are loaded. Projector load
success alone does not prove audio support. The required `modelProfile` is an
explicit declaration that prevents an ordinary audio-understanding model from
being advertised as ASR merely because it accepts audio.

On native llama.cpp, `loadMultimodalProjector` itself throws when it cannot
load the projector: `LlamaModelException` for a missing file or a projector the
runtime rejects, such as the Qwen3-TTS projector with the Qwen3-ASR model, and
`LlamaUnsupportedException` when the runtime lacks the mtmd functions. On Web,
it throws `LlamaModelException` when the bridge cannot fetch or load the
projector.

```dart
final task = await recognizer.transcribe(
  const SpeechToTextRequest(
    audio: SpeechAudioFileInput('/recordings/meeting.wav'),
    contextPrompt: 'llamadart, Qwen3-ASR',
  ),
);

try {
  await for (final event in task.events) {
    if (event is SpeechToTextFinalEvent) {
      print(event.result.text);
    }
  }
} on LlamaException catch (error) {
  print('Recognition failed: $error');
}

final completion = await task.done;
print(completion.state);
```

`transcribe` itself throws typed input, state, or unsupported errors when
preflight fails before a task can start. After startup, `events` is a
single-subscription stream: runtime failure is emitted as a stream error and
the same terminal condition is available through `task.done`.

## Stream live audio with LiteRT-LM

LiteRT-LM's dedicated ASR engines (added in LiteRT-LM v0.16) consume PCM
windows instead of an audio part in normal chat. Configure the local
model/tokenizer pair, start a stream, and await every input push so bounded
native backpressure can throttle the producer.

```dart
final recognizer = SpeechToTextEngine.liteRtLm(
  const LiteRtLmAsrRuntimeConfig(
    modelPath: '/models/moonshine_tiny.tflite',
    tokenizerPath: '/models/tokenizer.json',
    modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
  ),
);

final capabilities = await recognizer.capabilities;
if (!capabilities.isSupported) {
  throw StateError(capabilities.unsupportedReason!);
}

final session = await recognizer.startStream();
final events = session.events.listen((event) {
  if (event is SpeechToTextPartialEvent) {
    print('stable=${event.confirmedText} pending=${event.pendingText}');
  } else if (event is SpeechToTextFinalEvent) {
    print('final=${event.result.text}');
  }
});

for (final chunk in mono16KhzFloatPcmChunks) {
  await session.addPcm(chunk);
}
await session.finish();
final completion = await session.done;
await events.cancel();
print(completion.state);
```

The session runs synchronous inference in a worker isolate. `confirmedText` is
stable, while `pendingText` may change after the next inference window.
`finish` flushes a partial final window.

`LiteRtLmAsrBackend.cpu` is the only backend. Metadata presets cover Parakeet
TDT, Parakeet CTC, Moonshine Tiny, Whisper Tiny, and Qwen3-ASR 0.6B, but
callers must supply a matching model and tokenizer. The API does not capture a
microphone or resample audio. Advanced callers can use `LiteRtLmRuntimeClient`
and `LiteRtLmAsrRuntimeSession` directly, but those synchronous calls must not
run on a Flutter UI isolate.

## Cancel and concurrency

```dart
final task = await recognizer.transcribe(request);
// Later:
task.cancel();
final completion = await task.done;
assert(completion.state == SpeechToTextCompletionState.cancelled);
```

Cancellation is cooperative: `task.cancel()` for whole-input recognition, or
`await session.cancel()` for a LiteRT-LM session, which stops between native
windows. Cancelling or pausing an event subscription neither cancels nor
throttles native inference; LiteRT-LM producers must await `addPcm` for input
backpressure.

All Qwen3-ASR wrappers over one `LlamaEngine` share a one-task lease. A
LiteRT-LM recognizer allows one active task per `SpeechToTextEngine` instance.

## Input formats and length

Qwen3-ASR recognition is validated up to 30 seconds per input. Longer inputs
can drop or repeat sentences without reaching any limit, so split longer
recordings into windows of at most 30 seconds. Built-in windowing is tracked in
[#327](https://github.com/leehack/llamadart/issues/327).

A Qwen3-ASR prompt grows by about 13 tokens per second of audio, and the
transcript shares the same context. On native llama.cpp, a task that reaches
the context size or `maxOutputTokens` before the transcript ends fails with
`LlamaSpeechTranscriptTruncatedException`. Its `limit` names the limit that
stopped recognition and `partialTranscript` holds the text produced before it.
A Qwen3-ASR task whose transcript is empty, for example from silent input,
fails with `LlamaSpeechException`.

Native llama.cpp accepts WAV, MP3, and FLAC file or byte inputs. Raw PCM is
unsupported for the prompt adapter because projector sample rates are
model-specific. LiteRT-LM accepts `SpeechAudioPcmInput` for a complete mono
16 kHz normalized `Float32List` buffer, or the incremental session above.

`SpeechAudioFormat` carries optional encoding and MIME metadata. Final results
reserve segment and word timing, confidence, and speaker fields for future
backends; the Qwen3-ASR adapter returns one untimed segment.

## Web

Web runs the Qwen3-ASR adapter through WebGPU bridge assets `v0.1.30+`. The
hosted chat app derives the capability from the immutable
`llama-web-bridge-assets` tag; custom hosts can set
`window.__llamadartBridgeSpeechToTextSupported` before the backend is created.
An older bridge, no loaded projector, a projector without audio support, or a
failed runtime audio probe leaves `capabilities.isSupported` false with an
actionable reason.

WebGPU accepts encoded WAV, MP3, and FLAC bytes. Read the selected file into
memory and pass `SpeechAudioBytesInput` with a `SpeechAudioFormat` whose
`encoding` is `'wav'`, `'mp3'` or `'flac'`; local filesystem paths, other
encodings, raw PCM, and bytes without that metadata are rejected. The bridge
does not report why generation stopped, so a truncated Web transcript still
completes. The browser needs enough memory for the roughly 1.02 GB Qwen3-ASR
0.6B Q8_0 model/projector pair.

## Known limits

- Validated with Qwen3-ASR 0.6B Q8_0 on WAV up to 33 s, and on MP3 and FLAC
  copies of the 11 s `jfk.wav` on native macOS and in headless Chromium. The
  audio prompt grows with duration (3,890 tokens for 297 s in
  [#636](https://github.com/leehack/llamadart/issues/636)).
- Qwen3-ASR may emit a leading `language English<asr_text>` marker. llamadart
  strips that marker, but does not expose it as reliable detected-language
  metadata until language behavior has a dedicated validation contract.
- There are no word/segment timestamps, confidence scores, or speaker
  diarization. Incremental audio and partial text are LiteRT-LM-only.
- Inference backend correctness and performance remain device dependent;
  establish a CPU baseline before claiming GPU support for a deployment.
- The [chat app](../examples/chat-app) shows file transcription, microphone
  capture, and live dictation built on this API.
