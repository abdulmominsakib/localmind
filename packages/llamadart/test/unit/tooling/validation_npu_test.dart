@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/testing/validation/bundle.dart';
import '../../../tool/testing/validation/npu.dart';
import '../../../tool/testing/validation/process.dart';

void main() {
  late Directory root;
  late Directory kit;
  late File model;
  late File dispatch;
  late Map<String, dynamic> manifest;
  const id = 'npu-tensor-g5';

  Future<Map<String, dynamic>> inspect() =>
      inspectNpuInputs(root.path, id, kitPath: kit.path, modelPath: model.path);
  void save() => File(
    p.join(kit.path, 'npu-kit.json'),
  ).writeAsStringSync(jsonEncode(manifest));
  String status(Map<String, dynamic> report, String id) =>
      (report['checks'] as List).cast<Map>().singleWhere(
            (check) => check['id'] == id,
          )['status']
          as String;

  setUp(() {
    root = Directory.systemTemp.createTempSync('npu-input-test-');
    kit = Directory(p.join(root.path, 'kit'))..createSync();
    model = File(p.join(root.path, 'model.litertlm'))
      ..writeAsStringSync('fixture model');
    final header = List<int>.filled(20, 0)
      ..setRange(0, 6, [0x7f, 0x45, 0x4c, 0x46, 2, 1])
      ..[18] = 183;
    dispatch = File(p.join(kit.path, 'libLiteRtDispatch_GoogleTensor.so'))
      ..writeAsBytesSync(header);
    final profile =
        jsonDecode(
              File(
                'packages/llamadart_validation/assets/profiles/$id.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    profile['model']['bytes'] = model.lengthSync();
    // Fixture checks filesystem behavior with a tiny ELF header; real binary
    // qualification is deliberately outside this model-free unit test.
    (profile['npu_target']['libraries'] as Map).remove(
      'libLlamadartVendor_GoogleTensor.so',
    );
    profile['npu_target']['libraries'][p.basename(dispatch.path)]['sha256'] =
        sha256.convert(dispatch.readAsBytesSync()).toString();
    profile['model']['sha256'] = sha256
        .convert(model.readAsBytesSync())
        .toString();
    final profileFile = File(
      p.join(
        root.path,
        'packages/llamadart_validation/assets/profiles/$id.json',
      ),
    );
    profileFile.parent.createSync(recursive: true);
    profileFile.writeAsStringSync(jsonEncode(profile));
    final pins = File(
      p.join(root.path, 'lib/src/hook/native_release_pins.dart'),
    );
    pins.parent.createSync(recursive: true);
    pins.writeAsStringSync("const liteRtLmVersion = '$npuRuntimeTag';");
    manifest = {
      'schema_version': 1,
      'target': 'Google_Tensor_G5',
      'runtime_tag': npuRuntimeTag,
      'litert_revision': npuLiteRtRevision,
      'dispatch_header_sha256': npuDispatchHeaderHash,
      'libraries': {
        p.basename(dispatch.path): {
          'bytes': dispatch.lengthSync(),
          'sha256': sha256.convert(dispatch.readAsBytesSync()).toString(),
        },
      },
    };
    save();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('gated CPU profiles require local-file support before remote use', () {
    final profile =
        jsonDecode(
              File(
                'packages/llamadart_validation/assets/profiles/gemma3-litert-cpu.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(
      () => requireExecutableValidationProfile(profile),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('desktop runner with --model'),
        ),
      ),
    );
    expect(
      () => requireExecutableValidationProfile(
        profile,
        supportsLocalModelPath: true,
      ),
      returnsNormally,
    );
    expect(
      () => requireExecutableValidationProfile({
        'backend': 'cpu',
        'model': {'access': 'public'},
      }),
      returnsNormally,
    );
  });

  test('WebGPU profiles need a Web bundle, and Web decision bundles WebGPU', () {
    Map profile(String backend, {String family = 'decision'}) =>
        jsonDecode(
              File(
                'packages/llamadart_validation/assets/profiles/$family-gguf-$backend.json',
              ).readAsStringSync(),
            )
            as Map;
    Matcher rejects(String message) => throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        contains(message),
      ),
    );
    for (final family in ['decision', 'chat']) {
      expect(
        () => requireExecutableValidationProfile(
          profile('webgpu', family: family),
        ),
        rejects('only in Web bundles'),
        reason: family,
      );
      expect(
        () => requireExecutableValidationProfile(
          profile('webgpu', family: family),
          web: true,
        ),
        returnsNormally,
        reason: family,
      );
    }
    expect(
      () => requireExecutableValidationProfile(profile('cpu'), web: true),
      rejects('only on WebGPU'),
    );
    expect(
      () => requireExecutableValidationProfile(profile('cpu')),
      returnsNormally,
    );
    expect(
      () => requireExecutableValidationProfile({
        'backend': 'cpu',
        'model': {'access': 'public', 'kind': 'raw'},
      }, web: true),
      returnsNormally,
    );
  });

  test('gated CPU mobile builds fail before any build command', () async {
    final profile = File(
      p.join(
        root.path,
        'packages/llamadart_validation/assets/profiles/gemma3-litert-cpu.json',
      ),
    );
    profile.writeAsStringSync(
      File(
        'packages/llamadart_validation/assets/profiles/gemma3-litert-cpu.json',
      ).readAsStringSync(),
    );
    for (final target in ['android', 'ios', 'ios-inputs', 'web']) {
      var invoked = false;
      await expectLater(
        buildValidationBundle(
          root.path,
          target,
          p.join(root.path, 'output-$target'),
          profile: 'gemma3-litert-cpu',
          execute: (binary, args, {directory, timeout, environment}) async {
            invoked = true;
            throw StateError('Build command must not run');
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Mobile/remote model transfer is not implemented'),
          ),
        ),
      );
      expect(invoked, false);
    }
  });

  test(
    'WebGPU and decision bundles off their host fail before any build command',
    () async {
      for (final (target, id, message) in [
        ('desktop', 'decision-gguf-webgpu', 'only in Web bundles'),
        ('android', 'decision-gguf-webgpu', 'only in Web bundles'),
        ('ios-inputs', 'decision-gguf-webgpu', 'only in Web bundles'),
        ('web', 'decision-gguf-cpu', 'only on WebGPU'),
        ('web', 'decision-gguf-metal', 'only on WebGPU'),
        ('desktop', 'chat-gguf-webgpu', 'only in Web bundles'),
        ('android', 'chat-gguf-webgpu', 'only in Web bundles'),
        ('ios', 'chat-gguf-webgpu', 'only in Web bundles'),
        ('ios-inputs', 'chat-gguf-webgpu', 'only in Web bundles'),
      ]) {
        File(
          p.join(
            root.path,
            'packages/llamadart_validation/assets/profiles/$id.json',
          ),
        ).writeAsStringSync(
          File(
            'packages/llamadart_validation/assets/profiles/$id.json',
          ).readAsStringSync(),
        );
        var invoked = false;
        await expectLater(
          buildValidationBundle(
            root.path,
            target,
            p.join(root.path, 'output-$target-$id'),
            profile: id,
            execute: (binary, args, {directory, timeout, environment}) async {
              invoked = true;
              throw StateError('Build command must not run');
            },
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains(message),
            ),
          ),
          reason: '$target $id',
        );
        expect(invoked, false);
      }
    },
  );

  test(
    'matching input inventory never qualifies or permits dispatch',
    () async {
      final report = await inspect();
      expect(report['inputs_verified'], true);
      expect(report['qualified'], false);
      expect(report['dispatch_allowed'], false);
      expect(report['status'], 'NOT_RUN');
      expect(report['remaining'], isNotEmpty);
      expect(jsonEncode(report), isNot(contains(root.path)));
    },
  );

  test(
    'absent model and kit are actionable, not a download or success',
    () async {
      final report = await inspectNpuInputs(root.path, id);
      expect(status(report, 'model'), 'NOT_RUN');
      expect(status(report, 'kit_identity'), 'NOT_RUN');
      expect(report['inputs_verified'], false);
    },
  );

  test('wrong SoC, revision, header or runtime invalidates the kit', () async {
    for (final key in [
      'target',
      'runtime_tag',
      'litert_revision',
      'dispatch_header_sha256',
    ]) {
      final original = manifest[key];
      manifest[key] = 'incompatible';
      save();
      final report = await inspect();
      expect(status(report, 'kit_identity'), 'NOT_RUN', reason: key);
      expect(report['inputs_verified'], false, reason: key);
      manifest[key] = original;
    }
  });

  test('runtime pin drift requires a new dependency audit', () async {
    File(
      p.join(root.path, 'lib/src/hook/native_release_pins.dart'),
    ).writeAsStringSync("const liteRtLmVersion = '0.18.0';");
    expect(status(await inspect(), 'runtime_pin'), 'NOT_RUN');
  });

  test(
    'undeclared or unrelated libraries cannot enter a verified kit',
    () async {
      File(p.join(kit.path, 'libUnexpected.so')).writeAsStringSync('extra');
      expect(status(await inspect(), 'kit_library_inventory'), 'NOT_RUN');
      File(p.join(kit.path, 'libUnexpected.so')).deleteSync();
      manifest['libraries']['libUnexpected.so'] = {'bytes': 1, 'sha256': 'bad'};
      save();
      expect(status(await inspect(), 'kit_library_inventory'), 'NOT_RUN');
    },
  );

  test('corrupted, missing or symlinked library fails input checks', () async {
    for (final mutation in ['corrupt', 'missing', 'symlink']) {
      if (dispatch.existsSync()) dispatch.deleteSync();
      if (mutation == 'corrupt') dispatch.writeAsStringSync('bad');
      if (mutation == 'symlink') Link(dispatch.path).createSync(model.path);
      final report = await inspect();
      expect(
        status(report, 'library:${p.basename(dispatch.path)}'),
        'NOT_RUN',
        reason: mutation,
      );
    }
  });

  test(
    'matching hash cannot disguise a host/DSP architecture mismatch',
    () async {
      final bytes = dispatch.readAsBytesSync()..[18] = 164;
      dispatch.writeAsBytesSync(bytes);
      manifest['libraries'][p.basename(dispatch.path)]['sha256'] = sha256
          .convert(bytes)
          .toString();
      final profileFile = File(
        p.join(
          root.path,
          'packages/llamadart_validation/assets/profiles/$id.json',
        ),
      );
      final profile = jsonDecode(profileFile.readAsStringSync()) as Map;
      profile['npu_target']['libraries'][p.basename(dispatch.path)]['sha256'] =
          manifest['libraries'][p.basename(dispatch.path)]['sha256'];
      profileFile.writeAsStringSync(jsonEncode(profile));
      save();
      expect(
        status(await inspect(), 'library:${p.basename(dispatch.path)}'),
        'NOT_RUN',
      );
    },
  );

  test('a caller-supplied hash cannot replace the locked probe', () async {
    final bytes = [...dispatch.readAsBytesSync(), 1];
    dispatch.writeAsBytesSync(bytes);
    manifest['libraries'][p.basename(dispatch.path)] = {
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    };
    save();
    expect(
      status(await inspect(), 'library:${p.basename(dispatch.path)}'),
      'NOT_RUN',
    );
  });

  test('model size and SHA256 must both match', () async {
    model.writeAsStringSync('fixture Model');
    expect(status(await inspect(), 'model'), 'NOT_RUN');
    model.writeAsStringSync('short');
    expect(status(await inspect(), 'model'), 'NOT_RUN');
  });

  test('NPU build rejected before SDK or build commands', () async {
    var calls = 0;
    await expectLater(
      buildValidationBundle(
        root.path,
        'android',
        p.join(root.path, 'out'),
        profile: id,
        execute: (binary, arguments, {directory, timeout, environment}) async {
          calls++;
          throw StateError('must not reach build executor');
        },
      ),
      throwsA(isA<StateError>().having((e) => '$e', 'reason', contains('NPU'))),
    );
    expect(calls, 0);
  });

  test(
    'verified NPU build passes the staged inputs to every Android build',
    () async {
      for (final path in [
        '.flutter-version',
        'hook/build.dart',
        'scripts/fetch_webgpu_bridge_assets.sh',
        'packages/llamadart_validation/pubspec.lock',
        'example/chat_app/pubspec.lock',
        'example/chat_app/android/app/src/main/AndroidManifest.xml',
      ]) {
        final target = File(p.join(root.path, path));
        target.parent.createSync(recursive: true);
        File(path).copySync(target.path);
      }
      File(
        p.join(root.path, 'lib/src/hook/native_release_pins.dart'),
      ).writeAsStringSync(
        "const llamaCppTag = 'v0.0.0';\n"
        "const liteRtLmVersion = '$npuRuntimeTag';\n",
      );
      final javaHome = p.join(root.path, 'jdk');
      File(
        p.join(javaHome, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
      ).createSync(recursive: true);
      final commands = <(String, List<String>, Map<String, String>?)>[];
      final outputs = p.join(root.path, 'example/chat_app/build/app/outputs');
      await buildValidationBundle(
        root.path,
        'android',
        p.join(root.path, 'out'),
        profile: id,
        npuKit: kit.path,
        model: model.path,
        environment: {'JAVA_HOME': javaHome},
        execute: (binary, args, {directory, timeout, environment}) async {
          commands.add((binary, args, environment));
          if (binary == 'git') {
            return CommandResult(
              0,
              args.first == 'rev-parse' ? 'a' * 40 : '',
              '',
            );
          }
          if (binary == 'flutter' && args.first == '--version') {
            return CommandResult(
              0,
              jsonEncode({
                'frameworkVersion': File(
                  '.flutter-version',
                ).readAsStringSync().trim(),
                'dartSdkVersion': Platform.version.split(' ').first,
              }),
              '',
            );
          }
          if (binary == 'flutter' && args.first == 'config') {
            return CommandResult(0, jsonEncode({'jdk-dir': javaHome}), '');
          }
          for (final path in [
            if (binary == 'flutter' && args.first == 'build')
              p.join(outputs, 'flutter-apk', 'app-debug.apk'),
            if (binary.contains('gradlew'))
              p.join(
                outputs,
                'apk',
                'androidTest',
                'debug',
                'app-debug-androidTest.apk',
              ),
          ]) {
            File(path).createSync(recursive: true);
          }
          return const CommandResult(0, '', '');
        },
      );
      final builds = commands.where(
        (command) =>
            command.$2.take(2).join(' ') == 'pub get' ||
            command.$2.first == 'build' ||
            command.$1.contains('gradlew'),
      );
      expect(builds.map((command) => command.$2.first), [
        'pub',
        'build',
        'build',
        'app:assembleAndroidTest',
      ]);
      for (final (binary, args, environment) in builds) {
        expect(
          environment,
          containsPair(
            'LLAMADART_VALIDATION_NPU_STAGE',
            isA<String>().having(p.basename, 'basename', 'npu'),
          ),
          reason: '$binary $args',
        );
      }
    },
    skip: Platform.isWindows ? 'NPU APK builder needs macOS/Linux' : false,
  );
}
