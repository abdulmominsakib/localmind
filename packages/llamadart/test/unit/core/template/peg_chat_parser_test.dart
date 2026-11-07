import 'dart:convert';

import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  group('PegChatParser runtime', () {
    test('parses peg-native output using serialized parser', () {
      final parser = _buildNativeParser();
      final output = 'plan|answer|tool(get_weather:{"city":"Seoul"})';

      final result = ChatTemplateEngine.parse(
        ChatFormat.pegNative.index,
        output,
        parser: parser,
      );

      expect(result.reasoningContent, equals('plan'));
      expect(result.content, equals('answer'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('get_weather'));
      expect(
        result.toolCalls.first.function?.arguments,
        equals('{"city":"Seoul"}'),
      );
    });

    test('parses peg-constructed output using serialized parser', () {
      final parser = _buildConstructedParser();
      const output =
          'hello|<function=get_weather><parameter=city>Seoul</parameter><parameter=days>3</parameter></function>';

      final result = ChatTemplateEngine.parse(
        ChatFormat.pegConstructed.index,
        output,
        parser: parser,
      );

      expect(result.content, equals('hello'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('get_weather'));

      final args = jsonDecode(result.toolCalls.first.function!.arguments!);
      expect(args, equals({'city': 'Seoul', 'days': 3}));
    });

    test('supports parseToolCalls=false for peg formats', () {
      final parser = _buildNativeParser();
      final output = 'plan|answer|tool(get_weather:{"city":"Seoul"})';

      final result = ChatTemplateEngine.parse(
        ChatFormat.pegNative.index,
        output,
        parser: parser,
        parseToolCalls: false,
      );

      expect(result.reasoningContent, equals('plan'));
      expect(result.content, equals('answer'));
      expect(result.toolCalls, isEmpty);
    });

    test('throws when parser is missing for PEG formats', () {
      expect(
        () =>
            ChatTemplateEngine.parse(ChatFormat.pegNative.index, 'raw-output'),
        throwsA(isA<StateError>()),
      );
    });

    test('rethrows parse failures for partial PEG parse', () {
      expect(
        () => ChatTemplateEngine.parse(
          ChatFormat.pegNative.index,
          'partial-output',
          isPartial: true,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

String _buildNativeParser() {
  final builder = _ParserBuilder();

  final reasoningUntil = builder.add({
    'type': 'until',
    'delimiters': ['|'],
  });
  final reasoningTag = builder.add({
    'type': 'tag',
    'child': reasoningUntil,
    'tag': 'reasoning',
  });
  final reasoningRule = builder.add({
    'type': 'rule',
    'name': 'reasoning-rule',
    'child': reasoningTag,
    'trigger': false,
  });

  final separator1 = builder.add({'type': 'literal', 'literal': '|'});

  final contentUntil = builder.add({
    'type': 'until',
    'delimiters': ['|'],
  });
  final contentTag = builder.add({
    'type': 'tag',
    'child': contentUntil,
    'tag': 'content',
  });

  final separator2 = builder.add({'type': 'literal', 'literal': '|'});

  final toolOpenLiteral = builder.add({'type': 'literal', 'literal': 'tool('});
  final toolOpenTag = builder.add({
    'type': 'tag',
    'child': toolOpenLiteral,
    'tag': 'tool-open',
  });

  final toolNameUntil = builder.add({
    'type': 'until',
    'delimiters': [':'],
  });
  final toolNameTag = builder.add({
    'type': 'tag',
    'child': toolNameUntil,
    'tag': 'tool-name',
  });

  final nameArgSeparator = builder.add({'type': 'literal', 'literal': ':'});

  final toolArgsUntil = builder.add({
    'type': 'until',
    'delimiters': [')'],
  });
  final toolArgsTag = builder.add({
    'type': 'tag',
    'child': toolArgsUntil,
    'tag': 'tool-args',
  });

  final toolCloseLiteral = builder.add({'type': 'literal', 'literal': ')'});
  final end = builder.add({'type': 'end'});

  final root = builder.add({
    'type': 'sequence',
    'children': [
      reasoningRule,
      separator1,
      contentTag,
      separator2,
      toolOpenTag,
      toolNameTag,
      nameArgSeparator,
      toolArgsTag,
      toolCloseLiteral,
      end,
    ],
  });

  return builder.serialize(
    root: root,
    rules: <String, int>{'reasoning-rule': reasoningRule},
  );
}

String _buildConstructedParser() {
  final builder = _ParserBuilder();

  final contentUntil = builder.add({
    'type': 'until',
    'delimiters': ['|'],
  });
  final contentTag = builder.add({
    'type': 'tag',
    'child': contentUntil,
    'tag': 'content',
  });
  final separator = builder.add({'type': 'literal', 'literal': '|'});

  final toolOpenLiteral = builder.add({
    'type': 'literal',
    'literal': '<function=',
  });
  final toolOpenTag = builder.add({
    'type': 'tag',
    'child': toolOpenLiteral,
    'tag': 'tool-open',
  });
  final toolOpenAtomic = builder.add({'type': 'atomic', 'child': toolOpenTag});

  final toolNameUntil = builder.add({
    'type': 'until',
    'delimiters': ['>'],
  });
  final toolNameTag = builder.add({
    'type': 'tag',
    'child': toolNameUntil,
    'tag': 'tool-name',
  });
  final toolNameClose = builder.add({'type': 'literal', 'literal': '>'});

  final arg1OpenLiteral = builder.add({
    'type': 'literal',
    'literal': '<parameter=',
  });
  final arg1OpenTag = builder.add({
    'type': 'tag',
    'child': arg1OpenLiteral,
    'tag': 'tool-arg-open',
  });
  final arg1NameUntil = builder.add({
    'type': 'until',
    'delimiters': ['>'],
  });
  final arg1NameTag = builder.add({
    'type': 'tag',
    'child': arg1NameUntil,
    'tag': 'tool-arg-name',
  });
  final arg1NameClose = builder.add({'type': 'literal', 'literal': '>'});
  final arg1ValueUntil = builder.add({
    'type': 'until',
    'delimiters': ['</parameter>'],
  });
  final arg1StringTag = builder.add({
    'type': 'tag',
    'child': arg1ValueUntil,
    'tag': 'tool-arg-string-value',
  });
  final arg1CloseLiteral = builder.add({
    'type': 'literal',
    'literal': '</parameter>',
  });
  final arg1CloseTag = builder.add({
    'type': 'tag',
    'child': arg1CloseLiteral,
    'tag': 'tool-arg-close',
  });

  final arg2OpenLiteral = builder.add({
    'type': 'literal',
    'literal': '<parameter=',
  });
  final arg2OpenTag = builder.add({
    'type': 'tag',
    'child': arg2OpenLiteral,
    'tag': 'tool-arg-open',
  });
  final arg2NameUntil = builder.add({
    'type': 'until',
    'delimiters': ['>'],
  });
  final arg2NameTag = builder.add({
    'type': 'tag',
    'child': arg2NameUntil,
    'tag': 'tool-arg-name',
  });
  final arg2NameClose = builder.add({'type': 'literal', 'literal': '>'});
  final arg2ValueDigits = builder.add({
    'type': 'chars',
    'pattern': '[0-9]',
    'ranges': [
      {'start': 48, 'end': 57},
    ],
    'negated': false,
    'min_count': 1,
    'max_count': -1,
  });
  final arg2JsonTag = builder.add({
    'type': 'tag',
    'child': arg2ValueDigits,
    'tag': 'tool-arg-json-value',
  });
  final arg2CloseLiteral = builder.add({
    'type': 'literal',
    'literal': '</parameter>',
  });
  final arg2CloseTag = builder.add({
    'type': 'tag',
    'child': arg2CloseLiteral,
    'tag': 'tool-arg-close',
  });

  final toolCloseLiteral = builder.add({
    'type': 'literal',
    'literal': '</function>',
  });
  final toolCloseTag = builder.add({
    'type': 'tag',
    'child': toolCloseLiteral,
    'tag': 'tool-close',
  });

  final end = builder.add({'type': 'end'});

  final root = builder.add({
    'type': 'sequence',
    'children': [
      contentTag,
      separator,
      toolOpenAtomic,
      toolNameTag,
      toolNameClose,
      arg1OpenTag,
      arg1NameTag,
      arg1NameClose,
      arg1StringTag,
      arg1CloseTag,
      arg2OpenTag,
      arg2NameTag,
      arg2NameClose,
      arg2JsonTag,
      arg2CloseTag,
      toolCloseTag,
      end,
    ],
  });

  return builder.serialize(root: root);
}

class _ParserBuilder {
  final List<Map<String, dynamic>> _parsers = <Map<String, dynamic>>[];

  int add(Map<String, dynamic> parser) {
    _parsers.add(parser);
    return _parsers.length - 1;
  }

  String serialize({required int root, Map<String, int> rules = const {}}) {
    return jsonEncode({'parsers': _parsers, 'rules': rules, 'root': root});
  }
}
