import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
// The private release harness must verify the committed core runtime pin.
// ignore: implementation_imports
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:llamadart_validation/android_consumer_profile.dart';
import 'package:llamadart_validation/android_qualification_io.dart';
import 'package:test/test.dart';

import 'support/bounded_fixture_process.dart';

void main() {
  final names =
      (jsonDecode(
                File(
                  'test/fixtures/android_qualification/android_arm64_runtime_names.json',
                ).readAsStringSync(),
              )['libraries']
              as List)
          .cast<String>();

  Map<String, dynamic> binding(AndroidConsumerProfilePlan plan) {
    final archive = {
      for (final name in names) name: {'bytes': 12, 'sha256': 'a' * 64},
    };
    final selection = androidQualificationLibrarySelection(
      names,
      cpuProfile: plan.profile,
    );
    return {
      'schema': 1,
      'plan_sha256': plan.hash,
      'source_dirty': false,
      'source_commit': 'b' * 40,
      'source_tree': 'c' * 40,
      'source_inventory_sha256': 'a' * 64,
      'consumer_pubspec_sha256': 'a' * 64,
      'hook_sha256': 'a' * 64,
      'selector_sha256': 'a' * 64,
      'native_tag': 'v0.9.0',
      'native_archive_sha256':
          'd3c933a63e8ccaafeee32edd30685fdccd17c05e54b75895282f01fe74914a1b',
      'archive_libraries': archive,
      'packaging_selection': selection,
      'libraries': {
        for (final name in selection['packaged'] as List<String>)
          name: archive[name],
      },
    };
  }

  test('profile inventories bind all seven vs baseline-only CPU modules', () {
    final full = androidQualificationLibrarySelection(
      names,
      cpuProfile: 'full',
    );
    final compact = androidQualificationLibrarySelection(
      names,
      cpuProfile: 'compact',
    );
    List<String> cpus(Map selection) => (selection['packaged'] as List<String>)
        .where((name) => name.startsWith('libggml-cpu-'))
        .toList();
    expect(cpus(full), hasLength(7));
    expect(cpus(compact), ['libggml-cpu-android_armv8.0_1.so']);
    expect(full['backends'], compact['backends']);
    expect(full['omitted'], ['libggml-opencl.so']);
    expect(() => AndroidConsumerProfilePlan('unknown'), throwsFormatException);
  });

  test('consumer profiles bind the committed core runtime pin', () {
    for (final profile in ['full', 'compact']) {
      final plan = AndroidConsumerProfilePlan(profile);
      expect(plan.hookDefines['llamadart_native_tag'], llamaCppTag);
      expect(
        (plan.wire['hook_defines'] as Map)['llamadart_native_tag'],
        llamaCppTag,
      );
    }
  });

  test(
    'consumer binding refuses crossed profile, mutation and probe injection',
    () {
      for (final profile in ['full', 'compact']) {
        final plan = AndroidConsumerProfilePlan(profile);
        final good = binding(plan);
        Map read(Map value) => readAndroidQualificationBinding(
          jsonEncode(value),
          plan.fixture,
          consumerCpuProfile: profile,
          consumerPlanHash: plan.hash,
        );
        expect(read(good)['native_tag'], 'v0.9.0');
        for (final bad in [
          {...good, 'source_dirty': true},
          {...good, 'consumer_pubspec_sha256': ''},
          {...good, 'native_tag': 'v0.8.0-1'},
          {
            ...good,
            'plan_sha256': AndroidConsumerProfilePlan(
              profile == 'full' ? 'compact' : 'full',
            ).hash,
          },
          {
            ...good,
            'packaging_selection': androidQualificationLibrarySelection(names),
          },
          {
            ...good,
            'libraries': {
              ...good['libraries'] as Map,
              'libllamadart_android_qualification.so': {
                'bytes': 12,
                'sha256': 'a' * 64,
              },
            },
          },
          {
            ...good,
            'libraries': {
              ...good['libraries'] as Map,
              'libllama.so': {'bytes': 13, 'sha256': 'a' * 64},
            },
          },
        ]) {
          expect(() => read(bad), throwsFormatException);
        }
      }
    },
  );

  test('semantic fixture rejects empty, unrelated and corrupted output', () {
    expect(androidConsumerOutputPasses(' Paris.'), isTrue);
    for (final bad in ['', 'London.', 'Paris\uFFFD', 'Comparison']) {
      expect(androidConsumerOutputPasses(bad), isFalse);
    }
    final plan = AndroidConsumerProfilePlan('compact');
    expect(
      plan.fixture.model['sha256'],
      '7bbd90384d3deffe4c646ec9643b212802d32d4ce417c90a1ec9282100650062',
    );
    expect(plan.fixture.prompts.single, 'The capital of France is');
    expect(plan.wire['flutter_build_mode'], 'release');
  });

  test(
    'actual pubspec refuses path, runtime and CPU variant substitutions',
    () async {
      final temporary = Directory.systemTemp.createTempSync('consumer-config-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final inventory = File('${temporary.path}/inventory.json')
        ..writeAsStringSync(jsonEncode({for (final name in names) name: {}}));
      final sdk = File(Platform.resolvedExecutable).parent.parent.path;
      final kernel = '${temporary.path}/consumer-plan.dill';
      final compileWatch = Stopwatch()..start();
      // Reuse the real CLI without recompiling its public imports per mutation.
      // Invoke the compiler directly so its deadline owns the compiler itself.
      final compiled = await runBoundedFixtureProcess(
        '$sdk/bin/dartaotruntime${Platform.isWindows ? '.exe' : ''}',
        [
          '$sdk/bin/snapshots/gen_kernel_aot.dart.snapshot',
          '--platform',
          '$sdk/lib/_internal/vm_platform_strong.dill',
          '--packages',
          File('.dart_tool/package_config.json').absolute.path,
          '--output',
          kernel,
          File('bin/android_consumer_profile_plan.dart').absolute.path,
        ],
        timeout: const Duration(seconds: 60),
      );
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      print(
        'Consumer CLI kernel compilation ${compileWatch.elapsedMilliseconds} ms',
      );
      final staleNativeTag = llamaCppTag == 'v0.8.0-2'
          ? 'v0.8.0-1'
          : 'v0.8.0-2';
      for (final profile in ['full', 'compact']) {
        final plan = AndroidConsumerProfilePlan(profile);
        for (final variant in [
          'good',
          'native-tag',
          'path',
          'runtimes',
          'profile',
          'variants',
          'dev-only-plugin',
          'missing-plugin',
          'versioned-plugin',
          'duplicate-plugin',
        ]) {
          final defines =
              jsonDecode(jsonEncode(plan.hookDefines)) as Map<String, dynamic>;
          defines['llamadart_native_tag'] = llamaCppTag;
          switch (variant) {
            case 'native-tag':
              defines['llamadart_native_tag'] = staleNativeTag;
            case 'path':
              defines['llamadart_native_path'] = '/unadmitted';
            case 'runtimes':
              defines['llamadart_native_runtimes'] = 'all';
            case 'profile':
              defines['llamadart_native_backends']['platforms']['android-arm64']['cpu_profile'] =
                  'unknown';
            case 'variants':
              defines['llamadart_native_backends']['platforms']['android-arm64']['cpu_variants'] =
                  ['android_armv8.0_1'];
          }
          final dependencies = <String, Object?>{
            'integration_test': {'sdk': 'flutter'},
          };
          final devDependencies = <String, Object?>{};
          if (variant == 'dev-only-plugin' || variant == 'missing-plugin') {
            dependencies.remove('integration_test');
          }
          if (variant == 'dev-only-plugin' || variant == 'duplicate-plugin') {
            devDependencies['integration_test'] = {'sdk': 'flutter'};
          }
          if (variant == 'versioned-plugin') {
            dependencies['integration_test'] = '^1.0.0';
          }
          final spec = File('${temporary.path}/$profile-$variant.yaml')
            ..writeAsStringSync(
              jsonEncode({
                'dependencies': dependencies,
                'dev_dependencies': devDependencies,
                'hooks': {
                  'user_defines': {'llamadart': defines},
                },
              }),
            );
          final output = File('${temporary.path}/$profile-$variant.json');
          final watch = Stopwatch()..start();
          final result = await runBoundedFixtureProcess(
            Platform.resolvedExecutable,
            [kernel, profile, spec.path, inventory.path, output.path],
            timeout: const Duration(seconds: 10),
          );
          print(
            'Consumer CLI $profile/$variant ${watch.elapsedMilliseconds} ms',
          );
          expect(
            result.exitCode,
            variant == 'good' ? 0 : isNot(0),
            reason: '${result.stderr}',
          );
          expect(output.existsSync(), variant == 'good');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('real exporter journal replays through strict raw decoder', () async {
    final temporary = Directory.systemTemp.createTempSync('consumer-export-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final plan = AndroidConsumerProfilePlan('compact');
    final id = plan.caseIds.first;
    final names = [
      'app_apk.sha256',
      'vkjson.json',
      'cpuinfo.txt',
      '$id.maps',
      '$id.stderr.log',
    ];
    for (final name in names) {
      File('${temporary.path}/$name').writeAsBytesSync([0, 255, 1, 10]);
    }
    final rows = <Map<String, dynamic>>[
      {'event': 'manifest', 'schema': 1, 'plan': plan.wire},
      {'event': 'case_started', 'case_id': id},
    ];
    for (final event in [
      'public_geometry_stderr_snapshot',
      'public_stderr_capture',
    ]) {
      rows.add({
        'event': event,
        'case_id': id,
        'bytes': 4,
        'sha256': sha256.convert([0, 255, 1, 10]).toString(),
      });
    }
    expect(exportAndroidQualificationRaw(temporary, names, rows.add), isTrue);
    rows.add({
      'event': 'summary',
      'raw_export_complete': true,
      'case_inventory': {
        for (final item in plan.caseIds)
          item: {'status': item == id ? 'PASS' : 'NOT_RUN'},
      },
    });
    final journal = File('${temporary.path}/diagnostic.jsonl')
      ..writeAsStringSync("${rows.map(jsonEncode).join('\n')}\n");
    final result = await Process.run('python3', [
      'native/android_qualification/decode_raw.py',
      journal.path,
      '--out',
      '${temporary.path}/recovered',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    for (final name in names) {
      expect(File('${temporary.path}/recovered/$name').readAsBytesSync(), [
        0,
        255,
        1,
        10,
      ]);
    }
  });
}
