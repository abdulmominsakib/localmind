@TestOn('vm && (mac-os || linux)')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_legacy_service_client.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DynamicLibrary library;
  late String libraryPath;
  final variants = <String, DynamicLibrary>{};
  int nativeInt(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  void set(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  String nativeText(String name) => library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'fixture_$name',
      )()
      .toDartString();
  void emit(String? json, {bool finalChunk = false, int reason = 1}) {
    final text = json?.toNativeUtf8(allocator: calloc) ?? nullptr;
    try {
      library.lookupFunction<
        Void Function(Pointer<Utf8>, Bool, Int),
        void Function(Pointer<Utf8>, bool, int)
      >('fixture_client_emit')(text, finalChunk, reason);
    } finally {
      if (text != nullptr) calloc.free(text);
    }
  }

  LiteRtLmV1RuntimeClient client() {
    final result = LiteRtLmV1RuntimeClient(library);
    addTearDown(() async {
      if (result.nativeSettlement == LiteRtLmNativeSettlement.pending) {
        set('fail', 0);
        set('fail_copies', 0);
        result.cancel();
        if (nativeInt('client_active') != 0) {
          emit(null, finalChunk: true, reason: 4);
        }
        final clock = Stopwatch()..start();
        while (result.nativeSettlement == LiteRtLmNativeSettlement.pending) {
          if (clock.elapsed > const Duration(seconds: 5)) {
            fail('fixture native turn did not settle during teardown');
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
      result.dispose();
    });
    return result;
  }

  Future<void> initialize(LiteRtLmRuntimeClientContract client) =>
      client.initialize(
        modelPath: '/secret/models/m.litertlm',
        backend: 'cpu',
        cacheDir: '/secret/cache',
        speculativeDecoding: false,
        numberOfThreads: 2,
      );
  Future<void> waitForSend(int before) async {
    final clock = Stopwatch()..start();
    while (nativeInt('sends') == before) {
      if (clock.elapsed > const Duration(seconds: 5)) {
        fail('service did not enter v1 generation');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_v1_client_');
    libraryPath =
        '${directory.path}/client.${Platform.isMacOS ? 'dylib' : 'so'}';
    final result = await Process.run('cc', [
      '-shared',
      '-fPIC',
      '-pthread',
      'test/fixtures/litert_lm/c_api_v1_client.c',
      '-o',
      libraryPath,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    library = DynamicLibrary.open(libraryPath);
    for (final entry in <String, String>{
      'callback': 'PROXY_ABI=1',
      'allocation': 'ALLOCATION_FAILURE_ABI=2',
      'finish': 'FINISH_ABI=0',
      'penalty': 'OMIT_TURN_PRESENCE',
      'logging': 'OMIT_LOG_LEVEL',
    }.entries) {
      final path =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        '-D${entry.value}',
        'test/fixtures/litert_lm/c_api_v1_client.c',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      variants[entry.key] = DynamicLibrary.open(path);
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(() {
    library.lookupFunction<Void Function(), void Function()>(
      'fixture_metadata_reset',
    )();
    set('fail_copies', 0);
  });

  test(
    'reentrant final data preserves a fresh pending turn finish state',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      final nextStarted = Completer<void>();
      final firstClosed = Completer<void>();
      final firstChunks = <String>[];
      Future<List<String>>? second;
      final first = adapter
          .generate('first')
          .listen(
            (text) {
              firstChunks.add(text);
              if (nextStarted.isCompleted) return;
              try {
                adapter.createConversation();
                second = adapter.generate('second').toList();
                nextStarted.complete();
              } on Object catch (error, stack) {
                nextStarted.completeError(error, stack);
              }
            },
            onDone: () {
              if (!firstClosed.isCompleted) firstClosed.complete();
            },
            onError: (Object error, StackTrace stack) {
              if (!nextStarted.isCompleted) {
                nextStarted.completeError(error, stack);
              }
              if (!firstClosed.isCompleted) {
                firstClosed.completeError(error, stack);
              }
            },
          );
      final firstFinished = Future.wait([
        nextStarted.future,
        firstClosed.future,
      ]);
      emit(
        '{"role":"assistant","content":[{"type":"text","text":"first answer"}]}',
        finalChunk: true,
        reason: 2,
      );
      try {
        await firstFinished.timeout(const Duration(seconds: 5));
        expect(firstChunks, ['first answer']);
        expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.pending);
        expect(adapter.lastFinishReason, isNull);
      } finally {
        if (second != null) {
          emit(
            '{"role":"assistant","content":[{"type":"text","text":"second answer"}]}',
            finalChunk: true,
            reason: 1,
          );
          expect((await second!).join(), 'second answer');
        }
        await first.cancel();
      }
      expect(adapter.lastFinishReason, LiteRtLmFinishReason.stop);
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.settled);
    },
  );

  test(
    'default public client initializes v1 and releases native owners',
    () async {
      final legacy = LiteRtLmRuntimeClient(libraryPath: libraryPath);
      addTearDown(legacy.dispose);
      await initialize(LiteRtLmLegacyServiceClient(legacy));
      expect(legacy.supportsFinishReasons, isTrue);
      expect(legacy.tokenize('ABC', addSpecial: false), [3, 65, 67]);
      legacy.dispose();
      expect(nativeInt('live'), 0);
    },
  );
  test(
    'injected client routes initialization, tokenizer and logging to v1',
    () async {
      final adapter = client();
      await initialize(adapter);
      expect(nativeInt('client_log_level'), 3);
      adapter.setMinLogLevel(1000);
      expect(nativeInt('client_log_level'), 1000);
      expect(adapter.tokenize('ABC', addSpecial: false), [3, 65, 67]);
      expect(adapter.detokenize([1]), 'decoded 世界🙂');
      expect(adapter.supportsFinishReasons, isTrue);
      expect(adapter.supportsSamplingPenalties, isTrue);
      expect(adapter.supportsThinkingBudget, isFalse);
      expect(adapter.supportsJsonSchemaConstraints, isFalse);
      adapter.dispose();
      expect(nativeInt('live'), 0);
    },
  );
  test(
    'logging checks canonical status and copies diagnostics before cleanup',
    () async {
      final adapter = client();
      await initialize(adapter);
      set('fail', 81);
      expect(
        () => adapter.setMinLogLevel(2),
        throwsA(
          isA<LlamaModelException>().having(
            (e) => e.message,
            'status',
            contains('stage81'),
          ),
        ),
      );
      set('fail', 0);
      expect(
        () => adapter.setMinLogLevel(6),
        throwsA(isA<LlamaArgumentException>()),
      );
    },
  );
  test(
    'message stream parses channels, copies text and sets native cause before close',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.configureResponseThinkingTags(
        startTag: '<think>',
        endTag: '</think>',
      );
      adapter.createConversation(
        systemMessage: '{"plain":"世界"}',
        messages: [
          {'role': 'user', 'content': 'history'},
        ],
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'lookup',
              'parameters': {'type': 'object'},
            },
          },
        ],
      );
      final output = adapter
          .generateMessageJson(
            jsonEncode({
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'question'},
              ],
            }),
            maxOutputTokens: 12,
            repetitionPenalty: 1.2,
            presencePenalty: 0.25,
          )
          .toList();
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.pending);
      expect(adapter.lastFinishReason, isNull);
      expect(jsonDecode(nativeText('message')), {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'question'},
        ],
      });
      emit('{"role":"assistant","channels":{"thought":"reason 世界"}}');
      emit(
        '{"role":"assistant","content":[{"type":"text","text":"answer🙂"}]}',
        finalChunk: true,
        reason: 2,
      );
      expect((await output).join(), '<think>reason 世界</think>answer🙂');
      expect(adapter.lastFinishReason, LiteRtLmFinishReason.length);
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.settled);
      expect(adapter.readMetrics(wallMilliseconds: 123).inputTokens, 21);
      expect(nativeInt('copies'), 0);
      expect(nativeInt('proxies'), 0);
    },
  );
  test('active tool responses are validated and encoded once', () async {
    final adapter = client();
    await initialize(adapter);
    adapter.createConversation();
    final message = {
      'role': 'tool',
      'content': [
        {
          'type': 'tool_response',
          'name': 'lookup',
          'response': {'value': '{"quoted":"世界"}'},
        },
      ],
    };
    final output = adapter.generateMessageJson(jsonEncode(message)).toList();
    expect(jsonDecode(nativeText('message')), message);
    emit(null, finalChunk: true);
    expect(await output, isEmpty);
  });
  test(
    'per-send context is validated and snapshotted before native entry',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      final context = <String, dynamic>{
        'enable_thinking': false,
        'nested': {'text': '世界'},
      };
      final output = adapter
          .generateMessageJson(
            '{"role":"user","content":"p"}',
            extraContext: context,
          )
          .toList();
      context['enable_thinking'] = true;
      (context['nested'] as Map)['text'] = 'changed';
      expect(jsonDecode(nativeText('extra_context')), {
        'enable_thinking': false,
        'nested': {'text': '世界'},
      });
      emit(null, finalChunk: true);
      await output;
      final cyclic = <String, dynamic>{};
      cyclic['self'] = cyclic;
      final before = nativeInt('sends');
      expect(
        () => adapter.generateMessageJson(
          '{"role":"user","content":"p"}',
          extraContext: cyclic,
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(nativeInt('sends'), before);
    },
  );
  test(
    'v1 declared reasoning channels use reasoning markers exactly once',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      adapter.configureResponseThinkingTags(
        startTag: '<think>',
        endTag: '</think>',
      );
      final output = adapter.generate('reason').toList();
      emit(
        '{"role":"assistant","channels":{"analysis":"reason 世界"},"reasoning_content":"reason 世界"}',
      );
      emit(
        '{"role":"assistant","content":[{"type":"text","text":"answer"}]}',
        finalChunk: true,
      );
      expect((await output).join(), '<think>reason 世界</think>answer');
    },
  );
  for (final name in ['callback', 'allocation']) {
    test(
      'incompatible $name ABI refuses capabilities and conversation allocation',
      () async {
        final selected = variants[name]!;
        final adapter = LiteRtLmV1RuntimeClient(selected);
        addTearDown(adapter.dispose);
        await initialize(adapter);
        expect(adapter.supportsFinishReasons, isFalse);
        expect(adapter.supportsSamplingPenalties, isFalse);
        expect(
          () => adapter.createConversation(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(
          selected.lookupFunction<Int Function(), int Function()>(
            'fixture_created',
          )(),
          0,
        );
      },
    );
  }
  test('missing penalty setter refuses before starting generation', () async {
    final selected = variants['penalty']!;
    final adapter = LiteRtLmV1RuntimeClient(selected);
    addTearDown(adapter.dispose);
    await initialize(adapter);
    adapter.createConversation();
    expect(adapter.supportsSamplingPenalties, isFalse);
    expect(
      () => adapter.generate('p', presencePenalty: 0.5),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(
      selected.lookupFunction<Int Function(), int Function()>(
        'fixture_sends',
      )(),
      0,
    );
  });
  test('missing logging export refuses before creating an engine', () async {
    final selected = variants['logging']!;
    final adapter = LiteRtLmV1RuntimeClient(selected);
    addTearDown(adapter.dispose);
    await expectLater(
      initialize(adapter),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(
      selected.lookupFunction<Int Function(), int Function()>('fixture_live')(),
      0,
    );
  });
  test(
    'unknown finish ABI keeps finish null without inferring it from counts',
    () async {
      final selected = variants['finish']!;
      final adapter = LiteRtLmV1RuntimeClient(selected);
      addTearDown(adapter.dispose);
      await initialize(adapter);
      adapter.createConversation();
      expect(adapter.supportsFinishReasons, isFalse);
      final output = adapter.generate('p').toList();
      selected.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_emit',
      )(2);
      expect(await output, isEmpty);
      expect(adapter.lastFinishReason, isNull);
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.settled);
    },
  );
  for (final mode in ['failed-drain', 'missing-final']) {
    test('$mode retains the native family in an isolated process', () async {
      final result = await Process.run('dart', [
        'run',
        'test/fixtures/litert_lm_v1_client_retention.dart',
        libraryPath,
        mode,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
      expect(result.stdout, contains('$mode client lifetime controls passed'));
    });
  }
  Future<void> cancelFirstGeneration(LiteRtLmV1RuntimeClient adapter) async {
    await initialize(adapter);
    adapter.createConversation();
    final subscription = adapter.generate('cancel').listen((_) {});
    final cancellation = subscription.cancel();
    emit(null, finalChunk: true, reason: 4);
    await cancellation;
    expect(adapter.lastFinishReason, LiteRtLmFinishReason.cancelled);
  }

  test('a cancelled generation keeps its performance counters', () async {
    final adapter = client();
    await cancelFirstGeneration(adapter);
    final metrics = adapter.readMetrics(wallMilliseconds: 123);
    expect(metrics.inputTokens, 21);
    expect(metrics.wallMilliseconds, 123);
  });

  test(
    'a cancelled generation without readable counters reports them unavailable',
    () async {
      set('metadata_fail', 7);
      final adapter = client();
      await cancelFirstGeneration(adapter);
      expect(
        () => adapter.readMetrics(wallMilliseconds: 123),
        throwsA(isA<LlamaStateException>()),
      );
    },
  );
  test(
    'a cancelled generation that ends in error reports no counters',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      final subscription = adapter.generate('cancel').listen((_) {});
      final cancellation = subscription.cancel();
      emit(null, finalChunk: true, reason: 5);
      await cancellation;
      expect(adapter.lastFinishReason, LiteRtLmFinishReason.error);
      expect(
        () => adapter.readMetrics(wallMilliseconds: 123),
        throwsA(isA<LlamaStateException>()),
      );
    },
  );
  test('a cancelled turn with lost copies reports no counters', () async {
    final adapter = client();
    await initialize(adapter);
    adapter.createConversation();
    set('fail_copies', 1);
    final subscription = adapter.generate('cancel').listen((_) {});
    emit('{"role":"assistant","content":"lost"}');
    final cancellation = subscription.cancel();
    emit(null, finalChunk: true, reason: 4);
    await cancellation;
    set('fail_copies', 0);
    expect(
      () => adapter.readMetrics(wallMilliseconds: 123),
      throwsA(isA<LlamaStateException>()),
    );
  });
  test('a cancel racing natural completion keeps its counters', () async {
    final adapter = client();
    await initialize(adapter);
    adapter.createConversation();
    final subscription = adapter.generate('race').listen((_) {});
    final cancellation = subscription.cancel();
    emit(null, finalChunk: true, reason: 1);
    await cancellation;
    expect(adapter.lastFinishReason, LiteRtLmFinishReason.stop);
    expect(adapter.readMetrics(wallMilliseconds: 9).inputTokens, 21);
  });
  test('a disposed adapter does not serve a cancelled snapshot', () async {
    final adapter = LiteRtLmV1RuntimeClient(library);
    await initialize(adapter);
    adapter.createConversation();
    final subscription = adapter.generate('cancel').listen((_) {});
    final cancellation = subscription.cancel();
    emit(null, finalChunk: true, reason: 4);
    await cancellation;
    expect(adapter.readMetrics(wallMilliseconds: 1).inputTokens, 21);
    adapter.dispose();
    expect(
      () => adapter.readMetrics(wallMilliseconds: 1),
      throwsA(isA<LlamaStateException>()),
    );
  });
  test(
    'a fresh conversation after a cancelled one reads its own counters',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      final subscription = adapter.generate('cancel').listen((_) {});
      final cancellation = subscription.cancel();
      emit(null, finalChunk: true, reason: 4);
      await cancellation;
      set('metadata_fail', 7);
      adapter.createConversation();
      expect(
        () => adapter.readMetrics(wallMilliseconds: 1),
        throwsA(isA<LlamaModelException>()),
      );
      set('metadata_fail', 0);
    },
  );
  test(
    'subscription cancellation waits for final and allows a fresh child',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      final subscription = adapter.generate('cancel').listen((_) {});
      var cancelled = false;
      final cancellation = subscription.cancel().then((_) {
        cancelled = true;
      });
      try {
        await Future<void>.delayed(Duration.zero);
        expect(cancelled, isFalse);
        expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.pending);
        expect(() => adapter.dispose(), throwsA(isA<LlamaStateException>()));
      } finally {
        emit(null, finalChunk: true, reason: 4);
        await cancellation;
      }
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.settled);
      expect(adapter.lastFinishReason, LiteRtLmFinishReason.cancelled);
      adapter.createConversation();
      final next = adapter.generate('fresh').toList();
      emit(
        '{"role":"assistant","content":[{"type":"text","text":"fresh answer"}]}',
        finalChunk: true,
      );
      expect((await next).join(), 'fresh answer');
    },
  );
  test(
    'copy loss rejects the stream while preserving native finish and settled engine',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      set('fail_copies', 1);
      final rejected = expectLater(
        adapter.generate('loss').toList(),
        throwsA(isA<LiteRtLmV1CopyLossException>()),
      );
      emit('{"role":"assistant","content":"lost"}');
      emit(null, finalChunk: true, reason: 2);
      await rejected;
      expect(adapter.lastFinishReason, LiteRtLmFinishReason.length);
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.settled);
      expect(nativeInt('copies'), 0);
      expect(nativeInt('proxies'), 0);
      set('fail_copies', 0);
      adapter.createConversation();
      final next = adapter.generate('retry').toList();
      emit(null, finalChunk: true);
      expect(await next, isEmpty);
    },
  );
  test(
    'synchronous failed send clears earlier finish reason and releases child',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      final first = adapter.generate('first').toList();
      emit(null, finalChunk: true, reason: 2);
      await first;
      expect(adapter.lastFinishReason, LiteRtLmFinishReason.length);
      set('fail', 17);
      expect(
        () => adapter.generate('failed'),
        throwsA(isA<LlamaModelException>()),
      );
      expect(adapter.lastFinishReason, isNull);
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.settled);
      expect(nativeInt('proxies'), 0);
      set('fail', 0);
    },
  );
  test(
    'incomplete families refuse before native generation instead of legacy fallthrough',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      final before = nativeInt('sends');
      for (final call in <void Function()>[
        () => adapter.generateMessageJson(
          '{"role":"user","content":"p"}',
          thinkingTokenBudget: 4,
        ),
        () => adapter.generateMessageJson(
          '{"role":"user","content":"p"}',
          visualTokenBudget: 28,
        ),
        () => adapter.generateMessageJson(
          '{"role":"user","content":"p"}',
          jsonSchema: '{}',
        ),

        () => adapter.generateMessageJson(
          '{"role":"user","content":[{"type":"image","blob":"AQID"}]}',
        ),
        () => adapter.createConversation(loraPath: '/lora'),
        () => adapter.createConversation(jsonSchemaConstraints: true),
      ]) {
        expect(call, throwsA(isA<LlamaUnsupportedException>()));
      }
      expect(nativeInt('sends'), before);
      await expectLater(
        adapter.createEmbeddingSession(
          modelPath: '/embedding',
          backend: 'cpu',
          cacheDir: '/cache',
          maxInputLength: 32,
          numberOfThreads: 2,
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );
  test(
    'text LoRA refusal preserves the existing native conversation',
    () async {
      final adapter = client();
      await initialize(adapter);
      adapter.createConversation();
      final created = nativeInt('created');
      final live = nativeInt('live');
      expect(
        () => adapter.createConversation(loraPath: '/private/adapter.lora'),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'runtime restriction',
            allOf(
              contains('pinned native LiteRT-LM runtime'),
              contains('advanced engine'),
              contains('litert-lm-native#99'),
              isNot(contains('/private/')),
            ),
          ),
        ),
      );
      expect(nativeInt('created'), created);
      expect(nativeInt('live'), live);
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.settled);
    },
  );
  test(
    'real service injection reaches v1 text generation, limits and metrics',
    () async {
      final model = File('${directory.path}/service.litertlm')
        ..writeAsStringSync('fake model');
      final clients = <LiteRtLmV1RuntimeClient>[];
      final service = LiteRtLmService(
        runtimeClientFactory: () {
          final result = LiteRtLmV1RuntimeClient(library);
          clients.add(result);
          return result;
        },
        linkParentDirectory: directory,
        useTempCacheDir: false,
        readBundleChatTemplate: (_) => null,
        readBundleFirstChannel: (_) => null,
      );
      addTearDown(() {
        service.dispose();
        for (final adapter in clients) {
          adapter.dispose();
        }
      });
      final params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        numberOfThreads: 2,
        contextSize: 64,
        liteRtLmCacheDir: '${directory.path}/cache',
      );
      final modelHandle = await service.loadModel(model.path, params);
      final context = service.createContext(modelHandle, params);
      expect(service.reportsFinishReasons(), isTrue);
      final before = nativeInt('sends');
      final output = service
          .generate(
            context,
            'hello 世界',
            const GenerationParams(maxTokens: 12, temp: 0, seed: 7),
          )
          .toList();
      await waitForSend(before);
      emit(
        '{"role":"assistant","content":[{"type":"text","text":"service answer"}]}',
        finalChunk: true,
        reason: 2,
      );
      expect(
        utf8.decode((await output).expand((chunk) => chunk).toList()),
        'service answer',
      );
      expect(service.lastGenerationLimit, BackendGenerationLimit.maxTokens);
      expect(service.nativeSettlement, LiteRtLmNativeSettlement.settled);
      final chatBefore = nativeInt('sends');
      final chat = service
          .generateChat(
            context,
            const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.system,
                text: 'system 世界',
              ),
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'history',
              ),
              LlamaChatMessage.fromText(
                role: LlamaChatRole.assistant,
                text: 'old answer',
              ),
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'lookup now',
              ),
            ],
            const GenerationParams(maxTokens: 12, temp: 0, seed: 7),
            tools: [
              {
                'type': 'function',
                'function': {
                  'name': 'lookup',
                  'parameters': {
                    'type': 'object',
                    'properties': {
                      'query': {'type': 'string'},
                    },
                  },
                },
              },
            ],
            enableThinking: false,
          )
          .toList();
      await waitForSend(chatBefore);
      expect(jsonDecode(nativeText('message'))['role'], 'user');
      emit(
        '{"role":"assistant","tool_calls":[{"type":"function","function":{"name":"lookup","arguments":{"query":"世界"}}}]}',
        finalChunk: true,
      );
      final toolResponse = jsonDecode(
        utf8.decode((await chat).expand((chunk) => chunk).toList()),
      );
      expect(toolResponse['tool_calls'][0]['function']['arguments'], {
        'query': '世界',
      });
      service.dispose();
      expect(nativeInt('live'), 0);
    },
  );
}
