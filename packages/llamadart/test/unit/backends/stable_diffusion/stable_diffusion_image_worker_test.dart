@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_bindings.dart'
    as sd;
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_calls.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_image_worker.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_io.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/image/generated_image.dart';
import 'package:llamadart/src/core/image/image_editing_request.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:llamadart/src/core/image/image_generation_events.dart';
import 'package:llamadart/src/core/image/image_generation_progress.dart';
import 'package:llamadart/src/core/image/image_generation_request.dart';
import 'package:llamadart/src/core/image/image_hires_fix_request.dart';
import 'package:llamadart/src/core/image/image_reference_editing_request.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';

import '../../../support/fake_stable_diffusion_runtime.dart';
import '../../../support/image_model_headers.dart';

const _config = ImageGenerationSessionConfig(
  files: {'model': '/models/sdxs.gguf'},
  backend: null,
  threads: 0,
);

ImageGenerationSessionRequest _request({int steps = 2, int count = 1}) =>
    ImageGenerationSessionRequest(
      prompt: 'a red fox',
      negativePrompt: '',
      width: 8,
      height: 8,
      steps: steps,
      guidanceScale: 1,
      seed: 7,
      count: count,
    );

/// The reports stable-diffusion.cpp makes for [count] images of [steps]
/// steps, then [tiles] tiles of a tiled decode.
List<(int, int)> _upstreamReports({
  required int steps,
  required int count,
  int tiles = 0,
}) => [
  for (var image = 0; image < count; image++)
    for (var step = 0; step <= steps; step++) (step, steps),
  for (var tile = 1; tile <= tiles; tile++) (tile, tiles),
];

// What a start calls in the calling isolate with no log level: the log
// recorder is registered, recording nothing, before the progress recorder.
const _startCalls = [
  'sd_dart_log_enable',
  'sd_dart_log_set_level:5',
  'sd_dart_progress_enable',
];

// A drain of the log that finds [messages] messages.
List<String> _logReads(int messages) => [
  for (var read = 0; read <= messages; read++) 'sd_dart_log_read',
  'sd_dart_log_dropped',
];

const _loadCalls = [
  'sd_ctx_params_init',
  'sd_dart_new_sd_ctx',
  'sd_ctx_supports_image_generation+held',
  'sd_get_model_version_name+held',
];

// What ggml's Metal backend logs when a command buffer fails, and on every
// later graph until the backend is created again.
const _commandBufferFailed =
    'ggml - ggml_metal_synchronize: error: command buffer 0 failed with '
    'status 5\n'
    'ggml - error: Discarded (victim of GPU error/recovery) '
    '(00000005:kIOGPUCommandBufferCallbackErrorInnocentVictim)';
const _backendInErrorState =
    'ggml - ggml_metal_graph_compute: backend is in error state from a '
    'previous command buffer failure - recreate the backend to recover\n'
    'ggml_runner.cpp:785  - unet compute failed: GGML status: error '
    '(operation failed)';

final _reloadFailure = isA<LlamaInferenceException>().having(
  (error) => error.message,
  'message',
  allOf(
    contains('Metal backend in an error state'),
    contains('Dispose the ImageGenerationEngine and load the model again'),
    isNot(contains('It reports no reason')),
  ),
);

const _generateCalls = [
  'sd_img_gen_params_init+held',
  'sd_dart_generate_image+held',
  'sd_dart_last_error',
  'free_sd_images+held',
];

// Real generation needs the opt-in runtime, which the root package does not
// bundle; example/basic_app/test/image_generation_e2e_test.dart covers it.
// The tests below run the worker's two isolates on a recording stand-in.
void main() {
  test(
    'a worker whose runtime is missing fails its start and exits',
    () async {
      await expectLater(
        StableDiffusionImageWorker.start(_config),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
    skip: probeStableDiffusionRuntime().isAvailable
        ? 'the stable_diffusion runtime is bundled here'
        : false,
  );

  group('on a recording runtime', () {
    late FakeStableDiffusionRuntime runtime;
    late ManualProgressTimers timers;
    final workers = <StableDiffusionImageWorker>[];

    Future<StableDiffusionImageWorker> start({
      LlamaLogLevel logLevel = LlamaLogLevel.none,
      ImageGenerationSessionConfig config = _config,
    }) async {
      final worker = await StableDiffusionImageWorker.start(
        config,
        resolveCalls: runtime.resolver,
        progressTimer: timers.start,
        logLevel: logLevel,
      );
      workers.add(worker);
      return worker;
    }

    test(
      'required tiny-decoder policy fails closed on an older runtime before worker start',
      () async {
        await expectLater(
          start(
            config: const ImageGenerationSessionConfig(
              files: {'model': '/models/sdxs.gguf'},
              backend: 'gpu',
              threads: 1,
              requiresIntrinsicTinyDecoderV1: true,
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await runtime.flush();
        expect(runtime.calls('worker'), isEmpty);
        expect(runtime.calls('caller'), isEmpty);
      },
    );

    test(
      'required tiny-decoder policy calls its native constructor and releases the context',
      () async {
        runtime.supportsIntrinsicTinyDecoderV1 = true;
        final worker = await start(
          config: const ImageGenerationSessionConfig(
            files: {'model': '/models/sdxs.gguf'},
            backend: 'cpu',
            threads: 1,
            requiresIntrinsicTinyDecoderV1: true,
          ),
        );
        await worker.dispose();
        await runtime.flush();
        expect(
          runtime.calls('worker'),
          contains('sd_dart_new_sd_ctx_intrinsic_tiny_v1'),
        );
        expect(runtime.calls('worker'), contains('sd_dart_exit_free'));
      },
    );

    test(
      'worker capability loss returns a typed refusal before native creation',
      () async {
        runtime
          ..supportsIntrinsicTinyDecoderV1 = true
          ..intrinsicTinyMissingInWorker = true;
        await expectLater(
          start(
            config: const ImageGenerationSessionConfig(
              files: {'model': '/models/sdxs.gguf'},
              backend: 'cpu',
              threads: 1,
              requiresIntrinsicTinyDecoderV1: true,
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await runtime.flush();
        expect(runtime.calls('worker'), isEmpty);
      },
    );

    test(
      'FP8 Metal preflight precedes native context creation, CPU forwards',
      () async {
        final directory = Directory.systemTemp.createTempSync('image-fp8-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/private-weights.bin')
          ..writeAsBytesSync(
            safetensorsHeader(
              [
                ('model.diffusion_model.weight', [1]),
              ],
              dtype: 'F8_E4M3',
              dataBytes: 1,
            ),
          );
        for (final backend in [null, 'gpu', 'MTL0']) {
          await expectLater(
            start(
              config: ImageGenerationSessionConfig(
                files: {'model': file.path},
                backend: backend,
                threads: 1,
              ),
            ),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          await runtime.flush();
          expect(runtime.calls('worker'), isEmpty);
          expect(runtime.calls('caller'), isEmpty);
        }
        final worker = await start(
          config: ImageGenerationSessionConfig(
            files: {'model': file.path},
            backend: 'cpu',
            threads: 1,
          ),
        );
        await runtime.flush();
        expect(
          runtime
              .calls('worker')
              .any((call) => call.contains('sd_dart_new_sd_ctx')),
          isTrue,
        );
        await worker.dispose();
        runtime.clearCalls();
        file.writeAsBytesSync(
          safetensorsHeader([
            ('model.diffusion_model.weight', [1]),
          ], dataBytes: 2),
        );
        final metal = await start(
          config: ImageGenerationSessionConfig(
            files: {'model': file.path},
            backend: 'gpu',
            threads: 1,
          ),
        );
        await runtime.flush();
        expect(runtime.calls('worker'), contains('sd_dart_new_sd_ctx'));
        await metal.dispose();
      },
      skip: !(Platform.isMacOS || Platform.isIOS),
    );

    test(
      'a runtime that loads FP8 as F16 on Metal skips the preflight',
      () async {
        runtime.loadsFp8AsF16OnMetal = true;
        final directory = Directory.systemTemp.createTempSync('image-fp8-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/private-weights.bin')
          ..writeAsBytesSync(
            safetensorsHeader(
              [
                ('model.diffusion_model.weight', [1]),
              ],
              dtype: 'F8_E4M3',
              dataBytes: 1,
            ),
          );
        for (final model in [file.path, directory.path]) {
          for (final backend in [null, 'gpu', 'MTL0']) {
            final worker = await start(
              config: ImageGenerationSessionConfig(
                files: {'model': model},
                backend: backend,
                threads: 1,
              ),
            );
            await runtime.flush();
            expect(
              runtime.calls('worker'),
              contains('sd_dart_new_sd_ctx'),
              reason: '$model $backend',
            );
            await worker.dispose();
            runtime.clearCalls();
          }
        }
      },
      skip: !(Platform.isMacOS || Platform.isIOS),
    );

    /// A started worker, with the calls of its load forgotten.
    test('concurrent disposal waits for the same worker cleanup', () async {
      runtime.freeDelay = const Duration(milliseconds: 300);
      final worker = await start();
      final first = worker.dispose();
      final elapsed = Stopwatch()..start();
      await worker.dispose();
      elapsed.stop();
      expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(200));
      await first;
    });

    /// A started worker, with the calls of its load forgotten.
    Future<StableDiffusionImageWorker> loaded({
      LlamaLogLevel logLevel = LlamaLogLevel.none,
    }) async {
      final worker = await start(logLevel: logLevel);
      await runtime.flush();
      runtime.clearCalls();
      return worker;
    }

    test(
      'owned image inputs survive worker transport, held cancellation and reset',
      () async {
        final worker = await start(
          config: const ImageGenerationSessionConfig(
            files: {'model': '/models/renamed.gguf'},
            backend: 'cpu',
            threads: 1,
            imageEditingRecipeVerified: true,
          ),
        );
        expect(worker.supportsImageEditing, isTrue);
        final rgb = Uint8List.fromList(
          List.generate(64 * 64 * 3, (i) => i % 251),
        );
        final mask = Uint8List.fromList(
          List.generate(64 * 64, (i) => i % 2 == 0 ? 0 : 255),
        );
        final image = ImageEditingPixels.rgb(
          width: 64,
          height: 64,
          pixels: rgb,
        );
        final ownedMask = ImageEditingPixels.mask(
          width: 64,
          height: 64,
          pixels: mask,
        );
        List<num> expected() => [
          64,
          64,
          3,
          rgb.fold<int>(0, (a, b) => a + b),
          [
            for (var i = 0; i < rgb.length; i++) rgb[i] * (i + 1),
          ].fold<int>(0, (a, b) => a + b),
          64,
          64,
          1,
          mask.fold<int>(0, (a, b) => a + b),
          [
            for (var i = 0; i < mask.length; i++) mask[i] * (i + 1),
          ].fold<int>(0, (a, b) => a + b),
          0.5,
        ];
        final original = expected();
        runtime
          ..holdStart = true
          ..pauseAfter = 0;
        final generation = worker.generate(
          ImageGenerationSessionRequest(
            prompt: 'edit',
            negativePrompt: '',
            width: 64,
            height: 64,
            steps: 4,
            guidanceScale: 1,
            seed: 42,
            count: 1,
            initialImage: image,
            mask: ownedMask,
            strength: 0.5,
          ),
          (_, _) {},
        );
        await runtime.imageInputHeld();
        expect(runtime.imageInputSnapshot(), original);
        rgb.fillRange(0, rgb.length, 0);
        mask.fillRange(0, mask.length, 0);
        image.pixels.fillRange(0, rgb.length, 255);
        ownedMask.pixels.fillRange(0, mask.length, 255);
        worker.cancel();
        runtime.holdStart = false;
        await runtime.pausedIn(generation);
        expect(runtime.imageInputSnapshot(afterHold: true), original);
        timers.poll();
        runtime.resume();
        expect(await generation, isNull);
        runtime.pauseAfter = -1;
        await worker.generate(_request(), (_, _) {});
        expect(runtime.imageInputSnapshot().take(10), everyElement(0));
        await runtime.flush();
        expect(
          runtime
              .calls('worker')
              .where((c) => c.startsWith('sd_dart_generate_image')),
          everyElement('sd_dart_generate_image+held'),
        );
      },
    );

    group('ControlNet', () {
      const controlConfig = ImageGenerationSessionConfig(
        files: {
          'model': '/models/renamed-sd15.safetensors',
          'controlNet': '/models/renamed-canny.safetensors',
        },
        backend: 'cpu',
        threads: 1,
        controlNetRecipeVerified: true,
      );
      ImageGenerationSessionRequest controlRequest(ImageEditingPixels image) =>
          ImageGenerationSessionRequest(
            prompt: 'a house',
            negativePrompt: '',
            width: 64,
            height: 64,
            steps: 4,
            guidanceScale: 7,
            seed: 42,
            count: 1,
            controlImage: image,
            controlStrength: 1.5,
          );

      test('control input survives worker transport, held cancellation and '
          'reset, after the load proves the ControlNet', () async {
        runtime.modelVersion = 'SD 1.x';
        final worker = await start(config: controlConfig);
        expect(worker.modelVersion, 'SD 1.x');
        expect(worker.supportsControlNet, isTrue);
        expect(worker.supportsImageEditing, isFalse);
        expect(
          runtime.loadedFiles['controlNet'],
          '/models/renamed-canny.safetensors',
        );
        await runtime.flush();
        expect(
          runtime.calls('worker'),
          containsAllInOrder([
            'sd_dart_new_sd_ctx',
            'sd_ctx_has_control_net+held',
          ]),
        );
        final rgb = Uint8List.fromList(
          List.generate(64 * 64 * 3, (i) => i % 247),
        );
        final image = ImageEditingPixels.rgb(
          width: 64,
          height: 64,
          pixels: rgb,
        );
        final original = [
          64,
          64,
          3,
          rgb.fold<int>(0, (a, b) => a + b),
          [
            for (var i = 0; i < rgb.length; i++) rgb[i] * (i + 1),
          ].fold<int>(0, (a, b) => a + b),
          1.5,
        ];
        runtime
          ..holdStart = true
          ..pauseAfter = 0;
        final generation = worker.generate(controlRequest(image), (_, _) {});
        await runtime.imageInputHeld();
        expect(runtime.controlInputSnapshot(), original);
        rgb.fillRange(0, rgb.length, 0);
        image.pixels.fillRange(0, rgb.length, 255);
        worker.cancel();
        runtime.holdStart = false;
        await runtime.pausedIn(generation);
        expect(runtime.controlInputSnapshot(afterHold: true), original);
        timers.poll();
        runtime.resume();
        expect(await generation, isNull);
        runtime.pauseAfter = -1;
        await worker.generate(_request(), (_, _) {});
        expect(runtime.controlInputSnapshot().take(5), everyElement(0));
      });

      test('a ControlNet compute failure fails the generation instead of '
          'returning an uncontrolled image', () async {
        runtime.modelVersion = 'SD 1.x';
        final worker = await start(config: controlConfig);
        runtime
          ..generationErrors =
              'diffusion_engine.cpp:2392 - controlnet compute failed'
          ..returnImagesDespiteError = true;
        final image = ImageEditingPixels.rgb(
          width: 64,
          height: 64,
          pixels: Uint8List(64 * 64 * 3),
        );
        await expectLater(
          worker.generate(controlRequest(image), (_, _) {}),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              allOf(contains('ControlNet'), contains('control image')),
            ),
          ),
        );
        runtime.generationErrors = null;
        expect(await worker.generate(controlRequest(image), (_, _) {}), [
          isA<GeneratedImage>(),
        ]);
      });

      test('direct worker refuses control input without a proven ControlNet, '
          'its log or the SD 1.x family, before generation', () async {
        for (final kind in ['probe', 'older', 'no file', 'family']) {
          runtime.modelVersion = kind == 'family' ? 'SD 2.x' : 'SD 1.x';
          runtime.hideControlNet = kind == 'probe';
          runtime.olderRelease = kind == 'older';
          final worker = await start(
            config: kind == 'no file'
                ? const ImageGenerationSessionConfig(
                    files: {'model': '/models/sd15.safetensors'},
                    backend: 'cpu',
                    threads: 1,
                    controlNetRecipeVerified: true,
                  )
                : controlConfig,
          );
          expect(worker.supportsControlNet, isFalse, reason: kind);
          await runtime.flush();
          if (kind == 'no file') {
            expect(
              runtime.calls('worker'),
              isNot(contains('sd_ctx_has_control_net+held')),
            );
          }
          runtime.clearCalls();
          await expectLater(
            worker.generate(
              controlRequest(
                ImageEditingPixels.rgb(
                  width: 64,
                  height: 64,
                  pixels: Uint8List(64 * 64 * 3),
                ),
              ),
              (_, _) {},
            ),
            throwsA(isA<LlamaUnsupportedException>()),
            reason: kind,
          );
          await runtime.flush();
          expect(runtime.calls('worker'), isEmpty, reason: kind);
          await worker.dispose();
          runtime
            ..hideControlNet = false
            ..olderRelease = false;
        }
      });
    });

    group('reference image editing', () {
      const referenceConfig = ImageGenerationSessionConfig(
        files: {
          'diffusionModel': '/models/flux1-kontext-dev.gguf',
          'vae': '/models/ae.safetensors',
          'clipL': '/models/clip_l.gguf',
          't5xxl': '/models/t5xxl.gguf',
        },
        backend: 'gpu',
        threads: 1,
        referenceEditingRecipeVerified: true,
      );
      ImageGenerationSessionRequest referenceRequest(
        List<ImageEditingPixels> references,
      ) => ImageGenerationSessionRequest(
        prompt: 'make the fox blue',
        negativePrompt: '',
        width: 64,
        height: 128,
        steps: 4,
        guidanceScale: 1,
        seed: 42,
        count: 1,
        references: references,
        referenceRecipe: ImageReferenceEditingRecipe.fluxKontext,
      );
      List<int> snapshot(Uint8List pixels) => [
        64,
        128,
        3,
        pixels.fold<int>(0, (a, b) => a + b),
        [
          for (var i = 0; i < pixels.length; i++) pixels[i] * (i + 1),
        ].fold<int>(0, (a, b) => a + b),
      ];

      test('the reference and preset reach the guarded generation and stay '
          'owned through a held cancel, and an ordinary request after it '
          'has none', () async {
        runtime.modelVersion = 'Flux';
        final worker = await start(config: referenceConfig);
        expect(worker, isA<ImageReferenceEditingSession>());
        expect(worker.supportsReferenceImageEditing, isTrue);
        final rgb = Uint8List.fromList(
          List.generate(64 * 128 * 3, (i) => i % 251),
        );
        final reference = ImageEditingPixels.rgb(
          width: 64,
          height: 128,
          pixels: rgb,
        );
        final original = [1, ...snapshot(rgb), 0, 0, 0, 0, 0];
        runtime
          ..holdStart = true
          ..pauseAfter = 0;
        final generation = worker.generate(
          referenceRequest([reference]),
          (_, _) {},
        );
        await runtime.imageInputHeld();
        expect(runtime.referenceInputSnapshot(), original);
        expect(runtime.lastReferenceArgs, 'preset=flux_kontext');
        rgb.fillRange(0, rgb.length, 0);
        reference.pixels.fillRange(0, rgb.length, 255);
        worker.cancel();
        runtime.holdStart = false;
        await runtime.pausedIn(generation);
        expect(runtime.referenceInputSnapshot(afterHold: true), original);
        timers.poll();
        runtime.resume();
        expect(await generation, isNull);
        runtime.pauseAfter = -1;
        final images = await worker.generate(
          referenceRequest([reference]),
          (_, _) {},
        );
        expect(
          [for (final image in images!) (image.width, image.height)],
          [(64, 128)],
        );
        await worker.generate(_request(), (_, _) {});
        expect(runtime.referenceInputSnapshot(), everyElement(0));
        expect(runtime.lastReferenceArgs, isNull);
        await runtime.flush();
        expect(
          runtime
              .calls('worker')
              .where((c) => c.startsWith('sd_dart_generate_image')),
          everyElement('sd_dart_generate_image+held'),
        );
      });

      test('direct worker refuses references without recipe proof, for '
          'another family and in another number, before generation', () async {
        final reference = ImageEditingPixels.rgb(
          width: 64,
          height: 128,
          pixels: Uint8List(64 * 128 * 3),
        );
        for (final kind in ['no proof', 'family', 'two']) {
          runtime.modelVersion = kind == 'family' ? 'Flux Fill' : 'Flux';
          final worker = await start(
            config: kind == 'no proof'
                ? const ImageGenerationSessionConfig(
                    files: {'diffusionModel': '/models/flux1-dev.gguf'},
                    backend: 'gpu',
                    threads: 1,
                  )
                : referenceConfig,
          );
          expect(
            worker.supportsReferenceImageEditing,
            kind == 'two',
            reason: kind,
          );
          await runtime.flush();
          runtime.clearCalls();
          await expectLater(
            worker.generate(
              referenceRequest(
                kind == 'two' ? [reference, reference] : [reference],
              ),
              (_, _) {},
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                contains('eference'),
              ),
            ),
            reason: kind,
          );
          await runtime.flush();
          expect(runtime.calls('worker'), isEmpty, reason: kind);
          await worker.dispose();
        }
      });
    });

    group('hires fix', () {
      const hiresConfig = ImageGenerationSessionConfig(
        files: {'model': '/models/sd15.safetensors'},
        backend: 'cpu',
        threads: 1,
        hiresFixRecipeVerified: true,
      );
      ImageGenerationSessionRequest hiresRequest({
        int steps = 3,
        int hiresSteps = 2,
        int count = 1,
        ImageVaeTiling? tiling,
      }) => ImageGenerationSessionRequest(
        prompt: 'a fox',
        negativePrompt: '',
        width: 64,
        height: 128,
        steps: steps,
        guidanceScale: 7,
        seed: 42,
        count: count,
        vaeTiling: tiling,
        hiresFix: ImageGenerationSessionHiresFix(
          width: 128,
          height: 192,
          steps: hiresSteps,
          denoisingStrength: 0.55,
          upscaler: ImageHiresUpscaler.latent,
        ),
      );

      test('the pass reaches the guarded generation, both passes report '
          'progress, and an ordinary request after it has none', () async {
        runtime.modelVersion = 'SD 1.x';
        final worker = await start(config: hiresConfig);
        expect(worker.supportsHiresFix, isTrue);
        await runtime.flush();
        runtime.clearCalls();
        final progress = <(int, int)>[];
        final images = await worker.generate(
          hiresRequest(count: 2),
          (step, steps) => progress.add((step, steps)),
        );
        expect(
          [for (final image in images!) (image.width, image.height)],
          [(128, 192), (128, 192)],
        );
        final (
          enabled,
          upscaler,
          width,
          height,
          steps,
          strength,
          scale,
          sigmas,
          modelPath,
        ) = runtime.lastHires;
        expect(
          (enabled, width, height, steps, scale, sigmas, modelPath),
          (true, 128, 192, 2, 0.0, 0, 0),
        );
        expect(upscaler, sd.sd_hires_upscaler_t.SD_HIRES_UPSCALER_LATENT.value);
        expect(strength, closeTo(0.55, 0.000001));
        expect(progress, [
          ..._upstreamReports(steps: 3, count: 2),
          ..._upstreamReports(steps: 2, count: 2),
        ]);
        await runtime.flush();
        expect(runtime.calls('worker'), _generateCalls);

        final plain = await worker.generate(_request(), (_, _) {});
        expect((plain!.single.width, plain.single.height), (8, 8));
        expect(runtime.lastHires.$1, isFalse);
        expect(runtime.lastHires.$3, 0);
      });

      test('a cancel during the second pass stops it before its next step '
          'and returns no images', () async {
        runtime.modelVersion = 'SD 2.x';
        final worker = await start(config: hiresConfig);
        // 4 first-pass reports, then 0/3 and 1/3 of the second pass.
        runtime.pauseAfter = 6;
        final progress = <(int, int)>[];
        final generation = worker.generate(
          hiresRequest(hiresSteps: 3),
          (step, steps) => progress.add((step, steps)),
        );
        await runtime.pausedIn(generation);
        worker.cancel();
        runtime.resume();
        expect(await generation, isNull);
        expect(progress, [
          ..._upstreamReports(steps: 3, count: 1),
          (0, 3),
          (1, 3),
        ]);
        runtime.pauseAfter = -1;
        expect(await worker.generate(hiresRequest(), (_, _) {}), hasLength(1));
      });

      test('direct worker refuses a hires fix without recipe proof, for '
          'another family, and combined with another input, before '
          'generation', () async {
        for (final kind in ['no proof', 'family', 'tiling']) {
          runtime.modelVersion = switch (kind) {
            'family' => 'SDXL',
            'tiling' => 'SD 2.x',
            _ => 'SD 1.x',
          };
          final worker = await start(
            config: switch (kind) {
              'no proof' => _config,
              // Tiling alone is admitted, so only the combination refuses.
              'tiling' => const ImageGenerationSessionConfig(
                files: {'model': '/models/sd-turbo.gguf'},
                backend: 'cpu',
                threads: 1,
                hiresFixRecipeVerified: true,
                vaeTilingRecipeVerified: true,
              ),
              _ => hiresConfig,
            },
          );
          expect(worker.supportsHiresFix, kind == 'tiling', reason: kind);
          await runtime.flush();
          runtime.clearCalls();
          await expectLater(
            worker.generate(
              hiresRequest(
                tiling: kind == 'tiling' ? const ImageVaeTiling() : null,
              ),
              (_, _) {},
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                contains('hires fix'),
              ),
            ),
            reason: kind,
          );
          await runtime.flush();
          expect(runtime.calls('worker'), isEmpty, reason: kind);
          await worker.dispose();
        }
      });
    });

    test(
      'direct worker refuses image editing without recipe proof before generation',
      () async {
        final worker = await loaded();
        expect(worker.supportsImageEditing, isFalse);
        await expectLater(
          worker.generate(
            ImageGenerationSessionRequest(
              prompt: 'edit',
              negativePrompt: '',
              width: 64,
              height: 64,
              steps: 1,
              guidanceScale: 1,
              seed: 42,
              count: 1,
              initialImage: ImageEditingPixels.rgb(
                width: 64,
                height: 64,
                pixels: Uint8List(64 * 64 * 3),
              ),
              strength: 0.5,
            ),
            (_, _) {},
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await runtime.flush();
        expect(runtime.calls('worker'), isEmpty);
        expect(runtime.calls('caller'), isEmpty);
      },
    );

    test(
      'tiling survives worker transport and resets on the next request',
      () async {
        final worker = await start(
          config: const ImageGenerationSessionConfig(
            files: {'model': '/models/renamed.gguf'},
            backend: 'cpu',
            threads: 1,
            vaeTilingRecipeVerified: true,
          ),
        );
        await worker.generate(
          const ImageGenerationSessionRequest(
            prompt: 'a',
            negativePrompt: '',
            width: 512,
            height: 512,
            steps: 1,
            guidanceScale: 1,
            seed: 42,
            count: 1,
            vaeTiling: ImageVaeTiling(
              tileWidth: 128,
              tileHeight: 256,
              overlap: 0.25,
            ),
          ),
          (_, _) {},
        );
        expect(runtime.lastVaeTiling, (true, 128, 256, 0.25, 0.0, 0.0));
        await worker.generate(_request(), (_, _) {});
        expect(runtime.lastVaeTiling.$1, isFalse);
        await runtime.flush();
        expect(
          runtime
              .calls('worker')
              .where((c) => c == 'sd_dart_generate_image+held')
              .length,
          2,
        );
      },
    );

    test(
      'direct worker tiling without decoder proof makes no native call',
      () async {
        final worker = await loaded();
        await expectLater(
          worker.generate(
            const ImageGenerationSessionRequest(
              prompt: 'a',
              negativePrompt: '',
              width: 512,
              height: 512,
              steps: 1,
              guidanceScale: 1,
              seed: 42,
              count: 1,
              vaeTiling: ImageVaeTiling(),
            ),
            (_, _) {},
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await runtime.flush();
        expect(runtime.calls('caller'), isEmpty);
        expect(runtime.calls('worker'), isEmpty);
        await worker.generate(_request(), (_, _) {});
      },
    );

    test(
      'direct worker circular requests reject an unqualified native family',
      () async {
        final worker = await loaded();
        await expectLater(
          worker.generate(
            const ImageGenerationSessionRequest(
              prompt: 'stone',
              negativePrompt: '',
              width: 512,
              height: 512,
              steps: 4,
              guidanceScale: 1,
              seed: 42,
              count: 1,
              circularX: true,
            ),
            (_, _) {},
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await runtime.flush();
        expect(runtime.calls('caller'), isEmpty);
        expect(runtime.calls('worker'), isEmpty);
        await worker.generate(_request(), (_, _) {});
      },
    );

    /// The records the calling isolate's logger hands its handler from now
    /// on, at [level].
    List<(LlamaLogLevel, String)> records({
      LlamaLogLevel level = LlamaLogLevel.debug,
    }) {
      final records = <(LlamaLogLevel, String)>[];
      final logger = LlamaLogger.instance;
      final previous = logger.level;
      logger
        ..setLevel(level)
        ..setHandler((record) => records.add((record.level, record.message)));
      addTearDown(() {
        logger
          ..setLevel(previous)
          ..setHandler(null);
      });
      return records;
    }

    setUp(() {
      runtime = FakeStableDiffusionRuntime();
      timers = ManualProgressTimers();
      StableDiffusionImageWorker.debugResetLogPositionForTesting();
    });

    tearDown(() async {
      for (final worker in workers) {
        await worker.dispose();
      }
      workers.clear();
      runtime.close();
    });

    test('a load enables the recorder before the worker creates its tracked '
        'context, and holds the context for its exit-free', () async {
      final worker = await start();
      await runtime.flush();

      expect(runtime.calls('caller'), _startCalls);
      expect(runtime.calls('worker'), _loadCalls);
      expect(worker.modelVersion, 'SD 2.x');
    });

    test('a load writes its files into the parameters after the runtime '
        'initialized them', () async {
      await start();

      expect(runtime.loadedModelPath, '/models/sdxs.gguf');
    });

    for (final capacity in [null, 0, 1, 64]) {
      test(
        'worker load reads conditioning capacity $capacity across isolates',
        () async {
          await start(
            config: ImageGenerationSessionConfig(
              files: _config.files,
              backend: _config.backend,
              threads: _config.threads,
              conditioningCacheSize: capacity,
            ),
          );
          expect(runtime.loadedConditioningCacheSize, capacity ?? 4);
        },
      );
    }

    test('a generation marks its start, reads the reports after the reply '
        'and stops its timer', () async {
      runtime.loadReports = 3;
      final worker = await loaded();
      final progress = <(int, int)>[];

      final images = await worker.generate(
        _request(),
        (step, steps) => progress.add((step, steps)),
      );
      await runtime.flush();

      expect(runtime.calls('caller'), [
        'sd_dart_progress_read:mark',
        'sd_dart_progress_read',
      ]);
      expect(runtime.calls('worker'), _generateCalls);
      expect(progress, [(0, 2), (1, 2), (2, 2)]);
      expect(timers.intervals, [const Duration(milliseconds: 50)]);
      expect(timers.active, 0);
      final GeneratedImage image = images!.single;
      expect((image.width, image.height, image.channels), (8, 8, 3));
      expect(image.pixels, List.filled(8 * 8 * 3, 1));
    });

    test('a poll during a generation delivers the reports so far, and the '
        'events of a batch of three match the unpolled stream', () async {
      final worker = await loaded();
      runtime.pauseAfter = 7;
      const steps = 4;
      const count = 3;
      final tracker = ImageGenerationProgressTracker(
        steps: steps,
        imageCount: count,
      );
      final events = <String>[];
      final generation = worker.generate(
        _request(steps: steps, count: count),
        (step, total) =>
            events.addAll(tracker.onNativeProgress(step, total).map(_describe)),
      );
      await runtime.pausedIn(generation);

      expect(events, isEmpty);
      timers.poll();
      expect(events, [
        'sampling 0/4 image 0/3',
        'sampling 1/4 image 0/3',
        'sampling 2/4 image 0/3',
        'sampling 3/4 image 0/3',
        'sampling 4/4 image 0/3',
        'sampling 0/4 image 1/3',
        'sampling 1/4 image 1/3',
      ]);
      runtime.resume();
      final images = await generation;
      await runtime.flush();

      final reference = ImageGenerationProgressTracker(
        steps: steps,
        imageCount: count,
      );
      expect(events, [
        for (final (step, total) in _upstreamReports(
          steps: steps,
          count: count,
        ))
          ...reference.onNativeProgress(step, total).map(_describe),
      ]);
      expect(events, hasLength(16));
      expect(events.last, 'decoding 0/3 image 2/3');
      expect(runtime.calls('caller'), [
        'sd_dart_progress_read:mark',
        'sd_dart_progress_read',
        'sd_dart_progress_read',
      ]);
      expect([for (final image in images!) image.pixels.first], [1, 2, 3]);
    });

    test('a second generation reads only its own reports', () async {
      final worker = await loaded();
      final first = <(int, int)>[];
      final second = <(int, int)>[];

      await worker.generate(_request(steps: 3), (a, b) => first.add((a, b)));
      await worker.generate(
        _request(steps: 1, count: 2),
        (a, b) => second.add((a, b)),
      );

      expect(first, _upstreamReports(steps: 3, count: 1));
      expect(second, _upstreamReports(steps: 1, count: 2));
    });

    test('reads until it holds the newest report when there are more than '
        'one read returns', () async {
      final worker = await loaded();
      runtime.decodeReports = 200;
      final progress = <(int, int)>[];

      await worker.generate(
        _request(steps: 4, count: 3),
        (step, steps) => progress.add((step, steps)),
      );
      await runtime.flush();

      expect(progress, _upstreamReports(steps: 4, count: 3, tiles: 200));
      // 215 reports, 64 a read.
      expect(runtime.calls('caller'), [
        'sd_dart_progress_read:mark',
        for (var read = 0; read < 4; read++) 'sd_dart_progress_read',
      ]);
    });

    test('one poll stops after 64 reads of a runtime that reports faster '
        'than it is read', () async {
      final worker = await loaded();
      runtime.pauseAfter = 0;
      var delivered = 0;
      final generation = worker.generate(_request(), (_, _) => delivered++);
      await runtime.pausedIn(generation);
      runtime.reportsPerRead = 100;

      timers.poll();
      await runtime.flush();

      expect(runtime.calls('caller'), [
        'sd_dart_progress_read:mark',
        for (var read = 0; read < 64; read++) 'sd_dart_progress_read',
      ]);
      expect(delivered, 64 * 64);
      runtime.reportsPerRead = 0;
      runtime.resume();
      await generation;
    });

    test('delivers the reports the runtime still has, in order, when it '
        'dropped older ones, and warns once', () async {
      runtime.close();
      runtime = FakeStableDiffusionRuntime(history: 8);
      final warnings = <String>[];
      final logger = LlamaLogger.instance;
      final level = logger.level;
      logger
        ..setLevel(LlamaLogLevel.warn)
        ..setHandler((record) => warnings.add(record.message));
      addTearDown(() {
        logger
          ..setLevel(level)
          ..setHandler(null);
      });
      final worker = await loaded();
      runtime.pauseAfter = 3;
      final progress = <(int, int)>[];
      final generation = worker.generate(
        _request(steps: 9, count: 2),
        (step, steps) => progress.add((step, steps)),
      );
      await runtime.pausedIn(generation);
      timers.poll();
      expect(progress, [(0, 9), (1, 9), (2, 9)]);

      runtime.resume();
      await generation;

      // 20 reports; the 17 after the poll leave the newest 8.
      final all = _upstreamReports(steps: 9, count: 2);
      expect(progress, [...all.take(3), ...all.skip(12)]);
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('dropped 9 image-generation'));

      warnings.clear();
      progress.clear();
      runtime.pauseAfter = -1;
      await worker.generate(
        _request(steps: 2),
        (step, steps) => progress.add((step, steps)),
      );
      expect(progress, _upstreamReports(steps: 2, count: 1));
      expect(warnings, isEmpty);
    });

    test('the largest request cannot record more reports than the runtime '
        'keeps', () {
      expect(
        ImageGenerationRequest.maxCount * (ImageGenerationRequest.maxSteps + 1),
        lessThanOrEqualTo(StableDiffusionCalls.progressHistory),
      );
      // A hires pass can run one step more than asked.
      expect(
        ImageHiresFix.maxCount *
            (ImageGenerationRequest.maxSteps +
                1 +
                ImageGenerationRequest.maxSteps +
                2),
        lessThanOrEqualTo(StableDiffusionCalls.progressHistory),
      );
    });

    test('a cancel that the starting generation cleared is applied again by '
        'the next poll', () async {
      final worker = await loaded();
      runtime
        ..holdStart = true
        ..pauseAfter = 0;
      final progress = <(int, int)>[];
      final generation = worker.generate(
        _request(steps: 4),
        (step, steps) => progress.add((step, steps)),
      );
      worker.cancel();
      expect(runtime.cancelPending, isTrue);
      runtime.holdStart = false;
      await runtime.pausedIn(generation);
      expect(runtime.cancelPending, isFalse);

      timers.poll();
      expect(runtime.cancelPending, isTrue);
      runtime.resume();

      expect(await generation, isNull);
      await runtime.flush();
      expect(runtime.calls('caller'), [
        'sd_dart_progress_read:mark',
        'sd_dart_cancel_generation',
        'sd_dart_cancel_generation',
        'sd_dart_progress_read',
        'sd_dart_progress_read',
      ]);
      expect(runtime.calls('worker'), [
        'sd_img_gen_params_init+held',
        'sd_dart_generate_image+held',
        'sd_dart_last_error',
      ]);
      expect(progress, [(0, 4)]);
    });

    test('a cancel during a generation stops it before the next step, and '
        'the next generation is not cancelled', () async {
      final worker = await loaded();
      runtime.pauseAfter = 2;
      final progress = <(int, int)>[];
      final generation = worker.generate(
        _request(steps: 4),
        (step, steps) => progress.add((step, steps)),
      );
      await runtime.pausedIn(generation);
      timers.poll();
      worker.cancel();
      runtime.resume();

      expect(await generation, isNull);
      await runtime.flush();
      expect(runtime.calls('caller'), [
        'sd_dart_progress_read:mark',
        'sd_dart_progress_read',
        'sd_dart_cancel_generation',
        'sd_dart_progress_read',
      ]);
      expect(progress, [(0, 4), (1, 4)]);

      runtime.clearCalls();
      runtime.pauseAfter = 1;
      final next = worker.generate(_request(), (_, _) {});
      await runtime.pausedIn(next);
      timers.poll();
      runtime.resume();
      expect(await next, hasLength(1));
      await runtime.flush();
      expect(runtime.calls('caller'), [
        'sd_dart_progress_read:mark',
        'sd_dart_progress_read',
        'sd_dart_progress_read',
      ]);
    });

    test('a cancel with no generation running is not applied to the next '
        'one', () async {
      final worker = await loaded();
      worker.cancel();
      runtime.pauseAfter = 0;
      final generation = worker.generate(_request(), (_, _) {});
      await runtime.pausedIn(generation);
      timers.poll();
      runtime.resume();

      expect(await generation, hasLength(1));
      await runtime.flush();
      expect(runtime.calls('caller'), [
        'sd_dart_cancel_generation',
        'sd_dart_progress_read:mark',
        'sd_dart_progress_read',
        'sd_dart_progress_read',
      ]);
    });

    test(
      'the default timer delivers progress while the generation runs',
      () async {
        final worker = await StableDiffusionImageWorker.start(
          _config,
          resolveCalls: runtime.resolver,
        );
        workers.add(worker);
        runtime.pauseAfter = 2;
        final progress = <(int, int)>[];
        final polled = Completer<void>();
        final generation = worker.generate(_request(steps: 4), (step, steps) {
          progress.add((step, steps));
          if (progress.length == 2) polled.complete();
        });
        await runtime.pausedIn(generation);

        await polled.future.timeout(const Duration(seconds: 10));
        expect(progress, [(0, 4), (1, 4)]);
        runtime.resume();
        await generation;
        expect(progress, _upstreamReports(steps: 4, count: 1));
      },
    );

    test('dispose frees the context through the exit-free after releasing '
        'its hold, and a later cancel calls nothing', () async {
      final worker = await loaded();

      await worker.dispose();
      worker.cancel();
      await runtime.flush();

      expect(runtime.calls('worker'), ['sd_dart_exit_free']);
      expect(runtime.calls('caller'), isEmpty);
    });

    test('a failed load creates nothing to free, and its error carries the '
        'reason the runtime logged, read right after the load, with the '
        'file named by role', () async {
      runtime.rejectLoad = true;

      await expectLater(
        start(),
        throwsA(
          isA<LlamaModelException>()
              .having(
                (error) => error.message,
                'message',
                allOf(
                  startsWith(
                    'stable-diffusion.cpp could not load the image model '
                    'files. The runtime reported: "model_loader.cpp:1061 - '
                    "cannot inspect model source '<checkpoint file>': No "
                    'such file or directory".',
                  ),
                  isNot(contains('Check that they form a model')),
                  isNot(contains('no reason')),
                ),
              )
              .having((error) => error.details, 'details', 'files: checkpoint')
              .having(
                (error) => '$error',
                'toString',
                isNot(contains('/models')),
              ),
        ),
      );
      await runtime.flush();

      expect(runtime.calls('caller'), _startCalls);
      expect(runtime.calls('worker'), [
        'sd_ctx_params_init',
        'sd_dart_new_sd_ctx',
        'sd_dart_last_error',
      ]);
    });

    test('a failed load for which the runtime logged no error says so and '
        'keeps the general advice', () async {
      runtime
        ..rejectLoad = true
        ..quietReject = true;

      await expectLater(
        start(),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Check that they form a model the runtime supports'),
              endsWith('The runtime logged no reason.'),
              isNot(contains('reported:')),
            ),
          ),
        ),
      );
    });

    test('a model that cannot generate images is freed through the '
        'exit-free', () async {
      runtime.videoOnly = true;

      await expectLater(
        start(),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('does not support image generation'),
          ),
        ),
      );
      await runtime.flush();

      expect(runtime.calls('worker'), [
        'sd_ctx_params_init',
        'sd_dart_new_sd_ctx',
        'sd_ctx_supports_image_generation+held',
        'sd_dart_exit_free',
      ]);
    });

    test('a runtime without the sd_dart_ functions is unsupported, and '
        'nothing is called on it', () async {
      await expectLater(
        StableDiffusionImageWorker.start(_config, resolveCalls: () => null),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('sd_dart_progress_read'),
              contains('sd_dart_new_sd_ctx'),
              contains('stable-diffusion-native v0.2.0-1 or later'),
            ),
          ),
        ),
      );

      runtime.missingInWorker = true;
      await expectLater(start(), throwsA(isA<LlamaUnsupportedException>()));
      await runtime.flush();
      expect(runtime.calls('caller'), _startCalls);
      expect(runtime.calls('worker'), isEmpty);
    });

    test('a generation that fails leaves its context held, so the worker\'s '
        'shutdown frees it through the exit-free', () async {
      final worker = await loaded();
      runtime.throwInGenerate = true;

      await expectLater(
        worker.generate(_request(), (_, _) {}),
        throwsA(isA<LlamaStateException>()),
      );
      await runtime.flush();

      expect(runtime.calls('worker'), [
        'sd_img_gen_params_init+held',
        'sd_dart_generate_image+held',
        'uncaught generation error+held',
      ]);
    });

    test('a worker that dies in a generation fails it, stops its timer and '
        'stays safe to dispose, and a later cancel calls nothing', () async {
      final worker = await loaded();
      runtime.throwInGenerate = true;

      await expectLater(
        worker.generate(_request(), (_, _) {}),
        throwsA(isA<LlamaStateException>()),
      );
      expect(timers.active, 0);
      await expectLater(
        worker.generate(_request(), (_, _) {}),
        throwsA(isA<LlamaStateException>()),
      );
      worker.cancel();
      await worker.dispose();
      await runtime.flush();

      expect(runtime.calls('worker'), [
        'sd_img_gen_params_init+held',
        'sd_dart_generate_image+held',
        'uncaught generation error+held',
      ]);
      expect(runtime.calls('caller'), ['sd_dart_progress_read:mark']);
    });

    for (final (name, errors) in [
      ('a failed command buffer', _commandBufferFailed),
      ('a backend in its error state', _backendInErrorState),
    ]) {
      test('a generation that fails with $name says to reload the model, and '
          'every later one fails the same way without native work', () async {
        final worker = await loaded();
        runtime.generationErrors = errors;

        await expectLater(
          worker.generate(_request(), (_, _) {}),
          throwsA(_reloadFailure),
        );
        await runtime.flush();
        expect(runtime.calls('worker'), [
          'sd_img_gen_params_init+held',
          'sd_dart_generate_image+held',
          'sd_dart_last_error',
        ]);

        runtime
          ..generationErrors = null
          ..clearCalls();
        await expectLater(
          worker.generate(_request(), (_, _) {}),
          throwsA(_reloadFailure),
        );
        await runtime.flush();
        expect(runtime.calls('worker'), isEmpty);
        expect(runtime.calls('caller'), isEmpty);
      });
    }

    test('a generation that fails for another reason returns null, and the '
        'next one runs', () async {
      final worker = await loaded();
      runtime.generationErrors =
          'ggml_backend_cpu_buffer_type_alloc_buffer: failed to allocate '
          'buffer of size 1073741824';

      expect(await worker.generate(_request(), (_, _) {}), isNull);
      await runtime.flush();
      expect(runtime.calls('worker'), [
        'sd_img_gen_params_init+held',
        'sd_dart_generate_image+held',
        'sd_dart_last_error',
      ]);

      runtime.generationErrors = null;
      expect(await worker.generate(_request(), (_, _) {}), hasLength(1));
    });

    for (final (name, errors) in [
      ('command-buffer failure', _commandBufferFailed),
      ('poisoned backend', _backendInErrorState),
    ]) {
      test('an apparent native success with $name rejects and frees its '
          'images even with logging disabled', () async {
        final worker = await loaded();
        runtime
          ..generationErrors = errors
          ..returnImagesDespiteError = true;

        await expectLater(
          worker.generate(_request(count: 2), (_, _) {}),
          throwsA(_reloadFailure),
        );
        await runtime.flush();
        expect(runtime.calls('worker'), _generateCalls);
        runtime
          ..generationErrors = null
          ..clearCalls();
        await expectLater(
          worker.generate(_request(), (_, _) {}),
          throwsA(_reloadFailure),
        );
        await runtime.flush();
        expect(runtime.calls('worker'), isEmpty);
        await worker.dispose();
        final fresh = await loaded();
        expect(await fresh.generate(_request(), (_, _) {}), hasLength(1));
      });
    }

    test('an apparent native success with an unrelated recorded error '
        'still returns its image', () async {
      final worker = await loaded();
      runtime
        ..generationErrors = 'unrelated optional backend diagnostic'
        ..returnImagesDespiteError = true;
      expect(await worker.generate(_request(), (_, _) {}), hasLength(1));
    });

    test(
      'a generation that succeeds checks for recorded backend failures',
      () async {
        final worker = await loaded();

        expect(await worker.generate(_request(), (_, _) {}), hasLength(1));
        await runtime.flush();
        expect(runtime.calls('worker'), _generateCalls);
      },
    );

    group('with a log level', () {
      test('the recorder is set to the level before the worker starts, and '
          'the worker reads what the load recorded after its calls on the '
          'context', () async {
        final logged = records();

        await start(logLevel: LlamaLogLevel.info);
        await runtime.flush();

        expect(runtime.calls('caller'), [
          'sd_dart_log_enable',
          'sd_dart_log_set_level:2',
          'sd_dart_progress_enable',
        ]);
        expect(runtime.calls('worker'), [..._loadCalls, ..._logReads(1)]);
        expect(logged, [
          (
            LlamaLogLevel.info,
            'stable_diffusion: stable-diffusion.cpp:262 - loading model from '
                "'<checkpoint file>'",
          ),
        ]);
      });

      test('each level sets its own sd_log_level_t', () async {
        for (final (level, threshold) in [
          (LlamaLogLevel.debug, 0),
          (LlamaLogLevel.warn, 3),
          (LlamaLogLevel.error, 4),
        ]) {
          final worker = await loaded(logLevel: level);
          await worker.dispose();
          workers.remove(worker);
          runtime.clearCalls();
          await start(logLevel: level);
          await runtime.flush();

          expect(
            runtime.calls('caller')[1],
            'sd_dart_log_set_level:$threshold',
          );
        }
      });

      test('a generation is followed by a read of what it recorded, after '
          'its images are freed', () async {
        final worker = await loaded(logLevel: LlamaLogLevel.debug);
        final logged = records();

        await worker.generate(_request(), (_, _) {});
        await runtime.flush();

        expect(runtime.calls('worker'), [..._generateCalls, ..._logReads(2)]);
        expect(logged, [
          (
            LlamaLogLevel.debug,
            'stable_diffusion: stable-diffusion.cpp:3120 - sampling',
          ),
          (
            LlamaLogLevel.info,
            'stable_diffusion: stable-diffusion.cpp:3391 - generating',
          ),
        ]);
      });

      test('the runtime records nothing below the level, and the logger of '
          'the calling isolate applies its own level again', () async {
        final worker = await loaded(logLevel: LlamaLogLevel.info);
        final logged = records(level: LlamaLogLevel.warn);
        runtime.log(3, utf8.encode('ggml - a warning'));

        await worker.generate(_request(), (_, _) {});
        await runtime.flush();

        // The warning and "generating"; "sampling" was not recorded.
        expect(runtime.calls('worker'), [..._generateCalls, ..._logReads(2)]);
        expect(logged, [
          (LlamaLogLevel.warn, 'stable_diffusion: ggml - a warning'),
        ]);
      });

      test('dispose reads what was recorded since the last read, after the '
          'context is freed', () async {
        final worker = await loaded(logLevel: LlamaLogLevel.info);
        final logged = records();
        runtime.log(4, utf8.encode('ggml - late error'));

        await worker.dispose();
        await runtime.flush();

        expect(runtime.calls('worker'), ['sd_dart_exit_free', ..._logReads(1)]);
        expect(logged, [
          (LlamaLogLevel.error, 'stable_diffusion: ggml - late error'),
        ]);
      });

      test('a second worker continues where the first one stopped '
          'reading', () async {
        final logged = records();
        final first = await start(logLevel: LlamaLogLevel.info);
        await first.generate(_request(), (_, _) {});
        await first.dispose();
        expect(logged, hasLength(2));
        logged.clear();
        runtime.clearCalls();

        await start(logLevel: LlamaLogLevel.info);
        await runtime.flush();

        expect(runtime.calls('worker'), [..._loadCalls, ..._logReads(1)]);
        expect(logged.single.$2, contains('loading model from'));
      });

      test('a drain that finishes after a later one does not move the read '
          'position back', () async {
        final first = await loaded(logLevel: LlamaLogLevel.info);
        final second = await loaded(logLevel: LlamaLogLevel.info);
        final logged = records(level: LlamaLogLevel.info);
        const generating =
            'stable_diffusion: stable-diffusion.cpp:3391 - generating';

        // The first drain reads its message and is held before it sends it;
        // the second one starts from the same position and reads both.
        runtime.holdNextLogDrain();
        final held = first.generate(_request(), (_, _) {});
        await runtime.logDrainHeld();
        await second.generate(_request(), (_, _) {});
        runtime.releaseLogDrain();
        await held;
        expect(logged.map((record) => record.$2), everyElement(generating));
        logged.clear();

        await second.generate(_request(), (_, _) {});

        expect(logged, [(LlamaLogLevel.info, generating)]);
      });

      test('a drain that finishes after a later one does not move the '
          'dropped count back', () async {
        final first = await loaded(logLevel: LlamaLogLevel.error);
        final second = await loaded(logLevel: LlamaLogLevel.error);
        final logged = records();

        // The first drain reads no drops and is held before it sends that;
        // the second one reads the three dropped meanwhile.
        runtime.holdNextLogDrain();
        final held = first.generate(_request(), (_, _) {});
        await runtime.logDrainHeld();
        runtime.dropUnrecorded(3);
        await second.generate(_request(), (_, _) {});
        runtime.releaseLogDrain();
        await held;
        await second.generate(_request(), (_, _) {});
        await runtime.flush();

        expect(logged, hasLength(1));
        expect(
          logged.single.$2,
          startsWith('The stable_diffusion runtime dropped 3 log messages'),
        );
      });

      test('messages the runtime dropped are reported in one warning, after '
          'the ones it kept', () async {
        runtime.close();
        runtime = FakeStableDiffusionRuntime(logHistory: 2);
        final worker = await loaded(logLevel: LlamaLogLevel.info);
        final logged = records();
        for (var i = 1; i <= 5; i++) {
          runtime.log(2, utf8.encode('message $i'));
        }

        await worker.generate(_request(), (_, _) {});

        // Six were recorded since the last read, and the newest two kept.
        expect(logged.take(2), [
          (LlamaLogLevel.info, 'stable_diffusion: message 5'),
          (
            LlamaLogLevel.info,
            'stable_diffusion: stable-diffusion.cpp:3391 - generating',
          ),
        ]);
        expect(logged, hasLength(3));
        expect(logged.last.$1, LlamaLogLevel.warn);
        expect(
          logged.last.$2,
          startsWith('The stable_diffusion runtime dropped 4 log messages'),
        );

        logged.clear();
        await worker.generate(_request(), (_, _) {});
        expect(logged, hasLength(1));
      });

      test('messages dropped with nothing new to read are reported once, '
          'not again by the next read', () async {
        final worker = await loaded(logLevel: LlamaLogLevel.error);
        final logged = records();
        runtime.dropUnrecorded(3);

        await worker.generate(_request(), (_, _) {});
        await worker.generate(_request(), (_, _) {});
        await runtime.flush();

        // Nothing is recorded at the error level, so the position stays.
        expect(runtime.calls('worker'), [
          ..._generateCalls,
          ..._logReads(0),
          ..._generateCalls,
          ..._logReads(0),
        ]);
        expect(logged, hasLength(1));
        expect(
          logged.single.$2,
          startsWith('The stable_diffusion runtime dropped 3 log messages'),
        );
      });

      test('text that is not valid UTF-8 is delivered, not thrown', () async {
        final worker = await loaded(logLevel: LlamaLogLevel.info);
        final logged = records();
        runtime.log(2, [0x62, 0x61, 0x64, 0xff, 0x21]);

        await worker.generate(_request(), (_, _) {});

        expect(logged.first, (
          LlamaLogLevel.info,
          'stable_diffusion: bad\u{fffd}!',
        ));
      });

      test('a failed load forwards what the runtime logged before it '
          'fails', () async {
        runtime.rejectLoad = true;
        final logged = records();

        await expectLater(
          start(logLevel: LlamaLogLevel.error),
          throwsA(isA<LlamaModelException>()),
        );
        await runtime.flush();

        expect(runtime.calls('worker'), [
          'sd_ctx_params_init',
          'sd_dart_new_sd_ctx',
          'sd_dart_last_error',
          ..._logReads(1),
        ]);
        expect(logged, [
          (
            LlamaLogLevel.error,
            'stable_diffusion: model_loader.cpp:1061 - cannot inspect model '
                "source '<checkpoint file>': No such file or directory",
          ),
        ]);
      });

      test('a model that cannot generate images is freed before the log is '
          'read', () async {
        runtime.videoOnly = true;

        await expectLater(
          start(logLevel: LlamaLogLevel.info),
          throwsA(isA<LlamaModelException>()),
        );
        await runtime.flush();

        expect(runtime.calls('worker'), [
          'sd_ctx_params_init',
          'sd_dart_new_sd_ctx',
          'sd_ctx_supports_image_generation+held',
          'sd_dart_exit_free',
          ..._logReads(1),
        ]);
      });
    });

    group('on a runtime older than the log, v0.2.0-1', () {
      setUp(() => runtime.olderRelease = true);

      test('a failed command buffer cannot be told apart from another '
          'failure, so the generation returns null', () async {
        final worker = await loaded();
        runtime.generationErrors = _backendInErrorState;

        expect(await worker.generate(_request(), (_, _) {}), isNull);
        await runtime.flush();
        expect(runtime.calls('worker'), [
          'sd_img_gen_params_init+held',
          'sd_dart_generate_image+held',
        ]);
      });

      test('a worker loads, generates and disposes without any log call, '
          'whatever the log level', () async {
        final logged = records();

        final worker = await start(logLevel: LlamaLogLevel.debug);
        final images = await worker.generate(_request(), (_, _) {});
        await worker.dispose();
        await runtime.flush();

        expect(images, hasLength(1));
        expect(runtime.calls('caller'), [
          'sd_dart_progress_enable',
          'sd_dart_progress_read:mark',
          'sd_dart_progress_read',
        ]);
        expect(runtime.calls('worker'), [
          ..._loadCalls,
          ..._generateCalls.where((call) => call != 'sd_dart_last_error'),
          'sd_dart_exit_free',
        ]);
        expect(logged, isEmpty);
      });

      test('a failed load names the roles and the release that reports the '
          'reason', () async {
        runtime.rejectLoad = true;

        await expectLater(
          start(logLevel: LlamaLogLevel.debug),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('Check that they form a model the runtime supports'),
                endsWith(
                  'This stable_diffusion runtime does not report its reason: '
                  'that needs stable-diffusion-native v0.2.0-2 or later.',
                ),
              ),
            ),
          ),
        );
        await runtime.flush();

        expect(runtime.calls('worker'), [
          'sd_ctx_params_init',
          'sd_dart_new_sd_ctx',
        ]);
      });
    });
  });

  group('stableDiffusionBackendInErrorState', () {
    test('is true for a failed Metal command buffer and for the backend '
        'refusing a graph in its error state', () {
      expect(stableDiffusionBackendInErrorState(_commandBufferFailed), isTrue);
      expect(stableDiffusionBackendInErrorState(_backendInErrorState), isTrue);
    });

    test('is false for other errors and for none', () {
      expect(stableDiffusionBackendInErrorState(''), isFalse);
      expect(
        stableDiffusionBackendInErrorState(
          'ggml_backend_cpu_buffer_type_alloc_buffer: failed to allocate '
          'buffer of size 1073741824\n'
          'diffusion_engine.cpp:2594 - diffusion model compute failed',
        ),
        isFalse,
      );
    });
  });

  group('stableDiffusionModelLoadFailure', () {
    test('puts the runtime\'s reason first and keeps the roles a split '
        'checkpoint lacks', () {
      final error = stableDiffusionModelLoadFailure(
        {'diffusionModel': '/m/sdxs.gguf'},
        reason: "get sd version from file failed: ''",
        runtimeReportsReason: true,
      );

      expect(
        error.message,
        allOf(
          startsWith(
            'stable-diffusion.cpp could not load the image model files. The '
            'runtime reported: "get sd version from file failed: \'\'". '
            'Standalone diffusion weights',
          ),
          contains('need a vae or taesd file'),
          contains('need their text encoders'),
          isNot(contains('Check that they form a model')),
          isNot(contains('no reason')),
          isNot(contains('does not report')),
        ),
      );
      expect(error.details, 'files: diffusionModel');
    });

    test('says that the runtime logged no reason when it could have', () {
      final error = stableDiffusionModelLoadFailure({
        'model': '/m/sd_turbo.gguf',
      }, runtimeReportsReason: true);

      expect(error.message, contains('enough memory'));
      expect(error.message, endsWith('The runtime logged no reason.'));
    });

    test('names a missing VAE when a diffusionModel has none', () {
      final error = stableDiffusionModelLoadFailure({
        'diffusionModel': '/m/sd3.5_medium-Q8_0.gguf',
        'clipL': '/m/clip_l.gguf',
        'clipG': '/m/clip_g.gguf',
        't5xxl': '/m/t5xxl.gguf',
      });

      expect(error.message, contains('need a vae or taesd file'));
      expect(error.message, contains('is an ImageModelRole.checkpoint'));
      expect(error.message, isNot(contains('text encoders')));
      expect(error.details, 'files: diffusionModel, clipL, clipG, t5xxl');
      expect('$error', isNot(contains('/m/')));
    });

    test('names missing text encoders when a diffusionModel has none', () {
      final error = stableDiffusionModelLoadFailure({
        'diffusionModel': '/m/z_image_turbo-Q4_K.gguf',
        'vae': '/m/ae.safetensors',
      });

      expect(error.message, contains('llm for Z-Image and Qwen-Image'));
      expect(error.message, isNot(contains('vae or taesd')));
      expect(error.details, 'files: diffusionModel, vae');
    });

    test('each text encoder, llm included, counts as one', () {
      for (final role in ['clipL', 'clipG', 't5xxl', 'llm']) {
        final error = stableDiffusionModelLoadFailure({
          'diffusionModel': '/m/diffusion.gguf',
          'vae': '/m/vae.safetensors',
          role: '/m/encoder.gguf',
        });

        expect(error.message, isNot(contains('text encoders')), reason: role);
        expect(error.message, contains('enough memory'), reason: role);
      }
    });

    test('a taesd file stands in for the VAE', () {
      final error = stableDiffusionModelLoadFailure({
        'diffusionModel': '/m/flux1-schnell-Q4_0.gguf',
        'taesd': '/m/taef1.safetensors',
        'clipL': '/m/clip_l.gguf',
        't5xxl': '/m/t5xxl.gguf',
      });

      expect(error.message, isNot(contains('vae or taesd')));
      expect(error.message, contains('enough memory'));
    });

    test('a single-file checkpoint gets the general advice', () {
      final error = stableDiffusionModelLoadFailure({
        'model': '/m/sd_turbo.gguf',
      });

      expect(
        error.message,
        contains('ImageModelRole.checkpoint for a single file'),
      );
      expect(error.message, contains('enough memory'));
      expect(error.message, contains('does not report its reason'));
      expect(error.details, 'files: checkpoint');
    });
  });
}

String _describe(ImageGenerationProgressEvent event) =>
    '${event.phase.name} ${event.step}/${event.steps} '
    'image ${event.imageIndex}/${event.imageCount}';
