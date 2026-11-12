import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit/plugin.dart' as api;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';

const _supported = llama.LlamaEngineCapabilities(
  isSupported: true,
  runtime: llama.LlamaRuntime.llamaCpp,
  supportsGrammar: true,
  supportsStructuredOutput: true,
  supportsPresencePenalty: true,
  supportsPenalty: true,
  supportsMinP: true,
  supportsThinkingBudget: true,
  supportsStreamBatching: true,
  speculativeDecodingStrategies: {
    SpeculativeDecodingStrategy.backendDefault,
    SpeculativeDecodingStrategy.ngramSimple,
  },
);

void main() {
  late FakeRuntime runtime;
  late LlamaDartPlugin plugin;
  late genkit.Genkit ai;
  late int runtimeFactoryCalls;
  setUp(() {
    runtimeFactoryCalls = 0;
    runtime = FakeRuntime()
      ..capabilitySnapshot = _supported
      ..createChunks = [textChunk('ok')]
      ..templateResult = llama.LlamaChatTemplateResult(
        prompt: 'prompt',
        format: llama.ChatFormat.gemma4.index,
        grammar: 'root ::= "{}"',
        additionalStops: ['END'],
      )
      ..generatedTokens = ['{}'];
    plugin = LlamaDartPlugin(
      models: const [LlamaModelDefinition(name: 'local', modelPath: '/model')],
      runtimeFactory: () {
        runtimeFactoryCalls += 1;
        return runtime;
      },
    );
    ai = genkit.Genkit(plugins: [plugin], isDevEnv: false);
  });
  tearDown(() async {
    await plugin.dispose();
    await ai.shutdown();
  });

  Future<genkit.GenerateResult<dynamic>> generate(
    LlamaDartGenerationConfig config, {
    bool structured = false,
  }) => ai.generate(
    model: llamaDart.model('local'),
    prompt: 'Hi',
    config: config,
    outputFormat: structured ? 'json' : null,
    outputConstrained: structured ? true : null,
  );

  for (final structured in [false, true]) {
    test(
      'Genkit forwards inference controls with structured=$structured',
      () async {
        final response = await generate(
          LlamaDartGenerationConfig(
            presencePenalty: 2,
            thinkingBudget: const ThinkingBudget(maxTokens: 4),
            reusePromptPrefix: const bool.fromEnvironment('dart.library.io')
                ? false
                : null,
            streamBatchTokenThreshold: 1,
            streamBatchByteThreshold: 64,
            stop: ['STOP'],
            penalty: 1,
            temperature: 1,
            topP: 1,
            topK: 20,
            minP: 0,
          ),
          structured: structured,
        );
        expect(response.finishReason, genkit.FinishReason.stop);
        final params = runtime.lastGenerationParams!;
        expect(params.presencePenalty, 2);
        expect(params.penalty, 1);
        expect(params.temp, 1);
        expect(params.topP, 1);
        expect(params.topK, 20);
        expect(params.minP, 0);
        expect(params.thinkingBudget!.maxTokens, 4);
        expect(
          params.reusePromptPrefix,
          !const bool.fromEnvironment('dart.library.io'),
        );
        expect(params.streamBatchTokenThreshold, 1);
        expect(params.streamBatchByteThreshold, 64);
        expect(params.stopSequences, structured ? ['END', 'STOP'] : ['STOP']);
        if (structured) {
          final tags = llama.ChatTemplateEngine.thinkingTagsFor(
            llama.ChatFormat.gemma4.index,
          );
          expect(params.thinkingBudget!.startTag, tags.startTag);
          expect(params.thinkingBudget!.endTag, tags.endTag);
          expect(params.grammar, 'root ::= "{}"');
          expect(runtime.generateCallCount, 1);
          expect(runtime.createCallCount, 0);
        } else {
          expect(params.thinkingBudget!.startTag, isNull);
          expect(runtime.createCallCount, 1);
        }
      },
    );
    test(
      'omitted controls preserve defaults with structured=$structured',
      () async {
        await generate(
          const LlamaDartGenerationConfig(),
          structured: structured,
        );
        final params = runtime.lastGenerationParams!;
        expect(params.presencePenalty, 0);
        expect(params.thinkingBudget, isNull);
        expect(params.resolvedSpeculativeDecodingConfig, isNull);
        expect(params.reusePromptPrefix, true);
        expect(params.streamBatchTokenThreshold, 8);
        expect(params.streamBatchByteThreshold, 512);
      },
    );
  }

  test(
    'structured thinking retains explicit delimiters and forced message',
    () async {
      await generate(
        const LlamaDartGenerationConfig(
          thinkingBudget: ThinkingBudget(
            maxTokens: 8,
            startTag: '<custom>',
            endTag: '</custom>',
            forcedMessage: 'finish reasoning',
          ),
        ),
        structured: true,
      );
      final budget = runtime.lastGenerationParams!.thinkingBudget!;
      expect(budget.startTag, '<custom>');
      expect(budget.endTag, '</custom>');
      expect(budget.forcedMessage, 'finish reasoning');
    },
  );

  test(
    'typed speculation takes precedence over disabled default flag',
    () async {
      final response = await generate(
        const LlamaDartGenerationConfig(
          speculativeDecoding: false,
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(
            ngramSizeN: 3,
            ngramSizeM: 8,
            ngramMinHits: 2,
          ),
        ),
      );
      expect(response.finishReason, genkit.FinishReason.stop);
      final config =
          runtime.lastGenerationParams!.resolvedSpeculativeDecodingConfig!;
      expect(config.effectiveStrategies, [
        SpeculativeDecodingStrategy.ngramSimple,
      ]);
      expect(config.ngramSizeN, 3);
      expect(config.ngramSizeM, 8);
      expect(config.ngramMinHits, 2);
      await generate(
        const LlamaDartGenerationConfig(speculativeDecoding: true),
      );
      expect(
        runtime
            .lastGenerationParams!
            .resolvedSpeculativeDecodingConfig!
            .effectiveStrategies,
        [SpeculativeDecodingStrategy.backendDefault],
      );
    },
  );

  final advanced = [
    const LlamaDartGenerationConfig(presencePenalty: 2),
    const LlamaDartGenerationConfig(
      thinkingBudget: ThinkingBudget(maxTokens: 0),
    ),
    const LlamaDartGenerationConfig(streamBatchTokenThreshold: 1),
    const LlamaDartGenerationConfig(streamBatchByteThreshold: 1),
    const LlamaDartGenerationConfig(reusePromptPrefix: false),
    const LlamaDartGenerationConfig(speculativeDecoding: true),
    const LlamaDartGenerationConfig(
      speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(),
    ),
  ];
  test(
    'unsupported controls fail before either inference path starts',
    () async {
      runtime.capabilitySnapshot = const llama.LlamaEngineCapabilities(
        isSupported: true,
        supportsGrammar: true,
        supportsStructuredOutput: true,
      );
      for (final structured in [false, true]) {
        for (final config in advanced) {
          final response = await generate(config, structured: structured);
          expect(response.finishReason, genkit.FinishReason.failed);
          expect(
            response.cause,
            isA<genkit.GenkitException>().having(
              (e) => e.status,
              'status',
              genkit.StatusCode.unimplemented,
            ),
          );
        }
      }
      expect(
        runtime.createCallCount +
            runtime.generateCallCount +
            runtime.chatTemplateCallCount,
        0,
      );
      await generate(
        const LlamaDartGenerationConfig(
          presencePenalty: 0,
          speculativeDecoding: false,
          streamBatchTokenThreshold: 8,
          streamBatchByteThreshold: 512,
        ),
      );
      expect(runtime.createCallCount, 1);
    },
  );

  test(
    'incompatible speculation fails before template or generation',
    () async {
      for (final structured in [false, true]) {
        final response = await generate(
          LlamaDartGenerationConfig(
            speculativeDecoding: true,
            thinkingBudget: structured
                ? null
                : const ThinkingBudget(maxTokens: 1),
          ),
          structured: structured,
        );
        expect(response.finishReason, genkit.FinishReason.failed);
        expect(response.cause.toString(), contains('cannot be combined'));
      }
      expect(
        runtime.createCallCount +
            runtime.generateCallCount +
            runtime.chatTemplateCallCount,
        0,
      );
    },
  );

  test(
    'malformed controls fail safely before loading and valid requests recover',
    () async {
      final action = (await plugin.init())
          .whereType<api.Model<LlamaDartGenerationConfig>>()
          .single;
      for (final config in [
        {'presencePenalty': 'AUDIT_SECRET'},
        {
          'thinkingBudget': {'maxTokens': 1.5},
        },
        {
          'speculativeDecodingConfig': {
            'strategies': ['AUDIT_SECRET'],
          },
        },
      ]) {
        await expectLater(
          action(
            api.ModelRequest(
              messages: [
                api.Message(
                  role: api.Role.user,
                  content: [api.TextPart(text: 'Hi')],
                ),
              ],
              config: config,
            ),
          ),
          throwsA(
            isA<api.GenkitException>()
                .having(
                  (e) => e.status,
                  'status',
                  api.StatusCode.invalidArgument,
                )
                .having(
                  (e) => e.toString(),
                  'safe diagnostic',
                  isNot(contains('AUDIT_SECRET')),
                ),
          ),
        );
      }
      expect(runtimeFactoryCalls, 0);
      expect(runtime.initializeCount, 0);
      expect(runtime.capabilityReadCount, 0);
      expect(runtime.createCallCount + runtime.generateCallCount, 0);
      final response = await generate(const LlamaDartGenerationConfig());
      expect(response.finishReason, genkit.FinishReason.stop);
      expect(runtimeFactoryCalls, 1);
      expect(runtime.initializeCount, 1);
      expect(runtime.createCallCount, 1);
    },
  );

  test('media and active tools reject speculation before inference', () async {
    runtime.capabilitySnapshot = const llama.LlamaEngineCapabilities(
      isSupported: true,
      supportsVision: true,
      supportsToolCalling: true,
      supportsThinkingBudget: true,
      speculativeDecodingStrategies: {
        SpeculativeDecodingStrategy.backendDefault,
      },
    );
    final action = (await plugin.init())
        .whereType<api.Model<LlamaDartGenerationConfig>>()
        .single;
    final requests = [
      api.ModelRequest(
        messages: [
          api.Message(
            role: api.Role.user,
            content: [
              api.MediaPart(
                media: api.Media(
                  url: 'data:image/png;base64,AQ==',
                  contentType: 'image/png',
                ),
              ),
            ],
          ),
        ],
        config: const LlamaDartGenerationConfig(
          speculativeDecoding: true,
        ).toJson(),
      ),
      api.ModelRequest(
        messages: [
          api.Message(
            role: api.Role.user,
            content: [api.TextPart(text: 'Hi')],
          ),
        ],
        tools: [
          api.ToolDefinition(
            name: 'lookup',
            description: 'Lookup a value',
            inputSchema: {'type': 'object'},
          ),
        ],
        config: const LlamaDartGenerationConfig(
          speculativeDecoding: true,
        ).toJson(),
      ),
    ];
    for (final request in requests) {
      await expectLater(
        action(request),
        throwsA(
          isA<api.GenkitException>().having(
            (e) => e.status,
            'status',
            api.StatusCode.unimplemented,
          ),
        ),
      );
    }
    expect(
      runtime.createCallCount +
          runtime.generateCallCount +
          runtime.chatTemplateCallCount,
      0,
    );
  });

  test(
    'discovery is lazy and detailed metadata clears after a capability change',
    () async {
      final retained = (await plugin.list()).first.metadata;
      Map generation() =>
          (retained['llamadartCapabilities'] as Map)['generation'] as Map;
      expect(generation()['presencePenalty'], false);
      expect(runtime.initializeCount, 0);
      final schema = (retained['model'] as Map)['configSchema'] as Map;
      expect((retained['model'] as Map)['customOptions'], schema);
      final registered = (await ai.registry.listActions()).singleWhere(
        (a) => a.actionType == api.ActionType.model,
      );
      expect((registered.metadata['model'] as Map)['customOptions'], schema);
      expect(
        (schema['properties'] as Map).keys,
        containsAll([
          'presencePenalty',
          'thinkingBudget',
          'speculativeDecodingConfig',
          'reusePromptPrefix',
          'streamBatchTokenThreshold',
          'streamBatchByteThreshold',
        ]),
      );
      await generate(const LlamaDartGenerationConfig(presencePenalty: 2));
      expect(generation()['presencePenalty'], true);
      expect(generation()['penalty'], true);
      expect(generation()['minP'], true);
      expect(generation()['speculativeDecodingStrategies'], [
        'backendDefault',
        'ngramSimple',
      ]);
      runtime.capabilitySnapshot = const llama.LlamaEngineCapabilities(
        isSupported: true,
      );
      final response = await generate(
        const LlamaDartGenerationConfig(presencePenalty: 2),
      );
      expect(response.finishReason, genkit.FinishReason.failed);
      expect(generation()['presencePenalty'], false);
      expect(generation()['speculativeDecodingStrategies'], isEmpty);
      expect(generation()['penalty'], false);
      expect(generation()['minP'], false);
      expect(runtime.createCallCount, 1);
    },
  );
}
