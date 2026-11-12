---
title: Share models between apps
sidebar_label: Shared model store
description: The separate llamadart_model_store package keeps model and projector files in a directory several apps share, and deletes them only when no app references them. Platform boundaries, behavior and open design questions.
---

`llamadart_model_store` is a separate, independently versioned Flutter
package. It is not published yet and requires `llamadart` 0.17. Core
behavior does not change for apps that do not use it.

Its `ModelStore` keeps each `LlamaModel`, model and projector together, as one
entry in a directory every participating app can open, and records which apps
reference each entry. A file is deleted only when no app references it. Files
are downloaded, resumed, verified and locked by core's
`DefaultModelDownloadManager`; see [Downloads and cache](./model-downloads).

```dart
final store = await ModelStore.open(
  directory: sharedDirectory,
  appId: 'com.example.chat',
);
final entry = await store.ensure(
  LlamaModel(
    ModelSource.parse('hf://owner/repo/model-Q4_K_M.gguf'),
    projector: ModelSource.parse('hf://owner/repo/mmproj-F16.gguf'),
  ),
);
final engine = await LlamaEngine.load(entry.toLlamaModel());

// When the app no longer needs the model:
await store.release(entry.id);
```

`ModelStore` implements `ModelDownloadManager`, so it also works with
`ModelDownloadController` and as an engine's download manager through
`ModelFileStore(downloadManager: store)`; each file the engine downloads then
becomes a single-file entry the app references. The
[package README](https://github.com/leehack/llamadart/blob/main/packages/llamadart_model_store/README.md)
covers the API, the fallback to an app-local cache, and the on-disk layout.

## Platform boundaries

The store shares files only between apps that can open the same directory as
a file path. It never invents a shared folder.

| Platform | Sharing boundary | Store |
| --- | --- | --- |
| Linux, macOS, Windows | Every process of the user | A per-user directory, such as one under `defaultSharedCacheDirectory()` |
| Android | Apps the user granted the same directory | Only a directory that apps reach as a file path. Storage Access Framework tree grants give content URIs, which the loaders cannot open. Do not request All Files Access to get a path. |
| iOS and sandboxed macOS | Apps in one App Group | The App Group container. Apps from unrelated developers have no shared writable directory; they can only load files the user picks. |
| Web | None | `ModelStore.open` throws `LlamaUnsupportedException`: browser caches are origin-scoped. |

`ModelStore.open` throws `LlamaUnsupportedException` when the directory cannot
be created, written or locked, so an app can fall back to its own cache.

## Behavior

- **One logical entry.** A model and its projector share an entry id derived
  from both files' cache keys. A projector two entries share stays until
  neither is referenced.
- **References before downloads.** `ensure` records the app's reference
  before downloading, under a store-wide lock that `release`, `remove`,
  `clear` and `prune` also take. Another app therefore never deletes a file
  that is downloading for, or was just returned to, an app that references
  it. A failed or cancelled `ensure` leaves the app's references as they
  were before the call; overlapping calls of one app count as one, keeping
  the reference when any succeeds. Partial files stay for a retry to resume.
- **Deletes only unreferenced files.** `release` drops this app's reference
  and deletes files no app references. `remove` and `clear` do the same and
  throw `ModelCacheEntryInUseException` naming files they kept because
  another app references them or they are downloading elsewhere. `prune`
  never deletes a referenced file; it also drops file metadata whose file is
  gone, but leaves partial downloads.
- **Refused deletes.** A file the OS refuses to delete for good, such as one
  in a read-only directory, stays intact and reusable. `release`, `remove`
  and `clear` delete everything else and then throw that
  `FileSystemException`; the reference is gone either way. `prune` skips such
  a file so it never blocks the rest.
- **No secrets in shared metadata.** Store metadata holds file cache keys
  (SHA-256 hashes), app ids and timestamps. Tokens, headers and URLs are never
  written; core's file metadata redacts URL query strings, fragments and
  userinfo. Every app sharing the store can read the other apps' ids.
- **Credentials stay on one host.** As in `LlamaEngine.load`, a bearer token
  or headers for a model and projector on different hosts throw
  `LlamaArgumentException`.
- **Version skew.** An entry a store version cannot read but that has
  references keeps every file, so an older app never deletes what a newer
  app's entry protects.

## Limits

- Downloads run in the foreground, as with `DefaultModelDownloadManager`.
  Background downloads that survive sleep need platform executors: Android
  user-initiated data-transfer jobs or a foreground service, and iOS
  background `URLSession` tasks handed to the store at relaunch. They are not
  part of this version ([#1499](https://github.com/leehack/llamadart/issues/1499)). Android's system `DownloadManager` is not an option
  for authenticated sources because it persists request headers.
- Use a store from one isolate per process. Its lock excludes other
  processes but, on Linux, macOS, Android and iOS, not another isolate of
  the same process, and the store does not detect one: calls from two
  isolates are not serialized, so a release in one can delete files a
  concurrent call in the other is about to return. Spellings of the store
  directory through symbolic links resolve to one store.
- The store lock is held only around metadata updates, and core holds its
  entry lock during a download. On iOS, finish or cancel downloads in an App
  Group container before the app is suspended, or iOS terminates it
  (`0xdead10cc`).
- References from an app that was uninstalled stay until another app with
  the user's consent clears them; the store has no policy for that yet.

## Open design questions

These need a maintainer decision before the platform executors land.

1. **Stale references.** Whether a user-facing app may drop other apps'
   references, for example after confirming with the user, or references
   expire after a period without use.
2. **Android file access.** Whether loading from a file descriptor is a
   `llamadart-native` prerequisite, so a Storage Access Framework grant can be
   shared without a file path.
3. **Background transfer handoff.** Core gains
   `DefaultModelDownloadManager.importDownloadedFile` to verify a file a
   platform executor downloaded and move it into place atomically.
4. **Desktop interop.** Whether the desktop store adopts content-addressed
   blobs compatible with the Hugging Face hub cache.
5. **Multi-file sets.** Whether shard sets, such as the Safetensors sets of
   [#1219](https://github.com/leehack/llamadart/issues/1219), become
   multi-file entries the same way.
6. **Abandoned partial downloads.** Whether `prune` deletes partial downloads
   no app references. Deleting one safely needs core's entry lock, which core
   does not export, or a core `prune` option for partial files.
