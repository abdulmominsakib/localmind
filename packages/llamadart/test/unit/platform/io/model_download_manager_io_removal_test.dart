@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:llamadart/src/platform/io/model_cache_entry_lock.dart';
import 'package:llamadart/src/platform/io/model_download_manager_io.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../support/dart_script_snapshot.dart';
import '../../../support/windows_directory_handle.dart';

void main() {
  late String childSnapshot;
  late Directory root;
  late HttpServer server;
  late DefaultModelDownloadManager manager;

  setUpAll(() async {
    childSnapshot = await compileDartScript(
      'test/support/model_cache_clear_child.dart',
    );
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('llamadart_cache_removal_');
    addTearDown(() => root.delete(recursive: true));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentLength = 1024;
      request.response.add(List<int>.filled(1024, 7));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    manager = DefaultModelDownloadManager(defaultCacheDirectory: root.path);
  });

  Future<void> populate(int count) async {
    for (var i = 0; i < count; i += 1) {
      await manager.ensureModel(
        ModelSource.url(
          Uri.parse('http://127.0.0.1:${server.port}/model$i.gguf'),
          fileName: 'model$i.gguf',
        ),
      );
    }
  }

  test('clears in several processes and this one report no entry in use, '
      'since each takes the removal lock until it finishes deleting', () async {
    for (var round = 0; round < 3; round += 1) {
      await populate(60);
      final goDirectory = await Directory.systemTemp.createTemp(
        'llamadart_cache_removal_go_',
      );
      addTearDown(() => goDirectory.delete(recursive: true));
      final go = path.join(goDirectory.path, 'go');
      final children = <Process>[];
      final lines = <StreamIterator<String>>[];
      for (var i = 0; i < 3; i += 1) {
        final child = await Process.start(Platform.resolvedExecutable, <String>[
          childSnapshot,
          root.path,
          go,
        ]);
        addTearDown(() async {
          child.kill();
          await child.exitCode;
        });
        children.add(child);
        lines.add(
          StreamIterator(
            child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter()),
          ),
        );
      }
      Future<Map<String, Object?>> nextEvent(
        StreamIterator<String> lines,
      ) async {
        expect(
          await lines.moveNext().timeout(const Duration(seconds: 60)),
          isTrue,
        );
        return jsonDecode(lines.current) as Map<String, Object?>;
      }

      for (final childLines in lines) {
        expect((await nextEvent(childLines))['event'], 'ready');
      }
      File(go).writeAsStringSync('go');

      await manager.clear();
      for (final childLines in lines) {
        final done = await nextEvent(childLines);
        expect(done['errors'], isEmpty);
        expect(done['inUse'], 0);
      }
      for (final child in children) {
        await child.exitCode;
      }
      for (final childLines in lines) {
        await childLines.cancel();
      }
      expect(await manager.list(), isEmpty);
    }
  });

  group('on Windows, an entry another remover is deleting', () {
    late Directory entry;
    late _EntryTypeOverrides overrides;

    setUp(() async {
      await populate(1);
      entry = root.listSync().whereType<Directory>().singleWhere(
        (directory) => path.basename(directory.path) != '.locks',
      );
      overrides = _EntryTypeOverrides(entry.path);
    });

    /// Empties the entry and holds it pending delete until the returned
    /// function finishes deleting it.
    void Function() markPendingDelete() {
      for (final file in entry.listSync().whereType<File>()) {
        file.deleteSync();
      }
      final finishDelete = markWindowsDirectoryDeletePending(entry.path);
      addTearDown(finishDelete);
      return finishDelete;
    }

    Future<T> withOverrides<T>(Future<T> Function() body) =>
        IOOverrides.runWithIOOverrides(body, overrides);

    Future<void> clear() => withOverrides(manager.clear);

    /// Starts [operation] and holds it at the removal lock, after it has
    /// checked the entry, until the returned function runs.
    Future<({Future<void> clearing, void Function() proceed})>
    heldAtRemovalLock(Future<void> Function() operation) async {
      final waiting = Completer<void>();
      final proceed = Completer<void>();
      modelCacheEntryLocker = (lockPath, {required throwIfCancelled}) async {
        if (path.basename(lockPath) == '.removal.lock' &&
            !waiting.isCompleted) {
          waiting.complete();
          await proceed.future;
        }
        return acquireModelCacheEntryLock(
          lockPath,
          throwIfCancelled: throwIfCancelled,
        );
      };
      addTearDown(() => modelCacheEntryLocker = acquireModelCacheEntryLock);
      void release() {
        if (!proceed.isCompleted) {
          proceed.complete();
        }
      }

      final clearing = withOverrides(operation);
      addTearDown(() async {
        release();
        await clearing.then<void>((_) {}, onError: (Object _) {});
      });
      await waiting.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError(
          'The operation never reached the .removal.lock: it no longer takes '
          'the lock this test holds it at.',
        ),
      );
      return (clearing: clearing, proceed: release);
    }

    Future<({Future<void> clearing, void Function() proceed})>
    clearHeldAtRemovalLock() => heldAtRemovalLock(manager.clear);

    void expectOnlyLocksLeftOnceDeleted(void Function() finishDelete) {
      finishDelete();
      expect(
        root.listSync().map((entity) => path.basename(entity.path)),
        <String>['.locks'],
      );
    }

    test('reads as missing and fails to open with access denied', () {
      markPendingDelete();

      expect(
        FileSystemEntity.typeSync(entry.path, followLinks: false),
        FileSystemEntityType.notFound,
      );
      expect(entry.resolveSymbolicLinksSync, throwsA(_accessDenied));
    });

    test('is skipped when the deletion starts after clear finds the entry '
        'and before it resolves it', () async {
      void Function()? finishDelete;
      overrides.afterFirstCheck = () async =>
          finishDelete = markPendingDelete();

      await clear();

      expect(finishDelete, isNotNull);
      expectOnlyLocksLeftOnceDeleted(finishDelete!);
    });

    test('is skipped when the deletion happens while clear waits for the '
        'removal lock', () async {
      final held = await clearHeldAtRemovalLock();
      final finishDelete = markPendingDelete();
      held.proceed();

      await held.clearing;
      expectOnlyLocksLeftOnceDeleted(finishDelete);
    });

    test('is skipped by remove when the deletion happens while it waits for '
        'the removal lock', () async {
      final cacheKey = (await manager.list()).single.cacheKey;
      final held = await heldAtRemovalLock(() => manager.remove(cacheKey));
      final finishDelete = markPendingDelete();
      held.proceed();

      await held.clearing;
      expectOnlyLocksLeftOnceDeleted(finishDelete);
    });

    test('is skipped by prune when the deletion happens while it waits for '
        'the removal lock', () async {
      final held = await heldAtRemovalLock(
        () => manager.prune(maxAge: Duration.zero),
      );
      final finishDelete = markPendingDelete();
      held.proceed();

      await held.clearing;
      expectOnlyLocksLeftOnceDeleted(finishDelete);
    });

    test('is not skipped when the entry still reads as a directory: clear '
        'reports the access denial', () async {
      markPendingDelete();
      overrides.reportAsDirectory = true;

      await expectLater(clear(), throwsA(_accessDenied));
    });

    test('is not skipped when the entry still reads as a directory under the '
        'removal lock: clear cannot lock it', () async {
      final held = await clearHeldAtRemovalLock();
      markPendingDelete();
      overrides.reportAsDirectory = true;
      held.proceed();

      await expectLater(held.clearing, throwsA(isA<LlamaStateException>()));
    });
  }, testOn: 'windows');

  test('clear removes a stray .removal directory instead of reporting it in '
      'use', () async {
    await populate(1);
    Directory(path.join(root.path, '.removal')).createSync();

    await manager.clear().timeout(const Duration(seconds: 10));

    expect(
      root.listSync().map((entity) => path.basename(entity.path)),
      <String>['.locks'],
    );
  });

  for (final name in <String>['.REMOVAL', '.Removal']) {
    test('clear removes a stray $name directory instead of reporting it in '
        'use', () async {
      await populate(1);
      Directory(path.join(root.path, name)).createSync();

      await manager.clear().timeout(const Duration(seconds: 10));

      expect(
        root.listSync().map((entity) => path.basename(entity.path)),
        <String>['.locks'],
      );
    });
  }

  test('overlapping clears take turns removing stray and transient '
      'directories', () async {
    for (var round = 0; round < 30; round += 1) {
      for (var i = 0; i < 20; i += 1) {
        final directory = Directory(
          path.join(root.path, 'model$i-0123456789ab-nocache-$i'),
        )..createSync();
        File(path.join(directory.path, 'model.part')).writeAsStringSync('x');
      }
      Directory(path.join(root.path, '.removal')).createSync();

      await Future.wait(<Future<void>>[
        manager.clear(),
        manager.clear(),
        manager.clear(),
      ]);

      expect(
        root.listSync().whereType<Directory>().map(
          (directory) => path.basename(directory.path),
        ),
        everyElement('.locks'),
      );
    }
  });

  test('overlapping prunes by size remove only what the limit needs', () async {
    await populate(3);

    final results = await Future.wait(<Future<Object?>>[
      manager.prune(maxBytes: 2048),
      manager.prune(maxBytes: 2048),
    ]);

    final removed = [
      for (final result in results) ...(result as List<Object?>),
    ];
    expect(removed, hasLength(1));
    expect(await manager.list(), hasLength(2));
  });
}

final Matcher _accessDenied = isA<FileSystemException>().having(
  (error) => error.osError?.errorCode,
  'errorCode',
  5,
);

/// Reports [entryPath]'s type as the file system does, but can run
/// [afterFirstCheck] once right after its first check, or report it as a
/// directory.
final class _EntryTypeOverrides extends IOOverrides {
  _EntryTypeOverrides(this.entryPath);

  final String entryPath;
  Future<void> Function()? afterFirstCheck;
  bool reportAsDirectory = false;

  bool _isEntry(String candidate) => path.equals(
    path.normalize(path.absolute(candidate)),
    path.normalize(path.absolute(entryPath)),
  );

  @override
  Future<FileSystemEntityType> fseGetType(
    String candidate,
    bool followLinks,
  ) async {
    final type = await super.fseGetType(candidate, followLinks);
    if (!_isEntry(candidate)) {
      return type;
    }
    final hook = afterFirstCheck;
    afterFirstCheck = null;
    await hook?.call();
    return reportAsDirectory ? FileSystemEntityType.directory : type;
  }

  @override
  FileSystemEntityType fseGetTypeSync(String candidate, bool followLinks) {
    final type = super.fseGetTypeSync(candidate, followLinks);
    return reportAsDirectory && _isEntry(candidate)
        ? FileSystemEntityType.directory
        : type;
  }
}
