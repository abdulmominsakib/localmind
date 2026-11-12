---
title: Model Lifecycle
---

This guide covers model load/unload flows and safe lifecycle patterns.

## Single model lifecycle

```dart
final engine = LlamaEngine(LlamaBackend());
await engine.loadModel('/path/to/model.gguf');

// ...run inference...

await engine.unloadModel();
await engine.dispose();
```

## Switching models

`LlamaEngine.loadModel(...)` requires no currently loaded model. Unload first:

```dart
await engine.unloadModel();
await engine.loadModel('/path/to/another_model.gguf');
```

## Load from URL (web-focused)

```dart
await engine.loadModelFromUrl(
  'https://example.com/model.gguf',
  onProgress: (progress) => print('progress: $progress'),
);
```

`loadModelFromUrl` requires a backend with URL loading support.

## Structured model sources

Use `loadModelSource(...)` when the caller wants to describe the model location
as a value object instead of branching on raw strings:

```dart
await engine.loadModelSource(ModelSource.path('/path/to/model.gguf'));

await engine.loadModelSource(
  ModelSource.url(Uri.parse('https://example.com/model.gguf')),
  onProgress: (progress) {
    final fraction = progress.fraction;
    if (fraction != null) {
      print('download progress: ${(fraction * 100).toStringAsFixed(1)}%');
    }
  },
);

await engine.loadModelSource(
  ModelSource.parse('hf://owner/repo/path/to/model.gguf'),
);
```

`ModelSource.parse(...)` accepts local paths, HTTP(S) URLs, and `hf://`
Hugging Face references. Local path sources require native/file-backed targets;
URL-loading web backends reject explicit local filesystem paths and should use
HTTP(S) or `hf://` sources instead. Local paths already point at a file, so the
native manager only applies cancellation and optional `sha256` verification to
`ModelSource.path(...)` loads. Remote/download-only options such as non-default
cache policies, `cacheDirectory`, authenticated headers, `resume`, and
`maxRetries` are rejected for local paths instead of being silently ignored.
Source values expose deterministic cache keys and redacted metadata identities
so signed URL query strings are not stored in logs or cache metadata.

### Hugging Face `hf://` references

Use `hf://owner/repo/path/to/model.gguf` for a public GGUF file. The shorthand
resolves to `https://huggingface.co/owner/repo/resolve/main/path/to/model.gguf`
with `download=true` and uses the stable `hf://...` identity for cache keys.

```dart
final main = ModelSource.parse(
  'hf://unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_K_M.gguf',
);

final tagged = ModelSource.parse(
  'hf://owner/repo@v1.0.0/model-Q4_K_M.gguf',
);

// Use ?revision= when the revision itself contains `/`, such as PR refs.
final pullRequestRef = ModelSource.parse(
  'hf://owner/repo/model-Q4_K_M.gguf?revision=refs/pr/12',
);
```

`ModelSource.huggingFace(...)` exposes the same pieces directly when building a
source from app state:

```dart
final source = ModelSource.huggingFace(
  repoId: 'owner/repo',
  revision: 'main',
  filePath: 'model-Q4_K_M.gguf',
);
```

Private or gated repositories should pass credentials through
`ModelLoadOptions`, not in the source string:

```dart
await engine.loadModelSource(
  ModelSource.parse('hf://owner/private-repo/model-Q4_K_M.gguf'),
  options: ModelLoadOptions(bearerToken: hfToken),
);
```

Bearer tokens and custom headers are used only for remote download requests and
are not part of `ModelSource.canonicalKey`, cache metadata, or `toString()`.
Signed HTTP(S) URLs are different: `ModelSource.canonicalKey` keeps the full
raw URL and `cacheKey` hashes that full identity so distinct signed URLs stay
unique. Persisted cache metadata and `toString()` redact query strings and
append the deterministic cache key, but callers should not log or persist
`canonicalKey` for signed URLs that carry secrets.

Current limitations:

- `hf://` identifies one file. For multimodal models, create a separate source
  for the model GGUF and the `mmproj` GGUF, then load/cache each asset according
  to the API you are using.
- Sharded GGUF manifests are not expanded automatically; track that as a
  separate design before relying on sharded repos.
- `llamadart` does not list Hugging Face files or choose recommended
  quantizations for you. Pick the exact `.gguf` file path from the repository's
  **Files and versions** tab.

Native/file-backed backends download remote sources into the package-managed
cache, verify the completed file, persist metadata, and then call the existing
local `loadModel(...)` path. URL-capable web backends keep using
`loadModelFromUrl(...)` for simple unauthenticated `preferCached` requests; use
native/file-backed targets when you need authenticated headers, checksum
verification, explicit cache policies, retries, or resume.

```dart
final cancelToken = ModelDownloadCancelToken();

await engine.loadModelSource(
  ModelSource.url(Uri.parse('https://example.com/model.gguf')),
  options: ModelLoadOptions(
    cachePolicy: ModelCachePolicy.preferCached,
    cacheDirectory: '/app/cache/llamadart-models',
    sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    bearerToken: 'hf_xxx',
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

Cache policies:

- `preferCached`: reuse a completed cache entry when present; otherwise download.
- `refresh`: replace the cached file atomically.
- `cacheOnly`: fail without a network request when the entry is missing.
- `noCache`: download to a temporary manager entry without source-keyed reuse; call
  `remove(entry.cacheKey)`/`clear()` when the returned file is no longer needed, or
  use thresholded `prune(...)` for age/size-based cleanup.

The download manager can also inspect and clean the persisted cache:

```dart
final manager = DefaultModelDownloadManager(
  defaultCacheDirectory: '/app/cache/llamadart-models',
);

final cached = await manager.list();
final entry = await manager.get(ModelSource.parse('hf://owner/repo/model.gguf').cacheKey);
if (entry != null) {
  await manager.remove(entry.cacheKey);
}
await manager.prune(maxAge: const Duration(days: 30), maxBytes: 20 * 1024 * 1024 * 1024);
await manager.clear();
```

### App-friendly download controller

Flutter apps often need more than byte callbacks: they need stable UI states,
retry/cancel controls, cache-hit handling, and a safe error string for snackbars
or banners. `ModelDownloadController` wraps any `ModelDownloadManager` and emits
that lifecycle without depending on Flutter:

```dart
final controller = ModelDownloadController(
  manager: DefaultModelDownloadManager(
    defaultCacheDirectory: '/app/cache/llamadart-models',
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

Controller stages are `idle`, `resolving`, `checkingCache`, `downloading`,
`verifying`, `ready`, `failed`, and `cancelled`. The cache check is advisory for
UI state only; `ready` is emitted only after the manager's authoritative
`ensureModel(...)` path validates the cache entry and any caller-provided
checksum. Call `cancel()` from your UI to request cooperative cancellation; call
`retry()` after `failed` or `cancelled` to reuse the last source/options. Because
the controller owns cancellation, pass cache/auth/retry options through
`ModelLoadOptions` but call `controller.cancel()` instead of supplying
`ModelLoadOptions.cancelToken`. Error messages redact URL query strings and
fragments so signed URLs or tokens are not shown in UI logs. On web, inject a
custom manager for browser-specific storage; the default package manager remains
native/file-backed.

Downloaded files are written to `.part` files and promoted to the completed
model path only after the HTTP stream and optional SHA-256 verification succeed.
Stable-cache remote downloads are serialized per cache entry in-process,
including across `DefaultModelDownloadManager` instances that share a cache root:
same-entry callers wait for the active operation, cache-reusing policies then
re-check the completed cache, and different cache entries remain parallel.
Concurrent `refresh` calls are serialized but each refreshes when its turn runs;
`noCache` transient downloads are not stable-cache coalesced. Cancelling a
waiting caller is observed after the active same-entry operation finishes and
does not cancel that active download; cancellation of the active download
releases the entry lock so a later caller can retry or resume from a safe `.part`
file.

Cache metadata uses a versioned `metadata.json` sidecar next to the completed
model file. A completed cache entry is reused only when the sidecar matches the
requested cache key, file name, and file path, and the file still satisfies the
recorded byte length plus any caller-supplied or previously stored SHA-256. If a
completed file remains but the sidecar is missing, malformed, or written by an
unsupported schema version, the native manager rebuilds a fresh versioned
sidecar from the deterministic source/cache identity instead of touching the
network; `cacheOnly` can therefore recover from metadata-only damage. If the
file is missing or fails the recorded length/checksum checks, the entry is
ignored as a cache miss and cache-reusing policies re-download safely.

Retry/resume use HTTP Range only when the partial file has a safe validator
(ETag/Last-Modified) or the caller supplied a SHA-256 checksum; validator-less
partials restart from byte zero. If a server ignores a resume request and
returns `200 OK`, the manager also restarts from byte zero. Signed URL query
strings, fragments, and userinfo are redacted from display strings and metadata.

### Mobile large-download guidance

For Flutter apps, pass an app-controlled `cacheDirectory` from your storage
strategy (for example an application-support or documents directory selected by
`path_provider`). Surface progress/cancel controls in the UI, keep downloads
serialized for large GGUF files, and tell users to keep the app open for the
foreground download. Do not cancel purely because the app receives a lifecycle
pause: Android/iOS may allow short screen-lock or app-switch interruptions to
continue, while an eager cancellation guarantees a pause on every lock.

Foreground Dart HTTP requests are still not a substitute for native background
downloads. If the OS suspends or kills the app, the request can fail later. The
`.part` resume support lets a later foreground session continue when the server
supports Range requests and exposes a safe validator or the caller supplies
SHA-256. On Android, a robust always-continue UX needs an app-owned foreground
service or system `DownloadManager` flow with a notification; on iOS, use
background `URLSession` download tasks. Implement those policies in the app or
an optional platform package that implements `ModelDownloadManager`, not in the
core package.

For shared device-level GGUF storage, keep the same separation: core
`llamadart` exposes source identities, cache metadata, progress, cancellation,
retry, and verification hooks; a future opt-in platform model-store package can
decide how apps share files, metadata, permissions, pruning, and native
background download execution. On Android, prefer app-private storage unless the
app intentionally exposes model files to the user; on iOS, avoid cache
directories that the OS may purge while a model is still needed.

## State persistence

Native backends and WebGPU bridge assets `v0.1.15+` can save and restore
llama.cpp KV-cache state to avoid re-evaluating a long raw prompt on resume or
when forking a prompt prefix. Gate the flow with `supportsStatePersistence` so
backends that do not implement state persistence can fall back to prompt
re-evaluation. If a web app overrides the bridge to older/custom assets that do
not expose state APIs, `stateSaveFile(...)` / `stateLoadFile(...)` throw a clear
unsupported error and callers should use the same fallback path.

```dart
if (!engine.supportsStatePersistence) {
  throw LlamaUnsupportedException('State persistence is not supported by this backend.');
}

final prompt = 'You are a concise assistant. Summarize llamadart.';
final tokens = await engine.tokenize(prompt);

// Populate the KV cache, then persist it with the token sequence that produced
// state. This sample uses a WebGPU bridge WASMFS virtual path. Native apps
// should replace it with an app-writable filesystem path.
const statePath = '/prompt-prefix.state';

await engine.generate(
  prompt,
  params: const GenerationParams(maxTokens: 1, reusePromptPrefix: true),
).drain<void>();
await engine.stateSaveFile(statePath, tokens: tokens);

// Later, after loading the same model with a compatible runtime/bridge build:
final restored = await engine.stateLoadFile(
  statePath,
  tokenCapacity: await engine.getContextSize(),
);

await for (final token in engine.generate(
  '$prompt Continue from the saved prefix.',
  params: const GenerationParams(reusePromptPrefix: true),
)) {
  print(token);
}

print('Restored ${restored.tokens.length} prompt tokens');
```

Important caveats:

- State files are opaque llama.cpp artifacts. Treat them as tied to the same
  model file and compatible runtime/build that created them. Web paths refer to
  the bridge WASMFS virtual filesystem and are not durable across page reloads.
  Durable browser storage currently requires app-level export/import outside the
  Dart `stateSaveFile` / `stateLoadFile` helpers.
- `stateLoadFile(...)` restores native KV-cache state only. It does not rebuild
  `ChatSession` message history; persist and reconstruct chat messages
  separately when using the high-level chat API.
- Pass a `tokenCapacity` large enough for the saved prompt token sequence. The
  current context size is usually a safe default.

## Multimodal projector lifecycle

```dart
await engine.loadMultimodalProjector('/path/to/mmproj.gguf');
final canSee = await engine.supportsVision;
final canHear = await engine.supportsAudio;
print('vision=$canSee audio=$canHear');
```

Projector resources are released by `unloadModel()` or `dispose()`.

## LoRA adapters at runtime

```dart
await engine.setLora('/path/to/adapter.gguf', scale: 0.8);
await engine.removeLora('/path/to/adapter.gguf');
await engine.clearLoras();
```

See [LoRA Adapters](./lora-adapters) for scaling strategy, stacking, and
platform-specific behavior.

## Recommended lifecycle checks

- Check `engine.isReady` before inference paths.
- Use `try/finally` to guarantee `dispose()` on shutdown.
- Keep model switch logic serialized to avoid overlapping load/unload calls.
