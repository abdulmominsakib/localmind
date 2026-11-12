import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/decision/decision_sequence.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

const _cls = 1;
const _sep = 2;
const _mask = 3;
const _spec = DecisionSequenceSpec(
  clsToken: _cls,
  sepToken: _sep,
  maskToken: _mask,
  maskText: '<mask>',
);

const _headMax40 = DecisionSequenceSpec(
  clsToken: _cls,
  sepToken: _sep,
  maskToken: _mask,
  maskText: '<mask>',
  headMaxTokens: 40,
);

DecisionSequenceSpec _maxTokens(int maxTokens) => DecisionSequenceSpec(
  clsToken: _cls,
  sepToken: _sep,
  maskToken: _mask,
  maskText: '<mask>',
  maxTokens: maxTokens,
);

List<int> _run(int start, int length) => [
  for (var i = 0; i < length; i++) start + i,
];

void main() {
  group('renderDecisionOptions matches Laya render_options', () {
    test('choice', () {
      expect(
        renderDecisionOptions(
          DecisionQuestion.choice(
            'q',
            criteria: {
              'a': null,
              'b': '',
              'c': 'desc',
              'd': 0,
              'e': false,
              'f': {'max': 500, 'desc': '\u00e9'},
              'g': [1, 'x'],
              'h': 1.5,
            },
          ),
        ),
        [
          'a',
          'b',
          'c: desc',
          'd: 0',
          'e: false',
          'f: {"max": 500, "desc": "\u00e9"}',
          'g: [1, "x"]',
          'h: 1.5',
        ],
      );
    });

    test('score', () {
      expect(
        renderDecisionOptions(
          DecisionQuestion.score(
            'q',
            levels: [
              'none',
              0,
              {'k': 'v'},
              null,
              true,
            ],
          ),
        ),
        [
          'level 0: none',
          'level 1: 0',
          'level 2: {"k": "v"}',
          'level 3: null',
          'level 4: true',
        ],
      );
    });

    test('noul', () {
      expect(renderDecisionOptions(DecisionQuestion.noul('q')), [
        'false: no, the statement does not hold',
        'true: yes, the statement holds',
      ]);
      expect(
        renderDecisionOptions(
          DecisionQuestion.noul('q', whenTrue: '', whenFalse: 'nope'),
        ),
        ['false: nope', 'true: yes, the statement holds'],
      );
      expect(
        renderDecisionOptions(
          DecisionQuestion.noul('q', whenTrue: {'a': 1}, whenFalse: false),
        ),
        ['false: false', 'true: {"a": 1}'],
      );
    });
  });

  group('tokenizer texts', () {
    test('head is "<type> question: <instructions>" without mask text', () {
      expect(
        decisionHeadText(
          DecisionQuestion.choice('Is <mask> here?', criteria: {'a': null}),
          _spec,
        ),
        'choice question: Is   here?',
      );
      expect(
        decisionHeadText(DecisionQuestion.score('Rate', levels: [0]), _spec),
        'score question: Rate',
      );
      expect(
        decisionHeadText(DecisionQuestion.noul('<mask><mask>'), _spec),
        'noul question:   ',
      );
    });

    test('options get a leading space and lose mask text', () {
      expect(
        decisionOptionTexts(
          DecisionQuestion.choice(
            'q',
            criteria: {'a': null, 'b<mask>': 'x<mask>y'},
          ),
          _spec,
        ),
        [' a', ' b : x y'],
      );
    });

    test('state is text as is or json.dumps, without mask text', () {
      expect(decisionStateText('a<mask>b', _spec), 'a b');
      expect(decisionStateText('', _spec), '');
      expect(
        decisionStateText({'k': '<mask>', '\u00e9': 1.5, 'n': null}, _spec),
        '{"k": " ", "\u00e9": 1.5, "n": null}',
      );
      expect(decisionStateText(null, _spec), 'null');
      expect(decisionStateText(['x', 2], _spec), '["x", 2]');
    });
  });

  group('assembleDecisionSequence', () {
    test('lays out head, marked options and state', () {
      final sequence = assembleDecisionSequence(
        headTokens: [10, 11],
        optionTokens: [
          [20],
          [21, 22],
        ],
        stateTokens: [30, 31],
        spec: _spec,
      );

      expect(sequence.tokens, [
        _cls,
        10,
        11,
        _sep,
        _mask,
        20,
        _mask,
        21,
        22,
        _sep,
        30,
        31,
        _sep,
      ]);
      expect(sequence.markers, [4, 6]);
    });

    test('keeps 48 tokens of each option after its marker', () {
      final sequence = assembleDecisionSequence(
        headTokens: [10],
        optionTokens: [_run(100, 60)],
        stateTokens: [],
        spec: _spec,
      );

      expect(sequence.tokens, [
        _cls,
        10,
        _sep,
        _mask,
        ..._run(100, 48),
        _sep,
        _sep,
      ]);
    });

    test('leaves options whole when exactly 16 head tokens remain', () {
      final sequence = assembleDecisionSequence(
        headTokens: _run(500, 30),
        optionTokens: [
          _run(100, 48),
          _run(200, 48),
          _run(300, 48),
          _run(400, 28),
        ],
        stateTokens: [],
        spec: _spec,
      );

      expect(sequence.markers, [18, 67, 116, 165]);
      expect(sequence.tokens.sublist(1, 17), _run(500, 16));
      expect(sequence.tokens.sublist(18, 67), [_mask, ..._run(100, 48)]);
    });

    test('squeezes options when fewer than 16 head tokens remain', () {
      final sequence = assembleDecisionSequence(
        headTokens: _run(500, 30),
        optionTokens: [for (var i = 0; i < 4; i++) _run(100 * (i + 1), 44)],
        stateTokens: [],
        spec: _spec,
      );

      expect(sequence.markers, [18, 62, 106, 150]);
      expect(sequence.tokens.sublist(18, 62), [_mask, ..._run(100, 43)]);
      expect(sequence.tokens.sublist(150, 194), [_mask, ..._run(400, 43)]);
    });

    test('squeezes options when exactly 15 head tokens remain', () {
      final sequence = assembleDecisionSequence(
        headTokens: _run(500, 30),
        optionTokens: [
          _run(100, 48),
          _run(200, 48),
          _run(300, 48),
          _run(400, 29),
        ],
        stateTokens: [],
        spec: _spec,
      );

      expect(sequence.markers, [32, 76, 120, 164]);
      expect(sequence.tokens.sublist(32, 76), [_mask, ..._run(100, 43)]);
    });

    test('squeezes each option to (headMaxTokens - 16) ~/ K', () {
      final sequence = assembleDecisionSequence(
        headTokens: _run(500, 30),
        optionTokens: [for (var i = 0; i < 5; i++) _run(100 * (i + 1), 9)],
        stateTokens: [],
        spec: _headMax40,
      );

      expect(sequence.markers, [22, 26, 30, 34, 38]);
      expect(sequence.tokens.sublist(1, 21), _run(500, 20));
    });

    test('squeezes a single option to headMaxTokens - 16', () {
      final sequence = assembleDecisionSequence(
        headTokens: _run(500, 30),
        optionTokens: [_run(100, 48)],
        stateTokens: [],
        spec: _headMax40,
      );

      expect(sequence.markers, [18]);
      expect(sequence.tokens.sublist(18, 42), [_mask, ..._run(100, 23)]);
    });

    test('squeezes to at least 4 tokens and keeps at least 8 head tokens', () {
      final sequence = assembleDecisionSequence(
        headTokens: _run(500, 30),
        optionTokens: [for (var i = 0; i < 10; i++) _run(100 * (i + 1), 5)],
        stateTokens: [],
        spec: _headMax40,
      );

      expect(sequence.tokens.sublist(1, 9), _run(500, 8));
      expect(sequence.markers, [for (var i = 0; i < 10; i++) 10 + 4 * i]);
      expect(sequence.tokens.sublist(10, 14), [_mask, ..._run(100, 3)]);
    });

    test('cuts the head to the remaining budget', () {
      final sequence = assembleDecisionSequence(
        headTokens: _run(500, 250),
        optionTokens: [
          [20],
        ],
        stateTokens: [],
        spec: _spec,
      );

      expect(sequence.markers, [192]);
      expect(sequence.tokens.sublist(1, 191), _run(500, 190));
    });

    test('fills the rest with state and ends at maxTokens', () {
      final sequence = assembleDecisionSequence(
        headTokens: [10],
        optionTokens: [
          [20],
        ],
        stateTokens: _run(100, 100),
        spec: _maxTokens(20),
      );

      expect(sequence.tokens, [
        _cls,
        10,
        _sep,
        _mask,
        20,
        _sep,
        ..._run(100, 13),
        _sep,
      ]);
      expect(sequence.markers, [3]);
    });

    test('drops markers past maxTokens', () {
      final sequence = assembleDecisionSequence(
        headTokens: [10],
        optionTokens: [
          [20, 21],
          [22, 23],
          [24, 25],
        ],
        stateTokens: [30],
        spec: _maxTokens(8),
      );

      expect(sequence.tokens, [_cls, 10, _sep, _mask, 20, 21, _mask, 22]);
      expect(sequence.markers, [3, 6]);
    });

    test('drops a marker exactly at maxTokens', () {
      final sequence = assembleDecisionSequence(
        headTokens: [10],
        optionTokens: [
          [20, 21],
          [22],
          [24],
        ],
        stateTokens: [30],
        spec: _maxTokens(8),
      );

      expect(sequence.tokens, [_cls, 10, _sep, _mask, 20, 21, _mask, 22]);
      expect(sequence.markers, [3, 6]);
    });
  });

  group('buildDecisionSequences', () {
    late List<String> calls;

    Future<List<int>> tokenize(String text) async {
      calls.add(text);
      return [for (final unit in text.codeUnits) 1000 + unit];
    }

    setUp(() => calls = []);

    test('builds one sequence per question in question order', () async {
      final request = DecisionRequest(
        state: 'st',
        questions: {
          'second': DecisionQuestion.noul('B'),
          'first': DecisionQuestion.choice('A', criteria: {'x': null}),
        },
      );

      final sequences = await buildDecisionSequences(request, _spec, tokenize);

      expect(sequences, hasLength(2));
      expect(
        sequences[0].tokens,
        assembleDecisionSequence(
          headTokens: await tokenize('noul question: B'),
          optionTokens: [
            await tokenize(' false: no, the statement does not hold'),
            await tokenize(' true: yes, the statement holds'),
          ],
          stateTokens: await tokenize('st'),
          spec: _spec,
        ).tokens,
      );
      expect(sequences[1].tokens, [
        _cls,
        ...await tokenize('choice question: A'),
        _sep,
        _mask,
        ...await tokenize(' x'),
        _sep,
        ...await tokenize('st'),
        _sep,
      ]);
    });

    test('sends mask-free texts and an empty state', () async {
      final request = DecisionRequest(
        state: '',
        questions: {
          'q': DecisionQuestion.choice(
            'Has <mask>?',
            criteria: {'<mask>': null},
          ),
        },
      );

      final sequences = await buildDecisionSequences(request, _spec, tokenize);

      expect(calls.toSet(), {'', 'choice question: Has  ?', '  '});
      expect(
        sequences.single.tokens.sublist(sequences.single.tokens.length - 2),
        [_sep, _sep],
      );
    });

    test('rejects a question whose markers do not all fit', () async {
      final request = DecisionRequest(
        state: 'st',
        questions: {
          'fits': DecisionQuestion.choice('ok', criteria: {'y': null}),
          'many': DecisionQuestion.choice(
            'Pick',
            criteria: {for (var i = 0; i < 12; i++) 'option $i': null},
          ),
        },
      );

      await expectLater(
        buildDecisionSequences(request, _maxTokens(40), tokenize),
        throwsA(
          isA<LlamaDecisionException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('"many"'),
              contains('head_max_len=192'),
              contains('only 2 of 12'),
            ),
          ),
        ),
      );
    });

    test('rejects a question whose last marker lands on maxTokens', () async {
      final request = DecisionRequest(
        state: 's',
        questions: {
          'q': DecisionQuestion.choice(
            '',
            criteria: {'a': null, 'bb': null, 'c': null},
          ),
        },
      );

      await expectLater(
        buildDecisionSequences(request, _maxTokens(26), tokenize),
        throwsA(
          isA<LlamaDecisionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"q"'), contains('only 2 of 3')),
          ),
        ),
      );
    });
  });
}
