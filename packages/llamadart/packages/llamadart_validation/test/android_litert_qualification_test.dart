import 'dart:convert';
import 'dart:io';

// The binding must admit the runtime the hook pins.
// ignore: implementation_imports
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:llamadart_validation/android_litert_qualification.dart';
import 'package:llamadart_validation/android_litert_qualification_io.dart';
import 'package:test/test.dart';

Map<String, dynamic> profile(String backend) =>
    jsonDecode(
          File('assets/profiles/chat-litert-$backend.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
String repeated(String value, int count) => List.filled(count, value).join();
Map<String, dynamic> binding() {
  final libraries = {
    for (final name in s24LiteRtNativeLibraries)
      name: {'bytes': 7, 'sha256': repeated('a', 64)},
  };
  return {
    'schema': 1,
    'source_dirty': false,
    'source_commit': repeated('a', 40),
    'source_tree': repeated('b', 40),
    'owner_commit': repeated('c', 40),
    for (final key in [
      'source_inventory_sha256',
      'runtime_archive_sha256',
      'runtime_manifest_sha256',
      'shared_budget_receipt_sha256',
      'template_sha256',
    ])
      key: repeated('d', 64),
    'runtime_tag': 'v0.19.1',
    'abi': 'android-arm64',
    'test_class': 'com.example.llamadart_chat_example.S24LiteRtPublicTest',
    'max_minutes': 20,
    'execution_count': 1,
    'reservation_usd': '2.50',
    'shared_cap_usd': '22.50',
    'profiles': {'cpu': profile('cpu'), 'gpu': profile('gpu')},
    'libraries': {
      ...libraries,
      'libllamadart_litert_child.so': {'bytes': 7, 'sha256': repeated('a', 64)},
    },
    'child_sha256': repeated('a', 64),
    'archive_libraries': jsonDecode(jsonEncode(libraries)),
    'owner_libraries': jsonDecode(jsonEncode(libraries)),
  };
}

Map<String, dynamic> observation({
  bool automatic = false,
  String lifetimeId = 'cpu-corrected.1',
}) => {
  'backend_name': 'LiteRT-LM cpu',
  'reported_gpu_layers': 0,
  'native_finish': 'not_exposed_by_default_service',
  'native_settlement': 'settled',
  'input_tokens': 12,
  'output_tokens': 3,
  'public_process_pid': 123,
  'process_cpu_delegate_initialization': {
    'pid': 123,
    'capture': captureS24LiteRtBytes(
      utf8.encode('Created TensorFlow Lite XNNPACK delegate for CPU.'),
    ),
  },
  'native_stderr': {
    ...captureS24LiteRtBytes(
      utf8.encode(
        'Flatbuffer model initialized directly from incoming litert model.',
      ),
    ),
    'lifetime_id': lifetimeId,
    'empty_at_load': true,
  },
  'mapped_core_verified': true,
  'warnings': [if (automatic) '$s24LiteRtFallbackWarning More details.'],
};

void main() {
  test(
    'maintained profiles keep distinct byte identities and fixed C04 oracles',
    () {
      for (final backend in ['cpu', 'gpu']) {
        requireS24LiteRtProfile(profile(backend), backend);
      }
      final changed = profile('gpu');
      (changed['model'] as Map)['sha256'] = s24LiteRtCpuHash;
      expect(
        () => requireS24LiteRtProfile(changed, 'gpu'),
        throwsFormatException,
      );
      final prompt = profile('cpu');
      (prompt['fixtures'] as Map)['arithmetic']['prompt'] = 'What is 2 + 2?';
      expect(
        () => requireS24LiteRtProfile(prompt, 'cpu'),
        throwsFormatException,
      );
    },
  );
  test(
    'binding needs final owner, complete payloads and original shared cap',
    () {
      requireS24LiteRtBinding(binding());
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (value) =>
            value['owner_commit'] = '7ea10d0cce10dfddbae273bb69e253d9ea97e1d2',
        (value) => value['source_dirty'] = true,
        (value) => value['runtime_tag'] = 'v0.19.0',
        (value) => value.remove('shared_budget_receipt_sha256'),
        (value) => value['shared_cap_usd'] = '25.00',
        (value) => value['execution_count'] = 2,
        (value) => (value['libraries'] as Map).remove('libwebgpu_dawn.so'),
        (value) => value['owner_libraries']['libLiteRtLm.so']['sha256'] =
            repeated('f', 64),
      ]) {
        final value = binding();
        mutation(value);
        expect(() => requireS24LiteRtBinding(value), throwsFormatException);
      }
    },
  );
  test('binding admits only the listed runtime tags, including the pin', () {
    expect(
      s24LiteRtRuntimeTags,
      contains(liteRtLmReleaseTag),
      reason:
          'Requalify S24 on $liteRtLmReleaseTag, or admit it only if its '
          'Android arm64 binaries match an admitted tag.',
    );
    for (final tag in s24LiteRtRuntimeTags) {
      requireS24LiteRtBinding(binding()..['runtime_tag'] = tag);
    }
    for (final tag in <Object?>[
      'v0.19.0',
      'v0.19.1-5',
      'v0.19.2',
      'v0.20.0',
      '0.19.1-1',
      'v0.19.1 ',
      null,
    ]) {
      expect(
        () => requireS24LiteRtBinding(binding()..['runtime_tag'] = tag),
        throwsFormatException,
        reason: '$tag',
      );
    }
  });
  test('raw capture preserves invalid UTF8 and NUL without interpretation', () {
    final raw = [0, 0xc3, 0x8a, 0xff];
    final captured = captureS24LiteRtBytes(raw);
    expect(readS24LiteRtBytes(captured), raw);
    captured['base64'] = base64Encode([0, 0xc3]);
    expect(() => readS24LiteRtBytes(captured), throwsFormatException);
  });
  test('Pixel-shared capture stays base64 while S24 explicitly opts in', () {
    final raw = utf8.encode('native capture lines\n' * 100);
    final original = captureS24LiteRtBytes(raw);
    final compact = captureCompactS24LiteRtBytes(raw);
    expect(original['base64'], base64Encode(raw));
    expect(original.containsKey('utf8'), isFalse);
    expect(compact.containsKey('utf8'), isTrue);
    expect(readS24LiteRtBytes(original), raw);
    expect(readS24LiteRtBytes(compact), raw);
  });
  test('C04 semantic oracles do not become transport-only passes', () {
    requireS24LiteRtAnswer('hello', utf8.encode('Hello!'));
    requireS24LiteRtAnswer('arithmetic', utf8.encode('7'));
    requireS24LiteRtAnswer('arithmetic', utf8.encode('3 + 4 = 7.'));
    for (final wrong in ['2', '4', 'Osaka', '7 extra', '<think>7</think>']) {
      expect(
        () => requireS24LiteRtAnswer('arithmetic', utf8.encode(wrong)),
        throwsFormatException,
      );
    }
  });
  test(
    'auto requires correlated failure and CPU evidence, not selector hints',
    () {
      requireS24LiteRtCpuObservation(
        observation(),
        automatic: false,
        lifetimeId: 'cpu-corrected.1',
      );
      requireS24LiteRtCpuObservation(
        observation(automatic: true, lifetimeId: 'cpu-corrected.1'),
        automatic: true,
        lifetimeId: 'cpu-corrected.1',
      );
      expect(
        () => requireS24LiteRtCpuObservation(
          observation(),
          automatic: true,
          lifetimeId: 'cpu-corrected.1',
        ),
        throwsFormatException,
      );
      for (final key in ['mapped_core_verified']) {
        final value = observation(
          automatic: true,
          lifetimeId: 'cpu-corrected.1',
        )..[key] = false;
        expect(
          () => requireS24LiteRtCpuObservation(
            value,
            automatic: true,
            lifetimeId: 'cpu-corrected.1',
          ),
          throwsFormatException,
        );
      }
      final stale = observation();
      (stale['native_stderr'] as Map)['lifetime_id'] = 'cpu-corrected.0';
      expect(
        () => requireS24LiteRtCpuObservation(
          stale,
          automatic: false,
          lifetimeId: 'cpu-corrected.1',
        ),
        throwsFormatException,
      );
      final inventedFinish = observation()..['native_finish'] = 'stop';
      expect(
        () => requireS24LiteRtCpuObservation(
          inventedFinish,
          automatic: false,
          lifetimeId: 'cpu-corrected.1',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'S24 child ignores GGUF grading but requires every raw transport receipt',
    () {
      final lock = repeated('a', 64);
      final rows = [
        {
          'schema': 1,
          'binding': lock,
          'case_id': 's24.native.launch',
          'pid': 123,
          'sequence': 0,
          'event': 'started',
        },
        {
          'schema': 1,
          'binding': lock,
          'case_id': 's24.native.launch',
          'pid': 123,
          'sequence': 1,
          'event': 'finished',
        },
      ];
      final out = utf8.encode("${rows.map(jsonEncode).join('\n')}\n");
      final err = utf8.encode('actual stderr bytes');
      final receipt = <String, dynamic>{
        'binding': lock,
        'case_id': 's24.native.launch',
        'pid': 123,
        'exit_code': 0,
        'timed_out': false,
        'capture_limit_exceeded': false,
        'capture_failed': false,
        'elapsed_ms': 100,
        'protocol_complete': false,
        'files': {
          'stdout.jsonl': captureS24LiteRtBytes(out),
          'stderr.log': captureS24LiteRtBytes(err),
        },
      };
      List<Map<String, dynamic>> parse(Map value, [List<int>? output]) =>
          readS24LiteRtChildRecords(
            value,
            output ?? out,
            err,
            binding: lock,
            caseId: 's24.native.launch',
          );
      expect(parse(receipt), hasLength(2));
      for (final key in [
        'timed_out',
        'capture_limit_exceeded',
        'capture_failed',
      ]) {
        expect(() => parse({...receipt, key: true}), throwsFormatException);
      }
      expect(() => parse({...receipt, 'exit_code': -6}), throwsFormatException);
      expect(() => parse({...receipt, 'pid': 456}), throwsFormatException);
      expect(
        () => parse(receipt, out.sublist(0, out.length - 1)),
        throwsFormatException,
      );
    },
  );
  test(
    'raw native response keeps fixed positive oracle separate from transport',
    () {
      final wrong = utf8.encode(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': '2'},
          ],
        }),
      );
      final answer = readS24LiteRtNativeAnswer(wrong);
      expect(answer, '2');
      expect(
        () => requireS24LiteRtAnswer('arithmetic', utf8.encode(answer)),
        throwsFormatException,
      );
      expect(
        () => readS24LiteRtNativeAnswer(utf8.encode('{}')),
        throwsFormatException,
      );
      expect(() => readS24LiteRtHex('8a2'), throwsFormatException);
    },
  );
  test('GPU initialization needs hardware records and rejects failure markers', () {
    const log =
        'Selected adapter: Adreno (TM) 750, arch=adreno, vendor=Qualcomm, backend=Vulkan, adapterType=Integrated GPU\n'
        'Created a WebGPU environment.\nTotal 2 external tensors are used for delegate inputs and outputs';
    expect(s24LiteRtGpuInitialized(log), isTrue);
    expect(s24LiteRtGpuInitializationBackend(log), 'Vulkan');
    expect(
      s24LiteRtGpuInitialized(log.replaceAll('Total 2', 'Total 0')),
      isFalse,
    );
    expect(s24LiteRtGpuInitialized('$log\nSelected adapter: CPU'), isFalse);
    expect(s24LiteRtGpuInitialized('GPU registered'), isFalse);
    expect(
      s24LiteRtGpuInitialized(log.replaceAll('Vulkan', 'OpenGL')),
      isFalse,
    );
    expect(s24LiteRtGpuInitialized('$log\nVK_ERROR_DEVICE_LOST'), isFalse);
    expect(s24LiteRtStageSeconds.values.fold<int>(0, (a, b) => a + b), 1050);
    expect(s24LiteRtStageSeconds.values.every((value) => value <= 150), isTrue);
  });
  test(
    'authentic Vulkan lifetime retains shared environment and CPU embedder',
    () {
      final lines = File(
        'test/fixtures/android_logcat/galaxys24-gemma4-litert-gpu.logcat.txt',
      ).readAsLinesSync();
      final lifetime = lines.take(114).join('\n');
      final initialization = [
        45,
        46,
        49,
        53,
      ].map((n) => lines[n - 1]).join('\n');
      for (final log in [lifetime, initialization]) {
        expect(s24LiteRtGpuInitializationBackend(log), 'Vulkan');
        expect(s24LiteRtGpuInitialized(log), isTrue);
      }
      expect(lifetime, contains('Failed to load OpenCL library with dlopen:'));
      expect(lifetime, contains('Trying ICD loader.'));
      expect(
        lifetime,
        contains('Created TensorFlow Lite XNNPACK delegate for CPU.'),
      );
      final negatives = <String, String>{
        'CPU fallback': '$lifetime\nFalling back to CPU',
        'CPU graph':
            '$lifetime\nReplacing 1 out of 1 node(s) with delegate (XNNPACK)',
        'unbound CPU delegate':
            '$lifetime\nCreated TensorFlow Lite XNNPACK delegate for CPU.',
        'wrong CPU model': lifetime.replaceAll(
          'signature=embedder,',
          'signature=decode,',
        ),
        'multiple CPU graphs': lifetime.replaceAll(
          'Loaded: num_subgraphs=1, num_signatures=1',
          'Loaded: num_subgraphs=2, num_signatures=1',
        ),
        'uncompiled CPU model': lifetime.replaceAll(
          'Flatbuffer model initialized directly from incoming litert model.',
          'Missing compiled model',
        ),
        'GPU failure':
            '$lifetime\nGPU accelerator could not be loaded and registered',
        'shared environment failure':
            '$lifetime\nGpuEnvironment initialization failed',
        'delegate failure': '$lifetime\nGPU delegate initialization failed',
        'GPU device lost': '$lifetime\nVK_ERROR_DEVICE_LOST',
        'OpenCL device conflict':
            '$lifetime\nCreated OpenCL device from provided device id and platform id.',
        'OpenCL API conflict':
            '$lifetime\nInitializing OpenCL-based API from serialized data.',
        'OpenCL graph conflict': '$lifetime\nLITERT_CL',
      };
      for (final entry in negatives.entries) {
        expect(
          s24LiteRtGpuInitializationBackend(entry.value),
          isNull,
          reason: entry.key,
        );
      }
    },
  );
  test('owned OpenCL log requires both full ordered positive GPU graphs', () {
    final log = File('test/fixtures/s24_opencl_stderr.txt').readAsStringSync();
    expect(
      captureS24LiteRtBytes(utf8.encode(log))['sha256'],
      'f26a99f7e73e3d76b92a740794de3e9794ae843714a8a111a161d0624ebb5007',
    );
    expect(s24LiteRtGpuInitializationBackend(log), 'OpenCL');
    expect(s24LiteRtGpuInitialized(log), isTrue);
    final negatives = <String, String>{
      'library only': 'INFO: Loaded OpenCL library with dlopen.',
      'CPU registry only': 'XNNPACK CPU accelerator registered.',
      'shared environment only': 'Created LiteRT GpuEnvironment.',
      'loader failure on OpenCL':
          '$log\nFailed to load OpenCL library with dlopen: dlopen failed: library libvndksupport.so not found. Trying ICD loader.',
      'missing device': log.replaceAll(
        'Created OpenCL device',
        'Absent device',
      ),
      'missing environment': log.replaceAll(
        'Created LiteRT GpuEnvironment.',
        '',
      ),
      'zero graph': log.replaceAll('1306 out of 1306', '0 out of 0'),
      'partial decode': log.replaceAll('1306 out of 1306', '1305 out of 1306'),
      'partial prefill': log.replaceAll('1358 out of 1358', '1357 out of 1358'),
      'malformed counts': log.replaceAll(
        '1306 out of 1306',
        '1306x out of 1306',
      ),
      'noncanonical counts': log.replaceAll(
        '1306 out of 1306',
        '01306 out of 01306',
      ),
      'overflow counts': log.replaceAll(
        '1306 out of 1306',
        '${'9' * 30} out of ${'9' * 30}',
      ),
      'overflow tensors': log.replaceAll('Total 113', 'Total ${'9' * 30}'),
      'no delegation': log.replaceAll(
        RegExp(r'^VERBOSE: Replacing.*$', multiLine: true),
        '',
      ),
      'decode only': log.replaceAll(
        RegExp(r'^VERBOSE: Replacing.*prefill_128.*$', multiLine: true),
        '',
      ),
      'multiple partitions': log.replaceAll(
        'yielding 1 partitions',
        'yielding 2 partitions',
      ),
      'zero tensors': log.replaceAll('Total 113', 'Total 0'),
      'missing API': log.replaceFirst(
        'Initializing OpenCL-based API from serialized data.',
        '',
      ),
      'wrong graph': log.replaceAll(
        'subgraph 0 (decode)',
        'subgraph 0 (prefill_128)',
      ),
      'missing prefill': log.replaceAll(
        'subgraph 1 (prefill_128)',
        'subgraph 2 (prefill_128)',
      ),
      'CPU graph': log.replaceFirst('(LITERT_CL)', '(XNNPACK)'),
      'CPU delegate': '$log\nCreated TensorFlow Lite XNNPACK delegate for CPU.',
      'fallback': '$log\nFalling back to CPU',
      'GPU error': '$log\nOpenCL initialization failed',
      'GPU failure marker': '$log\nFailed to modify graph with delegate',
      'error severity': '$log\nERROR: GPU unavailable',
      'error severity prefix':
          '$log\nE0000 00:00:1793800461 GPU initialization refused',
      'repeated load': '$log\n$log',
      'conflicting backend': '$log\nCreated a WebGPU environment.',
      'conflicting adapter': '$log\nSelected adapter: CPU backend=Vulkan',
    };
    for (final entry in negatives.entries) {
      expect(
        s24LiteRtGpuInitializationBackend(entry.value),
        isNull,
        reason: entry.key,
      );
      expect(s24LiteRtGpuInitialized(entry.value), isFalse, reason: entry.key);
    }
  });
}
