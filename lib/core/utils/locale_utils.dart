import 'package:flutter/material.dart';

Locale? parseLocaleCode(String? localeCode) {
  if (localeCode == null) {
    return null;
  }

  final normalized = localeCode.trim().replaceAll('-', '_');
  if (normalized.isEmpty) {
    return null;
  }

  final parts = normalized.split('_');
  final languageCode = parts.first.toLowerCase();

  if (parts.length == 1) {
    return Locale(languageCode);
  }

  final secondPart = parts[1];
  final scriptCode = secondPart.length == 4 ? secondPart : null;
  final countryCode = scriptCode == null ? secondPart.toUpperCase() : null;
  final resolvedCountryCode = parts.length > 2
      ? parts[2].toUpperCase()
      : countryCode;

  return Locale.fromSubtags(
    languageCode: languageCode,
    scriptCode: scriptCode,
    countryCode: resolvedCountryCode,
  );
}

Locale? findSupportedLocale(
  String? localeCode,
  Iterable<Locale> supportedLocales,
) {
  final parsedLocale = parseLocaleCode(localeCode);
  if (parsedLocale == null) {
    return null;
  }

  for (final locale in supportedLocales) {
    if (_sameLocale(locale, parsedLocale)) {
      return locale;
    }
  }

  for (final locale in supportedLocales) {
    if (locale.languageCode == parsedLocale.languageCode) {
      return locale;
    }
  }

  return null;
}

bool _sameLocale(Locale a, Locale b) {
  return a.languageCode == b.languageCode &&
      (a.scriptCode ?? '') == (b.scriptCode ?? '') &&
      (a.countryCode ?? '') == (b.countryCode ?? '');
}
