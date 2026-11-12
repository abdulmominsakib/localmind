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

Symptoms:

- The app loads, but model load fails only on web.
- WebGPU falls back to CPU or reports lower GPU layers than requested.
- A hosted build behaves differently from `localhost`.

Checks:

1. Confirm bridge runtime is loaded successfully:
   `window.LlamaWebGpuBridge` should exist and
   `window.__llamadartBridgeLoadError` should be empty.
2. Verify browser capability: secure context, `navigator.gpu`,
   `requestAdapter()`, adapter features/limits, and current GPU drivers.
3. For large single-file GGUF loads, verify cross-origin isolation:
   `window.crossOriginIsolated === true` and the app origin sends COOP/COEP
   headers.
4. Distinguish bridge-load failures from model/config pressure. Memory errors,
   `bad_alloc`, `memory access out of bounds`, or aborts often mean the model,
   context size, thread count, or GPU-layer count is too large for the current
   browser.
5. Validate model URLs, CORS/CORP policy, base href, service-worker cache state,
   and whether the runtime came from CDN or local assets.
6. See [WebGPU Bridge](../platforms/webgpu-bridge) for the readiness probe,
   fallback rules, and Flutter Web smoke-test command.

## High log noise

Use split log levels:

```dart
await engine.setDartLogLevel(LlamaLogLevel.warn);
await engine.setNativeLogLevel(LlamaLogLevel.error);
```
