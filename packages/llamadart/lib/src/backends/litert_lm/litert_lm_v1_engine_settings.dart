part of 'litert_lm_v1_runtime.dart';

typedef _EngineActionN = Int Function(Pointer<Void>);
typedef _EngineActionD = int Function(Pointer<Void>);

/// Resolved engine options for internal C API 1.0 preparation only.
///
/// This does not select the public adapter, discover devices, lease caches or
/// qualify media/backends. Callers resolve [ComputeDevice.auto] before this
/// boundary. Nullable options preserve runtime defaults; ModelParams' automatic
/// thread count (zero) must be resolved to null, not forwarded as an override.
final class LiteRtLmV1EngineSettings {
  /// Uses the service defaults: context 4096, benchmarks on, speculation off.
  const LiteRtLmV1EngineSettings({
    this.backend = ComputeDevice.cpu,
    this.visionBackend,
    this.audioBackend,
    this.contextSize = 4096,
    this.numberOfThreads,
    this.cacheDir,
    this.activationDataType,
    this.prefillChunkSize,
    this.parallelFileSectionLoading,
    this.dispatchLibDir,
    this.enableBenchmark = true,
    this.prefillTokens,
    this.speculativeDecoding = false,
    this.maxNumImages,
  });

  /// Explicit main backend; auto is refused without guessing a platform default.
  final ComputeDevice backend;

  /// Optional executor backends; null leaves the corresponding executor unset.
  final ComputeDevice? visionBackend, audioBackend;

  /// Positive signed C-int context capacity, as ModelParams.contextSize.
  final int contextSize;

  /// Explicit positive CPU threads; null preserves native automatic selection.
  final int? numberOfThreads;

  /// Optional resolved cache path; no directory creation or lease is performed.
  final String? cacheDir;

  /// Override using the maintained ModelParams activation enum wire values.
  final LiteRtLmActivationDataType? activationDataType;

  /// Positive CPU dynamic-model prefill chunk override, or native default.
  final int? prefillChunkSize;

  /// Null keeps upstream parallel loading; false explicitly disables it.
  final bool? parallelFileSectionLoading;

  /// Optional NPU dispatch-library directory; refused on other main backends.
  final String? dispatchLibDir;

  /// Enables measured prefill/decode metrics, as the production service does.
  final bool enableBenchmark;

  /// Optional positive benchmark prefill count, not a response token limit.
  final int? prefillTokens;

  /// Engine mode off/on; adaptive and per-session overrides remain separate.
  final bool speculativeDecoding;

  /// Unsupported enforced capacity for the legacy engine. The service's
  /// history-derived preparation hint is resolved before this boundary.
  final int? maxNumImages;

  void _validate(String modelPath) {
    for (final value in [modelPath, ?cacheDir, ?dispatchLibDir]) {
      if (value.trim().isEmpty || value.contains('\u0000')) {
        throw LlamaArgumentException(
          'C API 1.0 engine paths must be nonempty without NUL.',
        );
      }
    }
    for (final value in [
      contextSize,
      ?numberOfThreads,
      ?prefillChunkSize,
      ?prefillTokens,
      ?maxNumImages,
    ]) {
      if (value <= 0 || value > 0x7fffffff) {
        throw LlamaArgumentException(
          'C API 1.0 engine counts must be positive signed C ints.',
        );
      }
    }
    if ([backend, visionBackend, audioBackend].contains(ComputeDevice.auto)) {
      throw LlamaUnsupportedException(
        'C API 1.0 engine preparation requires resolved CPU/GPU/NPU backends; auto selection belongs to the service.',
      );
    }
    if (backend != ComputeDevice.cpu &&
        (numberOfThreads != null || prefillChunkSize != null)) {
      throw LlamaUnsupportedException(
        'C API 1.0 numberOfThreads and prefillChunkSize require the CPU backend; the native setters otherwise return success without applying them.',
      );
    }
    if (dispatchLibDir != null && backend != ComputeDevice.npu) {
      throw LlamaUnsupportedException(
        'C API 1.0 dispatchLibDir requires the NPU backend.',
      );
    }
    if (speculativeDecoding && backend == ComputeDevice.npu) {
      throw LlamaUnsupportedException(
        'C API 1.0 speculative decoding requires CPU or GPU; the NPU backend decodes without speculation.',
      );
    }
    if (maxNumImages != null) {
      throw LlamaUnsupportedException(
        'C API 1.0 maxNumImages is a legacy-engine-only capacity; the selected advanced engine accepts actual image inputs dynamically and cannot enforce this capacity.',
      );
    }
    if (prefillTokens != null && !enableBenchmark) {
      throw LlamaArgumentException(
        'C API 1.0 prefillTokens requires enableBenchmark; the native prefill setter enables benchmark parameters.',
      );
    }
  }
}

const _engineSettingsSymbols = <String>[
  'litert_lm_engine_settings_enable_benchmark',
  'litert_lm_engine_settings_set_parallel_file_section_loading',
  'litert_lm_engine_settings_set_activation_data_type',
  'litert_lm_engine_settings_set_prefill_chunk_size',
  'litert_lm_engine_settings_set_num_prefill_tokens',
  'litert_lm_engine_settings_set_litert_dispatch_lib_dir',
  'litert_lm_speculative_decoding_config_create',
  'litert_lm_speculative_decoding_config_delete',
  'litert_lm_speculative_decoding_config_set_mode',
  'litert_lm_engine_settings_set_speculative_decoding_config',
];

extension _V1EngineSettingsCalls on LiteRtLmV1Runtime {
  void _applyEngineSettings(
    Pointer<Void> settings,
    LiteRtLmV1EngineSettings options,
    Pointer<Utf8> Function(String?) owned,
  ) {
    void integer(String suffix, int value) => _check(
      _library.lookupFunction<_SetIntN, _SetIntD>(
        'litert_lm_engine_settings_$suffix',
      )(settings, value),
      suffix,
    );
    if (options.enableBenchmark) {
      _check(
        _library.lookupFunction<_EngineActionN, _EngineActionD>(
          'litert_lm_engine_settings_enable_benchmark',
        )(settings),
        'enable_benchmark',
      );
    }
    if (options.parallelFileSectionLoading case final parallel?) {
      _check(
        _library.lookupFunction<_SetBoolN, _SetBoolD>(
          'litert_lm_engine_settings_set_parallel_file_section_loading',
        )(settings, parallel),
        'set_parallel_file_section_loading',
      );
    }
    if (options.activationDataType case final activation?) {
      integer('set_activation_data_type', activation.nativeValue);
    }
    if (options.prefillChunkSize case final chunk?) {
      integer('set_prefill_chunk_size', chunk);
    }
    if (options.prefillTokens case final tokens?) {
      integer('set_num_prefill_tokens', tokens);
    }
    if (options.dispatchLibDir case final dispatch?) {
      _check(
        _library.lookupFunction<_SetStringN, _SetStringD>(
          'litert_lm_engine_settings_set_litert_dispatch_lib_dir',
        )(settings, owned(dispatch)),
        'set_litert_dispatch_lib_dir',
      );
    }
    Pointer<Void> speculative = nullptr;
    try {
      speculative = _create(
        'speculative_decoding_config_create',
        _library.lookupFunction<_CreateN, _CreateD>(
          'litert_lm_speculative_decoding_config_create',
        ),
      );
      _check(
        _library.lookupFunction<_SetIntN, _SetIntD>(
          'litert_lm_speculative_decoding_config_set_mode',
        )(speculative, options.speculativeDecoding ? 1 : 0),
        'speculative_decoding_config_set_mode',
      );
      _check(
        _library.lookupFunction<_SetPointerN, _SetPointerD>(
          'litert_lm_engine_settings_set_speculative_decoding_config',
        )(settings, speculative),
        'set_speculative_decoding_config',
      );
    } finally {
      if (speculative != nullptr) {
        _library.lookupFunction<_DeleteN, _DeleteD>(
          'litert_lm_speculative_decoding_config_delete',
        )(speculative);
      }
    }
  }
}
