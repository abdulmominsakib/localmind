import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart_validation/src/desktop_bundle.dart';
import 'package:llamadart_validation/src/runtime_environment.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Map<String, dynamic> identity;
  late String runtimePath;
  void put(String name, String content) {
    final file = File(p.join(root.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void seal() {
    put('environment.json', jsonEncode(identity));
    final files = <String, dynamic>{};
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      final name = p.relative(file.path, from: root.path).replaceAll('\\', '/');
      if (name == 'bundle-manifest.json') continue;
      files[name] = {
        'sha256': sha256.convert(file.readAsBytesSync()).toString(),
        'bytes': file.lengthSync(),
      };
    }
    put(
      'bundle-manifest.json',
      jsonEncode({'schema_version': 1, ...identity, 'files': files}),
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('validation-bundle-test-');
    final abi = Abi.current();
    final libraries = liteRtLmRequiredLibrariesForAbi(abi);
    runtimePath = libraries.isEmpty
        ? ''
        : '.dart_tool/llamadart/litert_lm/0.17.0-6/${liteRtLmCacheDirectoryCandidatesForAbi(abi).singleWhere((candidate) => candidate.contains('/'))}';
    identity = {
      'target': 'desktop',
      'build_os': Platform.operatingSystem,
      'build_abi': abi.toString(),
      'litert_tag': '0.17.0-6',
      'litert_runtime_supported': libraries.isNotEmpty,
      if (libraries.isNotEmpty) 'litert_runtime_layout': runtimePath,
    };
    put(
      'bin/llamadart-validate${Platform.isWindows ? '.exe' : ''}',
      'executable',
    );
    put(
      'lib/${Platform.isMacOS
          ? 'libllamadart.dylib'
          : Platform.isWindows
          ? 'llamadart.dll'
          : 'libllamadart.so'}',
      'native',
    );
    for (final library in libraries) {
      put('$runtimePath/$library', library);
    }
    seal();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'verified payload tolerates results without weakening library inventory',
    () async {
      put('results/events.jsonl', 'journal');
      put('model-cache/weights.gguf', 'model');
      final value = await verifyDesktopValidationBundle(
        root,
        environment: const {},
      );
      expect(value['runtime_payload_verified'], true);
      expect(value['runtime_bundle_sha256'], matches(r'^[a-f0-9]{64}$'));
      // Preserve upstream platform-suffixed primary library filenames.
      final native =
          Directory(p.join(root.path, 'lib')).listSync().single as File;
      native.renameSync(
        p.join(native.parent.path, 'llamadart-windows-x64.dll'),
      );
      seal();
      expect(
        (await verifyDesktopValidationBundle(
          root,
          environment: const {},
        ))['runtime_payload_verified'],
        true,
      );
    },
  );
  test('modified runtime bytes fail before inference', () async {
    final native =
        Directory(p.join(root.path, 'lib')).listSync().single as File;
    native.writeAsStringSync('changed');
    await expectLater(
      verifyDesktopValidationBundle(root, environment: const {}),
      throwsFormatException,
    );
  });
  test('unlisted runtime sidecars fail before discovery', () async {
    for (final name in [
      'lib/extra.dll',
      '.dart_tool/lib/extra.so',
      'Frameworks/extra.dylib',
      'extra.dll',
    ]) {
      put(name, 'unchecked');
      await expectLater(
        verifyDesktopValidationBundle(root, environment: const {}),
        throwsFormatException,
      );
      File(p.join(root.path, name)).deleteSync();
    }
  });
  test(
    'self-consistent incomplete LiteRT inventory cannot use ancestor cache',
    () async {
      if (runtimePath.isEmpty) return;
      (Directory(p.join(root.path, runtimePath)).listSync().first as File)
          .deleteSync();
      seal();
      await expectLater(
        verifyDesktopValidationBundle(root, environment: const {}),
        throwsFormatException,
      );
    },
  );
  test('rehashed environment cannot contradict bundle provenance', () async {
    put('environment.json', jsonEncode({...identity, 'litert_tag': 'other'}));
    final file = File(p.join(root.path, 'bundle-manifest.json'));
    final manifest = jsonDecode(file.readAsStringSync()) as Map;
    final environment = File(p.join(root.path, 'environment.json'));
    (manifest['files'] as Map)['environment.json'] = {
      'sha256': sha256.convert(environment.readAsBytesSync()).toString(),
      'bytes': environment.lengthSync(),
    };
    file.writeAsStringSync(jsonEncode(manifest));
    await expectLater(
      verifyDesktopValidationBundle(root, environment: const {}),
      throwsFormatException,
    );
  });
  test('runtime override diagnostics expose names only', () {
    requireValidationRuntimeEnvironment(
      environment: {'PATH': '/usual/path'},
      portable: true,
    );
    for (final key in [
      'LLAMADART_LITERT_LM_LIB_DIR',
      'LLAMADART_NATIVE_LIB_DIR',
      'LLAMADART_BACKEND_MODULE_DIR',
      'LD_PRELOAD',
      'LD_LIBRARY_PATH',
      'DYLD_LIBRARY_PATH',
      'WEBGPU_BRIDGE_ASSETS_TAG',
    ]) {
      expect(
        () => requireValidationRuntimeEnvironment(
          environment: {key: '/secret/token'},
          portable: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'diagnostic',
            allOf(contains(key), isNot(contains('/secret/token'))),
          ),
        ),
      );
    }
  });
  test(
    'public engine refuses ambient override before creating native engine',
    () async {
      final probe = File(p.join(root.path, 'override_probe.dart'))
        ..writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import 'package:llamadart_validation/llamadart_validation.dart';
Future<void> main() async {
  final profile = ValidationProfile.fromJson(jsonDecode(File('assets/profiles/chat-litert-cpu.json').readAsStringSync()));
  final engine = PublicValidationEngine(engineFactory: () => throw StateError('ENGINE_WAS_CREATED'));
  try {
    await engine.load('missing-model', profile);
    throw StateError('OVERRIDE_ACCEPTED');
  } on StateError catch (error) {
    if (!error.message.toString().contains('unset LLAMADART_LITERT_LM_LIB_DIR')) rethrow;
    stdout.write('override rejected before engine creation');
  }
}
''');
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--packages=${p.absolute('.dart_tool/package_config.json')}',
          probe.path,
        ],
        environment: {'LLAMADART_LITERT_LM_LIB_DIR': '/unverified/runtime'},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('override rejected before engine creation'),
      );
    },
  );
}
