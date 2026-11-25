import '../../core/models/inference/model_params.dart';
import 'litert_lm_embedding.dart';
import 'litert_lm_runtime.dart';
import 'litert_lm_runtime_client_contract.dart';

/// Keeps the public legacy client and its extension dispatch unchanged while
/// adapting the worker service to a version-specific runtime boundary.
final class LiteRtLmLegacyServiceClient
    implements LiteRtLmRuntimeClientContract {
  /// Wraps the exact client selected by the existing service factory.
  LiteRtLmLegacyServiceClient(
    this._client, {
    int? Function(int)? resolveVisualTokenBudget,
  }) : _resolveVisualTokenBudget = resolveVisualTokenBudget;

  final LiteRtLmRuntimeClient _client;
  final int? Function(int)? _resolveVisualTokenBudget;

  @override
  void configureResponseThinkingTags({
    required String startTag,
    required String endTag,
  }) =>
      _client.configureResponseThinkingTags(startTag: startTag, endTag: endTag);
  @override
  bool get supportsAsrBridge => _client.supportsAsrBridge;
  @override
  bool get supportsSamplingPenalties => _client.supportsSamplingPenalties;
  @override
  bool get supportsThinkingBudget => _client.supportsThinkingBudget;
  @override
  bool get supportsFinishReasons => _client.supportsFinishReasons;
  @override
  bool get supportsJsonSchemaConstraints =>
      _client.supportsJsonSchemaConstraints;
  @override
  bool get supportsJsonSchemaThinking => _client.supportsJsonSchemaThinking;
  @override
  bool get supportsMessageRendering => _client.supportsMessageRendering;
  @override
  int? resolveDefaultVisualTokenBudget(int preferredBudget) =>
      _resolveVisualTokenBudget == null
      ? preferredBudget
      : _resolveVisualTokenBudget(preferredBudget);
  @override
  LiteRtLmFinishReason? get lastFinishReason => _client.lastFinishReason;
  @override
  LiteRtLmNativeSettlement get nativeSettlement => _client.nativeSettlement;
  @override
  ({bool vision, bool audio, bool speculativeDecoding})? bundleCapabilities(
    String modelPath,
  ) => _client.bundleCapabilities(modelPath);
  @override
  LiteRtLmAsrRuntimeSession createAsrSession(LiteRtLmAsrRuntimeConfig config) =>
      _client.createAsrSession(config);
  @override
  Future<LiteRtLmEmbeddingRuntimeSession> createEmbeddingSession({
    required String modelPath,
    required String backend,
    required String cacheDir,
    required int maxInputLength,
    required int numberOfThreads,
  }) => _client.createEmbeddingSession(
    modelPath: modelPath,
    backend: backend,
    cacheDir: cacheDir,
    maxInputLength: maxInputLength,
    numberOfThreads: numberOfThreads,
  );
  @override
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
  }) => _client.initialize(
    modelPath: modelPath,
    backend: backend,
    visionBackend: visionBackend,
    audioBackend: audioBackend,
    maxTokens: maxTokens,
    outputTokens: outputTokens,
    prefillTokens: prefillTokens,
    maxNumImages: maxNumImages,
    cacheDir: cacheDir,
    speculativeDecoding: speculativeDecoding,
    minLogLevel: minLogLevel,
    activationDataType: activationDataType,
    prefillChunkSize: prefillChunkSize,
    parallelFileSectionLoading: parallelFileSectionLoading,
    dispatchLibDir: dispatchLibDir,
    numberOfThreads: numberOfThreads,
  );
  @override
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
  }) => _client.createConversation(
    systemMessage: systemMessage,
    promptTemplate: promptTemplate,
    messages: messages,
    tools: tools,
    extraContext: extraContext,
    temperature: temperature,
    topK: topK,
    topP: topP,
    seed: seed,
    npuBackend: npuBackend,
    loraPath: loraPath,
    jsonSchemaConstraints: jsonSchemaConstraints,
  );
  @override
  void setMinLogLevel(int level) => _client.setMinLogLevel(level);
  @override
  List<int> tokenize(String text, {bool addSpecial = true}) =>
      _client.tokenize(text, addSpecial: addSpecial);
  @override
  String detokenize(List<int> tokens) => _client.detokenize(tokens);
  @override
  String renderMessageToString(Map<String, dynamic> message) =>
      _client.renderMessageToString(message);
  @override
  Stream<String> generate(
    String prompt, {
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
  }) => _client.generate(
    prompt,
    maxOutputTokens: maxOutputTokens,
    repetitionPenalty: repetitionPenalty,
    presencePenalty: presencePenalty,
  );
  @override
  Stream<String> generateMessageJson(
    String messageJson, {
    Map<String, dynamic>? extraContext,
    int? visualTokenBudget,
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
    int? thinkingTokenBudget,
    String? jsonSchema,
  }) => _client.generateMessageJson(
    messageJson,
    extraContext: extraContext,
    visualTokenBudget: visualTokenBudget,
    maxOutputTokens: maxOutputTokens,
    repetitionPenalty: repetitionPenalty,
    presencePenalty: presencePenalty,
    thinkingTokenBudget: thinkingTokenBudget,
    jsonSchema: jsonSchema,
  );
  @override
  Future<LiteRtLmRuntimeResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,
  }) => _client.run(
    prompt: prompt,
    warmupRuns: warmupRuns,
    measuredRuns: measuredRuns,
  );
  @override
  LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds}) =>
      _client.readMetrics(wallMilliseconds: wallMilliseconds);
  @override
  void cancel() => _client.cancel();
  @override
  void dispose() => _client.dispose();
}
