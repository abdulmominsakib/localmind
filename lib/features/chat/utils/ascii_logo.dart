import 'dart:math' as math;

import 'package:localmind/features/chat/utils/ascii_logo_data.dart';

export 'package:localmind/features/chat/utils/ascii_logo_data.dart'
    show asciiLogoColumns, asciiLogoRows;

/// The mark the new-chat screen draws for the active connection.
enum AsciiLogo { localMind, lmStudio, ollama, server, openRouter, requesty }

/// Ticks spent on the scrambled reveal before a logo's own loop starts.
const asciiLogoIntroTicks = 16;

/// Time between animation ticks (12.5 fps — enough for ASCII, cheap to build).
const asciiLogoTickInterval = Duration(milliseconds: 80);

/// One frame of a logo as two layers of equal size: [base] in the logo's
/// color, [highlight] in its accent. A cell is filled in at most one layer.
class AsciiLogoFrame {
  const AsciiLogoFrame({required this.base, required this.highlight});

  final List<String> base;
  final List<String> highlight;
}

List<String> asciiLogoMask(AsciiLogo logo) => switch (logo) {
  AsciiLogo.localMind => localMindMask,
  AsciiLogo.lmStudio => lmStudioMask,
  AsciiLogo.ollama => ollamaMask,
  AsciiLogo.server => serverMask,
  AsciiLogo.openRouter => openRouterMask,
  AsciiLogo.requesty => requestyMask,
};

/// Builds [logo] at [tick]. A null tick is the still logo, used when the
/// platform asks for reduced motion.
AsciiLogoFrame asciiLogoFrame(AsciiLogo logo, int? tick) {
  final base = [for (final row in asciiLogoMask(logo)) row.split('')];
  final highlight = [for (final row in base) List.filled(row.length, ' ')];

  if (tick != null) {
    if (tick < asciiLogoIntroTicks) {
      _scramble(base, tick);
    } else {
      final t = tick - asciiLogoIntroTicks;
      switch (logo) {
        case AsciiLogo.localMind:
          _pulse(base, highlight, t);
        case AsciiLogo.lmStudio:
          _slideBars(base, t);
        case AsciiLogo.ollama:
          _blink(base, t);
        case AsciiLogo.server:
          _serverActivity(base, highlight, t);
        case AsciiLogo.openRouter:
          _sweep(base, highlight, t);
        case AsciiLogo.requesty:
          _blinkCursor(base, t);
      }
    }
  }

  return AsciiLogoFrame(
    base: [for (final row in base) row.join()],
    highlight: [for (final row in highlight) row.join()],
  );
}

const _glitch = '!<>-_/[]{}=+*^?#';

/// Stable pseudo-random value in [0, 1) for a cell and a seed.
double _noise(num a, num b, num c) {
  final x = math.sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453;
  return x - x.floorToDouble();
}

/// Each inked cell shows random glyphs until its own moment to settle.
void _scramble(List<List<String>> base, int tick) {
  final progress = tick / asciiLogoIntroTicks;
  for (var r = 0; r < base.length; r++) {
    for (var c = 0; c < base[r].length; c++) {
      if (base[r][c] == ' ' || _noise(r, c, 0) <= progress) continue;
      base[r][c] = _glitch[(_noise(r, c, tick) * _glitch.length).floor()];
    }
  }
}

/// Height of a cell over its width, in the logo images' pixels: the grids
/// are sampled from square crops, so a row is this many columns tall.
const _cellAspect = asciiLogoColumns / asciiLogoRows;

/// LocalMind: a ring spreads out from the centre, with the odd spark.
void _pulse(List<List<String>> base, List<List<String>> highlight, int t) {
  const centerColumn = asciiLogoColumns / 2;
  const centerRow = asciiLogoRows / 2;
  final radius = (t * 1.0) % 62;
  for (var r = 0; r < base.length; r++) {
    for (var c = 0; c < base[r].length; c++) {
      final distance = math.sqrt(
        math.pow(c - centerColumn, 2) +
            math.pow((r - centerRow) * _cellAspect, 2),
      );
      if (base[r][c] != ' ' && (distance - radius).abs() < 2.2) {
        highlight[r][c] = base[r][c];
        base[r][c] = ' ';
      } else if (base[r][c] == ' ' &&
          distance < 32 &&
          _noise(r, c, t ~/ 4) < 0.006) {
        highlight[r][c] = '.';
      }
    }
  }
}

/// LM Studio: each bar drifts on its own phase.
void _slideBars(List<List<String>> base, int t) {
  for (var r = 0; r < base.length; r++) {
    final bar = lmStudioBarOfRow[r];
    final shift = (4.3 * math.sin(t * 0.16 + bar * 1.1)).round();
    final row = base[r];
    base[r] = shift >= 0
        ? [...List.filled(shift, ' '), ...row.take(row.length - shift)]
        : [...row.skip(-shift), ...List.filled(-shift, ' ')];
  }
}

/// Ollama: the llama blinks every few seconds.
void _blink(List<List<String>> base, int t) {
  if (t % 46 >= 3) return;
  for (final (r, c, glyph) in ollamaBlink) {
    base[r][c] = glyph;
  }
}

/// Generic server: status lights flicker and activity runs along each unit.
void _serverActivity(
  List<List<String>> base,
  List<List<String>> highlight,
  int t,
) {
  for (final (i, (r, c)) in serverLights.indexed) {
    if (_noise(i, 0, t ~/ 5) > 0.4) {
      highlight[r][c] = base[r][c] == ' ' ? '@' : base[r][c];
      base[r][c] = ' ';
    }
  }
  for (final (i, (r, from, to)) in serverPackets.indexed) {
    final span = to - from + 1;
    final head = from + (t + i * 7) % span;
    for (var c = head; c < head + 3 && c <= to; c++) {
      highlight[r][c] = '#';
      base[r][c] = ' ';
    }
  }
}

/// OpenRouter: a diagonal shine sweeps across the mark.
void _sweep(List<List<String>> base, List<List<String>> highlight, int t) {
  for (var r = 0; r < base.length; r++) {
    for (var c = 0; c < base[r].length; c++) {
      final position = (c + r * _cellAspect - t * 2.3) % 144;
      if (base[r][c] != ' ' && position < 5) {
        highlight[r][c] = '/';
        base[r][c] = ' ';
      }
    }
  }
}

/// Requesty: the `_` of the prompt blinks like a terminal cursor.
void _blinkCursor(List<List<String>> base, int t) {
  if ((t ~/ 6).isEven) return;
  for (final (r, c) in requestyCursor) {
    base[r][c] = '@';
  }
}
