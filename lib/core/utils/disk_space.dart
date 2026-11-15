import 'dart:ffi';

// Struct member names mirror the C ABI and cannot be lowerCamelCase.
// ignore_for_file: non_constant_identifier_names
import 'package:ffi/ffi.dart';
import 'dart:io';

/// Best-effort user-available free space on the volume holding [path], in
/// bytes. Returns null when the platform cannot answer (unsupported ABI,
/// missing symbol, implausible result) — callers must treat null as
/// "unknown" and skip the check rather than fail the download.
int? freeDiskSpaceBytes(String path) {
  try {
    if (Platform.isWindows) {
      return _freeSpaceWindows(path);
    }
    if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
      return _freeSpaceStatvfs(path);
    }
    return null;
  } catch (_) {
    return null;
  }
}

int? _freeSpaceWindows(String path) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final getDiskFreeSpaceExW = kernel32.lookupFunction<
      Int32 Function(
          Pointer<Utf16>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>),
      int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint64>)>('GetDiskFreeSpaceExW');
  final dir = path.toNativeUtf16();
  final freeToCaller = calloc<Uint64>();
  final total = calloc<Uint64>();
  final totalFree = calloc<Uint64>();
  try {
    final ok = getDiskFreeSpaceExW(dir, freeToCaller, total, totalFree);
    if (ok == 0) return null;
    final bytes = freeToCaller.value;
    return _plausible(bytes) ? bytes : null;
  } finally {
    calloc.free(dir);
    calloc.free(freeToCaller);
    calloc.free(total);
    calloc.free(totalFree);
  }
}

int? _freeSpaceStatvfs(String path) {
  // struct statvfs (LP64 ABIs: Android arm64, macOS, Linux x64/arm64):
  // f_bsize, f_frsize, f_blocks, f_bfree, f_bavail are the first five
  // unsigned-long members, so f_bavail sits at offset 32.
  final libc = DynamicLibrary.process();
  final statvfs = libc.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(
      Pointer<Utf8>)>('statvfs');
  final buf = calloc<_Statvfs64>();
  final pathNative = path.toNativeUtf8();
  try {
    if (statvfs(pathNative) != 0) return null;
    final bytes = buf.ref.f_frsize * buf.ref.f_bavail;
    return _plausible(bytes) ? bytes : null;
  } finally {
    calloc.free(buf);
    calloc.free(pathNative);
  }
}

bool _plausible(int bytes) => bytes > 0 && bytes < (1 << 47);

final class _Statvfs64 extends Struct {
  @Uint64()
  external int f_bsize;

  @Uint64()
  external int f_frsize;

  @Uint64()
  external int f_blocks;

  @Uint64()
  external int f_bfree;

  @Uint64()
  external int f_bavail;
}
