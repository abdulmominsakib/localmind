import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../core/logger/app_logger.dart';

/// Double in dB-ish units (iOS) or 0..1-ish (Android) reported by the
/// speech_to_text plugin via `onSoundLevelChange`. Higher = louder.
typedef SoundLevelChange = void Function(double level);

class SttState {
  final bool isListening;
  final bool isAvailable;
  final String recognizedWords;
  final String? error;

  const SttState({
    this.isListening = false,
    this.isAvailable = false,
    this.recognizedWords = '',
    this.error,
  });

  SttState copyWith({
    bool? isListening,
    bool? isAvailable,
    String? recognizedWords,
    String? error,
    bool clearError = false,
  }) {
    return SttState(
      isListening: isListening ?? this.isListening,
      isAvailable: isAvailable ?? this.isAvailable,
      recognizedWords: recognizedWords ?? this.recognizedWords,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SttNotifier extends Notifier<SttState> {
  late SpeechToText _speech;
  bool _isInit = false;
  // Monotonically increasing counter; status callbacks from a previous
  // session cannot clobber state set by a newer one.
  int _session = 0;
  // Snapshot of the most recently issued session id. Set to -1 when no
  // listen() is in flight.
  int _activeSession = -1;

  @override
  SttState build() {
    _speech = SpeechToText();
    ref.onDispose(() {
      try {
        _speech.cancel();
      } catch (e) {
        Log.error('STT dispose/cancel error: $e');
      }
    });
    return const SttState();
  }

  Future<bool> initSpeech() async {
    if (_isInit) return state.isAvailable;
    try {
      final available = await _speech.initialize(
        onError: (val) {
          if (!ref.mounted) return;
          Log.error('STT error: ${val.errorMsg} - permanent: ${val.permanent}');
          state = state.copyWith(error: val.errorMsg, isListening: false);
        },
        onStatus: (val) {
          if (!ref.mounted) return;
          Log.debug('STT status: $val');
          // Only honour status updates from the active session; stale
          // callbacks from a previous listen() (or callbacks fired while
          // we've already stopped the current one) must not clobber state.
          if (_activeSession != _session) return;
          if (val == 'listening') {
            state = state.copyWith(isListening: true);
          } else if (val == 'notListening' || val == 'done') {
            state = state.copyWith(isListening: false);
          }
        },
      );
      if (!ref.mounted) return false;
      _isInit = true;
      state = state.copyWith(isAvailable: available);
      return available;
    } catch (e) {
      if (!ref.mounted) return false;
      Log.error('STT initialization failed: $e');
      state = state.copyWith(isAvailable: false, error: e.toString());
      return false;
    }
  }

  Future<void> startListening({
    required void Function(String) onResult,
    void Function(String)? onFinal,
    SoundLevelChange? onSoundLevelChange,
  }) async {
    final available = await initSpeech();
    if (!ref.mounted) return;
    if (!available) {
      state = state.copyWith(
        error: 'Speech recognition not available or permission denied',
      );
      return;
    }

    state = state.copyWith(
      isListening: true,
      recognizedWords: '',
      clearError: true,
    );
    _session++;
    _activeSession = _session;

    try {
      await _speech.listen(
        onResult: (result) {
          if (!ref.mounted) return;
          state = state.copyWith(recognizedWords: result.recognizedWords);
          onResult(result.recognizedWords);
          if (result.finalResult && onFinal != null) {
            onFinal(result.recognizedWords);
          }
        },
        onSoundLevelChange: (level) {
          // iOS reports negative dB (-2 quiet, 10 loud), Android ~0..1.
          final normalised = level <= 0
              ? ((level + 2) / 12).clamp(0.0, 1.0)
              : level.clamp(0.0, 1.0);
          onSoundLevelChange?.call(normalised);
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (e) {
      if (!ref.mounted) return;
      Log.error('STT listen error: $e');
      state = state.copyWith(isListening: false, error: e.toString());
    }
  }

  Future<void> stopListening() async {
    // Invalidate the current session so any in-flight status callbacks
    // are ignored.
    _session++;
    _activeSession = -1;
    try {
      await _speech.stop();
      if (!ref.mounted) return;
      state = state.copyWith(isListening: false);
    } catch (e) {
      Log.error('STT stop error: $e');
    }
  }

  Future<void> cancelListening() async {
    _session++;
    _activeSession = -1;
    try {
      await _speech.cancel();
      if (!ref.mounted) return;
      state = state.copyWith(isListening: false);
    } catch (e) {
      Log.error('STT cancel error: $e');
    }
  }
}

final sttProvider = NotifierProvider<SttNotifier, SttState>(() {
  return SttNotifier();
});
