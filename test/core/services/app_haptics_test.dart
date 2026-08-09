import 'package:flutter_test/flutter_test.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:localmind/core/services/app_haptics.dart';

void main() {
  test('suppresses vibration while haptic feedback is disabled', () async {
    var enabled = false;
    final calls = <HapticsType>[];
    final haptics = AppHaptics(
      () => enabled,
      vibrate: (type) async => calls.add(type),
    );

    await haptics.light();
    expect(calls, isEmpty);

    enabled = true;
    await haptics.medium();
    expect(calls, [HapticsType.medium]);
  });

  test('swallows platform vibration failures', () async {
    final haptics = AppHaptics(
      () => true,
      vibrate: (_) => Future<void>.error(StateError('unsupported')),
    );

    await expectLater(haptics.selection(), completes);
  });
}
