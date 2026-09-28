import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';

void main() {
  test('sampling send flags and default system prompt round-trip', () {
    final settings = AppSettings(
      sendTemperature: false,
      sendTopP: false,
      defaultSystemPrompt: 'Be brief.',
    );

    final restored = AppSettings.fromMap(settings.toMap());

    expect(restored.sendTemperature, isFalse);
    expect(restored.sendTopP, isFalse);
    expect(restored.defaultSystemPrompt, 'Be brief.');
  });

  test('older saved settings default to sending both params', () {
    final restored = AppSettings.fromMap(const <String, dynamic>{});

    expect(restored.sendTemperature, isTrue);
    expect(restored.sendTopP, isTrue);
    expect(restored.defaultSystemPrompt, isEmpty);
  });
}
