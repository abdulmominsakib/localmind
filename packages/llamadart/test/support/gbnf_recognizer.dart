/// Decides whether a GBNF grammar accepts a whole string, for the subset the
/// JSON schema converter emits: literals, character classes, groups,
/// alternation, `.`, `? * +`, `{n}`, `{n,}`, `{n,m}` and rule references. Rule
/// references may recurse but not left-recurse.
class GbnfRecognizer {
  GbnfRecognizer(String grammar) {
    for (final line in grammar.split('\n')) {
      final split = line.indexOf(' ::= ');
      if (split > 0) {
        _sources[line.substring(0, split)] = line.substring(split + 5);
      }
    }
  }

  final _sources = <String, String>{};
  final _parsed = <String, _Node>{};
  final _memo = <String, Set<int>>{};
  late List<int> _input;

  bool accepts(String text, {String rule = 'root'}) {
    _input = text.runes.toList();
    _memo.clear();
    return _match(_ruleNode(rule), {0}).contains(_input.length);
  }

  _Node _ruleNode(String name) => _parsed.putIfAbsent(
    name,
    () => _Parser(
      _sources[name] ?? (throw ArgumentError('Undefined rule: $name')),
    ).parse(),
  );

  Set<int> _match(_Node node, Set<int> starts) {
    switch (node) {
      case _Alt(:final options):
        return {for (final option in options) ..._match(option, starts)};
      case _Seq(:final items):
        var at = starts;
        for (final item in items) {
          at = _match(item, at);
          if (at.isEmpty) break;
        }
        return at;
      case _Lit(:final runes):
        return {
          for (final start in starts)
            if (_hasAt(start, runes)) start + runes.length,
        };
      case _Class(:final negated, :final ranges):
        return {
          for (final start in starts)
            if (start < _input.length &&
                ranges.any(
                      (r) => _input[start] >= r.$1 && _input[start] <= r.$2,
                    ) !=
                    negated)
              start + 1,
        };
      case _Ref(:final name):
        return {
          for (final start in starts)
            ..._memo.putIfAbsent(
              '$name@$start',
              () => _match(_ruleNode(name), {start}),
            ),
        };
      case _Repeat(:final item, :final min, :final max):
        var layer = starts;
        final reached = <int>{if (min == 0) ...starts};
        for (
          var count = 1;
          (max == null || count <= max) && layer.isNotEmpty;
          count++
        ) {
          layer = _match(item, layer);
          if (count < min) continue;
          final fresh = layer.difference(reached);
          if (max == null && fresh.isEmpty) break;
          reached.addAll(layer);
          layer = max == null ? fresh : layer;
        }
        return reached;
    }
  }

  bool _hasAt(int start, List<int> runes) {
    if (start + runes.length > _input.length) return false;
    for (var i = 0; i < runes.length; i++) {
      if (_input[start + i] != runes[i]) return false;
    }
    return true;
  }
}

sealed class _Node {}

class _Alt extends _Node {
  _Alt(this.options);
  final List<_Node> options;
}

class _Seq extends _Node {
  _Seq(this.items);
  final List<_Node> items;
}

class _Lit extends _Node {
  _Lit(this.runes);
  final List<int> runes;
}

class _Class extends _Node {
  _Class(this.negated, this.ranges);
  final bool negated;
  final List<(int, int)> ranges;
}

class _Ref extends _Node {
  _Ref(this.name);
  final String name;
}

class _Repeat extends _Node {
  _Repeat(this.item, this.min, this.max);
  final _Node item;
  final int min;
  final int? max;
}

class _Parser {
  _Parser(this.text);

  final String text;
  var _at = 0;

  _Node parse() => _alternatives();

  _Node _alternatives() {
    final options = [_sequence()];
    while (_peek == '|') {
      _at++;
      options.add(_sequence());
    }
    return _Alt(options);
  }

  _Node _sequence() {
    final items = <_Node>[];
    while (true) {
      final c = _peek;
      if (c == null || c == '|' || c == ')') break;
      items.add(_repeated(_atom()));
    }
    return _Seq(items);
  }

  String? get _peek {
    while (_at < text.length && text[_at] == ' ') {
      _at++;
    }
    return _at < text.length ? text[_at] : null;
  }

  _Node _atom() {
    final c = text[_at];
    if (c == '"') {
      final runes = <int>[];
      for (_at++; text[_at] != '"';) {
        runes.add(_char());
      }
      _at++;
      return _Lit(runes);
    }
    if (c == '[') {
      _at++;
      final negated = text[_at] == '^';
      if (negated) _at++;
      final ranges = <(int, int)>[];
      while (text[_at] != ']') {
        final low = _char();
        if (text[_at] == '-' && text[_at + 1] != ']') {
          _at++;
          ranges.add((low, _char()));
        } else {
          ranges.add((low, low));
        }
      }
      _at++;
      return _Class(negated, ranges);
    }
    if (c == '(') {
      _at++;
      final inner = _alternatives();
      _at++;
      return inner;
    }
    if (c == '.') {
      _at++;
      return _Class(true, const []);
    }
    final name = RegExp(r'[A-Za-z0-9-]+').matchAsPrefix(text, _at)![0]!;
    _at += name.length;
    return _Ref(name);
  }

  int _char() {
    if (text[_at] != r'\') return text.codeUnitAt(_at++);
    _at++;
    final c = text[_at++];
    int hex(int digits) {
      final value = int.parse(text.substring(_at, _at + digits), radix: 16);
      _at += digits;
      return value;
    }

    return switch (c) {
      'n' => 10,
      't' => 9,
      'r' => 13,
      'x' => hex(2),
      'u' => hex(4),
      'U' => hex(8),
      _ => c.runes.first,
    };
  }

  _Node _repeated(_Node item) {
    switch (_peek) {
      case '?':
        _at++;
        return _Repeat(item, 0, 1);
      case '*':
        _at++;
        return _Repeat(item, 0, null);
      case '+':
        _at++;
        return _Repeat(item, 1, null);
      case '{':
        final close = text.indexOf('}', _at);
        final bounds = text.substring(_at + 1, close).split(',');
        _at = close + 1;
        final min = int.parse(bounds[0]);
        return _Repeat(
          item,
          min,
          bounds.length == 1
              ? min
              : bounds[1].isEmpty
              ? null
              : int.parse(bounds[1]),
        );
    }
    return item;
  }
}
