import '../../exceptions.dart';
import '../model_load_options.dart';
import '../model_source.dart';

/// How a [GenerationGrammarTrigger] activates a lazy grammar.
enum GrammarTriggerType {
  /// The trigger value appears literally in the output. Wire value `0`.
  word(0),

  /// The model samples the token [GenerationGrammarTrigger.token], or the
  /// token id the trigger value spells. Wire value `1`.
  token(1),

  /// The output matches the trigger value as a regular expression. Wire
  /// value `2`.
  pattern(2),

  /// The whole output matches the trigger value as a regular expression.
  /// Wire value `3`.
  patternFull(3);

  const GrammarTriggerType(this.wireValue);

  /// The integer [GenerationGrammarTrigger.type] carries for this value.
  final int wireValue;

  /// Returns the value whose [wireValue] is [value].
  ///
  /// Throws [LlamaUnsupportedException] for any other integer.
  static GrammarTriggerType fromWireValue(int value) {
    for (final type in values) {
      if (type.wireValue == value) return type;
    }
    throw LlamaUnsupportedException(
      'Grammar trigger type $value is not supported; expected 0 (word), '
      '1 (token), 2 (pattern) or 3 (patternFull). Use '
      'GenerationGrammarTrigger.typed with a GrammarTriggerType.',
    );
  }
}

/// Lazy grammar activation trigger.
///
/// ```dart
/// const trigger = GenerationGrammarTrigger.typed(
///   type: GrammarTriggerType.word,
///   value: '<tool_call>',
/// );
/// ```
class GenerationGrammarTrigger {
  final GrammarTriggerType? _typedType;
  final int _rawType;

  /// Trigger text value.
  final String value;

  /// Trigger token id for token-based triggers.
  final int? token;

  /// Creates a grammar trigger from a raw trigger type (0=word, 1=token,
  /// 2=pattern, 3=pattern_full).
  ///
  /// Any other [type] makes [triggerType] throw
  /// [LlamaUnsupportedException], as does a llama.cpp lazy-grammar generation
  /// that uses this trigger.
  @Deprecated(
    'Use GenerationGrammarTrigger.typed with a GrammarTriggerType. '
    'This constructor will be removed in a future release.',
  )
  const GenerationGrammarTrigger({
    required int type,
    required this.value,
    this.token,
  }) : _rawType = type,
       _typedType = null;

  /// Creates a grammar trigger of [type].
  const GenerationGrammarTrigger.typed({
    required GrammarTriggerType type,
    required this.value,
    this.token,
  }) : _typedType = type,
       _rawType = -1;

  /// Trigger type wire value (0=word, 1=token, 2=pattern, 3=pattern_full).
  ///
  /// Prefer [triggerType].
  int get type => _typedType?.wireValue ?? _rawType;

  /// The trigger type.
  ///
  /// Throws [LlamaUnsupportedException] when this trigger was created with
  /// a raw [type] that is not a [GrammarTriggerType] wire value.
  GrammarTriggerType get triggerType =>
      _typedType ?? GrammarTriggerType.fromWireValue(_rawType);
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

  /// Experimental, opt-in DSpark draft-model speculative decoding.
  ///
  /// llama.cpp maps this to its `draft-dspark` path. It uses a separate draft
  /// model and is distinct from MTP. Callers must select this strategy
  /// explicitly; it is never enabled by default.
  draftDspark,
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

  /// Physical micro-batch size (`n_ubatch`) of the speculative draft context.
  ///
  /// Mirrors upstream llama.cpp `--spec-draft-n-ubatch`. A value below the
  /// target's `ModelParams.microBatchSize` shrinks the draft context's compute
  /// buffer. Chunked draft prefill can change the draft model's numerics, so
  /// it may change which tokens the draft proposes, and with them speed,
  /// acceptance and sometimes the output, even with greedy sampling. The
  /// target model still verifies every accepted token. `null` keeps the
  /// draft context on the target context's micro-batch size.
  ///
  /// Native llama.cpp applies it to the draft context of `draftSimple`,
  /// `draftEagle3`, `mtp`, `draftDflash` and `draftDspark`, and throws
  /// [LlamaArgumentException] when it is below one, above the context's
  /// resolved `ModelParams.batchSize` (bounded by `ModelParams.contextSize`),
  /// or, for `draftDflash` and `draftDspark`, below the effective
  /// [draftTokenMax] plus one, since those decode a whole draft block in one
  /// micro-batch. With a LiliCorr draft model (GGUF
  /// `lilicorr.candidate_topk` above zero) that block is the model's
  /// `dflash.block_size` (16 when absent), whatever [draftTokenMax] is, and
  /// generation throws before the draft session starts when the size is
  /// below it. While this is `null`, generation throws
  /// [LlamaArgumentException] naming `ModelParams.microBatchSize` before the
  /// draft session starts when the inherited micro-batch is smaller than the
  /// block llama.cpp decodes: that LiliCorr block, or else
  /// `min(draftTokenMax, block_size - 1) + 1` (DFlash and DSpark with
  /// `dflash.sample_from_anchor` false) or `min(draftTokenMax, block_size)`
  /// (anchor-first DSpark), using the effective [draftTokenMax] and the
  /// draft model's `dflash.block_size`. Strategies without a draft context
  /// and WebGPU throw
  /// [LlamaUnsupportedException]; LiteRT-LM rejects it with its other
  /// llama.cpp-specific speculative options.
  final int? draftMicroBatchSize;

  final String? _draftModelPath;

  /// Optional draft model for speculative decoding modes that use a separate
  /// drafter model, such as llama.cpp `--model-draft` with `draft-simple`,
  /// `draft-eagle3`, `draft-mtp`, `draft-dflash`, or `draft-dspark`: a local
  /// path, an HTTP(S) URL or a Hugging Face file.
  ///
  /// Leave null for models that carry their own MTP layers.
  ///
  /// `LlamaEngine` resolves it when the first generation that uses it starts,
  /// before the request reaches the backend, as
  /// `LlamaEngine.setModel` resolves a model: its `modelResolver` and
  /// `modelDownloadManager` check a local file, or download a remote one
  /// with [draftModelDownload] into the model cache, or reuse the cached
  /// file. On WebGPU the runtime fetches the URL itself. Later generations
  /// on the same loaded model reuse that file for the same source, cache
  /// directory and checksum, so the download and any checksum check run
  /// once per loaded model; unloading or reloading the model resolves it
  /// again. Cancelling the generation, or unloading the model, stops the
  /// download. LiteRT-LM, and a backend that does not report every strategy
  /// of this configuration, throw `LlamaUnsupportedException` before
  /// anything downloads. The download reports no progress; to show
  /// progress, download the file first with
  /// `engine.modelDownloadManager.ensureModel(draftModel, options:
  /// draftModelDownload, onProgress: ...)`, and the generation then reuses
  /// the cached file.
  ///
  /// Strategies that use a separate drafter, such as `draftSimple`, need it
  /// at run time: the backend throws when it is null.
  final ModelSource? draftModel;

  /// Download options for [draftModel]: cache policy and directory,
  /// authentication, checksum, resume, retries and cancel token. A local
  /// [draftModel] takes only [ModelLoadOptions.sha256] and the cancel token,
  /// as [ModelLoadOptions] describes. [ModelCachePolicy.noCache] and
  /// [ModelCachePolicy.refresh] throw `LlamaUnsupportedException`, since the
  /// draft model resolves once per loaded model. They apply only to the
  /// download `LlamaEngine` runs: backends receive the configuration with
  /// default options, so credentials and the cancel token stay in the
  /// calling isolate.
  final ModelLoadOptions draftModelDownload;

  /// The draft model file that backends load: the deprecated path a caller
  /// set, the path of a local [draftModel], or the URL of a remote one.
  ///
  /// A remote [draftModel] becomes a file only when `LlamaEngine` downloads
  /// it, so pass a configuration with a remote [draftModel] through
  /// `LlamaEngine`, not straight to a native backend.
  String? get draftModelPath =>
      _draftModelPath ?? draftModel?.path ?? draftModel?.url.toString();

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
    this.draftMicroBatchSize,
    @Deprecated(
      'Use draftModel with ModelSource.path(path) or another ModelSource. '
      'This parameter will be removed in a future release.',
    )
    String? draftModelPath,
    this.draftModel,
    this.draftModelDownload = ModelLoadOptions.defaults,
    this.ngramSize,
    this.ngramSizeN,
    this.ngramSizeM,
    this.ngramMinHits,
    this.ngramMatch,
    this.ngramTokenMin,
    this.ngramTokenMax,
    this.ngramCacheStaticPath,
    this.ngramCacheDynamicPath,
  }) : _draftModelPath = draftModelPath,
       assert(
         draftModelPath == null || draftModel == null,
         'Set draftModel or the deprecated draftModelPath, not both.',
       ),
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

  /// Enables the backend's default speculative decoding behavior.
  const SpeculativeDecodingConfig.backendDefault()
    : strategy = SpeculativeDecodingStrategy.backendDefault,
      strategies = const [SpeculativeDecodingStrategy.backendDefault],
      draftTokenMax = null,
      draftTokenMin = null,
      minProbability = null,
      draftSplitProbability = null,
      draftMicroBatchSize = null,
      _draftModelPath = null,
      draftModel = null,
      draftModelDownload = ModelLoadOptions.defaults,
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
    this.draftMicroBatchSize,
    @Deprecated(
      'Use draftModel with ModelSource.path(path) or another ModelSource. '
      'This parameter will be removed in a future release.',
    )
    String? draftModelPath,
    this.draftModel,
    this.draftModelDownload = ModelLoadOptions.defaults,
  }) : _draftModelPath = draftModelPath,
       assert(
         draftModelPath == null || draftModel == null,
         'Set draftModel or the deprecated draftModelPath, not both.',
       ),
       strategy = SpeculativeDecodingStrategy.mtp,
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
    this.draftMicroBatchSize,
    @Deprecated(
      'Use draftModel with ModelSource.path(path) or another ModelSource. '
      'This parameter will be removed in a future release.',
    )
    String? draftModelPath,
    this.draftModel,
    this.draftModelDownload = ModelLoadOptions.defaults,
  }) : _draftModelPath = draftModelPath,
       assert(
         draftModelPath == null || draftModel == null,
         'Set draftModel or the deprecated draftModelPath, not both.',
       ),
       strategy = SpeculativeDecodingStrategy.draftSimple,
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
    this.draftMicroBatchSize,
    @Deprecated(
      'Use draftModel with ModelSource.path(path) or another ModelSource. '
      'This parameter will be removed in a future release.',
    )
    String? draftModelPath,
    this.draftModel,
    this.draftModelDownload = ModelLoadOptions.defaults,
  }) : _draftModelPath = draftModelPath,
       assert(
         draftModelPath == null || draftModel == null,
         'Set draftModel or the deprecated draftModelPath, not both.',
       ),
       strategy = SpeculativeDecodingStrategy.draftEagle3,
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
    this.draftMicroBatchSize,
    @Deprecated(
      'Use draftModel with ModelSource.path(path) or another ModelSource. '
      'This parameter will be removed in a future release.',
    )
    String? draftModelPath,
    this.draftModel,
    this.draftModelDownload = ModelLoadOptions.defaults,
  }) : _draftModelPath = draftModelPath,
       assert(
         draftModelPath == null || draftModel == null,
         'Set draftModel or the deprecated draftModelPath, not both.',
       ),
       strategy = SpeculativeDecodingStrategy.draftDflash,
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

  /// Enables experimental upstream llama.cpp `draft-dspark` decoding.
  ///
  /// This is an opt-in strategy and is never selected automatically. Native
  /// llama.cpp requires [draftModel] to identify a compatible external
  /// DSpark draft GGUF. Validate deterministic output, acceptance, and warmed
  /// throughput for the exact target, draft, and backend before production
  /// use. LiteRT-LM rejects this strategy, WebGPU rejects it unless its bridge
  /// assets report `draft-dspark`, and native runtimes without DSpark
  /// draft-context support fail explicitly.
  const SpeculativeDecodingConfig.draftDspark({
    this.draftTokenMax,
    this.draftTokenMin,
    this.minProbability,
    this.draftSplitProbability,
    this.draftMicroBatchSize,
    @Deprecated(
      'Use draftModel with ModelSource.path(path) or another ModelSource. '
      'This parameter will be removed in a future release.',
    )
    String? draftModelPath,
    this.draftModel,
    this.draftModelDownload = ModelLoadOptions.defaults,
  }) : _draftModelPath = draftModelPath,
       assert(
         draftModelPath == null || draftModel == null,
         'Set draftModel or the deprecated draftModelPath, not both.',
       ),
       strategy = SpeculativeDecodingStrategy.draftDspark,
       strategies = const [SpeculativeDecodingStrategy.draftDspark],
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
       draftMicroBatchSize = null,
       _draftModelPath = null,
       draftModel = null,
       draftModelDownload = ModelLoadOptions.defaults,
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
       draftMicroBatchSize = null,
       _draftModelPath = null,
       draftModel = null,
       draftModelDownload = ModelLoadOptions.defaults,
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
       draftMicroBatchSize = null,
       _draftModelPath = null,
       draftModel = null,
       draftModelDownload = ModelLoadOptions.defaults,
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
       draftMicroBatchSize = null,
       _draftModelPath = null,
       draftModel = null,
       draftModelDownload = ModelLoadOptions.defaults,
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
       draftMicroBatchSize = null,
       _draftModelPath = null,
       draftModel = null,
       draftModelDownload = ModelLoadOptions.defaults,
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
    this.draftMicroBatchSize,
    @Deprecated(
      'Use draftModel with ModelSource.path(path) or another ModelSource. '
      'This parameter will be removed in a future release.',
    )
    String? draftModelPath,
    this.draftModel,
    this.draftModelDownload = ModelLoadOptions.defaults,
    this.ngramSize,
    this.ngramSizeN,
    this.ngramSizeM,
    this.ngramMinHits,
    this.ngramMatch,
    this.ngramTokenMin,
    this.ngramTokenMax,
    this.ngramCacheStaticPath,
    this.ngramCacheDynamicPath,
  }) : _draftModelPath = draftModelPath,
       assert(
         draftModelPath == null || draftModel == null,
         'Set draftModel or the deprecated draftModelPath, not both.',
       ),
       strategy = SpeculativeDecodingStrategy.backendDefault,
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

  /// A copy of this configuration with [draftModel] and its
  /// [draftModelDownload] in place of its draft model, download options or
  /// deprecated path, keeping every other setting.
  SpeculativeDecodingConfig withDraftModel(
    ModelSource draftModel, {
    ModelLoadOptions draftModelDownload = ModelLoadOptions.defaults,
  }) => SpeculativeDecodingConfig._copy(
    this,
    draftModel: draftModel,
    draftModelPath: null,
    draftModelDownload: draftModelDownload,
  );

  /// A copy of this configuration with [draftModelDownload] in place of its
  /// download options, keeping every other setting.
  ///
  /// `LlamaEngine` sends backends a copy with the default options: the
  /// caller's options, which can hold credentials and a cancel token, only
  /// apply to the download the engine runs.
  SpeculativeDecodingConfig withDraftModelDownload(
    ModelLoadOptions draftModelDownload,
  ) => SpeculativeDecodingConfig._copy(
    this,
    draftModel: draftModel,
    draftModelPath: _draftModelPath,
    draftModelDownload: draftModelDownload,
  );

  SpeculativeDecodingConfig._copy(
    SpeculativeDecodingConfig config, {
    required this.draftModel,
    required String? draftModelPath,
    required this.draftModelDownload,
  }) : strategy = config.strategy,
       strategies = config.strategies,
       draftTokenMax = config.draftTokenMax,
       draftTokenMin = config.draftTokenMin,
       minProbability = config.minProbability,
       draftSplitProbability = config.draftSplitProbability,
       draftMicroBatchSize = config.draftMicroBatchSize,
       _draftModelPath = draftModelPath,
       ngramSize = config.ngramSize,
       ngramSizeN = config.ngramSizeN,
       ngramSizeM = config.ngramSizeM,
       ngramMinHits = config.ngramMinHits,
       ngramMatch = config.ngramMatch,
       ngramTokenMin = config.ngramTokenMin,
       ngramTokenMax = config.ngramTokenMax,
       ngramCacheStaticPath = config.ngramCacheStaticPath,
       ngramCacheDynamicPath = config.ngramCacheDynamicPath;

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
  ///
  /// With [endTag] omitted, Qwen3-Coder XML templates append a line break to
  /// it, as llama.cpp does.
  final String? forcedMessage;
}

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
  /// Range is typically 0.0 to 2.0. Native LiteRT-LM CPU/GPU and LiteRT-LM Web
  /// treat zero as greedy decoding and use one candidate regardless of [topK].
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
  ///
  /// Native LiteRT-LM counts only the tokens of the current send, leaves the
  /// default value unapplied and rejects values below 1.0.
  final double penalty;

  /// Additive penalty applied once to tokens that appear in the sampler's
  /// recent history.
  ///
  /// `0.0` disables the penalty. This is distinct from [penalty], which scales
  /// logits using llama.cpp's repeat-penalty sampler. Native llama.cpp supports
  /// this option; native LiteRT-LM applies it to the tokens of the current
  /// send only. Backends without an equivalent sampler reject nonzero values
  /// instead of silently ignoring them.
  final double presencePenalty;

  /// Random seed for the sampler.
  ///
  /// If null, a seed based on the current time will be used.
  final int? seed;

  /// Strings that end generation when matched, excluding the marker from output.
  ///
  /// Empty strings are ignored. Native GGUF matches across token boundaries and
  /// inside token pieces; an unfinished prefix is emitted if generation ends
  /// without a full match. Exact entries in [preservedTokens] remain available
  /// to the native chat parser instead of acting as text stops.
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
  /// after reasoning has ended. Native LiteRT-LM applies it to chat
  /// generation on bundles with a thinking channel, which it closes with the
  /// bundle's own end marker; it rejects a zero budget and
  /// [ThinkingBudget.forcedMessage]. Other backends reject this setting rather
  /// than silently ignoring it.
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
  /// setting; when the runtime cannot run it and the bundle declares no
  /// speculative drafter, the request throws `LlamaUnsupportedException`.
  /// llama.cpp, native and WebGPU, maps it to the backend-default
  /// speculative strategy, `ngram-mod`, when the active model/context supports
  /// that path; WebGPU needs bridge assets that report `ngram-mod`. LiteRT-LM
  /// web rejects this option.
  ///
  /// With a llama.cpp runtime older than ggml 0.28.0 (llamadart-native
  /// v0.8.0), native Qwen3.5 on Android Vulkan GPUs with a subgroup size below
  /// 32 other than 8 rejects speculation before evaluation (#948).
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
  /// Exact full-prompt replays of an in-process cache are conservatively
  /// re-ingested. After loading a KV state file, native llama.cpp instead
  /// re-evaluates the final token on an exact match; scores and continuation
  /// can differ from full-prompt evaluation. Set this to false to explicitly
  /// evaluate the full prompt again, trading away prefix reuse.
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
