/// Result of extracting thinking/reasoning from model output.
typedef ThinkingExtraction = ({String content, String? reasoning});

/// Extracts thinking/reasoning content from model output text.
///
/// Many models wrap reasoning in `<think>`/`</think>` tags (or format-specific
/// variants). This utility splits the output into reasoning vs. content.
///
/// If [startTag] is found without a matching [endTag], all text after
/// [startTag] is treated as reasoning (model may still be thinking).
ThinkingExtraction extractThinking(
  String text, {
  String startTag = '<think>',
  String endTag = '</think>',
  bool thinkingForcedOpen = false,
}) {
  final result = _extractThinking(
    text,
    startTag: startTag,
    endTag: endTag,
    thinkingForcedOpen: thinkingForcedOpen,
  );
  // Trim only the overall content ends here, once. The recursion keeps content
  // raw so whitespace between stripped thinking blocks (e.g. the space in
  // "Hello<think>x</think> world<think>y</think>!") is preserved.
  return (content: result.content.trim(), reasoning: result.reasoning);
}

ThinkingExtraction _extractThinking(
  String text, {
  required String startTag,
  required String endTag,
  bool thinkingForcedOpen = false,
}) {
  final startIdx = text.indexOf(startTag);
  final endIdx = text.indexOf(endTag);

  if (startIdx == -1) {
    if (endIdx != -1) {
      // Case: pre-opened thinking (started in prompt).
      // Everything before endTag is reasoning.
      final reasoning = text
          .substring(0, endIdx)
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\r')
          .trim();
      final content = text.substring(endIdx + endTag.length);
      return (
        content: content,
        reasoning: reasoning.isEmpty ? null : reasoning,
      );
    }
    // If we are forced open but see no tags, it's all reasoning
    if (thinkingForcedOpen) {
      final reasoning = text.replaceAll(r'\n', '\n').replaceAll(r'\r', '\r');
      return (content: '', reasoning: reasoning.isEmpty ? null : reasoning);
    }
    return (content: text, reasoning: null);
  }

  // If endTag appears before startTag, handle as pre-opened thinking first
  if (endIdx != -1 && endIdx < startIdx) {
    final reasoning = text
        .substring(0, endIdx)
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .trim();
    final remaining = text.substring(endIdx + endTag.length);
    // Recursively parse the rest to find more thinking tags if any
    final rest = _extractThinking(
      remaining,
      startTag: startTag,
      endTag: endTag,
    );
    return (
      content: rest.content,
      reasoning:
          reasoning + (rest.reasoning != null ? '\n${rest.reasoning}' : ''),
    );
  }

  final afterStart = startIdx + startTag.length;
  final nextEndIdx = text.indexOf(endTag, afterStart);

  if (nextEndIdx == -1) {
    // Still thinking — everything after startTag is reasoning
    final before = text.substring(0, startIdx);
    final reasoning = text
        .substring(afterStart)
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .trim();
    return (content: before, reasoning: reasoning.isEmpty ? null : reasoning);
  }

  // Complete thinking block found
  final reasoning = text
      .substring(afterStart, nextEndIdx)
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .trim();
  final before = text.substring(0, startIdx);
  final after = text.substring(nextEndIdx + endTag.length);
  // Recurse into the remainder so additional <think> blocks are also stripped
  // (mirrors the pre-opened branch above), instead of leaking them into
  // user-visible content. Content is kept raw; the public wrapper trims once.
  final rest = _extractThinking(after, startTag: startTag, endTag: endTag);
  final content = before + rest.content;
  final reasoningParts = <String>[
    if (reasoning.isNotEmpty) reasoning,
    if (rest.reasoning != null && rest.reasoning!.isNotEmpty) rest.reasoning!,
  ];

  return (
    content: content,
    reasoning: reasoningParts.isEmpty ? null : reasoningParts.join('\n'),
  );
}

/// Strips all thinking tags and content from text, returning only the
/// non-thinking content.
String stripThinking(
  String text, {
  String startTag = '<think>',
  String endTag = '</think>',
}) {
  return extractThinking(text, startTag: startTag, endTag: endTag).content;
}

/// Checks if the prompt ends with a thinking start tag, allowing for trailing
/// whitespace.
///
/// If true, the model is "forced" to continue with reasoning content.
bool isThinkingForcedOpen(String prompt, {String startTag = '<think>'}) {
  var trimmed = prompt.trimRight();

  // Handle literal escaped newlines/returns which can happen in some templates
  // Runes 92 (\) and 110 (n) or 114 (r)
  while (trimmed.endsWith(r'\n') || trimmed.endsWith(r'\r')) {
    trimmed = trimmed.substring(0, trimmed.length - 2).trimRight();
  }

  return trimmed.endsWith(startTag);
}
