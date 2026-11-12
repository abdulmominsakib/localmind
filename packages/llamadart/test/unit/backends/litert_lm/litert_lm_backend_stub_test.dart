library;

import 'package:llamadart/src/backends/litert_lm/litert_lm_backend_stub.dart';
import 'package:test/test.dart';

void main() {
  test('constructing the stub backend reports the platform requirement', () {
    expect(
      LiteRtLmBackend.new,
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          'LiteRT-LM backend requires a native platform.',
        ),
      ),
    );
  });
}
