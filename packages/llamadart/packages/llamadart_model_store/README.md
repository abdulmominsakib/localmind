# llamadart_model_store

A model store that every [`llamadart`](https://pub.dev/packages/llamadart) app
able to open the same directory shares: download a GGUF once and reuse it
across apps, without one app deleting a model another still uses.

- A model and its multimodal projector are one entry.
- Each app records a reference to the entries it uses. A file is deleted only
  when no app references it.
- Files are downloaded, resumed, verified and locked by core's
  `DefaultModelDownloadManager`, so a file becomes visible only once it is
  complete.
- `ModelStore` implements `ModelDownloadManager`, so it plugs into
  `ModelDownloadController` and `ModelFileStore(downloadManager: store)`.

This package is versioned independently of core and is not yet published. It
requires `llamadart` 0.17.

## Use the store when the app has one, else the app cache

```dart
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_model_store/llamadart_model_store.dart';

Future<LlamaModel> resolve(LlamaModel model, String? sharedDirectory) async {
  if (sharedDirectory != null) {
    try {
      final store = await ModelStore.open(
        directory: sharedDirectory,
        appId: 'com.example.chat',
      );
      return (await store.ensure(model)).toLlamaModel();
    } on LlamaUnsupportedException {
      // No shared directory on this platform or file system.
    }
  }
  return model; // The engine downloads into its app-local cache.
}

final engine = await LlamaEngine.load(
  await resolve(
    LlamaModel(
      ModelSource.parse('hf://owner/repo/model-Q4_K_M.gguf'),
      projector: ModelSource.parse('hf://owner/repo/mmproj-F16.gguf'),
    ),
    sharedDirectory,
  ),
);
```

When the app is done with a model:

```dart
await store.release(ModelStore.entryIdFor(model));
```

`entries()` lists complete entries with the apps that reference them, for a
model-library screen.

## Which directory

| Platform | Directory every participating app can open |
| --- | --- |
| Linux, macOS, Windows | A per-user directory, for example under `DefaultModelDownloadManager.defaultSharedCacheDirectory()` |
| Android | A directory the user granted every participating app as a file path. Storage Access Framework content URIs are not paths, and model loaders take paths. |
| iOS, macOS sandboxed | A directory in an App Group container shared by the apps; apps from unrelated developers cannot share one |
| Web | None: `ModelStore.open` throws `LlamaUnsupportedException` |

`ModelStore.open` probes the directory and throws `LlamaUnsupportedException`
when it cannot be created, written or locked.

## Behavior

- `ensure` records the app's reference before downloading, so no other app
  deletes the files while they download. A failed or cancelled call leaves
  the app's references as they were before it; overlapping calls of one app
  count as one, keeping the reference when any succeeds. Downloaded and
  partial files stay for a retry to resume.
- `release`, `remove` and `clear` drop this app's references, then delete
  files no app references. Files another app references, or that are
  downloading elsewhere, stay, and the call throws
  `ModelCacheEntryInUseException` naming them (`release` keeps another
  entry's files silently). A file the OS refuses to delete, such as one in a
  read-only directory, stays intact and reusable; the call deletes the rest
  and then throws that `FileSystemException`.
- `prune` deletes only unreferenced files, by age then by size, and file
  metadata whose file is gone. It skips files in use or that the OS refuses
  to delete, and partial downloads stay.
- `ensureModel` records a single-file entry, so an engine using the store as
  its download manager is protected the same way. Local files and `noCache`
  downloads pass through without a reference.
- Credentials and `sha256` apply as in `LlamaEngine.load`: credentials are
  never sent to a second host, and `sha256` needs a model without projector.
- Store metadata holds cache keys, app ids and timestamps: every app can read
  the ids of the others. URLs, tokens and headers are never written.
- Downloads run in the foreground. Background transfers need platform
  executors that are not part of this version.
- Use a store from one isolate per process. Its lock excludes other
  processes but, on Linux, macOS, Android and iOS, not another isolate of the
  same process, and the store does not detect one: calls from two isolates
  are not serialized, so a release in one can delete files a concurrent call
  in the other is about to return.
- `directory` resolves symbolic links, so every spelling of one directory
  opens the same store.
- Resolve the OS-provided directory and reopen the store on every launch.
  If an app update moves it, `entries`, `list` and `get` report retained files
  at their current paths before another `ensure`; release and pruning still
  honor app references. Persist model sources or entry ids, not file paths.
- On iOS, the store holds a file lock in the App Group container only for
  the metadata update around a call, and a download holds core's entry lock:
  finish or cancel downloads before the app is suspended.

## Layout

```
<directory>/
  store.lock               store-wide lock for reference changes
  files/                   DefaultModelDownloadManager cache root
  entries/<entry id>/
    entry.json             the entry's file cache keys
    refs/<sha256(appId)>.json
```

Entry ids derive from the files' `ModelSource.cacheKey`s, so every app and
platform computes the same id. An entry whose metadata a store version cannot
read, but which has references, keeps every file: nothing is deleted until it
is released.

See the [shared model store guide](https://llamadart.leehack.com/docs/guides/model-store)
for the design and its open questions.
