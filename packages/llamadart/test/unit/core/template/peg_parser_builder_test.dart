import 'dart:convert';

import 'package:llamadart/src/core/template/peg_parser_builder.dart';
import 'package:test/test.dart';

void main() {
  group('PegParserBuilder', () {
    test('save resolves root refs to rule nodes', () {
      final builder = PegParserBuilder();
      final ruleRef = builder.rule('value rule', builder.literal('x'));
      builder.setRoot(ruleRef);

      final arena = _decodeArena(builder.save());
      final rootId = arena['root'] as int;
      final root = _node(arena, rootId);

      expect(root['type'], equals('rule'));
      expect(root['name'], equals('value-rule'));

      final child = _node(arena, root['child'] as int);
      expect(child['type'], equals('literal'));
      expect(child['literal'], equals('x'));
    });

    test('choice flattens nested choice nodes', () {
      final builder = PegParserBuilder();
      final a = builder.literal('a');
      final b = builder.literal('b');
      final c = builder.literal('c');
      final nestedChoice = builder.choice(<PegParser>[a, b]);
      final root = builder.choice(<PegParser>[nestedChoice, c]);
      builder.setRoot(root);

      final arena = _decodeArena(builder.save());
      final rootNode = _node(arena, arena['root'] as int);

      expect(rootNode['type'], equals('choice'));
      final children = (rootNode['children'] as List<dynamic>).cast<int>();
      expect(children.length, equals(3));

      final literals = children
          .map((id) => _node(arena, id))
          .where((node) => node['type'] == 'literal')
          .map((node) => node['literal'])
          .toList(growable: false);
      expect(literals, equals(<String>['a', 'b', 'c']));
    });

    test('sequence flattens nested sequence nodes', () {
      final builder = PegParserBuilder();
      final a = builder.literal('a');
      final b = builder.literal('b');
      final c = builder.literal('c');
      final nestedSequence = builder.sequence(<PegParser>[a, b]);
      final root = builder.sequence(<PegParser>[nestedSequence, c]);
      builder.setRoot(root);

      final arena = _decodeArena(builder.save());
      final rootNode = _node(arena, arena['root'] as int);

      expect(rootNode['type'], equals('sequence'));
      final children = (rootNode['children'] as List<dynamic>).cast<int>();
      expect(children.length, equals(3));
    });

    test('chars stores parsed ranges and negation metadata', () {
      final builder = PegParserBuilder();
      builder.setRoot(builder.chars(r'[^a-z\n]'));

      final arena = _decodeArena(builder.save());
      final node = _node(arena, arena['root'] as int);

      expect(node['type'], equals('chars'));
      expect(node['pattern'], equals(r'[^a-z\n]'));
      expect(node['negated'], isTrue);
      expect(node['min_count'], equals(1));
      expect(node['max_count'], equals(-1));

      final ranges = (node['ranges'] as List<dynamic>)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(growable: false);
      expect(ranges[0]['start'], equals(0x61));
      expect(ranges[0]['end'], equals(0x7A));
      expect(ranges[1]['start'], equals(0x0A));
      expect(ranges[1]['end'], equals(0x0A));
    });

    test('operator composition rejects unsupported operands', () {
      final builder = PegParserBuilder();
      final parser = builder.literal('a');
      expect(() => parser + 42, throwsArgumentError);
      expect(() => parser << 42, throwsArgumentError);
      expect(() => parser | 42, throwsArgumentError);
    });
  });

  group('ChatPeg builders', () {
    test('constructed builder emits expected tag nodes', () {
      final builder = ChatPegConstructedBuilder();
      final tagged = builder.toolArgJsonValue(builder.literal('{}'));
      builder.setRoot(tagged);

      final arena = _decodeArena(builder.save());
      final node = _node(arena, arena['root'] as int);

      expect(node['type'], equals('tag'));
      expect(
        node['tag'],
        equals(ChatPegConstructedBuilder.toolArgJsonValueTag),
      );
    });
  });
}

Map<String, dynamic> _decodeArena(String payload) {
  return (jsonDecode(payload) as Map).cast<String, dynamic>();
}

Map<String, dynamic> _node(Map<String, dynamic> arena, int id) {
  final parsers = (arena['parsers'] as List<dynamic>);
  return (parsers[id] as Map).cast<String, dynamic>();
}
