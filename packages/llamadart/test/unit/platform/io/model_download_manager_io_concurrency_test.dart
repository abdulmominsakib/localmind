@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/download/model_download_manager_base.dart';
import 'package:llamadart/src/core/models/model_load_options.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:llamadart/src/platform/io/model_cache_entry_lock.dart';
import 'package:llamadart/src/platform/io/model_download_manager_io.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../support/dart_script_snapshot.dart';

const String _fileName = 'tiny.gguf';

void main() {
  late String childSnapshot;
  late Directory root;
  late _HoldingServer server;

  setUpAll(() async {
    childSnapshot = await compileDartScript(
      'test/support/model_cache_download_child.dart',
    );
  });

  setUp(() async {
    final created = await Directory.systemTemp.createTemp(
      'llamadart_cache_lock_',
    );
    root = Directory(await created.resolveSymbolicLinks());
    addTearDown(() => root.delete(recursive: true));
    server = await _HoldingServer.start();
    addTearDown(server.close);
  });

  ModelSource source() => ModelSource.url(server.uri, fileName: _fileName);
  Directory entryDirectory() =>
      Directory(path.join(root.path, source().cacheDirectoryName));
  String lockPath() =>
      path.join(root.path, '.locks', '${source().cacheDirectoryName}.lock');

  Future<_Child> spawnChild() => _Child.spawn(childSnapshot, <String>[
    root.path,
    server.uri.toString(),
    _fileName,
  ]);

  List<String> leftovers() => entryDirectory().existsSync()
      ? entryDirectory()
            .listSync()
            .map((entity) => path.basename(entity.path))
            .where(
              (name) =>
                  name.endsWith('.part') ||
                  name.endsWith('.part.json') ||
                  name.endsWith('.tmp'),
            )
            .toList()
      : const <String>[];

  test('two processes sharing a cache root download once and both return '
      'the complete file', () async {
    final first = await spawnChild();
    final second = await spawnChild();
    await Future.wait(<Future<void>>[first.started, second.started]);
    await server.firstResponseHeld;
    // A second request can only arrive if the other process did not wait.
    await Future.any(<Future<void>>[
      server.requestArrived(2),
      Future<void>.delayed(const Duration(milliseconds: 1500)),
    ]);
    server.release();

    final results = await Future.wait(<Future<Map<String, Object?>>>[
      first.done,
      second.done,
    ]);

    for (final result in results) {
      expect(result['bytes'], server.payload.length);
      expect(result['fileBytes'], server.payload.length);
      expect(result['sha256'], server.sha256Digest);
    }
    expect(server.requestCount, 1);
    expect(server.maxActiveRequests, 1);
    expect(leftovers(), isEmpty);
  });

  test('two isolates sharing a cache root download once', () async {
    final rootPath = root.path;
    final url = server.uri.toString();
    final downloads = <Future<(int?, String)>>[
      _downloadInIsolate(rootPath, url),
      _downloadInIsolate(rootPath, url),
    ];
    await server.firstResponseHeld;
    await Future.any(<Future<void>>[
      server.requestArrived(2),
      Future<void>.delayed(const Duration(milliseconds: 1500)),
    ]);
    server.release();

    for (final (bytes, digest) in await Future.wait(
      downloads,
    ).timeout(const Duration(seconds: 30))) {
      expect(bytes, server.payload.length);
      expect(digest, server.sha256Digest);
    }
    expect(server.requestCount, 1);
    expect(server.maxActiveRequests, 1);
  });

  test('without file locks, overlapping downloads each return their own '
      'complete file', () async {
    // Different lengths make any shared or swapped file visible; without a
    // validator neither download can resume the other's bytes.
    final longer = <int>[...server.payload, ...List<int>.filled(4096, 9)];
    server
      ..etag = null
      ..payloadOverrides[2] = longer
      ..holdAtOverrides[1] = 0
      ..holdAtOverrides[2] = longer.length - 1;
    final rootPath = root.path;
    final url = server.uri.toString();
    final downloads = <Future<(int?, String)>>[
      _downloadInIsolate(rootPath, url, lockable: false),
      _downloadInIsolate(rootPath, url, lockable: false),
    ];
    await Future.wait(<Future<void>>[server.held(1), server.held(2)]);
    await _waitForPartFile(entryDirectory(), longer.length - 1);
    server.releaseRequest(1);
    // Release the other download only once the first has returned and read
    // its file: Windows cannot replace a file another handle has open.
    await Future.any(downloads).timeout(const Duration(seconds: 30));
    server.release();

    final lengths = <String, int>{
      server.sha256Digest: server.payload.length,
      sha256.convert(longer).toString(): longer.length,
    };
    final results = await Future.wait(
      downloads,
    ).timeout(const Duration(seconds: 30));
    for (final (bytes, digest) in results) {
      expect(lengths, containsPair(digest, bytes));
    }
    expect(results.map((result) => result.$2).toSet(), hasLength(2));
    expect(leftovers(), isEmpty);
  });

  test('a waiting process takes over and resumes after the downloading '
      'process is killed', () async {
    final crashed = await spawnChild();
    await server.firstResponseHeld;
    await _waitForPartFile(entryDirectory(), server.holdAfter);

    final waiter = await spawnChild();
    await waiter.started;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(server.requestCount, 1, reason: 'the waiter must not download');

    crashed.kill();
    final result = await waiter.done;

    expect(result['bytes'], server.payload.length);
    expect(result['sha256'], server.sha256Digest);
    expect(server.requestCount, 2);
    expect(server.ranges.last, 'bytes=${server.holdAfter}-');
    expect(leftovers(), isEmpty);
  });

  group('in one process', () {
    late DefaultModelDownloadManager manager;

    setUp(() {
      manager = DefaultModelDownloadManager(defaultCacheDirectory: root.path);
      server.holdFirst = false;
    });

    test('a waiter re-validates the entry once the holder releases the lock '
        'and never returns a truncated file', () async {
      final cached = await manager.ensureModel(source());
      expect(server.requestCount, 1);

      final holder = await acquireModelCacheEntryLock(
        lockPath(),
        throwIfCancelled: () {},
      );
      expect(holder, isNotNull);
      final waiting = manager.ensureModel(source());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // The holder leaves a file whose size no longer matches its metadata.
      File(cached.filePath).writeAsBytesSync(server.payload.sublist(0, 7));
      await holder!.release();

      final entry = await waiting;

      expect(server.requestCount, 2);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
    });

    test('a waiter honours cancellation while another holder has the '
        'lock', () async {
      Directory(path.dirname(lockPath())).createSync(recursive: true);
      final holder = await acquireModelCacheEntryLock(
        lockPath(),
        throwIfCancelled: () {},
      );
      expect(holder, isNotNull);
      addTearDown(() => holder?.release());
      final token = ModelDownloadCancelToken();
      final waiting = manager.ensureModel(
        source(),
        options: ModelLoadOptions(cancelToken: token),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      token.cancel();

      await expectLater(waiting, throwsA(isA<LlamaStateException>()));
      expect(server.requestCount, 0);
    });

    test('resumes from the largest orphaned attempt and removes the '
        'rest', () async {
      final directory = entryDirectory()..createSync(recursive: true);
      final validator = jsonEncode(<String, Object?>{'etag': server.etag});
      void orphan(String id, List<int> bytes) {
        File(
          path.join(directory.path, '$_fileName.$id.part'),
        ).writeAsBytesSync(bytes);
        File(
          path.join(directory.path, '$_fileName.$id.part.json'),
        ).writeAsStringSync(validator);
      }

      orphan('00000000000000a1', <int>[1, 2]);
      orphan('00000000000000a2', server.payload.sublist(0, 9));
      File(path.join(directory.path, '$_fileName.part')).writeAsStringSync('x');
      File(
        path.join(directory.path, 'metadata.json.00000000000000a3.tmp'),
      ).writeAsStringSync('{');
      File(
        path.join(directory.path, '$_fileName.00000000000000a4.part.json'),
      ).writeAsStringSync(validator);

      final entry = await manager.ensureModel(source());

      expect(server.ranges, <String?>['bytes=9-']);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
      expect(leftovers(), isEmpty);
    });

    test('drops a resume validator left without its part file', () async {
      final directory = entryDirectory()..createSync(recursive: true);
      File(
        path.join(directory.path, '$_fileName.part.json'),
      ).writeAsStringSync(jsonEncode(<String, Object?>{'etag': server.etag}));

      final entry = await manager.ensureModel(source());

      expect(server.ranges, <String?>[null]);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
      expect(leftovers(), isEmpty);
    });

    test('a failed attempt leaves its bytes as <file>.part for the next '
        'resume', () async {
      server.failAfterHold = true;
      server.holdFirst = true;
      final failing = manager.ensureModel(
        source(),
        options: ModelLoadOptions(maxRetries: 0),
      );
      await server.firstResponseHeld;
      server.release();
      await expectLater(failing, throwsA(isA<LlamaModelException>()));

      expect(
        leftovers(),
        unorderedEquals(<String>['$_fileName.part', '$_fileName.part.json']),
      );
      final part = File(path.join(entryDirectory().path, '$_fileName.part'));
      expect(part.lengthSync(), server.holdAfter);

      final entry = await manager.ensureModel(source());

      expect(server.ranges.last, 'bytes=${server.holdAfter}-');
      expect(await File(entry.filePath).readAsBytes(), server.payload);
      expect(leftovers(), isEmpty);
    });

    test('a locked caller that resumes a part file another writer is still '
        'appending to discards the result and downloads again', () async {
      // The other writer cannot lock: an older llamadart, or a process whose
      // lock failed. The locked caller adopts its in-flight part file.
      server
        ..holdFirst = true
        ..holdHeaders.add(2);
      final rootPath = root.path;
      final url = server.uri.toString();
      final unlocked = _downloadInIsolate(rootPath, url, lockable: false);
      await server.firstResponseHeld;
      await _waitForPartFile(entryDirectory(), server.holdAfter);
      final locked = manager.ensureModel(source());
      await server.headersHeld(2);
      // Windows refuses to rename a file another handle has open, so there
      // the locked caller cannot adopt the in-flight file and starts afresh.
      expect(
        server.ranges[1],
        Platform.isWindows ? isNull : 'bytes=${server.holdAfter}-',
      );
      server.releaseRequest(1);
      final (unlockedBytes, unlockedDigest) = await unlocked.timeout(
        const Duration(seconds: 30),
      );
      server.releaseHeaders(2);
      final entry = await locked.timeout(const Duration(seconds: 30));

      expect(unlockedBytes, server.payload.length);
      expect(unlockedDigest, server.sha256Digest);
      expect(entry.bytes, server.payload.length);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
      final cached = await manager.get(source().cacheKey);
      expect(cached?.bytes, server.payload.length);
    });

    test('downloads a gzip-encoded response whose Content-Length counts the '
        'encoded bytes', () async {
      server.gzipBody = true;

      final entry = await manager.ensureModel(
        source(),
        options: ModelLoadOptions(maxRetries: 0),
      );

      expect(await File(entry.filePath).readAsBytes(), server.payload);
      expect(entry.bytes, server.payload.length);
    });

    test(
      'a body shorter than the reported total is kept and resumed',
      () async {
        server.shortBodies.add(1);

        final entry = await manager.ensureModel(source());

        expect(server.ranges, <String?>[null, 'bytes=${server.holdAfter}-']);
        expect(await File(entry.filePath).readAsBytes(), server.payload);
      },
    );

    test('a resumed attempt writes at the offset it requested while a writer '
        'without the lock extends the same file', () async {
      // An older llamadart writes <file>.part directly, without the lock, and
      // keeps its handle open. The locked caller adopts the file at [adopted]
      // bytes; the old writer reaches [extended] during the round trip.
      const adopted = 128 * 1024;
      const extended = 192 * 1024;
      server
        ..holdHeaders.add(1)
        ..holdAtOverrides[1] = 16 * 1024
        ..failAfterHold = true
        ..releaseRequest(1);
      final directory = entryDirectory()..createSync(recursive: true);
      final part = File(path.join(directory.path, '$_fileName.part'));
      File(
        '${part.path}.json',
      ).writeAsStringSync(jsonEncode(<String, Object?>{'etag': server.etag}));
      final oldWriter = await part.open(mode: FileMode.write);
      addTearDown(oldWriter.close);
      await oldWriter.writeFrom(server.payload, 0, adopted);
      await oldWriter.flush();

      final locked = manager.ensureModel(source());
      await server.headersHeld(1);
      expect(server.ranges.first, 'bytes=$adopted-');
      await oldWriter.writeFrom(server.payload, adopted, extended);
      await oldWriter.flush();
      server.releaseHeaders(1);
      final entry = await locked.timeout(const Duration(seconds: 30));

      expect(entry.bytes, server.payload.length);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
    }, testOn: '!windows');

    test('a cacheOnly call waits for a download this isolate already '
        'started', () async {
      server.holdFirst = true;
      final downloading = manager.ensureModel(source());
      await server.firstResponseHeld;
      final probe = manager.ensureModel(
        source(),
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      server.release();
      await downloading;

      final entry = await probe;
      expect(await File(entry.filePath).readAsBytes(), server.payload);
      expect(server.requestCount, 1);
    });

    test('a cacheOnly call that finds the file only after waiting reads it '
        'under the entry lock', () async {
      Directory(path.dirname(lockPath())).createSync(recursive: true);
      final holder = await acquireModelCacheEntryLock(
        lockPath(),
        throwIfCancelled: () {},
      );
      expect(holder, isNotNull);
      addTearDown(() => holder?.release());
      final token = ModelDownloadCancelToken();
      final blocked = manager.ensureModel(
        source(),
        options: ModelLoadOptions(cancelToken: token),
      );
      final probe = manager.ensureModel(
        source(),
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // The holder, another process, is mid-refresh: its new file is in place
      // and its metadata still describes the old one.
      final directory = entryDirectory()..createSync(recursive: true);
      final file = File(path.join(directory.path, _fileName))
        ..writeAsBytesSync(server.payload);
      void writeMetadata(int bytes) {
        final now = DateTime.now().toUtc();
        File(path.join(directory.path, 'metadata.json')).writeAsStringSync(
          jsonEncode(<String, Object?>{
            'schema_version': 1,
            ...ModelCacheEntry(
              sourceCanonicalKey: source().metadataSourceKey,
              cacheKey: source().cacheKey,
              fileName: _fileName,
              filePath: file.path,
              bytes: bytes,
              createdAt: now,
              updatedAt: now,
            ).toJson(),
          }),
        );
      }

      writeMetadata(7);
      token.cancel();
      await expectLater(blocked, throwsA(isA<LlamaStateException>()));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      writeMetadata(server.payload.length);
      await holder!.release();

      final entry = await probe;
      expect(await File(entry.filePath).readAsBytes(), server.payload);
      expect(server.requestCount, 0);
    });

    test('a resume whose file outgrows the reported total is discarded and '
        'downloaded again', () async {
      final directory = entryDirectory()..createSync(recursive: true);
      File(
        path.join(directory.path, '$_fileName.part'),
      ).writeAsBytesSync(server.payload.sublist(0, 1000));
      File(
        path.join(directory.path, '$_fileName.part.json'),
      ).writeAsStringSync(jsonEncode(<String, Object?>{'etag': server.etag}));
      server.answerResumeWithSmallerTotal = true;

      final entry = await manager.ensureModel(source());

      expect(server.ranges, <String?>['bytes=1000-', null]);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
    });

    test('a discarded oversized resume leaves no part file or validator and '
        'releases the lock', () async {
      final directory = entryDirectory()..createSync(recursive: true);
      File(
        path.join(directory.path, '$_fileName.part'),
      ).writeAsBytesSync(server.payload.sublist(0, 1000));
      File(
        path.join(directory.path, '$_fileName.part.json'),
      ).writeAsStringSync(jsonEncode(<String, Object?>{'etag': server.etag}));
      server.answerResumeWithSmallerTotal = true;

      await expectLater(
        manager.ensureModel(source(), options: ModelLoadOptions(maxRetries: 0)),
        throwsA(isA<LlamaModelException>()),
      );
      expect(leftovers(), isEmpty);

      server.answerResumeWithSmallerTotal = false;
      final entry = await DefaultModelDownloadManager(
        defaultCacheDirectory: root.path,
      ).ensureModel(source()).timeout(const Duration(seconds: 10));
      expect(server.ranges, <String?>['bytes=1000-', null]);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
    });

    test('never touches a metadata temp file another writer owns', () async {
      final directory = entryDirectory()..createSync(recursive: true);
      final foreign = File(path.join(directory.path, 'metadata.json.tmp'))
        ..writeAsStringSync('foreign');

      await manager.ensureModel(source());

      expect(foreign.readAsStringSync(), 'foreign');
    });

    test('a cacheOnly miss creates no lock directory', () async {
      final missingRoot = path.join(root.path, 'missing');

      await expectLater(
        manager.ensureModel(
          source(),
          options: ModelLoadOptions(
            cachePolicy: ModelCachePolicy.cacheOnly,
            cacheDirectory: missingRoot,
          ),
        ),
        throwsA(isA<LlamaStateException>()),
      );
      expect(Directory(missingRoot).existsSync(), isFalse);
    });

    test('without file locks, a failed attempt without a validator drops '
        'a stale one left at <file>.part.json', () async {
      final previousLocker = modelCacheEntryLocker;
      modelCacheEntryLocker = (lockPath, {required throwIfCancelled}) async =>
          null;
      addTearDown(() => modelCacheEntryLocker = previousLocker);
      final directory = entryDirectory()..createSync(recursive: true);
      final staleValidator = File(
        path.join(directory.path, '$_fileName.part.json'),
      )..writeAsStringSync(jsonEncode(<String, Object?>{'etag': '"old"'}));
      server
        ..etag = null
        ..holdFirst = true
        ..failAfterHold = true
        ..release();

      await expectLater(
        manager.ensureModel(source(), options: ModelLoadOptions(maxRetries: 0)),
        throwsA(isA<LlamaModelException>()),
      );

      expect(
        File(path.join(directory.path, '$_fileName.part')).existsSync(),
        isTrue,
      );
      expect(staleValidator.existsSync(), isFalse);
    });

    test('without file locks it warns once, downloads into its own attempt '
        'file and leaves other attempts alone', () async {
      final previousLocker = modelCacheEntryLocker;
      modelCacheEntryLocker = (lockPath, {required throwIfCancelled}) async =>
          null;
      final records = <LlamaLogRecord>[];
      final logger = LlamaLogger.instance;
      final previousLevel = logger.level;
      logger
        ..setLevel(LlamaLogLevel.warn)
        ..setHandler(records.add);
      addTearDown(() {
        modelCacheEntryLocker = previousLocker;
        logger
          ..setLevel(previousLevel)
          ..setHandler(null);
      });
      resetModelCacheLockWarningForTesting();
      final directory = entryDirectory()..createSync(recursive: true);
      final foreign = File(
        path.join(directory.path, '$_fileName.00000000000000b1.part'),
      )..writeAsStringSync('in-flight');

      final entry = await manager.ensureModel(source());
      await manager.ensureModel(
        source(),
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
      );

      expect(await File(entry.filePath).readAsBytes(), server.payload);
      expect(foreign.readAsStringSync(), 'in-flight');
      expect(records, hasLength(1));
      expect(records.single.level, LlamaLogLevel.warn);
      expect(records.single.message, contains('Cannot lock'));
    });
  });

  group('cache management', () {
    late DefaultModelDownloadManager manager;

    setUp(() {
      manager = DefaultModelDownloadManager(defaultCacheDirectory: root.path);
      server.holdFirst = false;
    });

    ModelSource named(String fileName) =>
        ModelSource.url(server.uri, fileName: fileName);
    String directoryOf(ModelSource source) =>
        path.join(root.path, source.cacheDirectoryName);
    String lockPathOf(ModelSource source) =>
        path.join(root.path, '.locks', '${source.cacheDirectoryName}.lock');

    /// Holds [source]'s entry lock as another process would.
    Future<ModelCacheEntryLock> holdLock(ModelSource source) async {
      Directory(path.dirname(lockPathOf(source))).createSync(recursive: true);
      final lock = await acquireModelCacheEntryLock(
        lockPathOf(source),
        throwIfCancelled: () {},
      );
      addTearDown(() => lock?.release());
      return lock!;
    }

    Matcher inUse(List<String> directories) =>
        isA<ModelCacheEntryInUseException>()
            .having(
              (error) => error.entryDirectories,
              'entryDirectories',
              directories,
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains(root.path)),
            );

    /// Holds the cache root's removal lock as another process's remover
    /// would.
    Future<ModelCacheEntryLock> holdRemovalLock() async {
      final locks = Directory(path.join(root.path, '.locks'))
        ..createSync(recursive: true);
      final lock = await acquireModelCacheEntryLock(
        path.join(locks.path, '.removal.lock'),
        throwIfCancelled: () {},
      );
      addTearDown(() => lock?.release());
      return lock!;
    }

    test('remove leaves an entry whose lock another caller holds and reports '
        'it in use', () async {
      final entry = await manager.ensureModel(source());
      final lock = await holdLock(source());

      await expectLater(
        manager.remove(source().cacheKey),
        throwsA(inUse(<String>[entryDirectory().path])),
      );
      expect(await File(entry.filePath).readAsBytes(), server.payload);
      expect(File(lockPath()).existsSync(), isTrue);

      await lock.release();
      await manager.remove(source().cacheKey);
      expect(entryDirectory().existsSync(), isFalse);
    });

    test('prune skips entries in use and removes the rest', () async {
      final busy = named('busy.gguf');
      final idle = named('idle.gguf');
      final stale = named('stale.gguf');
      await manager.ensureModel(busy);
      await manager.ensureModel(idle);
      final staleEntry = await manager.ensureModel(stale);
      File(staleEntry.filePath).deleteSync();
      await holdLock(busy);
      await holdLock(stale);

      final pruned = await manager.prune(maxBytes: 0);

      expect(pruned.map((entry) => entry.cacheKey), <String>[idle.cacheKey]);
      expect(Directory(directoryOf(busy)).existsSync(), isTrue);
      expect(Directory(directoryOf(stale)).existsSync(), isTrue);
      expect(Directory(directoryOf(idle)).existsSync(), isFalse);
      expect((await manager.list()).single.cacheKey, busy.cacheKey);
    });

    test('prune by size still counts an oldest entry in use', () async {
      final busy = named('busy.gguf');
      final first = named('first.gguf');
      final second = named('second.gguf');
      for (final source in [busy, first, second]) {
        await manager.ensureModel(source);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await holdLock(busy);

      final pruned = await manager.prune(maxBytes: 2 * server.payload.length);

      expect(pruned.map((entry) => entry.cacheKey), <String>[first.cacheKey]);
      expect(Directory(directoryOf(busy)).existsSync(), isTrue);
      expect(Directory(directoryOf(second)).existsSync(), isTrue);
    });

    test('prune keeps an entry used after it listed it', () async {
      final entry = await manager.ensureModel(source());
      final previousLocker = modelCacheEntryLocker;
      addTearDown(() => modelCacheEntryLocker = previousLocker);
      // A cache hit in another isolate completes between prune listing the
      // entry and taking its lock.
      modelCacheEntryLocker = (lockPath, {required throwIfCancelled}) async {
        modelCacheEntryLocker = previousLocker;
        await _downloadInIsolate(root.path, server.uri.toString());
        return previousLocker(lockPath, throwIfCancelled: throwIfCancelled);
      };
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final pruned = await manager.prune(maxAge: Duration.zero);

      expect(pruned, isEmpty);
      expect(server.requestCount, 1);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
    });

    test('prune keeps a stale entry downloaded again after it listed '
        'it', () async {
      final entry = await manager.ensureModel(source());
      File(entry.filePath).deleteSync();
      final previousLocker = modelCacheEntryLocker;
      addTearDown(() => modelCacheEntryLocker = previousLocker);
      modelCacheEntryLocker = (lockPath, {required throwIfCancelled}) async {
        modelCacheEntryLocker = previousLocker;
        await _downloadInIsolate(root.path, server.uri.toString());
        return previousLocker(lockPath, throwIfCancelled: throwIfCancelled);
      };

      final pruned = await manager.prune();

      expect(pruned, isEmpty);
      expect(server.requestCount, 2);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
    });

    test('clear removes every entry not in use, reports the rest and keeps '
        'their lock files', () async {
      final busy = named('busy.gguf');
      final idle = named('idle.gguf');
      await manager.ensureModel(busy);
      await manager.ensureModel(idle);
      final lock = await holdLock(busy);

      await expectLater(
        manager.clear(),
        throwsA(inUse(<String>[directoryOf(busy)])),
      );
      expect((await manager.list()).single.cacheKey, busy.cacheKey);
      expect(File(lockPathOf(busy)).existsSync(), isTrue);

      await lock.release();
      File(path.join(root.path, 'stray.txt')).writeAsStringSync('stray');
      await manager.clear();
      expect(await manager.list(), isEmpty);
      expect(
        root.listSync().map((entity) => path.basename(entity.path)),
        <String>['.locks'],
      );
    });

    for (final lockable in <bool>[true, false]) {
      test('overlapping clears report no entry the other is removing'
          '${lockable ? '' : ', without file locks'}', () async {
        for (var i = 0; i < 4; i += 1) {
          await manager.ensureModel(named('model$i.gguf'));
        }
        if (!lockable) {
          final previousLocker = modelCacheEntryLocker;
          addTearDown(() => modelCacheEntryLocker = previousLocker);
          modelCacheEntryLocker =
              (lockPath, {required throwIfCancelled}) async => null;
        }

        await Future.wait(<Future<void>>[
          manager.clear(),
          DefaultModelDownloadManager(defaultCacheDirectory: root.path).clear(),
          manager.remove(named('model2.gguf').cacheKey),
        ]);

        expect(await manager.list(), isEmpty);
      });
    }

    test(
      'overlapping clears of stray files neither throw nor leave any',
      () async {
        for (var i = 0; i < 6; i += 1) {
          File(path.join(root.path, 'stray$i.txt')).writeAsStringSync('stray');
        }

        await Future.wait(<Future<void>>[
          manager.clear(),
          DefaultModelDownloadManager(defaultCacheDirectory: root.path).clear(),
        ]);

        expect(
          root.listSync().map((entity) => path.basename(entity.path)),
          <String>['.locks'],
        );
      },
    );

    test('remove waits for another process removing the entry instead of '
        'reporting it in use', () async {
      await manager.ensureModel(source());
      final removalLock = await holdRemovalLock();
      // Downloads and cache hits never wait for removers.
      await manager.ensureModel(source()).timeout(const Duration(seconds: 10));
      final entryLock = await holdLock(source());

      var removed = false;
      final removing = manager
          .remove(source().cacheKey)
          .then((_) => removed = true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(removed, isFalse);
      entryDirectory().deleteSync(recursive: true);
      await entryLock.release();
      await removalLock.release();

      await removing.timeout(const Duration(seconds: 10));
      expect(await manager.list(), isEmpty);
    });

    test(
      'clear waits for another remover before deleting a stray file',
      () async {
        final stray = File(path.join(root.path, 'stray.txt'))
          ..createSync(recursive: true);
        final removalLock = await holdRemovalLock();

        var cleared = false;
        final clearing = manager.clear().then((_) => cleared = true);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(cleared, isFalse);
        expect(stray.existsSync(), isTrue);
        await removalLock.release();

        await clearing.timeout(const Duration(seconds: 10));
        expect(stray.existsSync(), isFalse);
      },
    );

    test('a same-isolate download of an entry waits for its removal and then '
        'runs', () async {
      await manager.ensureModel(source());
      final previousLocker = modelCacheEntryLocker;
      addTearDown(() => modelCacheEntryLocker = previousLocker);
      final removerLocking = Completer<void>();
      final letRemoverLock = Completer<void>();
      modelCacheEntryLocker = (requested, {required throwIfCancelled}) async {
        if (requested == lockPath() && !removerLocking.isCompleted) {
          removerLocking.complete();
          await letRemoverLock.future;
          // As on a file system without locks: only the isolate lock
          // excludes the download.
          return null;
        }
        return previousLocker(requested, throwIfCancelled: throwIfCancelled);
      };

      final removing = manager.remove(source().cacheKey);
      await removerLocking.future;
      var downloaded = false;
      final downloading = manager
          .ensureModel(source())
          .whenComplete(() => downloaded = true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(downloaded, isFalse);
      letRemoverLock.complete();

      await removing;
      final entry = await downloading.timeout(const Duration(seconds: 10));
      expect(server.requestCount, 2);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
    });

    test('prune keeps an entry whose metadata names another file after it '
        'listed it', () async {
      final entry = await manager.ensureModel(source());
      final previousLocker = modelCacheEntryLocker;
      addTearDown(() => modelCacheEntryLocker = previousLocker);
      final metadataFile = File(
        path.join(entryDirectory().path, 'metadata.json'),
      );
      final otherFile = File(path.join(entryDirectory().path, 'other.gguf'))
        ..writeAsBytesSync(server.payload);
      modelCacheEntryLocker = (lockPath, {required throwIfCancelled}) async {
        modelCacheEntryLocker = previousLocker;
        final metadata =
            jsonDecode(metadataFile.readAsStringSync()) as Map<String, Object?>;
        metadata['file_path'] = otherFile.path;
        metadataFile.writeAsStringSync(jsonEncode(metadata));
        return previousLocker(lockPath, throwIfCancelled: throwIfCancelled);
      };
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(await manager.prune(maxAge: Duration.zero), isEmpty);
      expect(File(entry.filePath).existsSync(), isTrue);
    });

    test('prune never removes the lock directory, even when it holds entry '
        'metadata', () async {
      final entry = await manager.ensureModel(source());
      final metadata =
          jsonDecode(
                File(
                  path.join(entryDirectory().path, 'metadata.json'),
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final locks = path.join(root.path, '.locks');
      metadata['file_path'] = path.join(locks, entry.fileName);
      File(
        path.join(locks, 'metadata.json'),
      ).writeAsStringSync(jsonEncode(metadata));

      await manager.prune();

      expect(File(lockPath()).existsSync(), isTrue);
    });

    test('remove reports a permission failure as that error, not in use, and '
        'keeps the entry', () async {
      await manager.ensureModel(source());
      expect(
        Process.runSync('chmod', ['a-w', entryDirectory().path]).exitCode,
        0,
      );
      addTearDown(
        () => Process.runSync('chmod', ['u+w', entryDirectory().path]),
      );

      await expectLater(
        manager.remove(source().cacheKey),
        throwsA(isA<FileSystemException>()),
      );
      expect((await manager.list()).single.cacheKey, source().cacheKey);
    }, testOn: '!windows');

    test(
      'clear removes noCache entries and creates only the removal lock',
      () async {
        await manager.ensureModel(
          source(),
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.noCache),
        );

        await manager.clear();

        expect(await manager.list(), isEmpty);
        final locks = Directory(path.join(root.path, '.locks'));
        expect(
          locks.existsSync()
              ? locks.listSync().map((lock) => path.basename(lock.path))
              : const <String>[],
          everyElement('.removal.lock'),
        );
      },
    );

    test('clear leaves another process to finish its download', () async {
      server.holdFirst = true;
      final child = await spawnChild();
      await server.firstResponseHeld;
      await _waitForPartFile(entryDirectory(), server.holdAfter);

      await expectLater(
        manager.clear(),
        throwsA(inUse(<String>[entryDirectory().path])),
      );
      server.release();
      final result = await child.done;

      expect(result['sha256'], server.sha256Digest);
      expect(server.requestCount, 1);
      expect((await manager.list()).single.cacheKey, source().cacheKey);
    });

    test('prune and remove called from a download in this isolate skip its '
        'entry without waiting for it', () async {
      await manager.ensureModel(source());
      server.holdAtOverrides[2] = server.holdAfter;
      Future<List<ModelCacheEntry>>? pruned;
      Future<Object?>? removeError;

      final refreshing = manager.ensureModel(
        source(),
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
        onProgress: (_) {
          pruned ??= manager.prune(maxBytes: 0);
          removeError ??= manager
              .remove(source().cacheKey)
              .then((_) => null, onError: (Object error) => error);
        },
      );
      await server.held(2);
      while (pruned == null || removeError == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // Both finish while the download they were called from is still held.
      expect(await pruned!.timeout(const Duration(seconds: 10)), isEmpty);
      expect(
        await removeError!.timeout(const Duration(seconds: 10)),
        inUse(<String>[entryDirectory().path]),
      );
      server.release();
      final refreshed = await refreshing;
      expect(server.requestCount, 2);
      expect(await File(refreshed.filePath).readAsBytes(), server.payload);
    });

    test('without file locks, remove still skips an entry this isolate is '
        'downloading', () async {
      final previousLocker = modelCacheEntryLocker;
      modelCacheEntryLocker = (lockPath, {required throwIfCancelled}) async =>
          null;
      addTearDown(() => modelCacheEntryLocker = previousLocker);
      await manager.ensureModel(source());
      server.holdAtOverrides[2] = server.holdAfter;
      final refreshing = manager.ensureModel(
        source(),
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
      );
      await server.held(2);

      await expectLater(
        manager.remove(source().cacheKey),
        throwsA(inUse(<String>[entryDirectory().path])),
      );
      server.release();
      final entry = await refreshing;

      expect(server.requestCount, 2);
      expect(await File(entry.filePath).readAsBytes(), server.payload);
    });

    test('an entry whose model file is open elsewhere is in use only on '
        'Windows, where the open handle blocks deleting it', () async {
      final entry = await manager.ensureModel(source());
      var open = true;
      final handle = await File(entry.filePath).open();
      Future<void> close() async {
        if (open) {
          open = false;
          await handle.close();
        }
      }

      addTearDown(close);

      if (!Platform.isWindows) {
        await manager.remove(source().cacheKey);
        expect(entryDirectory().existsSync(), isFalse);
        return;
      }
      for (final operation in <Future<void> Function()>[
        () => manager.remove(source().cacheKey),
        manager.clear,
      ]) {
        await expectLater(
          operation(),
          throwsA(inUse(<String>[entryDirectory().path])),
        );
        expect((await manager.list()).single.cacheKey, source().cacheKey);
      }
      expect(await manager.prune(maxBytes: 0), isEmpty);
      await close();
      await manager.remove(source().cacheKey);
      expect(entryDirectory().existsSync(), isFalse);
    });

    test('an entry whose metadata file is open elsewhere is in use on '
        'Windows', () async {
      await manager.ensureModel(source());
      final handle = await File(
        path.join(entryDirectory().path, 'metadata.json'),
      ).open();
      var open = true;
      Future<void> close() async {
        if (open) {
          open = false;
          await handle.close();
        }
      }

      addTearDown(close);

      await expectLater(
        manager.remove(source().cacheKey),
        throwsA(inUse(<String>[entryDirectory().path])),
      );
      expect(
        File(path.join(entryDirectory().path, 'metadata.json')).existsSync(),
        isTrue,
      );
      await close();
      await manager.remove(source().cacheKey);
      expect(entryDirectory().existsSync(), isFalse);
    }, skip: Platform.isWindows ? null : 'a sharing violation is Windows-only');

    test('a cache hit on a read-only cache root returns the entry', () async {
      final entry = await manager.ensureModel(source());
      final unrecorded = named('unrecorded.gguf');
      final unrecordedEntry = await manager.ensureModel(unrecorded);
      File(path.join(directoryOf(unrecorded), 'metadata.json')).deleteSync();
      Directory(path.join(root.path, '.locks')).deleteSync(recursive: true);
      expect(Process.runSync('chmod', ['-R', 'a-w', root.path]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['-R', 'u+w', root.path]));
      final metadata = File(
        path.join(entryDirectory().path, 'metadata.json'),
      ).readAsStringSync();

      for (final policy in <ModelCachePolicy>[
        ModelCachePolicy.cacheOnly,
        ModelCachePolicy.preferCached,
      ]) {
        final hit = await manager.ensureModel(
          source(),
          options: ModelLoadOptions(cachePolicy: policy),
        );
        expect(hit.filePath, entry.filePath);
        expect(hit.bytes, server.payload.length);
        final recovered = await manager.ensureModel(
          unrecorded,
          options: ModelLoadOptions(cachePolicy: policy),
        );
        expect(recovered.filePath, unrecordedEntry.filePath);
      }
      expect(server.requestCount, 2);
      expect(
        File(
          path.join(entryDirectory().path, 'metadata.json'),
        ).readAsStringSync(),
        metadata,
      );
    }, testOn: '!windows');

    test('a cacheOnly miss stays a miss when the file appears before the '
        'entry is read', () async {
      await manager.ensureModel(source());
      final modelPath = path.join(entryDirectory().path, _fileName);

      await IOOverrides.runWithIOOverrides(
        () => expectLater(
          manager.ensureModel(
            source(),
            options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
          ),
          throwsA(isA<LlamaStateException>()),
        ),
        _FirstExistsCheckMisses(modelPath),
      );
    });
  });
}

/// Answers the first `exists()` check of [_path] with false, as if another
/// process wrote the file just after it.
final class _FirstExistsCheckMisses extends IOOverrides {
  _FirstExistsCheckMisses(this._path);

  final String _path;
  bool _missed = false;

  @override
  File createFile(String path) {
    if (_missed || path != _path) {
      return super.createFile(path);
    }
    _missed = true;
    return _MissingFile(super.createFile(path));
  }
}

final class _MissingFile implements File {
  _MissingFile(this._file);

  final File _file;

  @override
  String get path => _file.path;

  @override
  Future<bool> exists() async => false;

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} on $path');
}

// A top-level function, so the closure sent to the isolate captures only
// [root] and [url].
Future<(int?, String)> _downloadInIsolate(
  String root,
  String url, {
  bool lockable = true,
}) => Isolate.run(() => _download(root, url, lockable));

Future<(int?, String)> _download(String root, String url, bool lockable) async {
  if (!lockable) {
    modelCacheEntryLocker = (lockPath, {required throwIfCancelled}) async =>
        null;
  }
  final manager = DefaultModelDownloadManager(defaultCacheDirectory: root);
  final entry = await manager.ensureModel(
    ModelSource.url(Uri.parse(url), fileName: _fileName),
  );
  final bytes = await File(entry.filePath).readAsBytes();
  return (entry.bytes, sha256.convert(bytes).toString());
}

Future<void> _waitForPartFile(Directory directory, int length) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    if (directory.existsSync()) {
      for (final entity in directory.listSync()) {
        if (entity is File &&
            entity.path.endsWith('.part') &&
            entity.lengthSync() == length) {
          return;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('No $length-byte part file appeared in ${directory.path}.');
}

/// A child process running `model_cache_download_child.dart`.
class _Child {
  _Child._(this._process) {
    _stdout = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final event = jsonDecode(line) as Map<String, Object?>;
          switch (event['event']) {
            case 'started':
              _started.complete();
            case 'done':
              _done.complete(event);
          }
        });
    _stderr = _process.stderr.transform(utf8.decoder).listen(_errors.write);
    _process.exitCode.then((code) {
      if (!_done.isCompleted && !_killed) {
        _done.completeError(
          StateError('child exited $code before finishing:\n$_errors'),
        );
      }
    });
  }

  static Future<_Child> spawn(String snapshot, List<String> args) async {
    final process = await Process.start(Platform.resolvedExecutable, <String>[
      snapshot,
      ...args,
    ]);
    final child = _Child._(process);
    addTearDown(child._dispose);
    return child;
  }

  final Process _process;
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  final StringBuffer _errors = StringBuffer();
  final Completer<void> _started = Completer<void>();
  final Completer<Map<String, Object?>> _done =
      Completer<Map<String, Object?>>();
  bool _killed = false;

  Future<void> get started => _started.future;

  Future<Map<String, Object?>> get done =>
      _done.future.timeout(const Duration(seconds: 30));

  void kill() {
    _killed = true;
    _process.kill(ProcessSignal.sigkill);
  }

  Future<void> _dispose() async {
    _killed = true;
    _process.kill(ProcessSignal.sigkill);
    await _process.exitCode;
    await _stdout.cancel();
    await _stderr.cancel();
  }
}

/// Serves one payload with an ETag and byte ranges. The first full response
/// pauses after [holdAfter] bytes until [release], so a test controls when
/// that download can finish.
class _HoldingServer {
  _HoldingServer._(this._server) {
    _subscription = _server.listen(_accept);
  }

  static Future<_HoldingServer> start() async =>
      _HoldingServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;
  final Set<Future<void>> _inFlight = <Future<void>>{};
  final List<int> payload = List<int>.generate(
    256 * 1024,
    (index) => (index * 31 + 7) % 251,
  );
  String? etag = '"holding-v1"';
  final List<String?> ranges = <String?>[];
  final Map<int, Completer<void>> _held = <int, Completer<void>>{};
  final Map<int, Completer<void>> _released = <int, Completer<void>>{};
  final Map<int, Completer<void>> _arrivals = <int, Completer<void>>{};
  bool _releasedAll = false;
  bool holdFirst = true;

  /// Bodies, and mid-body pause offsets, by request number.
  final Map<int, List<int>> payloadOverrides = <int, List<int>>{};
  final Map<int, int> holdAtOverrides = <int, int>{};
  bool failAfterHold = false;

  /// Sends every body gzip-encoded, with the encoded Content-Length.
  bool gzipBody = false;

  /// Answers every Range request with 100 bytes and a Content-Range total
  /// 50 bytes past the requested start, so the resumed file outgrows it.
  bool answerResumeWithSmallerTotal = false;

  /// Request numbers whose full response ends at [holdAfter] bytes.
  final Set<int> shortBodies = <int>{};

  /// Request numbers whose headers wait for [releaseHeaders].
  final Set<int> holdHeaders = <int>{};
  final Map<int, Completer<void>> _headersHeld = <int, Completer<void>>{};
  final Map<int, Completer<void>> _headersReleased = <int, Completer<void>>{};

  Future<void> headersHeld(int number) =>
      (_headersHeld[number] ??= Completer<void>()).future;

  void releaseHeaders(int number) {
    final released = _headersReleased[number] ??= Completer<void>();
    if (!released.isCompleted) {
      released.complete();
    }
  }

  int requestCount = 0;
  int activeRequests = 0;
  int maxActiveRequests = 0;

  int get holdAfter => payload.length ~/ 2;

  Uri get uri =>
      Uri.parse('http://127.0.0.1:${_server.port}/models/$_fileName');

  String get sha256Digest => sha256.convert(payload).toString();

  Future<void> get firstResponseHeld => held(1);

  /// Completes once full response [number] has paused mid-body.
  Future<void> held(int number) => (_held[number] ??= Completer<void>()).future;

  Future<void> requestArrived(int count) =>
      (_arrivals[count] ??= Completer<void>()).future;

  /// Lets every held response, and any held later, finish.
  void release() {
    _releasedAll = true;
    _released.keys.toList().forEach(releaseRequest);
    _headersReleased.keys.toList().forEach(releaseHeaders);
  }

  void releaseRequest(int number) {
    final released = _released[number] ??= Completer<void>();
    if (!released.isCompleted) {
      released.complete();
    }
  }

  Future<void> close() async {
    release();
    await _subscription.cancel();
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList());
    }
    await _server.close(force: true);
  }

  void _accept(HttpRequest request) {
    late final Future<void> tracked;
    tracked = _handle(request)
        .catchError((Object _) {
          // A killed client leaves the held response writing to a dead socket.
        })
        .whenComplete(() => _inFlight.remove(tracked));
    _inFlight.add(tracked);
  }

  Future<void> _handle(HttpRequest request) async {
    requestCount += 1;
    final number = requestCount;
    (_arrivals[number] ??= Completer<void>()).complete();
    activeRequests += 1;
    if (activeRequests > maxActiveRequests) {
      maxActiveRequests = activeRequests;
    }
    try {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      if (holdHeaders.contains(number)) {
        (_headersHeld[number] ??= Completer<void>()).complete();
        if (_releasedAll) {
          releaseHeaders(number);
        }
        await (_headersReleased[number] ??= Completer<void>()).future;
      }
      final response = request.response;
      final currentEtag = etag;
      if (currentEtag != null) {
        response.headers.set(HttpHeaders.etagHeader, currentEtag);
      }
      if (answerResumeWithSmallerTotal && range != null) {
        final from = int.parse(
          range.substring('bytes='.length).split('-').first,
        );
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $from-${from + 99}/${from + 50}',
          )
          ..headers.contentLength = 100
          ..add(List<int>.filled(100, 1));
        await response.close();
        return;
      }
      final body = payloadOverrides[number] ?? payload;
      var start = 0;
      if (range != null &&
          currentEtag != null &&
          request.headers.value(HttpHeaders.ifRangeHeader) == currentEtag) {
        start = int.parse(range.substring('bytes='.length).split('-').first);
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${body.length - 1}/${body.length}',
        );
      }
      if (gzipBody) {
        final encoded = gzip.encode(body.sublist(start));
        response.headers
          ..set(HttpHeaders.contentEncodingHeader, 'gzip')
          ..contentLength = encoded.length;
        response.add(encoded);
        await response.close();
        return;
      }
      if (shortBodies.contains(number) && start == 0) {
        // Ends cleanly at half the body: no Content-Length to fall short of,
        // only the Content-Range total.
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-${holdAfter - 1}/${body.length}',
        );
        response.add(body.sublist(0, holdAfter));
        await response.close();
        return;
      }
      response.headers.contentLength = body.length - start;
      final holdAt =
          holdAtOverrides[number] ??
          (holdFirst && number == 1 && start == 0 ? holdAfter : null);
      if (holdAt == null) {
        response.add(body.sublist(start));
        await response.close();
        return;
      }
      // [holdAt] counts bytes of this response, from [start].
      response.add(body.sublist(start, start + holdAt));
      await response.flush();
      (_held[number] ??= Completer<void>()).complete();
      if (_releasedAll) {
        releaseRequest(number);
      }
      await (_released[number] ??= Completer<void>()).future;
      if (failAfterHold) {
        // Closing short of Content-Length drops the connection mid-body.
        await response.close();
        return;
      }
      response.add(body.sublist(start + holdAt));
      await response.close();
    } finally {
      activeRequests -= 1;
    }
  }
}
