import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../core/models/config/log_level.dart';
import 'stable_diffusion_bindings.dart' as sd;
import 'stable_diffusion_calls.dart';

/// Where a reader of the runtime's log stands: the sequence of the last
/// message it read, and the runtime's count of dropped messages at that time.
typedef StableDiffusionLogPosition = ({int after, int dropped});

/// The messages one [drainStableDiffusionLog] read, where the next one
/// continues, and how many messages the runtime dropped since [position]'s
/// predecessor.
typedef StableDiffusionLogDrain = ({
  List<(LlamaLogLevel, String)> messages,
  StableDiffusionLogPosition position,
  int dropped,
});

/// Messages one [drainStableDiffusionLog] reads at most. The runtime keeps
/// 256 KiB of messages, about 2500 lines of 100 bytes, so one drain takes
/// what a load or a generation recorded; a thread that logs faster than it is
/// read cannot hold the reader.
const int stableDiffusionLogReadsPerDrain = 4096;

/// `sd_dart_last_error` keeps the 32 most recent errors of a call, cut to
/// 511 bytes each and joined by line breaks.
const int _lastErrorCapacity = 32 * 512;

/// Characters of the runtime's reason an exception message carries.
const int _reasonLimit = 1000;

/// The lowest `sd_log_level_t` the runtime records for [level]:
/// `SD_LOG_ERROR + 1`, which records nothing, for [LlamaLogLevel.none].
int stableDiffusionLogThreshold(LlamaLogLevel level) => switch (level) {
  LlamaLogLevel.none => sd.sd_log_level_t.SD_LOG_ERROR.value + 1,
  LlamaLogLevel.debug => sd.sd_log_level_t.SD_LOG_DEBUG.value,
  LlamaLogLevel.info => sd.sd_log_level_t.SD_LOG_INFO.value,
  LlamaLogLevel.warn => sd.sd_log_level_t.SD_LOG_WARN.value,
  LlamaLogLevel.error => sd.sd_log_level_t.SD_LOG_ERROR.value,
};

/// The level of a message the runtime recorded at `sd_log_level_t`
/// [runtimeLevel]. `SD_LOG_DEBUG` and `SD_LOG_VERBOSE` are both
/// [LlamaLogLevel.debug]; a value above `SD_LOG_ERROR` is an error.
LlamaLogLevel stableDiffusionLogLevel(int runtimeLevel) {
  if (runtimeLevel >= sd.sd_log_level_t.SD_LOG_ERROR.value) {
    return LlamaLogLevel.error;
  }
  if (runtimeLevel == sd.sd_log_level_t.SD_LOG_WARN.value) {
    return LlamaLogLevel.warn;
  }
  if (runtimeLevel == sd.sd_log_level_t.SD_LOG_INFO.value) {
    return LlamaLogLevel.info;
  }
  return LlamaLogLevel.debug;
}

/// Starts the recorder of [log] at [level]. Not synchronized with a load, a
/// generation or a device query on another thread, so it has to return before
/// one starts.
void recordStableDiffusionLog(
  StableDiffusionLogCalls log,
  LlamaLogLevel level,
) {
  log.enable();
  log.setLevel(stableDiffusionLogThreshold(level));
}

/// The text the runtime wrote to the [capacity] bytes at [text], up to its
/// terminator. The runtime cuts a text between two UTF-8 sequences; a byte
/// sequence that is malformed all the same decodes to U+FFFD.
String stableDiffusionText(Pointer<Char> text, int capacity) {
  final bytes = text.cast<Uint8>().asTypedList(capacity);
  final end = bytes.indexOf(0);
  return utf8.decode(
    end < 0 ? bytes : bytes.sublist(0, end),
    allowMalformed: true,
  );
}

/// Reads the messages of [log] after [position], oldest first, at most
/// [maxReads] of them.
///
/// Each read is a native call that can wait up to 100 ms for a thread that is
/// copying a message, so this runs in the worker isolate, never on a UI
/// isolate.
StableDiffusionLogDrain drainStableDiffusionLog(
  StableDiffusionLogCalls log,
  StableDiffusionLogPosition position, {
  int maxReads = stableDiffusionLogReadsPerDrain,
}) => using((arena) {
  final text = arena<Char>(sd.SD_DART_LOG_TEXT_SIZE);
  final level = arena<Int32>();
  final messages = <(LlamaLogLevel, String)>[];
  var after = position.after;
  for (var reads = 0; reads < maxReads; reads++) {
    final sequence = log.read(
      after,
      text,
      sd.SD_DART_LOG_TEXT_SIZE,
      level,
      nullptr,
    );
    if (sequence == 0) {
      break;
    }
    after = sequence;
    messages.add((
      stableDiffusionLogLevel(level.value),
      stableDiffusionText(text, sd.SD_DART_LOG_TEXT_SIZE),
    ));
  }
  final dropped = log.dropped();
  return (
    messages: messages,
    position: (after: after, dropped: dropped),
    // The count restarts with the process, and so does a reader's position.
    dropped: dropped > position.dropped ? dropped - position.dropped : 0,
  );
});

/// The errors the runtime logged during the calling thread's most recent
/// load or generation, one per line, or an empty string when it logged none
/// or [StableDiffusionLogCalls.enable] was not called before it.
///
/// Read it right after the call, with no asynchronous gap: the errors belong
/// to the thread, and an isolate stays on its thread only that long.
String readStableDiffusionLastError(StableDiffusionLogCalls log) =>
    using((arena) {
      final text = arena<Char>(_lastErrorCapacity);
      if (log.lastError(text, _lastErrorCapacity) == 0) {
        return '';
      }
      return stableDiffusionText(text, _lastErrorCapacity);
    });

/// Replaces the paths of [files], keyed by runtime role as in
/// `ImageGenerationSessionConfig.files`, and their directories in a text of
/// the runtime, so that errors and log records name image model files by
/// role, as the rest of the image API does, and never by path.
String Function(String text) stableDiffusionPathRedactor(
  Map<String, String> files,
) {
  final replacements = <String, String>{
    for (final MapEntry(key: role, value: path) in files.entries)
      if (path.isNotEmpty) path: '<${_roleName(role)} file>',
  };
  for (final path in files.values) {
    final separator = path.lastIndexOf(RegExp(r'[/\\]'));
    if (separator > 0) {
      replacements.putIfAbsent(
        path.substring(0, separator),
        () => '<model directory>',
      );
    }
  }
  // Longest first, so a path goes before the directory it starts with.
  final ordered = replacements.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return (text) {
    for (final path in ordered) {
      text = text.replaceAll(path, replacements[path]!);
    }
    return text;
  };
}

/// The runtime's reason for a failed call as one line an exception message
/// can carry: [lastError] with [redact] applied, control characters removed
/// and runs of spaces collapsed, its lines joined by `; ` and cut to 1000
/// characters. `null` when there is nothing left.
String? stableDiffusionFailureReason(
  String lastError,
  String Function(String text) redact,
) {
  final lines = [
    for (final line in redact(lastError).split('\n'))
      line.replaceAll(_blanks, ' ').trim(),
  ].where((line) => line.isNotEmpty);
  if (lines.isEmpty) {
    return null;
  }
  final reason = lines.join('; ');
  return reason.length <= _reasonLimit
      ? reason
      : '${reason.substring(0, _reasonLimit)}...';
}

String _roleName(String runtimeRole) =>
    runtimeRole == 'model' ? 'checkpoint' : runtimeRole;

final RegExp _blanks = RegExp(r'[\x00-\x20\x7f]+');
