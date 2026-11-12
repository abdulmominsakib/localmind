import 'dart:async';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'engine_test.dart' show MockLlamaBackend;

const _llamaCppGeneration = BackendGenerationCapabilities(
  penalty: true,
  presencePenalty: true,
  minP: true,
  thinkingBudget: true,
  streamBatching: true,
  speculativeDecodingStrategies: <SpeculativeDecodingStrategy>{
    SpeculativeDecodingStrategy.ngramMod,
    SpeculativeDecodingStrategy.mtp,
  },
);

const _liteRtLmNativeGeneration = BackendGenerationCapabilities(
  presencePenalty: false,
  minP: false,
  thinkingBudget: false,
  streamBatching: true,
  speculativeDecodingStrategies: <SpeculativeDecodingStrategy>{
    SpeculativeDecodingStrategy.backendDefault,
    SpeculativeDecodingStrategy.mtp,
  },
);

/// A backend shaped like one of the built-in runtimes through the probes
/// `LlamaEngine.capabilities` reads.
class _RuntimeBackend extends MockLlamaBackend
    implements
        BackendRuntimeIdentity,
        BackendGenerationCapabilitiesSupport,
        BackendGrammarConstraintsSupport,
        BackendLazyGrammarSupport,
        BackendEmbeddingsSupport,
        BackendNextTokenScoringSupport,
        BackendDirectMediaInput,
        BackendChatScope {
  _RuntimeBackend({
    required this.runtime,
    required this.generation,
    super.backendName,
    this.supportsGrammarConstraints = true,
    this.supportsLazyGrammar = true,
    this.supportsEmbeddings = true,
    this.supportsNextTokenScoring = true,
    this.directMedia = (vision: false, audio: false),
    this.supportsMultiTurnChat = true,
    this.supportsToolCalling = true,
    this.projectorProbeError,
    this.backendNameError,
  });

  @override
  final LlamaRuntime runtime;
  final BackendGenerationCapabilities generation;
  @override
  final bool supportsGrammarConstraints;
  @override
  final bool supportsLazyGrammar;
  @override
  final bool supportsEmbeddings;
  @override
  final bool supportsNextTokenScoring;
  final ({bool vision, bool audio}) directMedia;
  @override
  final bool supportsMultiTurnChat;
  @override
  final bool supportsToolCalling;
  final Object? projectorProbeError;
  final Object? backendNameError;

  /// When set, [generationCapabilities] waits for it.
  Completer<void>? generationGate;

  /// When set, [generationCapabilities] throws it after [generationGate].
  Object? generationError;

  @override
  Future<BackendGenerationCapabilities> generationCapabilities() async {
    await generationGate?.future;
    if (generationError case final error?) throw error;
    return generation;
  }

  @override
  Future<({bool vision, bool audio})> directMediaInput() async => directMedia;

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    if (projectorProbeError case final error?) throw error;
    return super.supportsVision(mmContextHandle);
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    if (projectorProbeError case final error?) throw error;
    return super.supportsAudio(mmContextHandle);
  }

  @override
  Future<String> getBackendName() async {
    if (backendNameError case final error?) throw error;
    return super.getBackendName();
  }
}

void main() {
  late List<LlamaEngine> engines;

  setUp(() => engines = <LlamaEngine>[]);

  tearDown(() async {
    for (final engine in engines) {
      await engine.dispose();
    }
  });

  Future<LlamaEngine> loaded(LlamaBackend backend) async {
    final engine = LlamaEngine(backend);
    engines.add(engine);
    await engine.loadModel('model.gguf');
    return engine;
  }

  test('reports no model and no capability before a load', () async {
    final engine = LlamaEngine(
      _RuntimeBackend(
        runtime: LlamaRuntime.llamaCpp,
        generation: _llamaCppGeneration,
      ),
    );
    engines.add(engine);

    final capabilities = await engine.capabilities;

    expect(engine.runtime, isNull);
    expect(capabilities.isSupported, isFalse);
    expect(capabilities.unsupportedReason, contains('No model is loaded'));
    expect(capabilities.runtime, isNull);
    expect(capabilities.backendName, isNull);
    expect(capabilities.supportsMultiTurnChat, isFalse);
    expect(capabilities.supportsGrammar, isFalse);
    expect(capabilities.supportsPenalty, isFalse);
    expect(capabilities.speculativeDecodingStrategies, isEmpty);
  });

  test('reads as the shared EngineCapabilities', () async {
    final engine = await loaded(
      _RuntimeBackend(
        runtime: LlamaRuntime.llamaCpp,
        generation: _llamaCppGeneration,
        backendName: 'Metal',
      ),
    );

    final EngineCapabilities capabilities = await engine.capabilities;

    expect(capabilities.isSupported, isTrue);
    expect(capabilities.unsupportedReason, isNull);
    expect(capabilities.backendName, 'Metal');
  });

  test('reports a llama.cpp runtime with a vision projector', () async {
    final engine = await loaded(
      _RuntimeBackend(
        runtime: LlamaRuntime.llamaCpp,
        generation: _llamaCppGeneration,
        backendName: 'Metal',
      ),
    );

    final textOnly = await engine.capabilities;
    expect(engine.runtime, LlamaRuntime.llamaCpp);
    expect(textOnly.isSupported, isTrue);
    expect(textOnly.unsupportedReason, isNull);
    expect(textOnly.backendName, 'Metal');
    expect(textOnly.runtime, LlamaRuntime.llamaCpp);
    expect(textOnly.supportsVision, isFalse);
    expect(textOnly.supportsAudio, isFalse);
    expect(textOnly.supportsEmbeddings, isTrue);
    expect(textOnly.supportsNextTokenScoring, isTrue);
    expect(textOnly.supportsMultiTurnChat, isTrue);
    expect(textOnly.supportsToolCalling, isTrue);
    expect(textOnly.supportsStructuredOutput, isTrue);
    expect(textOnly.supportsGrammar, isTrue);
    expect(textOnly.supportsLazyGrammar, isTrue);
    expect(textOnly.supportsPenalty, isTrue);
    expect(textOnly.supportsPresencePenalty, isTrue);
    expect(textOnly.supportsMinP, isTrue);
    expect(textOnly.supportsThinkingBudget, isTrue);
    expect(textOnly.supportsStreamBatching, isTrue);
    expect(
      textOnly.speculativeDecodingStrategies,
      _llamaCppGeneration.speculativeDecodingStrategies,
    );
    expect(
      () => textOnly.speculativeDecodingStrategies.add(
        SpeculativeDecodingStrategy.ngramCache,
      ),
      throwsUnsupportedError,
    );

    await engine.loadMultimodalProjector('mmproj.gguf');
    final withProjector = await engine.capabilities;
    expect(withProjector.supportsVision, isTrue);
    expect(withProjector.supportsAudio, isFalse);
    expect(await engine.supportsVision, isTrue);
    expect(await engine.supportsAudio, isFalse);

    await engine.unloadMultimodalProjector();
    expect((await engine.capabilities).supportsVision, isFalse);
    expect(await engine.supportsVision, isFalse);

    await engine.unloadModel();
    expect(engine.runtime, isNull);
    expect((await engine.capabilities).isSupported, isFalse);
  });

  test('reports a native LiteRT-LM bundle that takes media directly', () async {
    final engine = await loaded(
      _RuntimeBackend(
        runtime: LlamaRuntime.liteRtLm,
        generation: _liteRtLmNativeGeneration,
        backendName: 'LiteRT-LM gpu',
        supportsGrammarConstraints: false,
        supportsEmbeddings: false,
        supportsNextTokenScoring: false,
        directMedia: (vision: true, audio: true),
      ),
    );

    final capabilities = await engine.capabilities;

    expect(engine.runtime, LlamaRuntime.liteRtLm);
    expect(capabilities.runtime, LlamaRuntime.liteRtLm);
    expect(capabilities.supportsVision, isTrue);
    expect(capabilities.supportsAudio, isTrue);
    expect(engine.hasMultimodalProjector, isFalse);
    expect(await engine.supportsVision, isTrue);
    expect(await engine.supportsAudio, isTrue);
    expect(capabilities.supportsEmbeddings, isFalse);
    expect(capabilities.supportsNextTokenScoring, isFalse);
    expect(capabilities.supportsMultiTurnChat, isTrue);
    expect(capabilities.supportsToolCalling, isTrue);
    expect(capabilities.supportsStructuredOutput, isFalse);
    expect(capabilities.supportsGrammar, isFalse);
    expect(capabilities.supportsLazyGrammar, isFalse);
    expect(capabilities.supportsPenalty, isFalse);
    expect(capabilities.supportsPresencePenalty, isFalse);
    expect(capabilities.supportsMinP, isFalse);
    expect(capabilities.supportsThinkingBudget, isFalse);
    expect(capabilities.supportsStreamBatching, isTrue);
    expect(
      capabilities.speculativeDecodingStrategies,
      _liteRtLmNativeGeneration.speculativeDecodingStrategies,
    );
  });

  test('reports a single-turn LiteRT-LM web runtime', () async {
    final engine = await loaded(
      _RuntimeBackend(
        runtime: LlamaRuntime.liteRtLm,
        generation: const BackendGenerationCapabilities(
          presencePenalty: false,
          minP: false,
          thinkingBudget: false,
        ),
        supportsGrammarConstraints: false,
        supportsEmbeddings: false,
        supportsMultiTurnChat: false,
        supportsToolCalling: false,
      ),
    );

    final capabilities = await engine.capabilities;

    expect(capabilities.supportsMultiTurnChat, isFalse);
    expect(capabilities.supportsToolCalling, isFalse);
    expect(capabilities.supportsVision, isFalse);
    expect(capabilities.supportsAudio, isFalse);
    expect(capabilities.supportsStreamBatching, isFalse);
    expect(capabilities.speculativeDecodingStrategies, isEmpty);
  });

  test('reports a WebGPU runtime whose grammar is not lazy', () async {
    final engine = await loaded(
      _RuntimeBackend(
        runtime: LlamaRuntime.llamaCpp,
        generation: const BackendGenerationCapabilities(
          penalty: true,
          presencePenalty: false,
          minP: true,
          thinkingBudget: false,
        ),
        supportsLazyGrammar: false,
      ),
    );

    final capabilities = await engine.capabilities;

    expect(capabilities.supportsStructuredOutput, isTrue);
    expect(capabilities.supportsGrammar, isTrue);
    expect(capabilities.supportsLazyGrammar, isFalse);
    expect(capabilities.supportsPenalty, isTrue);
    expect(capabilities.supportsPresencePenalty, isFalse);
    expect(capabilities.supportsMinP, isTrue);
    expect(capabilities.supportsStreamBatching, isFalse);
  });

  test('reports a backend without probes by its structural defaults', () async {
    final engine = await loaded(MockLlamaBackend());

    final capabilities = await engine.capabilities;

    expect(engine.runtime, isNull);
    expect(capabilities.isSupported, isTrue);
    expect(capabilities.runtime, isNull);
    expect(capabilities.backendName, 'Mock');
    expect(capabilities.supportsMultiTurnChat, isTrue);
    expect(capabilities.supportsToolCalling, isTrue);
    expect(capabilities.supportsGrammar, isTrue);
    expect(capabilities.supportsLazyGrammar, isTrue);
    expect(capabilities.supportsEmbeddings, isFalse);
    expect(capabilities.supportsPenalty, isFalse);
    expect(capabilities.supportsMinP, isFalse);
    expect(capabilities.speculativeDecodingStrategies, isEmpty);
  });

  for (final reload in [false, true]) {
    test('reports no model when the model ${reload ? 'reloads' : 'unloads'} '
        'while capabilities are read', () async {
      final backend = _RuntimeBackend(
        runtime: LlamaRuntime.llamaCpp,
        generation: _llamaCppGeneration,
      );
      final engine = await loaded(backend);
      final gate = backend.generationGate = Completer<void>();

      final pending = engine.capabilities;
      await engine.unloadModel();
      if (reload) await engine.loadModel('model.gguf');
      gate.complete();
      final capabilities = await pending;

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.runtime, isNull);
      expect(capabilities.supportsPenalty, isFalse);
      backend.generationGate = null;
      expect((await engine.capabilities).isSupported, reload);
    });
  }

  test('reports no model when a probe fails because the model unloaded '
      'while capabilities are read', () async {
    final backend = _RuntimeBackend(
      runtime: LlamaRuntime.llamaCpp,
      generation: _llamaCppGeneration,
    );
    final engine = await loaded(backend);
    final gate = backend.generationGate = Completer<void>();

    final pending = engine.capabilities;
    await engine.unloadModel();
    backend.generationError = StateError('model handle is gone');
    gate.complete();
    final capabilities = await pending;

    expect(capabilities.isSupported, isFalse);
    expect(capabilities.unsupportedReason, contains('No model is loaded'));
    expect(capabilities.runtime, isNull);
  });

  for (final grammar in [true, false]) {
    test('ChatSession rejects strict responseFormat exactly when '
        'capabilities report no structured output ($grammar)', () async {
      final engine = await loaded(
        _RuntimeBackend(
          runtime: LlamaRuntime.liteRtLm,
          generation: _liteRtLmNativeGeneration,
          supportsGrammarConstraints: grammar,
        ),
      );

      expect((await engine.capabilities).supportsStructuredOutput, grammar);
      final turn = ChatSession(engine).create(
        const [LlamaTextContent('Hi')],
        responseFormat: const {'type': 'json_object'},
      );
      if (grammar) {
        await turn.drain<void>();
      } else {
        await expectLater(
          turn.drain<void>(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }
    });
  }

  test('reports a failed media probe or backend name as missing', () async {
    final engine = await loaded(
      _RuntimeBackend(
        runtime: LlamaRuntime.llamaCpp,
        generation: _llamaCppGeneration,
        projectorProbeError: LlamaUnsupportedException('no mtmd'),
        backendNameError: StateError('worker gone'),
      ),
    );
    await engine.loadMultimodalProjector('mmproj.gguf');

    final capabilities = await engine.capabilities;

    expect(capabilities.isSupported, isTrue);
    expect(capabilities.backendName, isNull);
    expect(capabilities.supportsVision, isFalse);
    expect(capabilities.supportsAudio, isFalse);
    expect(await engine.supportsVision, isFalse);
    expect(await engine.supportsAudio, isFalse);
  });

  test('reports a disposed engine without probing the backend', () async {
    final backend = _RuntimeBackend(
      runtime: LlamaRuntime.liteRtLm,
      generation: _liteRtLmNativeGeneration,
      directMedia: (vision: true, audio: true),
    );
    final engine = await loaded(backend);
    await engine.dispose();
    backend.generationGate = Completer<void>();

    final capabilities = await engine.capabilities;

    expect(capabilities.isSupported, isFalse);
    expect(capabilities.unsupportedReason, contains('disposed'));
    expect(capabilities.runtime, isNull);
    expect(capabilities.supportsVision, isFalse);
    expect(await engine.supportsVision, isFalse);
    expect(await engine.supportsAudio, isFalse);
  });

  test('reports disposed when the engine is disposed while capabilities '
      'are read', () async {
    final backend = _RuntimeBackend(
      runtime: LlamaRuntime.llamaCpp,
      generation: _llamaCppGeneration,
    );
    final engine = await loaded(backend);
    final gate = backend.generationGate = Completer<void>();

    final pending = engine.capabilities;
    final disposal = engine.dispose();
    gate.complete();
    await disposal;
    final capabilities = await pending;

    expect(capabilities.isSupported, isFalse);
    expect(capabilities.unsupportedReason, contains('disposed'));
  });
}
