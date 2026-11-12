---
title: Common Issues
---

## Runtime bundle or native asset load failure

Symptoms:

- Model fails to load on first run.
- Errors about missing native libs.

Checks:

1. Ensure internet connectivity for first runtime bundle resolution.
2. Verify your app can access GitHub release endpoints.
3. If backend config changed recently, run `flutter clean` once.

## Model path or URL issues

Symptoms:

- `Failed to load model` errors.

Checks:

1. Confirm path exists and is readable.
2. Confirm file is valid GGUF.
3. For URL loading, confirm backend/platform supports URL model load.

## Slow generation

Checks:

1. Reduce model size or quantization level.
2. Tune `contextSize` and generation length (`maxTokens`).
3. Use appropriate backend and GPU offload (`gpuLayers`).

## Tool calling seems unstable

Checks:

1. Use `ToolChoice.auto` before forcing `required`.
2. Lower temperature for tool-calling requests.
3. Validate tool schema and required parameters.
4. Ensure your loop appends tool result messages correctly.

## Web behavior differs from native

Checks:

1. Confirm bridge runtime is loaded successfully.
2. Verify browser WebGPU support and fallback behavior.
3. Validate model URLs and CORS policy for hosted assets.

## High log noise

Use split log levels:

```dart
await engine.setDartLogLevel(LlamaLogLevel.warn);
await engine.setNativeLogLevel(LlamaLogLevel.error);
```
