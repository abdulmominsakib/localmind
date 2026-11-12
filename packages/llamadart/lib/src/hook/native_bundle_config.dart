/// Decodes the `hooks.user_defines.llamadart` native-bundle configuration for
/// `hook/build.dart`. Pure decisions over already-discovered paths and
/// already-decoded config: nothing here downloads, extracts, or emits assets.
///
/// [nativeRuntimesUserDefineKey] picks the runtime families to build;
/// [nativeBackendUserDefineKey] filters the split llama.cpp backend modules
/// within `llama_cpp`. Both scope by platform through a `platforms` map, or —
/// kept for backward compatibility — a bare map already keyed by platform.
///
/// Entry-point roles, deliberately not a call order `hook/build.dart` may
/// reorder: [resolveNativeBundleSpec] names the target's release bundle;
/// [selectNativeRuntimesForBundle] picks the runtime families and
/// [nativeRuntimeExplicitlySelectedForBundle] and
/// [nativeRuntimeNamedForExactBundle] say how hard to fail when one is
/// unpublished, and whether `all` only implied it; [stableDiffusionBundleForNativeBundle] names the opt-in
/// stable_diffusion archive; [describeNativeLibrary] classifies a discovered
/// file; [selectLibrariesForBundling] picks which ship;
/// [codeAssetNameForLibrary] names each as a code asset. A Flutter Apple build
/// depending on the llama.cpp or LiteRT-LM companion package takes the
/// llama_cpp and litert_lm families from it, not
/// [selectNativeRuntimesForBundle]. stable_diffusion is decided on its own: the
/// stable_diffusion companion selects it, and otherwise it still comes from
/// [selectNativeRuntimesForBundle], unless `all` only implied it: such a build
/// skips it.
///
/// User-facing docs: `website/docs/platforms/native-build-hooks.md` and
/// `website/docs/guides/backend-selection.md`.
library;

import 'package:code_assets/code_assets.dart';
import 'package:path/path.dart' as path;

export 'native_release_tag.dart';

/// User-define key selecting which llama.cpp backend modules to bundle (`cpu`,
/// `vulkan`, `cuda`, `blas`, `opencl`, `hip`); also carries the Android arm64
/// `cpu_profile`/`cpu_variants` policy. [parseRequestedBackends] decodes the
/// backend list; [selectLibrariesForBundling] decodes the CPU policy.
const String nativeBackendUserDefineKey = 'llamadart_native_backends';

/// User-define key choosing the stable_diffusion build (`cpu` or `vulkan`) on
/// Linux and Windows independently of the llama.cpp backends; same shape as
/// [nativeBackendUserDefineKey]. See [stableDiffusionBundleForNativeBundle].
const String stableDiffusionBackendUserDefineKey =
    'llamadart_stable_diffusion_backends';

/// `llamadart-native` release tag to download; resolved in `hook/build.dart`.
const String nativeTagUserDefineKey = 'llamadart_native_tag';

/// GitHub `owner/repo` slug releases come from; resolved in `hook/build.dart`.
const String nativeRepositoryUserDefineKey = 'llamadart_native_repository';

/// Local native bundle directory, used instead of a release download;
/// resolved in `hook/build.dart`.
const String nativePathUserDefineKey = 'llamadart_native_path';

/// User-define key selecting runtime families. Decoded by
/// [selectNativeRuntimesForBundle].
const String nativeRuntimesUserDefineKey = 'llamadart_native_runtimes';

/// The llama.cpp/GGUF runtime family; the only one with configurable backends.
const String nativeRuntimeLlamaCpp = 'llama_cpp';

/// The LiteRT-LM runtime family; not published for every bundle.
const String nativeRuntimeLiteRtLm = 'litert_lm';

/// The experimental stable-diffusion.cpp runtime family. Opt-in: it is
/// bundled when named or through `all`, never by default and never through
/// `both`, because it adds tens of megabytes per platform. Not published for
/// every bundle; see [stableDiffusionBundleForNativeBundle].
const String nativeRuntimeStableDiffusion = 'stable_diffusion';

/// The runtime families `all` expands to, in that order.
const List<String> allNativeRuntimes = [
  nativeRuntimeLlamaCpp,
  nativeRuntimeLiteRtLm,
  nativeRuntimeStableDiffusion,
];

/// Every runtime family a config may name.
const List<String> supportedNativeRuntimes = allNativeRuntimes;

/// The families `both` expands to, and the fallback for config that names no
/// runtimes. An explicit `none` selects nothing instead.
const List<String> defaultNativeRuntimes = [
  nativeRuntimeLlamaCpp,
  nativeRuntimeLiteRtLm,
];

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
  'stable-diffusion': nativeRuntimeStableDiffusion,
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

/// What `llamadart-native` publishes for one target.
class NativeBundleSpec {
  /// Release bundle key (`linux-x64`, `ios-arm64-sim`), and the key user
  /// config is matched against. Downstream branches test it by prefix
  /// (`windows-`) or whole (`android-arm64`).
  final String bundle;

  /// Whether this bundle ships split `ggml-*` backend modules that
  /// `llamadart_native_backends` can filter. `false` for the consolidated
  /// Apple runtimes, where [selectBackendsForBundle] selects nothing and
  /// [selectLibrariesForBundling] passes every library through unchanged.
  final bool configurableBackends;

  /// Backends preferred when the user requests none — listing one here does
  /// not force it to exist, and [selectBackendsForBundle] may bundle more or
  /// other modules. Empty whenever [configurableBackends] is `false`.
  final List<String> defaultBackends;

  /// Creates a spec for one release bundle.
  const NativeBundleSpec({
    required this.bundle,
    required this.configurableBackends,
    required this.defaultBackends,
  });
}

/// One native library file, classified from its basename alone.
class NativeLibraryDescriptor {
  /// Path the file was found at, verbatim.
  ///
  /// `hook/build.dart` re-describes every file it copies into the build output
  /// directory, and on `linux-*` copies each `.so` under its `.so.0` SONAME
  /// alias too, so each `.so` yields two descriptors sharing one
  /// [canonicalName]. Overrides pinning a historical `bNNNN` artifact or the
  /// original `v0.2.0` add a third `libmtmd.so.SOVERSION` descriptor for their
  /// literal placeholder SONAME, which canonicalises to a non-core
  /// `mtmd.so.soversion`.
  final String filePath;

  /// Basename of [filePath], with the casing it has on disk.
  final String fileName;

  /// [fileName] lowercased, with the extension (including trailing `.<n>`
  /// SONAME components), a leading `lib`, and any packed platform suffix such
  /// as `-windows-x64` removed: `libllama.so.0` and `llama-windows-x64.dll`
  /// both give `llama`. Every classification decision keys off this name.
  final String canonicalName;

  /// Whether this library is bundled regardless of backend selection:
  /// `llamadart`, `llama`, `llama-common`, `ggml`, `ggml-base`, `mtmd`. Core
  /// libraries always report a `null` [backend].
  final bool isCore;

  /// Whether [canonicalName] is `llamadart`. `hook/build.dart` fails the build
  /// when no discovered library is primary. Not the same as owning the default
  /// asset name: on Windows [codeAssetNameForLibrary] gives that to `llama`.
  final bool isPrimary;

  /// Backend module this library implements, or `null` — for core libraries,
  /// for names that imply no backend, and for CUDA/BLAS runtime dependencies,
  /// which [selectLibrariesForBundling] matches by name instead.
  final String? backend;

  /// Creates a descriptor for one classified library file.
  const NativeLibraryDescriptor({
    required this.filePath,
    required this.fileName,
    required this.canonicalName,
    required this.isCore,
    required this.isPrimary,
    required this.backend,
  });
}

/// The `llamadart-native` release bundle for a target OS/architecture, or
/// `null` when none is published — `hook/build.dart` then warns and emits no
/// native assets at all.
///
/// Apple bundles are not backend-configurable; Android, Linux and Windows
/// are, and default to `['cpu', 'vulkan']`.
///
/// [isIosSimulator] only distinguishes `ios-arm64` from `ios-arm64-sim`; the
/// x64 iOS bundle is simulator-only regardless of the flag.
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

/// Normalises a user-written bundle key so config keys and bundle names
/// compare equal: spaces are stripped and `_` folds to `-`, then `x86-64` is
/// respelled `x86_64` to match the published bundle keys. Bundle aliases such
/// as `android-arm64-v8a` are resolved too. Unrecognised values come back
/// normalised rather than rejected.
///
/// OS aliases (`darwin`, `osx`, `win32`, `iphonesimulator`, ...) are
/// deliberately not applied here: OS keys are only considered one level up,
/// after an exact bundle-key match has failed.
///
/// `ios-arm64-sim` never collapses to `ios-arm64`: a config entry naming the
/// device bundle must not silently change what a simulator build bundles. Use
/// the `ios` OS key to cover both.
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

/// Classifies one library file from its basename; the file is never opened.
///
/// A canonical name in the core set reports `isCore: true` and a `null`
/// backend. Otherwise the backend is the first `-`-separated token after a
/// `ggml-` prefix, alias-resolved, so `libggml-cpu-android_armv8.2_1.so`
/// infers `cpu`; bare `ggml` and `ggml-base` infer nothing, and a canonical
/// name of exactly `opencl` infers `opencl`.
///
/// The split runs before the alias lookup, so single-token aliases survive it
/// (`vk`, `ocl`) and multi-token ones do not: `open-cl` resolves to `opencl`
/// in user config, but `libggml-open-cl.so` infers `open`.
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

/// [describeNativeLibrary] over every path, order preserved.
/// `hook/build.dart` requires at least one primary entry before going on.
List<NativeLibraryDescriptor> describeNativeLibraries(
  Iterable<String> filePaths,
) {
  return filePaths.map(describeNativeLibrary).toList(growable: false);
}

/// The distinct non-null backends present in [libraries] — what this bundle
/// can actually offer. Requested and default backends are validated against
/// this set, so a bundle shipping no `ggml-cuda` module cannot select `cuda`.
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

/// The backends requested for [bundle] under `llamadart_native_backends`, or
/// `null` when the config resolves no value for it: unset, not
/// platform-scoped, or no matching entry. The lookup takes the first key
/// canonicalising to [bundle], else the first for its OS. Both `null` and `[]`
/// leave the bundle defaults in force in [selectBackendsForBundle].
///
/// A matched platform entry may be a comma-separated string, a list of
/// strings, or a map with a `backends` key — the map form also carries
/// `cpu_profile`/`cpu_variants`; a matched map without `backends` yields `[]`,
/// not `null`. Tokens are trimmed, lowercased, `_`-to-`-` normalised,
/// alias-resolved and de-duplicated in first-seen order; non-string list
/// entries are skipped.
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

/// The runtime families to build for [bundle], decoded from
/// `llamadart_native_runtimes`.
///
/// Precedence, first match wins: the `platforms` entry canonicalising to
/// [bundle]; the entry for that bundle's OS; the top-level `runtimes` key; the
/// top-level `default` key; else [defaultNativeRuntimes]. A
/// matched platform entry with a `null` value ends the platform search, so the
/// OS entry is skipped. `runtimes` is consulted by key presence, so an
/// explicit `runtimes: null` suppresses `default` instead of falling through
/// to it. A bare string or list at the root is taken as-is, unscoped.
///
/// Tokens are trimmed, lowercased and `_`-to-`-` normalised before alias
/// lookup: `gguf` and `llama.cpp` reach `llama_cpp`; `litert`, `litertlm` and
/// `.litertlm` reach `litert_lm`; `stable-diffusion` reaches
/// `stable_diffusion`. `all` expands to [allNativeRuntimes] and `both` to
/// [defaultNativeRuntimes], which leaves out the opt-in `stable_diffusion`;
/// the string tokens `none`, `off` and `false` clear what has accumulated. A
/// bare YAML boolean `false` clears it too, including in a list.
/// Unrecognised non-empty tokens are dropped and reported once through
/// [warn]; empty tokens are ignored silently. A string or list that selects
/// nothing because it was empty or all-unrecognised yields
/// [defaultNativeRuntimes]. Once a `none` token clears the selection only a later
/// recognised token refills it, so `['none', 'llama_cpp']` selects `llama_cpp`
/// while `['none', 'tflite']` stays empty, which `hook/build.dart` throws on.
///
/// A map is first unwrapped through its `runtimes` key. At a selected map
/// entry, values other than a string, list, map, or boolean `false` select
/// nothing, which `hook/build.dart` throws on. When no level resolves a value
/// at all — an unsupported scalar at the *root* included — the fallback to
/// [defaultNativeRuntimes] is silent when the key is unset or the config is
/// platform-scoped, and a [warn] otherwise.
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
    return defaultNativeRuntimes;
  }

  final invalid = parsed.invalid;
  if (invalid.isNotEmpty) {
    warn(
      'Ignoring unknown native runtime(s) for $bundle: ${invalid.join(', ')}. '
      'Supported runtimes: ${supportedNativeRuntimes.join(', ')}.',
    );
  }

  return parsed.runtimes;
}

/// Whether [runtime] was named for [bundle], not implied by a default or by
/// `all`/`both` expansion. `false` for `all`, `both`, `none`, unrecognised
/// spellings, and for a name a later `none` cleared (`['litert_lm', 'none']`).
/// Order decides it, so `['none', 'litert_lm']` is explicit.
///
/// `hook/build.dart` uses this when LiteRT-LM is selected but the bundle
/// publishes no LiteRT-LM archive: an explicit request throws, an implied one
/// is dropped with a warning. It also uses it on Flutter iOS and macOS builds
/// without the stable_diffusion companion, where a stable_diffusion that
/// `all` only implied is skipped.
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

/// Whether [runtime] is named in the `platforms` entry whose key is exactly
/// [bundle] (after [canonicalizeBundleKey]); an OS key such as `android`, the
/// top-level `runtimes`/`default` keys and a bare list do not count. Order and
/// `none` apply as in [nativeRuntimeExplicitlySelectedForBundle].
///
/// `hook/build.dart` fails the build only for such a bundle-scoped request
/// when the bundle publishes no stable_diffusion archive. A broader request,
/// such as a top-level `runtimes: [llama_cpp, stable_diffusion]`, would
/// otherwise break Flutter Android builds that also target `android-x64`.
bool nativeRuntimeNamedForExactBundle({
  required String bundle,
  required Object? rawUserConfig,
  required String runtime,
}) {
  final normalizedRuntime = _normalizeRuntime(runtime);
  final root = _toStringMap(rawUserConfig);
  if (normalizedRuntime == null || root == null) {
    return false;
  }
  final platformsMap = _extractPlatformsMap(root);
  if (platformsMap == null) {
    return false;
  }
  final canonicalBundle = canonicalizeBundleKey(bundle);
  for (final entry in platformsMap.entries) {
    if (canonicalizeBundleKey(entry.key) != canonicalBundle) {
      continue;
    }
    final value = entry.value;
    final platformMap = _toStringMap(value);
    final parsed = _parseRuntimeList(
      platformMap != null && platformMap.containsKey('runtimes')
          ? platformMap['runtimes']
          : value,
    );
    return parsed.explicit.contains(normalizedRuntime);
  }
  return false;
}

/// The stable-diffusion-native release bundle for the llama.cpp [spec], or
/// `null` when none is published (`android-x64`, `windows-arm64`).
///
/// Linux and Windows publish a CPU and a `-vulkan` archive; only one is
/// bundled. [rawStableDiffusionBackendConfig]
/// (`llamadart_stable_diffusion_backends`: a list or string for every
/// platform, or a `platforms` map like `llamadart_native_backends`) decides
/// first: `-vulkan` when it names
/// `vulkan`, the CPU archive when it names only `cpu`. An entry naming neither
/// is ignored with a [warn]. Without an entry the choice follows the llama.cpp
/// selection under `llamadart_native_backends` ([rawBackendConfig]): the
/// `-vulkan` archive when Vulkan is requested there, or when nothing is
/// requested and Vulkan is among [NativeBundleSpec.defaultBackends]; the CPU
/// archive otherwise. Apple bundles are Metal builds and Android arm64 is
/// CPU-only, whatever either config says.
String? stableDiffusionBundleForNativeBundle({
  required NativeBundleSpec spec,
  required Object? rawBackendConfig,
  Object? rawStableDiffusionBackendConfig,
  void Function(String message)? warn,
}) {
  final base = switch (spec.bundle) {
    'android-arm64' => 'android-arm64',
    'ios-arm64' => 'ios-arm64',
    'ios-arm64-sim' => 'ios-arm64-sim',
    'ios-x86_64-sim' => 'ios-x64-sim',
    'macos-arm64' => 'macos-arm64',
    'macos-x86_64' => 'macos-x64',
    'linux-arm64' => 'linux-arm64',
    'linux-x64' => 'linux-x64',
    'windows-x64' => 'windows-x64',
    _ => null,
  };
  if (base == null ||
      !(spec.bundle.startsWith('linux-') ||
          spec.bundle.startsWith('windows-'))) {
    return base;
  }
  final own =
      rawStableDiffusionBackendConfig is String ||
          rawStableDiffusionBackendConfig is List
      ? _parseBackendList(rawStableDiffusionBackendConfig)
      : parseRequestedBackends(
          bundle: spec.bundle,
          rawUserConfig: rawStableDiffusionBackendConfig,
        );
  if (own != null && own.isNotEmpty) {
    if (own.contains('vulkan')) {
      return '$base-vulkan';
    }
    if (own.contains('cpu')) {
      return base;
    }
    warn?.call(
      '$stableDiffusionBackendUserDefineKey for ${spec.bundle} names '
      '${own.join(', ')}; stable_diffusion supports cpu and vulkan there. '
      'Following $nativeBackendUserDefineKey instead.',
    );
  }
  final requested = parseRequestedBackends(
    bundle: spec.bundle,
    rawUserConfig: rawBackendConfig,
  );
  final backends = requested == null || requested.isEmpty
      ? spec.defaultBackends
      : requested;
  return backends.contains('vulkan') ? '$base-vulkan' : base;
}

/// The backend modules to bundle for [spec], constrained to
/// [availableBackends]. Non-configurable bundles select nothing.
///
/// `cpu` is added to the defaults and to an accepted request whenever a `cpu`
/// module exists, so it cannot be opted out of. The defaults are
/// [NativeBundleSpec.defaultBackends] restricted to what is available; they
/// apply when the request is `null` or empty, and also when a request names
/// any unavailable backend — such a request is rejected whole, not partially,
/// with a [warn] naming the missing backends. When the defaults resolve to
/// nothing while the bundle does contain modules, every available module is
/// bundled in sort order with a [warn] of its own — a second one on the
/// rejected-request path, which has already warned about the missing
/// backends.
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

  if (rawUserConfig is String ||
      rawUserConfig is List<Object?> ||
      rawUserConfig == false) {
    return _parseRuntimeList(rawUserConfig);
  }

  final root = _toStringMap(rawUserConfig);
  if (root == null) {
    return (
      runtimes: defaultNativeRuntimes,
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
    runtimes: defaultNativeRuntimes,
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

/// Filters [libraries] down to the files the hook should copy and report as
/// code assets. Non-configurable bundles pass through untouched.
///
/// Otherwise the backend set comes from [selectBackendsForBundle] over
/// [collectAvailableBackends], and a library survives when it is core, when
/// its inferred backend is selected, or when it infers no backend at all —
/// unrecognised vendor libraries are kept, not dropped. Two canonical-name
/// shapes are instead gated on a backend so they leave alongside the module
/// that needs them: `cudart64`, `cublas64` or `cublaslt64` with an optional
/// trailing digit run, itself optionally preceded by `_` or `-`, on `cuda`,
/// and anything starting `openblas` on `blas`.
///
/// `android-arm64` then gets a second pass over the per-CPU-variant
/// `ggml-cpu-*` modules. An explicit `cpu_variants` list wins, minus
/// unrecognised entries ([warn]); if nothing valid remains a [warn] fires and
/// resolution falls through to `cpu_profile`, which is `full` (all seven ARM
/// variants) by default, keeps only `android_armv8.0_1` when `compact`, and
/// warns and stays `full` when it is unrecognised or a non-string other than
/// `null`, which takes the default silently. A legacy
/// unsuffixed `ggml-cpu` module is always kept, and whenever the result holds
/// no CPU module — a bundle that shipped none included — [warn] fires and the
/// unfiltered backend selection is returned instead.
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

/// The `package:llamadart/<name>` code-asset name to report [library] under.
///
/// The primary `llamadart` library normally takes the bare package name, the
/// asset the generated FFI bindings resolve. On `windows-*` two independent
/// renames apply — `llama` takes `llamadart`, `llamadart` takes
/// `llamadart_wrapper` — because that bundle puts the core llama/ggml symbols
/// in `llama.dll` and only wrapper helpers in `llamadart.dll`. Every other
/// library uses its sanitised canonical name; names are not guaranteed unique,
/// so the caller de-duplicates before emitting assets.
String codeAssetNameForLibrary({
  required NativeBundleSpec spec,
  required NativeLibraryDescriptor library,
}) {
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
  // Distinguishes "the user asked for nothing" from "nothing was recognised",
  // which resolve to opposite selections below.
  var explicitNone = false;

  void addToken(String token) {
    final normalized = _normalizeRuntime(token);
    if (normalized == null) {
      if (token.trim().isNotEmpty) {
        invalid.add(token.trim());
      }
      return;
    }
    if (normalized == 'all' || normalized == 'both') {
      final expansion = normalized == 'all'
          ? allNativeRuntimes
          : defaultNativeRuntimes;
      for (final runtime in expansion) {
        if (!result.contains(runtime)) {
          result.add(runtime);
        }
      }
      return;
    }
    if (normalized == 'none') {
      result.clear();
      explicit.clear();
      explicitNone = true;
      return;
    }
    if (!result.contains(normalized)) {
      result.add(normalized);
    }
    explicit.add(normalized);
  }

  if (value == false) {
    addToken('none');
    return (runtimes: result, invalid: invalid, explicit: explicit);
  }

  if (value is String) {
    for (final token in value.split(',')) {
      addToken(token);
    }
    return (
      runtimes: result.isEmpty && !explicitNone
          ? defaultNativeRuntimes
          : result,
      invalid: invalid,
      explicit: explicit,
    );
  }

  if (value is List<Object?>) {
    for (final entry in value) {
      if (entry is String) {
        addToken(entry);
      } else if (entry == false) {
        addToken('none');
      } else if (entry != null) {
        invalid.add(entry.toString());
      }
    }
    return (
      runtimes: result.isEmpty && !explicitNone
          ? defaultNativeRuntimes
          : result,
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
    return normalized;
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
