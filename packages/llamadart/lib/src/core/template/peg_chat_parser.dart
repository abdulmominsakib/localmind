import 'dart:convert';

import '../models/chat/completion_chunk.dart';
import 'chat_format.dart';
import 'chat_parse_result.dart';

/// Runtime PEG parser for llama.cpp `parser.save()` payloads.
///
/// This executes serialized PEG parsers and maps AST tags to chat payloads,
/// mirroring llama.cpp's `common_chat_peg_parse` behavior.
class PegChatParser {
  static final Map<String, _PegArena> _arenaCache = <String, _PegArena>{};

  /// Parses [output] with a serialized [parser] definition.
  static ChatParseResult parse({
    required String parser,
    required ChatFormat format,
    required String output,
    bool isPartial = false,
    bool parseToolCalls = true,
  }) {
    if (parser.trim().isEmpty) {
      throw StateError('Missing PEG parser definition.');
    }

    final arena = _arenaCache.putIfAbsent(
      parser,
      () => _PegArena.fromSerialized(parser),
    );

    final ctx = _PegParseContext(input: output, isPartial: isPartial);
    final parseResult = arena.parse(ctx);
    if (parseResult.isFail) {
      throw StateError('Failed to parse input at pos ${parseResult.end}.');
    }

    final message = _PegChatMessage();
    final mapper = switch (format) {
      ChatFormat.pegNative => _PegNativeMapper(message),
      ChatFormat.pegConstructed => _PegConstructedMapper(message),
      _ => _PegBaseMapper(message),
    };
    mapper.fromAst(ctx.ast, parseResult);

    final toolCalls = parseToolCalls
        ? message.toolCalls
              .asMap()
              .entries
              .map(
                (entry) => LlamaCompletionChunkToolCall(
                  index: entry.key,
                  id: entry.value.id.isEmpty ? null : entry.value.id,
                  type: 'function',
                  function: LlamaCompletionChunkFunction(
                    name: entry.value.name,
                    arguments: entry.value.arguments,
                  ),
                ),
              )
              .toList(growable: false)
        : const <LlamaCompletionChunkToolCall>[];

    return ChatParseResult(
      content: message.content,
      reasoningContent: message.reasoningContent.isEmpty
          ? null
          : message.reasoningContent,
      toolCalls: toolCalls,
    );
  }
}

class _PegChatMessage {
  String content = '';
  String reasoningContent = '';
  final List<_PegToolCall> toolCalls = <_PegToolCall>[];
}

class _PegToolCall {
  String id = '';
  String name = '';
  String arguments = '';
}

class _PegBaseMapper {
  _PegBaseMapper(this.message);

  final _PegChatMessage message;

  void fromAst(_PegAstArena arena, _PegParseResult result) {
    arena.visitResult(result, map);
  }

  void map(_PegAstNode node) {
    if (node.tag == 'reasoning') {
      message.reasoningContent = _trimTrailingWhitespace(node.text);
      return;
    }
    if (node.tag == 'content') {
      message.content = _trimTrailingWhitespace(node.text);
    }
  }
}

class _PegNativeMapper extends _PegBaseMapper {
  _PegNativeMapper(super.message);

  _PegToolCall? _currentTool;

  @override
  void map(_PegAstNode node) {
    super.map(node);

    if (node.tag == 'tool-open') {
      final tool = _PegToolCall();
      message.toolCalls.add(tool);
      _currentTool = tool;
      return;
    }

    if (node.tag == 'tool-id' && _currentTool != null) {
      _currentTool!.id = _trimTrailingWhitespace(node.text);
      return;
    }

    if (node.tag == 'tool-name' && _currentTool != null) {
      _currentTool!.name = _trimTrailingWhitespace(node.text);
      return;
    }

    if (node.tag == 'tool-args' && _currentTool != null) {
      _currentTool!.arguments = _trimTrailingWhitespace(node.text);
    }
  }
}

class _PegConstructedMapper extends _PegBaseMapper {
  _PegConstructedMapper(super.message);

  _PegToolCall? _currentTool;
  int _argCount = 0;
  bool _needsClosingQuote = false;

  @override
  void map(_PegAstNode node) {
    super.map(node);

    if (node.tag == 'tool-open') {
      final tool = _PegToolCall();
      message.toolCalls.add(tool);
      _currentTool = tool;
      _argCount = 0;
      return;
    }

    if (node.tag == 'tool-name' && _currentTool != null) {
      _currentTool!.name = node.text;
      _currentTool!.arguments = '{';
      return;
    }

    if (node.tag == 'tool-arg-open') {
      _needsClosingQuote = false;
      return;
    }

    if (node.tag == 'tool-arg-name' && _currentTool != null) {
      if (_argCount > 0) {
        _currentTool!.arguments += ',';
      }
      _currentTool!.arguments +=
          '${jsonEncode(_trimTrailingWhitespace(node.text))}:';
      _argCount += 1;
      return;
    }

    if (node.tag == 'tool-arg-string-value' && _currentTool != null) {
      final dumped = jsonEncode(_trimTrailingWhitespace(node.text));
      if (dumped.isNotEmpty) {
        _currentTool!.arguments += dumped.substring(0, dumped.length - 1);
      }
      _needsClosingQuote = true;
      return;
    }

    if (node.tag == 'tool-arg-close' && _currentTool != null) {
      if (_needsClosingQuote) {
        _currentTool!.arguments += '"';
        _needsClosingQuote = false;
      }
      return;
    }

    if (node.tag == 'tool-arg-json-value' && _currentTool != null) {
      _currentTool!.arguments += _trimTrailingWhitespace(node.text);
      return;
    }

    if (node.tag == 'tool-close' && _currentTool != null) {
      if (_needsClosingQuote) {
        _currentTool!.arguments += '"';
        _needsClosingQuote = false;
      }
      _currentTool!.arguments += '}';
    }
  }
}

class _PegArena {
  _PegArena({required this.parsers, required this.rules, required this.root});

  final List<Map<String, dynamic>> parsers;
  final Map<String, int> rules;
  final int root;

  factory _PegArena.fromSerialized(String data) {
    final decoded = jsonDecode(data);
    if (decoded is! Map) {
      throw StateError('Invalid parser JSON: expected object root.');
    }

    final parserList = decoded['parsers'];
    final ruleMap = decoded['rules'];
    final root = decoded['root'];

    if (parserList is! List) {
      throw StateError('Invalid parser JSON: missing parsers array.');
    }
    if (ruleMap is! Map) {
      throw StateError('Invalid parser JSON: missing rules object.');
    }
    if (root is! num) {
      throw StateError('Invalid parser JSON: missing root.');
    }

    final parsers = parserList
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    final rules = <String, int>{};
    for (final entry in ruleMap.entries) {
      final value = entry.value;
      if (value is! num) {
        throw StateError('Invalid rule id for ${entry.key}.');
      }
      rules[entry.key.toString()] = value.toInt();
    }

    return _PegArena(parsers: parsers, rules: rules, root: root.toInt());
  }

  _PegParseResult parse(_PegParseContext ctx, [int? start]) {
    if (root < 0 || root >= parsers.length) {
      throw StateError('No root parser set.');
    }
    return _parseNode(root, ctx, start ?? 0);
  }

  _PegParseResult _parseNode(int id, _PegParseContext ctx, int startPos) {
    if (id < 0 || id >= parsers.length) {
      throw StateError('Invalid parser id: $id');
    }

    final node = parsers[id];
    final type = node['type'];
    if (type is! String) {
      throw StateError('Parser node missing type field: $node');
    }

    switch (type) {
      case 'epsilon':
        return _PegParseResult.success(startPos, startPos);
      case 'start':
        return startPos == 0
            ? _PegParseResult.success(startPos, startPos)
            : _PegParseResult.fail(startPos, startPos);
      case 'end':
        return startPos >= ctx.input.length
            ? _PegParseResult.success(startPos, startPos)
            : _PegParseResult.fail(startPos, startPos);
      case 'literal':
        return _parseLiteral(node, ctx, startPos);
      case 'sequence':
        return _parseSequence(node, ctx, startPos);
      case 'choice':
        return _parseChoice(node, ctx, startPos);
      case 'repetition':
        return _parseRepetition(node, ctx, startPos);
      case 'and':
        return _parseAnd(node, ctx, startPos);
      case 'not':
        return _parseNot(node, ctx, startPos);
      case 'any':
        return _parseAny(ctx, startPos);
      case 'space':
        return _parseSpace(ctx, startPos);
      case 'chars':
        return _parseChars(node, ctx, startPos);
      case 'json_string':
        return _parseJsonString(ctx, startPos);
      case 'until':
        return _parseUntil(node, ctx, startPos);
      case 'schema':
        return _parseNode(_intField(node, 'child'), ctx, startPos);
      case 'rule':
        return _parseRule(node, ctx, startPos);
      case 'tag':
        return _parseTag(node, ctx, startPos);
      case 'ref':
        return _parseRef(node, ctx, startPos);
      case 'atomic':
        return _parseAtomic(node, ctx, startPos);
      default:
        throw StateError('Unknown parser type: $type');
    }
  }

  _PegParseResult _parseLiteral(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final literal = _stringField(node, 'literal');
    var pos = startPos;
    for (var i = 0; i < literal.length; i++) {
      if (pos >= ctx.input.length) {
        if (!ctx.isPartial) {
          return _PegParseResult.fail(startPos, pos);
        }
        return _PegParseResult.needMore(startPos, pos);
      }
      if (ctx.input.codeUnitAt(pos) != literal.codeUnitAt(i)) {
        return _PegParseResult.fail(startPos, pos);
      }
      pos += 1;
    }
    return _PegParseResult.success(startPos, pos);
  }

  _PegParseResult _parseSequence(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final children = _intListField(node, 'children');
    var pos = startPos;
    final astNodes = <int>[];

    for (final childId in children) {
      final result = _parseNode(childId, ctx, pos);
      if (result.isFail) {
        return _PegParseResult.fail(startPos, result.end);
      }
      if (result.nodes.isNotEmpty) {
        astNodes.addAll(result.nodes);
      }
      if (result.isNeedMoreInput) {
        return _PegParseResult.needMore(startPos, result.end, nodes: astNodes);
      }
      pos = result.end;
    }

    return _PegParseResult.success(startPos, pos, nodes: astNodes);
  }

  _PegParseResult _parseChoice(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final children = _intListField(node, 'children');
    for (final childId in children) {
      final result = _parseNode(childId, ctx, startPos);
      if (!result.isFail) {
        return result;
      }
    }
    return _PegParseResult.fail(startPos, startPos);
  }

  _PegParseResult _parseRepetition(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final child = _intField(node, 'child');
    final minCount = _intField(node, 'min_count');
    final maxCount = _intField(node, 'max_count');

    var pos = startPos;
    var matchCount = 0;
    final astNodes = <int>[];

    while (maxCount == -1 || matchCount < maxCount) {
      if (pos >= ctx.input.length) {
        break;
      }

      final result = _parseNode(child, ctx, pos);
      if (result.isSuccess) {
        if (result.end == pos) {
          break;
        }
        if (result.nodes.isNotEmpty) {
          astNodes.addAll(result.nodes);
        }
        pos = result.end;
        matchCount += 1;
        continue;
      }

      if (result.isNeedMoreInput) {
        if (result.nodes.isNotEmpty) {
          astNodes.addAll(result.nodes);
        }
        return _PegParseResult.needMore(startPos, result.end, nodes: astNodes);
      }

      break;
    }

    if (minCount > 0 && matchCount < minCount) {
      if (pos >= ctx.input.length && ctx.isPartial) {
        return _PegParseResult.needMore(startPos, pos, nodes: astNodes);
      }
      return _PegParseResult.fail(startPos, pos);
    }

    return _PegParseResult.success(startPos, pos, nodes: astNodes);
  }

  _PegParseResult _parseAnd(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final child = _intField(node, 'child');
    final result = _parseNode(child, ctx, startPos);
    if (result.isNeedMoreInput) {
      return _PegParseResult.needMore(startPos, startPos);
    }
    if (result.isSuccess) {
      return _PegParseResult.success(startPos, startPos);
    }
    return _PegParseResult.fail(startPos, startPos);
  }

  _PegParseResult _parseNot(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final child = _intField(node, 'child');
    final result = _parseNode(child, ctx, startPos);
    if (result.isSuccess) {
      return _PegParseResult.fail(startPos, startPos);
    }
    if (result.isNeedMoreInput) {
      return _PegParseResult.needMore(startPos, startPos);
    }
    return _PegParseResult.success(startPos, startPos);
  }

  _PegParseResult _parseAny(_PegParseContext ctx, int startPos) {
    final cp = _parseCodePointAt(ctx.input, startPos);
    if (cp.isIncomplete) {
      if (!ctx.isPartial) {
        return _PegParseResult.fail(startPos, startPos);
      }
      return _PegParseResult.needMore(startPos, startPos);
    }
    if (cp.isInvalid) {
      return _PegParseResult.fail(startPos, startPos);
    }
    return _PegParseResult.success(startPos, startPos + cp.codeUnitLength);
  }

  _PegParseResult _parseSpace(_PegParseContext ctx, int startPos) {
    var pos = startPos;
    while (pos < ctx.input.length) {
      final cp = _parseCodePointAt(ctx.input, pos);
      if (cp.isInvalid || cp.isIncomplete) {
        break;
      }
      if (!_isWhitespaceCodePoint(cp.codePoint)) {
        break;
      }
      pos += cp.codeUnitLength;
    }
    return _PegParseResult.success(startPos, pos);
  }

  _PegParseResult _parseChars(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final rangeJson = node['ranges'];
    if (rangeJson is! List) {
      throw StateError('chars parser missing ranges field');
    }

    final ranges = <_PegCharRange>[];
    for (final item in rangeJson) {
      if (item is! Map) {
        throw StateError('Invalid char range entry: $item');
      }
      final map = Map<String, dynamic>.from(item);
      ranges.add(
        _PegCharRange(
          start: _intField(map, 'start'),
          end: _intField(map, 'end'),
        ),
      );
    }

    final negated = _boolField(node, 'negated');
    final minCount = _intField(node, 'min_count');
    final maxCount = _intField(node, 'max_count');

    var pos = startPos;
    var matchCount = 0;

    while (maxCount == -1 || matchCount < maxCount) {
      final cp = _parseCodePointAt(ctx.input, pos);
      if (cp.isIncomplete) {
        if (matchCount >= minCount) {
          return _PegParseResult.success(startPos, pos);
        }
        if (!ctx.isPartial) {
          return _PegParseResult.fail(startPos, startPos);
        }
        return _PegParseResult.needMore(startPos, pos);
      }
      if (cp.isInvalid) {
        if (matchCount >= minCount) {
          return _PegParseResult.success(startPos, pos);
        }
        return _PegParseResult.fail(startPos, startPos);
      }

      var matches = false;
      for (final range in ranges) {
        if (range.contains(cp.codePoint)) {
          matches = true;
          break;
        }
      }
      if (negated) {
        matches = !matches;
      }

      if (!matches) {
        break;
      }

      pos += cp.codeUnitLength;
      matchCount += 1;
    }

    if (matchCount < minCount) {
      if (pos >= ctx.input.length && ctx.isPartial) {
        return _PegParseResult.needMore(startPos, pos);
      }
      return _PegParseResult.fail(startPos, pos);
    }

    return _PegParseResult.success(startPos, pos);
  }

  _PegParseResult _parseJsonString(_PegParseContext ctx, int startPos) {
    var pos = startPos;

    while (pos < ctx.input.length) {
      final unit = ctx.input.codeUnitAt(pos);

      if (unit == 0x22) {
        return _PegParseResult.success(startPos, pos);
      }

      if (unit == 0x5c) {
        pos += 1;
        if (pos >= ctx.input.length) {
          if (!ctx.isPartial) {
            return _PegParseResult.fail(startPos, startPos);
          }
          return _PegParseResult.needMore(startPos, pos);
        }

        final escaped = ctx.input.codeUnitAt(pos);
        if (_isSimpleJsonEscape(escaped)) {
          pos += 1;
          continue;
        }

        if (escaped == 0x75) {
          pos += 1;
          for (var i = 0; i < 4; i++) {
            if (pos >= ctx.input.length) {
              if (!ctx.isPartial) {
                return _PegParseResult.fail(startPos, startPos);
              }
              return _PegParseResult.needMore(startPos, pos);
            }
            if (!_isHexDigitCodeUnit(ctx.input.codeUnitAt(pos))) {
              return _PegParseResult.fail(startPos, startPos);
            }
            pos += 1;
          }
          continue;
        }

        return _PegParseResult.fail(startPos, startPos);
      }

      final cp = _parseCodePointAt(ctx.input, pos);
      if (cp.isIncomplete) {
        if (!ctx.isPartial) {
          return _PegParseResult.fail(startPos, startPos);
        }
        return _PegParseResult.needMore(startPos, pos);
      }
      if (cp.isInvalid) {
        return _PegParseResult.fail(startPos, startPos);
      }
      pos += cp.codeUnitLength;
    }

    if (!ctx.isPartial) {
      return _PegParseResult.fail(startPos, pos);
    }
    return _PegParseResult.needMore(startPos, pos);
  }

  _PegParseResult _parseUntil(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final delimiters = _stringListField(node, 'delimiters');

    var pos = startPos;
    var lastValidPos = startPos;

    while (pos < ctx.input.length) {
      final cp = _parseCodePointAt(ctx.input, pos);
      if (cp.isIncomplete) {
        if (!ctx.isPartial) {
          return _PegParseResult.fail(startPos, startPos);
        }
        return _PegParseResult.needMore(startPos, lastValidPos);
      }
      if (cp.isInvalid) {
        return _PegParseResult.fail(startPos, startPos);
      }

      final delimiterState = _matchDelimiterAt(ctx.input, pos, delimiters);
      if (delimiterState == _DelimiterMatchState.complete ||
          delimiterState == _DelimiterMatchState.partial) {
        return _PegParseResult.success(startPos, pos);
      }

      pos += cp.codeUnitLength;
      lastValidPos = pos;
    }

    if (lastValidPos == ctx.input.length && ctx.isPartial) {
      return _PegParseResult.needMore(startPos, lastValidPos);
    }
    return _PegParseResult.success(startPos, lastValidPos);
  }

  _PegParseResult _parseRule(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final child = _intField(node, 'child');
    final name = _stringField(node, 'name');

    final result = _parseNode(child, ctx, startPos);
    if (result.isFail) {
      return result;
    }

    final text = result.start < ctx.input.length
        ? ctx.input.substring(result.start, result.end)
        : '';
    final nodeId = ctx.ast.addNode(
      rule: name,
      tag: '',
      start: result.start,
      end: result.end,
      text: text,
      children: result.nodes,
      isPartial: result.isNeedMoreInput,
    );

    return _PegParseResult(
      type: result.type,
      start: result.start,
      end: result.end,
      nodes: <int>[nodeId],
    );
  }

  _PegParseResult _parseTag(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final child = _intField(node, 'child');
    final tag = _stringField(node, 'tag');

    final result = _parseNode(child, ctx, startPos);
    if (result.isFail) {
      return result;
    }

    final text = result.start < ctx.input.length
        ? ctx.input.substring(result.start, result.end)
        : '';
    final nodeId = ctx.ast.addNode(
      rule: '',
      tag: tag,
      start: result.start,
      end: result.end,
      text: text,
      children: result.nodes,
      isPartial: result.isNeedMoreInput,
    );

    return _PegParseResult(
      type: result.type,
      start: result.start,
      end: result.end,
      nodes: <int>[nodeId],
    );
  }

  _PegParseResult _parseRef(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final name = _stringField(node, 'name');
    final ruleId = rules[name];
    if (ruleId == null) {
      throw StateError('Rule not found: $name');
    }
    return _parseNode(ruleId, ctx, startPos);
  }

  _PegParseResult _parseAtomic(
    Map<String, dynamic> node,
    _PegParseContext ctx,
    int startPos,
  ) {
    final child = _intField(node, 'child');
    final result = _parseNode(child, ctx, startPos);
    if (result.isNeedMoreInput) {
      return _PegParseResult.needMore(result.start, result.end);
    }
    return result;
  }

  static int _intField(Map<String, dynamic> node, String key) {
    final value = node[key];
    if (value is num) {
      return value.toInt();
    }
    throw StateError('Invalid or missing int field "$key" in $node');
  }

  static bool _boolField(Map<String, dynamic> node, String key) {
    final value = node[key];
    if (value is bool) {
      return value;
    }
    throw StateError('Invalid or missing bool field "$key" in $node');
  }

  static String _stringField(Map<String, dynamic> node, String key) {
    final value = node[key];
    if (value is String) {
      return value;
    }
    throw StateError('Invalid or missing string field "$key" in $node');
  }

  static List<int> _intListField(Map<String, dynamic> node, String key) {
    final value = node[key];
    if (value is! List) {
      throw StateError('Invalid or missing int-list field "$key" in $node');
    }
    return value
        .map((e) {
          if (e is num) {
            return e.toInt();
          }
          throw StateError('Invalid list entry for "$key": $e');
        })
        .toList(growable: false);
  }

  static List<String> _stringListField(Map<String, dynamic> node, String key) {
    final value = node[key];
    if (value is! List) {
      throw StateError('Invalid or missing string-list field "$key" in $node');
    }
    return value
        .map((e) {
          if (e is String) {
            return e;
          }
          throw StateError('Invalid list entry for "$key": $e');
        })
        .toList(growable: false);
  }
}

class _PegParseContext {
  _PegParseContext({required this.input, required this.isPartial});

  final String input;
  final bool isPartial;
  final _PegAstArena ast = _PegAstArena();
}

class _PegParseResult {
  const _PegParseResult({
    required this.type,
    required this.start,
    required this.end,
    this.nodes = const <int>[],
  });

  factory _PegParseResult.fail(int start, int end) =>
      _PegParseResult(type: _PegResultType.fail, start: start, end: end);

  factory _PegParseResult.success(
    int start,
    int end, {
    List<int> nodes = const <int>[],
  }) => _PegParseResult(
    type: _PegResultType.success,
    start: start,
    end: end,
    nodes: nodes,
  );

  factory _PegParseResult.needMore(
    int start,
    int end, {
    List<int> nodes = const <int>[],
  }) => _PegParseResult(
    type: _PegResultType.needMoreInput,
    start: start,
    end: end,
    nodes: nodes,
  );

  final _PegResultType type;
  final int start;
  final int end;
  final List<int> nodes;

  bool get isFail => type == _PegResultType.fail;
  bool get isSuccess => type == _PegResultType.success;
  bool get isNeedMoreInput => type == _PegResultType.needMoreInput;
}

enum _PegResultType { fail, success, needMoreInput }

class _PegAstNode {
  const _PegAstNode({
    required this.id,
    required this.rule,
    required this.tag,
    required this.start,
    required this.end,
    required this.text,
    required this.children,
    required this.isPartial,
  });

  final int id;
  final String rule;
  final String tag;
  final int start;
  final int end;
  final String text;
  final List<int> children;
  final bool isPartial;
}

class _PegAstArena {
  final List<_PegAstNode> _nodes = <_PegAstNode>[];

  int addNode({
    required String rule,
    required String tag,
    required int start,
    required int end,
    required String text,
    required List<int> children,
    required bool isPartial,
  }) {
    final id = _nodes.length;
    _nodes.add(
      _PegAstNode(
        id: id,
        rule: rule,
        tag: tag,
        start: start,
        end: end,
        text: text,
        children: List<int>.unmodifiable(children),
        isPartial: isPartial,
      ),
    );
    return id;
  }

  _PegAstNode getNode(int id) {
    if (id < 0 || id >= _nodes.length) {
      throw StateError('Invalid AST node id: $id');
    }
    return _nodes[id];
  }

  void visitNode(int id, void Function(_PegAstNode node) visitor) {
    final node = getNode(id);
    visitor(node);
    for (final childId in node.children) {
      visitNode(childId, visitor);
    }
  }

  void visitResult(
    _PegParseResult result,
    void Function(_PegAstNode node) visitor,
  ) {
    for (final nodeId in result.nodes) {
      visitNode(nodeId, visitor);
    }
  }
}

class _PegCharRange {
  const _PegCharRange({required this.start, required this.end});

  final int start;
  final int end;

  bool contains(int value) => value >= start && value <= end;
}

class _CodePointResult {
  const _CodePointResult._({
    required this.status,
    required this.codePoint,
    required this.codeUnitLength,
  });

  const _CodePointResult.valid(int codePoint, int codeUnitLength)
    : this._(
        status: _CodePointStatus.valid,
        codePoint: codePoint,
        codeUnitLength: codeUnitLength,
      );

  const _CodePointResult.invalid()
    : this._(
        status: _CodePointStatus.invalid,
        codePoint: -1,
        codeUnitLength: 0,
      );

  const _CodePointResult.incomplete()
    : this._(
        status: _CodePointStatus.incomplete,
        codePoint: -1,
        codeUnitLength: 0,
      );

  final _CodePointStatus status;
  final int codePoint;
  final int codeUnitLength;

  bool get isInvalid => status == _CodePointStatus.invalid;
  bool get isIncomplete => status == _CodePointStatus.incomplete;
}

enum _CodePointStatus { valid, invalid, incomplete }

_CodePointResult _parseCodePointAt(String input, int index) {
  if (index >= input.length) {
    return const _CodePointResult.incomplete();
  }

  final first = input.codeUnitAt(index);
  if (first >= 0xD800 && first <= 0xDBFF) {
    if (index + 1 >= input.length) {
      return const _CodePointResult.incomplete();
    }
    final second = input.codeUnitAt(index + 1);
    if (second < 0xDC00 || second > 0xDFFF) {
      return const _CodePointResult.invalid();
    }
    final high = first - 0xD800;
    final low = second - 0xDC00;
    final codePoint = 0x10000 + ((high << 10) | low);
    return _CodePointResult.valid(codePoint, 2);
  }

  if (first >= 0xDC00 && first <= 0xDFFF) {
    return const _CodePointResult.invalid();
  }

  return _CodePointResult.valid(first, 1);
}

enum _DelimiterMatchState { noMatch, partial, complete }

_DelimiterMatchState _matchDelimiterAt(
  String input,
  int pos,
  List<String> delimiters,
) {
  for (final delimiter in delimiters) {
    if (delimiter.isEmpty) {
      continue;
    }
    if (pos + delimiter.length <= input.length &&
        input.startsWith(delimiter, pos)) {
      return _DelimiterMatchState.complete;
    }
    if (pos < input.length) {
      final tail = input.substring(pos);
      if (delimiter.startsWith(tail)) {
        return _DelimiterMatchState.partial;
      }
    }
  }
  return _DelimiterMatchState.noMatch;
}

bool _isWhitespaceCodePoint(int codePoint) {
  return String.fromCharCode(codePoint).trim().isEmpty;
}

bool _isHexDigitCodeUnit(int unit) {
  return (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x46) ||
      (unit >= 0x61 && unit <= 0x66);
}

bool _isSimpleJsonEscape(int unit) {
  return unit == 0x22 ||
      unit == 0x5c ||
      unit == 0x2f ||
      unit == 0x62 ||
      unit == 0x66 ||
      unit == 0x6e ||
      unit == 0x72 ||
      unit == 0x74;
}

String _trimTrailingWhitespace(String input) {
  return input.replaceFirst(RegExp(r'\s+$'), '');
}
