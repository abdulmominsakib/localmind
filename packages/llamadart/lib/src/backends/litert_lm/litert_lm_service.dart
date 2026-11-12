import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/engine/chat_template_renderer.dart';
import '../../core/engine/engine_observer.dart';
import '../../core/engine/json_schema_chat_request.dart';
import '../../core/exceptions.dart';
import '../../core/models/inference/embedding.dart';
import '../../core/llama_logger.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/chat/chat_message.dart';
import '../../core/models/chat/chat_role.dart';
import '../../core/models/config/compute_device.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/gpu_layer_count.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/model_params_runtime_support.dart';
import '../../core/models/inference/tool_choice.dart';
import '../../core/models/model_format.dart';
import '../../core/template/chat_template_engine.dart';
import '../../hook/native_release_pins.dart';
import '../backend.dart';
import '../native/model_format_probe.dart';
import 'litert_lm_bundle_template.dart';
import 'litert_lm_cache.dart';
import 'litert_lm_embedding.dart';
import 'litert_lm_gpu_adapter.dart';
import 'litert_lm_chat_template.dart';
import 'litert_lm_chat_templates.dart';
import 'litert_lm_model_link.dart';
import 'litert_lm_platform.dart';
import 'litert_lm_runtime.dart';
import 'litert_lm_runtime_client_contract.dart';
import 'litert_lm_legacy_service_client.dart';
import 'litert_lm_sampler_params.dart';

const int _gemma4DefaultVisualTokenBudget = 280;

// Probed once per isolate, on the first GPU load: each probe creates a Vulkan
// instance, and the installed drivers do not change while the process runs.
final LiteRtLmVulkanAdapters _systemVulkanAdapters =
    probeLiteRtLmVulkanAdapters();

/// Test-only replacement for the system Vulkan loader probe that a Linux
/// service without injected clients runs before a GPU load.
LiteRtLmVulkanAdapters Function()? debugLiteRtLmSystemVulkanAdaptersOverride;

LiteRtLmVulkanAdapters _systemVulkanAdaptersProbe() =>
    debugLiteRtLmSystemVulkanAdaptersOverride?.call() ?? _systemVulkanAdapters;

bool _isLinuxAbi(Abi abi) => abi == Abi.linuxX64 || abi == Abi.linuxArm64;
const String _liteRtLmVideoUnsupportedMessage =
    'LiteRT-LM video input is not supported through llamadart. '
    'Extract and send image frames instead.';

// Hosts and accelerators where real-model JSON Schema runs passed; the others
// stay refused until a run on that host passes.
const _jsonSchemaQualifiedBackendsByAbi = <Abi, Set<String>>{
  Abi.macosArm64: {'cpu', 'gpu'},
  Abi.iosArm64: {'cpu', 'gpu'},
  Abi.androidArm64: {'cpu'},
  Abi.linuxX64: {'cpu'},
  Abi.linuxArm64: {'cpu'},
  Abi.windowsX64: {'cpu'},
};

/// Reads what the `.litertlm` bundle at a path declares, as
/// [LiteRtLmRuntimeClient.bundleCapabilities] does.
typedef LiteRtLmBundleCapabilitiesReader =
    ({bool vision, bool audio, bool speculativeDecoding})? Function(
      String modelPath,
    );

/// Reads the chat template embedded in the `.litertlm` bundle at a path, as
/// [readLiteRtLmBundleChatTemplate] does.
typedef LiteRtLmBundleChatTemplateReader = String? Function(String modelPath);

/// Reads the first response channel of the `.litertlm` bundle at a path, as
/// [readLiteRtLmBundleFirstChannel] does.
typedef LiteRtLmBundleFirstChannelReader =
    ({String name, bool? isReasoning})? Function(String modelPath);

/// The per-send decode controls a request resolves to.
typedef _LiteRtLmGenerationControls = ({
  double? repetitionPenalty,
  double? presencePenalty,
  int? thinkingTokenBudget,
});

typedef _LiteRtLmEngineOptions = ({
  String? vision,
  String? audio,
  bool usesGpu,
  String? runtimeCacheDir,
});

const _liteRtLmThinkingChannelNames = {
  'thought',
  'thinking',
  'think',
  'reasoning',
};

/// Worker-owned service for the LiteRT-LM backend.
///
/// This keeps all LiteRT-LM FFI state inside the backend worker isolate. The
/// public backend only sends requests and receives stream chunks, mirroring the
/// llama.cpp backend architecture.
class LiteRtLmService {
  /// Creates a LiteRT-LM service.
  ///
  /// The service's own log records go through [LlamaLogger.instance] of the
  /// isolate it runs in; [setLogLevel] controls only the native runtime.
  /// [linkParentDirectory] holds the private directories of
  /// [LiteRtLmModelLink]s, the system temp directory by default.
  /// [useTempCacheDir] says whether caches go to a llamadart temp directory
  /// when [ModelParams.liteRtLmCacheDir] is unset; by default only on macOS
  /// and Android. [createLink] replaces [Link.create] for those links in
  /// tests. [readBundleCapabilities] replaces
  /// [LiteRtLmRuntimeClient.bundleCapabilities] on a fresh client,
  /// [readBundleChatTemplate] replaces [readLiteRtLmBundleChatTemplate], and
  /// [readBundleFirstChannel] replaces [readLiteRtLmBundleFirstChannel].
  /// [finishReasonProbeLibraryPath] is the runtime library that
  /// [reportsFinishReasons] probes, the default runtime when null.
  /// [runtimeClientFactory] injects a version-specific internal client together
  /// with its metadata and finish-reason probes. It is exclusive with the legacy
  /// [clientFactory]; neither changes the production runtime selection.
  /// [probeGpuAdapters] lists the Vulkan devices a GPU engine can use; by
  /// default the system Vulkan loader on Linux when neither factory is
  /// injected, and nothing otherwise.
  LiteRtLmService({
    LiteRtLmRuntimeClient Function()? clientFactory,
    LiteRtLmRuntimeClientContract Function()? runtimeClientFactory,
    Directory? linkParentDirectory,
    bool? useTempCacheDir,
    LiteRtLmLinkCreator? createLink,
    LiteRtLmBundleCapabilitiesReader? readBundleCapabilities,
    LiteRtLmBundleChatTemplateReader? readBundleChatTemplate,
    LiteRtLmBundleFirstChannelReader? readBundleFirstChannel,
    String? finishReasonProbeLibraryPath,
    Set<String> Function()? jsonSchemaQualifiedBackends,
    LiteRtLmVulkanAdapters Function()? probeGpuAdapters,
  }) : _probeGpuAdapters =
           probeGpuAdapters ??
           (_isLinuxAbi(liteRtLmGateAbi()) &&
                   clientFactory == null &&
                   runtimeClientFactory == null
               ? _systemVulkanAdaptersProbe
               : null),
       _jsonSchemaQualifiedBackends =
           jsonSchemaQualifiedBackends ??
           (() => _jsonSchemaQualifiedBackendsByAbi[liteRtLmGateAbi()] ?? {}),
       _clientFactory =
           runtimeClientFactory ??
           (() => clientFactory == null
               ? createLiteRtLmSelectedServiceClient()
               : LiteRtLmLegacyServiceClient(clientFactory())),
       _injectedFinishReasonProbe = runtimeClientFactory == null
           ? null
           : (() => runtimeClientFactory().supportsFinishReasons),
       _readBundleCapabilities =
           readBundleCapabilities ??
           ((modelPath) => runtimeClientFactory == null
               ? createLiteRtLmSelectedRuntimeClient().bundleCapabilities(
                   modelPath,
                 )
               : runtimeClientFactory().bundleCapabilities(modelPath)),
       _readBundleChatTemplate =
           readBundleChatTemplate ?? readLiteRtLmBundleChatTemplate,
       _readBundleFirstChannel =
           readBundleFirstChannel ?? readLiteRtLmBundleFirstChannel,
       _finishReasonProbeLibraryPath = finishReasonProbeLibraryPath,
       _linkParentDirectory = linkParentDirectory,
       _createLink = createLink,
       _useTempCacheDir =
           useTempCacheDir ?? (Platform.isMacOS || Platform.isAndroid) {
    if (clientFactory != null && runtimeClientFactory != null) {
      throw LlamaArgumentException(
        'Choose either the legacy client factory or the version-specific runtime client factory.',
      );
    }
  }

  final LiteRtLmRuntimeClientContract Function() _clientFactory;
  final LiteRtLmVulkanAdapters Function()? _probeGpuAdapters;
  final LiteRtLmBundleCapabilitiesReader _readBundleCapabilities;
  final LiteRtLmBundleChatTemplateReader _readBundleChatTemplate;
  final LiteRtLmBundleFirstChannelReader _readBundleFirstChannel;
  final String? _finishReasonProbeLibraryPath;
  final bool Function()? _injectedFinishReasonProbe;
  final Directory? _linkParentDirectory;
  final LiteRtLmLinkCreator? _createLink;
  final bool _useTempCacheDir;
  LiteRtLmRuntimeClientContract? _client;
  bool _nativeResourcesQuarantined = false;
  bool _embeddingPreparing = false;
  bool _nativeInitializationPending = false;

  /// Native lifetime; failed Dart requests can still own live callbacks.
  LiteRtLmNativeSettlement get nativeSettlement => _nativeResourcesQuarantined
      ? LiteRtLmNativeSettlement.quarantined
      : _nativeInitializationPending || _embeddingPreparing
      ? LiteRtLmNativeSettlement.pending
      : _client?.nativeSettlement ?? LiteRtLmNativeSettlement.settled;

  /// Retains this native family, its model link and cache lease until exit.
  ///
  /// This is irreversible: callers must restart the process before retrying.
  void quarantineNativeResources() {
    _nativeResourcesQuarantined = true;
  }

  bool _retainUnsettledClient(
    LiteRtLmRuntimeClientContract client,
    LiteRtLmCacheLease? lease,
  ) {
    if (client.nativeSettlement == LiteRtLmNativeSettlement.settled) {
      return false;
    }
    _client = client;
    _cacheLease = lease;
    quarantineNativeResources();
    return true;
  }

  bool _jsonSchemaAdmitted = false;
  bool _jsonSchemaThinking = false;
  final Set<String> Function() _jsonSchemaQualifiedBackends;
  LiteRtLmEmbeddingRuntimeSession? _embedding;
  LiteRtLmCacheLease? _cacheLease;
  ModelParams? _modelParams;
  String? _modelPath;
  LiteRtLmModelLink? _modelLink;
  String? _activeBackend;
  String? _loadedBackend;
  bool _automaticBackend = false;
  bool? _activeSpeculativeDecoding;
  int? _activeMaxNumImages;
  bool? _activeVisionEnabled;
  bool? _activeAudioEnabled;
  bool _recreateClientAfterImageCancellation = false;
  String? _workingAudioBackend;
  int _nextModelHandle = 1;
  int _nextContextHandle = 1;
  int? _modelHandle;
  int? _contextHandle;
  LiteRtLmRuntimeMetrics? _lastMetrics;
  ({bool vision, bool audio, bool speculativeDecoding})? _bundleCapabilities;
  bool _bundleCapabilitiesRead = false;
  bool _bundleTemplateProbed = false;
  String? _bundleTemplateAdapter;
  bool _bundleTemplateMisreadsContent = false;
  ({List<int> tokens, String text, bool plainText})? _startToken;
  ({bool penalties, bool thinkingBudget})? _runtimeGenerationControls;
  bool? _runtimeFinishReasons;
  BackendGenerationLimit? _lastGenerationLimit;
  bool? _bundleDeclaresThinkingChannel;
  LlamaLogLevel _logLevel = LlamaLogLevel.warn;
  bool _modelLoaded = false;
  bool _contextCreated = false;
  bool _cancelRequested = false;

  /// Updates the current backend log level.
  void setLogLevel(LlamaLogLevel level) {
    _logLevel = level;
    _client?.setMinLogLevel(_liteRtLmMinLogLevel(level));
  }

  /// Loads a local LiteRT-LM model bundle, recognized by its header or, when
  /// the header is unreadable, its `.litertlm` extension.
  Future<int> loadModel(
    String path,
    ModelParams params, {
    String? backendOverride,
  }) async {
    _validateModelParams(params);
    final file = File(path);
    if (!await file.exists()) {
      throw ArgumentError('LiteRT-LM model does not exist: $path');
    }
    final format =
        await readModelFormatHeader(path) ?? ModelFormat.fromPath(path);
    if (format != ModelFormat.liteRtLm) {
      throw ArgumentError(
        'LiteRtLmBackend expects a LiteRT-LM (.litertlm) model bundle; '
        'got $path',
      );
    }
    final resolvedBackend = _resolveBackendName(
      params,
      backendOverride: backendOverride,
    );
    final automaticBackend =
        params.device == ComputeDevice.auto &&
        params.liteRtLmBackend.nativeName == null &&
        normalizeLiteRtLmNativeBackendOverride(backendOverride) == null;
    final engineBackend = resolvedBackend == liteRtLmGpuBackend
        ? _gpuBackendForAdapters(automatic: automaticBackend)
        : resolvedBackend;
    if (params.liteRtLmEmbeddingEngine) {
      liteRtLmEnsureNativeEmbeddingsQualified();
      ensureLiteRtLmNativeEmbeddingBackend(resolvedBackend);
    }
    final modelLink = await LiteRtLmModelLink.create(
      path,
      parent: _linkParentDirectory,
      createLink: _createLink,
    );

    try {
      _disposeClient();
    } on Object {
      modelLink?.dispose();
      rethrow;
    }
    _modelLink?.dispose();
    _modelPath = path;
    _modelLink = modelLink;
    _modelParams = params;
    _activeBackend = engineBackend;
    _loadedBackend = resolvedBackend;
    _automaticBackend = automaticBackend;
    _activeSpeculativeDecoding = null;
    _workingAudioBackend = null;
    _bundleCapabilities = null;
    _bundleCapabilitiesRead = false;
    _bundleTemplateProbed = false;
    _bundleTemplateAdapter = null;
    _bundleTemplateMisreadsContent = false;
    _startToken = null;
    _bundleDeclaresThinkingChannel = null;
    _modelHandle = _nextModelHandle++;
    _contextHandle = null;
    _lastMetrics = null;
    _cancelRequested = false;
    _modelLoaded = true;
    _contextCreated = false;
    return _modelHandle!;
  }

  /// Frees the loaded model and any active LiteRT-LM client.
  void freeModel(int modelHandle) {
    _checkModelHandle(modelHandle);
    _disposeClient();
    _modelLink?.dispose();
    _modelLink = null;
    _modelPath = null;
    _modelParams = null;
    _activeBackend = null;
    _loadedBackend = null;
    _activeSpeculativeDecoding = null;
    _workingAudioBackend = null;
    _bundleCapabilities = null;
    _bundleCapabilitiesRead = false;
    _bundleTemplateProbed = false;
    _bundleTemplateAdapter = null;
    _bundleTemplateMisreadsContent = false;
    _startToken = null;
    _bundleDeclaresThinkingChannel = null;
    _modelHandle = null;
    _contextHandle = null;
    _lastMetrics = null;
    _cancelRequested = false;
    _modelLoaded = false;
    _contextCreated = false;
  }

  /// Creates the single LiteRT-LM context used by this backend.
  int createContext(int modelHandle, ModelParams params) {
    _checkModelHandle(modelHandle);
    _validateModelParams(params);
    _validateContextBackendParams(params);
    if (params.liteRtLmEmbeddingEngine !=
        _modelParams!.liteRtLmEmbeddingEngine) {
      throw LlamaUnsupportedException(
        'A LiteRT-LM context cannot change the embedding engine selected at model load; reload the model to switch engines.',
      );
    }
    _disposeContextRuntimeState();
    _modelParams = params;
    _contextHandle = _nextContextHandle++;
    _contextCreated = true;
    return _contextHandle!;
  }

  /// Frees the active LiteRT-LM context.
  void freeContext(int contextHandle) {
    _checkContextHandle(contextHandle);
    _disposeContextRuntimeState();
    _contextHandle = null;
    _contextCreated = false;
  }

  /// Returns the configured context size.
  int getContextSize(int contextHandle) {
    _checkContextHandle(contextHandle);
    return _modelParams?.contextSize ?? 0;
  }

  void _requireConversationEngine() {
    if (_modelParams?.liteRtLmEmbeddingEngine ?? false) {
      throw LlamaUnsupportedException(
        'Conversation and tokenizer APIs are unavailable on a LiteRT-LM embedding engine; load with embeddingEngine: false for conversation.',
      );
    }
  }

  Future<LiteRtLmEmbeddingRuntimeSession> _ensureEmbedding() async {
    if (!(_modelParams?.liteRtLmEmbeddingEngine ?? false)) {
      throw LlamaUnsupportedException(
        'LiteRT-LM embeddings require loading with LiteRtLmModelParams(embeddingEngine: true); the active model is a conversation engine.',
      );
    }
    final existing = _embedding;
    if (existing != null) {
      return existing;
    }
    if (nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'Embedding creation has unsettled native resources.',
      );
    }
    final params = _modelParams!;
    final cache = _effectiveCacheDir(params) ?? liteRtLmNoCacheDirectory;
    final client = _clientFactory();
    final lease = _leaseCacheDirectory(cache, _modelPath!);
    _client = client;
    _cacheLease = lease;
    _embeddingPreparing = true;
    try {
      final session = await client.createEmbeddingSession(
        modelPath: _modelLink?.path ?? _modelPath!,
        backend: _activeBackend!,
        cacheDir: cache,
        maxInputLength: params.contextSize,
        numberOfThreads: params.numberOfThreads,
      );
      return _embedding = session;
    } catch (_) {
      _embeddingPreparing = false;
      if (client.nativeSettlement != LiteRtLmNativeSettlement.settled) {
        quarantineNativeResources();
      } else {
        _disposeClient();
      }
      rethrow;
    } finally {
      _embeddingPreparing = false;
    }
  }

  /// Probes a loaded embedding context; unknown contexts do no I/O.
  Future<LlamaEmbeddingCapabilities> embeddingCapabilities(
    int contextHandle,
  ) async {
    if (!_contextCreated ||
        contextHandle != _contextHandle ||
        !(_modelParams?.liteRtLmEmbeddingEngine ?? false)) {
      return const LlamaEmbeddingCapabilities();
    }
    return (await _ensureEmbedding()).capabilities;
  }

  /// Computes a preflighted batch on the worker, retaining the engine until settled.
  Future<List<List<double>>> embed(
    int contextHandle,
    List<List<LiteRtLmEmbeddingPart>> inputs, {
    required bool normalize,
  }) async {
    _checkContextHandle(contextHandle);
    if (inputs.isEmpty) {
      return [];
    }
    _cancelRequested = false;
    final session = await _ensureEmbedding();
    for (final input in inputs) {
      for (final part in input) {
        if (part.type == 1 && !session.capabilities.image ||
            part.type == 3 && !session.capabilities.audio) {
          throw LlamaUnsupportedException(
            'LiteRT-LM embedding bundle has no qualified processor for the requested modality.',
          );
        }
      }
    }
    if (_cancelRequested) {
      throw LlamaInferenceException(
        'LiteRT-LM embedding cancelled before native work.',
      );
    }
    final result = <List<double>>[];
    for (final input in inputs) {
      result.add(await session.compute(input, normalize: normalize));
      if (_cancelRequested) {
        throw LlamaInferenceException(
          'LiteRT-LM embedding cancelled after native work settled.',
        );
      }
    }
    return result;
  }

  /// Generates UTF-8 token byte chunks for [prompt].
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) => _explainUndeclaredFailure(
    _generate(contextHandle, prompt, params, parts: parts),
    hasImages: false,
    hasAudio: false,
    speculativeDecoding: params.isSpeculativeDecodingEnabled,
  );

  Stream<List<int>> _generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    resetPerformanceMetrics();
    _lastGenerationLimit = null;
    _checkContextHandle(contextHandle);
    _requireConversationEngine();
    if (parts?.any((part) => part is LlamaVideoContent) ?? false) {
      throw UnsupportedError(_liteRtLmVideoUnsupportedMessage);
    }
    if (_hasMediaParts(parts)) {
      throw UnsupportedError('LiteRtLmBackend does not support media parts.');
    }
    _validateGenerationParams(params);
    if (params.thinkingBudget != null) {
      throw LlamaUnsupportedException(
        'LiteRtLmBackend applies GenerationParams.thinkingBudget only to native '
        'chat generation, where LiteRT-LM renders the prompt and tracks the '
        "bundle's thinking channel; raw prompt generation has no thinking "
        'budget.',
      );
    }
    final controls = _resolveGenerationControls(params, enableThinking: false);

    _cancelRequested = false;
    if (params.maxTokens <= 0) {
      return;
    }

    final client = await _ensureClientForGeneration(params);
    if (_cancelRequested) {
      return;
    }
    final rawPrompt = _withoutLeadingStartToken(client, prompt);
    if (rawPrompt.isEmpty) {
      throw LlamaArgumentException(
        prompt.isEmpty
            ? 'LiteRtLmBackend raw prompt generation needs prompt text: the '
                  'prompt is empty.'
            : 'LiteRtLmBackend raw prompt generation needs prompt text: the '
                  "prompt holds only the model's start token, which the "
                  'LiteRT-LM runtime adds itself.',
        name: 'prompt',
        invalidValue: prompt,
      );
    }
    final backend =
        _activeBackend ?? _backendNameFor(_modelParams ?? const ModelParams());
    final loraPath = _activeTextLoraPath();
    void createConversation(String? template) => client.createConversation(
      promptTemplate: template,
      temperature: params.temp,
      // Zero-temperature LiteRT GPU sampling needs a single greedy candidate.
      topK: liteRtLmEffectiveTopK(temperature: params.temp, topK: params.topK),
      topP: params.topP,
      seed: params.seed ?? _defaultSamplerSeed(),
      npuBackend: backend == 'npu',
      loraPath: loraPath,
    );
    createConversation(liteRtLmRawPromptTemplate);
    if (_cancelRequested) {
      client.cancel();
      return;
    }

    final stopSequences = params.stopSequences
        .where((sequence) => sequence.isNotEmpty)
        .toList(growable: false);
    final sw = Stopwatch()..start();
    try {
      final stream = _applyStopSequences(
        client.generate(
          rawPrompt,
          maxOutputTokens: params.maxTokens,
          repetitionPenalty: controls.repetitionPenalty,
          presencePenalty: controls.presencePenalty,
        ),
        stopSequences,
        onStop: cancelGeneration,
      );
      await for (final chunk in stream) {
        if (_cancelRequested) {
          break;
        }
        yield chunk;
      }
      _lastGenerationLimit = _generationLimitOf(client);
    } finally {
      sw.stop();
      try {
        _lastMetrics = client.readMetrics(
          wallMilliseconds: sw.elapsedMilliseconds,
        );
      } catch (_) {
        _lastMetrics = null;
      }
    }
  }

  /// Returns [prompt] without a leading start token, which the runtime adds
  /// before every prompt, so that a prompt holding one does not get two. As
  /// llama.cpp does, this compares tokens: ordinary text that tokenizes to the
  /// start token is removed only when the rest of the prompt keeps its tokens.
  /// Special-token text, such as Gemma's `<bos>`, which the runtime reads as
  /// the token but [LiteRtLmRuntimeClientContract.tokenize] does not, is
  /// removed as text.
  String _withoutLeadingStartToken(
    LiteRtLmRuntimeClientContract client,
    String prompt,
  ) {
    final start = _startToken ??= () {
      final tokens = client.tokenize('', addSpecial: true);
      final text = tokens.isEmpty ? '' : client.detokenize(tokens);
      return (
        tokens: tokens,
        text: text,
        plainText: _sameTokens(
          client.tokenize(text, addSpecial: false),
          tokens,
        ),
      );
    }();
    if (start.text.isEmpty || !prompt.startsWith(start.text)) {
      return prompt;
    }
    final rest = prompt.substring(start.text.length);
    if (!start.plainText) {
      return rest;
    }
    final keepsTokens = _sameTokens(
      client.tokenize(prompt, addSpecial: false),
      [...start.tokens, ...client.tokenize(rest, addSpecial: false)],
    );
    return keepsTokens ? rest : prompt;
  }

  static bool _sameTokens(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Admits the actual native provider, rather than relying on setter exports.
  Future<void> prepareJsonSchemaChat() async {
    if (_jsonSchemaAdmitted) return;
    _requireConversationEngine();
    final qualified = _jsonSchemaQualifiedBackends();
    Never refuseBackend(String backend) => throw LlamaUnsupportedException(
      'Native JSON Schema chat is not qualified for the LiteRT-LM $backend '
      'backend on ${liteRtLmGateAbi()}'
      '${qualified.isEmpty ? '' : '; load with ${qualified.map((b) => 'ComputeDevice.$b').join(' or ')}'}.',
    );
    // The loaded backend includes the deprecated preferredBackend override.
    final loaded = _loadedBackend!;
    if (!qualified.contains(loaded)) refuseBackend(loaded);
    final routing = _templateRouting();
    final family = routing.family;
    final customTemplate = _modelParams?.chatTemplate;
    final String? promptTemplate;
    if (family?.id == 'qwen3' &&
        routing.rendersFamilyText &&
        (customTemplate == null || customTemplate == family!.template)) {
      promptTemplate = family!.template;
    } else if (family?.id == 'gemma4' &&
        !routing.rendersFamilyText &&
        customTemplate == null) {
      promptTemplate = null;
    } else {
      throw LlamaUnsupportedException(
        'Native JSON Schema chat is qualified only for Qwen3 with its canonical '
        'text template and Gemma 4 with its bundle template; custom templates '
        'and other model families are unqualified.',
      );
    }
    _cancelRequested = false;
    final client = await _ensureClientForGeneration(const GenerationParams());
    // An automatic GPU load can run on the CPU instead.
    if (!qualified.contains(_activeBackend)) refuseBackend(_activeBackend!);
    if (!client.supportsJsonSchemaConstraints) {
      throw LlamaUnsupportedException(
        'Native JSON Schema chat requires all constraint-provider and thinking-config symbols. '
        'Use the packaged LiteRT-LM $liteRtLmReleaseTag runtime through the default ABI-selecting client; '
        'model and platform qualification still applies.',
      );
    }
    if (!client.supportsFinishReasons) {
      throw LlamaUnsupportedException(
        'Native JSON Schema chat requires a runtime that reports finish '
        'reasons, so that a reply cut off by maxTokens reports length instead '
        'of success.',
      );
    }
    try {
      client.createConversation(
        promptTemplate: promptTemplate,
        temperature: 0,
        topK: 1,
        topP: 1,
        jsonSchemaConstraints: true,
      );
    } catch (error) {
      if (error is! StateError && error is! LlamaModelException) rethrow;
      throw LlamaUnsupportedException(
        'The loaded LiteRT-LM model cannot construct its JSON Schema provider; the model tokenizer or EOS may be incompatible.',
      );
    }
    // Only Gemma 4 kept the constraint after its reasoning channel on real
    // models; Qwen3 with thinking produced unconstrained text.
    _jsonSchemaThinking =
        family!.id == 'gemma4' &&
        client.supportsJsonSchemaThinking &&
        _bundleBoundsThinking();
    _jsonSchemaAdmitted = true;
  }

  /// Whether the admitted model may reason before its schema-constrained reply.
  bool get supportsJsonSchemaChatThinking =>
      _jsonSchemaAdmitted && _jsonSchemaThinking;

  /// Shares the normal chat lifecycle, with a validated per-request schema.
  Stream<List<int>> generateJsonSchemaChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    required String jsonSchema,
    bool enableThinking = false,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    validateJsonSchemaChatRequest(messages, params);
    jsonSchemaChatPayload(jsonDecode(jsonSchema) as Map<String, dynamic>);
    await prepareJsonSchemaChat();
    validateJsonSchemaChatRequest(
      messages,
      params,
      enableThinking: enableThinking && !_jsonSchemaThinking,
    );
    var outputStarted = false;
    try {
      await for (final chunk in _generateChat(
        contextHandle,
        messages,
        params,
        toolChoice: ToolChoice.none,
        enableThinking: enableThinking,
        chatTemplateKwargs: chatTemplateKwargs,
        templateNow: templateNow,
        jsonSchema: jsonSchema,
      )) {
        outputStarted = true;
        yield chunk;
      }
    } catch (error) {
      if (error is! StateError && error is! LlamaModelException) rethrow;
      // The pre-check should refuse every schema the provider cannot compile;
      // the provider reports one only as an INTERNAL send failure.
      if (!outputStarted && '$error'.contains('INTERNAL (13)')) {
        throw LlamaUnsupportedException(
          'The native LiteRT-LM runtime refused the JSON Schema request '
          'before generation (INTERNAL).',
        );
      }
      // Native diagnostics can echo the schema or model paths.
      throw LlamaInferenceException(
        'Native JSON Schema chat failed during constrained decoding.',
      );
    }
    // maxTokens <= 0 generates nothing, so no finish reason is reported.
    if (params.maxTokens > 0 &&
        !_cancelRequested &&
        _lastGenerationLimit == null &&
        _client?.lastFinishReason != LiteRtLmFinishReason.stop) {
      throw LlamaInferenceException(
        'Native JSON Schema chat ended without a stop or length finish '
        'reason, so the reply may be incomplete.',
      );
    }
  }

  /// Generates native chat from messages/tools instead of a rendered prompt.
  Stream<List<int>> generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<Map<String, dynamic>>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) => _explainUndeclaredFailure(
    _generateChat(
      contextHandle,
      messages,
      params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
    ),
    hasImages: _maxNumImagesFor(messages) != null,
    hasAudio: _hasAudioFor(messages),
    speculativeDecoding: params.isSpeculativeDecodingEnabled,
  );

  Stream<List<int>> _generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<Map<String, dynamic>>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
    String? jsonSchema,
  }) async* {
    resetPerformanceMetrics();
    _lastGenerationLimit = null;
    _checkContextHandle(contextHandle);
    _requireConversationEngine();
    if (messages.isEmpty) {
      throw ArgumentError('LiteRT-LM native chat generation needs a message.');
    }
    if (messages.last.role == LlamaChatRole.system) {
      throw UnsupportedError(
        'LiteRtLmBackend native chat generation cannot send a system message '
        'as the active turn.',
      );
    }
    if (toolChoice == ToolChoice.required) {
      throw UnsupportedError(
        'LiteRtLmBackend native chat generation does not expose '
        'ToolChoice.required enforcement. Use LlamaEngine.create so a '
        'compatible template can select its rendered-prompt fallback. For '
        'Hermes/Qwen, use ToolChoice.auto only when best-effort tool calling '
        'is acceptable, or use a grammar-capable backend such as llama.cpp '
        'for required tool calls.',
      );
    }
    if (parallelToolCalls) {
      throw UnsupportedError(
        'LiteRtLmBackend native chat generation does not expose a parallel '
        'tool-call switch.',
      );
    }
    _validateGenerationParams(params);
    final controls = _resolveGenerationControls(
      params,
      enableThinking: enableThinking,
    );

    _cancelRequested = false;
    if (params.maxTokens <= 0) {
      return;
    }

    final seed = _nativeConversationSeed(messages.take(messages.length - 1));
    final activeMessageJson = jsonEncode(
      _chatMessageToNativeJson(messages.last),
    );
    final maxNumImages = _maxNumImagesFor(messages);
    final enableAudio = _hasAudioFor(messages);
    final client = await _ensureClientForGeneration(
      params,
      maxNumImages: maxNumImages,
      enableAudio: enableAudio,
    );
    if (_cancelRequested) {
      return;
    }
    final backend =
        _activeBackend ?? _backendNameFor(_modelParams ?? const ModelParams());
    final nativeTools = _nativeToolsFor(toolChoice, tools);
    final loraPath = _activeTextLoraPath();
    final extraContext = _nativeExtraContext(
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
      enableThinking: enableThinking,
    );
    final routing = _templateRouting();
    final promptTemplate =
        maxNumImages == null && !enableAudio && routing.rendersFamilyText
        ? _modelParams?.chatTemplate ?? routing.family?.template
        : null;
    void createConversation(String? template, {bool seeded = true}) =>
        client.createConversation(
          promptTemplate: template,
          systemMessage: seeded ? seed.systemMessage : null,
          messages: seeded ? seed.messages : null,
          tools: seeded ? nativeTools : null,
          extraContext: seeded ? extraContext : null,
          temperature: params.temp,
          // Zero-temperature LiteRT GPU sampling needs a single greedy
          // candidate.
          topK: liteRtLmEffectiveTopK(
            temperature: params.temp,
            topK: params.topK,
          ),
          topP: params.topP,
          seed: params.seed ?? _defaultSamplerSeed(),
          npuBackend: backend == 'npu',
          loraPath: loraPath,
          jsonSchemaConstraints: jsonSchema != null,
        );
    if (promptTemplate == null) {
      _createBundleTemplateConversation(
        client,
        create: createConversation,
        createProbe: (template) => createConversation(template, seeded: false),
      );
    } else {
      createConversation(promptTemplate);
    }
    if (_cancelRequested) {
      client.cancel();
      return;
    }

    final stopSequences = params.stopSequences
        .where((sequence) => sequence.isNotEmpty)
        .toList(growable: false);
    final sw = Stopwatch()..start();
    var outputStarted = false;
    try {
      final stream = _applyStopSequences(
        client
            .generateMessageJson(
              activeMessageJson,
              jsonSchema: jsonSchema,
              visualTokenBudget: maxNumImages == null
                  ? null
                  : client.resolveDefaultVisualTokenBudget(
                      _gemma4DefaultVisualTokenBudget,
                    ),
              maxOutputTokens: params.maxTokens,
              repetitionPenalty: controls.repetitionPenalty,
              presencePenalty: controls.presencePenalty,
              thinkingTokenBudget: controls.thinkingTokenBudget,
            )
            .map((chunk) {
              outputStarted = true;
              return chunk;
            }),
        stopSequences,
        onStop: cancelGeneration,
      );
      await for (final chunk in stream) {
        if (_cancelRequested) {
          break;
        }
        yield chunk;
      }
      _lastGenerationLimit = _generationLimitOf(client);
    } on StateError catch (error, stackTrace) {
      _throwSendFailure(
        error,
        error.message,
        stackTrace,
        outputStarted: outputStarted,
        promptTemplate: promptTemplate,
        withNote: StateError.new,
      );
    } on LiteRtLmSendFailureException catch (error, stackTrace) {
      _throwSendFailure(
        error,
        error.message,
        stackTrace,
        outputStarted: outputStarted,
        promptTemplate: promptTemplate,
        withNote: (message) =>
            LiteRtLmSendFailureException(message, error.details),
      );
    } finally {
      sw.stop();
      // A fresh conversation can retain degraded image-generation state after
      // cancellation. Reinitialize the engine on its next use, only after the
      // callback family has drained; this costs one engine initialization.
      if (maxNumImages != null &&
          (_cancelRequested ||
              client.lastFinishReason == LiteRtLmFinishReason.cancelled) &&
          nativeSettlement == LiteRtLmNativeSettlement.settled) {
        _recreateClientAfterImageCancellation = true;
      }
      try {
        _lastMetrics = client.readMetrics(
          wallMilliseconds: sw.elapsedMilliseconds,
        );
      } catch (_) {
        _lastMetrics = null;
      }
    }
  }

  /// Rethrows [error], a failed native send, naming the template in use when
  /// the failure came before any output and that template is known not to
  /// read the content the runtime gives it.
  ///
  /// The runtime reports a template that fails to render only as a failed
  /// send, and from v0.18 it renders with content as a list of parts.
  Never _throwSendFailure(
    Object error,
    String message,
    StackTrace stackTrace, {
    required bool outputStarted,
    required Object Function(String message) withNote,
    String? promptTemplate,
  }) {
    final String? note;
    if (outputStarted) {
      note = null;
    } else if (promptTemplate == null) {
      note = _bundleTemplateMisreadsContent
          ? 'The chat template of this bundle does not read message content '
                'as the runtime passes it: from LiteRT-LM v0.18 that is a '
                'list of {"type": "text", "text": ...} parts, and llamadart '
                'could not adapt the template, so it can fail here. Use a '
                'bundle whose template reads content parts.'
          : null;
    } else {
      note = _modelParams?.chatTemplate == null
          ? null
          : 'ModelParams.chatTemplate is set: from LiteRT-LM v0.18 the '
                'runtime passes each message content to the template as a '
                'list of {"type": "text", "text": ...} parts, so a template '
                'that reads content as a string can fail here.';
    }
    if (note == null) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    Error.throwWithStackTrace(withNote('$message $note'), stackTrace);
  }

  /// Creates a conversation that renders with the bundle's own template.
  ///
  /// [create] creates the conversation of the request and [createProbe] one
  /// with the same session and no messages, each with the bundle template
  /// when its argument is null and with the given template otherwise.
  ///
  /// From LiteRT-LM v0.18 the runtime passes every template content as a list
  /// of parts and no longer turns a single text part back into a string for a
  /// template that reads content as one. The first use of a loaded model
  /// decides, once, whether its conversations use
  /// [liteRtLmTextContentAdapter] around the template read from the bundle.
  void _createBundleTemplateConversation(
    LiteRtLmRuntimeClientContract client, {
    required void Function(String? template) create,
    required void Function(String? template) createProbe,
  }) {
    if (!_bundleTemplateProbed) {
      _probeBundleTemplate(client, createProbe);
      _bundleTemplateProbed = true;
    }
    create(_bundleTemplateAdapter);
  }

  /// Renders [liteRtLmContentShapeProbeMessage] alone with the bundle template
  /// and, when its text does not come out as text, with the adapter.
  ///
  /// A template that renders the text is left alone. Otherwise the adapter is
  /// adopted when it renders the text; when it does not, or the template
  /// cannot be read from the bundle, the bundle template stays and a warning
  /// says so.
  void _probeBundleTemplate(
    LiteRtLmRuntimeClientContract client,
    void Function(String? template) createProbe,
  ) {
    if (!client.supportsMessageRendering) {
      return;
    }
    // A failed native render is a StateError from the legacy client and a
    // LlamaModelException from the C API 1.0 client.
    bool rendersProbeText() {
      try {
        return liteRtLmRendersProbeText(
          client.renderMessageToString(liteRtLmContentShapeProbeMessage),
        );
      } on StateError {
        return false;
      } on LlamaModelException {
        return false;
      }
    }

    createProbe(null);
    if (rendersProbeText()) {
      return;
    }
    final bundleTemplate = _readBundleChatTemplate(_modelPath!);
    if (bundleTemplate != null) {
      final adapter = liteRtLmTextContentAdapter(bundleTemplate);
      try {
        createProbe(adapter);
        if (rendersProbeText()) {
          _bundleTemplateAdapter = adapter;
          return;
        }
      } on StateError {
        // The legacy runtime rejected the adapted template.
      } on LlamaModelException {
        // The C API 1.0 runtime rejected the adapted template.
      } on LlamaUnsupportedException {
        // The runtime takes no conversation template.
      }
    }
    _bundleTemplateMisreadsContent = true;
    _warn(
      'The chat template of this LiteRT-LM bundle does not render the text '
      'of a message as the runtime passes it: from LiteRT-LM v0.18 that is '
      'a list of {"type": "text", "text": ...} parts. llamadart could not '
      'adapt the template, so requests can fail or get degraded replies. '
      'Use a bundle whose template reads content parts.',
    );
  }

  /// Cancels the active LiteRT-LM conversation if one is running.
  void cancelGeneration() {
    _cancelRequested = true;
    _client?.cancel();
    // Late subscription cancels can follow a settled image turn, so cancelling
    // an idle image-enabled engine also costs one reinitialization before reuse.
    if (_activeVisionEnabled == true &&
        (_activeMaxNumImages ?? 0) > 0 &&
        nativeSettlement == LiteRtLmNativeSettlement.settled) {
      _recreateClientAfterImageCancellation = true;
    }
  }

  /// Tokenizes text with the loaded LiteRT-LM model tokenizer.
  Future<List<int>> tokenize(
    int modelHandle,
    String text,
    bool addSpecial,
  ) async {
    _checkModelHandle(modelHandle);
    final client = await _ensureClientForRuntime();
    return client.tokenize(text, addSpecial: addSpecial);
  }

  /// Tokenizes [prompt] as native prefill reads it: without a leading start
  /// token, which the runtime then adds once.
  Future<List<int>> tokenizeRuntimePrompt(
    int modelHandle,
    String prompt,
  ) async {
    _checkModelHandle(modelHandle);
    final client = await _ensureClientForRuntime();
    return client.tokenize(
      _withoutLeadingStartToken(client, prompt),
      addSpecial: true,
    );
  }

  /// Detokenizes token IDs with the loaded LiteRT-LM model tokenizer.
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens,
    bool special,
  ) async {
    _checkModelHandle(modelHandle);
    if (special) {
      throw UnsupportedError(
        'LiteRtLmBackend does not support detokenizing special tokens.',
      );
    }
    final client = await _ensureClientForRuntime();
    return client.detokenize(tokens);
  }

  /// What the loaded bundle declares in its section metadata: image and
  /// audio input, and a speculative decoding drafter.
  ///
  /// Null when no model is loaded or the runtime cannot read the
  /// declaration.
  ({bool vision, bool audio, bool speculativeDecoding})? bundleCapabilities() {
    final modelPath = _modelPath;
    if (!_modelLoaded || modelPath == null) {
      return null;
    }
    if (_bundleCapabilitiesRead) {
      return _bundleCapabilities;
    }
    try {
      _bundleCapabilities = _readBundleCapabilities(
        _modelLink?.path ?? modelPath,
      );
      if (_bundleCapabilities == null) {
        _warn(
          'The LiteRT-LM runtime did not report the bundle capabilities; '
          'reporting no image or audio input.',
        );
      }
    } catch (error) {
      _warn('Could not read the LiteRT-LM bundle capabilities.', error);
    }
    _bundleCapabilitiesRead = true;
    return _bundleCapabilities;
  }

  /// Reports a runtime failure, before the first chunk, of a request that
  /// needs an image or audio encoder or a speculative drafter the loaded
  /// bundle declares absent as that missing piece.
  ///
  /// The declaration only explains a failure and never rejects a request
  /// itself.
  Stream<List<int>> _explainUndeclaredFailure(
    Stream<List<int>> generation, {
    required bool hasImages,
    required bool hasAudio,
    required bool speculativeDecoding,
  }) async* {
    var produced = false;
    try {
      await for (final chunk in generation) {
        produced = true;
        yield chunk;
      }
    } catch (error, stackTrace) {
      if (produced ||
          _cancelRequested ||
          error is UnsupportedError ||
          error is ArgumentError ||
          error is LlamaUnsupportedException) {
        rethrow;
      }
      final bundle = bundleCapabilities();
      final missing = [
        if (hasImages && bundle?.vision == false) 'image encoder',
        if (hasAudio && bundle?.audio == false) 'audio encoder',
        if (speculativeDecoding && bundle?.speculativeDecoding == false)
          'speculative decoding drafter',
      ];
      if (missing.isEmpty) {
        rethrow;
      }
      Error.throwWithStackTrace(
        UnsupportedError(
          'LiteRtLmBackend: the runtime could not run this request, and the '
          'loaded bundle declares no ${missing.join(' or ')}. Use a bundle '
          'with it, or leave it out of the request. Runtime error: $error',
        ),
        stackTrace,
      );
    }
  }

  /// Returns metadata from the bundle name, declarations and template override.
  Map<String, String> getMetadata(int modelHandle) {
    _checkModelHandle(modelHandle);
    final modelPath = _modelPath;
    final modelName = modelPath == null
        ? null
        : File(modelPath).uri.pathSegments.last;
    final metadata = <String, String>{
      'general.architecture': 'litert-lm',
      'general.file_type': 'litertlm',
    };
    if (modelName != null) {
      metadata['general.name'] = modelName;
    }
    if (_modelParams case final params?) {
      metadata['llm.context_length'] = params.contextSize.toString();
    }
    if (modelPath == null) {
      return metadata;
    }
    final routing = _templateRouting();
    if (routing.family case final family?) {
      metadata['tokenizer.ggml.bos_token'] = family.bosToken;
      metadata['tokenizer.ggml.eos_token'] = family.eosToken;
    }
    final parsingTemplate =
        _modelParams?.chatTemplate ?? routing.family?.template;
    if (parsingTemplate == null) {
      return metadata;
    }
    final runtimeTemplate = routing.rendersFamilyText
        ? parsingTemplate
        : _readBundleChatTemplate(modelPath) ?? parsingTemplate;
    metadata['tokenizer.chat_template'] = runtimeTemplate;
    if (runtimeTemplate != parsingTemplate) {
      metadata[parsingChatTemplateMetadataKey] = parsingTemplate;
    }
    return metadata;
  }

  /// The built-in template Dart parses the loaded bundle with, and whether
  /// the runtime renders it, or [ModelParams.chatTemplate], for text-only
  /// chats instead of the bundle's own template.
  ///
  /// Older Qwen3 bundles use a native ChatML template that ignores
  /// enable_thinking, so text-only chats render the template the Dart parser
  /// uses, which closes the reasoning prefix when thinking is off. Media and
  /// every other family keep the native model-specific processor.
  ({LiteRtLmChatTemplate? family, bool rendersFamilyText}) _templateRouting() {
    final modelName = File(
      _modelPath!,
    ).uri.pathSegments.last.toLowerCase().replaceAll('_', '-');
    final filenameTemplate = _resolveBuiltinTemplate(modelName);
    final unnamedTemplate = filenameTemplate == null
        ? _resolveUnnamedQwen3Template()
        : null;
    return (
      family: filenameTemplate ?? unnamedTemplate,
      rendersFamilyText:
          RegExp(r'qwen-?3(?:[^.\d]|$)').hasMatch(modelName) ||
          unnamedTemplate != null,
    );
  }

  /// Resolves the built-in chat template for [modelName], if any.
  ///
  /// `.litertlm` bundles don't expose their chat template through the native
  /// FFI, so the family is detected from the bundle filename and mapped to one
  /// of the templates in [kLiteRtLmChatTemplates]. Callers can always override
  /// the result with [ModelParams.chatTemplate].
  LiteRtLmChatTemplate? _resolveBuiltinTemplate(String modelName) {
    final normalized = modelName.toLowerCase().replaceAll('_', '-');
    for (final template in kLiteRtLmChatTemplates) {
      if (template.matches(normalized)) {
        return template;
      }
    }
    return null;
  }

  // Generic ChatML and thinking markers are shared by several Qwen families.
  // Only a family declaration or the complete canonical template opts in.
  LiteRtLmChatTemplate? _resolveUnnamedQwen3Template() {
    final metadata = readLiteRtLmBundleMetadata(_modelPath!);
    final qwen3 = kLiteRtLmChatTemplates.singleWhere(
      (item) => item.id == 'qwen3',
    );
    final template = _modelParams?.chatTemplate ?? metadata?.chatTemplate;
    if (metadata?.isQwen3 == true ||
        (template != null &&
            template.trimLeft().startsWith(qwen3.template.trim()))) {
      return qwen3;
    }
    return null;
  }

  /// Returns the active backend name.
  String getActiveBackendName() {
    final backend =
        _activeBackend ?? liteRtLmDefaultNativeBackendForCurrentPlatform();
    return 'LiteRT-LM $backend';
  }

  /// Returns the backend choices available on this platform.
  List<String> getAvailableBackendInfo() {
    return liteRtLmAvailableNativeBackendsForCurrentPlatform();
  }

  /// Returns the resolved GPU layer count analogue for LiteRT-LM.
  int? getResolvedGpuLayers() {
    final backend =
        _activeBackend ?? liteRtLmDefaultNativeBackendForCurrentPlatform();
    return backend == liteRtLmCpuBackend ? 0 : ModelParams.maxGpuLayers;
  }

  /// Invalidates metrics when an admitted generation produces no runtime run.
  void resetPerformanceMetrics() {
    _lastMetrics = null;
  }

  /// Returns the most recent LiteRT-LM performance metrics.
  BackendPerfContextData? getPerformanceContext(int contextHandle) {
    _checkContextHandle(contextHandle);
    final metrics = _lastMetrics;
    if (metrics == null) {
      return null;
    }
    final promptEvalMs = _millisecondsFromTps(
      metrics.inputTokens,
      metrics.prefillTokensPerSecond,
    );
    final evalMs = _millisecondsFromTps(
      metrics.outputTokens,
      metrics.decodeTokensPerSecond,
    );
    return BackendPerfContextData(
      loadMs: (metrics.initSeconds ?? 0) * 1000.0,
      promptEvalMs: promptEvalMs,
      evalMs: evalMs,
      sampleMs: 0,
      promptEvalTokens: metrics.inputTokens,
      evalTokens: metrics.outputTokens,
      sampleCount: metrics.outputTokens,
      reusedGraphs: 0,
    );
  }

  /// Returns whether this runtime can use a GPU LiteRT-LM backend.
  bool getGpuSupport() {
    return liteRtLmNativeGpuSupportedOnCurrentPlatform();
  }

  /// Returns VRAM information when the backend can expose it.
  ({int total, int free}) getVramInfo() => (total: 0, free: 0);

  /// Applies a native chat template.
  String applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) {
    _checkModelHandle(modelHandle);
    _requireConversationEngine();
    final metadata = getMetadata(modelHandle);
    final result = ChatTemplateEngine.render(
      templateSource:
          metadata[parsingChatTemplateMetadataKey] ??
          metadata['tokenizer.chat_template'],
      messages: messages.map(_messageFromTemplateMap).toList(growable: false),
      metadata: metadata,
      addAssistant: addAssistant,
      customTemplate: customTemplate,
    );
    return result.prompt;
  }

  /// Releases all service-owned native resources.
  void dispose() {
    _disposeContextRuntimeState();
    _modelLink?.dispose();
    _modelLink = null;
    _modelPath = null;
    _modelParams = null;
    _activeBackend = null;
    _loadedBackend = null;
    _workingAudioBackend = null;
    _modelHandle = null;
    _contextHandle = null;
    _modelLoaded = false;
    _contextCreated = false;
  }

  void _disposeContextRuntimeState() {
    _disposeClient();
    _activeSpeculativeDecoding = null;
    _activeMaxNumImages = null;
    _activeVisionEnabled = null;
    _activeAudioEnabled = null;
    _lastMetrics = null;
    _cancelRequested = false;
  }

  Future<LiteRtLmRuntimeClientContract> _ensureClientForGeneration(
    GenerationParams params, {
    int? maxNumImages,
    bool? enableAudio,
  }) {
    return _ensureClientForRuntime(
      speculativeDecoding: params.isSpeculativeDecodingEnabled,
      maxNumImages: maxNumImages,
      enableVision: maxNumImages != null,
      enableAudio: enableAudio,
    );
  }

  Future<LiteRtLmRuntimeClientContract> _ensureClientForRuntime({
    bool? speculativeDecoding,
    int? maxNumImages,
    bool? enableVision,
    bool? enableAudio,
  }) async {
    _requireConversationEngine();
    final modelPath = _modelPath;
    final modelParams = _modelParams;
    if (modelPath == null || modelParams == null) {
      throw StateError('No LiteRT-LM model is loaded.');
    }

    final resolvedSpeculativeDecoding =
        speculativeDecoding ?? _activeSpeculativeDecoding ?? false;
    final resolvedVisionEnabled = enableVision ?? _activeVisionEnabled ?? false;
    // The runtime rejects an image count without a vision encoder, so a turn
    // whose history holds no images drops the previous turn's count.
    final resolvedMaxNumImages = resolvedVisionEnabled
        ? maxNumImages ?? _activeMaxNumImages
        : null;
    final resolvedAudioEnabled = enableAudio ?? _activeAudioEnabled ?? false;
    final backend = _activeBackend ?? _backendNameFor(modelParams);
    final existing = _client;
    if (existing != null &&
        !_recreateClientAfterImageCancellation &&
        (speculativeDecoding == null ||
            _activeSpeculativeDecoding == resolvedSpeculativeDecoding) &&
        (maxNumImages == null || _activeMaxNumImages == resolvedMaxNumImages) &&
        (enableVision == null ||
            _activeVisionEnabled == resolvedVisionEnabled) &&
        (enableAudio == null || _activeAudioEnabled == resolvedAudioEnabled) &&
        _activeBackend == backend) {
      return existing;
    }

    _disposeClient();
    _activeSpeculativeDecoding = null;
    _activeMaxNumImages = null;
    _activeVisionEnabled = null;
    _activeAudioEnabled = null;
    final responseThinkingTags = _responseThinkingTagsForModel(modelPath);
    final cacheDir = _effectiveCacheDir(modelParams);
    final runtimeModelPath = _modelLink?.path ?? modelPath;
    final cacheLease = _leaseCacheDirectory(cacheDir, runtimeModelPath);

    _LiteRtLmEngineOptions engineOptions(String engineBackend) {
      final vision = resolvedVisionEnabled
          ? _visionBackendName(engineBackend)
          : null;
      final audio = resolvedAudioEnabled
          ? (engineBackend == backend ? _workingAudioBackend : null) ??
                _visionBackendName(engineBackend)
          : null;
      final usesGpu = [
        engineBackend,
        vision,
        audio,
      ].contains(liteRtLmGpuBackend);
      return (
        vision: vision,
        audio: audio,
        usesGpu: usesGpu,
        runtimeCacheDir:
            cacheDir ??
            _modelLink?.runtimeCacheDirectory() ??
            liteRtLmUnlinkedCacheDirectory(
              modelPath,
              gpu: usesGpu,
              textOnly:
                  !resolvedVisionEnabled &&
                  !resolvedAudioEnabled &&
                  !resolvedSpeculativeDecoding,
            ),
      );
    }

    var initializationUnsettled = false;

    Future<LiteRtLmRuntimeClientContract> initializeClient(
      String engineBackend,
      String? visionBackend,
      String? audioBackend,
      String? cacheDirectory,
    ) async {
      _pruneProgramCaches(
        cacheDir,
        modelParams.liteRtLmMaxProgramCacheBytes,
        cacheLease,
      );
      final client = _clientFactory();
      _client = client;
      _cacheLease = cacheLease;
      _nativeInitializationPending = true;
      try {
        client.configureResponseThinkingTags(
          startTag: responseThinkingTags.startTag,
          endTag: responseThinkingTags.endTag,
        );
        await client.initialize(
          modelPath: runtimeModelPath,
          backend: engineBackend,
          visionBackend: visionBackend,
          audioBackend: audioBackend,
          maxTokens: modelParams.contextSize,
          maxNumImages: resolvedMaxNumImages,
          cacheDir: cacheDirectory,
          speculativeDecoding: resolvedSpeculativeDecoding,
          minLogLevel: _liteRtLmMinLogLevel(_logLevel),
          activationDataType: modelParams.liteRtLmActivationDataType,
          prefillChunkSize: modelParams.liteRtLmPrefillChunkSize,
          parallelFileSectionLoading:
              modelParams.liteRtLmParallelFileSectionLoading,
          dispatchLibDir: modelParams.liteRtLmDispatchLibDir,
          numberOfThreads: modelParams.numberOfThreads == 0
              ? null
              : modelParams.numberOfThreads,
        );
        _nativeInitializationPending = false;
        return client;
      } catch (_) {
        _nativeInitializationPending = false;
        if (_retainUnsettledClient(client, cacheLease)) {
          initializationUnsettled = true;
          rethrow;
        }
        try {
          client.dispose();
        } catch (_) {
          // Preserve the initialization error reported by the runtime.
        }
        if (identical(_client, client)) {
          _client = null;
          _cacheLease = null;
        }
        rethrow;
      }
    }

    Future<({LiteRtLmRuntimeClientContract client, String? audioBackend})>
    createEngine(String engineBackend, _LiteRtLmEngineOptions options) async {
      final runtimeCacheDir = options.runtimeCacheDir;
      try {
        return (
          client: await initializeClient(
            engineBackend,
            options.vision,
            options.audio,
            runtimeCacheDir,
          ),
          audioBackend: options.audio,
        );
      } catch (initialError, initialStackTrace) {
        if (initializationUnsettled) rethrow;
        // The GPU backend fails engine creation on a cache it rejects, such
        // as a truncated weight cache, when it cannot write a new one.
        final uncachedDir =
            initialError is LiteRtLmEngineCreateError && runtimeCacheDir == null
            ? liteRtLmUnlinkedCacheDirectory(
                modelPath,
                gpu: options.usesGpu,
                textOnly: false,
              )
            : null;
        final canRetryWithCpuAudio =
            options.audio != null && options.audio != liteRtLmCpuBackend;
        if (uncachedDir == null && !canRetryWithCpuAudio) {
          rethrow;
        }

        try {
          if (uncachedDir != null) {
            return (
              client: await initializeClient(
                engineBackend,
                options.vision,
                options.audio,
                uncachedDir,
              ),
              audioBackend: options.audio,
            );
          }
          return (
            client: await initializeClient(
              engineBackend,
              options.vision,
              liteRtLmCpuBackend,
              runtimeCacheDir,
            ),
            audioBackend: liteRtLmCpuBackend,
          );
        } catch (_) {
          Error.throwWithStackTrace(initialError, initialStackTrace);
        }
      }
    }

    final options = engineOptions(backend);
    late ({LiteRtLmRuntimeClientContract client, String? audioBackend}) engine;
    var engineBackend = backend;
    var created = false;
    try {
      try {
        engine = await createEngine(backend, options);
      } catch (gpuError, gpuStackTrace) {
        if (initializationUnsettled) rethrow;
        if (!_mayRetryAutoGpuOnCpu(modelParams, backend)) {
          rethrow;
        }
        _warn(
          'LiteRT-LM could not create a GPU engine under ComputeDevice.auto; '
          'retrying on the CPU. Load with ComputeDevice.cpu to skip the GPU, '
          'or ComputeDevice.gpu to fail instead.',
          gpuError,
        );
        try {
          engine = await createEngine(
            liteRtLmCpuBackend,
            engineOptions(liteRtLmCpuBackend),
          );
        } catch (_) {
          Error.throwWithStackTrace(gpuError, gpuStackTrace);
        }
        engineBackend = liteRtLmCpuBackend;
      }
      created = true;
    } on LiteRtLmEngineCreateError catch (error, stackTrace) {
      // From LiteRT-LM v0.18 a cache directory the runtime cannot write fails
      // engine creation on every backend, with no reason reported.
      final String cacheHint;
      if (modelParams.liteRtLmCacheDir != null) {
        cacheHint =
            ' Engine creation also fails when the runtime cannot write '
            '${modelParamsTypeName(modelParams)}.'
            '${liteRtLmOptionName(modelParams, 'liteRtLmCacheDir')}.';
      } else if (options.runtimeCacheDir != null &&
          options.runtimeCacheDir != liteRtLmNoCacheDirectory) {
        cacheHint =
            ' Engine creation also fails when the runtime cannot write its '
            'cache directory; set LiteRtLmModelParams.cacheDir '
            '(ModelParams.liteRtLmCacheDir) to one it can write.';
      } else {
        cacheHint = '';
      }
      final device = modelParams.device;
      if (device != ComputeDevice.gpu && device != ComputeDevice.npu) {
        Error.throwWithStackTrace(
          LlamaModelException('${error.message}$cacheHint'),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(
        LlamaUnsupportedException(
          'ComputeDevice.${device.name} was requested, but LiteRT-LM could '
          'not create a $backend engine on ${Platform.operatingSystem}. '
          'Either the $backend backend cannot start here or the model file '
          'cannot be loaded, and the runtime may not say which. '
          '${error.message}$cacheHint Load with ComputeDevice.cpu to tell '
          'them apart.',
        ),
        stackTrace,
      );
    } finally {
      if (!created && !initializationUnsettled) {
        cacheLease?.release();
      }
    }
    _client = engine.client;
    _cacheLease = cacheLease;
    if (resolvedAudioEnabled) {
      _workingAudioBackend = engine.audioBackend;
    }
    _activeSpeculativeDecoding = resolvedSpeculativeDecoding;
    _activeMaxNumImages = resolvedMaxNumImages;
    _activeVisionEnabled = resolvedVisionEnabled;
    _activeAudioEnabled = resolvedAudioEnabled;
    _activeBackend = engineBackend;
    return engine.client;
  }

  ({String startTag, String endTag}) _responseThinkingTagsForModel(
    String modelPath,
  ) {
    final modelName = File(modelPath).uri.pathSegments.last;
    final template = _resolveBuiltinTemplate(modelName);
    return (
      startTag:
          template?.thinkingStartTag ??
          LiteRtLmChannelAssembler.gemma4ThinkingStartTag,
      endTag:
          template?.thinkingEndTag ??
          LiteRtLmChannelAssembler.gemma4ThinkingEndTag,
    );
  }

  Stream<List<int>> _applyStopSequences(
    Stream<String> source,
    List<String> stopSequences, {
    required void Function() onStop,
  }) async* {
    if (stopSequences.isEmpty) {
      await for (final chunk in source) {
        if (chunk.isNotEmpty) {
          yield utf8.encode(chunk);
        }
      }
      return;
    }

    final keepChars =
        stopSequences
            .map((sequence) => sequence.length)
            .reduce((a, b) => a > b ? a : b) -
        1;
    var pending = '';
    var stopped = false;

    await for (final chunk in source) {
      pending += chunk;
      final stopIndex = _firstStopIndex(pending, stopSequences);
      if (stopIndex >= 0) {
        final allowed = pending.substring(0, stopIndex);
        if (allowed.isNotEmpty) {
          yield utf8.encode(allowed);
        }
        stopped = true;
        onStop();
        break;
      }

      final emitLength = pending.length - keepChars;
      if (emitLength > 0) {
        final allowed = pending.substring(0, emitLength);
        pending = pending.substring(emitLength);
        if (allowed.isNotEmpty) {
          yield utf8.encode(allowed);
        }
      }
    }

    if (!stopped && pending.isNotEmpty) {
      yield utf8.encode(pending);
    }
  }

  bool _hasMediaParts(List<LlamaContentPart>? parts) {
    if (parts == null) {
      return false;
    }
    return parts.any(
      (part) =>
          part is LlamaImageContent ||
          part is LlamaAudioContent ||
          part is LlamaVideoContent,
    );
  }

  int? _maxNumImagesFor(List<LlamaChatMessage> messages) {
    final imageCount = messages
        .expand((message) => message.parts)
        .whereType<LlamaImageContent>()
        .length;
    return imageCount == 0 ? null : imageCount;
  }

  bool _hasAudioFor(List<LlamaChatMessage> messages) {
    return messages
        .expand((message) => message.parts)
        .whereType<LlamaAudioContent>()
        .isNotEmpty;
  }

  /// Whether a GPU engine that failed to start may retry on the CPU: only
  /// when neither the load nor the context selected a device.
  bool _mayRetryAutoGpuOnCpu(ModelParams params, String backend) =>
      backend == liteRtLmGpuBackend &&
      _automaticBackend &&
      params.device == ComputeDevice.auto &&
      params.liteRtLmBackend.nativeName == null;

  String _visionBackendName(String backend) {
    if (backend == liteRtLmNpuBackend) {
      return liteRtLmCpuBackend;
    }
    return backend;
  }

  Map<String, dynamic> _nativeImageContent(LlamaImageContent part) {
    final imagePath = part.path;
    if (imagePath != null) {
      if (imagePath.isEmpty) {
        throw ArgumentError.value(imagePath, 'path', 'must not be empty');
      }
      if (!File(imagePath).existsSync()) {
        throw ArgumentError('LiteRT-LM image file does not exist: $imagePath');
      }
      return {'type': 'image', 'path': imagePath};
    }

    final imageBytes = part.bytes;
    if (imageBytes != null) {
      if (imageBytes.isEmpty) {
        throw ArgumentError.value(imageBytes, 'bytes', 'must not be empty');
      }
      if (part.width != null || part.height != null) {
        throw UnsupportedError(
          'LiteRtLmBackend does not support raw RGB image bytes yet. Pass a '
          'local encoded image file path or encoded image bytes.',
        );
      }
      return {'type': 'image', 'blob': base64Encode(imageBytes)};
    }

    final imageUrl = part.url;
    if (imageUrl != null) {
      throw LlamaUnsupportedException(
        'LiteRtLmBackend does not support remote image URLs '
        '(LlamaImageContent.url). Pass a local image file path or encoded '
        'image bytes.',
      );
    }

    throw ArgumentError(
      'LiteRT-LM image content must provide a local path or encoded bytes.',
    );
  }

  Map<String, dynamic> _nativeAudioContent(LlamaAudioContent part) {
    final audioPath = part.path;
    if (audioPath != null) {
      if (audioPath.isEmpty) {
        throw ArgumentError.value(audioPath, 'path', 'must not be empty');
      }
      if (!File(audioPath).existsSync()) {
        throw ArgumentError('LiteRT-LM audio file does not exist: $audioPath');
      }
      return {'type': 'audio', 'path': audioPath};
    }

    final audioBytes = part.bytes;
    if (audioBytes != null) {
      if (audioBytes.isEmpty) {
        throw ArgumentError.value(audioBytes, 'bytes', 'must not be empty');
      }
      return {'type': 'audio', 'blob': base64Encode(audioBytes)};
    }

    if (part.samples != null) {
      throw UnsupportedError(
        'LiteRtLmBackend does not support raw PCM audio samples yet. Pass an '
        'encoded audio file path or encoded audio bytes.',
      );
    }

    throw ArgumentError(
      'LiteRT-LM audio content must provide a local path or encoded bytes.',
    );
  }

  int _firstStopIndex(String text, List<String> stopSequences) {
    var stopIndex = -1;
    for (final stop in stopSequences) {
      final index = text.indexOf(stop);
      if (index >= 0 && (stopIndex < 0 || index < stopIndex)) {
        stopIndex = index;
      }
    }
    return stopIndex;
  }

  /// The backend for a GPU request: the GPU unless every Vulkan device is
  /// software, on which the GPU backend can silently return wrong text
  /// (#572). Then an automatic choice runs on the CPU and an explicit one
  /// fails.
  String _gpuBackendForAdapters({required bool automatic}) {
    final software = _probeGpuAdapters?.call().softwareOnly;
    if (software == null) return liteRtLmGpuBackend;
    final names = software.map((device) => '"${device.name}"').join(', ');
    if (automatic) {
      _warn(
        'LiteRT-LM found only software Vulkan devices ($names) under '
        'ComputeDevice.auto; running on the CPU. Install the GPU vendor\'s '
        'Vulkan driver to use the GPU.',
      );
      return liteRtLmCpuBackend;
    }
    throw LlamaUnsupportedException(
      'LiteRT-LM GPU on ${liteRtLmGateAbi()} needs a hardware Vulkan '
      'device, but every Vulkan device here is a software rasterizer '
      '(VK_PHYSICAL_DEVICE_TYPE_CPU: $names), on which the GPU backend can '
      'return wrong text. Install the GPU vendor\'s Vulkan driver, or load '
      'with ComputeDevice.cpu.',
    );
  }

  String _resolveBackendName(ModelParams params, {String? backendOverride}) {
    final device = params.device;
    if (device != ComputeDevice.auto) {
      if (backendOverride != null) {
        throw LlamaUnsupportedException(
          'ModelParams.device ${device.name} cannot be combined with the '
          'deprecated LiteRtLmBackend(preferredBackend: $backendOverride). '
          'Set only ModelParams.device.',
        );
      }
      liteRtLmEnsureDeviceAvailable(device);
      return _deviceBackendName(device)!;
    }
    final backend =
        normalizeLiteRtLmNativeBackendOverride(backendOverride) ??
        _backendNameFor(params);
    liteRtLmEnsureNativeBackendSupported(backend);
    final available = getAvailableBackendInfo();
    if (!available.contains(backend)) {
      throw ArgumentError(
        'LiteRtLmBackend backend $backend is not available on '
        '${Platform.operatingSystem}. Available LiteRT-LM backends: '
        '${available.join(', ')}.',
      );
    }
    return backend;
  }

  static String? _deviceBackendName(ComputeDevice device) => switch (device) {
    ComputeDevice.auto => null,
    ComputeDevice.cpu => liteRtLmCpuBackend,
    ComputeDevice.gpu => liteRtLmGpuBackend,
    ComputeDevice.npu => liteRtLmNpuBackend,
  };

  String _backendNameFor(ModelParams params) {
    final explicit =
        _deviceBackendName(params.device) ?? params.liteRtLmBackend.nativeName;
    if (explicit != null) {
      return explicit;
    }
    if (resolveGpuLayerCount(params.gpuLayers) == 0) {
      return liteRtLmCpuBackend;
    }
    return _backendNameForGpuPreference(params.preferredBackend);
  }

  void _validateModelParams(ModelParams params) {
    params.validate();
    checkModelParamsTypeFor(params, LlamaRuntime.liteRtLm);

    if (params.liteRtLmEmbeddingEngine) {
      final ignored = <String>[
        if (params.loras.isNotEmpty) 'loras',
        if (params.chatTemplate != null) 'chatTemplate',
        for (final (field, isSet) in [
          (
            'liteRtLmActivationDataType',
            params.liteRtLmActivationDataType != null,
          ),
          ('liteRtLmPrefillChunkSize', params.liteRtLmPrefillChunkSize != null),
          (
            'liteRtLmParallelFileSectionLoading',
            params.liteRtLmParallelFileSectionLoading != null,
          ),
          ('liteRtLmDispatchLibDir', params.liteRtLmDispatchLibDir != null),
          (
            'liteRtLmMaxProgramCacheBytes',
            params.liteRtLmMaxProgramCacheBytes != null,
          ),
        ])
          if (isSet) liteRtLmOptionName(params, field),
        if (params.loadMtp) 'loadMtp',
        if (params.speculativeRollbackTokenMax != 0)
          'speculativeRollbackTokenMax',
        if (params.preferMemory64 != null) 'preferMemory64',
        if (params.modelBytesHint != null) 'modelBytesHint',
      ];
      if (ignored.isNotEmpty) {
        throw LlamaUnsupportedException(
          'LiteRT-LM embedding mode does not apply: ${ignored.join(', ')}. '
          'Use contextSize (encoder signature), numberOfThreads, '
          '${liteRtLmOptionName(params, 'liteRtLmCacheDir')} and CPU device '
          'selection.',
        );
      }
    }
    final unsupported = [
      ...modelParamsUnsupportedBy(params, LlamaRuntime.liteRtLm, web: false),
      if (params.loras.length > 1) 'loras.length=${params.loras.length}',
      if (params.loras.any((lora) => lora.scale != 1.0)) 'loras.scale',
    ];
    if (unsupported.isEmpty) {
      return;
    }
    throw LlamaUnsupportedException(
      unsupportedModelParamsMessage(
        unsupported,
        LlamaRuntime.liteRtLm,
        web: false,
      ),
    );
  }

  String? _activeTextLoraPath() {
    final loras = _modelParams?.loras ?? const [];
    if (loras.isEmpty) {
      return null;
    }
    return loras.single.path;
  }

  void _validateContextBackendParams(ModelParams params) {
    final requestedBackend = _explicitContextBackendName(params);
    if (requestedBackend == null) {
      return;
    }

    // An automatic hint still names the load-time choice after CPU fallback.
    if (_automaticBackend &&
        params.device == ComputeDevice.auto &&
        params.liteRtLmBackend.nativeName == null &&
        requestedBackend == _loadedBackend) {
      return;
    }

    liteRtLmEnsureNativeBackendSupported(requestedBackend);
    final available = getAvailableBackendInfo();
    if (!available.contains(requestedBackend)) {
      throw ArgumentError(
        'LiteRtLmBackend backend $requestedBackend is not available on '
        '${Platform.operatingSystem}. Available LiteRT-LM backends: '
        '${available.join(', ')}.',
      );
    }

    final activeBackend =
        _activeBackend ?? liteRtLmDefaultNativeBackendForCurrentPlatform();
    if (requestedBackend == activeBackend) {
      return;
    }

    throw ArgumentError(
      'LiteRtLmBackend contextCreate cannot change the loaded backend from '
      '$activeBackend to $requestedBackend. Select the LiteRT-LM backend in '
      'modelLoad ModelParams.',
    );
  }

  String? _explicitContextBackendName(ModelParams params) {
    final explicit =
        _deviceBackendName(params.device) ?? params.liteRtLmBackend.nativeName;
    if (explicit != null) {
      return explicit;
    }
    if (resolveGpuLayerCount(params.gpuLayers) == 0) {
      return liteRtLmCpuBackend;
    }
    if (params.preferredBackend != GpuBackend.auto) {
      return _backendNameForGpuPreference(params.preferredBackend);
    }
    return null;
  }

  void _validateGenerationParams(GenerationParams params) {
    const defaults = GenerationParams();
    final unsupported = <String>[];
    if (params.minP != defaults.minP) {
      unsupported.add('minP');
    }
    if (params.grammar != null) {
      unsupported.add('grammar');
    }
    if (params.grammarLazy) {
      unsupported.add('grammarLazy');
    }
    if (params.grammarTriggers.isNotEmpty) {
      unsupported.add('grammarTriggers');
    }
    if (params.preservedTokens.isNotEmpty) {
      unsupported.add('preservedTokens');
    }
    if (params.grammarRoot != defaults.grammarRoot) {
      unsupported.add('grammarRoot');
    }
    _addUnsupportedSpeculativeDecodingOptions(params, unsupported);

    if (unsupported.isEmpty) {
      return;
    }
    throw UnsupportedError(
      'LiteRtLmBackend does not support llama.cpp-specific GenerationParams: '
      '${unsupported.join(', ')}. Supported LiteRT-LM generation options are '
      'maxTokens, temp, topK, topP, seed, stopSequences, penalty, '
      'presencePenalty, thinkingBudget, speculativeDecoding, '
      'speculativeDecodingConfig, and native stream batching thresholds.',
    );
  }

  /// Which per-send decode controls the LiteRT-LM runtime and the loaded
  /// bundle apply: repetition and presence penalties when the runtime
  /// exports the repetition penalty API, and a thinking budget when it also
  /// exports the thinking config API and the bundle declares a thinking
  /// channel for the runtime to bound.
  ({bool penalties, bool thinkingBudget}) generationControls() {
    final runtime = _readRuntimeGenerationControls();
    return (
      penalties: runtime.penalties,
      thinkingBudget: runtime.thinkingBudget && _bundleBoundsThinking(),
    );
  }

  /// Whether the LiteRT-LM runtime reports why each generation ended, so
  /// [lastGenerationLimit] can tell a token limit from a natural stop.
  ///
  /// Probes a fresh client, so a model load that asks creates no engine.
  bool reportsFinishReasons() =>
      _runtimeFinishReasons ??= _finishReasonProbeLibraryPath != null
      ? createLiteRtLmSelectedRuntimeClient(
          libraryPath: _finishReasonProbeLibraryPath,
        ).supportsFinishReasons
      : _injectedFinishReasonProbe?.call() ??
            createLiteRtLmSelectedRuntimeClient().supportsFinishReasons;

  /// The token limit that ended the latest generation, or null when it ended
  /// at a stop token, a stop sequence, cancellation or an error, is still
  /// running, or ran on a runtime without [reportsFinishReasons].
  BackendGenerationLimit? get lastGenerationLimit => _lastGenerationLimit;

  // Cancellation, including a Dart stop sequence, which cancels the native
  // turn, wins over a limit the runtime reported at the same time.
  BackendGenerationLimit? _generationLimitOf(
    LiteRtLmRuntimeClientContract client,
  ) {
    if (_cancelRequested) {
      return null;
    }
    return switch (client.lastFinishReason) {
      LiteRtLmFinishReason.length => BackendGenerationLimit.maxTokens,
      LiteRtLmFinishReason.contextExhausted =>
        BackendGenerationLimit.contextSize,
      _ => null,
    };
  }

  ({bool penalties, bool thinkingBudget}) _readRuntimeGenerationControls() {
    final cached = _runtimeGenerationControls;
    if (cached != null) {
      return cached;
    }
    final client = _client ?? _clientFactory();
    return _runtimeGenerationControls = (
      penalties: client.supportsSamplingPenalties,
      thinkingBudget: client.supportsThinkingBudget,
    );
  }

  bool _bundleBoundsThinking() {
    final cached = _bundleDeclaresThinkingChannel;
    if (cached != null) {
      return cached;
    }
    final modelPath = _modelPath;
    if (!_modelLoaded || modelPath == null) {
      return false;
    }
    final channel = _readBundleFirstChannel(_modelLink?.path ?? modelPath);
    return _bundleDeclaresThinkingChannel =
        channel != null &&
        (channel.isReasoning ??
            _liteRtLmThinkingChannelNames.contains(channel.name.toLowerCase()));
  }

  /// Maps [params] to LiteRT-LM per-send decode controls, or throws when the
  /// runtime, the bundle or the request cannot apply one as asked.
  ///
  /// The default [GenerationParams.penalty] stays unapplied, as it was before
  /// LiteRT-LM applied penalties, so default requests keep their output.
  _LiteRtLmGenerationControls _resolveGenerationControls(
    GenerationParams params, {
    required bool enableThinking,
  }) {
    const defaults = GenerationParams();
    final penalty = params.penalty;
    final presencePenalty = params.presencePenalty;
    final appliesPenalty = penalty != defaults.penalty;
    final appliesPresencePenalty = presencePenalty != defaults.presencePenalty;
    final budget = params.thinkingBudget;
    if (!appliesPenalty && !appliesPresencePenalty && budget == null) {
      return (
        repetitionPenalty: null,
        presencePenalty: null,
        thinkingTokenBudget: null,
      );
    }
    if (appliesPenalty && !penalty.isFinite) {
      throw ArgumentError.value(penalty, 'penalty', 'must be finite');
    }
    if (appliesPresencePenalty && !presencePenalty.isFinite) {
      throw ArgumentError.value(
        presencePenalty,
        'presencePenalty',
        'must be finite',
      );
    }
    if (appliesPenalty && penalty < 1.0) {
      throw LlamaUnsupportedException(
        'LiteRtLmBackend cannot apply GenerationParams.penalty $penalty: '
        'LiteRT-LM repetition penalties start at 1.0 (no penalty) and the '
        'runtime raises smaller values to 1.0.',
      );
    }
    if (params.isSpeculativeDecodingEnabled) {
      throw LlamaUnsupportedException(
        'LiteRtLmBackend does not combine speculative decoding with '
        'GenerationParams.penalty, presencePenalty or thinkingBudget; this '
        'LiteRT-LM combination is not qualified.',
      );
    }
    final runtime = _readRuntimeGenerationControls();
    if ((appliesPenalty || appliesPresencePenalty) && !runtime.penalties) {
      throw LlamaUnsupportedException(
        'LiteRtLmBackend cannot apply GenerationParams.penalty or '
        'presencePenalty: the loaded LiteRT-LM runtime does not export the '
        'repetition penalty API (litert-lm-native v0.18.0 or newer).',
      );
    }
    int? thinkingTokenBudget;
    if (budget != null) {
      if (budget.forcedMessage != null) {
        throw LlamaUnsupportedException(
          'LiteRtLmBackend cannot apply ThinkingBudget.forcedMessage: '
          'LiteRT-LM closes an exhausted thinking channel with its end marker '
          'only.',
        );
      }
      if (budget.maxTokens == 0) {
        throw LlamaUnsupportedException(
          'LiteRtLmBackend cannot apply a zero ThinkingBudget: LiteRT-LM '
          'treats a zero thinking token budget as no budget. Disable '
          'thinking instead, or use a budget of at least 1.',
        );
      }
      if (!runtime.thinkingBudget) {
        throw LlamaUnsupportedException(
          'LiteRtLmBackend cannot apply GenerationParams.thinkingBudget: the '
          'loaded LiteRT-LM runtime does not export the thinking config API '
          '(litert-lm-native v0.18.0 or newer).',
        );
      }
      if (!_bundleBoundsThinking()) {
        throw LlamaUnsupportedException(
          'LiteRtLmBackend cannot apply GenerationParams.thinkingBudget to '
          'this model: LiteRT-LM bounds thinking with the first response '
          'channel a bundle declares, and this bundle declares no thinking '
          'channel.',
        );
      }
      if (enableThinking) {
        thinkingTokenBudget = budget.maxTokens;
      }
    }
    return (
      repetitionPenalty: appliesPenalty ? penalty : null,
      presencePenalty: appliesPresencePenalty ? presencePenalty : null,
      thinkingTokenBudget: thinkingTokenBudget,
    );
  }

  void _addUnsupportedSpeculativeDecodingOptions(
    GenerationParams params,
    List<String> unsupported,
  ) {
    final config = params.resolvedSpeculativeDecodingConfig;
    if (config == null) {
      return;
    }
    final strategies = config.effectiveStrategies;
    final unsupportedStrategy =
        strategies.length > 1 ||
        strategies.any(
          (strategy) =>
              strategy != SpeculativeDecodingStrategy.backendDefault &&
              strategy != SpeculativeDecodingStrategy.mtp,
        );
    if (unsupportedStrategy) {
      unsupported.add('speculativeDecodingConfig.strategy');
    }
    if (config.draftTokenMax != null) {
      unsupported.add('speculativeDecodingConfig.draftTokenMax');
    }
    if (config.draftTokenMin != null) {
      unsupported.add('speculativeDecodingConfig.draftTokenMin');
    }
    if (config.minProbability != null) {
      unsupported.add('speculativeDecodingConfig.minProbability');
    }
    if (config.draftSplitProbability != null) {
      unsupported.add('speculativeDecodingConfig.draftSplitProbability');
    }
    if (config.draftMicroBatchSize != null) {
      unsupported.add('speculativeDecodingConfig.draftMicroBatchSize');
    }
    if (config.draftModelPath != null) {
      unsupported.add('speculativeDecodingConfig.draftModel');
    }
    if (config.ngramSize != null) {
      unsupported.add('speculativeDecodingConfig.ngramSize');
    }
    if (config.ngramSizeN != null) {
      unsupported.add('speculativeDecodingConfig.ngramSizeN');
    }
    if (config.ngramSizeM != null) {
      unsupported.add('speculativeDecodingConfig.ngramSizeM');
    }
    if (config.ngramMinHits != null) {
      unsupported.add('speculativeDecodingConfig.ngramMinHits');
    }
    if (config.ngramMatch != null) {
      unsupported.add('speculativeDecodingConfig.ngramMatch');
    }
    if (config.ngramTokenMin != null) {
      unsupported.add('speculativeDecodingConfig.ngramTokenMin');
    }
    if (config.ngramTokenMax != null) {
      unsupported.add('speculativeDecodingConfig.ngramTokenMax');
    }
    if (config.ngramCacheStaticPath != null) {
      unsupported.add('speculativeDecodingConfig.ngramCacheStaticPath');
    }
    if (config.ngramCacheDynamicPath != null) {
      unsupported.add('speculativeDecodingConfig.ngramCacheDynamicPath');
    }
  }

  int _defaultSamplerSeed() {
    return DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
  }

  String _backendNameForGpuPreference(GpuBackend backend) {
    switch (backend) {
      case GpuBackend.cpu:
      case GpuBackend.blas:
        return liteRtLmCpuBackend;
      case GpuBackend.auto:
        return liteRtLmDefaultNativeBackendForCurrentPlatform();
      case GpuBackend.vulkan:
      case GpuBackend.metal:
      case GpuBackend.cuda:
      case GpuBackend.opencl:
      case GpuBackend.hip:
        return liteRtLmGpuBackend;
    }
  }

  LlamaChatMessage _messageFromTemplateMap(Map<String, dynamic> message) {
    final roleName = message['role']?.toString() ?? LlamaChatRole.user.name;
    final role = LlamaChatRole.values.byName(roleName);
    return LlamaChatMessage.fromText(
      role: role,
      text: _contentTextFromTemplateMap(message['content']),
    );
  }

  ({String? systemMessage, List<Map<String, dynamic>>? messages})
  _nativeConversationSeed(Iterable<LlamaChatMessage> history) {
    final systemText = <String>[];
    final seededMessages = <Map<String, dynamic>>[];
    for (final message in history) {
      if (message.role == LlamaChatRole.system) {
        if (_hasMediaParts(message.parts)) {
          throw UnsupportedError(
            'LiteRtLmBackend native chat generation does not support media '
            'parts in system messages.',
          );
        }
        final content = message.content.trim();
        if (content.isNotEmpty) {
          systemText.add(content);
        }
        continue;
      }
      seededMessages.add(_chatMessageToNativeJson(message));
    }

    // The runtime encodes this text as JSON content; the native conversation
    // adds the system role itself.
    final systemMessage = systemText.isEmpty ? null : systemText.join('\n');
    return (
      systemMessage: systemMessage,
      messages: seededMessages.isEmpty ? null : seededMessages,
    );
  }

  Map<String, dynamic> _chatMessageToNativeJson(LlamaChatMessage message) {
    if (!_hasMediaParts(message.parts)) {
      final toolResults = message.parts.whereType<LlamaToolResultContent>();
      if (toolResults.isNotEmpty) {
        return {
          'role': LlamaChatRole.tool.name,
          'content': [
            for (final result in toolResults)
              {
                'type': 'tool_response',
                'name': result.name,
                'response': result.result,
              },
          ],
        };
      }
      final toolCalls = message.parts.whereType<LlamaToolCallContent>();
      if (toolCalls.isNotEmpty) {
        final thinking = message.parts.whereType<LlamaThinkingContent>();
        return {
          'role': LlamaChatRole.assistant.name,
          // Always a string: LiteRT-LM's generic data processor reads
          // `content` without a presence check, and drops `tool_calls` when
          // it rewrites a one-part text list.
          'content': message.parts
              .whereType<LlamaTextContent>()
              .map((part) => part.text)
              .join(),
          if (thinking.isNotEmpty)
            'reasoning_content': thinking
                .map((part) => part.thinking)
                .join('\n'),
          'tool_calls': [
            for (final call in toolCalls)
              {
                'type': 'function',
                'function': {'name': call.name, 'arguments': call.arguments},
              },
          ],
        };
      }
      return Map<String, dynamic>.from(message.toJsonMultimodal());
    }
    if (message.role == LlamaChatRole.system) {
      throw UnsupportedError(
        'LiteRtLmBackend native chat generation does not support media parts '
        'in system messages.',
      );
    }

    final content = <Map<String, dynamic>>[];
    for (final part in message.parts) {
      switch (part) {
        case LlamaTextContent(:final text):
          if (text.isNotEmpty) {
            content.add({'type': 'text', 'text': text});
          }
        case LlamaImageContent():
          content.add(_nativeImageContent(part));
        case LlamaAudioContent():
          content.add(_nativeAudioContent(part));
        case LlamaVideoContent():
          throw UnsupportedError(_liteRtLmVideoUnsupportedMessage);
        case LlamaThinkingContent():
          throw UnsupportedError(
            'LiteRtLmBackend native chat generation does not support thinking '
            'content in the same message as media parts.',
          );
        case LlamaToolCallContent():
          throw UnsupportedError(
            'LiteRtLmBackend native chat generation does not support tool-call '
            'content in the same message as media parts.',
          );
        case LlamaToolResultContent():
          throw UnsupportedError(
            'LiteRtLmBackend native chat generation does not support tool-result '
            'content in the same message as media parts.',
          );
      }
    }
    if (content.isEmpty) {
      content.add({'type': 'text', 'text': ''});
    }
    return {'role': message.role.name, 'content': content};
  }

  List<Map<String, dynamic>>? _nativeToolsFor(
    ToolChoice toolChoice,
    List<Map<String, dynamic>>? tools,
  ) {
    if (toolChoice == ToolChoice.none || tools == null || tools.isEmpty) {
      return null;
    }
    return tools.map(Map<String, dynamic>.from).toList(growable: false);
  }

  Map<String, dynamic>? _nativeExtraContext({
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
    required bool enableThinking,
  }) {
    final extraContext = <String, dynamic>{
      ...?chatTemplateKwargs,
      if (templateNow != null) 'now': templateNow.toIso8601String(),
      'enable_thinking': enableThinking,
    };
    return extraContext.isEmpty ? null : extraContext;
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
          'LiteRtLmBackend does not support multimodal chat-template content.',
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
              'LiteRtLmBackend does not support multimodal chat-template '
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

  String? _effectiveCacheDir(ModelParams params) {
    final configured = params.liteRtLmCacheDir;
    if (configured == liteRtLmNoCacheDirectory) {
      return configured;
    }
    if (configured == null && !_useTempCacheDir) {
      return null;
    }
    final dir = Directory(
      configured ?? '${Directory.systemTemp.path}/llamadart_litert_lm',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  void _disposeClient() {
    if (nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'LiteRT-LM native resources are unsettled; retain the model and caches and restart the process.',
      );
    }
    _jsonSchemaAdmitted = false;
    _embedding?.dispose();
    _embedding = null;
    _client?.dispose();
    _client = null;
    _recreateClientAfterImageCancellation = false;
    _cacheLease?.release();
    _cacheLease = null;
  }

  /// Marks the caches of [modelPath] in [cacheDir] as in use until the client
  /// is disposed, so other engines pruning that directory keep them.
  LiteRtLmCacheLease? _leaseCacheDirectory(String? cacheDir, String modelPath) {
    if (cacheDir == null || cacheDir == liteRtLmNoCacheDirectory) {
      return null;
    }
    try {
      return LiteRtLmCacheLease.acquire(cacheDir, p.basename(modelPath));
    } on FileSystemException catch (error) {
      // Other engines cannot delete from a directory this one cannot write.
      LlamaLogger.instance.debug(
        'Could not mark LiteRT-LM caches in $cacheDir as in use: $error',
      );
      return null;
    }
  }

  void _pruneProgramCaches(
    String? cacheDir,
    int? configuredMaxBytes,
    LiteRtLmCacheLease? ownLease,
  ) {
    final maxBytes =
        configuredMaxBytes ?? ModelParams.defaultLiteRtLmMaxProgramCacheBytes;
    if (cacheDir == null ||
        cacheDir == liteRtLmNoCacheDirectory ||
        maxBytes == ModelParams.unlimitedLiteRtLmProgramCacheBytes) {
      return;
    }
    pruneLiteRtLmProgramCaches(
      cacheDir,
      maxBytes,
      ownLease: ownLease,
      onDeleted: (path, bytes) => _warn(
        'Deleted LiteRT-LM GPU program cache $path ($bytes bytes) to keep the '
        'program caches in its directory within '
        'liteRtLmMaxProgramCacheBytes=$maxBytes; see '
        'https://github.com/leehack/llamadart/issues/552',
      ),
      onError: (path, error) => _warn(
        'Could not prune LiteRT-LM GPU program cache at $path; see '
        'https://github.com/leehack/llamadart/issues/552',
        error,
      ),
    );
  }

  void _warn(String message, [Object? error]) {
    LlamaLogger.instance.warn(message, error);
  }

  double _millisecondsFromTps(int tokens, double? tps) {
    if (tokens <= 0 || tps == null || tps <= 0) {
      return 0;
    }
    return tokens / tps * 1000.0;
  }

  int _liteRtLmMinLogLevel(LlamaLogLevel level) {
    switch (level) {
      case LlamaLogLevel.none:
        return 1000;
      case LlamaLogLevel.debug:
        return 1;
      case LlamaLogLevel.info:
        return 2;
      case LlamaLogLevel.warn:
        return 3;
      case LlamaLogLevel.error:
        return 4;
    }
  }

  void _checkModelHandle(int handle) {
    if (handle != _modelHandle || !_modelLoaded) {
      throw StateError('Invalid LiteRT-LM model handle: $handle');
    }
  }

  void _checkContextHandle(int handle) {
    if (handle != _contextHandle || !_modelLoaded || !_contextCreated) {
      throw StateError('Invalid LiteRT-LM context handle: $handle');
    }
  }
}
