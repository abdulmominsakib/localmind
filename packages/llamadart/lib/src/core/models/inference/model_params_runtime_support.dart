import '../../engine/engine_observer.dart';
import '../../exceptions.dart';
import '../config/flash_attention.dart';
import '../config/kv_cache_type.dart';
import 'model_params.dart';

/// The fields of [params] set away from their defaults that [runtime] does
/// not apply, natively or on the Web when [web] is true, each as a rejection
/// message names it.
///
/// [ModelParams.liteRtLmEmbeddingEngine] and LiteRT-LM LoRA limits are left
/// to the checks that already reject them with their own guidance.
List<String> modelParamsUnsupportedBy(
  ModelParams params,
  LlamaRuntime runtime, {
  required bool web,
}) => switch (runtime) {
  LlamaRuntime.llamaCpp => [
    ..._liteRtLmOnlyFields(params),
    if (web) ...[
      ..._gpuDeviceFields(params),
      if (!params.useMmap) 'useMmap=false',
      if (params.useMlock) 'useMlock',
      ..._moeExpertFields(params),
    ] else ...[
      if (params.preferMemory64 != null) 'preferMemory64',
      if (params.modelBytesHint != null) 'modelBytesHint',
    ],
  ],
  LlamaRuntime.liteRtLm => [
    if (params.contextSize <= 0) 'contextSize=${params.contextSize}',
    if (params.gpuLayers > 0 && params.gpuLayers != ModelParams.maxGpuLayers)
      'gpuLayers=${params.gpuLayers}',
    if (params.splitMode != ModelSplitMode.layer) 'splitMode',
    if (params.mainGpu != 0) 'mainGpu',
    ..._gpuDeviceFields(params),
    if (web) ...[
      if (params.loras.isNotEmpty) 'loras',
      ..._liteRtLmNativeOnlyFields(params),
      if (params.numberOfThreads != 0) 'numberOfThreads',
    ],
    if (params.numberOfThreadsBatch != 0) 'numberOfThreadsBatch',
    if (params.batchSize > 0) 'batchSize',
    if (params.microBatchSize > 0) 'microBatchSize',
    if (params.maxParallelSequences != 1) 'maxParallelSequences',
    if (params.speculativeRollbackTokenMax != 0) 'speculativeRollbackTokenMax',
    if (!params.useMmap) 'useMmap=false',
    if (params.useMlock) 'useMlock',
    if (params.loadMtp) 'loadMtp',
    if (params.flashAttention != FlashAttention.auto) 'flashAttention',
    if (params.cacheTypeK != KvCacheType.f16) 'cacheTypeK',
    if (params.cacheTypeV != KvCacheType.f16) 'cacheTypeV',
    if (params.kvUnified != null) 'kvUnified',
    if (params.ropeFrequencyBase != null) 'ropeFrequencyBase',
    if (params.ropeFrequencyScale != null) 'ropeFrequencyScale',
    ..._moeExpertFields(params),
    if (params.preferMemory64 != null) 'preferMemory64',
    if (params.modelBytesHint != null) 'modelBytesHint',
  ],
};

List<String> _moeExpertFields(ModelParams params) => [
  if (params.cpuMoeLayers != 0) 'cpuMoeLayers',
  if (params.moeCacheBytes != 0) 'moeCacheBytes',
];

/// Throws [LlamaUnsupportedException] naming each field of [params] that
/// [runtime] would not apply, natively or on the Web when [web] is true,
/// instead of loading the model without it.
void checkModelParamsSupportedBy(
  ModelParams params,
  LlamaRuntime runtime, {
  required bool web,
}) {
  checkModelParamsTypeFor(params, runtime);
  final unsupported = modelParamsUnsupportedBy(params, runtime, web: web);
  if (unsupported.isEmpty) return;
  throw LlamaUnsupportedException(
    unsupportedModelParamsMessage(unsupported, runtime, web: web),
  );
}

/// Throws [LlamaUnsupportedException] when [params] is a runtime-specific
/// subtype for another runtime than [runtime].
void checkModelParamsTypeFor(ModelParams params, LlamaRuntime runtime) {
  final (type, typeRuntime, model) = switch (params) {
    LlamaCppModelParams() => (
      'LlamaCppModelParams',
      LlamaRuntime.llamaCpp,
      'llama.cpp (GGUF)',
    ),
    LiteRtLmModelParams() => (
      'LiteRtLmModelParams',
      LlamaRuntime.liteRtLm,
      'LiteRT-LM (.litertlm)',
    ),
    _ => (null, null, null),
  };
  if (type == null || typeRuntime == runtime) return;
  final (other, otherModel) = runtime == LlamaRuntime.liteRtLm
      ? ('LiteRtLmModelParams', 'LiteRT-LM (.litertlm)')
      : ('LlamaCppModelParams', 'llama.cpp (GGUF)');
  throw LlamaUnsupportedException(
    '$type configures $model models, but this model runs on $otherModel. '
    'Use $other.',
  );
}

/// The message of the [LlamaUnsupportedException] for the [unsupported]
/// fields of a load in [runtime], natively or on the Web when [web] is true.
String unsupportedModelParamsMessage(
  List<String> unsupported,
  LlamaRuntime runtime, {
  required bool web,
}) {
  final fields = unsupported.join(', ');
  return switch ((runtime, web)) {
    (LlamaRuntime.llamaCpp, false) =>
      'llama.cpp does not apply these ModelParams natively: $fields. The '
          'liteRtLm* fields apply only to LiteRT-LM (.litertlm) models, and '
          'preferMemory64 and modelBytesHint only to llama.cpp on the Web. '
          'Leave them unset for this model.',
    (LlamaRuntime.llamaCpp, true) =>
      'llama.cpp on the Web does not apply these ModelParams: $fields. The '
          'liteRtLm* fields apply only to LiteRT-LM (.litertlm) models, and '
          'the Web runtime neither memory-maps nor locks model weights nor '
          'keeps MoE experts in host memory. Leave them unset for this model.',
    (LlamaRuntime.liteRtLm, false) =>
      'LiteRtLmBackend does not support llama.cpp-specific ModelParams: '
          '$fields. Supported LiteRT-LM load options are contextSize, '
          'chatTemplate, device or the deprecated liteRtLmBackend for '
          'explicit CPU/GPU/NPU selection, preferredBackend, all-or-CPU '
          'gpuLayers hints, numberOfThreads, and the LiteRT-LM options of '
          'LiteRtLmModelParams '
          '(liteRtLm* fields on ModelParams).',
    (LlamaRuntime.liteRtLm, true) =>
      'LiteRtLmBackend web does not support these native or '
          'llama.cpp-specific ModelParams: $fields. Supported LiteRT-LM web '
          'load options are contextSize, chatTemplate, device or the '
          'deprecated liteRtLmBackend for CPU/GPU selection, '
          'preferredBackend, and all-or-CPU gpuLayers hints.',
  };
}

/// The name of the type [params] was built with, as messages name it.
String modelParamsTypeName(ModelParams params) => switch (params) {
  LlamaCppModelParams() => 'LlamaCppModelParams',
  LiteRtLmModelParams() => 'LiteRtLmModelParams',
  _ => 'ModelParams',
};

/// The LiteRT-LM option [field], a `liteRtLm*` field of [ModelParams], as
/// [params] spells it: without the prefix on [LiteRtLmModelParams].
String liteRtLmOptionName(ModelParams params, String field) =>
    params is LiteRtLmModelParams
    ? '${field[8].toLowerCase()}${field.substring(9)}'
    : field;

List<String> _liteRtLmOnlyFields(ModelParams params) => [
  if (params.liteRtLmBackend != LiteRtLmBackendPreference.auto)
    'liteRtLmBackend',
  ..._liteRtLmNativeOnlyFields(params),
];

List<String> _liteRtLmNativeOnlyFields(ModelParams params) => [
  for (final (field, isSet) in [
    ('liteRtLmActivationDataType', params.liteRtLmActivationDataType != null),
    ('liteRtLmPrefillChunkSize', params.liteRtLmPrefillChunkSize != null),
    (
      'liteRtLmParallelFileSectionLoading',
      params.liteRtLmParallelFileSectionLoading != null,
    ),
    ('liteRtLmDispatchLibDir', params.liteRtLmDispatchLibDir != null),
    ('liteRtLmCacheDir', params.liteRtLmCacheDir != null),
    (
      'liteRtLmMaxProgramCacheBytes',
      params.liteRtLmMaxProgramCacheBytes != null,
    ),
  ])
    if (isSet) liteRtLmOptionName(params, field),
];

List<String> _gpuDeviceFields(ModelParams params) => [
  if (params.gpuDevices != null) 'gpuDevices',
  if (params.tensorSplit != null) 'tensorSplit',
];
