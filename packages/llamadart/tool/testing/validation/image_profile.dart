import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// The chat app owns the single model its image test downloads; profiles must
// lock exactly that file. Read it without the app's Flutter package resolver.
// ignore: avoid_relative_lib_imports
import '../../../example/chat_app/lib/models/image_model_profile.dart';
import '../../../example/chat_app/integration_test/support/image_evidence.dart';
import '../../../example/chat_app/integration_test/support/image_settings_evidence.dart';

/// The chat-app integration test an image-generation bundle compiles.
const imageGenerationTestTarget =
    'integration_test/image_generation_e2e_test.dart';

/// The chat-app integration test an image settings comparison bundle
/// compiles.
const imageSettingsTestTarget =
    'integration_test/image_settings_comparison_e2e_test.dart';

/// The `suite` of an image profile that runs the settings comparison
/// instead of the image screen check.
const imageSettingsSuite = 'settings-comparison';

/// Where that test writes its evidence on Android (app external files).
const androidImageEvidenceDirectory =
    '/sdcard/Android/data/com.example.llamadart_chat_example/files/'
    '$imageEvidenceDirectoryName';

/// Where the settings comparison writes its evidence on Android.
const androidImageSettingsDirectory =
    '/sdcard/Android/data/com.example.llamadart_chat_example/files/'
    '$imageSettingsDirectoryName';

/// Where the shared validation test writes its journal on Android.
const androidValidationDirectory =
    '/sdcard/Android/data/com.example.llamadart_chat_example/files/validation';

/// Each image backend runs on one mobile target, and the test records the
/// device name the stable_diffusion runtime reports for it.
const _imageBackends = {
  'cpu': (target: 'android', device: 'CPU'),
  'metal': (target: 'ios', device: 'MTL0'),
};

/// Whether [profile] is an image-generation profile rather than a text one.
bool isImageGenerationProfile(Map<dynamic, dynamic> profile) =>
    profile['runtime'] == 'stable_diffusion';

/// Whether image [profile] runs the settings comparison.
bool isImageSettingsProfile(Map<dynamic, dynamic> profile) =>
    profile['suite'] == imageSettingsSuite;

/// The chat-app test an image [profile]'s bundle compiles.
String imageProfileTestTarget(Map<dynamic, dynamic> profile) =>
    isImageSettingsProfile(profile)
    ? imageSettingsTestTarget
    : imageGenerationTestTarget;

/// The dart-defines an image [profile]'s bundle adds: a settings profile
/// names the variants its run compares and those its device class may see
/// refused by the memory check, and downloads its models in
/// parallel ranges: Test Lab devices fetch one Hugging Face connection at a
/// few MB/s, which took SD-Turbo 7 to 12 minutes of a 20-minute run.
List<String> imageProfileDefines(Map<dynamic, dynamic> profile) => [
  if (isImageSettingsProfile(profile)) ...[
    'IMAGE_SETTINGS_VARIANTS=${(profile['variants'] as List).join(',')}',
    if (profile['expected_refusals'] case final List refusals)
      'IMAGE_SETTINGS_EXPECTED_REFUSALS=${refusals.join(',')}',
    for (final (key, define) in _runSizeDefines)
      if (profile[key] case final int value) '$define=$value',
    'LLAMADART_CHAT_PARALLEL_DOWNLOAD=true',
  ],
];

/// The Android directory Test Lab pulls for image [profile].
String androidImageProfileDirectory(Map<dynamic, dynamic> profile) =>
    isImageSettingsProfile(profile)
    ? androidImageSettingsDirectory
    : androidImageEvidenceDirectory;

/// The bundled profile file for [id]: text profiles live in `profiles/`,
/// image-generation profiles in `image_profiles/`, and an ID names one file.
File validationProfileFile(String package, String id) {
  final candidates = [
    for (final directory in ['profiles', 'image_profiles'])
      File(p.join(package, 'assets', directory, '$id.json')),
  ].where((file) => file.existsSync()).toList();
  if (candidates.length != 1) {
    throw FormatException(
      candidates.isEmpty
          ? 'Unknown validation profile: $id'
          : 'Validation profile $id exists as both a text and an image profile',
    );
  }
  return candidates.single;
}

String _revisionOf(String url) {
  final uri = Uri.parse(url);
  return uri.pathSegments[uri.pathSegments.indexOf('resolve') + 1];
}

/// The model lock of the chat app's SDXS profile, as the image test records
/// it in its evidence receipt, plus the download URL the profile pins.
Map<String, Object> sdxsModelLock() {
  const profile = ImageModelProfile.sdxs;
  return {
    'id': profile.id,
    'revision': _revisionOf(profile.modelSource.url),
    'filename': profile.modelSource.filename,
    'sha256': profile.modelSource.sha256!,
    'bytes': profile.modelSource.sizeBytes!,
    'url': profile.modelSource.url,
  };
}

/// Every file the settings comparison downloads (the chat app's SDXS and
/// SD-Turbo profiles, TAESD included), as its receipt records them, plus the
/// download URL each profile pins.
List<Map<String, Object>> imageSettingsModelLocks() => [
  for (final profile in [ImageModelProfile.sdxs, ImageModelProfile.sdTurbo])
    for (final source in profile.sources)
      {
        'filename': source.filename,
        'sha256': source.sha256!,
        'bytes': source.sizeBytes!,
        'revision': _revisionOf(source.url),
        'url': source.url,
      },
];

/// Rejects an image profile that is malformed, locks another model than the
/// one the test downloads, or is built for a target its backend cannot run on.
/// Keep this at both build and upload boundaries, like NPU kit checks.
void requireImageGenerationProfile(
  Map<dynamic, dynamic> profile,
  String target,
) {
  final backend = _imageBackends[profile['backend']];
  final settings = isImageSettingsProfile(profile);
  final executionPathValid =
      !profile.containsKey('execution_path') ||
      profile['execution_path'] == 'public_api';
  final shapeValid =
      isImageGenerationProfile(profile) &&
      profile['schema_version'] == 1 &&
      RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch('${profile['id']}') &&
      executionPathValid &&
      _sameKeys(profile, [
        'schema_version',
        'id',
        'runtime',
        'backend',
        if (settings) ...['suite', 'variants', 'models'] else 'model',
        // The builder records the execution path in the bundled copy.
        if (profile.containsKey('execution_path')) 'execution_path',
        for (final (key, _) in _runSizeDefines)
          if (settings && profile.containsKey(key)) key,
        if (settings && profile.containsKey('expected_refusals'))
          'expected_refusals',
      ]) &&
      _runSizeDefines.every(
        (entry) =>
            !profile.containsKey(entry.$1) ||
            (profile[entry.$1] is int &&
                (profile[entry.$1] as int) >= 1 &&
                (profile[entry.$1] as int) <= 4),
      );
  final variants = profile['variants'];
  final refusals = profile['expected_refusals'];
  if (!shapeValid ||
      !(settings
          ? _locksAll(profile['models'], imageSettingsModelLocks()) &&
                variants is List &&
                variants.isNotEmpty &&
                variants.toSet().length == variants.length &&
                variants.every(imageSettingsVariants.containsKey) &&
                (refusals == null ||
                    (refusals is List &&
                        refusals.isNotEmpty &&
                        refusals.toSet().length == refusals.length &&
                        refusals.every(variants.contains)))
          : _locks(profile['model'], sdxsModelLock()))) {
    throw FormatException(
      settings
          ? 'Image settings profiles lock the chat app SDXS, SD-Turbo and '
                'TAESD files exactly: schema_version, id, runtime '
                'stable_diffusion, backend, suite $imageSettingsSuite, '
                'variants of ${imageSettingsVariants.keys.join(', ')}, '
                'models with kind image, and optionally rounds and '
                'measured_per_load from 1 to 4 and expected_refusals of its '
                'variants'
          : 'Image-generation profiles lock the chat app SDXS model exactly: '
                'schema_version, id, runtime stable_diffusion, backend and a '
                'model with kind image',
    );
  }
  if (backend == null) {
    throw FormatException(
      'Image-generation backend ${profile['backend']} has no device route; '
      'use ${_imageBackends.keys.join(' or ')}',
    );
  }
  if (target != backend.target) {
    throw UnsupportedError(
      'Image-generation profile ${profile['id']} runs only in ${backend.target} '
      'bundles; the ${profile['backend']} backend is not routed on $target',
    );
  }
}

/// Optional settings profile keys that size a run, and the test's defines.
const _runSizeDefines = [
  ('rounds', 'IMAGE_SETTINGS_ROUNDS'),
  ('measured_per_load', 'IMAGE_SETTINGS_MEASURED'),
];

bool _sameKeys(Map<dynamic, dynamic> value, List<String> keys) =>
    value.length == keys.length && keys.every(value.containsKey);

bool _locks(Object? model, Map<String, Object> lock) =>
    model is Map &&
    _sameKeys(model, [...lock.keys, 'kind']) &&
    model['kind'] == 'image' &&
    lock.entries.every((entry) => model[entry.key] == entry.value);

bool _locksAll(Object? models, List<Map<String, Object>> locks) =>
    models is List &&
    models.length == locks.length &&
    [
      for (final (index, lock) in locks.indexed) _locks(models[index], lock),
    ].every((locked) => locked);

/// The pinned stable_diffusion release tag at [root], which the image test
/// compiles in and records as its runtime tag.
String readStableDiffusionTag(String root) {
  final pins = File(
    p.join(root, 'lib/src/hook/native_release_pins.dart'),
  ).readAsStringSync();
  final tag = RegExp(
    "const stableDiffusionReleaseTag = '([^']+)'",
  ).firstMatch(pins)?.group(1);
  if (tag == null) throw StateError('Cannot establish the image runtime pin');
  return tag;
}

/// Grades one collected Firebase image-generation run with the maintained
/// image verifier and writes `report/image-verdict.json`. The evidence must
/// match the bundle exactly: clean source commit, the profile's backend
/// device, the bundle's runtime tag and model lock, seed 42, 512x512 and
/// structurally valid PNGs whose bytes match the receipt. A settings
/// comparison profile is graded by `verifyImageSettingsEvidence` instead,
/// against the same identity, its model locks and the refusals the profile
/// declares in `expected_refusals`.
///
/// Android evidence is the pulled `image_generation_e2e/run-*` (or
/// `image_settings/run-*`) directory. iOS evidence is the XCTest attachments
/// the runner adds from the app's cache directory, exported from `.xcresult`
/// on macOS. Exactly one run's files must be present; anything else does not
/// verify.
bool gradeCollectedImageRun(
  Directory run,
  Map<dynamic, dynamic> profile,
  Map<dynamic, dynamic> bundle,
) {
  final settings = isImageSettingsProfile(profile);
  final report = Directory(p.join(run.path, 'report'))
    ..createSync(recursive: true);
  final verdict = File(p.join(report.path, 'image-verdict.json'));
  if (verdict.existsSync()) verdict.deleteSync();
  final expected = <String, Object?>{
    'source_commit': bundle['source_commit'],
    'source_dirty': false,
    'backend': _imageBackends[profile['backend']]?.device,
    'runtime_tag': bundle['stable_diffusion_tag'],
    if (settings) 'variants': profile['variants'],
    if (settings) 'expected_refusals': profile['expected_refusals'] ?? [],
    if (settings)
      for (final (key, _) in _runSizeDefines)
        if (profile.containsKey(key)) key: profile[key],
    if (settings)
      'model_locks': [
        for (final model in profile['models'] as List)
          {
            for (final key in ['filename', 'sha256', 'bytes', 'revision'])
              key: (model as Map)[key],
          },
      ]
    else
      'model_lock': {
        for (final key in ['id', 'filename', 'sha256', 'bytes', 'revision'])
          key: (profile['model'] as Map)[key],
      },
  };
  String? reason;
  String? location;
  Map<String, dynamic>? evidence;
  try {
    if (bundle['source_dirty'] != false ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch('${bundle['source_commit']}') ||
        expected['backend'] == null ||
        expected['runtime_tag'] is! String) {
      throw const FormatException('Bundle lacks a clean image build identity');
    }
    final directory = _locateImageEvidence(
      run,
      report,
      settings ? _settingsEvidence : _e2eEvidence,
    );
    location = p.relative(directory.path, from: run.path);
    if (settings) {
      final manifest = verifyImageSettingsEvidence(
        directory,
        expectedCommit: expected['source_commit'] as String,
        expectedBackend: expected['backend'] as String,
        expectedRuntimeTag: expected['runtime_tag'] as String,
        expectedModelLocks: [
          for (final lock in expected['model_locks'] as List)
            Map<String, dynamic>.from(lock as Map),
        ],
        expectedVariants: [
          for (final variant in expected['variants'] as List) variant as String,
        ],
        expectedRefusals: [
          for (final variant in expected['expected_refusals'] as List)
            variant as String,
        ],
      );
      for (final (key, _) in _runSizeDefines) {
        if (expected.containsKey(key) && manifest[key] != expected[key]) {
          throw FormatException('Image settings $key mismatch');
        }
      }
      // The loads stay in the receipt; the verdict carries the table.
      evidence = {
        for (final key in [
          'source_commit',
          'os',
          'os_version',
          'runtime_tag',
          'runtime_version',
          'memory_source',
          'variants',
          'rounds',
          'measured_per_load',
          'summary',
        ])
          key: manifest[key],
      };
    } else {
      evidence = verifyImageEvidence(
        directory,
        expectedCommit: expected['source_commit'] as String,
        expectedBackend: expected['backend'] as String,
        expectedRuntimeTag: expected['runtime_tag'] as String,
        expectedModelLock: Map<String, dynamic>.from(
          expected['model_lock'] as Map,
        ),
      );
    }
  } on FormatException catch (error) {
    reason = error.message;
  } on Object catch (error) {
    // Like the verifier CLI: any malformed receipt fails closed, by type only.
    reason = 'Image evidence is unreadable or malformed (${error.runtimeType})';
  }
  verdict.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'schema_version': 1,
      'kind': settings ? 'image_settings_comparison' : 'image_generation_e2e',
      'profile': profile['id'],
      'evidence_verified': reason == null,
      'reason': ?reason,
      'expected': expected,
      'evidence_directory': ?location,
      'evidence': ?evidence,
    }),
    flush: true,
  );
  return reason == null;
}

/// Where one image test's evidence lives and which files make it up:
/// [names] are required exactly once, [optional] matches further files.
typedef _EvidenceLayout = ({
  String directory,
  String manifest,
  Set<String> names,
  RegExp? optional,
});

const _EvidenceLayout _e2eEvidence = (
  directory: imageEvidenceDirectoryName,
  manifest: imageEvidenceManifestName,
  names: {
    imageEvidenceManifestName,
    'image_generation_e2e.png',
    'image_generation_screen.png',
  },
  optional: null,
);

final _EvidenceLayout _settingsEvidence = (
  directory: imageSettingsDirectoryName,
  manifest: imageSettingsReceiptName,
  names: {imageSettingsReceiptName},
  // The receipt names the PNGs it needs; the verifier requires each one.
  optional: RegExp(r'^(journal\.jsonl|[a-z_]+__[a-z_]+\.png)$'),
);

/// Exported attachments are named `<stem>_<index>_<UUID>.<extension>`.
final _exportedAttachment = RegExp(
  r'^(.+)_\d+_[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'
  r'(\.[a-z]+)$',
);

Directory _locateImageEvidence(
  Directory run,
  Directory report,
  _EvidenceLayout layout,
) {
  final pulled = [
    for (final file in Directory(
      p.join(run.path, 'remote-results'),
    ).listSync(recursive: true, followLinks: false).whereType<File>())
      if (p.basename(file.path) == layout.manifest &&
          RegExp(
            '/files/${layout.directory}/run-\\d+\$',
          ).hasMatch(p.dirname(file.path).replaceAll('\\', '/')))
        file.parent,
  ];
  final attached = <String, List<File>>{};
  for (final exported in run.listSync().whereType<Directory>().where(
    (d) => p.basename(d.path).startsWith('xctest-attachments-'),
  )) {
    final manifest = File(p.join(exported.path, 'manifest.json'));
    if (!manifest.existsSync()) continue;
    for (final test in jsonDecode(manifest.readAsStringSync()) as List) {
      for (final attachment in (test as Map)['attachments'] as List) {
        final match = _exportedAttachment.firstMatch(
          '${(attachment as Map)['suggestedHumanReadableName']}',
        );
        final name = match == null ? null : '${match[1]}${match[2]}';
        final file = File(
          p.join(
            exported.path,
            p.basename('${attachment['exportedFileName']}'),
          ),
        );
        if (name != null &&
            (layout.names.contains(name) ||
                (layout.optional?.hasMatch(name) ?? false))) {
          (attached[name] ??= []).add(file);
        }
      }
    }
  }
  if (pulled.length + (attached.isEmpty ? 0 : 1) != 1) {
    throw FormatException(
      pulled.isEmpty && attached.isEmpty
          ? 'No image evidence was collected'
          : 'More than one image evidence run was collected',
    );
  }
  if (pulled.isNotEmpty) return pulled.single;
  if (!layout.names.every(attached.containsKey) ||
      attached.values.any((files) => files.length != 1)) {
    throw const FormatException(
      'XCTest attachments do not hold exactly one image evidence run',
    );
  }
  final staged = Directory(p.join(report.path, 'image-evidence'));
  if (staged.existsSync()) staged.deleteSync(recursive: true);
  staged.createSync(recursive: true);
  for (final entry in attached.entries) {
    entry.value.single.copySync(p.join(staged.path, entry.key));
  }
  return staged;
}
