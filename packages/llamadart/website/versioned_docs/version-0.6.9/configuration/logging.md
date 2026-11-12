---
title: Logging
---

`llamadart` supports separate log controls for Dart-side and native runtime
layers.

## Engine log controls

```dart
await engine.setDartLogLevel(LlamaLogLevel.info);
await engine.setNativeLogLevel(LlamaLogLevel.warn);

// or set both to same value
await engine.setLogLevel(LlamaLogLevel.error);
```

## Global Dart logger configuration

```dart
LlamaEngine.configureLogging(
  level: LlamaLogLevel.info,
  handler: (record) {
    print('[${record.level}] ${record.message}');
  },
);
```

## Recommended profiles

- Local debugging: Dart `info`, native `warn`.
- Performance testing: Dart `warn`, native `error`.
- Production app defaults: both `error` or `none`.

## Troubleshooting noisy logs

If you still see too much output, verify:

- You are not re-enabling logs in app startup paths.
- Model load/reload paths set levels before first inference.
- Any custom logger handler is filtering correctly.
