import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/providers/app_providers.dart';
import '../../chat/providers/chat_notifier.dart';
import '../../tts/views/tts_model_manager_screen.dart';
import '../providers/voice_mode_provider.dart';
import 'components/voice_mode_controls.dart';
import 'components/voice_transcript.dart';
import 'components/voice_visualizer.dart';

/// Full-screen voice-to-voice conversation overlay.
///
/// Presents an animated visual indicator and transcript text across
/// Listen → Process → Speak phases, looping hands-free when
/// auto-listen is enabled.
///
/// Usage:
/// ```dart
/// VoiceModeOverlay.show(context);
/// ```
class VoiceModeOverlay extends ConsumerStatefulWidget {
  const VoiceModeOverlay({super.key});

  /// Show the voice mode overlay as a full-screen modal dialog.
  static Future<void> show(BuildContext context) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curve),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return const VoiceModeOverlay();
      },
    );
  }

  @override
  ConsumerState<VoiceModeOverlay> createState() => _VoiceModeOverlayState();
}

class _VoiceModeOverlayState extends ConsumerState<VoiceModeOverlay> {
  @override
  void initState() {
    super.initState();
    // Start the voice session once the overlay is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(voiceModeProvider.notifier).startSession();
    });
  }

  Future<void> _endSession() async {
    Haptics.vibrate(HapticsType.medium);
    await ref.read(voiceModeProvider.notifier).endSession();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleCenterAction() {
    final phase = ref.read(voiceModeProvider).phase;
    Haptics.vibrate(HapticsType.light);

    switch (phase) {
      case VoiceModePhase.listening:
        // Send current transcript.
        ref.read(voiceModeProvider.notifier).stopListeningAndSend();
      case VoiceModePhase.speaking:
        // Interrupt and potentially re-listen.
        ref.read(voiceModeProvider.notifier).interrupt();
      case VoiceModePhase.idle:
      case VoiceModePhase.error:
        // Start listening.
        ref.read(voiceModeProvider.notifier).startListening();
      case VoiceModePhase.processing:
        // Can't interrupt processing — do nothing.
        break;
    }
  }

  Widget _buildTtsChip(BuildContext context, ThemeData theme, bool isDark) {
    final settings = ref.watch(settingsProvider);
    final String label;

    switch (settings.ttsEngine) {
      case EngineId.system:
        label = 'System TTS';
      case EngineId.piper:
        final voice = voiceFromSettings(settings.ttsVoiceId, EngineId.piper);
        label = 'Piper • ${voice?.name ?? 'Ryan'}';
      case EngineId.kitten:
        label = 'Kitten • ${settings.kittenTtsModelVariant.displayName}';
    }

    return InkWell(
      onTap: () {
        Haptics.vibrate(HapticsType.light);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const TtsModelManagerScreen(),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedVolumeHigh,
              size: 13,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.85)
                    : Colors.black87,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceModeProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark
        ? const Color(0xFF0A0A0A)
        : const Color(0xFFFAFAFA);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSession();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 0.92),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: SafeArea(
              child: Column(
                children: [
                  // Top bar — title, TTS chip, close button.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        // Title.
                        Text(
                          'Voice Mode',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.7)
                                : Colors.black.withValues(alpha: 0.6),
                          ),
                        ),
                        const Spacer(),
                        // TTS Model Chip.
                        _buildTtsChip(context, theme, isDark),
                        const SizedBox(width: 8),
                        // Close button.
                        IconButton(
                          onPressed: _endSession,
                          icon: Icon(
                            Icons.close,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.6)
                                : Colors.black.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Expanding space.
                  const Spacer(flex: 2),

                  // Animated visualizer.
                  GestureDetector(
                    onTap: _handleCenterAction,
                    child: VoiceVisualizer(
                      phase: state.phase,
                      size: 220,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Transcript / status text.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: VoiceTranscript(
                      phase: state.phase,
                      transcript: state.transcript,
                      response: state.phase == VoiceModePhase.processing
                          ? (ref.watch(
                                chatProvider.select(
                                  (s) => s.streamingMessage?.content,
                                ),
                              ) ??
                              state.response)
                          : state.response,
                      error: state.error,
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Bottom controls.
                  VoiceModeControls(
                    phase: state.phase,
                    autoListen: state.autoListen,
                    isMuted: state.isMuted,
                    onEnd: _endSession,
                    onToggleMute: () {
                      ref.read(voiceModeProvider.notifier).toggleMute();
                    },
                    onToggleAutoListen: () {
                      Haptics.vibrate(HapticsType.light);
                      ref.read(voiceModeProvider.notifier).toggleAutoListen();
                    },
                    onTapCenter: _handleCenterAction,
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
