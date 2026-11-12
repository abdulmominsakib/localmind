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

A `SpeechToTextModel` names the model's files, each a `ModelSource`, and the
adapter that drives it. The adapter picks the runtime.

| Approach | API | Runtimes | Input | Output |
| --- | --- | --- | --- | --- |
| Qwen3-ASR, whole file | `SpeechToTextEngine.load` with `Qwen3AsrAdapter`, or `attach` | Native llama.cpp; WebGPU with bridge assets `v0.1.30+` | A complete WAV, MP3, or FLAC file or bytes; bytes only on Web | One final transcript |
| Another audio chat model, whole file | `load` or `attach` with your own `SpeechToTextPromptAdapter` | As Qwen3-ASR | As Qwen3-ASR | One final transcript |
| LiteRT-LM, live streaming | `SpeechToTextEngine.load` with `LiteRtLmAsrAdapter` | Native LiteRT-LM, CPU only | Mono 16 kHz float PCM, pushed incrementally or as one buffer | Replaceable partial text, then a final transcript |
| Generic audio chat | `LlamaAudioContent` in `engine.create` | Audio-capable GGUF projectors; `.litertlm` bundles with audio | Audio as a chat content part | Ordinary chat output, no transcript contract |

LiteRT-LM Web supports none of these. A prompt adapter reports
`SpeechToTextImplementation.multimodalPromptAdapter`: it runs whole-audio
generation on a `LlamaEngine`. `LiteRtLmAsrAdapter` reports
`SpeechToTextImplementation.dedicatedBackend` and does not use a chat model.

The adapter is an explicit declaration: an audio-understanding model is not
advertised as ASR merely because it accepts audio.

## Load or attach

`SpeechToTextEngine.load` downloads each remote file into the model cache,
loads the model, and returns a recognizer that owns what it loaded.
`dispose()` releases it. `SpeechToTextEngine.attach` borrows a `LlamaEngine`
you loaded yourself, for example to chat with the same model, and its
`dispose()` leaves that engine loaded.

| | `load(model, ...)` | `attach(engine, adapter: ...)` |
| --- | --- | --- |
| Adapters | Any | `SpeechToTextPromptAdapter` only |
| Who loads the files | The recognizer, from `ModelSource`s | You |
| Capability check | `load` throws `LlamaUnsupportedException` | Read `capabilities` yourself |
| `dispose()` | Cancels the task and disposes the engine | Cancels the task; the engine stays loaded |

`load` takes `download:` (`ModelLoadOptions` for every remote file: cache
policy and directory, authentication, resume, retries and cancel token),
`onProgress:` (one combined progress for all files), `store:` (a
`ModelFileStore` with your own resolver or download manager), and, for a
prompt adapter, `params:` (`ModelParams`) and `backend:` (by default
`LlamaBackend()`). Every file resolves, main file first, before anything
loads. A local file takes only the cancel token. The bearer token and headers
are never sent across hosts: when they are set and the remote files span more
than one origin (scheme, host and port), `load` throws
`LlamaArgumentException` before downloading from another host, so load such
files from one host or leave the credentials unset. `ModelLoadOptions.sha256` throws
`LlamaUnsupportedException` for a model of more than one file. The load is
atomic: when it throws, nothing stays loaded, and downloaded files stay in the
cache.

`load` takes ownership of a `backend:` you pass: the recognizer's `dispose()`,
or a failed load, disposes it with the engine, so pass a backend that nothing
else uses.

## Transcribe a file with Qwen3-ASR

Use a matching model and multimodal projector pair. llama.cpp documents
Qwen3-ASR in its
[multimodal model list](https://github.com/ggml-org/llama.cpp/blob/b10356/docs/multimodal.md),
and published GGUF pairs are available from
[`ggml-org/Qwen3-ASR-0.6B-GGUF`](https://huggingface.co/ggml-org/Qwen3-ASR-0.6B-GGUF).
Sources may be local paths, HTTP(S) URLs or `hf://owner/repo/file` references.

```dart
final recognizer = await SpeechToTextEngine.load(
  SpeechToTextModel(
    ModelSource.path('/models/Qwen3-ASR-0.6B-Q8_0.gguf'),
    projector: ModelSource.path('/models/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf'),
    adapter: const Qwen3AsrAdapter(),
  ),
);
try {
  final result = await recognizer.transcribeOnce(
    const SpeechToTextRequest(
      audio: SpeechAudioFileInput('/recordings/meeting.wav'),
      contextPrompt: 'llamadart, Qwen3-ASR',
    ),
  );
  print(result.text);
} finally {
  await recognizer.dispose();
}
```

`load` checks `capabilities` after the model and projector load and throws
`LlamaUnsupportedException` with the reason when they cannot recognize speech.
Projector load success alone does not prove audio support.

`load` rethrows what the projector load throws. On native llama.cpp that is
`LlamaModelException` for a projector the runtime rejects, such as the
Qwen3-TTS projector with the Qwen3-ASR model, and `LlamaUnsupportedException`
when the runtime lacks the mtmd functions. On Web, it is `LlamaModelException`
when the bridge cannot fetch or load the projector.

With an engine you loaded, attach the adapter and check `capabilities`
yourself:

```dart
final recognizer = SpeechToTextEngine.attach(
  engine,
  adapter: const Qwen3AsrAdapter(),
);
final capabilities = await recognizer.capabilities;
if (!capabilities.isSupported) {
  throw StateError(capabilities.unsupportedReason!);
}
```

`transcribeOnce` returns the final result, and throws the task's failure, or
`LlamaStateException` when the task is cancelled. For events, use
`transcribe`:

```dart
final task = await recognizer.transcribe(
  const SpeechToTextRequest(
    audio: SpeechAudioFileInput('/recordings/meeting.wav'),
    contextPrompt: 'llamadart, Qwen3-ASR',
  ),
);
task.events.listen((event) {
  if (event is SpeechToTextPartialEvent) {
    print('partial: ${event.text}');
  }
});

try {
  final result = await task.result;
  print(result.text);
} on LlamaException catch (error) {
  print('Recognition failed or was cancelled: $error');
}
```

`transcribe` itself throws typed input, state, or unsupported errors when
preflight fails before a task can start. After startup, `events` is a
single-subscription stream of progress that never emits an error: a
prompt adapter emits one `SpeechToTextFinalEvent`, and LiteRT-LM emits
partial events first. `task.result` returns the transcript or throws the
failure, or `LlamaStateException` when the task is cancelled; `task.done`
reports the same outcome as a `SpeechToTextCompletion` and never throws.

## Add a model family

To recognize speech with another audio chat model on `LlamaEngine`, extend
`SpeechToTextPromptAdapter`. The recognizer sends one user turn: the text from
`promptFor`, then the audio. Natively the turn goes through the model's chat
template with thinking disabled; on Web the bridge takes the text as the raw
prompt with the audio bytes. Generation is greedy and stops at
`maxOutputTokens`. `parseTranscript` turns the complete output into a
`SpeechToTextTranscript`; an empty transcript fails the task.

```dart
class MyAsrAdapter extends SpeechToTextPromptAdapter {
  const MyAsrAdapter();

  @override
  String get name => 'My-ASR';

  @override
  bool get supportsLanguageHints => true;

  @override
  String promptFor(SpeechToTextRequest request) {
    final language = request.languageHint;
    return language == null
        ? 'Transcribe the audio.'
        : 'Transcribe the audio. It is in $language.';
  }

  @override
  SpeechToTextTranscript parseTranscript(String output) =>
      SpeechToTextTranscript(output.trim());
}

final recognizer = await SpeechToTextEngine.load(
  SpeechToTextModel(
    ModelSource.parse('hf://owner/repo/asr-model.gguf'),
    projector: ModelSource.parse('hf://owner/repo/mmproj-asr-model.gguf'),
    adapter: const MyAsrAdapter(),
  ),
);
```

`supportsLanguageHints` defaults to false, and the recognizer then rejects a
`languageHint` with `LlamaUnsupportedException`. `supportsContextPrompt`
defaults to true; `supportsLanguageDetection` defaults to false and says
whether `parseTranscript` reports `SpeechToTextTranscript.language`.
`capabilities` reports these flags. The recognizer checks only that the loaded
projector supports audio; whether the prompt suits the model is the adapter's
responsibility.

## Stream live audio with LiteRT-LM

LiteRT-LM's dedicated ASR engines (added in LiteRT-LM v0.16) consume PCM
windows instead of an audio part in normal chat. Load the model with its
tokenizer and a `LiteRtLmAsrAdapter` for the model family's preset, start a
stream, and await every input push so bounded native backpressure can
throttle the producer.

```dart
final recognizer = await SpeechToTextEngine.load(
  SpeechToTextModel(
    ModelSource.path('/models/moonshine_tiny.tflite'),
    tokenizer: ModelSource.path('/models/tokenizer.json'),
    adapter: const LiteRtLmAsrAdapter(LiteRtLmAsrModelPreset.moonshineTiny),
  ),
);

final session = await recognizer.startStream();
final events = session.events.listen(
  (event) {
    if (event is SpeechToTextPartialEvent) {
      print('stable=${event.confirmedText} pending=${event.pendingText}');
    } else if (event is SpeechToTextFinalEvent) {
      print('final=${event.result.text}');
    }
  },
  // A session's events report a failure as an error too; done carries it.
  onError: (Object _) {},
);

for (final chunk in mono16KhzFloatPcmChunks) {
  await session.addPcm(chunk);
}
await session.finish();
final completion = await session.done;
await events.cancel();
print(completion.state);
await recognizer.dispose();
```

`load` probes the LiteRT-LM ASR runtime before it downloads anything and
throws `LlamaUnsupportedException` when the runtime is unavailable, including
on Web. It then resolves the model and tokenizer, each a local path, an
HTTP(S) URL or a Hugging Face file, to local files, model first, downloading
remote ones into the model cache as described under
[Load or attach](#load-or-attach); each `transcribe` or `startStream` starts its
own native session on them. The
adapter carries the runtime settings (`backend`, `numberOfThreads`,
`maxBufferedAudio`, `overlapRatio`, and `libraryPath` for local validation),
so `params:` and `backend:` must be null. A `LiteRtLmAsrAdapter` model takes
no projector, and a prompt adapter model no tokenizer.

The session runs synchronous inference in a worker isolate. `confirmedText` is
stable, while `pendingText` may change after the next inference window.
`finish` flushes a partial final window.

`LiteRtLmAsrBackend.cpu` is the only backend. Metadata presets cover Parakeet
TDT, Parakeet CTC, Moonshine Tiny, Whisper Tiny, and Qwen3-ASR 0.6B, but
callers must supply a matching model and tokenizer. The API does not capture a
microphone or resample audio. Advanced callers can use `LiteRtLmRuntimeClient`
and `LiteRtLmAsrRuntimeSession` from `package:llamadart/backend.dart` directly
with local files, but those synchronous calls must not run on a Flutter UI
isolate.

## Cancel, dispose and concurrency

```dart
final task = await recognizer.transcribe(request);
// Later:
task.cancel();
final completion = await task.done;
assert(completion.state == SpeechToTextCompletionState.cancelled);
```

Cancellation is cooperative: `task.cancel()` for whole-input recognition, or
`await session.cancel()` for a LiteRT-LM session, which stops between native
windows. `task.cancel()` stops only that task: on a prompt adapter it cancels
the task's own generation and no other request on the same `LlamaEngine`. A
session's `cancel()` returns a future because it ends a live input
stream and releases the native recognizer; a session has no single `result`. Cancelling or pausing an event subscription neither cancels nor
throttles native inference; LiteRT-LM producers must await `addPcm` for input
backpressure.

`dispose()` cancels a running task or stream, waits for it to stop, and
disposes the engine that `load` created. Calling it again is safe, and
`isDisposed` reports it. After `dispose()`, `transcribe` and `startStream`
throw `LlamaStateException` and `capabilities` reports unsupported.

All prompt-adapter recognizers and text-to-speech wrappers over one
`LlamaEngine` share a one-task lease. Direct `LlamaEngine.create` calls on a
borrowed engine must not run during a task. A LiteRT-LM recognizer allows one
active task per `SpeechToTextEngine` instance.

## Input formats and length

Qwen3-ASR recognition is validated up to 30 seconds per input. Longer inputs
can drop or repeat sentences without reaching any limit, so split longer
recordings into windows of at most 30 seconds. Built-in windowing is tracked in
[#327](https://github.com/leehack/llamadart/issues/327).

A Qwen3-ASR prompt grows by about 13 tokens per second of audio, and the
transcript shares the same context. On native llama.cpp, a prompt-adapter task
that reaches the context size or `maxOutputTokens` before the transcript ends
fails with `LlamaSpeechTranscriptTruncatedException`. Its `limit` names the
limit that stopped recognition and `partialTranscript` holds the text produced
before it. A task whose transcript is empty, for example from silent input,
fails with `LlamaSpeechException`.

Native llama.cpp accepts WAV, MP3, and FLAC file or byte inputs. Raw PCM is
unsupported for prompt adapters because projector sample rates are
model-specific. LiteRT-LM accepts `SpeechAudioPcmInput` for a complete mono
16 kHz normalized `Float32List` buffer, or the incremental session above.

`SpeechAudioFormat` carries optional encoding and MIME metadata. Final results
reserve segment and word timing, confidence, and speaker fields for future
backends; prompt adapters return one untimed segment.

## Web

Web runs prompt adapters, such as Qwen3-ASR, through WebGPU bridge assets
`v0.1.30+`. The hosted chat app derives the capability from the immutable
`llama-web-bridge-assets` tag; custom hosts can set
`window.__llamadartBridgeSpeechToTextSupported` before the backend is created.
An older bridge, no loaded projector, a projector without audio support, or a
failed runtime audio probe makes `load` throw `LlamaUnsupportedException`, and
leaves an attached recognizer's `capabilities.isSupported` false, with an
actionable reason. On Web, `load` passes the sources to the browser runtime,
which fetches each file itself: a `ModelSource.path` is a URL relative to the
document, or a `blob:` URL, and `download` must stay at its defaults.

WebGPU accepts encoded WAV, MP3, and FLAC bytes. Read the selected file into
memory and pass `SpeechAudioBytesInput` with a `SpeechAudioFormat` whose
`encoding` is `'wav'`, `'mp3'` or `'flac'`; local filesystem paths, other
encodings, raw PCM, and bytes without that metadata are rejected. The bridge
reports truncation through `onUsage` when its `supportsCompletionUsage`
probe is true (`v0.1.54+`). A cut-off Web transcript then fails with
`LlamaSpeechTranscriptTruncatedException`, whose `limit` is
`LlamaSpeechTranscriptLimit.runtime`: the bridge combines output-token,
context and media caps, so the error cannot name the exact cause. Its
`partialTranscript` holds the text produced before the limit. Older bridges
without this signal retain their existing completion behavior. The browser
needs enough memory for the roughly 1.02 GB Qwen3-ASR
0.6B Q8_0 model/projector pair.

## Known limits

- Validated with Qwen3-ASR 0.6B Q8_0 on WAV up to 33 s, and on MP3 and FLAC
  copies of the 11 s `jfk.wav` on native macOS and in headless Chromium. The
  audio prompt grows with duration (3,890 tokens for 297 s in
  [#636](https://github.com/leehack/llamadart/issues/636)).
- Qwen3-ASR may emit a leading `language English<asr_text>` marker.
  `Qwen3AsrAdapter` strips that marker, but does not expose it as reliable
  detected-language metadata until language behavior has a dedicated
  validation contract.
- There are no word/segment timestamps, confidence scores, or speaker
  diarization. Incremental audio and partial text are LiteRT-LM-only.
- Inference backend correctness and performance remain device dependent;
  establish a CPU baseline before claiming GPU support for a deployment.
- The [chat app](../examples/chat-app) shows file transcription, microphone
  capture, and live dictation built on this API.
