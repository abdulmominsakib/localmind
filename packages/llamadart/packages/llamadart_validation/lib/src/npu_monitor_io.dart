import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'npu_evidence.dart';

/// Reads the probe already packaged and hash-checked by the Android host.
class AndroidNpuMonitor implements NpuExecutionMonitor {
  AndroidNpuMonitor(this.dispatchDirectory, String library, this.identity) {
    if (!Platform.isAndroid || p.basename(library) != library) {
      throw UnsupportedError('NPU probe requires an installed Android library');
    }
    _snapshot = DynamicLibrary.open(p.join(dispatchDirectory, library))
        .lookupFunction<
          Int32 Function(Pointer<Uint64>, Size),
          int Function(Pointer<Uint64>, int)
        >('LlamadartNpuProbeSnapshot');
  }

  @override
  final String dispatchDirectory;
  @override
  final Map<String, dynamic> identity;
  late final int Function(Pointer<Uint64>, int) _snapshot;

  @override
  List<int> snapshot() {
    final buffer = calloc<Uint64>(7);
    try {
      if (_snapshot(buffer, 7) != 0) {
        throw StateError('NPU probe snapshot failed');
      }
      return List<int>.generate(7, (i) => buffer[i]);
    } finally {
      calloc.free(buffer);
    }
  }
}
