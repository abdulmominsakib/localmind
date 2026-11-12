import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:llamadart_validation/src/s24_litert_capture.dart';
import 'package:test/test.dart';

Map<String, dynamic> base64Capture(List<int> bytes) => {
  'bytes': bytes.length,
  'sha256': sha256.convert(bytes).toString(),
  'base64': base64Encode(bytes),
};

int jsonBytes(Map value) => utf8.encode(jsonEncode(value)).length;

void main() {
  test('text and binary preserve exact raw bytes and original identity', () {
    final samples = [
      <int>[],
      utf8.encode('maps and native log lines\n' * 100),
      utf8.encode('é漢😀\u2028\u2029\n"\\\t\u0000' * 100),
      [for (var value = 0; value < 256; value++) value],
      [0xc0, 0xaf, 0xff, 0x80],
      [0xef, 0xbb, 0xbf, 65],
    ];
    for (final raw in samples) {
      final encoded = encodeS24LiteRtCapture(raw);
      expect(decodeS24LiteRtCapture(encoded), raw);
      expect(encoded['bytes'], raw.length);
      expect(encoded['sha256'], sha256.convert(raw).toString());
      expect(
        jsonBytes(encoded),
        lessThanOrEqualTo(jsonBytes(base64Capture(raw))),
      );
    }
    expect(encodeS24LiteRtCapture([0xff]).containsKey('base64'), isTrue);
    expect(
      encodeS24LiteRtCapture([0xef, 0xbb, 0xbf, 65]).containsKey('base64'),
      isTrue,
    );
  });
  test(
    'selection compares escaped JSON, including nonbeneficial valid text',
    () {
      for (final text in ['plain\n' * 500, '\u0000' * 500, '"\\\t' * 500]) {
        final raw = utf8.encode(text);
        final old = base64Capture(raw);
        final candidate = Map<String, dynamic>.of(old)
          ..remove('base64')
          ..['utf8'] = text;
        final encoded = encodeS24LiteRtCapture(raw);
        expect(
          encoded.containsKey('utf8'),
          jsonBytes(candidate) < jsonBytes(old),
        );
        expect(decodeS24LiteRtCapture(encoded), raw);
      }
    },
  );
  test('legacy base64 remains accepted, with canonical encoding required', () {
    final raw = utf8.encode('old evidence\n');
    expect(decodeS24LiteRtCapture(base64Capture(raw)), raw);
    for (final value in ['YQ', 'YR==', '____', '!!!!']) {
      final row = base64Capture([97])..['base64'] = value;
      expect(() => decodeS24LiteRtCapture(row), throwsFormatException);
    }
  });
  test('missing, ambiguous, mistyped or corrupted envelopes reject', () {
    final valid = encodeS24LiteRtCapture(utf8.encode('native maps\n'));
    final values = [
      {...valid}..remove('utf8'),
      {...valid, 'base64': ''},
      {...valid, 'utf8': 1},
      {...valid, 'utf8': 'changed'},
      {...valid, 'bytes': -1},
      {...valid, 'bytes': 1.0},
      {...valid, 'bytes': true},
      {...valid, 'bytes': valid['bytes'] + 1},
      {...valid, 'sha256': 'g' * 64},
      {...valid, 'sha256': '0' * 64},
      {...valid, 'sha256': null},
      {
        ...base64Capture([0xff]),
        'base64': 1,
      },
    ];
    for (final value in values) {
      expect(() => decodeS24LiteRtCapture(value), throwsFormatException);
    }
  });
  test('UTF-8 claim rejects lone surrogates and byte-length mismatch', () {
    for (final text in [
      String.fromCharCode(0xd800),
      String.fromCharCode(0xdc00),
      '${String.fromCharCode(0xd800)}x',
    ]) {
      final row = {'bytes': text.length, 'sha256': '0' * 64, 'utf8': text};
      expect(() => decodeS24LiteRtCapture(row), throwsFormatException);
    }
    final wide = {'bytes': 1, 'sha256': '0' * 64, 'utf8': '漢'};
    expect(() => decodeS24LiteRtCapture(wide), throwsFormatException);
  });
  test(
    'oversized claims reject before payload access or decode allocation',
    () {
      final map = _PayloadMustNotBeRead();
      expect(() => decodeS24LiteRtCapture(map), throwsFormatException);
      expect(map.payloadAccessed, isFalse);
      expect(
        () => encodeS24LiteRtCapture(_OversizedBytes()),
        throwsFormatException,
      );
      final encoded = {'bytes': 0, 'sha256': '0' * 64, 'base64': 'AAAA'};
      expect(() => decodeS24LiteRtCapture(encoded), throwsFormatException);
    },
  );
  test('maximum original raw bound is accepted, never expanded', () {
    final raw = List<int>.filled(s24LiteRtMaximumCaptureBytes, 65);
    final capture = encodeS24LiteRtCapture(raw);
    expect(decodeS24LiteRtCapture(capture), raw);
    expect(capture['bytes'], 8388608);
  });
  test('out-of-range byte values reject without normalization', () {
    for (final raw in [
      [-1],
      [256],
    ]) {
      expect(() => encodeS24LiteRtCapture(raw), throwsFormatException);
    }
  });
}

final class _OversizedBytes extends ListBase<int> {
  @override
  int get length => s24LiteRtMaximumCaptureBytes + 1;
  @override
  set length(int value) => throw StateError('No allocation');
  @override
  int operator [](int index) => throw StateError('No payload access');
  @override
  void operator []=(int index, int value) => throw StateError('No allocation');
}

final class _PayloadMustNotBeRead extends MapBase<String, dynamic> {
  bool payloadAccessed = false;
  @override
  dynamic operator [](Object? key) {
    if (key == 'bytes') return s24LiteRtMaximumCaptureBytes + 1;
    if (key == 'sha256') return '0' * 64;
    payloadAccessed = true;
    throw StateError('Oversized payload must not be read');
  }

  @override
  bool containsKey(Object? key) => key == 'utf8';
  @override
  void operator []=(String key, dynamic value) => throw UnimplementedError();
  @override
  void clear() => throw UnimplementedError();
  @override
  Iterable<String> get keys => throw UnimplementedError();
  @override
  dynamic remove(Object? key) => throw UnimplementedError();
}
