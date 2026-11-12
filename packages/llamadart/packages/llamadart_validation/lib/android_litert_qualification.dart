/// Private S24 LiteRT admission and evidence checks; never submits a device run.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'src/manifest.dart';
import 'src/s24_litert_capture.dart';

const s24LiteRtCpuHash =
    'c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108';
const s24LiteRtGpuHash =
    '555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4';
const s24LiteRtFallbackWarning =
    'LiteRT-LM could not create a GPU engine under ComputeDevice.auto; '
    'retrying on the CPU.';
const s24LiteRtNativeLibraries = {
  'libLiteRtLm.so',
  'libLiteRtGpuAccelerator.so',
  'libLiteRtOpenClAccelerator.so',
  'libLiteRtWebGpuAccelerator.so',
  'libGemmaModelConstraintProvider.so',
  'libwebgpu_dawn.so',
};

/// Owner runtime tags the S24 binding admits. `v0.19.1-1` rebuilt only the
/// Linux and Windows hosts; its Android binaries are byte-identical to
/// `v0.19.1` (#1808). `v0.19.1-2` changes only the Android `libLiteRtLm.so`
/// and passed the full S24 graph again (Test Lab `matrix-wmalbq6nz437a`,
/// #1830). `v0.19.1-3` and `v0.19.1-4` leave Android unchanged: their
/// Android arm64 archives hold the same libraries as `v0.19.1-2` (#1798, #1911).
const s24LiteRtRuntimeTags = {
  'v0.19.1',
  'v0.19.1-1',
  'v0.19.1-2',
  'v0.19.1-3',
  'v0.19.1-4',
};

/// Fixed prospective stage caps sum to 1,050s; FTL still caps the run at 1,200s.
const s24LiteRtStageSeconds = {
  'staging-and-identity': 120,
  'native-guard': 120,
  'public-gpu-refusal': 60,
  'native-cpu-corrected': 120,
  'public-cpu-corrected': 150,
  'public-auto-legacy': 150,
  'native-gpu-corrected': 120,
  'public-auto-corrected': 150,
  'cleanup-and-export': 60,
};

final List<String> s24LiteRtCases = List.unmodifiable([
  's24.native.launch',
  's24.native.gpu-guard',
  'public.legacy.gpu-refusal',
  's24.native.cpu-corrected',
  for (final route in ['cpu-corrected', 'auto-legacy', 'auto-corrected']) ...[
    for (final lifetime in [1, 2]) ...[
      '$route.$lifetime.hello',
      '$route.$lifetime.arithmetic',
    ],
    '$route.cancel',
  ],
  's24.native.gpu-corrected',
]);

String s24LiteRtHash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

void requireS24LiteRtProfile(Map<String, dynamic> value, String backend) {
  final profile = ValidationProfile.fromJson(value);
  _require(
    profile.id == 'chat-litert-$backend' &&
        value['runtime'] == 'litert' &&
        value['backend'] == backend &&
        value['context_size'] == 1024 &&
        value['threads'] == 4 &&
        value['max_tokens'] == 32,
    'S24 requires the unchanged maintained chat profile configuration',
  );
  final model = value['model'] as Map;
  final revision = backend == 'cpu'
      ? 'e6687177e00897731e7716267eebd4eba0dde7c2'
      : '8414150f2e9dcc82449bcc9c5abc404b399a4d06';
  _require(
    model['id'] == 'chat-litert' &&
        model['filename'] == 'Qwen3-0.6B.litertlm' &&
        model['kind'] == 'chat' &&
        model['revision'] == revision &&
        model['url'] ==
            'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/$revision/Qwen3-0.6B.litertlm',
    'Model metadata must identify its own maintained CPU or GPU artifact',
  );

  _require(
    model['sha256'] ==
            (backend == 'cpu' ? s24LiteRtCpuHash : s24LiteRtGpuHash) &&
        model['bytes'] == (backend == 'cpu' ? 613722264 : 614236160),
    'S24 CPU and GPU artifacts must retain their separate model locks',
  );
  _require(
    canonicalJson(value['fixtures']) ==
        canonicalJson({
          'hello': {
            'prompt': 'Reply with one short sentence saying hello.',
            'regex': r'\bhello\b',
          },
          'arithmetic': {
            'prompt': 'What is 3 + 4? Reply with only the number.',
            'regex': r'^(?:3 \+ 4 = )?7[.!]?$',
          },
        }),
    'The maintained C04 prompts and semantic oracles cannot change',
  );
}

/// Validates a prospective final build binding, independently of run claims.
void requireS24LiteRtBinding(Map<String, dynamic> value) {
  _require(
    value['schema'] == 1 &&
        value['source_dirty'] == false &&
        s24LiteRtRuntimeTags.contains(value['runtime_tag']) &&
        value['abi'] == 'android-arm64' &&
        value['test_class'] ==
            'com.example.llamadart_chat_example.S24LiteRtPublicTest' &&
        value['max_minutes'] == 20 &&
        value['execution_count'] == 1 &&
        value['reservation_usd'] == '2.50' &&
        value['shared_cap_usd'] == '22.50',
    'S24 admission requires one bounded run and the existing shared budget',
  );
  for (final key in ['source_commit', 'source_tree', 'owner_commit']) {
    _require(
      value[key] is String && RegExp(r'^[a-f0-9]{40}$').hasMatch(value[key]),
      'Missing exact source/owner revision: $key',
    );
  }
  _require(
    value['owner_commit'] != '7ea10d0cce10dfddbae273bb69e253d9ea97e1d2',
    'The aborted 7ea candidate is not the final rebuilt owner artifact',
  );
  for (final key in [
    'source_inventory_sha256',
    'runtime_archive_sha256',
    'runtime_manifest_sha256',
    'shared_budget_receipt_sha256',
    'template_sha256',
    'child_sha256',
  ]) {
    _require(
      value[key] is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value[key]),
      'Missing admitted source/artifact/budget binding: $key',
    );
  }
  final inventory = value['libraries'];
  _require(inventory is Map, 'Missing installed native inventory');
  _require(
    (inventory as Map)['libllamadart_litert_child.so']?['sha256'] ==
        value['child_sha256'],
    'The owned child executable must be part of the APK inventory',
  );
  final profiles = value['profiles'];
  _require(profiles is Map, 'Missing maintained profiles');
  for (final backend in ['cpu', 'gpu']) {
    _require(
      (profiles as Map)[backend] is Map,
      'Missing maintained $backend profile',
    );
    requireS24LiteRtProfile(
      Map<String, dynamic>.from(profiles[backend] as Map),
      backend,
    );
  }
  _require(
    inventory.keys.toSet().containsAll(s24LiteRtNativeLibraries),
    'Incomplete Android owner runtime inventory',
  );
  _require(
    value['owner_libraries'] is Map &&
        canonicalJson(value['owner_libraries']) ==
            canonicalJson(value['archive_libraries']) &&
        (value['owner_libraries'] as Map).keys.toSet().containsAll(
          s24LiteRtNativeLibraries,
        ),
    'Owner libraries must match the complete admitted archive',
  );
  for (final entry in (value['owner_libraries'] as Map).entries) {
    _require(
      canonicalJson(inventory[entry.key]) == canonicalJson(entry.value),
      'APK owner payload differs from its archive',
    );
  }
  for (final entry in inventory.entries) {
    _require(
      entry.key is String &&
          RegExp(r'^lib[A-Za-z0-9_.+-]+\.so$').hasMatch(entry.key) &&
          entry.value is Map &&
          entry.value['bytes'] is int &&
          entry.value['bytes'] > 0 &&
          entry.value['sha256'] is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value['sha256']),
      'Invalid runtime library identity',
    );
  }
}

/// Grades copied public bytes only after the caller has persisted them.
void requireS24LiteRtAnswer(String name, List<int> bytes) {
  _require(
    const ['hello', 'arithmetic'].contains(name),
    'Unknown fixed C04 fixture',
  );
  final text = utf8.decode(bytes);
  _require(
    !text.contains('<think>') && !text.contains('</think>'),
    'Thinking delimiters escaped into the public answer',
  );
  final expression = name == 'hello'
      ? RegExp(r'\bhello\b', caseSensitive: false)
      : RegExp(r'^(?:3 \+ 4 = )?7[.!]?$');
  _require(expression.hasMatch(text.trim()), 'Fixed C04 $name oracle failed');
}

/// Minimum observable proof; public backend labels alone are not placement proof.
void requireS24LiteRtCpuObservation(
  Map<String, dynamic> value, {
  required bool automatic,
  required String lifetimeId,
}) {
  _require(
    value['backend_name'] == 'LiteRT-LM cpu' &&
        value['reported_gpu_layers'] == 0 &&
        value['native_finish'] == 'not_exposed_by_default_service' &&
        value['native_settlement'] == 'settled' &&
        value['input_tokens'] is int &&
        value['input_tokens'] > 0 &&
        value['output_tokens'] is int &&
        value['output_tokens'] > 0 &&
        value['mapped_core_verified'] == true,
    'CPU functionality lacks correlated native/provenance/lifecycle evidence',
  );
  List<int> captured(Map value) => decodeS24LiteRtCapture(value);

  final initialization = value['process_cpu_delegate_initialization'];
  final current = value['native_stderr'];
  _require(
    initialization is Map &&
        initialization['pid'] == value['public_process_pid'] &&
        current is Map &&
        current['lifetime_id'] == lifetimeId &&
        current['empty_at_load'] == true,
    'CPU initialization scope or fresh lifetime capture differs',
  );
  final processLog = utf8.decode(
    captured((initialization as Map)['capture'] as Map),
    allowMalformed: true,
  );
  final currentLog = utf8.decode(
    captured(current as Map),
    allowMalformed: true,
  );
  _require(
    processLog.contains('Created TensorFlow Lite XNNPACK delegate for CPU.') &&
        currentLog.contains(
          'Flatbuffer model initialized directly from incoming litert model.',
        ),
    'Need process-wide CPU initialization and fresh current-lifetime native compilation',
  );
  final warnings = value['warnings'];
  _require(warnings is List, 'Missing per-lifetime warning capture');
  final observed = (warnings as List).whereType<String>().any(
    (line) => line.contains(s24LiteRtFallbackWarning),
  );
  _require(
    observed == automatic,
    'Auto requires observed GPU failure then CPU recovery; explicit CPU must skip it',
  );
}
