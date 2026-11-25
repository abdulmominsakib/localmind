// coverage:ignore-file

import '../../core/models/inference/model_params.dart';
import 'litert_lm_asr_types.dart';
import 'litert_lm_finish_reason.dart';
import 'litert_lm_native_settlement.dart';

export 'litert_lm_asr_types.dart';
export 'litert_lm_finish_reason.dart';
export 'litert_lm_native_settlement.dart';

/// Runtime metrics shape shared with the native LiteRT-LM implementation.
class LiteRtLmRuntimeMetrics {
  /// Number of prompt/input tokens.
  final int inputTokens;

  /// Number of generated/output tokens.
  final int outputTokens;

  /// Time to first token in seconds, when reported by LiteRT-LM.
  final double? timeToFirstTokenSeconds;

  /// Engine initialization time in seconds, when reported by LiteRT-LM.
  final double? initSeconds;

  /// Prompt prefill throughput in tokens per second.
  final double? prefillTokensPerSecond;

  /// Decode throughput in tokens per second.
  final double? decodeTokensPerSecond;

  /// Wall-clock runtime measured by Dart.
  final int wallMilliseconds;

  /// Creates runtime metrics.
  const LiteRtLmRuntimeMetrics({
    required this.inputTokens,
    required this.outputTokens,
    required this.timeToFirstTokenSeconds,
    required this.initSeconds,
    required this.prefillTokensPerSecond,
    required this.decodeTokensPerSecond,
    required this.wallMilliseconds,
  });

  /// Converts metrics to JSON-compatible values.
  Map<String, Object?> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'timeToFirstTokenSeconds': timeToFirstTokenSeconds,
    'initSeconds': initSeconds,
    'prefillTokensPerSecond': prefillTokensPerSecond,
    'decodeTokensPerSecond': decodeTokensPerSecond,
    'wallMilliseconds': wallMilliseconds,
  };
}

/// Generated text and runtime metrics from a LiteRT-LM run.
class LiteRtLmRuntimeResult {
  /// Generated text.
  final String text;

  /// Runtime metrics.
  final LiteRtLmRuntimeMetrics metrics;

  /// Creates a runtime result.
  const LiteRtLmRuntimeResult({required this.text, required this.metrics});
}

/// Web-safe placeholder for the native-only runtime client.
class LiteRtLmRuntimeClient {
  /// Creates a placeholder client on platforms without `dart:ffi`.
  LiteRtLmRuntimeClient({String? libraryPath}) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Configures how LiteRT-LM thought-channel chunks are exposed to parsers.
  void configureResponseThinkingTags({
    required String startTag,
    required String endTag,
  }) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// No native family exists on this unsupported platform.
  LiteRtLmNativeSettlement get nativeSettlement =>
      LiteRtLmNativeSettlement.settled;

  /// Dedicated native ASR is unavailable without `dart:ffi`.
  bool get supportsAsrBridge => false;

  /// Sampling penalties are unavailable without `dart:ffi`.
  bool get supportsSamplingPenalties => false;

  /// Thinking budgets are unavailable without `dart:ffi`.
  bool get supportsThinkingBudget => false;

  /// JSON Schema constraints require the native runtime.
  bool get supportsJsonSchemaConstraints => false;

  /// JSON Schema constraints require the native runtime.
  bool get supportsJsonSchemaThinking => false;

  /// Finish reasons are unavailable without `dart:ffi`.
  bool get supportsFinishReasons => false;

  /// Finish reasons are unavailable without `dart:ffi`.
  LiteRtLmFinishReason? get lastFinishReason => null;

  /// Bundle capability queries are unavailable without `dart:ffi`.
  ({bool vision, bool audio, bool speculativeDecoding})? bundleCapabilities(
    String modelPath,
  ) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Dedicated native ASR is unavailable without `dart:ffi`.
  LiteRtLmAsrRuntimeSession createAsrSession(LiteRtLmAsrRuntimeConfig config) {
    throw UnsupportedError('LiteRT-LM ASR requires a native platform.');
  }

  /// Initializes the native LiteRT-LM engine.
  ///
  /// [outputTokens] is the fallback per-request output limit, not a benchmark
  /// decode-step count.
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
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Updates the native LiteRT-LM log level.
  void setMinLogLevel(int level) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Creates a conversation for generation/token operations.
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
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Tokenizes text with the native LiteRT-LM tokenizer.
  List<int> tokenize(String text, {bool addSpecial = true}) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Converts native LiteRT-LM token ids back to text.
  String detokenize(List<int> tokens) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Streams generated text from the active conversation.
  Stream<String> generate(
    String prompt, {
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
  }) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Streams generated text from a native message JSON object.
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
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Whether a runtime is loaded and provides the entry point of
  /// [renderMessageToString].
  bool get supportsMessageRendering =>
      throw UnsupportedError('LiteRT-LM runtime requires a native platform.');

  /// Renders a message with the active native conversation template.
  String renderMessageToString(Map<String, dynamic> message) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Runs a benchmark-style prompt loop and returns runtime metrics.
  Future<LiteRtLmRuntimeResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,
  }) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Reads runtime metrics for the active conversation.
  LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds}) {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Cancels active native generation.
  void cancel() {
    throw UnsupportedError('LiteRT-LM runtime requires a native platform.');
  }

  /// Releases native LiteRT-LM resources.
  void dispose() {}
}
