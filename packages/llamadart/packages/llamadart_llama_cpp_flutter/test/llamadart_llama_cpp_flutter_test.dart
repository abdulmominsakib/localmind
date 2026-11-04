import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart_llama_cpp_flutter/llamadart_llama_cpp_flutter.dart';

void main() {
  test('declares llama.cpp runtime family', () {
    expect(llamadartLlamaCppFlutterRuntime, 'llama_cpp');
  });

  test('declares Flutter SwiftPM product name', () {
    final manifest = File(
      'darwin/llamadart_llama_cpp_flutter/Package.swift',
    ).readAsStringSync();

    expect(manifest, contains('name: "llamadart-llama-cpp-flutter"'));
  });
}
