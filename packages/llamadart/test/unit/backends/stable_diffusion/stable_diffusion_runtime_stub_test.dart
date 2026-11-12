import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_stub.dart';
import 'package:llamadart/src/core/exceptions.dart';

void main() {
  test('the web probe reports an unsupported runtime without loading', () {
    final status = probeStableDiffusionRuntime();

    expect(status.isAvailable, isFalse);
    expect(
      status.throwIfUnavailable,
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          allOf(contains('stable_diffusion'), contains('web')),
        ),
      ),
    );
  });
}
