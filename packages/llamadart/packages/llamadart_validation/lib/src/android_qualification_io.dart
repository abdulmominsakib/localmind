import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:ffi/ffi.dart';

import 'android_qualification.dart';
import 'android_qualification_libraries.dart';

/// Binds the child to the full admitted source/runtime/plan envelope.
String androidQualificationExecutionHash(Map<String, dynamic> binding) =>
    sha256.convert(utf8.encode(jsonEncode(binding))).toString();

/// Reads and checks the admitted build binding, never inferring clean source.
Map<String, dynamic> readAndroidQualificationBinding(
  String text,
  AndroidQualificationPlan plan, {
  String? consumerCpuProfile,
  String? consumerPlanHash,
}) {
  if ((consumerCpuProfile == null) != (consumerPlanHash == null)) {
    throw const FormatException('Incomplete consumer profile binding');
  }
  final value = jsonDecode(text);
  if (value is! Map<String, dynamic> ||
      value['schema'] != 1 ||
      value['plan_sha256'] != (consumerPlanHash ?? plan.hash) ||
      value['source_dirty'] != false ||
      value['native_tag'] != 'v0.9.0' ||
      value['native_archive_sha256'] !=
          'd3c933a63e8ccaafeee32edd30685fdccd17c05e54b75895282f01fe74914a1b') {
    throw const FormatException('Android diagnostic build binding mismatch');
  }
  for (final key in ['source_commit', 'source_tree']) {
    if (value[key] is! String ||
        !RegExp(r'^[a-f0-9]{40}$').hasMatch(value[key] as String)) {
      throw const FormatException('Invalid diagnostic source identity');
    }
  }
  for (final key in [
    'source_inventory_sha256',
    'hook_sha256',
    if (consumerCpuProfile == null) 'probe_sha256',
    if (consumerCpuProfile != null) 'consumer_pubspec_sha256',
    'selector_sha256',
  ]) {
    if (value[key] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value[key] as String)) {
      throw const FormatException('Missing diagnostic source/build hash');
    }
  }
  final libraries = value['libraries'];
  final archive = value['archive_libraries'];
  if (libraries is! Map ||
      !libraries.containsKey('libllama.so') ||
      !libraries.containsKey('libggml-vulkan.so') ||
      (consumerCpuProfile == null &&
          !libraries.containsKey('libllamadart_android_qualification.so'))) {
    throw const FormatException('Missing diagnostic runtime inventory');
  }
  for (final entry in libraries.entries) {
    _validateAndroidLibraryLock(entry.key, entry.value);
  }
  if (archive is! Map<String, dynamic> ||
      archive.isEmpty ||
      archive.containsKey('libllamadart_android_qualification.so')) {
    throw const FormatException('Missing complete owner archive provenance');
  }
  for (final entry in archive.entries) {
    _validateAndroidLibraryLock(entry.key, entry.value);
  }
  final expected = androidQualificationLibrarySelection(
    archive.keys,
    cpuProfile: consumerCpuProfile,
  );
  final selection = value['packaging_selection'];
  if (selection is! Map ||
      selection.length != expected.length ||
      expected.entries.any(
        (entry) =>
            !selection.containsKey(entry.key) ||
            jsonEncode(selection[entry.key]) != jsonEncode(entry.value),
      )) {
    throw const FormatException(
      'Diagnostic packaged selection differs from the normal hook',
    );
  }
  final packaged = (expected['packaged'] as List<String>);
  if (libraries.length !=
          packaged.length + (consumerCpuProfile == null ? 1 : 0) ||
      packaged.any(
        (name) =>
            !libraries.containsKey(name) ||
            libraries[name]['bytes'] != archive[name]['bytes'] ||
            libraries[name]['sha256'] != archive[name]['sha256'],
      )) {
    throw const FormatException(
      'Diagnostic packaged inventory differs from owner bytes',
    );
  }
  if (consumerCpuProfile == null &&
      libraries['libllamadart_android_qualification.so']['sha256'] !=
          value['probe_sha256']) {
    throw const FormatException('Conflicting diagnostic probe identity');
  }
  return value;
}

void _validateAndroidLibraryLock(Object? name, Object? value) {
  if (name is! String ||
      !RegExp(r'^lib[A-Za-z0-9_.-]+\.so$').hasMatch(name) ||
      value is! Map ||
      value['bytes'] is! int ||
      value['bytes'] <= 0 ||
      value['sha256'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String)) {
    throw const FormatException('Invalid diagnostic library lock');
  }
}

/// Hashes actual regular files before any model load or child launch.
Future<Map<String, Object>> verifyAndroidQualificationFile(
  File file,
  Map lock,
) async {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() != lock['bytes']) {
    throw const FormatException('Diagnostic file type or size mismatch');
  }
  final digest = (await sha256.bind(file.openRead()).first).toString();
  if (digest != lock['sha256']) {
    throw const FormatException('Diagnostic file checksum mismatch');
  }
  return {'bytes': lock['bytes'] as int, 'sha256': digest};
}

/// Verifies actual mapped paths, rejecting same-name libraries from elsewhere.
Future<void> verifyAndroidQualificationMaps(
  String maps,
  Directory directory,
  Map<String, dynamic> binding, {
  required bool vulkan,
}) async {
  final inventory = binding['libraries'] as Map;
  final seen = <String>{};
  for (final line in const LineSplitter().convert(maps)) {
    final match = RegExp(
      r'^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(.+)$',
    ).firstMatch(line);
    if (match == null) continue;
    final mappedPath = match.group(1)!;
    final name = p.basename(
      mappedPath.replaceFirst(RegExp(r' \(deleted\)$'), ''),
    );
    if (!name.startsWith('libggml') && !name.startsWith('libllama')) {
      continue;
    }
    if (!inventory.containsKey(name) ||
        p.normalize(mappedPath) != p.join(directory.path, name)) {
      throw const FormatException('Mapped runtime is outside admitted APK');
    }
    if (seen.add(name)) {
      await verifyAndroidQualificationFile(
        File(p.join(directory.path, name)),
        inventory[name] as Map,
      );
    }
  }
  if (!seen.contains('libllama.so') ||
      !seen.contains('libggml-base.so') ||
      (vulkan && !seen.contains('libggml-vulkan.so'))) {
    throw const FormatException('Required mapped runtime evidence missing');
  }
}

typedef _CreatNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _Creat = int Function(Pointer<Utf8>, int);
typedef _DupNative = Int32 Function(Int32);
typedef _Dup = int Function(int);
typedef _Dup2Native = Int32 Function(Int32, Int32);
typedef _Dup2 = int Function(int, int);

/// Captures public-process native stderr; errors never become silent success.
class AndroidQualificationStderr {
  AndroidQualificationStderr._(this._saved);

  /// Redirects only for a serialized test stage, restoring on [close].
  factory AndroidQualificationStderr.capture(File output) {
    final libc = DynamicLibrary.process();
    final creat = libc.lookupFunction<_CreatNative, _Creat>('creat');
    final dup = libc.lookupFunction<_DupNative, _Dup>('dup');
    final path = output.path.toNativeUtf8();
    final saved = dup(2);
    if (saved < 0) {
      malloc.free(path);
      throw StateError('Cannot save native stderr');
    }
    try {
      final descriptor = creat(path, 384);
      if (descriptor < 0) throw StateError('Cannot open native stderr');
      try {
        if (_dup2(descriptor, 2) != 2) {
          throw StateError('Cannot redirect native stderr');
        }
      } finally {
        _close(descriptor);
      }
      return AndroidQualificationStderr._(saved);
    } on Object {
      _close(saved);
      rethrow;
    } finally {
      malloc.free(path);
    }
  }
  static final _Dup2 _dup2 = DynamicLibrary.process()
      .lookupFunction<_Dup2Native, _Dup2>('dup2');
  static final _Dup _close = DynamicLibrary.process()
      .lookupFunction<_DupNative, _Dup>('close');
  int? _saved;

  /// Restores the prior descriptor exactly once.
  void close() {
    final saved = _saved;
    if (saved == null) return;
    _saved = null;
    try {
      if (_dup2(saved, 2) != 2) {
        throw StateError('Cannot restore native stderr');
      }
    } finally {
      _close(saved);
    }
  }
}

/// Executes only one owned process, persisting raw bytes before parsing/oracles.
///
/// Native controls also arm their own watchdog. This outer deadline kills only
/// this child; model-free host tests do not prove Android executable admission.
/// S24 callers validate their separate protocol and binding from the retained
/// raw files; `protocol_complete` describes only the GGUF-shaped parser.
Future<Map<String, dynamic>> captureAndroidNativeChild({
  required String executable,
  required List<String> arguments,
  required Directory output,
  required String binding,
  required String caseId,
  required Duration timeout,
  Map<String, String> environment = const {},
  int stdoutLimit = 2 * 1024 * 1024,
  int stderrLimit = 8 * 1024 * 1024,
}) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(binding) ||
      !RegExp(r'^(a35|pixel8a|s24)\.native\.[a-z-]+$').hasMatch(caseId) ||
      timeout <= Duration.zero ||
      timeout > const Duration(seconds: 120) ||
      stdoutLimit <= 0 ||
      stderrLimit <= 0 ||
      stdoutLimit > 2 * 1024 * 1024 ||
      stderrLimit > 8 * 1024 * 1024) {
    throw const FormatException('Invalid diagnostic child bounds');
  }
  if (output.existsSync()) {
    throw StateError('Diagnostic child output already exists');
  }
  output.createSync(recursive: true);
  final stdoutFile = File(p.join(output.path, 'stdout.jsonl'));
  final stderrFile = File(p.join(output.path, 'stderr.log'));
  final stdoutHandle = stdoutFile.openSync(mode: FileMode.writeOnly);
  final stderrHandle = stderrFile.openSync(mode: FileMode.writeOnly);
  Process? child;
  Timer? deadline;
  var timedOut = false;
  var exceeded = false;
  var captureFailed = false;
  var stdoutBytes = 0;
  var stderrBytes = 0;
  int? exitCode;
  final started = Stopwatch()..start();
  Future<void>? stdoutDone;
  Future<void>? stderrDone;
  StreamSubscription<List<int>>? stdoutSubscription;
  StreamSubscription<List<int>>? stderrSubscription;
  try {
    child = await Process.start(
      executable,
      arguments,
      environment: environment,
      includeParentEnvironment: false,
    );
    await child.stdin.close();
    void capture(List<int> bytes, RandomAccessFile file, bool standardOutput) {
      final before = standardOutput ? stdoutBytes : stderrBytes;
      final limit = standardOutput ? stdoutLimit : stderrLimit;
      final count = bytes.length < limit - before
          ? bytes.length
          : limit - before;
      try {
        if (count > 0) {
          file.writeFromSync(bytes, 0, count);
          file.flushSync();
        }
      } on FileSystemException {
        captureFailed = true;
        child!.kill(ProcessSignal.sigkill);
      }
      if (standardOutput) {
        stdoutBytes += count;
      } else {
        stderrBytes += count;
      }
      if (bytes.length > count) {
        exceeded = true;
        child!.kill(ProcessSignal.sigkill);
      }
    }

    stdoutSubscription = child.stdout.listen((bytes) {
      capture(bytes, stdoutHandle, true);
    });
    stdoutDone = stdoutSubscription.asFuture<void>();
    stderrSubscription = child.stderr.listen((bytes) {
      capture(bytes, stderrHandle, false);
    });
    stderrDone = stderrSubscription.asFuture<void>();
    deadline = Timer(timeout, () {
      timedOut = true;
      child!.kill(ProcessSignal.sigkill);
    });
    exitCode = await child.exitCode;
    // A child that left inherited pipes open cannot keep collection unbounded.
    try {
      await Future.wait([
        stdoutDone,
        stderrDone,
      ]).timeout(const Duration(seconds: 5));
    } on Object {
      captureFailed = true;
      rethrow;
    }
  } finally {
    deadline?.cancel();
    if (exitCode == null) child?.kill(ProcessSignal.sigkill);
    await stdoutSubscription?.cancel();
    await stderrSubscription?.cancel();
    stdoutHandle.closeSync();
    stderrHandle.closeSync();
    started.stop();
    final receipt = {
      'schema': 1,
      'binding': binding,
      'case_id': caseId,
      'pid': child?.pid,
      'exit_code': exitCode,
      'timed_out': timedOut,
      'capture_limit_exceeded': exceeded,
      'capture_failed': captureFailed,
      'elapsed_ms': started.elapsedMilliseconds,
      'qualified': false,
      'capture_complete': exitCode != null && !exceeded && !captureFailed,
      'files': {
        for (final file in [stdoutFile, stderrFile])
          p.basename(file.path): {
            'bytes': file.lengthSync(),
            'sha256': sha256.convert(file.readAsBytesSync()).toString(),
          },
      },
    };
    File(
      p.join(output.path, 'capture.json'),
    ).writeAsStringSync('${jsonEncode(receipt)}\n', flush: true);
  }
  final receipt =
      jsonDecode(File(p.join(output.path, 'capture.json')).readAsStringSync())
          as Map<String, dynamic>;
  // Failures retain raw bytes and receipts, but never gain parsed success.
  if (exitCode != 0 || timedOut || exceeded || captureFailed) return receipt;
  try {
    receipt['records'] = parseAndroidNativeRecords(
      stdoutFile.readAsBytesSync(),
      binding: binding,
      caseId: caseId,
      processId: child.pid,
    );
    receipt['protocol_complete'] = true;
  } on FormatException {
    receipt['protocol_complete'] = false;
  }
  File(
    p.join(output.path, 'capture.json'),
  ).writeAsStringSync('${jsonEncode(receipt)}\n', flush: true);
  return receipt;
}
