@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../support/dart_script_snapshot.dart';

void main() {
  late String script;
  late Directory directory;
  late File fake;
  setUpAll(
    () async => script = await compileDartScript(
      'test/fixtures/litert_lm_v1_asr_qualification.dart',
    ),
  );
  setUp(() {
    directory = Directory.systemTemp.createTempSync('v1_asr_hash_');
    fake = File('${directory.path}/not-a-native-library')
      ..writeAsStringSync('model-free fixture');
  });
  tearDown(() => directory.deleteSync(recursive: true));
  for (final badIndex in [1, 3, 5, 7]) {
    test(
      'input digest $badIndex is checked before any native loading',
      () async {
        final hash = sha256.convert(fake.readAsBytesSync()).toString();
        final args = [
          for (var i = 0; i < 4; i++) ...[fake.path, hash],
          'moonshine-tiny',
          'country',
        ];
        args[badIndex] = '0' * 64;
        final result = await Process.run(Platform.resolvedExecutable, [
          script,
          ...args,
        ]);
        expect(result.exitCode, isNot(0));
        expect(
          '${result.stderr}',
          contains('SHA256 mismatch before native loading'),
        );
        expect(
          '${result.stderr}',
          isNot(contains('Failed to load dynamic library')),
        );
      },
    );
  }
}
