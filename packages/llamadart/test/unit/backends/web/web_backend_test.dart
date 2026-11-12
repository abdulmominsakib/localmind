@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/web/web_backend.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/engine/chat_completion_request_planner.dart';
import 'package:llamadart/src/core/engine/chat_session.dart';
import 'package:llamadart/src/core/engine/chat_session_tool_loop.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:llamadart/src/core/engine/engine_observer.dart';
import 'package:llamadart/src/core/engine/load_check_report.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/config/compute_device.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/config/lora_config.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/generation_usage.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/inference/next_token_scores.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/model_format.dart';
import 'package:llamadart/src/core/models/model_resolver.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:llamadart/src/core/speech/text_to_speech.dart';
import 'package:llamadart/src/core/speech/text_to_speech_model.dart';
import 'package:llamadart/src/core/models/inference/embedding.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend_web.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';

import '../../../support/load_check_agreement.dart';
import '../../core/engine/engine_test.dart';
import '../../core/engine/multimodal_embeddings_test.dart';

void main() {
  test('checkLoad rejects fields the named runtime ignores', () {
    final backend = WebAutoBackend();
    expect(
      () => backend.checkLoad(
        const ModelParams(useMlock: true),
        ModelFormat.gguf,
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains(
            'llama.cpp on the Web does not apply these ModelParams: '
            'useMlock.',
          ),
        ),
      ),
    );
    expect(
      () => backend.checkLoad(
        const ModelParams(liteRtLmCacheDir: '/cache'),
        ModelFormat.liteRtLm,
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('liteRtLmCacheDir'),
        ),
      ),
    );
    backend.checkLoad(
      const ModelParams(modelBytesHint: 1 << 30),
      ModelFormat.gguf,
    );
    backend.checkLoad(const ModelParams(useMlock: true), null);
  });

  test('checkLoad rejects a subtype for the other runtime', () {
    final backend = WebAutoBackend();
    expect(
      () => backend.checkLoad(const LiteRtLmModelParams(), ModelFormat.gguf),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('Use LlamaCppModelParams.'),
        ),
      ),
    );
    backend.checkLoad(
      const LiteRtLmModelParams(contextSize: 2048),
      ModelFormat.liteRtLm,
    );
  });

  test('LlamaEngine.checkLoad reports and agrees with what setModel rejects '
      'on the Web before any fetch', () async {
    final resolver = SentinelResolver();
    final engine = LlamaEngine(WebAutoBackend(), modelResolver: resolver);
    addTearDown(engine.dispose);
    final gguf = LlamaModel(ModelSource.parse('https://example.com/m.gguf'));
    final liteRtLm = LlamaModel(
      ModelSource.parse('https://example.com/m.litertlm'),
    );
    final cases = <(LlamaModel, ModelParams, LlamaLoadCheckStatus, String?)>[
      (gguf, const ModelParams(), LlamaLoadCheckStatus.supported, null),
      (
        gguf,
        const ModelParams(useMlock: true),
        LlamaLoadCheckStatus.unsupported,
        'llama.cpp on the Web does not apply these ModelParams: useMlock.',
      ),
      (
        liteRtLm,
        const ModelParams(
          loras: [LoraAdapterConfig(path: 'https://example.com/a.gguf')],
        ),
        LlamaLoadCheckStatus.unsupported,
        'LiteRtLmBackend web does not support',
      ),
      (
        LlamaModel(ModelSource.parse('https://example.com/download?id=7')),
        const ModelParams(useMlock: true),
        LlamaLoadCheckStatus.deferred,
        'Set ModelSource.format',
      ),
      (
        liteRtLm,
        const ModelParams(device: ComputeDevice.npu),
        LlamaLoadCheckStatus.unsupported,
        'ComputeDevice.npu is not available for LiteRT-LM on the Web',
      ),
      (
        liteRtLm,
        const ModelParams(liteRtLmEmbeddingEngine: true),
        LlamaLoadCheckStatus.unsupported,
        'LiteRT-LM WebGPU embeddings are unavailable',
      ),
      (
        liteRtLm,
        const ModelParams(
          liteRtLmEmbeddingEngine: true,
          device: ComputeDevice.cpu,
        ),
        LlamaLoadCheckStatus.unsupported,
        'LiteRT-LM Web CPU embeddings are unavailable',
      ),
      (
        liteRtLm,
        const ModelParams(
          liteRtLmEmbeddingEngine: true,
          // ignore: deprecated_member_use_from_same_package
          liteRtLmBackend: LiteRtLmBackendPreference.npu,
        ),
        LlamaLoadCheckStatus.unsupported,
        'LiteRtLmBackendPreference.npu is not available for LiteRT-LM on the '
            'Web',
      ),
      (liteRtLm, const ModelParams(), LlamaLoadCheckStatus.supported, null),
    ];
    for (final (model, params, status, reason) in cases) {
      final report = await engine.checkLoad(model, params: params);
      expect(report.status, status, reason: '$report');
      if (reason != null) expect(report.reason, contains(reason));
      expect(resolver.calls, 0);
      await expectSetModelAgrees(engine, resolver, model, params, report);
    }
  });

  test('router cancels content during its own capability probe', () async {
    final delegate = ContentBackend()..probeGate = Completer<void>();
    final router = WebAutoBackend(webGpuFactory: () => delegate);
    addTearDown(router.dispose);
    final model = await router.modelLoad('fake.gguf', const ModelParams());
    final context = await router.contextCreate(model, const ModelParams());
    final input = LlamaEmbeddingInput([const LlamaTextContent('text')]);
    final future = router.embedContentBatch(context, List.filled(64, input));
    await pumpEventQueue();
    router.cancelGeneration();
    final cancelled = expectLater(
      future,
      throwsA(isA<LlamaInferenceException>()),
    );
    delegate.probeGate!.complete();
    await cancelled;
    expect(delegate.received, isEmpty);
    expect(await router.embedContentBatch(context, [input]), [
      [1.0],
    ]);
  });

  test(
    'unloaded context probes return all-false without creating a runtime',
    () async {
      final router = WebAutoBackend(
        webGpuFactory: () =>
            throw StateError('probe must not create a runtime'),
        liteRtLmFactory: () =>
            throw StateError('probe must not create a runtime'),
      );
      addTearDown(router.dispose);
      final capabilities = await router.getEmbeddingCapabilities(-1);
      expect(capabilities.text, isFalse);
      expect(capabilities.image, isFalse);
      expect(capabilities.audio, isFalse);
    },
  );

  for (final runtime in LlamaRuntime.values) {
    test(
      'embedding diagnostic identifies $runtime through the router',
      () async {
        final delegate = RuntimeContentBackend(runtime)
          ..supported = const LlamaEmbeddingCapabilities(text: true);
        final router = WebAutoBackend(webGpuFactory: () => delegate);
        final engine = LlamaEngine(router);
        addTearDown(engine.dispose);
        await engine.loadModel('https://example.com/fake.gguf');
        await expectLater(
          engine.embedContent(
            LlamaEmbeddingInput([const LlamaImageContent(path: 'secret.png')]),
          ),
          throwsA(
            isA<LlamaUnsupportedException>()
                .having((e) => e.message, 'runtime', contains(runtime.name))
                .having((e) => e.message, 'modality', contains('image'))
                .having(
                  (e) => e.message,
                  'condition',
                  contains('capability probe'),
                )
                .having(
                  (e) => e.message,
                  'redaction',
                  isNot(contains('secret')),
                ),
          ),
        );
      },
    );
  }

  test(
    'all current web backends reject image and audio embeddings before inference',
    () async {
      for (final backend in <LlamaBackend>[
        WebGpuLlamaBackend(),
        LiteRtLmBackend(),
        WebAutoBackend(),
      ]) {
        addTearDown(backend.dispose);
        final capabilities = await backend.probeEmbeddingCapabilities(1);
        expect(capabilities.image, isFalse);
        expect(capabilities.audio, isFalse);
        for (final part in <LlamaContentPart>[
          const LlamaImageContent(path: 'secret.png'),
          const LlamaAudioContent(path: 'secret.wav'),
        ]) {
          final input = LlamaEmbeddingInput([part]);
          await expectLater(
            backend.embedContentWithFallback(1, [input]),
            throwsA(
              isA<LlamaUnsupportedException>()
                  .having(
                    (error) => error.message,
                    'modality',
                    contains(input.partKinds.single.name),
                  )
                  .having(
                    (error) => error.message,
                    'redaction',
                    isNot(contains('secret')),
                  ),
            ),
          );
        }
      }
    },
  );

  test(
    'router forwards loaded embedding probe and ordered content to its delegate',
    () async {
      final delegate = ContentBackend();
      final router = WebAutoBackend(webGpuFactory: () => delegate);
      final engine = LlamaEngine(router);
      addTearDown(engine.dispose);
      expect((await router.getEmbeddingCapabilities(1)).image, isFalse);
      await engine.loadModel('https://example.com/fake.gguf');
      expect((await engine.embeddingCapabilities).image, isTrue);
      final input = LlamaEmbeddingInput([
        const LlamaImageContent(path: 'image.png'),
        const LlamaTextContent('caption'),
      ]);
      expect(await engine.embedContent(input, normalize: false), [2.0]);
      expect(delegate.received.single, same(input));
      expect(delegate.normalized, isFalse);
    },
  );

  test(
    'router uses legacy text fallback and reports media unavailable',
    () async {
      final delegate = MockEmbeddingBackend();
      final router = WebAutoBackend(webGpuFactory: () => delegate);
      final engine = LlamaEngine(router);
      addTearDown(engine.dispose);
      await engine.loadModel('https://example.com/fake.gguf');
      final capabilities = await engine.embeddingCapabilities;
      expect(capabilities.text, isTrue);
      expect(capabilities.image, isFalse);
      final input = LlamaEmbeddingInput([const LlamaTextContent('same')]);
      expect(await engine.embedContent(input), await engine.embed('same'));
    },
  );

  test('createBackend returns WebAutoBackend', () {
    final backend = createBackend();

    expect(backend, isA<LlamaBackend>());
    expect(backend, isA<WebAutoBackend>());
    expect(backend, isA<BackendEmbeddings>());
    expect(backend, isA<BackendEmbeddingsSupport>());
    expect(backend, isA<BackendBatchEmbeddings>());
    expect(backend, isA<BackendStatePersistence>());
    expect(backend, isA<BackendStatePersistenceSupport>());
    expect(backend, isA<BackendPromptSpeechToTextSupport>());
    expect(backend, isA<BackendTextToSpeech>());
    expect(backend, isA<BackendDecision>());
    expect(backend, isA<BackendNextTokenScoring>());
    expect(backend, isA<BackendNextTokenScoringSupport>());
    expect((backend as WebAutoBackend).supportsStatePersistence, isFalse);
    expect(backend.supportsNextTokenScoring, isFalse);
    expect(backend.supportsEmbeddings, isFalse);
  });

  test('WebAutoBackend reports the runtime of its delegate', () {
    expect(
      WebAutoBackend(
        webBackend: _RuntimeBackend(LlamaRuntime.llamaCpp),
      ).runtime,
      LlamaRuntime.llamaCpp,
    );
    expect(WebAutoBackend(webBackend: _NoStateBackend()).runtime, isNull);
    expect(WebAutoBackend().runtime, isNull);
  });

  test('WebAutoBackend forwards explicit unsupported limit reporting', () {
    expect(
      WebAutoBackend(
        webBackend: _LimitSupportBackend('runtime has no reason'),
      ).generationLimitUnsupportedReason,
      'runtime has no reason',
    );
    expect(
      WebAutoBackend(
        webBackend: _LimitSupportBackend(null),
      ).generationLimitUnsupportedReason,
      isNull,
    );
    expect(
      WebAutoBackend(
        webBackend: _NoStateBackend(),
      ).generationLimitUnsupportedReason,
      isNull,
    );
    expect(WebAutoBackend().generationLimitUnsupportedReason, isNull);
  });

  test(
    'WebAutoBackend prevents an automatic loop on an explicitly unsupported delegate',
    () async {
      final engine = LlamaEngine(
        WebAutoBackend(
          webBackend: _LimitSupportBackend('runtime has no reason'),
        ),
      );
      addTearDown(engine.dispose);
      final session = ChatSession(engine, maxContextTokens: 0);
      await expectLater(
        session.sendWithTools('Reply', tools: const []),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('runtime has no reason'),
          ),
        ),
      );
      expect(session.history, isEmpty);
    },
  );

  test('WebAutoBackend forwards generation limits from its delegate', () {
    final generation = Stream<List<int>>.empty();
    final limit = BackendGenerationLimit.runtime;
    expect(
      WebAutoBackend(
        webBackend: _LimitBackend({generation: limit}),
      ).generationLimitOf(generation),
      limit,
    );
    expect(
      WebAutoBackend(
        webBackend: _NoStateBackend(),
      ).generationLimitOf(generation),
      isNull,
    );
    expect(WebAutoBackend().generationLimitOf(generation), isNull);
  });

  test('WebAutoBackend forwards generation usage from its delegate', () {
    final generation = Stream<List<int>>.empty();
    const usage = LlamaGenerationUsage(promptTokens: 4, completionTokens: 2);

    expect(
      WebAutoBackend(
        webBackend: _UsageBackend({generation: usage}),
      ).generationUsageOf(generation),
      same(usage),
    );
    expect(
      WebAutoBackend(
        webBackend: _NoStateBackend(),
      ).generationUsageOf(generation),
      isNull,
    );
  });

  test('WebAutoBackend forwards grammar support from its delegate', () {
    final unsupported = WebAutoBackend(
      webBackend: _GrammarSupportBackend(supportsGrammarConstraints: false),
    );
    final supported = WebAutoBackend(
      webBackend: _GrammarSupportBackend(supportsGrammarConstraints: true),
    );
    final legacy = WebAutoBackend(webBackend: _NoStateBackend());

    expect(unsupported, isA<BackendGrammarConstraintsSupport>());
    expect(unsupported.supportsGrammarConstraints, isFalse);
    expect(supported.supportsGrammarConstraints, isTrue);
    expect(legacy.supportsGrammarConstraints, isTrue);
  });

  test('WebAutoBackend forwards lazy grammar support from its delegate', () {
    final eager = WebAutoBackend(webBackend: _EagerGrammarBackend());
    final legacy = WebAutoBackend(webBackend: _NoStateBackend());

    expect(eager, isA<BackendLazyGrammarSupport>());
    expect(eager.supportsLazyGrammar, isFalse);
    expect(legacy.supportsLazyGrammar, isTrue);
  });

  test(
    'WebAutoBackend forwards deferred engine creation from its delegate',
    () {
      final deferred = WebAutoBackend(webBackend: _DeferredEngineBackend());
      final legacy = WebAutoBackend(webBackend: _NoStateBackend());

      expect(deferred, isA<BackendDeferredEngineCreation>());
      expect(deferred.defersEngineCreation, isTrue);
      expect(legacy.defersEngineCreation, isFalse);
    },
  );

  test('WebAutoBackend rejects strict output for unsupported delegates', () {
    final backend = WebAutoBackend(
      webBackend: _GrammarSupportBackend(supportsGrammarConstraints: false),
    );

    expect(
      () => ChatCompletionRequestPlanner.build(
        backend: backend,
        templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
        responseFormat: const {'type': 'json_object'},
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('active backend does not support grammar constraints'),
        ),
      ),
    );
  });

  test('WebAutoBackend forwards prompt speech runtime support', () async {
    final unsupported = WebAutoBackend(webBackend: _NoStateBackend());
    expect(unsupported.supportsPromptSpeechToText, isFalse);
    expect(
      unsupported.promptSpeechToTextUnsupportedReason,
      contains('does not expose'),
    );

    final supported = WebAutoBackend(webBackend: _SpeechSupportBackend());
    expect(supported.supportsPromptSpeechToText, isTrue);
    expect(supported.promptSpeechToTextUnsupportedReason, isNull);
  });

  test('WebAutoBackend forwards LoRA and projector calls to a capable '
      'delegate', () async {
    final delegate = _LoraMultimodalBackend();
    final backend = WebAutoBackend(webBackend: delegate);

    await backend.setLoraAdapter(1, 'a.gguf', 0.5);
    await backend.removeLoraAdapter(1, 'a.gguf');
    await backend.clearLoraAdapters(1);
    expect(await backend.multimodalContextCreate(1, 'mmproj.gguf'), 9);
    expect(await backend.supportsVision(9), isTrue);
    expect(await backend.supportsAudio(9), isTrue);
    await backend.multimodalContextFree(9);
    expect(delegate.calls, [
      'set a.gguf 0.5',
      'remove a.gguf',
      'clear',
      'create mmproj.gguf',
      'vision 9',
      'audio 9',
      'free 9',
    ]);
  });

  test('WebAutoBackend rejects LoRA and projector calls for a delegate '
      'without the capabilities', () {
    final backend = WebAutoBackend(webBackend: _NoStateBackend());
    Matcher unsupported(String operation) => throwsA(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        '$operation are not supported by the active Web runtime.',
      ),
    );

    expect(
      () => backend.setLoraAdapter(1, 'a.gguf', 1),
      unsupported('LoRA adapters'),
    );
    expect(
      () => backend.removeLoraAdapter(1, 'a.gguf'),
      unsupported('LoRA adapters'),
    );
    expect(() => backend.clearLoraAdapters(1), unsupported('LoRA adapters'));
    expect(
      () => backend.multimodalContextCreate(1, 'mmproj.gguf'),
      unsupported('Multimodal projectors'),
    );
    expect(
      () => backend.multimodalContextFree(1),
      unsupported('Multimodal projectors'),
    );
    expect(
      () => backend.supportsVision(1),
      unsupported('Multimodal projectors'),
    );
    expect(
      () => backend.supportsAudio(1),
      unsupported('Multimodal projectors'),
    );
  });

  test(
    'WebAutoBackend forwards typed text-to-speech to its delegate',
    () async {
      final delegate = _TextToSpeechBackend();
      final backend = WebAutoBackend(webBackend: delegate);

      final capabilities = await backend.textToSpeechCapabilities(3, 4);
      expect(capabilities.isSupported, isTrue);
      expect(capabilities.sampleRateHz, 24000);

      final result = await backend.synthesizeTextToSpeech(
        3,
        4,
        const BackendTextToSpeechRequest(text: 'Hello'),
      );
      expect(result.samples, <double>[0.25, -0.25]);
      expect(delegate.lastText, 'Hello');
      expect(delegate.capabilityHandles, (3, 4));
      expect(delegate.synthesisHandles, (3, 4));

      backend.cancelTextToSpeech();
      expect(delegate.cancelCalls, 1);
    },
  );

  test(
    'WebAutoBackend drives Qwen3-TTS only and refuses others before loading',
    () async {
      final backend = WebAutoBackend(webBackend: _NoStateBackend());
      for (final model in BackendTextToSpeechModel.values) {
        final reason = await backend.textToSpeechModelUnsupportedReason(model);
        if (model == BackendTextToSpeechModel.qwen3Tts) {
          expect(reason, isNull);
        } else {
          expect(reason, contains('Web text-to-speech drives Qwen3-TTS only'));
        }
      }

      final delegate = _LoadRecordingBackend();
      await expectLater(
        TextToSpeechEngine.load(
          TextToSpeechModel(
            ModelSource.url(Uri.parse('https://example.com/lfm3.gguf')),
            projector: ModelSource.url(
              Uri.parse('https://example.com/mmproj.gguf'),
            ),
            adapter: const Lfm3AudioTtsAdapter(),
          ),
          backend: WebAutoBackend(webBackend: delegate),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('Qwen3-TTS only'),
          ),
        ),
      );
      expect(delegate.loadedUrls, isEmpty);
    },
  );

  test('WebAutoBackend throws typed unsupported TTS errors', () {
    final backend = WebAutoBackend(webBackend: _NoStateBackend());

    expect(
      () => backend.synthesizeTextToSpeech(
        3,
        4,
        const BackendTextToSpeechRequest(text: 'Hello'),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('active Web runtime'),
        ),
      ),
    );
  });

  test(
    'WebAutoBackend reports embedding support from active delegate',
    () async {
      final unsupported = WebAutoBackend(
        webBackend: _EmbeddingSupportBackend(supportsEmbeddings: false),
      );
      expect(unsupported.supportsEmbeddings, isFalse);

      final supported = WebAutoBackend(
        webBackend: _EmbeddingSupportBackend(supportsEmbeddings: true),
      );
      expect(supported.supportsEmbeddings, isTrue);
      expect(await supported.embed(1, 'hello'), <double>[1, 2, 3]);
    },
  );

  test('WebAutoBackend reports state support from injected delegate', () async {
    final backend = WebAutoBackend(webBackend: _NoStateBackend());
    final engine = LlamaEngine(backend);

    expect(backend.supportsStatePersistence, isFalse);
    expect(engine.supportsStatePersistence, isFalse);

    await engine.loadModel('/model.gguf');
    expect(engine.supportsStatePersistence, isFalse);
    await expectLater(
      () =>
          engine.stateSaveFile('/prompt-prefix.state', tokens: const <int>[1]),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('v0.1.15'),
        ),
      ),
    );
  });

  test('WebAutoBackend forwards next-token scoring to its delegate', () async {
    final scoring = _ScoringBackend(supportsNextTokenScoring: true);
    final backend = WebAutoBackend(webBackend: scoring);
    expect(backend.supportsNextTokenScoring, isTrue);
    expect(
      WebAutoBackend(
        webBackend: _ScoringBackend(supportsNextTokenScoring: false),
      ).supportsNextTokenScoring,
      isFalse,
    );

    final scores = await backend.scoreNextToken(
      1,
      'prompt',
      candidates: const <int>[4, 2],
      topK: 3,
      reusePromptPrefix: false,
    );
    final request = scoring.lastRequest!;
    expect(request.$1, 1);
    expect(request.$2, 'prompt');
    expect(request.$3, <int>[4, 2]);
    expect(request.$4, 3);
    expect(request.$5, isFalse);
    expect(scores.promptTokens, 5);

    final legacy = WebAutoBackend(webBackend: _NoStateBackend());
    expect(legacy.supportsNextTokenScoring, isFalse);
    final engine = LlamaEngine(legacy);
    await engine.loadModel('/model.gguf');
    expect(engine.supportsNextTokenScoring, isFalse);
    await expectLater(
      () => engine.scoreNextToken('prompt', topK: 1),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });

  test('WebAutoBackend forwards decision calls to its delegate', () async {
    final delegate = _DecisionBackend();
    final backend = WebAutoBackend(webBackend: delegate);
    final sequence = BackendDecisionSequence(
      tokens: Int32List.fromList([1, 3, 2]),
      markers: Int32List.fromList([1]),
      questionType: DecisionQuestionType.noul,
    );

    final capabilities = await backend.decisionCapabilities(1);
    final head = await backend.decisionHeadLoad(
      1,
      'laya-head.safetensors',
      configPath: 'rl_agent_config.json',
    );
    final outputs = await backend.decisionRun(head.handle, [sequence]);
    await backend.decisionHeadFree(head.handle);

    expect(capabilities.isSupported, isTrue);
    expect(outputs.single.logits, [0.5]);
    expect(delegate.calls, [
      'capabilities 1',
      'load 1 laya-head.safetensors rl_agent_config.json',
      'run 9 1',
      'free 9',
    ]);
  });

  test('WebAutoBackend reports decision models unsupported on LiteRT-LM '
      'Web', () async {
    const reason =
        'The active Web runtime does not run decision models. Load a '
        'ModernBERT encoder GGUF, which uses the llama.cpp WebGPU bridge.';
    final liteRtLm = _RecordingBackend('litert');
    final backend = WebAutoBackend(
      webGpuFactory: _DecisionBackend.new,
      liteRtLmFactory: () => liteRtLm,
    );
    await backend.modelLoadFromUrl(
      'https://example.com/gemma-4-E2B-it-web.litertlm',
      const ModelParams(),
    );

    final capabilities = await backend.decisionCapabilities(1);

    expect(capabilities.isSupported, isFalse);
    expect(capabilities.unsupportedReason, reason);
    expect(
      () => backend.decisionHeadLoad(1, 'laya-head.safetensors'),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          reason,
        ),
      ),
    );
    expect(
      () => backend.decisionRun(1, const []),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    await backend.decisionHeadFree(1);
  });

  test(
    'WebAutoBackend reports generation capabilities of its delegate',
    () async {
      final backend = WebAutoBackend(
        webGpuFactory: _GenerationCapabilitiesBackend.new,
        liteRtLmFactory: () => _RecordingBackend('litert'),
      );

      final beforeLoad = await backend.generationCapabilities();
      expect(beforeLoad.minP, isFalse);

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );
      final webGpu = await backend.generationCapabilities();
      expect(webGpu.presencePenalty, isFalse);
      expect(webGpu.minP, isTrue);
      expect(webGpu.thinkingBudget, isTrue);
      expect(
        webGpu.speculativeDecodingStrategies,
        <SpeculativeDecodingStrategy>{SpeculativeDecodingStrategy.ngramSimple},
      );

      await backend.modelLoadFromUrl(
        'https://example.com/gemma-4-E2B-it-web.litertlm',
        const ModelParams(),
      );
      final liteRtLm = await backend.generationCapabilities();
      expect(liteRtLm.presencePenalty, isFalse);
      expect(liteRtLm.minP, isFalse);
      expect(liteRtLm.thinkingBudget, isFalse);
      expect(liteRtLm.speculativeDecodingStrategies, isEmpty);
      await backend.dispose();
    },
  );

  test('WebAutoBackend reports the chat scope of its delegate', () async {
    final backend = WebAutoBackend(
      webGpuFactory: () => _RecordingBackend('webgpu'),
      liteRtLmFactory: _SingleTurnBackend.new,
    );

    expect(backend.supportsMultiTurnChat, isTrue);
    expect(backend.supportsToolCalling, isTrue);

    await backend.modelLoadFromUrl(
      'https://example.com/model.gguf',
      const ModelParams(),
    );
    expect(backend.supportsMultiTurnChat, isTrue);
    expect(backend.supportsToolCalling, isTrue);

    await backend.modelLoadFromUrl(
      'https://example.com/gemma-4-E2B-it-web.litertlm',
      const ModelParams(),
    );
    expect(backend.supportsMultiTurnChat, isFalse);
    expect(backend.supportsToolCalling, isFalse);
    await backend.dispose();
  });

  test('WebAutoBackend rejects decision calls before a model load', () async {
    final backend = WebAutoBackend(webGpuFactory: _DecisionBackend.new);

    expect(
      () => backend.decisionCapabilities(1),
      throwsA(isA<LlamaStateException>()),
    );
    expect(
      () => backend.decisionHeadLoad(1, 'laya-head.safetensors'),
      throwsA(isA<LlamaStateException>()),
    );
    expect(
      () => backend.decisionRun(1, const []),
      throwsA(
        isA<LlamaStateException>().having(
          (e) => e.message,
          'message',
          contains('LlamaEngine.load or setModel'),
        ),
      ),
    );
    await backend.decisionHeadFree(1);
  });

  group('WebAutoBackend generateChatPrompt', () {
    test('gives a delegate that takes chat prompts the prompt and its '
        'marker', () async {
      final webGpu = _ChatPromptBackend('webgpu');
      final backend = WebAutoBackend(
        webGpuFactory: () => webGpu,
        liteRtLmFactory: () => _RecordingBackend('litert'),
      );
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      await backend
          .generateChatPrompt(
            1,
            '<m>a <__media__>',
            const GenerationParams(),
            mediaMarker: '<m>',
          )
          .drain<void>();

      expect(webGpu.chatPrompts, [('<m>a <__media__>', '<m>')]);
      expect(webGpu.prompts, isEmpty);
    });

    test('gives any other delegate the prompt with the default marker '
        'through generate', () async {
      final liteRtLm = _PromptBackend('litert');
      final backend = WebAutoBackend(
        webGpuFactory: () => _RecordingBackend('webgpu'),
        liteRtLmFactory: () => liteRtLm,
      );
      await backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      );

      await backend
          .generateChatPrompt(
            1,
            '<m>a',
            const GenerationParams(),
            mediaMarker: '<m>',
          )
          .drain<void>();

      expect(liteRtLm.prompts, ['<__media__>a']);
    });
  });

  test('WebAutoBackend routes .litertlm URLs to LiteRT-LM delegate', () async {
    final webGpu = _RecordingBackend('webgpu');
    final liteRtLm = _RecordingBackend('litert');
    final backend = WebAutoBackend(
      webGpuFactory: () => webGpu,
      liteRtLmFactory: () => liteRtLm,
    );

    await backend.modelLoadFromUrl(
      'https://example.com/model.gguf',
      const ModelParams(),
    );
    expect(webGpu.loadedUrls, ['https://example.com/model.gguf']);
    expect(liteRtLm.loadedUrls, isEmpty);
    expect(await backend.getBackendName(), 'webgpu');

    await backend.modelLoadFromUrl(
      'https://example.com/gemma-4-E2B-it-web.litertlm?download=1',
      const ModelParams(),
    );
    expect(liteRtLm.loadedUrls, [
      'https://example.com/gemma-4-E2B-it-web.litertlm?download=1',
    ]);
    expect(webGpu.disposeCalls, 1);
    expect(await backend.getBackendName(), 'litert');
  });

  group('extensionless URLs', () {
    const url = 'https://example.com/download?id=42';

    test(
      'WebAutoBackend loads extensionless URLs as GGUF by default',
      () async {
        final webGpu = _RecordingBackend('webgpu');
        final liteRtLm = _RecordingBackend('litert');
        final backend = WebAutoBackend(
          webGpuFactory: () => webGpu,
          liteRtLmFactory: () => liteRtLm,
        );

        await backend.modelLoadFromUrl(url, const ModelParams());

        expect(webGpu.loadedUrls, [url]);
        expect(liteRtLm.loadedUrls, isEmpty);
      },
    );

    test('WebAutoBackend routes an explicit format past the URL', () async {
      final webGpu = _RecordingBackend('webgpu');
      final liteRtLm = _FormatRecordingBackend('litert');
      final backend = WebAutoBackend(
        webGpuFactory: () => webGpu,
        liteRtLmFactory: () => liteRtLm,
      );

      await backend.modelLoadFromUrlAs(
        url,
        const ModelParams(),
        ModelFormat.liteRtLm,
      );
      expect(liteRtLm.loadedAs, [(url, ModelFormat.liteRtLm)]);
      expect(webGpu.loadedUrls, isEmpty);

      await backend.modelLoadAs(
        'https://example.com/model.litertlm',
        const ModelParams(),
        ModelFormat.gguf,
      );
      expect(webGpu.loadedUrls, ['https://example.com/model.litertlm']);
      expect(liteRtLm.disposeCalls, 1);
    });

    test('engine threads ModelSource.format to the Web router', () async {
      final liteRtLm = _FormatRecordingBackend('litert');
      final engine = LlamaEngine(
        WebAutoBackend(
          webGpuFactory: () => _RecordingBackend('webgpu'),
          liteRtLmFactory: () => liteRtLm,
        ),
      );

      try {
        await engine.loadModelSource(
          ModelSource.url(Uri.parse(url), format: ModelFormat.liteRtLm),
        );

        expect(liteRtLm.loadedAs, [(url, ModelFormat.liteRtLm)]);
      } finally {
        await engine.dispose();
      }
    });

    test('engine rejects ModelParams.loras for a Web LiteRT-LM model '
        'before it resolves any adapter, and resolves them for a GGUF '
        'model', () async {
      final webGpu = _FormatRecordingBackend('webgpu');
      final liteRtLm = _FormatRecordingBackend('litert');
      final resolver = _RecordingResolver();
      final engine = LlamaEngine(
        WebAutoBackend(
          webGpuFactory: () => webGpu,
          liteRtLmFactory: () => liteRtLm,
        ),
        modelResolver: resolver,
      );
      final adapter = ModelSource.url(
        Uri.parse('https://example.com/adapter.gguf'),
      );
      final params = ModelParams(loras: [LoraAdapterConfig.source(adapter)]);

      try {
        for (final model in [
          ModelSource.url(Uri.parse('https://example.com/model.litertlm')),
          ModelSource.url(Uri.parse(url), format: ModelFormat.liteRtLm),
        ]) {
          await expectLater(
            engine.loadModelSource(model, modelParams: params),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                contains('LiteRT-LM on the Web takes no LoRA adapter'),
              ),
            ),
          );
        }
        expect(resolver.resolved, isNot(contains(adapter.cacheKey)));
        expect(liteRtLm.loadedUrls, isEmpty);

        await engine.loadModelSource(
          ModelSource.url(Uri.parse('https://example.com/model.gguf')),
          modelParams: params,
        );
        expect(resolver.resolved, contains(adapter.cacheKey));
        expect(webGpu.loadedUrls, ['https://example.com/model.gguf']);
      } finally {
        await engine.dispose();
      }
    });

    test(
      'engine rejects a format a single-runtime backend cannot run',
      () async {
        final engine = LlamaEngine(_RuntimeBackend(LlamaRuntime.llamaCpp));

        try {
          await expectLater(
            engine.loadModelSource(
              ModelSource.url(Uri.parse(url), format: ModelFormat.liteRtLm),
            ),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          expect(engine.isReady, isFalse);
        } finally {
          await engine.dispose();
        }
      },
    );
  });
}

class _FormatRecordingBackend extends _RecordingBackend
    implements BackendModelFormatRouting {
  final loadedAs = <(String, ModelFormat)>[];

  _FormatRecordingBackend(super.name);

  @override
  Future<int> modelLoadAs(
    String path,
    ModelParams params,
    ModelFormat format,
  ) async {
    loadedAs.add((path, format));
    loadedUrls.add(path);
    return 1;
  }

  @override
  Future<int> modelLoadFromUrlAs(
    String url,
    ModelParams params,
    ModelFormat format, {
    void Function(double progress)? onProgress,
  }) => modelLoadAs(url, params, format);

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  void cancelGeneration() {}
}

/// Resolves like the default resolver and records each source's cache key.
class _RecordingResolver implements ModelResolver {
  final resolved = <String>[];

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) {
    resolved.add(source.cacheKey);
    return const DefaultModelResolver().resolve(source, request);
  }
}

class _LoadRecordingBackend extends _NoStateBackend {
  final List<String> loadedUrls = <String>[];

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) async {
    loadedUrls.add(url);
    return 1;
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    loadedUrls.add(path);
    return 1;
  }
}

class _NoStateBackend implements LlamaBackend {
  @override
  bool get isReady => true;

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) async => 1;

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<String> getBackendName() async => 'WebGPU';

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoraMultimodalBackend extends _NoStateBackend
    implements BackendLoraSupport, BackendMultimodalSupport {
  final List<String> calls = <String>[];

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async => calls.add('set $path $scale');

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async =>
      calls.add('remove $path');

  @override
  Future<void> clearLoraAdapters(int contextHandle) async => calls.add('clear');

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    calls.add('create $mmProjPath');
    return 9;
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async =>
      calls.add('free $mmContextHandle');

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    calls.add('vision $mmContextHandle');
    return true;
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    calls.add('audio $mmContextHandle');
    return true;
  }
}

class _PromptBackend extends _RecordingBackend {
  _PromptBackend(super.name);

  final prompts = <String>[];

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    prompts.add(prompt);
    return const Stream<List<int>>.empty();
  }
}

class _ChatPromptBackend extends _PromptBackend
    implements BackendChatPromptGeneration {
  _ChatPromptBackend(super.name);

  final chatPrompts = <(String, String)>[];

  @override
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    required String mediaMarker,
    List<LlamaContentPart>? parts,
  }) {
    chatPrompts.add((prompt, mediaMarker));
    return const Stream<List<int>>.empty();
  }
}

class _RecordingBackend implements LlamaBackend {
  final String name;
  final loadedUrls = <String>[];
  var disposeCalls = 0;

  _RecordingBackend(this.name);

  @override
  bool get isReady => loadedUrls.isNotEmpty;

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    loadedUrls.add(path);
    return 1;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) async {
    loadedUrls.add(url);
    return 1;
  }

  @override
  Future<String> getBackendName() async => name;

  @override
  Future<bool> isGpuSupported() async => name == 'webgpu';

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpeechSupportBackend extends _NoStateBackend
    implements BackendPromptSpeechToTextSupport {
  @override
  bool get supportsPromptSpeechToText => true;

  @override
  String? get promptSpeechToTextUnsupportedReason => null;
}

class _EmbeddingSupportBackend
    implements LlamaBackend, BackendEmbeddings, BackendEmbeddingsSupport {
  @override
  final bool supportsEmbeddings;

  _EmbeddingSupportBackend({required this.supportsEmbeddings});

  @override
  bool get isReady => true;

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    return const <double>[1, 2, 3];
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeferredEngineBackend extends _NoStateBackend
    implements BackendDeferredEngineCreation {
  @override
  bool get defersEngineCreation => true;
}

class _RuntimeBackend extends _NoStateBackend
    implements BackendRuntimeIdentity {
  _RuntimeBackend(this.runtime);

  @override
  final LlamaRuntime runtime;
}

class _UsageBackend extends _NoStateBackend
    implements BackendGenerationUsageReporting {
  _UsageBackend(this.usages);

  final Map<Stream<List<int>>, LlamaGenerationUsage> usages;

  @override
  LlamaGenerationUsage? generationUsageOf(Stream<List<int>> generation) =>
      usages[generation];
}

class _GrammarSupportBackend extends _NoStateBackend
    implements BackendGrammarConstraintsSupport {
  _GrammarSupportBackend({required this.supportsGrammarConstraints});

  @override
  final bool supportsGrammarConstraints;
}

class _SingleTurnBackend extends _NoStateBackend implements BackendChatScope {
  @override
  bool get supportsMultiTurnChat => false;

  @override
  bool get supportsToolCalling => false;
}

class _EagerGrammarBackend extends _NoStateBackend
    implements BackendLazyGrammarSupport {
  @override
  bool get supportsLazyGrammar => false;
}

class _TextToSpeechBackend extends _NoStateBackend
    implements BackendTextToSpeech {
  String? lastText;
  var cancelCalls = 0;
  (int, int)? capabilityHandles;
  (int, int)? synthesisHandles;

  @override
  Future<BackendTextToSpeechCapabilities> textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) async {
    capabilityHandles = (contextHandle, mmContextHandle);
    return const BackendTextToSpeechCapabilities(
      isSupported: true,
      model: BackendTextToSpeechModel.qwen3Tts,
      sampleRateHz: 24000,
      channelCount: 1,
    );
  }

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) async {
    lastText = request.text;
    synthesisHandles = (contextHandle, mmContextHandle);
    return BackendTextToSpeechResult(
      samples: Float32List.fromList(<double>[0.25, -0.25]),
      sampleRateHz: 24000,
      channelCount: 1,
      framesGenerated: 1,
      truncated: false,
    );
  }

  @override
  void cancelTextToSpeech() {
    cancelCalls += 1;
  }
}

class _ScoringBackend extends _NoStateBackend
    implements BackendNextTokenScoring, BackendNextTokenScoringSupport {
  _ScoringBackend({required this.supportsNextTokenScoring});

  @override
  final bool supportsNextTokenScoring;

  (int, String, List<int>, int, bool)? lastRequest;

  @override
  Future<LlamaNextTokenScores> scoreNextToken(
    int contextHandle,
    String prompt, {
    required List<int> candidates,
    required int topK,
    required bool reusePromptPrefix,
  }) async {
    lastRequest = (contextHandle, prompt, candidates, topK, reusePromptPrefix);
    return LlamaNextTokenScores(
      candidates: const <LlamaTokenLogprob>[],
      top: const <LlamaTokenLogprob>[],
      promptTokens: 5,
    );
  }
}

class _GenerationCapabilitiesBackend extends _NoStateBackend
    implements BackendGenerationCapabilitiesSupport {
  @override
  Future<BackendGenerationCapabilities> generationCapabilities() async {
    return const BackendGenerationCapabilities(
      presencePenalty: false,
      minP: true,
      thinkingBudget: true,
      speculativeDecodingStrategies: <SpeculativeDecodingStrategy>{
        SpeculativeDecodingStrategy.ngramSimple,
      },
    );
  }
}

class _DecisionBackend extends _NoStateBackend implements BackendDecision {
  final List<String> calls = <String>[];

  @override
  Future<BackendDecisionCapabilities> decisionCapabilities(
    int modelHandle,
  ) async {
    calls.add('capabilities $modelHandle');
    return const BackendDecisionCapabilities(isSupported: true);
  }

  @override
  Future<BackendDecisionHeadInfo> decisionHeadLoad(
    int modelHandle,
    String headPath, {
    String? configPath,
  }) async {
    calls.add('load $modelHandle $headPath $configPath');
    return const BackendDecisionHeadInfo(
      handle: 9,
      hiddenSize: 4,
      clsToken: 1,
      sepToken: 2,
      maskToken: 3,
      maskText: '[MASK]',
      configJson: '{}',
      deviceName: 'WebGPU',
    );
  }

  @override
  Future<List<BackendDecisionOutput>> decisionRun(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  ) async {
    calls.add('run $headHandle ${sequences.length}');
    return [
      BackendDecisionOutput(
        logits: Float32List.fromList([0.5]),
        actLogits: Float32List.fromList([1, 0]),
      ),
    ];
  }

  @override
  Future<void> decisionHeadFree(int headHandle) async {
    calls.add('free $headHandle');
  }
}

class _LimitBackend extends _NoStateBackend
    implements BackendGenerationLimitReporting {
  _LimitBackend(this.limits);
  final Map<Stream<List<int>>, BackendGenerationLimit> limits;
  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      limits[generation];
}

class _LimitSupportBackend extends _NoStateBackend
    implements BackendGenerationLimitSupport {
  _LimitSupportBackend(this.generationLimitUnsupportedReason);
  @override
  final String? generationLimitUnsupportedReason;
}
