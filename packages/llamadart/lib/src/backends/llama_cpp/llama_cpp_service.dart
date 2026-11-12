import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../backend.dart';
import '../isolate_shutdown_releases.dart';
import '../windows_runtime_libraries.dart';
import '../../core/decision/decision_decoder.dart';
import '../../core/exceptions.dart';
import '../../core/llama_logger.dart';
import '../../core/models/chat/chat_message.dart';
import '../../core/models/chat/chat_role.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/compute_device.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/gpu_device_info.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/diagnostics/model_file_type.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/gpu_layer_count.dart';
import '../../core/template/media_placeholders.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/embedding.dart';
import '../../core/models/inference/reranking.dart';
import '../../core/models/inference/next_token_scores.dart';
import '../../core/models/inference/state_identity.dart';
import '../../core/template/chat_template_engine.dart';
import '../../hook/native_release_pins.dart';
import '../../platform/io/ios_simulator.dart';
import 'build_identity.dart';
import 'decision_head.dart';
import 'exit_teardown_api.dart';
import 'ggml_graph_api.dart';
import 'gpu_device_placement.dart';
import 'lazy_grammar_triggers.dart';
import 'load_device_selection.dart';
import 'reranking_classifier.dart';
import 'load_param_helpers.dart';
import 'safetensors.dart';
import 'stop_sequence_buffer.dart';
import 'token_batch.dart';
import 'bindings.dart';
import 'llama_cpp_raw_bindings.dart' as raw_bindings;
import 'moe_expert_placement.dart';
import 'mtmd_chunk_eval.dart';
import 'native_barrier_api.dart';
import 'native_library_candidates.dart';
import 'native_owner_api.dart';
import 'sampled_token_validation.dart';
import 'vulkan_device_probe.dart';

part 'library_loading.dart';
part 'multimodal_embedding.dart';
part 'native_signatures.dart';
part 'reranking.dart';
part 'startup_diagnostics.dart';

const _llamadartWrapperAssetId = 'package:llamadart/llamadart_wrapper';
final int _nativeStatusException =
    llama_dart_status.LLAMA_DART_STATUS_EXCEPTION.value;
final Pointer<NativeFinalizerFunction> _samplerFreeAddress =
    Native.addressOf<NativeFunction<Void Function(Pointer<llama_sampler>)>>(
      llama_sampler_free,
    ).cast();

final RegExp _linuxLlamadartProcMapsPattern = RegExp(
  r'/libllamadart\.so(?:\.\d+)?$',
);

const int _maxLlamaCppReasoningBudgetTokens = 0x7fffffff;
const String _minimumDsparkNativeTag = 'b10356';

/// llama.cpp's DFlash block size when a draft model has no `dflash.block_size`.
const int _llamaCppDefaultDflashBlockSize = 16;

/// A draft context's micro-batch size, and whether it is inherited from the
/// target context because `draftMicroBatchSize` is unset.
typedef _DraftMicroBatch = ({int size, bool inherited});

LlamaArgumentException _draftMicroBatchTooSmall(
  _DraftMicroBatch microBatch,
  String requirement,
) {
  final size = microBatch.size;
  return LlamaArgumentException(
    microBatch.inherited
        ? 'ModelParams.microBatchSize (resolved to $size; the draft context '
              'inherits it while SpeculativeDecodingConfig.draftMicroBatchSize '
              'is unset) must be at least $requirement'
        : 'SpeculativeDecodingConfig.draftMicroBatchSize ($size) must be at '
              'least $requirement',
    name: microBatch.inherited ? 'microBatchSize' : 'draftMicroBatchSize',
    invalidValue: size,
  );
}

const String _draftBlockRequirement =
    'for llama.cpp draft-dflash and draft-dspark, which decode a whole draft '
    'block in one micro-batch.';

class _LlamaCppThinkingBudgetConfig {
  const _LlamaCppThinkingBudgetConfig({
    required this.maxTokens,
    required this.startTag,
    required this.endTag,
    required this.forcedMessage,
  });

  final int maxTokens;
  final String startTag;
  final String endTag;
  final String forcedMessage;
}

class _LlamaCppSpeculativeConfig {
  const _LlamaCppSpeculativeConfig({
    required this.strategies,
    required this.typeNames,
    required this.draftTokenMax,
    required this.draftTokenMin,
    required this.minProbability,
    required this.draftSplitProbability,
    required this.draftMicroBatchSize,
    required this.draftModelPath,
    required this.ngramSizeN,
    required this.ngramSizeM,
    required this.ngramMinHits,
    required this.ngramMatch,
    required this.ngramTokenMin,
    required this.ngramTokenMax,
    required this.ngramCacheStaticPath,
    required this.ngramCacheDynamicPath,
  });

  final List<SpeculativeDecodingStrategy> strategies;
  final String typeNames;
  final int draftTokenMax;
  final int draftTokenMin;
  final double? minProbability;
  final double? draftSplitProbability;
  final int? draftMicroBatchSize;
  final String? draftModelPath;
  final int? ngramSizeN;
  final int? ngramSizeM;
  final int? ngramMinHits;
  final int? ngramMatch;
  final int? ngramTokenMin;
  final int? ngramTokenMax;
  final String? ngramCacheStaticPath;
  final String? ngramCacheDynamicPath;

  bool get hasDraftContextStrategy => strategies.any(
    (strategy) =>
        strategy == SpeculativeDecodingStrategy.draftSimple ||
        strategy == SpeculativeDecodingStrategy.draftEagle3 ||
        strategy == SpeculativeDecodingStrategy.mtp ||
        strategy == SpeculativeDecodingStrategy.draftDflash ||
        strategy == SpeculativeDecodingStrategy.draftDspark,
  );

  bool get requiresExternalDraftModel => strategies.any(
    (strategy) =>
        strategy == SpeculativeDecodingStrategy.draftSimple ||
        strategy == SpeculativeDecodingStrategy.draftEagle3 ||
        strategy == SpeculativeDecodingStrategy.draftDflash ||
        strategy == SpeculativeDecodingStrategy.draftDspark,
  );

  bool get usesMtp => strategies.contains(SpeculativeDecodingStrategy.mtp);

  bool get usesDspark =>
      strategies.contains(SpeculativeDecodingStrategy.draftDspark);

  bool get usesBlockDraft =>
      strategies.contains(SpeculativeDecodingStrategy.draftDflash) ||
      strategies.contains(SpeculativeDecodingStrategy.draftDspark);

  bool get suppressDraftProcessLogits => strategies.any(
    (strategy) =>
        strategy == SpeculativeDecodingStrategy.draftSimple ||
        strategy == SpeculativeDecodingStrategy.draftEagle3 ||
        strategy == SpeculativeDecodingStrategy.draftDflash ||
        strategy == SpeculativeDecodingStrategy.draftDspark,
  );
}

/// Copies [text] to native memory as NUL-terminated UTF-8.
///
/// Returns the pointer, which the caller frees with `malloc.free`, and the
/// byte length without the terminator. The length counts the bytes after an
/// embedded U+0000, where `Utf8.length` stops.
(Pointer<Utf8>, int) _toNativeUtf8WithLength(String text) {
  final bytes = utf8.encode(text);
  final pointer = malloc<Uint8>(bytes.length + 1);
  pointer.asTypedList(bytes.length + 1)
    ..setAll(0, bytes)
    ..[bytes.length] = 0;
  return (pointer.cast(), bytes.length);
}

/// Service responsible for managing Llama.cpp models and contexts.
///
/// This service handles the direct interaction with the native Llama.cpp library,
/// including loading models, creating contexts, managing memory, and running inference.
class LlamaCppService {
  static const bool _androidVulkanAllowKqvOffload = bool.fromEnvironment(
    'LLAMADART_ANDROID_VULKAN_ALLOW_KQV',
    defaultValue: false,
  );
  static const bool _androidVulkanAllowOpOffload = bool.fromEnvironment(
    'LLAMADART_ANDROID_VULKAN_ALLOW_OP_OFFLOAD',
    defaultValue: false,
  );
  static const bool _androidVulkanAllowFlashAttn = bool.fromEnvironment(
    'LLAMADART_ANDROID_VULKAN_ALLOW_FLASH_ATTN',
    defaultValue: false,
  );
  static const int _loadWithAlteredSearchPath = 0x00000008;
  static const int _semFailCriticalErrors = 0x0001;
  static const Map<SpeculativeDecodingStrategy, String>
  _llamaCppSpeculativeTypeNames = <SpeculativeDecodingStrategy, String>{
    SpeculativeDecodingStrategy.draftSimple: 'draft-simple',
    SpeculativeDecodingStrategy.draftEagle3: 'draft-eagle3',
    SpeculativeDecodingStrategy.mtp: 'draft-mtp',
    SpeculativeDecodingStrategy.draftDflash: 'draft-dflash',
    SpeculativeDecodingStrategy.draftDspark: 'draft-dspark',
    SpeculativeDecodingStrategy.ngramSimple: 'ngram-simple',
    SpeculativeDecodingStrategy.ngramMapK: 'ngram-map-k',
    SpeculativeDecodingStrategy.ngramMapK4v: 'ngram-map-k4v',
    SpeculativeDecodingStrategy.ngramMod: 'ngram-mod',
    SpeculativeDecodingStrategy.ngramCache: 'ngram-cache',
  };
  static const Set<SpeculativeDecodingStrategy> _llamaCppDraftStrategies =
      <SpeculativeDecodingStrategy>{
        SpeculativeDecodingStrategy.draftSimple,
        SpeculativeDecodingStrategy.draftEagle3,
        SpeculativeDecodingStrategy.mtp,
        SpeculativeDecodingStrategy.draftDflash,
        SpeculativeDecodingStrategy.draftDspark,
      };

  /// Creates the service; tests replace the runtime's first native call, the
  /// host probes behind its Windows load diagnostics, the Android check behind
  /// its backend and context policy, the iOS simulator and macOS x86_64
  /// checks behind its backend policy, the core count behind its default CPU
  /// thread counts, the raw `ggml_backend_dev_type` values a
  /// [ComputeDevice.gpu] load checks for a backend, the calls that create,
  /// free and run models and contexts, the ggml calls of decision heads, the
  /// calls that allocate and free per-request token batches and prepared
  /// embedding resources, the read of the Vulkan device facts, the registered
  /// ggml devices a load selects from, the devices the registry of an
  /// explicit GPU backend lists, the probe of whether a device's
  /// backend has row split buffer types, the allocator of the model paths,
  /// tensor splits and tensor buffer overrides [loadModel] and draft model
  /// loads pass to llama.cpp, and the allocator
  /// of each context's token batch, whose blocks `malloc`'s free must be able
  /// to free: an isolate exit frees a batch still held with it.
  LlamaCppService({
    void Function()? backendInit,
    Abi? abi,
    bool? isWindows,
    bool? isAndroid,
    bool? isIosSimulator,
    bool? isMacosX64,
    int? availableCores,
    List<String> Function(List<String> names) missingWindowsLibraries =
        findMissingWindowsLibraries,
    List<int> Function(GpuBackend backend)? deviceTypes,
    LlamaCppObjectCalls? objectCalls,
    GgmlGraphApi? decisionHeadGraphApi,
    llama_batch Function(int tokens, int embd, int sequences)? batchInit,
    void Function(llama_batch batch)? batchFree,
    void Function(Pointer<mtmd_input_chunks>)? embeddingChunksFree,
    void Function(Pointer<mtmd_bitmap>)? embeddingBitmapFree,
    void Function(Pointer<llama_batch_ext>)? embeddingBatchFree,
    VulkanDeviceProbe Function()? vulkanDeviceProbe,
    List<GgmlDeviceEntry> Function()? registeredDevices,
    List<ggml_backend_dev_t>? Function(GpuBackend backend)? backendDevices,
    bool Function(GgmlDeviceEntry device)? splitBufferTypeProbe,
    Allocator modelLoadAllocator = malloc,
    Allocator contextBatchAllocator = malloc,
    String? Function()? buildIdentity,
    String? Function(Pointer<llama_model> model)? modelArchitecture,
    String? Function()? ggmlVersion,
  }) : _backendInit = backendInit ?? (() => llama_backend_init()),
       _abi = abi ?? Abi.current(),
       _isWindows = isWindows ?? Platform.isWindows,
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _isIosSimulator = isIosSimulator ?? isIosSimulatorProcess(),
       _isMacosX64 = isMacosX64 ?? Abi.current() == Abi.macosX64,
       _availableCores = availableCores ?? Platform.numberOfProcessors,
       _missingWindowsLibraries = missingWindowsLibraries,
       _deviceTypesOverride = deviceTypes,
       _objectCallsOverride = objectCalls,
       _decisionHeadGraphApi = decisionHeadGraphApi,
       _batchInit = batchInit ?? llama_batch_init,
       _batchFree = batchFree ?? llama_batch_free,
       _embeddingChunksFree = embeddingChunksFree,
       _embeddingBitmapFree = embeddingBitmapFree,
       _embeddingBatchFree = embeddingBatchFree,
       _vulkanDeviceProbeOverride = vulkanDeviceProbe,
       _registeredDevicesOverride = registeredDevices,
       _backendDevicesOverride = backendDevices,
       _splitBufferTypeProbeOverride = splitBufferTypeProbe,
       _modelLoadAllocator = modelLoadAllocator,
       _contextBatchAllocator = contextBatchAllocator,
       _readBuildIdentity = buildIdentity,
       _modelArchitectureOverride = modelArchitecture,
       _readGgmlVersion = ggmlVersion;

  NativeWorkerOwner? _nativeOwner;

  /// Prepares library resolution and creates an empty parent-owned bootstrap.
  /// No model, context or optional GPU backend is initialized here.
  static NativeOwnerBootstrap? createOwnerBootstrap() {
    final service = LlamaCppService();
    service._prepareLinuxRuntimeDependenciesBeforeBinding();
    service._preloadLinuxCoreLibrariesForSonameResolution();
    if (Platform.isWindows) {
      try {
        // Resolve the core image before its optional dependent wrapper, as
        // worker initialization does, without initializing a backend here.
        Native.addressOf<NativeFunction<Void Function()>>(llama_backend_init);
      } on ArgumentError {
        // Preserve the worker's existing missing-runtime diagnostics.
        return null;
      }
    }
    return NativeOwnerBootstrap.tryCreate();
  }

  /// Attaches stable cleanup before activating the worker's native owner.
  void installWorkerOwner(int? token) {
    if (token == null) return;
    final current = _nativeOwner;
    if (current != null) {
      if (current.token.address == token) {
        return;
      }
      throw LlamaBackendInitializationException(
        'The worker already has a different native owner.',
      );
    }
    final api = NativeOwnerApi.tryResolve();
    if (api == null) {
      throw LlamaBackendInitializationException(
        'The worker cannot resolve the native owner API selected by its parent.',
      );
    }
    final owner = NativeWorkerOwner(api, Pointer.fromAddress(token));
    IsolateShutdownReleases.current.installOwner(owner);
    if (!api.activate(owner.token)) {
      throw LlamaBackendInitializationException(
        'The native worker owner expired before activation.',
      );
    }
    _nativeOwner = owner;
  }

  Pointer<llama_model> _loadOwnedModel(
    Pointer<Char> path,
    llama_model_params params,
  ) {
    final owner = _nativeOwner;
    if (owner == null) return _calls.loadModel(path, params);
    final model = owner.api.loadModel(owner.token, path, params);
    if (model == nullptr) {
      _calls.failures.throwIfCaught(
        'llama_model_load_from_file',
        LlamaModelException.new,
      );
    }
    return model;
  }

  Pointer<llama_context> _createOwnedContext(
    Pointer<llama_model> model,
    llama_context_params params,
  ) {
    final owner = _nativeOwner;
    if (owner == null) return _calls.createContext(model, params);
    final context = owner.api.createContext(owner.token, model, params);
    if (context == nullptr) {
      _calls.failures.throwIfCaught(
        'llama_init_from_model',
        LlamaContextException.new,
        windowsFreeOnly: [model],
      );
    }
    return context;
  }

  final void Function() _backendInit;
  final Abi _abi;
  final bool _isWindows;
  final bool _isAndroid;
  final bool _isIosSimulator;
  final bool _isMacosX64;
  final int _availableCores;
  final List<String> Function(List<String> names) _missingWindowsLibraries;
  final List<int> Function(GpuBackend backend)? _deviceTypesOverride;
  final LlamaCppObjectCalls? _objectCallsOverride;
  final GgmlGraphApi? _decisionHeadGraphApi;
  final llama_batch Function(int tokens, int embd, int sequences) _batchInit;
  final void Function(llama_batch batch) _batchFree;
  final void Function(Pointer<mtmd_input_chunks>)? _embeddingChunksFree;
  final void Function(Pointer<mtmd_bitmap>)? _embeddingBitmapFree;
  final void Function(Pointer<llama_batch_ext>)? _embeddingBatchFree;
  final VulkanDeviceProbe Function()? _vulkanDeviceProbeOverride;
  late final LlamaCppObjectCalls _calls =
      _objectCallsOverride ?? _resolveObjectCalls();

  final List<GgmlDeviceEntry> Function()? _registeredDevicesOverride;
  final List<ggml_backend_dev_t>? Function(GpuBackend backend)?
  _backendDevicesOverride;
  final bool Function(GgmlDeviceEntry device)? _splitBufferTypeProbeOverride;
  final Allocator _modelLoadAllocator;
  final Allocator _contextBatchAllocator;
  final String? Function()? _readBuildIdentity;
  late final String? _buildIdentity =
      (_readBuildIdentity ??
      () => readNativeBuildIdentity(isWindows: _isWindows))();
  final String? Function()? _readGgmlVersion;
  late final bool _ggmlHasSmallMatmulTileFix = () {
    final version = (_readGgmlVersion ?? readGgmlVersion)();
    final fixed = ggmlHasSmallMatmulTileFix(version);
    LlamaLogger.instance.debug(
      'llama_cpp_service: ggml ${version ?? '(no ggml_version)'} '
      '${fixed ? 'has' : 'lacks'} the Vulkan small matmul tile fix '
      '(ggml $smallMatmulTileFixGgmlVersion)',
    );
    return fixed;
  }();

  // Reading the facts loads the system's GPU drivers into the process, so
  // they are read once, and only for a load that selects a registered
  // ggml-vulkan device or an Android context of a registry that has one:
  // ggml-vulkan has loaded the drivers by then.
  late final VulkanDeviceProbe _vulkanDeviceProbe =
      (_vulkanDeviceProbeOverride ??
      () => VulkanDeviceInfoApi.probeRuntime(isWindows: _isWindows))();
  int _nextHandle = 1;
  String? _backendModuleDirectory;
  final Set<String> _loadedBackendModules = <String>{};
  final Set<String> _failedBackendModules = <String>{};
  final Map<String, DynamicLibrary> _loadedBackendLibraries =
      <String, DynamicLibrary>{};
  final Map<String, List<DynamicLibrary>> _preloadedBackendDependencyLibraries =
      <String, List<DynamicLibrary>>{};
  final List<DynamicLibrary> _preloadedCoreLibraries = <DynamicLibrary>[];
  bool _backendLoadAllSymbolUnavailable = false;
  bool _backendLoadAllFromPathSymbolUnavailable = false;
  bool _backendLoadSymbolUnavailable = false;
  bool _backendRegistrySymbolUnavailable = false;
  bool _linuxCorePreloadAttempted = false;
  bool _linuxRuntimeDepsPrepared = false;
  String? _linuxPreparedLibraryDirectory;
  bool _ggmlFallbackLookupAttempted = false;
  String? _ggmlFallbackLookupSearchKey;
  String? _ggmlRuntimeProbeOutcome;
  _GgmlBackendLoadDart? _ggmlBackendLoadFallback;
  _GgmlBackendLoadAllDart? _ggmlBackendLoadAllFallback;
  _GgmlBackendLoadAllFromPathDart? _ggmlBackendLoadAllFromPathFallback;
  _GgmlBackendRegisterDart? _ggmlBackendRegisterFallback;
  _GgmlBackendRegCountDart? _ggmlBackendRegCountFallback;
  _GgmlBackendRegGetDart? _ggmlBackendRegGetFallback;
  _GgmlBackendRegNameDart? _ggmlBackendRegNameFallback;
  _GgmlBackendRegByNameDart? _ggmlBackendRegByNameFallback;
  _GgmlBackendRegGetProcAddressDart? _ggmlBackendRegGetProcAddressFallback;
  // Tests replace this through mirrors to reproduce an absent primary export.
  // ignore: prefer_final_fields
  _GgmlBackendRegGetProcAddressDart _ggmlBackendRegGetProcAddressPrimary =
      ggml_backend_reg_get_proc_address;
  _GgmlBackendRegDevCountDart? _ggmlBackendRegDevCountFallback;
  _GgmlBackendRegDevGetDart? _ggmlBackendRegDevGetFallback;
  _GgmlBackendDevCountDart? _ggmlBackendDevCountFallback;
  _GgmlBackendDevGetDart? _ggmlBackendDevGetFallback;
  _GgmlBackendDevNameDart? _ggmlBackendDevNameFallback;
  _GgmlBackendDevBackendRegDart? _ggmlBackendDevBackendRegFallback;
  _GgmlBackendDevByTypeDart? _ggmlBackendDevByTypeFallback;
  _GgmlBackendDevBufferTypeDart? _ggmlBackendDevBufferTypeFallback;
  _GgmlBackendDevTypeDart? _ggmlBackendDevTypeFallback;
  _GgmlBackendDevGetPropsDart? _ggmlBackendDevGetPropsFallback;
  _GgmlBackendDevMemoryDart? _ggmlBackendDevMemoryFallback;
  bool _logLevelFallbackLookupAttempted = false;
  String? _logLevelFallbackLookupSearchKey;
  String? _logLevelProbeOutcome;
  _LlamaDartSetLogLevelDart? _llamaDartSetLogLevelFallback;
  LlamaLogLevel _configuredLogLevel = LlamaLogLevel.warn;
  String _activeBackendName = 'CPU';
  int _activeResolvedGpuLayers = 0;
  bool _mtmdFallbackLookupAttempted = false;
  String? _mtmdFallbackLookupDirectory;
  bool _mtmdPrimarySymbolsUnavailable = false;
  bool _mtmdVideoPrimarySymbolUnavailable = false;
  _MtmdApi? _mtmdFallbackApi;
  bool _reasoningBudgetApiLookupAttempted = false;
  _ReasoningBudgetApi? _reasoningBudgetApi;
  final Map<String, int> _reasoningBudgetLoadFailures = <String, int>{};
  bool _speculativeApiLookupAttempted = false;
  _SpeculativeApi? _speculativeApi;
  bool _ttsApiLookupAttempted = false;
  _TtsApi? _ttsApi;
  Pointer<llama_dart_tts> _activeTts = nullptr;
  bool _ttsCancelPending = false;
  int? _activeTtsContextHandle;
  final StartupDiagnosticBuffer _startupDiagnostics = StartupDiagnosticBuffer();

  // --- Internal State ---
  final Map<int, _LlamaModelWrapper> _models = {};
  final Map<int, _LlamaContextWrapper> _contexts = {};
  final Map<int, int> _contextToModel = {};
  final Map<int, Pointer<llama_sampler>> _samplers = {};
  final Map<int, TokenBatch> _batches = {};
  final Map<int, llama_context_params> _contextParams = {};

  /// Called for unit tests with the draft context of each speculative session
  /// a generation creates, or `nullptr` for a strategy without one.
  void Function(Pointer<llama_context> draftContext)?
  debugOnSpeculativeDraftContextForTesting;

  final Map<int, Map<String, _LlamaLoraWrapper>> _loraAdapters = {};
  final Map<int, Map<String, double>> _activeLoras = {};
  final String? Function(Pointer<llama_model>)? _modelArchitectureOverride;
  final Map<int, String> _modelResolvedBackends = <int, String>{};
  final Map<int, String?> _modelArchitectures = <int, String?>{};
  final Map<int, String> _modelBackendNames = <int, String>{};
  final Map<int, int> _modelResolvedGpuLayers = <int, int>{};
  // Retain the raw load layers for auxiliary placement, but report zero and
  // disable context offload when the load selected no GPU.
  final Set<int> _modelsOnNoGpu = <int>{};
  final Map<int, ModelParams> _modelLoadParams = <int, ModelParams>{};
  final Map<int, GpuDevicePlacement> _modelPlacements =
      <int, GpuDevicePlacement>{};
  final Map<String, _LlamaModelWrapper> _speculativeDraftModels =
      <String, _LlamaModelWrapper>{};
  final Map<int, Set<String>> _modelToSpeculativeDraftModelKeys =
      <int, Set<String>>{};

  /// Refcount of in-flight `generate()` calls per context. A set would let the
  /// first completion clear the marker while another decode is still running.
  final Map<int, int> _generatingContexts = <int, int>{};

  // Mapping: modelHandle -> mtmdContextHandle
  final Map<int, int> _modelToMtmd = {};
  final Map<int, Pointer<mtmd_context>> _mtmdContexts = {};
  final Map<int, bool> _modelToMtmdUseGpu = {};

  final Map<int, _DecisionHead> _decisionHeads = <int, _DecisionHead>{};

  int _getHandle() => _nextHandle++;

  /// Maps [ModelParams.device] onto the llama.cpp fields the load reads.
  ///
  /// [ComputeDevice.cpu] forces the CPU module (or BLAS when requested) and 0
  /// GPU layers. [ComputeDevice.gpu] keeps the requested backend, except that
  /// Android resolves [GpuBackend.auto] to Vulkan and an iOS simulator or
  /// macOS x86_64 resolves it to Metal, since their `auto` means the CPU.
  /// [ComputeDevice.npu] has no llama.cpp backend.
  static ModelParams resolveComputeDeviceParams(
    ModelParams modelParams, {
    bool isAndroid = false,
    bool isIosSimulator = false,
    bool isMacosX64 = false,
    String platform = 'this platform',
  }) {
    switch (modelParams.device) {
      case ComputeDevice.auto:
        return modelParams;
      case ComputeDevice.cpu:
        return modelParams.copyWith(
          preferredBackend: modelParams.preferredBackend == GpuBackend.blas
              ? GpuBackend.blas
              : GpuBackend.cpu,
          gpuLayers: 0,
        );
      case ComputeDevice.gpu:
        if (isAndroid && modelParams.preferredBackend == GpuBackend.auto) {
          return modelParams.copyWith(preferredBackend: GpuBackend.vulkan);
        }
        if ((isIosSimulator || isMacosX64) &&
            modelParams.preferredBackend == GpuBackend.auto) {
          return modelParams.copyWith(preferredBackend: GpuBackend.metal);
        }
        return modelParams;
      case ComputeDevice.npu:
        throw LlamaUnsupportedException(
          'ComputeDevice.npu is not available for llama.cpp on $platform: '
          'llama.cpp runs GGUF models on the CPU or a GPU, and only LiteRT-LM '
          'on Android has an NPU backend. Use ComputeDevice.auto, cpu or gpu.',
        );
    }
  }

  /// Resolves the effective backend preference for model loading.
  ///
  /// Android keeps Vulkan bundled, but `auto` currently prefers CPU to avoid
  /// initializing optional GPU backends by default on devices with unstable
  /// Vulkan stacks. An iOS simulator resolves `auto` to CPU as well: its
  /// Metal device returns incorrect output from llama.cpp
  /// (https://github.com/leehack/llamadart/issues/950). So does macOS x86_64,
  /// Rosetta included: Metal returns garbled output on Intel Macs with AMD
  /// GPUs (https://github.com/leehack/llamadart/issues/1597), and an x86_64
  /// process cannot tell an Intel Mac from Rosetta. An explicit backend is
  /// returned as requested.
  static GpuBackend resolvePreferredBackendForLoad(
    ModelParams modelParams, {
    bool isAndroid = false,
    bool isIosSimulator = false,
    bool isMacosX64 = false,
  }) {
    if ((isAndroid || isIosSimulator || isMacosX64) &&
        modelParams.preferredBackend == GpuBackend.auto) {
      return GpuBackend.cpu;
    }
    return modelParams.preferredBackend;
  }

  /// Resolves the effective GPU layer count for model loading.
  ///
  /// CPU backend preference always forces zero offloaded layers, and a
  /// negative [ModelParams.gpuLayers] resolves to [ModelParams.maxGpuLayers]:
  /// llama.cpp offloads every layer for it, so the context offload, backend
  /// name and reported layer count must treat it as a GPU load.
  static int resolveGpuLayersForLoad(
    ModelParams modelParams, {
    bool isAndroid = false,
    bool isIosSimulator = false,
    bool isMacosX64 = false,
  }) {
    return resolvePreferredBackendForLoad(
              modelParams,
              isAndroid: isAndroid,
              isIosSimulator: isIosSimulator,
              isMacosX64: isMacosX64,
            ) ==
            GpuBackend.cpu
        ? 0
        : resolveGpuLayerCount(modelParams.gpuLayers);
  }

  /// The warning for a model an iOS simulator loaded with [resolvedGpuLayers]
  /// GPU layers, or `null` when [isIosSimulator] is false or the model runs
  /// on the CPU.
  static String? iosSimulatorMetalWarning({
    required bool isIosSimulator,
    required int resolvedGpuLayers,
  }) {
    if (!isIosSimulator || resolvedGpuLayers == 0) {
      return null;
    }
    return "llama.cpp's Metal backend is known to return incorrect output on "
        'the iOS simulator '
        '(https://github.com/leehack/llamadart/issues/950), and this model '
        'was loaded with GPU layers there. Use ComputeDevice.auto with '
        'GpuBackend.auto, or ComputeDevice.cpu, to run it on the CPU.';
  }

  /// The warning for a model a macOS x86_64 process loaded with
  /// [resolvedGpuLayers] GPU layers, or `null` when [isMacosX64] is false or
  /// the model runs on the CPU.
  static String? macosX64MetalWarning({
    required bool isMacosX64,
    required int resolvedGpuLayers,
  }) {
    if (!isMacosX64 || resolvedGpuLayers == 0) {
      return null;
    }
    return "llama.cpp's Metal backend is known to return garbled output on "
        'Intel Macs with AMD GPUs '
        '(https://github.com/leehack/llamadart/issues/1597), and this model '
        'was loaded with GPU layers in a macOS x86_64 process. Use '
        'ComputeDevice.auto with GpuBackend.auto, or ComputeDevice.cpu, to '
        'run it on the CPU.';
  }

  /// Returns whether context-time GPU offload should be disabled.
  ///
  /// When CPU mode is selected (or model load resolved to zero GPU layers),
  /// context-level offload knobs must also be disabled to prevent runtime
  /// GPU initialization during `llama_init_from_model(...)`.
  static bool shouldDisableContextGpuOffload(
    ModelParams modelParams, {
    int? resolvedGpuLayers,
  }) {
    final effectiveGpuLayers =
        resolvedGpuLayers ?? resolveGpuLayersForLoad(modelParams);
    return modelParams.preferredBackend == GpuBackend.cpu ||
        effectiveGpuLayers <= 0;
  }

  /// Returns whether Android Vulkan should use conservative context settings.
  ///
  /// Some Android Vulkan stacks can abort during decode scheduling when
  /// context-time KQV/op offload and flash-attention auto-selection stay fully
  /// enabled. We keep model layers offloaded but disable the more aggressive
  /// context compute knobs for stability.
  static bool shouldUseConservativeAndroidVulkanContextConfig(
    ModelParams modelParams, {
    int? resolvedGpuLayers,
    bool isAndroid = false,
  }) {
    if (!isAndroid) {
      return false;
    }

    final effectiveGpuLayers =
        resolvedGpuLayers ?? resolveGpuLayersForLoad(modelParams);
    return modelParams.preferredBackend == GpuBackend.vulkan &&
        effectiveGpuLayers > 0;
  }

  /// Returns whether Android Vulkan must keep KQV offload enabled for the
  /// model architecture to preserve inference correctness.
  ///
  /// Qwen3.5 produces incorrect logits when its model layers are offloaded to
  /// Vulkan while KQV remains on the CPU. Keep the other conservative Android
  /// Vulkan settings independent so this correctness exception does not also
  /// enable op offload or Flash Attention.
  static bool shouldKeepAndroidVulkanKqvOffloadEnabled(
    String? modelArchitecture,
  ) {
    if (modelArchitecture == null || modelArchitecture.isEmpty) {
      return false;
    }

    final normalized = modelArchitecture.toLowerCase().replaceAll(
      RegExp('[^a-z0-9]'),
      '',
    );
    return normalized == 'qwen35';
  }

  /// Most tokens of a text prompt an Android Vulkan context decodes in one
  /// micro-batch when [ModelParams.microBatchSize] is unset.
  static const int androidVulkanPromptMicroBatchSize = 8;

  /// Returns the most tokens of a text prompt one decode call takes on a
  /// context created with [modelParams], or `null` for the context's own
  /// micro-batch.
  ///
  /// An Android Vulkan context gets [androidVulkanPromptMicroBatchSize]
  /// unless [ModelParams.microBatchSize] is set or
  /// [hasSmallMatmulTileDefect] returns false. That is called only when the
  /// cap would otherwise apply; without it the cap applies.
  static int? resolvePromptMicroBatchLimit(
    ModelParams modelParams, {
    int? resolvedGpuLayers,
    bool isAndroid = false,
    bool Function()? hasSmallMatmulTileDefect,
  }) {
    // A speed default: on a Pixel 9 Pro (Mali-G715, subgroup 16), 8-token
    // calls evaluated a prompt at about 44 tok/s against 27-29 for 32 or 512
    // on ggml 0.29. Before ggml 0.28 it also keeps prompts out of the small
    // matmul tile defect above 32 tokens
    // (https://github.com/ggml-org/llama.cpp/issues/28637).
    // `n_ubatch` is left alone: a non-causal image decode and a one-pass
    // embedding need their whole input in one micro-batch.
    if (modelParams.microBatchSize > 0 ||
        !shouldUseConservativeAndroidVulkanContextConfig(
          modelParams,
          resolvedGpuLayers: resolvedGpuLayers,
          isAndroid: isAndroid,
        ) ||
        hasSmallMatmulTileDefect?.call() == false) {
      return null;
    }
    return androidVulkanPromptMicroBatchSize;
  }

  /// Whether a Vulkan device ggml-vulkan registered may give wrong results
  /// from its small matmul tile.
  ///
  /// True unless [probe] lists exactly [registeredDeviceCount] devices and
  /// none of them has the defect: a runtime without the probe, a probe that
  /// failed and a device list that does not match ggml's all count as
  /// affected.
  static bool vulkanSmallMatmulTileDefect(
    VulkanDeviceProbe probe, {
    required int registeredDeviceCount,
  }) {
    final devices = probe.devices;
    return devices == null ||
        devices.isEmpty ||
        devices.length != registeredDeviceCount ||
        devices.any((device) => device.hasSmallMatmulTileDefect);
  }

  static const String _qwen35VulkanRestriction =
      'Qwen3.5 on Android/Vulkan with a llama.cpp runtime older than ggml '
      '$smallMatmulTileFixGgmlVersion (llamadart-native v0.8.0) and unsafe or '
      'unproven small-matmul subgroup facts supports ordinary text only, with '
      'microBatchSize unset or 1..8 '
      '(https://github.com/leehack/llamadart/issues/948). Use the bundled '
      'runtime, or ComputeDevice.cpu for larger batches, media, speculation or '
      'embeddings.';

  // Context preferences cannot move tensors already loaded onto Vulkan.
  bool _modelUsesAndroidVulkan(int modelHandle) =>
      _isAndroid &&
      _modelResolvedBackends[modelHandle] == 'Vulkan' &&
      (_modelResolvedGpuLayers[modelHandle] ?? 0) > 0 &&
      !_modelsOnNoGpu.contains(modelHandle);

  bool _requiresQwen35VulkanRestriction(int modelHandle) =>
      !_ggmlHasSmallMatmulTileFix &&
      _isQwen35OnSmallTileAndroidVulkan(modelHandle);

  /// The native architecture of [modelHandle] when it is placed on an
  /// Android Vulkan device with unsafe or unproven small-matmul subgroup
  /// facts, judged by the actual placement rather than the context's
  /// preferences; `null` when it is not, and empty when it is unreadable.
  String? _smallTileAndroidVulkanArchitecture(int modelHandle) {
    if (!_modelUsesAndroidVulkan(modelHandle) ||
        !_androidVulkanHasSmallMatmulTileDefect()) {
      return null;
    }
    try {
      return _modelArchitecture(modelHandle)?.trim() ?? '';
    } on Object {
      return '';
    }
  }

  static bool _isQwen35Architecture(String architecture) =>
      architecture.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '') ==
      'qwen35';

  /// Whether [modelHandle] is Qwen3.5 on small-tile Android Vulkan.
  bool _isQwen35OnSmallTileAndroidVulkan(int modelHandle) {
    final architecture = _smallTileAndroidVulkanArchitecture(modelHandle);
    if (architecture == null) return false;
    if (architecture.isEmpty) {
      // Missing runtime metadata cannot establish admission for this GPU path.
      if (_ggmlHasSmallMatmulTileFix) return false;
      throw LlamaUnsupportedException(
        'Cannot establish required model safety for Android/Vulkan with a '
        'llama.cpp runtime older than ggml $smallMatmulTileFixGgmlVersion '
        '(llamadart-native v0.8.0) and unsafe or unproven small-matmul '
        'subgroup facts: native general.architecture is unavailable '
        '(https://github.com/leehack/llamadart/issues/948). Use the bundled '
        'runtime or ComputeDevice.cpu.',
      );
    }
    return _isQwen35Architecture(architecture);
  }

  // The Qwen3.5 image encoder on these GPUs is unvalidated on every runtime,
  // so it stays on the CPU; an unreadable architecture counts as Qwen3.5.
  bool _keepsProjectorOnCpu(int modelHandle) {
    final architecture = _smallTileAndroidVulkanArchitecture(modelHandle);
    return architecture != null &&
        (architecture.isEmpty || _isQwen35Architecture(architecture));
  }

  String? _modelArchitecture(int modelHandle) =>
      _modelArchitectures.putIfAbsent(
        modelHandle,
        () => _modelArchitectureOverride == null
            ? _getModelMetadataValue(modelHandle, 'general.architecture')
            : _modelArchitectureOverride(_models[modelHandle]!.pointer),
      );

  void _checkQwen35VulkanEmbedding(_LlamaContextWrapper context) {
    if (context.qwen35VulkanRestricted) {
      throw LlamaUnsupportedException(
        'Embeddings are unavailable. $_qwen35VulkanRestriction',
      );
    }
  }

  bool _projectorHasQwen35VulkanRestriction(int mmContextHandle) {
    for (final entry in _modelToMtmd.entries) {
      if (entry.value == mmContextHandle) {
        return _requiresQwen35VulkanRestriction(entry.key);
      }
    }
    return false;
  }

  /// Resolves effective context batch parameters.
  ///
  /// Uses the shared non-FFI helper for consistent default resolution and
  /// clamping while allowing each backend to select its compatibility policy.
  static ({int batchSize, int microBatchSize}) resolveContextBatchSizes(
    ModelParams modelParams,
    int contextSize, {
    bool useFullContextDefaults = false,
  }) {
    return resolveModelContextBatchSizes(
      modelParams,
      contextSize,
      useFullContextDefaults: useFullContextDefaults,
    );
  }

  /// Resolves whether multimodal projector init should use GPU.
  ///
  /// This follows effective model-load configuration from model loading.
  static bool resolveMtmdUseGpuForLoad(
    ModelParams modelParams,
    int effectiveGpuLayers, {
    String? modelPath,
    bool isAndroid = false,
  }) {
    if (shouldForceCpuProjectorForAndroid(modelPath, isAndroid: isAndroid)) {
      return false;
    }

    return !shouldDisableContextGpuOffload(
      modelParams,
      resolvedGpuLayers: effectiveGpuLayers,
    );
  }

  /// Returns whether Android should keep mtmd projector work on CPU for the
  /// given model file.
  static bool shouldForceCpuProjectorForAndroid(
    String? modelPath, {
    bool isAndroid = false,
  }) {
    if (!isAndroid || modelPath == null || modelPath.isEmpty) {
      return false;
    }

    final normalized = path.basename(modelPath).toLowerCase();
    return normalized.contains('qwen3.5-0.8b') ||
        normalized.contains('qwen_qwen3.5-0.8b');
  }

  // --- Core Methods ---

  /// Sets the log level for the Llama.cpp library.
  void setLogLevel(LlamaLogLevel level) {
    _configuredLogLevel = level;
    _applyConfiguredLogLevel();
  }

  /// Initializes the Llama.cpp backend.
  ///
  /// This must be called before loading any models.
  void initializeBackend() {
    _prepareLinuxRuntimeDependenciesBeforeBinding();
    _preloadLinuxCoreLibrariesForSonameResolution();
    _backendModuleDirectory = resolveBackendModuleDirectory();
    if (_backendModuleDirectory == null && Platform.isLinux) {
      _backendModuleDirectory =
          _linuxPreparedLibraryDirectory ??
          _resolveLinuxPrimaryLibraryDirectory();
    }
    _applyConfiguredLogLevel();
    runLlamaBackendInit(
      _backendInit,
      abi: _abi,
      missingWindowsLibraries: _missingWindowsLibraries,
    );
    _refreshBackendModuleDirectoryAfterPrimaryLoad();
    _applyConfiguredLogLevel();

    if ((Platform.isMacOS || Platform.isIOS) &&
        _backendModuleDirectory == null) {
      return;
    }

    // Startup path should remain CPU-safe so reading backend options does not
    // initialize optional GPU backends.
    if (_backendModuleDirectory != null) {
      _tryLoadBackendModuleIfBundled('cpu');
    } else {
      _tryLoadBackendModule('cpu');
    }

    if (_ggmlBackendRegCount() == 0) {
      // Fallback path: attempt to load CPU backend by filename resolution.
      _tryLoadBackendModule('cpu');
    }
  }

  void _prepareLinuxRuntimeDependenciesBeforeBinding() {
    if (!Platform.isLinux || _linuxRuntimeDepsPrepared) {
      return;
    }
    _linuxRuntimeDepsPrepared = true;

    final targetDir = _resolveLinuxPrimaryLibraryDirectory();
    if (targetDir == null) {
      return;
    }

    final sourceDirectories = _linuxDependencySourceDirectories(targetDir);
    const coreLibraries = <String>[
      'libggml-base.so',
      'libggml.so',
      'libllama.so',
    ];

    for (final libraryFileName in coreLibraries) {
      copyMissingLinuxLibrary(
        targetDirectory: targetDir,
        sourceDirectories: sourceDirectories,
        fileName: libraryFileName,
        onDiagnostic: _recordStartupDiagnostic,
      );
      ensureLinuxSonameAlias(
        directory: targetDir,
        baseFileName: libraryFileName,
        onDiagnostic: _recordStartupDiagnostic,
      );
    }

    const backendModuleLibraries = <String>[
      'libggml-cpu.so',
      'libggml-vulkan.so',
      'libggml-opencl.so',
      'libggml-cuda.so',
      'libggml-blas.so',
      'libggml-hip.so',
    ];

    for (final libraryFileName in backendModuleLibraries) {
      copyMissingLinuxLibrary(
        targetDirectory: targetDir,
        sourceDirectories: sourceDirectories,
        fileName: libraryFileName,
        onDiagnostic: _recordStartupDiagnostic,
      );
      ensureLinuxSonameAlias(
        directory: targetDir,
        baseFileName: libraryFileName,
        onDiagnostic: _recordStartupDiagnostic,
      );
    }

    _linuxPreparedLibraryDirectory = targetDir;
  }

  String? _resolveLinuxPrimaryLibraryDirectory() {
    return resolveLinuxPrimaryLibraryDirectory(
      resolvedExecutablePath: Platform.resolvedExecutable,
      currentDirectoryPath: Directory.current.path,
      environment: Platform.environment,
    );
  }

  void _refreshBackendModuleDirectoryAfterPrimaryLoad() {
    if (_backendModuleDirectory != null) {
      return;
    }

    if (!Platform.isAndroid && !Platform.isLinux) {
      return;
    }

    _backendModuleDirectory = resolveBackendModuleDirectory();
    if (_backendModuleDirectory == null && Platform.isLinux) {
      _backendModuleDirectory =
          _linuxPreparedLibraryDirectory ??
          _resolveLinuxPrimaryLibraryDirectory();
    }
  }

  /// Copies a missing Linux runtime dependency into the target directory.
  ///
  /// Returns `true` when the dependency already exists or is copied
  /// successfully. When a copy attempt fails, [onDiagnostic] receives a
  /// best-effort diagnostic message.
  static bool copyMissingLinuxLibrary({
    required String targetDirectory,
    required List<String> sourceDirectories,
    required String fileName,
    void Function(String message)? onDiagnostic,
  }) {
    final targetPath = path.join(targetDirectory, fileName);
    if (File(targetPath).existsSync()) {
      return true;
    }

    for (final sourceDirectory in sourceDirectories) {
      final sourcePath = path.join(sourceDirectory, fileName);
      final sourceFile = File(sourcePath);
      if (!sourceFile.existsSync()) {
        continue;
      }
      try {
        sourceFile.copySync(targetPath);
        return true;
      } catch (error) {
        onDiagnostic?.call(
          'Failed to copy Linux runtime dependency `$fileName` from '
          '`$sourcePath` to `$targetPath`: $error',
        );
        continue;
      }
    }

    return false;
  }

  /// Ensures a Linux SONAME alias file exists for [baseFileName].
  ///
  /// Returns `true` when the alias already exists or is created successfully.
  /// When both symlink creation and fallback copying fail, [onDiagnostic]
  /// receives a best-effort diagnostic message.
  static bool ensureLinuxSonameAlias({
    required String directory,
    required String baseFileName,
    void Function(String message)? onDiagnostic,
  }) {
    final sourcePath = path.join(directory, baseFileName);
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) {
      return false;
    }

    final aliasPath = '$sourcePath.0';
    final aliasFile = File(aliasPath);
    if (aliasFile.existsSync()) {
      return true;
    }

    Object? linkError;
    try {
      Link(aliasPath).createSync(baseFileName);
      return true;
    } catch (error) {
      linkError = error;
    }

    try {
      sourceFile.copySync(aliasPath);
      return true;
    } catch (copyError) {
      onDiagnostic?.call(
        'Failed to create or copy Linux SONAME alias `$aliasPath` for '
        '`$sourcePath`: link error=$linkError; copy error=$copyError',
      );
      return false;
    }
  }

  /// Resolves the native backend module directory for dynamic backend loading.
  ///
  /// On Android/Linux we inspect `/proc/self/maps` to find the loaded
  /// `libllamadart.so` location, then load backend modules from that directory.
  /// Returns `null` when the path cannot be resolved.
  static String? resolveBackendModuleDirectory() {
    if (Platform.isWindows) {
      return resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: Platform.resolvedExecutable,
        currentDirectoryPath: Directory.current.path,
        environment: Platform.environment,
      );
    }

    if (!Platform.isAndroid && !Platform.isLinux) {
      return null;
    }

    try {
      final mapsFile = File('/proc/self/maps');
      if (!mapsFile.existsSync()) {
        return null;
      }

      final mapsContent = mapsFile.readAsStringSync();
      return parseBackendModuleDirectoryFromProcMaps(mapsContent);
    } catch (_) {
      return null;
    }
  }

  /// Returns startup diagnostics as retained by [StartupDiagnosticBuffer].
  List<String> getStartupDiagnostics() {
    return _startupDiagnostics.entries;
  }

  /// Returns whether a backend score allows a dynamically loaded module.
  ///
  /// Native runtimes expose `ggml_backend_score` to reject unsupported backend
  /// variants on the current system. A `null` score means the optional symbol
  /// is unavailable, so the candidate remains eligible for compatibility.
  static bool isBackendCandidateScoreSupported(int? score) {
    return score == null || score > 0;
  }

  /// Returns the first candidate whose probed score indicates support.
  ///
  /// Candidates with a missing score symbol (`null`) remain eligible so older
  /// backends that do not export `ggml_backend_score` still work.
  static T? selectFirstSupportedBackendCandidate<T>(
    Iterable<T> candidates, {
    required int? Function(T candidate) scoreForCandidate,
  }) {
    for (final candidate in candidates) {
      final score = scoreForCandidate(candidate);
      if (isBackendCandidateScoreSupported(score)) {
        return candidate;
      }
    }

    return null;
  }

  /// Describes why a backend asset candidate was skipped.
  static String describeSkippedBackendAssetCandidate(
    String assetUri,
    int score,
  ) {
    return 'Skipped backend asset `$assetUri` because '
        '`ggml_backend_score` returned $score.';
  }

  /// Describes which backend asset candidate was loaded.
  static String describeLoadedBackendAssetCandidate(
    String assetUri,
    int? score,
  ) {
    if (score == null) {
      return 'Loaded backend asset `$assetUri` without '
          '`ggml_backend_score`.';
    }
    return 'Loaded backend asset `$assetUri` with '
        '`ggml_backend_score`=$score.';
  }

  void _recordStartupDiagnostic(
    String message, {
    StartupDiagnosticCategory category = StartupDiagnosticCategory.causal,
  }) {
    _startupDiagnostics.record(message, category: category);
  }

  void _recordMissingGgmlSymbol(String symbol) {
    _recordStartupDiagnostic(
      '$symbol is unavailable: the primary FFI asset does not export it and '
      '${_ggmlRuntimeProbeOutcome ?? 'no ggml runtime candidate was probed'}.',
    );
  }

  /// Resolves Windows backend-module directory for dynamic backend loading.
  ///
  /// Resolution order:
  /// 1. Explicit environment override (`LLAMADART_NATIVE_LIB_DIR` or
  ///    `LLAMADART_BACKEND_MODULE_DIR`)
  /// 2. Directory of resolved executable (if it looks like a native bundle)
  /// 3. Standard CLI `bin/../lib` directory (if it looks like a native bundle)
  /// 4. Current working directory (if it looks like a native bundle)
  /// 5. Hook cache under `.dart_tool/llamadart/native_bundles_v2`, including
  ///    default, custom GitHub, and local archive cache namespaces.
  /// 6. Directory of resolved executable (best-effort fallback)
  static String? resolveWindowsBackendModuleDirectory({
    required String resolvedExecutablePath,
    required String currentDirectoryPath,
    required Map<String, String> environment,
  }) {
    final overrideCandidates = <String>[
      environment['LLAMADART_NATIVE_LIB_DIR'] ?? '',
      environment['LLAMADART_BACKEND_MODULE_DIR'] ?? '',
    ];
    for (final override in overrideCandidates) {
      if (override.isEmpty) {
        continue;
      }
      if (_containsWindowsNativeModules(override)) {
        return override;
      }
    }

    final executableDir = path.dirname(resolvedExecutablePath);
    if (_containsWindowsNativeModules(executableDir)) {
      return executableDir;
    }

    // `dart build cli` places executables in bin/ and native assets in lib/.
    if (path.basename(executableDir).toLowerCase() == 'bin') {
      final cliLibraryDir = path.normalize(
        path.join(executableDir, '..', 'lib'),
      );
      if (_containsWindowsNativeModules(cliLibraryDir)) {
        return cliLibraryDir;
      }
    }

    if (_containsWindowsNativeModules(currentDirectoryPath)) {
      return currentDirectoryPath;
    }

    final dartToolLibDir = _findDartToolLibDirectory(currentDirectoryPath);
    if (dartToolLibDir != null) {
      return dartToolLibDir;
    }

    final preferredBundle = _preferredWindowsBundleName();
    final hookCacheDir = _findHookCacheWindowsBundleDirectory(
      currentDirectoryPath,
      preferredBundleName: preferredBundle,
    );
    if (hookCacheDir != null) {
      return hookCacheDir;
    }

    return executableDir;
  }

  /// Resolves the primary Linux native-library directory.
  ///
  /// Resolution order:
  /// 1. Explicit environment override (`LLAMADART_NATIVE_LIB_DIR` or
  ///    `LLAMADART_BACKEND_MODULE_DIR`)
  /// 2. `.dart_tool/lib`
  /// 3. Executable-adjacent `lib/` directory
  /// 4. Directory of resolved executable
  /// 5. Current working directory `lib/`
  /// 6. Current working directory
  static String? resolveLinuxPrimaryLibraryDirectory({
    required String resolvedExecutablePath,
    required String currentDirectoryPath,
    required Map<String, String> environment,
  }) {
    final overrideCandidates = <String>[
      environment['LLAMADART_NATIVE_LIB_DIR'] ?? '',
      environment['LLAMADART_BACKEND_MODULE_DIR'] ?? '',
    ];
    for (final override in overrideCandidates) {
      if (override.isEmpty) {
        continue;
      }
      if (_containsLinuxPrimaryLibrary(override)) {
        return override;
      }
    }

    final executableDir = path.dirname(resolvedExecutablePath);
    final candidates = <String>[
      path.join(currentDirectoryPath, '.dart_tool', 'lib'),
      path.join(executableDir, 'lib'),
      executableDir,
      path.join(currentDirectoryPath, 'lib'),
      currentDirectoryPath,
    ];

    final seen = <String>{};
    for (final candidate in candidates) {
      final normalized = path.normalize(candidate);
      if (!seen.add(normalized)) {
        continue;
      }
      if (_containsLinuxPrimaryLibrary(normalized)) {
        return normalized;
      }
    }

    return null;
  }

  static String? _preferredWindowsBundleName() {
    switch (Abi.current()) {
      case Abi.windowsX64:
        return 'windows-x64';
      case Abi.windowsArm64:
        return 'windows-arm64';
      default:
        return null;
    }
  }

  static String? _findHookCacheWindowsBundleDirectory(
    String currentDirectoryPath, {
    String? preferredBundleName,
  }) {
    var cursor = Directory(currentDirectoryPath).absolute;
    while (true) {
      final cacheRoot = Directory(
        path.join(cursor.path, '.dart_tool', 'llamadart', 'native_bundles_v2'),
      );
      if (cacheRoot.existsSync()) {
        final found = _selectWindowsBundleDirectoryFromCache(
          cacheRoot.path,
          preferredBundleName: preferredBundleName,
        );
        if (found != null) {
          return found;
        }
      }

      final parent = cursor.parent;
      if (parent.path == cursor.path) {
        break;
      }
      cursor = parent;
    }

    return null;
  }

  static String? _selectWindowsBundleDirectoryFromCache(
    String cacheRootPath, {
    String? preferredBundleName,
  }) {
    final bundleDirs = _windowsBundleDirectoriesFromCache(
      cacheRootPath,
      preferredBundleName: preferredBundleName,
    );

    for (final bundleDir in bundleDirs) {
      final extractedDir = path.join(bundleDir.path, 'extracted');
      if (_containsWindowsNativeModules(extractedDir)) {
        return extractedDir;
      }
      if (_containsWindowsNativeModules(bundleDir.path)) {
        return bundleDir.path;
      }
    }

    return null;
  }

  static List<Directory> _windowsBundleDirectoriesFromCache(
    String cacheRootPath, {
    String? preferredBundleName,
  }) {
    final cacheRoot = Directory(cacheRootPath);
    final tagDirectories = <Directory>[];

    void addDefaultTags(Directory root) {
      for (final child in _listChildDirectories(root)) {
        final name = path.basename(child.path);
        if (name == 'github' || name == 'local') {
          continue;
        }
        tagDirectories.add(child);
      }
    }

    void addGitHubTags(Directory root) {
      final githubRoot = Directory(path.join(root.path, 'github'));
      for (final ownerDir in _listChildDirectories(githubRoot)) {
        for (final repoDir in _listChildDirectories(ownerDir)) {
          tagDirectories.addAll(_listChildDirectories(repoDir));
        }
      }
    }

    void addLocalTags(Directory root) {
      final localRoot = Directory(path.join(root.path, 'local'));
      for (final digestDir in _listChildDirectories(localRoot)) {
        tagDirectories.addAll(_listChildDirectories(digestDir));
      }
    }

    addDefaultTags(cacheRoot);
    addGitHubTags(cacheRoot);
    addLocalTags(cacheRoot);

    tagDirectories.sort(
      (a, b) => path.basename(b.path).compareTo(path.basename(a.path)),
    );

    final candidates = <Directory>[];
    for (final tagDirectory in tagDirectories) {
      if (preferredBundleName != null) {
        final preferred = Directory(
          path.join(tagDirectory.path, preferredBundleName),
        );
        if (preferred.existsSync()) {
          candidates.add(preferred);
        }
      }

      for (final directory in _listChildDirectories(tagDirectory)) {
        if (path.basename(directory.path).startsWith('windows-')) {
          candidates.add(directory);
        }
      }
    }

    final seen = <String>{};
    return candidates
        .where((directory) {
          return seen.add(path.normalize(directory.path));
        })
        .toList(growable: false);
  }

  static List<Directory> _listChildDirectories(Directory directory) {
    try {
      return directory.listSync().whereType<Directory>().toList(
        growable: false,
      );
    } catch (_) {
      return const <Directory>[];
    }
  }

  static bool _containsWindowsNativeModules(String directoryPath) {
    try {
      final directory = Directory(directoryPath);
      if (!directory.existsSync()) {
        return false;
      }

      final fileNames = directory
          .listSync()
          .whereType<File>()
          .map((file) => path.basename(file.path).toLowerCase())
          .toSet();

      final hasLlama = fileNames.any(
        (name) => RegExp(r'^llama(?:-[^.\\/]+)*\.dll$').hasMatch(name),
      );
      final hasGgml = fileNames.any(
        (name) => RegExp(r'^ggml(?:-[^.\\/]+)*\.dll$').hasMatch(name),
      );
      final hasCpuBackend = fileNames.any(
        (name) => RegExp(r'^ggml-cpu(?:-[^.\\/]+)*\.dll$').hasMatch(name),
      );
      return hasLlama && hasGgml && hasCpuBackend;
    } catch (_) {
      return false;
    }
  }

  static bool _containsLinuxPrimaryLibrary(String directoryPath) {
    try {
      final directory = Directory(directoryPath);
      if (!directory.existsSync()) {
        return false;
      }

      return File(path.join(directoryPath, 'libllamadart.so')).existsSync() ||
          File(path.join(directoryPath, 'libllamadart.so.0')).existsSync();
    } catch (_) {
      return false;
    }
  }

  static String? _findDartToolLibDirectory(String currentDirectoryPath) {
    var cursor = Directory(currentDirectoryPath).absolute;
    while (true) {
      final dartToolLib = path.join(cursor.path, '.dart_tool', 'lib');
      if (_containsWindowsNativeModules(dartToolLib)) {
        return dartToolLib;
      }

      final parent = cursor.parent;
      if (parent.path == cursor.path) {
        break;
      }
      cursor = parent;
    }

    return null;
  }

  /// Parses `/proc/self/maps` content and returns the module directory.
  ///
  /// This is exposed for testability.
  static String? parseBackendModuleDirectoryFromProcMaps(String mapsContent) {
    for (final rawLine in mapsContent.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final slashIndex = line.indexOf('/');
      if (slashIndex < 0) {
        continue;
      }

      final mappedPath = line.substring(slashIndex).trim();
      final normalizedPath = mappedPath.endsWith(' (deleted)')
          ? mappedPath.substring(0, mappedPath.length - ' (deleted)'.length)
          : mappedPath;

      if (!_linuxLlamadartProcMapsPattern.hasMatch(normalizedPath)) {
        continue;
      }

      return path.dirname(normalizedPath);
    }

    return null;
  }

  LlamaCppObjectCalls _resolveObjectCalls() {
    final calls = LlamaCppObjectCalls.resolve(
      isWindows: Platform.isWindows,
      mixedBatchResolver: () => LlamaCppMixedBatchApi.tryResolve(
        isWindows: Platform.isWindows,
        mtmdSymbol: _mixedMtmdSymbol,
      ),
    );
    if (calls.exit == null) {
      LlamaLogger.instance.warning(
        'The loaded llama.cpp runtime does not export the exit-teardown '
        'functions (llama_dart_exit_free and the llama_dart_ calls that go '
        'with it; llamadart-native ${ExitTeardownApi.minimumNativeRelease} '
        'or later is needed), so models and contexts are '
        'created with the upstream llama.cpp functions. The runtime then '
        'frees nothing at process exit: an Apple process that exits with '
        'one still allocated on Metal aborts in ggml-metal. Use the '
        'package-pinned native runtime $llamaCppTag or a newer one.',
      );
    } else if (calls.failures.barrier == null) {
      LlamaLogger.instance.warning(
        'The loaded llama.cpp runtime does not export the exception barrier '
        '(llama_dart_last_error and the llama_dart_ wrappers that go with '
        'it; llamadart-native ${NativeBarrierApi.minimumNativeRelease} or '
        'later is needed), so a C++ exception llama.cpp throws still ends '
        'the process. Use the package-pinned native runtime $llamaCppTag or '
        'a newer one.',
      );
    }
    return calls;
  }

  /// Throws [LlamaStateException] when an earlier llama.cpp exception left
  /// [model] free-only.
  void _ensureModelUsable(_LlamaModelWrapper model) {
    _calls.failures.ensureUsable(model.pointer, 'This model');
    _calls.failures.ensureUsable(
      llama_model_get_vocab(model.pointer),
      'This model',
    );
  }

  /// Throws [LlamaStateException] when an earlier llama.cpp exception left
  /// the context of [contextHandle] or its model free-only.
  void _ensureContextUsable(int contextHandle, _LlamaContextWrapper ctx) {
    _calls.failures.ensureUsable(ctx.pointer, 'This context');
    final model = _models[_contextToModel[contextHandle]];
    if (model != null) _ensureModelUsable(model);
  }

  void _ensureNoActiveTts(int contextHandle, String operation) {
    if (_activeTtsContextHandle == contextHandle) {
      throw LlamaStateException(
        'Cannot $operation while text-to-speech is active on this context.',
      );
    }
  }

  /// Loads a model from the specified [modelPath].
  ///
  /// Returns a handle to the loaded model.
  /// Throws an [Exception] if the file does not exist or fails to load.
  int loadModel(String modelPath, ModelParams modelParams) {
    modelParams = resolveComputeDeviceParams(
      modelParams,
      isAndroid: _isAndroid,
      isIosSimulator: _isIosSimulator,
      isMacosX64: _isMacosX64,
      platform: Platform.operatingSystem,
    );
    final modelFileSize = _validateGgufModelFile(modelPath, 'Model');

    _applyConfiguredLogLevel();
    final effectiveBackend = resolvePreferredBackendForLoad(
      modelParams,
      isAndroid: _isAndroid,
      isIosSimulator: _isIosSimulator,
      isMacosX64: _isMacosX64,
    );

    _prepareBackendsForModelLoad(effectiveBackend);

    final mparams = llama_model_default_params();
    var preferredDevices = _createPreferredDeviceList(effectiveBackend);
    var gpuLayers = resolveGpuLayersForLoad(
      modelParams,
      isAndroid: _isAndroid,
      isIosSimulator: _isIosSimulator,
      isMacosX64: _isMacosX64,
    );
    var forcedCpuFallback = false;

    final explicitGpuBackend =
        effectiveBackend != GpuBackend.auto &&
        effectiveBackend != GpuBackend.cpu;
    if (explicitGpuBackend &&
        preferredDevices == null &&
        _shouldForceCpuFallbackForMissingPreferredDevices(effectiveBackend)) {
      // Honor explicit backend intent: if requested GPU backend is unavailable,
      // fall back to CPU instead of letting another GPU backend auto-select.
      preferredDevices = _createPreferredDeviceList(GpuBackend.cpu);
      gpuLayers = 0;
      forcedCpuFallback = true;
    }
    if (modelParams.device == ComputeDevice.gpu &&
        (forcedCpuFallback || !_hasGpuDevice(effectiveBackend))) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      throw LlamaUnsupportedException(
        _noGpuMessage(effectiveBackend, forcedCpuFallback: forcedCpuFallback),
      );
    }
    final loadsOnNoGpu =
        gpuLayers != 0 &&
        preferredDevices == null &&
        _registryShowsNoGpuDevice();
    final unusableBackendModule =
        loadsOnNoGpu && explicitGpuBackend && _backendModuleDirectory != null;
    if (unusableBackendModule) {
      gpuLayers = 0;
    }
    final vulkan = _resolveVulkanLoadDevices(
      effectiveBackend,
      gpuLayers: gpuLayers,
      splitMode: modelParams.splitMode.llamaCppValue,
      mainGpu: modelParams.mainGpu,
    );
    if (vulkan.refused) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      if (modelParams.device == ComputeDevice.gpu) {
        throw LlamaUnsupportedException(
          'ComputeDevice.gpu is not available for llama.cpp on '
          '${Platform.operatingSystem}: ${vulkan.unsupported}. Use '
          'ComputeDevice.auto to run on the CPU instead.',
        );
      }
      preferredDevices = _createPreferredDeviceList(GpuBackend.cpu);
      gpuLayers = 0;
    } else if (vulkan.devices case final usable?) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      preferredDevices = _createDeviceList(usable);
    }
    final ggml_backend_buffer_type_t? cpuMoeBuffer;
    try {
      _checkMoeCacheSupported(
        modelParams,
        backend: effectiveBackend,
        gpuLayers: gpuLayers,
        vulkan: vulkan,
      );
      cpuMoeBuffer = _cpuMoeBufferType(modelParams.cpuMoeLayers);
    } catch (_) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      rethrow;
    }
    final mtmdUseGpu = resolveMtmdUseGpuForLoad(
      modelParams,
      gpuLayers,
      modelPath: modelPath,
      isAndroid: _isAndroid,
    );

    final GpuDevicePlacement? placement;
    try {
      placement = _resolveGpuDevicePlacement(
        modelParams,
        backend: effectiveBackend,
        gpuLayers: gpuLayers,
        vulkan: vulkan,
      );
    } catch (_) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      rethrow;
    }
    if (placement != null) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      preferredDevices = _createDeviceList(placement.devices);
    }
    final Pointer<Float>? tensorSplit;
    try {
      _checkRowSplitSupported(modelParams, preferredDevices);
      tensorSplit = _createTensorSplit(placement);
    } catch (_) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      rethrow;
    }
    if (tensorSplit != null) {
      mparams.tensor_split = tensorSplit;
    }
    final cpuMoeOverrides = cpuMoeBuffer == null
        ? null
        : allocateTensorBufferOverrides(
            cpuMoeOverridePatterns(modelParams.cpuMoeLayers),
            cpuMoeBuffer,
            allocator: _modelLoadAllocator,
          );
    mparams.n_gpu_layers = gpuLayers;
    mparams.split_modeAsInt = modelParams.splitMode.llamaCppValue;
    mparams.main_gpu = modelParams.mainGpu;
    applyModelParams(mparams, modelParams);
    applyMoeCacheModelParams(mparams, modelParams);
    if (preferredDevices != null) {
      mparams.devices = preferredDevices;
    }
    if (cpuMoeOverrides != null) {
      mparams.tensor_buft_overrides = cpuMoeOverrides;
    }
    // Without a device list llama.cpp offloads to every registered GPU,
    // whichever backend was requested.
    final reportedBackend = preferredDevices == null
        ? GpuBackend.auto
        : modelParams.preferredBackend;

    Pointer<llama_model> modelPtr = nullptr;
    final modelPathPtr = modelPath.toNativeUtf8(allocator: _modelLoadAllocator);
    try {
      modelPtr = _loadOwnedModel(modelPathPtr.cast(), mparams);
      IsolateShutdownReleases.current.hold(
        ShutdownStage.model,
        _calls.modelFreeAddress,
        modelPtr,
      );
    } finally {
      _modelLoadAllocator.free(modelPathPtr);
      if (tensorSplit != null) {
        _modelLoadAllocator.free(tensorSplit);
      }
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      if (cpuMoeOverrides != null) {
        freeTensorBufferOverrides(
          cpuMoeOverrides,
          allocator: _modelLoadAllocator,
        );
      }
    }

    if (modelPtr == nullptr) {
      throw Exception(
        describeModelLoadFailure(
          sizeBytes: modelFileSize,
          backendDiagnostics: _backendDiagnostics(),
          startupDiagnostics: getStartupDiagnostics(),
        ),
      );
    }

    final model = _createModelWrapper(modelPtr, sourcePath: modelPath);
    final handle = _getHandle();
    _models[handle] = model;
    _loraAdapters[handle] = {};
    _modelToMtmdUseGpu[handle] = mtmdUseGpu;
    if (_moeExpertPlacementProblem(model, modelParams, gpuLayers)
        case final problem?) {
      freeModel(handle);
      throw LlamaUnsupportedException(problem);
    }
    final resolvedBackend = _resolveBackendNameForLoad(
      requestedBackend: reportedBackend,
      resolvedGpuLayers: gpuLayers,
      forcedCpuFallback: forcedCpuFallback,
    );
    _modelResolvedBackends[handle] = resolvedBackend;
    _modelBackendNames[handle] = placement == null
        ? resolvedBackend
        : '$resolvedBackend (${placement.deviceNames})';
    _modelResolvedGpuLayers[handle] = gpuLayers;
    _modelLoadParams[handle] = modelParams;
    if (placement != null) {
      _modelPlacements[handle] = placement;
    }
    if (loadsOnNoGpu ||
        selectsNoGpuDevice(
          splitMode: modelParams.splitMode.llamaCppValue,
          mainGpu: modelParams.mainGpu,
        )) {
      _modelsOnNoGpu.add(handle);
    }
    _activateModelReport(handle);
    if (vulkan.unsupported case final unsupported?) {
      LlamaLogger.instance.warning(
        vulkan.refused
            ? '$unsupported, so the model loaded on $resolvedBackend with 0 '
                  'GPU layers.'
            : '$unsupported, so the model loaded without that device, on '
                  '${vulkan.devices!.join(', ')}.',
      );
    }
    if (forcedCpuFallback) {
      final requested = effectiveBackend.name;
      LlamaLogger.instance.warning(
        'preferredBackend $requested was requested, but its backend module '
        'is not bundled for this platform, so the model loaded on '
        '$resolvedBackend with 0 GPU layers. To bundle it, add $requested to '
        'the llamadart_native_backends hook user-define in your app '
        'pubspec.yaml.',
      );
    }
    if (unusableBackendModule) {
      LlamaLogger.instance.warning(
        'preferredBackend ${effectiveBackend.name} was requested, but its '
        'backend module failed to load or found no usable device, so the '
        'model loaded on $resolvedBackend with 0 GPU layers.',
      );
    }
    final simulatorWarning = iosSimulatorMetalWarning(
      isIosSimulator: _isIosSimulator,
      resolvedGpuLayers: _activeResolvedGpuLayers,
    );
    if (simulatorWarning != null) {
      LlamaLogger.instance.warning(simulatorWarning);
    }
    final intelWarning = macosX64MetalWarning(
      isMacosX64: _isMacosX64,
      resolvedGpuLayers: _activeResolvedGpuLayers,
    );
    if (intelWarning != null) {
      LlamaLogger.instance.warning(intelWarning);
    }

    return handle;
  }

  void _activateModelReport(int handle) {
    final params = _modelLoadParams[handle]!;
    final noGpu = selectsNoGpuDevice(
      splitMode: params.splitMode.llamaCppValue,
      mainGpu: params.mainGpu,
    );
    // Retain load metadata for auxiliary device selection and apply placement
    // separately where a consumer must follow the model onto the CPU.
    _activeBackendName = noGpu
        ? _backendDisplayName('cpu')
        : _modelBackendNames[handle]!;
    _activeResolvedGpuLayers = noGpu || _modelsOnNoGpu.contains(handle)
        ? 0
        : _modelResolvedGpuLayers[handle]!;
  }

  /// What a load on [backend] with [gpuLayers] layers does about Vulkan
  /// devices below Vulkan 1.2 among the devices llama.cpp would use for it.
  VulkanLoadDecision _resolveVulkanLoadDevices(
    GpuBackend backend, {
    required int gpuLayers,
    required int splitMode,
    required int mainGpu,
  }) => resolveVulkanLoadDecision(
    usesGpu: gpuLayers != 0 && backend != GpuBackend.cpu,
    backendRegistry: ggmlGpuRegistryName(backend),
    splitMode: splitMode,
    mainGpu: mainGpu,
    registered: _registeredDevices,
    probe: () => _vulkanDeviceProbe,
    isAndroid: _isAndroid,
  );

  /// Throws [LlamaUnsupportedException] when the MoE expert cache budget of
  /// [params] cannot run on the devices a load on [backend] with [gpuLayers]
  /// uses.
  void _checkMoeCacheSupported(
    ModelParams params, {
    required GpuBackend backend,
    required int gpuLayers,
    required VulkanLoadDecision vulkan,
  }) {
    if (params.moeCacheBytes == 0) return;
    final splitMode = params.splitMode.llamaCppValue;
    final List<GgmlDeviceEntry> devices;
    if (gpuLayers == 0 || backend == GpuBackend.cpu) {
      devices = const [];
    } else {
      final registered = _registeredDevices();
      final registry = ggmlGpuRegistryName(backend)?.toLowerCase();
      final listed =
          vulkan.devices ??
          [
            for (final device in registered)
              if (device.registry.toLowerCase() == registry) device,
          ];
      devices = selectModelDevices(
        registered: registered,
        listed: listed.isEmpty ? null : listed,
        splitMode: splitMode,
        mainGpu: params.mainGpu,
      );
    }
    final unsupported = moeCacheUnsupportedReason(
      gpuLayers: gpuLayers,
      splitMode: splitMode,
      devices: devices,
    );
    if (unsupported == null) return;
    throw LlamaUnsupportedException(
      'ModelParams.moeCacheBytes, the llama.cpp MoE expert cache, is not '
      'available for this load on ${Platform.operatingSystem}: $unsupported. '
      'Set moeCacheBytes to 0.',
    );
  }

  /// Throws [LlamaUnsupportedException] when [params] asks for row split and
  /// a device the load passes in [listed], or llama.cpp selects without a
  /// list, has no split buffer types, which llama.cpp would only find out
  /// while it loads the model.
  void _checkRowSplitSupported(
    ModelParams params,
    Pointer<ggml_backend_dev_t>? listed,
  ) {
    if (params.splitMode != ModelSplitMode.row) return;
    final registered = _registeredDevices();
    final List<GgmlDeviceEntry> devices;
    if (listed == null) {
      devices = selectModelDevices(
        registered: registered,
        listed: null,
        splitMode: params.splitMode.llamaCppValue,
        mainGpu: params.mainGpu,
      );
    } else {
      final props = calloc<ggml_backend_dev_props>();
      try {
        devices = [
          for (var i = 0; listed[i] != nullptr; i++)
            registered.firstWhere(
              (entry) => entry.device == listed[i],
              orElse: () => _describeDevice(listed[i], props),
            ),
        ];
      } finally {
        calloc.free(props);
      }
    }
    final unsupported = rowSplitUnsupportedReason(
      splitMode: params.splitMode.llamaCppValue,
      devices: devices,
      hasSplitBufferType: _splitBufferTypeProbeOverride ?? _hasSplitBufferType,
    );
    if (unsupported == null) return;
    throw LlamaUnsupportedException(
      'ModelSplitMode.row, llama.cpp row split, is not available for this '
      'load on ${Platform.operatingSystem}: $unsupported. Use '
      'ModelSplitMode.layer, the default, to split the model by layers '
      'instead.',
    );
  }

  /// Whether the backend registry of [entry] exports
  /// `ggml_backend_split_buffer_type`, as llama.cpp looks it up for row split.
  /// A device or symbol that cannot be read counts as having it, which leaves
  /// the decision to llama.cpp.
  bool _hasSplitBufferType(GgmlDeviceEntry entry) {
    final device = entry.device;
    if (device == null || device == nullptr) return true;
    final registry = _ggmlBackendDevBackendReg(device);
    if (registry == nullptr) return true;
    final name = 'ggml_backend_split_buffer_type'.toNativeUtf8();
    try {
      final proc = _ggmlBackendRegGetProcAddress(registry, name.cast());
      return proc == null || proc != nullptr;
    } finally {
      malloc.free(name);
    }
  }

  /// The CPU buffer type that keeps the experts of [cpuMoeLayers] layers in
  /// host memory, or `null` for `0`.
  ggml_backend_buffer_type_t? _cpuMoeBufferType(int cpuMoeLayers) {
    if (cpuMoeLayers == 0) return null;
    final cpu = _ggmlBackendDevByType(
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU,
    );
    final buft = cpu == nullptr ? nullptr : _ggmlBackendDevBufferType(cpu);
    if (buft == nullptr) {
      throw LlamaUnsupportedException(
        'ModelParams.cpuMoeLayers needs the llama.cpp CPU backend, which '
        'this runtime does not register on ${Platform.operatingSystem}.',
      );
    }
    return buft;
  }

  /// Why the MoE fields of [params] do nothing for the loaded [model], or
  /// `null` when they apply or are unset.
  String? _moeExpertPlacementProblem(
    _LlamaModelWrapper model,
    ModelParams params,
    int gpuLayers,
  ) {
    if (params.cpuMoeLayers == 0) return null;
    final architecture = _readModelMetadataValue(
      model.pointer,
      'general.architecture',
    );
    final experts = architecture == null
        ? null
        : int.tryParse(
            _readModelMetadataValue(
                  model.pointer,
                  '$architecture.expert_count',
                ) ??
                '',
          );
    if (experts == null || experts <= 0) {
      return 'ModelParams.cpuMoeLayers and moeCacheBytes apply to '
          'Mixture-of-Experts models, and this ${architecture ?? 'model'} '
          'model has no experts. Leave them at 0.';
    }
    if (params.moeCacheBytes == 0) return null;
    final cacheable = moeCacheableLayerCount(
      layerCount: llama_model_n_layer(model.pointer),
      gpuLayers: gpuLayers,
      cpuMoeLayers: params.cpuMoeLayers,
    );
    if (cacheable > 0) return null;
    return 'ModelParams.moeCacheBytes caches the host experts of offloaded '
        'layers, and no layer that cpuMoeLayers ${params.cpuMoeLayers} keeps '
        'in host memory is among the $gpuLayers gpuLayers, which llama.cpp '
        'takes from the end of the model. Raise gpuLayers or cpuMoeLayers.';
  }

  /// The registered ggml devices, in registry order.
  List<GgmlDeviceEntry> _registeredDevices() {
    final override = _registeredDevicesOverride;
    if (override != null) return override();
    final props = calloc<ggml_backend_dev_props>();
    try {
      return [
        for (var i = 0; i < _ggmlBackendDevCount(); i++)
          if (_ggmlBackendDevGet(i) case final device when device != nullptr)
            _describeDevice(device, props),
      ];
    } finally {
      calloc.free(props);
    }
  }

  GgmlDeviceEntry _describeDevice(
    ggml_backend_dev_t device,
    Pointer<ggml_backend_dev_props> props,
  ) {
    final hasProps = _ggmlBackendDevGetProps(device, props);
    return GgmlDeviceEntry(
      name: _utf8OrEmpty(_ggmlBackendDevName(device)),
      type: _ggmlBackendDevType(device),
      registry: _registryNameOf(device),
      description: hasProps ? _utf8OrEmpty(props.ref.description) : '',
      deviceId: hasProps && props.ref.device_id != nullptr
          ? _utf8OrEmpty(props.ref.device_id)
          : null,
      device: device,
    );
  }

  String _registryNameOf(ggml_backend_dev_t device) {
    final registry = _ggmlBackendDevBackendReg(device);
    return registry == nullptr
        ? ''
        : _utf8OrEmpty(_ggmlBackendRegName(registry));
  }

  int _registeredVulkanDeviceCount() =>
      _registeredDevices().where((device) => device.isVulkan).length;

  Pointer<ggml_backend_dev_t> _createDeviceList(List<GgmlDeviceEntry> devices) {
    final pointers = [
      for (final entry in devices)
        if (entry.device case final device? when device != nullptr) device,
    ];
    final list = _modelLoadAllocator<ggml_backend_dev_t>(pointers.length + 1);
    for (final (index, device) in pointers.indexed) {
      list[index] = device;
    }
    list[pointers.length] = nullptr;
    return list;
  }

  /// The devices and tensor split [params] place a load on [backend] with
  /// [gpuLayers] on, or `null` when it sets neither
  /// [ModelParams.gpuDevices] nor [ModelParams.tensorSplit].
  ///
  /// Throws [LlamaUnsupportedException] instead of loading on other devices:
  /// when the load fell back to the CPU, and when a listed Vulkan device is
  /// one ggml-vulkan cannot drive.
  GpuDevicePlacement? _resolveGpuDevicePlacement(
    ModelParams params, {
    required GpuBackend backend,
    required int gpuLayers,
    required VulkanLoadDecision vulkan,
  }) {
    if (params.gpuDevices == null && params.tensorSplit == null) return null;
    final field = params.gpuDevices != null ? 'gpuDevices' : 'tensorSplit';
    final capability =
        'ModelParams.$field, llama.cpp multi-GPU placement, is not available '
        'on ${Platform.operatingSystem}';
    if (gpuLayers == 0) {
      final autoHint =
          backend == GpuBackend.cpu &&
              params.preferredBackend == GpuBackend.auto
          ? ' GpuBackend.auto loads on the CPU on this platform; set a GPU '
                'preferredBackend or use ComputeDevice.gpu.'
          : '';
      throw LlamaUnsupportedException(
        '$capability: the ${backend.name} backend has no usable GPU here'
        '${vulkan.unsupported == null ? '' : ' (${vulkan.unsupported})'}, '
        'so the load would run on the CPU.$autoHint',
      );
    }
    final placement = resolveGpuDevicePlacement(
      params,
      backend: backend,
      registered: _registeredDevices(),
      backendOf: gpuBackendFromRegName,
      maxDevices: llama_max_devices(),
      platform: Platform.operatingSystem,
    )!;
    if (vulkan.unsupported case final unsupported?) {
      final usable = vulkan.devices ?? const <GgmlDeviceEntry>[];
      for (final device in placement.devices) {
        if (device.isVulkan &&
            !usable.any((entry) => entry.device == device.device)) {
          throw LlamaUnsupportedException('$capability: $unsupported.');
        }
      }
    }
    return placement;
  }

  /// The `llama_model_params.tensor_split` array of [placement], or `null`
  /// without a split.
  Pointer<Float>? _createTensorSplit(GpuDevicePlacement? placement) {
    final split = placement?.tensorSplit;
    if (split == null) return null;
    return allocateTensorSplit(
      split,
      maxDevices: llama_max_devices(),
      allocator: _modelLoadAllocator,
    );
  }

  /// Whether a GPU device of [backend], or any GPU device for
  /// [GpuBackend.auto], is registered after the backend modules load.
  bool _hasGpuDevice(GpuBackend backend) {
    final types = (_deviceTypesOverride ?? _registeredDeviceTypes)(backend);
    return types.any((type) {
      return type == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value ||
          type == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value;
    });
  }

  /// Whether llama.cpp, given no device list, has no GPU to place layers on.
  ///
  /// `false` when the runtime lacks the registry functions: they then read as
  /// no devices, which says nothing about the GPUs llama.cpp itself sees.
  bool _registryShowsNoGpuDevice() =>
      !_hasGpuDevice(GpuBackend.auto) && !_backendRegistrySymbolUnavailable;

  List<int> _registeredDeviceTypes(GpuBackend backend) {
    final devices = backend == GpuBackend.auto
        ? [
            for (var i = 0; i < _ggmlBackendDevCount(); i++)
              _ggmlBackendDevGet(i),
          ]
        : _resolvePreferredDevices(backend) ?? const <ggml_backend_dev_t>[];
    return [
      for (final device in devices)
        if (device != nullptr) _ggmlBackendDevType(device),
    ];
  }

  String _noGpuMessage(GpuBackend backend, {required bool forcedCpuFallback}) {
    final platform = Platform.operatingSystem;
    final requested = backend == GpuBackend.auto
        ? 'a GPU'
        : 'the ${backend.name} backend';
    final needs =
        'ComputeDevice.gpu needs $requested for llama.cpp on $platform';
    const useCpu = 'Use ComputeDevice.auto to run on the CPU instead.';
    if (forcedCpuFallback) {
      return '$needs, but its backend module is not bundled. Add '
          '${backend.name} to the llamadart_native_backends hook user-define '
          'in your app pubspec.yaml. $useCpu';
    }
    final devices = getBackendInfo().join(', ');
    // Without a device of its explicit backend, a ComputeDevice.auto load
    // offloads to any other registered GPU, such as Metal on the consolidated
    // Apple runtime, instead of running on the CPU.
    final otherGpu = backend == GpuBackend.auto
        ? null
        : _registeredGpuBackendOtherThan(backend);
    if (otherGpu != null) {
      return '$needs, but no ${backend.name} GPU device is available '
          '(devices: $devices). Use GpuBackend.${otherGpu.name} to run on the '
          '${otherGpu.name} GPU, or ComputeDevice.cpu to run on the CPU.';
    }
    return '$needs, but no GPU device is available (devices: $devices). '
        '$useCpu';
  }

  GpuBackend? _registeredGpuBackendOtherThan(GpuBackend backend) {
    for (final device in _registeredDevices()) {
      if (device.type !=
              ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value &&
          device.type !=
              ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value) {
        continue;
      }
      final registry = device.registry.toLowerCase();
      for (final candidate in GpuBackend.values) {
        if (candidate != backend &&
            ggmlGpuRegistryName(candidate)?.toLowerCase() == registry) {
          return candidate;
        }
      }
    }
    return null;
  }

  int _validateGgufModelFile(String modelPath, String label) {
    final modelFile = File(modelPath);
    if (!modelFile.existsSync()) {
      throw LlamaModelException("$label file not found: $modelPath");
    }
    final modelFileSize = modelFile.lengthSync();
    if (modelFileSize <= 0) {
      throw LlamaModelException("$label file is empty: $modelPath");
    }
    if (!_looksLikeGguf(modelFile)) {
      throw LlamaModelException(
        "$label file does not appear to be GGUF: $modelPath. "
        "Please verify the download completed correctly.",
      );
    }
    return modelFileSize;
  }

  String _speculativeDraftModelCacheKey(
    int targetModelHandle,
    String draftModelPath,
    int resolvedGpuLayers,
    bool loadMtp,
  ) {
    final normalizedPath = File(draftModelPath).absolute.path;
    return '$targetModelHandle\x00$normalizedPath\x00$resolvedGpuLayers\x00$loadMtp';
  }

  _LlamaModelWrapper _loadSpeculativeDraftModel(
    int targetModelHandle,
    String draftModelPath,
    String label, {
    required bool loadMtp,
  }) {
    final modelFileSize = _validateGgufModelFile(draftModelPath, label);
    final targetModelParams =
        _modelLoadParams[targetModelHandle] ?? const ModelParams();
    final targetBackendName = _modelBackendNames[targetModelHandle];
    final targetOnCpu = targetBackendName == _backendDisplayName('cpu');
    final effectiveBackend = targetOnCpu
        ? GpuBackend.cpu
        : resolvePreferredBackendForLoad(
            targetModelParams,
            isAndroid: _isAndroid,
            isIosSimulator: _isIosSimulator,
            isMacosX64: _isMacosX64,
          );
    final targetResolvedGpuLayers =
        _modelResolvedGpuLayers[targetModelHandle] ??
        resolveGpuLayersForLoad(
          targetModelParams,
          isAndroid: _isAndroid,
          isIosSimulator: _isIosSimulator,
          isMacosX64: _isMacosX64,
        );
    final draftBackend = effectiveBackend;
    final draftGpuLayers = targetResolvedGpuLayers;
    // llama.cpp rejects a CPU device list in row mode. Layer mode places the
    // same on the CPU, and no-list row mode would fail on any GPU registered
    // since the target loaded.
    final draftSplitMode =
        targetOnCpu && targetModelParams.splitMode == ModelSplitMode.row
        ? ModelSplitMode.layer
        : targetModelParams.splitMode;
    final cacheKey = _speculativeDraftModelCacheKey(
      targetModelHandle,
      draftModelPath,
      draftGpuLayers,
      loadMtp,
    );

    final cached = _speculativeDraftModels[cacheKey];
    if (cached != null) {
      return cached;
    }

    _prepareBackendsForModelLoad(draftBackend);

    final mparams = llama_model_default_params();
    var preferredDevices = _createPreferredDeviceList(draftBackend);
    // The target load already decided whether the GPU is usable; a draft
    // only needs the same devices left out.
    final vulkan = _resolveVulkanLoadDevices(
      draftBackend,
      gpuLayers: draftGpuLayers,
      splitMode: draftSplitMode.llamaCppValue,
      mainGpu: targetModelParams.mainGpu,
    );
    if (vulkan.devices case final usable?) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      preferredDevices = _createDeviceList(usable);
    }
    final GpuDevicePlacement? placement;
    try {
      placement = _resolveGpuDevicePlacement(
        targetModelParams,
        backend: draftBackend,
        gpuLayers: draftGpuLayers,
        vulkan: vulkan,
      );
    } catch (_) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      rethrow;
    }
    if (placement != null) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      preferredDevices = _createDeviceList(placement.devices);
    }
    mparams.n_gpu_layers = draftGpuLayers;
    mparams.split_modeAsInt = draftSplitMode.llamaCppValue;
    mparams.main_gpu = targetModelParams.mainGpu;
    applyModelParams(mparams, targetModelParams.copyWith(loadMtp: loadMtp));
    if (preferredDevices != null) {
      mparams.devices = preferredDevices;
    }
    final Pointer<Float>? tensorSplit;
    try {
      tensorSplit = _createTensorSplit(placement);
    } catch (_) {
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      rethrow;
    }
    if (tensorSplit != null) {
      mparams.tensor_split = tensorSplit;
    }

    Pointer<llama_model> modelPtr = nullptr;
    final modelPathPtr = draftModelPath.toNativeUtf8(
      allocator: _modelLoadAllocator,
    );
    try {
      modelPtr = _loadOwnedModel(modelPathPtr.cast(), mparams);
      IsolateShutdownReleases.current.hold(
        ShutdownStage.model,
        _calls.modelFreeAddress,
        modelPtr,
      );
    } finally {
      _modelLoadAllocator.free(modelPathPtr);
      if (preferredDevices != null) {
        _modelLoadAllocator.free(preferredDevices);
      }
      if (tensorSplit != null) {
        _modelLoadAllocator.free(tensorSplit);
      }
    }

    if (modelPtr == nullptr) {
      throw Exception(
        describeDraftModelLoadFailure(
          label: label,
          path: draftModelPath,
          sizeBytes: modelFileSize,
          backendDiagnostics: _backendDiagnostics(),
          startupDiagnostics: getStartupDiagnostics(),
        ),
      );
    }

    final wrapper = _createModelWrapper(modelPtr, sourcePath: draftModelPath);
    _speculativeDraftModels[cacheKey] = wrapper;
    _modelToSpeculativeDraftModelKeys
        .putIfAbsent(targetModelHandle, () => <String>{})
        .add(cacheKey);
    return wrapper;
  }

  String _resolveBackendNameForLoad({
    required GpuBackend requestedBackend,
    required int resolvedGpuLayers,
    required bool forcedCpuFallback,
  }) {
    if (forcedCpuFallback || resolvedGpuLayers <= 0) {
      return _backendDisplayName('cpu');
    }

    final backendInfo = getBackendInfo().join(', ');

    switch (requestedBackend) {
      case GpuBackend.auto:
        return _resolveAutoBackendName(backendInfo) ??
            _backendDisplayName('cpu');
      case GpuBackend.cpu:
        return _backendDisplayName('cpu');
      case GpuBackend.vulkan:
        return _resolveExplicitBackendName(GpuBackend.vulkan, backendInfo);
      case GpuBackend.metal:
        return _resolveExplicitBackendName(GpuBackend.metal, backendInfo);
      case GpuBackend.cuda:
        return _resolveExplicitBackendName(GpuBackend.cuda, backendInfo);
      case GpuBackend.blas:
        return _resolveExplicitBackendName(GpuBackend.blas, backendInfo);
      case GpuBackend.opencl:
        return _resolveExplicitBackendName(GpuBackend.opencl, backendInfo);
      case GpuBackend.hip:
        return _resolveExplicitBackendName(GpuBackend.hip, backendInfo);
    }
  }

  _LlamaModelWrapper _createModelWrapper(
    Pointer<llama_model> modelPointer, {
    required String sourcePath,
  }) {
    try {
      final vocab = llama_model_get_vocab(modelPointer);
      return _LlamaModelWrapper(
        modelPointer,
        _calls,
        sourcePath: sourcePath,
        vocabSize: llama_vocab_n_tokens(vocab),
        suppressedTokens: readModelSuppressTokens(vocab),
      );
    } catch (_) {
      IsolateShutdownReleases.current.release(modelPointer);
      _calls.freeModel(modelPointer);
      rethrow;
    }
  }

  String _resolveExplicitBackendName(GpuBackend backend, String backendInfo) {
    if (_backendInfoContainsBackendMarker(backendInfo, backend)) {
      return _backendDisplayName(backend.name);
    }
    return _backendDisplayName('cpu');
  }

  String? _resolveAutoBackendName(String backendInfo) {
    const preferredOrder = <GpuBackend>[
      GpuBackend.metal,
      GpuBackend.cuda,
      GpuBackend.hip,
      GpuBackend.vulkan,
      GpuBackend.opencl,
      GpuBackend.blas,
    ];

    for (final backend in preferredOrder) {
      if (_backendInfoContainsBackendMarker(backendInfo, backend)) {
        return _backendDisplayName(backend.name);
      }
    }

    return null;
  }

  bool _shouldForceCpuFallbackForMissingPreferredDevices(
    GpuBackend requestedBackend,
  ) {
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      // Consolidated runtimes (notably Apple) do not expose per-backend
      // dynamic modules. Missing preferred-device pointers here does not
      // reliably mean GPU is unavailable.
      return false;
    }

    return !_isBackendModuleBundled(requestedBackend.name);
  }

  static bool _backendInfoContainsBackendMarker(
    String value,
    GpuBackend backend,
  ) {
    final lower = value.toLowerCase();
    switch (backend) {
      case GpuBackend.cpu:
        return lower.contains('cpu') || lower.contains('llvm');
      case GpuBackend.auto:
        return false;
      case GpuBackend.metal:
      case GpuBackend.vulkan:
      case GpuBackend.opencl:
      case GpuBackend.hip:
      case GpuBackend.cuda:
      case GpuBackend.blas:
        return lower.contains(backend.name) ||
            lower.contains(ggmlGpuRegistryName(backend)!.toLowerCase());
    }
  }

  void _prepareBackendsForModelLoad(GpuBackend preferredBackend) {
    // Apple bundles are consolidated into a single native library and do not
    // ship separate ggml backend modules.
    if ((Platform.isMacOS || Platform.isIOS) &&
        _backendModuleDirectory == null) {
      return;
    }
    final backendModuleDirectory = _backendModuleDirectory;

    switch (preferredBackend) {
      case GpuBackend.auto:
        final loadedAll = backendModuleDirectory == null
            ? _tryLoadAllBackendsBestEffort()
            : _tryLoadAllBackendsFromPathBestEffort(backendModuleDirectory);

        if (!loadedAll) {
          // Fallback when load-all symbols are unavailable.
          _tryLoadBackendModuleIfBundled('cpu');
        }

        if (Platform.isAndroid || Platform.isLinux || Platform.isWindows) {
          _tryLoadBackendModuleIfBundled('vulkan');
        }
        if (Platform.isLinux || Platform.isWindows) {
          _tryLoadBackendModuleIfBundled('blas');
          _tryLoadBackendModuleIfBundled('cuda');
        }
        if (Platform.isLinux) {
          _tryLoadBackendModuleIfBundled('hip');
        }
        return;
      case GpuBackend.cpu:
        // Explicit CPU mode must not initialize optional GPU backends.
        _tryLoadBackendModuleIfBundled('cpu');
        return;
      case GpuBackend.vulkan:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('vulkan');
        return;
      case GpuBackend.metal:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('metal');
        return;
      case GpuBackend.cuda:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('cuda');
        return;
      case GpuBackend.blas:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('blas');
        return;
      case GpuBackend.opencl:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('opencl');
        return;
      case GpuBackend.hip:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('hip');
        return;
    }
  }

  bool _tryLoadBackendModule(String backend) {
    if (_backendLoadSymbolUnavailable) {
      return false;
    }

    if (_loadedBackendModules.contains(backend)) {
      return true;
    }
    if (_failedBackendModules.contains(backend)) {
      return false;
    }

    final fileNameCandidates = _libraryCandidates.backend(backend);
    final candidates = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(backendModuleDirectory, fileName));
      }
    } else {
      // No resolved module directory: rely on platform search paths.
      candidates.addAll(fileNameCandidates);
    }

    _preloadWindowsBackendDependencies(backend);

    final failures = BackendProbeFailures();
    if (backendModuleDirectory != null && fileNameCandidates.isEmpty) {
      failures.add(_libraryCandidates.backendFileName(backend), 'file missing');
    }
    for (final candidate in candidates) {
      if (path.isAbsolute(candidate) && !File(candidate).existsSync()) {
        failures.add(candidate, 'file missing');
        continue;
      }

      final alteredSearchPathHandle = _preloadWindowsBackendModule(
        candidate,
        backend,
      );
      final libraryPathPtr = candidate.toNativeUtf8();
      try {
        ggml_backend_reg_t reg;
        try {
          reg = ggml_backend_load(libraryPathPtr.cast());
        } on ArgumentError {
          _resolveGgmlFallbackFunctions();
          final fallback = _ggmlBackendLoadFallback;
          if (fallback == null) {
            // Optional dynamic-loader symbol can be missing from the primary
            // FFI asset in split bundles. If ggml fallback is unavailable,
            // stop retrying.
            _recordMissingGgmlSymbol('`ggml_backend_load`');
            _backendLoadSymbolUnavailable = true;
            return false;
          }
          reg = fallback(libraryPathPtr.cast());
        }
        if (reg == nullptr) {
          failures.add(candidate, '`ggml_backend_load` returned null');
          continue;
        }

        // Best-effort compatibility call for runtimes where explicit register is
        // required after dynamic load. We still consider the module load
        // successful even if this symbol is unavailable.
        _registerBackendRegBestEffort(reg);
        _loadedBackendModules.add(backend);
        _failedBackendModules.remove(backend);
        return true;
      } finally {
        if (alteredSearchPathHandle != nullptr) {
          _freeWindowsBackendModule(
            alteredSearchPathHandle,
            candidate,
            backend,
          );
        }
        malloc.free(libraryPathPtr);
      }
    }

    if (_tryRegisterBackendModuleViaAsset(backend, failures)) {
      return true;
    }

    _failedBackendModules.add(backend);
    final missingLoader = describeMissingWindowsBackendLoader(
      backend,
      isWindows: _isWindows,
      missingWindowsLibraries: _missingWindowsLibraries,
    );
    _recordStartupDiagnostic(
      'Backend module `$backend` not loaded from any candidate: '
      '${failures.describe()}.$missingLoader',
    );
    return false;
  }

  Pointer<Void> _preloadWindowsBackendModule(
    String libraryPath,
    String backend,
  ) {
    final flags = windowsBackendModuleLoadFlags(libraryPath);
    if (!Platform.isWindows || flags == 0) {
      return nullptr;
    }

    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final setErrorMode = kernel32
          .lookupFunction<_SetErrorModeNative, _SetErrorModeDart>(
            'SetErrorMode',
          );
      final loadLibraryExW = kernel32
          .lookupFunction<_LoadLibraryExWNative, _LoadLibraryExWDart>(
            'LoadLibraryExW',
          );
      final oldMode = setErrorMode(_semFailCriticalErrors);
      setErrorMode(oldMode | _semFailCriticalErrors);

      final libraryPathPtr = libraryPath.toNativeUtf16();
      try {
        final handle = loadLibraryExW(libraryPathPtr, nullptr, flags);
        if (handle == nullptr) {
          _recordStartupDiagnostic(
            'Failed to preload Windows backend module `$libraryPath` with '
            'LOAD_WITH_ALTERED_SEARCH_PATH for `$backend`.',
          );
        }
        return handle;
      } finally {
        malloc.free(libraryPathPtr);
        setErrorMode(oldMode);
      }
    } catch (error) {
      _recordStartupDiagnostic(
        'Failed to preload Windows backend module `$libraryPath` with '
        'LOAD_WITH_ALTERED_SEARCH_PATH for `$backend`: $error',
      );
      return nullptr;
    }
  }

  void _recordWindowsBackendModuleReleaseFailure(
    String libraryPath,
    String backend, [
    Object? error,
  ]) {
    _recordStartupDiagnostic(
      'Failed to release temporary Windows backend module preload for '
      '`$libraryPath` (`$backend`)${error == null ? '.' : ': $error'}',
      category: StartupDiagnosticCategory.teardown,
    );
  }

  void _preloadWindowsBackendDependencies(String backend) {
    if (!Platform.isWindows) {
      return;
    }

    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return;
    }

    final cacheKey =
        '$backend|${path.normalize(backendModuleDirectory).toLowerCase()}';
    if (_preloadedBackendDependencyLibraries.containsKey(cacheKey)) {
      return;
    }

    final handles = <DynamicLibrary>[];
    _preloadedBackendDependencyLibraries[cacheKey] = handles;

    for (final dependencyPath in windowsBackendDependencyPaths(
      backendModuleDirectory,
      backend,
    )) {
      try {
        handles.add(DynamicLibrary.open(dependencyPath));
      } catch (error) {
        _recordStartupDiagnostic(
          'Failed to preload Windows backend dependency '
          '`$dependencyPath` for `$backend`: $error',
        );
      }
    }
  }

  /// Returns Windows `LoadLibraryExW` flags for preloading a backend module.
  ///
  /// llama.cpp currently opens dynamic backend modules with plain
  /// `LoadLibraryW`. For absolute native-asset bundle paths, an earlier
  /// `LOAD_WITH_ALTERED_SEARCH_PATH` load lets Windows resolve transitive DLL
  /// imports from the backend module directory before llama.cpp registers it.
  static int windowsBackendModuleLoadFlags(String libraryPath) {
    if (!path.isAbsolute(libraryPath)) {
      return 0;
    }
    return _loadWithAlteredSearchPath;
  }

  /// Returns absolute paths for backend-owned Windows dependency DLLs that
  /// can be preloaded before asking llama.cpp to dynamically load [backend].
  ///
  /// This is only a best-effort compatibility path. The backend module itself
  /// is also preloaded with `LOAD_WITH_ALTERED_SEARCH_PATH`, because Windows
  /// may still fail to resolve module-owned transitive imports from the bundle
  /// directory after individual dependency DLLs were loaded by absolute path.
  static List<String> windowsBackendDependencyPaths(
    String directoryPath,
    String backend, {
    Iterable<String>? fileNames,
  }) {
    if (backend != 'cuda') {
      return const <String>[];
    }

    final names =
        fileNames?.toList(growable: false) ??
        _listWindowsBackendDependencyFileNames(directoryPath);
    final selected = <String>[];
    for (final name in names) {
      final lower = name.toLowerCase();
      if (!lower.endsWith('.dll')) {
        continue;
      }
      if (lower.startsWith('cudart64_') ||
          lower.startsWith('cublas64_') ||
          lower.startsWith('cublaslt64_')) {
        selected.add(name);
      }
    }

    selected.sort((a, b) {
      final priorityCompare = _windowsCudaDependencyPriority(
        a,
      ).compareTo(_windowsCudaDependencyPriority(b));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    return selected
        .map((name) => path.join(directoryPath, name))
        .toList(growable: false);
  }

  static List<String> _listWindowsBackendDependencyFileNames(
    String directoryPath,
  ) {
    try {
      return Directory(directoryPath)
          .listSync()
          .whereType<File>()
          .map((file) => path.basename(file.path))
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  static int _windowsCudaDependencyPriority(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.startsWith('cudart64_')) {
      return 0;
    }
    if (lower.startsWith('cublas64_')) {
      return 1;
    }
    if (lower.startsWith('cublaslt64_')) {
      return 2;
    }
    return 100;
  }

  bool _tryRegisterBackendModuleViaAsset(
    String backend,
    BackendProbeFailures failures, {
    List<String>? candidates,
    DynamicLibrary Function(String)? open,
    int? Function(DynamicLibrary)? lookupScore,
    _GgmlBackendInitDart Function(DynamicLibrary)? lookupInit,
    bool Function(ggml_backend_reg_t)? register,
  }) {
    final assetCandidates =
        candidates ?? _libraryCandidates.backendAssetUris(backend);
    final recordAssetDiagnostics = backend == 'cpu' && Platform.isAndroid;

    final registered = probeLibraryCandidates(
      assetCandidates,
      failures: failures,
      open: open ?? DynamicLibrary.open,
      accept: (assetUri, library) {
        try {
          final score = (lookupScore ?? _lookupBackendAssetScore)(library);
          if (!isBackendCandidateScoreSupported(score)) {
            if (recordAssetDiagnostics && score != null) {
              _recordStartupDiagnostic(
                describeSkippedBackendAssetCandidate(assetUri, score),
              );
            }
            failures.add(assetUri, '`ggml_backend_score` returned $score');
            return null;
          }

          final _GgmlBackendInitDart init;
          try {
            init =
                lookupInit?.call(library) ??
                library.lookupFunction<
                  _GgmlBackendInitNative,
                  _GgmlBackendInitDart
                >('ggml_backend_init');
          } catch (_) {
            failures.add(assetUri, 'no `ggml_backend_init` export');
            return null;
          }
          final reg = init();
          if (reg == nullptr) {
            if (recordAssetDiagnostics) {
              _recordStartupDiagnostic(
                'Backend asset `$assetUri` returned null from '
                '`ggml_backend_init`.',
              );
            }
            failures.add(assetUri, '`ggml_backend_init` returned null');
            return null;
          }

          // Asset init path mirrors ggml_backend_load() by honoring
          // optional backend score gates before initialization, then
          // explicitly registering the backend because asset loading
          // bypasses the native dynamic-loader helper.
          if (!(register ?? _registerBackendRegBestEffort)(reg)) {
            if (recordAssetDiagnostics) {
              _recordStartupDiagnostic(
                'Backend asset `$assetUri` failed explicit backend '
                'registration.',
              );
            }
            failures.add(assetUri, '`ggml_backend_register` unavailable');
            return null;
          }
          _loadedBackendLibraries[backend] = library;
          _loadedBackendModules.add(backend);
          if (recordAssetDiagnostics) {
            _recordStartupDiagnostic(
              describeLoadedBackendAssetCandidate(assetUri, score),
            );
          }
          return true;
        } catch (error) {
          failures.add(assetUri, 'probe threw ${error.runtimeType}');
          return null;
        }
      },
    );
    return registered ?? false;
  }

  List<String> _ggmlFallbackCandidates() {
    final fileNameCandidates = _libraryCandidates.ggml();
    final candidates = <String>[..._libraryCandidates.ggmlAssetUris()];
    final filesystemCandidates = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      for (final fileName in fileNameCandidates) {
        filesystemCandidates.add(path.join(backendModuleDirectory, fileName));
      }
    }
    // Keep bare-name fallback last so module-dir resolution wins when present.
    filesystemCandidates.addAll(fileNameCandidates);
    candidates.addAll(filesystemCandidates);
    return candidates;
  }

  void _resolveGgmlFallbackFunctions({
    List<String>? candidates,
    DynamicLibrary Function(String)? open,
    Pointer<NativeType> Function(String)? assetSymbol,
  }) {
    if (_isWindows && candidates == null && open == null) {
      if (_ggmlFallbackLookupSearchKey == 'windows-code-assets' &&
          _ggmlBackendRegCountFallback != null) {
        return;
      }
      _ggmlFallbackLookupAttempted = true;
      _ggmlFallbackLookupSearchKey = 'windows-code-assets';
      // Filesystem overrides select backend modules, not a second ggml
      // registry beside the one imported by the hook's llama.dll.
      _bindGgmlFallbackFunctions(assetSymbol ?? _windowsGgmlSymbolAddress);
      _ggmlRuntimeProbeOutcome =
          'the Windows code assets package:llamadart/ggml and '
          'package:llamadart/ggml-base do not export it';
      if (_ggmlBackendRegCountFallback == null) {
        throw LlamaUnsupportedException(
          'Windows llama.cpp backend registration requires the ggml code '
          'asset emitted by the llamadart build hook, including the '
          'ggml_backend_reg_count export used by llama.dll. Use a complete, '
          'ABI-compatible native bundle through llamadart_native_path.',
        );
      }
      return;
    }
    candidates ??= _ggmlFallbackCandidates();

    final searchKey = candidates.map(path.normalize).join('|');
    if (_ggmlFallbackLookupAttempted &&
        _ggmlFallbackLookupSearchKey == searchKey) {
      return;
    }
    _ggmlFallbackLookupAttempted = true;
    _ggmlFallbackLookupSearchKey = searchKey;

    final failures = BackendProbeFailures();
    final opened = <String>{};
    probeLibraryCandidates(
      candidates,
      failures: failures,
      open: open ?? DynamicLibrary.open,
      accept: (candidate, library) {
        opened.add(probeCandidateIdentity(candidate));

        _bindGgmlFallbackFunctions(library.lookup);

        return _ggmlFallbacksFullyResolved ? true : null;
      },
    );
    _ggmlRuntimeProbeOutcome = opened.isEmpty
        ? 'no ggml runtime candidate opened (${failures.describe()})'
        : 'the opened ggml runtime candidates (${opened.join(', ')}) do not '
              'export it'
              '${failures.isEmpty ? '' : '; other candidates: ${failures.describe()}'}';
  }

  void _bindGgmlFallbackFunctions(Pointer<NativeType> Function(String) lookup) {
    _ggmlBackendLoadFallback ??= _tryBind(
      () => lookup('ggml_backend_load')
          .cast<NativeFunction<_GgmlBackendLoadNative>>()
          .asFunction<_GgmlBackendLoadDart>(),
    );
    _ggmlBackendLoadAllFallback ??= _tryBind(
      () => lookup('ggml_backend_load_all')
          .cast<NativeFunction<_GgmlBackendLoadAllNative>>()
          .asFunction<_GgmlBackendLoadAllDart>(),
    );
    _ggmlBackendLoadAllFromPathFallback ??= _tryBind(
      () => lookup('ggml_backend_load_all_from_path')
          .cast<NativeFunction<_GgmlBackendLoadAllFromPathNative>>()
          .asFunction<_GgmlBackendLoadAllFromPathDart>(),
    );
    _ggmlBackendRegisterFallback ??= _tryBind(
      () => lookup('ggml_backend_register')
          .cast<NativeFunction<_GgmlBackendRegisterNative>>()
          .asFunction<_GgmlBackendRegisterDart>(),
    );
    _ggmlBackendRegCountFallback ??= _tryBind(
      () => lookup('ggml_backend_reg_count')
          .cast<NativeFunction<_GgmlBackendRegCountNative>>()
          .asFunction<_GgmlBackendRegCountDart>(),
    );
    _ggmlBackendRegGetFallback ??= _tryBind(
      () => lookup('ggml_backend_reg_get')
          .cast<NativeFunction<_GgmlBackendRegGetNative>>()
          .asFunction<_GgmlBackendRegGetDart>(),
    );
    _ggmlBackendRegNameFallback ??= _tryBind(
      () => lookup('ggml_backend_reg_name')
          .cast<NativeFunction<_GgmlBackendRegNameNative>>()
          .asFunction<_GgmlBackendRegNameDart>(),
    );
    _ggmlBackendRegByNameFallback ??= _tryBind(
      () => lookup('ggml_backend_reg_by_name')
          .cast<NativeFunction<_GgmlBackendRegByNameNative>>()
          .asFunction<_GgmlBackendRegByNameDart>(),
    );
    _ggmlBackendRegGetProcAddressFallback ??= _tryBind(
      () => lookup('ggml_backend_reg_get_proc_address')
          .cast<NativeFunction<_GgmlBackendRegGetProcAddressNative>>()
          .asFunction<_GgmlBackendRegGetProcAddressDart>(),
    );
    _ggmlBackendRegDevCountFallback ??= _tryBind(
      () => lookup('ggml_backend_reg_dev_count')
          .cast<NativeFunction<_GgmlBackendRegDevCountNative>>()
          .asFunction<_GgmlBackendRegDevCountDart>(),
    );
    _ggmlBackendRegDevGetFallback ??= _tryBind(
      () => lookup('ggml_backend_reg_dev_get')
          .cast<NativeFunction<_GgmlBackendRegDevGetNative>>()
          .asFunction<_GgmlBackendRegDevGetDart>(),
    );
    _ggmlBackendDevCountFallback ??= _tryBind(
      () => lookup('ggml_backend_dev_count')
          .cast<NativeFunction<_GgmlBackendDevCountNative>>()
          .asFunction<_GgmlBackendDevCountDart>(),
    );
    _ggmlBackendDevGetFallback ??= _tryBind(
      () => lookup('ggml_backend_dev_get')
          .cast<NativeFunction<_GgmlBackendDevGetNative>>()
          .asFunction<_GgmlBackendDevGetDart>(),
    );
    _ggmlBackendDevNameFallback ??= _tryBind(
      () => lookup('ggml_backend_dev_name')
          .cast<NativeFunction<_GgmlBackendDevNameNative>>()
          .asFunction<_GgmlBackendDevNameDart>(),
    );
    _ggmlBackendDevBackendRegFallback ??= _tryBind(
      () => lookup('ggml_backend_dev_backend_reg')
          .cast<NativeFunction<_GgmlBackendDevBackendRegNative>>()
          .asFunction<_GgmlBackendDevBackendRegDart>(),
    );
    _ggmlBackendDevByTypeFallback ??= _tryBind(
      () => lookup('ggml_backend_dev_by_type')
          .cast<NativeFunction<_GgmlBackendDevByTypeNative>>()
          .asFunction<_GgmlBackendDevByTypeDart>(),
    );
    _ggmlBackendDevBufferTypeFallback ??= _tryBind(
      () => lookup('ggml_backend_dev_buffer_type')
          .cast<NativeFunction<_GgmlBackendDevBufferTypeNative>>()
          .asFunction<_GgmlBackendDevBufferTypeDart>(),
    );
    _ggmlBackendDevTypeFallback ??= _tryBind(
      () => lookup('ggml_backend_dev_type')
          .cast<NativeFunction<_GgmlBackendDevTypeNative>>()
          .asFunction<_GgmlBackendDevTypeDart>(),
    );
    _ggmlBackendDevGetPropsFallback ??= _tryBind(
      () => lookup('ggml_backend_dev_get_props')
          .cast<NativeFunction<_GgmlBackendDevGetPropsNative>>()
          .asFunction<_GgmlBackendDevGetPropsDart>(),
    );
    _ggmlBackendDevMemoryFallback ??= _tryBind(
      () => lookup('ggml_backend_dev_memory')
          .cast<NativeFunction<_GgmlBackendDevMemoryNative>>()
          .asFunction<_GgmlBackendDevMemoryDart>(),
    );
  }

  static Pointer<NativeType> _windowsGgmlSymbolAddress(String symbol) =>
      switch (symbol) {
        'ggml_backend_load' =>
          Native.addressOf<NativeFunction<_GgmlBackendLoadNative>>(
            _windowsGgmlBackendLoad,
          ),
        'ggml_backend_load_all' =>
          Native.addressOf<NativeFunction<_GgmlBackendLoadAllNative>>(
            _windowsGgmlBackendLoadAll,
          ),
        'ggml_backend_load_all_from_path' =>
          Native.addressOf<NativeFunction<_GgmlBackendLoadAllFromPathNative>>(
            _windowsGgmlBackendLoadAllFromPath,
          ),
        'ggml_backend_register' =>
          Native.addressOf<NativeFunction<_GgmlBackendRegisterNative>>(
            _windowsGgmlBackendRegister,
          ),
        'ggml_backend_reg_count' =>
          Native.addressOf<NativeFunction<_GgmlBackendRegCountNative>>(
            _windowsGgmlBackendRegCount,
          ),
        'ggml_backend_reg_get' =>
          Native.addressOf<NativeFunction<_GgmlBackendRegGetNative>>(
            _windowsGgmlBackendRegGet,
          ),
        'ggml_backend_reg_name' =>
          Native.addressOf<NativeFunction<_GgmlBackendRegNameNative>>(
            _windowsGgmlBackendRegName,
          ),
        'ggml_backend_reg_by_name' =>
          Native.addressOf<NativeFunction<_GgmlBackendRegByNameNative>>(
            _windowsGgmlBackendRegByName,
          ),
        'ggml_backend_reg_get_proc_address' =>
          Native.addressOf<NativeFunction<_GgmlBackendRegGetProcAddressNative>>(
            _windowsGgmlBackendRegGetProcAddress,
          ),
        'ggml_backend_reg_dev_count' =>
          Native.addressOf<NativeFunction<_GgmlBackendRegDevCountNative>>(
            _windowsGgmlBackendRegDevCount,
          ),
        'ggml_backend_reg_dev_get' =>
          Native.addressOf<NativeFunction<_GgmlBackendRegDevGetNative>>(
            _windowsGgmlBackendRegDevGet,
          ),
        'ggml_backend_dev_count' =>
          Native.addressOf<NativeFunction<_GgmlBackendDevCountNative>>(
            _windowsGgmlBackendDevCount,
          ),
        'ggml_backend_dev_get' =>
          Native.addressOf<NativeFunction<_GgmlBackendDevGetNative>>(
            _windowsGgmlBackendDevGet,
          ),
        'ggml_backend_dev_name' =>
          Native.addressOf<NativeFunction<_GgmlBackendDevNameNative>>(
            _windowsGgmlBackendDevName,
          ),
        'ggml_backend_dev_backend_reg' =>
          Native.addressOf<NativeFunction<_GgmlBackendDevBackendRegNative>>(
            _windowsGgmlBackendDevBackendReg,
          ),
        'ggml_backend_dev_by_type' =>
          Native.addressOf<NativeFunction<_GgmlBackendDevByTypeNative>>(
            _windowsGgmlBackendDevByType,
          ),
        'ggml_backend_dev_buffer_type' =>
          Native.addressOf<NativeFunction<_GgmlBackendDevBufferTypeNative>>(
            _windowsGgmlBackendDevBufferType,
          ),
        'ggml_backend_dev_type' =>
          Native.addressOf<NativeFunction<_GgmlBackendDevTypeNative>>(
            _windowsGgmlBackendDevType,
          ),
        'ggml_backend_dev_get_props' =>
          Native.addressOf<NativeFunction<_GgmlBackendDevGetPropsNative>>(
            _windowsGgmlBackendDevGetProps,
          ),
        'ggml_backend_dev_memory' =>
          Native.addressOf<NativeFunction<_GgmlBackendDevMemoryNative>>(
            _windowsGgmlBackendDevMemory,
          ),
        _ => throw ArgumentError.value(symbol, 'symbol', 'not bound'),
      };

  /// Runs one symbol binding, returning `null` if it fails for any reason so
  /// the caller can keep searching the remaining candidates.
  ///
  /// Every exception is swallowed, not just a missing symbol: a candidate that
  /// exports the name with an incompatible signature is treated the same as one
  /// that does not export it at all. That is deliberate, and matches the
  /// per-symbol `try`/`catch` blocks this replaced.
  static D? _tryBind<D extends Function>(D Function() bind) {
    try {
      return bind();
    } catch (_) {
      return null;
    }
  }

  void _resolveLogLevelFallbackFunction({
    List<String>? candidates,
    DynamicLibrary Function(String)? open,
  }) {
    final directories = _llamadartFallbackLookupDirectories();
    final searchKey = directories.map(path.normalize).join('|');

    if (_logLevelFallbackLookupAttempted &&
        _llamaDartSetLogLevelFallback != null) {
      return;
    }

    if (_logLevelFallbackLookupAttempted &&
        _llamaDartSetLogLevelFallback == null &&
        _logLevelFallbackLookupSearchKey == searchKey) {
      return;
    }

    _logLevelFallbackLookupAttempted = true;
    _logLevelFallbackLookupSearchKey = searchKey;

    final failures = BackendProbeFailures();
    final setLogLevel = probeLibraryCandidates(
      candidates ?? _libraryCandidates.wrapperPaths(directories),
      failures: failures,
      open: open ?? _openWrapperLibrary,
      accept: (candidate, library) {
        try {
          return library.lookupFunction<
            _LlamaDartSetLogLevelNative,
            _LlamaDartSetLogLevelDart
          >('llama_dart_set_log_level');
        } catch (_) {
          failures.add(candidate, 'no `llama_dart_set_log_level` export');
          return null;
        }
      },
    );
    if (setLogLevel != null) {
      _llamaDartSetLogLevelFallback = setLogLevel;
      return;
    }
    _logLevelProbeOutcome = failures.describe();
  }

  /// Reports generation controls for a loaded model and this runtime bundle.
  BackendGenerationCapabilities generationCapabilities(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) {
      return const BackendGenerationCapabilities(
        presencePenalty: false,
        minP: false,
        thinkingBudget: false,
      );
    }
    _ensureModelUsable(model);
    return BackendGenerationCapabilities(
      penalty: true,
      presencePenalty: true,
      minP: true,
      thinkingBudget: _supportsThinkingBudget(),
      streamBatching: true,
      speculativeDecodingStrategies:
          _requiresQwen35VulkanRestriction(modelHandle)
          ? const <SpeculativeDecodingStrategy>{}
          : const <SpeculativeDecodingStrategy>{
              SpeculativeDecodingStrategy.backendDefault,
              SpeculativeDecodingStrategy.mtp,
              SpeculativeDecodingStrategy.ngramSimple,
              SpeculativeDecodingStrategy.draftSimple,
              SpeculativeDecodingStrategy.draftEagle3,
              SpeculativeDecodingStrategy.draftDflash,
              SpeculativeDecodingStrategy.ngramMapK,
              SpeculativeDecodingStrategy.ngramMapK4v,
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.ngramCache,
              SpeculativeDecodingStrategy.draftDspark,
            },
    );
  }

  _ReasoningBudgetApi _resolveReasoningBudgetApi({
    List<String>? candidates,
    DynamicLibrary Function(String)? open,
  }) {
    final cached = _reasoningBudgetApi;
    if (cached != null) {
      return cached;
    }

    if (_reasoningBudgetApiLookupAttempted) {
      throw LlamaUnsupportedException(_reasoningBudgetUnavailableMessage());
    }
    _reasoningBudgetApiLookupAttempted = true;

    for (final candidate
        in candidates ?? _llamadartWrapperLibraryCandidates()) {
      var stage = 'open';
      try {
        final library = (open ?? _openWrapperLibrary)(candidate);
        stage = 'lookup';
        final api = _ReasoningBudgetApi.load(library);
        _reasoningBudgetApi = api;
        _reasoningBudgetLoadFailures.clear();
        return api;
      } catch (error) {
        final diagnostic = stage == 'lookup'
            ? 'lookup: required export unavailable'
            : _reasoningBudgetOpenFailure(error);
        _reasoningBudgetLoadFailures.update(
          diagnostic,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    throw LlamaUnsupportedException(_reasoningBudgetUnavailableMessage());
  }

  String _reasoningBudgetUnavailableMessage() {
    return 'llama.cpp thinking-budget control is unavailable in this native '
        'runtime bundle (could not resolve '
        'llama_dart_sampler_init_reasoning_budget). '
        'Use the package-pinned reasoning-budget wrapper and ensure its sibling '
        'DLLs and Microsoft runtime dependencies can load. '
        'loaderDiagnostics=['
        '${_reasoningBudgetLoadFailures.entries.map((entry) => '${entry.key} '
            '(${entry.value} attempts)').join('; ')}]';
  }

  // Emit only a finite vocabulary: OS errors can contain credentials, signed
  // URLs and arbitrary paths. Never retain the candidate or raw exception.
  static String _reasoningBudgetOpenFailure(Object error) {
    final message = error.toString();
    final code = RegExp(
      r'\(error code: (5|126|127|193|1114)\)',
    ).firstMatch(message)?.group(1);
    final reason = switch (code) {
      '5' => 'access denied',
      '126' => 'library or dependency not found',
      '127' => 'dependency procedure not found',
      '193' => 'invalid binary or architecture mismatch',
      '1114' => 'DLL initialization failed',
      _ => 'library or dependency could not be loaded',
    };
    return 'open: $reason${code == null ? '' : ' (Windows error $code)'}';
  }

  _SpeculativeApi _resolveSpeculativeApi({
    List<String>? candidates,
    DynamicLibrary Function(String)? open,
  }) {
    final cached = _speculativeApi;
    if (cached != null) {
      return cached;
    }

    if (_speculativeApiLookupAttempted) {
      throw LlamaUnsupportedException(_speculativeUnavailableMessage());
    }
    _speculativeApiLookupAttempted = true;

    if (!_isWindows) {
      try {
        final direct = _SpeculativeApi.direct();
        _speculativeApi = direct;
        return direct;
      } catch (_) {}
    }

    if (_isWindows) {
      try {
        final asset = _SpeculativeApi.windowsAsset();
        _speculativeApi = asset;
        return asset;
      } catch (_) {}
    }

    for (final candidate
        in candidates ?? _llamadartWrapperLibraryCandidates()) {
      try {
        final library = (open ?? _openWrapperLibrary)(candidate);
        final api = _SpeculativeApi.tryLoad(library);
        if (api != null) {
          _speculativeApi = api;
          return api;
        }
      } catch (_) {
        continue;
      }
    }

    throw LlamaUnsupportedException(_speculativeUnavailableMessage());
  }

  _TtsApi _resolveTtsApi() {
    final cached = _ttsApi;
    if (cached != null) {
      return cached;
    }
    if (_ttsApiLookupAttempted) {
      throw LlamaUnsupportedException(_ttsUnavailableMessage());
    }
    _ttsApiLookupAttempted = true;

    for (final candidate in _llamadartWrapperLibraryCandidates()) {
      try {
        final library = _openWrapperLibrary(candidate);
        final api = _TtsApi.tryLoad(library);
        if (api != null) {
          _ttsApi = api;
          return api;
        }
      } catch (_) {
        continue;
      }
    }
    throw LlamaUnsupportedException(_ttsUnavailableMessage());
  }

  DynamicLibrary _openWrapperLibrary(String candidate) {
    return openWrapperLibraryWithDependencies(
      candidate,
      isWindows: Platform.isWindows,
      preload: (candidate) =>
          _preloadWindowsBackendModule(candidate, 'wrapper'),
      open: DynamicLibrary.open,
      release: (handle, candidate) =>
          _freeWindowsBackendModule(handle, candidate, 'wrapper'),
    );
  }

  /// Opens a wrapper while its sibling dependencies remain loaded on Windows.
  ///
  /// The temporary handle uses the same altered search path as backend modules.
  /// Keep it alive until [open] acquires its own reference, including on failure.
  /// Injectable operations allow resource-lifetime regression tests on every OS.
  /// A candidate that takes the altered search path is preloaded only when
  /// [exists] returns true for it; [exists] defaults to [File.existsSync].
  static DynamicLibrary openWrapperLibraryWithDependencies(
    String candidate, {
    required bool isWindows,
    required Pointer<Void> Function(String) preload,
    required DynamicLibrary Function(String) open,
    required void Function(Pointer<Void>, String) release,
    bool Function(String)? exists,
  }) {
    final handle =
        isWindows &&
            windowsBackendModuleLoadFlags(candidate) != 0 &&
            (exists ?? _fileExists)(candidate)
        ? preload(candidate)
        : nullptr;
    try {
      return open(candidate);
    } finally {
      if (handle != nullptr) {
        release(handle, candidate);
      }
    }
  }

  static bool _fileExists(String filePath) => File(filePath).existsSync();

  LlamaCppLibraryCandidates get _libraryCandidates => LlamaCppLibraryCandidates(
    os: Platform.operatingSystem,
    abi: _abi,
    moduleDirectory: _backendModuleDirectory,
    listFiles: _listFileNames,
    fileExists: _fileExists,
  );

  static List<String> _listFileNames(String directoryPath) => [
    for (final entity in Directory(directoryPath).listSync())
      if (entity is File) path.basename(entity.path),
  ];

  /// Tries to load the ggml [backend] module from [moduleDirectory], as model
  /// loading does, for VM regression tests.
  bool debugTryLoadBackendModuleForTesting(
    String backend, {
    required String moduleDirectory,
  }) {
    _backendModuleDirectory = moduleDirectory;
    return _tryLoadBackendModule(backend);
  }

  /// Returns the Linux native bundle directory names for the running ABI for
  /// VM regression tests.
  List<String> debugLinuxBundleNamesForTesting() =>
      _linuxBundleNamesForCurrentAbi();

  /// Returns wrapper-library lookup candidates for VM regression tests.
  List<String> debugLlamadartWrapperLibraryCandidatesForTesting() {
    return _llamadartWrapperLibraryCandidates();
  }

  T _ggmlRegistryFallbackOr<T>(
    T fallback,
    T Function() primaryCall,
    T? Function() fallbackCall,
  ) {
    if (_isWindows) {
      // Windows split bundles can expose ggml registry state through ggml.dll
      // while the generated default asset points at llama.dll. Prefer the
      // explicit ggml runtime lookup when it is available so count/get/name
      // calls all read the same registry.
      _resolveGgmlFallbackFunctions();
      final fallbackValue = fallbackCall();
      if (fallbackValue != null) {
        return fallbackValue;
      }
    }

    try {
      return primaryCall();
    } on ArgumentError {
      _resolveGgmlFallbackFunctions();
      final fallbackValue = fallbackCall();
      if (fallbackValue != null) {
        return fallbackValue;
      }
      _backendRegistrySymbolUnavailable = true;
      return fallback;
    }
  }

  int _ggmlBackendRegCount() {
    return _ggmlRegistryFallbackOr<int>(
      0,
      ggml_backend_reg_count,
      () => _ggmlBackendRegCountFallback?.call(),
    );
  }

  ggml_backend_reg_t _ggmlBackendRegGet(int index) {
    return _ggmlRegistryFallbackOr<ggml_backend_reg_t>(
      nullptr,
      () => ggml_backend_reg_get(index),
      () => _ggmlBackendRegGetFallback?.call(index),
    );
  }

  Pointer<Char> _ggmlBackendRegName(ggml_backend_reg_t reg) {
    return _ggmlRegistryFallbackOr<Pointer<Char>>(
      nullptr,
      () => ggml_backend_reg_name(reg),
      () => _ggmlBackendRegNameFallback?.call(reg),
    );
  }

  int _ggmlBackendRegDevCount(ggml_backend_reg_t reg) {
    return _ggmlRegistryFallbackOr<int>(
      0,
      () => ggml_backend_reg_dev_count(reg),
      () => _ggmlBackendRegDevCountFallback?.call(reg),
    );
  }

  ggml_backend_dev_t _ggmlBackendDevGet(int index) {
    return _ggmlRegistryFallbackOr<ggml_backend_dev_t>(
      nullptr,
      () => ggml_backend_dev_get(index),
      () => _ggmlBackendDevGetFallback?.call(index),
    );
  }

  /// Routes `ggml_backend_dev_memory` through the registry fallback.
  /// Same shape as [_ggmlBackendDevGetProps]; returns `false` when the
  /// symbol is unavailable.
  bool _ggmlBackendDevMemory(
    ggml_backend_dev_t dev,
    Pointer<Size> free,
    Pointer<Size> total,
  ) {
    final barrier = _calls.failures.barrier;
    if (barrier != null) return barrier.ggmlBackendDevMemory(dev, free, total);
    return _ggmlRegistryFallbackOr<bool>(
      false,
      () {
        ggml_backend_dev_memory(dev, free, total);
        return true;
      },
      () {
        final fn = _ggmlBackendDevMemoryFallback;
        if (fn == null) return null;
        fn(dev, free, total);
        return true;
      },
    );
  }

  static bool _looksLikeGguf(File modelFile) {
    try {
      final header = modelFile.openSync(mode: FileMode.read);
      try {
        final magic = header.readSync(4);
        if (magic.length < 4) {
          return false;
        }
        return magic[0] == 0x47 &&
            magic[1] == 0x47 &&
            magic[2] == 0x55 &&
            magic[3] == 0x46;
      } finally {
        header.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  String _backendDiagnostics() {
    final regs = <String>[];
    final regCount = _ggmlBackendRegCount();
    for (var i = 0; i < regCount; i++) {
      final reg = _ggmlBackendRegGet(i);
      if (reg == nullptr) {
        continue;
      }
      final regNamePtr = _ggmlBackendRegName(reg);
      if (regNamePtr == nullptr) {
        continue;
      }
      regs.add(regNamePtr.cast<Utf8>().toDartString());
    }

    final devices = getBackendInfo();
    return '{moduleDir=${_backendModuleDirectory ?? "null"}, '
        'loadedModules=${_loadedBackendModules.toList(growable: false)}, '
        'registeredBackends=$regs, devices=$devices, '
        'registryApisUnavailable=$_backendRegistrySymbolUnavailable}';
  }

  Pointer<ggml_backend_dev_t>? _createPreferredDeviceList(GpuBackend backend) {
    final devices = _resolvePreferredDevices(backend);
    if (devices == null || devices.isEmpty) {
      return null;
    }

    final ptr = _modelLoadAllocator<ggml_backend_dev_t>(devices.length + 1);
    for (var i = 0; i < devices.length; i++) {
      ptr[i] = devices[i];
    }
    ptr[devices.length] = nullptr;
    return ptr;
  }

  List<ggml_backend_dev_t>? _resolvePreferredDevices(GpuBackend backend) {
    if (backend == GpuBackend.cpu) {
      final cpuDev = _ggmlBackendDevByType(
        ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU,
      );
      if (cpuDev == nullptr) {
        return null;
      }
      return [cpuDev];
    }
    final registryName = ggmlGpuRegistryName(backend);
    return registryName == null
        ? null
        : _backendDevicesOverride?.call(backend) ??
              _devicesForBackendRegName(registryName);
  }

  /// Returns the name of the ggml backend registry that lists the devices of
  /// an explicit GPU [backend], or `null` for [GpuBackend.auto] and
  /// [GpuBackend.cpu].
  static String? ggmlGpuRegistryName(GpuBackend backend) => switch (backend) {
    GpuBackend.vulkan => 'Vulkan',
    GpuBackend.metal => 'MTL',
    GpuBackend.cuda => 'CUDA',
    GpuBackend.blas => 'BLAS',
    GpuBackend.opencl => 'OpenCL',
    GpuBackend.hip => 'ROCm',
    GpuBackend.auto || GpuBackend.cpu => null,
  };

  List<ggml_backend_dev_t>? _devicesForBackendRegName(String regName) {
    final regNamePtr = regName.toNativeUtf8();
    try {
      final reg = _ggmlBackendRegByName(regNamePtr.cast());
      if (reg == nullptr) {
        return null;
      }

      final count = _ggmlBackendRegDevCount(reg);
      if (count <= 0) {
        return null;
      }

      final devices = <ggml_backend_dev_t>[];
      for (var i = 0; i < count; i++) {
        final dev = _ggmlBackendRegDevGet(reg, i);
        if (dev != nullptr) {
          devices.add(dev);
        }
      }

      if (devices.isEmpty) {
        return null;
      }

      return devices;
    } finally {
      malloc.free(regNamePtr);
    }
  }

  /// Frees the model associated with [modelHandle].
  ///
  /// This also frees the model's decision heads, contexts and LoRA adapters.
  void freeModel(int modelHandle) {
    _freeDecisionHeadsWhere((head) => head.modelHandle == modelHandle);
    final model = _models.remove(modelHandle);
    _modelToMtmdUseGpu.remove(modelHandle);
    if (model != null) {
      final contextsToRemove = _contextToModel.entries
          .where((e) => e.value == modelHandle)
          .map((e) => e.key)
          .toList();
      for (final ctxHandle in contextsToRemove) {
        _freeContext(ctxHandle);
      }
      final adapters = _loraAdapters.remove(modelHandle);
      adapters?.values.forEach((a) => a.dispose());

      // Free associated multimodal context
      final mmHandle = _modelToMtmd.remove(modelHandle);
      if (mmHandle != null) {
        final mmCtx = _mtmdContexts.remove(mmHandle);
        if (mmCtx != null) _mtmdFree(mmCtx);
      }

      model.dispose();
    }

    _modelResolvedBackends.remove(modelHandle);
    _modelArchitectures.remove(modelHandle);
    _modelBackendNames.remove(modelHandle);
    _modelResolvedGpuLayers.remove(modelHandle);
    _modelsOnNoGpu.remove(modelHandle);
    _modelLoadParams.remove(modelHandle);
    _modelPlacements.remove(modelHandle);
    final draftModelKeys = _modelToSpeculativeDraftModelKeys.remove(
      modelHandle,
    );
    if (draftModelKeys != null) {
      for (final key in draftModelKeys) {
        _speculativeDraftModels.remove(key)?.dispose();
      }
    }
    if (_modelBackendNames.isEmpty) {
      _activeBackendName = _backendDisplayName('cpu');
      _activeResolvedGpuLayers = 0;
    } else {
      _activateModelReport(_modelBackendNames.keys.last);
    }
  }

  void _validateRollbackReservation(
    ModelParams params, {
    required bool isRecurrent,
    required bool isHybrid,
  }) {
    if (params.speculativeRollbackTokenMax == 0 ||
        (!isRecurrent && !isHybrid)) {
      return;
    }
    throw LlamaUnsupportedException(
      'Native llama.cpp recurrent/hybrid models cannot safely reserve '
      'speculativeRollbackTokenMax=${params.speculativeRollbackTokenMax}: '
      'the native API does not expose a validated rollback graph-node budget. '
      'Use speculativeRollbackTokenMax=0 for ordinary generation. '
      'Speculative decoding that needs recurrent rollback is unsupported '
      'until the native runtime can validate the required graph capacity.',
    );
  }

  /// Creates an inference context for the specified [modelHandle].
  ///
  /// Returns a handle to the created context.
  /// Throws an [Exception] if the model handle is invalid or context creation fails.
  int createContext(
    int modelHandle,
    ModelParams params, {
    bool reranking = false,
  }) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }
    _ensureModelUsable(model);
    params = resolveComputeDeviceParams(
      params,
      isAndroid: _isAndroid,
      isIosSimulator: _isIosSimulator,
      isMacosX64: _isMacosX64,
      platform: Platform.operatingSystem,
    );
    final qwen35OnSmallTileVulkan = _isQwen35OnSmallTileAndroidVulkan(
      modelHandle,
    );
    final qwen35VulkanRestricted =
        qwen35OnSmallTileVulkan && !_ggmlHasSmallMatmulTileFix;
    if (qwen35VulkanRestricted &&
        params.microBatchSize > androidVulkanPromptMicroBatchSize) {
      throw LlamaUnsupportedException(
        'microBatchSize=${params.microBatchSize} is unavailable. $_qwen35VulkanRestriction',
      );
    }
    if (params.speculativeRollbackTokenMax > 0) {
      _validateRollbackReservation(
        params,
        isRecurrent: llama_model_is_recurrent(model.pointer),
        isHybrid: llama_model_is_hybrid(model.pointer),
      );
    }

    final ctxParams = llama_context_default_params();
    int nCtx = params.contextSize;
    if (nCtx <= 0) {
      nCtx = llama_model_n_ctx_train(model.pointer);
    }
    final hasEncoder = llama_model_has_encoder(model.pointer);
    final hasDecoder = llama_model_has_decoder(model.pointer);
    final resolvedBatchSizes = resolveContextBatchSizes(
      params,
      nCtx,
      useFullContextDefaults: hasEncoder && !hasDecoder,
    );
    final maxSeqLimit = llama_max_parallel_sequences();
    final resolvedMaxParallelSequences = math.max(
      1,
      math.min(params.maxParallelSequences, maxSeqLimit),
    );

    ctxParams.n_ctx = nCtx;
    ctxParams.n_batch = resolvedBatchSizes.batchSize;
    ctxParams.n_ubatch = resolvedBatchSizes.microBatchSize;
    ctxParams.n_seq_max = resolvedMaxParallelSequences;
    ctxParams.n_rs_seq = params.speculativeRollbackTokenMax;
    applyContextThreads(ctxParams, params, availableCores: _availableCores);
    if (resolvedMaxParallelSequences > 1) {
      // Keep per-sequence context at full n_ctx when multiple sequence slots
      // are enabled so regular generation behavior is unchanged.
      ctxParams.kv_unified = true;
    }

    final resolvedModelGpuLayers = _modelsOnNoGpu.contains(modelHandle)
        ? 0
        : _modelResolvedGpuLayers[modelHandle];
    if (qwen35OnSmallTileVulkan) {
      _applyConservativeAndroidVulkanContextConfig(ctxParams, modelHandle);
    } else if (shouldDisableContextGpuOffload(
      params,
      resolvedGpuLayers: resolvedModelGpuLayers,
    )) {
      ctxParams.offload_kqv = false;
      ctxParams.op_offload = false;
      ctxParams.flash_attn_typeAsInt =
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value;
    } else if (shouldUseConservativeAndroidVulkanContextConfig(
      params,
      resolvedGpuLayers: resolvedModelGpuLayers,
      isAndroid: _isAndroid,
    )) {
      _applyConservativeAndroidVulkanContextConfig(ctxParams, modelHandle);
    }

    params.validate();
    final resolvedFlashAttn = applyContextParams(ctxParams, params);
    if (resolvedFlashAttn != params.flashAttention) {
      LlamaLogger.instance.debug(
        'llama_cpp_service: promoting flash_attn=enabled for non-F16 KV '
        '(k=${params.cacheTypeK}, v=${params.cacheTypeV})',
      );
    }

    if (reranking) {
      ctxParams.pooling_type = llama_pooling_type.LLAMA_POOLING_TYPE_RANK;
      ctxParams.embeddings = true;
    }
    final ctxPtr = _createOwnedContext(model.pointer, ctxParams);
    IsolateShutdownReleases.current.hold(
      ShutdownStage.context,
      _calls.contextFreeAddress,
      ctxPtr,
    );
    if (ctxPtr == nullptr) {
      if (params.moeCacheBytes > 0) {
        throw LlamaContextException(
          'Failed to create the context with a ${params.moeCacheBytes}-byte '
          'MoE expert cache (ModelParams.moeCacheBytes): llama.cpp could not '
          'allocate it on the GPU, or it cannot hold the experts of one '
          'token. Change moeCacheBytes, or set it to 0 to disable the cache.',
        );
      }
      throw Exception("Failed to create context");
    }

    final handle = _getHandle();
    _contexts[handle] = _LlamaContextWrapper(
      ctxPtr,
      model,
      _calls,
      qwen35VulkanRestricted: qwen35VulkanRestricted,
      promptMicroBatchLimit:
          qwen35VulkanRestricted ||
              qwen35OnSmallTileVulkan && params.microBatchSize <= 0
          ? androidVulkanPromptMicroBatchSize
          : resolvePromptMicroBatchLimit(
              params,
              resolvedGpuLayers: resolvedModelGpuLayers,
              isAndroid: _isAndroid,
              hasSmallMatmulTileDefect: _androidVulkanHasSmallMatmulTileDefect,
            ),
    );
    _contextToModel[handle] = modelHandle;
    _activeLoras[handle] = {};
    _contextParams[handle] = ctxParams;
    final sampler = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );
    _holdSamplerChain(sampler);
    _samplers[handle] = sampler;
    final batch = TokenBatch.allocate(
      resolvedBatchSizes.batchSize,
      1,
      allocator: _contextBatchAllocator,
    );
    IsolateShutdownReleases.current.hold(
      ShutdownStage.session,
      TokenBatch.freeAddress,
      batch.block,
    );
    _batches[handle] = batch;

    return handle;
  }

  bool _androidVulkanHasSmallMatmulTileDefect() {
    final registeredDeviceCount = _registeredVulkanDeviceCount();
    // Without a ggml-vulkan device there is nothing to learn, and the facts
    // are not to be read where Vulkan is ruled out.
    if (registeredDeviceCount == 0) return true;
    final probe = _vulkanDeviceProbe;
    final defect = vulkanSmallMatmulTileDefect(
      probe,
      registeredDeviceCount: registeredDeviceCount,
    );
    LlamaLogger.instance.debug(
      'llama_cpp_service: Android Vulkan text prompt decode is '
      '${defect ? 'capped at $androidVulkanPromptMicroBatchSize tokens per '
                'call' : 'not capped'} '
      '(${probe.devices?.join(', ') ?? probe.unavailableReason})',
    );
    return defect;
  }

  void _applyConservativeAndroidVulkanContextConfig(
    llama_context_params ctxParams,
    int modelHandle,
  ) {
    if (!_androidVulkanAllowKqvOffload) {
      final modelArchitecture = _modelArchitecture(modelHandle);
      if (!shouldKeepAndroidVulkanKqvOffloadEnabled(modelArchitecture)) {
        ctxParams.offload_kqv = false;
      }
    }
    if (!_androidVulkanAllowOpOffload) {
      ctxParams.op_offload = false;
    }
    if (!_androidVulkanAllowFlashAttn) {
      ctxParams.flash_attn_typeAsInt =
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value;
    }
  }

  /// Frees the context associated with [contextHandle].
  void freeContext(int contextHandle) {
    _freeContext(contextHandle);
  }

  void _freeContext(int handle) {
    _contextToModel.remove(handle);
    _activeLoras.remove(handle);
    _contextParams.remove(handle);
    final sampler = _samplers.remove(handle);
    if (sampler != null && sampler != nullptr) _freeSamplerChain(sampler);
    final batch = _batches.remove(handle);
    if (batch != null) {
      IsolateShutdownReleases.current.release(batch.block);
      batch.free();
    }
    _contexts.remove(handle)?.dispose();
  }

  static const String _encoderDecoderEmbeddingsUnsupported =
      'Embeddings are not supported for encoder-decoder models such as T5; '
      'use an encoder-only or decoder-only embedding model.';

  // Without a projector the prompt would be evaluated as text and the media
  // silently dropped; upstream llama-server rejects such requests too.
  void _checkLlamaCppMediaParts(
    List<LlamaContentPart> parts, {
    required bool projectorLoaded,
  }) {
    if (!projectorLoaded) {
      final hasImage = parts.any((part) => part is LlamaImageContent);
      final hasAudio = parts.any((part) => part is LlamaAudioContent);
      final kind = hasImage && hasAudio
          ? 'Image and audio'
          : hasImage
          ? 'Image'
          : 'Audio';
      throw LlamaUnsupportedException(
        '$kind input needs a multimodal projector on llama.cpp, and none is '
        'loaded. Load the model with LlamaModel(source, projector: ...) '
        'before sending media.',
      );
    }
    for (final part in parts) {
      if (part is LlamaImageContent &&
          part.path == null &&
          part.bytes == null &&
          part.url != null) {
        throw LlamaUnsupportedException(
          'llama.cpp does not load remote image URLs '
          '(LlamaImageContent.url). Pass a local image file path or encoded '
          'image bytes.',
        );
      }
    }
  }

  _LlamaCppThinkingBudgetConfig? _resolveLlamaCppThinkingBudgetConfig(
    GenerationParams params, {
    required bool hasMediaParts,
  }) {
    final budget = params.thinkingBudget;
    if (budget == null) {
      return null;
    }
    if (budget.maxTokens < 0) {
      throw RangeError.value(
        budget.maxTokens,
        'thinkingBudget.maxTokens',
        'must be non-negative for llama.cpp thinking-budget control',
      );
    }
    if (budget.maxTokens > _maxLlamaCppReasoningBudgetTokens) {
      throw RangeError.range(
        budget.maxTokens,
        0,
        _maxLlamaCppReasoningBudgetTokens,
        'thinkingBudget.maxTokens',
        'must fit the signed 32-bit llama.cpp reasoning-budget limit',
      );
    }
    if (hasMediaParts) {
      throw LlamaUnsupportedException(
        'llama.cpp thinking-budget control currently supports text-only '
        'generation in llamadart because template prompt tokens must be '
        'inspected by the native reasoning sampler.',
      );
    }

    final startTag = budget.startTag;
    final endTag = budget.endTag;
    if (startTag == null ||
        startTag.trim().isEmpty ||
        endTag == null ||
        endTag.trim().isEmpty) {
      throw ArgumentError(
        'GenerationParams.thinkingBudget requires non-empty startTag and '
        'endTag for raw generation. LlamaEngine.create fills them from the '
        'selected chat template automatically.',
      );
    }

    return _LlamaCppThinkingBudgetConfig(
      maxTokens: budget.maxTokens,
      startTag: startTag,
      endTag: endTag,
      forcedMessage: budget.forcedMessage ?? '',
    );
  }

  _LlamaCppSpeculativeConfig? _resolveLlamaCppSpeculativeConfig(
    GenerationParams params, {
    required bool hasMediaParts,
  }) {
    final speculativeConfig = params.resolvedSpeculativeDecodingConfig;
    if (speculativeConfig == null) {
      return null;
    }

    if (hasMediaParts) {
      throw LlamaUnsupportedException(
        'llama.cpp speculative decoding currently supports text-only '
        'generation in llamadart.',
      );
    }
    if (params.thinkingBudget != null) {
      throw LlamaUnsupportedException(
        'llama.cpp thinking-budget control cannot be combined with '
        'speculative decoding in llamadart.',
      );
    }
    if (params.grammar != null) {
      throw LlamaUnsupportedException(
        'llama.cpp speculative decoding does not yet support grammar '
        'sampling in llamadart.',
      );
    }

    final requestedStrategies = speculativeConfig.effectiveStrategies;
    final strategies = <SpeculativeDecodingStrategy>[
      for (final strategy in requestedStrategies)
        if (strategy == SpeculativeDecodingStrategy.backendDefault)
          SpeculativeDecodingStrategy.ngramMod
        else
          strategy,
    ];
    final uniqueStrategies = <SpeculativeDecodingStrategy>[];
    for (final strategy in strategies) {
      if (!_llamaCppSpeculativeTypeNames.containsKey(strategy)) {
        throw LlamaUnsupportedException(
          'llama.cpp does not support speculative strategy $strategy.',
        );
      }
      if (!uniqueStrategies.contains(strategy)) {
        uniqueStrategies.add(strategy);
      }
    }

    final draftStrategyCount = uniqueStrategies
        .where(_llamaCppDraftStrategies.contains)
        .length;
    if (draftStrategyCount > 1) {
      throw LlamaUnsupportedException(
        'llama.cpp speculative decoding can mix n-gram strategies with at '
        'most one draft-model strategy in llamadart.',
      );
    }

    final draftModelPath = speculativeConfig.draftModelPath;
    if (draftModelPath != null && draftModelPath.trim().isEmpty) {
      throw ArgumentError.value(
        draftModelPath,
        'draftModelPath',
        'must be null or a non-empty path for llama.cpp speculative decoding',
      );
    }

    final requiresExternalDraft = uniqueStrategies.any(
      (strategy) =>
          strategy == SpeculativeDecodingStrategy.draftSimple ||
          strategy == SpeculativeDecodingStrategy.draftEagle3 ||
          strategy == SpeculativeDecodingStrategy.draftDflash ||
          strategy == SpeculativeDecodingStrategy.draftDspark,
    );
    if (requiresExternalDraft && draftModelPath == null) {
      throw LlamaArgumentException(
        'llama.cpp ${uniqueStrategies.map((s) => _llamaCppSpeculativeTypeNames[s]).join(', ')} '
        'requires SpeculativeDecodingConfig.draftModel.',
      );
    }

    final isNgramOnly =
        draftStrategyCount == 0 &&
        uniqueStrategies.every(
          (strategy) =>
              strategy != SpeculativeDecodingStrategy.backendDefault &&
              _llamaCppSpeculativeTypeNames.containsKey(strategy),
        );
    if (isNgramOnly &&
        (speculativeConfig.draftTokenMin != null ||
            speculativeConfig.minProbability != null ||
            speculativeConfig.draftSplitProbability != null ||
            speculativeConfig.draftModelPath != null)) {
      throw LlamaUnsupportedException(
        'llama.cpp n-gram speculative decoding uses token history and does '
        'not support draftTokenMin, minProbability, draftSplitProbability, or '
        'draftModel unless a draft-model strategy is also enabled.',
      );
    }

    final ngramCachePaths = <String?>[
      speculativeConfig.ngramCacheStaticPath,
      speculativeConfig.ngramCacheDynamicPath,
    ];
    for (final cachePath in ngramCachePaths) {
      if (cachePath == null) {
        continue;
      }
      if (cachePath.trim().isEmpty) {
        throw ArgumentError.value(
          cachePath,
          'ngramCachePath',
          'must be null or a non-empty path',
        );
      }
      if (!File(cachePath).existsSync()) {
        throw ArgumentError.value(
          cachePath,
          'ngramCachePath',
          'must exist before enabling llama.cpp ngram-cache',
        );
      }
    }

    final draftTokenMax = _resolveLlamaCppSpeculativeDraftTokenMax(
      uniqueStrategies,
      speculativeConfig,
    );
    final draftTokenMin = speculativeConfig.draftTokenMin ?? 0;
    if (draftTokenMax <= 0) {
      throw RangeError.value(
        draftTokenMax,
        'draftTokenMax',
        'must be greater than zero for llama.cpp speculative decoding',
      );
    }
    if (draftTokenMin < 0 || draftTokenMin > draftTokenMax) {
      throw RangeError.value(
        draftTokenMin,
        'draftTokenMin',
        'must be between zero and draftTokenMax for llama.cpp speculative decoding',
      );
    }

    final ngramTokenMin = speculativeConfig.ngramTokenMin;
    final ngramTokenMax = speculativeConfig.ngramTokenMax;
    if (ngramTokenMin != null &&
        ngramTokenMax != null &&
        ngramTokenMin > ngramTokenMax) {
      throw RangeError.value(
        ngramTokenMin,
        'ngramTokenMin',
        'must be less than or equal to ngramTokenMax',
      );
    }

    final draftMicroBatchSize = speculativeConfig.draftMicroBatchSize;
    if (draftMicroBatchSize != null) {
      if (draftStrategyCount == 0) {
        throw LlamaUnsupportedException(
          'llama.cpp n-gram speculative decoding creates no draft context, so '
          'draftMicroBatchSize needs a draft-model or MTP strategy.',
        );
      }
      if (draftMicroBatchSize < 1) {
        throw LlamaArgumentException(
          'SpeculativeDecodingConfig.draftMicroBatchSize must be at least 1, '
          'or null to keep the target micro-batch size.',
          name: 'draftMicroBatchSize',
          invalidValue: draftMicroBatchSize,
        );
      }
      final blockSize = draftTokenMax + 1;
      final usesBlockDraft =
          uniqueStrategies.contains(SpeculativeDecodingStrategy.draftDflash) ||
          uniqueStrategies.contains(SpeculativeDecodingStrategy.draftDspark);
      if (usesBlockDraft && draftMicroBatchSize < blockSize) {
        throw _draftMicroBatchTooSmall((
          size: draftMicroBatchSize,
          inherited: false,
        ), 'draftTokenMax + 1 ($blockSize) $_draftBlockRequirement');
      }
    }

    final typeNames = uniqueStrategies
        .map((strategy) => _llamaCppSpeculativeTypeNames[strategy]!)
        .join(',');
    return _LlamaCppSpeculativeConfig(
      strategies: List<SpeculativeDecodingStrategy>.unmodifiable(
        uniqueStrategies,
      ),
      typeNames: typeNames,
      draftTokenMax: draftTokenMax,
      draftTokenMin: draftTokenMin,
      minProbability: speculativeConfig.minProbability,
      draftSplitProbability: speculativeConfig.draftSplitProbability,
      draftMicroBatchSize: draftMicroBatchSize,
      draftModelPath: draftModelPath,
      ngramSizeN: speculativeConfig.ngramSizeN ?? speculativeConfig.ngramSize,
      ngramSizeM: speculativeConfig.ngramSizeM,
      ngramMinHits: speculativeConfig.ngramMinHits,
      ngramMatch: speculativeConfig.ngramMatch,
      ngramTokenMin: ngramTokenMin,
      ngramTokenMax:
          ngramTokenMax ??
          (uniqueStrategies.contains(SpeculativeDecodingStrategy.ngramMod)
              ? speculativeConfig.draftTokenMax
              : null),
      ngramCacheStaticPath: speculativeConfig.ngramCacheStaticPath,
      ngramCacheDynamicPath: speculativeConfig.ngramCacheDynamicPath,
    );
  }

  /// Resolves llama.cpp speculative strategy type names for unit tests.
  String? debugResolveSpeculativeTypeNamesForTesting(
    GenerationParams params, {
    bool hasMediaParts = false,
  }) {
    return _resolveLlamaCppSpeculativeConfig(
      params,
      hasMediaParts: hasMediaParts,
    )?.typeNames;
  }

  void _validateMtpModelLoad(
    _LlamaCppSpeculativeConfig? config,
    ModelParams modelParams,
  ) {
    if (config?.usesMtp == true &&
        config?.draftModelPath == null &&
        !modelParams.loadMtp) {
      throw LlamaUnsupportedException(
        'Bundled MTP speculative decoding requires the model to be loaded '
        'with ModelParams(loadMtp: true). Reload the target model with MTP '
        'tensors enabled, or provide a compatible external draftModel.',
      );
    }
  }

  void _validateDraftMicroBatchSizeFitsContext(
    _LlamaCppSpeculativeConfig? config, {
    required int batchSize,
    required int contextSize,
  }) {
    final draftMicroBatchSize = config?.draftMicroBatchSize;
    if (draftMicroBatchSize == null) {
      return;
    }
    final limit = math.min(batchSize, contextSize);
    if (draftMicroBatchSize > limit) {
      throw LlamaArgumentException(
        'SpeculativeDecodingConfig.draftMicroBatchSize ($draftMicroBatchSize) '
        "must not exceed the draft context's logical batch size ($limit): "
        'the resolved ModelParams.batchSize, bounded by '
        'ModelParams.contextSize.',
        name: 'draftMicroBatchSize',
        invalidValue: draftMicroBatchSize,
      );
    }
  }

  /// Resolves the draft context's micro-batch: `draftMicroBatchSize`, or the
  /// target context parameters' `n_ubatch` as `llama_init_from_model`
  /// resolves it.
  _DraftMicroBatch _resolveDraftMicroBatch(
    _LlamaCppSpeculativeConfig config, {
    required int targetBatchSize,
    required int targetMicroBatchSize,
  }) {
    final draftMicroBatchSize = config.draftMicroBatchSize;
    if (draftMicroBatchSize != null) {
      return (size: draftMicroBatchSize, inherited: false);
    }
    return (
      size: targetMicroBatchSize == 0
          ? targetBatchSize
          : math.min(targetBatchSize, targetMicroBatchSize),
      inherited: true,
    );
  }

  /// Rejects a draft micro-batch smaller than the block llama.cpp
  /// draft-dflash and draft-dspark decode in one micro-batch, which it sizes
  /// from the draft model's metadata (`common/speculative.cpp`).
  void _validateDraftBlockFitsMicroBatch(
    _LlamaCppSpeculativeConfig config,
    _DraftMicroBatch microBatch,
    String? Function(String key) draftMetadata,
  ) {
    if (!config.usesBlockDraft) {
      return;
    }
    int? metadataInt(String key) =>
        int.tryParse(draftMetadata(key)?.trim() ?? '');
    final blockSize =
        metadataInt('dflash.block_size') ?? _llamaCppDefaultDflashBlockSize;
    // llama.cpp decodes a LiliCorr draft's whole trained block, whatever
    // draftTokenMax is.
    final liliCorrTopK = metadataInt('lilicorr.candidate_topk') ?? 0;
    if (liliCorrTopK > 0) {
      if (microBatch.size < blockSize) {
        throw _draftMicroBatchTooSmall(
          microBatch,
          'the draft model block size dflash.block_size ($blockSize) for a '
          'LiliCorr draft model (lilicorr.candidate_topk $liliCorrTopK), '
          'which llama.cpp draft-dflash and draft-dspark decode as a whole '
          'block in one micro-batch.',
        );
      }
      return;
    }
    // Otherwise the block is the draft length, clamped to what the trained
    // block yields, plus the anchor token, which anchor-first DSpark drafts
    // too. llama.cpp treats sample_from_anchor as true when absent and otherwise
    // only when the value is exactly "true".
    final anchorFirst =
        config.usesDspark &&
        (draftMetadata('dflash.sample_from_anchor') ?? 'true') == 'true';
    final draftLength = math.min(
      config.draftTokenMax,
      anchorFirst ? blockSize : blockSize - 1,
    );
    final block = anchorFirst ? draftLength : draftLength + 1;
    if (microBatch.size < block) {
      throw _draftMicroBatchTooSmall(
        microBatch,
        'the $block-token draft block (draftTokenMax ${config.draftTokenMax} '
        'within dflash.block_size $blockSize'
        '${anchorFirst ? ', anchor-first DSpark' : ', plus the anchor token'}) '
        '$_draftBlockRequirement',
      );
    }
  }

  /// Validates a block draft's micro-batch, set or inherited from target
  /// context parameters, against the block the draft model's metadata gives
  /// for unit tests.
  void debugValidateDraftBlockMicroBatchForTesting(
    GenerationParams params, {
    Map<String, String> draftMetadata = const {},
    int targetBatchSize = 2048,
    int targetMicroBatchSize = 512,
  }) {
    final config = _resolveLlamaCppSpeculativeConfig(
      params,
      hasMediaParts: false,
    );
    if (config == null) {
      return;
    }
    _validateDraftBlockFitsMicroBatch(
      config,
      _resolveDraftMicroBatch(
        config,
        targetBatchSize: targetBatchSize,
        targetMicroBatchSize: targetMicroBatchSize,
      ),
      (key) => draftMetadata[key],
    );
  }

  /// Validates a speculative draft micro-batch size against a context's
  /// resolved logical batch and context sizes for unit tests.
  void debugValidateDraftMicroBatchSizeForTesting(
    GenerationParams params, {
    required int batchSize,
    required int contextSize,
  }) {
    _validateDraftMicroBatchSizeFitsContext(
      _resolveLlamaCppSpeculativeConfig(params, hasMediaParts: false),
      batchSize: batchSize,
      contextSize: contextSize,
    );
  }

  /// Validates bundled MTP model-loading requirements for unit tests.
  void debugValidateMtpModelLoadForTesting(
    GenerationParams params,
    ModelParams modelParams, {
    bool hasMediaParts = false,
  }) {
    _validateMtpModelLoad(
      _resolveLlamaCppSpeculativeConfig(params, hasMediaParts: hasMediaParts),
      modelParams,
    );
  }

  /// Validates a llama.cpp thinking budget for unit tests.
  void debugValidateThinkingBudgetForTesting(
    GenerationParams params, {
    bool hasMediaParts = false,
  }) {
    _resolveLlamaCppThinkingBudgetConfig(params, hasMediaParts: hasMediaParts);
  }

  /// Resolves whether llama.cpp speculative prompt processing suppresses logits.
  bool debugSuppressesDraftProcessLogitsForTesting(
    GenerationParams params, {
    bool hasMediaParts = false,
  }) {
    return _resolveLlamaCppSpeculativeConfig(
          params,
          hasMediaParts: hasMediaParts,
        )?.suppressDraftProcessLogits ??
        false;
  }

  /// Resolves llama.cpp speculative native params for unit tests.
  Map<String, Object?> debugResolveSpeculativeNativeParamsForTesting(
    GenerationParams params, {
    bool hasMediaParts = false,
  }) {
    final config = _resolveLlamaCppSpeculativeConfig(
      params,
      hasMediaParts: hasMediaParts,
    );
    return <String, Object?>{
      'typeNames': config?.typeNames,
      'draftTokenMax': config?.draftTokenMax,
      'draftMicroBatchSize': config?.draftMicroBatchSize,
      'ngramSizeN': config?.ngramSizeN,
      'ngramSizeM': config?.ngramSizeM,
      'ngramTokenMax': config?.ngramTokenMax,
      'hasDraftContextStrategy': config?.hasDraftContextStrategy,
      'requiresExternalDraftModel': config?.requiresExternalDraftModel,
      'usesMtp': config?.usesMtp,
      'suppressDraftProcessLogits': config?.suppressDraftProcessLogits,
    };
  }

  /// Throws the native speculative-session initialization error for tests.
  Never debugThrowSpeculativeInitFailureForTesting(
    GenerationParams params, {
    bool hasMediaParts = false,
  }) {
    final config = _resolveLlamaCppSpeculativeConfig(
      params,
      hasMediaParts: hasMediaParts,
    );
    if (config == null) {
      throw StateError('Speculative decoding must be enabled for this check.');
    }
    throw _speculativeInitFailure(config);
  }

  LlamaUnsupportedException _speculativeInitFailure(
    _LlamaCppSpeculativeConfig config,
  ) {
    final strategyHint = config.usesDspark
        ? 'DSpark requires leehack/llamadart-native@$_minimumDsparkNativeTag '
              'or a newer ABI-compatible native build with DSpark '
              'draft-context support. '
        : '';
    final draftHint = config.requiresExternalDraftModel
        ? 'Verify that the external draft model is compatible with the target '
              'model. '
        : 'Verify that the selected strategy is compatible with this model. ';
    return LlamaUnsupportedException(
      'llama.cpp speculative decoding (${config.typeNames}) is not available '
      'for this model/context. $strategyHint$draftHint'
      'Use a native libllamadart build that includes the llama-common generic '
      'speculative wrapper, and set ModelParams.speculativeRollbackTokenMax '
      '>= the effective speculative draft length (draftTokenMax for '
      'draft-model or ngram-cache strategies; ngramTokenMax when set for '
      'ngram-mod, otherwise draftTokenMax/default; ngramSizeM for '
      'ngram-simple, ngram-map-k, or ngram-map-k4v) when the target '
      'architecture needs bounded rollback snapshots.',
    );
  }

  ({int lastN, double repeat, double frequency, double presence})
  _resolvePenaltySamplerConfig(GenerationParams params) {
    return (
      lastN: 64,
      repeat: params.penalty,
      frequency: 0.0,
      presence: params.presencePenalty,
    );
  }

  /// Resolves llama.cpp penalty sampler parameters for unit tests.
  Map<String, Object> debugResolvePenaltySamplerParamsForTesting(
    GenerationParams params,
  ) {
    final config = _resolvePenaltySamplerConfig(params);
    return <String, Object>{
      'lastN': config.lastN,
      'repeat': config.repeat,
      'frequency': config.frequency,
      'presence': config.presence,
    };
  }

  /// Runs [action] while native batch logits are temporarily zeroed.
  static T debugWithSuppressedBatchLogitsForTesting<T>(
    Pointer<Int8> logits,
    int tokenCount,
    bool suppress,
    T Function() action,
  ) {
    return _withSuppressedBatchLogits(logits, tokenCount, suppress, action);
  }

  int _resolveLlamaCppSpeculativeDraftTokenMax(
    List<SpeculativeDecodingStrategy> strategies,
    SpeculativeDecodingConfig config,
  ) {
    var max = 0;
    for (final strategy in strategies) {
      switch (strategy) {
        case SpeculativeDecodingStrategy.draftSimple:
        case SpeculativeDecodingStrategy.draftEagle3:
        case SpeculativeDecodingStrategy.mtp:
        case SpeculativeDecodingStrategy.draftDflash:
        case SpeculativeDecodingStrategy.draftDspark:
          max = math.max(max, config.draftTokenMax ?? 3);
          break;
        case SpeculativeDecodingStrategy.ngramSimple:
        case SpeculativeDecodingStrategy.ngramMapK:
        case SpeculativeDecodingStrategy.ngramMapK4v:
          max = math.max(max, config.ngramSizeM ?? 48);
          break;
        case SpeculativeDecodingStrategy.ngramMod:
          max = math.max(
            max,
            config.ngramTokenMax ?? config.draftTokenMax ?? 64,
          );
          break;
        case SpeculativeDecodingStrategy.ngramCache:
          max = math.max(max, config.draftTokenMax ?? 8);
          break;
        case SpeculativeDecodingStrategy.backendDefault:
          max = math.max(max, config.draftTokenMax ?? 64);
          break;
      }
    }
    return max == 0 ? 64 : max;
  }

  /// Generates text based on the given [prompt] and [params].
  ///
  /// Returns a [Stream] of token bytes.
  /// Supports multimodal input via [parts].
  /// Calls [onLimit] before the stream closes when a token limit ended the
  /// generation.
  ///
  /// The caller wrote [prompt]: a media placeholder in it stands for a part,
  /// and parts without one go before the prompt.
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    List<LlamaContentPart>? parts,
    bool countPromptTokensInPenalties = false,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) => _generate(
    contextHandle,
    prompt,
    params,
    cancelTokenAddress,
    parts: parts,
    countPromptTokensInPenalties: countPromptTokensInPenalties,
    onLimit: onLimit,
  );

  /// Generates like [generate] from a [prompt] that a chat template rendered
  /// with [mediaMarker] where each part was. A placeholder string elsewhere
  /// in it is message text.
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    required String mediaMarker,
    List<LlamaContentPart>? parts,
    bool countPromptTokensInPenalties = false,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) => _generate(
    contextHandle,
    prompt,
    params,
    cancelTokenAddress,
    parts: parts,
    countPromptTokensInPenalties: countPromptTokensInPenalties,
    chatMediaMarker: mediaMarker,
    onLimit: onLimit,
  );

  Stream<List<int>> _generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    List<LlamaContentPart>? parts,
    bool countPromptTokensInPenalties = false,
    String? chatMediaMarker,
    void Function(BackendGenerationLimit limit)? onLimit,
  }) async* {
    var ctx = _contexts[contextHandle];
    if (ctx == null) throw Exception("Invalid context handle");
    _ensureNoActiveTts(contextHandle, 'generate text');
    ctx.performanceAvailable = false;
    _ensureContextUsable(contextHandle, ctx);
    _generatingContexts.update(
      contextHandle,
      (count) => count + 1,
      ifAbsent: () => 1,
    );

    Pointer<Int32> tokensPtr = nullptr;
    Pointer<Uint8> pieceBuf = nullptr;
    Pointer<Utf8> grammarPtr = nullptr;
    Pointer<Utf8> rootPtr = nullptr;
    _LazyGrammarConfig? lazyGrammarConfig;
    Pointer<llama_sampler> sampler = nullptr;
    Pointer<llama_dart_speculative> speculativeSession = nullptr;
    _SpeculativeApi? speculativeApi;

    try {
      final modelHandle = _contextToModel[contextHandle]!;
      final model = _models[modelHandle]!;
      final modelParams = _contextParams[contextHandle]!;
      final vocab = llama_model_get_vocab(model.pointer);
      final hasMediaParts =
          parts?.any((p) => p is LlamaImageContent || p is LlamaAudioContent) ??
          false;
      final hasVideoParts =
          parts?.any((part) => part is LlamaVideoContent) ?? false;
      if (ctx.qwen35VulkanRestricted &&
          (hasMediaParts ||
              hasVideoParts ||
              params.resolvedSpeculativeDecodingConfig != null)) {
        throw LlamaUnsupportedException(_qwen35VulkanRestriction);
      }
      if (hasVideoParts) {
        final mmHandle = _modelToMtmd[modelHandle];
        if (mmHandle == null) {
          throw LlamaUnsupportedException(
            'Video input is unavailable because no multimodal projector is '
            'loaded to inspect native runtime capability. Loading a compatible '
            'projector enables inspection only; it does not enable public video '
            'ingestion. Extract and send image frames instead.',
          );
        }
        final nativeRuntimeSupportsVideo = supportsVideo(mmHandle);
        if (!nativeRuntimeSupportsVideo) {
          throw LlamaUnsupportedException(_videoUnreportedMessage());
        }
        throw LlamaUnsupportedException(
          'The loaded native runtime reports mtmd video support, but the Dart '
          'frame-ingestion and video-context lifetime contract is not wired. '
          'Extract and send image frames instead.',
        );
      }
      if (hasMediaParts) {
        _checkLlamaCppMediaParts(
          parts!,
          projectorLoaded: _modelToMtmd[modelHandle] != null,
        );
      }
      final thinkingBudgetConfig = _resolveLlamaCppThinkingBudgetConfig(
        params,
        hasMediaParts: hasMediaParts,
      );
      final speculativeConfig = _resolveLlamaCppSpeculativeConfig(
        params,
        hasMediaParts: hasMediaParts,
      );
      _validateMtpModelLoad(
        speculativeConfig,
        _modelLoadParams[modelHandle] ?? const ModelParams(),
      );
      _validateDraftMicroBatchSizeFitsContext(
        speculativeConfig,
        batchSize: modelParams.n_batch,
        contextSize: modelParams.n_ctx,
      );
      final reasoningBudgetApi = thinkingBudgetConfig == null
          ? null
          : _resolveReasoningBudgetApi();
      // 1. Reset Context
      ctx = _resetContext(
        contextHandle,
        ctx,
        clearMemory:
            hasMediaParts ||
            speculativeConfig != null ||
            !params.reusePromptPrefix,
      );
      _resetRequestPerformance(contextHandle, ctx);

      // 2. Prepare Resources
      final nCtx = llama_n_ctx(ctx.pointer);
      final batch = _batches[contextHandle]!.batch;
      tokensPtr = malloc<Int32>(nCtx);
      pieceBuf = malloc<Uint8>(256);

      if (speculativeConfig != null) {
        speculativeApi = _resolveSpeculativeApi();
        final draftModelPath = speculativeConfig.draftModelPath;
        final draftModel = draftModelPath == null
            ? null
            : _loadSpeculativeDraftModel(
                modelHandle,
                draftModelPath,
                'speculative draft model',
                loadMtp: speculativeConfig.usesMtp,
              );
        if (draftModel != null) {
          _validateDraftBlockFitsMicroBatch(
            speculativeConfig,
            _resolveDraftMicroBatch(
              speculativeConfig,
              targetBatchSize: modelParams.n_batch,
              targetMicroBatchSize: modelParams.n_ubatch,
            ),
            (key) => _readModelMetadataValue(draftModel.pointer, key),
          );
        }
        speculativeSession = speculativeApi.initSession(
          targetModel: model.pointer,
          draftModel: draftModel?.pointer,
          targetContext: ctx.pointer,
          contextParams: modelParams,
          config: speculativeConfig,
        );
        IsolateShutdownReleases.current.hold(
          ShutdownStage.session,
          speculativeApi.freeAddress,
          speculativeSession,
        );
        if (speculativeSession == nullptr) {
          _calls.failures.throwIfCaught(
            'llama_dart_speculative_init',
            LlamaInferenceException.new,
            windowsFreeOnly: [ctx.pointer],
          );
          throw _speculativeInitFailure(speculativeConfig);
        }
        debugOnSpeculativeDraftContextForTesting?.call(
          speculativeApi.getDraftContext(speculativeSession),
        );
        // Native initialization enables the outputs its selected strategies
        // consume; the legacy need_embd query always returned false.
        llama_perf_context_reset(ctx.pointer);
      }

      if (params.grammar != null) {
        grammarPtr = params.grammar!.toNativeUtf8();
        rootPtr = params.grammarRoot.toNativeUtf8();
        if (params.grammarLazy && params.grammarTriggers.isNotEmpty) {
          lazyGrammarConfig = _buildLazyGrammarConfig(params);
        }
      }

      // 3. Ingest Prompt (Text or Multimodal)
      final promptEvalStopwatch = Stopwatch()..start();
      final (
        nPast: initialTokens,
        :promptTokenCount,
        :evaluatedPromptTokens,
      ) = _ingestPrompt(
        contextHandle,
        modelHandle,
        ctx,
        batch,
        vocab,
        prompt,
        parts,
        tokensPtr,
        nCtx,
        modelParams,
        chatMediaMarker: chatMediaMarker,
        allowTextPromptReuse:
            speculativeConfig == null &&
            !hasMediaParts &&
            params.reusePromptPrefix,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
        cancelToken: Pointer<Int8>.fromAddress(cancelTokenAddress),
      );
      promptEvalStopwatch.stop();
      ctx.lastPerfPromptEvalMs =
          promptEvalStopwatch.elapsedMicroseconds / 1000.0;
      ctx.lastPerfPromptEvalTokens = evaluatedPromptTokens;

      _ensureLogitsAvailableAfterPromptEval(ctx.pointer);
      if (speculativeSession != nullptr &&
          !speculativeApi!.begin(
            speculativeSession,
            0,
            tokensPtr,
            promptTokenCount,
          )) {
        _throwIfSpeculativeCaught('llama_dart_speculative_begin', ctx.pointer);
        throw Exception(
          "Failed to initialize llama.cpp speculative prompt state",
        );
      }

      // 4. Initialize and Run Sampler Loop
      sampler = _initializeSampler(
        params,
        vocab,
        model.vocabSize,
        model.suppressedTokens,
        grammarPtr,
        rootPtr,
        lazyGrammarConfig,
        thinkingBudgetConfig,
        reasoningBudgetApi,
        promptTokenCount,
        tokensPtr,
        countPromptTokensInPenalties,
      );

      final preservedTokenIds = _resolvePreservedTokenIds(
        vocab,
        params.preservedTokens,
      );
      final effectiveStopSequences = _effectiveStopSequences(
        params.stopSequences,
        params.preservedTokens,
      );

      if (speculativeSession != nullptr && speculativeConfig != null) {
        yield* _runSpeculativeInferenceLoop(
          ctx,
          batch,
          vocab,
          sampler,
          params,
          speculativeConfig,
          initialTokens,
          nCtx,
          cancelTokenAddress,
          pieceBuf,
          preservedTokenIds,
          effectiveStopSequences,
          speculativeSession,
          speculativeApi!,
          tokensPtr,
          onLimit,
        );
      } else {
        yield* _runInferenceLoop(
          ctx,
          batch,
          vocab,
          sampler,
          params,
          initialTokens,
          nCtx,
          cancelTokenAddress,
          pieceBuf,
          preservedTokenIds,
          effectiveStopSequences,
          onLimit,
        );
      }
    } finally {
      if (speculativeSession != nullptr) {
        IsolateShutdownReleases.current.release(speculativeSession);
        speculativeApi?.free(speculativeSession);
      }
      if (sampler != nullptr) _freeSamplerChain(sampler);
      final remaining = (_generatingContexts[contextHandle] ?? 1) - 1;
      if (remaining <= 0) {
        _generatingContexts.remove(contextHandle);
      } else {
        _generatingContexts[contextHandle] = remaining;
      }
      if (tokensPtr != nullptr) malloc.free(tokensPtr);
      if (pieceBuf != nullptr) malloc.free(pieceBuf);
      if (grammarPtr != nullptr) malloc.free(grammarPtr);
      if (rootPtr != nullptr) malloc.free(rootPtr);
      lazyGrammarConfig?.dispose();
    }
  }

  /// Evaluates [prompt] as [generate] would, then returns the
  /// log-probabilities of [candidates] and of the [topK] most probable tokens
  /// at the next position, from a softmax over the raw logits.
  ///
  /// Throws [RangeError] for a candidate outside the vocabulary,
  /// [LlamaStateException] while text generation or text-to-speech is active
  /// on the context, and [LlamaUnsupportedException] for a model without a
  /// decoder.
  LlamaNextTokenScores scoreNextToken(
    int contextHandle,
    String prompt, {
    required List<int> candidates,
    required int topK,
    required bool reusePromptPrefix,
  }) {
    var ctx = _contexts[contextHandle];
    if (ctx == null) throw Exception('Invalid context handle');
    _ensureNoActiveTts(contextHandle, 'score tokens');
    ctx.performanceAvailable = false;
    _ensureContextUsable(contextHandle, ctx);
    if (_generatingContexts.containsKey(contextHandle)) {
      throw LlamaStateException(
        'Cannot score tokens while generation is active on context '
        '$contextHandle',
      );
    }
    final modelHandle = _contextToModel[contextHandle]!;
    final model = _models[modelHandle]!;
    if (!llama_model_has_decoder(model.pointer)) {
      throw LlamaUnsupportedException(
        'Next-token scoring needs a model with a decoder; the loaded model '
        'has none.',
      );
    }
    final vocabSize = model.vocabSize;
    for (final token in candidates) {
      RangeError.checkValueInInterval(token, 0, vocabSize - 1, 'candidates');
    }
    RangeError.checkValueInInterval(topK, 0, vocabSize, 'topK');

    final vocab = llama_model_get_vocab(model.pointer);
    final modelParams = _contextParams[contextHandle]!;
    ctx = _resetContext(contextHandle, ctx, clearMemory: !reusePromptPrefix);
    _resetRequestPerformance(contextHandle, ctx);
    final nCtx = llama_n_ctx(ctx.pointer);
    final tokensPtr = malloc<Int32>(nCtx);
    var pieceCapacity = 256;
    var pieceBuf = malloc<Uint8>(pieceCapacity);
    try {
      final promptTokens = _ingestTextPrompt(
        _batches[contextHandle]!.batch,
        vocab,
        prompt,
        tokensPtr,
        nCtx,
        ctx,
        maxBatchTokens: modelParams.n_batch,
        allowPromptReuse: reusePromptPrefix,
        speculativeSession: nullptr,
        speculativeApi: null,
        speculativeConfig: null,
        isCancelled: () => false,
      );
      if (promptTokens == 0) {
        throw LlamaInferenceException('The prompt tokenized to no tokens.');
      }
      _ensureLogitsAvailableAfterPromptEval(ctx.pointer);
      final logitsPtr = llama_get_logits_ith(ctx.pointer, -1);
      if (logitsPtr == nullptr) {
        throw LlamaInferenceException(
          'Prompt evaluation produced no logits for the last token.',
        );
      }
      final logits = logitsPtr.asTypedList(vocabSize);

      var maxLogit = double.negativeInfinity;
      for (var i = 0; i < vocabSize; i++) {
        if (logits[i] > maxLogit) maxLogit = logits[i];
      }
      var sum = 0.0;
      for (var i = 0; i < vocabSize; i++) {
        sum += math.exp(logits[i] - maxLogit);
      }
      final logSum = maxLogit + math.log(sum);

      LlamaTokenLogprob scored(int token) {
        var n = _calls.tokenToPiece(
          vocab,
          token,
          pieceBuf.cast(),
          pieceCapacity,
          0,
          true,
        );
        if (n < 0) {
          malloc.free(pieceBuf);
          pieceCapacity = -n;
          pieceBuf = malloc<Uint8>(pieceCapacity);
          n = _calls.tokenToPiece(
            vocab,
            token,
            pieceBuf.cast(),
            pieceCapacity,
            0,
            true,
          );
        }
        return LlamaTokenLogprob(
          token: token,
          bytes: n > 0 ? List<int>.of(pieceBuf.asTypedList(n)) : const [],
          logprob: logits[token] - logSum,
        );
      }

      return LlamaNextTokenScores(
        candidates: [for (final token in candidates) scored(token)],
        top: [for (final token in _topTokens(logits, topK)) scored(token)],
        promptTokens: promptTokens,
      );
    } finally {
      malloc.free(tokensPtr);
      malloc.free(pieceBuf);
    }
  }

  /// Ids of the [k] largest [logits], largest first; ties keep the lower id.
  static List<int> _topTokens(Float32List logits, int k) {
    if (k == 0) return const [];
    final heap = <int>[];
    bool before(int a, int b) =>
        logits[a] < logits[b] || (logits[a] == logits[b] && a > b);
    void siftDown(int i) {
      while (true) {
        final left = 2 * i + 1, right = left + 1;
        var smallest = i;
        if (left < heap.length && before(heap[left], heap[smallest])) {
          smallest = left;
        }
        if (right < heap.length && before(heap[right], heap[smallest])) {
          smallest = right;
        }
        if (smallest == i) return;
        final t = heap[i];
        heap[i] = heap[smallest];
        heap[smallest] = t;
        i = smallest;
      }
    }

    for (var token = 0; token < logits.length; token++) {
      if (heap.length < k) {
        heap.add(token);
        var i = heap.length - 1;
        while (i > 0) {
          final parent = (i - 1) ~/ 2;
          if (!before(heap[i], heap[parent])) break;
          final t = heap[i];
          heap[i] = heap[parent];
          heap[parent] = t;
          i = parent;
        }
      } else if (before(heap[0], token)) {
        heap[0] = token;
        siftDown(0);
      }
    }
    return heap..sort((a, b) => before(a, b) ? 1 : (before(b, a) ? -1 : 0));
  }

  /// Generates a single embedding vector for [text].
  List<double> embed(int contextHandle, String text, {bool normalize = true}) {
    _ensureNoActiveTts(contextHandle, 'embed');
    _contexts[contextHandle]?.performanceAvailable = false;
    return _embed(
      contextHandle,
      text,
      normalize: normalize,
      resetPerformance: true,
    );
  }

  List<double> _embed(
    int contextHandle,
    String text, {
    required bool normalize,
    required bool resetPerformance,
  }) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw Exception('Invalid context handle');
    }

    final modelHandle = _contextToModel[contextHandle];
    if (modelHandle == null) {
      throw Exception('Invalid context handle');
    }

    final model = _models[modelHandle];
    if (model == null) {
      throw Exception('Invalid model handle');
    }

    final contextParams = _contextParams[contextHandle];
    if (contextParams == null) {
      throw Exception('Missing context parameters');
    }
    _ensureContextUsable(contextHandle, ctx);
    _checkQwen35VulkanEmbedding(ctx);

    final hasEncoder = llama_model_has_encoder(model.pointer);
    final hasDecoder = llama_model_has_decoder(model.pointer);
    if (hasEncoder && hasDecoder) {
      throw LlamaUnsupportedException(_encoderDecoderEmbeddingsUnsupported);
    }
    final useEncoderPath = hasEncoder && !hasDecoder;
    final poolingType = llama_pooling_type$1(ctx.pointer);
    _checkEmbeddingPoolingType(poolingType);

    final vocab = llama_model_get_vocab(model.pointer);
    final nSeqCtx = llama_n_ctx_seq(ctx.pointer);
    final tokens = _tokenizeEmbeddingText(vocab, text, nSeqCtx);
    final passTokenLimit = _embeddingPassTokenLimit(
      modelHandle,
      ctx.pointer,
      useEncoderPath,
      poolingType,
    );
    _checkEmbeddingPassTokenLimit(tokens.length, passTokenLimit);
    final configuredBatchSize = contextParams.n_batch > 0
        ? contextParams.n_batch
        : tokens.length;
    final batchCapacity = math.max(
      1,
      math.min(configuredBatchSize, tokens.length),
    );
    final embeddingSize = _resolveEmbeddingDimension(model.pointer);
    final batch = _batchInit(batchCapacity, 0, 1);

    try {
      _calls.synchronize(ctx.pointer);
      if (resetPerformance) _resetRequestPerformance(contextHandle, ctx);
      _clearContextMemory(ctx.pointer, strict: false);
      ctx.cachedPromptTokens = null;
      llama_set_embeddings(ctx.pointer, true);

      var decodedTokens = 0;
      while (decodedTokens < tokens.length) {
        final remaining = tokens.length - decodedTokens;
        final chunkTokenCount = math.min(batchCapacity, remaining);
        batch.n_tokens = chunkTokenCount;

        for (int i = 0; i < chunkTokenCount; i++) {
          final tokenIndex = decodedTokens + i;
          batch.token[i] = tokens[tokenIndex];
          batch.pos[i] = tokenIndex;
          batch.n_seq_id[i] = 1;
          batch.seq_id[i][0] = 0;
          batch.logits[i] = 1;
        }

        final status = useEncoderPath
            ? _calls.encode(ctx.pointer, batch)
            : _calls.decode(ctx.pointer, batch);
        if (status != 0) {
          throw LlamaInferenceException('Embedding forward pass failed');
        }

        decodedTokens += chunkTokenCount;
      }

      Pointer<Float> embeddingPtr;
      if (poolingType == llama_pooling_type.LLAMA_POOLING_TYPE_NONE) {
        embeddingPtr = llama_get_embeddings_ith(
          ctx.pointer,
          batch.n_tokens - 1,
        );
        if (embeddingPtr == nullptr) {
          embeddingPtr = llama_get_embeddings(ctx.pointer);
        }
      } else {
        embeddingPtr = llama_get_embeddings_seq(ctx.pointer, 0);
        if (embeddingPtr == nullptr) {
          embeddingPtr = llama_get_embeddings(ctx.pointer);
        }
      }

      if (embeddingPtr == nullptr) {
        throw LlamaInferenceException('Embedding output is unavailable');
      }

      final vector = List<double>.from(
        embeddingPtr.asTypedList(embeddingSize),
        growable: false,
      );

      if (!normalize) {
        return vector;
      }

      return _normalizeEmbeddingVector(vector);
    } finally {
      llama_set_embeddings(ctx.pointer, false);
      _batchFree(batch);
    }
  }

  /// Generates embedding vectors for [texts] in input order.
  List<List<double>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  }) {
    if (texts.isEmpty) {
      return const <List<double>>[];
    }

    _ensureNoActiveTts(contextHandle, 'embed');
    final ctx = _contexts[contextHandle];
    ctx?.performanceAvailable = false;
    if (ctx == null) {
      throw Exception('Invalid context handle');
    }

    final modelHandle = _contextToModel[contextHandle];
    if (modelHandle == null) {
      throw Exception('Invalid context handle');
    }

    final model = _models[modelHandle];
    if (model == null) {
      throw Exception('Invalid model handle');
    }

    final contextParams = _contextParams[contextHandle];
    if (contextParams == null) {
      throw Exception('Missing context parameters');
    }
    _ensureContextUsable(contextHandle, ctx);
    _checkQwen35VulkanEmbedding(ctx);

    final hasEncoder = llama_model_has_encoder(model.pointer);
    final hasDecoder = llama_model_has_decoder(model.pointer);
    if (hasEncoder && hasDecoder) {
      throw LlamaUnsupportedException(_encoderDecoderEmbeddingsUnsupported);
    }
    final useEncoderPath = hasEncoder && !hasDecoder;

    final poolingType = llama_pooling_type$1(ctx.pointer);
    _checkEmbeddingPoolingType(poolingType);
    final maxParallelSequences = llama_n_seq_max(ctx.pointer);
    final vocab = llama_model_get_vocab(model.pointer);
    final nSeqCtx = llama_n_ctx_seq(ctx.pointer);
    final configuredBatchSize = contextParams.n_batch > 0
        ? contextParams.n_batch
        : llama_n_ctx(ctx.pointer);
    final passTokenLimit = _embeddingPassTokenLimit(
      modelHandle,
      ctx.pointer,
      useEncoderPath,
      poolingType,
    );
    final batchCapacity = math.max(
      1,
      passTokenLimit == null
          ? configuredBatchSize
          : math.min(configuredBatchSize, passTokenLimit),
    );
    final embeddingSize = _resolveEmbeddingDimension(model.pointer);

    final tokenizedInputs = <List<int>>[];
    for (final text in texts) {
      final tokens = _tokenizeEmbeddingText(vocab, text, nSeqCtx);
      _checkEmbeddingPassTokenLimit(tokens.length, passTokenLimit);
      tokenizedInputs.add(tokens);
    }

    _resetRequestPerformance(contextHandle, ctx);

    if (poolingType == llama_pooling_type.LLAMA_POOLING_TYPE_NONE ||
        maxParallelSequences <= 1) {
      final fallbackVectors = <List<double>>[];
      for (final text in texts) {
        fallbackVectors.add(
          _embed(
            contextHandle,
            text,
            normalize: normalize,
            resetPerformance: false,
          ),
        );
      }
      return fallbackVectors;
    }

    final vectors = List<List<double>?>.filled(texts.length, null);

    int index = 0;
    while (index < texts.length) {
      final currentTokenCount = tokenizedInputs[index].length;

      if (currentTokenCount > batchCapacity) {
        vectors[index] = _embed(
          contextHandle,
          texts[index],
          normalize: normalize,
          resetPerformance: false,
        );
        index += 1;
        continue;
      }

      var groupTokenCount = 0;
      final groupStart = index;
      while (index < texts.length &&
          (index - groupStart) < maxParallelSequences) {
        final nextCount = tokenizedInputs[index].length;
        if (nextCount > batchCapacity) {
          break;
        }

        final nextTotal = groupTokenCount + nextCount;
        if (groupTokenCount > 0 && nextTotal > batchCapacity) {
          break;
        }

        groupTokenCount = nextTotal;
        index += 1;
      }

      if (groupStart == index) {
        vectors[index] = _embed(
          contextHandle,
          texts[index],
          normalize: normalize,
          resetPerformance: false,
        );
        index += 1;
        continue;
      }

      final groupSize = index - groupStart;
      final batch = _batchInit(groupTokenCount, 0, groupSize);
      try {
        _calls.synchronize(ctx.pointer);
        _clearContextMemory(ctx.pointer, strict: false);
        ctx.cachedPromptTokens = null;
        llama_set_embeddings(ctx.pointer, true);

        batch.n_tokens = groupTokenCount;

        var tokenOffset = 0;
        for (int sequence = 0; sequence < groupSize; sequence++) {
          final tokens = tokenizedInputs[groupStart + sequence];
          for (int pos = 0; pos < tokens.length; pos++) {
            batch.token[tokenOffset] = tokens[pos];
            batch.pos[tokenOffset] = pos;
            batch.n_seq_id[tokenOffset] = 1;
            batch.seq_id[tokenOffset][0] = sequence;
            batch.logits[tokenOffset] = 1;
            tokenOffset += 1;
          }
        }

        final status = useEncoderPath
            ? _calls.encode(ctx.pointer, batch)
            : _calls.decode(ctx.pointer, batch);
        if (status != 0) {
          throw LlamaInferenceException('Batch embedding forward pass failed');
        }

        for (int sequence = 0; sequence < groupSize; sequence++) {
          var embeddingPtr = llama_get_embeddings_seq(ctx.pointer, sequence);
          if (embeddingPtr == nullptr && groupSize == 1) {
            embeddingPtr = llama_get_embeddings(ctx.pointer);
          }
          if (embeddingPtr == nullptr) {
            throw LlamaInferenceException(
              'Batch embedding output is unavailable',
            );
          }

          final vector = List<double>.from(
            embeddingPtr.asTypedList(embeddingSize),
            growable: false,
          );
          vectors[groupStart + sequence] = normalize
              ? _normalizeEmbeddingVector(vector)
              : vector;
        }
      } finally {
        llama_set_embeddings(ctx.pointer, false);
        _batchFree(batch);
      }
    }

    return vectors.map((vector) => vector!).toList(growable: false);
  }

  bool _embeddingAddsSpecial(Pointer<llama_vocab> vocab, String text) =>
      !_promptStartsWithBosToken(vocab, text);

  List<int> _tokenizeEmbeddingText(
    Pointer<llama_vocab> vocab,
    String text,
    int maxTokens,
  ) {
    final shouldAddSpecial = _embeddingAddsSpecial(vocab, text);
    final (textPtr, textLength) = _toNativeUtf8WithLength(text);

    final int requiredTokenCount;
    try {
      requiredTokenCount = -_calls.tokenize(
        vocab,
        textPtr.cast(),
        textLength,
        nullptr,
        0,
        shouldAddSpecial,
        true,
      );
    } catch (_) {
      malloc.free(textPtr);
      rethrow;
    }

    if (requiredTokenCount <= 0) {
      malloc.free(textPtr);
      throw LlamaInferenceException(
        'Failed to tokenize embedding input: it produced no tokens.',
      );
    }
    if (requiredTokenCount > maxTokens) {
      malloc.free(textPtr);
      throw LlamaEmbeddingInputTooLongException(
        'The embedding input has $requiredTokenCount tokens, but the context '
        'holds at most $maxTokens tokens per sequence. Shorten the input or '
        'raise ModelParams.contextSize; with ModelParams.kvUnified false, the '
        'context is split across ModelParams.maxParallelSequences.',
        maxInputTokens: maxTokens,
        actualTokens: requiredTokenCount,
      );
    }

    final tokensPtr = malloc<Int32>(requiredTokenCount);
    try {
      final actualTokenCount = _calls.tokenize(
        vocab,
        textPtr.cast(),
        textLength,
        tokensPtr,
        requiredTokenCount,
        shouldAddSpecial,
        true,
      );
      if (actualTokenCount <= 0 || actualTokenCount > maxTokens) {
        throw LlamaInferenceException('Failed to encode embedding input');
      }

      return List<int>.from(tokensPtr.asTypedList(actualTokenCount));
    } finally {
      malloc.free(tokensPtr);
      malloc.free(textPtr);
    }
  }

  void _checkEmbeddingPoolingType(llama_pooling_type poolingType) {
    if (poolingType == llama_pooling_type.LLAMA_POOLING_TYPE_RANK) {
      throw LlamaUnsupportedException(
        'Embeddings are not supported for rank-pooled models such as '
        'rerankers: llama.cpp returns classifier scores, not an embedding, '
        'for pooling type RANK. Reranking is tracked in '
        'https://github.com/leehack/llamadart/issues/323.',
      );
    }
  }

  int? _embeddingPassTokenLimit(
    int modelHandle,
    Pointer<llama_context> contextPointer,
    bool useEncoderPath,
    llama_pooling_type poolingType,
  ) {
    // MEAN/CLS pooling overwrites the sequence embedding per micro-batch;
    // non-causal attention needs all prompt tokens in the same forward pass.
    if (useEncoderPath ||
        llama_get_memory(contextPointer) == nullptr ||
        poolingType == llama_pooling_type.LLAMA_POOLING_TYPE_MEAN ||
        poolingType == llama_pooling_type.LLAMA_POOLING_TYPE_CLS ||
        !_embeddingModelHasCausalAttention(modelHandle)) {
      return llama_n_ubatch(contextPointer);
    }
    return null;
  }

  bool _embeddingModelHasCausalAttention(
    int modelHandle, {
    bool Function(Pointer<llama_model>)? diffusionProbe,
  }) {
    try {
      if ((diffusionProbe ?? llama_model_is_diffusion)(
        _models[modelHandle]!.pointer,
      )) {
        return false;
      }
    } on Object {
      throw LlamaUnsupportedException(
        'Cannot verify causal attention for native embeddings: the runtime '
        'does not expose the required llama_model_is_diffusion probe. '
        'Use the pinned native runtime or a compatible version before decoding.',
      );
    }
    final metadata = getMetadata(modelHandle);
    final architecture = metadata['general.architecture'];
    if (architecture == null || architecture.isEmpty) {
      throw LlamaUnsupportedException(
        'Cannot verify causal attention for native embeddings: the runtime '
        'did not report general.architecture model metadata. Use a runtime '
        'that exposes embedding model metadata before decoding.',
      );
    }
    // llama.cpp v0.6.0 (d8123504) forces this non-diffusion architecture's
    // attention to non-causal after loading the optional metadata override.
    if (architecture == 'gemma-embedding') return false;
    final causal = metadata['$architecture.attention.causal'];
    // The other models in the pinned loader default causal_attn to true when
    // this optional boolean key is absent. Context creation keeps that value.
    return switch (causal) {
      null || 'true' => true,
      'false' => false,
      _ => throw LlamaUnsupportedException(
        'Cannot verify causal attention for native embeddings: the runtime '
        'reported invalid attention.causal model metadata. Use a runtime '
        'that reports a boolean attention mode before decoding.',
      ),
    };
  }

  void _checkEmbeddingPassTokenLimit(int tokenCount, int? passTokenLimit) {
    if (passTokenLimit != null && tokenCount > passTokenLimit) {
      throw LlamaEmbeddingInputTooLongException(
        'The embedding input has $tokenCount tokens, but this model '
        'embeds its input in one pass of at most $passTokenLimit tokens '
        '(n_ubatch). Shorten the input or raise ModelParams.microBatchSize '
        'and ModelParams.batchSize.',
        maxInputTokens: passTokenLimit,
        actualTokens: tokenCount,
      );
    }
  }

  int _resolveEmbeddingDimension(Pointer<llama_model> modelPointer) {
    var embeddingSize = llama_model_n_embd_out(modelPointer);
    if (embeddingSize <= 0) {
      embeddingSize = llama_model_n_embd(modelPointer);
    }
    if (embeddingSize <= 0) {
      throw LlamaInferenceException('Failed to resolve embedding dimension');
    }
    return embeddingSize;
  }

  List<double> _normalizeEmbeddingVector(List<double> vector) {
    var normSquared = 0.0;
    for (final value in vector) {
      normSquared += value * value;
    }

    if (normSquared <= 0.0) {
      return vector;
    }

    final scale = 1.0 / math.sqrt(normSquared);
    final normalized = List<double>.filled(vector.length, 0.0, growable: false);
    for (int i = 0; i < vector.length; i++) {
      normalized[i] = vector[i] * scale;
    }
    return normalized;
  }

  // Native counters and Dart timing fallbacks must share a request boundary.
  void _resetRequestPerformance(int contextHandle, _LlamaContextWrapper ctx) {
    ctx.resetLastPerf();
    llama_perf_context_reset(ctx.pointer);
    final sampler = _samplers[contextHandle];
    if (sampler != null) llama_perf_sampler_reset(sampler);
    ctx.performanceAvailable = true;
  }

  /// Helper: Resets the context state to be ready for new generation.
  _LlamaContextWrapper _resetContext(
    int contextHandle,
    _LlamaContextWrapper ctx, {
    required bool clearMemory,
  }) {
    _calls.synchronize(ctx.pointer);

    if (clearMemory) {
      _clearContextMemory(ctx.pointer);
      ctx.cachedPromptTokens = null;
    }

    _contexts[contextHandle] = ctx;
    return ctx;
  }

  void _clearContextMemory(
    Pointer<llama_context> contextPointer, {
    bool strict = true,
  }) {
    final memory = llama_get_memory(contextPointer);
    if (memory == nullptr) {
      if (strict) {
        throw Exception("Failed to reset context memory");
      }
      return;
    }

    _calls.memoryClear(contextPointer, memory, true);
  }

  /// Ingests the prompt (text or multimodal).
  ///
  /// Returns the next KV position, how many prompt ids were written to
  /// `tokensPtr`, and how many prompt tokens were evaluated, media tokens
  /// included. Multimodal ingestion writes no ids, and its positions can be
  /// fewer than its tokens. A prompt cancelled through `cancelToken` reports
  /// only the tokens decoded before the cancel.
  ({int nPast, int promptTokenCount, int evaluatedPromptTokens}) _ingestPrompt(
    int contextHandle,
    int modelHandle,
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart>? parts,
    Pointer<Int32> tokensPtr,
    int nCtx,
    llama_context_params modelParams, {
    required String? chatMediaMarker,
    required bool allowTextPromptReuse,
    required Pointer<llama_dart_speculative> speculativeSession,
    required _SpeculativeApi? speculativeApi,
    required _LlamaCppSpeculativeConfig? speculativeConfig,
    required Pointer<Int8> cancelToken,
  }) {
    final mediaParts =
        parts
            ?.where((p) => p is LlamaImageContent || p is LlamaAudioContent)
            .toList() ??
        [];
    final mmHandle = _modelToMtmd[modelHandle];
    final mmCtx = mmHandle != null ? _mtmdContexts[mmHandle] : null;

    if (mediaParts.isNotEmpty && mmCtx != null) {
      final (:nPast, :evaluatedTokens) = _ingestMultimodalPrompt(
        mmCtx,
        ctx,
        vocab,
        prompt,
        mediaParts,
        modelParams,
        cancelToken,
        chatMediaMarker: chatMediaMarker,
      );
      return (
        nPast: nPast,
        promptTokenCount: 0,
        evaluatedPromptTokens: evaluatedTokens,
      );
    } else {
      final nTokens = _ingestTextPrompt(
        batch,
        vocab,
        prompt,
        tokensPtr,
        nCtx,
        ctx,
        maxBatchTokens: modelParams.n_batch,
        allowPromptReuse: allowTextPromptReuse,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
        isCancelled: () => cancelToken.value == 1,
      );
      return (
        nPast: nTokens,
        promptTokenCount: nTokens,
        evaluatedPromptTokens: nTokens,
      );
    }
  }

  /// Without chunk-level mtmd functions, [evaluatedTokens] falls back to the
  /// positions, as no token count is reachable.
  ({int nPast, int evaluatedTokens}) _ingestMultimodalPrompt(
    Pointer<mtmd_context> mmCtx,
    _LlamaContextWrapper ctx,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart> mediaParts,
    llama_context_params modelParams,
    Pointer<Int8> cancelToken, {
    required String? chatMediaMarker,
    Allocator allocator = calloc,
  }) {
    _calls.failures.ensureUsable(mmCtx, 'This multimodal projector');
    int initialTokens = 0;
    int? evaluatedTokens;
    // Zeroed, so the cleanup of a part that failed skips the slots after it.
    final bitmaps = allocator<Pointer<mtmd_bitmap>>(mediaParts.length);
    Pointer<mtmd_input_chunks> chunks = nullptr;
    Pointer<mtmd_input_text> inputText = nullptr;
    Pointer<Utf8> promptPtr = nullptr;

    try {
      chunks = _mtmdInputChunksInit();
      for (int i = 0; i < mediaParts.length; i++) {
        final p = mediaParts[i];
        if (p is LlamaImageContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8(allocator: allocator);
            try {
              bitmaps[i] = _mtmdHelperBitmapInitFromFile(mmCtx, pathPtr.cast());
            } finally {
              allocator.free(pathPtr);
            }
          } else if (p.bytes != null) {
            final dataPtr = allocator<Uint8>(p.bytes!.length);
            try {
              dataPtr.asTypedList(p.bytes!.length).setAll(0, p.bytes!);
              bitmaps[i] = _mtmdHelperBitmapInitFromBuf(
                mmCtx,
                dataPtr.cast(),
                p.bytes!.length,
              );
            } finally {
              allocator.free(dataPtr);
            }
          }
        } else if (p is LlamaAudioContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8(allocator: allocator);
            try {
              bitmaps[i] = _mtmdHelperBitmapInitFromFile(mmCtx, pathPtr.cast());
            } finally {
              allocator.free(pathPtr);
            }
          } else if (p.bytes != null) {
            final dataPtr = allocator<Uint8>(p.bytes!.length);
            try {
              dataPtr.asTypedList(p.bytes!.length).setAll(0, p.bytes!);
              bitmaps[i] = _mtmdHelperBitmapInitFromBuf(
                mmCtx,
                dataPtr.cast(),
                p.bytes!.length,
              );
            } finally {
              allocator.free(dataPtr);
            }
          } else if (p.samples != null) {
            final dataPtr = allocator<Float>(p.samples!.length);
            try {
              dataPtr.asTypedList(p.samples!.length).setAll(0, p.samples!);
              bitmaps[i] = _mtmdBitmapInitFromAudio(
                p.samples!.length,
                dataPtr.cast(),
              );
            } finally {
              allocator.free(dataPtr);
            }
          }
        }

        if (bitmaps[i] == nullptr) {
          _calls.failures.throwIfCaught(
            'the mtmd bitmap constructor',
            LlamaInferenceException.new,
            windowsFreeOnly: [mmCtx],
          );
          throw _missingEncoderFor(mmCtx, [p]) ??
              Exception("Failed to load media part $i");
        }
      }

      inputText = allocator<mtmd_input_text>();
      final normalizedPrompt = _normalizeMtmdPromptMarkers(
        prompt,
        mediaParts.length,
        chatMediaMarker: chatMediaMarker,
      );
      promptPtr = normalizedPrompt.toNativeUtf8(allocator: allocator);
      inputText.ref.text = promptPtr.cast();
      inputText.ref.text_len = utf8.encode(normalizedPrompt).length;

      final bos = llama_vocab_bos(vocab);
      final eos = llama_vocab_eos(vocab);
      final shouldAddSpecial =
          (bos != eos && bos != -1) &&
          !_promptStartsWithBosToken(vocab, normalizedPrompt);
      inputText.ref.add_special = shouldAddSpecial;
      inputText.ref.parse_special = true;

      final res = _mtmdTokenize(
        mmCtx,
        chunks,
        inputText,
        bitmaps.cast(),
        mediaParts.length,
      );

      if (res == 0) {
        final newPast = allocator<llama_pos>();
        try {
          final unguardedChunkEvalApi = _mtmdPrimarySymbolsUnavailable
              ? _resolveMtmdFallbackApi()?.chunkEval
              : MtmdChunkEvalApi.primary;
          final exitTeardown = _mtmdExitTeardown;
          final chunkEvalApi = exitTeardown == null
              ? unguardedChunkEvalApi
              : unguardedChunkEvalApi?.withExitTeardown(exitTeardown);
          final int evalResult;
          MtmdChunkEvalFailure? chunkFailure;
          if (chunkEvalApi == null) {
            evalResult = _mtmdHelperEvalChunks(
              mmCtx,
              ctx.pointer,
              chunks,
              0,
              0,
              modelParams.n_batch,
              true,
              newPast,
            );
          } else {
            _checkNonCausalMediaChunks(
              chunkEvalApi,
              mmCtx,
              chunks,
              batchTokens: modelParams.n_batch,
              microBatchTokens: llama_n_ubatch(ctx.pointer),
            );
            chunkFailure = evalMtmdChunksUntilCancelled(
              chunkEvalApi,
              mmCtx,
              ctx.pointer,
              chunks,
              modelParams.n_batch,
              newPast,
              cancelToken,
              onChunkEvaluated: (tokens) =>
                  evaluatedTokens = (evaluatedTokens ?? 0) + tokens,
            );
            evalResult = chunkFailure?.result ?? 0;
            if (evalResult == _nativeStatusException) {
              _calls.failures.throwIfCaught(
                'the mtmd chunk evaluation ($chunkFailure)',
                LlamaInferenceException.new,
                freeOnly: [mmCtx, ctx.pointer],
              );
            }
          }
          if (evalResult == 0) {
            // The tracked mtmd evaluations wait for the backend, as the
            // object calls' decode does; upstream libmtmd returns before an
            // asynchronous one has finished.
            if (exitTeardown == null) _calls.synchronize(ctx.pointer);
            initialTokens = newPast.value;
          } else {
            throw Exception(
              'Multimodal prompt evaluation failed: $evalResult'
              '${chunkFailure == null ? '' : ' ($chunkFailure)'}. '
              'The active context window may be too small for this image and conversation history.',
            );
          }
        } finally {
          allocator.free(newPast);
        }
      } else {
        throw _missingEncoderFor(mmCtx, mediaParts) ??
            Exception("mtmd_tokenize failed: $res");
      }
    } finally {
      // Free in finally so a tokenize/eval failure above does not leak the
      // prompt buffer or the input-text struct.
      if (promptPtr != nullptr) allocator.free(promptPtr);
      if (inputText != nullptr) allocator.free(inputText);
      for (int i = 0; i < mediaParts.length; i++) {
        if (bitmaps[i] != nullptr) _mtmdBitmapFree(bitmaps[i]);
      }
      allocator.free(bitmaps);
      if (chunks != nullptr) _mtmdInputChunksFree(chunks);
    }
    ctx.cachedPromptTokens = null;
    return (
      nPast: initialTokens,
      evaluatedTokens: evaluatedTokens ?? initialTokens,
    );
  }

  /// Rejects a prompt whose non-causal media chunk llama.cpp would abort on.
  ///
  /// `mtmd_helper_decode_image_chunk` decodes such a chunk in pieces of
  /// [batchTokens], the `n_batch` it is given, and `llama_context::decode`
  /// aborts on a non-causal piece above [microBatchTokens]. With the two
  /// equal the pieces pass, and the chunk is decoded in several non-causal
  /// batches, which is logged.
  void _checkNonCausalMediaChunks(
    MtmdChunkEvalApi api,
    Pointer<mtmd_context> mmCtx,
    Pointer<mtmd_input_chunks> chunks, {
    required int batchTokens,
    required int microBatchTokens,
  }) {
    final chunk = findMtmdChunkAboveMicroBatch(
      api,
      mmCtx,
      chunks,
      microBatchTokens,
    );
    if (chunk == null) return;
    final media = mtmdMediaChunkName(chunk.chunkType);
    if (batchTokens <= microBatchTokens) {
      LlamaLogger.instance.warning(
        'llama_cpp_service: the $media input has ${chunk.tokenCount} tokens, '
        'more than the context\'s micro-batch of $microBatchTokens tokens '
        '(n_ubatch), so it is decoded in several non-causal batches, which '
        'can reduce accuracy. Load the model with '
        'ModelParams.microBatchSize and ModelParams.batchSize of at least '
        '${chunk.tokenCount} to decode it in one.',
      );
      return;
    }
    throw LlamaInferenceException(
      'The $media input has ${chunk.tokenCount} tokens, more than the '
      'context\'s micro-batch of $microBatchTokens tokens (n_ubatch), and '
      'this projector decodes it with non-causal attention, which llama.cpp '
      'cannot split across micro-batches. Raise ModelParams.microBatchSize '
      'to at least ${chunk.tokenCount}, and ModelParams.batchSize with it, '
      'or pass a smaller $media if the projector sizes its output by the '
      'input.',
    );
  }

  void _ensureLogitsAvailableAfterPromptEval(Pointer<llama_context> ctx) {
    if (llama_get_logits(ctx) != nullptr) {
      return;
    }

    throw Exception(
      'Prompt evaluation produced no logits for sampling. '
      'The active context window may be too small for this prompt or multimodal decode failed.',
    );
  }

  String _normalizeMtmdPromptMarkers(
    String prompt,
    int mediaPartCount, {
    required String? chatMediaMarker,
  }) {
    final markerPtr = _mtmdDefaultMarker();
    final marker = markerPtr == nullptr
        ? '<__media__>'
        : markerPtr.cast<Utf8>().toDartString();

    // The projector splits a prompt on its marker wherever it is. Its helper
    // for speech output writes the default marker itself, so the projector
    // cannot be given another one.
    var normalized = chatMediaMarker == null
        ? normalizeMediaPlaceholders(prompt, marker: marker)
        : chatPromptForMarkerRuntime(
            prompt,
            chatMarker: chatMediaMarker,
            marker: marker,
            runtimePlaceholders: marker,
          );

    if (mediaPartCount <= 0) {
      return normalized;
    }

    final markerCount = _countOccurrences(normalized, marker);
    if (markerCount < mediaPartCount) {
      final missing = mediaPartCount - markerCount;
      final markerBlock = List.filled(missing, marker).join(' ');

      if (normalized.contains('User:')) {
        normalized = normalized.replaceFirst('User:', 'User: $markerBlock ');
      } else if (normalized.contains('user:')) {
        normalized = normalized.replaceFirst('user:', 'user: $markerBlock ');
      } else {
        normalized = '$markerBlock\n$normalized';
      }
    }

    return normalized;
  }

  int _countOccurrences(String text, String pattern) {
    if (pattern.isEmpty) {
      return 0;
    }

    int count = 0;
    int start = 0;
    while (true) {
      final index = text.indexOf(pattern, start);
      if (index == -1) {
        break;
      }
      count++;
      start = index + pattern.length;
    }
    return count;
  }

  bool _promptStartsWithBosToken(Pointer<llama_vocab> vocab, String prompt) {
    final bos = llama_vocab_bos(vocab);
    if (bos < 0) {
      return false;
    }

    final bosPtr = llama_token_get_text(vocab, bos);
    if (bosPtr == nullptr) {
      return false;
    }

    final bosToken = bosPtr.cast<Utf8>().toDartString();
    if (bosToken.isEmpty) {
      return false;
    }

    return prompt.trimLeft().startsWith(bosToken);
  }

  int _ingestTextPrompt(
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    Pointer<Int32> tokensPtr,
    int nCtx,
    _LlamaContextWrapper ctx, {
    required int maxBatchTokens,
    required bool allowPromptReuse,
    required Pointer<llama_dart_speculative> speculativeSession,
    required _SpeculativeApi? speculativeApi,
    required _LlamaCppSpeculativeConfig? speculativeConfig,
    required bool Function() isCancelled,
  }) {
    final (promptPtr, promptLength) = _toNativeUtf8WithLength(prompt);
    final shouldAddSpecial = !_promptStartsWithBosToken(vocab, prompt);
    final int nTokens;
    try {
      nTokens = _calls.tokenize(
        vocab,
        promptPtr.cast(),
        promptLength,
        tokensPtr,
        nCtx,
        shouldAddSpecial,
        true,
      );
    } finally {
      malloc.free(promptPtr);
    }

    if (nTokens < 0 || nTokens > nCtx) {
      throw Exception("Tokenization failed or prompt too long");
    }

    if (!allowPromptReuse || nTokens == 0) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
        isCancelled: isCancelled,
      );
    }

    final cachedTokens = ctx.cachedPromptTokens;
    if (cachedTokens == null || cachedTokens.isEmpty) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
        isCancelled: isCancelled,
      );
    }

    final reusedPrefix = _sharedPrefixLength(cachedTokens, tokensPtr, nTokens);

    // Loaded KV holds no live logits; re-decode only the final token. Gated
    // on kvFromStateLoad so the in-process reuse path stays bit-exact against
    // a cleared baseline (parity property).
    final exactStateLoadMatch =
        ctx.kvFromStateLoad &&
        reusedPrefix == nTokens &&
        cachedTokens.length == nTokens;

    if (reusedPrefix <= 0 ||
        (reusedPrefix >= nTokens && !exactStateLoadMatch)) {
      final canReuseCachedCopy =
          reusedPrefix == nTokens && cachedTokens.length == nTokens;
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        existingCachedTokens: canReuseCachedCopy ? cachedTokens : null,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
        isCancelled: isCancelled,
      );
    }

    final memory = llama_get_memory(ctx.pointer);
    if (memory == nullptr) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
        isCancelled: isCancelled,
      );
    }

    final decodeStart = exactStateLoadMatch ? nTokens - 1 : reusedPrefix;

    final maxSeqPos = llama_memory_seq_pos_max(memory, 0);
    final removeTo = maxSeqPos >= decodeStart ? maxSeqPos + 1 : decodeStart;
    ctx.cachedPromptTokens = null;
    ctx.kvFromStateLoad = false;
    final removedTail = llama_memory_seq_rm(memory, 0, decodeStart, removeTo);
    if (!removedTail) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
        isCancelled: isCancelled,
      );
    }

    ctx.lastPerfCachedPromptTokens = decodeStart;
    final suffixTokenCount = nTokens - decodeStart;
    final decodedEnd =
        decodeStart +
        _decodePromptSegment(
          batch,
          tokensPtr,
          ctx,
          startTokenIndex: decodeStart,
          tokenCount: suffixTokenCount,
          maxBatchTokens: maxBatchTokens,
          outputAllLogits: speculativeSession != nullptr,
          speculativeSession: speculativeSession,
          speculativeApi: speculativeApi,
          speculativeConfig: speculativeConfig,
          isCancelled: isCancelled,
        );

    ctx.cachedPromptTokens = exactStateLoadMatch && decodedEnd == nTokens
        ? cachedTokens
        : _copyPromptTokens(tokensPtr, decodedEnd);
    ctx.kvFromStateLoad = false;

    return decodedEnd;
  }

  int _decodeAndCacheFullPrompt(
    llama_batch batch,
    Pointer<Int32> tokensPtr,
    _LlamaContextWrapper ctx,
    int nTokens, {
    required int maxBatchTokens,
    List<int>? existingCachedTokens,
    bool outputAllLogits = false,
    Pointer<llama_dart_speculative>? speculativeSession,
    _SpeculativeApi? speculativeApi,
    _LlamaCppSpeculativeConfig? speculativeConfig,
    required bool Function() isCancelled,
  }) {
    ctx.cachedPromptTokens = null;
    ctx.kvFromStateLoad = false;
    _clearContextMemory(ctx.pointer);
    final decoded = _decodePromptSegment(
      batch,
      tokensPtr,
      ctx,
      startTokenIndex: 0,
      tokenCount: nTokens,
      maxBatchTokens: maxBatchTokens,
      outputAllLogits: outputAllLogits,
      speculativeSession: speculativeSession,
      speculativeApi: speculativeApi,
      speculativeConfig: speculativeConfig,
      isCancelled: isCancelled,
    );
    ctx.cachedPromptTokens = decoded == nTokens && existingCachedTokens != null
        ? existingCachedTokens
        : _copyPromptTokens(tokensPtr, decoded);
    ctx.kvFromStateLoad = false;
    return decoded;
  }

  List<int> _copyPromptTokens(Pointer<Int32> tokensPtr, int tokenCount) {
    if (tokenCount <= 0) {
      return const <int>[];
    }
    return List<int>.from(tokensPtr.asTypedList(tokenCount), growable: false);
  }

  /// Decodes [tokenCount] prompt tokens from [startTokenIndex] and returns
  /// how many were decoded before [isCancelled] reported a cancel.
  ///
  /// [isCancelled] is read before each `llama_decode` call. Without a
  /// speculative session, each [maxBatchTokens] chunk is decoded in calls of
  /// at most `n_ubatch` tokens, the size llama.cpp splits a larger call into.
  /// A speculative session processes each call's batch, so it gets each chunk
  /// in one call. Either way a call takes at most the context's
  /// `promptMicroBatchLimit` tokens when it has one.
  int _decodePromptSegment(
    llama_batch batch,
    Pointer<Int32> tokensPtr,
    _LlamaContextWrapper ctx, {
    required int startTokenIndex,
    required int tokenCount,
    required int maxBatchTokens,
    bool outputAllLogits = false,
    Pointer<llama_dart_speculative>? speculativeSession,
    _SpeculativeApi? speculativeApi,
    _LlamaCppSpeculativeConfig? speculativeConfig,
    required bool Function() isCancelled,
  }) {
    if (tokenCount <= 0) {
      return 0;
    }

    final effectiveBatchTokens = maxBatchTokens > 0
        ? maxBatchTokens
        : tokenCount;
    final hasSpeculativeSession =
        speculativeSession != null && speculativeSession != nullptr;
    final microBatchLimit = ctx.promptMicroBatchLimit;
    final uncappedCallTokens = hasSpeculativeSession
        ? effectiveBatchTokens
        : llama_n_ubatch(ctx.pointer);
    final callTokens = microBatchLimit == null
        ? uncappedCallTokens
        : math.min(uncappedCallTokens, microBatchLimit);
    var decoded = 0;

    while (decoded < tokenCount) {
      if (isCancelled()) {
        break;
      }
      final chunkTokenCount = math.min(
        math.min(
          callTokens,
          effectiveBatchTokens - decoded % effectiveBatchTokens,
        ),
        tokenCount - decoded,
      );
      batch.n_tokens = chunkTokenCount;

      for (int i = 0; i < chunkTokenCount; i++) {
        final tokenIndex = startTokenIndex + decoded + i;
        batch.token[i] = tokensPtr[tokenIndex];
        batch.pos[i] = tokenIndex;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        final isLastTokenInPrompt = decoded + i == tokenCount - 1;
        batch.logits[i] = outputAllLogits || isLastTokenInPrompt ? 1 : 0;
      }

      if (_calls.decode(ctx.pointer, batch) != 0) {
        throw Exception("Initial decode failed");
      }
      if (hasSpeculativeSession &&
          !_processSpeculativeBatch(
            speculativeApi!,
            speculativeSession,
            batch,
            speculativeConfig,
            ctx.pointer,
          )) {
        throw Exception("Speculative prompt decode processing failed");
      }

      decoded += chunkTokenCount;
    }
    return decoded;
  }

  bool _processSpeculativeBatch(
    _SpeculativeApi speculativeApi,
    Pointer<llama_dart_speculative> speculativeSession,
    llama_batch batch,
    _LlamaCppSpeculativeConfig? speculativeConfig,
    Pointer<llama_context> context,
  ) {
    final processed = _withSuppressedBatchLogits(
      batch.logits,
      batch.n_tokens,
      speculativeConfig?.suppressDraftProcessLogits == true,
      () => speculativeApi.processBatch(speculativeSession, batch),
    );
    if (!processed) {
      _throwIfSpeculativeCaught(
        'llama_dart_speculative_process_batch',
        context,
      );
    }
    return processed;
  }

  // Speculative state is built on the target context, so a call on it that
  // caught an exception leaves that context free-only too.
  void _throwIfSpeculativeCaught(String call, Pointer<llama_context> context) {
    _calls.failures.throwIfCaught(
      call,
      LlamaInferenceException.new,
      freeOnly: [context],
    );
  }

  static T _withSuppressedBatchLogits<T>(
    Pointer<Int8> logits,
    int tokenCount,
    bool suppress,
    T Function() action,
  ) {
    if (!suppress || logits == nullptr || tokenCount <= 0) {
      return action();
    }

    final logitView = logits.asTypedList(tokenCount);
    final previousLogits = List<int>.of(logitView, growable: false);
    try {
      logitView.fillRange(0, tokenCount, 0);
      return action();
    } finally {
      logitView.setAll(0, previousLogits);
    }
  }

  int _sharedPrefixLength(
    List<int> cachedTokens,
    Pointer<Int32> newTokens,
    int newTokenCount,
  ) {
    final maxLength = cachedTokens.length < newTokenCount
        ? cachedTokens.length
        : newTokenCount;
    int i = 0;
    while (i < maxLength && cachedTokens[i] == newTokens[i]) {
      i++;
    }
    return i;
  }

  void _holdSamplerChain(Pointer<llama_sampler> chain) =>
      IsolateShutdownReleases.current.hold(
        ShutdownStage.session,
        _samplerFreeAddress,
        chain,
      );

  void _freeSamplerChain(Pointer<llama_sampler> chain) {
    IsolateShutdownReleases.current.release(chain);
    llama_sampler_free(chain);
  }

  /// Helper: Initializes the sampler chain.
  Pointer<llama_sampler> _initializeSampler(
    GenerationParams params,
    Pointer<llama_vocab> vocab,
    int vocabSize,
    List<int> suppressedTokens,
    Pointer<Utf8> grammarPtr,
    Pointer<Utf8> rootPtr,
    _LazyGrammarConfig? lazyGrammarConfig,
    _LlamaCppThinkingBudgetConfig? thinkingBudgetConfig,
    _ReasoningBudgetApi? reasoningBudgetApi,
    int promptTokenCount,
    Pointer<Int32> tokensPtr,
    bool countPromptTokensInPenalties,
  ) {
    final sampler = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );
    _holdSamplerChain(sampler);

    final penaltyConfig = _resolvePenaltySamplerConfig(params);
    final penaltiesSampler = llama_sampler_init_penalties(
      vocabSize,
      penaltyConfig.lastN,
      penaltyConfig.repeat,
      penaltyConfig.frequency,
      penaltyConfig.presence,
    );
    llama_sampler_chain_add(sampler, penaltiesSampler);

    if (suppressedTokens.isNotEmpty) {
      final suppressSampler = createSuppressTokensSampler(
        vocabSize,
        suppressedTokens,
      );
      if (suppressSampler == nullptr) {
        _freeSamplerChain(sampler);
        throw LlamaInferenceException(
          'llama.cpp failed to initialize model-specific suppressed tokens.',
        );
      }
      llama_sampler_chain_add(sampler, suppressSampler);
    }

    Pointer<llama_sampler> grammarSampler = nullptr;
    final useLazyGrammar = params.grammarLazy && lazyGrammarConfig != null;
    if (grammarPtr != nullptr) {
      if (useLazyGrammar) {
        try {
          grammarSampler = _calls.samplerInitGrammarLazyPatterns(
            vocab,
            grammarPtr.cast(),
            rootPtr.cast(),
            lazyGrammarConfig.triggerPatterns,
            lazyGrammarConfig.numTriggerPatterns,
            lazyGrammarConfig.triggerTokens,
            lazyGrammarConfig.numTriggerTokens,
          );
        } on LlamaException {
          _freeSamplerChain(sampler);
          rethrow;
        }
      } else {
        grammarSampler = llama_sampler_init_grammar(
          vocab,
          grammarPtr.cast(),
          rootPtr.cast(),
        );
      }
    }
    if (grammarPtr != nullptr && grammarSampler == nullptr) {
      _freeSamplerChain(sampler);
      throw LlamaInferenceException(
        'llama.cpp failed to initialize the requested grammar sampler.',
      );
    }

    if (thinkingBudgetConfig != null) {
      final api = reasoningBudgetApi;
      if (api == null) {
        if (grammarSampler != nullptr) {
          llama_sampler_free(grammarSampler);
        }
        _freeSamplerChain(sampler);
        throw StateError('Missing llama.cpp reasoning-budget sampler API.');
      }
      final budgetSampler = api.initSampler(
        vocab: vocab,
        config: thinkingBudgetConfig,
        pauseGrammarDuringReasoning: grammarSampler != nullptr,
        grammarSampler: grammarSampler,
        promptTokens: tokensPtr,
        promptTokenCount: promptTokenCount,
      );
      if (budgetSampler == nullptr) {
        if (grammarSampler != nullptr) {
          llama_sampler_free(grammarSampler);
        }
        _freeSamplerChain(sampler);
        _calls.failures.throwIfCaught(
          'llama_dart_sampler_init_reasoning_budget',
          LlamaInferenceException.new,
          windowsFreeOnly: [vocab],
        );
        throw LlamaUnsupportedException(
          'llama.cpp could not initialize thinking-budget control. Verify '
          'that the configured thinking tags are supported by the loaded '
          'model vocabulary.',
        );
      }
      // The native composite sampler owns grammarSampler after this point.
      grammarSampler = nullptr;
      llama_sampler_chain_add(sampler, budgetSampler);
    } else if (grammarSampler != nullptr) {
      llama_sampler_chain_add(sampler, grammarSampler);
    }

    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(params.topK));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params.topP, 1));
    if (params.minP > 0) {
      llama_sampler_chain_add(
        sampler,
        llama_sampler_init_min_p(params.minP, 1),
      );
    }
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(params.temp));

    if (params.temp <= 0) {
      llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    } else {
      final seed = params.seed ?? DateTime.now().millisecondsSinceEpoch;
      llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
    }

    if (countPromptTokensInPenalties &&
        grammarPtr != nullptr &&
        tokensPtr != nullptr &&
        promptTokenCount > 0) {
      try {
        // The prompt must never reach the attached grammar or activate it.
        for (int i = 0; i < promptTokenCount; i++) {
          _calls.samplerAccept(penaltiesSampler, tokensPtr[i]);
        }
      } on LlamaException {
        _freeSamplerChain(sampler);
        rethrow;
      }
    }

    if (grammarPtr == nullptr && tokensPtr != nullptr && promptTokenCount > 0) {
      try {
        if (thinkingBudgetConfig != null) {
          // The composite sampler derives its reasoning state from the
          // complete prompt rather than accepting it token by token, but
          // prompt tokens still need to seed the repeat-penalty sampler as
          // before.
          for (int i = 0; i < promptTokenCount; i++) {
            _calls.samplerAccept(penaltiesSampler, tokensPtr[i]);
          }
        } else {
          for (int i = 0; i < promptTokenCount; i++) {
            _calls.samplerAccept(sampler, tokensPtr[i]);
          }
        }
      } on LlamaException {
        _freeSamplerChain(sampler);
        rethrow;
      }
    }

    return sampler;
  }

  /// Helper: Runs the main inference loop and yields tokens.
  Stream<List<int>> _runInferenceLoop(
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    Pointer<llama_sampler> sampler,
    GenerationParams params,
    int startPos,
    int nCtx,
    int cancelTokenAddress,
    Pointer<Uint8> pieceBuf,
    Set<int> preservedTokenIds,
    List<String> stopSequences,
    void Function(BackendGenerationLimit limit)? onLimit,
  ) async* {
    final cancelToken = Pointer<Int8>.fromAddress(cancelTokenAddress);
    int currentPos = startPos;
    final stopBuffer = StopSequenceBuffer(stopSequences);
    BackendGenerationLimit? limit = BackendGenerationLimit.maxTokens;
    final evalStopwatch = Stopwatch()..start();
    var sampleMicros = 0;
    var evalMicros = 0;
    var generatedTokens = 0;

    for (int i = 0; i < params.maxTokens; i++) {
      if (cancelToken.value == 1) {
        limit = null;
        break;
      }
      if (currentPos >= nCtx) {
        limit = BackendGenerationLimit.contextSize;
        break;
      }

      final sampleTick = Stopwatch()..start();
      final selectedToken = _calls.samplerSample(sampler, ctx.pointer, -1);
      sampleTick.stop();
      sampleMicros += sampleTick.elapsedMicroseconds;
      // Never pass an invalid sampled token into get_rows / token_to_piece.
      // This applies only to sampled text tokens, not multimodal embeddings.
      validateSampledToken(selectedToken, llama_vocab_n_tokens(vocab));
      if (llama_vocab_is_eog(vocab, selectedToken)) {
        limit = null;
        break;
      }

      final pieceTick = Stopwatch()..start();
      final n = _calls.tokenToPiece(
        vocab,
        selectedToken,
        pieceBuf.cast(),
        256,
        0,
        preservedTokenIds.contains(selectedToken),
      );
      pieceTick.stop();
      sampleMicros += pieceTick.elapsedMicroseconds;
      generatedTokens++;

      if (n > 0) {
        final bytes = pieceBuf.asTypedList(n).toList();
        final visible = stopBuffer.add(bytes);
        if (visible.isNotEmpty) yield visible;
        if (stopBuffer.isStopped) {
          limit = null;
          break;
        }
      }

      batch.n_tokens = 1;
      batch.token[0] = selectedToken;
      batch.pos[0] = currentPos++;
      batch.n_seq_id[0] = 1;
      batch.seq_id[0][0] = 0;
      batch.logits[0] = 1;

      final evalTick = Stopwatch()..start();
      final decodeStatus = _calls.decode(ctx.pointer, batch);
      evalTick.stop();
      evalMicros += evalTick.elapsedMicroseconds;
      if (decodeStatus != 0) {
        limit = null;
        break;
      }
    }

    final remaining = stopBuffer.finish();
    if (remaining.isNotEmpty) yield remaining;
    if (limit != null && currentPos != 0) {
      final probeToken = _calls.samplerSample(sampler, ctx.pointer, -1);
      // Never pass an invalid sampled token into native EOG checks.
      // This applies only to sampled text tokens, not multimodal embeddings.
      validateSampledToken(probeToken, llama_vocab_n_tokens(vocab));
      if (!llama_vocab_is_eog(vocab, probeToken)) {
        onLimit?.call(limit);
      }
    } else if (limit != null) {
      onLimit?.call(limit);
    }

    evalStopwatch.stop();
    ctx.lastPerfEvalMs = evalMicros / 1000.0;
    ctx.lastPerfSampleMs = sampleMicros / 1000.0;
    ctx.lastPerfDecodeMs = evalMicros / 1000.0;
    ctx.lastPerfEvalTokens = generatedTokens;
    ctx.lastPerfSampleCount = generatedTokens;
  }

  Stream<List<int>> _runSpeculativeInferenceLoop(
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    Pointer<llama_sampler> sampler,
    GenerationParams params,
    _LlamaCppSpeculativeConfig speculativeConfig,
    int startPos,
    int nCtx,
    int cancelTokenAddress,
    Pointer<Uint8> pieceBuf,
    Set<int> preservedTokenIds,
    List<String> stopSequences,
    Pointer<llama_dart_speculative> speculativeSession,
    _SpeculativeApi speculativeApi,
    Pointer<Int32> tokensPtr,
    void Function(BackendGenerationLimit limit)? onLimit,
  ) async* {
    final cancelToken = Pointer<Int8>.fromAddress(cancelTokenAddress);
    final draftCapacity = speculativeConfig.draftTokenMax;
    final draftPtr = malloc<Int32>(draftCapacity);
    final idxPtr = malloc<Int32>(draftCapacity + 1);
    final acceptedPtr = malloc<Int32>(draftCapacity + 1);
    final draftContext = speculativeApi.getDraftContext(speculativeSession);
    final hasDraftContext = draftContext != nullptr;

    int currentPos = startPos;
    int? pendingSampledToken;
    final stopBuffer = StopSequenceBuffer(stopSequences);
    final evalStopwatch = Stopwatch()..start();
    var sampleMicros = 0;
    var evalMicros = 0;
    var draftMicros = 0;
    var verifyMicros = 0;
    var generatedTokens = 0;
    var speculativeDraftTokens = 0;
    var speculativeAcceptedDraftTokens = 0;
    var speculativeDraftAttempts = 0;
    var speculativeVerifyTokens = 0;
    var speculativeReplayTokens = 0;
    var shouldStop = false;
    var contextFull = false;

    // Like [_runInferenceLoop], a reply that ends exactly at a limit is not
    // truncated, and a failed decode reports no limit. The last accepted
    // token may not be decoded yet.
    bool limitStands() {
      final undecoded = pendingSampledToken;
      if (undecoded != null) {
        if (currentPos >= nCtx) return true;
        batch.n_tokens = 1;
        batch.token[0] = undecoded;
        batch.pos[0] = currentPos;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = 1;
        if (_calls.decode(ctx.pointer, batch) != 0) return false;
      } else if (currentPos == 0) {
        return true;
      }
      final probeToken = _calls.samplerSample(sampler, ctx.pointer, -1);
      // Never pass an invalid sampled token into native EOG checks.
      // This applies only to sampled text tokens, not multimodal embeddings.
      validateSampledToken(probeToken, llama_vocab_n_tokens(vocab));
      return !llama_vocab_is_eog(vocab, probeToken);
    }

    try {
      while (!shouldStop && generatedTokens < params.maxTokens) {
        if (cancelToken.value == 1) break;
        if (currentPos >= nCtx) {
          contextFull = true;
          break;
        }

        int selectedToken;
        if (pendingSampledToken != null) {
          selectedToken = pendingSampledToken;
          pendingSampledToken = null;
        } else {
          final sampleTick = Stopwatch()..start();
          selectedToken = _calls.samplerSample(sampler, ctx.pointer, -1);
          sampleTick.stop();
          sampleMicros += sampleTick.elapsedMicroseconds;
          // Never pass an invalid sampled token into get_rows / token_to_piece.
          // This applies only to sampled text tokens, not multimodal embeddings.
          validateSampledToken(selectedToken, llama_vocab_n_tokens(vocab));
          if (llama_vocab_is_eog(vocab, selectedToken)) break;

          final pieceTick = Stopwatch()..start();
          final n = _calls.tokenToPiece(
            vocab,
            selectedToken,
            pieceBuf.cast(),
            256,
            0,
            preservedTokenIds.contains(selectedToken),
          );
          pieceTick.stop();
          sampleMicros += pieceTick.elapsedMicroseconds;
          generatedTokens++;

          if (n > 0) {
            final bytes = pieceBuf.asTypedList(n).toList();
            final visible = stopBuffer.add(bytes);
            if (visible.isNotEmpty) yield visible;
            shouldStop = stopBuffer.isStopped;
          }

          if (shouldStop) {
            break;
          }
        }

        final remainingToGenerate = params.maxTokens - generatedTokens;
        final batchCapacity = math.max(1, llama_n_batch(ctx.pointer));
        final rollbackCapacity = llama_n_rs_seq(ctx.pointer);
        final contextDraftCapacity = rollbackCapacity > 0
            ? math.min(nCtx - currentPos - 2, rollbackCapacity)
            : nCtx - currentPos - 2;
        final draftLimit = remainingToGenerate <= 1
            ? 0
            : math.min(
                speculativeConfig.draftTokenMax,
                math.min(
                  math.min(remainingToGenerate - 1, contextDraftCapacity),
                  batchCapacity - 1,
                ),
              );

        var draftCount = 0;
        if (draftLimit > 0) {
          speculativeDraftAttempts++;
          final draftTick = Stopwatch()..start();
          draftCount = speculativeApi.draft(
            speculativeSession,
            0,
            currentPos,
            selectedToken,
            tokensPtr,
            currentPos,
            draftLimit,
            draftPtr,
            draftLimit,
          );
          draftTick.stop();
          draftMicros += draftTick.elapsedMicroseconds;
          if (draftCount < 0) {
            _throwIfSpeculativeCaught(
              'llama_dart_speculative_draft',
              ctx.pointer,
            );
            throw Exception("llama.cpp speculative draft failed");
          }
          speculativeDraftTokens += draftCount;
        }

        if (draftCount <= 0) {
          batch.n_tokens = 1;
          batch.token[0] = selectedToken;
          batch.pos[0] = currentPos;
          batch.n_seq_id[0] = 1;
          batch.seq_id[0][0] = 0;
          batch.logits[0] = 1;

          final evalTick = Stopwatch()..start();
          final decodeStatus = _calls.decode(ctx.pointer, batch);
          if (decodeStatus == 0 &&
              !_processSpeculativeBatch(
                speculativeApi,
                speculativeSession,
                batch,
                speculativeConfig,
                ctx.pointer,
              )) {
            throw Exception("Speculative decode processing failed");
          }
          evalTick.stop();
          evalMicros += evalTick.elapsedMicroseconds;
          if (decodeStatus != 0) {
            shouldStop = true;
            break;
          }

          tokensPtr[currentPos] = selectedToken;
          currentPos++;
          continue;
        }

        Pointer<Uint8> seqCheckpoint = nullptr;
        var seqCheckpointSize = 0;
        final draftMemory = hasDraftContext
            ? llama_get_memory(draftContext)
            : nullptr;

        try {
          if (hasDraftContext) {
            if (draftMemory == nullptr ||
                !llama_memory_seq_rm(draftMemory, 0, currentPos, -1)) {
              throw UnsupportedError(
                'llama.cpp speculative draft rollback failed for this context.',
              );
            }
          } else {
            _calls.synchronize(ctx.pointer);
            seqCheckpointSize = _calls.stateSeqGetSizeExt(
              ctx.pointer,
              0,
              LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY,
            );
            if (seqCheckpointSize > 0) {
              seqCheckpoint = malloc<Uint8>(seqCheckpointSize);
              final written = _calls.stateSeqGetDataExt(
                ctx.pointer,
                seqCheckpoint,
                seqCheckpointSize,
                0,
                LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY,
              );
              if (written != seqCheckpointSize) {
                throw Exception(
                  'speculative checkpoint capture failed '
                  '(expected $seqCheckpointSize bytes, got $written)',
                );
              }
            }
          }

          final batchTokens = draftCount + 1;
          batch.n_tokens = batchTokens;
          batch.token[0] = selectedToken;
          batch.pos[0] = currentPos;
          batch.n_seq_id[0] = 1;
          batch.seq_id[0][0] = 0;
          batch.logits[0] = 1;
          for (int i = 0; i < draftCount; i++) {
            final batchIndex = i + 1;
            batch.token[batchIndex] = draftPtr[i];
            batch.pos[batchIndex] = currentPos + batchIndex;
            batch.n_seq_id[batchIndex] = 1;
            batch.seq_id[batchIndex][0] = 0;
            batch.logits[batchIndex] = 1;
          }

          final evalTick = Stopwatch()..start();
          final decodeStatus = _calls.decode(ctx.pointer, batch);
          if (decodeStatus == 0 &&
              !_processSpeculativeBatch(
                speculativeApi,
                speculativeSession,
                batch,
                speculativeConfig,
                ctx.pointer,
              )) {
            throw Exception("Speculative decode processing failed");
          }
          if (decodeStatus == 0) {
            _calls.synchronize(ctx.pointer);
          }
          evalTick.stop();
          evalMicros += evalTick.elapsedMicroseconds;
          if (decodeStatus != 0) {
            shouldStop = true;
            break;
          }
          speculativeVerifyTokens += batchTokens;

          for (int i = 0; i < batchTokens; i++) {
            idxPtr[i] = i;
          }

          final verifyTick = Stopwatch()..start();
          final acceptedCount = speculativeApi.sampleAndAcceptN(
            sampler,
            ctx.pointer,
            idxPtr,
            batchTokens,
            draftPtr,
            draftCount,
            acceptedPtr,
            batchTokens,
          );
          verifyTick.stop();
          verifyMicros += verifyTick.elapsedMicroseconds;
          if (acceptedCount <= 0) {
            _calls.failures.throwIfCaught(
              'llama_dart_sampler_sample_and_accept_n',
              LlamaInferenceException.new,
              windowsFreeOnly: [ctx.pointer],
            );
            throw Exception("llama.cpp speculative draft verification failed");
          }

          final acceptedDraftCount = acceptedCount - 1;
          final rejectedTailCount = batchTokens - acceptedCount;
          final keepUntil = currentPos + 1 + acceptedDraftCount;
          var targetTailReconciled = false;
          if (!hasDraftContext && rejectedTailCount > 0) {
            final targetMemory = llama_get_memory(ctx.pointer);
            final trimmedRejectedTail =
                targetMemory != nullptr &&
                llama_memory_seq_rm(targetMemory, 0, keepUntil, -1);
            if (trimmedRejectedTail) {
              targetTailReconciled = true;
            } else {
              if (seqCheckpoint == nullptr) {
                throw UnsupportedError(
                  'llama.cpp speculative checkpoint rollback is unavailable '
                  'for this context.',
                );
              }

              final restored = _calls.stateSeqSetDataExt(
                ctx.pointer,
                seqCheckpoint,
                seqCheckpointSize,
                0,
                LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY,
              );
              if (restored != seqCheckpointSize) {
                throw Exception(
                  'speculative checkpoint restore failed '
                  '(expected $seqCheckpointSize bytes, got $restored)',
                );
              }

              final targetMemory = llama_get_memory(ctx.pointer);
              if (targetMemory == nullptr ||
                  !llama_memory_seq_rm(targetMemory, 0, currentPos, -1)) {
                throw UnsupportedError(
                  'llama.cpp speculative checkpoint rollback failed for this '
                  'context.',
                );
              }

              final replayTokens = 1 + acceptedDraftCount;
              batch.n_tokens = replayTokens;
              batch.token[0] = selectedToken;
              batch.pos[0] = currentPos;
              batch.n_seq_id[0] = 1;
              batch.seq_id[0][0] = 0;
              batch.logits[0] = 0;
              for (int i = 0; i < acceptedDraftCount; i++) {
                final batchIndex = i + 1;
                batch.token[batchIndex] = acceptedPtr[i];
                batch.pos[batchIndex] = currentPos + batchIndex;
                batch.n_seq_id[batchIndex] = 1;
                batch.seq_id[batchIndex][0] = 0;
                batch.logits[batchIndex] = 0;
              }

              final replayTick = Stopwatch()..start();
              final replayStatus = _calls.decode(ctx.pointer, batch);
              if (replayStatus == 0 &&
                  !_processSpeculativeBatch(
                    speculativeApi,
                    speculativeSession,
                    batch,
                    speculativeConfig,
                    ctx.pointer,
                  )) {
                throw Exception("Speculative replay processing failed");
              }
              if (replayStatus == 0) {
                _calls.synchronize(ctx.pointer);
              }
              replayTick.stop();
              evalMicros += replayTick.elapsedMicroseconds;
              if (replayStatus != 0) {
                throw Exception("Speculative replay decode failed");
              }
              speculativeReplayTokens += replayTokens;
              targetTailReconciled = true;
            }
          }

          speculativeAcceptedDraftTokens += acceptedDraftCount;
          speculativeApi.accept(speculativeSession, 0, acceptedDraftCount);
          _throwIfSpeculativeCaught(
            'llama_dart_speculative_accept',
            ctx.pointer,
          );

          final targetMemory = llama_get_memory(ctx.pointer);
          final targetRollbackOk =
              targetTailReconciled ||
              targetMemory != nullptr &&
                  llama_memory_seq_rm(targetMemory, 0, keepUntil, -1);
          final draftRollbackOk =
              !hasDraftContext ||
              (draftMemory != nullptr &&
                  llama_memory_seq_rm(draftMemory, 0, keepUntil, -1));
          if (!targetRollbackOk || !draftRollbackOk) {
            throw UnsupportedError(
              'llama.cpp speculative target rollback failed for this context. '
              'Set ModelParams.speculativeRollbackTokenMax >= the effective '
              'speculative draft length (draftTokenMax for draft-model or '
              'ngram-cache strategies; ngramTokenMax when set for ngram-mod, '
              'otherwise draftTokenMax/default; ngramSizeM for ngram-simple, '
              'ngram-map-k, or ngram-map-k4v) if this model/backend uses '
              'bounded rollback snapshots.',
            );
          }

          tokensPtr[currentPos] = selectedToken;
          for (int i = 0; i < acceptedDraftCount; i++) {
            tokensPtr[currentPos + 1 + i] = acceptedPtr[i];
          }
          currentPos = keepUntil;

          for (int i = 0; i < acceptedCount; i++) {
            final token = acceptedPtr[i];
            if (llama_vocab_is_eog(vocab, token)) {
              shouldStop = true;
              break;
            }

            final pieceTick = Stopwatch()..start();
            final n = _calls.tokenToPiece(
              vocab,
              token,
              pieceBuf.cast(),
              256,
              0,
              preservedTokenIds.contains(token),
            );
            pieceTick.stop();
            sampleMicros += pieceTick.elapsedMicroseconds;
            generatedTokens++;

            if (n > 0) {
              final bytes = pieceBuf.asTypedList(n).toList();
              final visible = stopBuffer.add(bytes);
              if (visible.isNotEmpty) yield visible;
              shouldStop = stopBuffer.isStopped;
            }

            if (shouldStop || generatedTokens >= params.maxTokens) {
              break;
            }
          }

          if (!shouldStop) {
            pendingSampledToken = acceptedPtr[acceptedCount - 1];
          }
        } finally {
          if (seqCheckpoint != nullptr) {
            malloc.free(seqCheckpoint);
          }
        }
      }
      final remaining = stopBuffer.finish();
      if (remaining.isNotEmpty) yield remaining;
      final limit = contextFull
          ? BackendGenerationLimit.contextSize
          : !shouldStop && generatedTokens >= params.maxTokens
          ? BackendGenerationLimit.maxTokens
          : null;
      if (limit != null && limitStands()) onLimit?.call(limit);
    } finally {
      malloc.free(draftPtr);
      malloc.free(idxPtr);
      malloc.free(acceptedPtr);
      evalStopwatch.stop();
      ctx.lastPerfEvalMs = evalMicros / 1000.0;
      ctx.lastPerfSampleMs = sampleMicros / 1000.0;
      ctx.lastPerfDecodeMs = evalMicros / 1000.0;
      ctx.lastPerfSpeculativeDraftMs = draftMicros / 1000.0;
      ctx.lastPerfSpeculativeVerifyMs = verifyMicros / 1000.0;
      ctx.lastPerfEvalTokens = generatedTokens;
      ctx.lastPerfSampleCount = generatedTokens;
      ctx.lastPerfSpeculativeDraftTokens = speculativeDraftTokens;
      ctx.lastPerfSpeculativeAcceptedDraftTokens =
          speculativeAcceptedDraftTokens;
      ctx.lastPerfSpeculativeDraftAttempts = speculativeDraftAttempts;
      ctx.lastPerfSpeculativeVerifyTokens = speculativeVerifyTokens;
      ctx.lastPerfSpeculativeReplayTokens = speculativeReplayTokens;
      ctx.lastPerfSpeculativeRan = true;
    }
  }

  _LazyGrammarConfig? _buildLazyGrammarConfig(GenerationParams params) {
    final (patterns: triggerPatterns, tokens: triggerTokens) =
        lazyGrammarTriggerInputs(params.grammarTriggers);

    if (triggerPatterns.isEmpty && triggerTokens.isEmpty) {
      return null;
    }

    final allocatedPatternPtrs = triggerPatterns
        .map((pattern) => pattern.toNativeUtf8())
        .toList(growable: false);

    final triggerPatternsPtr = allocatedPatternPtrs.isEmpty
        ? nullptr
        : malloc<Pointer<Char>>(allocatedPatternPtrs.length);

    if (triggerPatternsPtr != nullptr) {
      for (var i = 0; i < allocatedPatternPtrs.length; i++) {
        triggerPatternsPtr[i] = allocatedPatternPtrs[i].cast();
      }
    }

    final triggerTokensPtr = triggerTokens.isEmpty
        ? nullptr
        : malloc<llama_token>(triggerTokens.length);

    if (triggerTokensPtr != nullptr) {
      for (var i = 0; i < triggerTokens.length; i++) {
        triggerTokensPtr[i] = triggerTokens[i];
      }
    }

    return _LazyGrammarConfig(
      triggerPatterns: triggerPatternsPtr,
      numTriggerPatterns: allocatedPatternPtrs.length,
      triggerTokens: triggerTokensPtr,
      numTriggerTokens: triggerTokens.length,
      allocatedPatternPointers: allocatedPatternPtrs,
    );
  }

  Set<int> _resolvePreservedTokenIds(
    Pointer<llama_vocab> vocab,
    List<String> preservedTokens,
  ) {
    if (preservedTokens.isEmpty) {
      return const <int>{};
    }

    final ids = <int>{};
    for (final tokenText in preservedTokens) {
      if (tokenText.isEmpty) {
        continue;
      }

      final (textPtr, textLength) = _toNativeUtf8WithLength(tokenText);
      try {
        final required = -_calls.tokenize(
          vocab,
          textPtr.cast(),
          textLength,
          nullptr,
          0,
          false,
          true,
        );

        if (required <= 0) {
          continue;
        }

        final tokenIds = malloc<Int32>(required);
        try {
          final actual = _calls.tokenize(
            vocab,
            textPtr.cast(),
            textLength,
            tokenIds,
            required,
            false,
            true,
          );

          if (actual > 0) {
            for (int i = 0; i < actual; i++) {
              ids.add(tokenIds[i]);
            }
          }
        } finally {
          malloc.free(tokenIds);
        }
      } finally {
        malloc.free(textPtr);
      }
    }

    return ids;
  }

  List<String> _effectiveStopSequences(
    List<String> stopSequences,
    List<String> preservedTokens,
  ) {
    if (stopSequences.isEmpty || preservedTokens.isEmpty) {
      return stopSequences;
    }

    final preservedSet = preservedTokens.toSet();
    return stopSequences
        .where((sequence) => !preservedSet.contains(sequence))
        .toList(growable: false);
  }

  /// Tokenizes the given [text].
  List<int> tokenize(int modelHandle, String text, bool addSpecial) {
    final model = _models[modelHandle];
    if (model == null) return [];
    _ensureModelUsable(model);
    final vocab = llama_model_get_vocab(model.pointer);
    final (textPtr, textLength) = _toNativeUtf8WithLength(text);
    final shouldAddSpecial =
        addSpecial && !_promptStartsWithBosToken(vocab, text);
    Pointer<Int32> tokensPtr = nullptr;
    try {
      final n = -_calls.tokenize(
        vocab,
        textPtr.cast(),
        textLength,
        nullptr,
        0,
        shouldAddSpecial,
        true,
      );
      tokensPtr = malloc<Int32>(n);
      final actual = _calls.tokenize(
        vocab,
        textPtr.cast(),
        textLength,
        tokensPtr,
        n,
        shouldAddSpecial,
        true,
      );
      return List.generate(actual, (i) => tokensPtr[i]);
    } finally {
      malloc.free(textPtr);
      if (tokensPtr != nullptr) malloc.free(tokensPtr);
    }
  }

  /// Detokenizes the given [tokens].
  String detokenize(int modelHandle, List<int> tokens, bool special) {
    final model = _models[modelHandle];
    if (model == null) return "";
    _ensureModelUsable(model);
    final vocab = llama_model_get_vocab(model.pointer);
    // UTF-8 decoding requires unsigned bytes, including byte-fallback tokens.
    final buffer = malloc<Uint8>(256);
    final bytes = <int>[];
    try {
      for (final t in tokens) {
        final n = _calls.tokenToPiece(vocab, t, buffer.cast(), 256, 0, special);
        if (n > 0) bytes.addAll(buffer.asTypedList(n));
      }
    } finally {
      malloc.free(buffer);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Persists the KV-cache state of [contextHandle] to [path] together
  /// with the producing token sequence so a later [stateLoadFile] can
  /// reuse matching prompt KV. Live logits and sampler/RNG state are not
  /// persisted; exact-prompt reuse re-evaluates the final token and can differ
  /// from full-prompt evaluation.
  ///
  /// Wraps `llama_state_save_file`. Returns true on success.
  bool stateSaveFile(int contextHandle, String path, List<int> tokens) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw LlamaStateException('Unknown context handle: $contextHandle');
    }
    _ensureContextUsable(contextHandle, ctx);
    if (_generatingContexts.containsKey(contextHandle)) {
      final activity = _activeTtsContextHandle == contextHandle
          ? 'text-to-speech'
          : 'generation';
      throw LlamaStateException(
        'Cannot save state while $activity is active on context $contextHandle',
      );
    }
    _calls.synchronize(ctx.pointer);
    final pathPtr = path.toNativeUtf8();
    final tokensPtr = tokens.isEmpty ? nullptr : malloc<Int32>(tokens.length);
    try {
      for (int i = 0; i < tokens.length; i++) {
        tokensPtr[i] = tokens[i];
      }
      return _calls.stateSaveFile(
        ctx.pointer,
        pathPtr.cast(),
        tokensPtr,
        tokens.length,
      );
    } finally {
      malloc.free(pathPtr);
      if (tokensPtr != nullptr) malloc.free(tokensPtr);
    }
  }

  /// The llama.cpp session version in the header of the state file at
  /// [path], or `null` when it cannot be read or is not a session file.
  static int? readSessionFileVersion(String path) {
    try {
      final file = File(path).openSync();
      try {
        final header = file.readSync(8);
        if (header.length < 8) return null;
        final words = ByteData.sublistView(header);
        return words.getUint32(0, Endian.little) == LLAMA_FILE_MAGIC_GGSN
            ? words.getUint32(4, Endian.little)
            : null;
      } finally {
        file.closeSync();
      }
    } on FileSystemException {
      return null;
    }
  }

  /// Restores a previously saved KV-cache state into [contextHandle].
  /// [tokenCapacity] caps the number of tokens read back.
  ///
  /// Wraps `llama_state_load_file`. Throws on failure (corrupt file,
  /// schema mismatch, etc.).
  /// A capacity outside 1..context size throws [LlamaArgumentException] before
  /// native state-load work and leaves a usable, idle context unchanged.
  List<int> stateLoadFile(int contextHandle, String path, int tokenCapacity) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw LlamaStateException('Unknown context handle: $contextHandle');
    }
    _ensureContextUsable(contextHandle, ctx);
    if (_generatingContexts.containsKey(contextHandle)) {
      final activity = _activeTtsContextHandle == contextHandle
          ? 'text-to-speech'
          : 'generation';
      throw LlamaStateException(
        'Cannot load state while $activity is active on context $contextHandle',
      );
    }
    if (tokenCapacity <= 0) {
      throw LlamaArgumentException(
        'tokenCapacity must be positive; received $tokenCapacity.',
        name: 'tokenCapacity',
        invalidValue: tokenCapacity,
      );
    }
    final contextCapacity = llama_n_ctx(ctx.pointer);
    if (tokenCapacity > contextCapacity) {
      throw LlamaArgumentException(
        'tokenCapacity must not exceed context size ($contextCapacity); '
        'received $tokenCapacity.',
        name: 'tokenCapacity',
        invalidValue: tokenCapacity,
      );
    }
    _calls.synchronize(ctx.pointer);
    final pathPtr = path.toNativeUtf8();
    final tokensPtr = malloc<Int32>(tokenCapacity);
    final countPtr = malloc<Size>();
    // llama.cpp clears the KV cache when a load fails after reading the
    // token list, so the cached prefix must not survive any load attempt.
    ctx.cachedPromptTokens = null;
    ctx.kvFromStateLoad = false;
    try {
      countPtr.value = 0;
      final ok = _calls.stateLoadFile(
        ctx.pointer,
        pathPtr.cast(),
        tokensPtr,
        tokenCapacity,
        countPtr,
      );
      if (!ok) {
        final fileVersion = readSessionFileVersion(path);
        if (fileVersion != null && fileVersion != LLAMA_SESSION_VERSION) {
          throw LlamaStateException(
            'The state file "$path" has llama.cpp session version '
            '$fileVersion, and this runtime reads version '
            '$LLAMA_SESSION_VERSION. A state file does not carry over to a '
            'llama.cpp release that changed the format: evaluate the prompt '
            'again and save a new one.',
          );
        }
        throw LlamaStateException(
          'llama_state_load_file failed for "$path" '
          '(corrupt file, version mismatch, or capacity too small)',
        );
      }
      final actual = countPtr.value;
      if (actual > tokenCapacity) {
        throw LlamaStateException(
          'llama_state_load_file returned actual=$actual '
          'exceeding capacity=$tokenCapacity',
        );
      }
      final loaded = List<int>.generate(actual, (i) => tokensPtr[i]);
      ctx.cachedPromptTokens = loaded;
      ctx.kvFromStateLoad = true;
      return loaded;
    } finally {
      malloc.free(pathPtr);
      malloc.free(tokensPtr);
      malloc.free(countPtr);
    }
  }

  /// The identity of the state [stateSaveFile] writes for [contextHandle].
  ///
  /// Throws [LlamaUnsupportedException] when the runtime does not export
  /// `llama_dart_build_identity` or reports an empty identity.
  LlamaStateIdentity stateIdentity(int contextHandle) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw LlamaStateException('Unknown context handle: $contextHandle');
    }
    _ensureContextUsable(contextHandle, ctx);
    final build = _buildIdentity;
    if (build == null) {
      throw LlamaUnsupportedException(
        'State identity needs a llama.cpp runtime that reports its build '
        'identity (llama_dart_build_identity, llamadart-native '
        '$minimumBuildIdentityNativeRelease or newer). The loaded runtime is '
        'older: remove the native release override or use '
        '$minimumBuildIdentityNativeRelease or newer.',
      );
    }
    if (build.isEmpty) {
      throw LlamaUnsupportedException(
        'State identity needs a llama.cpp runtime that reports its build '
        'identity, and the loaded runtime reports an empty one: it was not '
        'built from git checkouts of llamadart-native and llama.cpp. Use a '
        'llamadart-native $minimumBuildIdentityNativeRelease or newer release, '
        'or build it from git checkouts.',
      );
    }
    return LlamaStateIdentity(
      runtimeBuild: build,
      sessionFormatVersion: LLAMA_SESSION_VERSION,
      contextSize: llama_n_ctx(ctx.pointer),
      contextConfigDigest: stateContextConfigDigest(
        _contextParams[contextHandle]!,
      ),
    );
  }

  /// Returns one metadata value without enumerating the full model metadata.
  String? _getModelMetadataValue(int modelHandle, String key) {
    final model = _models[modelHandle];
    if (model == null) return null;
    return _readModelMetadataValue(model.pointer, key);
  }

  String? _readModelMetadataValue(Pointer<llama_model> model, String key) {
    if (key.isEmpty) return null;

    final keyPtr = key.toNativeUtf8();
    try {
      final length = llama_model_meta_val_str(model, keyPtr.cast(), nullptr, 0);
      if (length < 0) return null;

      final valueBuf = malloc<Int8>(length + 1);
      try {
        final written = llama_model_meta_val_str(
          model,
          keyPtr.cast(),
          valueBuf.cast(),
          length + 1,
        );
        if (written != length) return null;
        return valueBuf.cast<Utf8>().toDartString(length: written);
      } finally {
        malloc.free(valueBuf);
      }
    } finally {
      malloc.free(keyPtr);
    }
  }

  /// Returns metadata for the specified [modelHandle].
  Map<String, String> getMetadata(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) return {};
    final metadata = <String, String>{};
    final keyBuf = malloc<Int8>(1024);
    final valBuf = malloc<Int8>(1024 * 64);
    final n = llama_model_meta_count(model.pointer);
    for (int i = 0; i < n; i++) {
      llama_model_meta_key_by_index(model.pointer, i, keyBuf.cast(), 1024);
      llama_model_meta_val_str_by_index(
        model.pointer,
        i,
        valBuf.cast(),
        1024 * 64,
      );
      metadata[keyBuf.cast<Utf8>().toDartString()] = valBuf
          .cast<Utf8>()
          .toDartString();
    }
    malloc.free(keyBuf);
    malloc.free(valBuf);
    return metadata;
  }

  /// Returns model file type or quantization metadata for [modelHandle].
  ModelFileType? getModelFileType(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) return null;

    final ftype = raw_bindings.llama_model_ftype_raw(model.pointer);
    final namePtr = raw_bindings.llama_ftype_name_raw(ftype);
    if (namePtr == nullptr) return null;

    final name = namePtr.cast<Utf8>().toDartString();
    return ModelFileType(id: ftype, name: name);
  }

  /// Applies the configured or loaded model chat template to [messages].
  String applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) {
    if (!_models.containsKey(modelHandle)) {
      throw StateError('Invalid model handle for chat template: $modelHandle');
    }
    final metadata = getMetadata(modelHandle);
    final modelParamsTemplate = _nonEmptyTemplate(
      _modelLoadParams[modelHandle]?.chatTemplate,
    );
    final templateSource = customTemplate == null
        ? modelParamsTemplate ?? _modelChatTemplate(modelHandle)
        : null;
    final result = ChatTemplateEngine.render(
      templateSource: templateSource ?? metadata['tokenizer.chat_template'],
      messages: messages.map(_messageFromTemplateMap).toList(growable: false),
      metadata: metadata,
      addAssistant: addAssistant,
      customTemplate: customTemplate,
    );
    return result.prompt;
  }

  String? _nonEmptyTemplate(String? template) {
    if (template == null || template.isEmpty) {
      return null;
    }
    return template;
  }

  String? _modelChatTemplate(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) {
      return null;
    }
    final templatePtr = llama_model_chat_template(model.pointer, nullptr);
    if (templatePtr == nullptr) {
      return null;
    }
    final template = templatePtr.cast<Utf8>().toDartString();
    return template.isEmpty ? null : template;
  }

  LlamaChatMessage _messageFromTemplateMap(Map<String, dynamic> message) {
    final roleName = message['role']?.toString() ?? LlamaChatRole.user.name;
    final role = LlamaChatRole.values.byName(roleName);
    return LlamaChatMessage.fromText(
      role: role,
      text: _contentTextFromTemplateMap(message['content']),
    );
  }

  String _contentTextFromTemplateMap(Object? content) {
    if (content == null) {
      return '';
    }
    if (content is String) {
      return content;
    }
    if (content is Map) {
      if (_isUnsupportedTemplateContentPart(content)) {
        throw UnsupportedError(
          'LlamaCppBackend does not support multimodal chat-template content.',
        );
      }
      if (content['type']?.toString() == 'text' && content['text'] != null) {
        return content['text'].toString();
      }
      return content.toString();
    }
    if (content is Iterable) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map) {
          if (_isUnsupportedTemplateContentPart(part)) {
            throw UnsupportedError(
              'LlamaCppBackend does not support multimodal chat-template '
              'content.',
            );
          }
          final type = part['type']?.toString();
          if (type == 'text' && part['text'] != null) {
            buffer.write(part['text']);
            continue;
          }
        }
        buffer.write(part);
      }
      return buffer.toString();
    }
    return content.toString();
  }

  bool _isUnsupportedTemplateContentPart(Map<dynamic, dynamic> part) {
    final type = part['type']?.toString().toLowerCase();
    if (type == 'image' ||
        type == 'image_url' ||
        type == 'input_image' ||
        type == 'audio' ||
        type == 'input_audio' ||
        type == 'video' ||
        type == 'input_video') {
      return true;
    }
    return part.containsKey('image') ||
        part.containsKey('image_url') ||
        part.containsKey('input_audio') ||
        part.containsKey('audio') ||
        part.containsKey('video');
  }

  /// Handles LoRA adapter operations.
  void handleLora(int contextHandle, String? path, double? scale, String op) {
    final ctx = _contexts[contextHandle];
    final modelHandle = _contextToModel[contextHandle];
    if (ctx == null || modelHandle == null) return;
    _ensureNoActiveTts(contextHandle, 'change LoRA adapters');
    _ensureContextUsable(contextHandle, ctx);

    final modelAdapters = _loraAdapters[modelHandle];
    final activeLoras = _activeLoras[contextHandle];
    if (modelAdapters == null || activeLoras == null) return;

    try {
      if (op == 'set') {
        if (path == null) {
          throw Exception('LoRA path is required for set operation');
        }
        if (scale == null) {
          throw Exception('LoRA scale is required for set operation');
        }

        var adapter = modelAdapters[path];
        if (adapter == null) {
          final pathPtr = path.toNativeUtf8();
          final Pointer<llama_adapter_lora> adapterPtr;
          try {
            adapterPtr = _calls.adapterLoraInit(
              _models[modelHandle]!.pointer,
              pathPtr.cast(),
            );
          } finally {
            malloc.free(pathPtr);
          }
          if (adapterPtr == nullptr) {
            throw LlamaModelException('Failed to load LoRA at $path');
          }
          _validateLoraForEagerActivation(
            adapterPtr,
            path,
            invocationTokenCount: llama_adapter_get_alora_n_invocation_tokens,
            invocationTokenData: llama_adapter_get_alora_invocation_tokens,
            freeAdapter: llama_adapter_lora_free,
          );
          adapter = _LlamaLoraWrapper(adapterPtr);
          modelAdapters[path] = adapter;
        }
        activeLoras[path] = scale;
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
        ctx.cachedPromptTokens = null;
      } else if (op == 'remove') {
        if (path == null) {
          throw Exception('LoRA path is required for remove operation');
        }
        activeLoras.remove(path);
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
        ctx.cachedPromptTokens = null;
      } else if (op == 'clear') {
        activeLoras.clear();
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
        ctx.cachedPromptTokens = null;
      } else {
        throw Exception('Unknown LoRA operation: $op');
      }
    } catch (e) {
      rethrow;
    }
  }

  static void _validateLoraForEagerActivation(
    Pointer<llama_adapter_lora> adapter,
    String adapterPath, {
    required int Function(Pointer<llama_adapter_lora>) invocationTokenCount,
    required Pointer<llama_token> Function(Pointer<llama_adapter_lora>)
    invocationTokenData,
    required void Function(Pointer<llama_adapter_lora>) freeAdapter,
  }) {
    final int invocationTokens;
    try {
      invocationTokens = invocationTokenCount(adapter);
      final tokenData = invocationTokenData(adapter);
      if (invocationTokens > 0 && tokenData == nullptr) {
        throw StateError(
          'aLoRA metadata reports invocation tokens without token data',
        );
      }
    } catch (_) {
      _freeRejectedLoraAdapter(adapter, freeAdapter);
      throw LlamaUnsupportedException(
        'Cannot safely load the LoRA adapter at $adapterPath because the '
        'loaded native runtime cannot inspect aLoRA invocation-token metadata '
        '(missing or incompatible '
        'llama_adapter_get_alora_n_invocation_tokens / '
        'llama_adapter_get_alora_invocation_tokens ABI). Use a native runtime '
        'artifact that matches this package\'s bindings or another '
        'ABI-compatible build that exports both symbols.',
      );
    }

    // aLoRA must activate only after its invocation tokens appear, but
    // adapters here apply from the start of generation.
    if (invocationTokens > 0) {
      _freeRejectedLoraAdapter(adapter, freeAdapter);
      throw LlamaUnsupportedException(
        'The adapter at $adapterPath is an aLoRA adapter ($invocationTokens '
        'invocation token(s)). llamadart applies LoRA adapters from the start '
        'of generation, but an aLoRA adapter must activate only after its '
        'invocation sequence appears in the prompt, so applying it eagerly '
        'would silently change output. Use a standard LoRA adapter until '
        'invocation-aware activation is implemented.',
      );
    }
  }

  static void _freeRejectedLoraAdapter(
    Pointer<llama_adapter_lora> adapter,
    void Function(Pointer<llama_adapter_lora>) freeAdapter,
  ) {
    try {
      freeAdapter(adapter);
    } catch (_) {
      // Keep the safety failure typed and actionable even for a severely
      // version-skewed runtime whose cleanup symbol is also unavailable.
    }
  }

  /// Exercises the production aLoRA safety guard with injected native calls.
  ///
  /// This is public only for VM unit tests, which use inert pointer values and
  /// callbacks to cover ordinary LoRA, aLoRA, version-skew, and cleanup paths
  /// without requiring a large model/adapter fixture.
  static void debugValidateLoraForEagerActivationForTesting(
    Pointer<llama_adapter_lora> adapter,
    String adapterPath, {
    required int Function(Pointer<llama_adapter_lora>) invocationTokenCount,
    required Pointer<llama_token> Function(Pointer<llama_adapter_lora>)
    invocationTokenData,
    required void Function(Pointer<llama_adapter_lora>) freeAdapter,
  }) {
    _validateLoraForEagerActivation(
      adapter,
      adapterPath,
      invocationTokenCount: invocationTokenCount,
      invocationTokenData: invocationTokenData,
      freeAdapter: freeAdapter,
    );
  }

  void _applyActiveLoras(
    Pointer<llama_context> context,
    Map<String, _LlamaLoraWrapper> loadedAdapters,
    Map<String, double> activeLoras,
  ) {
    if (activeLoras.isEmpty) {
      final result = llama_set_adapters_lora(context, nullptr, 0, nullptr);
      if (result != 0) {
        throw Exception('Failed to clear LoRA adapters (code: $result)');
      }
      return;
    }

    final activeEntries = activeLoras.entries.toList(growable: false);
    final adapterPointers = malloc<Pointer<llama_adapter_lora>>(
      activeEntries.length,
    );
    final scalesPointer = malloc<Float>(activeEntries.length);

    try {
      for (var i = 0; i < activeEntries.length; i++) {
        final entry = activeEntries[i];
        final adapter = loadedAdapters[entry.key];
        if (adapter == null) {
          throw Exception(
            'LoRA adapter not loaded for active path: ${entry.key}',
          );
        }
        adapterPointers[i] = adapter.pointer;
        scalesPointer[i] = entry.value;
      }

      final result = llama_set_adapters_lora(
        context,
        adapterPointers,
        activeEntries.length,
        scalesPointer,
      );
      if (result != 0) {
        throw Exception('Failed to apply LoRA adapters (code: $result)');
      }
    } finally {
      malloc.free(adapterPointers);
      malloc.free(scalesPointer);
    }
  }

  /// Returns the currently active backend name.
  String getActiveBackendName() {
    return _activeBackendName;
  }

  /// Returns resolved GPU layers for the active model load.
  int? getResolvedGpuLayers() {
    if (_models.isEmpty) {
      return null;
    }
    return _activeResolvedGpuLayers;
  }

  /// Returns backend names available for selection.
  ///
  /// This path avoids optional GPU backend initialization and is intended for
  /// settings/selector UIs.
  List<String> getAvailableBackendInfo() {
    final available = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;

    if (backendModuleDirectory != null) {
      const backendCandidates = <String>[
        'cpu',
        'vulkan',
        'opencl',
        'metal',
        'cuda',
        'hip',
        'blas',
      ];

      for (final backend in backendCandidates) {
        if (_isBackendModuleBundled(backend) &&
            !_failedBackendModules.contains(backend)) {
          available.add(_backendDisplayName(backend));
        }
      }
    }

    if (available.isEmpty) {
      available.addAll(getBackendInfo());
    }

    if (available.isEmpty) {
      available.add(_backendDisplayName('cpu'));
    }

    final ordered = available.toList(growable: false)
      ..sort((a, b) {
        final aOrder = _backendDisplaySortKey(a);
        final bOrder = _backendDisplaySortKey(b);
        if (aOrder != bOrder) {
          return aOrder.compareTo(bOrder);
        }
        return a.compareTo(b);
      });
    return ordered;
  }

  static int _backendDisplaySortKey(String backendName) {
    switch (backendName.toUpperCase()) {
      case 'CPU':
        return 0;
      case 'METAL':
        return 1;
      case 'VULKAN':
        return 2;
      case 'OPENCL':
        return 3;
      case 'HIP':
        return 4;
      case 'CUDA':
        return 5;
      case 'BLAS':
        return 6;
      default:
        return 99;
    }
  }

  /// Returns information about currently initialized backend devices.
  List<String> getBackendInfo() {
    final count = _ggmlBackendDevCount();
    final devices = <String>{};
    for (var i = 0; i < count; i++) {
      final dev = _ggmlBackendDevGet(i);
      if (dev == nullptr) continue;

      final devNamePtr = _ggmlBackendDevName(dev);
      if (devNamePtr == nullptr) continue;
      final devName = devNamePtr.cast<Utf8>().toDartString();

      String label = devName;
      final reg = _ggmlBackendDevBackendReg(dev);
      if (reg != nullptr) {
        final regNamePtr = _ggmlBackendRegName(reg);
        if (regNamePtr != nullptr) {
          final regName = regNamePtr.cast<Utf8>().toDartString();
          if (regName.toLowerCase() == devName.toLowerCase()) {
            label = regName;
          } else {
            label = '$regName ($devName)';
          }
        }
      }

      devices.add(label);
    }
    if (devices.isNotEmpty) {
      return devices.toList(growable: false);
    }

    // Fallback when device-enumeration symbols are unavailable: surface loaded
    // backend modules so UI can still present selectable backends.
    final moduleBackends =
        _loadedBackendModules
            .map(_backendDisplayName)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    return moduleBackends;
  }

  static String _backendDisplayName(String backend) {
    switch (backend.toLowerCase()) {
      case 'cpu':
        return 'CPU';
      case 'vulkan':
        return 'Vulkan';
      case 'opencl':
        return 'OpenCL';
      case 'metal':
        return 'Metal';
      case 'cuda':
        return 'CUDA';
      case 'hip':
        return 'HIP';
      case 'blas':
        return 'BLAS';
      default:
        return backend;
    }
  }

  /// Returns whether GPU offloading is supported.
  bool getGpuSupport() {
    return llama_supports_gpu_offload();
  }

  /// Disposes of all resources managed by the service.
  void dispose() {
    _freeDecisionHeadsWhere((_) => true);
    for (final handle in _contexts.keys.toList()) {
      _freeContext(handle);
    }
    // A projector uses its model, so it goes first, as in freeModel.
    for (final m in _mtmdContexts.values) {
      _mtmdFree(m);
    }
    _mtmdContexts.clear();
    _modelToMtmd.clear();
    _modelToMtmdUseGpu.clear();
    for (final m in _models.values) {
      m.dispose();
    }
    _models.clear();
    for (final m in _speculativeDraftModels.values) {
      m.dispose();
    }
    _speculativeDraftModels.clear();
    _modelToSpeculativeDraftModelKeys.clear();
    _modelResolvedBackends.clear();
    _modelArchitectures.clear();
    _modelBackendNames.clear();
    _modelResolvedGpuLayers.clear();
    _modelsOnNoGpu.clear();
    _modelLoadParams.clear();
    _modelPlacements.clear();
    _activeBackendName = _backendDisplayName('cpu');
    _activeResolvedGpuLayers = 0;
    // llama_backend_free(); // DISABLED: Prevents race conditions with other isolates
  }

  /// Creates a multimodal context (projector) for the model.
  int createMultimodalContext(int modelHandle, String mmProjPath) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }
    _ensureModelUsable(model);
    if (!File(mmProjPath).existsSync()) {
      throw LlamaModelException('Multimodal projector file not found.');
    }
    _applyConfiguredLogLevel();

    final mmProjPathPtr = mmProjPath.toNativeUtf8();
    Pointer<mtmd_context> mmCtx = nullptr;
    try {
      mmCtx = _mtmdInitFromFile(
        mmProjPathPtr.cast(),
        model.pointer,
        _mtmdContextParamsFor(modelHandle),
      );
    } finally {
      malloc.free(mmProjPathPtr);
    }

    if (mmCtx == nullptr) {
      throw LlamaModelException(
        'The native runtime could not load the multimodal projector for the '
        'loaded model. It may be for a different model family, use a '
        'projector type this runtime does not support, or not be a projector '
        'file.',
      );
    }

    final handle = _getHandle();
    _mtmdContexts[handle] = mmCtx;
    _modelToMtmd[modelHandle] = handle;
    return handle;
  }

  mtmd_context_params _mtmdContextParamsFor(int modelHandle) {
    final ctxParams = _mtmdContextParamsDefault();
    ctxParams.use_gpu = _modelToMtmdUseGpu[modelHandle] ?? true;
    if (ctxParams.use_gpu && _keepsProjectorOnCpu(modelHandle)) {
      LlamaLogger.instance.debug(
        'llama_cpp_service: keeping the Qwen3.5 projector on the CPU on '
        'Android Vulkan',
      );
      ctxParams.use_gpu = false;
    }
    // Without a device mtmd takes the first GPU of any backend, which a
    // gpuDevices list may exclude.
    if (ctxParams.use_gpu && _modelPlacements[modelHandle] != null) {
      final device = _placedAuxiliaryDevice(modelHandle);
      if (device == null) {
        ctxParams.use_gpu = false;
      } else {
        ctxParams.device = device;
      }
    }
    ctxParams.cb_eval = _ttsEvalCallback();
    // ModelParams thread counts never reached mtmd, which defaults to 4.
    ctxParams.n_threads = resolveCpuThreads(0, availableCores: _availableCores);
    return ctxParams;
  }

  /// The `cb_eval` address [createMultimodalContext] passes to mtmd: that of
  /// `llama_dart_tts_eval_callback` in the library providing the text-to-
  /// speech API, or 0 when that API is unavailable or its library does not
  /// export the callback.
  int debugMtmdEvalCallbackAddressForTesting() =>
      _mtmdContextParamsFor(-1).cb_eval.address;

  /// Whether the text-to-speech API this service resolves has
  /// `llama_dart_tts_eval_callback` and `llama_dart_tts_set_cancel_flag`;
  /// null when that API is unavailable.
  ({bool evalCallback, bool setCancelFlag})? debugTtsCancelExportsForTesting() {
    final _TtsApi api;
    try {
      api = _resolveTtsApi();
    } on LlamaUnsupportedException {
      return null;
    }
    return (
      evalCallback: api.evalCallback != nullptr,
      setCancelFlag: api.setCancelFlag != null,
    );
  }

  /// Frees the multimodal context (projector).
  void freeMultimodalContext(int mmContextHandle) {
    final mmCtx = _mtmdContexts.remove(mmContextHandle);
    if (mmCtx != null) {
      _mtmdFree(mmCtx);
      _modelToMtmd.removeWhere((k, v) => v == mmContextHandle);
    }
  }

  Pointer<Char> _mtmdDefaultMarker() {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_default_marker();
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    return fallback?.defaultMarker() ?? nullptr;
  }

  mtmd_context_params _mtmdContextParamsDefault() {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_context_params_default();
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw LlamaUnsupportedException(
        _mtmdUnavailableMessage('mtmd_context_params_default'),
      );
    }
    return fallback.contextParamsDefault();
  }

  /// The exit-teardown functions the mtmd calls go through; `null` when the
  /// service calls llama.cpp directly or the runtime has no mtmd.
  ExitTeardownApi? get _mtmdExitTeardown {
    final exitTeardown = _calls.exit;
    if (exitTeardown == null ||
        (_mtmdPrimarySymbolsUnavailable && _resolveMtmdFallbackApi() == null)) {
      return null;
    }
    return exitTeardown;
  }

  /// The exception barrier the mtmd bitmap constructors go through; `null`
  /// when the runtime has none or the mtmd calls are not guarded.
  NativeBarrierApi? get _mtmdBarrier =>
      _mtmdExitTeardown == null ? null : _calls.failures.barrier;

  Pointer<mtmd_context> _mtmdInitFromFile(
    Pointer<Char> mmProjPath,
    Pointer<llama_model> model,
    mtmd_context_params ctxParams,
  ) {
    final exitTeardown = _mtmdExitTeardown;
    if (exitTeardown != null) {
      final params = calloc<mtmd_context_params>()..ref = ctxParams;
      try {
        final owner = _nativeOwner;
        final context = owner == null
            ? exitTeardown.mtmdInitFromFile(mmProjPath, model, params)
            : owner.api.createProjector(owner.token, mmProjPath, model, params);
        if (context == nullptr) {
          _calls.failures.throwIfCaught(
            'mtmd_init_from_file',
            LlamaModelException.new,
            windowsFreeOnly: [model],
          );
        }
        IsolateShutdownReleases.current.hold(
          ShutdownStage.modelUser,
          exitTeardown.freeAddress,
          context,
        );
        return context;
      } finally {
        calloc.free(params);
      }
    }
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        final free = Native.addressOf<NativeFunction<_MtmdFreeNative>>(
          mtmd_free,
        ).cast<NativeFinalizerFunction>();
        final context = mtmd_init_from_file(mmProjPath, model, ctxParams);
        IsolateShutdownReleases.current.hold(
          ShutdownStage.modelUser,
          free,
          context,
        );
        return context;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw LlamaUnsupportedException(
        _mtmdUnavailableMessage('mtmd_init_from_file'),
      );
    }
    final context = fallback.initFromFile(mmProjPath, model, ctxParams);
    IsolateShutdownReleases.current.hold(
      ShutdownStage.modelUser,
      fallback.freeAddress,
      context,
    );
    return context;
  }

  void _mtmdFree(Pointer<mtmd_context> ctx) {
    IsolateShutdownReleases.current.release(ctx);
    _calls.failures.forget(ctx);
    final exitTeardown = _mtmdExitTeardown;
    if (exitTeardown != null) {
      exitTeardown.free(ctx.cast());
      return;
    }
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        mtmd_free(ctx);
        return;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      return;
    }
    fallback.free(ctx);
  }

  Pointer<mtmd_input_chunks> _mtmdInputChunksInit() {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_input_chunks_init();
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw LlamaUnsupportedException(
        _mtmdUnavailableMessage('mtmd_input_chunks_init'),
      );
    }
    return fallback.inputChunksInit();
  }

  void _mtmdInputChunksFree(Pointer<mtmd_input_chunks> chunks) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        mtmd_input_chunks_free(chunks);
        return;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      return;
    }
    fallback.inputChunksFree(chunks);
  }

  Pointer<mtmd_bitmap> _mtmdHelperBitmapInitFromFile(
    Pointer<mtmd_context> ctx,
    Pointer<Char> pathPtr,
  ) {
    final barrier = _mtmdBarrier;
    if (barrier != null) return barrier.mtmdBitmapInitFromFile(ctx, pathPtr);
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_helper_bitmap_init_from_file(
          ctx,
          pathPtr,
          false,
          mtmd_helper_init_opt_default(),
        ).bitmap;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw LlamaUnsupportedException(
        _mtmdUnavailableMessage('mtmd_helper_bitmap_init_from_file'),
      );
    }
    return fallback
        .helperBitmapInitFromFile(
          ctx,
          pathPtr,
          false,
          fallback.helperInitOptDefault(),
        )
        .bitmap;
  }

  Pointer<mtmd_bitmap> _mtmdHelperBitmapInitFromBuf(
    Pointer<mtmd_context> ctx,
    Pointer<UnsignedChar> data,
    int size,
  ) {
    final barrier = _mtmdBarrier;
    if (barrier != null) return barrier.mtmdBitmapInitFromBuf(ctx, data, size);
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_helper_bitmap_init_from_buf(
          ctx,
          data,
          size,
          false,
          mtmd_helper_init_opt_default(),
        ).bitmap;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw LlamaUnsupportedException(
        _mtmdUnavailableMessage('mtmd_helper_bitmap_init_from_buf'),
      );
    }
    return fallback
        .helperBitmapInitFromBuf(
          ctx,
          data,
          size,
          false,
          fallback.helperInitOptDefault(),
        )
        .bitmap;
  }

  Pointer<mtmd_bitmap> _mtmdBitmapInitFromAudio(int n, Pointer<Float> samples) {
    final barrier = _mtmdBarrier;
    if (barrier != null) return barrier.mtmdBitmapInitFromAudio(n, samples);
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_bitmap_init_from_audio(n, samples);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw LlamaUnsupportedException(
        _mtmdUnavailableMessage('mtmd_bitmap_init_from_audio'),
      );
    }
    return fallback.bitmapInitFromAudio(n, samples);
  }

  void _mtmdBitmapFree(Pointer<mtmd_bitmap> bitmap) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        mtmd_bitmap_free(bitmap);
        return;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      return;
    }
    fallback.bitmapFree(bitmap);
  }

  int _mtmdTokenize(
    Pointer<mtmd_context> ctx,
    Pointer<mtmd_input_chunks> output,
    Pointer<mtmd_input_text> text,
    Pointer<Pointer<mtmd_bitmap>> bitmaps,
    int nBitmaps,
  ) {
    final exitTeardown = _mtmdExitTeardown;
    if (exitTeardown != null) {
      final result = exitTeardown.mtmdTokenize(
        ctx,
        output,
        text,
        bitmaps,
        nBitmaps,
      );
      if (result == _nativeStatusException) {
        _calls.failures.throwIfCaught(
          'mtmd_tokenize',
          LlamaInferenceException.new,
          freeOnly: [ctx],
        );
      }
      return result;
    }
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_tokenize(ctx, output, text, bitmaps, nBitmaps);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw LlamaUnsupportedException(_mtmdUnavailableMessage('mtmd_tokenize'));
    }
    return fallback.tokenize(ctx, output, text, bitmaps, nBitmaps);
  }

  int _mtmdHelperEvalChunks(
    Pointer<mtmd_context> ctx,
    Pointer<llama_context> lctx,
    Pointer<mtmd_input_chunks> chunks,
    int nPast,
    int seqId,
    int nBatch,
    bool logitsLast,
    Pointer<llama_pos> newNPast,
  ) {
    final exitTeardown = _mtmdExitTeardown;
    if (exitTeardown != null) {
      final result = exitTeardown.mtmdHelperEvalChunks(
        ctx,
        lctx,
        chunks,
        nPast,
        seqId,
        nBatch,
        logitsLast,
        newNPast,
      );
      if (result == _nativeStatusException) {
        _calls.failures.throwIfCaught(
          'mtmd_helper_eval_chunks',
          LlamaInferenceException.new,
          freeOnly: [ctx, lctx],
        );
      }
      return result;
    }
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_helper_eval_chunks(
          ctx,
          lctx,
          chunks,
          nPast,
          seqId,
          nBatch,
          logitsLast,
          newNPast,
        );
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw LlamaUnsupportedException(
        _mtmdUnavailableMessage('mtmd_helper_eval_chunks'),
      );
    }
    return fallback.helperEvalChunks(
      ctx,
      lctx,
      chunks,
      nPast,
      seqId,
      nBatch,
      logitsLast,
      newNPast,
    );
  }

  /// Puts the service on its mtmd fallback path, resolving that fallback from
  /// a wrapper library candidate instead of the mtmd library, for real-model
  /// regression tests.
  ///
  /// With [chunkEval] true, the fallback is loaded the way the service loads
  /// its own; with false, it gets no chunk-level functions.
  /// Returns false, changing nothing, when no candidate provides the
  /// fallback's mtmd functions.
  bool debugUseWrapperMtmdFallbackForTesting({required bool chunkEval}) {
    for (final candidate in _llamadartWrapperLibraryCandidates()) {
      final _MtmdApi? api;
      try {
        final library = _openWrapperLibrary(candidate);
        api = chunkEval
            ? _MtmdApi.tryLoad(library)
            : _MtmdApi.tryLoad(library, loadChunkEval: false);
      } catch (_) {
        continue;
      }
      if (api == null) continue;
      _mtmdPrimarySymbolsUnavailable = true;
      _mtmdFallbackLookupAttempted = true;
      _mtmdFallbackApi = api;
      return true;
    }
    return false;
  }

  /// Whether the mtmd fallback, loaded from [library] the way the service
  /// loads its own, has chunk-level functions.
  static bool debugMtmdFallbackHasChunkEvalForTesting(DynamicLibrary library) =>
      _MtmdApi.tryLoad(library)?.chunkEval != null;

  Pointer<NativeType> _mixedMtmdSymbol(String name) {
    final library = _resolveMtmdFallbackApi()?.library;
    if (library == null) throw ArgumentError('mtmd library unavailable');
    return library.lookup<NativeType>(name);
  }

  // Log setup can probe before backend initialization discovers the bundle's
  // module directory. A miss only describes that search, while a loaded API
  // must stay bound to the same library for live projector objects.
  static bool _shouldRetryMtmdFallbackLookup({
    required bool attempted,
    required bool hasApi,
    required String? searchedDirectory,
    required String? moduleDirectory,
  }) => !attempted || (!hasApi && searchedDirectory != moduleDirectory);

  _MtmdApi? _resolveMtmdFallbackApi({DynamicLibrary Function(String)? open}) {
    if (!_shouldRetryMtmdFallbackLookup(
      attempted: _mtmdFallbackLookupAttempted,
      hasApi: _mtmdFallbackApi != null,
      searchedDirectory: _mtmdFallbackLookupDirectory,
      moduleDirectory: _backendModuleDirectory,
    )) {
      return _mtmdFallbackApi;
    }
    _mtmdFallbackLookupAttempted = true;
    _mtmdFallbackLookupDirectory = _backendModuleDirectory;

    final fileNameCandidates = _libraryCandidates.mtmd();
    final candidates = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(backendModuleDirectory, fileName));
      }
    }

    // Keep the bundled runtime ahead of unrelated libraries on the search path.
    candidates.addAll(fileNameCandidates);

    DynamicLibrary? library;
    for (final candidate in candidates) {
      try {
        library = (open ?? DynamicLibrary.open)(candidate);
        break;
      } catch (_) {
        continue;
      }
    }
    if (library == null) {
      return null;
    }

    _mtmdFallbackApi = _MtmdApi.tryLoad(library);
    return _mtmdFallbackApi;
  }

  String _mtmdUnavailableMessage(String symbol) {
    return 'Multimodal support is unavailable in this native runtime: the '
        'llamadart library lacks an mtmd function this package calls, and the '
        'fallback mtmd library is missing or incomplete, so `$symbol` cannot '
        'run. Use the llamadart-native runtime this package pins '
        '($llamaCppTag) or an ABI-compatible build.';
  }

  // --- Helper Getters ---

  /// Returns total and free VRAM (in bytes) of the first GPU-class ggml
  /// backend device. Backend-agnostic — works for Vulkan, CUDA, HIP,
  /// Metal, whichever the active backend(s) expose at runtime.
  ///
  /// Reads memory via `ggml_backend_dev_get_props` (the struct-filling
  /// API) first. The older `ggml_backend_dev_memory` is unreliable on
  /// the Vulkan backend in current llama.cpp — it can return all-zeros
  /// even when the GPU is fully free — so we use it only as a
  /// second-chance fallback per device, for backends that haven't moved
  /// their memory reporting to props yet.
  ///
  /// All ggml backend-device FFI calls are routed through registry
  /// fallback wrappers ([_ggmlBackendDevCount], [_ggmlBackendDevType],
  /// [_ggmlBackendDevGetProps], [_ggmlBackendDevMemory]) so the call
  /// lands on whichever runtime asset owns the device state on
  /// Windows split bundles. Returns `(0, 0)` only when no GPU-class
  /// device is reachable through either symbol path AND every
  /// reachable GPU device declines to report memory.
  ({int total, int free}) getVramInfo() {
    final count = _ggmlBackendDevCount();
    for (var i = 0; i < count; i++) {
      final dev = _ggmlBackendDevGet(i);
      if (dev == nullptr) continue;
      // Compare via raw int so a future llama.cpp adding a new
      // `ggml_backend_dev_type` variant doesn't crash here via the
      // high-level binding's `fromValue` ArgumentError — unknown
      // values just don't match any GPU-class check and we move on.
      final type = _ggmlBackendDevType(dev);
      if (type != ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value &&
          type != ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value &&
          type != ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value) {
        continue;
      }
      final propsPtr = calloc<ggml_backend_dev_props>();
      try {
        if (_ggmlBackendDevGetProps(dev, propsPtr)) {
          final props = propsPtr.ref;
          if (props.memory_total > 0) {
            return (total: props.memory_total, free: props.memory_free);
          }
        }
        // get_props unavailable or reported zero on this device —
        // fall back to the older dev_memory entry point.
        final freePtr = calloc<Size>();
        final totalPtr = calloc<Size>();
        try {
          if (_ggmlBackendDevMemory(dev, freePtr, totalPtr) &&
              totalPtr.value > 0) {
            return (total: totalPtr.value, free: freePtr.value);
          }
        } finally {
          calloc.free(freePtr);
          calloc.free(totalPtr);
        }
      } finally {
        calloc.free(propsPtr);
      }
    }
    return (total: 0, free: 0);
  }

  /// Enumerates GPU-class devices across registered backends.
  ///
  /// With an empty [probeBackends] only already-registered backends are
  /// inspected — no backend module is loaded, so an unsupported GPU runtime
  /// cannot crash the process during enumeration. Pass specific backends in
  /// [probeBackends] to opt into loading just those modules (guarded; CPU/auto
  /// are ignored) before enumerating. Walks the global device list
  /// (`ggml_backend_dev_count` / `ggml_backend_dev_get`) through the registry
  /// fallback wrappers so devices register on Windows split bundles, and reads
  /// each device's description/id/memory from `ggml_backend_dev_get_props`
  /// (with `ggml_backend_dev_memory` as a memory fallback). CPU devices are
  /// excluded. Returns an empty list when no GPU-class device is reachable.
  List<GpuDeviceInfo> listGpuDevices({
    List<GpuBackend> probeBackends = const [],
  }) {
    for (final backend in probeBackends) {
      if (backend == GpuBackend.auto || backend == GpuBackend.cpu) continue;
      _tryLoadBackendModuleIfBundled(backend.name);
    }

    final count = _ggmlBackendDevCount();
    final result = <GpuDeviceInfo>[];
    final perBackendOrdinal = <GpuBackend, int>{};
    for (var i = 0; i < count; i++) {
      final dev = _ggmlBackendDevGet(i);
      if (dev == nullptr) continue;

      final propsPtr = calloc<ggml_backend_dev_props>();
      try {
        final hasProps = _ggmlBackendDevGetProps(dev, propsPtr);
        final props = hasProps ? propsPtr.ref : null;

        // Prefer the standalone type probe; when its symbol is unavailable
        // (returns -1 -> unknown) fall back to the type carried in props, so a
        // device still enumerates on runtimes missing the standalone symbol.
        // Raw-int compares keep a future llama.cpp enum variant from crashing
        // the high-level binding's fromValue.
        var type = _mapGpuDeviceType(_ggmlBackendDevType(dev));
        if (type == GpuDeviceType.unknown && props != null) {
          type = _mapGpuDeviceType(props.typeAsInt);
        }
        if (type == GpuDeviceType.cpu || type == GpuDeviceType.unknown) {
          continue;
        }

        final backend = _gpuBackendForDevice(dev);
        final mainGpu = perBackendOrdinal[backend] ?? 0;
        perBackendOrdinal[backend] = mainGpu + 1;

        var name = '';
        var description = '';
        var deviceId = '';
        var free = 0;
        var total = 0;
        if (props != null) {
          name = _utf8OrEmpty(props.name);
          description = _utf8OrEmpty(props.description);
          deviceId = _utf8OrEmpty(props.device_id);
          free = props.memory_free;
          total = props.memory_total;
        }
        if (name.isEmpty) name = _utf8OrEmpty(_ggmlBackendDevName(dev));
        if (total <= 0) {
          final freePtr = calloc<Size>();
          final totalPtr = calloc<Size>();
          try {
            if (_ggmlBackendDevMemory(dev, freePtr, totalPtr)) {
              free = freePtr.value;
              total = totalPtr.value;
            }
          } finally {
            calloc.free(freePtr);
            calloc.free(totalPtr);
          }
        }

        result.add(
          GpuDeviceInfo(
            backend: backend,
            mainGpu: mainGpu,
            name: name,
            description: description.isEmpty ? name : description,
            deviceId: deviceId,
            type: type,
            memoryFreeBytes: free,
            memoryTotalBytes: total,
          ),
        );
      } finally {
        calloc.free(propsPtr);
      }
    }
    return result;
  }

  static String _utf8OrEmpty(Pointer<Char> ptr) =>
      ptr == nullptr ? '' : ptr.cast<Utf8>().toDartString();

  static GpuDeviceType _mapGpuDeviceType(int typeInt) {
    if (typeInt == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value) {
      return GpuDeviceType.discreteGpu;
    }
    if (typeInt == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value) {
      return GpuDeviceType.integratedGpu;
    }
    if (typeInt == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value) {
      return GpuDeviceType.accelerator;
    }
    if (typeInt == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value) {
      return GpuDeviceType.cpu;
    }
    return GpuDeviceType.unknown;
  }

  /// Maps a device's owning backend registry name to a [GpuBackend]. Returns
  /// [GpuBackend.auto] when the backend can't be resolved.
  GpuBackend _gpuBackendForDevice(ggml_backend_dev_t dev) {
    final reg = _ggmlBackendDevBackendReg(dev);
    if (reg == nullptr) return GpuBackend.auto;
    final namePtr = _ggmlBackendRegName(reg);
    if (namePtr == nullptr) return GpuBackend.auto;
    return gpuBackendFromRegName(namePtr.cast<Utf8>().toDartString());
  }

  /// Maps a ggml backend registry name, or a backend display name such as
  /// `Metal`, to a [GpuBackend]; returns [GpuBackend.auto] when unrecognized.
  /// Match-by-substring because registry names vary by build (e.g. the Metal
  /// backend registers as `Metal` on some builds and `MTL` on others),
  /// mirroring [_backendInfoContainsBackendMarker].
  static GpuBackend gpuBackendFromRegName(String regName) {
    final name = regName.toLowerCase();
    if (name.contains('vulkan')) return GpuBackend.vulkan;
    if (name.contains('cuda')) return GpuBackend.cuda;
    if (name.contains('metal') || name.contains('mtl')) {
      return GpuBackend.metal;
    }
    if (name.contains('hip') || name.contains('rocm')) return GpuBackend.hip;
    if (name.contains('opencl')) return GpuBackend.opencl;
    if (name.contains('blas')) return GpuBackend.blas;
    if (name.contains('cpu')) return GpuBackend.cpu;
    return GpuBackend.auto;
  }

  /// Returns the context size for the given [contextHandle].
  int getContextSize(int contextHandle) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) return 0;
    return llama_n_ctx(ctx.pointer);
  }

  /// Token counts of the last generation on [contextHandle], or null when
  /// no such context exists.
  ({int promptTokens, int cachedPromptTokens, int completionTokens})?
  lastGenerationTokenCounts(int contextHandle) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      return null;
    }
    return (
      promptTokens: ctx.lastPerfPromptEvalTokens,
      cachedPromptTokens: ctx.lastPerfCachedPromptTokens,
      completionTokens: ctx.lastPerfEvalTokens,
    );
  }

  /// Returns native llama.cpp perf timings, or null after a request fails
  /// before its counters can be reset.
  ({
    double loadMs,
    double promptEvalMs,
    double evalMs,
    double sampleMs,
    double? decodeMs,
    int promptEvalTokens,
    int evalTokens,
    int sampleCount,
    int reusedGraphs,
    int? speculativeDraftTokens,
    int? speculativeAcceptedDraftTokens,
    int? speculativeDraftAttempts,
    int? speculativeVerifyTokens,
    int? speculativeReplayTokens,
    double? speculativeDraftMs,
    double? speculativeVerifyMs,
  })?
  getPerformanceContext(int contextHandle) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw Exception("Invalid context handle");
    }

    if (!ctx.performanceAvailable) return null;

    final perf = llama_perf_context(ctx.pointer);
    final sampler = _samplers[contextHandle];
    final samplerPerf = sampler != null ? llama_perf_sampler(sampler) : null;

    final promptEvalMs = ctx.lastPerfPromptEvalMs > 0
        ? ctx.lastPerfPromptEvalMs
        : perf.t_p_eval_ms;
    final evalMs = ctx.lastPerfEvalMs > 0 ? ctx.lastPerfEvalMs : perf.t_eval_ms;
    final sampleMs = ctx.lastPerfSampleMs > 0
        ? ctx.lastPerfSampleMs
        : (samplerPerf?.t_sample_ms ?? 0);
    final promptEvalTokens = perf.n_p_eval > 0
        ? perf.n_p_eval
        : ctx.lastPerfPromptEvalTokens;
    final evalTokens = ctx.lastPerfEvalTokens > 0
        ? ctx.lastPerfEvalTokens
        : perf.n_eval;
    final sampleCount = ctx.lastPerfSampleCount > 0
        ? ctx.lastPerfSampleCount
        : (samplerPerf?.n_sample ?? 0);
    final decodeMs = ctx.lastPerfDecodeMs > 0 ? ctx.lastPerfDecodeMs : null;
    final speculativeDraftTokens = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeDraftTokens
        : null;
    final speculativeAcceptedDraftTokens = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeAcceptedDraftTokens
        : null;
    final speculativeDraftAttempts = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeDraftAttempts
        : null;
    final speculativeVerifyTokens = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeVerifyTokens
        : null;
    final speculativeReplayTokens = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeReplayTokens
        : null;
    final speculativeDraftMs = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeDraftMs
        : null;
    final speculativeVerifyMs = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeVerifyMs
        : null;

    return (
      loadMs: perf.t_load_ms,
      promptEvalMs: promptEvalMs,
      evalMs: evalMs,
      sampleMs: sampleMs,
      decodeMs: decodeMs,
      promptEvalTokens: promptEvalTokens,
      evalTokens: evalTokens,
      sampleCount: sampleCount,
      reusedGraphs: perf.n_reused,
      speculativeDraftTokens: speculativeDraftTokens,
      speculativeAcceptedDraftTokens: speculativeAcceptedDraftTokens,
      speculativeDraftAttempts: speculativeDraftAttempts,
      speculativeVerifyTokens: speculativeVerifyTokens,
      speculativeReplayTokens: speculativeReplayTokens,
      speculativeDraftMs: speculativeDraftMs,
      speculativeVerifyMs: speculativeVerifyMs,
    );
  }

  /// Returns whether the active multimodal projector supports vision input.
  bool supportsVision(int mmContextHandle) {
    final mmCtx = _mtmdContexts[mmContextHandle];
    if (mmCtx == null ||
        _projectorHasQwen35VulkanRestriction(mmContextHandle)) {
      return false;
    }
    return _mtmdHasEncoder(mmCtx, audio: false) ??
        (throw LlamaUnsupportedException(
          _mtmdUnavailableMessage('mtmd_support_vision'),
        ));
  }

  /// Returns whether the active multimodal projector supports audio input.
  bool supportsAudio(int mmContextHandle) {
    final mmCtx = _mtmdContexts[mmContextHandle];
    if (mmCtx == null ||
        _projectorHasQwen35VulkanRestriction(mmContextHandle)) {
      return false;
    }
    return _mtmdHasEncoder(mmCtx, audio: true) ??
        (throw LlamaUnsupportedException(
          _mtmdUnavailableMessage('mtmd_support_audio'),
        ));
  }

  /// Whether the projector [mmCtx] has an audio encoder, or with [audio]
  /// false a vision encoder, as mtmd reports it.
  ///
  /// Null when neither the llamadart library nor the fallback mtmd library
  /// has the probe function.
  bool? _mtmdHasEncoder(Pointer<mtmd_context> mmCtx, {required bool audio}) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return audio ? mtmd_support_audio(mmCtx) : mtmd_support_vision(mmCtx);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }

    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) return null;
    return audio
        ? fallback.supportsAudio(mmCtx)
        : fallback.supportsVision(mmCtx);
  }

  /// The error for [parts] that mtmd failed to load or tokenize when the
  /// projector [mmCtx] reports no encoder for the kind of one of them, and
  /// null otherwise, as when the runtime lacks the probe function.
  LlamaUnsupportedException? _missingEncoderFor(
    Pointer<mtmd_context> mmCtx,
    List<LlamaContentPart> parts,
  ) {
    final kinds = parts.map(_isAudioRatherThanImage).toList(growable: false);
    for (final (kind, audio) in const [('Image', false), ('Audio', true)]) {
      if (kinds.contains(audio) &&
          _mtmdHasEncoder(mmCtx, audio: audio) == false) {
        return LlamaUnsupportedException(
          '$kind input is not supported by the loaded multimodal projector: '
          'it has no ${kind.toLowerCase()} encoder. Load a projector that has '
          'one, or leave ${kind.toLowerCase()} input out of the request.',
        );
      }
    }
    return null;
  }

  /// Whether [part] is audio (true) or an image (false) to mtmd, or null
  /// when neither is established.
  ///
  /// mtmd decides by content for a path or encoded bytes, whatever the type
  /// of the part: audio by the magic of `is_audio_file` in llama.cpp's
  /// `mtmd-helper.cpp`, and anything else is tried as an image. Other content
  /// is an image here when it has the magic of an image format, or when the
  /// caller typed the part as an image too. An audio part that mtmd does not
  /// read as audio, such as an m4a or Ogg file, and a source that cannot be
  /// read are neither, so their mtmd error is kept.
  static bool? _isAudioRatherThanImage(LlamaContentPart part) {
    final (path, bytes) = switch (part) {
      LlamaImageContent() => (part.path, part.bytes),
      LlamaAudioContent() => (part.path, part.bytes),
      _ => (null, null),
    };
    final List<int> head;
    if (path != null) {
      try {
        final file = File(path).openSync();
        try {
          head = file.readSync(12);
        } finally {
          file.closeSync();
        }
      } on FileSystemException {
        return null;
      }
    } else if (bytes != null) {
      head = bytes;
    } else {
      return part is LlamaAudioContent ? true : null;
    }
    bool has(String magic, [int offset = 0]) {
      if (head.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (head[offset + i] != magic.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (head.length >= 12 &&
        (has('RIFF') && has('WAVE', 8) ||
            has('ID3') ||
            head[0] == 0xFF && head[1] & 0xE0 == 0xE0 ||
            has('fLaC'))) {
      return true;
    }
    final imageMagic =
        has('\x89PNG\r\n\x1a\n') ||
        has('\xff\xd8\xff') ||
        has('GIF8') ||
        has('BM');
    return imageMagic || part is LlamaImageContent ? false : null;
  }

  String _videoUnreportedMessage() {
    final platform = switch (_abi) {
      Abi.androidArm ||
      Abi.androidArm64 ||
      Abi.androidIA32 ||
      Abi.androidX64 ||
      Abi.androidRiscv64 => 'Android',
      Abi.iosArm64 || Abi.iosX64 => 'iOS',
      _ => null,
    };
    if (platform != null) {
      return 'Video input is unavailable on $platform: the llamadart native '
          'artifacts for this platform are built without mtmd video support '
          '(upstream forces MTMD_VIDEO off when LLAMA_SUBPROCESS, which '
          'spawns FFmpeg, is off), so mtmd_helper_support_video reports '
          'false. Extract and send image frames instead.';
    }
    return 'Video input is unavailable: the loaded native mtmd runtime '
        'reports no video support (mtmd_helper_support_video is false). On '
        'the pinned $llamaCppTag macOS, Linux and Windows artifacts this means '
        'the loaded multimodal projector has no vision encoder; load a vision '
        'projector. Otherwise the runtime is an older or custom build without '
        'LLAMA_SUBPROCESS/MTMD_VIDEO. Video also needs FFmpeg/ffprobe on '
        'PATH, and llamadart does not yet ingest video frames. Extract and '
        'send image frames instead.';
  }

  /// Returns whether the active native mtmd build and projector report video.
  ///
  /// This is a behavioral probe. The helper symbol is present even when
  /// `MTMD_VIDEO` was compiled out, so symbol lookup alone is not sufficient.
  bool supportsVideo(int mmContextHandle) {
    final mmCtx = _mtmdContexts[mmContextHandle];
    if (mmCtx == null) {
      return false;
    }

    if (!_mtmdPrimarySymbolsUnavailable &&
        !_mtmdVideoPrimarySymbolUnavailable) {
      try {
        return mtmd_helper_support_video(mmCtx);
      } on ArgumentError {
        // Video helpers were added after the core mtmd surface. Do not mark
        // working vision/audio symbols unavailable when only this optional
        // probe is absent from an older library.
        _mtmdVideoPrimarySymbolUnavailable = true;
      }
    }

    final fallback = _resolveMtmdFallbackApi();
    return fallback?.supportsVideo(mmCtx) ?? false;
  }

  /// Reports whether the model [modelHandle] can run decision heads.
  ///
  /// Supported models are loaded ModernBERT encoders (`general.architecture`
  /// `modern-bert`) with CLS, SEP and MASK tokens.
  BackendDecisionCapabilities decisionCapabilities(int modelHandle) {
    final reason = _decisionUnsupportedReason(modelHandle);
    return BackendDecisionCapabilities(
      isSupported: reason == null,
      unsupportedReason: reason,
    );
  }

  /// Loads the decision head at [headPath] for the model [modelHandle] and
  /// returns its description.
  ///
  /// The head's config is the [configPath] file when given, else the head's
  /// `laya.config` metadata. The head gets a private encoder context of the
  /// config's `max_len` tokens, whose batch thread count also drives the
  /// head's CPU work. It runs on a GPU device of the load's backend
  /// (`mainGpu` picks among several), or on CPU with a CPU backend, disabled
  /// GPU layers, no matching device, or single-device mode with negative
  /// `mainGpu`. In other split modes, a negative or out-of-range `mainGpu`
  /// picks the first matching head device. An out-of-range nonnegative
  /// `mainGpu` in single-device mode fails the model load before head loading.
  /// Throws [LlamaStateException] for an unknown
  /// model, [LlamaUnsupportedException] for a model [decisionCapabilities]
  /// rejects, [LlamaModelException] for a head or config that does not fit
  /// the model, and [LlamaContextException] when the encoder context cannot
  /// be created or fails [checkDecisionEncoderContext].
  BackendDecisionHeadInfo loadDecisionHead(
    int modelHandle,
    String headPath,
    String? configPath,
  ) {
    final model = _models[modelHandle];
    if (model == null) {
      throw LlamaStateException(
        'No model is loaded for handle $modelHandle. Load the decision '
        'encoder before its head.',
      );
    }
    final unsupportedReason = _decisionUnsupportedReason(modelHandle);
    if (unsupportedReason != null) {
      throw LlamaUnsupportedException(unsupportedReason);
    }
    final vocab = llama_model_get_vocab(model.pointer);
    final clsToken = llama_vocab_bos(vocab);
    final sepToken = llama_vocab_sep(vocab);
    final maskToken = llama_vocab_mask(vocab);
    final hiddenSize = llama_model_n_embd(model.pointer);

    final String configText;
    final Pointer<llama_context> context;
    final DecisionHeadRuntime runtime;
    final int tokenLimit;
    final file = SafetensorsFile.open(headPath);
    try {
      configText = resolveDecisionHeadConfigText(
        headPath: headPath,
        configPath: configPath,
        metadata: file.metadata,
      );
      final config = parseDecisionHeadConfig(
        configText,
        source: configPath ?? '$headPath (laya.config metadata)',
      );
      final maxTokens = config.maxTokens;
      checkDecisionHeadFitsEncoder(
        trainedContext: llama_model_n_ctx_train(model.pointer),
        maxTokens: maxTokens,
      );
      final weights = DecisionHeadWeights.read(
        file,
        hiddenSize: hiddenSize,
        layers: config.headLayers,
      );

      final params = _modelLoadParams[modelHandle] ?? const ModelParams();
      final resolvedGpuLayers =
          _modelResolvedGpuLayers[modelHandle] ??
          resolveGpuLayersForLoad(
            params,
            isAndroid: _isAndroid,
            isIosSimulator: _isIosSimulator,
            isMacosX64: _isMacosX64,
          );
      final runsOnCpu = decisionHeadRunsOnCpu(
        params: params,
        modelBackendName: _modelBackendNames[modelHandle],
        resolvedGpuLayers: resolvedGpuLayers,
      );

      final ctxParams = llama_context_default_params();
      applyDecisionContextParams(
        ctxParams,
        params,
        maxTokens: maxTokens,
        runsOnCpu: runsOnCpu,
        availableCores: _availableCores,
      );
      if (!runsOnCpu &&
          shouldUseConservativeAndroidVulkanContextConfig(
            params,
            resolvedGpuLayers: resolvedGpuLayers,
            isAndroid: _isAndroid,
          )) {
        _applyConservativeAndroidVulkanContextConfig(ctxParams, modelHandle);
      }

      context = _createOwnedContext(model.pointer, ctxParams);
      IsolateShutdownReleases.current.hold(
        ShutdownStage.context,
        _calls.contextFreeAddress,
        context,
      );
      if (context == nullptr) {
        throw LlamaContextException(
          'Failed to create the decision encoder context of $maxTokens tokens.',
        );
      }
      try {
        tokenLimit = llama_n_ubatch(context);
        checkDecisionEncoderContext(
          poolingType: llama_pooling_type$1(context).value,
          tokenLimit: tokenLimit,
          maxTokens: maxTokens,
        );
        final device = runsOnCpu ? null : _decisionHeadDevice(modelHandle);
        runtime = DecisionHeadRuntime.create(
          weights,
          device: device,
          cpuThreads: llama_n_threads_batch(context),
          opOffload: device != null && ctxParams.op_offload,
          api: _decisionHeadGraphApi,
          exitTeardown: _calls.exit,
          failures: _calls.failures,
        );
      } catch (_) {
        IsolateShutdownReleases.current.release(context);
        _calls.freeContext(context);
        rethrow;
      }
    } finally {
      file.close();
    }

    final handle = _getHandle();
    _decisionHeads[handle] = _DecisionHead(
      modelHandle: modelHandle,
      context: context,
      runtime: runtime,
      hiddenSize: hiddenSize,
      tokenLimit: tokenLimit,
      vocabSize: llama_vocab_n_tokens(vocab),
      encode: (context, batch, valueCount) =>
          _encodeDecisionBatch(_calls.encode, context, batch, valueCount),
      freeContext: _calls.freeContext,
    );
    return BackendDecisionHeadInfo(
      handle: handle,
      hiddenSize: hiddenSize,
      clsToken: clsToken,
      sepToken: sepToken,
      maskToken: maskToken,
      maskText: _vocabTokenText(vocab, maskToken),
      configJson: configText,
      deviceName: runtime.deviceName,
    );
  }

  /// Runs [sequences] through the encoder and the decision head [headHandle]
  /// and returns one output per sequence, in order.
  ///
  /// Throws [LlamaStateException] for an unknown head and
  /// [LlamaInferenceException] when a sequence fails
  /// [validateDecisionSequences] or the encoder pass fails; no sequence runs
  /// unless all are valid.
  List<BackendDecisionOutput> runDecision(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  ) {
    final head = _decisionHeads[headHandle];
    if (head == null) {
      throw LlamaStateException(
        'Decision head $headHandle is not loaded; it was freed or its model '
        'was unloaded. Load the decision head again.',
      );
    }
    _calls.failures.ensureUsable(head.context, 'This decision head');
    validateDecisionSequences(
      sequences,
      tokenLimit: head.tokenLimit,
      vocabSize: head.vocabSize,
    );
    final batch = _batchInit(head.tokenLimit, 0, 1);
    try {
      return <BackendDecisionOutput>[
        for (final sequence in sequences)
          _runDecisionSequence(head, batch, sequence),
      ];
    } finally {
      _batchFree(batch);
    }
  }

  /// Frees the decision head [headHandle]; unknown handles are ignored.
  void freeDecisionHead(int headHandle) {
    _decisionHeads.remove(headHandle)?.dispose();
  }

  /// Checks [sequences] against a decision head's limits.
  ///
  /// Each sequence needs 1 to [tokenLimit] tokens, each in `[0, vocabSize)`,
  /// 1 to token-count markers, and every marker a position in its tokens.
  /// Throws [LlamaInferenceException] naming the first sequence that fails.
  /// The llama-web-bridge decision core runs these checks with the same
  /// messages, so both runtimes reject the same sequences.
  static void validateDecisionSequences(
    List<BackendDecisionSequence> sequences, {
    required int tokenLimit,
    required int vocabSize,
  }) {
    for (var i = 0; i < sequences.length; i++) {
      final sequence = sequences[i];
      final tokens = sequence.tokens;
      if (tokens.isEmpty || tokens.length > tokenLimit) {
        throw LlamaInferenceException(
          'Decision sequence $i has ${tokens.length} tokens; the decision '
          'encoder accepts 1 to $tokenLimit.',
        );
      }
      for (final token in tokens) {
        if (token < 0 || token >= vocabSize) {
          throw LlamaInferenceException(
            'Decision sequence $i contains token $token, outside the '
            'encoder vocabulary of $vocabSize tokens.',
          );
        }
      }
      if (sequence.markers.isEmpty) {
        throw LlamaInferenceException(
          'Decision sequence $i has no option markers.',
        );
      }
      if (sequence.markers.length > tokens.length) {
        throw LlamaInferenceException(
          'Decision sequence $i has ${sequence.markers.length} markers for '
          'its ${tokens.length} tokens; a sequence holds at most one marker '
          'per token.',
        );
      }
      for (final marker in sequence.markers) {
        if (marker < 0 || marker >= tokens.length) {
          throw LlamaInferenceException(
            'Decision sequence $i has marker $marker outside its '
            '${tokens.length} tokens.',
          );
        }
      }
    }
  }

  /// Returns the Laya config text of the decision head at [headPath].
  ///
  /// Reads the [configPath] file when given, else returns the `laya.config`
  /// entry of the head's [metadata]. Throws [LlamaModelException] when the
  /// file cannot be read or neither source exists.
  static String resolveDecisionHeadConfigText({
    required String headPath,
    required String? configPath,
    required Map<String, String> metadata,
  }) {
    if (configPath != null) {
      try {
        return File(configPath).readAsStringSync();
      } on FileSystemException catch (error) {
        throw LlamaModelException(
          'Cannot read the decision head config at $configPath.',
          error.osError?.message ?? error.message,
        );
      }
    }
    final text = metadata['laya.config'];
    if (text == null) {
      throw LlamaModelException(
        'The decision head at $headPath has no "laya.config" metadata. Pass '
        'the head\'s rl_agent_config.json as its config.',
      );
    }
    return text;
  }

  /// Parses decision head config [text] read from [source].
  ///
  /// Throws [LlamaModelException] naming [source] when
  /// [decodeDecisionHeadConfig] rejects [text].
  static DecisionHeadConfig parseDecisionHeadConfig(
    String text, {
    required String source,
  }) {
    try {
      return decodeDecisionHeadConfig(text);
    } on LlamaDecisionException catch (error) {
      throw LlamaModelException(
        'The decision head config in $source is invalid: ${error.message}',
      );
    }
  }

  /// Returns why a model cannot run decision heads, or null when it can.
  ///
  /// The model needs [architecture] `modern-bert`; [clsToken], [sepToken]
  /// and [maskToken] within `[0, vocabSize)`; a non-empty [maskText]; and an
  /// [outputSize] of 0 or equal to [hiddenSize], so the encoder returns its
  /// last hidden state.
  static String? decisionModelUnsupportedReason({
    required String? architecture,
    required int vocabSize,
    required int clsToken,
    required int sepToken,
    required int maskToken,
    required String maskText,
    required int hiddenSize,
    required int outputSize,
  }) {
    if (architecture != _decisionEncoderArchitecture) {
      final reported = architecture == null
          ? 'no architecture'
          : 'architecture "$architecture"';
      return 'Decision heads need a ModernBERT encoder GGUF '
          '(general.architecture "$_decisionEncoderArchitecture"); the loaded '
          'model reports $reported.';
    }
    for (final (name, token) in <(String, int)>[
      ('CLS', clsToken),
      ('SEP', sepToken),
      ('MASK', maskToken),
    ]) {
      if (token < 0 || token >= vocabSize) {
        return 'The loaded encoder has no $name token, which decision '
            'sequences need. Convert the GGUF with its tokenizer\'s special '
            'tokens.';
      }
    }
    if (maskText.isEmpty) {
      return 'The loaded encoder\'s MASK token has no text, which decision '
          'prompts need to strip it from user text.';
    }
    if (outputSize > 0 && outputSize != hiddenSize) {
      return 'The encoder outputs $outputSize values per token but its hidden '
          'size is $hiddenSize; decision heads need the last hidden state.';
    }
    return null;
  }

  /// Checks that a decision head config's [maxTokens] fits the loaded
  /// encoder.
  ///
  /// Throws [LlamaModelException] when [maxTokens] exceeds the encoder's
  /// [trainedContext].
  static void checkDecisionHeadFitsEncoder({
    required int trainedContext,
    required int maxTokens,
  }) {
    if (trainedContext < maxTokens) {
      throw LlamaModelException(
        'The decision head config sets max_len $maxTokens, but the loaded '
        'encoder was trained for $trainedContext tokens.',
      );
    }
  }

  /// Checks a decision encoder context for a head config's [maxTokens].
  ///
  /// Throws [LlamaContextException] when [poolingType] is not
  /// `LLAMA_POOLING_TYPE_NONE`, so the context would not return per-token
  /// hidden states, or when its [tokenLimit] (`n_ubatch`) is below
  /// [maxTokens].
  static void checkDecisionEncoderContext({
    required int poolingType,
    required int tokenLimit,
    required int maxTokens,
  }) {
    if (poolingType != llama_pooling_type.LLAMA_POOLING_TYPE_NONE.value) {
      throw LlamaContextException(
        'The decision encoder context does not return per-token hidden '
        'states (pooling is not NONE).',
      );
    }
    if (tokenLimit < maxTokens) {
      throw LlamaContextException(
        'The decision encoder context accepts $tokenLimit tokens per pass, '
        'fewer than the head config max_len $maxTokens.',
      );
    }
  }

  /// Returns whether a decision head for a model runs on the CPU.
  ///
  /// True when the model loaded on the CPU backend ([modelBackendName]
  /// `CPU`), offloads no layers ([resolvedGpuLayers] <= 0), or [params]
  /// selects no GPU (single-device split mode with a negative main GPU).
  static bool decisionHeadRunsOnCpu({
    required ModelParams params,
    required String? modelBackendName,
    required int resolvedGpuLayers,
  }) {
    return modelBackendName == _backendDisplayName('cpu') ||
        resolvedGpuLayers <= 0 ||
        selectsNoGpuDevice(
          splitMode: params.splitMode.llamaCppValue,
          mainGpu: params.mainGpu,
        );
  }

  /// Picks the device of a decision head for a model on [modelBackendName].
  ///
  /// [deviceBackends] holds the backend of each GPU or iGPU device, in
  /// registry order, and [mainGpu] counts among the devices of the model's
  /// backend. Returns the index in [deviceBackends] of the device [mainGpu]
  /// selects, or of the backend's first device when [mainGpu] is out of
  /// range in other split modes. A single-device model load with an
  /// out-of-range nonnegative index fails before head selection; callers must
  /// pass the placement of a successfully loaded model.
  /// Returns null, meaning the CPU, when single-device [splitMode]
  /// with a negative [mainGpu] selects no GPU, when [modelBackendName] maps to
  /// the CPU or to no backend, or when no device has the model's backend.
  static int? decisionHeadDeviceIndex({
    required ModelSplitMode splitMode,
    required String? modelBackendName,
    required List<GpuBackend> deviceBackends,
    required int mainGpu,
  }) {
    if (selectsNoGpuDevice(
      splitMode: splitMode.llamaCppValue,
      mainGpu: mainGpu,
    )) {
      return null;
    }
    final backend = gpuBackendFromRegName(modelBackendName ?? '');
    if (backend == GpuBackend.auto || backend == GpuBackend.cpu) {
      return null;
    }
    final matching = [
      for (final (index, deviceBackend) in deviceBackends.indexed)
        if (deviceBackend == backend) index,
    ];
    if (matching.isEmpty) {
      return null;
    }
    return mainGpu >= 0 && mainGpu < matching.length
        ? matching[mainGpu]
        : matching.first;
  }

  String? _decisionUnsupportedReason(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) {
      return 'No llama.cpp model is loaded for handle $modelHandle. Load a '
          'ModernBERT encoder GGUF first.';
    }
    final vocab = llama_model_get_vocab(model.pointer);
    final vocabSize = llama_vocab_n_tokens(vocab);
    final maskToken = llama_vocab_mask(vocab);
    return decisionModelUnsupportedReason(
      architecture: _getModelMetadataValue(modelHandle, 'general.architecture'),
      vocabSize: vocabSize,
      clsToken: llama_vocab_bos(vocab),
      sepToken: llama_vocab_sep(vocab),
      maskToken: maskToken,
      maskText: maskToken >= 0 && maskToken < vocabSize
          ? _vocabTokenText(vocab, maskToken)
          : '',
      hiddenSize: llama_model_n_embd(model.pointer),
      outputSize: llama_model_n_embd_out(model.pointer),
    );
  }

  static const String _decisionEncoderArchitecture = 'modern-bert';

  String _vocabTokenText(Pointer<llama_vocab> vocab, int token) {
    final text = llama_vocab_get_text(vocab, token);
    return text == nullptr ? '' : text.cast<Utf8>().toDartString();
  }

  /// The listed device the decision heads and projector of [modelHandle]
  /// run on, or `null`, the CPU, when its placement lists no GPU.
  ggml_backend_dev_t? _placedAuxiliaryDevice(int modelHandle) {
    final params = _modelLoadParams[modelHandle] ?? const ModelParams();
    return auxiliaryPlacementDevice(
      _modelPlacements[modelHandle]!,
      params.mainGpu,
    )?.device;
  }

  ggml_backend_dev_t? _decisionHeadDevice(int modelHandle) {
    if (_modelPlacements.containsKey(modelHandle)) {
      return _placedAuxiliaryDevice(modelHandle);
    }
    final devices = [
      for (final entry in _registeredDevices())
        if (entry.device != null &&
            entry.device != nullptr &&
            (entry.type ==
                    ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value ||
                entry.type ==
                    ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value))
          entry,
    ];
    final params = _modelLoadParams[modelHandle] ?? const ModelParams();
    final index = decisionHeadDeviceIndex(
      splitMode: params.splitMode,
      modelBackendName: _modelBackendNames[modelHandle],
      deviceBackends: [
        for (final entry in devices) gpuBackendFromRegName(entry.registry),
      ],
      mainGpu: params.mainGpu,
    );
    return index == null ? null : devices[index].device;
  }

  BackendDecisionOutput _runDecisionSequence(
    _DecisionHead head,
    llama_batch batch,
    BackendDecisionSequence sequence,
  ) {
    final tokens = sequence.tokens;
    batch.n_tokens = tokens.length;
    for (var i = 0; i < tokens.length; i++) {
      batch.token[i] = tokens[i];
      batch.pos[i] = i;
      batch.n_seq_id[i] = 1;
      batch.seq_id[i][0] = 0;
      batch.logits[i] = 1;
    }
    return head.runtime.run(
      head.encode(head.context, batch, tokens.length * head.hiddenSize),
      tokens.length,
      sequence.questionType,
      sequence.markers,
    );
  }

  void _freeDecisionHeadsWhere(bool Function(_DecisionHead head) test) {
    final handles = <int>[
      for (final MapEntry(:key, :value) in _decisionHeads.entries)
        if (test(value)) key,
    ];
    for (final handle in handles) {
      _decisionHeads.remove(handle)!.dispose();
    }
  }

  /// Discovers dedicated native text-to-speech support.
  BackendTextToSpeechCapabilities textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) {
    if (!_isMatchingContextAndProjector(contextHandle, mmContextHandle)) {
      return const BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason:
            'The loaded context and text-to-speech projector do not match.',
      );
    }

    _TtsApi api;
    try {
      api = _resolveTtsApi();
    } on LlamaUnsupportedException catch (error) {
      return BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason: error.message,
      );
    }

    if (api.apiVersion() != LLAMA_DART_TTS_API_VERSION) {
      return BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason:
            'The native text-to-speech ABI version is incompatible '
            '(expected $LLAMA_DART_TTS_API_VERSION).',
      );
    }

    final mtmd = _mtmdContexts[mmContextHandle]!;
    final acceptedTypes = _ttsAcceptedModelTypes(api);
    final info = malloc<llama_dart_tts_info>();
    try {
      info.ref.struct_size = sizeOf<llama_dart_tts_info>();
      final getInfoExt = api.hasModelTypeOptIn ? api.getInfoExt : null;
      final status = llama_dart_tts_status.fromValue(
        getInfoExt != null
            ? getInfoExt(mtmd, acceptedTypes, info)
            : api.getInfo(mtmd, info),
      );
      if (status == llama_dart_tts_status.LLAMA_DART_TTS_STATUS_UNSUPPORTED) {
        return BackendTextToSpeechCapabilities(
          isSupported: false,
          unsupportedReason: _ttsUnsupportedProjectorMessage(
            api,
            acceptedTypes,
          ),
        );
      }
      _throwForTtsStatus(
        status,
        operation: 'Text-to-speech capability probe',
        barrierCall: getInfoExt != null
            ? 'llama_dart_tts_get_info_ext'
            : 'llama_dart_tts_get_info',
      );
      final model = _backendTtsModels[info.ref.model_type];
      if (model == null || acceptedTypes & (1 << info.ref.model_type) == 0) {
        return BackendTextToSpeechCapabilities(
          isSupported: false,
          unsupportedReason: _ttsUnsupportedProjectorMessage(
            api,
            acceptedTypes,
          ),
        );
      }
      final flags = info.ref.capabilities;
      bool has(llama_dart_tts_capability capability) =>
          flags & capability.value != 0;
      final supportsLanguage = has(
        llama_dart_tts_capability.LLAMA_DART_TTS_CAPABILITY_LANGUAGE,
      );
      if (model == BackendTextToSpeechModel.chatterbox && supportsLanguage) {
        final sequences = llama_n_seq_max(_contexts[contextHandle]!.pointer);
        if (sequences < 2) {
          return BackendTextToSpeechCapabilities(
            isSupported: false,
            unsupportedReason:
                'Chatterbox Multilingual decodes a second sequence for '
                'classifier-free guidance, so its context needs '
                'ModelParams.maxParallelSequences of at least 2; this '
                'context has $sequences.',
          );
        }
      }
      if (model == BackendTextToSpeechModel.lfm3Audio &&
          !_modelHasTtsTemplate(contextHandle)) {
        return const BackendTextToSpeechCapabilities(
          isSupported: false,
          unsupportedReason:
              'The loaded model has no `tts` chat template, which LFM3-Audio '
              'speech output needs. Load the LFM3-Audio or LFM3-Omni model '
              'that matches this projector.',
        );
      }
      final supportsVoice = has(
        llama_dart_tts_capability.LLAMA_DART_TTS_CAPABILITY_VOICE,
      );
      return BackendTextToSpeechCapabilities(
        isSupported: true,
        model: model,
        sampleRateHz: info.ref.sample_rate,
        channelCount: info.ref.channels,
        supportsLanguage: supportsLanguage,
        supportsSpeakerReference: has(
          llama_dart_tts_capability.LLAMA_DART_TTS_CAPABILITY_SPEAKER_REFERENCE,
        ),
        supportsCancellation: true,
        supportsVoice: supportsVoice && api.hasModelTypeOptIn,
        voices: supportsVoice && api.hasModelTypeOptIn
            ? _ttsVoices(api, mtmd, acceptedTypes)
            : const <String>[],
      );
    } finally {
      malloc.free(info);
    }
  }

  /// Why this runtime cannot drive [model], or null when it can; reads the
  /// runtime's exports only.
  String? textToSpeechModelUnsupportedReason(BackendTextToSpeechModel model) {
    final _TtsApi api;
    try {
      api = _resolveTtsApi();
    } on LlamaUnsupportedException catch (error) {
      return error.message;
    }
    if (model == BackendTextToSpeechModel.qwen3Tts) return null;
    final name = _ttsModelName(model);
    final version = _ttsOptInNativeVersions[model]!;
    if (!api.hasModelTypeOptIn) {
      return '$name speech output needs the model-type opt-in '
          '(`llama_dart_tts_init_ext`) of llamadart-native $version or later; '
          'this llama.cpp runtime predates it.';
    }
    final type = _backendTtsModels.entries
        .firstWhere((entry) => entry.value == model)
        .key;
    if (_ttsAcceptedModelTypes(api) & (1 << type) != 0) return null;
    return 'This llama.cpp runtime cannot drive $name speech output '
        '(`llama_dart_tts_supported_model_types`); it needs '
        'llamadart-native $version or later.';
  }

  static const Map<int, BackendTextToSpeechModel> _backendTtsModels = {
    1: BackendTextToSpeechModel.qwen3Tts,
    2: BackendTextToSpeechModel.lfm3Audio,
    3: BackendTextToSpeechModel.soprano,
    4: BackendTextToSpeechModel.chatterbox,
    5: BackendTextToSpeechModel.pocketTts,
  };

  /// The `_ext` mask of model types this core drives and the runtime can
  /// create; Qwen3-TTS alone on a runtime without the opt-in.
  int _ttsAcceptedModelTypes(_TtsApi api) {
    const qwen3 = 1 << 1;
    final supportedModelTypes = api.supportedModelTypes;
    if (!api.hasModelTypeOptIn || supportedModelTypes == null) return qwen3;
    var known = 0;
    for (final type in _backendTtsModels.keys) {
      known |= 1 << type;
    }
    return (supportedModelTypes() & known) | qwen3;
  }

  String _ttsUnsupportedProjectorMessage(_TtsApi api, int acceptedTypes) {
    const base =
        'The loaded projector does not expose supported audio generation.';
    if (!api.hasModelTypeOptIn) {
      return '$base This runtime drives Qwen3-TTS only: other models need '
          'the model-type opt-in (`llama_dart_tts_init_ext`) of '
          'llamadart-native v0.8.0 or later (Chatterbox and Pocket TTS: '
          'v0.9.0).';
    }
    final missing = [
      for (final MapEntry(key: type, value: model) in _backendTtsModels.entries)
        if (acceptedTypes & (1 << type) == 0)
          '${_ttsModelName(model)} (llamadart-native '
              '${_ttsOptInNativeVersions[model]})',
    ];
    if (missing.isEmpty) return base;
    return '$base This runtime cannot drive ${missing.join(', ')} '
        '(`llama_dart_tts_supported_model_types`).';
  }

  /// The first llamadart-native release that drives each model type behind
  /// the model-type opt-in; Qwen3-TTS predates it.
  static const Map<BackendTextToSpeechModel, String> _ttsOptInNativeVersions = {
    BackendTextToSpeechModel.lfm3Audio: 'v0.8.0',
    BackendTextToSpeechModel.soprano: 'v0.8.0',
    BackendTextToSpeechModel.chatterbox: 'v0.9.0',
    BackendTextToSpeechModel.pocketTts: 'v0.9.0',
  };

  static String _ttsModelName(BackendTextToSpeechModel model) =>
      switch (model) {
        BackendTextToSpeechModel.qwen3Tts => 'Qwen3-TTS',
        BackendTextToSpeechModel.lfm3Audio => 'LFM3-Audio',
        BackendTextToSpeechModel.soprano => 'Soprano',
        BackendTextToSpeechModel.chatterbox => 'Chatterbox',
        BackendTextToSpeechModel.pocketTts => 'Pocket TTS',
      };

  bool _modelHasTtsTemplate(int contextHandle) {
    final model = _models[_contextToModel[contextHandle]];
    if (model == null) return false;
    final name = 'tts'.toNativeUtf8();
    try {
      return llama_model_chat_template(model.pointer, name.cast()) != nullptr;
    } finally {
      malloc.free(name);
    }
  }

  /// The projector's predefined voices in upstream order, or none when the
  /// runtime cannot list them (llamadart-native before v0.9.0).
  List<String> _ttsVoices(
    _TtsApi api,
    Pointer<mtmd_context> mtmd,
    int acceptedTypes,
  ) {
    final getVoiceCount = api.getVoiceCount;
    final getVoiceName = api.getVoiceName;
    if (getVoiceCount == null || getVoiceName == null) {
      return const <String>[];
    }
    final count = malloc<Int32>();
    final length = malloc<Size>();
    try {
      _throwForTtsStatus(
        llama_dart_tts_status.fromValue(
          getVoiceCount(mtmd, acceptedTypes, count),
        ),
        operation: 'Text-to-speech voice listing',
        barrierCall: 'llama_dart_tts_get_voice_count',
      );
      final voices = <String>[];
      for (var index = 0; index < count.value; index++) {
        _throwForTtsStatus(
          llama_dart_tts_status.fromValue(
            getVoiceName(mtmd, acceptedTypes, index, nullptr, 0, length),
          ),
          operation: 'Text-to-speech voice listing',
          barrierCall: 'llama_dart_tts_get_voice_name',
        );
        final capacity = length.value + 1;
        final name = malloc<Char>(capacity);
        try {
          _throwForTtsStatus(
            llama_dart_tts_status.fromValue(
              getVoiceName(mtmd, acceptedTypes, index, name, capacity, length),
            ),
            operation: 'Text-to-speech voice listing',
            barrierCall: 'llama_dart_tts_get_voice_name',
          );
          voices.add(name.cast<Utf8>().toDartString(length: length.value));
        } finally {
          malloc.free(name);
        }
      }
      return List<String>.unmodifiable(voices);
    } finally {
      malloc.free(count);
      malloc.free(length);
    }
  }

  /// Synthesizes complete float32 PCM with the stable native TTS wrapper.
  ///
  /// [cancelFlagAddress] is the address of a one-byte flag that another
  /// isolate sets to nonzero to cancel. It is read before the native task is
  /// created and, when the runtime exports `llama_dart_tts_set_cancel_flag`,
  /// attached to the task after startup so native code reads it while a step
  /// runs. It must stay allocated until this future completes; it is last read
  /// before then.
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request,
    int cancelFlagAddress, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) async {
    final context = _contexts[contextHandle];
    if (_activeTtsContextHandle != null) {
      throw LlamaStateException('Text-to-speech synthesis is already active.');
    }
    if (_generatingContexts.containsKey(contextHandle)) {
      throw LlamaStateException(
        'Cannot start text-to-speech while generation is active.',
      );
    }
    context?.performanceAvailable = false;
    final mtmd = _mtmdContexts[mmContextHandle];
    if (context == null ||
        mtmd == null ||
        !_isMatchingContextAndProjector(contextHandle, mmContextHandle)) {
      throw LlamaStateException(
        'The loaded context and text-to-speech projector do not match.',
      );
    }
    _ensureContextUsable(contextHandle, context);
    _calls.failures.ensureUsable(mtmd, 'This multimodal projector');
    // Speaker-reference loading can yield before a native task exists.
    _generatingContexts[contextHandle] = 1;
    _activeTtsContextHandle = contextHandle;
    try {
      return await _synthesizeTextToSpeech(
        contextHandle,
        context,
        mtmd,
        request,
        cancelFlagAddress,
        onProgress: onProgress,
      );
    } finally {
      _activeTtsContextHandle = null;
      _generatingContexts.remove(contextHandle);
    }
  }

  Future<BackendTextToSpeechResult> _synthesizeTextToSpeech(
    int contextHandle,
    _LlamaContextWrapper context,
    Pointer<mtmd_context> mtmd,
    BackendTextToSpeechRequest request,
    int cancelFlagAddress, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) async {
    final cancelFlag = Pointer<Int8>.fromAddress(cancelFlagAddress);
    // A cancel for this synthesis is only sent after its synthesize request,
    // so anything latched here belongs to a run that already ended.
    _ttsCancelPending = false;

    final api = _resolveTtsApi();
    final textBytes = utf8.encode(request.text);
    final text = malloc<Uint8>(textBytes.length + 1);
    for (var index = 0; index < textBytes.length; index++) {
      text[index] = textBytes[index];
    }
    text[textBytes.length] = 0;

    Pointer<Utf8> language = nullptr;
    final trimmedLanguage = request.language?.trim();
    if (trimmedLanguage != null && trimmedLanguage.isNotEmpty) {
      language = trimmedLanguage.toNativeUtf8();
    }
    final voiceName = request.voice;
    final startWithVoice = api.hasModelTypeOptIn ? api.startWithVoice : null;
    if (voiceName != null && startWithVoice == null) {
      malloc.free(text);
      if (language != nullptr) malloc.free(language);
      throw LlamaUnsupportedException(
        'Selecting a text-to-speech voice needs the model-type opt-in '
        '(`llama_dart_tts_start_with_voice`) of llamadart-native v0.8.0 or '
        'later; this runtime lacks it.',
      );
    }
    final Pointer<Utf8> voice = voiceName == null
        ? nullptr
        : voiceName.toNativeUtf8();

    Pointer<UnsignedChar> speakerAudio = nullptr;
    Uint8List? speakerBytes = request.speakerAudioBytes;
    final speakerPath = request.speakerAudioPath;
    if (speakerBytes == null && speakerPath != null) {
      try {
        speakerBytes = await File(speakerPath).readAsBytes();
      } catch (error) {
        malloc.free(text);
        if (language != nullptr) malloc.free(language);
        if (voice != nullptr) malloc.free(voice);
        throw LlamaAudioFormatException(
          'Unable to read speaker reference audio.',
          error,
        );
      }
    }
    if (speakerBytes != null && speakerBytes.isNotEmpty) {
      speakerAudio = malloc<UnsignedChar>(speakerBytes.length);
      speakerAudio
          .cast<Uint8>()
          .asTypedList(speakerBytes.length)
          .setAll(0, speakerBytes);
    }

    final requestPointer = malloc<llama_dart_tts_request>();
    final initStatus = malloc<Int32>();
    final progress = malloc<llama_dart_tts_progress>();
    Pointer<llama_dart_tts> task = nullptr;
    var framesGenerated = 0;
    var truncated = false;

    llama_set_embeddings(context.pointer, true);
    try {
      // Yields so a cancel already queued for this synthesis can be processed
      // before the native task setup, which cannot be interrupted.
      await Future<void>.delayed(Duration.zero);
      if (_ttsCancelPending || cancelFlag.value != 0) {
        _ttsCancelPending = false;
        throw LlamaTextToSpeechException(
          'Text-to-speech synthesis was cancelled.',
        );
      }
      _calls.synchronize(context.pointer);
      _resetRequestPerformance(contextHandle, context);
      final initExt = api.hasModelTypeOptIn ? api.initExt : null;
      task = initExt != null
          ? initExt(
              context.pointer,
              mtmd,
              _ttsAcceptedModelTypes(api),
              initStatus,
            )
          : api.init(context.pointer, mtmd, initStatus);
      IsolateShutdownReleases.current.hold(
        ShutdownStage.session,
        api.freeAddress,
        task,
      );
      if (task == nullptr) {
        _throwForTtsStatus(
          llama_dart_tts_status.fromValue(initStatus.value),
          operation: 'Text-to-speech initialization',
          barrierCall: initExt != null
              ? 'llama_dart_tts_init_ext'
              : 'llama_dart_tts_init',
          context: context.pointer,
        );
        throw LlamaTextToSpeechException(
          'Text-to-speech initialization returned no task.',
        );
      }
      _activeTts = task;
      if (_ttsCancelPending) {
        _ttsCancelPending = false;
        api.cancel(task);
      }

      requestPointer.ref = api.requestDefault();
      requestPointer.ref.text = text.cast();
      requestPointer.ref.text_length = textBytes.length;
      requestPointer.ref.speaker_audio = speakerAudio;
      requestPointer.ref.speaker_audio_length = speakerBytes?.length ?? 0;
      requestPointer.ref.language = language.cast();
      requestPointer.ref.sequence_id = 0;
      requestPointer.ref.prompt_batch_size = request.promptBatchSize;
      requestPointer.ref.max_frames = request.maxFrames;
      requestPointer.ref.top_k = request.topK;
      requestPointer.ref.top_p = request.topP;
      requestPointer.ref.min_p = request.minP;
      requestPointer.ref.temperature = request.temperature;
      requestPointer.ref.seed = request.seed;

      _throwForTtsStatus(
        llama_dart_tts_status.fromValue(
          voice == nullptr
              ? api.start(task, requestPointer)
              : startWithVoice!(task, requestPointer, voice.cast()),
        ),
        operation: 'Text-to-speech startup',
        api: api,
        task: task,
        barrierCall: voice == nullptr
            ? 'llama_dart_tts_start'
            : 'llama_dart_tts_start_with_voice',
        context: context.pointer,
      );
      api.setCancelFlag?.call(task, cancelFlag);

      while (true) {
        progress.ref.struct_size = sizeOf<llama_dart_tts_progress>();
        final status = llama_dart_tts_status.fromValue(
          api.step(task, progress),
        );
        if (status == llama_dart_tts_status.LLAMA_DART_TTS_STATUS_CANCELLED) {
          throw LlamaTextToSpeechException(
            'Text-to-speech synthesis was cancelled.',
          );
        }
        _throwForTtsStatus(
          status,
          operation: 'Text-to-speech generation',
          api: api,
          task: task,
          barrierCall: 'llama_dart_tts_step',
          context: context.pointer,
        );
        framesGenerated = progress.ref.frames_generated;
        truncated = progress.ref.truncated;
        final state = llama_dart_tts_state.fromValue(progress.ref.state);
        if (state == llama_dart_tts_state.LLAMA_DART_TTS_STATE_COMPLETED) {
          break;
        }
        if (state == llama_dart_tts_state.LLAMA_DART_TTS_STATE_CANCELLED) {
          throw LlamaTextToSpeechException(
            'Text-to-speech synthesis was cancelled.',
          );
        }
        if (state == llama_dart_tts_state.LLAMA_DART_TTS_STATE_FAILED) {
          throw LlamaTextToSpeechException(
            'Text-to-speech synthesis failed.',
            _ttsLastError(api, task),
          );
        }
        onProgress?.call(
          BackendTextToSpeechProgress(
            phase:
                state ==
                    llama_dart_tts_state.LLAMA_DART_TTS_STATE_PROCESSING_PROMPT
                ? BackendTextToSpeechPhase.processingPrompt
                : BackendTextToSpeechPhase.generating,
            promptTokensRemaining: progress.ref.prompt_tokens_remaining,
            framesGenerated: framesGenerated,
            truncated: truncated,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      final outputInfo = malloc<llama_dart_tts_output_info>();
      try {
        outputInfo.ref.struct_size = sizeOf<llama_dart_tts_output_info>();
        _throwForTtsStatus(
          llama_dart_tts_status.fromValue(api.getOutputInfo(task, outputInfo)),
          operation: 'Text-to-speech output metadata',
          api: api,
          task: task,
        );
        final sampleCount = outputInfo.ref.sample_count;
        if (sampleCount <= 0) {
          throw LlamaTextToSpeechException(
            'Text-to-speech completed without PCM output.',
          );
        }
        final pcm = malloc<Float>(sampleCount);
        final outputCount = malloc<Size>();
        try {
          _throwForTtsStatus(
            llama_dart_tts_status.fromValue(
              api.readPcm(task, 0, pcm, sampleCount, outputCount),
            ),
            operation: 'Text-to-speech PCM read',
            api: api,
            task: task,
          );
          if (outputCount.value != sampleCount) {
            throw LlamaTextToSpeechException(
              'Native text-to-speech returned incomplete PCM output.',
              '${outputCount.value}/$sampleCount samples',
            );
          }
          return BackendTextToSpeechResult(
            samples: Float32List.fromList(pcm.asTypedList(sampleCount)),
            sampleRateHz: outputInfo.ref.sample_rate,
            channelCount: outputInfo.ref.channels,
            framesGenerated: framesGenerated,
            truncated: truncated,
          );
        } finally {
          malloc.free(pcm);
          malloc.free(outputCount);
        }
      } finally {
        malloc.free(outputInfo);
      }
    } finally {
      if (task != nullptr) {
        try {
          api.reset(task);
        } catch (_) {}
        IsolateShutdownReleases.current.release(task);
        api.free(task);
      }
      _activeTts = nullptr;
      _ttsCancelPending = false;
      llama_set_embeddings(context.pointer, false);
      malloc.free(requestPointer);
      malloc.free(initStatus);
      malloc.free(progress);
      malloc.free(text);
      if (language != nullptr) malloc.free(language);
      if (voice != nullptr) malloc.free(voice);
      if (speakerAudio != nullptr) malloc.free(speakerAudio);
    }
  }

  /// Requests cancellation of the active native synthesis.
  void cancelTextToSpeech() {
    final task = _activeTts;
    if (task == nullptr) {
      _ttsCancelPending = true;
      return;
    }
    _resolveTtsApi().cancel(task);
  }

  bool _isMatchingContextAndProjector(int contextHandle, int mmContextHandle) {
    final modelHandle = _contextToModel[contextHandle];
    return modelHandle != null &&
        _contexts.containsKey(contextHandle) &&
        _mtmdContexts.containsKey(mmContextHandle) &&
        _modelToMtmd[modelHandle] == mmContextHandle;
  }

  void _throwForTtsStatus(
    llama_dart_tts_status status, {
    required String operation,
    _TtsApi? api,
    Pointer<llama_dart_tts>? task,
    String? barrierCall,
    Pointer<llama_context>? context,
  }) {
    if (status == llama_dart_tts_status.LLAMA_DART_TTS_STATUS_OK) {
      return;
    }
    if (barrierCall != null &&
        status == llama_dart_tts_status.LLAMA_DART_TTS_STATUS_UPSTREAM_ERROR) {
      _calls.failures.throwIfCaught(
        barrierCall,
        LlamaTextToSpeechException.new,
        freeOnly: [?context],
      );
    }
    final details = api != null && task != null && task != nullptr
        ? _ttsLastError(api, task)
        : null;
    switch (status) {
      case llama_dart_tts_status.LLAMA_DART_TTS_STATUS_UNSUPPORTED:
        throw LlamaUnsupportedException(
          '$operation is unsupported by the loaded native runtime or model.',
        );
      case llama_dart_tts_status.LLAMA_DART_TTS_STATUS_INVALID_STATE:
        throw LlamaStateException(
          '$operation is not valid in this state.',
          details,
        );
      case llama_dart_tts_status.LLAMA_DART_TTS_STATUS_SPEAKER_DECODE_FAILED:
        throw LlamaAudioFormatException(
          'Speaker reference audio could not be decoded.',
          details,
        );
      case llama_dart_tts_status.LLAMA_DART_TTS_STATUS_CANCELLED:
        throw LlamaTextToSpeechException(
          'Text-to-speech synthesis was cancelled.',
        );
      case llama_dart_tts_status.LLAMA_DART_TTS_STATUS_INVALID_ARGUMENT:
      case llama_dart_tts_status.LLAMA_DART_TTS_STATUS_UPSTREAM_ERROR:
        throw LlamaTextToSpeechException('$operation failed.', details);
      case llama_dart_tts_status.LLAMA_DART_TTS_STATUS_OK:
        return;
    }
  }

  String? _ttsLastError(_TtsApi api, Pointer<llama_dart_tts> task) {
    final error = api.lastError(task);
    if (error == nullptr) {
      return null;
    }
    final message = error.cast<Utf8>().toDartString().trim();
    return message.isEmpty ? null : message;
  }
}

class _LazyGrammarConfig {
  final Pointer<Pointer<Char>> triggerPatterns;
  final int numTriggerPatterns;
  final Pointer<llama_token> triggerTokens;
  final int numTriggerTokens;
  final List<Pointer<Utf8>> allocatedPatternPointers;

  const _LazyGrammarConfig({
    required this.triggerPatterns,
    required this.numTriggerPatterns,
    required this.triggerTokens,
    required this.numTriggerTokens,
    required this.allocatedPatternPointers,
  });

  void dispose() {
    for (final pointer in allocatedPatternPointers) {
      malloc.free(pointer);
    }

    if (triggerPatterns != nullptr) {
      malloc.free(triggerPatterns);
    }
    if (triggerTokens != nullptr) {
      malloc.free(triggerTokens);
    }
  }
}

// --- Native Wrappers ---

class _LlamaLoraWrapper {
  final Pointer<llama_adapter_lora> pointer;
  _LlamaLoraWrapper(this.pointer);
  void dispose() {
    llama_adapter_lora_free(pointer);
  }
}

class _DecisionHead {
  _DecisionHead({
    required this.modelHandle,
    required this.context,
    required this.runtime,
    required this.hiddenSize,
    required this.tokenLimit,
    required this.vocabSize,
    required this.encode,
    required this.freeContext,
  });

  final int modelHandle;
  final Pointer<llama_context> context;
  final DecisionHeadRuntime runtime;
  final int hiddenSize;
  final int tokenLimit;
  final int vocabSize;
  final Float32List Function(
    Pointer<llama_context> context,
    llama_batch batch,
    int valueCount,
  )
  encode;
  final void Function(Pointer<llama_context> context) freeContext;

  void dispose() {
    try {
      runtime.dispose();
    } finally {
      IsolateShutdownReleases.current.release(context);
      freeContext(context);
    }
  }
}

Float32List _encodeDecisionBatch(
  int Function(Pointer<llama_context> context, llama_batch batch) encode,
  Pointer<llama_context> context,
  llama_batch batch,
  int valueCount,
) {
  final status = encode(context, batch);
  if (status != 0) {
    throw LlamaInferenceException(
      'The decision encoder pass failed.',
      'llama_encode returned $status',
    );
  }
  final embeddings = llama_get_embeddings(context);
  if (embeddings == nullptr) {
    throw LlamaInferenceException(
      'The decision encoder returned no per-token hidden states.',
    );
  }
  // The next llama_encode or llama_free on the context invalidates this view.
  return embeddings.asTypedList(valueCount);
}

class _LlamaModelWrapper {
  final Pointer<llama_model> pointer;
  final String? sourcePath;
  final int vocabSize;
  final List<int> suppressedTokens;
  final LlamaCppObjectCalls _calls;
  _LlamaModelWrapper(
    this.pointer,
    this._calls, {
    this.sourcePath,
    required this.vocabSize,
    required this.suppressedTokens,
  });
  void dispose() {
    IsolateShutdownReleases.current.release(pointer);
    _calls.failures.forget(llama_model_get_vocab(pointer));
    _calls.freeModel(pointer);
  }
}

class _LlamaContextWrapper {
  final Pointer<llama_context> pointer;
  // Keep a strong model reference while the context pointer is alive.
  // ignore: unused_field
  final _LlamaModelWrapper? _modelKeepAlive;
  List<int>? cachedPromptTokens;

  /// Set by stateLoadFile, cleared by any decode. Gates the exact-prompt
  /// single-token resume path; without the gate, the in-process reuse path
  /// would diverge from the cleared+full-decode baseline (parity property).
  bool kvFromStateLoad = false;

  double lastPerfPromptEvalMs = 0;
  double lastPerfEvalMs = 0;
  double lastPerfSampleMs = 0;
  double lastPerfDecodeMs = 0;
  double lastPerfSpeculativeDraftMs = 0;
  double lastPerfSpeculativeVerifyMs = 0;
  int lastPerfPromptEvalTokens = 0;
  int lastPerfCachedPromptTokens = 0;
  int lastPerfEvalTokens = 0;
  int lastPerfSampleCount = 0;
  int lastPerfSpeculativeDraftTokens = 0;
  int lastPerfSpeculativeAcceptedDraftTokens = 0;
  int lastPerfSpeculativeDraftAttempts = 0;
  int lastPerfSpeculativeVerifyTokens = 0;
  int lastPerfSpeculativeReplayTokens = 0;
  bool lastPerfSpeculativeRan = false;
  bool performanceAvailable = true;
  final LlamaCppObjectCalls _calls;

  /// Most tokens of a text prompt one decode call takes, or `null` for the
  /// context's own micro-batch.
  final int? promptMicroBatchLimit;
  final bool qwen35VulkanRestricted;

  _LlamaContextWrapper(
    this.pointer,
    this._modelKeepAlive,
    this._calls, {
    this.promptMicroBatchLimit,
    this.qwen35VulkanRestricted = false,
  });
  void resetLastPerf() {
    lastPerfPromptEvalMs = 0;
    lastPerfEvalMs = 0;
    lastPerfSampleMs = 0;
    lastPerfDecodeMs = 0;
    lastPerfSpeculativeDraftMs = 0;
    lastPerfSpeculativeVerifyMs = 0;
    lastPerfPromptEvalTokens = 0;
    lastPerfCachedPromptTokens = 0;
    lastPerfEvalTokens = 0;
    lastPerfSampleCount = 0;
    lastPerfSpeculativeDraftTokens = 0;
    lastPerfSpeculativeAcceptedDraftTokens = 0;
    lastPerfSpeculativeDraftAttempts = 0;
    lastPerfSpeculativeVerifyTokens = 0;
    lastPerfSpeculativeReplayTokens = 0;
    lastPerfSpeculativeRan = false;
  }

  void dispose() {
    cachedPromptTokens = null;
    kvFromStateLoad = false;
    IsolateShutdownReleases.current.release(pointer);
    _calls.freeContext(pointer);
  }
}
