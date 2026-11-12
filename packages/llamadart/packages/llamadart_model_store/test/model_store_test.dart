@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_model_store/llamadart_model_store.dart';
import 'package:path/path.dart' as p;

import 'support/model_server.dart';

void main() {
  late Directory root;
  late ModelServer server;
  late LlamaModel pair;

  final modelBytes = List<int>.generate(4096, (i) => i % 251);
  final projectorBytes = List<int>.generate(1024, (i) => i % 13);
  final otherBytes = List<int>.generate(2048, (i) => i % 7);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('model_store_test_');
    server = await ModelServer.start(<String, List<int>>{
      '/model.gguf': modelBytes,
      '/mmproj.gguf': projectorBytes,
      '/other.gguf': otherBytes,
    });
    pair = LlamaModel(
      ModelSource.url(server.url('/model.gguf')),
      projector: ModelSource.url(server.url('/mmproj.gguf')),
    );
  });

  tearDown(() async {
    await server.close();
    await root.delete(recursive: true);
  });

  Future<ModelStore> open(String appId) =>
      ModelStore.open(directory: root.path, appId: appId);

  LlamaModel single(String path) =>
      LlamaModel(ModelSource.url(server.url(path)));

  /// The reference files of [model]'s entry.
  List<String> referenceFiles(LlamaModel model) {
    final refs = Directory(
      p.join(root.path, 'entries', ModelStore.entryIdFor(model), 'refs'),
    );
    // Leaves out the temporary files of writes in progress.
    return refs.existsSync()
        ? [
            for (final file in refs.listSync())
              if (p.extension(file.path) == '.json') p.basename(file.path),
          ]
        : <String>[];
  }

  /// The contents of the single reference file of [model]'s entry.
  String referenceContents(LlamaModel model) => File(
    p.join(
      root.path,
      'entries',
      ModelStore.entryIdFor(model),
      'refs',
      referenceFiles(model).single,
    ),
  ).readAsStringSync();

  /// Marks [file] as last used two days ago in its cache metadata.
  Future<void> age(ModelCacheEntry file) async {
    final metadata = File(p.join(p.dirname(file.filePath), 'metadata.json'));
    final json = jsonDecode(await metadata.readAsString()) as Map;
    json['updated_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 2))
        .toIso8601String();
    await metadata.writeAsString(jsonEncode(json));
  }

  Future<List<String>> storeFileNames() async =>
      [for (final file in await (await open('inspector')).list()) file.fileName]
        ..sort();

  /// Releases the entry [id] for [appId] from another process.
  Future<void> releaseInAnotherProcess(String appId, String id) async {
    final result = await Process.run(_dartExecutable(), [
      'test/support/release_entry.dart',
      root.path,
      appId,
      id,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  group('after the store directory moves', () {
    Future<void> moveStore() async {
      final previous = root;
      final moved = '${root.path}_moved';
      await previous.rename(moved);
      root = Directory(moved);
    }

    test('inventory and final release work before another ensure', () async {
      final a = await open('app.a');
      final entry = await a.ensure(pair);
      await (await open('app.b')).ensure(pair);
      await moveStore();
      final movedA = await open('app.a');
      final movedB = await open('app.b');
      final listed = (await movedA.entries()).single;
      final files = await movedA.list();
      expect(files, hasLength(2));
      expect(listed.id, entry.id);
      expect(listed.references.map((r) => r.appId).toSet(), {'app.a', 'app.b'});
      for (final file in [listed.model, listed.projector!]) {
        expect(p.isWithin(movedA.directory, file.filePath), isTrue);
        expect((await movedA.get(file.cacheKey))?.filePath, file.filePath);
      }
      await movedA.release(entry.id);
      expect(File(listed.model.filePath).existsSync(), isTrue);
      expect(await movedA.prune(maxBytes: 0), isEmpty);
      await movedB.release(entry.id);
      expect(File(listed.model.filePath).existsSync(), isFalse);
      expect(File(listed.projector!.filePath).existsSync(), isFalse);
      expect(await movedB.entries(), isEmpty);
      expect(server.requests['/model.gguf'], 1);
      expect(server.requests['/mmproj.gguf'], 1);
    });

    test('prune collects relocated unreferenced files before ensure', () async {
      final a = await open('app.a');
      final entry = await a.ensure(pair);
      final refs = Directory(p.join(root.path, 'entries', entry.id, 'refs'));
      await refs.delete(recursive: true);
      await moveStore();
      final moved = await open('collector');
      final files = await moved.list();
      expect((await moved.prune(maxBytes: 0)).map((e) => e.fileName).toSet(), {
        'model.gguf',
        'mmproj.gguf',
      });
      for (final file in files) {
        expect(File(file.filePath).existsSync(), isFalse);
      }
      expect(await moved.entries(), isEmpty);
      expect(server.requests['/model.gguf'], 1);
      expect(server.requests['/mmproj.gguf'], 1);
    });
  });

  group('ensure', () {
    test('keeps a model and its projector as one referenced entry', () async {
      final store = await open('app.a');

      final entry = await store.ensure(pair);

      expect(entry.id, ModelStore.entryIdFor(pair));
      expect(await File(entry.model.filePath).readAsBytes(), modelBytes);
      expect(
        await File(entry.projector!.filePath).readAsBytes(),
        projectorBytes,
      );
      expect(entry.references.map((r) => r.appId), ['app.a']);
      final loadable = entry.toLlamaModel();
      expect(loadable.source.path, entry.model.filePath);
      expect(loadable.projector!.path, entry.projector!.filePath);

      final listed = await store.entries();
      expect(listed.map((e) => e.id), [entry.id]);
      expect(listed.single.projector!.cacheKey, entry.projector!.cacheKey);
    });

    test('reuses files another app downloaded and records both apps', () async {
      await (await open('app.a')).ensure(pair);
      final entry = await (await open('app.b')).ensure(pair);

      expect(server.requests['/model.gguf'], 1);
      expect(server.requests['/mmproj.gguf'], 1);
      expect(entry.references.map((r) => r.appId).toSet(), {'app.a', 'app.b'});
    });

    test('drops its reference when a download fails', () async {
      final store = await open('app.a');
      final broken = LlamaModel(
        ModelSource.url(server.url('/model.gguf')),
        projector: ModelSource.url(server.url('/missing.gguf')),
      );

      await expectLater(
        store.ensure(broken, options: ModelLoadOptions(maxRetries: 0)),
        throwsA(isA<LlamaException>()),
      );

      expect(await store.entries(), isEmpty);
      // The downloaded model stays for a retry, but nothing protects it.
      expect(await storeFileNames(), ['model.gguf']);
      await store.prune(maxBytes: 0);
      expect(await storeFileNames(), isEmpty);
    });

    test('drops its reference on a cacheOnly miss', () async {
      final store = await open('app.a');

      await expectLater(
        store.ensure(
          pair,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
        ),
        throwsA(isA<LlamaException>()),
      );

      final refs = Directory(
        p.join(root.path, 'entries', ModelStore.entryIdFor(pair), 'refs'),
      );
      expect(refs.listSync(), isEmpty);
    });

    test('a cancelled call keeps the reference the app already held', () async {
      final a = await open('app.a');
      final model = single('/model.gguf');
      final entry = await a.ensure(model);
      final cancelled = ModelDownloadCancelToken()..cancel();

      await expectLater(
        a.ensure(model, options: ModelLoadOptions(cancelToken: cancelled)),
        throwsA(isA<LlamaStateException>()),
      );

      expect((await a.entries()).single.references.map((r) => r.appId), [
        'app.a',
      ]);
      await (await open('app.b')).prune(maxBytes: 0);
      expect(File(entry.model.filePath).existsSync(), isTrue);
    });

    test('overlapping failed calls of one app leave no reference', () async {
      final a = await open('app.a');
      final missing = single('/missing.gguf');
      final options = ModelLoadOptions(maxRetries: 0);

      final results = await Future.wait([
        a
            .ensure(missing, options: options)
            .then((_) => 'ok', onError: (_) => 'fail'),
        a
            .ensure(missing, options: options)
            .then((_) => 'ok', onError: (_) => 'fail'),
      ]);

      expect(results, ['fail', 'fail']);
      expect(referenceFiles(missing), isEmpty);
    });

    test(
      'a later failed call does not restore an earlier failed one',
      () async {
        final a = await open('app.a');
        final missing = single('/missing.gguf');
        final gate = Completer<void>();
        server.gates['/missing.gguf'] = gate.future;
        final options = ModelLoadOptions(maxRetries: 0);

        final first = a
            .ensure(missing, options: options)
            .then((_) => 'ok', onError: (_) => 'fail');
        while (server.requests['/missing.gguf'] == null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final firstReference = referenceContents(missing);
        final second = a
            .ensure(missing, options: options)
            .then((_) => 'ok', onError: (_) => 'fail');
        // The second call has recorded its reference and waits for the
        // first download's entry lock.
        while (referenceContents(missing) == firstReference) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        gate.complete();

        expect(await Future.wait([first, second]), ['fail', 'fail']);
        expect(referenceFiles(missing), isEmpty);
      },
    );

    test('a call after a release is not undone to before it', () async {
      final a = await open('app.a');
      final model = single('/model.gguf');
      final entry = await a.ensure(model);
      final gate = Completer<void>();
      server.gates['/model.gguf'] = gate.future;
      server.failing.add('/model.gguf');
      final refresh = ModelLoadOptions(
        cachePolicy: ModelCachePolicy.refresh,
        maxRetries: 0,
      );

      final first = a
          .ensure(model, options: refresh)
          .then((_) => 'ok', onError: (_) => 'fail');
      while (server.requests['/model.gguf'] != 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await expectLater(
        a.release(entry.id),
        throwsA(isA<ModelCacheEntryInUseException>()),
      );
      final second = a
          .ensure(model, options: refresh)
          .then((_) => 'ok', onError: (_) => 'fail');
      while (referenceFiles(model).isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      gate.complete();

      expect(await Future.wait([first, second]), ['fail', 'fail']);
      expect(referenceFiles(model), isEmpty);
    });

    test('a release in another process is not undone', () async {
      final a = await open('app.a');
      final model = single('/model.gguf');
      final entry = await a.ensure(model);
      final gate = Completer<void>();
      server
        ..gates['/model.gguf'] = gate.future
        ..failing.add('/model.gguf');
      final refresh = ModelLoadOptions(
        cachePolicy: ModelCachePolicy.refresh,
        maxRetries: 0,
      );

      final first = a
          .ensure(model, options: refresh)
          .then((_) => 'ok', onError: (_) => 'fail');
      while (server.requests['/model.gguf'] != 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await releaseInAnotherProcess('app.a', entry.id);
      expect(referenceFiles(model), isEmpty);
      final second = a
          .ensure(model, options: refresh)
          .then((_) => 'ok', onError: (_) => 'fail');
      while (referenceFiles(model).isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      gate.complete();

      expect(await Future.wait([first, second]), ['fail', 'fail']);
      expect(referenceFiles(model), isEmpty);
    });

    test('a failed call that cannot lock the store keeps its error', () async {
      final a = await open('app.a');
      final missing = single('/missing.gguf');
      final options = ModelLoadOptions(maxRetries: 0);
      final gate = Completer<void>();
      server.gates['/missing.gguf'] = gate.future;
      final lock = File(p.join(root.path, 'store.lock'));

      final failing = a.ensure(missing, options: options);
      while (server.requests['/missing.gguf'] == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Process.run('chmod', ['444', lock.path]);
      addTearDown(() => Process.run('chmod', ['644', lock.path]));
      gate.complete();

      await expectLater(failing, throwsA(isA<LlamaModelException>()));
      // Unable to put the reference back, the call leaves it to a release.
      expect(referenceFiles(missing), hasLength(1));
      await Process.run('chmod', ['644', lock.path]);
      await a.release(ModelStore.entryIdFor(missing));
      await expectLater(
        a.ensure(missing, options: options),
        throwsA(isA<LlamaModelException>()),
      );
      expect(referenceFiles(missing), isEmpty);
    }, skip: Platform.isWindows ? 'POSIX permissions' : false);

    test(
      'a failed call that cannot put back the reference keeps its error',
      () async {
        final a = await open('app.a');
        final model = single('/model.gguf');
        final entry = await a.ensure(model);
        final gate = Completer<void>();
        server
          ..gates['/model.gguf'] = gate.future
          ..failing.add('/model.gguf');
        final refs = p.join(root.path, 'entries', entry.id, 'refs');
        final initial = referenceContents(model);

        final failing = a.ensure(
          model,
          options: ModelLoadOptions(
            cachePolicy: ModelCachePolicy.refresh,
            maxRetries: 0,
          ),
        );
        while (referenceContents(model) == initial) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await Process.run('chmod', ['555', refs]);
        addTearDown(() => Process.run('chmod', ['755', refs]));
        gate.complete();

        await expectLater(failing, throwsA(isA<LlamaModelException>()));
        expect(referenceFiles(model), hasLength(1));
      },
      skip: Platform.isWindows ? 'POSIX permissions' : false,
    );

    test('a reference it cannot write does not outlive the call', () async {
      final a = await open('app.a');
      final model = single('/model.gguf');
      final entry = await a.ensure(model);
      final refs = p.join(root.path, 'entries', entry.id, 'refs');
      await Process.run('chmod', ['555', refs]);
      addTearDown(() => Process.run('chmod', ['755', refs]));

      await expectLater(a.ensure(model), throwsA(isA<FileSystemException>()));
      await Process.run('chmod', ['755', refs]);
      await releaseInAnotherProcess('app.a', entry.id);
      server.failing.add('/model.gguf');
      await expectLater(
        a.ensure(model, options: ModelLoadOptions(maxRetries: 0)),
        throwsA(isA<LlamaModelException>()),
      );

      expect(referenceFiles(model), isEmpty);
    }, skip: Platform.isWindows ? 'POSIX permissions' : false);

    test('overlapping failed calls of two apps settle separately', () async {
      final a = await open('app.a');
      final b = await open('app.b');
      final model = single('/model.gguf');
      await a.ensure(model);
      final gate = Completer<void>();
      server
        ..gates['/model.gguf'] = gate.future
        ..failing.add('/model.gguf');
      final refresh = ModelLoadOptions(
        cachePolicy: ModelCachePolicy.refresh,
        maxRetries: 0,
      );

      final calls = [
        for (final store in [a, b])
          store
              .ensure(model, options: refresh)
              .then<Object>((_) => 'ok', onError: (Object error) => error),
      ];
      // References are recorded in call order, so b's is the last.
      while (referenceFiles(model).length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      gate.complete();

      expect(await Future.wait(calls), [
        isA<LlamaModelException>(),
        isA<LlamaModelException>(),
      ]);
      expect((await a.entries()).single.references.map((r) => r.appId), [
        'app.a',
      ]);
    });

    test(
      'a success keeps the reference when an overlapping call fails later',
      () async {
        final a = await open('app.a');
        final model = single('/model.gguf');
        final firstGate = Completer<void>();
        final secondGate = Completer<void>();
        server.gates['/model.gguf'] = firstGate.future;

        final download = a.ensure(model);
        while (server.requests['/model.gguf'] == null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        server
          ..failing.add('/model.gguf')
          ..gates['/model.gguf'] = secondGate.future;
        final initial = referenceContents(model);
        final refresh = a
            .ensure(
              model,
              options: ModelLoadOptions(
                cachePolicy: ModelCachePolicy.refresh,
                maxRetries: 0,
              ),
            )
            .then((_) => 'ok', onError: (_) => 'fail');
        while (referenceContents(model) == initial) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        firstGate.complete();
        await download;
        secondGate.complete();

        expect(await refresh, 'fail');
        expect((await a.entries()).single.references.map((r) => r.appId), [
          'app.a',
        ]);
      },
    );

    test('a success before a release does not keep a later failure', () async {
      final a = await open('app.a');
      final model = single('/model.gguf');
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      server.gates['/model.gguf'] = firstGate.future;
      final refresh = ModelLoadOptions(
        cachePolicy: ModelCachePolicy.refresh,
        maxRetries: 0,
      );

      final download = a.ensure(model);
      while (server.requests['/model.gguf'] == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      server
        ..failing.add('/model.gguf')
        ..gates['/model.gguf'] = secondGate.future;
      final initial = referenceContents(model);
      final first = a
          .ensure(model, options: refresh)
          .then((_) => 'ok', onError: (_) => 'fail');
      while (referenceContents(model) == initial) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      firstGate.complete();
      final entry = await download;
      await expectLater(
        a.release(entry.id),
        throwsA(isA<ModelCacheEntryInUseException>()),
      );
      final second = a
          .ensure(model, options: refresh)
          .then((_) => 'ok', onError: (_) => 'fail');
      while (referenceFiles(model).isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      secondGate.complete();

      expect(await Future.wait([first, second]), ['fail', 'fail']);
      expect(referenceFiles(model), isEmpty);
    });

    test(
      'failed calls keep a reference another process records between them',
      () async {
        final a = await open('app.a');
        final model = single('/model.gguf');
        await DefaultModelDownloadManager(
          defaultCacheDirectory: p.join(a.directory, 'files'),
        ).ensureModel(model.source);
        final gate = Completer<void>();
        server
          ..gates['/model.gguf'] = gate.future
          ..failing.add('/model.gguf');
        final refresh = ModelLoadOptions(
          cachePolicy: ModelCachePolicy.refresh,
          maxRetries: 0,
        );

        final first = a
            .ensure(model, options: refresh)
            .then((_) => 'ok', onError: (_) => 'fail');
        while (server.requests['/model.gguf'] != 2) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final own = referenceContents(model);
        // Records its reference, then waits for the entry lock of the first
        // call's download.
        final other = await Process.start(_dartExecutable(), [
          'test/support/ensure_entry.dart',
          root.path,
          'app.a',
          server.url('/model.gguf').toString(),
        ]);
        addTearDown(other.kill);
        final errors = other.stderr.transform(utf8.decoder).join();
        while (referenceContents(model) == own) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final recorded = referenceContents(model);
        final second = a
            .ensure(model, options: refresh)
            .then((_) => 'ok', onError: (_) => 'fail');
        while (referenceContents(model) == recorded) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        gate.complete();

        expect(await Future.wait([first, second]), ['fail', 'fail']);
        expect(await other.exitCode, 0, reason: await errors);
        expect(referenceContents(model), recorded);
      },
    );

    test('a failed call keeps a reference another process rewrote', () async {
      final a = await open('app.a');
      final model = single('/model.gguf');
      final gate = Completer<void>();
      server.gates['/model.gguf'] = gate.future;
      server.failing.add('/model.gguf');

      final failing = a
          .ensure(model, options: ModelLoadOptions(maxRetries: 0))
          .then((_) => 'ok', onError: (_) => 'fail');
      while (server.requests['/model.gguf'] == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final reference = File(
        p.join(
          root.path,
          'entries',
          ModelStore.entryIdFor(model),
          'refs',
          referenceFiles(model).single,
        ),
      );
      final rewritten = jsonDecode(reference.readAsStringSync()) as Map
        ..['token'] = 'other-process';
      reference.writeAsStringSync(jsonEncode(rewritten));
      gate.complete();

      expect(await failing, 'fail');
      expect(
        jsonDecode(reference.readAsStringSync())['token'],
        'other-process',
      );
    });

    test('a release while a call is failing is not undone', () async {
      final a = await open('app.a');
      final model = single('/model.gguf');
      final entry = await a.ensure(model);
      final gate = Completer<void>();
      server.gates['/model.gguf'] = gate.future;

      final refresh = a
          .ensure(
            model,
            options: ModelLoadOptions(
              cachePolicy: ModelCachePolicy.refresh,
              maxRetries: 0,
            ),
          )
          .then((_) => 'ok', onError: (_) => 'fail');
      while (server.requests['/model.gguf'] != 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await expectLater(
        a.release(entry.id),
        throwsA(isA<ModelCacheEntryInUseException>()),
      );
      await server.close();
      gate.complete();

      expect(await refresh, 'fail');
      expect(referenceFiles(model), isEmpty);
    });

    test('a failed refresh keeps the reference the app already held', () async {
      final a = await open('app.a');
      final model = single('/model.gguf');
      final entry = await a.ensure(model);
      final firstUse = (await a.entries()).single.references.single.lastUsedAt;
      await server.close();

      await expectLater(
        a.ensure(
          model,
          options: ModelLoadOptions(
            cachePolicy: ModelCachePolicy.refresh,
            maxRetries: 0,
          ),
        ),
        throwsA(isA<LlamaModelException>()),
      );

      final kept = (await a.entries()).single.references.single;
      expect(kept.appId, 'app.a');
      expect(kept.lastUsedAt, firstUse);
      await (await open('app.b')).prune(maxBytes: 0);
      expect(File(entry.model.filePath).existsSync(), isTrue);
    });

    test(
      'keeps a reference a concurrent call of the same app rewrote',
      () async {
        final store = await open('app.a');

        final miss = store.ensure(
          pair,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
        );
        final download = store.ensure(pair);

        await expectLater(miss, throwsA(isA<LlamaException>()));
        await download;
        expect((await store.entries()).single.references.map((r) => r.appId), [
          'app.a',
        ]);
      },
    );

    test('rejects what the store cannot hold', () async {
      final store = await open('app.a');
      final local = File(p.join(root.path, 'local.gguf'))
        ..writeAsBytesSync(modelBytes);

      await expectLater(
        store.ensure(LlamaModel(ModelSource.path(local.path))),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await expectLater(
        store.ensure(
          pair,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.noCache),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await expectLater(
        store.ensure(
          pair,
          options: ModelLoadOptions(cacheDirectory: root.path),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await expectLater(
        store.ensure(pair, options: ModelLoadOptions(sha256: 'a' * 64)),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(server.requests, isEmpty);
      expect(Directory(p.join(root.path, 'entries')).listSync(), isEmpty);
    });

    test('never sends credentials to a second host', () async {
      final store = await open('app.a');
      final crossHost = LlamaModel(
        ModelSource.url(server.url('/model.gguf')),
        projector: ModelSource.url(
          server.url('/mmproj.gguf').replace(host: 'localhost'),
        ),
      );

      await expectLater(
        store.ensure(
          crossHost,
          options: ModelLoadOptions(bearerToken: 'secret-token'),
        ),
        throwsA(
          isA<LlamaArgumentException>().having(
            (e) => e.message,
            'message',
            isNot(contains('secret-token')),
          ),
        ),
      );
      expect(server.requests, isEmpty);
    });

    test('treats another port on the same host as another host', () async {
      final store = await open('app.a');
      final otherPort = LlamaModel(
        ModelSource.url(server.url('/model.gguf')),
        projector: ModelSource.url(
          server.url('/mmproj.gguf').replace(port: server.url('/').port + 1),
        ),
      );

      await expectLater(
        store.ensure(
          otherPort,
          options: ModelLoadOptions(bearerToken: 'secret-token'),
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(server.requests, isEmpty);
    });

    test('records the reference before the download starts', () async {
      final a = await open('app.a');
      final gate = Completer<void>();
      server.gates['/model.gguf'] = gate.future;
      final model = single('/model.gguf');

      final download = a.ensure(model);
      while (server.requests['/model.gguf'] == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final refs = Directory(
        p.join(root.path, 'entries', ModelStore.entryIdFor(model), 'refs'),
      );
      expect(refs.listSync().whereType<File>(), hasLength(1));
      final b = await open('app.b');
      await b.prune(maxBytes: 0);
      gate.complete();
      final entry = await download;

      await b.prune(maxBytes: 0);
      await expectLater(
        b.clear(),
        throwsA(isA<ModelCacheEntryInUseException>()),
      );
      expect(File(entry.model.filePath).existsSync(), isTrue);
    });

    test('repairs an entry file it cannot read', () async {
      final a = await open('app.a');
      final model = single('/model.gguf');
      final entry = await a.ensure(model);
      final entryFile = File(
        p.join(root.path, 'entries', entry.id, 'entry.json'),
      )..writeAsStringSync('{"id": "trunc');

      await expectLater(a.prune(maxBytes: 0), completion(isEmpty));
      expect(await a.entries(), isEmpty);
      await (await open('app.b')).ensure(model);

      expect(jsonDecode(entryFile.readAsStringSync())['cache_keys'], [
        model.source.cacheKey,
      ]);
      expect((await a.entries()).single.references, hasLength(2));
    });

    test('writes no source secrets to store metadata', () async {
      final signed = LlamaModel(
        ModelSource.url(
          server.url('/model.gguf', query: {'X-Amz-Signature': 'url-secret'}),
        ),
      );
      final store = await open('app.a');

      await store.ensure(
        signed,
        options: ModelLoadOptions(
          bearerToken: 'bearer-secret',
          headers: {'X-Api-Key': 'header-secret'},
        ),
      );

      expect(server.requestHeaders.single.value('x-api-key'), 'header-secret');
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (p.extension(file.path) == '.gguf') {
          continue;
        }
        final text = latin1.decode(file.readAsBytesSync());
        for (final secret in ['url-secret', 'bearer-secret', 'header-secret']) {
          expect(text, isNot(contains(secret)), reason: file.path);
        }
      }
    });
  });

  group('release', () {
    test('keeps files while another app references them', () async {
      final a = await open('app.a');
      final b = await open('app.b');
      final entry = await a.ensure(pair);
      await b.ensure(pair);

      await a.release(entry.id);

      expect(File(entry.model.filePath).existsSync(), isTrue);
      expect((await b.entries()).single.references.map((r) => r.appId), [
        'app.b',
      ]);

      await b.release(entry.id);

      expect(File(entry.model.filePath).existsSync(), isFalse);
      expect(File(entry.projector!.filePath).existsSync(), isFalse);
      expect(await b.entries(), isEmpty);
    });

    test('a file the OS refuses to delete stops nothing else', () async {
      final a = await open('app.a');
      final entry = await a.ensure(pair);
      final denied = p.dirname(entry.model.filePath);
      await Process.run('chmod', ['555', denied]);
      addTearDown(() => Process.run('chmod', ['755', denied]));

      await expectLater(
        a.release(entry.id),
        throwsA(isA<FileSystemException>()),
      );

      expect(File(entry.model.filePath).existsSync(), isTrue);
      expect(File(entry.projector!.filePath).existsSync(), isFalse);
      expect(referenceFiles(pair), isEmpty);
      expect(await a.prune(maxBytes: 0), isEmpty);
      expect(await a.prune(maxAge: Duration.zero), isEmpty);

      await Process.run('chmod', ['755', denied]);
      final again = await (await open('app.b')).ensure(single('/model.gguf'));
      expect(again.model.filePath, entry.model.filePath);
      expect(server.requests['/model.gguf'], 1);
      await (await open('app.b')).release(again.id);
      expect(File(entry.model.filePath).existsSync(), isFalse);
    }, skip: Platform.isWindows ? 'POSIX permissions' : false);

    test('keeps a projector another referenced entry shares', () async {
      final a = await open('app.a');
      final b = await open('app.b');
      final first = await a.ensure(pair);
      final second = await b.ensure(
        LlamaModel(
          ModelSource.url(server.url('/other.gguf')),
          projector: pair.projector,
        ),
      );

      await a.release(first.id);

      expect(File(first.model.filePath).existsSync(), isFalse);
      expect(File(second.projector!.filePath).existsSync(), isTrue);
      expect((await b.entries()).map((e) => e.id), [second.id]);
    });

    test('rejects an id that is not an entry id', () async {
      final a = await open('app.a');
      await a.ensure(single('/model.gguf'));
      final outside = File(p.join(root.path, 'outside', 'refs', 'x.json'))
        ..createSync(recursive: true);

      for (final id in ['../outside', '', 'A' * 64, 'a' * 63]) {
        await expectLater(
          a.release(id),
          throwsA(isA<LlamaArgumentException>()),
          reason: id,
        );
      }
      expect(outside.existsSync(), isTrue);
      expect(await storeFileNames(), ['model.gguf']);
    });

    test('a symbolic link to the store shares its lock', () async {
      final link = Link(p.join(root.path, 'link'));
      final real = Directory(p.join(root.path, 'real'))..createSync();
      await link.create(real.path);
      final viaReal = await ModelStore.open(directory: real.path, appId: 'a');
      final viaLink = await ModelStore.open(directory: link.path, appId: 'b');

      expect(viaLink.directory, viaReal.directory);
      final model = single('/model.gguf');
      final entry = await viaReal.ensure(model);
      await viaLink.ensure(model);
      await viaReal.release(entry.id);
      expect(File(entry.model.filePath).existsSync(), isTrue);
    });

    test('waits for a store lock another process holds', () async {
      final a = await open('app.a');
      final entry = await a.ensure(pair);
      final child = await Process.start(_dartExecutable(), [
        'test/support/hold_store_lock.dart',
        p.join(root.path, 'store.lock'),
      ]);
      addTearDown(child.kill);
      final output = child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      await output.firstWhere((line) => line == 'locked');

      var released = false;
      final release = a.release(entry.id).then((_) => released = true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(released, isFalse);
      expect(File(entry.model.filePath).existsSync(), isTrue);

      child.stdin.writeln('done');
      await child.stdin.flush();
      await release;
      expect(await child.exitCode, 0);
      expect(File(entry.model.filePath).existsSync(), isFalse);
    });
  });

  group('download manager contract', () {
    test('ensureModel records a single-file entry', () async {
      final store = await open('app.a');
      final model = single('/model.gguf');

      final file = await store.ensureModel(model.source);

      expect(await File(file.filePath).readAsBytes(), modelBytes);
      expect((await store.entries()).single.id, ModelStore.entryIdFor(model));
      expect(await store.get(model.source.cacheKey), isNotNull);
      expect((await store.list()).single.cacheKey, model.source.cacheKey);
    });

    test(
      'ensureModel passes local files through without a reference',
      () async {
        final store = await open('app.a');
        final local = File(p.join(root.path, 'local.gguf'))
          ..writeAsBytesSync(modelBytes);

        final file = await store.ensureModel(ModelSource.path(local.path));

        expect(file.filePath, local.path);
        expect(await store.entries(), isEmpty);
      },
    );

    test('rejects another cache directory', () async {
      final store = await open('app.a');

      final other = root.path;
      final calls = <String, Future<Object?> Function()>{
        'ensureModel': () => store.ensureModel(
          single('/model.gguf').source,
          options: ModelLoadOptions(cacheDirectory: other),
        ),
        'noCache ensureModel': () => store.ensureModel(
          single('/model.gguf').source,
          options: ModelLoadOptions(
            cachePolicy: ModelCachePolicy.noCache,
            cacheDirectory: other,
          ),
        ),
        'list': () => store.list(cacheDirectory: other),
        'get': () => store.get('key', cacheDirectory: other),
        'remove': () => store.remove('key', cacheDirectory: other),
        'clear': () => store.clear(cacheDirectory: other),
        'prune': () => store.prune(cacheDirectory: other),
      };
      for (final call in calls.entries) {
        await expectLater(
          call.value(),
          throwsA(isA<LlamaUnsupportedException>()),
          reason: call.key,
        );
      }
      expect(server.requests, isEmpty);
    });

    test('remove keeps a file another app references', () async {
      final a = await open('app.a');
      final b = await open('app.b');
      final model = single('/model.gguf');
      final file = await a.ensureModel(model.source);
      await b.ensureModel(model.source);

      await expectLater(
        a.remove(model.source.cacheKey),
        throwsA(
          isA<ModelCacheEntryInUseException>().having(
            (e) => e.entryDirectories,
            'entryDirectories',
            [p.dirname(file.filePath)],
          ),
        ),
      );
      expect(File(file.filePath).existsSync(), isTrue);
      expect((await a.entries()).single.references.map((r) => r.appId), [
        'app.b',
      ]);

      await b.remove(model.source.cacheKey);
      expect(File(file.filePath).existsSync(), isFalse);
    });

    test('clear removes only what no other app references', () async {
      final a = await open('app.a');
      final b = await open('app.b');
      await a.ensure(pair);
      final shared = await a.ensure(single('/other.gguf'));
      await b.ensure(single('/other.gguf'));

      await expectLater(
        a.clear(),
        throwsA(
          isA<ModelCacheEntryInUseException>().having(
            (e) => e.entryDirectories,
            'entryDirectories',
            [p.dirname(shared.model.filePath)],
          ),
        ),
      );

      expect(await storeFileNames(), ['other.gguf']);
      expect((await b.entries()).single.id, shared.id);
    });

    test('prune deletes only unreferenced files, oldest first', () async {
      final a = await open('app.a');
      final referenced = await a.ensure(single('/model.gguf'));
      final unreferenced = DefaultModelDownloadManager(
        defaultCacheDirectory: p.join(a.directory, 'files'),
      );
      await unreferenced.ensureModel(single('/other.gguf').source);
      await unreferenced.ensureModel(single('/mmproj.gguf').source);
      await age(referenced.model);
      await age((await a.get(single('/other.gguf').source.cacheKey))!);

      final byAge = await a.prune(maxAge: const Duration(days: 1));

      expect(byAge.map((e) => e.fileName), ['other.gguf']);
      expect(await storeFileNames(), ['mmproj.gguf', 'model.gguf']);

      final bySize = await a.prune(maxBytes: 0);

      expect(bySize.map((e) => e.fileName), ['mmproj.gguf']);
      expect(await storeFileNames(), ['model.gguf']);
    });

    test('prune drops file metadata whose file is gone', () async {
      final a = await open('app.a');
      final entry = await a.ensure(single('/model.gguf'));
      await a.release(entry.id);
      final stale = DefaultModelDownloadManager(
        defaultCacheDirectory: p.join(a.directory, 'files'),
      );
      final file = await stale.ensureModel(single('/other.gguf').source);
      File(file.filePath).deleteSync();

      final removed = await a.prune();

      expect(removed.map((e) => e.fileName), ['other.gguf']);
      expect(Directory(p.dirname(file.filePath)).existsSync(), isFalse);
    });

    test('prune leaves core cleanup it cannot do for a later prune', () async {
      final a = await open('app.a');
      final files = p.join(a.directory, 'files');
      final stale = await DefaultModelDownloadManager(
        defaultCacheDirectory: files,
      ).ensureModel(single('/other.gguf').source);
      File(stale.filePath).deleteSync();
      final metadata = File(p.join(p.dirname(stale.filePath), 'metadata.json'));
      final metadataBytes = metadata.readAsBytesSync();
      final realFiles = Directory(files);
      final systemIO = _SystemIO();
      var listings = 0;
      var completedInventories = 0;
      var failedListings = 0;
      addTearDown(() => Process.run('chmod', ['755', files]));

      try {
        final removed = await IOOverrides.runZoned(
          () => a.prune(),
          createDirectory: (path) {
            final directory = systemIO.createDirectory(path);
            if (!p.equals(p.normalize(p.absolute(path)), files)) {
              return directory;
            }
            return _AfterListDirectory(
              directory,
              onStart: () => listings++,
              onFailure: () => failedListings++,
              onComplete: () async {
                if (++completedInventories != 1) {
                  return;
                }
                // Revoke listing permission after store inventory, before the
                // core cleanup pass. Metadata must remain a regular file.
                expect(
                  (await Process.run('chmod', ['333', files])).exitCode,
                  0,
                );
                await expectLater(
                  realFiles.list().toList(),
                  throwsA(isA<FileSystemException>()),
                );
              },
            );
          },
        );

        expect(removed, isEmpty);
        expect(completedInventories, 1);
        expect(listings, 2);
        expect(failedListings, 1);
        expect(metadata.readAsBytesSync(), metadataBytes);
        expect(Directory(p.dirname(stale.filePath)).existsSync(), isTrue);
      } finally {
        expect((await Process.run('chmod', ['755', files])).exitCode, 0);
      }

      expect((await a.prune()).map((e) => e.fileName), ['other.gguf']);
      expect(Directory(p.dirname(stale.filePath)).existsSync(), isFalse);
    }, skip: Platform.isWindows ? 'POSIX permissions' : false);

    test('prune deletes leftover entries without references', () async {
      final a = await open('app.a');
      final entry = await a.ensure(pair);
      File(p.join(root.path, 'entries', entry.id, 'refs')).parent
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => p.dirname(file.path).endsWith('refs'))
          .forEach((file) => file.deleteSync());

      await a.prune();

      expect(
        Directory(p.join(root.path, 'entries', entry.id)).existsSync(),
        isFalse,
      );
      expect(await storeFileNames(), ['mmproj.gguf', 'model.gguf']);
    });

    test('an unreadable referenced entry protects every file', () async {
      final a = await open('app.a');
      await a.ensure(single('/other.gguf'));
      final entry = await a.ensure(single('/model.gguf'));
      final foreign = Directory(p.join(root.path, 'entries', 'foreign'));
      File(p.join(foreign.path, 'refs', 'x.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      File(p.join(foreign.path, 'entry.json')).writeAsStringSync('{"v":9}');

      await a.release(entry.id);
      expect(await storeFileNames(), ['model.gguf', 'other.gguf']);
      expect(await a.prune(maxBytes: 0), isEmpty);
      expect(await storeFileNames(), ['model.gguf', 'other.gguf']);
      await expectLater(
        a.clear(),
        throwsA(isA<ModelCacheEntryInUseException>()),
      );
      expect(await storeFileNames(), ['model.gguf', 'other.gguf']);
    });
  });

  test('entry ids stay stable across store versions', () {
    // Every app sharing a store derives the same id; changing it orphans
    // existing entries.
    final model = LlamaModel(
      ModelSource.parse('hf://owner/repo/model.gguf'),
      projector: ModelSource.parse('hf://owner/repo/mmproj.gguf'),
    );

    expect(
      ModelStore.entryIdFor(model),
      '292ebbecf6ab9efd5fa017606e35fd223d39fdce0fa1c489c9613884f8944820',
    );
  });

  group('open', () {
    test('rejects a blank app id', () async {
      await expectLater(
        ModelStore.open(directory: root.path, appId: ' '),
        throwsA(isA<LlamaArgumentException>()),
      );
    });

    test('rejects a directory whose lock cannot be taken', () async {
      Directory(p.join(root.path, 'store.lock')).createSync();

      await expectLater(
        open('app.a'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('rejects a directory it cannot write', () async {
      final file = File(p.join(root.path, 'not-a-directory'))
        ..writeAsStringSync('');

      await expectLater(
        ModelStore.open(directory: p.join(file.path, 'store'), appId: 'a'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  });
}

/// The `dart` executable of the SDK running these tests.
String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    return p.join(flutterRoot, 'bin', Platform.isWindows ? 'dart.bat' : 'dart');
  }
  return 'dart';
}

final class _SystemIO extends IOOverrides {}

class _AfterListDirectory implements Directory {
  _AfterListDirectory(
    this.directory, {
    required this.onStart,
    required this.onComplete,
    required this.onFailure,
  });

  final Directory directory;
  final void Function() onStart;
  final Future<void> Function() onComplete;
  final void Function() onFailure;

  @override
  String get path => directory.path;
  @override
  Directory get absolute => directory.absolute;
  @override
  Future<bool> exists() => directory.exists();
  @override
  Future<String> resolveSymbolicLinks() => directory.resolveSymbolicLinks();
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    onStart();
    try {
      await for (final entity in directory.list(
        recursive: recursive,
        followLinks: followLinks,
      )) {
        yield entity;
      }
    } on FileSystemException {
      onFailure();
      rethrow;
    }
    await onComplete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
