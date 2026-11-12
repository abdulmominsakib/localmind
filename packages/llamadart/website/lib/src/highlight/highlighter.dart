import 'package:syntax_highlight_lite/syntax_highlight_lite.dart';

/// A run of source text; [kind] names its token class, or is null for plain
/// text.
class Token {
  const Token(this.text, [this.kind]);

  final String text;
  final String? kind;

  @override
  String toString() => kind == null ? text : '<$kind>$text</$kind>';
}

/// Highlights fenced code for every language the docs use. Dart uses the
/// TextMate grammar bundled with `syntax_highlight_lite`; the other
/// languages use the small rule sets below, because that package cannot
/// compile the Oniguruma regexes in their TextMate grammars.
///
/// Concatenating the returned tokens always reproduces [source].
Future<List<Token>> highlight(String source, String? language) async {
  final lang = _aliases[language] ?? language;
  if (lang == 'dart') return _highlightDart(source);
  final rules = _rules[lang];
  return rules == null ? [Token(source)] : _lex(source, rules);
}

/// Languages [highlight] colors; anything else renders plain.
Set<String> get highlightedLanguages => {
  'dart',
  ..._rules.keys,
  ..._aliases.keys,
};

const _aliases = {
  'sh': 'bash',
  'shell': 'bash',
  'zsh': 'bash',
  'console': 'bash',
  'yml': 'yaml',
  'javascript': 'js',
  'ts': 'js',
  'typescript': 'js',
  'xml': 'html',
  'markup': 'html',
  'svg': 'html',
  'ps1': 'powershell',
  'pwsh': 'powershell',
  'rb': 'ruby',
};

Future<void>? _dartReady;
HighlighterTheme? _dartTheme;

Future<List<Token>> _highlightDart(String source) async {
  await (_dartReady ??= Highlighter.initialize(['dart']));
  _dartTheme ??= await HighlighterTheme.loadDarkTheme();
  final span = Highlighter(
    language: 'dart',
    theme: _dartTheme!,
  ).highlight(source);
  final tokens = <Token>[];
  void walk(TextSpan span, String? inherited) {
    final kind = _dartKind(span.style) ?? inherited;
    if (span.text case final text? when text.isNotEmpty) {
      tokens.add(Token(text, kind));
    }
    for (final child in span.children) {
      walk(child, kind);
    }
  }

  walk(span, null);
  return tokens;
}

/// Maps the Dark+ colors the Dart grammar resolves to site token classes.
/// Punctuation and rainbow-bracket colors stay plain.
String? _dartKind(TextStyle? style) {
  if (style == null) return null;
  return switch (style.foreground.argb & 0xFFFFFF) {
    0x608B4E || 0x6A9955 => 'comment',
    0xCE9178 || 0xD7BA7D => 'string',
    0x569CD6 || 0xC586C0 => 'keyword',
    0xB5CEA8 => 'number',
    0xDCDCAA => 'function',
    0x4EC9B0 => 'type',
    0x9CDCFE => 'variable',
    _ => null,
  };
}

class _Rule {
  _Rule(String pattern, this.kind, {bool multiLine = false})
    : regex = RegExp(pattern, multiLine: multiLine);

  final RegExp regex;
  final String? kind;
}

List<Token> _lex(String source, List<_Rule> rules) {
  final tokens = <Token>[];
  final plain = StringBuffer();
  void flush() {
    if (plain.isEmpty) return;
    tokens.add(Token(plain.toString()));
    plain.clear();
  }

  var index = 0;
  next:
  while (index < source.length) {
    for (final rule in rules) {
      final match = rule.regex.matchAsPrefix(source, index);
      if (match == null || match.end == index) continue;
      if (rule.kind == null) {
        plain.write(match[0]);
      } else {
        flush();
        tokens.add(Token(match[0]!, rule.kind));
      }
      index = match.end;
      continue next;
    }
    plain.writeCharCode(source.codeUnitAt(index++));
  }
  flush();
  return tokens;
}

final _doubleQuoted = r'"(?:[^"\\\n]|\\.)*"';
final _singleQuoted = r"'(?:[^'\\\n]|\\.)*'";
final _hashComment = r'(?<![^\s])#[^\n]*';
final _number = r'(?<![\w.])-?\d+(?:\.\d+)*(?:[eE][+-]?\d+)?\b';

final Map<String, List<_Rule>> _rules = {
  'bash': [
    _Rule(_hashComment, 'comment'),
    _Rule(_doubleQuoted, 'string'),
    _Rule(r"'[^']*'", 'string'),
    _Rule(r'\$\{[^}\n]*\}|\$[A-Za-z_]\w*|\$[0-9@#?*!$-]', 'variable'),
    _Rule(
      r'\b(?:if|then|else|elif|fi|for|while|until|do|done|case|esac|in|'
          r'function|return|export|local|readonly|unset)\b',
      'keyword',
    ),
    _Rule(
      r'(?<=(?:^|[|;&(]|\$\()[ \t]*)(?:sudo[ \t]+)?[A-Za-z_./][\w./+-]*',
      'function',
      multiLine: true,
    ),
    _Rule(r'(?<![^\s])--?[A-Za-z][\w-]*', 'attribute'),
    _Rule(r'[\w./+-]+', null),
  ],
  'yaml': [
    _Rule(_hashComment, 'comment'),
    _Rule(
      r'''(?<=^[ \t]*(?:-[ \t]+)?)[^\s#'"\-][^:\n#]*?(?=:(?:[ \t]|$))''',
      'key',
      multiLine: true,
    ),
    _Rule(_doubleQuoted, 'string'),
    _Rule(_singleQuoted, 'string'),
    _Rule(r'\b(?:true|false|null|~)\b', 'literal'),
    _Rule(_number, 'number'),
    _Rule(r'[&*][\w-]+', 'variable'),
    _Rule(r'[\w.-]+', null),
  ],
  'json': [
    _Rule(r'"(?:[^"\\\n]|\\.)*"(?=\s*:)', 'key'),
    _Rule(_doubleQuoted, 'string'),
    _Rule(r'\b(?:true|false|null)\b', 'literal'),
    _Rule(_number, 'number'),
  ],
  'js': [
    _Rule(r'//[^\n]*|/\*[\s\S]*?\*/', 'comment'),
    _Rule(_doubleQuoted, 'string'),
    _Rule(_singleQuoted, 'string'),
    _Rule(r'`(?:[^`\\]|\\.)*`', 'string'),
    _Rule(
      r'\b(?:const|let|var|function|return|if|else|for|while|do|of|in|new|'
          r'class|extends|import|export|from|default|async|await|try|catch|'
          r'finally|throw|typeof|instanceof|this|switch|case|break|continue)\b',
      'keyword',
    ),
    _Rule(r'\b(?:true|false|null|undefined)\b', 'literal'),
    _Rule(_number, 'number'),
    _Rule(r'[A-Za-z_$][\w$]*(?=\s*\()', 'function'),
    _Rule(r'[A-Za-z_$][\w$]*', null),
  ],
  'html': [
    _Rule(r'<!--[\s\S]*?-->', 'comment'),
    _Rule(r'</?[A-Za-z][\w:-]*|/?>', 'tag'),
    _Rule(r'(?<=\s)[A-Za-z_:@][\w:.-]*(?=\s*=)', 'attribute'),
    _Rule(_doubleQuoted, 'string'),
    _Rule(_singleQuoted, 'string'),
  ],
  'ruby': [
    _Rule(_doubleQuoted, 'string'),
    _Rule(_singleQuoted, 'string'),
    _Rule(r'#[^\n]*', 'comment'),
    _Rule(
      r'\b(?:def|end|do|if|unless|else|elsif|while|until|for|in|return|'
          r'require|class|module|begin|rescue|ensure|yield|then)\b',
      'keyword',
    ),
    _Rule(r'\b(?:true|false|nil|self)\b', 'literal'),
    _Rule(r'(?<![:\w]):[A-Za-z_]\w*', 'literal'),
    _Rule(_number, 'number'),
    _Rule(r'\b[A-Z]\w*', 'type'),
    _Rule(r'\w+', null),
  ],
  'powershell': [
    _Rule(r'<#[\s\S]*?#>|#[^\n]*', 'comment'),
    _Rule(_doubleQuoted, 'string'),
    _Rule(r"'[^']*'", 'string'),
    _Rule(r'\$[\w:]+', 'variable'),
    _Rule(
      r'\b(?:if|else|elseif|foreach|for|while|function|param|return|try|'
          r'catch|finally|throw)\b',
      'keyword',
    ),
    _Rule(r'\b[A-Z][a-z]+-[A-Z]\w*', 'function'),
    _Rule(r'(?<![^\s])-[A-Za-z]\w*', 'attribute'),
    _Rule(r'\w+', null),
  ],
  'http': [
    _Rule(
      r'^(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b',
      'keyword',
      multiLine: true,
    ),
    _Rule(r'\bHTTP/\d(?:\.\d)?\b', 'literal'),
    _Rule(r'^[\w-]+(?=:)', 'key', multiLine: true),
    _Rule(_doubleQuoted, 'string'),
    _Rule(_number, 'number'),
  ],
};
