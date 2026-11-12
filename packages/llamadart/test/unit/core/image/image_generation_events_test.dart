import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/image/generated_image.dart';
import 'package:llamadart/src/core/image/image_generation_events.dart';

void main() {
  final result = ImageGenerationResult(
    images: [
      GeneratedImage(width: 8, height: 8, channels: 3, pixels: Uint8List(192)),
    ],
    seed: 7,
    elapsed: const Duration(milliseconds: 5),
  );

  test('completed carries the result only', () {
    final completion = ImageGenerationCompletion.completed(result);

    expect(completion.state, ImageGenerationCompletionState.completed);
    expect(completion.result, same(result));
    expect(completion.error, isNull);
  });

  test('cancelled carries neither result nor error', () {
    const completion = ImageGenerationCompletion.cancelled();

    expect(completion.state, ImageGenerationCompletionState.cancelled);
    expect(completion.result, isNull);
    expect(completion.error, isNull);
  });

  test('failed carries the error only', () {
    final error = LlamaInferenceException('GPU abort');
    final completion = ImageGenerationCompletion.failed(error);

    expect(completion.state, ImageGenerationCompletionState.failed);
    expect(completion.error, same(error));
    expect(completion.result, isNull);
  });

  test('a progress event without passes describes a one-pass generation', () {
    const event = ImageGenerationProgressEvent(
      phase: ImageGenerationPhase.sampling,
      step: 1,
      steps: 4,
      imageIndex: 0,
      imageCount: 1,
    );

    expect((event.pass, event.passCount), (0, 1));
  });

  test('the final event carries the result', () {
    expect(ImageGenerationFinalEvent(result).result, same(result));
  });
}
