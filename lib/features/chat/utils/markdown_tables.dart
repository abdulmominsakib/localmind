import 'markdown_code_segments.dart';

/// Stands in for an escaped `\|` inside a table cell so gpt_markdown doesn't
/// split the cell on it. The table builder turns it back into `|`.
const escapedTablePipe = '';

/// A GFM delimiter row: `---`, `:--`, `--:` or `:-:` cells joined by pipes.
final _delimiterRow = RegExp(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');

/// Rewrites GFM tables into the stricter shape gpt_markdown's parser needs:
/// every row wrapped in outer pipes, empty cells kept (`||` → `| |`, which
/// it would otherwise drop and shift the columns), and escaped `\|` kept
/// inside its cell. Code blocks are left untouched.
String normalizeMarkdownTables(String input) {
  if (!input.contains('|')) return input;

  final out = StringBuffer();
  for (final segment in splitFencedCode(input)) {
    out.write(segment.isCode ? segment.text : _normalizeTables(segment.text));
  }
  return out.toString();
}

String _normalizeTables(String text) {
  final lines = text.split('\n');
  var inTable = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!inTable) {
      final next = i + 1 < lines.length ? lines[i + 1] : null;
      inTable =
          line.contains('|') &&
          next != null &&
          next.contains('|') &&
          _delimiterRow.hasMatch(next);
    } else if (line.trim().isEmpty || !line.contains('|')) {
      inTable = false;
    }
    if (inTable) lines[i] = _normalizeRow(line);
  }
  return lines.join('\n');
}

String _normalizeRow(String line) {
  var row = line.trim().replaceAll(r'\|', escapedTablePipe);
  if (!row.startsWith('|')) row = '| $row';
  if (!row.endsWith('|')) row = '$row |';
  while (row.contains('||')) {
    row = row.replaceAll('||', '| |');
  }
  return row;
}
