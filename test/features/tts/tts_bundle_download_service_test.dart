import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/downloads/download_engine.dart';
import 'package:localmind/core/downloads/download_task.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/tts/data/tts_bundle.dart';
import 'package:localmind/features/tts/data/tts_bundle_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal melo-shaped bundle archive (model.onnx + tokens.txt + lexicon.txt
/// + dict/) with a `test-bundle` top-level directory, base64-encoded so the
/// test stays hermetic.
const _fixtureTarBz2Base64 =
    'QlpoOTFBWSZTWQ4WckwAAXTf5ceQQAP/gCc+hBB+/55AIBABIAAwEBQECDABOCkJKSNNAGmgGjQaNA09QA0aaGAAAAA0AAAAACKSZGpqehGnqT0E0A9Mkehknqeo0x7bjzjAyugjWNrh2yBJd0r1VLejTklLEYHoGwJmgppguGo4jA3woFg8KSoO8aB3a5G/ju8OkbrPP9z8mIcAxzAygB2GzZt28w4jcOkbBgeuQOuY0nqwmOqDNDSKjOQ9o0srejMZTuG+JJYlAiY5Ctx8hoMEWA1GsxvCdclBPCdHhW7XCV2dil5DjWIXvVCJyFou+9hY6SNIxaxtu1cMo0tH58lR3juvOGwcubJzWjOWEqcRhZ5acc/HQPPhtGvIN4wN3KZxkQP8xOr19ufMdg8o/4c+eA+n6gow5Ls8AgP4u5IpwoSAcLOSYA==';

final Uint8List _fixtureBytes =
    Uint8List.fromList(base64Decode(_fixtureTarBz2Base64));

class _TestBundle implements TtsBundleDescriptor {
  @override
  EngineId get engine => EngineId.melo;

  @override
  String get bundleDirName => 'test-bundle';

  @override
  String get tarballUrl => 'https://example.invalid/tts-models/test-bundle.tar.bz2';

  @override
  int get totalSizeBytes => _fixtureBytes.length;

  @override
  String get modelFileName => 'model.onnx';

  @override
  String get tokensFileName => 'tokens.txt';

  @override
  List<String> get requiredFileNames => ['model.onnx', 'tokens.txt', 'lexicon.txt'];

  @override
  List<String> get requiredDirNames => ['dict'];

  @override
  List<String> get ruleFstFileNames => ['date.fst'];
}

/// Dio adapter serving the fixture bytes (or garbage) for every request;
/// optionally never responds, to hold a task mid-transfer.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.hang = false, this.corrupt = false});

  final bool hang;
  final bool corrupt;
  final List<String> requests = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri.toString());
    if (hang) {
      return Completer<ResponseBody>().future;
    }
    final bytes = corrupt ? Uint8List.fromList([1, 2, 3, 4]) : _fixtureBytes;
    return ResponseBody(
      Stream<Uint8List>.fromIterable([bytes]),
      200,
      headers: {
        HttpHeaders.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }
}

Future<Directory> _tempDir(String tag) =>
    Directory.systemTemp.createTemp('lm_tts_bundle_${tag}_');

/// Windows keeps handles open briefly after cancelled transfers; retries
/// make teardown deterministic.
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

Future<DownloadEngine> _engine(_StubAdapter adapter, Directory dir) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final engine = DownloadEngine(
    store: DownloadTaskStore(prefs),
    dio: Dio()..httpClientAdapter = adapter,
    workDirectory: () async => dir,
    tokenResolver: () => null,
  );
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

void main() {
  late Directory supportDir;
  late Directory workDir;

  setUp(() async {
    supportDir = await _tempDir('support');
    workDir = await _tempDir('work');
  });

  tearDown(() async {
    await _deleteDirWithRetry(supportDir);
    await _deleteDirWithRetry(workDir);
  });

  TtsBundleDownloadService serviceFor(
    DownloadEngine engine, {
    List<TtsBundleDescriptor>? descriptors,
  }) {
    return TtsBundleDownloadService(
      engine: engine,
      descriptors: descriptors ?? [_TestBundle()],
      supportDirectoryResolver: () async => supportDir,
    );
  }

  group('TtsBundleDownloadService', () {
    test('enqueue → engine transfer → extraction → completed + installed', () async {
      final engine = await _engine(_StubAdapter(), workDir);
      final service = serviceFor(engine);
      final descriptor = _TestBundle();

      await service.enqueue(descriptor);
      final task = await _waitFor(
        engine,
        (t) => t.state == DownloadTaskState.completed,
      );

      expect(task, isNotNull);
      expect(task!.kind, DownloadTaskKind.ttsBundle);
      expect(task.groupId, 'tts-test-bundle');
      expect(await service.isDownloaded(descriptor), isTrue);

      final bundleDir = Directory(
        '${supportDir.path}/tts_models/melo/test-bundle',
      );
      expect(await File('${bundleDir.path}/model.onnx').exists(), isTrue);
      expect(await Directory('${bundleDir.path}/dict').exists(), isTrue);
      // The archive is scratch and must be gone after a successful publish.
      expect(
        await File('${supportDir.path}/tts_bundle_archives/test-bundle.tar.bz2')
            .exists(),
        isFalse,
      );
    });

    test('enqueue rejects a duplicate non-failed task', () async {
      final adapter = _StubAdapter(hang: true);
      final engine = await _engine(adapter, workDir);
      final service = serviceFor(engine);

      await service.enqueue(_TestBundle());
      expect(
        () => service.enqueue(_TestBundle()),
        throwsA(isA<StateError>()),
      );
    });

    test('corrupt archive fails the task and cleans partial extraction', () async {
      final engine = await _engine(_StubAdapter(corrupt: true), workDir);
      final service = serviceFor(engine);
      final descriptor = _TestBundle();

      await service.enqueue(descriptor);
      final task = await _waitFor(
        engine,
        (t) => t.state == DownloadTaskState.failed,
      );

      expect(task, isNotNull);
      expect(await service.isDownloaded(descriptor), isFalse);
      // No half-extracted bundle may linger.
      expect(
        await Directory(
          '${supportDir.path}/tts_models/melo/test-bundle',
        ).exists(),
        isFalse,
      );
    });

    test('cancel during transfer clears the archive lineage', () async {
      final engine = await _engine(_StubAdapter(hang: true), workDir);
      final service = serviceFor(engine);
      final descriptor = _TestBundle();

      await service.enqueue(descriptor);
      final task = await _waitFor(
        engine,
        (t) => t.state == DownloadTaskState.running,
      );
      expect(task, isNotNull);

      await service.cancel(descriptor);
      final canceled = await _waitFor(
        engine,
        (t) => t.state == DownloadTaskState.canceled,
      );
      expect(canceled, isNotNull);
      expect(
        await File(
          '${supportDir.path}/tts_bundle_archives/test-bundle.tar.bz2.part',
        ).exists(),
        isFalse,
      );
    });

    test('deleteBundle removes the extracted bundle and lineage', () async {
      final engine = await _engine(_StubAdapter(), workDir);
      final service = serviceFor(engine);
      final descriptor = _TestBundle();

      await service.enqueue(descriptor);
      await _waitFor(
        engine,
        (t) => t.state == DownloadTaskState.completed,
      );
      expect(await service.isDownloaded(descriptor), isTrue);

      await service.deleteBundle(descriptor);
      expect(await service.isDownloaded(descriptor), isFalse);
      expect(
        await Directory(
          '${supportDir.path}/tts_models/melo/test-bundle',
        ).exists(),
        isFalse,
      );
    });

    test('ruleFstsArg joins only the FST files actually present', () async {
      final engine = await _engine(_StubAdapter(), workDir);
      final service = serviceFor(engine);
      final descriptor = _TestBundle();

      expect(await service.ruleFstsArg(descriptor), '');

      await service.enqueue(descriptor);
      await _waitFor(
        engine,
        (t) => t.state == DownloadTaskState.completed,
      );
      // The fixture has no date.fst — still empty after extraction.
      expect(await service.ruleFstsArg(descriptor), '');
    });

    test('joinedFilesArg returns absolute comma-joined lexicon paths', () async {
      final engine = await _engine(_StubAdapter(), workDir);
      final service = serviceFor(engine);

      final arg = await service.joinedFilesArg(_TestBundle(), const [
        'lexicon.txt',
        'tokens.txt',
      ]);
      final parts = arg.split(',');
      expect(parts.length, 2);
      expect(parts[0], contains('lexicon.txt'));
      expect(parts[1], contains('tokens.txt'));
    });

    test('default descriptors are Melo and Kokoro', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final engine = DownloadEngine(
        store: DownloadTaskStore(prefs),
        dio: Dio(),
        workDirectory: () async => workDir,
        tokenResolver: () => null,
      );
      final service = TtsBundleDownloadService(
        engine: engine,
        supportDirectoryResolver: () async => supportDir,
      );
      expect(
        service.descriptors.map((d) => d.engine),
        [EngineId.melo, EngineId.kokoro],
      );
    });
  });
}
