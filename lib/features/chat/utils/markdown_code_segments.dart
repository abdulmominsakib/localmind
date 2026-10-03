/// An opening code fence: up to three spaces, then 3+ backticks or tildes.
final _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// A run of markdown that is either prose or a fenced code block.
class MarkdownSegment {
  const MarkdownSegment(this.text, {required this.isCode});

  final String text;
  final bool isCode;
}

/// Splits [input] into alternating prose and fenced-code segments. An
/// unclosed fence (e.g. mid-stream) runs to the end of the input.
List<MarkdownSegment> splitFencedCode(String input) {
  final segments = <MarkdownSegment>[];
  final buffer = StringBuffer();
  String? fence;

  void flush({required bool isCode}) {
    if (buffer.isEmpty) return;
    segments.add(MarkdownSegment(buffer.toString(), isCode: isCode));
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
