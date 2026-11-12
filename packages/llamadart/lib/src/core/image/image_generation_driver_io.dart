import 'dart:isolate';
import 'dart:typed_data';

import '../../backends/stable_diffusion/stable_diffusion_image_worker.dart';
import '../../backends/stable_diffusion/stable_diffusion_memory.dart';
import '../../backends/stable_diffusion/stable_diffusion_runtime_io.dart';
import '../../backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import '../llama_logging.dart';
import '../models/config/log_level.dart';
import 'image_generation_driver.dart';

/// Probes the runtime, recording its log at a level.
typedef ImageRuntimeProbe =
    StableDiffusionRuntimeStatus Function({LlamaLogLevel logLevel});

/// Reads the memory of every GPU, recording the runtime's log at a level.
typedef ImageGpuMemoryReader =
    List<StableDiffusionGpuMemory>? Function({LlamaLogLevel logLevel});

/// Creates the driver for the bundled stable_diffusion runtime.
///
/// [probe] and [readGpuMemory] run in a short-lived isolate, so they have to
/// be top-level or static functions; tests replace them.
ImageGenerationDriver createImageGenerationDriver({
  ImageRuntimeProbe probe = probeStableDiffusionRuntime,
  ImageGpuMemoryReader readGpuMemory = readStableDiffusionGpuMemory,
}) => _NativeImageGenerationDriver(probe, readGpuMemory);

/// The level the runtime records its messages at. They reach the app
/// through `LlamaLogger`, so one has to pass both [LlamaLogging.nativeLevel]
/// and [LlamaLogging.level]: the runtime records from the stricter of the
/// two, and nothing when either is [LlamaLogLevel.none].
LlamaLogLevel imageRuntimeLogLevel() {
  final dart = LlamaLogging.level;
  final native = LlamaLogging.nativeLevel;
  if (dart == LlamaLogLevel.none || native == LlamaLogLevel.none) {
    return LlamaLogLevel.none;
  }
  return dart.index > native.index ? dart : native;
}

class _NativeImageGenerationDriver implements ImageGenerationDriver {
  const _NativeImageGenerationDriver(this._probe, this._readGpuMemory);

  final ImageRuntimeProbe _probe;
  final ImageGpuMemoryReader _readGpuMemory;

  @override
  String get operatingSystem => stableDiffusionHostOperatingSystem();

  @override
  bool get isMacosX64 => stableDiffusionHostIsMacosX64();

  @override
  Future<StableDiffusionRuntimeStatus> probeInBackground() {
    final probe = _probe;
    final logLevel = imageRuntimeLogLevel();
    return Isolate.run(() => probe(logLevel: logLevel));
  }

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
  }) async {
    if (device != ImageGenerationComputeDevice.otherGpu) {
      return (
        refuse: readStableDiffusionMemoryBudget(device: device),
        slower: null,
      );
    }
    return stableDiffusionGpuMemoryLimits(
      gpus,
      runtimePicksGpu: runtimePicksGpu,
      hostBudget: readStableDiffusionMemoryBudget,
    );
  }

  @override
  Future<List<StableDiffusionGpuMemory>?> readGpuMemory() {
    final readGpuMemory = _readGpuMemory;
    final logLevel = imageRuntimeLogLevel();
    // The first query in a process initializes the GPU backend.
    return Isolate.run(() => readGpuMemory(logLevel: logLevel));
  }

  @override
  Future<ImageGenerationSession> start(ImageGenerationSessionConfig config) =>
      StableDiffusionImageWorker.start(
        config,
        logLevel: imageRuntimeLogLevel(),
      );
}
