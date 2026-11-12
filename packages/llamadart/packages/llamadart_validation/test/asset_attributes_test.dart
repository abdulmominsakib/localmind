@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:test/test.dart';

void main() {
  const packageRoot = 'packages/llamadart_validation';
  final lockedAssets = <String, String>{
    for (final entry in (embeddingValidationFixture['files'] as Map).entries)
      '$packageRoot/${embeddingValidationFixture['directory']}/${entry.key}':
          entry.value as String,
    '$packageRoot/${decisionValidationFixture['reference']}':
        decisionValidationFixture['reference_sha256'] as String,
  };

  for (final entry in lockedAssets.entries) {
    test('${entry.key} preserves its locked bytes on Windows checkout', () {
      expect(
        sha256.convert(File('../../${entry.key}').readAsBytesSync()).toString(),
        entry.value,
        reason: 'The checked-in asset must match its catalog lock.',
      );
      final result = Process.runSync('git', [
        'check-attr',
        '-z',
        'text',
        'eol',
        '--',
        entry.key,
      ], workingDirectory: '../..');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final attributes = (result.stdout as String).split('\u0000');
      expect(
        attributes[2] == 'unset' || attributes[5] == 'lf',
        isTrue,
        reason:
            '${entry.key} needs -text (or eol=lf) in .gitattributes so '
            'core.autocrlf cannot invalidate its SHA256 lock. '
            'Got text=${attributes[2]}, eol=${attributes[5]}.',
      );
    });
  }
}
