import 'dart:convert';
import 'dart:io';

import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/placement.dart';
import 'package:test/test.dart';

void main() {
  final profile = ValidationProfile.fromJson(
    jsonDecode(
      File('assets/profiles/embedding-gguf-metal.json').readAsStringSync(),
    ),
  );
  final manifest = <String, dynamic>{
    'schema_version': 2,
    'profile': profile.toJson(),
    'catalog': {'version': validationCatalogVersion},
  };
  final cases = <Map<String, dynamic>>[
    {
      'case_id': 'C01.load',
      'status': 'PASS',
      'diagnostics': {'backend_name': 'Metal'},
    },
  ];
  final metal = File(
    'test/fixtures/embedding_placement/metal.txt',
  ).readAsStringSync();
  final cpu = File(
    'test/fixtures/embedding_placement/cpu.txt',
  ).readAsStringSync();
  bool verified(String log, {Map<String, dynamic>? source}) =>
      inspectPlacement(source ?? manifest, cases, log)['verified'] == true;

  test(
    'real embedding log attributes 18 allocations to one llama and two CLIP contexts',
    () {
      final result = inspectPlacement(manifest, cases, metal);
      expect(result['verified'], isTrue, reason: '$result');
      expect(result['compute_records'], hasLength(18));
      expect(result['offload_records'], hasLength(1));
    },
  );
  final negatives = <String, String>{
    'CPU fallback': cpu,
    'nested reservation start': metal.replaceFirst(
      'sched_reserve: reserving ...',
      'sched_reserve: reserving ...\nsched_reserve: reserving ...',
    ),
    'projector type outside its context': metal
        .replaceFirst('load_hparams: projector:          gemma4v\n', '')
        .replaceFirst(
          'clip_ctx: CLIP using MTL0 backend',
          'load_hparams: projector:          gemma4v\nclip_ctx: CLIP using MTL0 backend',
        ),

    'no contexts or buffers': 'load_tensors: offloaded 25/25 layers to GPU\n',
    'CPU scratch zero': metal.replaceFirst('32.05', '0.00'),
    'wrong allocation owner': metal.replaceFirst(
      'sched_reserve:       MTL0',
      'wrong_owner:       MTL0',
    ),
    'no llama reservations': metal.replaceAll(
      RegExp(
        r'sched_reserve: reserving \.\.\.[\s\S]*?sched_reserve: reserve took[^\r\n]*',
      ),
      '',
    ),
    'wrong scratch device': metal.replaceFirst('CPU compute', 'CUDA0 compute'),

    'zero offload with Metal buffers': metal.replaceFirst('25/25', '0/25'),
    'partial offload': metal.replaceFirst('25/25', '24/25'),
    'missing offload': metal.replaceFirst(
      'load_tensors: offloaded 25/25 layers to GPU',
      '',
    ),
    'extra offload': 'load_tensors: offloaded 25/25 layers to GPU\n$metal',
    'wrong device': metal.replaceFirst('MTL0 compute', 'MTL1 compute'),
    'wrong projector device': metal.replaceFirst(
      'CLIP using MTL0',
      'CLIP using CPU',
    ),
    'zero size': metal.replaceFirst('244.04', '0.00'),
    'zero projector size': metal.replaceFirst('101.27', '0.00'),
    'missing compute buffer': metal.replaceAll(
      RegExp(r'^.*MTL0 compute buffer.*\n', multiLine: true),
      '',
    ),
    'missing one reservation buffer': metal.replaceFirst(
      RegExp(r'^.*MTL0 compute buffer.*\n', multiLine: true),
      '',
    ),
    'orphan buffer':
        'sched_reserve: MTL0 compute buffer size = 1.00 MiB\n$metal',
    'unattributed buffer':
        '$metal\nunknown: MTL0 compute buffer size = 1.00 MiB\n',
    'extra llama context':
        '$metal\nllama_context: constructing llama_context\n',
    'missing llama context': metal.replaceFirst(
      'llama_context: constructing llama_context',
      '',
    ),
    'extra projector context': '$metal\nclip_ctx: CLIP using MTL0 backend\n',
    'missing projector context': metal.replaceFirst(
      'clip_ctx: CLIP using MTL0 backend',
      '',
    ),
    'wrong projector type': metal.replaceFirst('gemma4a', 'gemma4v'),
    'truncated reservation': metal.replaceFirst(
      RegExp(r'^sched_reserve: reserve took.*\n', multiLine: true),
      '',
    ),
    'malformed size': metal.replaceFirst('244.04', 'unknown'),
    'unknown accelerator alongside Metal':
        '$metal\nCUDA0 compute buffer size = 1.00 MiB\n',
  };
  for (final entry in negatives.entries) {
    test('embedding placement rejects ${entry.key}', () {
      expect(verified(entry.value), isFalse);
    });
  }
  test(
    'every existing non-embedding accelerator profile retains exact buffer counts',
    () {
      var checked = 0;
      for (final file in Directory(
        'assets/profiles',
      ).listSync().whereType<File>()) {
        final parsed = ValidationProfile.fromJson(
          jsonDecode(file.readAsStringSync()),
        );
        if (parsed.isEmbedding ||
            parsed.isDecision ||
            parsed.toolResultProjector != null ||
            parsed.runtime != 'gguf' ||
            !['metal', 'cuda', 'vulkan'].contains(parsed.backend)) {
          continue;
        }
        final ids = parsed.caseIds
            .where(
              [
                'C01.load',
                'C09.reload',
                'C12.recovery',
                'C09.reload.second',
                'C12.guards',
              ].contains,
            )
            .toList();
        final device = {
          'metal': 'MTL0',
          'cuda': 'CUDA0',
          'vulkan': 'Vulkan0',
        }[parsed.backend]!;
        final load =
            'load_tensors: offloaded 7/7 layers to GPU\n$device compute buffer size = 64.0 MiB\n';
        final oldManifest = {...manifest, 'profile': parsed.toJson()};
        final oldCases = <Map<String, dynamic>>[
          for (final id in ids)
            {
              'case_id': id,
              'status': 'PASS',
              'diagnostics': {'backend_name': parsed.backend},
            },
        ];
        expect(
          inspectPlacement(
            oldManifest,
            oldCases,
            'ggml_vulkan: 0 = NVIDIA Tesla T4 | uma: 0\n${load * ids.length}',
          )['verified'],
          isTrue,
          reason: parsed.id,
        );
        expect(
          inspectPlacement(
            oldManifest,
            oldCases,
            'ggml_vulkan: 0 = NVIDIA Tesla T4 | uma: 0\n${load * ids.length}$device compute buffer size = 1.0 MiB\n',
          )['verified'],
          isFalse,
          reason: parsed.id,
        );
        expect(
          inspectPlacement(
            oldManifest,
            oldCases,
            'ggml_vulkan: 0 = NVIDIA Tesla T4 | uma: 0\n${load.replaceFirst('7/7', '1/7') * ids.length}',
          )['verified'],
          isTrue,
          reason:
              '${parsed.id} retains its existing positive partial-offload rule',
        );
        checked++;
      }
      expect(checked, 10);
    },
  );
}
