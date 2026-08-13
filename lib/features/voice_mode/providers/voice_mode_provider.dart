import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../../../services/voice_feedback_service.dart';
import '../../chat/providers/chat_providers.dart';
import '../../stt/providers/stt_providers.dart';
import '../../tts/providers/tts_providers.dart';

/// The phase of the voice-to-voice conversation loop.
enum VoiceModePhase {
  /// Overlay is open but idle — waiting for the user to start.
  idle,

  /// Actively listening for user speech via STT.
  listening,

  /// User speech captured; waiting for LLM response.
  processing,

  /// LLM response complete; TTS is speaking.
  speaking,

  /// An error occurred in one of the phases.
  error,
}

class VoiceModeState {
  final bool isActive;
  final VoiceModePhase phase;
  final String transcript;
  final String response;
  final bool autoListen;
  final bool isMuted;
  final String? error;

  /// Live microphone input level in 0..1, set from the STT
  /// `onSoundLevelChange` callback. 0 when not listening.
  final double micLevel;

  const VoiceModeState({
    this.isActive = false,
    this.phase = VoiceModePhase.idle,
    this.transcript = '',
    this.response = '',
    this.autoListen = true,
    this.isMuted = false,
    this.error,
    this.micLevel = 0,
  });

  VoiceModeState copyWith({
    bool? isActive,
    VoiceModePhase? phase,
    String? transcript,
    String? response,
    bool? autoListen,
    bool? isMuted,
    String? error,
    bool clearError = false,
    double? micLevel,
  }) {
    return VoiceModeState(
      isActive: isActive ?? this.isActive,
      phase: phase ?? this.phase,
      transcript: transcript ?? this.transcript,
      response: response ?? this.response,
      autoListen: autoListen ?? this.autoListen,
      isMuted: isMuted ?? this.isMuted,
      error: clearError ? null : (error ?? this.error),
      micLevel: micLevel ?? this.micLevel,
    );
  }
}

final voiceModeProvider = NotifierProvider<VoiceModeNotifier, VoiceModeState>(
  () {
    return VoiceModeNotifier();
  },
);

class VoiceModeNotifier extends Notifier<VoiceModeState> {
  /// Tracks whether we are currently orchestrating a voice session so
  /// listeners don't fire after the session has been torn down.
  bool _active = false;
  bool _isSendingTranscript = false;

  /// Whether the "generating" feedback cue has already fired for the
  /// current streamed response. Reset on session start; consumed once
  /// in `_handleStreamingComplete` so haptic only fires on the first
  /// chunk arrival, not on every token.
  bool _generatingFired = false;

  @override
  VoiceModeState build() {
    // Listen to chat streaming state changes.
    ref.listen<bool>(
      isStreamingProvider,
      (previous, next) => _onStreamingChanged(previous ?? false, next),
    );

    // Listen to TTS speaking state changes.
    ref.listen<TtsState>(
      ttsProvider,
      (previous, next) => _onTtsStateChanged(previous, next),
    );

    // A server or genuinely loaded model can become available while the voice
    // overlay is open. Resume automatically instead of leaving the user on a
    // stale selection error.
    ref.listen<ActiveChatTarget>(activeChatTargetProvider, (previous, next) {
      final waitingForTarget =
          state.phase == VoiceModePhase.error &&
          (state.error == modelSelectionRequiredMessage ||
              state.error == 'No server connected');
      if (_active && waitingForTarget && next.isReady) {
        unawaited(startListening());
      }
    });

    // Listen to STT errors and show them directly on the voice screen.
    ref.listen<String?>(sttProvider.select((s) => s.error), (previous, next) {
      if (!_active || next == null) return;
      state = state.copyWith(
        phase: VoiceModePhase.error,
        error: _mapSttError(next),
      );
      ref.read(voiceFeedbackProvider).playDisconnected();
    });

    return const VoiceModeState();
  }

  // ──────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────

  /// Begin the voice mode session. Called when the overlay opens.
  void startSession() {
    _active = true;
    _generatingFired = false;
    state = const VoiceModeState(isActive: true, phase: VoiceModePhase.idle);
    if (!_ensureChatTarget()) return;
    ref.read(voiceFeedbackProvider).playConnected();
    // Auto-start listening.
    startListening();
  }

  /// Start listening for user speech.
  Future<void> startListening() async {
    if (!_active) return;
    if (!_ensureChatTarget()) return;

    _isSendingTranscript = false;
    state = state.copyWith(
      isActive: true,
      phase: VoiceModePhase.listening,
      transcript: '',
      response: '',
      micLevel: 0,
      clearError: true,
    );

    ref.read(voiceFeedbackProvider).playListening();

    final stt = ref.read(sttProvider.notifier);
    await stt.startListening(
      onResult: (words) {
        if (!_active) return;
        if (words.isNotEmpty) {
          state = state.copyWith(transcript: words);
        }
      },
      onFinal: (finalWords) async {
        if (!_active) return;
        if (!state.autoListen) return;
        if (_isSendingTranscript) return;
        final text = finalWords.trim().isNotEmpty
            ? finalWords
            : state.transcript;
        if (text.trim().isEmpty) return;
        _isSendingTranscript = true;
        await stopListeningAndSend();
      },
      onSoundLevelChange: (level) {
        if (!_active) return;
        // Skip the rebuild when the value hasn't materially changed
        // (riverpod notifies listeners on every distinct copyWith).
        if ((state.micLevel - level).abs() < 0.01) return;
        state = state.copyWith(micLevel: level);
      },
    );
  }

  /// Stop listening and send the captured transcript to the LLM.
  Future<void> stopListeningAndSend() async {
    if (!_active) return;

    final stt = ref.read(sttProvider.notifier);
    await stt.stopListening();

    final transcript = state.transcript.trim();
    if (transcript.isEmpty) {
      // Nothing was recognized — show error state directly on screen.
      state = state.copyWith(
        phase: VoiceModePhase.error,
        error: 'No speech recognized. Tap to try again.',
      );
      return;
    }

    if (!_ensureChatTarget()) return;

    // Reset the mic level so the waveform visualizer doesn't keep
    // dancing on a stale value once we leave the listening phase.
    state = state.copyWith(
      phase: VoiceModePhase.processing,
      response: '',
      micLevel: 0,
    );

    // Send the transcript as a regular chat message. The streaming
    // listener will handle the transition to speaking phase.
    try {
      await ref.read(chatProvider.notifier).sendMessage(transcript);
    } catch (e) {
      Log.error('Voice mode send error: $e');
      state = state.copyWith(phase: VoiceModePhase.error, error: e.toString());
    }
  }

  /// Toggle auto-listen after TTS completes.
  void toggleAutoListen() {
    state = state.copyWith(autoListen: !state.autoListen);
  }

  /// Toggle mute (pause listening without ending session).
  void toggleMute() {
    state = state.copyWith(isMuted: !state.isMuted);
  }

  /// End the entire voice session and reset everything.
  Future<void> endSession() async {
    _active = false;
    _isSendingTranscript = false;
    _generatingFired = false;

    ref.read(voiceFeedbackProvider).playDisconnected();

    // Stop STT if still listening.
    try {
      final stt = ref.read(sttProvider.notifier);
      await stt.cancelListening();
    } catch (e) {
      Log.error('Voice mode STT cancel error: $e');
    }

    // Stop TTS if still speaking.
    try {
      final tts = ref.read(ttsProvider.notifier);
      await tts.stop();
    } catch (e) {
      Log.error('Voice mode TTS stop error: $e');
    }

    state = const VoiceModeState();
  }

  /// Manually interrupt speaking and re-listen.
  Future<void> interrupt() async {
    if (!_active) return;
    try {
      final tts = ref.read(ttsProvider.notifier);
      await tts.stop();
    } catch (_) {}

    if (state.autoListen) {
      startListening();
    } else {
      state = state.copyWith(phase: VoiceModePhase.idle);
    }
  }

  // ──────────────────────────────────────────────────────
  // Internal listeners
  // ──────────────────────────────────────────────────────

  void _onStreamingChanged(bool wasStreaming, bool isStreaming) {
    if (!_active) return;
    if (state.phase != VoiceModePhase.processing) return;

    if (wasStreaming && !isStreaming) {
      // Streaming just completed — grab the last assistant message content.
      _handleStreamingComplete();
    }
  }

  void _handleStreamingComplete() {
    if (!_active) return;

    final chatState = ref.read(chatProvider);
    final messages = chatState.messages;
    if (messages.isEmpty) return;

    // The last message should be the assistant's response.
    final lastMessage = messages.last;
    final responseText = lastMessage.content.trim();

    if (responseText.isEmpty) {
      // No real content — try again or go idle.
      if (state.autoListen) {
        startListening();
      } else {
        state = state.copyWith(phase: VoiceModePhase.idle);
      }
      return;
    }

    state = state.copyWith(
      phase: VoiceModePhase.speaking,
      response: responseText,
    );

    // Fire the generating cue only on the first chunk of this response —
    // repeated taps during streaming feel glitchy.
    if (!_generatingFired) {
      _generatingFired = true;
      ref.read(voiceFeedbackProvider).playGenerating();
    }

    // Trigger TTS to speak the response. Pass message/conversation IDs so
    // TTS can cache and resume playback against the right message.
    final tts = ref.read(ttsProvider.notifier);
    () async {
      try {
        await tts.speak(
          responseText,
          messageId: lastMessage.id,
          conversationId: lastMessage.conversationId,
        );
      } catch (e) {
        if (!_active) return;
        Log.error('Voice mode TTS speak failed: $e');
        state = state.copyWith(
          phase: VoiceModePhase.error,
          error: e.toString(),
        );
      }
    }();
  }

  void _onTtsStateChanged(TtsState? previous, TtsState next) {
    if (!_active) return;
    if (state.phase != VoiceModePhase.speaking) return;

    final wasSpeaking = previous?.isSpeaking ?? false;
    final isSpeaking = next.isSpeaking;

    if (wasSpeaking && !isSpeaking && !next.isPaused) {
      // TTS just finished speaking.
      _onSpeakingComplete();
    }
  }

  void _onSpeakingComplete() {
    if (!_active) return;

    if (state.autoListen) {
      // Restart listening for the next turn.
      startListening();
    } else {
      state = state.copyWith(phase: VoiceModePhase.idle);
    }
  }

  bool _ensureChatTarget() {
    final target = ref.read(activeChatTargetProvider);
    if (target.isReady) return true;

    _isSendingTranscript = false;
    state = state.copyWith(
      isActive: true,
      phase: VoiceModePhase.error,
      error: target.server == null
          ? 'No server connected'
          : modelSelectionRequiredMessage,
      micLevel: 0,
    );
    return false;
  }
}

String _mapSttError(String error) {
  switch (error) {
    case 'error_no_match':
      return 'No speech recognized. Tap to try again.';
    case 'error_speech_timeout':
      return 'No speech detected. Tap to try again.';
    case 'error_permission':
      return 'Microphone permission denied.';
    case 'error_busy':
      return 'Speech recognition is busy. Please try again.';
    case 'error_network':
    case 'error_network_timeout':
      return 'Network error. Please check your connection.';
    case 'error_audio':
      return 'Audio recording error. Please check your microphone.';
    default:
      if (error.startsWith('error_')) {
        final cleanName = error.replaceFirst('error_', '').replaceAll('_', ' ');
        return 'Speech recognition error: $cleanName';
      }
      return error;
  }
}
