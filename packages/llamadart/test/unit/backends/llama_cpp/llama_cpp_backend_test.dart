@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:llamadart/src/core/engine/engine_capabilities.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/embedding.dart';
import 'package:llamadart/src/core/engine/engine_observer.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/llama_logging.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/generation_usage.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/inference/next_token_scores.dart';
import 'package:llamadart/src/core/models/model_load_options.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/config/lora_config.dart';
import 'package:test/test.dart';

import '../../../support/slow_exiting_worker.dart';

void main() {
  group('NativeLlamaBackend request routing', () {
    late _FakeWorkerHarness harness;
    late _TrackingNativeLlamaBackend backend;

    setUp(() {
      harness = _FakeWorkerHarness();
      backend = _TrackingNativeLlamaBackend(initialSendPort: harness.sendPort);
    });

    tearDown(() async {
      await backend.dispose();
      harness.dispose();
    });

    test(
      'rejects LiteRT-LM embedding mode before any worker request',
      () async {
        await expectLater(
          backend.modelLoad(
            'ok.gguf',
            const ModelParams(liteRtLmEmbeddingEngine: true),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'runtime',
              contains('llama.cpp'),
            ),
          ),
        );
        expect(harness.received, isEmpty);
      },
    );

    test('rejects LiteRT-LM-only fields before any worker request', () async {
      await expectLater(
        backend.modelLoad(
          'ok.gguf',
          const ModelParams(liteRtLmPrefillChunkSize: 128),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            contains('natively: liteRtLmPrefillChunkSize.'),
          ),
        ),
      );
      expect(harness.received, isEmpty);
    });

    test('names the subtype mismatch before the embedding-engine '
        'rejection', () async {
      await expectLater(
        backend.modelLoad(
          'ok.gguf',
          const LiteRtLmModelParams(embeddingEngine: true),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            contains('Use LlamaCppModelParams.'),
          ),
        ),
      );
      expect(harness.received, isEmpty);
    });

    test('rejects LiteRtLmModelParams before any worker request', () async {
      await expectLater(
        backend.modelLoad('ok.gguf', const LiteRtLmModelParams()),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            contains('Use LlamaCppModelParams.'),
          ),
        ),
      );
      expect(harness.received, isEmpty);
    });

    test('setLogLevel forwards request through worker port', () async {
      await backend.setLogLevel(LlamaLogLevel.info);

      expect(
        harness.received.any((message) => message is LogLevelRequest),
        isTrue,
      );
    });

    test('model and context lifecycle routes handle responses', () async {
      final modelHandle = await backend.modelLoad(
        'ok.gguf',
        const ModelParams(),
      );
      expect(modelHandle, 11);

      final contextHandle = await backend.contextCreate(
        modelHandle,
        const ModelParams(),
      );
      expect(contextHandle, 22);

      await backend.modelFree(modelHandle);
      await backend.contextFree(contextHandle);
      expect(
        harness.received.whereType<ModelFreeRequest>().length,
        greaterThanOrEqualTo(1),
      );
      expect(
        harness.received.whereType<ContextFreeRequest>().length,
        greaterThanOrEqualTo(1),
      );
    });

    test('modelLoad and contextCreate surface worker errors', () async {
      expect(
        () => backend.modelLoad('error.gguf', const ModelParams()),
        throwsException,
      );
      expect(
        () => backend.contextCreate(-1, const ModelParams()),
        throwsException,
      );
    });

    test('free operations surface worker errors', () async {
      await expectLater(
        () => backend.contextFree(-1),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('context free failed'),
          ),
        ),
      );

      await expectLater(
        () => backend.modelFree(-1),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('model free failed'),
          ),
        ),
      );

      await expectLater(
        () => backend.multimodalContextFree(-1),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('mm free failed'),
          ),
        ),
      );
    });

    test('tokenize detokenize metadata and context-size requests', () async {
      expect(await backend.tokenize(1, 'hello'), <int>[1, 2, 3]);
      expect(await backend.detokenize(1, const <int>[1, 2]), 'decoded');
      expect(await backend.modelMetadata(1), <String, String>{'a': 'b'});
      expect(await backend.getContextSize(1), 2048);
    });

    test('embed and embedBatch requests are supported', () async {
      expect(await backend.embed(1, 'hello', normalize: true), <double>[
        0.1,
        0.2,
      ]);
      expect(
        await backend.embedBatch(1, const <String>['a', 'bb']),
        <List<double>>[
          <double>[1.0, 10.0],
          <double>[2.0, 10.0],
        ],
      );
      expect(
        await backend.embedBatch(1, const <String>[]),
        const <List<double>>[],
      );
      expect(() => backend.embed(1, 'boom'), throwsException);
      expect(
        () => backend.embedBatch(1, const <String>['boom']),
        throwsException,
      );
    });

    test('a generation whose request cannot reach the worker fails alone and '
        'the next one runs', () async {
      final port = RawReceivePort();
      addTearDown(port.close);
      final unsendable = GenerationParams(
        speculativeDecodingConfig: SpeculativeDecodingConfig(
          strategies: const [SpeculativeDecodingStrategy.ngramMod],
          draftModelDownload: ModelLoadOptions(
            cancelToken: _PortCancelToken(port),
          ),
        ),
      );

      await expectLater(
        backend.generate(1, 'ok', unsendable),
        emitsInOrder([emitsError(isA<ArgumentError>()), emitsDone]),
      );
      expect(
        await backend.generate(1, 'ok', const GenerationParams()).toList(),
        isNotEmpty,
      );
    });

    test(
      'dispatch failure invalidates previous counters until the next dispatch',
      () async {
        await backend.generate(1, 'ok', const GenerationParams()).drain<void>();
        final port = RawReceivePort();
        addTearDown(port.close);
        final params = GenerationParams(
          speculativeDecodingConfig: SpeculativeDecodingConfig(
            strategies: const [SpeculativeDecodingStrategy.ngramMod],
            draftModelDownload: ModelLoadOptions(
              cancelToken: _PortCancelToken(port),
            ),
          ),
        );
        await expectLater(
          backend.generate(1, 'bad', params),
          emitsInOrder([emitsError(isA<ArgumentError>()), emitsDone]),
        );
        expect(await backend.getPerformanceContext(1), isNull);
        expect((await backend.getPerformanceContext(2))?.evalTokens, 7);
        await backend.generate(1, 'ok', const GenerationParams()).drain<void>();
        expect((await backend.getPerformanceContext(1))?.evalTokens, 7);
      },
    );

    Future<void> staleContext(NativeLlamaBackend target) async {
      final running = target
          .generate(1, 'pending', const GenerationParams())
          .drain<void>();
      while (harness.received.whereType<GenerateRequest>().isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final request = harness.received.whereType<GenerateRequest>().last;
      target.cancelGeneration();
      final queued = target
          .generate(1, 'ok', const GenerationParams())
          .drain<void>();
      target.cancelGeneration();
      await queued;
      request.sendPort.send(DoneResponse());
      await running;
    }

    for (final operation in ['embed', 'batch', 'content', 'score', 'tts']) {
      test(
        '$operation revives counters after an unsent queued cancellation',
        () async {
          final proxy = ReceivePort();
          addTearDown(proxy.close);
          proxy.listen((message) {
            if (message is EmbedContentBatchRequest) {
              message.sendPort.send(
                EmbedBatchResponse([
                  [0.1, 0.2],
                ]),
              );
            } else {
              harness.sendPort.send(message);
            }
          });
          final target = NativeLlamaBackend(initialSendPort: proxy.sendPort);
          addTearDown(target.dispose);
          await staleContext(target);
          expect(await target.getPerformanceContext(1), isNull);
          await expectLater(target.embed(1, 'boom'), throwsException);
          expect(await target.getPerformanceContext(1), isNull);
          switch (operation) {
            case 'embed':
              await target.embed(1, 'ok');
            case 'batch':
              await target.embedBatch(1, ['ok']);
            case 'content':
              await target.embedContentBatch(1, [
                LlamaEmbeddingInput([const LlamaTextContent('ok')]),
              ]);
            case 'score':
              await target.scoreNextToken(
                1,
                'ok',
                candidates: [1],
                topK: 1,
                reusePromptPrefix: false,
              );
            case 'tts':
              await target.synthesizeTextToSpeech(
                1,
                2,
                const BackendTextToSpeechRequest(text: 'hello'),
              );
          }
          expect((await target.getPerformanceContext(1))?.evalTokens, 7);
        },
      );
    }

    test(
      'dispose clears stale marks before a worker reuses its context handle',
      () async {
        final target = NativeLlamaBackend(
          initialSendPort: harness.sendPort,
          workerEntrypoint: _counterWorkerEntry,
        );
        addTearDown(target.dispose);
        await staleContext(target);
        expect(await target.getPerformanceContext(1), isNull);
        await target.dispose();
        expect((await target.getPerformanceContext(1))?.evalTokens, 7);
      },
    );

    test(
      'a stale perf lookup cannot revive when a later request dispatches',
      () async {
        final proxy = ReceivePort();
        addTearDown(proxy.close);
        final held = <PerformanceContextRequest>[];
        proxy.listen((message) {
          if (message is PerformanceContextRequest) {
            held.add(message);
          } else {
            harness.sendPort.send(message);
          }
        });
        final target = NativeLlamaBackend(initialSendPort: proxy.sendPort);
        addTearDown(target.dispose);
        await staleContext(target);
        final lookup = target.getPerformanceContext(1);
        await pumpEventQueue();
        await target.generate(1, 'ok', const GenerationParams()).drain<void>();
        for (final request in held) {
          harness.sendPort.send(request);
        }
        expect(await lookup, isNull);
        expect(held, isEmpty, reason: 'stale counters need no worker RPC');
      },
    );

    test('generate streams bytes and supports error forwarding', () async {
      final chunks = await backend
          .generate(1, 'ok', const GenerationParams())
          .toList();
      expect(chunks, <List<int>>[
        <int>[65],
        <int>[66],
      ]);

      await expectLater(
        backend.generate(1, 'boom', const GenerationParams()).drain<void>(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            'Exception: generation failed',
          ),
        ),
      );

      await expectLater(
        backend
            .generate(1, 'unsupported', const GenerationParams())
            .drain<void>(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('reasoning-budget wrapper'),
          ),
        ),
      );

      await expectLater(
        backend
            .generate(1, 'inference', const GenerationParams())
            .drain<void>(),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            contains('grammar sampler failed'),
          ),
        ),
      );
    });

    test(
      'generationLimitOf reports the limit of each finished stream',
      () async {
        final limited = backend.generate(
          1,
          'pending',
          const GenerationParams(),
        );
        final chunks = <List<int>>[];
        final done = limited.listen(chunks.add).asFuture<void>();
        await Future<void>.delayed(Duration.zero);
        final generateRequest = harness.received
            .whereType<GenerateRequest>()
            .last;
        generateRequest.sendPort
          ..send(TokenResponse(<int>[67]))
          ..send(
            DoneResponse(generationLimit: BackendGenerationLimit.contextSize),
          );
        await done;

        expect(chunks, <List<int>>[
          <int>[67],
        ]);
        expect(
          backend.generationLimitOf(limited),
          BackendGenerationLimit.contextSize,
        );

        final natural = backend.generate(1, 'ok', const GenerationParams());
        await natural.drain<void>();
        expect(backend.generationLimitOf(natural), isNull);
        expect(
          backend.generationLimitOf(limited),
          BackendGenerationLimit.contextSize,
        );
      },
    );

    test(
      'prompt penalty policy crosses the worker boundary only on its explicit route',
      () async {
        expect(backend.supportsPromptPenaltiesWithGrammar, isTrue);
        const params = GenerationParams(
          grammar: 'root ::= "ok"',
          grammarLazy: true,
          grammarTriggers: [GenerationGrammarTrigger(type: 0, value: 'go')],
        );
        for (final enabled in [false, true, false]) {
          final stream = enabled
              ? backend.generateWithPromptPenalties(
                  1,
                  '<m>prompt',
                  params,
                  mediaMarker: '<m>',
                )
              : backend.generateChatPrompt(
                  1,
                  '<m>prompt',
                  params,
                  mediaMarker: '<m>',
                );
          final done = stream.drain<void>();
          await Future<void>.delayed(Duration.zero);
          final request = harness.received.whereType<GenerateRequest>().last;
          expect(request.countPromptTokensInPenalties, enabled);
          expect(request.chatMediaMarker, '<m>');
          expect(request.params.grammarLazy, isTrue);
          expect(request.params.grammarTriggers.single.value, 'go');
          request.sendPort.send(DoneResponse());
          await done;
        }
      },
    );

    test('generateChatPrompt sends the worker the prompt with its marker, '
        'generate without one', () async {
      GenerateRequest sent() =>
          harness.received.whereType<GenerateRequest>().last;

      final chat = backend
          .generateChatPrompt(
            1,
            '<m>a <img>',
            const GenerationParams(),
            mediaMarker: '<m>',
          )
          .drain<void>();
      await Future<void>.delayed(Duration.zero);
      expect(sent().prompt, '<m>a <img>');
      expect(sent().chatMediaMarker, '<m>');
      sent().sendPort.send(DoneResponse());
      await chat;

      final caller = backend
          .generate(1, '<img>b', const GenerationParams())
          .drain<void>();
      await Future<void>.delayed(Duration.zero);
      expect(sent().prompt, '<img>b');
      expect(sent().chatMediaMarker, isNull);
      sent().sendPort.send(DoneResponse());
      await caller;
    });

    test(
      'generationLimitOf ignores a limit after the caller cancels',
      () async {
        final cancelled = backend.generate(
          1,
          'pending',
          const GenerationParams(),
        );
        final subscription = cancelled.listen((_) {});
        await Future<void>.delayed(Duration.zero);
        final generateRequest = harness.received
            .whereType<GenerateRequest>()
            .last;
        await subscription.cancel();
        generateRequest.sendPort.send(
          DoneResponse(generationLimit: BackendGenerationLimit.maxTokens),
        );
        await Future<void>.delayed(Duration.zero);

        expect(backend.generationLimitOf(cancelled), isNull);
      },
    );

    test(
      'generationUsageOf reports the usage of each finished stream',
      () async {
        const usage = LlamaGenerationUsage(
          promptTokens: 9,
          cachedPromptTokens: 2,
          completionTokens: 1,
          duration: Duration(milliseconds: 4),
        );
        final reported = backend.generate(
          1,
          'pending',
          const GenerationParams(),
        );
        final done = reported.drain<void>();
        await Future<void>.delayed(Duration.zero);
        final generateRequest = harness.received
            .whereType<GenerateRequest>()
            .last;
        expect(backend.generationUsageOf(reported), isNull);
        generateRequest.sendPort
          ..send(TokenResponse(<int>[67]))
          ..send(DoneResponse(generationUsage: usage));
        await done;

        expect(backend.generationUsageOf(reported), same(usage));

        final unreported = backend.generate(1, 'ok', const GenerationParams());
        await unreported.drain<void>();
        expect(backend.generationUsageOf(unreported), isNull);
        expect(backend.generationUsageOf(reported), same(usage));
      },
    );

    test('generationUsageOf is null for a stream that failed', () async {
      final failed = backend.generate(1, 'pending', const GenerationParams());
      final done = failed.drain<void>();
      await Future<void>.delayed(Duration.zero);
      harness.received.whereType<GenerateRequest>().last.sendPort.send(
        ErrorResponse('decode failed'),
      );
      await expectLater(done, throwsA(anything));

      expect(backend.generationUsageOf(failed), isNull);
    });

    group('generation cancel flags', () {
      late _RecordingAllocator allocator;
      late NativeLlamaBackend flagBackend;

      setUp(() {
        allocator = _RecordingAllocator();
        flagBackend = NativeLlamaBackend(
          initialSendPort: harness.sendPort,
          cancelFlagAllocator: allocator,
        );
        addTearDown(allocator.release);
        addTearDown(flagBackend.dispose);
      });

      List<GenerateRequest> generateRequests() =>
          harness.received.whereType<GenerateRequest>().toList();

      int flagValue(GenerateRequest request) =>
          Pointer<Int8>.fromAddress(request.cancelTokenAddress).value;

      Future<GenerateRequest> startPending() async {
        flagBackend
            .generate(1, 'pending', const GenerationParams())
            .listen((_) {});
        await Future<void>.delayed(Duration.zero);
        return generateRequests().last;
      }

      test('cancelling a subscription raises only its own flag', () async {
        final subscription = flagBackend
            .generate(1, 'pending', const GenerationParams())
            .listen((_) {});
        await Future<void>.delayed(Duration.zero);
        final request = generateRequests().single;
        expect(flagValue(request), 0);

        await subscription.cancel();

        expect(flagValue(request), 1);
        expect(allocator.freed, isEmpty);
        request.sendPort.send(DoneResponse());
        await Future<void>.delayed(Duration.zero);
        expect(allocator.freed, [request.cancelTokenAddress]);
      });

      test('a finished generation keeps its freed flag untouched', () async {
        await flagBackend.generate(1, 'ok', const GenerationParams()).toList();
        final request = generateRequests().single;

        expect(allocator.freed, [request.cancelTokenAddress]);
        expect(flagValue(request), 0);
      });

      test('rejects a generation that overlaps an uncancelled one', () async {
        await startPending();

        await expectLater(
          flagBackend.generate(1, 'ok', const GenerationParams()).drain<void>(),
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('already in progress'),
            ),
          ),
        );
        expect(generateRequests(), hasLength(1));
      });

      for (final cancelled in const <String>[
        'subscription',
        'cancelGeneration',
      ]) {
        test('a generation after a $cancelled cancel starts once the cancelled '
            'run ends', () async {
          final subscription = flagBackend
              .generate(1, 'pending', const GenerationParams())
              .listen((_) {});
          await Future<void>.delayed(Duration.zero);
          final first = generateRequests().single;
          if (cancelled == 'subscription') {
            await subscription.cancel();
          } else {
            flagBackend.cancelGeneration();
          }

          final chunks = <List<int>>[];
          final next = flagBackend
              .generate(1, 'ok', const GenerationParams())
              .listen(chunks.add)
              .asFuture<void>();
          await Future<void>.delayed(Duration.zero);
          if (cancelled == 'cancelGeneration') {
            await subscription.cancel();
          }
          expect(generateRequests(), hasLength(1));

          first.sendPort.send(DoneResponse());
          await next;

          final second = generateRequests().last;
          expect(generateRequests(), hasLength(2));
          expect(second.cancelTokenAddress, isNot(first.cancelTokenAddress));
          expect(chunks, <List<int>>[
            <int>[65],
            <int>[66],
          ]);
          expect(allocator.freed, [
            first.cancelTokenAddress,
            second.cancelTokenAddress,
          ]);
          expect(flagValue(second), 0);
        });
      }

      test(
        'a worker error on the cancelled run starts the queued one',
        () async {
          final firstDone = flagBackend
              .generate(1, 'pending', const GenerationParams())
              .drain<void>();
          await Future<void>.delayed(Duration.zero);
          final first = generateRequests().single;
          flagBackend.cancelGeneration();
          final next = flagBackend
              .generate(1, 'ok', const GenerationParams())
              .toList();

          first.sendPort.send(ErrorResponse('decode failed'));

          await expectLater(firstDone, throwsA(isA<Exception>()));
          expect(await next, hasLength(2));
          expect(generateRequests(), hasLength(2));
        },
      );

      test('an engine subscription cancel before the first token raises the '
          'flag, and a generation right after it waits for the run', () async {
        final engine = LlamaEngine(flagBackend);
        await engine.loadModel('model.gguf');
        final subscription = engine.generate('pending').listen((_) {});
        while (generateRequests().isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        final first = generateRequests().single;

        unawaited(subscription.cancel());
        final next = engine.generate('ok').join();

        expect(flagValue(first), 1);
        await Future<void>.delayed(Duration.zero);
        expect(generateRequests(), hasLength(1));
        first.sendPort.send(DoneResponse());
        expect(await next, 'AB');
        expect(generateRequests(), hasLength(2));
      });

      for (final cancelSubscription in [false, true]) {
        test(
          'unsent cancellation clears only its context perf (subscription: $cancelSubscription)',
          () async {
            await flagBackend
                .generate(1, 'ok', const GenerationParams())
                .toList();
            expect((await flagBackend.getPerformanceContext(1))!.evalTokens, 7);
            final first = await startPending();
            flagBackend.cancelGeneration();
            final subscription = flagBackend
                .generate(1, 'ok', const GenerationParams())
                .listen((_) {});
            if (cancelSubscription) {
              await subscription.cancel();
            } else {
              flagBackend.cancelGeneration();
            }
            expect(await flagBackend.getPerformanceContext(1), isNull);
            expect((await flagBackend.getPerformanceContext(2))!.evalTokens, 7);
            first.sendPort.send(DoneResponse());
            await Future<void>.delayed(Duration.zero);
            expect(
              await flagBackend.getPerformanceContext(1),
              isNull,
              reason:
                  'Completion of the earlier request cannot revive stale counters.',
            );
            expect(generateRequests(), hasLength(2));
            await flagBackend
                .generate(1, 'ok', const GenerationParams())
                .toList();
            expect((await flagBackend.getPerformanceContext(1))!.evalTokens, 7);
          },
        );
      }

      test('cancelGeneration ends a queued generation unsent', () async {
        final first = await startPending();
        flagBackend.cancelGeneration();
        final chunks = <List<int>>[];
        final next = flagBackend
            .generate(1, 'ok', const GenerationParams())
            .listen(chunks.add)
            .asFuture<void>();

        flagBackend.cancelGeneration();
        await next;
        first.sendPort.send(DoneResponse());
        await Future<void>.delayed(Duration.zero);

        expect(chunks, isEmpty);
        expect(generateRequests(), hasLength(1));
      });

      test('a cancelled queued subscription frees the queue slot', () async {
        final first = await startPending();
        flagBackend.cancelGeneration();
        final dropped = flagBackend
            .generate(1, 'ok', const GenerationParams())
            .listen((_) {});
        await dropped.cancel();

        final next = flagBackend
            .generate(1, 'ok', const GenerationParams())
            .toList();
        first.sendPort.send(DoneResponse());

        expect(await next, hasLength(2));
        expect(generateRequests(), hasLength(2));
      });

      test('rejects a generation while another is queued', () async {
        await startPending();
        flagBackend.cancelGeneration();
        flagBackend.generate(1, 'ok', const GenerationParams()).listen((_) {});

        await expectLater(
          flagBackend.generate(1, 'ok', const GenerationParams()).drain<void>(),
          throwsA(isA<LlamaStateException>()),
        );
      });

      test('dispose ends a queued generation unsent', () async {
        final first = await startPending();
        flagBackend.cancelGeneration();
        final chunks = <List<int>>[];
        final next = flagBackend
            .generate(1, 'ok', const GenerationParams())
            .listen(chunks.add)
            .asFuture<void>();

        final disposed = flagBackend.dispose();
        await next;
        first.sendPort.send(DoneResponse());
        await disposed;

        expect(chunks, isEmpty);
        expect(generateRequests(), hasLength(1));
        expect(allocator.freed, [first.cancelTokenAddress]);
      });

      test(
        'a generation queued during dispose ends unsent when the run ends',
        () async {
          harness.holdNextDispose = true;
          final first = await startPending();
          final disposed = flagBackend.dispose();
          await harness.disposeReceived.future;
          final chunks = <List<int>>[];
          final next = flagBackend
              .generate(1, 'ok', const GenerationParams())
              .listen(chunks.add)
              .asFuture<void>();

          first.sendPort.send(DoneResponse());
          await next;
          harness.acknowledgeHeldDispose();
          await disposed;

          expect(chunks, isEmpty);
          expect(generateRequests(), hasLength(1));
        },
      );

      test(
        'dispose ends a queued generation when the cancelled run never ends',
        () async {
          harness.holdNextDispose = true;
          final first = await startPending();
          final disposed = flagBackend.dispose();
          await harness.disposeReceived.future;
          final next = flagBackend
              .generate(1, 'ok', const GenerationParams())
              .toList();

          harness.acknowledgeHeldDispose();
          await disposed;

          expect(await next, isEmpty);
          expect(generateRequests(), hasLength(1));
          expect(allocator.freed, [first.cancelTokenAddress]);
        },
      );
    });

    test('diagnostic and multimodal endpoints route correctly', () async {
      expect(await backend.getBackendName(), 'CPU');
      expect(await backend.getAvailableBackends(), 'CPU, METAL');
      expect(await backend.getResolvedGpuLayers(), 12);
      expect(await backend.isGpuSupported(), isTrue);
      expect(await backend.getVramInfo(), (total: 100, free: 40));

      final perf = await backend.getPerformanceContext(1);
      expect(perf, isNotNull);
      expect(perf!.speculativeDraftTokens, 0);
      expect(perf.speculativeAcceptedDraftTokens, 0);
      expect(perf.speculativeDraftAttempts, 10);
      expect(perf.speculativeVerifyTokens, 11);
      expect(perf.speculativeReplayTokens, 12);

      final mmHandle = await backend.multimodalContextCreate(1, 'mmproj.gguf');
      expect(mmHandle, 33);
      expect(await backend.supportsAudio(mmHandle!), isTrue);
      expect(await backend.supportsVision(mmHandle), isFalse);
      expect(await backend.supportsVideoRuntime(mmHandle), isFalse);
      await backend.multimodalContextFree(mmHandle);
      expect(
        () => backend.multimodalContextCreate(-1, 'mmproj.gguf'),
        throwsException,
      );
    });

    test('routes the text-to-speech model support probe', () async {
      expect(
        await backend.textToSpeechModelUnsupportedReason(
          BackendTextToSpeechModel.chatterbox,
        ),
        'needs v0.9.0',
      );
      expect(
        await backend.textToSpeechModelUnsupportedReason(
          BackendTextToSpeechModel.qwen3Tts,
        ),
        isNull,
      );
      await expectLater(
        backend.textToSpeechModelUnsupportedReason(
          BackendTextToSpeechModel.pocketTts,
        ),
        throwsA(
          isA<Exception>().having(
            (error) => '$error',
            'message',
            contains('probe failed'),
          ),
        ),
      );
      expect(
        harness.received.whereType<TextToSpeechModelSupportRequest>().map(
          (request) => request.model,
        ),
        <BackendTextToSpeechModel>[
          BackendTextToSpeechModel.chatterbox,
          BackendTextToSpeechModel.qwen3Tts,
          BackendTextToSpeechModel.pocketTts,
        ],
      );
    });

    test(
      'routes text-to-speech capability, progress, result, and cancel',
      () async {
        final capabilities = await backend.textToSpeechCapabilities(22, 33);
        expect(capabilities.isSupported, isTrue);
        expect(capabilities.model, BackendTextToSpeechModel.qwen3Tts);
        expect(capabilities.sampleRateHz, 24000);

        final progress = <BackendTextToSpeechProgress>[];
        final result = await backend.synthesizeTextToSpeech(
          22,
          33,
          const BackendTextToSpeechRequest(text: 'Hello.'),
          onProgress: progress.add,
        );
        expect(progress, hasLength(1));
        expect(result.samples, <double>[0.25, -0.25]);
        expect(result.sampleRateHz, 24000);
        expect(result.channelCount, 1);
        final capabilityRequest = harness.received
            .whereType<TextToSpeechCapabilitiesRequest>()
            .single;
        final synthesisRequest = harness.received
            .whereType<TextToSpeechSynthesizeRequest>()
            .single;
        expect(
          (capabilityRequest.contextHandle, capabilityRequest.mmContextHandle),
          (22, 33),
        );
        expect(
          (synthesisRequest.contextHandle, synthesisRequest.mmContextHandle),
          (22, 33),
        );

        harness.holdTextToSpeech = true;
        final pending = backend.synthesizeTextToSpeech(
          22,
          33,
          const BackendTextToSpeechRequest(text: 'Cancel.'),
        );
        await harness.textToSpeechStarted.future;
        backend.cancelTextToSpeech();
        await Future<void>.delayed(Duration.zero);
        expect(
          harness.received.whereType<TextToSpeechCancelRequest>(),
          isNotEmpty,
        );
        harness.finishHeldTextToSpeech();
        await pending;
      },
    );

    test(
      'a cancel before the request is sent is already in its flag',
      () async {
        harness.holdTextToSpeech = true;
        final pending = backend.synthesizeTextToSpeech(
          22,
          33,
          const BackendTextToSpeechRequest(text: 'Cancel early.'),
        );
        backend.cancelTextToSpeech();
        await harness.textToSpeechStarted.future;
        await Future<void>.delayed(Duration.zero);
        expect(harness.cancelFlagAtRequest, 1);
        expect(
          harness.received.whereType<TextToSpeechCancelRequest>(),
          hasLength(1),
        );
        harness.finishHeldTextToSpeech();
        await pending;
      },
    );

    test(
      'frees the cancel flag on the terminal response, not on cancel',
      () async {
        final allocator = _RecordingAllocator();
        addTearDown(allocator.release);
        final flagBackend = NativeLlamaBackend(
          initialSendPort: harness.sendPort,
          cancelFlagAllocator: allocator,
        );
        harness.holdTextToSpeech = true;
        final pending = flagBackend.synthesizeTextToSpeech(
          22,
          33,
          const BackendTextToSpeechRequest(text: 'Hold.'),
        );
        await harness.textToSpeechStarted.future;
        final address = harness.received
            .whereType<TextToSpeechSynthesizeRequest>()
            .last
            .cancelFlagAddress;
        expect(allocator.allocated, [address]);
        expect(harness.cancelFlagAtRequest, 0);

        flagBackend.cancelTextToSpeech();
        await Future<void>.delayed(Duration.zero);
        expect(Pointer<Int8>.fromAddress(address).value, 1);
        expect(allocator.freed, isEmpty);

        harness.finishHeldTextToSpeech();
        await pending;
        expect(allocator.freed, [address]);
        await flagBackend.dispose();
        expect(allocator.freed, [address]);
      },
    );

    test(
      'dispose frees a running synthesis cancel flag after the worker acks',
      () async {
        final allocator = _RecordingAllocator();
        addTearDown(allocator.release);
        final flagBackend = NativeLlamaBackend(
          initialSendPort: harness.sendPort,
          cancelFlagAllocator: allocator,
        );
        harness.holdTextToSpeech = true;
        final pending = flagBackend.synthesizeTextToSpeech(
          22,
          33,
          const BackendTextToSpeechRequest(text: 'Hold.'),
        );
        await harness.textToSpeechStarted.future;
        final flag = Pointer<Int8>.fromAddress(
          harness.received
              .whereType<TextToSpeechSynthesizeRequest>()
              .last
              .cancelFlagAddress,
        );

        harness.holdNextDispose = true;
        final disposed = flagBackend.dispose();
        await harness.disposeReceived.future;
        expect(flag.value, 1);
        expect(allocator.freed, isEmpty);

        harness.acknowledgeHeldDispose();
        await disposed;
        expect(allocator.freed, [flag.address]);

        flag.value = 0;
        flagBackend.cancelTextToSpeech();
        expect(flag.value, 0);

        harness.finishHeldTextToSpeech();
        await pending;
        expect(allocator.freed, [flag.address]);
      },
    );

    test('a failed worker startup frees the cancel flag', () async {
      final allocator = _RecordingAllocator();
      addTearDown(allocator.release);
      final flagBackend = NativeLlamaBackend(
        workerEntrypoint: _failingInitializationWorkerEntry,
        cancelFlagAllocator: allocator,
      );
      addTearDown(flagBackend.dispose);

      await expectLater(
        flagBackend.synthesizeTextToSpeech(
          22,
          33,
          const BackendTextToSpeechRequest(text: 'Never sent.'),
        ),
        throwsA(isA<LlamaBackendInitializationException>()),
      );
      expect(allocator.allocated, hasLength(1));
      expect(allocator.freed, allocator.allocated);
    });

    test(
      'dispose keeps the cancel flag of a synthesis claimed during it',
      () async {
        final allocator = _RecordingAllocator();
        addTearDown(allocator.release);
        final flagBackend = NativeLlamaBackend(
          workerEntrypoint: _delayedTextToSpeechRejectingWorkerEntry,
          cancelFlagAllocator: allocator,
        );
        addTearDown(flagBackend.dispose);
        final startup = flagBackend.modelLoad(
          'never.gguf',
          const ModelParams(),
        );
        final disposed = flagBackend.dispose();
        final synthesis = flagBackend.synthesizeTextToSpeech(
          22,
          33,
          const BackendTextToSpeechRequest(text: 'Next worker.'),
        );
        await expectLater(
          startup,
          throwsA(isA<LlamaBackendInitializationException>()),
        );
        await disposed;
        expect(allocator.allocated, hasLength(1));
        expect(allocator.freed, isEmpty);

        await expectLater(
          synthesis,
          throwsA(isA<LlamaTextToSpeechException>()),
        );
        expect(allocator.freed, allocator.allocated);
      },
    );

    test('preserves speech error subtypes from the worker', () async {
      await expectLater(
        backend.synthesizeTextToSpeech(
          22,
          33,
          const BackendTextToSpeechRequest(text: 'audio-format-error'),
        ),
        throwsA(isA<LlamaAudioFormatException>()),
      );
      await expectLater(
        backend.synthesizeTextToSpeech(
          22,
          33,
          const BackendTextToSpeechRequest(text: 'tts-error'),
        ),
        throwsA(isA<LlamaTextToSpeechException>()),
      );
    });

    test('decision requests route through the worker', () async {
      final capabilities = await backend.decisionCapabilities(11);
      expect(capabilities.isSupported, isTrue);

      final head = await backend.decisionHeadLoad(
        11,
        'head.safetensors',
        configPath: 'config.json',
      );
      expect(head.handle, 44);
      expect(head.deviceName, 'Metal');
      final load = harness.received.whereType<DecisionHeadLoadRequest>().single;
      expect(load.modelHandle, 11);
      expect(load.headPath, 'head.safetensors');
      expect(load.configPath, 'config.json');

      final outputs = await backend.decisionRun(44, [
        BackendDecisionSequence(
          tokens: Int32List.fromList([5, 6, 7, 8]),
          markers: Int32List.fromList([1, 3]),
          questionType: DecisionQuestionType.choice,
        ),
      ]);
      expect(outputs.single.logits, [1.0, 3.0]);
      expect(outputs.single.actLogits, [0.5, -0.5]);
      final run = harness.received.whereType<DecisionRunRequest>().single;
      expect(run.headHandle, 44);
      expect(run.sequences.single.tokens, [5, 6, 7, 8]);

      await backend.decisionHeadFree(44);
      expect(
        harness.received.whereType<DecisionHeadFreeRequest>().single.headHandle,
        44,
      );
    });

    test('decision capabilities pass an unsupported reply through', () async {
      final capabilities = await backend.decisionCapabilities(12);

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, 'not modern-bert');
    });

    test('decision outputs keep the order of their sequences', () async {
      final markers = [
        [1],
        [2, 3],
        [4, 5, 6],
      ];

      final outputs = await backend.decisionRun(44, [
        for (final positions in markers)
          BackendDecisionSequence(
            tokens: Int32List(8),
            markers: Int32List.fromList(positions),
            questionType: DecisionQuestionType.choice,
          ),
      ]);

      expect([for (final output in outputs) output.logits], markers);
    });

    test('an unexpected decision reply is a decision error', () async {
      await expectLater(
        backend.decisionRun(45, const []),
        throwsA(
          isA<LlamaDecisionException>().having(
            (error) => error.message,
            'message',
            contains('Unexpected llama.cpp worker response (DoneResponse)'),
          ),
        ),
      );
    });

    test('decisionHeadFree during dispose returns without a request', () async {
      harness.holdDispose = true;
      final disposing = backend.dispose();
      await pumpEventQueue();

      await backend.decisionHeadFree(3).timeout(const Duration(seconds: 2));

      expect(harness.received.whereType<DecisionHeadFreeRequest>(), isEmpty);
      harness.releaseDispose();
      await disposing;
    });

    test('decision errors keep the worker error kind', () async {
      await expectLater(
        backend.decisionHeadLoad(11, 'bad.safetensors'),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('type_emb.weight'),
          ),
        ),
      );
      await expectLater(
        backend.decisionHeadLoad(11, 'unsupported.safetensors'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await expectLater(
        backend.decisionRun(-1, const []),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(
        backend.decisionRun(44, [
          BackendDecisionSequence(
            tokens: Int32List(0),
            markers: Int32List(0),
            questionType: DecisionQuestionType.choice,
          ),
        ]),
        throwsA(isA<LlamaInferenceException>()),
      );
      await expectLater(
        backend.decisionCapabilities(-1),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(
        backend.decisionHeadFree(-1),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test('next-token scoring maps responses and errors', () async {
      final scores = await backend.scoreNextToken(
        22,
        'Answer:',
        candidates: const [5, 6],
        topK: 3,
        reusePromptPrefix: false,
      );
      expect(scores.candidates.map((t) => t.token), [5, 6]);
      expect(scores.candidates.first.logprob, -3);
      expect(scores.promptTokens, 2);
      final request = harness.received.whereType<ScoreNextTokenRequest>().last;
      expect(request.contextHandle, 22);

      await expectLater(
        backend.scoreNextToken(
          22,
          'range',
          candidates: const [1],
          topK: 0,
          reusePromptPrefix: true,
        ),
        throwsA(
          isA<RangeError>().having(
            (error) => error.toString(),
            'toString',
            'RangeError: bad token',
          ),
        ),
      );
      await expectLater(
        backend.scoreNextToken(
          22,
          'busy',
          candidates: const [1],
          topK: 0,
          reusePromptPrefix: true,
        ),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test('chat template and lora methods map responses and errors', () async {
      expect(
        await backend.applyChatTemplate(1, const <Map<String, dynamic>>[]),
        'templated',
      );
      expect(
        () => backend.applyChatTemplate(
          1,
          const <Map<String, dynamic>>[],
          customTemplate: 'error',
        ),
        throwsException,
      );

      await backend.setLoraAdapter(1, '/tmp/a.lora', 0.5);
      await backend.removeLoraAdapter(1, '/tmp/a.lora');
      await backend.clearLoraAdapters(1);

      expect(
        harness.received.whereType<LoraRequest>().map((request) => request.op),
        containsAll(<String>['set', 'remove', 'clear']),
      );
    });

    test('LoRA errors keep the worker error kind', () async {
      // The worker's error kind must survive the isolate boundary.
      await expectLater(
        backend.setLoraAdapter(1, 'alora.gguf', 1.0),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('aLoRA adapter'),
          ),
        ),
      );
    });

    test('LoRA metadata version skew stays typed across the worker', () async {
      await expectLater(
        backend.setLoraAdapter(1, 'old-runtime.gguf', 1.0),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('llama_adapter_get_alora_n_invocation_tokens'),
          ),
        ),
      );
    });

    test('worker errors keep their kind through every request', () async {
      await expectLater(
        backend.tokenize(1, 'boom'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await expectLater(
        backend.detokenize(1, const <int>[]),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await expectLater(
        backend.applyChatTemplate(
          1,
          const <Map<String, dynamic>>[],
          customTemplate: 'unsupported',
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('a failed adapter load surfaces as a model error', () async {
      await expectLater(
        backend.setLoraAdapter(1, 'missing.gguf', 1.0),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            'Failed to load LoRA at missing.gguf',
          ),
        ),
      );
    });

    test('ordinary LoRA operations still succeed', () async {
      await backend.setLoraAdapter(1, 'ordinary.gguf', 0.8);
      await backend.removeLoraAdapter(1, 'ordinary.gguf');
      await backend.clearLoraAdapters(1);
      expect(
        harness.received.whereType<LoraRequest>().map((r) => r.op),
        containsAll(<String>['set', 'remove', 'clear']),
      );
    });

    test('contextCreate applies ModelParams.loras at their scales', () async {
      final contextHandle = await backend.contextCreate(
        11,
        const ModelParams(
          loras: [
            LoraAdapterConfig(path: 'style.gguf', scale: 0.5),
            LoraAdapterConfig(path: 'domain.gguf'),
          ],
        ),
      );

      expect(contextHandle, 22);
      expect(
        harness.received.whereType<LoraRequest>().map(
          (r) => (r.contextHandle, r.op, r.path, r.scale),
        ),
        [(22, 'set', 'style.gguf', 0.5), (22, 'set', 'domain.gguf', 1.0)],
      );
      expect(harness.received.whereType<ContextFreeRequest>(), isEmpty);
    });

    test(
      'a failing ModelParams.loras adapter frees the context and is named',
      () async {
        await expectLater(
          backend.contextCreate(
            11,
            const ModelParams(
              loras: [
                LoraAdapterConfig(path: 'ordinary.gguf'),
                LoraAdapterConfig(path: 'missing.gguf'),
              ],
            ),
          ),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.toString(),
              'toString',
              allOf(
                contains('ModelParams.loras'),
                contains('missing.gguf'),
                contains('Failed to load LoRA at missing.gguf'),
              ),
            ),
          ),
        );
        expect(
          harness.received.whereType<ContextFreeRequest>().map(
            (r) => r.contextHandle,
          ),
          [22],
        );
      },
    );

    test('an unsupported ModelParams.loras adapter stays typed and frees the '
        'context', () async {
      await expectLater(
        backend.contextCreate(
          11,
          const ModelParams(loras: [LoraAdapterConfig(path: 'alora.gguf')]),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('ModelParams.loras'), contains('aLoRA adapter')),
          ),
        ),
      );
      expect(
        harness.received.whereType<ContextFreeRequest>().map(
          (r) => r.contextHandle,
        ),
        [22],
      );
    });

    test('engine loads apply ModelParams.loras each time and roll back a '
        'failed adapter', () async {
      final engine = LlamaEngine(backend);
      List<(int, String, String?, double?)> loraRequests() => harness.received
          .whereType<LoraRequest>()
          .map((r) => (r.contextHandle, r.op, r.path, r.scale))
          .toList();

      await expectLater(
        engine.loadModel(
          'ok.gguf',
          modelParams: const ModelParams(
            loras: [LoraAdapterConfig(path: 'missing.gguf')],
          ),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.toString(),
            'toString',
            contains('ModelParams.loras adapter missing.gguf'),
          ),
        ),
      );
      expect(engine.isReady, isFalse);
      expect(harness.received.whereType<ContextFreeRequest>(), hasLength(1));
      expect(harness.received.whereType<ModelFreeRequest>(), hasLength(1));

      const withAdapter = ModelParams(
        loras: [LoraAdapterConfig(path: 'ordinary.gguf', scale: 0.25)],
      );
      await engine.loadModel('ok.gguf', modelParams: withAdapter);
      await engine.unloadModel();
      await engine.loadModel('ok.gguf', modelParams: withAdapter);
      expect(loraRequests().skip(1), [
        (22, 'set', 'ordinary.gguf', 0.25),
        (22, 'set', 'ordinary.gguf', 0.25),
      ]);

      await engine.unloadModel();
      await engine.loadModel('ok.gguf');
      expect(loraRequests(), hasLength(3));
      await engine.unloadModel();
    });

    test('modelLoadFromUrl remains unsupported on native backend', () {
      expect(
        () => backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('supportsUrlLoading is false'),
          ),
        ),
      );
      expect(backend.supportsUrlLoading, isFalse);
      expect(backend.isReady, isTrue);
    });
  });

  test(
    'cancel reaches a worker blocked in a native step through the flag',
    () async {
      final events = ReceivePort();
      final eventQueue = StreamIterator<Object?>(events);
      final isolate = await Isolate.spawn(_flagPollingWorker, events.sendPort);
      addTearDown(() {
        isolate.kill(priority: Isolate.immediate);
        events.close();
      });
      expect(await eventQueue.moveNext(), isTrue);
      final backend = NativeLlamaBackend(
        initialSendPort: eventQueue.current as SendPort,
      );
      final pending = backend.synthesizeTextToSpeech(
        22,
        33,
        const BackendTextToSpeechRequest(text: 'Blocked.'),
      );
      expect(await eventQueue.moveNext(), isTrue);
      expect(eventQueue.current, 'in-step');
      backend.cancelTextToSpeech();
      await expectLater(
        pending,
        throwsA(
          isA<LlamaTextToSpeechException>().having(
            (error) => error.message,
            'message',
            'flag observed',
          ),
        ),
      );
    },
  );

  test('reports the llama.cpp runtime', () {
    expect(NativeLlamaBackend().runtime, LlamaRuntime.llamaCpp);
  });

  test('places only images at tool-result markers', () {
    expect(NativeLlamaBackend().toolResultMedia, {LlamaToolResultMedia.image});
  });

  test(
    'generation capabilities are empty before load without starting a worker',
    () async {
      final backend = NativeLlamaBackend();
      addTearDown(backend.dispose);
      final capabilities = await backend.generationCapabilities();
      expect(capabilities.penalty, isFalse);
      expect(capabilities.presencePenalty, isFalse);
      expect(capabilities.minP, isFalse);
      expect(capabilities.streamBatching, isFalse);
      expect(capabilities.thinkingBudget, isFalse);
      expect(capabilities.speculativeDecodingStrategies, isEmpty);
      expect(backend.isReady, isFalse);
    },
  );

  for (final supportsBudget in [false, true]) {
    test(
      'loaded generation capabilities use the worker budget=$supportsBudget snapshot',
      () async {
        final backend = NativeLlamaBackend(
          workerEntrypoint: _generationCapabilitiesWorkerEntry,
        );
        addTearDown(backend.dispose);
        await backend.modelLoad(
          supportsBudget ? '2' : '1',
          const ModelParams(),
        );
        final caps = await backend.generationCapabilities();
        expect(caps.thinkingBudget, supportsBudget);
        expect(caps.penalty, isTrue);
      },
    );
  }

  test(
    'generation capabilities follow worker results and the active model lifecycle',
    () async {
      final backend = NativeLlamaBackend(
        workerEntrypoint: _generationCapabilitiesWorkerEntry,
      );
      addTearDown(backend.dispose);
      expect((await backend.generationCapabilities()).thinkingBudget, isFalse);
      await expectLater(
        backend.modelLoad('error', const ModelParams()),
        throwsA(isA<LlamaModelException>()),
      );
      expect((await backend.generationCapabilities()).penalty, isFalse);
      final first = await backend.modelLoad('1', const ModelParams());
      expect((await backend.generationCapabilities()).thinkingBudget, isFalse);
      expect((await backend.generationCapabilities()).penalty, isTrue);
      await backend.modelFree(99);
      expect((await backend.generationCapabilities()).penalty, isTrue);
      await expectLater(
        backend.modelFree(-1),
        throwsA(isA<LlamaModelException>()),
      );
      expect((await backend.generationCapabilities()).penalty, isTrue);
      final second = await backend.modelLoad('2', const ModelParams());
      expect((await backend.generationCapabilities()).thinkingBudget, isTrue);
      await backend.modelFree(first);
      expect((await backend.generationCapabilities()).thinkingBudget, isTrue);
      await backend.modelFree(second);
      expect((await backend.generationCapabilities()).penalty, isFalse);
      await backend.modelLoad('2', const ModelParams());
      await backend.dispose();
      expect((await backend.generationCapabilities()).thinkingBudget, isFalse);
      expect(
        (await backend.generationCapabilities()).speculativeDecodingStrategies,
        isEmpty,
      );
    },
  );

  test('disposal clears a model load that replies during shutdown', () async {
    final port = ReceivePort();
    final backend = NativeLlamaBackend(initialSendPort: port.sendPort);
    final loadReceived = Completer<void>();
    ModelLoadRequest? loadRequest;
    port.listen((message) {
      if (message is ModelLoadRequest) {
        loadRequest = message;
        loadReceived.complete();
      } else if (message is DisposeRequest) {
        loadRequest!.sendPort.send(HandleResponse(1));
        message.sendPort.send(DoneResponse());
      }
    });
    addTearDown(() async {
      await backend.dispose();
      port.close();
    });
    final load = backend.modelLoad('model', const ModelParams());
    await loadReceived.future;
    await backend.dispose();
    await load;
    expect((await backend.generationCapabilities()).penalty, isFalse);
  });

  test(
    'generation capability probe rejects an unexpected worker response',
    () async {
      final port = ReceivePort();
      final backend = NativeLlamaBackend(initialSendPort: port.sendPort);
      port.listen((message) {
        if (message is ModelLoadRequest) {
          message.sendPort.send(HandleResponse(1));
        } else if (message is WorkerRequest) {
          message.sendPort.send(DoneResponse());
        }
      });
      addTearDown(() async {
        await backend.dispose();
        port.close();
      });
      await backend.modelLoad('model', const ModelParams());
      await expectLater(
        backend.generationCapabilities(),
        throwsA(isA<LlamaStateException>()),
      );
    },
  );

  test('modelFree and contextFree are no-op without worker port', () async {
    final backend = NativeLlamaBackend();

    await backend.modelFree(1);
    await backend.contextFree(1);
    expect(await backend.getContextSize(1), 0);

    await backend.dispose();
    expect(backend.isReady, isFalse);
  });

  test('decisionHeadFree does not start a worker', () async {
    final backend = NativeLlamaBackend();

    await backend.decisionHeadFree(1);
    expect(backend.isReady, isFalse);

    await backend.dispose();
    await backend.decisionHeadFree(1);
    expect(backend.isReady, isFalse);
  });

  test('a disposed backend starts a fresh worker instead of hanging', () async {
    final backend = NativeLlamaBackend(workerEntrypoint: _reusableWorkerEntry);

    try {
      expect(
        await backend
            .modelLoad('first.gguf', const ModelParams())
            .timeout(const Duration(seconds: 2)),
        42,
      );
      await backend.dispose().timeout(const Duration(seconds: 2));
      expect(backend.isReady, isFalse);
      expect(
        await backend
            .modelLoad('second.gguf', const ModelParams())
            .timeout(const Duration(seconds: 2)),
        42,
      );
      expect(backend.isReady, isTrue);
    } finally {
      await backend.dispose().timeout(const Duration(seconds: 2));
    }
  });

  test(
    'dispose waits for synchronous work after the acknowledgement',
    () async {
      final backend = NativeLlamaBackend(
        workerEntrypoint: slowExitingWorkerEntry,
      );
      await backend.modelLoad('model.gguf', const ModelParams());
      final elapsed = Stopwatch()..start();
      await Future.wait([backend.dispose(), backend.dispose()]);
      elapsed.stop();
      expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(200));
      expect(backend.isReady, isFalse);
    },
    skip: Platform.isWindows ? 'uses the POSIX usleep function' : false,
  );

  test('disposal keeps a standalone host alive until worker exit', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'test/fixtures/shutdown/worker_dispose_host.dart',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('DISPOSAL_COMPLETED'));
  }, skip: Platform.isWindows ? 'uses the POSIX usleep function' : false);

  group('worker log forwarding', () {
    final records = <LlamaLogRecord>[];

    setUp(records.clear);

    tearDown(LlamaLogging.configure);

    test('a worker warning reaches the LlamaLogging handler', () async {
      await LlamaLogging.configure(
        level: LlamaLogLevel.warn,
        handler: records.add,
      );
      final backend = NativeLlamaBackend(workerEntrypoint: _loggingWorkerEntry);
      try {
        final name = await backend.getBackendName().timeout(
          const Duration(seconds: 5),
        );
        expect(name, 'logging');
        await _waitForRecords(records, 1);
        expect(records.single.level, LlamaLogLevel.warn);
        expect(records.single.message, 'worker warning');
        expect(records.single.error, 'Bad state: worker detail');
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test('nothing is forwarded at level none', () async {
      await LlamaLogging.configure(
        level: LlamaLogLevel.none,
        handler: records.add,
      );
      final backend = NativeLlamaBackend(workerEntrypoint: _loggingWorkerEntry);
      try {
        await backend.getBackendName().timeout(const Duration(seconds: 5));
        LlamaLogger.instance.setLevel(LlamaLogLevel.debug);
        await backend.getBackendName().timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(records, isEmpty);
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test(
      'LlamaLogging.configure changes what a running worker forwards',
      () async {
        await LlamaLogging.configure(
          level: LlamaLogLevel.none,
          handler: records.add,
        );
        final backend = NativeLlamaBackend(
          workerEntrypoint: _loggingWorkerEntry,
        );
        final engine = LlamaEngine(backend);
        try {
          await backend.getBackendName().timeout(const Duration(seconds: 5));
          await LlamaLogging.configure(
            level: LlamaLogLevel.warn,
            handler: records.add,
          ).timeout(const Duration(seconds: 5));
          await backend.getBackendName().timeout(const Duration(seconds: 5));
          await _waitForRecords(records, 1);
          expect(records.single.message, 'worker warning');
        } finally {
          await engine.dispose().timeout(const Duration(seconds: 2));
        }
      },
    );
  });

  group('worker error types', () {
    test('a missing GGUF file is a LlamaModelException', () async {
      final backend = NativeLlamaBackend(workerEntrypoint: _loggingWorkerEntry);
      try {
        await expectLater(
          backend
              .modelLoad('/nonexistent/model.gguf', const ModelParams())
              .timeout(const Duration(seconds: 5)),
          throwsA(
            isA<LlamaModelException>().having(
              (e) => e.message,
              'message',
              'Model file not found: /nonexistent/model.gguf',
            ),
          ),
        );
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test('invalid ModelParams stay a LlamaArgumentException', () async {
      final backend = NativeLlamaBackend(
        workerEntrypoint: _validatingWorkerEntry,
      );
      try {
        await expectLater(
          backend
              .modelLoad(
                '/models/model.gguf',
                const ModelParams(speculativeRollbackTokenMax: -1),
              )
              .timeout(const Duration(seconds: 5)),
          throwsA(
            isA<LlamaArgumentException>().having(
              (e) => e.message,
              'message',
              contains('speculativeRollbackTokenMax'),
            ),
          ),
        );
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });
  });

  group('worker startup handshake', () {
    test(
      'init failure is typed, diagnostic, retryable, and cleaned up',
      () async {
        final backend = NativeLlamaBackend(
          workerEntrypoint: _failingInitializationWorkerEntry,
        );

        try {
          for (var attempt = 0; attempt < 2; attempt += 1) {
            await expectLater(
              backend
                  .modelLoad('never.gguf', const ModelParams())
                  .timeout(const Duration(seconds: 2)),
              throwsA(
                isA<LlamaBackendInitializationException>()
                    .having(
                      (error) => error.message,
                      'message',
                      contains('synthetic native loader failure'),
                    )
                    .having(
                      (error) => error.message,
                      'startup diagnostics',
                      contains('libllamadart.dylib was not loadable'),
                    )
                    .having(
                      (error) => error.message,
                      'sanitized diagnostics',
                      allOf(
                        isNot(contains('user:pass')),
                        isNot(contains('token=secret')),
                        isNot(contains('\u0000')),
                      ),
                    ),
              ),
              reason: 'attempt ${attempt + 1} must fail instead of hanging',
            );
            expect(backend.isReady, isFalse);
          }
        } finally {
          await backend.dispose().timeout(const Duration(seconds: 2));
        }
      },
    );

    test('concurrent calls share the failing startup handshake', () async {
      final backend = NativeLlamaBackend(
        workerEntrypoint: _delayedFailingInitializationWorkerEntry,
      );

      try {
        final startupFailure = throwsA(
          isA<LlamaBackendInitializationException>().having(
            (error) => error.message,
            'message',
            contains('delayed synthetic initialization failure'),
          ),
        );
        await Future.wait(<Future<void>>[
          expectLater(
            backend
                .modelLoad('first.gguf', const ModelParams())
                .timeout(const Duration(seconds: 2)),
            startupFailure,
          ),
          expectLater(
            backend
                .modelLoad('second.gguf', const ModelParams())
                .timeout(const Duration(seconds: 2)),
            startupFailure,
          ),
        ]);
        expect(backend.isReady, isFalse);
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test('log-level update joins a failing startup handshake', () async {
      final backend = NativeLlamaBackend(
        workerEntrypoint: _delayedFailingInitializationWorkerEntry,
      );

      try {
        final modelLoad = backend.modelLoad('never.gguf', const ModelParams());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final logLevelUpdate = backend.setLogLevel(LlamaLogLevel.debug);

        await Future.wait(<Future<void>>[
          expectLater(
            modelLoad.timeout(const Duration(seconds: 2)),
            throwsA(isA<LlamaBackendInitializationException>()),
          ),
          expectLater(
            logLevelUpdate.timeout(const Duration(seconds: 2)),
            throwsA(isA<LlamaBackendInitializationException>()),
          ),
        ]);
        expect(backend.isReady, isFalse);
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test(
      'concurrent dispose cancels the startup caller and permits restart',
      () async {
        final backend = NativeLlamaBackend(
          workerEntrypoint: _delayedReusableWorkerEntry,
        );

        try {
          final modelLoad = backend.modelLoad(
            'before-dispose.gguf',
            const ModelParams(),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));

          await Future.wait(<Future<void>>[
            expectLater(
              modelLoad.timeout(const Duration(seconds: 2)),
              throwsA(
                isA<LlamaBackendInitializationException>().having(
                  (error) => error.message,
                  'message',
                  contains('disposed during backend initialization'),
                ),
              ),
            ),
            backend.dispose().timeout(const Duration(seconds: 2)),
            backend.dispose().timeout(const Duration(seconds: 2)),
          ]);
          expect(backend.isReady, isFalse);
          expect(
            await backend
                .modelLoad('after-dispose.gguf', const ModelParams())
                .timeout(const Duration(seconds: 2)),
            42,
          );
          expect(backend.isReady, isTrue);
        } finally {
          await backend.dispose().timeout(const Duration(seconds: 2));
        }
      },
    );

    test(
      'worker exit before handshake acknowledgement fails promptly',
      () async {
        final backend = NativeLlamaBackend(
          workerEntrypoint: _exitingBeforeHandshakeReplyWorkerEntry,
        );

        try {
          await expectLater(
            backend
                .modelLoad('never.gguf', const ModelParams())
                .timeout(const Duration(seconds: 2)),
            throwsA(
              isA<LlamaBackendInitializationException>().having(
                (error) => error.message,
                'message',
                contains('before acknowledging'),
              ),
            ),
          );
          expect(backend.isReady, isFalse);
        } finally {
          await backend.dispose().timeout(const Duration(seconds: 2));
        }
      },
    );

    test(
      'uncaught worker error before request port identifies stage',
      () async {
        final backend = NativeLlamaBackend(
          workerEntrypoint: _crashingBeforeRequestPortWorkerEntry,
        );

        try {
          await expectLater(
            backend
                .modelLoad('never.gguf', const ModelParams())
                .timeout(const Duration(seconds: 2)),
            throwsA(
              isA<LlamaBackendInitializationException>()
                  .having(
                    (error) => error.message,
                    'startup stage',
                    contains('before providing its request port'),
                  )
                  .having(
                    (error) => error.message,
                    'message',
                    contains('synthetic pre-port crash'),
                  ),
            ),
          );
          expect(backend.isReady, isFalse);
        } finally {
          await backend.dispose().timeout(const Duration(seconds: 2));
        }
      },
    );

    test('uncaught worker startup error preserves its stack trace', () async {
      final backend = NativeLlamaBackend(
        workerEntrypoint: _crashingDuringHandshakeWorkerEntry,
      );

      try {
        await expectLater(
          backend
              .modelLoad('never.gguf', const ModelParams())
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<LlamaBackendInitializationException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('synthetic handshake crash'),
                )
                .having(
                  (error) => error.details,
                  'stack trace',
                  contains('_crashingDuringHandshakeWorkerEntry'),
                ),
          ),
        );
        expect(backend.isReady, isFalse);
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test('wedged worker initialization times out and is cleaned up', () async {
      final backend = NativeLlamaBackend(
        workerEntrypoint: _wedgedInitializationWorkerEntry,
        workerStartupTimeout: const Duration(milliseconds: 50),
      );

      try {
        await expectLater(
          backend
              .modelLoad('never.gguf', const ModelParams())
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<LlamaBackendInitializationException>()
                .having(
                  (error) => error.message,
                  'timeout',
                  contains('Timed out after 50 ms'),
                )
                .having(
                  (error) => error.message,
                  'diagnostic',
                  contains('native runtime may be unavailable or unresponsive'),
                ),
          ),
        );
        expect(backend.isReady, isFalse);
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test('default startup timeout permits a slow native cold start', () {
      final mirror = reflect(NativeLlamaBackend());
      final owner = mirror.type.owner as LibraryMirror;
      expect(
        mirror
            .getField(MirrorSystem.getSymbol('_workerStartupTimeout', owner))
            .reflectee,
        const Duration(seconds: 30),
        reason: 'physical iOS cold starts exceed the former 5 s default (#462)',
      );
    });

    test('a handshake slower than instant completes within the startup '
        'timeout', () async {
      final backend = NativeLlamaBackend(
        workerEntrypoint: _slowReusableWorkerEntry,
        workerStartupTimeout: const Duration(seconds: 2),
      );

      try {
        final handle = await backend
            .modelLoad('slow.gguf', const ModelParams())
            .timeout(const Duration(seconds: 10));
        expect(handle, 42);
        expect(backend.isReady, isTrue);
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test('unexpected handshake response reports version skew', () async {
      final backend = NativeLlamaBackend(
        workerEntrypoint: _incompatibleHandshakeWorkerEntry,
      );

      try {
        await expectLater(
          backend
              .modelLoad('never.gguf', const ModelParams())
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<LlamaBackendInitializationException>()
                .having(
                  (error) => error.message,
                  'response type',
                  contains('String'),
                )
                .having(
                  (error) => error.message,
                  'compatibility hint',
                  contains('may be incompatible'),
                ),
          ),
        );
        expect(backend.isReady, isFalse);
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });
  });
}

void _delayedTextToSpeechRejectingWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((message) async {
    switch (message) {
      case WorkerHandshake():
        await Future<void>.delayed(const Duration(milliseconds: 50));
        message.sendPort.send(DoneResponse());
      case TextToSpeechSynthesizeRequest():
        message.sendPort.send(
          ErrorResponse('rejected', kind: WorkerErrorKind.textToSpeech),
        );
      case DisposeRequest():
        message.sendPort.send(null);
        receivePort.close();
        Isolate.exit();
    }
  });
}

void _failingInitializationWorkerEntry(SendPort initialSendPort) {
  runLlamaWorkerForTesting(
    initialSendPort,
    _FailingInitializationLlamaCppService(),
  );
}

void _loggingWorkerEntry(SendPort initialSendPort) {
  runLlamaWorkerForTesting(initialSendPort, _LoggingLlamaCppService());
}

Future<void> _waitForRecords(List<LlamaLogRecord> records, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (records.length < count && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void _validatingWorkerEntry(SendPort initialSendPort) {
  runLlamaWorkerForTesting(initialSendPort, _ValidatingLlamaCppService());
}

class _ValidatingLlamaCppService extends _LoggingLlamaCppService {
  @override
  int loadModel(String modelPath, ModelParams modelParams) {
    modelParams.validate();
    return 1;
  }
}

class _LoggingLlamaCppService extends LlamaCppService {
  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  String getActiveBackendName() {
    LlamaLogger.instance.warn('worker warning', StateError('worker detail'));
    return 'logging';
  }

  @override
  void dispose() {}
}

void _reusableWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    switch (message) {
      case WorkerHandshake():
        message.sendPort.send(DoneResponse());
      case ModelLoadRequest():
        message.sendPort.send(HandleResponse(42));
      case DisposeRequest():
        message.sendPort.send(null);
        receivePort.close();
        Isolate.exit();
    }
  });
}

void _delayedFailingInitializationWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((message) async {
    if (message is WorkerHandshake) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      message.sendPort.send(
        ErrorResponse(
          'delayed synthetic initialization failure',
          kind: WorkerErrorKind.backendInitialization,
        ),
      );
      receivePort.close();
    }
  });
}

void _delayedReusableWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((message) async {
    switch (message) {
      case WorkerHandshake():
        await Future<void>.delayed(const Duration(milliseconds: 50));
        message.sendPort.send(DoneResponse());
      case ModelLoadRequest():
        message.sendPort.send(HandleResponse(42));
      case DisposeRequest():
        message.sendPort.send(null);
        receivePort.close();
        Isolate.exit();
    }
  });
}

void _slowReusableWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((message) async {
    switch (message) {
      case WorkerHandshake():
        await Future<void>.delayed(const Duration(milliseconds: 200));
        message.sendPort.send(DoneResponse());
      case ModelLoadRequest():
        message.sendPort.send(HandleResponse(42));
      case DisposeRequest():
        message.sendPort.send(null);
        receivePort.close();
        Isolate.exit();
    }
  });
}

void _exitingBeforeHandshakeReplyWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    if (message is WorkerHandshake) {
      receivePort.close();
      Isolate.exit();
    }
  });
}

void _crashingBeforeRequestPortWorkerEntry(SendPort initialSendPort) {
  throw StateError('synthetic pre-port crash');
}

void _crashingDuringHandshakeWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    if (message is WorkerHandshake) {
      throw StateError('synthetic handshake crash');
    }
  });
}

void _wedgedInitializationWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((_) {
    // Keep the worker alive without acknowledging its startup handshake.
  });
}

void _incompatibleHandshakeWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    if (message is WorkerHandshake) {
      message.sendPort.send('legacy-ready');
      receivePort.close();
    }
  });
}

class _FailingInitializationLlamaCppService extends LlamaCppService {
  @override
  void initializeBackend() {
    throw ArgumentError('synthetic native loader failure');
  }

  @override
  List<String> getStartupDiagnostics() {
    return const <String>[
      'libllamadart.dylib was not loadable',
      'failed at https://user:pass@example.com/lib.dylib?token=secret\u0000next',
    ];
  }

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  void dispose() {}
}

class _TrackingNativeLlamaBackend extends NativeLlamaBackend {
  _TrackingNativeLlamaBackend({super.initialSendPort});

  bool cancelGenerationCalled = false;

  @override
  void cancelGeneration() {
    cancelGenerationCalled = true;
    super.cancelGeneration();
  }
}

class _FakeWorkerHarness {
  final ReceivePort _port = ReceivePort();
  final List<Object> received = <Object>[];
  bool holdTextToSpeech = false;
  bool holdDispose = false;
  DisposeRequest? _heldDispose;
  Completer<void> textToSpeechStarted = Completer<void>();
  TextToSpeechSynthesizeRequest? _heldTextToSpeech;
  int? cancelFlagAtRequest;
  bool holdNextDispose = false;
  final Completer<void> disposeReceived = Completer<void>();

  _FakeWorkerHarness() {
    _port.listen((message) {
      if (message is! Object) {
        return;
      }
      received.add(message);

      switch (message) {
        case LogLevelRequest():
          message.sendPort.send(DoneResponse());
        case ModelLoadRequest():
          if (message.modelPath.startsWith('error')) {
            message.sendPort.send(ErrorResponse('model load failed'));
          } else {
            message.sendPort.send(HandleResponse(11));
          }
        case ContextCreateRequest():
          if (message.modelHandle < 0) {
            message.sendPort.send(ErrorResponse('context create failed'));
          } else {
            message.sendPort.send(HandleResponse(22));
          }
        case ModelFreeRequest():
          if (message.modelHandle < 0) {
            message.sendPort.send(ErrorResponse('model free failed'));
          } else {
            message.sendPort.send(DoneResponse());
          }
        case ContextFreeRequest():
          if (message.contextHandle < 0) {
            message.sendPort.send(ErrorResponse('context free failed'));
          } else {
            message.sendPort.send(DoneResponse());
          }
        case TokenizeRequest():
          if (message.text == 'boom') {
            message.sendPort.send(
              ErrorResponse(
                'tokenizer unavailable',
                kind: WorkerErrorKind.unsupported,
              ),
            );
          } else {
            message.sendPort.send(TokenizeResponse(<int>[1, 2, 3]));
          }
        case DetokenizeRequest():
          if (message.tokens.isEmpty) {
            message.sendPort.send(
              ErrorResponse(
                'detokenizer unavailable',
                kind: WorkerErrorKind.unsupported,
              ),
            );
          } else {
            message.sendPort.send(DetokenizeResponse('decoded'));
          }
        case MetadataRequest():
          message.sendPort.send(MetadataResponse(<String, String>{'a': 'b'}));
        case EmbedRequest():
          if (message.text == 'boom') {
            message.sendPort.send(ErrorResponse('embed failed'));
          } else {
            message.sendPort.send(EmbedResponse(<double>[0.1, 0.2]));
          }
        case EmbedBatchRequest():
          if (message.texts.contains('boom')) {
            message.sendPort.send(ErrorResponse('embed batch failed'));
          } else {
            message.sendPort.send(
              EmbedBatchResponse(
                message.texts
                    .map((text) => <double>[text.length.toDouble(), 10.0])
                    .toList(growable: false),
              ),
            );
          }
        case GenerateRequest():
          if (message.prompt == 'boom') {
            message.sendPort.send(
              ErrorResponse('Exception: generation failed'),
            );
          } else if (message.prompt == 'unsupported') {
            message.sendPort.send(
              ErrorResponse(
                'missing reasoning-budget wrapper',
                kind: WorkerErrorKind.unsupported,
              ),
            );
          } else if (message.prompt == 'inference') {
            message.sendPort.send(
              ErrorResponse(
                'grammar sampler failed',
                kind: WorkerErrorKind.inference,
              ),
            );
          } else if (message.prompt == 'pending') {
            // Hold open until the client cancels the stream.
          } else {
            message.sendPort.send(TokenResponse(<int>[65]));
            message.sendPort.send(TokenResponse(<int>[66]));
            message.sendPort.send(DoneResponse());
          }
        case BackendInfoRequest():
          message.sendPort.send(BackendInfoResponse('CPU'));
        case AvailableBackendsRequest():
          message.sendPort.send(BackendInfoResponse('CPU, METAL'));
        case ResolvedGpuLayersRequest():
          message.sendPort.send(ResolvedGpuLayersResponse(12));
        case GpuSupportRequest():
          message.sendPort.send(GpuSupportResponse(true));
        case SystemInfoRequest():
          message.sendPort.send(SystemInfoResponse(100, 40));
        case PerformanceContextRequest():
          message.sendPort.send(
            PerformanceContextResponse(
              loadMs: 1,
              promptEvalMs: 2,
              evalMs: 3,
              sampleMs: 4,
              decodeMs: 5,
              promptEvalTokens: 6,
              evalTokens: 7,
              sampleCount: 8,
              reusedGraphs: 9,
              speculativeDraftTokens: 0,
              speculativeAcceptedDraftTokens: 0,
              speculativeDraftAttempts: 10,
              speculativeVerifyTokens: 11,
              speculativeReplayTokens: 12,
              speculativeDraftMs: 0,
              speculativeVerifyMs: 13,
            ),
          );
        case MultimodalContextCreateRequest():
          if (message.modelHandle < 0) {
            message.sendPort.send(ErrorResponse('mm create failed'));
          } else {
            message.sendPort.send(HandleResponse(33));
          }
        case MultimodalContextFreeRequest():
          if (message.mmContextHandle < 0) {
            message.sendPort.send(ErrorResponse('mm free failed'));
          } else {
            message.sendPort.send(DoneResponse());
          }
        case SupportsAudioRequest():
          message.sendPort.send(true);
        case SupportsVisionRequest():
          message.sendPort.send(false);
        case SupportsVideoRequest():
          message.sendPort.send(false);
        case TextToSpeechModelSupportRequest():
          message.sendPort.send(switch (message.model) {
            BackendTextToSpeechModel.qwen3Tts =>
              TextToSpeechModelSupportResponse(null),
            BackendTextToSpeechModel.pocketTts => ErrorResponse('probe failed'),
            _ => TextToSpeechModelSupportResponse('needs v0.9.0'),
          });
        case TextToSpeechCapabilitiesRequest():
          message.sendPort.send(
            TextToSpeechCapabilitiesResponse(
              const BackendTextToSpeechCapabilities(
                isSupported: true,
                model: BackendTextToSpeechModel.qwen3Tts,
                sampleRateHz: 24000,
                channelCount: 1,
                supportsCancellation: true,
              ),
            ),
          );
        case TextToSpeechSynthesizeRequest():
          cancelFlagAtRequest = Pointer<Int8>.fromAddress(
            message.cancelFlagAddress,
          ).value;
          if (!textToSpeechStarted.isCompleted) {
            textToSpeechStarted.complete();
          }
          if (message.request.text == 'audio-format-error') {
            message.sendPort.send(
              ErrorResponse(
                'speaker audio is invalid',
                kind: WorkerErrorKind.audioFormat,
              ),
            );
          } else if (message.request.text == 'tts-error') {
            message.sendPort.send(
              ErrorResponse(
                'synthesis failed',
                kind: WorkerErrorKind.textToSpeech,
              ),
            );
          } else if (holdTextToSpeech) {
            _heldTextToSpeech = message;
          } else {
            _sendTextToSpeechResult(message);
          }
        case TextToSpeechCancelRequest():
          break;
        case ScoreNextTokenRequest():
          if (message.prompt == 'range') {
            message.sendPort.send(
              ErrorResponse(
                'RangeError: bad token',
                kind: WorkerErrorKind.range,
              ),
            );
          } else if (message.prompt == 'busy') {
            message.sendPort.send(
              ErrorResponse('generation active', kind: WorkerErrorKind.state),
            );
          } else {
            message.sendPort.send(
              ScoreNextTokenResponse(
                LlamaNextTokenScores(
                  candidates: [
                    for (final token in message.candidates)
                      LlamaTokenLogprob(
                        token: token,
                        bytes: const [66],
                        logprob: -message.topK.toDouble(),
                      ),
                  ],
                  top: const [],
                  promptTokens: message.reusePromptPrefix ? 1 : 2,
                ),
              ),
            );
          }
        case DecisionCapabilitiesRequest():
          if (message.modelHandle < 0) {
            message.sendPort.send(
              ErrorResponse('no model', kind: WorkerErrorKind.state),
            );
          } else if (message.modelHandle == 12) {
            message.sendPort.send(
              DecisionCapabilitiesResponse(
                const BackendDecisionCapabilities(
                  isSupported: false,
                  unsupportedReason: 'not modern-bert',
                ),
              ),
            );
          } else {
            message.sendPort.send(
              DecisionCapabilitiesResponse(
                const BackendDecisionCapabilities(isSupported: true),
              ),
            );
          }
        case DecisionHeadLoadRequest():
          if (message.headPath == 'bad.safetensors') {
            message.sendPort.send(
              ErrorResponse(
                'type_emb.weight has shape [3, 768], expected [3, 1024]',
                kind: WorkerErrorKind.model,
              ),
            );
          } else if (message.headPath == 'unsupported.safetensors') {
            message.sendPort.send(
              ErrorResponse(
                'not a ModernBERT encoder',
                kind: WorkerErrorKind.unsupported,
              ),
            );
          } else {
            message.sendPort.send(
              DecisionHeadLoadResponse(
                const BackendDecisionHeadInfo(
                  handle: 44,
                  hiddenSize: 4,
                  clsToken: 1,
                  sepToken: 2,
                  maskToken: 3,
                  maskText: '[MASK]',
                  configJson: '{}',
                  deviceName: 'Metal',
                ),
              ),
            );
          }
        case DecisionRunRequest():
          if (message.headHandle < 0) {
            message.sendPort.send(
              ErrorResponse('head not loaded', kind: WorkerErrorKind.state),
            );
          } else if (message.headHandle == 45) {
            message.sendPort.send(DoneResponse());
          } else if (message.sequences.any((s) => s.tokens.isEmpty)) {
            message.sendPort.send(
              ErrorResponse('empty sequence', kind: WorkerErrorKind.inference),
            );
          } else {
            message.sendPort.send(
              DecisionRunResponse([
                for (final sequence in message.sequences)
                  BackendDecisionOutput(
                    logits: Float32List.fromList([
                      for (final marker in sequence.markers) marker.toDouble(),
                    ]),
                    actLogits: Float32List.fromList([0.5, -0.5]),
                  ),
              ]),
            );
          }
        case DecisionHeadFreeRequest():
          if (message.headHandle < 0) {
            message.sendPort.send(
              ErrorResponse('free failed', kind: WorkerErrorKind.state),
            );
          } else {
            message.sendPort.send(DoneResponse());
          }
        case GetContextSizeRequest():
          message.sendPort.send(GetContextSizeResponse(2048));
        case ChatTemplateRequest():
          if (message.customTemplate == 'error') {
            message.sendPort.send(ErrorResponse('chat template failed'));
          } else if (message.customTemplate == 'unsupported') {
            message.sendPort.send(
              ErrorResponse(
                'multimodal chat-template content is unavailable',
                kind: WorkerErrorKind.unsupported,
              ),
            );
          } else {
            message.sendPort.send(ChatTemplateResponse('templated'));
          }
        case LoraRequest():
          if (message.path == 'alora.gguf') {
            message.sendPort.send(
              ErrorResponse(
                'The adapter at alora.gguf is an aLoRA adapter',
                kind: WorkerErrorKind.unsupported,
              ),
            );
          } else if (message.path == 'old-runtime.gguf') {
            message.sendPort.send(
              ErrorResponse(
                'Cannot safely load the LoRA adapter because the native '
                'runtime is missing '
                'llama_adapter_get_alora_n_invocation_tokens',
                kind: WorkerErrorKind.unsupported,
              ),
            );
          } else if (message.path == 'missing.gguf') {
            message.sendPort.send(
              ErrorResponse(
                'Failed to load LoRA at missing.gguf',
                kind: WorkerErrorKind.model,
              ),
            );
          } else {
            message.sendPort.send(DoneResponse());
          }
        case DisposeRequest():
          if (holdNextDispose) {
            holdNextDispose = false;
            _heldDispose = message;
            disposeReceived.complete();
          } else if (holdDispose) {
            _heldDispose = message;
          } else {
            message.sendPort.send(DoneResponse());
          }
        case WorkerHandshake():
        // Not expected in these tests.
      }
    });
  }

  SendPort get sendPort => _port.sendPort;

  void acknowledgeHeldDispose() {
    _heldDispose?.sendPort.send(DoneResponse());
    _heldDispose = null;
  }

  void releaseDispose() {
    holdDispose = false;
    _heldDispose?.sendPort.send(DoneResponse());
    _heldDispose = null;
  }

  void finishHeldTextToSpeech() {
    final request = _heldTextToSpeech;
    if (request == null) {
      return;
    }
    _heldTextToSpeech = null;
    _sendTextToSpeechResult(request);
  }

  void _sendTextToSpeechResult(TextToSpeechSynthesizeRequest request) {
    request.sendPort.send(
      TextToSpeechProgressResponse(
        const BackendTextToSpeechProgress(
          phase: BackendTextToSpeechPhase.generating,
          promptTokensRemaining: 0,
          framesGenerated: 2,
          truncated: false,
        ),
      ),
    );
    request.sendPort.send(
      TextToSpeechResultResponse(
        samples: Float32List.fromList(<double>[0.25, -0.25]),
        sampleRateHz: 24000,
        channelCount: 1,
        framesGenerated: 2,
        truncated: false,
      ),
    );
  }

  void dispose() {
    _port.close();
  }
}

void _flagPollingWorker(SendPort events) {
  final requests = ReceivePort();
  events.send(requests.sendPort);
  requests.listen((message) {
    if (message is! TextToSpeechSynthesizeRequest) {
      return;
    }
    final flag = Pointer<Int8>.fromAddress(message.cancelFlagAddress);
    events.send('in-step');
    final watch = Stopwatch()..start();
    while (flag.value == 0 && watch.elapsed < const Duration(seconds: 10)) {
      sleep(const Duration(milliseconds: 1));
    }
    message.sendPort.send(
      ErrorResponse(
        flag.value == 0 ? 'flag never observed' : 'flag observed',
        kind: WorkerErrorKind.textToSpeech,
      ),
    );
  });
}

final class _RecordingAllocator implements Allocator {
  final List<int> allocated = <int>[];
  final List<int> freed = <int>[];

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final pointer = malloc.allocate<Uint8>(byteCount, alignment: alignment);
    pointer.asTypedList(byteCount).fillRange(0, byteCount, 0x5a);
    allocated.add(pointer.address);
    return pointer.cast<T>();
  }

  @override
  void free(Pointer<NativeType> pointer) => freed.add(pointer.address);

  void release() {
    for (final address in allocated) {
      malloc.free(Pointer<Uint8>.fromAddress(address));
    }
  }
}

/// A cancel token that, like one built on a port, cannot cross an isolate.
class _PortCancelToken extends ModelDownloadCancelToken {
  _PortCancelToken(this.port);

  final RawReceivePort port;
}

void _generationCapabilitiesWorkerEntry(SendPort initialSendPort) {
  runLlamaWorkerForTesting(initialSendPort, _GenerationCapabilitiesService());
}

class _GenerationCapabilitiesService extends _LoggingLlamaCppService {
  @override
  int loadModel(String modelPath, ModelParams modelParams) {
    if (modelPath == 'error') throw LlamaModelException('load failed');
    return int.parse(modelPath);
  }

  @override
  void freeModel(int modelHandle) {
    if (modelHandle < 0) throw LlamaModelException('free failed');
  }

  @override
  BackendGenerationCapabilities generationCapabilities(int modelHandle) =>
      BackendGenerationCapabilities(
        penalty: true,
        presencePenalty: true,
        minP: true,
        thinkingBudget: modelHandle == 2,
      );
}

void _counterWorkerEntry(SendPort initialSendPort) {
  final receive = ReceivePort();
  initialSendPort.send(receive.sendPort);
  receive.listen((message) {
    switch (message) {
      case WorkerHandshake():
        message.sendPort.send(DoneResponse());
      case PerformanceContextRequest():
        message.sendPort.send(
          PerformanceContextResponse(
            loadMs: 1,
            promptEvalMs: 1,
            evalMs: 1,
            sampleMs: 0,
            promptEvalTokens: 1,
            evalTokens: 7,
            sampleCount: 7,
            reusedGraphs: 0,
          ),
        );
      case DisposeRequest():
        message.sendPort.send(DoneResponse());
        receive.close();
        Isolate.exit();
    }
  });
}
