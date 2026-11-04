// ignore_for_file: public_member_api_docs

import 'package:code_assets/code_assets.dart';
import 'package:path/path.dart' as path;

const String nativeBackendUserDefineKey = 'llamadart_native_backends';
const String nativeTagUserDefineKey = 'llamadart_native_tag';
const String nativeRepositoryUserDefineKey = 'llamadart_native_repository';
const String nativePathUserDefineKey = 'llamadart_native_path';
const String nativeRuntimesUserDefineKey = 'llamadart_native_runtimes';
const String nativeRuntimeLlamaCpp = 'llama_cpp';
const String nativeRuntimeLiteRtLm = 'litert_lm';

const List<String> allNativeRuntimes = [
  nativeRuntimeLlamaCpp,
  nativeRuntimeLiteRtLm,
];

const List<String> defaultNativeRuntimes = allNativeRuntimes;

const Set<String> _coreLibraries = {
  'llamadart',
  'llama',
  'llama-common',
  'ggml',
  'ggml-base',
  'mtmd',
};

const Set<String> _knownBundleKeys = {
  'android-arm64',
  'android-x64',
  'ios-arm64',
  'ios-arm64-sim',
  'ios-x86_64-sim',
  'linux-arm64',
  'linux-x64',
  'macos-arm64',
  'macos-x86_64',
  'windows-arm64',
  'windows-x64',
};

const Set<String> _knownOsKeys = {
  'android',
  'ios',
  'linux',
  'macos',
  'windows',
};

const Map<String, String> _bundleOsKeys = {
  'android-arm64': 'android',
  'android-x64': 'android',
  'ios-arm64': 'ios',
  'ios-arm64-sim': 'ios',
  'ios-x86_64-sim': 'ios',
  'linux-arm64': 'linux',
  'linux-x64': 'linux',
  'macos-arm64': 'macos',
  'macos-x86_64': 'macos',
  'windows-arm64': 'windows',
  'windows-x64': 'windows',
};

const List<String> _platformSuffixes = [
  '-ios-x86_64-sim',
  '-ios-arm64-sim',
  '-windows-arm64',
  '-windows-x64',
  '-android-arm64',
  '-android-x64',
  '-macos-x86_64',
  '-macos-arm64',
  '-linux-arm64',
  '-linux-x64',
  '-ios-arm64',
];

const Map<String, String> _bundleAliases = {
  'android-arm64-v8a': 'android-arm64',
  'android-x86_64': 'android-x64',
  'ios-x64-sim': 'ios-x86_64-sim',
  'linux-x86_64': 'linux-x64',
  'macos-x64': 'macos-x86_64',
  'windows-x86_64': 'windows-x64',
};

const Map<String, String> _osAliases = {
  'darwin': 'macos',
  'mac': 'macos',
  'mac-os': 'macos',
  'macosx': 'macos',
  'osx': 'macos',
  'iphoneos': 'ios',
  'iphonesimulator': 'ios',
  'ios-sim': 'ios',
  'ios-simulator': 'ios',
  'win': 'windows',
  'win32': 'windows',
  'win64': 'windows',
};

const Map<String, String> _backendAliases = {
  'vk': 'vulkan',
  'ocl': 'opencl',
  'open-cl': 'opencl',
};

const Map<String, String> _runtimeAliases = {
  'llama': nativeRuntimeLlamaCpp,
  'llamacpp': nativeRuntimeLlamaCpp,
  'llama-cpp': nativeRuntimeLlamaCpp,
  'llama.cpp': nativeRuntimeLlamaCpp,
  'gguf': nativeRuntimeLlamaCpp,
  'litert': nativeRuntimeLiteRtLm,
  'lite-rt': nativeRuntimeLiteRtLm,
  'lite-rt-lm': nativeRuntimeLiteRtLm,
  'litertlm': nativeRuntimeLiteRtLm,
  'litert-lm': nativeRuntimeLiteRtLm,
  'litert.lm': nativeRuntimeLiteRtLm,
  '.litertlm': nativeRuntimeLiteRtLm,
};

final _cudaRuntimeDependencyNamePattern = RegExp(
  r'^(?:cudart64|cublas64|cublaslt64)(?:[_-]?\d+)?$',
);

const String _androidArm64Bundle = 'android-arm64';
const String _androidCpuProfileCompact = 'compact';
const String _androidCpuProfileFull = 'full';
const String _androidCpuProfileDefault = _androidCpuProfileFull;

const List<String> _androidArm64CpuFullVariants = [
  'android_armv8.0_1',
  'android_armv8.2_1',
  'android_armv8.2_2',
  'android_armv8.6_1',
  'android_armv9.0_1',
  'android_armv9.2_1',
  'android_armv9.2_2',
];

const List<String> _androidArm64CpuCompactVariants = ['android_armv8.0_1'];

const Map<String, String> _androidCpuVariantAliases = {
  'baseline': 'android_armv8.0_1',
};

class NativeBundleSpec {
  final String bundle;
  final bool configurableBackends;
  final List<String> defaultBackends;

  const NativeBundleSpec({
    required this.bundle,
    required this.configurableBackends,
    required this.defaultBackends,
  });
}

class NativeLibraryDescriptor {
  final String filePath;
  final String fileName;
  final String canonicalName;
  final bool isCore;
  final bool isPrimary;
  final String? backend;

  const NativeLibraryDescriptor({
    required this.filePath,
    required this.fileName,
    required this.canonicalName,
    required this.isCore,
    required this.isPrimary,
    required this.backend,
  });
}

NativeBundleSpec? resolveNativeBundleSpec({
  required OS os,
  required Architecture arch,
  required bool isIosSimulator,
}) {
  switch ((os, arch)) {
    case (OS.android, Architecture.arm64):
      return const NativeBundleSpec(
        bundle: 'android-arm64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.android, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'android-x64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.iOS, Architecture.arm64):
      return NativeBundleSpec(
        bundle: isIosSimulator ? 'ios-arm64-sim' : 'ios-arm64',
        configurableBackends: false,
        defaultBackends: const [],
      );
    case (OS.iOS, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'ios-x86_64-sim',
        configurableBackends: false,
        defaultBackends: [],
      );
    case (OS.linux, Architecture.arm64):
      return const NativeBundleSpec(
        bundle: 'linux-arm64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.linux, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'linux-x64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.macOS, Architecture.arm64):
      return const NativeBundleSpec(
        bundle: 'macos-arm64',
        configurableBackends: false,
        defaultBackends: [],
      );
    case (OS.macOS, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'macos-x86_64',
        configurableBackends: false,
        defaultBackends: [],
      );
    case (OS.windows, Architecture.arm64):
      return const NativeBundleSpec(
        bundle: 'windows-arm64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    case (OS.windows, Architecture.x64):
      return const NativeBundleSpec(
        bundle: 'windows-x64',
        configurableBackends: true,
        defaultBackends: ['cpu', 'vulkan'],
      );
    default:
      return null;
  }
}

String canonicalizeBundleKey(String value) {
  var normalized = value.trim().toLowerCase().replaceAll(' ', '');
  normalized = normalized.replaceAll('_', '-');
  normalized = normalized.replaceAll('x86-64', 'x86_64');
  return _bundleAliases[normalized] ?? normalized;
}

String _canonicalizePlatformKey(String value) {
  final canonicalBundle = canonicalizeBundleKey(value);
  if (_knownBundleKeys.contains(canonicalBundle)) {
    return canonicalBundle;
  }
  return _osAliases[canonicalBundle] ?? canonicalBundle;
}

bool _isKnownPlatformConfigKey(String value) {
  final canonical = _canonicalizePlatformKey(value);
  return _knownBundleKeys.contains(canonical) ||
      _knownOsKeys.contains(canonical);
}

Object? _platformConfigValueForBundle({
  required String bundle,
  required Object? rawUserConfig,
}) {
  final root = _toStringMap(rawUserConfig);
  if (root == null) {
    return null;
  }

  final platformsMap = _extractPlatformsMap(root);
  if (platformsMap == null) {
    return null;
  }

  final canonicalBundle = canonicalizeBundleKey(bundle);
  for (final entry in platformsMap.entries) {
    if (canonicalizeBundleKey(entry.key) == canonicalBundle) {
      return entry.value;
    }
  }

  final osKey = _bundleOsKeys[canonicalBundle];
  if (osKey == null) {
    return null;
  }
  for (final entry in platformsMap.entries) {
    if (_canonicalizePlatformKey(entry.key) == osKey) {
      return entry.value;
    }
  }

  return null;
}

Map<String, Object?>? _platformConfigMapForBundle({
  required String bundle,
  required Object? rawUserConfig,
}) {
  final platformValue = _platformConfigValueForBundle(
    bundle: bundle,
    rawUserConfig: rawUserConfig,
  );
  return _toStringMap(platformValue);
}

NativeLibraryDescriptor describeNativeLibrary(String filePath) {
  final fileName = path.basename(filePath);
  final canonicalName = _canonicalLibraryName(fileName);
  final backend = _inferBackend(canonicalName);
  final isCore = _coreLibraries.contains(canonicalName);

  return NativeLibraryDescriptor(
    filePath: filePath,
    fileName: fileName,
    canonicalName: canonicalName,
    isCore: isCore,
    isPrimary: canonicalName == 'llamadart',
    backend: isCore ? null : backend,
  );
}

List<NativeLibraryDescriptor> describeNativeLibraries(
  Iterable<String> filePaths,
) {
  return filePaths.map(describeNativeLibrary).toList(growable: false);
}

Set<String> collectAvailableBackends(
  Iterable<NativeLibraryDescriptor> libraries,
) {
  final backends = <String>{};
  for (final library in libraries) {
    if (library.backend != null) {
      backends.add(library.backend!);
    }
  }
  return backends;
}

List<String>? parseRequestedBackends({
  required String bundle,
  required Object? rawUserConfig,
}) {
  final platformValue = _platformConfigValueForBundle(
    bundle: bundle,
    rawUserConfig: rawUserConfig,
  );
  if (platformValue == null) {
    return null;
  }

  if (platformValue is Map<Object?, Object?> &&
      platformValue['backends'] != null) {
    return _parseBackendList(platformValue['backends']);
  }

  return _parseBackendList(platformValue);
}

List<String> selectNativeRuntimesForBundle({
  required String bundle,
  required Object? rawUserConfig,
  required void Function(String message) warn,
}) {
  final parsed = _parseNativeRuntimeConfigForBundle(
    bundle: bundle,
    rawUserConfig: rawUserConfig,
  );
  if (parsed == null) {
    return defaultNativeRuntimesForBundle(bundle);
  }

  final invalid = parsed.invalid;
  if (invalid.isNotEmpty) {
    warn(
      'Ignoring unknown native runtime(s) for $bundle: ${invalid.join(', ')}. '
      'Supported runtimes: llama_cpp, litert_lm.',
    );
  }

  return parsed.runtimes;
}

bool nativeRuntimeExplicitlySelectedForBundle({
  required String bundle,
  required Object? rawUserConfig,
  required String runtime,
}) {
  final normalizedRuntime = _normalizeRuntime(runtime);
  if (normalizedRuntime == null ||
      normalizedRuntime == 'all' ||
      normalizedRuntime == 'none') {
    return false;
  }
  final parsed = _parseNativeRuntimeConfigForBundle(
    bundle: bundle,
    rawUserConfig: rawUserConfig,
  );
  return parsed?.explicit.contains(normalizedRuntime) ?? false;
}

List<String> defaultNativeRuntimesForBundle(String bundle) {
  return defaultNativeRuntimes;
}

List<String> selectBackendsForBundle({
  required NativeBundleSpec spec,
  required Set<String> availableBackends,
  required Object? rawUserConfig,
  required void Function(String message) warn,
}) {
  if (!spec.configurableBackends) {
    return const [];
  }

  final defaults = spec.defaultBackends
      .where(availableBackends.contains)
      .toList(growable: false);
  final effectiveDefaults = _ensureCpuBackend(defaults, availableBackends);

  final requested = parseRequestedBackends(
    bundle: spec.bundle,
    rawUserConfig: rawUserConfig,
  );

  if (requested == null || requested.isEmpty) {
    if (effectiveDefaults.isNotEmpty || availableBackends.isEmpty) {
      return effectiveDefaults;
    }

    final fallback = availableBackends.toList()..sort();
    warn(
      'No default backend module was found for ${spec.bundle}; '
      'bundling all available modules: ${fallback.join(', ')}.',
    );
    return fallback;
  }

  final missing = requested
      .where((backend) => !availableBackends.contains(backend))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    warn(
      'Requested backend(s) ${missing.join(', ')} are unavailable for '
      '${spec.bundle}. Falling back to defaults: '
      '${effectiveDefaults.join(', ')}.',
    );
    if (effectiveDefaults.isNotEmpty || availableBackends.isEmpty) {
      return effectiveDefaults;
    }

    final fallback = availableBackends.toList()..sort();
    warn(
      'Default backends are also unavailable for ${spec.bundle}; '
      'bundling all available modules: ${fallback.join(', ')}.',
    );
    return fallback;
  }

  return _ensureCpuBackend(requested, availableBackends);
}

({List<String> runtimes, List<String> invalid, Set<String> explicit})?
_parseNativeRuntimeConfigForBundle({
  required String bundle,
  required Object? rawUserConfig,
}) {
  if (rawUserConfig == null) {
    return null;
  }

  if (rawUserConfig is String || rawUserConfig is List<Object?>) {
    return _parseRuntimeList(rawUserConfig);
  }

  final root = _toStringMap(rawUserConfig);
  if (root == null) {
    return (
      runtimes: defaultNativeRuntimesForBundle(bundle),
      invalid: [rawUserConfig.toString()],
      explicit: const <String>{},
    );
  }

  final globalValue = root.containsKey('runtimes')
      ? root['runtimes']
      : root.containsKey('default')
      ? root['default']
      : null;
  final platformValue = _platformConfigValueForBundle(
    bundle: bundle,
    rawUserConfig: rawUserConfig,
  );

  if (platformValue != null) {
    if (platformValue is Map<Object?, Object?>) {
      final platformMap = _toStringMap(platformValue);
      if (platformMap != null && platformMap.containsKey('runtimes')) {
        return _parseRuntimeList(platformMap['runtimes']);
      }
      return _parseRuntimeList(platformValue);
    }
    return _parseRuntimeList(platformValue);
  }

  if (globalValue != null) {
    return _parseRuntimeList(globalValue);
  }

  final hasRuntimeShape =
      root.keys.any(_isKnownPlatformConfigKey) ||
      _extractPlatformsMap(root) != null;
  if (hasRuntimeShape) {
    return null;
  }

  return (
    runtimes: defaultNativeRuntimesForBundle(bundle),
    invalid: [rawUserConfig.toString()],
    explicit: const <String>{},
  );
}

List<String> _androidCpuVariantsForProfile(String profile) {
  switch (profile) {
    case _androidCpuProfileCompact:
      return _androidArm64CpuCompactVariants;
    case _androidCpuProfileFull:
      return _androidArm64CpuFullVariants;
    default:
      return _androidArm64CpuFullVariants;
  }
}

String _resolveAndroidCpuProfile({
  required Map<String, Object?> platformConfig,
  required void Function(String message) warn,
}) {
  final raw = platformConfig['cpu_profile'];
  if (raw == null) {
    return _androidCpuProfileDefault;
  }

  if (raw is! String) {
    warn(
      'Invalid cpu_profile for $_androidArm64Bundle. '
      'Expected string (compact/full); defaulting to '
      '$_androidCpuProfileDefault.',
    );
    return _androidCpuProfileDefault;
  }

  final normalized = raw.trim().toLowerCase().replaceAll('_', '-');
  if (normalized == _androidCpuProfileCompact ||
      normalized == _androidCpuProfileFull) {
    return normalized;
  }

  warn(
    'Unknown cpu_profile "$raw" for $_androidArm64Bundle. '
    'Supported values: compact, full. '
    'Defaulting to $_androidCpuProfileDefault.',
  );
  return _androidCpuProfileDefault;
}

({List<String> selected, List<String> invalid}) _parseAndroidCpuVariantList(
  Object? value,
) {
  final selected = <String>[];
  final invalid = <String>[];
  final tokens = <String>[];

  if (value is String) {
    tokens.addAll(value.split(','));
  } else if (value is List<Object?>) {
    for (final entry in value) {
      if (entry is String) {
        tokens.add(entry);
      } else if (entry != null) {
        invalid.add(entry.toString());
      }
    }
  } else if (value != null) {
    invalid.add(value.toString());
  }

  for (final token in tokens) {
    final normalized = _normalizeAndroidCpuVariant(token);
    if (normalized == null) {
      if (token.trim().isNotEmpty) {
        invalid.add(token.trim());
      }
      continue;
    }
    if (!selected.contains(normalized)) {
      selected.add(normalized);
    }
  }

  return (selected: selected, invalid: invalid);
}

String? _normalizeAndroidCpuVariant(String value) {
  var normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }

  normalized = normalized.replaceAll(' ', '');
  normalized = normalized.replaceAll('-', '_');
  if (normalized.startsWith('libggml_cpu_')) {
    normalized = normalized.substring('libggml_cpu_'.length);
  }
  if (normalized.startsWith('ggml_cpu_')) {
    normalized = normalized.substring('ggml_cpu_'.length);
  }
  if (normalized.endsWith('.so')) {
    normalized = normalized.substring(0, normalized.length - '.so'.length);
  }

  if (normalized.startsWith('androidarmv')) {
    normalized = normalized.replaceFirst('androidarmv', 'android_armv');
  }
  if (normalized.startsWith('armv')) {
    normalized = 'android_$normalized';
  }
  if (normalized.startsWith('v')) {
    normalized = 'android_arm$normalized';
  }

  final compactMatch = RegExp(
    r'^android_armv(\d+)_([0-9]+_[0-9]+)$',
  ).firstMatch(normalized);
  if (compactMatch != null) {
    normalized =
        'android_armv${compactMatch.group(1)}.${compactMatch.group(2)}';
  }

  normalized = _androidCpuVariantAliases[normalized] ?? normalized;
  if (_androidArm64CpuFullVariants.contains(normalized)) {
    return normalized;
  }
  return null;
}

List<String> _resolveAndroidArm64CpuVariants({
  required Object? rawUserConfig,
  required void Function(String message) warn,
}) {
  final platformConfig = _platformConfigMapForBundle(
    bundle: _androidArm64Bundle,
    rawUserConfig: rawUserConfig,
  );

  if (platformConfig == null) {
    return _androidCpuVariantsForProfile(_androidCpuProfileDefault);
  }

  if (platformConfig.containsKey('cpu_variants')) {
    final parsed = _parseAndroidCpuVariantList(platformConfig['cpu_variants']);
    if (parsed.invalid.isNotEmpty) {
      warn(
        'Ignoring unknown cpu_variants for $_androidArm64Bundle: '
        '${parsed.invalid.join(', ')}.',
      );
    }
    if (parsed.selected.isNotEmpty) {
      return parsed.selected;
    }
    warn(
      'No valid cpu_variants were provided for $_androidArm64Bundle. '
      'Falling back to cpu_profile/default selection.',
    );
  }

  final profile = _resolveAndroidCpuProfile(
    platformConfig: platformConfig,
    warn: warn,
  );
  return _androidCpuVariantsForProfile(profile);
}

bool _isCpuBackendModule(NativeLibraryDescriptor library) {
  if (library.isCore || library.backend != 'cpu') {
    return false;
  }

  return library.canonicalName == 'ggml-cpu' ||
      library.canonicalName.startsWith('ggml-cpu-');
}

String? _androidCpuVariantTagFromCanonicalName(String canonicalName) {
  if (!canonicalName.startsWith('ggml-cpu-')) {
    return null;
  }
  return canonicalName.substring('ggml-cpu-'.length);
}

List<NativeLibraryDescriptor> selectLibrariesForBundling({
  required NativeBundleSpec spec,
  required List<NativeLibraryDescriptor> libraries,
  required Object? rawUserConfig,
  required void Function(String message) warn,
}) {
  if (!spec.configurableBackends) {
    return libraries;
  }

  final selectedBackends = selectBackendsForBundle(
    spec: spec,
    availableBackends: collectAvailableBackends(libraries),
    rawUserConfig: rawUserConfig,
    warn: warn,
  );

  final selectedLibraries = libraries
      .where((library) {
        if (library.isCore) {
          return true;
        }

        final runtimeBackend = _runtimeDependencyBackendFor(library);
        if (runtimeBackend != null) {
          return selectedBackends.contains(runtimeBackend);
        }

        if (library.backend == null) {
          return true;
        }

        return selectedBackends.contains(library.backend);
      })
      .toList(growable: false);

  if (spec.bundle != _androidArm64Bundle) {
    return selectedLibraries;
  }

  final selectedCpuVariants = _resolveAndroidArm64CpuVariants(
    rawUserConfig: rawUserConfig,
    warn: warn,
  ).toSet();

  final filteredLibraries = selectedLibraries
      .where((library) {
        if (!_isCpuBackendModule(library)) {
          return true;
        }

        // Keep legacy unsuffixed CPU backend modules when present.
        final variant = _androidCpuVariantTagFromCanonicalName(
          library.canonicalName,
        );
        if (variant == null) {
          return true;
        }

        return selectedCpuVariants.contains(variant);
      })
      .toList(growable: false);

  if (filteredLibraries.any(_isCpuBackendModule)) {
    return filteredLibraries;
  }

  warn(
    'No CPU backend module matched Android arm64 cpu profile selection. '
    'Bundling all available CPU modules instead.',
  );
  return selectedLibraries;
}

String codeAssetNameForLibrary({
  required NativeBundleSpec spec,
  required NativeLibraryDescriptor library,
}) {
  // Windows split bundle exports core llama/ggml symbols from `llama.dll`,
  // while `llamadart.dll` only contains wrapper helpers. The Dart bindings
  // default asset must point at the core symbol provider.
  if (spec.bundle.startsWith('windows-')) {
    if (library.canonicalName == 'llama') {
      return 'llamadart';
    }
    if (library.canonicalName == 'llamadart') {
      return 'llamadart_wrapper';
    }
  }

  if (library.isPrimary) {
    return 'llamadart';
  }
  return library.canonicalName.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
}

List<String> _ensureCpuBackend(
  List<String> backends,
  Set<String> availableBackends,
) {
  if (!availableBackends.contains('cpu') || backends.contains('cpu')) {
    return backends;
  }

  final updated = <String>['cpu', ...backends];
  return updated;
}

Map<String, Object?>? _extractPlatformsMap(Map<String, Object?> root) {
  final platformsValue = root['platforms'];
  final platformsMap = _toStringMap(platformsValue);
  if (platformsMap != null) {
    return platformsMap;
  }

  // Backward-compatible shape: direct platform map.
  final hasPlatformKeys = root.keys.any(_isKnownPlatformConfigKey);
  if (hasPlatformKeys) {
    return root;
  }

  return null;
}

Map<String, Object?>? _toStringMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }

  final mapped = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      mapped[key] = entry.value;
    }
  }
  return mapped;
}

List<String> _parseBackendList(Object? value) {
  final result = <String>[];

  if (value is String) {
    for (final token in value.split(',')) {
      final normalized = _normalizeBackend(token);
      if (normalized != null && !result.contains(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  if (value is! List<Object?>) {
    return result;
  }

  for (final entry in value) {
    if (entry is! String) {
      continue;
    }
    final normalized = _normalizeBackend(entry);
    if (normalized != null && !result.contains(normalized)) {
      result.add(normalized);
    }
  }

  return result;
}

({List<String> runtimes, List<String> invalid, Set<String> explicit})
_parseRuntimeList(Object? value) {
  final result = <String>[];
  final invalid = <String>[];
  final explicit = <String>{};

  void addToken(String token) {
    final normalized = _normalizeRuntime(token);
    if (normalized == null) {
      if (token.trim().isNotEmpty) {
        invalid.add(token.trim());
      }
      return;
    }
    if (normalized == 'all') {
      for (final runtime in allNativeRuntimes) {
        if (!result.contains(runtime)) {
          result.add(runtime);
        }
      }
      return;
    }
    if (normalized == 'none') {
      result.clear();
      explicit.clear();
      return;
    }
    if (!result.contains(normalized)) {
      result.add(normalized);
    }
    explicit.add(normalized);
  }

  if (value is String) {
    for (final token in value.split(',')) {
      addToken(token);
    }
    return (
      runtimes: result.isEmpty ? allNativeRuntimes : result,
      invalid: invalid,
      explicit: explicit,
    );
  }

  if (value is List<Object?>) {
    for (final entry in value) {
      if (entry is String) {
        addToken(entry);
      } else if (entry != null) {
        invalid.add(entry.toString());
      }
    }
    return (
      runtimes: result.isEmpty ? allNativeRuntimes : result,
      invalid: invalid,
      explicit: explicit,
    );
  }

  if (value is Map<Object?, Object?>) {
    final mapped = _toStringMap(value);
    if (mapped != null && mapped.containsKey('runtimes')) {
      return _parseRuntimeList(mapped['runtimes']);
    }
  }

  if (value != null) {
    invalid.add(value.toString());
  }
  return (runtimes: result, invalid: invalid, explicit: explicit);
}

String? _normalizeBackend(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('_', '-');
  if (normalized.isEmpty) {
    return null;
  }
  return _backendAliases[normalized] ?? normalized;
}

String? _normalizeRuntime(String value) {
  var normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  normalized = normalized.replaceAll('_', '-');
  if (normalized == 'all' || normalized == 'both') {
    return 'all';
  }
  if (normalized == 'none' || normalized == 'off' || normalized == 'false') {
    return 'none';
  }
  if (normalized == nativeRuntimeLlamaCpp.replaceAll('_', '-')) {
    return nativeRuntimeLlamaCpp;
  }
  if (normalized == nativeRuntimeLiteRtLm.replaceAll('_', '-')) {
    return nativeRuntimeLiteRtLm;
  }
  return _runtimeAliases[normalized];
}

String _canonicalLibraryName(String fileName) {
  var stem = fileName.toLowerCase();

  if (stem.endsWith('.dll')) {
    stem = stem.substring(0, stem.length - '.dll'.length);
  } else if (stem.endsWith('.dylib')) {
    stem = stem.substring(0, stem.length - '.dylib'.length);
  } else {
    stem = stem.replaceFirst(RegExp(r'\.so(?:\.\d+)*$'), '');
  }

  if (stem.startsWith('lib') && stem.length > 3) {
    stem = stem.substring(3);
  }

  for (final suffix in _platformSuffixes) {
    if (stem.endsWith(suffix)) {
      return stem.substring(0, stem.length - suffix.length);
    }
  }

  return stem;
}

String? _inferBackend(String canonicalName) {
  if (canonicalName.startsWith('ggml-')) {
    final suffix = canonicalName.substring('ggml-'.length);
    if (suffix.isEmpty || suffix == 'base') {
      return null;
    }
    return _normalizeBackend(suffix.split('-').first);
  }

  if (canonicalName == 'opencl') {
    return 'opencl';
  }

  return null;
}

String? _runtimeDependencyBackendFor(NativeLibraryDescriptor library) {
  final canonicalName = library.canonicalName;
  if (_cudaRuntimeDependencyNamePattern.hasMatch(canonicalName)) {
    return 'cuda';
  }
  if (canonicalName.startsWith('openblas')) {
    return 'blas';
  }
  return null;
}
