import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../example/basic_app/test/fixtures/image_warmup_comparison.dart';

void main() {
  test(
    'compares equally uncached requests after awaited GPU warm-up',
    () async {
      final gate = Completer<void>();
      final prompts = <String>[];
      var warmed = false;
      final pending = measureImageWarmUp(
        backendName: 'CUDA0',
        warmUp: () async {
          await gate.future;
          warmed = true;
        },
        generate: (request) async {
          expect(warmed, isTrue);
          prompts.add(request.prompt);
          return const Duration(milliseconds: 340);
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(prompts, isEmpty);
      gate.complete();
      final timings = (await pending)!;
      expect(prompts, [
        'a red fox in autumn leaves',
        'a red cat in autumn leaves',
      ]);
      expect(prompts.toSet(), hasLength(2));
      expect(prompts, isNot(contains('warm-up')));
      expect(
        timings.first,
        lessThan(timings.second * 2 + const Duration(milliseconds: 250)),
      );
      final first = imageWarmUpRequests[0];
      final second = imageWarmUpRequests[1];
      expect(first.prompt.length, second.prompt.length);
      expect(
        (
          first.width,
          first.height,
          first.steps,
          first.guidanceScale,
          first.seed,
        ),
        (
          second.width,
          second.height,
          second.steps,
          second.guidanceScale,
          second.seed,
        ),
      );
    },
  );

  test(
    'conditioning cache controls expose the original unequal comparison',
    () async {
      final cache = <String>{};
      Future<Duration> generate(ImageGenerationRequest request) async =>
          Duration(milliseconds: cache.add(request.prompt) ? 340 : 40);
      final originalFirst = await generate(imageWarmUpRequests[0]);
      final originalSecond = await generate(imageWarmUpRequests[0]);
      expect(
        originalFirst,
        greaterThan(originalSecond * 2 + const Duration(milliseconds: 250)),
      );
      cache.clear();
      final timings = (await measureImageWarmUp(
        backendName: 'Vulkan0',
        warmUp: () async {},
        generate: generate,
      ))!;
      expect(timings.first, const Duration(milliseconds: 340));
      expect(timings.second, const Duration(milliseconds: 340));
      expect(
        timings.first,
        lessThan(timings.second * 2 + const Duration(milliseconds: 250)),
      );
    },
  );

  test(
    'lost pipeline warm-up still fails the unchanged timing budget',
    () async {
      var compiled = false;
      final timings = (await measureImageWarmUp(
        backendName: 'MTL0',
        warmUp: () async {}, // Negative control: pipeline compilation was lost.
        generate: (_) async {
          final elapsed = Duration(milliseconds: compiled ? 340 : 4340);
          compiled = true;
          return elapsed;
        },
      ))!;
      expect(
        timings.first,
        greaterThan(timings.second * 2 + const Duration(milliseconds: 250)),
      );
    },
  );

  test(
    'CPU and BLAS warm-up run validation without GPU latency measurements',
    () async {
      for (final backend in ['CPU', 'BLAS']) {
        var calls = 0;
        final timings = await measureImageWarmUp(
          backendName: backend,
          warmUp: () async {
            calls++;
          },
          generate: (_) async =>
              fail('CPU cannot claim the GPU timing contract'),
        );
        expect(timings, isNull);
        expect(calls, 1);
      }
    },
  );

  test('unknown backend cannot silently bypass the timing gate', () async {
    await expectLater(
      measureImageWarmUp(
        backendName: 'unreported-device',
        warmUp: () async => fail('Unknown backend'),
        generate: (_) async => fail('Unknown backend'),
      ),
      throwsStateError,
    );
  });
}
