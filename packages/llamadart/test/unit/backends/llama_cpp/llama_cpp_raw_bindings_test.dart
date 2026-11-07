@TestOn('vm')
library;

import 'dart:ffi' as ffi;

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_raw_bindings.dart'
    as raw;
import 'package:test/test.dart';

void main() {
  test('raw ftype binding helpers are available for forward compatibility', () {
    expect(
      raw.llama_model_ftype_raw,
      isA<int Function(ffi.Pointer<llama_model>)>(),
    );
    expect(
      raw.llama_ftype_name_raw,
      isA<ffi.Pointer<ffi.Char> Function(int)>(),
    );
  });
}
