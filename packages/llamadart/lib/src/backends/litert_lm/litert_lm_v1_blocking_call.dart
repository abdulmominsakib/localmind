import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../core/exceptions.dart';
import 'litert_lm_blocking_call.dart';
import 'litert_lm_last_error.dart';

/// Scalar addresses only; the owning client must retain the loaded library.
typedef LiteRtLmV1ErrorAddresses = ({int message, int clear});

/// A sendable request for a status/out constructor with one configuration.
typedef LiteRtLmV1CreateRequest = ({
  int createAddress,
  int configAddress,
  int deleteAddress,
  LiteRtLmV1ErrorAddresses errors,
  List<String> diagnosticPaths,
});

/// Explicit native completion, with any failing partial owner already deleted.
final class LiteRtLmV1CreateResult {
  /// Captures a returned status and an owner only on native success.
  const LiteRtLmV1CreateResult({
    required this.status,
    required this.ownerAddress,
    required this.nativeError,
  });

  /// Canonical status returned by the constructor.
  final int status;

  /// Successful owner address, or zero for a failure or null-success result.
  final int ownerAddress;

  /// Copied, redacted failure detail from the calling native thread.
  final String? nativeError;
}

/// Injection boundary for testing loss of the completion receipt.
typedef LiteRtLmV1CreateRunner =
    Future<LiteRtLmBlockingCallResult<LiteRtLmV1CreateResult>> Function(
      LiteRtLmV1CreateRequest request,
    );

typedef _ErrorMessageNative = Pointer<Utf8> Function();
typedef _ErrorClearNative = Void Function();

/// Canonical v1 message/clear functions, reconstructed on the calling thread.
/// Error status comes from the operation, never the removed legacy code getter.
final class LiteRtLmV1LastError {
  LiteRtLmV1LastError._(this._message, this._clear);
  final Pointer<Utf8> Function() _message;
  final void Function() _clear;

  /// Clears only the calling thread's previous error.
  void clear() => _clear();

  /// Copies and redacts this thread's error using the operation's [status].
  String describe({required int status, Iterable<String> paths = const []}) {
    final pointer = _message();
    return liteRtLmNativeErrorDetail(
      code: status,
      message: pointer == nullptr ? '' : pointer.toDartString(),
      paths: paths,
    );
  }
}

/// Resolves canonical error exports without sending library objects.
LiteRtLmV1ErrorAddresses liteRtLmV1ErrorAddressesForLibrary(
  DynamicLibrary library,
) {
  int required(String symbol) {
    if (!library.providesSymbol(symbol)) {
      throw LlamaUnsupportedException(
        'C API 1.0 asynchronous calls require the native error export $symbol.',
      );
    }
    return library.lookup<Void>(symbol).address;
  }

  return (
    message: required(LiteRtLmLastError.messageSymbol),
    clear: required(LiteRtLmLastError.clearSymbol),
  );
}

/// Reconstructs canonical message/clear on the synchronous native-call thread.
LiteRtLmV1LastError liteRtLmV1LastErrorFromAddresses(
  LiteRtLmV1ErrorAddresses addresses,
) {
  if (addresses.message == 0 || addresses.clear == 0) {
    throw LlamaUnsupportedException(
      'C API 1.0 requires canonical native error message and clear functions.',
    );
  }
  return LiteRtLmV1LastError._(
    Pointer<NativeFunction<_ErrorMessageNative>>.fromAddress(
      addresses.message,
    ).asFunction<Pointer<Utf8> Function()>(),
    Pointer<NativeFunction<_ErrorClearNative>>.fromAddress(
      addresses.clear,
    ).asFunction<void Function()>(),
  );
}

/// Copies failure details before cleanup can overwrite this thread's error.
String liteRtLmV1CopyError({
  required LiteRtLmV1ErrorAddresses addresses,
  required int status,
  Iterable<String> diagnosticPaths = const [],
}) => liteRtLmV1LastErrorFromAddresses(
  addresses,
).describe(status: status, paths: diagnosticPaths);

/// Runs a canonical status/out constructor in an explicit completion scope.
Future<LiteRtLmBlockingCallResult<LiteRtLmV1CreateResult>>
runLiteRtLmV1CreateFromConfig({
  required int createAddress,
  required int configAddress,
  required int deleteAddress,
  required LiteRtLmV1ErrorAddresses errors,
  List<String> diagnosticPaths = const [],
}) => runLiteRtLmV1Create((
  createAddress: createAddress,
  configAddress: configAddress,
  deleteAddress: deleteAddress,
  errors: errors,
  diagnosticPaths: List<String>.unmodifiable(diagnosticPaths),
));

/// Top-level dispatch keeps the isolate closure free of native owner objects.
Future<LiteRtLmBlockingCallResult<LiteRtLmV1CreateResult>> runLiteRtLmV1Create(
  LiteRtLmV1CreateRequest request,
) {
  final snapshot = (
    createAddress: request.createAddress,
    configAddress: request.configAddress,
    deleteAddress: request.deleteAddress,
    errors: request.errors,
    diagnosticPaths: List<String>.unmodifiable(request.diagnosticPaths),
  );
  return runLiteRtLmBlockingCall(() => _create(snapshot));
}

LiteRtLmV1CreateResult _create(LiteRtLmV1CreateRequest request) {
  // Android arm64 heap tags can set the sign bit of a non-null pointer.
  // Preserve every address bit when crossing the isolate boundary.
  if (request.createAddress == 0 ||
      request.configAddress == 0 ||
      request.deleteAddress == 0) {
    throw LlamaStateException(
      'C API 1.0 creation requires admitted native function/configuration addresses.',
    );
  }
  final create =
      Pointer<
            NativeFunction<Int Function(Pointer<Void>, Pointer<Pointer<Void>>)>
          >.fromAddress(request.createAddress)
          .asFunction<int Function(Pointer<Void>, Pointer<Pointer<Void>>)>();
  final delete =
      Pointer<NativeFunction<Void Function(Pointer<Void>)>>.fromAddress(
        request.deleteAddress,
      ).asFunction<void Function(Pointer<Void>)>();
  final output = calloc<Pointer<Void>>();
  var transferred = false;
  try {
    liteRtLmV1LastErrorFromAddresses(request.errors).clear();
    final status = create(
      Pointer<Void>.fromAddress(request.configAddress),
      output,
    );
    if (status != 0) {
      final detail = liteRtLmV1CopyError(
        addresses: request.errors,
        status: status,
        diagnosticPaths: request.diagnosticPaths,
      );
      return LiteRtLmV1CreateResult(
        status: status,
        ownerAddress: 0,
        nativeError: detail,
      );
    }
    final result = LiteRtLmV1CreateResult(
      status: status,
      ownerAddress: output.value.address,
      nativeError: null,
    );
    transferred = true;
    return result;
  } finally {
    if (!transferred && output.value != nullptr) delete(output.value);
    calloc.free(output);
  }
}
