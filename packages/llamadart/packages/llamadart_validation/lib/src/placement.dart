import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'case_catalog.dart';
import 'decision_catalog.dart';
import 'litert_gpu_failure_markers.dart';
import 'manifest.dart';
import 'npu_evidence.dart';

/// Conservative native-log evidence. A selector or device inventory alone is
/// insufficient: every expected GGUF load needs positive offload and compute
/// allocation, and every expected LiteRT GPU load a fully initialized delegate.
Map<String, dynamic> inspectPlacement(
  Map<String, dynamic> manifest,
  List<Map<String, dynamic>> cases,
  String? log,
) {
  final profile = manifest['profile'] is Map
      ? manifest['profile'] as Map
      : const {};
  final backend = profile['backend'];
  // The selector determines the obligation; a journal flag cannot waive it.
  final required = !['cpu', 'auto', 'blas'].contains(backend);
  if (!required) {
    return {'required': false, 'verified': true, 'reason': 'not_required'};
  }
  final result = <String, dynamic>{
    'required': true,
    'verified': false,
    'reason': 'native placement evidence unavailable',
    if (log != null) 'log_sha256': sha256.convert(utf8.encode(log)).toString(),
  };
  // Derive obligations from the executable profile, never from a producer's
  // case inventory or the evidence records that happen to be present.
  final List<String> selected;
  var headContexts = const <String, int>{};
  var embeddingMetal = false;
  var mediaProjector = false;
  try {
    final parsed = ValidationProfile.fromJson(
      Map<String, dynamic>.from(profile),
    );
    final schema = manifest['schema_version'];
    if (schema != 1 && schema != 2 ||
        schema == 1 && (parsed.selection == 'focused' || parsed.isDecision)) {
      return result;
    }
    if (parsed.isDecision) headContexts = decisionHeadContexts;
    embeddingMetal = parsed.isEmbedding && backend == 'metal';
    mediaProjector = parsed.toolResultProjector != null;
    final catalog = manifest['catalog'] as Map?;
    final version = catalog?['version'] ?? 1;
    selected =
        (schema == 1
                ? parsed.legacyCaseIds
                : version is int &&
                      version >= 1 &&
                      version <= validationCatalogVersion
                ? parsed.caseIdsForCatalog(version)
                : parsed.caseIds)
            .where(
              (id) =>
                  !['C10.stop', 'C12.guards'].contains(id) ||
                  (schema == 2 &&
                      version is int &&
                      version >= 3 &&
                      !parsed.nativeReference),
            )
            .toList();
  } catch (_) {
    return result;
  }
  if (profile['runtime'] == 'litert' && backend == 'npu') {
    return _inspectNpu(manifest, cases, selected, result);
  }
  final expectedIds = selected
      .where(
        (id) => [
          'C01.load',
          'C09.reload',
          'C12.recovery',
          'C09.reload.second',
          'C12.guards',
          'D06.reload',
        ].contains(id),
      )
      .toList();
  if (profile['runtime'] == 'litert' && backend == 'gpu') {
    return log == null
        ? result
        : _inspectLiteRtGpu(manifest, cases, expectedIds, log, result);
  }
  if (profile['runtime'] != 'gguf' ||
      log == null ||
      !['cuda', 'metal', 'vulkan'].contains(backend)) {
    return result;
  }
  if (backend == 'vulkan' && _softwareRenderer.hasMatch(log)) {
    return {
      ...result,
      'reason':
          'software Vulkan device present; physical accelerator execution is unproven',
    };
  }
  final expectedLoads = expectedIds.length;
  final prefix = {
    'cuda': r'CUDA\d+',
    'metal': r'MTL\d+|Metal',
    'vulkan': r'Vulkan\d+',
  }[backend]!;
  final heads = cases
      .where((c) => headContexts.containsKey(c['case_id']))
      .toList();
  final headDevices = [
    for (final head in heads)
      for (final evidence in [head, head['head_reload'], head['model_reload']])
        if (evidence is Map && evidence.containsKey('device_name'))
          evidence['device_name'],
  ];
  if (headContexts.keys.any(
        (id) =>
            heads
                .where((c) => c['case_id'] == id && c['status'] == 'PASS')
                .length !=
            1,
      ) ||
      headDevices.length != headContexts.values.fold(0, (a, b) => a + b) ||
      headDevices.any(
        (device) =>
            device is! String || !RegExp('^(?:$prefix)\$').hasMatch(device),
      )) {
    return {...result, 'reason': 'decision head placement evidence incomplete'};
  }
  if (!_loadsReport(cases, expectedIds, backend as String)) return result;
  final offloads = RegExp(
    r'load_tensors: offloaded (\d+)/(\d+) layers to GPU',
  ).allMatches(log).toList();
  final buffers = RegExp(
    '(?:$prefix) compute buffer size =\\s*([0-9.]+) (?:MiB|MB)',
  ).allMatches(log).toList();
  var deviceIdentityVerified = true;
  if (backend == 'vulkan') {
    final devices = <String, Set<String>>{};
    void addDevice(String index, String name, {bool discovery = false}) {
      // Discovery includes capability columns and sometimes a vendor suffix;
      // selected-model records contain just the same physical device name.
      final unsafe = _softwareDevice.hasMatch(name);
      final identity = !discovery || unsafe
          ? name.trim()
          : name
                .split('|')
                .first
                .trim()
                .replaceFirst(
                  RegExp(r'\s+\((?:NVIDIA|AMD|Intel|Apple|Qualcomm)\)$'),
                  '',
                );
      devices.putIfAbsent(index, () => {}).add(identity);
    }

    for (final match in RegExp(
      r'ggml_vulkan:\s*(\d+)\s*=\s*([^\r\n]+)',
    ).allMatches(log)) {
      addDevice(match[1]!, match[2]!, discovery: true);
    }
    for (final match in RegExp(
      r'^llama_prepare_model_devices: using device Vulkan(\d+) '
      r'\(((?:[^()\r\n]|\([^()\r\n]*\))+)\)'
      r'(?: \([0-9a-fA-F:.]+\))? - [0-9]+(?:\.[0-9]+)? MiB free\r?$',
      multiLine: true,
    ).allMatches(log)) {
      addDevice(match[1]!, match[2]!);
    }
    final selectedDevices = RegExp(
      r'Vulkan(\d+) compute buffer size',
    ).allMatches(log).map((match) => match[1]!).toSet();
    deviceIdentityVerified =
        selectedDevices.isNotEmpty &&
        selectedDevices.every((id) {
          final names = devices[id];
          return names != null &&
              names.length == 1 &&
              _hardwareVendor.hasMatch(names.single) &&
              !_softwareDevice.hasMatch(names.single);
        });
  }
  final positive =
      deviceIdentityVerified &&
      offloads.length == expectedLoads &&
      offloads.every(
        (m) =>
            int.parse(m[1]!) > 0 &&
            (embeddingMetal
                ? m[1] == m[2]
                : int.parse(m[1]!) <= int.parse(m[2]!)),
      ) &&
      (embeddingMetal
          ? _embeddingMetalBuffers(log, expectedLoads)
          : mediaProjector
          ? _projectorBuffers(log, prefix, buffers.length, expectedLoads)
          : buffers.length ==
                expectedLoads + headContexts.values.fold(0, (a, b) => a + b)) &&
      buffers.every((m) => (double.tryParse(m[1]!) ?? 0) > 0);
  return {
    ...result,
    'verified': positive,
    'reason': positive
        ? 'matching runtime diagnostics, positive native tensor offload and compute buffers for all $expectedLoads loads'
        : !deviceIdentityVerified
        ? 'Vulkan compute device identity is missing, contradictory or unrecognized as physical hardware'
        : 'native placement records incomplete or contradictory',
    'expected_loads': expectedLoads,
    'offload_records': offloads.map((m) => m[0]).toList(),
    'compute_records': buffers.map((m) => m[0]).toList(),
  };
}

// Each load of a tool-result media profile also builds one CLIP context whose
// `reserve_compute_meta` logs a second compute buffer on the same backend.
bool _projectorBuffers(
  String log,
  String prefix,
  int compute,
  int expectedLoads,
) =>
    compute == expectedLoads * 2 &&
    RegExp('clip_ctx: CLIP using (?:$prefix) backend').allMatches(log).length ==
        expectedLoads &&
    RegExp(
          r'load_hparams: projector:\s*qwen3vl_merger',
        ).allMatches(log).length ==
        expectedLoads &&
    RegExp('(?:$prefix) compute buffer size').allMatches(log).length ==
        compute &&
    RegExp(
          'reserve_compute_meta:\\s*(?:$prefix) compute buffer size',
        ).allMatches(log).length ==
        expectedLoads;

// Pooled embedding requests toggle the graph shape, so sched_reserve can emit
// repeatedly for one llama_context. Count contexts, then account for every
// reservation instead of imposing a request-dependent buffer-record ceiling.
// This shape is qualified only for the locked Gemma embedding Metal pack.
bool _embeddingMetalBuffers(String log, int expectedLoads) {
  final contexts = RegExp(
    r'llama_context: constructing llama_context',
  ).allMatches(log).toList();
  final allocations = RegExp(
    r'(\w+):\s*(\S+) compute buffer size =\s*([0-9.]+) (?:MiB|MB)',
  ).allMatches(log).toList();
  if (contexts.length != expectedLoads ||
      allocations.length != 'compute buffer size'.allMatches(log).length) {
    return false;
  }
  var accounted = 0;
  for (var i = 0; i < contexts.length; i++) {
    final start = contexts[i].start;
    final end = i + 1 < contexts.length ? contexts[i + 1].start : log.length;
    final context = log.substring(start, end);
    final reservations = RegExp(
      r'sched_reserve: reserving \.\.\.[\s\S]*?'
      r'sched_reserve: reserve took[^\r\n]*',
    ).allMatches(context).toList();
    final projectors = RegExp(
      r'clip_ctx: CLIP using (\S+) backend[\s\S]*?'
      r'reserve_compute_meta: graph splits =[^\r\n]*',
    ).allMatches(context).toList();
    final projectorIdentities = projectors.map((p) {
      final types = RegExp(
        r'load_hparams: projector:\s*(\S+)',
      ).allMatches(p[0]!).map((m) => m[1]).join(',');
      return '${p[1]}:$types';
    });
    if (reservations.isEmpty ||
        reservations.length !=
            'sched_reserve: reserving ...'.allMatches(context).length ||
        projectors.length !=
            'clip_ctx: CLIP using '.allMatches(context).length ||
        projectorIdentities.join(',') != 'MTL0:gemma4v,MTL0:gemma4a') {
      return false;
    }
    for (final block in [...reservations, ...projectors]) {
      final records = allocations
          .where(
            (a) => a.start >= start + block.start && a.end <= start + block.end,
          )
          .toList();
      final owner = reservations.contains(block)
          ? 'sched_reserve'
          : 'reserve_compute_meta';
      if (records.where((a) => a[2] == 'MTL0').length != 1 ||
          records.any(
            (a) =>
                a[1] != owner ||
                !['MTL0', 'CPU'].contains(a[2]) ||
                (double.tryParse(a[3]!) ?? 0) <= 0,
          )) {
        return false;
      }
      accounted += records.length;
    }
  }
  // Includes CPU scratch buffers: they may accompany Metal, but a CPU-only
  // reservation cannot satisfy the per-block MTL0 requirement above.
  return accounted == allocations.length;
}

final _softwareRenderer = RegExp(
  r'llvmpipe|lavapipe|swiftshader|microsoft basic render driver|software rasterizer',
  caseSensitive: false,
);
final _softwareDevice = RegExp(
  r'\b(cpu|software|virtual)\b',
  caseSensitive: false,
);
final _hardwareVendor = RegExp(
  r'\b(NVIDIA|AMD|Radeon|Intel|Apple|Adreno|Mali|PowerVR|Immortalis|Xclipse|Qualcomm)\b',
  caseSensitive: false,
);

/// Whether every expected load passed exactly once and reported [backend].
bool _loadsReport(
  List<Map<String, dynamic>> cases,
  List<String> expectedIds,
  String backend,
) {
  final loads = cases
      .where((c) => expectedIds.contains(c['case_id']) && c['status'] == 'PASS')
      .toList();
  return expectedIds.isNotEmpty &&
      expectedIds.every(
        (id) => loads.where((c) => c['case_id'] == id).length == 1,
      ) &&
      loads.every((c) {
        final name = (c['diagnostics'] as Map?)?['backend_name'];
        return name is String && name.toLowerCase().contains(backend);
      });
}

/// LiteRT-LM tags whose sources were read for the two rules
/// [_inspectLiteRtGpu] rests on. Before adding a tag, re-read
/// `runtime/executor/llm_executor_settings_utils.cc` and LiteRT's
/// `litert/runtime/compiled_model.cc` at that tag's pins. A `-N` wrapper
/// rebuild is listed only once its upstream sources are confirmed unchanged.
/// v0.18.0-2 and v0.18.0-3 retain both source pins; their patches touch only
/// ASR sources and the conversation finish reason. v0.18.1 keeps the
/// LiteRT-LM source and moves LiteRT to `ca21dc99`, where both rules hold and
/// the undelegated-node count can only grow. v0.18.1-1 and v0.18.1-2 add only XNNPACK
/// CPU kernel patches to those sources. v0.18.1-3 changes only the Windows
/// runtime. v0.18.1-4 patches only LiteRT's CPU options identifier, which
/// `compiled_model.cc` reads only when the CPU accelerator is requested.
const _liteRtGpuOnlyDelegationTags = {
  '0.18.0',
  '0.18.0-1',
  '0.18.0-2',
  '0.18.0-3',
  '0.18.1',
  '0.18.1-1',
  '0.18.1-2',
  '0.18.1-3',
  '0.18.1-4',
};

/// A logcat `threadtime` record's tag:
/// `MM-DD HH:MM:SS.mmm PID TID L tag: message`.
final _logcatTag = RegExp(
  r'^\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} +\d+ +\d+ [VDIWEF] ([^ :]+) *: ',
);

/// Load-time evidence that LiteRT-LM's main model was delegated to one
/// hardware WebGPU-on-Vulkan adapter on Android for every expected load.
///
/// The LiteRT-LM GPU executor requests the GPU accelerator alone, and LiteRT
/// then refuses to compile a model with an undelegated node, so one completed
/// GPU delegate initialization per expected load implies full delegation of
/// the main model. The delegate-kernel count is a consistency check on top of
/// that rule, not proof by itself. No generation request is observed, and the
/// embedding models LiteRT-LM loads beside the main model and any CPU engine
/// the process creates are outside this evidence.
///
/// [log] is logcat `threadtime` records, as collection retains them. Adapter
/// and delegate-kernel records count only under the `native` tag and
/// signature and environment records only under `litert`, as LiteRT-LM 0.18.0
/// logs them; the same text under another tag, such as a Dart `print` under
/// `flutter`, leaves placement unverified. Failure markers count under any
/// tag and are not exhaustive.
///
/// Accelerator registration records are ignored: a CPU engine logs them too.
/// Metal, OpenCL, desktop and Web logs have no qualified shape here.
Map<String, dynamic> _inspectLiteRtGpu(
  Map<String, dynamic> manifest,
  List<Map<String, dynamic>> cases,
  List<String> expectedIds,
  String log,
  Map<String, dynamic> result,
) {
  Map<String, dynamic> unverified(
    String reason, [
    Map<String, dynamic> details = const {},
  ]) => {...result, 'reason': reason, 'placement': 'unverified', ...details};

  final environment = manifest['environment'];
  if (environment is! Map ||
      environment['platform'] != 'android' ||
      environment['web'] != false) {
    return unverified(
      'LiteRT GPU placement evidence is defined only for Android WebGPU on Vulkan',
    );
  }
  if (!_liteRtGpuOnlyDelegationTags.contains(environment['litert_tag'])) {
    return unverified(
      'LiteRT-LM tag is not source-qualified for GPU-only delegation',
    );
  }
  if (!_loadsReport(cases, expectedIds, 'gpu')) {
    return unverified(
      'expected load cases did not each pass once reporting the GPU backend',
    );
  }
  final expectedLoads = expectedIds.length;
  final lowered = log.toLowerCase();
  final failures = [
    for (final marker in liteRtGpuFailureMarkers)
      if (lowered.contains(marker.toLowerCase())) marker,
  ];
  final adapter = RegExp(
    r'Selected adapter: (([^,]+), arch=[^,]*, vendor=[^,]*, '
    r'backend=([^,]+), adapterType=([^,]+))$',
  );
  final loaded = RegExp(r'Loaded: num_subgraphs=\d+, num_signatures=(\d+)');
  final kernel = RegExp(
    r'Total \d+ external tensors are used for delegate inputs and outputs',
  );
  const created = 'Created a WebGPU environment.';

  // One window per engine load, opened by its adapter selection. The main
  // model's signature record is the last one before that selection and
  // declares more signatures than any other record in the log; the embedding
  // models' records follow the main model's delegate kernels.
  final adapters = <RegExpMatch>[];
  final signatures = <int?>[];
  final environments = <int>[];
  final kernels = <int>[];
  var adapterMentions = 0;
  var beforeFirstLoad = 0;
  var unusable = 0;
  var mostOtherSignatures = 0;
  int? pendingSignatures;
  for (final line in const LineSplitter().convert(log)) {
    final tag = _logcatTag.firstMatch(line)?[1];
    final selects = line.contains('Selected adapter:');
    final record = loaded.firstMatch(line);
    final count = record == null ? null : int.tryParse(record[1]!);
    final initialized = kernel.allMatches(line).length;
    final ready = created.allMatches(line).length;
    if (selects) adapterMentions++;
    if ((selects || initialized > 0) && tag != 'native' ||
        (record != null || ready > 0) && tag != 'litert' ||
        record != null && count == null) {
      unusable++;
      continue;
    }
    if (selects) {
      final match = adapter.firstMatch(line);
      if (match != null) {
        adapters.add(match);
        signatures.add(pendingSignatures);
        environments.add(0);
        kernels.add(0);
        pendingSignatures = null;
      }
    }
    if (count != null) {
      mostOtherSignatures = math.max(
        mostOtherSignatures,
        pendingSignatures ?? 0,
      );
      pendingSignatures = count;
    }
    if (adapters.isEmpty) {
      beforeFirstLoad += initialized + ready;
    } else {
      kernels.last += initialized;
      environments.last += ready;
    }
  }
  mostOtherSignatures = math.max(mostOtherSignatures, pendingSignatures ?? 0);
  final identities = {for (final match in adapters) match[1]!};
  final details = <String, dynamic>{
    'expected_loads': expectedLoads,
    'adapter': identities.length == 1 ? identities.single : null,
    'adapter_records': adapterMentions,
    'environment_records': created.allMatches(log).length,
    'signatures_per_load': signatures.toSet().length == 1
        ? signatures.first
        : null,
    'delegate_records': kernel.allMatches(log).length,
    'failure_markers': failures,
  };
  if (failures.isNotEmpty) {
    return unverified(
      'native log reports a GPU delegate failure or CPU fallback',
      details,
    );
  }
  if (unusable != 0) {
    return unverified(
      'GPU delegate records are malformed or were not logged under the '
      'native runtime tags',
      details,
    );
  }
  if (adapterMentions != expectedLoads ||
      adapters.length != expectedLoads ||
      identities.length != 1) {
    return unverified(
      'WebGPU adapter selection is missing, repeated or inconsistent across loads',
      details,
    );
  }
  final selected = adapters.first;
  if (selected[3] != 'Vulkan' ||
      !const ['Integrated GPU', 'Discrete GPU'].contains(selected[4]) ||
      !_hardwareVendor.hasMatch(selected[2]!) ||
      _softwareRenderer.hasMatch(selected[1]!) ||
      _softwareDevice.hasMatch(selected[1]!) ||
      RegExp('basic render', caseSensitive: false).hasMatch(selected[1]!)) {
    return unverified(
      'WebGPU adapter is not a recognized hardware Vulkan GPU',
      details,
    );
  }
  final perLoad = signatures.first;
  if (beforeFirstLoad != 0 ||
      perLoad == null ||
      perLoad < 1 ||
      perLoad <= mostOtherSignatures ||
      signatures.any((count) => count != perLoad) ||
      environments.any((count) => count != 1) ||
      kernels.any((count) => count != perLoad)) {
    return unverified(
      'WebGPU environment or delegate initialization records are incomplete or contradictory',
      details,
    );
  }
  return {
    ...result,
    'verified': true,
    'reason':
        'matching runtime diagnostics and a hardware WebGPU/Vulkan delegate '
        'initialized for all $perLoad main-model signatures of all '
        '$expectedLoads loads; per-request execution and embedding-model '
        'placement are unobserved',
    'placement': 'gpu_delegate_initialized_per_load_execution_unobserved',
    ...details,
  };
}

Map<String, dynamic> _inspectNpu(
  Map<String, dynamic> manifest,
  List<Map<String, dynamic>> cases,
  List<String> selected,
  Map<String, dynamic> result,
) {
  final profile = manifest['profile'] as Map;
  final target = profile['npu_target'] as Map? ?? {};
  final identity = (manifest['preparation'] as Map?)?['npu'] as Map? ?? {};
  final device = identity['device'] as Map? ?? {};
  final kit = identity['kit'] as Map? ?? {};
  final libraries = kit['libraries'] as Map? ?? {};
  final locks = target['libraries'] as Map? ?? {};
  final aliases = target['device_soc_models'] as List? ?? [];
  final identitiesMatch =
      locks.isNotEmpty &&
      kit['target'] == target['soc'] &&
      kit['runtime_tag'] == (manifest['environment'] as Map?)?['litert_tag'] &&
      kit['schema_version'] == 1 &&
      kit['litert_revision'] == '9fe5be45564c868408e6514c8aabb83e211a0911' &&
      kit['dispatch_header_sha256'] ==
          '11dd4d98bd084157ac987b1ee1951f3f96e2b3ca6b51a27c10e645686bf0e3ee' &&
      device['verified'] == true &&
      device['abi'] == target['abi'] &&
      device['android_api'] is int &&
      target['minimum_android_api'] is int &&
      (device['android_api'] as int) >=
          (target['minimum_android_api'] as int) &&
      aliases.any(
        (soc) => '$soc'.toLowerCase() == '${device['soc_model']}'.toLowerCase(),
      ) &&
      libraries.length == locks.length &&
      locks.entries.every((entry) {
        final value = libraries[entry.key];
        final lock = entry.value as Map;
        return value is Map &&
            value['bytes'] is int &&
            (value['bytes'] as int) > 0 &&
            RegExp(r'^[a-f0-9]{64}$').hasMatch('${value['sha256']}') &&
            (lock['sha256'] == null || value['sha256'] == lock['sha256']);
      });
  final version = (manifest['catalog'] as Map?)?['version'];
  final expected = selected.where(
    (id) => [
      'C03.raw',
      'C04.hello',
      'C04.arithmetic',
      'C06.history',
      'C06.history.public_system_wire',
      'C06.history.no_system',
      'C06.history.combined',
      'C08.cancel',
      'C09.reload',
      'C10.limit',
      'C12.recovery',
      'B01.warmup',
      'B01.1',
      'B01.2',
      'B01.3',
      'C09.reload.second',
      'C10.stop',
      'C12.guards',
      if (version is int && version >= 4) ...[
        'C02.generate',
        'C05.thinking',
        'C07.tools',
      ],
      if (version is int && version >= 5) ...[
        'C08.cancel.early',
        'C07.tools.auto_text',
      ],
    ].contains(id),
  );
  final records = {for (final record in cases) record['case_id']: record};
  var valid = identitiesMatch;
  var proven = 0;
  List<int>? previous;
  for (final id in expected) {
    final record = records[id];
    if (record == null) {
      valid = false;
      continue;
    }
    final generations = switch (id) {
      'C08.cancel' => [
        record['uncancelled_control'],
        record,
        record['recovery'],
      ],
      'C10.stop' => [record['control'], record['stopped'], record['recovery']],
      'C12.guards' || 'C08.cancel.early' => [record['recovery']],
      'C05.thinking' => [
        for (var i = 0; i < 2; i++)
          record['trials'] is List && (record['trials'] as List).length > i
              ? (record['trials'] as List)[i]
              : null,
      ],
      'C07.tools' => [
        for (var i = 0; i < 3; i++) ...[
          record['trials'] is List && (record['trials'] as List).length > i
              ? (record['trials'] as List)[i]
              : null,
          if (i < 2)
            record['trials'] is List &&
                    (record['trials'] as List).length > i &&
                    (record['trials'] as List)[i] is Map
                ? ((record['trials'] as List)[i] as Map)['tool_result_followup']
                : null,
        ],
        record['recovery'],
      ],
      _ => [record],
    };
    for (final generation in generations) {
      final evidence = generation is Map ? generation['npu_execution'] : null;
      final before = evidence is Map ? evidence['before'] : null;
      final after = evidence is Map ? evidence['after'] : null;
      if (before is! List ||
          after is! List ||
          before.any((v) => v is! int) ||
          after.any((v) => v is! int)) {
        valid = false;
        continue;
      }
      final start = before.cast<int>();
      final end = after.cast<int>();
      final checked = npuGenerationEvidence(start, end);
      if (checked['verified'] != true ||
          (previous != null &&
              (start.length != 7 ||
                  List.generate(
                    5,
                    (i) => start[i + 1] < previous![i + 1],
                  ).any((v) => v)))) {
        valid = false;
      } else {
        proven++;
      }
      if (end.length == 7) previous = end;
    }
  }
  return {
    ...result,
    'verified': valid,
    'reason': valid
        ? 'Per-generation completed vendor calls; CPU partitions remain unknown'
        : 'Missing, inconsistent or failed per-generation NPU evidence/device identity',
    'placement': valid
        ? 'npu_participation_cpu_partitions_unknown'
        : 'unverified',
    'proven_generations': proven,
    'native_reference_only': profile['execution_path'] == 'native_c_api',
  };
}
