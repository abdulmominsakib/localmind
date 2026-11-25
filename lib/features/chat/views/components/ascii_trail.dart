import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// What an [AsciiTrail] is showing.
enum AsciiTrailKind {
  /// Bars that fill in toward the status label as the prompt is read.
  processing,

  /// A slow, sparse twinkle while the model reasons.
  thinking,

  /// A wave flowing out from the label, like tokens streaming out.
  generating,
}

/// Which side of the status label the trail sits on. Each side's inner end
/// faces the label.
enum AsciiTrailSide { start, end }

const _waveRamp = ' .:-=+*';
const _frameStep = Duration(milliseconds: 80);

/// One frame of a trail [width] characters wide, written for the start
/// side: index 0 is the outer edge, the last index touches the label.
/// [ticks] counts [_frameStep]s since the animation began; [progress] is
/// the prompt-reading progress, 0 to 1, for [AsciiTrailKind.processing].
@visibleForTesting
String asciiTrailFrame(
  AsciiTrailKind kind,
  int width, {
  required int ticks,
  double progress = 0,
}) {
  if (width <= 0) return '';
  final chars = List<String>.filled(width, ' ');
  switch (kind) {
    case AsciiTrailKind.processing:
      final filled = (progress.clamp(0.0, 1.0) * width).floor();
      for (var i = 0; i < width; i++) {
        chars[i] = i < filled ? '=' : '.';
      }
      // The bar's head blinks while it waits for more of the prompt.
      if (filled < width) chars[filled] = ticks.isEven ? '>' : '-';
    case AsciiTrailKind.thinking:
      for (var i = 0; i < width; i++) {
        // A cheap hash per cell and slow time step: a few cells glow at once.
        final h = ((i * 73856093) ^ ((ticks ~/ 4) * 19349663)) & 0xff;
        chars[i] = h < 14 ? '*' : (h < 40 ? '.' : ' ');
      }
    case AsciiTrailKind.generating:
      for (var i = 0; i < width; i++) {
        // Distance from the label grows toward index 0; the phase moves
        // outward over time.
        final d = width - 1 - i;
        final wave = math.sin(d * 0.55 - ticks * 0.6);
        final level = ((wave + 1) / 2 * (_waveRamp.length - 1)).round();
        chars[i] = _waveRamp[level];
      }
  }
  return chars.join();
}

/// An animated line of ASCII that fills the empty room beside the composer's
/// live status. It fades toward its outer edge and holds still when the
/// platform asks for reduced motion.
class AsciiTrail extends StatefulWidget {
  const AsciiTrail({
    super.key,
    required this.kind,
    required this.side,
    this.progress = 0,
    this.color,
    this.fontSize = 11,
  });

  final AsciiTrailKind kind;
  final AsciiTrailSide side;
  final double progress;
  final Color? color;
  final double fontSize;

  @override
  State<AsciiTrail> createState() => _AsciiTrailState();
}

class _AsciiTrailState extends State<AsciiTrail>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  int _ticks = 0;

  void _onTick(Duration elapsed) {
    final ticks = elapsed.inMilliseconds ~/ _frameStep.inMilliseconds;
    if (ticks != _ticks) setState(() => _ticks = ticks);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _ticker.isActive) {
      _ticker.stop();
    } else if (!still && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['Courier', 'monospace'],
      fontSize: widget.fontSize,
      height: 1,
      color: color,
    );
    final charWidth = _charWidth(style);
    final atStart = widget.side == AsciiTrailSide.start;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth / charWidth).floor();
        var line = asciiTrailFrame(
          widget.kind,
          width,
          ticks: _ticks,
          progress: widget.progress,
        );
        if (!atStart) line = _mirror(line);
        return ExcludeSemantics(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: atStart ? Alignment.centerLeft : Alignment.centerRight,
              end: atStart ? Alignment.centerRight : Alignment.centerLeft,
              colors: const [Color(0x00000000), Color(0xFF000000)],
              stops: const [0.0, 0.7],
            ).createShader(bounds),
            child: Text(
              line,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              textAlign: atStart ? TextAlign.right : TextAlign.left,
              style: style,
            ),
          ),
        );
      },
    );
  }

  double _charWidth(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w > 0 ? w : style.fontSize! * 0.6;
  }

  static String _mirror(String line) => String.fromCharCodes(
    line.codeUnits.reversed.map(
      (c) => switch (c) {
        0x3E => 0x3C, // > to <
        _ => c,
      },
    ),
  );
}
