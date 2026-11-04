import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('model resolver value models', () {
    test('LocalModelFile exposes path for engine/backend dispatch', () {
      const target = LocalModelFile('/models/model.gguf');

      expect(target.path, '/models/model.gguf');
      expect(target.isLocal, isTrue);
      expect(target.isRemote, isFalse);
    });

    test('RemoteModelUrl exposes URL for engine/backend dispatch', () {
      final url = Uri.parse('https://host/model.gguf');
      final target = RemoteModelUrl(url, useBrowserCache: false);

      expect(target.url, url);
      expect(target.useBrowserCache, isFalse);
      expect(target.isLocal, isFalse);
      expect(target.isRemote, isTrue);
    });

    test('ModelLoadOptions defaults prefer cached policy', () {
      final options = ModelLoadOptions.defaults;

      expect(options.cachePolicy, ModelCachePolicy.preferCached);
      expect(options.headers, isEmpty);
      expect(options.resume, isTrue);
      expect(options.maxRetries, 3);
    });

    test(
      'DefaultModelResolver resolves local paths to local file targets',
      () async {
        const resolver = DefaultModelResolver();
        final target = await resolver.resolve(
          ModelSource.path('/models/model.gguf'),
          const ModelResolveRequest(options: ModelLoadOptions.defaults),
        );

        expect(target, isA<LocalModelFile>());
        expect((target as LocalModelFile).path, '/models/model.gguf');
      },
    );

    test('DefaultModelResolver throws LlamaStateException when cancelled', () {
      const resolver = DefaultModelResolver();
      final cancelToken = ModelDownloadCancelToken()..cancel();

      expect(
        () => resolver.resolve(
          ModelSource.url(Uri.parse('https://host/model.gguf')),
          ModelResolveRequest(
            options: ModelLoadOptions(cancelToken: cancelToken),
          ),
        ),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test(
      'DefaultModelResolver leaves download/cache options for engine or manager',
      () async {
        const resolver = DefaultModelResolver();
        final source = ModelSource.url(Uri.parse('https://host/model.gguf'));
        final target = await resolver.resolve(
          source,
          ModelResolveRequest(
            options: ModelLoadOptions(
              cachePolicy: ModelCachePolicy.refresh,
              bearerToken: 'token',
              headers: const <String, String>{'x-token': 'token'},
              sha256: List.filled(64, 'a').join(),
              cacheDirectory: '/tmp/cache',
              resume: false,
              maxRetries: 0,
            ),
          ),
        );

        expect(target, isA<RemoteModelUrl>());
        expect((target as RemoteModelUrl).url, source.resolvedUri);
      },
    );
  });
}
