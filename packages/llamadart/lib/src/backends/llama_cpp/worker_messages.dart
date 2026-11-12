import 'dart:isolate';
import 'dart:typed_data';

import '../backend.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/embedding.dart';
import '../../core/models/inference/reranking.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/generation_usage.dart';
import '../../core/models/inference/next_token_scores.dart';
import '../../core/models/inference/state_identity.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/gpu_device_info.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/diagnostics/model_file_type.dart';
import '../worker_log_message.dart';

export '../worker_log_message.dart';

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

  /// The marker a chat template rendered [prompt] with, or null for a prompt
  /// the caller wrote.
  final String? chatMediaMarker;

  /// Seeds only the penalties sampler from the prompt, even with a grammar.
  final bool countPromptTokensInPenalties;

  /// Creates a new [GenerateRequest].
  GenerateRequest(
    this.contextHandle,
    this.prompt,
    this.params,
    this.cancelTokenAddress,
    super.sendPort, {
    this.parts,
    this.chatMediaMarker,
    this.countPromptTokensInPenalties = false,
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

/// Probe the loaded embedding model and its attached projector.
class EmbeddingCapabilitiesRequest extends WorkerRequest {
  /// Context to probe; unknown contexts report no capabilities.
  final int contextHandle;

  /// Creates a probe request.
  EmbeddingCapabilitiesRequest(this.contextHandle, super.sendPort);
}

/// Ordered content inputs with owned worker media snapshots.
class EmbedContentBatchRequest extends WorkerRequest {
  /// Context to embed with.
  final int contextHandle;

  /// Inputs with adjacent text merged verbatim and copied media buffers.
  final List<LlamaEmbeddingInput> inputs;

  /// Whether to normalize each pooled output.
  final bool normalize;

  /// Shared flag, retained until the worker settles.
  final int cancelTokenAddress;

  /// Creates an owned request without transferring caller buffers.
  EmbedContentBatchRequest(
    this.contextHandle,
    List<LlamaEmbeddingInput> inputs,
    this.normalize,
    this.cancelTokenAddress,
    super.sendPort,
  ) : inputs = [for (final input in inputs) _copyEmbeddingInput(input)];
}

LlamaEmbeddingInput _copyEmbeddingInput(LlamaEmbeddingInput input) {
  final parts = <LlamaContentPart>[];
  for (final part in input.parts) {
    if (part is LlamaTextContent) {
      if (parts.isNotEmpty && parts.last is LlamaTextContent) {
        parts[parts.length - 1] = LlamaTextContent(
          (parts.last as LlamaTextContent).text + part.text,
        );
      } else {
        parts.add(part);
      }
    } else if (part is LlamaImageContent) {
      parts.add(
        LlamaImageContent(
          bytes: part.bytes == null ? null : Uint8List.fromList(part.bytes!),
          path: part.path,
          url: part.url,
          width: part.width,
          height: part.height,
        ),
      );
    } else if (part is LlamaAudioContent) {
      parts.add(
        LlamaAudioContent(
          bytes: part.bytes == null ? null : Uint8List.fromList(part.bytes!),
          samples: part.samples == null
              ? null
              : Float32List.fromList(part.samples!),
          path: part.path,
        ),
      );
    }
  }
  return LlamaEmbeddingInput(parts);
}

/// Loaded-context embedding support, without model sources or media.
class EmbeddingCapabilitiesResponse {
  /// Qualified modalities.
  final LlamaEmbeddingCapabilities capabilities;

  /// Creates a probe response.
  EmbeddingCapabilitiesResponse(this.capabilities);
}

/// Request to score the token that would follow a prompt.
class ScoreNextTokenRequest extends WorkerRequest {
  /// The handle of the context.
  final int contextHandle;

  /// The prompt to evaluate.
  final String prompt;

  /// Token ids to report, in order.
  final List<int> candidates;

  /// How many of the most probable tokens to report.
  final int topK;

  /// Whether a matching prompt prefix in the context is reused.
  final bool reusePromptPrefix;

  /// Creates a new [ScoreNextTokenRequest].
  ScoreNextTokenRequest(
    this.contextHandle,
    this.prompt,
    this.candidates,
    this.topK,
    this.reusePromptPrefix,
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

/// Request to set the level the worker's Dart logger forwards from.
///
/// Ignored, but still answered with [DoneResponse], when the handshake
/// carried no log port.
class DartLogLevelRequest extends WorkerRequest {
  /// The target log level.
  final LlamaLogLevel logLevel;

  /// Creates a new [DartLogLevelRequest].
  DartLogLevelRequest(this.logLevel, super.sendPort);
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

/// Request to probe compiled native video support for a projector.
class SupportsVideoRequest extends WorkerRequest {
  /// The handle of the multimodal context.
  final int mmContextHandle;

  /// Creates a native video capability request.
  SupportsVideoRequest(this.mmContextHandle, super.sendPort);
}

/// Request to discover dedicated native text-to-speech support.
class TextToSpeechCapabilitiesRequest extends WorkerRequest {
  /// Handle of the loaded llama context.
  final int contextHandle;

  /// Handle of the loaded multimodal projector.
  final int mmContextHandle;

  /// Creates a TTS capability request.
  TextToSpeechCapabilitiesRequest(
    this.contextHandle,
    this.mmContextHandle,
    super.sendPort,
  );
}

/// Request for why the runtime cannot drive a text-to-speech model.
class TextToSpeechModelSupportRequest extends WorkerRequest {
  /// The model family to check.
  final BackendTextToSpeechModel model;

  /// Creates a TTS model support request.
  TextToSpeechModelSupportRequest(this.model, super.sendPort);
}

/// Worker response to a [TextToSpeechModelSupportRequest].
class TextToSpeechModelSupportResponse {
  /// Why the runtime cannot drive the model, or null when it can.
  final String? unsupportedReason;

  /// Creates a TTS model support response.
  TextToSpeechModelSupportResponse(this.unsupportedReason);
}

/// Request to synthesize one complete utterance.
class TextToSpeechSynthesizeRequest extends WorkerRequest {
  /// Handle of the loaded llama context.
  final int contextHandle;

  /// Handle of the loaded multimodal projector.
  final int mmContextHandle;

  /// Synthesis inputs and sampling parameters.
  final BackendTextToSpeechRequest request;

  /// Address of the one-byte cancel flag the sender owns.
  ///
  /// The sender sets the byte to nonzero to cancel and keeps it allocated
  /// until this request's terminal response arrives or the worker acknowledges
  /// a [DisposeRequest].
  final int cancelFlagAddress;

  /// Creates a TTS synthesis request.
  TextToSpeechSynthesizeRequest(
    this.contextHandle,
    this.mmContextHandle,
    this.request,
    this.cancelFlagAddress,
    super.sendPort,
  );
}

/// Fire-and-forget request to cancel active native speech synthesis.
class TextToSpeechCancelRequest {}

/// Request for generation controls of a loaded model and runtime bundle.
class GenerationCapabilitiesRequest extends WorkerRequest {
  /// Handle of the loaded model.
  final int modelHandle;

  /// Creates a generation capability request.
  GenerationCapabilitiesRequest(this.modelHandle, super.sendPort);
}

/// Request for decision-model support of a loaded model.
class DecisionCapabilitiesRequest extends WorkerRequest {
  /// Handle of the loaded model.
  final int modelHandle;

  /// Creates a decision capability request.
  DecisionCapabilitiesRequest(this.modelHandle, super.sendPort);
}

/// Request to load a decision head for a loaded model.
class DecisionHeadLoadRequest extends WorkerRequest {
  /// Handle of the loaded encoder model.
  final int modelHandle;

  /// Path to the head's safetensors file.
  final String headPath;

  /// Path to a JSON config for heads without `laya.config` metadata.
  final String? configPath;

  /// Creates a decision head load request.
  DecisionHeadLoadRequest(
    this.modelHandle,
    this.headPath,
    this.configPath,
    super.sendPort,
  );
}

/// Request to run encoder inputs through a loaded decision head.
class DecisionRunRequest extends WorkerRequest {
  /// Handle of the loaded decision head.
  final int headHandle;

  /// Encoder inputs, one per question, in order.
  final List<BackendDecisionSequence> sequences;

  /// Creates a decision run request.
  DecisionRunRequest(this.headHandle, this.sequences, super.sendPort);
}

/// Request to free a decision head; answered with [DoneResponse].
class DecisionHeadFreeRequest extends WorkerRequest {
  /// Handle of the decision head.
  final int headHandle;

  /// Creates a decision head free request.
  DecisionHeadFreeRequest(this.headHandle, super.sendPort);
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

/// Request for the identity of the state [contextHandle] saves and loads.
class StateIdentityRequest extends WorkerRequest {
  /// Context whose state identity to report.
  final int contextHandle;

  /// Creates a new [StateIdentityRequest].
  StateIdentityRequest(this.contextHandle, super.sendPort);
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

/// Worker response containing TTS capabilities.
class TextToSpeechCapabilitiesResponse {
  /// Capability snapshot from the native runtime.
  final BackendTextToSpeechCapabilities capabilities;

  /// Creates a TTS capability response.
  TextToSpeechCapabilitiesResponse(this.capabilities);
}

/// Worker response containing synthesis progress.
class TextToSpeechProgressResponse {
  /// Current native synthesis progress.
  final BackendTextToSpeechProgress progress;

  /// Creates a progress response.
  TextToSpeechProgressResponse(this.progress);
}

/// Worker response containing complete float32 PCM.
class TextToSpeechResultResponse {
  /// Transferable bytes containing float32 PCM in host byte order.
  final TransferableTypedData pcm;

  /// Output sample rate in Hertz.
  final int sampleRateHz;

  /// Number of interleaved channels.
  final int channelCount;

  /// Number of generated audio-codec frames.
  final int framesGenerated;

  /// Whether the requested frame limit was reached.
  final bool truncated;

  /// Creates a final TTS worker response.
  TextToSpeechResultResponse({
    required Float32List samples,
    required this.sampleRateHz,
    required this.channelCount,
    required this.framesGenerated,
    required this.truncated,
  }) : pcm = TransferableTypedData.fromList(<TypedData>[samples]);
}

/// Worker response containing the loaded model's generation controls.
class GenerationCapabilitiesResponse {
  /// Capability snapshot from the native runtime.
  final BackendGenerationCapabilities capabilities;

  /// Creates a generation capability response.
  GenerationCapabilitiesResponse(this.capabilities);
}

/// Worker response containing decision-model support.
class DecisionCapabilitiesResponse {
  /// Capability snapshot from the native runtime.
  final BackendDecisionCapabilities capabilities;

  /// Creates a decision capability response.
  DecisionCapabilitiesResponse(this.capabilities);
}

/// Worker response describing a loaded decision head.
class DecisionHeadLoadResponse {
  /// The loaded head.
  final BackendDecisionHeadInfo head;

  /// Creates a decision head load response.
  DecisionHeadLoadResponse(this.head);
}

/// Worker response containing raw decision-head outputs.
class DecisionRunResponse {
  /// Outputs in request order.
  final List<BackendDecisionOutput> outputs;

  /// Creates a decision run response.
  DecisionRunResponse(this.outputs);
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

/// Response containing next-token scores.
class ScoreNextTokenResponse {
  /// The scores.
  final LlamaNextTokenScores scores;

  /// Creates a new [ScoreNextTokenResponse].
  ScoreNextTokenResponse(this.scores);
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

/// Response from a [StateIdentityRequest].
class StateIdentityResponse {
  /// The identity of the context's state.
  final LlamaStateIdentity identity;

  /// Creates a new [StateIdentityResponse].
  StateIdentityResponse(this.identity);
}

/// Category used to preserve llama.cpp worker failures across isolates.
enum WorkerErrorKind {
  /// An unclassified worker error.
  generic,

  /// The native backend failed during worker startup.
  backendInitialization,

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

  /// Generic speech recognition or processing failed.
  speech,

  /// Speech audio did not satisfy the input format contract.
  audioFormat,

  /// Text-to-speech synthesis failed.
  textToSpeech,

  /// An argument was outside its valid range.
  range,

  /// An argument or parameter combination was invalid.
  argument,

  /// An embedding input exceeds the context or single-pass capacity.
  embeddingInputTooLong,
}

/// Response containing an error message and category.
class ErrorResponse {
  /// The error message.
  final String message;

  /// The category of error reported by the worker.
  final WorkerErrorKind kind;

  /// Creates a new [ErrorResponse].
  ErrorResponse(
    this.message, {
    this.kind = WorkerErrorKind.generic,
    this.maxInputTokens,
    this.actualTokens,
  });

  /// Effective limit for an embedding overflow; null for other errors.
  final int? maxInputTokens;

  /// Exact input size when supplied by the embedding runtime.
  final int? actualTokens;
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
class DoneResponse {
  /// The token limit that ended a generation, or null when none did.
  final BackendGenerationLimit? generationLimit;

  /// The usage of a finished generation, or null for other operations.
  final LlamaGenerationUsage? generationUsage;

  /// Creates a new [DoneResponse].
  DoneResponse({this.generationLimit, this.generationUsage});
}

/// Handshake message sent from main to worker.
class WorkerHandshake {
  /// The initial log level to set before backend initialization.
  final LlamaLogLevel initialLogLevel;

  /// Port that receives [DoneResponse] or an initialization [ErrorResponse].
  final SendPort sendPort;

  /// The main isolate's [LlamaLogger] level at spawn; the worker forwards
  /// only records at or above it.
  final LlamaLogLevel dartLogLevel;

  /// Port that receives [WorkerLogMessage]s; `null` disables forwarding and
  /// leaves the worker's logger untouched.
  final SendPort? logPort;

  /// Empty native owner established by the parent before spawning this worker.
  final int? nativeOwnerToken;

  /// Creates a new [WorkerHandshake].
  WorkerHandshake(
    this.initialLogLevel,
    this.sendPort, {
    this.dartLogLevel = LlamaLogLevel.none,
    this.logPort,
    this.nativeOwnerToken,
  });
}

/// Loaded-context reranking capability request.
class RerankingCapabilitiesRequest extends WorkerRequest {
  /// Creates a capability request.
  RerankingCapabilitiesRequest(this.contextHandle, super.sendPort);

  /// Context to probe.
  final int contextHandle;
}

/// Complete native reranking request with a caller-owned cancellation flag.
class RerankRequest extends WorkerRequest {
  /// Creates a request; the caller retains the flag until the reply or worker exit.
  RerankRequest(
    this.contextHandle,
    this.query,
    this.documents,
    this.cancelTokenAddress,
    super.sendPort,
  );

  /// Loaded context.
  final int contextHandle;

  /// Verbatim query.
  final String query;

  /// Verbatim documents in input order.
  final List<String> documents;

  /// Shared cancellation flag address.
  final int cancelTokenAddress;
}

/// Loaded-context reranking probe response.
class RerankingCapabilitiesResponse {
  /// Creates a response.
  RerankingCapabilitiesResponse(this.capabilities);

  /// Probed capabilities.
  final LlamaRerankingCapabilities capabilities;
}

/// Complete, input-ordered native classifier response.
class RerankResponse {
  /// Creates a response.
  RerankResponse(this.output);

  /// All class outputs and labels.
  final BackendRerankingOutput output;
}

/// Explicit RANK context creation after classifier verification.
class RerankingContextCreateRequest extends WorkerRequest {
  /// Creates a request for the owning reranker loader.
  RerankingContextCreateRequest(this.modelHandle, this.params, super.sendPort);

  /// Loaded model to verify.
  final int modelHandle;

  /// Standard context/device limits, with explicit RANK pooling.
  final ModelParams params;
}
