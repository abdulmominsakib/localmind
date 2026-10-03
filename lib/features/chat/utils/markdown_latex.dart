/// gpt_markdown only recognizes `\(...\)` / `\[...\]` for LaTeX, not the
/// `$...$` / `$$...$$` delimiters models most commonly output. Converts the
/// dollar forms to the ones gpt_markdown understands.
///
/// Code is left alone: fenced blocks and inline code spans are copied
/// through untouched, so `$HOME`, `${name}` or `$x = $y` survive. Inline
/// math follows Pandoc's rule — no whitespace just inside either `$`, and
/// the closing `$` isn't followed by a digit — so prices like
/// "$5 to $10" stay text. An escaped `\$` becomes a literal `$`.
String normalizeDollarLatex(String input) {
  if (!input.contains(r'$')) return input;

  final out = StringBuffer();
  for (final segment in _splitFencedCode(input)) {
    if (segment.isCode) {
      out.write(segment.text);
      continue;
    }
    var last = 0;
    for (final match in _inlineCode.allMatches(segment.text)) {
      out.write(_convertDollars(segment.text.substring(last, match.start)));
      out.write(match[0]);
      last = match.end;
    }
    out.write(_convertDollars(segment.text.substring(last)));
  }
  return out.toString();
}

final _blockDollarLatex = RegExp(r'(?<!\\)\$\$([\s\S]+?)(?<!\\)\$\$');
final _inlineDollarLatex = RegExp(
  r'(?<![\\$])\$(?![\s$])((?:\\.|[^$\n\\])+?)(?<![\s\\])\$(?![\d$])',
);
final _currencyLike = RegExp(r'^\s*\d[\d,]*(\.\d+)?\s*$');
final _escapedDollar = RegExp(r'\\\$');

/// A backtick run, then the shortest text up to a run of the same length.
final _inlineCode = RegExp(r'(?<!`)(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)');

/// An opening code fence: up to three spaces, then 3+ backticks or tildes.
final _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})');

String _convertDollars(String text) {
  if (!text.contains(r'$')) return text;

  var result = text.replaceAllMapped(_blockDollarLatex, (m) {
    final inner = m[1]!.trim();
    if (inner.isEmpty || _currencyLike.hasMatch(inner)) return m[0]!;
    return '\\[$inner\\]';
  });

  result = result.replaceAllMapped(_inlineDollarLatex, (m) {
    final inner = m[1]!;
    if (_currencyLike.hasMatch(inner)) return m[0]!;
    return '\\($inner\\)';
  });

  return result.replaceAll(_escapedDollar, r'$');
}

class _Segment {
  const _Segment(this.text, {required this.isCode});

  final String text;
  final bool isCode;
}

/// Splits [input] into alternating prose and fenced-code segments. An
/// unclosed fence (e.g. mid-stream) runs to the end of the input.
List<_Segment> _splitFencedCode(String input) {
  final segments = <_Segment>[];
  final buffer = StringBuffer();
  String? fence;

  void flush({required bool isCode}) {
    if (buffer.isEmpty) return;
    segments.add(_Segment(buffer.toString(), isCode: isCode));
    buffer.clear();
  }

  var start = 0;
  while (start < input.length) {
    final newline = input.indexOf('\n', start);
    final end = newline == -1 ? input.length : newline + 1;
    final line = input.substring(start, end);
    start = end;

    if (fence == null) {
      final open = _fenceOpen.firstMatch(line);
      if (open != null) {
        flush(isCode: false);
        fence = open[1];
      }
      buffer.write(line);
      continue;
    }

    buffer.write(line);
    if (_closesFence(line, fence)) {
      flush(isCode: true);
      fence = null;
    }
  }
  flush(isCode: fence != null);
  return segments;
}

/// A closing fence uses the opening fence's character, is at least as long,
/// and has nothing but whitespace after it.
bool _closesFence(String line, String fence) {
  final trimmed = line.trimRight();
  final indent = trimmed.length - trimmed.trimLeft().length;
  if (indent > 3) return false;
  final body = trimmed.trimLeft();
  if (body.length < fence.length) return false;
  final char = fence[0];
  return body.split('').every((c) => c == char);
}
