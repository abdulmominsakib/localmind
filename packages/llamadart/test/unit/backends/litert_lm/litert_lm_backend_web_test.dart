@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/src/backends/litert_lm/litert_lm_backend_web.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  setUp(_clearGlobals);
  tearDown(_clearGlobals);

  test('loads .litertlm URL through preloaded LiteRT-LM Engine', () async {
    JSObject? lastEngineSettings;
    JSObject? lastConversationConfig;
    String? lastPrompt;
    var progress = <double>[];

    _installFakeEngine(
      onCreate: (settings) {
        lastEngineSettings = settings;
      },
      onCreateConversation: (config) {
        lastConversationConfig = config;
      },
      onPrompt: (prompt) {
        lastPrompt = prompt;
      },
      chunks: <JSAny?>[_messageChunk('Hello'), _messageChunk(' world')],
    );

    final backend = LiteRtLmBackend();
    final modelParams = ModelParams(
      contextSize: 2048,
      preferredBackend: GpuBackend.vulkan,
    );
    final modelHandle = await backend.modelLoadFromUrl(
      'https://example.com/gemma-4-E2B-it-web.litertlm?download=1',
      modelParams,
      onProgress: progress.add,
    );
    final contextHandle = await backend.contextCreate(modelHandle, modelParams);

    final settings = lastEngineSettings!;
    expect(
      (settings.getProperty('model'.toJS) as JSString).toDart,
      'https://example.com/gemma-4-E2B-it-web.litertlm?download=1',
    );
    expect((settings.getProperty('backend'.toJS) as JSNumber).toDartInt, 2);
    final executor =
        settings.getProperty('mainExecutorSettings'.toJS) as JSObject;
    expect(
      (executor.getProperty('maxNumTokens'.toJS) as JSNumber).toDartInt,
      2048,
    );
    expect(progress, <double>[0, 1]);
    expect(await backend.getBackendName(), 'LiteRT-LM web gpu');

    final output = await backend
        .generate(
          contextHandle,
          'Say hi',
          const GenerationParams(
            maxTokens: 8,
            temp: 0.2,
            topK: 7,
            topP: 0.5,
            seed: 42,
          ),
        )
        .expand((bytes) => bytes)
        .toList();

    expect(utf8.decode(output), 'Hello world');
    expect(lastPrompt, 'Say hi');

    final conversationConfig = lastConversationConfig!;
    final sessionConfig =
        conversationConfig.getProperty('sessionConfig'.toJS) as JSObject;
    expect(
      (sessionConfig.getProperty('maxOutputTokens'.toJS) as JSNumber).toDartInt,
      8,
    );
    expect(
      (sessionConfig.getProperty('samplerBackend'.toJS) as JSNumber).toDartInt,
      2,
    );
    final sampler = sessionConfig.getProperty('samplerParams'.toJS) as JSObject;
    expect((sampler.getProperty('k'.toJS) as JSNumber).toDartInt, 7);
    expect((sampler.getProperty('p'.toJS) as JSNumber).toDartDouble, 0.5);
    expect(
      (sampler.getProperty('temperature'.toJS) as JSNumber).toDartDouble,
      0.2,
    );
    expect((sampler.getProperty('seed'.toJS) as JSNumber).toDartInt, 42);
  });

  test('loads cached .litertlm URL through CacheStorage Blob', () async {
    const cacheName = 'llamadart-webgpu-model-cache-v1';
    const modelUrl = 'https://example.com/gemma-web.litertlm?download=true';
    final cache = await window.caches.open(cacheName).toDart;
    await cache.put(modelUrl.toJS, Response('cached litert'.toJS)).toDart;
    addTearDown(() async {
      await window.caches.delete(cacheName).toDart;
    });

    JSAny? lastModelSetting;
    _installFakeEngine(
      onCreate: (settings) {
        lastModelSetting = settings.getProperty('model'.toJS);
      },
      chunks: <JSAny?>[_messageChunk('ok')],
    );

    final backend = LiteRtLmBackend();
    final modelHandle = await backend.modelLoadFromUrl(
      modelUrl,
      const ModelParams(),
    );

    expect(lastModelSetting, isNotNull);
    expect(lastModelSetting!.isA<Blob>(), isTrue);
    expect(
      await backend.modelMetadata(modelHandle),
      containsPair('llamadart.litert_lm_web.model_source', 'cache'),
    );
    expect(
      await backend.modelMetadata(modelHandle),
      containsPair('llamadart.litert_lm_web.model_cache_state', 'hit'),
    );
  });

  test('does not use cached Blob for credential-like .litertlm URLs', () async {
    const cacheName = 'llamadart-webgpu-model-cache-v1';
    const modelUrl = 'https://example.com/gemma-web.litertlm?token=secret';
    final cache = await window.caches.open(cacheName).toDart;
    await cache.put(modelUrl.toJS, Response('cached litert'.toJS)).toDart;
    addTearDown(() async {
      await window.caches.delete(cacheName).toDart;
    });

    JSAny? lastModelSetting;
    _installFakeEngine(
      onCreate: (settings) {
        lastModelSetting = settings.getProperty('model'.toJS);
      },
      chunks: <JSAny?>[_messageChunk('ok')],
    );

    final backend = LiteRtLmBackend();
    final modelHandle = await backend.modelLoadFromUrl(
      modelUrl,
      const ModelParams(),
    );

    expect(lastModelSetting, isA<JSString>());
    expect((lastModelSetting as JSString).toDart, modelUrl);
    expect(
      await backend.modelMetadata(modelHandle),
      containsPair('llamadart.litert_lm_web.model_source', 'network'),
    );
    expect(
      await backend.modelMetadata(modelHandle),
      containsPair('llamadart.litert_lm_web.model_cache_state', 'miss'),
    );
  });

  test('setLogLevel updates LiteRT-LM web console log level', () async {
    final backend = LiteRtLmBackend();

    await backend.setLogLevel(LlamaLogLevel.error);

    final raw = globalContext.getProperty<JSAny?>(
      '__llamadartLiteRtLmLogLevel'.toJS,
    );
    expect(raw, isA<JSNumber>());
    expect((raw as JSNumber).toDartInt, LlamaLogLevel.error.index);
  });

  test(
    'exposes single-turn latest-message template for JS conversation runtime',
    () async {
      _installFakeEngine(chunks: <JSAny?>[_messageChunk('ok')]);

      final backend = LiteRtLmBackend();
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      );

      final metadata = await backend.modelMetadata(modelHandle);
      expect(metadata, containsPair('general.architecture', 'litert-lm'));
      expect(metadata, containsPair('general.file_type', 'litertlm'));
      expect(
        metadata,
        containsPair('llamadart.litert_lm_web.chat_scope', 'single-turn-text'),
      );
      expect(
        metadata,
        containsPair('llamadart.litert_lm_web.structured_chat', 'false'),
      );
      expect(metadata, containsPair('general.name', 'model.litertlm'));
      expect(metadata, containsPair('llm.context_length', '4096'));
      expect(
        metadata,
        containsPair(
          'litert_lm.model_url',
          'https://example.com/model.litertlm',
        ),
      );
      final rendered = ChatTemplateEngine.render(
        templateSource: metadata['tokenizer.chat_template'],
        messages: const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.system,
            text: 'Be terse.',
          ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Ignore this older turn.',
          ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: 'Older answer.',
          ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'What is 2+2?',
          ),
        ],
        metadata: metadata,
        addAssistant: true,
      );

      expect(rendered.prompt, 'What is 2+2?');
    },
  );

  test(
    'routes high-level single-turn text through JS conversation runtime',
    () async {
      String? lastPrompt;
      _installFakeEngine(
        chunks: <JSAny?>[_messageChunk('4')],
        onPrompt: (prompt) {
          lastPrompt = prompt;
        },
      );

      final engine = LlamaEngine(LiteRtLmBackend());
      await engine.loadModelFromUrl(
        'https://example.com/gemma-4-E2B-it-web.litertlm',
        modelParams: const ModelParams(
          contextSize: 1024,
          preferredBackend: GpuBackend.vulkan,
        ),
      );

      final chunks = await engine.create(
        const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.system,
            text: 'Answer as JSON.',
          ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'This older user turn is not forwarded by LiteRT-LM web.',
          ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: 'Older assistant turn.',
          ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'What is 2+2?',
          ),
        ],
        params: const GenerationParams(maxTokens: 8, temp: 0, topK: 1, topP: 1),
      ).toList();
      final text = chunks
          .map((chunk) => chunk.choices.first.delta.content ?? '')
          .join();

      expect(text, '4');
      expect(lastPrompt, 'What is 2+2?');
      await engine.dispose();
    },
  );

  test('invalidates stale model and context handles after reload', () async {
    _installFakeEngine(chunks: <JSAny?>[_messageChunk('ok')]);

    final backend = LiteRtLmBackend();
    try {
      final firstModelHandle = await backend.modelLoadFromUrl(
        'https://example.com/first.litertlm',
        const ModelParams(),
      );
      final firstContextHandle = await backend.contextCreate(
        firstModelHandle,
        const ModelParams(),
      );

      final secondModelHandle = await backend.modelLoadFromUrl(
        'https://example.com/second.litertlm',
        const ModelParams(contextSize: 1024),
      );
      final secondContextHandle = await backend.contextCreate(
        secondModelHandle,
        const ModelParams(contextSize: 1024),
      );

      expect(secondModelHandle, isNot(firstModelHandle));
      expect(secondContextHandle, isNot(firstContextHandle));
      await expectLater(
        backend.modelMetadata(firstModelHandle),
        throwsStateError,
      );
      await expectLater(
        backend.getContextSize(firstContextHandle),
        throwsStateError,
      );
      await expectLater(
        backend.contextFree(firstContextHandle),
        throwsStateError,
      );
      await expectLater(backend.modelFree(firstModelHandle), throwsStateError);
      expect(
        await backend.modelMetadata(secondModelHandle),
        containsPair('general.name', 'second.litertlm'),
      );
      expect(await backend.getContextSize(secondContextHandle), 1024);
    } finally {
      await backend.dispose();
    }
  });

  test('rejects speculative decoding on LiteRT-LM web', () async {
    _installFakeEngine(chunks: <JSAny?>[]);

    final backend = LiteRtLmBackend();
    try {
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      );
      final contextHandle = await backend.contextCreate(
        modelHandle,
        const ModelParams(),
      );

      await expectLater(
        backend.generate(
          contextHandle,
          'hello',
          const GenerationParams(speculativeDecoding: true),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('speculativeDecoding'),
          ),
        ),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('rejects presence penalty on LiteRT-LM web', () async {
    _installFakeEngine(chunks: <JSAny?>[]);

    final backend = LiteRtLmBackend();
    try {
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      );
      final contextHandle = await backend.contextCreate(
        modelHandle,
        const ModelParams(),
      );

      await expectLater(
        backend.generate(
          contextHandle,
          'hello',
          const GenerationParams(presencePenalty: 1.5),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('presencePenalty'),
          ),
        ),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('rejects thinking budget on LiteRT-LM web', () async {
    _installFakeEngine(chunks: <JSAny?>[]);

    final backend = LiteRtLmBackend();
    try {
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      );
      final contextHandle = await backend.contextCreate(
        modelHandle,
        const ModelParams(),
      );

      await expectLater(
        backend.generate(
          contextHandle,
          'hello',
          const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 16)),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('thinkingBudget'),
          ),
        ),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('rejects speculative decoding config on LiteRT-LM web', () async {
    _installFakeEngine(chunks: <JSAny?>[]);

    final backend = LiteRtLmBackend();
    try {
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      );
      final contextHandle = await backend.contextCreate(
        modelHandle,
        const ModelParams(),
      );

      await expectLater(
        backend.generate(
          contextHandle,
          'hello',
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
          ),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('speculativeDecodingConfig'),
          ),
        ),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('rejects unsupported context-time model params', () async {
    _installFakeEngine(chunks: <JSAny?>[]);

    final backend = LiteRtLmBackend();
    try {
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      );

      await expectLater(
        () => backend.contextCreate(
          modelHandle,
          const ModelParams(batchSize: 128),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains('batchSize'),
          ),
        ),
      );

      await expectLater(
        () => backend.contextCreate(
          modelHandle,
          const ModelParams(
            liteRtLmActivationDataType: LiteRtLmActivationDataType.float16,
            liteRtLmPrefillChunkSize: 128,
            liteRtLmParallelFileSectionLoading: false,
            liteRtLmDispatchLibDir: '/vendor/litert',
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('native'),
              contains('liteRtLmActivationDataType'),
              contains('liteRtLmPrefillChunkSize'),
              contains('liteRtLmParallelFileSectionLoading'),
              contains('liteRtLmDispatchLibDir'),
            ),
          ),
        ),
      );

      await expectLater(
        () => backend.contextCreate(
          modelHandle,
          const ModelParams(contextSize: 0),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains('contextSize=0'),
          ),
        ),
      );

      await expectLater(
        () => backend.contextCreate(
          modelHandle,
          const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.npu),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('NPU backend'),
          ),
        ),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('rejects media content in direct chat-template calls', () async {
    _installFakeEngine(chunks: <JSAny?>[_messageChunk('ok')]);

    final backend = LiteRtLmBackend();
    try {
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      );

      expect(
        await backend.applyChatTemplate(
          modelHandle,
          const <Map<String, dynamic>>[
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'hello'},
                {'type': 'text', 'text': ' world'},
              ],
            },
          ],
          addAssistant: false,
        ),
        'hello world',
      );
      await expectLater(
        backend.applyChatTemplate(modelHandle, const <Map<String, dynamic>>[
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'https://example.com/cat.png'},
              },
            ],
          },
        ]),
        throwsUnsupportedError,
      );
    } finally {
      await backend.dispose();
    }
  });

  test('reports zero VRAM without requiring web runtime', () async {
    final backend = LiteRtLmBackend(readyTimeout: Duration.zero);

    expect(await backend.getVramInfo(), (total: 0, free: 0));
  });

  test('validates LoRA context handles before unsupported errors', () async {
    _installFakeEngine(chunks: <JSAny?>[_messageChunk('ok')]);

    final backend = LiteRtLmBackend();
    try {
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      );

      expect(
        () => backend.setLoraAdapter(123, 'adapter.lora', 1),
        throwsStateError,
      );
      final contextHandle = await backend.contextCreate(
        modelHandle,
        const ModelParams(),
      );
      expect(
        () => backend.setLoraAdapter(contextHandle, 'adapter.lora', 1),
        throwsUnsupportedError,
      );
      expect(
        () => backend.removeLoraAdapter(contextHandle, 'adapter.lora'),
        throwsUnsupportedError,
      );
      expect(
        () => backend.clearLoraAdapters(contextHandle),
        throwsUnsupportedError,
      );

      await backend.contextFree(contextHandle);
      expect(() => backend.clearLoraAdapters(contextHandle), throwsStateError);
    } finally {
      await backend.dispose();
    }
  });

  test('rejects unsupported multimodal operations consistently', () async {
    _installFakeEngine(chunks: <JSAny?>[_messageChunk('ok')]);

    final backend = LiteRtLmBackend();
    final modelHandle = await backend.modelLoadFromUrl(
      'https://example.com/model.litertlm',
      const ModelParams(),
    );

    expect(
      () => backend.multimodalContextCreate(modelHandle, 'mmproj.gguf'),
      throwsUnsupportedError,
    );
    expect(() => backend.multimodalContextFree(1), throwsUnsupportedError);
    expect(() => backend.supportsVision(1), throwsUnsupportedError);
    expect(() => backend.supportsAudio(1), throwsUnsupportedError);
  });

  test('loads LiteRT-LM Engine from module URL', () async {
    final moduleUrl =
        'data:text/javascript;charset=utf-8,${Uri.encodeComponent('''
      export const Backend = { CPU: 3, GPU_ARTISAN: 2, GPU: 4 };
      export const Engine = {
        async create(settings) {
          globalThis.__llamadartLiteRtLmModuleSettings = {
            model: settings.model,
            backend: settings.backend,
            maxNumTokens: settings.mainExecutorSettings?.maxNumTokens,
          };
          if (settings.backend !== 2) {
            throw new Error(`Unexpected backend: \${settings.backend}`);
          }
          return {
            async createConversation(config) {
              globalThis.__llamadartLiteRtLmModuleConversationConfig = config;
              return {
                sendMessageStreaming(prompt) {
                  globalThis.__llamadartLiteRtLmModulePrompt = prompt;
                  let sent = false;
                  return new ReadableStream({
                    pull(controller) {
                      if (sent) {
                        controller.close();
                        return;
                      }
                      sent = true;
                      controller.enqueue({
                        content: [{ type: 'text', text: 'Module ok' }],
                      });
                    },
                  });
                },
                cancel() {},
                async delete() {},
              };
            },
            async delete() {},
          };
        },
      };
    ''')}';

    final backend = LiteRtLmBackend(moduleUrl: moduleUrl);
    final modelHandle = await backend.modelLoadFromUrl(
      'https://example.com/module-model.litertlm',
      const ModelParams(contextSize: 1024, preferredBackend: GpuBackend.vulkan),
    );
    final contextHandle = await backend.contextCreate(
      modelHandle,
      const ModelParams(contextSize: 1024, preferredBackend: GpuBackend.vulkan),
    );

    final output = await backend
        .generate(
          contextHandle,
          'Module prompt',
          const GenerationParams(maxTokens: 8),
        )
        .expand((bytes) => bytes)
        .toList();

    expect(utf8.decode(output), 'Module ok');
    final settings =
        globalContext.getProperty('__llamadartLiteRtLmModuleSettings'.toJS)
            as JSObject;
    expect(
      (settings.getProperty('model'.toJS) as JSString).toDart,
      'https://example.com/module-model.litertlm',
    );
    expect((settings.getProperty('backend'.toJS) as JSNumber).toDartInt, 2);
    expect(
      (settings.getProperty('maxNumTokens'.toJS) as JSNumber).toDartInt,
      1024,
    );
    expect(
      (globalContext.getProperty('__llamadartLiteRtLmModulePrompt'.toJS)
              as JSString)
          .toDart,
      'Module prompt',
    );
  });

  test('applies stop sequences and cancels active conversation', () async {
    var cancelCalls = 0;
    var readerCancelCalls = 0;
    _installFakeEngine(
      chunks: <JSAny?>[_messageChunk('Hello ST'), _messageChunk('OP hidden')],
      onCancel: () {
        cancelCalls += 1;
      },
      onReaderCancel: () {
        readerCancelCalls += 1;
      },
    );

    final backend = LiteRtLmBackend();
    const params = ModelParams();
    await backend.modelLoadFromUrl(
      'https://example.com/model.litertlm',
      params,
    );
    await backend.contextCreate(1, params);

    final output = await backend
        .generate(
          1,
          'prompt',
          const GenerationParams(maxTokens: 16, stopSequences: ['STOP']),
        )
        .expand((bytes) => bytes)
        .toList();

    expect(utf8.decode(output), 'Hello ');
    expect(cancelCalls, 1);
    expect(readerCancelCalls, 1);
  });

  test('reports missing web runtime with actionable setup error', () async {
    final backend = LiteRtLmBackend(readyTimeout: Duration.zero);

    await expectLater(
      () => backend.modelLoadFromUrl(
        'https://example.com/model.litertlm',
        const ModelParams(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('__llamadartLiteRtLmModuleUrl'),
        ),
      ),
    );
  });

  test('rejects non-LiteRT model sources before loading runtime', () async {
    final backend = LiteRtLmBackend(readyTimeout: Duration.zero);

    await expectLater(
      () => backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}

typedef _CreateHook = void Function(JSObject settings);
typedef _ConversationHook = void Function(JSObject config);
typedef _PromptHook = void Function(String prompt);

void _installFakeEngine({
  _CreateHook? onCreate,
  _ConversationHook? onCreateConversation,
  _PromptHook? onPrompt,
  void Function()? onCancel,
  void Function()? onReaderCancel,
  required List<JSAny?> chunks,
}) {
  final engineClass = JSObject();
  engineClass.setProperty(
    'create'.toJS,
    ((JSObject settings) {
      onCreate?.call(settings);
      final engine = JSObject();
      engine.setProperty(
        'createConversation'.toJS,
        ((JSObject config) {
          onCreateConversation?.call(config);
          return Future<JSObject>.value(
            _fakeConversation(
              chunks: chunks,
              onPrompt: onPrompt,
              onCancel: onCancel,
              onReaderCancel: onReaderCancel,
            ),
          ).toJS;
        }).toJS,
      );
      engine.setProperty(
        'delete'.toJS,
        (() => Future<JSAny?>.value(null).toJS).toJS,
      );
      return Future<JSObject>.value(engine).toJS;
    }).toJS,
  );
  globalContext.setProperty('LiteRtLmEngine'.toJS, engineClass);
}

JSObject _fakeConversation({
  required List<JSAny?> chunks,
  _PromptHook? onPrompt,
  void Function()? onCancel,
  void Function()? onReaderCancel,
}) {
  final conversation = JSObject();
  conversation.setProperty(
    'sendMessageStreaming'.toJS,
    ((String prompt) {
      onPrompt?.call(prompt);
      return _fakeReadableStream(chunks, onReaderCancel: onReaderCancel);
    }).toJS,
  );
  conversation.setProperty(
    'cancel'.toJS,
    (() {
      onCancel?.call();
    }).toJS,
  );
  conversation.setProperty(
    'delete'.toJS,
    (() => Future<JSAny?>.value(null).toJS).toJS,
  );
  return conversation;
}

JSObject _fakeReadableStream(
  List<JSAny?> chunks, {
  void Function()? onReaderCancel,
}) {
  final stream = JSObject();
  stream.setProperty(
    'getReader'.toJS,
    (() {
      var index = 0;
      final reader = JSObject();
      reader.setProperty(
        'read'.toJS,
        (() {
          final result = JSObject();
          if (index >= chunks.length) {
            result.setProperty('done'.toJS, true.toJS);
            return Future<JSObject>.value(result).toJS;
          }
          result.setProperty('done'.toJS, false.toJS);
          final value = chunks[index];
          index += 1;
          if (value != null) {
            result.setProperty('value'.toJS, value);
          }
          return Future<JSObject>.value(result).toJS;
        }).toJS,
      );
      reader.setProperty(
        'cancel'.toJS,
        (() {
          onReaderCancel?.call();
          return Future<JSAny?>.value(null).toJS;
        }).toJS,
      );
      reader.setProperty('releaseLock'.toJS, (() {}).toJS);
      return reader;
    }).toJS,
  );
  return stream;
}

JSObject _messageChunk(String text) {
  final chunk = JSObject();
  final content = JSArray();
  final item = JSObject();
  item.setProperty('type'.toJS, 'text'.toJS);
  item.setProperty('text'.toJS, text.toJS);
  content.setProperty(0.toJS, item);
  chunk.setProperty('content'.toJS, content);
  return chunk;
}

void _clearGlobals() {
  globalContext.delete('LiteRtLmEngine'.toJS);
  globalContext.delete('LiteRtLmBackendEnum'.toJS);
  globalContext.delete('__llamadartLiteRtLmModule'.toJS);
  globalContext.delete('__llamadartLiteRtLmModuleUrl'.toJS);
  globalContext.delete('__llamadartLiteRtLmModuleSettings'.toJS);
  globalContext.delete('__llamadartLiteRtLmModuleConversationConfig'.toJS);
  globalContext.delete('__llamadartLiteRtLmModulePrompt'.toJS);
  globalContext.delete('__llamadartLiteRtLmLogLevel'.toJS);
  globalContext.delete('__llamadartInstallLiteRtLmConsoleGuard'.toJS);
}
