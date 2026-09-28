import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/logger/app_logger.dart';
import '../utils/stt_error_messages.dart';

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
  SttNotifier({SpeechToText Function()? speechFactory})
    : _speechFactory = speechFactory ?? SpeechToText.new;

  /// Delay before re-listening after an `error_client`, giving the platform
  /// recognizer time to release the previous session.
  static const clientErrorRetryDelay = Duration(milliseconds: 300);

  final SpeechToText Function() _speechFactory;
  late SpeechToText _speech;
  bool _isInit = false;
  Future<bool>? _initialization;
  // Monotonically increasing counter; status callbacks from a previous
  // session cannot clobber state set by a newer one.
  int _session = 0;
  // Snapshot of the most recently issued session id. Set to -1 when no
  // listen() is in flight.
  int _activeSession = -1;
  // Re-issues the current listen() with the same callbacks. Null when no
  // listen is in flight.
  Future<void> Function()? _relisten;
  bool _retriedClientError = false;
  // Android: use the on-device recognizer instead of the default service.
  // Flipped after an `error_client`, which is what devices without Google
  // speech services (e.g. GrapheneOS) report for the default one (#100).
  bool _useOnDeviceRecognizer = false;
  bool _switchedRecognizerForRetry = false;

  @override
  SttState build() {
    _speech = _speechFactory();
    ref.onDispose(() {
      try {
        _speech.cancel();
      } catch (e) {
        Log.error('STT dispose/cancel error: $e');
      }
    });
    return const SttState();
  }

  Future<bool> initSpeech() {
    if (_isInit) return Future.value(state.isAvailable);
    return _initialization ??= _initializeSpeech();
  }

  Future<bool> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        onError: (val) {
          if (!ref.mounted) return;
          Log.error('STT error: ${val.errorMsg} - permanent: ${val.permanent}');
          if (val.errorMsg == 'error_client' && _retryAfterClientError()) {
            return;
          }
          if (_switchedRecognizerForRetry) {
            // The other recognizer didn't help either; go back to the
            // original one for the next attempt.
            _useOnDeviceRecognizer = !_useOnDeviceRecognizer;
            _switchedRecognizerForRetry = false;
          }
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
        options: [SpeechToText.androidNoBluetooth],
      );
      if (!ref.mounted) return false;
      // A denied permission must remain retryable after the user changes it
      // in Android Settings. Do not cache an unsuccessful initialization.
      _isInit = available;
      state = state.copyWith(isAvailable: available, clearError: available);
      return available;
    } catch (e) {
      if (!ref.mounted) return false;
      Log.error('STT initialization failed: $e');
      final noRecognizer =
          e is PlatformException && e.code == 'recognizerNotAvailable';
      state = state.copyWith(
        isAvailable: false,
        error: noRecognizer ? sttUnavailableCode : e.toString(),
      );
      return false;
    } finally {
      _initialization = null;
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
    _retriedClientError = false;
    _switchedRecognizerForRetry = false;
    _relisten = () => _listen(
      onResult: onResult,
      onFinal: onFinal,
      onSoundLevelChange: onSoundLevelChange,
    );
    await _relisten!();
  }

  Future<void> _listen({
    required void Function(String) onResult,
    void Function(String)? onFinal,
    SoundLevelChange? onSoundLevelChange,
  }) async {
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
          onDevice: _useOnDeviceRecognizer,
        ),
      );
    } catch (e) {
      if (!ref.mounted) return;
      Log.error('STT listen error: $e');
      state = state.copyWith(isListening: false, error: e.toString());
    }
  }

  /// Retries the current listen once after an `error_client`. On Android the
  /// retry switches between the default and the on-device recognizer.
  /// Returns false when the error should be surfaced instead.
  bool _retryAfterClientError() {
    final relisten = _relisten;
    if (relisten == null || _retriedClientError) return false;
    _retriedClientError = true;
    if (defaultTargetPlatform == TargetPlatform.android) {
      _useOnDeviceRecognizer = !_useOnDeviceRecognizer;
      _switchedRecognizerForRetry = true;
    }
    Log.warning(
      'STT error_client, retrying once '
      '(onDevice: $_useOnDeviceRecognizer)',
    );
    final session = _session;
    unawaited(() async {
      try {
        await _speech.cancel();
      } catch (e) {
        Log.error('STT cancel before retry failed: $e');
      }
      await Future<void>.delayed(clientErrorRetryDelay);
      // Bail if the caller stopped or restarted listening meanwhile.
      if (!ref.mounted || _session != session || _relisten != relisten) {
        return;
      }
      await relisten();
    }());
    return true;
  }

  Future<void> stopListening() async {
    // Invalidate the current session so any in-flight status callbacks
    // are ignored.
    _relisten = null;
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
    _relisten = null;
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
