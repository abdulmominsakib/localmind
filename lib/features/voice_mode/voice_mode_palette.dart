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

  /// Secondary accent color for multi-spectral gradient shaders & wave rings.
  static Color secondaryFor(VoiceModePhase phase, {required bool isDark}) {
    switch (phase) {
      case VoiceModePhase.listening:
        return isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
      case VoiceModePhase.processing:
        return isDark ? const Color(0xFFE879F9) : const Color(0xFFC084FC);
      case VoiceModePhase.speaking:
        return isDark ? const Color(0xFFF472B6) : const Color(0xFFDB2777);
      case VoiceModePhase.idle:
        return isDark ? const Color(0xFF64748B) : const Color(0xFF475569);
      case VoiceModePhase.error:
        return isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    }
  }

  /// Full 3D sphere gradient stops for a given phase.
  static List<Color> sphereGradientFor(
    VoiceModePhase phase, {
    required bool isDark,
  }) {
    final accent = accentFor(phase, isDark: isDark);
    final secondary = secondaryFor(phase, isDark: isDark);

    switch (phase) {
      case VoiceModePhase.listening:
        return [
          const Color(0xFFA7F3D0), // Soft mint top highlight
          accent, // Emerald / Teal accent
          secondary, // Cyan blue
          const Color(0xFF0284C7), // Deep cyan edge
        ];
      case VoiceModePhase.processing:
        return [
          const Color(0xFFF0ABFC), // Bright violet light top
          accent, // Deep purple
          secondary, // Magenta shimmer
          const Color(0xFF4C1D95), // Deep dark indigo edge
        ];
      case VoiceModePhase.speaking:
        return [
          const Color(0xFFFFAEE2), // Light peach pink top
          const Color(0xFFF472B6), // Pink
          accent, // Indigo / Purple
          secondary, // Deep rose / cyan bottom
        ];
      case VoiceModePhase.idle:
        return [
          const Color(0xFFCBD5E1), // Cool grey light
          accent, // Slate blue
          secondary, // Dark slate
          const Color(0xFF334155), // Charcoal edge
        ];
      case VoiceModePhase.error:
        return [
          const Color(0xFFFECDD3), // Soft rose pink highlight
          const Color(0xFFF87171), // Vibrant coral red
          accent, // Crimson red
          const Color(0xFF991B1B), // Dark burgundy edge
        ];
    }
  }

  /// Subtle background used behind the centred phase icon / pill.
  static Color subtleBg(BuildContext context, {double opacity = 0.08}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (isDark ? Colors.white : Colors.black).withValues(alpha: opacity);
  }
}
