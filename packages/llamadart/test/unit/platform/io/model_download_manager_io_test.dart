@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/download/model_download_manager_base.dart';
import 'package:llamadart/src/core/models/model_load_options.dart';
import 'package:llamadart/src/platform/io/model_download_manager_io.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('DefaultModelDownloadManager IO', () {
    late Directory tempDir;
    late _ModelHttpFixture server;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'llamadart_model_cache_test_',
      );
      server = await _ModelHttpFixture.start();
    });

    tearDown(() async {
      await server.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolves desktop shared model cache directories', () {
      expect(
        DefaultModelDownloadManager.defaultSharedCacheDirectory(
          platform: ModelCachePlatform.linux,
          environment: const <String, String>{
            'XDG_CACHE_HOME': '/tmp/cache-home',
          },
        ),
        '/tmp/cache-home/llamadart/models',
      );
      expect(
        DefaultModelDownloadManager.defaultSharedCacheDirectory(
          platform: ModelCachePlatform.linux,
          environment: const <String, String>{},
          homeDirectory: '/home/alice',
        ),
        '/home/alice/.cache/llamadart/models',
      );
      expect(
        DefaultModelDownloadManager.defaultSharedCacheDirectory(
          platform: ModelCachePlatform.macos,
          environment: const <String, String>{},
          homeDirectory: '/Users/alice',
        ),
        '/Users/alice/Library/Caches/llamadart/models',
      );
      expect(
        DefaultModelDownloadManager.defaultSharedCacheDirectory(
          platform: ModelCachePlatform.windows,
          environment: const <String, String>{
            'LOCALAPPDATA': r'C:\Users\Alice\AppData\Local',
          },
        ),
        r'C:\Users\Alice\AppData\Local\llamadart\models',
      );
    });

    test('constructor defaults to the platform implicit cache directory', () {
      final manager = DefaultModelDownloadManager();
      final platform = ModelCachePlatform.parse(Platform.operatingSystem);

      if (platform.supportsImplicitSharedModelCache) {
        expect(
          manager.defaultCacheDirectory,
          DefaultModelDownloadManager.defaultSharedCacheDirectory(
            platform: platform,
          ),
        );
      } else {
        expect(
          manager.defaultCacheDirectory,
          path.join(Directory.systemTemp.path, 'llamadart', 'models'),
        );
      }
    });

    test('auto uses desktop shared cache directories', () {
      final linuxManager = DefaultModelDownloadManager.auto(
        platform: ModelCachePlatform.linux,
        environment: const <String, String>{
          'XDG_CACHE_HOME': '/tmp/cache-home',
        },
        appPrivateCacheDirectory: path.join(tempDir.path, 'mobile-private'),
      );
      final macosManager = DefaultModelDownloadManager.auto(
        platform: ModelCachePlatform.macos,
        environment: const <String, String>{},
        homeDirectory: '/Users/alice',
      );

      expect(
        linuxManager.defaultCacheDirectory,
        '/tmp/cache-home/llamadart/models',
      );
      expect(
        macosManager.defaultCacheDirectory,
        '/Users/alice/Library/Caches/llamadart/models',
      );
    });

    test('auto uses app-private directories on mobile', () {
      final androidManager = DefaultModelDownloadManager.auto(
        platform: ModelCachePlatform.android,
        appPrivateCacheDirectory: path.join(tempDir.path, 'android-private'),
      );
      final iosManager = DefaultModelDownloadManager.auto(
        platform: ModelCachePlatform.ios,
        appPrivateCacheDirectory: path.join(tempDir.path, 'ios-private'),
      );

      expect(androidManager.defaultCacheDirectory, endsWith('android-private'));
      expect(iosManager.defaultCacheDirectory, endsWith('ios-private'));
    });

    test('auto uses platform-specific app-private directories on mobile', () {
      final commonPrivate = path.join(tempDir.path, 'common-private');
      final androidPrivate = path.join(tempDir.path, 'android-private');
      final iosPrivate = path.join(tempDir.path, 'ios-private');

      final androidManager = DefaultModelDownloadManager.auto(
        platform: ModelCachePlatform.android,
        appPrivateCacheDirectory: commonPrivate,
        androidAppPrivateCacheDirectory: androidPrivate,
        iosAppPrivateCacheDirectory: iosPrivate,
      );
      final iosManager = DefaultModelDownloadManager.auto(
        platform: ModelCachePlatform.ios,
        appPrivateCacheDirectory: commonPrivate,
        androidAppPrivateCacheDirectory: androidPrivate,
        iosAppPrivateCacheDirectory: iosPrivate,
      );
      final macosManager = DefaultModelDownloadManager.auto(
        platform: ModelCachePlatform.macos,
        environment: const <String, String>{},
        homeDirectory: '/Users/alice',
        appPrivateCacheDirectory: commonPrivate,
        androidAppPrivateCacheDirectory: androidPrivate,
        iosAppPrivateCacheDirectory: iosPrivate,
      );

      expect(androidManager.defaultCacheDirectory, androidPrivate);
      expect(iosManager.defaultCacheDirectory, iosPrivate);
      expect(
        macosManager.defaultCacheDirectory,
        '/Users/alice/Library/Caches/llamadart/models',
      );
    });

    test('auto explicit cache directory overrides platform defaults', () {
      final manager = DefaultModelDownloadManager.auto(
        platform: ModelCachePlatform.android,
        cacheDirectory: path.join(tempDir.path, 'user-library'),
      );

      expect(manager.defaultCacheDirectory, endsWith('user-library'));
    });

    test('auto falls back to app-private temp cache on mobile', () {
      for (final platform in <ModelCachePlatform>[
        ModelCachePlatform.android,
        ModelCachePlatform.ios,
      ]) {
        final manager = DefaultModelDownloadManager.auto(platform: platform);

        expect(
          manager.defaultCacheDirectory,
          path.join(Directory.systemTemp.path, 'llamadart', 'models'),
          reason: platform.name,
        );
      }
    });

    test('auto applies namespace to mobile temp cache fallback', () {
      final androidManager = DefaultModelDownloadManager.auto(
        namespace: 'com.example.app',
        platform: ModelCachePlatform.android,
      );
      final iosManager = DefaultModelDownloadManager.auto(
        namespace: 'com.example.app',
        platform: ModelCachePlatform.ios,
      );

      expect(
        androidManager.defaultCacheDirectory,
        path.join(Directory.systemTemp.path, 'com.example.app', 'models'),
      );
      expect(
        iosManager.defaultCacheDirectory,
        path.join(Directory.systemTemp.path, 'com.example.app', 'models'),
      );
    });

    test('auto validates namespace for mobile temp cache fallback', () {
      expect(
        () => DefaultModelDownloadManager.auto(
          namespace: '../bad',
          platform: ModelCachePlatform.android,
        ),
        throwsArgumentError,
      );
    });

    test(
      'auto uses generic mobile directory when specific directory is blank',
      () {
        final genericPrivate = path.join(tempDir.path, 'generic-private');
        final androidManager = DefaultModelDownloadManager.auto(
          platform: ModelCachePlatform.android,
          appPrivateCacheDirectory: genericPrivate,
          androidAppPrivateCacheDirectory: '  ',
        );
        final iosManager = DefaultModelDownloadManager.auto(
          platform: ModelCachePlatform.ios,
          appPrivateCacheDirectory: genericPrivate,
          iosAppPrivateCacheDirectory: '',
        );

        expect(androidManager.defaultCacheDirectory, genericPrivate);
        expect(iosManager.defaultCacheDirectory, genericPrivate);
      },
    );

    test('auto rejects non-file-backed and unknown platforms', () {
      for (final platform in <ModelCachePlatform>[
        ModelCachePlatform.web,
        ModelCachePlatform.fuchsia,
        ModelCachePlatform.unknown,
      ]) {
        expect(
          () => DefaultModelDownloadManager.auto(platform: platform),
          throwsA(isA<LlamaUnsupportedException>()),
          reason: platform.name,
        );
      }
    });

    test('rejects implicit shared cache directories on mobile and web', () {
      for (final platform in <ModelCachePlatform>[
        ModelCachePlatform.android,
        ModelCachePlatform.ios,
        ModelCachePlatform.web,
        ModelCachePlatform.fuchsia,
        ModelCachePlatform.unknown,
      ]) {
        expect(
          () => DefaultModelDownloadManager.defaultSharedCacheDirectory(
            platform: platform,
            environment: const <String, String>{},
            homeDirectory: '/home/alice',
          ),
          throwsA(isA<LlamaUnsupportedException>()),
          reason: platform.name,
        );
      }
    });

    test('uses explicit directories for mobile sharing modes', () {
      final appPrivate = DefaultModelDownloadManager.appPrivate(
        cacheDirectory: path.join(tempDir.path, 'app-private'),
      );
      final userSelected = DefaultModelDownloadManager.userSelected(
        cacheDirectory: path.join(tempDir.path, 'user-selected'),
      );
      final appGroup = DefaultModelDownloadManager.appGroup(
        cacheDirectory: path.join(tempDir.path, 'app-group'),
      );
      final explicitShared = DefaultModelDownloadManager.sharedCache(
        cacheDirectory: path.join(tempDir.path, 'explicit-shared'),
        platform: ModelCachePlatform.android,
      );

      expect(appPrivate.defaultCacheDirectory, endsWith('app-private'));
      expect(userSelected.defaultCacheDirectory, endsWith('user-selected'));
      expect(appGroup.defaultCacheDirectory, endsWith('app-group'));
      expect(explicitShared.defaultCacheDirectory, endsWith('explicit-shared'));
    });

    test('validates shared cache namespace', () {
      expect(
        () => DefaultModelDownloadManager.defaultSharedCacheDirectory(
          namespace: '../llamadart',
          platform: ModelCachePlatform.linux,
          environment: const <String, String>{},
          homeDirectory: '/home/alice',
        ),
        throwsArgumentError,
      );
      expect(
        DefaultModelDownloadManager.defaultSharedCacheDirectory(
          namespace: 'com.example.llamadart',
          platform: ModelCachePlatform.linux,
          environment: const <String, String>{},
          homeDirectory: '/home/alice',
        ),
        '/home/alice/.cache/com.example.llamadart/models',
      );
    });

    test(
      'downloads remote source, writes metadata, reports progress, and reuses cache',
      () async {
        server.payload = utf8.encode('model-bytes-v1');
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        final progress = <double>[];

        final entry = await manager.ensureModel(
          source,
          options: ModelLoadOptions(
            bearerToken: 'secret-token',
            headers: const <String, String>{'X-Test-Header': 'present'},
          ),
          onProgress: (event) {
            final fraction = event.fraction;
            if (fraction != null) {
              progress.add(fraction);
            }
          },
        );

        expect(server.requestCount, 1);
        expect(server.lastAuthorization, 'Bearer secret-token');
        expect(server.lastTestHeader, 'present');
        expect(File(entry.filePath).readAsBytesSync(), server.payload);
        expect(entry.bytes, server.payload.length);
        expect(entry.sha256, isNull);
        expect(entry.sourceCanonicalKey, isNot(contains('secret-token')));
        expect(progress, isNotEmpty);
        expect(progress.last, 1);
        expect(
          File(
            path.join(path.dirname(entry.filePath), 'metadata.json'),
          ).existsSync(),
          isTrue,
        );

        server.payload = utf8.encode('model-bytes-v2');
        final cached = await manager.ensureModel(source);

        expect(
          server.requestCount,
          1,
          reason: 'preferCached should not re-download a completed entry',
        );
        expect(cached.filePath, entry.filePath);
        expect(
          File(cached.filePath).readAsBytesSync(),
          utf8.encode('model-bytes-v1'),
        );
      },
    );

    test('sharedCache managers reuse one explicit model library', () async {
      server.payload = utf8.encode('shared-cache-model');
      server.responseDelay = const Duration(milliseconds: 100);
      final firstManager = DefaultModelDownloadManager.sharedCache(
        cacheDirectory: tempDir.path,
      );
      final secondManager = DefaultModelDownloadManager.sharedCache(
        cacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

      final entries = await Future.wait(<Future<ModelCacheEntry>>[
        firstManager.ensureModel(source),
        secondManager.ensureModel(source),
      ]);

      expect(server.requestCount, 1);
      expect(server.maxActiveRequests, 1);
      expect(entries.map((entry) => entry.filePath).toSet(), hasLength(1));
      expect(
        File(entries.first.filePath).readAsStringSync(),
        'shared-cache-model',
      );
    });

    test('downloads and caches LiteRT-LM bundle files', () async {
      server.payload = utf8.encode('litert-lm-bundle-bytes');
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(
        server.modelUri,
        fileName: 'gemma-4-E2B-it.litertlm',
      );

      final entry = await manager.ensureModel(source);
      final cached = await manager.get(source.cacheKey);

      expect(server.requestCount, 1);
      expect(entry.fileName, 'gemma-4-E2B-it.litertlm');
      expect(entry.filePath, endsWith('gemma-4-E2B-it.litertlm'));
      expect(File(entry.filePath).readAsStringSync(), 'litert-lm-bundle-bytes');
      expect(cached?.filePath, entry.filePath);
      expect(cached?.sourceCanonicalKey, source.metadataSourceKey);
    });

    test('serializes concurrent downloads for the same cache key', () async {
      server.payload = utf8.encode('serialized-model');
      server.responseDelay = const Duration(milliseconds: 100);
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

      final entries = await Future.wait(<Future<ModelCacheEntry>>[
        manager.ensureModel(source),
        manager.ensureModel(source),
        manager.ensureModel(source),
      ]);

      expect(server.requestCount, 1);
      expect(server.maxActiveRequests, 1);
      expect(entries.map((entry) => entry.filePath).toSet(), hasLength(1));
      expect(
        File(entries.first.filePath).readAsStringSync(),
        'serialized-model',
      );
      final cacheDir = Directory(path.dirname(entries.first.filePath));
      expect(
        File(path.join(cacheDir.path, 'tiny.gguf.part')).existsSync(),
        isFalse,
      );
      expect(
        File(path.join(cacheDir.path, 'tiny.gguf.part.json')).existsSync(),
        isFalse,
      );
    });

    test('serializes same-key downloads across manager instances', () async {
      server.payload = utf8.encode('shared-manager-cache');
      server.responseDelay = const Duration(milliseconds: 100);
      final firstManager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final secondManager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

      final entries = await Future.wait(<Future<ModelCacheEntry>>[
        firstManager.ensureModel(source),
        secondManager.ensureModel(source),
      ]);

      expect(server.requestCount, 1);
      expect(server.maxActiveRequests, 1);
      expect(entries.map((entry) => entry.filePath).toSet(), hasLength(1));
      expect(
        File(entries.first.filePath).readAsStringSync(),
        'shared-manager-cache',
      );
    });

    test('keeps different cache keys parallelizable', () async {
      server.responseDelay = const Duration(milliseconds: 100);
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final firstSource = ModelSource.url(
        server.modelUri,
        fileName: 'first.gguf',
      );
      final secondSource = ModelSource.url(
        server.modelUri.replace(queryParameters: const {'variant': 'second'}),
        fileName: 'second.gguf',
      );

      final entries = await Future.wait(<Future<ModelCacheEntry>>[
        manager.ensureModel(firstSource),
        manager.ensureModel(secondSource),
      ]);

      expect(server.requestCount, 2);
      expect(server.maxActiveRequests, greaterThanOrEqualTo(2));
      expect(entries.map((entry) => entry.cacheKey).toSet(), hasLength(2));
      expect(entries.map((entry) => entry.filePath).toSet(), hasLength(2));
    });

    test(
      'cancelled same-key waiters do not cancel the active download',
      () async {
        server.payload = utf8.encode('leader-model');
        server.responseDelay = const Duration(milliseconds: 100);
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        final waiterToken = ModelDownloadCancelToken();

        final leader = manager.ensureModel(source);
        await server.firstRequestStarted;
        final waiter = manager.ensureModel(
          source,
          options: ModelLoadOptions(cancelToken: waiterToken),
        );
        waiterToken.cancel();

        final leaderEntry = await leader;
        await expectLater(waiter, throwsA(isA<LlamaStateException>()));

        expect(server.requestCount, 1);
        expect(File(leaderEntry.filePath).readAsStringSync(), 'leader-model');
        expect(
          (await manager.get(source.cacheKey))?.filePath,
          leaderEntry.filePath,
        );
      },
    );

    test('cancelled same-key leader releases lock for retry', () async {
      server.payload = utf8.encode('retry-after-leader-cancel');
      server.responseDelay = const Duration(milliseconds: 100);
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      final leaderToken = ModelDownloadCancelToken();

      final leader = manager.ensureModel(
        source,
        options: ModelLoadOptions(cancelToken: leaderToken),
      );
      await server.firstRequestStarted;
      final retry = manager.ensureModel(source);
      leaderToken.cancel();

      await expectLater(leader, throwsA(isA<LlamaStateException>()));
      final retryEntry = await retry;

      expect(server.requestCount, 2);
      expect(
        File(retryEntry.filePath).readAsStringSync(),
        'retry-after-leader-cancel',
      );
      expect(
        (await manager.get(source.cacheKey))?.filePath,
        retryEntry.filePath,
      );
    });

    test(
      'cross-origin redirects do not forward caller supplied headers',
      () async {
        final redirectedServer = await _ModelHttpFixture.start();
        addTearDown(redirectedServer.close);
        server.redirectTo = redirectedServer.modelUri;
        redirectedServer.payload = utf8.encode('redirected-model');
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        final entry = await manager.ensureModel(
          source,
          options: ModelLoadOptions(
            bearerToken: 'secret-token',
            headers: const <String, String>{'X-Test-Header': 'present'},
          ),
        );

        expect(server.requestCount, 1);
        expect(server.lastAuthorization, 'Bearer secret-token');
        expect(server.lastTestHeader, 'present');
        expect(redirectedServer.requestCount, 1);
        expect(redirectedServer.lastAuthorization, isNull);
        expect(redirectedServer.lastTestHeader, isNull);
        expect(File(entry.filePath).readAsStringSync(), 'redirected-model');
      },
    );

    test(
      'cacheOnly fails on cache miss without touching the network',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        await expectLater(
          manager.ensureModel(
            source,
            options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
          ),
          throwsA(isA<LlamaStateException>()),
        );

        expect(server.requestCount, 0);
      },
    );

    test('cacheOnly returns an existing completed cache entry', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

      server.payload = utf8.encode('cached-model');
      final first = await manager.ensureModel(source);
      server.payload = utf8.encode('remote-newer-model');

      final cached = await manager.ensureModel(
        source,
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
      );

      expect(server.requestCount, 1);
      expect(cached.filePath, first.filePath);
      expect(File(cached.filePath).readAsStringSync(), 'cached-model');
    });

    test(
      'cacheOnly recovers missing metadata for an existing model file',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        server.payload = utf8.encode('metadata-recovery-model');
        final first = await manager.ensureModel(source);
        final metadataFile = File(
          path.join(path.dirname(first.filePath), 'metadata.json'),
        );
        await metadataFile.delete();

        final recovered = await manager.ensureModel(
          source,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
        );

        expect(server.requestCount, 1);
        expect(recovered.filePath, first.filePath);
        expect(recovered.cacheKey, source.cacheKey);
        expect(recovered.fileName, source.fileName);
        expect(recovered.bytes, utf8.encode('metadata-recovery-model').length);
        expect(metadataFile.existsSync(), isTrue);
        expect(
          metadataFile.readAsStringSync(),
          isNot(contains('download=true')),
        );
      },
    );

    test(
      'cache hit recovers malformed metadata without re-downloading',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        server.payload = utf8.encode('malformed-metadata-model');
        final first = await manager.ensureModel(source);
        final metadataFile = File(
          path.join(path.dirname(first.filePath), 'metadata.json'),
        );
        await metadataFile.writeAsString('{not valid json');

        server.payload = utf8.encode('remote-newer-model');
        final recovered = await manager.ensureModel(source);

        expect(server.requestCount, 1);
        expect(recovered.filePath, first.filePath);
        expect(
          File(recovered.filePath).readAsStringSync(),
          'malformed-metadata-model',
        );
        expect(
          metadataFile.readAsStringSync(),
          contains('"schema_version": 1'),
        );
      },
    );

    test('cacheOnly recovers malformed metadata without network', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

      server.payload = utf8.encode('cache-only-malformed-metadata-model');
      final first = await manager.ensureModel(source);
      final metadataFile = File(
        path.join(path.dirname(first.filePath), 'metadata.json'),
      );
      await metadataFile.writeAsString('{not valid json');

      server.payload = utf8.encode('remote-newer-model');
      final recovered = await manager.ensureModel(
        source,
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
      );

      expect(server.requestCount, 1);
      expect(recovered.filePath, first.filePath);
      expect(
        File(recovered.filePath).readAsStringSync(),
        'cache-only-malformed-metadata-model',
      );
      expect(metadataFile.readAsStringSync(), contains('"schema_version": 1'));
    });

    test(
      'cacheOnly recovers unsupported metadata schema for an existing file',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        server.payload = utf8.encode('future-schema-model');
        final first = await manager.ensureModel(source);
        final metadataFile = File(
          path.join(path.dirname(first.filePath), 'metadata.json'),
        );
        final metadata =
            jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
        metadata['schema_version'] = 999;
        await metadataFile.writeAsString(jsonEncode(metadata));

        final recovered = await manager.ensureModel(
          source,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
        );

        expect(server.requestCount, 1);
        expect(recovered.filePath, first.filePath);
        expect(
          metadataFile.readAsStringSync(),
          contains('"schema_version": 1'),
        );
      },
    );

    test(
      'cache hit redownloads when metadata byte length does not match file',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        server.payload = utf8.encode('cached-model');
        final first = await manager.ensureModel(source);
        final metadataFile = File(
          path.join(path.dirname(first.filePath), 'metadata.json'),
        );
        final metadata =
            jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
        metadata['bytes'] = 1024 * 1024;
        await metadataFile.writeAsString(jsonEncode(metadata));

        server.payload = utf8.encode('redownloaded-model');
        final refreshed = await manager.ensureModel(source);

        expect(server.requestCount, 2);
        expect(refreshed.filePath, first.filePath);
        expect(
          File(refreshed.filePath).readAsStringSync(),
          'redownloaded-model',
        );
      },
    );

    test(
      'cache hit redownloads when stored sha256 no longer matches file',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        server.payload = utf8.encode('checksummed-model');
        final expectedSha256 = sha256.convert(server.payload).toString();

        final first = await manager.ensureModel(
          source,
          options: ModelLoadOptions(sha256: expectedSha256),
        );
        await File(first.filePath).writeAsString('checksum-mismatch');

        server.payload = utf8.encode('redownloaded-model');
        final refreshed = await manager.ensureModel(source);

        expect(server.requestCount, 2);
        expect(refreshed.filePath, first.filePath);
        expect(
          File(refreshed.filePath).readAsStringSync(),
          'redownloaded-model',
        );
      },
    );

    test(
      'cache hit redownloads when stored sha256 conflicts with caller sha256',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        server.payload = utf8.encode('checksummed-model');
        final storedSha256 = sha256.convert(server.payload).toString();

        final first = await manager.ensureModel(
          source,
          options: ModelLoadOptions(sha256: storedSha256),
        );
        server.payload = utf8.encode('checksum-mismatch');
        final callerSha256 = sha256.convert(server.payload).toString();
        await File(first.filePath).writeAsString('checksum-mismatch');

        final refreshed = await manager.ensureModel(
          source,
          options: ModelLoadOptions(sha256: callerSha256),
        );

        expect(server.requestCount, 2);
        expect(refreshed.filePath, first.filePath);
        expect(refreshed.sha256, callerSha256);
        expect(
          File(refreshed.filePath).readAsStringSync(),
          'checksum-mismatch',
        );
      },
    );

    test('cache hit rejects metadata for a different source', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      final otherSource = ModelSource.url(
        server.modelUri.replace(queryParameters: const {'variant': 'other'}),
        fileName: 'other.gguf',
      );

      server.payload = utf8.encode('cached-model');
      final first = await manager.ensureModel(source);
      final metadataFile = File(
        path.join(path.dirname(first.filePath), 'metadata.json'),
      );
      final metadata =
          jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
      metadata['cache_key'] = otherSource.cacheKey;
      metadata['file_name'] = otherSource.fileName;
      metadataFile.writeAsStringSync(jsonEncode(metadata));

      server.payload = utf8.encode('fresh-model');
      final refreshed = await manager.ensureModel(source);

      expect(server.requestCount, 2);
      expect(refreshed.cacheKey, source.cacheKey);
      expect(refreshed.fileName, source.fileName);
      expect(File(refreshed.filePath).readAsStringSync(), 'fresh-model');
    });

    test('management APIs can target the per-call cache directory', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final customCacheDirectory = path.join(tempDir.path, 'custom-cache');
      server.payload = utf8.encode('custom-cache-model');
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

      final entry = await manager.ensureModel(
        source,
        options: ModelLoadOptions(cacheDirectory: customCacheDirectory),
      );

      expect(await manager.list(), isEmpty);
      expect(
        await manager.list(cacheDirectory: customCacheDirectory),
        hasLength(1),
      );
      expect(
        await manager.get(
          source.cacheKey,
          cacheDirectory: customCacheDirectory,
        ),
        isNotNull,
      );
      expect(File(entry.filePath).existsSync(), isTrue);

      final pruned = await manager.prune(
        maxBytes: 0,
        cacheDirectory: customCacheDirectory,
      );
      expect(pruned.single.cacheKey, source.cacheKey);
      expect(File(entry.filePath).existsSync(), isFalse);

      final refreshed = await manager.ensureModel(
        source,
        options: ModelLoadOptions(cacheDirectory: customCacheDirectory),
      );
      expect(File(refreshed.filePath).existsSync(), isTrue);

      await manager.remove(
        source.cacheKey,
        cacheDirectory: customCacheDirectory,
      );
      expect(await manager.list(cacheDirectory: customCacheDirectory), isEmpty);

      await manager.ensureModel(
        source,
        options: ModelLoadOptions(cacheDirectory: customCacheDirectory),
      );
      await manager.clear(cacheDirectory: customCacheDirectory);
      expect(await manager.list(cacheDirectory: customCacheDirectory), isEmpty);
    });

    test('prune removes stale metadata entries with missing files', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      server.payload = utf8.encode('stale-cache-model');
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      final entry = await manager.ensureModel(source);
      final cacheDir = Directory(path.dirname(entry.filePath));
      await File(entry.filePath).delete();

      final pruned = await manager.prune();

      expect(pruned.single.cacheKey, source.cacheKey);
      expect(await cacheDir.exists(), isFalse);
      expect(await manager.list(), isEmpty);
    });

    test(
      'ignores metadata whose file path points outside its cache entry',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        server.payload = utf8.encode('cached-model');
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        final entry = await manager.ensureModel(source);
        final metadataFile = File(
          path.join(path.dirname(entry.filePath), 'metadata.json'),
        );
        final outsideDir = await Directory.systemTemp.createTemp(
          'llamadart_outside_cache_',
        );
        addTearDown(() async {
          if (await outsideDir.exists()) {
            await outsideDir.delete(recursive: true);
          }
        });
        final outsideFile = File(path.join(outsideDir.path, 'outside.gguf'))
          ..writeAsStringSync('outside');
        final metadata =
            jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
        metadata['file_path'] = outsideFile.path;
        metadataFile.writeAsStringSync(jsonEncode(metadata));

        expect(await manager.list(), isEmpty);

        await manager.remove(source.cacheKey);

        expect(outsideFile.existsSync(), isTrue);
      },
    );

    test(
      'remove deletes matching cache directories even when cached file is missing',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        server.payload = utf8.encode('cached-model');
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        final entry = await manager.ensureModel(source);
        final cacheEntryDirectory = Directory(path.dirname(entry.filePath));

        await File(entry.filePath).delete();

        expect(await manager.list(), isEmpty);
        await manager.remove(source.cacheKey);

        expect(cacheEntryDirectory.existsSync(), isFalse);
      },
    );

    test('stores sha256 metadata only when checksum is requested', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      server.payload = utf8.encode('checksummed-model');
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      final expectedSha256 = sha256.convert(server.payload).toString();

      final entry = await manager.ensureModel(
        source,
        options: ModelLoadOptions(sha256: expectedSha256),
      );

      expect(entry.sha256, expectedSha256);
      expect(
        File(
          path.join(path.dirname(entry.filePath), 'metadata.json'),
        ).readAsStringSync(),
        contains(expectedSha256),
      );
    });

    test('cache hit with sha256 verifies and persists the digest', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      server.payload = utf8.encode('cached-checksum-model');
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      final first = await manager.ensureModel(source);
      final expectedSha256 = sha256.convert(server.payload).toString();

      expect(first.sha256, isNull);

      final verified = await manager.ensureModel(
        source,
        options: ModelLoadOptions(sha256: expectedSha256),
      );

      expect(server.requestCount, 1);
      expect(verified.filePath, first.filePath);
      expect(verified.sha256, expectedSha256);
      expect(
        File(
          path.join(path.dirname(verified.filePath), 'metadata.json'),
        ).readAsStringSync(),
        contains(expectedSha256),
      );
    });

    test('local path sha256 is verified before metadata is returned', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final localFile = File(path.join(tempDir.path, 'local-model.gguf'))
        ..writeAsStringSync('local-model');
      final expectedSha256 = sha256
          .convert(utf8.encode('local-model'))
          .toString();

      final entry = await manager.ensureModel(
        ModelSource.path(localFile.path),
        options: ModelLoadOptions(sha256: expectedSha256),
      );

      expect(entry.filePath, localFile.path);
      expect(entry.sha256, expectedSha256);

      await expectLater(
        manager.ensureModel(
          ModelSource.path(localFile.path),
          options: ModelLoadOptions(sha256: List.filled(64, '0').join()),
        ),
        throwsA(isA<LlamaModelException>()),
      );
    });

    test('local path rejects remote cache/download options', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final localFile = File(path.join(tempDir.path, 'local-model.gguf'))
        ..writeAsStringSync('local-model');
      final source = ModelSource.path(localFile.path);
      final remoteOnlyOptions = <ModelLoadOptions>[
        ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
        ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
        ModelLoadOptions(cachePolicy: ModelCachePolicy.noCache),
        ModelLoadOptions(cacheDirectory: path.join(tempDir.path, 'cache')),
        ModelLoadOptions(bearerToken: 'secret-token'),
        ModelLoadOptions(headers: const <String, String>{'X-Test': 'value'}),
        ModelLoadOptions(resume: false),
        ModelLoadOptions(maxRetries: 0),
      ];

      for (final options in remoteOnlyOptions) {
        await expectLater(
          manager.ensureModel(source, options: options),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              allOf(contains('Local'), contains('ModelSource.path')),
            ),
          ),
        );
      }
    });

    test('local path honors cancellation before filesystem work', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final token = ModelDownloadCancelToken()..cancel();
      final missingPath = path.join(tempDir.path, 'missing-local-model.gguf');

      await expectLater(
        manager.ensureModel(
          ModelSource.path(missingPath),
          options: ModelLoadOptions(cancelToken: token),
        ),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test('normalizes local paths before returning metadata', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      await Directory(path.join(tempDir.path, 'nested')).create();
      final localFile = File(path.join(tempDir.path, 'local-model.gguf'))
        ..writeAsStringSync('local-model');
      final traversalPath = path.join(
        tempDir.path,
        'nested',
        '..',
        'local-model.gguf',
      );

      final entry = await manager.ensureModel(ModelSource.path(traversalPath));

      expect(entry.filePath, path.normalize(path.absolute(localFile.path)));
      expect(entry.filePath, isNot(contains('..')));
    });

    test('missing local path errors include the full path', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final missingPath = path.join(tempDir.path, 'missing', 'model.gguf');

      await expectLater(
        manager.ensureModel(ModelSource.path(missingPath)),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains(missingPath),
          ),
        ),
      );
    });

    test('local directory path fails with a clear file error', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final directory = Directory(path.join(tempDir.path, 'model-dir'))
        ..createSync();

      await expectLater(
        manager.ensureModel(ModelSource.path(directory.path)),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            allOf(contains('not a file'), contains(directory.path)),
          ),
        ),
      );
    });

    test(
      'noCache creates transient entries that cache cleanup can remove',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        server.payload = utf8.encode('first-transient');
        final first = await manager.ensureModel(
          source,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.noCache),
        );
        server.payload = utf8.encode('second-transient');
        final second = await manager.ensureModel(
          source,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.noCache),
        );

        expect(server.requestCount, 2);
        expect(first.filePath, isNot(second.filePath));
        expect(
          path.basename(path.dirname(first.filePath)),
          contains('-nocache-'),
        );
        expect(await manager.list(), hasLength(2));

        await manager.remove(source.cacheKey);

        expect(File(first.filePath).existsSync(), isFalse);
        expect(File(second.filePath).existsSync(), isFalse);
        expect(await manager.list(), isEmpty);
      },
    );

    test('failed noCache download removes transient cache directory', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      server.failuresBeforeSuccess = 1;
      server.failureStatusCode = HttpStatus.badRequest;

      await expectLater(
        manager.ensureModel(
          source,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.noCache),
        ),
        throwsA(isA<LlamaModelException>()),
      );

      expect(
        tempDir.listSync().whereType<Directory>().where(
          (dir) => path
              .basename(dir.path)
              .startsWith('${source.cacheDirectoryName}-nocache-'),
        ),
        isEmpty,
      );
    });

    test('prune on missing cache root returns empty list', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: path.join(tempDir.path, 'missing-cache-root'),
      );

      final removed = await manager.prune(maxBytes: 1);

      expect(removed, isEmpty);
    });

    test(
      'get finds newest matching cache entry without full metadata scan',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        server.payload = utf8.encode('stable-entry');
        await manager.ensureModel(source);

        final malformedCandidate = Directory(
          path.join(tempDir.path, '${source.cacheDirectoryName}-nocache-bad'),
        )..createSync(recursive: true);
        File(
          path.join(malformedCandidate.path, 'metadata.json'),
        ).writeAsStringSync('{not valid json');

        server.payload = utf8.encode('transient-entry');
        final transient = await manager.ensureModel(
          source,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.noCache),
        );

        final found = await manager.get(source.cacheKey);

        expect(found, isNotNull);
        expect(found!.filePath, transient.filePath);
        expect(File(found.filePath).readAsStringSync(), 'transient-entry');
      },
    );

    test('retries retryable HTTP failures and then succeeds', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      server.failuresBeforeSuccess = 1;
      server.failureStatusCode = HttpStatus.internalServerError;
      server.payload = utf8.encode('eventual-model');

      final entry = await manager.ensureModel(
        source,
        options: ModelLoadOptions(maxRetries: 1),
      );

      expect(server.requestCount, 2);
      expect(File(entry.filePath).readAsStringSync(), 'eventual-model');
    });

    test('does not retry non-retryable HTTP failures', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      server.failuresBeforeSuccess = 1;
      server.failureStatusCode = HttpStatus.notFound;

      await expectLater(
        manager.ensureModel(source, options: ModelLoadOptions(maxRetries: 3)),
        throwsA(isA<LlamaModelException>()),
      );

      expect(server.requestCount, 1);
    });

    test(
      'refresh re-downloads and replaces the cached file atomically',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        server.payload = utf8.encode('old-model');
        final first = await manager.ensureModel(source);
        expect(File(first.filePath).readAsStringSync(), 'old-model');

        server.payload = utf8.encode('new-model');
        final refreshed = await manager.ensureModel(
          source,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
        );

        expect(server.requestCount, 2);
        expect(refreshed.filePath, first.filePath);
        expect(File(refreshed.filePath).readAsStringSync(), 'new-model');
        expect(path.basename(refreshed.filePath), 'tiny.gguf');
        expect(
          Directory(
            path.dirname(refreshed.filePath),
          ).listSync().whereType<File>().map((f) => path.basename(f.path)),
          isNot(contains('tiny.gguf.tmp')),
        );
      },
    );

    test(
      'failed refresh preserves the previous completed cache entry',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');

        server.payload = utf8.encode('old-model');
        final first = await manager.ensureModel(source);
        final metadataFile = File(
          path.join(path.dirname(first.filePath), 'metadata.json'),
        );
        final metadataBefore = metadataFile.readAsStringSync();

        server.payload = utf8.encode('corrupt-new-model');
        await expectLater(
          manager.ensureModel(
            source,
            options: ModelLoadOptions(
              cachePolicy: ModelCachePolicy.refresh,
              sha256: List.filled(64, '0').join(),
            ),
          ),
          throwsA(isA<LlamaModelException>()),
        );

        expect(File(first.filePath).readAsStringSync(), 'old-model');
        expect(metadataFile.readAsStringSync(), metadataBefore);
        expect((await manager.get(source.cacheKey))?.filePath, first.filePath);
      },
    );

    test('checksum mismatch removes final file and metadata', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      server.payload = utf8.encode('bad-checksum-content');

      await expectLater(
        manager.ensureModel(
          source,
          options: ModelLoadOptions(sha256: List.filled(64, '0').join()),
        ),
        throwsA(isA<LlamaModelException>()),
      );

      final cacheDir = Directory(
        path.join(tempDir.path, source.cacheDirectoryName),
      );
      expect(File(path.join(cacheDir.path, 'tiny.gguf')).existsSync(), isFalse);
      expect(
        File(path.join(cacheDir.path, 'metadata.json')).existsSync(),
        isFalse,
      );
    });

    test(
      'resumes a partial download only when the server returns matching 206',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        server.payload = utf8.encode('0123456789');
        server.supportRanges = true;
        final cacheDir = Directory(
          path.join(tempDir.path, source.cacheDirectoryName),
        )..createSync(recursive: true);
        File(
          path.join(cacheDir.path, 'tiny.gguf.part'),
        ).writeAsStringSync('0123');
        File(path.join(cacheDir.path, 'tiny.gguf.part.json')).writeAsStringSync(
          '${jsonEncode(<String, Object?>{'etag': server.etag})}\n',
        );

        final entry = await manager.ensureModel(source);

        expect(server.lastRange, 'bytes=4-');
        expect(server.lastIfRange, server.etag);
        expect(File(entry.filePath).readAsStringSync(), '0123456789');
      },
    );

    test(
      'restarts validator-less partial downloads instead of appending',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        server.payload = utf8.encode('fresh-model');
        server.supportRanges = true;
        final cacheDir = Directory(
          path.join(tempDir.path, source.cacheDirectoryName),
        )..createSync(recursive: true);
        File(
          path.join(cacheDir.path, 'tiny.gguf.part'),
        ).writeAsStringSync('stale');

        final entry = await manager.ensureModel(source);

        expect(server.lastRange, isNull);
        expect(File(entry.filePath).readAsStringSync(), 'fresh-model');
      },
    );

    test(
      'restarts from byte zero when a resume request receives HTTP 200',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        server.payload = utf8.encode('fresh-content');
        server.supportRanges = false;
        final cacheDir = Directory(
          path.join(tempDir.path, source.cacheDirectoryName),
        )..createSync(recursive: true);
        File(
          path.join(cacheDir.path, 'tiny.gguf.part'),
        ).writeAsStringSync('stale-partial');
        File(path.join(cacheDir.path, 'tiny.gguf.part.json')).writeAsStringSync(
          '${jsonEncode(<String, Object?>{'etag': server.etag})}\n',
        );

        final entry = await manager.ensureModel(source);

        expect(server.lastRange, 'bytes=13-');
        expect(server.lastIfRange, server.etag);
        expect(File(entry.filePath).readAsStringSync(), 'fresh-content');
      },
    );

    test(
      'restarts from byte zero when a resume request receives HTTP 416',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        server.payload = utf8.encode('short');
        server.supportRanges = true;
        final cacheDir = Directory(
          path.join(tempDir.path, source.cacheDirectoryName),
        )..createSync(recursive: true);
        File(
          path.join(cacheDir.path, 'tiny.gguf.part'),
        ).writeAsStringSync('stale-partial');
        File(path.join(cacheDir.path, 'tiny.gguf.part.json')).writeAsStringSync(
          '${jsonEncode(<String, Object?>{'etag': server.etag})}\n',
        );

        final entry = await manager.ensureModel(source);

        expect(server.requestCount, 2);
        expect(server.rangeHistory, <String?>['bytes=13-', null]);
        expect(File(entry.filePath).readAsStringSync(), 'short');
        expect(
          File(path.join(cacheDir.path, 'tiny.gguf.part.json')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'restarts stale partial downloads when resume validators mismatch',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
        server.payload = utf8.encode('fresh-content');
        server.supportRanges = true;
        server.etag = '"new-etag"';
        final cacheDir = Directory(
          path.join(tempDir.path, source.cacheDirectoryName),
        )..createSync(recursive: true);
        File(
          path.join(cacheDir.path, 'tiny.gguf.part'),
        ).writeAsStringSync('stale');
        File(path.join(cacheDir.path, 'tiny.gguf.part.json')).writeAsStringSync(
          '${jsonEncode(<String, Object?>{'etag': '"old-etag"'})}\n',
        );

        final entry = await manager.ensureModel(source);

        expect(server.requestCount, 2);
        expect(server.lastRange, isNull);
        expect(File(entry.filePath).readAsStringSync(), 'fresh-content');
      },
    );

    test('cancellation leaves no completed cache entry or metadata', () async {
      final manager = DefaultModelDownloadManager(
        defaultCacheDirectory: tempDir.path,
      );
      final source = ModelSource.url(server.modelUri, fileName: 'tiny.gguf');
      server.payload = List<int>.generate(64 * 1024, (index) => index % 251);
      final token = ModelDownloadCancelToken();

      await expectLater(
        manager.ensureModel(
          source,
          options: ModelLoadOptions(cancelToken: token),
          onProgress: (event) {
            if (event.receivedBytes > 0) {
              token.cancel();
            }
          },
        ),
        throwsA(isA<LlamaStateException>()),
      );

      final cacheDir = Directory(
        path.join(tempDir.path, source.cacheDirectoryName),
      );
      expect(File(path.join(cacheDir.path, 'tiny.gguf')).existsSync(), isFalse);
      expect(
        File(path.join(cacheDir.path, 'metadata.json')).existsSync(),
        isFalse,
      );
    });

    test(
      'list, get, remove, clear, and prune operate on persisted metadata',
      () async {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );
        server.payload = utf8.encode('first');
        final firstSource = ModelSource.url(
          server.modelUri,
          fileName: 'first.gguf',
        );
        final first = await manager.ensureModel(firstSource);

        server.payload = utf8.encode('second');
        final secondSource = ModelSource.url(
          server.modelUri.replace(queryParameters: <String, String>{'id': '2'}),
          fileName: 'second.gguf',
        );
        final second = await manager.ensureModel(secondSource);

        expect(
          (await manager.list()).map((entry) => entry.cacheKey),
          containsAll(<String>[first.cacheKey, second.cacheKey]),
        );
        expect((await manager.get(first.cacheKey))?.fileName, 'first.gguf');

        await manager.remove(first.cacheKey);
        expect(await manager.get(first.cacheKey), isNull);
        expect(File(first.filePath).existsSync(), isFalse);
        expect(await manager.get(second.cacheKey), isNotNull);

        final secondMetadataFile = File(
          path.join(path.dirname(second.filePath), 'metadata.json'),
        );
        final secondMetadata = Map<String, Object?>.from(
          jsonDecode(secondMetadataFile.readAsStringSync()) as Map,
        );
        secondMetadata.remove('bytes');
        secondMetadataFile.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(secondMetadata)}\n',
        );

        final pruned = await manager.prune(maxBytes: 1);
        expect(
          pruned.map((entry) => entry.cacheKey),
          contains(second.cacheKey),
        );
        expect(await manager.list(), isEmpty);

        final third = await manager.ensureModel(
          firstSource,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
        );
        expect(File(third.filePath).existsSync(), isTrue);
        await manager.clear();
        expect(await manager.list(), isEmpty);
        expect(
          Directory(
            path.join(tempDir.path, firstSource.cacheDirectoryName),
          ).existsSync(),
          isFalse,
        );
      },
    );
  });
}

class _ModelHttpFixture {
  _ModelHttpFixture._(this._server);

  final HttpServer _server;
  List<int> payload = utf8.encode('model-bytes');
  bool supportRanges = false;
  String? etag = '"fixture-v1"';
  int failuresBeforeSuccess = 0;
  int failureStatusCode = HttpStatus.internalServerError;
  Uri? redirectTo;
  int requestCount = 0;
  int activeRequests = 0;
  int maxActiveRequests = 0;
  Duration responseDelay = Duration.zero;
  final Completer<void> _firstRequestStarted = Completer<void>();
  String? lastRange;
  final rangeHistory = <String?>[];
  String? lastIfRange;
  String? lastAuthorization;
  String? lastTestHeader;

  Uri get modelUri => Uri.parse(
    'http://127.0.0.1:${_server.port}/models/tiny.gguf?download=true',
  );

  static Future<_ModelHttpFixture> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _ModelHttpFixture._(server);
    server.listen(fixture._handleRequest);
    return fixture;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> get firstRequestStarted => _firstRequestStarted.future;

  void _handleRequest(HttpRequest request) async {
    requestCount += 1;
    final requestNumber = requestCount;
    activeRequests += 1;
    if (activeRequests > maxActiveRequests) {
      maxActiveRequests = activeRequests;
    }
    if (!_firstRequestStarted.isCompleted) {
      _firstRequestStarted.complete();
    }
    try {
      final requestRange = request.headers.value(HttpHeaders.rangeHeader);
      final requestIfRange = request.headers.value(HttpHeaders.ifRangeHeader);
      final requestAuthorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      final requestTestHeader = request.headers.value('X-Test-Header');
      lastRange = requestRange;
      rangeHistory.add(requestRange);
      lastIfRange = requestIfRange;
      lastAuthorization = requestAuthorization;
      lastTestHeader = requestTestHeader;

      final currentEtag = etag;
      if (currentEtag != null) {
        request.response.headers.set(HttpHeaders.etagHeader, currentEtag);
      }

      if (responseDelay > Duration.zero) {
        await Future<void>.delayed(responseDelay);
      }

      final redirectTarget = redirectTo;
      if (redirectTarget != null) {
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          redirectTarget.toString(),
        );
        await request.response.close();
        return;
      }

      if (requestNumber <= failuresBeforeSuccess) {
        request.response.statusCode = failureStatusCode;
        await request.response.close();
        return;
      }

      final range = requestRange;
      if (supportRanges && range != null && range.startsWith('bytes=')) {
        final startText = range.substring('bytes='.length).split('-').first;
        final start = int.parse(startText);
        if (start >= payload.length) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */${payload.length}',
          );
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${payload.length - 1}/${payload.length}',
        );
        request.response.headers.contentLength = payload.length - start;
        request.response.add(payload.sublist(start));
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentLength = payload.length;
        request.response.add(payload);
      }
      await request.response.close();
    } finally {
      activeRequests -= 1;
    }
  }
}
