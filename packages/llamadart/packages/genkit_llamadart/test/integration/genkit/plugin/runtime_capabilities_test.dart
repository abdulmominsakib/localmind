import 'dart:async';

import 'package:genkit/genkit.dart' show Genkit;
import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';

const _textOnly = llama.LlamaEngineCapabilities(isSupported: true);
const _nativeLiteRt = llama.LlamaEngineCapabilities(
  isSupported: true,
  runtime: llama.LlamaRuntime.liteRtLm,
  supportsMultiTurnChat: true,
  supportsToolCalling: true,
);

genkit.Message _message(genkit.Role role, [String text = 'Hello']) =>
    genkit.Message(
      role: role,
      content: [genkit.TextPart(text: text)],
    );

genkit.ModelRequest _request({
  List<genkit.Message>? messages,
  List<genkit.ToolDefinition>? tools,
  genkit.OutputConfig? output,
}) => genkit.ModelRequest(
  messages: messages ?? [_message(genkit.Role.user)],
  tools: tools,
  output: output,
);

final _tools = [
  genkit.ToolDefinition(
    name: 'lookup',
    description: 'Look up a value',
    inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
  ),
];

genkit.ModelRequest _media(String contentType) => _request(
  messages: [
    genkit.Message(
      role: genkit.Role.user,
      content: [
        genkit.MediaPart(
          media: genkit.Media(
            url: 'data:$contentType;base64,AA==',
            contentType: contentType,
          ),
        ),
      ],
    ),
  ],
);

genkit.EmbedRequest _embedRequest() => genkit.EmbedRequest(
  input: [
    genkit.DocumentData(content: [genkit.TextPart(text: 'Hello')]),
  ],
);

TypeMatcher<genkit.GenkitException> _status(genkit.StatusCode status) =>
    isA<genkit.GenkitException>().having(
      (error) => error.status,
      'status',
      status,
    );

Map<String, dynamic> _supports(Map<String, dynamic> metadata) =>
    (metadata['model'] as Map<String, dynamic>)['supports']
        as Map<String, dynamic>;

Map<String, dynamic> _state(Map<String, dynamic> metadata) =>
    metadata['llamadartCapabilities'] as Map<String, dynamic>;

void main() {
  late int factoryCalls;
  late FakeRuntime runtime;
  late LlamaDartPlugin plugin;
  late genkit.Model<LlamaDartGenerationConfig> model;
  late genkit.Embedder<LlamaDartEmbedConfig> embedder;

  setUp(() async {
    factoryCalls = 0;
    runtime = FakeRuntime()
      ..createChunks = [textChunk('ok')]
      ..embeddings = [
        [1, 2],
      ];
    plugin = LlamaDartPlugin(
      models: [
        LlamaModelDefinition(
          name: 'local',
          modelPath: '/not-loaded/model.gguf',
          modelInfo: genkit.ModelInfo(
            label: 'Custom',
            supports: {'media': true, 'tools': true, 'extra': true},
          ),
        ),
      ],
      runtimeFactory: () {
        factoryCalls++;
        return runtime;
      },
    );
    final actions = await plugin.init();
    model = actions.whereType<genkit.Model<LlamaDartGenerationConfig>>().single;
    embedder = actions
        .whereType<genkit.Embedder<LlamaDartEmbedConfig>>()
        .single;
  });
  tearDown(() => plugin.dispose());

  test(
    'discovery stays lazy and preserves declared permissions separately',
    () async {
      final listed = await plugin.list();
      expect(factoryCalls, 0);
      expect(runtime.initializeCount, 0);
      expect(runtime.capabilityReadCount, 0);
      for (final metadata in [
        model.metadata,
        embedder.metadata,
        ...listed
            .where((a) => a.actionType != LlamaDartPlugin.scoringActionType)
            .map((a) => a.metadata),
      ]) {
        expect(_state(metadata), {
          'state': 'unloaded',
          'ready': false,
          'embedding': {'text': false, 'image': false, 'audio': false},
          'generation': {
            'penalty': false,
            'minP': false,
            'presencePenalty': false,
            'thinkingBudget': false,
            'streamBatching': false,
            'promptPrefixControl': false,
            'speculativeDecodingStrategies': <String>[],
          },
          'declared': {'tools': true, 'constrained': true, 'embeddings': true},
        });
        final supports = _supports(metadata);
        expect(supports['extra'], true);
        for (final key in [
          'tools',
          'media',
          'multiturn',
          'systemRole',
          'constrained',
          'embeddings',
        ]) {
          expect(supports[key], false, reason: key);
        }
      }
    },
  );

  test(
    'capability refresh preserves framework and app model annotations',
    () async {
      final listed = await plugin.list();
      final views = [model.metadata, embedder.metadata, listed.first.metadata];
      for (final metadata in views) {
        final modelInfo = metadata['model'] as Map<String, dynamic>;
        modelInfo['customOptions'] = {'type': 'object', 'title': 'App config'};
        modelInfo['appAnnotation'] = 'keep';
        (modelInfo['supports'] as Map<String, dynamic>)['appCapability'] = true;
      }
      await model(_request());
      runtime.capabilitySnapshot = _textOnly;
      await model(_request());
      for (final metadata in views) {
        final modelInfo = metadata['model'] as Map<String, dynamic>;
        expect(modelInfo['label'], 'Custom');
        expect(modelInfo['customOptions'], {
          'type': 'object',
          'title': 'App config',
        });
        expect(modelInfo['appAnnotation'], 'keep');
        expect(_supports(metadata)['appCapability'], true);
        expect(_supports(metadata)['tools'], false);
      }
    },
  );

  for (final vision in [false, true]) {
    test(
      'image/audio capabilities are independent with vision=$vision',
      () async {
        runtime.capabilitySnapshot = llama.LlamaEngineCapabilities(
          isSupported: true,
          supportsVision: vision,
          supportsAudio: !vision,
        );
        final supported = vision ? 'image/png' : 'audio/wav';
        final unsupported = vision ? 'audio/wav' : 'image/png';
        await model(_media(supported));
        await expectLater(
          model(_media(unsupported)),
          throwsA(_status(genkit.StatusCode.unimplemented)),
        );
        expect(runtime.createCallCount, 1);
        expect(_supports(model.metadata)['media'], true);
      },
    );
  }

  for (final loadViaEmbedder in [false, true]) {
    test(
      'loading through embedder=$loadViaEmbedder updates every metadata view',
      () async {
        if (loadViaEmbedder) {
          await embedder(_embedRequest());
        } else {
          await model(_request());
        }
        expect(runtime.initializeCount, 1);
        expect(runtime.capabilityReadCount, 1);
        for (final (metadata, mediaSupported) in [
          (model.metadata, true),
          (embedder.metadata, false),
          ...(await plugin.list())
              .where((a) => a.actionType != LlamaDartPlugin.scoringActionType)
              .map(
                (a) => (a.metadata, a.actionType == genkit.ActionType.model),
              ),
        ]) {
          expect(_state(metadata)['state'], 'verified');
          expect(_state(metadata)['ready'], true);
          expect(_supports(metadata)['tools'], true);
          expect(_supports(metadata)['media'], mediaSupported);
          expect(_supports(metadata)['embeddings'], true);
          expect(_supports(metadata)['constrainedWithTools'], false);
        }
        await plugin.dispose();
        expect(_supports(model.metadata)['tools'], false);
        expect(_state(model.metadata)['ready'], false);
      },
    );
  }

  test(
    'Genkit registry and retained listing expose refreshed metadata',
    () async {
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(ai.shutdown);
      final retained = await plugin.list();
      final registered = await ai.registry.listActions();
      final registeredModel = registered.singleWhere(
        (a) =>
            a.name == 'llamadart/local' &&
            a.actionType == genkit.ActionType.model,
      );
      expect(_supports(registeredModel.metadata)['tools'], false);
      final response = await ai.generate(
        model: llamaDart.model('local'),
        prompt: 'Hi',
      );
      expect(response.text, 'ok');
      expect(_supports(registeredModel.metadata)['tools'], true);
      expect(_supports(retained.first.metadata)['tools'], true);
      runtime.capabilitySnapshot = _textOnly;
      await model(_request());
      expect(_supports(registeredModel.metadata)['tools'], false);
      expect(_supports(retained.first.metadata)['tools'], false);
    },
  );

  for (final feature in ['tools', 'constrained', 'embeddings', 'docs']) {
    test(
      'disabled $feature cannot be overridden and does not construct a runtime',
      () async {
        final restrictedPlugin = LlamaDartPlugin(
          models: [
            LlamaModelDefinition(
              name: 'restricted',
              modelPath: '/model',
              supportsTools: feature != 'tools',
              supportsConstrainedOutput: feature != 'constrained',
              supportsEmbeddings: feature != 'embeddings',
              modelInfo: genkit.ModelInfo(
                supports: {
                  'tools': true,
                  'constrained': true,
                  'embeddings': true,
                },
              ),
            ),
          ],
          runtimeFactory: () {
            factoryCalls++;
            return runtime;
          },
        );
        addTearDown(restrictedPlugin.dispose);
        final actions = await restrictedPlugin.init();
        final restricted = actions
            .whereType<genkit.Model<LlamaDartGenerationConfig>>()
            .single;
        if (feature == 'embeddings') {
          expect(actions.whereType<genkit.Embedder>(), isEmpty);
        } else {
          final request = feature == 'docs'
              ? genkit.ModelRequest(
                  messages: [_message(genkit.Role.user)],
                  docs: [
                    genkit.DocumentData(
                      content: [genkit.TextPart(text: 'document')],
                    ),
                  ],
                )
              : feature == 'tools'
              ? _request(tools: _tools)
              : _request(output: genkit.OutputConfig(format: 'json'));
          await expectLater(
            () => restricted(request),
            throwsA(
              _status(
                feature == 'docs'
                    ? genkit.StatusCode.invalidArgument
                    : genkit.StatusCode.failedPrecondition,
              ),
            ),
          );
        }
        expect(factoryCalls, 0);
        expect(runtime.initializeCount, 0);
        expect(runtime.capabilityReadCount, 0);
        expect(_supports(restricted.metadata)[feature], isNot(true));
        await restricted(_request());
        expect(_supports(restricted.metadata)[feature], isNot(true));
      },
    );
  }

  test('a projector path alone does not confirm media support', () async {
    runtime.capabilitySnapshot = _textOnly;
    final projectedPlugin = LlamaDartPlugin(
      models: const [
        LlamaModelDefinition(
          name: 'projected',
          modelPath: '/model.gguf',
          mmprojPath: '/projector.gguf',
        ),
      ],
      runtimeFactory: () => runtime,
    );
    addTearDown(projectedPlugin.dispose);
    final action = (await projectedPlugin.init())
        .whereType<genkit.Model<LlamaDartGenerationConfig>>()
        .single;
    await expectLater(
      action(_media('image/png')),
      throwsA(_status(genkit.StatusCode.unimplemented)),
    );
    expect(runtime.lastInitializedDefinition!.mmprojPath, '/projector.gguf');
    expect(_supports(action.metadata)['media'], false);
    expect(runtime.createCallCount, 0);
  });

  test(
    'pending capability refresh clears stale metadata before inference',
    () async {
      final delayed = _DelayedRuntime()..createChunks = [textChunk('ok')];
      final delayedPlugin = LlamaDartPlugin(
        models: const [
          LlamaModelDefinition(name: 'delayed', modelPath: '/model'),
        ],
        runtimeFactory: () => delayed,
      );
      addTearDown(delayedPlugin.dispose);
      final action = (await delayedPlugin.init())
          .whereType<genkit.Model<LlamaDartGenerationConfig>>()
          .single;
      await action(_request());
      delayed.waitForProbe = Completer<void>();
      delayed.probeStarted = Completer<void>();
      final second = action(_request(tools: _tools));
      await delayed.probeStarted!.future;
      expect(delayed.initializeCount, 1);
      expect(delayed.createCallCount, 1);
      expect(_state(action.metadata)['state'], 'unverified');
      expect(_supports(action.metadata)['tools'], false);
      delayed.capabilitySnapshot = _textOnly;
      delayed.waitForProbe!.complete();
      await expectLater(
        second,
        throwsA(_status(genkit.StatusCode.unimplemented)),
      );
      expect(delayed.createCallCount, 1);
    },
  );

  final unsupportedRequests = <String, genkit.ModelRequest Function()>{
    'tools': () => _request(tools: _tools),
    'system message': () => _request(
      messages: [_message(genkit.Role.system), _message(genkit.Role.user)],
    ),
    'history': () => _request(
      messages: [
        _message(genkit.Role.user),
        _message(genkit.Role.model),
        _message(genkit.Role.user),
      ],
    ),
    'image': () => _media('image/png'),
    'audio': () => _media('audio/wav'),
    'structured output': () =>
        _request(output: genkit.OutputConfig(format: 'json')),
    'tool request history': () => _request(
      messages: [
        genkit.Message(
          role: genkit.Role.model,
          content: [
            genkit.ToolRequestPart(
              toolRequest: genkit.ToolRequest(
                name: 'lookup',
                ref: 'call',
                input: {},
              ),
            ),
          ],
        ),
      ],
    ),
    'tool response history': () => _request(
      messages: [
        genkit.Message(
          role: genkit.Role.tool,
          content: [
            genkit.ToolResponsePart(
              toolResponse: genkit.ToolResponse(
                name: 'lookup',
                ref: 'call',
                output: {'answer': 1},
              ),
            ),
          ],
        ),
      ],
    ),
  };
  for (final entry in unsupportedRequests.entries) {
    test('text-only runtime rejects ${entry.key} before inference', () async {
      runtime.capabilitySnapshot = _textOnly;
      await expectLater(
        model(entry.value()),
        throwsA(_status(genkit.StatusCode.unimplemented)),
      );
      expect(runtime.initializeCount, 1);
      expect(runtime.createCallCount, 0);
      expect(runtime.chatTemplateCallCount, 0);
      expect(runtime.generateCallCount, 0);
    });
    test('verified runtime forwards ${entry.key}', () async {
      runtime.generatedTokens = ['{}'];
      await model(entry.value());
      if (entry.key == 'structured output') {
        expect(runtime.chatTemplateCallCount, 1);
        expect(runtime.generateCallCount, 1);
      } else {
        expect(runtime.createCallCount, 1);
        expect(runtime.lastMessages, isNotEmpty);
      }
    });
  }

  test(
    'native LiteRT allows chat and tools but rejects strict JSON and embeddings',
    () async {
      runtime.capabilitySnapshot = _nativeLiteRt;
      await model(_request(tools: _tools));
      expect(runtime.lastTools!.single.name, 'lookup');
      await expectLater(
        model(_request(output: genkit.OutputConfig(format: 'json'))),
        throwsA(_status(genkit.StatusCode.unimplemented)),
      );
      await expectLater(
        embedder(_embedRequest()),
        throwsA(_status(genkit.StatusCode.unimplemented)),
      );
      expect(runtime.chatTemplateCallCount, 0);
      expect(runtime.generateCallCount, 0);
      expect(runtime.embedBatchCallCount, 0);
      expect(_supports(model.metadata)['constrained'], false);
      expect(_supports(embedder.metadata)['embeddings'], false);
    },
  );

  test(
    'structured declaration without grammar does not advertise or run strict JSON',
    () async {
      runtime.capabilitySnapshot = const llama.LlamaEngineCapabilities(
        isSupported: true,
        supportsStructuredOutput: true,
      );
      await expectLater(
        model(_request(output: genkit.OutputConfig(format: 'json'))),
        throwsA(_status(genkit.StatusCode.unimplemented)),
      );
      expect(_supports(model.metadata)['constrained'], false);
      expect(runtime.generateCallCount, 0);
    },
  );

  test('text-only runtime runs single-turn text', () async {
    runtime.capabilitySnapshot = _textOnly;
    expect((await model(_request())).text, 'ok');
    expect(runtime.createCallCount, 1);
  });

  test('built-in media reaches inference without a projector', () async {
    await model(_media('image/png'));
    expect(runtime.lastInitializedDefinition!.mmprojPath, isNull);
    expect(
      runtime.lastMessages!.single.parts.single,
      isA<llama.LlamaImageContent>(),
    );
    await model(_media('audio/wav'));
    expect(
      runtime.lastMessages!.single.parts.single,
      isA<llama.LlamaAudioContent>(),
    );
    expect(_supports(model.metadata)['media'], true);
  });

  test(
    'native LiteRT preserves best-effort media while web rejects it',
    () async {
      runtime.capabilitySnapshot = _nativeLiteRt;
      for (final contentType in ['image/png', 'audio/wav']) {
        if (const bool.fromEnvironment('dart.library.io')) {
          await model(_media(contentType));
        } else {
          await expectLater(
            model(_media(contentType)),
            throwsA(_status(genkit.StatusCode.unimplemented)),
          );
        }
      }
      expect(_supports(model.metadata)['media'], false);
      expect(
        runtime.createCallCount,
        const bool.fromEnvironment('dart.library.io') ? 2 : 0,
      );
    },
  );

  test(
    'each request refreshes capabilities and cannot reuse stale permission',
    () async {
      await model(_request(tools: _tools));
      runtime.capabilitySnapshot = _textOnly;
      await expectLater(
        model(_request(tools: _tools)),
        throwsA(_status(genkit.StatusCode.unimplemented)),
      );
      expect(runtime.initializeCount, 1);
      expect(runtime.capabilityReadCount, 2);
      expect(runtime.createCallCount, 1);
      expect(_supports(model.metadata)['tools'], false);
    },
  );

  test(
    'probe failure clears metadata, blocks inference and allows a clean retry',
    () async {
      await model(_request());
      runtime.capabilityError = StateError(
        'secret /private/model?token=credential',
      );
      await expectLater(
        model(_request()),
        throwsA(
          isA<llama.LlamaStateException>().having(
            (e) => e.toString(),
            'safe diagnostic',
            allOf(
              contains('LlamaRuntimeCapabilityProvider'),
              isNot(contains('credential')),
              isNot(contains('/private/model')),
            ),
          ),
        ),
      );
      expect(_state(model.metadata)['state'], 'unverified');
      expect(_supports(model.metadata)['tools'], false);
      expect(runtime.createCallCount, 1);
      runtime.capabilityError = null;
      await model(_request());
      expect(runtime.initializeCount, 1);
      expect(runtime.createCallCount, 2);
      expect(_state(model.metadata)['state'], 'verified');
    },
  );

  test(
    'a snapshot without a ready model blocks even plain text and embeddings',
    () async {
      runtime.capabilitySnapshot = const llama.LlamaEngineCapabilities(
        isSupported: false,
        unsupportedReason: '/private/model?token=secret',
      );
      await expectLater(
        model(_request()),
        throwsA(_status(genkit.StatusCode.failedPrecondition)),
      );
      await expectLater(
        embedder(_embedRequest()),
        throwsA(_status(genkit.StatusCode.failedPrecondition)),
      );
      expect(runtime.createCallCount, 0);
      expect(runtime.embedBatchCallCount, 0);
      expect(_state(model.metadata)['ready'], false);
    },
  );

  test(
    'legacy custom runtime stays usable for basic text but cannot promise advanced support',
    () async {
      final legacy = _LegacyRuntime(runtime);
      final legacyPlugin = LlamaDartPlugin(
        models: const [
          LlamaModelDefinition(name: 'legacy', modelPath: '/model'),
        ],
        runtimeFactory: () => legacy,
      );
      addTearDown(legacyPlugin.dispose);
      final actions = await legacyPlugin.init();
      final action = actions
          .whereType<genkit.Model<LlamaDartGenerationConfig>>()
          .single;
      expect((await action(_request())).text, 'ok');
      await expectLater(
        action(_request(tools: _tools)),
        throwsA(
          _status(genkit.StatusCode.failedPrecondition).having(
            (e) => e.toString(),
            'diagnostic',
            contains('LlamaRuntimeCapabilityProvider'),
          ),
        ),
      );
      final embed = actions
          .whereType<genkit.Embedder<LlamaDartEmbedConfig>>()
          .single;
      await expectLater(
        embed(_embedRequest()),
        throwsA(_status(genkit.StatusCode.failedPrecondition)),
      );
      for (final config in [
        const LlamaDartGenerationConfig(presencePenalty: 2),
        const LlamaDartGenerationConfig(
          thinkingBudget: ThinkingBudget(maxTokens: 0),
        ),
        const LlamaDartGenerationConfig(speculativeDecoding: true),
        const LlamaDartGenerationConfig(reusePromptPrefix: false),
        const LlamaDartGenerationConfig(streamBatchTokenThreshold: 1),
      ]) {
        final request = _request()..config = config.toJson();
        await expectLater(
          action(request),
          throwsA(_status(genkit.StatusCode.failedPrecondition)),
        );
      }
      expect(runtime.createCallCount, 1);
      expect(runtime.capabilityReadCount, 0);
      expect(_state(action.metadata)['state'], 'unverified');
    },
  );
}

// This implementation deliberately has no capability provider interface.
class _LegacyRuntime implements LlamaDartRuntime {
  _LegacyRuntime(this.delegate);
  final FakeRuntime delegate;
  @override
  Future<void> initialize(LlamaModelDefinition definition) =>
      delegate.initialize(definition);
  @override
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    llama.GenerationParams? params,
    List<llama.ToolDefinition>? tools,
    llama.ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
  }) => delegate.create(messages, params: params);
  @override
  void cancelGeneration() => delegate.cancelGeneration();
  @override
  Future<void> dispose() => delegate.dispose();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected advanced call: ${invocation.memberName}');
}

class _DelayedRuntime extends FakeRuntime {
  Completer<void>? waitForProbe;
  Completer<void>? probeStarted;
  @override
  Future<llama.LlamaEngineCapabilities> get capabilities async {
    expect(initializeCount, 1);
    probeStarted?.complete();
    await waitForProbe?.future;
    return super.capabilities;
  }
}
