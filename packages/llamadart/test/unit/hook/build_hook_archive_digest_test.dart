@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:llamadart/src/hook/native_archive_digest.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';

import '../../../hook/build.dart' as build_hook;
import '../../support/hook_project_root.dart';
import '../../support/runtime_bundle_http_fixture.dart';

const _bundle = 'linux-arm64';
const _overrideTag = 'v9.9.9';
const _forkRepository = 'digest-test/fork';
const _llamaLibraries = [
  'libllamadart.so',
  'libmtmd.so',
  'libllama.so',
  'libllama-common.so',
  'libggml.so',
  'libggml-base.so',
  'libggml-cpu.so',
];

const _windowsLibraries = [
  'llamadart-windows-x64.dll',
  'llama-windows-x64.dll',
  'ggml-windows-x64.dll',
  'ggml-base-windows-x64.dll',
  'ggml-cpu-windows-x64.dll',
];

/// A Windows bundle with a CUDA module but no CUDA runtime, which the hook
/// treats as incomplete.
const _windowsCudaLibraries = [
  ..._windowsLibraries,
  'ggml-cuda-windows-x64.dll',
];

void main() {
  final project = HookProjectRoot.create();
  final nativeBundlesDir = project.resolve(
    path.join('.dart_tool', 'llamadart', 'native_bundles_v2'),
  );
  final defaultCacheDir = Directory(
    path.join(nativeBundlesDir, llamaCppTag, _bundle),
  );
  final overrideCacheDir = Directory(
    path.join(nativeBundlesDir, _overrideTag, _bundle),
  );
  final windowsOverrideCacheDir = Directory(
    path.join(nativeBundlesDir, _overrideTag, 'windows-x64'),
  );
  final forkCacheDir = Directory(
    path.joinAll([
      nativeBundlesDir,
      'github',
      ..._forkRepository.split('/'),
      llamaCppTag,
      _bundle,
    ]),
  );
  final stableDiffusionCacheDir = project.resolve(
    path.join(
      '.dart_tool',
      'llamadart',
      'stable_diffusion',
      stableDiffusionVersion,
    ),
  );
  final stableDiffusionArchiveName =
      'stable-diffusion-native-runtime-$_bundle-$stableDiffusionReleaseTag'
      '.tar.gz';
  final stableDiffusionArchive = File(
    path.join(stableDiffusionCacheDir, stableDiffusionArchiveName),
  );
  final stableDiffusionBundleDir = Directory(
    path.join(stableDiffusionCacheDir, _bundle),
  );
  final liteRtLmCacheDir = project.resolve(
    path.join('.dart_tool', 'llamadart', 'litert_lm', liteRtLmVersion),
  );
  final liteRtLmArchiveName =
      'litert-lm-native-runtime-$_bundle-$liteRtLmReleaseTag.tar.gz';
  final liteRtLmArchive = File(
    path.join(liteRtLmCacheDir, liteRtLmArchiveName),
  );
  final liteRtLmBundleDir = Directory(
    path.join(liteRtLmCacheDir, 'linux', 'arm64'),
  );
  final touched = <FileSystemEntity>[
    defaultCacheDir,
    overrideCacheDir,
    windowsOverrideCacheDir,
    forkCacheDir,
    // Where the hook records that a release publishes no assets.json.
    for (final releaseDir in [overrideCacheDir, forkCacheDir])
      File(path.join(releaseDir.parent.path, 'assets.json.absent')),
    stableDiffusionArchive,
    stableDiffusionBundleDir,
    liteRtLmArchive,
    liteRtLmBundleDir,
  ];

  String archiveName(String tag) => 'llamadart-native-$_bundle-$tag.tar.gz';
  String releaseUrl(String repository, String tag, String asset) =>
      'https://github.com/$repository/releases/download/$tag/$asset';
  final defaultArchiveUrl = releaseUrl(
    'leehack/llamadart-native',
    llamaCppTag,
    archiveName(llamaCppTag),
  );
  final overrideArchiveUrl = releaseUrl(
    'leehack/llamadart-native',
    _overrideTag,
    archiveName(_overrideTag),
  );
  final overrideSumsUrl = releaseUrl(
    'leehack/llamadart-native',
    _overrideTag,
    'SHA256SUMS',
  );
  // These fixtures publish no assets.json, which reads as hook contract 1.
  final overrideManifestUrl = releaseUrl(
    'leehack/llamadart-native',
    _overrideTag,
    'assets.json',
  );

  setUp(() async {
    for (final entity in touched) {
      if (entity.existsSync()) {
        await entity.delete(recursive: true);
      }
    }
  });

  tearDownAll(project.delete);

  test(
    'an explicit compatible tag downloads into v2 without reusing legacy',
    () async {
      const tag = 'v0.8.0-2';
      final legacy = Directory(
        project.resolve(
          path.join('.dart_tool', 'llamadart', 'native_bundles', tag, _bundle),
        ),
      )..createSync(recursive: true);
      addTearDown(() => legacy.deleteSync(recursive: true));
      final legacyBytes = _archive('legacy');
      final legacyArchive = File(path.join(legacy.path, archiveName(tag)))
        ..writeAsBytesSync(legacyBytes);
      final archive = _archive('compatible');
      final fixture = RuntimeBundleHttpFixture({
        releaseUrl(_forkRepository, tag, 'SHA256SUMS'): sha256SumsFor({
          archiveName(tag): archive,
        }).codeUnits,
        releaseUrl(_forkRepository, tag, archiveName(tag)): archive,
      });

      final libraries = await _runHook(
        project,
        fixture,
        tag: tag,
        repository: _forkRepository,
        check: () {},
      );

      expect(libraries['libllamadart.so'], 'compatible-libllamadart.so');
      expect(
        fixture.requests,
        contains(releaseUrl(_forkRepository, tag, archiveName(tag))),
      );
      expect(legacyArchive.readAsBytesSync(), legacyBytes);
      expect(
        File(
          path.joinAll([
            nativeBundlesDir,
            'github',
            ..._forkRepository.split('/'),
            tag,
            _bundle,
            archiveName(tag),
          ]),
        ),
        _exists,
      );
    },
  );

  group('llama.cpp pinned release', () {
    test('rejects a downloaded archive that differs from its pin', () async {
      final fixture = RuntimeBundleHttpFixture({
        defaultArchiveUrl: _archive('tampered'),
      });
      var emitted = false;

      await expectLater(
        _runHook(project, fixture, check: () => emitted = true),
        throwsA(
          isA<NativeArchiveDigestException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains(archiveName(llamaCppTag)),
              contains(llamaCppBundleSha256[_bundle]),
              contains('was deleted and not used'),
            ),
          ),
        ),
      );
      expect(fixture.requests, [defaultArchiveUrl]);
      expect(emitted, isFalse);
      expect(
        File(path.join(defaultCacheDir.path, archiveName(llamaCppTag))),
        isNot(_exists),
      );
      expect(
        Directory(path.join(defaultCacheDir.path, 'extracted')),
        isNot(_exists),
      );
    });

    test('redownloads a cached archive that differs from its pin', () async {
      final cached = File(
        path.join(defaultCacheDir.path, archiveName(llamaCppTag)),
      );
      await cached.parent.create(recursive: true);
      await cached.writeAsBytes(_archive('cached-tampered'));
      final fixture = RuntimeBundleHttpFixture({
        defaultArchiveUrl: _archive('downloaded-tampered'),
      });

      final log = await _captureLog(() async {
        await expectLater(
          _runHook(project, fixture),
          throwsA(isA<NativeArchiveDigestException>()),
        );
      });

      expect(
        log,
        contains(
          stringContainsInOrder([
            'Cached native bundle archive',
            cached.path,
            llamaCppBundleSha256[_bundle]!,
            'redownloading',
          ]),
        ),
      );
      expect(fixture.requests, [defaultArchiveUrl]);
      expect(cached, isNot(_exists));
      expect(
        Directory(path.join(defaultCacheDir.path, 'extracted')),
        isNot(_exists),
      );
    });
  });

  test('the pinned release ignores a cached SHA256SUMS', () async {
    final tampered = _archive('tampered');
    final cached = File(
      path.join(defaultCacheDir.path, archiveName(llamaCppTag)),
    );
    await cached.parent.create(recursive: true);
    await cached.writeAsBytes(tampered);
    await File(
      path.join(defaultCacheDir.path, 'SHA256SUMS'),
    ).writeAsString(sha256SumsFor({archiveName(llamaCppTag): tampered}));
    final fixture = RuntimeBundleHttpFixture({defaultArchiveUrl: tampered});

    await expectLater(
      _runHook(project, fixture),
      throwsA(
        isA<NativeArchiveDigestException>().having(
          (error) => error.message,
          'message',
          contains(llamaCppBundleSha256[_bundle]),
        ),
      ),
    );
    expect(fixture.requests, [defaultArchiveUrl]);
    expect(
      Directory(path.join(defaultCacheDir.path, 'extracted')),
      isNot(_exists),
    );
  });

  group('llama.cpp tag override', () {
    test('verifies the download against the release SHA256SUMS', () async {
      final archive = _archive('valid');
      final fixture = RuntimeBundleHttpFixture({
        overrideSumsUrl: sha256SumsFor({
          archiveName(_overrideTag): archive,
        }).codeUnits,
        overrideArchiveUrl: archive,
      });

      final libraries = await _runHook(
        project,
        fixture,
        tag: _overrideTag,
        check: () {},
      );

      expect(fixture.requests, [
        overrideSumsUrl,
        overrideManifestUrl,
        overrideArchiveUrl,
      ]);
      expect(libraries['libllamadart.so'], 'valid-libllamadart.so');
      expect(
        File(path.join(overrideCacheDir.path, archiveName(_overrideTag))),
        _exists,
      );
    });

    test('reuses a cached archive that matches SHA256SUMS', () async {
      final archive = _archive('cached-valid');
      final cached = File(
        path.join(overrideCacheDir.path, archiveName(_overrideTag)),
      );
      await cached.parent.create(recursive: true);
      await cached.writeAsBytes(archive);
      final fixture = RuntimeBundleHttpFixture({
        overrideSumsUrl: sha256SumsFor({
          archiveName(_overrideTag): archive,
        }).codeUnits,
      });

      final libraries = await _runHook(
        project,
        fixture,
        tag: _overrideTag,
        check: () {},
      );

      expect(fixture.requests, [overrideSumsUrl]);
      expect(libraries['libllamadart.so'], 'cached-valid-libllamadart.so');
    });

    test(
      'replaces a cached archive that differs from SHA256SUMS before use',
      () async {
        final archive = _archive('valid');
        final cached = File(
          path.join(overrideCacheDir.path, archiveName(_overrideTag)),
        );
        await cached.parent.create(recursive: true);
        await cached.writeAsBytes(_archive('cached-tampered'));
        final fixture = RuntimeBundleHttpFixture({
          overrideSumsUrl: sha256SumsFor({
            archiveName(_overrideTag): archive,
          }).codeUnits,
          overrideArchiveUrl: archive,
        });

        late Map<String, String> libraries;
        final log = await _captureLog(() async {
          libraries = await _runHook(
            project,
            fixture,
            tag: _overrideTag,
            check: () {},
          );
        });

        expect(fixture.requests, [
          overrideSumsUrl,
          overrideManifestUrl,
          overrideArchiveUrl,
        ]);
        expect(libraries['libllamadart.so'], 'valid-libllamadart.so');
        expect(
          log,
          contains(
            stringContainsInOrder([
              cached.path,
              'SHA256SUMS expects',
              'redownloading',
            ]),
          ),
        );
      },
    );

    test('rejects a download that differs from SHA256SUMS', () async {
      final fixture = RuntimeBundleHttpFixture({
        overrideSumsUrl: sha256SumsFor({
          archiveName(_overrideTag): _archive('published'),
        }).codeUnits,
        overrideArchiveUrl: _archive('tampered'),
      });

      await expectLater(
        _runHook(project, fixture, tag: _overrideTag),
        throwsA(
          isA<NativeArchiveDigestException>().having(
            (error) => error.message,
            'message',
            contains('leehack/llamadart-native@$_overrideTag SHA256SUMS'),
          ),
        ),
      );
      expect(
        File(path.join(overrideCacheDir.path, archiveName(_overrideTag))),
        isNot(_exists),
      );
    });

    test(
      'fails before downloading when the release has no SHA256SUMS',
      () async {
        final fixture = RuntimeBundleHttpFixture({
          overrideArchiveUrl: _archive('unverifiable'),
        });

        await expectLater(
          _runHook(project, fixture, tag: _overrideTag),
          throwsA(
            isA<NativeArchiveDigestException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('publishes no SHA256SUMS'),
                contains('llamadart_native_path'),
              ),
            ),
          ),
        );
        expect(fixture.requests, [overrideSumsUrl]);
      },
    );

    test(
      'fails before downloading when SHA256SUMS omits the archive',
      () async {
        final fixture = RuntimeBundleHttpFixture({
          overrideSumsUrl: sha256SumsFor({
            'llamadart-native-linux-x64-$_overrideTag.tar.gz': _archive(
              'other',
            ),
          }).codeUnits,
          overrideArchiveUrl: _archive('unverifiable'),
        });

        await expectLater(
          _runHook(project, fixture, tag: _overrideTag),
          throwsA(
            isA<NativeArchiveDigestException>().having(
              (error) => error.message,
              'message',
              contains('lists no SHA-256 for ${archiveName(_overrideTag)}'),
            ),
          ),
        );
        expect(fixture.requests, [overrideSumsUrl]);
        expect(overrideCacheDir.listSync(), isEmpty);
      },
    );
  });

  group('llama.cpp tag override offline', () {
    final cachedArchive = File(
      path.join(overrideCacheDir.path, archiveName(_overrideTag)),
    );
    final cachedSums = File(path.join(overrideCacheDir.path, 'SHA256SUMS'));
    final extractedDir = Directory(
      path.join(overrideCacheDir.path, 'extracted'),
    );

    Future<void> seed({
      required List<int> archive,
      Map<String, List<int>>? sumsFor,
      String? sums,
    }) async {
      await overrideCacheDir.create(recursive: true);
      await cachedArchive.writeAsBytes(archive);
      final sumsText =
          sums ?? (sumsFor == null ? null : sha256SumsFor(sumsFor));
      if (sumsText != null) {
        await cachedSums.writeAsString(sumsText);
      }
    }

    test(
      'extracts a pre-seeded archive verified by a pre-seeded SHA256SUMS',
      () async {
        final archive = _archive('seeded');
        await seed(
          archive: archive,
          sumsFor: {archiveName(_overrideTag): archive},
        );
        final fixture = RuntimeBundleHttpFixture.offline();

        final libraries = await _runHook(
          project,
          fixture,
          tag: _overrideTag,
          check: () {},
        );

        expect(fixture.requests, isEmpty);
        expect(libraries['libllamadart.so'], 'seeded-libllamadart.so');
      },
    );

    test('keeps the fetched SHA256SUMS for a later offline build', () async {
      final archive = _archive('valid');
      final online = RuntimeBundleHttpFixture({
        overrideSumsUrl: sha256SumsFor({
          archiveName(_overrideTag): archive,
        }).codeUnits,
        overrideArchiveUrl: archive,
      });
      await _runHook(project, online, tag: _overrideTag, check: () {});
      expect(
        await cachedSums.readAsString(),
        sha256SumsFor({archiveName(_overrideTag): archive}),
      );

      await extractedDir.delete(recursive: true);
      final offline = RuntimeBundleHttpFixture.offline();
      final libraries = await _runHook(
        project,
        offline,
        tag: _overrideTag,
        check: () {},
      );

      expect(offline.requests, isEmpty);
      expect(libraries['libllamadart.so'], 'valid-libllamadart.so');
    });

    test(
      'fails with a typed error naming the pre-seed path without SHA256SUMS',
      () async {
        await seed(archive: _archive('seeded'));
        final fixture = RuntimeBundleHttpFixture.offline();

        await expectLater(
          _runHook(project, fixture, tag: _overrideTag),
          throwsA(
            isA<NativeArchiveDigestException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains(overrideSumsUrl),
                contains('OfflineFixtureException'),
                contains(cachedSums.path),
                contains('llamadart_native_path'),
              ),
            ),
          ),
        );
        expect(fixture.requests, [overrideSumsUrl]);
        expect(cachedArchive, _exists);
        expect(extractedDir, isNot(_exists));
      },
    );

    test(
      'rejects a pre-seeded archive that differs from the cached SHA256SUMS',
      () async {
        await seed(
          archive: _archive('tampered'),
          sumsFor: {archiveName(_overrideTag): _archive('published')},
        );
        final fixture = RuntimeBundleHttpFixture.offline();

        await expectLater(
          _runHook(project, fixture, tag: _overrideTag),
          throwsA(isA<NativeArchiveDigestException>()),
        );
        expect(fixture.requests, [overrideSumsUrl]);
        expect(cachedArchive, _exists);
        expect(extractedDir, isNot(_exists));
      },
    );

    test(
      'reuses a cached archive the release lists when the cached list is stale',
      () async {
        final archive = _archive('cached-valid');
        await seed(
          archive: archive,
          sumsFor: {archiveName(_overrideTag): _archive('older')},
        );
        final sums = sha256SumsFor({archiveName(_overrideTag): archive});
        final fixture = RuntimeBundleHttpFixture({
          overrideSumsUrl: sums.codeUnits,
        });

        final libraries = await _runHook(
          project,
          fixture,
          tag: _overrideTag,
          check: () {},
        );

        expect(fixture.requests, [overrideSumsUrl]);
        expect(libraries['libllamadart.so'], 'cached-valid-libllamadart.so');
        expect(await cachedSums.readAsString(), sums);
      },
    );

    test(
      'verifies a download against the fetched SHA256SUMS, not the cache',
      () async {
        final evil = _archive('evil');
        await seed(
          archive: _archive('stale'),
          sumsFor: {archiveName(_overrideTag): evil},
        );
        final fixture = RuntimeBundleHttpFixture({
          overrideSumsUrl: sha256SumsFor({
            archiveName(_overrideTag): _archive('published'),
          }).codeUnits,
          overrideArchiveUrl: evil,
        });

        await expectLater(
          _runHook(project, fixture, tag: _overrideTag),
          throwsA(
            isA<NativeArchiveDigestException>().having(
              (error) => error.message,
              'message',
              contains('was deleted and not used'),
            ),
          ),
        );
        expect(fixture.requests, [
          overrideSumsUrl,
          overrideManifestUrl,
          overrideArchiveUrl,
        ]);
        expect(extractedDir, isNot(_exists));
      },
    );

    test(
      'refreshes a cached SHA256SUMS that is not UTF-8 from the release',
      () async {
        final archive = _archive('cached-valid');
        await seed(archive: archive);
        final sums = sha256SumsFor({archiveName(_overrideTag): archive});
        await cachedSums.writeAsBytes(_utf16le(sums));
        final fixture = RuntimeBundleHttpFixture({
          overrideSumsUrl: sums.codeUnits,
        });

        final libraries = await _runHook(
          project,
          fixture,
          tag: _overrideTag,
          check: () {},
        );

        expect(fixture.requests, [overrideSumsUrl]);
        expect(libraries['libllamadart.so'], 'cached-valid-libllamadart.so');
        expect(await cachedSums.readAsString(), sums);
      },
    );

    test(
      'names why a cached SHA256SUMS was rejected when it cannot refetch',
      () async {
        final archive = _archive('seeded');
        await seed(archive: archive);
        await cachedSums.writeAsBytes(
          _utf16le(sha256SumsFor({archiveName(_overrideTag): archive})),
        );
        final fixture = RuntimeBundleHttpFixture.offline();

        await expectLater(
          _runHook(project, fixture, tag: _overrideTag),
          throwsA(
            isA<NativeArchiveDigestException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('The cached SHA256SUMS was not used'),
                contains('is not UTF-8 text'),
                contains(cachedSums.path),
              ),
            ),
          ),
        );
        expect(extractedDir, isNot(_exists));
      },
    );

    test('accepts a cached SHA256SUMS with a BOM and uppercase hex', () async {
      final archive = _archive('seeded');
      await seed(
        archive: archive,
        sums:
            '\uFEFF${sha256.convert(archive).toString().toUpperCase()}  '
            '${archiveName(_overrideTag)}\n',
      );
      final fixture = RuntimeBundleHttpFixture.offline();

      final libraries = await _runHook(
        project,
        fixture,
        tag: _overrideTag,
        check: () {},
      );

      expect(fixture.requests, isEmpty);
      expect(libraries['libllamadart.so'], 'seeded-libllamadart.so');
    });

    test(
      'builds when a directory occupies the cached SHA256SUMS path',
      () async {
        final archive = _archive('cached-valid');
        await seed(archive: archive);
        await Directory(cachedSums.path).create();
        final fixture = RuntimeBundleHttpFixture({
          overrideSumsUrl: sha256SumsFor({
            archiveName(_overrideTag): archive,
          }).codeUnits,
        });

        final libraries = await _runHook(
          project,
          fixture,
          tag: _overrideTag,
          check: () {},
        );

        expect(fixture.requests, [overrideSumsUrl]);
        expect(libraries['libllamadart.so'], 'cached-valid-libllamadart.so');
      },
    );

    test('fetches a fresh SHA256SUMS before replacing an incomplete cached '
        'archive', () async {
      final windowsArchiveName =
          'llamadart-native-windows-x64-$_overrideTag.tar.gz';
      final stale = _archive('stale', libraries: _windowsCudaLibraries);
      final complete = _archive('valid', libraries: _windowsLibraries);
      await windowsOverrideCacheDir.create(recursive: true);
      await File(
        path.join(windowsOverrideCacheDir.path, windowsArchiveName),
      ).writeAsBytes(stale);
      await File(
        path.join(windowsOverrideCacheDir.path, 'SHA256SUMS'),
      ).writeAsString(sha256SumsFor({windowsArchiveName: stale}));
      final archiveUrl = releaseUrl(
        'leehack/llamadart-native',
        _overrideTag,
        windowsArchiveName,
      );
      final fixture = RuntimeBundleHttpFixture({
        overrideSumsUrl: sha256SumsFor({
          windowsArchiveName: complete,
        }).codeUnits,
        archiveUrl: complete,
      });

      final libraries = await _runHook(
        project,
        fixture,
        tag: _overrideTag,
        targetOS: OS.windows,
        targetArchitecture: Architecture.x64,
        check: () {},
      );

      expect(fixture.requests, [
        overrideSumsUrl,
        overrideManifestUrl,
        archiveUrl,
      ]);
      expect(
        libraries['llamadart-windows-x64.dll'],
        'valid-llamadart-windows-x64.dll',
      );
    });

    test('refreshes a malformed cached SHA256SUMS from the release', () async {
      final archive = _archive('cached-valid');
      await seed(archive: archive, sums: 'not a checksum line\n');
      final sums = sha256SumsFor({archiveName(_overrideTag): archive});
      final fixture = RuntimeBundleHttpFixture({
        overrideSumsUrl: sums.codeUnits,
      });

      final libraries = await _runHook(
        project,
        fixture,
        tag: _overrideTag,
        check: () {},
      );

      expect(fixture.requests, [overrideSumsUrl]);
      expect(libraries['libllamadart.so'], 'cached-valid-libllamadart.so');
      expect(await cachedSums.readAsString(), sums);
    });
  });

  group('a cached extraction', () {
    final cachedArchive = File(
      path.join(overrideCacheDir.path, archiveName(_overrideTag)),
    );
    final extractedDir = Directory(
      path.join(overrideCacheDir.path, 'extracted'),
    );
    final marker = File('${extractedDir.path}.json');
    final archive = _archive('valid');
    final sums = sha256SumsFor({archiveName(_overrideTag): archive});

    Future<Map<String, String>> buildOffline({List<String>? log}) async {
      final offline = RuntimeBundleHttpFixture.offline();
      late Map<String, String> libraries;
      final lines = await _captureLog(() async {
        libraries = await _runHook(
          project,
          offline,
          tag: _overrideTag,
          check: () {},
        );
      });
      log?.addAll(lines);
      expect(offline.requests, isEmpty);
      return libraries;
    }

    Future<void> buildOnline() => _runHook(
      project,
      RuntimeBundleHttpFixture({
        overrideSumsUrl: sums.codeUnits,
        overrideArchiveUrl: archive,
      }),
      tag: _overrideTag,
      check: () {},
    );

    /// A cache an older hook left: the archive and an extraction of it,
    /// here with other contents, and no marker.
    Future<void> seedLegacy({required bool withSums}) async {
      await overrideCacheDir.create(recursive: true);
      await cachedArchive.writeAsBytes(archive);
      if (withSums) {
        await File(
          path.join(overrideCacheDir.path, 'SHA256SUMS'),
        ).writeAsString(sums);
      }
      await extractedDir.create();
      for (final library in _llamaLibraries) {
        await File(
          path.join(extractedDir.path, library),
        ).writeAsString('legacy-$library');
      }
    }

    test('is reused by the next build without extracting again', () async {
      await buildOnline();
      expect(marker, _exists);

      final log = <String>[];
      final libraries = await buildOffline(log: log);

      expect(libraries['libllamadart.so'], 'valid-libllamadart.so');
      expect(log, contains(contains('Using cached native bundle:')));
      expect(log, isNot(contains(contains('Extracted native bundle'))));
    });

    test('whose library was replaced is extracted again', () async {
      await buildOnline();
      File(
        path.join(extractedDir.path, 'libllamadart.so'),
      ).writeAsStringSync('fake-libllamadart.so');

      final log = <String>[];
      final libraries = await buildOffline(log: log);

      expect(libraries['libllamadart.so'], 'valid-libllamadart.so');
      expect(
        log,
        contains(
          allOf(contains('WARNING'), contains('does not match its archive')),
        ),
      );
    });

    test('with a marker is not re-extracted unverified offline', () async {
      await buildOnline();
      await File(path.join(overrideCacheDir.path, 'SHA256SUMS')).delete();
      File(
        path.join(extractedDir.path, 'libllamadart.so'),
      ).writeAsStringSync('fake-libllamadart.so');
      final offline = RuntimeBundleHttpFixture.offline();

      await expectLater(
        _runHook(project, offline, tag: _overrideTag),
        throwsA(isA<NativeArchiveDigestException>()),
      );
      expect(offline.requests, [overrideSumsUrl]);
    });

    test('from before markers without its archive is downloaded again, '
        'logging no warning', () async {
      await seedLegacy(withSums: true);
      await cachedArchive.delete();
      final log = await _captureLog(buildOnline);

      expect(log, contains(contains('has no extraction record')));
      expect(
        log,
        isNot(contains(allOf(contains('WARNING'), contains('Cached native')))),
      );
      expect(marker, _exists);
    });

    test('with an added library is extracted again', () async {
      await buildOnline();
      File(
        path.join(extractedDir.path, 'libggml-vulkan.so'),
      ).writeAsStringSync('stub');

      final libraries = await buildOffline();

      expect(libraries, isNot(contains('libggml-vulkan.so')));
      expect(libraries['libllamadart.so'], 'valid-libllamadart.so');
    });

    test('without its archive is downloaded again', () async {
      await buildOnline();
      await cachedArchive.delete();
      final fixture = RuntimeBundleHttpFixture({
        overrideSumsUrl: sums.codeUnits,
        overrideArchiveUrl: archive,
      });

      await _runHook(project, fixture, tag: _overrideTag, check: () {});

      expect(fixture.requests, [overrideSumsUrl, overrideArchiveUrl]);
    });

    test('from before markers whose archive the cached SHA256SUMS does not '
        'list is not used', () async {
      await seedLegacy(withSums: false);
      await File(path.join(overrideCacheDir.path, 'SHA256SUMS')).writeAsString(
        sha256SumsFor({archiveName(_overrideTag): _archive('published')}),
      );
      final offline = RuntimeBundleHttpFixture.offline();

      await expectLater(
        _runHook(project, offline, tag: _overrideTag),
        throwsA(isA<NativeArchiveDigestException>()),
      );
      expect(offline.requests, [overrideSumsUrl]);
      expect(extractedDir, isNot(_exists));
    });

    for (final withSums in [true, false]) {
      test(
        'from before markers is re-extracted offline from its archive, '
        '${withSums ? 'verified by' : 'without'} a cached SHA256SUMS',
        () async {
          await seedLegacy(withSums: withSums);

          final libraries = await buildOffline();

          expect(libraries['libllamadart.so'], 'valid-libllamadart.so');
          expect(marker, _exists);
          expect(
            jsonDecode(marker.readAsStringSync()),
            containsPair(
              'archive',
              containsPair('sha256', sha256.convert(archive).toString()),
            ),
          );
          final log = <String>[];
          await buildOffline(log: log);
          expect(log, contains(contains('Using cached native bundle:')));
        },
      );
    }

    test('from before markers of the pinned release is not re-extracted '
        'from an archive that differs from its pin', () async {
      final pinnedCacheDir = Directory(
        path.join(nativeBundlesDir, llamaCppTag, _bundle),
      );
      final pinnedExtracted = Directory(
        path.join(pinnedCacheDir.path, 'extracted'),
      );
      await pinnedExtracted.create(recursive: true);
      for (final library in _llamaLibraries) {
        await File(
          path.join(pinnedExtracted.path, library),
        ).writeAsString('legacy-$library');
      }
      final pinnedArchive = File(
        path.join(pinnedCacheDir.path, archiveName(llamaCppTag)),
      );
      await pinnedArchive.writeAsBytes(_archive('tampered'));
      final offline = RuntimeBundleHttpFixture.offline();

      await expectLater(
        _runHook(project, offline),
        throwsA(isA<OfflineFixtureException>()),
      );
      expect(offline.requests, [defaultArchiveUrl]);
      expect(pinnedArchive, isNot(_exists));
    });

    test('from before markers is not re-extracted from an archive that '
        'extracts incomplete', () async {
      final cacheDir = windowsOverrideCacheDir;
      final windowsExtracted = Directory(path.join(cacheDir.path, 'extracted'));
      await windowsExtracted.create(recursive: true);
      for (final library in _windowsLibraries) {
        await File(
          path.join(windowsExtracted.path, library),
        ).writeAsString('legacy-$library');
      }
      await File(
        path.join(
          cacheDir.path,
          'llamadart-native-windows-x64-$_overrideTag.tar.gz',
        ),
      ).writeAsBytes(_archive('stale', libraries: _windowsCudaLibraries));
      final offline = RuntimeBundleHttpFixture.offline();

      await expectLater(
        _runHook(
          project,
          offline,
          tag: _overrideTag,
          targetOS: OS.windows,
          targetArchitecture: Architecture.x64,
        ),
        throwsA(isA<NativeArchiveDigestException>()),
      );
      expect(offline.requests, [overrideSumsUrl]);
    });
  });

  test(
    'a repository override verifies against that release, not the pin',
    () async {
      final archive = _archive('fork');
      final sumsUrl = releaseUrl(_forkRepository, llamaCppTag, 'SHA256SUMS');
      final manifestUrl = releaseUrl(
        _forkRepository,
        llamaCppTag,
        'assets.json',
      );
      final archiveUrl = releaseUrl(
        _forkRepository,
        llamaCppTag,
        archiveName(llamaCppTag),
      );
      final fixture = RuntimeBundleHttpFixture({
        sumsUrl: sha256SumsFor({archiveName(llamaCppTag): archive}).codeUnits,
        archiveUrl: archive,
      });

      final libraries = await _runHook(
        project,
        fixture,
        repository: _forkRepository,
        check: () {},
      );

      expect(fixture.requests, [sumsUrl, manifestUrl, archiveUrl]);
      expect(libraries['libllamadart.so'], 'fork-libllamadart.so');
    },
  );

  group('stable_diffusion', () {
    final url =
        'https://github.com/leehack/stable-diffusion-native/releases/download/'
        '$stableDiffusionReleaseTag/$stableDiffusionArchiveName';

    test('rejects a downloaded archive with a typed error', () async {
      final fixture = RuntimeBundleHttpFixture({url: _archive('tampered')});

      await expectLater(
        _runHook(project, fixture, runtimes: const ['stable_diffusion']),
        throwsA(
          isA<NativeArchiveDigestException>().having(
            (error) => error.message,
            'message',
            contains(stableDiffusionArchiveName),
          ),
        ),
      );
      expect(fixture.requests, [url]);
      expect(stableDiffusionArchive, isNot(_exists));
    });

    test('redownloads a cached archive that differs from its pin', () async {
      await stableDiffusionArchive.parent.create(recursive: true);
      await stableDiffusionArchive.writeAsBytes(_archive('cached-tampered'));
      final fixture = RuntimeBundleHttpFixture({url: _archive('tampered')});

      await expectLater(
        _runHook(project, fixture, runtimes: const ['stable_diffusion']),
        throwsA(isA<NativeArchiveDigestException>()),
      );
      expect(fixture.requests, [url]);
    });
  });

  group('LiteRT-LM', () {
    final url =
        'https://github.com/leehack/litert-lm-native/releases/download/'
        '$liteRtLmReleaseTag/$liteRtLmArchiveName';

    test('rejects a downloaded archive with a typed error', () async {
      final fixture = RuntimeBundleHttpFixture({url: _archive('tampered')});

      await expectLater(
        _runHook(project, fixture, runtimes: const ['litert_lm']),
        throwsA(
          isA<NativeArchiveDigestException>().having(
            (error) => error.message,
            'message',
            contains(liteRtLmArchiveName),
          ),
        ),
      );
      expect(fixture.requests, [url]);
      expect(liteRtLmArchive, isNot(_exists));
    });

    test('redownloads a cached archive that differs from its pin', () async {
      await liteRtLmArchive.parent.create(recursive: true);
      await liteRtLmArchive.writeAsBytes(_archive('cached-tampered'));
      final fixture = RuntimeBundleHttpFixture({url: _archive('tampered')});

      await expectLater(
        _runHook(project, fixture, runtimes: const ['litert_lm']),
        throwsA(isA<NativeArchiveDigestException>()),
      );
      expect(fixture.requests, [url]);
    });
  });
}

final _exists = predicate<FileSystemEntity>(
  (entity) => entity.existsSync(),
  'exists',
);

List<int> _utf16le(String text) => [
  0xFF,
  0xFE,
  for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
];

/// Runs the hook (for Linux arm64 by default) with every download served by
/// [fixture], and returns the emitted llama.cpp libraries' contents by file
/// name.
Future<Map<String, String>> _runHook(
  HookProjectRoot project,
  RuntimeBundleHttpFixture fixture, {
  String? tag,
  String? repository,
  List<String> runtimes = const ['llama_cpp'],
  OS targetOS = OS.linux,
  Architecture targetArchitecture = Architecture.arm64,
  void Function()? check,
}) async {
  final libraries = <String, String>{};
  await build_hook.withRuntimeBundleHttpClientForTesting(
    fixture.createClient,
    () => project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: targetOS,
      targetArchitecture: targetArchitecture,
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'llamadart_native_runtimes': runtimes,
            'llamadart_stable_diffusion_backends': ['cpu'],
            'llamadart_native_tag': ?tag,
            'llamadart_native_repository': ?repository,
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
        if (check == null) {
          fail('The hook emitted assets from an unverified archive.');
        }
        check();
      },
    ),
  );
  return libraries;
}

/// A `.tar.gz` bundle whose libraries hold `<label>-<library>`.
List<int> _archive(String label, {List<String> libraries = _llamaLibraries}) {
  final archive = Archive();
  for (final library in libraries) {
    final content = '$label-$library'.codeUnits;
    archive.addFile(ArchiveFile(library, content.length, content));
  }
  return GZipEncoder().encode(TarEncoder().encode(archive));
}

Future<List<String>> _captureLog(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => lines.add(line),
    ),
  );
  return lines;
}
