import 'markdown_code_segments.dart';

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
  for (final segment in splitFencedCode(input)) {
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
