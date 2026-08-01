import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/l10n/app_localizations.dart';

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
    expect(l10n.onboarding_choose_language, 'Découvrez les langues de LocalMind');
  });
}
