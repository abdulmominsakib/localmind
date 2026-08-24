/// Prepares text for text-to-speech by stripping markdown and normalizing
/// characters that engines misread (e.g. `$1` → "dollar one").
class TtsTextProcessor {
  static String process(String text, {required bool stripMarkdown}) {
    if (text.isEmpty) return text;
    var result = text;
    if (stripMarkdown) {
      result = _stripMarkdown(result);
    }
    result = _normalizeForSpeech(result);
    return result.trim();
  }

  static String _stripMarkdown(String text) {
    var s = text;
    // Fenced code blocks
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    // Inline code
    s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1) ?? '');
    // Images ![alt](url)
    s = s.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
      (m) => m.group(1)?.isNotEmpty == true ? m.group(1)! : ' ',
    );
    // Links [text](url)
    s = s.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'),
      (m) => m.group(1)!,
    );
    // Bold / italic
    s = s.replaceAllMapped(RegExp(r'\*\*\*(.+?)\*\*\*'), (m) => m.group(1)!);
    s = s.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!);
    s = s.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!);
    s = s.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1)!);
    s = s.replaceAllMapped(RegExp(r'_(.+?)_'), (m) => m.group(1)!);
    // Headings
    s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    // Blockquote
    s = s.replaceAll(RegExp(r'^>\s?', multiLine: true), '');
    // Horizontal rules
    s = s.replaceAll(RegExp(r'^-{3,}$', multiLine: true), ' ');
    // List markers
    s = s.replaceAll(RegExp(r'^[\s]*[-*+]\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^[\s]*\d+\.\s+', multiLine: true), '');
    // Residual asterisks / underscores used as emphasis markers
    s = s.replaceAll('*', '').replaceAll('_', '');
    return s;
  }

  static String _normalizeForSpeech(String text) {
    var s = text;
    // `$1`, `$42` in templates → "1 dollars" not "dollar one"
    s = s.replaceAllMapped(
      RegExp(r'\$(\d+(?:\.\d+)?)'),
      (m) => '${m.group(1)} dollars',
    );
    // Lone `$` symbols (not followed by a word character, e.g. `$HOME`)
    s = s.replaceAll(RegExp(r'\$(?!\w)'), ' dollars ');
    // Collapse whitespace
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s;
  }
}
