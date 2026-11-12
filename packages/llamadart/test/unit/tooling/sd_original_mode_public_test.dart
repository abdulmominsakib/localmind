@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_bindings.dart'
    as sd;
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_params.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../example/basic_app/test/fixtures/image_original_container_model.dart';
import '../../support/image_model_headers.dart';

void main() {
  test(
    'real public diagnostic load maps supported CPU mode and refuses false autoFit',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'sd24-public-model-free-',
      );
      final model = File(path.join(directory.path, 'header.gguf'))
        ..writeAsBytesSync(ImageModelHeaders.sdTurboCheckpoint);
      final taesd = File(path.join(directory.path, 'header.safetensors'))
        ..writeAsBytesSync(ImageModelHeaders.taesd);
      final driver = _RecordingDriver();
      debugImageGenerationDriverOverride = driver;
      ImageGenerationEngine? engine;
      try {
        // This is the same load helper called by the uninjected real child.
        engine = await loadOriginalContainer(model.path, taesd.path);
        final config = driver.started.single;
        expect(config.files, {'model': model.path, 'taesd': taesd.path});
        using((arena) {
          final params = arena<sd.sd_ctx_params_t>();
          params.ref.auto_fit = false;
          applyStableDiffusionContextParams(params, config, arena);
          expect(params.ref.backend.cast<Utf8>().toDartString(), 'cpu');
          expect(params.ref.n_threads, 4);
          expect(params.ref.conditioning_cache_size, 4);
          expect(params.ref.auto_fit, isTrue);
          expect(params.ref.eager_load, isTrue);
          expect(params.ref.batched_cfg, isFalse);
          expect(params.ref.diffusion_flash_attn, isTrue);
          expect(params.ref.vae_conv_direct, isFalse);
          expect(
            params.ref.flash_attn_mode.cast<Utf8>().toDartString(),
            'off,diffusion=on',
          );
          expect(
            params.ref.conv_direct_mode.cast<Utf8>().toDartString(),
            'off',
          );
        });
        await expectLater(
          ImageGenerationEngine.load(
            ImageGenerationModel(
              ModelSource.path(model.path),
              role: ImageModelRole.checkpoint,
              components: [
                ImageModelComponent(
                  ModelSource.path(taesd.path),
                  role: ImageModelRole.taesd,
                ),
              ],
            ),
            params: const ImageConditioningCacheParams(
              capacity: 4,
              device: ComputeDevice.cpu,
              threads: 4,
              flashAttention: true,
              vaeDirectConvolution: false,
            ),
            placement: const ImageModelPlacement(autoFit: false),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(
          driver.started,
          hasLength(1),
          reason: 'false CPU placement cannot start a context',
        );
      } finally {
        await engine?.dispose();
        debugImageGenerationDriverOverride = null;
        directory.deleteSync(recursive: true);
      }
    },
  );
}

final class _RecordingDriver implements ImageGenerationDriver {
  final List<ImageGenerationSessionConfig> started = [];
  @override
  String get operatingSystem => 'macos';

  @override
  bool get isMacosX64 => false;
  @override
  Future<StableDiffusionRuntimeStatus> probeInBackground() async =>
      const StableDiffusionRuntimeStatus.available(
        version: 'fixture',
        commit: 'fixture',
        devices: [
          StableDiffusionDevice(name: 'CPU', description: 'model-free'),
        ],
      );
  @override
  int? fileSize(String path) => File(path).lengthSync();
  @override
  Future<Uint8List> readFileRange(String path, int offset, int length) async {
    final bytes = File(path).readAsBytesSync();
    final start = offset.clamp(0, bytes.length);
    return Uint8List.sublistView(
      bytes,
      start,
      (offset + length).clamp(start, bytes.length),
    );
  }

  @override
  Future<List<StableDiffusionGpuMemory>?> readGpuMemory() async => null;
  @override
  Future<ImageGenerationMemoryLimits> memoryLimits(
    ImageGenerationComputeDevice device, {
    required bool runtimePicksGpu,
    List<StableDiffusionGpuMemory>? gpus,
  }) async => (refuse: null, slower: null);
  @override
  Future<ImageGenerationSession> start(
    ImageGenerationSessionConfig config,
  ) async {
    started.add(config);
    return _RecordingSession();
  }
}

final class _RecordingSession implements ImageGenerationSession {
  @override
  String get modelVersion => 'SD 2.x';
  @override
  Future<List<GeneratedImage>?> generate(
    ImageGenerationSessionRequest request,
    void Function(int step, int steps) onProgress,
  ) => throw UnimplementedError('no inference');
  @override
  void cancel() => throw UnimplementedError('no inference');
  @override
  Future<void> dispose() async {}
}
