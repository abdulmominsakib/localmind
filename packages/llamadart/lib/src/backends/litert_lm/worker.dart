import 'dart:async';
import 'dart:isolate';

import '../../core/llama_logger.dart';
import '../../core/engine/json_schema_chat_request.dart';
import '../../core/models/inference/tool_choice.dart';
import '../native_token_stream_batcher.dart';
import 'litert_lm_service.dart';
import 'worker_messages.dart';

export 'worker_messages.dart';

/// Entry point for the LiteRT-LM worker isolate.
void liteRtLmWorkerEntry(SendPort initialSendPort) {
  runLiteRtLmWorkerForTesting(initialSendPort, LiteRtLmService());
}

/// Runs the LiteRT-LM worker loop with an injected service.
///
/// This is public only for VM unit tests; production callers should use
/// [liteRtLmWorkerEntry].
void runLiteRtLmWorkerForTesting(
  SendPort initialSendPort,
  LiteRtLmService service, {
  bool exitOnDispose = true,
  Duration disposeTimeout = const Duration(seconds: 5),
}) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);

  Future<void> activeRequest = Future<void>.value();
  var cancellationSerial = 0;
  final embeddings = <SendPort, bool>{};
  SendPort? activeEmbedding;
  var generationInFlight = false;
  var generationCancelRequested = false;
  var shuttingDown = false;
  var forwardsLogs = false;

  LiteRtLmErrorResponse generationError(Object error) {
    if (service.nativeSettlement != LiteRtLmNativeSettlement.settled) {
      service.quarantineNativeResources();
      shuttingDown = true;
    }
    return LiteRtLmErrorResponse.from(
      error,
      nativeSettlement: service.nativeSettlement,
    );
  }

  LiteRtLmDoneResponse generationDone() {
    if (service.nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw StateError('LiteRT-LM stream ended before native settlement.');
    }
    return LiteRtLmDoneResponse(generationLimit: service.lastGenerationLimit);
  }

  receivePort.listen((message) async {
    if (message is LiteRtLmDisposeRequest) {
      shuttingDown = true;
      if (service.nativeSettlement == LiteRtLmNativeSettlement.quarantined) {
        message.sendPort.send(
          LiteRtLmErrorResponse(
            'LiteRT-LM native resources remain quarantined; restart the process.',
            kind: 'state',
            nativeSettlement: LiteRtLmNativeSettlement.quarantined,
          ),
        );
        return;
      }
      try {
        service.cancelGeneration();
      } catch (_) {
        // Cancellation can fail while the turn still drains successfully.
        // Only the subsequent native settlement and cleanup decide disposal.
      }
      var requestSettled = true;
      try {
        await activeRequest.timeout(disposeTimeout);
      } on TimeoutException {
        requestSettled = false;
      } catch (_) {
        // The request result does not establish native callback settlement.
      }
      if (!requestSettled ||
          service.nativeSettlement != LiteRtLmNativeSettlement.settled) {
        service.quarantineNativeResources();
        message.sendPort.send(
          LiteRtLmErrorResponse(
            'LiteRT-LM native operation has not settled; resources retained. '
            'Restart the process before retrying this runtime.',
            kind: 'state',
            nativeSettlement: LiteRtLmNativeSettlement.quarantined,
          ),
        );
        // Keep the callback owner, model link and cache lease alive. Exiting
        // this isolate could close a NativeCallable still used by native code.
        return;
      }
      message.sendPort.send(const LiteRtLmNativeTeardownStarted());
      try {
        service.dispose();
      } catch (error) {
        service.quarantineNativeResources();
        message.sendPort.send(
          LiteRtLmErrorResponse.from(
            error,
            nativeSettlement: LiteRtLmNativeSettlement.quarantined,
          ),
        );
        return;
      }
      message.sendPort.send(LiteRtLmDoneResponse());
      receivePort.close();
      if (exitOnDispose) Isolate.exit();
      return;
    }

    if (shuttingDown && message is LiteRtLmWorkerRequest) {
      message.sendPort.send(
        LiteRtLmErrorResponse(
          'LiteRT-LM worker is shutting down; restart the process before retrying.',
          kind: 'state',
          nativeSettlement: service.nativeSettlement,
        ),
      );
      return;
    }

    if (message is LiteRtLmWorkerHandshake) {
      if (shuttingDown) return;
      final logPort = message.logPort;
      if (logPort != null) {
        installWorkerLogForwarding(logPort, message.dartLogLevel);
        forwardsLogs = true;
      }
      service.setLogLevel(message.initialLogLevel);
      return;
    }

    if (message is! LiteRtLmWorkerRequest) {
      return;
    }

    if (message is LiteRtLmCancelEmbeddingRequest) {
      if (embeddings.containsKey(message.embeddingPort)) {
        embeddings[message.embeddingPort] = true;
      }
      try {
        if (activeEmbedding == message.embeddingPort) {
          service.cancelGeneration();
        }
        message.sendPort.send(
          LiteRtLmDoneResponse(nativeSettlement: service.nativeSettlement),
        );
      } catch (error) {
        message.sendPort.send(
          LiteRtLmErrorResponse.from(
            error,
            nativeSettlement: service.nativeSettlement,
          ),
        );
      }
      return;
    }

    if (message is LiteRtLmCancelGenerationRequest) {
      cancellationSerial++;
      if (generationInFlight) {
        generationCancelRequested = true;
      }
      try {
        service.cancelGeneration();
        message.sendPort.send(
          LiteRtLmDoneResponse(nativeSettlement: service.nativeSettlement),
        );
      } catch (error) {
        message.sendPort.send(
          LiteRtLmErrorResponse.from(
            error,
            nativeSettlement: service.nativeSettlement,
          ),
        );
      }
      return;
    }

    if (message is LiteRtLmGenerateRequest ||
        message is LiteRtLmGenerateChatRequest) {
      if (generationInFlight) {
        message.sendPort.send(
          LiteRtLmErrorResponse(
            'LiteRT-LM generation is already in progress.',
            kind: 'state',
          ),
        );
        return;
      }
      generationInFlight = true;
    }

    if (message is LiteRtLmEmbedRequest) {
      embeddings[message.sendPort] = false;
    }
    final requestCancellationSerial = cancellationSerial;
    activeRequest = activeRequest.catchError((_) {}).then((_) async {
      try {
        if (shuttingDown) {
          message.sendPort.send(
            LiteRtLmErrorResponse(
              'LiteRT-LM worker is shutting down.',
              kind: 'state',
              nativeSettlement: service.nativeSettlement,
            ),
          );
          return;
        }
        switch (message) {
          case LiteRtLmEmbeddingCapabilitiesRequest():
            message.sendPort.send(
              LiteRtLmEmbeddingCapabilitiesResponse(
                await service.embeddingCapabilities(message.contextHandle),
              ),
            );
          case LiteRtLmEmbedRequest():
            // Keep queued embed cancellation separate from conversation state.
            final embeddingCancelled =
                requestCancellationSerial != cancellationSerial ||
                embeddings[message.sendPort] == true;
            if (embeddingCancelled) {
              message.sendPort.send(
                LiteRtLmErrorResponse(
                  'LiteRT-LM embedding cancelled before dispatch.',
                  kind: 'llamaInference',
                ),
              );
              return;
            }
            activeEmbedding = message.sendPort;
            message.sendPort.send(
              LiteRtLmEmbedResponse(
                await service.embed(
                  message.contextHandle,
                  message.inputs,
                  normalize: message.normalize,
                ),
              ),
            );
          case LiteRtLmModelLoadRequest():
            final handle = await service.loadModel(
              message.modelPath,
              message.modelParams,
              backendOverride: message.backendOverride,
            );
            message.sendPort.send(
              LiteRtLmHandleResponse(
                handle,
                reportsFinishReasons:
                    !message.modelParams.liteRtLmEmbeddingEngine &&
                    service.reportsFinishReasons(),
              ),
            );

          case LiteRtLmJsonSchemaPrepareRequest():
            await service.prepareJsonSchemaChat();
            message.sendPort.send(
              LiteRtLmJsonSchemaAdmissionResponse(
                thinking: service.supportsJsonSchemaChatThinking,
              ),
            );

          case LiteRtLmModelFreeRequest():
            message.sendPort.send(const LiteRtLmNativeTeardownStarted());
            service.freeModel(message.modelHandle);
            message.sendPort.send(LiteRtLmDoneResponse());

          case LiteRtLmContextCreateRequest():
            final handle = service.createContext(
              message.modelHandle,
              message.params,
            );
            message.sendPort.send(LiteRtLmHandleResponse(handle));

          case LiteRtLmContextFreeRequest():
            message.sendPort.send(const LiteRtLmNativeTeardownStarted());
            service.freeContext(message.contextHandle);
            message.sendPort.send(LiteRtLmDoneResponse());

          case LiteRtLmGenerateRequest():
            try {
              if (generationCancelRequested) {
                service.resetPerformanceMetrics();
                message.sendPort.send(LiteRtLmDoneResponse());
                return;
              }
              final stream = service.generate(
                message.contextHandle,
                message.prompt,
                message.params,
                parts: message.parts,
              );
              final batcher = NativeTokenStreamBatcher(
                tokenThreshold: message.params.streamBatchTokenThreshold,
                byteThreshold: message.params.streamBatchByteThreshold,
              );

              await for (final tokens in stream) {
                final readyChunks = batcher.add(tokens);
                for (final chunk in readyChunks) {
                  message.sendPort.send(LiteRtLmTokenResponse(chunk));
                }
              }

              final finalChunk = batcher.flush();
              if (finalChunk != null) {
                message.sendPort.send(LiteRtLmTokenResponse(finalChunk));
              }

              message.sendPort.send(generationDone());
            } catch (error) {
              message.sendPort.send(generationError(error));
            }

          case LiteRtLmGenerateChatRequest():
            try {
              if (generationCancelRequested) {
                service.resetPerformanceMetrics();
                message.sendPort.send(LiteRtLmDoneResponse());
                return;
              }
              if (message.jsonSchema != null) {
                validateJsonSchemaChatRequest(
                  message.messages,
                  message.params,
                  hasTools: message.tools?.isNotEmpty ?? false,
                  requiredTools: message.toolChoice == ToolChoice.required,
                  parallelToolCalls: message.parallelToolCalls,
                  // Thinking is checked by the service after it re-admits the
                  // model; a recreated client clears the earlier admission.
                  enableThinking: false,
                );
              }
              final stream = message.jsonSchema != null
                  ? service.generateJsonSchemaChat(
                      message.contextHandle,
                      message.messages,
                      message.params,
                      jsonSchema: message.jsonSchema!,
                      enableThinking: message.enableThinking,
                      chatTemplateKwargs: message.chatTemplateKwargs,
                      templateNow: message.templateNow,
                    )
                  : service.generateChat(
                      message.contextHandle,
                      message.messages,
                      message.params,
                      tools: message.tools,
                      toolChoice: message.toolChoice,
                      parallelToolCalls: message.parallelToolCalls,
                      enableThinking: message.enableThinking,
                      chatTemplateKwargs: message.chatTemplateKwargs,
                      templateNow: message.templateNow,
                    );
              final batcher = NativeTokenStreamBatcher(
                tokenThreshold: message.params.streamBatchTokenThreshold,
                byteThreshold: message.params.streamBatchByteThreshold,
              );

              await for (final tokens in stream) {
                final readyChunks = batcher.add(tokens);
                for (final chunk in readyChunks) {
                  message.sendPort.send(LiteRtLmTokenResponse(chunk));
                }
              }

              final finalChunk = batcher.flush();
              if (finalChunk != null) {
                message.sendPort.send(LiteRtLmTokenResponse(finalChunk));
              }

              message.sendPort.send(generationDone());
            } catch (error) {
              message.sendPort.send(generationError(error));
            }

          case LiteRtLmTokenizeRequest():
            final tokens = message.runtimePrompt
                ? await service.tokenizeRuntimePrompt(
                    message.modelHandle,
                    message.text,
                  )
                : await service.tokenize(
                    message.modelHandle,
                    message.text,
                    message.addSpecial,
                  );
            message.sendPort.send(LiteRtLmTokenizeResponse(tokens));

          case LiteRtLmDetokenizeRequest():
            final text = await service.detokenize(
              message.modelHandle,
              message.tokens,
              message.special,
            );
            message.sendPort.send(LiteRtLmDetokenizeResponse(text));

          case LiteRtLmMetadataRequest():
            final metadata = service.getMetadata(message.modelHandle);
            message.sendPort.send(LiteRtLmMetadataResponse(metadata));

          case LiteRtLmBackendInfoRequest():
            final info = service.getActiveBackendName();
            message.sendPort.send(LiteRtLmBackendInfoResponse(info));

          case LiteRtLmAvailableBackendsRequest():
            final info = service.getAvailableBackendInfo();
            message.sendPort.send(LiteRtLmBackendInfoResponse(info.join(', ')));

          case LiteRtLmResolvedGpuLayersRequest():
            final layers = service.getResolvedGpuLayers();
            message.sendPort.send(LiteRtLmResolvedGpuLayersResponse(layers));

          case LiteRtLmPerformanceContextRequest():
            final perf = service.getPerformanceContext(message.contextHandle);
            if (perf == null) {
              message.sendPort.send(LiteRtLmDoneResponse());
            } else {
              message.sendPort.send(
                LiteRtLmPerformanceContextResponse(
                  loadMs: perf.loadMs,
                  promptEvalMs: perf.promptEvalMs,
                  evalMs: perf.evalMs,
                  sampleMs: perf.sampleMs,
                  promptEvalTokens: perf.promptEvalTokens,
                  evalTokens: perf.evalTokens,
                  sampleCount: perf.sampleCount,
                  reusedGraphs: perf.reusedGraphs,
                ),
              );
            }

          case LiteRtLmGpuSupportRequest():
            final supports = service.getGpuSupport();
            message.sendPort.send(LiteRtLmGpuSupportResponse(supports));

          case LiteRtLmLogLevelRequest():
            service.setLogLevel(message.logLevel);
            message.sendPort.send(LiteRtLmDoneResponse());

          case LiteRtLmDartLogLevelRequest():
            if (forwardsLogs) {
              LlamaLogger.instance.setLevel(message.logLevel);
            }
            message.sendPort.send(LiteRtLmDoneResponse());

          case LiteRtLmGetContextSizeRequest():
            final size = service.getContextSize(message.contextHandle);
            message.sendPort.send(LiteRtLmGetContextSizeResponse(size));

          case LiteRtLmBundleCapabilitiesRequest():
            message.sendPort.send(
              LiteRtLmBundleCapabilitiesResponse(service.bundleCapabilities()),
            );

          case LiteRtLmGenerationControlsRequest():
            final controls = service.generationControls();
            message.sendPort.send(
              LiteRtLmGenerationControlsResponse(
                penalties: controls.penalties,
                thinkingBudget: controls.thinkingBudget,
              ),
            );

          case LiteRtLmSystemInfoRequest():
            final info = service.getVramInfo();
            message.sendPort.send(
              LiteRtLmSystemInfoResponse(info.total, info.free),
            );

          case LiteRtLmChatTemplateRequest():
            final result = service.applyChatTemplate(
              message.modelHandle,
              message.messages,
              customTemplate: message.customTemplate,
              addAssistant: message.addAssistant,
            );
            message.sendPort.send(LiteRtLmChatTemplateResponse(result));
        }
      } catch (error) {
        message.sendPort.send(
          LiteRtLmErrorResponse.from(
            error,
            nativeSettlement: service.nativeSettlement,
          ),
        );
      } finally {
        if (message is LiteRtLmEmbedRequest) {
          embeddings.remove(message.sendPort);
          activeEmbedding = null;
        }
        if (message is LiteRtLmGenerateRequest ||
            message is LiteRtLmGenerateChatRequest) {
          generationCancelRequested = false;
          generationInFlight = false;
        }
      }
    });
  });
}
