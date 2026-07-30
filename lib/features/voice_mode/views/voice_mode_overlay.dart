import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/providers/app_providers.dart';
import '../../chat/providers/chat_notifier.dart';
import '../../tts/views/tts_model_manager_screen.dart';
import '../providers/voice_mode_provider.dart';
import '../voice_mode_palette.dart';
import 'components/voice_mode_controls.dart';
import 'components/voice_transcript.dart';
import 'components/voice_visualizer.dart';

/// Full-screen voice-to-voice conversation overlay.
///
/// Presents a real-time waveform visualizer and auto-scrolling transcript
/// across Listen → Process → Speak phases, looping hands-free when
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
      transitionDuration: const Duration(milliseconds: 420),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curve),
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
    await ref.read(voiceModeProvider.notifier).endSession();
    if (mounted) {
      context.pop();
    }
  }

  void _handleCenterAction() {
    final phase = ref.read(voiceModeProvider).phase;

    switch (phase) {
      case VoiceModePhase.listening:
        ref.read(voiceModeProvider.notifier).stopListeningAndSend();
      case VoiceModePhase.speaking:
        ref.read(voiceModeProvider.notifier).interrupt();
      case VoiceModePhase.idle:
      case VoiceModePhase.error:
        ref.read(voiceModeProvider.notifier).startListening();
      case VoiceModePhase.processing:
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
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.08),
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
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.85)
                    : Colors.black87,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.45)
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

    final bgColor = isDark ? const Color(0xFF0B0B10) : const Color(0xFFF7F7FB);

    final accent = VoiceModePalette.accentFor(state.phase, isDark: isDark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSession();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // RepaintBoundary so the gradient + blur aren't re-rasterised
            // when the lower subtree (transcript/visualizer/controls)
            // rebuilds on streamed tokens or mic-level changes.
            Positioned.fill(
              child: RepaintBoundary(
                child: _PulsingBackgroundGlow(
                  phase: state.phase,
                  micLevel: state.micLevel,
                  isDark: isDark,
                  accent: accent,
                  bgColor: bgColor,
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Voice Mode',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.85)
                                : Colors.black.withValues(alpha: 0.8),
                          ),
                        ),
                        const Spacer(),
                        _buildTtsChip(context, theme, isDark),
                        const SizedBox(width: 4),
                        _CloseButton(isDark: isDark, onPressed: _endSession),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  GestureDetector(
                    onTap: _handleCenterAction,
                    child: VoiceVisualizer(
                      phase: state.phase,
                      micLevel: state.micLevel,
                      size: 240,
                    ),
                  ),

                  const SizedBox(height: 28),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: _StreamingTranscript(
                      phase: state.phase,
                      transcript: state.transcript,
                      response: state.response,
                      error: state.error,
                    ),
                  ),

                  const Spacer(flex: 3),

                  VoiceModeControls(
                    phase: state.phase,
                    autoListen: state.autoListen,
                    isMuted: state.isMuted,
                    onEnd: _endSession,
                    onToggleMute: () {
                      ref.read(voiceModeProvider.notifier).toggleMute();
                    },
                    onToggleAutoListen: () {
                      ref.read(voiceModeProvider.notifier).toggleAutoListen();
                    },
                    onTapCenter: _handleCenterAction,
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subscribes to the chat streaming message and feeds its content into
/// [VoiceTranscript] during the processing phase. Lives in its own
/// Consumer so streamed tokens only rebuild this subtree, not the
/// gradient/BackdropFilter above it.
class _StreamingTranscript extends ConsumerWidget {
  final VoiceModePhase phase;
  final String transcript;
  final String response;
  final String? error;

  const _StreamingTranscript({
    required this.phase,
    required this.transcript,
    required this.response,
    required this.error,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamed = phase == VoiceModePhase.processing
        ? (ref.watch(chatProvider.select((s) => s.streamingMessage?.content)) ??
              response)
        : response;
    return VoiceTranscript(
      phase: phase,
      transcript: transcript,
      response: streamed,
      error: error,
    );
  }
}

class _CloseButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onPressed;

  const _CloseButton({required this.isDark, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: isDark
                ? Colors.white.withValues(alpha: 0.7)
                : Colors.black.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _PulsingBackgroundGlow extends StatefulWidget {
  final VoiceModePhase phase;
  final double micLevel;
  final bool isDark;
  final Color accent;
  final Color bgColor;

  const _PulsingBackgroundGlow({
    required this.phase,
    required this.micLevel,
    required this.isDark,
    required this.accent,
    required this.bgColor,
  });

  @override
  State<_PulsingBackgroundGlow> createState() => _PulsingBackgroundGlowState();
}

class _PulsingBackgroundGlowState extends State<_PulsingBackgroundGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        final breath = _ticker.value;
        final double pulse;

        switch (widget.phase) {
          case VoiceModePhase.listening:
            pulse = 0.15 + 0.5 * widget.micLevel.clamp(0.0, 1.0) + 0.1 * breath;
          case VoiceModePhase.speaking:
            pulse = 0.20 + 0.25 * breath;
          case VoiceModePhase.error:
            pulse = 0.18 + 0.22 * breath;
          case VoiceModePhase.processing:
            pulse = 0.16 + 0.18 * breath;
          case VoiceModePhase.idle:
            pulse = 0.06 + 0.06 * breath;
        }

        final baseAlpha = widget.isDark ? 0.12 : 0.16;
        final alpha = (baseAlpha + pulse * 0.16).clamp(0.05, 0.40);
        final radius = 0.95 + pulse * 0.35;

        return Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: radius,
                  colors: [
                    widget.accent.withValues(alpha: alpha),
                    widget.accent.withValues(alpha: alpha * 0.35),
                    widget.bgColor,
                  ],
                  stops: const [0.0, 0.55, 0.95],
                ),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                child: Container(
                  color: widget.bgColor.withValues(alpha: 0.50),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

