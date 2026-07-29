import 'package:flutter/material.dart';

import 'providers/voice_mode_provider.dart';

/// Accent color palette used across the voice-mode UI (overlay header,
/// waveform visualizer, transcript badge, control buttons).
///
/// Centralised so the same phase always renders with the same colour
/// regardless of which surface paints it.
class VoiceModePalette {
  const VoiceModePalette._();

  static Color accentFor(VoiceModePhase phase, {required bool isDark}) {
    switch (phase) {
      case VoiceModePhase.listening:
        return isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
      case VoiceModePhase.processing:
        return isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
      case VoiceModePhase.speaking:
        return isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);
      case VoiceModePhase.idle:
        return isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
      case VoiceModePhase.error:
        return const Color(0xFFEF4444);
    }
  }

  /// Subtle background used behind the centred phase icon / pill.
  static Color subtleBg(BuildContext context, {double opacity = 0.08}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (isDark ? Colors.white : Colors.black).withValues(alpha: opacity);
  }
}
