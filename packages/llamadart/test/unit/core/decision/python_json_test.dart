import 'package:llamadart/src/core/decision/python_json.dart';
import 'package:test/test.dart';

// Expected strings are Python 3.12 json.dumps output for the same inputs.

final List<(String, Object?, String, String)> _portableCases = [
  ('null', null, 'null', 'null'),
  ('true', true, 'true', 'true'),
  ('false', false, 'false', 'false'),
  ('zero', 0, '0', '0'),
  ('positive int', 42, '42', '42'),
  ('negative int', -7, '-7', '-7'),
  ('max safe int', 9007199254740991, '9007199254740991', '9007199254740991'),
  ('min safe int', -9007199254740991, '-9007199254740991', '-9007199254740991'),
  ('empty string', '', '""', '""'),
  ('plain string', 'hello world', '"hello world"', '"hello world"'),
  (
    'quote and backslash',
    'say "hi" \\ back',
    '"say \\"hi\\" \\\\ back"',
    '"say \\"hi\\" \\\\ back"',
  ),
  ('slash', 'a/b', '"a/b"', '"a/b"'),
  (
    'short escapes',
    'tab\tnl\nret\rbs\u{8}ff\u{c}',
    '"tab\\tnl\\nret\\rbs\\bff\\f"',
    '"tab\\tnl\\nret\\rbs\\bff\\f"',
  ),
  (
    'control chars',
    '\u{0}\u{1}\u{1b}\u{1f}',
    '"\\u0000\\u0001\\u001b\\u001f"',
    '"\\u0000\\u0001\\u001b\\u001f"',
  ),
  ('space and tilde', ' ~', '" ~"', '" ~"'),
  ('delete', '\u{7f}', '"\u{7f}"', '"\\u007f"'),
  (
    'latin',
    'Gr\u{fc}\u{df}e \u{e9}',
    '"Gr\u{fc}\u{df}e \u{e9}"',
    '"Gr\\u00fc\\u00dfe \\u00e9"',
  ),
  ('cjk', '\u{4fa1}\u{683c}', '"\u{4fa1}\u{683c}"', '"\\u4fa1\\u683c"'),
  (
    'line separator',
    '\u{2028}\u{2029}',
    '"\u{2028}\u{2029}"',
    '"\\u2028\\u2029"',
  ),
  ('astral', '\u{1f621}', '"\u{1f621}"', '"\\ud83d\\ude21"'),
  ('lone surrogate', '\u{d800}x', '"\u{d800}x"', '"\\ud800x"'),
  (
    'mixed',
    'm\u{fc}ller "x"\n\u{1f621}\u{7f}',
    '"m\u{fc}ller \\"x\\"\\n\u{1f621}\u{7f}"',
    '"m\\u00fcller \\"x\\"\\n\\ud83d\\ude21\\u007f"',
  ),
  ('mask text', '[MASK] token', '"[MASK] token"', '"[MASK] token"'),
  ('empty list', <Object?>[], '[]', '[]'),
  ('nested empty list', <Object?>[<Object?>[]], '[[]]', '[[]]'),
  (
    'list',
    <Object?>[1, 'a', null, true, false],
    '[1, "a", null, true, false]',
    '[1, "a", null, true, false]',
  ),
  (
    'nested list',
    <Object?>[
      <Object?>[
        1,
        <Object?>[2],
      ],
      <Object?, Object?>{'k': <Object?>[]},
    ],
    '[[1, [2]], {"k": []}]',
    '[[1, [2]], {"k": []}]',
  ),
  (
    'non-ascii list',
    <Object?>[
      '\u{e9}',
      <Object?>['\u{4fa1}'],
    ],
    '["\u{e9}", ["\u{4fa1}"]]',
    '["\\u00e9", ["\\u4fa1"]]',
  ),
  ('empty map', <Object?, Object?>{}, '{}', '{}'),
  ('map', <Object?, Object?>{'a': 1}, '{"a": 1}', '{"a": 1}'),
  (
    'map keeps insertion order',
    <Object?, Object?>{
      'b': <Object?>[
        1,
        <Object?, Object?>{'c': null},
      ],
      'a': 'x',
    },
    '{"b": [1, {"c": null}], "a": "x"}',
    '{"b": [1, {"c": null}], "a": "x"}',
  ),
  (
    'non-ascii key',
    <Object?, Object?>{'\u{e9}': '\u{fc}'},
    '{"\u{e9}": "\u{fc}"}',
    '{"\\u00e9": "\\u00fc"}',
  ),
  ('empty key', <Object?, Object?>{'': ''}, '{"": ""}', '{"": ""}'),
  (
    'escaped key',
    <Object?, Object?>{'q"\n': 1},
    '{"q\\"\\n": 1}',
    '{"q\\"\\n": 1}',
  ),
  (
    'state',
    <Object?, Object?>{
      'from': 'user@acme.com',
      'items': <Object?>[1, 2, 3],
      'approved': false,
      'notes': null,
      'body': 'Gr\u{fc}\u{df}e \u{1f621} \u{2014} \u{4fa1}',
    },
    '{"from": "user@acme.com", "items": [1, 2, 3], "approved": false, "notes": null, "body": "Gr\u{fc}\u{df}e \u{1f621} \u{2014} \u{4fa1}"}',
    '{"from": "user@acme.com", "items": [1, 2, 3], "approved": false, "notes": null, "body": "Gr\\u00fc\\u00dfe \\ud83d\\ude21 \\u2014 \\u4fa1"}',
  ),
];

final List<(String, Object?, String)> _vmCases = [
  ('positive zero', 0.0, '0.0'),
  ('negative zero', -0.0, '-0.0'),
  ('one', 1.0, '1.0'),
  ('minus one', -1.0, '-1.0'),
  ('one and a half', 1.5, '1.5'),
  ('negative fraction', -2.5, '-2.5'),
  ('negative fraction below one', -0.5, '-0.5'),
  ('negative small fixed', -0.001, '-0.001'),
  ('tenth', 0.1, '0.1'),
  ('inexact sum', 0.30000000000000004, '0.30000000000000004'),
  ('third', 0.3333333333333333, '0.3333333333333333'),
  ('two thirds', 0.6666666666666666, '0.6666666666666666'),
  ('hundred', 100.0, '100.0'),
  ('fraction', 12345.678, '12345.678'),
  ('amount', 1250.5, '1250.5'),
  ('pi', 3.141592653589793, '3.141592653589793'),
  ('milli', 0.001, '0.001'),
  ('smallest fixed', 0.0001, '0.0001'),
  ('largest small sci', 9.99e-05, '9.99e-05'),
  ('ten micro', 1e-05, '1e-05'),
  ('small sci', 2.5e-05, '2.5e-05'),
  ('tiny sci', 1.5e-07, '1.5e-07'),
  ('very small', 1e-100, '1e-100'),
  ('denormal', 5e-324, '5e-324'),
  ('big fixed', 123456789012345.0, '123456789012345.0'),
  ('largest fixed power', 1000000000000000.0, '1000000000000000.0'),
  ('largest fixed', 9999999999999998.0, '9999999999999998.0'),
  ('rounded fixed', 9007199254740992.0, '9007199254740992.0'),
  ('smallest big sci', 1e+16, '1e+16'),
  ('big sci digits', 1.2345678901234568e+16, '1.2345678901234568e+16'),
  ('avogadro', 6.02214076e+23, '6.02214076e+23'),
  ('big power', 1e+22, '1e+22'),
  ('huge', 1e+100, '1e+100'),
  ('max double', 1.7976931348623157e+308, '1.7976931348623157e+308'),
  ('negative sci', -1.5e-07, '-1.5e-07'),
  ('negative big', -1e+16, '-1e+16'),
  ('nan', double.nan, 'NaN'),
  ('infinity', double.infinity, 'Infinity'),
  ('negative infinity', double.negativeInfinity, '-Infinity'),
  ('max int64', int.parse('9223372036854775807'), '9223372036854775807'),
  ('min int64', int.parse('-9223372036854775808'), '-9223372036854775808'),
  ('doubles in list', <Object?>[1.0, 2.5, -0.0], '[1.0, 2.5, -0.0]'),
  (
    'double in map',
    <Object?, Object?>{'x': 0.5, 'y': 1e-07},
    '{"x": 0.5, "y": 1e-07}',
  ),
];

void main() {
  group('pythonJsonDumps matches Python json.dumps', () {
    for (final (label, value, plain, ascii) in _portableCases) {
      test(label, () {
        expect(pythonJsonDumps(value), plain);
        expect(pythonJsonDumps(value, ensureAscii: true), ascii);
      });
    }
  });

  // Web numbers cannot tell 1.0 from 1 or hold the int64 range.
  group('pythonJsonDumps matches Python for VM numbers', () {
    for (final (label, value, expected) in _vmCases) {
      test(label, () {
        expect(pythonJsonDumps(value), expected);
        expect(pythonJsonDumps(value, ensureAscii: true), expected);
      });
    }
  }, testOn: 'vm');

  group('pythonJsonDumps rejects what Python cannot encode', () {
    test('values', () {
      for (final value in <Object?>[
        <int>{1},
        Object(),
        BigInt.one,
        <Object?>[DateTime(2026)],
        <String, Object?>{'nested': <Object?>{}},
      ]) {
        expect(
          () => pythonJsonDumps(value),
          throwsArgumentError,
          reason: '$value',
        );
      }
    });

    test('non-string map keys', () {
      for (final key in <Object?>[
        1,
        1.5,
        true,
        null,
        <int>[1],
      ]) {
        expect(
          () => pythonJsonDumps(<Object?, Object?>{key: 'value'}),
          throwsArgumentError,
          reason: '$key',
        );
      }
    });
  });
}
