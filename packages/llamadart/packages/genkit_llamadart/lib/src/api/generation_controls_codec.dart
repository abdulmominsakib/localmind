import 'package:llamadart/llamadart.dart' as llama;

Never _invalid(String field, String expected) =>
    throw FormatException('$field $expected.');

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    _invalid(field, 'must be an object');
  }
  return value.cast<String, dynamic>();
}

void _keys(Map<String, dynamic> map, Set<String> allowed, String field) {
  if (map.keys.any((key) => !allowed.contains(key))) {
    _invalid(field, 'contains unsupported fields');
  }
}

int? controlInt(Map<String, dynamic> map, String field, {int minimum = 0}) {
  final value = map[field];
  if (value == null) return null;
  if (value is! num ||
      !value.isFinite ||
      value != value.roundToDouble() ||
      value < minimum ||
      value > 2147483647) {
    _invalid(field, 'must be an integer from $minimum through 2147483647');
  }
  return value.toInt();
}

double? controlDouble(
  Map<String, dynamic> map,
  String field, {
  bool probability = false,
}) {
  final value = map[field];
  if (value == null) return null;
  if (value is! num ||
      !value.isFinite ||
      (probability && (value < 0 || value > 1))) {
    _invalid(
      field,
      probability
          ? 'must be a finite probability from 0 through 1'
          : 'must be finite numeric',
    );
  }
  return value.toDouble();
}

bool? controlBool(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value == null || value is bool) return value as bool?;
  _invalid(field, 'must be boolean');
}

String? _string(
  Map<String, dynamic> map,
  String field, {
  bool nonempty = false,
}) {
  final value = map[field];
  if (value == null) return null;
  if (value is! String || (nonempty && value.trim().isEmpty)) {
    _invalid(
      field,
      nonempty ? 'must be a nonempty string' : 'must be a string',
    );
  }
  return value;
}

String? _path(Map<String, dynamic> map, String field) {
  final value = _string(map, field, nonempty: true);
  if (value != null &&
      (value.contains('://') || value.contains('?') || value.contains('#'))) {
    _invalid(field, 'must be a local path without URL or query syntax');
  }
  return value;
}

T? _enum<T extends Enum>(
  Map<String, dynamic> map,
  String field,
  List<T> values,
) {
  final value = map[field];
  if (value == null) return null;
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  _invalid(field, 'must be a supported enum name');
}

llama.ThinkingBudget? thinkingBudgetFromJson(Object? value) {
  if (value == null) return null;
  final map = _object(value, 'thinkingBudget');
  _keys(map, {
    'maxTokens',
    'startTag',
    'endTag',
    'forcedMessage',
  }, 'thinkingBudget');
  final maxTokens = controlInt(map, 'maxTokens');
  if (maxTokens == null) _invalid('thinkingBudget.maxTokens', 'is required');
  return llama.ThinkingBudget(
    maxTokens: maxTokens,
    startTag: _string(map, 'startTag', nonempty: true),
    endTag: _string(map, 'endTag', nonempty: true),
    forcedMessage: _string(map, 'forcedMessage'),
  );
}

Map<String, dynamic> thinkingBudgetToJson(llama.ThinkingBudget budget) {
  final map = <String, dynamic>{
    'maxTokens': budget.maxTokens,
    if (budget.startTag != null) 'startTag': budget.startTag,
    if (budget.endTag != null) 'endTag': budget.endTag,
    if (budget.forcedMessage != null) 'forcedMessage': budget.forcedMessage,
  };
  thinkingBudgetFromJson(map);
  return map;
}

const _specKeys = {
  'strategies',
  'draftTokenMax',
  'draftTokenMin',
  'minProbability',
  'draftSplitProbability',
  'draftMicroBatchSize',
  'draftModel',
  'draftModelDownload',
  'ngramSize',
  'ngramSizeN',
  'ngramSizeM',
  'ngramMinHits',
  'ngramMatch',
  'ngramTokenMin',
  'ngramTokenMax',
  'ngramCacheStaticPath',
  'ngramCacheDynamicPath',
};

llama.SpeculativeDecodingConfig? speculativeConfigFromJson(Object? value) {
  if (value == null) return null;
  final map = _object(value, 'speculativeDecodingConfig');
  _keys(map, _specKeys, 'speculativeDecodingConfig');
  final names = map['strategies'];
  if (names is! List || names.isEmpty) {
    _invalid('strategies', 'must be a nonempty array of enum names');
  }
  final strategies = names
      .map(
        (name) =>
            _enum(
              {'strategy': name},
              'strategy',
              llama.SpeculativeDecodingStrategy.values,
            ) ??
            _invalid('strategy', 'must be a supported enum name'),
      )
      .toList(growable: false);
  if (strategies.toSet().length != strategies.length ||
      (strategies.length > 1 &&
          strategies.contains(
            llama.SpeculativeDecodingStrategy.backendDefault,
          ))) {
    _invalid(
      'strategies',
      'must be distinct and cannot mix backendDefault with another strategy',
    );
  }
  final config = llama.SpeculativeDecodingConfig(
    strategy: strategies.first,
    strategies: strategies,
    draftTokenMax: controlInt(map, 'draftTokenMax'),
    draftTokenMin: controlInt(map, 'draftTokenMin'),
    minProbability: controlDouble(map, 'minProbability', probability: true),
    draftSplitProbability: controlDouble(
      map,
      'draftSplitProbability',
      probability: true,
    ),
    draftMicroBatchSize: controlInt(map, 'draftMicroBatchSize', minimum: 1),
    draftModel: map['draftModel'] == null
        ? null
        : _sourceFromJson(map['draftModel']),
    draftModelDownload: map['draftModelDownload'] == null
        ? llama.ModelLoadOptions.defaults
        : _downloadFromJson(map['draftModelDownload']),
    ngramSize: controlInt(map, 'ngramSize', minimum: 1),
    ngramSizeN: controlInt(map, 'ngramSizeN', minimum: 1),
    ngramSizeM: controlInt(map, 'ngramSizeM', minimum: 1),
    ngramMinHits: controlInt(map, 'ngramMinHits', minimum: 1),
    ngramMatch: controlInt(map, 'ngramMatch', minimum: 1),
    ngramTokenMin: controlInt(map, 'ngramTokenMin'),
    ngramTokenMax: controlInt(map, 'ngramTokenMax'),
    ngramCacheStaticPath: _path(map, 'ngramCacheStaticPath'),
    ngramCacheDynamicPath: _path(map, 'ngramCacheDynamicPath'),
  );
  for (final pair in [
    (config.draftTokenMin, config.draftTokenMax),
    (config.ngramTokenMin, config.ngramTokenMax),
  ]) {
    if (pair.$1 != null && pair.$2 != null && pair.$1! > pair.$2!) {
      _invalid('speculativeDecodingConfig', 'minimum cannot exceed maximum');
    }
  }
  if (config.draftModel == null && map['draftModelDownload'] != null) {
    _invalid('draftModelDownload', 'requires draftModel');
  }
  return config;
}

Map<String, dynamic> speculativeConfigToJson(
  llama.SpeculativeDecodingConfig config,
) {
  if (config.draftModelPath != null && config.draftModel == null) {
    _invalid(
      'draftModelPath',
      'is deprecated; use draftModel with ModelSource.path',
    );
  }
  final options = config.draftModelDownload;
  if (options.bearerToken != null ||
      options.headers.isNotEmpty ||
      options.cancelToken != null) {
    _invalid(
      'draftModelDownload',
      'cannot contain authentication or cancellation tokens; download the draft before the Genkit request',
    );
  }
  if (config.draftModel == null &&
      (options.cachePolicy != llama.ModelCachePolicy.preferCached ||
          options.cacheDirectory != null ||
          options.sha256 != null ||
          !options.resume ||
          options.maxRetries != 3)) {
    _invalid('draftModelDownload', 'requires draftModel');
  }
  final map = <String, dynamic>{
    'strategies': config.effectiveStrategies.map((s) => s.name).toList(),
    if (config.draftTokenMax != null) 'draftTokenMax': config.draftTokenMax,
    if (config.draftTokenMin != null) 'draftTokenMin': config.draftTokenMin,
    if (config.minProbability != null) 'minProbability': config.minProbability,
    if (config.draftSplitProbability != null)
      'draftSplitProbability': config.draftSplitProbability,
    if (config.draftMicroBatchSize != null)
      'draftMicroBatchSize': config.draftMicroBatchSize,
    if (config.draftModel != null)
      'draftModel': _sourceToJson(config.draftModel!),
    if (config.draftModel != null)
      'draftModelDownload': {
        'cachePolicy': options.cachePolicy.name,
        if (options.cacheDirectory != null)
          'cacheDirectory': options.cacheDirectory,
        if (options.sha256 != null) 'sha256': options.sha256,
        'resume': options.resume,
        'maxRetries': options.maxRetries,
      },
    if (config.ngramSize != null) 'ngramSize': config.ngramSize,
    if (config.ngramSizeN != null) 'ngramSizeN': config.ngramSizeN,
    if (config.ngramSizeM != null) 'ngramSizeM': config.ngramSizeM,
    if (config.ngramMinHits != null) 'ngramMinHits': config.ngramMinHits,
    if (config.ngramMatch != null) 'ngramMatch': config.ngramMatch,
    if (config.ngramTokenMin != null) 'ngramTokenMin': config.ngramTokenMin,
    if (config.ngramTokenMax != null) 'ngramTokenMax': config.ngramTokenMax,
    if (config.ngramCacheStaticPath != null)
      'ngramCacheStaticPath': config.ngramCacheStaticPath,
    if (config.ngramCacheDynamicPath != null)
      'ngramCacheDynamicPath': config.ngramCacheDynamicPath,
  };
  speculativeConfigFromJson(map);
  return map;
}

llama.ModelSource _sourceFromJson(Object? value) {
  final map = _object(value, 'draftModel');
  _keys(map, {
    'kind',
    'path',
    'url',
    'repoId',
    'filePath',
    'revision',
    'fileName',
    'format',
  }, 'draftModel');
  final kind = _enum(map, 'kind', llama.ModelSourceKind.values);
  final format = _enum(map, 'format', llama.ModelFormat.values);
  String required(String key) =>
      _string(map, key, nonempty: true) ??
      _invalid('draftModel.$key', 'is required');
  try {
    switch (kind) {
      case llama.ModelSourceKind.path:
        _keys(map, {'kind', 'path', 'format'}, 'draftModel');
        final path = required('path');
        if (path.contains('://') || path.contains('?') || path.contains('#')) {
          _invalid(
            'draftModel.path',
            'must be a local path without URL or query syntax',
          );
        }
        return llama.ModelSource.path(path, format: format);
      case llama.ModelSourceKind.http:
        _keys(map, {'kind', 'url', 'fileName', 'format'}, 'draftModel');
        final uri = Uri.tryParse(required('url'));
        if (uri == null) _invalid('draftModel.url', 'must be a valid URL');
        if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
          _invalid(
            'draftModel.url',
            'cannot contain credentials, query or fragment; download the draft before the Genkit request',
          );
        }
        return llama.ModelSource.url(
          uri,
          fileName: _string(map, 'fileName', nonempty: true),
          format: format,
        );
      case llama.ModelSourceKind.huggingFace:
        _keys(map, {
          'kind',
          'repoId',
          'filePath',
          'revision',
          'fileName',
          'format',
        }, 'draftModel');
        return llama.ModelSource.huggingFace(
          repoId: required('repoId'),
          filePath: required('filePath'),
          revision: _string(map, 'revision', nonempty: true) ?? 'main',
          fileName: _string(map, 'fileName', nonempty: true),
          format: format,
        );
      case null:
        _invalid('draftModel.kind', 'is required');
    }
  } on ArgumentError {
    _invalid('draftModel', 'must be a valid model source');
  }
}

Map<String, dynamic> _sourceToJson(llama.ModelSource source) {
  if (source.kind == llama.ModelSourceKind.huggingFace &&
      source.url !=
          llama.ModelSource.huggingFace(
            repoId: source.repoId!,
            filePath: source.filePath!,
            revision: source.revision!,
            fileName: source.fileName,
            format: source.format,
          ).url) {
    _invalid(
      'draftModel',
      'cannot use a custom resolved URL; download the draft before the Genkit request',
    );
  }
  final map = <String, dynamic>{
    'kind': source.kind.name,
    if (source.format != null) 'format': source.format!.name,
    if (source.isLocal) 'path': source.path,
    if (source.kind == llama.ModelSourceKind.http) 'url': source.url.toString(),
    if (source.isRemote) 'fileName': source.fileName,
    if (source.kind == llama.ModelSourceKind.huggingFace) ...{
      'repoId': source.repoId,
      'filePath': source.filePath,
      'revision': source.revision,
    },
  };
  _sourceFromJson(map);
  return map;
}

llama.ModelLoadOptions _downloadFromJson(Object? value) {
  final map = _object(value, 'draftModelDownload');
  _keys(map, {
    'cachePolicy',
    'cacheDirectory',
    'sha256',
    'resume',
    'maxRetries',
  }, 'draftModelDownload');
  final policy =
      _enum(map, 'cachePolicy', llama.ModelCachePolicy.values) ??
      llama.ModelCachePolicy.preferCached;
  if (policy != llama.ModelCachePolicy.preferCached &&
      policy != llama.ModelCachePolicy.cacheOnly) {
    _invalid(
      'draftModelDownload.cachePolicy',
      'must be preferCached or cacheOnly',
    );
  }
  try {
    return llama.ModelLoadOptions(
      cachePolicy: policy,
      cacheDirectory: _path(map, 'cacheDirectory'),
      sha256: _string(map, 'sha256', nonempty: true),
      resume: controlBool(map, 'resume') ?? true,
      maxRetries: controlInt(map, 'maxRetries') ?? 3,
    );
  } on ArgumentError {
    _invalid('draftModelDownload', 'must contain valid download options');
  }
}

void validateGenerationControls({
  double? presencePenalty,
  int? streamBatchTokenThreshold,
  int? streamBatchByteThreshold,
}) {
  controlDouble({'presencePenalty': presencePenalty}, 'presencePenalty');
  controlInt(
    {'streamBatchTokenThreshold': streamBatchTokenThreshold},
    'streamBatchTokenThreshold',
    minimum: 1,
  );
  controlInt(
    {'streamBatchByteThreshold': streamBatchByteThreshold},
    'streamBatchByteThreshold',
    minimum: 1,
  );
}
