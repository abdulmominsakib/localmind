import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/core/utils/locale_utils.dart';
import 'package:localmind/features/onboarding/screens/onboarding_language_screen.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Turkish locale is supported and loads translations', () {
    expect(
      AppLocalizations.supportedLocales.contains(const Locale('tr')),
      isTrue,
    );

    final l10n = lookupAppLocalizations(const Locale('tr'));
    expect(l10n.app_name, 'LocalMind');
    expect(l10n.cancel, 'İptal');
    expect(l10n.settings_language, 'Dil');
    expect(l10n.onboarding_choose_language, 'LocalMind dillerini keşfedin');
  });

  test('French locale is supported and loads translations', () {
    expect(
      AppLocalizations.supportedLocales.contains(const Locale('fr')),
      isTrue,
    );

    final l10n = lookupAppLocalizations(const Locale('fr'));
    expect(l10n.app_name, 'LocalMind');
    expect(l10n.cancel, 'Annuler');
    expect(l10n.settings_language, 'Langue');
    expect(
      l10n.onboarding_choose_language,
      'Découvrez les langues de LocalMind',
    );
  });

  testWidgets('onboarding switches the app to Polish and Vietnamese', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, child) {
            final locale = findSupportedLocale(
              ref.watch(
                settingsProvider.select((settings) => settings.localeCode),
              ),
              AppLocalizations.supportedLocales,
            );
            return ShadTheme(
              data: AppTheme.lightShadTheme,
              child: MaterialApp(
                locale: locale ?? const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const OnboardingLanguageScreen(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Polski'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).localeCode, 'pl');
    expect(find.text('Wybierz język'), findsOneWidget);

    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).localeCode, 'vi');
    expect(find.text('Chọn ngôn ngữ'), findsOneWidget);
  });
}
