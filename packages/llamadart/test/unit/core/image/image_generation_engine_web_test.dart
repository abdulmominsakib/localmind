@TestOn('browser')
library;

import 'package:test/test.dart';

import 'package:llamadart/llamadart.dart';

void main() {
  test(
    'checkRuntime reports image generation unsupported on the web',
    () async {
      final capabilities = await ImageGenerationEngine.checkRuntime();

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('web'));
    },
  );

  test('load throws LlamaUnsupportedException on the web before anything '
      'downloads', () async {
    final downloads = _RecordingDownloads();

    for (final model in [
      ImageGenerationModel(ModelSource.parse('hf://owner/sdxs@main/sdxs.gguf')),
      ImageGenerationModel(
        ModelSource.path('flux.gguf'),
        components: [ImageModelComponent.auto(ModelSource.path('ae.gguf'))],
      ),
    ]) {
      await expectLater(
        ImageGenerationEngine.load(
          model,
          store: ModelFileStore(downloadManager: downloads),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('not available on the web'),
          ),
        ),
      );
    }
    expect(downloads.requested, isEmpty);
  });

  test(
    'explicit conditioning capacity cannot enable the Web runtime',
    () async {
      final downloads = _RecordingDownloads();
      for (final capacity in [0, 1, ImageConditioningCacheParams.maxCapacity]) {
        await expectLater(
          ImageGenerationEngine.load(
            ImageGenerationModel(
              ModelSource.parse('https://example.com/sdxs.gguf'),
            ),
            params: ImageConditioningCacheParams(capacity: capacity),
            store: ModelFileStore(downloadManager: downloads),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }
      expect(downloads.requested, isEmpty);
    },
  );

  test('no module placement enables the Web runtime', () async {
    final downloads = _RecordingDownloads();
    for (final placement in [
      const ImageModelPlacement(textEncoderOnCpu: true),
      const ImageModelPlacement(vaeOnCpu: true),
      const ImageModelPlacement(maxGpuMemoryGiB: 4),
      const ImageModelPlacement(autoFit: false),
    ]) {
      await expectLater(
        ImageGenerationEngine.load(
          ImageGenerationModel(
            ModelSource.parse('https://example.com/sdxs.gguf'),
          ),
          placement: placement,
          store: ModelFileStore(downloadManager: downloads),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('not available on the web'),
          ),
        ),
      );
    }
    expect(downloads.requested, isEmpty);
  });
}

final class _RecordingDownloads extends ThrowingModelDownloadManager {
  final List<ModelSource> requested = [];

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) {
    requested.add(source);
    return super.ensureModel(source, options: options, onProgress: onProgress);
  }
}
