---
title: Download and cache models
sidebar_label: Downloads and cache
description: Download GGUF and LiteRT-LM models from Hugging Face or HTTP(S) with progress, retry and cancel, choose where the cache lives on each platform, and inspect or clean it.
---

On native targets, `loadModelSource(...)` downloads a remote `ModelSource` into
a package-managed cache, verifies it, and loads the cached local file. Later
loads reuse the cached file without a network request. Loading itself is
covered in [Model lifecycle](./model-lifecycle).

## Show download progress in an app

`ModelDownloadController` wraps any `ModelDownloadManager` and emits UI-ready
snapshots: a stage, a progress fraction, cancel and retry, and an error message
with URL query strings and fragments redacted. It does not depend on Flutter.

```dart
final controller = ModelDownloadController(
  manager: DefaultModelDownloadManager.auto(
    appPrivateCacheDirectory: appCacheModelsDirectory,
  ),
);

final subscription = controller.snapshots.listen((snapshot) {
  switch (snapshot.stage) {
    case ModelDownloadTaskStage.checkingCache:
      print('Checking cache for ${snapshot.source?.displayName}');
      break;
    case ModelDownloadTaskStage.downloading:
      final percent = snapshot.fraction == null
          ? 'unknown'
          : '${(snapshot.fraction! * 100).toStringAsFixed(1)}%';
      print('Downloading $percent');
      break;
    case ModelDownloadTaskStage.ready:
      print('Ready at ${snapshot.entry?.filePath}');
      break;
    case ModelDownloadTaskStage.failed:
      print(snapshot.errorMessage);
      break;
    case ModelDownloadTaskStage.cancelled:
      print('Cancelled; retry is available: ${snapshot.canRetry}');
      break;
    default:
      break;
  }
});

try {
  final entry = await controller.start(
    ModelSource.parse('hf://owner/repo/model-Q4_K_M.gguf'),
    options: ModelLoadOptions(maxRetries: 3),
  );
  await engine.loadModel(entry.filePath);
} catch (_) {
  if (controller.snapshot.canRetry) {
    // Wire this to a Retry button.
    await controller.retry();
  }
} finally {
  await subscription.cancel();
  await controller.dispose();
}
```

- Stages: `idle`, `resolving`, `checkingCache`, `downloading`, `verifying`,
  `ready`, `failed`, `cancelled`. The cache check only drives UI state; `ready`
  follows the manager's own `ensureModel(...)` validation and any checksum.
- `cancel()` requests cooperative cancellation. `retry()` after `failed` or
  `cancelled` reuses the last source and options.
- The controller owns cancellation: call `controller.cancel()` and leave
  `ModelLoadOptions.cancelToken` unset, or `start(...)` throws.
- On web, pass a custom manager for browser storage; the default manager's
  operations throw `LlamaUnsupportedException` there.

## Hugging Face `hf://` references

`hf://owner/repo/path/to/file` names one `.gguf` or `.litertlm` file and
resolves to `https://huggingface.co/owner/repo/resolve/<revision>/path/to/file`
with `download=true`. The revision defaults to `main`. The cache key uses the
stable `hf://` identity, not the resolved URL.

```dart
final main = ModelSource.parse(
  'hf://unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_K_M.gguf',
);

final litert = ModelSource.parse(
  'hf://litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm',
);

final tagged = ModelSource.parse(
  'hf://owner/repo@v1.0.0/model-Q4_K_M.gguf',
);

// Use ?revision= when the revision contains `/`, such as PR refs.
final pullRequestRef = ModelSource.parse(
  'hf://owner/repo/model-Q4_K_M.gguf?revision=refs/pr/12',
);

// The same pieces, built from app state.
final source = ModelSource.huggingFace(
  repoId: 'owner/repo',
  revision: 'main',
  filePath: 'model-Q4_K_M.gguf',
);
```

Keep the real file extension in the path: `LlamaBackend()` routes by it.

### Private and gated repositories

Pass credentials through `ModelLoadOptions`, never in the source string:

```dart
await engine.loadModelSource(
  ModelSource.parse('hf://owner/private-repo/model-Q4_K_M.gguf'),
  options: ModelLoadOptions(bearerToken: hfToken),
);
```

Bearer tokens and custom `headers` go only on download requests. They are not
part of `ModelSource.canonicalKey`, cache metadata or `toString()`.

Signed HTTP(S) URLs differ: `canonicalKey` keeps the full URL, and `cacheKey`
hashes it so distinct signed URLs stay distinct. Cache metadata and
`toString()` redact the query string, fragment and userinfo, but do not log or
persist `canonicalKey` for a signed URL.

## Download options

```dart
final cancelToken = ModelDownloadCancelToken();
final engine = LlamaEngine(
  LlamaBackend(),
  modelDownloadManager: DefaultModelDownloadManager.auto(
    appPrivateCacheDirectory: appCacheModelsDirectory,
  ),
);

await engine.loadModelSource(
  ModelSource.url(Uri.parse('https://example.com/model.gguf')),
  options: ModelLoadOptions(
    cachePolicy: ModelCachePolicy.preferCached,
    sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    bearerToken: hfToken,
    cancelToken: cancelToken,
    resume: true,
    maxRetries: 3,
  ),
  onProgress: (progress) {
    final fraction = progress.fraction;
    if (fraction != null) {
      print('download progress: ${(fraction * 100).toStringAsFixed(1)}%');
    }
  },
);
```

`ModelLoadOptions.defaults` is `preferCached`, `resume: true` and
`maxRetries: 3`.

`ModelSource.path(...)` loads apply only `sha256` and cancellation. A local
source with a non-default cache policy, `cacheDirectory`, auth headers,
`resume: false` or a non-default `maxRetries` throws
`LlamaUnsupportedException` instead of ignoring the option.

## Cache policies

- `preferCached` (default): reuse a completed cache entry; otherwise download.
- `refresh`: download again and replace the cached file atomically.
- `cacheOnly`: throw without a network request when the entry is missing.
- `noCache`: download to a temporary entry that later loads do not reuse. Call
  `remove(entry.cacheKey)` or `clear()` when done, or use `prune(...)`.

## Choose the cache location

`DefaultModelDownloadManager.auto(...)` keeps one call site for every
platform: desktop and server use a per-user shared cache; Android and iOS use
the app-private directory you pass.

```dart
// Desktop/server shared cache; app-private directory on Android/iOS.
final crossPlatformManager = DefaultModelDownloadManager.auto(
  appPrivateCacheDirectory: appCacheModelsDirectory,
);

// Desktop/server: per-user cache shared by llamadart apps.
final desktopManager = DefaultModelDownloadManager.sharedCache();

// Mobile: an app-private directory resolved by the app.
final mobileManager = DefaultModelDownloadManager.appPrivate(
  cacheDirectory: appCacheModelsDirectory,
);

// Android sharing across developers: only a directory the user granted.
final androidUserLibrary = DefaultModelDownloadManager.userSelected(
  cacheDirectory: userGrantedModelLibraryDirectory,
);

// iOS/macOS sharing between apps in the same App Group.
final appGroupLibrary = DefaultModelDownloadManager.appGroup(
  cacheDirectory: appGroupModelsDirectory,
);
```

In Flutter, resolve the mobile directory with `path_provider`:
`getApplicationCacheDirectory()` for re-downloadable models, or
`getApplicationSupportDirectory()` only when the app manages its backup
policy. Pass the result as `appPrivateCacheDirectory`, or pass
`androidAppPrivateCacheDirectory` and `iosAppPrivateCacheDirectory` to resolve
both up front. Without one, `auto(...)` falls back to
`Directory.systemTemp/llamadart/models`, which the OS may clear.

| Platform | Default root |
| --- | --- |
| Linux | `$XDG_CACHE_HOME/llamadart/models`, or `$HOME/.cache/llamadart/models` when `XDG_CACHE_HOME` is unset |
| macOS | `$HOME/Library/Caches/llamadart/models` |
| Windows | `%LOCALAPPDATA%\llamadart\models`, then `%APPDATA%\llamadart\models`, then `%USERPROFILE%\AppData\Local\llamadart\models` |
| Android/iOS | the supplied app-private directory, else `Directory.systemTemp/llamadart/models` |

- Pass `namespace: 'your.namespace'` to `auto(...)` or `sharedCache(...)` to
  replace the `llamadart` segment, or `cacheDirectory` to force a root.
- `sharedCache()` never invents a shared folder on Android or iOS: it throws
  without `cacheDirectory`. Android shares a model library only through a
  directory the user granted; iOS only within an App Group. Apps from
  unrelated iOS developers can load user-picked files but have no writable
  shared cache.
- `DefaultModelDownloadManager()`, which `LlamaEngine` uses when you pass no
  manager, uses the same defaults as `auto()`, but falls back to the system
  temp directory when no home or cache directory exists; `auto()` and
  `sharedCache()` report an error instead.
- On web, `DefaultModelDownloadManager` is a placeholder whose operations
  (`ensureModel`, `list` and the rest) throw `LlamaUnsupportedException`.
  Browser model caches are origin-scoped.

## Inspect and clean the cache

```dart
final manager = DefaultModelDownloadManager.auto(
  appPrivateCacheDirectory: appCacheModelsDirectory,
);

final cached = await manager.list();
final entry = await manager.get(
  ModelSource.parse('hf://owner/repo/model.gguf').cacheKey,
);
if (entry != null) {
  await manager.remove(entry.cacheKey);
}
await manager.prune(
  maxAge: const Duration(days: 30),
  maxBytes: 20 * 1024 * 1024 * 1024,
);
await manager.clear();
```

## Large downloads on mobile

- Show progress and a cancel control, download one large GGUF at a time, and
  ask users to keep the app open.
- Do not cancel on every lifecycle pause: Android and iOS may let a short
  screen lock or app switch continue, and an eager cancel guarantees a restart.
- Downloads are foreground Dart HTTP requests. If the OS suspends or kills the
  app, the request can fail; a later session resumes from the `.part` file
  when resume is possible (see [Reference](#reference-resume-locking-and-cache-metadata)).
- For downloads that must continue in the background, implement
  `ModelDownloadManager` in the app or a platform package: an Android
  foreground service or system `DownloadManager` with a notification, or iOS
  background `URLSession` tasks.
- For device-level sharing, use `userSelected(...)` on Android only after the
  user grants every participating app the same directory (do not request All
  Files Access by default), and `appGroup(...)` on iOS only for apps in the
  same App Group. Apps from unrelated developers should accept user-picked
  files through the document picker and copy them into the app cache: the
  loaders take file paths, not content URIs or file descriptors.

## Limits

- `hf://` names one file. A multimodal model's `mmproj` GGUF is a separate
  source; see [Multimodal](./multimodal).
- Sharded GGUF files are not expanded. Pick a single-file GGUF.
- `llamadart` does not list repository files or pick a quantization. Copy the
  exact path from the repository's **Files and versions** tab.
- URL-loading web backends accept only unauthenticated `preferCached` loads.
  Auth headers, checksums, cancel tokens, other cache policies,
  `cacheDirectory`, `resume: false` and custom retries throw
  `LlamaUnsupportedException` there, as do local paths. Use a native target
  for those.

## Reference: resume, locking and cache metadata

**Atomic writes.** Downloads go to a `.part` file, which becomes the cached
model only after the HTTP stream and any SHA-256 check succeed.

**Resume.** A retry or resume sends an HTTP `Range` request only when the
partial file has a validator (`ETag` or `Last-Modified`); otherwise it
restarts from byte zero. A server that answers a Range
request with `200 OK` also restarts it from byte zero.

**Locking.** Stable-cache downloads are serialized per cache entry within the
process, including across `DefaultModelDownloadManager` instances that share a
cache root. A same-entry caller waits for the active operation; cache-reusing
policies then re-check the cache. Different entries download in parallel.
Concurrent `refresh` calls each refresh in turn. `noCache` downloads are not
coalesced. Cancelling a waiting caller takes effect after the active operation
finishes and does not cancel it; cancelling the active download releases the
lock so a later caller can retry or resume from a safe `.part` file.

**Metadata.** Each entry has a versioned `metadata.json` sidecar next to the
model file. An entry is reused only when the sidecar matches the cache key,
file name and file path, and the file matches the recorded length and any
supplied or stored SHA-256. If the file is intact but the sidecar is missing,
malformed or from an unsupported schema version, the manager rebuilds the
sidecar without a network request, so `cacheOnly` survives metadata damage. A
missing file or a failed length or checksum check counts as a cache miss, and
cache-reusing policies download again.
