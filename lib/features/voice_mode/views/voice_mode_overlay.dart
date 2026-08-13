import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/app_haptics.dart';
import '../../../../l10n/app_localizations.dart';
import '../../chat/providers/chat_notifier.dart';
import '../../chat/providers/model_selection_providers.dart';
import '../../models/components/model_list.dart';
import '../../on_device/components/on_device_picker_section.dart';
import '../../servers/providers/server_providers.dart';
import '../../tts/providers/tts_providers.dart';
import '../../tts/views/tts_model_manager_screen.dart';
import '../providers/voice_mode_provider.dart';
import '../voice_mode_palette.dart';
import 'components/voice_mode_controls.dart';
import 'components/voice_transcript.dart';
import 'components/voice_visualizer.dart';

/// Full-screen voice-to-voice conversation overlay.
///
/// Features a real-time glowing 3D crystal visualizer and auto-scrolling transcript
/// set against an adaptive pearlescent or obsidian atmospheric backdrop.
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
    final isDark = theme.brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF25243A);
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
        ref.read(appHapticsProvider).light();
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
          color: foreground.withValues(alpha: isDark ? 0.08 : 0.055),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: foreground.withValues(alpha: isDark ? 0.14 : 0.10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedVolumeHigh,
              size: 13,
              color: foreground.withValues(alpha: 0.90),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: foreground.withValues(alpha: 0.90),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: foreground.withValues(alpha: 0.50),
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
    final bgColor = isDark ? const Color(0xFF090A10) : const Color(0xFFF4F6FA);
    final foreground = isDark ? Colors.white : const Color(0xFF25243A);
    final accent = VoiceModePalette.accentFor(state.phase, isDark: isDark);
    final secondary = VoiceModePalette.secondaryFor(
      state.phase,
      isDark: isDark,
    );
    final ttsPlayback = ref.watch(
      ttsProvider.select(
        (tts) => (position: tts.position, duration: tts.duration),
      ),
    );
    final durationMicros = ttsPlayback.duration.inMicroseconds;
    final responseProgress = durationMicros <= 0
        ? 0.0
        : (ttsPlayback.position.inMicroseconds / durationMicros).clamp(
            0.0,
            1.0,
          );
    final orbSize = (MediaQuery.sizeOf(context).width * 0.72).clamp(
      225.0,
      255.0,
    );
    final target = ref.watch(activeChatTargetProvider);
    final showInlineModelPicker = target.server != null && !target.isReady;
    final modelPickerHeight = (MediaQuery.sizeOf(context).height / 3).clamp(
      220.0,
      380.0,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSession();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Theme(
          data: theme,
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
                      isDark: isDark,
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
                                color: foreground.withValues(alpha: 0.90),
                              ),
                            ),
                            const Spacer(),
                            _buildTtsChip(context, theme),
                            const SizedBox(width: 4),
                            _CloseButton(onPressed: _endSession),
                          ],
                        ),
                      ),
                      if (showInlineModelPicker) ...[
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final compactOrbSize =
                                  (constraints.maxHeight * 0.52).clamp(
                                    110.0,
                                    orbSize,
                                  );
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: _handleCenterAction,
                                    child: VoiceVisualizer(
                                      phase: state.phase,
                                      micLevel: state.micLevel,
                                      responseProgress: responseProgress,
                                      size: compactOrbSize,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                      ),
                                      child: _StreamingTranscript(
                                        phase: state.phase,
                                        transcript: state.transcript,
                                        response: state.response,
                                        error: state.error,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SizedBox(
                            height: modelPickerHeight,
                            child: const VoiceModelPickerPanel(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else ...[
                        const Spacer(flex: 2),
                        GestureDetector(
                          onTap: _handleCenterAction,
                          child: VoiceVisualizer(
                            phase: state.phase,
                            micLevel: state.micLevel,
                            responseProgress: responseProgress,
                            size: orbSize,
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
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Center(child: VoiceTargetChip()),
                        ),
                      ],

                      VoiceModeControls(
                        phase: state.phase,
                        autoListen: state.autoListen,
                        isMuted: state.isMuted,
                        onEnd: _endSession,
                        onToggleMute: () {
                          ref.read(voiceModeProvider.notifier).toggleMute();
                        },
                        onToggleAutoListen: () {
                          ref
                              .read(voiceModeProvider.notifier)
                              .toggleAutoListen();
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

class VoiceModelPickerPanel extends ConsumerWidget {
  const VoiceModelPickerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final server = ref.watch(activeServerProvider);
    if (server == null) return const SizedBox.shrink();

    final selectedModel = ref.watch(selectedModelProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF25243A);
    final surface = isDark
        ? const Color(0xFF151720).withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.88);

    return Semantics(
      container: true,
      label: '${l10n.select_model_title}, ${server.name}',
      child: Container(
        key: const ValueKey('voice-model-picker-panel'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: foreground.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.07),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.memory_rounded,
                  size: 16,
                  color: foreground.withValues(alpha: 0.62),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    l10n.select_model_title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: foreground.withValues(alpha: 0.86),
                    ),
                  ),
                ),
                Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: foreground.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: server.type == ServerType.onDevice
                  ? OnDevicePickerSection(
                      selectedModelId: selectedModel?.id,
                      isDark: isDark,
                      closeOnSelect: false,
                    )
                  : ModelList(
                      serverId: server.id,
                      selectedModelId: selectedModel?.id,
                      isDark: isDark,
                      closeOnSelect: false,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class VoiceTargetChip extends ConsumerWidget {
  const VoiceTargetChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(activeChatTargetProvider);
    final server = target.server;
    if (server == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF25243A);

    return Semantics(
      label: 'Active server ${server.name}, model ${target.modelLabel}',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: isDark ? 0.055 : 0.035),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: foreground.withValues(alpha: isDark ? 0.10 : 0.075),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 12,
              color: foreground.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: foreground.withValues(alpha: 0.62),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '•',
                style: TextStyle(
                  fontSize: 10,
                  color: foreground.withValues(alpha: 0.32),
                ),
              ),
            ),
            Flexible(
              child: Text(
                target.modelLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: foreground.withValues(alpha: 0.52),
                ),
              ),
            ),
          ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF25243A);

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
            color: foreground.withValues(alpha: isDark ? 0.08 : 0.055),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: foreground.withValues(alpha: 0.80),
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
  final bool isDark;

  const _PulsingBackgroundGlow({
    required this.phase,
    required this.micLevel,
    required this.accent,
    required this.secondary,
    required this.bgColor,
    required this.isDark,
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
            pulse =
                0.18 + 0.45 * widget.micLevel.clamp(0.0, 1.0) + 0.12 * breath;
          case VoiceModePhase.speaking:
            pulse = 0.22 + 0.28 * breath;
          case VoiceModePhase.error:
            pulse = 0.18 + 0.20 * breath;
          case VoiceModePhase.processing:
            pulse = 0.16 + 0.18 * breath;
          case VoiceModePhase.idle:
            pulse = 0.06 + 0.06 * breath;
        }

        final alpha = widget.isDark
            ? (0.16 + pulse * 0.18).clamp(0.08, 0.45)
            : (0.012 + pulse * 0.020).clamp(0.01, 0.05);
        final radius = 0.85 + pulse * 0.40;

        return Stack(
          children: [
            // Theme-adaptive background base.
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
                  color: (widget.isDark ? Colors.black : Colors.white)
                      .withValues(alpha: widget.isDark ? 0.15 : 0.10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
