import 'dart:convert';
import 'dart:io';

import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/placement.dart';
import 'package:test/test.dart';

void main() {
  final profile = ValidationProfile.fromJson(
    jsonDecode(
          File('assets/profiles/qwen3vl-gguf-metal.json').readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  final manifest = <String, dynamic>{
    'schema_version': 2,
    'profile': profile.toJson(),
    'catalog': {'version': validationCatalogVersion},
  };
  final cases = [
    for (final id in ['C01.load', 'C09.reload', 'C12.recovery'])
      {
        'case_id': id,
        'status': 'PASS',
        'diagnostics': {'backend_name': 'Metal'},
      },
  ];
  final metal = File(
    'test/fixtures/tool_result_media_placement/metal.txt',
  ).readAsStringSync();
  bool verified(String log) =>
      inspectPlacement(manifest, cases, log)['verified'] == true;

  test('real log counts one llama and one CLIP buffer for each load', () {
    final result = inspectPlacement(manifest, cases, metal);
    expect(result['verified'], isTrue, reason: '$result');
    expect(result['compute_records'], hasLength(6));
    expect(result['offload_records'], hasLength(3));
  });

  final negatives = <String, String>{
    'CPU fallback': metal.replaceAll('MTL0', 'CPU'),
    'missing projector buffer': metal.replaceFirst(
      RegExp(r'reserve_compute_meta:\s*MTL0 compute buffer size[^\n]*\n'),
      '',
    ),
    'missing projector backend': metal.replaceFirst(
      'clip_ctx: CLIP using MTL0 backend',
      'clip_ctx: CLIP using CPU backend',
    ),
    'wrong projector type': metal.replaceFirst('qwen3vl_merger', 'gemma4v'),
    'extra allocation':
        '$metal'
        'sched_reserve:       MTL0 compute buffer size =     1.00 MiB\n',
    'zero projector buffer': metal.replaceFirst('459.11', '0.00'),
  };
  for (final entry in negatives.entries) {
    test('rejects ${entry.key}', () => expect(verified(entry.value), isFalse));
  }
}
