import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:test/test.dart';

import '../../../../support/gbnf_recognizer.dart';

void main() {
  group('schema-directed Python calls', () {
    ToolDefinition tool(List<ToolParam> parameters) => ToolDefinition(
      name: 'f',
      description: 'Test',
      parameters: parameters,
      handler: _noop,
    );
    Map<String, dynamic> parse(String payload, List<ToolParam> parameters) {
      final result = Lfm2Handler().parseWithTools(
        '<|tool_call_start|>[$payload]<|tool_call_end|>',
        tools: [tool(parameters)],
      );
      return jsonDecode(result.toolCalls.single.function!.arguments!)
          as Map<String, dynamic>;
    }

    test('types Python booleans using the declared parameter', () {
      expect(parse('f(x=True)', [ToolParam.boolean('x')]), {'x': true});
      expect(parse('f(x=False)', [ToolParam.string('x')]), {'x': 'False'});
    });
    test('keeps named object arguments without unwrapping aliases', () {
      expect(
        parse('f(arguments={"a":1})', [
          ToolParam.object('arguments', properties: [ToolParam.integer('a')]),
        ]),
        {
          'arguments': {'a': 1},
        },
      );
    });
    test(
      'preserves undeclared legacy argument wrappers against the schema',
      () {
        for (final wrapper in ['arguments', 'parameters', 'params', 'input']) {
          final raw =
              '<|tool_call_start|>[f($wrapper={"a":1})]<|tool_call_end|>';
          final baseline = Lfm2Handler().parse(raw);
          expect(jsonDecode(baseline.toolCalls.single.function!.arguments!), {
            'a': 1,
          });
          final candidate = Lfm2Handler().parseWithTools(
            raw,
            tools: [
              tool([ToolParam.integer('a', required: true)]),
            ],
          );
          expect(candidate.toolCalls, hasLength(1), reason: wrapper);
          expect(jsonDecode(candidate.toolCalls.single.function!.arguments!), {
            'a': 1,
          });
        }
      },
    );
    test('accepts a declared zero-argument call', () {
      expect(parse('f()', []), isEmpty);
    });
    for (final payload in ['f(a=1)', '[f(a=1,)]']) {
      test('preserves typed legacy call $payload', () {
        final raw = '<|tool_call_start|>$payload<|tool_call_end|>';
        final baseline = Lfm2Handler().parse(raw);
        expect(jsonDecode(baseline.toolCalls.single.function!.arguments!), {
          'a': 1,
        });
        final result = Lfm2Handler().parseWithTools(
          raw,
          tools: [
            tool([ToolParam.integer('a', required: true)]),
          ],
        );
        expect(result.toolCalls, hasLength(1), reason: payload);
        expect(jsonDecode(result.toolCalls.single.function!.arguments!), {
          'a': 1,
        });
      });
    }
    test(
      'preserves JSON-string wrappers without unwrapping declared aliases',
      () {
        for (final wrapper in ['arguments', 'parameters', 'params', 'input']) {
          final raw =
              '<|tool_call_start|>[f($wrapper=\'{"a":1}\')]<|tool_call_end|>';
          final legacy = Lfm2Handler().parse(raw);
          expect(jsonDecode(legacy.toolCalls.single.function!.arguments!), {
            'a': 1,
          });
          final result = Lfm2Handler().parseWithTools(
            raw,
            tools: [
              tool([ToolParam.integer('a', required: true)]),
            ],
          );
          expect(result.toolCalls, hasLength(1), reason: wrapper);
          expect(jsonDecode(result.toolCalls.single.function!.arguments!), {
            'a': 1,
          }, reason: wrapper);
          expect(
            parse('f($wrapper=\'{"a":1}\')', [ToolParam.string(wrapper)]),
            {wrapper: '{"a":1}'},
          );
        }
      },
    );
    test('rejects malformed typed calls and invalid JSON-string wrappers', () {
      for (final payload in [
        '[f(a=1,,)]',
        '[f(a=1,a=2,)]',
        '[f(a="1",)]',
        '[f(a=1)] trailing',
        '[f(a=1)',
        'f(a=1)]',
        'f(a=1',
        '[f(arguments=\'{"a":"1"}\')]',
        '[f(arguments=\'{"b":1}\')]',
        '[f(arguments=\'{"a":1\')]',
        '[f(arguments=\'[1]\')]',
      ]) {
        final result = Lfm2Handler().parseWithTools(
          '<|tool_call_start|>$payload<|tool_call_end|>',
          tools: [
            tool([ToolParam.integer('a', required: true)]),
          ],
        );
        expect(result.toolCalls, isEmpty, reason: payload);
      }
    });
    test('preserves copied string backslashes', () {
      expect(parse(r'f(x="C:\new\table.txt")', [ToolParam.string('x')]), {
        'x': r'C:\new\table.txt',
      });
    });
    test('preserves unquoted text and container-shaped string values', () {
      expect(parse('f(x=서울)', [ToolParam.string('x')]), {'x': '서울'});
      expect(parse("f(x={'a': 1})", [ToolParam.string('x')]), {
        'x': "{'a': 1}",
      });
    });
    test('uses nested property schemas for Python literals', () {
      expect(
        parse('f(config={"text":False,"enabled":True})', [
          ToolParam.object(
            'config',
            properties: [
              ToolParam.string('text'),
              ToolParam.boolean('enabled'),
            ],
          ),
        ]),
        {
          'config': {'text': 'False', 'enabled': true},
        },
      );
    });
    test('types nullable values, arrays and nested empty values', () {
      expect(
        parse(
          'f(values=[True,False],note=None,config={"name":"","items":[]})',
          [
            ToolParam.array('values', itemType: ToolParam.boolean('item')),
            ToolParam.nullType('note'),
            ToolParam.object(
              'config',
              properties: [
                ToolParam.string('name'),
                ToolParam.array('items', itemType: ToolParam.string('item')),
              ],
            ),
          ],
        ),
        {
          'values': [true, false],
          'note': null,
          'config': {'name': '', 'items': []},
        },
      );
    });
    test('does not coerce quoted booleans into non-string fields', () {
      final result = Lfm2Handler().parseWithTools(
        '<|tool_call_start|>[f(x="True")]<|tool_call_end|>',
        tools: [
          tool([ToolParam.boolean('x')]),
        ],
      );
      expect(result.toolCalls, isEmpty);
    });
    test('rejects unknown tools and missing required arguments', () {
      for (final payload in ['g(x=True)', 'f()']) {
        final result = Lfm2Handler().parseWithTools(
          '<|tool_call_start|>[$payload]<|tool_call_end|>',
          tools: [
            tool([ToolParam.boolean('x', required: true)]),
          ],
        );
        expect(result.toolCalls, isEmpty, reason: payload);
      }
    });
    test('tool choice none leaves typed-looking model text literal', () {
      const output = '<|tool_call_start|>[f(x=True)]<|tool_call_end|>';
      final result = Lfm2Handler().parseWithTools(
        output,
        tools: [
          tool([ToolParam.boolean('x')]),
        ],
        parseToolCalls: false,
      );
      expect(result.toolCalls, isEmpty);
      expect(result.content, output);
    });
    test('rejects duplicate argument names', () {
      final result = Lfm2Handler().parseWithTools(
        '<|tool_call_start|>[f(x=True,x=False)]<|tool_call_end|>',
        tools: [
          tool([ToolParam.boolean('x')]),
        ],
      );
      expect(result.toolCalls, isEmpty);
    });
  });

  test('reasoning is available to either LFM2 template field', () {
    final rendered = Lfm2Handler().render(
      templateSource:
          '{{ messages[0].thinking }}|{{ messages[0].reasoning_content }}',
      messages: const [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [LlamaThinkingContent('Why')],
        ),
      ],
      metadata: const {},
    );
    expect(rendered.prompt, 'Why|Why');
  });

  group('required tool choice grammar', () {
    LlamaChatTemplateResult render(
      List<ToolDefinition> tools, {
      bool parallel = false,
      String system = '',
      ToolChoice toolChoice = ToolChoice.required,
    }) => Lfm2Handler().render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: [
        if (system.isNotEmpty)
          LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
        const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
      ],
      metadata: {
        internalToolChoiceMetadataKey: toolChoice.name,
        internalParallelToolCallsMetadataKey: parallel.toString(),
      },
      tools: tools,
    );

    final search = ToolDefinition(
      name: 'search',
      description: 'Search',
      parameters: [ToolParam.string('query', required: true)],
      handler: _noop,
    );

    test('takes a second call only when the request allows it', () {
      final single = render([search]).grammar;
      expect(single, contains('root-item'));
      expect(render([search], parallel: true).grammar, isNot(single));
    });

    test('force-json-schema keeps the JSON list and its parallel flag', () {
      final single = render([search], system: 'Force JSON schema.\nSystem');
      expect(single.grammar, contains('root-item'));
      final parallel = render(
        [search],
        system: 'Force JSON schema.\nSystem',
        parallel: true,
      );
      expect(parallel.grammar, isNot(single.grammar));
    });

    test(
      'auto without the force-json marker uses a lazy Python-call grammar',
      () {
        final result = render([search], toolChoice: ToolChoice.auto);
        expect(result.grammar, contains('py-string'));
        expect(result.grammarLazy, isTrue);
        expect(result.grammarTriggers, hasLength(1));
        expect(result.grammarTriggers.single.type, 3);
      },
    );

    test('diagnostic roots belong only to Python auto tool choice', () {
      expect(
        render([search], toolChoice: ToolChoice.auto).grammar,
        contains('diagnostic-envelope'),
      );
      expect(render([search]).grammar, isNot(contains('diagnostic-envelope')));
      expect(
        render(
          [search],
          system: 'Force JSON schema.\nSystem',
          toolChoice: ToolChoice.auto,
        ).grammar,
        isNot(contains('diagnostic-envelope')),
      );
      expect(render([search], toolChoice: ToolChoice.none).grammar, isNull);
    });

    test('string arguments keep raw quotes no closing quote could precede', () {
      final grammar = GbnfRecognizer(render([search]).grammar!);
      String call(String query) =>
          '<|tool_call_start|>[{"name": "search", "arguments": '
          '{"query": "$query"}}]<|tool_call_end|>';
      for (final (raw, value) in [
        ('print(f"hi {name}")', 'print(f"hi {name}")'),
        ('{"a": 1, "b": "two"}', '{"a": 1, "b": "two"}'),
        ('She said "hi"', 'She said "hi"'),
        (r'C:\\Users\\me', r'C:\Users\me'),
        (r'say \"hi\"', 'say "hi"'),
      ]) {
        final output = call(raw);
        expect(grammar.accepts(output), isTrue, reason: output);
        for (final parsed in [
          Lfm2Handler().parse(output),
          Lfm2Handler().parseWithTools(output, tools: [search]),
        ]) {
          expect(parsed.content, isEmpty, reason: output);
          expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
            'query': value,
          }, reason: output);
        }
      }
      // A miscounted closer still ends the string, so the grammar corrects it.
      expect(grammar.accepts(call('a"}]] b')), isFalse);
      expect(grammar.accepts(call('a", "b')), isFalse);
    });

    test('an odd raw quote parses once the call is complete', () {
      const call =
          '<|tool_call_start|>[{"name": "search", "arguments": '
          '{"query": "it"s"}}]';
      const output = '$call<|tool_call_end|>';
      expect(GbnfRecognizer(render([search]).grammar!).accepts(output), isTrue);
      expect(Lfm2Handler().parse(call, isPartial: true).toolCalls, isEmpty);
      for (final partial in [true, false]) {
        expect(
          jsonDecode(
            Lfm2Handler()
                .parse(output, isPartial: partial)
                .toolCalls
                .single
                .function!
                .arguments!,
          ),
          {'query': 'it"s'},
        );
      }
    });

    test('an end marker inside a raw-quoted string is argument text', () {
      const call =
          '<|tool_call_start|>[{"name": "search", "arguments": '
          '{"query": "f("x)}}]<|tool_call_end|> it"s."}}]';
      const output = '$call<|tool_call_end|>';
      expect(GbnfRecognizer(render([search]).grammar!).accepts(output), isTrue);
      expect(Lfm2Handler().parse(call, isPartial: true).toolCalls, isEmpty);
      for (final parsed in [
        Lfm2Handler().parse(output),
        Lfm2Handler().parse(output, isPartial: true),
      ]) {
        expect(parsed.content, isEmpty);
        expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
          'query': 'f("x)}}]<|tool_call_end|> it"s.',
        });
      }
    });

    test('buildGrammar is the single-call list', () {
      expect(Lfm2Handler().buildGrammar([search]), render([search]).grammar);
    });
  });

  group('model output never throws out of parse', () {
    String nested(String open, String close, int depth) =>
        open * depth + close * depth;
    const isJavaScript = identical(0, 0.0);

    for (final (name, payload) in [
      ('an overflowing number', '[f(x=1e999)]'),
      ('an overflowing negative number', '[f(x=-1e999)]'),
      ('a JSON overflowing number', '[{"name":"f","arguments":{"x":1e999}}]'),
      (
        'JSON arguments nested past the wire limit',
        '[{"name":"f","arguments":{"x":${nested('[', ']', 200)}}}]',
      ),
    ]) {
      test('$name takes no call', () {
        final parsed = Lfm2Handler().parse(
          'Before<|tool_call_start|>$payload<|tool_call_end|>',
        );
        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, 'Before');
      });
    }

    for (final quote in ["'", '"']) {
      test('a lone $quote reads as text', () {
        final parsed = Lfm2Handler().parse(
          '<|tool_call_start|>[f(x=$quote)]<|tool_call_end|>',
        );
        expect(
          parsed.toolCalls.single.function?.arguments,
          jsonEncode({'x': quote}),
        );
      });
    }

    for (final depth in [20000, 200000]) {
      final list = nested('[', ']', depth);
      for (final (name, payload) in [
        ('arguments', '[{"name":"f","arguments":{"x":$list}}]'),
        ('arguments themselves', '[{"name":"f","arguments":$list}]'),
        ('a name', '[{"name":$list}]'),
        ('a function', '[{"function":$list}]'),
        ('a whole list', list),
        ('loose JSON', '[f({"x":$list})]'),
      ]) {
        test('$name nested $depth levels take no call', () {
          final parsed = Lfm2Handler().parse(
            'Before<|tool_call_start|>$payload<|tool_call_end|>',
          );
          expect(parsed.toolCalls, isEmpty);
          expect(parsed.content, 'Before');
        });
      }

      for (final (name, payload) in [
        ('an id', '[{"name":"f","id":$list,"arguments":{"a":1}}]'),
        (
          'a function id',
          '[{"function":{"name":"f","id":$list,"arguments":{"a":1}}}]',
        ),
        ('another field', '[{"name":"f","junk":$list,"arguments":{"a":1}}]'),
      ]) {
        test('$name nested $depth levels keeps the VM call', () {
          final calls = Lfm2Handler()
              .parse('<|tool_call_start|>$payload<|tool_call_end|>')
              .toolCalls;
          // Where dart2js overflows depends on the stack, so a call may survive.
          if (isJavaScript && calls.isEmpty) return;
          expect(calls.single.function?.arguments, '{"a":1}');
        });
      }
    }

    test('a deep id stringifies as toString would', () {
      for (final depth in [1000, if (!isJavaScript) 200000]) {
        final id = nested('[', ']', depth);
        final call = Lfm2Handler()
            .parse(
              '<|tool_call_start|>[{"name":"f","id":$id}]<|tool_call_end|>',
            )
            .toolCalls
            .single;
        expect(call.id, id);
      }
    });

    test('parses a deep map id with ordered siblings and mixed values', () {
      const depth = identical(0, 0.0) ? 1000 : 20000;
      final id =
          '${'{"before":[1,"[,{}]",null],"next":' * depth}7'
          '${',"after":{"z":true,"a":2}}' * depth}';
      final call = Lfm2Handler()
          .parse(
            '<|tool_call_start|>[{"name":"f","id":$id,"arguments":{"ok":true}}]'
            '<|tool_call_end|>',
          )
          .toolCalls
          .single;
      expect(
        call.id,
        '${'{before: [1, [,{}], null], next: ' * depth}7'
        '${', after: {z: true, a: 2}}' * depth}',
      );
      expect(call.function?.name, 'f');
      expect(call.function?.arguments, '{"ok":true}');
    });

    test('keeps a call whose ignored field nests deeply but decodes', () {
      final list = nested('[', ']', 1000);
      final call = Lfm2Handler()
          .parse(
            '<|tool_call_start|>[{"name":"f","junk":$list,"arguments":{"a":1}}]'
            '<|tool_call_end|>',
          )
          .toolCalls
          .single;
      expect(call.function?.arguments, '{"a":1}');
    });

    test('brackets in a string do not count as nesting', () {
      final text = '[' * 200000;
      final calls = Lfm2Handler()
          .parse(
            '<|tool_call_start|>[{"name":"f","arguments":{"x":"$text"}}]'
            '<|tool_call_end|>',
          )
          .toolCalls;
      expect(calls.single.function?.arguments, jsonEncode({'x': text}));
    });

    test('an overflow leaves the next parse working', () {
      final list = nested('[', ']', 200000);
      for (var run = 0; run < 20; run++) {
        Lfm2Handler().parse(
          '<|tool_call_start|>[{"name":"f","id":$list}]<|tool_call_end|>',
        );
        final call = Lfm2Handler()
            .parse(
              '<|tool_call_start|>[{"name":"f","id":[1],"arguments":{"a":1}}]'
              '<|tool_call_end|>',
            )
            .toolCalls
            .single;
        expect(call.id, '[1]');
        expect(call.function?.arguments, '{"a":1}');
      }
    });
  });

  // llama.cpp reads these differently, by schema. A parser that follows it
  // needs the tool schemas: https://github.com/leehack/llamadart/issues/1610
  group('reads a Python-style list as it always did', () {
    for (final (arguments, expected) in <(String, Object)>[
      ('x=True', {'x': 'True'}),
      ('x=None', {'x': 'None'}),
      ('x=False', {'x': 'False'}),
      ('x=false', {'x': false}),
      ('config={"a": 1}', {'a': 1}),
      ('arguments={"a": 1}', {'a': 1}),
      ("text={'a': 1}", {'text': "{'a': 1}"}),
      (r'''x="print('C:\\temp')"''', {'x': r"print('C:\\temp')"}),
      (r"x='it\'s ok'", {'x': r"it\'s ok"}),
      (r's="s/\//-/g"', {'s': r's/\//-/g'}),
      (r'x="caf\u00e9"', {'x': r'caf\u00e9'}),
    ]) {
      test(arguments, () {
        final parsed = Lfm2Handler().parse(
          '<|tool_call_start|>[f($arguments)]<|tool_call_end|>',
        );
        expect(
          jsonDecode(parsed.toolCalls.single.function!.arguments!),
          expected,
        );
      });
    }

    test('takes no call from name()', () {
      expect(
        Lfm2Handler()
            .parse('<|tool_call_start|>[f()]<|tool_call_end|>')
            .toolCalls,
        isEmpty,
      );
    });

    test('keeps a JSON id of infinity as text', () {
      expect(
        Lfm2Handler()
            .parse(
              '<|tool_call_start|>[{"name":"f","id":1e999}]<|tool_call_end|>',
            )
            .toolCalls
            .single
            .id,
        'Infinity',
      );
    });
  });

  test('Lfm2Handler matches llama.cpp force-json-schema semantics', () {
    final handler = Lfm2Handler();
    final tools = [
      ToolDefinition(
        name: 'search',
        description: 'Search',
        parameters: [ToolParam.string('query', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
    );

    expect(handler.format, isA<ChatFormat>());
    expect(rendered.grammar, contains('py-string'));
    expect(rendered.grammarLazy, isTrue);
    expect(rendered.grammarTriggers, hasLength(1));
    expect(rendered.preservedTokens, contains('<|tool_call_start|>'));
    expect(rendered.additionalStops, isEmpty);

    final renderedWithMarker = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: 'Force JSON schema.\nSystem prompt',
        ),
      ],
      metadata: const {},
      tools: tools,
    );
    expect(renderedWithMarker.prompt, equals('System prompt'));
    expect(renderedWithMarker.grammar, isNotNull);
    expect(renderedWithMarker.grammar, contains('"<|tool_call_start|>"'));
    expect(renderedWithMarker.grammarLazy, isTrue);
    expect(renderedWithMarker.grammarTriggers, hasLength(1));

    final renderedWithRequiredChoice = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: {internalToolChoiceMetadataKey: ToolChoice.required.name},
      tools: tools,
    );
    expect(renderedWithRequiredChoice.grammar, isNotNull);
    expect(
      renderedWithRequiredChoice.grammar,
      contains('"<|tool_call_start|>"'),
    );
    expect(
      renderedWithRequiredChoice.grammar,
      contains(
        'root-item ::= "{" space root-item-name-kv "," space '
        'root-item-arguments-kv "}" space',
      ),
    );
    expect(renderedWithRequiredChoice.grammarLazy, isFalse);
    expect(renderedWithRequiredChoice.grammarTriggers, hasLength(1));

    final modern = handler.parse(
      '<|tool_call_start|>[{"name":"search","arguments":{"query":"llama"}}]<|tool_call_end|>',
    );
    expect(modern.toolCalls, hasLength(1));
    expect(modern.toolCalls.first.function?.name, equals('search'));
    expect(
      jsonDecode(modern.toolCalls.first.function!.arguments!),
      containsPair('query', 'llama'),
    );

    final pythonStyle = handler.parse(
      '<|tool_call_start|>[search(query=\'llama, dart\', limit=2, exact=true)]<|tool_call_end|>',
    );
    expect(pythonStyle.toolCalls, hasLength(1));
    expect(pythonStyle.toolCalls.first.function?.name, equals('search'));
    expect(jsonDecode(pythonStyle.toolCalls.first.function!.arguments!), {
      'query': 'llama, dart',
      'limit': 2,
      'exact': true,
    });

    final parallelPythonStyle = handler.parse(
      '<|tool_call_start|>[search(query=\'llama\'), search(query=\'dart\')]<|tool_call_end|>',
    );
    expect(parallelPythonStyle.toolCalls, hasLength(2));
    expect(parallelPythonStyle.toolCalls[0].index, 0);
    expect(parallelPythonStyle.toolCalls[1].index, 1);
    expect(parallelPythonStyle.toolCalls[0].function?.name, equals('search'));
    expect(parallelPythonStyle.toolCalls[1].function?.name, equals('search'));

    final inThinking = handler.parse(
      '<think>reasoning <|tool_call_start|>[{"name":"search","arguments":{"query":"llama"}}]<|tool_call_end|></think>',
    );
    expect(inThinking.toolCalls, isEmpty);
    expect(
      inThinking.reasoningContent,
      'reasoning <|tool_call_start|>[{"name":"search",'
      '"arguments":{"query":"llama"}}]<|tool_call_end|>',
    );
    expect(inThinking.content, isEmpty);

    final thinkingOnly = handler.parse(
      '<think>plan first</think>final answer',
      parseToolCalls: false,
    );
    expect(thinkingOnly.reasoningContent, equals('plan first'));
    expect(thinkingOnly.content, equals('final answer'));

    final legacy = handler.parse("[search(query='llama')] and text");
    expect(legacy.toolCalls, isEmpty);
    expect(legacy.content, equals("[search(query='llama')] and text"));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
