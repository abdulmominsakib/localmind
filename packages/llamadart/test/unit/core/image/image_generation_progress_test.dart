import 'package:test/test.dart';

import 'package:llamadart/src/core/image/image_generation_events.dart';
import 'package:llamadart/src/core/image/image_generation_progress.dart';

String _label(ImageGenerationProgressEvent event) =>
    '${event.phase.name} ${event.step}/${event.steps} '
    '#${event.imageIndex}/${event.imageCount}';

List<String> _feed(
  ImageGenerationProgressTracker tracker,
  List<(int, int)> callbacks,
) => [
  for (final (step, total) in callbacks)
    ...tracker.onNativeProgress(step, total).map(_label),
];

void main() {
  test('starts in encodingPrompt', () {
    final tracker = ImageGenerationProgressTracker(steps: 4, imageCount: 1);

    expect(_label(tracker.start()), 'encodingPrompt 0/4 #0/1');
  });

  test('labels an eagerly loaded single image as sampling, then decoding', () {
    final tracker = ImageGenerationProgressTracker(steps: 1, imageCount: 1);

    expect(_feed(tracker, [(0, 1), (1, 1)]), [
      'sampling 0/1 #0/1',
      'sampling 1/1 #0/1',
      'decoding 0/1 #0/1',
    ]);
  });

  test('advances the image index per sampling pass', () {
    final tracker = ImageGenerationProgressTracker(steps: 2, imageCount: 2);

    expect(_feed(tracker, [(0, 2), (1, 2), (2, 2), (0, 2), (1, 2), (2, 2)]), [
      'sampling 0/2 #0/2',
      'sampling 1/2 #0/2',
      'sampling 2/2 #0/2',
      'sampling 0/2 #1/2',
      'sampling 1/2 #1/2',
      'sampling 2/2 #1/2',
      'decoding 0/2 #1/2',
    ]);
  });

  test('labels lazy tensor loads as loading and tiled decodes as decoding '
      '(first SDXS run with lazy loading)', () {
    final tracker = ImageGenerationProgressTracker(steps: 1, imageCount: 1);

    expect(
      _feed(tracker, [
        (4, 196),
        (196, 196),
        (0, 1),
        (0, 280),
        (280, 280),
        (1, 1),
        (0, 67),
        (67, 67),
      ]),
      [
        'loading 4/196 #0/1',
        'loading 196/196 #0/1',
        'sampling 0/1 #0/1',
        'loading 0/280 #0/1',
        'loading 280/280 #0/1',
        'sampling 1/1 #0/1',
        'decoding 0/1 #0/1',
        'decoding 0/67 #0/1',
        'decoding 67/67 #0/1',
      ],
    );
  });

  test('a callback after every image is sampled is decoding, even with the '
      'step total', () {
    final tracker = ImageGenerationProgressTracker(steps: 4, imageCount: 1);
    _feed(tracker, [(0, 4), (1, 4), (2, 4), (3, 4), (4, 4)]);

    expect(_feed(tracker, [(2, 4)]), ['decoding 2/4 #0/1']);
  });

  test('a hires fix labels its second pass by the total it reports, then '
      'decodes after the last image\'s second pass', () {
    final tracker = ImageGenerationProgressTracker(
      steps: 2,
      imageCount: 2,
      passCount: 2,
    );
    String label(ImageGenerationProgressEvent event) =>
        '${_label(event)} pass ${event.pass}/${event.passCount}';

    expect(label(tracker.start()), 'encodingPrompt 0/2 #0/2 pass 0/2');
    expect(
      [
        for (final (step, total) in [
          (0, 2),
          (2, 2),
          (0, 2),
          (2, 2),
          (0, 3),
          (1, 3),
          (3, 3),
          (0, 3),
          (3, 3),
          (0, 4),
        ])
          ...tracker.onNativeProgress(step, total).map(label),
      ],
      [
        'sampling 0/2 #0/2 pass 0/2',
        'sampling 2/2 #0/2 pass 0/2',
        'sampling 0/2 #1/2 pass 0/2',
        'sampling 2/2 #1/2 pass 0/2',
        'sampling 0/3 #0/2 pass 1/2',
        'sampling 1/3 #0/2 pass 1/2',
        'sampling 3/3 #0/2 pass 1/2',
        'sampling 0/3 #1/2 pass 1/2',
        'sampling 3/3 #1/2 pass 1/2',
        'decoding 0/2 #1/2 pass 1/2',
        'decoding 0/4 #1/2 pass 1/2',
      ],
    );
  });

  test('a second-pass callback with another total is not sampling', () {
    final tracker = ImageGenerationProgressTracker(
      steps: 1,
      imageCount: 1,
      passCount: 2,
    );
    _feed(tracker, [(0, 1), (1, 1), (0, 5)]);

    expect(_feed(tracker, [(7, 196), (5, 5)]), [
      'loading 7/196 #0/1',
      'sampling 5/5 #0/1',
      'decoding 0/1 #0/1',
    ]);
  });

  test('one pass reports pass 0 of 1', () {
    final events = ImageGenerationProgressTracker(
      steps: 1,
      imageCount: 1,
    ).onNativeProgress(1, 1);
    expect([for (final e in events) (e.pass, e.passCount)], [(0, 1), (0, 1)]);
  });
}
