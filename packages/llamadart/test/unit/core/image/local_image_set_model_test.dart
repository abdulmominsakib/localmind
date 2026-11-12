import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/image/local_image_set_model.dart';
import 'package:test/test.dart';

void main() {
  test('public factory rejects empty paths with a typed argument error', () {
    final valid = {
      'model.safetensors.index.json': 'a' * 64,
      'model-00001-of-00001.safetensors': 'b' * 64,
    };
    expect(
      () => ImageGenerationModel.localSafetensorsSet(
        '',
        sha256: valid,
        cacheDirectory: 'private-cache',
      ),
      throwsA(isA<LlamaArgumentException>()),
    );
  });
  test(
    'public factory preserves typed URL and empty cache refusal without echo',
    () {
      final valid = {
        'model.safetensors.index.json': 'a' * 64,
        'model-00001-of-00001.safetensors': 'b' * 64,
      };
      expect(
        () => ImageGenerationModel.localSafetensorsSet(
          'https://PRIVATE_PATH_CANARY.invalid/model',
          sha256: valid,
          cacheDirectory: 'private-cache',
        ),
        throwsA(
          isA<LlamaArgumentException>().having(
            (e) => e.message,
            'message',
            isNot(contains('PRIVATE_PATH_CANARY')),
          ),
        ),
      );
      expect(
        () => ImageGenerationModel.localSafetensorsSet(
          'local',
          sha256: valid,
          cacheDirectory: '',
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
    },
  );
  test(
    'public factory owns identity map without changing legacy model interfaces',
    () {
      final values = {
        'model.safetensors.index.json': 'A' * 64,
        'model-00001-of-00002.safetensors': 'b' * 64,
      };
      final model =
          ImageGenerationModel.localSafetensorsSet(
                'local',
                sha256: values,
                cacheDirectory: 'private',
              )
              as LocalImageSetModel;
      values['model-00001-of-00002.safetensors'] = 'c' * 64;
      expect(model.sha256['model-00001-of-00002.safetensors'], 'b' * 64);
      expect(model.sha256['model.safetensors.index.json'], 'a' * 64);
      expect(() => model.sha256.clear(), throwsUnsupportedError);
      expect(model.role, ImageModelRole.checkpoint);
      expect(model.source.path, 'local');
    },
  );
  test('secret-bearing arbitrary shard names are rejected without echo', () {
    expect(
      () => ImageGenerationModel.localSafetensorsSet(
        'local',
        sha256: {
          'model.safetensors.index.json': 'a' * 64,
          'PRIVATE_ALIAS_CANARY.safetensors': 'b' * 64,
        },
        cacheDirectory: 'private',
      ),
      throwsA(
        isA<LlamaArgumentException>().having(
          (e) => e.message,
          'message',
          isNot(contains('PRIVATE_ALIAS_CANARY')),
        ),
      ),
    );
  });
  test('factory rejects incomplete, unsafe or nonhex identity manifests', () {
    for (final values in [
      <String, String>{},
      {'model.safetensors.index.json': '0' * 64},
      {'index.json': 'a' * 64, 'model-00001-of-00002.safetensors': 'b' * 64},
      {
        'model.safetensors.index.json': 'a' * 64,
        '../model-00001-of-00002.safetensors': 'b' * 64,
      },
      {
        'model.safetensors.index.json': 'a' * 64,
        'model-00001-of-00002.safetensors': 'xyz',
      },
    ]) {
      expect(
        () => ImageGenerationModel.localSafetensorsSet(
          'local',
          sha256: values,
          cacheDirectory: 'private',
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
    }
  });
}
