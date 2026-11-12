import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/android_qualification.dart';
import 'package:llamadart_validation/android_qualification_io.dart';
import 'package:test/test.dart';

import '../../../test/unit/core/engine/engine_test.dart' as engine_fixture;

class _SpecialTokenBackend extends engine_fixture.MockLlamaBackend {
  final List<bool> flags = [];
  @override
  Future<List<int>> tokenize(
    int handle,
    String text, {
    bool addSpecial = true,
  }) async {
    flags.add(addSpecial);
    final long = text.split('coffee').length > 2;
    return List.generate(
      (long ? 44 : 7) + (addSpecial ? 2 : 0),
      (index) => index,
    );
  }
}

String _rawF32(List<double> values) {
  final bytes = ByteData(values.length * 4);
  for (var index = 0; index < values.length; index++) {
    bytes.setFloat32(index * 4, values[index], Endian.little);
  }
  return bytes.buffer
      .asUint8List()
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}

List<Map<String, dynamic>> _embeddingTranscript(
  List<double> raw,
  List<double> reported,
) {
  const plan = AndroidQualificationPlan(AndroidQualificationScenario.pixel8a);
  final records = <Map<String, dynamic>>[];
  void append(String event, Map<String, dynamic> fields) => records.add({
    'schema': 1,
    'binding': plan.hash,
    'case_id': 'pixel8a.native.cpu-probe',
    'pid': 123,
    'sequence': records.length,
    'event': event,
    ...fields,
  });
  append('started', {});
  for (var input = 0; input < 2; input++) {
    final fields = {
      'input': input,
      'phase': 'probe',
      'tokens': input == 0 ? 9 : 46,
    };
    append('embedding_raw', {...fields, 'vector_f32_le_hex': _rawF32(raw)});
    append('embedding', {...fields, 'operation_ms': 1.0, 'vector': reported});
  }
  append('finished', {});
  return records;
}

void main() {
  const pixel = AndroidQualificationPlan(AndroidQualificationScenario.pixel8a);
  const a35 = AndroidQualificationPlan(AndroidQualificationScenario.a35);
  test(
    'malformed native diagnostics keep exact bytes while geometry uses a lenient view',
    () {
      final directory = Directory.systemTemp.createTempSync('diagnostic-utf8-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final bytes = [
        ...utf8.encode('llama_model_loader: tokenizer.ggml.merges ["Ċ '),
        0xc4,
        ...ascii.encode('...\nn_ctx = 1024\nn_batch = 1024\nn_ubatch = 1024\n'),
      ];
      final file = File('${directory.path}/native.stderr.log')
        ..writeAsBytesSync(bytes);
      final digest = sha256.convert(bytes).toString();
      expect(file.readAsStringSync, throwsA(isA<FileSystemException>()));
      expect(
        matchesAndroidQualificationGeometry(
          androidQualificationDiagnosticText(file.readAsBytesSync()),
          pixel,
        ),
        isTrue,
      );
      expect(file.readAsBytesSync(), bytes);
      expect(sha256.convert(file.readAsBytesSync()).toString(), digest);
    },
  );

  test(
    'actual public tokenization preserves the 9/46 special-token precondition',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'embedding-token-policy-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final model = File('${directory.path}/mock.gguf')
        ..writeAsBytesSync([0, 0, 0, 0]);
      final backend = _SpecialTokenBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.setModel(LlamaModel(ModelSource.path(model.path)));
      expect(await engine.getTokenCount(pixel.prompts.first), 7);
      expect(
        (await androidQualificationEmbeddingTokens(
          engine,
          pixel.prompts.first,
        )).length,
        9,
      );
      expect(
        (await androidQualificationEmbeddingTokens(
          engine,
          pixel.prompts.last,
        )).length,
        46,
      );
      expect(backend.flags, [false, true, true]);
    },
  );

  test(
    'normal production hook omits OpenCL while retaining complete owner provenance',
    () {
      final archive =
          jsonDecode(
                File(
                  'test/fixtures/android_qualification/android_arm64_runtime_names.json',
                ).readAsStringSync(),
              )
              as Map;
      final names = (archive['libraries'] as List).cast<String>();
      final selection = androidQualificationLibrarySelection(names);
      expect(names, hasLength(15));
      expect(selection['backends'], ['cpu', 'vulkan']);
      expect(selection['omitted'], ['libggml-opencl.so']);
      expect(selection['packaged'], hasLength(14));
      expect(selection['packaged'], isNot(contains('libggml-opencl.so')));
      expect(names, contains('libggml-opencl.so'));
    },
  );
  test(
    'nonfinite returned vector bytes survive before a JSON oracle can run',
    () {
      final encoded = androidQualificationVectorBytes([
        1.0,
        double.infinity,
        double.nan,
      ]);
      final bytes = ByteData.sublistView(base64Decode(encoded));
      expect(bytes.getFloat64(0, Endian.little), 1.0);
      expect(bytes.getFloat64(8, Endian.little), double.infinity);
      expect(bytes.getFloat64(16, Endian.little).isNaN, isTrue);
    },
  );
  test(
    'actual C++ producer serialization agrees with retained f32 bytes',
    () async {
      final temporary = Directory.systemTemp.createTempSync(
        'native-vector-producer-',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));
      final executable = '${temporary.path}/producer';
      final compiled = await Process.run('c++', [
        '-std=c++17',
        '-O2',
        '-Wall',
        '-Wextra',
        '-Werror',
        File('test/fixtures/android_qualification/producer.cpp').absolute.path,
        '-o',
        executable,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      final capture = await captureAndroidNativeChild(
        executable: executable,
        arguments: [pixel.hash, 'pixel8a.native.cpu-probe'],
        output: Directory('${temporary.path}/capture'),
        binding: pixel.hash,
        caseId: 'pixel8a.native.cpu-probe',
        timeout: const Duration(seconds: 5),
      );
      expect(capture['exit_code'], 0);
      expect(capture['protocol_complete'], isTrue);
      final records = (capture['records'] as List).cast<Map<String, dynamic>>();
      expect(
        assessAndroidEmbeddingRecords(records, records, probeOnly: true),
        isTrue,
      );
    },
    testOn: '!windows',
  );

  test('original models and geometry cannot become the stock BF16 pack', () {
    expect(
      pixel.model['sha256'],
      '2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135',
    );
    expect(pixel.model['bytes'], 309855456);
    expect(
      pixel.modelUrl,
      contains('/6ea3e3a309d12a4779cfda98b8c19800d2d5da71/'),
    );
    expect(pixel.params('vulkan').microBatchSize, 1024);
    expect(pixel.params('vulkan').device, ComputeDevice.gpu);
    expect(pixel.params('cpu').gpuLayers, 0);
    expect(a35.params('vulkan').microBatchSize, 512);
    expect(a35.params('vulkan').flashAttention, FlashAttention.disabled);
    expect(a35.nativeBackends, ['cpu', 'vulkan-defaults', 'vulkan']);
    expect(pixel.caseIds, contains('pixel8a.native.vulkan-probe'));
    expect(
      pixel.configuration['public_process_scope'],
      'serialized_complete_engine_lifetimes',
    );
    expect(pixel.hash, isNot(a35.hash));
    expect(() => pixel.params('auto'), throwsArgumentError);
  });

  test(
    'actual context geometry must be complete and agree across native records',
    () {
      expect(
        matchesAndroidQualificationGeometry(
          'llama_context: n_ctx = 1024\n'
          'llama_context: n_batch = 1024\nllama_context: n_ubatch = 1024',
          pixel,
        ),
        isTrue,
      );
      expect(
        matchesAndroidQualificationGeometry(
          'n_ctx=1024 n_batch=512 n_ubatch=512',
          pixel,
        ),
        isFalse,
      );
      expect(
        matchesAndroidQualificationGeometry('n_ctx=1024 n_batch=1024', pixel),
        isFalse,
      );
      expect(
        matchesAndroidQualificationGeometry(
          'n_ctx=1024 n_batch=1024 n_ubatch=1024\nn_ubatch=8',
          pixel,
        ),
        isFalse,
      );
    },
  );

  test(
    'embedding oracle rejects zero, malformed, unnormalized and wrong inputs',
    () {
      final unit = [1.0, ...List.filled(767, 0.0)];
      final other = [0.0, 1.0, ...List.filled(766, 0.0)];
      expect(assessAndroidEmbedding(unit, unit)['passed'], isTrue);
      for (final vector in [
        List.filled(768, 0.0),
        List.filled(767, 0.0),
        [double.nan, ...unit.skip(1)],
        [double.infinity, ...unit.skip(1)],
        [2.0, ...unit.skip(1)],
        other,
      ]) {
        expect(assessAndroidEmbedding(vector, unit)['passed'], isFalse);
      }
    },
  );

  test('missing, duplicated or incorrect input/phase cells block timing', () {
    final unit = [1.0, ...List.filled(767, 0.0)];
    final reference = _embeddingTranscript(unit, unit);
    List<Map<String, dynamic>> patch(int index, Map<String, dynamic> fields) =>
        [
          for (var i = 0; i < reference.length; i++)
            if (i == index) {...reference[i], ...fields} else reference[i],
        ];
    expect(
      assessAndroidEmbeddingRecords(reference, reference, probeOnly: true),
      isTrue,
    );
    for (final broken in [
      [...reference.take(3), reference.last],
      [...reference.take(5), reference[3], reference[4], reference.last],
      patch(4, {'tokens': 9}),
      patch(4, {'phase': 'measured-1'}),
      patch(4, {'operation_ms': double.infinity}),
      patch(4, {'vector': List.filled(768, 0.0)}),
      [
        reference.first,
        reference[3],
        reference[4],
        reference[1],
        reference[2],
        reference.last,
      ],
    ]) {
      expect(
        assessAndroidEmbeddingRecords(broken, reference, probeOnly: true),
        isFalse,
      );
    }
    expect(
      assessAndroidEmbeddingRecords(reference, reference, probeOnly: false),
      isFalse,
    );
  });

  test(
    'raw f32 values, normalization and token identity bind the numerical oracle',
    () {
      final raw = [3.0, 4.0, ...List.filled(766, 0.0)];
      final reported = [0.6, 0.8, ...List.filled(766, 0.0)];
      final good = _embeddingTranscript(raw, reported);
      List<Map<String, dynamic>> parse(List<Map<String, dynamic>> records) =>
          parseAndroidNativeRecords(
            utf8.encode('${records.map(jsonEncode).join('\n')}\n'),
            binding: pixel.hash,
            caseId: 'pixel8a.native.cpu-probe',
            processId: 123,
          );
      final parsed = parse(good);
      expect(
        assessAndroidEmbeddingRecords(parsed, parsed, probeOnly: true),
        isTrue,
      );
      final wrongTokens = [
        for (var index = 0; index < good.length; index++)
          if (index == 1) {...good[index], 'tokens': 7} else good[index],
      ];
      for (final bad in [
        _embeddingTranscript(List.filled(768, double.nan), reported),
        _embeddingTranscript([double.infinity, ...raw.skip(1)], reported),
        _embeddingTranscript(List.filled(768, 0.0), reported),
        _embeddingTranscript(raw.take(767).toList(), reported),
        _embeddingTranscript([4.0, 3.0, ...List.filled(766, 0.0)], reported),
        _embeddingTranscript(
          [1.0, 1e-20, ...List.filled(766, 0.0)],
          [1.0, ...List.filled(767, 0.0)],
        ),
        wrongTokens,
      ]) {
        expect(() => parse(bad), throwsFormatException);
        expect(
          assessAndroidEmbeddingRecords(bad, good, probeOnly: true),
          isFalse,
        );
      }
    },
  );

  test('generation control cannot pass with empty or malformed transport', () {
    final good = <String, dynamic>{
      'event': 'generation',
      'prompt_tokens': 7,
      'token_ids': [8, 9],
      'eog': true,
      'output_hex': '2050617269732e',
    };
    expect(assessAndroidGenerationRecords([good]), isTrue);
    for (final bad in [
      <String, dynamic>{},
      {...good, 'token_ids': []},
      {...good, 'output_hex': 'ff'},
      {...good, 'output_hex': '20'},
      {...good, 'prompt_tokens': 0},
    ]) {
      expect(assessAndroidGenerationRecords([bad]), isFalse);
    }
  });

  test(
    'build binding rejects dirty, wrong-source and conflicting runtime inputs',
    () {
      final hash = 'a' * 64;
      final names =
          (jsonDecode(
                    File(
                      'test/fixtures/android_qualification/android_arm64_runtime_names.json',
                    ).readAsStringSync(),
                  )['libraries']
                  as List)
              .cast<String>();
      final archive = {
        for (final name in names) name: {'bytes': 12, 'sha256': hash},
      };
      final selection = androidQualificationLibrarySelection(names);
      final good = <String, dynamic>{
        'schema': 1,
        'plan_sha256': a35.hash,
        'source_dirty': false,
        'source_commit': 'b' * 40,
        'source_tree': 'c' * 40,
        'source_inventory_sha256': hash,
        'hook_sha256': hash,
        'probe_sha256': hash,
        'selector_sha256': hash,
        'native_tag': 'v0.9.0',
        'native_archive_sha256':
            'd3c933a63e8ccaafeee32edd30685fdccd17c05e54b75895282f01fe74914a1b',
        'libraries': {
          for (final name in selection['packaged'] as List<String>)
            name: archive[name],
          'libllamadart_android_qualification.so': {
            'bytes': 12,
            'sha256': hash,
          },
        },
        'archive_libraries': archive,
        'packaging_selection': selection,
      };
      expect(
        readAndroidQualificationBinding(jsonEncode(good), a35)['source_dirty'],
        isFalse,
      );
      for (final bad in [
        {...good, 'source_dirty': true},
        {...good, 'source_commit': 'b'},
        {...good, 'native_tag': 'v0.7.0-1'},
        {...good, 'libraries': {}},
        {...good, 'probe_sha256': 'd' * 64},
        {...good, 'plan_sha256': pixel.hash},
        {...good, 'archive_libraries': <String, dynamic>{}},
        {...good, 'packaging_selection': <String, dynamic>{}},
        {
          ...good,
          'libraries': {
            ...good['libraries'] as Map,
            'libggml-opencl.so': archive['libggml-opencl.so'],
          },
        },
      ]) {
        expect(
          () => readAndroidQualificationBinding(jsonEncode(bad), a35),
          throwsFormatException,
        );
      }
      expect(
        androidQualificationExecutionHash(good),
        isNot(
          androidQualificationExecutionHash({...good, 'source_tree': 'e' * 40}),
        ),
      );
    },
  );

  group('owned child capture', () {
    late Directory temporary;
    setUp(() {
      temporary = Directory.systemTemp.createTempSync('android-qualification-');
    });
    tearDown(() {
      temporary.deleteSync(recursive: true);
    });
    test(
      'mapped paths cannot substitute same-name or modified runtime files',
      () async {
        final inventory = <String, dynamic>{};
        for (final name in [
          'libllama.so',
          'libggml-base.so',
          'libggml-vulkan.so',
        ]) {
          final file = File('${temporary.path}/$name')..writeAsStringSync(name);
          inventory[name] = {
            'bytes': file.lengthSync(),
            'sha256': sha256.convert(file.readAsBytesSync()).toString(),
          };
        }
        String maps(String directory) => inventory.keys
            .map((name) => '1000-2000 r-xp 00000000 00:00 1 $directory/$name')
            .join('\n');
        await verifyAndroidQualificationMaps(maps(temporary.path), temporary, {
          'libraries': inventory,
        }, vulkan: true);
        await expectLater(
          verifyAndroidQualificationMaps(maps('/wrong'), temporary, {
            'libraries': inventory,
          }, vulkan: true),
          throwsFormatException,
        );
        await expectLater(
          verifyAndroidQualificationMaps(
            '${maps(temporary.path)}\n'
            '1000-2000 r-xp 00000000 00:00 1 ${temporary.path}/libllama.so (deleted)',
            temporary,
            {'libraries': inventory},
            vulkan: true,
          ),
          throwsFormatException,
        );
        File('${temporary.path}/libllama.so').writeAsStringSync('bad');
        await expectLater(
          verifyAndroidQualificationMaps(maps(temporary.path), temporary, {
            'libraries': inventory,
          }, vulkan: true),
          throwsFormatException,
        );
      },
    );
    Future<Map<String, dynamic>> run(
      String mode, {
      int limit = 2 * 1024 * 1024,
      String caseId = 'a35.native.cpu',
    }) => captureAndroidNativeChild(
      executable: (Process.runSync('which', ['python3']).stdout as String)
          .trim(),
      arguments: [
        'test/fixtures/android_qualification/child.py',
        mode,
        a35.hash,
        caseId,
      ],
      output: Directory('${temporary.path}/$mode'),
      binding: a35.hash,
      caseId: caseId,
      timeout: Duration(milliseconds: mode == 'hang' ? 300 : 3000),
      stdoutLimit: limit,
    );
    test(
      'S24 shares owned capture only under the explicit native case prefix',
      () async {
        final value = await run('s24-success', caseId: 's24.native.guard');
        expect(value['exit_code'], 0);
        expect(value['case_id'], 's24.native.guard');
        expect(value['capture_complete'], isTrue);
        expect(value['qualified'], isFalse);
        expect(
          File('${temporary.path}/s24-success/stderr.log').readAsBytesSync(),
          [...utf8.encode('raw-native-stderr'), 0, 255, 10],
        );
        for (final caseId in [
          's24.public.cpu',
          's24x.native.cpu',
          'other.native.cpu',
          's24.native.cpu/escape',
          's24.native.guard1',
        ]) {
          await expectLater(
            run('refused-$caseId', caseId: caseId),
            throwsFormatException,
          );
          expect(
            Directory('${temporary.path}/refused-$caseId').existsSync(),
            isFalse,
          );
        }
      },
    );
    test('keeps exact stderr bytes before protocol validation', () async {
      final value = await run('success');
      expect(value['protocol_complete'], isTrue);
      expect(value['qualified'], isFalse);
      expect(File('${temporary.path}/success/stderr.log').readAsBytesSync(), [
        ...utf8.encode('raw-native-stderr'),
        0,
        255,
        10,
      ]);
      expect((value['records'] as List).last['event'], 'finished');
      expect(value['capture_complete'], isTrue);
    });
    test('kills a hung child and retains partial raw output', () async {
      final value = await run('hang');
      expect(value['timed_out'], isTrue);
      expect(value['exit_code'], isNot(0));
      expect(value['qualified'], isFalse);
      expect(value, isNot(contains('records')));
      expect(
        Process.killPid(value['pid'] as int, ProcessSignal.sigkill),
        isFalse,
      );
      expect(
        File('${temporary.path}/hang/stdout.jsonl').lengthSync(),
        greaterThan(0),
      );
    });
    test(
      'bounds streamed output and retains a failed capture receipt',
      () async {
        final value = await run('overflow', limit: 1024);
        expect(value['capture_limit_exceeded'], isTrue);
        expect(value['capture_complete'], isFalse);
        expect(
          File('${temporary.path}/overflow/stdout.jsonl').lengthSync(),
          1024,
        );
      },
    );
    for (final mode in ['truncated', 'wrong-binding', 'failure']) {
      test('$mode never gains protocol success', () async {
        final value = await run(mode);
        expect(value['protocol_complete'], isNot(true));
        expect(value['qualified'], isFalse);
        expect(
          File('${temporary.path}/$mode/capture.json').existsSync(),
          isTrue,
        );
      });
    }
  });

  test('protocol binds PID, case, sequence and complete lifetime', () {
    List<int> encoded(List<Map<String, Object>> records) =>
        utf8.encode('${records.map(jsonEncode).join('\n')}\n');
    Map<String, Object> record(String event, int sequence) => {
      'schema': 1,
      'binding': a35.hash,
      'case_id': 'a35.native.cpu',
      'pid': 123,
      'sequence': sequence,
      'event': event,
    };
    final good = [record('started', 0), record('finished', 1)];
    List<Map<String, dynamic>> parse(List<int> bytes) =>
        parseAndroidNativeRecords(
          bytes,
          binding: a35.hash,
          caseId: 'a35.native.cpu',
          processId: 123,
        );
    expect(parse(encoded(good)), hasLength(2));
    for (final bad in [
      [good.first],
      [good.last, good.first],
      [
        good.first,
        {...good.last, 'pid': 124},
      ],
      [
        good.first,
        {...good.last, 'sequence': 9},
      ],
      [
        good.first,
        {...good.last, 'case_id': 'pixel8a.native.cpu'},
      ],
    ]) {
      expect(() => parse(encoded(bad)), throwsFormatException);
    }
    expect(() => parse([255]), throwsFormatException);
  });
}
