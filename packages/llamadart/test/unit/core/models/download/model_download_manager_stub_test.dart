@TestOn('browser')
library;

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/download/model_download_manager_stub.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultModelDownloadManager stub placeholder', () {
    test('throws unsupported exception for ensureModel', () async {
      const manager = DefaultModelDownloadManager();

      await expectLater(
        manager.ensureModel(ModelSource.path('/models/model.gguf')),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('auto constructor compiles on non-IO platforms', () async {
      const manager = DefaultModelDownloadManager.auto(
        appPrivateCacheDirectory: '/app/models',
        androidAppPrivateCacheDirectory: '/android/models',
        iosAppPrivateCacheDirectory: '/ios/models',
      );

      await expectLater(
        manager.ensureModel(ModelSource.path('/models/model.gguf')),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('default cache directory getter throws unsupported exception', () {
      const manager = DefaultModelDownloadManager.auto(
        appPrivateCacheDirectory: '/app/models',
        androidAppPrivateCacheDirectory: '/android/models',
        iosAppPrivateCacheDirectory: '/ios/models',
      );

      expect(
        () => manager.defaultCacheDirectory,
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('throws unsupported exception for file-backed shared cache root', () {
      expect(
        DefaultModelDownloadManager.defaultSharedCacheDirectory,
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  });
}
