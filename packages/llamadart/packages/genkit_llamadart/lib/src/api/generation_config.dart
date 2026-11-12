import 'package:llamadart/llamadart.dart' as llama;

import 'config_parsing.dart';
import 'generation_controls_codec.dart';

/// Sampling and chat-template options for a Genkit model request.
///
/// Null fields use the adapter defaults when a request executes. Backend and
/// model restrictions still apply; these options cannot enable an unsupported
/// capability. [toJson] omits null fields for Genkit configuration maps.
///
/// ```dart
/// final response = await ai.generate(
///   model: llamaDart.model('local-chat'),
///   prompt: 'Summarize this in one line.',
///   config: const LlamaDartGenerationConfig(
///     temperature: 0.2,
///     maxTokens: 128,
///     enableThinking: false,
///   ),
/// );
/// ```
class LlamaDartGenerationConfig {
  /// Default sampling temperature.
  static const double defaultTemperature = 0.8;

  /// Default nucleus sampling value.
  static const double defaultTopP = 0.9;

  /// Default top-k sampling value.
  static const int defaultTopK = 40;

  /// Default minimum probability cutoff.
  static const double defaultMinP = 0.0;

  /// Default repetition penalty.
  static const double defaultPenalty = 1.1;

  /// Default maximum generated tokens.
  static const int defaultMaxTokens = 4096;

  /// Whether thinking is enabled when the request omits [enableThinking].
  static const bool defaultEnableThinking = false;

  /// Default parallel tool-call behavior.
  static const bool defaultParallelToolCalls = false;

  /// Creates a generation config.
  const LlamaDartGenerationConfig({
    this.temperature,
    this.topP,
    this.topK,
    this.minP,
    this.penalty,
    this.maxTokens,
    this.presencePenalty,
    this.thinkingBudget,
    this.speculativeDecoding,
    this.speculativeDecodingConfig,
    this.reusePromptPrefix,
    this.streamBatchTokenThreshold,
    this.streamBatchByteThreshold,
    this.stop,
    this.seed,
    this.enableThinking,
    this.parallelToolCalls,
    this.sourceLangCode,
    this.targetLangCode,
    this.chatTemplateKwargs,
  });

  /// Reads recognized fields from a Genkit config map.
  ///
  /// Null maps produce an empty config. Numeric values are converted to the
  /// required numeric type for existing sampling fields; those integer fields
  /// truncate fractional numbers.
  /// Non-numeric sampling values, non-boolean flags and mixed-type stop lists
  /// become null. Language hints must be strings and template keys must be
  /// strings; incompatible values can throw [TypeError]. Unknown keys are
  /// ignored. New inference controls reject malformed values with
  /// [FormatException], without including supplied values in diagnostics.
  factory LlamaDartGenerationConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const LlamaDartGenerationConfig();
    }

    return LlamaDartGenerationConfig(
      temperature: asDouble(json['temperature']),
      topP: asDouble(json['topP']),
      topK: asInt(json['topK']),
      minP: asDouble(json['minP']),
      penalty: asDouble(json['penalty']),
      presencePenalty: controlDouble(json, 'presencePenalty'),
      thinkingBudget: thinkingBudgetFromJson(json['thinkingBudget']),
      speculativeDecoding: controlBool(json, 'speculativeDecoding'),
      speculativeDecodingConfig: speculativeConfigFromJson(
        json['speculativeDecodingConfig'],
      ),
      reusePromptPrefix: controlBool(json, 'reusePromptPrefix'),
      streamBatchTokenThreshold: controlInt(
        json,
        'streamBatchTokenThreshold',
        minimum: 1,
      ),
      streamBatchByteThreshold: controlInt(
        json,
        'streamBatchByteThreshold',
        minimum: 1,
      ),
      maxTokens: asInt(json['maxTokens']),
      stop: asStringList(json['stop']),
      seed: asInt(json['seed']),
      enableThinking: asBool(json['enableThinking']),
      parallelToolCalls: asBool(json['parallelToolCalls']),
      sourceLangCode: json['sourceLangCode'] as String?,
      targetLangCode: json['targetLangCode'] as String?,
      chatTemplateKwargs: asStringDynamicMap(json['chatTemplateKwargs']),
    );
  }

  /// Sampling temperature; lower values favor more predictable output.
  ///
  /// Null uses [defaultTemperature].
  final double? temperature;

  /// Cumulative probability cutoff for nucleus sampling.
  ///
  /// Null uses [defaultTopP].
  final double? topP;

  /// Maximum number of candidate tokens considered by top-k sampling.
  ///
  /// Null uses [defaultTopK].
  final int? topK;

  /// Minimum token probability relative to the most likely candidate.
  ///
  /// Null uses [defaultMinP], which disables this cutoff.
  final double? minP;

  /// Repetition penalty applied to previously generated tokens.
  ///
  /// Null uses [defaultPenalty].
  final double? penalty;

  /// Additive presence penalty; null or zero disables it.
  ///
  /// Requires the loaded runtime to report presence-penalty support. Unlike
  /// [penalty], this adds a fixed penalty rather than scaling repeated logits.
  final double? presencePenalty;

  /// Maximum reasoning tokens per block; null leaves reasoning unbudgeted.
  ///
  /// This does not enable thinking: set [enableThinking] for the model's
  /// template. Omitted delimiters are resolved from the selected template in
  /// chat and constrained JSON. Media and speculative decoding cannot be
  /// combined with a budget. Requires runtime thinking-budget support.
  final llama.ThinkingBudget? thinkingBudget;

  /// Enables the backend's default speculative strategy; null defaults false.
  ///
  /// Prefer [speculativeDecodingConfig] to select a strategy. A non-null typed
  /// config takes precedence, including when this flag is false.
  final bool? speculativeDecoding;

  /// Backend-native speculative strategy and tuning; null disables it unless
  /// [speculativeDecoding] is true.
  ///
  /// Every selected strategy must be reported by the loaded runtime. The core
  /// runtime validates model-specific tuning. Constrained JSON, active tools,
  /// media and thinking budgets cannot be combined with speculation.
  /// JSON uses enum names and nested source/download objects. Authenticated or
  /// signed draft sources must be downloaded outside the request first:
  /// [toJson] rejects credentials and cancellation tokens to keep them out of
  /// Genkit request traces. Deprecated draft paths are rejected as well.
  final llama.SpeculativeDecodingConfig? speculativeDecodingConfig;

  /// Whether native text generation reuses matching prompt prefixes.
  ///
  /// Null defaults true. This is an optimization, not a conversational session;
  /// send the full history on every request. Disabling reuse requires confirmed
  /// native llama.cpp; Web and LiteRT-LM cannot confirm this control.
  final bool? reusePromptPrefix;

  /// Native worker flush threshold in token pieces; null defaults to 8.
  ///
  /// Must be positive. Lower values improve granularity at the cost of message
  /// overhead. Nondefault values require stream-batching support.
  final int? streamBatchTokenThreshold;

  /// Native worker flush threshold in bytes; null defaults to 512.
  ///
  /// Must be positive. Nondefault values require stream-batching support.
  final int? streamBatchByteThreshold;

  /// Maximum number of generated tokens, excluding the input prompt.
  ///
  /// Null uses [defaultMaxTokens]. Reaching the limit can leave structured
  /// output incomplete; inspect the final Genkit result.
  final int? maxTokens;

  /// Additional strings that stop generation when encountered.
  ///
  /// Structured output also preserves stop sequences supplied by the template.
  final List<String>? stop;

  /// Sampling seed, when supported by the active backend.
  ///
  /// Reproducibility also depends on the model, backend and sampling settings.
  final int? seed;

  /// Whether the chat template enables model thinking.
  ///
  /// Null uses [defaultEnableThinking]. This controls model/template behavior,
  /// rather than merely hiding reasoning parts in the response.
  final bool? enableThinking;

  /// Whether the chat template permits multiple tool calls in one turn.
  ///
  /// Null uses [defaultParallelToolCalls]. Tool execution remains owned by Genkit.
  final bool? parallelToolCalls;

  /// Source language hint for translation-style chat templates.
  ///
  /// A nonempty value overrides `source_lang_code` in [chatTemplateKwargs].
  final String? sourceLangCode;

  /// Target language hint for translation-style chat templates.
  ///
  /// A nonempty value overrides `target_lang_code` in [chatTemplateKwargs].
  final String? targetLangCode;

  /// Extra globals supplied to the model's chat template.
  ///
  /// Accepted keys and effects depend on the template. Nonempty
  /// [sourceLangCode] and [targetLangCode] take precedence over matching keys.
  final Map<String, dynamic>? chatTemplateKwargs;

  /// Serializes the config to a Genkit-friendly map.
  ///
  /// Throws [FormatException] for invalid new controls or speculative draft
  /// settings that cannot safely be represented in request traces.
  Map<String, dynamic> toJson() {
    validateGenerationControls(
      presencePenalty: presencePenalty,
      streamBatchTokenThreshold: streamBatchTokenThreshold,
      streamBatchByteThreshold: streamBatchByteThreshold,
    );
    return {
      if (presencePenalty != null) 'presencePenalty': presencePenalty,
      if (thinkingBudget != null)
        'thinkingBudget': thinkingBudgetToJson(thinkingBudget!),
      if (speculativeDecoding != null)
        'speculativeDecoding': speculativeDecoding,
      if (speculativeDecodingConfig != null)
        'speculativeDecodingConfig': speculativeConfigToJson(
          speculativeDecodingConfig!,
        ),
      if (reusePromptPrefix != null) 'reusePromptPrefix': reusePromptPrefix,
      if (streamBatchTokenThreshold != null)
        'streamBatchTokenThreshold': streamBatchTokenThreshold,
      if (streamBatchByteThreshold != null)
        'streamBatchByteThreshold': streamBatchByteThreshold,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (topK != null) 'topK': topK,
      if (minP != null) 'minP': minP,
      if (penalty != null) 'penalty': penalty,
      if (maxTokens != null) 'maxTokens': maxTokens,
      if (stop != null) 'stop': stop,
      if (seed != null) 'seed': seed,
      if (enableThinking != null) 'enableThinking': enableThinking,
      if (parallelToolCalls != null) 'parallelToolCalls': parallelToolCalls,
      if (sourceLangCode != null) 'sourceLangCode': sourceLangCode,
      if (targetLangCode != null) 'targetLangCode': targetLangCode,
      if (chatTemplateKwargs != null) 'chatTemplateKwargs': chatTemplateKwargs,
    };
  }
}
