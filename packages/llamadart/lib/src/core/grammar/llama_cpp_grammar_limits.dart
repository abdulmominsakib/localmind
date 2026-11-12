import '../exceptions.dart';
import '../llama_logger.dart';

/// llama.cpp's `MAX_REPETITION_THRESHOLD`.
const _maxRepetitionThreshold = 2000;
const _unbounded = -1;

/// Throws [LlamaUnsupportedException] when the shipped llama.cpp runtime would
/// refuse to load [grammar] for its repetition limit.
///
/// A repetition upper bound above the threshold, which llama.cpp replaces
/// with an unbounded repetition, logs a warning instead: the output still
/// matches the rest of the grammar.
void checkTemplateGrammarLimits(String grammar) {
  final budget = _RepetitionBudget(grammar);
  final rejection = budget.rejection();
  if (rejection != null) {
    throw LlamaUnsupportedException(
      'The generated grammar exceeds llama.cpp grammar limits ($rejection). '
      'Pass fewer tools or simpler schemas, or use smaller repetition '
      'bounds.',
    );
  }
  final dropped = budget.droppedBound;
  if (dropped != null) {
    LlamaLogger.instance.warning(
      'The generated grammar $dropped; llama.cpp ignores repetition upper '
      'bounds above $_maxRepetitionThreshold, so that bound is not enforced.',
    );
  }
}

/// Returns why llama.cpp's grammar parser would reject [grammar] for its
/// repetition limit, or `null` when it stays within it or uses syntax this
/// check does not model.
///
/// Mirrors the symbol accounting of `llama_grammar_parser::parse_sequence` in
/// the llama.cpp release the native runtime ships (upstream `v0.9.0`,
/// cd959bae9, for native pin `v0.9.0`): a repeated item counts every symbol
/// created while it was parsed (synthesized groups, repetition rules and
/// first references to rule names), and the product with the repetition count
/// must not exceed `MAX_REPETITION_THRESHOLD`. Releases before upstream
/// 9e0e22059, such as b10549, also rejected a product equal to it.
String? llamaCppRepetitionRejection(String grammar) =>
    _RepetitionBudget(grammar).rejection();

final class _RepetitionBudget {
  _RepetitionBudget(this._source);

  final String _source;

  /// The first repetition upper bound llama.cpp drops, once [rejection] ran.
  String? droppedBound;
  final Set<String> _names = {};
  int _generated = 0;
  int _pos = 0;
  String _rule = '';

  int get _symbols => _names.length + _generated;

  String? rejection() {
    try {
      _skipSpace(newlines: true);
      while (_pos < _source.length) {
        _parseRule();
      }
      return null;
    } on _Rejected catch (rejected) {
      return rejected.message;
    } on _Unparsed {
      // llama.cpp reports syntax errors itself when it loads the grammar.
      return null;
    }
  }

  void _parseRule() {
    _rule = _name();
    _names.add(_rule);
    _skipSpace(newlines: false);
    _expect('::=');
    _skipSpace(newlines: true);
    _alternates(nested: false);
    _skipSpace(newlines: true);
  }

  void _alternates({required bool nested}) {
    _sequence(nested: nested);
    while (_peek == _bar) {
      _pos++;
      _skipSpace(newlines: true);
      _sequence(nested: nested);
    }
  }

  void _sequence({required bool nested}) {
    var previous = 1;
    void repeat(int min, int max) {
      final total = max != _unbounded && max > 0 ? max : (min > 0 ? min : 1);
      if (previous * total > _maxRepetitionThreshold) {
        throw _Rejected(
          'rule $_rule repeats $previous symbols $total times at $_pos',
        );
      }
      _generated += max == _unbounded ? 1 : max - min;
      previous *= total;
    }

    while (_pos < _source.length) {
      final char = _peek;
      if (char == _quote || char == _openBracket) {
        _delimited(char == _quote ? _quote : _closeBracket);
        previous = 1;
      } else if (char == _lessThan || char == _bang) {
        if (char == _bang) _pos++;
        _delimited(_greaterThan);
        previous = 1;
      } else if (_isWordChar(char)) {
        _names.add(_name());
        previous = 1;
      } else if (char == _openParen) {
        _pos++;
        _skipSpace(newlines: true);
        final before = _symbols;
        _generated++;
        _alternates(nested: true);
        _expect(')');
        previous = _symbols - before;
      } else if (char == _dot) {
        _pos++;
        previous = 1;
      } else if (char == _star || char == _plus || char == _question) {
        _pos++;
        repeat(char == _plus ? 1 : 0, char == _question ? 1 : _unbounded);
      } else if (char == _openBrace) {
        _pos++;
        _skipSpace(newlines: nested);
        final min = _int();
        _skipSpace(newlines: nested);
        var max = min;
        if (_peek == _comma) {
          _pos++;
          _skipSpace(newlines: nested);
          max = _isDigit(_peek) ? _int() : _unbounded;
          _skipSpace(newlines: nested);
        }
        _expect('}');
        if (min > _maxRepetitionThreshold) {
          throw _Rejected('rule $_rule repeats $min times');
        }
        if (max > _maxRepetitionThreshold) {
          droppedBound ??= 'bounds a repetition in rule $_rule at $max';
          max = _unbounded;
        }
        repeat(min, max);
      } else {
        return;
      }
      _skipSpace(newlines: nested);
    }
  }

  void _delimited(int end) {
    _pos++;
    while (_peek != end) {
      if (_pos >= _source.length) throw const _Unparsed();
      _pos += _peek == _backslash ? 2 : 1;
    }
    _pos++;
  }

  String _name() {
    final start = _pos;
    while (_isWordChar(_peek)) {
      _pos++;
    }
    if (start == _pos) throw const _Unparsed();
    return _source.substring(start, _pos);
  }

  int _int() {
    final start = _pos;
    while (_isDigit(_peek)) {
      _pos++;
    }
    if (start == _pos) throw const _Unparsed();
    return int.parse(_source.substring(start, _pos));
  }

  void _expect(String token) {
    if (!_source.startsWith(token, _pos)) throw const _Unparsed();
    _pos += token.length;
  }

  void _skipSpace({required bool newlines}) {
    while (_pos < _source.length) {
      final char = _source.codeUnitAt(_pos);
      if (char == _hash) {
        while (_pos < _source.length &&
            _peek != _newline &&
            _peek != _carriageReturn) {
          _pos++;
        }
      } else if (char == _space ||
          char == _tab ||
          newlines && (char == _newline || char == _carriageReturn)) {
        _pos++;
      } else {
        return;
      }
    }
  }

  int get _peek => _pos < _source.length ? _source.codeUnitAt(_pos) : -1;

  static bool _isDigit(int char) => char >= 0x30 && char <= 0x39;

  static bool _isWordChar(int char) =>
      _isDigit(char) ||
      (char >= 0x41 && char <= 0x5A) ||
      (char >= 0x61 && char <= 0x7A) ||
      char == 0x5F ||
      char == 0x2D;
}

const _tab = 0x09;
const _newline = 0x0A;
const _carriageReturn = 0x0D;
const _space = 0x20;
const _bang = 0x21;
const _quote = 0x22;
const _hash = 0x23;
const _openParen = 0x28;
const _star = 0x2A;
const _plus = 0x2B;
const _comma = 0x2C;
const _dot = 0x2E;
const _lessThan = 0x3C;
const _greaterThan = 0x3E;
const _question = 0x3F;
const _openBracket = 0x5B;
const _backslash = 0x5C;
const _closeBracket = 0x5D;
const _openBrace = 0x7B;
const _bar = 0x7C;

final class _Rejected implements Exception {
  _Rejected(this.message);

  final String message;
}

final class _Unparsed implements Exception {
  const _Unparsed();
}
