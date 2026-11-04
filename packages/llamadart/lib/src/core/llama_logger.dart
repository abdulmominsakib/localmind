import 'models/config/log_level.dart';

/// A log record containing level, message, time, and optional error info.
class LlamaLogRecord {
  /// The log level of this record.
  final LlamaLogLevel level;

  /// The log message.
  final String message;

  /// The timestamp of the log record.
  final DateTime time;

  /// Optional error object associated with this record.
  final Object? error;

  /// Optional stack trace associated with this record.
  final StackTrace? stackTrace;

  /// Creates a new [LlamaLogRecord].
  LlamaLogRecord({
    required this.level,
    required this.message,
    required this.time,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    final sb = StringBuffer();
    sb.write('[${time.toIso8601String()}] ');
    sb.write('[${level.name.toUpperCase()}] ');
    sb.write(message);
    if (error != null) {
      sb.write('\nError: $error');
    }
    if (stackTrace != null) {
      sb.write('\n$stackTrace');
    }
    return sb.toString();
  }
}

/// Type definition for custom log handlers.
typedef LlamaLogHandler = void Function(LlamaLogRecord record);

/// A lightweight singleton logger for the llama_dart library.
///
/// Users can configure the log level and provide a custom log handler via
/// [LlamaEngine.configureLogging].
class LlamaLogger {
  static LlamaLogger? _instance;

  LlamaLogLevel _level = LlamaLogLevel.none;
  LlamaLogHandler? _handler;

  LlamaLogger._();

  /// Gets the singleton instance of [LlamaLogger].
  static LlamaLogger get instance => _instance ??= LlamaLogger._();

  /// Sets the current log level.
  ///
  /// Logs below this level will be ignored.
  void setLevel(LlamaLogLevel level) {
    _level = level;
  }

  /// Sets a custom log handler.
  ///
  /// If set to `null` and the log level is not [LlamaLogLevel.none],
  /// the logger will default to [print].
  void setHandler(LlamaLogHandler? handler) {
    _handler = handler;
  }

  /// Logs a record at [LlamaLogLevel.debug] level.
  void debug(String message) {
    _log(LlamaLogLevel.debug, message);
  }

  /// Logs a record at [LlamaLogLevel.info] level.
  void info(String message) {
    _log(LlamaLogLevel.info, message);
  }

  /// Logs a record at [LlamaLogLevel.warn] level.
  void warn(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LlamaLogLevel.warn, message, error, stackTrace);
  }

  /// Alias for [warn].
  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      warn(message, error, stackTrace);

  /// Logs a record at [LlamaLogLevel.error] level.
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LlamaLogLevel.error, message, error, stackTrace);
  }

  void _log(
    LlamaLogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (_level == LlamaLogLevel.none || level.index < _level.index) {
      return;
    }

    final record = LlamaLogRecord(
      level: level,
      message: message,
      time: DateTime.now(),
      error: error,
      stackTrace: stackTrace,
    );

    if (_handler != null) {
      _handler!(record);
    } else {
      // Default print behavior
      // ignore: avoid_print
      print(record.toString());
    }
  }
}
