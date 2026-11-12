@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dinja/dinja.dart';
import 'package:llamadart/llamadart.dart' as api;
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_bundle_template.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_cache.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_templates.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_gpu_adapter.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_platform.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/core/engine/chat_template_renderer.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/config/compute_device.dart';
import 'package:llamadart/src/core/models/config/flash_attention.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/kv_cache_type.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/config/lora_config.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:test/test.dart';

import '../../../support/litert_lm_content_templates.dart';
import '../../../support/litert_lm_gpu_caches.dart';
import '../../../support/read_only_directory.dart';
import '../../../support/suite_system_temp.dart';

void main() {
  final suiteTemp = useSuiteSystemTemp();
  late Directory tempDir;
  late File modelFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'llamadart_litert_service_test_',
    );
    modelFile = File('${tempDir.path}/model.litertlm');
    await modelFile.writeAsString('fake model');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('native JSON Schema admission', () {
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);
    late _FakeLiteRtLmRuntimeClient client;
    late LiteRtLmService service;
    setUp(() async {
      client = _FakeLiteRtLmRuntimeClient()
        ..jsonSchemaSupport = true
        ..finishReason = LiteRtLmFinishReason.stop;
      service = LiteRtLmService(
        clientFactory: () => client,
        jsonSchemaQualifiedBackends: () => {'cpu', 'gpu'},
      );
      await service.loadModel(
        (await modelFile.copy('${tempDir.path}/Qwen3-0.6B.litertlm')).path,
        params,
      );
    });
    tearDown(() async {
      final unused = client.generateCount == 0
          ? client.generated.stream.drain<void>()
          : null;
      await client.generated.close();
      await unused;
      service.dispose();
    });
    test(
      'constructs a model provider before admitting and sends a per-request schema',
      () async {
        final context = service.createContext(1, params);
        await service.prepareJsonSchemaChat();
        expect(client.lastJsonSchemaConfig, isTrue);
        final stream = service
            .generateJsonSchemaChat(
              context,
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'p'),
              ],
              const GenerationParams(),
              jsonSchema: '{"type":"object"}',
            )
            .toList();
        await client.generateStarted.future;
        expect(client.lastJsonSchemaConfig, isTrue);
        expect(client.lastJsonSchema, '{"type":"object"}');
        client.generated.add('{}');
        await client.generated.close();
        expect(await stream, [utf8.encode('{}')]);
      },
    );
    final hostHasGpu = liteRtLmAvailableNativeBackendsForCurrentPlatform()
        .contains('gpu');
    test(
      'admits the GPU delegate',
      skip: hostHasGpu
          ? null
          : 'needs a host with a LiteRT-LM GPU backend to select the delegate',
      () async {
        service.dispose();
        service = LiteRtLmService(
          clientFactory: () => client,
          jsonSchemaQualifiedBackends: () => {'cpu', 'gpu'},
        );
        await service.loadModel(
          '${tempDir.path}/Qwen3-0.6B.litertlm',
          const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
        );
        await service.prepareJsonSchemaChat();
        expect(client.lastBackend, 'gpu');
        expect(client.lastJsonSchemaConfig, isTrue);
      },
    );
    for (final excluded in ['host', 'family', 'template']) {
      test('rejects unqualified $excluded before native admission', () async {
        service.dispose();
        service = LiteRtLmService(
          clientFactory: () => client,
          jsonSchemaQualifiedBackends: () =>
              excluded == 'host' ? const {} : {'cpu', 'gpu'},
        );
        final selected = excluded == 'template'
            ? const ModelParams(
                liteRtLmBackend: LiteRtLmBackendPreference.cpu,
                chatTemplate: '{{ messages }}',
              )
            : params;
        await service.loadModel(
          excluded == 'family'
              ? modelFile.path
              : '${tempDir.path}/Qwen3-0.6B.litertlm',
          selected,
        );
        await expectLater(
          service.prepareJsonSchemaChat(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(client.createConversationCount, 0);
        expect(client.generateCount, 0);
      });
    }
    group('default qualification table', () {
      tearDown(() => debugLiteRtLmAbiOverride = null);
      const hardwareGpu = LiteRtLmVulkanAdapters.devices([
        LiteRtLmVulkanAdapter(name: 'GPU', deviceType: 2),
      ]);
      LiteRtLmService tableService({
        LiteRtLmVulkanAdapters adapters = hardwareGpu,
        Set<String> Function()? qualified,
      }) => LiteRtLmService(
        clientFactory: () => client,
        probeGpuAdapters: () => adapters,
        jsonSchemaQualifiedBackends: qualified,
      );
      Future<void> expectRefused(
        String backend, {
        bool beforeEngine = true,
      }) async {
        await expectLater(
          service.prepareJsonSchemaChat(),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              contains('not qualified for the LiteRT-LM $backend'),
            ),
          ),
        );
        expect(client.createConversationCount, 0);
        if (beforeEngine) expect(client.lastBackend, isNull);
      }

      const expected = <Abi, Set<String>>{
        Abi.macosArm64: {'cpu', 'gpu'},
        Abi.iosArm64: {'cpu', 'gpu'},
        Abi.androidArm64: {'cpu'},
        Abi.androidX64: {},
        Abi.linuxX64: {'cpu'},
        Abi.linuxArm64: {'cpu'},
        Abi.windowsX64: {'cpu'},
        Abi.macosX64: {},
      };
      for (final MapEntry(key: abi, value: backends) in expected.entries) {
        for (final backend in ['cpu', 'gpu']) {
          final admitted = backends.contains(backend);
          test(
            '${admitted ? 'admits' : 'refuses'} $backend on $abi',
            skip: backend == 'gpu' && !hostHasGpu
                ? 'needs a host with a LiteRT-LM GPU backend'
                : null,
            () async {
              service.dispose();
              service = tableService();
              await service.loadModel(
                '${tempDir.path}/Qwen3-0.6B.litertlm',
                backend == 'cpu'
                    ? params
                    : const ModelParams(
                        liteRtLmBackend: LiteRtLmBackendPreference.gpu,
                      ),
              );
              debugLiteRtLmAbiOverride = abi;
              if (admitted) {
                await service.prepareJsonSchemaChat();
                expect(client.lastBackend, backend);
                expect(client.lastJsonSchemaConfig, isTrue);
              } else {
                await expectRefused(backend);
              }
            },
          );
        }
      }
      for (final abi in [Abi.linuxX64, Abi.windowsX64, Abi.androidArm64]) {
        test(
          'refuses the deprecated gpu backend override on $abi',
          skip: hostHasGpu ? null : 'needs a host with a LiteRT-LM GPU backend',
          () async {
            service.dispose();
            service = tableService();
            await service.loadModel(
              '${tempDir.path}/Qwen3-0.6B.litertlm',
              const ModelParams(),
              backendOverride: 'gpu',
            );
            debugLiteRtLmAbiOverride = abi;
            await expectRefused('gpu');
          },
        );
      }
      test(
        'refuses an automatic GPU load that runs on an unqualified CPU',
        skip: liteRtLmDefaultNativeBackendForCurrentPlatform() == 'gpu'
            ? null
            : 'needs a host whose automatic LiteRT-LM backend is the GPU',
        () async {
          service.dispose();
          service = tableService(
            adapters: const LiteRtLmVulkanAdapters.devices([
              LiteRtLmVulkanAdapter(
                name: 'llvmpipe',
                deviceType: vulkanPhysicalDeviceTypeCpu,
              ),
            ]),
            qualified: () => {'gpu'},
          );
          await service.loadModel(
            '${tempDir.path}/Qwen3-0.6B.litertlm',
            const ModelParams(),
          );
          await expectRefused('cpu', beforeEngine: false);
          expect(client.lastBackend, 'cpu');
        },
      );
      test('a reload repeats admission', () async {
        service.dispose();
        service = tableService();
        final model = '${tempDir.path}/Qwen3-0.6B.litertlm';
        await service.loadModel(model, params);
        debugLiteRtLmAbiOverride = Abi.linuxX64;
        await service.prepareJsonSchemaChat();
        await service.loadModel(model, params);
        debugLiteRtLmAbiOverride = Abi.macosX64;
        client.createConversationCount = 0;
        await expectRefused('cpu', beforeEngine: false);
      });
    });
    test('missing optional API never admits or starts generation', () async {
      client.jsonSchemaSupport = false;
      await expectLater(
        service.prepareJsonSchemaChat(),
        throwsA(
          isA<LlamaUnsupportedException>()
              .having(
                (error) => error.message,
                'current runtime',
                contains('packaged LiteRT-LM $liteRtLmReleaseTag runtime'),
              )
              .having(
                (error) => error.message,
                'ABI selection',
                contains('default ABI-selecting client'),
              )
              .having(
                (error) => error.message,
                'qualification limits',
                contains('model and platform qualification still applies'),
              ),
        ),
      );
      expect(client.generateCount, 0);
      expect(client.createConversationCount, 0);
    });
    for (final nativeError in <(String, Object Function(String))>[
      ('legacy', StateError.new),
      ('v1', LlamaModelException.new),
    ]) {
      test(
        '${nativeError.$1} provider failure cannot be treated as support',
        () async {
          final context = service.createContext(1, params);
          client.onCreateConversation = () =>
              throw nativeError.$2('/private/model-secret invalid EOS');
          await expectLater(
            service.prepareJsonSchemaChat(),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (e) => e.message,
                'redacted native diagnostic',
                isNot(contains('model-secret')),
              ),
            ),
          );
          expect(client.generateCount, 0);
          client.onCreateConversation = null;
          await service.prepareJsonSchemaChat();
          expect(client.lastJsonSchemaConfig, isTrue);
          client.onCreateConversation = () =>
              throw nativeError.$2('/private/model-secret schema-secret');
          await expectLater(
            service
                .generateJsonSchemaChat(
                  context,
                  const [
                    LlamaChatMessage.fromText(
                      role: LlamaChatRole.user,
                      text: 'p',
                    ),
                  ],
                  const GenerationParams(),
                  jsonSchema: '{"type":"object"}',
                )
                .toList(),
            throwsA(
              isA<LlamaInferenceException>().having(
                (e) => e.message,
                'redacted schema diagnostic',
                isNot(contains('secret')),
              ),
            ),
          );
        },
      );
    }
  });

  group('native JSON Schema families, thinking and finish', () {
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);
    const user = [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'p'),
    ];
    late _FakeLiteRtLmRuntimeClient client;
    late LiteRtLmService service;
    Future<int> load(
      String name, {
      ModelParams modelParams = params,
      bool reasoningChannel = true,
    }) async {
      client = _FakeLiteRtLmRuntimeClient()
        ..jsonSchemaSupport = true
        ..jsonSchemaThinking = true
        ..finishReason = LiteRtLmFinishReason.stop;
      service = LiteRtLmService(
        clientFactory: () => client,
        jsonSchemaQualifiedBackends: () => {'cpu', 'gpu'},
        readBundleFirstChannel: (_) =>
            reasoningChannel ? (name: 'thought', isReasoning: true) : null,
      );
      await service.loadModel(
        (await modelFile.copy('${tempDir.path}/$name')).path,
        modelParams,
      );
      return service.createContext(1, modelParams);
    }

    Future<List<List<int>>> generate(
      int context, {
      bool enableThinking = false,
      void Function()? whileRunning,
    }) async {
      final stream = service
          .generateJsonSchemaChat(
            context,
            user,
            const GenerationParams(),
            jsonSchema: '{"type":"object"}',
            enableThinking: enableThinking,
          )
          .toList();
      // The failure cases complete the stream before the caller awaits it.
      stream.ignore();
      await client.generateStarted.future;
      whileRunning?.call();
      await client.generated.close();
      return stream;
    }

    tearDown(() async {
      if (!client.generated.isClosed) {
        final unused = client.generateCount == 0
            ? client.generated.stream.drain<void>()
            : null;
        await client.generated.close();
        await unused;
      }
      service.dispose();
    });

    test('Gemma 4 renders its bundle template and may think', () async {
      final context = await load('gemma-4-E2B-it.litertlm');
      await service.prepareJsonSchemaChat();
      expect(client.lastPromptTemplate, isNull);
      expect(client.lastJsonSchemaConfig, isTrue);
      expect(service.supportsJsonSchemaChatThinking, isTrue);
      await generate(
        context,
        enableThinking: true,
        whileRunning: () => client.generated.add('{}'),
      );
      expect(client.lastJsonSchema, '{"type":"object"}');
      expect(client.lastExtraContext?['enable_thinking'], isTrue);
    });

    test('Gemma 4 thinking is re-admitted after an image turn recreates the '
        'client', () async {
      final context = await load('gemma-4-E2B-it.litertlm');
      await service.prepareJsonSchemaChat();
      _FakeLiteRtLmRuntimeClient fresh() =>
          client = _FakeLiteRtLmRuntimeClient()
            ..jsonSchemaSupport = true
            ..jsonSchemaThinking = true
            ..finishReason = LiteRtLmFinishReason.stop;
      final imageClient = fresh();
      final image = service.generateChat(context, [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            const LlamaTextContent('Describe'),
            LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
          ],
        ),
      ], const GenerationParams(maxTokens: 8)).toList();
      await imageClient.generateStarted.future;
      imageClient.generated.add('A');
      await imageClient.generated.close();
      await image;
      expect(service.supportsJsonSchemaChatThinking, isFalse);
      fresh();
      await generate(
        context,
        enableThinking: true,
        whileRunning: () => client.generated.add('{}'),
      );
      expect(service.supportsJsonSchemaChatThinking, isTrue);
      expect(client.lastExtraContext?['enable_thinking'], isTrue);
    });

    test('maxTokens 0 ignores a stale finish reason', () async {
      final context = await load('gemma-4-E2B-it.litertlm');
      await service.prepareJsonSchemaChat();
      client.finishReason = LiteRtLmFinishReason.unknown;
      expect(
        await service
            .generateJsonSchemaChat(
              context,
              user,
              const GenerationParams(maxTokens: 0),
              jsonSchema: '{"type":"object"}',
            )
            .toList(),
        isEmpty,
      );
      expect(client.generateCount, 0);
    });

    test('Gemma 4 thinking needs a declared reasoning channel', () async {
      final context = await load(
        'gemma-4-E2B-it.litertlm',
        reasoningChannel: false,
      );
      await service.prepareJsonSchemaChat();
      expect(service.supportsJsonSchemaChatThinking, isFalse);
      await expectLater(
        service
            .generateJsonSchemaChat(
              context,
              user,
              const GenerationParams(),
              jsonSchema: '{"type":"object"}',
              enableThinking: true,
            )
            .toList(),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(client.generateCount, 0);
    });

    test('a runtime that forces thinking off cannot think', () async {
      await load('gemma-4-E2B-it.litertlm');
      client.jsonSchemaThinking = false;
      await service.prepareJsonSchemaChat();
      expect(service.supportsJsonSchemaChatThinking, isFalse);
    });

    test('Qwen3 is admitted without thinking', () async {
      final context = await load('Qwen3-0.6B.litertlm');
      await service.prepareJsonSchemaChat();
      expect(client.lastPromptTemplate, isNotNull);
      expect(service.supportsJsonSchemaChatThinking, isFalse);
      await expectLater(
        service
            .generateJsonSchemaChat(
              context,
              user,
              const GenerationParams(),
              jsonSchema: '{"type":"object"}',
              enableThinking: true,
            )
            .toList(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            contains('Gemma 4'),
          ),
        ),
      );
      expect(client.generateCount, 0);
    });

    for (final name in ['gemma-4-E2B-it.litertlm', 'gemma-3n-E2B.litertlm']) {
      test('refuses $name with an unqualified template', () async {
        await load(
          name,
          modelParams: name.startsWith('gemma-4')
              ? const ModelParams(
                  liteRtLmBackend: LiteRtLmBackendPreference.cpu,
                  chatTemplate: '{{ messages }}',
                )
              : params,
        );
        await expectLater(
          service.prepareJsonSchemaChat(),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              contains('Gemma 4 with its bundle template'),
            ),
          ),
        );
        expect(client.createConversationCount, 0);
      });
    }

    test('refuses a runtime without finish reasons', () async {
      await load('Qwen3-0.6B.litertlm');
      client.finishReasons = false;
      await expectLater(
        service.prepareJsonSchemaChat(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            contains('reports length instead of success'),
          ),
        ),
      );
      expect(client.createConversationCount, 0);
    });

    test('a reply cut off at maxTokens reports the token limit', () async {
      final context = await load('Qwen3-0.6B.litertlm');
      client.finishReason = LiteRtLmFinishReason.length;
      expect(
        await generate(
          context,
          whileRunning: () => client.generated.add('{"v": "ab'),
        ),
        [utf8.encode('{"v": "ab')],
      );
      expect(service.lastGenerationLimit, BackendGenerationLimit.maxTokens);
    });

    for (final reason in [
      LiteRtLmFinishReason.unknown,
      LiteRtLmFinishReason.error,
      null,
    ]) {
      test('an unclassified $reason finish is never success', () async {
        final context = await load('Qwen3-0.6B.litertlm');
        client.finishReason = reason;
        await expectLater(
          generate(context, whileRunning: () => client.generated.add('{')),
          throwsA(
            isA<LlamaInferenceException>().having(
              (e) => e.message,
              'message',
              contains('may be incomplete'),
            ),
          ),
        );
      });
    }

    for (final (status, expected) in [
      ('INTERNAL (13)', isA<LlamaUnsupportedException>()),
      ('INVALID_ARGUMENT (3)', isA<LlamaInferenceException>()),
    ]) {
      test('a send failure with $status before output is typed', () async {
        final context = await load('Qwen3-0.6B.litertlm');
        await expectLater(
          generate(
            context,
            whileRunning: () => client.generated.addError(
              LiteRtLmSendFailureException(
                'conversation_send_message_stream failed: LiteRT-LM '
                'reported $status: Failed to create LLGuidance constraint: '
                'secret-schema',
              ),
            ),
          ),
          throwsA(
            allOf(
              expected,
              isA<LlamaException>().having(
                (e) => e.message,
                'message',
                isNot(contains('secret-schema')),
              ),
            ),
          ),
        );
      });
    }

    test('an INTERNAL failure after output is an inference failure', () async {
      final context = await load('Qwen3-0.6B.litertlm');
      await expectLater(
        generate(
          context,
          whileRunning: () => client.generated
            ..add('{')
            ..addError(LlamaModelException('INTERNAL (13)')),
        ),
        throwsA(isA<LlamaInferenceException>()),
      );
    });
  });

  group('bundleCapabilities', () {
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);
    late ({bool vision, bool audio, bool speculativeDecoding})? declared;
    late Object? readError;
    late List<String> readPaths;

    setUp(() {
      declared = null;
      readError = null;
      readPaths = <String>[];
    });

    LiteRtLmService newService(_FakeLiteRtLmRuntimeClient client) =>
        LiteRtLmService(
          clientFactory: () => client,
          readBundleCapabilities: (modelPath) {
            readPaths.add(modelPath);
            if (readError case final error?) throw error;
            return declared;
          },
        );

    test(
      'reports the declaration of the loaded bundle once per load',
      () async {
        final service = newService(_FakeLiteRtLmRuntimeClient());
        declared = (vision: true, audio: false, speculativeDecoding: true);
        try {
          expect(service.bundleCapabilities(), isNull);
          expect(readPaths, isEmpty);

          final model = await service.loadModel(modelFile.path, params);
          expect(service.bundleCapabilities(), declared);
          expect(service.bundleCapabilities(), declared);
          expect(readPaths, hasLength(1));
          expect(
            File(readPaths.single).resolveSymbolicLinksSync(),
            modelFile.resolveSymbolicLinksSync(),
          );

          declared = (vision: true, audio: true, speculativeDecoding: false);
          await service.loadModel(modelFile.path, params);
          expect(service.bundleCapabilities(), declared);
          expect(readPaths, hasLength(2));

          service.freeModel(model + 1);
          expect(service.bundleCapabilities(), isNull);
          expect(readPaths, hasLength(2));
        } finally {
          service.dispose();
        }
      },
    );

    test('reports nothing when the runtime cannot tell', () async {
      final service = newService(_FakeLiteRtLmRuntimeClient());
      readError = UnsupportedError('missing symbol');
      try {
        await service.loadModel(modelFile.path, params);
        expect(service.bundleCapabilities(), isNull);
        expect(service.bundleCapabilities(), isNull);
        expect(readPaths, hasLength(1));
      } finally {
        service.dispose();
      }
    });

    Future<List<List<int>>> mediaChat(
      LiteRtLmService service,
      int context,
      LlamaContentPart media,
    ) => service.generateChat(context, [
      LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [const LlamaTextContent('Describe'), media],
      ),
    ], const GenerationParams(maxTokens: 8)).toList();

    Future<void> answer(_FakeLiteRtLmRuntimeClient client) async {
      await client.generateStarted.future;
      client.generated.add('A');
      await client.generated.close();
    }

    Matcher undeclared(String piece) => throwsA(
      isA<UnsupportedError>().having(
        (error) => '${error.message}',
        'message',
        allOf(
          contains('declares no $piece'),
          contains('Runtime error: Bad state: runtime failed'),
        ),
      ),
    );
    final rethrowsRuntimeError = throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'runtime failed',
      ),
    );

    for (final (kind, piece) in [
      ('image', 'image encoder'),
      ('audio', 'audio encoder'),
    ]) {
      LlamaContentPart mediaPart() => kind == 'image'
          ? LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3]))
          : LlamaAudioContent(bytes: Uint8List.fromList([4, 5, 6]));

      for (final declaredPresent in <bool?>[true, false, null]) {
        ({bool vision, bool audio, bool speculativeDecoding})? declaration() =>
            declaredPresent == null
            ? null
            : (
                vision: kind == 'image' ? declaredPresent : true,
                audio: kind == 'audio' ? declaredPresent : true,
                speculativeDecoding: true,
              );

        test('$kind input runs whatever the bundle declares '
            '($declaredPresent)', () async {
          final client = _FakeLiteRtLmRuntimeClient();
          final service = newService(client);
          declared = declaration();
          try {
            final model = await service.loadModel(modelFile.path, params);
            final context = service.createContext(model, params);
            final pending = mediaChat(service, context, mediaPart());
            await answer(client);
            expect(await pending, [utf8.encode('A')]);
          } finally {
            service.dispose();
          }
        });

        test('a runtime failure on $kind input is explained only when the '
            'bundle declares no $piece ($declaredPresent)', () async {
          final client = _FakeLiteRtLmRuntimeClient()
            ..onCreateConversation = () => throw StateError('runtime failed');
          final service = newService(client);
          declared = declaration();
          try {
            final model = await service.loadModel(modelFile.path, params);
            final context = service.createContext(model, params);
            await expectLater(
              mediaChat(service, context, mediaPart()),
              declaredPresent == false
                  ? undeclared(piece)
                  : rethrowsRuntimeError,
            );
          } finally {
            service.dispose();
          }
        });
      }
    }

    test('a failure after output started is never explained', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = newService(client);
      declared = (vision: false, audio: false, speculativeDecoding: false);
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);
        final pending = mediaChat(
          service,
          context,
          LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
        );
        final failed = expectLater(pending, rethrowsRuntimeError);
        await client.generateStarted.future;
        client.generated
          ..add('A')
          ..addError(StateError('runtime failed'));
        await client.generated.close();
        await failed;
      } finally {
        service.dispose();
      }
    });

    for (final declaredDrafter in <bool?>[true, false, null]) {
      test('speculative decoding on a bundle declaring a drafter '
          '$declaredDrafter runs, and a runtime failure is explained only '
          'when it declares none', () async {
        for (final fails in [false, true]) {
          final client = _FakeLiteRtLmRuntimeClient(
            initializeError: fails ? StateError('runtime failed') : null,
          );
          final service = newService(client);
          declared = declaredDrafter == null
              ? null
              : (
                  vision: false,
                  audio: false,
                  speculativeDecoding: declaredDrafter,
                );
          try {
            final model = await service.loadModel(modelFile.path, params);
            final context = service.createContext(model, params);
            final pending = service
                .generate(
                  context,
                  'Hello',
                  const GenerationParams(
                    maxTokens: 8,
                    speculativeDecoding: true,
                  ),
                )
                .toList();
            if (!fails) {
              await answer(client);
              await pending;
              expect(client.lastSpeculativeDecoding, isTrue);
              continue;
            }
            await expectLater(
              pending,
              declaredDrafter == false
                  ? undeclared('speculative decoding drafter')
                  : rethrowsRuntimeError,
            );
          } finally {
            service.dispose();
          }
        }
      });
    }

    for (final (name, media, passedThrough) in [
      (
        'an unsupported raw RGB image',
        LlamaImageContent(
          bytes: Uint8List.fromList([1, 2, 3]),
          width: 1,
          height: 1,
        ),
        isA<UnsupportedError>().having(
          (error) => '${error.message}',
          'message',
          allOf(contains('raw RGB'), isNot(contains('declares no'))),
        ),
      ),
      (
        'a missing image file',
        const LlamaImageContent(path: '/missing/llamadart-image.png'),
        isA<ArgumentError>().having(
          (error) => '${error.message}',
          'message',
          contains('image file does not exist'),
        ),
      ),
      (
        'a remote image URL',
        const LlamaImageContent(url: 'https://example.com/image.png'),
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('remote image URLs'),
        ),
      ),
    ]) {
      test('rejecting $name on a bundle that declares no image encoder '
          'passes through unexplained', () async {
        final client = _FakeLiteRtLmRuntimeClient();
        final service = newService(client);
        declared = (vision: false, audio: false, speculativeDecoding: false);
        try {
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);
          await expectLater(
            mediaChat(service, context, media),
            throwsA(passedThrough),
          );
        } finally {
          service.dispose();
        }
      });
    }

    test('a speculative chat failure on a bundle that declares no drafter is '
        'explained', () async {
      final client = _FakeLiteRtLmRuntimeClient(
        initializeError: StateError('runtime failed'),
      );
      final service = newService(client);
      declared = (vision: true, audio: true, speculativeDecoding: false);
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);
        await expectLater(
          service.generateChat(
            context,
            [
              const LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'Hi',
              ),
            ],
            const GenerationParams(maxTokens: 8, speculativeDecoding: true),
          ).toList(),
          undeclared('speculative decoding drafter'),
        );
      } finally {
        service.dispose();
      }
    });
  });

  group('raw prompt start token', () {
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);
    late _FakeLiteRtLmRuntimeClient client;

    setUp(() => client = _FakeLiteRtLmRuntimeClient());

    /// A tokenizer that puts [start] (the text of token 1) before every
    /// prompt and reads [vocabulary] words, longest first, one token each.
    void tokenizer(String start, Map<String, int> vocabulary) {
      client.onTokenize = (text, addSpecial) {
        final tokens = <int>[if (addSpecial && start.isNotEmpty) 1];
        var rest = text;
        while (rest.isNotEmpty) {
          final word = vocabulary.keys
              .where(rest.startsWith)
              .fold('', (a, b) => b.length > a.length ? b : a);
          if (word.isEmpty) {
            tokens.add(rest.codeUnitAt(0) + 1000);
            rest = rest.substring(1);
          } else {
            tokens.add(vocabulary[word]!);
            rest = rest.substring(word.length);
          }
        }
        return tokens;
      };
      client.onDetokenize = (tokens) =>
          tokens.length == 1 && tokens.single == 1 ? start : '';
    }

    LiteRtLmService? service;
    int? context;

    tearDown(() {
      service?.dispose();
      service = null;
    });

    int? model;

    Future<void> load() async {
      if (service != null) return;
      service = LiteRtLmService(clientFactory: () => client);
      model = await service!.loadModel(modelFile.path, params);
      context = service!.createContext(model!, params);
    }

    Future<List<int>> tokenizeRuntimePrompt(String prompt) async {
      await load();
      return service!.tokenizeRuntimePrompt(model!, prompt);
    }

    Future<String?> send(String prompt) async {
      await load();
      client.generated = StreamController<String>()..add('ok');
      unawaited(client.generated.close());
      await service!
          .generate(context!, prompt, const GenerationParams(maxTokens: 8))
          .drain<void>();
      return client.lastPrompt;
    }

    test('drops special start-token text the runtime would read as a second '
        'start token', () async {
      tokenizer('<bos>', const {'hi': 50});
      expect(await send('<bos>hi'), 'hi');
      expect(await send('hi<bos>'), 'hi<bos>');
      expect(await send('hi'), 'hi');
    });

    test('drops plain start-token text only when the rest keeps its '
        'tokens', () async {
      tokenizer('None', const {'None': 1, 'hi': 50, 'Nonet': 60, 'he': 61});
      expect(await send('Nonehi'), 'hi');
      expect(await send('Nonethe'), 'Nonethe');
    });

    test('reads the start token again after loading another model', () async {
      tokenizer('None', const {'None': 1, 'hi': 50});
      final second = _FakeLiteRtLmRuntimeClient()
        ..onTokenize = client.onTokenize
        ..onDetokenize = (tokens) => '<bos>';
      final clients = [client, second];
      final service = LiteRtLmService(clientFactory: () => clients.removeAt(0));
      addTearDown(service.dispose);

      Future<String?> sendTo(
        _FakeLiteRtLmRuntimeClient fake,
        int context,
        String prompt,
      ) async {
        fake.generated = StreamController<String>()..add('ok');
        unawaited(fake.generated.close());
        await service
            .generate(context, prompt, const GenerationParams(maxTokens: 8))
            .drain<void>();
        return fake.lastPrompt;
      }

      var model = await service.loadModel(modelFile.path, params);
      var context = service.createContext(model, params);
      expect(await sendTo(client, context, 'Nonehi'), 'hi');

      model = await service.loadModel(modelFile.path, params);
      context = service.createContext(model, params);
      expect(await sendTo(second, context, 'Nonehi'), 'Nonehi');
      expect(await sendTo(second, context, '<bos>hi'), 'hi');
    });

    test('keeps a prompt when the runtime adds no start token', () async {
      tokenizer('', const {'hi': 50});
      expect(await send('<bos>hi'), '<bos>hi');
    });

    // As Gemma's tokenizer does, read `<bos>` text as three plain tokens.
    const bosText = {'<': 236820, 'bos': 46757, '>': 236813};

    test('counts special start-token text of a runtime prompt as the one '
        'start token prefill adds', () async {
      tokenizer('<bos>', const {...bosText, 'hi': 50});
      expect(await tokenizeRuntimePrompt('<bos>hi'), [1, 50]);
      expect(await tokenizeRuntimePrompt('hi'), [1, 50]);
      expect(await tokenizeRuntimePrompt('hi<bos>'), [
        1,
        50,
        236820,
        46757,
        236813,
      ]);
    });

    test('counts plain start-token text of a runtime prompt once only when '
        'prefill drops it', () async {
      tokenizer('None', const {'None': 1, 'hi': 50, 'Nonet': 60, 'he': 61});
      expect(await tokenizeRuntimePrompt('Nonehi'), [1, 50]);
      expect(await tokenizeRuntimePrompt('Nonethe'), [1, 60, 61]);
    });

    test('counts a runtime prompt as text when the runtime adds no start '
        'token', () async {
      tokenizer('', const {...bosText, 'hi': 50});
      expect(await tokenizeRuntimePrompt('<bos>hi'), [
        236820,
        46757,
        236813,
        50,
      ]);
    });

    for (final (name, start, prompt, reason) in [
      ('an empty prompt', '', '', contains('is empty')),
      (
        'an empty prompt for a runtime with a start token',
        '<bos>',
        '',
        allOf(contains('is empty'), isNot(contains('start token'))),
      ),
      (
        'a prompt that is only the start token',
        '<bos>',
        '<bos>',
        contains("holds only the model's start token"),
      ),
    ]) {
      test('refuses $name before native work', () async {
        tokenizer(start, const {});
        await expectLater(
          send(prompt),
          throwsA(
            isA<LlamaArgumentException>()
                .having((error) => error.name, 'name', 'prompt')
                .having(
                  (error) => error.message,
                  'message',
                  allOf(contains('needs prompt text'), reason),
                ),
          ),
        );
        expect(client.createConversationCount, 0);
        expect(client.generateCount, 0);
      });
    }
  });

  group('bundle template content shape', () {
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);
    const probeParts = [
      {'type': 'text', 'text': liteRtLmContentShapeProbeText},
    ];
    const history = [
      LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: 'Repeat "text": "$liteRtLmContentShapeProbeText" back.',
      ),
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: liteRtLmContentShapeProbeText,
      ),
      LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: 'Done.'),
    ];
    final records = <LlamaLogRecord>[];
    late _FakeLiteRtLmRuntimeClient client;
    late List<String> readPaths;

    setUp(() {
      client = _FakeLiteRtLmRuntimeClient()..rendersMessages = true;
      readPaths = <String>[];
      records.clear();
      LlamaLogger.instance.setLevel(LlamaLogLevel.warn);
      LlamaLogger.instance.setHandler(records.add);
    });

    tearDown(() {
      LlamaLogger.instance.setLevel(LlamaLogLevel.none);
      LlamaLogger.instance.setHandler(null);
    });

    // Renders as a LiteRT-LM v0.18 runtime does: content is a list of parts.
    void renderLikeTheRuntime(String bundleTemplate) {
      client.onRenderMessage = (template) =>
          renderLiteRtLmContent(template ?? bundleTemplate, probeParts);
    }

    LiteRtLmService serviceReading(String? template) => LiteRtLmService(
      clientFactory: () => client,
      readBundleChatTemplate: (path) {
        readPaths.add(path);
        return template;
      },
    );

    Future<void> chat(
      LiteRtLmService service,
      int context, {
      Object? sendError,
    }) async {
      client.generated = StreamController<String>();
      if (sendError == null) {
        client.generated.add('Hello');
      } else {
        client.generated.addError(sendError);
      }
      unawaited(client.generated.close());
      await service.generateChat(context, const [
        ...history,
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello'),
      ], const GenerationParams(maxTokens: 64)).drain<void>();
    }

    Future<void> raw(
      LiteRtLmService service,
      int context, {
      Object? sendError,
    }) async {
      client.generated = StreamController<String>();
      if (sendError == null) {
        client.generated.add('Hello');
      } else {
        client.generated.addError(sendError);
      }
      unawaited(client.generated.close());
      await service
          .generate(context, 'Hello', const GenerationParams(maxTokens: 64))
          .drain<void>();
    }

    for (final MapEntry(key: shape, value: bundleTemplate)
        in liteRtLmStringContentTemplates.entries) {
      test('adapts a template $shape content', () async {
        renderLikeTheRuntime(bundleTemplate);
        final adapter = liteRtLmTextContentAdapter(bundleTemplate);
        final service = serviceReading(bundleTemplate);
        try {
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);

          await chat(service, context);
          expect(client.conversations, [
            (template: null, seeded: false),
            (template: adapter, seeded: false),
            (template: adapter, seeded: true),
          ]);
          expect(readPaths, [modelFile.path]);

          await chat(service, context);
          expect(client.conversations.skip(3), [
            (template: adapter, seeded: true),
          ]);
          expect(client.renderMessageCount, 2);
          expect(readPaths, hasLength(1));
          expect(records, isEmpty);
        } finally {
          service.dispose();
        }
      });
    }

    for (final (name, nativeError) in [
      ('legacy', StateError.new),
      ('C API 1.0', LlamaModelException.new),
    ]) {
      test('adapts a template the $name runtime fails to render', () async {
        final concatenating = liteRtLmStringContentTemplates['concatenating']!;
        client.onRenderMessage = (template) => template == null
            ? throw nativeError(
                'render_message_to_string failed: tried to use + operator '
                'on unsupported types string and sequence',
              )
            : renderLiteRtLmContent(template, probeParts);
        final adapter = liteRtLmTextContentAdapter(concatenating);
        final service = serviceReading(concatenating);
        try {
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);

          await chat(service, context);
          expect(client.conversations, [
            (template: null, seeded: false),
            (template: adapter, seeded: false),
            (template: adapter, seeded: true),
          ]);
          expect(records, isEmpty);
        } finally {
          service.dispose();
        }
      });
    }

    test('keeps a template that reads content parts', () async {
      renderLikeTheRuntime(liteRtLmPartsContentTemplate);
      final service = serviceReading(liteRtLmPartsContentTemplate);
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);

        await chat(service, context);
        await chat(service, context);
        expect(client.conversations, [
          (template: null, seeded: false),
          (template: null, seeded: true),
          (template: null, seeded: true),
        ]);
        expect(client.renderMessageCount, 1);
        expect(readPaths, isEmpty);
        expect(records, isEmpty);
      } finally {
        service.dispose();
      }
    });

    test('does not probe a runtime that cannot render a message', () async {
      client.rendersMessages = false;
      final service = serviceReading(
        liteRtLmStringContentTemplates['interpolating'],
      );
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);

        await chat(service, context);
        await chat(service, context);
        expect(client.conversations, [
          (template: null, seeded: true),
          (template: null, seeded: true),
        ]);
        expect(readPaths, isEmpty);
        expect(records, isEmpty);
      } finally {
        service.dispose();
      }
    });

    final interpolating = liteRtLmStringContentTemplates['interpolating']!;
    final concatenating = liteRtLmStringContentTemplates['concatenating']!;
    // How each runtime client reports a failed native call.
    final nativeErrors = <(String, Object Function(String))>[
      ('legacy', StateError.new),
      ('C API 1.0', LlamaModelException.new),
    ];
    for (final (name, template, configure) in [
      (
        'a bundle whose template it cannot read',
        null,
        (_FakeLiteRtLmRuntimeClient client) =>
            client.onRenderMessage = (_) =>
                renderLiteRtLmContent(interpolating, probeParts),
      ),
      (
        'a template the adapter does not change',
        interpolating,
        (_FakeLiteRtLmRuntimeClient client) =>
            client.onRenderMessage = (_) =>
                renderLiteRtLmContent(interpolating, probeParts),
      ),
      (
        'a template that drops the text with the adapter too',
        interpolating,
        (_FakeLiteRtLmRuntimeClient client) =>
            client.onRenderMessage = (_) => '<|im_start|>\n<|im_end|>\n',
      ),
      for (final (client, nativeError) in nativeErrors) ...[
        (
          'a template that fails to render with the adapter too ($client)',
          concatenating,
          (_FakeLiteRtLmRuntimeClient client) =>
              client.onRenderMessage = (_) =>
                  throw nativeError('render_message_to_string failed'),
        ),
        (
          'an adapted template the $client runtime rejects',
          interpolating,
          (_FakeLiteRtLmRuntimeClient client) {
            client.onRenderMessage = (_) => '';
            client.onCreateConversation = () {
              if (client.lastPromptTemplate != null) {
                throw nativeError('litert_lm_conversation_create failed');
              }
            };
          },
        ),
      ],
      (
        'a runtime that takes no conversation template',
        interpolating,
        (_FakeLiteRtLmRuntimeClient client) {
          client.onRenderMessage = (_) => '';
          client.onCreateConversation = () {
            if (client.lastPromptTemplate != null) {
              throw LlamaUnsupportedException('no template setter');
            }
          };
        },
      ),
    ]) {
      test('warns once and keeps the bundle template for $name', () async {
        configure(client);
        final service = serviceReading(template);
        try {
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);

          await chat(service, context);
          expect(client.conversations.last, (template: null, seeded: true));
          expect(records, hasLength(1));
          expect(records.single.level, LlamaLogLevel.warn);
          expect(records.single.message, contains('could not adapt'));

          final created = client.conversations.length;
          final rendered = client.renderMessageCount;
          await chat(service, context);
          expect(client.conversations.skip(created), [
            (template: null, seeded: true),
          ]);
          expect(client.renderMessageCount, rendered);
          expect(records, hasLength(1));
        } finally {
          service.dispose();
        }
      });
    }

    for (final (clientName, nativeError, typeMatcher)
        in <(String, Object Function(String), Matcher)>[
          ('legacy', StateError.new, isA<StateError>()),
          (
            'v1',
            LiteRtLmSendFailureException.new,
            isA<LiteRtLmSendFailureException>(),
          ),
        ]) {
      test('a failed $clientName chat send names a bundle template it could '
          'not adapt', () async {
        client.onRenderMessage = (_) => throw StateError('render failed');
        final service = serviceReading(null);
        final failure = nativeError('send_message_stream rc=13');
        try {
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);

          await expectLater(
            chat(service, context, sendError: failure),
            throwsA(
              allOf(
                typeMatcher,
                isA<Object>().having(
                  _nativeMessage,
                  'message',
                  allOf(
                    startsWith('send_message_stream rc=13 '),
                    contains('chat template of this bundle'),
                    contains('list of {"type": "text", "text": ...} parts'),
                  ),
                ),
              ),
            ),
          );
        } finally {
          service.dispose();
        }
      });
    }

    test('a v1 send failure keeps its details when it gets the note', () async {
      client.onRenderMessage = (_) => throw StateError('render failed');
      final service = serviceReading(null);
      const details = {'status': 13};
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);

        await expectLater(
          chat(
            service,
            context,
            sendError: LiteRtLmSendFailureException('send failed', details),
          ),
          throwsA(
            isA<LiteRtLmSendFailureException>()
                .having((e) => e.details, 'details', details)
                .having(
                  (e) => e.message,
                  'message',
                  contains('chat template of this bundle'),
                ),
          ),
        );
      } finally {
        service.dispose();
      }
    });

    test('a v1 stream failure before output gets no template note', () async {
      client.onRenderMessage = (_) => throw StateError('render failed');
      final service = serviceReading(null);
      final failure = LlamaModelException(
        'C API 1.0 stream failed: INVALID_ARGUMENT: Input token ids are too '
        'long',
      );
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);

        await expectLater(
          chat(service, context, sendError: failure),
          throwsA(same(failure)),
        );
      } finally {
        service.dispose();
      }
    });

    test('a chat send failing with another Llama exception stays as it '
        'is', () async {
      client.onRenderMessage = (_) => throw StateError('render failed');
      final service = serviceReading(null);
      final failure = LlamaStateException('engine disposed');
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);

        await expectLater(
          chat(service, context, sendError: failure),
          throwsA(same(failure)),
        );
      } finally {
        service.dispose();
      }
    });

    test('a failed raw send does not name a bundle template it does not '
        'use', () async {
      client.onRenderMessage = (_) => throw StateError('render failed');
      final service = serviceReading(null);
      final failure = StateError('send_message_stream rc=13');
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);
        await chat(service, context);
        expect(records.single.message, contains('could not adapt'));

        await expectLater(
          raw(service, context, sendError: failure),
          throwsA(same(failure)),
        );
      } finally {
        service.dispose();
      }
    });

    test('raw generation sends the prompt unchanged, without the bundle '
        'template or its probe', () async {
      renderLikeTheRuntime(interpolating);
      final service = serviceReading(interpolating);
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);
        const prompt =
            '<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n';
        client.generated = StreamController<String>()..add('Hi');
        unawaited(client.generated.close());

        await service
            .generate(context, prompt, const GenerationParams(maxTokens: 8))
            .drain<void>();

        expect(client.conversations, [
          (template: liteRtLmRawPromptTemplate, seeded: false),
        ]);
        expect(client.lastPrompt, prompt);
        expect(client.renderMessageCount, 0);
        expect(readPaths, isEmpty);

        await chat(service, context);
        expect(client.conversations.skip(1), [
          (template: null, seeded: false),
          (template: liteRtLmTextContentAdapter(interpolating), seeded: false),
          (template: liteRtLmTextContentAdapter(interpolating), seeded: true),
        ]);
      } finally {
        service.dispose();
      }
    });

    test('a state failure creating the adapted template propagates without '
        'a cannot-adapt warning', () async {
      final failure = LlamaStateException('engine is not ready');
      client.onRenderMessage = (_) => '';
      client.onCreateConversation = () {
        if (client.lastPromptTemplate != null) throw failure;
      };
      final service = serviceReading(interpolating);
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);

        await expectLater(chat(service, context), throwsA(same(failure)));
        expect(
          records.where((record) => record.message.contains('could not adapt')),
          isEmpty,
        );
      } finally {
        service.dispose();
      }
    });

    test('raw generation keeps a runtime refusal of its template', () async {
      final refusal = LlamaUnsupportedException('no template setter');
      client.onCreateConversation = () {
        if (client.lastPromptTemplate != null) throw refusal;
      };
      final service = serviceReading(null);
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);

        await expectLater(
          service
              .generate(context, 'Hello', const GenerationParams(maxTokens: 8))
              .drain<void>(),
          throwsA(same(refusal)),
        );
        expect(client.generateCount, 0);
      } finally {
        service.dispose();
      }
    });

    for (final (name, send) in [('chat', chat), ('raw', raw)]) {
      test('a failed $name send stays as it is for a template that reads '
          'content', () async {
        final service = serviceReading(liteRtLmPartsContentTemplate);
        final failure = StateError('send_message_stream rc=13');
        try {
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);

          await expectLater(
            send(service, context, sendError: failure),
            throwsA(same(failure)),
          );
        } finally {
          service.dispose();
        }
      });
    }

    test('a send that fails after output keeps its error', () async {
      client.onRenderMessage = (_) => throw StateError('render failed');
      final service = serviceReading(null);
      final failure = StateError('send_message_stream rc=13');
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);
        client.generated = StreamController<String>()
          ..add('Hello')
          ..addError(failure);
        unawaited(client.generated.close());

        await expectLater(
          service
              .generate(context, 'Hello', const GenerationParams(maxTokens: 8))
              .drain<void>(),
          throwsA(same(failure)),
        );
      } finally {
        service.dispose();
      }
    });

    test('does not decide when the probe conversation cannot be '
        'created', () async {
      renderLikeTheRuntime(interpolating);
      final adapter = liteRtLmTextContentAdapter(interpolating);
      final service = serviceReading(interpolating);
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);
        client.onCreateConversation = () =>
            throw StateError('litert_lm_conversation_create returned null');

        await expectLater(chat(service, context), throwsStateError);
        expect(
          records.where((record) => record.message.contains('adapt')),
          isEmpty,
        );

        client.onCreateConversation = null;
        await chat(service, context);
        expect(client.conversations.last, (template: adapter, seeded: true));
      } finally {
        service.dispose();
      }
    });

    test('does not decide when the probe render fails for another '
        'reason', () async {
      final disposed = LlamaStateException('C API 1.0 adapter is disposed.');
      final adapter = liteRtLmTextContentAdapter(interpolating);
      client.onRenderMessage = (_) => throw disposed;
      final service = serviceReading(interpolating);
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);

        await expectLater(chat(service, context), throwsA(same(disposed)));
        expect(
          records.where((record) => record.message.contains('adapt')),
          isEmpty,
        );

        renderLikeTheRuntime(interpolating);
        await chat(service, context);
        expect(client.conversations.last, (template: adapter, seeded: true));
      } finally {
        service.dispose();
      }
    });

    test('probes each loaded model', () async {
      renderLikeTheRuntime(interpolating);
      final service = serviceReading(interpolating);
      final other = File('${tempDir.path}/other.litertlm');
      await other.writeAsString('fake model');
      try {
        var model = await service.loadModel(modelFile.path, params);
        await chat(service, service.createContext(model, params));
        expect(
          client.lastPromptTemplate,
          liteRtLmTextContentAdapter(interpolating),
        );

        client = _FakeLiteRtLmRuntimeClient()..rendersMessages = true;
        model = await service.loadModel(other.path, params);
        await chat(service, service.createContext(model, params));
        expect(client.conversations, [
          (template: null, seeded: false),
          (template: null, seeded: true),
        ]);
        expect(client.renderMessageCount, 1);
      } finally {
        service.dispose();
      }
    });

    test('leaves a conversation that overrides the template alone', () async {
      renderLikeTheRuntime(interpolating);
      final service = serviceReading(interpolating);
      final file = File('${tempDir.path}/Qwen3-0.6B.litertlm');
      await file.writeAsString('fake model');
      try {
        final model = await service.loadModel(file.path, params);
        await chat(service, service.createContext(model, params));
        expect(
          client.conversations.single.template,
          contains('enable_thinking'),
        );
        expect(client.renderMessageCount, 0);
        expect(readPaths, isEmpty);
      } finally {
        service.dispose();
      }
    });
  });

  group('renamed Qwen3 thinking', () {
    final qwen3 = kLiteRtLmChatTemplates.singleWhere(
      (item) => item.id == 'qwen3',
    );
    Future<String?> generate(
      LiteRtLmService service,
      _FakeLiteRtLmRuntimeClient client,
      int context, {
      LlamaContentPart? media,
    }) async {
      final pending = service
          .generateChat(
            context,
            [
              LlamaChatMessage.withContent(
                role: LlamaChatRole.user,
                content: [const LlamaTextContent('Hello'), ?media],
              ),
            ],
            const GenerationParams(maxTokens: 64),
            enableThinking: false,
          )
          .toList();
      await Future.any([client.generateStarted.future, pending]);
      client.generated.add('Hello');
      await client.generated.close();
      expect(await pending, [utf8.encode('Hello')]);
      return client.lastPromptTemplate;
    }

    for (final name in ['download', 'qwen.litertlm', 'Qwen3-0.6B.litertlm']) {
      for (final setter in [false, true]) {
        test('public Qwen3 override $name setter=$setter', () async {
          final file = File('${tempDir.path}/$name');
          // Legacy bundles have no model-type or Jinja metadata (fields 6/7).
          final legacy = Uint8List.fromList([
            ..._thinkingBundle(modelType: 5).take(136),
            0x28, 0x80, 0x20, // max_num_tokens = 4096 (field 5 only).
          ]);
          ByteData.sublistView(
            legacy,
          ).setUint64(108, legacy.length, Endian.little);
          await file.writeAsBytes(legacy);
          expect(readLiteRtLmBundleMetadata(file.path)?.isQwen3, isFalse);
          expect(readLiteRtLmBundleMetadata(file.path)?.chatTemplate, isNull);
          final client = _FakeLiteRtLmRuntimeClient();
          if (!setter) {
            client.onCreateConversation = () {
              if (client.lastPromptTemplate != null) {
                throw LlamaUnsupportedException('no template setter');
              }
            };
          }
          final service = LiteRtLmService(clientFactory: () => client);
          final params = ModelParams(
            device: ComputeDevice.cpu,
            chatTemplate: api.liteRtLmQwen3ChatTemplate,
          );
          try {
            final model = await service.loadModel(file.path, params);
            final context = service.createContext(model, params);
            if (!setter) {
              await expectLater(
                service
                    .generateChat(
                      context,
                      const [
                        LlamaChatMessage.fromText(
                          role: LlamaChatRole.user,
                          text: 'Hello',
                        ),
                      ],
                      const GenerationParams(maxTokens: 64),
                      enableThinking: false,
                    )
                    .toList(),
                throwsA(isA<LlamaUnsupportedException>()),
              );
              return;
            }
            expect(
              await generate(service, client, context),
              api.liteRtLmQwen3ChatTemplate,
            );
            expect(client.lastExtraContext?['enable_thinking'], isFalse);
            final rendered = Template(client.lastPromptTemplate!).render({
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': 'Hello'},
                  ],
                },
              ],
              'add_generation_prompt': true,
              ...client.lastExtraContext!,
            });
            expect(rendered, endsWith('<think>\n\n</think>\n\n'));
            expect(
              service.getMetadata(model)['tokenizer.chat_template'],
              api.liteRtLmQwen3ChatTemplate,
            );
          } finally {
            service.dispose();
          }
        });
      }
    }

    for (final name in [
      'Phi-4-mini',
      'Llama-3.2-1B',
      'DeepSeek-R1-Distill-Qwen',
      'renamed-gemma-3n',
      'download', // Renamed Gemma 3n with no family hint in the filename.
      'Qwen2.5-0.5B',
    ]) {
      for (final override in [null, '{{ messages[0].content }}', '']) {
        test('main native routing $name override=$override', () async {
          final file = File('${tempDir.path}/$name.litertlm');
          await file.writeAsBytes(_thinkingBundle(modelType: 1));
          final client = _FakeLiteRtLmRuntimeClient()
            ..rendersMessages = true
            ..onRenderMessage = (_) => liteRtLmContentShapeProbeText;
          final service = LiteRtLmService(clientFactory: () => client);
          final params = ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            chatTemplate: override,
          );
          try {
            final model = await service.loadModel(file.path, params);
            expect(
              await generate(
                service,
                client,
                service.createContext(model, params),
              ),
              isNull,
            );
            expect(client.renderMessageCount, 1);
            expect(client.conversations, [
              (template: null, seeded: false),
              (template: null, seeded: true),
            ]);
            if (override != null) {
              expect(
                service.getMetadata(model)['tokenizer.chat_template'],
                override,
              );
            }
          } finally {
            service.dispose();
          }
        });
      }
    }

    for (final fixture in [
      'test/fixtures/templates/Qwen3_5-0_8B.jinja',
      'test/fixtures/llama_cpp_templates/Qwen-QwQ-32B.jinja',
    ]) {
      test('does not replace the embedded family template $fixture', () async {
        await modelFile.writeAsBytes(
          _thinkingBundle(
            modelType: 1,
            template: File(fixture).readAsStringSync(),
          ),
        );
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        const params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        );
        try {
          final model = await service.loadModel(modelFile.path, params);
          expect(
            service.getMetadata(model),
            isNot(contains('tokenizer.chat_template')),
          );
          expect(
            await generate(
              service,
              client,
              service.createContext(model, params),
            ),
            isNull,
          );
        } finally {
          service.dispose();
        }
      });
    }

    test(
      'a detected bundle uses the explicit override before its template',
      () async {
        await modelFile.writeAsBytes(
          _thinkingBundle(modelType: 5, template: qwen3.template),
        );
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        const custom = '{{ enable_thinking }} custom';
        const params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          chatTemplate: custom,
        );
        try {
          final model = await service.loadModel(modelFile.path, params);
          expect(
            await generate(
              service,
              client,
              service.createContext(model, params),
            ),
            custom,
          );
          expect(service.getMetadata(model)['tokenizer.chat_template'], custom);
        } finally {
          service.dispose();
        }
      },
    );

    test(
      'canonical override identifies a bundle despite a different embedded template',
      () async {
        await modelFile.writeAsBytes(
          _thinkingBundle(modelType: 1, template: '{{ messages }}'),
        );
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        final custom = '  \n${qwen3.template}';
        final params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          chatTemplate: custom,
        );
        try {
          final model = await service.loadModel(modelFile.path, params);
          expect(
            await generate(
              service,
              client,
              service.createContext(model, params),
            ),
            custom,
          );
        } finally {
          service.dispose();
        }
      },
    );

    test('generic override keeps the bundle content adapter', () async {
      const embedded = '{{ messages[0].content }}';
      final adapted = liteRtLmTextContentAdapter(embedded);
      final client = _FakeLiteRtLmRuntimeClient()
        ..rendersMessages = true
        ..onRenderMessage = (template) =>
            renderLiteRtLmContent(template ?? embedded, [
              {'type': 'text', 'text': liteRtLmContentShapeProbeText},
            ]);
      final service = LiteRtLmService(
        clientFactory: () => client,
        readBundleChatTemplate: (_) => embedded,
      );
      const params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        chatTemplate: 'user override',
      );
      try {
        final model = await service.loadModel(modelFile.path, params);
        expect(
          await generate(service, client, service.createContext(model, params)),
          adapted,
        );
        expect(client.renderMessageCount, 2);
        expect(service.getMetadata(model), {
          'general.architecture': 'litert-lm',
          'general.file_type': 'litertlm',
          'general.name': 'model.litertlm',
          'llm.context_length': '${params.contextSize}',
          'tokenizer.chat_template': embedded,
          parsingChatTemplateMetadataKey: 'user override',
        });
      } finally {
        service.dispose();
      }
    });

    group('reports the template the runtime renders', () {
      const embedded = '{{ messages[0].content }} EMBEDDED';
      final cases = <(String, String?, String?)>[
        // (bundle file, ModelParams.chatTemplate, embedded template)
        ('Qwen3.5-0.8B_int8.litertlm', null, embedded),
        ('Qwen3.5-0.8B-VL_int8.litertlm', null, embedded),
        ('gemma-4-E2B-it.litertlm', null, embedded),
        ('Qwen2.5-1.5B-Instruct.litertlm', null, embedded),
        ('gemma-4-E2B-it.litertlm', 'user override', embedded),
        ('Phi-4-mini.litertlm', 'user override', embedded),
        ('Qwen3-0.6B.litertlm', null, embedded),
        ('Qwen3-0.6B.litertlm', 'user override', embedded),
        ('Qwen3.5-0.8B_int8.litertlm', null, null),
        ('Phi-4-mini.litertlm', null, embedded),
      ];
      for (final (name, override, bundleTemplate) in cases) {
        test(
          '$name override=$override embedded=${bundleTemplate != null}',
          () async {
            final file = File('${tempDir.path}/$name');
            await file.writeAsBytes(_thinkingBundle(modelType: 1));
            final service = LiteRtLmService(
              clientFactory: _FakeLiteRtLmRuntimeClient.new,
              readBundleChatTemplate: (_) => bundleTemplate,
            );
            try {
              final model = await service.loadModel(
                file.path,
                ModelParams(
                  liteRtLmBackend: LiteRtLmBackendPreference.cpu,
                  chatTemplate: override,
                ),
              );
              final family = kLiteRtLmChatTemplates
                  .where(
                    (template) => template.matches(
                      name.toLowerCase().replaceAll('_', '-'),
                    ),
                  )
                  .firstOrNull;
              final parsing = override ?? family?.template;
              final rendersParsingTemplate = name.startsWith('Qwen3-');
              final runtime = parsing == null || rendersParsingTemplate
                  ? parsing
                  : bundleTemplate ?? parsing;
              final metadata = service.getMetadata(model);
              expect(metadata['tokenizer.chat_template'], runtime);
              expect(
                metadata[parsingChatTemplateMetadataKey],
                runtime == parsing ? isNull : parsing,
              );
              expect(metadata['tokenizer.ggml.eos_token'], family?.eosToken);
            } finally {
              service.dispose();
            }
          },
        );
      }
    });

    test(
      'JSON Schema chat follows the Qwen3 text routing of generation',
      () async {
        final file = File('${tempDir.path}/Qwen3.5-0.8B_int8.litertlm');
        await file.writeAsBytes(
          _thinkingBundle(modelType: 5, template: qwen3.template),
        );
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(
          clientFactory: () => client,
          jsonSchemaQualifiedBackends: () => {'cpu', 'gpu'},
        );
        try {
          await service.loadModel(
            file.path,
            const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu),
          );
          await expectLater(
            service.prepareJsonSchemaChat(),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                contains('Qwen3 with its canonical text template'),
              ),
            ),
          );
        } finally {
          service.dispose();
        }
      },
    );

    test('detected Qwen3 reports a missing native template setter', () async {
      await modelFile.writeAsBytes(_thinkingBundle(modelType: 5));
      final client = _FakeLiteRtLmRuntimeClient();
      client.onCreateConversation = () {
        if (client.lastPromptTemplate != null) {
          throw LlamaUnsupportedException('no template setter');
        }
      };
      final service = LiteRtLmService(clientFactory: () => client);
      const params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
      );
      try {
        final model = await service.loadModel(modelFile.path, params);
        await expectLater(
          generate(service, client, service.createContext(model, params)),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      } finally {
        service.dispose();
      }
    });

    for (final custom in ["{{ enable_thinking }}", '']) {
      test('explicit override is forwarded verbatim: "$custom"', () async {
        await modelFile.writeAsBytes(_thinkingBundle(modelType: 5));
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        final params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          chatTemplate: custom,
        );
        try {
          final model = await service.loadModel(modelFile.path, params);
          expect(
            await generate(
              service,
              client,
              service.createContext(model, params),
            ),
            custom,
          );
          expect(client.lastExtraContext?['enable_thinking'], isFalse);
        } finally {
          service.dispose();
        }
      });
    }

    for (final marker in [
      '<|im_start|>',
      '<|im_end|>',
      '<think>',
      '</think>',
      'enable_thinking',
    ]) {
      test('does not infer Qwen3 without $marker', () async {
        await modelFile.writeAsBytes(
          _thinkingBundle(
            modelType: 1,
            template: qwen3.template.replaceAll(marker, ''),
          ),
        );
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        const params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        );
        try {
          final model = await service.loadModel(modelFile.path, params);
          expect(
            service.getMetadata(model),
            isNot(contains('tokenizer.chat_template')),
          );
          expect(
            await generate(
              service,
              client,
              service.createContext(model, params),
            ),
            isNull,
          );
        } finally {
          service.dispose();
        }
      });
    }

    for (final name in ['Qwen3.5-0.8B', 'gemma-4-E2B']) {
      test('preserves the established $name native processor', () async {
        final file = File('${tempDir.path}/$name.litertlm');
        await file.writeAsBytes(
          _thinkingBundle(modelType: 5, template: qwen3.template),
        );
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        final params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          chatTemplate: qwen3.template,
        );
        try {
          final model = await service.loadModel(file.path, params);
          expect(
            await generate(
              service,
              client,
              service.createContext(model, params),
            ),
            isNull,
          );
        } finally {
          service.dispose();
        }
      });
    }

    for (final media in [
      LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
      LlamaAudioContent(bytes: Uint8List.fromList([1, 2, 3])),
    ]) {
      test('keeps the native ${media.runtimeType} processor', () async {
        await modelFile.writeAsBytes(_thinkingBundle(modelType: 5));
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        final params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          chatTemplate: qwen3.template,
        );
        try {
          final model = await service.loadModel(modelFile.path, params);
          expect(
            await generate(
              service,
              client,
              service.createContext(model, params),
              media: media,
            ),
            isNull,
          );
        } finally {
          service.dispose();
        }
      });
    }

    test('forgets bundle family on reload and free', () async {
      await modelFile.writeAsBytes(_thinkingBundle(modelType: 5));
      final service = LiteRtLmService();
      const params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
      );
      try {
        var model = await service.loadModel(modelFile.path, params);
        expect(
          service.getMetadata(model)['tokenizer.chat_template'],
          qwen3.template,
        );
        await modelFile.writeAsBytes(_thinkingBundle(modelType: 1));
        model = await service.loadModel(modelFile.path, params);
        expect(
          service.getMetadata(model),
          isNot(contains('tokenizer.chat_template')),
        );
        service.freeModel(model);
        model = await service.loadModel(modelFile.path, params);
        expect(
          service.getMetadata(model),
          isNot(contains('tokenizer.chat_template')),
        );
      } finally {
        service.dispose();
      }
    });

    for (final source in ['model type', 'bundle template', 'override']) {
      for (final basename in ['qwen.litertlm', 'download']) {
        for (final thinking in [false, true]) {
          test('$source $basename honours enableThinking=$thinking', () async {
            final file = File('${tempDir.path}/$basename');
            // LlmMetadata.llm_model_type.qwen3 (6 -> 5), no model weights.
            await file.writeAsBytes(
              _thinkingBundle(
                modelType: source == 'model type' ? 5 : 1,
                template: source == 'bundle template' ? qwen3.template : null,
              ),
            );
            final client = _FakeLiteRtLmRuntimeClient();
            final service = LiteRtLmService(clientFactory: () => client);
            final custom = '${qwen3.template}\ncustom';
            final params = ModelParams(
              liteRtLmBackend: LiteRtLmBackendPreference.cpu,
              chatTemplate: source == 'override' ? custom : null,
            );
            try {
              final model = await service.loadModel(file.path, params);
              final context = service.createContext(model, params);
              final pending = service
                  .generateChat(
                    context,
                    const [
                      LlamaChatMessage.fromText(
                        role: LlamaChatRole.user,
                        text: 'Hello',
                      ),
                    ],
                    const GenerationParams(maxTokens: 64),
                    enableThinking: thinking,
                  )
                  .toList();
              await client.generateStarted.future;
              client.generated.add('Hello');
              await client.generated.close();
              expect(await pending, [utf8.encode('Hello')]);
              expect(
                client.lastPromptTemplate,
                source == 'override' ? custom : qwen3.template,
              );
              expect(
                service.getMetadata(model)['tokenizer.chat_template'],
                client.lastPromptTemplate,
              );
              expect(
                service.getMetadata(model)['tokenizer.ggml.eos_token'],
                '<|im_end|>',
              );
              final rendered = Template(client.lastPromptTemplate!).render({
                'messages': [
                  {
                    'role': 'user',
                    'content': [
                      {'type': 'text', 'text': 'Hello'},
                    ],
                  },
                ],
                'add_generation_prompt': true,
                ...client.lastExtraContext!,
              });
              expect(rendered, contains('<|im_start|>user\nHello<|im_end|>'));
              expect(rendered.contains('<think>\n\n</think>'), !thinking);
            } finally {
              service.dispose();
            }
          });
        }
      }
    }
  });

  for (final name in ['Qwen3-0.6B', 'Qwen3.5-0.8B', 'gemma-4-E2B', 'unknown']) {
    for (final thinking in [false, true]) {
      test('$name native text template preserves thinking=$thinking', () async {
        final file = File('${tempDir.path}/$name.litertlm');
        await file.writeAsString('fake model');
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        const params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        );
        try {
          final model = await service.loadModel(file.path, params);
          final context = service.createContext(model, params);
          final pending = service
              .generateChat(
                context,
                const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'Hello',
                  ),
                ],
                const GenerationParams(maxTokens: 64),
                enableThinking: thinking,
              )
              .toList();
          await client.generateStarted.future;
          client.generated.add('Hello');
          await client.generated.close();
          expect(await pending, [utf8.encode('Hello')]);
          expect(client.lastExtraContext?['enable_thinking'], thinking);
          if (name == 'Qwen3-0.6B') {
            expect(client.lastPromptTemplate, contains('enable_thinking'));
            expect(
              client.lastPromptTemplate,
              service.getMetadata(model)['tokenizer.chat_template'],
            );
          } else {
            expect(client.lastPromptTemplate, isNull);
          }
        } finally {
          service.dispose();
        }
      });
    }
  }

  for (final (clientName, nativeError, typeMatcher)
      in <(String, Object Function(String), Matcher)>[
        ('legacy', StateError.new, isA<StateError>()),
        (
          'v1',
          LiteRtLmSendFailureException.new,
          isA<LiteRtLmSendFailureException>(),
        ),
      ]) {
    for (final custom in [true, false]) {
      test('a failed $clientName native send '
          '${custom ? 'names' : 'does not name'} the '
          'content-parts change ${custom ? 'with' : 'without'} a custom '
          'template', () async {
        final file = File('${tempDir.path}/Qwen3-0.6B.litertlm');
        await file.writeAsString('fake model');
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        final params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          chatTemplate: custom ? "{{ 'x' + messages[0]['content'] }}" : null,
        );
        try {
          final model = await service.loadModel(file.path, params);
          final context = service.createContext(model, params);
          final pending = service.generateChat(context, const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
          ], const GenerationParams(maxTokens: 8)).toList();
          const nativeFailure =
              'litert_lm_conversation_send_message_stream rc=13';
          final failure = expectLater(
            pending,
            throwsA(
              allOf(
                typeMatcher,
                isA<Object>().having(
                  _nativeMessage,
                  'message',
                  custom
                      ? allOf(
                          startsWith('$nativeFailure ModelParams.chatTemplate'),
                          contains(
                            'list of {"type": "text", "text": ...} parts',
                          ),
                        )
                      : nativeFailure,
                ),
              ),
            ),
          );
          await client.generateStarted.future;
          client.generated.addError(nativeError(nativeFailure));
          await client.generated.close();
          await failure;
        } finally {
          service.dispose();
        }
      });
    }
  }

  test(
    'a v1 stream failure before output gets no custom-template note',
    () async {
      final file = File('${tempDir.path}/Qwen3-0.6B.litertlm');
      await file.writeAsString('fake model');
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      const params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        chatTemplate: '{{ messages[0].content }}',
      );
      final failure = LlamaModelException(
        'C API 1.0 stream failed: INVALID_ARGUMENT: Input token ids are too long',
      );
      try {
        final model = await service.loadModel(file.path, params);
        final context = service.createContext(model, params);
        final pending = service.generateChat(context, const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
        ], const GenerationParams(maxTokens: 8)).toList();
        final result = expectLater(pending, throwsA(same(failure)));
        await client.generateStarted.future;
        client.generated.addError(failure);
        await client.generated.close();
        await result;
      } finally {
        service.dispose();
      }
    },
  );

  test('a native failure after output started does not name the '
      'content-parts change', () async {
    final file = File('${tempDir.path}/Qwen3-0.6B.litertlm');
    await file.writeAsString('fake model');
    final client = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => client);
    const params = ModelParams(
      liteRtLmBackend: LiteRtLmBackendPreference.cpu,
      chatTemplate: '{{ messages[0].content }}',
    );
    try {
      final model = await service.loadModel(file.path, params);
      final context = service.createContext(model, params);
      final chunks = <List<int>>[];
      const nativeFailure = 'litert_lm_conversation_send_message_stream rc=13';
      final failure = expectLater(
        service
            .generateChat(
              context,
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
              ],
              // The stop sequence holds the chunk back from the caller.
              const GenerationParams(maxTokens: 8, stopSequences: ['<stop>']),
            )
            .forEach(chunks.add),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            nativeFailure,
          ),
        ),
      );
      await client.generateStarted.future;
      client.generated
        ..add('Hel')
        ..addError(StateError(nativeFailure));
      await client.generated.close();
      await failure;
      expect(chunks, isEmpty);
    } finally {
      service.dispose();
    }
  });

  for (final withMedia in [false, true]) {
    test(
      'Qwen3 custom text override and native media boundary: $withMedia',
      () async {
        final file = File('${tempDir.path}/Qwen3-0.6B.litertlm');
        await file.writeAsString('fake model');
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        const custom = '{{ messages[0].content }}';
        const params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          chatTemplate: custom,
        );
        try {
          final model = await service.loadModel(file.path, params);
          final context = service.createContext(model, params);
          final pending = service
              .generateChat(
                context,
                [
                  LlamaChatMessage.withContent(
                    role: LlamaChatRole.user,
                    content: [
                      const LlamaTextContent('Hello'),
                      if (withMedia)
                        LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
                    ],
                  ),
                ],
                const GenerationParams(maxTokens: 64),
                enableThinking: false,
              )
              .toList();
          await client.generateStarted.future;
          client.generated.add('Hello');
          await client.generated.close();
          expect(await pending, [utf8.encode('Hello')]);
          expect(client.lastPromptTemplate, withMedia ? isNull : custom);
        } finally {
          service.dispose();
        }
      },
    );
  }

  test(
    'loads local litertlm bundles without initializing native runtime',
    () async {
      final service = LiteRtLmService();

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(
            contextSize: 2048,
            preferredBackend: GpuBackend.cpu,
          ),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(contextSize: 1024),
        );

        expect(modelHandle, 1);
        expect(contextHandle, 1);
        expect(service.getContextSize(contextHandle), 1024);
        expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
        expect(service.getResolvedGpuLayers(), 0);
        expect(
          service.getMetadata(modelHandle),
          containsPair('general.file_type', 'litertlm'),
        );
        expect(service.getAvailableBackendInfo(), contains('cpu'));

        service.freeContext(contextHandle);
        service.freeModel(modelHandle);

        final uppercaseModelFile = File('${tempDir.path}/MODEL.LITERTLM');
        await uppercaseModelFile.writeAsString('fake model');
        final uppercaseModelHandle = await service.loadModel(
          uppercaseModelFile.path,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );
        expect(uppercaseModelHandle, isNot(modelHandle));
        expect(
          service.getMetadata(uppercaseModelHandle),
          containsPair('general.name', 'MODEL.LITERTLM'),
        );
        service.freeModel(uppercaseModelHandle);
      } finally {
        service.dispose();
      }
    },
  );

  test('invalidates stale model and context handles after reload', () async {
    final service = LiteRtLmService();
    final secondModelFile = File('${tempDir.path}/second.litertlm');
    await secondModelFile.writeAsString('fake model');

    try {
      final firstModelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      final firstContextHandle = service.createContext(
        firstModelHandle,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      final secondModelHandle = await service.loadModel(
        secondModelFile.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      final secondContextHandle = service.createContext(
        secondModelHandle,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      expect(secondModelHandle, isNot(firstModelHandle));
      expect(secondContextHandle, isNot(firstContextHandle));
      expect(() => service.getMetadata(firstModelHandle), throwsStateError);
      expect(
        () => service.getContextSize(firstContextHandle),
        throwsStateError,
      );
      expect(() => service.freeContext(firstContextHandle), throwsStateError);
      expect(() => service.freeModel(firstModelHandle), throwsStateError);
      expect(
        service.getMetadata(secondModelHandle),
        containsPair('general.name', 'second.litertlm'),
      );
      expect(service.getContextSize(secondContextHandle), 4096);
    } finally {
      service.dispose();
    }
  });

  test('names a bundle whose path holds %, # and ? literally', () async {
    final service = LiteRtLmService();
    final name = Platform.isWindows
        ? 'gemma-4 100%#1.litertlm'
        : 'gemma-4 100%#?.litertlm';
    final bundle = File('${tempDir.path}/100% a#b%zz%25/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync('fake model');

    try {
      final modelHandle = await service.loadModel(
        bundle.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      expect(
        service.getMetadata(modelHandle),
        containsPair('general.name', name),
      );
    } finally {
      service.dispose();
    }
  });

  test('exposes Gemma 4 chat template metadata for Gemma 4 bundles', () async {
    final service = LiteRtLmService();
    final gemmaModelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
    await gemmaModelFile.writeAsString('fake model');

    try {
      final modelHandle = await service.loadModel(
        gemmaModelFile.path,
        const ModelParams(
          contextSize: 2048,
          chatTemplate: 'custom {{ message }}',
        ),
      );
      final metadata = service.getMetadata(modelHandle);

      expect(metadata, containsPair('general.name', 'gemma-4-E2B-it.litertlm'));
      expect(metadata, containsPair('llm.context_length', '2048'));
      expect(
        metadata,
        containsPair('tokenizer.chat_template', 'custom {{ message }}'),
      );
      expect(metadata, containsPair('tokenizer.ggml.bos_token', '<bos>'));
      expect(metadata, containsPair('tokenizer.ggml.eos_token', '<turn|>'));
    } finally {
      service.dispose();
    }
  });

  test('exposes the built-in Gemma 4 template when no override is set', () async {
    final service = LiteRtLmService();
    final gemmaModelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
    await gemmaModelFile.writeAsString('fake model');

    try {
      final modelHandle = await service.loadModel(
        gemmaModelFile.path,
        const ModelParams(contextSize: 2048),
      );
      final template = service.getMetadata(
        modelHandle,
      )['tokenizer.chat_template'];

      // The full canonical template renders tool declarations and the thinking
      // channel — unlike the previous stub, which omitted both.
      expect(template, isNotNull);
      expect(template, contains('format_function_declaration'));
      expect(template, contains('<|tool>'));
      expect(template, contains('<|think|>'));
      // The native runtime adds the start token, so the template must not emit
      // its own BOS (which would double it).
      expect(template, isNot(contains('bos_token')));
    } finally {
      service.dispose();
    }
  });

  test('renders with an empty load template instead of the built-in '
      'one', () async {
    final service = LiteRtLmService();
    final gemmaModelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
    await gemmaModelFile.writeAsString('fake model');

    try {
      final modelHandle = await service.loadModel(
        gemmaModelFile.path,
        const ModelParams(chatTemplate: ''),
      );

      expect(
        service.getMetadata(modelHandle),
        containsPair('tokenizer.chat_template', ''),
      );
      const messages = [
        {'role': 'user', 'content': 'hello'},
      ];
      final rendered = service.applyChatTemplate(modelHandle, messages);
      expect(rendered, isNot(contains('<|turn>')));
      expect(
        rendered,
        service.applyChatTemplate(modelHandle, messages, customTemplate: ''),
      );
    } finally {
      service.dispose();
    }
  });

  test('applies the parsing template in Dart', () async {
    const embedded = 'EMBEDDED {{ messages[0].content }}';
    final service = LiteRtLmService(readBundleChatTemplate: (_) => embedded);
    final gemmaModelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
    await gemmaModelFile.writeAsString('fake model');

    try {
      final modelHandle = await service.loadModel(
        gemmaModelFile.path,
        const ModelParams(contextSize: 2048),
      );
      expect(
        service.getMetadata(modelHandle),
        containsPair('tokenizer.chat_template', embedded),
      );

      final rendered = service.applyChatTemplate(modelHandle, const [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hello'},
          ],
        },
      ]);

      expect(rendered, contains('<|turn>user\nhello<turn|>'));
      // Thinking is enabled by default: the canonical template emits a
      // `<|think|>` system block and leaves the model turn open.
      expect(rendered, contains('<|turn>system\n<|think|>\n<turn|>'));
      expect(rendered, endsWith('<|turn>model\n'));

      final custom = service.applyChatTemplate(
        modelHandle,
        const [
          {'role': 'user', 'content': 'hello'},
        ],
        customTemplate:
            '{{ messages[0]["role"] }}:{{ messages[0]["content"] }}'
            '{% if add_generation_prompt %}:assistant{% endif %}',
      );
      expect(custom, 'user:hello:assistant');

      expect(
        () => service.applyChatTemplate(modelHandle, const [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'describe this'},
              {
                'type': 'image_url',
                'image_url': {'url': 'file:///tmp/image.png'},
              },
            ],
          },
        ]),
        throwsUnsupportedError,
      );

      final mappedContent = service.applyChatTemplate(modelHandle, const [
        {
          'role': 'user',
          'content': {'type': 'text', 'text': 'mapped'},
        },
        {
          'role': 'user',
          'content': {'type': 'custom', 'value': 7},
        },
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'part'},
            ' tail',
            {'type': 'custom', 'value': 1},
          ],
        },
        {'role': 'user', 'content': 42},
      ]);

      expect(mappedContent, contains('<|turn>user\nmapped<turn|>'));
      expect(
        mappedContent,
        contains('<|turn>user\n{type: custom, value: 7}<turn|>'),
      );
      expect(
        mappedContent,
        contains('<|turn>user\npart tail{type: custom, value: 1}<turn|>'),
      );
      expect(mappedContent, contains('<|turn>user\n42<turn|>'));

      expect(
        () => service.applyChatTemplate(modelHandle, const [
          {
            'role': 'user',
            'content': {'type': 'input_audio', 'data': '...'},
          },
        ]),
        throwsUnsupportedError,
      );
    } finally {
      service.dispose();
    }
  });

  test('resolves LiteRT-LM backend preference from model params', () async {
    final service = LiteRtLmService();
    final throwsUnavailableGpu = liteRtLmGateAbi() == Abi.macosX64
        ? throwsA(isA<LlamaUnsupportedException>())
        : throwsArgumentError;

    try {
      var modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(),
      );
      expect(
        service.getActiveBackendName(),
        'LiteRT-LM ${_expectedAutoLiteRtLmBackend()}',
      );
      service.freeModel(modelHandle);

      modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(preferredBackend: GpuBackend.blas),
      );
      expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
      service.freeModel(modelHandle);

      final gpuLikeBackends = <GpuBackend>[
        GpuBackend.vulkan,
        GpuBackend.metal,
        GpuBackend.cuda,
        GpuBackend.opencl,
        GpuBackend.hip,
      ];
      for (final preferredBackend in gpuLikeBackends) {
        if (service.getAvailableBackendInfo().contains('gpu')) {
          modelHandle = await service.loadModel(
            modelFile.path,
            ModelParams(preferredBackend: preferredBackend),
          );
          expect(service.getActiveBackendName(), 'LiteRT-LM gpu');
          service.freeModel(modelHandle);
        } else {
          expect(
            () => service.loadModel(
              modelFile.path,
              ModelParams(preferredBackend: preferredBackend),
            ),
            throwsUnavailableGpu,
          );
        }
      }

      modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(gpuLayers: 0),
      );
      expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
      expect(service.getResolvedGpuLayers(), 0);
      service.freeModel(modelHandle);

      modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(),
        backendOverride: ' CPU ',
      );
      expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
      expect(service.getResolvedGpuLayers(), 0);
      service.freeModel(modelHandle);

      modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(
          preferredBackend: GpuBackend.metal,
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        ),
      );
      expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
      service.freeModel(modelHandle);

      if (service.getAvailableBackendInfo().contains('gpu')) {
        modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
        );
        expect(service.getActiveBackendName(), 'LiteRT-LM gpu');
        service.freeModel(modelHandle);
      } else {
        expect(
          () => service.loadModel(
            modelFile.path,
            const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
          ),
          throwsUnavailableGpu,
        );
      }

      if (Platform.isAndroid) {
        modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.npu),
        );
        expect(service.getActiveBackendName(), 'LiteRT-LM npu');
      } else {
        expect(
          () => service.loadModel(
            modelFile.path,
            const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.npu),
          ),
          throwsArgumentError,
        );
      }
    } finally {
      service.dispose();
    }
  });

  group('macOS ABI GPU selection', () {
    void runOn(Abi abi) {
      debugLiteRtLmAbiOverride = abi;
      addTearDown(() => debugLiteRtLmAbiOverride = null);
    }

    final macOsX64Gpu = throwsA(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        contains('LiteRT-LM GPU is not available on macOS x86_64'),
      ),
    );

    test('macOS arm64 auto selection loads GPU', () async {
      runOn(Abi.macosArm64);
      final service = LiteRtLmService(
        clientFactory: () => _FakeLiteRtLmRuntimeClient(),
      );
      try {
        expect(service.getGpuSupport(), isTrue);
        final model = await service.loadModel(
          modelFile.path,
          const ModelParams(),
        );
        expect(service.getActiveBackendName(), 'LiteRT-LM gpu');
        expect(service.getResolvedGpuLayers(), ModelParams.maxGpuLayers);
        service.freeModel(model);

        await service.loadModel(
          modelFile.path,
          const ModelParams(device: ComputeDevice.gpu),
        );
        expect(service.getActiveBackendName(), 'LiteRT-LM gpu');
      } finally {
        service.dispose();
      }
    });

    test('macOS x86_64 auto selection loads CPU', () async {
      runOn(Abi.macosX64);
      final service = LiteRtLmService(
        clientFactory: () => _FakeLiteRtLmRuntimeClient(),
      );
      try {
        expect(service.getGpuSupport(), isFalse);
        expect(service.getAvailableBackendInfo(), const ['cpu']);
        expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
        final model = await service.loadModel(
          modelFile.path,
          const ModelParams(),
        );
        expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
        expect(service.getResolvedGpuLayers(), 0);
        service.freeModel(model);
      } finally {
        service.dispose();
      }
    });

    test('macOS x86_64 GPU requests throw LlamaUnsupportedException', () async {
      runOn(Abi.macosX64);
      final service = LiteRtLmService(
        clientFactory: () => _FakeLiteRtLmRuntimeClient(),
      );
      try {
        for (final params in const [
          ModelParams(device: ComputeDevice.gpu),
          ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
          ModelParams(preferredBackend: GpuBackend.metal),
        ]) {
          await expectLater(
            service.loadModel(modelFile.path, params),
            macOsX64Gpu,
            reason: '$params',
          );
        }
        await expectLater(
          service.loadModel(
            modelFile.path,
            const ModelParams(),
            backendOverride: 'gpu',
          ),
          macOsX64Gpu,
        );

        final model = await service.loadModel(
          modelFile.path,
          const ModelParams(device: ComputeDevice.cpu),
        );
        expect(
          () => service.createContext(
            model,
            const ModelParams(device: ComputeDevice.gpu),
          ),
          macOsX64Gpu,
        );
      } finally {
        service.dispose();
      }
    });
  });

  group('ModelParams.device', () {
    Matcher unsupported(List<String> parts) => throwsA(
      isA<LlamaUnsupportedException>().having(
        (e) => e.message,
        'message',
        allOf([for (final part in parts) contains(part)]),
      ),
    );

    test('selects the LiteRT-LM backend it names', () async {
      late _FakeLiteRtLmRuntimeClient client;
      final service = LiteRtLmService(
        clientFactory: () => client = _FakeLiteRtLmRuntimeClient(),
      );
      try {
        for (final (device, backend) in [
          (ComputeDevice.cpu, 'cpu'),
          if (service.getAvailableBackendInfo().contains('gpu'))
            (ComputeDevice.gpu, 'gpu'),
        ]) {
          final params = ModelParams(device: device);
          final model = await service.loadModel(modelFile.path, params);
          service.createContext(model, params);
          await service.tokenize(model, 'hi', true);

          expect(service.getActiveBackendName(), 'LiteRT-LM $backend');
          expect(client.lastBackend, backend);
          service.freeModel(model);
        }
      } finally {
        service.dispose();
      }
    });

    test('an unavailable device throws LlamaUnsupportedException', () async {
      final service = LiteRtLmService();
      try {
        for (final device in [
          if (!Platform.isAndroid) ComputeDevice.npu,
          if (!service.getAvailableBackendInfo().contains('gpu'))
            ComputeDevice.gpu,
        ]) {
          await expectLater(
            service.loadModel(modelFile.path, ModelParams(device: device)),
            unsupported(
              device == ComputeDevice.gpu && liteRtLmGateAbi() == Abi.macosX64
                  ? ['LiteRT-LM GPU is not available on macOS x86_64']
                  : ['ComputeDevice.${device.name}', Platform.operatingSystem],
            ),
          );
        }
      } finally {
        service.dispose();
      }
    });

    test('an explicit device rejects the deprecated constructor '
        'preferredBackend', () async {
      final service = LiteRtLmService();
      try {
        await expectLater(
          service.loadModel(
            modelFile.path,
            const ModelParams(device: ComputeDevice.cpu),
            backendOverride: 'cpu',
          ),
          unsupported(['Set only ModelParams.device']),
        );
      } finally {
        service.dispose();
      }
    });

    test('a GPU engine that fails to start throws '
        'LlamaUnsupportedException, and LlamaModelException under auto when '
        'the CPU fails too', () async {
      if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
        markTestSkipped('No LiteRT-LM GPU backend on this platform.');
        return;
      }
      for (final device in [ComputeDevice.gpu, ComputeDevice.auto]) {
        final service = LiteRtLmService(
          clientFactory: () => _FakeLiteRtLmRuntimeClient(
            initializeError: LiteRtLmEngineCreateError('delegate init failed.'),
          ),
          // No cache directory is passed, so the message names none.
          useTempCacheDir: false,
        );
        try {
          final params = ModelParams(
            device: device,
            preferredBackend: GpuBackend.metal,
          );
          final model = await service.loadModel(modelFile.path, params);
          service.createContext(model, params);

          await expectLater(
            service.tokenize(model, 'hi', true),
            device == ComputeDevice.gpu
                ? unsupported([
                    'ComputeDevice.gpu',
                    'gpu engine',
                    Platform.operatingSystem,
                    'model file',
                    'delegate init failed. Load with ComputeDevice.cpu',
                  ])
                : throwsA(
                    isA<LlamaModelException>().having(
                      (error) => error.message,
                      'message',
                      'delegate init failed.',
                    ),
                  ),
          );
        } finally {
          service.dispose();
        }
      }
    });

    test('an engine that fails to start with a caller-supplied cache '
        'directory names it as a possible cause', () async {
      for (final device in [
        ComputeDevice.cpu,
        if (liteRtLmNativeGpuSupportedOnCurrentPlatform()) ComputeDevice.gpu,
      ]) {
        final service = LiteRtLmService(
          clientFactory: () => _FakeLiteRtLmRuntimeClient(
            initializeError: LiteRtLmEngineCreateError('no engine.'),
          ),
        );
        try {
          final params = ModelParams(
            device: device,
            liteRtLmCacheDir: '${tempDir.path}/cache',
          );
          final model = await service.loadModel(modelFile.path, params);
          service.createContext(model, params);

          await expectLater(
            service.tokenize(model, 'hi', true),
            throwsA(
              isA<LlamaException>()
                  .having(
                    (error) => error,
                    'type',
                    device == ComputeDevice.gpu
                        ? isA<LlamaUnsupportedException>()
                        : isA<LlamaModelException>(),
                  )
                  .having(
                    (error) => error.message,
                    'message',
                    contains(
                      'no engine. Engine creation also fails when the '
                      'runtime cannot write ModelParams.liteRtLmCacheDir.',
                    ),
                  ),
            ),
          );
        } finally {
          service.dispose();
        }
      }
    });

    test('the cache-directory hint names the option as '
        'LiteRtLmModelParams spells it', () async {
      final service = LiteRtLmService(
        clientFactory: () => _FakeLiteRtLmRuntimeClient(
          initializeError: LiteRtLmEngineCreateError('no engine.'),
        ),
      );
      try {
        final params = LiteRtLmModelParams(
          device: ComputeDevice.cpu,
          cacheDir: '${tempDir.path}/cache',
        );
        final model = await service.loadModel(modelFile.path, params);
        service.createContext(model, params);

        await expectLater(
          service.tokenize(model, 'hi', true),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              contains('write LiteRtLmModelParams.cacheDir.'),
            ),
          ),
        );
      } finally {
        service.dispose();
      }
    });

    for (final linked in [false, true]) {
      test('an engine that fails to start with '
          '${linked ? "a linked bundle's directory" : 'the default temp '
                    'directory'} as its cache directory names a cache '
          'directory as a possible cause', () async {
        final service = LiteRtLmService(
          clientFactory: () => _FakeLiteRtLmRuntimeClient(
            initializeError: LiteRtLmEngineCreateError('no engine.'),
          ),
          linkParentDirectory: await Directory(
            '${tempDir.path}/links',
          ).create(),
          useTempCacheDir: !linked,
        );
        final extensionless = File('${tempDir.path}/download');
        await extensionless.writeAsString('LITERTLM fake model');
        try {
          const params = ModelParams(device: ComputeDevice.cpu);
          final model = await service.loadModel(
            linked ? extensionless.path : modelFile.path,
            params,
          );
          service.createContext(model, params);

          await expectLater(
            service.tokenize(model, 'hi', true),
            throwsA(
              isA<LlamaModelException>().having(
                (error) => error.message,
                'message',
                'no engine. Engine creation also fails when the runtime '
                    'cannot write its cache directory; set '
                    'LiteRtLmModelParams.cacheDir '
                    '(ModelParams.liteRtLmCacheDir) to one it can write.',
              ),
            ),
          );
        } finally {
          service.dispose();
        }
      }, testOn: '!windows');
    }

    for (final fails in [false, true]) {
      test('a linked bundle in a directory the process cannot write runs '
          'uncached${fails ? ', and its failed engine names no cache '
                    'directory' : ''}', () async {
        final client = _FakeLiteRtLmRuntimeClient(
          initializeError: fails
              ? LiteRtLmEngineCreateError('no engine.')
              : null,
        );
        final service = LiteRtLmService(
          clientFactory: () => client,
          linkParentDirectory: await Directory(
            '${tempDir.path}/links',
          ).create(),
          useTempCacheDir: false,
        );
        final models = await Directory('${tempDir.path}/models').create();
        final extensionless = File('${models.path}/download');
        await extensionless.writeAsString('LITERTLM fake model');
        if (!makeReadOnly(models)) {
          markTestSkipped(
            'This user writes a directory without write permission.',
          );
          service.dispose();
          return;
        }
        try {
          const params = ModelParams(device: ComputeDevice.cpu);
          final model = await service.loadModel(extensionless.path, params);
          service.createContext(model, params);

          final tokenized = service.tokenize(model, 'hi', true);
          if (fails) {
            await expectLater(
              tokenized,
              throwsA(
                isA<LlamaModelException>().having(
                  (error) => error.message,
                  'message',
                  'no engine.',
                ),
              ),
            );
          } else {
            await tokenized;
          }
          expect(
            await Link(client.lastModelPath!).target(),
            extensionless.absolute.path,
          );
          expect(client.lastCacheDir, ':nocache');
        } finally {
          service.dispose();
        }
      }, testOn: '!windows');
    }

    test('a caller-supplied cache directory the process cannot write is '
        'still passed to the runtime and named when the engine '
        'fails', () async {
      final client = _FakeLiteRtLmRuntimeClient(
        initializeError: LiteRtLmEngineCreateError('no engine.'),
      );
      final service = LiteRtLmService(
        clientFactory: () => client,
        linkParentDirectory: await Directory('${tempDir.path}/links').create(),
        useTempCacheDir: false,
      );
      final models = await Directory('${tempDir.path}/models').create();
      final extensionless = File('${models.path}/download');
      await extensionless.writeAsString('LITERTLM fake model');
      final cacheDir = await Directory('${tempDir.path}/cache').create();
      makeReadOnly(models);
      makeReadOnly(cacheDir);
      try {
        final params = ModelParams(
          device: ComputeDevice.cpu,
          liteRtLmCacheDir: cacheDir.path,
        );
        final model = await service.loadModel(extensionless.path, params);
        service.createContext(model, params);

        await expectLater(
          service.tokenize(model, 'hi', true),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              'no engine. Engine creation also fails when the runtime '
                  'cannot write ModelParams.liteRtLmCacheDir.',
            ),
          ),
        );
        expect(client.lastCacheDir, cacheDir.path);
      } finally {
        service.dispose();
      }
    }, testOn: '!windows');

    test('a GPU load whose runtime library cannot open keeps the runtime '
        'error', () async {
      if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
        markTestSkipped('No LiteRT-LM GPU backend on this platform.');
        return;
      }
      final service = LiteRtLmService(
        clientFactory: () => _FakeLiteRtLmRuntimeClient(
          initializeError: ArgumentError('Failed to load dynamic library'),
        ),
      );
      try {
        const params = ModelParams(device: ComputeDevice.gpu);
        final model = await service.loadModel(modelFile.path, params);
        service.createContext(model, params);

        await expectLater(
          service.tokenize(model, 'hi', true),
          throwsArgumentError,
        );
      } finally {
        service.dispose();
      }
    });
  });

  test('treats negative gpuLayers as every layer, not the CPU', () async {
    final service = LiteRtLmService();
    final throwsUnavailableGpu = liteRtLmGateAbi() == Abi.macosX64
        ? throwsA(isA<LlamaUnsupportedException>())
        : throwsArgumentError;

    try {
      for (final gpuLayers in [-1, -2]) {
        var modelHandle = await service.loadModel(
          modelFile.path,
          ModelParams(gpuLayers: gpuLayers),
        );
        expect(
          service.getActiveBackendName(),
          'LiteRT-LM ${_expectedAutoLiteRtLmBackend()}',
        );
        service.freeModel(modelHandle);

        final metal = ModelParams(
          gpuLayers: gpuLayers,
          preferredBackend: GpuBackend.metal,
        );
        if (service.getAvailableBackendInfo().contains('gpu')) {
          modelHandle = await service.loadModel(modelFile.path, metal);
          expect(service.getActiveBackendName(), 'LiteRT-LM gpu');
          expect(service.getResolvedGpuLayers(), ModelParams.maxGpuLayers);
          service.freeModel(modelHandle);
        } else {
          expect(
            () => service.loadModel(modelFile.path, metal),
            throwsUnavailableGpu,
          );
        }

        modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(gpuLayers: 0),
        );
        expect(
          () => service.createContext(modelHandle, metal),
          anyOf(throwsArgumentError, throwsUnavailableGpu),
        );
        service.freeModel(modelHandle);
      }
    } finally {
      service.dispose();
    }
  });

  test('rejects explicit backend changes during context creation', () async {
    final service = LiteRtLmService();

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(gpuLayers: 0),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(gpuLayers: 0),
      );

      expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
      expect(service.getContextSize(contextHandle), 4096);
      service.freeContext(contextHandle);

      if (service.getAvailableBackendInfo().contains('gpu')) {
        expect(
          () => service.createContext(
            modelHandle,
            const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              allOf(contains('cannot change'), contains('cpu to gpu')),
            ),
          ),
        );
      }

      expect(
        () => service.createContext(
          modelHandle,
          const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.npu),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            Platform.isAndroid
                ? allOf(contains('cannot change'), contains('cpu to npu'))
                : contains('not available'),
          ),
        ),
      );
    } finally {
      service.dispose();
    }
  });

  test('rejects unsupported LiteRT-LM load-time model params', () async {
    final service = LiteRtLmService();

    try {
      await expectLater(
        () =>
            service.loadModel(modelFile.path, const ModelParams(gpuLayers: 12)),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('gpuLayers=12'),
          ),
        ),
      );

      await expectLater(
        () => service.loadModel(
          modelFile.path,
          const ModelParams(contextSize: 0),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('contextSize=0'),
          ),
        ),
      );

      await expectLater(
        () => service.loadModel(
          modelFile.path,
          const ModelParams(
            gpuLayers: 12,
            liteRtLmBackend: LiteRtLmBackendPreference.gpu,
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('gpuLayers=12'),
          ),
        ),
      );

      await expectLater(
        () => service.loadModel(
          modelFile.path,
          const ModelParams(batchSize: 128, useMlock: true),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('batchSize'), contains('useMlock')),
          ),
        ),
      );

      await expectLater(
        () => service.loadModel(
          modelFile.path,
          const ModelParams(
            splitMode: ModelSplitMode.none,
            mainGpu: 1,
            loras: [
              LoraAdapterConfig(path: 'adapter-a.bin'),
              LoraAdapterConfig(path: 'adapter-b.bin', scale: 0.5),
            ],
            numberOfThreadsBatch: 3,
            microBatchSize: 64,
            maxParallelSequences: 2,
            useMmap: false,
            flashAttention: FlashAttention.enabled,
            cacheTypeK: KvCacheType.q8_0,
            cacheTypeV: KvCacheType.q4_0,
            kvUnified: true,
            ropeFrequencyBase: 10000,
            ropeFrequencyScale: 1.0,
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            predicate<String>(
              (message) => const <String>[
                'splitMode',
                'mainGpu',
                'loras.length=2',
                'loras.scale',
                'numberOfThreadsBatch',
                'microBatchSize',
                'maxParallelSequences',
                'useMmap=false',
                'flashAttention',
                'cacheTypeK',
                'cacheTypeV',
                'kvUnified',
                'ropeFrequencyBase',
                'ropeFrequencyScale',
              ].every(message.contains),
              'contains every unsupported ModelParams field',
            ),
          ),
        ),
      );

      expect(
        () => service.loadModel(
          modelFile.path,
          const ModelParams(),
          backendOverride: 'directml',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(contains('must be cpu, gpu, or npu'), contains('directml')),
          ),
        ),
      );

      expect(
        service.getActiveBackendName(),
        'LiteRT-LM ${_expectedAutoLiteRtLmBackend()}',
      );
    } finally {
      service.dispose();
    }
  });

  test('reports platform default backend diagnostics before load', () {
    final service = LiteRtLmService();

    try {
      final expectedBackend = _expectedAutoLiteRtLmBackend();
      expect(service.getActiveBackendName(), 'LiteRT-LM $expectedBackend');
      expect(
        service.getResolvedGpuLayers(),
        expectedBackend == 'cpu' ? 0 : ModelParams.maxGpuLayers,
      );
    } finally {
      service.dispose();
    }
  });

  test('loads a bundle by its header whatever its file name', () async {
    final client = _FakeLiteRtLmRuntimeClient();
    final links = await Directory('${tempDir.path}/links').create();
    final service = LiteRtLmService(
      clientFactory: () => client,
      linkParentDirectory: links,
    );
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);
    final extensionless = File('${tempDir.path}/download');
    await extensionless.writeAsString('LITERTLM fake model');
    final ggufContent = File('${tempDir.path}/mislabelled.litertlm');
    await ggufContent.writeAsString('GGUF fake model');
    final unknownContent = File('${tempDir.path}/blob');
    await unknownContent.writeAsString('fake model');

    try {
      await expectLater(
        service.loadModel(ggufContent.path, params),
        throwsArgumentError,
      );
      await expectLater(
        service.loadModel(unknownContent.path, params),
        throwsArgumentError,
      );
      expect(links.listSync(), isEmpty);

      final model = await service.loadModel(extensionless.path, params);
      expect(service.getMetadata(model)['general.name'], 'download');
      final context = service.createContext(model, params);
      final pending = service.generateChat(context, const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
      ], const GenerationParams(maxTokens: 8)).toList();
      await client.generateStarted.future;
      await client.generated.close();
      await pending;

      final runtimePath = client.lastModelPath!;
      expect(runtimePath, endsWith('.litertlm'));
      expect(File(runtimePath).parent.parent.path, links.path);
      expect(await Link(runtimePath).target(), extensionless.absolute.path);

      final reloaded = await service.loadModel(extensionless.path, params);
      expect(Link(runtimePath).existsSync(), isFalse);
      expect(links.listSync(), hasLength(1));

      service.freeModel(reloaded);
      expect(links.listSync(), isEmpty);

      await service.loadModel(extensionless.path, params);
      expect(links.listSync(), hasLength(1));
      await service.loadModel(modelFile.path, params);
      expect(links.listSync(), isEmpty);

      await service.loadModel(extensionless.path, params);
      service.dispose();
      expect(links.listSync(), isEmpty);
      expect(extensionless.existsSync(), isTrue);
    } finally {
      service.dispose();
    }
  }, testOn: '!windows');

  Future<void> startEngine(
    LiteRtLmService service,
    _FakeLiteRtLmRuntimeClient client,
    int model,
    ModelParams params, {
    GenerationParams generation = const GenerationParams(maxTokens: 8),
  }) async {
    final context = service.createContext(model, params);
    final pending = service.generateChat(context, const [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
    ], generation).toList();
    await client.generateStarted.future;
    await client.generated.close();
    await pending;
  }

  for (final (useTempCacheDir, configured) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    test('linked bundle cache directory, temp default $useTempCacheDir, '
        'configured $configured', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(
        clientFactory: () => client,
        linkParentDirectory: await Directory('${tempDir.path}/links').create(),
        useTempCacheDir: useTempCacheDir,
      );
      final models = await Directory('${tempDir.path}/models').create();
      final extensionless = File('${models.path}/download');
      await extensionless.writeAsString('LITERTLM fake model');
      final configuredDir = '${tempDir.path}/cache';
      final params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        liteRtLmCacheDir: configured ? configuredDir : null,
      );

      try {
        final model = await service.loadModel(extensionless.path, params);
        await startEngine(service, client, model, params);

        expect(client.lastModelPath, isNot(extensionless.path));
        expect(
          client.lastCacheDir,
          configured
              ? configuredDir
              : useTempCacheDir
              ? '${Directory.systemTemp.path}/llamadart_litert_lm'
              : models.absolute.path,
        );
      } finally {
        service.dispose();
      }
    }, testOn: '!windows');
  }

  test('keeps no cache directory for an unlinked bundle by default', () async {
    final client = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(
      clientFactory: () => client,
      useTempCacheDir: false,
    );
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);

    try {
      final model = await service.loadModel(modelFile.path, params);
      await startEngine(service, client, model, params);

      expect(client.lastModelPath, modelFile.path);
      expect(client.lastCacheDir, isNull);
    } finally {
      service.dispose();
    }
  });

  /// A `.litertlm` bundle in a directory the process cannot write, with the
  /// GPU caches of its text model when [caches] is set, or null when this
  /// user writes such a directory anyway.
  Future<File?> readOnlyBundle({bool caches = false}) async {
    final models = await Directory('${tempDir.path}/models').create();
    final bundle = File('${models.path}/model.litertlm');
    await bundle.writeAsString('LITERTLM fake model');
    if (caches) writeLiteRtLmGpuTextCaches(bundle);
    if (!makeReadOnly(models)) {
      markTestSkipped('This user writes a directory without write permission.');
      return null;
    }
    return bundle;
  }

  for (final device in [ComputeDevice.cpu, ComputeDevice.gpu]) {
    for (final caches in [false, true]) {
      final uncached = device == ComputeDevice.gpu && !caches;
      test('an unlinked bundle in a directory the process cannot write '
          '${caches ? 'with' : 'without'} GPU caches runs '
          '${uncached ? 'uncached' : 'on the runtime cache default'} on '
          '${device.name}', () async {
        if (device == ComputeDevice.gpu &&
            !liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
          markTestSkipped('No LiteRT-LM GPU backend on this platform.');
          return;
        }
        final bundle = await readOnlyBundle(caches: caches);
        if (bundle == null) return;
        final entries = bundle.parent.listSync().map((e) => e.path).toSet();
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(
          clientFactory: () => client,
          useTempCacheDir: false,
        );
        try {
          final params = ModelParams(device: device);
          final model = await service.loadModel(bundle.path, params);
          await startEngine(service, client, model, params);

          expect(client.lastModelPath, bundle.path);
          expect(client.lastCacheDir, uncached ? ':nocache' : isNull);
          expect(bundle.parent.listSync().map((e) => e.path).toSet(), entries);
        } finally {
          service.dispose();
        }
      }, testOn: '!windows');
    }
  }

  test('an unlinked bundle in a directory the process cannot write runs a '
      'speculative GPU engine uncached despite its text GPU caches', () async {
    if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return;
    }
    final bundle = await readOnlyBundle(caches: true);
    if (bundle == null) return;
    final client = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(
      clientFactory: () => client,
      useTempCacheDir: false,
    );
    try {
      const params = ModelParams(device: ComputeDevice.gpu);
      final model = await service.loadModel(bundle.path, params);
      await startEngine(
        service,
        client,
        model,
        params,
        generation: const GenerationParams(
          maxTokens: 8,
          speculativeDecoding: true,
        ),
      );

      expect(client.lastSpeculativeDecoding, isTrue);
      expect(client.lastCacheDir, ':nocache');
    } finally {
      service.dispose();
    }
  }, testOn: '!windows');

  test('an unlinked bundle in a directory the process cannot write retries a '
      'GPU engine uncached when the runtime rejects its caches', () async {
    if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return;
    }
    final bundle = await readOnlyBundle(caches: true);
    if (bundle == null) return;
    final rejected = _FakeLiteRtLmRuntimeClient(
      initializeError: LiteRtLmEngineCreateError('bad cache.'),
    );
    final uncached = _FakeLiteRtLmRuntimeClient();
    final clients = [rejected, uncached];
    var nextClient = 0;
    final service = LiteRtLmService(
      clientFactory: () => clients[nextClient++],
      useTempCacheDir: false,
    );
    try {
      const params = ModelParams(device: ComputeDevice.gpu);
      final model = await service.loadModel(bundle.path, params);
      await startEngine(service, uncached, model, params);

      expect(nextClient, 2);
      expect(rejected.lastCacheDir, isNull);
      expect(rejected.disposeCount, 1);
      expect(uncached.lastCacheDir, ':nocache');
      expect(uncached.lastBackend, 'gpu');
    } finally {
      service.dispose();
    }
  }, testOn: '!windows');

  test('an unlinked bundle in a directory the process cannot write reports '
      'the first GPU engine error when the uncached retry fails too', () async {
    if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return;
    }
    final bundle = await readOnlyBundle(caches: true);
    if (bundle == null) return;
    final clients = [
      _FakeLiteRtLmRuntimeClient(
        initializeError: LiteRtLmEngineCreateError('bad cache.'),
      ),
      _FakeLiteRtLmRuntimeClient(
        initializeError: LiteRtLmEngineCreateError('no gpu.'),
      ),
    ];
    var nextClient = 0;
    final service = LiteRtLmService(
      clientFactory: () => clients[nextClient++],
      useTempCacheDir: false,
    );
    try {
      const params = ModelParams(device: ComputeDevice.gpu);
      final model = await service.loadModel(bundle.path, params);
      service.createContext(model, params);

      await expectLater(
        service.tokenize(model, 'hi', true),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('bad cache.'), isNot(contains('no gpu.'))),
          ),
        ),
      );
      expect(nextClient, 2);
      expect(clients.last.lastCacheDir, ':nocache');
    } finally {
      service.dispose();
    }
  }, testOn: '!windows');

  group('ComputeDevice.auto GPU engine fallback', () {
    final records = <LlamaLogRecord>[];

    setUp(() {
      records.clear();
      LlamaLogger.instance.setLevel(LlamaLogLevel.warn);
      LlamaLogger.instance.setHandler(records.add);
    });

    tearDown(() {
      LlamaLogger.instance.setLevel(LlamaLogLevel.none);
      LlamaLogger.instance.setHandler(null);
    });

    bool skipWithoutGpu() {
      if (liteRtLmNativeGpuSupportedOnCurrentPlatform()) return false;
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return true;
    }

    void expectOneFallbackWarning(Object gpuError) {
      expect(records, hasLength(1));
      expect(records.single.level, LlamaLogLevel.warn);
      expect(
        records.single.message,
        allOf(
          contains('ComputeDevice.auto'),
          contains('GPU engine'),
          contains('retrying on the CPU'),
          contains('ComputeDevice.cpu'),
        ),
      );
      expect(records.single.error, same(gpuError));
    }

    for (final (name, params) in [
      ('the platform default', const ModelParams()),
      (
        'a GPU preferredBackend hint',
        const ModelParams(preferredBackend: GpuBackend.metal),
      ),
    ]) {
      test('a GPU engine that fails to start under $name runs on the CPU '
          'with a warning', () async {
        if (skipWithoutGpu()) return;
        if (params.preferredBackend == GpuBackend.auto &&
            liteRtLmDefaultNativeBackendForCurrentPlatform() !=
                liteRtLmGpuBackend) {
          markTestSkipped('ComputeDevice.auto selects the CPU here.');
          return;
        }
        final gpuError = LiteRtLmEngineCreateError('delegate init failed.');
        final gpu = _FakeLiteRtLmRuntimeClient(initializeError: gpuError);
        final cpu = _FakeLiteRtLmRuntimeClient();
        final clients = [gpu, cpu];
        var nextClient = 0;
        final service = LiteRtLmService(
          clientFactory: () => clients[nextClient++],
          useTempCacheDir: false,
        );
        try {
          final model = await service.loadModel(modelFile.path, params);
          expect(service.getActiveBackendName(), 'LiteRT-LM gpu');
          await startEngine(service, cpu, model, params);

          expect(nextClient, 2);
          expect(gpu.lastBackend, 'gpu');
          expect(gpu.disposeCount, 1);
          expect(cpu.lastBackend, 'cpu');
          expect(cpu.lastVisionBackend, isNull);
          expect(cpu.lastAudioBackend, isNull);
          expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
          expect(service.getResolvedGpuLayers(), 0);
          expectOneFallbackWarning(gpuError);

          cpu.tokenizeResult = const [7];
          expect(await service.tokenize(model, 'again', true), [7]);
          expect(nextClient, 2);
        } finally {
          service.dispose();
        }
      });
    }

    for (final preference in [GpuBackend.auto, GpuBackend.metal]) {
      test('recreates a CPU fallback context with unchanged '
          '${preference.name} hints', () async {
        if (skipWithoutGpu()) return;
        if (preference == GpuBackend.auto &&
            liteRtLmDefaultNativeBackendForCurrentPlatform() !=
                liteRtLmGpuBackend) {
          markTestSkipped('ComputeDevice.auto selects the CPU here.');
          return;
        }
        final gpu = _FakeLiteRtLmRuntimeClient(
          initializeError: LiteRtLmEngineCreateError('no gpu.'),
        );
        final cpu = _FakeLiteRtLmRuntimeClient()..tokenizeResult = const [7];
        final recreated = _FakeLiteRtLmRuntimeClient()
          ..tokenizeResult = const [8];
        final clients = [gpu, cpu, recreated];
        var nextClient = 0;
        final service = LiteRtLmService(
          clientFactory: () => clients[nextClient++],
          useTempCacheDir: false,
        );
        try {
          final params = ModelParams(preferredBackend: preference);
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);
          expect(await service.tokenize(model, 'first', true), [7]);
          expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
          service.freeContext(context);
          for (final explicit in [
            const ModelParams(device: ComputeDevice.gpu),
            const ModelParams(device: ComputeDevice.npu),
            const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
            const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.npu),
          ]) {
            expect(
              () => service.createContext(model, explicit),
              throwsA(
                anyOf(isA<ArgumentError>(), isA<LlamaUnsupportedException>()),
              ),
            );
          }
          final cpuContext = service.createContext(
            model,
            const ModelParams(device: ComputeDevice.cpu, gpuLayers: 0),
          );
          service.freeContext(cpuContext);
          final second = service.createContext(model, params);
          expect(second, isNot(context));
          expect(await service.tokenize(model, 'second', true), [8]);
          expect(nextClient, 3);
          expect(gpu.lastBackend, 'gpu');
          expect(cpu.lastBackend, 'cpu');
          expect(cpu.disposeCount, 1);
          expect(recreated.lastBackend, 'cpu');
          expect(records, hasLength(1));
          service.freeContext(second);
          final cpuModel = await service.loadModel(
            modelFile.path,
            const ModelParams(gpuLayers: 0),
          );
          expect(
            () => service.createContext(
              cpuModel,
              const ModelParams(preferredBackend: GpuBackend.metal),
            ),
            throwsArgumentError,
          );
        } finally {
          service.dispose();
        }
      });
    }

    test('the CPU retry recomputes the cache directory for a CPU '
        'engine', () async {
      if (skipWithoutGpu()) return;
      final bundle = await readOnlyBundle();
      if (bundle == null) return;
      final gpuError = LiteRtLmEngineCreateError('no gpu.');
      final gpu = _FakeLiteRtLmRuntimeClient(initializeError: gpuError);
      final cpu = _FakeLiteRtLmRuntimeClient();
      final clients = [gpu, cpu];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
        useTempCacheDir: false,
      );
      try {
        const params = ModelParams(preferredBackend: GpuBackend.metal);
        final model = await service.loadModel(bundle.path, params);
        await startEngine(service, cpu, model, params);

        expect(nextClient, 2);
        expect(gpu.lastCacheDir, ':nocache');
        expect(cpu.lastBackend, 'cpu');
        expect(cpu.lastCacheDir, isNull);
        expectOneFallbackWarning(gpuError);
      } finally {
        service.dispose();
      }
    }, testOn: '!windows');

    test('the CPU retry after a working GPU audio engine runs the vision '
        'and audio executors on the CPU', () async {
      if (skipWithoutGpu()) return;
      final gpuAudio = _FakeLiteRtLmRuntimeClient();
      final gpuError = StateError('GPU engine is incompatible');
      final gpu = _FakeLiteRtLmRuntimeClient(initializeError: gpuError);
      final gpuWithCpuAudio = _FakeLiteRtLmRuntimeClient(
        initializeError: StateError('GPU vision executor is incompatible'),
      );
      final cpu = _FakeLiteRtLmRuntimeClient();
      final recreated = _FakeLiteRtLmRuntimeClient();
      final clients = [gpuAudio, gpu, gpuWithCpuAudio, cpu, recreated];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
        useTempCacheDir: false,
      );
      final imageFile = File('${tempDir.path}/fallback-image.png');
      await imageFile.writeAsBytes(const <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      List<LlamaChatMessage> media(int images) => [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            const LlamaTextContent('Describe the image and audio.'),
            for (var i = 0; i < images; i++)
              LlamaImageContent(path: imageFile.path),
            LlamaAudioContent(bytes: Uint8List.fromList(const <int>[1, 2, 3])),
          ],
        ),
      ];
      try {
        const params = ModelParams(preferredBackend: GpuBackend.metal);
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);

        final audioOnly = service
            .generateChat(
              context,
              media(0),
              const GenerationParams(maxTokens: 8),
            )
            .toList();
        await gpuAudio.generateStarted.future;
        await gpuAudio.generated.close();
        await audioOnly;
        expect(gpuAudio.lastBackend, 'gpu');
        expect(gpuAudio.lastAudioBackend, 'gpu');

        final chunks = service
            .generateChat(
              context,
              media(1),
              const GenerationParams(maxTokens: 8),
            )
            .toList();
        await cpu.generateStarted.future;
        await cpu.generated.close();
        await chunks;

        expect(gpu.lastBackend, 'gpu');
        expect(gpu.lastVisionBackend, 'gpu');
        expect(gpu.lastAudioBackend, 'gpu');
        expect(gpuWithCpuAudio.lastBackend, 'gpu');
        expect(gpuWithCpuAudio.lastAudioBackend, 'cpu');
        expect(cpu.lastBackend, 'cpu');
        expect(cpu.lastVisionBackend, 'cpu');
        expect(cpu.lastAudioBackend, 'cpu');
        expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
        expectOneFallbackWarning(gpuError);

        final again = service
            .generateChat(
              context,
              media(2),
              const GenerationParams(maxTokens: 8),
            )
            .toList();
        await recreated.generateStarted.future;
        await recreated.generated.close();
        await again;

        expect(nextClient, 5);
        expect(recreated.lastBackend, 'cpu');
        expect(recreated.lastVisionBackend, 'cpu');
        expect(recreated.lastAudioBackend, 'cpu');
        expect(records, hasLength(1));
      } finally {
        service.dispose();
      }
    });

    for (final (name, gpuError, cpuError, matcher)
        in <(String, Object, Object, Matcher Function(Object gpuError))>[
          (
            'an engine creation error',
            LiteRtLmEngineCreateError('delegate init failed.'),
            LiteRtLmEngineCreateError('cpu init failed.'),
            (_) => isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              'delegate init failed.',
            ),
          ),
          (
            'another error',
            StateError('GPU state is broken'),
            StateError('CPU state is broken'),
            same,
          ),
        ]) {
      test('a failed CPU retry rethrows the GPU error for $name', () async {
        if (skipWithoutGpu()) return;
        final clients = [
          _FakeLiteRtLmRuntimeClient(initializeError: gpuError),
          _FakeLiteRtLmRuntimeClient(initializeError: cpuError),
        ];
        var nextClient = 0;
        final service = LiteRtLmService(
          clientFactory: () => clients[nextClient++],
          useTempCacheDir: false,
        );
        try {
          const params = ModelParams(preferredBackend: GpuBackend.metal);
          final model = await service.loadModel(modelFile.path, params);
          service.createContext(model, params);

          await expectLater(
            service.tokenize(model, 'hi', true),
            throwsA(matcher(gpuError)),
          );
          expect(nextClient, 2);
          expect(clients.first.lastBackend, 'gpu');
          expect(clients.last.lastBackend, 'cpu');
          expect(service.getActiveBackendName(), 'LiteRT-LM gpu');
          expectOneFallbackWarning(gpuError);
        } finally {
          service.dispose();
        }
      });
    }

    // A failed GPU and CPU pair is not remembered, so a cause the caller can
    // clear, such as an unwritable cache directory, needs no reload (#1458).
    test('the next call after a failed CPU retry tries the GPU and the CPU '
        'again', () async {
      if (skipWithoutGpu()) return;
      final gpuError = LiteRtLmEngineCreateError('no gpu.');
      final retryGpuError = LiteRtLmEngineCreateError('still no gpu.');
      final clients = [
        _FakeLiteRtLmRuntimeClient(initializeError: gpuError),
        _FakeLiteRtLmRuntimeClient(
          initializeError: LiteRtLmEngineCreateError('no cpu.'),
        ),
        _FakeLiteRtLmRuntimeClient(initializeError: retryGpuError),
        _FakeLiteRtLmRuntimeClient()..tokenizeResult = const [7],
      ];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
        useTempCacheDir: false,
      );
      try {
        const params = ModelParams(preferredBackend: GpuBackend.metal);
        final model = await service.loadModel(modelFile.path, params);
        service.createContext(model, params);

        await expectLater(
          service.tokenize(model, 'hi', true),
          throwsA(isA<LlamaModelException>()),
        );
        expect(await service.tokenize(model, 'again', true), [7]);
        expect(nextClient, 4);
        expect(clients.map((client) => client.lastBackend), [
          'gpu',
          'cpu',
          'gpu',
          'cpu',
        ]);
        expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
        expect(records.map((record) => record.error), [
          same(gpuError),
          same(retryGpuError),
        ]);
      } finally {
        service.dispose();
      }
    });

    for (final (name, loadParams, contextParams, backendOverride, matcher)
        in <(String, ModelParams, ModelParams, String?, Matcher)>[
          (
            'ComputeDevice.gpu',
            const ModelParams(device: ComputeDevice.gpu),
            const ModelParams(device: ComputeDevice.gpu),
            null,
            isA<LlamaUnsupportedException>(),
          ),
          (
            'ComputeDevice.gpu in the context only',
            const ModelParams(preferredBackend: GpuBackend.metal),
            const ModelParams(device: ComputeDevice.gpu),
            null,
            isA<LlamaUnsupportedException>(),
          ),
          (
            'ComputeDevice.gpu at load with an automatic context',
            const ModelParams(device: ComputeDevice.gpu),
            const ModelParams(),
            null,
            isA<LlamaModelException>(),
          ),
          (
            'the deprecated liteRtLmBackend gpu',
            const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
            const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
            null,
            isA<LlamaModelException>(),
          ),
          (
            'the deprecated liteRtLmBackend gpu at load only',
            const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
            const ModelParams(),
            null,
            isA<LlamaModelException>(),
          ),
          (
            'the deprecated liteRtLmBackend gpu in the context only',
            const ModelParams(preferredBackend: GpuBackend.metal),
            const ModelParams(
              preferredBackend: GpuBackend.metal,
              liteRtLmBackend: LiteRtLmBackendPreference.gpu,
            ),
            null,
            isA<LlamaModelException>(),
          ),
          (
            'the deprecated LiteRtLmBackend preferredBackend gpu',
            const ModelParams(),
            const ModelParams(),
            'gpu',
            isA<LlamaModelException>(),
          ),
        ]) {
      test('a GPU engine that fails to start under $name is not retried on '
          'the CPU', () async {
        if (skipWithoutGpu()) return;
        final clients = [
          _FakeLiteRtLmRuntimeClient(
            initializeError: LiteRtLmEngineCreateError('no gpu.'),
          ),
          _FakeLiteRtLmRuntimeClient(),
        ];
        var nextClient = 0;
        final service = LiteRtLmService(
          clientFactory: () => clients[nextClient++],
          useTempCacheDir: false,
        );
        try {
          final model = await service.loadModel(
            modelFile.path,
            loadParams,
            backendOverride: backendOverride,
          );
          service.createContext(model, contextParams);

          await expectLater(
            service.tokenize(model, 'hi', true),
            throwsA(matcher),
          );
          expect(nextClient, 1);
          expect(clients.first.lastBackend, 'gpu');
          expect(service.getActiveBackendName(), 'LiteRT-LM gpu');
          expect(records, isEmpty);
        } finally {
          service.dispose();
        }
      });
    }

    test('a CPU engine that fails to start under ComputeDevice.auto is not '
        'retried', () async {
      final clients = [
        _FakeLiteRtLmRuntimeClient(
          initializeError: LiteRtLmEngineCreateError('no cpu.'),
        ),
        _FakeLiteRtLmRuntimeClient(),
      ];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
        useTempCacheDir: false,
      );
      try {
        const params = ModelParams(gpuLayers: 0);
        final model = await service.loadModel(modelFile.path, params);
        service.createContext(model, params);

        await expectLater(
          service.tokenize(model, 'hi', true),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              'no cpu.',
            ),
          ),
        );
        expect(nextClient, 1);
        expect(clients.first.lastBackend, 'cpu');
        expect(records, isEmpty);
      } finally {
        service.dispose();
      }
    });
  });

  group('GPU loads on software Vulkan adapters', () {
    final records = <LlamaLogRecord>[];
    const llvmpipe = LiteRtLmVulkanAdapter(
      name: 'llvmpipe (LLVM 20.1.2, 256 bits)',
      deviceType: vulkanPhysicalDeviceTypeCpu,
    );
    const discreteGpu = LiteRtLmVulkanAdapter(name: 'NVIDIA L4', deviceType: 2);
    const softwareOnly = LiteRtLmVulkanAdapters.devices([llvmpipe]);
    var probes = 0;

    setUp(() {
      records.clear();
      probes = 0;
      LlamaLogger.instance.setLevel(LlamaLogLevel.warn);
      LlamaLogger.instance.setHandler(records.add);
    });

    tearDown(() {
      LlamaLogger.instance.setLevel(LlamaLogLevel.none);
      LlamaLogger.instance.setHandler(null);
    });

    bool skipWithoutGpu() {
      if (liteRtLmNativeGpuSupportedOnCurrentPlatform()) return false;
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return true;
    }

    LiteRtLmService serviceWith(
      _FakeLiteRtLmRuntimeClient client,
      LiteRtLmVulkanAdapters adapters,
    ) => LiteRtLmService(
      clientFactory: () => client,
      useTempCacheDir: false,
      probeGpuAdapters: () {
        probes++;
        return adapters;
      },
    );

    for (final (name, params, backendOverride) in [
      ('ComputeDevice.gpu', const ModelParams(device: ComputeDevice.gpu), null),
      (
        'LiteRtLmBackendPreference.gpu',
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
        null,
      ),
      ('the deprecated gpu backend override', const ModelParams(), 'gpu'),
    ]) {
      test('$name fails to load with a typed error', () async {
        if (skipWithoutGpu()) return;
        final client = _FakeLiteRtLmRuntimeClient();
        final service = serviceWith(client, softwareOnly);
        try {
          await expectLater(
            service.loadModel(
              modelFile.path,
              params,
              backendOverride: backendOverride,
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                allOf(
                  contains('LiteRT-LM GPU on ${liteRtLmGateAbi()} needs'),
                  contains('needs a hardware Vulkan device'),
                  contains('"llvmpipe (LLVM 20.1.2, 256 bits)"'),
                  contains('VK_PHYSICAL_DEVICE_TYPE_CPU'),
                  contains('ComputeDevice.cpu'),
                ),
              ),
            ),
          );
          expect(probes, 1);
          expect(client.lastBackend, isNull);
          expect(records, isEmpty);
        } finally {
          service.dispose();
        }
      });
    }

    test('a ComputeDevice.auto GPU hint runs on the CPU with a '
        'warning', () async {
      if (skipWithoutGpu()) return;
      final client = _FakeLiteRtLmRuntimeClient();
      final service = serviceWith(client, softwareOnly);
      try {
        const params = ModelParams(preferredBackend: GpuBackend.vulkan);
        final model = await service.loadModel(modelFile.path, params);
        expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
        await startEngine(service, client, model, params);

        expect(client.lastBackend, 'cpu');
        expect(records, hasLength(1));
        expect(records.single.level, LlamaLogLevel.warn);
        expect(
          records.single.message,
          allOf(
            contains('only software Vulkan devices'),
            contains('"llvmpipe (LLVM 20.1.2, 256 bits)"'),
            contains('ComputeDevice.auto'),
            contains('running on the CPU'),
          ),
        );
      } finally {
        service.dispose();
      }
    });

    for (final (name, adapters) in [
      (
        'a hardware adapter beside llvmpipe',
        const LiteRtLmVulkanAdapters.devices([llvmpipe, discreteGpu]),
      ),
      ('no listed adapter', const LiteRtLmVulkanAdapters.devices([])),
      (
        'an unavailable probe',
        const LiteRtLmVulkanAdapters.unavailable('no loader'),
      ),
    ]) {
      test('ComputeDevice.gpu with $name starts a GPU engine', () async {
        if (skipWithoutGpu()) return;
        final client = _FakeLiteRtLmRuntimeClient();
        final service = serviceWith(client, adapters);
        try {
          const params = ModelParams(device: ComputeDevice.gpu);
          final model = await service.loadModel(modelFile.path, params);
          await startEngine(service, client, model, params);

          expect(probes, 1);
          expect(client.lastBackend, 'gpu');
          expect(records, isEmpty);
        } finally {
          service.dispose();
        }
      });
    }

    group('default probe selection', () {
      var systemProbes = 0;

      setUp(() {
        systemProbes = 0;
        debugLiteRtLmSystemVulkanAdaptersOverride = () {
          systemProbes++;
          return softwareOnly;
        };
      });

      tearDown(() {
        debugLiteRtLmSystemVulkanAdaptersOverride = null;
        debugLiteRtLmAbiOverride = null;
      });

      test('a Linux service with the production client probes the system '
          'loader', () async {
        debugLiteRtLmAbiOverride = Abi.linuxX64;
        final service = LiteRtLmService(useTempCacheDir: false);
        try {
          await expectLater(
            service.loadModel(
              modelFile.path,
              const ModelParams(device: ComputeDevice.gpu),
            ),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          expect(systemProbes, 1);
        } finally {
          service.dispose();
        }
      });

      for (final (name, abi, injected) in [
        ('a macOS service', Abi.macosArm64, null),
        ('a Windows service', Abi.windowsX64, null),
        ('a Linux service with a client factory', Abi.linuxX64, 'legacy'),
        (
          'a Linux service with a runtime client factory',
          Abi.linuxX64,
          'runtime',
        ),
      ]) {
        test('$name does not probe the system loader', () async {
          debugLiteRtLmAbiOverride = abi;
          final service = switch (injected) {
            'legacy' => LiteRtLmService(
              clientFactory: _FakeLiteRtLmRuntimeClient.new,
              useTempCacheDir: false,
            ),
            'runtime' => LiteRtLmService(
              runtimeClientFactory: () =>
                  throw StateError('this test creates no engine'),
              useTempCacheDir: false,
            ),
            _ => LiteRtLmService(useTempCacheDir: false),
          };
          try {
            await service.loadModel(
              modelFile.path,
              const ModelParams(device: ComputeDevice.gpu),
            );
            expect(service.getActiveBackendName(), 'LiteRT-LM gpu');
            expect(systemProbes, 0);
          } finally {
            service.dispose();
          }
        });
      }
    });

    test('a CPU load does not probe the adapters', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = serviceWith(client, softwareOnly);
      try {
        const params = ModelParams(device: ComputeDevice.cpu);
        final model = await service.loadModel(modelFile.path, params);
        await startEngine(service, client, model, params);

        expect(probes, 0);
        expect(client.lastBackend, 'cpu');
      } finally {
        service.dispose();
      }
    });
  });

  for (final readOnly in [true, false]) {
    final device = readOnly ? ComputeDevice.cpu : ComputeDevice.gpu;
    test('an unlinked bundle in a directory the process '
        '${readOnly ? 'cannot' : 'can'} write does not retry a failed '
        '${device.name} engine', () async {
      if (device == ComputeDevice.gpu &&
          !liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
        markTestSkipped('No LiteRT-LM GPU backend on this platform.');
        return;
      }
      final File bundle;
      if (readOnly) {
        final readOnlyFile = await readOnlyBundle(caches: true);
        if (readOnlyFile == null) return;
        bundle = readOnlyFile;
      } else {
        final models = await Directory('${tempDir.path}/models').create();
        bundle = File('${models.path}/model.litertlm')
          ..writeAsStringSync('LITERTLM fake model');
        writeLiteRtLmGpuTextCaches(bundle);
      }
      var created = 0;
      final client = _FakeLiteRtLmRuntimeClient(
        initializeError: LiteRtLmEngineCreateError('no engine.'),
      );
      final service = LiteRtLmService(
        clientFactory: () {
          created++;
          return client;
        },
        useTempCacheDir: false,
      );
      try {
        final params = ModelParams(device: device);
        final model = await service.loadModel(bundle.path, params);
        service.createContext(model, params);

        await expectLater(
          service.tokenize(model, 'hi', true),
          throwsA(
            isA<LlamaException>().having(
              (error) => error.message,
              'message',
              readOnly ? 'no engine.' : contains('no engine.'),
            ),
          ),
        );
        expect(created, 1);
        expect(client.lastCacheDir, isNull);
      } finally {
        service.dispose();
      }
    }, testOn: '!windows');
  }

  for (final modality in ['vision', 'audio']) {
    test(
      'an unlinked bundle in a directory the process cannot write runs a '
      'GPU engine with $modality uncached despite its text GPU caches',
      () async {
        if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
          markTestSkipped('No LiteRT-LM GPU backend on this platform.');
          return;
        }
        final bundle = await readOnlyBundle(caches: true);
        if (bundle == null) return;
        final imageFile = File('${tempDir.path}/image.png');
        await imageFile.writeAsBytes(const [0x89, 0x50, 0x4e, 0x47]);
        var created = 0;
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(
          clientFactory: () {
            created++;
            return client;
          },
          useTempCacheDir: false,
        );
        try {
          const params = ModelParams(device: ComputeDevice.gpu);
          final model = await service.loadModel(bundle.path, params);
          final context = service.createContext(model, params);
          final pending = service.generateChat(context, [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [
                const LlamaTextContent('Hi'),
                if (modality == 'vision')
                  LlamaImageContent(path: imageFile.path)
                else
                  LlamaAudioContent(bytes: Uint8List.fromList(const [1, 2, 3])),
              ],
            ),
          ], const GenerationParams(maxTokens: 8)).toList();
          await client.generateStarted.future;
          await client.generated.close();
          await pending;

          expect(created, 1);
          expect(client.lastBackend, 'gpu');
          if (modality == 'vision') {
            expect(client.lastVisionBackend, isNotNull);
          } else {
            expect(client.lastAudioBackend, isNotNull);
          }
          expect(client.lastCacheDir, ':nocache');
        } finally {
          service.dispose();
        }
      },
      testOn: '!windows',
    );
  }

  test('an unlinked bundle in a directory the process cannot write does not '
      'retry a failed GPU engine uncached with a configured cache '
      'directory', () async {
    if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return;
    }
    final bundle = await readOnlyBundle();
    if (bundle == null) return;
    final configuredDir = '${tempDir.path}/cache';
    var created = 0;
    final client = _FakeLiteRtLmRuntimeClient(
      initializeError: LiteRtLmEngineCreateError('no engine.'),
    );
    final service = LiteRtLmService(
      clientFactory: () {
        created++;
        return client;
      },
      useTempCacheDir: false,
    );
    try {
      final params = ModelParams(
        device: ComputeDevice.gpu,
        liteRtLmCacheDir: configuredDir,
      );
      final model = await service.loadModel(bundle.path, params);
      service.createContext(model, params);

      await expectLater(
        service.tokenize(model, 'hi', true),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('no engine.'),
          ),
        ),
      );
      expect(created, 1);
      expect(client.lastCacheDir, configuredDir);
    } finally {
      service.dispose();
    }
  }, testOn: '!windows');

  test('an unlinked bundle in a directory the process cannot write does not '
      'retry a GPU engine uncached after an error other than engine '
      'creation', () async {
    if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return;
    }
    final bundle = await readOnlyBundle(caches: true);
    if (bundle == null) return;
    var created = 0;
    final client = _FakeLiteRtLmRuntimeClient(
      initializeError: StateError('runtime failed'),
    );
    final service = LiteRtLmService(
      clientFactory: () {
        created++;
        return client;
      },
      useTempCacheDir: false,
    );
    try {
      const params = ModelParams(device: ComputeDevice.gpu);
      final model = await service.loadModel(bundle.path, params);
      service.createContext(model, params);

      await expectLater(
        service.tokenize(model, 'hi', true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'runtime failed',
          ),
        ),
      );
      expect(created, 1);
      expect(client.lastCacheDir, isNull);
    } finally {
      service.dispose();
    }
  }, testOn: '!windows');

  for (final configured in [true, false]) {
    test('an unlinked bundle in a directory the process cannot write keeps '
        '${configured ? 'a configured cache directory' : 'the temp cache '
                  'default'}', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(
        clientFactory: () => client,
        useTempCacheDir: !configured,
      );
      final models = await Directory('${tempDir.path}/models').create();
      final bundle = File('${models.path}/model.litertlm');
      await bundle.writeAsString('LITERTLM fake model');
      final configuredDir = '${tempDir.path}/cache';
      makeReadOnly(models);
      try {
        final params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          liteRtLmCacheDir: configured ? configuredDir : null,
        );
        final model = await service.loadModel(bundle.path, params);
        await startEngine(service, client, model, params);

        expect(
          client.lastCacheDir,
          configured
              ? configuredDir
              : '${Directory.systemTemp.path}/llamadart_litert_lm',
        );
      } finally {
        service.dispose();
      }
    }, testOn: '!windows');
  }

  test('a failed link keeps the previous model loaded', () async {
    final client = _FakeLiteRtLmRuntimeClient();
    final blocker = File('${tempDir.path}/blocker');
    await blocker.writeAsString('not a directory');
    final service = LiteRtLmService(
      clientFactory: () => client,
      linkParentDirectory: Directory(blocker.path),
    );
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);
    final extensionless = File('${tempDir.path}/download');
    await extensionless.writeAsString('LITERTLM fake model');

    try {
      final model = await service.loadModel(modelFile.path, params);
      await expectLater(
        service.loadModel(extensionless.path, params),
        throwsA(isA<LlamaModelException>()),
      );

      expect(service.getMetadata(model)['general.name'], 'model.litertlm');
      await startEngine(service, client, model, params);
      expect(client.lastModelPath, modelFile.path);
    } finally {
      service.dispose();
    }
  });

  test('a failed link keeps a previous linked model', () async {
    final client = _FakeLiteRtLmRuntimeClient();
    final links = await Directory('${tempDir.path}/links').create();
    var linksCreated = 0;
    final service = LiteRtLmService(
      clientFactory: () => client,
      linkParentDirectory: links,
      createLink: (link, target) {
        if (linksCreated++ > 0) {
          throw FileSystemException('no more links', link.path);
        }
        return link.create(target);
      },
    );
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);
    final first = File('${tempDir.path}/first');
    await first.writeAsString('LITERTLM first');
    final second = File('${tempDir.path}/second');
    await second.writeAsString('LITERTLM second');

    try {
      final model = await service.loadModel(first.path, params);
      await startEngine(service, client, model, params);
      final firstLink = client.lastModelPath!;

      await expectLater(
        service.loadModel(second.path, params),
        throwsA(isA<LlamaUnsupportedException>()),
      );

      expect(service.getMetadata(model)['general.name'], 'first');
      expect(await Link(firstLink).target(), first.absolute.path);
      expect(await File(firstLink).readAsString(), 'LITERTLM first');
      expect(links.listSync(), hasLength(1));
    } finally {
      service.dispose();
    }
  }, testOn: '!windows');

  test(
    'rejects invalid paths and unsupported llama.cpp-specific features',
    () async {
      final service = LiteRtLmService();
      final wrongFormat = File('${tempDir.path}/model.gguf');
      await wrongFormat.writeAsString('fake model');

      try {
        expect(
          () => service.loadModel(
            '/does/not/exist.litertlm',
            const ModelParams(),
          ),
          throwsArgumentError,
        );
        expect(
          () => service.loadModel(wrongFormat.path, const ModelParams()),
          throwsArgumentError,
        );

        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(),
        );

        await expectLater(
          service.generate(
            contextHandle,
            'hello',
            const GenerationParams(grammar: 'root ::= "x"'),
          ),
          emitsError(isA<UnsupportedError>()),
        );
      } finally {
        service.dispose();
      }
    },
  );

  test('rejects media parts before native runtime initialization', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'describe',
          const GenerationParams(),
          parts: const [LlamaImageContent(path: '/tmp/image.png')],
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('media parts'),
          ),
        ),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'describe',
          const GenerationParams(),
          parts: [LlamaVideoContent(path: '/tmp/clip.mp4')],
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('Extract and send image frames'),
          ),
        ),
      );

      expect(fakeClient.initializeStarted.isCompleted, isFalse);
      expect(fakeClient.createConversationCount, 0);
      expect(fakeClient.generateCount, 0);
    } finally {
      service.dispose();
    }
  });

  test(
    'routes native chat media parts through LiteRT-LM message JSON',
    () async {
      final fakeClient = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => fakeClient);
      final imageFile = File('${tempDir.path}/image.png');
      await imageFile.writeAsBytes(const <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        final chunksFuture = service.generateChat(contextHandle, [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              const LlamaTextContent('Describe this image and audio.'),
              LlamaImageContent(path: imageFile.path),
              LlamaAudioContent(
                bytes: Uint8List.fromList(const <int>[1, 2, 3]),
              ),
            ],
          ),
        ], const GenerationParams(maxTokens: 8)).toList();

        await fakeClient.generateStarted.future;
        fakeClient.generated.add('ok');
        await fakeClient.generated.close();

        expect(await chunksFuture, [utf8.encode('ok')]);
        expect(fakeClient.lastMaxNumImages, 1);
        expect(fakeClient.lastVisionBackend, 'cpu');
        expect(fakeClient.lastAudioBackend, 'cpu');
        expect(fakeClient.lastVisualTokenBudget, 280);
        expect(fakeClient.lastMaxOutputTokens, 8);
        expect(fakeClient.createConversationCount, 1);
        expect(fakeClient.generateCount, 1);

        final message =
            jsonDecode(fakeClient.lastMessageJson!) as Map<String, dynamic>;
        expect(message['role'], 'user');
        expect(message['content'], [
          {'type': 'text', 'text': 'Describe this image and audio.'},
          {'type': 'image', 'path': imageFile.path},
          {
            'type': 'audio',
            'blob': base64Encode(const <int>[1, 2, 3]),
          },
        ]);
      } finally {
        service.dispose();
      }
    },
  );

  group('a turn after an image turn', () {
    late List<_FakeLiteRtLmRuntimeClient> clients;
    late LiteRtLmService service;
    late int modelHandle;
    late int contextHandle;
    late LlamaChatMessage imageTurn;

    setUp(() async {
      clients = [];
      service = LiteRtLmService(
        clientFactory: () {
          final client = _FakeLiteRtLmRuntimeClient();
          clients.add(client);
          return client;
        },
      );
      final imageFile = File('${tempDir.path}/history-image.png');
      await imageFile.writeAsBytes(const <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      imageTurn = LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [
          const LlamaTextContent('Describe this image.'),
          LlamaImageContent(path: imageFile.path),
        ],
      );
      const params = ModelParams(preferredBackend: GpuBackend.cpu);
      modelHandle = await service.loadModel(modelFile.path, params);
      contextHandle = service.createContext(modelHandle, params);
    });

    tearDown(() => service.dispose());

    Future<void> chat(List<LlamaChatMessage> messages) async {
      int generations() =>
          clients.fold(0, (count, client) => count + client.generateCount);
      final previousGenerations = generations();
      final chunks = service
          .generateChat(
            contextHandle,
            messages,
            const GenerationParams(maxTokens: 8),
          )
          .toList();
      while (generations() == previousGenerations) {
        await Future<void>.delayed(Duration.zero);
      }
      final client = clients.last;
      client.generated.add('ok');
      await client.generated.close();
      expect(await chunks, [utf8.encode('ok')]);
      client.generated = StreamController<String>();
    }

    test('keeps the vision engine while the history holds the image', () async {
      await chat([imageTurn]);
      await chat([
        imageTurn,
        LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: 'A cat.',
        ),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Its color?'),
      ]);

      expect(clients, hasLength(1));
      expect(clients.single.lastVisionBackend, 'cpu');
      expect(clients.single.lastMaxNumImages, 1);
      expect(clients.single.generateCount, 2);
    });

    test('a rebuild that names no media keeps the image count', () async {
      await chat([imageTurn]);
      service.cancelGeneration();
      await service.tokenize(modelHandle, 'Hello', false);

      expect(clients, hasLength(2));
      expect(clients.last.lastVisionBackend, 'cpu');
      expect(clients.last.lastMaxNumImages, 1);
    });

    test('drops the image count for a fresh text-only conversation', () async {
      await chat([imageTurn]);
      await chat([
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello'),
      ]);

      expect(clients, hasLength(2));
      expect(clients.first.disposeCount, 1);
      expect(clients.last.lastVisionBackend, isNull);
      expect(clients.last.lastMaxNumImages, isNull);
    });

    test('drops the image count for a fresh audio-only conversation', () async {
      await chat([imageTurn]);
      await chat([
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaAudioContent(bytes: Uint8List.fromList(const <int>[1, 2, 3])),
            const LlamaTextContent('Transcribe this.'),
          ],
        ),
      ]);

      expect(clients, hasLength(2));
      expect(clients.last.lastVisionBackend, isNull);
      expect(clients.last.lastAudioBackend, 'cpu');
      expect(clients.last.lastMaxNumImages, isNull);
    });
  });

  test(
    'routes encoded image bytes and audio file paths through message JSON',
    () async {
      final fakeClient = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => fakeClient);
      final audioFile = File('${tempDir.path}/audio.wav');
      await audioFile.writeAsBytes(const <int>[
        0x52,
        0x49,
        0x46,
        0x46,
        0x00,
        0x00,
        0x00,
        0x00,
        0x57,
        0x41,
        0x56,
        0x45,
      ]);

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        final imageBytes = Uint8List.fromList(const <int>[1, 2, 3, 4]);
        final chunksFuture = service.generateChat(contextHandle, [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              const LlamaTextContent('Describe this image and audio.'),
              LlamaImageContent(bytes: imageBytes),
              LlamaAudioContent(path: audioFile.path),
            ],
          ),
        ], const GenerationParams(maxTokens: 8)).toList();

        await fakeClient.generateStarted.future;
        fakeClient.generated.add('ok');
        await fakeClient.generated.close();

        expect(await chunksFuture, [utf8.encode('ok')]);
        expect(fakeClient.lastMaxNumImages, 1);
        expect(fakeClient.lastVisionBackend, 'cpu');
        expect(fakeClient.lastAudioBackend, 'cpu');
        expect(fakeClient.lastVisualTokenBudget, 280);
        expect(fakeClient.lastMaxOutputTokens, 8);

        final message =
            jsonDecode(fakeClient.lastMessageJson!) as Map<String, dynamic>;
        expect(message['content'], [
          {'type': 'text', 'text': 'Describe this image and audio.'},
          {'type': 'image', 'blob': base64Encode(imageBytes)},
          {'type': 'audio', 'path': audioFile.path},
        ]);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'retries renamed audio bundles with only the audio executor on CPU',
    () async {
      final gpuAudioClient = _FakeLiteRtLmRuntimeClient(
        initializeError: StateError('GPU audio executor is incompatible'),
      );
      final cpuAudioClient = _FakeLiteRtLmRuntimeClient();
      final recreatedCpuAudioClient = _FakeLiteRtLmRuntimeClient();
      final clients = <_FakeLiteRtLmRuntimeClient>[
        gpuAudioClient,
        cpuAudioClient,
        recreatedCpuAudioClient,
      ];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
      );
      final renamedModelFile = File('${tempDir.path}/renamed-bundle.litertlm');
      await renamedModelFile.writeAsString('fake model');
      final imageFile = File('${tempDir.path}/gpu-media-image.png');
      await imageFile.writeAsBytes(const <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);

      if (!service.getAvailableBackendInfo().contains('gpu')) {
        service.dispose();
        return;
      }

      try {
        final modelHandle = await service.loadModel(
          renamedModelFile.path,
          const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
        );

        final chunksFuture = service.generateChat(contextHandle, [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              const LlamaTextContent('Answer the spoken request.'),
              LlamaImageContent(path: imageFile.path),
              LlamaAudioContent(
                bytes: Uint8List.fromList(const <int>[1, 2, 3]),
              ),
            ],
          ),
        ], const GenerationParams(maxTokens: 8)).toList();

        await cpuAudioClient.generateStarted.future;
        cpuAudioClient.generated.add('ok');
        await cpuAudioClient.generated.close();

        expect(await chunksFuture, [utf8.encode('ok')]);
        expect(gpuAudioClient.lastBackend, 'gpu');
        expect(gpuAudioClient.lastVisionBackend, 'gpu');
        expect(gpuAudioClient.lastAudioBackend, 'gpu');
        expect(gpuAudioClient.disposeCount, 1);
        expect(cpuAudioClient.lastBackend, 'gpu');
        expect(cpuAudioClient.lastVisionBackend, 'gpu');
        expect(cpuAudioClient.lastAudioBackend, 'cpu');

        final recreatedChunksFuture = service.generateChat(contextHandle, [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              const LlamaTextContent('Compare the images and audio.'),
              LlamaImageContent(path: imageFile.path),
              LlamaImageContent(path: imageFile.path),
              LlamaAudioContent(
                bytes: Uint8List.fromList(const <int>[1, 2, 3]),
              ),
            ],
          ),
        ], const GenerationParams(maxTokens: 8)).toList();

        await recreatedCpuAudioClient.generateStarted.future;
        recreatedCpuAudioClient.generated.add('again');
        await recreatedCpuAudioClient.generated.close();

        expect(await recreatedChunksFuture, [utf8.encode('again')]);
        expect(cpuAudioClient.disposeCount, 1);
        expect(recreatedCpuAudioClient.lastBackend, 'gpu');
        expect(recreatedCpuAudioClient.lastVisionBackend, 'gpu');
        expect(recreatedCpuAudioClient.lastAudioBackend, 'cpu');
        expect(recreatedCpuAudioClient.lastMaxNumImages, 2);
        expect(nextClient, 3);
      } finally {
        service.dispose();
      }
    },
  );

  test('forgets learned CPU audio fallback when another model loads', () async {
    final gpuAudioClient = _FakeLiteRtLmRuntimeClient(
      initializeError: StateError('GPU audio executor is incompatible'),
    );
    final cpuAudioClient = _FakeLiteRtLmRuntimeClient();
    final nextModelGpuAudioClient = _FakeLiteRtLmRuntimeClient();
    final clients = <_FakeLiteRtLmRuntimeClient>[
      gpuAudioClient,
      cpuAudioClient,
      nextModelGpuAudioClient,
    ];
    var nextClient = 0;
    final service = LiteRtLmService(clientFactory: () => clients[nextClient++]);
    final nextModelFile = File('${tempDir.path}/next-model.litertlm');
    await nextModelFile.writeAsString('different fake model');

    if (!service.getAvailableBackendInfo().contains('gpu')) {
      service.dispose();
      return;
    }

    try {
      final firstModelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
      );
      final firstContextHandle = service.createContext(
        firstModelHandle,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
      );

      final firstChunksFuture = service.generateChat(firstContextHandle, [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            const LlamaTextContent('Transcribe this.'),
            LlamaAudioContent(bytes: Uint8List.fromList(const <int>[1, 2, 3])),
          ],
        ),
      ], const GenerationParams(maxTokens: 8)).toList();

      await cpuAudioClient.generateStarted.future;
      cpuAudioClient.generated.add('first');
      await cpuAudioClient.generated.close();
      expect(await firstChunksFuture, [utf8.encode('first')]);
      expect(cpuAudioClient.lastAudioBackend, 'cpu');

      final nextModelHandle = await service.loadModel(
        nextModelFile.path,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
      );
      final nextContextHandle = service.createContext(
        nextModelHandle,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
      );
      final nextChunksFuture = service.generateChat(nextContextHandle, [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            const LlamaTextContent('Transcribe this too.'),
            LlamaAudioContent(bytes: Uint8List.fromList(const <int>[4, 5, 6])),
          ],
        ),
      ], const GenerationParams(maxTokens: 8)).toList();

      await nextModelGpuAudioClient.generateStarted.future;
      nextModelGpuAudioClient.generated.add('second');
      await nextModelGpuAudioClient.generated.close();

      expect(await nextChunksFuture, [utf8.encode('second')]);
      expect(nextModelGpuAudioClient.lastAudioBackend, 'gpu');
      expect(nextClient, 3);
    } finally {
      service.dispose();
    }
  });

  test('does not force unrelated same-name bundles to CPU audio', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);
    final sameNameModelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
    await sameNameModelFile.writeAsString('unrelated fake model');

    if (!service.getAvailableBackendInfo().contains('gpu')) {
      service.dispose();
      return;
    }

    try {
      final modelHandle = await service.loadModel(
        sameNameModelFile.path,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
      );

      final chunksFuture = service.generateChat(contextHandle, [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            const LlamaTextContent('Answer the spoken request.'),
            LlamaAudioContent(bytes: Uint8List.fromList(const <int>[1, 2, 3])),
          ],
        ),
      ], const GenerationParams(maxTokens: 8)).toList();

      await fakeClient.generateStarted.future;
      fakeClient.generated.add('ok');
      await fakeClient.generated.close();

      expect(await chunksFuture, [utf8.encode('ok')]);
      expect(fakeClient.lastBackend, 'gpu');
      expect(fakeClient.lastVisionBackend, isNull);
      expect(fakeClient.lastAudioBackend, 'gpu');
    } finally {
      service.dispose();
    }
  });

  test('preserves the primary error when CPU audio fallback fails', () async {
    final primaryError = StateError('primary GPU audio failure');
    final gpuAudioClient = _FakeLiteRtLmRuntimeClient(
      initializeError: primaryError,
    );
    final cpuAudioClient = _FakeLiteRtLmRuntimeClient(
      initializeError: StateError('CPU audio fallback failure'),
    );
    final clients = <_FakeLiteRtLmRuntimeClient>[
      gpuAudioClient,
      cpuAudioClient,
    ];
    var nextClient = 0;
    final service = LiteRtLmService(clientFactory: () => clients[nextClient++]);

    if (!service.getAvailableBackendInfo().contains('gpu')) {
      service.dispose();
      return;
    }

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
      );

      await expectLater(
        service.generateChat(contextHandle, [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              const LlamaTextContent('Answer the spoken request.'),
              LlamaAudioContent(
                bytes: Uint8List.fromList(const <int>[1, 2, 3]),
              ),
            ],
          ),
        ], const GenerationParams(maxTokens: 8)).drain<void>(),
        throwsA(same(primaryError)),
      );

      expect(gpuAudioClient.lastAudioBackend, 'gpu');
      expect(gpuAudioClient.disposeCount, 1);
      expect(cpuAudioClient.lastAudioBackend, 'cpu');
      expect(cpuAudioClient.disposeCount, 1);
      expect(nextClient, 2);
    } finally {
      service.dispose();
    }
  });

  test(
    'rejects unsupported native chat media shapes before runtime init',
    () async {
      final fakeClient = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => fakeClient);

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        Future<void> expectMediaError(
          List<LlamaContentPart> content,
          Matcher matcher,
        ) {
          return expectLater(
            service.generateChat(contextHandle, [
              LlamaChatMessage.withContent(
                role: LlamaChatRole.user,
                content: content,
              ),
            ], const GenerationParams()),
            emitsError(matcher),
          );
        }

        await expectMediaError(
          const [LlamaImageContent(path: '')],
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            contains('must not be empty'),
          ),
        );

        await expectMediaError(
          [LlamaImageContent(path: '${tempDir.path}/missing.png')],
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            contains('image file does not exist'),
          ),
        );

        await expectMediaError(
          [LlamaImageContent(bytes: Uint8List(0))],
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            contains('must not be empty'),
          ),
        );

        await expectLater(
          service.generateChat(contextHandle, const [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [LlamaImageContent(url: 'https://example.com/a.png')],
            ),
          ], const GenerationParams()),
          emitsError(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('remote image URLs'),
                contains('LlamaImageContent.url'),
              ),
            ),
          ),
        );

        await expectMediaError(
          const [LlamaImageContent()],
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            contains('image content must provide'),
          ),
        );

        await expectMediaError(
          const [LlamaAudioContent(path: '')],
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            contains('must not be empty'),
          ),
        );

        await expectMediaError(
          [LlamaAudioContent(path: '${tempDir.path}/missing.wav')],
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            contains('audio file does not exist'),
          ),
        );

        await expectMediaError(
          [LlamaAudioContent(bytes: Uint8List(0))],
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            contains('must not be empty'),
          ),
        );

        await expectLater(
          service.generateChat(contextHandle, [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [
                LlamaImageContent(
                  bytes: Uint8List.fromList(const <int>[0, 0, 0]),
                  width: 1,
                  height: 1,
                ),
              ],
            ),
          ], const GenerationParams()),
          emitsError(
            isA<UnsupportedError>().having(
              (error) => error.message.toString(),
              'message',
              contains('raw RGB image bytes'),
            ),
          ),
        );

        await expectLater(
          service.generateChat(contextHandle, [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [
                LlamaAudioContent(samples: Float32List.fromList([0.1])),
              ],
            ),
          ], const GenerationParams()),
          emitsError(
            isA<UnsupportedError>().having(
              (error) => error.message.toString(),
              'message',
              contains('raw PCM audio samples'),
            ),
          ),
        );

        await expectMediaError(
          const [LlamaAudioContent()],
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            contains('audio content must provide'),
          ),
        );

        await expectMediaError(
          [LlamaVideoContent(path: '/tmp/clip.mp4')],
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('Extract and send image frames'),
          ),
        );

        expect(fakeClient.initializeStarted.isCompleted, isFalse);
        expect(fakeClient.createConversationCount, 0);
        expect(fakeClient.generateCount, 0);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'rejects unsupported native chat media message roles and parts',
    () async {
      final fakeClient = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => fakeClient);
      final imageFile = File('${tempDir.path}/image.png');
      await imageFile.writeAsBytes(const <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        Future<void> expectMediaError(
          List<LlamaChatMessage> messages,
          String expectedMessage,
        ) {
          return expectLater(
            service.generateChat(
              contextHandle,
              messages,
              const GenerationParams(),
            ),
            emitsError(
              isA<UnsupportedError>().having(
                (error) => error.message.toString(),
                'message',
                contains(expectedMessage),
              ),
            ),
          );
        }

        await expectMediaError([
          LlamaChatMessage.withContent(
            role: LlamaChatRole.system,
            content: [LlamaImageContent(path: imageFile.path)],
          ),
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'hello',
          ),
        ], 'system messages');

        await expectMediaError([
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaImageContent(path: imageFile.path),
              const LlamaThinkingContent('thinking'),
            ],
          ),
        ], 'thinking content');

        await expectMediaError([
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaImageContent(path: imageFile.path),
              const LlamaToolCallContent(
                name: 'lookup',
                arguments: <String, Object?>{},
                rawJson: '{}',
              ),
            ],
          ),
        ], 'tool-call content');

        await expectMediaError([
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaImageContent(path: imageFile.path),
              const LlamaToolResultContent(name: 'lookup', result: 'ok'),
            ],
          ),
        ], 'tool-result content');

        expect(fakeClient.initializeStarted.isCompleted, isFalse);
        expect(fakeClient.createConversationCount, 0);
        expect(fakeClient.generateCount, 0);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'allows text parts already represented in the rendered prompt',
    () async {
      final fakeClient = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => fakeClient);

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        final chunksFuture = service
            .generate(
              contextHandle,
              'hello',
              const GenerationParams(),
              parts: const [LlamaTextContent('hello')],
            )
            .toList();

        await fakeClient.generateStarted.future;
        fakeClient.generated.add('ok');
        await fakeClient.generated.close();

        expect(await chunksFuture, [utf8.encode('ok')]);
        expect(fakeClient.createConversationCount, 1);
        expect(fakeClient.generateCount, 1);
      } finally {
        service.dispose();
      }
    },
  );

  test('passes LiteRT-LM tokenization APIs to the client', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient()
      ..tokenizeResult = const <int>[2, 10, 11]
      ..detokenizeResult = 'hello';
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      expect(await service.tokenize(modelHandle, 'hello', true), [2, 10, 11]);
      expect(
        await service.detokenize(modelHandle, const [10, 11], false),
        'hello',
      );
      expect(
        () => service.detokenize(modelHandle, const [10, 11], true),
        throwsUnsupportedError,
      );
      expect(fakeClient.lastModelPath, modelFile.path);
      expect(fakeClient.lastBackend, 'cpu');
      expect(fakeClient.lastMaxTokens, 3072);
      expect(fakeClient.lastMinLogLevel, 3);
      expect(fakeClient.lastTokenizeText, 'hello');
      expect(fakeClient.lastTokenizeAddSpecial, isTrue);
      expect(fakeClient.lastDetokenizeTokens, [10, 11]);
    } finally {
      service.dispose();
    }
  });

  test('recovers after replacement client initialization fails', () async {
    final firstClient = _FakeLiteRtLmRuntimeClient()
      ..tokenizeResult = const <int>[1];
    final failingClient = _FakeLiteRtLmRuntimeClient(
      initializeError: StateError('planned initialization failure'),
    );
    final retryClient = _FakeLiteRtLmRuntimeClient()
      ..tokenizeResult = const <int>[3];
    final clients = [firstClient, failingClient, retryClient];
    var nextClient = 0;
    final service = LiteRtLmService(clientFactory: () => clients[nextClient++]);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      expect(await service.tokenize(modelHandle, 'first', true), [1]);

      await expectLater(
        service
            .generate(
              contextHandle,
              'hello',
              const GenerationParams(maxTokens: 7, speculativeDecoding: true),
            )
            .drain<void>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('planned initialization failure'),
          ),
        ),
      );

      expect(firstClient.disposeCount, 1);
      expect(failingClient.disposeCount, 1);
      expect(await service.tokenize(modelHandle, 'retry', true), [3]);
      expect(retryClient.lastTokenizeText, 'retry');
      expect(nextClient, 3);
    } finally {
      service.dispose();
    }
  });

  test('maps log levels to LiteRT-LM native log levels', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient()
      ..tokenizeResult = const <int>[1];
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      service.setLogLevel(LlamaLogLevel.none);
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      await service.tokenize(modelHandle, 'hello', false);
      expect(fakeClient.lastMinLogLevel, 1000);

      service.setLogLevel(LlamaLogLevel.debug);
      expect(fakeClient.lastSetMinLogLevel, 1);

      service.setLogLevel(LlamaLogLevel.error);
      expect(fakeClient.lastSetMinLogLevel, 4);
    } finally {
      service.dispose();
    }
  });

  test('keeps LiteRT-LM speculative decoding disabled by default', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      final subscription = service
          .generate(
            contextHandle,
            'hello',
            const GenerationParams(maxTokens: 7),
          )
          .listen((_) {});

      await fakeClient.generateStarted.future;
      expect(fakeClient.lastSpeculativeDecoding, isFalse);
      unawaited(subscription.cancel());
    } finally {
      service.dispose();
    }
  });

  test('passes LiteRT-LM MTP config as speculative decoding', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      final subscription = service
          .generate(
            contextHandle,
            'hello',
            const GenerationParams(
              maxTokens: 7,
              speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
            ),
          )
          .listen((_) {});

      await fakeClient.generateStarted.future;
      expect(fakeClient.lastSpeculativeDecoding, isTrue);
      unawaited(subscription.cancel());
    } finally {
      service.dispose();
    }
  });

  for (final chat in [false, true]) {
    for (final requestedTopK in [0, 1, 40]) {
      test('uses greedy LiteRT sampling for zero temperature '
          '(chat=$chat, topK=$requestedTopK)', () async {
        final fakeClient = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => fakeClient);
        const modelParams = ModelParams(preferredBackend: GpuBackend.cpu);
        try {
          final model = await service.loadModel(modelFile.path, modelParams);
          final context = service.createContext(model, modelParams);
          final params = GenerationParams(
            temp: 0,
            topK: requestedTopK,
            topP: 0.4,
            seed: 9,
          );
          final stream = chat
              ? service.generateChat(
                  context,
                  const [
                    LlamaChatMessage.fromText(
                      role: LlamaChatRole.user,
                      text: '2+2?',
                    ),
                  ],
                  params,
                  enableThinking: false,
                )
              : service.generate(context, '2+2?', params);
          final chunks = stream.toList();
          await fakeClient.generateStarted.future;
          fakeClient.generated.add('4');
          await fakeClient.generated.close();
          expect(await chunks, [utf8.encode('4')]);
          expect(fakeClient.lastTemperature, 0);
          expect(fakeClient.lastTopK, 1);
          expect(fakeClient.lastTopP, 0.4);
          expect(fakeClient.lastSeed, 9);
        } finally {
          service.dispose();
        }
      });
    }
  }

  group('cancelled image engine recovery', () {
    const generation = GenerationParams(
      maxTokens: 32,
      temp: 0,
      seed: 9,
      speculativeDecoding: false,
    );
    late _FakeLiteRtLmRuntimeClient firstClient;
    late _FakeLiteRtLmRuntimeClient nextClient;
    late LiteRtLmService service;
    late ModelParams params;
    late int context;

    List<LlamaChatMessage> messages({String modality = 'image'}) => [
      LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [
          const LlamaTextContent('describe'),
          if (modality == 'image')
            LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
          if (modality == 'audio')
            LlamaAudioContent(bytes: Uint8List.fromList([4, 5, 6])),
        ],
      ),
    ];

    Stream<List<int>> generate({String modality = 'image'}) =>
        service.generateChat(
          context,
          messages(modality: modality),
          generation,
          enableThinking: false,
        );

    Future<void> finish(
      Stream<List<int>> stream,
      _FakeLiteRtLmRuntimeClient client,
    ) async {
      final done = stream.toList();
      await client.generateStarted.future;
      client.generated.add('answer');
      await client.generated.close();
      expect(await done, [utf8.encode('answer')]);
    }

    setUp(() async {
      firstClient = _FakeLiteRtLmRuntimeClient();
      nextClient = _FakeLiteRtLmRuntimeClient();
      params = ModelParams(
        device: ComputeDevice.cpu,
        contextSize: 768,
        numberOfThreads: 2,
        liteRtLmCacheDir: '${tempDir.path}/recovery-cache',
      );
      service = LiteRtLmService(
        clientFactory: () =>
            firstClient.disposeCount == 0 ? firstClient : nextClient,
        linkParentDirectory: tempDir,
        useTempCacheDir: false,
      );
      final model = await service.loadModel(modelFile.path, params);
      context = service.createContext(model, params);
    });

    tearDown(() async {
      for (final client in [firstClient, nextClient]) {
        final unused = client.generateCount == 0
            ? client.generated.stream.drain<void>()
            : null;
        await client.generated.close();
        await unused;
      }
      service.dispose();
    });

    for (final explicitCancel in [false, true]) {
      test('recreates a settled cancelled image engine on its next use '
          '(requested: $explicitCancel)', () async {
        final done = generate().drain<void>();
        await firstClient.generateStarted.future;
        if (explicitCancel) service.cancelGeneration();
        firstClient.finishReason = explicitCancel
            ? null
            : LiteRtLmFinishReason.cancelled;
        await firstClient.generated.close();
        await done;
        expect(firstClient.disposeCount, 0);
        expect(nextClient.initializeStarted.isCompleted, isFalse);

        await finish(generate(), nextClient);
        expect(firstClient.disposeCount, 1);
        expect(nextClient.lastModelPath, firstClient.lastModelPath);
        expect(nextClient.lastBackend, 'cpu');
        expect(nextClient.lastVisionBackend, 'cpu');
        expect(nextClient.lastCacheDir, firstClient.lastCacheDir);
        expect(nextClient.lastMaxTokens, 768);
        expect(nextClient.lastMaxNumImages, 1);
        expect(nextClient.lastNumberOfThreads, 2);
        expect(nextClient.lastSpeculativeDecoding, isFalse);
        expect(nextClient.lastTemperature, 0);
        expect(nextClient.lastTopK, 1);
        expect(nextClient.lastSeed, 9);
        expect(service.getContextSize(context), 768);

        nextClient.generated = StreamController<String>();
        await finish(generate(), nextClient);
        expect(nextClient.disposeCount, 0);
        expect(nextClient.generateCount, 2);
      });
    }

    for (final modality in ['image', 'text', 'audio']) {
      test('keeps ordinary reuse for $modality '
          '(cancelled: ${modality != 'image'})', () async {
        final done = generate(modality: modality).drain<void>();
        await firstClient.generateStarted.future;
        if (modality != 'image') {
          service.cancelGeneration();
          firstClient.finishReason = LiteRtLmFinishReason.cancelled;
        }
        await firstClient.generated.close();
        await done;
        firstClient
          ..generated = StreamController<String>()
          ..finishReason = LiteRtLmFinishReason.stop;
        await finish(generate(modality: modality), firstClient);
        expect(firstClient.disposeCount, 0);
        expect(nextClient.initializeStarted.isCompleted, isFalse);
      });
    }

    test(
      'a late subscription cancellation recreates the settled image engine',
      () async {
        await finish(generate(), firstClient);
        service.cancelGeneration();
        expect(firstClient.disposeCount, 0);
        await finish(generate(), nextClient);
        expect(firstClient.disposeCount, 1);
      },
    );

    test(
      'a refused image cancellation remains visible before recovery',
      () async {
        final done = generate().drain<void>();
        await firstClient.generateStarted.future;
        final refusal = LlamaStateException('Cancellation was refused.');
        firstClient.cancelError = refusal;
        expect(service.cancelGeneration, throwsA(same(refusal)));
        await firstClient.generated.close();
        await done;
        expect(firstClient.disposeCount, 0);
        await finish(generate(), nextClient);
        expect(firstClient.disposeCount, 1);
      },
    );

    test(
      'subscription cancellation retains the engine until final drain',
      () async {
        final drain = Completer<void>();
        final unused = firstClient.generated.stream.drain<void>();
        await firstClient.generated.close();
        await unused;
        firstClient.generated = StreamController<String>(
          onCancel: () async {
            await drain.future;
            firstClient
              ..settlement = LiteRtLmNativeSettlement.settled
              ..finishReason = LiteRtLmFinishReason.cancelled;
          },
        );
        final firstChunk = Completer<void>();
        final subscription = generate().listen((_) => firstChunk.complete());
        await firstClient.generateStarted.future;
        firstClient
          ..settlement = LiteRtLmNativeSettlement.pending
          ..generated.add('partial');
        await firstChunk.future;
        service.cancelGeneration();
        final cancelled = subscription.cancel();
        try {
          await Future<void>.delayed(Duration.zero);
          expect(service.nativeSettlement, LiteRtLmNativeSettlement.pending);
          expect(firstClient.disposeCount, 0);
          expect(nextClient.initializeStarted.isCompleted, isFalse);
          expect(service.dispose, throwsA(isA<LlamaStateException>()));
        } finally {
          drain.complete();
          await cancelled;
        }
        expect(service.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(firstClient.disposeCount, 0);
        await finish(generate(), nextClient);
        expect(firstClient.disposeCount, 1);
      },
    );

    for (final unsettled in [
      LiteRtLmNativeSettlement.pending,
      LiteRtLmNativeSettlement.quarantined,
    ]) {
      test(
        'recovery never closes an engine whose lifetime is $unsettled',
        () async {
          final done = generate().drain<void>();
          await firstClient.generateStarted.future;
          service.cancelGeneration();
          firstClient.finishReason = LiteRtLmFinishReason.cancelled;
          await firstClient.generated.close();
          await done;
          firstClient.settlement = unsettled;
          try {
            await expectLater(
              generate().drain<void>(),
              throwsA(isA<LlamaStateException>()),
            );
            expect(firstClient.disposeCount, 0);
            expect(nextClient.initializeStarted.isCompleted, isFalse);
          } finally {
            firstClient.settlement = LiteRtLmNativeSettlement.settled;
          }
          await finish(generate(), nextClient);
          expect(firstClient.disposeCount, 1);
        },
      );
    }
  });

  group('finish reasons', () {
    const params = ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu);

    final expectations = <LiteRtLmFinishReason?, BackendGenerationLimit?>{
      LiteRtLmFinishReason.length: BackendGenerationLimit.maxTokens,
      LiteRtLmFinishReason.contextExhausted: BackendGenerationLimit.contextSize,
      LiteRtLmFinishReason.stop: null,
      LiteRtLmFinishReason.unknown: null,
      LiteRtLmFinishReason.cancelled: null,
      LiteRtLmFinishReason.error: null,
      null: null,
    };

    for (final chat in [false, true]) {
      Stream<List<int>> generate(
        LiteRtLmService service,
        int context, {
        List<String> stopSequences = const [],
      }) {
        final generationParams = GenerationParams(
          maxTokens: 4,
          stopSequences: stopSequences,
        );
        return chat
            ? service.generateChat(context, const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
              ], generationParams)
            : service.generate(context, 'Hi', generationParams);
      }

      final kind = chat ? 'chat' : 'raw';

      for (final MapEntry(key: reason, value: limit) in expectations.entries) {
        test('$kind generation maps $reason to $limit', () async {
          final client = _FakeLiteRtLmRuntimeClient();
          final service = LiteRtLmService(clientFactory: () => client);
          try {
            final model = await service.loadModel(modelFile.path, params);
            final context = service.createContext(model, params);
            final done = generate(service, context).drain<void>();
            await client.generateStarted.future;
            client
              ..generated.add('partial')
              ..finishReason = reason;
            await client.generated.close();
            await done;
            expect(service.lastGenerationLimit, limit);
          } finally {
            service.dispose();
          }
        });
      }

      test('$kind cancellation wins over a reported limit', () async {
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        try {
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);
          final done = generate(service, context).drain<void>();
          await client.generateStarted.future;
          client
            ..generated.add('partial')
            ..finishReason = LiteRtLmFinishReason.length;
          service.cancelGeneration();
          await client.generated.close();
          await done;
          expect(service.lastGenerationLimit, isNull);
        } finally {
          service.dispose();
        }
      });

      test('$kind stop sequence wins over a reported limit', () async {
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        try {
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);
          final text = generate(
            service,
            context,
            stopSequences: ['END'],
          ).expand((chunk) => chunk).toList();
          await client.generateStarted.future;
          client
            ..generated.add('done END tail')
            ..finishReason = LiteRtLmFinishReason.length;
          await client.generated.close();
          expect(utf8.decode(await text), 'done ');
          expect(service.lastGenerationLimit, isNull);
        } finally {
          service.dispose();
        }
      });

      test('$kind failed generation clears the previous limit', () async {
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        try {
          final model = await service.loadModel(modelFile.path, params);
          final context = service.createContext(model, params);
          final first = generate(service, context).drain<void>();
          await client.generateStarted.future;
          client.finishReason = LiteRtLmFinishReason.length;
          await client.generated.close();
          await first;
          expect(service.lastGenerationLimit, BackendGenerationLimit.maxTokens);

          client.generated = StreamController<String>();
          final second = expectLater(
            generate(service, context).drain<void>(),
            throwsA(isA<StateError>()),
          );
          await pumpEventQueue();
          client.generated.addError(StateError('native failure'));
          await client.generated.close();
          await second;
          expect(service.lastGenerationLimit, isNull);
        } finally {
          service.dispose();
        }
      });
    }
  });

  test('passes supported LiteRT-LM generation options to the client', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      final chunks = <List<int>>[];
      final subscription = service
          .generate(
            contextHandle,
            'hello',
            const GenerationParams(
              maxTokens: 7,
              temp: 0.3,
              topK: 5,
              topP: 0.4,
              seed: 123,
              stopSequences: ['STOP'],
              speculativeDecoding: true,
            ),
          )
          .listen(chunks.add);

      await fakeClient.generateStarted.future;
      fakeClient.generated.add('alpha STOP hidden');
      await fakeClient.generated.close();
      await subscription.asFuture<void>();

      expect(fakeClient.lastModelPath, modelFile.path);
      expect(fakeClient.lastBackend, 'cpu');
      expect(fakeClient.lastMaxTokens, 3072);
      expect(fakeClient.lastOutputTokens, 256);
      expect(fakeClient.lastMaxOutputTokens, 7);
      expect(fakeClient.lastTemperature, 0.3);
      expect(fakeClient.lastTopK, 5);
      expect(fakeClient.lastTopP, 0.4);
      expect(fakeClient.lastSeed, 123);
      expect(fakeClient.lastSpeculativeDecoding, isTrue);
      expect(fakeClient.lastNpuBackend, isFalse);
      expect(utf8.decode(chunks.expand((chunk) => chunk).toList()), 'alpha ');
      expect(fakeClient.cancelCount, 1);
    } finally {
      service.dispose();
    }
  });

  group('LiteRT-LM cache directory', () {
    final records = <LlamaLogRecord>[];

    setUp(() {
      records.clear();
      LlamaLogger.instance.setLevel(LlamaLogLevel.warn);
      LlamaLogger.instance.setHandler(records.add);
    });

    tearDown(() {
      LlamaLogger.instance.setLevel(LlamaLogLevel.none);
      LlamaLogger.instance.setHandler(null);
    });

    Future<void> createEngine(
      LiteRtLmService service,
      _FakeLiteRtLmRuntimeClient client,
      ModelParams params,
    ) async {
      final model = await service.loadModel(modelFile.path, params);
      final context = service.createContext(model, params);
      final chunks = service
          .generate(context, 'hello', const GenerationParams(maxTokens: 1))
          .toList();
      await client.generateStarted.future;
      await client.generated.close();
      await chunks;
    }

    File writeCache(Directory dir, String name, int bytes) {
      return File('${dir.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(List<int>.filled(bytes, 0));
    }

    test('default directory is platform specific', () async {
      expect(Directory.systemTemp.path, suiteTemp().path);
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      try {
        await createEngine(
          service,
          client,
          const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu),
        );
        if (Platform.isMacOS || Platform.isAndroid) {
          expect(
            client.lastCacheDir,
            '${suiteTemp().path}/$liteRtLmTempCacheDirectoryName',
          );
        } else {
          expect(client.lastCacheDir, isNull);
        }
      } finally {
        service.dispose();
      }
    });

    test('the default directory prunes the suite temp directory, never the '
        'real one', () async {
      // Checked first: a load reaching the real directory would delete the
      // program caches apps keep there.
      expect(Directory.systemTemp.path, suiteTemp().path);
      final defaultDir = Directory(
        '${suiteTemp().path}/$liteRtLmTempCacheDirectoryName',
      )..createSync();
      final sentinel = writeCache(
        defaultDir,
        'sentinel.litertlm_1_2_mldrift_program_cache.bin',
        64,
      );
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      try {
        await createEngine(
          service,
          client,
          const ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmMaxProgramCacheBytes: 32,
          ),
        );
        expect(
          sentinel.existsSync(),
          !(Platform.isMacOS || Platform.isAndroid),
        );
      } finally {
        service.dispose();
        defaultDir.deleteSync(recursive: true);
      }
    });

    test('configured directory is created and forwarded', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      final cacheDir = Directory('${tempDir.path}/nested/cache');
      try {
        await createEngine(
          service,
          client,
          ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: cacheDir.path,
          ),
        );
        expect(client.lastCacheDir, cacheDir.path);
        expect(cacheDir.existsSync(), isTrue);
      } finally {
        service.dispose();
      }
    });

    File sparseCache(Directory dir, String name, int bytes) {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      final raf = file.openSync(mode: FileMode.write);
      try {
        raf.truncateSync(bytes);
      } finally {
        raf.closeSync();
      }
      return file;
    }

    List<String> leaseFiles(Directory dir) => [
      for (final entry in dir.listSync())
        if (entry.uri.pathSegments.last.startsWith(liteRtLmCacheLeasePrefix))
          entry.path,
    ];

    for (final (bytes, kept) in [
      (ModelParams.defaultLiteRtLmMaxProgramCacheBytes, true),
      (ModelParams.defaultLiteRtLmMaxProgramCacheBytes + 1, false),
    ]) {
      test('null cap applies the 1 GiB default to a $bytes byte program '
          'cache', () async {
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        final cacheDir = Directory('${tempDir.path}/cache')..createSync();
        final program = sparseCache(
          cacheDir,
          'm_1_2_mldrift_program_cache.bin',
          bytes,
        );
        try {
          await createEngine(
            service,
            client,
            ModelParams(
              liteRtLmBackend: LiteRtLmBackendPreference.cpu,
              liteRtLmCacheDir: cacheDir.path,
            ),
          );
          expect(ModelParams.defaultLiteRtLmMaxProgramCacheBytes, 1 << 30);
          expect(program.existsSync(), kept);
          if (kept) {
            expect(records, isEmpty);
          } else {
            expect(
              records.single.message,
              contains('liteRtLmMaxProgramCacheBytes=1073741824'),
            );
          }
        } finally {
          service.dispose();
        }
      });
    }

    test('a raised cap keeps a program cache above the default', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      final program = sparseCache(
        cacheDir,
        'm_1_2_mldrift_program_cache.bin',
        ModelParams.defaultLiteRtLmMaxProgramCacheBytes + 1,
      );
      try {
        await createEngine(
          service,
          client,
          ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: cacheDir.path,
            liteRtLmMaxProgramCacheBytes:
                2 * ModelParams.defaultLiteRtLmMaxProgramCacheBytes,
          ),
        );
        expect(program.existsSync(), isTrue);
        expect(records, isEmpty);
      } finally {
        service.dispose();
      }
    });

    test('unlimited cap keeps every program cache and still leases the '
        'directory', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      final program = sparseCache(
        cacheDir,
        'm_1_2_mldrift_program_cache.bin',
        4 * ModelParams.defaultLiteRtLmMaxProgramCacheBytes,
      );
      List<String>? leasesAtInitialize;
      client.onInitialize = () => leasesAtInitialize = leaseFiles(cacheDir);
      try {
        await createEngine(
          service,
          client,
          ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: cacheDir.path,
            liteRtLmMaxProgramCacheBytes:
                ModelParams.unlimitedLiteRtLmProgramCacheBytes,
          ),
        );
        expect(program.existsSync(), isTrue);
        expect(records, isEmpty);
        expect(leasesAtInitialize, hasLength(2));
      } finally {
        service.dispose();
      }
      expect(leaseFiles(cacheDir), isEmpty);
    });

    test('pruning keeps the program caches of a model another engine is '
        'using, until that engine is disposed', () async {
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      final params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        liteRtLmCacheDir: cacheDir.path,
        liteRtLmMaxProgramCacheBytes: 32,
      );
      final firstClient = _FakeLiteRtLmRuntimeClient();
      final first = LiteRtLmService(clientFactory: () => firstClient);
      final secondClient = _FakeLiteRtLmRuntimeClient();
      final second = LiteRtLmService(clientFactory: () => secondClient);
      final thirdClient = _FakeLiteRtLmRuntimeClient();
      final third = LiteRtLmService(clientFactory: () => thirdClient);
      try {
        await createEngine(first, firstClient, params);
        final inUse = writeCache(
          cacheDir,
          'model.litertlm_1_2_mldrift_program_cache.bin',
          64,
        );
        final unused = writeCache(
          cacheDir,
          'other.litertlm_1_2_mldrift_program_cache.bin',
          64,
        );

        await createEngine(second, secondClient, params);
        expect(inUse.existsSync(), isTrue);
        expect(unused.existsSync(), isFalse);

        first.dispose();
        second.dispose();
        await createEngine(third, thirdClient, params);
        expect(inUse.existsSync(), isFalse);
      } finally {
        first.dispose();
        second.dispose();
        third.dispose();
      }
      expect(leaseFiles(cacheDir), isEmpty);
    });

    for (final suffix in ['/', '//']) {
      test('pruning deletes the program caches of the model being loaded in '
          "a cache directory ending in '$suffix'", () async {
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        final cacheDir = Directory('${tempDir.path}/cache')..createSync();
        final own = writeCache(
          cacheDir,
          'model.litertlm_1_2_mldrift_program_cache.bin',
          64,
        );
        try {
          await createEngine(
            service,
            client,
            ModelParams(
              liteRtLmBackend: LiteRtLmBackendPreference.cpu,
              liteRtLmCacheDir: '${cacheDir.path}$suffix',
              liteRtLmMaxProgramCacheBytes: 32,
            ),
          );
          expect(own.existsSync(), isFalse);
        } finally {
          service.dispose();
        }
        expect(leaseFiles(cacheDir), isEmpty);
      });
    }

    test(
      'failed native cleanup retains its lease until cleanup succeeds',
      () async {
        final client = _FakeLiteRtLmRuntimeClient()
          ..disposeError = StateError('dispose failed');
        final service = LiteRtLmService(clientFactory: () => client);
        final cacheDir = Directory('${tempDir.path}/cache')..createSync();
        await createEngine(
          service,
          client,
          ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: cacheDir.path,
          ),
        );
        expect(leaseFiles(cacheDir), hasLength(2));

        expect(service.dispose, throwsStateError);
        expect(leaseFiles(cacheDir), hasLength(2));
        client.disposeError = null;
        service.dispose();
        expect(leaseFiles(cacheDir), isEmpty);
      },
    );

    test(
      'pending callbacks retain the client and lease until native settlement',
      () async {
        final client = _FakeLiteRtLmRuntimeClient();
        final service = LiteRtLmService(clientFactory: () => client);
        final cacheDir = Directory('${tempDir.path}/cache')..createSync();
        await createEngine(
          service,
          client,
          ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: cacheDir.path,
          ),
        );
        client.settlement = LiteRtLmNativeSettlement.pending;
        expect(service.dispose, throwsA(isA<LlamaStateException>()));
        expect(client.disposeCount, 0);
        expect(leaseFiles(cacheDir), hasLength(2));
        client.settlement = LiteRtLmNativeSettlement.settled;
        service.dispose();
        expect(client.disposeCount, 1);
        expect(leaseFiles(cacheDir), isEmpty);
      },
    );

    test(
      'failed cleanup preserves the model link and protects caches from pruning',
      () async {
        final client = _FakeLiteRtLmRuntimeClient();
        final links = Directory('${tempDir.path}/links')..createSync();
        final service = LiteRtLmService(
          clientFactory: () => client,
          linkParentDirectory: links,
        );
        final original = File('${tempDir.path}/download')
          ..writeAsStringSync('LITERTLM fake model');
        final cacheDir = Directory('${tempDir.path}/cache')..createSync();
        final params = ModelParams(
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          liteRtLmCacheDir: cacheDir.path,
        );
        final model = await service.loadModel(original.path, params);
        await startEngine(service, client, model, params);
        final runtimePath = client.lastModelPath!;
        final runtimeName = File(runtimePath).uri.pathSegments.last;
        final program = writeCache(
          cacheDir,
          '${runtimeName}_1_2_mldrift_program_cache.bin',
          16,
        );
        client.disposeError = StateError('native cleanup failed');
        expect(service.dispose, throwsStateError);
        expect(Link(runtimePath).existsSync(), isTrue);
        expect(leaseFiles(cacheDir), hasLength(2));
        pruneLiteRtLmProgramCaches(cacheDir.path, 0);
        expect(program.existsSync(), isTrue);
        client.disposeError = null;
        service.dispose();
        expect(links.listSync(), isEmpty);
        expect(leaseFiles(cacheDir), isEmpty);
        pruneLiteRtLmProgramCaches(cacheDir.path, 0);
        expect(program.existsSync(), isFalse);
        expect(original.existsSync(), isTrue);
      },
      testOn: '!windows',
    );

    test('a failed engine create releases its lease', () async {
      final client = _FakeLiteRtLmRuntimeClient(
        initializeError: LiteRtLmEngineCreateError('no engine.'),
      );
      final service = LiteRtLmService(clientFactory: () => client);
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      try {
        final params = ModelParams(
          device: ComputeDevice.cpu,
          liteRtLmCacheDir: cacheDir.path,
        );
        final model = await service.loadModel(modelFile.path, params);
        service.createContext(model, params);
        await expectLater(
          service.tokenize(model, 'hi', true),
          throwsA(isA<LlamaModelException>()),
        );
        expect(leaseFiles(cacheDir), isEmpty);
      } finally {
        service.dispose();
      }
    });

    test('bundle-side caches are neither pruned nor leased without a cache '
        'directory', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(
        clientFactory: () => client,
        useTempCacheDir: false,
      );
      final program = writeCache(
        tempDir,
        'model.litertlm_1_2_mldrift_program_cache.bin',
        64,
      );
      try {
        await createEngine(
          service,
          client,
          const ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmMaxProgramCacheBytes: 0,
          ),
        );
        expect(client.lastCacheDir, isNull);
        expect(program.existsSync(), isTrue);
        expect(leaseFiles(tempDir), isEmpty);
        expect(records, isEmpty);
      } finally {
        service.dispose();
      }
    });

    test('caches next to a linked bundle are neither pruned nor leased '
        'without a cache directory', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(
        clientFactory: () => client,
        linkParentDirectory: await Directory('${tempDir.path}/links').create(),
        useTempCacheDir: false,
      );
      final models = await Directory('${tempDir.path}/models').create();
      final extensionless = File('${models.path}/download');
      await extensionless.writeAsString('LITERTLM fake model');
      final program = writeCache(
        models,
        'download_1_2_mldrift_program_cache.bin',
        64,
      );
      const params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        liteRtLmMaxProgramCacheBytes: 0,
      );
      try {
        final model = await service.loadModel(extensionless.path, params);
        await startEngine(service, client, model, params);
        expect(client.lastCacheDir, models.absolute.path);
        expect(program.existsSync(), isTrue);
        expect(leaseFiles(models), isEmpty);
      } finally {
        service.dispose();
      }
    }, testOn: '!windows');

    test('a linked bundle leases its caches under the name the runtime '
        'loads it by', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(
        clientFactory: () => client,
        linkParentDirectory: await Directory('${tempDir.path}/links').create(),
      );
      final models = await Directory('${tempDir.path}/models').create();
      final extensionless = File('${models.path}/download');
      await extensionless.writeAsString('LITERTLM fake model');
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      List<String>? leasedModels;
      client.onInitialize = () => leasedModels = [
        for (final lease in leaseFiles(cacheDir))
          if (!lease.endsWith('.lock')) File(lease).readAsStringSync(),
      ];
      final params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        liteRtLmCacheDir: cacheDir.path,
      );
      try {
        final model = await service.loadModel(extensionless.path, params);
        await startEngine(service, client, model, params);
        final runtimeName = File(client.lastModelPath!).uri.pathSegments.last;
        expect(runtimeName, isNot('download'));
        expect(leasedModels, [runtimeName]);
      } finally {
        service.dispose();
      }
    }, testOn: '!windows');

    test('a :nocache cache directory is forwarded without creating, pruning '
        'or leasing a directory', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      // Listed rather than checked by path: `:nocache` is not a valid path on
      // Windows.
      Set<String> workingDirectoryNames() => {
        for (final entry in Directory.current.listSync())
          entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
      };
      final before = workingDirectoryNames();
      if (!Platform.isWindows && !before.contains(liteRtLmNoCacheDirectory)) {
        addTearDown(() {
          final created = Directory(liteRtLmNoCacheDirectory);
          if (created.existsSync()) created.deleteSync(recursive: true);
        });
      }
      try {
        await createEngine(
          service,
          client,
          const ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: liteRtLmNoCacheDirectory,
            liteRtLmMaxProgramCacheBytes: 0,
          ),
        );
        expect(client.lastCacheDir, liteRtLmNoCacheDirectory);
        expect(workingDirectoryNames().difference(before), isEmpty);
        expect(records, isEmpty);
      } finally {
        service.dispose();
      }
    });

    test('a :nocache cache directory never prunes or leases a directory of '
        'that name', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      final relative = Directory(liteRtLmNoCacheDirectory);
      if (relative.existsSync()) {
        markTestSkipped('${relative.absolute.path} already exists.');
        return;
      }
      relative.createSync();
      final program = writeCache(
        relative,
        'model.litertlm_1_2_mldrift_program_cache.bin',
        64,
      );
      List<String>? leasesAtInitialize;
      client.onInitialize = () => leasesAtInitialize = leaseFiles(relative);
      try {
        await createEngine(
          service,
          client,
          const ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: liteRtLmNoCacheDirectory,
            liteRtLmMaxProgramCacheBytes: 0,
          ),
        );
        expect(program.existsSync(), isTrue);
        expect(leasesAtInitialize, isEmpty);
      } finally {
        service.dispose();
        relative.deleteSync(recursive: true);
      }
    }, testOn: '!windows');

    test('cap deletes an oversized program cache before engine create and '
        'logs one warning', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      final program = writeCache(
        cacheDir,
        'm_1_2_mldrift_program_cache.bin',
        64,
      );
      final small = writeCache(cacheDir, 'n_1_2_mldrift_program_cache.bin', 8);
      final weights = writeCache(
        cacheDir,
        'm_1_2_mldrift_weight_cache.bin',
        64,
      );
      final xnnpack = writeCache(cacheDir, 'm.litertlm.xnnpack_cache', 64);
      bool? programExistedAtInitialize;
      client.onInitialize = () {
        programExistedAtInitialize = program.existsSync();
      };
      try {
        await createEngine(
          service,
          client,
          ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: cacheDir.path,
            liteRtLmMaxProgramCacheBytes: 32,
          ),
        );
        expect(programExistedAtInitialize, isFalse);
        expect(small.existsSync(), isTrue);
        expect(weights.existsSync(), isTrue);
        expect(xnnpack.existsSync(), isTrue);
        expect(records, hasLength(1));
        expect(records.single.level, LlamaLogLevel.warn);
        expect(
          records.single.message,
          allOf(
            contains(program.path),
            contains('64 bytes'),
            contains('issues/552'),
          ),
        );
      } finally {
        service.dispose();
      }
    });

    test('warning is suppressed above the Dart warn log level', () async {
      LlamaLogger.instance.setLevel(LlamaLogLevel.error);
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client)
        ..setLogLevel(LlamaLogLevel.warn);
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      final program = writeCache(
        cacheDir,
        'm_1_2_mldrift_program_cache.bin',
        64,
      );
      try {
        await createEngine(
          service,
          client,
          ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: cacheDir.path,
            liteRtLmMaxProgramCacheBytes: 32,
          ),
        );
        expect(program.existsSync(), isFalse);
        expect(records, isEmpty);
      } finally {
        service.dispose();
      }
    });

    test('native log level does not gate the warning', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client)
        ..setLogLevel(LlamaLogLevel.none);
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      final program = writeCache(
        cacheDir,
        'm_1_2_mldrift_program_cache.bin',
        64,
      );
      try {
        await createEngine(
          service,
          client,
          ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: cacheDir.path,
            liteRtLmMaxProgramCacheBytes: 32,
          ),
        );
        expect(program.existsSync(), isFalse);
        expect(records, hasLength(1));
        expect(records.single.level, LlamaLogLevel.warn);
      } finally {
        service.dispose();
      }
    });

    test('a failed delete does not fail engine create', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      final cacheDir = Directory('${tempDir.path}/cache')..createSync();
      final program = writeCache(
        cacheDir,
        'm_1_2_mldrift_program_cache.bin',
        64,
      );
      Process.runSync('chmod', ['a-w', cacheDir.path]);
      try {
        await createEngine(
          service,
          client,
          ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.cpu,
            liteRtLmCacheDir: cacheDir.path,
            liteRtLmMaxProgramCacheBytes: 32,
          ),
        );
        expect(client.lastCacheDir, cacheDir.path);
        expect(records, hasLength(1));
        if (program.existsSync()) {
          expect(records.single.error, isA<FileSystemException>());
        }
      } finally {
        Process.runSync('chmod', ['u+w', cacheDir.path]);
        service.dispose();
      }
    }, testOn: '!windows');
  });

  test('passes LiteRT-LM runtime tuning options to the client', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);
    const modelParams = ModelParams(
      contextSize: 3072,
      preferredBackend: GpuBackend.cpu,
      liteRtLmActivationDataType: LiteRtLmActivationDataType.float16,
      liteRtLmPrefillChunkSize: 128,
      liteRtLmParallelFileSectionLoading: false,
      liteRtLmDispatchLibDir: '/vendor/litert-dispatch',
      loras: [LoraAdapterConfig(path: '/tmp/adapter.lora')],
      numberOfThreads: 4,
    );

    try {
      final modelHandle = await service.loadModel(modelFile.path, modelParams);
      final contextHandle = service.createContext(modelHandle, modelParams);

      final chunks = service
          .generate(
            contextHandle,
            'hello',
            const GenerationParams(maxTokens: 7),
          )
          .toList();

      await fakeClient.generateStarted.future;
      fakeClient.generated.add('done');
      await fakeClient.generated.close();
      await chunks;

      expect(
        fakeClient.lastActivationDataType,
        LiteRtLmActivationDataType.float16,
      );
      expect(fakeClient.lastPrefillChunkSize, 128);
      expect(fakeClient.lastParallelFileSectionLoading, isFalse);
      expect(fakeClient.lastDispatchLibDir, '/vendor/litert-dispatch');
      expect(fakeClient.lastLoraPath, '/tmp/adapter.lora');
      expect(fakeClient.lastNumberOfThreads, 4);
    } finally {
      service.dispose();
    }
  });

  test('passes native chat messages and tools to the client', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      final chunksFuture = service
          .generateChat(
            contextHandle,
            const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.system,
                text: 'Be concise.',
              ),
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'hello',
              ),
              LlamaChatMessage.fromText(
                role: LlamaChatRole.assistant,
                text: 'hi',
              ),
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'weather?',
              ),
            ],
            const GenerationParams(
              maxTokens: 7,
              temp: 0.3,
              topK: 5,
              topP: 0.4,
              seed: 9,
            ),
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Gets weather.',
                parameters: [
                  ToolParam.string(
                    'city',
                    description: 'City name.',
                    required: true,
                  ),
                ],
                handler: (_) async => 'sunny',
              ).toJson(),
            ],
            chatTemplateKwargs: const {
              'locale': 'en_CA',
              'source_lang_code': 'en',
              'target_lang_code': 'fr',
            },
            templateNow: DateTime.utc(2026, 6, 7, 12),
          )
          .toList();

      await fakeClient.generateStarted.future;
      fakeClient.generated.add('native response');
      await fakeClient.generated.close();

      expect(await chunksFuture, [utf8.encode('native response')]);
      expect(fakeClient.lastOutputTokens, 256);
      expect(fakeClient.lastTemperature, 0.3);
      expect(fakeClient.lastTopK, 5);
      expect(fakeClient.lastTopP, 0.4);
      expect(fakeClient.lastSeed, 9);
      expect(fakeClient.lastNpuBackend, isFalse);

      expect(fakeClient.lastSystemMessage, 'Be concise.');
      expect(fakeClient.lastMessages, [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hello'},
          ],
        },
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'hi'},
          ],
        },
      ]);
      expect(jsonDecode(fakeClient.lastMessageJson!), {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'weather?'},
        ],
      });
      expect(fakeClient.lastTools?.single['function'], {
        'name': 'get_weather',
        'description': 'Gets weather.',
        'parameters': {
          'type': 'object',
          'properties': {
            'city': {'type': 'string', 'description': 'City name.'},
          },
          'required': ['city'],
        },
      });
      expect(fakeClient.lastExtraContext, {
        'locale': 'en_CA',
        'source_lang_code': 'en',
        'target_lang_code': 'fr',
        'now': '2026-06-07T12:00:00.000Z',
        'enable_thinking': true,
      });
    } finally {
      service.dispose();
    }
  });

  for (final entry in <(String, List<String>, String?)>[
    ('absent', [], null),
    ('empty', ['', ' \n\t '], null),
    (
      'multiple',
      ['  Remember "cedar17".\nKeep case.  ', ' ', '안녕'],
      'Remember "cedar17".\nKeep case.\n안녕',
    ),
    (
      'literal JSON',
      ['{"role":"system","content":[{"type":"text","text":"cedar17"}]}'],
      '{"role":"system","content":[{"type":"text","text":"cedar17"}]}',
    ),
  ]) {
    test('native chat passes ${entry.$1} system text unchanged', () async {
      final client = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => client);
      const params = ModelParams(preferredBackend: GpuBackend.cpu);
      try {
        final model = await service.loadModel(modelFile.path, params);
        final context = service.createContext(model, params);
        final pending = service.generateChat(context, [
          for (final text in entry.$2)
            LlamaChatMessage.fromText(role: LlamaChatRole.system, text: text),
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'What is the code?',
          ),
        ], const GenerationParams(maxTokens: 32)).toList();
        await client.generateStarted.future;
        client.generated.add('cedar17');
        await client.generated.close();
        expect(await pending, [utf8.encode('cedar17')]);
        expect(client.lastSystemMessage, entry.$3);
        expect(client.lastMessages, isNull);
        expect(jsonDecode(client.lastMessageJson!), {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'What is the code?'},
          ],
        });
      } finally {
        service.dispose();
      }
    });
  }

  Future<(List<Map<String, dynamic>>?, Object?)> nativeChatPayload(
    List<LlamaChatMessage> messages,
  ) async {
    final client = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => client);
    const params = ModelParams(preferredBackend: GpuBackend.cpu);
    try {
      final model = await service.loadModel(modelFile.path, params);
      final context = service.createContext(model, params);
      final pending = service
          .generateChat(context, messages, const GenerationParams(maxTokens: 8))
          .toList();
      await client.generateStarted.future;
      await client.generated.close();
      await pending;
      return (client.lastMessages, jsonDecode(client.lastMessageJson!));
    } finally {
      service.dispose();
    }
  }

  const weatherCall = LlamaToolCallContent(
    id: 'call_0',
    name: 'get_weather',
    arguments: {'city': 'Montréal'},
    rawJson: '{"city":"Montréal"}',
  );
  const weather = {'city': 'Montréal', 'temperature_celsius': 17};

  for (final entry in <(String, Object?)>[
    ('Map', weather),
    ('String', jsonEncode(weather)),
  ]) {
    test('native chat sends a ${entry.$1} tool result as a LiteRT-LM '
        'tool_response', () async {
      final (history, active) = await nativeChatPayload([
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Weather in Montréal?',
        ),
        const LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [weatherCall],
        ),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(
              id: 'call_0',
              name: 'get_weather',
              result: entry.$2,
            ),
          ],
        ),
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Reply with only the number.',
        ),
      ]);
      expect(history, [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Weather in Montréal?'},
          ],
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'type': 'function',
              'function': {
                'name': 'get_weather',
                'arguments': {'city': 'Montréal'},
              },
            },
          ],
        },
        {
          'role': 'tool',
          'content': [
            {
              'type': 'tool_response',
              'name': 'get_weather',
              'response': entry.$2,
            },
          ],
        },
      ]);
      expect(active, {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Reply with only the number.'},
        ],
      });
    });
  }

  test('native chat keeps every tool result and assistant text, thinking '
      'and calls', () async {
    final (history, active) = await nativeChatPayload([
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Weather in Montréal and Paris?',
      ),
      const LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          LlamaThinkingContent('Two cities.'),
          LlamaTextContent('Checking '),
          LlamaTextContent('both.'),
          weatherCall,
          LlamaToolCallContent(
            name: 'get_weather',
            arguments: {'city': 'Paris'},
            rawJson: '{"city": "Paris"}',
          ),
        ],
      ),
      const LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [
          LlamaToolResultContent(
            id: 'call_0',
            name: 'get_weather',
            result: weather,
          ),
          LlamaToolResultContent(name: 'get_weather', result: 'Paris: 21'),
        ],
      ),
    ]);
    expect(history?.last, {
      'role': 'assistant',
      'content': 'Checking both.',
      'reasoning_content': 'Two cities.',
      'tool_calls': [
        {
          'type': 'function',
          'function': {
            'name': 'get_weather',
            'arguments': {'city': 'Montréal'},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'get_weather',
            'arguments': {'city': 'Paris'},
          },
        },
      ],
    });
    expect(active, {
      'role': 'tool',
      'content': [
        {'type': 'tool_response', 'name': 'get_weather', 'response': weather},
        {
          'type': 'tool_response',
          'name': 'get_weather',
          'response': 'Paris: 21',
        },
      ],
    });
  });

  test(
    'rejects native required tool choice before runtime initialization',
    () async {
      final fakeClient = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => fakeClient);

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        await expectLater(
          service
              .generateChat(
                contextHandle,
                const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'Call get_weather for Seoul.',
                  ),
                ],
                const GenerationParams(maxTokens: 32),
                tools: [
                  ToolDefinition(
                    name: 'get_weather',
                    description: 'Gets weather.',
                    parameters: const [],
                    handler: (_) async => 'sunny',
                  ).toJson(),
                ],
                toolChoice: ToolChoice.required,
              )
              .drain<void>(),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('ToolChoice.required enforcement'),
                contains('rendered-prompt fallback'),
                contains('grammar-capable backend'),
              ),
            ),
          ),
        );
        expect(fakeClient.initializeStarted.isCompleted, isFalse);
        expect(fakeClient.createConversationCount, 0);
        expect(fakeClient.generateCount, 0);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'recreates LiteRT-LM client when speculative decoding changes',
    () async {
      final firstClient = _FakeLiteRtLmRuntimeClient();
      final secondClient = _FakeLiteRtLmRuntimeClient();
      final clients = <_FakeLiteRtLmRuntimeClient>[firstClient, secondClient];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
      );

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );

        final firstChunks = service
            .generate(
              contextHandle,
              'hello',
              const GenerationParams(maxTokens: 7, speculativeDecoding: true),
            )
            .toList();
        await firstClient.generateStarted.future;
        firstClient.generated.add('first');
        await firstClient.generated.close();
        await firstChunks;

        final secondChunks = service
            .generate(
              contextHandle,
              'hello',
              const GenerationParams(maxTokens: 7),
            )
            .toList();
        await secondClient.generateStarted.future;
        secondClient.generated.add('second');
        await secondClient.generated.close();
        await secondChunks;

        expect(firstClient.lastSpeculativeDecoding, isTrue);
        expect(firstClient.disposeCount, 1);
        expect(secondClient.lastSpeculativeDecoding, isFalse);
        expect(nextClient, 2);
      } finally {
        service.dispose();
      }
    },
  );

  test('changes response limits without recreating the client', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    var clientCreations = 0;
    final service = LiteRtLmService(
      clientFactory: () {
        clientCreations++;
        return fakeClient;
      },
    );

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      final first = service
          .generate(
            contextHandle,
            'short',
            const GenerationParams(maxTokens: 2),
          )
          .toList();
      await fakeClient.generateStarted.future;
      fakeClient.generated.add('one');
      await fakeClient.generated.close();
      await first;

      fakeClient.generated = StreamController<String>();
      final second = service
          .generate(
            contextHandle,
            'long allowance',
            const GenerationParams(maxTokens: 1024),
          )
          .toList();
      await Future<void>.delayed(Duration.zero);
      fakeClient.generated.add('two');
      await fakeClient.generated.close();
      await second;

      expect(clientCreations, 1);
      expect(fakeClient.lastOutputTokens, 256);
      expect(fakeClient.lastMaxOutputTokens, 1024);
    } finally {
      service.dispose();
    }
  });

  test(
    'recreates LiteRT-LM client when audio media needs an executor',
    () async {
      final firstClient = _FakeLiteRtLmRuntimeClient();
      final secondClient = _FakeLiteRtLmRuntimeClient();
      final clients = <_FakeLiteRtLmRuntimeClient>[firstClient, secondClient];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
      );

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );

        final firstChunks = service
            .generate(
              contextHandle,
              'hello',
              const GenerationParams(maxTokens: 7),
            )
            .toList();
        await firstClient.generateStarted.future;
        firstClient.generated.add('first');
        await firstClient.generated.close();
        await firstChunks;

        final secondChunks = service.generateChat(contextHandle, [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              const LlamaTextContent('Transcribe this.'),
              LlamaAudioContent(
                bytes: Uint8List.fromList(const <int>[1, 2, 3]),
              ),
            ],
          ),
        ], const GenerationParams(maxTokens: 7)).toList();
        await secondClient.generateStarted.future;
        secondClient.generated.add('second');
        await secondClient.generated.close();
        await secondChunks;

        expect(firstClient.disposeCount, 1);
        expect(secondClient.lastVisionBackend, isNull);
        expect(secondClient.lastAudioBackend, 'cpu');
        expect(secondClient.lastMaxNumImages, isNull);
        expect(secondClient.lastVisualTokenBudget, isNull);
        expect(nextClient, 2);
      } finally {
        service.dispose();
      }
    },
  );

  test('buffers stop-sequence tails when no stop is found', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      final chunks = <List<int>>[];
      final subscription = service
          .generate(
            contextHandle,
            'hello',
            const GenerationParams(stopSequences: ['XYZ']),
          )
          .listen(chunks.add);

      await fakeClient.generateStarted.future;
      fakeClient.generated
        ..add('ab')
        ..add('cd')
        ..add('ef');
      unawaited(fakeClient.generated.close());
      await subscription.asFuture<void>();

      expect(utf8.decode(chunks.expand((chunk) => chunk).toList()), 'abcdef');
      expect(fakeClient.cancelCount, 0);
    } finally {
      service.dispose();
    }
  });

  test('skips empty chunks when no stop sequences are configured', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      final chunks = <List<int>>[];
      final subscription = service
          .generate(contextHandle, 'hello', const GenerationParams())
          .listen(chunks.add);

      await fakeClient.generateStarted.future;
      fakeClient.generated
        ..add('')
        ..add('visible');
      unawaited(fakeClient.generated.close());
      await subscription.asFuture<void>();

      expect(chunks, hasLength(1));
      expect(utf8.decode(chunks.single), 'visible');
    } finally {
      service.dispose();
    }
  });

  for (final nativeChat in [false, true]) {
    for (final failure in [
      'handle',
      'media',
      'params',
      'setup',
      'initialize',
    ]) {
      test('admitted LiteRT request clears previous metrics '
          '(chat: $nativeChat, exit: $failure)', () async {
        final firstClient = _FakeLiteRtLmRuntimeClient();
        final nextClient = _FakeLiteRtLmRuntimeClient(blockInitialize: true);
        var clients = 0;
        final service = LiteRtLmService(
          clientFactory: () => clients++ == 0 ? firstClient : nextClient,
        );
        addTearDown(service.dispose);
        final model = await service.loadModel(
          modelFile.path,
          const ModelParams(),
        );
        final context = service.createContext(model, const ModelParams());
        final first = service
            .generate(context, 'first', const GenerationParams())
            .drain<void>();
        await firstClient.generateStarted.future;
        await firstClient.generated.close();
        await first;
        expect(service.getPerformanceContext(context), isNotNull);
        if (failure == 'setup') {
          firstClient.onCreateConversation = service.cancelGeneration;
        }
        final params = failure == 'params'
            ? const GenerationParams(grammar: 'invalid')
            : GenerationParams(speculativeDecoding: failure == 'initialize');
        final handle = failure == 'handle' ? -1 : context;
        final stream = nativeChat
            ? service.generateChat(
                handle,
                failure == 'media'
                    ? [
                        LlamaChatMessage.withContent(
                          role: LlamaChatRole.user,
                          content: [LlamaVideoContent(bytes: Uint8List(1))],
                        ),
                      ]
                    : [
                        LlamaChatMessage.fromText(
                          role: LlamaChatRole.user,
                          text: 'next',
                        ),
                      ],
                params,
              )
            : service.generate(
                handle,
                'next',
                params,
                parts: failure == 'media'
                    ? [LlamaImageContent(bytes: Uint8List(1))]
                    : null,
              );
        final done =
            failure == 'handle' || failure == 'media' || failure == 'params'
            ? expectLater(
                stream,
                emitsError(
                  failure == 'handle'
                      ? isA<StateError>()
                      : isA<UnsupportedError>(),
                ),
              )
            : expectLater(stream, emitsDone);
        if (failure == 'initialize') {
          await nextClient.initializeStarted.future;
          service.cancelGeneration();
          nextClient.completeInitialize();
        }
        await done;
        expect(service.getPerformanceContext(context), isNull);
        expect(firstClient.generateCount, 1);
        expect(nextClient.generateCount, 0);
      });
    }
  }

  test('stores LiteRT-LM runtime metrics as performance context', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient()
      ..metrics = const LiteRtLmRuntimeMetrics(
        inputTokens: 8,
        outputTokens: 5,
        timeToFirstTokenSeconds: 0.05,
        initSeconds: 0.25,
        prefillTokensPerSecond: 40,
        decodeTokensPerSecond: 25,
        wallMilliseconds: 123,
      );
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      final subscription = service
          .generate(contextHandle, 'hello', const GenerationParams())
          .listen((_) {});

      await fakeClient.generateStarted.future;
      fakeClient.generated.add('done');
      unawaited(fakeClient.generated.close());
      await subscription.asFuture<void>();

      final perf = service.getPerformanceContext(contextHandle);
      expect(perf, isNotNull);
      expect(perf!.loadMs, 250);
      expect(perf.promptEvalMs, 200);
      expect(perf.evalMs, 200);
      expect(perf.promptEvalTokens, 8);
      expect(perf.evalTokens, 5);
      expect(perf.sampleCount, 5);
    } finally {
      service.dispose();
    }
  });

  test('clears performance context when runtime metrics fail', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient()
      ..metricsError = StateError('metrics unavailable');
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      final subscription = service
          .generate(contextHandle, 'hello', const GenerationParams())
          .listen((_) {});

      await fakeClient.generateStarted.future;
      fakeClient.generated.add('done');
      unawaited(fakeClient.generated.close());
      await subscription.asFuture<void>();

      expect(service.getPerformanceContext(contextHandle), isNull);
    } finally {
      service.dispose();
    }
  });

  test(
    'cancels when cancellation is requested after conversation setup',
    () async {
      final fakeClient = _FakeLiteRtLmRuntimeClient();
      final service = LiteRtLmService(clientFactory: () => fakeClient);
      fakeClient.onCreateConversation = service.cancelGeneration;

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );

        final chunks = await service
            .generate(contextHandle, 'hello', const GenerationParams())
            .toList();

        expect(chunks, isEmpty);
        expect(fakeClient.createConversationCount, 1);
        expect(fakeClient.generateCount, 0);
        expect(fakeClient.cancelCount, 2);
      } finally {
        service.dispose();
      }
    },
  );

  test('maxTokens less than one is a no-op and clears metrics', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(contextSize: 3072, preferredBackend: GpuBackend.cpu),
      );

      final firstSubscription = service
          .generate(
            contextHandle,
            'hello',
            const GenerationParams(maxTokens: 2, stopSequences: ['STOP']),
          )
          .listen((_) {});

      await fakeClient.generateStarted.future;
      fakeClient.generated.add('alpha STOP hidden');
      await fakeClient.generated.close();
      await firstSubscription.asFuture<void>();

      expect(service.getPerformanceContext(contextHandle), isNotNull);
      expect(fakeClient.lastOutputTokens, 256);
      expect(fakeClient.createConversationCount, 1);
      expect(fakeClient.generateCount, 1);

      final zeroChunks = await service
          .generate(
            contextHandle,
            'should not run',
            const GenerationParams(maxTokens: 0),
          )
          .toList();
      final negativeChunks = await service
          .generate(
            contextHandle,
            'should not run either',
            const GenerationParams(maxTokens: -1),
          )
          .toList();

      expect(zeroChunks, isEmpty);
      expect(negativeChunks, isEmpty);
      expect(service.getPerformanceContext(contextHandle), isNull);
      expect(fakeClient.lastOutputTokens, 256);
      expect(fakeClient.createConversationCount, 1);
      expect(fakeClient.generateCount, 1);
    } finally {
      service.dispose();
    }
  });

  test(
    'freeContext disposes runtime client and clears context metrics',
    () async {
      final firstClient = _FakeLiteRtLmRuntimeClient();
      final secondClient = _FakeLiteRtLmRuntimeClient()
        ..tokenizeResult = const <int>[42];
      final clients = <_FakeLiteRtLmRuntimeClient>[firstClient, secondClient];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
      );

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );
        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );

        final subscription = service
            .generate(
              contextHandle,
              'hello',
              const GenerationParams(stopSequences: ['STOP']),
            )
            .listen((_) {});
        await firstClient.generateStarted.future;
        firstClient.generated.add('done STOP hidden');
        await subscription.asFuture<void>();

        expect(service.getPerformanceContext(contextHandle), isNotNull);

        service.freeContext(contextHandle);
        expect(firstClient.disposeCount, 1);

        final nextContextHandle = service.createContext(
          modelHandle,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );
        expect(nextContextHandle, isNot(contextHandle));
        expect(service.getPerformanceContext(nextContextHandle), isNull);
        expect(await service.tokenize(modelHandle, 'after-free', true), [42]);
        expect(secondClient.lastTokenizeText, 'after-free');
        expect(nextClient, 2);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'createContext disposes pre-context runtime client and applies params',
    () async {
      final firstClient = _FakeLiteRtLmRuntimeClient()
        ..tokenizeResult = const <int>[1];
      final secondClient = _FakeLiteRtLmRuntimeClient()
        ..tokenizeResult = const <int>[2];
      final clients = <_FakeLiteRtLmRuntimeClient>[firstClient, secondClient];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
      );

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(
            contextSize: 2048,
            preferredBackend: GpuBackend.cpu,
          ),
        );

        expect(await service.tokenize(modelHandle, 'before-context', true), [
          1,
        ]);
        expect(firstClient.lastMaxTokens, 2048);

        final contextHandle = service.createContext(
          modelHandle,
          const ModelParams(
            contextSize: 4096,
            preferredBackend: GpuBackend.cpu,
          ),
        );

        expect(firstClient.disposeCount, 1);
        expect(service.getContextSize(contextHandle), 4096);
        expect(await service.tokenize(modelHandle, 'after-context', true), [2]);
        expect(secondClient.lastTokenizeText, 'after-context');
        expect(secondClient.lastMaxTokens, 4096);
        expect(nextClient, 2);
      } finally {
        service.dispose();
      }
    },
  );

  test(
    'recreating context disposes previous runtime client and metrics',
    () async {
      final firstClient = _FakeLiteRtLmRuntimeClient();
      final secondClient = _FakeLiteRtLmRuntimeClient()
        ..tokenizeResult = const <int>[7];
      final clients = <_FakeLiteRtLmRuntimeClient>[firstClient, secondClient];
      var nextClient = 0;
      final service = LiteRtLmService(
        clientFactory: () => clients[nextClient++],
      );

      try {
        final modelHandle = await service.loadModel(
          modelFile.path,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );
        final firstContextHandle = service.createContext(
          modelHandle,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );

        final subscription = service
            .generate(
              firstContextHandle,
              'hello',
              const GenerationParams(stopSequences: ['STOP']),
            )
            .listen((_) {});
        await firstClient.generateStarted.future;
        firstClient.generated.add('done STOP hidden');
        await subscription.asFuture<void>();

        expect(service.getPerformanceContext(firstContextHandle), isNotNull);

        final secondContextHandle = service.createContext(
          modelHandle,
          const ModelParams(
            contextSize: 3072,
            preferredBackend: GpuBackend.cpu,
          ),
        );

        expect(secondContextHandle, isNot(firstContextHandle));
        expect(firstClient.disposeCount, 1);
        expect(
          () => service.getPerformanceContext(firstContextHandle),
          throwsStateError,
        );
        expect(service.getPerformanceContext(secondContextHandle), isNull);
        expect(await service.tokenize(modelHandle, 'after-recreate', true), [
          7,
        ]);
        expect(secondClient.lastTokenizeText, 'after-recreate');
        expect(nextClient, 2);
      } finally {
        service.dispose();
      }
    },
  );

  group('generation controls', () {
    late _FakeLiteRtLmRuntimeClient client;
    late ({String name, bool? isReasoning})? firstChannel;
    late LiteRtLmService service;
    late int context;

    setUp(() async {
      client = _FakeLiteRtLmRuntimeClient();
      firstChannel = (name: 'thought', isReasoning: null);
      service = LiteRtLmService(
        clientFactory: () => client,
        readBundleFirstChannel: (_) => firstChannel,
      );
      final model = await service.loadModel(
        modelFile.path,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu),
      );
      context = service.createContext(model, const ModelParams());
    });

    tearDown(() => service.dispose());

    Future<void> answer() async {
      await client.generateStarted.future;
      client.generated.add('A');
      await client.generated.close();
    }

    Future<void> raw(GenerationParams params) async {
      final done = service.generate(context, 'Hello', params).drain<void>();
      await answer();
      await done;
    }

    Future<void> chat(GenerationParams params, {bool enableThinking = true}) {
      final done = service
          .generateChat(
            context,
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
            ],
            params,
            enableThinking: enableThinking,
          )
          .drain<void>();
      return answer().then((_) => done);
    }

    test('leaves the default penalty unapplied', () async {
      await raw(const GenerationParams(maxTokens: 8));

      expect(client.lastRepetitionPenalty, isNull);
      expect(client.lastPresencePenalty, isNull);
      expect(client.lastThinkingTokenBudget, isNull);
    });

    test('passes non-default penalties to raw generation', () async {
      await raw(const GenerationParams(penalty: 1.3, presencePenalty: -0.4));

      expect(client.lastRepetitionPenalty, 1.3);
      expect(client.lastPresencePenalty, -0.4);
    });

    test('passes only the penalty that differs from its default', () async {
      await chat(const GenerationParams(presencePenalty: 0.6));

      expect(client.lastRepetitionPenalty, isNull);
      expect(client.lastPresencePenalty, 0.6);
    });

    test('passes a thinking budget to native chat generation', () async {
      await chat(
        const GenerationParams(
          penalty: 1.2,
          thinkingBudget: ThinkingBudget(
            maxTokens: 32,
            startTag: '<think>',
            endTag: '</think>',
          ),
        ),
      );

      expect(client.lastThinkingTokenBudget, 32);
      expect(client.lastRepetitionPenalty, 1.2);
    });

    test('sends no budget when thinking is disabled', () async {
      await chat(
        const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 32)),
        enableThinking: false,
      );

      expect(client.lastThinkingTokenBudget, isNull);
    });

    test('accepts a first channel flagged as reasoning', () async {
      firstChannel = (name: 'analysis', isReasoning: true);

      await chat(
        const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 4)),
      );

      expect(client.lastThinkingTokenBudget, 4);
    });

    test('reports the controls the runtime and bundle apply', () {
      expect(service.generationControls(), (
        penalties: true,
        thinkingBudget: true,
      ));
    });

    test('reports no thinking budget for a bundle without a thinking '
        'channel', () async {
      firstChannel = (name: 'tool', isReasoning: null);
      final other = LiteRtLmService(
        clientFactory: () => client,
        readBundleFirstChannel: (_) => firstChannel,
      );
      addTearDown(other.dispose);

      expect(other.generationControls().thinkingBudget, isFalse);
      await other.loadModel(modelFile.path, const ModelParams());
      expect(other.generationControls(), (
        penalties: true,
        thinkingBudget: false,
      ));
    });

    test('rereads the thinking channel when another bundle loads', () async {
      expect(service.generationControls().thinkingBudget, isTrue);

      firstChannel = null;
      final model = await service.loadModel(
        modelFile.path,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu),
      );
      final reloaded = service.createContext(model, const ModelParams());

      expect(service.generationControls(), (
        penalties: true,
        thinkingBudget: false,
      ));
      await expectLater(
        service.generateChat(
          reloaded,
          const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
          ],
          const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 8)),
        ),
        emitsError(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('declares no thinking channel'),
          ),
        ),
      );
      expect(client.generateCount, 0);
    });

    test('reports no controls for a runtime without their APIs', () {
      client
        ..samplingPenalties = false
        ..thinkingBudget = false;

      expect(service.generationControls(), (
        penalties: false,
        thinkingBudget: false,
      ));
    });

    Matcher unsupported(String fragment) => emitsError(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        contains(fragment),
      ),
    );

    for (final (name, params, fragment) in [
      (
        'a penalty below 1.0',
        const GenerationParams(penalty: 0.9),
        'start at 1.0',
      ),
      (
        'penalties with speculative decoding',
        const GenerationParams(presencePenalty: 0.5, speculativeDecoding: true),
        'speculative decoding',
      ),
      (
        'a thinking budget with speculative decoding',
        const GenerationParams(
          thinkingBudget: ThinkingBudget(maxTokens: 8),
          speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
        ),
        'speculative decoding',
      ),
      (
        'a forced thinking message',
        const GenerationParams(
          thinkingBudget: ThinkingBudget(maxTokens: 8, forcedMessage: 'Done.'),
        ),
        'forcedMessage',
      ),
      (
        'a zero thinking budget',
        const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 0)),
        'zero thinking token budget as no budget',
      ),
    ]) {
      test('refuses $name before sending', () async {
        await expectLater(
          service.generateChat(context, const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
          ], params),
          unsupported(fragment),
        );
        expect(client.generateCount, 0);
      });
    }

    test('refuses penalties on a runtime without the penalty API', () async {
      client.samplingPenalties = false;

      await expectLater(
        service.generate(context, 'Hi', const GenerationParams(penalty: 1.0)),
        unsupported('does not export the repetition penalty API'),
      );
      expect(client.generateCount, 0);
    });

    test('refuses a thinking budget on a runtime without the thinking '
        'API', () async {
      client.thinkingBudget = false;

      await expectLater(
        service.generateChat(
          context,
          const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
          ],
          const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 8)),
        ),
        unsupported('does not export the thinking config API'),
      );
      expect(client.generateCount, 0);
    });

    for (final channel in <({String name, bool? isReasoning})?>[
      null,
      (name: 'tool', isReasoning: null),
      (name: 'thought', isReasoning: false),
    ]) {
      test('refuses a thinking budget when the first channel is '
          '$channel', () async {
        firstChannel = channel;

        await expectLater(
          service.generateChat(
            context,
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
            ],
            const GenerationParams(
              thinkingBudget: ThinkingBudget(maxTokens: 8),
            ),
          ),
          unsupported('declares no thinking channel'),
        );
        expect(client.generateCount, 0);
      });
    }

    test('rejects non-finite penalties', () async {
      await expectLater(
        service.generate(
          context,
          'Hi',
          const GenerationParams(presencePenalty: double.nan),
        ),
        emitsError(isArgumentError),
      );
      expect(client.generateCount, 0);
    });
  });

  test('rejects unsupported LiteRT-LM generation params', () async {
    final service = LiteRtLmService();

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'hello',
          const GenerationParams(minP: 0.1),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('minP'),
          ),
        ),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'hello',
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftDspark(
              draftModelPath: 'draft.gguf',
            ),
          ),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('speculativeDecodingConfig.strategy'),
              contains('speculativeDecodingConfig.draftModel'),
              isNot(contains('draftModelPath')),
            ),
          ),
        ),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'hello',
          const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 16)),
        ),
        emitsError(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('raw prompt generation has no thinking budget'),
          ),
        ),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'hello',
          const GenerationParams(
            grammarLazy: true,
            grammarTriggers: [
              GenerationGrammarTrigger.typed(
                type: GrammarTriggerType.word,
                value: '<tool_call>',
              ),
            ],
            preservedTokens: ['<tool_call>'],
            grammarRoot: 'tool_call',
          ),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('GenerationParams: grammarLazy,'),
              contains('grammarLazy'),
              contains('grammarTriggers'),
              contains('preservedTokens'),
              contains('grammarRoot'),
            ),
          ),
        ),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'hello',
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(
              draftTokenMax: 3,
              draftModelPath: 'draft.gguf',
              draftMicroBatchSize: 8,
            ),
          ),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('speculativeDecodingConfig.draftTokenMax'),
              contains('speculativeDecodingConfig.draftMicroBatchSize'),
              contains('speculativeDecodingConfig.draftModel'),
              isNot(contains('draftModelPath')),
            ),
          ),
        ),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'hello',
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(
              draftTokenMax: 4,
              ngramSize: 12,
              ngramSizeM: 16,
              ngramMinHits: 2,
            ),
          ),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('speculativeDecodingConfig.strategy'),
              contains('speculativeDecodingConfig.draftTokenMax'),
              contains('speculativeDecodingConfig.ngramSize'),
              contains('speculativeDecodingConfig.ngramSizeN'),
              contains('speculativeDecodingConfig.ngramSizeM'),
              contains('speculativeDecodingConfig.ngramMinHits'),
            ),
          ),
        ),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'hello',
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(
              draftSplitProbability: 0.1,
            ),
          ),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('speculativeDecodingConfig.draftSplitProbability'),
          ),
        ),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'hello',
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
              strategies: [
                SpeculativeDecodingStrategy.ngramMod,
                SpeculativeDecodingStrategy.mtp,
              ],
              ngramMatch: 2,
              ngramTokenMin: 1,
              ngramTokenMax: 4,
            ),
          ),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('speculativeDecodingConfig.strategy'),
              contains('speculativeDecodingConfig.ngramMatch'),
              contains('speculativeDecodingConfig.ngramTokenMin'),
              contains('speculativeDecodingConfig.ngramTokenMax'),
            ),
          ),
        ),
      );

      await expectLater(
        service.generate(
          contextHandle,
          'hello',
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramCache(
              ngramCacheStaticPath: 'static.ngram',
              ngramCacheDynamicPath: 'dynamic.ngram',
            ),
          ),
        ),
        emitsError(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(
              contains('speculativeDecodingConfig.strategy'),
              contains('speculativeDecodingConfig.ngramCacheStaticPath'),
              contains('speculativeDecodingConfig.ngramCacheDynamicPath'),
            ),
          ),
        ),
      );
    } finally {
      service.dispose();
    }
  });

  test('latches cancellation while LiteRT-LM client initializes', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient(blockInitialize: true);
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(),
      );

      final chunks = <List<int>>[];
      final subscription = service
          .generate(contextHandle, 'hello', const GenerationParams())
          .listen(chunks.add);

      await fakeClient.initializeStarted.future;
      service.cancelGeneration();
      fakeClient.completeInitialize();
      await subscription.asFuture<void>();

      expect(chunks, isEmpty);
      expect(fakeClient.createConversationCount, 0);
      expect(fakeClient.generateCount, 0);
    } finally {
      service.dispose();
    }
  });

  test('suppresses late blocking response after cancellation', () async {
    final fakeClient = _FakeLiteRtLmRuntimeClient();
    final service = LiteRtLmService(clientFactory: () => fakeClient);

    try {
      final modelHandle = await service.loadModel(
        modelFile.path,
        const ModelParams(),
      );
      final contextHandle = service.createContext(
        modelHandle,
        const ModelParams(),
      );

      final chunks = <List<int>>[];
      final subscription = service
          .generate(contextHandle, 'hello', const GenerationParams())
          .listen(chunks.add);

      await fakeClient.generateStarted.future;
      service.cancelGeneration();
      fakeClient.generated.add('late response');
      await fakeClient.generated.close();
      await subscription.asFuture<void>();

      expect(chunks, isEmpty);
      expect(fakeClient.createConversationCount, 1);
      expect(fakeClient.cancelCount, 1);
    } finally {
      service.dispose();
    }
  });

  test('reports platform-level capabilities conservatively', () {
    final service = LiteRtLmService();

    try {
      expect(
        service.getGpuSupport(),
        Platform.isIOS ||
            Platform.isAndroid ||
            liteRtLmGateAbi() == Abi.macosArm64 ||
            liteRtLmGateAbi() == Abi.linuxX64 ||
            liteRtLmGateAbi() == Abi.windowsX64,
      );
      expect(service.getVramInfo(), (total: 0, free: 0));
    } finally {
      service.dispose();
    }
  });
}

String _expectedAutoLiteRtLmBackend() {
  if (Platform.isAndroid || liteRtLmGateAbi() == Abi.macosArm64) {
    return 'gpu';
  }
  return 'cpu';
}

class _FakeLiteRtLmRuntimeClient extends LiteRtLmRuntimeClient {
  LiteRtLmNativeSettlement settlement = LiteRtLmNativeSettlement.settled;

  @override
  LiteRtLmNativeSettlement get nativeSettlement => settlement;

  _FakeLiteRtLmRuntimeClient({
    bool blockInitialize = false,
    this.initializeError,
  }) : _initializeBlocker = blockInitialize ? Completer<void>() : null;

  final Completer<void> initializeStarted = Completer<void>();
  final Completer<void> generateStarted = Completer<void>();
  StreamController<String> generated = StreamController<String>();
  final Completer<void>? _initializeBlocker;
  final Object? initializeError;
  String? lastModelPath;
  String? lastBackend;
  String? lastVisionBackend;
  String? lastAudioBackend;
  int? lastMaxTokens;
  int? lastOutputTokens;
  int? lastMaxNumImages;
  String? lastCacheDir;
  bool? lastSpeculativeDecoding;
  int? lastMinLogLevel;
  LiteRtLmActivationDataType? lastActivationDataType;
  int? lastPrefillChunkSize;
  bool? lastParallelFileSectionLoading;
  String? lastDispatchLibDir;
  int? lastNumberOfThreads;
  int? lastSetMinLogLevel;
  double? lastTemperature;
  int? lastTopK;
  double? lastTopP;
  int? lastSeed;
  bool? lastNpuBackend;
  String? lastLoraPath;
  String? lastSystemMessage;
  List<Map<String, dynamic>>? lastMessages;
  List<Map<String, dynamic>>? lastTools;
  Map<String, dynamic>? lastExtraContext;
  String? lastTokenizeText;
  bool? lastTokenizeAddSpecial;
  List<int>? lastDetokenizeTokens;
  String? lastMessageJson;
  Map<String, dynamic>? lastMessageExtraContext;
  int? lastVisualTokenBudget;
  int? lastMaxOutputTokens;
  double? lastRepetitionPenalty;
  double? lastPresencePenalty;
  int? lastThinkingTokenBudget;
  bool jsonSchemaSupport = false;
  bool? lastJsonSchemaConfig;
  String? lastJsonSchema;
  @override
  bool get supportsJsonSchemaConstraints => jsonSchemaSupport;
  bool jsonSchemaThinking = false;
  @override
  bool get supportsJsonSchemaThinking => jsonSchemaThinking;
  bool finishReasons = true;
  @override
  bool get supportsFinishReasons => finishReasons;

  bool samplingPenalties = true;
  bool thinkingBudget = true;
  LiteRtLmFinishReason? finishReason;
  List<int> tokenizeResult = const <int>[];
  List<int>? Function(String text, bool addSpecial)? onTokenize;
  String? Function(List<int> tokens)? onDetokenize;
  String detokenizeResult = '';
  LiteRtLmRuntimeMetrics? metrics;
  Object? metricsError;
  void Function()? onCreateConversation;
  void Function()? onInitialize;
  String? lastPromptTemplate;
  String? lastPrompt;
  final List<({String? template, bool seeded})> conversations = [];
  String Function(String? promptTemplate)? onRenderMessage;

  /// Whether this runtime has the render entry point. Without it the service
  /// creates no probe conversation.
  bool rendersMessages = false;
  int renderMessageCount = 0;
  int createConversationCount = 0;
  int generateCount = 0;
  int cancelCount = 0;
  Object? cancelError;
  int disposeCount = 0;
  Object? disposeError;

  @override
  Future<void> initialize({
    required String modelPath,
    String backend = 'gpu',
    String? visionBackend,
    String? audioBackend,
    int maxTokens = 4096,
    int outputTokens = 256,
    int? prefillTokens,
    int? maxNumImages,
    String? cacheDir,
    bool speculativeDecoding = true,
    int minLogLevel = 3,
    LiteRtLmActivationDataType? activationDataType,
    int? prefillChunkSize,
    bool? parallelFileSectionLoading,
    String? dispatchLibDir,
    int? numberOfThreads,
  }) {
    lastModelPath = modelPath;
    lastBackend = backend;
    lastVisionBackend = visionBackend;
    lastAudioBackend = audioBackend;
    lastMaxTokens = maxTokens;
    lastOutputTokens = outputTokens;
    lastMaxNumImages = maxNumImages;
    lastCacheDir = cacheDir;
    lastSpeculativeDecoding = speculativeDecoding;
    lastMinLogLevel = minLogLevel;
    lastActivationDataType = activationDataType;
    lastPrefillChunkSize = prefillChunkSize;
    lastParallelFileSectionLoading = parallelFileSectionLoading;
    lastDispatchLibDir = dispatchLibDir;
    lastNumberOfThreads = numberOfThreads;
    onInitialize?.call();
    if (!initializeStarted.isCompleted) {
      initializeStarted.complete();
    }
    final error = initializeError;
    if (error != null) {
      throw error;
    }
    return _initializeBlocker?.future ?? Future<void>.value();
  }

  void completeInitialize() {
    if (_initializeBlocker != null && !_initializeBlocker.isCompleted) {
      _initializeBlocker.complete();
    }
  }

  @override
  void setMinLogLevel(int level) {
    _checkNotDisposed();
    lastSetMinLogLevel = level;
  }

  @override
  void createConversation({
    String? systemMessage,
    String? promptTemplate,
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? extraContext,
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    int seed = 1,
    bool npuBackend = false,
    String? loraPath,
    bool jsonSchemaConstraints = false,
  }) {
    _checkNotDisposed();
    lastJsonSchemaConfig = jsonSchemaConstraints;
    lastTemperature = temperature;
    lastTopK = topK;
    lastTopP = topP;
    lastSeed = seed;
    lastNpuBackend = npuBackend;
    lastLoraPath = loraPath;
    lastSystemMessage = systemMessage;
    lastPromptTemplate = promptTemplate;
    conversations.add((
      template: promptTemplate,
      seeded:
          systemMessage != null ||
          messages != null ||
          tools != null ||
          extraContext != null,
    ));
    lastMessages = messages
        ?.map(Map<String, dynamic>.from)
        .toList(growable: false);
    lastTools = tools?.map(Map<String, dynamic>.from).toList(growable: false);
    lastExtraContext = extraContext == null
        ? null
        : Map<String, dynamic>.from(extraContext);
    createConversationCount += 1;
    onCreateConversation?.call();
  }

  @override
  bool get supportsMessageRendering => rendersMessages;

  @override
  String renderMessageToString(Map<String, dynamic> message) {
    _checkNotDisposed();
    if (!rendersMessages) {
      throw ArgumentError('Failed to lookup the render symbol.');
    }
    renderMessageCount += 1;
    return onRenderMessage?.call(lastPromptTemplate) ??
        liteRtLmContentShapeProbeText;
  }

  @override
  List<int> tokenize(String text, {bool addSpecial = true}) {
    _checkNotDisposed();
    lastTokenizeText = text;
    lastTokenizeAddSpecial = addSpecial;
    return onTokenize?.call(text, addSpecial) ?? tokenizeResult;
  }

  @override
  String detokenize(List<int> tokens) {
    _checkNotDisposed();
    lastDetokenizeTokens = List<int>.from(tokens);
    return onDetokenize?.call(tokens) ?? detokenizeResult;
  }

  @override
  bool get supportsSamplingPenalties => samplingPenalties;

  @override
  bool get supportsThinkingBudget => thinkingBudget;

  @override
  LiteRtLmFinishReason? get lastFinishReason => finishReason;

  @override
  Stream<String> generate(
    String prompt, {
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
  }) {
    _checkNotDisposed();
    lastPrompt = prompt;
    lastMaxOutputTokens = maxOutputTokens;
    lastRepetitionPenalty = repetitionPenalty;
    lastPresencePenalty = presencePenalty;
    lastThinkingTokenBudget = null;
    generateCount += 1;
    if (!generateStarted.isCompleted) {
      generateStarted.complete();
    }
    return generated.stream;
  }

  @override
  Stream<String> generateMessageJson(
    String messageJson, {
    Map<String, dynamic>? extraContext,
    int? visualTokenBudget,
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
    int? thinkingTokenBudget,
    String? jsonSchema,
  }) {
    _checkNotDisposed();
    lastMessageJson = messageJson;
    lastJsonSchema = jsonSchema;
    lastRepetitionPenalty = repetitionPenalty;
    lastPresencePenalty = presencePenalty;
    lastThinkingTokenBudget = thinkingTokenBudget;
    lastMessageExtraContext = extraContext == null
        ? null
        : Map<String, dynamic>.from(extraContext);
    lastVisualTokenBudget = visualTokenBudget;
    lastMaxOutputTokens = maxOutputTokens;
    generateCount += 1;
    if (!generateStarted.isCompleted) {
      generateStarted.complete();
    }
    return generated.stream;
  }

  @override
  LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds}) {
    _checkNotDisposed();
    final error = metricsError;
    if (error != null) {
      throw error;
    }
    final currentMetrics = metrics;
    if (currentMetrics != null) {
      return LiteRtLmRuntimeMetrics(
        inputTokens: currentMetrics.inputTokens,
        outputTokens: currentMetrics.outputTokens,
        timeToFirstTokenSeconds: currentMetrics.timeToFirstTokenSeconds,
        initSeconds: currentMetrics.initSeconds,
        prefillTokensPerSecond: currentMetrics.prefillTokensPerSecond,
        decodeTokensPerSecond: currentMetrics.decodeTokensPerSecond,
        wallMilliseconds: wallMilliseconds,
      );
    }
    return LiteRtLmRuntimeMetrics(
      inputTokens: 0,
      outputTokens: 0,
      timeToFirstTokenSeconds: null,
      initSeconds: null,
      prefillTokensPerSecond: null,
      decodeTokensPerSecond: null,
      wallMilliseconds: wallMilliseconds,
    );
  }

  @override
  void cancel() {
    _checkNotDisposed();
    cancelCount += 1;
    final error = cancelError;
    if (error != null) throw error;
  }

  @override
  void dispose() {
    disposeCount += 1;
    if (!generated.isClosed) {
      unawaited(generated.close());
    }
    final error = disposeError;
    if (error != null) throw error;
  }

  void _checkNotDisposed() {
    if (disposeCount > 0) {
      throw StateError('Fake LiteRT-LM client has been disposed.');
    }
  }
}

// FlatBuffers section header plus LlmMetadata protobuf, following LiteRT-LM
// v0.18.0 schema/core/litertlm_header_schema.fbs and runtime/proto/llm_metadata.proto.
Uint8List _thinkingBundle({required int modelType, String? template}) {
  List<int> varint(int value) {
    final bytes = <int>[];
    while (value >= 128) {
      bytes.add((value & 127) | 128);
      value >>= 7;
    }
    return bytes..add(value);
  }

  final text = template == null ? null : utf8.encode(template);
  final metadata = [
    0x32,
    2,
    (modelType << 3) | 2,
    0,
    if (text != null) ...[0x3a, ...varint(text.length), ...text],
  ];
  final bytes = Uint8List(136 + metadata.length);
  bytes.setAll(0, ascii.encode('LITERTLM'));
  final data = ByteData.sublistView(bytes);
  data.setUint64(24, 116, Endian.little);
  const header = 32;
  for (final (offset, value) in [
    (0, 12),
    (12, 8),
    (20, 12),
    (32, 8),
    (36, 4),
    (40, 1),
    (44, 16),
    (60, 12),
  ]) {
    data.setUint32(header + offset, value, Endian.little);
  }
  for (final (offset, value) in [
    (4, 8),
    (6, 12),
    (10, 8),
    (24, 6),
    (26, 8),
    (28, 4),
    (48, 12),
    (50, 24),
    (54, 8),
    (56, 16),
    (58, 4),
  ]) {
    data.setUint16(header + offset, value, Endian.little);
  }
  data.setUint8(header + 64, 5);
  data.setUint64(header + 68, 136, Endian.little);
  data.setUint64(header + 76, bytes.length, Endian.little);
  bytes.setAll(136, metadata);
  return bytes;
}

String _nativeMessage(Object error) =>
    error is LlamaException ? error.message : (error as StateError).message;
