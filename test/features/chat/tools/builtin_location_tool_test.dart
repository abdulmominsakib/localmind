import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/tools/builtin_tool_provider.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';

void main() {
  group('Location built-in tool gating', () {
    test('location tool is off by default', () async {
      final provider = BuiltInToolProvider();
      final tools = await provider.listTools();
      expect(
        tools.any((t) => t.name == 'location.get_current_location'),
        isFalse,
      );
    });

    test('location tool is listed when enabled', () async {
      final provider = BuiltInToolProvider(locationToolsEnabled: true);
      final tools = await provider.listTools();
      expect(
        tools.any((t) => t.name == 'location.get_current_location'),
        isTrue,
      );
    });

    test('calendar flag alone does not enable location', () async {
      final provider = BuiltInToolProvider(calendarToolsEnabled: true);
      final tools = await provider.listTools();
      expect(
        tools.any((t) => t.name == 'location.get_current_location'),
        isFalse,
      );
      expect(tools.any((t) => t.name.startsWith('calendar.')), isTrue);
    });

    test(
      'executing location tool without permission fails gracefully',
      () async {
        final provider = BuiltInToolProvider(locationToolsEnabled: true);
        final result = await provider.execute(
          'location.get_current_location',
          {},
        );
        expect(result.success, isFalse);
        expect(result.error, isNotNull);
      },
    );
  });

  group('AppSettings locationToolsEnabled', () {
    test('defaults to false', () {
      expect(AppSettings().locationToolsEnabled, isFalse);
    });

    test('survives toMap/fromMap round-trip', () {
      final settings = AppSettings().copyWith(locationToolsEnabled: true);
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.locationToolsEnabled, isTrue);
      expect(
        AppSettings.fromMap(AppSettings().toMap()).locationToolsEnabled,
        isFalse,
      );
    });
  });
}
