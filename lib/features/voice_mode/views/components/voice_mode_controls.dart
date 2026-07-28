import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../providers/voice_mode_provider.dart';

/// Bottom control bar for voice mode overlay:
/// end call button, mute toggle, auto-listen toggle.
class VoiceModeControls extends StatelessWidget {
  final VoiceModePhase phase;
  final bool autoListen;
  final bool isMuted;
  final VoidCallback onEnd;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleAutoListen;
  final VoidCallback onTapCenter;

  const VoiceModeControls({
    super.key,
    required this.phase,
    required this.autoListen,
    required this.isMuted,
    required this.onEnd,
    required this.onToggleMute,
    required this.onToggleAutoListen,
    required this.onTapCenter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Auto-listen toggle.
          _ControlButton(
            icon: autoListen
                ? HugeIcons.strokeRoundedRepeat
                : HugeIcons.strokeRoundedRepeatOff,
            label: autoListen ? 'Auto' : 'Manual',
            isActive: autoListen,
            activeColor: isDark
                ? const Color(0xFF6366F1)
                : const Color(0xFF4F46E5),
            isDark: isDark,
            onTap: onToggleAutoListen,
          ),

          // Main action — end session (red).
          _EndCallButton(onTap: onEnd),

          // Send / interrupt based on phase.
          _ControlButton(
            icon: phase == VoiceModePhase.listening
                ? HugeIcons.strokeRoundedSent
                : phase == VoiceModePhase.speaking
                    ? HugeIcons.strokeRoundedStop
                    : HugeIcons.strokeRoundedMic01,
            label: phase == VoiceModePhase.listening
                ? 'Send'
                : phase == VoiceModePhase.speaking
                    ? 'Stop'
                    : 'Speak',
            isActive: phase == VoiceModePhase.listening ||
                phase == VoiceModePhase.speaking,
            activeColor: isDark
                ? const Color(0xFF34D399)
                : const Color(0xFF059669),
            isDark: isDark,
            onTap: onTapCenter,
          ),
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Center(
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedCallEnd01,
            size: 28,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final bool isDark;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isActive
        ? activeColor.withValues(alpha: 0.15)
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05));

    final iconColor = isActive
        ? activeColor
        : (isDark
            ? Colors.white.withValues(alpha: 0.6)
            : Colors.black.withValues(alpha: 0.5));

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? activeColor.withValues(alpha: 0.3)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Center(
              child: HugeIcon(
                icon: icon,
                size: 24,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.black.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
