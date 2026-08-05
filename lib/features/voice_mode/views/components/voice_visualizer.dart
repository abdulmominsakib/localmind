import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../providers/voice_mode_provider.dart';
import '../../voice_mode_palette.dart';

/// Premium 3D glowing orb visualizer with hardware-accelerated GLSL shader
/// support and high-performance multi-layer CustomPainter fallback.
///
/// Features:
/// - 4-tier layered glow architecture with additive (`BlendMode.plus`) wave intersections.
/// - Fluid cubic Bezier wave morphing driven by asynchronous harmonic rotation.
/// - Exponential moving average audio reactivity smoothing for jitter-free response.
/// - Smooth phase state transition cross-fading (450ms color & physics interpolation).
/// - Physics-based state behaviors: elastic snap for processing, deflation + shake for error.
class VoiceVisualizer extends StatefulWidget {
  final VoiceModePhase phase;
  final double size;

  /// Current microphone input level in 0..1 (listening phase).
  final double micLevel;

  /// Approximate progress through the spoken response in 0..1.
  ///
  /// TTS does not expose output amplitude, so the shader combines this signal
  /// with a layered speech cadence to keep speaking motion tied to playback.
  final double responseProgress;

  const VoiceVisualizer({
    super.key,
    required this.phase,
    this.size = 240,
    this.micLevel = 0,
    this.responseProgress = 0,
  });

  @override
  State<VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<VoiceVisualizer>
    with TickerProviderStateMixin {
  late final AnimationController _ticker;
  late final AnimationController _transitionController;

  VoiceModePhase _oldPhase = VoiceModePhase.idle;
  VoiceModePhase _currentPhase = VoiceModePhase.idle;

  double _smoothedMicLevel = 0.0;
  final Stopwatch _clock = Stopwatch();
  int _lastFrameMicros = 0;
  FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _oldPhase = widget.phase;
    _currentPhase = widget.phase;

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _clock.start();

    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: 1.0,
    );

    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await FragmentProgram.fromAsset(
        'assets/shaders/orb.frag',
      );
      if (mounted) {
        setState(() {
          _shader = program.fragmentShader();
        });
      }
    } catch (_) {
      // Shader unavailable or uncompiled on target platform; falls back gracefully to CustomPainter.
    }
  }

  @override
  void didUpdateWidget(covariant VoiceVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _oldPhase = oldWidget.phase;
      _currentPhase = widget.phase;
      _transitionController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _clock.stop();
    _ticker.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ticker, _transitionController]),
        builder: (context, _) {
          final nowMicros = _clock.elapsedMicroseconds;
          final elapsedMicros = _lastFrameMicros == 0
              ? 16667
              : nowMicros - _lastFrameMicros;
          _lastFrameMicros = nowMicros;
          final deltaSeconds = (elapsedMicros / Duration.microsecondsPerSecond)
              .clamp(0.0, 0.05);

          // Fast attack preserves responsiveness; slower release prevents
          // speech gaps from making the orb visibly snap or flicker.
          final targetMic = widget.phase == VoiceModePhase.listening
              ? widget.micLevel.clamp(0.0, 1.0)
              : 0.0;
          final smoothingRate = targetMic > _smoothedMicLevel ? 15.0 : 6.5;
          final smoothing = 1.0 - math.exp(-smoothingRate * deltaSeconds);
          _smoothedMicLevel =
              lerpDouble(_smoothedMicLevel, targetMic, smoothing) ?? 0.0;

          final transitionProgress = CurvedAnimation(
            parent: _transitionController,
            curve: Curves.easeInOutCubic,
          ).value;

          return CustomPaint(
            painter: _OrbWavePainter(
              oldPhase: _oldPhase,
              targetPhase: _currentPhase,
              transitionProgress: transitionProgress,
              micLevel: _smoothedMicLevel,
              responseProgress: widget.responseProgress.clamp(0.0, 1.0),
              time: nowMicros / Duration.microsecondsPerSecond,
              isDark: isDark,
              shader: _shader,
            ),
          );
        },
      ),
    );
  }
}

class _OrbWavePainter extends CustomPainter {
  final VoiceModePhase oldPhase;
  final VoiceModePhase targetPhase;
  final double transitionProgress;
  final double micLevel;
  final double responseProgress;
  final double time;
  final bool isDark;
  final FragmentShader? shader;

  _OrbWavePainter({
    required this.oldPhase,
    required this.targetPhase,
    required this.transitionProgress,
    required this.micLevel,
    required this.responseProgress,
    required this.time,
    required this.isDark,
    this.shader,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rawCenter = Offset(size.width / 2, size.height / 2);

    // 1. Calculate Phase Colors with Smooth 450ms Cross-Fade
    final oldAccent = VoiceModePalette.accentFor(oldPhase, isDark: isDark);
    final targetAccent = VoiceModePalette.accentFor(
      targetPhase,
      isDark: isDark,
    );
    final accent = Color.lerp(oldAccent, targetAccent, transitionProgress)!;

    final oldSecondary = VoiceModePalette.secondaryFor(
      oldPhase,
      isDark: isDark,
    );
    final targetSecondary = VoiceModePalette.secondaryFor(
      targetPhase,
      isDark: isDark,
    );
    final secondary = Color.lerp(
      oldSecondary,
      targetSecondary,
      transitionProgress,
    )!;

    // 2. Physics & Scale State Changes
    final oldAmp = _computeAmplitudeFor(
      oldPhase,
      time,
      micLevel,
      responseProgress,
    );
    final targetAmp = _computeAmplitudeFor(
      targetPhase,
      time,
      micLevel,
      responseProgress,
    );
    final amp = lerpDouble(oldAmp, targetAmp, transitionProgress)!;

    // Base radius scale factor
    double scaleFactor = 1.0;
    Offset center = rawCenter;

    // Error Deflation & Horizontal Shake Oscillation
    if (targetPhase == VoiceModePhase.error ||
        oldPhase == VoiceModePhase.error) {
      final errorWeight = targetPhase == VoiceModePhase.error
          ? transitionProgress
          : (1.0 - transitionProgress);
      scaleFactor = lerpDouble(1.0, 0.84, errorWeight)!;
      final shake = math.sin(time * 7.5) * 6.5 * errorWeight;
      center = Offset(rawCenter.dx + shake, rawCenter.dy);
    }

    // Thinking / Processing Inward Elastic Snap Pulse
    if (targetPhase == VoiceModePhase.processing && transitionProgress < 1.0) {
      final elasticSnap = math.sin(transitionProgress * math.pi) * 0.14;
      scaleFactor -= elasticSnap;
    }

    final baseRadius = (size.width * 0.27) * scaleFactor;

    // 3. Render GPU Shader if Available
    if (shader != null) {
      // Dynamic expansion driven by speaking cadence / microphone listening level
      final dynamicScale = scaleFactor * (1.0 + amp * 0.20);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(dynamicScale);
      canvas.translate(-rawCenter.dx, -rawCenter.dy);

      shader!
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, time)
        ..setFloat(3, accent.r)
        ..setFloat(4, accent.g)
        ..setFloat(5, accent.b)
        ..setFloat(6, secondary.r)
        ..setFloat(7, secondary.g)
        ..setFloat(8, secondary.b);

      final shaderPaint = Paint()..shader = shader!;
      canvas.drawRect(
        Offset.zero & size,
        shaderPaint,
      );

      canvas.restore();
      return;
    }

    // 4. CustomPainter Rendering Pipeline
    // A. Multi-Tier Layered Ambient Glow Halos
    _paintMultiLayerHalo(
      canvas,
      center,
      baseRadius,
      time,
      amp,
      accent,
      secondary,
    );

    // B. Outer Organic Translucent Wave Rings with Additive Blend Modes
    _paintAdditiveOuterWaveRings(
      canvas,
      center,
      baseRadius,
      time,
      amp,
      accent,
      secondary,
      size,
    );

    // C. Central 3D Gradient Orb Core with specular light & inner liquid shimmer
    _paint3DOrbCore(canvas, center, baseRadius, time, amp, accent, secondary);
  }

  double _computeAmplitudeFor(
    VoiceModePhase phase,
    double time,
    double mic,
    double responseProgress,
  ) {
    switch (phase) {
      case VoiceModePhase.listening:
        return math.pow(mic, 0.78).toDouble();
      case VoiceModePhase.speaking:
        final playbackPhase = responseProgress * math.pi * 18;
        final syllable = 0.5 + 0.5 * math.sin(time * 7.4 + playbackPhase);
        final texture =
            0.5 + 0.5 * math.sin(time * 12.7 - responseProgress * math.pi * 11);
        return (0.16 + syllable * texture * 0.56).clamp(0.12, 0.82);
      case VoiceModePhase.processing:
        return 0.18 + 0.14 * (0.5 + 0.5 * math.sin(time * 3.6));
      case VoiceModePhase.idle:
        return 0.05 + 0.035 * (0.5 + 0.5 * math.sin(time * 1.1));
      case VoiceModePhase.error:
        return 0.07 + 0.04 * (0.5 + 0.5 * math.sin(time * 2.1));
    }
  }

  void _paintMultiLayerHalo(
    Canvas canvas,
    Offset center,
    double baseRadius,
    double time,
    double amp,
    Color accent,
    Color secondary,
  ) {
    final breathingGlow = 0.35 + 0.15 * math.sin(time * 0.7);

    // Layer 1: Atmospheric Wide Ambient Halo
    final wideRadius = baseRadius * (1.75 + 0.35 * amp);
    final widePaint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseRadius * 0.85)
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: (isDark ? 0.28 : 0.22) * breathingGlow),
          secondary.withValues(alpha: 0.14 * breathingGlow),
          accent.withValues(alpha: 0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: wideRadius));
    canvas.drawCircle(center, wideRadius, widePaint);

    // Layer 2: Saturated Mid-Glow Aura
    final midRadius = baseRadius * (1.4 + 0.25 * amp);
    final midPaint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseRadius * 0.48)
      ..shader = RadialGradient(
        colors: [
          secondary.withValues(alpha: isDark ? 0.38 : 0.30),
          accent.withValues(alpha: 0.22),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: midRadius));
    canvas.drawCircle(center, midRadius, midPaint);

    // Layer 3: Tight High-Intensity Inner Core Glow
    final tightRadius = baseRadius * (1.15 + 0.15 * amp);
    final tightPaint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseRadius * 0.22)
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.40),
          accent.withValues(alpha: 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: tightRadius));
    canvas.drawCircle(center, tightRadius, tightPaint);
  }

  void _paintAdditiveOuterWaveRings(
    Canvas canvas,
    Offset center,
    double baseRadius,
    double time,
    double amp,
    Color accent,
    Color secondary,
    Size canvasSize,
  ) {
    // 4 Asynchronous Counter-Rotating Organic Wave Rings
    final rings = [
      _RingConfig(
        baseScale: 1.14,
        waveAmp: 15.0 * (0.3 + 0.7 * amp),
        frequency: 3,
        rotSpeed: 0.65,
        timeScale: 1.2,
        colors: [
          secondary.withValues(alpha: 0.45),
          accent.withValues(alpha: 0.35),
          const Color(0xFF818CF8).withValues(alpha: 0.20),
        ],
        strokeColor: secondary.withValues(alpha: 0.65),
      ),
      _RingConfig(
        baseScale: 1.25,
        waveAmp: 19.0 * (0.3 + 0.7 * amp),
        frequency: 2,
        rotSpeed: -0.90,
        timeScale: 1.6,
        colors: [
          accent.withValues(alpha: 0.40),
          secondary.withValues(alpha: 0.30),
          const Color(0xFFF472B6).withValues(alpha: 0.18),
        ],
        strokeColor: accent.withValues(alpha: 0.60),
      ),
      _RingConfig(
        baseScale: 1.36,
        waveAmp: 23.0 * (0.2 + 0.8 * amp),
        frequency: 4,
        rotSpeed: 0.45,
        timeScale: 0.95,
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: 0.35),
          accent.withValues(alpha: 0.28),
          secondary.withValues(alpha: 0.15),
        ],
        strokeColor: const Color(0xFF38BDF8).withValues(alpha: 0.55),
      ),
      _RingConfig(
        baseScale: 1.48,
        waveAmp: 27.0 * (0.15 + 0.85 * amp),
        frequency: 5,
        rotSpeed: -0.30,
        timeScale: 1.3,
        colors: [
          secondary.withValues(alpha: 0.30),
          accent.withValues(alpha: 0.22),
          Colors.transparent,
        ],
        strokeColor: secondary.withValues(alpha: 0.45),
      ),
    ];

    // Save Layer with BlendMode.plus for Additive Wave Intersections
    final layerRect = Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
    canvas.saveLayer(layerRect, Paint());

    for (final ring in rings) {
      final path = _generateOrganicCubicBezierPath(
        center,
        baseRadius * ring.baseScale,
        ring.waveAmp,
        ring.frequency,
        ring.rotSpeed,
        ring.timeScale,
        time,
      );

      final bounds = path.getBounds();
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ring.colors,
        ).createShader(bounds.isEmpty ? layerRect : bounds);
      canvas.drawPath(path, fillPaint);

      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = ring.strokeColor;
      canvas.drawPath(path, strokePaint);
    }

    canvas.restore(); // Restore layer
  }

  Path _generateOrganicCubicBezierPath(
    Offset center,
    double ringRadius,
    double waveAmp,
    int frequency,
    double rotSpeed,
    double timeScale,
    double time,
  ) {
    final path = Path();
    const count = 16; // Control point anchors along full circle
    final points = <Offset>[];

    for (int i = 0; i < count; i++) {
      final theta = (i / count) * 2 * math.pi;
      final angle = theta + (time * rotSpeed);

      final w1 = math.sin(theta * frequency + time * timeScale);
      final w2 = math.cos(theta * (frequency + 1) - time * timeScale * 0.75);
      final r = ringRadius + (w1 * 0.6 + w2 * 0.4) * waveAmp;

      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      points.add(Offset(x, y));
    }

    // Smooth Cubic Bezier Loop through Control Points
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < count; i++) {
      final p0 = points[(i - 1 + count) % count];
      final p1 = points[i];
      final p2 = points[(i + 1) % count];
      final p3 = points[(i + 2) % count];

      // Catmull-Rom to Cubic Bezier Conversion for Smooth Liquid Curve
      final control1 = p1 + (p2 - p0) * 0.1666;
      final control2 = p2 - (p3 - p1) * 0.1666;

      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        p2.dx,
        p2.dy,
      );
    }

    path.close();
    return path;
  }

  void _paint3DOrbCore(
    Canvas canvas,
    Offset center,
    double baseRadius,
    double time,
    double amp,
    Color accent,
    Color secondary,
  ) {
    final orbRadius = baseRadius * (0.95 + 0.15 * amp);
    final orbRect = Rect.fromCircle(center: center, radius: orbRadius);

    final gradientStops = VoiceModePalette.sphereGradientFor(
      targetPhase,
      isDark: isDark,
    );
    final orbGradient = RadialGradient(
      center: const Alignment(-0.35, -0.45),
      radius: 1.15,
      colors: gradientStops.length >= 4
          ? [
              Color.lerp(gradientStops[0], accent, 0.1)!,
              gradientStops[1],
              gradientStops[2],
              gradientStops[3],
            ]
          : [accent, secondary],
      stops: const [0.0, 0.32, 0.68, 1.0],
    );

    final orbPaint = Paint()..shader = orbGradient.createShader(orbRect);

    // Save layer for clipping inner liquid waves
    canvas.save();
    final orbPath = Path()..addOval(orbRect);
    canvas.clipPath(orbPath);

    // Main 3D gradient sphere body
    canvas.drawCircle(center, orbRadius, orbPaint);

    // Inner morphing liquid wave shimmer
    _paintInnerLiquidWaves(
      canvas,
      center,
      orbRadius,
      time,
      amp,
      accent,
      secondary,
    );

    // Specular 3D light reflection highlight
    final specularPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.55),
        radius: 0.65,
        colors: [
          Colors.white.withValues(alpha: 0.68),
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(orbRect);

    canvas.drawCircle(center, orbRadius, specularPaint);
    canvas.restore(); // Restore clip

    // Crisp outer edge glow rim ring
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.75),
          accent.withValues(alpha: 0.55),
          secondary.withValues(alpha: 0.40),
          Colors.white.withValues(alpha: 0.25),
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
    Color accent,
    Color secondary,
  ) {
    final wavePath = Path();
    final yOffset = center.dy + radius * 0.15 * math.sin(time * 1.5);
    final waveHeight = radius * (0.25 + 0.35 * amp);

    wavePath.moveTo(center.dx - radius, center.dy + radius);
    wavePath.lineTo(center.dx - radius, yOffset);

    const steps = 40;
    for (int i = 0; i <= steps; i++) {
      final x = center.dx - radius + (i / steps) * (2 * radius);
      final normalizedX = (i / steps) * 2 * math.pi;
      final y =
          yOffset +
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
        colors: [
          secondary.withValues(alpha: 0.35),
          accent.withValues(alpha: 0.20),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawPath(wavePath, liquidPaint);
  }

  @override
  bool shouldRepaint(covariant _OrbWavePainter oldDelegate) {
    return oldPhase != oldDelegate.oldPhase ||
        targetPhase != oldDelegate.targetPhase ||
        transitionProgress != oldDelegate.transitionProgress ||
        micLevel != oldDelegate.micLevel ||
        responseProgress != oldDelegate.responseProgress ||
        time != oldDelegate.time ||
        isDark != oldDelegate.isDark ||
        shader != oldDelegate.shader;
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
