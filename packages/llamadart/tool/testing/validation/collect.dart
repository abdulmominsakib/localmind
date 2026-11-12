import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// The root orchestrator shares policy with the private, unpublished harness;
// adding a root package dependency would create a dependency cycle.
// ignore: avoid_relative_lib_imports
import '../../../packages/llamadart_validation/lib/src/litert_gpu_failure_markers.dart';
import 'bundle.dart';
import 'image_profile.dart';
import 'process.dart';
import 'remote.dart';

/// Normalizes pulled journals or complete console records, then re-runs the
/// shared report validator. Provider results alone never prove Dart assertions.
Future<bool> assessCollectedRun(
  String repository,
  RemotePlan plan,
  Directory run, {
  CommandExecutor execute = executeCommand,
  bool offline = false,
}) async {
  final retainedLog = File(p.join(run.path, 'report', 'native.log'));
  if (retainedLog.existsSync()) retainedLog.deleteSync();
  final package = p.join(repository, 'packages/llamadart_validation');
  final packageConfig = File(p.join(package, '.dart_tool/package_config.json'));
  if (offline) _requirePreparedAssessmentDependencies(packageConfig);
  final source = Directory(p.join(run.path, 'remote-results'));
  if (!source.existsSync()) return false;
  final xcresults = source
      .listSync(recursive: true, followLinks: false)
      .whereType<Directory>()
      .where((d) => d.path.endsWith('.xcresult'))
      .toList();
  if (offline &&
      xcresults.isNotEmpty &&
      !run.listSync().whereType<Directory>().any(
        (d) => p.basename(d.path).startsWith('xctest-attachments-'),
      )) {
    throw StateError(
      'Offline reassessment requires previously extracted xcresult attachments',
    );
  }
  for (var i = 0; !offline && i < xcresults.length; i++) {
    if (!Platform.isMacOS) continue;
    final output = Directory(p.join(run.path, 'xctest-attachments-$i'));
    if (!output.existsSync()) {
      await execute('xcrun', [
        'xcresulttool',
        'export',
        'attachments',
        '--path',
        xcresults[i].path,
        '--output-path',
        output.path,
      ], timeout: const Duration(minutes: 2));
    }
  }
  if (plan.firebase) {
    final profileBytes = File(
      p.join(plan.bundle, 'profile.json'),
    ).readAsBytesSync();
    final profile = jsonDecode(utf8.decode(profileBytes)) as Map;
    if (isImageGenerationProfile(profile)) {
      // Grade against the identity that was planned and uploaded.
      final manifestBytes = File(
        p.join(plan.bundle, 'bundle-manifest.json'),
      ).readAsBytesSync();
      final bundle = jsonDecode(utf8.decode(manifestBytes)) as Map;
      return sha256.convert(manifestBytes).toString() ==
              plan.json['bundle_sha256'] &&
          ((bundle['files'] as Map?)?['profile.json'] as Map?)?['sha256'] ==
              sha256.convert(profileBytes).toString() &&
          profile['id'] == plan.profile &&
          bundle['profile'] == plan.profile &&
          bundle['target'] == plan.target.substring('firebase-'.length) &&
          gradeCollectedImageRun(run, profile, bundle);
    }
  }
  final files = <File>[];
  for (final dir in [
    source,
    ...run.listSync().whereType<Directory>().where(
      (d) => p.basename(d.path).startsWith('xctest-attachments-'),
    ),
  ]) {
    files.addAll(
      dir.listSync(recursive: true, followLinks: false).whereType<File>(),
    );
  }
  final candidates = <String, String>{};
  final consoles = <String>[];
  for (final file in files) {
    if (file.lengthSync() > 16 * 1024 * 1024) continue;
    final name = p.basename(file.path).toLowerCase();
    if (!(name.endsWith('.jsonl') ||
        name.endsWith('.log') ||
        name.endsWith('.txt'))) {
      continue;
    }
    String text;
    try {
      text = file.readAsStringSync();
    } catch (_) {
      continue;
    }
    if (name == 'xcodebuild_output.log') consoles.add(text);
    if (!name.endsWith('.jsonl')) {
      final lines = <String>[];
      for (final line in const LineSplitter().convert(text)) {
        const prefix = 'LLAMADART_VALIDATION ';
        final index = line.indexOf(prefix);
        if (index >= 0) lines.add(line.substring(index + prefix.length));
      }
      text = lines.join('\n');
    }
    final lines = const LineSplitter()
        .convert(text)
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) continue;
    try {
      final first = jsonDecode(lines.first) as Map;
      if (first['type'] != 'manifest' ||
          (first['profile'] as Map?)?['id'] != plan.profile) {
        continue;
      }
      final canonical = '${lines.join('\n')}\n';
      candidates[sha256.convert(utf8.encode(canonical)).toString()] = canonical;
    } catch (_) {
      continue;
    }
  }
  // Conflicting pull/log evidence or multiple executions require reconciliation.
  if (candidates.length != 1) return false;
  final output = Directory(p.join(run.path, 'report'))
    ..createSync(recursive: true);
  File(
    p.join(output.path, 'events.jsonl'),
  ).writeAsStringSync(candidates.values.single, flush: true);
  final stderrLogs = [
    for (final f in files)
      if (p.basename(f.path) == 'stderr.log' &&
          f.lengthSync() <= 8 * 1024 * 1024)
        f.path,
  ];
  final consoleLogs = [
    for (final console in consoles)
      ?boundConsoleNativeLog(console, candidates.values.single),
  ];
  String? nativeLog;
  if (stderrLogs.length + consoleLogs.length == 1) {
    nativeLog = stderrLogs.isNotEmpty
        ? stderrLogs.single
        : (retainedLog..writeAsStringSync(consoleLogs.single, flush: true))
              .path;
  } else if (plan.target == 'firebase-android' &&
      !files.any(
        (f) => const {
          'stderr.log',
          'xcodebuild_output.log',
        }.contains(p.basename(f.path).toLowerCase()),
      )) {
    // A stderr or console capture, bound or not, always decides first; the
    // device log is read only for runs that produced neither.
    final logcats = [
      for (final f in files)
        if (p.basename(f.path) == 'logcat' && p.isWithin(source.path, f.path))
          f,
    ];
    if (logcats.length == 1 &&
        logcats.single.lengthSync() <= _logcatReadLimit) {
      final bound = await boundLogcatNativeLog(
        logcats.single
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter()),
        candidates.values.single,
      );
      if (bound != null) {
        nativeLog = (retainedLog..writeAsStringSync(bound, flush: true)).path;
      }
    }
  }
  if (!offline) {
    final resolved = await execute(
      Platform.resolvedExecutable,
      const ['pub', 'get'],
      directory: package,
      timeout: const Duration(minutes: 3),
    );
    if (resolved.code != 0) {
      throw ValidationAssessmentFailure(_stepFailure('dart pub get', resolved));
    }
  }
  final resultFile = File(p.join(output.path, 'results.json'));
  if (resultFile.existsSync()) resultFile.deleteSync();
  final generated = await execute(
    Platform.resolvedExecutable,
    [
      if (offline) '--packages=${packageConfig.path}' else 'run',
      'bin/report.dart',
      output.path,
      if (nativeLog != null) ...['--native-log', nativeLog],
    ],
    directory: package,
    timeout: const Duration(minutes: 3),
  );
  final result = resultFile.existsSync()
      ? jsonDecode(resultFile.readAsStringSync()) as Map
      : null;
  final unqualified =
      generated.code == 1 &&
      (result?['summary'] as Map?)?['qualified'] == false;
  if (result == null || (generated.code != 0 && !unqualified)) {
    throw ValidationAssessmentFailure(
      _stepFailure(
        offline ? 'prepared Dart reporter' : 'dart run bin/report.dart',
        generated,
        detail: result == null ? 'wrote no results.json' : null,
      ),
    );
  }
  final manifest = result['manifest'] as Map;
  final bundle =
      jsonDecode(
            File(
              p.join(plan.bundle, 'bundle-manifest.json'),
            ).readAsStringSync(),
          )
          as Map;
  final profile = jsonDecode(
    File(
      p.join(
        plan.bundle,
        plan.firebase ? 'profile.json' : 'assets/profiles/${plan.profile}.json',
      ),
    ).readAsStringSync(),
  );
  String canonical(Object? value) {
    Object? sort(Object? value) => value is Map
        ? {
            for (final key in (value.keys.cast<String>().toList()..sort()))
              key: sort(value[key]),
          }
        : value is List
        ? value.map(sort).toList()
        : value;
    return jsonEncode(sort(value));
  }

  return generated.code == 0 &&
      (result['summary'] as Map)['qualified'] == true &&
      const [
        'source_commit',
        'source_dirty',
        'hook_sha256',
        'native_tag',
        'litert_tag',
        'bridge_tag',
      ].every(
        (key) =>
            bundle.containsKey(key) &&
            (manifest['environment'] as Map?)?[key] == bundle[key],
      ) &&
      (plan.firebase ||
          (manifest['environment'] as Map?)?['runtime_bundle_sha256'] ==
              plan.json['bundle_sha256']) &&
      canonical(manifest['profile']) == canonical(profile);
}

/// The native log an iOS XCTest run printed to [console] between its first
/// and last validation record, or null unless those records are exactly
/// [journal]'s lines. Lines outside that window belong to no proven run.
String? boundConsoleNativeLog(String console, String journal) {
  const prefix = 'LLAMADART_VALIDATION ';
  final lines = const LineSplitter().convert(console);
  final records = <String>[];
  final native = <String>[];
  var pending = <String>[];
  for (final line in lines) {
    final index = line.indexOf(prefix);
    if (index < 0) {
      if (records.isNotEmpty) pending.add(line);
      continue;
    }
    records.add(line.substring(index + prefix.length));
    native.addAll(pending);
    pending = [];
  }
  final expected = const LineSplitter()
      .convert(journal)
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (records.isEmpty ||
      records.length != expected.length ||
      Iterable.generate(records.length).any((i) => records[i] != expected[i])) {
    return null;
  }
  return native.map((line) => '$line\n').join();
}

/// A Firebase device log covers the whole device session; a quick run is
/// about 15 MB. It is streamed, so this bounds time rather than memory.
const _logcatReadLimit = 128 * 1024 * 1024;

/// The retained app-process lines share the `stderr.log` limit.
const _nativeLogLimit = 8 * 1024 * 1024;

/// How long after its test start record the app may mint its run id, and how
/// long after `started_at` its first native epoch timestamp may follow. Both
/// took under 0.4 s on a Pixel 9 Pro and a Galaxy S24. Ten seconds leaves a
/// slow cold start room and is far shorter than a run, whose cases alone took
/// over 45 s on both, so a later run on the device cannot fall inside it.
const _bindingWindow = Duration(seconds: 10);

/// Slack for placing the test start record on the epoch clock. Device-log
/// times are truncated to the millisecond; they were within 1 ms of the epoch
/// timestamps of the same records in the collected logs.
const _logcatSkew = Duration(milliseconds: 100);

/// How far a daylight saving time change moves the device clock: an hour,
/// or half an hour on Lord Howe Island.
const _daylightSavingShifts = [Duration(minutes: 30), Duration(hours: 1)];

final _logcatLine = RegExp(
  r'^(\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}) +(\d+) +\d+ [VDIWEF] (.*)$',
);
final _abslEpoch = RegExp(
  r'\b[IWEF]\d{4} \d\d:\d\d:(\d{9,11})\.(\d{6})\s+\d+ ',
);
final _modelDirectory = RegExp(r'/validation/models/([0-9a-f]{64})/');

/// A line that may carry a Dart VM service URL, whose path is an auth code:
/// one named as such, or any URL whose host is `localhost`, a subdomain of it
/// or an IP literal, in any case or numeric spelling.
final _serviceUrl = RegExp(
  r'(?:Dart VM service|DevTools).*://|'
  r'://(?:[^\s/@]*@)?'
  r'(?:\[[^\]\s]*\]|(?:[^\s/:?#@]*\.)?localhost\.?|'
  r'(?:0x[0-9a-f]*|\d+)(?:\.(?:0x[0-9a-f]*|\d+)){0,3}\.?)'
  r'(?:[:/?#\s]|$)',
  caseSensitive: false,
);

/// The whole message of a Dart VM service announcement.
final _vmService = RegExp(
  r'^flutter *: (?:The )?Dart VM service is listening on \S+$',
);

/// A device-log `MM-DD HH:MM:SS.mmm` time read as UTC in [year]. The log
/// names neither year nor zone, so only the difference between two records
/// of one log is meaningful.
DateTime _logcatTime(String stamp, int year) => DateTime.utc(
  year,
  int.parse(stamp.substring(0, 2)),
  int.parse(stamp.substring(3, 5)),
  int.parse(stamp.substring(6, 8)),
  int.parse(stamp.substring(9, 11)),
  int.parse(stamp.substring(12, 14)),
  int.parse(stamp.substring(15)),
);

/// The lines a Firebase Android run's app process logged from its test start
/// record onward, or null unless [logcat] is bound to [journal]'s run.
///
/// The device log holds every process of the device session. It is bound only
/// when the journal is an Android LiteRT GPU run, exactly one Flutter test
/// start record names the journal's profile and every other mention of a
/// shared validation test is that process naming that profile, every model
/// that process loaded came from the profile's locked SHA-256 directory, and
/// every epoch timestamp its native lines carry is at or after the journal's
/// `started_at`. The manifest is written before the first load on the same
/// device clock, so no skew is allowed.
///
/// The run is bound in time at both ends. The first of those epoch timestamps
/// is at most [_bindingWindow] after `started_at`. The journal's `run_id` is
/// `app-<epoch microseconds>`, minted after the test start record and before
/// `started_at`; the device log never prints it, so it is bound by its time:
/// it is at most [_bindingWindow] after the start record, whose epoch time is
/// that first timestamp less the device-log time elapsed between the two
/// records. The log cannot show a daylight saving change between them, so
/// that start may also be moved by any of [_daylightSavingShifts] either way.
/// A journal of another run whose times all fall inside those windows is not
/// told apart.
///
/// The retained lines are stored with the report, so a Dart VM service
/// announcement is dropped wherever that process logs it, unless it carries a
/// GPU failure marker, which the report would otherwise never see. Any other
/// line of the process that [_serviceUrl] matches leaves the log unbound, so
/// that no line is altered or silently lost.
Future<String?> boundLogcatNativeLog(
  Stream<String> logcat,
  String journal,
) async {
  final String profile;
  final String model;
  final int started;
  final int minted;
  try {
    final manifest =
        jsonDecode(
              const LineSplitter()
                  .convert(journal)
                  .firstWhere((line) => line.trim().isNotEmpty),
            )
            as Map;
    final declared = manifest['profile'] as Map;
    final time = DateTime.parse(manifest['started_at'] as String);
    final run = RegExp(
      r'^app-(\d{16})$',
    ).firstMatch(manifest['run_id'] as String);
    profile = declared['id'] as String;
    model = (declared['model'] as Map)['sha256'] as String;
    started = time.microsecondsSinceEpoch;
    minted = int.parse(run![1]!);
    if (manifest['type'] != 'manifest' ||
        minted > started ||
        (manifest['environment'] as Map)['platform'] != 'android' ||
        declared['runtime'] != 'litert' ||
        declared['backend'] != 'gpu' ||
        !time.isUtc ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(model)) {
      return null;
    }
  } catch (_) {
    return null;
  }
  const mention = 'shared validation: ';
  final start = RegExp(
    '^flutter *: \\d\\d:\\d\\d \\+0: $mention${RegExp.escape(profile)}\$',
  );
  final named = RegExp('$mention${RegExp.escape(profile)}(?:\\(|\$)');
  String? pid;
  String? began;
  var models = 0;
  var stamps = 0;
  var size = 0;
  final kept = StringBuffer();
  await for (final line in logcat) {
    final entry = _logcatLine.firstMatch(line);
    if (line.contains(mention)) {
      if (entry == null) return null;
      if (start.hasMatch(entry[3]!)) {
        if (pid != null) return null;
        pid = entry[2];
        began = entry[1];
      } else if (entry[2] != pid || !named.hasMatch(line)) {
        return null;
      }
    }
    if (entry == null || pid == null || entry[2] != pid) continue;
    final directories = _modelDirectory.allMatches(line).toList();
    if (directories.any((match) => match[1] != model)) return null;
    if (RegExp(r'\bModel .+ loaded from ').hasMatch(line)) {
      if (directories.isEmpty) return null;
      models++;
    }
    for (final match in _abslEpoch.allMatches(line)) {
      final epoch = int.parse(match[1]!) * 1000000 + int.parse(match[2]!);
      if (epoch < started) return null;
      stamps++;
      if (stamps > 1) continue;
      final year = DateTime.fromMicrosecondsSinceEpoch(epoch, isUtc: true).year;
      final logged = _logcatTime(entry[1]!, year);
      var testStart = _logcatTime(began!, year);
      // A run across the device's New Year starts in the year before; one
      // across a daylight saving change that turns the clock back does not.
      if (testStart.isAfter(logged.add(_daylightSavingShifts.last))) {
        testStart = _logcatTime(began, year - 1);
      }
      final elapsed = logged.difference(testStart);
      bool mintedInWindow(Duration shift) {
        final sinceTestStart =
            minted - (epoch - (elapsed + shift).inMicroseconds);
        return sinceTestStart >= -_logcatSkew.inMicroseconds &&
            sinceTestStart <= _bindingWindow.inMicroseconds;
      }

      if (epoch - started > _bindingWindow.inMicroseconds ||
          ![
            Duration.zero,
            for (final shift in _daylightSavingShifts) ...[shift, -shift],
          ].any(mintedInWindow)) {
        return null;
      }
    }
    size += line.length + 1;
    if (size > _nativeLogLimit) return null;
    if (_serviceUrl.hasMatch(line)) {
      if (!_vmService.hasMatch(entry[3]!) ||
          containsLiteRtGpuFailureMarker(line)) {
        return null;
      }
      continue;
    }
    kept.writeln(line);
  }
  return pid == null || models == 0 || stamps == 0 ? null : kept.toString();
}

String _stepFailure(String step, CommandResult result, {String? detail}) {
  final tail = _redactedTail(result.error);
  return [
    'Validation report step `$step` in packages/llamadart_validation exited '
        '${result.code}',
    ?detail,
    if (tail.isNotEmpty) 'stderr tail:\n$tail',
  ].join('; ');
}

/// The last 20 non-blank lines of [text], at most 2000 characters, with URLs,
/// absolute paths and credential-like values replaced.
String _redactedTail(String text) {
  final lines = const LineSplitter()
      .convert(text)
      .where((line) => line.trim().isNotEmpty)
      .toList();
  var tail = lines.skip(lines.length > 20 ? lines.length - 20 : 0).join('\n');
  if (tail.length > 2000) tail = tail.substring(tail.length - 2000);
  return tail
      .replaceAll(RegExp(r'[A-Za-z][A-Za-z0-9+.-]*://\S+'), '<url>')
      .replaceAllMapped(
        RegExp(
          r'\b(bearer|token|password|secret|key)(\s*[=:]\s*|\s+)\S+',
          caseSensitive: false,
        ),
        (match) => '${match[1]}${match[2]}<redacted>',
      )
      .replaceAll(
        RegExp(r'''(?:[A-Za-z]:)?[\\/](?:[^\s\\/:"']+[\\/])+[^\s\\/:"']*'''),
        '<path>',
      );
}

/// Replays saved raw evidence into a new directory without provider calls or
/// dependency resolution. Cached lifecycle observations retain their age.
Future<Map<String, dynamic>> reassessSavedRun(
  String repository,
  Directory saved,
  Directory output, {
  CommandExecutor execute = executeCommand,
}) async {
  String resolvedPath(String value) {
    final path = p.normalize(p.absolute(value));
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
      return Directory(path).resolveSymbolicLinksSync();
    }
    return p.join(resolvedPath(p.dirname(path)), p.basename(path));
  }

  final savedPath = resolvedPath(saved.path);
  final outputPath = resolvedPath(output.path);
  if (output.existsSync() ||
      FileSystemEntity.typeSync(output.path) != FileSystemEntityType.notFound ||
      p.isWithin(savedPath, outputPath) ||
      p.isWithin(outputPath, savedPath)) {
    throw StateError(
      'Reassessment requires a new directory outside the saved run',
    );
  }
  final state =
      jsonDecode(
            File(p.join(saved.path, 'orchestration.json')).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final plan = RemotePlan(Map<String, dynamic>.from(state['plan'] as Map));
  if (p.basename(saved.path) != plan.runId) {
    throw StateError('Saved run ID mismatch');
  }
  final bundlePath = resolvedPath(plan.bundle);
  if (outputPath == bundlePath ||
      p.isWithin(bundlePath, outputPath) ||
      p.isWithin(outputPath, bundlePath)) {
    throw StateError('Reassessment destination overlaps its saved bundle');
  }
  final manifestFile = File(p.join(plan.bundle, 'bundle-manifest.json'));
  if (sha256.convert(manifestFile.readAsBytesSync()).toString() !=
      plan.json['bundle_sha256']) {
    throw StateError('Bundle changed after planning');
  }
  final bundle = await verifyBundle(Directory(plan.bundle));
  requireRemoteBundleTarget(plan, bundle);
  final packageConfig = File(
    p.join(
      repository,
      'packages/llamadart_validation/.dart_tool/package_config.json',
    ),
  );
  _requirePreparedAssessmentDependencies(packageConfig);
  output.createSync(recursive: true);
  // Only raw collections and prior attachment extractions enter the replay.
  // In particular, an old report/native.log can never become placement evidence.
  for (final directory
      in saved.listSync(followLinks: false).whereType<Directory>()) {
    final name = p.basename(directory.path);
    if (name != 'remote-results' && !name.startsWith('xctest-attachments-')) {
      continue;
    }
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) throw StateError('Symlink in saved evidence');
      if (entity is File) {
        final copy = File(
          p.join(output.path, p.relative(entity.path, from: saved.path)),
        );
        copy.parent.createSync(recursive: true);
        entity.copySync(copy.path);
      }
    }
  }
  final assertions = await assessCollectedRun(
    repository,
    plan,
    output,
    execute: execute,
    offline: true,
  );
  final providerPassed = savedProviderPassed(plan, state['remote'] as Map);
  final result = <String, dynamic>{
    'schema_version': 1,
    'kind': 'offline_reassessment_with_historical_lifecycle',
    'run_id': plan.runId,
    'bundle_sha256': plan.json['bundle_sha256'],
    'saved_plan_sha256': sha256
        .convert(utf8.encode(jsonEncode(plan.json)))
        .toString(),
    'assertions_passed': assertions,
    'historical': {
      'provider': state['remote'],
      'provider_passed': providerPassed,
      'collection': state['collection'],
      'cleanup': state['cleanup'],
      'error': state['error'],
    },
    'qualified':
        assertions &&
        providerPassed &&
        state['collection'] == 'COMPLETE' &&
        state['cleanup'] == 'VERIFIED' &&
        state['error'] == null,
  };
  File(
    p.join(output.path, 'reassessment.json'),
  ).writeAsStringSync(jsonEncode(result), flush: true);
  return result;
}

void _requirePreparedAssessmentDependencies(File config) {
  try {
    final graph = jsonDecode(config.readAsStringSync()) as Map;
    final packages = graph['packages'] as List;
    if (graph['configVersion'] != 2 ||
        packages.isEmpty ||
        !packages.any(
          (entry) => (entry as Map)['name'] == 'llamadart_validation',
        )) {
      throw const FormatException('Unprepared package graph');
    }
    for (final entry in packages.cast<Map>()) {
      final root = config.uri.resolve(entry['rootUri'] as String);
      if (root.scheme != 'file' ||
          !Directory.fromUri(root).existsSync() ||
          !Directory.fromUri(
            Directory.fromUri(
              root,
            ).uri.resolve(entry['packageUri'] as String? ?? 'lib/'),
          ).existsSync()) {
        throw const FormatException('Unavailable package');
      }
    }
  } on Object {
    throw StateError(
      'Offline reassessment requires prepared dependencies: '
      'run dart pub get in packages/llamadart_validation before going offline',
    );
  }
}
