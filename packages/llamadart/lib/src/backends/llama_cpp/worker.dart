import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import '../../core/exceptions.dart';
import '../../core/llama_logger.dart';
import '../../core/models/inference/generation_usage.dart';
import '../backend.dart';
import '../native_token_stream_batcher.dart';
import 'llama_cpp_service.dart';
import 'worker_messages.dart';

// Re-export messages so native_backend.dart can see them via worker.dart if needed
export 'worker_messages.dart';

ErrorResponse _toErrorResponse(Object error) {
  String messageFor(LlamaException error) => error.details == null
      ? error.message
      : '${error.message} (${error.details})';

  if (error is LlamaArgumentException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.argument);
  }
  if (error is LlamaModelException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.model);
  }
  if (error is LlamaContextException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.context);
  }
  if (error is LlamaEmbeddingInputTooLongException) {
    return ErrorResponse(
      error.message,
      kind: WorkerErrorKind.embeddingInputTooLong,
      maxInputTokens: error.maxInputTokens,
      actualTokens: error.actualTokens,
    );
  }
  if (error is LlamaInferenceException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.inference);
  }
  if (error is LlamaUnsupportedException) {
    return ErrorResponse(error.message, kind: WorkerErrorKind.unsupported);
  }
  if (error is LlamaStateException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.state);
  }
  if (error is LlamaAudioFormatException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.audioFormat);
  }
  if (error is LlamaTextToSpeechException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.textToSpeech);
  }
  if (error is LlamaSpeechException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.speech);
  }
  // UnimplementedError is an unfinished code path, not a runtime capability
  // limit, so it stays generic. It implements UnsupportedError, so it must be
  // checked first.
  if (error is UnimplementedError) {
    return ErrorResponse(error.toString());
  }
  if (error is UnsupportedError) {
    return ErrorResponse(
      error.message ?? error.toString(),
      kind: WorkerErrorKind.unsupported,
    );
  }
  return ErrorResponse(error.toString());
}

/// Entry point for the llama worker isolate.
void llamaWorkerEntry(SendPort initialSendPort) {
  runLlamaWorkerForTesting(initialSendPort, LlamaCppService());
}

/// Runs the llama.cpp worker loop with an injected service.
///
/// This is public only for VM unit tests; production callers should use
/// [llamaWorkerEntry].
void runLlamaWorkerForTesting(
  SendPort initialSendPort,
  LlamaCppService service, {
  bool exitOnDispose = true,
  Duration disposeActiveGenerateTimeout = const Duration(seconds: 5),
}) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);

  var isInitialized = false;
  var shuttingDown = false;
  var forwardsLogs = false;

  // Tracks the currently running generation so dispose can wait for it to emit
  // its terminal response (and stop reading the shared native cancel token)
  // before tearing the isolate down. Without this, Isolate.exit() abandons an
  // in-flight generate with no DoneResponse, hanging the consumer's stream.
  Future<void> activeGenerate = Future<void>.value();
  Completer<void>? activeTextToSpeech;
  var pendingTextToSpeech = 0;

  Future<bool> waitForActiveGenerate({Duration? timeout}) async {
    try {
      final generate = activeGenerate;
      if (timeout == null) {
        await generate;
      } else {
        await generate.timeout(timeout);
      }
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      // Generation has already stopped if its future completed with an error.
      return true;
    }
  }

  Future<bool> waitForActiveTextToSpeech({Duration? timeout}) async {
    try {
      final synthesis = activeTextToSpeech?.future ?? Future<void>.value();
      if (timeout == null) {
        await synthesis;
      } else {
        await synthesis.timeout(timeout);
      }
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
    }
  }

  receivePort.listen((message) async {
    if (message is DisposeRequest) {
      shuttingDown = true;
      service.cancelTextToSpeech();
      // Let any in-flight generation observe the cancel flag and finish
      // emitting its terminal response before we dispose native resources.
      final generationStopped = await waitForActiveGenerate(
        timeout: disposeActiveGenerateTimeout,
      );
      final synthesisStopped = await waitForActiveTextToSpeech(
        timeout: disposeActiveGenerateTimeout,
      );
      // If native generation wedges, acknowledge dispose and exit the worker
      // instead of hanging the caller forever. Skipping service.dispose() leaks
      // native handles only in this edge case, but avoids use-after-free.
      if (generationStopped && synthesisStopped) {
        try {
          service.dispose();
        } catch (e) {
          // Ignore errors during dispose
        }
      }
      message.sendPort.send(null);
      receivePort.close();
      if (exitOnDispose) {
        Isolate.exit();
      }
      return;
    }

    if (message is TextToSpeechCancelRequest) {
      service.cancelTextToSpeech();
      return;
    }

    // Handshake
    if (message is WorkerHandshake) {
      final logPort = message.logPort;
      if (logPort != null) {
        installWorkerLogForwarding(logPort, message.dartLogLevel);
        forwardsLogs = true;
      }
      try {
        service.installWorkerOwner(message.nativeOwnerToken);
        service.setLogLevel(message.initialLogLevel);
        if (!isInitialized) {
          service.initializeBackend();
          isInitialized = true;
        }
        message.sendPort.send(DoneResponse());
      } catch (error, stackTrace) {
        final diagnostics = service.getStartupDiagnostics();
        final diagnosticsSuffix = formatStartupDiagnostics(diagnostics);
        final diagnosticsSection = diagnosticsSuffix.isEmpty
            ? ''
            : '\n${diagnosticsSuffix.replaceFirst(RegExp(r'^,\s*'), '')}';
        message.sendPort.send(
          ErrorResponse(
            'Failed to initialize the llama.cpp backend: '
            '$error\n$stackTrace$diagnosticsSection',
            kind: WorkerErrorKind.backendInitialization,
          ),
        );
        shuttingDown = true;
        try {
          service.dispose();
        } catch (_) {
          // Initialization already failed; preserve the original error.
        }
        receivePort.close();
        if (exitOnDispose) {
          Isolate.exit();
        }
      }
      return;
    }

    // Requests
    if (message is WorkerRequest) {
      if (shuttingDown) {
        return;
      }
      try {
        switch (message) {
          case ModelLoadRequest():
            final handle = service.loadModel(
              message.modelPath,
              message.modelParams,
            );
            message.sendPort.send(HandleResponse(handle));

          case LogLevelRequest():
            service.setLogLevel(message.logLevel);
            message.sendPort.send(DoneResponse());

          case DartLogLevelRequest():
            if (forwardsLogs) {
              LlamaLogger.instance.setLevel(message.logLevel);
            }
            message.sendPort.send(DoneResponse());

          case ModelFreeRequest():
            await waitForActiveGenerate();
            await waitForActiveTextToSpeech();
            service.freeModel(message.modelHandle);
            message.sendPort.send(DoneResponse());

          case RerankingContextCreateRequest():
            await waitForActiveGenerate();
            await waitForActiveTextToSpeech();
            message.sendPort.send(
              HandleResponse(
                service.createRerankingContext(
                  message.modelHandle,
                  message.params,
                ),
              ),
            );

          case ContextCreateRequest():
            final handle = service.createContext(
              message.modelHandle,
              message.params,
            );
            message.sendPort.send(HandleResponse(handle));

          case ContextFreeRequest():
            await waitForActiveGenerate();
            await waitForActiveTextToSpeech();
            service.freeContext(message.contextHandle);
            message.sendPort.send(DoneResponse());

          case GenerateRequest():
            // Capture the generation future so a concurrent DisposeRequest can
            // await its terminal response before tearing down the isolate.
            final generateFuture = () async {
              try {
                final stopwatch = Stopwatch()..start();
                Duration? timeToFirstToken;
                BackendGenerationLimit? limit;
                final chatMediaMarker = message.chatMediaMarker;
                final stream = chatMediaMarker == null
                    ? service.generate(
                        message.contextHandle,
                        message.prompt,
                        message.params,
                        message.cancelTokenAddress,
                        parts: message.parts,
                        countPromptTokensInPenalties:
                            message.countPromptTokensInPenalties,
                        onLimit: (reached) => limit = reached,
                      )
                    : service.generateChatPrompt(
                        message.contextHandle,
                        message.prompt,
                        message.params,
                        message.cancelTokenAddress,
                        mediaMarker: chatMediaMarker,
                        parts: message.parts,
                        countPromptTokensInPenalties:
                            message.countPromptTokensInPenalties,
                        onLimit: (reached) => limit = reached,
                      );

                final batcher = NativeTokenStreamBatcher(
                  tokenThreshold: message.params.streamBatchTokenThreshold,
                  byteThreshold: message.params.streamBatchByteThreshold,
                );

                await for (final tokens in stream) {
                  if (tokens.isNotEmpty) {
                    timeToFirstToken ??= stopwatch.elapsed;
                  }
                  final readyChunks = batcher.add(tokens);
                  for (final chunk in readyChunks) {
                    message.sendPort.send(TokenResponse(chunk));
                  }
                }

                final finalChunk = batcher.flush();
                if (finalChunk != null) {
                  message.sendPort.send(TokenResponse(finalChunk));
                }

                final counts = service.lastGenerationTokenCounts(
                  message.contextHandle,
                );
                message.sendPort.send(
                  DoneResponse(
                    generationLimit: limit,
                    generationUsage: counts == null
                        ? null
                        : LlamaGenerationUsage(
                            promptTokens: counts.promptTokens,
                            cachedPromptTokens: counts.cachedPromptTokens,
                            completionTokens: counts.completionTokens,
                            timeToFirstToken: timeToFirstToken,
                            duration: stopwatch.elapsed,
                          ),
                  ),
                );
              } catch (error) {
                message.sendPort.send(_toErrorResponse(error));
              }
            }();
            activeGenerate = generateFuture;
            await generateFuture;

          case TextToSpeechModelSupportRequest():
            message.sendPort.send(
              TextToSpeechModelSupportResponse(
                service.textToSpeechModelUnsupportedReason(message.model),
              ),
            );

          case TextToSpeechCapabilitiesRequest():
            final capabilities = service.textToSpeechCapabilities(
              message.contextHandle,
              message.mmContextHandle,
            );
            message.sendPort.send(
              TextToSpeechCapabilitiesResponse(capabilities),
            );

          case TextToSpeechSynthesizeRequest():
            final idle = activeTextToSpeech ??= Completer<void>();
            pendingTextToSpeech++;
            final synthesisFuture = () async {
              try {
                final result = await service.synthesizeTextToSpeech(
                  message.contextHandle,
                  message.mmContextHandle,
                  message.request,
                  message.cancelFlagAddress,
                  onProgress: (progress) {
                    message.sendPort.send(
                      TextToSpeechProgressResponse(progress),
                    );
                  },
                );
                message.sendPort.send(
                  TextToSpeechResultResponse(
                    samples: result.samples,
                    sampleRateHz: result.sampleRateHz,
                    channelCount: result.channelCount,
                    framesGenerated: result.framesGenerated,
                    truncated: result.truncated,
                  ),
                );
              } catch (error) {
                message.sendPort.send(_toErrorResponse(error));
              }
            }();
            // Rejected overlaps share this wait group so they cannot hide the
            // original task from disposal. Retire it when all handlers finish.
            try {
              await synthesisFuture;
            } finally {
              if (--pendingTextToSpeech == 0) {
                activeTextToSpeech = null;
                idle.complete();
              }
            }

          case GenerationCapabilitiesRequest():
            final capabilities = service.generationCapabilities(
              message.modelHandle,
            );
            message.sendPort.send(GenerationCapabilitiesResponse(capabilities));

          case DecisionCapabilitiesRequest():
            final capabilities = service.decisionCapabilities(
              message.modelHandle,
            );
            message.sendPort.send(DecisionCapabilitiesResponse(capabilities));

          case DecisionHeadLoadRequest():
            final head = service.loadDecisionHead(
              message.modelHandle,
              message.headPath,
              message.configPath,
            );
            message.sendPort.send(DecisionHeadLoadResponse(head));

          case DecisionRunRequest():
            final outputs = service.runDecision(
              message.headHandle,
              message.sequences,
            );
            message.sendPort.send(DecisionRunResponse(outputs));

          case DecisionHeadFreeRequest():
            service.freeDecisionHead(message.headHandle);
            message.sendPort.send(DoneResponse());

          case RerankingCapabilitiesRequest():
            await waitForActiveGenerate();
            message.sendPort.send(
              RerankingCapabilitiesResponse(
                service.getRerankingCapabilities(message.contextHandle),
              ),
            );

          case RerankRequest():
            await waitForActiveGenerate();
            await waitForActiveTextToSpeech();
            message.sendPort.send(
              RerankResponse(
                service.rerank(
                  message.contextHandle,
                  message.query,
                  message.documents,
                  cancelToken: Pointer<Int8>.fromAddress(
                    message.cancelTokenAddress,
                  ),
                ),
              ),
            );

          case EmbeddingCapabilitiesRequest():
            message.sendPort.send(
              EmbeddingCapabilitiesResponse(
                service.getEmbeddingCapabilities(message.contextHandle),
              ),
            );

          case EmbedContentBatchRequest():
            message.sendPort.send(
              EmbedBatchResponse(
                service.embedContentBatch(
                  message.contextHandle,
                  message.inputs,
                  normalize: message.normalize,
                  cancelToken: Pointer<Int8>.fromAddress(
                    message.cancelTokenAddress,
                  ),
                ),
              ),
            );

          case EmbedRequest():
            final embedding = service.embed(
              message.contextHandle,
              message.text,
              normalize: message.normalize,
            );
            message.sendPort.send(EmbedResponse(embedding));

          case EmbedBatchRequest():
            final embeddings = service.embedBatch(
              message.contextHandle,
              message.texts,
              normalize: message.normalize,
            );
            message.sendPort.send(EmbedBatchResponse(embeddings));

          case ScoreNextTokenRequest():
            try {
              final scores = service.scoreNextToken(
                message.contextHandle,
                message.prompt,
                candidates: message.candidates,
                topK: message.topK,
                reusePromptPrefix: message.reusePromptPrefix,
              );
              message.sendPort.send(ScoreNextTokenResponse(scores));
            } on RangeError catch (error) {
              message.sendPort.send(
                ErrorResponse(error.toString(), kind: WorkerErrorKind.range),
              );
            }

          case TokenizeRequest():
            final tokens = service.tokenize(
              message.modelHandle,
              message.text,
              message.addSpecial,
            );
            message.sendPort.send(TokenizeResponse(tokens));

          case DetokenizeRequest():
            final text = service.detokenize(
              message.modelHandle,
              message.tokens,
              message.special,
            );
            message.sendPort.send(DetokenizeResponse(text));

          case MetadataRequest():
            final metadata = service.getMetadata(message.modelHandle);
            message.sendPort.send(MetadataResponse(metadata));

          case ModelFileTypeRequest():
            final modelFileType = service.getModelFileType(message.modelHandle);
            message.sendPort.send(ModelFileTypeResponse(modelFileType));

          case LoraRequest():
            service.handleLora(
              message.contextHandle,
              message.path,
              message.scale,
              message.op,
            );
            message.sendPort.send(DoneResponse());

          case BackendInfoRequest():
            final info = service.getActiveBackendName();
            message.sendPort.send(BackendInfoResponse(info));

          case AvailableBackendsRequest():
            final info = service.getAvailableBackendInfo();
            message.sendPort.send(BackendInfoResponse(info.join(", ")));

          case ResolvedGpuLayersRequest():
            final layers = service.getResolvedGpuLayers();
            message.sendPort.send(ResolvedGpuLayersResponse(layers));

          case PerformanceContextRequest():
            final perf = service.getPerformanceContext(message.contextHandle);
            if (perf == null) {
              message.sendPort.send(DoneResponse());
              return;
            }
            message.sendPort.send(
              PerformanceContextResponse(
                loadMs: perf.loadMs,
                promptEvalMs: perf.promptEvalMs,
                evalMs: perf.evalMs,
                sampleMs: perf.sampleMs,
                decodeMs: perf.decodeMs,
                promptEvalTokens: perf.promptEvalTokens,
                evalTokens: perf.evalTokens,
                sampleCount: perf.sampleCount,
                reusedGraphs: perf.reusedGraphs,
                speculativeDraftTokens: perf.speculativeDraftTokens,
                speculativeAcceptedDraftTokens:
                    perf.speculativeAcceptedDraftTokens,
                speculativeDraftAttempts: perf.speculativeDraftAttempts,
                speculativeVerifyTokens: perf.speculativeVerifyTokens,
                speculativeReplayTokens: perf.speculativeReplayTokens,
                speculativeDraftMs: perf.speculativeDraftMs,
                speculativeVerifyMs: perf.speculativeVerifyMs,
              ),
            );

          case GpuSupportRequest():
            final supports = service.getGpuSupport();
            message.sendPort.send(GpuSupportResponse(supports));

          case MultimodalContextCreateRequest():
            final handle = service.createMultimodalContext(
              message.modelHandle,
              message.mmProjPath,
            );
            message.sendPort.send(HandleResponse(handle));

          case MultimodalContextFreeRequest():
            await waitForActiveGenerate();
            await waitForActiveTextToSpeech();
            service.freeMultimodalContext(message.mmContextHandle);
            message.sendPort.send(DoneResponse());

          case GetContextSizeRequest():
            final size = service.getContextSize(message.contextHandle);
            message.sendPort.send(GetContextSizeResponse(size));

          case SupportsVisionRequest():
            final supported = service.supportsVision(message.mmContextHandle);
            message.sendPort.send(supported);

          case SupportsAudioRequest():
            final supported = service.supportsAudio(message.mmContextHandle);
            message.sendPort.send(supported);

          case SupportsVideoRequest():
            final supported = service.supportsVideo(message.mmContextHandle);
            message.sendPort.send(supported);

          case SystemInfoRequest():
            final info = service.getVramInfo();
            message.sendPort.send(SystemInfoResponse(info.total, info.free));

          case ListGpuDevicesRequest():
            final devices = service.listGpuDevices(
              probeBackends: message.probeBackends,
            );
            message.sendPort.send(ListGpuDevicesResponse(devices));

          case ChatTemplateRequest():
            message.sendPort.send(
              ChatTemplateResponse(
                service.applyChatTemplate(
                  message.modelHandle,
                  message.messages,
                  customTemplate: message.customTemplate,
                  addAssistant: message.addAssistant,
                ),
              ),
            );

          case StateSaveFileRequest():
            final ok = service.stateSaveFile(
              message.contextHandle,
              message.path,
              message.tokens,
            );
            message.sendPort.send(StateSaveFileResponse(ok));

          case StateLoadFileRequest():
            final tokens = service.stateLoadFile(
              message.contextHandle,
              message.path,
              message.tokenCapacity,
            );
            message.sendPort.send(StateLoadFileResponse(tokens));

          case StateIdentityRequest():
            message.sendPort.send(
              StateIdentityResponse(
                service.stateIdentity(message.contextHandle),
              ),
            );
        }
      } catch (error) {
        message.sendPort.send(_toErrorResponse(error));
      }
    }
  });
}
