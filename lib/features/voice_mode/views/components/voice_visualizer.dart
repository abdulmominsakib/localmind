import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../providers/voice_mode_provider.dart';
import '../../voice_mode_palette.dart';

/// Real-time waveform visualizer.
///
/// While [VoiceModePhase.listening] the bars animate from the live
/// microphone level. While [VoiceModePhase.speaking] (AI playback) we
/// drive a procedural envelope because we can't read amplitude from the
/// TTS audio stream.
class VoiceVisualizer extends StatefulWidget {
  final VoiceModePhase phase;
  final double size;

  /// Current microphone input level in 0..1 (only meaningful while
  /// listening).
  final double micLevel;

  const VoiceVisualizer({
    super.key,
    required this.phase,
    this.size = 220,
    this.micLevel = 0,
  });

  @override
  State<VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<VoiceVisualizer>
    with SingleTickerProviderStateMixin {
  /// Always running — even during listening we need per-frame ticks so the
  /// procedural noise modulation keeps moving while the user speaks. During
  /// speaking the same controller drives the AI envelope.
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          return CustomPaint(
            painter: _WaveformPainter(
              phase: widget.phase,
              micLevel: widget.micLevel.clamp(0.0, 1.0),
              aiValue: _ticker.value,
              isDark: isDark,
            ),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  static const _barCount = 28;

  final VoiceModePhase phase;
  final double micLevel;
  final double aiValue;
  final bool isDark;

  // Pre-allocated scratch values to keep the per-frame loop tight.
  static final Paint _barPaint = Paint()..strokeCap = StrokeCap.round;
  static final Paint _haloPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
  static final Paint _corePaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  _WaveformPainter({
    required this.phase,
    required this.micLevel,
    required this.aiValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final accent = VoiceModePalette.accentFor(phase, isDark: isDark);

    // The halo keeps the surface feeling alive even when there's no audio.
    _paintHalo(canvas, center, size, accent);

    switch (phase) {
      case VoiceModePhase.listening:
        _paintBars(canvas, size, accent, amp: micLevel);
      case VoiceModePhase.speaking:
        _paintBars(canvas, size, accent, amp: _aiEnvelope());
      case VoiceModePhase.processing:
        _paintProcessingBars(canvas, size, accent);
      case VoiceModePhase.idle:
        _paintBars(canvas, size, accent, amp: 0.06 + 0.04 * aiValue);
      case VoiceModePhase.error:
        _paintBars(canvas, size, accent, amp: 0.05);
    }
  }

  void _paintBars(
    Canvas canvas,
    Size size,
    Color color, {
    required double amp,
  }) {
    const half = _barCount ~/ 2;
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;
    final maxBarHeight = height * 0.42;
    final minBarHeight = height * 0.04;
    final barWidth = (width / (_barCount * 2)).clamp(2.0, 4.0);
    final gap = (width - barWidth * _barCount * 2) / (_barCount * 2 + 1);
    final baseX = centerY - (half * (barWidth + gap)) + gap / 2;
    final stride = barWidth + gap;
    final t = aiValue * 2 * math.pi;
    final ampScale = 0.45 + amp * 1.35;

    _barPaint.strokeWidth = barWidth;

    for (int i = 0; i < _barCount; i++) {
      final dist = ((i - half).abs() / half).clamp(0.0, 1.0);
      final envelope = math.cos(dist * math.pi / 2);
      final noise = _waveNoise(i - half, phase, t);
      final normalised = (envelope * ampScale * (0.6 + 0.4 * noise))
          .clamp(0.0, 1.0);
      final barHeight = minBarHeight + (maxBarHeight - minBarHeight) * normalised;

      _barPaint.color = color.withValues(alpha: 0.35 + 0.55 * normalised);
      canvas.drawLine(
        Offset(baseX + i * stride, centerY - barHeight / 2),
        Offset(baseX + i * stride, centerY + barHeight / 2),
        _barPaint,
      );
    }

    _corePaint.color = color.withValues(alpha: 0.6 + 0.4 * amp);
    canvas.drawCircle(
      Offset(width / 2, height / 2),
      4 + 6 * amp,
      _corePaint,
    );
  }

  void _paintProcessingBars(Canvas canvas, Size size, Color color) {
    const half = _barCount ~/ 2;
    final centerY = size.height / 2;
    final maxBarHeight = size.height * 0.28;
    final minBarHeight = size.height * 0.03;
    final barWidth = (size.width / (_barCount * 2)).clamp(2.0, 4.0);
    final gap = (size.width - barWidth * _barCount * 2) / (_barCount * 2 + 1);
    final baseX = centerY - (half * (barWidth + gap)) + gap / 2;
    final stride = barWidth + gap;

    _barPaint.strokeWidth = barWidth;

    for (int i = 0; i < _barCount; i++) {
      final dist = ((i - half).abs() / half).clamp(0.0, 1.0);
      final progress = ((aiValue + dist * 0.6) % 1.0);
      final wave = math.sin(progress * math.pi);
      final h = minBarHeight + (maxBarHeight - minBarHeight) * wave;

      _barPaint.color = color.withValues(alpha: 0.25 + 0.55 * wave);
      canvas.drawLine(
        Offset(baseX + i * stride, centerY - h / 2),
        Offset(baseX + i * stride, centerY + h / 2),
        _barPaint,
      );
    }

    final breath = 0.5 + 0.5 * math.sin(aiValue * 2 * math.pi);
    _corePaint
      ..color = color.withValues(alpha: 0.5 + 0.4 * breath)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      6 + 4 * breath,
      _corePaint,
    );
    // Restore the original blur radius for the next caller.
    _corePaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  }

  void _paintHalo(
    Canvas canvas,
    Offset center,
    Size size,
    Color color,
  ) {
    _haloPaint.color = color.withValues(alpha: isDark ? 0.18 : 0.12);
    canvas.drawCircle(center, size.width * 0.32, _haloPaint);
  }

  /// Two-sine envelope that mimics natural speech rhythm.
  double _waveNoise(int barIndex, VoiceModePhase phase, double t) {
    final phaseOffset = barIndex * 0.45;
    switch (phase) {
      case VoiceModePhase.listening:
        return 0.5 + 0.5 * math.sin(t * 0.6 + phaseOffset);
      case VoiceModePhase.speaking:
        final a = math.sin(t * 1.3 + phaseOffset);
        final b = math.sin(t * 2.7 + phaseOffset * 1.7);
        return 0.5 + 0.35 * a + 0.25 * b;
      case VoiceModePhase.idle:
        return 0.5 + 0.5 * math.sin(t + phaseOffset);
      case VoiceModePhase.error:
      case VoiceModePhase.processing:
        return 0.5;
    }
  }

  double _aiEnvelope() {
    final t = aiValue;
    final wave = 0.55 + 0.45 * math.sin(t * 2 * math.pi * 4);
    final breath = 0.4 + 0.6 * math.sin(t * 2 * math.pi);
    return (wave * breath).clamp(0.05, 1.0);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return phase != oldDelegate.phase ||
        micLevel != oldDelegate.micLevel ||
        aiValue != oldDelegate.aiValue ||
        isDark != oldDelegate.isDark;
  }
}