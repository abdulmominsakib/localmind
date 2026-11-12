@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/web/web_backend.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:llamadart/src/core/decision/decision_engine.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show Blob, BlobPropertyBag, URL, document;

import '../../../support/fake_webgpu_decision_bridge.dart';

void main() {
  late List<FakeDecisionBridge> bridges;
  late bool withDecisionApi;
  late LlamaEngine engine;

  LlamaBackend fakeBackend() => WebAutoBackend(
    webGpuFactory: () => WebGpuLlamaBackend(
      bridgeFactory: ([config]) {
        final fake = FakeDecisionBridge(
          withDecisionApi: withDecisionApi,
          withModelApi: true,
        );
        bridges.add(fake);
        return fake.bridge;
      },
    ),
  );

  setUp(() {
    bridges = <FakeDecisionBridge>[];
    withDecisionApi = true;
    engine = LlamaEngine(fakeBackend());
  });

  tearDown(() => engine.dispose());

  Future<void> loadModel() => engine.loadModel(
    'laya-Q8_0.gguf',
    modelParams: const ModelParams(contextSize: 512),
  );

  final questions = <String, DecisionQuestion>{
    'department': DecisionQuestion.choice(
      'Which department?',
      criteria: {'billing': null, 'technical': null, 'other': null},
    ),
    'refund': DecisionQuestion.noul('Refund requested?'),
  };

  test('answers questions through the WebGPU bridge', () async {
    await loadModel();

    final capabilities = await DecisionEngine.capabilitiesFor(engine);
    final decisions = await DecisionEngine.attach(
      engine,
      head: ModelSource.path('laya-head.safetensors'),
    );
    final result = await decisions.systemOne(
      state: 'Billed twice.',
      questions: questions,
    );
    await decisions.dispose();

    final fake = bridges.single;
    expect(capabilities.isSupported, isTrue);
    expect(capabilities.backendName, 'WebGPU (Fake)');
    expect(decisions.info.maxTokens, 32);
    expect(decisions.info.headMaxTokens, 16);
    expect(decisions.info.deviceName, 'WebGPU');
    expect(fake.lastSequences, hasLength(2));
    for (final sequence in fake.lastSequences) {
      expect(sequence.typedArrays, isTrue);
      expect(sequence.tokens.first, 1);
      expect(sequence.tokens.last, 2);
      expect(
        [for (final m in sequence.markers) sequence.tokens[m]],
        [for (final _ in sequence.markers) 3],
      );
    }
    expect(fake.lastSequences.map((s) => s.markers.length), [3, 2]);
    expect(fake.lastSequences.map((s) => s.questionType), [0, 2]);
    expect(result.choices['department']!.choice, 'billing');
    expect(result.nouls['refund']!.noul, lessThan(0.5));
    expect(
      result.usage.inputTokens,
      fake.lastSequences.fold<int>(0, (n, s) => n + s.tokens.length),
    );
    expect(fake.calls.last, 'free 7');
    expect(fake.liveHandles, isEmpty);
  });

  test('reads typed keys from Web results', () async {
    await loadModel();
    final decisions = await DecisionEngine.attach(
      engine,
      head: ModelSource.path('laya-head.safetensors'),
    );
    addTearDown(decisions.dispose);
    final department = ChoiceKey.enumOf(
      'department',
      'Which department?',
      criteria: {
        _Department.billing: null,
        _Department.technical: null,
        _Department.other: null,
      },
    );
    final urgency = ScoreKey.of(
      'urgency',
      'How urgent?',
      levels: ['low', 'high'],
    );
    final refund = NoulKey.of('refund', 'Refund requested?');

    final result = await decisions.systemOne(
      state: 'Billed twice.',
      questions: DecisionKey.questionsOf([department, urgency, refund]),
    );

    expect(bridges.single.lastSequences.map((s) => s.questionType), [0, 1, 2]);
    expect(result.questions!['department'], same(department.question));
    expect(result.answerOf(department).value, _Department.billing);
    expect(result.answerOf(urgency).levelProbabilities, hasLength(2));
    expect(result.answerOf(refund).noul, result.nouls['refund']!.noul);
    expect(
      () => result.answerOf(NoulKey.of('refund', 'Refund requested?')),
      throwsA(
        isA<LlamaDecisionException>().having(
          (error) => error.message,
          'message',
          startsWith('Result question "refund" is not this key\'s question'),
        ),
      ),
    );
  });

  test('fetches the config in the page', () async {
    const config = '{"max_len": 48, "head_max_len": 24}';
    final url = URL.createObjectURL(
      Blob(<JSAny>[config.toJS].toJS, BlobPropertyBag(type: 'text/plain')),
    );
    addTearDown(() => URL.revokeObjectURL(url));
    await loadModel();

    final decisions = await DecisionEngine.attach(
      engine,
      head: ModelSource.path('model.safetensors'),
      config: ModelSource.path(url),
    );

    expect(bridges.single.loadedConfigs, [config]);
    expect(decisions.info.maxTokens, 48);
    expect(decisions.info.headMaxTokens, 24);
  });

  test(
    'attach passes document-relative and blob sources to the bridge',
    () async {
      const config = '{"max_len": 48, "head_max_len": 24}';
      final url = URL.createObjectURL(
        Blob(<JSAny>[config.toJS].toJS, BlobPropertyBag(type: 'text/plain')),
      );
      addTearDown(() => URL.revokeObjectURL(url));
      await loadModel();

      final decisions = await DecisionEngine.attach(
        engine,
        head: ModelSource.path('models/model.safetensors'),
        config: ModelSource.path(url),
      );
      await decisions.dispose();

      final fake = bridges.single;
      expect(
        fake.calls.singleWhere((call) => call.startsWith('load ')),
        'load ${URL('models/model.safetensors', document.baseURI).href}',
      );
      expect(fake.loadedConfigs, [config]);
      expect(decisions.info.maxTokens, 48);
      expect(fake.disposeCalls, 0);
      expect(engine.isReady, isTrue);
    },
  );

  test('load owns a Web engine and frees it on dispose', () async {
    debugDecisionBackendFactory = fakeBackend;
    addTearDown(() => debugDecisionBackendFactory = null);

    final decisions = await DecisionEngine.load(
      DecisionModel(
        encoder: ModelSource.parse('https://example.com/laya-Q8_0.gguf'),
        head: ModelSource.parse('https://example.com/laya-head.safetensors'),
      ),
    );
    final capabilities = await decisions.capabilities;
    final result = await decisions.systemOne(
      state: 'Billed twice.',
      questions: questions,
    );
    await decisions.dispose();

    final fake = bridges.single;
    expect(capabilities.isSupported, isTrue);
    expect(capabilities.runtime, LlamaRuntime.llamaCpp);
    expect(
      fake.calls,
      contains('loadModel https://example.com/laya-Q8_0.gguf'),
    );
    expect(
      fake.calls,
      contains('load https://example.com/laya-head.safetensors'),
    );
    expect(result.choices['department']!.choice, 'billing');
    expect(fake.liveHandles, isEmpty);
    expect(fake.disposeCalls, 1);
  });

  test('reports bridge assets without the decision API', () async {
    withDecisionApi = false;
    await loadModel();

    final capabilities = await DecisionEngine.capabilitiesFor(engine);

    expect(capabilities.isSupported, isFalse);
    expect(
      capabilities.unsupportedReason,
      'Web decision models need llama-web-bridge assets v0.1.47+ with the '
      'decision API (apiVersion 1); the loaded bridge does not expose it.',
    );
    await expectLater(
      DecisionEngine.attach(
        engine,
        head: ModelSource.path('laya-head.safetensors'),
      ),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });

  test('reports decision API version skew', () async {
    await loadModel();
    bridges.single.capabilitiesApiVersion = 2;

    await expectLater(
      DecisionEngine.attach(
        engine,
        head: ModelSource.path('laya-head.safetensors'),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('decision API version 2'),
        ),
      ),
    );
    expect(
      bridges.single.calls.where((call) => call.startsWith('load ')),
      isEmpty,
    );
  });

  test(
    'a cancelled capability probe fails attach with LlamaStateException',
    () async {
      await loadModel();
      bridges.single.capabilitiesError =
          'Decision capability probe was cancelled.';

      final capabilities = await DecisionEngine.capabilitiesFor(engine);

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('was cancelled'));
      await expectLater(
        DecisionEngine.attach(
          engine,
          head: ModelSource.path('laya-head.safetensors'),
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Decision capability probe was cancelled.',
          ),
        ),
      );
    },
  );

  test(
    'a head fails with LlamaStateException after the model unloads',
    () async {
      await loadModel();
      final decisions = await DecisionEngine.attach(
        engine,
        head: ModelSource.path('laya-head.safetensors'),
      );

      await engine.unloadModel();

      await expectLater(
        decisions.systemOne(state: 'Billed twice.', questions: questions),
        throwsA(isA<LlamaStateException>()),
      );
      await decisions.dispose();
      final fake = bridges.single;
      expect(fake.disposeCalls, 1);
      expect(fake.calls.where((call) => call.startsWith('free')), isEmpty);
      expect(fake.calls.where((call) => call.startsWith('run')), isEmpty);
    },
  );
}

enum _Department { billing, technical, other }
