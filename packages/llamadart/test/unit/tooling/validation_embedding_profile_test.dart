@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../../tool/testing/validation/npu.dart';

void main() {
  test('embedding CPU/Metal profiles lock matching published BF16 artifacts', () {
    for (final backend in ['cpu', 'metal']) {
      final profile =
          jsonDecode(
                File(
                  'packages/llamadart_validation/assets/profiles/embedding-gguf-$backend.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final model = profile['model'] as Map;
      final projector = (profile['embedding'] as Map)['projector'] as Map;
      expect(model['bytes'], 557950176);
      expect(projector['bytes'], 982074784);
      expect(projector['revision'], model['revision']);
      expect(projector['revision'], 'bfcd298762cc34d0357ece5ebdd31791a3a374d8');
      requireExecutableValidationProfile(profile);
      expect(
        () => requireExecutableValidationProfile(profile, web: true),
        throwsStateError,
      );
    }
  });
  test('fixture regeneration is byte-identical', () {
    const root = 'packages/llamadart_validation/assets/embeddings';
    final output = Directory.systemTemp.createTempSync('embedding-fixtures-');
    addTearDown(() => output.deleteSync(recursive: true));
    final before = {
      for (final name in ['checker.png', 'tone.wav'])
        name: sha256
            .convert(File('$root/v1/$name').readAsBytesSync())
            .toString(),
    };
    final result = Process.runSync('python3', [
      '$root/generate_fixtures.py',
      output.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    for (final entry in before.entries) {
      expect(
        sha256
            .convert(File('${output.path}/${entry.key}').readAsBytesSync())
            .toString(),
        entry.value,
      );
    }
  });
  test('desktop and Flutter hosts carry projector and fixture paths', () {
    final cli = File(
      'packages/llamadart_validation/bin/run.dart',
    ).readAsStringSync();
    final host = File(
      'example/chat_app/lib/validation/host_native.dart',
    ).readAsStringSync();
    final controller = File(
      'example/chat_app/lib/validation/controller.dart',
    ).readAsStringSync();
    for (final source in [cli, host]) {
      expect(source, contains('prepareEmbeddingProjector('));
      expect(source, contains('PublicEmbeddingValidationEngine('));
      expect(source, contains("'embedding_projector'"));
    }
    expect(controller, contains('embeddingAssets:'));
    expect(
      File('packages/llamadart_validation/pubspec.yaml').readAsStringSync(),
      contains('- assets/embeddings/v1/'),
    );
    expect(
      File('tool/testing/validation.dart').readAsStringSync(),
      contains("p.absolute(options['projector']!)"),
    );
  });
}
