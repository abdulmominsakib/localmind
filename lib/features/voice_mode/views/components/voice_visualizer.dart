import 'dart:math';

import 'package:flutter/material.dart';

import '../../providers/voice_mode_provider.dart';

/// Animated visual indicator that changes appearance based on the
/// current [VoiceModePhase]. Uses [CustomPainter] for smooth,
/// GPU-friendly rendering.
class VoiceVisualizer extends StatefulWidget {
  final VoiceModePhase phase;
  final double size;

  const VoiceVisualizer({
    super.key,
    required this.phase,
    this.size = 220,
  });

  @override
  State<VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<VoiceVisualizer>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _orbitController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _syncAnimations(widget.phase);
  }

  @override
  void didUpdateWidget(VoiceVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _syncAnimations(widget.phase);
    }
  }

  void _syncAnimations(VoiceModePhase phase) {
    // Stop all first.
    _pulseController.stop();
    _orbitController.stop();
    _waveController.stop();

    switch (phase) {
      case VoiceModePhase.listening:
        _pulseController.repeat(reverse: true);
      case VoiceModePhase.processing:
        _orbitController.repeat();
      case VoiceModePhase.speaking:
        _waveController.repeat();
      case VoiceModePhase.idle:
      case VoiceModePhase.error:
        // Gentle idle pulse.
        _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _orbitController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _pulseController,
          _orbitController,
          _waveController,
        ]),
        builder: (context, _) {
          return CustomPaint(
            painter: _VoicePainter(
              phase: widget.phase,
              pulseValue: _pulseController.value,
              orbitValue: _orbitController.value,
              waveValue: _waveController.value,
              isDark: Theme.of(context).brightness == Brightness.dark,
            ),
          );
        },
      ),
    );
  }
}

class _VoicePainter extends CustomPainter {
  final VoiceModePhase phase;
  final double pulseValue;
  final double orbitValue;
  final double waveValue;
  final bool isDark;

  _VoicePainter({
    required this.phase,
    required this.pulseValue,
    required this.orbitValue,
    required this.waveValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    switch (phase) {
      case VoiceModePhase.listening:
        _paintListening(canvas, center, maxRadius);
      case VoiceModePhase.processing:
        _paintProcessing(canvas, center, maxRadius);
      case VoiceModePhase.speaking:
        _paintSpeaking(canvas, center, maxRadius);
      case VoiceModePhase.idle:
        _paintIdle(canvas, center, maxRadius);
      case VoiceModePhase.error:
        _paintError(canvas, center, maxRadius);
    }
  }

  void _paintListening(Canvas canvas, Offset center, double maxRadius) {
    final baseColor = isDark
        ? const Color(0xFF6366F1) // Indigo
        : const Color(0xFF4F46E5);

    // Concentric pulsing rings.
    for (int i = 0; i < 4; i++) {
      final progress = (pulseValue + i * 0.2) % 1.0;
      final radius = maxRadius * 0.3 + maxRadius * 0.6 * progress;
      final alpha = (1.0 - progress) * 0.4;

      final paint = Paint()
        ..color = baseColor.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 - (progress * 1.5);

      canvas.drawCircle(center, radius, paint);
    }

    // Inner glowing core.
    final corePaint = Paint()
      ..color = baseColor.withValues(alpha: 0.6 + pulseValue * 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, maxRadius * 0.18, corePaint);

    final solidCore = Paint()..color = baseColor;
    canvas.drawCircle(center, maxRadius * 0.12, solidCore);
  }

  void _paintProcessing(Canvas canvas, Offset center, double maxRadius) {
    final baseColor = isDark
        ? const Color(0xFFA78BFA) // Violet
        : const Color(0xFF7C3AED);

    // Orbiting dots.
    const dotCount = 8;
    for (int i = 0; i < dotCount; i++) {
      final angle = (orbitValue * 2 * pi) + (i * 2 * pi / dotCount);
      final orbitRadius = maxRadius * 0.45;
      final dotX = center.dx + cos(angle) * orbitRadius;
      final dotY = center.dy + sin(angle) * orbitRadius;

      final trailAlpha = 0.3 + (0.7 * (i / dotCount));
      final dotRadius = 4.0 + (3.0 * (i / dotCount));

      final paint = Paint()
        ..color = baseColor.withValues(alpha: trailAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, dotRadius * 0.5);

      canvas.drawCircle(Offset(dotX, dotY), dotRadius, paint);
    }

    // Second ring going the opposite direction.
    for (int i = 0; i < 5; i++) {
      final angle = -(orbitValue * 1.5 * 2 * pi) + (i * 2 * pi / 5);
      final orbitRadius = maxRadius * 0.65;
      final dotX = center.dx + cos(angle) * orbitRadius;
      final dotY = center.dy + sin(angle) * orbitRadius;

      final trailAlpha = 0.15 + (0.35 * (i / 5));

      final paint = Paint()
        ..color = baseColor.withValues(alpha: trailAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      canvas.drawCircle(Offset(dotX, dotY), 3, paint);
    }

    // Center pulse.
    final corePulse = (sin(orbitValue * 2 * pi) + 1) / 2;
    final corePaint = Paint()
      ..color = baseColor.withValues(alpha: 0.3 + corePulse * 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(center, maxRadius * 0.15, corePaint);
  }

  void _paintSpeaking(Canvas canvas, Offset center, double maxRadius) {
    final baseColor = isDark
        ? const Color(0xFF34D399) // Emerald
        : const Color(0xFF059669);

    // Equalizer-style bars arranged in a circular pattern.
    const barCount = 24;
    for (int i = 0; i < barCount; i++) {
      final angle = (i * 2 * pi / barCount) - pi / 2;
      final phaseOffset = sin(waveValue * 2 * pi + i * 0.5);
      final barHeight = maxRadius * 0.15 + maxRadius * 0.3 * ((phaseOffset + 1) / 2);

      final innerRadius = maxRadius * 0.3;
      final outerRadius = innerRadius + barHeight;

      final startX = center.dx + cos(angle) * innerRadius;
      final startY = center.dy + sin(angle) * innerRadius;
      final endX = center.dx + cos(angle) * outerRadius;
      final endY = center.dy + sin(angle) * outerRadius;

      final barAlpha = 0.3 + 0.6 * ((phaseOffset + 1) / 2);

      final paint = Paint()
        ..color = baseColor.withValues(alpha: barAlpha)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }

    // Inner glow.
    final corePaint = Paint()
      ..color = baseColor.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(center, maxRadius * 0.2, corePaint);

    final solidCore = Paint()..color = baseColor.withValues(alpha: 0.8);
    canvas.drawCircle(center, maxRadius * 0.1, solidCore);
  }

  void _paintIdle(Canvas canvas, Offset center, double maxRadius) {
    final baseColor = isDark
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.15);

    // Gentle breathing circle.
    final radius = maxRadius * 0.2 + maxRadius * 0.05 * pulseValue;
    final paint = Paint()
      ..color = baseColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius, paint);

    // Thin outer ring.
    final ringPaint = Paint()
      ..color = baseColor.withValues(alpha: 0.15 + pulseValue * 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, maxRadius * 0.5, ringPaint);
  }

  void _paintError(Canvas canvas, Offset center, double maxRadius) {
    final baseColor = const Color(0xFFEF4444);

    // Pulsing red glow.
    final radius = maxRadius * 0.2 + maxRadius * 0.05 * pulseValue;
    final paint = Paint()
      ..color = baseColor.withValues(alpha: 0.4 + pulseValue * 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius, paint);

    final solidCore = Paint()..color = baseColor.withValues(alpha: 0.7);
    canvas.drawCircle(center, maxRadius * 0.1, solidCore);
  }

  @override
  bool shouldRepaint(covariant _VoicePainter oldDelegate) {
    return phase != oldDelegate.phase ||
        pulseValue != oldDelegate.pulseValue ||
        orbitValue != oldDelegate.orbitValue ||
        waveValue != oldDelegate.waveValue ||
        isDark != oldDelegate.isDark;
  }
}
