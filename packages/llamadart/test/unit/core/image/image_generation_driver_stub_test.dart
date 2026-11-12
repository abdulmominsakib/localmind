import 'package:test/test.dart';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:llamadart/src/core/image/image_generation_driver_stub.dart';

void main() {
  test('reports the runtime unavailable and never starts', () async {
    final driver = createImageGenerationDriver();

    expect(driver.operatingSystem, 'web');
    expect(driver.isMacosX64, isFalse);
    final status = await driver.probeInBackground();
    expect(status.isAvailable, isFalse);
    expect(
      status.unavailableReason?.message,
      contains('not available on the web'),
    );
    expect(driver.fileSize('/models/sdxs.gguf'), isNull);
    await expectLater(
      driver.readFileRange('/models/sdxs.gguf', 0, 8),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    for (final device in ImageGenerationComputeDevice.values) {
      expect(await driver.memoryLimits(device, runtimePicksGpu: true), (
        refuse: null,
        slower: null,
      ));
    }
    expect(await driver.readGpuMemory(), isNull);
    await expectLater(
      driver.start(
        const ImageGenerationSessionConfig(
          files: {'model': '/models/sdxs.gguf'},
          backend: null,
          threads: 0,
        ),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('not available on the web'),
        ),
      ),
    );
  });
}
