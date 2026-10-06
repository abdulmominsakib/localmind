import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/providers/chat_background_service_provider.dart';
import '../../../services/voice_feedback_service.dart';
import '../../chat/providers/chat_providers.dart';
import '../../stt/providers/stt_providers.dart';
import '../../stt/utils/stt_error_messages.dart';
import '../../tts/providers/tts_providers.dart';

/// The phase of the voice-to-voice conversation loop.
enum VoiceModePhase {
  /// Overlay is open but idle — waiting for the user to start.
  idle,

  /// Actively listening for user speech via STT.
  listening,

  /// User speech captured; the composed message is being sent.
  processing,

  /// Transitional: retained for palette rendering compatibility; voice mode
  /// no longer speaks inline by itself.
  speaking,

  /// The message was handed to the chat. The overlay closes and the user
  /// lands in the conversation thread.
  sent,

  /// An error occurred in one of the phases.
  error,
}

class VoiceModeState {
  final bool isActive;
  final VoiceModePhase phase;
  final String transcript;
  final String response;
  final bool isMuted;
  final String? error;

  /// Live microphone input level in 0..1, set from the STT
  /// `onSoundLevelChange` callback. 0 when not listening.
  final double micLevel;

  /// An assistant screen snapshot is waiting to be attached to the next
  /// voice send.
  final bool screenshotPending;

  /// When a snapshot is pending, the user can exclude it from the next
  /// send entirely.
  final bool excludeScreenshot;

  const VoiceModeState({
    this.isActive = false,
    this.phase = VoiceModePhase.idle,
    this.transcript = '',
    this.response = '',
    this.isMuted = false,
    this.error,
    this.micLevel = 0,
    this.screenshotPending = false,
    this.excludeScreenshot = false,
  });

  VoiceModeState copyWith({
    bool? isActive,
    VoiceModePhase? phase,
    String? transcript,
    String? response,
    bool? isMuted,
    String? error,
    bool clearError = false,
    double? micLevel,
    bool? screenshotPending,
    bool? excludeScreenshot,
  }) {
    return VoiceModeState(
      isActive: isActive ?? this.isActive,
      phase: phase ?? this.phase,
      transcript: transcript ?? this.transcript,
      response: response ?? this.response,
      isMuted: isMuted ?? this.isMuted,
      error: clearError ? null : (error ?? this.error),
      micLevel: micLevel ?? this.micLevel,
      screenshotPending: screenshotPending ?? this.screenshotPending,
      excludeScreenshot: excludeScreenshot ?? this.excludeScreenshot,
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
  int _listenAttempt = 0;
  String? _assistantScreenshotPath;

  @override
  VoiceModeState build() {
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

    // Listen to STT errors and show them directly on the voice screen. The
    // raw code is kept in state and localized by the view.
    ref.listen<String?>(sttProvider.select((s) => s.error), (previous, next) {
      if (!_active || next == null) return;
      state = state.copyWith(phase: VoiceModePhase.error, error: next);
      ref.read(voiceFeedbackProvider).playDisconnected();
    });

    return const VoiceModeState();
  }

  // ──────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────

  /// Begin the voice mode session. Called when the overlay opens.
  ///
  /// [assistantScreenshotPath] points at a screen snapshot captured on the
  /// Android assistant invocation. It is only attached when the message is
  /// actually sent — and can be excluded for the session by the user — so
  /// sending without speech submits the screenshot alone in a fresh thread
  /// when the active model can see images.
  void startSession({String? assistantScreenshotPath}) {
    _active = true;
    _assistantScreenshotPath = assistantScreenshotPath;
    state = VoiceModeState(
      isActive: true,
      phase: VoiceModePhase.idle,
      screenshotPending: assistantScreenshotPath != null,
    );
    if (!_ensureChatTarget()) return;
    ref.read(voiceFeedbackProvider).playConnected();
    // Auto-start listening.
    startListening();
  }

  /// Attach or drop the pending assistant snapshot for the next send.
  void toggleExcludeScreenshot() {
    state = state.copyWith(excludeScreenshot: !state.excludeScreenshot);
  }

  /// Start listening for user speech.
  Future<void> startListening() async {
    if (!_active || !ref.mounted) return;
    final attempt = ++_listenAttempt;
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
    final available = await stt.initSpeech();
    if (!_isCurrentListenAttempt(attempt)) return;
    if (!available) {
      // Distinguish a missing recognizer (#100) from a microphone permission
      // that is genuinely missing or refused. A plain `false` with no code
      // follows the plugin's own permission signal and stays a permission
      // problem, matching the model-guard spec.
      final code = ref.read(sttProvider).error;
      final noRecognizer = code == sttUnavailableCode;
      state = state.copyWith(
        phase: VoiceModePhase.error,
        error: noRecognizer
            ? sttUnavailableCode
            : 'Microphone permission is required for voice mode.',
        micLevel: 0,
      );
      ref.read(voiceFeedbackProvider).playDisconnected();
      return;
    }

    // Hold a microphone-typed foreground service so that voice capture
    // survives when the app is backgrounded on Android 14+. Must run
    // after permission has been granted and while this activity is visible.
    final background = ref.read(chatBackgroundServiceProvider);
    final micStarted = await background.startMic();
    if (!_isCurrentListenAttempt(attempt)) {
      if (micStarted) await background.stopMic();
      return;
    }
    if (!micStarted) {
      state = state.copyWith(
        phase: VoiceModePhase.error,
        error:
            'Could not start microphone access. Open LocalMind and try again.',
        micLevel: 0,
      );
      ref.read(voiceFeedbackProvider).playDisconnected();
      return;
    }

    await stt.startListening(
      onResult: (words) {
        if (!_active || !ref.mounted) return;
        if (words.isNotEmpty) {
          state = state.copyWith(transcript: words);
        }
      },
      onFinal: (finalWords) async {
        if (!_active || !ref.mounted) return;
        if (_isSendingTranscript) return;
        final text = finalWords.trim().isNotEmpty
            ? finalWords
            : state.transcript;
        // Silence alone never fires a send; the user taps Send (or an
        // attached screenshot makes it meaningful).
        if (text.trim().isEmpty) return;
        _isSendingTranscript = true;
        await stopListeningAndSend();
      },
      onSoundLevelChange: (level) {
        if (!_active || !ref.mounted) return;
        // Skip the rebuild when the value hasn't materially changed
        // (riverpod notifies listeners on every distinct copyWith).
        if ((state.micLevel - level).abs() < 0.01) return;
        state = state.copyWith(micLevel: level);
      },
    );
  }

  /// Stop listening and hand the composed message (transcript and/or the
  /// assistant's screen snapshot) to the chat. The overlay transitions to
  /// the conversation thread once this runs.
  Future<void> stopListeningAndSend() async {
    if (!_active || !ref.mounted) return;
    _listenAttempt++;

    final stt = ref.read(sttProvider.notifier);
    await stt.stopListening();
    // Release the microphone-typed foreground service as soon as capture
    // is done. The transcript is in hand and the LLM will be polled by
    // the inference FGS path, not the mic one.
    await ref.read(chatBackgroundServiceProvider).stopMic();
    if (!_active || !ref.mounted) return;

    final transcript = state.transcript.trim();
    final attachments = <File>[];
    final screenshot = _assistantScreenshotPath;
    if (screenshot != null &&
        !state.excludeScreenshot &&
        _activeModelSupportsVision()) {
      attachments.add(File(screenshot));
      // The snapshot opens its own fresh thread so the conversation starts
      // from the screen the assistant was fired on.
      try {
        await ref.read(chatProvider.notifier).startNewConversation();
      } catch (e) {
        if (!_active || !ref.mounted) return;
        Log.error('Voice mode thread creation error: $e');
        state = state.copyWith(
          phase: VoiceModePhase.error,
          error: e.toString(),
        );
        return;
      }
    }

    if (transcript.isEmpty && attachments.isEmpty) {
      // Nothing was recognized and there is nothing to attach — a sendless
      // send is not allowed.
      state = state.copyWith(
        phase: VoiceModePhase.error,
        error: 'No speech recognized. Tap to try again.',
        micLevel: 0,
      );
      return;
    }

    state = state.copyWith(
      phase: VoiceModePhase.processing,
      response: '',
      micLevel: 0,
    );

    try {
      await ref
          .read(chatProvider.notifier)
          .sendMessage(
            transcript,
            attachments: attachments.isEmpty ? null : attachments,
          );
    } catch (e) {
      if (!_active || !ref.mounted) return;
      Log.error('Voice mode send error: $e');
      state = state.copyWith(phase: VoiceModePhase.error, error: e.toString());
      return;
    }
    if (!_active || !ref.mounted) return;
    state = state.copyWith(phase: VoiceModePhase.sent);
  }

  /// Toggle mute (pause listening without ending session).
  void toggleMute() {
    state = state.copyWith(isMuted: !state.isMuted);
  }

  /// End the entire voice session and reset everything.
  Future<void> endSession() async {
    _active = false;
    _listenAttempt++;
    _isSendingTranscript = false;

    // Cancel speech recognition before releasing the microphone service so
    // the recognizer never continues using an already-stopped FGS.
    try {
      if (ref.mounted) {
        final stt = ref.read(sttProvider.notifier);
        await stt.cancelListening();
      }
    } catch (e) {
      Log.error('Voice mode STT cancel error: $e');
    }

    // Always release the mic FGS, even if listening never started cleanly.
    try {
      await ref.read(chatBackgroundServiceProvider).stopMic();
    } catch (e) {
      Log.error('Voice mode mic service stop error: $e');
    }

    if (ref.mounted) {
      ref.read(voiceFeedbackProvider).playDisconnected();
    }

    // Stop TTS if something is still speaking.
    try {
      if (ref.mounted) {
        final tts = ref.read(ttsProvider.notifier);
        await tts.stop();
      }
    } catch (e) {
      Log.error('Voice mode TTS stop error: $e');
    }

    _deleteAssistantScreenshot();
    if (ref.mounted) {
      state = const VoiceModeState();
    }
  }

  // ──────────────────────────────────────────────────────
  // Internal helpers
  // ──────────────────────────────────────────────────────

  /// True when the model picked for this session accepts image input.
  bool _activeModelSupportsVision() {
    return ref.read(activeChatTargetProvider).selectedModel?.supportsVision ??
        false;
  }

  void _deleteAssistantScreenshot() {
    final path = _assistantScreenshotPath;
    _assistantScreenshotPath = null;
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      Log.error('Assistant screenshot cleanup failed: $e');
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

  bool _isCurrentListenAttempt(int attempt) {
    return _active && ref.mounted && attempt == _listenAttempt;
  }
}
