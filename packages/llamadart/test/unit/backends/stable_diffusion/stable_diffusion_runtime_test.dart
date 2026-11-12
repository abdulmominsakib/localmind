import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime.dart';
import 'package:llamadart/src/core/exceptions.dart';

void main() {
  // This package's own test build does not opt into stable_diffusion, so the
  // platform probe must report it as unusable, never as a crash.
  test('the platform probe reports an unbundled runtime as unsupported', () {
    final status = probeStableDiffusionRuntime();

    expect(status.isAvailable, isFalse);
    expect(
      status.unavailableReason,
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        anyOf(
          contains('stable_diffusion runtime is not bundled'),
          contains('stable_diffusion runtime is not published'),
          contains('stable_diffusion runtime is not available on the web'),
        ),
      ),
    );
  });
}
