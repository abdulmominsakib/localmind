import 'package:dinja/ast.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/core/template/jinja/jinja_analyzer.dart';
import 'package:llamadart/src/core/template/template_caps.dart';

/// Guards what `jinja_analyzer.dart` assumes of `package:dinja/ast.dart`:
/// `dinja public AST coupling` fails if `parseTemplate` stops parsing a
/// representative chat template into a non-empty `Program`, if walking it
/// stops producing the six node types that group lists, if
/// `BinaryExpression.op.value` stops giving the operator text `==`, or if
/// `-n`, `items[]` and `items.0` stop parsing to the node shapes it checks.
///
/// The capability goldens are descriptive of the analyzer's current output,
/// not a dinja guarantee - a deliberate analyzer change is expected to update
/// them, and that is not dinja drift.
void main() {
  const representativeTemplate = '''
{% for message in messages %}
{% if message.role == 'system' %}{{ message.content }}{% endif %}
{% if message.tool_calls %}
{% for tool_call in message.tool_calls %}{{ tool_call.function.name }}{% endfor %}
{% endif %}
{% if message.role == 'user' %}
{% for item in message.content %}{% if item.type == 'text' %}{{ item.text }}{% endif %}{% endfor %}
{% endif %}
{% endfor %}
{% for tool in tools %}{{ tool.function.name }}{% endfor %}
''';

  group('dinja public AST coupling', () {
    test('parseTemplate returns the Program the analyzer walks', () {
      final Program program = parseTemplate(representativeTemplate);
      expect(program.body, isNotEmpty);
    });

    test('AST node types the analyzer matches on are still produced', () {
      final program = parseTemplate(representativeTemplate);

      final seen = <Type>{};
      final operators = <String>{};
      void visit(Statement node) {
        seen.add(node.runtimeType);
        if (node is BinaryExpression) {
          operators.add(node.op.value);
        }
        if (node is Program) {
          node.body.forEach(visit);
        } else if (node is IfStatement) {
          visit(node.test);
          node.body.forEach(visit);
          node.alternate.forEach(visit);
        } else if (node is ForStatement) {
          visit(node.iterable);
          visit(node.loopVar);
          node.body.forEach(visit);
          node.defaultBlock.forEach(visit);
        } else if (node is BinaryExpression) {
          visit(node.left);
          visit(node.right);
        } else if (node is MemberExpression) {
          visit(node.object);
          visit(node.property);
        }
      }

      visit(program);

      expect(
        seen,
        containsAll(<Type>[
          IfStatement,
          ForStatement,
          BinaryExpression,
          MemberExpression,
          Identifier,
          StringLiteral,
        ]),
        reason: 'JinjaAnalyzer pattern-matches on each of these node types',
      );
      expect(
        operators,
        contains('=='),
        reason: 'JinjaAnalyzer reads BinaryExpression.op.value',
      );
    });

    test('unary minus, empty subscript and numeric member parse', () {
      final body = parseTemplate(
        '{{ -n }}{{ items[] }}{{ items.0 }}',
      ).body.cast<Expression>();

      expect(
        body[0],
        isA<UnaryExpression>()
            .having((e) => e.op.value, 'op', '-')
            .having((e) => e.argument, 'argument', isA<Identifier>()),
      );
      expect(
        body[1],
        isA<MemberExpression>()
            .having((e) => e.computed, 'computed', isTrue)
            .having((e) => e.property, 'property', isA<BlankExpression>()),
      );
      expect(
        body[2],
        isA<MemberExpression>()
            .having((e) => e.computed, 'computed', isFalse)
            .having((e) => e.property, 'property', isA<IntegerLiteral>()),
      );
    });
  });

  group('JinjaAnalyzer capability goldens', () {
    const cases = <String, String>{
      'full chat template': representativeTemplate,
      'string literal does not imply thinking support':
          '{{ "thinking about it" }}'
          '{% for m in messages %}{{ m.content }}{% endfor %}',
      'typed content parts':
          '{% for message in messages %}'
          "{% for part in message['content'] %}"
          "{% if part['type'] == 'image' %}Image{% endif %}"
          '{% endfor %}{% endfor %}',
      'bare tools guard': '{% if tools %}tools available{% endif %}',
    };

    const goldens = <String, Map<String, bool>>{
      'full chat template': <String, bool>{
        'supports_system_role': true,
        'supports_tool_calls': false,
        'supports_tools': false,
        'supports_parallel_tool_calls': false,
        'supports_string_content': false,
        'supports_typed_content': true,
        'supports_thinking': false,
        'supports_object_arguments': false,
      },
      'string literal does not imply thinking support': <String, bool>{
        'supports_system_role': true,
        'supports_tool_calls': false,
        'supports_tools': false,
        'supports_parallel_tool_calls': false,
        'supports_string_content': true,
        'supports_typed_content': false,
        'supports_thinking': false,
        'supports_object_arguments': false,
      },
      'typed content parts': <String, bool>{
        'supports_system_role': true,
        'supports_tool_calls': false,
        'supports_tools': false,
        'supports_parallel_tool_calls': false,
        'supports_string_content': false,
        'supports_typed_content': true,
        'supports_thinking': false,
        'supports_object_arguments': false,
      },
      'bare tools guard': <String, bool>{
        'supports_system_role': false,
        'supports_tool_calls': false,
        'supports_tools': false,
        'supports_parallel_tool_calls': false,
        'supports_string_content': true,
        'supports_typed_content': false,
        'supports_thinking': false,
        'supports_object_arguments': false,
      },
    };

    for (final entry in cases.entries) {
      test('${entry.key} keeps its capability map', () {
        final source = entry.value;
        expect(JinjaAnalyzer.analyze(source).toMap(), goldens[entry.key]);
        expect(
          TemplateCaps.detectRegex(source).toMap(),
          isNot(goldens[entry.key]),
          reason:
              'golden must be unreachable via the regex fallback, otherwise a '
              'broken dinja parse path would still pass',
        );
      });
    }

    test('a template using unary minus and str.format is probed', () {
      const source =
          '{%- set n = 1 -%}'
          '{%- for message in messages -%}'
          "{%- if message.role == 'system' and loop.index0 > -n -%}"
          "{{ '<{}>'.format(message.content) }}"
          '{%- endif -%}'
          '{%- for tool_call in message.tool_calls -%}'
          '{{ tool_call.function.name }}'
          '{%- endfor -%}'
          '{%- endfor -%}'
          '{%- for tool in tools -%}{{ tool.function.name }}{%- endfor -%}';

      final outcome = JinjaAnalyzer.analyzeWithOutcome(source);

      expect(outcome.failed, isFalse);
      expect(outcome.caps.toMap(), <String, bool>{
        'supports_system_role': true,
        'supports_tool_calls': true,
        'supports_tools': true,
        'supports_parallel_tool_calls': true,
        'supports_string_content': true,
        'supports_typed_content': false,
        'supports_thinking': false,
        'supports_object_arguments': false,
      });
    });

    test('invalid syntax still falls back to the regex result', () {
      const invalid =
          "{% if message.role == 'system' %}{{ message.content }} thinking";
      final regexCaps = TemplateCaps.detectRegex(invalid);

      expect(
        regexCaps.supportsThinking,
        isTrue,
        reason:
            'the raw marker must distinguish regex fallback from a silently '
            'accepted AST path',
      );
      expect(JinjaAnalyzer.analyze(invalid).toMap(), regexCaps.toMap());
    });
  });
}
