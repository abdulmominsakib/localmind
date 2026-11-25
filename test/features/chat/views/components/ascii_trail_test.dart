import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/views/components/ascii_trail.dart';

void main() {
  group('asciiTrailFrame', () {
    test('processing fills toward the label as progress grows', () {
      final quarter = asciiTrailFrame(
        AsciiTrailKind.processing,
        20,
        ticks: 0,
        progress: 0.25,
      );
      final most = asciiTrailFrame(
        AsciiTrailKind.processing,
        20,
        ticks: 0,
        progress: 0.9,
      );
      expect(quarter, hasLength(20));
      expect(quarter, startsWith('====='));
      expect(quarter[5], '>');
      expect('='.allMatches(most).length, 18);
      expect(most, endsWith('>.'));
    });

    test('processing head blinks between frames', () {
      String head(int ticks) => asciiTrailFrame(
        AsciiTrailKind.processing,
        10,
        ticks: ticks,
        progress: 0.5,
      )[5];
      expect({head(0), head(1)}, {'>', '-'});
    });

    test('generating flows: frames change and only use the wave ramp', () {
      final a = asciiTrailFrame(AsciiTrailKind.generating, 30, ticks: 0);
      final b = asciiTrailFrame(AsciiTrailKind.generating, 30, ticks: 1);
      expect(a, isNot(b));
      expect(RegExp(r'^[ .:\-=+*]+$').hasMatch(a), isTrue);
    });

    test('kinds look different from each other', () {
      final frames = {
        for (final kind in AsciiTrailKind.values)
          asciiTrailFrame(kind, 30, ticks: 3, progress: 0.5),
      };
      expect(frames, hasLength(AsciiTrailKind.values.length));
    });

    test('no room gives an empty frame', () {
      expect(asciiTrailFrame(AsciiTrailKind.generating, 0, ticks: 5), '');
    });
  });
}
