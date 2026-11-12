@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  const desktopAbis = [
    Abi.macosArm64,
    Abi.linuxArm64,
    Abi.linuxX64,
    Abi.windowsX64,
  ];
  // Linux and Windows hosts from v0.19.1-1 link LiteRT in and never load
  // the prebuilt libLiteRt their owner archive still carries.
  const linkedInLiteRt = {
    Abi.linuxArm64: 'libLiteRt.so',
    Abi.linuxX64: 'libLiteRt.so',
    Abi.windowsX64: 'libLiteRt.dll',
  };
  // v0.19.1-3 stopped shipping the Metal accelerator that the linked-in GPU
  // accelerator makes unreachable.
  const unusedMetalAccelerator = 'libLiteRtMetalAccelerator.dylib';
  // v0.19.1-4 stopped shipping the macOS LiteRT and WebGPU accelerator
  // dylibs; the LiteRT and accelerator embedded in LiteRtLm never open them.
  const unusedMacOsLiteRtCompanions = {
    'libLiteRt.dylib',
    'libLiteRtWebGpuAccelerator.dylib',
  };
  bool isRetiredByOwner(Abi abi, String file) =>
      file == unusedMetalAccelerator ||
      (abi == Abi.macosArm64 && unusedMacOsLiteRtCompanions.contains(file));
  for (final abi in desktopAbis) {
    test(
      '$abi v1 keeps all owner companions except retired TopK libraries, '
      'the unused Metal and macOS LiteRT companions and a linked-in LiteRT',
      () {
        final legacy = liteRtLmRequiredLibrariesForAbi(abi);
        final modern = liteRtLmRequiredLibrariesForAbi(abi, cApiV1: true);
        expect(modern.length, switch (abi) {
          Abi.macosArm64 => 4,
          Abi.windowsX64 => 11,
          _ => 4,
        });
        final retired = legacy.toSet().difference(modern.toSet());
        expect(
          retired.where(
            (file) =>
                file != linkedInLiteRt[abi] && !isRetiredByOwner(abi, file),
          ),
          everyElement(contains('TopK')),
        );
        if (linkedInLiteRt[abi] case final liteRt?) {
          expect(retired, contains(liteRt));
        }
        expect(modern, containsAll(liteRtLmNonPreloadedLibrariesForAbi(abi)));
        expect(
          liteRtLmCompanionLibrariesForAbi(abi, cApiV1: true),
          unorderedEquals(
            modern.where(
              (file) =>
                  file != liteRtLmPrimaryLibraryForAbi(abi) &&
                  !liteRtLmNonPreloadedLibrariesForAbi(abi).contains(file),
            ),
          ),
        );
      },
    );
  }

  test('v1 discovery matches the frozen owner 0.19 desktop inventory', () {
    final projection =
        jsonDecode(
              File(
                'tool/native/fixtures/litert_lm_v019_apple_inventory_projection.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(projection['compatibilityTag'], 'v0.19.0');
    final platforms = projection['platforms'] as List<dynamic>;
    for (final entry in {
      Abi.macosArm64: ('macos', 'arm64'),
      Abi.linuxArm64: ('linux', 'arm64'),
      Abi.linuxX64: ('linux', 'x64'),
      Abi.windowsX64: ('windows', 'x64'),
    }.entries) {
      final platform = platforms.cast<Map<String, dynamic>>().singleWhere(
        (item) =>
            item['platform'] == entry.value.$1 &&
            item['arch'] == entry.value.$2,
      );
      final owner =
          (platform['artifactPaths'] as List<dynamic>)
              .cast<String>()
              .where((file) => !file.endsWith('.lib'))
              .map(path.basename)
              .toList()
            ..sort();
      final linked = linkedInLiteRt[entry.key];
      if (linked != null) expect(owner, contains(linked));
      final expected = owner
          .where((file) => file != linked && !isRetiredByOwner(entry.key, file))
          .toList();
      expect(
        liteRtLmRequiredLibrariesForAbi(entry.key, cApiV1: true),
        expected,
        reason: '${entry.key} owner inventory',
      );
    }
  });

  for (final abi in linkedInLiteRt.keys) {
    test('$abi explicit directories open a present libLiteRt for older '
        'hosts', () {
      final liteRt = linkedInLiteRt[abi]!;
      final directory = Directory.systemTemp.createTempSync('litert_optional_');
      addTearDown(() => directory.deleteSync(recursive: true));
      List<String> names({required bool cApiV1}) =>
          liteRtLmExplicitDirectoryCompanionPathsForAbi(
            abi,
            directory,
            cApiV1: cApiV1,
          ).map((file) => file.split('/').last).toList();

      expect(liteRtLmOptionalCompanionLibrariesForAbi(abi), [liteRt]);
      expect(
        names(cApiV1: true),
        liteRtLmCompanionLibrariesForAbi(abi, cApiV1: true),
        reason: 'a v0.19.1-1 directory without it is unchanged',
      );
      File(path.join(directory.path, liteRt)).writeAsStringSync('');
      expect(names(cApiV1: true), [
        ...liteRtLmCompanionLibrariesForAbi(abi, cApiV1: true),
        liteRt,
      ]);
      expect(
        names(cApiV1: false).where((file) => file == liteRt),
        hasLength(1),
        reason: 'legacy inventories already require it',
      );
    });
  }
  test('macOS explicit directories open no optional companion', () {
    expect(liteRtLmOptionalCompanionLibrariesForAbi(Abi.macosArm64), isEmpty);
  });

  test('v1 Windows still loads CRT and Dawn before their importers', () {
    final order = liteRtLmCompanionLibrariesForAbi(
      Abi.windowsX64,
      cApiV1: true,
    );
    for (final entry in {
      'msvcp140.dll': ['vcruntime140.dll', 'vcruntime140_1.dll'],
      'vcruntime140_1.dll': ['vcruntime140.dll'],
      'vcruntime140_threads.dll': ['vcruntime140.dll'],
      'libLiteRtWebGpuAccelerator.dll': ['webgpu_dawn.dll'],
    }.entries) {
      for (final dependency in entry.value) {
        expect(
          order.indexOf(dependency),
          allOf(isNonNegative, lessThan(order.indexOf(entry.key))),
        );
      }
    }
  });

  _compiledFixtures();
}

void _compiledFixtures() {
  if ((!Platform.isMacOS && !Platform.isLinux) ||
      liteRtLmPrimaryLibraryForAbi(Abi.current()) == null) {
    return;
  }

  late Directory root;
  late String executable;
  late String companion;
  final primary = <String, String>{};
  final abi = Abi.current();
  final libraryName = liteRtLmPrimaryLibraryForAbi(abi)!;

  Future<void> compile(
    String source,
    String output, [
    List<String> flags = const [],
  ]) async {
    final result = await Process.run('cc', [
      '-shared',
      '-fPIC',
      '-pthread',
      source,
      ...flags,
      '-o',
      output,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('litert_inventory_');
    companion = path.join(root.path, 'companion');
    await compile('test/fixtures/litert_lm/discovery_companion.c', companion);
    for (final entry in {
      'v1': ('c_api_v1_asr.c', <String>[]),
      'legacy': ('c_api_legacy_service.c', <String>[]),
      'future': ('c_api_version.c', ['-DAPI_MAJOR=2']),
      'malformed': ('c_api_version.c', ['-DOMIT_PATCH_WRITE']),
    }.entries) {
      final file = path.join(root.path, entry.key);
      await compile(
        'test/fixtures/litert_lm/${entry.value.$1}',
        file,
        entry.value.$2,
      );
      primary[entry.key] = file;
    }
    executable = path.join(root.path, 'probe');
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'test/fixtures/litert_lm/discovery_probe.dart',
      '-o',
      executable,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
  tearDownAll(() => root.delete(recursive: true));

  Directory populate(
    String name,
    String version, {
    bool legacyFiles = false,
    List<String>? files,
    String? primaryName,
  }) {
    final directory = Directory(path.join(root.path, name))
      ..createSync(recursive: true);
    for (final file
        in files ??
            liteRtLmRequiredLibrariesForAbi(abi, cApiV1: !legacyFiles)) {
      final destination = File(path.join(directory.path, file));
      destination.parent.createSync(recursive: true);
      File(
        file == (primaryName ?? libraryName) ? primary[version]! : companion,
      ).copySync(destination.path);
    }
    return directory;
  }

  Future<ProcessResult> probe({
    String? directory,
    String? binary,
    String? explicitLibrary,
    bool legacyOff = false,
  }) => Process.run(
    binary ?? executable,
    [legacyOff ? 'legacy-off' : 'staged', ?explicitLibrary],
    environment: {'LLAMADART_LITERT_LM_LIB_DIR': directory ?? ''},
    workingDirectory: root.path,
  );

  void succeeds(ProcessResult result) =>
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  void refuses(ProcessResult result, String message) {
    expect(result.exitCode, 10, reason: '${result.stdout}\n${result.stderr}');
    expect(
      result.stderr,
      allOf(contains('LlamaUnsupportedException'), contains(message)),
    );
  }

  test(
    'compiled selected-directory probe accepts actual v1 and full legacy',
    () async {
      for (final version in ['v1', 'legacy']) {
        final directory = populate(
          'valid-$version',
          version,
          legacyFiles: version == 'legacy',
        );
        succeeds(await probe(directory: directory.path));
      }
    },
  );

  test(
    'version-skew probes refuse future and malformed C APIs without engine calls',
    () async {
      for (final version in ['future', 'malformed']) {
        final directory = populate('invalid-$version', version);
        refuses(await probe(directory: directory.path), 'version probe status');
      }
    },
  );

  test('absent API marker never waives any legacy TopK companion', () async {
    final samplers = liteRtLmRequiredLibrariesForAbi(
      abi,
    ).where((file) => file.contains('TopK')).toList();
    for (var index = 0; index < samplers.length; index++) {
      final directory = populate(
        'truncated-legacy-$index',
        'legacy',
        legacyFiles: true,
      );
      File(path.join(directory.path, samplers[index])).deleteSync();
      refuses(await probe(directory: directory.path), samplers[index]);
    }
  });

  test(
    'malformed explicit primary and companion do not use another image',
    () async {
      for (final file in [
        libraryName,
        liteRtLmCompanionLibrariesForAbi(abi, cApiV1: true).first,
      ]) {
        final directory = populate('corrupt-$file', 'v1');
        File(
          path.join(directory.path, file),
        ).writeAsStringSync('not a native library');
        refuses(await probe(directory: directory.path), 'explicitly selected');
      }
    },
  );

  test(
    'missing each v1 primary/common library fails the explicit directory',
    () async {
      final files = liteRtLmRequiredLibrariesForAbi(abi, cApiV1: true);
      for (var index = 0; index < files.length; index++) {
        final directory = populate('missing-common-$index', 'v1');
        File(path.join(directory.path, files[index])).deleteSync();
        refuses(
          await probe(directory: directory.path),
          'complete LiteRT-LM runtime directory',
        );
      }
    },
  );

  if (Platform.isLinux) {
    test('an older host importing libLiteRt loads from an explicit directory '
        'only when its libLiteRt is present', () async {
      for (final version in ['v1', 'legacy']) {
        final directory = populate(
          'imports-litert-$version',
          version,
          legacyFiles: version == 'legacy',
        );
        // No RUNPATH: like Windows, the import resolves only to a module
        // that is already open.
        await compile(
          'test/fixtures/litert_lm/discovery_companion.c',
          path.join(directory.path, 'libLiteRt.so'),
          ['-Wl,-soname,libLiteRt.so'],
        );
        await compile(
          'test/fixtures/litert_lm/${version == 'v1' ? 'c_api_v1_asr.c' : 'c_api_legacy_service.c'}',
          path.join(directory.path, libraryName),
          ['-L${directory.path}', '-Wl,--no-as-needed', '-lLiteRt'],
        );
        succeeds(await probe(directory: directory.path));
        if (version == 'v1') {
          File(path.join(directory.path, 'libLiteRt.so')).deleteSync();
          refuses(
            await probe(directory: directory.path),
            'explicitly selected',
          );
        }
      }
    });
  }

  test('flag-off retains legacy inventory and refuses v1', () async {
    final legacy = populate('flag-off-legacy', 'legacy', legacyFiles: true);
    succeeds(await probe(directory: legacy.path, legacyOff: true));
    final modern = populate('flag-off-v1', 'v1', legacyFiles: true);
    refuses(
      await probe(directory: modern.path, legacyOff: true),
      'pre-1.0 bindings',
    );
  });

  test(
    'explicit library is one image and does not fall through to directory',
    () async {
      final valid = populate('explicit-fallback', 'v1');
      refuses(
        await probe(
          directory: valid.path,
          explicitLibrary: path.join(root.path, 'missing-primary'),
        ),
        'explicitly selected',
      );
      refuses(
        await probe(directory: valid.path, explicitLibrary: primary['future']),
        'version probe status',
      );
    },
  );

  test(
    'default packaged flat directory works and explicit override wins',
    () async {
      final bundle = Platform.isMacOS
          ? populate('packaged.app/Contents/Frameworks/LiteRtLmRuntime', 'v1')
          : populate('packaged/lib', 'v1');
      final binary = Platform.isMacOS
          ? path.join(root.path, 'packaged.app/Contents/MacOS/probe')
          : path.join(root.path, 'packaged/bin/probe');
      File(binary).parent.createSync(recursive: true);
      File(executable).copySync(binary);
      succeeds(await probe(binary: binary));
      final wrong = populate('package-override-future', 'future');
      refuses(
        await probe(binary: binary, directory: wrong.path),
        'version probe status',
      );
      refuses(
        await probe(binary: binary, directory: path.join(root.path, 'absent')),
        'complete LiteRT-LM runtime directory',
      );
      expect(bundle.existsSync(), isTrue);
    },
  );

  if (Platform.isMacOS) {
    for (final spm in [false, true]) {
      test(
        'macOS ${spm ? 'native SPM' : 'versioned framework'} wrapper reexports selected core',
        () async {
          final files = spm
              ? liteRtLmMacOsRequiredNativeSpmFilesForAbi(abi, cApiV1: true)
              : liteRtLmMacOsRequiredFrameworksForAbi(abi, cApiV1: true);
          const wrapper = 'LiteRtLm.framework/Versions/A/LiteRtLm';
          final directory = populate(
            'framework-$spm.app/Contents/Frameworks',
            'v1',
            files: files,
            primaryName: wrapper,
          );
          final core = spm
              ? 'libCLiteRTLM_mac.dylib'
              : 'CLiteRTLM_mac.framework/Versions/A/CLiteRTLM_mac';
          await compile(
            'test/fixtures/litert_lm/c_api_v1_asr.c',
            path.join(directory.path, core),
          );
          await compile(
            'test/fixtures/litert_lm/discovery_companion.c',
            path.join(directory.path, wrapper),
            ['-Wl,-reexport_library,${path.join(directory.path, core)}'],
          );
          final binary = path.join(directory.parent.path, 'MacOS/probe');
          File(binary).parent.createSync(recursive: true);
          File(executable).copySync(binary);
          succeeds(await probe(binary: binary));
        },
      );
    }
  }
}
