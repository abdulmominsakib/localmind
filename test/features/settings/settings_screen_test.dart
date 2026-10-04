import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/personas/data/models/persona.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/views/settings_screen.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoServers extends ServersNotifier {
  @override
  Future<List<Server>> build() async => const [];
}

class _NoPersonas extends PersonasNotifier {
  @override
  Future<List<Persona>> build() async => const [];
}

Future<ProviderContainer> _pump(WidgetTester tester) async {
  // The test font draws every glyph a full em wide; give rows room.
  tester.view.physicalSize = const Size(700, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      packageInfoProvider.overrideWith(
        (ref) async => PackageInfo(
          appName: 'LocalMind',
          packageName: 'test',
          version: '1.0.0',
          buildNumber: '1',
        ),
      ),
      serversProvider.overrideWith(_NoServers.new),
      personasNotifierProvider.overrideWith(_NoPersonas.new),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShadTheme(
        data: AppTheme.lightShadTheme,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SettingsViews()),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  testWidgets('search keeps matching rows and hides the rest', (tester) async {
    await _pump(tester);
    expect(find.text('Haptic Feedback'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('settings_search')),
      'haptic',
    );
    await tester.pump();
    expect(find.text('Haptic Feedback'), findsOneWidget);
    expect(find.text('Streaming Responses'), findsNothing);
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('search finds options one level down', (tester) async {
    await _pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('settings_search')),
      'temperature',
    );
    await tester.pump();
    expect(find.text('More chat options'), findsOneWidget);
    expect(find.text('Haptic Feedback'), findsNothing);

    await tester.tap(find.text('More chat options'));
    await tester.pumpAndSettle();
    expect(find.text('Send temperature'), findsOneWidget);
  });

  testWidgets('the theme control switches the app theme', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.text('Dark').first);
    await tester.pump();
    expect(container.read(themeModeProvider), AppThemeType.dark);
  });

  testWidgets('switch rows toggle from anywhere on the row', (tester) async {
    final container = await _pump(tester);
    final before = container.read(settingsProvider).hapticFeedbackEnabled;
    await tester.tap(find.text('Haptic Feedback'));
    await tester.pump();
    expect(container.read(settingsProvider).hapticFeedbackEnabled, !before);
  });
}
