import 'dart:collection';

import 'package:dinja/ast.dart';
import 'package:dinja/dinja.dart';

/// Renders a Jinja template while recording which input values it reads and
/// which operations it applies to them, as llama.cpp's `jinja::caps_get`
/// does with value usage statistics at llama.cpp 7fe450e19.
///
/// The template is rewritten so that every identifier lookup, member access,
/// filter, test and `for` iterable passes its value through a recording
/// function first, and is then rendered with dinja. A value is *used* when
/// llama.cpp would mark it used; an operation is recorded under llama.cpp's
/// name for it: `array_access` for integer subscripts and `for` loops,
/// `object_access` for string subscripts and attributes, `test_is_<name>`
/// for tests, and the filter or attribute name for filters and built-ins.
///
/// As in llama.cpp, a `for` loop over a string throws. dinja iterates its
/// characters instead, so templates rendered for inference are unaffected.
class JinjaUsageProbe {
  JinjaUsageProbe._(this._template);

  final Template _template;

  /// Builds a probe for [program], as returned by `parseTemplate`.
  ///
  /// Throws [UnsupportedError] if [program] holds a node type this probe
  /// does not know, or dinja's exception if the rewritten source does not
  /// parse.
  factory JinjaUsageProbe(Program program) {
    final source = (_Rewriter(
      instrument: true,
    )..statements(program.body)).toString();
    return JinjaUsageProbe._(Template(source));
  }

  /// Writes [program] back as Jinja source that parses to an equivalent
  /// program: the same nodes and values, except that comments and
  /// `generation` tags are dropped and template text becomes string literals.
  static String writeSource(Program program) =>
      (_Rewriter(instrument: false)..statements(program.body)).toString();

  /// Renders the template with [context] and returns what it read.
  ///
  /// [context] values may be [JinjaValue]s; their identity is kept, so
  /// [JinjaUsageRun.used] and [JinjaUsageRun.ops] can be asked about them.
  JinjaUsageRun render(Map<String, Object?> context) {
    final stats = LinkedHashMap<JinjaValue, Set<String>>.identity();
    void use(JinjaValue value, [String? op]) {
      final ops = stats.putIfAbsent(value, () => <String>{});
      if (op != null) ops.add(op);
    }

    void useDeep(JinjaValue value) {
      use(value);
      if (value is JinjaList) {
        value.items.forEach(useDeep);
      } else if (value is JinjaTuple) {
        value.items.forEach(useDeep);
      } else if (value is JinjaMap) {
        for (final entry in value.items.entries) {
          useDeep(entry.key);
          useDeep(entry.value);
        }
      }
    }

    JinjaValue arg(List<JinjaValue> args, int index) =>
        index < args.length ? args[index] : const JinjaUndefined();

    final hooks = <String, Object?>{
      _use: JinjaFunction(_use, (args, _) {
        final value = arg(args, 0);
        use(value);
        return value;
      }),
      _member: JinjaFunction(_member, (args, _) {
        final object = arg(args, 0);
        final property = arg(args, 1);
        use(object);
        if (property is JinjaInteger) {
          use(object, 'array_access');
        } else if (property is JinjaStringValue) {
          final key = property.toString();
          if (object is! JinjaMap || !object.items.containsKey(property)) {
            use(object, key);
          }
          use(object, 'object_access');
        }
        return object;
      }),
      _attribute: JinjaFunction(_attribute, (args, _) {
        final object = arg(args, 0);
        use(object, arg(args, 1).toString());
        use(object, 'object_access');
        return object;
      }),
      _slice: JinjaFunction(_slice, (args, _) {
        final object = arg(args, 0);
        use(object, 'slice');
        return object;
      }),
      _filter: JinjaFunction(_filter, (args, _) {
        final value = arg(args, 0);
        final name = arg(args, 1).toString();
        use(value, name);
        if (name == 'tojson' ||
            (name == 'string' && (value is JinjaList || value is JinjaMap))) {
          useDeep(value);
        }
        return value;
      }),
      _test: JinjaFunction(_test, (args, _) {
        final value = arg(args, 0);
        use(value, 'test_is_${arg(args, 1)}');
        return value;
      }),
      _iterate: JinjaFunction(_iterate, (args, _) {
        final value = arg(args, 0);
        use(value, 'array_access');
        if (value is JinjaMap) use(value, 'object_access');
        if (value is JinjaStringValue) {
          throw const _StringIterationError();
        }
        return value;
      }),
    };

    try {
      final output = _template.render(<String, Object?>{...context, ...hooks});
      return JinjaUsageRun._(true, output, stats, null);
    } catch (error) {
      return JinjaUsageRun._(false, '', stats, error);
    }
  }

  static const String _use = '__llamadart_use';
  static const String _member = '__llamadart_member';
  static const String _attribute = '__llamadart_attribute';
  static const String _slice = '__llamadart_slice';
  static const String _filter = '__llamadart_filter';
  static const String _test = '__llamadart_test';
  static const String _iterate = '__llamadart_iterate';
}

/// Thrown for a `for` loop over a string, which llama.cpp rejects.
class _StringIterationError implements Exception {
  const _StringIterationError();

  @override
  String toString() =>
      'Expected iterable or object type in for loop: got String';
}

/// The result of one [JinjaUsageProbe.render].
class JinjaUsageRun {
  JinjaUsageRun._(this.success, this.output, this._stats, this.error);

  /// Whether the render completed without throwing.
  final bool success;

  /// The rendered text, or an empty string when the render threw.
  final String output;

  /// What the render threw, or `null` when it succeeded.
  final Object? error;

  final Map<JinjaValue, Set<String>> _stats;

  /// Whether the template read [value] before finishing or throwing.
  bool used(JinjaValue value) => _stats.containsKey(value);

  /// The operations the template applied to [value].
  Set<String> ops(JinjaValue value) => _stats[value] ?? const <String>{};
}

/// Writes a [Program] back as Jinja source that parses to an equivalent
/// program. With [instrument], identifier lookups, member accesses, filters,
/// tests and `for` iterables also pass through the probe's recording
/// functions. Every compound expression is parenthesized, negative numbers
/// too, and template text is written as string literals, so the written
/// template renders the same text as the original.
class _Rewriter {
  _Rewriter({required this.instrument});

  final bool instrument;
  final StringBuffer _out = StringBuffer();

  @override
  String toString() => _out.toString();

  void statements(List<Statement> body) => body.forEach(statement);

  void statement(Statement node) {
    switch (node) {
      case CommentStatement() || NoopStatement():
        return;
      case StringLiteral(:final value):
        _out.write('{{ ${_literal(value)} }}');
      case IfStatement(:final test, :final body, :final alternate):
        _out.write('{% if ${expression(test)} %}');
        statements(body);
        if (alternate.isNotEmpty) {
          _out.write('{% else %}');
          statements(alternate);
        }
        _out.write('{% endif %}');
      case ForStatement(
        :final loopVar,
        :final iterable,
        :final body,
        :final defaultBlock,
      ):
        final iterated = iterable is SelectExpression
            ? '${_iterable(iterable.lhs)} if ${expression(iterable.test)}'
            : _iterable(iterable);
        _out.write('{% for ${_plain(loopVar)} in $iterated %}');
        statements(body);
        if (defaultBlock.isNotEmpty) {
          _out.write('{% else %}');
          statements(defaultBlock);
        }
        _out.write('{% endfor %}');
      case SetStatement(:final assignee, :final value, :final body):
        if (value != null) {
          _out.write('{% set ${_plain(assignee)} = ${expression(value)} %}');
        } else {
          _out.write('{% set ${_plain(assignee)} %}');
          statements(body);
          _out.write('{% endset %}');
        }
      case MacroStatement(:final name, :final args, :final body):
        _out.write('{% macro ${_primary(name)}(${_parameters(args)}) %}');
        statements(body);
        _out.write('{% endmacro %}');
      case CallStatement(:final call, :final callerArgs, :final body):
        final callerParameters = callerArgs.isEmpty
            ? ''
            : '(${_parameters(callerArgs)})';
        _out.write(
          '{% call$callerParameters ${_primary(call.callee)}'
          '(${_arguments(call.args)}) %}',
        );
        statements(body);
        _out.write('{% endcall %}');
      case FilterStatement(:final filter, :final body):
        _out.write('{% filter ${_callable(filter)} %}');
        statements(body);
        _out.write('{% endfilter %}');
      case DoStatement(:final expr):
        _out.write('{% do ${expression(expr)} %}');
      case BreakStatement():
        _out.write('{% break %}');
      case ContinueStatement():
        _out.write('{% continue %}');
      case Expression():
        _out.write('{{ ${expression(node)} }}');
      default:
        throw UnsupportedError('Unsupported statement ${node.type}');
    }
  }

  String expression(Expression node) {
    switch (node) {
      case Identifier(:final name):
        return instrument ? _call(JinjaUsageProbe._use, [name]) : name;
      case IntegerLiteral(:final value):
        return _number('$value', negative: value.isNegative);
      case FloatLiteral(:final value):
        return _number(_decimal(value), negative: value.isNegative);
      case StringLiteral(:final value):
        return _literal(value);
      case ArrayLiteral(:final items):
        return '[${items.map(expression).join(', ')}]';
      case TupleLiteral(:final items):
        return '(${items.map(expression).join(', ')})';
      case ObjectLiteral(:final items):
        final entries = items.map(
          (entry) => '${expression(entry.key)}: ${expression(entry.value)}',
        );
        return '({${entries.join(', ')}})';
      case MemberExpression(:final object, :final property, :final computed):
        final member = _member(
          expression(object),
          property,
          computed: computed,
        );
        return instrument ? _call(JinjaUsageProbe._use, [member]) : member;
      case CallExpression(:final callee, :final args):
        return '(${expression(callee)}(${_arguments(args)}))';
      case BinaryExpression(:final op, :final left, :final right):
        return '(${expression(left)} ${op.value} ${expression(right)})';
      case UnaryExpression(:final op, :final argument):
        return '(${op.value} ${expression(argument)})';
      case FilterExpression(:final operand, :final filter):
        final value = instrument
            ? _call(JinjaUsageProbe._filter, [
                expression(operand),
                _literal(_calleeName(filter)),
              ])
            : expression(operand);
        return '($value | ${_callable(filter)})';
      case TestExpression(:final operand, :final negate, :final test):
        final value = instrument
            ? _call(JinjaUsageProbe._test, [
                expression(operand),
                _literal(_calleeName(test)),
              ])
            : expression(operand);
        return '($value is ${negate ? 'not ' : ''}${_callable(test)})';
      case SelectExpression(:final lhs, :final test):
        return '(${expression(lhs)} if ${expression(test)})';
      case TernaryExpression(
        :final condition,
        :final trueExpr,
        :final falseExpr,
      ):
        return '(${expression(trueExpr)} if ${expression(condition)} '
            'else ${expression(falseExpr)})';
      default:
        throw UnsupportedError('Unsupported expression ${node.type}');
    }
  }

  String _iterable(Expression node) => instrument
      ? _call(JinjaUsageProbe._iterate, [expression(node)])
      : expression(node);

  String _member(String object, Expression property, {required bool computed}) {
    if (computed && property is SliceExpression) {
      String bound(Expression? value) => value == null ? '' : expression(value);
      final step = property.step == null ? '' : ':${bound(property.step)}';
      return '${_recorded(JinjaUsageProbe._slice, [object])}'
          '[${bound(property.start)}:${bound(property.stop)}$step]';
    }
    if (computed && property is BlankExpression) {
      return '${_recorded(JinjaUsageProbe._slice, [object])}[]';
    }
    if (computed) {
      final key = expression(property);
      return '${_recorded(JinjaUsageProbe._member, [object, key])}[$key]';
    }
    if (property is Identifier) {
      final name = property.name;
      return '${_recorded(JinjaUsageProbe._attribute, [object, _literal(name)])}'
          '.$name';
    }
    final key = _plain(property);
    return '${_recorded(JinjaUsageProbe._member, [object, key])}.($key)';
  }

  /// [args] recorded by [function] when instrumenting, else the object alone.
  String _recorded(String function, List<String> args) =>
      instrument ? _call(function, args) : args.first;

  /// Macro and caller parameters: names, which are not read, and default
  /// values, which are.
  String _parameters(List<Statement> parameters) {
    return parameters
        .map(
          (parameter) => switch (parameter) {
            KeywordArgumentExpression(:final key, :final val) =>
              '${_plain(key)}=${expression(val)}',
            SpreadExpression(argument: final spread) => '*${_plain(spread)}',
            Expression() => _plain(parameter),
            _ => throw UnsupportedError(
              'Unsupported parameter ${parameter.type}',
            ),
          },
        )
        .join(', ');
  }

  String _arguments(List<Statement> args) {
    return args
        .map(
          (argument) => switch (argument) {
            KeywordArgumentExpression(:final key, :final val) =>
              '${_plain(key)}=${expression(val)}',
            SpreadExpression(argument: final spread) =>
              '*${expression(spread)}',
            Expression() => expression(argument),
            _ => throw UnsupportedError(
              'Unsupported argument ${argument.type}',
            ),
          },
        )
        .join(', ');
  }

  /// A filter or test: its name, or a call on it, as the parser reads it
  /// after `|`, `is` or `filter`.
  String _callable(Expression node) => switch (node) {
    CallExpression(:final callee, :final args) =>
      '${_callable(callee)}(${_arguments(args)})',
    _ => _primary(node),
  };

  /// [node] as a primary expression: a bare name, or parenthesized.
  String _primary(Expression node) =>
      node is Identifier ? node.name : '(${_plain(node)})';

  String _calleeName(Expression node) => switch (node) {
    CallExpression(:final callee) => _calleeName(callee),
    Identifier(:final name) => name,
    _ => _plain(node),
  };

  /// [node] written without recording calls, for positions the template
  /// assigns to or names rather than reads.
  String _plain(Expression node) =>
      _Rewriter(instrument: false).expression(node);

  static String _number(String text, {required bool negative}) =>
      negative ? '($text)' : text;

  /// [value] as digits with a decimal point and no exponent, which dinja's
  /// lexer reads back as the same double. On the web, `toString` drops the
  /// point from whole numbers.
  static String _decimal(double value) {
    final sign = value.isNegative ? '-' : '';
    if (value.isInfinite) return '${sign}1${'0' * 400}.0';
    final text = value.abs().toString();
    final e = text.indexOf('e');
    final String digits;
    if (e < 0) {
      digits = text;
    } else {
      final mantissa = text.substring(0, e);
      final dot = mantissa.indexOf('.');
      final all = mantissa.replaceFirst('.', '');
      final point =
          (dot < 0 ? mantissa.length : dot) + int.parse(text.substring(e + 1));
      digits = point <= 0
          ? '0.${'0' * -point}$all'
          : point >= all.length
          ? '$all${'0' * (point - all.length)}'
          : '${all.substring(0, point)}.${all.substring(point)}';
    }
    return '$sign$digits${digits.contains('.') ? '' : '.0'}';
  }

  static String _call(String function, List<String> args) =>
      '$function(${args.join(', ')})';

  static String _literal(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return "'$escaped'";
  }
}
