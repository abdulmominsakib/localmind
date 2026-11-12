@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/inference/next_token_scores.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:test/test.dart';

void main() {
  group('llamaWorkerEntry isolate routing', () {
    test('reports and cleans up backend initialization failure', () async {
      final service = _FailingInitializationLlamaCppService();
      final receivePort = ReceivePort();
      runLlamaWorkerForTesting(
        receivePort.sendPort,
        service,
        exitOnDispose: false,
      );
      final sendPort = await receivePort.first as SendPort;
      receivePort.close();
      final handshakePort = ReceivePort();

      sendPort.send(
        WorkerHandshake(LlamaLogLevel.warn, handshakePort.sendPort),
      );
      final response = await handshakePort.first;
      handshakePort.close();

      expect(response, isA<ErrorResponse>());
      final error = response as ErrorResponse;
      expect(error.kind, WorkerErrorKind.backendInitialization);
      expect(error.message, contains('synthetic initialization failure'));
      expect(
        error.message,
        contains('_FailingInitializationLlamaCppService.initializeBackend'),
      );
      expect(error.message, contains('libllamadart.so could not be opened'));
      expect(
        error.message,
        contains('\nstartupDiagnostics=[libllamadart.so could not be opened]'),
      );
      expect(error.message, isNot(contains(', startupDiagnostics=')));
      expect(service.disposeCalls, 1);
    });

    test('handles control and info requests', () async {
      final worker = await _spawnWorker();

      try {
        final logResponse = await _sendRequest(
          worker.sendPort,
          (sendPort) => LogLevelRequest(LlamaLogLevel.info, sendPort),
        );
        expect(logResponse, isA<DoneResponse>());

        final backendInfo = await _sendRequest(
          worker.sendPort,
          BackendInfoRequest.new,
        );
        expect(backendInfo, isA<BackendInfoResponse>());

        final available = await _sendRequest(
          worker.sendPort,
          AvailableBackendsRequest.new,
        );
        expect(available, isA<BackendInfoResponse>());

        final resolved = await _sendRequest(
          worker.sendPort,
          ResolvedGpuLayersRequest.new,
        );
        expect(resolved, isA<ResolvedGpuLayersResponse>());

        final gpuSupport = await _sendRequest(
          worker.sendPort,
          GpuSupportRequest.new,
        );
        expect(gpuSupport, isA<GpuSupportResponse>());

        final systemInfo = await _sendRequest(
          worker.sendPort,
          SystemInfoRequest.new,
        );
        expect(systemInfo, isA<SystemInfoResponse>());
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('returns error responses for invalid handles', () async {
      final worker = await _spawnWorker();

      try {
        final contextCreate = await _sendRequest(
          worker.sendPort,
          (sendPort) => ContextCreateRequest(-1, const ModelParams(), sendPort),
        );
        expect(contextCreate, isA<ErrorResponse>());

        final generate = await _sendRequest(
          worker.sendPort,
          (sendPort) => GenerateRequest(
            -1,
            'hello',
            const GenerationParams(),
            0,
            sendPort,
          ),
        );
        expect(generate, isA<ErrorResponse>());

        final embed = await _sendRequest(
          worker.sendPort,
          (sendPort) => EmbedRequest(-1, 'hello', true, sendPort),
        );
        expect(embed, isA<ErrorResponse>());

        final embedBatch = await _sendRequest(
          worker.sendPort,
          (sendPort) =>
              EmbedBatchRequest(-1, const <String>['a'], true, sendPort),
        );
        expect(embedBatch, isA<ErrorResponse>());

        final chatTemplate = await _sendRequest(
          worker.sendPort,
          (sendPort) => ChatTemplateRequest(
            1,
            const <Map<String, dynamic>>[],
            null,
            true,
            sendPort,
          ),
        );
        expect(chatTemplate, isA<ErrorResponse>());
        expect(
          (chatTemplate as ErrorResponse).message,
          contains('Invalid model handle'),
        );
        expect(chatTemplate.message, contains('1'));
        expect(chatTemplate.message, isNot(contains('not implemented')));

        final tokenize = await _sendRequest(
          worker.sendPort,
          (sendPort) => TokenizeRequest(999, 'text', true, sendPort),
        );
        expect(tokenize, isA<TokenizeResponse>());

        final detokenize = await _sendRequest(
          worker.sendPort,
          (sendPort) => DetokenizeRequest(999, const <int>[1], false, sendPort),
        );
        expect(detokenize, isA<DetokenizeResponse>());
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('answers decision requests for unknown handles', () async {
      final worker = await _spawnWorker();

      try {
        final capabilities = await _sendRequest(
          worker.sendPort,
          (sendPort) => DecisionCapabilitiesRequest(-1, sendPort),
        );
        expect(capabilities, isA<DecisionCapabilitiesResponse>());
        final snapshot =
            (capabilities as DecisionCapabilitiesResponse).capabilities;
        expect(snapshot.isSupported, isFalse);
        expect(snapshot.unsupportedReason, contains('handle -1'));

        final load = await _sendRequest(
          worker.sendPort,
          (sendPort) =>
              DecisionHeadLoadRequest(-1, 'head.safetensors', null, sendPort),
        );
        expect(load, isA<ErrorResponse>());
        expect((load as ErrorResponse).kind, WorkerErrorKind.state);

        final run = await _sendRequest(
          worker.sendPort,
          (sendPort) => DecisionRunRequest(-1, const [], sendPort),
        );
        expect(run, isA<ErrorResponse>());
        expect((run as ErrorResponse).kind, WorkerErrorKind.state);

        final free = await _sendRequest(
          worker.sendPort,
          (sendPort) => DecisionHeadFreeRequest(-1, sendPort),
        );
        expect(free, isA<DoneResponse>());
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('routes decision requests and their typed lists', () async {
      final service = _DecisionService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final capabilities = await _sendRequest(
          worker.sendPort,
          (sendPort) => DecisionCapabilitiesRequest(5, sendPort),
        );
        expect(
          (capabilities as DecisionCapabilitiesResponse)
              .capabilities
              .isSupported,
          isTrue,
        );
        expect(service.capabilityModels, [5]);

        final load = await _sendRequest(
          worker.sendPort,
          (sendPort) => DecisionHeadLoadRequest(
            5,
            'head.safetensors',
            'config.json',
            sendPort,
          ),
        );
        final head = (load as DecisionHeadLoadResponse).head;
        expect(head.handle, 9);
        expect(head.maskText, '[MASK]');
        expect(service.loads, [(5, 'head.safetensors', 'config.json')]);

        final run = await _sendRequest(
          worker.sendPort,
          (sendPort) => DecisionRunRequest(9, [
            for (final (markers, type) in [
              ([1, 2], DecisionQuestionType.noul),
              ([0], DecisionQuestionType.choice),
              ([2, 0, 1], DecisionQuestionType.score),
            ])
              BackendDecisionSequence(
                tokens: Int32List.fromList([1, 2, 3]),
                markers: Int32List.fromList(markers),
                questionType: type,
              ),
          ], sendPort),
        );
        final outputs = (run as DecisionRunResponse).outputs;
        expect(outputs, hasLength(3));
        expect(outputs.first.logits, isA<Float32List>());
        expect(
          [for (final output in outputs) output.logits],
          [
            [1.0, 2.0],
            [0.0],
            [2.0, 0.0, 1.0],
          ],
        );
        expect(outputs.first.actLogits, [2.0, -2.0]);
        final received = service.runs.single;
        expect(received.$1, 9);
        expect(received.$2.first.tokens, isA<Int32List>());
        expect(received.$2.first.tokens, [1, 2, 3]);
        expect(
          [for (final sequence in received.$2) sequence.questionType],
          [
            DecisionQuestionType.noul,
            DecisionQuestionType.choice,
            DecisionQuestionType.score,
          ],
        );

        final free = await _sendRequest(
          worker.sendPort,
          (sendPort) => DecisionHeadFreeRequest(9, sendPort),
        );
        expect(free, isA<DoneResponse>());
        expect(service.freedHeads, [9]);
      } finally {
        await _disposeWorker(worker);
      }
    });

    test(
      'preserves typed embedding overflow fields through the worker',
      () async {
        final worker = await _startWorkerInCurrentIsolate(
          _DecisionService(
            error: LlamaEmbeddingInputTooLongException(
              'input too long',
              maxInputTokens: 64,
              actualTokens: 65,
            ),
          ),
        );
        try {
          final response =
              await _sendRequest(
                    worker.sendPort,
                    (sendPort) => DecisionRunRequest(1, const [], sendPort),
                  )
                  as ErrorResponse;
          expect(response.kind, WorkerErrorKind.embeddingInputTooLong);
          expect(response.maxInputTokens, 64);
          expect(response.actualTokens, 65);
        } finally {
          await _disposeWorker(worker);
        }
      },
    );

    test('preserves decision error categories', () async {
      final cases = <(Object, WorkerErrorKind)>[
        (LlamaModelException('bad head tensor'), WorkerErrorKind.model),
        (LlamaArgumentException('bad head path'), WorkerErrorKind.argument),
        (LlamaStateException('head 9 is not loaded'), WorkerErrorKind.state),
        (
          LlamaInferenceException('sequence 0 has no markers'),
          WorkerErrorKind.inference,
        ),
        (
          LlamaUnsupportedException('not a ModernBERT encoder'),
          WorkerErrorKind.unsupported,
        ),
        (
          LlamaContextException('encoder context failed'),
          WorkerErrorKind.context,
        ),
      ];
      final requests = <WorkerRequest Function(SendPort)>[
        (sendPort) => DecisionHeadLoadRequest(1, 'h', null, sendPort),
        (sendPort) => DecisionRunRequest(1, const [], sendPort),
        (sendPort) => DecisionHeadFreeRequest(1, sendPort),
        (sendPort) => DecisionCapabilitiesRequest(1, sendPort),
      ];

      for (final (exception, expectedKind) in cases) {
        final worker = await _startWorkerInCurrentIsolate(
          _DecisionService(error: exception),
        );
        try {
          for (final request in requests) {
            final response = await _sendRequest(worker.sendPort, request);
            expect(response, isA<ErrorResponse>());
            expect((response as ErrorResponse).kind, expectedKind);
            expect(response.message, isNot(contains('LlamaException:')));
          }
        } finally {
          await _disposeWorker(worker);
        }
      }
    });

    test('routes next-token scoring requests', () async {
      final service = _ScoringService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final response = await _sendRequest(
          worker.sendPort,
          (sendPort) =>
              ScoreNextTokenRequest(3, 'Answer:', [4, 7], 2, false, sendPort),
        );

        final scores = (response as ScoreNextTokenResponse).scores;
        expect(scores.candidates.map((t) => t.token), [4, 7]);
        expect(scores.candidates.first.text, 'A');
        expect(scores.promptTokens, 5);
        final (handle, prompt, candidates, topK, reuse) = service.calls.single;
        expect((handle, prompt, topK, reuse), (3, 'Answer:', 2, false));
        expect(candidates, [4, 7]);
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('preserves next-token scoring error categories', () async {
      final cases = <(Object, WorkerErrorKind)>[
        (RangeError.range(9, 0, 4, 'candidates'), WorkerErrorKind.range),
        (LlamaStateException('generation active'), WorkerErrorKind.state),
        (LlamaUnsupportedException('no decoder'), WorkerErrorKind.unsupported),
      ];
      for (final (exception, expectedKind) in cases) {
        final worker = await _startWorkerInCurrentIsolate(
          _ScoringService(error: exception),
        );
        try {
          final response = await _sendRequest(
            worker.sendPort,
            (sendPort) => ScoreNextTokenRequest(1, 'x', [9], 0, true, sendPort),
          );
          expect((response as ErrorResponse).kind, expectedKind);
        } finally {
          await _disposeWorker(worker);
        }
      }
    });

    test('keeps range errors of other requests generic', () async {
      final worker = await _startWorkerInCurrentIsolate(
        _ScoringService(error: RangeError.range(9, 0, 4, 'budget')),
      );
      try {
        final response = await _sendRequest(
          worker.sendPort,
          (sendPort) => TokenizeRequest(1, 'x', true, sendPort),
        );
        expect((response as ErrorResponse).kind, WorkerErrorKind.generic);
      } finally {
        await _disposeWorker(worker);
      }
    });

    test(
      'preserves unsupported generation errors across worker messages',
      () async {
        final worker = await _startWorkerInCurrentIsolate(
          _UnsupportedGenerationLlamaCppService(),
        );

        try {
          final response = await _sendRequest(
            worker.sendPort,
            (sendPort) => GenerateRequest(
              1,
              'hello',
              const GenerationParams(),
              0,
              sendPort,
            ),
          );

          expect(response, isA<ErrorResponse>());
          final error = response as ErrorResponse;
          expect(error.kind, WorkerErrorKind.unsupported);
          expect(error.message, contains('reasoning-budget wrapper'));
        } finally {
          await _disposeWorker(worker);
        }
      },
    );

    test(
      'DartLogLevelRequest leaves the logger alone without a log port',
      () async {
        final worker = await _startWorkerInCurrentIsolate(
          _UnsupportedGenerationLlamaCppService(),
        );
        try {
          final response = await _sendRequest(
            worker.sendPort,
            (sendPort) => DartLogLevelRequest(LlamaLogLevel.debug, sendPort),
          );
          expect(response, isA<DoneResponse>());
          expect(LlamaLogger.instance.level, LlamaLogLevel.none);
        } finally {
          await _disposeWorker(worker);
        }
      },
    );

    test(
      'preserves inference generation errors across worker messages',
      () async {
        final worker = await _startWorkerInCurrentIsolate(
          _InferenceGenerationLlamaCppService(),
        );

        try {
          final response = await _sendRequest(
            worker.sendPort,
            (sendPort) => GenerateRequest(
              1,
              'hello',
              const GenerationParams(),
              0,
              sendPort,
            ),
          );

          expect(response, isA<ErrorResponse>());
          final error = response as ErrorResponse;
          expect(error.kind, WorkerErrorKind.inference);
          expect(error.message, contains('grammar sampler failed'));
          expect(error.message, contains('native grammar stack exhausted'));
          expect(error.message, isNot(contains('LlamaException:')));
        } finally {
          await _disposeWorker(worker);
        }
      },
    );

    for (final limit in <BackendGenerationLimit?>[
      null,
      ...BackendGenerationLimit.values,
    ]) {
      test(
        'sends the generation limit $limit with the final response',
        () async {
          final worker = await _startWorkerInCurrentIsolate(
            _LimitedGenerationLlamaCppService(limit),
          );
          final responsePort = ReceivePort();

          try {
            final responses = StreamIterator<Object?>(responsePort);
            worker.sendPort.send(
              GenerateRequest(
                1,
                'hello',
                const GenerationParams(streamBatchTokenThreshold: 1),
                0,
                responsePort.sendPort,
              ),
            );

            expect(await responses.moveNext(), isTrue);
            expect((responses.current as TokenResponse).bytes, <int>[104, 105]);
            expect(await responses.moveNext(), isTrue);
            final done = responses.current as DoneResponse;
            expect(done.generationLimit, limit);
            await responses.cancel();
          } finally {
            responsePort.close();
            await _disposeWorker(worker);
          }
        },
      );
    }

    test('sends no generation usage for an unknown context', () async {
      final worker = await _startWorkerInCurrentIsolate(
        _LimitedGenerationLlamaCppService(null),
      );

      try {
        final done = await _generateUntilDone(
          worker.sendPort,
          (sendPort) => GenerateRequest(
            1,
            'hello',
            const GenerationParams(),
            0,
            sendPort,
          ),
        );

        expect(done.generationUsage, isNull);
      } finally {
        await _disposeWorker(worker);
      }
    });

    test(
      'worker forwards the prompt penalty flag on caller and chat routes',
      () async {
        final service = _PromptRecordingLlamaCppService();
        final worker = await _startWorkerInCurrentIsolate(service);
        try {
          for (final chat in [false, true]) {
            for (final enabled in [false, true]) {
              await _generateUntilDone(
                worker.sendPort,
                (port) => GenerateRequest(
                  7,
                  'prompt',
                  const GenerationParams(),
                  0,
                  port,
                  chatMediaMarker: chat ? '<m>' : null,
                  countPromptTokensInPenalties: enabled,
                ),
              );
            }
          }
          expect(service.penaltyPolicies, [false, true, false, true]);
        } finally {
          await _disposeWorker(worker);
        }
      },
    );

    test('gives the service a chat prompt with its marker and a caller '
        'prompt without one', () async {
      final service = _PromptRecordingLlamaCppService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        await _generateUntilDone(
          worker.sendPort,
          (sendPort) => GenerateRequest(
            7,
            '<m>a <img>',
            const GenerationParams(),
            0,
            sendPort,
            chatMediaMarker: '<m>',
          ),
        );
        await _generateUntilDone(
          worker.sendPort,
          (sendPort) => GenerateRequest(
            7,
            '<img>b',
            const GenerationParams(),
            0,
            sendPort,
          ),
        );

        expect(service.chatPrompts, [('<m>a <img>', '<m>')]);
        expect(service.callerPrompts, ['<img>b']);
        expect(service.penaltyPolicies, [false, false]);
      } finally {
        await _disposeWorker(worker);
      }
    });

    test(
      'sends generation usage timed from the first non-empty chunk',
      () async {
        const firstTextDelay = Duration(milliseconds: 50);
        final worker = await _startWorkerInCurrentIsolate(
          _UsageReportingLlamaCppService(firstTextDelay),
        );

        try {
          final done = await _generateUntilDone(
            worker.sendPort,
            (sendPort) => GenerateRequest(
              7,
              'hello',
              const GenerationParams(),
              0,
              sendPort,
            ),
          );

          final usage = done.generationUsage!;
          expect(usage.promptTokens, 11);
          expect(usage.cachedPromptTokens, 4);
          expect(usage.completionTokens, 2);
          expect(
            usage.timeToFirstToken,
            greaterThanOrEqualTo(firstTextDelay ~/ 2),
          );
          expect(usage.duration, greaterThanOrEqualTo(usage.timeToFirstToken!));
        } finally {
          await _disposeWorker(worker);
        }
      },
    );

    test('routes text-to-speech progress, result, and cancellation', () async {
      final service = _BlockingTextToSpeechService();
      final worker = await _startWorkerInCurrentIsolate(service);
      final responsePort = ReceivePort();
      final responses = <Object>[];
      final resultCompleter = Completer<TextToSpeechResultResponse>();
      final capabilitiesCompleter =
          Completer<TextToSpeechCapabilitiesResponse>();
      final subscription = responsePort.listen((response) {
        if (response is Object) {
          responses.add(response);
        }
        if (response is TextToSpeechResultResponse &&
            !resultCompleter.isCompleted) {
          resultCompleter.complete(response);
        }
        if (response is TextToSpeechCapabilitiesResponse &&
            !capabilitiesCompleter.isCompleted) {
          capabilitiesCompleter.complete(response);
        }
      });

      try {
        worker.sendPort.send(
          TextToSpeechCapabilitiesRequest(2, 3, responsePort.sendPort),
        );
        await capabilitiesCompleter.future;
        expect(service.capabilityHandles, (2, 3));

        worker.sendPort.send(
          TextToSpeechSynthesizeRequest(
            2,
            3,
            const BackendTextToSpeechRequest(text: 'Hello.'),
            0x5a5a0,
            responsePort.sendPort,
          ),
        );
        await service.synthesisStarted.future;
        expect(service.synthesisHandles, (2, 3));
        expect(service.receivedCancelFlagAddress, 0x5a5a0);
        worker.sendPort.send(TextToSpeechCancelRequest());
        await service.cancelObserved.future;
        service.releaseSynthesis();

        final result = await resultCompleter.future;
        expect(
          responses.whereType<TextToSpeechProgressResponse>(),
          hasLength(1),
        );
        expect(Float32List.view(result.pcm.materialize()).toList(), <double>[
          0.5,
          -0.5,
        ]);
        expect(service.cancelCalls, 1);
      } finally {
        await subscription.cancel();
        responsePort.close();
        await _disposeWorker(worker);
      }
    });

    test('answers the text-to-speech model support probe', () async {
      final service = _BlockingTextToSpeechService();
      final worker = await _startWorkerInCurrentIsolate(service);
      final responsePort = ReceivePort();
      final responses = StreamIterator<dynamic>(responsePort);

      Future<String?> probe(BackendTextToSpeechModel model) async {
        worker.sendPort.send(
          TextToSpeechModelSupportRequest(model, responsePort.sendPort),
        );
        expect(await responses.moveNext(), isTrue);
        return (responses.current as TextToSpeechModelSupportResponse)
            .unsupportedReason;
      }

      try {
        expect(
          await probe(BackendTextToSpeechModel.soprano),
          'Soprano is not driven here.',
        );
        expect(await probe(BackendTextToSpeechModel.qwen3Tts), isNull);
        expect(service.probedModels, <BackendTextToSpeechModel>[
          BackendTextToSpeechModel.soprano,
          BackendTextToSpeechModel.qwen3Tts,
        ]);
      } finally {
        await responses.cancel();
        responsePort.close();
        await _disposeWorker(worker);
      }
    });

    test('preserves text-to-speech error categories', () async {
      final cases = <(Object, WorkerErrorKind)>[
        (
          LlamaAudioFormatException('Invalid speaker audio', 'wav'),
          WorkerErrorKind.audioFormat,
        ),
        (
          LlamaTextToSpeechException('Synthesis failed', 'native'),
          WorkerErrorKind.textToSpeech,
        ),
        (
          LlamaSpeechException('Speech failed', 'generic'),
          WorkerErrorKind.speech,
        ),
      ];

      for (final (exception, expectedKind) in cases) {
        final worker = await _startWorkerInCurrentIsolate(
          _ThrowingTextToSpeechService(exception),
        );
        try {
          final response = await _sendRequest(
            worker.sendPort,
            (sendPort) => TextToSpeechSynthesizeRequest(
              2,
              3,
              const BackendTextToSpeechRequest(text: 'Hello.'),
              0x5a5a0,
              sendPort,
            ),
          );
          expect(response, isA<ErrorResponse>());
          expect((response as ErrorResponse).kind, expectedKind);
          expect(response.message, isNot(contains('LlamaException:')));
        } finally {
          await _disposeWorker(worker);
        }
      }
    });

    test('preserves LoRA and capability error categories', () async {
      final cases = <(Object, WorkerErrorKind)>[
        (
          LlamaModelException('Failed to load LoRA at bad.gguf'),
          WorkerErrorKind.model,
        ),
        (
          LlamaUnsupportedException('The adapter is an aLoRA adapter'),
          WorkerErrorKind.unsupported,
        ),
        (
          UnsupportedError('native capability missing'),
          WorkerErrorKind.unsupported,
        ),
        // UnimplementedError implements UnsupportedError, so it must not be
        // reclassified as a runtime capability limit.
        (UnimplementedError('not done yet'), WorkerErrorKind.generic),
        (Exception('boom'), WorkerErrorKind.generic),
      ];

      for (final (exception, expectedKind) in cases) {
        final worker = await _startWorkerInCurrentIsolate(
          _ThrowingLoraService(exception),
        );
        try {
          final response = await _sendRequest(
            worker.sendPort,
            (sendPort) => LoraRequest(
              1,
              'set',
              path: 'bad.gguf',
              scale: 1.0,
              sendPort: sendPort,
            ),
          );
          expect(response, isA<ErrorResponse>());
          expect((response as ErrorResponse).kind, expectedKind);
          expect(response.message, isNot(contains('LlamaException:')));
        } finally {
          await _disposeWorker(worker);
        }
      }
    });

    test(
      'releases TTS handle waits when sending a synthesis reply throws',
      () async {
        final errors = <Object>[];
        final service = _BlockingTtsHandleService();
        final worker = await runZoned(
          () => _startWorkerInCurrentIsolate(
            service,
            disposeActiveGenerateTimeout: const Duration(milliseconds: 30),
          ),
          zoneSpecification: ZoneSpecification(
            handleUncaughtError: (self, parent, zone, error, stack) =>
                errors.add(error),
          ),
        );
        final pending = <_PendingResponse>[];
        try {
          worker.sendPort.send(
            TextToSpeechSynthesizeRequest(
              2,
              3,
              const BackendTextToSpeechRequest(text: 'hello'),
              0,
              _ThrowingSendPort(),
            ),
          );
          await service.synthesisStarted.future;
          for (final build in <WorkerRequest Function(SendPort)>[
            (port) => ModelFreeRequest(1, port),
            (port) => ContextFreeRequest(2, port),
            (port) => MultimodalContextFreeRequest(3, port),
          ]) {
            final response = _PendingResponse();
            pending.add(response);
            worker.sendPort.send(build(response.sendPort));
          }
          for (final response in pending) {
            await response.expectNoResponse();
          }
          expect(service.frees, isEmpty);
          service.releaseSynthesis();
          for (final response in pending) {
            expect(
              await response.nextResponse.timeout(const Duration(seconds: 1)),
              isA<DoneResponse>(),
            );
          }
          expect(
            service.frees,
            unorderedEquals(['model', 'context', 'projector']),
          );
          await pumpEventQueue();
          expect(errors, isNotEmpty);
          expect(errors, everyElement(isA<StateError>()));
        } finally {
          service.releaseSynthesis();
          for (final response in pending) {
            response.close();
          }
          await _disposeWorker(worker);
        }
      },
    );

    test(
      'waits for original TTS after a second synthesis is rejected',
      () async {
        final service = _BlockingTtsHandleService();
        final worker = await _startWorkerInCurrentIsolate(service);
        final synthesisPort = ReceivePort();
        final synthesisResult = synthesisPort.first;
        final pending = <_PendingResponse>[];
        try {
          worker.sendPort.send(
            TextToSpeechSynthesizeRequest(
              2,
              3,
              const BackendTextToSpeechRequest(text: 'hello'),
              0,
              synthesisPort.sendPort,
            ),
          );
          await service.synthesisStarted.future;
          final rejected = await _sendRequest(
            worker.sendPort,
            (port) => TextToSpeechSynthesizeRequest(
              2,
              3,
              const BackendTextToSpeechRequest(text: 'second'),
              0,
              port,
            ),
          );
          expect(rejected, isA<ErrorResponse>());
          expect((rejected as ErrorResponse).kind, WorkerErrorKind.state);
          for (final build in <WorkerRequest Function(SendPort)>[
            (port) => ModelFreeRequest(1, port),
            (port) => ContextFreeRequest(2, port),
            (port) => MultimodalContextFreeRequest(3, port),
          ]) {
            final response = _PendingResponse();
            pending.add(response);
            worker.sendPort.send(build(response.sendPort));
          }
          for (final response in pending) {
            await response.expectNoResponse();
          }
          expect(service.frees, isEmpty);
          service.releaseSynthesis();
          for (final response in pending) {
            expect(await response.nextResponse, isA<DoneResponse>());
          }
          expect(
            service.frees,
            unorderedEquals(['model', 'context', 'projector']),
          );
        } finally {
          service.releaseSynthesis();
          await synthesisResult;
          synthesisPort.close();
          for (final response in pending) {
            response.close();
          }
          await _disposeWorker(worker);
        }
      },
    );

    for (final failFirst in [false, true]) {
      test(
        'waits for later TTS after completion (failure: $failFirst)',
        () async {
          final service = _SequentialTextToSpeechService(failFirst);
          final worker = await _startWorkerInCurrentIsolate(service);
          final synthesis = _PendingResponse();
          final disposal = _PendingResponse();
          var disposalSent = false;
          try {
            final first = await _sendRequest(
              worker.sendPort,
              (port) => TextToSpeechSynthesizeRequest(
                2,
                3,
                const BackendTextToSpeechRequest(text: 'first'),
                0,
                port,
              ),
            );
            expect(
              first,
              failFirst
                  ? isA<ErrorResponse>()
                  : isA<TextToSpeechResultResponse>(),
            );
            worker.sendPort.send(
              TextToSpeechSynthesizeRequest(
                2,
                3,
                const BackendTextToSpeechRequest(text: 'second'),
                0,
                synthesis.sendPort,
              ),
            );
            await service.synthesisStarted.future;
            worker.sendPort.send(DisposeRequest(disposal.sendPort));
            disposalSent = true;
            await disposal.expectNoResponse();
            expect(service.disposeCalls, 0);
          } finally {
            service.releaseSynthesis();
            if (disposalSent) {
              await disposal.nextResponse;
            } else {
              await _disposeWorker(worker);
            }
            synthesis.close();
            disposal.close();
          }
          expect(service.disposeCalls, 1);
        },
      );
    }

    test('waits for active generation before freeing native handles', () async {
      final service = _BlockingLlamaCppService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final generationPort = ReceivePort();
        worker.sendPort.send(
          GenerateRequest(
            1,
            'hold',
            const GenerationParams(),
            0,
            generationPort.sendPort,
          ),
        );
        await service.generateStarted.future;

        final modelFree = _PendingResponse();
        worker.sendPort.send(ModelFreeRequest(11, modelFree.sendPort));
        final contextFree = _PendingResponse();
        worker.sendPort.send(ContextFreeRequest(22, contextFree.sendPort));
        final multimodalFree = _PendingResponse();
        worker.sendPort.send(
          MultimodalContextFreeRequest(33, multimodalFree.sendPort),
        );

        await Future<void>.delayed(Duration.zero);
        expect(service.freeModelCalls, 0);
        expect(service.freeContextCalls, 0);
        expect(service.freeMultimodalContextCalls, 0);
        await modelFree.expectNoResponse();
        await contextFree.expectNoResponse();
        await multimodalFree.expectNoResponse();

        service.releaseGeneration();

        expect(await modelFree.nextResponse, isA<DoneResponse>());
        expect(await contextFree.nextResponse, isA<DoneResponse>());
        expect(await multimodalFree.nextResponse, isA<DoneResponse>());
        expect(service.freeModelCalls, 1);
        expect(service.freeContextCalls, 1);
        expect(service.freeMultimodalContextCalls, 1);

        await _expectDoneResponse(generationPort);
        modelFree.close();
        contextFree.close();
        multimodalFree.close();
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('waits for active generation before disposing service', () async {
      final service = _BlockingLlamaCppService();
      final worker = await _startWorkerInCurrentIsolate(service);

      final generationPort = ReceivePort();
      worker.sendPort.send(
        GenerateRequest(
          1,
          'hold',
          const GenerationParams(),
          0,
          generationPort.sendPort,
        ),
      );
      await service.generateStarted.future;

      final disposeResponse = _PendingResponse();
      worker.sendPort.send(DisposeRequest(disposeResponse.sendPort));

      await Future<void>.delayed(Duration.zero);
      expect(service.disposeCalls, 0);
      await disposeResponse.expectNoResponse();

      service.releaseGeneration();

      expect(await disposeResponse.nextResponse, isNull);
      expect(service.disposeCalls, 1);
      await _expectDoneResponse(generationPort);
      disposeResponse.close();
    });

    test(
      'dispose times out wedged generation without disposing service',
      () async {
        final service = _BlockingLlamaCppService();
        final worker = await _startWorkerInCurrentIsolate(
          service,
          disposeActiveGenerateTimeout: const Duration(milliseconds: 30),
        );

        final generationPort = ReceivePort();
        final disposeResponse = _PendingResponse();
        try {
          worker.sendPort.send(
            GenerateRequest(
              1,
              'hold',
              const GenerationParams(),
              0,
              generationPort.sendPort,
            ),
          );
          await service.generateStarted.future;

          worker.sendPort.send(DisposeRequest(disposeResponse.sendPort));

          await disposeResponse.expectNoResponse();
          expect(await disposeResponse.nextResponse, isNull);
          expect(service.disposeCalls, 0);

          service.releaseGeneration();
          await _expectDoneResponse(generationPort);
        } finally {
          disposeResponse.close();
          generationPort.close();
        }
      },
    );
  });
}

Future<({Isolate isolate, SendPort sendPort})> _spawnWorker() async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(llamaWorkerEntry, receivePort.sendPort);
  final sendPort = await receivePort.first as SendPort;
  await _performHandshake(sendPort);
  return (isolate: isolate, sendPort: sendPort);
}

Future<({Isolate? isolate, SendPort sendPort})> _startWorkerInCurrentIsolate(
  LlamaCppService service, {
  Duration disposeActiveGenerateTimeout = const Duration(seconds: 5),
}) async {
  final receivePort = ReceivePort();
  runLlamaWorkerForTesting(
    receivePort.sendPort,
    service,
    exitOnDispose: false,
    disposeActiveGenerateTimeout: disposeActiveGenerateTimeout,
  );
  final sendPort = await receivePort.first as SendPort;
  receivePort.close();
  await _performHandshake(sendPort);
  return (isolate: null, sendPort: sendPort);
}

Future<void> _performHandshake(SendPort workerSendPort) async {
  final responsePort = ReceivePort();
  workerSendPort.send(
    WorkerHandshake(LlamaLogLevel.warn, responsePort.sendPort),
  );
  final response = await responsePort.first;
  responsePort.close();
  expect(response, isA<DoneResponse>());
}

Future<dynamic> _sendRequest(
  SendPort workerSendPort,
  WorkerRequest Function(SendPort sendPort) buildRequest,
) async {
  final responsePort = ReceivePort();
  workerSendPort.send(buildRequest(responsePort.sendPort));
  final response = await responsePort.first;
  responsePort.close();
  return response;
}

Future<DoneResponse> _generateUntilDone(
  SendPort workerSendPort,
  GenerateRequest Function(SendPort sendPort) buildRequest,
) async {
  final responsePort = ReceivePort();
  workerSendPort.send(buildRequest(responsePort.sendPort));
  try {
    return await responsePort.firstWhere((response) => response is DoneResponse)
        as DoneResponse;
  } finally {
    responsePort.close();
  }
}

Future<void> _disposeWorker(
  ({Isolate? isolate, SendPort sendPort}) worker,
) async {
  final responsePort = ReceivePort();
  worker.sendPort.send(DisposeRequest(responsePort.sendPort));
  await responsePort.first;
  responsePort.close();
  worker.isolate?.kill(priority: Isolate.immediate);
}

Future<void> _expectDoneResponse(ReceivePort responsePort) async {
  final response = await responsePort.first;
  expect(response, isA<DoneResponse>());
  responsePort.close();
}

class _PendingResponse {
  final ReceivePort _port = ReceivePort();
  final Completer<Object?> _nextResponse = Completer<Object?>();
  late final StreamSubscription<Object?> _subscription;

  _PendingResponse() {
    _subscription = _port.listen((response) {
      if (!_nextResponse.isCompleted) {
        _nextResponse.complete(response);
      }
    });
  }

  SendPort get sendPort => _port.sendPort;

  Future<Object?> get nextResponse => _nextResponse.future;

  Future<void> expectNoResponse() async {
    await expectLater(
      _nextResponse.future.timeout(const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
  }

  void close() {
    _subscription.cancel();
    _port.close();
  }
}

class _BlockingLlamaCppService extends LlamaCppService {
  final Completer<void> generateStarted = Completer<void>();
  final Completer<void> _releaseGeneration = Completer<void>();
  int freeModelCalls = 0;
  int freeContextCalls = 0;
  int freeMultimodalContextCalls = 0;
  int disposeCalls = 0;

  void releaseGeneration() {
    if (!_releaseGeneration.isCompleted) {
      _releaseGeneration.complete();
    }
  }

  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    bool countPromptTokensInPenalties = false,
    List<LlamaContentPart>? parts,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) async* {
    if (!generateStarted.isCompleted) {
      generateStarted.complete();
    }
    await _releaseGeneration.future;
  }

  @override
  void freeModel(int modelHandle) {
    freeModelCalls += 1;
  }

  @override
  void freeContext(int contextHandle) {
    freeContextCalls += 1;
  }

  @override
  void freeMultimodalContext(int mmContextHandle) {
    freeMultimodalContextCalls += 1;
  }

  @override
  void dispose() {
    disposeCalls += 1;
  }
}

class _FailingInitializationLlamaCppService extends LlamaCppService {
  int disposeCalls = 0;

  @override
  void initializeBackend() {
    throw ArgumentError('synthetic initialization failure');
  }

  @override
  List<String> getStartupDiagnostics() {
    return const <String>['libllamadart.so could not be opened'];
  }

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  void dispose() {
    disposeCalls += 1;
  }
}

class _UnsupportedGenerationLlamaCppService extends LlamaCppService {
  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    bool countPromptTokensInPenalties = false,
    List<LlamaContentPart>? parts,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) async* {
    throw LlamaUnsupportedException(
      'missing reasoning-budget wrapper in this test runtime',
    );
  }

  @override
  void dispose() {}
}

class _BlockingTextToSpeechService extends LlamaCppService {
  final Completer<void> synthesisStarted = Completer<void>();
  final Completer<void> cancelObserved = Completer<void>();
  final Completer<void> _releaseSynthesis = Completer<void>();
  int cancelCalls = 0;
  int? receivedCancelFlagAddress;
  (int, int)? capabilityHandles;
  (int, int)? synthesisHandles;
  final List<BackendTextToSpeechModel> probedModels =
      <BackendTextToSpeechModel>[];

  void releaseSynthesis() {
    if (!_releaseSynthesis.isCompleted) {
      _releaseSynthesis.complete();
    }
  }

  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  String? textToSpeechModelUnsupportedReason(BackendTextToSpeechModel model) {
    probedModels.add(model);
    return model == BackendTextToSpeechModel.qwen3Tts
        ? null
        : 'Soprano is not driven here.';
  }

  @override
  BackendTextToSpeechCapabilities textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) {
    capabilityHandles = (contextHandle, mmContextHandle);
    return const BackendTextToSpeechCapabilities(isSupported: true);
  }

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request,
    int cancelFlagAddress, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) async {
    synthesisHandles = (contextHandle, mmContextHandle);
    receivedCancelFlagAddress = cancelFlagAddress;
    if (!synthesisStarted.isCompleted) {
      synthesisStarted.complete();
    }
    await _releaseSynthesis.future;
    onProgress?.call(
      const BackendTextToSpeechProgress(
        phase: BackendTextToSpeechPhase.generating,
        promptTokensRemaining: 0,
        framesGenerated: 2,
        truncated: false,
      ),
    );
    return BackendTextToSpeechResult(
      samples: Float32List.fromList(<double>[0.5, -0.5]),
      sampleRateHz: 24000,
      channelCount: 1,
      framesGenerated: 2,
      truncated: false,
    );
  }

  @override
  void cancelTextToSpeech() {
    cancelCalls += 1;
    if (!cancelObserved.isCompleted) {
      cancelObserved.complete();
    }
  }

  @override
  void dispose() {}
}

class _ThrowingTextToSpeechService extends LlamaCppService {
  _ThrowingTextToSpeechService(this.exception);

  final Object exception;

  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request,
    int cancelFlagAddress, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) async {
    throw exception;
  }

  @override
  void dispose() {}
}

class _PromptRecordingLlamaCppService extends LlamaCppService {
  final List<String> callerPrompts = <String>[];
  final List<bool> penaltyPolicies = [];
  final List<(String, String)> chatPrompts = <(String, String)>[];

  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    bool countPromptTokensInPenalties = false,
    List<LlamaContentPart>? parts,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) {
    penaltyPolicies.add(countPromptTokensInPenalties);
    callerPrompts.add(prompt);
    return const Stream<List<int>>.empty();
  }

  @override
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    required String mediaMarker,
    bool countPromptTokensInPenalties = false,
    List<LlamaContentPart>? parts,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) {
    penaltyPolicies.add(countPromptTokensInPenalties);
    chatPrompts.add((prompt, mediaMarker));
    return const Stream<List<int>>.empty();
  }

  @override
  void dispose() {}
}

class _UsageReportingLlamaCppService extends LlamaCppService {
  _UsageReportingLlamaCppService(this.firstTextDelay);

  final Duration firstTextDelay;

  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    bool countPromptTokensInPenalties = false,
    List<LlamaContentPart>? parts,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) async* {
    yield const <int>[];
    await Future<void>.delayed(firstTextDelay);
    yield <int>[104];
    yield <int>[105];
  }

  @override
  ({int promptTokens, int cachedPromptTokens, int completionTokens})?
  lastGenerationTokenCounts(int contextHandle) => contextHandle == 7
      ? (promptTokens: 11, cachedPromptTokens: 4, completionTokens: 2)
      : null;

  @override
  void dispose() {}
}

class _LimitedGenerationLlamaCppService extends LlamaCppService {
  _LimitedGenerationLlamaCppService(this.limit);

  final BackendGenerationLimit? limit;

  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    bool countPromptTokensInPenalties = false,
    List<LlamaContentPart>? parts,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) async* {
    yield <int>[104, 105];
    final reached = limit;
    if (reached != null) {
      onLimit?.call(reached);
    }
  }

  @override
  void dispose() {}
}

class _InferenceGenerationLlamaCppService extends LlamaCppService {
  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    bool countPromptTokensInPenalties = false,
    List<LlamaContentPart>? parts,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) async* {
    throw LlamaInferenceException(
      'grammar sampler failed in this test runtime',
      'native grammar stack exhausted',
    );
  }

  @override
  void dispose() {}
}

class _ScoringService extends LlamaCppService {
  _ScoringService({this.error});

  final Object? error;
  final List<(int, String, List<int>, int, bool)> calls = [];

  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  List<int> tokenize(int modelHandle, String text, bool addSpecial) {
    if (error case final error?) throw error;
    return const [];
  }

  @override
  LlamaNextTokenScores scoreNextToken(
    int contextHandle,
    String prompt, {
    required List<int> candidates,
    required int topK,
    required bool reusePromptPrefix,
  }) {
    if (error case final error?) throw error;
    calls.add((contextHandle, prompt, candidates, topK, reusePromptPrefix));
    return LlamaNextTokenScores(
      candidates: [
        for (final token in candidates)
          LlamaTokenLogprob(token: token, bytes: const [65], logprob: -0.5),
      ],
      top: const [],
      promptTokens: 5,
    );
  }
}

class _DecisionService extends LlamaCppService {
  _DecisionService({this.error});

  final Object? error;
  final List<int> capabilityModels = <int>[];
  final List<(int, String, String?)> loads = <(int, String, String?)>[];
  final List<(int, List<BackendDecisionSequence>)> runs =
      <(int, List<BackendDecisionSequence>)>[];
  final List<int> freedHeads = <int>[];

  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  BackendDecisionCapabilities decisionCapabilities(int modelHandle) {
    if (error case final error?) throw error;
    capabilityModels.add(modelHandle);
    return const BackendDecisionCapabilities(isSupported: true);
  }

  @override
  BackendDecisionHeadInfo loadDecisionHead(
    int modelHandle,
    String headPath,
    String? configPath,
  ) {
    if (error case final error?) throw error;
    loads.add((modelHandle, headPath, configPath));
    return const BackendDecisionHeadInfo(
      handle: 9,
      hiddenSize: 4,
      clsToken: 1,
      sepToken: 2,
      maskToken: 3,
      maskText: '[MASK]',
      configJson: '{}',
      deviceName: 'CPU',
    );
  }

  @override
  List<BackendDecisionOutput> runDecision(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  ) {
    if (error case final error?) throw error;
    runs.add((headHandle, sequences));
    return [
      for (final sequence in sequences)
        BackendDecisionOutput(
          logits: Float32List.fromList([
            for (final marker in sequence.markers) marker.toDouble(),
          ]),
          actLogits: Float32List.fromList([2.0, -2.0]),
        ),
    ];
  }

  @override
  void freeDecisionHead(int headHandle) {
    if (error case final error?) throw error;
    freedHeads.add(headHandle);
  }

  @override
  void dispose() {}
}

class _ThrowingLoraService extends LlamaCppService {
  _ThrowingLoraService(this.error);

  final Object error;

  @override
  void initializeBackend() {}

  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  void handleLora(int contextHandle, String? path, double? scale, String op) {
    throw error;
  }

  @override
  void dispose() {}
}

class _BlockingTtsHandleService extends _BlockingTextToSpeechService {
  final List<String> frees = [];

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request,
    int cancelFlagAddress, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) {
    if (synthesisStarted.isCompleted) {
      throw LlamaStateException('Text-to-speech synthesis is already active.');
    }
    return super.synthesizeTextToSpeech(
      contextHandle,
      mmContextHandle,
      request,
      cancelFlagAddress,
      onProgress: onProgress,
    );
  }

  @override
  void freeModel(int modelHandle) => frees.add('model');
  @override
  void freeContext(int contextHandle) => frees.add('context');
  @override
  void freeMultimodalContext(int mmContextHandle) => frees.add('projector');
}

class _SequentialTextToSpeechService extends _BlockingTextToSpeechService {
  final bool failFirst;
  int disposeCalls = 0;

  _SequentialTextToSpeechService(this.failFirst);

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request,
    int cancelFlagAddress, {
    void Function(BackendTextToSpeechProgress)? onProgress,
  }) async {
    if (request.text == 'first') {
      if (failFirst) {
        throw LlamaStateException('Injected first request failure');
      }
      return BackendTextToSpeechResult(
        samples: Float32List(0),
        sampleRateHz: 24000,
        channelCount: 1,
        framesGenerated: 0,
        truncated: false,
      );
    }
    return super.synthesizeTextToSpeech(
      contextHandle,
      mmContextHandle,
      request,
      cancelFlagAddress,
    );
  }

  @override
  void dispose() => disposeCalls++;
}

class _ThrowingSendPort implements SendPort {
  @override
  void send(Object? message) => throw StateError('Injected reply send failure');
}
