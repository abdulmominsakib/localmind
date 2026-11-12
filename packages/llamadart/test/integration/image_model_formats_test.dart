@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_image_worker.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_memory.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_stable_diffusion_runtime.dart';
import '../support/image_model_headers.dart';

// Header fixtures exercise real file resolution and the worker's native
// parameter writes. The recording runtime does not validate tensor payloads
// or establish model/dtype compatibility.
void main() {
  late Directory directory;
  late FakeStableDiffusionRuntime runtime;
  late _RecordingDriver driver;
  final engines = <ImageGenerationEngine>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('image-formats-');
    runtime = FakeStableDiffusionRuntime();
    driver = _RecordingDriver(runtime);
    debugImageGenerationDriverOverride = driver;
    StableDiffusionImageWorker.debugResetLogPositionForTesting();
  });

  tearDown(() async {
    for (final engine in engines) {
      await engine.dispose();
    }
    engines.clear();
    debugImageGenerationDriverOverride = null;
    runtime.close();
    await directory.delete(recursive: true);
  });

  Future<ModelSource> file(String name, List<int> bytes) async {
    final target = File(p.join(directory.path, name));
    await target.writeAsBytes(bytes);
    return ModelSource.path(target.path);
  }

  Future<ImageGenerationEngine> load(ImageGenerationModel model) async {
    final engine = await ImageGenerationEngine.load(
      model,
      params: const ImageModelParams(device: ComputeDevice.cpu),
    );
    engines.add(engine);
    return engine;
  }

  for (final (format, header) in [
    ('GGUF', ImageModelHeaders.sdTurboCheckpoint),
    ('Safetensors', ImageModelHeaders.sdxlCheckpoint),
  ]) {
    for (final name in ['model.gguf', 'model.safetensors', 'weights']) {
      test('$format checkpoint reaches native model_path as $name', () async {
        final source = await file(name, header);
        final engine = await load(ImageGenerationModel(source));

        expect(engine.roles, {ImageModelRole.checkpoint: source});
        expect(runtime.loadedFiles, {'model': source.path});
        expect(driver.starts, 1);
      });
    }
  }

  test('mixed split components retain their paths across the worker', () async {
    final diffusion = await file('diffusion', ImageModelHeaders.fluxDiffusion);
    final vae = await file('vae.gguf', ImageModelHeaders.fluxVae);
    final clip = await file('clip.safetensors', ImageModelHeaders.clipL);
    final t5 = await file('t5', ImageModelHeaders.t5xxl);
    final engine = await load(
      ImageGenerationModel(
        t5,
        components: [
          ImageModelComponent.auto(vae),
          ImageModelComponent.auto(diffusion),
          ImageModelComponent.auto(clip),
        ],
      ),
    );

    expect(engine.roles, {
      ImageModelRole.t5xxl: t5,
      ImageModelRole.vae: vae,
      ImageModelRole.diffusionModel: diffusion,
      ImageModelRole.clipL: clip,
    });
    expect(runtime.loadedFiles, {
      'diffusionModel': diffusion.path,
      'vae': vae.path,
      'clipL': clip.path,
      't5xxl': t5.path,
    });
  });

  for (final (name, header, components) in [
    (
      'SD-Turbo',
      ImageModelHeaders.sdTurboCheckpoint,
      {'taesd': ImageModelHeaders.taesd},
    ),
    (
      'SD 3.5',
      ImageModelHeaders.sd35Diffusion,
      {
        'vae': ImageModelHeaders.fluxVae,
        'clipL': ImageModelHeaders.clipL,
        'clipG': ImageModelHeaders.clipG,
        't5xxl': ImageModelHeaders.t5xxl,
      },
    ),
    (
      'Z-Image',
      ImageModelHeaders.zImageDiffusion,
      {'vae': ImageModelHeaders.fluxVae, 'llm': ImageModelHeaders.qwen3Llm},
    ),
  ]) {
    test('$name component roles reach their native path fields', () async {
      final main = await file('weights', header);
      final files = <String, String>{
        name == 'SD-Turbo' ? 'model' : 'diffusionModel': main.path!,
      };
      final sources = <ImageModelComponent>[];
      for (final MapEntry(key: role, value: bytes) in components.entries) {
        final source = await file(role, bytes);
        sources.add(ImageModelComponent.auto(source));
        files[role] = source.path!;
      }

      await load(ImageGenerationModel(main, components: sources));
      expect(runtime.loadedFiles, files);
    });
  }

  for (final extension in ['ckpt', 'pth', 'pt']) {
    test(
      'explicit .$extension role still permits native refusal and reuse',
      () async {
        // Inert signature bytes only: no pickle or Python code is executed.
        final source = await file('model.$extension', ImageModelHeaders.pickle);
        await expectLater(
          load(ImageGenerationModel(source)),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              contains('Cannot detect the role of the main file'),
            ),
          ),
        );
        expect(driver.starts, 0);

        runtime.rejectLoad = true;
        await expectLater(
          load(ImageGenerationModel(source, role: ImageModelRole.checkpoint)),
          throwsA(
            isA<LlamaModelException>()
                .having(
                  (error) => error.details,
                  'details',
                  'files: checkpoint',
                )
                .having(
                  (error) => '$error',
                  'redacted error',
                  isNot(contains(directory.path)),
                ),
          ),
        );
        expect(driver.starts, 1);
        expect(runtime.loadedFiles, {'model': source.path});

        runtime.rejectLoad = false;
        final supported = await file(
          'supported',
          ImageModelHeaders.sdxlCheckpoint,
        );
        await load(ImageGenerationModel(supported));
        expect(runtime.loadedFiles, {'model': supported.path});
      },
    );
  }

  for (final (name, bytes) in [
    ('lora.gguf', ImageModelHeaders.lora),
    ('decoder.safetensors', ImageModelHeaders.decoderOnlyTaesd),
    ('truncated.safetensors', Uint8List.fromList([32, 0, 0, 0, 0, 0, 0, 0])),
    ('unknown.gguf', ggufHeader(metadata: {'general.architecture': 'unknown'})),
    (
      'model.safetensors.index.json',
      utf8.encode('{"weight_map":{"a":"part.safetensors"}}'),
    ),
  ]) {
    test('$name is not admitted by its extension', () async {
      final source = await file(name, bytes);

      await expectLater(
        load(ImageGenerationModel(source)),
        throwsA(isA<LlamaModelException>()),
      );
      expect(driver.starts, 0);
    });
  }

  test('a ControlNet loaded through the real worker reports engine '
      'ControlNet support only when the runtime proves it', () async {
    driver
      ..operatingSystemOverride = 'macos'
      ..runtimeCommit = 'be48649';
    runtime.modelVersion = 'SD 1.x';
    final checkpoint = await file(
      'sd15.safetensors',
      ImageModelHeaders.sd15Checkpoint(),
    );
    final controlNet = await file(
      'canny.safetensors',
      ImageModelHeaders.sd15ControlNet(),
    );
    final model = ImageGenerationModel(
      checkpoint,
      components: [ImageModelComponent.auto(controlNet)],
    );
    const params = ImageModelParams(
      device: ComputeDevice.cpu,
      flashAttention: false,
      vaeDirectConvolution: false,
    );

    final engine = await ImageGenerationEngine.load(model, params: params);
    engines.add(engine);
    expect((await engine.capabilities).supportsControlNet, isTrue);
    expect(runtime.loadedFiles['controlNet'], controlNet.path);

    runtime.hideControlNet = true;
    await expectLater(
      ImageGenerationEngine.load(model, params: params),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });

  test('a directory cannot bypass the individual-file contract', () async {
    await expectLater(
      load(ImageGenerationModel(ModelSource.path(directory.path))),
      throwsA(isA<LlamaModelException>()),
    );
    expect(driver.starts, 0);
  });
}

final class _RecordingDriver implements ImageGenerationDriver {
  _RecordingDriver(this.runtime);

  final FakeStableDiffusionRuntime runtime;
  int starts = 0;
  String? operatingSystemOverride;
  String runtimeCommit = 'fixture';

  @override
  String get operatingSystem =>
      operatingSystemOverride ?? Platform.operatingSystem;

  @override
  bool get isMacosX64 => false;

  @override
  Future<StableDiffusionRuntimeStatus> probeInBackground() async =>
      StableDiffusionRuntimeStatus.available(
        version: 'recording-runtime',
        commit: runtimeCommit,
        devices: parseStableDiffusionDeviceList('CPU\tRecording runtime\n'),
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
