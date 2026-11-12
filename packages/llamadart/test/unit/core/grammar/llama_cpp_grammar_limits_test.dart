import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:llamadart/src/core/grammar/llama_cpp_grammar_limits.dart';
import 'package:test/test.dart';

void main() {
  List<String> captureWarnings() {
    final logger = LlamaLogger.instance;
    final level = logger.level;
    final logs = <String>[];
    logger
      ..setLevel(LlamaLogLevel.warn)
      ..setHandler((record) => logs.add(record.message));
    addTearDown(() {
      logger
        ..setHandler(null)
        ..setLevel(level);
    });
    return logs;
  }

  Matcher rejects(String reason) => throwsA(
    isA<LlamaUnsupportedException>().having(
      (error) => error.message,
      'message',
      contains(reason),
    ),
  );

  group('checkTemplateGrammarLimits', () {
    // Each grammar was checked against the test-gbnf-validator of the shipped
    // runtime (upstream v0.7.0), built by
    // tool/testing/build_llama_cpp_runtime_gbnf_validator.sh.
    test('accepts grammars llama.cpp loads with every bound kept', () {
      for (final grammar in [
        'root ::= ("a" "b"{0,1999})?',
        'root ::= "a"{0,2000}',
        'root ::= "a"{2000}',
        'root ::= ("a" b){0,1000}\nb ::= "b"',
        'root ::= ( "a" b{0,998} ){2,}\nb ::= "b"',
        'root ::= x{40} "a"{60}\nx ::= "x"',
        'root ::= x{40} [a]{60}\nx ::= "x"',
        'root ::= ( "a"\r\n b{ 0 , 1998 } )?\r\nb ::= "b"',
        'root ::= ( "a" # comment ( unbalanced\n  b{ 2 , 3 } )\r\nb ::= [x] | "y"',
        'root ::= "(" ( "a" | "b" )+ ")" | "\\"" [^"\\\\]* "\\""',
        'root ::= "a"{40} .{60}',
        'root ::= ("a" root){0,1001}',
        'root ::= ("a"* "b"{0,1998})?',
        'root ::= ("a"* "b"{0,1998})*',
        'root ::= ("a"* "b"{0,1998}){0} "c"',
        'root ::= "a"{10}{10}{20}',
      ]) {
        expect(() => checkTemplateGrammarLimits(grammar), returnsNormally);
        expect(llamaCppRepetitionRejection(grammar), isNull, reason: grammar);
      }
    });

    test('rejects grammars over the repetition-symbol limit', () {
      for (final grammar in [
        'root ::= ("a" "b"{0,2000})?',
        'root ::= ("a" b){0,1001}\nb ::= "b"',
        'root ::= "a"{2001}',
        'root ::= ( "a" b{0,999} ){2,}\nb ::= "b"',
        'root ::= ( "a"\r\n b{ 0 , 1999 } )?\r\nb ::= "b"',
        'root ::= # comment\n("a" "b"{0,2000})?',
        'root ::= "a"{40}{60}',
        'root ::= ("a"* "b"{0,1999})?',
        'root ::= ("a"* "b"{0,1999})*',
        'root ::= ("a"* "b"{0,1999}){0} "c"',
        'root ::= "a"{10}{10}{21}',
        'root ::= ( ${[for (var i = 0; i < 2000; i++) 'r$i'].join(' | ')} )+',
      ]) {
        expect(
          llamaCppRepetitionRejection(grammar),
          isNotNull,
          reason: grammar,
        );
        expect(
          () => checkTemplateGrammarLimits(grammar),
          rejects('exceeds llama.cpp grammar limits (rule root repeats'),
        );
      }
    });

    test('accepts schema bounds of 2000 and rejects a minimum above it', () {
      for (final schema in [
        {'type': 'string', 'maxLength': 2000},
        {'type': 'string', 'minLength': 2000},
        {
          'type': 'array',
          'items': {'type': 'integer'},
          'maxItems': 2000,
        },
      ]) {
        final grammar = JsonSchemaConverter.convert(schema);
        expect(llamaCppRepetitionRejection(grammar), isNull, reason: '$schema');
      }
      expect(
        llamaCppRepetitionRejection(
          JsonSchemaConverter.convert({'type': 'string', 'minLength': 2001}),
        ),
        isNotNull,
      );
    });

    test('counts a token as one item, as parse_sequence does', () {
      // test-gbnf-validator has no vocabulary to resolve tokens, so these
      // follow llama_grammar_parser::parse_sequence directly.
      expect(
        llamaCppRepetitionRejection('root ::= ( !<x> b{0,1998} )?'),
        isNull,
      );
      expect(
        llamaCppRepetitionRejection('root ::= ( !<x> b{0,1999} )?'),
        isNotNull,
      );
      expect(
        llamaCppRepetitionRejection('root ::= <[42]>{2000} <x>{2000}'),
        isNull,
      );
    });

    test('warns about upper bounds llama.cpp drops', () {
      final logs = captureWarnings();
      for (final grammar in ['root ::= "a"{0,2001}', 'root ::= [a]{3,5000}']) {
        expect(llamaCppRepetitionRejection(grammar), isNull);
        expect(() => checkTemplateGrammarLimits(grammar), returnsNormally);
      }
      expect(logs, hasLength(2));
      expect(logs.first, contains('bounds a repetition in rule root at 2001'));
      expect(logs.last, contains('at 5000'));
      checkTemplateGrammarLimits('root ::= "a"{0,1999}');
      expect(logs, hasLength(2));
    });

    test('sets no length limit of its own', () {
      final grammar = 'root ::= "a"\n#${'x' * (12 * 1024 * 1024)}';
      expect(() => checkTemplateGrammarLimits(grammar), returnsNormally);
    });

    test('leaves syntax it does not model to llama.cpp', () {
      for (final grammar in [
        'root ::= "unterminated',
        'root = "a"',
        'root ::= "a"{x}',
      ]) {
        expect(llamaCppRepetitionRejection(grammar), isNull, reason: grammar);
        expect(() => checkTemplateGrammarLimits(grammar), returnsNormally);
      }
    });
  });
}
