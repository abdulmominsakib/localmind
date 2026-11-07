/// Parameters controlling the token sampling and generation process.
///
/// Use [GenerationParams] to fine-tune how the model generates text, including
/// randomness (temperature), sampling constraints (Top-K/Top-P), and
/// architectural limits (max tokens).
///
/// Example:
/// ```dart
/// final params = GenerationParams(
///   temp: 0.7,
///   maxTokens: 1024,
///   stopSequences: ['User:', '\n\n'],
///   grammar: 'root ::= "yes" | "no"', // Force binary response
/// );
/// ```
/// Lazy grammar activation trigger.
class GenerationGrammarTrigger {
  /// Trigger type (0=word, 1=token, 2=pattern, 3=pattern_full).
  final int type;

  /// Trigger text value.
  final String value;

  /// Trigger token id for token-based triggers.
  final int? token;

  /// Creates a new grammar trigger.
  const GenerationGrammarTrigger({
    required this.type,
    required this.value,
    this.token,
  });
}

/// Backend-neutral speculative decoding strategy.
enum SpeculativeDecodingStrategy {
  /// Let the selected backend choose its native speculative decoding mode.
  backendDefault,

  /// Multi-token prediction.
  ///
  /// llama.cpp maps this to its `draft-mtp` speculative path. LiteRT-LM native
  /// currently maps this to its runtime speculative decoding switch.
  mtp,

  /// Self-speculative n-gram pattern matching.
  ///
  /// llama.cpp maps this to its `ngram-simple` path. It uses token history
  /// rather than a separate draft model.
  ngramSimple,

  /// Standalone draft-model speculative decoding.
  draftSimple,

  /// EAGLE-3 draft-model speculative decoding.
  draftEagle3,

  /// DFlash block-diffusion draft-model speculative decoding.
  draftDflash,

  /// Self-speculative n-gram map with key-only lookup.
  ngramMapK,

  /// Self-speculative n-gram map with up to four values per key.
  ngramMapK4v,

  /// Self-speculative n-gram hasher with a shared token pool.
  ngramMod,

  /// Self-speculative three-level n-gram cache.
  ngramCache,
}

/// Backend-neutral speculative decoding configuration.
///
/// Backends map the strategy and knobs they support to their native runtime.
/// Unsupported strategy/option combinations must fail explicitly instead of
/// silently falling back.
class SpeculativeDecodingConfig {
  /// Strategy to use when speculative decoding is enabled.
  ///
  /// For single-strategy configs this mirrors [strategies].first. For mixed
  /// llama.cpp configs, use [strategies].
  final SpeculativeDecodingStrategy strategy;

  /// Ordered speculative decoding strategies to enable.
  ///
  /// llama.cpp follows upstream `--spec-type` semantics: draftless n-gram
  /// strategies can be mixed with one draft-model strategy. Other backends may
  /// reject mixed strategy sets until they expose equivalent controls.
  final List<SpeculativeDecodingStrategy> strategies;

  /// Maximum number of draft tokens to propose per speculative step.
  ///
  /// llama.cpp draft-model strategies map this to upstream
  /// `--spec-draft-n-max`. Draftless `ngram-simple`, `ngram-map-k`, and
  /// `ngram-map-k4v` use [ngramSizeM] as their effective draft length instead,
  /// matching upstream n-gram map semantics.
  ///
  /// `null` lets the backend choose its default.
  final int? draftTokenMax;

  /// Minimum number of draft tokens required for speculative verification.
  ///
  /// `null` lets the backend choose its default.
  final int? draftTokenMin;

  /// Minimum draft-token probability accepted by the backend.
  ///
  /// `null` lets the backend choose its default.
  final double? minProbability;

  /// Split probability for draft-model speculative decoding.
  ///
  /// `null` lets the backend choose its default.
  final double? draftSplitProbability;

  /// Optional draft model path for speculative decoding modes that use a
  /// separate drafter model, such as llama.cpp `--model-draft` with
  /// `draft-simple`, `draft-eagle3`, `draft-mtp`, or `draft-dflash`.
  ///
  /// Leave null for models that carry their own MTP layers.
  final String? draftModelPath;

  /// Lookup n-gram size for n-gram self-speculative decoding.
  ///
  /// Alias for [ngramSizeN] retained for source compatibility with the first
  /// ngram-simple API. New code should prefer [ngramSizeN].
  final int? ngramSize;

  /// Lookup n-gram size N for upstream n-gram speculative strategies.
  final int? ngramSizeN;

  /// Draft m-gram size M for ngram-simple/map strategies.
  ///
  /// For llama.cpp `ngram-simple`, `ngram-map-k`, and `ngram-map-k4v`, this is
  /// also the effective draft length passed to the n-gram strategy.
  final int? ngramSizeM;

  /// Minimum number of matching hits for ngram-simple/map strategies.
  final int? ngramMinHits;

  /// Lookup length for ngram-mod.
  final int? ngramMatch;

  /// Minimum accepted draft length for ngram-mod.
  final int? ngramTokenMin;

  /// Maximum draft length for ngram-mod.
  final int? ngramTokenMax;

  /// Optional static n-gram cache path for ngram-cache.
  final String? ngramCacheStaticPath;

  /// Optional dynamic n-gram cache path for ngram-cache.
  final String? ngramCacheDynamicPath;

  /// Creates a backend-neutral speculative decoding configuration.
  const SpeculativeDecodingConfig({
    this.strategy = SpeculativeDecodingStrategy.backendDefault,
    this.strategies = const [],
    this.draftTokenMax,
    this.draftTokenMin,
    this.minProbability,
    this.draftSplitProbability,
    this.draftModelPath,
    this.ngramSize,
    this.ngramSizeN,
    this.ngramSizeM,
    this.ngramMinHits,
    this.ngramMatch,
    this.ngramTokenMin,
    this.ngramTokenMax,
    this.ngramCacheStaticPath,
    this.ngramCacheDynamicPath,
  }) : assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(draftTokenMin == null || draftTokenMin >= 0),
       assert(ngramSize == null || ngramSize > 0),
       assert(ngramSizeN == null || ngramSizeN > 0),
       assert(ngramSizeM == null || ngramSizeM > 0),
       assert(ngramMinHits == null || ngramMinHits > 0),
       assert(ngramMatch == null || ngramMatch > 0),
       assert(ngramTokenMin == null || ngramTokenMin >= 0),
       assert(ngramTokenMax == null || ngramTokenMax >= 0),
       assert(
         minProbability == null ||
             (minProbability >= 0.0 && minProbability <= 1.0),
       ),
       assert(
         draftSplitProbability == null ||
             (draftSplitProbability >= 0.0 && draftSplitProbability <= 1.0),
       );

  /// Enables the backend's default speculative decoding behavior.
  const SpeculativeDecodingConfig.backendDefault()
    : strategy = SpeculativeDecodingStrategy.backendDefault,
      strategies = const [SpeculativeDecodingStrategy.backendDefault],
      draftTokenMax = null,
      draftTokenMin = null,
      minProbability = null,
      draftSplitProbability = null,
      draftModelPath = null,
      ngramSize = null,
      ngramSizeN = null,
      ngramSizeM = null,
      ngramMinHits = null,
      ngramMatch = null,
      ngramTokenMin = null,
      ngramTokenMax = null,
      ngramCacheStaticPath = null,
      ngramCacheDynamicPath = null;

  /// Enables multi-token prediction speculative decoding.
  const SpeculativeDecodingConfig.mtp({
    this.draftTokenMax,
    this.draftTokenMin,
    this.minProbability,
    this.draftSplitProbability,
    this.draftModelPath,
  }) : strategy = SpeculativeDecodingStrategy.mtp,
       strategies = const [SpeculativeDecodingStrategy.mtp],
       ngramSize = null,
       ngramSizeN = null,
       ngramSizeM = null,
       ngramMinHits = null,
       ngramMatch = null,
       ngramTokenMin = null,
       ngramTokenMax = null,
       ngramCacheStaticPath = null,
       ngramCacheDynamicPath = null,
       assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(draftTokenMin == null || draftTokenMin >= 0),
       assert(
         minProbability == null ||
             (minProbability >= 0.0 && minProbability <= 1.0),
       ),
       assert(
         draftSplitProbability == null ||
             (draftSplitProbability >= 0.0 && draftSplitProbability <= 1.0),
       );

  /// Enables standalone draft-model speculative decoding.
  const SpeculativeDecodingConfig.draftSimple({
    this.draftTokenMax,
    this.draftTokenMin,
    this.minProbability,
    this.draftSplitProbability,
    required this.draftModelPath,
  }) : strategy = SpeculativeDecodingStrategy.draftSimple,
       strategies = const [SpeculativeDecodingStrategy.draftSimple],
       ngramSize = null,
       ngramSizeN = null,
       ngramSizeM = null,
       ngramMinHits = null,
       ngramMatch = null,
       ngramTokenMin = null,
       ngramTokenMax = null,
       ngramCacheStaticPath = null,
       ngramCacheDynamicPath = null,
       assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(draftTokenMin == null || draftTokenMin >= 0),
       assert(
         minProbability == null ||
             (minProbability >= 0.0 && minProbability <= 1.0),
       ),
       assert(
         draftSplitProbability == null ||
             (draftSplitProbability >= 0.0 && draftSplitProbability <= 1.0),
       );

  /// Enables EAGLE-3 draft-model speculative decoding.
  const SpeculativeDecodingConfig.draftEagle3({
    this.draftTokenMax,
    this.draftTokenMin,
    this.minProbability,
    this.draftSplitProbability,
    required this.draftModelPath,
  }) : strategy = SpeculativeDecodingStrategy.draftEagle3,
       strategies = const [SpeculativeDecodingStrategy.draftEagle3],
       ngramSize = null,
       ngramSizeN = null,
       ngramSizeM = null,
       ngramMinHits = null,
       ngramMatch = null,
       ngramTokenMin = null,
       ngramTokenMax = null,
       ngramCacheStaticPath = null,
       ngramCacheDynamicPath = null,
       assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(draftTokenMin == null || draftTokenMin >= 0),
       assert(
         minProbability == null ||
             (minProbability >= 0.0 && minProbability <= 1.0),
       ),
       assert(
         draftSplitProbability == null ||
             (draftSplitProbability >= 0.0 && draftSplitProbability <= 1.0),
       );

  /// Enables DFlash draft-model speculative decoding.
  const SpeculativeDecodingConfig.draftDflash({
    this.draftTokenMax,
    this.draftTokenMin,
    this.minProbability,
    this.draftSplitProbability,
    required this.draftModelPath,
  }) : strategy = SpeculativeDecodingStrategy.draftDflash,
       strategies = const [SpeculativeDecodingStrategy.draftDflash],
       ngramSize = null,
       ngramSizeN = null,
       ngramSizeM = null,
       ngramMinHits = null,
       ngramMatch = null,
       ngramTokenMin = null,
       ngramTokenMax = null,
       ngramCacheStaticPath = null,
       ngramCacheDynamicPath = null,
       assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(draftTokenMin == null || draftTokenMin >= 0),
       assert(
         minProbability == null ||
             (minProbability >= 0.0 && minProbability <= 1.0),
       ),
       assert(
         draftSplitProbability == null ||
             (draftSplitProbability >= 0.0 && draftSplitProbability <= 1.0),
       );

  /// Enables llama.cpp ngram-simple speculative decoding.
  ///
  /// Ngram-simple uses previous tokens as its draft source and maps to upstream
  /// `ngram-simple`.
  const SpeculativeDecodingConfig.ngramSimple({
    this.draftTokenMax,
    int? ngramSize,
    int? ngramSizeN,
    this.ngramSizeM,
    this.ngramMinHits,
  }) : strategy = SpeculativeDecodingStrategy.ngramSimple,
       strategies = const [SpeculativeDecodingStrategy.ngramSimple],
       draftTokenMin = null,
       minProbability = null,
       draftSplitProbability = null,
       draftModelPath = null,
       ngramSize = ngramSizeN ?? ngramSize,
       ngramSizeN = ngramSizeN ?? ngramSize,
       ngramMatch = null,
       ngramTokenMin = null,
       ngramTokenMax = null,
       ngramCacheStaticPath = null,
       ngramCacheDynamicPath = null,
       assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(ngramSize == null || ngramSize > 0),
       assert(ngramSizeN == null || ngramSizeN > 0),
       assert(ngramSizeM == null || ngramSizeM > 0),
       assert(ngramMinHits == null || ngramMinHits > 0);

  /// Enables llama.cpp ngram-map-k speculative decoding.
  const SpeculativeDecodingConfig.ngramMapK({
    this.draftTokenMax,
    int? ngramSize,
    int? ngramSizeN,
    this.ngramSizeM,
    this.ngramMinHits,
  }) : strategy = SpeculativeDecodingStrategy.ngramMapK,
       strategies = const [SpeculativeDecodingStrategy.ngramMapK],
       draftTokenMin = null,
       minProbability = null,
       draftSplitProbability = null,
       draftModelPath = null,
       ngramSize = ngramSizeN ?? ngramSize,
       ngramSizeN = ngramSizeN ?? ngramSize,
       ngramMatch = null,
       ngramTokenMin = null,
       ngramTokenMax = null,
       ngramCacheStaticPath = null,
       ngramCacheDynamicPath = null,
       assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(ngramSize == null || ngramSize > 0),
       assert(ngramSizeN == null || ngramSizeN > 0),
       assert(ngramSizeM == null || ngramSizeM > 0),
       assert(ngramMinHits == null || ngramMinHits > 0);

  /// Enables llama.cpp ngram-map-k4v speculative decoding.
  const SpeculativeDecodingConfig.ngramMapK4v({
    this.draftTokenMax,
    int? ngramSize,
    int? ngramSizeN,
    this.ngramSizeM,
    this.ngramMinHits,
  }) : strategy = SpeculativeDecodingStrategy.ngramMapK4v,
       strategies = const [SpeculativeDecodingStrategy.ngramMapK4v],
       draftTokenMin = null,
       minProbability = null,
       draftSplitProbability = null,
       draftModelPath = null,
       ngramSize = ngramSizeN ?? ngramSize,
       ngramSizeN = ngramSizeN ?? ngramSize,
       ngramMatch = null,
       ngramTokenMin = null,
       ngramTokenMax = null,
       ngramCacheStaticPath = null,
       ngramCacheDynamicPath = null,
       assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(ngramSize == null || ngramSize > 0),
       assert(ngramSizeN == null || ngramSizeN > 0),
       assert(ngramSizeM == null || ngramSizeM > 0),
       assert(ngramMinHits == null || ngramMinHits > 0);

  /// Enables llama.cpp ngram-mod speculative decoding.
  const SpeculativeDecodingConfig.ngramMod({
    this.draftTokenMax,
    this.ngramMatch,
    this.ngramTokenMin,
    this.ngramTokenMax,
  }) : strategy = SpeculativeDecodingStrategy.ngramMod,
       strategies = const [SpeculativeDecodingStrategy.ngramMod],
       draftTokenMin = null,
       minProbability = null,
       draftSplitProbability = null,
       draftModelPath = null,
       ngramSize = null,
       ngramSizeN = null,
       ngramSizeM = null,
       ngramMinHits = null,
       ngramCacheStaticPath = null,
       ngramCacheDynamicPath = null,
       assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(ngramMatch == null || ngramMatch > 0),
       assert(ngramTokenMin == null || ngramTokenMin >= 0),
       assert(ngramTokenMax == null || ngramTokenMax >= 0);

  /// Enables llama.cpp ngram-cache speculative decoding.
  const SpeculativeDecodingConfig.ngramCache({
    this.draftTokenMax,
    this.ngramCacheStaticPath,
    this.ngramCacheDynamicPath,
  }) : strategy = SpeculativeDecodingStrategy.ngramCache,
       strategies = const [SpeculativeDecodingStrategy.ngramCache],
       draftTokenMin = null,
       minProbability = null,
       draftSplitProbability = null,
       draftModelPath = null,
       ngramSize = null,
       ngramSizeN = null,
       ngramSizeM = null,
       ngramMinHits = null,
       ngramMatch = null,
       ngramTokenMin = null,
       ngramTokenMax = null,
       assert(draftTokenMax == null || draftTokenMax >= 0);

  /// Enables a mixed llama.cpp speculative configuration.
  ///
  /// This mirrors upstream comma-separated `--spec-type`. Use at most one
  /// draft-model strategy and any number of draftless n-gram strategies.
  const SpeculativeDecodingConfig.mixed({
    required this.strategies,
    this.draftTokenMax,
    this.draftTokenMin,
    this.minProbability,
    this.draftSplitProbability,
    this.draftModelPath,
    this.ngramSize,
    this.ngramSizeN,
    this.ngramSizeM,
    this.ngramMinHits,
    this.ngramMatch,
    this.ngramTokenMin,
    this.ngramTokenMax,
    this.ngramCacheStaticPath,
    this.ngramCacheDynamicPath,
  }) : strategy = SpeculativeDecodingStrategy.backendDefault,
       assert(draftTokenMax == null || draftTokenMax >= 0),
       assert(draftTokenMin == null || draftTokenMin >= 0),
       assert(ngramSize == null || ngramSize > 0),
       assert(ngramSizeN == null || ngramSizeN > 0),
       assert(ngramSizeM == null || ngramSizeM > 0),
       assert(ngramMinHits == null || ngramMinHits > 0),
       assert(ngramMatch == null || ngramMatch > 0),
       assert(ngramTokenMin == null || ngramTokenMin >= 0),
       assert(ngramTokenMax == null || ngramTokenMax >= 0),
       assert(
         minProbability == null ||
             (minProbability >= 0.0 && minProbability <= 1.0),
       ),
       assert(
         draftSplitProbability == null ||
             (draftSplitProbability >= 0.0 && draftSplitProbability <= 1.0),
       );

  /// Effective strategy list for backends that support upstream-style mixing.
  List<SpeculativeDecodingStrategy> get effectiveStrategies =>
      strategies.isEmpty ? <SpeculativeDecodingStrategy>[strategy] : strategies;
}

/// Limits the generated tokens within a model's reasoning block.
///
/// This maps to llama.cpp's reasoning-budget sampler. A budget of zero closes
/// the next reasoning block immediately; a positive value permits that many
/// generated reasoning tokens before the sampler forces [endTag].
/// llama.cpp accepts values from zero through 2,147,483,647.
///
/// [LlamaEngine.create] resolves omitted [startTag] and [endTag] from the
/// rendered chat template. Callers using raw generation should supply both
/// tags explicitly because models do not share a universal reasoning syntax.
class ThinkingBudget {
  /// Creates a thinking-token budget.
  const ThinkingBudget({
    required this.maxTokens,
    this.startTag,
    this.endTag,
    this.forcedMessage,
  }) : assert(maxTokens >= 0, 'maxTokens must be non-negative');

  /// Maximum generated tokens allowed inside each reasoning block.
  final int maxTokens;

  /// Reasoning-block opening delimiter.
  final String? startTag;

  /// Reasoning-block closing delimiter forced when [maxTokens] is exhausted.
  final String? endTag;

  /// Optional text forced immediately before [endTag] after exhaustion.
  final String? forcedMessage;
}

/// Parameters controlling the token sampling and generation process.
class GenerationParams {
  /// Default prompt prefix reuse behavior for native generation.
  static const bool defaultReusePromptPrefix = true;

  /// Default native stream batching threshold by token pieces.
  static const int defaultStreamBatchTokenThreshold = 8;

  /// Default native stream batching threshold by byte size.
  static const int defaultStreamBatchByteThreshold = 512;

  /// Maximum number of new tokens to generate.
  final int maxTokens;

  /// Temperature for sampling (higher = more creative/random, lower = more deterministic).
  /// Range is typically 0.0 to 2.0.
  final double temp;

  /// Top-K sampling: only sample from the top K most likely tokens.
  /// Set to 0 to disable.
  final int topK;

  /// Top-P sampling (nucleus sampling): only sample from tokens whose
  /// cumulative probability exceeds P.
  final double topP;

  /// Min-P sampling threshold.
  ///
  /// Set to 0.0 to disable Min-P filtering.
  final double minP;

  /// Penalty applied to tokens that have already appeared in the sequence.
  /// 1.0 means no penalty.
  final double penalty;

  /// Additive penalty applied once to tokens that appear in the sampler's
  /// recent history.
  ///
  /// `0.0` disables the penalty. This is distinct from [penalty], which scales
  /// logits using llama.cpp's repeat-penalty sampler. Native llama.cpp supports
  /// this option; backends without an equivalent sampler reject nonzero values
  /// instead of silently ignoring them.
  final double presencePenalty;

  /// Random seed for the sampler.
  ///
  /// If null, a seed based on the current time will be used.
  final int? seed;

  /// List of strings that, if generated, will immediately stop the generation process.
  final List<String> stopSequences;

  /// GBNF grammar string for structured output (e.g., "root ::= \"hello\" | \"world\"").
  final String? grammar;

  /// Whether grammar should be lazily activated by triggers.
  final bool grammarLazy;

  /// Optional llama.cpp-style limit for tokens generated inside a reasoning
  /// block.
  ///
  /// The native llama.cpp backend pauses grammar constraints while budgeted
  /// reasoning is active, then resumes tool-call or structured-output grammar
  /// after reasoning has ended. Other backends reject this setting rather than
  /// silently ignoring it.
  final ThinkingBudget? thinkingBudget;

  /// Lazy grammar activation triggers.
  final List<GenerationGrammarTrigger> grammarTriggers;

  /// Tokens to preserve during constrained decoding.
  final List<String> preservedTokens;

  /// Grammar start symbol. Defaults to "root".
  final String grammarRoot;

  /// Enables backend-native speculative decoding when supported.
  ///
  /// Native LiteRT-LM forwards this flag to the runtime's speculative decoding
  /// setting. llama.cpp maps it to the backend-default speculative strategy
  /// when the active model/context supports that path. WebGPU and LiteRT-LM web
  /// reject this option until their runtimes expose equivalent controls.
  ///
  /// Prefer [speculativeDecodingConfig] for new code that needs a specific
  /// strategy or runtime-neutral options.
  final bool speculativeDecoding;

  /// Strategy and knobs for backend-native speculative decoding.
  ///
  /// `null` disables speculative decoding unless [speculativeDecoding] is true.
  /// When [speculativeDecoding] is true and this is null, backends should treat
  /// the request as [SpeculativeDecodingStrategy.backendDefault].
  final SpeculativeDecodingConfig? speculativeDecodingConfig;

  /// Reuses matching prompt prefixes from previous requests in the same native
  /// context to reduce prompt ingestion latency.
  ///
  /// This optimization applies to native text-only generation.
  /// Exact full-prompt replays are conservatively re-ingested to preserve
  /// deterministic parity.
  final bool reusePromptPrefix;

  /// Native worker chunk flush threshold by token pieces.
  ///
  /// Lower values improve stream granularity but increase isolate message
  /// overhead. Higher values reduce overhead but emit larger chunks.
  final int streamBatchTokenThreshold;

  /// Native worker chunk flush threshold by byte size.
  ///
  /// Lower values improve stream granularity but increase isolate message
  /// overhead. Higher values reduce overhead but emit larger chunks.
  final int streamBatchByteThreshold;

  /// Creates generation parameters with default values.
  const GenerationParams({
    this.maxTokens = 4096,
    this.temp = 0.8,
    this.topK = 40,
    this.topP = 0.9,
    this.minP = 0.0,
    this.penalty = 1.1,
    this.presencePenalty = 0.0,
    this.seed,
    this.stopSequences = const [],
    this.grammar,
    this.grammarLazy = false,
    this.thinkingBudget,
    this.grammarTriggers = const [],
    this.preservedTokens = const [],
    this.grammarRoot = 'root',
    this.speculativeDecoding = false,
    this.speculativeDecodingConfig,
    this.reusePromptPrefix = defaultReusePromptPrefix,
    this.streamBatchTokenThreshold = defaultStreamBatchTokenThreshold,
    this.streamBatchByteThreshold = defaultStreamBatchByteThreshold,
  });

  /// Whether speculative decoding is requested by either public API shape.
  bool get isSpeculativeDecodingEnabled =>
      speculativeDecoding || speculativeDecodingConfig != null;

  /// Resolved speculative decoding configuration, if enabled.
  ///
  /// Legacy [speculativeDecoding] requests resolve to backend-default
  /// speculative decoding.
  SpeculativeDecodingConfig? get resolvedSpeculativeDecodingConfig =>
      speculativeDecodingConfig ??
      (speculativeDecoding
          ? const SpeculativeDecodingConfig.backendDefault()
          : null);

  /// Creates a copy of this [GenerationParams] with updated fields.
  GenerationParams copyWith({
    int? maxTokens,
    double? temp,
    int? topK,
    double? topP,
    double? minP,
    double? penalty,
    double? presencePenalty,
    int? seed,
    List<String>? stopSequences,
    String? grammar,
    bool? grammarLazy,
    ThinkingBudget? thinkingBudget,
    bool clearThinkingBudget = false,
    List<GenerationGrammarTrigger>? grammarTriggers,
    List<String>? preservedTokens,
    String? grammarRoot,
    bool? speculativeDecoding,
    SpeculativeDecodingConfig? speculativeDecodingConfig,
    bool clearSpeculativeDecodingConfig = false,
    bool? reusePromptPrefix,
    int? streamBatchTokenThreshold,
    int? streamBatchByteThreshold,
  }) {
    return GenerationParams(
      maxTokens: maxTokens ?? this.maxTokens,
      temp: temp ?? this.temp,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
      minP: minP ?? this.minP,
      penalty: penalty ?? this.penalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      seed: seed ?? this.seed,
      stopSequences: stopSequences ?? this.stopSequences,
      grammar: grammar ?? this.grammar,
      grammarLazy: grammarLazy ?? this.grammarLazy,
      thinkingBudget: clearThinkingBudget
          ? null
          : (thinkingBudget ?? this.thinkingBudget),
      grammarTriggers: grammarTriggers ?? this.grammarTriggers,
      preservedTokens: preservedTokens ?? this.preservedTokens,
      grammarRoot: grammarRoot ?? this.grammarRoot,
      speculativeDecoding: speculativeDecoding ?? this.speculativeDecoding,
      speculativeDecodingConfig: clearSpeculativeDecodingConfig
          ? null
          : (speculativeDecodingConfig ?? this.speculativeDecodingConfig),
      reusePromptPrefix: reusePromptPrefix ?? this.reusePromptPrefix,
      streamBatchTokenThreshold:
          streamBatchTokenThreshold ?? this.streamBatchTokenThreshold,
      streamBatchByteThreshold:
          streamBatchByteThreshold ?? this.streamBatchByteThreshold,
    );
  }
}
