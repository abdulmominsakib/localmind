@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../tool/litert_lm_library_smoke.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('litert_library_smoke_');
    for (final name in liteRtLmRequiredLibrariesForAbi(Abi.windowsX64)) {
      File(path.join(directory.path, name)).writeAsStringSync('fixture');
    }
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'Windows smoke retries an earlier DLL after a later dependency loads',
    () {
      final calls = <String>[];
      final inventory = liteRtLmCompanionLibrariesForAbi(Abi.windowsX64);
      final dependent = inventory.first;
      final dependency = inventory.last;
      var dependencyLoaded = false;
      final opened = openLiteRtLmSmokeLibrary(
        directory: directory.path,
        abi: Abi.windowsX64,
        openLibrary: (library) {
          final name = path.basename(library);
          calls.add(name);
          if (name == dependent && !dependencyLoaded) {
            throw ArgumentError('missing dependency: $dependency');
          }
          if (name == dependency) dependencyLoaded = true;
          return DynamicLibrary.process();
        },
      );
      expect(calls.last, 'LiteRtLm.dll');
      expect(calls.where((name) => name == dependent), hasLength(2));
      expect(opened.companions, hasLength(inventory.length));
    },
  );

  test('Windows smoke requires the DXC pair without opening it', () {
    final calls = <String>[];
    openLiteRtLmSmokeLibrary(
      directory: directory.path,
      abi: Abi.windowsX64,
      openLibrary: (library) {
        calls.add(path.basename(library));
        return DynamicLibrary.process();
      },
    );
    expect(calls, isNot(anyElement(isIn(['dxcompiler.dll', 'dxil.dll']))));
    expect(calls, [
      ...liteRtLmCompanionLibrariesForAbi(Abi.windowsX64),
      'LiteRtLm.dll',
    ]);

    File(path.join(directory.path, 'dxil.dll')).deleteSync();
    expect(
      () => openLiteRtLmSmokeLibrary(
        directory: directory.path,
        abi: Abi.windowsX64,
        openLibrary: (_) => fail('must validate inventory first'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('dxil.dll'),
        ),
      ),
    );
  });

  test('missing required DLL fails before opening any libraries', () {
    File(path.join(directory.path, 'libwebgpu_dawn.dll')).deleteSync();
    expect(
      () => openLiteRtLmSmokeLibrary(
        directory: directory.path,
        abi: Abi.windowsX64,
        openLibrary: (_) => fail('must validate inventory first'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('libwebgpu_dawn.dll'),
        ),
      ),
    );
  });

  test('smoke inventory selection admits only reviewed release tags', () {
    expect(liteRtLmSmokeUsesCApiV1('v0.19.0'), isTrue);
    expect(liteRtLmSmokeUsesCApiV1('v0.19.1'), isTrue);
    expect(liteRtLmSmokeUsesCApiV1('v0.19.1-1'), isTrue);
    expect(liteRtLmSmokeUsesCApiV1('v0.19.1-2'), isTrue);
    expect(liteRtLmSmokeUsesCApiV1('v0.19.1-3'), isTrue);
    expect(liteRtLmSmokeUsesCApiV1('v0.19.1-4'), isTrue);
    expect(liteRtLmSmokeUsesCApiV1('v0.18.1-4'), isFalse);
    for (final tag in ['v0.19.0-1', 'v0.19.2', 'v0.20.0', 'g0123456789ab']) {
      expect(
        () => liteRtLmSmokeUsesCApiV1(tag),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('no reviewed C API inventory for $tag'),
          ),
        ),
      );
    }
  });

  for (final (tag, abi) in [
    ('v0.19.1-2', Abi.linuxX64),
    ('v0.19.1-2', Abi.macosArm64),
    ('v0.19.1-2', Abi.windowsX64),
    ('v0.19.1-3', Abi.macosArm64),
    ('v0.19.1-4', Abi.macosArm64),
    ('v0.18.1-4', Abi.linuxX64),
    ('v0.18.1-4', Abi.macosArm64),
    ('v0.18.1-4', Abi.windowsX64),
  ]) {
    final cApiV1 = liteRtLmSmokeUsesCApiV1(tag);
    final required = liteRtLmRequiredLibrariesForAbi(abi, cApiV1: cApiV1);
    test('$tag $abi smoke opens its complete reviewed inventory', () {
      final runtimeDir = Directory(path.join(directory.path, 'runtime'))
        ..createSync();
      for (final name in required) {
        File(path.join(runtimeDir.path, name)).writeAsStringSync('fixture');
      }
      final calls = <String>[];
      final opened = openLiteRtLmSmokeLibrary(
        directory: runtimeDir.path,
        abi: abi,
        cApiV1: cApiV1,
        openLibrary: (library) {
          calls.add(path.basename(library));
          return DynamicLibrary.process();
        },
      );
      final primary = liteRtLmPrimaryLibraryForAbi(abi)!;
      final nonPreloaded = liteRtLmNonPreloadedLibrariesForAbi(abi);
      expect(
        calls,
        unorderedEquals(required.where((name) => !nonPreloaded.contains(name))),
      );
      expect(calls.last, primary);
      expect(opened.companions, hasLength(calls.length - 1));
      expect(calls, isNot(anyElement(isIn(nonPreloaded))));
      if (cApiV1) {
        expect(calls, isNot(anyElement(contains('TopK'))));
      } else {
        expect(calls, anyElement(contains('TopKWebGpuSampler')));
      }
    });

    for (final missing in required) {
      test('$tag $abi refuses missing $missing before any library opens', () {
        final runtimeDir = Directory(path.join(directory.path, 'runtime'))
          ..createSync();
        for (final name in required.where((name) => name != missing)) {
          File(path.join(runtimeDir.path, name)).writeAsStringSync('fixture');
        }
        expect(
          () => openLiteRtLmSmokeLibrary(
            directory: runtimeDir.path,
            abi: abi,
            cApiV1: cApiV1,
            openLibrary: (_) =>
                fail('must validate every required member first'),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains(
                'Required LiteRT-LM smoke library is missing: '
                '${runtimeDir.path}/$missing',
              ),
            ),
          ),
        );
      });
    }
  }

  test('an unresolved DLL dependency still fails the smoke', () {
    final failure = ArgumentError('missing external dependency');
    expect(
      () => openLiteRtLmSmokeLibrary(
        directory: directory.path,
        abi: Abi.windowsX64,
        openLibrary: (_) => throw failure,
      ),
      throwsA(same(failure)),
    );
  });

  group('in-process LiteRT marker', () {
    final skip = Platform.isWindows ? 'compiles fixtures with cc' : null;
    final libraries = <String, DynamicLibrary>{};
    late Directory fixtures;

    setUpAll(() {
      if (skip != null) return;
      fixtures = Directory.systemTemp.createTempSync('litert_marker_');
      for (final (name, defines) in [
        ('absent', ['-DSMOKE_SYMBOLS']),
        ('zero', ['-DSMOKE_SYMBOLS', '-DIN_PROCESS_LITERT_ABI=0']),
        ('one', ['-DSMOKE_SYMBOLS', '-DIN_PROCESS_LITERT_ABI=1']),
      ]) {
        final output = path.join(
          fixtures.path,
          '$name.${Platform.isMacOS ? 'dylib' : 'so'}',
        );
        final result = Process.runSync('cc', [
          '-shared',
          '-fPIC',
          ...defines,
          'test/fixtures/litert_lm/c_api_version.c',
          '-o',
          output,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        libraries[name] = DynamicLibrary.open(output);
      }
    });

    tearDownAll(() {
      if (skip == null) fixtures.deleteSync(recursive: true);
    });

    test('desktop runtimes must export the marker with value 1', () {
      for (final abi in [Abi.linuxX64, Abi.linuxArm64, Abi.windowsX64]) {
        requireInProcessLiteRtMarker(libraries['one']!, abi);
        for (final name in ['absent', 'zero']) {
          expect(
            () => requireInProcessLiteRtMarker(libraries[name]!, abi),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains('litert_lm_native_in_process_litert_abi_version'),
              ),
            ),
          );
        }
      }
    }, skip: skip);

    Map<String, Object?> runSmoke(String fixture, Abi abi) =>
        runLiteRtLmLibrarySmoke(
          abi: abi,
          directory: null,
          releaseTag: 'v0.19.1-4',
          openLibrary: (_) => libraries[fixture]!,
        );

    test('the smoke run enforces the marker and reports its value', () {
      for (final abi in [Abi.linuxX64, Abi.windowsX64]) {
        expect(runSmoke('one', abi)['inProcessLiteRtAbi'], 1);
        for (final name in ['absent', 'zero']) {
          expect(() => runSmoke(name, abi), throwsStateError);
        }
      }
    }, skip: skip);

    test('the smoke run reports no marker where it is not required', () {
      expect(runSmoke('absent', Abi.macosArm64)['inProcessLiteRtAbi'], isNull);
    }, skip: skip);

    test('Apple and Android runtimes are not required to export it', () {
      requireInProcessLiteRtMarker(libraries['absent']!, Abi.macosArm64);
      requireInProcessLiteRtMarker(libraries['absent']!, Abi.androidArm64);
    }, skip: skip);
  });
}
