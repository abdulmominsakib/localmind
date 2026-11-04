import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../../core/exceptions.dart';
import '../../core/models/inference/model_params.dart';

const _litertLmVersion = '0.15.0-native.3';
const _litertLmLibDirEnv = 'LLAMADART_LITERT_LM_LIB_DIR';
const _liteRtLmIosNativeAsset = 'package:llamadart/litert_lm_LiteRtLm';
const _processLibraryCandidate = '<process>';
const _streamChunkCallbackAbiVersion = 2;

/// Returns macOS LiteRT-LM candidates for a concrete runtime library path.
///
/// Concrete app/cache paths must win over process-linked native assets so
/// validation and deployments do not silently use a different runtime version.
/// Explicit overrides exclude process fallback entirely.
List<String> liteRtLmMacOsLibraryCandidates(
  String libraryPath, {
  required bool explicitOverride,
}) {
  return explicitOverride
      ? <String>[libraryPath]
      : <String>[libraryPath, _processLibraryCandidate];
}

/// Describes an unsafe StreamProxy/upstream callback ABI combination.
///
/// This is public only for unit tests. A non-null result means registering the
/// asynchronous callback would be unsafe and must fail before generation.
String? liteRtLmStreamProxyCompatibilityError({
  required bool hasStreamProxy,
  required bool hasStreamChunkApi,
  required int? callbackAbiVersion,
}) {
  if (!hasStreamChunkApi) {
    return null;
  }
  if (hasStreamProxy && callbackAbiVersion == _streamChunkCallbackAbiVersion) {
    return null;
  }
  final detectedAbi = hasStreamProxy
      ? callbackAbiVersion?.toString() ?? 'no ABI marker'
      : 'missing StreamProxy';
  return 'LiteRT-LM exposes the 0.15+ stream-chunk callback API, but its '
      'embedded StreamProxy is missing or not stream-chunk compatible. '
      'Expected callback ABI $_streamChunkCallbackAbiVersion from pinned '
      'litert-lm-native v$_litertLmVersion; detected $detectedAbi. Install the '
      'pinned runtime before using asynchronous generation.';
}

/// Builds a diagnostic for LiteRT-LM engine creation failures.
///
/// This is public only for unit tests; production callers should receive the
/// message through [LiteRtLmRuntimeClient.initialize].
String liteRtLmEngineCreateFailureMessage({
  required String backend,
  required String modelPath,
}) {
  final modelName = path.basename(modelPath);
  final displayName = modelName.isEmpty ? modelPath : modelName;
  final normalizedBackend = backend.toLowerCase();
  final hint = switch (normalizedBackend) {
    'npu' =>
      'The Android NPU delegate may not support this device, OS, model, or '
          'bundle; try backend "gpu" or backend "cpu".',
    'gpu' =>
      'The GPU delegate may not support this device, OS, model, or bundle; '
          'try backend "cpu".',
    'cpu' => 'Verify the LiteRT-LM bundle and native runtime libraries.',
    _ =>
      'Verify the backend name, LiteRT-LM bundle, and native runtime '
          'libraries.',
  };
  return 'LiteRT-LM engine creation failed for backend "$backend" and model '
      '"$displayName". $hint';
}

/// Internal helper used by the LiteRT-LM runtime to locate extracted macOS
/// native-assets cache directories.
List<String> liteRtLmMacOsCacheDirectoryCandidatesForAbi(Abi abi) {
  final arch = switch (abi) {
    Abi.macosArm64 => 'arm64',
    Abi.macosX64 => 'x64',
    _ => null,
  };
  if (arch == null) {
    return const <String>[];
  }
  return <String>['macos_$arch', 'macos/$arch'];
}

/// Internal helper used by the LiteRT-LM runtime to validate extracted macOS
/// native-assets cache directories.
List<String> liteRtLmMacOsRequiredLibrariesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 || Abi.macosX64 => const <String>[
      'libLiteRtLm.dylib',
      'libCLiteRTLM_mac.dylib',
    ],
    _ => const <String>[],
  };
}

/// Internal helper used by the LiteRT-LM runtime to locate extracted
/// native-assets cache directories.
List<String> liteRtLmCacheDirectoryCandidatesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => liteRtLmMacOsCacheDirectoryCandidatesForAbi(abi),
    Abi.macosX64 => liteRtLmMacOsCacheDirectoryCandidatesForAbi(abi),
    Abi.linuxArm64 => const <String>['linux/arm64', 'linux_arm64'],
    Abi.linuxX64 => const <String>['linux/x64', 'linux_x64'],
    Abi.windowsX64 => const <String>['windows/x64', 'windows_x64'],
    _ => const <String>[],
  };
}

/// Internal helper used by the LiteRT-LM runtime to locate iOS native assets.
List<String> liteRtLmIosLibraryCandidatesForAbi(Abi abi) {
  return switch (abi) {
    Abi.iosArm64 || Abi.iosX64 => const <String>[
      _processLibraryCandidate,
      _liteRtLmIosNativeAsset,
      'LiteRtLm',
      'CLiteRTLM',
    ],
    _ => const <String>[],
  };
}

/// Path to an embedded iOS framework binary
/// (`<Frameworks>/<name>.framework/<name>`).
///
/// iOS frameworks are flat, unlike the versioned macOS layout.
String liteRtLmIosFrameworkBinaryPath(String frameworksDirPath, String name) {
  return '$frameworksDirPath/$name.framework/$name';
}

/// Ordered LiteRT-LM library load candidates for iOS.
///
/// `DynamicLibrary.open` does not resolve Dart native-asset ids (only `@Native`
/// externals do), so the `package:llamadart/...` id is passed verbatim to
/// dlopen and never loads. When [frameworksDirPath] is known, the wrapper
/// framework is tried first because it exports StreamProxy and reexports the
/// upstream `CLiteRTLM` API. The process image and absolute upstream framework
/// path remain fallbacks for older Flutter SPM packaging; native-asset ids and
/// bare dylib names remain last-resort fallbacks for the error message.
List<String> liteRtLmIosLibraryCandidates(
  Abi abi, {
  String? frameworksDirPath,
}) {
  final fallbacks = liteRtLmIosLibraryCandidatesForAbi(abi);
  if (fallbacks.isEmpty) {
    return const <String>[];
  }
  return <String>[
    if (frameworksDirPath != null)
      liteRtLmIosFrameworkBinaryPath(frameworksDirPath, 'LiteRtLm'),
    _processLibraryCandidate,
    if (frameworksDirPath != null)
      liteRtLmIosFrameworkBinaryPath(frameworksDirPath, 'CLiteRTLM'),
    ...fallbacks.where((candidate) => candidate != _processLibraryCandidate),
  ];
}

/// Internal helper used by the LiteRT-LM runtime to validate extracted
/// native-assets cache directories.
List<String> liteRtLmRequiredLibrariesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => liteRtLmMacOsRequiredLibrariesForAbi(abi),
    Abi.macosX64 => liteRtLmMacOsRequiredLibrariesForAbi(abi),
    Abi.linuxArm64 => const <String>[
      'libGemmaModelConstraintProvider.so',
      'libLiteRt.so',
      'libLiteRtLm.so',
      'libwebgpu_dawn.so',
      'libLiteRtTopKWebGpuSampler.so',
      'libLiteRtWebGpuAccelerator.so',
    ],
    Abi.linuxX64 => const <String>[
      'libGemmaModelConstraintProvider.so',
      'libLiteRt.so',
      'libLiteRtLm.so',
      'libwebgpu_dawn.so',
      'libLiteRtTopKWebGpuSampler.so',
      'libLiteRtWebGpuAccelerator.so',
    ],
    Abi.windowsX64 => const <String>[
      'LiteRtLm.dll',
      'libGemmaModelConstraintProvider.dll',
      'libLiteRt.dll',
      'libwebgpu_dawn.dll',
      'libLiteRtTopKWebGpuSampler.dll',
      'libLiteRtWebGpuAccelerator.dll',
    ],
    _ => const <String>[],
  };
}

/// Internal helper used by the LiteRT-LM runtime to locate this package's
/// source root from an app's `.dart_tool/package_config.json`.
List<String> liteRtLmPackageRootsFromPackageConfig(
  File packageConfig, {
  String packageName = 'llamadart',
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(packageConfig.readAsStringSync());
  } on Object {
    return const <String>[];
  }
  if (decoded is! Map<String, Object?>) {
    return const <String>[];
  }
  final packages = decoded['packages'];
  if (packages is! List) {
    return const <String>[];
  }

  final roots = <String>[];
  for (final entry in packages) {
    if (entry is! Map<String, Object?> || entry['name'] != packageName) {
      continue;
    }
    final rootUri = entry['rootUri'];
    if (rootUri is! String || rootUri.trim().isEmpty) {
      continue;
    }
    final root = _directoryFromPackageConfigRootUri(packageConfig, rootUri);
    if (root != null) {
      roots.add(path.normalize(root.absolute.path));
    }
  }
  return roots;
}

Directory? _directoryFromPackageConfigRootUri(
  File packageConfig,
  String rootUri,
) {
  try {
    final uri = Uri.parse(rootUri);
    if (uri.hasScheme) {
      if (uri.scheme != 'file') {
        return null;
      }
      return Directory.fromUri(uri);
    }
    final configDir = packageConfig.absolute.parent.path;
    return Directory(path.normalize(path.join(configDir, rootUri)));
  } on Object {
    return null;
  }
}

/// Internal helper used by the LiteRT-LM runtime to validate macOS app
/// framework directories.
List<String> liteRtLmMacOsRequiredFrameworksForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 ||
    Abi.macosX64 => const <String>['LiteRtLm.framework/Versions/A/LiteRtLm'],
    _ => const <String>[],
  };
}

/// Internal helper used by the LiteRT-LM runtime to validate the native-repo
/// Apple SPM layout in macOS app bundles.
List<String> liteRtLmMacOsRequiredNativeSpmFilesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 || Abi.macosX64 => const <String>[
      'LiteRtLm.framework/Versions/A/LiteRtLm',
      'libCLiteRTLM_mac.dylib',
    ],
    _ => const <String>[],
  };
}

/// Internal helper used by the LiteRT-LM runtime to validate extracted macOS
/// native-assets cache directories.
bool liteRtLmIsMacOsCacheDirectoryForAbi(Directory dir, Abi abi) {
  final requiredLibraries = liteRtLmMacOsRequiredLibrariesForAbi(abi);
  return requiredLibraries.isNotEmpty &&
      requiredLibraries.every(
        (library) => File('${dir.path}/$library').existsSync(),
      );
}

/// Internal helper used by the LiteRT-LM runtime to validate extracted
/// native-assets cache directories.
bool liteRtLmIsCacheDirectoryForAbi(Directory dir, Abi abi) {
  final requiredLibraries = liteRtLmRequiredLibrariesForAbi(abi);
  return requiredLibraries.isNotEmpty &&
      requiredLibraries.every(
        (library) => File('${dir.path}/$library').existsSync(),
      );
}

typedef _StreamCallbackNative =
    Void Function(
      Pointer<Void> callbackData,
      Pointer<Char> chunk,
      Bool isFinal,
      Pointer<Char> errorMessage,
    );

typedef _ProxyCreateNative =
    Pointer<Void> Function(
      Pointer<NativeFunction<_StreamCallbackNative>> dartCallback,
      Pointer<Void> dartData,
      Pointer<Pointer<NativeFunction<_StreamCallbackNative>>> outProxyFn,
    );
typedef _ProxyCreateDart =
    Pointer<Void> Function(
      Pointer<NativeFunction<_StreamCallbackNative>> dartCallback,
      Pointer<Void> dartData,
      Pointer<Pointer<NativeFunction<_StreamCallbackNative>>> outProxyFn,
    );

typedef _ProxyFreeStringNative = Void Function(Pointer<Char> value);
typedef _ProxyFreeStringDart = void Function(Pointer<Char> value);

typedef _ProxyDeleteNative = Void Function(Pointer<Void> callbackData);
typedef _ProxyDeleteDart = void Function(Pointer<Void> callbackData);

typedef _ProxyCallbackAbiVersionNative = Int32 Function();
typedef _ProxyCallbackAbiVersionDart = int Function();

typedef _LoadGlobalNative = Pointer<Void> Function(Pointer<Utf8> path);
typedef _LoadGlobalDart = Pointer<Void> Function(Pointer<Utf8> path);

final class _LiteRtLmEngine extends Opaque {}

final class _LiteRtLmEngineSettings extends Opaque {}

final class _LiteRtLmSessionConfig extends Opaque {}

final class _LiteRtLmConversationConfig extends Opaque {}

final class _LiteRtLmConversationOptionalArgs extends Opaque {}

final class _LiteRtLmConversation extends Opaque {}

final class _LiteRtLmJsonResponse extends Opaque {}

final class _LiteRtLmBenchmarkInfo extends Opaque {}

final class _LiteRtLmTokenizeResult extends Opaque {}

final class _LiteRtLmDetokenizeResult extends Opaque {}

final class _LiteRtLmTokenUnion extends Opaque {}

final class _LiteRtLmSamplerParams extends Opaque {}

final class _LegacyLiteRtLmSamplerParams extends Struct {
  @Int32()
  external int type;

  @Int32()
  external int topK;

  @Float()
  external double topP;

  @Float()
  external double temperature;

  @Int32()
  external int seed;
}

/// Runtime metrics reported by LiteRT-LM for a completed generation.
class LiteRtLmRuntimeMetrics {
  /// Number of prompt/input tokens.
  final int inputTokens;

  /// Number of generated/output tokens.
  final int outputTokens;

  /// Time to first token in seconds, when reported by LiteRT-LM.
  final double? timeToFirstTokenSeconds;

  /// Engine initialization time in seconds, when reported by LiteRT-LM.
  final double? initSeconds;

  /// Prompt prefill throughput in tokens per second.
  final double? prefillTokensPerSecond;

  /// Decode throughput in tokens per second.
  final double? decodeTokensPerSecond;

  /// Wall-clock runtime measured by Dart.
  final int wallMilliseconds;

  /// Creates runtime metrics.
  const LiteRtLmRuntimeMetrics({
    required this.inputTokens,
    required this.outputTokens,
    required this.timeToFirstTokenSeconds,
    required this.initSeconds,
    required this.prefillTokensPerSecond,
    required this.decodeTokensPerSecond,
    required this.wallMilliseconds,
  });

  /// Converts metrics to JSON-compatible values.
  Map<String, Object?> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'timeToFirstTokenSeconds': timeToFirstTokenSeconds,
    'initSeconds': initSeconds,
    'prefillTokensPerSecond': prefillTokensPerSecond,
    'decodeTokensPerSecond': decodeTokensPerSecond,
    'wallMilliseconds': wallMilliseconds,
  };
}

/// Generated text and runtime metrics from a LiteRT-LM run.
class LiteRtLmRuntimeResult {
  /// Generated text.
  final String text;

  /// Runtime metrics.
  final LiteRtLmRuntimeMetrics metrics;

  /// Creates a runtime result.
  const LiteRtLmRuntimeResult({required this.text, required this.metrics});
}

// coverage:ignore-start
// Native FFI boundary: exercised by LiteRT-LM smoke tests with real libraries.
final class _BlockingSendMessageRequest {
  const _BlockingSendMessageRequest({
    required this.libraryPath,
    required this.companionLibraryPaths,
    required this.conversationAddress,
    required this.messageJson,
    this.extraContextJson,
    this.visualTokenBudget,
    this.maxOutputTokens,
  });

  final String libraryPath;
  final List<String> companionLibraryPaths;
  final int conversationAddress;
  final String messageJson;
  final String? extraContextJson;
  final int? visualTokenBudget;
  final int? maxOutputTokens;
}

/// Low-level native LiteRT-LM runtime client.
///
/// Most callers should use [LiteRtLmBackend] through the high-level
/// `LlamaEngine` API. This client is exported for benchmark tools and advanced
/// native integrations that need direct access to LiteRT-LM bundles.
class LiteRtLmRuntimeClient {
  String _thinkingStartTag = LiteRtLmChannelAssembler.gemma4ThinkingStartTag;
  String _thinkingEndTag = LiteRtLmChannelAssembler.gemma4ThinkingEndTag;

  /// Configures how LiteRT-LM thought-channel chunks are exposed to parsers.
  void configureResponseThinkingTags({
    required String startTag,
    required String endTag,
  }) {
    _thinkingStartTag = startTag;
    _thinkingEndTag = endTag;
  }

  _LiteRtLmBindings? _bindings;
  // Keep a strong runtime-library reference while proxy function pointers are active.
  // ignore: unused_field
  DynamicLibrary? _proxyLibrary;
  // Keep macOS/Linux/Windows companion libraries loaded while the runtime is active.
  // ignore: unused_field
  List<DynamicLibrary> _companionLibraries = const <DynamicLibrary>[];
  _ProxyCreateDart? _proxyCreate;
  _ProxyFreeStringDart? _proxyFreeString;
  _ProxyDeleteDart? _proxyDelete;
  String? _liteRtLmLibraryPath;
  List<String> _liteRtLmCompanionLibraryPaths = const <String>[];
  Pointer<_LiteRtLmEngine>? _engine;
  Pointer<_LiteRtLmConversation>? _conversation;
  int _defaultMaxOutputTokens = 256;

  /// Initializes the native LiteRT-LM engine for a `.litertlm` model bundle.
  ///
  /// [visionBackend] and [audioBackend] enable the native media executors for
  /// multimodal bundles. [maxNumImages] configures the image preprocessor
  /// capacity for conversations that may include image inputs. [outputTokens]
  /// is the per-request fallback when generation does not provide an explicit
  /// maximum; it is not an upstream benchmark decode-step count.
  Future<void> initialize({
    required String modelPath,
    String backend = 'gpu',
    String? visionBackend,
    String? audioBackend,
    int maxTokens = 4096,
    int outputTokens = 256,
    int? prefillTokens,
    int? maxNumImages,
    String? cacheDir,
    bool speculativeDecoding = true,
    int minLogLevel = 3,
    LiteRtLmActivationDataType? activationDataType,
    int? prefillChunkSize,
    bool? parallelFileSectionLoading,
    String? dispatchLibDir,
    int? numberOfThreads,
  }) async {
    if (maxTokens <= 0) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    }
    if (outputTokens <= 0) {
      throw ArgumentError.value(
        outputTokens,
        'outputTokens',
        'must be positive',
      );
    }
    if (prefillTokens != null && prefillTokens <= 0) {
      throw ArgumentError.value(
        prefillTokens,
        'prefillTokens',
        'must be positive when provided',
      );
    }
    if (maxNumImages != null && maxNumImages <= 0) {
      throw ArgumentError.value(
        maxNumImages,
        'maxNumImages',
        'must be positive when provided',
      );
    }
    if (prefillChunkSize != null && prefillChunkSize <= 0) {
      throw ArgumentError.value(
        prefillChunkSize,
        'prefillChunkSize',
        'must be positive when provided',
      );
    }
    if (dispatchLibDir != null && dispatchLibDir.trim().isEmpty) {
      throw ArgumentError.value(
        dispatchLibDir,
        'dispatchLibDir',
        'must be non-empty when provided',
      );
    }
    if (numberOfThreads != null && numberOfThreads <= 0) {
      throw ArgumentError.value(
        numberOfThreads,
        'numberOfThreads',
        'must be positive when provided',
      );
    }
    final resolvedBackend = _normalizeLiteRtLmRuntimeBackend(backend);
    final resolvedVisionBackend = visionBackend == null
        ? null
        : _normalizeLiteRtLmRuntimeBackend(
            visionBackend,
            name: 'visionBackend',
          );
    final resolvedAudioBackend = audioBackend == null
        ? null
        : _normalizeLiteRtLmRuntimeBackend(audioBackend, name: 'audioBackend');
    _defaultMaxOutputTokens = outputTokens;

    _ensureLibrariesLoaded();
    final bindings = _bindings!;
    bindings.setMinLogLevel(minLogLevel);
    if (_engine != null || _conversation != null) {
      dispose();
    }

    final modelPathPtr = modelPath.toNativeUtf8(allocator: calloc);
    final backendPtr = resolvedBackend.toNativeUtf8(allocator: calloc);
    final visionBackendPtr = resolvedVisionBackend?.toNativeUtf8(
      allocator: calloc,
    );
    final audioBackendPtr = resolvedAudioBackend?.toNativeUtf8(
      allocator: calloc,
    );
    final cacheDirPtr = cacheDir?.toNativeUtf8(allocator: calloc);
    final dispatchLibDirPtr = dispatchLibDir?.toNativeUtf8(allocator: calloc);
    Pointer<_LiteRtLmEngineSettings> settings = nullptr;

    try {
      settings = bindings.engineSettingsCreate(
        modelPathPtr.cast(),
        backendPtr.cast(),
        visionBackendPtr?.cast() ?? nullptr,
        audioBackendPtr?.cast() ?? nullptr,
      );
      if (settings == nullptr) {
        throw StateError('litert_lm_engine_settings_create returned null');
      }
      bindings.engineSettingsSetMaxNumTokens(settings, maxTokens);
      // Benchmarking exposes real prefill/decode metrics. Do not set
      // num_decode_tokens here: upstream defines it as a forced benchmark step
      // count, not a response limit. Per-request maxOutputTokens handles that.
      bindings.engineSettingsEnableBenchmark(settings);
      bindings.engineSettingsSetEnableSpeculativeDecoding(
        settings,
        speculativeDecoding,
      );
      if (maxNumImages != null) {
        bindings.engineSettingsSetMaxNumImages(settings, maxNumImages);
      }
      if (parallelFileSectionLoading != null) {
        bindings.engineSettingsSetParallelFileSectionLoading(
          settings,
          parallelFileSectionLoading,
        );
      }
      if (activationDataType != null) {
        bindings.engineSettingsSetActivationDataType(
          settings,
          activationDataType.nativeValue,
        );
      }
      if (prefillChunkSize != null) {
        bindings.engineSettingsSetPrefillChunkSize(settings, prefillChunkSize);
      }
      if (prefillTokens != null) {
        bindings.engineSettingsSetNumPrefillTokens(settings, prefillTokens);
      }
      if (cacheDirPtr != null) {
        bindings.engineSettingsSetCacheDir(settings, cacheDirPtr.cast());
      }
      if (dispatchLibDirPtr != null) {
        bindings.engineSettingsSetLiteRtDispatchLibDir(
          settings,
          dispatchLibDirPtr.cast(),
        );
      }
      if (numberOfThreads != null) {
        final setter = bindings.engineSettingsSetNumThreads;
        if (setter == null) {
          throw UnsupportedError(
            'LiteRT-LM numberOfThreads requires native runtime v0.14.0 or '
            'newer because litert_lm_engine_settings_set_num_threads is '
            'missing.',
          );
        }
        setter(settings, numberOfThreads);
      }

      final settingsAddress = settings.address;
      final liteRtLmLibraryPath = _liteRtLmLibraryPath!;
      final companionLibraryPaths = _liteRtLmCompanionLibraryPaths;
      final engineAddress = await Isolate.run(() {
        final companionLibraries = _openCompanionLibraries(
          companionLibraryPaths,
        );
        try {
          final lib = _openLiteRtLmLibraryCandidate(liteRtLmLibraryPath);
          final create = lib
              .lookupFunction<
                Pointer<_LiteRtLmEngine> Function(
                  Pointer<_LiteRtLmEngineSettings>,
                ),
                Pointer<_LiteRtLmEngine> Function(
                  Pointer<_LiteRtLmEngineSettings>,
                )
              >('litert_lm_engine_create');
          return create(
            Pointer<_LiteRtLmEngineSettings>.fromAddress(settingsAddress),
          ).address;
        } finally {
          _keepAlive(companionLibraries);
        }
      });
      if (engineAddress == 0) {
        throw StateError(
          liteRtLmEngineCreateFailureMessage(
            backend: resolvedBackend,
            modelPath: modelPath,
          ),
        );
      }
      _engine = Pointer<_LiteRtLmEngine>.fromAddress(engineAddress);
    } finally {
      if (settings != nullptr) {
        bindings.engineSettingsDelete(settings);
      }
      calloc.free(modelPathPtr);
      calloc.free(backendPtr);
      if (visionBackendPtr != null) {
        calloc.free(visionBackendPtr);
      }
      if (audioBackendPtr != null) {
        calloc.free(audioBackendPtr);
      }
      if (cacheDirPtr != null) {
        calloc.free(cacheDirPtr);
      }
      if (dispatchLibDirPtr != null) {
        calloc.free(dispatchLibDirPtr);
      }
    }
  }

  /// Creates a new LiteRT-LM conversation for generation and token operations.
  void createConversation({
    String? systemMessage,
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? extraContext,
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    int seed = 1,
    bool npuBackend = false,
    String? loraPath,
  }) {
    final bindings = _requireBindings();
    final engine = _requireEngine();
    _deleteConversation();

    final sessionConfig = bindings.sessionConfigCreate();
    if (sessionConfig == nullptr) {
      throw StateError('litert_lm_session_config_create returned null');
    }
    if (!npuBackend) {
      _setSessionSamplerParams(
        bindings,
        sessionConfig,
        topK: topK,
        topP: topP,
        temperature: temperature,
        seed: seed,
      );
    }
    _setSessionLoraPath(bindings, sessionConfig, loraPath);

    final systemPtr = systemMessage == null
        ? nullptr
        : _systemMessageJson(systemMessage).toNativeUtf8(allocator: calloc);
    final messagesPtr = messages == null || messages.isEmpty
        ? nullptr
        : jsonEncode(messages).toNativeUtf8(allocator: calloc);
    final toolsPtr = tools == null || tools.isEmpty
        ? nullptr
        : jsonEncode(tools).toNativeUtf8(allocator: calloc);
    final extraContextPtr = extraContext == null || extraContext.isEmpty
        ? nullptr
        : jsonEncode(extraContext).toNativeUtf8(allocator: calloc);
    Pointer<_LiteRtLmConversationConfig> config = nullptr;
    try {
      config = bindings.conversationConfigCreate();
      if (config == nullptr) {
        throw StateError('litert_lm_conversation_config_create returned null');
      }
      bindings.conversationConfigSetSessionConfig(config, sessionConfig);
      if (systemPtr != nullptr) {
        bindings.conversationConfigSetSystemMessage(config, systemPtr.cast());
      }
      if (messagesPtr != nullptr) {
        bindings.conversationConfigSetMessages(config, messagesPtr.cast());
      }
      if (toolsPtr != nullptr) {
        bindings.conversationConfigSetTools(config, toolsPtr.cast());
      }
      if (extraContextPtr != nullptr) {
        bindings.conversationConfigSetExtraContext(
          config,
          extraContextPtr.cast(),
        );
      }
      bindings.conversationConfigSetEnableConstrainedDecoding(config, false);
      final conversation = bindings.conversationCreate(engine, config);
      if (conversation == nullptr) {
        throw StateError('litert_lm_conversation_create returned null');
      }
      _conversation = conversation;
    } finally {
      if (config != nullptr) {
        bindings.conversationConfigDelete(config);
      }
      bindings.sessionConfigDelete(sessionConfig);
      if (systemPtr != nullptr) {
        calloc.free(systemPtr);
      }
      if (messagesPtr != nullptr) {
        calloc.free(messagesPtr);
      }
      if (toolsPtr != nullptr) {
        calloc.free(toolsPtr);
      }
      if (extraContextPtr != nullptr) {
        calloc.free(extraContextPtr);
      }
    }
  }

  /// Updates the native LiteRT-LM log level.
  void setMinLogLevel(int level) {
    _ensureLibrariesLoaded();
    _bindings!.setMinLogLevel(level);
  }

  /// Tokenizes text with the native LiteRT-LM tokenizer.
  List<int> tokenize(String text, {bool addSpecial = true}) {
    final tokens = _tokenizeRaw(text);
    if (!addSpecial) {
      return tokens;
    }
    final startToken = _readStartToken();
    if (startToken.isEmpty) {
      return tokens;
    }
    return <int>[...startToken, ...tokens];
  }

  /// Converts native LiteRT-LM token ids back to text.
  String detokenize(List<int> tokens) {
    final bindings = _requireBindings();
    final engine = _requireEngine();
    if (tokens.isEmpty) {
      return '';
    }

    final tokenPtr = calloc<Int>(tokens.length);
    Pointer<_LiteRtLmDetokenizeResult> result = nullptr;
    try {
      for (var i = 0; i < tokens.length; i++) {
        tokenPtr[i] = tokens[i];
      }
      result = bindings.engineDetokenize(engine, tokenPtr, tokens.length);
      if (result == nullptr) {
        throw StateError('litert_lm_engine_detokenize returned null');
      }
      final textPtr = bindings.detokenizeResultGetString(result);
      if (textPtr == nullptr) {
        throw StateError(
          'litert_lm_detokenize_result_get_string returned null',
        );
      }
      return textPtr.cast<Utf8>().toDartString();
    } finally {
      if (result != nullptr) {
        bindings.detokenizeResultDelete(result);
      }
      calloc.free(tokenPtr);
    }
  }

  /// Renders a message with the active native LiteRT-LM conversation template.
  ///
  /// The returned string is copied into Dart before the native conversation may
  /// invalidate the underlying buffer.
  String renderMessageToString(Map<String, dynamic> message) {
    final bindings = _requireBindings();
    final conversation = _requireConversation();
    final messagePtr = jsonEncode(message).toNativeUtf8(allocator: calloc);
    try {
      final renderedPtr = bindings.conversationRenderMessageToString(
        conversation,
        messagePtr.cast(),
      );
      if (renderedPtr == nullptr) {
        throw StateError(
          'litert_lm_conversation_render_message_to_string returned null',
        );
      }
      return renderedPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(messagePtr);
    }
  }

  /// Returns the token count currently held by the active conversation KV cache.
  int conversationTokenCount() {
    final bindings = _requireBindings();
    final conversation = _requireConversation();
    final count = bindings.conversationGetTokenCount(conversation);
    if (count < 0) {
      throw StateError(
        'litert_lm_conversation_get_token_count returned $count',
      );
    }
    return count;
  }

  /// Replaces the active conversation with a native clone of itself.
  void replaceConversationWithClone() {
    final bindings = _requireBindings();
    final conversation = _requireConversation();
    final clone = bindings.conversationClone(conversation);
    if (clone == nullptr) {
      throw StateError('litert_lm_conversation_clone returned null');
    }
    bindings.conversationDelete(conversation);
    _conversation = clone;
  }

  /// Streams generated text from the active conversation.
  Stream<String> generate(String prompt, {int? maxOutputTokens}) {
    return generateMessageJson(
      _messageJson(prompt),
      maxOutputTokens: maxOutputTokens,
    );
  }

  /// Streams generated text by sending a native LiteRT-LM message JSON object.
  ///
  /// [visualTokenBudget] configures the native image-token budget for
  /// multimodal messages.
  Stream<String> generateMessageJson(
    String messageJson, {
    Map<String, dynamic>? extraContext,
    int? visualTokenBudget,
    int? maxOutputTokens,
  }) {
    final resolvedMaxOutputTokens = maxOutputTokens ?? _defaultMaxOutputTokens;
    if (visualTokenBudget != null && visualTokenBudget <= 0) {
      throw ArgumentError.value(
        visualTokenBudget,
        'visualTokenBudget',
        'must be positive when provided',
      );
    }
    if (resolvedMaxOutputTokens <= 0) {
      throw ArgumentError.value(
        resolvedMaxOutputTokens,
        'maxOutputTokens',
        'must be positive when provided',
      );
    }
    // Upstream stream callback strings are only valid during the native call.
    // Dart listener callbacks run later, so streaming requires StreamProxy to
    // copy those strings across the thread/isolate boundary.
    final extraContextJson = extraContext == null || extraContext.isEmpty
        ? null
        : jsonEncode(extraContext);
    if (_proxyCreate == null) {
      return _generateBlockingMessageJson(
        messageJson,
        extraContextJson: extraContextJson,
        visualTokenBudget: visualTokenBudget,
        maxOutputTokens: resolvedMaxOutputTokens,
      );
    }
    return _generateStreamingMessageJson(
      messageJson,
      extraContextJson: extraContextJson,
      visualTokenBudget: visualTokenBudget,
      maxOutputTokens: resolvedMaxOutputTokens,
    );
  }

  Stream<String> _generateBlockingMessageJson(
    String messageJson, {
    String? extraContextJson,
    int? visualTokenBudget,
    int? maxOutputTokens,
  }) {
    final conversation = _requireConversation();
    final liteRtLmLibraryPath = _liteRtLmLibraryPath!;
    final controller = StreamController<String>(onCancel: cancel);
    final request = _BlockingSendMessageRequest(
      libraryPath: liteRtLmLibraryPath,
      companionLibraryPaths: _liteRtLmCompanionLibraryPaths,
      conversationAddress: conversation.address,
      messageJson: messageJson,
      extraContextJson: extraContextJson,
      visualTokenBudget: visualTokenBudget,
      maxOutputTokens: maxOutputTokens,
    );

    unawaited(() async {
      try {
        final raw = await _runBlockingSendMessageInIsolate(request);
        if (!controller.isClosed) {
          final assembler = LiteRtLmChannelAssembler(
            thinkingStartTag: _thinkingStartTag,
            thinkingEndTag: _thinkingEndTag,
          );
          final text = assembler.add(raw) + assembler.flush();
          if (text.isNotEmpty) {
            controller.add(text);
          }
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      } finally {
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }());

    return controller.stream;
  }

  Stream<String> _generateStreamingMessageJson(
    String messageJson, {
    String? extraContextJson,
    int? visualTokenBudget,
    int? maxOutputTokens,
  }) {
    final bindings = _requireBindings();
    final conversation = _requireConversation();
    final messagePtr = messageJson.toNativeUtf8(allocator: calloc);
    final extraContextPtr = extraContextJson == null
        ? nullptr
        : extraContextJson.toNativeUtf8(allocator: calloc);
    final assembler = LiteRtLmChannelAssembler(
      thinkingStartTag: _thinkingStartTag,
      thinkingEndTag: _thinkingEndTag,
    );
    Pointer<Void> callbackData = nullptr;
    var cleanedUp = false;

    late final NativeCallable<_StreamCallbackNative> callable;
    late final StreamController<String> controller;
    void cleanup() {
      if (cleanedUp) {
        return;
      }
      cleanedUp = true;
      if (callbackData != nullptr) {
        _proxyDelete?.call(callbackData);
        callbackData = nullptr;
      }
      callable.close();
      calloc.free(messagePtr);
      if (extraContextPtr != nullptr) {
        calloc.free(extraContextPtr);
      }
    }

    controller = StreamController<String>(
      onCancel: () {
        // Signal the native side to stop, but do NOT run cleanup() here:
        // closing the NativeCallable while the runtime may still invoke it is
        // unsafe. cancellation drives the runtime to deliver a terminal
        // CANCELLED/error callback, and cleanup() runs from there (below). A
        // timer-based backstop is deliberately avoided: closing the callable
        // while a later native callback is still possible would crash. If the
        // runtime never delivers a terminal callback the callback resources
        // leak, which is preferable to a use-after-free.
        cancel();
      },
    );

    callable = NativeCallable<_StreamCallbackNative>.listener((
      Pointer<Void> data,
      Pointer<Char> chunk,
      bool isFinal,
      Pointer<Char> errorMessage,
    ) {
      if (errorMessage != nullptr) {
        final error = errorMessage.cast<Utf8>().toDartString();
        _proxyFreeString?.call(errorMessage);
        if (error.startsWith('CANCELLED')) {
          if (!controller.isClosed) {
            unawaited(controller.close());
          }
        } else {
          if (!controller.isClosed) {
            controller.addError(StateError(error));
            unawaited(controller.close());
          }
        }
        cleanup();
        return;
      }

      if (chunk != nullptr) {
        final raw = chunk.cast<Utf8>().toDartString();
        _proxyFreeString?.call(chunk);
        final text = assembler.add(raw);
        if (text.isNotEmpty && !controller.isClosed) {
          controller.add(text);
        }
      }

      if (isFinal) {
        final tail = assembler.flush();
        if (tail.isNotEmpty && !controller.isClosed) {
          controller.add(tail);
        }
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
        cleanup();
      }
    });

    var callbackFn = callable.nativeFunction;
    final proxyCreate = _proxyCreate;
    if (proxyCreate != null) {
      final outProxyFn =
          calloc<Pointer<NativeFunction<_StreamCallbackNative>>>();
      try {
        callbackData = proxyCreate(
          callable.nativeFunction,
          nullptr,
          outProxyFn,
        );
        callbackFn = outProxyFn.value;
        if (callbackData == nullptr || callbackFn == nullptr) {
          throw StateError('stream_proxy_create returned null');
        }
      } catch (_) {
        cleanup();
        rethrow;
      } finally {
        calloc.free(outProxyFn);
      }
    }

    Pointer<_LiteRtLmConversationOptionalArgs> optionalArgs = nullptr;
    try {
      optionalArgs = bindings.conversationOptionalArgsCreate();
      if (optionalArgs == nullptr) {
        throw StateError(
          'litert_lm_conversation_optional_args_create returned null',
        );
      }
      _setConversationOptionalArgs(
        bindings,
        optionalArgs,
        visualTokenBudget: visualTokenBudget,
        maxOutputTokens: maxOutputTokens,
      );

      final rc = bindings.conversationSendMessageStream(
        conversation,
        messagePtr.cast(),
        extraContextPtr.cast(),
        optionalArgs,
        callbackFn.cast(),
        callbackData,
      );
      if (rc != 0) {
        throw StateError('litert_lm_conversation_send_message_stream rc=$rc');
      }
    } catch (_) {
      cleanup();
      rethrow;
    } finally {
      if (optionalArgs != nullptr) {
        bindings.conversationOptionalArgsDelete(optionalArgs);
      }
    }

    return controller.stream;
  }

  List<int> _tokenizeRaw(String text) {
    final bindings = _requireBindings();
    final engine = _requireEngine();
    final textPtr = text.toNativeUtf8(allocator: calloc);
    Pointer<_LiteRtLmTokenizeResult> result = nullptr;
    try {
      result = bindings.engineTokenize(engine, textPtr.cast());
      if (result == nullptr) {
        throw StateError('litert_lm_engine_tokenize returned null');
      }
      final count = bindings.tokenizeResultGetNumTokens(result);
      final tokenPtr = bindings.tokenizeResultGetTokens(result);
      if (count > 0 && tokenPtr == nullptr) {
        throw StateError('litert_lm_tokenize_result_get_tokens returned null');
      }
      return List<int>.generate(count, (index) => tokenPtr[index]);
    } finally {
      if (result != nullptr) {
        bindings.tokenizeResultDelete(result);
      }
      calloc.free(textPtr);
    }
  }

  List<int> _readStartToken() {
    final bindings = _requireBindings();
    final engine = _requireEngine();
    final tokenUnion = bindings.engineGetStartToken(engine);
    if (tokenUnion == nullptr) {
      return const <int>[];
    }
    try {
      final type = bindings.tokenUnionGetType(tokenUnion);
      if (type == 1) {
        final tokensOut = calloc<Pointer<Int>>();
        final countOut = calloc<Size>();
        try {
          final rc = bindings.tokenUnionGetIds(tokenUnion, tokensOut, countOut);
          final tokenPtr = tokensOut.value;
          final count = countOut.value;
          if (rc != 0 || count == 0 || tokenPtr == nullptr) {
            return const <int>[];
          }
          return List<int>.generate(count, (index) => tokenPtr[index]);
        } finally {
          calloc.free(tokensOut);
          calloc.free(countOut);
        }
      }

      if (type == 0) {
        final textPtr = bindings.tokenUnionGetString(tokenUnion);
        if (textPtr == nullptr) {
          return const <int>[];
        }
        final text = textPtr.cast<Utf8>().toDartString();
        return text.isEmpty ? const <int>[] : _tokenizeRaw(text);
      }

      return const <int>[];
    } finally {
      bindings.tokenUnionDelete(tokenUnion);
    }
  }

  /// Runs a benchmark-style prompt loop and returns runtime metrics.
  Future<LiteRtLmRuntimeResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,
  }) async {
    if (warmupRuns < 0) {
      throw ArgumentError.value(warmupRuns, 'warmupRuns', 'must be >= 0');
    }
    if (measuredRuns <= 0) {
      throw ArgumentError.value(measuredRuns, 'measuredRuns', 'must be > 0');
    }

    for (var i = 0; i < warmupRuns; i++) {
      createConversation();
      await generate(prompt).drain<void>();
    }

    var lastText = '';
    late LiteRtLmRuntimeMetrics metrics;
    for (var i = 0; i < measuredRuns; i++) {
      createConversation();
      final buffer = StringBuffer();
      final sw = Stopwatch()..start();
      await for (final chunk in generate(prompt)) {
        buffer.write(chunk);
      }
      sw.stop();
      lastText = buffer.toString();
      metrics = _readMetrics(sw.elapsedMilliseconds);
    }

    return LiteRtLmRuntimeResult(text: lastText, metrics: metrics);
  }

  /// Reads runtime metrics for the active conversation.
  LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds}) {
    return _readMetrics(wallMilliseconds);
  }

  /// Cancels active native generation.
  void cancel() {
    final conversation = _conversation;
    final bindings = _bindings;
    if (conversation != null && conversation != nullptr && bindings != null) {
      bindings.conversationCancelProcess(conversation);
    }
  }

  /// Releases native LiteRT-LM resources.
  void dispose() {
    _deleteConversation();
    final engine = _engine;
    final bindings = _bindings;
    if (engine != null && engine != nullptr && bindings != null) {
      bindings.engineDelete(engine);
    }
    _engine = null;
    _defaultMaxOutputTokens = 256;
  }

  void _ensureLibrariesLoaded() {
    if (_bindings != null) {
      return;
    }
    final libraries = _librariesForCurrentPlatform();
    if (libraries == null) {
      throw UnsupportedError('LiteRT-LM does not support ${Abi.current()}.');
    }

    final companionLibraries = _openCompanionLibraries(libraries.companions);

    final liteRtLm = _openFirstAvailableWithPath(
      libraries.liteRtLmCandidates,
      description: 'LiteRT-LM library',
    );
    _liteRtLmLibraryPath = liteRtLm.path;
    _liteRtLmCompanionLibraryPaths = libraries.companions;
    _companionLibraries = companionLibraries;
    _tryLoadEmbeddedStreamProxy(
      liteRtLm.library,
      liteRtLm.path,
      libraries.directCallbackSupported,
    );
    _bindings = _LiteRtLmBindings(liteRtLm.library);
  }

  ({
    List<String> liteRtLmCandidates,
    List<String> companions,
    bool directCallbackSupported,
  })?
  _librariesForCurrentPlatform() {
    final abi = Abi.current();
    if (Platform.isAndroid &&
        (abi == Abi.androidArm64 || abi == Abi.androidX64)) {
      return (
        liteRtLmCandidates: const ['libLiteRtLm.so'],
        companions: const [],
        directCallbackSupported: true,
      );
    }
    if (Platform.isIOS && (abi == Abi.iosArm64 || abi == Abi.iosX64)) {
      // The LiteRT-LM frameworks are embedded under
      // `<App>.app/Frameworks/<Name>.framework/<Name>`. Resolving their absolute
      // paths from the executable lets dlopen and the isolate re-open receive a
      // real path (the `package:` native-asset ids never load via
      // `DynamicLibrary.open`).
      final frameworksDirPath = _findIosAppFrameworksDir()?.path;
      return (
        liteRtLmCandidates: liteRtLmIosLibraryCandidates(
          abi,
          frameworksDirPath: frameworksDirPath,
        ),
        companions: const [],
        directCallbackSupported: true,
      );
    }
    if (Platform.isMacOS && (abi == Abi.macosArm64 || abi == Abi.macosX64)) {
      final companions = _macOsCompanionLibrariesForAbi(abi);
      final frameworksDir = _findMacOsAppFrameworksDir();
      if (frameworksDir != null) {
        final usesNativeSpmFramework = File(
          '${frameworksDir.path}/LiteRtLm.framework/Versions/A/LiteRtLm',
        ).existsSync();
        return (
          liteRtLmCandidates: liteRtLmMacOsLibraryCandidates(
            '${frameworksDir.path}/LiteRtLm.framework/Versions/A/LiteRtLm',
            explicitOverride: false,
          ),
          companions: usesNativeSpmFramework
              ? const []
              : [
                  for (final library in companions)
                    _macOsFrameworkBinaryPath(frameworksDir, library),
                ],
          directCallbackSupported: true,
        );
      }
      final appLibraryDir = _findMacOsAppLibraryDir();
      if (appLibraryDir != null) {
        return (
          liteRtLmCandidates: liteRtLmMacOsLibraryCandidates(
            '${appLibraryDir.path}/libLiteRtLm.dylib',
            explicitOverride: false,
          ),
          companions: [
            for (final library in companions) '${appLibraryDir.path}/$library',
          ],
          directCallbackSupported: true,
        );
      }
      final cacheDir = _findMacOsLiteRtLmCacheDir();
      if (cacheDir != null) {
        final explicitOverride =
            Platform.environment[_litertLmLibDirEnv]?.trim().isNotEmpty ??
            false;
        return (
          liteRtLmCandidates: liteRtLmMacOsLibraryCandidates(
            '${cacheDir.path}/libLiteRtLm.dylib',
            explicitOverride: explicitOverride,
          ),
          companions: [
            for (final library in companions) '${cacheDir.path}/$library',
          ],
          directCallbackSupported: true,
        );
      }
      return (
        liteRtLmCandidates: const [
          _processLibraryCandidate,
          'libLiteRtLm.dylib',
        ],
        companions: [for (final library in companions) library],
        directCallbackSupported: true,
      );
    }
    if (Platform.isLinux && (abi == Abi.linuxX64 || abi == Abi.linuxArm64)) {
      final cacheDir = _findLiteRtLmCacheDirForAbi(abi);
      if (cacheDir != null) {
        return (
          liteRtLmCandidates: ['${cacheDir.path}/libLiteRtLm.so'],
          companions: _companionLibrariesForAbi(abi, cacheDir),
          directCallbackSupported: true,
        );
      }
      return (
        liteRtLmCandidates: const ['package:llamadart/litert_lm_LiteRtLm'],
        companions: const [],
        directCallbackSupported: true,
      );
    }
    if (Platform.isWindows && abi == Abi.windowsX64) {
      final cacheDir = _findLiteRtLmCacheDirForAbi(abi);
      if (cacheDir != null) {
        return (
          liteRtLmCandidates: ['${cacheDir.path}/LiteRtLm.dll'],
          companions: _companionLibrariesForAbi(abi, cacheDir),
          directCallbackSupported: true,
        );
      }
      return (
        liteRtLmCandidates: const ['package:llamadart/litert_lm_LiteRtLm'],
        companions: const [],
        directCallbackSupported: true,
      );
    }
    return null;
  }

  ({String path, DynamicLibrary library}) _openFirstAvailableWithPath(
    List<String> candidates, {
    required String description,
  }) {
    final errors = <String>[];
    for (final candidate in candidates) {
      try {
        final library = _openLiteRtLmLibraryCandidate(candidate);
        _validateLiteRtLmLibrary(library);
        return (path: candidate, library: library);
      } catch (error) {
        errors.add('  - $candidate: $error');
      }
    }
    throw ArgumentError(
      'Failed to load any $description candidate:\n${errors.join('\n')}',
    );
  }

  void _tryLoadEmbeddedStreamProxy(
    DynamicLibrary liteRtLmLibrary,
    String liteRtLmPath,
    bool directCallbackSupported,
  ) {
    _validateEmbeddedStreamProxyCompatibility(liteRtLmLibrary);
    try {
      _loadRuntimeGloballyIfAvailable(liteRtLmLibrary, liteRtLmPath);
      final proxyCreate = liteRtLmLibrary
          .lookupFunction<_ProxyCreateNative, _ProxyCreateDart>(
            'stream_proxy_create',
          );
      final proxyFreeString = liteRtLmLibrary
          .lookupFunction<_ProxyFreeStringNative, _ProxyFreeStringDart>(
            'stream_proxy_free_string',
          );
      final proxyDelete = liteRtLmLibrary
          .lookupFunction<_ProxyDeleteNative, _ProxyDeleteDart>(
            'stream_proxy_delete',
          );

      _proxyCreate = proxyCreate;
      _proxyFreeString = proxyFreeString;
      _proxyDelete = proxyDelete;
      _proxyLibrary = liteRtLmLibrary;
    } catch (error) {
      _proxyCreate = null;
      _proxyFreeString = null;
      _proxyDelete = null;
      _proxyLibrary = null;
      if (!directCallbackSupported) {
        throw StateError(
          'LiteRT-LM runtime does not export embedded StreamProxy symbols: '
          '$error',
        );
      }
    }
  }

  void _validateEmbeddedStreamProxyCompatibility(
    DynamicLibrary liteRtLmLibrary,
  ) {
    final hasStreamProxy = const [
      'stream_proxy_create',
      'stream_proxy_free_string',
      'stream_proxy_delete',
    ].every((symbol) => _hasNativeSymbol(liteRtLmLibrary, symbol));
    final hasStreamChunkApi = _hasNativeSymbol(
      liteRtLmLibrary,
      'litert_lm_stream_chunk_get_text',
    );
    int? callbackAbiVersion;
    if (hasStreamProxy) {
      try {
        callbackAbiVersion = liteRtLmLibrary
            .lookupFunction<
              _ProxyCallbackAbiVersionNative,
              _ProxyCallbackAbiVersionDart
            >('stream_proxy_callback_abi_version')();
      } on ArgumentError {
        callbackAbiVersion = null;
      }
    }
    final compatibilityError = liteRtLmStreamProxyCompatibilityError(
      hasStreamProxy: hasStreamProxy,
      hasStreamChunkApi: hasStreamChunkApi,
      callbackAbiVersion: callbackAbiVersion,
    );
    if (compatibilityError != null) {
      throw LlamaUnsupportedException(compatibilityError);
    }
  }

  void _loadRuntimeGloballyIfAvailable(
    DynamicLibrary liteRtLmLibrary,
    String liteRtLmPath,
  ) {
    try {
      final loadGlobal = liteRtLmLibrary
          .lookupFunction<_LoadGlobalNative, _LoadGlobalDart>(
            'stream_proxy_load_global',
          );
      final liteRtLmName = liteRtLmPath.toNativeUtf8(allocator: calloc);
      try {
        loadGlobal(liteRtLmName);
      } finally {
        calloc.free(liteRtLmName);
      }
    } catch (_) {
      // Loading the already-open runtime globally is best-effort. The proxy
      // functions themselves are resolved from the active LiteRtLm handle below.
    }
  }

  Directory? _findMacOsAppFrameworksDir() {
    final executable = File(Platform.resolvedExecutable);
    final contentsDir = executable.parent.parent;
    final frameworksDir = Directory('${contentsDir.path}/Frameworks');
    if (!frameworksDir.existsSync()) {
      return null;
    }
    final requiredNativeSpmFiles = liteRtLmMacOsRequiredNativeSpmFilesForAbi(
      Abi.current(),
    );
    if (requiredNativeSpmFiles.isNotEmpty &&
        requiredNativeSpmFiles.every(
          (file) => File('${frameworksDir.path}/$file').existsSync(),
        )) {
      return frameworksDir;
    }
    final requiredFrameworks = liteRtLmMacOsRequiredFrameworksForAbi(
      Abi.current(),
    );
    if (requiredFrameworks.isEmpty) {
      return null;
    }
    final requiredFiles = [
      for (final framework in requiredFrameworks)
        '${frameworksDir.path}/$framework',
    ];
    if (requiredFiles.every((file) => File(file).existsSync())) {
      return frameworksDir;
    }
    return null;
  }

  Directory? _findMacOsAppLibraryDir() {
    final executable = File(Platform.resolvedExecutable);
    final contentsDir = executable.parent.parent;
    final libraryDir = Directory(
      '${contentsDir.path}/Frameworks/LiteRtLmRuntime',
    );
    if (!libraryDir.existsSync()) {
      return null;
    }
    return liteRtLmIsMacOsCacheDirectoryForAbi(libraryDir, Abi.current())
        ? libraryDir
        : null;
  }

  /// Locates the `Frameworks` directory of the running iOS `.app` bundle when
  /// it contains the embedded LiteRT-LM framework.
  ///
  /// iOS frameworks are flat (`<App>.app/Frameworks/<Name>.framework/<Name>`),
  /// unlike the versioned macOS layout, and the executable lives directly in
  /// the bundle root (`<App>.app/<Executable>`).
  Directory? _findIosAppFrameworksDir() {
    final executable = File(Platform.resolvedExecutable);
    final frameworksDir = Directory('${executable.parent.path}/Frameworks');
    if (!frameworksDir.existsSync()) {
      return null;
    }
    final upstream = File(
      liteRtLmIosFrameworkBinaryPath(frameworksDir.path, 'CLiteRTLM'),
    );
    if (upstream.existsSync()) {
      return frameworksDir;
    }
    final liteRtLm = File(
      liteRtLmIosFrameworkBinaryPath(frameworksDir.path, 'LiteRtLm'),
    );
    return liteRtLm.existsSync() ? frameworksDir : null;
  }

  Directory? _findMacOsLiteRtLmCacheDir() {
    return _findLiteRtLmCacheDirForAbi(Abi.current());
  }

  Directory? _findLiteRtLmCacheDirForAbi(Abi abi) {
    final envPath = Platform.environment[_litertLmLibDirEnv];
    if (envPath != null && envPath.isNotEmpty) {
      final dir = Directory(envPath);
      if (liteRtLmIsCacheDirectoryForAbi(dir, abi)) {
        return dir.absolute;
      }
    }

    final cacheDirectoryCandidates = liteRtLmCacheDirectoryCandidatesForAbi(
      abi,
    );

    for (final root in _candidateSearchRoots()) {
      Directory? current = root;
      while (current != null) {
        for (final cacheDirectoryCandidate in cacheDirectoryCandidates) {
          final candidate = Directory(
            '${current.path}/.dart_tool/llamadart/litert_lm/'
            '$_litertLmVersion/$cacheDirectoryCandidate',
          );
          if (liteRtLmIsCacheDirectoryForAbi(candidate, abi)) {
            return candidate;
          }
        }
        current = current.parent.path == current.path ? null : current.parent;
      }
    }
    return null;
  }

  List<Directory> _candidateSearchRoots() {
    final roots = <String>{Directory.current.path};
    final scriptPath = Platform.script.toFilePath();
    if (scriptPath.isNotEmpty) {
      roots.add(File(scriptPath).parent.path);
    }
    roots.add(File(Platform.resolvedExecutable).parent.path);
    roots.addAll(_llamadartPackageRootsFromNearestPackageConfigs(roots));
    return roots.map(Directory.new).toList();
  }

  List<String> _macOsCompanionLibrariesForAbi(Abi abi) {
    return liteRtLmMacOsRequiredLibrariesForAbi(abi)
        .where((library) => library != 'libLiteRtLm.dylib')
        .toList(growable: false);
  }

  List<String> _companionLibrariesForAbi(Abi abi, Directory dir) {
    final liteRtLm = _liteRtLmLibraryFileNameForAbi(abi);
    if (liteRtLm == null) {
      return const <String>[];
    }
    return liteRtLmRequiredLibrariesForAbi(abi)
        .where((library) => library != liteRtLm)
        .map((library) => '${dir.path}/$library')
        .toList(growable: false);
  }

  List<String> _llamadartPackageRootsFromNearestPackageConfigs(
    Iterable<String> roots,
  ) {
    final packageRoots = <String>{};
    final visitedConfigs = <String>{};
    for (final root in roots) {
      Directory? current = Directory(root).absolute;
      while (current != null) {
        final packageConfig = File(
          '${current.path}/.dart_tool/package_config.json',
        );
        if (packageConfig.existsSync() &&
            visitedConfigs.add(packageConfig.path)) {
          packageRoots.addAll(
            liteRtLmPackageRootsFromPackageConfig(packageConfig),
          );
        }
        current = current.parent.path == current.path ? null : current.parent;
      }
    }
    return packageRoots.toList(growable: false);
  }

  String? _liteRtLmLibraryFileNameForAbi(Abi abi) {
    return switch (abi) {
      Abi.macosArm64 => 'libLiteRtLm.dylib',
      Abi.macosX64 => 'libLiteRtLm.dylib',
      Abi.linuxArm64 => 'libLiteRtLm.so',
      Abi.linuxX64 => 'libLiteRtLm.so',
      Abi.windowsX64 => 'LiteRtLm.dll',
      _ => null,
    };
  }

  String _macOsFrameworkBinaryPath(Directory frameworksDir, String library) {
    final frameworkName = _macOsFrameworkNameForLibrary(library);
    return '${frameworksDir.path}/$frameworkName.framework/Versions/A/'
        '$frameworkName';
  }

  String _macOsFrameworkNameForLibrary(String library) {
    final basename = path.basenameWithoutExtension(library);
    return basename.startsWith('lib') ? basename.substring(3) : basename;
  }

  _LiteRtLmBindings _requireBindings() {
    final bindings = _bindings;
    if (bindings == null) {
      throw StateError('LiteRT-LM bindings are not initialized.');
    }
    return bindings;
  }

  Pointer<_LiteRtLmEngine> _requireEngine() {
    final engine = _engine;
    if (engine == null || engine == nullptr) {
      throw StateError('LiteRT-LM engine is not initialized.');
    }
    return engine;
  }

  Pointer<_LiteRtLmConversation> _requireConversation() {
    final conversation = _conversation;
    if (conversation == null || conversation == nullptr) {
      throw StateError('LiteRT-LM conversation is not initialized.');
    }
    return conversation;
  }

  void _deleteConversation() {
    final conversation = _conversation;
    final bindings = _bindings;
    if (conversation != null && conversation != nullptr && bindings != null) {
      bindings.conversationDelete(conversation);
    }
    _conversation = null;
  }

  LiteRtLmRuntimeMetrics _readMetrics(int wallMilliseconds) {
    final bindings = _requireBindings();
    final conversation = _requireConversation();
    final info = bindings.conversationGetBenchmarkInfo(conversation);
    if (info == nullptr) {
      return LiteRtLmRuntimeMetrics(
        inputTokens: 0,
        outputTokens: 0,
        timeToFirstTokenSeconds: null,
        initSeconds: null,
        prefillTokensPerSecond: null,
        decodeTokensPerSecond: null,
        wallMilliseconds: wallMilliseconds,
      );
    }
    try {
      final prefillTurns = bindings.benchmarkInfoGetNumPrefillTurns(info);
      final decodeTurns = bindings.benchmarkInfoGetNumDecodeTurns(info);
      var inputTokens = 0;
      var outputTokens = 0;
      for (var i = 0; i < prefillTurns; i++) {
        inputTokens += bindings.benchmarkInfoGetPrefillTokenCountAt(info, i);
      }
      for (var i = 0; i < decodeTurns; i++) {
        outputTokens += bindings.benchmarkInfoGetDecodeTokenCountAt(info, i);
      }
      final prefillTps = prefillTurns == 0
          ? null
          : bindings.benchmarkInfoGetPrefillTokensPerSecAt(
              info,
              prefillTurns - 1,
            );
      final decodeTps = decodeTurns == 0
          ? null
          : bindings.benchmarkInfoGetDecodeTokensPerSecAt(
              info,
              decodeTurns - 1,
            );
      return LiteRtLmRuntimeMetrics(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        timeToFirstTokenSeconds: bindings.benchmarkInfoGetTimeToFirstToken(
          info,
        ),
        initSeconds: bindings.benchmarkInfoGetTotalInitTimeInSecond(info),
        prefillTokensPerSecond: prefillTps,
        decodeTokensPerSecond: decodeTps,
        wallMilliseconds: wallMilliseconds,
      );
    } finally {
      bindings.benchmarkInfoDelete(info);
    }
  }
}

String _normalizeLiteRtLmRuntimeBackend(
  String backend, {
  String name = 'backend',
}) {
  final normalized = backend.trim().toLowerCase();
  if (normalized == 'cpu' || normalized == 'gpu' || normalized == 'npu') {
    return normalized;
  }
  throw ArgumentError.value(backend, name, 'must be cpu, gpu, or npu');
}

String _messageJson(String text) {
  return jsonEncode({
    'role': 'user',
    'content': [
      {'type': 'text', 'text': text},
    ],
  });
}

String _systemMessageJson(String textOrJson) {
  try {
    final decoded = jsonDecode(textOrJson);
    if (decoded is Map<String, dynamic>) {
      return textOrJson;
    }
  } on FormatException {
    // Plain text system messages are wrapped below.
  }
  return jsonEncode({
    'role': 'system',
    'content': [
      {'type': 'text', 'text': textOrJson},
    ],
  });
}

void _setConversationOptionalArgs(
  _LiteRtLmBindings bindings,
  Pointer<_LiteRtLmConversationOptionalArgs> optionalArgs, {
  int? visualTokenBudget,
  int? maxOutputTokens,
}) {
  if (visualTokenBudget != null) {
    bindings.conversationOptionalArgsSetVisualTokenBudget(
      optionalArgs,
      visualTokenBudget,
    );
  }
  if (maxOutputTokens != null) {
    final setter = bindings.conversationOptionalArgsSetMaxOutputTokens;
    if (setter == null) {
      throw UnsupportedError(
        'LiteRT-LM per-request maxOutputTokens requires native runtime '
        'v0.14.0 or newer because '
        'litert_lm_conversation_optional_args_set_max_output_tokens is '
        'missing.',
      );
    }
    setter(optionalArgs, maxOutputTokens);
  }
}

void _setSessionSamplerParams(
  _LiteRtLmBindings bindings,
  Pointer<_LiteRtLmSessionConfig> sessionConfig, {
  required int topK,
  required double topP,
  required double temperature,
  required int seed,
}) {
  final create = bindings.samplerParamsCreate;
  final delete = bindings.samplerParamsDelete;
  if (create != null && delete != null) {
    final setTopK = bindings.samplerParamsSetTopK;
    final setTopP = bindings.samplerParamsSetTopP;
    final setTemperature = bindings.samplerParamsSetTemperature;
    final setSeed = bindings.samplerParamsSetSeed;
    if (setTopK == null ||
        setTopP == null ||
        setTemperature == null ||
        setSeed == null) {
      throw UnsupportedError(
        'LiteRT-LM opaque sampler params require native runtime v0.14.0 or '
        'newer with all sampler setter symbols available.',
      );
    }
    final sampler = create(2);
    if (sampler == nullptr) {
      throw StateError('litert_lm_sampler_params_create returned null');
    }
    try {
      setTopK(sampler, topK);
      setTopP(sampler, topP);
      setTemperature(sampler, temperature);
      setSeed(sampler, seed);
      bindings.sessionConfigSetSamplerParams(sessionConfig, sampler.cast());
    } finally {
      delete(sampler);
    }
    return;
  }

  final sampler = calloc<_LegacyLiteRtLmSamplerParams>();
  try {
    sampler.ref
      ..type = 2
      ..topK = topK
      ..topP = topP
      ..temperature = temperature
      ..seed = seed;
    bindings.sessionConfigSetSamplerParams(sessionConfig, sampler.cast());
  } finally {
    calloc.free(sampler);
  }
}

void _setSessionLoraPath(
  _LiteRtLmBindings bindings,
  Pointer<_LiteRtLmSessionConfig> sessionConfig,
  String? loraPath,
) {
  if (loraPath == null) {
    return;
  }
  final setter = bindings.sessionConfigSetLoraPath;
  if (setter == null) {
    throw UnsupportedError(
      'LiteRT-LM initial LoRA adapters require native runtime v0.14.0 or '
      'newer because litert_lm_session_config_set_lora_path is missing.',
    );
  }
  final loraPathPtr = loraPath.toNativeUtf8(allocator: calloc);
  try {
    final result = setter(sessionConfig, loraPathPtr.cast());
    if (result != 0) {
      throw StateError('litert_lm_session_config_set_lora_path failed.');
    }
  } finally {
    calloc.free(loraPathPtr);
  }
}

Future<String> _runBlockingSendMessageInIsolate(
  _BlockingSendMessageRequest request,
) {
  return Isolate.run(() => _runBlockingSendMessage(request));
}

String _runBlockingSendMessage(_BlockingSendMessageRequest request) {
  final companionLibraries = _openCompanionLibraries(
    request.companionLibraryPaths,
  );
  try {
    final bindings = _LiteRtLmBindings(
      _openLiteRtLmLibraryCandidate(request.libraryPath),
    );
    final conversation = Pointer<_LiteRtLmConversation>.fromAddress(
      request.conversationAddress,
    );
    final messagePtr = request.messageJson.toNativeUtf8(allocator: calloc);
    final extraContextPtr = request.extraContextJson == null
        ? nullptr
        : request.extraContextJson!.toNativeUtf8(allocator: calloc);
    Pointer<_LiteRtLmConversationOptionalArgs> optionalArgs = nullptr;
    try {
      optionalArgs = bindings.conversationOptionalArgsCreate();
      if (optionalArgs == nullptr) {
        throw StateError(
          'litert_lm_conversation_optional_args_create returned null',
        );
      }
      _setConversationOptionalArgs(
        bindings,
        optionalArgs,
        visualTokenBudget: request.visualTokenBudget,
        maxOutputTokens: request.maxOutputTokens,
      );

      final response = bindings.conversationSendMessage(
        conversation,
        messagePtr.cast(),
        extraContextPtr.cast(),
        optionalArgs,
      );
      if (response == nullptr) {
        throw StateError('litert_lm_conversation_send_message returned null');
      }

      try {
        final rawPtr = bindings.jsonResponseGetString(response);
        if (rawPtr == nullptr) {
          throw StateError('litert_lm_json_response_get_string returned null');
        }
        return rawPtr.cast<Utf8>().toDartString();
      } finally {
        bindings.jsonResponseDelete(response);
      }
    } finally {
      if (optionalArgs != nullptr) {
        bindings.conversationOptionalArgsDelete(optionalArgs);
      }
      calloc.free(messagePtr);
      if (extraContextPtr != nullptr) {
        calloc.free(extraContextPtr);
      }
    }
  } finally {
    _keepAlive(companionLibraries);
  }
}

DynamicLibrary _openLiteRtLmLibraryCandidate(String candidate) {
  return candidate == _processLibraryCandidate
      ? DynamicLibrary.process()
      : DynamicLibrary.open(candidate);
}

bool _hasNativeSymbol(DynamicLibrary library, String symbol) {
  try {
    library.lookup<NativeFunction<Void Function()>>(symbol);
    return true;
  } on ArgumentError {
    return false;
  }
}

List<DynamicLibrary> _openCompanionLibraries(Iterable<String> companions) {
  final libraries = <DynamicLibrary>[];
  for (final companion in companions) {
    if (File(companion).existsSync() || !path.isAbsolute(companion)) {
      libraries.add(DynamicLibrary.open(companion));
    }
  }
  return libraries;
}

void _keepAlive(Object? value) {}

void _validateLiteRtLmLibrary(DynamicLibrary library) {
  library.lookup<NativeFunction<Void Function()>>(
    'litert_lm_engine_settings_create',
  );
}

/// Reassembles LiteRT-LM streaming response chunks into the textual form the
/// chat-template handlers parse.
///
/// The native runtime emits thinking and final content on separate channels:
/// thought as `{"role":"assistant","channels":{"thought":"..."}}` and the
/// answer as `{"role":"assistant","content":[{"type":"text","text":"..."}]}`.
/// Thought runs are wrapped in the active chat handler's reasoning tags so
/// downstream parsing surfaces them as reasoning instead of leaking raw JSON.
class LiteRtLmChannelAssembler {
  /// Gemma 4 reasoning start marker.
  static const String gemma4ThinkingStartTag = '<|channel>thought\n';

  /// Gemma 4 reasoning end marker.
  static const String gemma4ThinkingEndTag = '<channel|>';

  /// Creates a response-channel assembler.
  LiteRtLmChannelAssembler({
    this.thinkingStartTag = gemma4ThinkingStartTag,
    this.thinkingEndTag = gemma4ThinkingEndTag,
  });

  /// Marker used to open a thought run.
  final String thinkingStartTag;

  /// Marker used to close a thought run.
  final String thinkingEndTag;

  bool _inThought = false;

  /// Converts one native response [raw] chunk into handler-facing text.
  String add(String raw) {
    final chunk = _parseLiteRtLmChunk(raw);
    final buffer = StringBuffer();
    final thought = chunk.thought;
    if (thought != null && thought.isNotEmpty) {
      if (!_inThought) {
        buffer.write(thinkingStartTag);
        _inThought = true;
      }
      buffer.write(thought);
    }
    final content = chunk.content;
    if (content != null && content.isNotEmpty) {
      buffer.write(_closeThoughtIfOpen());
      buffer.write(content);
    }
    return buffer.toString();
  }

  /// Closes a still-open thought run at end of stream (e.g. token-limit cutoff).
  String flush() => _closeThoughtIfOpen();

  String _closeThoughtIfOpen() {
    if (!_inThought) {
      return '';
    }
    _inThought = false;
    return thinkingEndTag;
  }
}

({String? thought, String? content}) _parseLiteRtLmChunk(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return (thought: null, content: raw);
    }

    final channels = decoded['channels'];
    String? thought;
    final contentBuffer = StringBuffer();
    if (channels is Map<String, dynamic>) {
      channels.forEach((channel, value) {
        if (value is! String) {
          return;
        }
        if (channel == 'thought') {
          thought = (thought ?? '') + value;
        } else {
          // Non-thought channels are surfaced as ordinary content.
          contentBuffer.write(value);
        }
      });
    }

    final content = decoded['content'];
    if (decoded.containsKey('tool_calls')) {
      return (
        thought: thought,
        content: jsonEncode({'tool_calls': decoded['tool_calls']}),
      );
    }
    if (decoded.containsKey('tool_call')) {
      return (
        thought: thought,
        content: jsonEncode({'tool_call': decoded['tool_call']}),
      );
    }
    if (content is List) {
      for (final item in content) {
        if (item is Map<String, dynamic> && item['type'] == 'text') {
          contentBuffer.write(item['text'] as String? ?? '');
        }
      }
    } else if (channels is! Map<String, dynamic>) {
      // Neither a recognized channels nor content shape: preserve verbatim.
      return (thought: null, content: raw);
    }

    return (
      thought: thought,
      content: contentBuffer.isEmpty ? null : contentBuffer.toString(),
    );
  } on FormatException {
    return (thought: null, content: raw);
  }
}

class _LiteRtLmBindings {
  final DynamicLibrary _library;

  _LiteRtLmBindings(this._library);

  Pointer<NativeFunction<NativeF>>?
  _lookupOptionalNative<NativeF extends Function>(String symbol) {
    try {
      return _library.lookup<NativeFunction<NativeF>>(symbol);
    } on ArgumentError {
      return null;
    }
  }

  late final setMinLogLevel = _library
      .lookupFunction<Void Function(Int), void Function(int)>(
        'litert_lm_set_min_log_level',
      );

  late final engineSettingsCreate = _library
      .lookupFunction<
        Pointer<_LiteRtLmEngineSettings> Function(
          Pointer<Char>,
          Pointer<Char>,
          Pointer<Char>,
          Pointer<Char>,
        ),
        Pointer<_LiteRtLmEngineSettings> Function(
          Pointer<Char>,
          Pointer<Char>,
          Pointer<Char>,
          Pointer<Char>,
        )
      >('litert_lm_engine_settings_create');

  late final engineSettingsDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>),
        void Function(Pointer<_LiteRtLmEngineSettings>)
      >('litert_lm_engine_settings_delete');

  late final engineSettingsSetMaxNumTokens = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>, Int),
        void Function(Pointer<_LiteRtLmEngineSettings>, int)
      >('litert_lm_engine_settings_set_max_num_tokens');

  late final engineSettingsEnableBenchmark = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>),
        void Function(Pointer<_LiteRtLmEngineSettings>)
      >('litert_lm_engine_settings_enable_benchmark');

  late final engineSettingsSetNumPrefillTokens = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>, Int),
        void Function(Pointer<_LiteRtLmEngineSettings>, int)
      >('litert_lm_engine_settings_set_num_prefill_tokens');

  late final engineSettingsSetMaxNumImages = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>, Int),
        void Function(Pointer<_LiteRtLmEngineSettings>, int)
      >('litert_lm_engine_settings_set_max_num_images');

  late final engineSettingsSetEnableSpeculativeDecoding = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>, Bool),
        void Function(Pointer<_LiteRtLmEngineSettings>, bool)
      >('litert_lm_engine_settings_set_enable_speculative_decoding');

  late final engineSettingsSetCacheDir = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>, Pointer<Char>),
        void Function(Pointer<_LiteRtLmEngineSettings>, Pointer<Char>)
      >('litert_lm_engine_settings_set_cache_dir');

  late final engineSettingsSetParallelFileSectionLoading = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>, Bool),
        void Function(Pointer<_LiteRtLmEngineSettings>, bool)
      >('litert_lm_engine_settings_set_parallel_file_section_loading');

  late final engineSettingsSetLiteRtDispatchLibDir = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>, Pointer<Char>),
        void Function(Pointer<_LiteRtLmEngineSettings>, Pointer<Char>)
      >('litert_lm_engine_settings_set_litert_dispatch_lib_dir');

  late final engineSettingsSetActivationDataType = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>, Int),
        void Function(Pointer<_LiteRtLmEngineSettings>, int)
      >('litert_lm_engine_settings_set_activation_data_type');

  late final engineSettingsSetPrefillChunkSize = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngineSettings>, Int),
        void Function(Pointer<_LiteRtLmEngineSettings>, int)
      >('litert_lm_engine_settings_set_prefill_chunk_size');

  late final engineSettingsSetNumThreads =
      _lookupOptionalNative<
            Void Function(Pointer<_LiteRtLmEngineSettings>, Int)
          >('litert_lm_engine_settings_set_num_threads')
          ?.asFunction<void Function(Pointer<_LiteRtLmEngineSettings>, int)>();

  late final engineDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmEngine>),
        void Function(Pointer<_LiteRtLmEngine>)
      >('litert_lm_engine_delete');

  late final engineTokenize = _library
      .lookupFunction<
        Pointer<_LiteRtLmTokenizeResult> Function(
          Pointer<_LiteRtLmEngine>,
          Pointer<Char>,
        ),
        Pointer<_LiteRtLmTokenizeResult> Function(
          Pointer<_LiteRtLmEngine>,
          Pointer<Char>,
        )
      >('litert_lm_engine_tokenize');

  late final tokenizeResultDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmTokenizeResult>),
        void Function(Pointer<_LiteRtLmTokenizeResult>)
      >('litert_lm_tokenize_result_delete');

  late final tokenizeResultGetTokens = _library
      .lookupFunction<
        Pointer<Int> Function(Pointer<_LiteRtLmTokenizeResult>),
        Pointer<Int> Function(Pointer<_LiteRtLmTokenizeResult>)
      >('litert_lm_tokenize_result_get_tokens');

  late final tokenizeResultGetNumTokens = _library
      .lookupFunction<
        Size Function(Pointer<_LiteRtLmTokenizeResult>),
        int Function(Pointer<_LiteRtLmTokenizeResult>)
      >('litert_lm_tokenize_result_get_num_tokens');

  late final engineDetokenize = _library
      .lookupFunction<
        Pointer<_LiteRtLmDetokenizeResult> Function(
          Pointer<_LiteRtLmEngine>,
          Pointer<Int>,
          Size,
        ),
        Pointer<_LiteRtLmDetokenizeResult> Function(
          Pointer<_LiteRtLmEngine>,
          Pointer<Int>,
          int,
        )
      >('litert_lm_engine_detokenize');

  late final detokenizeResultDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmDetokenizeResult>),
        void Function(Pointer<_LiteRtLmDetokenizeResult>)
      >('litert_lm_detokenize_result_delete');

  late final detokenizeResultGetString = _library
      .lookupFunction<
        Pointer<Char> Function(Pointer<_LiteRtLmDetokenizeResult>),
        Pointer<Char> Function(Pointer<_LiteRtLmDetokenizeResult>)
      >('litert_lm_detokenize_result_get_string');

  late final engineGetStartToken = _library
      .lookupFunction<
        Pointer<_LiteRtLmTokenUnion> Function(Pointer<_LiteRtLmEngine>),
        Pointer<_LiteRtLmTokenUnion> Function(Pointer<_LiteRtLmEngine>)
      >('litert_lm_engine_get_start_token');

  late final tokenUnionDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmTokenUnion>),
        void Function(Pointer<_LiteRtLmTokenUnion>)
      >('litert_lm_token_union_delete');

  late final tokenUnionGetType = _library
      .lookupFunction<
        Int Function(Pointer<_LiteRtLmTokenUnion>),
        int Function(Pointer<_LiteRtLmTokenUnion>)
      >('litert_lm_token_union_get_type');

  late final tokenUnionGetString = _library
      .lookupFunction<
        Pointer<Char> Function(Pointer<_LiteRtLmTokenUnion>),
        Pointer<Char> Function(Pointer<_LiteRtLmTokenUnion>)
      >('litert_lm_token_union_get_string');

  late final tokenUnionGetIds = _library
      .lookupFunction<
        Int Function(
          Pointer<_LiteRtLmTokenUnion>,
          Pointer<Pointer<Int>>,
          Pointer<Size>,
        ),
        int Function(
          Pointer<_LiteRtLmTokenUnion>,
          Pointer<Pointer<Int>>,
          Pointer<Size>,
        )
      >('litert_lm_token_union_get_ids');

  late final sessionConfigCreate = _library
      .lookupFunction<
        Pointer<_LiteRtLmSessionConfig> Function(),
        Pointer<_LiteRtLmSessionConfig> Function()
      >('litert_lm_session_config_create');

  late final sessionConfigDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmSessionConfig>),
        void Function(Pointer<_LiteRtLmSessionConfig>)
      >('litert_lm_session_config_delete');

  late final sessionConfigSetSamplerParams = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmSessionConfig>, Pointer<Void>),
        void Function(Pointer<_LiteRtLmSessionConfig>, Pointer<Void>)
      >('litert_lm_session_config_set_sampler_params');

  late final sessionConfigSetLoraPath =
      _lookupOptionalNative<
            Int Function(Pointer<_LiteRtLmSessionConfig>, Pointer<Char>)
          >('litert_lm_session_config_set_lora_path')
          ?.asFunction<
            int Function(Pointer<_LiteRtLmSessionConfig>, Pointer<Char>)
          >();

  late final samplerParamsCreate =
      _lookupOptionalNative<Pointer<_LiteRtLmSamplerParams> Function(Int32)>(
        'litert_lm_sampler_params_create',
      )?.asFunction<Pointer<_LiteRtLmSamplerParams> Function(int)>();

  late final samplerParamsDelete =
      _lookupOptionalNative<Void Function(Pointer<_LiteRtLmSamplerParams>)>(
        'litert_lm_sampler_params_delete',
      )?.asFunction<void Function(Pointer<_LiteRtLmSamplerParams>)>();

  late final samplerParamsSetTopK =
      _lookupOptionalNative<
            Void Function(Pointer<_LiteRtLmSamplerParams>, Int32)
          >('litert_lm_sampler_params_set_top_k')
          ?.asFunction<void Function(Pointer<_LiteRtLmSamplerParams>, int)>();

  late final samplerParamsSetTopP =
      _lookupOptionalNative<
            Void Function(Pointer<_LiteRtLmSamplerParams>, Float)
          >('litert_lm_sampler_params_set_top_p')
          ?.asFunction<
            void Function(Pointer<_LiteRtLmSamplerParams>, double)
          >();

  late final samplerParamsSetTemperature =
      _lookupOptionalNative<
            Void Function(Pointer<_LiteRtLmSamplerParams>, Float)
          >('litert_lm_sampler_params_set_temperature')
          ?.asFunction<
            void Function(Pointer<_LiteRtLmSamplerParams>, double)
          >();

  late final samplerParamsSetSeed =
      _lookupOptionalNative<
            Void Function(Pointer<_LiteRtLmSamplerParams>, Int32)
          >('litert_lm_sampler_params_set_seed')
          ?.asFunction<void Function(Pointer<_LiteRtLmSamplerParams>, int)>();

  late final conversationConfigCreate = _library
      .lookupFunction<
        Pointer<_LiteRtLmConversationConfig> Function(),
        Pointer<_LiteRtLmConversationConfig> Function()
      >('litert_lm_conversation_config_create');

  late final conversationConfigSetSessionConfig = _library
      .lookupFunction<
        Void Function(
          Pointer<_LiteRtLmConversationConfig>,
          Pointer<_LiteRtLmSessionConfig>,
        ),
        void Function(
          Pointer<_LiteRtLmConversationConfig>,
          Pointer<_LiteRtLmSessionConfig>,
        )
      >('litert_lm_conversation_config_set_session_config');

  late final conversationConfigSetSystemMessage = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>),
        void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>)
      >('litert_lm_conversation_config_set_system_message');

  late final conversationConfigSetTools = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>),
        void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>)
      >('litert_lm_conversation_config_set_tools');

  late final conversationConfigSetMessages = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>),
        void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>)
      >('litert_lm_conversation_config_set_messages');

  late final conversationConfigSetExtraContext = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>),
        void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>)
      >('litert_lm_conversation_config_set_extra_context');

  late final conversationConfigSetEnableConstrainedDecoding = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationConfig>, Bool),
        void Function(Pointer<_LiteRtLmConversationConfig>, bool)
      >('litert_lm_conversation_config_set_enable_constrained_decoding');

  late final conversationConfigDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationConfig>),
        void Function(Pointer<_LiteRtLmConversationConfig>)
      >('litert_lm_conversation_config_delete');

  late final conversationCreate = _library
      .lookupFunction<
        Pointer<_LiteRtLmConversation> Function(
          Pointer<_LiteRtLmEngine>,
          Pointer<_LiteRtLmConversationConfig>,
        ),
        Pointer<_LiteRtLmConversation> Function(
          Pointer<_LiteRtLmEngine>,
          Pointer<_LiteRtLmConversationConfig>,
        )
      >('litert_lm_conversation_create');

  late final conversationDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversation>),
        void Function(Pointer<_LiteRtLmConversation>)
      >('litert_lm_conversation_delete');

  late final conversationClone = _library
      .lookupFunction<
        Pointer<_LiteRtLmConversation> Function(Pointer<_LiteRtLmConversation>),
        Pointer<_LiteRtLmConversation> Function(Pointer<_LiteRtLmConversation>)
      >('litert_lm_conversation_clone');

  late final conversationOptionalArgsCreate = _library
      .lookupFunction<
        Pointer<_LiteRtLmConversationOptionalArgs> Function(),
        Pointer<_LiteRtLmConversationOptionalArgs> Function()
      >('litert_lm_conversation_optional_args_create');

  late final conversationOptionalArgsDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationOptionalArgs>),
        void Function(Pointer<_LiteRtLmConversationOptionalArgs>)
      >('litert_lm_conversation_optional_args_delete');

  late final conversationOptionalArgsSetVisualTokenBudget = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationOptionalArgs>, Int),
        void Function(Pointer<_LiteRtLmConversationOptionalArgs>, int)
      >('litert_lm_conversation_optional_args_set_visual_token_budget');

  late final conversationOptionalArgsSetMaxOutputTokens =
      _lookupOptionalNative<
            Void Function(Pointer<_LiteRtLmConversationOptionalArgs>, Int)
          >('litert_lm_conversation_optional_args_set_max_output_tokens')
          ?.asFunction<
            void Function(Pointer<_LiteRtLmConversationOptionalArgs>, int)
          >();

  late final conversationSendMessage = _library
      .lookupFunction<
        Pointer<_LiteRtLmJsonResponse> Function(
          Pointer<_LiteRtLmConversation>,
          Pointer<Char>,
          Pointer<Char>,
          Pointer<_LiteRtLmConversationOptionalArgs>,
        ),
        Pointer<_LiteRtLmJsonResponse> Function(
          Pointer<_LiteRtLmConversation>,
          Pointer<Char>,
          Pointer<Char>,
          Pointer<_LiteRtLmConversationOptionalArgs>,
        )
      >('litert_lm_conversation_send_message');

  late final jsonResponseDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmJsonResponse>),
        void Function(Pointer<_LiteRtLmJsonResponse>)
      >('litert_lm_json_response_delete');

  late final jsonResponseGetString = _library
      .lookupFunction<
        Pointer<Char> Function(Pointer<_LiteRtLmJsonResponse>),
        Pointer<Char> Function(Pointer<_LiteRtLmJsonResponse>)
      >('litert_lm_json_response_get_string');

  late final conversationSendMessageStream = _library
      .lookupFunction<
        Int Function(
          Pointer<_LiteRtLmConversation>,
          Pointer<Char>,
          Pointer<Char>,
          Pointer<_LiteRtLmConversationOptionalArgs>,
          Pointer<NativeFunction<_StreamCallbackNative>>,
          Pointer<Void>,
        ),
        int Function(
          Pointer<_LiteRtLmConversation>,
          Pointer<Char>,
          Pointer<Char>,
          Pointer<_LiteRtLmConversationOptionalArgs>,
          Pointer<NativeFunction<_StreamCallbackNative>>,
          Pointer<Void>,
        )
      >('litert_lm_conversation_send_message_stream');

  late final conversationRenderMessageToString = _library
      .lookupFunction<
        Pointer<Char> Function(Pointer<_LiteRtLmConversation>, Pointer<Char>),
        Pointer<Char> Function(Pointer<_LiteRtLmConversation>, Pointer<Char>)
      >('litert_lm_conversation_render_message_to_string');

  late final conversationCancelProcess = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversation>),
        void Function(Pointer<_LiteRtLmConversation>)
      >('litert_lm_conversation_cancel_process');

  late final conversationGetBenchmarkInfo = _library
      .lookupFunction<
        Pointer<_LiteRtLmBenchmarkInfo> Function(
          Pointer<_LiteRtLmConversation>,
        ),
        Pointer<_LiteRtLmBenchmarkInfo> Function(Pointer<_LiteRtLmConversation>)
      >('litert_lm_conversation_get_benchmark_info');

  late final conversationGetTokenCount = _library
      .lookupFunction<
        Int Function(Pointer<_LiteRtLmConversation>),
        int Function(Pointer<_LiteRtLmConversation>)
      >('litert_lm_conversation_get_token_count');

  late final benchmarkInfoDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmBenchmarkInfo>),
        void Function(Pointer<_LiteRtLmBenchmarkInfo>)
      >('litert_lm_benchmark_info_delete');

  late final benchmarkInfoGetTimeToFirstToken = _library
      .lookupFunction<
        Double Function(Pointer<_LiteRtLmBenchmarkInfo>),
        double Function(Pointer<_LiteRtLmBenchmarkInfo>)
      >('litert_lm_benchmark_info_get_time_to_first_token');

  late final benchmarkInfoGetTotalInitTimeInSecond = _library
      .lookupFunction<
        Double Function(Pointer<_LiteRtLmBenchmarkInfo>),
        double Function(Pointer<_LiteRtLmBenchmarkInfo>)
      >('litert_lm_benchmark_info_get_total_init_time_in_second');

  late final benchmarkInfoGetNumPrefillTurns = _library
      .lookupFunction<
        Int Function(Pointer<_LiteRtLmBenchmarkInfo>),
        int Function(Pointer<_LiteRtLmBenchmarkInfo>)
      >('litert_lm_benchmark_info_get_num_prefill_turns');

  late final benchmarkInfoGetNumDecodeTurns = _library
      .lookupFunction<
        Int Function(Pointer<_LiteRtLmBenchmarkInfo>),
        int Function(Pointer<_LiteRtLmBenchmarkInfo>)
      >('litert_lm_benchmark_info_get_num_decode_turns');

  late final benchmarkInfoGetPrefillTokenCountAt = _library
      .lookupFunction<
        Int Function(Pointer<_LiteRtLmBenchmarkInfo>, Int),
        int Function(Pointer<_LiteRtLmBenchmarkInfo>, int)
      >('litert_lm_benchmark_info_get_prefill_token_count_at');

  late final benchmarkInfoGetDecodeTokenCountAt = _library
      .lookupFunction<
        Int Function(Pointer<_LiteRtLmBenchmarkInfo>, Int),
        int Function(Pointer<_LiteRtLmBenchmarkInfo>, int)
      >('litert_lm_benchmark_info_get_decode_token_count_at');

  late final benchmarkInfoGetPrefillTokensPerSecAt = _library
      .lookupFunction<
        Double Function(Pointer<_LiteRtLmBenchmarkInfo>, Int),
        double Function(Pointer<_LiteRtLmBenchmarkInfo>, int)
      >('litert_lm_benchmark_info_get_prefill_tokens_per_sec_at');

  late final benchmarkInfoGetDecodeTokensPerSecAt = _library
      .lookupFunction<
        Double Function(Pointer<_LiteRtLmBenchmarkInfo>, Int),
        double Function(Pointer<_LiteRtLmBenchmarkInfo>, int)
      >('litert_lm_benchmark_info_get_decode_tokens_per_sec_at');
}

// coverage:ignore-end
