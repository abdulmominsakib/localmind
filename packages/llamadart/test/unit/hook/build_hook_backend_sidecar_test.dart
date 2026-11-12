@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:llamadart/src/hook/native_archive_digest.dart';
import 'package:llamadart/src/hook/native_release_manifest.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';

import '../../../hook/build.dart' as build_hook;
import '../../support/hook_core_version.dart';
import '../../support/native_bundle_cache.dart';
import '../../support/runtime_bundle_http_fixture.dart';

const _tag = 'v9.9.8';
const _coreArchive = 'llamadart-native-windows-x64-$_tag.tar.gz';
const _sidecarBundle = 'windows-x64-cuda12';
const _sidecarArchive = 'llamadart-native-$_sidecarBundle-$_tag.tar.gz';

const _coreLibraries = [
  'llamadart.dll',
  'llama.dll',
  'llama-common.dll',
  'mtmd.dll',
  'ggml.dll',
  'ggml-base.dll',
  'ggml-cpu.dll',
  'ggml-vulkan.dll',
];

const _cudaLibraries = [
  'ggml-cuda.dll',
  'cudart64_12.dll',
  'cublas64_12.dll',
  'cublasLt64_12.dll',
];

String _url(String asset) =>
    'https://github.com/leehack/llamadart-native/releases/download/$_tag/'
    '$asset';

final _sumsUrl = _url('SHA256SUMS');
final _manifestUrl = _url('assets.json');
final _coreUrl = _url(_coreArchive);
final _sidecarUrl = _url(_sidecarArchive);

void main() {
  // Each test builds in its own package root, so the hook's
  // `.dart_tool/llamadart/native_bundles_v2` cache never touches this checkout's.
  late Directory packageRoot;
  late Directory releaseCacheDir;

  setUp(() {
    packageRoot = Directory.systemTemp.createTempSync('sidecar-root-');
    File(path.join(packageRoot.path, 'pubspec.yaml')).writeAsStringSync(
      'name: llamadart\nversion: ${readCheckoutCoreVersion()}\n',
    );
    releaseCacheDir = Directory(_bundlesDir(packageRoot, _tag));
  });

  tearDown(() => packageRoot.deleteSync(recursive: true));

  Future<Map<String, String>> runHook(
    RuntimeBundleHttpFixture fixture, {
    String? tag = _tag,
    List<String>? backends,
    String? nativePath,
  }) => IOOverrides.runZoned(
    () =>
        _runHook(fixture, tag: tag, backends: backends, nativePath: nativePath),
    getCurrentDirectory: () => packageRoot,
  );

  final core = _archive('core', _coreLibraries);
  final sidecar = _archive('sidecar', _cudaLibraries);
  File absentRecord() =>
      File(path.join(releaseCacheDir.path, 'assets.json.absent'));

  Map<String, List<int>> release({
    Object? manifest,
    List<int>? sidecarBody,
    bool listSidecar = true,
  }) => {
    _sumsUrl: sha256SumsFor({
      _coreArchive: core,
      if (listSidecar) _sidecarArchive: sidecar,
    }).codeUnits,
    if (manifest != null) _manifestUrl: utf8.encode(jsonEncode(manifest)),
    _coreUrl: core,
    _sidecarUrl: sidecarBody ?? sidecar,
  };

  group('a contract 2 release', () {
    test('adds the CUDA sidecar when cuda is selected', () async {
      final fixture = RuntimeBundleHttpFixture(release(manifest: _manifest()));

      final libraries = await runHook(fixture, backends: ['cpu', 'cuda']);

      expect(fixture.requests, [
        _sumsUrl,
        _manifestUrl,
        _coreUrl,
        _sumsUrl,
        _sidecarUrl,
      ]);
      expect(libraries, containsPair('ggml-cuda.dll', 'sidecar-ggml-cuda.dll'));
      expect(
        libraries,
        containsPair('cublasLt64_12.dll', 'sidecar-cublasLt64_12.dll'),
      );
      expect(libraries, containsPair('ggml-cpu.dll', 'core-ggml-cpu.dll'));
      expect(libraries, isNot(contains('ggml-vulkan.dll')));
    });

    test('reuses the cached sidecar and manifest offline', () async {
      await runHook(
        RuntimeBundleHttpFixture(release(manifest: _manifest())),
        backends: ['cpu', 'cuda'],
      );
      final offline = RuntimeBundleHttpFixture.offline();

      final libraries = await runHook(offline, backends: ['cpu', 'cuda']);

      expect(offline.requests, isEmpty);
      expect(libraries, contains('ggml-cuda.dll'));
    });

    for (final damaged in ['ggml-cuda.dll', 'cudart64_12.dll']) {
      test('re-extracts a cached sidecar missing $damaged offline', () async {
        await runHook(
          RuntimeBundleHttpFixture(release(manifest: _manifest())),
          backends: ['cuda'],
        );
        File(
          path.join(releaseCacheDir.path, _sidecarBundle, 'extracted', damaged),
        ).deleteSync();
        final offline = RuntimeBundleHttpFixture.offline();

        final libraries = await runHook(offline, backends: ['cuda']);

        expect(offline.requests, isEmpty);
        expect(libraries, containsPair(damaged, 'sidecar-$damaged'));
      });
    }

    test('redownloads a cached sidecar missing its CUDA runtime', () async {
      await runHook(
        RuntimeBundleHttpFixture(release(manifest: _manifest())),
        backends: ['cuda'],
      );
      final sidecarCache = path.join(releaseCacheDir.path, _sidecarBundle);
      File(
        path.join(sidecarCache, 'extracted', 'cudart64_12.dll'),
      ).deleteSync();
      File(path.join(sidecarCache, _sidecarArchive)).deleteSync();
      final fixture = RuntimeBundleHttpFixture(release(manifest: _manifest()));

      final libraries = await runHook(fixture, backends: ['cuda']);

      expect(fixture.requests, [_sumsUrl, _sidecarUrl]);
      expect(
        libraries,
        containsPair('cudart64_12.dll', 'sidecar-cudart64_12.dll'),
      );
    });

    test('skips the sidecar unless cuda is selected', () async {
      final fixture = RuntimeBundleHttpFixture(release(manifest: _manifest()));

      final libraries = await runHook(fixture);

      expect(fixture.requests, [_sumsUrl, _manifestUrl, _coreUrl]);
      expect(libraries.keys, containsAll(['ggml-cpu.dll', 'ggml-vulkan.dll']));
      expect(libraries.keys.where((name) => name.contains('cu')), isEmpty);
    });

    test(
      'fails instead of falling back when it lists no CUDA sidecar',
      () async {
        final fixture = RuntimeBundleHttpFixture(
          release(manifest: _manifest(sidecars: false), listSidecar: false),
        );

        await expectLater(
          runHook(fixture, backends: ['cuda']),
          throwsA(
            isA<NativeHookContractException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('selects cuda for windows-x64'),
                contains('leehack/llamadart-native@$_tag (hook contract 2)'),
                contains('only as a sidecar archive'),
              ),
            ),
          ),
        );
        expect(fixture.requests, [_sumsUrl, _manifestUrl, _coreUrl]);
      },
    );

    test('rejects a sidecar that differs from SHA256SUMS', () async {
      final fixture = RuntimeBundleHttpFixture(
        release(
          manifest: _manifest(),
          sidecarBody: _archive('tampered', _cudaLibraries),
        ),
      );

      await expectLater(
        runHook(fixture, backends: ['cuda']),
        throwsA(
          isA<NativeArchiveDigestException>().having(
            (error) => error.message,
            'message',
            allOf(contains(_sidecarArchive), contains('was deleted')),
          ),
        ),
      );
    });

    test('rejects a sidecar without the backend module', () async {
      final missingModule = _archive('sidecar', _cudaLibraries.sublist(1));
      final fixture = RuntimeBundleHttpFixture({
        ...release(manifest: _manifest()),
        _sumsUrl: sha256SumsFor({
          _coreArchive: core,
          _sidecarArchive: missingModule,
        }).codeUnits,
        _sidecarUrl: missingModule,
      });

      await expectLater(
        runHook(fixture, backends: ['cuda']),
        throwsA(
          isA<NativeHookContractException>().having(
            (error) => error.message,
            'message',
            contains('holds no ggml-cuda module'),
          ),
        ),
      );
    });

    test('rejects a sidecar without the CUDA runtime', () async {
      final noRuntime = _archive('sidecar', _cudaLibraries.sublist(0, 1));
      final fixture = RuntimeBundleHttpFixture({
        ...release(manifest: _manifest()),
        _sumsUrl: sha256SumsFor({
          _coreArchive: core,
          _sidecarArchive: noRuntime,
        }).codeUnits,
        _sidecarUrl: noRuntime,
      });

      await expectLater(
        runHook(fixture, backends: ['cuda']),
        throwsA(
          isA<NativeHookContractException>().having(
            (error) => error.message,
            'message',
            contains('missing runtime dependencies'),
          ),
        ),
      );
    });

    test('does not download again a cached sidecar that matches SHA256SUMS '
        'but lacks the CUDA runtime', () async {
      final noRuntime = _archive('sidecar', _cudaLibraries.sublist(0, 1));
      Map<String, List<int>> incompleteRelease() => {
        ...release(manifest: _manifest()),
        _sumsUrl: sha256SumsFor({
          _coreArchive: core,
          _sidecarArchive: noRuntime,
        }).codeUnits,
        _sidecarUrl: noRuntime,
      };
      await expectLater(
        runHook(
          RuntimeBundleHttpFixture(incompleteRelease()),
          backends: ['cuda'],
        ),
        throwsA(isA<NativeHookContractException>()),
      );
      final fixture = RuntimeBundleHttpFixture(incompleteRelease());

      await expectLater(
        runHook(fixture, backends: ['cuda']),
        throwsA(
          isA<NativeHookContractException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('missing runtime dependencies'),
              contains('downloading it again would not help'),
              contains('remove cuda for windows-x64 from hooks.user_defines'),
            ),
          ),
        ),
      );
      // Only a fresh SHA256SUMS, which could list a republished archive.
      expect(fixture.requests, [_sumsUrl]);
    });

    test('downloads again a cached sidecar that a republished SHA256SUMS no '
        'longer lists', () async {
      final noRuntime = _archive('sidecar', _cudaLibraries.sublist(0, 1));
      await expectLater(
        runHook(
          RuntimeBundleHttpFixture({
            ...release(manifest: _manifest()),
            _sumsUrl: sha256SumsFor({
              _coreArchive: core,
              _sidecarArchive: noRuntime,
            }).codeUnits,
            _sidecarUrl: noRuntime,
          }),
          backends: ['cuda'],
        ),
        throwsA(isA<NativeHookContractException>()),
      );
      final fixture = RuntimeBundleHttpFixture(release(manifest: _manifest()));

      final libraries = await runHook(fixture, backends: ['cuda']);

      expect(fixture.requests, [_sumsUrl, _sidecarUrl]);
      expect(
        libraries,
        containsPair('cudart64_12.dll', 'sidecar-cudart64_12.dll'),
      );
    });
  });

  test('a cached core archive that matches SHA256SUMS but lacks runtime '
      'libraries is not downloaded again', () async {
    final incompleteCore = _archive('core', [
      ..._coreLibraries,
      'ggml-cuda.dll',
    ]);
    Map<String, List<int>> incompleteRelease() => {
      ...release(manifest: _manifest()),
      _sumsUrl: sha256SumsFor({
        _coreArchive: incompleteCore,
        _sidecarArchive: sidecar,
      }).codeUnits,
      _coreUrl: incompleteCore,
    };
    await expectLater(
      runHook(RuntimeBundleHttpFixture(incompleteRelease())),
      throwsA(
        isA<Exception>().having(
          (error) => '$error',
          'message',
          contains('missing runtime deps'),
        ),
      ),
    );
    final fixture = RuntimeBundleHttpFixture(incompleteRelease());

    await expectLater(
      runHook(fixture),
      throwsA(
        isA<Exception>().having(
          (error) => '$error',
          'message',
          contains('downloading it again would not help'),
        ),
      ),
    );
    expect(fixture.requests, [_sumsUrl]);
  });

  test(
    'a cached core archive that matches the cached SHA256SUMS but lacks '
    'runtime libraries does not ask to pre-seed SHA256SUMS offline',
    () async {
      final incompleteCore = _archive('core', [
        ..._coreLibraries,
        'ggml-cuda.dll',
      ]);
      final incompleteRelease = {
        ...release(manifest: _manifest()),
        _sumsUrl: sha256SumsFor({
          _coreArchive: incompleteCore,
          _sidecarArchive: sidecar,
        }).codeUnits,
        _coreUrl: incompleteCore,
      };
      await expectLater(
        runHook(RuntimeBundleHttpFixture(incompleteRelease)),
        throwsA(isA<Exception>()),
      );
      final offline = RuntimeBundleHttpFixture.offline();

      await expectLater(
        runHook(offline),
        throwsA(
          isA<NativeArchiveDigestException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('lists the cached archive'),
              isNot(contains('put that release')),
            ),
          ),
        ),
      );
    },
  );

  test('a sidecar may rely on CUDA runtime libraries the core ships', () async {
    final coreWithCudart = _archive('core', [
      ..._coreLibraries,
      'cudart64_12.dll',
    ]);
    final sidecarWithoutCudart = _archive('sidecar', [
      'ggml-cuda.dll',
      'cublas64_12.dll',
    ]);
    final fixture = RuntimeBundleHttpFixture({
      ...release(manifest: _manifest()),
      _sumsUrl: sha256SumsFor({
        _coreArchive: coreWithCudart,
        _sidecarArchive: sidecarWithoutCudart,
      }).codeUnits,
      _coreUrl: coreWithCudart,
      _sidecarUrl: sidecarWithoutCudart,
    });

    final libraries = await runHook(fixture, backends: ['cuda']);

    expect(libraries, containsPair('ggml-cuda.dll', 'sidecar-ggml-cuda.dll'));
    expect(libraries, containsPair('cudart64_12.dll', 'core-cudart64_12.dll'));
  });

  group('an unsupported hook contract', () {
    test('fails before the core archive is downloaded', () async {
      final fixture = RuntimeBundleHttpFixture(
        release(manifest: _manifest(contract: 3)),
      );

      await expectLater(
        runHook(fixture),
        throwsA(
          isA<NativeHookContractException>().having(
            (error) => error.message,
            'message',
            contains('requires native hook contract 3'),
          ),
        ),
      );
      expect(fixture.requests, [_sumsUrl, _manifestUrl]);
    });

    test('an unreachable assets.json fails before the core archive is '
        'downloaded', () async {
      final fixture = RuntimeBundleHttpFixture(
        release(manifest: _manifest()),
        unreachable: {_manifestUrl},
      );

      await expectLater(
        runHook(fixture, backends: ['cuda']),
        throwsA(
          isA<NativeHookContractException>().having(
            (error) => error.message,
            'message',
            contains('Could not download $_manifestUrl'),
          ),
        ),
      );
      expect(fixture.requests, [_sumsUrl, _manifestUrl]);
      expect(absentRecord().existsSync(), isFalse);
    });

    test('fails a CUDA build over a cached core bundle', () async {
      await runHook(RuntimeBundleHttpFixture(release(manifest: _manifest())));
      await File(path.join(releaseCacheDir.path, 'assets.json')).delete();
      final fixture = RuntimeBundleHttpFixture(
        release(manifest: _manifest(contract: 3)),
      );

      await expectLater(
        runHook(fixture, backends: ['cuda']),
        throwsA(isA<NativeHookContractException>()),
      );
      expect(fixture.requests, [_manifestUrl]);
    });
  });

  group('a release without assets.json', () {
    test('keeps CUDA from the core bundle', () async {
      final legacyCore = _archive('legacy', [
        ..._coreLibraries,
        ..._cudaLibraries,
      ]);
      final fixture = RuntimeBundleHttpFixture({
        _sumsUrl: sha256SumsFor({_coreArchive: legacyCore}).codeUnits,
        _coreUrl: legacyCore,
      });

      final libraries = await runHook(fixture, backends: ['cuda']);

      expect(fixture.requests, [_sumsUrl, _manifestUrl, _coreUrl]);
      expect(libraries, containsPair('ggml-cuda.dll', 'legacy-ggml-cuda.dll'));
    });

    test('still warns and falls back when CUDA is missing', () async {
      final fixture = RuntimeBundleHttpFixture({
        _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
        _coreUrl: core,
      });

      final libraries = await runHook(fixture, backends: ['cuda']);

      expect(fixture.requests, [_sumsUrl, _manifestUrl, _coreUrl]);
      expect(libraries, isNot(contains('ggml-cuda.dll')));
      expect(libraries, contains('ggml-vulkan.dll'));

      final offline = RuntimeBundleHttpFixture.offline();
      expect(await runHook(offline, backends: ['cuda']), libraries);
      expect(offline.requests, isEmpty);
    });

    test('loses to an assets.json seeded after it was recorded', () async {
      await runHook(
        RuntimeBundleHttpFixture({
          _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
          _coreUrl: core,
        }),
      );
      expect(absentRecord().existsSync(), isTrue);
      File(
        path.join(releaseCacheDir.path, 'assets.json'),
      ).writeAsStringSync(jsonEncode(_manifest()));
      final fixture = RuntimeBundleHttpFixture(release(manifest: _manifest()));

      final libraries = await runHook(fixture, backends: ['cuda']);

      expect(fixture.requests, [_sumsUrl, _sidecarUrl]);
      expect(libraries, containsPair('ggml-cuda.dll', 'sidecar-ggml-cuda.dll'));
    });

    test('is re-checked once a day old and dropped when the release '
        'publishes assets.json', () async {
      await runHook(
        RuntimeBundleHttpFixture({
          _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
          _coreUrl: core,
        }),
      );
      absentRecord().setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 1, minutes: 1)),
      );
      final fixture = RuntimeBundleHttpFixture(release(manifest: _manifest()));

      final libraries = await runHook(fixture, backends: ['cuda']);

      expect(fixture.requests, [_manifestUrl, _sumsUrl, _sidecarUrl]);
      expect(libraries, containsPair('ggml-cuda.dll', 'sidecar-ggml-cuda.dll'));
      expect(absentRecord().existsSync(), isFalse);
    });

    test('ages by the hook clock, not the machine clock', () async {
      final legacyRelease = {
        _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
        _coreUrl: core,
      };
      await runHook(RuntimeBundleHttpFixture(legacyRelease));
      final recorded = DateTime.now().subtract(const Duration(days: 2));
      absentRecord().setLastModifiedSync(recorded);
      final fixture = RuntimeBundleHttpFixture(legacyRelease);

      await build_hook.withClockForTesting(
        () => recorded.add(const Duration(hours: 1)),
        () => runHook(fixture, backends: ['cuda']),
      );

      expect(fixture.requests, isNot(contains(_manifestUrl)));
    });

    test('is renewed when a re-check finds no assets.json again, and kept '
        'and renewed when the re-check fails', () async {
      final legacyRelease = {
        _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
        _coreUrl: core,
      };
      await runHook(RuntimeBundleHttpFixture(legacyRelease));
      final old = DateTime.now().subtract(const Duration(days: 2));
      absentRecord().setLastModifiedSync(old);

      final renewing = RuntimeBundleHttpFixture(legacyRelease);
      await runHook(renewing, backends: ['cuda']);
      expect(renewing.requests, [_manifestUrl]);
      expect(absentRecord().lastModifiedSync().isAfter(old), isTrue);

      absentRecord().setLastModifiedSync(old);
      final offline = RuntimeBundleHttpFixture.offline();
      final libraries = await runHook(offline, backends: ['cuda']);
      expect(offline.requests, [_manifestUrl]);
      expect(libraries, isNot(contains('ggml-cuda.dll')));
      expect(absentRecord().lastModifiedSync().isAfter(old), isTrue);

      final nextOffline = RuntimeBundleHttpFixture.offline();
      await runHook(nextOffline, backends: ['cuda']);
      expect(nextOffline.requests, isEmpty);
    });

    test('is stamped with the hook clock, not the file system clock, when a '
        'future-dated record is re-checked and the release still has no '
        'assets.json', () async {
      final legacyRelease = {
        _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
        _coreUrl: core,
      };
      await runHook(RuntimeBundleHttpFixture(legacyRelease));
      absentRecord().setLastModifiedSync(
        DateTime.now().add(const Duration(days: 30)),
      );
      final hookNow = DateTime.now().subtract(const Duration(hours: 3));

      await build_hook.withClockForTesting(
        () => hookNow,
        () => runHook(
          RuntimeBundleHttpFixture(legacyRelease),
          backends: ['cuda'],
        ),
      );

      expect(
        absentRecord().lastModifiedSync().difference(hookNow).abs(),
        lessThan(const Duration(seconds: 5)),
      );
    });

    test('is re-checked when dated in the future', () async {
      await runHook(
        RuntimeBundleHttpFixture({
          _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
          _coreUrl: core,
        }),
      );
      absentRecord().setLastModifiedSync(
        DateTime.now().add(const Duration(days: 30)),
      );
      final fixture = RuntimeBundleHttpFixture(release(manifest: _manifest()));

      final libraries = await runHook(fixture, backends: ['cuda']);

      expect(fixture.requests, [_manifestUrl, _sumsUrl, _sidecarUrl]);
      expect(libraries, containsPair('ggml-cuda.dll', 'sidecar-ggml-cuda.dll'));
      expect(absentRecord().existsSync(), isFalse);
    });

    test('is kept and renewed with a warning when the re-check returns a '
        'page that is not JSON', () async {
      final legacyRelease = {
        _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
        _coreUrl: core,
      };
      await runHook(RuntimeBundleHttpFixture(legacyRelease));
      final old = DateTime.now().subtract(const Duration(days: 2));
      absentRecord().setLastModifiedSync(old);
      final fixture = RuntimeBundleHttpFixture({
        ...legacyRelease,
        _manifestUrl: utf8.encode('<html>Blocked by the network</html>'),
      });
      final warnings = _captureWarnings();

      final libraries = await runHook(fixture, backends: ['cuda']);

      expect(fixture.requests, [_manifestUrl]);
      expect(libraries, isNot(contains('ggml-cuda.dll')));
      expect(warnings, contains(contains('is not JSON')));
      expect(absentRecord().lastModifiedSync().isAfter(old), isTrue);
    });

    final undecidableBodies = <String, List<int>>{
      'truncated JSON': utf8.encode('{"hook_contract_version": 2, "artif'),
      'an empty body': const <int>[],
      'bytes that are not UTF-8': const <int>[0xff, 0xfe, 0x7b],
      'JSON that is not a manifest': utf8.encode('{"error":"blocked"}'),
      'a truncated JSON array': utf8.encode('[{"hook_contract_version": 2'),
      'a JSON array that is not a manifest': utf8.encode('[]'),
    };
    undecidableBodies.forEach((name, body) {
      test('fails instead of keeping the record when the re-check returns '
          '$name', () async {
        final legacyRelease = {
          _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
          _coreUrl: core,
        };
        await runHook(RuntimeBundleHttpFixture(legacyRelease));
        final old = DateTime.now().subtract(const Duration(days: 2));
        absentRecord().setLastModifiedSync(old);
        final fixture = RuntimeBundleHttpFixture({
          ...legacyRelease,
          _manifestUrl: body,
        });

        await expectLater(
          runHook(fixture, backends: ['cuda']),
          throwsA(
            isA<NativeHookContractException>().having(
              (error) => error.message,
              'message',
              name.contains('not a manifest')
                  ? anything
                  : allOf(contains('Retry the build'), contains('assets.json')),
            ),
          ),
        );
        expect(
          File(path.join(releaseCacheDir.path, 'assets.json')).existsSync(),
          isFalse,
        );
        expect(absentRecord().lastModifiedSync().isAtSameMomentAs(old), isTrue);
      });
    });

    test('does not hide a body that is not JSON without a record', () async {
      final fixture = RuntimeBundleHttpFixture({
        _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
        _coreUrl: core,
        _manifestUrl: utf8.encode('<html>Blocked by the network</html>'),
      });

      await expectLater(
        runHook(fixture, backends: ['cuda']),
        throwsA(isA<NativeHookContractException>()),
      );
      expect(absentRecord().existsSync(), isFalse);
    });

    test('still lets a core download proceed when its re-check '
        'fails', () async {
      final legacyRelease = {
        _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
        _coreUrl: core,
      };
      await runHook(RuntimeBundleHttpFixture(legacyRelease));
      absentRecord().setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 2)),
      );
      Directory(
        path.join(releaseCacheDir.path, 'windows-x64'),
      ).deleteSync(recursive: true);
      final fixture = RuntimeBundleHttpFixture(
        legacyRelease,
        unreachable: {_manifestUrl},
      );

      final libraries = await runHook(fixture);

      expect(fixture.requests, [_sumsUrl, _manifestUrl, _coreUrl]);
      expect(libraries, containsPair('ggml-cpu.dll', 'core-ggml-cpu.dll'));
      expect(absentRecord().existsSync(), isTrue);
    });
  });

  test('a CUDA build over a cached core falls back when assets.json is '
      'unreachable', () async {
    await runHook(
      RuntimeBundleHttpFixture({
        ...release(manifest: _manifest(contract: 1, sidecars: false)),
        _sumsUrl: sha256SumsFor({_coreArchive: core}).codeUnits,
      }),
    );
    await File(path.join(releaseCacheDir.path, 'assets.json')).delete();
    final offline = RuntimeBundleHttpFixture.offline();
    final warnings = _captureWarnings();

    final libraries = await runHook(offline, backends: ['cpu', 'cuda']);

    expect(offline.requests, [_manifestUrl]);
    expect(libraries, isNot(contains('ggml-cuda.dll')));
    expect(libraries, containsPair('ggml-cpu.dll', 'core-ggml-cpu.dll'));
    expect(
      warnings,
      contains(
        allOf(
          contains('Could not download $_manifestUrl to find the cuda sidecar'),
          contains('building windows-x64 without it'),
        ),
      ),
    );
    expect(absentRecord().existsSync(), isFalse);
  });

  group('a CUDA build whose assets.json is unreachable', () {
    setUp(() async {
      await runHook(
        RuntimeBundleHttpFixture(release(manifest: _manifest())),
        backends: ['cuda'],
      );
      await File(path.join(releaseCacheDir.path, 'assets.json')).delete();
    });

    test('uses the cached sidecar', () async {
      final offline = RuntimeBundleHttpFixture.offline();

      final libraries = await runHook(offline, backends: ['cuda']);

      expect(offline.requests, [_manifestUrl]);
      expect(libraries, containsPair('ggml-cuda.dll', 'sidecar-ggml-cuda.dll'));
    });

    test('extracts a cached sidecar archive the cached SHA256SUMS '
        'lists', () async {
      Directory(
        path.join(releaseCacheDir.path, _sidecarBundle, 'extracted'),
      ).deleteSync(recursive: true);
      final offline = RuntimeBundleHttpFixture.offline();

      final libraries = await runHook(offline, backends: ['cuda']);

      expect(offline.requests, [_manifestUrl]);
      expect(
        libraries,
        containsPair('cudart64_12.dll', 'sidecar-cudart64_12.dll'),
      );
    });

    test('leaves out a cached sidecar it cannot complete offline', () async {
      final sidecarCache = path.join(releaseCacheDir.path, _sidecarBundle);
      File(
        path.join(sidecarCache, 'extracted', 'cudart64_12.dll'),
      ).deleteSync();
      File(path.join(sidecarCache, _sidecarArchive)).deleteSync();
      final offline = RuntimeBundleHttpFixture.offline();
      final warnings = _captureWarnings();

      final libraries = await runHook(offline, backends: ['cuda']);

      expect(libraries, isNot(contains('ggml-cuda.dll')));
      expect(libraries, containsPair('ggml-cpu.dll', 'core-ggml-cpu.dll'));
      expect(warnings, contains(contains('building windows-x64 without it')));
    });
  });

  group('the pinned release', () {
    late Directory coreDir;
    late Directory sidecarDir;
    final sidecarSpec = llamaCppBackendSidecarSpecs.singleWhere(
      (spec) => spec.bundle == 'windows-x64' && spec.backend == 'cuda',
    );
    final sidecarArchive =
        'llamadart-native-${sidecarSpec.archive}-$llamaCppTag.tar.gz';
    final sidecarUrl =
        'https://github.com/leehack/llamadart-native/releases/download/'
        '$llamaCppTag/$sidecarArchive';

    setUp(() async {
      final bundlesDir = _bundlesDir(packageRoot, llamaCppTag);
      coreDir = Directory(path.join(bundlesDir, 'windows-x64'));
      sidecarDir = Directory(path.join(bundlesDir, sidecarSpec.archive));
      // The pinned core archive cannot be faked, so seed its extraction.
      await _seedExtracted(coreDir, 'pinned', _coreLibraries);
    });

    test('downloads the CUDA sidecar only when cuda is selected', () async {
      final fixture = RuntimeBundleHttpFixture({
        sidecarUrl: _archive('tampered', _cudaLibraries),
      });

      final libraries = await runHook(fixture, tag: null);
      expect(fixture.requests, isEmpty);
      expect(libraries, containsPair('ggml-cpu.dll', 'pinned-ggml-cpu.dll'));

      await expectLater(
        runHook(fixture, tag: null, backends: ['cuda']),
        throwsA(
          isA<NativeArchiveDigestException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains(sidecarArchive),
              contains(sidecarSpec.sha256),
              contains('was deleted and not used'),
            ),
          ),
        ),
      );
      expect(fixture.requests, [sidecarUrl]);
    });

    test('reuses an extracted CUDA sidecar offline', () async {
      await _seedExtracted(sidecarDir, 'pinned', _cudaLibraries);
      final fixture = RuntimeBundleHttpFixture.offline();

      final libraries = await runHook(
        fixture,
        tag: null,
        backends: ['cpu', 'cuda'],
      );

      expect(fixture.requests, isEmpty);
      expect(libraries, containsPair('ggml-cuda.dll', 'pinned-ggml-cuda.dll'));
      expect(libraries, contains('cudart64_12.dll'));
    });

    test('redownloads an extracted CUDA sidecar missing its runtime', () async {
      await _seedExtracted(sidecarDir, 'pinned', _cudaLibraries.sublist(0, 2));
      final fixture = RuntimeBundleHttpFixture({
        sidecarUrl: _archive('tampered', _cudaLibraries),
      });

      await expectLater(
        runHook(fixture, tag: null, backends: ['cuda']),
        throwsA(isA<NativeArchiveDigestException>()),
      );
      expect(fixture.requests, [sidecarUrl]);
    });
  });

  test('a local native path bundle needs no manifest or sidecar', () async {
    Future<Map<String, String>> build(List<String> libraries) async {
      final local = Directory.systemTemp.createTempSync('sidecar-local-');
      addTearDown(() => local.delete(recursive: true));
      for (final library in libraries) {
        File(
          path.join(local.path, library),
        ).writeAsStringSync('local-$library');
      }
      final fixture = RuntimeBundleHttpFixture.offline();
      final emitted = await runHook(
        fixture,
        backends: ['cuda'],
        nativePath: local.path,
      );
      expect(fixture.requests, isEmpty);
      return emitted;
    }

    expect(
      await build([..._coreLibraries, ..._cudaLibraries]),
      containsPair('ggml-cuda.dll', 'local-ggml-cuda.dll'),
    );
    expect(await build(_coreLibraries), isNot(contains('ggml-cuda.dll')));
  });
}

/// Messages the hook logs at warning level from now until the test ends.
List<String> _captureWarnings() {
  final warnings = <String>[];
  final subscription = Logger.root.onRecord
      .where((record) => record.level == Level.WARNING)
      .listen((record) => warnings.add(record.message));
  addTearDown(subscription.cancel);
  return warnings;
}

Map<String, Object?> _manifest({int contract = 2, bool sidecars = true}) => {
  'tag': _tag,
  'native_release_tag': _tag,
  'hook_contract_version': contract,
  'artifacts': [
    {
      'module': 'core',
      'platform': 'windows',
      'arch': 'x64',
      'backend': 'core',
      'file': _coreArchive,
    },
    if (sidecars)
      {
        'module': 'backend-cuda12',
        'platform': 'windows',
        'arch': 'x64',
        'backend': 'cuda',
        'file': _sidecarArchive,
      },
  ],
};

/// Runs the hook for Windows x64 against release [tag], or the pinned release
/// when it is `null`, with every download
/// served by [fixture], and returns the emitted libraries' contents by file
/// name.
Future<Map<String, String>> _runHook(
  RuntimeBundleHttpFixture fixture, {
  String? tag = _tag,
  List<String>? backends,
  String? nativePath,
}) async {
  final libraries = <String, String>{};
  await build_hook.withRuntimeBundleHttpClientForTesting(
    fixture.createClient,
    () => testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.windows,
      targetArchitecture: Architecture.x64,
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'llamadart_native_runtimes': ['llama_cpp'],
            'llamadart_native_tag': ?tag,
            if (backends != null)
              'llamadart_native_backends': {
                'platforms': {'windows-x64': backends},
              },
            'llamadart_native_path': ?nativePath,
          },
          basePath: Directory.current.uri,
        ),
      ),
      check: (_, output) {
        for (final asset
            in output.assets.encodedAssets
                .where((asset) => asset.isCodeAsset)
                .map((asset) => asset.asCodeAsset)) {
          final file = File.fromUri(asset.file!);
          libraries[path.basename(file.path)] = file.readAsStringSync();
        }
      },
    ),
  );
  return libraries;
}

String _bundlesDir(Directory packageRoot, String tag) => path.join(
  packageRoot.path,
  '.dart_tool',
  'llamadart',
  'native_bundles_v2',
  tag,
);

/// Seeds the `extracted/` cache of [bundleDir] with libraries holding
/// `<label>-<library>`, beside the archive and marker the hook would leave.
Future<void> _seedExtracted(
  Directory bundleDir,
  String label,
  List<String> libraries,
) async {
  final extracted = Directory(path.join(bundleDir.path, 'extracted'))
    ..createSync(recursive: true);
  for (final library in libraries) {
    File(
      path.join(extracted.path, library),
    ).writeAsStringSync('$label-$library');
  }
  await markExtractedBundle(extracted);
}

/// A `.tar.gz` bundle whose libraries hold `<label>-<library>`.
List<int> _archive(String label, List<String> libraries) {
  final archive = Archive();
  for (final library in libraries) {
    final content = '$label-$library'.codeUnits;
    archive.addFile(ArchiveFile(library, content.length, content));
  }
  return GZipEncoder().encode(TarEncoder().encode(archive));
}
