import 'dart:async';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../core/runtime/test_support/fake_runtime.dart';

void main() {
  test(
    'registration stays lazy; inspection loads once without inference',
    () async {
      final strategies = <SpeculativeDecodingStrategy>{
        SpeculativeDecodingStrategy.ngramSimple,
      };
      final runtime = _InspectionRuntime()
        ..capabilitySnapshot = LlamaEngineCapabilities(
          isSupported: true,
          backendName: 'CPU',
          supportsMinP: true,
          supportsThinkingBudget: true,
          speculativeDecodingStrategies: strategies,
        );
      var factories = 0;
      final plugin = LlamaDartPlugin(
        models: [_definition],
        runtimeFactory: () {
          factories++;
          return runtime;
        },
      );
      addTearDown(plugin.dispose);
      final listed = await plugin.list();
      await plugin.init();
      expect(factories, 0);
      final snapshot = await plugin.inspectModel('local');
      expect(factories, 1);
      expect(runtime.initializeCount, 1);
      expect(snapshot.contextSize, 2048);
      expect(snapshot.capabilities!.backendName, 'CPU');
      expect(snapshot.capabilities!.supportsMinP, true);
      expect(snapshot.capabilities!.supportsThinkingBudget, true);
      strategies.clear();
      expect(snapshot.capabilities!.speculativeDecodingStrategies, {
        SpeculativeDecodingStrategy.ngramSimple,
      });
      expect(
        () => snapshot.capabilities!.speculativeDecodingStrategies.clear(),
        throwsUnsupportedError,
      );
      expect(
        (listed.first.metadata['llamadartCapabilities'] as Map)['state'],
        'verified',
      );
      await plugin.inspectModel('local');
      expect(runtime.initializeCount, 1);
      expect(runtime.createCallCount, 0);
      expect(runtime.generateCallCount, 0);
      expect(runtime.chatTemplateCallCount, 0);
      expect(runtime.embedBatchCallCount, 0);
    },
  );

  test(
    'raw counting and special-token options use the runtime tokenizer',
    () async {
      final runtime = _InspectionRuntime();
      final plugin = _plugin(runtime);
      addTearDown(plugin.dispose);
      final tokens = await plugin.tokenize('local', 'hello world');
      expect(tokens, [10, 20]);
      expect(() => tokens.add(30), throwsUnsupportedError);
      expect(await plugin.countTokens('local', 'hello world'), tokens.length);
      expect(await plugin.tokenize('local', 'hello world', addSpecial: true), [
        1,
        10,
        20,
      ]);
      expect(runtime.tokenRequests, [false, false, true]);
      expect(runtime.tokenTexts, ['hello world', 'hello world', 'hello world']);
      expect(runtime.createCallCount, 0);
      expect(runtime.chatTemplateCallCount, 0);
    },
  );

  test(
    'custom runtimes without inspection preserve absent values and fail tokenization',
    () async {
      final runtime = FakeRuntime();
      final plugin = _plugin(runtime);
      addTearDown(plugin.dispose);
      final result = await plugin.inspectModel('local');
      expect(result.capabilities!.isSupported, true);
      expect(result.contextSize, isNull);
      await expectLater(
        plugin.countTokens('local', 'hello'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(runtime.createCallCount, 0);
      expect(runtime.initializeCount, 1);
    },
  );

  test(
    'unverified runtimes remain unverified without invented measurements',
    () async {
      final runtime = _UnverifiedRuntime();
      final plugin = LlamaDartPlugin(
        models: [_definition],
        runtimeFactory: () => runtime,
      );
      addTearDown(plugin.dispose);
      final result = await plugin.inspectModel('local');
      expect(result.capabilities, isNull);
      expect(result.contextSize, isNull);
      await expectLater(
        plugin.tokenize('local', ''),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test(
    'unsupported tokenizer failures do not poison later queued work',
    () async {
      final runtime = _InspectionRuntime()
        ..tokenError = LlamaUnsupportedException(
          'Tokenizer unavailable on this runtime.',
        );
      final plugin = _plugin(runtime);
      addTearDown(plugin.dispose);
      await expectLater(
        plugin.countTokens('local', 'hello'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      runtime.tokenError = null;
      expect(await plugin.countTokens('local', 'hello'), 2);
    },
  );

  test(
    'missing diagnostics remain null and arbitrary labels/reasons stay private',
    () async {
      final runtime = _InspectionRuntime()
        ..actualContext = 0
        ..capabilitySnapshot = const LlamaEngineCapabilities(
          isSupported: false,
          backendName: 'https://host/model?token=secret',
          unsupportedReason: '/private/models/secret.gguf',
        );
      final plugin = _plugin(runtime);
      addTearDown(plugin.dispose);
      final result = await plugin.inspectModel('local');
      expect(result.contextSize, isNull);
      expect(result.capabilities!.backendName, isNull);
      expect(runtime.contextReads, 0);
      await expectLater(
        plugin.tokenize('local', 'hello'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(runtime.tokenRequests, isEmpty);
      expect(
        result.capabilities!.unsupportedReason,
        'The loaded runtime is unavailable.',
      );
    },
  );

  test(
    'inspection and tokenization queue behind generation and disposal waits',
    () async {
      final runtime = _InspectionRuntime();
      final plugin = _plugin(runtime);
      final ai = genkit.Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(ai.shutdown);
      final response = ai.generate(
        model: llamaDart.model('local'),
        prompt: 'hello',
      );
      await runtime.started.future;
      final inspection = plugin.inspectModel('local');
      final tokens = plugin.countTokens('local', 'hello');
      final disposal = plugin.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(runtime.contextReads, 0);
      expect(runtime.tokenRequests, isEmpty);
      expect(runtime.disposeCount, 0);
      runtime.release.complete();
      expect((await response).text, 'ready');
      expect((await inspection).contextSize, 2048);
      expect(await tokens, 2);
      await disposal;
      expect(runtime.disposeCount, 1);
      expect(() => plugin.inspectModel('local'), throwsStateError);
      expect(() => plugin.tokenize('local', 'hello'), throwsStateError);
      await expectLater(plugin.countTokens('local', 'hello'), throwsStateError);
    },
  );

  test(
    'unavailable measurements are null while recognized backend labels remain visible',
    () async {
      final runtime = _InspectionRuntime()..actualContext = 0;
      final plugin = _plugin(runtime);
      addTearDown(plugin.dispose);
      for (final label in [
        'CPU',
        'Metal',
        'Vulkan',
        'CUDA',
        'OpenCL',
        'HIP',
        'BLAS',
        'WebGPU',
        'WebGPU (Web)',
        'WASM',
        'WASM (CPU)',
        'LiteRT-LM CPU',
        'LiteRT-LM GPU',
        'LiteRT-LM TPU',
        'LiteRT-LM NPU',
        'LiteRT-LM Web CPU',
        'LiteRT-LM Web GPU',
        'LiteRT-LM Web auto',
      ]) {
        runtime.capabilitySnapshot = LlamaEngineCapabilities(
          isSupported: true,
          backendName: label,
        );
        final result = await plugin.inspectModel('local');
        expect(result.contextSize, isNull);
        expect(result.capabilities!.backendName, label);
      }
    },
  );

  test('unknown model cannot construct or load a runtime', () async {
    var factories = 0;
    final plugin = LlamaDartPlugin(
      models: [_definition],
      runtimeFactory: () {
        factories++;
        return _InspectionRuntime();
      },
    );
    addTearDown(plugin.dispose);
    expect(() => plugin.inspectModel('other'), throwsStateError);
    expect(() => plugin.tokenize('other', 'hello'), throwsStateError);
    expect(factories, 0);
  });
}

const _definition = LlamaModelDefinition(
  name: 'local',
  modelPath: '/models/local.gguf',
  supportsEmbeddings: false,
);
LlamaDartPlugin _plugin(FakeRuntime runtime) =>
    LlamaDartPlugin(models: [_definition], runtimeFactory: () => runtime);

class _InspectionRuntime extends FakeRuntime
    implements LlamaRuntimeInspectionProvider {
  int? actualContext = 2048;
  int contextReads = 0;
  Object? tokenError;
  final tokenRequests = <bool>[];
  final tokenTexts = <String>[];
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<int?> get contextSize async {
    contextReads++;
    return actualContext;
  }

  @override
  Future<List<int>> tokenize(String text, {bool addSpecial = false}) async {
    if (tokenError != null) throw tokenError!;
    tokenRequests.add(addSpecial);
    tokenTexts.add(text);
    return [if (addSpecial) 1, 10, 20];
  }

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
  }) async* {
    createCallCount++;
    started.complete();
    await release.future;
    yield textChunk('ready', finishReason: 'stop');
  }
}

class _UnverifiedRuntime implements LlamaDartRuntime {
  @override
  Future<void> initialize(LlamaModelDefinition definition) async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected runtime call.');
}
