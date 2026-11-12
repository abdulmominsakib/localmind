import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:llamadart/src/core/image/image_generation_engine.dart';

import '../../../support/legacy_image_model_params.dart';
import '../../../support/legacy_image_generation_request.dart';
import '../../../support/legacy_image_generation_engine.dart';
import '../../../support/image_model_headers.dart';
import '../../../support/engine_lifecycle_contract.dart';

const _model = '/models/sd-turbo.gguf';
const _taesd = '/models/taesd.safetensors';
const _flux = '/models/flux1-schnell.gguf';
const _ae = '/models/ae.safetensors';
const _clipL = '/models/clip_l.gguf';
const _t5xxl = '/models/t5xxl.gguf';
const _sd15 = '/models/sd15.safetensors';
const _sd2Base = '/models/sd2-context.safetensors';
const _canny = '/models/control_sd15_canny.safetensors';
const _diffusersCanny = '/models/diffusers_canny.safetensors';
const _gib = 1 << 30;

ModelSource _local(String path) => ModelSource.path(path);

final _remote = ModelSource.parse('hf://owner/sdxs@0123abc/sdxs.gguf');
final _remoteTaesd = ModelSource.parse(
  'hf://owner/taesd@0123abc/taesd.safetensors',
);

/// A checkpoint (by default the local SD-Turbo fixture), plus [taesd].
ImageGenerationModel _sdxs([ModelSource? model, ModelSource? taesd]) =>
    ImageGenerationModel(
      model ?? _local(_model),
      components: [if (taesd != null) ImageModelComponent.auto(taesd)],
    );

/// FLUX.1-schnell's four local files, main file first, components in
/// [order] of `ae`, CLIP-L and T5-XXL.
/// An SD 1.x checkpoint (or [base]) with the original-layout ControlNet (or
/// [control]) and any [extra] files.
ImageGenerationModel _controlNetModel({
  String base = _sd15,
  String control = _canny,
  List<ImageModelComponent> extra = const [],
}) => ImageGenerationModel(
  _local(base),
  components: [ImageModelComponent.auto(_local(control)), ...extra],
);

ImageGenerationModel _fluxModel([List<int> order = const [0, 1, 2]]) {
  const parts = [_ae, _clipL, _t5xxl];
  return ImageGenerationModel(
    _local(_flux),
    components: [
      for (final index in order) ImageModelComponent.auto(_local(parts[index])),
    ],
  );
}

void main() {
  late _FakeDriver driver;
  final engines = <ImageGenerationEngine>[];

  late _FakeDownloads downloads;

  Future<ImageGenerationEngine> load(
    ImageGenerationModel model, {
    ImageModelParams params = const ImageModelParams(),
    ImageModelPlacement placement = const ImageModelPlacement(),
    ModelLoadOptions download = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
    ModelResolver? resolver,
  }) async {
    final engine = await ImageGenerationEngine.load(
      model,
      params: params,
      placement: placement,
      download: download,
      onProgress: onProgress,
      store: ModelFileStore(resolver: resolver, downloadManager: downloads),
    );
    engines.add(engine);
    return engine;
  }

  setUp(() {
    driver = _FakeDriver();
    downloads = _FakeDownloads(driver);
    debugImageGenerationDriverOverride = driver;
  });

  tearDown(() async {
    for (final engine in engines) {
      await engine.dispose();
    }
    engines.clear();
    debugImageGenerationDriverOverride = null;
  });

  test('generic lifecycle ownership disposes a loaded image engine', () async {
    final engine = await load(_sdxs());
    final before = await checkEngineLifecycle(engine);
    expect(before.isSupported, isTrue);
  });

  group('FP8 Metal safety', () {
    const tensor = ('model.diffusion_model.weight', <int>[1]);
    final formats = <String, Uint8List>{
      for (final dtype in ['F8_E4M3', 'F8_E5M2'])
        dtype: safetensorsHeader([tensor], dtype: dtype, dataBytes: 1),
      for (final type in [43, 44])
        'GGUF $type': ggufHeader(tensors: [tensor], tensorType: type),
    };
    for (final MapEntry(key: format, value: header) in formats.entries) {
      for (final device in [ComputeDevice.auto, ComputeDevice.gpu]) {
        test(
          '$format ${device.name} refuses before memory or native load',
          () async {
            driver.headers[_model] = header;
            driver.budget = (bytes: 1, source: 'too small');
            await expectLater(
              load(_sdxs(), params: ImageModelParams(device: device)),
              throwsA(
                isA<LlamaUnsupportedException>().having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('FP8'),
                    contains('Metal'),
                    contains('ComputeDevice.cpu'),
                    isNot(contains(_model)),
                  ),
                ),
              ),
            );
            expect(driver.started, isEmpty);
            expect(driver.budgetDevices, isEmpty);
          },
        );
      }
      test('$format explicit CPU forwards the original checkpoint', () async {
        driver.headers[_model] = header;
        await load(
          _sdxs(),
          params: const ImageModelParams(device: ComputeDevice.cpu),
        );
        expect(driver.started.single.files, {'model': _model});
        expect(driver.started.single.backend, 'cpu');
      });
    }
    test(
      'inspects every explicit-role component including LLM GGUF tensors',
      () async {
        for (final role in ImageModelRole.values.where(
          (r) =>
              r != ImageModelRole.checkpoint &&
              r != ImageModelRole.diffusionModel,
        )) {
          const component = '/models/private-component.bin';
          driver.sizes[component] = 1024;
          driver.headers[component] = ggufHeader(
            metadata: {'general.architecture': 'qwen3'},
            tensors: [
              ('token_embd.weight', [1]),
            ],
            tensorType: 43,
          );
          await expectLater(
            load(
              ImageGenerationModel(
                _local(_model),
                components: [
                  ImageModelComponent(_local(component), role: role),
                ],
              ),
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (e) => e.message,
                'FP8 component',
                contains('FP8 image weights in component 1'),
              ),
            ),
          );
          expect(driver.started, isEmpty);
        }
      },
    );
    test('standalone diffusion FP8 is checked before native loading', () async {
      driver.headers[_model] = formats.values.first;
      await expectLater(
        load(
          ImageGenerationModel(
            _local(_model),
            role: ImageModelRole.diffusionModel,
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(driver.started, isEmpty);
    });
    test('automatic CPU selection preserves FP8 loading', () async {
      driver.status = _available('CPU\tCPU\n');
      driver.headers[_model] = formats.values.first;
      await load(_sdxs());
      expect(driver.started.single.backend, 'cpu');
    });
    test('ordinary F16 auto retains the resolved CPU fallback', () async {
      driver.status = _available('CPU\tCPU\n');
      await load(_sdxs());
      expect(driver.started.single.backend, 'cpu');
      expect(driver.started.single.files, {'model': _model});
    });
    test(
      'a GGUF renamed with a JSON suffix retains native format precedence',
      () async {
        const path = '/models/checkpoint.json';
        driver.sizes[path] = 1024;
        driver.headers[path] = ImageModelHeaders.sdTurboCheckpoint;
        await load(ImageGenerationModel(_local(path)));
        expect(driver.started.single.backend, isNull);
        expect(driver.started.single.files, {'model': path});
      },
    );
    group('on a runtime that loads FP8 as F16 on Metal', () {
      setUp(() {
        driver.status = _available(
          'MTL0\tApple M4\nBLAS\tAccelerate\nCPU\tApple M4\n',
          loadsFp8AsF16OnMetal: true,
        );
      });
      for (final MapEntry(key: format, value: header) in formats.entries) {
        for (final device in [ComputeDevice.auto, ComputeDevice.gpu]) {
          test('$format ${device.name} forwards to Metal', () async {
            driver.headers[_model] = header;
            await load(_sdxs(), params: ImageModelParams(device: device));
            expect(driver.started.single.files, {'model': _model});
            expect(
              driver.started.single.backend,
              device == ComputeDevice.gpu ? 'gpu' : isNull,
            );
          });
        }
      }
      test('an uninspectable JSON index forwards to Metal', () async {
        const index = '/models/checkpoint.json';
        driver.sizes[index] = 100;
        driver.headers[index] = Uint8List.fromList([123, 125]);
        await load(
          ImageGenerationModel(_local(index), role: ImageModelRole.checkpoint),
        );
        expect(driver.started.single.files, {'model': index});
        expect(driver.started.single.backend, isNull);
      });
    });
    test('the pinned upstream commit alone does not admit FP8 on Metal, '
        'since a runtime without the fix shares it', () async {
      driver.status = StableDiffusionRuntimeStatus.available(
        version: 'unknown',
        commit: 'be48649',
        devices: parseStableDiffusionDeviceList('MTL0\tApple M4\nCPU\tCPU\n'),
      );
      driver.headers[_model] = formats.values.first;
      await expectLater(
        load(_sdxs()),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(driver.started, isEmpty);
    });
    test('Vulkan keeps native dtype admission', () async {
      driver.operatingSystem = 'linux';
      driver.status = _available('Vulkan0\tGPU\nCPU\tCPU\n');
      driver.headers[_model] = formats.values.first;
      await load(_sdxs());
      expect(driver.started.single.files, {'model': _model});
    });
    test(
      'explicit-role JSON indexes remain CPU-only when dtypes cannot be inspected',
      () async {
        const index = '/models/checkpoint.json';
        driver.sizes[index] = 100;
        driver.headers[index] = Uint8List.fromList([123, 125]);
        final model = ImageGenerationModel(
          _local(index),
          role: ImageModelRole.checkpoint,
        );
        await expectLater(
          load(model),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(driver.started, isEmpty);
        await load(
          model,
          params: const ImageModelParams(device: ComputeDevice.cpu),
        );
        expect(driver.started.single.files, {'model': index});
      },
    );
  });

  test(
    'local set recipe gates precede filesystem, resolver and native load',
    () async {
      final model = ImageGenerationModel.localSafetensorsSet(
        'not-read',
        sha256: {
          'model.safetensors.index.json': 'a' * 64,
          'model-00001-of-00002.safetensors': 'b' * 64,
        },
        cacheDirectory: 'not-created',
      );
      for (final kind in [
        'host',
        'runtime',
        'v0.3.0 runtime',
        'device',
        'flash',
        'direct',
      ]) {
        driver = _FakeDriver();
        downloads = _FakeDownloads(driver);
        debugImageGenerationDriverOverride = driver;
        if (kind == 'host') {
          driver.operatingSystem = 'linux';
        }
        if (kind.endsWith('runtime')) {
          driver.status = StableDiffusionRuntimeStatus.available(
            version: 'unknown',
            // The upstream commit of stable-diffusion-native v0.3.0, which
            // no longer has the recipe's qualification.
            commit: kind == 'runtime' ? 'unknown' : '0518b34',
            devices: parseStableDiffusionDeviceList('CPU\tCPU\n'),
          );
        }
        await expectLater(
          load(
            model,
            params: ImageModelParams(
              device: kind == 'device' ? ComputeDevice.gpu : ComputeDevice.cpu,
              flashAttention: kind == 'flash',
              vaeDirectConvolution: kind == 'direct',
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(downloads.calls, isEmpty);
        expect(driver.started, isEmpty);
        expect(driver.fileSizePaths, isEmpty);
      }
    },
  );

  group('image editing', () {
    final params = const ImageModelParams(
      device: ComputeDevice.cpu,
      flashAttention: false,
      vaeDirectConvolution: false,
    );
    ImageEditingRequest edit({
      double strength = 0.5,
      ImageEditingPixels? mask,
    }) => ImageEditingRequest(
      prompt: 'paint',
      initialImage: ImageEditingPixels.rgb(
        width: 64,
        height: 64,
        pixels: Uint8List(64 * 64 * 3)..[17] = 91,
      ),
      mask: mask,
      strength: strength,
      steps: 4,
    );

    test(
      'owned editing inputs survive resolution and ordinary requests reset',
      () async {
        final engine = await load(_sdxs(), params: params);
        expect(driver.started.single.imageEditingRecipeVerified, isTrue);
        expect((await engine.capabilities).supportsImageEditing, isTrue);
        final mask = ImageEditingPixels.mask(
          width: 64,
          height: 64,
          pixels: Uint8List(64 * 64)..[5] = 255,
        );
        await engine.generateImage(edit(mask: mask));
        final mapped = driver.session.requests.single;
        expect(mapped.initialImage!.pixels[17], 91);
        expect(mapped.initialImage!.channels, 3);
        expect(mapped.mask!.pixels[5], 255);
        expect((mapped.width, mapped.height, mapped.strength), (64, 64, 0.5));
        await engine.generateImage(
          const ImageGenerationRequest(prompt: 'plain'),
        );
        final plain = driver.session.requests.last;
        expect(
          (plain.initialImage, plain.mask, plain.strength),
          (null, null, null),
        );
        await engine.dispose();
        expect((await engine.capabilities).supportsImageEditing, isFalse);
      },
    );

    test(
      'legacy and explicitly unsupported sessions refuse before task starts',
      () async {
        for (final legacy in [true, false]) {
          driver.sessionOverride = legacy
              ? _LegacySession(driver.session)
              : null;
          driver.session.supportsImageEditing = false;
          final engine = await load(_sdxs(), params: params);
          expect((await engine.capabilities).supportsImageEditing, isFalse);
          await expectLater(
            engine.generate(edit()),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          expect(driver.session.requests, isEmpty);
          await engine.generateImage(
            const ImageGenerationRequest(prompt: 'plain'),
          );
          await engine.dispose();
          driver.session = _FakeSession();
        }
      },
    );

    test(
      'host runtime decoder device and native family are actual admission gates',
      () async {
        for (final kind in [
          'host',
          'runtime',
          'decoder',
          'device',
          'family',
          'flash',
          'direct',
        ]) {
          driver = _FakeDriver();
          downloads = _FakeDownloads(driver);
          debugImageGenerationDriverOverride = driver;
          if (kind == 'host') driver.operatingSystem = 'linux';
          if (kind == 'runtime') {
            driver.status = StableDiffusionRuntimeStatus.available(
              version: 'unknown',
              commit: 'unknown',
              devices: parseStableDiffusionDeviceList('CPU\tCPU\n'),
            );
          }
          if (kind == 'family') driver.session.modelVersion = 'SDXL';
          final engine = await load(
            _sdxs(null, kind == 'decoder' ? _local(_taesd) : null),
            params: ImageModelParams(
              device: kind == 'device' ? ComputeDevice.gpu : ComputeDevice.cpu,
              flashAttention: kind == 'flash',
              vaeDirectConvolution: kind == 'direct',
            ),
          );
          expect(
            (await engine.capabilities).supportsImageEditing,
            isFalse,
            reason: kind,
          );
          await expectLater(
            engine.generate(edit()),
            throwsA(isA<LlamaUnsupportedException>()),
            reason: kind,
          );
          expect(driver.session.requests, isEmpty, reason: kind);
          await engine.generateImage(
            const ImageGenerationRequest(prompt: 'plain'),
          );
          await engine.dispose();
        }
      },
    );

    test(
      'invalid strength and mask fail before native work and allow reuse',
      () async {
        final engine = await load(_sdxs(), params: params);
        for (final strength in [0.0, -1.0, 1.01, double.nan, double.infinity]) {
          await expectLater(
            engine.generate(edit(strength: strength)),
            throwsA(isA<LlamaImageGenerationException>()),
          );
        }
        await expectLater(
          engine.generate(
            edit(
              mask: ImageEditingPixels.mask(
                width: 128,
                height: 64,
                pixels: Uint8List(128 * 64),
              ),
            ),
          ),
          throwsA(isA<LlamaImageGenerationException>()),
        );
        expect(driver.session.requests, isEmpty);
        await engine.generateImage(edit(strength: 1));
        expect(driver.session.requests.single.strength, 1);
      },
    );

    test(
      'cancel dispose overlap and reload preserve editing operation ownership',
      () async {
        final engine = await load(_sdxs(), params: params);
        driver.session.gate = Completer<void>();
        final task = await engine.generate(edit());
        await expectLater(
          engine.generate(edit()),
          throwsA(isA<LlamaStateException>()),
        );
        task.cancel();
        driver.session.gate!.complete();
        expect(
          (await task.done).state,
          ImageGenerationCompletionState.cancelled,
        );
        driver.session.gate = null;
        await engine.generateImage(
          const ImageGenerationRequest(prompt: 'plain'),
        );
        expect(driver.session.requests.last.initialImage, isNull);
        driver.session.gate = Completer<void>();
        final pending = await engine.generate(edit());
        final disposal = engine.dispose();
        expect(driver.session.disposed, isFalse);
        driver.session.gate!.complete();
        await disposal;
        expect(
          (await pending.done).state,
          ImageGenerationCompletionState.cancelled,
        );
        expect(driver.session.disposedAfterGenerate, isTrue);
        driver.session = _FakeSession();
        final reloaded = await load(_sdxs(), params: params);
        await reloaded.generateImage(edit());
        expect(driver.session.requests.single.initialImage!.pixels[17], 91);
      },
    );
  });

  group('hires fix', () {
    const hiresFix = HiresFixImageGenerationRequest(
      prompt: 'a fox',
      width: 512,
      height: 384,
      steps: 3,
      count: 2,
      seed: 9,
      hiresFix: ImageHiresFix.scale(1.5, steps: 2, denoisingStrength: 0.4),
    );

    test('a full-VAE SD 1.x or SD 2.x checkpoint on macOS CPU or Metal maps '
        'the resolved pass and reports both passes', () async {
      for (final (path, family, device) in [
        (_sd15, 'SD 1.x', ComputeDevice.cpu),
        (_model, 'SD 2.x', ComputeDevice.auto),
        (_model, 'SD 2.x', ComputeDevice.gpu),
      ]) {
        driver = _FakeDriver();
        downloads = _FakeDownloads(driver);
        debugImageGenerationDriverOverride = driver;
        driver.session.modelVersion = family;
        final engine = await load(
          ImageGenerationModel(_local(path)),
          params: ImageModelParams(device: device),
        );
        final reason = '$family ${device.name}';
        expect(driver.started.single.hiresFixRecipeVerified, isTrue);
        expect(
          (await engine.capabilities).supportsHiresFix,
          isTrue,
          reason: reason,
        );
        final task = await engine.generate(hiresFix);
        final events = await task.events.toList();
        final result = (await task.done).result!;
        final mapped = driver.session.requests.single.hiresFix!;
        expect(
          (mapped.width, mapped.height, mapped.steps),
          (768, 576, 2),
          reason: reason,
        );
        expect(mapped.denoisingStrength, 0.4);
        expect(mapped.upscaler, ImageHiresUpscaler.latent);
        expect(driver.session.requests.single.width, 512);
        expect(result.seed, 9);
        expect(
          [for (final image in result.images) (image.width, image.height)],
          [(768, 576), (768, 576)],
        );
        final progress = events.whereType<ImageGenerationProgressEvent>();
        expect(
          [
            for (final event in progress)
              if (event.phase == ImageGenerationPhase.sampling &&
                  event.step == event.steps)
                '${event.pass}/${event.passCount} #${event.imageIndex} '
                    '${event.steps}',
          ],
          ['0/2 #0 3', '0/2 #1 3', '1/2 #0 2', '1/2 #1 2'],
          reason: reason,
        );
        expect(progress.last.phase, ImageGenerationPhase.decoding);
        expect(events.last, isA<ImageGenerationFinalEvent>());

        await engine.generateImage(
          const ImageGenerationRequest(prompt: 'plain'),
        );
        expect(driver.session.requests.last.hiresFix, isNull);
        await engine.dispose();
        expect((await engine.capabilities).supportsHiresFix, isFalse);
      }
    });

    test('unqualified hosts, runtimes, devices and decoders load without the '
        'capability and refuse a hires fix before the task starts', () async {
      for (final kind in [
        'host',
        'runtime',
        'vulkan',
        'tiny decoder',
        'taesd override',
        'extra component',
        'checkpoint without a VAE',
        'family',
        'legacy session',
        'session probe',
      ]) {
        driver = _FakeDriver();
        downloads = _FakeDownloads(driver);
        debugImageGenerationDriverOverride = driver;
        if (kind == 'host') driver.operatingSystem = 'linux';
        if (kind == 'runtime') {
          driver.status = StableDiffusionRuntimeStatus.available(
            version: 'master-929',
            commit: '3f8527a',
            devices: parseStableDiffusionDeviceList('CPU\tCPU\n'),
          );
        }
        if (kind == 'vulkan') {
          driver.status = _available('Vulkan0\tRTX\nCPU\tCPU\n');
        }
        if (kind == 'tiny decoder') {
          driver.headers[_model] = ImageModelHeaders.sdxsCheckpoint;
        }
        if (kind == 'checkpoint without a VAE') {
          driver.headers[_model] = ggufHeader(
            tensors: [
              ('model.diffusion_model.input_blocks.0.0.weight', [3, 3, 4, 320]),
              ('model.diffusion_model.out.2.weight', [3, 3, 320, 4]),
              ('cond_stage_model.model.token_embedding.weight', [1024, 49408]),
            ],
          );
        }
        if (kind == 'family') driver.session.modelVersion = 'SDXL';
        if (kind == 'legacy session') {
          driver.sessionOverride = _LegacySession(driver.session);
        }
        if (kind == 'session probe') driver.session.supportsHiresFix = false;
        final engine = await load(
          _sdxs(null, switch (kind) {
            'taesd override' => _local(_taesd),
            'extra component' => _local(_clipL),
            _ => null,
          }),
          params: ImageModelParams(
            device: kind == 'vulkan' ? ComputeDevice.gpu : ComputeDevice.auto,
          ),
        );
        expect(
          driver.started.single.hiresFixRecipeVerified,
          ['family', 'legacy session', 'session probe'].contains(kind),
          reason: kind,
        );
        expect(
          (await engine.capabilities).supportsHiresFix,
          isFalse,
          reason: kind,
        );
        await expectLater(
          engine.generate(hiresFix),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              allOf(contains('hires fix'), contains('v0.3.0-1')),
            ),
          ),
          reason: kind,
        );
        expect(driver.session.requests, isEmpty, reason: kind);
        await engine.generateImage(
          const ImageGenerationRequest(prompt: 'plain'),
        );
        await engine.dispose();
      }
    });

    test('invalid passes throw before the task starts and leave the slot '
        'free', () async {
      final engine = await load(_sdxs());
      for (final request in [
        const HiresFixImageGenerationRequest(
          prompt: 'a fox',
          hiresFix: ImageHiresFix.scale(3),
        ),
        const HiresFixImageGenerationRequest(
          prompt: 'a fox',
          width: 520,
          hiresFix: ImageHiresFix.scale(1.5),
        ),
        const HiresFixImageGenerationRequest(
          prompt: 'a fox',
          count: 5,
          hiresFix: ImageHiresFix.scale(1.5),
        ),
        const HiresFixImageGenerationRequest(
          prompt: 'a fox',
          hiresFix: ImageHiresFix.size(width: 1024, height: 1088),
        ),
      ]) {
        await expectLater(
          engine.generate(request),
          throwsA(isA<LlamaImageGenerationException>()),
        );
      }
      expect(driver.session.requests, isEmpty);
      await engine.generateImage(
        const HiresFixImageGenerationRequest(
          prompt: 'a fox',
          steps: 1,
          hiresFix: ImageHiresFix.size(width: 640, height: 512),
        ),
      );
      expect(driver.session.requests.single.hiresFix!.steps, 1);
    });

    test('first-pass images returned as success fail the task, and the engine '
        'stays usable', () async {
      final engine = await load(_sdxs());
      driver.session.ignoreHires = true;
      final completion = await (await engine.generate(hiresFix)).done;
      expect(completion.state, ImageGenerationCompletionState.failed);
      expect(
        completion.error,
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          contains('768x576'),
        ),
      );
      driver.session.ignoreHires = false;
      final result = await engine.generateImage(hiresFix);
      expect(result.images.first.width, 768);
    });

    test('fewer final-size images than requested fail the task', () async {
      final engine = await load(_sdxs());
      driver.session.returnedImageCount = 1;
      final completion = await (await engine.generate(hiresFix)).done;
      expect(completion.state, ImageGenerationCompletionState.failed);
      expect(
        completion.error,
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          contains('2 hires-fix images'),
        ),
      );
    });

    test('a cancel during the second pass cancels the task with no images, '
        'and dispose during it waits for the pass to stop', () async {
      final engine = await load(_sdxs());
      final task = await engine.generate(hiresFix);
      await for (final event in task.events) {
        if (event case ImageGenerationProgressEvent(
          pass: 1,
          :final step,
        ) when step > 0) {
          task.cancel();
        }
      }
      expect((await task.done).state, ImageGenerationCompletionState.cancelled);
      expect(driver.session.stepsRun, lessThan(3 * 2 + 2 * 2));
      expect(driver.session.stepsRun, greaterThan(3 * 2));

      final pending = await engine.generate(hiresFix);
      final first = await pending.events.firstWhere(
        (event) => event is ImageGenerationProgressEvent && event.pass == 1,
      );
      expect(first, isA<ImageGenerationProgressEvent>());
      await engine.dispose();
      expect(
        (await pending.done).state,
        ImageGenerationCompletionState.cancelled,
      );
      expect(driver.session.disposedAfterGenerate, isTrue);
    });
  });

  group('reference image editing', () {
    ImageEditingPixels reference([int value = 5, int width = 512]) =>
        ImageEditingPixels.rgb(
          width: width,
          height: 384,
          pixels: Uint8List(width * 384 * 3)..fillRange(0, 6, value),
        );
    ReferenceImageEditingRequest edit([List<ImageEditingPixels>? references]) =>
        ReferenceImageEditingRequest(
          prompt: 'make the fox blue',
          recipe: ImageReferenceEditingRecipe.fluxKontext,
          references: references ?? [reference()],
          steps: 3,
          guidanceScale: 1,
          seed: 4,
        );

    setUp(() {
      driver.headers[_flux] = ImageModelHeaders.fluxKontextDiffusion;
      driver.session.modelVersion = 'Flux';
    });

    test('a FLUX.1 Kontext set on macOS Metal maps the reference, its size '
        'and the recipe, and an ordinary request after it has none', () async {
      for (final device in [ComputeDevice.auto, ComputeDevice.gpu]) {
        driver = _FakeDriver()
          ..headers[_flux] = ImageModelHeaders.fluxKontextDiffusion;
        driver.session.modelVersion = 'Flux';
        downloads = _FakeDownloads(driver);
        debugImageGenerationDriverOverride = driver;
        final engine = await load(
          _fluxModel([2, 0, 1]),
          params: ImageModelParams(device: device),
        );
        expect(driver.started.single.referenceEditingRecipeVerified, isTrue);
        expect(
          (await engine.capabilities).supportsReferenceImageEditing,
          isTrue,
          reason: device.name,
        );
        final result = await engine.generateImage(edit());
        final mapped = driver.session.requests.single;
        expect(mapped.referenceRecipe, ImageReferenceEditingRecipe.fluxKontext);
        expect(
          [
            for (final image in mapped.references!)
              (image.width, image.height, image.channels, image.pixels[5]),
          ],
          [(512, 384, 3, 5)],
        );
        expect((mapped.width, mapped.height), (512, 384));
        expect(
          [for (final image in result.images) (image.width, image.height)],
          [(512, 384)],
        );
        await engine.generateImage(
          const ImageGenerationRequest(prompt: 'plain'),
        );
        expect(driver.session.requests.last.references, isNull);
        expect(driver.session.requests.last.referenceRecipe, isNull);
        await engine.dispose();
        expect(
          (await engine.capabilities).supportsReferenceImageEditing,
          isFalse,
        );
      }
    });

    test(
      'unqualified hosts, runtimes, devices and model sets load without '
      'the capability and refuse references before the task starts',
      () async {
        for (final kind in [
          'host',
          'runtime',
          'cpu',
          'vulkan',
          'schnell',
          'missing T5-XXL',
          'family',
          'legacy session',
          'session probe',
        ]) {
          driver = _FakeDriver()
            ..headers[_flux] = kind == 'schnell'
                ? ImageModelHeaders.fluxDiffusion
                : ImageModelHeaders.fluxKontextDiffusion;
          driver.session.modelVersion = kind == 'family' ? 'Flux Fill' : 'Flux';
          downloads = _FakeDownloads(driver);
          debugImageGenerationDriverOverride = driver;
          if (kind == 'host') driver.operatingSystem = 'linux';
          if (kind == 'runtime') {
            driver.status = StableDiffusionRuntimeStatus.available(
              version: 'master-929',
              commit: '3f8527a',
              devices: parseStableDiffusionDeviceList('MTL0\tApple M4\n'),
            );
          }
          if (kind == 'vulkan') {
            driver.status = _available('Vulkan0\tRTX\nCPU\tCPU\n');
          }
          if (kind == 'legacy session') {
            driver.sessionOverride = _LegacySession(driver.session);
          }
          if (kind == 'session probe') {
            driver.session.supportsReferenceImageEditing = false;
          }
          final engine = await load(
            kind == 'missing T5-XXL'
                ? ImageGenerationModel(
                    _local(_flux),
                    components: [
                      ImageModelComponent.auto(_local(_ae)),
                      ImageModelComponent.auto(_local(_clipL)),
                    ],
                  )
                : _fluxModel(),
            params: ImageModelParams(
              device: switch (kind) {
                'cpu' => ComputeDevice.cpu,
                'vulkan' => ComputeDevice.gpu,
                _ => ComputeDevice.auto,
              },
            ),
          );
          expect(
            driver.started.single.referenceEditingRecipeVerified,
            ['family', 'legacy session', 'session probe'].contains(kind),
            reason: kind,
          );
          expect(
            (await engine.capabilities).supportsReferenceImageEditing,
            isFalse,
            reason: kind,
          );
          await expectLater(
            engine.generate(edit()),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                allOf(contains('reference'), contains('v0.3.0-1')),
              ),
            ),
            reason: kind,
          );
          expect(driver.session.requests, isEmpty, reason: kind);
          await engine.generateImage(
            const ImageGenerationRequest(prompt: 'plain'),
          );
          await engine.dispose();
        }
      },
    );

    test('invalid references and counts throw before the task starts and '
        'leave the slot free', () async {
      final engine = await load(_fluxModel());
      for (final (request, matcher) in [
        (
          edit([reference(), reference(5, 576)]),
          isA<LlamaImageGenerationException>(),
        ),
        (
          ReferenceImageEditingRequest(
            prompt: 'edit',
            recipe: ImageReferenceEditingRecipe.fluxKontext,
            references: [
              ImageEditingPixels.rgb(
                width: 1088,
                height: 1024,
                pixels: Uint8List(1088 * 1024 * 3),
              ),
            ],
          ),
          isA<LlamaImageGenerationException>(),
        ),
        (edit([reference(), reference(6)]), isA<LlamaUnsupportedException>()),
      ]) {
        await expectLater(engine.generate(request), throwsA(matcher));
      }
      expect(driver.session.requests, isEmpty);
      await engine.generateImage(edit());
      expect(driver.session.requests.single.references, hasLength(1));
    });

    test('a cancel stops the edit with no images, an overlapping request is '
        'refused, and dispose during an edit waits for it', () async {
      final engine = await load(_fluxModel());
      final task = await engine.generate(edit());
      await expectLater(
        engine.generate(edit()),
        throwsA(isA<LlamaStateException>()),
      );
      await task.events.firstWhere(
        (event) =>
            event is ImageGenerationProgressEvent &&
            event.phase == ImageGenerationPhase.sampling &&
            event.step > 0,
      );
      task.cancel();
      expect((await task.done).state, ImageGenerationCompletionState.cancelled);
      expect((await task.done).result, isNull);
      final reused = await engine.generateImage(edit());
      expect(reused.images.single.width, 512);

      final pending = await engine.generate(edit());
      await pending.events.firstWhere(
        (event) => event is ImageGenerationProgressEvent,
      );
      await engine.dispose();
      expect(
        (await pending.done).state,
        ImageGenerationCompletionState.cancelled,
      );
      expect(driver.session.disposedAfterGenerate, isTrue);
    });
  });

  group('module placement', () {
    const metal = 'MTL0\tApple M4\nBLAS\tAccelerate\nCPU\tApple M4\n';
    const vulkan = 'Vulkan0\tNVIDIA L4\nCPU\tHost\n';

    Future<ImageGenerationSessionConfig> startedWith(
      ImageModelPlacement placement, {
      String devices = metal,
      ComputeDevice device = ComputeDevice.auto,
    }) async {
      driver
        ..status = _available(devices)
        ..started.clear();
      await load(
        _sdxs(),
        params: ImageModelParams(device: device),
        placement: placement,
      );
      return driver.started.single;
    }

    test('the default placement leaves the backend, budget and fit to the '
        'runtime', () async {
      for (final (device, backend) in [
        (ComputeDevice.auto, null),
        (ComputeDevice.gpu, 'gpu'),
        (ComputeDevice.cpu, 'cpu'),
      ]) {
        final config = await startedWith(
          const ImageModelPlacement(),
          device: device,
        );
        expect(config.backend, backend, reason: device.name);
        expect(config.maxGpuMemoryGiB, isNull, reason: device.name);
        expect(config.autoFit, isTrue, reason: device.name);
      }
    });

    for (final (placement, auto, gpu) in [
      (
        const ImageModelPlacement(textEncoderOnCpu: true),
        'te=cpu',
        'gpu,te=cpu',
      ),
      (const ImageModelPlacement(vaeOnCpu: true), 'vae=cpu', 'gpu,vae=cpu'),
      (
        const ImageModelPlacement(textEncoderOnCpu: true, vaeOnCpu: true),
        'te=cpu,vae=cpu',
        'gpu,te=cpu,vae=cpu',
      ),
    ]) {
      test('moves modules to the CPU as $auto on Metal and Vulkan', () async {
        for (final devices in [metal, vulkan]) {
          expect(
            (await startedWith(placement, devices: devices)).backend,
            auto,
          );
          expect(
            (await startedWith(
              placement,
              devices: devices,
              device: ComputeDevice.gpu,
            )).backend,
            gpu,
          );
        }
      });
    }

    for (final gib in [1, 12, ImageModelPlacement.largestGpuMemoryGiB]) {
      test('forwards a $gib GiB GPU budget with the fit on', () async {
        final config = await startedWith(
          ImageModelPlacement(maxGpuMemoryGiB: gib),
          devices: vulkan,
        );
        expect(config.maxGpuMemoryGiB, gib);
        expect(config.autoFit, isTrue);
        expect(config.backend, isNull);
      });
    }

    test('turns the fit off, and the memory check then expects the first '
        'GPU', () async {
      for (final device in [ComputeDevice.auto, ComputeDevice.gpu]) {
        driver.runtimePicks.clear();
        final config = await startedWith(
          const ImageModelPlacement(autoFit: false),
          devices: vulkan,
          device: device,
        );
        expect(config.autoFit, isFalse);
        expect(config.maxGpuMemoryGiB, isNull);
        expect(driver.runtimePicks, [false], reason: device.name);
      }
      driver.runtimePicks.clear();
      await startedWith(const ImageModelPlacement(), devices: vulkan);
      expect(driver.runtimePicks, [true]);
    });

    for (final gib in [0, -1, ImageModelPlacement.largestGpuMemoryGiB + 1]) {
      test('rejects a $gib GiB GPU budget before file resolution', () async {
        await expectLater(
          load(
            _sdxs(ModelSource.parse('https://example.com/model.gguf')),
            placement: ImageModelPlacement(maxGpuMemoryGiB: gib),
          ),
          throwsA(
            isA<LlamaImageGenerationException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('ImageModelPlacement.maxGpuMemoryGiB'),
                )
                .having((error) => error.details, 'details', gib),
          ),
        );
        expect(downloads.calls, isEmpty);
        expect(driver.started, isEmpty);
      });
    }

    for (final (discrete, name) in [
      (false, 'only integrated GPUs'),
      (null, 'no GPU type'),
    ]) {
      test('refuses a GPU budget on Vulkan when the runtime reports $name, '
          'before file resolution', () async {
        driver
          ..status = _available(vulkan)
          ..discreteGpu = discrete;
        for (final device in [ComputeDevice.auto, ComputeDevice.gpu]) {
          await expectLater(
            load(
              _sdxs(ModelSource.parse('https://example.com/model.gguf')),
              params: ImageModelParams(device: device),
              placement: const ImageModelPlacement(maxGpuMemoryGiB: 4),
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                allOf(
                  contains('maxGpuMemoryGiB'),
                  contains('discrete GPU'),
                  contains('Vulkan0'),
                  contains('stable-diffusion-native/issues/34'),
                ),
              ),
            ),
            reason: device.name,
          );
        }
        expect(downloads.calls, isEmpty);
        expect(driver.started, isEmpty);
      });
    }

    test('an integrated GPU still takes module moves and the fit, and Metal '
        'takes a budget without asking for the GPU type', () async {
      driver.discreteGpu = false;
      for (final placement in [
        const ImageModelPlacement(textEncoderOnCpu: true, vaeOnCpu: true),
        const ImageModelPlacement(autoFit: false),
      ]) {
        await startedWith(placement, devices: vulkan);
      }
      // One read per load, for the memory check.
      expect(driver.gpuMemoryReads, 2);
      final config = await startedWith(
        const ImageModelPlacement(maxGpuMemoryGiB: 4),
      );
      expect(config.maxGpuMemoryGiB, 4);
      expect(driver.gpuMemoryReads, 2);
    });

    test(
      'a discrete Vulkan GPU takes a budget after one GPU memory read',
      () async {
        final config = await startedWith(
          const ImageModelPlacement(maxGpuMemoryGiB: 4),
          devices: vulkan,
        );
        expect(config.maxGpuMemoryGiB, 4);
        expect(driver.gpuMemoryReads, 1);
      },
    );

    test('a GPU budget with the memory check reads the GPU memory once and '
        'checks the memory against what it read', () async {
      driver
        ..status = _available(vulkan)
        ..started.clear();

      await load(
        _sdxs(),
        params: const ImageModelParams(device: ComputeDevice.gpu),
        placement: const ImageModelPlacement(maxGpuMemoryGiB: 4),
      );

      expect(driver.gpuMemoryReads, 1);
      expect(driver.budgetDevices, [ImageGenerationComputeDevice.otherGpu]);
      expect(driver.memoryGpus.single, hasLength(1));
    });

    test('a GPU budget on a host with an integrated and a discrete GPU is '
        'taken', () async {
      driver
        ..status = _available(vulkan)
        ..mixedGpus = true;

      final config = await startedWith(
        const ImageModelPlacement(maxGpuMemoryGiB: 4),
        devices: vulkan,
      );

      expect(config.maxGpuMemoryGiB, 4);
    });

    test('a GPU budget reads the GPU memory again for the memory check only '
        'when files were downloaded', () async {
      driver.status = _available(vulkan);
      const params = ImageModelParams(device: ComputeDevice.gpu);
      const placement = ImageModelPlacement(maxGpuMemoryGiB: 4);

      await load(_sdxs(), params: params, placement: placement);
      expect(driver.gpuMemoryReads, 1);

      driver.gpuMemoryReads = 0;
      await load(
        _sdxs(ModelSource.parse('https://example.com/model.gguf')),
        params: params,
        placement: placement,
      );
      expect(driver.gpuMemoryReads, 2);
      expect(driver.memoryGpus.last, hasLength(1));
    });

    test('the memory check alone reads the GPU memory once, and without '
        'one it reads none', () async {
      driver.status = _available(vulkan);
      await load(
        _sdxs(),
        params: const ImageModelParams(device: ComputeDevice.gpu),
      );
      expect(driver.gpuMemoryReads, 1);

      driver.gpuMemoryReads = 0;
      await load(
        _sdxs(),
        params: const ImageModelParams(
          device: ComputeDevice.gpu,
          checkMemory: false,
        ),
      );
      expect(driver.gpuMemoryReads, 0);
    });

    test('refuses a GPU budget with the fit off, which aborts the runtime, '
        'before file resolution', () async {
      await expectLater(
        load(
          _sdxs(ModelSource.parse('https://example.com/model.gguf')),
          placement: const ImageModelPlacement(
            autoFit: false,
            maxGpuMemoryGiB: 8,
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('maxGpuMemoryGiB'),
              contains('autoFit: false'),
              contains('autoFit'),
            ),
          ),
        ),
      );
      expect(downloads.calls, isEmpty);
      expect(driver.started, isEmpty);
    });

    for (final (name, placement) in [
      ('textEncoderOnCpu', const ImageModelPlacement(textEncoderOnCpu: true)),
      ('vaeOnCpu', const ImageModelPlacement(vaeOnCpu: true)),
      ('maxGpuMemoryGiB', const ImageModelPlacement(maxGpuMemoryGiB: 4)),
      ('autoFit: false', const ImageModelPlacement(autoFit: false)),
    ]) {
      test('$name on a CPU engine throws before file resolution', () async {
        for (final (devices, device, why) in [
          (metal, ComputeDevice.cpu, 'ComputeDevice.cpu was requested'),
          ('CPU\tCortex-A78\n', ComputeDevice.auto, 'reports no GPU, only CPU'),
          (
            'BLAS\tOpenBLAS\nCPU\tHost\n',
            ComputeDevice.auto,
            'reports no GPU, only BLAS, CPU',
          ),
        ]) {
          driver.status = _available(devices);
          await expectLater(
            load(
              _sdxs(ModelSource.parse('https://example.com/model.gguf')),
              params: ImageModelParams(device: device),
              placement: placement,
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                allOf(contains(name), contains('GPU'), contains(why)),
              ),
            ),
            reason: '$devices ${device.name}',
          );
        }
        expect(downloads.calls, isEmpty);
        expect(driver.started, isEmpty);
      });
    }

    test('a module on the CPU leaves the Metal-only FLUX.1 Kontext recipe '
        'unqualified; a GPU budget does not', () async {
      driver.headers[_flux] = ImageModelHeaders.fluxKontextDiffusion;
      driver.session.modelVersion = 'Flux';
      for (final (placement, qualified) in [
        (const ImageModelPlacement(), true),
        (const ImageModelPlacement(maxGpuMemoryGiB: 12), true),
        (const ImageModelPlacement(autoFit: false), true),
        (const ImageModelPlacement(textEncoderOnCpu: true), false),
        (const ImageModelPlacement(vaeOnCpu: true), false),
      ]) {
        driver.started.clear();
        final engine = await load(_fluxModel(), placement: placement);
        expect(
          driver.started.single.referenceEditingRecipeVerified,
          qualified,
          reason: '$placement',
        );
        await engine.dispose();
      }
    });
  });

  group('ControlNet', () {
    const params = ImageModelParams(
      device: ComputeDevice.cpu,
      flashAttention: false,
      vaeDirectConvolution: false,
    );
    ControlNetImageGenerationRequest control({
      double strength = 0.6,
      ImageEditingPixels? image,
    }) => ControlNetImageGenerationRequest(
      prompt: 'a house',
      control: ImageControlNetCondition(
        image:
            image ??
            ImageEditingPixels.rgb(
              width: 128,
              height: 64,
              pixels: Uint8List(128 * 64 * 3)..[23] = 201,
            ),
        strength: strength,
      ),
      steps: 4,
    );

    test('a header-verified ControlNet loads with the model and requests map '
        'owned control input, then ordinary requests reset it', () async {
      driver.session.modelVersion = 'SD 1.x';
      final engine = await load(_controlNetModel(), params: params);
      final config = driver.started.single;
      expect(config.files, {'model': _sd15, 'controlNet': _canny});
      expect(config.controlNetRecipeVerified, isTrue);
      expect(config.imageEditingRecipeVerified, isFalse);
      expect(config.vaeTilingRecipeVerified, isFalse);
      expect(engine.roles.map((role, source) => MapEntry(role, source.path)), {
        ImageModelRole.checkpoint: _sd15,
        ImageModelRole.controlNet: _canny,
      });
      final capabilities = await engine.capabilities;
      expect(capabilities.supportsControlNet, isTrue);
      expect(capabilities.supportsImageEditing, isFalse);
      await engine.generateImage(control());
      final mapped = driver.session.requests.single;
      expect(mapped.controlImage!.pixels[23], 201);
      expect(mapped.controlImage!.channels, 3);
      expect(
        (mapped.width, mapped.height, mapped.controlStrength),
        (128, 64, 0.6),
      );
      expect(mapped.initialImage, isNull);
      await engine.generateImage(const ImageGenerationRequest(prompt: 'plain'));
      final plain = driver.session.requests.last;
      expect((plain.controlImage, plain.controlStrength), (null, null));
      await engine.dispose();
      expect((await engine.capabilities).supportsControlNet, isFalse);
    });

    test(
      'unqualified ControlNet loads refuse before the native load',
      () async {
        for (final kind in [
          'host',
          'runtime',
          'auto device',
          'gpu device',
          'default flash attention',
          'default direct convolution',
          'flash attention',
          'direct convolution',
          'SD 2.x base',
          'Diffusers layout',
          'extra component',
          'explicit role without header proof',
        ]) {
          driver = _FakeDriver();
          downloads = _FakeDownloads(driver);
          debugImageGenerationDriverOverride = driver;
          driver.session.modelVersion = 'SD 1.x';
          if (kind == 'host') driver.operatingSystem = 'linux';
          if (kind == 'runtime') {
            driver.status = StableDiffusionRuntimeStatus.available(
              version: 'unknown',
              commit: 'unknown',
              devices: parseStableDiffusionDeviceList('CPU\tCPU\n'),
            );
          }
          final model = switch (kind) {
            'SD 2.x base' => _controlNetModel(base: _sd2Base),
            'Diffusers layout' => _controlNetModel(control: _diffusersCanny),
            'extra component' => _controlNetModel(
              extra: [ImageModelComponent.auto(_local(_taesd))],
            ),
            'explicit role without header proof' => ImageGenerationModel(
              _local(_sd15),
              components: [
                ImageModelComponent(
                  _local('/models/control.pth'),
                  role: ImageModelRole.controlNet,
                ),
              ],
            ),
            _ => _controlNetModel(),
          };
          driver.sizes['/models/control.pth'] = 700 << 20;
          await expectLater(
            load(
              model,
              params: ImageModelParams(
                device: switch (kind) {
                  'auto device' => ComputeDevice.auto,
                  'gpu device' => ComputeDevice.gpu,
                  _ => ComputeDevice.cpu,
                },
                flashAttention: switch (kind) {
                  'default flash attention' => null,
                  'flash attention' => true,
                  _ => false,
                },
                vaeDirectConvolution: switch (kind) {
                  'default direct convolution' => null,
                  'direct convolution' => true,
                  _ => false,
                },
              ),
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                contains('ControlNet'),
              ),
            ),
            reason: kind,
          );
          expect(driver.started, isEmpty, reason: kind);
        }
      },
    );

    test(
      'a native family or ControlNet probe mismatch frees the loaded model',
      () async {
        for (final kind in ['family', 'probe', 'legacy session']) {
          driver = _FakeDriver();
          downloads = _FakeDownloads(driver);
          debugImageGenerationDriverOverride = driver;
          driver.session.modelVersion = kind == 'family' ? 'SD 2.x' : 'SD 1.x';
          driver.session.supportsControlNet = kind != 'probe';
          if (kind == 'legacy session') {
            driver.sessionOverride = _LegacySession(driver.session);
          }
          await expectLater(
            load(_controlNetModel(), params: params),
            throwsA(isA<LlamaUnsupportedException>()),
            reason: kind,
          );
          expect(driver.started, hasLength(1), reason: kind);
          expect(driver.session.disposed, isTrue, reason: kind);
          final next = await load(_sdxs(), params: params);
          await next.dispose();
        }
      },
    );

    test('a session that stops reporting the ControlNet clears the capability '
        'and refuses control before the task starts', () async {
      driver.session.modelVersion = 'SD 1.x';
      final engine = await load(_controlNetModel(), params: params);
      driver.session.supportsControlNet = false;
      expect((await engine.capabilities).supportsControlNet, isFalse);
      await expectLater(
        engine.generate(control()),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(driver.session.requests, isEmpty);
      await engine.generateImage(const ImageGenerationRequest(prompt: 'plain'));
      expect(driver.session.requests.single.controlImage, isNull);
    });

    test('control requests refuse on models without a ControlNet', () async {
      for (final model in [_sdxs(), ImageGenerationModel(_local(_sd15))]) {
        driver.session = _FakeSession()..modelVersion = 'SD 1.x';
        final engine = await load(model, params: params);
        expect(driver.started.last.controlNetRecipeVerified, isFalse);
        expect((await engine.capabilities).supportsControlNet, isFalse);
        await expectLater(
          engine.generate(control()),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(driver.session.requests, isEmpty);
        await engine.generateImage(
          const ImageGenerationRequest(prompt: 'plain'),
        );
        await engine.dispose();
      }
    });

    test(
      'invalid control input fails before native work and allows reuse',
      () async {
        driver.session.modelVersion = 'SD 1.x';
        final engine = await load(_controlNetModel(), params: params);
        for (final strength in [-0.5, 2.5, double.nan, double.infinity]) {
          await expectLater(
            engine.generate(control(strength: strength)),
            throwsA(isA<LlamaImageGenerationException>()),
            reason: '$strength',
          );
        }
        await expectLater(
          engine.generate(
            control(
              image: ImageEditingPixels.mask(
                width: 64,
                height: 64,
                pixels: Uint8List(64 * 64),
              ),
            ),
          ),
          throwsA(isA<LlamaImageGenerationException>()),
        );
        expect(driver.session.requests, isEmpty);
        for (final strength in [0.0, 2.0]) {
          await engine.generateImage(control(strength: strength));
          expect(driver.session.requests.last.controlStrength, strength);
        }
      },
    );

    test(
      'cancel dispose overlap and reload keep control input owned',
      () async {
        driver.session.modelVersion = 'SD 1.x';
        final engine = await load(_controlNetModel(), params: params);
        driver.session.gate = Completer<void>();
        final task = await engine.generate(control());
        await expectLater(
          engine.generate(control()),
          throwsA(isA<LlamaStateException>()),
        );
        task.cancel();
        driver.session.gate!.complete();
        expect(
          (await task.done).state,
          ImageGenerationCompletionState.cancelled,
        );
        driver.session.gate = Completer<void>();
        final pending = await engine.generate(control());
        final disposal = engine.dispose();
        expect(driver.session.disposed, isFalse);
        driver.session.gate!.complete();
        await disposal;
        expect(
          (await pending.done).state,
          ImageGenerationCompletionState.cancelled,
        );
        expect(driver.session.disposedAfterGenerate, isTrue);
        driver.session = _FakeSession()..modelVersion = 'SD 1.x';
        final reloaded = await load(_controlNetModel(), params: params);
        await reloaded.generateImage(control());
        expect(driver.session.requests.single.controlImage!.pixels[23], 201);
      },
    );
  });

  group('seamless textures', () {
    test(
      'circular flags survive resolution and ordinary requests reset them',
      () async {
        driver.headers[_model] = ImageModelHeaders.sdxsCheckpoint;
        driver.session.modelVersion = 'SDXS (512-DS)';
        final engine = await load(
          _sdxs(),
          params: const ImageModelParams(
            flashAttention: false,
            vaeDirectConvolution: false,
          ),
        );
        for (final (x, y) in [
          (true, false),
          (false, true),
          (true, true),
          (false, false),
        ]) {
          await engine.generateImage(
            SeamlessImageGenerationRequest(
              prompt: 'stone',
              circularX: x,
              circularY: y,
            ),
          );
          expect(
            (
              driver.session.requests.last.circularX,
              driver.session.requests.last.circularY,
            ),
            (x, y),
          );
        }
        await engine.generateImage(const LegacyImageGenerationRequest());
        expect(
          (
            driver.session.requests.last.circularX,
            driver.session.requests.last.circularY,
          ),
          (false, false),
        );
      },
    );

    test(
      'forced checkpoint roles and decoder overrides cannot bypass circular checks',
      () async {
        driver.session.modelVersion = 'SDXS (512-DS)';
        for (final header in [
          ImageModelHeaders.sdTurboCheckpoint,
          Uint8List(16),
        ]) {
          driver.headers[_model] = header;
          final engine = await load(
            ImageGenerationModel(
              _local(_model),
              role: ImageModelRole.checkpoint,
            ),
            params: const ImageModelParams(
              flashAttention: false,
              vaeDirectConvolution: false,
            ),
          );
          await expectLater(
            engine.generate(
              const SeamlessImageGenerationRequest(
                prompt: 'stone',
                circularX: true,
              ),
            ),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          expect(driver.session.requests, isEmpty);
          await engine.dispose();
          driver.session = _FakeSession()..modelVersion = 'SDXS (512-DS)';
        }
        driver.headers[_model] = ImageModelHeaders.sdxsCheckpoint;
        final engine = await load(
          _sdxs(_local(_model), _local(_taesd)),
          params: const ImageModelParams(
            flashAttention: false,
            vaeDirectConvolution: false,
          ),
        );
        await expectLater(
          engine.generate(
            const SeamlessImageGenerationRequest(
              prompt: 'stone',
              circularY: true,
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(driver.session.requests, isEmpty);
        // Rejection happens before taking the process-wide generation slot.
        await engine.generateImage(
          const ImageGenerationRequest(prompt: 'ordinary'),
        );
      },
    );
  });

  group('on macOS x86_64', () {
    late List<LlamaLogRecord> records;

    setUp(() {
      driver
        ..isMacosX64 = true
        ..status = _available(
          'MTL0\tAMD Radeon Pro 5500M\nBLAS\tAccelerate\nCPU\tIntel\n',
        );
      records = [];
      final logger = LlamaLogger.instance;
      final level = logger.level;
      logger
        ..setLevel(LlamaLogLevel.debug)
        ..setHandler(records.add);
      addTearDown(() {
        logger
          ..setLevel(level)
          ..setHandler(null);
      });
    });

    test('auto loads on the CPU', () async {
      await load(_sdxs());
      expect(driver.started.single.backend, 'cpu');
      expect(driver.budgetDevices, [ImageGenerationComputeDevice.cpu]);
      expect(records.where((r) => r.level == LlamaLogLevel.warn), isEmpty);
    });

    test('checkRuntime reports the CPU as the device auto picks', () async {
      final capabilities = await ImageGenerationEngine.checkRuntime();
      expect(capabilities.backendName, 'CPU');
      expect(capabilities.deviceNames, contains('MTL0'));
    });

    test('an explicit GPU still loads on Metal and warns', () async {
      await load(
        _sdxs(),
        params: const ImageModelParams(device: ComputeDevice.gpu),
      );
      expect(driver.started.single.backend, 'gpu');
      expect(driver.budgetDevices, [ImageGenerationComputeDevice.metal]);
      expect(
        records.where(
          (r) =>
              r.level == LlamaLogLevel.warn &&
              r.message.contains('macOS x86_64'),
        ),
        hasLength(1),
      );
    });

    test('placement under auto asks for an explicit GPU', () async {
      await expectLater(
        load(_sdxs(), placement: const ImageModelPlacement(vaeOnCpu: true)),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('ComputeDevice.auto runs on the CPU on macOS x86_64'),
              contains('ComputeDevice.gpu'),
              isNot(contains('reports no GPU')),
            ),
          ),
        ),
      );
      expect(driver.started, isEmpty);
    });

    test('placement with no GPU listed still reports no GPU', () async {
      driver.status = _available('BLAS\tAccelerate\nCPU\tIntel\n');
      await expectLater(
        load(_sdxs(), placement: const ImageModelPlacement(vaeOnCpu: true)),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('reports no GPU, only BLAS, CPU'),
              isNot(contains('ComputeDevice.auto runs on the CPU')),
            ),
          ),
        ),
      );
      expect(driver.started, isEmpty);
    });

    test('an explicit CPU stays on the CPU', () async {
      await load(
        _sdxs(),
        params: const ImageModelParams(device: ComputeDevice.cpu),
      );
      expect(driver.started.single.backend, 'cpu');
    });
  });

  test('an explicit GPU on another host does not warn', () async {
    final records = <LlamaLogRecord>[];
    final logger = LlamaLogger.instance;
    final level = logger.level;
    logger
      ..setLevel(LlamaLogLevel.debug)
      ..setHandler(records.add);
    addTearDown(() {
      logger
        ..setLevel(level)
        ..setHandler(null);
    });
    await load(
      _sdxs(),
      params: const ImageModelParams(device: ComputeDevice.gpu),
    );
    expect(driver.started.single.backend, 'gpu');
    expect(records.where((r) => r.level == LlamaLogLevel.warn), isEmpty);
  });

  group('checkRuntime', () {
    test('reports the devices and the device auto would pick, probing in '
        'the background', () async {
      final capabilities = await ImageGenerationEngine.checkRuntime();

      expect(driver.backgroundProbes, 1);
      expect(capabilities.isSupported, isTrue);
      expect(capabilities.unsupportedReason, isNull);
      expect(capabilities.deviceNames, ['MTL0', 'BLAS', 'CPU']);
      expect(capabilities.backendName, 'MTL0');
      expect(capabilities.runtimeVersion, 'master-929');
      expect(capabilities.modelVersion, isNull);
      expect(capabilities.supportsCancellation, isTrue);
      expect(capabilities.maxConcurrentTasks, 1);
    });

    test('reports why the runtime is unavailable', () async {
      driver.status = StableDiffusionRuntimeStatus.unavailable(
        LlamaUnsupportedException('stable_diffusion runtime is not bundled'),
      );

      final EngineCapabilities capabilities =
          await ImageGenerationEngine.checkRuntime();

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('not bundled'));
      expect(capabilities.backendName, isNull);
      expect(
        (capabilities as ImageGenerationCapabilities).deviceNames,
        isEmpty,
      );
    });

    test('checks started while a probe runs share it, and a later check '
        'probes again', () async {
      final gate = driver.probeGate = Completer<void>();

      final first = ImageGenerationEngine.checkRuntime();
      final second = ImageGenerationEngine.checkRuntime();
      await pumpEventQueue();
      expect(driver.backgroundProbes, 1);
      gate.complete();
      expect((await first).backendName, 'MTL0');
      expect((await second).backendName, 'MTL0');

      driver.status = _available('CPU\tHost\n');
      expect((await ImageGenerationEngine.checkRuntime()).backendName, 'CPU');
      expect(driver.backgroundProbes, 2);
    });

    test('a failed probe fails every check that shared it, and the next '
        'check probes again', () async {
      final gate = driver.probeGate = Completer<void>();
      driver.probeError = StateError('probe isolate failed');

      final first = ImageGenerationEngine.checkRuntime();
      final second = ImageGenerationEngine.checkRuntime();
      gate.complete();
      await expectLater(first, throwsA(same(driver.probeError)));
      await expectLater(second, throwsA(same(driver.probeError)));
      expect(driver.backgroundProbes, 1);

      driver
        ..probeGate = null
        ..probeError = null;
      expect((await ImageGenerationEngine.checkRuntime()).isSupported, isTrue);
      expect(driver.backgroundProbes, 2);
    });
  });

  group('load', () {
    test('probes the runtime in the background and shares a running '
        'checkRuntime probe', () async {
      final gate = driver.probeGate = Completer<void>();

      final check = ImageGenerationEngine.checkRuntime();
      final loading = load(_sdxs());
      await pumpEventQueue();
      expect(driver.started, isEmpty);
      gate.complete();
      await check;
      final engine = await loading;

      expect(driver.backgroundProbes, 1);
      expect((await engine.capabilities).deviceNames, ['MTL0', 'BLAS', 'CPU']);
    });

    test('throws the probe reason and loads nothing when the runtime is '
        'unavailable', () async {
      driver.status = StableDiffusionRuntimeStatus.unavailable(
        LlamaUnsupportedException('not published for android-x64'),
      );

      await expectLater(
        load(_sdxs()),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'not published for android-x64',
          ),
        ),
      );
      expect(driver.started, isEmpty);
    });

    test('passes every file and the device choice to the runtime', () async {
      final engine = await load(
        _sdxs(_local(_model), _local(_taesd)),
        params: const ImageModelParams(device: ComputeDevice.cpu, threads: 4),
      );

      final config = driver.started.single;
      expect(config.files, {'model': _model, 'taesd': _taesd});
      expect(config.backend, 'cpu');
      expect(config.threads, 4);
      final capabilities = await engine.capabilities;
      expect(capabilities.backendName, 'CPU');
      expect(capabilities.modelVersion, 'SD 2.x');
      expect(capabilities.deviceNames, ['MTL0', 'BLAS', 'CPU']);
      expect(capabilities.supportsCancellation, isTrue);
    });

    test('auto leaves the device to the runtime and reports its GPU', () async {
      final engine = await load(_sdxs());

      expect(driver.started.single.backend, isNull);
      expect((await engine.capabilities).backendName, 'MTL0');
    });

    test('assigns split files their roles from their headers, in any '
        'order', () async {
      for (final order in const [
        [0, 1, 2],
        [2, 0, 1],
        [1, 2, 0],
      ]) {
        final engine = await load(_fluxModel(order));
        await engine.dispose();

        expect(driver.started.last.files, {
          'diffusionModel': _flux,
          'vae': _ae,
          'clipL': _clipL,
          't5xxl': _t5xxl,
        }, reason: '$order');
        expect(
          engine.roles.map((role, source) => MapEntry(role, source.path)),
          {
            ImageModelRole.diffusionModel: _flux,
            ImageModelRole.vae: _ae,
            ImageModelRole.clipL: _clipL,
            ImageModelRole.t5xxl: _t5xxl,
          },
        );
      }
    });

    test('takes the role a component sets, and the main file role', () async {
      const ckpt = '/models/model.ckpt';
      driver
        ..sizes[ckpt] = _gib
        ..headers[ckpt] = ImageModelHeaders.pickle;

      await load(
        ImageGenerationModel(
          _local(_taesd),
          components: [
            ImageModelComponent(_local(ckpt), role: ImageModelRole.checkpoint),
          ],
        ),
      );
      expect(driver.started.last.files, {'model': ckpt, 'taesd': _taesd});

      await engines.removeLast().dispose();
      await load(
        ImageGenerationModel(_local(ckpt), role: ImageModelRole.checkpoint),
      );
      expect(driver.started.last.files, {'model': ckpt});
    });

    test('a file the header check cannot classify throws naming its '
        'position', () async {
      const ckpt = '/models/model.ckpt';
      driver
        ..sizes[ckpt] = _gib
        ..headers[ckpt] = ImageModelHeaders.pickle;

      await expectLater(
        load(_sdxs(_local(_model), _local(ckpt))),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('component 1'),
              contains('ImageModelComponent(source, role: ...)'),
              isNot(contains(ckpt)),
            ),
          ),
        ),
      );
      expect(driver.started, isEmpty);
    });

    group('automatic attention and VAE settings', () {
      Future<ImageGenerationSessionConfig> startedWith(
        String devices,
        ImageGenerationModel model, {
        ImageModelParams params = const ImageModelParams(),
      }) async {
        driver
          ..status = _available(devices)
          ..started.clear();
        await load(model, params: params);
        return driver.started.single;
      }

      final checkpoint = _sdxs();
      const metal = 'MTL0\tApple M4\nBLAS\tAccelerate\nCPU\tApple M4\n';
      const vulkan = 'Vulkan0\tNVIDIA L4\nCPU\tHost\n';
      const cpu = 'CPU\tCortex-A78\n';

      test('Metal uses flash attention and keeps the unfolded VAE', () async {
        final config = await startedWith(metal, checkpoint);

        expect(config.flashAttention, isTrue);
        expect(config.vaeDirectConvolution, isFalse);
      });

      test('Vulkan uses direct VAE convolutions and leaves flash attention '
          'off', () async {
        final config = await startedWith(vulkan, checkpoint);

        expect(config.flashAttention, isFalse);
        expect(config.vaeDirectConvolution, isTrue);
      });

      test('the CPU uses both', () async {
        final config = await startedWith(cpu, checkpoint);

        expect(config.flashAttention, isTrue);
        expect(config.vaeDirectConvolution, isTrue);
      });

      test('the device auto picks decides, so cpu on a Mac uses direct VAE '
          'convolutions', () async {
        final config = await startedWith(
          metal,
          checkpoint,
          params: const ImageModelParams(device: ComputeDevice.cpu),
        );

        expect(config.flashAttention, isTrue);
        expect(config.vaeDirectConvolution, isTrue);
      });

      test('a taesd file keeps the unfolded VAE on every device; a single '
          'checkpoint uses direct convolutions off Metal', () async {
        final withTaesd = _sdxs(_local(_model), _local(_taesd));
        for (final devices in [metal, vulkan, cpu]) {
          final config = await startedWith(devices, withTaesd);
          expect(config.vaeDirectConvolution, isFalse, reason: devices);
        }
        expect(
          (await startedWith(cpu, checkpoint)).vaeDirectConvolution,
          isTrue,
        );
        expect(
          (await startedWith(
            cpu,
            checkpoint,
            params: const ImageModelParams(vaeDirectConvolution: false),
          )).vaeDirectConvolution,
          isFalse,
        );
      });

      test('a checkpoint whose header shows an embedded tiny autoencoder '
          'keeps the unfolded VAE', () async {
        const sdxs = '/models/sdxs.gguf';
        driver
          ..sizes[sdxs] = 651 << 20
          ..headers[sdxs] = ImageModelHeaders.sdxsCheckpoint;

        for (final devices in [metal, vulkan, cpu]) {
          final config = await startedWith(
            devices,
            ImageGenerationModel(_local(sdxs)),
          );
          expect(config.vaeDirectConvolution, isFalse, reason: devices);
        }
      });

      test('explicit params override the automatic choice', () async {
        final onMetal = await startedWith(
          metal,
          checkpoint,
          params: const ImageModelParams(
            flashAttention: false,
            vaeDirectConvolution: true,
          ),
        );
        expect(onMetal.flashAttention, isFalse);
        expect(onMetal.vaeDirectConvolution, isTrue);

        final onVulkan = await startedWith(
          vulkan,
          _sdxs(),
          params: const ImageModelParams(
            flashAttention: true,
            vaeDirectConvolution: true,
          ),
        );
        expect(onVulkan.flashAttention, isTrue);
        expect(onVulkan.vaeDirectConvolution, isTrue);
      });

      group('direct VAE convolutions on iOS', () {
        const iphone = 'MTL0\tApple A18 Pro GPU\nBLAS\tAccelerate\nCPU\tCPU\n';
        setUp(() => driver.operatingSystem = 'ios');

        test('true on Metal throws LlamaUnsupportedException naming the '
            'option, the platform, the backend and the issue, before any '
            'file is read or loaded', () async {
          driver
            ..status = _available(iphone)
            ..started.clear();

          await expectLater(
            load(
              checkpoint,
              params: const ImageModelParams(vaeDirectConvolution: true),
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                allOf(
                  contains('ImageModelParams.vaeDirectConvolution: true'),
                  contains('iOS with the Metal backend (MTL0)'),
                  contains('https://github.com/leehack/llamadart/issues/1044'),
                ),
              ),
            ),
          );
          expect(driver.fileSizePaths, isEmpty);
          expect(driver.readPaths, isEmpty);
          expect(downloads.calls, isEmpty);
          expect(driver.started, isEmpty);
          expect(driver.budgetDevices, isEmpty);
        });

        test('full VAE refuses automatic and explicit Metal before native '
            'creation, including unfolded convolutions', () async {
          driver.status = _available(iphone);
          for (final device in [ComputeDevice.auto, ComputeDevice.gpu]) {
            for (final value in [null, false]) {
              await expectLater(
                load(
                  checkpoint,
                  params: ImageModelParams(
                    device: device,
                    vaeDirectConvolution: value,
                  ),
                ),
                throwsA(
                  isA<LlamaUnsupportedException>().having(
                    (error) => error.message,
                    'full-VAE safety restriction',
                    allOf(
                      contains('Full-VAE decoding on iOS'),
                      contains('Metal backend (MTL0)'),
                      contains('/issues/1047'),
                      contains('vaeOnCpu: true'),
                      isNot(contains(_model)),
                    ),
                  ),
                ),
              );
              expect(driver.started, isEmpty);
              expect(driver.budgetDevices, isEmpty);
            }
          }
        });

        test('a full VAE can explicitly compute on the CPU while diffusion '
            'uses Metal', () async {
          driver.status = _available(iphone);
          await load(
            checkpoint,
            params: const ImageModelParams(vaeDirectConvolution: false),
            placement: const ImageModelPlacement(vaeOnCpu: true),
          );
          expect(driver.started.single.vaeDirectConvolution, isFalse);
          expect(driver.started.single.backend, contains('vae=cpu'));
          expect(driver.started.single.requiresIntrinsicTinyDecoderV1, isFalse);
        });

        test(
          'only native-verified intrinsic SDXS decoders use iOS Metal',
          () async {
            const embedded = '/models/embedded-tiny.gguf';
            driver
              ..sizes[embedded] = 651 << 20
              ..headers[embedded] = ImageModelHeaders.sdxsCheckpoint;
            for (final family in ['SDXS (512-DS)', 'SDXS (09)']) {
              for (final device in [ComputeDevice.auto, ComputeDevice.gpu]) {
                driver.session = _FakeSession()..modelVersion = family;
                final config = await startedWith(
                  iphone,
                  ImageGenerationModel(_local(embedded)),
                  params: ImageModelParams(device: device),
                );
                expect(config.vaeDirectConvolution, isFalse);
                expect(config.requiresIntrinsicTinyDecoderV1, isTrue);
                expect(config.backend, isNot(contains('vae=cpu')));
                expect(driver.session.disposed, isFalse);
              }
            }
          },
        );

        test(
          'external tiny decoders cannot hide a full-VAE fallback',
          () async {
            driver.status = _available(iphone);
            for (final header in [
              ImageModelHeaders.taesd,
              ImageModelHeaders.pickle,
            ]) {
              driver
                ..started.clear()
                ..headers[_taesd] = header
                ..session = _FakeSession();
              final model = ImageGenerationModel(
                _local(_model),
                components: [
                  ImageModelComponent(
                    _local(_taesd),
                    role: ImageModelRole.taesd,
                  ),
                ],
              );
              await expectLater(
                load(model),
                throwsA(isA<LlamaUnsupportedException>()),
              );
              expect(driver.started, isEmpty);
              expect(driver.session.disposeCalls, 0);
              expect(driver.session.requests, isEmpty);
            }
            driver
              ..session = _FakeSession()
              ..headers[_taesd] = ImageModelHeaders.taesd;
            await load(
              _sdxs(null, _local(_taesd)),
              placement: const ImageModelPlacement(vaeOnCpu: true),
            );
            expect(driver.started.last.backend, 'vae=cpu');
          },
        );

        test(
          'tiny header markers and unknown native families fail closed',
          () async {
            driver
              ..status = _available(iphone)
              ..headers[_model] = ggufHeader(
                tensors: [
                  (
                    'model.diffusion_model.input_blocks.0.0.weight',
                    [3, 3, 4, 320],
                  ),
                  ('model.diffusion_model.out.2.weight', [3, 3, 320, 4]),
                  (
                    'model.diffusion_model.middle_block.1.proj_in.weight',
                    [1, 1, 1280, 1280],
                  ),
                  ('first_stage_model.decoder.conv_in.weight', [3, 3, 4, 512]),
                  ('first_stage_model.quant_conv.weight', [1, 1, 8, 8]),
                  ('first_stage_model.decoder.layers.0.weight', [3, 3, 4, 64]),
                  (
                    'cond_stage_model.model.token_embedding.weight',
                    [1024, 49408],
                  ),
                ],
              );
            for (final family in ['', 'Unknown', 'SD 2.x', 'SDXL', 'SDXS']) {
              driver.session = _FakeSession()..modelVersion = family;
              await expectLater(
                load(checkpoint),
                throwsA(isA<LlamaUnsupportedException>()),
              );
              expect(driver.session.disposeCalls, 1, reason: family);
              expect(driver.session.requests, isEmpty);
            }
          },
        );

        test(
          'a qualified old runtime refuses intrinsic SDXS before native creation',
          () async {
            driver
              ..status = _available(
                iphone,
                supportsIntrinsicTinyDecoderV1: false,
              )
              ..headers[_model] = ImageModelHeaders.sdxsCheckpoint
              ..session = (_FakeSession()..modelVersion = 'SDXS (512-DS)');
            await expectLater(
              load(checkpoint),
              throwsA(
                isA<LlamaUnsupportedException>().having(
                  (error) => error.message,
                  'remedy',
                  allOf(
                    contains('intrinsic tiny-decoder v1'),
                    contains('intrinsic SDXS tiny decoder'),
                    contains('selected runtime'),
                    isNot(contains('current pinned')),
                    contains('vaeOnCpu: true'),
                  ),
                ),
              ),
            );
            expect(driver.started, isEmpty);
          },
        );

        test('an unqualified runtime refuses even tiny candidates before '
            'native creation', () async {
          driver.status = StableDiffusionRuntimeStatus.available(
            version: 'unknown',
            commit: 'unknown',
            devices: parseStableDiffusionDeviceList(iphone),
          );
          await expectLater(
            load(_sdxs(null, _local(_taesd))),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          expect(driver.started, isEmpty);
        });

        test('the full pinned commit without the policy refuses SDXS and other '
            'runtimes keep CPU alternatives', () async {
          driver
            ..status = StableDiffusionRuntimeStatus.available(
              version: 'master-1017',
              commit: 'be486498eadc29dc3cd234d944c2180ed42b1415',
              devices: parseStableDiffusionDeviceList(iphone),
            )
            ..headers[_model] = ImageModelHeaders.sdxsCheckpoint
            ..session = (_FakeSession()..modelVersion = 'SDXS (512-DS)');
          await expectLater(
            load(checkpoint),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          expect(driver.started, isEmpty);
          expect(driver.session.disposed, isFalse);
          driver
            ..status = StableDiffusionRuntimeStatus.available(
              version: 'unknown',
              commit: 'unknown',
              devices: parseStableDiffusionDeviceList(iphone),
            )
            ..headers[_model] = ImageModelHeaders.sdTurboCheckpoint
            ..session = _FakeSession();
          await load(
            checkpoint,
            placement: const ImageModelPlacement(vaeOnCpu: true),
          );
          expect(driver.started.last.backend, 'vae=cpu');
          driver.session = _FakeSession();
          await load(
            checkpoint,
            params: const ImageModelParams(device: ComputeDevice.cpu),
          );
          expect(driver.started.last.backend, 'cpu');
        });

        test('true loads on the CPU', () async {
          final config = await startedWith(
            iphone,
            checkpoint,
            params: const ImageModelParams(
              device: ComputeDevice.cpu,
              vaeDirectConvolution: true,
            ),
          );
          expect(config.vaeDirectConvolution, isTrue);
        });
      });

      test('true loads on Metal off iOS, and on every backend of other '
          'platforms', () async {
        for (final (os, devices) in [
          ('macos', metal),
          ('linux', vulkan),
          ('android', cpu),
          ('windows', vulkan),
        ]) {
          driver.operatingSystem = os;
          final config = await startedWith(
            devices,
            checkpoint,
            params: const ImageModelParams(vaeDirectConvolution: true),
          );
          expect(config.vaeDirectConvolution, isTrue, reason: os);
        }
      });
    });

    test('gpu selects the first GPU the runtime reports', () async {
      driver.status = _available('Vulkan0\tAMD Radeon\nCPU\tHost\n');

      final engine = await load(
        _sdxs(),
        params: const ImageModelParams(device: ComputeDevice.gpu),
      );

      expect(driver.started.single.backend, 'gpu');
      expect((await engine.capabilities).backendName, 'Vulkan0');
    });

    test('gpu without a GPU device throws LlamaUnsupportedException', () async {
      driver.status = _available('CPU\tCortex-A78\n');

      await expectLater(
        load(
          _sdxs(),
          params: const ImageModelParams(device: ComputeDevice.gpu),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('ComputeDevice.gpu needs a GPU'),
              contains('reports only CPU'),
              contains('llamadart_stable_diffusion_backends'),
            ),
          ),
        ),
      );
      expect(driver.started, isEmpty);

      final engine = await load(_sdxs());
      expect((await engine.capabilities).backendName, 'CPU');
    });

    test('a missing file throws LlamaModelException naming its position, '
        'not its path', () async {
      driver.sizes.remove(_taesd);

      await expectLater(
        load(_sdxs(_local(_model), _local(_taesd))),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            allOf(contains('component 1'), isNot(contains(_taesd))),
          ),
        ),
      );
      await expectLater(
        load(_sdxs(_local('  '))),
        throwsA(isA<LlamaModelException>()),
      );
      expect(driver.started, isEmpty);
    });

    test('a set without diffusion weights is rejected', () async {
      await expectLater(
        load(
          ImageGenerationModel(
            _local(_ae),
            components: [ImageModelComponent.auto(_local(_clipL))],
          ),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('None of the image model files holds diffusion weights'),
          ),
        ),
      );
      expect(driver.started, isEmpty);
    });

    test('ComputeDevice.npu is unsupported', () async {
      await expectLater(
        load(
          _sdxs(),
          params: const ImageModelParams(device: ComputeDevice.npu),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('no NPU backend'),
          ),
        ),
      );
      expect(downloads.calls, isEmpty);
    });

    test('a LiteRT-LM source format is unsupported', () async {
      await expectLater(
        load(_sdxs(ModelSource.path(_model, format: ModelFormat.liteRtLm))),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(downloads.calls, isEmpty);
    });

    test('a GGUF source format loads like no format', () async {
      await load(_sdxs(ModelSource.path(_model, format: ModelFormat.gguf)));
    });

    for (final capacity in [
      null,
      0,
      1,
      ImageConditioningCacheParams.maxCapacity,
    ]) {
      test(
        'forwards conditioning cache capacity $capacity to the session',
        () async {
          final engine = await load(
            _sdxs(),
            params: capacity == null
                ? const ImageModelParams()
                : ImageConditioningCacheParams(capacity: capacity),
          );
          expect(
            engine.params is ImageConditioningCacheParams,
            capacity != null,
          );
          expect(driver.started.single.conditioningCacheSize, capacity);
        },
      );
    }

    for (final capacity in [-1, ImageConditioningCacheParams.maxCapacity + 1]) {
      test(
        'rejects conditioning cache capacity $capacity before file resolution',
        () async {
          await expectLater(
            load(
              _sdxs(ModelSource.parse('https://example.com/model.gguf')),
              params: ImageConditioningCacheParams(capacity: capacity),
            ),
            throwsA(
              isA<LlamaImageGenerationException>().having(
                (error) => error.message,
                'message',
                contains('ImageConditioningCacheParams.capacity'),
              ),
            ),
          );
          expect(downloads.calls, isEmpty);
          expect(driver.started, isEmpty);
        },
      );
    }

    test(
      'legacy external implementations and subclasses preserve default cache settings',
      () async {
        for (final legacy in [
          const LegacyImageModelParams(),
          const LegacyImageModelSubclass(),
        ]) {
          final engine = await load(_sdxs(), params: legacy);
          expect(engine.params, same(legacy));
          final config = driver.started.last;
          expect(config.conditioningCacheSize, isNull);
          expect(config.backend, 'cpu');
          expect(config.threads, legacy.threads);
        }
      },
    );

    test(
      'explicit cache settings preserve every inherited runtime option',
      () async {
        const params = ImageConditioningCacheParams(
          capacity: 2,
          device: ComputeDevice.cpu,
          threads: 5,
          checkMemory: false,
          flashAttention: false,
          vaeDirectConvolution: false,
        );
        final engine = await load(_sdxs(), params: params);
        expect(engine.params, same(params));
        final config = driver.started.single;
        expect(config.conditioningCacheSize, 2);
        expect(config.backend, 'cpu');
        expect(config.threads, 5);
        expect(config.flashAttention, isFalse);
        expect(config.vaeDirectConvolution, isFalse);
        expect(driver.budgetDevices, isEmpty);
      },
    );

    test('negative threads are rejected', () async {
      await expectLater(
        load(_sdxs(), params: const ImageModelParams(threads: -1)),
        throwsA(isA<LlamaImageGenerationException>()),
      );
    });

    test(
      'a load failure propagates and frees the one-operation slot',
      () async {
        driver.startError = LlamaModelException('not an image model');

        await expectLater(load(_sdxs()), throwsA(isA<LlamaModelException>()));

        driver.startError = null;
        await load(_sdxs());
      },
    );

    test('a cancel during the native load frees what it loaded and leaves '
        'nothing loaded', () async {
      final cancelToken = ModelDownloadCancelToken();
      final gate = driver.startGate = Completer<void>();

      final loading = load(
        _fluxModel(),
        download: ModelLoadOptions(cancelToken: cancelToken),
      );
      await pumpEventQueue();
      expect(driver.started, hasLength(1));
      cancelToken.cancel();
      gate.complete();

      await expectLater(
        loading,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Image model loading was cancelled.',
          ),
        ),
      );
      expect(driver.session.disposeCalls, 1);

      driver.startGate = null;
      final engine = await load(_sdxs());
      expect((await engine.capabilities).isSupported, isTrue);
    });

    test('a cancel during header classification starts nothing', () async {
      final cancelToken = ModelDownloadCancelToken();
      final gate = driver.readGate = Completer<void>();

      final loading = load(
        _fluxModel(),
        download: ModelLoadOptions(cancelToken: cancelToken),
      );
      await pumpEventQueue();
      cancelToken.cancel();
      gate.complete();

      await expectLater(loading, throwsA(isA<LlamaStateException>()));
      expect(driver.started, isEmpty);
      expect(driver.session.disposeCalls, 0);
    });

    test('a runtime failure leaves nothing loaded, and the next load starts '
        'from scratch', () async {
      driver.startError = LlamaModelException('not an image model');

      await expectLater(
        load(_fluxModel()),
        throwsA(isA<LlamaModelException>()),
      );
      expect(driver.started, isEmpty);

      driver.startError = null;
      final engine = await load(_sdxs());
      expect(driver.started.single.files, {'model': _model});
      expect((await engine.capabilities).isSupported, isTrue);
    });

    test('passes each role to the runtime under its runtime name', () async {
      const sd35 = '/models/sd35.gguf';
      const clipG = '/models/clip_g.gguf';
      const taesd3 = '/models/taesd3.safetensors';
      const zImage = '/models/z_image.gguf';
      const qwen = '/models/qwen3.gguf';
      driver
        ..sizes.addAll({
          sd35: _gib,
          clipG: _gib,
          taesd3: 1 << 20,
          zImage: _gib,
          qwen: _gib,
        })
        ..headers.addAll({
          sd35: ImageModelHeaders.sd35Diffusion,
          clipG: ImageModelHeaders.clipG,
          taesd3: ImageModelHeaders.taef1,
          zImage: ImageModelHeaders.zImageDiffusion,
          qwen: ImageModelHeaders.qwen3Llm,
        });
      ImageGenerationModel split(String main, List<String> components) =>
          ImageGenerationModel(
            _local(main),
            components: [
              for (final path in components)
                ImageModelComponent.auto(_local(path)),
            ],
          );

      for (final (model, files) in [
        (
          _sdxs(_local(_model), _local(_taesd)),
          {'model': _model, 'taesd': _taesd},
        ),
        (
          split(sd35, [clipG, _t5xxl, taesd3, _clipL]),
          {
            'diffusionModel': sd35,
            'taesd': taesd3,
            'clipL': _clipL,
            'clipG': clipG,
            't5xxl': _t5xxl,
          },
        ),
        (
          split(qwen, [_ae, zImage]),
          {'diffusionModel': zImage, 'vae': _ae, 'llm': qwen},
        ),
      ]) {
        final engine = await load(model);
        await engine.dispose();
        expect(driver.started.last.files, files);
      }
    });

    for (final fails in [false, true]) {
      test(
        'disposal publishes terminal state before session cleanup (fails=$fails)',
        () async {
          final engine = await load(_sdxs());
          Future<void>? nested;
          bool? stateInHook;
          Future<ImageGenerationCapabilities>? capsInHook;
          final error = StateError('image cleanup');
          driver.session.onDispose = () {
            driver.session.onDispose = null;
            stateInHook = engine.isDisposed;
            capsInHook = engine.capabilities;
            nested = engine.dispose();
          };
          if (fails) driver.session.disposeError = error;
          final first = engine.dispose();
          if (fails) {
            await expectLater(first, throwsA(same(error)));
            await expectLater(nested, throwsA(same(error)));
            engines.remove(engine);
          } else {
            await first;
            await nested;
          }
          expect(stateInHook, isTrue);
          expect(nested, same(first));
          expect((await capsInHook!).isSupported, isFalse);
          expect(engine.dispose(), same(first));
          expect(driver.session.disposeCalls, 1);
        },
      );
    }

    test('dispose is idempotent', () async {
      final engine = await load(_sdxs());

      final first = engine.dispose();
      final second = engine.dispose();
      expect(second, same(first));
      await first;
      await engine.dispose();

      expect(engine.isDisposed, isTrue);
      expect(driver.session.disposeCalls, 1);
      final capabilities = await engine.capabilities;
      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        'The ImageGenerationEngine is disposed.',
      );
    });
  });

  group('model sources', () {
    test('resolves every file through the manager, then assigns roles to '
        'the local copies', () async {
      final flux = ModelSource.parse('hf://owner/flux@0123abc/flux.gguf');
      final ae = ModelSource.url(
        Uri.parse('https://example.com/ae.safetensors'),
      );
      final t5xxl = ModelSource.parse('hf://owner/t5@0123abc/t5xxl.gguf');
      downloads.remoteHeaders
        ..['flux.gguf'] = ImageModelHeaders.fluxDiffusion
        ..['ae.safetensors'] = ImageModelHeaders.fluxVae
        ..['t5xxl.gguf'] = ImageModelHeaders.t5xxl;

      final engine = await load(
        ImageGenerationModel(
          t5xxl,
          components: [
            ImageModelComponent.auto(_local(_clipL)),
            ImageModelComponent.auto(flux),
            ImageModelComponent.auto(ae),
          ],
        ),
      );

      expect(
        [for (final (source, _) in downloads.calls) source.canonicalKey],
        [
          for (final source in [t5xxl, _local(_clipL), flux, ae])
            source.canonicalKey,
        ],
      );
      expect(driver.started.single.files, {
        'diffusionModel': _FakeDownloads.cachePath(flux),
        'vae': _FakeDownloads.cachePath(ae),
        'clipL': _clipL,
        't5xxl': _FakeDownloads.cachePath(t5xxl),
      });
      expect(engine.roles[ImageModelRole.diffusionModel], flux);
      expect(
        downloads.calls.first.$1.resolvedUri.toString(),
        'https://huggingface.co/owner/t5/resolve/0123abc/t5xxl.gguf'
        '?download=true',
      );
    });

    test('a non-component file fails after its download, starts nothing, '
        'and keeps the download cached', () async {
      final lora = ModelSource.parse(
        'hf://owner/lora@0123abc/lora.safetensors',
      );
      downloads.remoteHeaders['lora.safetensors'] = ImageModelHeaders.lora;

      await expectLater(
        load(_sdxs(_local(_model), lora)),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            allOf(
              startsWith('Component 1 is a LoRA adapter'),
              isNot(contains('lora.safetensors')),
            ),
          ),
        ),
      );
      expect(driver.started, isEmpty);
      expect(downloads.cached, contains(lora.canonicalKey));
    });

    test('a model cache directory that cannot be created fails the load with '
        'LlamaModelException', () async {
      await expectLater(
        ImageGenerationEngine.load(
          _sdxs(ModelSource.parse('http://127.0.0.1:9/sdxs.gguf')),
          download: ModelLoadOptions(
            // A path under a file, which no directory can be created at.
            cacheDirectory: '/dev/null/llamadart-cache',
            maxRetries: 0,
          ),
          store: ModelFileStore(
            downloadManager: DefaultModelDownloadManager(
              defaultCacheDirectory: '/dev/null/llamadart-cache',
            ),
          ),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('Cannot create the model cache directory'),
          ),
        ),
      );
      expect(driver.started, isEmpty);
    }, testOn: 'vm && !windows');

    test('remote-only options reach only remote files', () async {
      const cacheDirectory = '/models/cache';

      await load(
        _sdxs(_remote, _local(_taesd)),
        download: ModelLoadOptions(
          bearerToken: 'hf_secret',
          cacheDirectory: cacheDirectory,
        ),
      );

      final [(remote, remoteOptions), (local, localOptions)] = downloads.calls;
      expect(remote.isRemote, isTrue);
      expect(remoteOptions.bearerToken, 'hf_secret');
      expect(remoteOptions.cacheDirectory, cacheDirectory);
      expect(local.isLocal, isTrue);
      expect(localOptions.bearerToken, isNull);
      expect(localOptions.cacheDirectory, isNull);
    });

    test('credentials for remote files on more than one host are rejected '
        'before anything downloads', () async {
      final otherHost = ModelSource.url(
        Uri.parse('https://cdn.example.com/taesd.safetensors'),
      );

      await expectLater(
        load(
          _sdxs(_remote, otherHost),
          download: ModelLoadOptions(bearerToken: 'hf_secret'),
        ),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('https://cdn.example.com:443'),
              isNot(contains('hf_secret')),
            ),
          ),
        ),
      );
      expect(downloads.calls, isEmpty);
    });

    test('reports progress across files, counting cached ones as '
        'received', () async {
      downloads.remoteSizes
        ..['sdxs.gguf'] = 8192
        ..['taesd.safetensors'] = 1024;
      downloads.cached.add(_remote.canonicalKey);
      downloads.cached.remove(_remoteTaesd.canonicalKey);
      final events = <ModelDownloadProgress>[];

      await load(_sdxs(_remote, _remoteTaesd), onProgress: events.add);

      expect(downloads.downloaded, ['taesd.safetensors']);
      expect(events.map((e) => (e.receivedBytes, e.totalBytes)), [
        (8192, null),
        (8192 + 512, 8192 + 1024),
        (8192 + 1024, 8192 + 1024),
        (8192 + 1024, 8192 + 1024),
      ]);
    });

    test('local file sizes count toward the total from the start', () async {
      downloads.remoteSizes['late.gguf'] = 1024;
      downloads.remoteHeaders['late.gguf'] = ImageModelHeaders.taesd;
      final events = <ModelDownloadProgress>[];

      await load(
        _sdxs(
          _local(_model),
          ModelSource.url(Uri.parse('https://example.com/late.gguf')),
        ),
        onProgress: events.add,
      );

      expect(events.first.totalBytes, isNull);
      expect(events.first.receivedBytes, 651 << 20);
      expect(events.last.receivedBytes, (651 << 20) + 1024);
      expect(events.last.totalBytes, (651 << 20) + 1024);

      events.clear();
      await load(_sdxs(_local(_model), _local(_taesd)), onProgress: events.add);
      expect(events.map((e) => e.totalBytes), everyElement((660 << 20)));
    });

    test('a second load reuses the cache instead of downloading', () async {
      await load(_sdxs(_remote));
      await load(_sdxs(_remote));

      expect(downloads.downloaded, ['sdxs.gguf']);
      expect(downloads.calls, hasLength(2));
    });

    test('a cancelled load stops downloading, starts nothing and frees the '
        'slot', () async {
      final cancelToken = ModelDownloadCancelToken();
      final gate = downloads.gate = Completer<void>();

      final loading = load(
        _sdxs(_remote, _remoteTaesd),
        download: ModelLoadOptions(cancelToken: cancelToken),
      );
      await pumpEventQueue();
      cancelToken.cancel();
      gate.complete();

      await expectLater(loading, throwsA(isA<LlamaStateException>()));
      expect(downloads.calls, hasLength(1));
      expect(driver.started, isEmpty);

      downloads.gate = null;
      await load(_sdxs());
    });

    test('a cancel after the last file resolves stops before the runtime '
        'loads', () async {
      final cancelToken = ModelDownloadCancelToken();
      downloads.remoteSizes['sdxs.gguf'] = 4096;

      await expectLater(
        load(
          _sdxs(_remote),
          download: ModelLoadOptions(cancelToken: cancelToken),
          onProgress: (progress) {
            if (progress.receivedBytes == 4096) {
              cancelToken.cancel();
            }
          },
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );
      expect(driver.started, isEmpty);
    });

    test('a download failure surfaces as the download manager threw '
        'it', () async {
      final failure = LlamaModelException('Failed to download sdxs.gguf.');
      downloads.error = failure;

      await expectLater(load(_sdxs(_remote)), throwsA(same(failure)));
      expect(driver.started, isEmpty);
    });

    test('a missing local file fails before anything downloads', () async {
      await expectLater(
        load(
          ImageGenerationModel(
            _remote,
            components: [
              ImageModelComponent.auto(_local(_clipL)),
              ImageModelComponent.auto(_local('/models/missing.gguf')),
            ],
          ),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            allOf(contains('component 2'), isNot(contains('missing.gguf'))),
          ),
        ),
      );
      expect(downloads.calls, isEmpty);
    });

    test('an unavailable runtime throws before anything downloads', () async {
      driver.status = StableDiffusionRuntimeStatus.unavailable(
        LlamaUnsupportedException('not published for android-x64'),
      );

      await expectLater(
        load(_sdxs(_remote)),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(downloads.calls, isEmpty);
    });

    for (final (name, source) in [
      ('local', _local(_model)),
      ('remote', _remote),
    ]) {
      test('a checksum verifies a single $name file', () async {
        final checksum = 'a' * 64;

        await load(_sdxs(source), download: ModelLoadOptions(sha256: checksum));

        expect(downloads.calls.single.$2.sha256, checksum);
      });
    }

    for (final (name, source, message) in [
      (
        'local',
        _local(_model),
        'Checksum mismatch for local model file: $_model.',
      ),
      (
        'remote',
        _remote,
        'Checksum mismatch for hf://owner/sdxs@0123abc/sdxs.gguf.',
      ),
    ]) {
      test('a checksum mismatch for a single $name file names it by '
          'position', () async {
        downloads.checksumError = LlamaModelException(message);

        await expectLater(
          load(_sdxs(source), download: ModelLoadOptions(sha256: 'a' * 64)),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              allOf(
                equals(
                  'Checksum mismatch for the main file: its SHA-256 does not '
                  'match ModelLoadOptions.sha256.',
                ),
                isNot(contains('sdxs')),
                isNot(contains('/models')),
              ),
            ),
          ),
        );
        expect(driver.started, isEmpty);
      });
    }

    test('a download manager\'s own checksum error passes through when the '
        'load sets no sha256', () async {
      final failure = LlamaModelException(
        'Checksum mismatch for ${_local(_model)}.',
      );
      downloads.unconditionalError = failure;

      await expectLater(load(_sdxs(_local(_model))), throwsA(same(failure)));
    });

    test(
      'another model error from a checksummed load passes through',
      () async {
        final failure = LlamaModelException('Local model file does not exist.');
        downloads.checksumError = failure;

        await expectLater(
          load(_sdxs(), download: ModelLoadOptions(sha256: 'a' * 64)),
          throwsA(same(failure)),
        );
      },
    );

    test('a checksum for several files is rejected before anything '
        'downloads', () async {
      await expectLater(
        load(
          _sdxs(_remote, _remoteTaesd),
          download: ModelLoadOptions(sha256: 'a' * 64),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('2 files'), contains('ModelLoadOptions.sha256')),
          ),
        ),
      );
      expect(downloads.calls, isEmpty);
    });

    test('resolves through the given resolver, and keeps a signed URL out of '
        'its errors', () async {
      final signed = Uri.parse(
        'https://example.com/sdxs.gguf?X-Amz-Signature=supersecret',
      );

      await expectLater(
        load(
          _sdxs(_remote),
          resolver: _RemoteTargetResolver(signed, useBrowserCache: false),
          download: ModelLoadOptions(bearerToken: 'hf_secret'),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => '${error.message} ${error.details}',
            'message',
            allOf(
              contains('image model'),
              isNot(contains('supersecret')),
              isNot(contains('hf_secret')),
            ),
          ),
        ),
      );

      await load(
        _sdxs(_remote),
        resolver: _RemoteTargetResolver(signed, useBrowserCache: true),
      );
      final (source, _) = downloads.calls.single;
      expect(source.resolvedUri, signed);
      expect(source.canonicalKey, _remote.canonicalKey);
    });

    test('the memory check counts downloaded files', () async {
      driver.budget = (bytes: _gib, source: 'test budget');
      downloads.remoteSizes['sdxs.gguf'] = 2 * _gib;

      await expectLater(
        load(_sdxs(_remote)),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('2.00 GiB of weights'),
          ),
        ),
      );
      expect(downloads.downloaded, ['sdxs.gguf']);
      expect(driver.started, isEmpty);
    });
  });

  group('memory preflight', () {
    test('refuses a model whose estimate exceeds the budget', () async {
      driver.sizes[_model] = 2 * _gib;
      driver.budget = (
        bytes: 2 * _gib,
        source: 'MemAvailable in /proc/meminfo',
      );

      await expectLater(
        load(_sdxs()),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('about 3.00 GiB'),
              contains('2.00 GiB of weights'),
              contains('only 2.00 GiB is available'),
              contains('MemAvailable in /proc/meminfo'),
              contains('checkMemory'),
            ),
          ),
        ),
      );
      expect(driver.started, isEmpty);
    });

    group('on a Vulkan GPU', () {
      const gpuFigure = (
        bytes: 6 * _gib,
        source: 'free GPU memory of Vulkan0 (NVIDIA L4), out of 22.5 GiB',
      );
      const gpuAndHost = (
        bytes: 10 * _gib,
        source:
            '6.00 GiB of GPU memory and 4.00 GiB of system memory: free GPU '
            'memory of Vulkan0 (NVIDIA L4), out of 22.5 GiB; MemAvailable in '
            '/proc/meminfo',
      );
      late List<LlamaLogRecord> records;

      setUp(() {
        driver.status = _available('Vulkan0\tNVIDIA L4\nCPU\tHost\n');
        records = [];
        final logger = LlamaLogger.instance;
        final level = logger.level;
        logger
          ..setLevel(LlamaLogLevel.debug)
          ..setHandler(records.add);
        addTearDown(() {
          logger
            ..setLevel(level)
            ..setHandler(null);
        });
      });

      test('refuses a model that fits neither the GPU nor the GPU plus '
          'system memory, naming the estimate and both figures', () async {
        driver
          ..sizes[_model] = 8 * _gib
          ..budget = gpuAndHost
          ..slowerBudget = gpuFigure;

        await expectLater(
          load(_sdxs()),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('about 10.5 GiB'),
                contains('only 10.0 GiB is available'),
                contains('6.00 GiB of GPU memory'),
                contains('4.00 GiB of system memory'),
                contains('Vulkan0 (NVIDIA L4)'),
                contains('MemAvailable in /proc/meminfo'),
              ),
            ),
          ),
        );
        expect(driver.budgetDevices, [ImageGenerationComputeDevice.otherGpu]);
        expect(driver.started, isEmpty);
        expect(records, isEmpty);
      });

      test('loads a model larger than the GPU that fits the GPU plus system '
          'memory, with one warning that names the figures', () async {
        driver
          ..sizes[_model] = 6 * _gib
          ..budget = gpuAndHost
          ..slowerBudget = gpuFigure;

        await load(_sdxs());

        expect(driver.started, hasLength(1));
        expect(records, hasLength(1));
        expect(records.single.level, LlamaLogLevel.warn);
        expect(
          records.single.message,
          'The image model needs about 8.00 GiB (6.00 GiB of weights plus '
          'working memory), more than the 6.00 GiB available (free GPU '
          'memory of Vulkan0 (NVIDIA L4), out of 22.5 GiB). '
          'stable-diffusion.cpp keeps the part that does not fit in system '
          'memory, so generation will be slower.',
        );
      });

      test('the estimate has to exceed a figure, not reach it', () async {
        // 4 GiB of weights are estimated at 5.5 GiB, and 8 GiB at 10.5 GiB.
        driver
          ..slowerBudget = (bytes: 11 * _gib ~/ 2, source: 'the GPU')
          ..budget = (bytes: 21 * _gib ~/ 2, source: 'the GPU and the host');

        driver.sizes[_model] = 4 * _gib;
        await load(_sdxs());
        expect(records, isEmpty);

        driver.sizes[_model] = 8 * _gib;
        await load(_sdxs());
        expect(records, hasLength(1));
        expect(driver.started, hasLength(2));

        driver.sizes[_model] = 8 * _gib + 4;
        await expectLater(load(_sdxs()), throwsA(isA<LlamaModelException>()));
        driver.sizes[_model] = 4 * _gib + 4;
        await load(_sdxs());
        expect(records, hasLength(2));
      });

      test('where host memory is not read, as on Windows, a model of any '
          'size loads with the warning', () async {
        driver
          ..sizes[_model] = 64 * _gib
          ..budget = null
          ..slowerBudget = gpuFigure;

        await load(_sdxs());

        expect(driver.started, hasLength(1));
        expect(records.single.level, LlamaLogLevel.warn);
        expect(records.single.message, contains('more than the 6.00 GiB'));
      });

      test('says that the runtime picks the GPU for ComputeDevice.auto, '
          'and that it does not for ComputeDevice.gpu', () async {
        driver.status = _available(
          'Vulkan0\tGTX 1650\nVulkan1\tRTX 4090\nCPU\tHost\n',
        );

        await load(_sdxs());
        await load(
          _sdxs(),
          params: const ImageModelParams(device: ComputeDevice.gpu),
        );

        expect(driver.runtimePicks, [true, false]);
        expect(
          driver.budgetDevices,
          everyElement(ImageGenerationComputeDevice.otherGpu),
        );
      });

      test('with a small GPU listed before a large one, a model that fits '
          'the large one loads: 16.8 GiB against 4, 24 and 9 GiB', () async {
        driver
          ..status = _available(
            'Vulkan0\tGTX 1650\nVulkan1\tRTX 4090\nCPU\tHost\n',
          )
          // 13.04 GiB of weights are estimated at 16.8 GiB.
          ..sizes[_model] = 1304 * _gib ~/ 100
          ..slowerBudget = (bytes: 24 * _gib, source: 'Vulkan1')
          ..budget = (bytes: 37 * _gib, source: 'two GPUs and the host');

        await load(_sdxs());

        expect(driver.started, hasLength(1));
        expect(records, isEmpty);
      });

      test('a model that fits the GPU loads without a warning', () async {
        driver
          ..sizes[_model] = 2 * _gib
          ..budget = gpuAndHost
          ..slowerBudget = gpuFigure;

        await load(_sdxs());

        expect(driver.started, hasLength(1));
        expect(records, isEmpty);
      });

      test('checkMemory false neither asks, refuses nor warns', () async {
        driver
          ..sizes[_model] = 64 * _gib
          ..budget = gpuAndHost
          ..slowerBudget = gpuFigure;

        await load(_sdxs(), params: const ImageModelParams(checkMemory: false));

        expect(driver.budgetDevices, isEmpty);
        expect(driver.started, hasLength(1));
        expect(records, isEmpty);
      });
    });

    test('counts every file toward the estimate', () async {
      driver.sizes[_model] = _gib;
      driver.sizes[_taesd] = _gib;
      final required = estimateImageGenerationMemoryBytes(2 * _gib);
      driver.budget = (bytes: required - 1, source: 'physical memory');

      await expectLater(
        load(_sdxs(_local(_model), _local(_taesd))),
        throwsA(isA<LlamaModelException>()),
      );

      driver.budget = (bytes: required, source: 'physical memory');
      await load(_sdxs(_local(_model), _local(_taesd)));
    });

    test('counts FP8 weights at F16 size on Metal when the runtime loads '
        'them so', () async {
      const elements = 3 << 20;
      driver.sizes[_model] = _gib;
      driver.headers[_model] = safetensorsHeader([
        ('model.diffusion_model.weight', [3, 1 << 20]),
      ], dtype: 'F8_E4M3');
      final required = estimateImageGenerationMemoryBytes(_gib + elements);
      for (final (loadsFp8, device, budget, refused) in [
        (true, ComputeDevice.auto, required - 1, true),
        (true, ComputeDevice.auto, required, false),
        (true, ComputeDevice.cpu, required - 1, false),
        (false, ComputeDevice.cpu, required - 1, false),
      ]) {
        driver.status = _available(
          'MTL0\tApple M4\nCPU\tApple M4\n',
          loadsFp8AsF16OnMetal: loadsFp8,
        );
        driver.budget = (bytes: budget, source: 'physical memory');
        final loading = load(_sdxs(), params: ImageModelParams(device: device));
        if (refused) {
          await expectLater(loading, throwsA(isA<LlamaModelException>()));
        } else {
          await loading;
        }
      }
    });

    test('is skipped without a budget or when checkMemory is false', () async {
      driver.sizes[_model] = 64 * _gib;

      await load(_sdxs());

      driver.budget = (bytes: _gib, source: 'physical memory');
      await load(_sdxs(), params: const ImageModelParams(checkMemory: false));
      expect(driver.started, hasLength(2));
    });

    test('the estimate adds a quarter and 512 MiB to the weights', () {
      expect(estimateImageGenerationMemoryBytes(0), 512 << 20);
      expect(
        estimateImageGenerationMemoryBytes(4 * _gib),
        5 * _gib + (512 << 20),
      );
    });

    test('asks for the budget of the device the model loads on', () async {
      for (final (devices, device, expected) in [
        (
          'MTL0\tApple M4\nCPU\tApple M4\n',
          ComputeDevice.auto,
          ImageGenerationComputeDevice.metal,
        ),
        (
          'MTL0\tApple M4\nCPU\tApple M4\n',
          ComputeDevice.cpu,
          ImageGenerationComputeDevice.cpu,
        ),
        (
          'Vulkan0\tNVIDIA L4\nCPU\tHost\n',
          ComputeDevice.auto,
          ImageGenerationComputeDevice.otherGpu,
        ),
        (
          'CPU\tCortex-A78\n',
          ComputeDevice.auto,
          ImageGenerationComputeDevice.cpu,
        ),
      ]) {
        driver
          ..status = _available(devices)
          ..budgetDevices.clear();
        await load(_sdxs(), params: ImageModelParams(device: device));
        expect(driver.budgetDevices, [expected], reason: devices);
      }
    });
  });

  group('generate', () {
    test(
      'legacy/custom backend without tiling probe refuses opt-in only',
      () async {
        final old = _LegacySession(driver.session);
        driver.sessionOverride = old;
        final engine = await load(_sdxs());
        await expectLater(
          engine.generate(
            const TiledImageGenerationRequest(
              prompt: 'a',
              vaeTiling: ImageVaeTiling(),
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(driver.session.requests, isEmpty);
        await engine.generateImage(const ImageGenerationRequest(prompt: 'a'));
        expect(driver.session.requests.single.vaeTiling, isNull);
      },
    );

    test(
      'unknown runtime refuses tiling while ordinary requests still work',
      () async {
        driver.status = StableDiffusionRuntimeStatus.available(
          version: 'unknown',
          commit: 'unknown',
          devices: parseStableDiffusionDeviceList('CPU\tCPU\n'),
        );
        final engine = await load(_sdxs());
        await expectLater(
          engine.generate(
            const TiledImageGenerationRequest(
              prompt: 'a',
              vaeTiling: ImageVaeTiling(),
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await engine.generateImage(const ImageGenerationRequest(prompt: 'a'));
      },
    );

    test(
      'tiled cancellation, disposal and subsequent ordinary reuse stay isolated',
      () async {
        final engine = await load(
          _sdxs(),
          params: const ImageConditioningCacheParams(capacity: 0),
        );
        driver.session.gate = Completer<void>();
        final task = await engine.generate(
          const TiledImageGenerationRequest(
            prompt: 'a',
            steps: 4,
            vaeTiling: ImageVaeTiling(),
          ),
        );
        task.cancel();
        driver.session.gate!.complete();
        expect(
          (await task.done).state,
          ImageGenerationCompletionState.cancelled,
        );
        driver.session.gate = null;
        await engine.generateImage(const ImageGenerationRequest(prompt: 'a'));
        expect(driver.session.requests.map((r) => r.vaeTiling != null), [
          true,
          false,
        ]);
        driver.session.gate = Completer<void>();
        final disposing = await engine.generate(
          const TiledImageGenerationRequest(
            prompt: 'a',
            steps: 4,
            vaeTiling: ImageVaeTiling(),
          ),
        );
        final disposed = engine.dispose();
        driver.session.gate!.complete();
        await disposed;
        expect(
          (await disposing.done).state,
          ImageGenerationCompletionState.cancelled,
        );
        expect(driver.session.disposedAfterGenerate, isTrue);
      },
    );

    test(
      'legacy implementation and subclass requests retain defaults',
      () async {
        final legacy = LegacyImageGenerationEngine();
        await legacy.warmUp(width: 512, height: 512, guidanceScale: 1);
        expect(legacy.warmUpCalls, 1);
        final engine = await load(_sdxs());
        for (final request in [
          const LegacyImageGenerationRequest(),
          const LegacyImageGenerationRequestSubclass(),
        ]) {
          await engine.generateImage(request);
        }
        expect(driver.session.requests.map((r) => r.vaeTiling), [null, null]);
        expect(driver.session.requests.map((r) => r.prompt), [
          'legacy stone',
          'legacy subclass',
        ]);
      },
    );

    test(
      'tiling refuses other family, decoder proof and device recipes',
      () async {
        for (final family in [
          'SD 1.x',
          'SDXS (512-DS)',
          'SDXL',
          'FLUX.1',
          '',
        ]) {
          driver.session.modelVersion = family;
          final engine = await load(_sdxs());
          await expectLater(
            engine.generate(
              const TiledImageGenerationRequest(
                prompt: 'a',
                vaeTiling: ImageVaeTiling(),
              ),
            ),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          await engine.generateImage(const ImageGenerationRequest(prompt: 'a'));
        }
        driver.session.modelVersion = 'SD 2.x';
        driver.status = _available('Vulkan0\tNVIDIA L4\nCPU\tCPU\n');
        final vulkan = await load(_sdxs());
        await expectLater(
          vulkan.generate(
            const TiledImageGenerationRequest(
              prompt: 'a',
              vaeTiling: ImageVaeTiling(),
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await vulkan.generateImage(const ImageGenerationRequest(prompt: 'a'));
        driver.status = _available('CPU\tApple M4\n');
        driver.headers[_model] = ImageModelHeaders.sdxsCheckpoint;
        final tiny = await load(_sdxs());
        await expectLater(
          tiny.generate(
            const TiledImageGenerationRequest(
              prompt: 'a',
              vaeTiling: ImageVaeTiling(),
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        final taesd = await load(_sdxs(null, _local(_taesd)));
        await taesd.generateImage(
          const TiledImageGenerationRequest(
            prompt: 'a',
            vaeTiling: ImageVaeTiling(),
          ),
        );
      },
    );

    test(
      'tiling and either circular axis are refused before task acquisition',
      () async {
        final engine = await load(_sdxs());
        for (final (x, y) in [(true, false), (false, true), (true, true)]) {
          await expectLater(
            engine.generate(
              SeamlessImageGenerationRequest(
                prompt: 'a',
                circularX: x,
                circularY: y,
                vaeTiling: const ImageVaeTiling(),
              ),
            ),
            throwsA(isA<LlamaUnsupportedException>()),
          );
        }
        expect(driver.session.requests, isEmpty);
        await engine.generateImage(
          const SeamlessImageGenerationRequest(
            prompt: 'a',
            vaeTiling: ImageVaeTiling(),
          ),
        );
        expect(driver.session.requests.single.vaeTiling, isNotNull);
      },
    );

    test('rejects invalid requests before starting', () async {
      final engine = await load(_sdxs());

      for (final request in [
        const ImageGenerationRequest(prompt: ' '),
        const ImageGenerationRequest(prompt: 'a', width: 500),
        const ImageGenerationRequest(prompt: 'a', height: 56),
        const ImageGenerationRequest(prompt: 'a', width: 2056),
        const ImageGenerationRequest(prompt: 'a', steps: 0),
        const ImageGenerationRequest(prompt: 'a', steps: 151),
        const ImageGenerationRequest(prompt: 'a', guidanceScale: -1),
        const ImageGenerationRequest(prompt: 'a', guidanceScale: double.nan),
        const ImageGenerationRequest(prompt: 'a', seed: -1),
        const ImageGenerationRequest(prompt: 'a', count: 0),
        const ImageGenerationRequest(prompt: 'a', count: 17),
        const TiledImageGenerationRequest(
          prompt: 'a',
          vaeTiling: ImageVaeTiling(tileWidth: 100),
        ),
        const TiledImageGenerationRequest(
          prompt: 'a',
          vaeTiling: ImageVaeTiling(overlap: 0.75),
        ),
      ]) {
        await expectLater(
          engine.generate(request),
          throwsA(isA<LlamaImageGenerationException>()),
        );
      }
      expect(driver.session.requests, isEmpty);

      await (await engine.generate(
        const ImageGenerationRequest(prompt: 'a'),
      )).done;
    });

    test('fills unset size, steps and guidance with the neutral fallbacks, '
        'and leaves sampling to the runtime', () async {
      final engine = await load(_sdxs());

      await (await engine.generate(
        const ImageGenerationRequest(prompt: 'a'),
      )).done;

      final sent = driver.session.requests.last;
      expect((sent.width, sent.height), (512, 512));
      expect(sent.steps, 20);
      expect(sent.guidanceScale, 7);
      expect(sent.sampler, isNull);
      expect(sent.scheduler, isNull);
      expect(sent.flowShift, isNull);
      expect(sent.vaeTiling, isNull);
    });

    test('sends VAE tiling only with the request that sets it', () async {
      final engine = await load(_sdxs());
      const tiling = ImageVaeTiling(
        tileWidth: 512,
        tileHeight: 128,
        overlap: 0.25,
      );

      await (await engine.generate(
        const TiledImageGenerationRequest(prompt: 'a', vaeTiling: tiling),
      )).done;
      await (await engine.generate(
        const ImageGenerationRequest(prompt: 'a'),
      )).done;

      expect(driver.session.requests.map((r) => r.vaeTiling), [tiling, null]);
    });

    test('sends every setting a request sets, each side of the size on its '
        'own', () async {
      final engine = await load(_fluxModel());

      await (await engine.generate(
        const ImageGenerationRequest(
          prompt: 'a',
          width: 1024,
          height: 768,
          steps: 4,
          guidanceScale: 1,
          sampler: ImageGenerationSampler.euler,
          scheduler: ImageGenerationScheduler.sgmUniform,
          flowShift: 3,
        ),
      )).done;
      var sent = driver.session.requests.last;
      expect((sent.width, sent.height, sent.steps), (1024, 768, 4));
      expect(sent.guidanceScale, 1);
      expect(sent.sampler, ImageGenerationSampler.euler);
      expect(sent.scheduler, ImageGenerationScheduler.sgmUniform);
      expect(sent.flowShift, 3);

      await (await engine.generate(
        const ImageGenerationRequest(prompt: 'a', width: 768),
      )).done;
      sent = driver.session.requests.last;
      expect((sent.width, sent.height), (768, 512));
    });

    test('reports the seed it used', () async {
      final engine = await load(_sdxs());

      final fixed = await engine.generateImage(
        const ImageGenerationRequest(prompt: 'a', seed: 42),
      );
      expect(fixed.seed, 42);
      expect(driver.session.requests.last.seed, 42);

      final random = await engine.generateImage(
        const ImageGenerationRequest(prompt: 'a'),
      );
      expect(random.seed, driver.session.requests.last.seed);
      expect(random.seed, greaterThanOrEqualTo(0));
    });

    test('emits phases in order and one final event', () async {
      final engine = await load(_sdxs());

      final task = await engine.generate(
        const ImageGenerationRequest(
          prompt: 'a lighthouse',
          width: 256,
          height: 256,
          steps: 2,
          count: 2,
        ),
      );
      final events = await task.events.toList();

      final progress = events
          .whereType<ImageGenerationProgressEvent>()
          .map((e) => '${e.phase.name} ${e.step}/${e.steps} #${e.imageIndex}')
          .toList();
      expect(progress, [
        'encodingPrompt 0/2 #0',
        'sampling 0/2 #0',
        'sampling 1/2 #0',
        'sampling 2/2 #0',
        'sampling 0/2 #1',
        'sampling 1/2 #1',
        'sampling 2/2 #1',
        'decoding 0/2 #1',
      ]);
      final result = (events.last as ImageGenerationFinalEvent).result;
      expect(result.images, hasLength(2));
      expect(result.images.first.width, 256);
      final completion = await task.done;
      expect(completion.state, ImageGenerationCompletionState.completed);
      expect(completion.result, same(result));
      expect(await task.result, same(result));
      expect(driver.session.requests.single.prompt, 'a lighthouse');
    });

    test('allows one generation at a time across engines and loads', () async {
      final first = await load(_sdxs());
      final second = await load(_sdxs());
      final gate = driver.session.gate = Completer<void>();

      final running = first.generate(const ImageGenerationRequest(prompt: 'a'));

      for (final start in [
        first.generate(const ImageGenerationRequest(prompt: 'b')),
        second.generate(const ImageGenerationRequest(prompt: 'c')),
      ]) {
        await expectLater(
          start,
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('process-wide callback'),
            ),
          ),
        );
      }
      await expectLater(load(_sdxs()), throwsA(isA<LlamaStateException>()));

      gate.complete();
      expect(
        (await (await running).done).state,
        ImageGenerationCompletionState.completed,
      );
      driver.session.gate = null;

      final next = await second.generateImage(
        const ImageGenerationRequest(prompt: 'd'),
      );
      expect(next.images, isNotEmpty);
    });

    test('a cancel before the runtime starts is re-applied on its first '
        'progress callback', () async {
      final engine = await load(_sdxs());
      final gate = driver.session.gate = Completer<void>();

      final task = await engine.generate(
        const ImageGenerationRequest(prompt: 'a', steps: 4),
      );
      final events = task.events.toList();
      task.cancel();
      expect(driver.session.cancelCalls, 1);

      // The runtime clears the flag when generation starts.
      gate.complete();
      final completion = await task.done;

      expect(completion.state, ImageGenerationCompletionState.cancelled);
      await expectLater(
        task.result,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Image generation was cancelled.',
          ),
        ),
      );
      expect(driver.session.cancelCalls, 2);
      expect(driver.session.stepsRun, 0);
      expect(await events, everyElement(isA<ImageGenerationProgressEvent>()));
    });

    test('cancel during sampling stops the runtime', () async {
      final engine = await load(_sdxs());
      final task = await engine.generate(
        const ImageGenerationRequest(prompt: 'a', steps: 8),
      );

      final events = <ImageGenerationEvent>[];
      await for (final event in task.events) {
        events.add(event);
        if (event case ImageGenerationProgressEvent(
          phase: ImageGenerationPhase.sampling,
          step: 1,
        )) {
          task.cancel();
          task.cancel();
        }
      }

      expect((await task.done).state, ImageGenerationCompletionState.cancelled);
      expect(driver.session.stepsRun, lessThan(8));
      expect(events.whereType<ImageGenerationFinalEvent>(), isEmpty);
      expect(task.isCancellationRequested, isTrue);
    });

    test('a runtime failure fails the task with LlamaInferenceException and '
        'the engine runs the next request', () async {
      final engine = await load(_sdxs());
      driver.session.failNext = true;

      final task = await engine.generate(
        const ImageGenerationRequest(prompt: 'a'),
      );
      final events = await task.events.toList();
      expect(events, everyElement(isA<ImageGenerationProgressEvent>()));
      final completion = await task.done;
      expect(completion.state, ImageGenerationCompletionState.failed);
      expect(
        completion.error,
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('running out of memory'),
            isNot(contains('command buffer')),
            contains(
              'If every request fails this way, dispose the '
              'ImageGenerationEngine and load the model again.',
            ),
          ),
        ),
      );
      await expectLater(task.result, throwsA(same(completion.error)));

      final next = await engine.generateImage(
        const ImageGenerationRequest(prompt: 'b'),
      );
      expect(next.images, hasLength(1));
    });

    test('maps unexpected errors to LlamaInferenceException and keeps typed '
        'ones', () async {
      final engine = await load(_sdxs());

      driver.session.error = StateError('worker bug');
      await expectLater(
        engine.generateImage(const ImageGenerationRequest(prompt: 'a')),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.details,
            'details',
            isA<StateError>(),
          ),
        ),
      );

      driver.session.error = LlamaStateException('worker stopped');
      await expectLater(
        engine.generateImage(const ImageGenerationRequest(prompt: 'a')),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test('dispose cancels a running generation before freeing the '
        'model', () async {
      final engine = await load(_sdxs());
      final gate = driver.session.gate = Completer<void>();
      final result = engine.generateImage(
        const ImageGenerationRequest(prompt: 'a', steps: 4),
      );
      final resultExpectation = expectLater(
        result,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );

      final disposal = engine.dispose();
      expect(engine.isDisposed, isTrue);
      expect(driver.session.disposed, isFalse);
      gate.complete();
      await disposal;
      await resultExpectation;

      expect(driver.session.disposedAfterGenerate, isTrue);
      expect(driver.session.stepsRun, 0);
      await engine.dispose();
      expect(driver.session.disposeCalls, 1);
      expect((await engine.capabilities).isSupported, isFalse);
      await expectLater(
        engine.generate(const ImageGenerationRequest(prompt: 'a')),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test('a dispose before generate is awaited still returns the task, '
        'cancelled, with no error event', () async {
      final engine = await load(_sdxs());
      final gate = driver.session.gate = Completer<void>();
      final starting = engine.generate(
        const ImageGenerationRequest(prompt: 'a', steps: 4),
      );

      final disposal = engine.dispose();
      gate.complete();
      final task = await starting;
      final events = task.events.toList();
      await disposal;

      expect(task.isCancellationRequested, isTrue);
      expect(await events, everyElement(isA<ImageGenerationProgressEvent>()));
      expect((await task.done).state, ImageGenerationCompletionState.cancelled);
      await expectLater(task.result, throwsA(isA<LlamaStateException>()));
      expect(driver.session.disposedAfterGenerate, isTrue);
      expect(driver.session.stepsRun, 0);
    });
  });

  group('warmUp', () {
    test('runs one discarded single-step generation at the given size and '
        'guidance', () async {
      final engine = await load(_sdxs());

      await engine.warmUp(guidanceScale: 1);
      await engine.warmUp(width: 256, height: 384, guidanceScale: 1);

      expect(
        driver.session.requests.map(
          (r) => (r.width, r.height, r.steps, r.guidanceScale, r.count),
        ),
        [(512, 512, 1, 1.0, 1), (256, 384, 1, 1.0, 1)],
      );
      expect(driver.session.requests.map((r) => r.vaeTiling), [null, null]);
    });

    test('falls back like a request, and a given side overrides it', () async {
      final engine = await load(_fluxModel());

      await engine.warmUp();
      await engine.warmUp(width: 1024, height: 1024);
      await engine.warmUp(height: 768);

      expect(
        driver.session.requests.map(
          (r) => (r.width, r.height, r.steps, r.guidanceScale),
        ),
        [(512, 512, 1, 7.0), (1024, 1024, 1, 7.0), (512, 768, 1, 7.0)],
      );
    });

    test('runs nothing on the CPU but still checks the size and the engine '
        'state', () async {
      driver.status = _available('CPU\tCortex-A78\n');
      final engine = await load(_sdxs());

      await engine.warmUp();
      expect(driver.session.requests, isEmpty);

      await expectLater(
        engine.warmUp(width: 500),
        throwsA(isA<LlamaImageGenerationException>()),
      );

      final gate = driver.session.gate = Completer<void>();
      final running = await engine.generate(
        const ImageGenerationRequest(prompt: 'a'),
      );
      await expectLater(engine.warmUp(), throwsA(isA<LlamaStateException>()));
      gate.complete();
      await running.done;

      await engine.dispose();
      await expectLater(engine.warmUp(), throwsA(isA<LlamaStateException>()));
    });

    test('rejects an invalid size before running anything', () async {
      final engine = await load(_sdxs());

      for (final (width, height) in [(500, 512), (512, 56), (4096, 512)]) {
        await expectLater(
          engine.warmUp(width: width, height: height),
          throwsA(isA<LlamaImageGenerationException>()),
        );
      }
      expect(driver.session.requests, isEmpty);
    });

    test('holds the one-operation slot until it finishes', () async {
      final engine = await load(_sdxs());
      final gate = driver.session.gate = Completer<void>();

      final warmUp = engine.warmUp();

      await expectLater(
        engine.generate(const ImageGenerationRequest(prompt: 'a')),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(load(_sdxs()), throwsA(isA<LlamaStateException>()));
      await expectLater(engine.warmUp(), throwsA(isA<LlamaStateException>()));

      gate.complete();
      await warmUp;
      driver.session.gate = null;

      final result = await engine.generateImage(
        const ImageGenerationRequest(prompt: 'b'),
      );
      expect(result.images, hasLength(1));
      expect(driver.session.requests, hasLength(2));
    });

    test('throws LlamaStateException while a generation runs', () async {
      final engine = await load(_sdxs());
      final gate = driver.session.gate = Completer<void>();
      final running = await engine.generate(
        const ImageGenerationRequest(prompt: 'a'),
      );

      await expectLater(engine.warmUp(), throwsA(isA<LlamaStateException>()));

      gate.complete();
      expect(
        (await running.done).state,
        ImageGenerationCompletionState.completed,
      );
      expect(driver.session.requests, hasLength(1));
    });

    test('dispose cancels a running warm-up, which completes normally, and '
        'later warm-ups throw', () async {
      final engine = await load(_sdxs());
      final gate = driver.session.gate = Completer<void>();

      final warmUp = engine.warmUp();
      final disposal = engine.dispose();
      gate.complete();
      await disposal;
      await warmUp;

      expect(driver.session.stepsRun, 0);
      expect(driver.session.disposedAfterGenerate, isTrue);
      await expectLater(
        engine.warmUp(),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });

    test('throws a runtime failure and leaves the engine usable', () async {
      final engine = await load(_sdxs());

      driver.session.failNext = true;
      await expectLater(
        engine.warmUp(),
        throwsA(isA<LlamaInferenceException>()),
      );

      driver.session.error = StateError('worker bug');
      await expectLater(
        engine.warmUp(),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.details,
            'details',
            isA<StateError>(),
          ),
        ),
      );

      await engine.warmUp();
      final next = await engine.generateImage(
        const ImageGenerationRequest(prompt: 'b'),
      );
      expect(next.images, hasLength(1));
    });
  });
}

StableDiffusionRuntimeStatus _available(
  String devices, {
  bool loadsFp8AsF16OnMetal = false,
  bool supportsIntrinsicTinyDecoderV1 = true,
}) => StableDiffusionRuntimeStatus.available(
  version: 'master-929',
  commit: 'be48649',
  devices: parseStableDiffusionDeviceList(devices),
  loadsFp8AsF16OnMetal: loadsFp8AsF16OnMetal,
  supportsIntrinsicTinyDecoderV1: supportsIntrinsicTinyDecoderV1,
);

final class _FakeDriver implements ImageGenerationDriver {
  @override
  String operatingSystem = 'macos';
  @override
  bool isMacosX64 = false;

  StableDiffusionRuntimeStatus status = _available(
    'MTL0\tApple M4\nBLAS\tAccelerate\nCPU\tApple M4\n',
  );
  final Map<String, int> sizes = {
    _model: 651 << 20,
    _taesd: 9 << 20,
    _flux: 6 * _gib,
    _ae: 320 << 20,
    _clipL: 120 << 20,
    _t5xxl: 5 * _gib,
    _sd15: 2 * _gib,
    _sd2Base: 2 * _gib,
    _canny: 700 << 20,
    _diffusersCanny: 700 << 20,
  };
  final Map<String, Uint8List> headers = {
    _model: ImageModelHeaders.sdTurboCheckpoint,
    _taesd: ImageModelHeaders.taesd,
    _flux: ImageModelHeaders.fluxDiffusion,
    _ae: ImageModelHeaders.fluxVae,
    _clipL: ImageModelHeaders.clipL,
    _t5xxl: ImageModelHeaders.t5xxl,
    _sd15: ImageModelHeaders.sd15Checkpoint(),
    _sd2Base: ImageModelHeaders.sd15Checkpoint(contextWidth: 1024),
    _canny: ImageModelHeaders.sd15ControlNet(),
    _diffusersCanny: ImageModelHeaders.diffusersControlNet,
  };
  ImageGenerationMemoryBudget? budget;
  ImageGenerationMemoryBudget? slowerBudget;
  Object? startError;
  final List<ImageGenerationSessionConfig> started = [];
  ImageGenerationSession? sessionOverride;
  _FakeSession session = _FakeSession();
  Completer<void>? probeGate;
  Object? probeError;
  int backgroundProbes = 0;

  @override
  Future<StableDiffusionRuntimeStatus> probeInBackground() async {
    backgroundProbes++;
    await probeGate?.future;
    final error = probeError;
    if (error != null) {
      throw error;
    }
    return status;
  }

  final List<String> fileSizePaths = [];
  final List<String> readPaths = [];

  @override
  int? fileSize(String path) {
    fileSizePaths.add(path);
    return sizes[path];
  }

  @override
  Future<Uint8List> readFileRange(String path, int offset, int length) async {
    readPaths.add(path);
    await readGate?.future;
    final bytes = headers[path] ?? Uint8List(0);
    final start = offset.clamp(0, bytes.length);
    return Uint8List.sublistView(
      bytes,
      start,
      (offset + length).clamp(0, bytes.length),
    );
  }

  final List<ImageGenerationComputeDevice> budgetDevices = [];
  final List<bool> runtimePicks = [];

  /// What [readGpuMemory] lists: a discrete GPU, an integrated one, or
  /// nothing.
  bool? discreteGpu = true;
  bool mixedGpus = false;
  int gpuMemoryReads = 0;
  final List<List<StableDiffusionGpuMemory>?> memoryGpus = [];

  @override
  Future<List<StableDiffusionGpuMemory>?> readGpuMemory() async {
    gpuMemoryReads++;
    if (mixedGpus) {
      return [
        for (final integrated in [true, false])
          (
            name: integrated ? 'Vulkan0' : 'Vulkan1',
            totalBytes: 8 << 30,
            freeBytes: 8 << 30,
            integrated: integrated,
          ),
      ];
    }
    return switch (discreteGpu) {
      null => null,
      final discrete => [
        (
          name: 'Vulkan0',
          totalBytes: 8 << 30,
          freeBytes: 8 << 30,
          integrated: !discrete,
        ),
      ],
    };
  }

  @override
  Future<ImageGenerationMemoryLimits> memoryLimits(
    ImageGenerationComputeDevice device, {
    required bool runtimePicksGpu,
    List<StableDiffusionGpuMemory>? gpus,
  }) async {
    memoryGpus.add(gpus);
    budgetDevices.add(device);
    runtimePicks.add(runtimePicksGpu);
    return (refuse: budget, slower: slowerBudget);
  }

  @override
  Future<ImageGenerationSession> start(
    ImageGenerationSessionConfig config,
  ) async {
    final error = startError;
    if (error != null) {
      throw error;
    }
    started.add(config);
    await startGate?.future;
    return sessionOverride ?? session;
  }

  /// Holds header reads until completed.
  Completer<void>? readGate;

  /// Holds the native load, after it allocated the session, until completed.
  Completer<void>? startGate;
}

/// Behaves like stable-diffusion.cpp: a generation clears the cancel flag
/// when it starts, reports `0/steps` then each step, and checks the flag
/// before every step and before decoding.
final class _FakeSession
    implements
        ImageGenerationSession,
        ImageVaeTilingSession,
        ImageEditingSession,
        ImageControlNetSession,
        ImageHiresFixSession,
        ImageReferenceEditingSession {
  @override
  bool supportsVaeTiling = true;
  @override
  bool supportsHiresFix = true;
  @override
  bool supportsReferenceImageEditing = true;

  /// Returns first-pass images for a hires fix, as a runtime that disabled
  /// it would.
  bool ignoreHires = false;

  /// Images to return in place of `request.count`, as a runtime that
  /// dropped some would.
  int? returnedImageCount;
  @override
  bool supportsImageEditing = true;
  @override
  bool supportsControlNet = true;
  final List<ImageGenerationSessionRequest> requests = [];
  Completer<void>? gate;
  bool failNext = false;
  Object? error;
  bool _cancelFlag = false;
  bool _generating = false;
  int cancelCalls = 0;
  int stepsRun = 0;
  int disposeCalls = 0;
  bool disposed = false;
  bool disposedAfterGenerate = false;
  void Function()? onDispose;
  Object? disposeError;

  @override
  String modelVersion = 'SD 2.x';

  @override
  Future<List<GeneratedImage>?> generate(
    ImageGenerationSessionRequest request,
    void Function(int step, int steps) onProgress,
  ) async {
    requests.add(request);
    _generating = true;
    stepsRun = 0;
    try {
      await gate?.future;
      _cancelFlag = false;
      final failure = error;
      if (failure != null) {
        error = null;
        throw failure;
      }
      final hires = ignoreHires ? null : request.hiresFix;
      for (final steps in [request.steps, ?hires?.steps]) {
        for (var image = 0; image < request.count; image++) {
          onProgress(0, steps);
          for (var step = 1; step <= steps; step++) {
            await Future<void>.delayed(Duration.zero);
            if (_cancelFlag) {
              return null;
            }
            stepsRun++;
            onProgress(step, steps);
          }
        }
      }
      await Future<void>.delayed(Duration.zero);
      if (_cancelFlag || failNext) {
        failNext = false;
        return null;
      }
      final width = hires?.width ?? request.width;
      final height = hires?.height ?? request.height;
      return [
        for (var i = 0; i < (returnedImageCount ?? request.count); i++)
          GeneratedImage(
            width: width,
            height: height,
            channels: 3,
            pixels: Uint8List(width * height * 3),
          ),
      ];
    } finally {
      _generating = false;
    }
  }

  @override
  void cancel() {
    cancelCalls++;
    _cancelFlag = true;
  }

  @override
  Future<void> dispose() async {
    onDispose?.call();
    disposeCalls++;
    disposed = true;
    disposedAfterGenerate = !_generating;
    if (disposeError case final error?) throw error;
  }
}

/// Passes local files through and "downloads" remote ones into a fake cache,
/// registering their sizes with the driver.
final class _FakeDownloads implements ModelDownloadManager {
  _FakeDownloads(this.driver);

  final _FakeDriver driver;
  final List<(ModelSource, ModelLoadOptions)> calls = [];
  final Set<String> cached = {};
  final List<String> downloaded = [];
  final Map<String, int> remoteSizes = {};

  /// Header of each downloaded file, by file name; `.gguf` files default to
  /// a checkpoint and `.safetensors` files to a TAESD.
  final Map<String, Uint8List> remoteHeaders = {};
  Object? error;

  /// Thrown for any file when the load sets [ModelLoadOptions.sha256].
  Object? checksumError;

  /// Thrown for any file, with or without a checksum.
  Object? unconditionalError;
  Completer<void>? gate;

  static String cachePath(ModelSource source) =>
      '/cache/${source.cacheDirectoryName}/${source.fileName}';

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    calls.add((source, options));
    if (unconditionalError != null) {
      throw unconditionalError!;
    }
    if (options.sha256 != null && checksumError != null) {
      throw checksumError!;
    }
    final path = source.isLocal ? source.path! : cachePath(source);
    if (!source.isLocal) {
      final failure = error;
      if (failure != null) {
        throw failure;
      }
      final size = remoteSizes[source.fileName] ?? 4096;
      if (cached.add(source.canonicalKey)) {
        onProgress?.call(
          ModelDownloadProgress(receivedBytes: size ~/ 2, totalBytes: size),
        );
        await gate?.future;
        if (options.cancelToken?.isCancelled ?? false) {
          throw LlamaStateException('Model download was cancelled.');
        }
        onProgress?.call(
          ModelDownloadProgress(receivedBytes: size, totalBytes: size),
        );
        downloaded.add(source.fileName);
      }
      driver.sizes[path] = size;
      driver.headers[path] =
          remoteHeaders[source.fileName] ??
          (source.fileName.endsWith('.gguf')
              ? ImageModelHeaders.sdTurboCheckpoint
              : ImageModelHeaders.taesd);
    }
    final now = DateTime.utc(2026);
    return ModelCacheEntry(
      sourceCanonicalKey: source.canonicalKey,
      cacheKey: source.cacheKey,
      fileName: source.fileName,
      filePath: path,
      createdAt: now,
      updatedAt: now,
      bytes: driver.sizes[path],
    );
  }

  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async => [];

  @override
  Future<ModelCacheEntry?> get(
    String cacheKey, {
    String? cacheDirectory,
  }) async => null;

  @override
  Future<void> remove(String cacheKey, {String? cacheDirectory}) async {}

  @override
  Future<void> clear({String? cacheDirectory}) async {}

  @override
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  }) async => [];
}

final class _RemoteTargetResolver implements ModelResolver {
  _RemoteTargetResolver(this.url, {required this.useBrowserCache});

  final Uri url;
  final bool useBrowserCache;

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async => RemoteModelUrl(url, useBrowserCache: useBrowserCache);
}

final class _LegacySession implements ImageGenerationSession {
  final ImageGenerationSession delegate;
  _LegacySession(this.delegate);
  @override
  String get modelVersion => delegate.modelVersion;
  @override
  Future<List<GeneratedImage>?> generate(
    ImageGenerationSessionRequest request,
    void Function(int, int) onProgress,
  ) => delegate.generate(request, onProgress);
  @override
  void cancel() => delegate.cancel();
  @override
  Future<void> dispose() => delegate.dispose();
}
