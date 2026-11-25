import 'dart:typed_data';

import '../../backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import '../../backends/stable_diffusion/stable_diffusion_runtime_stub.dart';
import 'image_generation_driver.dart';

/// Creates the driver for platforms without native image generation, such as
/// the web. Its probe always reports the runtime unavailable.
ImageGenerationDriver createImageGenerationDriver() =>
    const _UnsupportedImageGenerationDriver();

class _UnsupportedImageGenerationDriver implements ImageGenerationDriver {
  const _UnsupportedImageGenerationDriver();

  @override
  String get operatingSystem => 'web';

  @override
  bool get isMacosX64 => false;

  @override
  Future<StableDiffusionRuntimeStatus> probeInBackground() async =>
      probeStableDiffusionRuntime();

  @override
  int? fileSize(String path) => null;

  @override
  Future<Uint8List> readFileRange(String path, int offset, int length) =>
      Future.error(probeStableDiffusionRuntime().unavailableReason!);

  @override
  Future<ImageGenerationMemoryLimits> memoryLimits(
    ImageGenerationComputeDevice device, {
    required bool runtimePicksGpu,
    List<StableDiffusionGpuMemory>? gpus,
  }) async => (refuse: null, slower: null);

  @override
  Future<List<StableDiffusionGpuMemory>?> readGpuMemory() async => null;

  @override
  Future<ImageGenerationSession> start(ImageGenerationSessionConfig config) =>
      Future.error(probeStableDiffusionRuntime().unavailableReason!);
}
