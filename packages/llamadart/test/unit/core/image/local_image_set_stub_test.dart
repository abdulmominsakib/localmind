import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/image/local_image_set_model.dart';
import 'package:llamadart/src/core/image/local_image_set_stub.dart';
import 'package:test/test.dart';

void main() {
  test('non-IO managed set resolution refuses explicitly', () {
    final model =
        ImageGenerationModel.localSafetensorsSet(
              'local',
              sha256: {
                'model.safetensors.index.json': 'a' * 64,
                'model-00001-of-00002.safetensors': 'b' * 64,
              },
              cacheDirectory: 'private',
            )
            as LocalImageSetModel;
    expect(
      () => resolveLocalImageSet(
        model,
        store: ModelFileStore(),
        options: ModelLoadOptions.defaults,
      ),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
}
