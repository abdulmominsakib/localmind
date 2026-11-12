/// IO capture for the private, source-bound S24 LiteRT qualifier.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';

import 'android_litert_qualification.dart';
import 'src/litert_gpu_failure_markers.dart';
import 'src/s24_litert_capture.dart';

Future<String> s24LiteRtFileHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> requireS24LiteRtFile(File file, Map lock) async {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() != lock['bytes'] ||
      await s24LiteRtFileHash(file) != lock['sha256']) {
    throw const FormatException(
      'S24 input bytes differ from admitted identity',
    );
  }
}

/// Checks the complete installed native directory, including non-LiteRT payloads.
Future<void> requireS24LiteRtPayloads(Directory directory, Map binding) async {
  final inventory = binding['libraries'] as Map;
  final files = directory.listSync().whereType<File>().where(
    (file) => file.path.endsWith('.so'),
  );
  final names = {for (final file in files) file.uri.pathSegments.last};
  if (names.length != inventory.length || !names.containsAll(inventory.keys)) {
    throw const FormatException('Installed Android native inventory differs');
  }
  for (final entry in inventory.entries) {
    await requireS24LiteRtFile(
      File('${directory.path}/${entry.key}'),
      entry.value as Map,
    );
  }
}

/// Copies the existing base64 envelope, also consumed by the Pixel qualifier.
Map<String, dynamic> captureS24LiteRtBytes(List<int> bytes) =>
    encodeS24LiteRtCapture(bytes, allowUtf8: false);

/// Copies S24 bytes with the smaller lossless UTF-8 or base64 envelope.
Map<String, dynamic> captureCompactS24LiteRtBytes(List<int> bytes) =>
    encodeS24LiteRtCapture(bytes);

List<int> readS24LiteRtBytes(Map capture) => decodeS24LiteRtCapture(capture);

/// Actual process mappings plus file hashes; same-name substitutions are refused.
Future<Map<String, dynamic>> captureS24LiteRtMappings(
  Directory directory,
  Map binding, {
  void Function(String phase, String? library)? diagnostic,
}) async {
  diagnostic?.call('mapping_capture_started', null);
  final raw = await File('/proc/self/maps').readAsBytes();
  final result = await verifyS24LiteRtMappings(
    raw,
    directory,
    binding,
    diagnostic: diagnostic,
  );
  diagnostic?.call('mapping_capture_completed', null);
  return result;
}

/// Verifies captured maps; the optional hash boundary supports model-free tests.
Future<Map<String, dynamic>> verifyS24LiteRtMappings(
  List<int> raw,
  Directory directory,
  Map binding, {
  Future<String> Function(File file)? hashFile,
  void Function(String phase, String? library)? diagnostic,
}) async {
  final inventory = binding['libraries'] as Map;
  final canonicalDirectory = await directory.resolveSymbolicLinks();
  if (directory.path != canonicalDirectory) {
    throw const FormatException('Noncanonical Android native directory');
  }
  final observed = <String, String>{};
  for (final line in utf8.decode(raw).split('\n')) {
    final match = RegExp(r'(/[^\n]*\.so)(?: \(deleted\))?$').firstMatch(line);
    if (match == null) continue;
    final path = match.group(1)!;
    final name = Uri.file(path).pathSegments.last;
    if (!inventory.containsKey(name)) continue;
    final file = File(path);
    if (path != '$canonicalDirectory/$name' ||
        line.endsWith(' (deleted)') ||
        FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() != path) {
      throw const FormatException('Another Android runtime payload is mapped');
    }
    observed[name] = path;
  }
  if (!observed.containsKey('libLiteRtLm.so')) {
    throw const FormatException('Bound LiteRT core was not observed mapped');
  }
  // Validate every segment/path before deduplicating expensive content reads.
  // The set is local to this capture: later captures must recheck file bytes.
  for (final entry in observed.entries) {
    final file = File(entry.value);
    final lock = inventory[entry.key] as Map;
    diagnostic?.call('mapping_hash_started', entry.key);
    if (await file.length() != lock['bytes'] ||
        await (hashFile ?? s24LiteRtFileHash)(file) != lock['sha256']) {
      throw const FormatException(
        'S24 input bytes differ from admitted identity',
      );
    }
    diagnostic?.call('mapping_hash_completed', entry.key);
  }
  return {
    'capture': captureCompactS24LiteRtBytes(raw),
    'verified': observed.keys.toList()..sort(),
  };
}

/// Scoped stderr descriptor ownership; never restores while native work is live.
final class S24LiteRtStderr {
  S24LiteRtStderr._(this._saved);
  int? _saved;
  static final _process = DynamicLibrary.process();
  static final _close = _process
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final _dup2 = _process
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'dup2',
      );
  static final _flush = _process
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('fflush');

  factory S24LiteRtStderr.open(File output) {
    final dup = _process
        .lookupFunction<Int32 Function(Int32), int Function(int)>('dup');
    final creat = _process
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Uint32),
          int Function(Pointer<Utf8>, int)
        >('creat');
    final path = output.path.toNativeUtf8();
    _flush(nullptr);
    final saved = dup(2);
    try {
      if (saved < 0) throw StateError('Cannot save native stderr');
      final descriptor = creat(path, 384);
      if (descriptor < 0) throw StateError('Cannot open native stderr capture');
      try {
        if (_dup2(descriptor, 2) != 2) {
          throw StateError('Cannot capture native stderr');
        }
      } finally {
        _close(descriptor);
      }
      return S24LiteRtStderr._(saved);
    } on Object {
      if (saved >= 0) _close(saved);
      rethrow;
    } finally {
      malloc.free(path);
    }
  }

  void close() {
    final saved = _saved;
    if (saved == null) return;
    _flush(nullptr);
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

/// Validates S24's own child protocol after the caller journals its raw captures.
/// The shared Android helper's GGUF protocol result is deliberately not used.
List<Map<String, dynamic>> readS24LiteRtChildRecords(
  Map receipt,
  List<int> stdoutBytes,
  List<int> stderrBytes, {
  required String binding,
  required String caseId,
}) {
  if (receipt['binding'] != binding ||
      receipt['case_id'] != caseId ||
      receipt['pid'] is! int ||
      receipt['pid'] <= 0 ||
      receipt['exit_code'] != 0 ||
      receipt['timed_out'] != false ||
      receipt['capture_limit_exceeded'] != false ||
      receipt['capture_failed'] != false ||
      receipt['elapsed_ms'] is! int ||
      receipt['elapsed_ms'] < 0 ||
      receipt['elapsed_ms'] > 125000) {
    throw const FormatException('Owned native child did not complete safely');
  }
  for (final entry in {
    'stdout.jsonl': stdoutBytes,
    'stderr.log': stderrBytes,
  }.entries) {
    final lock = (receipt['files'] as Map)[entry.key] as Map;
    if (entry.value.length != lock['bytes'] ||
        sha256.convert(entry.value).toString() != lock['sha256']) {
      throw const FormatException('Changed owned-child capture');
    }
  }
  final text = utf8.decode(stdoutBytes);
  if (!text.endsWith('\n')) {
    throw const FormatException('Truncated S24 child log');
  }
  final lines = const LineSplitter().convert(text);
  if (lines.length < 2 || lines.length > 16) {
    throw const FormatException('Invalid S24 child record count');
  }
  final records = <Map<String, dynamic>>[];
  for (final line in lines) {
    if (utf8.encode(line).length > 64 * 1024) {
      throw const FormatException('Oversized S24 child record');
    }
    final value = jsonDecode(line);
    if (value is! Map<String, dynamic> ||
        value['schema'] != 1 ||
        value['binding'] != binding ||
        value['case_id'] != caseId ||
        value['pid'] != receipt['pid'] ||
        value['sequence'] != records.length ||
        !const [
          'started',
          'maps',
          'generation',
          'finished',
        ].contains(value['event'])) {
      throw const FormatException('S24 child protocol binding mismatch');
    }
    records.add(value);
  }
  if (records.first['event'] != 'started' ||
      records.last['event'] != 'finished' ||
      records.where((value) => value['event'] == 'started').length != 1 ||
      records.where((value) => value['event'] == 'finished').length != 1) {
    throw const FormatException('Incomplete S24 child lifetime');
  }
  return records;
}

List<int> readS24LiteRtHex(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-f]*$').hasMatch(value)) {
    throw const FormatException('Invalid S24 child hexadecimal bytes');
  }
  return [
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ];
}

/// Parses only an already-captured synchronous native response's text fields.
String readS24LiteRtNativeAnswer(List<int> bytes) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map ||
      value['content'] is! List ||
      (value['reasoning_content'] != null &&
          value['reasoning_content'] != '') ||
      (value['tool_calls'] is List &&
          (value['tool_calls'] as List).isNotEmpty)) {
    throw const FormatException(
      'Native control returned unsupported response content',
    );
  }
  final text = StringBuffer();
  for (final part in value['content'] as List) {
    if (part is! Map || part['type'] != 'text' || part['text'] is! String) {
      throw const FormatException('Native control returned non-text content');
    }
    text.write(part['text']);
  }
  return text.toString();
}

/// This observes initialization in an owned S24 load log, never per-request
/// execution. Callers separately bind the GPU request, runtime, model and PID,
/// and require completed positive C04 controls before accepting qualification.
bool s24LiteRtGpuInitialized(String log) =>
    s24LiteRtGpuInitializationBackend(log) != null;

/// Corrected public auto must retain GPU placement after its native control.
/// CPU fallback remains valid product behavior, but cannot qualify this route.
void requireS24LiteRtGpuObservation(
  Map<String, dynamic> value, {
  required String lifetimeId,
}) {
  final warnings = value['warnings'];
  final capture = value['native_stderr'];
  if (value['backend_name'] != 'LiteRT-LM gpu' ||
      value['reported_gpu_layers'] != ModelParams.maxGpuLayers ||
      value['native_finish'] != 'not_exposed_by_default_service' ||
      value['native_settlement'] != 'settled' ||
      value['input_tokens'] is! int ||
      value['input_tokens'] <= 0 ||
      value['output_tokens'] is! int ||
      value['output_tokens'] <= 0 ||
      value['public_process_pid'] is! int ||
      value['public_process_pid'] <= 0 ||
      value['mapped_core_verified'] != true ||
      warnings is! List ||
      warnings.any((line) => line is! String) ||
      warnings.any((line) => line.contains(s24LiteRtFallbackWarning)) ||
      capture is! Map ||
      capture['lifetime_id'] != lifetimeId ||
      capture['empty_at_load'] != true) {
    throw const FormatException(
      'Corrected public auto requires GPU placement, positive counters and fresh settled evidence without CPU fallback',
    );
  }
  final backend = s24LiteRtGpuInitializationBackend(
    utf8.decode(readS24LiteRtBytes(capture)),
  );
  if (backend == null ||
      value['native_gpu_initialization'] != true ||
      value['native_gpu_initialization_backend'] != backend) {
    throw const FormatException(
      'Corrected public auto lacks correlated native GPU initialization',
    );
  }
}

/// Identifies the initialized delegate without relabeling OpenCL as Vulkan.
String? s24LiteRtGpuInitializationBackend(String log) {
  if (containsLiteRtGpuFailureMarker(log) ||
      RegExp(
        r'delegate \(XNNPACK|delegate \(CPU|'
        r'\b(?:ERROR|FATAL)\b|^[EF][0-9]{4} |'
        r'(?:failed|failure|error)[^\n]*(?:GpuEnvironment|GPU delegate)|'
        r'(?:GpuEnvironment|GPU delegate)[^\n]*(?:failed|failure|error)',
        caseSensitive: false,
        multiLine: true,
      ).hasMatch(log)) {
    return null;
  }
  final hasVulkan =
      log.contains('Selected adapter:') ||
      log.contains('Created a WebGPU environment.');
  final hasOpenCl =
      log.contains('Created OpenCL device') ||
      log.contains('LITERT_CL') ||
      log.contains('Initializing OpenCL-based API');
  if (hasVulkan && hasOpenCl) return null;
  if (hasVulkan) {
    return !_s24LiteRtHasUnexpectedCpuDelegate(log) &&
            'Selected adapter:'.allMatches(log).length == 1 &&
            RegExp(
                  r'Selected adapter: [^\n]*Adreno[^\n]*750[^\n]*backend=Vulkan, adapterType=(?:Integrated GPU|Discrete GPU)',
                ).allMatches(log).length ==
                1 &&
            'Created a WebGPU environment.'.allMatches(log).length == 1 &&
            RegExp(
              r'Total [1-9][0-9]* external tensors are used for delegate inputs and outputs',
            ).hasMatch(log)
        ? 'Vulkan'
        : null;
  }
  if (!hasOpenCl ||
      log.contains('Created TensorFlow Lite XNNPACK delegate for CPU.') ||
      RegExp(
        r'(?:failed|failure|error)[^\n]*(?:OpenCL|GpuEnvironment|GPU delegate)|'
        r'(?:OpenCL|GpuEnvironment|GPU delegate)[^\n]*(?:failed|failure|error)',
        caseSensitive: false,
      ).hasMatch(log)) {
    return null;
  }

  // The two compiled C04 graphs each emit delegation, tensors, then API init.
  // Require the complete ordered sequence; registration and dlopen prove none
  // of this, and mixed/repeated loads cannot supply another load's evidence.
  final records = log
      .split('\n')
      .where(
        (line) =>
            line.contains('Created OpenCL device') ||
            line.contains('Created LiteRT GpuEnvironment.') ||
            line.contains('Replacing ') ||
            line.contains(
              'external tensors are used for delegate inputs and outputs',
            ) ||
            line.contains('Initializing OpenCL-based API'),
      )
      .toList();
  if (records.length != 8 ||
      !records[0].endsWith(
        'Created OpenCL device from provided device id and platform id.',
      ) ||
      !records[1].endsWith('Created LiteRT GpuEnvironment.')) {
    return null;
  }
  for (var graph = 0; graph < 2; graph++) {
    final offset = 2 + graph * 3;
    final delegated = RegExp(
      r'^VERBOSE: Replacing ([1-9][0-9]*) out of ([1-9][0-9]*) node\(s\) with delegate \(LITERT_CL\) node, yielding 1 partitions for subgraph ([01]) \((decode|prefill_[1-9][0-9]*)\)\.$',
    ).firstMatch(records[offset]);
    final tensors = RegExp(
      r'\] Total ([1-9][0-9]*) external tensors are used for delegate inputs and outputs$',
    ).firstMatch(records[offset + 1]);
    if (delegated == null ||
        delegated[1] != delegated[2] ||
        int.tryParse(delegated[1]!) == null ||
        delegated[3] != '$graph' ||
        (graph == 0
            ? delegated[4] != 'decode'
            : !delegated[4]!.startsWith('prefill_')) ||
        tensors == null ||
        int.tryParse(tensors[1]!) == null ||
        !records[offset + 2].endsWith(
          '] Initializing OpenCL-based API from serialized data.',
        )) {
      return null;
    }
  }
  return 'OpenCL';
}

// Vulkan multimodal bundles can compile a separate CPU embedder after their
// GPU graphs. Its adjacent single-signature compilation is not CPU fallback.
bool _s24LiteRtHasUnexpectedCpuDelegate(String log) {
  var singleSignature = false;
  var auxiliaryEmbedder = false;
  var previousCompiled = false;
  for (final line in log.split('\n')) {
    if (line.contains('Loaded: num_subgraphs=')) {
      singleSignature = line.endsWith(
        'Loaded: num_subgraphs=1, num_signatures=1',
      );
      auxiliaryEmbedder = false;
    }
    if (line.contains('signature=')) {
      auxiliaryEmbedder =
          singleSignature &&
          RegExp(
            r'\bsignature=(?:embedder|per_layer_embedder),',
          ).hasMatch(line);
    }
    if (line.contains('Created TensorFlow Lite XNNPACK delegate for CPU.') &&
        !(auxiliaryEmbedder && previousCompiled)) {
      return true;
    }
    previousCompiled = line.endsWith(
      'Flatbuffer model initialized directly from incoming litert model.',
    );
  }
  return false;
}
