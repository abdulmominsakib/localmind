import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/settings/data/models/app_settings.dart';
import '../models/enums.dart';
import '../../features/tts/data/kitten_tts_model.dart';
import 'storage_providers.dart';
import '../theme/app_theme.dart';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeType>(() {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends Notifier<AppThemeType> {
  @override
  AppThemeType build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedMode = prefs.getInt('themeMode');
    if (savedMode != null &&
        savedMode >= 0 &&
        savedMode < AppThemeType.values.length) {
      return AppThemeType.values[savedMode];
    }
    return AppThemeType.system;
  }

  void setThemeMode(AppThemeType mode) {
    final prefs = ref.read(sharedPreferencesProvider);
    state = mode;
    prefs.setInt('themeMode', mode.index);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedJson = prefs.getString('appSettings');
    if (savedJson != null) {
      try {
        return AppSettings.fromJson(savedJson);
      } catch (_) {}
    }
    return AppSettings();
  }

  Future<void> updateSettings(AppSettings appSettings) async {
    final prefs = ref.read(sharedPreferencesProvider);
    state = appSettings;
    await prefs.setString('appSettings', appSettings.toJson());
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
  void setNewChatMcpEnabled(bool value) =>
      _update(state.copyWith(newChatMcpEnabled: value));
  void setCodeThemeDark(SyntaxThemeName value) =>
      _update(state.copyWith(codeThemeDark: value));
  void setCodeThemeLight(SyntaxThemeName value) =>
      _update(state.copyWith(codeThemeLight: value));
  void setPreferredBackend(LiteLmBackendType value) =>
      _update(state.copyWith(preferredBackend: value));
  void setTtsEngine(TtsEngine value) =>
      _update(state.copyWith(ttsEngine: value));
  void setKittenTtsVoice(KittenTtsVoice value) =>
      _update(state.copyWith(kittenTtsVoice: value));
  void setKittenTtsSpeed(double value) =>
      _update(state.copyWith(kittenTtsSpeed: value));
  void setKittenTtsModelVariant(KittenTtsModelVariant value) =>
      _update(state.copyWith(kittenTtsModelVariant: value));

  Future<void> _update(AppSettings updated) async {
    state = updated;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('appSettings', updated.toJson());
  }

  Future<void> resetToDefaults() async {
    state = AppSettings();
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('appSettings', state.toJson());
  }
}
