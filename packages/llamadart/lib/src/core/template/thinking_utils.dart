import 'dart:async';

import '../models/chat/chat_template_result.dart';
import 'template_internal_metadata.dart';

/// Result of extracting thinking/reasoning from model output.
typedef ThinkingExtraction = ({String content, String? reasoning});

/// Extracts thinking/reasoning content from model output text.
///
/// Many models wrap reasoning in `<think>`/`</think>` tags (or format-specific
/// variants). This utility splits the output into reasoning vs. content.
///
/// If [startTag] is found without a matching [endTag], all text after
/// [startTag] is treated as reasoning (model may still be thinking).
///
/// Inside [withThoughtOnlyAtReplyStart] and without [thinkingForcedOpen],
/// only a thought that starts [text] is reasoning, and the rest is content in
/// which thinking tags are text. With its `exact` rule, whitespace before the
/// thought makes it content, and an [endTag] that starts [text] is dropped.
///
/// Escaped `\n` and `\r` in reasoning become a newline and a carriage return
/// unless [unescape] is false. The content keeps the whitespace at its ends
/// unless [trimContent] is true.
ThinkingExtraction extractThinking(
  String text, {
  String startTag = '<think>',
  String endTag = '</think>',
  bool thinkingForcedOpen = false,
  bool unescape = true,
  bool trimContent = true,
}) {
  final leadingRule = Zone.current[_thoughtOnlyAtReplyStart];
  final result = !thinkingForcedOpen && leadingRule is _LeadingThoughtRule
      ? _extractLeadingThought(
          text,
          startTag: startTag,
          endTag: endTag,
          unescape: unescape,
          exact: leadingRule == _LeadingThoughtRule.exact,
        )
      : _extractThinking(
          text,
          startTag: startTag,
          endTag: endTag,
          thinkingForcedOpen: thinkingForcedOpen,
          unescape: unescape,
        );
  // Trim only the overall content ends here, once. The recursion keeps content
  // raw so whitespace between stripped thinking blocks (e.g. the space in
  // "Hello<think>x</think> world<think>y</think>!") is preserved.
  return (
    content: trimContent ? result.content.trim() : result.content,
    reasoning: result.reasoning,
  );
}

/// [text] without the ASCII whitespace that starts it, which llama.cpp's
/// parsers skip (`std::isspace`); other Unicode whitespace stays.
String trimLeftAsciiSpace(String text) {
  var start = 0;
  while (start < text.length) {
    final unit = text.codeUnitAt(start);
    if (unit != 0x20 && (unit < 0x09 || unit > 0x0d)) break;
    start++;
  }
  return text.substring(start);
}

/// Splits [text] that continues a thought the prompt opened at the first
/// [endTag], as llama.cpp's PEG parser does.
///
/// The reasoning before it keeps escapes and a repeated start tag, and the
/// rest is content, where thinking tags are text. The first of
/// [contentOpenings] also ends the thought when it comes first, and starts the
/// content. Without either, all of [text] is reasoning. A trailing prefix of
/// [endTag] or of an opening stays in a finished output, as llama.cpp
/// (`a71c00f0b`) keeps it, and is dropped while [isPartial], since it may
/// still complete the tag. Only the ends of each part are trimmed.
ThinkingExtraction extractForcedOpenThoughtVerbatim(
  String text, {
  String endTag = '</think>',
  List<String> contentOpenings = const [],
  bool isPartial = false,
}) {
  var thoughtEnd = text.indexOf(endTag);
  var contentStart = thoughtEnd == -1 ? -1 : thoughtEnd + endTag.length;
  for (final opening in contentOpenings) {
    final at = text.indexOf(opening);
    if (at != -1 && (thoughtEnd == -1 || at < thoughtEnd)) {
      thoughtEnd = at;
      contentStart = at;
    }
  }
  final reasoning =
      (thoughtEnd != -1
              ? text.substring(0, thoughtEnd)
              : isPartial
              ? withoutTrailingTagPrefix(text, [endTag, ...contentOpenings])
              : text)
          .trim();
  return (
    content: contentStart == -1 ? '' : text.substring(contentStart).trim(),
    reasoning: reasoning.isEmpty ? null : reasoning,
  );
}

/// Returns [text] without its longest ending that starts one of [tags] but is
/// not the whole tag.
///
/// llama.cpp's PEG parser drops such an ending from a thought that has not
/// ended while the output is still arriving, as the start of the tag that
/// would end it; a finished output keeps it (`a71c00f0b`).
String withoutTrailingTagPrefix(String text, Iterable<String> tags) {
  var cut = 0;
  for (final tag in tags) {
    for (var length = tag.length - 1; length > cut; length--) {
      if (text.endsWith(tag.substring(0, length))) {
        cut = length;
        break;
      }
    }
  }
  return text.substring(0, text.length - cut);
}

final Object _thoughtOnlyAtReplyStart = Object();

enum _LeadingThoughtRule { afterSpace, exact }

/// Runs [parse] with [extractThinking] taking a thought only where it starts
/// the text, as llama.cpp parses a reply to a prompt that opens no thought.
///
/// With [exact], as llama.cpp's MiniMax M3 parser does, the thought must start
/// the text with no whitespace before it, and an end tag that starts the text
/// is dropped.
///
/// Handlers extract thinking in many places and shapes, so the parse sets
/// this once around them instead of threading it through each one.
T withThoughtOnlyAtReplyStart<T>(T Function() parse, {bool exact = false}) =>
    runZoned(
      parse,
      zoneValues: {
        _thoughtOnlyAtReplyStart: exact
            ? _LeadingThoughtRule.exact
            : _LeadingThoughtRule.afterSpace,
      },
    );

/// Splits off the thought that starts [text], after ASCII whitespace unless
/// [exact], up to the first [endTag], or to the end when none follows. With
/// [exact], an [endTag] that starts [text] is dropped.
ThinkingExtraction _extractLeadingThought(
  String text, {
  required String startTag,
  required String endTag,
  required bool unescape,
  required bool exact,
}) {
  final rest = exact ? text : trimLeftAsciiSpace(text);
  if (exact && rest.startsWith(endTag)) {
    return (content: rest.substring(endTag.length), reasoning: null);
  }
  if (!rest.startsWith(startTag)) return (content: text, reasoning: null);
  final thought = rest.substring(startTag.length);
  final end = thought.indexOf(endTag);
  var reasoning = end == -1 ? thought : thought.substring(0, end);
  if (unescape) {
    reasoning = reasoning.replaceAll(r'\n', '\n').replaceAll(r'\r', '\r');
  }
  reasoning = reasoning.trim();
  return (
    content: end == -1 ? '' : thought.substring(end + endTag.length),
    reasoning: reasoning.isEmpty ? null : reasoning,
  );
}

ThinkingExtraction _extractThinking(
  String text, {
  required String startTag,
  required String endTag,
  required bool unescape,
  bool thinkingForcedOpen = false,
}) {
  String unescaped(String reasoning) => unescape
      ? reasoning.replaceAll(r'\n', '\n').replaceAll(r'\r', '\r')
      : reasoning;

  final startIdx = text.indexOf(startTag);
  final endIdx = text.indexOf(endTag);

  if (startIdx == -1) {
    if (endIdx != -1) {
      // Case: pre-opened thinking (started in prompt).
      // Everything before endTag is reasoning.
      final reasoning = unescaped(text.substring(0, endIdx)).trim();
      final content = text.substring(endIdx + endTag.length);
      return (
        content: content,
        reasoning: reasoning.isEmpty ? null : reasoning,
      );
    }
    // If we are forced open but see no tags, it's all reasoning
    if (thinkingForcedOpen) {
      final reasoning = unescaped(text);
      return (content: '', reasoning: reasoning.isEmpty ? null : reasoning);
    }
    return (content: text, reasoning: null);
  }

  // If endTag appears before startTag, handle as pre-opened thinking first
  if (endIdx != -1 && endIdx < startIdx) {
    final reasoning = unescaped(text.substring(0, endIdx)).trim();
    final remaining = text.substring(endIdx + endTag.length);
    // Recursively parse the rest to find more thinking tags if any
    final rest = _extractThinking(
      remaining,
      startTag: startTag,
      endTag: endTag,
      unescape: unescape,
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
    final reasoning = unescaped(text.substring(afterStart)).trim();
    return (content: before, reasoning: reasoning.isEmpty ? null : reasoning);
  }

  // Complete thinking block found
  final reasoning = unescaped(text.substring(afterStart, nextEndIdx)).trim();
  final before = text.substring(0, startIdx);
  final after = text.substring(nextEndIdx + endTag.length);
  // Recurse into the remainder so additional <think> blocks are also stripped
  // (mirrors the pre-opened branch above), instead of leaking them into
  // user-visible content. Content is kept raw; the public wrapper trims once.
  final rest = _extractThinking(
    after,
    startTag: startTag,
    endTag: endTag,
    unescape: unescape,
  );
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

/// Whether [text] has an [endTag] before any [startTag], so it ends a thought
/// it did not open.
bool endsUnopenedThought(
  String text, {
  String startTag = '<think>',
  String endTag = '</think>',
}) {
  final end = text.indexOf(endTag);
  if (end == -1) return false;
  final start = text.indexOf(startTag);
  return start == -1 || end < start;
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

/// Checks if the prompt ends with an empty thought, allowing for whitespace
/// around its end tag, as templates render one with thinking off.
bool isThinkingForcedClosed(
  String prompt, {
  String startTag = '<think>',
  String endTag = '</think>',
}) {
  final trimmed = prompt.trimRight();
  return trimmed.endsWith(endTag) &&
      trimmed
          .substring(0, trimmed.length - endTag.length)
          .trimRight()
          .endsWith(startTag);
}

final Expando<bool> _thinkingForcedClosed = Expando<bool>(
  'llamadart.thinkingForcedClosed',
);

/// Returns [result], marked when [closed] as rendered by a template that ended
/// the prompt with an empty thought or, for Qwen3-Coder XML, that has no
/// thinking tags.
///
/// Only the template's own render counts, not a thought a handler closes
/// because thinking is off. The DeepSeek V3, Hermes and Qwen3-Coder XML
/// parse and stream then take thinking tags in the reply as content, as
/// llama.cpp does. Internal engine plumbing, not part of the public API.
LlamaChatTemplateResult withThinkingForcedClosed(
  LlamaChatTemplateResult result, {
  required bool closed,
}) {
  if (closed) _thinkingForcedClosed[result] = true;
  return result;
}

/// Whether [withThinkingForcedClosed] marked [result].
bool thinkingForcedClosedOf(LlamaChatTemplateResult result) =>
    _thinkingForcedClosed[result] ?? false;

final Expando<bool> _thoughtClosedForThinkingOff = Expando<bool>(
  'llamadart.thoughtClosedForThinkingOff',
);

/// Returns [result], marked when [closed] as rendered by a handler that
/// closed a thought its template left open, because thinking is off.
///
/// The parse still takes reply text before a first end tag as that thought,
/// as llama.cpp parses the thought it keeps open, so the stream holds such
/// text until a thinking tag or the end shows what it is. Internal engine
/// plumbing, not part of the public API.
LlamaChatTemplateResult withThoughtClosedForThinkingOff(
  LlamaChatTemplateResult result, {
  required bool closed,
}) {
  if (closed) _thoughtClosedForThinkingOff[result] = true;
  return result;
}

/// Whether [withThoughtClosedForThinkingOff] marked [result].
bool thoughtClosedForThinkingOffOf(LlamaChatTemplateResult result) =>
    _thoughtClosedForThinkingOff[result] ?? false;

/// Returns [copy] with the thought and tool-call marks of [source], which it
/// copies.
LlamaChatTemplateResult withThoughtMarksOf(
  LlamaChatTemplateResult copy,
  LlamaChatTemplateResult source,
) => withLfm2AutoGrammarOf(
  withBareFirstCall(
    withSingleToolCall(
      withThoughtClosedForThinkingOff(
        withThinkingForcedClosed(copy, closed: thinkingForcedClosedOf(source)),
        closed: thoughtClosedForThinkingOffOf(source),
      ),
      single: singleToolCallOf(source),
    ),
    bare: bareFirstCallOf(source),
  ),
  source,
);

/// Returns the thinking flag a request renders, parses and streams with.
///
/// A boolean `enable_thinking` in [chatTemplateKwargs] overrides
/// [enableThinking], as in llama-server; failing that, a boolean `thinking`
/// does. Any other value leaves [enableThinking] in effect.
bool effectiveEnableThinking(
  bool enableThinking,
  Map<String, dynamic>? chatTemplateKwargs,
) {
  for (final key in const ['enable_thinking', 'thinking']) {
    final value = chatTemplateKwargs?[key];
    if (value is bool) return value;
  }
  return enableThinking;
}

/// Returns [result] with [LlamaChatTemplateResult.thinkingForcedOpen] set when
/// its prompt ends with [startTag] that the handler did not track.
///
/// The prompt is unchanged: as in llama.cpp, a thought the template opens is
/// parsed as reasoning whether or not thinking was requested.
LlamaChatTemplateResult withTemplateOpenedThought(
  LlamaChatTemplateResult result, {
  required String startTag,
}) {
  if (result.thinkingForcedOpen ||
      !isThinkingForcedOpen(result.prompt, startTag: startTag.trimRight())) {
    return result;
  }
  return withLfm2AutoGrammarOf(
    LlamaChatTemplateResult(
      prompt: result.prompt,
      format: result.format,
      grammar: result.grammar,
      grammarLazy: result.grammarLazy,
      additionalStops: result.additionalStops,
      preservedTokens: result.preservedTokens,
      grammarTriggers: result.grammarTriggers,
      thinkingForcedOpen: true,
      parser: result.parser,
      tokenCount: result.tokenCount,
    ),
    result,
  );
}
