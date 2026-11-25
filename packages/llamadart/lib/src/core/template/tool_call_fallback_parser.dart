import 'dart:convert';
import 'dart:math';

import '../models/chat/completion_chunk.dart';
import 'thinking_utils.dart';
import 'tool_call_parsing_utils.dart';

/// Result of parsing loose tool-call text fallback.
class ToolCallFallbackParseResult {
  /// Remaining user-visible content after extracting tool calls.
  final String content;

  /// Parsed tool calls, if any.
  final List<LlamaCompletionChunkToolCall> toolCalls;

  /// Creates a fallback parse result.
  const ToolCallFallbackParseResult({
    required this.content,
    required this.toolCalls,
  });
}

/// Parses tool calls from loose plain-text payloads.
///
/// This is intentionally permissive and used only when a format-specific
/// parser fails to extract explicit tool-call structures.
/// With [preserveJsonProse], keep the text around a loose JSON call and
/// recognize a standalone function call. While [isPartial], hold text that
/// can still become a call. When [allowedToolNames] is provided, accept only
/// those names. With [holdRecoveredCallSuffix] in partial mode, only expose
/// content before a recovered JSON call while native parsing can win.
ToolCallFallbackParseResult parseToolCallsFromLooseText(
  String input, {
  bool preserveJsonProse = false,
  bool isPartial = false,
  bool holdRecoveredCallSuffix = false,
  Iterable<String>? allowedToolNames,
}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return ToolCallFallbackParseResult(
      content: preserveJsonProse ? input : '',
      toolCalls: const <LlamaCompletionChunkToolCall>[],
    );
  }

  final allowedNames = allowedToolNames is Set<String>
      ? allowedToolNames
      : allowedToolNames?.toSet();
  if (preserveJsonProse) {
    final function = _parseLeadingFunctionCall(
      input,
      allowedNames: allowedNames,
      isPartial: isPartial,
    );
    if (function != null) return function;
  }
  final codeSpans = _MarkdownCodeSpans.parse(input);

  final json = _parseJsonLikeToolCalls(
    input,
    codeSpans: codeSpans,
    allowedNames: allowedNames,
    isPartial: isPartial,
  );
  if (json != null) {
    if (!preserveJsonProse) {
      return ToolCallFallbackParseResult(content: '', toolCalls: json.calls);
    }

    var prefix = input.substring(0, json.contentPrefixEnd);
    var insidePendingContainer = false;
    if (isPartial) {
      final holdFrom = _pendingLooseJsonStart(
        input,
        scanEnd: json.firstCallStart,
        endLimit: input.length,
        codeSpans: codeSpans,
        allowedNames: allowedNames,
      );
      if (holdFrom < prefix.length) {
        prefix = input.substring(0, holdFrom);
      }
      insidePendingContainer = holdFrom < json.firstCallStart;
      if (holdRecoveredCallSuffix) {
        return ToolCallFallbackParseResult(
          content: prefix.trimRight(),
          toolCalls: json.calls,
        );
      }
    }

    final suffix = insidePendingContainer
        ? ''
        : isPartial && json.holdTrailingFrom != null
        ? input.substring(json.suffixStart, json.holdTrailingFrom!)
        : input.substring(json.suffixStart);
    return ToolCallFallbackParseResult(
      content: _joinAtCallJunction(prefix, suffix),
      toolCalls: json.calls,
    );
  }

  if (!preserveJsonProse) {
    final functionCall = _parseFunctionCallSyntax(
      trimmed,
      allowedNames: allowedNames,
    );
    if (functionCall != null) {
      return ToolCallFallbackParseResult(
        content: '',
        toolCalls: [functionCall],
      );
    }
  }

  return ToolCallFallbackParseResult(
    content: !preserveJsonProse
        ? trimmed
        : isPartial
        ? input.substring(
            0,
            _pendingLooseJsonStart(
              input,
              scanEnd: input.length,
              endLimit: input.length,
              codeSpans: codeSpans,
              allowedNames: allowedNames,
            ),
          )
        : input,
    toolCalls: const <LlamaCompletionChunkToolCall>[],
  );
}

final _looseJsonWrapper = RegExp(r'<tool_call>\s*(?:\[\s*)?$|\[\s*$');

int _looseJsonWrapperStart(String prefix) {
  final match = _looseJsonWrapper.firstMatch(prefix);
  return match == null ? prefix.length : match.start;
}

int _pendingLooseJsonStart(
  String input, {
  required int scanEnd,
  required int endLimit,
  required _MarkdownCodeSpans codeSpans,
  required Set<String>? allowedNames,
}) {
  if (allowedNames != null && allowedNames.isEmpty) {
    return scanEnd;
  }

  final prefixSlice = input.substring(0, scanEnd);
  final wrapperPrefix = withoutTrailingTagPrefix(prefixSlice, const [
    '<tool_call>',
  ]);
  var holdFrom = min(wrapperPrefix.length, _looseJsonWrapperStart(prefixSlice));

  var pos = 0;
  while (pos < scanEnd) {
    final closedEnd = codeSpans.closedEndAt(pos);
    if (closedEnd != null) {
      pos = closedEnd;
      continue;
    }

    final ch = input.codeUnitAt(pos);
    if (ch != 0x7B && ch != 0x5B) {
      pos++;
      continue;
    }

    final scan = _JsonPrefixScanner(
      input,
      start: pos,
      endLimit: endLimit,
      allowedNames: allowedNames,
    ).scan();

    switch (scan.status) {
      case _JsonScanStatus.invalid:
        pos++;
      case _JsonScanStatus.complete:
        if (_hasDeclaredLooseCalls(
          input,
          pos,
          scan.end,
          allowedNames: allowedNames,
        )) {
          return min(holdFrom, _looseJsonWrapperStart(input.substring(0, pos)));
        }
        pos = scan.end;
      case _JsonScanStatus.pending:
        if (!scan.rejectedName) {
          return min(holdFrom, _looseJsonWrapperStart(input.substring(0, pos)));
        }
        // Skip nested objects inside a still-open outer object whose name is
        // rejected.
        return holdFrom;
    }
  }

  return holdFrom;
}

bool _hasDeclaredLooseCalls(
  String input,
  int start,
  int end, {
  required Set<String>? allowedNames,
}) {
  final decoded = _decodeJsonSlice(input.substring(start, end));
  if (decoded == null) {
    return false;
  }
  return _toolCallsFromDecoded(
    decoded,
    startIndex: 0,
    allowedNames: allowedNames,
  ).isNotEmpty;
}

enum _JsonScanStatus { invalid, complete, pending }

enum _JsonPart {
  objectStart,
  key,
  colon,
  value,
  objectEnd,
  arrayStart,
  arrayEnd,
}

enum _ContainerRole { candidate, functionObj, toolCallsArray, other }

class _ContainerFrame {
  _ContainerFrame(this.role);

  final _ContainerRole role;
  String? currentKey;
}

class _JsonPrefixScanner {
  _JsonPrefixScanner(
    this.input, {
    required this.start,
    required this.endLimit,
    required this.allowedNames,
    this.strict = false,
  }) : _offset = start;

  static const _integer = r'-?(?:0|[1-9][0-9]*)';
  static const _fraction = r'(?:\.[0-9]+)?';
  static final _number = RegExp(
    '$_integer$_fraction'
    r'(?:[eE][+-]?[0-9]+)?',
  );
  static final _incompleteNumber = RegExp(
    '(?:-|$_integer\\.|$_integer$_fraction'
    r'[eE][+-]?)$',
  );
  static final _bareIdentifier = RegExp(r'[A-Za-z_][A-Za-z0-9_\.-]*');
  static const _objectMember = [
    _JsonPart.objectEnd,
    _JsonPart.value,
    _JsonPart.colon,
    _JsonPart.key,
  ];

  final String input;
  final int start;
  final int endLimit;
  final Set<String>? allowedNames;
  final bool strict;

  int _offset;
  bool _rejectedName = false;
  final _frames = <_ContainerFrame>[];

  ({_JsonScanStatus status, int end, bool rejectedName}) scan() {
    final parts = [_JsonPart.value];
    while (parts.isNotEmpty && _offset < endLimit) {
      if (' \t\n\r'.contains(input[_offset])) {
        _offset++;
        continue;
      }
      switch (parts.removeLast()) {
        case _JsonPart.objectStart:
          if (_take('}')) {
            _popFrame();
          } else {
            parts.addAll(_objectMember);
          }
        case _JsonPart.key:
          final key = _scanString();
          if (key == null) {
            return (
              status: _JsonScanStatus.invalid,
              end: _offset,
              rejectedName: false,
            );
          }
          if (_frames.isNotEmpty) {
            _frames.last.currentKey = key.complete ? key.value : null;
          }
        case _JsonPart.colon:
          if (!_take(':')) {
            return (
              status: _JsonScanStatus.invalid,
              end: _offset,
              rejectedName: false,
            );
          }
        case _JsonPart.value:
          final frame = _frames.isNotEmpty ? _frames.last : null;
          final key = frame?.currentKey;
          final role = frame?.role;
          switch (input[_offset]) {
            case '{':
              _offset++;
              parts.add(_JsonPart.objectStart);
              _frames.add(_ContainerFrame(_childObjectRole(role, key)));
            case '[':
              _offset++;
              parts.add(_JsonPart.arrayStart);
              _frames.add(_ContainerFrame(_childArrayRole(role, key)));
            case '"':
              final str = _scanString();
              if (str == null) {
                return (
                  status: _JsonScanStatus.invalid,
                  end: _offset,
                  rejectedName: false,
                );
              }
              if (str.complete && str.value != null && frame != null) {
                _checkFieldName(frame.role, key, str.value!);
              }
            case 'n':
              if ((key == 'name' || key == 'function') &&
                  _scanBareIdentifier(frame, key)) {
                break;
              }
              if (!_scanLiteral('null')) {
                return (
                  status: _JsonScanStatus.invalid,
                  end: _offset,
                  rejectedName: false,
                );
              }
            case 't':
              if ((key == 'name' || key == 'function') &&
                  _scanBareIdentifier(frame, key)) {
                break;
              }
              if (!_scanLiteral('true')) {
                return (
                  status: _JsonScanStatus.invalid,
                  end: _offset,
                  rejectedName: false,
                );
              }
            case 'f':
              if ((key == 'name' || key == 'function') &&
                  _scanBareIdentifier(frame, key)) {
                break;
              }
              if (!_scanLiteral('false')) {
                return (
                  status: _JsonScanStatus.invalid,
                  end: _offset,
                  rejectedName: false,
                );
              }
            default:
              if ((key == 'name' || key == 'function') &&
                  _scanBareIdentifier(frame, key)) {
                break;
              }
              if (!_scanNumber()) {
                return (
                  status: _JsonScanStatus.invalid,
                  end: _offset,
                  rejectedName: false,
                );
              }
          }
        case _JsonPart.objectEnd:
          if (_take('}')) {
            _popFrame();
          } else if (_take(',')) {
            if (_frames.isNotEmpty) {
              _frames.last.currentKey = null;
            }
            parts.addAll(_objectMember);
          } else {
            return (
              status: _JsonScanStatus.invalid,
              end: _offset,
              rejectedName: false,
            );
          }
        case _JsonPart.arrayStart:
          if (_take(']')) {
            _popFrame();
          } else {
            parts.addAll(const [_JsonPart.arrayEnd, _JsonPart.value]);
          }
        case _JsonPart.arrayEnd:
          if (_take(']')) {
            _popFrame();
          } else if (_take(',')) {
            parts.addAll(const [_JsonPart.arrayEnd, _JsonPart.value]);
          } else {
            return (
              status: _JsonScanStatus.invalid,
              end: _offset,
              rejectedName: false,
            );
          }
      }
    }

    if (parts.isEmpty) {
      return (
        status: _JsonScanStatus.complete,
        end: _offset,
        rejectedName: _rejectedName,
      );
    }
    return (
      status: _JsonScanStatus.pending,
      end: _offset,
      rejectedName: _rejectedName,
    );
  }

  _ContainerRole _childObjectRole(_ContainerRole? parent, String? key) {
    if (parent == null) {
      return _ContainerRole.candidate;
    }
    if (parent == _ContainerRole.toolCallsArray) {
      return _ContainerRole.candidate;
    }
    if (parent == _ContainerRole.candidate) {
      if (key == 'tool_call' || key == 'tool_calls') {
        return _ContainerRole.candidate;
      }
      if (key == 'function') {
        return _ContainerRole.functionObj;
      }
    }
    return _ContainerRole.other;
  }

  _ContainerRole _childArrayRole(_ContainerRole? parent, String? key) {
    if (parent == null) {
      return _ContainerRole.toolCallsArray;
    }
    if (parent == _ContainerRole.candidate && key == 'tool_calls') {
      return _ContainerRole.toolCallsArray;
    }
    return _ContainerRole.other;
  }

  void _popFrame() {
    if (_frames.isNotEmpty) {
      _frames.removeLast();
    }
  }

  void _checkFieldName(_ContainerRole role, String? key, String value) {
    final allowed = allowedNames;
    if (allowed == null || key == null) {
      return;
    }
    if (_frames.length > 3) {
      return;
    }
    if (role == _ContainerRole.functionObj && key == 'name') {
      final normalized = normalizeFallbackToolName(value);
      if (normalized.isEmpty || !allowed.contains(normalized)) {
        _rejectedName = true;
      }
      return;
    }
    if (role != _ContainerRole.candidate) {
      return;
    }
    // Only single top-level/tool_call objects can be rejected before `}` closes;
    // arrays in `tool_calls` may still hold a valid later item.
    if (_frames.any((f) => f.role == _ContainerRole.toolCallsArray)) {
      return;
    }
    if (key == 'name' ||
        key == 'tool_name' ||
        key == 'code' ||
        key == 'function') {
      final normalized = normalizeFallbackToolName(value);
      if (normalized.isEmpty || !allowed.contains(normalized)) {
        _rejectedName = true;
      }
    } else if (key == 'type') {
      final normalized = normalizeFallbackToolName(value);
      if (normalized != 'function' &&
          normalized != 'tool' &&
          !allowed.contains(normalized)) {
        _rejectedName = true;
      }
    }
  }

  bool _scanBareIdentifier(_ContainerFrame? frame, String? key) {
    if (strict) return false;
    final match = _bareIdentifier.matchAsPrefix(input, _offset);
    if (match == null) {
      return false;
    }
    _offset = match.end;
    // Only reject once a delimiter/whitespace follows, so an identifier still
    // arriving at the partial tail (e.g. `weath`) is not rejected early.
    if (frame != null && _offset < endLimit) {
      _checkFieldName(frame.role, key, match.group(0)!);
    }
    return true;
  }

  bool _take(String value) {
    if (input[_offset] != value) return false;
    _offset++;
    return true;
  }

  bool _scanLiteral(String literal) {
    for (var i = 0; i < literal.length && _offset < endLimit; i++) {
      if (!_take(literal[i])) return false;
    }
    return true;
  }

  bool _scanNumber() {
    final slice = endLimit == input.length
        ? input
        : input.substring(0, endLimit);
    if (_incompleteNumber.matchAsPrefix(slice, _offset)?.end == endLimit) {
      _offset = endLimit;
      return true;
    }
    final match = _number.matchAsPrefix(slice, _offset);
    if (match == null) return false;
    _offset = match.end;
    return true;
  }

  ({bool complete, String? value})? _scanString() {
    if (!_take('"')) return null;
    final tokenStart = _offset - 1;
    while (_offset < endLimit) {
      final value = input.codeUnitAt(_offset++);
      if (value == 0x22) {
        String? decoded;
        try {
          final parsed = jsonDecode(input.substring(tokenStart, _offset));
          if (parsed is String) {
            decoded = parsed;
          }
        } on FormatException {
          decoded = null;
        }
        return (complete: true, value: decoded);
      }
      if (value < 0x20) return null;
      if (value != 0x5C) continue;
      if (_offset == endLimit) return (complete: false, value: null);
      final escape = input[_offset++];
      if (r'"\/bfnrt'.contains(escape)) continue;
      if (escape != 'u') return null;
      for (var i = 0; i < 4 && _offset < endLimit; i++) {
        if (!'0123456789abcdefABCDEF'.contains(input[_offset++])) return null;
      }
    }
    return (complete: false, value: null);
  }
}

class _MarkdownCodeSpans {
  _MarkdownCodeSpans._(this._closedRanges, this._openInlineStarts);

  final List<({int start, int end})> _closedRanges;
  final List<int> _openInlineStarts;

  static _MarkdownCodeSpans parse(String input) {
    final closed = <({int start, int end})>[];
    final openInline = <int>[];
    var i = 0;
    var atLineStart = true;

    while (i < input.length) {
      if (atLineStart) {
        var ws = i;
        while (ws < input.length && (input[ws] == ' ' || input[ws] == '\t')) {
          ws++;
        }
        if (ws < input.length && (input[ws] == '`' || input[ws] == '~')) {
          final fenceChar = input[ws];
          var fenceLen = 0;
          while (ws + fenceLen < input.length &&
              input[ws + fenceLen] == fenceChar) {
            fenceLen++;
          }
          if (fenceLen >= 3) {
            final lineEnd = _lineBreakIndex(input, ws + fenceLen);
            final info = input.substring(ws + fenceLen, lineEnd);
            if (fenceChar != '`' || !info.contains('`')) {
              final closeEnd = _findClosingFenceEnd(
                input,
                lineEnd < input.length ? lineEnd + 1 : input.length,
                fenceChar: fenceChar,
                minLen: fenceLen,
              );
              closed.add((start: ws, end: closeEnd));
              i = closeEnd;
              atLineStart = i == input.length || input[i - 1] == '\n';
              continue;
            }
          }
        }
        atLineStart = false;
      }

      final ch = input[i];
      if (ch == '\n') {
        var ws = i + 1;
        while (ws < input.length &&
            (input[ws] == ' ' || input[ws] == '\t' || input[ws] == '\r')) {
          ws++;
        }
        if (ws < input.length && input[ws] == '\n') {
          openInline.clear();
        }
        atLineStart = true;
        i++;
        continue;
      }

      if (ch == '`') {
        var backslashes = 0;
        var k = i - 1;
        while (k >= 0 && input[k] == r'\') {
          backslashes++;
          k--;
        }
        if (backslashes.isOdd) {
          i++;
          continue;
        }
        var runLen = 0;
        while (i + runLen < input.length && input[i + runLen] == '`') {
          runLen++;
        }
        final closeEnd = _findClosingBacktickRun(
          input,
          i + runLen,
          runLen: runLen,
        );
        if (closeEnd != null) {
          closed.add((start: i, end: closeEnd));
          i = closeEnd;
          continue;
        }
        openInline.add(i);
        i += runLen;
        continue;
      }

      i++;
    }

    return _MarkdownCodeSpans._(closed, openInline);
  }

  static int _lineBreakIndex(String input, int from) {
    final idx = input.indexOf('\n', from);
    return idx == -1 ? input.length : idx;
  }

  static int _findClosingFenceEnd(
    String input,
    int from, {
    required String fenceChar,
    required int minLen,
  }) {
    var pos = from;
    while (pos < input.length) {
      var ws = pos;
      while (ws < input.length && (input[ws] == ' ' || input[ws] == '\t')) {
        ws++;
      }
      var run = 0;
      while (ws + run < input.length && input[ws + run] == fenceChar) {
        run++;
      }
      final lineEnd = _lineBreakIndex(input, ws + run);
      if (run >= minLen && input.substring(ws + run, lineEnd).trim().isEmpty) {
        return lineEnd < input.length ? lineEnd + 1 : input.length;
      }
      pos = lineEnd < input.length ? lineEnd + 1 : input.length;
    }
    return input.length;
  }

  static int? _findClosingBacktickRun(
    String input,
    int from, {
    required int runLen,
  }) {
    var i = from;
    while (i < input.length) {
      if (input[i] == '\n') {
        // CommonMark inline code spans cannot cross a blank line.
        var ws = i + 1;
        while (ws < input.length &&
            (input[ws] == ' ' || input[ws] == '\t' || input[ws] == '\r')) {
          ws++;
        }
        if (ws < input.length && input[ws] == '\n') {
          return null;
        }
      }
      if (input[i] == '`') {
        var len = 0;
        while (i + len < input.length && input[i + len] == '`') {
          len++;
        }
        if (len == runLen) {
          return i + len;
        }
        i += len;
        continue;
      }
      i++;
    }
    return null;
  }

  int? closedEndAt(int offset) {
    for (final range in _closedRanges) {
      if (offset >= range.start && offset < range.end) {
        return range.end;
      }
    }
    return null;
  }

  bool isOpenInlineAt(int offset) {
    for (final start in _openInlineStarts) {
      if (offset >= start) {
        return true;
      }
    }
    return false;
  }
}

/// Decodes tool arguments JSON/object text into a map.
Map<String, dynamic> decodeToolArgumentsObject(String? rawArguments) {
  if (rawArguments == null) {
    return const <String, dynamic>{};
  }

  final trimmed = rawArguments.trim();
  if (trimmed.isEmpty) {
    return const <String, dynamic>{};
  }

  final decoded = ToolCallParsingUtils.decodeJsonMapValue(
    trimmed,
    trimInput: true,
  );
  if (decoded != null) {
    return decoded;
  }

  final object = ToolCallParsingUtils.extractFirstJsonObject(trimmed);
  if (object != null) {
    return object;
  }

  return const <String, dynamic>{};
}

/// Normalizes fallback argument aliases.
Map<String, dynamic> normalizeFallbackToolArguments(
  Map<String, dynamic> arguments,
) {
  final normalized = <String, dynamic>{...arguments};
  final wrappedArguments = _unwrapArgumentContainer(normalized);
  if (wrappedArguments != null) {
    normalized
      ..clear()
      ..addAll(wrappedArguments);
  }
  return normalized;
}

Map<String, dynamic>? _unwrapArgumentContainer(Map<String, dynamic> arguments) {
  const wrapperKeys = <String>{'arguments', 'parameters', 'params', 'input'};
  if (arguments.length != 1) {
    return null;
  }

  final entry = arguments.entries.first;
  if (!wrapperKeys.contains(entry.key)) {
    return null;
  }

  return ToolCallParsingUtils.coerceMap(entry.value);
}

/// Normalizes noisy tool aliases to canonical names where possible.
String normalizeFallbackToolName(
  String rawName, {
  Map<String, dynamic>? arguments,
}) {
  // Preserve model-emitted tool name for llama.cpp parity.
  final trimmed = rawName.trim();
  return trimmed;
}

({
  List<LlamaCompletionChunkToolCall> calls,
  int firstCallStart,
  int contentPrefixEnd,
  int suffixStart,
  int? holdTrailingFrom,
})?
_parseJsonLikeToolCalls(
  String input, {
  required _MarkdownCodeSpans codeSpans,
  required Set<String>? allowedNames,
  required bool isPartial,
}) {
  if (allowedNames != null && allowedNames.isEmpty) {
    return null;
  }

  final first = _findFirstLooseCall(
    input,
    from: 0,
    startIndex: 0,
    codeSpans: codeSpans,
    allowedNames: allowedNames,
  );
  if (first == null) {
    return null;
  }

  // When streaming inside an unclosed inline backtick span, keep holding from
  // the JSON opening until the backtick closes (or EOF proves it unmatched).
  if (isPartial && codeSpans.isOpenInlineAt(first.callStart)) {
    return null;
  }

  final contentPrefixEnd = _looseJsonWrapperStart(
    input.substring(0, first.callStart),
  );
  final wrapped = input.startsWith('<tool_call>', contentPrefixEnd);
  final calls = <LlamaCompletionChunkToolCall>[...first.calls];
  var callEnd = first.callEnd;
  int? holdTrailingFrom;

  // Collect semicolon-separated continuation calls (`call1; call2`) while
  // holding only a trailing `;` whose following text can still become a call.
  while (callEnd < input.length) {
    final semicolon = _skipCallWhitespace(input, callEnd);
    if (semicolon >= input.length || input[semicolon] != ';') {
      break;
    }

    final afterSemi = semicolon + 1;
    final next = wrapped
        ? null
        : _findFirstLooseCall(
            input,
            from: afterSemi,
            startIndex: calls.length,
            codeSpans: codeSpans,
            allowedNames: allowedNames,
          );
    if (next != null &&
        input.substring(afterSemi, next.callStart).trim().isEmpty) {
      if (isPartial && codeSpans.isOpenInlineAt(next.callStart)) {
        holdTrailingFrom = callEnd;
        break;
      }
      calls.addAll(next.calls);
      callEnd = next.callEnd;
      continue;
    }

    if (isPartial) {
      final tail = input.substring(afterSemi);
      if (tail.trim().isEmpty ||
          !wrapped &&
              _pendingLooseJsonStart(
                    tail,
                    scanEnd: tail.length,
                    endLimit: tail.length,
                    codeSpans: _MarkdownCodeSpans.parse(tail),
                    allowedNames: allowedNames,
                  ) <
                  tail.length) {
        holdTrailingFrom = callEnd;
        break;
      }
    }

    if (!_containsNewline(input, callEnd, semicolon)) {
      callEnd = _skipHorizontalWhitespace(input, afterSemi);
    }
    break;
  }

  if (holdTrailingFrom == null) {
    final after = _consumeClosingToolCallTag(
      input,
      from: callEnd,
      isPartial: isPartial,
    );
    callEnd = after.suffixStart;
    holdTrailingFrom = after.holdFrom;
  }

  return (
    calls: List<LlamaCompletionChunkToolCall>.unmodifiable(calls),
    firstCallStart: first.callStart,
    contentPrefixEnd: contentPrefixEnd,
    suffixStart: callEnd,
    holdTrailingFrom: holdTrailingFrom,
  );
}

({int suffixStart, int? holdFrom}) _consumeClosingToolCallTag(
  String input, {
  required int from,
  required bool isPartial,
}) {
  const closeTag = '</tool_call>';
  final ws = _skipCallWhitespace(input, from);
  final rest = input.substring(ws);
  if (rest.startsWith(closeTag)) {
    return (suffixStart: ws + closeTag.length, holdFrom: null);
  }
  if (rest.isNotEmpty && closeTag.startsWith(rest)) {
    return isPartial
        ? (suffixStart: from, holdFrom: from)
        : (suffixStart: input.length, holdFrom: null);
  }
  if (isPartial && rest.isEmpty) {
    return (suffixStart: from, holdFrom: from);
  }
  return (suffixStart: from, holdFrom: null);
}

int _skipCallWhitespace(String input, int start) {
  var offset = start;
  while (offset < input.length && ' \t\r\n'.contains(input[offset])) {
    offset++;
  }
  return offset;
}

bool _isHorizontalWhitespace(int codeUnit) =>
    codeUnit == 0x20 || codeUnit == 0x09;

int _skipHorizontalWhitespace(String input, int start) {
  var pos = start;
  while (pos < input.length && _isHorizontalWhitespace(input.codeUnitAt(pos))) {
    pos++;
  }
  return pos;
}

String _trimRightHorizontalWhitespace(String text) {
  var end = text.length;
  while (end > 0 && _isHorizontalWhitespace(text.codeUnitAt(end - 1))) {
    end--;
  }
  return text.substring(0, end);
}

String _trimLeftHorizontalWhitespace(String text) =>
    text.substring(_skipHorizontalWhitespace(text, 0));

bool _containsNewline(String input, int start, int end) {
  for (var i = start; i < end; i++) {
    final unit = input.codeUnitAt(i);
    if (unit == 0x0A || unit == 0x0D) {
      return true;
    }
  }
  return false;
}

String _joinAtCallJunction(String left, String right) {
  if (left.isEmpty) {
    return right;
  }
  if (right.isEmpty) {
    return left;
  }
  final leftTrimmed = _trimRightHorizontalWhitespace(left);
  final rightTrimmed = _trimLeftHorizontalWhitespace(right);
  final hadHorizontalWhitespace =
      leftTrimmed.length < left.length || rightTrimmed.length < right.length;
  if (leftTrimmed.isNotEmpty && rightTrimmed.isNotEmpty) {
    return hadHorizontalWhitespace
        ? '$leftTrimmed $rightTrimmed'
        : '$leftTrimmed$rightTrimmed';
  }
  if (rightTrimmed.isEmpty) {
    return leftTrimmed.isEmpty
        ? (hadHorizontalWhitespace ? ' ' : '')
        : (hadHorizontalWhitespace ? '$leftTrimmed ' : leftTrimmed);
  }
  return left.trim().isEmpty
      ? (hadHorizontalWhitespace ? ' $rightTrimmed' : rightTrimmed)
      : '$left$right';
}

({List<LlamaCompletionChunkToolCall> calls, int callStart, int callEnd})?
_findFirstLooseCall(
  String input, {
  required int from,
  required int startIndex,
  required _MarkdownCodeSpans codeSpans,
  required Set<String>? allowedNames,
}) {
  var pos = from;
  while (pos < input.length) {
    final closedEnd = codeSpans.closedEndAt(pos);
    if (closedEnd != null) {
      pos = closedEnd;
      continue;
    }

    final ch = input.codeUnitAt(pos);
    if (ch != 0x7B && ch != 0x5B) {
      pos++;
      continue;
    }

    final scan = _JsonPrefixScanner(
      input,
      start: pos,
      endLimit: input.length,
      allowedNames: allowedNames,
    ).scan();

    switch (scan.status) {
      case _JsonScanStatus.invalid:
        pos++;
      case _JsonScanStatus.complete:
        final decoded = _decodeJsonSlice(input.substring(pos, scan.end));
        if (decoded != null) {
          final calls = _toolCallsFromDecoded(
            decoded,
            startIndex: startIndex,
            allowedNames: allowedNames,
          );
          if (calls.isNotEmpty) {
            return (calls: calls, callStart: pos, callEnd: scan.end);
          }
        }
        pos = scan.end;
      case _JsonScanStatus.pending:
        if (scan.rejectedName) {
          return null;
        }
        pos++;
    }
  }
  return null;
}

Object? _decodeJsonSlice(String slice) {
  final direct = ToolCallParsingUtils.decodeJsonValue(slice);
  if (direct != null) {
    return direct;
  }

  final normalized = _normalizeLooseJsonIdentifiers(slice);
  return ToolCallParsingUtils.decodeJsonValue(normalized);
}

List<LlamaCompletionChunkToolCall> _toolCallsFromDecoded(
  Object decoded, {
  required int startIndex,
  required Set<String>? allowedNames,
}) {
  final decodedMap = ToolCallParsingUtils.coerceMap(decoded);
  if (decodedMap != null) {
    final toolCallsRaw = decodedMap['tool_calls'];
    if (toolCallsRaw != null) {
      final calls = _toolCallsFromDecoded(
        toolCallsRaw,
        startIndex: startIndex,
        allowedNames: allowedNames,
      );
      if (calls.isNotEmpty) {
        return calls;
      }
    }

    final call = _toolCallFromMap(
      decodedMap,
      index: startIndex,
      allowedNames: allowedNames,
    );
    if (call == null) {
      return const <LlamaCompletionChunkToolCall>[];
    }
    return <LlamaCompletionChunkToolCall>[call];
  }

  if (decoded is List) {
    final calls = <LlamaCompletionChunkToolCall>[];
    for (var i = 0; i < decoded.length; i++) {
      final item = ToolCallParsingUtils.coerceMap(decoded[i]);
      if (item == null) {
        continue;
      }

      final call = _toolCallFromMap(
        item,
        index: startIndex + i,
        allowedNames: allowedNames,
      );
      if (call != null) {
        calls.add(call);
      }
    }
    return List<LlamaCompletionChunkToolCall>.unmodifiable(calls);
  }

  return const <LlamaCompletionChunkToolCall>[];
}

LlamaCompletionChunkToolCall? _toolCallFromMap(
  Map<String, dynamic> object, {
  required int index,
  required Set<String>? allowedNames,
}) {
  final candidate =
      ToolCallParsingUtils.coerceMap(object['tool_call']) ?? object;

  final functionRaw = candidate['function'];
  Object? nameRaw;
  Object? argumentsRaw;
  final function = ToolCallParsingUtils.coerceMap(functionRaw);
  if (function != null) {
    nameRaw = function['name'];
    argumentsRaw =
        function['arguments'] ??
        function['parameters'] ??
        function['params'] ??
        function['input'] ??
        candidate['arguments'] ??
        candidate['parameters'] ??
        candidate['args'] ??
        candidate['params'] ??
        candidate['input'];
  } else {
    nameRaw =
        candidate['name'] ??
        functionRaw ??
        candidate['tool_name'] ??
        candidate['code'] ??
        candidate['type'];
    argumentsRaw =
        candidate['arguments'] ??
        candidate['parameters'] ??
        candidate['args'] ??
        candidate['params'] ??
        candidate['input'];
  }

  if (nameRaw is! String || nameRaw.trim().isEmpty) {
    return null;
  }

  if (allowedNames != null) {
    // Reject envelopes whose explicit `type` already rules out a tool call
    // (e.g. `{"type":"object","name":"weather"}`), matching streaming early
    // release so stream and final parses always agree.
    final typeRaw = candidate['type'];
    if (typeRaw is String) {
      final normalizedType = normalizeFallbackToolName(typeRaw);
      if (normalizedType != 'function' &&
          normalizedType != 'tool' &&
          !allowedNames.contains(normalizedType)) {
        return null;
      }
    }
  }

  final argsMap = argumentsRaw == null
      ? _extractInlineArguments(candidate)
      : _toArgumentsObject(argumentsRaw);
  final normalizedArgs = normalizeFallbackToolArguments(argsMap);
  final normalizedName = normalizeFallbackToolName(
    nameRaw,
    arguments: normalizedArgs,
  );

  if (normalizedName.isEmpty) {
    return null;
  }

  if (allowedNames != null && !allowedNames.contains(normalizedName)) {
    return null;
  }

  return ToolCallParsingUtils.createFunctionToolCall(
    index: index,
    name: normalizedName,
    id: object['id'] is String ? object['id'] as String : null,
    arguments: normalizedArgs,
  );
}

Map<String, dynamic> _extractInlineArguments(Map<String, dynamic> candidate) {
  const metaKeys = <String>{
    'name',
    'type',
    'code',
    'tool_name',
    'function',
    'tool',
    'toolName',
    'id',
    'call_id',
    'tool_call_id',
    'index',
    'tool_call',
  };

  final inline = <String, dynamic>{};
  for (final entry in candidate.entries) {
    if (metaKeys.contains(entry.key)) {
      continue;
    }
    inline[entry.key] = entry.value;
  }

  return inline;
}

Map<String, dynamic> _toArgumentsObject(Object? raw) {
  if (raw == null) {
    return const <String, dynamic>{};
  }

  final map = ToolCallParsingUtils.coerceMap(raw);
  if (map != null) {
    return map;
  }

  if (raw is String) {
    return decodeToolArgumentsObject(raw);
  }

  return const <String, dynamic>{};
}

LlamaCompletionChunkToolCall? _parseFunctionCallSyntax(
  String input, {
  Set<String>? allowedNames,
}) {
  if (allowedNames != null && allowedNames.isEmpty) {
    return null;
  }

  final match = RegExp(
    r'^([A-Za-z_][A-Za-z0-9_\.-]*)\s*(?:\((.*)\))?$',
    dotAll: true,
  ).firstMatch(input);
  if (match == null) {
    return null;
  }

  final nameRaw = match.group(1) ?? '';
  final rawArgs = (match.group(2) ?? '').trim();
  final args = _parseFunctionArguments(rawArgs);
  if (rawArgs.isNotEmpty && args == null) {
    return null;
  }

  final normalizedArgs = normalizeFallbackToolArguments(
    args ?? const <String, dynamic>{},
  );
  final normalizedName = normalizeFallbackToolName(
    nameRaw,
    arguments: normalizedArgs,
  );
  if (normalizedName.isEmpty) {
    return null;
  }

  if (allowedNames != null && !allowedNames.contains(normalizedName)) {
    return null;
  }

  if (rawArgs.isEmpty && normalizedName == nameRaw) {
    return null;
  }

  return ToolCallParsingUtils.createFunctionToolCall(
    index: 0,
    name: normalizedName,
    arguments: normalizedArgs,
  );
}

final _functionIdentifier = RegExp(r'[A-Za-z_][A-Za-z0-9_.-]*');
final _bareFunctionValue = RegExp(r'[A-Za-z0-9_.+\-]+');

ToolCallFallbackParseResult? _parseLeadingFunctionCall(
  String input, {
  required Set<String>? allowedNames,
  required bool isPartial,
}) {
  if (allowedNames != null && allowedNames.isEmpty) {
    return null;
  }

  final start = input.length - input.trimLeft().length;
  final match = _functionIdentifier.matchAsPrefix(input, start);
  if (match == null) {
    return null;
  }
  final name = match[0]!;
  const pending = ToolCallFallbackParseResult(content: '', toolCalls: []);
  if (isPartial && match.end == input.length) {
    return allowedNames == null ||
            allowedNames.any((candidate) => candidate.startsWith(name))
        ? pending
        : null;
  }
  if (allowedNames != null && !allowedNames.contains(name)) {
    return null;
  }

  final open = _skipFunctionWhitespace(input, match.end);
  if (open == input.length) {
    return isPartial ? pending : null;
  }
  if (input[open] != '(') {
    return null;
  }

  final scan = _scanFunctionArguments(input, open + 1);
  if (scan == null) {
    return null;
  }
  final end = scan.end;
  if (end == null) {
    return isPartial
        ? pending
        : ToolCallFallbackParseResult(content: input, toolCalls: const []);
  }

  final semicolon = _skipCallWhitespace(input, end);
  final afterCall =
      semicolon < input.length &&
          input[semicolon] == ';' &&
          !_containsNewline(input, end, semicolon)
      ? _skipHorizontalWhitespace(input, semicolon + 1)
      : end;
  final suffix = _consumeClosingToolCallTag(
    input,
    from: afterCall,
    isPartial: isPartial,
  );
  if (input.substring(suffix.suffixStart, suffix.holdFrom).trim().isNotEmpty) {
    return null;
  }
  return ToolCallFallbackParseResult(
    content: '',
    toolCalls: [
      ToolCallParsingUtils.createFunctionToolCall(
        index: 0,
        name: name,
        arguments: normalizeFallbackToolArguments(scan.arguments),
      ),
    ],
  );
}

int _skipFunctionWhitespace(String input, int start) {
  var offset = start;
  while (offset < input.length && input[offset].trim().isEmpty) {
    offset++;
  }
  return offset;
}

({int? end, Map<String, dynamic> arguments})? _scanFunctionArguments(
  String input,
  int start,
) {
  const pending = (end: null, arguments: <String, dynamic>{});
  var offset = _skipFunctionWhitespace(input, start);
  if (offset == input.length) return pending;

  if (input[offset] == '{') {
    final object = _scanFunctionValue(input, offset);
    if (object == null) return null;
    if (object.end == null) return pending;
    offset = _skipFunctionWhitespace(input, object.end!);
    if (offset == input.length) return pending;
    return input[offset] == ')'
        ? (end: offset + 1, arguments: object.value! as Map<String, dynamic>)
        : null;
  }

  final arguments = <String, dynamic>{};
  while (offset < input.length) {
    final key = _functionIdentifier.matchAsPrefix(input, offset);
    if (key == null) return null;
    offset = _skipFunctionWhitespace(input, key.end);
    if (offset == input.length && key.end == offset) return pending;
    if (arguments.containsKey(key[0])) return null;
    if (offset == input.length) return pending;
    if (input[offset] != '=') return null;

    offset = _skipFunctionWhitespace(input, offset + 1);
    if (offset == input.length) return pending;
    final value = _scanFunctionValue(input, offset);
    if (value == null) return null;
    if (value.end == null) return pending;
    offset = _skipFunctionWhitespace(input, value.end!);
    if (offset == input.length) return pending;
    arguments[key[0]!] = value.value;
    if (input[offset] == ')') return (end: offset + 1, arguments: arguments);
    if (input[offset] != ',') return null;
    offset = _skipFunctionWhitespace(input, offset + 1);
  }
  return pending;
}

({int? end, Object? value})? _scanFunctionValue(String input, int start) {
  const pending = (end: null, value: null);
  final first = input[start];
  if (first == '"' || first == "'") {
    for (var offset = start + 1; offset < input.length; offset++) {
      if (input[offset] == first) {
        return (end: offset + 1, value: input.substring(start + 1, offset));
      }
      if (input[offset] == r'\') offset++;
    }
    return pending;
  }
  if (first == '{' || first == '[') {
    final scan = _JsonPrefixScanner(
      input,
      start: start,
      endLimit: input.length,
      allowedNames: null,
      strict: true,
    ).scan();
    switch (scan.status) {
      case _JsonScanStatus.invalid:
        return null;
      case _JsonScanStatus.pending:
        return pending;
      case _JsonScanStatus.complete:
        final value = ToolCallParsingUtils.decodeJsonValue(
          input.substring(start, scan.end),
        );
        return value == null ? null : (end: scan.end, value: value);
    }
  }

  final bare = _bareFunctionValue.matchAsPrefix(input, start);
  if (bare == null) return null;
  var end = bare.end;
  if (end < input.length && input[end] == '(') {
    // Older Gemma emissions use unquoted words such as lookup(a).
    var depth = 0;
    do {
      switch (input[end]) {
        case '(':
          depth++;
          end++;
        case ')':
          depth--;
          end++;
        default:
          final word = _bareFunctionValue.matchAsPrefix(input, end);
          if (word == null) return null;
          end = word.end;
      }
    } while (depth > 0 && end < input.length);
    if (depth > 0) return pending;
  }
  final raw = input.substring(start, end);
  final number = int.tryParse(raw) ?? double.tryParse(raw);
  final value = switch (raw) {
    'true' => true,
    'false' => false,
    _ => number != null && number.isFinite ? number : raw,
  };
  return (end: end, value: value);
}

/// Splits `key=value` argument lists on top-level commas only, leaving commas
/// inside single/double-quoted values intact (e.g. `note='a, b'`).
List<String> _splitArgsRespectingQuotes(String raw) {
  final parts = <String>[];
  final buffer = StringBuffer();
  String? quote;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (quote != null) {
      buffer.write(ch);
      if (ch == quote) {
        quote = null;
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      buffer.write(ch);
    } else if (ch == ',') {
      parts.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  if (buffer.isNotEmpty) {
    parts.add(buffer.toString());
  }
  return parts;
}

Map<String, dynamic>? _parseFunctionArguments(String raw) {
  if (raw.trim().isEmpty) {
    return const <String, dynamic>{};
  }

  final asObject = ToolCallParsingUtils.extractFirstJsonObject(raw);
  if (asObject != null) {
    return asObject;
  }

  final result = <String, dynamic>{};
  final pairs = _splitArgsRespectingQuotes(raw);
  for (final rawPair in pairs) {
    final pair = rawPair.trim();
    if (pair.isEmpty) {
      continue;
    }

    final separatorIndex = pair.indexOf('=');
    if (separatorIndex <= 0) {
      return null;
    }

    final key = pair.substring(0, separatorIndex).trim();
    var value = pair.substring(separatorIndex + 1).trim();
    if (key.isEmpty || value.isEmpty) {
      return null;
    }

    if (value.length >= 2 &&
        ((value.startsWith("'") && value.endsWith("'")) ||
            (value.startsWith('"') && value.endsWith('"')))) {
      value = value.substring(1, value.length - 1);
      result[key] = value;
      continue;
    }

    if (value == 'true') {
      result[key] = true;
      continue;
    }

    if (value == 'false') {
      result[key] = false;
      continue;
    }

    final intValue = int.tryParse(value);
    if (intValue != null) {
      result[key] = intValue;
      continue;
    }

    final doubleValue = double.tryParse(value);
    if (doubleValue != null) {
      result[key] = doubleValue;
      continue;
    }

    result[key] = value;
  }

  return result;
}

String _normalizeLooseJsonIdentifiers(String input) {
  var normalized = input;
  normalized = normalized.replaceAllMapped(
    RegExp(r'("name"\s*:\s*)([A-Za-z_][A-Za-z0-9_\.-]*)'),
    (match) => '${match.group(1)}"${match.group(2)}"',
  );
  normalized = normalized.replaceAllMapped(
    RegExp(r'("function"\s*:\s*)([A-Za-z_][A-Za-z0-9_\.-]*)'),
    (match) => '${match.group(1)}"${match.group(2)}"',
  );
  return normalized;
}
