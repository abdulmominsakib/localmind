import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart_litert_lm_flutter/llamadart_litert_lm_flutter.dart';

void main() {
  test('declares LiteRT-LM runtime family', () {
    expect(llamadartLiteRtLmFlutterRuntime, 'litert_lm');
  });

  test('declares Flutter SwiftPM product name', () {
    final manifest = File(
      'darwin/llamadart_litert_lm_flutter/Package.swift',
    ).readAsStringSync();

    expect(manifest, contains('name: "llamadart-litert-lm-flutter"'));
    expect(manifest, isNot(contains('name: "GemmaModelConstraintProvider"')));
    expect(manifest, contains('name: "CLiteRTLMMac"'));
    expect(
      manifest,
      contains(
        'name: "LiteRtLm", condition: '
        '.when(platforms: [.iOS, .macOS])',
      ),
    );
    expect(
      manifest,
      contains('name: "CLiteRTLMMac", condition: .when(platforms: [.macOS])'),
    );
  });

  test('imports the primary LiteRT-LM runtime on macOS', () {
    final pluginSource = File(
      'darwin/llamadart_litert_lm_flutter/Sources/'
      'llamadart_litert_lm_flutter/LlamadartLiteRtLmPlugin.swift',
    ).readAsStringSync();

    final macosBlock = RegExp(
      r'#elseif os\(macOS\)([\s\S]*?)#endif',
    ).firstMatch(pluginSource);
    expect(macosBlock, isNotNull);
    expect(macosBlock!.group(1), contains('import LiteRtLm'));
  });
}
