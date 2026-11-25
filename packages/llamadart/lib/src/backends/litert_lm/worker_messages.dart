import 'dart:isolate';

import '../../core/exceptions.dart';
import '../../core/models/chat/chat_message.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/tool_choice.dart';
import '../backend.dart';
import '../worker_log_message.dart';
import 'litert_lm_embedding.dart';
import 'litert_lm_native_settlement.dart';
import '../../core/models/inference/embedding.dart';

export '../worker_log_message.dart';
export 'litert_lm_native_settlement.dart';

/// Base class for LiteRT-LM worker requests.
abstract class LiteRtLmWorkerRequest {
  /// The port to send responses to.
  final SendPort sendPort;

  /// Creates a new worker request.
  LiteRtLmWorkerRequest(this.sendPort);
}

/// Request to load a `.litertlm` model bundle.
class LiteRtLmModelLoadRequest extends LiteRtLmWorkerRequest {
  /// The local model bundle path.
  final String modelPath;

  /// Model load parameters.
  final ModelParams modelParams;

  /// Optional LiteRT-LM backend override such as cpu, gpu, or npu.
  final String? backendOverride;

  /// Creates a model load request.
  LiteRtLmModelLoadRequest(
    this.modelPath,
    this.modelParams,
    super.sendPort, {
    this.backendOverride,
  });
}

/// Request to free a model.
class LiteRtLmModelFreeRequest extends LiteRtLmWorkerRequest {
  /// The model handle to free.
  final int modelHandle;

  /// Creates a model free request.
  LiteRtLmModelFreeRequest(this.modelHandle, super.sendPort);
}

/// Request to create a context.
class LiteRtLmContextCreateRequest extends LiteRtLmWorkerRequest {
  /// The loaded model handle.
  final int modelHandle;

  /// Context parameters.
  final ModelParams params;

  /// Creates a context create request.
  LiteRtLmContextCreateRequest(this.modelHandle, this.params, super.sendPort);
}

/// Request to free a context.
class LiteRtLmContextFreeRequest extends LiteRtLmWorkerRequest {
  /// The context handle to free.
  final int contextHandle;

  /// Creates a context free request.
  LiteRtLmContextFreeRequest(this.contextHandle, super.sendPort);
}

/// Requests model-specific native JSON Schema provider admission.
class LiteRtLmJsonSchemaPrepareRequest extends LiteRtLmWorkerRequest {
  /// Creates an admission request.
  LiteRtLmJsonSchemaPrepareRequest(super.sendPort);
}

/// Request to generate text.
class LiteRtLmGenerateRequest extends LiteRtLmWorkerRequest {
  /// The context handle.
  final int contextHandle;

  /// Prompt text.
  final String prompt;

  /// Generation parameters.
  final GenerationParams params;

  /// Optional content parts.
  final List<LlamaContentPart>? parts;

  /// Creates a generate request.
  LiteRtLmGenerateRequest(
    this.contextHandle,
    this.prompt,
    this.params,
    super.sendPort, {
    this.parts,
  });
}

/// Request to generate text from structured chat messages.
class LiteRtLmGenerateChatRequest extends LiteRtLmWorkerRequest {
  /// The context handle.
  final int contextHandle;

  /// Structured chat messages.
  final List<LlamaChatMessage> messages;

  /// Generation parameters.
  final GenerationParams params;

  /// Optional validated native JSON Schema payload.
  final String? jsonSchema;

  /// Optional native tool definition JSON.
  final List<Map<String, dynamic>>? tools;

  /// Tool routing mode.
  final ToolChoice toolChoice;

  /// Whether the caller requested parallel tool calls.
  final bool parallelToolCalls;

  /// Whether thinking output should be enabled in template context.
  final bool enableThinking;

  /// Additional native template/context values.
  final Map<String, dynamic>? chatTemplateKwargs;

  /// Optional deterministic template time.
  final DateTime? templateNow;

  /// Creates a structured chat generate request.
  LiteRtLmGenerateChatRequest(
    this.contextHandle,
    this.messages,
    this.params,
    super.sendPort, {
    this.tools,
    this.jsonSchema,
    this.toolChoice = ToolChoice.auto,
    this.parallelToolCalls = false,
    this.enableThinking = true,
    this.chatTemplateKwargs,
    this.templateNow,
  });
}

/// Request to cancel the active generation.
class LiteRtLmCancelGenerationRequest extends LiteRtLmWorkerRequest {
  /// Creates a cancel request.
  LiteRtLmCancelGenerationRequest(super.sendPort);
}

/// Request to tokenize text.
class LiteRtLmTokenizeRequest extends LiteRtLmWorkerRequest {
  /// The model handle.
  final int modelHandle;

  /// Text to tokenize.
  final String text;

  /// Whether to add special tokens.
  final bool addSpecial;

  /// Whether [text] is a prompt to tokenize as native prefill reads it, which
  /// ignores [addSpecial].
  final bool runtimePrompt;

  /// Creates a tokenize request.
  LiteRtLmTokenizeRequest(
    this.modelHandle,
    this.text,
    this.addSpecial,
    super.sendPort, {
    this.runtimePrompt = false,
  });
}

/// Request to detokenize token IDs.
class LiteRtLmDetokenizeRequest extends LiteRtLmWorkerRequest {
  /// The model handle.
  final int modelHandle;

  /// Token IDs to detokenize.
  final List<int> tokens;

  /// Whether to include special tokens.
  final bool special;

  /// Creates a detokenize request.
  LiteRtLmDetokenizeRequest(
    this.modelHandle,
    this.tokens,
    this.special,
    super.sendPort,
  );
}

/// Request to get model metadata.
class LiteRtLmMetadataRequest extends LiteRtLmWorkerRequest {
  /// The model handle.
  final int modelHandle;

  /// Creates a metadata request.
  LiteRtLmMetadataRequest(this.modelHandle, super.sendPort);
}

/// Request for active backend information.
class LiteRtLmBackendInfoRequest extends LiteRtLmWorkerRequest {
  /// Creates a backend info request.
  LiteRtLmBackendInfoRequest(super.sendPort);
}

/// Request for available backend options.
class LiteRtLmAvailableBackendsRequest extends LiteRtLmWorkerRequest {
  /// Creates an available backends request.
  LiteRtLmAvailableBackendsRequest(super.sendPort);
}

/// Request for resolved GPU layers.
class LiteRtLmResolvedGpuLayersRequest extends LiteRtLmWorkerRequest {
  /// Creates a resolved GPU layers request.
  LiteRtLmResolvedGpuLayersRequest(super.sendPort);
}

/// Request for performance context metrics.
class LiteRtLmPerformanceContextRequest extends LiteRtLmWorkerRequest {
  /// The context handle.
  final int contextHandle;

  /// Creates a performance context request.
  LiteRtLmPerformanceContextRequest(this.contextHandle, super.sendPort);
}

/// Request to check GPU support.
class LiteRtLmGpuSupportRequest extends LiteRtLmWorkerRequest {
  /// Creates a GPU support request.
  LiteRtLmGpuSupportRequest(super.sendPort);
}

/// Request to dispose the worker.
class LiteRtLmDisposeRequest extends LiteRtLmWorkerRequest {
  /// Creates a dispose request.
  LiteRtLmDisposeRequest(super.sendPort);
}

/// Request to update log level.
class LiteRtLmLogLevelRequest extends LiteRtLmWorkerRequest {
  /// The target log level.
  final LlamaLogLevel logLevel;

  /// Creates a log level request.
  LiteRtLmLogLevelRequest(this.logLevel, super.sendPort);
}

/// Request to set the level the worker's Dart logger forwards from.
///
/// Ignored, but still answered with [LiteRtLmDoneResponse], when the
/// handshake carried no log port.
class LiteRtLmDartLogLevelRequest extends LiteRtLmWorkerRequest {
  /// The target log level.
  final LlamaLogLevel logLevel;

  /// Creates a Dart log level request.
  LiteRtLmDartLogLevelRequest(this.logLevel, super.sendPort);
}

/// Request to get the actual context size.
class LiteRtLmGetContextSizeRequest extends LiteRtLmWorkerRequest {
  /// The context handle.
  final int contextHandle;

  /// Creates a get context size request.
  LiteRtLmGetContextSizeRequest(this.contextHandle, super.sendPort);
}

/// Request for what the loaded bundle declares in its section metadata.
class LiteRtLmBundleCapabilitiesRequest extends LiteRtLmWorkerRequest {
  /// Creates a bundle capabilities request.
  LiteRtLmBundleCapabilitiesRequest(super.sendPort);
}

/// Request for the per-send decode controls the runtime and loaded bundle
/// apply.
class LiteRtLmGenerationControlsRequest extends LiteRtLmWorkerRequest {
  /// Creates a generation controls request.
  LiteRtLmGenerationControlsRequest(super.sendPort);
}

/// Request for system information.
class LiteRtLmSystemInfoRequest extends LiteRtLmWorkerRequest {
  /// Creates a system info request.
  LiteRtLmSystemInfoRequest(super.sendPort);
}

/// Request to apply a chat template.
class LiteRtLmChatTemplateRequest extends LiteRtLmWorkerRequest {
  /// The model handle.
  final int modelHandle;

  /// Messages to format.
  final List<Map<String, dynamic>> messages;

  /// Optional custom template.
  final String? customTemplate;

  /// Whether to add the assistant prompt.
  final bool addAssistant;

  /// Creates a chat template request.
  LiteRtLmChatTemplateRequest(
    this.modelHandle,
    this.messages,
    this.customTemplate,
    this.addAssistant,
    super.sendPort,
  );
}

/// Response containing a resource handle.
class LiteRtLmHandleResponse {
  /// The resource handle.
  final int handle;

  /// For a model load, whether the runtime reports why each generation
  /// ended; see `LiteRtLmRuntimeClient.supportsFinishReasons`.
  final bool reportsFinishReasons;

  /// Creates a handle response.
  LiteRtLmHandleResponse(this.handle, {this.reportsFinishReasons = false});
}

/// Response containing token bytes.
class LiteRtLmTokenResponse {
  /// The generated UTF-8 bytes.
  final List<int> bytes;

  /// Creates a token response.
  LiteRtLmTokenResponse(this.bytes);
}

/// Response containing token IDs.
class LiteRtLmTokenizeResponse {
  /// Token IDs.
  final List<int> tokens;

  /// Creates a tokenize response.
  LiteRtLmTokenizeResponse(this.tokens);
}

/// Response containing detokenized text.
class LiteRtLmDetokenizeResponse {
  /// Detokenized text.
  final String text;

  /// Creates a detokenize response.
  LiteRtLmDetokenizeResponse(this.text);
}

/// Response containing model metadata.
class LiteRtLmMetadataResponse {
  /// Metadata key-value pairs.
  final Map<String, String> metadata;

  /// Creates a metadata response.
  LiteRtLmMetadataResponse(this.metadata);
}

/// Response containing context size.
class LiteRtLmGetContextSizeResponse {
  /// Context size.
  final int size;

  /// Creates a context size response.
  LiteRtLmGetContextSizeResponse(this.size);
}

/// Response to a successful native JSON Schema admission.
class LiteRtLmJsonSchemaAdmissionResponse {
  /// Whether the admitted model may reason before its constrained reply.
  final bool thinking;

  /// Creates an admission response.
  LiteRtLmJsonSchemaAdmissionResponse({required this.thinking});
}

/// Response containing what the loaded bundle declares, or nothing when no
/// model is loaded or the runtime cannot read the declaration.
class LiteRtLmBundleCapabilitiesResponse {
  /// The declaration, as `LiteRtLmRuntimeClient.bundleCapabilities` reads it.
  final ({bool vision, bool audio, bool speculativeDecoding})? capabilities;

  /// Creates a bundle capabilities response.
  LiteRtLmBundleCapabilitiesResponse(this.capabilities);
}

/// Response containing the per-send decode controls the runtime and loaded
/// bundle apply, as `LiteRtLmService.generationControls` reports them.
class LiteRtLmGenerationControlsResponse {
  /// Whether repetition and presence penalties are applied.
  final bool penalties;

  /// Whether a thinking budget is applied.
  final bool thinkingBudget;

  /// Creates a generation controls response.
  LiteRtLmGenerationControlsResponse({
    required this.penalties,
    required this.thinkingBudget,
  });
}

/// Response containing an error.
class LiteRtLmErrorResponse {
  /// Error kind used to preserve public exception semantics across isolates.
  final String kind;

  /// Error message.
  final String message;

  /// Creates an error response.
  LiteRtLmErrorResponse(
    this.message, {
    this.kind = 'exception',
    this.argumentName,
    this.nativeSettlement = LiteRtLmNativeSettlement.settled,
  });

  /// [LlamaArgumentException.name] of the rejected argument, when known.
  final String? argumentName;

  /// Native lifetime, independent of the request's error kind.
  final LiteRtLmNativeSettlement nativeSettlement;

  /// Creates a typed response from an error object.
  factory LiteRtLmErrorResponse.from(
    Object error, {
    LiteRtLmNativeSettlement nativeSettlement =
        LiteRtLmNativeSettlement.settled,
  }) {
    final response = LiteRtLmErrorResponse._from(error);
    return LiteRtLmErrorResponse(
      response.message,
      kind: response.kind,
      argumentName: response.argumentName,
      nativeSettlement: nativeSettlement,
    );
  }

  factory LiteRtLmErrorResponse._from(Object error) {
    if (error is LlamaUnsupportedException) {
      return LiteRtLmErrorResponse(error.message, kind: 'llamaUnsupported');
    }
    if (error is LlamaException) {
      final kind = switch (error) {
        LlamaArgumentException() => 'llamaArgument',
        LlamaModelException() => 'llamaModel',
        LlamaContextException() => 'llamaContext',
        LlamaInferenceException() => 'llamaInference',
        LlamaStateException() => 'llamaState',
        _ => null,
      };
      if (kind != null) {
        final details = error.details;
        return LiteRtLmErrorResponse(
          details == null ? error.message : '${error.message} ($details)',
          kind: kind,
          argumentName: error is LlamaArgumentException ? error.name : null,
        );
      }
    }
    if (error is UnsupportedError) {
      return LiteRtLmErrorResponse(
        _stripErrorPrefix(error.toString(), 'Unsupported operation: '),
        kind: 'unsupported',
      );
    }
    if (error is ArgumentError) {
      return LiteRtLmErrorResponse(
        _stripErrorPrefix(error.toString(), 'Invalid argument(s): '),
        kind: 'argument',
      );
    }
    if (error is StateError) {
      return LiteRtLmErrorResponse(
        _stripErrorPrefix(error.toString(), 'Bad state: '),
        kind: 'state',
      );
    }
    return LiteRtLmErrorResponse(error.toString());
  }
}

/// Response containing backend name or backend list text.
class LiteRtLmBackendInfoResponse {
  /// Backend info text.
  final String name;

  /// Creates a backend info response.
  LiteRtLmBackendInfoResponse(this.name);
}

/// Response containing GPU support status.
class LiteRtLmGpuSupportResponse {
  /// Whether GPU is supported.
  final bool support;

  /// Creates a GPU support response.
  LiteRtLmGpuSupportResponse(this.support);
}

/// Response containing resolved GPU layers.
class LiteRtLmResolvedGpuLayersResponse {
  /// Resolved GPU layers.
  final int? layers;

  /// Creates a resolved GPU layers response.
  LiteRtLmResolvedGpuLayersResponse(this.layers);
}

/// Response containing performance context metrics.
class LiteRtLmPerformanceContextResponse {
  /// Model load time in ms.
  final double loadMs;

  /// Prompt evaluation time in ms.
  final double promptEvalMs;

  /// Decode evaluation time in ms.
  final double evalMs;

  /// Sampling time in ms.
  final double sampleMs;

  /// Number of prompt tokens.
  final int promptEvalTokens;

  /// Number of generated tokens.
  final int evalTokens;

  /// Number of sample steps.
  final int sampleCount;

  /// Number of reused graphs.
  final int reusedGraphs;

  /// Creates a performance response.
  LiteRtLmPerformanceContextResponse({
    required this.loadMs,
    required this.promptEvalMs,
    required this.evalMs,
    required this.sampleMs,
    required this.promptEvalTokens,
    required this.evalTokens,
    required this.sampleCount,
    required this.reusedGraphs,
  });
}

/// Response containing system information.
class LiteRtLmSystemInfoResponse {
  /// Total VRAM in bytes.
  final int totalVram;

  /// Free VRAM in bytes.
  final int freeVram;

  /// Creates a system info response.
  LiteRtLmSystemInfoResponse(this.totalVram, this.freeVram);
}

/// Response containing a formatted chat template.
class LiteRtLmChatTemplateResponse {
  /// Formatted prompt.
  final String result;

  /// Creates a chat template response.
  LiteRtLmChatTemplateResponse(this.result);
}

/// Response indicating an operation completed.
class LiteRtLmDoneResponse {
  /// The token limit that ended a generation, or null when none did or the
  /// runtime cannot tell.
  final BackendGenerationLimit? generationLimit;

  /// Creates a completion response.
  LiteRtLmDoneResponse({
    this.generationLimit,
    this.nativeSettlement = LiteRtLmNativeSettlement.settled,
  });

  /// Native lifetime at completion; a cancellation acknowledgement may be pending.
  final LiteRtLmNativeSettlement nativeSettlement;
}

/// Sent before the final response of a free or dispose request, immediately
/// before the worker calls native teardown: a free once earlier queued requests
/// have finished, a dispose once the in-flight request and native callbacks have
/// settled.
class LiteRtLmNativeTeardownStarted {
  /// Creates a teardown-started notice.
  const LiteRtLmNativeTeardownStarted();
}

/// Handshake message sent from the backend to the worker.
class LiteRtLmWorkerHandshake {
  /// Initial log level.
  final LlamaLogLevel initialLogLevel;

  /// The main isolate's [LlamaLogger] level at spawn; the worker forwards
  /// only records at or above it.
  final LlamaLogLevel dartLogLevel;

  /// Port that receives [WorkerLogMessage]s; `null` disables forwarding and
  /// leaves the worker's logger untouched.
  final SendPort? logPort;

  /// Creates a worker handshake.
  LiteRtLmWorkerHandshake(
    this.initialLogLevel, {
    this.dartLogLevel = LlamaLogLevel.none,
    this.logPort,
  });
}

String _stripErrorPrefix(String message, String prefix) {
  if (message.startsWith(prefix)) {
    return message.substring(prefix.length);
  }
  return message;
}

/// Request for processor-backed embedding capabilities.
class LiteRtLmEmbeddingCapabilitiesRequest extends LiteRtLmWorkerRequest {
  /// Context to probe.
  final int contextHandle;

  /// Creates a capability request.
  LiteRtLmEmbeddingCapabilitiesRequest(this.contextHandle, super.sendPort);
}

/// Cancels only the embedding identified by its response port.
class LiteRtLmCancelEmbeddingRequest extends LiteRtLmWorkerRequest {
  /// Response port of the active or queued request whose deadline expired.
  final SendPort embeddingPort;

  /// Creates a request-scoped cancellation.
  LiteRtLmCancelEmbeddingRequest(this.embeddingPort, super.sendPort);
}

/// Request containing owned embedding input bytes.
class LiteRtLmEmbedRequest extends LiteRtLmWorkerRequest {
  /// Loaded context.
  final int contextHandle;

  /// Ordered, copied inputs.
  final List<List<LiteRtLmEmbeddingPart>> inputs;

  /// Whether to L2-normalize the output.
  final bool normalize;

  /// Creates an embedding request.
  LiteRtLmEmbedRequest(
    this.contextHandle,
    this.inputs,
    this.normalize,
    super.sendPort,
  );
}

/// Processor-backed embedding capabilities.
class LiteRtLmEmbeddingCapabilitiesResponse {
  /// Qualified modalities.
  final LlamaEmbeddingCapabilities capabilities;

  /// Creates a capability response.
  LiteRtLmEmbeddingCapabilitiesResponse(this.capabilities);
}

/// Copied embedding vectors in request order.
class LiteRtLmEmbedResponse {
  /// Owned vectors.
  final List<List<double>> vectors;

  /// Creates an embedding response.
  LiteRtLmEmbedResponse(this.vectors);
}
