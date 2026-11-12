import 'dart:convert';
import 'dart:io';

import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/placement.dart';
import 'package:test/test.dart';

const _fixtures = 'test/fixtures/android_logcat';
const _label = 'gpu_delegate_initialized_per_load_execution_unobserved';
const _mali =
    'Mali-G715, arch=valhall, vendor=arm, backend=Vulkan, '
    'adapterType=Integrated GPU';
const _adreno =
    'Adreno (TM) 750, arch=adreno-7xx, vendor=qualcomm, backend=Vulkan, '
    'adapterType=Integrated GPU';
const _kernel = 'external tensors are used for delegate inputs and outputs';
const _created = 'Created a WebGPU environment.';
const _main = 'Loaded: num_subgraphs=976, num_signatures=4';
const _embedder = 'Loaded: num_subgraphs=1, num_signatures=1';
const _adapterReason =
    'WebGPU adapter selection is missing, repeated or inconsistent across '
    'loads';
const _recordsReason =
    'WebGPU environment or delegate initialization records are incomplete or '
    'contradictory';
const _tagReason =
    'GPU delegate records are malformed or were not logged under the native '
    'runtime tags';

String _read(String name) =>
    File('$_fixtures/$name').readAsStringSync().replaceAll('\r\n', '\n');

/// The app-process lines from the test start record onward: what collection
/// keeps of a device log it has bound to the journal.
String _bound(String logcat) {
  final lines = const LineSplitter().convert(logcat);
  final start = lines.indexWhere(
    (line) => line.contains(' I flutter : 00:00 +0: shared validation: '),
  );
  final pid = lines[start].split(RegExp(' +'))[2];
  return lines
      .skip(start)
      .where((line) => line.split(RegExp(' +')).elementAtOrNull(2) == pid)
      .map((line) => '$line\n')
      .join();
}

/// A device-log record shaped as the Pixel fixture's app process logs it.
String _record(String tag, String message, {String level = 'I'}) =>
    '10-13 02:45:30.000 22950 26936 $level ${tag.padRight(8)}: $message\n';

String _replaceNth(String text, Pattern from, String to, int index) {
  final match = from.allMatches(text).elementAt(index);
  return text.replaceRange(match.start, match.end, to);
}

String _withoutLine(String text, String containing, {int index = 0}) {
  final lines = const LineSplitter().convert(text);
  final hits = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].contains(containing)) i,
  ];
  lines.removeAt(hits[index]);
  return lines.map((line) => '$line\n').join();
}

void main() {
  final pixelJournal = _read('pixel9pro-gemma4-litert-gpu.events.jsonl');
  final pixel = _bound(_read('pixel9pro-gemma4-litert-gpu.logcat.txt'));
  final galaxyJournal = _read('galaxys24-gemma4-litert-gpu.events.jsonl');
  final galaxy = _bound(_read('galaxys24-gemma4-litert-gpu.logcat.txt'));
  final cpuControl = _bound(_read('pixel9pro-chat-litert-cpu.logcat.txt'));

  List<Map<String, dynamic>> events(String journal) => [
    for (final line in const LineSplitter().convert(journal))
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  Map<String, dynamic> manifest() => events(pixelJournal).first;
  List<Map<String, dynamic>> cases() =>
      events(pixelJournal).where((event) => event['type'] == 'case').toList();
  Map<String, dynamic> inspect(
    String? log, {
    Map<String, dynamic>? of,
    List<Map<String, dynamic>>? records,
  }) => inspectPlacement(of ?? manifest(), records ?? cases(), log);
  void rejects(String log, {String? reason, String? because}) {
    final placement = inspect(log);
    expect(placement['verified'], isFalse, reason: reason ?? '$placement');
    expect(placement['placement'], 'unverified', reason: reason);
    if (because != null) expect(placement['reason'], because, reason: reason);
  }

  group('LiteRT GPU delegate evidence', () {
    for (final (name, journal, log, adapter) in [
      ('Pixel 9 Pro Mali', pixelJournal, pixel, _mali),
      ('Galaxy S24 Adreno', galaxyJournal, galaxy, _adreno),
    ]) {
      test('$name device log verifies a delegate for every load', () {
        final recorded = events(journal);
        final placement = inspectPlacement(
          recorded.first,
          recorded.where((event) => event['type'] == 'case').toList(),
          log,
        );
        expect(placement, {
          'required': true,
          'verified': true,
          'reason': contains('per-request execution and embedding-model'),
          'log_sha256': matches(r'^[a-f0-9]{64}$'),
          'placement': _label,
          'expected_loads': 3,
          'adapter': adapter,
          'adapter_records': 3,
          'environment_records': 3,
          'signatures_per_load': 4,
          'delegate_records': 12,
          'failure_markers': isEmpty,
        });

        final report = ValidationReport.parse(journal, nativeLog: log);
        expect(report.qualified, isTrue);
        expect(report.qualificationGaps, isEmpty);
        expect(
          report.toHtml(),
          allOf(
            contains('per-request execution unobserved'),
            isNot(contains('verified native offload')),
          ),
        );

        final without = ValidationReport.parse(journal);
        expect(without.assertionsPassed, isTrue);
        expect(without.qualified, isFalse);
        expect(without.qualificationGaps, ['accelerator_evidence_missing']);
        expect(without.placement, {
          'required': true,
          'verified': false,
          'reason': 'native placement evidence unavailable',
        });
      });
    }

    test('accelerator registration is not evidence in either direction', () {
      for (final record in [
        'Dynamically loaded GPU accelerator(libLiteRtGpuAccelerator.so) '
            'registered.',
        'RegisterAccelerator: ',
        'XNNPACK CPU accelerator registered.',
      ]) {
        expect(cpuControl, contains(record));
        expect(pixel, contains(record));
      }
      final placement = inspect(cpuControl);
      expect(placement['verified'], isFalse);
      expect(placement['adapter_records'], 0);
      expect(placement['delegate_records'], 0);

      final unregistered = const LineSplitter()
          .convert(pixel)
          .where(
            (line) =>
                !line.contains('gpu_registry') &&
                !line.contains('RegisterAccelerator') &&
                !line.contains('XNNPACK'),
          )
          .map((line) => '$line\n')
          .join();
      expect(unregistered, isNot(pixel));
      expect(inspect(unregistered)['verified'], isTrue);
    });

    test('a GPU accelerator that did not load cannot verify', () {
      const failure =
          '10-13 02:44:27.834 22950 26936 W litert  : [gpu_registry.cc:1] '
          'GPU accelerator could not be loaded and registered: '
          'kLiteRtStatusErrorNotFound.\n';
      rejects(failure);
      rejects('$cpuControl$failure');
      final placement = inspect('$failure$pixel');
      expect(placement['verified'], isFalse);
      expect(placement['failure_markers'], [
        'GPU accelerator could not be loaded and registered',
      ]);
      // The NPU accelerator is absent on both devices and is not a GPU failure.
      expect(pixel, contains('NPU accelerator could not be loaded'));
    });

    for (final marker in [
      'Some ops are not accelerated. Add kLiteRtHwAcceleratorCpu',
      'Failed to modify graph with delegate',
      'vkCreateDevice failed: VK_ERROR_INITIALIZATION_FAILED',
      'Validation error: Binding size (155582464) is larger than the maximum',
      'Falling back to CPU',
      'falling back to cpu',
    ]) {
      test('failure marker "$marker" cannot verify', () {
        final placement = inspect('${pixel}E native : $marker\n');
        expect(placement['verified'], isFalse);
        expect(placement['failure_markers'], hasLength(1));
        expect(
          placement['reason'],
          'native log reports a GPU delegate failure or CPU fallback',
        );
      });
    }

    test('every expected load needs its own adapter and environment', () {
      final lines = const LineSplitter().convert(pixel);
      final third = lines.lastIndexWhere(
        (line) => line.contains('Selected adapter:'),
      );
      final twoLoads = lines.take(third).map((line) => '$line\n').join();
      final placement = inspect(twoLoads);
      expect(placement['verified'], isFalse);
      expect(placement['adapter_records'], 2);
      expect(placement['expected_loads'], 3);

      rejects(
        '$pixel$pixel',
        reason: 'six loads for three load cases',
        because: _adapterReason,
      );
      final unparsed = _record('native', 'Selected adapter: Mali-G715');
      rejects(
        '$pixel$unparsed',
        reason: 'a fourth, unparsed adapter selection',
        because: _adapterReason,
      );
      // Two complete loads and a third that only names an adapter.
      final partial =
          '${lines.take(third).map((line) => '$line\n').join()}$unparsed';
      expect(inspect(partial)['adapter_records'], 3);
      rejects(
        partial,
        reason: 'the third load selected no parsed adapter',
        because: _adapterReason,
      );
      for (var load = 0; load < 3; load++) {
        rejects(
          _withoutLine(pixel, _created, index: load),
          reason: 'load $load has no created environment',
          because: _recordsReason,
        );
        rejects(
          _withoutLine(pixel, 'Selected adapter:', index: load),
          reason: 'load $load selected no adapter',
          because: _adapterReason,
        );
      }
      rejects(
        '$pixel${_record('litert', '[delegate_webgpu.cc:1] $_created')}',
        because: _recordsReason,
      );
    });

    test('every main-model signature of every load needs a delegate', () {
      for (var record = 0; record < 12; record++) {
        final placement = inspect(_withoutLine(pixel, _kernel, index: record));
        expect(placement['verified'], isFalse, reason: 'record $record');
        expect(placement['delegate_records'], 11);
      }
      final extra = _record('native', 'Total 31 $_kernel');
      rejects('$pixel$extra', reason: 'thirteen', because: _recordsReason);

      // Twelve records, but one load has three and another five.
      final lines = const LineSplitter().convert(pixel);
      final first = lines.indexWhere((line) => line.contains(_kernel));
      final moved = lines.removeAt(first);
      lines.add(moved);
      final uneven = lines.map((line) => '$line\n').join();
      expect(RegExp(_kernel).allMatches(uneven), hasLength(12));
      rejects(uneven, reason: 'uneven', because: _recordsReason);

      // Records logged before any adapter selection belong to no load.
      rejects(
        '$extra$pixel',
        reason: 'delegate kernel before the first load',
        because: _recordsReason,
      );
      rejects(
        '${_record('litert', _created)}$pixel',
        reason: 'environment before the first load',
        because: _recordsReason,
      );
    });

    test('the signature count comes from each load\'s main model', () {
      const main = _main;
      expect(RegExp(main).allMatches(pixel), hasLength(3));
      // The embedding models load after the delegate kernels of each load.
      expect(RegExp(_embedder).allMatches(pixel), hasLength(12));
      for (var load = 0; load < 3; load++) {
        rejects(
          _replaceNth(
            pixel,
            main,
            'Loaded: num_subgraphs=976, num_signatures=5',
            load,
          ),
          reason: 'load $load declares five signatures',
        );
        rejects(
          _withoutLine(pixel, main, index: load),
          reason: 'load $load has no main-model record',
        );
      }
      final none = const LineSplitter()
          .convert(
            pixel.replaceAll(
              main,
              'Loaded: num_subgraphs=976, num_signatures=0',
            ),
          )
          .where((line) => !line.contains(_kernel))
          .map((line) => '$line\n')
          .join();
      rejects(none, reason: 'zero signatures');

      // A load takes no count from the records of the load before it.
      final lines = const LineSplitter().convert(pixel);
      final first = lines.indexWhere(
        (line) => line.contains('Selected adapter:'),
      );
      rejects(
        [
          for (var i = 0; i < lines.length; i++)
            if (i < first || !lines[i].contains('Loaded: ')) '${lines[i]}\n',
        ].join(),
        reason: 'only the first load has a signature record',
        because: _recordsReason,
      );
    });

    test('the main model declares the most signatures in the log', () {
      // One delegate kernel per load, with a single-signature record placed
      // between the four-signature main model and its adapter selection.
      final interposed = StringBuffer();
      var kernels = 0;
      for (final line in const LineSplitter().convert(pixel)) {
        if (line.contains('Selected adapter:')) kernels = 0;
        if (line.contains(_kernel) && ++kernels > 1) continue;
        interposed.writeln(line);
        if (line.contains(_main)) {
          interposed.write(_record('litert', _embedder));
        }
      }
      final placement = inspect('$interposed');
      expect(placement['delegate_records'], 3);
      expect(placement['signatures_per_load'], 1);
      expect(placement['verified'], isFalse);
      expect(placement['reason'], _recordsReason);

      for (var record = 0; record < 12; record++) {
        rejects(
          _replaceNth(
            pixel,
            _embedder,
            'Loaded: num_subgraphs=1, num_signatures=5',
            record,
          ),
          reason: 'record $record declares more than the main model',
          because: _recordsReason,
        );
      }
      rejects(
        '$pixel${_record('litert', 'Loaded: num_subgraphs=9, num_signatures=5')}',
        reason: 'a larger record after the last load',
        because: _recordsReason,
      );
      // A record as large as the main model's leaves the main model unknown.
      for (var record = 0; record < 12; record++) {
        rejects(
          _replaceNth(pixel, _embedder, _main, record),
          reason: 'record $record declares as many as the main model',
          because: _recordsReason,
        );
      }
      rejects(
        '$pixel${_record('litert', _main)}',
        reason: 'an equal record after the last load',
        because: _recordsReason,
      );
    });

    test('an unparsable signature count fails closed', () {
      const absurd = 'num_signatures=99999999999999999999';
      for (final (from, index) in [(_main, 0), (_main, 2), (_embedder, 5)]) {
        rejects(
          _replaceNth(pixel, from, 'Loaded: num_subgraphs=1, $absurd', index),
          reason: '$from $index',
          because: _tagReason,
        );
      }
    });

    test('evidence counts only under the native runtime tags', () {
      String retagged(String text, String from, String to) =>
          text.replaceAll(' I ${from.padRight(8)}: ', ' I ${to.padRight(8)}: ');
      final imitation = retagged(
        retagged(pixel, 'native', 'flutter'),
        'litert',
        'flutter',
      );
      expect(' I flutter : '.allMatches(imitation).length, greaterThan(200));
      for (final text in ['Selected adapter:', _created, _kernel, _main]) {
        expect(
          const LineSplitter()
              .convert(imitation)
              .where((l) => l.contains(text)),
          everyElement(contains(' I flutter : ')),
        );
      }
      // Dart `print` output of the same process cannot imitate the runtime.
      rejects(imitation, because: _tagReason);
      final printed = inspect('$cpuControl$imitation');
      expect(printed['verified'], isFalse);
      expect(printed['reason'], _tagReason);
      expect(printed['adapter_records'], 3);
      expect(printed['delegate_records'], 12);

      for (final (text, tag, occurrences) in [
        ('Selected adapter:', 'native', 3),
        (_created, 'litert', 3),
        (_kernel, 'native', 12),
        (_main, 'litert', 3),
        (_embedder, 'litert', 12),
      ]) {
        final lines = const LineSplitter().convert(pixel);
        final hits = [
          for (var i = 0; i < lines.length; i++)
            if (lines[i].contains(text)) i,
        ];
        expect(hits, hasLength(occurrences));
        for (final other in [
          'flutter',
          tag == 'native' ? 'litert' : 'native',
          'tflite',
          '${tag}2',
        ]) {
          for (final hit in hits) {
            final edited = [...lines];
            edited[hit] = retagged('${lines[hit]}\n', tag, other);
            expect(edited[hit], isNot('${lines[hit]}\n'));
            edited[hit] = edited[hit].trimRight();
            rejects(
              edited.map((line) => '$line\n').join(),
              reason: '$text under $other',
              because: _tagReason,
            );
          }
        }
        // The record without its device-log prefix names no tag.
        final bare = [...lines];
        bare[hits.first] = lines[hits.first].substring(
          lines[hits.first].indexOf(' I $tag') + 3,
        );
        rejects(bare.map((line) => '$line\n').join(), because: _tagReason);
        // Nor does a record that only contains a device-log record.
        final quoted = [...lines];
        quoted[hits.first] = '> ${lines[hits.first]}';
        rejects(quoted.map((line) => '$line\n').join(), because: _tagReason);
      }

      // A failure marker counts whoever logged it.
      final marked = inspect(
        '$pixel${_record('flutter', 'Falling back to CPU')}',
      );
      expect(marked['verified'], isFalse);
      expect(marked['failure_markers'], ['Falling back to CPU']);
    });

    test('only one hardware Vulkan adapter qualifies', () {
      String adapter(String identity) => pixel.replaceAll(_mali, identity);
      for (final identity in [
        'Mali-G715, arch=valhall, vendor=arm, backend=Vulkan, adapterType=CPU',
        'SwiftShader Device (Subzero), arch=swiftshader, vendor=google, '
            'backend=Vulkan, adapterType=CPU',
        'SwiftShader Device (Subzero), arch=swiftshader, vendor=google, '
            'backend=Vulkan, adapterType=Integrated GPU',
        'Mali-G715, arch=swiftshader, vendor=google, backend=Vulkan, '
            'adapterType=Integrated GPU',
        'llvmpipe (LLVM 17.0.6 256 bits), arch=, vendor=mesa, backend=Vulkan, '
            'adapterType=Integrated GPU',
        'Intel lavapipe, arch=, vendor=mesa, backend=Vulkan, '
            'adapterType=Discrete GPU',
        'Microsoft Basic Render Driver, arch=, vendor=microsoft, '
            'backend=Vulkan, adapterType=Integrated GPU',
        'Intel Basic Render, arch=, vendor=, backend=Vulkan, '
            'adapterType=Integrated GPU',
        'Adreno software renderer, arch=, vendor=, backend=Vulkan, '
            'adapterType=Integrated GPU',
        'Mali CPU fallback, arch=, vendor=arm, backend=Vulkan, '
            'adapterType=Integrated GPU',
        'Generic Accelerator, arch=, vendor=, backend=Vulkan, '
            'adapterType=Integrated GPU',
        // A vendor outside the adapter name does not make it hardware.
        'Generic Accelerator, arch=adreno-7xx, vendor=qualcomm, '
            'backend=Vulkan, adapterType=Integrated GPU',
        // A software device is refused wherever the identity names it.
        'Mali-G715, arch=valhall, vendor=virtual, backend=Vulkan, '
            'adapterType=Integrated GPU',
        'Mali-G715, arch=software, vendor=arm, backend=Vulkan, '
            'adapterType=Integrated GPU',
        'Mali-G715, arch=basic render, vendor=arm, backend=Vulkan, '
            'adapterType=Integrated GPU',
        '$_mali, extra',
        '$_mali extra',
        'Mali-G715, arch=valhall, vendor=arm, backend=Vulkan, '
            'adapterType=Unknown',
        'Mali-G715, arch=valhall, vendor=arm, backend=OpenGLES, '
            'adapterType=Integrated GPU',
        'Apple A18 Pro GPU, arch=, vendor=apple, backend=Metal, '
            'adapterType=Integrated GPU',
        'NVIDIA L4, arch=, vendor=nvidia, backend=D3D12, '
            'adapterType=Discrete GPU',
        'Mali-G715',
      ]) {
        expect(
          RegExp('Selected adapter').allMatches(adapter(identity)),
          hasLength(3),
        );
        rejects(adapter(identity), reason: identity);
      }
      const discrete =
          'NVIDIA L4, arch=, vendor=nvidia, backend=Vulkan, '
          'adapterType=Discrete GPU';
      expect(inspect(adapter(discrete))['adapter'], discrete);
      expect(inspect(adapter(discrete))['verified'], isTrue);

      for (var load = 0; load < 3; load++) {
        final mixed = inspect(_replaceNth(pixel, _mali, _adreno, load));
        expect(mixed['verified'], isFalse, reason: 'load $load');
        expect(mixed['adapter'], isNull);
        expect(mixed['adapter_records'], 3);
      }
    });

    test('load cases must each pass once reporting the GPU backend', () {
      List<Map<String, dynamic>> edited(
        void Function(List<Map<String, dynamic>>) edit,
      ) {
        final records = cases();
        edit(records);
        return records;
      }

      Map<String, dynamic> load(
        List<Map<String, dynamic>> records,
        String id,
      ) => records.singleWhere((record) => record['case_id'] == id);

      for (final id in ['C01.load', 'C09.reload', 'C12.recovery']) {
        for (final (reason, records) in [
          (
            'reports the CPU backend',
            edited(
              (records) =>
                  (load(records, id)['diagnostics'] as Map)['backend_name'] =
                      'LiteRT-LM cpu',
            ),
          ),
          (
            'has no diagnostics',
            edited((records) => load(records, id).remove('diagnostics')),
          ),
          ('failed', edited((records) => load(records, id)['status'] = 'FAIL')),
          (
            'is missing',
            edited((records) => records.remove(load(records, id))),
          ),
          (
            'passed twice',
            edited((records) => records.add({...load(records, id)})),
          ),
        ]) {
          final placement = inspect(pixel, records: records);
          expect(placement['verified'], isFalse, reason: '$id $reason');
          expect(
            placement['reason'],
            'expected load cases did not each pass once reporting the GPU '
            'backend',
          );
        }
      }
    });

    test('GGUF and LiteRT evidence do not cross runtimes', () {
      const offload =
          'load_tensors: offloaded 7/7 layers to GPU\n'
          'Vulkan0 compute buffer size = 64.0 MiB\n';
      const device = 'ggml_vulkan: 0 = Mali-G715\n';
      rejects('$device${offload * 3}');

      final gguf = <String, dynamic>{
        'schema_version': 1,
        'profile': jsonDecode(
          File('assets/profiles/tiny-gguf-vulkan.json').readAsStringSync(),
        ),
        'environment': manifest()['environment'],
      };
      final loads = [
        for (final id in ['C01.load', 'C09.reload', 'C12.recovery'])
          <String, dynamic>{
            'case_id': id,
            'status': 'PASS',
            'diagnostics': {'backend_name': 'Vulkan0 gpu'},
          },
      ];
      expect(
        inspectPlacement(gguf, loads, '$device${offload * 3}')['verified'],
        isTrue,
      );
      final crossed = inspectPlacement(gguf, loads, pixel);
      expect(crossed['verified'], isFalse);
      expect(crossed.containsKey('placement'), isFalse);
    });

    test('only the Android WebGPU-on-Vulkan shape is defined', () {
      Map<String, dynamic> on(Map<String, dynamic> environment) => {
        ...manifest(),
        'environment': {...manifest()['environment'] as Map, ...environment},
      };
      for (final environment in [
        {'platform': 'ios'},
        {'platform': 'macos'},
        {'platform': 'windows'},
        {'platform': 'linux'},
        {'platform': 'web'},
        {'web': true},
        {'web': null},
        {'web': 'false'},
        {'platform': null},
      ]) {
        final placement = inspect(pixel, of: on(environment));
        expect(placement['verified'], isFalse, reason: '$environment');
        expect(
          placement['reason'],
          'LiteRT GPU placement evidence is defined only for Android WebGPU '
          'on Vulkan',
        );
      }
      expect(
        inspect(pixel, of: {...manifest()}..remove('environment'))['verified'],
        isFalse,
      );
      final unstated = manifest();
      (unstated['environment'] as Map).remove('web');
      expect(inspect(pixel, of: unstated)['verified'], isFalse);
      expect(
        inspect(pixel, of: unstated)['reason'],
        contains('only for Android'),
      );
      expect((manifest()['environment'] as Map)['litert_tag'], '0.18.0');
      for (final tag in [
        '0.18.0',
        '0.18.0-1',
        '0.18.0-2',
        '0.18.0-3',
        '0.18.1',
        '0.18.1-1',
        '0.18.1-2',
        '0.18.1-3',
        '0.18.1-4',
      ]) {
        final placement = inspect(pixel, of: on({'litert_tag': tag}));
        expect(placement['verified'], isTrue, reason: tag);
        expect(placement['placement'], _label, reason: tag);
      }
      for (final tag in [
        '0.19.0',
        '0.18.2',
        '0.18.1-5',
        '0.18.0-4',
        '0.18.0-',
        '0.17.0-8',
        null,
      ]) {
        final placement = inspect(pixel, of: on({'litert_tag': tag}));
        expect(placement['verified'], isFalse, reason: '$tag');
        expect(
          placement['reason'],
          'LiteRT-LM tag is not source-qualified for GPU-only delegation',
        );
      }

      // An iPhone log names no adapter; nothing else in it can stand in.
      final adapterless = const LineSplitter()
          .convert(pixel)
          .where((line) => !line.contains('Selected adapter:'))
          .map((line) => '$line\n')
          .join();
      rejects(adapterless);
      expect(
        inspect(adapterless, of: on({'platform': 'ios'}))['verified'],
        isFalse,
      );
      rejects('');
      rejects('GPU success');
    });
  });
}
