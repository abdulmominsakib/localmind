@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Sources with no behavior of their own. The guard below requires each to
/// exist under `lib/src` and to have no mirrored file under `test/unit`.
const Set<String> behaviorlessSources = <String>{
  'backends/llama_cpp/llama_cpp_raw_bindings.dart',
  'backends/llama_cpp/native_signatures.dart',
  'backends/litert_lm/litert_lm_native_settlement.dart',
  'backends/litert_lm/litert_lm_runtime_client_contract.dart',
  'backends/webgpu/interop.dart',
  'core/decision/decision_model.dart',
  'core/engine/llamadart_engine.dart',
  'core/image/image_generation_driver.dart',
  'core/image/image_generation_model.dart',
  'core/image/image_model_params.dart',
  'core/image/image_model_placement.dart',
  'core/models/config/compute_device.dart',
  'core/models/config/flash_attention.dart',
  'core/models/config/kv_cache_type.dart',
  'core/models/download/model_download_manager.dart',
  'core/models/tools/tool_output.dart',
  'core/speech/litert_lm_speech_to_text_driver.dart',
  'core/speech/speech_platform_stub.dart',
  'core/speech/speech_platform_web.dart',
  'core/speech/text_to_speech_platform_stub.dart',
  'core/speech/text_to_speech_platform_web.dart',
};

void main() {
  test('every behavioral lib/src file has a mirrored unit test file', () {
    final libSrcDir = Directory('lib/src');
    final unitDir = Directory('test/unit');

    final sourceFiles =
        libSrcDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final missing = <String>[];

    for (final sourceFile in sourceFiles) {
      final relativeSourcePath = p.relative(
        sourceFile.path,
        from: libSrcDir.path,
      );
      if (_isGeneratedSource(sourceFile) ||
          behaviorlessSources.contains(
            p.posix.joinAll(p.split(relativeSourcePath)),
          )) {
        continue;
      }

      final sourceDir = p.dirname(relativeSourcePath);
      final sourceStem = p.basenameWithoutExtension(relativeSourcePath);
      final expectedTestPath = p.normalize(
        p.join(unitDir.path, sourceDir, '${sourceStem}_test.dart'),
      );

      if (!File(expectedTestPath).existsSync()) {
        missing.add('$relativeSourcePath -> ${p.relative(expectedTestPath)}');
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Missing mirrored unit test files:\n${missing.join('\n')}',
    );
  });

  test('behaviorless source exemptions name existing, untested sources', () {
    for (final source in behaviorlessSources) {
      expect(
        File(p.join('lib/src', source)).existsSync(),
        isTrue,
        reason: source,
      );
      final testPath = p.join(
        'test/unit',
        p.dirname(source),
        '${p.basenameWithoutExtension(source)}_test.dart',
      );
      expect(File(testPath).existsSync(), isFalse, reason: testPath);
    }
  });
}

/// Only real generator output is exempt. `coverage:ignore-file` is a coverage
/// pragma, and hand-written stubs carry it, so matching on it let them skip
/// mirroring too.
bool _isGeneratedSource(File sourceFile) {
  final header = sourceFile.readAsLinesSync().take(20).join('\n');

  // ffigen and tool/gen_litert_lm_templates.dart word their banners differently.
  return header.contains('AUTO GENERATED FILE, DO NOT EDIT.') ||
      header.contains('GENERATED FILE — DO NOT EDIT BY HAND.');
}
