import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../data/kitten_tts_service.dart';
import '../data/tts_service.dart';

/// Provider for the system TTS service (flutter_tts).
final systemTtsProvider = Provider<TtsService>((ref) {
  return TtsService();
});

/// Provider for the KittenTTS neural TTS service.
///
/// This is a lazy-initialized provider. The service copies model files
/// from assets to the filesystem on first use.
final kittenTtsServiceProvider = Provider<KittenTtsService>((ref) {
  return KittenTtsService();
});

/// Notifier that manages the currently active TTS engine state.
///
/// Delegates to either [TtsService] (system) or [KittenTtsService]
/// based on the user's settings preference.
final unifiedTtsProvider =
    NotifierProvider<UnifiedTtsNotifier, UnifiedTtsState>(() {
  return UnifiedTtsNotifier();
    });

class UnifiedTtsState {
  final bool isSpeaking;
  final bool isInitializing;
  final String? error;
  final TtsEngine activeEngine;

  const UnifiedTtsState({
    this.isSpeaking = false,
    this.isInitializing = false,
    this.error,
    this.activeEngine = TtsEngine.system,
  });

  UnifiedTtsState copyWith({
    bool? isSpeaking,
    bool? isInitializing,
    String? error,
    TtsEngine? activeEngine,
  }) {
    return UnifiedTtsState(
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isInitializing: isInitializing ?? this.isInitializing,
      error: error,
      activeEngine: activeEngine ?? this.activeEngine,
    );
  }
}

class UnifiedTtsNotifier extends Notifier<UnifiedTtsState> {
  TtsService? _systemTts;
  KittenTtsService? _kittenTts;

  @override
  UnifiedTtsState build() {
    final settings = ref.watch(settingsProvider);
    return UnifiedTtsState(activeEngine: settings.ttsEngine);
  }

  TtsService get _systemTtsInstance {
    _systemTts ??= ref.read(systemTtsProvider);
    return _systemTts!;
  }

  KittenTtsService get _kittenTtsInstance {
    _kittenTts ??= ref.read(kittenTtsServiceProvider);
    return _kittenTts!;
  }

  /// Speak the given text using the currently selected TTS engine.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;

    final settings = ref.read(settingsProvider);
    final engine = settings.ttsEngine;

    state = state.copyWith(
      isSpeaking: true,
      isInitializing: engine == TtsEngine.kitten,
      error: null,
    );

    try {
      if (engine == TtsEngine.kitten) {
        final variant = settings.kittenTtsModelVariant;
        await _kittenTtsInstance.initialize(variant: variant);
        await _kittenTtsInstance.speak(
          text,
          voice: settings.kittenTtsVoice,
          speed: settings.kittenTtsSpeed,
        );
      } else {
        await _systemTtsInstance.speak(text);
      }
    } catch (e) {
      state = state.copyWith(
        isSpeaking: false,
        isInitializing: false,
        error: 'TTS error: ${e.toString()}',
      );
    } finally {
      state = state.copyWith(
        isSpeaking: false,
        isInitializing: false,
      );
    }
  }

  /// Stop any ongoing speech.
  Future<void> stop() async {
    final settings = ref.read(settingsProvider);
    if (settings.ttsEngine == TtsEngine.kitten) {
      await _kittenTtsInstance.stop();
    } else {
      await _systemTtsInstance.stop();
    }
    state = state.copyWith(isSpeaking: false);
  }

  /// Pause ongoing speech.
  Future<void> pause() async {
    final settings = ref.read(settingsProvider);
    if (settings.ttsEngine == TtsEngine.kitten) {
      await _kittenTtsInstance.pause();
    } else {
      await _systemTtsInstance.pause();
    }
    state = state.copyWith(isSpeaking: false);
  }

  /// Dispose all TTS resources.
  Future<void> dispose() async {
    try {
      await _kittenTtsInstance.dispose();
    } catch (_) {}
    try {
      await _systemTtsInstance.dispose();
    } catch (_) {}
  }

  /// Check if any TTS engine is currently speaking.
  bool get isSpeaking {
    final settings = ref.read(settingsProvider);
    if (settings.ttsEngine == TtsEngine.kitten) {
      return _kittenTtsInstance.isSpeaking;
    }
    return _systemTtsInstance.isSpeaking;
  }
}
