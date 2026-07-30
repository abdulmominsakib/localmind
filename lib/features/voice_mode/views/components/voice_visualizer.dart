import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../providers/voice_mode_provider.dart';
import '../../voice_mode_palette.dart';

/// Real-time glowing orb visualizer with organic wave rings.
///
/// Displays a 3D gradient spherical orb surrounded by fluid, morphing wave
/// layers that pulse and rotate in response to speech (listening/speaking).
/// Features frame-by-frame smoothing to prevent flickering during listening.
class VoiceVisualizer extends StatefulWidget {
  final VoiceModePhase phase;
  final double size;

  /// Current microphone input level in 0..1 (listening phase).
  final double micLevel;

  const VoiceVisualizer({
    super.key,
    required this.phase,
    this.size = 240,
    this.micLevel = 0,
  });

  @override
  State<VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<VoiceVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  double _smoothedMicLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
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
          // Smooth the mic level frame-by-frame to eliminate jitter/flicker.
          final targetMic = widget.phase == VoiceModePhase.listening
              ? widget.micLevel.clamp(0.0, 1.0)
              : 0.0;
          _smoothedMicLevel =
              lerpDouble(_smoothedMicLevel, targetMic, 0.14) ?? 0.0;

          return CustomPaint(
            painter: _OrbWavePainter(
              phase: widget.phase,
              micLevel: _smoothedMicLevel,
              progress: _ticker.value,
              isDark: isDark,
            ),
          );
        },
      ),
    );
  }
}

class _OrbWavePainter extends CustomPainter {
  final VoiceModePhase phase;
  final double micLevel;
  final double progress;
  final bool isDark;

  _OrbWavePainter({
    required this.phase,
    required this.micLevel,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.28;
    final time = progress * 2 * math.pi;

    final amp = _computeAmplitude();
    final accent = VoiceModePalette.accentFor(phase, isDark: isDark);

    // 1. Paint background ambient glow halo
    _paintHalo(canvas, center, baseRadius, amp, accent);

    // 2. Paint outer organic translucent wave rings
    _paintOuterWaveRings(canvas, center, baseRadius, time, amp);

    // 3. Paint main 3D gradient orb core with inner fluid waves & highlights
    _paintOrbCore(canvas, center, baseRadius, time, amp);
  }

  double _computeAmplitude() {
    switch (phase) {
      case VoiceModePhase.listening:
        return micLevel;
      case VoiceModePhase.speaking:
        // Speech rhythm simulation with dual sine waves
        final wave = 0.5 + 0.5 * math.sin(progress * 2 * math.pi * 3.5);
        final breath = 0.4 + 0.6 * math.sin(progress * 2 * math.pi * 1.2);
        return (wave * breath).clamp(0.1, 1.0);
      case VoiceModePhase.processing:
        return 0.2 + 0.15 * math.sin(progress * 2 * math.pi * 2.0);
      case VoiceModePhase.idle:
        return 0.06 + 0.04 * math.sin(progress * 2 * math.pi);
      case VoiceModePhase.error:
        return 0.08 + 0.04 * math.sin(progress * 2 * math.pi * 1.5);
    }
  }

  void _paintHalo(
    Canvas canvas,
    Offset center,
    double baseRadius,
    double amp,
    Color accent,
  ) {
    final haloRadius = baseRadius * (1.4 + 0.3 * amp);
    final isError = phase == VoiceModePhase.error;
    final haloPaint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseRadius * 0.6)
      ..shader = RadialGradient(
        colors: isError
            ? [
                const Color(0xFFEF4444).withValues(alpha: isDark ? 0.25 : 0.20),
                const Color(0xFFF87171).withValues(alpha: 0.12),
                const Color(0xFFFECDD3).withValues(alpha: 0.06),
                Colors.transparent,
              ]
            : [
                accent.withValues(alpha: isDark ? 0.35 : 0.28),
                const Color(0xFFE879F9).withValues(alpha: 0.20),
                const Color(0xFF38BDF8).withValues(alpha: 0.12),
                Colors.transparent,
              ],
        stops: const [0.0, 0.4, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: haloRadius));

    canvas.drawCircle(center, haloRadius, haloPaint);
  }

  void _paintOuterWaveRings(
    Canvas canvas,
    Offset center,
    double baseRadius,
    double time,
    double amp,
  ) {
    final isError = phase == VoiceModePhase.error;

    // 3 distinct wave rings with different rotation speeds, harmonic frequencies, and soft pastel gradients
    final rings = [
      _RingConfig(
        baseScale: 1.12,
        waveAmp: 14.0 * (0.3 + 0.7 * amp),
        frequency: 3,
        rotSpeed: 0.6,
        timeScale: 1.2,
        colors: isError
            ? [
                const Color(0xFFFECDD3).withValues(alpha: 0.40),
                const Color(0xFFF87171).withValues(alpha: 0.30),
                const Color(0xFFEF4444).withValues(alpha: 0.18),
              ]
            : [
                const Color(0xFF38BDF8).withValues(alpha: 0.45),
                const Color(0xFFE879F9).withValues(alpha: 0.35),
                const Color(0xFF818CF8).withValues(alpha: 0.25),
              ],
        strokeColor: isError
            ? const Color(0xFFF87171).withValues(alpha: 0.50)
            : const Color(0xFF38BDF8).withValues(alpha: 0.6),
      ),
      _RingConfig(
        baseScale: 1.22,
        waveAmp: 18.0 * (0.3 + 0.7 * amp),
        frequency: 2,
        rotSpeed: -0.8,
        timeScale: 1.6,
        colors: isError
            ? [
                const Color(0xFFFCA5A5).withValues(alpha: 0.35),
                const Color(0xFFEF4444).withValues(alpha: 0.25),
                const Color(0xFFDC2626).withValues(alpha: 0.15),
              ]
            : [
                const Color(0xFFF472B6).withValues(alpha: 0.40),
                const Color(0xFFA78BFA).withValues(alpha: 0.30),
                const Color(0xFF34D399).withValues(alpha: 0.20),
              ],
        strokeColor: isError
            ? const Color(0xFFFCA5A5).withValues(alpha: 0.45)
            : const Color(0xFFF472B6).withValues(alpha: 0.55),
      ),
      _RingConfig(
        baseScale: 1.34,
        waveAmp: 22.0 * (0.2 + 0.8 * amp),
        frequency: 4,
        rotSpeed: 0.4,
        timeScale: 0.9,
        colors: isError
            ? [
                const Color(0xFFF87171).withValues(alpha: 0.30),
                const Color(0xFFFECDD3).withValues(alpha: 0.22),
                const Color(0xFFEF4444).withValues(alpha: 0.12),
              ]
            : [
                const Color(0xFF818CF8).withValues(alpha: 0.35),
                const Color(0xFF38BDF8).withValues(alpha: 0.30),
                const Color(0xFFFFAEE2).withValues(alpha: 0.20),
              ],
        strokeColor: isError
            ? const Color(0xFFF87171).withValues(alpha: 0.40)
            : const Color(0xFF818CF8).withValues(alpha: 0.5),
      ),
    ];

    for (final ring in rings) {
      final path = Path();
      const points = 72;
      final ringRadius = baseRadius * ring.baseScale;

      for (int i = 0; i <= points; i++) {
        final theta = (i / points) * 2 * math.pi;
        final rotAngle = time * ring.rotSpeed;
        final angle = theta + rotAngle;

        final wave1 = math.sin(theta * ring.frequency + time * ring.timeScale);
        final wave2 = math.cos(
          theta * (ring.frequency + 1) - time * ring.timeScale * 0.7,
        );
        final r = ringRadius + (wave1 * 0.6 + wave2 * 0.4) * ring.waveAmp;

        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();

      // Draw translucent gradient fill
      final bounds = path.getBounds();
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ring.colors,
        ).createShader(bounds);
      canvas.drawPath(path, fillPaint);

      // Draw glowing stroke outline
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = ring.strokeColor;
      canvas.drawPath(path, strokePaint);
    }
  }

  void _paintOrbCore(
    Canvas canvas,
    Offset center,
    double baseRadius,
    double time,
    double amp,
  ) {
    final orbRadius = baseRadius * (0.95 + 0.15 * amp);
    final orbRect = Rect.fromCircle(center: center, radius: orbRadius);
    final isError = phase == VoiceModePhase.error;

    // Primary 3D gradient sphere shader with reduced opacity for error mode
    final orbGradient = RadialGradient(
      center: const Alignment(-0.35, -0.45),
      radius: 1.15,
      colors: isError
          ? [
              const Color(0xFFFECDD3).withValues(alpha: 0.65), // Translucent soft rose top
              const Color(0xFFF87171).withValues(alpha: 0.55), // Coral red
              const Color(0xFFEF4444).withValues(alpha: 0.45), // Soft red
              const Color(0xFFDC2626).withValues(alpha: 0.35), // Translucent crimson edge
            ]
          : const [
              Color(0xFFFFAEE2), // Light peach pink top highlight
              Color(0xFFF472B6), // Vibrant pink
              Color(0xFFE879F9), // Soft orchid / magenta
              Color(0xFFA78BFA), // Rich lavender purple
              Color(0xFF38BDF8), // Electric cyan bottom
              Color(0xFF0284C7), // Deep blue edge
            ],
      stops: isError
          ? const [0.0, 0.35, 0.70, 1.0]
          : const [0.0, 0.22, 0.45, 0.68, 0.88, 1.0],
    );

    final orbPaint = Paint()
      ..shader = orbGradient.createShader(orbRect);

    // Save layer for clipping inner liquid waves
    canvas.save();
    final orbPath = Path()..addOval(orbRect);
    canvas.clipPath(orbPath);

    // Draw main gradient sphere body
    canvas.drawCircle(center, orbRadius, orbPaint);

    // Draw inner morphing liquid wave shimmer
    _paintInnerLiquidWaves(canvas, center, orbRadius, time, amp);

    // Draw top specular 3D light reflection
    final specularPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.55),
        radius: 0.65,
        colors: [
          Colors.white.withValues(alpha: 0.65),
          Colors.white.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(orbRect);

    canvas.drawCircle(center, orbRadius, specularPaint);

    canvas.restore(); // Restore clip

    // Crisp outer edge glow ring
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isError
            ? [
                Colors.white.withValues(alpha: 0.60),
                const Color(0xFFF87171).withValues(alpha: 0.45),
                const Color(0xFFEF4444).withValues(alpha: 0.30),
                Colors.white.withValues(alpha: 0.20),
              ]
            : [
                Colors.white.withValues(alpha: 0.70),
                const Color(0xFF38BDF8).withValues(alpha: 0.50),
                const Color(0xFFE879F9).withValues(alpha: 0.40),
                Colors.white.withValues(alpha: 0.20),
              ],
      ).createShader(orbRect);

    canvas.drawCircle(center, orbRadius, borderPaint);
  }

  void _paintInnerLiquidWaves(
    Canvas canvas,
    Offset center,
    double radius,
    double time,
    double amp,
  ) {
    final isError = phase == VoiceModePhase.error;
    final wavePath = Path();
    final yOffset = center.dy + radius * 0.15 * math.sin(time * 1.5);
    final waveHeight = radius * (0.25 + 0.3 * amp);

    wavePath.moveTo(center.dx - radius, center.dy + radius);
    wavePath.lineTo(center.dx - radius, yOffset);

    const steps = 40;
    for (int i = 0; i <= steps; i++) {
      final x = center.dx - radius + (i / steps) * (2 * radius);
      final normalizedX = (i / steps) * 2 * math.pi;
      final y = yOffset +
          math.sin(normalizedX * 2 + time * 2.5) * waveHeight * 0.5 +
          math.cos(normalizedX * 3 - time * 1.8) * waveHeight * 0.3;
      wavePath.lineTo(x, y);
    }

    wavePath.lineTo(center.dx + radius, center.dy + radius);
    wavePath.close();

    final liquidPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isError
            ? [
                const Color(0xFFF87171).withValues(alpha: 0.30),
                const Color(0xFFFECDD3).withValues(alpha: 0.20),
                Colors.transparent,
              ]
            : [
                const Color(0xFF38BDF8).withValues(alpha: 0.35),
                const Color(0xFFE879F9).withValues(alpha: 0.25),
                Colors.transparent,
              ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawPath(wavePath, liquidPaint);
  }

  @override
  bool shouldRepaint(covariant _OrbWavePainter oldDelegate) {
    return phase != oldDelegate.phase ||
        micLevel != oldDelegate.micLevel ||
        progress != oldDelegate.progress ||
        isDark != oldDelegate.isDark;
  }
}

class _RingConfig {
  final double baseScale;
  final double waveAmp;
  final int frequency;
  final double rotSpeed;
  final double timeScale;
  final List<Color> colors;
  final Color strokeColor;

  _RingConfig({
    required this.baseScale,
    required this.waveAmp,
    required this.frequency,
    required this.rotSpeed,
    required this.timeScale,
    required this.colors,
    required this.strokeColor,
  });
}