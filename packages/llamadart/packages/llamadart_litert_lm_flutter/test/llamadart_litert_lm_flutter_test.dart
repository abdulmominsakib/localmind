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
    expect(manifest, isNot(contains('GemmaModelConstraintProvider')));
    expect(manifest, isNot(contains('LiteRtMetalAccelerator')));
    expect(
      manifest,
      isNot(
        contains(
          'checksum: "0000000000000000000000000000000000000000000000000000000000000000"',
        ),
      ),
    );
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
    expect(
      manifest,
      contains('name: "CLiteRTLM", condition: .when(platforms: [.iOS])'),
    );
  });

  test(
    'links the complete macOS arm64 runtime without the embedded LiteRT',
    () {
      final manifest = File(
        'darwin/llamadart_litert_lm_flutter/Package.swift',
      ).readAsStringSync();

      const target = 'WebgpuDawn';
      expect(
        manifest,
        contains(
          'artifactName: "litert-lm-native-apple-$target-xcframework-'
          r'\(liteRtLmTag).zip"',
        ),
      );
      expect(
        manifest,
        contains('name: "$target", condition: .when(platforms: [.macOS])'),
      );
      // LiteRtLm embeds LiteRT and its GPU accelerator (#1911). Match the
      // quoted names: "LiteRt" is a prefix of other target names.
      for (final target in ['LiteRt', 'LiteRtWebGpuAccelerator']) {
        expect(manifest, isNot(contains('name: "$target"')));
      }
    },
  );

  test('declares the four published v0.19 runtime targets', () {
    final manifest = File(
      'darwin/llamadart_litert_lm_flutter/Package.swift',
    ).readAsStringSync();
    final targets = RegExp(
      r'nativeRepoBinaryTarget\(\s*name: "([^"]+)"',
    ).allMatches(manifest).map((match) => match.group(1)).toList();

    expect(
      targets,
      unorderedEquals(['LiteRtLm', 'CLiteRTLM', 'CLiteRTLMMac', 'WebgpuDawn']),
    );
    expect(manifest, isNot(contains('LiteRtTopKMetalSampler')));
    expect(manifest, isNot(contains('LiteRtTopKWebGpuSampler')));
  });

  test('macOS plugin source does not import the runtime modules', () {
    final pluginSource = File(
      'darwin/llamadart_litert_lm_flutter/Sources/'
      'llamadart_litert_lm_flutter/LlamadartLiteRtLmPlugin.swift',
    ).readAsStringSync();

    final macosBlock = RegExp(
      r'#elseif os\(macOS\)([\s\S]*?)#endif',
    ).firstMatch(pluginSource);
    expect(macosBlock, isNotNull);
    expect(macosBlock!.group(1), isNot(contains('import LiteRtLm')));
  });
}
