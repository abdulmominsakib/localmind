import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/utils/locale_utils.dart';
import 'package:localmind/l10n/app_localizations.dart';

void main() {
  group('parseLocaleCode', () {
    test('parses language only locales', () {
      expect(parseLocaleCode('zh'), const Locale('zh'));
    });

    test('parses locales with country codes', () {
      expect(parseLocaleCode('zh_TW'), const Locale('zh', 'TW'));
      expect(parseLocaleCode('zh-TW'), const Locale('zh', 'TW'));
    });
  });

  group('findSupportedLocale', () {
    test('matches Traditional Chinese exactly', () {
      expect(
        findSupportedLocale('zh_TW', AppLocalizations.supportedLocales),
        const Locale('zh', 'TW'),
      );
    });

    test('falls back to language-only locale when region is unsupported', () {
      expect(
        findSupportedLocale('zh_HK', AppLocalizations.supportedLocales),
        const Locale('zh'),
      );
    });
  });
}
