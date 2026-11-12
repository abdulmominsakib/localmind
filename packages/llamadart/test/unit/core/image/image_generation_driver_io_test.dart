@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:llamadart/src/core/image/image_generation_driver_io.dart';
import 'package:llamadart/src/core/llama_logging.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';

/// Set in the test isolate only: an isolate the driver spawns starts with the
/// initial value.
String _isolate = 'spawned';

StableDiffusionRuntimeStatus _probeNamingItsIsolate({
  LlamaLogLevel logLevel = LlamaLogLevel.none,
}) => StableDiffusionRuntimeStatus.unavailable(
  LlamaUnsupportedException('$_isolate isolate, log level ${logLevel.name}'),
);

List<StableDiffusionGpuMemory>? _gpuMemoryNamingItsIsolate({
  LlamaLogLevel logLevel = LlamaLogLevel.none,
}) => [
  (
    name: '$_isolate isolate, log level ${logLevel.name}',
    totalBytes: 8 << 30,
    freeBytes: 6 << 30,
    integrated: false,
  ),
];

List<StableDiffusionGpuMemory>? _twoGpus({
  LlamaLogLevel logLevel = LlamaLogLevel.none,
}) => [
  (name: 'Vulkan0', totalBytes: 4 << 30, freeBytes: 3 << 30, integrated: false),
  (
    name: 'Vulkan1',
    totalBytes: 24 << 30,
    freeBytes: 20 << 30,
    integrated: false,
  ),
];

List<StableDiffusionGpuMemory>? _integratedOnly({
  LlamaLogLevel logLevel = LlamaLogLevel.none,
}) => [
  (
    name: 'Vulkan0 (Intel Xe)',
    totalBytes: 16 << 30,
    freeBytes: 12 << 30,
    integrated: true,
  ),
];

List<StableDiffusionGpuMemory>? _integratedAndDiscrete({
  LlamaLogLevel logLevel = LlamaLogLevel.none,
}) => [..._integratedOnly(logLevel: logLevel)!, ..._twoGpus()!.take(1)];

/// Answers only in an isolate the driver spawns.
List<StableDiffusionGpuMemory>? _discreteInSpawnedIsolate({
  LlamaLogLevel logLevel = LlamaLogLevel.none,
}) => _isolate == 'spawned' ? _twoGpus() : null;

List<StableDiffusionGpuMemory>? _noGpuMemory({
  LlamaLogLevel logLevel = LlamaLogLevel.none,
}) => null;

void main() {
  setUp(() => _isolate = 'calling');

  tearDown(
    () => applyLogLevels(dart: LlamaLogLevel.none, native: LlamaLogLevel.none),
  );

  test('reports the host operating system', () {
    expect(
      createImageGenerationDriver().operatingSystem,
      Platform.operatingSystem,
    );
    expect(
      createImageGenerationDriver().isMacosX64,
      Abi.current() == Abi.macosX64,
    );
  });

  test('sizes regular files only', () async {
    final directory = await Directory.systemTemp.createTemp('llamadart-img-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/model.gguf')
      ..writeAsBytesSync(List.filled(1234, 0));
    final driver = createImageGenerationDriver();

    expect(driver.fileSize(file.path), 1234);
    expect(driver.fileSize(directory.path), isNull);
    expect(driver.fileSize('${directory.path}/missing.gguf'), isNull);
  });

  test(
    'probes the host runtime, which the root package does not bundle',
    () async {
      final status = await createImageGenerationDriver().probeInBackground();

      expect(status.isAvailable, isFalse);
      expect(status.unavailableReason?.message, contains('stable_diffusion'));
    },
  );

  test('the probe runs in another isolate', () async {
    final driver = createImageGenerationDriver(probe: _probeNamingItsIsolate);

    expect(
      (await driver.probeInBackground()).unavailableReason?.message,
      startsWith('spawned isolate'),
    );
  });

  test('the runtime records its log at the stricter of the two configured '
      'levels, and not at all when either is none', () async {
    final driver = createImageGenerationDriver(
      probe: _probeNamingItsIsolate,
      readGpuMemory: _gpuMemoryNamingItsIsolate,
    );

    for (final (dart, native, expected) in [
      (LlamaLogLevel.none, LlamaLogLevel.none, LlamaLogLevel.none),
      (LlamaLogLevel.debug, LlamaLogLevel.none, LlamaLogLevel.none),
      (LlamaLogLevel.none, LlamaLogLevel.debug, LlamaLogLevel.none),
      (LlamaLogLevel.debug, LlamaLogLevel.warn, LlamaLogLevel.warn),
      (LlamaLogLevel.error, LlamaLogLevel.info, LlamaLogLevel.error),
      (LlamaLogLevel.info, LlamaLogLevel.info, LlamaLogLevel.info),
    ]) {
      await applyLogLevels(dart: dart, native: native);
      final reason = '${dart.name}/${native.name}';

      expect(imageRuntimeLogLevel(), expected, reason: reason);
      expect(
        (await driver.probeInBackground()).unavailableReason?.message,
        endsWith('log level ${expected.name}'),
        reason: reason,
      );
      expect(
        (await driver.memoryLimits(
          ImageGenerationComputeDevice.otherGpu,
          runtimePicksGpu: true,
          gpus: await driver.readGpuMemory(),
        )).slower?.source,
        contains('log level ${expected.name}'),
        reason: reason,
      );
    }
  });

  test('the CPU and Metal refuse above their budget on macOS and Linux '
      'hosts and have nothing slower, and other GPUs have no limit on a host '
      'without the runtime', () async {
    final driver = createImageGenerationDriver();

    for (final device in [
      ImageGenerationComputeDevice.cpu,
      ImageGenerationComputeDevice.metal,
    ]) {
      final limits = await driver.memoryLimits(device, runtimePicksGpu: true);
      if (Platform.isMacOS || Platform.isLinux) {
        expect(limits.refuse, isNotNull);
        expect(limits.refuse!.bytes, greaterThan(0));
      } else if (Platform.isWindows) {
        expect(limits.refuse, isNull);
      }
      expect(limits.slower, isNull);
    }
    expect(
      await driver.memoryLimits(
        ImageGenerationComputeDevice.otherGpu,
        runtimePicksGpu: true,
      ),
      (refuse: null, slower: null),
    );
  });

  test('asks another GPU for its memory in another isolate: slower above '
      'its free memory, refused above that plus host memory where the host '
      'reads it', () async {
    final driver = createImageGenerationDriver(
      readGpuMemory: _gpuMemoryNamingItsIsolate,
    );

    final limits = await driver.memoryLimits(
      ImageGenerationComputeDevice.otherGpu,
      runtimePicksGpu: true,
      gpus: await driver.readGpuMemory(),
    );
    final host = (await driver.memoryLimits(
      ImageGenerationComputeDevice.cpu,
      runtimePicksGpu: true,
    )).refuse;

    expect(limits.slower?.bytes, 6 << 30);
    expect(
      limits.slower?.source,
      contains('free GPU memory of spawned isolate'),
    );
    if (Platform.isMacOS || Platform.isLinux) {
      // MemAvailable on Linux moves between the two reads.
      expect(
        limits.refuse!.bytes,
        closeTo((6 << 30) + host!.bytes, Platform.isLinux ? 1 << 30 : 0),
      );
      expect(limits.refuse!.source, endsWith(host.source));
    } else if (Platform.isWindows) {
      expect(limits.refuse, isNull);
    }
  });

  test('with two GPUs the driver passes on whether the runtime picks the '
      'one it computes on', () async {
    final driver = createImageGenerationDriver(readGpuMemory: _twoGpus);

    Future<ImageGenerationMemoryBudget?> slower({
      required bool runtimePicksGpu,
    }) async => (await driver.memoryLimits(
      ImageGenerationComputeDevice.otherGpu,
      runtimePicksGpu: runtimePicksGpu,
      gpus: await driver.readGpuMemory(),
    )).slower;

    expect((await slower(runtimePicksGpu: true))?.bytes, 20 << 30);
    expect((await slower(runtimePicksGpu: false))?.bytes, 3 << 30);
  });

  test('a GPU whose memory is not known has no limit, and the CPU and '
      'Metal limits do not ask it', () async {
    final driver = createImageGenerationDriver(readGpuMemory: _noGpuMemory);

    expect(
      await driver.memoryLimits(
        ImageGenerationComputeDevice.otherGpu,
        runtimePicksGpu: true,
        gpus: await driver.readGpuMemory(),
      ),
      (refuse: null, slower: null),
    );

    final unasked = createImageGenerationDriver(
      readGpuMemory: _gpuMemoryNamingItsIsolate,
    );
    for (final device in [
      ImageGenerationComputeDevice.cpu,
      ImageGenerationComputeDevice.metal,
    ]) {
      expect(
        (await unasked.memoryLimits(
          device,
          runtimePicksGpu: true,
        )).refuse?.source,
        isNot(contains('isolate')),
      );
    }
  });

  test('reads the GPU memory in another isolate; an unknown list is no '
      'answer', () async {
    expect(
      await createImageGenerationDriver(
        readGpuMemory: _discreteInSpawnedIsolate,
      ).readGpuMemory(),
      hasLength(2),
    );
    expect(
      (await createImageGenerationDriver(
        readGpuMemory: _integratedAndDiscrete,
      ).readGpuMemory())?.map((gpu) => gpu.integrated),
      [true, false],
    );
    expect(
      await createImageGenerationDriver(
        readGpuMemory: _noGpuMemory,
      ).readGpuMemory(),
      isNull,
    );
  });
}
