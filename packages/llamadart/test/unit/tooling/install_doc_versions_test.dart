@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/testing/verify_release_docs_versions.dart';

void main() {
  late Directory root;
  const versions = {
    'llamadart': '0.8.23',
    'llamadart_llama_cpp_flutter': '0.0.19',
  };
  setUp(() {
    root = Directory.systemTemp.createTempSync('install-pair-');
    File('${root.path}/CHANGELOG.md').writeAsStringSync('''
## Unreleased
Native v0.4.1 is being prepared.
## 0.8.23
Pin `leehack/llamadart-native@v0.4.0`.
Apple companion `0.0.18` supplies the matching native runtime.
''');
    final companion = File(
      '${root.path}/packages/llamadart_llama_cpp_flutter/CHANGELOG.md',
    );
    companion.parent.createSync(recursive: true);
    companion.writeAsStringSync('''
## 0.0.19
Pin `leehack/llamadart-native@v0.4.1`.
## 0.0.18
Pin `leehack/llamadart-native@v0.4.0`.
''');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'released install pair remains coherent during companion preparation',
    () {
      final errors = <String>[];
      final actual = installDocVersions(
        root,
        versions,
        errors,
        releasePrep: false,
      );
      expect(errors, isEmpty);
      expect(actual['llamadart_llama_cpp_flutter'], '0.0.18');
      expect(actual['llamadart'], '0.8.23');
    },
  );

  test('release prep still requires the checkout companion', () {
    final errors = <String>[];
    expect(
      installDocVersions(root, versions, errors, releasePrep: true),
      versions,
    );
    expect(errors, isEmpty);
  });

  test('a recorded pairing cannot bypass native compatibility', () {
    final file = File('${root.path}/CHANGELOG.md');
    file.writeAsStringSync(
      file.readAsStringSync().replaceAll('0.0.18', '0.0.19'),
    );
    final errors = <String>[];
    installDocVersions(root, versions, errors, releasePrep: false);
    expect(errors.single, contains('must record the same native runtime pin'));
  });

  test('unknown core version fails closed', () {
    final errors = <String>[];
    installDocVersions(
      root,
      {...versions, 'llamadart': '0.8.99'},
      errors,
      releasePrep: false,
    );
    expect(errors.single, contains('no section for install core'));
  });
}
