import 'dart:async'
    show
        Completer,
        StreamSubscription,
        Timer,
        TimeoutException,
        Zone,
        runZoned,
        unawaited;
import 'dart:convert' show jsonDecode, utf8;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'package:llamadart/src/hook/apple_companion_constraint.dart';
import 'package:llamadart/src/hook/native_archive_digest.dart';
import 'package:llamadart/src/hook/native_bundle_config.dart';
import 'package:llamadart/src/hook/native_extraction_marker.dart';
import 'package:llamadart/src/hook/native_release_manifest.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:llamadart/src/hook/native_runtime_coexistence.dart';
import 'package:llamadart/src/hook/windows_file_version.dart';

const _nativeRepoSlug = 'leehack/llamadart-native';
const _stableDiffusionNativeRepoSlug = 'leehack/stable-diffusion-native';

const _packageName = 'llamadart';
const _llamaCppFlutterPackageName = 'llamadart_llama_cpp_flutter';
// Bind the maintained SwiftPM code, not just a tag declaration that arbitrary
// Swift could ignore. Only the release tag/checksum and CRLF are normalized.
// Changes to the companion manifest implementation require contract review.
const _appleCompanionManifestTemplateSha256 =
    '6f047f32a768fb3afd2eb4b0488768b591f254fe94e2bb472c5d70b34ff52a86';
const _liteRtLmFlutterPackageName = 'llamadart_litert_lm_flutter';
// The maintained LiteRT-LM companion manifest with its tag and checksums
// normalized. Only this manifest links the complete macOS runtime, so any other
// resolved companion keeps macOS LiteRT-LM on the hook cache.
const _liteRtLmCompanionManifestTemplateSha256 =
    '98061435e1b7e7726a96ae6191ff2041ad53d9d8fda1e8555f87464f4ab88b66';
// The template of the previous companion release. It is also macOS-complete, so
// a companion pinning an earlier rebuild gets that message, not a gap warning.
const _previousLiteRtLmCompanionManifestTemplateSha256 =
    '3d1654fa98dd747c4c9f0e642f3fa27d7657f7e8e25cdab4591e5eacd0de9b17';
const _stableDiffusionFlutterPackageName = 'llamadart_stable_diffusion_flutter';
const _stableDiffusionCompanionManifestTemplateSha256 =
    '829188afd63eec24b16259b05c0d884725818558fed30b41fae40fa39eeef66c';
const _thirdPartyDir = 'third_party';
const _binDir = 'bin';
const _dartToolDir = '.dart_tool';
const _cacheBaseDir = 'llamadart';
const _bundleCacheDir = 'native_bundles_v2';
const _reportDir = 'llamadart_bin';
const _allowLegacyLocalBundleEnv = 'LLAMADART_ALLOW_LEGACY_LOCAL_BUNDLES';
const _litertLmNativeReleaseBaseUrl =
    'https://github.com/leehack/litert-lm-native/releases/download/'
    '$liteRtLmReleaseTag';
const _litertLmCacheDir = 'litert_lm';
const _liteRtLmMacOsX64Unavailable =
    'LiteRT-LM is not available on macOS x86_64: litert-lm-native publishes '
    'arm64-only macOS runtimes (leehack/litert-lm-native#72).';
const _stableDiffusionNativeReleaseBaseUrl =
    'https://github.com/leehack/stable-diffusion-native/releases/download/'
    '$stableDiffusionReleaseTag';
const _stableDiffusionCacheDir = 'stable_diffusion';
const _stableDiffusionAssetName = 'stable_diffusion';
const _runtimeBundleDownloadMaxAttempts = 5;
const _runtimeBundleDownloadRequestTimeout = Duration(seconds: 60);
const _runtimeBundleDownloadTransferTimeout = Duration(minutes: 10);
const _runtimeBundleDownloadRetryBaseDelay = Duration(seconds: 3);
const _absentManifestRecheckInterval = Duration(days: 1);

typedef RuntimeBundleDownloadFallbackForTesting =
    Future<bool> Function({
      required String url,
      required File destination,
      required String description,
      required Logger log,
    });

final _litertLmBundles = Map.unmodifiable({
  for (final bundle in liteRtLmBundleSpecs) bundle.bundle: bundle,
});

final _stableDiffusionBundles = Map.unmodifiable({
  for (final bundle in stableDiffusionBundleSpecs) bundle.bundle: bundle,
});

const _dynamicLibraryExtensions = {'.so', '.dylib', '.dll'};
final _windowsCudartPattern = RegExp(r'^cudart64(?:[_-]?\d+)?\.dll$');
final _windowsCublasPattern = RegExp(r'^cublas64(?:[_-]?\d+)?\.dll$');
final _linuxVersionedSoPattern = RegExp(r'\.so\.\d+$');
final _githubRepoSegmentPattern = RegExp(r'^[A-Za-z0-9_.-]+$');

class _NativeBundleConfig {
  final String tag;
  final String repository;
  final Uri? localPath;

  const _NativeBundleConfig({
    required this.tag,
    required this.repository,
    required this.localPath,
  });

  bool get usesOverride =>
      tag != llamaCppTag || repository != _nativeRepoSlug || localPath != null;

  String get sourceLabel {
    final pathUri = localPath;
    if (pathUri != null) {
      return 'local path ${pathUri.toFilePath()}';
    }
    return '$repository@$tag';
  }
}

extension _LiteRtLmBundleSpecPaths on LiteRtLmBundleSpec {
  String get archiveName =>
      'litert-lm-native-runtime-$bundle-$liteRtLmReleaseTag.tar.gz';

  String get directoryName {
    final separator = bundle.indexOf('-');
    if (separator < 0) {
      return bundle;
    }
    return '${bundle.substring(0, separator)}/${bundle.substring(separator + 1)}';
  }

  String get releaseUrl => '$_litertLmNativeReleaseBaseUrl/$archiveName';

  String get sourcePrefix => directoryName;
}

extension _StableDiffusionBundleSpecPaths on StableDiffusionBundleSpec {
  String get archiveName =>
      'stable-diffusion-native-runtime-$bundle-$stableDiffusionReleaseTag.tar.gz';

  String get releaseUrl => '$_stableDiffusionNativeReleaseBaseUrl/$archiveName';
}

void main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  final log = Logger('${_packageName}_hook');

  await build(args, (input, output) async {
    CodeConfig? code;
    try {
      code = input.config.code;
    } catch (_) {
      // Non-native targets (web) may not expose code config.
    }

    if (code == null) {
      log.info('Hook: Skipping native asset build for non-native platform.');
      return;
    }

    final isIosSimulator =
        code.targetOS == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    final spec = resolveNativeBundleSpec(
      os: code.targetOS,
      arch: code.targetArchitecture,
      isIosSimulator: isIosSimulator,
    );

    if (spec == null) {
      log.warning(
        'Unsupported platform/arch: ${code.targetOS}-${code.targetArchitecture}.',
      );
      return;
    }

    log.info('Hook Start: ${spec.bundle}');

    final pkgRoot = input.packageRoot.toFilePath();
    final rawNativeRuntimeConfig =
        input.userDefines[nativeRuntimesUserDefineKey];
    final appleCompanions = _flutterAppleCompanions(
      input: input,
      code: code,
      output: output,
      log: log,
    );
    final appleSpmRuntimes = appleCompanions?.runtimes;
    final stableDiffusionCompanion = appleCompanions?.stableDiffusion ?? false;
    final liteRtLmMacOsCompanionWarning = appleCompanions?.liteRtLmMacOsWarning;
    final configuredRuntimes = selectNativeRuntimesForBundle(
      bundle: spec.bundle,
      rawUserConfig: rawNativeRuntimeConfig,
      warn: log.warning,
    );
    var selectedRuntimes = appleSpmRuntimes == null
        ? configuredRuntimes
        : [
            ...appleSpmRuntimes,
            if (configuredRuntimes.contains(nativeRuntimeStableDiffusion))
              nativeRuntimeStableDiffusion,
          ];
    if (stableDiffusionCompanion &&
        !selectedRuntimes.contains(nativeRuntimeStableDiffusion)) {
      selectedRuntimes = [...selectedRuntimes, nativeRuntimeStableDiffusion];
    }
    if (appleCompanions != null &&
        !stableDiffusionCompanion &&
        selectedRuntimes.contains(nativeRuntimeStableDiffusion) &&
        !nativeRuntimeExplicitlySelectedForBundle(
          bundle: spec.bundle,
          rawUserConfig: rawNativeRuntimeConfig,
          runtime: nativeRuntimeStableDiffusion,
        )) {
      // App Store Connect rejects the iOS framework Flutter wraps the
      // hook-bundled library in, and only the companion's XCFramework carries
      // the privacy manifest, so `all` alone must not start shipping it.
      selectedRuntimes = selectedRuntimes
          .where((runtime) => runtime != nativeRuntimeStableDiffusion)
          .toList(growable: false);
      const skipped =
          'stable_diffusion is only implied by `all` in '
          '$nativeRuntimesUserDefineKey, so this Flutter iOS/macOS build '
          'leaves the image runtime out: $_stableDiffusionFlutterPackageName '
          'is not a dependency. Add that package to link the runtime through '
          'Swift Package Manager, or name stable_diffusion to bundle it '
          'through the hook.';
      log.warning('$skipped (${spec.bundle})');
      // Hook log records stay in the hooks_runner stdout.txt; Flutter relays
      // hook stderr into the Xcode build, where a `warning:` line becomes an
      // Xcode build warning.
      stderr.writeln('warning: llamadart: $skipped');
    }
    final liteRtLmBundleSpec = _liteRtLmBundleSpecForCode(code);
    if (selectedRuntimes.contains(nativeRuntimeLiteRtLm) &&
        liteRtLmBundleSpec == null) {
      final macOsX64 =
          code.targetOS == OS.macOS &&
          code.targetArchitecture == Architecture.x64;
      // A universal macOS build runs this hook once per architecture. Failing
      // the x86_64 pass for a companion or platform-wide selection would break
      // every universal build, so only a macos-x86_64-scoped request fails.
      final explicitLiteRtLmSelection = macOsX64
          ? nativeRuntimeNamedForExactBundle(
              bundle: spec.bundle,
              rawUserConfig: rawNativeRuntimeConfig,
              runtime: nativeRuntimeLiteRtLm,
            )
          : appleSpmRuntimes?.contains(nativeRuntimeLiteRtLm) == true ||
                nativeRuntimeExplicitlySelectedForBundle(
                  bundle: spec.bundle,
                  rawUserConfig: rawNativeRuntimeConfig,
                  runtime: nativeRuntimeLiteRtLm,
                );
      if (explicitLiteRtLmSelection) {
        final iOSSimulatorX64 =
            code.targetOS == OS.iOS &&
            code.targetArchitecture == Architecture.x64;
        throw Exception(
          macOsX64
              ? '$_liteRtLmMacOsX64Unavailable Remove litert_lm from the '
                    'macos-x86_64 entry of $nativeRuntimesUserDefineKey, or '
                    'build the app for arm64 only.'
              : iOSSimulatorX64
              ? 'LiteRT-LM runtime is not available for ${spec.bundle}. '
                    'Exclude the x86_64 simulator from the app: add '
                    '`EXCLUDED_ARCHS[sdk=iphonesimulator*]=i386 x86_64` to '
                    'ios/Flutter/Debug.xcconfig and Release.xcconfig.'
              : 'LiteRT-LM runtime is not available for ${spec.bundle}.',
        );
      }
      selectedRuntimes = selectedRuntimes
          .where((runtime) => runtime != nativeRuntimeLiteRtLm)
          .toList(growable: false);
      if (macOsX64) {
        const skipped =
            '$_liteRtLmMacOsX64Unavailable The x86_64 slice of this build '
            'leaves LiteRT-LM out; selecting it there throws '
            'LlamaUnsupportedException.';
        log.warning(skipped);
        stderr.writeln('warning: llamadart: $skipped');
        if (selectedRuntimes.isEmpty) {
          return;
        }
      } else {
        log.warning(
          'LiteRT-LM runtime is not available for ${spec.bundle}; skipping it.',
        );
      }
    }
    final stableDiffusionBundleSpec =
        _stableDiffusionBundles[stableDiffusionBundleForNativeBundle(
          spec: spec,
          rawBackendConfig: input.userDefines[nativeBackendUserDefineKey],
          rawStableDiffusionBackendConfig:
              input.userDefines[stableDiffusionBackendUserDefineKey],
          warn: log.warning,
        )];
    if (selectedRuntimes.contains(nativeRuntimeStableDiffusion) &&
        stableDiffusionBundleSpec == null) {
      if (nativeRuntimeNamedForExactBundle(
        bundle: spec.bundle,
        rawUserConfig: rawNativeRuntimeConfig,
        runtime: nativeRuntimeStableDiffusion,
      )) {
        throw Exception(
          'stable_diffusion runtime is not available for ${spec.bundle}.',
        );
      }
      selectedRuntimes = selectedRuntimes
          .where((runtime) => runtime != nativeRuntimeStableDiffusion)
          .toList(growable: false);
      log.warning(
        'stable_diffusion runtime is not available for ${spec.bundle}; no '
        'stable_diffusion assets will be bundled for this target.',
      );
      if (selectedRuntimes.isEmpty) {
        return;
      }
    }
    final hadLiteRtLm = selectedRuntimes.contains(nativeRuntimeLiteRtLm);
    final consumerWarnings = <String>[];
    selectedRuntimes = selectConsumerNativeRuntimes(
      packageGraph: _resolvedPackageGraph(input),
      hookPackage: _packageName,
      selectedRuntimes: selectedRuntimes,
      explicitLiteRtLm: nativeRuntimeExplicitlySelectedForBundle(
        bundle: spec.bundle,
        rawUserConfig: rawNativeRuntimeConfig,
        runtime: nativeRuntimeLiteRtLm,
      ),
      isAppleTarget: _isAppleTarget(code.targetOS),
      dependency: output.dependencies.add,
      warn: consumerWarnings.add,
    );
    final droppedLiteRtLm =
        hadLiteRtLm && !selectedRuntimes.contains(nativeRuntimeLiteRtLm);
    for (final warning in consumerWarnings) {
      log.warning(warning);
      // A successful build shows no hook log records; hook stderr is relayed
      // like the stable_diffusion skip above.
      if (droppedLiteRtLm) stderr.writeln('warning: llamadart: $warning');
    }
    if (selectedRuntimes.isEmpty) {
      throw Exception(
        'No native runtimes selected for ${spec.bundle}. Configure '
        '$nativeRuntimesUserDefineKey with '
        '${supportedNativeRuntimes.join(', ')}, or all.',
      );
    }
    log.info('Selected native runtimes: ${selectedRuntimes.join(', ')}.');

    final appleSpmHandledRuntimes = await _emitAppleSpmAssetsIfEnabled(
      code: code,
      output: output,
      includeLlamaCpp: selectedRuntimes.contains(nativeRuntimeLlamaCpp),
      includeLiteRtLm: selectedRuntimes.contains(nativeRuntimeLiteRtLm),
      appleSpmRuntimes: appleSpmRuntimes,
      liteRtLmMacOsCompanionWarning: liteRtLmMacOsCompanionWarning,
      rawNativeRuntimeConfig: rawNativeRuntimeConfig,
      hasNativeSourceOverride: _hasNativeSourceOverride(input.userDefines),
      hasNativeBackendOverride:
          input.userDefines[nativeBackendUserDefineKey] != null,
      log: log,
    );
    if (selectedRuntimes.contains(nativeRuntimeStableDiffusion) &&
        appleCompanions != null) {
      if (stableDiffusionCompanion) {
        output.assets.code.add(
          CodeAsset(
            package: _packageName,
            name: _stableDiffusionAssetName,
            linkMode: LookupInProcess(),
          ),
        );
        log.info(
          'Reporting package:$_packageName/$_stableDiffusionAssetName as an '
          'in-process code asset for the SPM-linked stable_diffusion runtime '
          'from $_stableDiffusionFlutterPackageName.',
        );
        selectedRuntimes = selectedRuntimes
            .where((runtime) => runtime != nativeRuntimeStableDiffusion)
            .toList(growable: false);
      } else if (code.targetOS == OS.iOS) {
        // Flutter keeps hook log records in the hooks_runner stdout.txt, but
        // it relays hook stderr into the Xcode build, where a `warning:` line
        // becomes an Xcode build warning.
        stderr.writeln(
          'warning: llamadart bundles stable_diffusion through native assets. '
          'Flutter writes MinimumOSVersion 13.0 into the framework it wraps '
          'the library in, while the library requires iOS 16.4, so App Store '
          'Connect rejects the upload. Add $_stableDiffusionFlutterPackageName '
          "to the app's dependencies to link the SwiftPM framework instead.",
        );
      }
    }
    if (code.targetOS == OS.macOS &&
        liteRtLmBundleSpec != null &&
        (appleSpmHandledRuntimes?.contains(nativeRuntimeLiteRtLm) ?? false)) {
      // The app bundle loads the SwiftPM frameworks, but host `flutter test`
      // runs in flutter_tester, which has none and loads this cache instead.
      await _acquireLiteRtLmBundle(
        packageRoot: pkgRoot,
        bundleSpec: liteRtLmBundleSpec,
        log: log,
      );
    }
    if (appleSpmHandledRuntimes != null) {
      selectedRuntimes = selectedRuntimes
          .where((runtime) => !appleSpmHandledRuntimes.contains(runtime))
          .toList(growable: false);
    }
    if (selectedRuntimes.isEmpty) {
      return;
    }
    final includeLlamaCpp = selectedRuntimes.contains(nativeRuntimeLlamaCpp);
    final includeLiteRtLm = selectedRuntimes.contains(nativeRuntimeLiteRtLm);
    final includeStableDiffusion = selectedRuntimes.contains(
      nativeRuntimeStableDiffusion,
    );

    final nativeConfig = _resolveNativeBundleConfig(input.userDefines);
    log.info('Using native runtime source: ${nativeConfig.sourceLabel}');
    if (nativeConfig.usesOverride) {
      log.warning(
        'Native runtime overrides do not regenerate Dart FFI bindings. '
        'The selected binaries must stay ABI- and symbol-compatible with '
        '$_nativeRepoSlug@$llamaCppTag.',
      );
    }

    final reportDirPath = path.join(
      input.outputDirectory.toFilePath(),
      _reportDir,
    );
    final reportDir = Directory(reportDirPath);
    if (reportDir.existsSync()) {
      await reportDir.delete(recursive: true);
    }
    await reportDir.create(recursive: true);

    final emittedFilePaths = <String, String>{};
    final usedAssetNames = <String>{};

    final emittedLibraries = <NativeLibraryDescriptor>[];

    if (includeLlamaCpp) {
      final bundleDir = await _acquireBundleDirectory(
        packageRoot: pkgRoot,
        nativeConfig: nativeConfig,
        bundle: spec.bundle,
        log: log,
      );

      final libraryPaths = _collectDynamicLibraryPaths(bundleDir);
      if (libraryPaths.isEmpty) {
        throw Exception('No dynamic libraries found in ${bundleDir.path}.');
      }
      libraryPaths.addAll(
        await _acquireBackendSidecarLibraryPaths(
          packageRoot: pkgRoot,
          nativeConfig: nativeConfig,
          bundle: spec.bundle,
          coreLibraryPaths: libraryPaths,
          rawBackendConfig: input.userDefines[nativeBackendUserDefineKey],
          log: log,
        ),
      );

      final libraries = describeNativeLibraries(libraryPaths);
      if (!libraries.any((library) => library.isPrimary)) {
        throw Exception(
          'No primary libllamadart library found in ${bundleDir.path}.',
        );
      }

      final selectedLibraries = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: input.userDefines[nativeBackendUserDefineKey],
        warn: log.warning,
      );

      for (final library in selectedLibraries) {
        final emittedFileNames = _emittedFileNamesForLibrary(
          spec: spec,
          library: library,
          nativeConfig: nativeConfig,
        );

        for (final emittedFileName in emittedFileNames) {
          final loweredFileName = emittedFileName.toLowerCase();
          if (emittedFilePaths.containsKey(loweredFileName)) {
            if (emittedFileName == library.fileName) {
              log.warning(
                'Duplicate library filename detected, skipping: '
                '${library.fileName}',
              );
            }
            continue;
          }

          final destinationPath = path.join(reportDirPath, emittedFileName);
          emittedFilePaths[loweredFileName] = destinationPath;
          await File(library.filePath).copy(destinationPath);
          emittedLibraries.add(describeNativeLibrary(destinationPath));
        }
      }
    }

    for (final emittedLibrary in emittedLibraries) {
      final baseAssetName = codeAssetNameForLibrary(
        spec: spec,
        library: emittedLibrary,
      );
      final assetName = _dedupeAssetName(baseAssetName, usedAssetNames);

      output.assets.code.add(
        CodeAsset(
          package: _packageName,
          name: assetName,
          linkMode: DynamicLoadingBundled(),
          file: Uri.file(path.absolute(emittedLibrary.filePath)),
        ),
      );

      log.info(
        'Reporting native library `${emittedLibrary.fileName}` as code asset '
        '`package:$_packageName/$assetName`.',
      );
    }

    if (includeLiteRtLm) {
      await _emitLiteRtLmAssets(
        code: code,
        output: output,
        packageRoot: pkgRoot,
        reportDirPath: reportDirPath,
        usedAssetNames: usedAssetNames,
        llamaCppFilePaths: emittedFilePaths,
        log: log,
      );
    }

    if (includeStableDiffusion) {
      await _emitStableDiffusionAssets(
        bundleSpec: stableDiffusionBundleSpec!,
        output: output,
        packageRoot: pkgRoot,
        reportDirPath: reportDirPath,
        usedAssetNames: usedAssetNames,
        log: log,
      );
    }

    if (includeLlamaCpp && !usedAssetNames.contains(_packageName)) {
      throw Exception(
        'Primary asset package:$_packageName/$_packageName was not emitted.',
      );
    }
  });
}

Future<List<String>?> _emitAppleSpmAssetsIfEnabled({
  required CodeConfig code,
  required BuildOutputBuilder output,
  required bool includeLlamaCpp,
  required bool includeLiteRtLm,
  required List<String>? appleSpmRuntimes,
  required String? liteRtLmMacOsCompanionWarning,
  required Object? rawNativeRuntimeConfig,
  required bool hasNativeSourceOverride,
  required bool hasNativeBackendOverride,
  required Logger log,
}) async {
  if (appleSpmRuntimes == null) {
    return null;
  }

  log.info(
    'Detected Flutter Apple companion packages for native runtimes: '
    '${appleSpmRuntimes.join(', ')}.',
  );
  if (rawNativeRuntimeConfig != null) {
    log.warning(
      'Flutter Apple builds select native runtimes from companion package '
      'dependencies ($_llamaCppFlutterPackageName and '
      '$_liteRtLmFlutterPackageName). Ignoring the llama_cpp and litert_lm '
      'selection in $nativeRuntimesUserDefineKey for this Apple build; '
      'stable_diffusion still follows that selection unless '
      '$_stableDiffusionFlutterPackageName is a dependency.',
    );
  }
  if (hasNativeSourceOverride) {
    log.warning(
      'Flutter Apple companion packages use Package.swift binary target pins. '
      '$nativeTagUserDefineKey, $nativeRepositoryUserDefineKey, and '
      '$nativePathUserDefineKey do not change their SPM binaries.',
    );
  }
  if (hasNativeBackendOverride) {
    log.warning(
      'Flutter Apple companion packages ignore $nativeBackendUserDefineKey; '
      'their frameworks include packaged native modules.',
    );
  }
  final handledRuntimes = <String>[];
  if (includeLlamaCpp) {
    output.assets.code.add(
      CodeAsset(
        package: _packageName,
        name: _packageName,
        linkMode: LookupInProcess(),
      ),
    );
    log.info(
      'Reporting package:$_packageName/$_packageName as an in-process code '
      'asset for the SPM-linked llama.cpp runtime.',
    );
    handledRuntimes.add(nativeRuntimeLlamaCpp);
  }
  if (includeLiteRtLm) {
    if (code.targetOS == OS.macOS && liteRtLmMacOsCompanionWarning != null) {
      log.warning(liteRtLmMacOsCompanionWarning);
      stderr.writeln('warning: llamadart: $liteRtLmMacOsCompanionWarning');
    } else {
      log.info(
        'LiteRT-LM will resolve symbols from the SPM-linked process image.',
      );
      handledRuntimes.add(nativeRuntimeLiteRtLm);
    }
  }
  return handledRuntimes;
}

bool _hasNativeSourceOverride(HookInputUserDefines userDefines) {
  return userDefines[nativeTagUserDefineKey] != null ||
      userDefines[nativeRepositoryUserDefineKey] != null ||
      userDefines[nativePathUserDefineKey] != null;
}

bool _isAppleTarget(OS os) => os == OS.iOS || os == OS.macOS;

/// Companion packages a Flutter Apple app depends on. [runtimes] holds the
/// llama_cpp and litert_lm families they provide, or `null` when neither
/// companion is a dependency and those families come from the hook.
/// [stableDiffusion] is decided on its own, so adding only the
/// stable_diffusion companion never moves llama_cpp or litert_lm off the hook.
/// [liteRtLmMacOsWarning] says how a macOS LiteRT-LM companion does not match
/// this core, or is `null` when it does or the build is not macOS LiteRT-LM.
typedef _AppleCompanions = ({
  List<String>? runtimes,
  bool stableDiffusion,
  String? liteRtLmMacOsWarning,
});

/// The companions of a Flutter iOS/macOS app build, or `null` for every other
/// build, which bundles all runtimes through the hook.
_AppleCompanions? _flutterAppleCompanions({
  required BuildInput input,
  required CodeConfig code,
  required BuildOutputBuilder output,
  required Logger log,
}) {
  if (!_isAppleTarget(code.targetOS)) {
    return null;
  }

  final consumerRoot = _consumerPackageRoot(input);
  if (consumerRoot == null) {
    log.info(
      'Using bundled Apple native assets; could not resolve the invoking '
      'package root.',
    );
    return null;
  }

  final packageRoot = Directory.fromUri(input.packageRoot);
  if (_sameDirectory(consumerRoot, packageRoot)) {
    log.info('Using bundled Apple native assets for package-root builds.');
    return null;
  }

  final pubspec = File(path.join(consumerRoot.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    log.info(
      'Using bundled Apple native assets; no pubspec.yaml found at '
      '${pubspec.path}.',
    );
    return null;
  }

  final pubspecSource = pubspec.readAsStringSync();
  output.dependencies.add(pubspec.uri);
  var consumer = 'Flutter package ${consumerRoot.path}';
  final Set<String> dependencies;
  if (_pubspecDeclaresFlutter(pubspecSource)) {
    dependencies = _flutterAppDependencies(consumerRoot, pubspecSource, output);
  } else if (_pubspecDeclaresWorkspace(pubspecSource)) {
    final app = _workspaceFlutterApp(
      consumerRoot,
      output,
      log,
      ios: code.targetOS == OS.iOS,
    );
    if (app == null) return null;
    consumer = 'Flutter workspace member ${app.name} of ${consumerRoot.path}';
    dependencies = app.dependencies;
  } else {
    log.info(
      'Using bundled Apple native assets for non-Flutter package '
      '${consumerRoot.path}.',
    );
    return null;
  }

  final runtimes = <String>[];
  String? liteRtLmMacOsWarning;
  if (dependencies.contains(_llamaCppFlutterPackageName)) {
    _validateAppleCompanion(
      _llamaCppCompanion,
      consumerRoot,
      packageRoot,
      output,
      log,
    );
    runtimes.add(nativeRuntimeLlamaCpp);
  }
  if (dependencies.contains(_liteRtLmFlutterPackageName)) {
    runtimes.add(nativeRuntimeLiteRtLm);
    if (code.targetOS == OS.macOS) {
      liteRtLmMacOsWarning = _liteRtLmMacOsCompanionWarning(
        consumerRoot,
        output,
      );
    }
  }
  final stableDiffusion = dependencies.contains(
    _stableDiffusionFlutterPackageName,
  );
  if (stableDiffusion) {
    _validateAppleCompanion(
      _stableDiffusionCompanion,
      consumerRoot,
      packageRoot,
      output,
      log,
    );
  }
  if (runtimes.isEmpty) {
    log.info(
      'Using bundled Apple native assets for llama_cpp and litert_lm in '
      '$consumer; neither '
      '$_llamaCppFlutterPackageName nor $_liteRtLmFlutterPackageName is a '
      'dependency.',
    );
  }
  return (
    runtimes: runtimes.isEmpty ? null : runtimes,
    stableDiffusion: stableDiffusion,
    liteRtLmMacOsWarning: liteRtLmMacOsWarning,
  );
}

/// The Flutter app of the pub workspace rooted at [workspaceRoot] with every
/// package its regular dependencies reach, directly or not, or `null` to keep
/// the bundled Apple native assets. Flutter links each plugin among those
/// packages, so they choose the Apple companions.
///
/// pub passes the workspace root pubspec, which holds the user-defines, and
/// the build does not tell the hook which member it builds, so the hook reads
/// `.dart_tool/package_graph.json`. A member builds llamadart into an app when
/// its dependencies or dev dependencies reach [_packageName] and no other
/// member lists it under regular dependencies. Every member shares this hook
/// output, so when those members do not all reach the same companions, or mix
/// Flutter apps with other packages, the build warns and keeps the bundled
/// assets.
///
/// Only a Flutter build targets iOS, so for [ios] non-Flutter members are not
/// considered; `flutter build ios` also hides hook warnings, which would leave
/// such a member's fallback silent. Debug and profile Flutter builds include
/// the dev dependencies of the app they build, so those count on every
/// target.
({String name, Set<String> dependencies})? _workspaceFlutterApp(
  Directory workspaceRoot,
  BuildOutputBuilder output,
  Logger log, {
  required bool ios,
}) {
  final dartTool = path.join(workspaceRoot.path, _dartToolDir);
  final graphFile = File(path.join(dartTool, 'package_graph.json'));
  final configFile = File(path.join(dartTool, 'package_config.json'));
  void warn(String message) {
    log.warning(message);
    stderr.writeln('warning: llamadart: $message');
  }

  const skipped =
      'so llamadart bundles its own Apple native assets and skips Apple '
      'companion validation and Swift Package Manager linking.';
  output.dependencies.addAll([graphFile.uri, configFile.uri]);
  final List<String> members;
  final Map<String, List<String>> dependencies;
  final Map<String, List<String>> devDependencies;
  final Map<String, Uri> roots;
  try {
    final graph = _decodePackageGraph(jsonDecode(graphFile.readAsStringSync()));
    final config = jsonDecode(configFile.readAsStringSync());
    members = [...graph.roots]..sort();
    dependencies = graph.dependencies;
    devDependencies = graph.devDependencies;
    if (config case {'packages': final List<Object?> entries}) {
      roots = {
        for (final entry in entries)
          if (entry case {
            'name': final String name,
            'rootUri': final String rootUri,
          })
            name: configFile.uri.resolve(
              rootUri.endsWith('/') ? rootUri : '$rootUri/',
            ),
      };
    } else {
      throw const FormatException();
    }
  } on FileSystemException {
    warn(
      'Cannot find the Flutter app in the pub workspace at '
      '${workspaceRoot.path}: ${graphFile.path} or ${configFile.path} could '
      'not be read, $skipped Run flutter pub get in the workspace and '
      'rebuild.',
    );
    return null;
  } on FormatException {
    warn(
      'Cannot find the Flutter app in the pub workspace at '
      '${workspaceRoot.path}: ${graphFile.path} or ${configFile.path} is '
      'malformed, $skipped Run flutter pub get in the workspace and rebuild.',
    );
    return null;
  }

  final libraries = {
    for (final member in members) ...?dependencies[member],
  }.intersection(members.toSet());
  bool reachesCore(String member) => _reachedThrough(dependencies, [
    member,
    ...?devDependencies[member],
  ]).contains(_packageName);

  const companions = {
    _llamaCppFlutterPackageName,
    _liteRtLmFlutterPackageName,
    _stableDiffusionFlutterPackageName,
  };
  final apps = <({String name, Set<String>? dependencies, String setup})>[];
  for (final member in members) {
    if (libraries.contains(member) || !reachesCore(member)) continue;
    final root = roots[member];
    if (root == null || root.scheme != 'file') {
      warn(
        'Cannot find the Flutter app in the pub workspace at '
        '${workspaceRoot.path}: ${configFile.path} has no local root for '
        'workspace member $member, $skipped Run flutter pub get in the '
        'workspace and rebuild.',
      );
      return null;
    }
    final pubspec = File.fromUri(root.resolve('pubspec.yaml'));
    output.dependencies.add(pubspec.uri);
    final String source;
    try {
      source = pubspec.readAsStringSync();
    } on FileSystemException {
      warn(
        'Cannot find the Flutter app in the pub workspace at '
        '${workspaceRoot.path}: ${pubspec.path} could not be read, $skipped '
        'Run flutter pub get in the workspace and rebuild.',
      );
      return null;
    }
    if (!_pubspecDeclaresFlutter(source)) {
      if (!ios) {
        apps.add((name: member, dependencies: null, setup: 'not Flutter'));
      }
      continue;
    }
    final reached = _reachedThrough(dependencies, {
      ..._pubspecDependencyNames(source),
      ...?dependencies[member],
    });
    final selected = companions.where(reached.contains).toList()..sort();
    apps.add((
      name: member,
      dependencies: reached,
      setup: selected.isEmpty
          ? 'Flutter, no Apple companion'
          : 'Flutter, ${selected.join(', ')}',
    ));
  }

  if (apps.map((app) => app.setup).toSet().length > 1) {
    warn(
      'Cannot tell which member of the pub workspace at '
      '${workspaceRoot.path} this Apple build is for: '
      '${apps.map((app) => '${app.name} (${app.setup})').join('; ')}. Every '
      'member shares this hook output, $skipped Declare the same Apple '
      'companions in every Flutter app that depends on $_packageName, or move '
      'apps with different companions into separate workspaces.',
    );
    return null;
  }
  final app = apps.firstOrNull;
  final appDependencies = app?.dependencies;
  if (app == null || appDependencies == null) {
    log.info(
      'Using bundled Apple native assets; no Flutter app in the pub workspace '
      'at ${workspaceRoot.path} depends on $_packageName.',
    );
    return null;
  }
  return (name: app.name, dependencies: appDependencies);
}

/// Every package the regular dependencies of the Flutter app with pubspec
/// [source] at [appRoot] reach, as Flutter links each plugin among them.
/// Without a readable `.dart_tool/package_graph.json`, which
/// [selectConsumerNativeRuntimes] warns about, only the direct dependencies
/// count.
Set<String> _flutterAppDependencies(
  Directory appRoot,
  String source,
  BuildOutputBuilder output,
) {
  final direct = _pubspecDependencyNames(source);
  final graphFile = File(
    path.join(appRoot.path, _dartToolDir, 'package_graph.json'),
  );
  output.dependencies.add(graphFile.uri);
  try {
    final graph = _decodePackageGraph(jsonDecode(graphFile.readAsStringSync()));
    return _reachedThrough(graph.dependencies, direct);
  } on FileSystemException {
    return direct;
  } on FormatException {
    return direct;
  }
}

/// The roots of the decoded `package_graph.json` [graph] and each package's
/// regular and dev dependencies. Throws [FormatException] on another shape.
({
  List<String> roots,
  Map<String, List<String>> dependencies,
  Map<String, List<String>> devDependencies,
})
_decodePackageGraph(Object? graph) {
  if (graph case {
    'roots': final List<Object?> roots,
    'packages': final List<Object?> packages,
  } when roots.every((root) => root is String)) {
    final dependencies = <String, List<String>>{};
    final devDependencies = <String, List<String>>{};
    for (final package in packages) {
      if (package case {
        'name': final String name,
        'dependencies': final List<Object?> direct,
      }) {
        dependencies[name] = direct.whereType<String>().toList();
        if (package['devDependencies'] case final List<Object?> dev) {
          devDependencies[name] = dev.whereType<String>().toList();
        }
      } else {
        throw const FormatException();
      }
    }
    return (
      roots: roots.cast<String>(),
      dependencies: dependencies,
      devDependencies: devDependencies,
    );
  }
  throw const FormatException();
}

/// [packages] with every package their regular [dependencies] reach.
Set<String> _reachedThrough(
  Map<String, List<String>> dependencies,
  Iterable<String> packages,
) {
  final reached = <String>{};
  final pending = [...packages];
  while (pending.isNotEmpty) {
    final name = pending.removeLast();
    if (reached.add(name)) pending.addAll(dependencies[name] ?? const []);
  }
  return reached;
}

/// What a resolved Flutter Apple companion must match before the hook trusts
/// its SwiftPM framework: the companion pins [nativeRepository]@[nativeTag]
/// through `let [tagVariable]` in the maintained manifest template.
/// [compatibleTags] maps earlier tags accepted with a warning to what their
/// frameworks lack; [artifactChecksums] binds each of them, and [nativeTag]
/// when listed, to its exact XCFramework checksum. [companionVersion] is the
/// first companion release pinning
/// [nativeTag], when the core records it; [appleCompanionConstraint] decides
/// whether a build error names it.
typedef _AppleCompanionContract = ({
  String label,
  String packageName,
  String tagVariable,
  String nativeRepository,
  String nativeTag,
  Map<String, String> compatibleTags,
  Map<String, String> artifactChecksums,
  String? companionVersion,
  String templateSha256,
});

const _AppleCompanionContract _llamaCppCompanion = (
  label: 'llama.cpp',
  packageName: _llamaCppFlutterPackageName,
  tagVariable: 'llamaCppTag',
  nativeRepository: _nativeRepoSlug,
  nativeTag: llamaCppTag,
  compatibleTags: llamaCppCompatibleAppleCompanionTags,
  artifactChecksums: llamaCppCompatibleAppleCompanionChecksums,
  companionVersion: llamaCppAppleCompanionVersion,
  templateSha256: _appleCompanionManifestTemplateSha256,
);

const _AppleCompanionContract _stableDiffusionCompanion = (
  label: 'stable_diffusion',
  packageName: _stableDiffusionFlutterPackageName,
  tagVariable: 'stableDiffusionTag',
  nativeRepository: _stableDiffusionNativeRepoSlug,
  nativeTag: stableDiffusionReleaseTag,
  compatibleTags: stableDiffusionCompatibleAppleCompanionTags,
  artifactChecksums: stableDiffusionAppleCompanionChecksums,
  companionVersion: stableDiffusionAppleCompanionVersion,
  templateSha256: _stableDiffusionCompanionManifestTemplateSha256,
);

void _validateAppleCompanion(
  _AppleCompanionContract contract,
  Directory consumerRoot,
  Directory packageRoot,
  BuildOutputBuilder output,
  Logger log,
) {
  final coreVersion = _corePackageVersion(packageRoot);
  final nativePin = '${contract.nativeRepository}@${contract.nativeTag}';
  final requiredCompanion =
      appleCompanionRequirement(
        packageName: contract.packageName,
        coreVersion: coreVersion,
        nativePin: nativePin,
        firstPinningRelease: contract.companionVersion,
      ) ??
      'Resolve ${contract.packageName} with a Package.swift pin matching '
          '$nativePin and rerun flutter pub get.';
  Never reject(String reason) => throw StateError(
    'Incompatible Apple ${contract.label} companion: $reason '
    '$requiredCompanion '
    'Upgrade the core and companion together to a matching released pair; '
    'native tag/path overrides do not replace SPM frameworks. '
    'No in-process native asset was emitted.',
  );

  try {
    final companionRoot = _resolvedCompanionRoot(
      consumerRoot,
      contract.packageName,
      contract.label,
      output,
      reject,
    );
    final pubspec = File(path.join(companionRoot.path, 'pubspec.yaml'));
    final manifest = File(
      path.join(
        companionRoot.path,
        'darwin',
        contract.packageName,
        'Package.swift',
      ),
    );
    output.dependencies.addAll([pubspec.uri, manifest.uri]);
    if (!pubspec.existsSync() || !manifest.existsSync()) {
      reject('Resolved companion package metadata is missing.');
    }
    final metadata = loadYaml(pubspec.readAsStringSync());
    if (metadata is! Map ||
        metadata['name'] != contract.packageName ||
        metadata['version'] is! String ||
        !RegExp(
          r'^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$',
        ).hasMatch(metadata['version'] as String)) {
      reject('Resolved companion identity is malformed.');
    }
    final source = manifest.readAsStringSync();
    final tagVariable = contract.tagVariable;
    final pins = RegExp(
      '^let $tagVariable = "([^"\\r\\n]+)"\\s*\$',
      multiLine: true,
    ).allMatches(source).toList();
    final pinnedTag = pins.length == 1 ? pins.single.group(1)! : null;
    if (pinnedTag == null ||
        (pinnedTag != contract.nativeTag &&
            !contract.compatibleTags.containsKey(pinnedTag))) {
      reject(
        'Resolved companion ${metadata['version']} does not uniquely pin '
        'the required native runtime ${contract.nativeTag}.',
      );
    }
    final normalizedSource = source.replaceAll('\r\n', '\n');
    final checksum = RegExp(r'checksum: "[0-9a-f]{64}"');
    final expectedChecksum = contract.artifactChecksums[pinnedTag];
    // A compatible earlier tag is accepted only for its qualified artifact;
    // the pinned tag is bound too when the contract records its checksum.
    final checksumRequired =
        contract.compatibleTags.containsKey(pinnedTag) ||
        contract.artifactChecksums.containsKey(contract.nativeTag);
    if (checksumRequired &&
        (expectedChecksum == null ||
            checksum.firstMatch(normalizedSource)?.group(0) !=
                'checksum: "$expectedChecksum"')) {
      reject(
        'Companion XCFramework checksum does not match the qualified '
        'published artifact for $pinnedTag.',
      );
    }
    final template = normalizedSource
        .replaceFirst(
          RegExp('^let $tagVariable = "[^"\\r\\n]+"\$', multiLine: true),
          'let $tagVariable = "PIN"',
        )
        .replaceFirst(checksum, 'checksum: "CHECKSUM"');
    if (checksum.allMatches(normalizedSource).length != 1 ||
        sha256.convert(utf8.encode(template)).toString() !=
            contract.templateSha256) {
      reject('Companion SwiftPM target does not use the supported native pin.');
    }
    final artifacts = Directory(path.join(manifest.parent.path, 'Artifacts'));
    // The supported manifest can prefer local binaries over its remote pin.
    // Such binaries have no verified ABI contract and must not inherit trust
    // from the tag string. Track the existing parent: directory dependencies
    // hash child names, so adding/removing Artifacts invalidates a cached
    // success without making Flutter enumerate a nonexistent directory.
    output.dependencies.add(manifest.parent.uri);
    if (artifacts.existsSync()) {
      reject(
        'Local Artifacts overrides cannot establish framework ABI '
        'compatibility; remove them and use the pinned framework.',
      );
    }
    final missing = contract.compatibleTags[pinnedTag];
    if (missing != null) {
      final constraint = appleCompanionConstraint(
        coreVersion,
        firstPinningRelease: contract.companionVersion,
      );
      final next = constraint == null
          ? 'Upgrade ${contract.packageName} to a release pinning'
          : 'Depend on `${contract.packageName}: $constraint` to link';
      final upgrade =
          'Resolved ${contract.packageName} ${metadata['version']} pins '
          '${contract.nativeRepository}@$pinnedTag, an earlier ${contract.label} '
          'runtime than ${contract.nativeTag} that this core still supports, '
          'so this build links it. Its frameworks lack $missing. $next '
          '${contract.nativeTag}.';
      log.warning(upgrade);
      stderr.writeln('warning: llamadart: $upgrade');
    }
  } on FileSystemException {
    reject('Unable to read resolved companion metadata.');
  } on FormatException {
    reject('Resolved companion metadata is malformed.');
  }
}

/// This core's pubspec `version`, which decides the companion constraint a
/// build error or warning names, or `null` when it cannot be read.
///
/// It is not a build dependency: a cached build emits no error or warning.
String? _corePackageVersion(Directory packageRoot) {
  final pubspec = File(path.join(packageRoot.path, 'pubspec.yaml'));
  try {
    final metadata = loadYaml(pubspec.readAsStringSync());
    final version = metadata is Map ? metadata['version'] : null;
    return version is String ? version : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// The root of the one [packageName] the consumer's nearest
/// `.dart_tool/package_config.json` resolves; [reject] reports why there is
/// none.
Directory _resolvedCompanionRoot(
  Directory consumerRoot,
  String packageName,
  String label,
  BuildOutputBuilder output,
  Never Function(String reason) reject,
) {
  var directory = consumerRoot;
  File? configuration;
  while (true) {
    final candidate = File(
      path.join(directory.path, _dartToolDir, 'package_config.json'),
    );
    if (candidate.existsSync()) {
      configuration = candidate;
      break;
    }
    final parent = directory.parent;
    if (_sameDirectory(parent, directory)) break;
    directory = parent;
  }
  if (configuration == null) {
    reject('Resolved package configuration missing.');
  }
  output.dependencies.add(configuration.uri);
  final config = jsonDecode(configuration.readAsStringSync());
  if (config is! Map ||
      config['configVersion'] != 2 ||
      config['packages'] is! List) {
    reject('Resolved package configuration is malformed.');
  }
  final entries = config['packages'] as List;
  if (entries.any((entry) => entry is! Map)) {
    reject('Resolved package configuration contains malformed entries.');
  }
  final companions = entries
      .where((entry) => (entry as Map)['name'] == packageName)
      .toList();
  if (companions.length != 1) {
    reject('Expected exactly one resolved $label companion.');
  }
  final root = (companions.single as Map)['rootUri'];
  if (root is! String || root.isEmpty) reject('Companion root URI missing.');
  final uri = configuration.uri.resolve(root);
  if (uri.scheme != 'file' || uri.hasQuery || uri.hasFragment) {
    reject('Companion root must be a local package directory.');
  }
  return Directory.fromUri(uri);
}

/// The build warning for a resolved LiteRT-LM companion that does not match
/// this core on macOS, or `null` when its manifest is the maintained one
/// pinning [liteRtLmReleaseTag].
String? _liteRtLmMacOsCompanionWarning(
  Directory consumerRoot,
  BuildOutputBuilder output,
) {
  Never gap(String reason) => throw _CompanionGap(reason);
  try {
    final companionRoot = _resolvedCompanionRoot(
      consumerRoot,
      _liteRtLmFlutterPackageName,
      'LiteRT-LM',
      output,
      gap,
    );
    final manifest = File(
      path.join(
        companionRoot.path,
        'darwin',
        _liteRtLmFlutterPackageName,
        'Package.swift',
      ),
    );
    output.dependencies.add(manifest.uri);
    if (!manifest.existsSync()) gap('Package.swift is missing');
    final source = manifest.readAsStringSync().replaceAll('\r\n', '\n');
    final pinPattern = RegExp(
      r'^let liteRtLmTag = "([^"\n]+)"$',
      multiLine: true,
    );
    final pins = pinPattern.allMatches(source).toList();
    if (pins.length != 1) {
      gap('it does not pin leehack/litert-lm-native@$liteRtLmReleaseTag');
    }
    final template = source
        .replaceFirst(pinPattern, 'let liteRtLmTag = "PIN"')
        .replaceAll(
          RegExp(r'checksum: "[0-9a-f]{64}"'),
          'checksum: "CHECKSUM"',
        );
    final pin = pins.single.group(1)!;
    final templateSha256 = sha256.convert(utf8.encode(template)).toString();
    if (templateSha256 != _liteRtLmCompanionManifestTemplateSha256 &&
        !(templateSha256 == _previousLiteRtLmCompanionManifestTemplateSha256 &&
            _isEarlierLiteRtLmRebuild(pin))) {
      gap('its Package.swift is not the macOS-complete manifest');
    }
    if (pin == liteRtLmReleaseTag) return null;
    if (_isEarlierLiteRtLmRebuild(pin)) {
      return 'The resolved $_liteRtLmFlutterPackageName pins '
          'leehack/litert-lm-native@$pin, an earlier build of this core\'s '
          'LiteRT-LM release $liteRtLmReleaseTag. It still embeds its '
          'complete macOS LiteRT-LM runtime, which the app loads from its '
          'bundle. Upgrade $_liteRtLmFlutterPackageName to the release '
          'pinning $liteRtLmReleaseTag.';
    }
    return 'The resolved $_liteRtLmFlutterPackageName pins '
        'leehack/litert-lm-native@$pin rather than this core\'s '
        '$liteRtLmReleaseTag, so LiteRT-LM stays in the hook cache. Upgrade '
        '$_liteRtLmFlutterPackageName and $_packageName together to a '
        'matching released pair.';
  } on _CompanionGap catch (error) {
    return _liteRtLmIncompleteCompanionWarning(error.reason);
  } on FileSystemException {
    return _liteRtLmIncompleteCompanionWarning(
      'its metadata could not be read',
    );
  } on FormatException {
    return _liteRtLmIncompleteCompanionWarning(
      'the resolved package configuration is malformed',
    );
  }
}

String _liteRtLmIncompleteCompanionWarning(String reason) =>
    'The resolved $_liteRtLmFlutterPackageName does not link the complete '
    'macOS LiteRT-LM runtime ($reason), so LiteRT-LM stays in the hook cache, '
    'which a sandboxed or relocated app cannot load. Upgrade '
    '$_liteRtLmFlutterPackageName together with $_packageName.';

/// Whether [pin] is an earlier build of this core's upstream LiteRT-LM
/// release: the same `vMAJOR.MINOR.PATCH` prefix as [liteRtLmReleaseTag]
/// with a lower wrapper rebuild counter, which a bare `vMAJOR.MINOR.PATCH`
/// has as 0. The native release manifest binds that prefix to one upstream
/// commit, so such a companion embeds the same LiteRT-LM release.
bool _isEarlierLiteRtLmRebuild(String pin) {
  final tagPattern = RegExp(r'^(v\d+\.\d+\.\d+)(?:-([1-9]\d*))?$');
  final core = tagPattern.firstMatch(liteRtLmReleaseTag);
  final candidate = tagPattern.firstMatch(pin);
  if (core == null || candidate == null || candidate[1] != core[1]) {
    return false;
  }
  int? rebuild(RegExpMatch tag) => int.tryParse(tag[2] ?? '0');
  final candidateRebuild = rebuild(candidate);
  final coreRebuild = rebuild(core);
  return candidateRebuild != null &&
      coreRebuild != null &&
      candidateRebuild < coreRebuild;
}

class _CompanionGap implements Exception {
  _CompanionGap(this.reason);

  final String reason;
}

/// The resolved graph of every package sharing this hook's output: the hook
/// runner keeps that output in the `.dart_tool/` pub resolved into, which a
/// pub workspace has once, at its root.
File? _resolvedPackageGraph(BuildInput input) {
  final root = _consumerPackageRootFromOutput(input);
  return root == null
      ? null
      : File(path.join(root.path, _dartToolDir, 'package_graph.json'));
}

Directory? _consumerPackageRoot(BuildInput input) {
  final fromUserDefines = _consumerPackageRootFromUserDefines(input);
  if (fromUserDefines != null) {
    return fromUserDefines;
  }

  return _consumerPackageRootFromOutput(input);
}

Directory? _consumerPackageRootFromOutput(BuildInput input) {
  final sharedOutputPath = path.normalize(
    input.outputDirectoryShared.toFilePath(),
  );
  final segments = path.split(sharedOutputPath);
  final dartToolIndex = segments.lastIndexOf(_dartToolDir);
  if (dartToolIndex <= 0) {
    return null;
  }
  return Directory(path.joinAll(segments.sublist(0, dartToolIndex)));
}

Directory? _consumerPackageRootFromUserDefines(BuildInput input) {
  final userDefines = input.json['user_defines'];
  if (userDefines is! Map) {
    return null;
  }
  final workspacePubspec = userDefines['workspace_pubspec'];
  if (workspacePubspec is! Map) {
    return null;
  }
  final basePathRaw = workspacePubspec['base_path'];
  if (basePathRaw is! String || basePathRaw.trim().isEmpty) {
    return null;
  }

  final basePath = _uriOrPathToFilePath(basePathRaw);
  if (basePath == null) {
    return null;
  }

  final type = FileSystemEntity.typeSync(basePath);
  return switch (type) {
    FileSystemEntityType.directory => Directory(basePath),
    FileSystemEntityType.file => File(basePath).parent,
    _ => File(basePath).parent,
  };
}

String? _uriOrPathToFilePath(String value) {
  if (_looksLikeWindowsPath(value)) {
    return value;
  }

  final uri = Uri.tryParse(value);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  if (uri != null && uri.scheme.isNotEmpty) {
    return null;
  }
  return value;
}

bool _looksLikeWindowsPath(String value) {
  if (value.startsWith(r'\\')) {
    return true;
  }
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
}

bool _sameDirectory(Directory a, Directory b) {
  final left = path.normalize(path.absolute(a.path));
  final right = path.normalize(path.absolute(b.path));
  return left == right;
}

bool _pubspecDeclaresFlutter(String source) {
  final pubspec = _readConsumerPubspec(source);
  if (pubspec is! Map) return false;
  final dependencies = pubspec['dependencies'];
  if (dependencies is! Map) return false;
  final flutter = dependencies['flutter'];
  return flutter is Map && flutter['sdk'] == 'flutter';
}

bool _pubspecDeclaresWorkspace(String source) {
  final pubspec = _readConsumerPubspec(source);
  return pubspec is Map && pubspec['workspace'] is List;
}

Set<String> _pubspecDependencyNames(String source) {
  final pubspec = _readConsumerPubspec(source);
  if (pubspec is! Map || pubspec['dependencies'] is! Map) return {};
  return (pubspec['dependencies'] as Map).keys.whereType<String>().toSet();
}

Object? _readConsumerPubspec(String source) {
  try {
    return loadYaml(source);
  } on FormatException {
    throw StateError(
      'Cannot validate Apple runtime selection: malformed '
      'consumer pubspec. Fix pubspec.yaml and rerun flutter pub get.',
    );
  }
}

Future<void> _emitLiteRtLmAssets({
  required CodeConfig code,
  required BuildOutputBuilder output,
  required String packageRoot,
  required String reportDirPath,
  required Set<String> usedAssetNames,
  required Map<String, String> llamaCppFilePaths,
  required Logger log,
}) async {
  final bundleSpec = _liteRtLmBundleSpecForCode(code);
  if (bundleSpec == null) {
    log.warning(
      'LiteRT-LM runtime is not available for '
      '${_liteRtLmTargetLabel(code)}; no LiteRT-LM assets will be bundled. '
      'Configure $nativeRuntimesUserDefineKey to exclude litert_lm for this '
      'target.',
    );
    return;
  }

  final bundleDir = await _acquireLiteRtLmBundle(
    packageRoot: packageRoot,
    bundleSpec: bundleSpec,
    log: log,
  );
  if (code.targetOS == OS.macOS) {
    log.info(
      'Keeping macOS LiteRT-LM libraries in the hook cache at '
      '${bundleDir.path}; the runtime loads them directly to avoid Flutter '
      'rewriting upstream install names during app bundling.',
    );
    return;
  }
  // Owner archives also carry libraries no host loads, such as the prebuilt
  // libLiteRt beside Linux and Windows hosts that link LiteRT in.
  final libraryPaths = _collectDynamicLibraryPaths(
    bundleDir,
    additionalFileNames: bundleSpec.requiredLibraries,
    onlyFileNames: bundleSpec.requiredLibraries,
  );
  if (libraryPaths.isEmpty) {
    log.warning('LiteRT-LM bundle had no dynamic libraries.');
    return;
  }

  final emittedFileNames = <String>{};
  for (final sourcePath in libraryPaths) {
    final fileName = path.basename(sourcePath);
    final loweredFileName = fileName.toLowerCase();
    if (!emittedFileNames.add(loweredFileName)) {
      log.info('Skipping duplicate LiteRT-LM library `$fileName`.');
      continue;
    }
    final llamaCppPath = llamaCppFilePaths[loweredFileName];
    if (llamaCppPath != null) {
      await _shareLibraryWithLlamaCpp(
        liteRtLmPath: sourcePath,
        llamaCppPath: llamaCppPath,
        log: log,
      );
      continue;
    }
    final destinationPath = path.join(reportDirPath, fileName);
    await File(sourcePath).copy(destinationPath);
    if (code.targetOS == OS.iOS) {
      await _makeOwnerWritableForAppleStrip(File(destinationPath), log: log);
    }
    final assetName = _dedupeAssetName(
      _liteRtLmAssetName(fileName),
      usedAssetNames,
    );
    output.assets.code.add(
      CodeAsset(
        package: _packageName,
        name: assetName,
        linkMode: DynamicLoadingBundled(),
        file: Uri.file(path.absolute(destinationPath)),
      ),
    );
    log.info(
      'Reporting LiteRT-LM library `$fileName` as code asset '
      '`package:$_packageName/$assetName`.',
    );
  }
}

/// Emits one copy of a library that both the llama.cpp and the LiteRT-LM
/// bundle ship, since an app may bundle each file name only once.
///
/// On Windows both bundles ship the Visual C++ runtime app-locally. When both
/// copies carry a Windows version resource, the newer file version serves
/// both, as Microsoft keeps the runtime backward compatible, and a tie keeps
/// the llama.cpp copy. When either copy lacks a version resource, identical
/// files share one copy and different files fail the build instead of
/// guessing.
Future<void> _shareLibraryWithLlamaCpp({
  required String liteRtLmPath,
  required String llamaCppPath,
  required Logger log,
}) async {
  final fileName = path.basename(llamaCppPath);
  final liteRtLmBytes = await File(liteRtLmPath).readAsBytes();
  final llamaCppBytes = await File(llamaCppPath).readAsBytes();
  final liteRtLmVersion = windowsFileVersion(liteRtLmBytes);
  final llamaCppVersion = windowsFileVersion(llamaCppBytes);
  if (liteRtLmVersion == null || llamaCppVersion == null) {
    if (_sameBytes(liteRtLmBytes, llamaCppBytes)) {
      log.info('LiteRT-LM shares the llama.cpp copy of `$fileName`.');
      return;
    }
    throw Exception(
      'The llama.cpp and LiteRT-LM bundles both ship a different '
      '`$fileName` without a Windows file version, and an app can bundle '
      'only one. Exclude one runtime with $nativeRuntimesUserDefineKey.',
    );
  }
  if (isNewerWindowsFileVersion(liteRtLmVersion, llamaCppVersion)) {
    await File(liteRtLmPath).copy(llamaCppPath);
    log.info(
      'Bundling the LiteRT-LM copy of `$fileName` '
      '(${formatWindowsFileVersion(liteRtLmVersion)}) for both runtimes; '
      'the llama.cpp copy is ${formatWindowsFileVersion(llamaCppVersion)}.',
    );
    return;
  }
  log.info(
    'Bundling the llama.cpp copy of `$fileName` '
    '(${formatWindowsFileVersion(llamaCppVersion)}) for both runtimes; '
    'the LiteRT-LM copy is ${formatWindowsFileVersion(liteRtLmVersion)}.',
  );
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

Future<void> _emitStableDiffusionAssets({
  required StableDiffusionBundleSpec bundleSpec,
  required BuildOutputBuilder output,
  required String packageRoot,
  required String reportDirPath,
  required Set<String> usedAssetNames,
  required Logger log,
}) async {
  final bundleDir = await _acquireStableDiffusionBundle(
    packageRoot: packageRoot,
    bundleSpec: bundleSpec,
    log: log,
  );
  // One library per bundle; the Dart bindings resolve it by this asset id.
  final fileName = bundleSpec.requiredLibraries.single;
  final destinationPath = path.join(reportDirPath, fileName);
  await File(path.join(bundleDir.path, fileName)).copy(destinationPath);
  if (!usedAssetNames.add(_stableDiffusionAssetName)) {
    throw Exception(
      'Code asset package:$_packageName/$_stableDiffusionAssetName is '
      'already taken.',
    );
  }
  output.assets.code.add(
    CodeAsset(
      package: _packageName,
      name: _stableDiffusionAssetName,
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(path.absolute(destinationPath)),
    ),
  );
  log.info(
    'Reporting stable_diffusion library `$fileName` from '
    '${bundleSpec.archiveName} as code asset '
    '`package:$_packageName/$_stableDiffusionAssetName`.',
  );
}

Future<Directory> _acquireStableDiffusionBundle({
  required String packageRoot,
  required StableDiffusionBundleSpec bundleSpec,
  required Logger log,
}) async {
  final cacheDir = path.join(
    packageRoot,
    _dartToolDir,
    _cacheBaseDir,
    _stableDiffusionCacheDir,
    stableDiffusionVersion,
  );
  final extractedDir = Directory(path.join(cacheDir, bundleSpec.bundle));
  if (_missingStableDiffusionLibraries(extractedDir, bundleSpec).isEmpty) {
    log.info('Using cached stable_diffusion bundle: ${extractedDir.path}');
    return extractedDir;
  }

  await Directory(cacheDir).create(recursive: true);
  final archiveFile = File(path.join(cacheDir, bundleSpec.archiveName));
  if (archiveFile.existsSync() &&
      !await _stableDiffusionArchiveMatchesPin(archiveFile, bundleSpec)) {
    log.warning(
      'Cached ${bundleSpec.archiveName} does not match its pinned SHA-256; '
      'redownloading.',
    );
    await archiveFile.delete();
  }
  if (!archiveFile.existsSync()) {
    log.info(
      'Downloading stable_diffusion bundle from ${bundleSpec.releaseUrl}',
    );
    await _downloadRuntimeBundle(
      url: bundleSpec.releaseUrl,
      destination: archiveFile,
      description: 'stable_diffusion bundle',
      log: log,
    );
    await requireNativeArchiveSha256(
      archive: archiveFile,
      expectedSha256: bundleSpec.sha256,
      digestSource:
          'the pinned $_stableDiffusionNativeRepoSlug@'
          '$stableDiffusionReleaseTag digest',
    );
  }

  await _extractStableDiffusionLibraries(
    archiveFile: archiveFile,
    extractedDir: extractedDir,
    bundleSpec: bundleSpec,
  );
  log.info('Extracted stable_diffusion bundle to ${extractedDir.path}');
  return extractedDir;
}

Future<bool> _stableDiffusionArchiveMatchesPin(
  File archiveFile,
  StableDiffusionBundleSpec bundleSpec,
) async {
  final digest = sha256.convert(await archiveFile.readAsBytes()).toString();
  return digest == bundleSpec.sha256;
}

/// Writes only the pinned `lib/<library>` entries, by basename, so no archive
/// path can escape [extractedDir].
Future<void> _extractStableDiffusionLibraries({
  required File archiveFile,
  required Directory extractedDir,
  required StableDiffusionBundleSpec bundleSpec,
}) async {
  if (extractedDir.existsSync()) {
    await extractedDir.delete(recursive: true);
  }
  await extractedDir.create(recursive: true);
  final archive = TarDecoder().decodeBytes(
    GZipDecoder().decodeBytes(await archiveFile.readAsBytes()),
  );
  for (final entry in archive.files) {
    if (!entry.isFile) {
      continue;
    }
    final entryPath = path.posix.normalize(entry.name);
    final fileName = path.posix.basename(entryPath);
    if (entryPath != 'lib/$fileName' ||
        !bundleSpec.requiredLibraries.contains(fileName)) {
      continue;
    }
    await File(
      path.join(extractedDir.path, fileName),
    ).writeAsBytes(entry.content as List<int>);
  }
  final missing = _missingStableDiffusionLibraries(extractedDir, bundleSpec);
  if (missing.isNotEmpty) {
    await extractedDir.delete(recursive: true);
    throw Exception(
      'stable_diffusion bundle ${bundleSpec.archiveName} is missing required '
      'libraries: ${missing.join(', ')}',
    );
  }
}

List<String> _missingStableDiffusionLibraries(
  Directory directory,
  StableDiffusionBundleSpec bundleSpec,
) {
  return bundleSpec.requiredLibraries
      .where(
        (library) => !File(path.join(directory.path, library)).existsSync(),
      )
      .toList(growable: false);
}

Future<void> _makeOwnerWritableForAppleStrip(
  File file, {
  required Logger log,
}) async {
  final result = await Process.run('chmod', ['u+w', file.path]);
  if (result.exitCode != 0) {
    throw Exception(
      'Could not make iOS native asset writable for Xcode strip: '
      '${file.path}. ${result.stderr}',
    );
  }
  log.fine('Made iOS native asset owner-writable: ${file.path}.');
}

LiteRtLmBundleSpec? _liteRtLmBundleSpecForCode(CodeConfig code) {
  switch (code.targetOS) {
    case OS.android:
      return switch (code.targetArchitecture) {
        Architecture.arm64 => _litertLmBundles['android-arm64'],
        Architecture.x64 => _litertLmBundles['android-x64'],
        _ => null,
      };
    case OS.iOS:
      final isSimulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
      return switch (code.targetArchitecture) {
        Architecture.arm64 =>
          _litertLmBundles[isSimulator ? 'ios-arm64-sim' : 'ios-arm64'],
        Architecture.x64 => null,
        _ => null,
      };
    case OS.macOS:
      return switch (code.targetArchitecture) {
        Architecture.arm64 => _litertLmBundles['macos-arm64'],
        _ => null,
      };
    case OS.linux:
      return switch (code.targetArchitecture) {
        Architecture.arm64 => _litertLmBundles['linux-arm64'],
        Architecture.x64 => _litertLmBundles['linux-x64'],
        _ => null,
      };
    case OS.windows:
      return switch (code.targetArchitecture) {
        Architecture.x64 => _litertLmBundles['windows-x64'],
        _ => null,
      };
    default:
      return null;
  }
}

String _liteRtLmTargetLabel(CodeConfig code) {
  final architecture =
      code.targetOS == OS.iOS && code.targetArchitecture == Architecture.x64
      ? 'x86_64'
      : code.targetArchitecture.name;
  if (code.targetOS == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator) {
    return '${code.targetOS.name}-$architecture-sim';
  }
  return '${code.targetOS.name}-$architecture';
}

String _liteRtLmAssetName(String fileName) {
  var name = path.basenameWithoutExtension(fileName);
  final extension = path.extension(fileName).toLowerCase();
  if (name.startsWith('lib') && extension != '.dylib') {
    name = name.substring(3);
  }
  return 'litert_lm_$name';
}

Future<Directory> _acquireLiteRtLmBundle({
  required String packageRoot,
  required LiteRtLmBundleSpec bundleSpec,
  required Logger log,
}) async {
  final cacheDir = path.join(
    packageRoot,
    _dartToolDir,
    _cacheBaseDir,
    _litertLmCacheDir,
    liteRtLmVersion,
  );
  final extractedDir = Directory(path.join(cacheDir, bundleSpec.directoryName));
  if (_liteRtLmBundleIsUsable(extractedDir, bundleSpec)) {
    log.info('Using cached LiteRT-LM bundle: ${extractedDir.path}');
    return extractedDir;
  }

  await Directory(cacheDir).create(recursive: true);
  final archiveFile = File(path.join(cacheDir, bundleSpec.archiveName));
  if (archiveFile.existsSync() &&
      await _verifyLiteRtLmArchiveChecksum(
        archiveFile: archiveFile,
        bundleSpec: bundleSpec,
        log: log,
        allowRefresh: true,
      ) &&
      await _tryExtractLiteRtLmArchive(
        archiveFile: archiveFile,
        extractedDir: extractedDir,
        bundleSpec: bundleSpec,
        log: log,
        allowRefresh: true,
      )) {
    return extractedDir;
  }
  if (!archiveFile.existsSync()) {
    await _downloadLiteRtLmArchive(
      bundleSpec: bundleSpec,
      destination: archiveFile,
      log: log,
    );
  }
  await _verifyLiteRtLmArchiveChecksum(
    archiveFile: archiveFile,
    bundleSpec: bundleSpec,
    log: log,
    allowRefresh: false,
  );

  await _tryExtractLiteRtLmArchive(
    archiveFile: archiveFile,
    extractedDir: extractedDir,
    bundleSpec: bundleSpec,
    log: log,
    allowRefresh: false,
  );
  return extractedDir;
}

Future<bool> _verifyLiteRtLmArchiveChecksum({
  required File archiveFile,
  required LiteRtLmBundleSpec bundleSpec,
  required Logger log,
  required bool allowRefresh,
}) async {
  final actualSha256 = sha256
      .convert(await archiveFile.readAsBytes())
      .toString();
  if (actualSha256 == bundleSpec.sha256) {
    return true;
  }

  if (!allowRefresh) {
    await archiveFile.delete();
    throw NativeArchiveDigestException.mismatch(
      archiveName: bundleSpec.archiveName,
      expectedSha256: bundleSpec.sha256,
      actualSha256: actualSha256,
      digestSource:
          'the pinned leehack/litert-lm-native@$liteRtLmReleaseTag digest',
    );
  }

  log.warning(
    'LiteRT-LM archive ${bundleSpec.archiveName} checksum mismatch: '
    'expected ${bundleSpec.sha256}, got $actualSha256. Redownloading.',
  );
  await archiveFile.delete();
  return false;
}

Future<bool> _tryExtractLiteRtLmArchive({
  required File archiveFile,
  required Directory extractedDir,
  required LiteRtLmBundleSpec bundleSpec,
  required Logger log,
  required bool allowRefresh,
}) async {
  if (extractedDir.existsSync()) {
    await extractedDir.delete(recursive: true);
  }
  await extractedDir.create(recursive: true);
  try {
    final bytes = await archiveFile.readAsBytes();
    final archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    for (final entry in archive.files) {
      if (!entry.isFile) {
        continue;
      }
      if (!_isLiteRtLmEntrySelected(entry.name, bundleSpec)) {
        continue;
      }
      final fileName = path.basename(entry.name);
      if (!_isLiteRtLmRuntimeLibraryFileName(fileName, bundleSpec)) {
        continue;
      }
      await File(
        path.join(extractedDir.path, fileName),
      ).writeAsBytes(entry.content as List<int>);
    }
  } on FormatException catch (error) {
    log.warning(
      'Archive package could not decode LiteRT-LM PAX metadata; falling back '
      'to system tar: $error',
    );
    final result = await Process.run('tar', [
      '-xzf',
      archiveFile.path,
      '-C',
      extractedDir.path,
    ]);
    if (result.exitCode != 0) {
      throw Exception(
        'System tar failed for LiteRT-LM bundle: ${result.stderr}',
      );
    }
    await _flattenLiteRtLmDynamicLibraries(extractedDir, bundleSpec);
  } catch (error) {
    if (!allowRefresh) {
      rethrow;
    }
    log.warning(
      'Cached LiteRT-LM archive could not be extracted; redownloading '
      '${bundleSpec.archiveName}: $error',
    );
    await archiveFile.delete();
    if (extractedDir.existsSync()) {
      await extractedDir.delete(recursive: true);
    }
    return false;
  }
  final missingLibraries = _missingLiteRtLmLibraries(extractedDir, bundleSpec);
  if (missingLibraries.isNotEmpty) {
    if (allowRefresh) {
      log.warning(
        'Cached LiteRT-LM archive ${bundleSpec.archiveName} is missing '
        'required libraries: ${missingLibraries.join(', ')}; redownloading.',
      );
      await archiveFile.delete();
      if (extractedDir.existsSync()) {
        await extractedDir.delete(recursive: true);
      }
      return false;
    }
    throw Exception(
      'LiteRT-LM bundle ${bundleSpec.archiveName} is missing required '
      'libraries: ${missingLibraries.join(', ')}',
    );
  }
  log.info('Extracted LiteRT-LM bundle to ${extractedDir.path}');
  return true;
}

Future<void> _downloadLiteRtLmArchive({
  required LiteRtLmBundleSpec bundleSpec,
  required File destination,
  required Logger log,
}) async {
  log.info('Downloading LiteRT-LM bundle from ${bundleSpec.releaseUrl}');
  await _downloadRuntimeBundle(
    url: bundleSpec.releaseUrl,
    destination: destination,
    description: 'LiteRT-LM bundle',
    log: log,
  );
}

bool _isLiteRtLmEntrySelected(String entryName, LiteRtLmBundleSpec bundleSpec) {
  final normalized = path.posix.normalize(entryName);
  final sourcePrefix = bundleSpec.sourcePrefix;
  return normalized == sourcePrefix || normalized.startsWith('$sourcePrefix/');
}

Future<void> _flattenLiteRtLmDynamicLibraries(
  Directory extractedDir,
  LiteRtLmBundleSpec bundleSpec,
) async {
  final sourcePrefix = bundleSpec.sourcePrefix;
  final nestedDir = Directory(
    path.joinAll([extractedDir.path, ...sourcePrefix.split('/')]),
  );
  if (!nestedDir.existsSync()) {
    return;
  }
  await for (final entity in nestedDir.list(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final fileName = path.basename(entity.path);
    if (!_isLiteRtLmRuntimeLibraryFileName(fileName, bundleSpec)) {
      continue;
    }
    await entity.copy(path.join(extractedDir.path, fileName));
  }
  await nestedDir.delete(recursive: true);
}

bool _liteRtLmBundleIsUsable(
  Directory directory,
  LiteRtLmBundleSpec bundleSpec,
) {
  if (_missingLiteRtLmLibraries(directory, bundleSpec).isNotEmpty) {
    return false;
  }
  return true;
}

List<String> _missingLiteRtLmLibraries(
  Directory directory,
  LiteRtLmBundleSpec bundleSpec,
) {
  if (!directory.existsSync()) {
    return bundleSpec.requiredLibraries.toList(growable: false);
  }
  return bundleSpec.requiredLibraries
      .where((libraryName) {
        return !File(path.join(directory.path, libraryName)).existsSync();
      })
      .toList(growable: false);
}

bool _isLiteRtLmRuntimeLibraryFileName(
  String fileName,
  LiteRtLmBundleSpec bundleSpec,
) {
  return _dynamicLibraryExtensions.contains(
        path.extension(fileName).toLowerCase(),
      ) ||
      bundleSpec.requiredLibraries.contains(fileName);
}

String _dedupeAssetName(String base, Set<String> used) {
  if (!used.contains(base)) {
    used.add(base);
    return base;
  }

  var index = 2;
  while (used.contains('${base}_$index')) {
    index++;
  }

  final deduped = '${base}_$index';
  used.add(deduped);
  return deduped;
}

_NativeBundleConfig _resolveNativeBundleConfig(
  HookInputUserDefines userDefines,
) {
  return _NativeBundleConfig(
    tag: _resolveNativeTag(userDefines[nativeTagUserDefineKey]),
    repository: _resolveNativeRepository(
      userDefines[nativeRepositoryUserDefineKey],
    ),
    localPath: _resolveNativePath(userDefines),
  );
}

String _resolveNativeTag(Object? rawUserConfig) {
  if (rawUserConfig == null) {
    return llamaCppTag;
  }

  if (rawUserConfig is! String) {
    throw FormatException(
      'hooks.user_defines.$_packageName.$nativeTagUserDefineKey must be a '
      'string release tag such as $llamaCppTag.',
    );
  }

  final tag = rawUserConfig;
  if (tag.isEmpty) {
    throw FormatException(
      'hooks.user_defines.$_packageName.$nativeTagUserDefineKey must not be '
      'empty.',
    );
  }
  if (!isValidNativeReleaseTag(tag)) {
    throw FormatException(
      'hooks.user_defines.$_packageName.$nativeTagUserDefineKey must be a '
      'stable vMAJOR.MINOR.PATCH tag, stable wrapper rebuild '
      'vMAJOR.MINOR.PATCH-N, canonical historical/nightly bNNNN tag without '
      'leading zeros, nightly wrapper '
      'rebuild bNNNN-N, or legacy wrapper artifact bNNNN-llamadart.N '
      '(for example $llamaCppTag).',
    );
  }

  return tag;
}

String _resolveNativeRepository(Object? rawUserConfig) {
  if (rawUserConfig == null) {
    return _nativeRepoSlug;
  }

  if (rawUserConfig is! String) {
    throw FormatException(
      'hooks.user_defines.$_packageName.$nativeRepositoryUserDefineKey must be '
      'a GitHub repository slug such as $_nativeRepoSlug.',
    );
  }

  final repository = _normalizeNativeRepository(rawUserConfig);
  final segments = repository.split('/');
  if (segments.length != 2 ||
      segments.any((segment) => !_isValidGithubRepoSegment(segment))) {
    throw FormatException(
      'hooks.user_defines.$_packageName.$nativeRepositoryUserDefineKey must be '
      'a GitHub repository slug such as $_nativeRepoSlug.',
    );
  }

  return repository;
}

bool _isValidGithubRepoSegment(String segment) {
  return _githubRepoSegmentPattern.hasMatch(segment) &&
      segment != '.' &&
      segment != '..';
}

String _normalizeNativeRepository(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host == 'github.com' &&
      uri.pathSegments.length >= 2) {
    final owner = uri.pathSegments[0];
    final repo = uri.pathSegments[1].replaceFirst(RegExp(r'\.git$'), '');
    return '$owner/$repo';
  }

  final gitPrefix = 'git@github.com:';
  if (trimmed.startsWith(gitPrefix)) {
    return trimmed
        .substring(gitPrefix.length)
        .replaceFirst(RegExp(r'\.git$'), '');
  }

  return trimmed.replaceFirst(RegExp(r'\.git$'), '');
}

Uri? _resolveNativePath(HookInputUserDefines userDefines) {
  final rawUserConfig = userDefines[nativePathUserDefineKey];
  if (rawUserConfig == null) {
    return null;
  }

  if (rawUserConfig is! String) {
    throw FormatException(
      'hooks.user_defines.$_packageName.$nativePathUserDefineKey must be a '
      'path string.',
    );
  }
  if (rawUserConfig.trim().isEmpty) {
    throw FormatException(
      'hooks.user_defines.$_packageName.$nativePathUserDefineKey must not be '
      'empty.',
    );
  }

  final resolvedPath = userDefines.path(nativePathUserDefineKey);
  if (resolvedPath == null || !resolvedPath.isScheme('file')) {
    throw FormatException(
      'hooks.user_defines.$_packageName.$nativePathUserDefineKey must resolve '
      'to a local file path.',
    );
  }

  return resolvedPath;
}

/// The cached, extracted or downloaded directory of release archive [bundle].
///
/// A [sidecar] archive is complete only when it holds the module of the
/// backend it adds and, with the core bundle's libraries, every runtime
/// dependency that backend needs; an incomplete cached copy is re-extracted or
/// redownloaded like a core bundle.
Future<Directory> _acquireBundleDirectory({
  required String packageRoot,
  required _NativeBundleConfig nativeConfig,
  required String bundle,
  required Logger log,
  ({String bundle, String backend, List<String> coreLibraryPaths})? sidecar,
}) async {
  bool holdsSidecarBackend(List<String> libraryPaths) =>
      collectAvailableBackends(
        describeNativeLibraries(libraryPaths),
      ).contains(sidecar!.backend);
  bool isComplete(List<String> libraryPaths) {
    if (sidecar == null) {
      return _isBundleLayoutCompatible(
        bundle: bundle,
        libraryPaths: libraryPaths,
        log: log,
      );
    }
    return libraryPaths.isNotEmpty &&
        holdsSidecarBackend(libraryPaths) &&
        _isBundleLayoutCompatible(
          bundle: sidecar.bundle,
          libraryPaths: [...sidecar.coreLibraryPaths, ...libraryPaths],
          log: log,
        );
  }

  final allowLegacyLocalBundles = _isLegacyLocalBundleEnabled();
  final archiveName = 'llamadart-native-$bundle-${nativeConfig.tag}.tar.gz';
  final cacheDir = _bundleCacheDirectory(
    packageRoot: packageRoot,
    nativeConfig: nativeConfig,
    bundle: bundle,
  );
  final extractedDir = Directory(path.join(cacheDir, 'extracted'));
  final archivePath = path.join(cacheDir, archiveName);
  final archiveFile = File(archivePath);

  Never throwIncomplete(
    List<String> libraryPaths, {
    String? cachedCopyMatches,
  }) {
    final String problem;
    final String fix;
    if (sidecar == null) {
      problem = 'Downloaded bundle $archiveName is missing runtime deps.';
      fix = 'use a release whose bundle is complete';
    } else {
      problem = holdsSidecarBackend(libraryPaths)
          ? 'The $bundle sidecar archive of ${nativeConfig.sourceLabel} is '
                'missing runtime dependencies of its ${sidecar.backend} '
                'backend for ${sidecar.bundle}.'
          : 'The $bundle sidecar archive of ${nativeConfig.sourceLabel} '
                'holds no ggml-${sidecar.backend} module.';
      fix =
          'remove ${sidecar.backend} for ${sidecar.bundle} from '
          'hooks.user_defines.$_packageName.$nativeBackendUserDefineKey, use '
          'a release whose sidecar is complete';
    }
    final message = cachedCopyMatches == null
        ? problem
        : '$problem Its cached copy at $archivePath matches $cachedCopyMatches, so '
              'downloading it again would not help: $fix, or set '
              '$nativePathUserDefineKey to a local bundle you trust.';
    if (sidecar != null) {
      throw NativeHookContractException(message);
    }
    throw Exception(message);
  }

  final localPath = nativeConfig.localPath;
  if (localPath != null) {
    return _acquireLocalBundleDirectory(
      localPath: localPath,
      nativeTag: nativeConfig.tag,
      bundle: bundle,
      archiveName: archiveName,
      cacheDir: cacheDir,
      extractedDir: extractedDir,
      log: log,
    );
  }

  final cachedLibraryPaths = _collectDynamicLibraryPaths(extractedDir);
  if (cachedLibraryPaths.isNotEmpty && isComplete(cachedLibraryPaths)) {
    if (await nativeExtractionMatchesArchive(
      extractedDir: extractedDir,
      archive: archiveFile,
    )) {
      log.info('Using cached native bundle: ${extractedDir.path}');
      return extractedDir;
    }
    if (!nativeExtractionMarkerFile(extractedDir).existsSync() &&
        archiveFile.existsSync() &&
        !_hasOfflineArchiveDigest(
          nativeConfig: nativeConfig,
          cacheDir: cacheDir,
        )) {
      // An extraction from before markers, of an override cached before the
      // hook kept SHA256SUMS: its archive cannot be verified offline, and was
      // as trusted as the extraction reused before, so it is re-extracted.
      try {
        final paths = await _extractCachedArchive(
          archivePath: archivePath,
          extractedDir: extractedDir,
          cacheDir: cacheDir,
          archiveSha256: await fileSha256(archiveFile),
          log: log,
        );
        if (isComplete(paths)) {
          log.info('Re-extracted cached native bundle archive: $archivePath');
          return extractedDir;
        }
      } on Exception catch (error) {
        log.warning('Could not re-extract $archivePath ($error).');
      }
    }
  }

  if (cachedLibraryPaths.isNotEmpty) {
    if (nativeExtractionMarkerFile(extractedDir).existsSync()) {
      log.warning(
        'Cached native bundle at ${extractedDir.path} is incomplete or does '
        'not match its archive; refreshing: $bundle',
      );
    } else {
      log.info(
        'Cached native bundle at ${extractedDir.path} has no extraction '
        'record; refreshing it: $bundle',
      );
    }
    if (extractedDir.existsSync()) {
      await extractedDir.delete(recursive: true);
    }
  }

  if (allowLegacyLocalBundles) {
    final localCandidates = _localBundleCandidates(
      packageRoot: packageRoot,
      bundle: bundle,
    );
    for (final candidatePath in localCandidates) {
      final candidate = Directory(candidatePath);
      final candidatePaths = _collectDynamicLibraryPaths(candidate);
      if (candidatePaths.isNotEmpty && isComplete(candidatePaths)) {
        log.info(
          'Using legacy local native bundle directory: ${candidate.path}',
        );
        return candidate;
      }
    }
  }

  await Directory(cacheDir).create(recursive: true);
  final cachedArchiveSha256 = archiveFile.existsSync()
      ? await fileSha256(archiveFile)
      : null;
  var expectedDigest = await _expectedNativeArchiveDigest(
    nativeConfig: nativeConfig,
    bundle: bundle,
    archiveName: archiveName,
    cacheDir: cacheDir,
    cachedArchiveSha256: cachedArchiveSha256,
    log: log,
  );

  var extractedLibraryPaths = const <String>[];
  if (cachedArchiveSha256 != null) {
    if (cachedArchiveSha256 == expectedDigest.sha256) {
      extractedLibraryPaths = await _extractCachedArchive(
        archivePath: archivePath,
        extractedDir: extractedDir,
        cacheDir: cacheDir,
        archiveSha256: cachedArchiveSha256,
        log: log,
      );
      if (isComplete(extractedLibraryPaths)) {
        log.info('Using cached native bundle archive: $archivePath');
        return extractedDir;
      }
      if (expectedDigest.cached) {
        expectedDigest = await _expectedNativeArchiveDigest(
          nativeConfig: nativeConfig,
          bundle: bundle,
          archiveName: archiveName,
          cacheDir: cacheDir,
          cachedArchiveSha256: null,
          log: log,
          cachedListMatchedArchive: true,
        );
      }
      if (cachedArchiveSha256 == expectedDigest.sha256) {
        throwIncomplete(
          extractedLibraryPaths,
          cachedCopyMatches: expectedDigest.source,
        );
      }
      log.warning(
        'Cached native bundle archive is stale; redownloading: $archivePath',
      );
    } else {
      log.warning(
        'Cached native bundle archive $archivePath has SHA-256 '
        '$cachedArchiveSha256, but ${expectedDigest.source} expects '
        '${expectedDigest.sha256}; redownloading.',
      );
    }
    await archiveFile.delete();
    if (extractedDir.existsSync()) {
      await extractedDir.delete(recursive: true);
    }
  }

  if (expectedDigest.cached) {
    expectedDigest = await _expectedNativeArchiveDigest(
      nativeConfig: nativeConfig,
      bundle: bundle,
      archiveName: archiveName,
      cacheDir: cacheDir,
      cachedArchiveSha256: null,
      log: log,
    );
  }
  if (nativeConfig.usesOverride) {
    // Fails before a download whose layout this hook cannot interpret.
    await _overrideReleaseManifest(
      packageRoot: packageRoot,
      nativeConfig: nativeConfig,
      bundle: bundle,
      log: log,
    );
  }
  await _downloadReleaseAsset(
    repository: nativeConfig.repository,
    nativeTag: nativeConfig.tag,
    assetName: archiveName,
    destinationPath: archivePath,
    log: log,
  );
  await requireNativeArchiveSha256(
    archive: archiveFile,
    expectedSha256: expectedDigest.sha256,
    digestSource: expectedDigest.source,
  );
  extractedLibraryPaths = await _extractCachedArchive(
    archivePath: archivePath,
    extractedDir: extractedDir,
    cacheDir: cacheDir,
    archiveSha256: expectedDigest.sha256,
    log: log,
  );
  if (!isComplete(extractedLibraryPaths)) {
    throwIncomplete(extractedLibraryPaths);
  }
  return extractedDir;
}

final _pinnedBackendSidecarSpecs = {
  for (final spec in llamaCppBackendSidecarSpecs) spec.archive: spec,
};

final _pinnedReleaseManifest = NativeReleaseManifest(
  hookContractVersion: llamaCppHookContractVersion,
  sidecars: [
    for (final spec in llamaCppBackendSidecarSpecs)
      NativeBackendSidecar(
        bundle: spec.bundle,
        backend: spec.backend,
        archive: spec.archive,
      ),
  ],
);

/// Library paths from the backend sidecars that add each requested backend
/// the core bundle at [coreLibraryPaths] lacks, each acquired like a bundle.
///
/// A requested backend with no sidecar is left to [selectLibrariesForBundling],
/// which warns and falls back to the defaults, unless the release publishes it
/// only as a sidecar: that throws [NativeHookContractException]. An
/// overridden release whose `assets.json` is neither cached nor reachable
/// gets only the sidecars [_cachedSidecarLibraryPaths] finds, so an offline
/// build over a cached core still succeeds. A local
/// `llamadart_native_path` bundle must already hold every module it ships.
Future<List<String>> _acquireBackendSidecarLibraryPaths({
  required String packageRoot,
  required _NativeBundleConfig nativeConfig,
  required String bundle,
  required List<String> coreLibraryPaths,
  required Object? rawBackendConfig,
  required Logger log,
}) async {
  if (nativeConfig.localPath != null) {
    return const [];
  }
  final requested =
      parseRequestedBackends(bundle: bundle, rawUserConfig: rawBackendConfig) ??
      const <String>[];
  final coreBackends = collectAvailableBackends(
    describeNativeLibraries(coreLibraryPaths),
  );
  final missing = requested.where((backend) => !coreBackends.contains(backend));
  if (missing.isEmpty) {
    return const [];
  }

  ({String failure, Object error, String remedy})? unreachable;
  final manifest = nativeConfig.usesOverride
      ? await _overrideReleaseManifest(
          packageRoot: packageRoot,
          nativeConfig: nativeConfig,
          bundle: bundle,
          log: log,
          onUnreachable: (failure, error, remedy) =>
              unreachable = (failure: failure, error: error, remedy: remedy),
        )
      : _pinnedReleaseManifest;
  if (unreachable case final unreachable?) {
    return _cachedSidecarLibraryPaths(
      packageRoot: packageRoot,
      nativeConfig: nativeConfig,
      bundle: bundle,
      backends: missing,
      coreLibraryPaths: coreLibraryPaths,
      unreachable: unreachable,
      log: log,
    );
  }
  final sidecarPaths = <String>[];
  for (final backend in missing) {
    final sidecar = manifest?.sidecarFor(bundle: bundle, backend: backend);
    if (sidecar == null) {
      if (manifest != null &&
          manifest.publishesOnlyAsSidecar(bundle: bundle, backend: backend)) {
        throw NativeHookContractException(
          'hooks.user_defines.$_packageName.$nativeBackendUserDefineKey '
          'selects $backend for $bundle, but ${nativeConfig.sourceLabel} '
          '(hook contract ${manifest.hookContractVersion}) publishes $backend '
          'for $bundle only as a sidecar archive and lists none. Remove '
          '$backend for $bundle, or use a release that publishes its sidecar.',
        );
      }
      continue;
    }
    final sidecarDir = await _acquireBundleDirectory(
      packageRoot: packageRoot,
      nativeConfig: nativeConfig,
      bundle: sidecar.archive,
      log: log,
      sidecar: (
        bundle: bundle,
        backend: backend,
        coreLibraryPaths: coreLibraryPaths,
      ),
    );
    log.info('Using the $backend backend sidecar: ${sidecarDir.path}');
    sidecarPaths.addAll(_collectDynamicLibraryPaths(sidecarDir));
  }
  return sidecarPaths;
}

/// Library paths of the cached sidecars that add [backends] to [bundle] of an
/// overridden release whose `assets.json` is [unreachable]; the others are
/// left out with a warning.
///
/// Without the manifest, a sidecar is looked for only under the archive name
/// the pinned release gives it, and is used only from a cache
/// [_acquireBundleDirectory] accepts: an extraction, or an archive the cached
/// `SHA256SUMS` lists. Fetching anything else would need the manifest first.
Future<List<String>> _cachedSidecarLibraryPaths({
  required String packageRoot,
  required _NativeBundleConfig nativeConfig,
  required String bundle,
  required Iterable<String> backends,
  required List<String> coreLibraryPaths,
  required ({String failure, Object error, String remedy}) unreachable,
  required Logger log,
}) async {
  final paths = <String>[];
  final skipped = <String>[];
  for (final backend in backends) {
    final archive = _pinnedReleaseManifest
        .sidecarFor(bundle: bundle, backend: backend)
        ?.archive;
    if (archive != null &&
        Directory(
          _bundleCacheDirectory(
            packageRoot: packageRoot,
            nativeConfig: nativeConfig,
            bundle: archive,
          ),
        ).existsSync()) {
      try {
        final directory = await _acquireBundleDirectory(
          packageRoot: packageRoot,
          nativeConfig: nativeConfig,
          bundle: archive,
          log: log,
          sidecar: (
            bundle: bundle,
            backend: backend,
            coreLibraryPaths: coreLibraryPaths,
          ),
        );
        log.info(
          '${unreachable.failure} (${unreachable.error}); using the cached '
          '$backend backend sidecar: ${directory.path}',
        );
        paths.addAll(_collectDynamicLibraryPaths(directory));
        continue;
      } on Exception catch (error) {
        log.warning('Not using the cached $archive sidecar ($error).');
      }
    }
    skipped.add(backend);
  }
  if (skipped.isNotEmpty) {
    log.warning(
      '${unreachable.failure} to find the ${skipped.join(', ')} sidecar of '
      '${nativeConfig.sourceLabel} (${unreachable.error}); building $bundle '
      'without it. ${unreachable.remedy}',
    );
  }
  return paths;
}

/// The `assets.json` of an overridden release, or `null` when the release
/// publishes none, as releases from before that manifest did (contract 1).
///
/// A copy cached beside the release's bundle caches is reused; otherwise the
/// manifest is downloaded and cached there. A release that publishes none is
/// recorded there as `assets.json.absent`, so builds in the next day need no
/// network; an older or future-dated record is re-checked, and kept and
/// renewed when the check fails or returns something other than JSON. Throws
/// [NativeHookContractException] when it requires an unsupported hook contract
/// or cannot be read. When the caller can do without it, a manifest that
/// cannot be downloaded instead passes the failure, its cause and the remedy
/// to [onUnreachable] and returns `null`.
Future<NativeReleaseManifest?> _overrideReleaseManifest({
  required String packageRoot,
  required _NativeBundleConfig nativeConfig,
  required String bundle,
  required Logger log,
  void Function(String failure, Object error, String remedy)? onUnreachable,
}) async {
  final cached = File(
    path.join(
      path.dirname(
        _bundleCacheDirectory(
          packageRoot: packageRoot,
          nativeConfig: nativeConfig,
          bundle: bundle,
        ),
      ),
      'assets.json',
    ),
  );
  final source = '${nativeConfig.sourceLabel} assets.json';
  final absent = File('${cached.path}.absent');
  final recordedAbsent = !cached.existsSync() && absent.existsSync();
  // A release can publish assets.json after a build recorded it missing, so
  // the record is re-checked once it is older than a day. A record dated in
  // the future would otherwise stay fresh until the clock passes it.
  final recordAge = recordedAbsent
      ? _now().difference(absent.statSync().modified)
      : null;
  if (recordAge != null &&
      !recordAge.isNegative &&
      recordAge < _absentManifestRecheckInterval) {
    log.info(
      '${nativeConfig.sourceLabel} publishes no assets.json (recorded at '
      '${absent.path}); treating it as hook contract 1.',
    );
    return null;
  }
  if (cached.existsSync()) {
    try {
      return parseNativeReleaseManifest(
        utf8.decode(await cached.readAsBytes()),
        tag: nativeConfig.tag,
        source: 'the cached $source at ${cached.path}',
      );
    } on Exception catch (error) {
      log.warning(
        'Not using the cached $source ($error); fetching it from the release.',
      );
    }
  }

  final url =
      'https://github.com/${nativeConfig.repository}/releases/download/'
      '${nativeConfig.tag}/assets.json';
  final downloaded = File('${cached.path}.download');

  // Stamps the record with this machine's clock, which the next build compares
  // it with; writing it would use the file system's, which a network file
  // system can run ahead of this one.
  Future<NativeReleaseManifest?> keepRecordedAbsent() async {
    try {
      if (!absent.existsSync()) {
        absent.createSync();
      }
      absent.setLastModifiedSync(_now());
    } on FileSystemException catch (error) {
      log.warning('Could not record ${absent.path} ($error).');
    }
    return null;
  }

  try {
    try {
      await _downloadRuntimeBundle(
        url: url,
        destination: downloaded,
        description: 'native release assets.json',
        log: log,
      );
    } on Exception catch (error) {
      if (error is _RuntimeBundleDownloadHttpException &&
          error.statusCode == HttpStatus.notFound) {
        log.info(
          '${nativeConfig.sourceLabel} publishes no assets.json; treating it '
          'as hook contract 1.',
        );
        return await keepRecordedAbsent();
      }
      if (recordedAbsent) {
        log.info(
          'Could not re-check $url ($error); still treating '
          '${nativeConfig.sourceLabel} as hook contract 1, as recorded at '
          '${absent.path}.',
        );
        return await keepRecordedAbsent();
      }
      final remedy =
          'To build without network access, put that release\'s assets.json '
          'at ${cached.path}, or set $nativePathUserDefineKey to a local '
          'bundle you trust.';
      if (onUnreachable != null) {
        onUnreachable('Could not download $url', error, remedy);
        return null;
      }
      throw NativeHookContractException(
        'Could not download $url to check the hook contract of '
        '${nativeConfig.sourceLabel}: $error. $remedy',
      );
    }
    // A cut-short or garbled download, unlike a network block page, is
    // corrupt: failing keeps it from passing for a release without assets.json.
    NativeHookContractException corrupt(String problem) =>
        NativeHookContractException(
          '$source from $url $problem. Retry the build; if it keeps failing, '
          'put that release\'s assets.json at ${cached.path}, or set '
          '$nativePathUserDefineKey to a local bundle you trust.',
        );
    final String text;
    try {
      text = utf8.decode(await downloaded.readAsBytes());
    } on FormatException {
      throw corrupt('is not UTF-8 text');
    }
    if (recordedAbsent && _looksLikeBlockPage(text)) {
      log.warning(
        '$source from $url is not JSON, such as a network block page; still '
        'treating ${nativeConfig.sourceLabel} as hook contract 1, as recorded '
        'at ${absent.path}.',
      );
      return await keepRecordedAbsent();
    }
    if (!_looksLikeBlockPage(text)) {
      try {
        jsonDecode(text);
      } on FormatException {
        throw corrupt('is empty or truncated JSON');
      }
    }
    final manifest = parseNativeReleaseManifest(
      text,
      tag: nativeConfig.tag,
      source: source,
    );
    try {
      if (cached.existsSync()) {
        await cached.delete();
      }
      await downloaded.rename(cached.path);
      if (absent.existsSync()) {
        await absent.delete();
      }
    } on FileSystemException catch (error) {
      log.warning('Could not keep $source at ${cached.path} ($error).');
    }
    return manifest;
  } finally {
    if (downloaded.existsSync()) {
      await downloaded.delete();
    }
  }
}

/// Whether [text] is a page rather than a manifest: not empty and not starting
/// as JSON, unlike a truncated or invalid manifest, which must still fail.
bool _looksLikeBlockPage(String text) {
  final trimmed = text.trimLeft();
  return trimmed.isNotEmpty &&
      !trimmed.startsWith('{') &&
      !trimmed.startsWith('[');
}

/// Whether [_expectedNativeArchiveDigest] may check a cached archive without
/// network access: the default release is pinned, and an override may have
/// its `SHA256SUMS` cached.
bool _hasOfflineArchiveDigest({
  required _NativeBundleConfig nativeConfig,
  required String cacheDir,
}) =>
    _isPinnedRelease(nativeConfig) ||
    FileSystemEntity.typeSync(path.join(cacheDir, 'SHA256SUMS')) !=
        FileSystemEntityType.notFound;

bool _isPinnedRelease(_NativeBundleConfig nativeConfig) =>
    nativeConfig.tag == llamaCppTag &&
    nativeConfig.repository == _nativeRepoSlug;

/// The SHA-256 a llama.cpp archive must have: the pin for the default release,
/// or the release's own `SHA256SUMS` entry for a tag or repository override.
///
/// For an override, a cached archive whose [cachedArchiveSha256] the cached
/// `SHA256SUMS` lists is verified offline, and the result is marked `cached`.
/// Otherwise the release's `SHA256SUMS` is fetched and kept beside the archive
/// for later builds. Callers fetch a fresh list before downloading, so a
/// download is never checked against the cached list. The cached list is no
/// less trusted than the cached archive it lists.
/// [cachedListMatchedArchive] marks the fetch that follows an incomplete
/// archive the cached list matched, whose failure must not ask for the list
/// to be pre-seeded.
Future<({String sha256, String source, bool cached})>
_expectedNativeArchiveDigest({
  required _NativeBundleConfig nativeConfig,
  required String bundle,
  required String archiveName,
  required String cacheDir,
  required String? cachedArchiveSha256,
  required Logger log,
  bool cachedListMatchedArchive = false,
}) async {
  if (_isPinnedRelease(nativeConfig)) {
    final pinned =
        llamaCppBundleSha256[bundle] ??
        _pinnedBackendSidecarSpecs[bundle]?.sha256;
    if (pinned == null) {
      throw NativeArchiveDigestException(
        'No SHA-256 is pinned for $archiveName in llamaCppBundleSha256, so '
        'the hook cannot verify it. Run tool/native/sync_native_release_pins.py '
        'for $llamaCppTag to pin every bundle.',
      );
    }
    return (
      sha256: pinned,
      source: 'the pinned $_nativeRepoSlug@$llamaCppTag digest',
      cached: false,
    );
  }

  final source = '${nativeConfig.sourceLabel} SHA256SUMS';
  final checksumFile = File(path.join(cacheDir, 'SHA256SUMS'));
  String? cachedListRejection;
  if (cachedArchiveSha256 != null &&
      FileSystemEntity.typeSync(checksumFile.path) !=
          FileSystemEntityType.notFound) {
    final cachedSource = 'the cached $source at ${checksumFile.path}';
    try {
      final cachedSha256 = sha256SumsEntry(
        await _readSha256Sums(checksumFile, source: cachedSource),
        fileName: archiveName,
        source: cachedSource,
      );
      if (cachedSha256 != null && cachedSha256 == cachedArchiveSha256) {
        return (sha256: cachedSha256, source: cachedSource, cached: true);
      }
      cachedListRejection = cachedSha256 == null
          ? '$cachedSource lists no SHA-256 for $archiveName.'
          : '$cachedSource lists SHA-256 $cachedSha256 for $archiveName, but '
                'the cached archive has $cachedArchiveSha256.';
    } on NativeArchiveDigestException catch (error) {
      cachedListRejection = error.message;
    } on FileSystemException catch (error) {
      cachedListRejection = '$cachedSource could not be read: $error.';
    }
    log.warning(
      'Not using the cached SHA256SUMS: $cachedListRejection Fetching the '
      'release SHA256SUMS instead.',
    );
  }

  final url =
      'https://github.com/${nativeConfig.repository}/releases/download/'
      '${nativeConfig.tag}/SHA256SUMS';
  final downloadedFile = File('${checksumFile.path}.download');
  try {
    try {
      await _downloadRuntimeBundle(
        url: url,
        destination: downloadedFile,
        description: 'native release SHA256SUMS',
        log: log,
      );
    } on Exception catch (error) {
      if (error is _RuntimeBundleDownloadHttpException &&
          error.statusCode == HttpStatus.notFound) {
        throw NativeArchiveDigestException(
          '${nativeConfig.sourceLabel} publishes no SHA256SUMS ($url returned '
          '404), so the hook cannot verify $archiveName. Use a release that '
          'publishes SHA256SUMS, or set $nativePathUserDefineKey to a local '
          'bundle you trust.',
        );
      }
      if (cachedListMatchedArchive) {
        throw NativeArchiveDigestException(
          'Could not download $url to re-check $archiveName: $error. The '
          'cached SHA256SUMS at ${checksumFile.path} lists the cached archive, '
          'which lacks runtime libraries. Build again online, or set '
          '$nativePathUserDefineKey to a local bundle you trust.',
        );
      }
      final rejectedCache = cachedListRejection == null
          ? ''
          : 'The cached SHA256SUMS was not used: $cachedListRejection ';
      throw NativeArchiveDigestException(
        'Could not download $url to verify $archiveName: $error. '
        '${rejectedCache}To build without network access, put that release\'s '
        'SHA256SUMS at ${checksumFile.path} with $archiveName beside it, or '
        'set $nativePathUserDefineKey to a local bundle you trust.',
      );
    }
    final listedSha256 = sha256SumsEntry(
      await _readSha256Sums(downloadedFile, source: source),
      fileName: archiveName,
      source: source,
    );
    if (listedSha256 == null) {
      throw NativeArchiveDigestException(
        '$source lists no SHA-256 for $archiveName, so the hook cannot verify '
        'it. Use a release whose SHA256SUMS covers this bundle, or set '
        '$nativePathUserDefineKey to a local bundle you trust.',
      );
    }
    try {
      if (checksumFile.existsSync()) {
        await checksumFile.delete();
      }
      await downloadedFile.rename(checksumFile.path);
    } on FileSystemException catch (error) {
      log.warning(
        'Could not keep $source at ${checksumFile.path} ($error); an offline '
        'build will need it pre-seeded there.',
      );
    }
    return (sha256: listedSha256, source: source, cached: false);
  } finally {
    if (downloadedFile.existsSync()) {
      await downloadedFile.delete();
    }
  }
}

/// Reads a `SHA256SUMS` [file] as UTF-8, raising
/// [NativeArchiveDigestException] when it is not UTF-8 text.
Future<String> _readSha256Sums(File file, {required String source}) async {
  final bytes = await file.readAsBytes();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw NativeArchiveDigestException(
      '$source is not UTF-8 text. Save it as UTF-8 or ASCII, for example '
      'with `Out-File -Encoding ascii` in Windows PowerShell 5.',
    );
  }
}

String _bundleCacheDirectory({
  required String packageRoot,
  required _NativeBundleConfig nativeConfig,
  required String bundle,
}) {
  final localPath = nativeConfig.localPath;
  if (localPath != null) {
    final digest = sha1.convert(utf8.encode(localPath.toString())).toString();
    return path.join(
      packageRoot,
      _dartToolDir,
      _cacheBaseDir,
      _bundleCacheDir,
      'local',
      digest,
      nativeConfig.tag,
      bundle,
    );
  }

  if (nativeConfig.repository == _nativeRepoSlug) {
    return path.join(
      packageRoot,
      _dartToolDir,
      _cacheBaseDir,
      _bundleCacheDir,
      nativeConfig.tag,
      bundle,
    );
  }

  final segments = nativeConfig.repository.split('/');
  return path.join(
    packageRoot,
    _dartToolDir,
    _cacheBaseDir,
    _bundleCacheDir,
    'github',
    segments[0],
    segments[1],
    nativeConfig.tag,
    bundle,
  );
}

Future<Directory> _acquireLocalBundleDirectory({
  required Uri localPath,
  required String nativeTag,
  required String bundle,
  required String archiveName,
  required String cacheDir,
  required Directory extractedDir,
  required Logger log,
}) async {
  final localFilePath = localPath.toFilePath();

  final directArchive = File(localFilePath);
  if (directArchive.existsSync()) {
    return _extractLocalBundleArchive(
      archivePath: directArchive.path,
      bundle: bundle,
      cacheDir: cacheDir,
      extractedDir: extractedDir,
      log: log,
    );
  }

  for (final candidatePath in _localPathDirectoryCandidates(
    localPath: localFilePath,
    nativeTag: nativeTag,
    bundle: bundle,
  )) {
    final candidate = Directory(candidatePath);
    final candidatePaths = _collectDynamicLibraryPaths(candidate);
    if (candidatePaths.isNotEmpty &&
        _isBundleLayoutCompatible(
          bundle: bundle,
          libraryPaths: candidatePaths,
          log: log,
        )) {
      log.info('Using local native bundle directory: ${candidate.path}');
      return candidate;
    }
  }

  for (final candidatePath in _localPathArchiveCandidates(
    localPath: localFilePath,
    nativeTag: nativeTag,
    bundle: bundle,
    archiveName: archiveName,
  )) {
    final candidate = File(candidatePath);
    if (!candidate.existsSync()) {
      continue;
    }
    return _extractLocalBundleArchive(
      archivePath: candidate.path,
      bundle: bundle,
      cacheDir: cacheDir,
      extractedDir: extractedDir,
      log: log,
    );
  }

  throw Exception(
    'No compatible native bundle found at $localFilePath for $bundle. '
    'Expected a directory containing dynamic libraries, a directory containing '
    '$archiveName, or a direct path to a bundle archive.',
  );
}

List<String> _localPathDirectoryCandidates({
  required String localPath,
  required String nativeTag,
  required String bundle,
}) {
  return _dedupePaths([
    path.join(localPath, nativeTag, bundle, 'extracted'),
    path.join(localPath, nativeTag, bundle),
    path.join(localPath, bundle, 'extracted'),
    path.join(localPath, bundle),
    path.join(localPath, 'extracted'),
    localPath,
  ]);
}

List<String> _localPathArchiveCandidates({
  required String localPath,
  required String nativeTag,
  required String bundle,
  required String archiveName,
}) {
  return _dedupePaths([
    path.join(localPath, archiveName),
    path.join(localPath, nativeTag, bundle, archiveName),
    path.join(localPath, bundle, archiveName),
  ]);
}

List<String> _dedupePaths(List<String> paths) {
  final normalizedPaths = <String>[];
  final seen = <String>{};
  for (final entry in paths) {
    final normalized = path.normalize(entry);
    if (seen.add(normalized)) {
      normalizedPaths.add(normalized);
    }
  }
  return normalizedPaths;
}

Future<Directory> _extractLocalBundleArchive({
  required String archivePath,
  required String bundle,
  required String cacheDir,
  required Directory extractedDir,
  required Logger log,
}) async {
  final extractedLibraryPaths = await _extractCachedArchive(
    archivePath: archivePath,
    extractedDir: extractedDir,
    cacheDir: cacheDir,
    archiveSha256: null,
    log: log,
  );
  if (!_isBundleLayoutCompatible(
    bundle: bundle,
    libraryPaths: extractedLibraryPaths,
    log: log,
  )) {
    throw Exception(
      'Local bundle archive $archivePath is missing runtime deps.',
    );
  }
  log.info('Using local native bundle archive: $archivePath');
  return extractedDir;
}

bool _isLegacyLocalBundleEnabled() {
  final raw = Platform.environment[_allowLegacyLocalBundleEnv];
  if (raw == null) {
    return false;
  }

  final normalized = raw.trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

List<String> _localBundleCandidates({
  required String packageRoot,
  required String bundle,
}) {
  final candidates = <String>[
    path.join(packageRoot, _thirdPartyDir, _binDir, bundle),
  ];

  switch (bundle) {
    case 'android-arm64':
      candidates.add(
        path.join(packageRoot, _thirdPartyDir, _binDir, 'android', 'arm64'),
      );
      break;
    case 'android-x64':
      candidates.add(
        path.join(packageRoot, _thirdPartyDir, _binDir, 'android', 'x64'),
      );
      break;
    case 'ios-arm64':
    case 'ios-arm64-sim':
    case 'ios-x86_64-sim':
      candidates.add(path.join(packageRoot, _thirdPartyDir, _binDir, 'ios'));
      break;
    case 'linux-arm64':
      candidates.add(
        path.join(packageRoot, _thirdPartyDir, _binDir, 'linux', 'arm64'),
      );
      break;
    case 'linux-x64':
      candidates.add(
        path.join(packageRoot, _thirdPartyDir, _binDir, 'linux', 'x64'),
      );
      break;
    case 'macos-arm64':
      candidates.add(
        path.join(packageRoot, _thirdPartyDir, _binDir, 'macos', 'arm64'),
      );
      break;
    case 'macos-x86_64':
      candidates.add(
        path.join(packageRoot, _thirdPartyDir, _binDir, 'macos', 'x86_64'),
      );
      candidates.add(
        path.join(packageRoot, _thirdPartyDir, _binDir, 'macos', 'x64'),
      );
      break;
    case 'windows-arm64':
      candidates.add(
        path.join(packageRoot, _thirdPartyDir, _binDir, 'windows', 'arm64'),
      );
      break;
    case 'windows-x64':
      candidates.add(
        path.join(packageRoot, _thirdPartyDir, _binDir, 'windows', 'x64'),
      );
      break;
  }

  return candidates;
}

List<String> _collectDynamicLibraryPaths(
  Directory directory, {
  Set<String> additionalFileNames = const {},
  Set<String>? onlyFileNames,
}) {
  if (!directory.existsSync()) {
    return const [];
  }

  final paths = <String>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final baseName = path.basename(entity.path);
    if (onlyFileNames != null && !onlyFileNames.contains(baseName)) {
      continue;
    }
    final fileName = baseName.toLowerCase();
    final extension = path.extension(entity.path).toLowerCase();
    if (_dynamicLibraryExtensions.contains(extension) ||
        additionalFileNames.contains(path.basename(entity.path)) ||
        _linuxVersionedSoPattern.hasMatch(fileName)) {
      paths.add(entity.path);
    }
  }

  paths.sort();
  return paths;
}

List<String> _emittedFileNamesForLibrary({
  required NativeBundleSpec spec,
  required NativeLibraryDescriptor library,
  required _NativeBundleConfig nativeConfig,
}) {
  final fileNames = <String>[library.fileName];

  // Linux shared objects in native bundles can encode SONAME dependencies such
  // as `libllama.so.0`. Emit `.so.0` aliases so runtime dynamic loading
  // resolves those dependencies in `.dart_tool/lib`.
  if (spec.bundle.startsWith('linux-')) {
    final lowered = library.fileName.toLowerCase();
    if (lowered.endsWith('.so') && !lowered.endsWith('.so.0')) {
      fileNames.add('${library.fileName}.0');
    }
    // Historical b-tag artifacts and the original v0.2.0 artifact can encode
    // mtmd's literal placeholder as their ELF SONAME. v0.2.0-1 corrected it.
    final needsMtmdSoversionAlias =
        nativeConfig.tag.startsWith('b') || nativeConfig.tag == 'v0.2.0';
    if (lowered == 'libmtmd.so' && needsMtmdSoversionAlias) {
      fileNames.add('${library.fileName}.SOVERSION');
    }
  }

  return fileNames;
}

bool _isBundleLayoutCompatible({
  required String bundle,
  required List<String> libraryPaths,
  required Logger log,
}) {
  if (libraryPaths.isEmpty) {
    return false;
  }

  if (bundle != 'windows-x64') {
    return true;
  }

  final fileNames = libraryPaths
      .map((entry) => path.basename(entry).toLowerCase())
      .toSet();

  if (_hasWindowsBackendModule(fileNames, 'cuda')) {
    final hasCudart = fileNames.any(_windowsCudartPattern.hasMatch);
    final hasCublas = fileNames.any(_windowsCublasPattern.hasMatch);
    if (!hasCudart || !hasCublas) {
      log.warning(
        'Windows CUDA backend module detected without required runtime '
        'dependencies (cudart/cublas).',
      );
      return false;
    }
  }

  if (_hasWindowsBackendModule(fileNames, 'blas')) {
    final hasOpenBlas = fileNames.any((name) => name.contains('openblas'));
    if (!hasOpenBlas) {
      log.warning(
        'Windows BLAS backend module detected without openblas runtime.',
      );
      return false;
    }
  }

  return true;
}

bool _hasWindowsBackendModule(Set<String> fileNames, String backend) {
  for (final fileName in fileNames) {
    if (!fileName.endsWith('.dll')) {
      continue;
    }
    if (!fileName.startsWith('ggml-$backend')) {
      continue;
    }
    return true;
  }
  return false;
}

/// Extracts [archivePath] into [extractedDir] and, given the archive's
/// [archiveSha256], writes the marker that lets a later build reuse the
/// extraction beside that archive.
Future<List<String>> _extractCachedArchive({
  required String archivePath,
  required Directory extractedDir,
  required String cacheDir,
  required String? archiveSha256,
  required Logger log,
}) async {
  final tmpExtractDir = Directory(path.join(cacheDir, 'extracting'));
  if (tmpExtractDir.existsSync()) {
    await tmpExtractDir.delete(recursive: true);
  }
  await tmpExtractDir.create(recursive: true);

  await _extractArchive(
    archivePath: archivePath,
    outputDirectory: tmpExtractDir.path,
    log: log,
  );

  final extractedLibraryPaths = _collectDynamicLibraryPaths(tmpExtractDir);
  if (extractedLibraryPaths.isEmpty) {
    throw Exception(
      'Downloaded bundle archive contains no dynamic libs: $archivePath',
    );
  }

  if (extractedDir.existsSync()) {
    await extractedDir.delete(recursive: true);
  }
  await tmpExtractDir.rename(extractedDir.path);
  if (archiveSha256 != null) {
    await writeNativeExtractionMarker(
      extractedDir: extractedDir,
      archive: File(archivePath),
      archiveSha256: archiveSha256,
    );
  }

  log.info('Extracted native bundle to ${extractedDir.path}');
  return extractedLibraryPaths;
}

Future<void> _downloadReleaseAsset({
  required String repository,
  required String nativeTag,
  required String assetName,
  required String destinationPath,
  required Logger log,
}) async {
  final url =
      'https://github.com/$repository/releases/download/$nativeTag/$assetName';
  log.info('Downloading native bundle: $url');

  await _downloadRuntimeBundle(
    url: url,
    destination: File(destinationPath),
    description: 'native bundle',
    log: log,
  );
}

Future<void> _downloadRuntimeBundle({
  required String url,
  required File destination,
  required String description,
  required Logger log,
  int maxAttempts = _runtimeBundleDownloadMaxAttempts,
  Duration requestTimeout = _runtimeBundleDownloadRequestTimeout,
  Duration transferTimeout = _runtimeBundleDownloadTransferTimeout,
  Duration retryBaseDelay = _runtimeBundleDownloadRetryBaseDelay,
  bool useCurlFallback = true,
  http.Client Function()? createClient,
  RuntimeBundleDownloadFallbackForTesting? curlFallback,
}) async {
  await destination.parent.create(recursive: true);

  Exception? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await _downloadRuntimeBundleOnce(
        url: url,
        destination: destination,
        requestTimeout: requestTimeout,
        transferTimeout: transferTimeout,
        createClient: createClient,
      );
      log.info('Saved $description to ${destination.path}');
      return;
    } on Exception catch (error) {
      lastError = error;
      final isRetryable = _isRetryableRuntimeBundleDownloadError(error);
      if (!isRetryable) {
        if (attempt == 1) {
          rethrow;
        }
        throw Exception(
          'Failed to download $url after $attempt attempts: $error',
        );
      }
      if (attempt == maxAttempts) {
        break;
      }

      final retryDelay = Duration(
        microseconds: retryBaseDelay.inMicroseconds * attempt,
      );
      log.warning(
        '$description download failed ($error); retrying in '
        '${retryDelay.inSeconds}s '
        '(attempt ${attempt + 1}/$maxAttempts).',
      );
      await Future<void>.delayed(retryDelay);
    }
  }

  if (useCurlFallback &&
      lastError != null &&
      await (curlFallback ?? _downloadRuntimeBundleWithCurl)(
        url: url,
        destination: destination,
        description: description,
        log: log,
      )) {
    log.info('Saved $description to ${destination.path}');
    return;
  }

  throw Exception(
    'Failed to download $url after $maxAttempts attempts: $lastError',
  );
}

Future<void> _downloadRuntimeBundleOnce({
  required String url,
  required File destination,
  required Duration requestTimeout,
  required Duration transferTimeout,
  required http.Client Function()? createClient,
}) async {
  final client =
      (createClient ??
      Zone.current[_runtimeBundleHttpClientZoneKey]
          as http.Client Function()? ??
      http.Client.new)();
  final temporaryDestination = File('${destination.path}.tmp');
  try {
    if (temporaryDestination.existsSync()) {
      await temporaryDestination.delete();
    }

    final request = http.Request('GET', Uri.parse(url));
    request.headers[HttpHeaders.acceptHeader] = 'application/octet-stream';
    request.headers[HttpHeaders.userAgentHeader] = 'llamadart-build-hook';
    final sendFuture = client.send(request);
    unawaited(sendFuture.then<void>((_) {}, onError: (_, _) {}));
    final response = await sendFuture.timeout(
      requestTimeout,
      onTimeout: () {
        client.close();
        throw TimeoutException(
          'Runtime bundle request timed out after '
          '${requestTimeout.inSeconds}s.',
          requestTimeout,
        );
      },
    );
    if (response.statusCode != 200) {
      throw _RuntimeBundleDownloadHttpException(url, response.statusCode);
    }

    final sink = temporaryDestination.openWrite();
    var sinkClosed = false;
    try {
      await _writeRuntimeBundleResponse(
        stream: response.stream,
        sink: sink,
        timeout: transferTimeout,
      );
      await sink.close();
      sinkClosed = true;
    } finally {
      if (!sinkClosed) {
        try {
          await sink.close();
        } catch (_) {
          // Preserve the original write or close failure; this is cleanup.
        }
      }
    }

    if (destination.existsSync()) {
      await destination.delete();
    }
    await temporaryDestination.rename(destination.path);
  } finally {
    client.close();
    if (temporaryDestination.existsSync()) {
      await temporaryDestination.delete();
    }
  }
}

final _runtimeBundleHttpClientZoneKey = Object();

/// Runs [body] with every runtime download the hook makes served by clients
/// from [createClient].
///
/// This is intended for hook tests that drive the build hook entrypoint
/// offline; production code never sets it.
Future<T> withRuntimeBundleHttpClientForTesting<T>(
  http.Client Function() createClient,
  Future<T> Function() body,
) {
  return runZoned(
    body,
    zoneValues: {_runtimeBundleHttpClientZoneKey: createClient},
  );
}

final _clockZoneKey = Object();

DateTime _now() =>
    (Zone.current[_clockZoneKey] as DateTime Function()?)?.call() ??
    DateTime.now();

/// Runs [body] with the hook's clock reading [now], so tests can tell this
/// machine's clock from the file system's.
///
/// This is intended for hook tests; production code never sets it.
Future<T> withClockForTesting<T>(
  DateTime Function() now,
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_clockZoneKey: now});
}

/// Downloads a runtime bundle through the hardened build-hook download path.
///
/// This is intended for hook tests that need shorter retry delays and timeouts;
/// production code should use the build hook entrypoint.
Future<void> downloadRuntimeBundleForTesting({
  required String url,
  required File destination,
  required String description,
  required Logger log,
  int maxAttempts = _runtimeBundleDownloadMaxAttempts,
  Duration requestTimeout = _runtimeBundleDownloadRequestTimeout,
  Duration transferTimeout = _runtimeBundleDownloadTransferTimeout,
  Duration retryBaseDelay = _runtimeBundleDownloadRetryBaseDelay,
  bool useCurlFallback = false,
  http.Client Function()? createClient,
  RuntimeBundleDownloadFallbackForTesting? curlFallback,
}) {
  return _downloadRuntimeBundle(
    url: url,
    destination: destination,
    description: description,
    log: log,
    maxAttempts: maxAttempts,
    requestTimeout: requestTimeout,
    transferTimeout: transferTimeout,
    retryBaseDelay: retryBaseDelay,
    useCurlFallback: useCurlFallback,
    createClient: createClient,
    curlFallback: curlFallback,
  );
}

Future<void> _writeRuntimeBundleResponse({
  required Stream<List<int>> stream,
  required IOSink sink,
  required Duration timeout,
}) async {
  final completed = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
  subscription = stream.listen(
    (chunk) {
      sink.add(chunk);
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completed.isCompleted) {
        completed.completeError(error, stackTrace);
      }
    },
    onDone: () {
      if (!completed.isCompleted) {
        completed.complete();
      }
    },
    cancelOnError: true,
  );
  final timeoutTimer = Timer(timeout, () {
    final timeoutError = TimeoutException(
      'Runtime bundle body download timed out after ${timeout.inSeconds}s.',
      timeout,
    );
    final timeoutStackTrace = StackTrace.current;
    unawaited(
      subscription.cancel().catchError((_) {}).whenComplete(() {
        if (!completed.isCompleted) {
          completed.completeError(timeoutError, timeoutStackTrace);
        }
      }),
    );
  });

  try {
    await completed.future;
  } finally {
    timeoutTimer.cancel();
  }
}

Future<bool> _downloadRuntimeBundleWithCurl({
  required String url,
  required File destination,
  required String description,
  required Logger log,
}) async {
  final temporaryDestination = File('${destination.path}.curl.tmp');
  try {
    if (temporaryDestination.existsSync()) {
      await temporaryDestination.delete();
    }

    log.warning(
      'Trying curl fallback for $description after Dart HTTP retries failed.',
    );
    final result = await Process.run('curl', [
      '--fail',
      '--location',
      '--retry',
      '5',
      '--retry-delay',
      '3',
      '--connect-timeout',
      '30',
      '--max-time',
      '600',
      '--silent',
      '--show-error',
      '--header',
      'Accept: application/octet-stream',
      '--header',
      'User-Agent: llamadart-build-hook',
      '--output',
      temporaryDestination.path,
      url,
    ]);
    if (result.exitCode != 0) {
      log.warning(
        'curl fallback failed for $description with exit code '
        '${result.exitCode}: ${result.stderr}',
      );
      return false;
    }

    if (destination.existsSync()) {
      await destination.delete();
    }
    await temporaryDestination.rename(destination.path);
    return true;
  } on ProcessException catch (error) {
    log.warning('curl fallback unavailable for $description: $error');
    return false;
  } finally {
    if (temporaryDestination.existsSync()) {
      await temporaryDestination.delete();
    }
  }
}

bool _isRetryableRuntimeBundleDownloadError(Exception error) {
  if (error is _RuntimeBundleDownloadHttpException) {
    return error.statusCode == 408 ||
        error.statusCode == 429 ||
        (error.statusCode >= 500 && error.statusCode < 600);
  }
  return error is http.ClientException ||
      error is SocketException ||
      error is HandshakeException ||
      error is HttpException ||
      error is TimeoutException;
}

final class _RuntimeBundleDownloadHttpException implements Exception {
  const _RuntimeBundleDownloadHttpException(this.url, this.statusCode);

  final String url;
  final int statusCode;

  @override
  String toString() => 'Failed to download $url ($statusCode).';
}

/// Extracts a native bundle archive through the hardened build-hook path.
///
/// This is intended for hook tests that need to assert extraction behaviour;
/// production code should use the build hook entrypoint.
Future<void> extractArchiveForTesting({
  required String archivePath,
  required String outputDirectory,
  required Logger log,
}) {
  return _extractArchive(
    archivePath: archivePath,
    outputDirectory: outputDirectory,
    log: log,
  );
}

Future<void> _extractArchive({
  required String archivePath,
  required String outputDirectory,
  required Logger log,
}) async {
  final outputRoot = path.normalize(path.absolute(outputDirectory));
  final archiveBytes = await File(archivePath).readAsBytes();

  Archive archive;
  try {
    archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(archiveBytes));
  } catch (error) {
    log.severe('Failed to decode archive $archivePath: $error');
    throw Exception('Failed to decode native bundle archive: $archivePath');
  }

  // An archive may repeat a normalized path (GNU tar emits `./`-prefixed names)
  // and may even switch its kind between repeats, so the whole archive is
  // scanned for traversal and deduplicated before anything touches the disk.
  // Only the last entry for a path decides whether it lands as a directory, a
  // regular file, or a materialized link alias.
  final entriesByArchivePath = <String, ArchiveFile>{};
  final targetPathsByArchivePath = <String, String>{};
  final winningEntryIndexes = <String, int>{};
  final archiveRelativePaths = <String>[];

  for (var index = 0; index < archive.files.length; index++) {
    final file = archive.files[index];
    final relativePath = path.normalize(file.name);
    final targetPath = path.normalize(path.join(outputRoot, relativePath));
    final isInRoot =
        targetPath == outputRoot || path.isWithin(outputRoot, targetPath);

    if (!isInRoot) {
      throw Exception(
        'Archive traversal entry blocked for $archivePath: ${file.name}',
      );
    }

    // `./` directory entries are normal in GNU tar output, but a regular file
    // or symlink named `.` would make extraction delete the output root and
    // replace it with a file, so it is rejected before anything touches disk.
    if (targetPath == outputRoot && !file.isDirectory) {
      throw Exception(
        'Archive root replacement entry blocked for $archivePath: ${file.name}',
      );
    }

    final archiveRelativePath = path.posix.joinAll(path.split(relativePath));
    entriesByArchivePath[archiveRelativePath] = file;
    targetPathsByArchivePath[archiveRelativePath] = targetPath;
    winningEntryIndexes[archiveRelativePath] = index;
    archiveRelativePaths.add(archiveRelativePath);
  }

  // Symbolic links are materialized after the extraction loop so link targets
  // that appear later in the archive still resolve.
  final symbolicLinkPaths = <String>[];

  for (var index = 0; index < archive.files.length; index++) {
    final archiveRelativePath = archiveRelativePaths[index];
    if (winningEntryIndexes[archiveRelativePath] != index) {
      continue;
    }

    final file = archive.files[index];
    final targetPath = targetPathsByArchivePath[archiveRelativePath]!;

    if (file.isDirectory) {
      await _createExtractionDirectory(targetPath);
      continue;
    }

    if (file.isSymbolicLink) {
      symbolicLinkPaths.add(archiveRelativePath);
      continue;
    }

    await _writeExtractionFile(targetPath, file.content as List<int>);
  }

  for (final linkPath in symbolicLinkPaths) {
    final resolved = _resolveArchiveSymlink(
      archivePath: archivePath,
      linkPath: linkPath,
      entriesByArchivePath: entriesByArchivePath,
    );

    final linkFilePath = targetPathsByArchivePath[linkPath]!;

    // Archive symlinks are materialized as regular files holding the resolved
    // target's bytes rather than as OS symlinks: Windows refuses symlink
    // creation without developer mode or elevation, and bundled native assets
    // are copied around by downstream tooling that would not carry a link.
    await _writeExtractionFile(
      linkFilePath,
      resolved.entry.content as List<int>,
    );
    log.fine(
      'Materialized archive symlink $linkPath as a copy of ${resolved.path}.',
    );
  }
}

/// Creates [targetPath] as a directory, replacing a file left by an earlier
/// entry for the same normalized path.
Future<void> _createExtractionDirectory(String targetPath) async {
  final existingType = await FileSystemEntity.type(
    targetPath,
    followLinks: false,
  );
  if (existingType == FileSystemEntityType.file ||
      existingType == FileSystemEntityType.link) {
    await File(targetPath).delete();
  }
  await Directory(targetPath).create(recursive: true);
}

/// Writes [bytes] to [targetPath], replacing a directory left by an earlier
/// entry for the same normalized path.
Future<void> _writeExtractionFile(String targetPath, List<int> bytes) async {
  await Directory(path.dirname(targetPath)).create(recursive: true);
  final existingType = await FileSystemEntity.type(
    targetPath,
    followLinks: false,
  );
  if (existingType == FileSystemEntityType.directory) {
    await Directory(targetPath).delete(recursive: true);
  }
  await File(targetPath).writeAsBytes(bytes);
}

typedef _ResolvedArchiveEntry = ({String path, ArchiveFile entry});

/// Follows an archive-internal symlink chain to the regular file it points at.
///
/// Throws when the chain escapes the archive root, cycles, dangles, or lands on
/// a directory, so a malicious or truncated bundle cannot write outside the
/// extraction root or leave unloadable placeholder libraries behind.
_ResolvedArchiveEntry _resolveArchiveSymlink({
  required String archivePath,
  required String linkPath,
  required Map<String, ArchiveFile> entriesByArchivePath,
}) {
  final visited = <String>{};
  var currentPath = linkPath;
  var current = entriesByArchivePath[currentPath]!;

  while (current.isSymbolicLink) {
    if (!visited.add(currentPath)) {
      throw Exception(
        'Archive symlink cycle blocked for $archivePath: $linkPath',
      );
    }

    final target = current.symbolicLink!;
    final resolvedPath = path.posix.normalize(
      path.posix.join(path.posix.dirname(currentPath), target),
    );
    if (path.posix.isAbsolute(target) ||
        path.isAbsolute(target) ||
        resolvedPath == '..' ||
        resolvedPath.startsWith('../')) {
      throw Exception(
        'Archive symlink traversal blocked for $archivePath: '
        '$linkPath -> $target',
      );
    }

    final next = entriesByArchivePath[resolvedPath];
    if (next == null) {
      throw Exception(
        'Archive symlink target missing in $archivePath: $linkPath -> $target',
      );
    }

    if (next.isDirectory) {
      throw Exception(
        'Archive symlink target is a directory in $archivePath: '
        '$linkPath -> $target',
      );
    }

    currentPath = resolvedPath;
    current = next;
  }

  return (path: currentPath, entry: current);
}
