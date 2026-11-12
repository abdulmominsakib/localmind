import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../../core/exceptions.dart';
import '../../core/models/inference/embedding.dart';
import '../../core/models/inference/model_params.dart';
import 'litert_lm_asr_types.dart';
import 'litert_lm_blocking_call.dart';
import 'litert_lm_c_api_version.dart';
import 'litert_lm_embedding.dart';
import 'litert_lm_embedding_bindings.dart' as emb;
import 'litert_lm_finish_reason.dart';
import 'litert_lm_native_settlement.dart';
import 'litert_lm_last_error.dart';
import 'litert_lm_json_schema_bindings.dart';
import 'litert_lm_platform.dart';
import 'litert_lm_sampler_params.dart';
import 'litert_lm_legacy_service_client.dart';
import 'litert_lm_runtime_client_contract.dart';
import 'litert_lm_v1_runtime.dart';

export 'litert_lm_asr_types.dart';
export 'litert_lm_finish_reason.dart';
export 'litert_lm_native_settlement.dart';

part 'litert_lm_embedding_native.dart';
part 'litert_lm_runtime_facade.dart';

const _litertLmReleaseTag = 'v0.19.1-4';
const _litertLmVersion = '0.19.1-4';
const _litertLmLibDirEnv = 'LLAMADART_LITERT_LM_LIB_DIR';
const _liteRtLmIosNativeAsset = 'package:llamadart/litert_lm_LiteRtLm';
const _processLibraryCandidate = '<process>';
const _streamChunkCallbackAbiVersion = 2;
// `LiteRtLmModality` values from LiteRT-LM's `c/capabilities.h`.
const _liteRtLmModalityVision = 1;
const _liteRtLmModalityAudio = 2;

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
      'litert-lm-native $_litertLmReleaseTag; detected $detectedAbi. Install the '
      'pinned runtime before using asynchronous generation.';
}

/// Looks up `stream_proxy_get_finish_reason` in [library] when its
/// `stream_proxy_finish_reason_abi_version` export reports an understood ABI,
/// and returns null when either export is missing or the version is not.
///
/// This is public only for unit tests.
int Function(Pointer<Void> callbackData)? liteRtLmFinishReasonReader(
  DynamicLibrary library,
) {
  int? abiVersion;
  try {
    abiVersion = library
        .lookupFunction<
          _ProxyCallbackAbiVersionNative,
          _ProxyCallbackAbiVersionDart
        >('stream_proxy_finish_reason_abi_version')();
  } on ArgumentError {
    abiVersion = null;
  }
  if (!liteRtLmFinishReasonAbiSupported(abiVersion)) {
    return null;
  }
  try {
    return library
        .lookupFunction<_ProxyGetFinishReasonNative, _ProxyGetFinishReasonDart>(
          'stream_proxy_get_finish_reason',
        );
  } on ArgumentError {
    return null;
  }
}

/// `litert_lm_engine_create` returned no engine for the requested backend,
/// for example a GPU or NPU delegate this device cannot start.
///
/// A [StateError], as before, so callers matching on it keep working.
class LiteRtLmEngineCreateError extends StateError {
  /// Creates the error with the diagnostic [message].
  LiteRtLmEngineCreateError(super.message);
}

/// Throws [LiteRtLmEngineCreateError] when `litert_lm_engine_create` returned
/// no engine, that is when [engineAddress] is 0.
///
/// This is public only for unit tests; production callers should receive the
/// error through [LiteRtLmRuntimeClient.initialize].
void liteRtLmCheckEngineCreated(
  int engineAddress, {
  required String backend,
  required String modelPath,
  String? nativeError,
}) {
  if (engineAddress == 0) {
    throw LiteRtLmEngineCreateError(
      liteRtLmEngineCreateFailureMessage(
        backend: backend,
        modelPath: modelPath,
        nativeError: nativeError,
      ),
    );
  }
}

/// Builds a diagnostic for LiteRT-LM engine creation failures, including
/// [nativeError], the runtime's own description, when it reported one.
///
/// This is public only for unit tests; production callers should receive the
/// message through [LiteRtLmRuntimeClient.initialize].
String liteRtLmEngineCreateFailureMessage({
  required String backend,
  required String modelPath,
  String? nativeError,
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
  final detail = nativeError == null ? '' : ' $nativeError';
  return 'LiteRT-LM engine creation failed for backend "$backend" and model '
      '"$displayName".$detail $hint';
}

String _withNativeError(String message, String? nativeError) =>
    nativeError == null ? message : '$message. $nativeError';

/// The error LiteRT-LM reports on [abi] before it looks for a runtime, or
/// null when litert-lm-native publishes one for [abi].
///
/// macOS x86_64 has none: litert-lm-native publishes arm64-only macOS runtimes
/// ([leehack/litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)),
/// so an x86_64 process, including an Apple-silicon app under Rosetta, gets a
/// [LlamaUnsupportedException] instead of a library lookup failure. Windows
/// arm64 and the x86_64 iOS simulator have no published runtime either, so
/// the build hook bundles none there.
LlamaUnsupportedException? liteRtLmUnsupportedAbiException(Abi abi) {
  return switch (abi) {
    Abi.macosX64 => LlamaUnsupportedException(
      'LiteRT-LM is not available on macOS x86_64; litert-lm-native publishes '
      'arm64-only macOS runtimes (leehack/litert-lm-native#72). Run the app '
      'natively on Apple silicon, not under Rosetta, or use the llama.cpp '
      'backend.',
    ),
    Abi.windowsArm64 => LlamaUnsupportedException(
      'LiteRT-LM is not available on Windows arm64; litert-lm-native '
      'publishes Windows x86_64 runtimes only. Use the llama.cpp backend.',
    ),
    Abi.iosX64 => LlamaUnsupportedException(
      'LiteRT-LM is not available on the x86_64 iOS simulator; '
      'litert-lm-native publishes arm64 iOS runtimes only. Use an arm64 '
      'simulator on Apple silicon, a device, or the llama.cpp backend.',
    ),
    _ => null,
  };
}

/// Test-only ABI that the macOS x86_64 LiteRT-LM gate and the desktop
/// backend defaults check instead of [Abi.current].
Abi? debugLiteRtLmAbiOverride;

/// The ABI the macOS x86_64 LiteRT-LM gate and the desktop backend defaults
/// check.
Abi liteRtLmGateAbi() => debugLiteRtLmAbiOverride ?? Abi.current();

/// Internal helper used by the LiteRT-LM runtime to locate extracted macOS
/// native-assets cache directories.
List<String> liteRtLmMacOsCacheDirectoryCandidatesForAbi(Abi abi) {
  final arch = switch (abi) {
    Abi.macosArm64 => 'arm64',
    _ => null,
  };
  if (arch == null) {
    return const <String>[];
  }
  return <String>['macos_$arch', 'macos/$arch'];
}

/// Internal helper used by the LiteRT-LM runtime to validate extracted macOS
/// native-assets cache directories.
List<String> liteRtLmMacOsRequiredLibrariesForAbi(
  Abi abi, {
  bool cApiV1 = false,
}) => abi == Abi.macosArm64
    ? liteRtLmRequiredLibrariesForAbi(abi, cApiV1: cApiV1)
    : const <String>[];

/// Internal helper used by the LiteRT-LM runtime to locate extracted
/// native-assets cache directories.
List<String> liteRtLmCacheDirectoryCandidatesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => liteRtLmMacOsCacheDirectoryCandidatesForAbi(abi),
    Abi.linuxArm64 => const <String>['linux/arm64', 'linux_arm64'],
    Abi.linuxX64 => const <String>['linux/x64', 'linux_x64'],
    Abi.windowsX64 => const <String>['windows/x64', 'windows_x64'],
    _ => const <String>[],
  };
}

/// Directories, in probe order, where a Linux or Windows build places the
/// LiteRT-LM code assets reported by the build hook, relative to the app
/// executable at [executablePath]: beside it (Flutter Windows), in `lib/`
/// beside it (Flutter Linux) and, only for an executable in `bin/`, in
/// `../lib/` (`dart build cli`), so a Flutter app never looks outside its
/// own folder.
///
/// `DynamicLibrary.open` cannot resolve the `package:` asset ids the hook
/// reports, so a relocated app must find these files by path.
List<String> liteRtLmBundleLibraryDirectoryCandidatesForAbi(
  String executablePath,
  Abi abi,
) {
  if (abi != Abi.linuxX64 && abi != Abi.linuxArm64 && abi != Abi.windowsX64) {
    return const <String>[];
  }
  final executableDir = path.dirname(path.absolute(executablePath));
  return <String>[
    executableDir,
    path.join(executableDir, 'lib'),
    if (path.basename(executableDir).toLowerCase() == 'bin')
      path.normalize(path.join(executableDir, '..', 'lib')),
  ];
}

/// The first [liteRtLmBundleLibraryDirectoryCandidatesForAbi] directory that
/// holds every [liteRtLmRequiredLibrariesForAbi] library, or null.
Directory? liteRtLmFindBundleLibraryDirectoryForAbi(
  String executablePath,
  Abi abi, {
  bool cApiV1 = false,
}) {
  for (final candidate in liteRtLmBundleLibraryDirectoryCandidatesForAbi(
    executablePath,
    abi,
  )) {
    final dir = Directory(candidate);
    if (liteRtLmIsCacheDirectoryForAbi(dir, abi, cApiV1: cApiV1)) {
      return dir;
    }
  }
  return null;
}

/// Resolves the directory holding the complete LiteRT-LM library set for
/// [abi] (see [liteRtLmIsCacheDirectoryForAbi]), in precedence order:
///
/// 1. [libDirOverride] (`LLAMADART_LITERT_LM_LIB_DIR`), which must be complete;
/// 2. the app bundle around [executablePath]
///    ([liteRtLmFindBundleLibraryDirectoryForAbi]);
/// 3. the `.dart_tool/llamadart/litert_lm/<version>` hook cache in any of
///    [searchRoots] or their ancestors.
///
/// An incomplete explicit override throws instead of substituting another runtime.
/// [searchRoots] is only called when the first two steps find nothing.
/// With [cApiV1], this finds a candidate containing the common 0.19 files; the
/// selected primary must still prove C API 1.0 before waiving legacy samplers.
Directory? liteRtLmResolveRuntimeDirectoryForAbi(
  Abi abi, {
  required String? libDirOverride,
  required String executablePath,
  required Iterable<Directory> Function() searchRoots,
  bool cApiV1 = false,
}) {
  final override = libDirOverride?.trim();
  if (override != null && override.isNotEmpty) {
    final dir = Directory(override);
    if (liteRtLmIsCacheDirectoryForAbi(dir, abi, cApiV1: cApiV1)) {
      return dir.absolute;
    }
    throw LlamaUnsupportedException(
      '$_litertLmLibDirEnv must name a complete LiteRT-LM runtime directory '
      'for $abi; the selected directory is missing required libraries. '
      'No bundled or cached runtime was substituted.',
    );
  }

  final bundleDir = liteRtLmFindBundleLibraryDirectoryForAbi(
    executablePath,
    abi,
    cApiV1: cApiV1,
  );
  if (bundleDir != null) {
    return bundleDir;
  }

  final cacheDirectoryCandidates = liteRtLmCacheDirectoryCandidatesForAbi(abi);
  for (final root in searchRoots()) {
    Directory? current = root;
    while (current != null) {
      for (final cacheDirectoryCandidate in cacheDirectoryCandidates) {
        final candidate = Directory(
          '${current.path}/.dart_tool/llamadart/litert_lm/'
          '$_litertLmVersion/$cacheDirectoryCandidate',
        );
        if (liteRtLmIsCacheDirectoryForAbi(candidate, abi, cApiV1: cApiV1)) {
          return candidate;
        }
      }
      current = current.parent.path == current.path ? null : current.parent;
    }
  }
  return null;
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

/// Required desktop runtime files. The default preserves legacy discovery;
/// [cApiV1] describes the owner 0.19 inventory after C API admission, less
/// the prebuilt `libLiteRt` that Linux and Windows hosts from v0.19.1-1 link
/// in instead of loading (litert-lm-native#112).
List<String> liteRtLmRequiredLibrariesForAbi(Abi abi, {bool cApiV1 = false}) {
  return cApiV1
      ? _liteRtLmV1RequiredLibrariesForAbi(abi)
      : _liteRtLmLegacyRequiredLibrariesForAbi(abi);
}

List<String> _liteRtLmLegacyRequiredLibrariesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>[
      'libCLiteRTLM_mac.dylib',
      'libGemmaModelConstraintProvider.dylib',
      'libLiteRt.dylib',
      'libLiteRtLm.dylib',
      'libLiteRtMetalAccelerator.dylib',
      'libLiteRtTopKMetalSampler.dylib',
      'libLiteRtTopKWebGpuSampler.dylib',
      'libLiteRtWebGpuAccelerator.dylib',
      'libwebgpu_dawn.dylib',
    ],
    Abi.linuxArm64 => const <String>[
      'libGemmaModelConstraintProvider.so',
      'libLiteRt.so',
      'libLiteRtLm.so',
      'libLiteRtTopKWebGpuSampler.so',
      'libLiteRtWebGpuAccelerator.so',
      'libwebgpu_dawn.so',
    ],
    Abi.linuxX64 => const <String>[
      'libGemmaModelConstraintProvider.so',
      'libLiteRt.so',
      'libLiteRtLm.so',
      'libLiteRtTopKWebGpuSampler.so',
      'libLiteRtWebGpuAccelerator.so',
      'libwebgpu_dawn.so',
    ],
    Abi.windowsX64 => const <String>[
      'LiteRtLm.dll',
      'dxcompiler.dll',
      'dxil.dll',
      'libGemmaModelConstraintProvider.dll',
      'libLiteRt.dll',
      'libLiteRtTopKWebGpuSampler.dll',
      'libLiteRtWebGpuAccelerator.dll',
      'libwebgpu_dawn.dll',
      'msvcp140.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'vcruntime140_threads.dll',
      'webgpu_dawn.dll',
    ],
    _ => const <String>[],
  };
}

List<String> _liteRtLmV1RequiredLibrariesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>[
      'libCLiteRTLM_mac.dylib',
      'libGemmaModelConstraintProvider.dylib',
      'libLiteRtLm.dylib',
      'libwebgpu_dawn.dylib',
    ],
    Abi.linuxArm64 => const <String>[
      'libGemmaModelConstraintProvider.so',
      'libLiteRtLm.so',
      'libLiteRtWebGpuAccelerator.so',
      'libwebgpu_dawn.so',
    ],
    Abi.linuxX64 => const <String>[
      'libGemmaModelConstraintProvider.so',
      'libLiteRtLm.so',
      'libLiteRtWebGpuAccelerator.so',
      'libwebgpu_dawn.so',
    ],
    Abi.windowsX64 => const <String>[
      'LiteRtLm.dll',
      'dxcompiler.dll',
      'dxil.dll',
      'libGemmaModelConstraintProvider.dll',
      'libLiteRtWebGpuAccelerator.dll',
      'libwebgpu_dawn.dll',
      'msvcp140.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'vcruntime140_threads.dll',
      'webgpu_dawn.dll',
    ],
    _ => const <String>[],
  };
}

/// Members of [liteRtLmRequiredLibrariesForAbi] that must be present but that
/// the runtime never opens itself: Dawn's D3D12 backend loads the DXC pair at
/// GPU engine creation.
Set<String> liteRtLmNonPreloadedLibrariesForAbi(Abi abi) {
  return switch (abi) {
    Abi.windowsX64 => const <String>{'dxcompiler.dll', 'dxil.dll'},
    _ => const <String>{},
  };
}

/// File name of the primary LiteRT-LM library in an extracted cache directory,
/// or null for ABIs without a hook-managed desktop bundle.
String? liteRtLmPrimaryLibraryForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => 'libLiteRtLm.dylib',
    Abi.linuxArm64 => 'libLiteRtLm.so',
    Abi.linuxX64 => 'libLiteRtLm.so',
    Abi.windowsX64 => 'LiteRtLm.dll',
    _ => null,
  };
}

/// Companions that other LiteRT-LM libraries import, in load order. Windows
/// binds an import to an already loaded module of the same name before it
/// searches the executable's directory, System32, the working directory and
/// `PATH`, so opening these first keeps every import inside the runtime
/// directory, including the `bin\` and `lib\` split of `dart build cli`.
List<String> _liteRtLmCompanionDependenciesForAbi(Abi abi) {
  return switch (abi) {
    Abi.windowsX64 => const <String>[
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'vcruntime140_threads.dll',
      'msvcp140.dll',
      'webgpu_dawn.dll',
    ],
    _ => const <String>[],
  };
}

/// [liteRtLmRequiredLibrariesForAbi] minus the primary library and
/// [liteRtLmNonPreloadedLibrariesForAbi]: imported dependencies first, then
/// the rest in inventory order. The runtime opens these before the primary
/// library when it loads a Linux or Windows runtime directory.
List<String> liteRtLmCompanionLibrariesForAbi(Abi abi, {bool cApiV1 = false}) {
  final primary = liteRtLmPrimaryLibraryForAbi(abi);
  if (primary == null) {
    return const <String>[];
  }
  final nonPreloaded = liteRtLmNonPreloadedLibrariesForAbi(abi);
  final companions = liteRtLmRequiredLibrariesForAbi(abi, cApiV1: cApiV1)
      .where((library) => library != primary && !nonPreloaded.contains(library))
      .toList();
  final dependencies = _liteRtLmCompanionDependenciesForAbi(
    abi,
  ).where(companions.contains).toList();
  return <String>[
    ...dependencies,
    ...companions.where((library) => !dependencies.contains(library)),
  ];
}

/// The prebuilt LiteRT that Linux and Windows hosts before v0.19.1-1 import
/// (v0.18.x, v0.19.0 and v0.19.1). Hosts from v0.19.1-1 link LiteRT in, so
/// neither inventory requires it.
List<String> liteRtLmOptionalCompanionLibrariesForAbi(Abi abi) {
  return switch (abi) {
    Abi.linuxArm64 || Abi.linuxX64 => const <String>['libLiteRt.so'],
    Abi.windowsX64 => const <String>['libLiteRt.dll'],
    _ => const <String>[],
  };
}

/// Companion paths the runtime opens from an explicit
/// `LLAMADART_LITERT_LM_LIB_DIR` [directory] before its primary library:
/// [liteRtLmCompanionLibrariesForAbi], then each
/// [liteRtLmOptionalCompanionLibrariesForAbi] library the directory holds.
///
/// Windows does not search a DLL's own directory for its imports, so an older
/// custom host loads only if its `libLiteRt.dll` is already open.
List<String> liteRtLmExplicitDirectoryCompanionPathsForAbi(
  Abi abi,
  Directory directory, {
  bool cApiV1 = false,
}) {
  final companions = liteRtLmCompanionLibrariesForAbi(abi, cApiV1: cApiV1);
  return <String>[
    for (final library in companions) '${directory.path}/$library',
    for (final library in liteRtLmOptionalCompanionLibrariesForAbi(abi))
      if (!companions.contains(library) &&
          File('${directory.path}/$library').existsSync())
        '${directory.path}/$library',
  ];
}

/// Internal helper used by the LiteRT-LM runtime to locate this package's
/// source root from an app's `.dart_tool/package_config.json`.
///
/// A caller that has already read the file passes its [contents]; relative
/// roots still resolve against [packageConfig].
List<String> liteRtLmPackageRootsFromPackageConfig(
  File packageConfig, {
  String packageName = 'llamadart',
  String? contents,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(contents ?? packageConfig.readAsStringSync());
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
List<String> liteRtLmMacOsRequiredFrameworksForAbi(
  Abi abi, {
  bool cApiV1 = false,
}) {
  return cApiV1
      ? _liteRtLmV1MacOsRequiredFrameworksForAbi(abi)
      : _liteRtLmMacOsRequiredFrameworksForAbi(abi);
}

List<String> _liteRtLmMacOsRequiredFrameworksForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>[
      'CLiteRTLM_mac.framework/Versions/A/CLiteRTLM_mac',
      'GemmaModelConstraintProvider.framework/Versions/A/GemmaModelConstraintProvider',
      'LiteRt.framework/Versions/A/LiteRt',
      'LiteRtLm.framework/Versions/A/LiteRtLm',
      'LiteRtMetalAccelerator.framework/Versions/A/LiteRtMetalAccelerator',
      'LiteRtTopKMetalSampler.framework/Versions/A/LiteRtTopKMetalSampler',
      'LiteRtTopKWebGpuSampler.framework/Versions/A/LiteRtTopKWebGpuSampler',
      'LiteRtWebGpuAccelerator.framework/Versions/A/LiteRtWebGpuAccelerator',
      'webgpu_dawn.framework/Versions/A/webgpu_dawn',
    ],
    _ => const <String>[],
  };
}

List<String> _liteRtLmV1MacOsRequiredFrameworksForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>[
      'CLiteRTLM_mac.framework/Versions/A/CLiteRTLM_mac',
      'GemmaModelConstraintProvider.framework/Versions/A/GemmaModelConstraintProvider',
      'LiteRtLm.framework/Versions/A/LiteRtLm',
      'webgpu_dawn.framework/Versions/A/webgpu_dawn',
    ],
    _ => const <String>[],
  };
}

/// Internal helper used by the LiteRT-LM runtime to validate the native-repo
/// Apple SPM layout in macOS app bundles.
List<String> liteRtLmMacOsRequiredNativeSpmFilesForAbi(
  Abi abi, {
  bool cApiV1 = false,
}) {
  return cApiV1
      ? _liteRtLmV1MacOsRequiredNativeSpmFilesForAbi(abi)
      : _liteRtLmMacOsRequiredNativeSpmFilesForAbi(abi);
}

List<String> _liteRtLmMacOsRequiredNativeSpmFilesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>[
      'LiteRtLm.framework/Versions/A/LiteRtLm',
      'libCLiteRTLM_mac.dylib',
      'LiteRtLm.framework/Versions/A/Dependencies/libGemmaModelConstraintProvider.dylib',
      'libLiteRt.dylib',
      'libLiteRtTopKWebGpuSampler.dylib',
      'libLiteRtWebGpuAccelerator.dylib',
      'libwebgpu_dawn.dylib',
    ],
    _ => const <String>[],
  };
}

List<String> _liteRtLmV1MacOsRequiredNativeSpmFilesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>[
      'LiteRtLm.framework/Versions/A/LiteRtLm',
      'libCLiteRTLM_mac.dylib',
      'LiteRtLm.framework/Versions/A/Dependencies/libGemmaModelConstraintProvider.dylib',
      'libwebgpu_dawn.dylib',
    ],
    _ => const <String>[],
  };
}

/// Internal helper used by the LiteRT-LM runtime to validate extracted macOS
/// native-assets cache directories.
bool liteRtLmIsMacOsCacheDirectoryForAbi(
  Directory dir,
  Abi abi, {
  bool cApiV1 = false,
}) {
  final requiredLibraries = liteRtLmMacOsRequiredLibrariesForAbi(
    abi,
    cApiV1: cApiV1,
  );
  return requiredLibraries.isNotEmpty &&
      requiredLibraries.every(
        (library) => File('${dir.path}/$library').existsSync(),
      );
}

/// Internal helper used by the LiteRT-LM runtime to validate extracted
/// native-assets cache directories.
bool liteRtLmIsCacheDirectoryForAbi(
  Directory dir,
  Abi abi, {
  bool cApiV1 = false,
}) {
  final requiredLibraries = liteRtLmRequiredLibrariesForAbi(
    abi,
    cApiV1: cApiV1,
  );
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

typedef _ProxyGetFinishReasonNative =
    Int32 Function(Pointer<Void> callbackData);
typedef _ProxyGetFinishReasonDart = int Function(Pointer<Void> callbackData);

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

final class _LiteRtLmLoadedFile extends Opaque {}

final class _LiteRtLmRepetitionPenaltyConfig extends Opaque {}

final class _LiteRtLmThinkingConfig extends Opaque {}

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

/// Per-send decode controls: penalties over the tokens this send generates
/// and a thinking token budget.
typedef _GenerationControls = ({
  ({double repetition, double presence})? penalties,
  int? thinkingTokenBudget,
});

// coverage:ignore-start
// Native FFI boundary: exercised by LiteRT-LM smoke tests with real libraries.
final class _BlockingSendMessageRequest {
  const _BlockingSendMessageRequest({
    required this.libraryPath,
    required this.companionLibraryPaths,
    required this.conversationAddress,
    required this.messageJson,
    required this.diagnosticPaths,
    this.extraContextJson,
    this.visualTokenBudget,
    this.maxOutputTokens,
    this.generationControls,
    this.jsonSchema,
  });

  final String libraryPath;
  final List<String> companionLibraryPaths;
  final int conversationAddress;
  final String messageJson;
  final List<String> diagnosticPaths;
  final String? extraContextJson;
  final int? visualTokenBudget;
  final int? maxOutputTokens;
  final _GenerationControls? generationControls;
  final String? jsonSchema;
}

/// Low-level native LiteRT-LM runtime client.
///
/// Most callers should use [LiteRtLmBackend] through the high-level
/// `LlamaEngine` API. This client is exported for benchmark tools and advanced
/// native integrations that need direct access to LiteRT-LM bundles.
class _LegacyLiteRtLmRuntimeClient extends LiteRtLmRuntimeClient {
  /// Creates a low-level LiteRT-LM runtime client.
  ///
  /// [libraryPath] is an advanced local-validation override. Packaged apps
  /// should omit it and use the platform runtime selected by native assets.
  _LegacyLiteRtLmRuntimeClient({
    String? libraryPath,
    bool allowV1Inventory = false,
  }) : _libraryPathOverride = libraryPath,
       _allowV1Inventory = allowV1Inventory,
       super._legacy();

  final bool _allowV1Inventory;
  ({Directory directory, List<String> legacy, List<String> v1})?
  _discoveryInventory;

  void _selectDirectoryInventory(
    Directory directory,
    List<String> Function(bool) files,
  ) {
    _discoveryInventory = (
      directory: directory,
      legacy: files(false),
      v1: files(true),
    );
  }

  String _thinkingStartTag = LiteRtLmChannelAssembler.gemma4ThinkingStartTag;
  String _thinkingEndTag = LiteRtLmChannelAssembler.gemma4ThinkingEndTag;

  /// Configures how LiteRT-LM thought-channel chunks are exposed to parsers.
  @override
  void configureResponseThinkingTags({
    required String startTag,
    required String endTag,
  }) {
    _thinkingStartTag = startTag;
    _thinkingEndTag = endTag;
  }

  /// Whether the active native runtime exports the dedicated ASR bridge.
  ///
  /// Runtime load failures are reported as unsupported rather than thrown so
  /// callers can use this as a capability probe.
  @override
  bool get supportsAsrBridge {
    try {
      _ensureLibrariesLoaded();
      final library = _bindings!._library;
      _LiteRtLmAsrBindings(library).validateCompatibility();
      return true;
    } on Object {
      return false;
    }
  }

  /// Whether the active native runtime exports the per-send repetition
  /// penalty API that [generateMessageJson] uses for `repetitionPenalty` and
  /// `presencePenalty`.
  ///
  /// Runtime load failures are reported as unsupported rather than thrown so
  /// callers can use this as a capability probe.
  @override
  bool get supportsSamplingPenalties {
    try {
      _ensureLibrariesLoaded();
      return _bindings!.penaltyApi != null;
    } on Object {
      return false;
    }
  }

  /// Whether the active native runtime exports the per-send thinking config
  /// API that [generateMessageJson] uses for `thinkingTokenBudget`.
  ///
  /// Runtime load failures are reported as unsupported rather than thrown so
  /// callers can use this as a capability probe.
  @override
  bool get supportsThinkingBudget {
    try {
      _ensureLibrariesLoaded();
      return _bindings!.thinkingApi != null;
    } on Object {
      return false;
    }
  }

  /// Whether the active native runtime reports why each streamed turn ended:
  /// its `stream_proxy_finish_reason_abi_version` export returns 1
  /// (litert-lm-native `v0.18.0-3` and later) and it streams through the
  /// embedded StreamProxy.
  ///
  /// Runtime load failures are reported as unsupported rather than thrown so
  /// callers can use this as a capability probe.
  @override
  bool get supportsFinishReasons {
    try {
      _ensureLibrariesLoaded();
      return _proxyCreate != null && _proxyGetFinishReason != null;
    } on Object {
      return false;
    }
  }

  /// Why the latest [generateMessageJson] or [generate] stream ended.
  ///
  /// Set before that stream closes. Null while a stream is running, before
  /// the first one, and on runtimes without [supportsFinishReasons].
  @override
  LiteRtLmFinishReason? get lastFinishReason => _lastFinishReason;

  /// What the `.litertlm` bundle at [modelPath] declares in its section
  /// metadata, read without creating an engine: whether it takes image and
  /// audio input, and whether it has a speculative decoding drafter.
  ///
  /// Returns null when the runtime lacks LiteRT-LM's loaded-file capability
  /// API or cannot read the bundle.
  @override
  ({bool vision, bool audio, bool speculativeDecoding})? bundleCapabilities(
    String modelPath,
  ) {
    _ensureLibrariesLoaded();
    final bindings = _bindings!;
    final create = bindings.loadedFileCreate;
    final delete = bindings.loadedFileDelete;
    final supportsInputModality = bindings.loadedFileSupportsInputModality;
    final hasSpeculativeDecoding =
        bindings.loadedFileHasSpeculativeDecodingSupport;
    if (create == null ||
        delete == null ||
        supportsInputModality == null ||
        hasSpeculativeDecoding == null) {
      return null;
    }
    final modelPathPtr = modelPath.toNativeUtf8(allocator: calloc);
    try {
      final loadedFile = create(modelPathPtr.cast());
      if (loadedFile == nullptr) {
        return null;
      }
      try {
        return (
          vision: supportsInputModality(loadedFile, _liteRtLmModalityVision),
          audio: supportsInputModality(loadedFile, _liteRtLmModalityAudio),
          speculativeDecoding: hasSpeculativeDecoding(loadedFile),
        );
      } finally {
        delete(loadedFile);
      }
    } finally {
      calloc.free(modelPathPtr);
    }
  }

  /// Whether the loaded runtime exports the complete optional schema API.
  @override
  bool get supportsJsonSchemaConstraints {
    _ensureLibrariesLoaded();
    return _bindings!.jsonSchemaApi != null;
  }

  /// The pre-1.0 C API schema group always disables thinking.
  @override
  bool get supportsJsonSchemaThinking => false;

  /// Creates a synchronous dedicated-ASR runtime session.
  ///
  /// The current bridge accepts mono 16 kHz float PCM. Inference calls block;
  /// high-level clients should own this session from a worker isolate.
  @override
  LiteRtLmAsrRuntimeSession createAsrSession(LiteRtLmAsrRuntimeConfig config) {
    _validateLiteRtLmAsrRuntimeConfig(config);
    _ensureLibrariesLoaded();
    return _NativeLiteRtLmAsrRuntimeSession.create(_bindings!._library, config);
  }

  _LiteRtLmBindings? _bindings;
  final String? _libraryPathOverride;
  // Keep a strong runtime-library reference while proxy function pointers are active.
  // ignore: unused_field
  DynamicLibrary? _proxyLibrary;
  // Keep macOS/Linux/Windows companion libraries loaded while the runtime is active.
  // ignore: unused_field
  List<DynamicLibrary> _companionLibraries = const <DynamicLibrary>[];
  _ProxyCreateDart? _proxyCreate;
  _ProxyFreeStringDart? _proxyFreeString;
  _ProxyDeleteDart? _proxyDelete;
  _ProxyGetFinishReasonDart? _proxyGetFinishReason;
  LiteRtLmFinishReason? _lastFinishReason;
  String? _liteRtLmLibraryPath;
  List<String> _liteRtLmCompanionLibraryPaths = const <String>[];
  // Paths a native error message may contain, cut to base names there.
  List<String> _diagnosticPaths = const <String>[];
  LiteRtLmNativeSettlement _nativeSettlement = LiteRtLmNativeSettlement.settled;

  /// Native lifetime; a Dart stream error alone does not establish settlement.
  @override
  LiteRtLmNativeSettlement get nativeSettlement => _nativeSettlement;

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
  @override
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
    final resolved = _validateLiteRtLmInitializeArguments(
      backend: backend,
      visionBackend: visionBackend,
      audioBackend: audioBackend,
      maxTokens: maxTokens,
      outputTokens: outputTokens,
      prefillTokens: prefillTokens,
      maxNumImages: maxNumImages,
      prefillChunkSize: prefillChunkSize,
      dispatchLibDir: dispatchLibDir,
      numberOfThreads: numberOfThreads,
    );
    final resolvedBackend = resolved.backend;
    final resolvedVisionBackend = resolved.visionBackend;
    final resolvedAudioBackend = resolved.audioBackend;
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
    final diagnosticPaths = <String>[modelPath, ?cacheDir, ?dispatchLibDir];
    _diagnosticPaths = diagnosticPaths;
    Pointer<_LiteRtLmEngineSettings> settings = nullptr;

    try {
      final lastError = bindings.lastError;
      lastError?.clear();
      settings = bindings.engineSettingsCreate(
        modelPathPtr.cast(),
        backendPtr.cast(),
        visionBackendPtr?.cast() ?? nullptr,
        audioBackendPtr?.cast() ?? nullptr,
      );
      if (settings == nullptr) {
        throw StateError(
          _withNativeError(
            'litert_lm_engine_settings_create returned null',
            lastError?.describe(paths: diagnosticPaths),
          ),
        );
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
      final created = await Isolate.run(() {
        final companionLibraries = liteRtLmOpenCompanionLibraries(
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
          // The error state is per thread, so it is read in this isolate
          // right after the call.
          final lastError = LiteRtLmLastError.probeLibrary(lib);
          lastError?.clear();
          final address = create(
            Pointer<_LiteRtLmEngineSettings>.fromAddress(settingsAddress),
          ).address;
          return (
            address: address,
            nativeError: address == 0
                ? lastError?.describe(paths: diagnosticPaths)
                : null,
          );
        } finally {
          _keepAlive(companionLibraries);
        }
      });
      liteRtLmCheckEngineCreated(
        created.address,
        backend: resolvedBackend,
        modelPath: modelPath,
        nativeError: created.nativeError,
      );
      _engine = Pointer<_LiteRtLmEngine>.fromAddress(created.address);
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
  ///
  /// [systemMessage] is plain text, including any literal JSON text. The native
  /// API wraps this content in its own system-role message.
  ///
  /// [promptTemplate] overrides the bundle's native Jinja template. Omit it to
  /// preserve model-specific formatting, especially for media. An explicit
  /// override requires the native conversation-template setter; incompatible
  /// runtime overrides fail with [LlamaUnsupportedException].
  ///
  /// With [temperature] `0`, [topK] is forced to `1`. [npuBackend] sets no
  /// sampler parameters.
  @override
  void createConversation({
    String? systemMessage,
    String? promptTemplate,
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? extraContext,
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    int seed = 1,
    bool npuBackend = false,
    String? loraPath,
    bool jsonSchemaConstraints = false,
  }) {
    final bindings = _requireBindings();
    final engine = _requireEngine();
    if (jsonSchemaConstraints && bindings.jsonSchemaApi == null) {
      throw LlamaUnsupportedException(
        'Native JSON Schema chat requires the complete LiteRT-LM constraint-provider and thinking API. '
        'Use the default LiteRtLmRuntimeClient or LiteRtLmService with the packaged '
        'litert-lm-native $_litertLmReleaseTag runtime; legacy overrides must provide this complete API '
        'and meet the JSON Schema qualification limits.',
      );
    }
    _deleteConversation();

    if (promptTemplate != null &&
        !bindings._library.providesSymbol(
          'litert_lm_conversation_config_set_prompt_template',
        )) {
      throw LlamaUnsupportedException(
        'This LiteRT-LM runtime lacks '
        'litert_lm_conversation_config_set_prompt_template, so llamadart '
        'cannot set a conversation template: raw prompt generation, '
        'ModelParams.chatTemplate and the built-in family templates, such as '
        'Qwen3 text chat, need one. Use the packaged litert-lm-native '
        '$_litertLmReleaseTag runtime or a newer one.',
      );
    }
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

    final templatePtr = promptTemplate?.toNativeUtf8(allocator: calloc);
    final systemPtr = systemMessage == null
        ? nullptr
        : jsonEncode(systemMessage).toNativeUtf8(allocator: calloc);
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
      if (templatePtr != null) {
        bindings.conversationConfigSetPromptTemplate(
          config,
          templatePtr.cast(),
        );
      }
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
      if (jsonSchemaConstraints) {
        bindings.jsonSchemaApi!.configure(config.cast());
      }
      final lastError = bindings.lastError;
      lastError?.clear();
      final conversation = bindings.conversationCreate(engine, config);
      if (conversation == nullptr) {
        throw StateError(
          _withNativeError(
            'litert_lm_conversation_create returned null',
            lastError?.describe(paths: [..._diagnosticPaths, ?loraPath]),
          ),
        );
      }
      _conversation = conversation;
    } finally {
      if (config != nullptr) {
        bindings.conversationConfigDelete(config);
      }
      bindings.sessionConfigDelete(sessionConfig);
      if (templatePtr != null) calloc.free(templatePtr);
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
  @override
  void setMinLogLevel(int level) {
    _ensureLibrariesLoaded();
    _bindings!.setMinLogLevel(level);
  }

  /// Tokenizes text with the native LiteRT-LM tokenizer.
  @override
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
  @override
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

  /// Whether a runtime is loaded and provides the entry point of
  /// [renderMessageToString].
  @override
  bool get supportsMessageRendering =>
      _bindings?._library.providesSymbol(
        'litert_lm_conversation_render_message_to_string',
      ) ??
      false;

  /// Renders a message with the active native LiteRT-LM conversation template.
  ///
  /// The returned string is copied into Dart before the native conversation may
  /// invalidate the underlying buffer.
  @override
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

  /// Streams generated text from the active conversation.
  ///
  /// [repetitionPenalty] and [presencePenalty] apply as in
  /// [generateMessageJson].
  @override
  Stream<String> generate(
    String prompt, {
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
  }) {
    return generateMessageJson(
      _messageJson(prompt),
      maxOutputTokens: maxOutputTokens,
      repetitionPenalty: repetitionPenalty,
      presencePenalty: presencePenalty,
    );
  }

  /// Streams generated text by sending a native LiteRT-LM message JSON object.
  ///
  /// [visualTokenBudget] configures the native image-token budget for
  /// multimodal messages.
  ///
  /// [repetitionPenalty] (at least 1.0) and [presencePenalty] penalize tokens
  /// that this send has already generated; prompt and history tokens are not
  /// counted. [thinkingTokenBudget] (at least 1) caps the tokens generated
  /// inside the thinking channel of the bundle before the runtime forces the
  /// channel closed, and enables thinking for this send. Both throw
  /// [LlamaUnsupportedException] when the runtime does not export their API;
  /// see [supportsSamplingPenalties] and [supportsThinkingBudget].
  @override
  Stream<String> generateMessageJson(
    String messageJson, {
    Map<String, dynamic>? extraContext,
    int? visualTokenBudget,
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
    int? thinkingTokenBudget,
    String? jsonSchema,
  }) {
    final resolvedMaxOutputTokens = maxOutputTokens ?? _defaultMaxOutputTokens;
    _validateLiteRtLmSendArguments(
      visualTokenBudget: visualTokenBudget,
      maxOutputTokens: resolvedMaxOutputTokens,
      repetitionPenalty: repetitionPenalty,
      presencePenalty: presencePenalty,
      thinkingTokenBudget: thinkingTokenBudget,
    );
    final _GenerationControls? generationControls =
        repetitionPenalty == null &&
            presencePenalty == null &&
            thinkingTokenBudget == null
        ? null
        : (
            penalties: repetitionPenalty == null && presencePenalty == null
                ? null
                : (
                    repetition: repetitionPenalty ?? 1.0,
                    presence: presencePenalty ?? 0.0,
                  ),
            thinkingTokenBudget: thinkingTokenBudget,
          );
    if (generationControls != null) {
      _checkGenerationControls(_requireBindings(), generationControls);
    }
    // Upstream stream callback strings are only valid during the native call.
    // Dart listener callbacks run later, so streaming requires StreamProxy to
    // copy those strings across the thread/isolate boundary.
    final extraContextJson = extraContext == null || extraContext.isEmpty
        ? null
        : jsonEncode(extraContext);
    _lastFinishReason = null;
    if (_proxyCreate == null) {
      return _generateBlockingMessageJson(
        messageJson,
        extraContextJson: extraContextJson,
        visualTokenBudget: visualTokenBudget,
        maxOutputTokens: resolvedMaxOutputTokens,
        generationControls: generationControls,
        jsonSchema: jsonSchema,
      );
    }
    return _generateStreamingMessageJson(
      messageJson,
      extraContextJson: extraContextJson,
      visualTokenBudget: visualTokenBudget,
      maxOutputTokens: resolvedMaxOutputTokens,
      generationControls: generationControls,
      jsonSchema: jsonSchema,
    );
  }

  Stream<String> _generateBlockingMessageJson(
    String messageJson, {
    String? extraContextJson,
    int? visualTokenBudget,
    int? maxOutputTokens,
    _GenerationControls? generationControls,
    String? jsonSchema,
  }) {
    final conversation = _requireConversation();
    final liteRtLmLibraryPath = _liteRtLmLibraryPath!;
    final controller = StreamController<String>(onCancel: cancel);
    final request = _BlockingSendMessageRequest(
      libraryPath: liteRtLmLibraryPath,
      companionLibraryPaths: _liteRtLmCompanionLibraryPaths,
      conversationAddress: conversation.address,
      messageJson: messageJson,
      diagnosticPaths: _diagnosticPaths,
      extraContextJson: extraContextJson,
      visualTokenBudget: visualTokenBudget,
      maxOutputTokens: maxOutputTokens,
      generationControls: generationControls,
      jsonSchema: jsonSchema,
    );

    _nativeSettlement = LiteRtLmNativeSettlement.pending;
    unawaited(() async {
      try {
        final result = await _runBlockingSendMessageInIsolate(request);
        // The child explicitly returned after its synchronous native call and
        // cleanup unwound. A failed isolate transport supplies no such proof.
        _nativeSettlement = LiteRtLmNativeSettlement.settled;
        final failure = result.error;
        if (failure != null) {
          Error.throwWithStackTrace(failure, result.stackTrace!);
        }
        final raw = result.value!;
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
        if (_nativeSettlement == LiteRtLmNativeSettlement.pending) {
          _nativeSettlement = LiteRtLmNativeSettlement.quarantined;
        }
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
    _GenerationControls? generationControls,
    String? jsonSchema,
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
      _nativeSettlement = LiteRtLmNativeSettlement.settled;
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

    Object? streamFailure;
    var nativeCancelled = false;
    callable = NativeCallable<_StreamCallbackNative>.listener((
      Pointer<Void> data,
      Pointer<Char> chunk,
      bool isFinal,
      Pointer<Char> errorMessage,
    ) {
      try {
        if (errorMessage != nullptr) {
          final error = errorMessage.cast<Utf8>().toDartString();
          if (error.startsWith('CANCELLED')) {
            nativeCancelled = true;
          } else {
            streamFailure ??= StateError(error);
          }
        }
        if (chunk != nullptr && streamFailure == null && !nativeCancelled) {
          final raw = chunk.cast<Utf8>().toDartString();
          final text = assembler.add(raw);
          if (text.isNotEmpty && !controller.isClosed) controller.add(text);
        }
      } catch (_) {
        streamFailure ??= StateError(
          'LiteRT-LM stream returned invalid callback data.',
        );
      } finally {
        if (chunk != nullptr) _proxyFreeString?.call(chunk);
        if (errorMessage != nullptr) _proxyFreeString?.call(errorMessage);
      }
      // An error is data, not proof that the native callback owner is idle.
      // Keep the listener/proxy alive until the actual terminal callback.
      if (!isFinal) return;
      final readFinishReason = _proxyGetFinishReason;
      if (readFinishReason != null && callbackData != nullptr) {
        _lastFinishReason = LiteRtLmFinishReason.fromWire(
          readFinishReason(callbackData),
        );
      }
      if (!controller.isClosed) {
        final failure = streamFailure;
        if (failure != null) {
          controller.addError(failure);
        } else if (!nativeCancelled) {
          final tail = assembler.flush();
          if (tail.isNotEmpty) controller.add(tail);
        }
        unawaited(controller.close());
      }
      cleanup();
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
        generationControls: generationControls,
        jsonSchema: jsonSchema,
      );

      final lastError = bindings.lastError;
      lastError?.clear();
      _nativeSettlement = LiteRtLmNativeSettlement.pending;
      final rc = bindings.conversationSendMessageStream(
        conversation,
        messagePtr.cast(),
        extraContextPtr.cast(),
        optionalArgs,
        callbackFn.cast(),
        callbackData,
      );
      if (rc != 0) {
        throw StateError(
          _withNativeError(
            'litert_lm_conversation_send_message_stream rc=$rc',
            lastError?.describe(paths: _diagnosticPaths),
          ),
        );
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
  @override
  Future<LiteRtLmRuntimeResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,
  }) async {
    _validateLiteRtLmBenchmarkArguments(warmupRuns, measuredRuns);

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
  @override
  LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds}) {
    return _readMetrics(wallMilliseconds);
  }

  /// Cancels active native generation.
  @override
  void cancel() {
    final conversation = _conversation;
    final bindings = _bindings;
    if (conversation != null && conversation != nullptr && bindings != null) {
      bindings.conversationCancelProcess(conversation);
    }
  }

  /// Releases native LiteRT-LM resources.
  @override
  void dispose() {
    if (nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'LiteRT-LM native callbacks have not settled; retain resources and restart the process.',
      );
    }
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
    final liteRtLm = _discoverLibraries();
    final bindings = _LiteRtLmBindings(liteRtLm.library);
    _tryLoadEmbeddedStreamProxy(liteRtLm.library, liteRtLm.path, true);
    _bindings = bindings;
  }

  ({String path, DynamicLibrary library})? _discoveredLibrary;
  ({String path, DynamicLibrary library}) _discoverLibraries() {
    try {
      return _discoverLibrariesImpl();
    } on ArgumentError catch (error) {
      final explicitLibrary = _libraryPathOverride?.trim().isNotEmpty ?? false;
      final explicitDirectory =
          Platform.environment[_litertLmLibDirEnv]?.trim().isNotEmpty ?? false;
      if (!explicitLibrary && !explicitDirectory) rethrow;
      throw LlamaUnsupportedException(
        'The explicitly selected LiteRT-LM runtime could not be loaded for '
        '${Abi.current()}. Install a complete matching runtime. '
        'No bundled, cached or process runtime was substituted. $error',
      );
    }
  }

  ({String path, DynamicLibrary library}) _discoverLibrariesImpl() {
    final existing = _discoveredLibrary;
    if (existing != null) return existing;
    final libraryPathOverride = _libraryPathOverride?.trim();
    if (libraryPathOverride == null || libraryPathOverride.isEmpty) {
      final unsupported = liteRtLmUnsupportedAbiException(liteRtLmGateAbi());
      if (unsupported != null) {
        throw unsupported;
      }
    }
    final libraries = _librariesForCurrentPlatform();
    if (libraries == null) {
      throw UnsupportedError('LiteRT-LM does not support ${Abi.current()}.');
    }

    final companionLibraries = liteRtLmOpenCompanionLibraries(
      libraries.companions,
    );

    final liteRtLm = _openFirstAvailableWithPath(
      libraries.liteRtLmCandidates,
      description: 'LiteRT-LM library',
    );
    final inventory = _discoveryInventory;
    if (_allowV1Inventory && inventory != null) {
      // Only the selected image's version probe can waive legacy sampler files.
      final v1 = readLiteRtLmCApiVersion(liteRtLm.library) != null;
      final required = v1 ? inventory.v1 : inventory.legacy;
      final missing = required
          .where(
            (file) =>
                !File(path.join(inventory.directory.path, file)).existsSync(),
          )
          .toList();
      if (missing.isNotEmpty) {
        throw LlamaUnsupportedException(
          'The selected LiteRT-LM ${v1 ? "C API 1.0" : "legacy C API"} '
          'runtime for ${Abi.current()} is incomplete: missing '
          '${missing.join(", ")}. Install a complete matching runtime; '
          'no other runtime was substituted.',
        );
      }
      if (!v1) {
        companionLibraries.addAll(
          liteRtLmOpenCompanionLibraries(
            inventory.legacy
                .where((file) => !inventory.v1.contains(file))
                .map((file) => path.join(inventory.directory.path, file)),
          ),
        );
      }
    }
    _liteRtLmLibraryPath = liteRtLm.path;
    _liteRtLmCompanionLibraryPaths = [
      ...libraries.companions,
      if (_allowV1Inventory &&
          inventory != null &&
          !liteRtLm.library.providesSymbol('litert_lm_get_api_version'))
        ...inventory.legacy
            .where((file) => !inventory.v1.contains(file))
            .map((file) => path.join(inventory.directory.path, file)),
    ];
    _companionLibraries = companionLibraries;
    return _discoveredLibrary = liteRtLm;
  }

  ({
    List<String> liteRtLmCandidates,
    List<String> companions,
    bool directCallbackSupported,
  })?
  _librariesForCurrentPlatform() {
    final libraryPathOverride = _libraryPathOverride?.trim();
    if (libraryPathOverride != null && libraryPathOverride.isNotEmpty) {
      return (
        liteRtLmCandidates: <String>[libraryPathOverride],
        companions: const <String>[],
        directCallbackSupported: true,
      );
    }
    final abi = Abi.current();
    final directoryOverride = Platform.environment[_litertLmLibDirEnv]?.trim();
    if (directoryOverride != null &&
        directoryOverride.isNotEmpty &&
        liteRtLmPrimaryLibraryForAbi(abi) != null) {
      final directory = _findLiteRtLmCacheDirForAbi(abi)!;
      return (
        liteRtLmCandidates: [
          path.join(directory.path, liteRtLmPrimaryLibraryForAbi(abi)!),
        ],
        companions: liteRtLmExplicitDirectoryCompanionPathsForAbi(
          abi,
          directory,
          cApiV1: _allowV1Inventory,
        ),
        directCallbackSupported: true,
      );
    }
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
    if (Platform.isMacOS && abi == Abi.macosArm64) {
      final companions = _macOsCompanionLibrariesForAbi(abi);
      final frameworksDir = _findMacOsAppFrameworksDir();
      if (frameworksDir != null) {
        final usesNativeSpmFramework = File(
          '${frameworksDir.path}/LiteRtLm.framework/Versions/A/LiteRtLm',
        ).existsSync();
        return (
          liteRtLmCandidates: liteRtLmMacOsLibraryCandidates(
            '${frameworksDir.path}/LiteRtLm.framework/Versions/A/LiteRtLm',
            explicitOverride: _allowV1Inventory,
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
            explicitOverride: _allowV1Inventory,
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
            explicitOverride: explicitOverride || _allowV1Inventory,
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
        if (!library.providesSymbol('litert_lm_get_api_version')) {
          _validateLiteRtLmLibrary(library);
        }
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
      _proxyGetFinishReason = liteRtLmFinishReasonReader(liteRtLmLibrary);
      _proxyLibrary = liteRtLmLibrary;
    } catch (error) {
      _proxyCreate = null;
      _proxyFreeString = null;
      _proxyDelete = null;
      _proxyGetFinishReason = null;
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
      cApiV1: _allowV1Inventory,
    );
    if (requiredNativeSpmFiles.isNotEmpty &&
        requiredNativeSpmFiles.every(
          (file) => File('${frameworksDir.path}/$file').existsSync(),
        )) {
      _selectDirectoryInventory(
        frameworksDir,
        (v1) => liteRtLmMacOsRequiredNativeSpmFilesForAbi(
          Abi.current(),
          cApiV1: v1,
        ),
      );
      return frameworksDir;
    }
    final requiredFrameworks = liteRtLmMacOsRequiredFrameworksForAbi(
      Abi.current(),
      cApiV1: _allowV1Inventory,
    );
    if (requiredFrameworks.isEmpty) {
      return null;
    }
    final requiredFiles = [
      for (final framework in requiredFrameworks)
        '${frameworksDir.path}/$framework',
    ];
    if (requiredFiles.every((file) => File(file).existsSync())) {
      _selectDirectoryInventory(
        frameworksDir,
        (v1) =>
            liteRtLmMacOsRequiredFrameworksForAbi(Abi.current(), cApiV1: v1),
      );
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
    if (!liteRtLmIsMacOsCacheDirectoryForAbi(
      libraryDir,
      Abi.current(),
      cApiV1: _allowV1Inventory,
    )) {
      return null;
    }
    _selectDirectoryInventory(
      libraryDir,
      (v1) => liteRtLmRequiredLibrariesForAbi(Abi.current(), cApiV1: v1),
    );
    return libraryDir;
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
    final directory = liteRtLmResolveRuntimeDirectoryForAbi(
      abi,
      libDirOverride: Platform.environment[_litertLmLibDirEnv],
      executablePath: Platform.resolvedExecutable,
      searchRoots: _candidateSearchRoots,
      cApiV1: _allowV1Inventory,
    );
    if (directory != null) {
      _selectDirectoryInventory(
        directory,
        (v1) => liteRtLmRequiredLibrariesForAbi(abi, cApiV1: v1),
      );
    }
    return directory;
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
    return liteRtLmMacOsRequiredLibrariesForAbi(abi, cApiV1: _allowV1Inventory)
        .where((library) => library != 'libLiteRtLm.dylib')
        .toList(growable: false);
  }

  List<String> _companionLibrariesForAbi(Abi abi, Directory dir) {
    return liteRtLmCompanionLibrariesForAbi(
      abi,
      cApiV1: _allowV1Inventory,
    ).map((library) => '${dir.path}/$library').toList(growable: false);
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

({String backend, String? visionBackend, String? audioBackend})
_validateLiteRtLmInitializeArguments({
  required String backend,
  String? visionBackend,
  String? audioBackend,
  required int maxTokens,
  required int outputTokens,
  int? prefillTokens,
  int? maxNumImages,
  int? prefillChunkSize,
  String? dispatchLibDir,
  int? numberOfThreads,
}) {
  if (maxTokens <= 0) {
    throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
  }
  if (outputTokens <= 0) {
    throw ArgumentError.value(outputTokens, 'outputTokens', 'must be positive');
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
      : _normalizeLiteRtLmRuntimeBackend(visionBackend, name: 'visionBackend');
  final resolvedAudioBackend = audioBackend == null
      ? null
      : _normalizeLiteRtLmRuntimeBackend(audioBackend, name: 'audioBackend');
  return (
    backend: resolvedBackend,
    visionBackend: resolvedVisionBackend,
    audioBackend: resolvedAudioBackend,
  );
}

void _validateLiteRtLmSendArguments({
  int? visualTokenBudget,
  int? maxOutputTokens,
  double? repetitionPenalty,
  double? presencePenalty,
  int? thinkingTokenBudget,
}) {
  if (repetitionPenalty != null &&
      !(repetitionPenalty.isFinite && repetitionPenalty >= 1.0)) {
    throw ArgumentError.value(
      repetitionPenalty,
      'repetitionPenalty',
      'must be finite and at least 1.0',
    );
  }
  if (presencePenalty != null && !presencePenalty.isFinite) {
    throw ArgumentError.value(
      presencePenalty,
      'presencePenalty',
      'must be finite',
    );
  }
  if (thinkingTokenBudget != null && thinkingTokenBudget <= 0) {
    throw ArgumentError.value(
      thinkingTokenBudget,
      'thinkingTokenBudget',
      'must be positive when provided',
    );
  }
  if (visualTokenBudget != null && visualTokenBudget <= 0) {
    throw ArgumentError.value(
      visualTokenBudget,
      'visualTokenBudget',
      'must be positive when provided',
    );
  }
  if (maxOutputTokens != null && maxOutputTokens <= 0) {
    throw ArgumentError.value(
      maxOutputTokens,
      'maxOutputTokens',
      'must be positive when provided',
    );
  }
}

void _validateLiteRtLmBenchmarkArguments(int warmupRuns, int measuredRuns) {
  if (warmupRuns < 0) {
    throw ArgumentError.value(warmupRuns, 'warmupRuns', 'must be >= 0');
  }
  if (measuredRuns <= 0) {
    throw ArgumentError.value(measuredRuns, 'measuredRuns', 'must be > 0');
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

void _setConversationOptionalArgs(
  _LiteRtLmBindings bindings,
  Pointer<_LiteRtLmConversationOptionalArgs> optionalArgs, {
  int? visualTokenBudget,
  int? maxOutputTokens,
  _GenerationControls? generationControls,
  String? jsonSchema,
}) {
  if (jsonSchema != null) {
    final api = bindings.jsonSchemaApi;
    if (api == null) {
      throw LlamaUnsupportedException(
        'Native JSON Schema chat requires the complete LiteRT-LM constraint API.',
      );
    }
    api.constrain(optionalArgs.cast(), jsonSchema);
  }
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
  final penalties = generationControls?.penalties;
  if (penalties != null) {
    final api = bindings.penaltyApi;
    if (api == null) {
      throw LlamaUnsupportedException(_liteRtLmPenaltiesUnavailable);
    }
    final config = api.create();
    if (config == nullptr) {
      throw StateError(
        'litert_lm_repetition_penalty_config_create returned null',
      );
    }
    try {
      api.setRepetitionPenalty(config, penalties.repetition);
      api.setPresencePenalty(config, penalties.presence);
      // The runtime deep-copies the config, so it can be freed right away.
      api.setOnOptionalArgs(optionalArgs, config);
    } finally {
      api.delete(config);
    }
  }
  final thinkingTokenBudget = generationControls?.thinkingTokenBudget;
  if (thinkingTokenBudget != null) {
    final api = bindings.thinkingApi;
    if (api == null) {
      throw LlamaUnsupportedException(_liteRtLmThinkingBudgetUnavailable);
    }
    final config = api.create();
    if (config == nullptr) {
      throw StateError('litert_lm_thinking_config_create returned null');
    }
    try {
      api.setEnableThinking(config, true);
      api.setTokenBudget(config, thinkingTokenBudget);
      api.setOnOptionalArgs(optionalArgs, config);
    } finally {
      api.delete(config);
    }
  }
}

void _checkGenerationControls(
  _LiteRtLmBindings bindings,
  _GenerationControls controls,
) {
  if (controls.penalties != null && bindings.penaltyApi == null) {
    throw LlamaUnsupportedException(_liteRtLmPenaltiesUnavailable);
  }
  if (controls.thinkingTokenBudget != null && bindings.thinkingApi == null) {
    throw LlamaUnsupportedException(_liteRtLmThinkingBudgetUnavailable);
  }
}

const _liteRtLmPenaltiesUnavailable =
    'LiteRT-LM repetition and presence penalties need a native runtime that '
    'exports the repetition penalty API (litert-lm-native v0.18.0 or newer); '
    'the loaded runtime lacks one of: '
    'litert_lm_repetition_penalty_config_create, '
    'litert_lm_repetition_penalty_config_delete, '
    'litert_lm_repetition_penalty_config_set_repetition_penalty, '
    'litert_lm_repetition_penalty_config_set_presence_penalty, '
    'litert_lm_conversation_optional_args_set_repetition_penalty_config.';

const _liteRtLmThinkingBudgetUnavailable =
    'LiteRT-LM thinking budgets need a native runtime that exports the '
    'thinking config API (litert-lm-native v0.18.0 or newer); the loaded '
    'runtime lacks one of: litert_lm_thinking_config_create, '
    'litert_lm_thinking_config_delete, '
    'litert_lm_thinking_config_set_enable_thinking, '
    'litert_lm_thinking_config_set_thinking_token_budget, '
    'litert_lm_conversation_optional_args_set_thinking_config.';

void _setSessionSamplerParams(
  _LiteRtLmBindings bindings,
  Pointer<_LiteRtLmSessionConfig> sessionConfig, {
  required int topK,
  required double topP,
  required double temperature,
  required int seed,
}) {
  // The LiteRT WebGPU sampler emits incoherent text at temperature 0 with
  // top-k > 1 (#544).
  topK = liteRtLmEffectiveTopK(temperature: temperature, topK: topK);
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

Future<LiteRtLmBlockingCallResult<String>> _runBlockingSendMessageInIsolate(
  _BlockingSendMessageRequest request,
) => runLiteRtLmBlockingCall(() => _runBlockingSendMessage(request));

String _runBlockingSendMessage(_BlockingSendMessageRequest request) {
  final companionLibraries = liteRtLmOpenCompanionLibraries(
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
        generationControls: request.generationControls,
        jsonSchema: request.jsonSchema,
      );

      final lastError = bindings.lastError;
      lastError?.clear();
      final response = bindings.conversationSendMessage(
        conversation,
        messagePtr.cast(),
        extraContextPtr.cast(),
        optionalArgs,
      );
      if (response == nullptr) {
        throw StateError(
          _withNativeError(
            'litert_lm_conversation_send_message returned null',
            lastError?.describe(paths: request.diagnosticPaths),
          ),
        );
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

/// Opens companion libraries, retrying dependencies after other libraries load.
///
/// Runtime inventories are not dependency ordered. Retry failed loads only when
/// the previous pass loaded another library; otherwise preserve the loader's
/// original error and stack. Missing absolute paths retain discovery's existing
/// behavior and are skipped. [openLibrary] allows isolated loader tests.
List<DynamicLibrary> liteRtLmOpenCompanionLibraries(
  Iterable<String> companions, {
  DynamicLibrary Function(String)? openLibrary,
}) {
  final open = openLibrary ?? DynamicLibrary.open;
  var pending = companions
      .where(
        (companion) =>
            File(companion).existsSync() || !path.isAbsolute(companion),
      )
      .toList();
  final libraries = <DynamicLibrary>[];
  while (pending.isNotEmpty) {
    final deferred = <String>[];
    ArgumentError? firstError;
    StackTrace? firstStack;
    for (final companion in pending) {
      try {
        libraries.add(open(companion));
      } on ArgumentError catch (error, stack) {
        deferred.add(companion);
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (deferred.length == pending.length) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
    pending = deferred;
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

/// Probes the independent ASR ABI on an explicitly selected loaded library.
/// This does not bind or admit the library's text-generation C API.
bool supportsLiteRtLmAsrLibrary(DynamicLibrary library) {
  try {
    _LiteRtLmAsrBindings(library).validateCompatibility();
    return true;
  } on Object {
    return false;
  }
}

/// Creates an owned ASR session after validating the independent bridge ABI.
/// The returned session retains its library independently of text engines.
LiteRtLmAsrRuntimeSession createLiteRtLmAsrSessionFromLibrary(
  DynamicLibrary library,
  LiteRtLmAsrRuntimeConfig config,
) {
  _validateLiteRtLmAsrRuntimeConfig(config);
  return _NativeLiteRtLmAsrRuntimeSession.create(library, config);
}

const int _liteRtLmAsrAbiVersion = 1;
const int _liteRtLmAsrStatusOk = 0;
const int _liteRtLmAsrStatusNeedsMoreAudio = 10;
const int _liteRtLmAsrStatusEndOfStream = 11;
const int _liteRtLmAsrStatusWouldBlock = 12;

final class _LiteRtLmAsrEngine extends Opaque {}

final class _LiteRtLmAsrSession extends Opaque {}

final class _LiteRtLmAsrConfig extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int abiVersion;

  external Pointer<Char> modelName;
  external Pointer<Char> modelPath;
  external Pointer<Char> tokenizerPath;

  @Int32()
  external int sampleRateHz;

  @Int32()
  external int numChannels;

  @Int32()
  external int inputMilliseconds;

  @Int32()
  external int maxBufferedAudioMilliseconds;

  @Int32()
  external int decoderType;

  @Int32()
  external int backend;

  @Int32()
  external int textMergerType;

  @Int32()
  external int numThreads;

  @Float()
  external double overlapRatio;

  @Int32()
  external int hasLogMelConfig;

  @Int32()
  external int logMelNFft;

  @Int32()
  external int logMelNMels;

  @Int32()
  external int logMelHopLength;

  @Int32()
  external int logMelNFrames;

  @Int32()
  external int logMelTranspose;

  @Float()
  external double logMelPreemphasis;

  @Int32()
  external int logMelNormType;

  @Int32()
  external int decodeStartTokenId;

  @Int32()
  external int decodeStopTokenId;

  @Int32()
  external int decodeSkipUntilTokenId;

  @Int32()
  external int decodeStatefullyAfter;

  @Int32()
  external int vocabSize;

  @Int32()
  external int blankTokenId;
}

final class _LiteRtLmAsrResult extends Struct {
  @Uint32()
  external int structSize;

  external Pointer<Char> confirmedText;
  external Pointer<Char> unconfirmedText;

  @Int32()
  external int isFinal;
}

void _validateLiteRtLmAsrRuntimeConfig(LiteRtLmAsrRuntimeConfig runtimeConfig) {
  const maxInt32 = 0x7fffffff;
  for (final (name, source) in [
    ('model', runtimeConfig.model),
    ('tokenizer', runtimeConfig.tokenizer),
  ]) {
    if (source != null && source.isRemote) {
      throw LlamaUnsupportedException(
        'The LiteRT-LM ASR runtime opens local files only, but the $name is '
        'the remote source ${source.displayName}. Use '
        'SpeechToTextEngine.load with a LiteRtLmAsrAdapter, which downloads '
        'it first.',
      );
    }
  }
  if (runtimeConfig.modelPath.trim().isEmpty) {
    throw ArgumentError.value(
      runtimeConfig.modelPath,
      'modelPath',
      'must not be empty',
    );
  }
  if (runtimeConfig.tokenizerPath.trim().isEmpty) {
    throw ArgumentError.value(
      runtimeConfig.tokenizerPath,
      'tokenizerPath',
      'must not be empty',
    );
  }
  if (runtimeConfig.numberOfThreads <= 0 ||
      runtimeConfig.numberOfThreads > maxInt32) {
    throw ArgumentError.value(
      runtimeConfig.numberOfThreads,
      'numberOfThreads',
      'must be in the range [1, $maxInt32]',
    );
  }
  final maxBufferedMilliseconds = runtimeConfig.maxBufferedAudio.inMilliseconds;
  final minimumBufferedAudio = _asrInputWindow(runtimeConfig.modelPreset);
  if (runtimeConfig.maxBufferedAudio < minimumBufferedAudio ||
      maxBufferedMilliseconds > maxInt32) {
    throw ArgumentError.value(
      runtimeConfig.maxBufferedAudio,
      'maxBufferedAudio',
      'must be between $minimumBufferedAudio and '
          'Duration(milliseconds: $maxInt32)',
    );
  }
  if (!runtimeConfig.overlapRatio.isFinite ||
      runtimeConfig.overlapRatio < 0 ||
      runtimeConfig.overlapRatio >= 1) {
    throw ArgumentError.value(
      runtimeConfig.overlapRatio,
      'overlapRatio',
      'must be finite and in the range [0, 1)',
    );
  }
}

Duration _asrInputWindow(LiteRtLmAsrModelPreset preset) => switch (preset) {
  LiteRtLmAsrModelPreset.whisperTiny => const Duration(seconds: 30),
  LiteRtLmAsrModelPreset.parakeetTdt0_6bV3 ||
  LiteRtLmAsrModelPreset.parakeetCtc0_6b ||
  LiteRtLmAsrModelPreset.moonshineTiny ||
  LiteRtLmAsrModelPreset.qwen3Asr0_6b => const Duration(seconds: 5),
};

class _NativeLiteRtLmAsrRuntimeSession implements LiteRtLmAsrRuntimeSession {
  _NativeLiteRtLmAsrRuntimeSession._(this._bindings, this._session);

  final _LiteRtLmAsrBindings _bindings;
  Pointer<_LiteRtLmAsrSession>? _session;

  static _NativeLiteRtLmAsrRuntimeSession create(
    DynamicLibrary library,
    LiteRtLmAsrRuntimeConfig runtimeConfig,
  ) {
    final bindings = _LiteRtLmAsrBindings(library);
    try {
      bindings.validateCompatibility();
    } on ArgumentError catch (error) {
      throw LlamaUnsupportedException(
        'The loaded LiteRT-LM runtime does not expose compatible dedicated '
        'ASR bridge ABI $_liteRtLmAsrAbiVersion. Install a speech-capable '
        'litert-lm-native v0.16+ artifact. Details: $error',
      );
    }
    final config = calloc<_LiteRtLmAsrConfig>();
    final engineOut = calloc<Pointer<_LiteRtLmAsrEngine>>();
    final sessionOut = calloc<Pointer<_LiteRtLmAsrSession>>();
    final errorOut = calloc<Pointer<Char>>();
    final modelPath = runtimeConfig.modelPath.toNativeUtf8(allocator: calloc);
    final tokenizerPath = runtimeConfig.tokenizerPath.toNativeUtf8(
      allocator: calloc,
    );
    Pointer<_LiteRtLmAsrEngine> engine = nullptr;
    Pointer<_LiteRtLmAsrSession> session = nullptr;
    try {
      final presetStatus = bindings.configInitForModelPreset(
        config,
        _nativeAsrPreset(runtimeConfig.modelPreset),
      );
      _throwOnAsrStatus(
        bindings,
        presetStatus,
        errorOut,
        operation: 'ASR model preset initialization',
      );
      config.ref.modelPath = modelPath.cast();
      config.ref.tokenizerPath = tokenizerPath.cast();
      config.ref.backend = runtimeConfig.backend.index;
      config.ref.numThreads = runtimeConfig.numberOfThreads;
      config.ref.maxBufferedAudioMilliseconds =
          runtimeConfig.maxBufferedAudio.inMilliseconds;
      config.ref.overlapRatio = runtimeConfig.overlapRatio;

      final engineStatus = bindings.engineCreate(config, engineOut, errorOut);
      engine = engineOut.value;
      _throwOnAsrStatus(
        bindings,
        engineStatus,
        errorOut,
        operation: 'LiteRT-LM ASR engine creation',
      );
      if (engine == nullptr) {
        throw LlamaSpeechException(
          'LiteRT-LM ASR engine creation returned no owner on success.',
        );
      }
      final sessionStatus = bindings.sessionCreate(
        engine,
        sessionOut,
        errorOut,
      );
      _throwOnAsrStatus(
        bindings,
        sessionStatus,
        errorOut,
        operation: 'LiteRT-LM ASR session creation',
      );
      if (sessionOut.value == nullptr) {
        throw LlamaSpeechException(
          'LiteRT-LM ASR session creation returned no owner on success.',
        );
      }
      session = sessionOut.value;
      return _NativeLiteRtLmAsrRuntimeSession._(bindings, session);
    } on ArgumentError catch (error) {
      throw LlamaUnsupportedException(
        'The loaded LiteRT-LM runtime does not expose compatible dedicated '
        'ASR bridge ABI $_liteRtLmAsrAbiVersion. Install a speech-capable '
        'litert-lm-native v0.16+ artifact. Details: $error',
      );
    } finally {
      if (engine != nullptr) {
        bindings.engineDelete(engine);
      }
      if (session == nullptr && sessionOut.value != nullptr) {
        bindings.sessionDelete(sessionOut.value);
      }
      if (errorOut.value != nullptr) {
        bindings.freeString(errorOut.value);
      }
      calloc.free(modelPath);
      calloc.free(tokenizerPath);
      calloc.free(errorOut);
      calloc.free(sessionOut);
      calloc.free(engineOut);
      calloc.free(config);
    }
  }

  Pointer<_LiteRtLmAsrSession> get _activeSession {
    final session = _session;
    if (session == null || session == nullptr) {
      throw StateError('LiteRT-LM ASR session has been disposed.');
    }
    return session;
  }

  @override
  LiteRtLmAsrPushResult pushAudio(Float32List samples) {
    if (samples.isEmpty) {
      return const LiteRtLmAsrPushResult(acceptedSamples: 0, wouldBlock: false);
    }
    final nativeSamples = calloc<Float>(samples.length);
    final acceptedOut = calloc<Size>();
    final errorOut = calloc<Pointer<Char>>();
    try {
      nativeSamples.asTypedList(samples.length).setAll(0, samples);
      final status = _bindings.sessionPushAudio(
        _activeSession,
        nativeSamples,
        samples.length,
        acceptedOut,
        errorOut,
      );
      if (status != _liteRtLmAsrStatusOk &&
          status != _liteRtLmAsrStatusWouldBlock) {
        _throwOnAsrStatus(
          _bindings,
          status,
          errorOut,
          operation: 'LiteRT-LM ASR audio push',
        );
      }
      final accepted = acceptedOut.value;
      if (accepted < 0 || accepted > samples.length) {
        throw LlamaSpeechException(
          'LiteRT-LM ASR returned an invalid accepted-sample count.',
          accepted,
        );
      }
      return LiteRtLmAsrPushResult(
        acceptedSamples: accepted,
        wouldBlock: status == _liteRtLmAsrStatusWouldBlock,
      );
    } finally {
      _releaseAsrError(_bindings, errorOut);
      calloc.free(errorOut);
      calloc.free(acceptedOut);
      calloc.free(nativeSamples);
    }
  }

  @override
  void finishAudio() {
    final errorOut = calloc<Pointer<Char>>();
    try {
      final status = _bindings.sessionFinishAudio(_activeSession, errorOut);
      _throwOnAsrStatus(
        _bindings,
        status,
        errorOut,
        operation: 'LiteRT-LM ASR input finalization',
      );
    } finally {
      _releaseAsrError(_bindings, errorOut);
      calloc.free(errorOut);
    }
  }

  @override
  LiteRtLmAsrProcessResult processNext() {
    final result = calloc<_LiteRtLmAsrResult>();
    final errorOut = calloc<Pointer<Char>>();
    _bindings.resultInit(result);
    try {
      final status = _bindings.sessionProcessNext(
        _activeSession,
        result,
        errorOut,
      );
      if (status == _liteRtLmAsrStatusNeedsMoreAudio) {
        return const LiteRtLmAsrProcessResult(
          state: LiteRtLmAsrProcessState.needsMoreAudio,
        );
      }
      if (status == _liteRtLmAsrStatusEndOfStream) {
        return const LiteRtLmAsrProcessResult(
          state: LiteRtLmAsrProcessState.endOfStream,
        );
      }
      _throwOnAsrStatus(
        _bindings,
        status,
        errorOut,
        operation: 'LiteRT-LM ASR inference',
      );
      return LiteRtLmAsrProcessResult(
        state: LiteRtLmAsrProcessState.update,
        confirmedText: _readAsrString(result.ref.confirmedText),
        unconfirmedText: _readAsrString(result.ref.unconfirmedText),
        isFinal: result.ref.isFinal != 0,
      );
    } finally {
      _bindings.resultRelease(result);
      _releaseAsrError(_bindings, errorOut);
      calloc.free(errorOut);
      calloc.free(result);
    }
  }

  @override
  void cancel() {
    final status = _bindings.sessionCancel(_activeSession);
    if (status != _liteRtLmAsrStatusOk) {
      throw LlamaSpeechException('LiteRT-LM ASR cancellation failed.', status);
    }
  }

  @override
  void reset() {
    final errorOut = calloc<Pointer<Char>>();
    try {
      final status = _bindings.sessionReset(_activeSession, errorOut);
      _throwOnAsrStatus(
        _bindings,
        status,
        errorOut,
        operation: 'LiteRT-LM ASR session reset',
      );
    } finally {
      _releaseAsrError(_bindings, errorOut);
      calloc.free(errorOut);
    }
  }

  @override
  void dispose() {
    final session = _session;
    if (session == null || session == nullptr) {
      return;
    }
    _bindings.sessionDelete(session);
    _session = null;
  }
}

int _nativeAsrPreset(LiteRtLmAsrModelPreset preset) => switch (preset) {
  LiteRtLmAsrModelPreset.parakeetTdt0_6bV3 => 1,
  LiteRtLmAsrModelPreset.parakeetCtc0_6b => 2,
  LiteRtLmAsrModelPreset.moonshineTiny => 3,
  LiteRtLmAsrModelPreset.whisperTiny => 4,
  LiteRtLmAsrModelPreset.qwen3Asr0_6b => 5,
};

String _readAsrString(Pointer<Char> value) =>
    value == nullptr ? '' : value.cast<Utf8>().toDartString();

String? _releaseAsrError(
  _LiteRtLmAsrBindings bindings,
  Pointer<Pointer<Char>> errorOut,
) {
  final value = errorOut.value;
  if (value == nullptr) {
    return null;
  }
  final message = _readAsrString(value);
  bindings.freeString(value);
  errorOut.value = nullptr;
  return message;
}

Never _throwAsrStatus({
  required int status,
  required String operation,
  String? details,
}) {
  throw LlamaSpeechException(
    '$operation failed with native status $status.',
    details,
  );
}

void _throwOnAsrStatus(
  _LiteRtLmAsrBindings bindings,
  int status,
  Pointer<Pointer<Char>> errorOut, {
  required String operation,
}) {
  if (status == _liteRtLmAsrStatusOk) {
    return;
  }
  _throwAsrStatus(
    status: status,
    operation: operation,
    details: _releaseAsrError(bindings, errorOut),
  );
}

class _LiteRtLmAsrBindings {
  _LiteRtLmAsrBindings(this._library);

  final DynamicLibrary _library;

  late final abiVersion = _library
      .lookupFunction<Uint32 Function(), int Function()>(
        'litert_lm_asr_abi_version',
      );

  late final configSize = _library
      .lookupFunction<Size Function(), int Function()>(
        'litert_lm_asr_config_size',
      );

  late final resultSize = _library
      .lookupFunction<Size Function(), int Function()>(
        'litert_lm_asr_result_size',
      );

  late final configInitForModelPreset = _library
      .lookupFunction<
        Int32 Function(Pointer<_LiteRtLmAsrConfig>, Int32),
        int Function(Pointer<_LiteRtLmAsrConfig>, int)
      >('litert_lm_asr_config_init_for_model_preset');

  late final resultInit = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmAsrResult>),
        void Function(Pointer<_LiteRtLmAsrResult>)
      >('litert_lm_asr_result_init');

  late final resultRelease = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmAsrResult>),
        void Function(Pointer<_LiteRtLmAsrResult>)
      >('litert_lm_asr_result_release');

  late final freeString = _library
      .lookupFunction<
        Void Function(Pointer<Char>),
        void Function(Pointer<Char>)
      >('litert_lm_asr_free_string');

  late final engineCreate = _library
      .lookupFunction<
        Int32 Function(
          Pointer<_LiteRtLmAsrConfig>,
          Pointer<Pointer<_LiteRtLmAsrEngine>>,
          Pointer<Pointer<Char>>,
        ),
        int Function(
          Pointer<_LiteRtLmAsrConfig>,
          Pointer<Pointer<_LiteRtLmAsrEngine>>,
          Pointer<Pointer<Char>>,
        )
      >('litert_lm_asr_engine_create');

  late final engineDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmAsrEngine>),
        void Function(Pointer<_LiteRtLmAsrEngine>)
      >('litert_lm_asr_engine_delete');

  late final sessionCreate = _library
      .lookupFunction<
        Int32 Function(
          Pointer<_LiteRtLmAsrEngine>,
          Pointer<Pointer<_LiteRtLmAsrSession>>,
          Pointer<Pointer<Char>>,
        ),
        int Function(
          Pointer<_LiteRtLmAsrEngine>,
          Pointer<Pointer<_LiteRtLmAsrSession>>,
          Pointer<Pointer<Char>>,
        )
      >('litert_lm_asr_session_create');

  late final sessionDelete = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmAsrSession>),
        void Function(Pointer<_LiteRtLmAsrSession>)
      >('litert_lm_asr_session_delete');

  late final sessionPushAudio = _library
      .lookupFunction<
        Int32 Function(
          Pointer<_LiteRtLmAsrSession>,
          Pointer<Float>,
          Size,
          Pointer<Size>,
          Pointer<Pointer<Char>>,
        ),
        int Function(
          Pointer<_LiteRtLmAsrSession>,
          Pointer<Float>,
          int,
          Pointer<Size>,
          Pointer<Pointer<Char>>,
        )
      >('litert_lm_asr_session_push_audio_f32');

  late final sessionFinishAudio = _library
      .lookupFunction<
        Int32 Function(Pointer<_LiteRtLmAsrSession>, Pointer<Pointer<Char>>),
        int Function(Pointer<_LiteRtLmAsrSession>, Pointer<Pointer<Char>>)
      >('litert_lm_asr_session_finish_audio');

  late final sessionProcessNext = _library
      .lookupFunction<
        Int32 Function(
          Pointer<_LiteRtLmAsrSession>,
          Pointer<_LiteRtLmAsrResult>,
          Pointer<Pointer<Char>>,
        ),
        int Function(
          Pointer<_LiteRtLmAsrSession>,
          Pointer<_LiteRtLmAsrResult>,
          Pointer<Pointer<Char>>,
        )
      >('litert_lm_asr_session_process_next');

  late final sessionReset = _library
      .lookupFunction<
        Int32 Function(Pointer<_LiteRtLmAsrSession>, Pointer<Pointer<Char>>),
        int Function(Pointer<_LiteRtLmAsrSession>, Pointer<Pointer<Char>>)
      >('litert_lm_asr_session_reset');

  late final sessionCancel = _library
      .lookupFunction<
        Int32 Function(Pointer<_LiteRtLmAsrSession>),
        int Function(Pointer<_LiteRtLmAsrSession>)
      >('litert_lm_asr_session_cancel');

  void validateCompatibility() {
    final actualAbiVersion = abiVersion();
    if (actualAbiVersion != _liteRtLmAsrAbiVersion) {
      throw ArgumentError(
        'ASR bridge ABI is $actualAbiVersion; expected '
        '$_liteRtLmAsrAbiVersion.',
      );
    }
    final actualConfigSize = configSize();
    final dartConfigSize = sizeOf<_LiteRtLmAsrConfig>();
    if (actualConfigSize != dartConfigSize) {
      throw ArgumentError(
        'ASR config layout is $actualConfigSize bytes; Dart expects '
        '$dartConfigSize.',
      );
    }
    final actualResultSize = resultSize();
    final dartResultSize = sizeOf<_LiteRtLmAsrResult>();
    if (actualResultSize != dartResultSize) {
      throw ArgumentError(
        'ASR result layout is $actualResultSize bytes; Dart expects '
        '$dartResultSize.',
      );
    }
    // Force every required lazy lookup while this is still a capability probe
    // so a partially packaged bridge cannot advertise ASR support and fail only
    // after model initialization.
    _keepAlive(<Object>[
      configInitForModelPreset,
      resultInit,
      resultRelease,
      freeString,
      engineCreate,
      engineDelete,
      sessionCreate,
      sessionDelete,
      sessionPushAudio,
      sessionFinishAudio,
      sessionProcessNext,
      sessionReset,
      sessionCancel,
    ]);
  }
}

class _LiteRtLmBindings {
  final DynamicLibrary _library;

  _LiteRtLmBindings(this._library) {
    requireLiteRtLmLegacyCApi(_library);
  }

  Pointer<NativeFunction<NativeF>>?
  _lookupOptionalNative<NativeF extends Function>(String symbol) {
    try {
      return _library.lookup<NativeFunction<NativeF>>(symbol);
    } on ArgumentError {
      return null;
    }
  }

  late final lastError = LiteRtLmLastError.probeLibrary(_library);

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

  late final loadedFileCreate =
      _lookupOptionalNative<
            Pointer<_LiteRtLmLoadedFile> Function(Pointer<Char>)
          >('litert_lm_loaded_file_create')
          ?.asFunction<Pointer<_LiteRtLmLoadedFile> Function(Pointer<Char>)>();

  late final loadedFileDelete =
      _lookupOptionalNative<Void Function(Pointer<_LiteRtLmLoadedFile>)>(
        'litert_lm_loaded_file_delete',
      )?.asFunction<void Function(Pointer<_LiteRtLmLoadedFile>)>();

  late final loadedFileHasSpeculativeDecodingSupport =
      _lookupOptionalNative<Bool Function(Pointer<_LiteRtLmLoadedFile>)>(
        'litert_lm_loaded_file_has_speculative_decoding_support',
      )?.asFunction<bool Function(Pointer<_LiteRtLmLoadedFile>)>();

  late final loadedFileSupportsInputModality =
      _lookupOptionalNative<Bool Function(Pointer<_LiteRtLmLoadedFile>, Int)>(
        'litert_lm_loaded_file_supports_input_modality',
      )?.asFunction<bool Function(Pointer<_LiteRtLmLoadedFile>, int)>();

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

  late final conversationConfigSetPromptTemplate = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>),
        void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>)
      >('litert_lm_conversation_config_set_prompt_template');

  late final conversationConfigSetExtraContext = _library
      .lookupFunction<
        Void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>),
        void Function(Pointer<_LiteRtLmConversationConfig>, Pointer<Char>)
      >('litert_lm_conversation_config_set_extra_context');

  late final jsonSchemaApi = LiteRtLmJsonSchemaApi.probeLibrary(_library);

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

  late final _LiteRtLmPenaltyApi? penaltyApi = _LiteRtLmPenaltyApi.lookup(this);

  late final _LiteRtLmThinkingApi? thinkingApi = _LiteRtLmThinkingApi.lookup(
    this,
  );
}

/// The per-send repetition penalty setters, present only when the runtime
/// exports all of them.
final class _LiteRtLmPenaltyApi {
  const _LiteRtLmPenaltyApi({
    required this.create,
    required this.delete,
    required this.setRepetitionPenalty,
    required this.setPresencePenalty,
    required this.setOnOptionalArgs,
  });

  static const symbols = <String>[
    'litert_lm_repetition_penalty_config_create',
    'litert_lm_repetition_penalty_config_delete',
    'litert_lm_repetition_penalty_config_set_repetition_penalty',
    'litert_lm_repetition_penalty_config_set_presence_penalty',
    'litert_lm_conversation_optional_args_set_repetition_penalty_config',
  ];

  static _LiteRtLmPenaltyApi? lookup(_LiteRtLmBindings bindings) {
    final create = bindings
        ._lookupOptionalNative<
          Pointer<_LiteRtLmRepetitionPenaltyConfig> Function()
        >(symbols[0])
        ?.asFunction<Pointer<_LiteRtLmRepetitionPenaltyConfig> Function()>();
    final delete = bindings
        ._lookupOptionalNative<
          Void Function(Pointer<_LiteRtLmRepetitionPenaltyConfig>)
        >(symbols[1])
        ?.asFunction<
          void Function(Pointer<_LiteRtLmRepetitionPenaltyConfig>)
        >();
    final setRepetitionPenalty = bindings
        ._lookupOptionalNative<
          Void Function(Pointer<_LiteRtLmRepetitionPenaltyConfig>, Float)
        >(symbols[2])
        ?.asFunction<
          void Function(Pointer<_LiteRtLmRepetitionPenaltyConfig>, double)
        >();
    final setPresencePenalty = bindings
        ._lookupOptionalNative<
          Void Function(Pointer<_LiteRtLmRepetitionPenaltyConfig>, Float)
        >(symbols[3])
        ?.asFunction<
          void Function(Pointer<_LiteRtLmRepetitionPenaltyConfig>, double)
        >();
    final setOnOptionalArgs = bindings
        ._lookupOptionalNative<
          Void Function(
            Pointer<_LiteRtLmConversationOptionalArgs>,
            Pointer<_LiteRtLmRepetitionPenaltyConfig>,
          )
        >(symbols[4])
        ?.asFunction<
          void Function(
            Pointer<_LiteRtLmConversationOptionalArgs>,
            Pointer<_LiteRtLmRepetitionPenaltyConfig>,
          )
        >();
    if (create == null ||
        delete == null ||
        setRepetitionPenalty == null ||
        setPresencePenalty == null ||
        setOnOptionalArgs == null) {
      return null;
    }
    return _LiteRtLmPenaltyApi(
      create: create,
      delete: delete,
      setRepetitionPenalty: setRepetitionPenalty,
      setPresencePenalty: setPresencePenalty,
      setOnOptionalArgs: setOnOptionalArgs,
    );
  }

  final Pointer<_LiteRtLmRepetitionPenaltyConfig> Function() create;
  final void Function(Pointer<_LiteRtLmRepetitionPenaltyConfig>) delete;
  final void Function(Pointer<_LiteRtLmRepetitionPenaltyConfig>, double)
  setRepetitionPenalty;
  final void Function(Pointer<_LiteRtLmRepetitionPenaltyConfig>, double)
  setPresencePenalty;
  final void Function(
    Pointer<_LiteRtLmConversationOptionalArgs>,
    Pointer<_LiteRtLmRepetitionPenaltyConfig>,
  )
  setOnOptionalArgs;
}

/// The per-send thinking budget setters, present only when the runtime
/// exports all of them.
final class _LiteRtLmThinkingApi {
  const _LiteRtLmThinkingApi({
    required this.create,
    required this.delete,
    required this.setEnableThinking,
    required this.setTokenBudget,
    required this.setOnOptionalArgs,
  });

  static const symbols = <String>[
    'litert_lm_thinking_config_create',
    'litert_lm_thinking_config_delete',
    'litert_lm_thinking_config_set_enable_thinking',
    'litert_lm_thinking_config_set_thinking_token_budget',
    'litert_lm_conversation_optional_args_set_thinking_config',
  ];

  static _LiteRtLmThinkingApi? lookup(_LiteRtLmBindings bindings) {
    final create = bindings
        ._lookupOptionalNative<Pointer<_LiteRtLmThinkingConfig> Function()>(
          symbols[0],
        )
        ?.asFunction<Pointer<_LiteRtLmThinkingConfig> Function()>();
    final delete = bindings
        ._lookupOptionalNative<Void Function(Pointer<_LiteRtLmThinkingConfig>)>(
          symbols[1],
        )
        ?.asFunction<void Function(Pointer<_LiteRtLmThinkingConfig>)>();
    final setEnableThinking = bindings
        ._lookupOptionalNative<
          Void Function(Pointer<_LiteRtLmThinkingConfig>, Bool)
        >(symbols[2])
        ?.asFunction<void Function(Pointer<_LiteRtLmThinkingConfig>, bool)>();
    final setTokenBudget = bindings
        ._lookupOptionalNative<
          Void Function(Pointer<_LiteRtLmThinkingConfig>, Int)
        >(symbols[3])
        ?.asFunction<void Function(Pointer<_LiteRtLmThinkingConfig>, int)>();
    final setOnOptionalArgs = bindings
        ._lookupOptionalNative<
          Void Function(
            Pointer<_LiteRtLmConversationOptionalArgs>,
            Pointer<_LiteRtLmThinkingConfig>,
          )
        >(symbols[4])
        ?.asFunction<
          void Function(
            Pointer<_LiteRtLmConversationOptionalArgs>,
            Pointer<_LiteRtLmThinkingConfig>,
          )
        >();
    if (create == null ||
        delete == null ||
        setEnableThinking == null ||
        setTokenBudget == null ||
        setOnOptionalArgs == null) {
      return null;
    }
    return _LiteRtLmThinkingApi(
      create: create,
      delete: delete,
      setEnableThinking: setEnableThinking,
      setTokenBudget: setTokenBudget,
      setOnOptionalArgs: setOnOptionalArgs,
    );
  }

  final Pointer<_LiteRtLmThinkingConfig> Function() create;
  final void Function(Pointer<_LiteRtLmThinkingConfig>) delete;
  final void Function(Pointer<_LiteRtLmThinkingConfig>, bool) setEnableThinking;
  final void Function(Pointer<_LiteRtLmThinkingConfig>, int) setTokenBudget;
  final void Function(
    Pointer<_LiteRtLmConversationOptionalArgs>,
    Pointer<_LiteRtLmThinkingConfig>,
  )
  setOnOptionalArgs;
}

// coverage:ignore-end
