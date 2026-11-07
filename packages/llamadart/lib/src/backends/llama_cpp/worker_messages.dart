import 'dart:isolate';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/gpu_device_info.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/diagnostics/model_file_type.dart';

/// Base class for all worker requests.
abstract class WorkerRequest {
  /// The port to send responses to.
  final SendPort sendPort;

  /// Creates a new [WorkerRequest].
  WorkerRequest(this.sendPort);
}

/// Request to load a model.
class ModelLoadRequest extends WorkerRequest {
  /// The path to the model file.
  final String modelPath;

  /// Parameters for loading the model.
  final ModelParams modelParams;

  /// Creates a new [ModelLoadRequest].
  ModelLoadRequest(this.modelPath, this.modelParams, super.sendPort);
}

/// Request to free a model.
class ModelFreeRequest extends WorkerRequest {
  /// The handle of the model to free.
  final int modelHandle;

  /// Creates a new [ModelFreeRequest].
  ModelFreeRequest(this.modelHandle, super.sendPort);
}

/// Request to create an inference context.
class ContextCreateRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// Parameters for the context.
  final ModelParams params;

  /// Creates a new [ContextCreateRequest].
  ContextCreateRequest(this.modelHandle, this.params, super.sendPort);
}

/// Request to free an inference context.
class ContextFreeRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// Creates a new [ContextFreeRequest].
  ContextFreeRequest(this.contextHandle, super.sendPort);
}

/// Request to generate text.
class GenerateRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// The input prompt.
  final String prompt;

  /// Generation parameters.
  final GenerationParams params;

  /// Address of the cancel token.
  final int cancelTokenAddress;

  /// Multimodal content parts.
  final List<LlamaContentPart>? parts;

  /// Creates a new [GenerateRequest].
  GenerateRequest(
    this.contextHandle,
    this.prompt,
    this.params,
    this.cancelTokenAddress,
    super.sendPort, {
    this.parts,
  });
}

/// Request to generate an embedding vector.
class EmbedRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// Text to encode as an embedding.
  final String text;

  /// Whether to L2-normalize the output vector.
  final bool normalize;

  /// Creates a new [EmbedRequest].
  EmbedRequest(this.contextHandle, this.text, this.normalize, super.sendPort);
}

/// Request to generate embedding vectors in a single worker call.
class EmbedBatchRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// Text inputs to encode as embeddings.
  final List<String> texts;

  /// Whether to L2-normalize each output vector.
  final bool normalize;

  /// Creates a new [EmbedBatchRequest].
  EmbedBatchRequest(
    this.contextHandle,
    this.texts,
    this.normalize,
    super.sendPort,
  );
}

/// Request to tokenize text.
class TokenizeRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// The text to tokenize.
  final String text;

  /// Whether to add special tokens.
  final bool addSpecial;

  /// Creates a new [TokenizeRequest].
  TokenizeRequest(this.modelHandle, this.text, this.addSpecial, super.sendPort);
}

/// Request to detokenize tokens.
class DetokenizeRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// The token IDs to detokenize.
  final List<int> tokens;

  /// Whether to include special tokens.
  final bool special;

  /// Creates a new [DetokenizeRequest].
  DetokenizeRequest(
    this.modelHandle,
    this.tokens,
    this.special,
    super.sendPort,
  );
}

/// Request to get model metadata.
class MetadataRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// Creates a new [MetadataRequest].
  MetadataRequest(this.modelHandle, super.sendPort);
}

/// Request to get model file type metadata.
class ModelFileTypeRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// Creates a new [ModelFileTypeRequest].
  ModelFileTypeRequest(this.modelHandle, super.sendPort);
}

/// Request for LoRA operations.
class LoraRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// Path to the LoRA file.
  final String? path;

  /// Strength scale.
  final double? scale;

  /// Operation: set, remove, clear.
  final String op;

  /// Creates a new [LoraRequest].
  LoraRequest(
    this.contextHandle,
    this.op, {
    this.path,
    this.scale,
    required SendPort sendPort,
  }) : super(sendPort);
}

/// Request for backend information.
class BackendInfoRequest extends WorkerRequest {
  /// Creates a new [BackendInfoRequest].
  BackendInfoRequest(super.sendPort);
}

/// Request for available backend options.
class AvailableBackendsRequest extends WorkerRequest {
  /// Creates a new [AvailableBackendsRequest].
  AvailableBackendsRequest(super.sendPort);
}

/// Request for resolved GPU layers of active model.
class ResolvedGpuLayersRequest extends WorkerRequest {
  /// Creates a new [ResolvedGpuLayersRequest].
  ResolvedGpuLayersRequest(super.sendPort);
}

/// Request for native llama.cpp perf timings of an active context.
class PerformanceContextRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// Creates a new [PerformanceContextRequest].
  PerformanceContextRequest(this.contextHandle, super.sendPort);
}

/// Request to check for GPU support.
class GpuSupportRequest extends WorkerRequest {
  /// Creates a new [GpuSupportRequest].
  GpuSupportRequest(super.sendPort);
}

/// Request to dispose the worker.
class DisposeRequest extends WorkerRequest {
  /// Creates a new [DisposeRequest].
  DisposeRequest(super.sendPort);
}

/// Request to update log level.
class LogLevelRequest extends WorkerRequest {
  /// The target log level.
  final LlamaLogLevel logLevel;

  /// Creates a new [LogLevelRequest].
  LogLevelRequest(this.logLevel, super.sendPort);
}

/// Request to get the actual context size.
class GetContextSizeRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// Creates a new [GetContextSizeRequest].
  GetContextSizeRequest(this.contextHandle, super.sendPort);
}

/// Request to create a multimodal context.
class MultimodalContextCreateRequest extends WorkerRequest {
  /// The handle of the text model.
  final int modelHandle;

  /// Path to the multimodal projector file (mmproj).
  final String mmProjPath;

  /// Creates a new [MultimodalContextCreateRequest].
  MultimodalContextCreateRequest(
    this.modelHandle,
    this.mmProjPath,
    super.sendPort,
  );
}

/// Request to free a multimodal context.
class MultimodalContextFreeRequest extends WorkerRequest {
  /// The handle of the multimodal context.
  final int mmContextHandle;

  /// Creates a new [MultimodalContextFreeRequest].
  MultimodalContextFreeRequest(this.mmContextHandle, super.sendPort);
}

/// Request to check for vision support.
class SupportsVisionRequest extends WorkerRequest {
  /// The handle of the multimodal context.
  final int mmContextHandle;

  /// Creates a new [SupportsVisionRequest].
  SupportsVisionRequest(this.mmContextHandle, super.sendPort);
}

/// Request to check for audio support.
class SupportsAudioRequest extends WorkerRequest {
  /// The handle of the multimodal context.
  final int mmContextHandle;

  /// Creates a new [SupportsAudioRequest].
  SupportsAudioRequest(this.mmContextHandle, super.sendPort);
}

/// Request for system information (VRAM/RAM).
class SystemInfoRequest extends WorkerRequest {
  /// Creates a new [SystemInfoRequest].
  SystemInfoRequest(super.sendPort);
}

/// Request to enumerate GPU-class devices. [probeBackends] opts into loading
/// only those backend modules before enumerating; empty means registered
/// backends only.
class ListGpuDevicesRequest extends WorkerRequest {
  /// Backends to load before enumerating; empty inspects registered ones only.
  final List<GpuBackend> probeBackends;

  /// Creates a new [ListGpuDevicesRequest].
  ListGpuDevicesRequest(this.probeBackends, super.sendPort);
}

/// Request to write the KV-cache state of [contextHandle] to [path]
/// together with the producing token sequence (for state restore).
class StateSaveFileRequest extends WorkerRequest {
  /// Context whose state to persist.
  final int contextHandle;

  /// Destination file path.
  final String path;

  /// Token sequence the current state was produced from.
  final List<int> tokens;

  /// Creates a new [StateSaveFileRequest].
  StateSaveFileRequest(
    this.contextHandle,
    this.path,
    this.tokens,
    super.sendPort,
  );
}

/// Request to load a previously saved KV-cache state from [path].
/// [tokenCapacity] caps the number of tokens the caller can hold —
/// typically the loaded model's context size.
class StateLoadFileRequest extends WorkerRequest {
  /// Context to restore the saved state into.
  final int contextHandle;

  /// Source file path.
  final String path;

  /// Maximum number of tokens to read back.
  final int tokenCapacity;

  /// Creates a new [StateLoadFileRequest].
  StateLoadFileRequest(
    this.contextHandle,
    this.path,
    this.tokenCapacity,
    super.sendPort,
  );
}

/// Request to apply a chat template.
class ChatTemplateRequest extends WorkerRequest {
  /// The handle of the model.
  final int modelHandle;

  /// The list of messages.
  final List<Map<String, dynamic>> messages;

  /// Optional custom template string.
  final String? customTemplate;

  /// Whether to add assistant prompt.
  final bool addAssistant;

  /// Creates a new [ChatTemplateRequest].
  ChatTemplateRequest(
    this.modelHandle,
    this.messages,
    this.customTemplate,
    this.addAssistant,
    super.sendPort,
  );
}

/// Response containing a resource handle.
class HandleResponse {
  /// The unique handle.
  final int handle;

  /// Creates a new [HandleResponse].
  HandleResponse(this.handle);
}

/// Response containing token bytes.
class TokenResponse {
  /// The generated bytes.
  final List<int> bytes;

  /// Creates a new [TokenResponse].
  TokenResponse(this.bytes);
}

/// Response containing a list of token IDs.
class TokenizeResponse {
  /// The resulting tokens.
  final List<int> tokens;

  /// Creates a new [TokenizeResponse].
  TokenizeResponse(this.tokens);
}

/// Response containing an embedding vector.
class EmbedResponse {
  /// Embedding values as doubles.
  final List<double> embedding;

  /// Creates a new [EmbedResponse].
  EmbedResponse(this.embedding);
}

/// Response containing multiple embedding vectors.
class EmbedBatchResponse {
  /// Embedding values in input order.
  final List<List<double>> embeddings;

  /// Creates a new [EmbedBatchResponse].
  EmbedBatchResponse(this.embeddings);
}

/// Response containing detokenized text.
class DetokenizeResponse {
  /// The resulting text.
  final String text;

  /// Creates a new [DetokenizeResponse].
  DetokenizeResponse(this.text);
}

/// Response containing model metadata.
class MetadataResponse {
  /// The metadata key-value pairs.
  final Map<String, String> metadata;

  /// Creates a new [MetadataResponse].
  MetadataResponse(this.metadata);
}

/// Response containing model file type metadata.
class ModelFileTypeResponse {
  /// The model file type metadata, or null when unavailable.
  final ModelFileType? modelFileType;

  /// Creates a new [ModelFileTypeResponse].
  ModelFileTypeResponse(this.modelFileType);
}

/// Response containing the context size.
class GetContextSizeResponse {
  /// The context size.
  final int size;

  /// Creates a new [GetContextSizeResponse].
  GetContextSizeResponse(this.size);
}

/// Response from a [StateSaveFileRequest]: success / failure.
class StateSaveFileResponse {
  /// Whether the save succeeded.
  final bool success;

  /// Creates a new [StateSaveFileResponse].
  StateSaveFileResponse(this.success);
}

/// Response from a [StateLoadFileRequest]: the token sequence the
/// restored state was originally produced from.
class StateLoadFileResponse {
  /// The recovered token IDs.
  final List<int> tokens;

  /// Creates a new [StateLoadFileResponse].
  StateLoadFileResponse(this.tokens);
}

/// Category used to preserve llama.cpp worker failures across isolates.
enum WorkerErrorKind {
  /// An unclassified worker error.
  generic,

  /// Model loading or ownership failed.
  model,

  /// Context creation or ownership failed.
  context,

  /// Inference or token generation failed.
  inference,

  /// A requested operation is unavailable in the active native runtime.
  unsupported,

  /// The engine was not in a state that permits the operation.
  state,
}

/// Response containing an error message and category.
class ErrorResponse {
  /// The error message.
  final String message;

  /// The category of error reported by the worker.
  final WorkerErrorKind kind;

  /// Creates a new [ErrorResponse].
  ErrorResponse(this.message, {this.kind = WorkerErrorKind.generic});
}

/// Response containing backend name.
class BackendInfoResponse {
  /// The backend name.
  final String name;

  /// Creates a new [BackendInfoResponse].
  BackendInfoResponse(this.name);
}

/// Response containing GPU support status.
class GpuSupportResponse {
  /// Whether supported.
  final bool support;

  /// Creates a new [GpuSupportResponse].
  GpuSupportResponse(this.support);
}

/// Response containing resolved GPU layers.
class ResolvedGpuLayersResponse {
  /// Resolved layer count for active model load.
  final int? layers;

  /// Creates a new [ResolvedGpuLayersResponse].
  ResolvedGpuLayersResponse(this.layers);
}

/// Response containing native llama.cpp perf timings.
class PerformanceContextResponse {
  /// Model load time in ms.
  final double loadMs;

  /// Prompt evaluation time in ms.
  final double promptEvalMs;

  /// Decode evaluation time in ms.
  final double evalMs;

  /// Sampling time in ms.
  final double sampleMs;

  /// Decode-only generation time in ms.
  final double? decodeMs;

  /// Number of prompt-evaluated tokens.
  final int promptEvalTokens;

  /// Number of generated tokens.
  final int evalTokens;

  /// Number of sampled tokens.
  final int sampleCount;

  /// Number of times graphs were reused.
  final int reusedGraphs;

  /// Number of speculative draft tokens proposed.
  final int? speculativeDraftTokens;

  /// Number of speculative draft tokens accepted.
  final int? speculativeAcceptedDraftTokens;

  /// Number of speculative draft attempts made.
  final int? speculativeDraftAttempts;

  /// Number of target-model tokens decoded to verify speculative drafts.
  final int? speculativeVerifyTokens;

  /// Number of target-model tokens decoded to replay accepted speculative work.
  final int? speculativeReplayTokens;

  /// Time spent generating speculative drafts in ms.
  final double? speculativeDraftMs;

  /// Time spent verifying speculative drafts in ms.
  final double? speculativeVerifyMs;

  /// Creates a new [PerformanceContextResponse].
  PerformanceContextResponse({
    required this.loadMs,
    required this.promptEvalMs,
    required this.evalMs,
    required this.sampleMs,
    this.decodeMs,
    required this.promptEvalTokens,
    required this.evalTokens,
    required this.sampleCount,
    required this.reusedGraphs,
    this.speculativeDraftTokens,
    this.speculativeAcceptedDraftTokens,
    this.speculativeDraftAttempts,
    this.speculativeVerifyTokens,
    this.speculativeReplayTokens,
    this.speculativeDraftMs,
    this.speculativeVerifyMs,
  });
}

/// Response containing system information.
class SystemInfoResponse {
  /// Total VRAM in bytes.
  final int totalVram;

  /// Free VRAM in bytes.
  final int freeVram;

  /// Creates a new [SystemInfoResponse].
  SystemInfoResponse(this.totalVram, this.freeVram);
}

/// Response carrying the enumerated GPU-class devices.
class ListGpuDevicesResponse {
  /// The enumerated devices (empty when none are reachable).
  final List<GpuDeviceInfo> devices;

  /// Creates a new [ListGpuDevicesResponse].
  ListGpuDevicesResponse(this.devices);
}

/// Response containing the formatted chat template result.
class ChatTemplateResponse {
  /// The formatted prompt string.
  final String result;

  /// Creates a new [ChatTemplateResponse].
  ChatTemplateResponse(this.result);
}

/// Response indicating an operation has completed.
class DoneResponse {}

/// Handshake message sent from main to worker.
class WorkerHandshake {
  /// The initial log level to set before backend initialization.
  final LlamaLogLevel initialLogLevel;

  /// Creates a new [WorkerHandshake].
  WorkerHandshake(this.initialLogLevel);
}
