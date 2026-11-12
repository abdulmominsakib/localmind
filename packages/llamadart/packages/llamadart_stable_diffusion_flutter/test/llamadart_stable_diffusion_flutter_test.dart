import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart_stable_diffusion_flutter/llamadart_stable_diffusion_flutter.dart';

void main() {
  test('declares stable_diffusion runtime family', () {
    expect(llamadartStableDiffusionFlutterRuntime, 'stable_diffusion');
  });

  test('declares Flutter SwiftPM product name', () {
    final manifest = File(
      'darwin/llamadart_stable_diffusion_flutter/Package.swift',
    ).readAsStringSync();

    expect(manifest, contains('name: "llamadart-stable-diffusion-flutter"'));
  });
}
