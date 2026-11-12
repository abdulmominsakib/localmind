import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The existing native-stderr limit also bounds any individual raw capture.
const int s24LiteRtMaximumCaptureBytes = 8 * 1024 * 1024;

/// Retains raw bytes, choosing text only when its escaped JSON is smaller.
Map<String, dynamic> encodeS24LiteRtCapture(
  List<int> bytes, {
  bool allowUtf8 = true,
}) {
  if (bytes.length > s24LiteRtMaximumCaptureBytes ||
      bytes.any((value) => value < 0 || value > 255)) {
    throw const FormatException('S24 capture size or bytes invalid');
  }
  final identity = <String, dynamic>{
    'bytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
  };
  if (!allowUtf8) return {...identity, 'base64': base64Encode(bytes)};
  try {
    final text = utf8.decode(bytes);
    final roundtrip = utf8.encode(text);
    if (_sameBytes(bytes, roundtrip)) {
      // Count JSON escapes without allocating a potentially sixfold string.
      var escapedBytes = bytes.length;
      for (final byte in bytes) {
        if (byte == 34 || byte == 92) {
          escapedBytes++;
        } else if (byte < 32) {
          escapedBytes += const [8, 9, 10, 12, 13].contains(byte) ? 1 : 5;
        }
      }
      final base64Length = ((bytes.length + 2) ~/ 3) * 4;
      if (escapedBytes + 'utf8'.length < base64Length + 'base64'.length) {
        return {...identity, 'utf8': text};
      }
    }
  } on FormatException {
    // Binary and invalid UTF-8 keep the original lossless base64 envelope.
  }
  return {...identity, 'base64': base64Encode(bytes)};
}

/// Reads either lossless envelope, validating bounds before decoding/encoding.
List<int> decodeS24LiteRtCapture(Map capture) {
  final size = capture['bytes'];
  final digest = capture['sha256'];
  final hasBase64 = capture.containsKey('base64');
  final hasText = capture.containsKey('utf8');
  if (size is! int ||
      size < 0 ||
      size > s24LiteRtMaximumCaptureBytes ||
      digest is! String ||
      digest.length != 64 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
      hasBase64 == hasText) {
    throw const FormatException('Invalid S24 capture identity or encoding');
  }
  final List<int> bytes;
  if (hasBase64) {
    final encoded = capture['base64'];
    if (encoded is! String || encoded.length != ((size + 2) ~/ 3) * 4) {
      throw const FormatException('Invalid S24 capture base64 bound');
    }
    bytes = base64Decode(encoded);
    if (base64Encode(bytes) != encoded) {
      throw const FormatException('Noncanonical S24 capture base64');
    }
  } else {
    final text = capture['utf8'];
    if (text is! String ||
        text.length > size ||
        _utf8Length(text, size) != size) {
      throw const FormatException('Invalid S24 capture UTF-8 bound');
    }
    bytes = utf8.encode(text);
  }
  if (bytes.length != size || sha256.convert(bytes).toString() != digest) {
    throw const FormatException('Changed S24 captured bytes');
  }
  return bytes;
}

int _utf8Length(String text, int maximum) {
  var length = 0;
  for (var index = 0; index < text.length; index++) {
    final value = text.codeUnitAt(index);
    if (value < 0x80) {
      length++;
    } else if (value < 0x800) {
      length += 2;
    } else if (value >= 0xd800 && value <= 0xdbff) {
      if (++index >= text.length ||
          text.codeUnitAt(index) < 0xdc00 ||
          text.codeUnitAt(index) > 0xdfff) {
        throw const FormatException('Unpaired S24 capture surrogate');
      }
      length += 4;
    } else if (value >= 0xdc00 && value <= 0xdfff) {
      throw const FormatException('Unpaired S24 capture surrogate');
    } else {
      length += 3;
    }
    if (length > maximum) {
      throw const FormatException('S24 capture UTF-8 exceeds claimed size');
    }
  }
  return length;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
