---
title: Logging
description: Control Dart-side and native log levels separately, configure logging in worker isolates, and quiet noisy runtime output.
---

`llamadart` has separate log levels for Dart-side records and the native
runtime. Both default to `none`.

For distributed traces, token metrics and exporter setup, see
[Observability](../guides/observability).

## Engine log controls

```dart
await engine.setDartLogLevel(LlamaLogLevel.info);
await engine.setNativeLogLevel(LlamaLogLevel.warn);

// or set both to the same value
await engine.setLogLevel(LlamaLogLevel.error);
```

`setDartLogLevel` and `setLogLevel` also apply the Dart level to a running
native backend worker (see [Backend worker isolates](#backend-worker-isolates)).
Set levels before `loadModel` to capture load-time output.

## Global Dart logger configuration

```dart
LlamaEngine.configureLogging(
  level: LlamaLogLevel.info,
  handler: (record) {
    print('[${record.level}] ${record.message}');
  },
);
```

## Backend worker isolates

The native llama.cpp and LiteRT-LM backends run in a worker isolate. A worker
takes the Dart logger level when it starts and forwards only records at or
above that level to the main isolate, where the `configureLogging` handler
receives them after the main-isolate level is applied again.
`engine.setDartLogLevel` and `engine.setLogLevel` change the level of a
running worker too; a later `configureLogging` call changes only the handler
and the main-isolate level. At the default `none` nothing is forwarded.

A forwarded record carries its error as `toString` text and its stack trace
rebuilt from text. A worker forwards at most 1000 `debug` records; records
above `debug` are never capped. An error thrown by the handler on a forwarded
record is printed, not thrown. Web backends run on the main isolate and are
unaffected.

## Recommended profiles

- Local debugging: Dart `info`, native `warn`.
- Performance testing: Dart `warn`, native `error`.
- Production: both `error` or `none`.

If output stays noisy, check that app startup or model reload paths do not
raise the levels again, and that a custom `configureLogging` handler filters
as intended.

## Native output outside llamadart's control

On the native LiteRT-LM backend, `setNativeLogLevel(LlamaLogLevel.none)` is
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
