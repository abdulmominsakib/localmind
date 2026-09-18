import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/tools/builtin_tool_provider.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';

void main() {
  group('SMS built-in tool gating', () {
    test('sms tool is off by default', () async {
      final provider = BuiltInToolProvider();
      final tools = await provider.listTools();
      expect(tools.any((t) => t.name == 'sms.query_messages'), isFalse);
    });

    test('sms tool is listed when enabled', () async {
      final provider = BuiltInToolProvider(smsToolsEnabled: true);
      final tools = await provider.listTools();
      expect(tools.any((t) => t.name == 'sms.query_messages'), isTrue);
    });

    test('calendar/location flags alone do not enable sms', () async {
      final provider = BuiltInToolProvider(
        calendarToolsEnabled: true,
        locationToolsEnabled: true,
      );
      final tools = await provider.listTools();
      expect(tools.any((t) => t.name == 'sms.query_messages'), isFalse);
      expect(tools.any((t) => t.name.startsWith('calendar.')), isTrue);
      expect(
        tools.any((t) => t.name == 'location.get_current_location'),
        isTrue,
      );
    });

    test('executing sms tool without permission fails gracefully', () async {
      final provider = BuiltInToolProvider(smsToolsEnabled: true);
      final result = await provider.execute('sms.query_messages', {});
      expect(result.success, isFalse);
      expect(result.error, isNotNull);
    });
  });

  group('AppSettings smsToolsEnabled', () {
    test('defaults to false', () {
      expect(AppSettings().smsToolsEnabled, isFalse);
    });

    test('survives toMap/fromMap round-trip', () {
      final settings = AppSettings().copyWith(smsToolsEnabled: true);
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.smsToolsEnabled, isTrue);
      expect(
        AppSettings.fromMap(AppSettings().toMap()).smsToolsEnabled,
        isFalse,
      );
    });
  });
}
