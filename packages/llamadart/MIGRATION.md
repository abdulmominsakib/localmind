# Migration Guide

This document covers the major breaking upgrade paths.

## Next release: model download/cache defaults

No source migration is required for existing calls: `DefaultModelDownloadManager`
constructors remain source-compatible, and the new mobile-specific directory
arguments on `DefaultModelDownloadManager.auto(...)` are optional.

There are two intentional runtime default changes to be aware of:

1. `DefaultModelDownloadManager()` no longer defaults to the process temporary
   directory on desktop/server platforms. It now uses the same platform cache
   root as `DefaultModelDownloadManager.auto()`:

   | Platform | New default root |
   | --- | --- |
   | Linux | `$XDG_CACHE_HOME/llamadart/models`, or `$HOME/.cache/llamadart/models` when `XDG_CACHE_HOME` is unset |
   | macOS | `$HOME/Library/Caches/llamadart/models` |
   | Windows | `%LOCALAPPDATA%\llamadart\models`, then `%APPDATA%\llamadart\models`, then `%USERPROFILE%\AppData\Local\llamadart\models` |

   If a desktop/server embedder cannot expose a home/cache environment, the
   default constructor preserves compatibility by falling back to
   `Directory.systemTemp/llamadart/models`. Explicit `auto(...)` and
   `sharedCache(...)` calls still report cache-resolution errors so apps can
   choose a durable directory.

2. `DefaultModelDownloadManager.auto(platform: android/ios)` without an explicit
   mobile directory no longer throws. It now uses an app-private temporary/cache
   fallback at `Directory.systemTemp/llamadart/models`. This is convenient for
   examples and rebuildable downloads, but large durable mobile model files
   should still use an app-private cache/support directory resolved by the app.
   For Flutter apps, prefer `path_provider.getApplicationCacheDirectory()` for
   re-downloadable model caches; use `getApplicationSupportDirectory()` only for
   app-owned durable support files when the app also accounts for platform
   backup/no-backup policy.

Recommended cross-platform setup:

```dart
final engine = LlamaEngine(
  LlamaBackend(),
  modelDownloadManager: DefaultModelDownloadManager.auto(
    // On Flutter, pass a path resolved by path_provider for the current app.
    // For re-downloadable model caches, prefer getApplicationCacheDirectory().
    // Desktop/server ignores this and uses the per-user shared cache.
    appPrivateCacheDirectory: appCacheModelsDirectory,
  ),
);
```

If your app resolves platform-specific mobile directories ahead of time, pass
both without adding `Platform.isAndroid` / `Platform.isIOS` branches around the
download manager constructor:

```dart
final manager = DefaultModelDownloadManager.auto(
  androidAppPrivateCacheDirectory: androidModelsDirectory,
  iosAppPrivateCacheDirectory: iosModelsDirectory,
);
```

To preserve the old temporary-cache behavior exactly on desktop/server, pass an
explicit directory:

```dart
final manager = DefaultModelDownloadManager(
  defaultCacheDirectory: path.join(
    Directory.systemTemp.path,
    'llamadart',
    'models',
  ),
);
```

If your application previously called `DefaultModelDownloadManager.auto()` on
Android/iOS and expected a `LlamaUnsupportedException`, update that test or call
`DefaultModelDownloadManager.sharedCache()` without `cacheDirectory` when you
specifically want to reject implicit mobile shared caches.

## `0.6.3` -> `0.6.4`

No public API break, but Android arm64 native packaging defaults changed.

- Shorthand config such as `android-arm64: [vulkan]` is still supported.
- If no CPU policy is set, Android arm64 now defaults to
  `cpu_profile: full` (all CPU variants).
- If you want smaller baseline-only packaging, set
  `cpu_profile: compact` explicitly.
- `cpu_variants: [...]` (when provided) overrides `cpu_profile`.

Example (preserve compact baseline-style packaging):

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_backends:
        platforms:
          android-arm64:
            backends: [vulkan]
            cpu_profile: compact
```

## `0.5.x` -> `0.6.x`

### Template routing / handler APIs

The legacy custom handler/override registry APIs were removed:

- `ChatTemplateEngine.registerHandler(...)`
- `ChatTemplateEngine.unregisterHandler(...)`
- `ChatTemplateEngine.clearCustomHandlers(...)`
- `ChatTemplateEngine.registerTemplateOverride(...)`
- `ChatTemplateEngine.unregisterTemplateOverride(...)`
- `ChatTemplateEngine.clearTemplateOverrides(...)`

Legacy per-call handler routing fields were also removed:

- render param: `customHandlerId`
- parse param: `handlerId`

### Error behavior in template render/parse

Template render/parse paths no longer silently downgrade to content-only
fallback when a handler/parser fails. Failures are now surfaced to the caller.

Audit call sites that previously relied on silent fallback behavior and handle
exceptions explicitly.

## `0.4.x` -> `0.5.0`

## 1) ChatSession API

- Old pattern (string-in, string-out helpers):
  - `session.chat(...)`
  - `session.chatText(...)`
- New pattern:
  - `session.create(List<LlamaContentPart> ...)`
  - stream `LlamaCompletionChunk`

Example migration:

```dart
// Before
await for (final token in session.chat('Hello')) {
  stdout.write(token);
}

// After
await for (final chunk in session.create([LlamaTextContent('Hello')])) {
  stdout.write(chunk.choices.first.delta.content ?? '');
}
```

## 2) LlamaChatMessage constructor names

- `LlamaChatMessage.text(...)` -> `LlamaChatMessage.fromText(...)`
- `LlamaChatMessage.multimodal(...)` -> `LlamaChatMessage.withContent(...)`

Example migration:

```dart
// Before
LlamaChatMessage.text(role: LlamaChatRole.user, content: 'Hi');

// After
LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi');
```

## 3) Logging configuration moved off ModelParams

- Removed: `ModelParams(logLevel: ...)`
- Use engine-level controls instead:
  - `await engine.setDartLogLevel(...)`
  - `await engine.setNativeLogLevel(...)`
  - or `await engine.setLogLevel(...)` to set both

Example migration:

```dart
// Before
await engine.loadModel(path, modelParams: ModelParams(logLevel: LlamaLogLevel.info));

// After
await engine.setNativeLogLevel(LlamaLogLevel.info);
await engine.loadModel(path);
```

## 4) Model reload lifecycle

- `loadModel(...)` now throws if a model is already loaded.
- Call `await engine.unloadModel()` (or `dispose()`) before loading another model.

## 5) Public exports tightened

The package root (`package:llamadart/llamadart.dart`) no longer exports some
previous internals. In particular:

- `ToolRegistry`
- `LlamaTokenizer`
- `ChatTemplateProcessor`

Use `LlamaEngine`, `ChatSession`, `ToolDefinition`, and the template APIs as
the supported surface.

## 6) Custom backend implementers

If you maintain your own `LlamaBackend` implementation, update it to match the
current interface:

- Add `getVramInfo()`.
- Update `applyChatTemplate(...)` signature/return type (string-based prompt
  rendering input/output).

## 7) Template routing in strict parity mode

Template/render/parse behavior is now strict llama.cpp parity:

- `customTemplate` remains supported for per-call template overrides.
- Legacy `customHandlerId`/parse `handlerId` routing was removed.
- `ChatTemplateEngine.registerHandler(...)` and
  `ChatTemplateEngine.registerTemplateOverride(...)` were removed.
- Render/parse paths no longer silently downgrade to content-only fallback when
  a handler/parser fails; failures are surfaced to the caller.

## 8) Quick migration checklist

- Replace old `ChatSession` chat helpers with `create(...)` streaming.
- Rename `LlamaChatMessage` named constructors.
- Remove `ModelParams.logLevel` usage.
- Audit imports that depended on removed root exports.
- For custom backends, implement the latest `LlamaBackend` interface.
