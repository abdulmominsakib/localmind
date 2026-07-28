import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../tts/providers/tts_providers.dart';
import '../../providers/voice_mode_provider.dart';

/// Displays the current voice phase badge and auto-scrolling response text container.
class VoiceTranscript extends ConsumerStatefulWidget {
  final VoiceModePhase phase;
  final String transcript;
  final String response;
  final String? error;

  const VoiceTranscript({
    super.key,
    required this.phase,
    required this.transcript,
    required this.response,
    this.error,
  });

  @override
  ConsumerState<VoiceTranscript> createState() => _VoiceTranscriptState();
}

class _VoiceTranscriptState extends ConsumerState<VoiceTranscript> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(VoiceTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.response != oldWidget.response &&
        widget.phase == VoiceModePhase.processing) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isTtsInitializing = ref.watch(
      ttsProvider.select((s) => s.isInitializing),
    );

    final (label, badgeColor, isSynthesizing) = _resolveStatusBadge(
      isTtsInitializing,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Status Badge Pill
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Container(
            key: ValueKey(label),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: badgeColor.withValues(alpha: isDark ? 0.3 : 0.25),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: badgeColor,
                    boxShadow: [
                      BoxShadow(
                        color: badgeColor.withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Main text content — auto-scrolling square container for RESPONDING/PROCESSING,
        // hidden when SPEAKING.
        if (widget.phase != VoiceModePhase.speaking)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _buildTextContent(context, isDark, isSynthesizing),
          ),
      ],
    );
  }

  (String, Color, bool) _resolveStatusBadge(bool isTtsInitializing) {
    if (widget.phase == VoiceModePhase.speaking && isTtsInitializing) {
      return ('SYNTHESIZING VOICE', const Color(0xFFF59E0B), true);
    }

    switch (widget.phase) {
      case VoiceModePhase.listening:
        return ('LISTENING', const Color(0xFF10B981), false);
      case VoiceModePhase.processing:
        final hasResponse = widget.response.trim().isNotEmpty;
        if (isTtsInitializing) {
          return ('SYNTHESIZING VOICE', const Color(0xFFF59E0B), true);
        }
        return (
          hasResponse ? 'RESPONDING' : 'PROCESSING',
          const Color(0xFF8B5CF6),
          false,
        );
      case VoiceModePhase.speaking:
        return ('SPEAKING', const Color(0xFF6366F1), false);
      case VoiceModePhase.idle:
        return ('READY', Colors.grey, false);
      case VoiceModePhase.error:
        final errorText = widget.error ?? '';
        final isSpeechError = errorText.toLowerCase().contains('speech');
        return (
          isSpeechError ? 'NO SPEECH DETECTED' : 'ERROR',
          const Color(0xFFEF4444),
          false,
        );
    }
  }

  Widget _buildTextContent(
    BuildContext context,
    bool isDark,
    bool isSynthesizing,
  ) {
    switch (widget.phase) {
      case VoiceModePhase.processing:
        final hasResponse = widget.response.trim().isNotEmpty;
        if (!hasResponse) {
          return Text(
            'Thinking...',
            key: const ValueKey('thinking'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: 0.5),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          );
        }

        // Auto-scrolling square container for generating text
        return Container(
          key: const ValueKey('responding-container'),
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 130),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: Text(
              widget.response,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.black.withValues(alpha: 0.65),
                height: 1.45,
              ),
              textAlign: TextAlign.start,
            ),
          ),
        );

      case VoiceModePhase.listening:
        final displayText =
            widget.transcript.isEmpty ? 'Listening...' : widget.transcript;
        return Text(
          displayText,
          key: ValueKey('listening-${displayText.hashCode}'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: isDark
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.black.withValues(alpha: 0.8),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        );

      case VoiceModePhase.idle:
        return Text(
          'Tap to start speaking',
          key: const ValueKey('idle'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: isDark
                ? Colors.white.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.4),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        );

      case VoiceModePhase.error:
        final errorText = (widget.error != null && widget.error!.isNotEmpty)
            ? widget.error!
            : 'No speech recognized. Tap to try again.';
        return Text(
          errorText,
          key: ValueKey('error-${errorText.hashCode}'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: const Color(0xFFEF4444).withValues(alpha: 0.9),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        );

      case VoiceModePhase.speaking:
        return const SizedBox.shrink();
    }
  }
}
