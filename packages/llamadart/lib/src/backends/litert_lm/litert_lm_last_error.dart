import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../../core/url_redaction.dart';

typedef _MessageNative = Pointer<Utf8> Function();
typedef _CodeNative = Int Function();
typedef _CodeDart = int Function();
typedef _ClearNative = Void Function();
typedef _ClearDart = void Function();

/// Looks up the address of a native [symbol], or returns null when the
/// runtime does not export it.
typedef LiteRtLmSymbolLookup = Pointer<Void>? Function(String symbol);

// `absl::StatusCode` names, which LiteRT-LM's `LiteRtLmStatusCode` mirrors.
const _statusNames = <int, String>{
  1: 'CANCELLED',
  2: 'UNKNOWN',
  3: 'INVALID_ARGUMENT',
  4: 'DEADLINE_EXCEEDED',
  5: 'NOT_FOUND',
  6: 'ALREADY_EXISTS',
  7: 'PERMISSION_DENIED',
  8: 'RESOURCE_EXHAUSTED',
  9: 'FAILED_PRECONDITION',
  10: 'ABORTED',
  11: 'OUT_OF_RANGE',
  12: 'UNIMPLEMENTED',
  13: 'INTERNAL',
  14: 'UNAVAILABLE',
  15: 'DATA_LOSS',
  16: 'UNAUTHENTICATED',
};

/// The error LiteRT-LM records for a failed C API call, read through
/// `litert_lm_get_last_error_message` and `litert_lm_get_last_error_code`.
///
/// LiteRT-LM v0.18.0 added these with `litert_lm_clear_last_error`; an older
/// runtime exports none of them. The state is per OS thread and survives
/// later successful calls, so [clear], the guarded call and [describe] run in
/// one synchronous stretch of the same isolate.
final class LiteRtLmLastError {
  LiteRtLmLastError._(this._message, this._code, this._clear);

  /// `litert_lm_get_last_error_message`.
  static const String messageSymbol = 'litert_lm_get_last_error_message';

  /// `litert_lm_get_last_error_code`.
  static const String codeSymbol = 'litert_lm_get_last_error_code';

  /// `litert_lm_clear_last_error`.
  static const String clearSymbol = 'litert_lm_clear_last_error';

  final Pointer<Utf8> Function() _message;
  final _CodeDart _code;
  final _ClearDart _clear;

  /// Returns the API when [lookup] resolves all three symbols, or null when
  /// any is missing, as on runtimes before LiteRT-LM v0.18.0.
  static LiteRtLmLastError? probe(LiteRtLmSymbolLookup lookup) {
    final message = lookup(messageSymbol);
    final code = lookup(codeSymbol);
    final clear = lookup(clearSymbol);
    if (message == null || code == null || clear == null) {
      return null;
    }
    return LiteRtLmLastError._(
      message
          .cast<NativeFunction<_MessageNative>>()
          .asFunction<Pointer<Utf8> Function()>(),
      code.cast<NativeFunction<_CodeNative>>().asFunction<_CodeDart>(),
      clear.cast<NativeFunction<_ClearNative>>().asFunction<_ClearDart>(),
    );
  }

  /// [probe] against the symbols [library] exports.
  static LiteRtLmLastError? probeLibrary(DynamicLibrary library) =>
      probe((symbol) {
        try {
          return library.lookup<Void>(symbol);
        } on ArgumentError {
          return null;
        }
      });

  /// Clears the error recorded on this thread, so that [describe] after the
  /// next call reports only that call.
  void clear() => _clear();

  /// Describes the error recorded on this thread with
  /// [liteRtLmNativeErrorDetail], or returns null when none is recorded.
  ///
  /// Call it only after a call reported failure: LiteRT-LM does not clear the
  /// error on success.
  String? describe({Iterable<String?> paths = const <String?>[]}) {
    final code = _code();
    final pointer = _message();
    final message = pointer == nullptr
        ? ''
        : utf8.decode(
            pointer.cast<Uint8>().asTypedList(pointer.length),
            allowMalformed: true,
          );
    if (code == 0 && message.trim().isEmpty) {
      return null;
    }
    return liteRtLmNativeErrorDetail(
      code: code,
      message: message,
      paths: paths,
    );
  }
}

/// Formats a LiteRT-LM error [code] and [message] for an exception message.
///
/// Each of [paths], typically the model, cache and adapter paths of the
/// failing call, and its directory are cut to their base names wherever
/// [message] contains them, as given or resolved through symbolic links, with
/// either separator, and URL credentials are redacted, so that the error
/// carries no directory or signed-URL secrets. Whitespace runs then become
/// single spaces.
String liteRtLmNativeErrorDetail({
  required int code,
  required String message,
  Iterable<String?> paths = const <String?>[],
}) {
  final baseNames = <String, String>{};
  for (final value in paths.whereType<String>()) {
    for (final known in <String>[value, path.dirname(value)]) {
      final baseName = path.basename(known);
      if (baseName.isEmpty || baseName == known) {
        continue;
      }
      for (final resolved in <String?>[known, _realPath(known)]) {
        if (resolved == null) {
          continue;
        }
        for (final spelling in <String>[
          resolved,
          resolved.replaceAll(r'\', '/'),
          resolved.replaceAll('/', r'\'),
        ]) {
          if (spelling != baseName) {
            baseNames.putIfAbsent(spelling, () => baseName);
          }
        }
      }
    }
  }
  // Paths are cut before whitespace is collapsed, so that a path with a
  // whitespace run still matches.
  var text = message;
  for (final spelling
      in baseNames.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length))) {
    text = text.replaceAll(spelling, baseNames[spelling]!);
  }
  final name = _statusNames[code];
  text = text.replaceAll(_whitespace, ' ').trim();
  if (name != null && text.startsWith('$name: ')) {
    text = text.substring(name.length + 2).trim();
  }
  text = redactUrlSecrets(text).replaceFirst(_trailingSeparators, '');
  final status = switch (code) {
    0 => '',
    _ when name != null => ' $name ($code)',
    _ => ' code $code',
  };
  if (text.isEmpty) {
    return 'LiteRT-LM reported$status.';
  }
  final stop = _sentenceEnd.hasMatch(text) ? '' : '.';
  return 'LiteRT-LM reported$status: $text$stop';
}

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _trailingSeparators = RegExp(r'[\s:;,]+$');
final RegExp _sentenceEnd = RegExp(r'[.!?]$');

/// [value] with symbolic links resolved, through its directory when [value]
/// itself does not exist, or null when neither exists.
String? _realPath(String value) {
  try {
    return File(value).resolveSymbolicLinksSync();
  } on FileSystemException {
    try {
      return path.join(
        Directory(path.dirname(value)).resolveSymbolicLinksSync(),
        path.basename(value),
      );
    } on FileSystemException {
      return null;
    }
  }
}
