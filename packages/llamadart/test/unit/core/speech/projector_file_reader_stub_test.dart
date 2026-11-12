import 'package:llamadart/src/core/speech/projector_file_reader_stub.dart';
import 'package:test/test.dart';

void main() {
  test('the stub reads no projector file', () {
    expect(
      () => readProjectorFileRange('https://example.com/mmproj.gguf', 0, 4),
      throwsUnsupportedError,
    );
  });
}
