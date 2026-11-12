import '../exceptions.dart';
import 'runtime_setup_report_stub.dart'
    if (dart.library.io) '../../platform/io/runtime_setup_report_io.dart'
    as platform;

/// A pinned publication policy for one runtime, never evidence of native loading.
final class LlamaRuntimeSetupRuntime {
  LlamaRuntimeSetupRuntime._(
    this.name,
    this.expectedReleaseTag,
    this.publication,
  );

  /// Runtime family identifier.
  final String name;

  /// Release tag expected by this package; custom overrides can differ.
  final String expectedReleaseTag;

  /// `published`, `unavailable`, or `unknown` for the host OS/ABI.
  final String publication;

  /// A stable, immutable JSON-compatible snapshot.
  Map<String, Object> toJson() => Map<String, Object>.unmodifiable({
    'name': name,
    'expected_release_tag': expectedReleaseTag,
    'publication': publication,
    'loaded_version': 'unknown',
    'native_loading': 'not_checked',
  });
}

/// A bounded, model-free desktop setup snapshot.
///
/// Publication policy does not establish which assets a consuming app emitted
/// or loaded. No engine, native library, GPU or model is initialized. This is
/// the current Dart process, not validation of a Flutter app, device or browser.
final class LlamaRuntimeSetupReport {
  LlamaRuntimeSetupReport._({
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.architecture,
    required this.dartVersion,
    required this.packageVersion,
    required List<LlamaRuntimeSetupRuntime> runtimes,
    required Map<String, bool> overrides,
  }) : runtimes = List.unmodifiable(runtimes),
       overrides = Map.unmodifiable(overrides);

  /// Version of the JSON report contract.
  int get schemaVersion => 1;

  /// Normalized host OS, or `unknown`.
  final String operatingSystem;

  /// Numeric OS version when safely recognizable, otherwise `unknown`.
  final String operatingSystemVersion;

  /// ABI architecture (`arm64`, `x64`, `arm`, `ia32`, or `unknown`).
  final String architecture;

  /// Dart SDK version without build paths or host details.
  final String dartVersion;

  /// This package's own pubspec version, or `unknown` when unavailable.
  final String packageVersion;

  /// Pinned publication policies, in stable runtime-family order.
  final List<LlamaRuntimeSetupRuntime> runtimes;

  /// Allowlisted native override names and set/unset presence only.
  final Map<String, bool> overrides;

  /// A stable, deeply immutable JSON-compatible snapshot.
  Map<String, Object> toJson() => Map<String, Object>.unmodifiable({
    'schema_version': schemaVersion,
    'scope': 'desktop_process_setup',
    'host': Map<String, Object>.unmodifiable({
      'os': operatingSystem,
      'os_version': operatingSystemVersion,
      'architecture': architecture,
      'dart_version': dartVersion,
      'llamadart_version': packageVersion,
      'flutter_version': 'unknown',
    }),
    'publication_policy': List<Map<String, Object>>.unmodifiable(
      runtimes.map((runtime) => runtime.toJson()),
    ),
    'overrides': Map<String, String>.unmodifiable({
      for (final entry in overrides.entries)
        entry.key: entry.value ? 'set' : 'unset',
    }),
    'observations': const <String, String>{
      'emitted_libraries': 'not_checked',
      'selected_backend': 'unknown',
      'selected_gpu': 'unknown',
      'gpu_usability': 'not_checked',
      'model_capabilities': 'not_checked',
      'inference': 'not_checked',
      'flutter_app_device_browser': 'not_checked',
    },
    'remediation': const <Map<String, String>>[
      {
        'code': 'POLICY_ONLY',
        'hint':
            'Published bundle policy is not proof of emitted or loaded assets; custom overrides can differ.',
      },
      {
        'code': 'RUNTIME_UNCHECKED',
        'hint':
            'Validate the intended app with its model and backend separately.',
      },
    ],
  });

  /// Concise human-readable output using only the report's sanitized fields.
  String toText() => [
    'llamadart setup report (schema $schemaVersion; runtime not verified)',
    'Host: $operatingSystem $operatingSystemVersion / $architecture',
    'Dart: $dartVersion; llamadart: $packageVersion; Flutter: unknown',
    for (final runtime in runtimes)
      '${runtime.name}: expected ${runtime.expectedReleaseTag}; publication ${runtime.publication}; native loading not_checked',
    for (final entry in overrides.entries)
      '${entry.key}: ${entry.value ? 'set' : 'unset'}',
    'Backend: unknown; GPU, emitted libraries, model and inference: not_checked',
    'POLICY_ONLY: Custom overrides can differ from pinned publication policy.',
    'RUNTIME_UNCHECKED: Validate the intended app/model/backend separately.',
  ].join('\n');
}

/// Collects a model-free setup report on macOS, Linux or Windows desktop.
///
/// Throws [LlamaUnsupportedException] on mobile, Web or other runtimes; use
/// app/device/browser validation there. Metadata reads are bounded. The
/// collector does not use the network, launch commands, resolve native assets
/// or initialize native libraries. `dart run` can still run a build hook before
/// this function starts, preparing/downloading assets or failing before main.
Future<LlamaRuntimeSetupReport> collectLlamaRuntimeSetupReport() =>
    platform.collectRuntimeSetupReport();

/// Internal construction boundary, outside the app export. Raw host metadata is
/// normalized before it can enter either renderer.
LlamaRuntimeSetupReport buildRuntimeSetupReport({
  required String os,
  required String osVersion,
  required String architecture,
  required String dartVersion,
  required String packageVersion,
  required List<({String name, String tag, String publication})> policies,
  required Map<String, String> environment,
}) => LlamaRuntimeSetupReport._(
  operatingSystem: const {'macos', 'linux', 'windows'}.contains(os)
      ? os
      : 'unknown',
  operatingSystemVersion: normalizeSetupOsVersion(osVersion),
  architecture: const {'arm64', 'x64', 'arm', 'ia32'}.contains(architecture)
      ? architecture
      : 'unknown',
  dartVersion: normalizeSetupVersion(dartVersion),
  packageVersion: normalizeSetupVersion(packageVersion),
  runtimes: [
    for (final policy in policies)
      LlamaRuntimeSetupRuntime._(
        const {
              'llama_cpp',
              'litert_lm',
              'stable_diffusion',
            }.contains(policy.name)
            ? policy.name
            : 'unknown',
        normalizeSetupVersion(policy.tag, releaseTag: true),
        const {'published', 'unavailable'}.contains(policy.publication)
            ? policy.publication
            : 'unknown',
      ),
  ],
  overrides: {
    for (final name in const [
      'LLAMADART_NATIVE_LIB_DIR',
      'LLAMADART_BACKEND_MODULE_DIR',
      'LLAMADART_LITERT_LM_LIB_DIR',
    ])
      name: environment.containsKey(name),
  },
);

/// Retains only a bounded canonical numeric SDK/package/release version.
String normalizeSetupVersion(String value, {bool releaseTag = false}) {
  if (value.length > 128) return 'unknown';
  final pattern = releaseTag
      ? r'^v[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}(?:-[0-9]{1,6})?$'
      : r'^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}(?:-(?:dev|beta|rc)\.[0-9.]{1,24})?$';
  final match = RegExp(pattern).firstMatch(value);
  return match?.end == value.length ? value : 'unknown';
}

/// Retains numeric OS versions and known macOS version/build framing only.
String normalizeSetupOsVersion(String value) {
  if (value.length > 1024) return 'unknown';
  final match = RegExp(
    r'^(?:Version )?([0-9]{1,6}\.[0-9]{1,6}(?:\.[0-9]{1,6})?)(?: \(Build [a-zA-Z0-9]{1,24}\))?$',
  ).firstMatch(value);
  return match?.end == value.length ? match!.group(1)! : 'unknown';
}
