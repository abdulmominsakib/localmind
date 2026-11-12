@TestOn('vm')
@Tags(['local-only'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final model = Platform.environment['LLAMADART_LFM2_MODEL'];
  for (final gpuLayers in [0, 99]) {
    for (final capacity in [0, 1, 48]) {
      test(
        'LFM2 rollback=$capacity gpuLayers=$gpuLayers survives context creation',
        skip: model == null
            ? 'Set LLAMADART_LFM2_MODEL to an LFM2 GGUF.'
            : null,
        () async {
          final result = await Process.run(Platform.resolvedExecutable, [
            'run',
            'test/support/native_rollback_probe.dart',
            model!,
            '$capacity',
            '$gpuLayers',
          ]).timeout(const Duration(minutes: 2));
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
          final record = (result.stdout as String)
              .split('\n')
              .where((line) => line.startsWith('{'))
              .last;
          final data = jsonDecode(record) as Map<String, dynamic>;
          if (capacity == 0) {
            expect(data['outcome'], 'generated');
            expect(data['output'], isNotEmpty);
          } else {
            expect(data['outcome'], 'unsupported');
            expect(data['message'], contains('speculativeRollbackTokenMax'));
            expect(data['message'], contains('graph'));
            expect(data['recovered'], isNotEmpty);
          }
        },
      );
    }
  }
}
