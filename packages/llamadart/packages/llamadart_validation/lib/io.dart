/// Native filesystem adapters; never imported by the shared/browser suite.
library;

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'llamadart_validation.dart';

const _downloadRetryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 15),
];

/// Verifies model bytes before reuse or load; download timing is separate.
///
/// A download that drops mid-transfer is retried after each of [retryDelays]
/// within the one [timeout], resuming with a `Range` request when the server
/// honors it and restarting otherwise.
Future<({String path, Map<String, dynamic> evidence})> prepareModel(
  ValidationProfile profile,
  Directory cache, {
  String? suppliedPath,
  Duration timeout = const Duration(minutes: 5),
  http.Client? client,
  List<Duration> retryDelays = _downloadRetryDelays,
  Future<void> Function(Map<String, dynamic>)? onProgress,
}) async {
  profile.requireRunnable();
  return _prepareArtifact(
    profile,
    profile.model,
    cache,
    suppliedPath: suppliedPath,
    timeout: timeout,
    client: client,
    retryDelays: retryDelays,
    onProgress: onProgress,
  );
}

/// Verifies the decision head and optional config of a decision profile
/// like [prepareModel]; `evidence` holds their verification records under
/// `decision_head` and `decision_config`.
Future<({String head, String? config, Map<String, dynamic> evidence})>
prepareDecisionAssets(
  ValidationProfile profile,
  Directory cache, {
  Duration timeout = const Duration(minutes: 5),
  http.Client Function()? client,
  Future<void> Function(Map<String, dynamic>)? onProgress,
}) async {
  final prepared = {
    for (final MapEntry(:key, :value) in profile.decisionArtifacts.entries)
      key: await _prepareArtifact(
        profile,
        value as Map<String, dynamic>,
        cache,
        artifact: 'decision_$key',
        timeout: timeout,
        client: client?.call(),
        onProgress: onProgress,
      ),
  };
  final head =
      prepared['head'] ?? (throw StateError('Profile has no decision head'));
  return (
    head: head.path,
    config: prepared['config']?.path,
    evidence: {
      for (final MapEntry(:key, :value) in prepared.entries)
        'decision_$key': value.evidence,
    },
  );
}

/// Verifies the embedding projector through the same bounded artifact path.
Future<({String path, Map<String, dynamic> evidence})>
prepareEmbeddingProjector(
  ValidationProfile profile,
  Directory cache, {
  String? suppliedPath,
  Duration timeout = const Duration(minutes: 5),
  http.Client? client,
  Future<void> Function(Map<String, dynamic>)? onProgress,
}) => _prepareArtifact(
  profile,
  profile.embeddingProjector,
  cache,
  artifact: 'embedding_projector',
  suppliedPath: suppliedPath,
  timeout: timeout,
  client: client,
  onProgress: onProgress,
);

/// Verifies a tool-result media profile's vision projector.
Future<({String path, Map<String, dynamic> evidence})>
prepareToolResultProjector(
  ValidationProfile profile,
  Directory cache, {
  String? suppliedPath,
  Duration timeout = const Duration(minutes: 5),
  http.Client? client,
  Future<void> Function(Map<String, dynamic>)? onProgress,
}) => _prepareArtifact(
  profile,
  profile.toolResultProjector!,
  cache,
  artifact: 'projector',
  suppliedPath: suppliedPath,
  timeout: timeout,
  client: client,
  onProgress: onProgress,
);

Future<({String path, Map<String, dynamic> evidence})> _prepareArtifact(
  ValidationProfile profile,
  Map<String, dynamic> lock,
  Directory cache, {
  String artifact = 'model',
  String? suppliedPath,
  required Duration timeout,
  http.Client? client,
  List<Duration> retryDelays = _downloadRetryDelays,
  Future<void> Function(Map<String, dynamic>)? onProgress,
}) async {
  final label = artifact.replaceAll('_', ' ');
  final hash = lock['sha256'] as String;
  final size = lock['bytes'] as int;
  final started = Stopwatch()..start();
  final target = suppliedPath == null
      ? File(p.join(cache.path, hash, lock['filename'] as String))
      : File(suppliedPath);
  var hit = target.existsSync();
  Future<void> progress(String stage, int bytes, String state) async {
    await onProgress?.call({
      'type': 'preparation_progress',
      'profile_id': profile.id,
      if (artifact != 'model') 'artifact': artifact,
      'model_sha256': hash,
      'stage': stage,
      'state': state,
      'bytes': bytes,
      'expected_bytes': size,
      'elapsed_ms': started.elapsedMilliseconds,
    });
  }

  Future<bool> valid(File file) async {
    final length = await file.length();
    await progress('checksum', 0, 'started');
    if (length != size) {
      await progress('checksum', length, 'rejected');
      return false;
    }
    var hashed = 0;
    var lastReport = started.elapsedMilliseconds;
    final digest = await sha256
        .bind(
          file.openRead().asyncMap((chunk) async {
            hashed += chunk.length;
            if (started.elapsedMilliseconds - lastReport >= 10000) {
              await progress('checksum', hashed, 'running');
              lastReport = started.elapsedMilliseconds;
            }
            return chunk;
          }),
        )
        .first;
    final matches = digest.toString() == hash;
    await progress('checksum', hashed, matches ? 'verified' : 'rejected');
    return matches;
  }

  final checksum = Stopwatch()..start();
  if (hit && !await valid(target)) {
    if (suppliedPath != null) {
      throw FormatException('Supplied $label hash/size mismatch');
    }
    await target.delete();
    hit = false;
  }
  checksum.stop();
  var downloadMs = 0;
  if (!hit) {
    if (suppliedPath != null) {
      throw FileSystemException('Supplied $label is missing');
    }
    await target.parent.create(recursive: true);
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    final transport = client ?? http.Client();
    var lastReport = started.elapsedMilliseconds;
    var receivedBytes = 0;
    var deadlineExpired = false;
    final timer = Timer(timeout, () {
      deadlineExpired = true;
      transport.close();
    });
    IOSink? sink;
    final watch = Stopwatch()..start();
    try {
      await progress('download', 0, 'started');
      var failures = 0;
      while (true) {
        try {
          final resumeFrom = receivedBytes;
          final request = http.Request('GET', Uri.parse(lock['url'] as String));
          if (resumeFrom > 0) request.headers['Range'] = 'bytes=$resumeFrom-';
          final response = await transport.send(request);
          final resumed =
              resumeFrom > 0 &&
              response.statusCode == 206 &&
              response.headers['content-range']?.startsWith(
                    'bytes $resumeFrom-',
                  ) ==
                  true;
          if (response.statusCode != 200 && !resumed) {
            await response.stream.drain<void>().catchError((_) {});
            throw HttpException('Model download HTTP ${response.statusCode}');
          }
          if (!resumed) receivedBytes = 0;
          final out = temporary.openWrite(
            mode: resumed ? FileMode.append : FileMode.write,
          );
          sink = out;
          await for (final chunk in response.stream) {
            receivedBytes += chunk.length;
            if (receivedBytes > size) {
              throw const FormatException(
                'Model download exceeded locked byte size',
              );
            }
            out.add(chunk);
            if (started.elapsedMilliseconds - lastReport >= 10000) {
              await progress('download', receivedBytes, 'running');
              lastReport = started.elapsedMilliseconds;
            }
          }
          await out.flush();
          await out.close();
          sink = null;
          break;
        } catch (error) {
          final dropped = sink;
          sink = null;
          await dropped?.close().catchError((_) {});
          if (deadlineExpired ||
              failures >= retryDelays.length ||
              !_isTransientDownloadFailure(error)) {
            rethrow;
          }
          await progress('download', receivedBytes, 'retrying');
          await Future<void>.delayed(retryDelays[failures++]);
          if (deadlineExpired) rethrow;
        }
      }
      if (deadlineExpired) throw TimeoutException('Model download deadline');
      timer.cancel();
      downloadMs = watch.elapsedMilliseconds;
      await progress('download', receivedBytes, 'finished');
      checksum.start();
      if (!await valid(temporary)) {
        throw FormatException('Downloaded $label hash/size mismatch');
      }
      checksum.stop();
      await temporary.rename(target.path);
    } catch (_) {
      if (deadlineExpired) {
        throw TimeoutException(
          'Model download deadline exceeded after receiving $receivedBytes '
          'of $size bytes',
          timeout,
        );
      }
      rethrow;
    } finally {
      timer.cancel();
      transport.close();
      await sink?.close();
      if (temporary.existsSync()) await temporary.delete();
    }
  }
  await progress('ready', size, 'verified');
  return (
    path: target.absolute.path,
    evidence: {
      'sha256': hash,
      'bytes': size,
      'verified': true,
      'cache_hit': hit,
      'download_timeout_ms': timeout.inMilliseconds,
      'download_ms': downloadMs,
      'checksum_ms': checksum.elapsedMilliseconds,
      'total_ms': started.elapsedMilliseconds,
    },
  );
}

bool _isTransientDownloadFailure(Object error) =>
    (error is http.ClientException &&
        !error.message.contains('already closed')) ||
    error is SocketException ||
    error is TlsException ||
    (error is HttpException && RegExp(r'HTTP (5\d\d|429)').hasMatch('$error'));

/// Writes incremental records synchronously enough to survive a native crash.
class FileValidationJournal {
  FileValidationJournal(this.directory) {
    directory.createSync(recursive: true);
    final file = File(p.join(directory.path, 'events.jsonl'));
    if (file.existsSync()) {
      throw StateError('Run output already exists; use a new run/attempt');
    }
    _file = file.openSync(mode: FileMode.write);
  }
  final Directory directory;
  late final RandomAccessFile _file;

  Future<void> emit(Map<String, dynamic> event) async {
    final line = jsonEncode(event);
    _file.writeStringSync('$line\n');
    _file.flushSync();
    if (event['type'] == 'manifest') {
      File(
        p.join(directory.path, 'manifest.json'),
      ).writeAsStringSync(line, flush: true);
    }
    // Complete, bounded records provide a provider-log fallback.
    if (utf8.encode(line).length <= 32768) {
      stdout.writeln('LLAMADART_VALIDATION $line');
    }
  }

  /// Persists diagnostics separately from the manifest-first suite protocol.
  Future<void> emitPreparation(Map<String, dynamic> event) async {
    final line = jsonEncode(event);
    File(
      p.join(directory.path, 'preparation.jsonl'),
    ).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    stdout.writeln('LLAMADART_PREPARATION $line');
  }

  void close() => _file.closeSync();
}

/// Recomputes every report format from an existing run journal.
ValidationReport writeReports(Directory directory, {String? nativeLog}) {
  final report = ValidationReport.parse(
    File(p.join(directory.path, 'events.jsonl')).readAsStringSync(),
    nativeLog: nativeLog,
  );
  for (final entry in {
    'results.json': const JsonEncoder.withIndent('  ').convert(report.toJson()),
    'junit.xml': report.toJUnit(),
    'samples.csv': report.toCsv(),
    'summary.html': report.toHtml(),
  }.entries) {
    File(p.join(directory.path, entry.key)).writeAsStringSync(entry.value);
  }
  return report;
}

/// Simple strict long-option parser shared by the private CLI entry points.
Map<String, String> parseOptions(List<String> args, Set<String> allowed) {
  final values = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) {
      throw FormatException('Expected option, got $arg');
    }
    final parts = arg.substring(2).split('=');
    final key = parts.first;
    if (!allowed.contains(key) || values.containsKey(key)) {
      throw FormatException('Unknown/duplicate option --$key');
    }
    if (key == 'help' || key == 'list') {
      values[key] = 'true';
    } else if (parts.length > 1) {
      values[key] = parts.skip(1).join('=');
    } else {
      if (++i >= args.length || args[i].startsWith('--')) {
        throw FormatException('Missing --$key value');
      }
      values[key] = args[i];
    }
  }
  return values;
}

/// Unique bounded state workspace, removed after each case even on failure.
class IoStateValidationWorkspace implements StateValidationWorkspace {
  IoStateValidationWorkspace._(this._directory);
  final Directory _directory;
  static Future<StateValidationWorkspace> create() async =>
      IoStateValidationWorkspace._(
        await Directory.systemTemp.createTemp('llamadart-validation-state-'),
      );
  @override
  String path(String role) {
    if (!const {
      'valid',
      'missing',
      'garbage',
      'short',
      'incompatible',
    }.contains(role)) {
      throw ArgumentError.value(role, 'role');
    }
    return p.join(_directory.path, '$role.state');
  }

  @override
  Future<Uint8List> read(String role) async {
    final file = File(path(role));
    if (await file.length() >
        (statePersistenceFixture['max_artifact_bytes'] as int)) {
      throw StateError('State artifact exceeds the 16 MiB diagnostic bound');
    }
    return file.readAsBytes();
  }

  @override
  Future<void> write(String role, List<int> bytes) async {
    if (bytes.length > (statePersistenceFixture['max_artifact_bytes'] as int)) {
      throw StateError('State artifact exceeds the 16 MiB diagnostic bound');
    }
    await File(path(role)).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> dispose() async {
    await _directory.delete(recursive: true);
    if (await _directory.exists()) {
      throw StateError('State workspace cleanup failed');
    }
  }
}
