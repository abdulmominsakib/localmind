import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart'
    as runtime;

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

  final opened = _openLiteRtLmLibrary();
  final library = opened.library;
  for (final symbol in _requiredSymbols) {
    library.lookup<NativeFunction<Void Function()>>(symbol);
  }

  print(
    'RESULT litert_lm_library ${jsonEncode({'abi': Abi.current().toString(), 'library': opened.path, 'symbols': _requiredSymbols})}',
  );
}

bool _isSupportedHost() {
  final abi = Abi.current();
  return (Platform.isLinux && (abi == Abi.linuxX64 || abi == Abi.linuxArm64)) ||
      (Platform.isWindows && abi == Abi.windowsX64);
}

({String path, DynamicLibrary library}) _openLiteRtLmLibrary() {
  final envDir = Platform.environment[_litertLmLibDirEnv];
  if (envDir != null && envDir.isNotEmpty) {
    final primary = _primaryLibraryFileName();
    if (primary == null) {
      throw UnsupportedError('LiteRT-LM does not support ${Abi.current()}.');
    }

    for (final companion
        in runtime
            .liteRtLmRequiredLibrariesForAbi(Abi.current())
            .where((library) => library != primary)) {
      DynamicLibrary.open('$envDir/$companion');
    }

    final path = '$envDir/$primary';
    return (path: path, library: DynamicLibrary.open(path));
  }

  return (
    path: _liteRtLmAssetId,
    library: DynamicLibrary.open(_liteRtLmAssetId),
  );
}

String? _primaryLibraryFileName() {
  final abi = Abi.current();
  return switch (abi) {
    Abi.linuxArm64 || Abi.linuxX64 => 'libLiteRtLm.so',
    Abi.windowsX64 => 'LiteRtLm.dll',
    _ => null,
  };
}
