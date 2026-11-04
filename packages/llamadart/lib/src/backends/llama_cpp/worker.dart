import 'dart:async';
import 'dart:isolate';

import '../../core/exceptions.dart';
import 'llama_cpp_service.dart';
import 'stream_batcher.dart';
import 'worker_messages.dart';

// Re-export messages so native_backend.dart can see them via worker.dart if needed
export 'worker_messages.dart';

ErrorResponse _toErrorResponse(Object error) {
  String messageFor(LlamaException error) => error.details == null
      ? error.message
      : '${error.message} (${error.details})';

  if (error is LlamaModelException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.model);
  }
  if (error is LlamaContextException) {
    return ErrorResponse(messageFor(error), kind: WorkerErrorKind.context);
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

  // Tracks the currently running generation so dispose can wait for it to emit
  // its terminal response (and stop reading the shared native cancel token)
  // before tearing the isolate down. Without this, Isolate.exit() abandons an
  // in-flight generate with no DoneResponse, hanging the consumer's stream.
  Future<void> activeGenerate = Future<void>.value();

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

  receivePort.listen((message) async {
    if (message is DisposeRequest) {
      shuttingDown = true;
      // Let any in-flight generation observe the cancel flag and finish
      // emitting its terminal response before we dispose native resources.
      final generationStopped = await waitForActiveGenerate(
        timeout: disposeActiveGenerateTimeout,
      );
      // If native generation wedges, acknowledge dispose and exit the worker
      // instead of hanging the caller forever. Skipping service.dispose() leaks
      // native handles only in this edge case, but avoids use-after-free.
      if (generationStopped) {
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

    // Handshake
    if (message is WorkerHandshake) {
      service.setLogLevel(message.initialLogLevel);
      if (!isInitialized) {
        service.initializeBackend();
        isInitialized = true;
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

          case ModelFreeRequest():
            await waitForActiveGenerate();
            service.freeModel(message.modelHandle);
            message.sendPort.send(DoneResponse());

          case ContextCreateRequest():
            final handle = service.createContext(
              message.modelHandle,
              message.params,
            );
            message.sendPort.send(HandleResponse(handle));

          case ContextFreeRequest():
            await waitForActiveGenerate();
            service.freeContext(message.contextHandle);
            message.sendPort.send(DoneResponse());

          case GenerateRequest():
            // Capture the generation future so a concurrent DisposeRequest can
            // await its terminal response before tearing down the isolate.
            final generateFuture = () async {
              try {
                final stream = service.generate(
                  message.contextHandle,
                  message.prompt,
                  message.params,
                  message.cancelTokenAddress,
                  parts: message.parts,
                );

                final batcher = NativeTokenStreamBatcher(
                  tokenThreshold: message.params.streamBatchTokenThreshold,
                  byteThreshold: message.params.streamBatchByteThreshold,
                );

                await for (final tokens in stream) {
                  final readyChunks = batcher.add(tokens);
                  for (final chunk in readyChunks) {
                    message.sendPort.send(TokenResponse(chunk));
                  }
                }

                final finalChunk = batcher.flush();
                if (finalChunk != null) {
                  message.sendPort.send(TokenResponse(finalChunk));
                }

                message.sendPort.send(DoneResponse());
              } catch (error) {
                message.sendPort.send(_toErrorResponse(error));
              }
            }();
            activeGenerate = generateFuture;
            await generateFuture;

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
        }
      } catch (error) {
        message.sendPort.send(_toErrorResponse(error));
      }
    }
  });
}
