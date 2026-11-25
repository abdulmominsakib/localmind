import '../../core/exceptions.dart';
import '../../core/models/inference/model_params.dart';
import 'litert_lm_asr_types.dart';
import 'litert_lm_embedding.dart';
import 'litert_lm_finish_reason.dart';
import 'litert_lm_native_settlement.dart';
import 'litert_lm_runtime.dart' as legacy;

/// A native send call that failed before any stream began, so the runtime
/// rejected the request itself (a chat template that fails to render shows up
/// here), as opposed to a failure the stream reports later, such as an input
/// that exceeds the context.
final class LiteRtLmSendFailureException extends LlamaModelException {
  /// Creates a send failure with [message].
  LiteRtLmSendFailureException(super.message, [super.details]);
}

/// Internal service boundary; each native ABI implements every operation rather
/// than inheriting calls that may have a different arity or ownership contract.
abstract interface class LiteRtLmRuntimeClientContract {
  /// Configures parser-facing reasoning markers without enabling native thinking.
  void configureResponseThinkingTags({
    required String startTag,
    required String endTag,
  });

  /// Whether the actual runtime provides the admitted dedicated ASR bridge.
  bool get supportsAsrBridge;

  /// Whether the runtime can apply per-send generated-token penalties.
  bool get supportsSamplingPenalties;

  /// Whether a requested thinking budget can be enforced, rather than ignored.
  bool get supportsThinkingBudget;

  /// Whether the admitted callback bridge reports native terminal causes.
  bool get supportsFinishReasons;

  /// Whether the admitted runtime can enforce native chat schemas.
  bool get supportsJsonSchemaConstraints;

  /// Whether schema constraints can follow an enabled reasoning channel,
  /// rather than forcing thinking off.
  bool get supportsJsonSchemaThinking;

  /// Whether native message rendering is available on the selected runtime.
  bool get supportsMessageRendering;

  /// Resolves the service's automatic image-preprocessing hint for this model.
  /// This is separate from an explicitly requested per-send visual constraint.
  int? resolveDefaultVisualTokenBudget(int preferredBudget);

  /// Terminal native cause of the latest completed turn, or null while pending.
  LiteRtLmFinishReason? get lastFinishReason;

  /// Native callback/handle lifetime, independent of Dart request completion.
  LiteRtLmNativeSettlement get nativeSettlement;

  /// Returns model-file declarations without creating an engine, or null if unavailable.
  ({bool vision, bool audio, bool speculativeDecoding})? bundleCapabilities(
    String modelPath,
  );

  /// Creates a dedicated, owned ASR session after bridge admission.
  LiteRtLmAsrRuntimeSession createAsrSession(LiteRtLmAsrRuntimeConfig config);

  /// Creates an owned embedding engine with independent version-specific bindings.
  Future<LiteRtLmEmbeddingRuntimeSession> createEmbeddingSession({
    required String modelPath,
    required String backend,
    required String cacheDir,
    required int maxInputLength,
    required int numberOfThreads,
  });

  /// Loads the configured engine; the service owns cache leases and backend selection.
  Future<void> initialize({
    required String modelPath,
    String backend = 'gpu',
    String? visionBackend,
    String? audioBackend,
    int maxTokens = 4096,
    int outputTokens = 256,
    int? prefillTokens,
    // History-derived preparation hint, not an enforced image capacity.
    int? maxNumImages,
    String? cacheDir,
    bool speculativeDecoding = true,
    int minLogLevel = 3,
    LiteRtLmActivationDataType? activationDataType,
    int? prefillChunkSize,
    bool? parallelFileSectionLoading,
    String? dispatchLibDir,
    int? numberOfThreads,
  });

  /// Replaces a settled conversation with snapshotted native preface and sampling.
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
  });

  /// Updates the native logging threshold on the selected library.
  void setMinLogLevel(int level);

  /// Copies token IDs, optionally prepending the configured start tokens.
  List<int> tokenize(String text, {bool addSpecial = true});

  /// Copies native UTF-8 decoded from the given token IDs.
  String detokenize(List<int> tokens);

  /// Copies the native template rendering of a supported message.
  String renderMessageToString(Map<String, dynamic> message);

  /// Streams a plain user prompt through the active conversation.
  Stream<String> generate(
    String prompt, {
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
  });

  /// Streams a structured native message with explicitly supported per-send controls.
  Stream<String> generateMessageJson(
    String messageJson, {
    Map<String, dynamic>? extraContext,
    int? visualTokenBudget,
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
    int? thinkingTokenBudget,
    String? jsonSchema,
  });

  /// Runs benchmark-style prompt loops and returns the final text and metrics.
  Future<legacy.LiteRtLmRuntimeResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,
  });

  /// Copies benchmark metrics from a settled conversation.
  legacy.LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds});

  /// Requests cancellation without claiming that native callbacks have settled.
  void cancel();

  /// Releases only settled native owners; failure must preserve quarantine.
  void dispose();
}
