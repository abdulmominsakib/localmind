import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_auto_grammar.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:test/test.dart';

import '../../../../support/gbnf_recognizer.dart';

void main() {
  test('foreign auto closers stay raw and cannot complete an executable call', () {
    final tools = [
      ToolDefinition(
        name: 'record',
        description: '',
        parameters: [ToolParam.string('value', required: true)],
      ),
      ToolDefinition(
        name: 'configure',
        description: '',
        parameters: [
          ToolParam.string('text', required: true),
          ToolParam.boolean('enabled', required: true),
        ],
      ),
    ];
    final grammar = GbnfRecognizer(
      buildLfm2AutoGrammar(tools, parallelToolCalls: false)!,
    );
    for (final call in [
      r'record(value=\\host)',
      'configure(text="ok", enabled=True)',
    ]) {
      for (final bracket in ['', ']']) {
        for (final tag in ['tool', 'function_call', 'x:result-2']) {
          final raw =
              '<|tool_call_start|>[$call$bracket</$tag>\n{"raw":true}<x><<';
          expect(grammar.accepts(raw), isTrue, reason: raw);
          final finalParse = Lfm2Handler().parseWithTools(raw, tools: tools);
          expect(finalParse.toolCalls, isEmpty, reason: raw);
          expect(finalParse.content, raw, reason: raw);
          for (var end = 0; end <= raw.length; end++) {
            expect(
              Lfm2Handler()
                  .parseWithTools(
                    raw.substring(0, end),
                    tools: tools,
                    isPartial: true,
                  )
                  .toolCalls,
              isEmpty,
              reason: raw.substring(0, end),
            );
          }
        }
      }
    }
    const start = '<|tool_call_start|>[';
    for (final raw in [
      '${start}record(value=ok)]',
      '${start}unknown(value=ok)</tool>',
      '${start}record(value=ok, value=wrong)</tool>',
      '${start}record(value=ok), record(value=wrong)</tool>',
      '${start}configure(text="ok", enabled="True")</tool>',
      '${start}configure(text=False, enabled=True)</tool>',
      '${start}configure(text="ok")</tool>',
      '${start}record(value=ok)</>',
      '${start}record(value=ok)</2tool>',
      '${start}record(value=ok)</tool><|tool_call_end|>',
      '${start}record(value=ok)</tool><<|tool_call_start|>',
      r'<|tool_call_start|>[record(value="ok)]<|tool_call_end|>x")]</tool>',
      r'<|tool_call_start|>[record(value="C:\temp\")]<|tool_call_end|>tail")]</tool>',
      r'<|tool_call_start|>[record(value="\<|tool_call_end|>")]</tool>',
      r'<|tool_call_start|>[record(arguments={"value":"<|tool_call_end|>"})]</tool>',
    ]) {
      expect(grammar.accepts(raw), isFalse, reason: raw);
    }
    // A partial special-marker prefix is diagnostic text, but cannot grow into
    // a canonical marker and resurrect its preceding call.
    const marker = '<|tool_call_end|>';
    for (var count = 1; count <= marker.length; count++) {
      final raw =
          '${start}record(value=ok)</tool>${marker.substring(0, count)}';
      expect(grammar.accepts(raw), count == 1, reason: raw);
    }
  });

  test('diagnostic envelopes cannot absorb a pending list continuation', () {
    final tools = [
      ToolDefinition(
        name: 'lookup',
        description: '',
        parameters: [ToolParam.string('place')],
      ),
    ];
    for (final parallel in [false, true]) {
      final grammar = GbnfRecognizer(
        buildLfm2AutoGrammar(tools, parallelToolCalls: parallel)!,
      );
      final calls = [
        'lookup(place="first")',
        if (parallel) 'lookup(place="first"), lookup(place="second")',
      ];
      for (final call in calls) {
        final start = '<|tool_call_start|>[$call';
        expect(grammar.accepts('$start]</result>'), isTrue);
        expect(grammar.accepts('$start,]<|tool_call_end|>'), isTrue);
        for (final whitespace in ['', ' \r\n  ']) {
          for (final bracket in ['', ']']) {
            expect(
              grammar.accepts(
                '$start,$whitespace$bracket</result>lookup(place="later")]',
              ),
              isFalse,
            );
          }
        }
      }
    }
  });

  test(
    'diagnostic marker exclusion blocks a lenient-parser execution prefix',
    () {
      final tools = [
        ToolDefinition(
          name: 'record',
          description: '',
          parameters: [ToolParam.string('value', required: true)],
        ),
      ];
      final grammar = GbnfRecognizer(
        buildLfm2AutoGrammar(tools, parallelToolCalls: false)!,
      );
      for (final raw in [
        r'<|tool_call_start|>[record(value="ok)]<|tool_call_end|>x")]</tool>',
        r'<|tool_call_start|>[record(value="C:\temp\")]<|tool_call_end|>tail")]</tool>',
      ]) {
        expect(
          Lfm2Handler().parseWithTools(raw, tools: tools).toolCalls,
          hasLength(1),
        );
        expect(grammar.accepts(raw), isFalse);
      }
    },
  );

  test('diagnostic terminals cannot hide markers in schema literals', () {
    const marker = '<|tool_call_end|>';
    for (final tool in [
      ToolDefinition(name: 'record$marker', description: '', parameters: []),
      ToolDefinition(
        name: 'record',
        description: '',
        parameters: [ToolParam.string('value$marker', required: true)],
      ),
      ToolDefinition(
        name: 'record',
        description: '',
        parameters: [
          ToolParam.enumType('value', values: [marker], required: true),
        ],
      ),
    ]) {
      final grammar = GbnfRecognizer(
        buildLfm2AutoGrammar([tool], parallelToolCalls: false)!,
      );
      final calls = [
        'record$marker()',
        'record(value$marker="ok")',
        'record(value="$marker")',
      ];
      for (final call in calls) {
        expect(grammar.accepts('<|tool_call_start|>[$call]</tool>'), isFalse);
      }
    }
  });

  test(
    'singleton strings preserve legacy quote spellings without rewriting',
    () {
      final tools = [
        ToolDefinition(
          name: 'record',
          description: '',
          parameters: [ToolParam.string('value', required: true)],
        ),
      ];
      final grammar = GbnfRecognizer(
        buildLfm2AutoGrammar(tools, parallelToolCalls: false)!,
      );
      final values = [
        r'''"{'path': 'D:\\work', 'message': "'q'r'}"''',
        r'''"{'path': 'D:\\work', 'message': "'q'r'"}"''',
        r"'alpha\\.example\\'.tail'",
      ];
      for (final value in values) {
        final raw =
            '<|tool_call_start|>[record(value=$value)]<|tool_call_end|>';
        expect(grammar.accepts(raw), isTrue, reason: raw);
        final parsed = Lfm2Handler().parseWithTools(raw, tools: tools);
        expect(parsed.toolCalls, hasLength(1), reason: raw);
        expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
          'value': value.substring(1, value.length - 1),
        }, reason: raw);
      }
      const ambiguous =
          '<|tool_call_start|>[record(value="{"count":13}")]<|tool_call_end|>';
      expect(grammar.accepts(ambiguous), isTrue);
      expect(
        Lfm2Handler().parseWithTools(ambiguous, tools: tools).toolCalls,
        isEmpty,
      );
    },
  );

  test('unclosed copied paths cannot absorb the completed call and prose', () {
    final tools = [
      ToolDefinition(
        name: 'record',
        description: '',
        parameters: [ToolParam.string('value', required: true)],
      ),
    ];
    final grammar = GbnfRecognizer(
      buildLfm2AutoGrammar(tools, parallelToolCalls: false)!,
    );
    for (final quote in ['"', "'"]) {
      for (final path in [r'prefix/\//-/suffix', r'D:\work\', r'\\server']) {
        final raw =
            '<|tool_call_start|>[record(value=$quote$path)]<|tool_call_end|>';
        expect(grammar.accepts(raw), isTrue, reason: raw);
        expect(grammar.accepts('$raw extra$quote)]<|tool_call_end|>'), isFalse);
        final legacy = Lfm2Handler().parse(raw);
        final candidate = Lfm2Handler().parseWithTools(raw, tools: tools);
        expect(candidate.toolCalls, hasLength(1));
        expect(
          candidate.toolCalls.single.function!.arguments,
          legacy.toolCalls.single.function!.arguments,
        );
      }
    }
  });

  test(
    'plain singleton strings retain copied wire spelling and value types',
    () {
      final tools = [
        ToolDefinition(
          name: 'record',
          description: '',
          parameters: [ToolParam.string('value', required: true)],
        ),
      ];
      final grammar = buildLfm2AutoGrammar(tools, parallelToolCalls: false)!;
      final recognizer = GbnfRecognizer(grammar);
      for (final value in [
        "{'count': 13, 'name': 'item'}",
        r'''{'path': 'D:\\work', 'message': "a\"b"}''',
        "['first', 'second', 'third']",
        "{'items': [1, None, True, {'name': 'item'}]}",
        r'a \ b',
        r'\\server',
        'False',
        '13',
        '서울',
      ]) {
        final raw =
            '<|tool_call_start|>[record(value=$value)]<|tool_call_end|>';
        expect(recognizer.accepts(raw), isTrue, reason: value);
        final parsed = Lfm2Handler().parseWithTools(raw, tools: tools);
        expect(parsed.toolCalls, hasLength(1), reason: value);
        expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
          'value': value,
        }, reason: value);
      }
      for (final payload in [
        'record(value={"x":1}, extra=True)',
        'record(value=first, value=second)',
        'record(value=[1),',
        'record(value={"x":1)',
        'unknown(value=first)',
        'record(value=first), record(value=second)',
      ]) {
        expect(
          recognizer.accepts('<|tool_call_start|>[$payload]<|tool_call_end|>'),
          isFalse,
          reason: payload,
        );
      }
    },
  );

  test('copied wire strings do not relax other declarations', () {
    for (final parameters in [
      [ToolParam.string('value')],
      [ToolParam.integer('value', required: true)],
      [
        ToolParam.string('value', required: true),
        ToolParam.boolean('enabled', required: true),
      ],
      [
        ToolParam.enumType('value', values: ['one'], required: true),
      ],
    ]) {
      final grammar = buildLfm2AutoGrammar([
        ToolDefinition(name: 'record', description: '', parameters: parameters),
      ], parallelToolCalls: false)!;
      final extra = parameters.length == 2 ? ', enabled=True' : '';
      for (final value in ["{'count':13}", '[1,2]', 'word']) {
        expect(
          GbnfRecognizer(grammar).accepts(
            '<|tool_call_start|>[record(value=$value$extra)]<|tool_call_end|>',
          ),
          isFalse,
          reason: '$parameters: $value',
        );
      }
    }
  });

  test('no declared tools adds no grammar', () {
    expect(buildLfm2AutoGrammar(null, parallelToolCalls: false), isNull);
    expect(buildLfm2AutoGrammar([], parallelToolCalls: true), isNull);
  });

  test('rejects an empty enum instead of emitting an accepting fallback', () {
    expect(
      () => buildLfm2AutoGrammar([
        ToolDefinition(
          name: 'choose',
          description: '',
          parameters: [
            ToolParam.enumType('choice', values: [], required: true),
          ],
        ),
      ], parallelToolCalls: false),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });

  test('rejects enum values whose copied tail escapes the closing quote', () {
    for (final tail in [1, 3, 5]) {
      expect(
        () => buildLfm2AutoGrammar([
          ToolDefinition(
            name: 'choose',
            description: '',
            parameters: [
              ToolParam.enumType(
                'choice',
                values: ['path${'\\' * tail}'],
                required: true,
              ),
              ToolParam.boolean('enabled', required: true),
            ],
          ),
        ], parallelToolCalls: false),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('odd number of backslashes'),
          ),
        ),
      );
    }
  });

  test('bounds unique-argument grammar expansion before generation', () {
    expect(
      () => buildLfm2AutoGrammar([
        ToolDefinition(
          name: 'many',
          description: '',
          parameters: [for (var i = 0; i < 13; i++) ToolParam.string('p$i')],
        ),
      ], parallelToolCalls: true),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
}
