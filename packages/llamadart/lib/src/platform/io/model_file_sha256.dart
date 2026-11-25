import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import '../../core/exceptions.dart';

/// Verifies file contents off the caller isolate, using system SHA-256 on Apple.
///
/// The portable implementation remains available when system symbols are absent.
Future<String> modelFileSha256(
  File file, {
  bool usePlatformAcceleration = true,
}) {
  final filePath = file.path;
  return Isolate.run(() async {
    final source = File(filePath);
    final native = usePlatformAcceleration ? _AppleSha256.tryCreate() : null;
    if (native != null) {
      return native.hash(source);
    }
    return (await sha256.bind(source.openRead()).first).toString();
  });
}

// CommonDigest.h defines CC_SHA256_CTX as 26 CC_LONG (uint32_t) words.
final class _Sha256Context extends Struct {
  @Array(26)
  external Array<Uint32> words;
}

typedef _InitNative = Int32 Function(Pointer<_Sha256Context>);
typedef _Init = int Function(Pointer<_Sha256Context>);
typedef _UpdateNative =
    Int32 Function(Pointer<_Sha256Context>, Pointer<Uint8>, Uint32);
typedef _Update = int Function(Pointer<_Sha256Context>, Pointer<Uint8>, int);
typedef _FinalNative = Int32 Function(Pointer<Uint8>, Pointer<_Sha256Context>);
typedef _Final = int Function(Pointer<Uint8>, Pointer<_Sha256Context>);

final class _AppleSha256 {
  _AppleSha256(DynamicLibrary library)
    : _init = library.lookupFunction<_InitNative, _Init>('CC_SHA256_Init'),
      _update = library.lookupFunction<_UpdateNative, _Update>(
        'CC_SHA256_Update',
      ),
      _final = library.lookupFunction<_FinalNative, _Final>('CC_SHA256_Final');

  final _Init _init;
  final _Update _update;
  final _Final _final;

  static _AppleSha256? tryCreate() {
    if (!Platform.isMacOS && !Platform.isIOS) {
      return null;
    }
    try {
      return _AppleSha256(DynamicLibrary.open('/usr/lib/libSystem.B.dylib'));
    } on ArgumentError {
      return null;
    }
  }

  String hash(File file) {
    final context = calloc<_Sha256Context>();
    final buffer = calloc<Uint8>(1024 * 1024);
    final digest = calloc<Uint8>(32);
    RandomAccessFile? input;
    try {
      input = file.openSync();
      final bytes = buffer.asTypedList(1024 * 1024);
      _check(_init(context));
      while (true) {
        final count = input.readIntoSync(bytes);
        if (count == 0) {
          break;
        }
        _check(_update(context, buffer, count));
      }
      _check(_final(digest, context));
      return digest
          .asTypedList(32)
          .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
    } finally {
      try {
        input?.closeSync();
      } finally {
        calloc.free(context);
        calloc.free(buffer);
        calloc.free(digest);
      }
    }
  }

  static void _check(int result) {
    if (result != 1) {
      throw LlamaModelException('System SHA-256 verification failed.');
    }
  }
}
