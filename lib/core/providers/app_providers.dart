import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'storage_providers.dart';

import '../theme/app_theme.dart';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeType>(() {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends Notifier<AppThemeType> {
  @override
  AppThemeType build() {
    final boxes = ref.watch(hiveBoxesProvider);
    final savedMode = boxes.settings.get('themeMode');
    if (savedMode is int &&
        savedMode >= 0 &&
        savedMode < AppThemeType.values.length) {
      return AppThemeType.values[savedMode];
    }
    return AppThemeType.system;
  }

  void setThemeMode(AppThemeType mode) {
    final boxes = ref.read(hiveBoxesProvider);
    state = mode;
    boxes.settings.put('themeMode', mode.index);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final boxes = ref.watch(hiveBoxesProvider);
    final saved = boxes.settings.get('appSettings');
    if (saved is AppSettings) {
      return saved;
    }
    return AppSettings();
  }

  Future<void> updateSettings(AppSettings appSettings) async {
    final boxes = ref.read(hiveBoxesProvider);
    state = appSettings;
    await boxes.settings.put('appSettings', appSettings);
  }

  Future<void> resetToDefaults() async {
    final boxes = ref.read(hiveBoxesProvider);
    state = AppSettings();
    await boxes.settings.put('appSettings', state);
  }
}
