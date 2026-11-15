import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/downloads/download_engine.dart';
import 'package:localmind/core/downloads/os_download_bridge.dart';
import 'package:localmind/core/downloads/download_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deterministic in-memory dio adapter serving byte payloads with optional
/// Range/ETag semantics, recording every request for assertions.
class MockDownloadAdapter implements HttpClientAdapter {
  MockDownloadAdapter(this.handler);

  final Future<ResponseBody> Function(
    RequestOptions options,
    List<String> requests,
  ) handler;
  final List<String> requests = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final range = options.headers['range']?.toString();
    final auth = options.headers['authorization']?.toString();
    requests.add('range=${range ?? 'none'} auth=${auth ?? 'none'}');
    return handler(options, requests);
  }
}

Uint8List _payload(int from, int to) =>
    Uint8List.fromList(List.generate(to - from, (i) => (from + i) % 256));

ResponseBody _body({
  required int status,
  required List<int> bytes,
  required int total,
  int? start,
  String? etag,
}) {
  final headers = <String, List<String>>{
    if (etag != null) HttpHeaders.etagHeader: [etag],
    HttpHeaders.contentLengthHeader: ['${bytes.length}'],
    if (start != null) 'content-range': ['bytes $start-${total - 1}/$total'],
  };
  return ResponseBody(
    Stream<Uint8List>.fromIterable([Uint8List.fromList(bytes)]),
    status,
    headers: headers,
  );
}

/// Emits chunks on demand with an optional hold gate so tests can pause at a
/// deterministic byte offset.
class _SlowSource {
  StreamController<Uint8List> controller = StreamController<Uint8List>();
  Completer<void>? holdUntil;
  int sent = 0;

  void drip({
    int chunkSize = 100,
    int total = 1000,
    Completer<void>? holdUntil,
    int delayMs = 5,
  }) {
    unawaited(() async {
      while (sent < total && !controller.isClosed) {
        final end = (sent + chunkSize).clamp(0, total);
        if (!controller.isClosed) {
          controller.add(Uint8List.fromList(_payload(sent, end)));
        }
        sent = end;
        if (holdUntil != null && !holdUntil.isCompleted) {
          await holdUntil.future;
        }
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      if (!controller.isClosed) await controller.close();
    }());
  }
}

/// Windows keeps file handles open briefly after a cancelled transfer's
/// sink closes; teardown deletion can race that and fail spuriously.
Future<void> _deleteDirWithRetry(Directory dir) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  await dir.delete(recursive: true);
}

Future<Directory> _tempDir(String tag) async {
  return Directory.systemTemp.createTemp('lm_download_engine_$tag');
}

Future<DownloadEngine> _engine(
  MockDownloadAdapter adapter,
  Directory dir, {
  int maxConcurrent = 2,
  int? Function(String path)? freeDiskSpaceBytes,
  String? token,
  Future<void> Function(DownloadTask task)? postTransfer,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final engine = DownloadEngine(
    store: DownloadTaskStore(prefs),
    dio: Dio()..httpClientAdapter = adapter,
    workDirectory: () async => dir,
    tokenResolver: () => token,
    maxConcurrent: maxConcurrent,
    freeDiskSpaceBytes: freeDiskSpaceBytes,
  );
  engine.registerPostTransfer(postTransfer ??
      (task) async {
        // Mirror the consumer publish contract: validate + rename into place.
        final part = File(task.partPath);
        if (await part.exists()) await part.rename(task.finalPath);
      });
  await engine.ready;
  return engine;
}

Future<DownloadTask?> _waitFor(
  DownloadEngine engine,
  bool Function(DownloadTask) predicate, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final task in engine.tasks) {
      if (predicate(task)) return task;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return null;
}

/// Polls until NO task matches [predicate]; returns true when absent (or
/// false when the timeout elapsed with the task still present).
Future<bool> _waitForAbsent(
  DownloadEngine engine,
  bool Function(DownloadTask) predicate, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final present = engine.tasks.any(predicate);
    if (!present) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return engine.tasks.any(predicate);
}

ResponseBody _slowResponseBody(_SlowSource source) {
  // A resume's second HTTP request must not re-listen the first request's
  // already-consumed stream — reset the controller each call.
  source.controller = StreamController<Uint8List>();
  return ResponseBody(
    source.controller.stream,
    200,
    headers: {
      HttpHeaders.etagHeader: ['etag-1'],
      HttpHeaders.contentLengthHeader: ['1000'],
    },
  );
}

ResponseBody _continueResponseBody(int start) {
  return _body(
    status: 206,
    bytes: _payload(start, 1000),
    total: 1000,
    start: start,
    etag: 'etag-1',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadTaskStore', () {
    test('round-trips tasks through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = DownloadTaskStore(prefs);
      final now = DateTime.utc(2026, 11, 14);
      final task = DownloadTask(
        id: 't1',
        kind: DownloadTaskKind.gguf,
        groupId: 'g1',
        url: 'https://huggingface.co/a/b/resolve/main/m.gguf',
        finalPath: '/x/m.gguf',
        partPath: '/x/m.gguf.part',
        requiresAuth: true,
        state: DownloadTaskState.running,
        receivedBytes: 12,
        totalBytes: 100,
        etag: 'abc',
        createdAt: now,
        updatedAt: now,
      );
      await store.save([task]);
      final loaded = store.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 't1');
      expect(loaded.single.state, DownloadTaskState.running);
      expect(loaded.single.etag, 'abc');
      expect(loaded.single.requiresAuth, isTrue);
    });

    test('corrupt store loads empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        DownloadTaskStore.storageKey: '{not json',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = DownloadTaskStore(prefs);
      expect(store.load(), isEmpty);
    });
  });

  group('DownloadSidecar', () {
    test('save/load round-trip and identity match', () async {
      final dir = await _tempDir('sidecar');
      addTearDown(() => _deleteDirWithRetry(dir));
      final path = '${dir.path}/m.gguf.part.json';
      const sidecar = DownloadSidecar(
        sourceUrl: 'https://huggingface.co/a/b/resolve/main/m.gguf',
        etag: 'e1',
        totalBytes: 1000,
        offset: 400,
      );
      await sidecar.save(path);
      final loaded = await DownloadSidecar.load(path);
      expect(loaded, isNotNull);
      expect(loaded!.offset, 400);
      expect(loaded.etag, 'e1');
      expect(loaded.matches(etag: 'e1', totalBytes: 1000), isTrue);
      expect(loaded.matches(etag: 'e2', totalBytes: 1000), isFalse);
      expect(loaded.matches(etag: 'e1', totalBytes: 999), isFalse);
    });

    test('resolveOffset flags torn writes', () async {
      final dir = await _tempDir('torn');
      addTearDown(() => _deleteDirWithRetry(dir));
      final part = File('${dir.path}/m.gguf.part');
      await part.writeAsBytes(_payload(0, 100));
      const torn = DownloadSidecar(
        sourceUrl: 'u',
        etag: 'e',
        totalBytes: 1000,
        offset: 400,
      );
      expect(
        await DownloadSidecar.resolveOffset(sidecar: torn, partFile: part),
        -1,
      );
      const healthy = DownloadSidecar(
        sourceUrl: 'u',
        etag: 'e',
        totalBytes: 1000,
        offset: 100,
      );
      expect(
        await DownloadSidecar.resolveOffset(sidecar: healthy, partFile: part),
        100,
      );
    });
  });

  group('DownloadEngine', () {
    test('fresh download completes and publishes via post-transfer hook',
        () async {
      final dir = await _tempDir('fresh');
      addTearDown(() => _deleteDirWithRetry(dir));
      final hook = <DownloadTask>[];
      final adapter = MockDownloadAdapter((options, _) async {
        return _body(
          status: 200,
          bytes: _payload(0, 1000),
          total: 1000,
          etag: 'etag-1',
        );
      });
      final engine = await _engine(
        adapter,
        dir,
        postTransfer: (task) async {
          await File(task.partPath).rename(task.finalPath);
          hook.add(task);
        },
      );
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      final done = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
      );
      expect(done, isNotNull);
      expect(done!.receivedBytes, 1000);
      expect(File(done.finalPath).lengthSync(), 1000);
      expect(hook, hasLength(1));
      expect(hook.single.etag, 'etag-1');
      await engine.dispose();
    });

    test('resumes a retained partial via Range and completes', () async {
      final dir = await _tempDir('resume');
      addTearDown(() => _deleteDirWithRetry(dir));
      final requests = <String>[];
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        if (range == 'bytes=400-') {
          requests.add('range=400');
          return _continueResponseBody(400);
        }
        requests.add('no-range');
        return _body(status: 200, bytes: _payload(0, 1000), total: 1000, etag: 'etag-1');
      });
      final engine = await _engine(adapter, dir);
      // Seed AFTER engine init so orphan cleanup does not remove them.
      final part = File('${dir.path}/m.gguf.part');
      await part.writeAsBytes(_payload(0, 400));
      const sidecar = DownloadSidecar(
        sourceUrl: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        etag: 'etag-1',
        totalBytes: 1000,
        offset: 400,
      );
      await sidecar.save('${dir.path}/m.gguf.part.json');
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      final done = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
      );
      expect(done, isNotNull);
      expect(done!.receivedBytes, 1000);
      expect(File(done.finalPath).lengthSync(), 1000);
      expect(requests, ['range=400']);
      await engine.dispose();
    });

    test(
'pausing retains bytes; resuming finishes the transfer',
    () async {
      final dir = await _tempDir('pause');
      addTearDown(() => _deleteDirWithRetry(dir));
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        if (range != null) {
          final start = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
          return _body(
            status: 206,
            bytes: _payload(start, 1000),
            total: 1000,
            start: start,
            etag: 'etag-1',
          );
        }
        final source = _SlowSource();
        source.drip(chunkSize: 50, total: 1000, delayMs: 25);
        return ResponseBody(
          source.controller.stream,
          200,
          headers: {
            HttpHeaders.etagHeader: ['etag-1'],
            HttpHeaders.contentLengthHeader: ['1000'],
          },
        );
      });
      final engine = await _engine(adapter, dir);
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      final started = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.running,
      );
      expect(started, isNotNull);
      final progressing = await _waitFor(
        engine,
        (t) => t.id == task.id && t.receivedBytes >= 100,
      );
      expect(progressing, isNotNull);
      await engine.pause(task.id);
      final paused = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.paused,
      );
      expect(paused, isNotNull);
      expect(paused!.receivedBytes, greaterThan(0));
      expect(paused.receivedBytes, lessThan(1000));
      final keptBytes = File(task.partPath).lengthSync();
      expect(keptBytes, greaterThan(0));

      await engine.resume(task.id);
      final done = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
      );
      expect(done, isNotNull);
      expect(File(task.finalPath).lengthSync(), 1000);
      await engine.dispose();
    });

    test(
'cancel keeps bytes as a resumable canceled task',
    () async {
      final dir = await _tempDir('cancel');
      addTearDown(() => _deleteDirWithRetry(dir));
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        if (range != null) {
          final start = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
          return _body(
            status: 206,
            bytes: _payload(start, 1000),
            total: 1000,
            start: start,
            etag: 'etag-1',
          );
        }
        final source = _SlowSource();
        source.drip(chunkSize: 50, total: 1000, delayMs: 25);
        return ResponseBody(
          source.controller.stream,
          200,
          headers: {
            HttpHeaders.etagHeader: ['etag-1'],
            HttpHeaders.contentLengthHeader: ['1000'],
          },
        );
      });
      final engine = await _engine(adapter, dir);
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.running,
      );
      final progressing = await _waitFor(
        engine,
        (t) => t.id == task.id && t.receivedBytes >= 100,
      );
      expect(progressing, isNotNull);
      await engine.cancel(task.id);
      final canceled = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.canceled,
      );
      expect(canceled, isNotNull);
      expect(canceled!.receivedBytes, greaterThan(0));
      expect(File(task.partPath).existsSync(), isTrue);

      await engine.resume(task.id);
      final done = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
      );
      expect(done, isNotNull);
      expect(File(task.finalPath).lengthSync(), 1000);
      await engine.dispose();
    });

    test('delete removes the record, partial and sidecar', () async {
      final dir = await _tempDir('delete');
      addTearDown(() => _deleteDirWithRetry(dir));
      final source = _SlowSource();
      final gate = Completer<void>();
      final adapter = MockDownloadAdapter((options, _) async {
        final body = _slowResponseBody(source);
        source.drip(holdUntil: gate);
        return body;
      });
      final engine = await _engine(adapter, dir);
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      await _waitFor(
        engine,
        (t) => t.id == task.id && t.receivedBytes >= 100,
      );
      await engine.delete(task.id);
      final removed = await _waitForAbsent(
        engine,
        (t) => t.id == task.id,
        timeout: const Duration(seconds: 5),
      );
      expect(removed, isTrue);
      expect(File(task.partPath).existsSync(), isFalse);
      expect(File('${task.partPath}.json').existsSync(), isFalse);
      await engine.dispose();
    });

    test('server ignoring Range restarts from byte 0 and completes',
        () async {
      final dir = await _tempDir('ignorerange');
      addTearDown(() => _deleteDirWithRetry(dir));
      final adapter = MockDownloadAdapter((options, _) async {
        return _body(status: 200, bytes: _payload(0, 1000), total: 1000, etag: 'etag-1');
      });
      final engine = await _engine(adapter, dir);
      // Seed AFTER engine init so orphan cleanup does not remove them.
      final part = File('${dir.path}/m.gguf.part');
      await part.writeAsBytes(_payload(0, 400));
      const sidecar = DownloadSidecar(
        sourceUrl: 'u',
        etag: 'etag-1',
        totalBytes: 1000,
        offset: 400,
      );
      await sidecar.save('${dir.path}/m.gguf.part.json');
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      final done = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
      );
      expect(done, isNotNull);
      expect(File(done!.finalPath).lengthSync(), 1000);
      await engine.dispose();
    });

    test('torn partial below sidecar offset restarts from byte 0', () async {
      final dir = await _tempDir('torn');
      addTearDown(() => _deleteDirWithRetry(dir));
      final requested = <String>[];
      final adapter = MockDownloadAdapter((options, _) async {
        requested.add(options.headers['range']?.toString() ?? 'none');
        return _body(status: 200, bytes: _payload(0, 1000), total: 1000, etag: 'etag-1');
      });
      final engine = await _engine(adapter, dir);
      // Seed AFTER engine init so orphan cleanup does not remove them.
      final part = File('${dir.path}/m.gguf.part');
      await part.writeAsBytes(_payload(0, 100)); // shorter than offset 400
      const sidecar = DownloadSidecar(
        sourceUrl: 'u',
        etag: 'etag-1',
        totalBytes: 1000,
        offset: 400,
      );
      await sidecar.save('${dir.path}/m.gguf.part.json');
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      final done = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
      );
      expect(done, isNotNull);
      // No Range request: the torn partial was discarded.
      expect(requested, everyElement('none'));
      expect(File(done!.finalPath).lengthSync(), 1000);
      await engine.dispose();
    });

    test('dependent task waits for its model and runs after it', () async {
      final dir = await _tempDir('deps');
      addTearDown(() => _deleteDirWithRetry(dir));
      final order = <String>[];
      final adapter = MockDownloadAdapter((options, _) async {
        order.add(options.uri.path);
        return _body(status: 200, bytes: _payload(0, 100), total: 100, etag: 'e');
      });
      final engine = await _engine(adapter, dir, maxConcurrent: 2);
      final model = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      await engine.enqueue(
        kind: DownloadTaskKind.projector,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/mmproj.gguf',
        finalPath: '${dir.path}/mmproj.gguf',
        partPath: '${dir.path}/mmproj.gguf.part',
        dependsOnTaskId: model.id,
      );
      final projectorDone = await _waitFor(
        engine,
        (t) =>
            t.kind == DownloadTaskKind.projector &&
            t.state == DownloadTaskState.completed,
      );
      expect(projectorDone, isNotNull);
      expect(order.length, 2);
      await engine.dispose();
    });

    test('dependency failure cancels dependents with the reason', () async {
      final dir = await _tempDir('depfail');
      addTearDown(() => _deleteDirWithRetry(dir));
      final adapter = MockDownloadAdapter((options, _) async {
        if (options.uri.path.contains('model')) {
          return ResponseBody.fromString('forbidden', 403, headers: {
            HttpHeaders.contentLengthHeader: ['9'],
          });
        }
        return _body(status: 200, bytes: _payload(0, 10), total: 10, etag: 'e');
      });
      final engine = await _engine(adapter, dir);
      final model = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/model.gguf',
        finalPath: '${dir.path}/model.gguf',
        partPath: '${dir.path}/model.gguf.part',
      );
      final projector = await engine.enqueue(
        kind: DownloadTaskKind.projector,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/mmproj.gguf',
        finalPath: '${dir.path}/mmproj.gguf',
        partPath: '${dir.path}/mmproj.gguf.part',
        dependsOnTaskId: model.id,
      );
      final modelFailed = await _waitFor(
        engine,
        (t) => t.id == model.id && t.state == DownloadTaskState.failed,
      );
      expect(modelFailed, isNotNull);
      expect(modelFailed!.error, contains('403'));
      final canceled = await _waitFor(
        engine,
        (t) => t.id == projector.id && t.state == DownloadTaskState.canceled,
      );
      expect(canceled, isNotNull);
      expect(canceled!.error, contains('Dependency failed'));
      await engine.dispose();
    });

    test('post-transfer failure marks the task failed and keeps bytes',
        () async {
      final dir = await _tempDir('hookfail');
      addTearDown(() => _deleteDirWithRetry(dir));
      final adapter = MockDownloadAdapter((options, _) async {
        return _body(status: 200, bytes: _payload(0, 100), total: 100, etag: 'e');
      });
      final engine = await _engine(
        adapter,
        dir,
        postTransfer: (task) async => throw StateError('GGUF validation failed'),
      );
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      final failed = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.failed,
      );
      expect(failed, isNotNull);
      expect(failed!.error, contains('GGUF validation failed'));
      expect(File(task.partPath).existsSync(), isTrue);
      await engine.dispose();
    });

    test('concurrency cap holds at two simultaneous transfers', () async {
      final dir = await _tempDir('cap');
      addTearDown(() => _deleteDirWithRetry(dir));
      var inFlight = 0;
      var peak = 0;
      final adapter = MockDownloadAdapter((options, _) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        try {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return _body(status: 200, bytes: _payload(0, 100), total: 100, etag: 'e');
        } finally {
          inFlight--;
        }
      });
      final engine = await _engine(adapter, dir, maxConcurrent: 2);
      for (var i = 0; i < 4; i++) {
        await engine.enqueue(
          kind: DownloadTaskKind.gguf,
          groupId: 'g$i',
          url: 'https://huggingface.co/o/r/resolve/main/m$i.gguf',
          finalPath: '${dir.path}/m$i.gguf',
          partPath: '${dir.path}/m$i.gguf.part',
        );
      }
      final allDone = await _waitFor(
        engine,
        (t) => engine.tasks.every(
          (task) => task.state == DownloadTaskState.completed,
        ),
      );
      expect(allDone, isNotNull);
      expect(peak, 2);
      await engine.dispose();
    });

    test('persisted running task is demoted to paused on restart', () async {
      final dir = await _tempDir('restart');
      addTearDown(() => _deleteDirWithRetry(dir));
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = DownloadTaskStore(prefs);
      final now = DateTime.now();
      final running = DownloadTask(
        id: 't-running',
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
        state: DownloadTaskState.running,
        receivedBytes: 500,
        totalBytes: 1000,
        createdAt: now,
        updatedAt: now,
      );
      await store.save([running]);
      final engine = DownloadEngine(
        store: store,
        dio: Dio(),
        workDirectory: () async => dir,
        tokenResolver: () => null,
      );
      await engine.ready;
      final restored = engine.tasks.single;
      expect(restored.state, DownloadTaskState.paused);
      expect(restored.receivedBytes, 500);
      await engine.dispose();
    });

    test('orphan partials without a task record are cleaned up', () async {
      final dir = await _tempDir('orphans');
      addTearDown(() => _deleteDirWithRetry(dir));
      final orphanPart = File('${dir.path}/orphan.gguf.part');
      await orphanPart.writeAsBytes(_payload(0, 10));
      final orphanSidecar = File('${dir.path}/orphan.gguf.part.json');
      await orphanSidecar.writeAsString('{}');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final engine = DownloadEngine(
        store: DownloadTaskStore(prefs),
        dio: Dio(),
        workDirectory: () async => dir,
        tokenResolver: () => null,
      );
      await engine.ready;
      expect(orphanPart.existsSync(), isFalse);
      expect(orphanSidecar.existsSync(), isFalse);
      await engine.dispose();
    });

    test('auth token rides on the request and 403 fails auth-specific',
        () async {
      final dir = await _tempDir('auth');
      addTearDown(() => _deleteDirWithRetry(dir));
      final requests = <String>[];
      final adapter = MockDownloadAdapter((options, req) async {
        requests.add(req.last);
        return ResponseBody.fromString('forbidden', 403, headers: {
          HttpHeaders.contentLengthHeader: ['9'],
        });
      });
      final engine = await _engine(adapter, dir, token: 'tok-123');
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
        requiresAuth: true,
      );
      final failed = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.failed,
      );
      expect(requests.single, contains('auth=Bearer tok-123'));
      expect(failed, isNotNull);
      expect(failed!.error, contains('Authentication failed'));
      await engine.dispose();
    });

    test('no Bearer header without auth requirement', () async {
      final dir = await _tempDir('noauth');
      addTearDown(() => _deleteDirWithRetry(dir));
      final requests = <String>[];
      final adapter = MockDownloadAdapter((options, req) async {
        requests.add(req.last);
        return _body(status: 200, bytes: _payload(0, 10), total: 10, etag: 'e');
      });
      final engine = await _engine(adapter, dir, token: 'tok-123');
      await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      await _waitFor(
        engine,
        (t) => t.state == DownloadTaskState.completed,
      );
      expect(requests.single, contains('auth=none'));
      await engine.dispose();
    });

    test('delegateToOs hands a running task to native and marks it; '
        'failure falls back to the in-app path', () async {
      final dir = await _tempDir('osdelegate');
      addTearDown(() => _deleteDirWithRetry(dir));
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        if (range != null) {
          final start = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
          return _body(
            status: 206,
            bytes: _payload(start, 1000),
            total: 1000,
            start: start,
            etag: 'etag-1',
          );
        }
        final source = _SlowSource();
        source.drip(chunkSize: 50, total: 1000, delayMs: 25);
        return ResponseBody(
          source.controller.stream,
          200,
          headers: {
            HttpHeaders.etagHeader: ['etag-1'],
            HttpHeaders.contentLengthHeader: ['1000'],
          },
        );
      });
      final engine = await _engine(adapter, dir);
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      await _waitFor(
        engine,
        (t) => t.id == task.id && t.receivedBytes >= 100,
      );
      var handOffCalls = 0;
      var handedOffset = -1;
      Future<bool> bridge(OsDownloadHandOff payload) async {
        handOffCalls++;
        handedOffset = payload.offset;
        return true;
      }

      final handed = await engine.delegateToOs(task.id, handOff: bridge);
      expect(handed, isTrue);
      expect(handOffCalls, 1);
      expect(handedOffset, greaterThanOrEqualTo(100));
      final managed = engine.tasks.firstWhere((t) => t.id == task.id);
      expect(managed.osManaged, isTrue);
      expect(managed.state, DownloadTaskState.running);
      // Native progress events drive bookkeeping.
      await engine.ingestNativeEvent(task.id, receivedBytes: 800);
      expect(
        engine.tasks.firstWhere((t) => t.id == task.id).receivedBytes,
        800,
      );
      // Completion event with no consumer hook completes the task.
      await engine.ingestNativeEvent(task.id, completed: true);
      expect(
        engine.tasks.firstWhere((t) => t.id == task.id).state,
        DownloadTaskState.completed,
      );
      await engine.dispose();
    });

    test('delegateToOs falls back when the OS hand-off fails', () async {
      final dir = await _tempDir('osfail');
      addTearDown(() => _deleteDirWithRetry(dir));
      final source = _SlowSource();
      final gate = Completer<void>();
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        if (range != null) {
          final start = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
          return _body(
            status: 206,
            bytes: _payload(start, 1000),
            total: 1000,
            start: start,
            etag: 'etag-1',
          );
        }
        final body = _slowResponseBody(source);
        source.drip(holdUntil: gate, chunkSize: 100, total: 1000);
        return body;
      });
      final engine = await _engine(adapter, dir);
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      await _waitFor(
        engine,
        (t) => t.id == task.id && t.receivedBytes >= 100,
      );
      final handed = await engine.delegateToOs(
        task.id,
        handOff: (payload) async => false,
      );
      expect(handed, isFalse);
      expect(
        engine.tasks.firstWhere((t) => t.id == task.id).osManaged,
        isFalse,
      );
      expect(
        engine.tasks.firstWhere((t) => t.id == task.id).state,
        DownloadTaskState.paused,
      );
      await engine.resume(task.id);
      final done = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
      );
      expect(done, isNotNull);
      expect(File(task.finalPath).lengthSync(), 1000);
      await engine.dispose();
    });

    test('disk-space shortfall fails the task with a disk-full reason',
        () async {
      final dir = await _tempDir('diskfull');
      addTearDown(() => _deleteDirWithRetry(dir));
      final adapter = MockDownloadAdapter((options, _) async {
        return _body(status: 200, bytes: _payload(0, 1000), total: 1000, etag: 'e');
      });
      final engine = await _engine(
        adapter,
        dir,
        freeDiskSpaceBytes: (_) => 1024,
      );
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      final failed = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.failed,
      );
      expect(failed, isNotNull);
      expect(failed!.error, contains('disk space'));
      await engine.dispose();
    });

    test(
'pauseAllRunning pauses running+queued as system-paused and '
        'resumeSystemPaused restores exactly them',
    () async {
      final dir = await _tempDir('syspause');
      addTearDown(() => _deleteDirWithRetry(dir));
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        if (range != null) {
          final start = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
          return _continueResponseBody(start);
        }
        final source = _SlowSource();
        source.drip(chunkSize: 50, total: 1000, delayMs: 25);
        return ResponseBody(
          source.controller.stream,
          200,
          headers: {
            HttpHeaders.etagHeader: ['etag-1'],
            HttpHeaders.contentLengthHeader: ['1000'],
          },
        );
      });
      final engine = await _engine(adapter, dir, maxConcurrent: 2);
      final running = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g-running',
        url: 'https://huggingface.co/o/r/resolve/main/running.gguf',
        finalPath: '${dir.path}/running.gguf',
        partPath: '${dir.path}/running.gguf.part',
      );
      final queued = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g-queued',
        url: 'https://huggingface.co/o/r/resolve/main/queued.gguf',
        finalPath: '${dir.path}/queued.gguf',
        partPath: '${dir.path}/queued.gguf.part',
      );
      // Fill the 2 slots so the queued task stays queued.
      await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g-slot',
        url: 'https://huggingface.co/o/r/resolve/main/slot.gguf',
        finalPath: '${dir.path}/slot.gguf',
        partPath: '${dir.path}/slot.gguf.part',
      );
      await _waitFor(
        engine,
        (t) =>
            t.id == running.id &&
            t.state == DownloadTaskState.running &&
            t.receivedBytes > 0,
      );
      // User pauses a third task manually.
      final userPaused = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g-user',
        url: 'https://huggingface.co/o/r/resolve/main/user.gguf',
        finalPath: '${dir.path}/user.gguf',
        partPath: '${dir.path}/user.gguf.part',
      );
      await engine.pause(userPaused.id);

      await engine.pauseAllRunning(note: 'network: connection lost');

      final pausedRunning = await _waitFor(
        engine,
        (t) =>
            t.id == running.id &&
            t.state == DownloadTaskState.paused &&
            t.receivedBytes > 0,
      );
      expect(pausedRunning, isNotNull);
      expect(
        engine.tasks
            .firstWhere((t) => t.id == queued.id)
            .state,
        DownloadTaskState.paused,
      );
      expect(
        engine.tasks.firstWhere((t) => t.id == userPaused.id).state,
        DownloadTaskState.paused,
      );
      // Network note lands in the error field of the system-paused task.
      expect(pausedRunning!.error, contains('network'));

      await engine.resumeSystemPaused();

      final resumedRunning = await _waitFor(
        engine,
        (t) =>
            t.id == running.id &&
            (t.state == DownloadTaskState.completed ||
                t.state == DownloadTaskState.running),
      );
      expect(resumedRunning, isNotNull);
      // The queued task started after its slot freed; the user-paused task
      // was never touched by resumeSystemPaused.
      expect(
        engine.tasks.firstWhere((t) => t.id == userPaused.id).state,
        DownloadTaskState.paused,
      );
      await engine.dispose();
    });

    test('user pause clears system bookkeeping (no double resume)',
        () async {
      final dir = await _tempDir('userpause');
      addTearDown(() => _deleteDirWithRetry(dir));
      final gate = Completer<void>();
      final source = _SlowSource();
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        if (range != null) {
          final start = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
          return _body(
            status: 206,
            bytes: _payload(start, 1000),
            total: 1000,
            start: start,
            etag: 'etag-1',
          );
        }
        final body = _slowResponseBody(source);
        source.drip(holdUntil: gate, chunkSize: 100, total: 1000);
        return body;
      });
      final engine = await _engine(adapter, dir);
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      await _waitFor(
        engine,
        (t) => t.id == task.id && t.receivedBytes >= 100,
      );
      await engine.pauseAllRunning(note: 'backgrounded');
      await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.paused,
      );
      // The user resumes manually — resumeSystemPaused must not re-queue.
      await engine.resume(task.id);
      await engine.resumeSystemPaused();

      // Wait a moment; if double-handled, the task would flip states.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final t = engine.tasks.firstWhere((x) => x.id == task.id);
      expect(
        t.state,
        isNot(DownloadTaskState.paused),
        reason: 'user-resumed task should be running/queued/completed',
      );
      await engine.dispose();
    });

    test('checkpoint sidecar advances during transfer and honors the '
        'interval knob', () async {
      final dir = await _tempDir('checkpoint');
      addTearDown(() => _deleteDirWithRetry(dir));
      final source = _SlowSource();
      // 50 bytes every 30ms: reaches 400 bytes with three checkpoints in
      // ~240ms, completes ~3s — time to observe checkpoints while running.
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        if (range != null) {
          final start = int.parse(range.replaceAll(RegExp(r'[^\d]'), ''));
          return _body(
            status: 206,
            bytes: _payload(start, 5000),
            total: 5000,
            start: start,
            etag: 'etag-1',
          );
        }
        source.drip(chunkSize: 50, total: 5000, delayMs: 30);
        return ResponseBody(
          source.controller.stream,
          200,
          headers: {
            HttpHeaders.etagHeader: ['etag-1'],
            HttpHeaders.contentLengthHeader: ['5000'],
          },
        );
      });
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final engine = DownloadEngine(
        store: DownloadTaskStore(prefs),
        dio: Dio()..httpClientAdapter = adapter,
        workDirectory: () async => dir,
        tokenResolver: () => null,
        checkpointIntervalBytes: 200,
      );
      engine.registerPostTransfer((task) async {
        final part = File(task.partPath);
        if (await part.exists()) await part.rename(task.finalPath);
      });
      await engine.ready;
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      // Wait until at least two checkpoints (400 bytes) landed in the
      // sidecar while the transfer is still running.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      var checkpointed = 0;
      while (DateTime.now().isBefore(deadline)) {
        final sidecar = await DownloadSidecar.load('${task.partPath}.json');
        checkpointed = sidecar?.offset ?? 0;
        if (checkpointed >= 400) break;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      expect(checkpointed, greaterThanOrEqualTo(400),
          reason: 'checkpoints should trail received bytes by < interval');
      await engine.pause(task.id);
      await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.paused,
      );
      await engine.resume(task.id);
      final done = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
        timeout: const Duration(seconds: 30),
      );
      expect(done, isNotNull);
      expect(File(task.finalPath).lengthSync(), 5000);
      await engine.dispose();
    });

    test('initial sidecar is written when a transfer enters running',
        () async {
      final dir = await _tempDir('initialsidecar');
      addTearDown(() => _deleteDirWithRetry(dir));
      final source = _SlowSource();
      final gate = Completer<void>();
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        if (range != null) {
          final start = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
          return _body(
            status: 206,
            bytes: _payload(start, 1000),
            total: 1000,
            start: start,
            etag: 'etag-1',
          );
        }
        final body = _slowResponseBody(source);
        source.drip(holdUntil: gate, chunkSize: 100, total: 1000);
        return body;
      });
      final engine = await _engine(adapter, dir);
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.running,
      );
      // The running state emits before the async initial-sidecar write
      // completes — poll for it.
      DownloadSidecar? sidecar;
      final sidecarDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(sidecarDeadline)) {
        sidecar = await DownloadSidecar.load('${task.partPath}.json');
        if (sidecar != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(sidecar, isNotNull);
      expect(sidecar!.sourceUrl, task.url);
      expect(sidecar.totalBytes, 1000);
      await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
      );
      await engine.dispose();
    });

    test(
'resume after hard kill truncates OS-cached bytes past the '
        'checkpoint (no mid-file hole)',
    () async {
      final dir = await _tempDir('truncate');
      addTearDown(() => _deleteDirWithRetry(dir));
      final requested = <String>[];
      final adapter = MockDownloadAdapter((options, _) async {
        final range = options.headers['range']?.toString();
        requested.add(range ?? 'none');
        if (range == 'bytes=1000-') {
          return _body(
            status: 206,
            bytes: _payload(1000, 2000),
            total: 2000,
            start: 1000,
            etag: 'etag-1',
          );
        }
        return _body(status: 200, bytes: _payload(0, 2000), total: 2000, etag: 'etag-1');
      });
      final engine = await _engine(adapter, dir);
      // Simulate a hard kill: the OS cache kept 1200 bytes but the last
      // checkpoint (sidecar) only recorded 1000.
      final part = File('${dir.path}/m.gguf.part');
      await part.writeAsBytes(_payload(0, 1200));
      const sidecar = DownloadSidecar(
        sourceUrl: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        etag: 'etag-1',
        totalBytes: 2000,
        offset: 1000,
      );
      await sidecar.save('${dir.path}/m.gguf.part.json');
      final task = await engine.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'g',
        url: 'https://huggingface.co/o/r/resolve/main/m.gguf',
        finalPath: '${dir.path}/m.gguf',
        partPath: '${dir.path}/m.gguf.part',
      );
      final done = await _waitFor(
        engine,
        (t) => t.id == task.id && t.state == DownloadTaskState.completed,
      );
      expect(done, isNotNull);
      expect(requested, ['bytes=1000-']);
      // Verify no hole: every byte matches the deterministic payload.
      final bytes = await File(task.finalPath).readAsBytes();
      expect(bytes.length, 2000);
      var hole = -1;
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] != i % 256) {
          hole = i;
          break;
        }
      }
      expect(hole, -1, reason: 'byte $hole diverges — mid-file hole');
      await engine.dispose();
    });
  });
}
