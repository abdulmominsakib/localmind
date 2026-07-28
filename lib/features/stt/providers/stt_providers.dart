import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../core/logger/app_logger.dart';

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
          Log.error('STT error: ${val.errorMsg} - permanent: ${val.permanent}');
          state = state.copyWith(error: val.errorMsg, isListening: false);
        },
        onStatus: (val) {
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
      _isInit = true;
      state = state.copyWith(isAvailable: available);
      return available;
    } catch (e) {
      Log.error('STT initialization failed: $e');
      state = state.copyWith(isAvailable: false, error: e.toString());
      return false;
    }
  }

  Future<void> startListening({
    required void Function(String) onResult,
    void Function(String)? onFinal,
  }) async {
    final available = await initSpeech();
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
          state = state.copyWith(recognizedWords: result.recognizedWords);
          onResult(result.recognizedWords);
          if (result.finalResult && onFinal != null) {
            onFinal(result.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (e) {
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
      state = state.copyWith(isListening: false);
    } catch (e) {
      Log.error('STT cancel error: $e');
    }
  }
}

final sttProvider = NotifierProvider<SttNotifier, SttState>(() {
  return SttNotifier();
});
