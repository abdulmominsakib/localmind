import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:llamadart/src/core/template/handlers/xml_argument_grammar.dart';
import 'package:test/test.dart';

void main() {
  group('permutedArguments', () {
    test('keeps one argument as is', () {
      final rules = <String>[];
      expect(permutedArguments(rules, 'p', ['a']), 'a');
      expect(rules, isEmpty);
    });

    test('takes up to six arguments in any order', () {
      final rules = <String>[];
      final root = permutedArguments(rules, 'p', ['a', 'b']);
      expect(root, 'p-3');
      expect(
        rules,
        unorderedEquals(['p-1 ::= a', 'p-2 ::= b', 'p-3 ::= a p-2 | b p-1']),
      );
    });

    test('keeps the declared order beyond six', () {
      final rules = <String>[];
      expect(
        permutedArguments(rules, 'p', ['a', 'b', 'c', 'd', 'e', 'f', 'g']),
        'a b c d e f g',
      );
      expect(rules, isEmpty);
    });
  });

  group('mayBeString', () {
    bool check(Map<String, dynamic> schema) => mayBeString(schema);

    test('follows the declared type', () {
      expect(check({'type': 'string'}), isTrue);
      expect(check({'type': 'integer'}), isFalse);
      expect(
        check({
          'type': ['integer', 'string'],
        }),
        isTrue,
      );
    });

    test('follows const and enum', () {
      expect(check({'const': 'a'}), isTrue);
      expect(check({'const': 1}), isFalse);
      expect(
        check({
          'enum': [1, 'a'],
        }),
        isTrue,
      );
      expect(
        check({
          'enum': [1, 2],
        }),
        isFalse,
      );
    });

    test('combines the alternatives of anyOf and allOf', () {
      expect(
        check({
          'anyOf': [
            {'type': 'integer'},
            {'type': 'string'},
          ],
        }),
        isTrue,
      );
      expect(
        check({
          'anyOf': [
            {'type': 'integer'},
            {'type': 'boolean'},
          ],
        }),
        isFalse,
      );
      expect(
        check({
          'allOf': [
            {'type': 'string'},
            {'type': 'integer'},
          ],
        }),
        isFalse,
      );
    });

    test('takes an untyped schema as possibly a string', () {
      expect(check({}), isTrue);
    });
  });

  group('ValueEndRules', () {
    test('ends a value where its JSON ends', () {
      final converter = JsonSchemaConverter();
      final rules = ValueEndRules(converter);
      final name = rules.visit({'type': 'integer'}, 'n');
      expect(name, endsWith('-at-value-end'));
      final sink = StringBuffer();
      rules.writeTo(sink);
      final text = sink.toString();
      final integer = RegExp(
        r'^integer-at-value-end ::= (.*)$',
        multiLine: true,
      ).firstMatch(text);
      expect(integer, isNotNull);
      expect(integer!.group(1), isNot(endsWith(' space')));
      expect(text, contains('integer ::= '));
    });

    test('names a copy apart from a rule a property already holds', () {
      final converter = JsonSchemaConverter();
      final rules = ValueEndRules(converter);
      rules.visit({
        'type': 'object',
        'properties': {
          'k': {'type': 'string'},
          'at-value-end': {
            'type': 'object',
            'properties': {
              'y': {'type': 'integer'},
            },
          },
        },
      }, 'schema');
      final sink = StringBuffer();
      rules.writeTo(sink);
      final names = [
        for (final line in sink.toString().split('\n'))
          if (line.contains(' ::= ')) line.split(' ::= ').first,
      ];
      expect(names.toSet(), hasLength(names.length));
    });
  });
}
