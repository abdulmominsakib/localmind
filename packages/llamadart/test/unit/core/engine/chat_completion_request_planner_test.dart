import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/core/engine/chat_completion_request_planner.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/grammar/llama_cpp_grammar_limits.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/hermes_handler.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:test/test.dart';
import '../../../support/raw_tool_schema_fixture.dart';

void main() {
  test(
    'canonical schemas require active grammar and avoid native chat bypass',
    () {
      for (final choice in ToolChoice.values) {
        for (final backend in [
          _NoGrammarBackend(),
          _NoGrammarNativeChatBackend(),
        ]) {
          ChatCompletionRequestPlan plan() =>
              ChatCompletionRequestPlanner.build(
                backend: backend,
                templateResult: const LlamaChatTemplateResult(
                  prompt: 'p',
                  grammar: 'root ::= "ok"',
                ),
                messages: const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'hello',
                  ),
                ],
                toolChoice: choice,
                parallelToolCalls: false,
                tools: [rawSchemaTool()],
              );
          if (choice == ToolChoice.none) {
            expect(plan, returnsNormally);
          } else {
            expect(plan, throwsA(isA<LlamaUnsupportedException>()));
          }
        }
      }
      final plan = ChatCompletionRequestPlanner.build(
        backend: _NativeChatBackend(),
        templateResult: const LlamaChatTemplateResult(
          prompt: 'p',
          grammar: 'root ::= "ok"',
        ),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
        tools: [rawSchemaTool()],
      );
      expect(plan.usesNativeChatGeneration, isFalse);
      expect(plan.generationParams.grammar, isNotEmpty);
    },
  );
  group('ChatCompletionRequestPlanner', () {
    test('merges template grammar, stop sequences, and preserved tokens', () {
      final backend = _NativeChatBackend();
      final plan = ChatCompletionRequestPlanner.build(
        backend: backend,
        templateResult: const LlamaChatTemplateResult(
          prompt: 'prompt',
          grammar: 'template ::= "ok"',
          grammarLazy: true,
          additionalStops: ['</s>'],
          preservedTokens: ['<tool>'],
          grammarTriggers: [GrammarTrigger(type: 0, value: '<tool>')],
        ),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        params: const GenerationParams(
          stopSequences: ['STOP'],
          grammar: 'caller ::= "ignored"',
          preservedTokens: ['<caller>'],
        ),
        tools: [_weatherTool],
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
      );

      expect(plan.generationParams.stopSequences, ['</s>', 'STOP']);
      expect(plan.generationParams.grammar, 'template ::= "ok"');
      expect(plan.generationParams.grammarLazy, isTrue);
      final trigger = plan.generationParams.grammarTriggers.single;
      expect(trigger.value, '<tool>');
      expect(trigger.triggerType, GrammarTriggerType.word);
      expect(trigger.type, 0);
      expect(plan.generationParams.preservedTokens, ['<tool>', '<caller>']);
      expect(plan.nativeChatBackend, same(backend));
      expect(plan.parseToolCallsEnabled, isTrue);
      expect(plan.excludesPromptFromPenalties, isFalse);
    });

    test('maps each template grammar trigger to its typed trigger', () {
      final plan = ChatCompletionRequestPlanner.build(
        backend: _NativeChatBackend(),
        templateResult: const LlamaChatTemplateResult(
          prompt: 'prompt',
          grammar: 'template ::= "ok"',
          grammarLazy: true,
          grammarTriggers: [
            GrammarTrigger(type: 0, value: '<tool>'),
            GrammarTrigger(type: 1, value: '<t>', token: 9),
            GrammarTrigger(type: 2, value: r'\{"name"'),
            GrammarTrigger(type: 3, value: r'[\s\S]*<call>'),
          ],
        ),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        tools: [_weatherTool],
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
      );

      final triggers = plan.generationParams.grammarTriggers;
      expect(triggers.map((trigger) => trigger.triggerType), [
        GrammarTriggerType.word,
        GrammarTriggerType.token,
        GrammarTriggerType.pattern,
        GrammarTriggerType.patternFull,
      ]);
      expect(triggers.map((trigger) => trigger.value), [
        '<tool>',
        '<t>',
        r'\{"name"',
        r'[\s\S]*<call>',
      ]);
      expect(triggers[1].token, 9);
    });

    test('rejects a template grammar trigger of an unknown type', () {
      expect(
        () => ChatCompletionRequestPlanner.build(
          backend: _NativeChatBackend(),
          templateResult: const LlamaChatTemplateResult(
            prompt: 'prompt',
            grammar: 'template ::= "ok"',
            grammarLazy: true,
            grammarTriggers: [GrammarTrigger(type: 7, value: '<tool>')],
          ),
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
          ],
          tools: [_weatherTool],
          toolChoice: ToolChoice.auto,
          parallelToolCalls: false,
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('rejects strict response format when backend cannot use grammar', () {
      expect(
        () => ChatCompletionRequestPlanner.build(
          backend: _NoGrammarBackend(),
          templateResult: const LlamaChatTemplateResult(
            prompt: 'prompt',
            grammar: 'root ::= "ok"',
          ),
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
          ],
          toolChoice: ToolChoice.auto,
          parallelToolCalls: false,
          responseFormat: const {'type': 'json_object'},
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('rejects an unrecognised response format on every backend', () {
      for (final backend in [_BaseBackend(), _NoGrammarBackend()]) {
        expect(
          () => ChatCompletionRequestPlanner.build(
            backend: backend,
            templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
            messages: const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'hello',
              ),
            ],
            toolChoice: ToolChoice.auto,
            parallelToolCalls: false,
            responseFormat: const {'type': 'json_shema'},
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains("responseFormat.type 'json_shema'"),
            ),
          ),
        );
      }
    });

    group('template grammar limits', () {
      List<ToolDefinition> schemaTools(int count) => [
        for (var i = 0; i < count; i++)
          ToolDefinition.fromJsonSchema(
            name: 'tool_$i',
            description: 'Tool $i',
            schema: const {
              'type': 'object',
              'properties': {
                'a': {'type': 'string'},
              },
              'required': ['a'],
            },
          ),
      ];

      ChatCompletionRequestPlan plan(
        LlamaBackend backend,
        String? grammar, {
        List<ToolDefinition>? tools,
        GenerationParams? params,
        Map<String, dynamic>? responseFormat,
        bool lazy = false,
      }) => ChatCompletionRequestPlanner.build(
        backend: backend,
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.hermes.index,
          grammar: grammar,
          grammarLazy: lazy,
          grammarTriggers: [
            if (lazy) GrammarTrigger(type: 0, value: '<tool_call>'),
          ],
        ),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
        tools: tools,
        params: params,
        responseFormat: responseFormat,
      );

      // 1997 tools is the most the shipped llama.cpp runtime loads; the e2e
      // grammar validation suite checks both counts against it.
      test('keeps Hermes grammars llama.cpp loads', () {
        final tools = schemaTools(1997);
        final grammar = HermesHandler().buildGrammar(tools)!;
        expect(
          plan(_BaseBackend(), grammar, tools: tools).generationParams.grammar,
          grammar,
        );
      });

      test('rejects Hermes grammars over the llama.cpp repetition limit', () {
        final tools = schemaTools(1998);
        for (final lazy in [false, true]) {
          expect(
            () => plan(
              _BaseBackend(),
              HermesHandler().buildGrammar(tools)!,
              tools: tools,
              lazy: lazy,
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                contains('exceeds llama.cpp grammar limits (rule root repeats'),
              ),
            ),
            reason: 'lazy: $lazy',
          );
        }
      });

      test('applies bounds llama.cpp drops with a warning', () {
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
        const grammar = 'root ::= "\\"" char{0,3000} "\\""\nchar ::= [a-z]';
        expect(
          plan(
            _BaseBackend(),
            grammar,
            responseFormat: const {
              'type': 'json_schema',
              'json_schema': {
                'schema': {'type': 'string', 'maxLength': 3000},
              },
            },
          ).generationParams.grammar,
          grammar,
        );
        expect(logs.single, contains('llama.cpp ignores repetition upper'));
      });

      test('leaves grammars the plan does not apply unchecked', () {
        final grammar =
            'root ::= ( ${[for (var i = 0; i < 2000; i++) 'r$i'].join(' | ')} )+';
        expect(llamaCppRepetitionRejection(grammar), isNotNull);
        expect(
          plan(
            _NoGrammarBackend(),
            grammar,
            tools: [_weatherTool],
          ).generationParams.grammar,
          isNull,
        );
        expect(
          plan(
            _EagerGrammarBackend(),
            grammar,
            tools: [_weatherTool],
            lazy: true,
          ).generationParams.grammar,
          isNull,
        );
        const custom = 'root ::= "a"{0,3000}';
        expect(
          plan(
            _BaseBackend(),
            null,
            params: const GenerationParams(grammar: custom),
          ).generationParams.grammar,
          custom,
        );
      });
    });

    test('keeps text response format unconstrained without grammar', () {
      final plan = ChatCompletionRequestPlanner.build(
        backend: _NoGrammarBackend(),
        templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
        responseFormat: const {'type': 'text'},
      );

      expect(plan.generationParams.grammar, isNull);
    });

    test('rejects required Hermes tools on every no-grammar route', () {
      for (final backend in <LlamaBackend>[
        _NoGrammarBackend(),
        _NoGrammarNativeChatBackend(),
      ]) {
        expect(
          () => ChatCompletionRequestPlanner.build(
            backend: backend,
            templateResult: LlamaChatTemplateResult(
              prompt: 'qwen prompt',
              format: ChatFormat.hermes.index,
              grammar: 'root ::= tool_call',
            ),
            messages: const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'Call get_weather for Seoul.',
              ),
            ],
            tools: [_weatherTool],
            toolChoice: ToolChoice.required,
            parallelToolCalls: false,
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('ToolChoice.required'),
                contains('Hermes/Qwen'),
                contains('grammar-constrained decoding'),
                isNot(contains('LiteRT-LM')),
              ),
            ),
          ),
          reason: backend.runtimeType.toString(),
        );
      }
    });

    test('keeps Hermes auto and none usable on every no-grammar route', () {
      for (final route in <({LlamaBackend backend, bool usesNativeChat})>[
        (backend: _NoGrammarBackend(), usesNativeChat: false),
        (backend: _NoGrammarNativeChatBackend(), usesNativeChat: true),
      ]) {
        for (final toolChoice in [ToolChoice.auto, ToolChoice.none]) {
          final plan = ChatCompletionRequestPlanner.build(
            backend: route.backend,
            templateResult: LlamaChatTemplateResult(
              prompt: 'qwen prompt',
              format: ChatFormat.hermes.index,
              grammar: toolChoice == ToolChoice.auto
                  ? 'root ::= tool_call'
                  : null,
            ),
            messages: const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'Hello.',
              ),
            ],
            tools: [_weatherTool],
            toolChoice: toolChoice,
            parallelToolCalls: false,
          );

          final reason = '${route.backend.runtimeType}/${toolChoice.name}';
          expect(
            plan.usesNativeChatGeneration,
            route.usesNativeChat,
            reason: reason,
          );
          expect(plan.generationParams.grammar, isNull, reason: reason);
          expect(
            plan.parseToolCallsEnabled,
            toolChoice == ToolChoice.auto,
            reason: reason,
          );
        }
      }
    });

    test('preserves required Hermes grammar on capable backends', () {
      final plan = ChatCompletionRequestPlanner.build(
        backend: _NativeChatBackend(),
        templateResult: LlamaChatTemplateResult(
          prompt: 'qwen prompt',
          format: ChatFormat.hermes.index,
          grammar: 'root ::= tool_call',
        ),
        messages: const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Call get_weather for Seoul.',
          ),
        ],
        tools: [_weatherTool],
        toolChoice: ToolChoice.required,
        parallelToolCalls: false,
      );

      expect(plan.usesNativeChatGeneration, isFalse);
      expect(plan.generationParams.grammar, 'root ::= tool_call');
      expect(plan.parseToolCallsEnabled, isTrue);
    });

    group('on a backend without lazy grammar', () {
      final lazyHermesResult = LlamaChatTemplateResult(
        prompt: 'qwen prompt',
        format: ChatFormat.hermes.index,
        grammar: 'root ::= tool_call',
        grammarLazy: true,
        preservedTokens: ['<tool_call>'],
        grammarTriggers: [GrammarTrigger(type: 0, value: '<tool_call>')],
      );
      const messages = [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello.'),
      ];

      test(
        'LFM2 auto requires explicit lazy support instead of dropping its grammar',
        () {
          final result = withLfm2AutoGrammar(
            LlamaChatTemplateResult(
              prompt: 'lfm prompt',
              format: ChatFormat.lfm2.index,
              grammar: 'root ::= "call"',
              grammarLazy: true,
              grammarTriggers: [
                GrammarTrigger(type: 0, value: '<|tool_call_start|>'),
              ],
            ),
            enabled: true,
          );
          for (final backend in [
            _EagerGrammarBackend(),
            _NoGrammarBackend(),
            _BaseBackend(),
            _PromptPenaltyBackend(false),
          ]) {
            expect(
              () => ChatCompletionRequestPlanner.build(
                backend: backend,
                templateResult: result,
                messages: messages,
                tools: [_weatherTool],
                toolChoice: ToolChoice.auto,
                parallelToolCalls: false,
              ),
              throwsA(
                isA<LlamaUnsupportedException>().having(
                  (error) => error.message,
                  'missing capability',
                  allOf(
                    contains('schema-directed lazy grammar'),
                    contains('Web requires bridge assets v0.1.82+'),
                    contains('lazyGrammar and penaltyPromptTokensWithGrammar'),
                    isNot(contains('Published Web assets do not support')),
                  ),
                ),
              ),
            );
          }
          final plan = ChatCompletionRequestPlanner.build(
            backend: _PromptPenaltyBackend(true),
            templateResult: result,
            messages: messages,
            tools: [_weatherTool],
            toolChoice: ToolChoice.auto,
            parallelToolCalls: false,
          );
          expect(plan.generationParams.grammarLazy, isTrue);
          expect(plan.generationParams.grammarTriggers, isNotEmpty);
          expect(plan.excludesPromptFromPenalties, isFalse);
          expect(plan.includesPromptInPenalties, isTrue);
        },
      );

      test('skips a lazy template grammar for ToolChoice.auto', () {
        final plan = ChatCompletionRequestPlanner.build(
          backend: _EagerGrammarBackend(),
          templateResult: lazyHermesResult,
          messages: messages,
          params: const GenerationParams(preservedTokens: ['<caller>']),
          tools: [_weatherTool],
          toolChoice: ToolChoice.auto,
          parallelToolCalls: false,
        );

        expect(plan.generationParams.grammar, isNull);
        expect(plan.generationParams.grammarLazy, isFalse);
        expect(plan.generationParams.grammarTriggers, isEmpty);
        expect(plan.generationParams.preservedTokens, ['<caller>']);
        expect(plan.parseToolCallsEnabled, isTrue);
        expect(plan.excludesPromptFromPenalties, isTrue);
      });

      test('keeps a caller grammar, empty included, when it skips one', () {
        for (final grammar in <String?>[null, '', 'root ::= "ok"']) {
          final plan = ChatCompletionRequestPlanner.build(
            backend: _EagerGrammarBackend(),
            templateResult: lazyHermesResult,
            messages: messages,
            params: GenerationParams(grammar: grammar),
            tools: [_weatherTool],
            toolChoice: ToolChoice.auto,
            parallelToolCalls: false,
          );

          expect(plan.generationParams.grammar, grammar);
          expect(plan.excludesPromptFromPenalties, isTrue);
        }
      });

      test('marks no plan whose lazy grammar it did not skip', () {
        const noGrammar = LlamaChatTemplateResult(prompt: 'p');
        for (final (backend, templateResult, toolChoice) in [
          (_EagerGrammarBackend(), noGrammar, ToolChoice.auto),
          (_EagerGrammarBackend(), noGrammar, ToolChoice.none),
          (_NoGrammarBackend(), lazyHermesResult, ToolChoice.auto),
          (_BaseBackend(), lazyHermesResult, ToolChoice.auto),
        ]) {
          final plan = ChatCompletionRequestPlanner.build(
            backend: backend,
            templateResult: templateResult,
            messages: messages,
            params: const GenerationParams(grammar: ''),
            tools: [_weatherTool],
            toolChoice: toolChoice,
            parallelToolCalls: false,
          );

          expect(plan.excludesPromptFromPenalties, isFalse);
        }
      });

      test('keeps a strict template grammar', () {
        final plan = ChatCompletionRequestPlanner.build(
          backend: _EagerGrammarBackend(),
          templateResult: LlamaChatTemplateResult(
            prompt: 'qwen prompt',
            format: ChatFormat.hermes.index,
            grammar: 'root ::= tool_call',
          ),
          messages: messages,
          tools: [_weatherTool],
          toolChoice: ToolChoice.required,
          parallelToolCalls: false,
        );

        expect(plan.generationParams.grammar, 'root ::= tool_call');
        expect(plan.generationParams.grammarLazy, isFalse);
        expect(plan.excludesPromptFromPenalties, isFalse);
      });

      test('rejects ToolChoice.required with a lazy template grammar', () {
        expect(
          () => ChatCompletionRequestPlanner.build(
            backend: _EagerGrammarBackend(),
            templateResult: LlamaChatTemplateResult(
              prompt: 'apertus prompt',
              format: ChatFormat.apertus.index,
              grammar: 'root ::= tool_call',
              grammarLazy: true,
            ),
            messages: messages,
            tools: [_weatherTool],
            toolChoice: ToolChoice.required,
            parallelToolCalls: false,
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              allOf(contains('ToolChoice.required'), contains('apertus')),
            ),
          ),
        );
      });

      test('rejects strict responseFormat with a lazy template grammar', () {
        expect(
          () => ChatCompletionRequestPlanner.build(
            backend: _EagerGrammarBackend(),
            templateResult: lazyHermesResult,
            messages: messages,
            tools: [_weatherTool],
            toolChoice: ToolChoice.auto,
            parallelToolCalls: false,
            responseFormat: const {'type': 'json_object'},
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      });
    });

    test('preserves Gemma 4 required rendered-prompt compatibility', () {
      final plan = ChatCompletionRequestPlanner.build(
        backend: _NoGrammarNativeChatBackend(),
        templateResult: LlamaChatTemplateResult(
          prompt: 'gemma prompt',
          format: ChatFormat.gemma4.index,
          grammar: 'root ::= tool_call',
        ),
        messages: const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Call get_weather for Seoul.',
          ),
        ],
        tools: [_weatherTool],
        toolChoice: ToolChoice.required,
        parallelToolCalls: false,
      );

      expect(plan.usesNativeChatGeneration, isFalse);
      expect(plan.generationParams.grammar, isNull);
      expect(plan.parseToolCallsEnabled, isTrue);
    });

    test('resolves omitted thinking-budget tags from the chat template', () {
      final plan = ChatCompletionRequestPlanner.build(
        backend: _NativeChatBackend(),
        templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        params: const GenerationParams(
          thinkingBudget: ThinkingBudget(maxTokens: 64),
        ),
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
      );

      expect(plan.generationParams.thinkingBudget?.maxTokens, 64);
      expect(plan.generationParams.thinkingBudget?.startTag, '<think>');
      expect(plan.generationParams.thinkingBudget?.endTag, '</think>');
    });

    group('thinking-budget thought close', () {
      ThinkingBudget? resolvedBudget(
        ChatFormat format,
        ThinkingBudget budget, {
        LlamaBackend? backend,
      }) {
        final plan = ChatCompletionRequestPlanner.build(
          backend: backend ?? _PromptBackend(),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: format.index,
          ),
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
          ],
          params: GenerationParams(thinkingBudget: budget),
          toolChoice: ToolChoice.auto,
          parallelToolCalls: false,
        );
        return plan.generationParams.thinkingBudget;
      }

      test('Qwen3-Coder XML closes the thought on a new line', () {
        final budget = resolvedBudget(
          ChatFormat.qwen3CoderXml,
          const ThinkingBudget(maxTokens: 4),
        );
        expect(budget?.endTag, '</think>');
        expect(budget?.forcedMessage, '\n');
      });

      test('appends the line break to a caller forced message', () {
        final budget = resolvedBudget(
          ChatFormat.qwen3CoderXml,
          const ThinkingBudget(maxTokens: 4, forcedMessage: 'Done.'),
        );
        expect(budget?.forcedMessage, 'Done.\n');
      });

      test('keeps the forced message when the caller sets the end tag', () {
        final budget = resolvedBudget(
          ChatFormat.qwen3CoderXml,
          const ThinkingBudget(maxTokens: 4, endTag: '</think>'),
        );
        expect(budget?.forcedMessage, isNull);
      });

      test('leaves other formats without a forced message', () {
        final budget = resolvedBudget(
          ChatFormat.hermes,
          const ThinkingBudget(maxTokens: 4),
        );
        expect(budget?.endTag, '</think>');
        expect(budget?.forcedMessage, isNull);
      });

      test('sends no forced message to a native-chat backend', () {
        final budget = resolvedBudget(
          ChatFormat.qwen3CoderXml,
          const ThinkingBudget(maxTokens: 4),
          backend: _NativeChatBackend(),
        );
        expect(budget?.forcedMessage, isNull);
      });
    });

    test(
      'falls back to rendered prompt when native chat cannot satisfy policy',
      () {
        final plan = ChatCompletionRequestPlanner.build(
          backend: _NativeChatBackend(),
          templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
          ],
          tools: [_weatherTool],
          toolChoice: ToolChoice.required,
          parallelToolCalls: false,
        );

        expect(plan.usesNativeChatGeneration, isFalse);
        expect(plan.parseToolCallsEnabled, isTrue);
      },
    );
  });
}

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'get_weather',
  description: 'Returns current weather for a city.',
  parameters: [ToolParam.string('location', description: 'City name')],
  handler: (_) async => 'Sunny',
);

class _NoGrammarBackend extends _BaseBackend
    implements BackendGrammarConstraintsSupport {
  @override
  bool get supportsGrammarConstraints => false;
}

class _EagerGrammarBackend extends _BaseBackend
    implements BackendLazyGrammarSupport {
  @override
  bool get supportsLazyGrammar => false;
}

class _PromptBackend extends _BaseBackend
    implements BackendGrammarConstraintsSupport {
  @override
  bool get supportsGrammarConstraints => true;
}

class _NativeChatBackend extends _BaseBackend
    implements BackendGrammarConstraintsSupport, BackendNativeChatGeneration {
  @override
  bool get supportsGrammarConstraints => true;

  @override
  bool get supportsNativeChatGeneration => true;
}

class _NoGrammarNativeChatBackend extends _NoGrammarBackend
    implements BackendNativeChatGeneration {
  @override
  bool get supportsNativeChatGeneration => true;
}

class _BaseBackend implements LlamaBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PromptPenaltyBackend extends _BaseBackend
    implements BackendPromptPenaltyGeneration {
  _PromptPenaltyBackend(this.supportsPromptPenaltiesWithGrammar);
  @override
  final bool supportsPromptPenaltiesWithGrammar;
}
