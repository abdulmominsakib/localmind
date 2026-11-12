import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_embedding.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_sampler_params.dart';

/// Records the actual settled conversation immediately before its native send.
/// Delegation preserves production serialization, settings and lifecycle.
final class ThinkingInputObserver implements LiteRtLmRuntimeClientContract {
  ThinkingInputObserver(this._client, this.onSend);
  final LiteRtLmRuntimeClientContract _client;
  final void Function(Map<String, Object?> input) onSend;
  Map<String, Object?>? _conversation;
  Map<String, Object?>? _engine;

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
      _client.resolveDefaultVisualTokenBudget(preferredBudget);
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
  }) async {
    await _client.initialize(
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
    _engine = {
      'backend': backend,
      'vision': visionBackend,
      'audio': audioBackend,
      'context': maxTokens,
      'default_output': outputTokens,
      'threads': numberOfThreads,
      'speculation': speculativeDecoding,
      'prefill_tokens': prefillTokens,
      'prefill_chunk': prefillChunkSize,
      'parallel_sections': parallelFileSectionLoading,
      'activation_type': activationDataType?.name,
      'dispatch': dispatchLibDir,
      'history_image_hint': maxNumImages,
    };
  }

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
  }) {
    _client.createConversation(
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
    _conversation =
        jsonDecode(
              jsonEncode({
                'temperature': temperature,
                'top_k': liteRtLmEffectiveTopK(
                  temperature: temperature,
                  topK: topK,
                ),
                'top_p': topP,
                'seed': seed,
                'extra_context': extraContext,
                'messages': messages,
                'tools': tools,
                'system': systemMessage,
                'template_sha256': promptTemplate == null
                    ? null
                    : sha256.convert(utf8.encode(promptTemplate)).toString(),
                'npu': npuBackend,
                'lora': loraPath,
                'schema': jsonSchemaConstraints,
              }),
            )
            as Map<String, dynamic>;
  }

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
  }) {
    final configured = _conversation;
    if (configured == null) throw StateError('No configured conversation.');
    final rendered = _client.renderMessageToString(
      jsonDecode(messageJson) as Map<String, dynamic>,
    );
    final bytes = utf8.encode(rendered);
    final ids = _client.tokenize(rendered, addSpecial: false);
    final withStartIds = _client.tokenize(rendered, addSpecial: true);
    onSend({
      'message_json': messageJson,
      'engine_after_successful_status_checks': _engine,
      'effective_settings_evidence':
          'Values passed through production setters after successful status checks; native configuration readback is unavailable. Per-send overrides below are requested until the turn succeeds.',
      'conversation_after_successful_status_checks': configured,
      'per_send_context': extraContext,
      'requested_max_output_tokens': maxOutputTokens,
      'requested_repetition_penalty_override': repetitionPenalty,
      'requested_presence_penalty_override': presencePenalty,
      'requested_thinking_budget': thinkingTokenBudget,
      'requested_visual_budget': visualTokenBudget,
      'requested_json_schema': jsonSchema,
      'rendered_prompt': rendered,
      'rendered_prompt_utf8_hex': bytes
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join(),
      'rendered_prompt_sha256': sha256.convert(bytes).toString(),
      'rendered_prompt_native_token_ids_without_added_start': ids,
      'rendered_prompt_native_token_count_without_added_start': ids.length,
      'rendered_prompt_native_token_ids_with_start': withStartIds,
      'rendered_prompt_native_token_count_with_start': withStartIds.length,
      'input_evidence_scope':
          'Native template rendering and direct tokenizer before send; excludes any native start token, modality processing or post-generation KV refill.',
    });
    return _client.generateMessageJson(
      messageJson,
      extraContext: extraContext,
      visualTokenBudget: visualTokenBudget,
      maxOutputTokens: maxOutputTokens,
      repetitionPenalty: repetitionPenalty,
      presencePenalty: presencePenalty,
      thinkingTokenBudget: thinkingTokenBudget,
      jsonSchema: jsonSchema,
    );
  }

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
