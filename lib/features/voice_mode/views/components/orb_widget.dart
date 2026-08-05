import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Animated glowing orb, rendered entirely with a GLSL fragment shader
/// (`assets/shaders/orb.frag`).
///
/// Features:
/// - Real-time audio reactivity: size pulses dynamically when speaking or listening.
/// - Continuous elapsed time clock (prevents time-reset jumps / flickering).
/// - Cached native [ui.FragmentShader] instance (eliminates GPU allocation churn).
class OrbWidget extends StatefulWidget {
  const OrbWidget({
    super.key,
    this.diameter = 230,
    this.baseColor,
    this.glowColor,
    this.micLevel = 0.0,
    this.isSpeaking = false,
    this.isListening = false,
    this.scale,
  });

  final double diameter;
  final Color? baseColor;
  final Color? glowColor;

  /// Microphone volume input level (0.0 to 1.0) when listening.
  final double micLevel;

  /// Whether the AI/TTS system is currently speaking.
  final bool isSpeaking;

  /// Whether the system is currently listening for user input.
  final bool isListening;

  /// Explicit override scale factor. If null, automatically computed from phase.
  final double? scale;

  @override
  State<OrbWidget> createState() => _OrbWidgetState();
}

class _OrbWidgetState extends State<OrbWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'assets/shaders/orb.frag',
      );
      if (mounted) {
        setState(() {
          _shader = program.fragmentShader();
        });
      }
    } catch (_) {
      // Graceful fallback if GLSL shader is unsupported on current backend
    }
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = widget.baseColor ?? theme.colorScheme.primaryContainer;
    final glowColor = widget.glowColor ?? theme.colorScheme.secondary;

    final shader = _shader;
    if (shader == null) {
      return SizedBox(width: widget.diameter, height: widget.diameter);
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          final time = _stopwatch.elapsedMicroseconds / 1000000.0;
          return CustomPaint(
            size: Size.square(widget.diameter),
            painter: _OrbPainter(
              shader: shader,
              time: time,
              baseColor: baseColor,
              glowColor: glowColor,
              micLevel: widget.micLevel,
              isSpeaking: widget.isSpeaking,
              isListening: widget.isListening,
              customScale: widget.scale,
            ),
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({
    required this.shader,
    required this.time,
    required this.baseColor,
    required this.glowColor,
    required this.micLevel,
    required this.isSpeaking,
    required this.isListening,
    this.customScale,
  });

  final ui.FragmentShader shader;
  final double time;
  final Color baseColor;
  final Color glowColor;
  final double micLevel;
  final bool isSpeaking;
  final bool isListening;
  final double? customScale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Compute dynamic scaling when speaking or listening
    double pulseScale = customScale ?? 1.0;
    if (customScale == null) {
      if (isListening) {
        // Enlarge dynamically with mic volume input
        final clampedMic = micLevel.clamp(0.0, 1.0);
        pulseScale = 1.0 + (math.pow(clampedMic, 0.75) * 0.20);
      } else if (isSpeaking) {
        // Organic breathing pulsation synced with TTS speech cadence
        final cadence = 0.5 + 0.5 * (math.sin(time * 7.2) * math.sin(time * 3.4));
        pulseScale = 1.0 + (cadence * 0.16);
      }
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(pulseScale);
    canvas.translate(-center.dx, -center.dy);

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, baseColor.r)
      ..setFloat(4, baseColor.g)
      ..setFloat(5, baseColor.b)
      ..setFloat(6, glowColor.r)
      ..setFloat(7, glowColor.g)
      ..setFloat(8, glowColor.b);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = shader,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.glowColor != glowColor ||
      oldDelegate.micLevel != micLevel ||
      oldDelegate.isSpeaking != isSpeaking ||
      oldDelegate.isListening != isListening ||
      oldDelegate.customScale != customScale ||
      oldDelegate.shader != shader;
}
