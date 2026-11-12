import 'dart:io';

import 'package:dinja/ast.dart';
import 'package:dinja/dinja.dart';
import 'package:llamadart/src/core/template/jinja/jinja_usage_probe.dart';
import 'package:test/test.dart';

JinjaUsageRun _render(String source, Map<String, JinjaValue> context) =>
    JinjaUsageProbe(parseTemplate(source)).render(context);

JinjaMap _message(Object? content) =>
    val(<String, Object?>{'role': 'user', 'content': content}) as JinjaMap;

JinjaValue _content(JinjaMap message) => message.items[val('content')]!;

/// [node] as nested lists of node types and values, without source positions
/// or parentheses. Comments and `generation` tags are dropped, and template
/// text compares equal to a string literal with the same value.
Object? _shape(Statement? node) {
  List<Object?> all(List<Statement> nodes) => [
    for (final node in nodes)
      if (node is! CommentStatement && node is! NoopStatement) _shape(node),
  ];
  return switch (node) {
    null => null,
    Program(:final body) => ['Program', all(body)],
    IfStatement(:final test, :final body, :final alternate) => [
      'If',
      _shape(test),
      all(body),
      all(alternate),
    ],
    ForStatement(
      :final loopVar,
      :final iterable,
      :final body,
      :final defaultBlock,
    ) =>
      ['For', _shape(loopVar), _shape(iterable), all(body), all(defaultBlock)],
    SetStatement(:final assignee, :final value, :final body) => [
      'Set',
      _shape(assignee),
      _shape(value),
      all(body),
    ],
    MacroStatement(:final name, :final args, :final body) => [
      'Macro',
      _shape(name),
      all(args),
      all(body),
    ],
    CallStatement(:final call, :final callerArgs, :final body) => [
      'CallBlock',
      _shape(call),
      all(callerArgs),
      all(body),
    ],
    FilterStatement(:final filter, :final body) => [
      'FilterBlock',
      _shape(filter),
      all(body),
    ],
    DoStatement(:final expr) => ['Do', _shape(expr)],
    BreakStatement() => ['Break'],
    ContinueStatement() => ['Continue'],
    Identifier(:final name) => ['Identifier', name],
    IntegerLiteral(:final value) => ['Integer', value],
    FloatLiteral(:final value) => ['Float', value.toString()],
    StringLiteral(:final value) => ['String', value],
    ArrayLiteral(:final items) => ['Array', all(items)],
    TupleLiteral(:final items) => ['Tuple', all(items)],
    ObjectLiteral(:final items) => [
      'Object',
      for (final entry in items) [_shape(entry.key), _shape(entry.value)],
    ],
    MemberExpression(:final object, :final property, :final computed) => [
      'Member',
      _shape(object),
      _shape(property),
      computed,
    ],
    CallExpression(:final callee, :final args) => [
      'Call',
      _shape(callee),
      all(args),
    ],
    BinaryExpression(:final op, :final left, :final right) => [
      'Binary',
      op.value,
      _shape(left),
      _shape(right),
    ],
    UnaryExpression(:final op, :final argument) => [
      'Unary',
      op.value,
      _shape(argument),
    ],
    FilterExpression(:final operand, :final filter) => [
      'Filter',
      _shape(operand),
      _shape(filter),
    ],
    TestExpression(:final operand, :final negate, :final test) => [
      'Test',
      _shape(operand),
      negate,
      _shape(test),
    ],
    SelectExpression(:final lhs, :final test) => [
      'Select',
      _shape(lhs),
      _shape(test),
    ],
    TernaryExpression(:final condition, :final trueExpr, :final falseExpr) => [
      'Ternary',
      _shape(condition),
      _shape(trueExpr),
      _shape(falseExpr),
    ],
    KeywordArgumentExpression(:final key, :final val) => [
      'Keyword',
      _shape(key),
      _shape(val),
    ],
    SpreadExpression(:final argument) => ['Spread', _shape(argument)],
    SliceExpression(:final start, :final stop, :final step) => [
      'Slice',
      _shape(start),
      _shape(stop),
      _shape(step),
    ],
    BlankExpression() => ['Blank'],
    _ => throw ArgumentError('Unknown node ${node.type}'),
  };
}

/// Writes [source] back through [JinjaUsageProbe.writeSource], checks that
/// it parses to the same shape, and that the probe can be built from it.
void _expectRoundTrip(String source) {
  final program = parseTemplate(source);
  final written = JinjaUsageProbe.writeSource(program);
  expect(
    _shape(parseTemplate(written)),
    _shape(program),
    reason: 'source: $source\nwritten: $written',
  );
  expect(() => JinjaUsageProbe(program), returnsNormally, reason: source);
}

const List<String> _literals = <String>[
  '0',
  '7',
  '-7',
  '+7',
  '9223372036854775807',
  '-9223372036854775808',
  '0.0',
  '-0.0',
  '1.5',
  '-1.5',
  '0.0000001',
  '0.00000012345',
  '-0.0000001',
  '100000000000000000000000.0',
  '123456789012345678901234567890.25',
  '0.1',
  '3.141592653589793',
  '0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000049',
  '179769313486231570000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0',
  "'plain'",
  "'it''s'",
  "'quote \\' and \\\\ backslash'",
  "'line\\nbreak\\ttab\\r'",
  "'braces }} %} {# #} {{ {%'",
  "'unicode 한글 👋'",
  '"double \\"quoted\\""',
  "''",
];

const List<String> _literalContexts = <String>[
  '{{ LIT }}',
  '{{ x - LIT }}',
  '{{ LIT - x }}',
  '{{ [LIT, LIT] }}',
  '{{ {LIT: LIT} }}',
  '{{ f(LIT, k=LIT) }}',
  '{{ x | f(LIT) }}',
  '{% if x is divisibleby(LIT) %}{% endif %}',
  '{% if x is sameas LIT %}{% endif %}',
  '{% set y = LIT %}',
  '{{ x[LIT] }}',
  '{{ x[LIT:LIT:LIT] }}',
  '{{ not LIT }}',
  '{{ LIT if x else LIT }}',
  '{% for i in range(LIT) %}{% endfor %}',
  '{% macro m(a=LIT) %}{% endmacro %}',
];

const List<String> _forms = <String>[
  '{% macro f() %}{% endmacro %}',
  '{% macro f(a) %}{{ a }}{% endmacro %}',
  '{% macro f(a, b=1) %}{% endmacro %}',
  '{% macro f(a, *args) %}{{ args }}{% endmacro %}',
  '{% macro f(*args) %}{% endmacro %}',
  '{% macro f(a, b=-1.5, *rest) %}{% endmacro %}',
  '{% call f(1, *z, k=2) %}x{% endcall %}',
  '{% call(x, *y) f() %}{{ x }}{% endcall %}',
  '{% call(a, b=2) f(1) %}{% endcall %}',
  '{{ f(*args) }}',
  '{{ f(a, *args, k=v) }}',
  '{% filter upper %}x{% endfilter %}',
  '{% filter replace("a", "b") %}x{% endfilter %}',
  '{{ x | f }}{{ x | f(1)(2) }}{{ x | (y) }}',
  '{{ x is defined }}{{ x is not none }}{{ x is f(1) }}{{ x is sameas y }}',
  '{{ x.y.z }}{{ x[0] }}{{ x.0 }}{{ x[y][z] }}{{ x.0.1 }}',
  '{{ x[:] }}{{ x[1:] }}{{ x[:2] }}{{ x[::3] }}{{ x[1:2:3] }}{{ x[] }}',
  '{{ (a, b) }}{% set a, b = 1, 2 %}{% for k, v in d.items() %}{% endfor %}',
  '{% set ns.x = 1 %}{% set y %}text{% endset %}',
  '{{ a and b or not c }}{{ a in b }}{{ a not in b }}{{ a ~ b }}',
  '{{ a // b }}{{ a % b }}{{ a ** b ** c }}{{ -a }}{{ - a }}{{ +a }}',
  '{{ ({"a": 1}) - 2 }}{{ [1] - 2 }}{{ (x) - 2 }}',
  '{{ a if b }}{{ a if b else c if d else e }}',
  '{{ a if b else (-7) }}{{ a if b else (-1.5) }}{{ a if b else (+7) }}',
  '{% for x in y if x %}{{ loop.index }}{% else %}none{% endfor %}',
  '{% for x in y %}{% if x %}{% break %}{% else %}{% continue %}{% endif %}'
      '{% endfor %}',
  '{% if a %}1{% elif b %}2{% elif c %}3{% else %}4{% endif %}',
  '{% do ns.update(x=1) %}{# comment #}{% generation %}g{% endgeneration %}',
  '  text {{- x -}}  more  {%- if y %} {% endif -%}\n',
  "{{ 'a' 'b' \"c\" }}{{ f()() }}{{ f().x() }}",
];

void main() {
  group('JinjaUsageProbe', () {
    test('renders the same text as the template', () {
      final message = _message('hi');
      final run = _render(
        "A{{ messages[0].content | upper }}{% if x is not defined %}-{% endif %}"
        "{% for i in range(2) %}{{ i }}{% endfor %}{{ 'q\\'s' }}{# c #}B",
        {
          'messages': JinjaList(<JinjaValue>[message]),
        },
      );

      expect(run.success, isTrue);
      expect(run.error, isNull);
      expect(run.output, "AHI-01q'sB");
    });

    test('records only the values the template reads', () {
      final read = _message('read');
      final unread = _message('unread');
      final run = _render('{{ messages[0].content }}', {
        'messages': JinjaList(<JinjaValue>[read, unread]),
      });

      expect(run.used(_content(read)), isTrue);
      expect(run.used(_content(unread)), isFalse);
      expect(run.ops(read), containsAll(<String>['object_access']));
    });

    test('records for loops and integer subscripts as array access', () {
      final looped = _message(<Object?>[]);
      final indexed = _message(<Object?>[
        <String, Object?>{'type': 'text', 'text': 'x'},
      ]);
      final run = _render(
        '{% for p in messages[0].content %}{% endfor %}'
        '{{ messages[1].content[0].text }}',
        {
          'messages': JinjaList(<JinjaValue>[looped, indexed]),
        },
      );

      expect(run.ops(_content(looped)), contains('array_access'));
      expect(run.ops(_content(indexed)), contains('array_access'));
    });

    test('throws on a for loop over a string, as llama.cpp does', () {
      final message = _message('text');
      final run = _render(
        '{% for p in messages[0].content %}{{ p }}{% endfor %}',
        {
          'messages': JinjaList(<JinjaValue>[message]),
        },
      );

      expect(run.success, isFalse);
      expect(run.output, isEmpty);
      expect(run.error.toString(), contains('got String'));
      expect(run.ops(_content(message)), contains('array_access'));
    });

    test('records filter names and tests', () {
      final message = _message('text');
      final run = _render(
        '{% if messages[0].content is string %}'
        '{{ messages[0].content | trim }}{% endif %}',
        {
          'messages': JinjaList(<JinjaValue>[message]),
        },
      );

      expect(
        run.ops(_content(message)),
        containsAll(<String>['test_is_string', 'trim']),
      );
    });

    test('marks every nested value used when tojson reads a value', () {
      final tools =
          val(<Object?>[
                <String, Object?>{
                  'function': <String, Object?>{'name': 'tool1'},
                },
              ])
              as JinjaList;
      final function =
          (tools.items.single as JinjaMap).items[val('function')] as JinjaMap;
      final run = _render('{{ tools | tojson }}', {'tools': tools});

      expect(run.used(function.items[val('name')]!), isTrue);
    });

    test('keeps what a throwing render read before it threw', () {
      final message = _message('text');
      final run = _render(
        "{{ messages[0].content }}{{ raise_exception('no') }}",
        {
          'messages': JinjaList(<JinjaValue>[message]),
        },
      );

      expect(run.success, isFalse);
      expect(run.error, isNotNull);
      expect(run.used(_content(message)), isTrue);
    });
  });

  group('JinjaUsageProbe.writeSource', () {
    test('round-trips every fixture template', () {
      final files = [
        for (final directory in ['test/fixtures', 'tool/litert_lm_templates'])
          ...Directory(directory)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.jinja')),
      ];
      expect(files, isNotEmpty);
      for (final file in files) {
        _expectRoundTrip(file.readAsStringSync());
      }
    }, testOn: 'vm');

    test('round-trips literals in every expression position', () {
      var parsed = 0;
      for (final context in _literalContexts) {
        for (final literal in _literals) {
          final source = context.replaceAll('LIT', literal);
          try {
            parseTemplate(source);
          } on Exception {
            // dinja lexes a sign after `else` or a test name as a binary
            // operator, so it rejects up to 7 combinations itself (6 on the
            // web, where int.parse accepts `9223372036854775808`).
            continue;
          }
          parsed++;
          _expectRoundTrip(source);
        }
      }
      expect(
        parsed,
        greaterThanOrEqualTo(_literalContexts.length * _literals.length - 7),
      );
    });

    test('round-trips signatures, calls, filters, tests and statements', () {
      _forms.forEach(_expectRoundTrip);
    });
  });
}
