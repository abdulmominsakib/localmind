import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../providers/voice_mode_provider.dart';
import '../../voice_mode_palette.dart';

/// Bottom control bar for voice mode overlay:
/// auto-listen toggle, end-call button, primary mic action.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PillControl(
            icon: autoListen
                ? HugeIcons.strokeRoundedRepeat
                : HugeIcons.strokeRoundedRepeatOff,
            label: autoListen ? 'Auto' : 'Manual',
            isActive: autoListen,
            activeColor: VoiceModePalette.accentFor(
              VoiceModePhase.speaking,
              isDark: isDark,
            ),
            onTap: onToggleAutoListen,
          ),

          _EndCallButton(onTap: onEnd),

          _PillControl(
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
            activeColor: VoiceModePalette.accentFor(
              VoiceModePhase.listening,
              isDark: isDark,
            ),
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
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Center(
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedCallEnd01,
            size: 30,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _PillControl extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _PillControl({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isActive
        ? activeColor.withValues(alpha: 0.14)
        : (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04));

    final iconColor = isActive
        ? activeColor
        : (isDark
            ? Colors.white.withValues(alpha: 0.7)
            : Colors.black.withValues(alpha: 0.55));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive
                ? activeColor.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: icon,
              size: 22,
              color: iconColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: isActive
                    ? activeColor
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.black.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}