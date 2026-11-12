import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_c_api_version.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_platform.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart'
    as runtime;
import 'package:llamadart/src/hook/native_release_pins.dart';

const _liteRtLmAssetId = 'package:llamadart/litert_lm_LiteRtLm';
const _litertLmLibDirEnv = 'LLAMADART_LITERT_LM_LIB_DIR';
const _requiredSymbols = <String>[
  'litert_lm_engine_settings_create',
  'litert_lm_engine_create',
  'litert_lm_engine_delete',
  'stream_proxy_create',
  'stream_proxy_free_string',
  'stream_proxy_delete',
];

void main() {
  if (!_isSupportedHost()) {
    stderr.writeln(
      'LiteRT-LM library smoke does not support ${Abi.current()}.',
    );
    exitCode = 64;
    return;
  }

  print(
    'RESULT litert_lm_library ${jsonEncode(runLiteRtLmLibrarySmoke(abi: Abi.current(), directory: Platform.environment[_litertLmLibDirEnv], releaseTag: liteRtLmReleaseTag))}',
  );
}

/// Opens the runtime, checks its symbols and in-process LiteRT marker, and
/// returns the RESULT payload.
Map<String, Object?> runLiteRtLmLibrarySmoke({
  required Abi abi,
  required String? directory,
  required String releaseTag,
  DynamicLibrary Function(String)? openLibrary,
}) {
  final opened = openLiteRtLmSmokeLibrary(
    directory: directory,
    abi: abi,
    cApiV1: liteRtLmSmokeUsesCApiV1(releaseTag),
    openLibrary: openLibrary,
  );
  final library = opened.library;
  for (final symbol in _requiredSymbols) {
    library.lookup<NativeFunction<Void Function()>>(symbol);
  }

  return {
    'abi': abi.toString(),
    'library': opened.path,
    'symbols': _requiredSymbols,
    'inProcessLiteRtAbi': requireInProcessLiteRtMarker(library, abi),
  };
}

/// Fails when a bundled Linux or Windows runtime does not report in-process
/// LiteRT, which gates native embeddings there; a repin that drops the
/// `litert_lm_native_in_process_litert_abi_version` export would otherwise
/// surface only on hardware. Returns the reported value, or null where the
/// marker is not required.
int? requireInProcessLiteRtMarker(DynamicLibrary library, Abi abi) {
  if (abi != Abi.linuxX64 && abi != Abi.linuxArm64 && abi != Abi.windowsX64) {
    return null;
  }
  final reported = readLiteRtLmInProcessLiteRtAbiVersion(library);
  if (reported != liteRtLmInProcessLiteRtAbiVersion) {
    throw StateError(
      'The $abi LiteRT-LM runtime reports '
      'litert_lm_native_in_process_litert_abi_version '
      '${reported ?? '(not exported)'}, expected '
      '$liteRtLmInProcessLiteRtAbiVersion.',
    );
  }
  return reported;
}

bool _isSupportedHost() {
  final abi = Abi.current();
  return (Platform.isLinux && (abi == Abi.linuxX64 || abi == Abi.linuxArm64)) ||
      (Platform.isMacOS && abi == Abi.macosArm64) ||
      (Platform.isWindows && abi == Abi.windowsX64);
}

/// Selects only a reviewed release's required smoke inventory.
bool liteRtLmSmokeUsesCApiV1(String releaseTag) {
  return switch (releaseTag) {
    'v0.19.0' ||
    'v0.19.1' ||
    'v0.19.1-1' ||
    'v0.19.1-2' ||
    'v0.19.1-3' ||
    'v0.19.1-4' => true,
    'v0.18.1-4' => false,
    _ => throw UnsupportedError(
      'LiteRT-LM library smoke has no reviewed C API inventory for $releaseTag.',
    ),
  };
}

/// Opens the smoke runtime with the same dependency handling as production.
({String path, DynamicLibrary library, List<DynamicLibrary> companions})
openLiteRtLmSmokeLibrary({
  required String? directory,
  required Abi abi,
  bool cApiV1 = false,
  DynamicLibrary Function(String)? openLibrary,
}) {
  final open = openLibrary ?? DynamicLibrary.open;
  final envDir = directory;
  if (envDir != null && envDir.isNotEmpty) {
    final primary = _primaryLibraryFileName(abi);
    if (primary == null) {
      throw UnsupportedError('LiteRT-LM does not support $abi.');
    }

    final companionPaths = [
      for (final library in runtime.liteRtLmCompanionLibrariesForAbi(
        abi,
        cApiV1: cApiV1,
      ))
        '$envDir/$library',
    ];
    // Production discovery can skip absent optional candidates; the smoke
    // must fail if any required inventory entry is missing.
    for (final library in runtime.liteRtLmRequiredLibrariesForAbi(
      abi,
      cApiV1: cApiV1,
    )) {
      final file = '$envDir/$library';
      if (!File(file).existsSync()) {
        throw StateError('Required LiteRT-LM smoke library is missing: $file');
      }
    }
    final companions = runtime.liteRtLmOpenCompanionLibraries(
      companionPaths,
      openLibrary: open,
    );
    final path = '$envDir/$primary';
    return (path: path, library: open(path), companions: companions);
  }

  return (
    path: _liteRtLmAssetId,
    library: open(_liteRtLmAssetId),
    companions: const <DynamicLibrary>[],
  );
}

String? _primaryLibraryFileName(Abi abi) {
  return switch (abi) {
    Abi.linuxArm64 || Abi.linuxX64 => 'libLiteRtLm.so',
    Abi.macosArm64 => 'libLiteRtLm.dylib',
    Abi.windowsX64 => 'LiteRtLm.dll',
    _ => null,
  };
}
