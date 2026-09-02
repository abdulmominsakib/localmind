import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/chat/views/components/notification_permission_banner.dart';
import 'package:localmind/features/on_device/data/notification_permission_service.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotificationPermissionService
    implements NotificationPermissionService {
  _FakeNotificationPermissionService({this.granted = false});

  final bool granted;
  bool requestCalled = false;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isPermissionGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    requestCalled = true;
    return true;
  }
}

class _TestSettingsNotifier extends SettingsNotifier {
  _TestSettingsNotifier(this._initial);
  final AppSettings _initial;

  @override
  AppSettings build() => _initial;
}

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

  group('NotificationPermissionBanner Widget Tests', () {
    testWidgets(
      'mounts cleanly and displays banner when permission not granted',
      (tester) async {
        final fakeService = _FakeNotificationPermissionService(granted: false);

        await tester.pumpWidget(
          _wrapWithApp(
            overrides: [
              notificationPermissionServiceProvider.overrideWithValue(
                fakeService,
              ),
              settingsProvider.overrideWith(
                () => _TestSettingsNotifier(
                  AppSettings(hasAskedForNotifications: false),
                ),
              ),
            ],
            child: const NotificationPermissionBanner(),
          ),
        );

        // Verify no exception on first frame / mount
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(find.text(l10n.enable_notifications), findsOneWidget);
      },
    );

    testWidgets('does not show banner when user already asked', (tester) async {
      final fakeService = _FakeNotificationPermissionService(granted: false);

      await tester.pumpWidget(
        _wrapWithApp(
          overrides: [
            notificationPermissionServiceProvider.overrideWithValue(
              fakeService,
            ),
            settingsProvider.overrideWith(
              () => _TestSettingsNotifier(
                AppSettings(hasAskedForNotifications: true),
              ),
            ),
          ],
          child: const NotificationPermissionBanner(),
        ),
      );

      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.enable_notifications), findsNothing);
    });
  });
}
