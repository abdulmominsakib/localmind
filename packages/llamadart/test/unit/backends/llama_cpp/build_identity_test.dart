@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:llamadart/src/backends/llama_cpp/build_identity.dart';
import 'package:test/test.dart';

void main() {
  test('the pinned runtime reports a complete, path-free build identity', () {
    final identity = readNativeBuildIdentity(isWindows: Platform.isWindows);

    expect(identity, startsWith('llamadart-native-build/1;'));
    final fields = {
      for (final field in identity!.split(';').skip(1))
        field.substring(0, field.indexOf('=')): field.substring(
          field.indexOf('=') + 1,
        ),
    };
    expect(
      fields.keys,
      containsAll(['owner', 'llama.cpp', 'backends', 'options']),
    );
    for (final MapEntry(:key, :value) in fields.entries) {
      expect(value, matches(RegExp(r'^[A-Za-z0-9._+,-]+$')), reason: key);
    }
  });

  test('a runtime without the symbol reads as null, not an error', () {
    // A @Native function whose symbol the process lacks throws this
    // ArgumentError when called, as on a runtime older than v0.7.0-3.
    expect(_missingSymbol, throwsArgumentError);
    expect(
      readNativeBuildIdentity(isWindows: false, call: _missingSymbol),
      isNull,
    );
  });

  test('a null identity pointer reads as empty', () {
    expect(readNativeBuildIdentity(isWindows: false, call: () => nullptr), '');
    final text = 'llamadart-native-build/1;owner=abc'.toNativeUtf8();
    addTearDown(() => malloc.free(text));
    expect(
      readNativeBuildIdentity(isWindows: false, call: text.cast),
      'llamadart-native-build/1;owner=abc',
    );
  });
}

@Native<Pointer<Char> Function()>(
  symbol: 'llama_dart_build_identity_missing_for_test',
)
external Pointer<Char> _missingSymbol();
