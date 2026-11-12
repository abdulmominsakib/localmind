import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'process.dart';

/// The native release and its actual LiteRT dependency, not the LiteRT-LM tag.
const npuRuntimeTag = '0.17.0-6';
const npuLiteRtRevision = '9fe5be45564c868408e6514c8aabb83e211a0911';
const npuDispatchHeaderHash =
    '11dd4d98bd084157ac987b1ee1951f3f96e2b3ca6b51a27c10e645686bf0e3ee';

/// Requires locally supplied gated models and verified Android NPU kits, and
/// keeps `webgpu` profiles to Web bundles and Web decision bundles to WebGPU.
/// Keep this at both build and upload boundaries: old/custom bundles can bypass
/// the builder, and spending a Firebase execution cannot repair missing inputs.
void requireExecutableValidationProfile(
  Map<dynamic, dynamic> profile, {
  bool verifiedAndroidKit = false,
  bool supportsLocalModelPath = false,
  bool web = false,
}) {
  if (web && (profile['model'] as Map?)?['kind'] == 'embedding') {
    throw StateError(
      'Embedding pack Web artifact/reference adapter is unqualified; keep Web NOT_RUN.',
    );
  }
  if (profile['backend'] == 'webgpu' && !web) {
    throw StateError('The webgpu backend runs only in Web bundles.');
  }
  if (web &&
      (profile['model'] as Map?)?['kind'] == 'decision' &&
      profile['backend'] != 'webgpu') {
    throw StateError(
      'Web decision bundles run only on WebGPU; use decision-gguf-webgpu.',
    );
  }
  if (profile['backend'] != 'npu' &&
      (profile['model'] as Map?)?['access'] == 'gated-local-staging' &&
      !supportsLocalModelPath) {
    throw StateError(
      'This gated CPU model requires a verified local file. Use the desktop '
      'runner with --model. Mobile/remote model transfer is not implemented; '
      'do not submit a credential-free download that would consume test quota.',
    );
  }
  if (profile['backend'] == 'npu' && !verifiedAndroidKit) {
    throw StateError(
      'NPU qualification requires a verified Android kit: installed-app vendor packaging, '
      'SoC preflight and per-generation native execution proof are required. '
      'Run validation.dart npu-preflight for the locked input inventory.',
    );
  }
}

/// Stages only verified inputs for the opt-in Android build. No credentials or
/// downloads are involved; models are streamed from APK assets on the device.
Future<Map<String, dynamic>> stageNpuAndroid(
  String root,
  String profileId,
  String? model,
  String? kit,
  Directory stage,
) async {
  final report = await inspectNpuInputs(
    root,
    profileId,
    modelPath: model,
    kitPath: kit,
  );
  if (report['inputs_verified'] != true) {
    throw StateError('NPU inputs are incomplete; run npu-preflight');
  }
  final assets = Directory(p.join(stage.path, 'assets', 'llamadart_npu'))
    ..createSync(recursive: true);
  final libraries = Directory(p.join(stage.path, 'jniLibs', 'arm64-v8a'))
    ..createSync(recursive: true);
  final profileFile = File(
    p.join(
      root,
      'packages/llamadart_validation/assets/profiles/$profileId.json',
    ),
  );
  final profile = jsonDecode(profileFile.readAsStringSync()) as Map;
  profileFile.copySync(p.join(assets.path, 'profile.json'));
  File(model!).copySync(p.join(assets.path, 'model.litertlm'));
  File(
    p.join(kit!, 'npu-kit.json'),
  ).copySync(p.join(assets.path, 'npu-kit.json'));
  for (final name in (report['libraries'] as Map).keys.cast<String>()) {
    File(p.join(kit, name)).copySync(p.join(libraries.path, name));
  }
  for (final file in Directory(kit).listSync().whereType<File>()) {
    if (p.basename(file.path).startsWith('license-')) {
      file.copySync(p.join(assets.path, p.basename(file.path)));
    }
  }
  final systemLibrary = profileId == 'npu-qualcomm-sm8650'
      ? 'libcdsprpc.so'
      : 'libedgetpu_litert.so';
  final original = File(
    p.join(root, 'example/chat_app/android/app/src/main/AndroidManifest.xml'),
  ).readAsStringSync();
  File(p.join(stage.path, 'AndroidManifest.xml')).writeAsStringSync(
    original.replaceFirst(
      '</application>',
      '<uses-native-library android:name="$systemLibrary" android:required="false"/>\n    </application>',
    ),
  );
  return {
    'schema_version': 1,
    'model_sha256': (profile['model'] as Map)['sha256'],
    'device_model': (profile['npu_target'] as Map)['firebase_model'],
    'runtime_tag': npuRuntimeTag,
  };
}

/// Rechecks embedded model and libraries in final APKs, including before upload.
Future<void> verifyNpuApks(
  String root,
  Directory bundle, {
  CommandExecutor execute = executeCommand,
}) async {
  for (final apk in ['app.apk', 'qa-app.apk']) {
    final result = await execute(Platform.isWindows ? 'python' : 'python3', [
      p.join(root, 'tool/testing/validation/check_npu_apk.py'),
      '--apk',
      p.join(bundle.path, apk),
      '--profile',
      p.join(bundle.path, 'profile.json'),
      '--kit',
      p.join(bundle.path, 'npu-kit.json'),
    ], timeout: const Duration(minutes: 5));
    if (result.code != 0) {
      throw StateError('NPU APK contents failed verification: $apk');
    }
  }
}

/// Audits local inputs without network access, executing libraries or dispatching.
/// A successful input check is deliberately separate from hardware qualification.
Future<Map<String, dynamic>> inspectNpuInputs(
  String root,
  String profileId, {
  String? modelPath,
  String? kitPath,
}) async {
  if (!const ['npu-qualcomm-sm8650', 'npu-tensor-g5'].contains(profileId)) {
    throw const FormatException('Select a locked NPU profile');
  }
  final profile =
      jsonDecode(
            File(
              p.join(
                root,
                'packages/llamadart_validation/assets/profiles',
                '$profileId.json',
              ),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final target = profile['npu_target'] as Map<String, dynamic>;
  final model = profile['model'] as Map<String, dynamic>;
  final checks = <Map<String, dynamic>>[];
  void check(String id, bool pass, String reason) => checks.add({
    'id': id,
    'status': pass ? 'PASS' : 'NOT_RUN',
    'reason': reason,
  });
  final pins = File(
    p.join(root, 'lib/src/hook/native_release_pins.dart'),
  ).readAsStringSync();
  final tag = RegExp(
    r"const liteRtLmVersion = '([^']+)'",
  ).firstMatch(pins)?.group(1);
  check(
    'runtime_pin',
    tag == npuRuntimeTag,
    tag == npuRuntimeTag
        ? 'Runtime matches the audited LiteRT dependency'
        : 'Runtime pin changed; resolve and audit its LiteRT dependency again',
  );
  check(
    'model',
    modelPath != null && await _matches(File(modelPath), model),
    'A locally supplied model must match the locked size and SHA256; '
        'no download credentials are read or exported',
  );
  Map<String, dynamic>? kit;
  if (kitPath != null) {
    final file = File(p.join(kitPath, 'npu-kit.json'));
    if (file.existsSync()) {
      kit = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  final identityMatches =
      kit?['schema_version'] == 1 &&
      kit?['target'] == target['soc'] &&
      kit?['runtime_tag'] == npuRuntimeTag &&
      kit?['litert_revision'] == npuLiteRtRevision &&
      kit?['dispatch_header_sha256'] == npuDispatchHeaderHash;
  check(
    'kit_identity',
    identityMatches,
    'Kit must bind the compiled SoC, runtime tag and exact LiteRT source/header; '
        'matching an API version string alone is insufficient',
  );
  final inventory = kit?['libraries'];
  final libraries = inventory is Map ? inventory : const {};
  final required = (target['libraries'] as Map).cast<String, dynamic>();
  final onDisk = kitPath != null && Directory(kitPath).existsSync()
      ? Directory(kitPath)
            .listSync(followLinks: false)
            .map((entry) => p.basename(entry.path))
            .where((name) => name.endsWith('.so'))
            .toSet()
      : <String>{};
  check(
    'kit_library_inventory',
    libraries.length == required.length &&
        required.keys.every(libraries.containsKey) &&
        onDisk.length == required.length &&
        required.keys.every(onDisk.contains),
    'Kit inventory and on-disk shared libraries must exactly match the target lock',
  );
  final libraryEvidence = <String, dynamic>{};
  for (final entry in required.entries) {
    final name = entry.key;
    // Names come only from the checked-in target lock, never an external kit.
    if (p.basename(name) != name || !name.endsWith('.so')) {
      throw const FormatException('Invalid locked library basename');
    }
    final lock = entry.value as Map;
    final declaration = libraries[name];
    final file = kitPath == null ? null : File(p.join(kitPath, name));
    final declared =
        declaration is Map &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(
          declaration['sha256'] is String ? declaration['sha256'] : '',
        ) &&
        declaration['bytes'] is int &&
        declaration['bytes'] > 0;
    final matches =
        file != null &&
        declared &&
        await _matches(file, declaration) &&
        (lock['sha256'] == null || declaration['sha256'] == lock['sha256']);
    var elfMatches = false;
    if (matches) {
      final handle = await file.open();
      try {
        final header = await handle.read(20);
        elfMatches =
            header.length == 20 &&
            header[0] == 0x7f &&
            header[1] == 0x45 &&
            header[2] == 0x4c &&
            header[3] == 0x46 &&
            header[4] == lock['elf_class'] &&
            header[5] == 1 &&
            (header[18] | header[19] << 8) == lock['elf_machine'];
      } finally {
        await handle.close();
      }
    }
    check(
      'library:$name',
      identityMatches && matches && elfMatches,
      'Require kit identity, file hash/size and the expected ELF architecture',
    );
    if (matches && elfMatches) {
      libraryEvidence[name] = {
        'sha256': declaration['sha256'],
        'bytes': declaration['bytes'],
        'elf_machine': lock['elf_machine'],
      };
    }
  }
  return {
    'schema_version': 1,
    'profile': profileId,
    'profile_sha256': sha256
        .convert(utf8.encode(jsonEncode(profile)))
        .toString(),
    'target': target['soc'],
    'model': model,
    'runtime_tag': tag,
    'litert_revision': npuLiteRtRevision,
    'dispatch_header_sha256': npuDispatchHeaderHash,
    'checks': checks,
    'libraries': libraryEvidence,
    'inputs_verified': checks.every((check) => check['status'] == 'PASS'),
    'status': 'NOT_RUN',
    'dispatch_allowed': false,
    'qualified': false,
    'remaining': [
      'Inspect final APK dependencies, licenses and sandbox-accessible model delivery',
      'Check on-device Build.SOC_MODEL, ABI and API level before native load',
      'Run installed-app direct-native reference and public Dart NPU bundles separately',
      'Require per-generation completed NPU execution evidence; selector and async submission do not qualify',
    ],
  };
}

Future<bool> _matches(File file, Map lock) async {
  // Reject symbolic links so the audit only covers regular kit files.
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() != lock['bytes']) {
    return false;
  }
  return (await sha256.bind(file.openRead()).first).toString() ==
      lock['sha256'];
}
