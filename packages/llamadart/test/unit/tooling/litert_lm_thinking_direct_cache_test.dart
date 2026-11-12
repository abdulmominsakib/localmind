@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

import '../../support/litert_lm_thinking_direct_cache.dart';

final class _UnwritableProbe implements File {
  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => throw const FileSystemException('Fixture denied writable probe.');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory scratch;
  setUp(() {
    scratch = Directory.systemTemp.createTempSync('thinking_cache_');
  });
  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test(
    'cache is private, absolute and writable while parent owns its lifetime',
    () {
      final sentinel = File('${scratch.path}/existing')
        ..writeAsStringSync('preserve');
      final cache = createThinkingDirectCache(scratch);
      final other = createThinkingDirectCache(scratch);
      expect(
        cache.path,
        startsWith(
          '${scratch.resolveSymbolicLinksSync()}${Platform.pathSeparator}direct-cache-',
        ),
      );
      expect(cache.isAbsolute, isTrue);
      expect(cache.path, isNot(other.path));
      expect(
        cache.listSync(),
        isEmpty,
        reason: 'The writable probe is removed.',
      );
      File('${cache.path}/native-artifact').writeAsStringSync('cache');
      expect(sentinel.readAsStringSync(), 'preserve');
      scratch.deleteSync(recursive: true);
      expect(cache.existsSync(), isFalse);
      expect(other.existsSync(), isFalse);
    },
  );
  test(
    'missing scratch or file scratch refuses without creating outside roots',
    () {
      final missing = Directory('${scratch.path}/missing');
      expect(
        () => createThinkingDirectCache(missing),
        throwsA(isA<FileSystemException>()),
      );
      expect(missing.existsSync(), isFalse);
      final file = File('${scratch.path}/file')..writeAsStringSync('preserve');
      expect(
        () => createThinkingDirectCache(Directory(file.path)),
        throwsA(isA<FileSystemException>()),
      );
      expect(file.readAsStringSync(), 'preserve');
    },
  );
  test(
    'failed writable probe refuses and removes only its new unowned cache',
    () {
      final sentinel = File('${scratch.path}/existing')
        ..writeAsStringSync('preserve');
      expect(
        () => IOOverrides.runZoned(
          () => createThinkingDirectCache(scratch),
          createFile: (_) => _UnwritableProbe(),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(scratch.listSync().map((f) => f.path), [sentinel.path]);
      expect(sentinel.readAsStringSync(), 'preserve');
    },
  );
  test(
    'real direct initialization rejects absent cache, then admits and retains prepared cache',
    () async {
      final libraryPath =
          '${scratch.path}/cache.${Platform.isMacOS ? 'dylib' : 'so'}';
      final compiled = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        'test/fixtures/litert_lm/c_api_v1_thinking_cache.c',
        '-o',
        libraryPath,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      final library = DynamicLibrary.open(libraryPath);
      int checked() => library.lookupFunction<Int Function(), int Function()>(
        'fixture_cache_checks',
      )();
      int exists() => library.lookupFunction<Int Function(), int Function()>(
        'fixture_cache_exists',
      )();
      final missingClient = LiteRtLmV1RuntimeClient(library);
      addTearDown(missingClient.dispose);
      await expectLater(
        missingClient.initialize(
          modelPath: '/fixture/model.litertlm',
          backend: 'cpu',
          numberOfThreads: 2,
          cacheDir: '${scratch.path}/direct-cache',
          speculativeDecoding: false,
        ),
        throwsA(
          isA<LiteRtLmEngineCreateError>().having(
            (e) => e.toString(),
            'native cache rejection',
            contains('INVALID_ARGUMENT (3)'),
          ),
        ),
      );
      expect(checked(), 1);
      expect(exists(), 0);
      missingClient.dispose();
      final cache = createThinkingDirectCache(scratch);
      final client = LiteRtLmV1RuntimeClient(library);
      addTearDown(client.dispose);
      await client.initialize(
        modelPath: '/fixture/model.litertlm',
        backend: 'cpu',
        numberOfThreads: 2,
        cacheDir: cache.path,
        speculativeDecoding: false,
      );
      expect(checked(), 2);
      expect(exists(), 1);
      expect(cache.existsSync(), isTrue);
      File('${cache.path}/cache-entry').writeAsStringSync('retained');
      client.dispose();
      expect(
        cache.existsSync(),
        isTrue,
        reason: 'Native disposal does not take parent scratch ownership.',
      );
      expect(File('${cache.path}/cache-entry').readAsStringSync(), 'retained');
      scratch.deleteSync(recursive: true);
      expect(cache.existsSync(), isFalse);
    },
  );
}
