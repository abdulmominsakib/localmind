import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import '../../core/cache_policy.dart';
import '../../core/exceptions.dart';
import '../../core/models/inference/generation_params.dart';
import 'interop.dart';
import 'webgpu_decision.dart';
import 'webgpu_errors.dart';
import 'webgpu_url.dart';

/// The llama.cpp `--spec-type` name the bridge takes for each strategy.
const Map<SpeculativeDecodingStrategy, String> webGpuSpeculativeStrategyNames =
    <SpeculativeDecodingStrategy, String>{
      SpeculativeDecodingStrategy.mtp: 'draft-mtp',
      SpeculativeDecodingStrategy.ngramSimple: 'ngram-simple',
      SpeculativeDecodingStrategy.draftSimple: 'draft-simple',
      SpeculativeDecodingStrategy.draftEagle3: 'draft-eagle3',
      SpeculativeDecodingStrategy.draftDflash: 'draft-dflash',
      SpeculativeDecodingStrategy.ngramMapK: 'ngram-map-k',
      SpeculativeDecodingStrategy.ngramMapK4v: 'ngram-map-k4v',
      SpeculativeDecodingStrategy.ngramMod: 'ngram-mod',
      SpeculativeDecodingStrategy.ngramCache: 'ngram-cache',
      SpeculativeDecodingStrategy.draftDspark: 'draft-dspark',
    };

const Set<SpeculativeDecodingStrategy> _ngramStrategies =
    <SpeculativeDecodingStrategy>{
      SpeculativeDecodingStrategy.ngramSimple,
      SpeculativeDecodingStrategy.ngramMapK,
      SpeculativeDecodingStrategy.ngramMapK4v,
      SpeculativeDecodingStrategy.ngramMod,
      SpeculativeDecodingStrategy.ngramCache,
    };

const Set<SpeculativeDecodingStrategy> _externalDraftStrategies =
    <SpeculativeDecodingStrategy>{
      SpeculativeDecodingStrategy.draftSimple,
      SpeculativeDecodingStrategy.draftEagle3,
      SpeculativeDecodingStrategy.draftDflash,
      SpeculativeDecodingStrategy.draftDspark,
    };

const int _maxInt32 = 0x7fffffff;
const int _maxNgramSize = 0xffff;

/// The strategies a bridge runs, from the `speculativeDecoding` flags of its
/// `getCompletionCapabilities()` after a model load.
///
/// A bridge runs none unless it reports an n-gram strategy, which needs only a
/// speculative-capable core. [SpeculativeDecodingStrategy.backendDefault]
/// runs `ngram-mod`, as on native llama.cpp. The bridge reports `draft-mtp`
/// only for a model loaded with MTP layers, and the other `draft-*`
/// strategies only while a matching draft is loaded; since generation loads
/// the draft, those count when the bridge reports them as flags and
/// [hasDraftModelApi].
Set<SpeculativeDecodingStrategy> webGpuSpeculativeStrategiesFrom(
  JSAny? flags, {
  required bool hasDraftModelApi,
}) {
  if (flags == null || !flags.isA<JSObject>()) {
    return const <SpeculativeDecodingStrategy>{};
  }
  final object = flags as JSObject;
  JSAny? flag(SpeculativeDecodingStrategy strategy) => object
      .getProperty<JSAny?>(webGpuSpeculativeStrategyNames[strategy]!.toJS);
  bool reported(SpeculativeDecodingStrategy strategy) {
    final value = flag(strategy);
    return value != null &&
        value.isA<JSBoolean>() &&
        (value as JSBoolean).toDart;
  }

  final strategies = <SpeculativeDecodingStrategy>{
    ..._ngramStrategies.where(reported),
  };
  if (strategies.isEmpty) {
    return const <SpeculativeDecodingStrategy>{};
  }
  if (strategies.contains(SpeculativeDecodingStrategy.ngramMod)) {
    strategies.add(SpeculativeDecodingStrategy.backendDefault);
  }
  if (reported(SpeculativeDecodingStrategy.mtp)) {
    strategies.add(SpeculativeDecodingStrategy.mtp);
  }
  if (hasDraftModelApi) {
    strategies.addAll(
      _externalDraftStrategies.where(
        (strategy) => flag(strategy)?.isA<JSBoolean>() ?? false,
      ),
    );
  }
  return Set<SpeculativeDecodingStrategy>.unmodifiable(strategies);
}

/// Throws [UnsupportedError] unless [supported] holds every strategy of
/// [config].
void requireWebGpuSpeculativeSupport(
  SpeculativeDecodingConfig config,
  Set<SpeculativeDecodingStrategy> supported,
) {
  if (supported.isEmpty) {
    throw UnsupportedError(
      'WebGPU speculative decoding needs bridge assets whose '
      'getCompletionCapabilities() reports speculativeDecoding strategies; '
      'the loaded assets report none.',
    );
  }
  for (final strategy in config.effectiveStrategies) {
    if (supported.contains(strategy)) continue;
    throw UnsupportedError(switch (strategy) {
      SpeculativeDecodingStrategy.backendDefault =>
        'WebGPU backend-default speculative decoding runs ngram-mod, as '
            'native llama.cpp does, and needs bridge assets whose '
            'getCompletionCapabilities() reports ngram-mod; the loaded assets '
            'do not.',
      SpeculativeDecodingStrategy.mtp =>
        'WebGPU $strategy (draft-mtp) needs bridge assets whose '
            'getCompletionCapabilities() reports draft-mtp, which they do for '
            'a model with MTP layers loaded with ModelParams(loadMtp: true); '
            'the loaded assets do not.',
      _ when _externalDraftStrategies.contains(strategy) =>
        'WebGPU $strategy (${webGpuSpeculativeStrategyNames[strategy]}) needs '
            'bridge assets with loadDraftModel() whose '
            'getCompletionCapabilities() reports '
            '${webGpuSpeculativeStrategyNames[strategy]}; the loaded assets do '
            'not.',
      _ =>
        'WebGPU $strategy (${webGpuSpeculativeStrategyNames[strategy]}) needs '
            'bridge assets whose getCompletionCapabilities() reports it; the '
            'loaded assets do not.',
    });
  }
}

/// A speculative decoding request resolved for the bridge.
class WebGpuSpeculativeRequest {
  WebGpuSpeculativeRequest._({
    required this.options,
    required this.draftStrategy,
    required this.draftModelUrl,
    required this.sourceUrls,
  });

  /// The `speculativeDecoding` completion option.
  final WebGpuSpeculativeDecodingOptions options;

  /// The strategy that needs [draftModelUrl] loaded, if any.
  final SpeculativeDecodingStrategy? draftStrategy;

  /// The draft model URL, when [draftStrategy] is set.
  final String? draftModelUrl;

  /// URLs the request names, for redacting bridge errors.
  final List<String> sourceUrls;
}

/// Resolves the speculative decoding of [params] for the bridge, validating
/// it as native llama.cpp does, or returns null when it is off.
///
/// Call [requireWebGpuSpeculativeSupport] first.
WebGpuSpeculativeRequest? resolveWebGpuSpeculativeRequest(
  GenerationParams params, {
  required bool hasMediaParts,
}) {
  final config = params.resolvedSpeculativeDecodingConfig;
  if (config == null) return null;

  if (hasMediaParts) {
    throw LlamaUnsupportedException(
      'WebGPU speculative decoding supports text-only generation, as native '
      'llama.cpp does.',
    );
  }
  if (params.thinkingBudget != null) {
    throw LlamaUnsupportedException(
      'WebGPU thinking-budget control cannot be combined with speculative '
      'decoding, as on native llama.cpp.',
    );
  }
  if (params.grammar != null) {
    throw LlamaUnsupportedException(
      'WebGPU speculative decoding does not support grammar sampling, as on '
      'native llama.cpp.',
    );
  }
  if (config.draftMicroBatchSize != null) {
    throw LlamaUnsupportedException(
      'WebGPU speculative decoding does not support draftMicroBatchSize: the '
      'bridge takes no draft micro-batch option and creates its draft context '
      'with the target micro-batch size.',
    );
  }

  final strategies = <SpeculativeDecodingStrategy>[];
  for (final requested in config.effectiveStrategies) {
    final strategy = requested == SpeculativeDecodingStrategy.backendDefault
        ? SpeculativeDecodingStrategy.ngramMod
        : requested;
    if (!strategies.contains(strategy)) strategies.add(strategy);
  }
  final draftStrategies = strategies
      .where((strategy) => !_ngramStrategies.contains(strategy))
      .toList(growable: false);
  if (draftStrategies.length > 1) {
    throw LlamaUnsupportedException(
      'WebGPU speculative decoding can mix n-gram strategies with at most one '
      'draft-model strategy, as native llama.cpp does.',
    );
  }
  final draftStrategy = draftStrategies.isEmpty ? null : draftStrategies.first;

  final draftModelPath = config.draftModelPath;
  if (draftModelPath != null && draftModelPath.trim().isEmpty) {
    throw ArgumentError.value(
      draftModelPath,
      'draftModelPath',
      'must be null or a non-empty URL for WebGPU speculative decoding',
    );
  }
  final needsDraftModel = _externalDraftStrategies.contains(draftStrategy);
  if (needsDraftModel && draftModelPath == null) {
    throw ArgumentError(
      'WebGPU ${webGpuSpeculativeStrategyNames[draftStrategy]} requires '
      'SpeculativeDecodingConfig.draftModel.',
    );
  }
  if (draftStrategy == SpeculativeDecodingStrategy.mtp &&
      draftModelPath != null) {
    throw LlamaUnsupportedException(
      'WebGPU draft-mtp runs the loaded model\'s own MTP layers; the bridge '
      'cannot load an external MTP draft model, so draftModel must be '
      'null.',
    );
  }
  if (draftStrategy == null &&
      (config.draftTokenMin != null ||
          config.minProbability != null ||
          config.draftSplitProbability != null ||
          draftModelPath != null)) {
    throw LlamaUnsupportedException(
      'WebGPU n-gram speculative decoding uses token history and does not '
      'support draftTokenMin, minProbability, draftSplitProbability, or '
      'draftModel unless a draft-model strategy is also enabled, as on '
      'native llama.cpp.',
    );
  }

  final usesNgramCache = strategies.contains(
    SpeculativeDecodingStrategy.ngramCache,
  );
  for (final cachePath in <String?>[
    config.ngramCacheStaticPath,
    config.ngramCacheDynamicPath,
  ]) {
    if (cachePath != null && cachePath.trim().isEmpty) {
      throw ArgumentError.value(
        cachePath,
        'ngramCachePath',
        'must be null or a non-empty URL',
      );
    }
  }

  final ngramSizeN = config.ngramSizeN ?? config.ngramSize;
  for (final (name, value, max) in <(String, int?, int)>[
    ('draftTokenMax', config.draftTokenMax, _maxInt32),
    ('draftTokenMin', config.draftTokenMin, _maxInt32),
    ('ngramSizeN', ngramSizeN, _maxNgramSize),
    ('ngramSizeM', config.ngramSizeM, _maxNgramSize),
    ('ngramMinHits', config.ngramMinHits, _maxNgramSize),
    ('ngramMatch', config.ngramMatch, _maxNgramSize),
    ('ngramTokenMin', config.ngramTokenMin, _maxInt32),
    ('ngramTokenMax', config.ngramTokenMax, _maxInt32),
  ]) {
    if (value != null && value > max) {
      throw RangeError.range(
        value,
        null,
        max,
        name,
        'exceeds the WebGPU bridge limit',
      );
    }
  }

  final draftTokenMax = _resolveDraftTokenMax(strategies, config);
  final draftTokenMin = config.draftTokenMin ?? 0;
  if (draftTokenMin < 0 || draftTokenMin > draftTokenMax) {
    throw RangeError.value(
      draftTokenMin,
      'draftTokenMin',
      'must be between zero and draftTokenMax for WebGPU speculative decoding',
    );
  }
  final ngramTokenMin = config.ngramTokenMin;
  final ngramTokenMax = config.ngramTokenMax;
  if (ngramTokenMin != null &&
      ngramTokenMax != null &&
      ngramTokenMin > ngramTokenMax) {
    throw RangeError.value(
      ngramTokenMin,
      'ngramTokenMin',
      'must be less than or equal to ngramTokenMax',
    );
  }

  final ngramCacheStatic = usesNgramCache ? config.ngramCacheStaticPath : null;
  final ngramCacheDynamic = usesNgramCache
      ? config.ngramCacheDynamicPath
      : null;
  return WebGpuSpeculativeRequest._(
    options: WebGpuSpeculativeDecodingOptions(
      strategies: <JSString>[
        for (final strategy in strategies)
          webGpuSpeculativeStrategyNames[strategy]!.toJS,
      ].toJS,
      draftTokenMax: config.draftTokenMax,
      draftTokenMin: config.draftTokenMin,
      minProbability: config.minProbability,
      draftSplitProbability: config.draftSplitProbability,
      ngramSizeN: ngramSizeN,
      ngramSizeM: config.ngramSizeM,
      ngramMinHits: config.ngramMinHits,
      ngramMatch: config.ngramMatch,
      ngramTokenMin: ngramTokenMin,
      ngramTokenMax: ngramTokenMax,
      ngramCacheStatic: ngramCacheStatic,
      ngramCacheDynamic: ngramCacheDynamic,
    ),
    draftStrategy: needsDraftModel ? draftStrategy : null,
    draftModelUrl: needsDraftModel ? draftModelPath : null,
    sourceUrls: <String>[
      ?(needsDraftModel ? draftModelPath : null),
      ?ngramCacheStatic,
      ?ngramCacheDynamic,
    ],
  );
}

/// Native llama.cpp's per-step draft maximum for [strategies].
int _resolveDraftTokenMax(
  List<SpeculativeDecodingStrategy> strategies,
  SpeculativeDecodingConfig config,
) {
  var max = 0;
  for (final strategy in strategies) {
    max = math.max(max, switch (strategy) {
      SpeculativeDecodingStrategy.ngramSimple ||
      SpeculativeDecodingStrategy.ngramMapK ||
      SpeculativeDecodingStrategy.ngramMapK4v => config.ngramSizeM ?? 48,
      SpeculativeDecodingStrategy.ngramMod =>
        config.ngramTokenMax ?? config.draftTokenMax ?? 64,
      SpeculativeDecodingStrategy.ngramCache => config.draftTokenMax ?? 8,
      SpeculativeDecodingStrategy.backendDefault => config.draftTokenMax ?? 64,
      _ => config.draftTokenMax ?? 3,
    });
  }
  return max == 0 ? 64 : max;
}

/// Returns the [LlamaException] for a bridge [error] that ended a speculative
/// completion, with the [sourceUrls] redacted.
///
/// A request the loaded models cannot run is a [LlamaUnsupportedException],
/// as native llama.cpp reports a speculative session it cannot start.
LlamaException webGpuSpeculativeCompletionError(
  Object error,
  Iterable<String> sourceUrls,
) {
  final classified = webGpuBridgeRequestError(error, sourceUrls: sourceUrls);
  if (classified != null) return classified;
  final message = webGpuBridgeErrorText(error, sourceUrls: sourceUrls);
  const unsupported = <String>[
    "needs the model's MTP head",
    'needs a draft model',
    "draft model's architecture is",
    'with recurrent state',
    'rollback snapshots',
    'target layers do not match',
    'exceed the context size',
    'speculative draft context',
    'Failed to initialize speculative decoding',
  ];
  if (unsupported.any(message.contains)) {
    return LlamaUnsupportedException(message);
  }
  return LlamaInferenceException(
    'WebGPU speculative generation failed.',
    message,
  );
}

/// The draft model the bridge holds for draft-model speculative decoding.
///
/// The bridge holds one draft, which a model load or dispose frees, and
/// reports a draft strategy only while a draft that runs it is loaded. Like
/// native llama.cpp's draft cache, the draft stays loaded between
/// generations.
class WebGpuDraftModel {
  String? _url;

  /// Loads the draft at [url], unless this loaded it last and the bridge
  /// still reports [strategy], and checks that the bridge can run [strategy]
  /// with it.
  ///
  /// Throws [LlamaModelException] when the draft cannot be fetched or loaded,
  /// [LlamaStateException] when the bridge refuses the load for its state,
  /// and [LlamaUnsupportedException] when the bridge rejects the draft for the
  /// loaded model's hidden size, or cannot run [strategy] with the draft,
  /// which it then unloads. Aborting [signal] cancels the load.
  Future<void> prepare(
    LlamaWebGpuBridge bridge,
    String url,
    SpeculativeDecodingStrategy strategy, {
    JSAny? signal,
  }) async {
    final name = webGpuSpeculativeStrategyNames[strategy]!;
    url = webGpuDocumentUrl(url);
    if (_url == url && await _reports(bridge, name)) return;
    final architecture = await _load(bridge, url, signal);
    if (await _reports(bridge, name)) return;
    try {
      await _settle(bridge.unloadDraftModel());
    } catch (_) {
      // The rejection below names the cause; the next load replaces the draft.
    }
    _url = null;
    throw LlamaUnsupportedException(
      'WebGPU $name cannot run with the draft model, whose architecture is '
      '${architecture ?? 'unknown'}: the bridge reports $name unsupported '
      'for it.',
    );
  }

  Future<String?> _load(
    LlamaWebGpuBridge bridge,
    String url,
    JSAny? signal,
  ) async {
    _url = null;
    final JSAny? raw;
    try {
      raw = await _settle(
        bridge.loadDraftModel(
          url,
          WebGpuDraftModelLoadOptions(
            useCache: !hasPersistentCacheSensitiveUrlParts(url),
            signal: signal,
          ),
        ),
      );
    } catch (error) {
      final message = webGpuBridgeErrorText(error, sourceUrls: <String>[url]);
      if (message.startsWith('No model loaded') ||
          message.contains('Bridge has been disposed') ||
          message.contains('during active generation')) {
        throw LlamaStateException(message);
      }
      if (message.contains('reads target hidden states')) {
        throw LlamaUnsupportedException(message);
      }
      throw LlamaModelException(
        'The Web runtime could not load the speculative draft model.',
        message,
      );
    }
    _url = url;
    if (raw == null || !raw.isA<JSObject>()) return null;
    final architecture = (raw as WebGpuDraftModelInfo).architecture;
    return architecture != null && architecture.isA<JSString>()
        ? (architecture as JSString).toDart
        : null;
  }

  static Future<bool> _reports(LlamaWebGpuBridge bridge, String name) async {
    try {
      final raw = await _settle(bridge.getCompletionCapabilities());
      if (raw == null || !raw.isA<JSObject>()) return false;
      final flags = (raw as WebGpuCompletionCapabilities).speculativeDecoding;
      if (flags == null || !flags.isA<JSObject>()) return false;
      final value = (flags as JSObject).getProperty<JSAny?>(name.toJS);
      return value != null &&
          value.isA<JSBoolean>() &&
          (value as JSBoolean).toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<JSAny?> _settle(JSAny? value) async {
    if (value != null && value.isA<JSPromise>()) {
      return (value as JSPromise<JSAny?>).toDart;
    }
    return value;
  }
}
