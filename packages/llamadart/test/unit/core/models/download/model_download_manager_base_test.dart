import 'package:llamadart/src/core/models/download/model_download_manager_base.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:test/test.dart';

void main() {
  group('ModelCachePlatform', () {
    test('parses Platform.operatingSystem values', () {
      expect(ModelCachePlatform.parse('android'), ModelCachePlatform.android);
      expect(ModelCachePlatform.parse('fuchsia'), ModelCachePlatform.fuchsia);
      expect(ModelCachePlatform.parse('ios'), ModelCachePlatform.ios);
      expect(ModelCachePlatform.parse('linux'), ModelCachePlatform.linux);
      expect(ModelCachePlatform.parse('macos'), ModelCachePlatform.macos);
      expect(ModelCachePlatform.parse('windows'), ModelCachePlatform.windows);
      expect(ModelCachePlatform.parse('web'), ModelCachePlatform.web);
      expect(
        ModelCachePlatform.parse('unsupported-os'),
        ModelCachePlatform.unknown,
      );
    });

    test('identifies mobile and implicit shared-cache platforms', () {
      expect(ModelCachePlatform.android.isMobile, isTrue);
      expect(ModelCachePlatform.ios.isMobile, isTrue);
      expect(ModelCachePlatform.linux.isMobile, isFalse);

      expect(ModelCachePlatform.linux.supportsImplicitSharedModelCache, isTrue);
      expect(ModelCachePlatform.macos.supportsImplicitSharedModelCache, isTrue);
      expect(
        ModelCachePlatform.windows.supportsImplicitSharedModelCache,
        isTrue,
      );
      expect(
        ModelCachePlatform.android.supportsImplicitSharedModelCache,
        isFalse,
      );
      expect(ModelCachePlatform.web.supportsImplicitSharedModelCache, isFalse);
    });
  });

  group('ThrowingModelDownloadManager', () {
    test('base placeholder throws for all operations', () async {
      const manager = _TestDownloadManager();
      final source = ModelSource.path('/models/model.gguf');

      await expectLater(manager.ensureModel(source), throwsUnsupportedError);
      await expectLater(manager.list(), throwsUnsupportedError);
      await expectLater(manager.get('abc123'), throwsUnsupportedError);
      await expectLater(manager.remove('abc123'), throwsUnsupportedError);
      await expectLater(manager.clear(), throwsUnsupportedError);
      await expectLater(manager.prune(), throwsUnsupportedError);
    });
  });
}

class _TestDownloadManager extends ThrowingModelDownloadManager {
  const _TestDownloadManager();

  @override
  Object unsupported(String operation) => UnsupportedError(operation);
}
