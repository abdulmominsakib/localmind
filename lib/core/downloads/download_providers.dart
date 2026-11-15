import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../providers/app_providers.dart';
import '../providers/service_providers.dart';
import '../providers/storage_providers.dart';
import '../utils/disk_space.dart';
import 'download_engine.dart';

/// Shared download engine singleton: one queue, one task store, one
/// sidecar/resume lineage — consumed by the GGUF import flow and TTS bundle
/// downloads alike so both share the concurrency bound and OS background
/// handoff.
final downloadEngineProvider = Provider<DownloadEngine>((ref) {
  final engine = DownloadEngine(
    store: DownloadTaskStore(ref.read(sharedPreferencesProvider)),
    dio: ref.read(dioProvider),
    // Scratch directory for in-flight archives and partials. The name is
    // historical (GGUF imports came first); renaming it would orphan the
    // .part lineage of tasks already persisted across an upgrade.
    workDirectory: () async {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'imported_gguf_models'));
      return dir;
    },
    tokenResolver: () => ref.read(settingsProvider).huggingFaceToken,
    freeDiskSpaceBytes: freeDiskSpaceBytes,
  );
  ref.onDispose(() => engine.dispose());
  return engine;
});
