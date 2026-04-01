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

  void setTemperature(double value) =>
      _update(state.copyWith(temperature: value));
  void setTopP(double value) => _update(state.copyWith(topP: value));
  void setMaxTokens(int value) => _update(state.copyWith(maxTokens: value));
  void setContextLength(int value) =>
      _update(state.copyWith(contextLength: value));
  void setFontSize(double value) => _update(state.copyWith(fontSize: value));
  void setShowSystemMessages(bool value) =>
      _update(state.copyWith(showSystemMessages: value));
  void setHapticFeedback(bool value) =>
      _update(state.copyWith(hapticFeedbackEnabled: value));
  void setSendOnEnter(bool value) =>
      _update(state.copyWith(sendOnEnter: value));
  void setDefaultServer(String? id) =>
      _update(state.copyWith(defaultServerId: id));
  void setShowDataIndicator(bool value) =>
      _update(state.copyWith(showDataIndicator: value));
  void setAutoGenerateTitle(bool value) =>
      _update(state.copyWith(autoGenerateTitle: value));
  void setStreamingEnabled(bool value) =>
      _update(state.copyWith(streamingEnabled: value));
  void setDefaultPersona(String? id) =>
      _update(state.copyWith(defaultPersonaId: id));
  void setHasCompletedOnboarding(bool value) =>
      _update(state.copyWith(hasCompletedOnboarding: value));
  void setMcpEnabled(bool value) => _update(state.copyWith(mcpEnabled: value));
  void setCodeTheme(SyntaxThemeName value) =>
      _update(state.copyWith(codeTheme: value));

  Future<void> _update(AppSettings updated) async {
    state = updated;
    final boxes = ref.read(hiveBoxesProvider);
    await boxes.settings.put('appSettings', updated);
  }

  Future<void> resetToDefaults() async {
    state = AppSettings();
    final boxes = ref.read(hiveBoxesProvider);
    await boxes.settings.put('appSettings', state);
  }
}
