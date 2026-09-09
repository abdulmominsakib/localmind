# Issue #78 and imported-model/TTS review fixes

Validated on 2026-09-08 against LocalMind 1.7.9 (84).

## Changes

- Preserve the existing Ollama fix that removes trailing empty assistant placeholders and sends native `think` controls.
- Keep native `message.thinking` and `message.content` authoritative and separate, including when the thinking field is empty.
- Handle legacy leading `<think>...</think>` content across stream boundaries. Tags later in an ordinary answer are preserved. Unclosed reasoning remains reasoning rather than being guessed into a final answer.
- Preserve Ollama's final frame without a trailing newline, including UTF-8 text split across network chunks.
- Add saved Model default / On / Off thinking controls to imported GGUF model cards in Local Models. Apply changes at the next generation, including when the model is already loaded. Explicit Off reaches llama.cpp through llamadart's `enableThinking` option. The model's template must support the option.
- Preserve the system TTS engine's voice/language instead of forcing en-US. Follow changes to Android's default TTS engine, await engine initialization, surface failed playback, and avoid starting speech after cancellation during setup.
- Declare Android TTS service discovery. Translate the new model controls into every supported locale.

Reasoning auto-collapse continues to respect the user's existing setting and manual expand/collapse choices.

## Automated verification

- `fvm flutter test`: 382 passed, one environment-dependent test skipped.
- `fvm flutter --suppress-analytics analyze`: no issues.
- `fvm flutter --suppress-analytics build apk --debug --target-platform android-arm64`: succeeded.
- `git diff --check`: clean.

Regression coverage includes native/legacy Ollama channel separation, split tags, UTF-8 boundaries, final frames without newlines, preference persistence and UI editing, actual forwarding to the inference API, default-engine changes, and TTS initialization failures.

## Android runtime verification

Installed the final debug APK on the Pixel 9 Pro Android 16 emulator and verified successful startup. The merged manifest contains `android.intent.action.TTS_SERVICE`.

Installed the Sherpa 1.13.7 arm64 English Piper lessac-low engine linked from the [official Sherpa APK catalog](https://k2-fsa.github.io/sherpa/onnx/tts/apk-engine.html). Selected it as Android's system TTS engine, then used LocalMind's existing Text To Speech → Speak sample.

Native logs confirmed:

- Binding to `com.k2fsa.sherpa.onnx.tts.engine`.
- Sherpa received and synthesized the sample text.
- LocalMind's utterance started at 21:49:23 and completed at 21:49:31.
- Restoring the original system engine without restarting LocalMind bound to `com.google.android.tts`; the next sample started at 21:50:33 and completed at 21:50:41.

The emulator was launched without host audio; this verifies synthesis and playback completion callbacks, not subjective audio quality. The temporary system-engine override was removed after testing.

## Remaining environment limits

The reporter's remote Ollama server and qwen3.5:9b model were not available for a live reproduction. Ollama behavior is verified with captured-request and streaming regression tests. Android 12 hardware was not available; the device smoke test used Android 16. This work does not publish a store release or modify the server's model template.
