import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/chat/data/tools/calendar_service.dart';
import 'package:localmind/features/chat/data/tools/location_service.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';
import 'package:localmind/features/chat/providers/tooling_providers.dart';
import 'package:localmind/features/mcp/views/mcp_tools_screen.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapWithApp({required Widget child, List<dynamic>? overrides}) {
  return ProviderScope(
    overrides: [...?overrides?.cast()],
    child: ShadTheme(
      data: AppTheme.lightShadTheme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('McpToolsScreen Widget Tests', () {
    testWidgets('renders without throwing setState during build exception', (
      tester,
    ) async {
      final List<ToolDefinition> tools = [
        const ToolDefinition(
          name: 'get_current_weather',
          description: 'Get weather for location',
          inputSchema: {},
          providerType: ToolProviderType.mcp,
          providerRef: 'weather_server',
        ),
      ];

      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            availableToolsProvider.overrideWith((ref) => Future.value(tools)),
            settingsProvider.overrideWith(
              () => _TestSettingsNotifier(
                AppSettings(mcpEnabled: true, newChatMcpEnabled: true),
              ),
            ),
          ],
          child: const McpToolsScreen(),
        ),
      );

      // Verify no exceptions were thrown during first build/mount
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();

      expect(find.text('get_current_weather'), findsOneWidget);
      expect(find.text('Get weather for location'), findsOneWidget);
      expect(find.text('weather_server'), findsOneWidget);
      expect(find.text('MCP'), findsOneWidget);
    });

    testWidgets('displays disabled warning when mcpEnabled is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            settingsProvider.overrideWith(
              () => _TestSettingsNotifier(AppSettings(mcpEnabled: false)),
            ),
          ],
          child: const McpToolsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.mcp_disabled_warning), findsOneWidget);
    });

    testWidgets('displays empty state when tools list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            availableToolsProvider.overrideWith(
              (ref) => Future.value(const <ToolDefinition>[]),
            ),
            settingsProvider.overrideWith(
              () => _TestSettingsNotifier(
                AppSettings(mcpEnabled: true, newChatMcpEnabled: true),
              ),
            ),
          ],
          child: const McpToolsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.no_tools_registered), findsOneWidget);
    });

    testWidgets('displays error panel when availableToolsProvider fails', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            availableToolsProvider.overrideWith(
              (ref) => Future.error('Connection failed to MCP socket'),
            ),
            settingsProvider.overrideWith(
              () => _TestSettingsNotifier(
                AppSettings(mcpEnabled: true, newChatMcpEnabled: true),
              ),
            ),
          ],
          child: const McpToolsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Connection failed to MCP socket'), findsOneWidget);
    });
  });

  // Regression for issue #111: granting a permission after the screen was
  // unmounted crashed with "Using ref when a widget ... has been unmounted".
  group('McpToolsScreen permission toggles', () {
    Future<ProviderContainer> pumpUnmountableScreen(
      WidgetTester tester, {
      required Completer<bool> permission,
      required ValueNotifier<bool> showScreen,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          availableToolsProvider.overrideWith(
            (ref) => Future.value(const <ToolDefinition>[]),
          ),
          settingsProvider.overrideWith(
            () => _TestSettingsNotifier(AppSettings(mcpEnabled: true)),
          ),
          calendarServiceProvider.overrideWithValue(
            _FakeCalendarService(permission.future),
          ),
          locationServiceProvider.overrideWithValue(
            _FakeLocationService(permission.future),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrapWithApp(
            child: ValueListenableBuilder<bool>(
              valueListenable: showScreen,
              builder: (context, show, _) =>
                  show ? const McpToolsScreen() : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> tapToggle(WidgetTester tester, String label) async {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      );
      final toggle = find.descendant(
        of: row.first,
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
    }

    final l10n = lookupAppLocalizations(const Locale('en'));

    for (final (label, isEnabled) in [
      (l10n.location_access, (AppSettings s) => s.locationToolsEnabled),
      (l10n.calendar_access, (AppSettings s) => s.calendarToolsEnabled),
    ]) {
      testWidgets('$label grant after unmount enables the tool', (
        tester,
      ) async {
        final permission = Completer<bool>();
        final showScreen = ValueNotifier(true);
        addTearDown(showScreen.dispose);
        final container = await pumpUnmountableScreen(
          tester,
          permission: permission,
          showScreen: showScreen,
        );

        await tapToggle(tester, label);

        // The user leaves the screen while the OS prompt is still up.
        showScreen.value = false;
        await tester.pump();

        permission.complete(true);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(isEnabled(container.read(settingsProvider)), isTrue);
      });
    }
  });
}

class _TestSettingsNotifier extends SettingsNotifier {
  _TestSettingsNotifier(this._initial);
  final AppSettings _initial;

  @override
  AppSettings build() => _initial;
}

class _FakeCalendarService implements CalendarService {
  _FakeCalendarService(this._access);
  final Future<bool> _access;

  @override
  Future<bool> requestAccess() => _access;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocationService implements LocationService {
  _FakeLocationService(this._access);
  final Future<bool> _access;

  @override
  Future<bool> requestAccess() => _access;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
