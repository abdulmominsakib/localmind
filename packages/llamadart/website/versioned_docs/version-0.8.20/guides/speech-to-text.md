---
title: Speech to Text
description: Transcribe encoded audio or stream PCM with the experimental typed speech API.
---

`SpeechToTextEngine` is the typed API for speech recognition. It is separate
from `LlamaEngine` because transcript events, timestamps, confidence, language,
speaker labels, cancellation, and audio metadata have a different contract from
chat-completion tokens.

The API currently has two experimental implementations. llama.cpp adapts
Qwen3-ASR audio input to whole-file transcription on native targets and on
validated WebGPU bridge assets. Native LiteRT-LM uses a dedicated CPU ASR engine
for incremental mono 16 kHz PCM, partial text, and finalization from a worker
isolate. Recognition quality and language behavior remain model dependent.
Generic `LlamaAudioContent` chat input still exists separately for audio-capable
multimodal models.

## Current support matrix

| Runtime | Generic audio-input chat | Typed `SpeechToTextEngine` | Text to speech |
| --- | --- | --- | --- |
| Native llama.cpp / GGUF | Model + projector dependent | Experimental Qwen3-ASR adapter; complete WAV/MP3/FLAC file or bytes, final transcript only | Experimental Qwen3-TTS adapter; see [Text to Speech](./text-to-speech) |
| WebGPU / GGUF | Bridge + model dependent | Experimental Qwen3-ASR adapter with bridge assets `v0.1.30+`; complete WAV bytes, final transcript only | Unsupported |
| Native LiteRT-LM | Separate `.litertlm` audio chat remains bundle dependent | Experimental dedicated CPU ASR through `SpeechToTextEngine.liteRtLm`; mono 16 kHz float PCM, partial/final text, streaming input | Unsupported |
| LiteRT-LM Web | Unsupported | Unsupported | Unsupported |

“Generic audio-input chat” means an audio content part is processed by normal
generation. It does not imply a transcript schema, stable ASR behavior, or TTS.
The typed STT API adds a stable Dart result/cancellation boundary. The llama.cpp
backend still performs whole-audio generation internally and reports
`SpeechToTextImplementation.multimodalPromptAdapter`. LiteRT-LM reports
`SpeechToTextImplementation.dedicatedBackend` and does not use the selected
chat model.

## Stream with dedicated LiteRT-LM ASR

LiteRT-LM v0.16 adds dedicated ASR engines that consume PCM windows instead of
an audio part in normal chat. Configure the local model/tokenizer pair, start a
stream, and await every input push so bounded native backpressure can throttle
the producer.

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
  throw StateError(capabilities.unsupportedReason);
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
```

The input contract is mono 16 kHz normalized `Float32List` PCM. The public
session owns synchronous inference in a worker isolate. `confirmedText` is
stable, while `pendingText` may change after the next inference window.
`finish` flushes a partial final window, and `cancel` is cooperative between
native windows. Pausing the event subscription does not throttle inference;
awaiting `addPcm` is the input-backpressure boundary.

The validated v0.16 contract is CPU-only. Supported metadata presets cover
Parakeet TDT, Parakeet CTC, Moonshine Tiny, Whisper Tiny, and Qwen3-ASR 0.6B,
but callers must supply a matching model and tokenizer. The API does not
capture a microphone, resample audio, or provide timestamps, confidence, or
diarization. Advanced callers can still use `LiteRtLmRuntimeClient` and
`LiteRtLmAsrRuntimeSession` directly, but those synchronous calls must not run
on a Flutter UI isolate.

## Load a Qwen3-ASR model

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

On Web, the active backend must also expose the validated prompt-speech
capability. The hosted chat app derives that opt-in from immutable
`llama-web-bridge-assets` tags `v0.1.30+`; custom hosts can explicitly set
`window.__llamadartBridgeSpeechToTextSupported` before the backend is created.
An older bridge, a missing or mismatched projector, or a failed runtime audio
probe leaves `capabilities.isSupported` false with an actionable reason.

## Transcribe a complete file

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

Native llama.cpp currently decodes WAV, MP3, and FLAC file or byte inputs. Raw
PCM remains unsupported for that prompt adapter because projector sample rates
are model-specific. Dedicated LiteRT-LM accepts `SpeechAudioPcmInput` for a
complete mono 16 kHz float buffer, or the incremental session shown above.

WebGPU accepts encoded WAV bytes only. Browser file pickers must read the
selected file into memory and use `SpeechAudioBytesInput`; local filesystem
paths, MP3, FLAC, raw PCM, and byte inputs without explicit
`SpeechAudioFormat(encoding: 'wav')` metadata are rejected. This narrower
contract reflects the published browser smoke rather than every decoder that
may be compiled into a particular bridge build.

For microphone capture, the chat app keeps the UI in its preparing state while
the browser capture graph warms up. It trims that warmup silence, inspects the
completed PCM16 WAV before inference, and rejects too-short, effectively
silent, or unsupported input with an actionable message. These checks avoid
clipping the beginning of speech or turning a missing browser input into a
slow empty-transcript failure.

`SpeechAudioFormat` also carries optional encoding and MIME metadata. Final
results reserve segment and word timing, confidence, and speaker fields so a
future backend can add them without changing the top-level API. The current
llama.cpp adapter returns one untimed segment and no confidence or diarization.

## Streaming, cancellation, and concurrency

The llama.cpp prompt adapter consumes complete encoded input and emits one final
event. Dedicated LiteRT-LM emits replaceable partial events while accepting
incremental PCM. Pausing either event stream does not throttle native
inference; LiteRT-LM producers must await `addPcm` for input backpressure.

Call `task.cancel()` to request cooperative cancellation:

```dart
final task = await recognizer.transcribe(request);
// Later:
task.cancel();
final completion = await task.done;
assert(completion.state == SpeechToTextCompletionState.cancelled);
```

Cancelling an event subscription does not cancel the native task. Call
`task.cancel()` for whole-input recognition or `await session.cancel()` for an
incremental session. All prompt-adapter wrappers over one `LlamaEngine` share a
one-task lease. A dedicated LiteRT-LM recognizer allows one active task per
`SpeechToTextEngine` instance.

## Chat app

The Flutter chat example keeps transcription and generic audio chat as
different user actions:

- **Attach Audio** sends audio through normal multimodal chat.
- **Transcribe Audio** selects one file and uses `SpeechToTextEngine` with a
  compatible GGUF ASR model. Native accepts WAV, MP3, and FLAC; Web accepts WAV.
- With Qwen3-ASR, the microphone records a temporary foreground WAV for up to
  five minutes. **Stop & transcribe** finalizes that recording and passes its
  file on native or its encoded bytes on Web to `SpeechToTextEngine`, while
  **Discard** cancels capture and removes or revokes the partial recording.
- With a native chat model, **Live transcription** uses a separately installed,
  checksum-pinned LiteRT model and tokenizer. Moonshine Tiny is the recommended
  54 MB default; Parakeet TDT 0.6B is an optional higher-capacity, heavier
  615 MB choice. The selector remembers the choice and reports model size,
  installed state, determinate download progress, cancellation, and retry. The
  app captures mono 16 kHz PCM, feeds the public worker-isolated
  `SpeechToTextEngine.liteRtLm` session, and renders monotonic confirmed text
  plus a replaceable pending suffix after each five-second window. **Use text** finalizes the
  session and inserts the result into the editable composer; it never submits
  the message automatically. Generic audio-chat models retain **Ask with
  voice** as a separate action.
- With native Gemma 4 E2B, **Ask with voice** uses either the LiteRT-LM
  direct-media bundle or the GGUF model with its matching audio-capable
  projector. It records up to 30 seconds and **Stop & ask** sends the WAV bytes
  through normal multimodal chat. The model is prompted to answer the spoken
  request; this path does not promise a transcript, timestamps, confidence,
  detected language, or live partial text. An ASR profile takes precedence
  when both capability declarations are present.

The dedicated **Transcribe Audio** action is available on Web only for the
validated Qwen3-ASR preset and runtime capability. It remains hidden for normal
LiteRT-LM chat bundles. Live dictation uses the native LiteRT-LM streaming STT
API with an app-managed sidecar; it is not a capability of the selected chat
bundle and remains unavailable on Web.
ASR microphone recordings are capped at five minutes, cancelled when the app is
backgrounded, and deleted on native or revoked on Web after transcription. This
remains a whole-file workflow: it does not produce live partial transcripts
while the user speaks. The recorder requests 16 kHz mono WAV, but hardware or
the browser may choose another valid sample rate; the downstream decoder reads
the WAV metadata.
The live sidecar path instead requests PCM16 mono 16 kHz streaming, preserves
samples split across arbitrary byte-chunk boundaries, applies one in-flight
worker push at a time, and caps each session at five minutes. It is currently
English-only and CPU-only. The composer integration is enabled on Android,
iOS, macOS, and Windows, cancelled on foreground lifecycle changes, and
disabled on Linux and Web.
Typed Qwen3-ASR microphone capture is code-supported on Android, iOS, macOS,
Windows, and secure browser origins. Browser startup still checks microphone
permission and WAV encoder support before recording. Capture remains disabled
on Linux with the current recorder plugin because its external-tool startup is
not safe to expose without a stronger preflight; selected-file transcription
is unchanged there. **Ask with voice** also requires a native direct-media
audio model or an audio-capable projector and is unavailable on Web. These
capability gates do not establish real-model behavior on every platform. The
experimental llama.cpp GGUF voice path has
engine-level Metal evidence on macOS, while current packaged microphone UI
evidence is LiteRT-LM on macOS. Android, iOS, and Windows still require
real-model/device evidence through the `chat-app-voice-question-smoke`
test-matrix row before making a platform validation claim.

The voice-question path makes a best-effort attempt to delete its temporary WAV
after reading it, but keeps the encoded audio bytes in the in-memory
conversation history so later turns and regeneration preserve context. Those
operations can reprocess the audio and consume additional memory. It remains
generic audio-input chat and does not change the typed STT support matrix above.

LiteRT-LM first initializes audio preprocessing on the selected backend, then
transparently retries CPU if that executor is incompatible and remembers the
working choice for the loaded model. For the validated Gemma 4 E2B bundle, GPU
text/vision with CPU audio is the resolved path. This is bundle/runtime
compatibility behavior, not a universal LiteRT-LM CPU-audio limitation.

The chat app catalog includes the Qwen3-ASR 0.6B Q8_0 model/projector pair on
native and Web. Its immutable artifact revision, byte sizes, and SHA-256
digests are pinned. Native downloads verify both files before selection; Web
uses origin-scoped Cache Storage and the pinned source metadata.

## Known limits

- Qwen3-ASR may emit a leading `language English<asr_text>` marker. llamadart
  strips that marker, but does not expose it as reliable detected-language
  metadata until language behavior has a dedicated validation contract.
- There are no word/segment timestamps, confidence scores, or speaker
  diarization. Incremental audio and partial text are LiteRT-LM-only.
- Inference backend correctness and performance remain device dependent;
  establish a CPU baseline before claiming GPU support for a deployment.
- The local real-model smoke has passed on macOS arm64 CPU, and a separate
  chat-app/manual smoke has passed on Metal. The full chat-app
  model/projector, microphone, and final-transcript flow has also passed on a
  physical Pixel using CPU inference and in the iOS Simulator. A physical
  iPhone and Windows remain unverified; Linux keeps selected-file STT but not
  microphone capture. Web requires `v0.1.30+`, a browser with enough memory for
  the roughly 1.02 GB model/projector pair, and the targeted
  `web-speech-to-text-smoke` validation row. That row verifies both browser
  file selection and Chromium fake-device microphone capture with the same WAV
  fixture. File selection returns the exact expected transcript; the microphone
  assertion requires the full expected transcript because Chromium loops its
  artificial input at the capture boundary. Real microphone hardware and
  browser/device combinations remain deployment-specific checks.
- TTS is a separate typed API with different models, projector capabilities,
  inputs, and output events. See [Text to Speech](./text-to-speech).
