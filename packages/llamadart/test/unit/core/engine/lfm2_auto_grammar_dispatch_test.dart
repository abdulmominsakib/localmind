import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart' as backend_internal;
import 'package:test/test.dart';

import 'engine_test.dart';

const _metadata = {
  'llm.context_length': '4096',
  'tokenizer.chat_template':
      '{# <|tool_list_start|> <|tool_list_end|> #}'
      '{% for m in messages %}{{ m["content"] }}{% endfor %}<think>',
};
const _messages = [
  LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Call clock.'),
];
final _tools = [
  ToolDefinition(
    name: 'clock',
    description: 'Time',
    parameters: [],
    handler: (_) async => '',
  ),
];

class _PenaltyBackend extends MockLlamaBackend
    implements BackendPromptPenaltyGeneration, BackendLazyGrammarSupport {
  _PenaltyBackend() : super(modelMetadataResponse: _metadata);
  bool supported = true;
  bool lazySupported = true;
  bool loseSupportAfterProbe = false;
  int probes = 0;
  int policyDispatches = 0;
  @override
  bool get supportsLazyGrammar => lazySupported;
  @override
  bool get supportsPromptPenaltiesWithGrammar {
    probes++;
    return supported && (!loseSupportAfterProbe || probes == 1);
  }

  @override
  Stream<List<int>> generateWithPromptPenalties(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    String? mediaMarker,
    List<LlamaContentPart>? parts,
  }) {
    policyDispatches++;
    return super.generate(contextHandle, prompt, params, parts: parts);
  }
}

class _HybridBackend extends _PenaltyBackend
    implements BackendNativeChatGeneration {
  int nativeCalls = 0;
  @override
  bool get supportsNativeChatGeneration => true;
  @override
  Stream<List<int>> generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    String? sourceLangCode,
    String? targetLangCode,
    DateTime? templateNow,
  }) {
    nativeCalls++;
    return super.generate(contextHandle, 'native', params);
  }
}

class _StructuredHybridBackend extends _HybridBackend
    implements backend_internal.BackendChatMessageValidation {
  @override
  bool get requiresStructuredChatInput => true;
  @override
  void validateChatMessages(List<LlamaChatMessage> messages) {}
}

void main() {
  test(
    'hybrid native chat backend uses the scoped LFM auto prompt route',
    () async {
      final backend = _HybridBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await engine.create(_messages, tools: _tools).drain<void>();
      expect(backend.policyDispatches, 1);
      expect(backend.nativeCalls, 0);
    },
  );
  test(
    'mandatory structured chat rejects the scoped LFM auto combination',
    () async {
      final backend = _StructuredHybridBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await expectLater(
        engine.create(_messages, tools: _tools).drain<void>(),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(backend.policyDispatches, 0);
      expect(backend.nativeCalls, 0);
    },
  );
  test('hybrid native chat remains available for LFM none', () async {
    final backend = _HybridBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('fake.gguf');
    await engine
        .create(_messages, tools: _tools, toolChoice: ToolChoice.none)
        .drain<void>();
    expect(backend.policyDispatches, 0);
    expect(backend.nativeCalls, 1);
  });

  test(
    'public LFM auto preserves policy through thought and draft parameter copies',
    () async {
      final backend = _PenaltyBackend()
        ..generationText =
            '</think><|tool_call_start|>[clock()]<|tool_call_end|>';
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      final completion = await engine
          .create(
            _messages,
            tools: _tools,
            params: GenerationParams(
              seed: 101,
              speculativeDecodingConfig: SpeculativeDecodingConfig(
                draftModelDownload: ModelLoadOptions(
                  headers: {'capture': 'discard'},
                ),
              ),
            ),
          )
          .collect();
      expect(completion.toolCalls.single.name, 'clock');
      expect(backend.policyDispatches, 1);
      expect(backend.lastGenerationParams!.seed, 101);
      expect(backend.lastGenerationParams!.grammarLazy, isTrue);
      expect(backend.lastGenerationParams!.grammarTriggers, isNotEmpty);
      expect(
        backend
            .lastGenerationParams!
            .speculativeDecodingConfig!
            .draftModelDownload
            .headers,
        isEmpty,
      );
    },
  );

  for (final late in [false, true]) {
    test(
      'public LFM auto rejects ${late ? 'lost' : 'false'} capability before dispatch',
      () async {
        final backend = _PenaltyBackend()
          ..supported = late
          ..loseSupportAfterProbe = late;
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('fake.gguf');
        await expectLater(
          engine.create(_messages, tools: _tools).drain<void>(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(backend.policyDispatches, 0);
        expect(backend.lastGenerationParams, isNull);
      },
    );
  }

  test(
    'custom backend without the new capability rejects LFM auto before dispatch',
    () async {
      final backend = MockLlamaBackend(modelMetadataResponse: _metadata);
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await expectLater(
        engine.create(_messages, tools: _tools).drain<void>(),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(backend.lastGenerationParams, isNull);
    },
  );

  for (final choice in [ToolChoice.required, ToolChoice.none]) {
    test(
      '$choice retains ordinary dispatch without the new capability',
      () async {
        final backend = _PenaltyBackend()..supported = false;
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('fake.gguf');
        await engine
            .create(_messages, tools: _tools, toolChoice: choice)
            .drain<void>();
        expect(backend.policyDispatches, 0);
        expect(backend.lastGenerationParams, isNotNull);
      },
    );
  }

  test(
    'explicit response schema replaces auto grammar and its policy',
    () async {
      final backend = _PenaltyBackend()..supported = false;
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await engine
          .create(
            _messages,
            tools: _tools,
            responseFormat: {
              'type': 'json_schema',
              'json_schema': {
                'schema': {'type': 'string'},
              },
            },
          )
          .drain<void>();
      expect(backend.policyDispatches, 0);
      expect(backend.lastGenerationParams!.grammarLazy, isFalse);
      expect(backend.lastGenerationParams!.grammarTriggers, isEmpty);
    },
  );

  test('force JSON auto retains legacy lazy-unsupported fallback', () async {
    final backend = _PenaltyBackend()
      ..supported = false
      ..lazySupported = false;
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('fake.gguf');
    await engine.create([
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: 'Force JSON schema.',
      ),
      ..._messages,
    ], tools: _tools).drain<void>();
    expect(backend.policyDispatches, 0);
    expect(backend.lastGenerationParams!.grammar, isNull);
    expect(backend.lastGenerationParams!.grammarLazy, isFalse);
  });

  test(
    'force JSON auto retains ordinary dispatch without the new capability',
    () async {
      final backend = _PenaltyBackend()..supported = false;
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      await engine.create([
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: 'Force JSON schema.',
        ),
        ..._messages,
      ], tools: _tools).drain<void>();
      expect(backend.policyDispatches, 0);
      expect(backend.lastGenerationParams!.grammar, contains('root-item'));
    },
  );
}
