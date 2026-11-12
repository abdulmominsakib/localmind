@TestOn('vm')
@Tags(['local-only'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _cacheBytes = 512 << 20;

void main() {
  final model = Platform.environment['LLAMADART_MOE_MODEL'];
  final skip = model == null
      ? 'Set LLAMADART_MOE_MODEL to a Mixture-of-Experts GGUF.'
      : null;

  Future<({Map<String, dynamic> record, String log})> probe(
    int cpuMoeLayers,
    int moeCacheBytes,
  ) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'test/support/moe_cache_probe.dart',
      model!,
      '$cpuMoeLayers',
      '$moeCacheBytes',
    ]).timeout(const Duration(minutes: 3));
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final record = (result.stdout as String)
        .split('\n')
        .where((line) => line.startsWith('{'))
        .last;
    final log = result.stderr as String;
    final cacheLine = log
        .split('\n')
        .where((line) => line.contains('MoE cache'))
        .join(' | ');
    print('cpuMoeLayers=$cpuMoeLayers moeCacheBytes=$moeCacheBytes: $record');
    if (cacheLine.isNotEmpty) print('  native: $cacheLine');
    return (record: jsonDecode(record) as Map<String, dynamic>, log: log);
  }

  test(
    'the expert cache allocates its budget and keeps greedy output',
    skip: skip,
    () async {
      final baseline = await probe(0, 0);
      final hostExperts = await probe(-1, 0);
      final cached = await probe(-1, _cacheBytes);

      for (final run in [baseline, hostExperts, cached]) {
        expect(run.record['outcome'], 'generated');
        expect(run.record['repeated'], run.record['output']);
      }
      expect(hostExperts.record['output'], baseline.record['output']);
      expect(cached.record['output'], baseline.record['output']);
      expect(baseline.log, isNot(contains('MoE cache size')));
      expect(hostExperts.log, isNot(contains('MoE cache size')));
      expect(
        cached.log,
        matches(RegExp(r'MoE cache size = +\d+\.\d+ MiB for \d+')),
      );
      expect(cached.log, isNot(contains('MoE cache is disabled')));
    },
  );

  test(
    'a budget too small for one token fails context creation',
    skip: skip,
    () async {
      final run = await probe(-1, 1 << 20);
      expect(run.record['outcome'], 'LlamaModelException');
      expect(run.record['details'], contains('moeCacheBytes'));
    },
  );
}
