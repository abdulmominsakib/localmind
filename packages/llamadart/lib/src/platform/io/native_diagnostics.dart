import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as path;

/// Internal CLI runtime identifiers; this is not an engine capability API.
const nativeDiagnosticRuntimes = {'llama_cpp', 'litert_lm', 'stable_diffusion'};

const _codes = {
  'SURFACE_OBSERVED',
  'PROBE_HOST_UNAVAILABLE',
  'ASSET_DECLARATION_UNAVAILABLE',
  'ASSET_DECLARATION_INVALID',
  'ASSET_NOT_DECLARED',
  'ARTIFACT_MISSING',
  'DEPENDENCY_UNAVAILABLE',
  'BINARY_INCOMPATIBLE',
  'LOADER_FAILED',
  'SYMBOL_MISSING',
  'ABI_UNKNOWN',
  'CHILD_FAILED',
  'CHILD_PROTOCOL_INVALID',
  'PROBE_TIMEOUT',
  'TERMINATION_UNCONFIRMED',
};
const _phases = {
  'not_started',
  'declaration',
  'open',
  'symbols',
  'abi',
  'complete',
};
const _sources = {'local_manifest_declaration', 'build_hook_cache'};
const _markers = {
  'not_checked',
  'not_available',
  'tts_v1',
  'callback_v2_finish_v1',
  'unknown',
};

/// Constructs only fixed, privacy-safe observation fields.
Map<String, Object> nativeDiagnosticObservation(
  String runtime,
  String code, {
  String phase = 'not_started',
  String marker = 'not_checked',
  String source = 'local_manifest_declaration',
}) {
  if (!nativeDiagnosticRuntimes.contains(runtime) ||
      !_codes.contains(code) ||
      !_phases.contains(phase) ||
      !_markers.contains(marker) ||
      !_sources.contains(source)) {
    throw const FormatException('Invalid native diagnostic observation');
  }
  return Map.unmodifiable({
    'runtime': runtime,
    'code': code,
    'phase': phase,
    'abi_marker': marker,
    'target_source': source,
    'loader_strategy': source == 'build_hook_cache'
        ? 'direct_hook_cache_files'
        : 'direct_declared_files',
    'loaded_release': 'unknown',
    'emitted_app_libraries': 'not_checked',
    'production_loader': 'not_checked',
    'selected_backend': 'unknown',
    'selected_gpu': 'unknown',
    'gpu_usability': 'not_checked',
    'model_capabilities': 'not_checked',
    'inference': 'not_checked',
    'remediation': switch (code) {
      'SURFACE_OBSERVED' =>
        'Only the checked files and symbols/markers were observed; validate the intended app/model/backend separately.',
      'ASSET_NOT_DECLARED' =>
        'The local manifest does not declare this runtime, and for macOS LiteRT-LM the build hook cache holds no complete runtime. Check the intended build runtime selection and rebuild; publication policy and overrides can differ.',
      'ARTIFACT_MISSING' =>
        'A declared file is unavailable. Regenerate the intended build assets; do not infer runtime publication from this observation.',
      'BINARY_INCOMPATIBLE' =>
        'Check that the declared artifact matches the process OS and ABI, and verify custom overrides.',
      'DEPENDENCY_UNAVAILABLE' =>
        'A dependency or loader search path may be unavailable. Check the runtime packaging and documented OS dependencies.',
      'SYMBOL_MISSING' || 'ABI_UNKNOWN' =>
        'The checked interface is missing or unrecognized. Use the package-compatible runtime and verify custom overrides.',
      'LOADER_FAILED' =>
        'The direct file loader failed. Check packaging, OS dependencies and overrides; production loader behavior remains unchecked.',
      'PROBE_TIMEOUT' || 'TERMINATION_UNCONFIRMED' =>
        'The isolated check did not terminate normally. Validate the runtime separately before retrying.',
      'CHILD_FAILED' || 'CHILD_PROTOCOL_INVALID' =>
        'The isolated check failed without a valid result. No runtime usability conclusion is available.',
      _ =>
        'Use a supported desktop Dart source invocation with its local native-assets manifest. Flutter apps, devices and browsers require separate validation.',
    },
  });
}

/// The human-readable `doctor_native` report for [probe].
String nativeDiagnosticTextReport(
  Map<String, Object> probe, {
  required bool overridesSet,
}) => [
  'llamadart isolated native check (runtime/model not verified)',
  '${probe['runtime']}: ${probe['code']} (${probe['phase']})',
  probe['target_source'] == 'build_hook_cache'
      ? 'Source: build hook cache; direct file loading only.'
      : 'Source: local manifest declaration; direct file loading only.',
  'Loaded release: unknown; production loader, GPU, model and inference: not_checked.',
  probe['remediation'],
  if (overridesSet)
    'OVERRIDES_MAY_DIFFER: Native overrides are set; their values and production resolution are not checked.',
].join('\n');

/// Canonical JSON prevents duplicate keys and ignored trailing data in IPC.
Object? decodeNativeDiagnosticJson(String source) {
  final decoded = jsonDecode(source);
  final compact = StringBuffer();
  var quoted = false;
  var escaped = false;
  for (final unit in source.codeUnits) {
    if (quoted || !const {9, 10, 13, 32}.contains(unit)) {
      compact.writeCharCode(unit);
    }
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        quoted = false;
      }
    } else if (unit == 34) {
      quoted = true;
    }
  }
  if (compact.toString() != jsonEncode(decoded)) {
    throw const FormatException('Noncanonical native diagnostic JSON');
  }
  return decoded;
}

/// A selected manifest entry, never an assertion about a compiled app mapping.
final class NativeDiagnosticTarget {
  /// Concrete file declarations passed only to the private child.
  const NativeDiagnosticTarget(this.primary, this.wrapper, this.companions);

  /// The runtime's declared primary file.
  final String primary;

  /// Wrapper file, or [primary] for a monolithic artifact.
  final String wrapper;

  /// Declared dependency files opened before the primary.
  final List<String> companions;
}

/// Reads a small regular file without leaving asynchronous filesystem work.
///
/// Manifest reads run in the killable child. Parent IPC reads require a private
/// directory with no other writer after confirmed child exit. The no-follow
/// check rejects pipes and links; it is not protection against a hostile
/// same-user process replacing a path between this check and the open.
String readNativeDiagnosticFile(File file, int limit) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Unsupported diagnostic file type');
  }
  final handle = file.openSync();
  try {
    final bytes = handle.readSync(limit + 1);
    if (bytes.length > limit) throw const FormatException('File exceeds limit');
    return utf8.decode(bytes);
  } finally {
    handle.closeSync();
  }
}

/// Reads only the current ABI's known, concrete local file declarations.
NativeDiagnosticTarget? parseNativeDiagnosticManifest(
  String source,
  String abi,
  String runtime,
) {
  if (source.length > 256 * 1024 ||
      !nativeDiagnosticRuntimes.contains(runtime)) {
    throw const FormatException('Invalid manifest');
  }
  final jsonSource = source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('#'))
      .join('\n');
  final decoded = decodeNativeDiagnosticJson(jsonSource);
  if (decoded is! Map ||
      jsonEncode(decoded['format-version']) != '[1,0,0]' ||
      decoded['native-assets'] is! Map) {
    throw const FormatException('Unsupported manifest');
  }
  final entries = (decoded['native-assets'] as Map)[abi];
  if (entries == null) return null;
  if (entries is! Map) throw const FormatException('Invalid ABI entry');
  final primaryId = switch (runtime) {
    'llama_cpp' => 'package:llamadart/llamadart',
    'stable_diffusion' => 'package:llamadart/stable_diffusion',
    _ =>
      'package:llamadart/litert_lm_${abi.startsWith('macos_') ? 'libLiteRtLm' : 'LiteRtLm'}',
  };
  String? file(String id) {
    final entry = entries[id];
    if (entry == null) return null;
    if (entry is! List ||
        entry.length != 2 ||
        entry[0] != 'absolute' ||
        entry[1] is! String ||
        (entry[1] as String).isEmpty ||
        (entry[1] as String).length > 4096 ||
        (entry[1] as String).contains('\u0000') ||
        !path.isAbsolute(entry[1] as String)) {
      throw const FormatException('Unsupported asset declaration');
    }
    return entry[1] as String;
  }

  final primary = file(primaryId);
  if (primary == null) return null;
  final wrapper = runtime == 'llama_cpp' && abi.startsWith('windows_')
      ? file('package:llamadart/llamadart_wrapper')
      : primary;
  if (wrapper == null) {
    throw const FormatException('Missing wrapper declaration');
  }
  final companions = <String>[];
  if (runtime == 'litert_lm') {
    // Fixed IDs only: untrusted neighboring assets are never opened.
    for (final name in const [
      'vcruntime140',
      'vcruntime140_1',
      'vcruntime140_threads',
      'msvcp140',
      'webgpu_dawn',
      'GemmaModelConstraintProvider',
      'LiteRt',
      'LiteRtTopKWebGpuSampler',
      'LiteRtWebGpuAccelerator',
      'libCLiteRTLM_mac',
      'libGemmaModelConstraintProvider',
      'libLiteRt',
      'libLiteRtMetalAccelerator',
      'libLiteRtTopKMetalSampler',
      'libLiteRtTopKWebGpuSampler',
      'libLiteRtWebGpuAccelerator',
      'libwebgpu_dawn',
    ]) {
      final candidate = file('package:llamadart/litert_lm_$name');
      if (candidate != null) companions.add(candidate);
    }
  }
  return NativeDiagnosticTarget(primary, wrapper, companions);
}

/// Injectable process start, confined to internal CLI tests.
typedef NativeDiagnosticProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Recognizes the private CLI source or Dart's package-command snapshot layout.
/// Other app entry points must not relaunch their executable as a Dart helper.
bool isNativeDiagnosticCliInvocation(Uri entry, Uri config, Uri helper) {
  if (entry.scheme != 'file' ||
      config.scheme != 'file' ||
      helper.scheme != 'file') {
    return false;
  }
  if (entry == helper.resolve('../../../../bin/doctor_native.dart')) {
    return true;
  }
  return entry.resolve('.') == config.resolve('pub/bin/llamadart/') &&
      RegExp(
        r'^doctor_native\.dart-[A-Za-z0-9._-]{1,80}\.snapshot$',
      ).hasMatch(entry.pathSegments.last);
}

/// Launches the packaged helper without dartdev, hooks or a shell.
Future<Map<String, Object>> runNativeDiagnostic(
  String runtime, {
  Uri? packageConfig,
  Uri? childScript,
  String? abi,
  NativeDiagnosticProcessStarter? start,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final elapsed = Stopwatch()..start();
  if (!nativeDiagnosticRuntimes.contains(runtime)) {
    throw ArgumentError('Unknown runtime');
  }
  Duration remaining() {
    final left = timeout - elapsed.elapsed;
    if (left <= Duration.zero) throw TimeoutException('Diagnostic deadline');
    return left;
  }

  var phase = 'not_started';
  Map<String, Object> result(String code, [String? at]) =>
      nativeDiagnosticObservation(runtime, code, phase: at ?? phase);
  Process? child;
  Directory? directory;
  var terminated = true;
  var launchExpired = false;
  StreamSubscription<List<int>>? stdoutSubscription;
  StreamSubscription<List<int>>? stderrSubscription;

  Future<Map<String, Object>> work() async {
    remaining();
    if (!const {
      'macos',
      'linux',
      'windows',
    }.contains(Platform.operatingSystem)) {
      return result('PROBE_HOST_UNAVAILABLE');
    }
    // These use the already-loaded isolate package mapping, not an abandoned
    // asynchronous metadata read when the deadline expires.
    final config = packageConfig ?? Isolate.packageConfigSync;
    remaining();
    final script =
        childScript ??
        Isolate.resolvePackageUriSync(
          Uri.parse(
            'package:llamadart/src/platform/io/native_diagnostics_child.dart',
          ),
        );
    remaining();
    if (config == null ||
        config.scheme != 'file' ||
        script == null ||
        script.scheme != 'file' ||
        (childScript == null &&
            !isNativeDiagnosticCliInvocation(
              Platform.script,
              config,
              script,
            )) ||
        FileSystemEntity.typeSync(script.toFilePath()) !=
            FileSystemEntityType.file) {
      return result('PROBE_HOST_UNAVAILABLE');
    }
    remaining();
    phase = 'declaration';
    final manifest = File.fromUri(config.resolve('native_assets.yaml'));
    final type = FileSystemEntity.typeSync(manifest.path, followLinks: false);
    remaining();
    if (type == FileSystemEntityType.notFound) {
      return result('ASSET_DECLARATION_UNAVAILABLE');
    }
    if (type != FileSystemEntityType.file) {
      return result('ASSET_DECLARATION_INVALID');
    }

    // Only the child opens manifest content: replacing a checked regular file
    // with a pipe can block that child, but cannot strand a parent file open.
    directory = Directory.systemTemp.createTempSync(
      'llamadart_native_diagnostic_',
    );
    remaining();
    final output = File('${directory!.path}/result.json');
    final phaseFile = File('${directory!.path}/phase');
    final random = Random.secure();
    final nonce = List.generate(
      24,
      (_) => random.nextInt(256),
    ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    remaining();
    final launch =
        (start ??
        ((executable, arguments) => Process.start(
          executable,
          arguments,
          runInShell: false,
        )))(Platform.resolvedExecutable, [
          '--disable-dart-dev',
          '--packages=${config.toFilePath()}',
          script.toFilePath(),
        ]);
    unawaited(
      launch.then<void>((lateChild) async {
        if (launchExpired) {
          lateChild.kill(ProcessSignal.sigkill);
          unawaited(lateChild.stdout.drain<void>().catchError((Object _) {}));
          unawaited(lateChild.stderr.drain<void>().catchError((Object _) {}));
          unawaited(lateChild.stdin.close().catchError((Object _) {}));
          try {
            await lateChild.exitCode.timeout(const Duration(seconds: 3));
          } catch (_) {
            /* A late launch contributes no runtime evidence. */
          }
        }
      }, onError: (Object _) {}),
    );
    child = await launch.timeout(remaining());
    terminated = false;
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    void complete(Completer<void> done) {
      if (!done.isCompleted) done.complete();
    }

    // Never retain native constructor output, including on a timeout.
    stdoutSubscription = child!.stdout.listen(
      (_) {},
      onError: (Object _) {},
      onDone: () => complete(stdoutDone),
    );
    stderrSubscription = child!.stderr.listen(
      (_) {},
      onError: (Object _) {},
      onDone: () => complete(stderrDone),
    );
    final request = jsonEncode({
      'runtime': runtime,
      'nonce': nonce,
      'output': output.path,
      'phase': phaseFile.path,
      'manifest': manifest.path,
      'abi': abi ?? Abi.current().toString(),
    });
    final code = await (() async {
      child!.stdin.writeln(request);
      try {
        await child!.stdin.close();
      } catch (_) {
        /* A failed child can close first. */
      }
      return child!.exitCode;
    })().timeout(remaining());
    terminated = true;
    await Future.wait([
      stdoutDone.future,
      stderrDone.future,
    ]).timeout(remaining());

    // No child writer remains. Parent reads only its own small private IPC
    // files, synchronously, with type checks and deadline checks on both sides.
    final phaseType = FileSystemEntity.typeSync(
      phaseFile.path,
      followLinks: false,
    );
    remaining();
    if (phaseType != FileSystemEntityType.notFound) {
      final value = readNativeDiagnosticFile(phaseFile, 32);
      remaining();
      if (_phases.contains(value)) phase = value;
    }
    if (code != 0) return result('CHILD_FAILED');
    final payload = decodeNativeDiagnosticJson(
      readNativeDiagnosticFile(output, 8192),
    );
    remaining();
    if (payload is! Map ||
        payload.keys.join(',') != 'runtime,nonce,code,phase,marker,source' ||
        payload['runtime'] != runtime ||
        payload['nonce'] != nonce ||
        !_codes.contains(payload['code']) ||
        !_phases.contains(payload['phase']) ||
        !_markers.contains(payload['marker']) ||
        !_sources.contains(payload['source']) ||
        (payload['source'] == 'build_hook_cache' && runtime != 'litert_lm')) {
      return result('CHILD_PROTOCOL_INVALID');
    }
    if (const {
      'ASSET_DECLARATION_UNAVAILABLE',
      'ASSET_DECLARATION_INVALID',
      'ASSET_NOT_DECLARED',
    }.contains(payload['code'])) {
      if (payload['phase'] != 'declaration' ||
          payload['marker'] != 'not_checked' ||
          payload['source'] != 'local_manifest_declaration') {
        return result('CHILD_PROTOCOL_INVALID');
      }
    } else if (!const {
      'SURFACE_OBSERVED',
      'ARTIFACT_MISSING',
      'DEPENDENCY_UNAVAILABLE',
      'BINARY_INCOMPATIBLE',
      'LOADER_FAILED',
      'SYMBOL_MISSING',
      'ABI_UNKNOWN',
    }.contains(payload['code'])) {
      return result('CHILD_PROTOCOL_INVALID');
    }
    if (payload['code'] == 'SURFACE_OBSERVED' &&
        (payload['phase'] != 'complete' ||
            payload['marker'] !=
                switch (runtime) {
                  'llama_cpp' => 'tts_v1',
                  'litert_lm' => 'callback_v2_finish_v1',
                  _ => 'not_available',
                })) {
      return result('CHILD_PROTOCOL_INVALID');
    }
    return nativeDiagnosticObservation(
      runtime,
      payload['code'] as String,
      phase: payload['phase'] as String,
      marker: payload['marker'] as String,
      source: payload['source'] as String,
    );
  }

  Map<String, Object> observation;
  try {
    observation = await work();
  } on TimeoutException {
    launchExpired = true;
    observation = result('PROBE_TIMEOUT');
  } catch (_) {
    observation = result(
      child == null ? 'PROBE_HOST_UNAVAILABLE' : 'CHILD_PROTOCOL_INVALID',
    );
  }
  // A single reserve covers forced termination, reaping and pipe cancellation.
  // Responsive local filesystem metadata/private regular IPC are assumed;
  // Dart cannot interrupt an arbitrary stalled kernel/filesystem operation.
  final cleanup = Stopwatch()..start();
  Duration reserve() {
    final left = const Duration(seconds: 3) - cleanup.elapsed;
    if (left <= Duration.zero) throw TimeoutException('Cleanup deadline');
    return left;
  }

  if (!terminated && child != null) {
    child!.kill(ProcessSignal.sigkill);
    try {
      await child!.exitCode.timeout(reserve());
      terminated = true;
    } catch (_) {
      /* Report the unconfirmed termination below. */
    }
  }
  try {
    await Future.wait([
      if (stdoutSubscription != null) stdoutSubscription!.cancel(),
      if (stderrSubscription != null) stderrSubscription!.cancel(),
    ]).timeout(reserve());
    if (terminated && directory != null) directory!.deleteSync(recursive: true);
  } catch (_) {
    /* No raw cleanup failure reaches a renderer. */
  }
  if (!terminated) return result('TERMINATION_UNCONFIRMED');
  if (elapsed.elapsed >= timeout) return result('PROBE_TIMEOUT');
  return observation;
}
