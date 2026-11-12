---
title: Logging
description: Configure Dart-side and native log levels and a log handler with LlamaLogging.configure, and quiet noisy runtime output.
---

`llamadart` has one logging configuration for the whole library: a level for
Dart-side records, a level for the native runtime and a handler. Both levels
default to `none`.

For distributed traces, token metrics and exporter setup, see
[Observability](../guides/observability).

## Configure logging

```dart
await LlamaLogging.configure(
  level: LlamaLogLevel.info,
  nativeLevel: LlamaLogLevel.warn, // defaults to level
  handler: (record) {
    print('[${record.level}] ${record.message}');
  },
);
```

Every engine shares this configuration, so the last `configure` call wins,
whatever the order of calls or the engine they came from. The new levels apply
at once on the calling isolate and to engines loaded later, and are sent to
the worker isolates and native runtimes of running engines. The returned
future completes when they have taken them, or after at most one second. A
worker that does not answer in time, such as one busy with a generation, logs
a warning and takes them when its current operation finishes; a backend that
fails logs a warning too. Without a `handler`, records are
printed. Configure logging before loading a model to capture load-time
output; `LlamaLogging.level` and `LlamaLogging.nativeLevel` read the current
levels.

`LlamaEngine.configureLogging`, `engine.setLogLevel`,
`engine.setDartLogLevel`, `engine.setNativeLogLevel`, `engine.dartLogLevel`
and `engine.nativeLogLevel` are deprecated forwarders to this configuration.

## Backend worker isolates

The native llama.cpp and LiteRT-LM backends run in a worker isolate. A worker
forwards only records at or above `level` to the main isolate, where the
handler receives them after the main-isolate level is applied again. At the
default `none` nothing is forwarded.

A forwarded record carries its error as `toString` text and its stack trace
rebuilt from text. A worker forwards at most 1000 `debug` records; records
above `debug` are never capped. An error thrown by the handler on a forwarded
record is printed, not thrown. Web backends run on the main isolate and are
unaffected.

## Image generation runtime

The opt-in `stable_diffusion` runtime logs through the same handler.
`ImageGenerationEngine.load` takes the levels it finds and the runtime
records from the stricter of `level` and `nativeLevel`, so a later
`configure` call applies to the next load. Its messages arrive after each
load and generation, not while one runs, and are not printed to stderr at
any level; see [Runtime logs](../guides/image-generation#runtime-logs).

## Recommended profiles

- Local debugging: `level: info`, `nativeLevel: warn`.
- Performance testing: `level: warn`, `nativeLevel: error`.
- Production: both `error` or `none`.

If output stays noisy, check that app startup or model reload paths do not
raise the levels again, and that a custom handler filters as intended.

## Native output outside llamadart's control

On the native LiteRT-LM backend, a `nativeLevel` of `LlamaLogLevel.none` is
passed to the runtime as silent before each engine create and stops the
runtime library's own absl, LiteRT and TFLite loggers. The prebuilt WebGPU
accelerator (`libLiteRtWebGpuAccelerator`) links its own absl and exports no
logging control, so a GPU engine create still writes `I0000` info lines to
stderr. A CPU-only load writes nothing. Verified on macOS arm64 with LiteRT-LM
0.17.0-6 and Qwen3-0.6B at `none`; source line numbers and the adapter string
vary by release and GPU:

```text
I0000 ... environment.cc:...] Selected adapter: Apple M4 Max, arch=metal-3, vendor=apple, backend=Metal, ...
I0000 ... delegate_webgpu.cc:...] # of threads to upload weights = 2
I0000 ... delegate_webgpu.cc:...] # of threads to compile kernels = 1
I0000 ... delegate_kernel.cc:...] Total 113 external tensors are used for delegate inputs and outputs
I0000 ... delegate_kernel.cc:...] Initializing WebGPU-based API from serialized data.
```

`llamadart` cannot filter or redirect these lines; an app that must hide them
has to capture the process stderr itself. Tracked in
[#568](https://github.com/leehack/llamadart/issues/568).
