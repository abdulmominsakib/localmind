import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// Features a real-time glowing 3D crystal visualizer and auto-scrolling transcript
/// set against a sleek dark obsidian atmospheric backdrop in both light and dark modes.
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

  Widget _buildTtsChip(BuildContext context, ThemeData theme) {
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
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedVolumeHigh,
              size: 13,
              color: Colors.white.withValues(alpha: 0.90),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: Colors.white.withValues(alpha: 0.90),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.50),
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

    // Voice mode presents a dark obsidian atmospheric theme in both light and dark modes
    const bgColor = Color(0xFF090A10);
    final accent = VoiceModePalette.accentFor(state.phase, isDark: true);
    final secondary = VoiceModePalette.secondaryFor(state.phase, isDark: true);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSession();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light, // White icons on Android
          statusBarBrightness: Brightness.dark,       // White text/icons on iOS
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Theme(
          data: theme.copyWith(
            brightness: Brightness.dark,
            colorScheme: const ColorScheme.dark(),
          ),
          child: Scaffold(
            backgroundColor: bgColor,
            body: Stack(
              children: [
                // Dynamic pulsing ambient background glow
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _PulsingBackgroundGlow(
                      phase: state.phase,
                      micLevel: state.micLevel,
                      accent: accent,
                      secondary: secondary,
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
                                    color: accent.withValues(alpha: 0.7),
                                    blurRadius: 10,
                                    spreadRadius: 2,
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
                                color: Colors.white.withValues(alpha: 0.90),
                              ),
                            ),
                            const Spacer(),
                            _buildTtsChip(context, theme),
                            const SizedBox(width: 4),
                            _CloseButton(onPressed: _endSession),
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
        ),
      ),
    );
  }
}

/// Subscribes to the chat streaming message and feeds its content into
/// [VoiceTranscript] during the processing phase.
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
  final VoidCallback onPressed;

  const _CloseButton({required this.onPressed});

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
            color: Colors.white.withValues(alpha: 0.08),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.80),
          ),
        ),
      ),
    );
  }
}

class _PulsingBackgroundGlow extends StatefulWidget {
  final VoiceModePhase phase;
  final double micLevel;
  final Color accent;
  final Color secondary;
  final Color bgColor;

  const _PulsingBackgroundGlow({
    required this.phase,
    required this.micLevel,
    required this.accent,
    required this.secondary,
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
      duration: const Duration(milliseconds: 3200),
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
            pulse = 0.18 + 0.45 * widget.micLevel.clamp(0.0, 1.0) + 0.12 * breath;
          case VoiceModePhase.speaking:
            pulse = 0.22 + 0.28 * breath;
          case VoiceModePhase.error:
            pulse = 0.18 + 0.20 * breath;
          case VoiceModePhase.processing:
            pulse = 0.16 + 0.18 * breath;
          case VoiceModePhase.idle:
            pulse = 0.06 + 0.06 * breath;
        }

        final alpha = (0.16 + pulse * 0.18).clamp(0.08, 0.45);
        final radius = 0.85 + pulse * 0.40;

        return Stack(
          children: [
            // Deep obsidian background base
            Container(color: widget.bgColor),

            // Top ambient gradient light pool
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: radius,
                  colors: [
                    widget.accent.withValues(alpha: alpha * 1.1),
                    widget.secondary.withValues(alpha: alpha * 0.45),
                    widget.bgColor.withValues(alpha: 0.85),
                    widget.bgColor,
                  ],
                  stops: const [0.0, 0.45, 0.78, 1.0],
                ),
              ),
            ),

            // Soft blur overlay for smooth diffusion
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.15),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
