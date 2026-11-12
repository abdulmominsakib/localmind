@TestOn('vm')
@Tags(['local-only'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_image_worker.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_memory.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:test/test.dart';

import '../../support/fake_stable_diffusion_runtime.dart';

void main() {
  final path = Platform.environment['LLAMADART_IMAGE_FP8_MODEL'];
  test(
    'on a runtime without the FP8 load fix, a real FP8 checkpoint refuses '
    'Metal before construction and forwards CPU',
    () async {
      final runtime = FakeStableDiffusionRuntime();
      final driver = _Driver(runtime);
      debugImageGenerationDriverOverride = driver;
      addTearDown(() async {
        debugImageGenerationDriverOverride = null;
        runtime.close();
      });
      final model = ImageGenerationModel(ModelSource.path(path!));
      for (final device in [ComputeDevice.auto, ComputeDevice.gpu]) {
        await expectLater(
          ImageGenerationEngine.load(
            model,
            params: ImageModelParams(device: device),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'FP8 Metal reason',
              allOf(contains('FP8'), contains('Metal')),
            ),
          ),
        );
        expect(driver.starts, 0);
        await runtime.flush();
        expect(runtime.calls('worker'), isEmpty);
      }
      for (final backend in [null, 'gpu', 'MTL0']) {
        await expectLater(
          StableDiffusionImageWorker.start(
            ImageGenerationSessionConfig(
              files: {'model': path},
              backend: backend,
              threads: 1,
            ),
            resolveCalls: runtime.resolver,
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await runtime.flush();
        expect(runtime.calls('worker'), isEmpty);
      }
      final engine = await ImageGenerationEngine.load(
        model,
        params: const ImageModelParams(
          device: ComputeDevice.cpu,
          checkMemory: false,
        ),
      );
      try {
        expect(driver.starts, 1);
        await runtime.flush();
        expect(runtime.calls('worker'), contains('sd_dart_new_sd_ctx'));
      } finally {
        await engine.dispose();
      }
    },
    skip: path == null || !Platform.isMacOS
        ? 'Set LLAMADART_IMAGE_FP8_MODEL to an existing FP8 checkpoint on macOS.'
        : false,
  );
}

final class _Driver implements ImageGenerationDriver {
  _Driver(this.runtime);
  final FakeStableDiffusionRuntime runtime;
  int starts = 0;
  @override
  String get operatingSystem => 'macos';

  @override
  bool get isMacosX64 => false;
  @override
  Future<StableDiffusionRuntimeStatus> probeInBackground() async =>
      StableDiffusionRuntimeStatus.available(
        version: 'unknown',
        commit: 'be48649',
        devices: parseStableDiffusionDeviceList('MTL0\tMetal\nCPU\tCPU\n'),
      );
  @override
  int? fileSize(String path) => stableDiffusionFileSize(path);
  @override
  Future<Uint8List> readFileRange(String path, int offset, int length) =>
      readStableDiffusionFileRange(path, offset, length);
  @override
  Future<ImageGenerationMemoryLimits> memoryLimits(
    ImageGenerationComputeDevice device, {
    required bool runtimePicksGpu,
    List<StableDiffusionGpuMemory>? gpus,
  }) async => (refuse: null, slower: null);
  @override
  Future<List<StableDiffusionGpuMemory>?> readGpuMemory() async => null;

  @override
  Future<ImageGenerationSession> start(ImageGenerationSessionConfig config) {
    starts++;
    return StableDiffusionImageWorker.start(
      config,
      resolveCalls: runtime.resolver,
    );
  }
}
