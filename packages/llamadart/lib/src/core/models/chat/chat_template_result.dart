/// The result of applying a chat template to a conversation history.
class LlamaChatTemplateResult {
  /// The formatted prompt string ready for inference.
  final String prompt;

  /// The detected chat format code (corresponds to common_chat_format enum).
  /// Defaults to 0 (content-only format) if not specified.
  final int format;

  /// GBNF grammar string for constraining model output (e.g., for tool calls).
  final String? grammar;

  /// Whether grammar should be lazily applied (triggered by specific tokens).
  final bool grammarLazy;

  /// Whether thinking mode is forced open.
  final bool thinkingForcedOpen;

  /// Additional stop sequences from the template.
  final List<String> additionalStops;

  /// Tokens that should be preserved during grammar constraining.
  final List<String> preservedTokens;

  /// Grammar triggers that activate the grammar constraint.
  final List<GrammarTrigger> grammarTriggers;

  /// PEG parser string if applicable.
  final String? parser;

  /// The number of tokens in the formatted prompt.
  final int? tokenCount;

  /// Creates a new template result.
  const LlamaChatTemplateResult({
    required this.prompt,
    this.format = 0,
    this.grammar,
    this.grammarLazy = false,
    this.thinkingForcedOpen = false,
    this.additionalStops = const [],
    this.preservedTokens = const [],
    this.grammarTriggers = const [],
    this.parser,
    this.tokenCount,
  });

  /// Creates a template result from a JSON map (from native).
  factory LlamaChatTemplateResult.fromJson(Map<String, dynamic> json) {
    return LlamaChatTemplateResult(
      prompt: json['prompt'] as String? ?? '',
      format: json['format'] as int? ?? 0,
      grammar: json['grammar'] as String?,
      grammarLazy: json['grammar_lazy'] as bool? ?? false,
      thinkingForcedOpen: json['thinking_forced_open'] as bool? ?? false,
      additionalStops:
          (json['additional_stops'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      preservedTokens:
          (json['preserved_tokens'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      grammarTriggers:
          (json['grammar_triggers'] as List<dynamic>?)
              ?.map((e) => GrammarTrigger.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      parser: json['parser'] as String?,
    );
  }

  /// Legacy getter for backwards compatibility.
  List<String> get stopSequences => additionalStops;
}

/// A trigger that activates grammar constraints.
class GrammarTrigger {
  /// The type of trigger (0=word, 1=token, 2=pattern, 3=pattern_full).
  final int type;

  /// The trigger value (word, token string, or regex pattern).
  final String value;

  /// The token ID if type is token.
  final int? token;

  /// Creates a new grammar trigger.
  const GrammarTrigger({required this.type, required this.value, this.token});

  /// Creates a grammar trigger from a JSON map.
  factory GrammarTrigger.fromJson(Map<String, dynamic> json) {
    return GrammarTrigger(
      type: json['type'] as int? ?? 0,
      value: json['value'] as String? ?? '',
      token: json['token'] as int?,
    );
  }
}
