import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class Log {
  late Logger _logger;
  static const lineLength = 80;
  static LogOutput? _additionalOutput;

  Log._internal() {
    _initLogger();
  }

  void _initLogger() {
    if (kDebugMode) {
      _logger = Logger(
        output: _additionalOutput != null
            ? MultiOutput([ConsoleOutput(), _additionalOutput!])
            : null,
        printer: PrettyPrinter(
          methodCount: 2,
          errorMethodCount: 8,
          lineLength: lineLength,
          colors: true,
          printEmojis: true,
          dateTimeFormat: DateTimeFormat.onlyTime,
        ),
      );
    } else {
      _logger = Logger(
        printer: PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 0,
          lineLength: 0,
          colors: false,
          printEmojis: false,
          dateTimeFormat: DateTimeFormat.onlyTime,
        ),
        level: Level.off,
      );
    }
  }

  static void attachOutput(LogOutput output) {
    _additionalOutput = output;
    _singleton._initLogger();
  }

  static final Log _singleton = Log._internal();

  static void fatal({required Object error, required StackTrace stackTrace}) =>
      _singleton._logger.f('Fatal', error: error, stackTrace: stackTrace);

  static void debug(String message) => _singleton._logger.d(message);

  static void info(String message) => _singleton._logger.i(message);

  static void error(String message) => _singleton._logger.e(message);

  static void warning(String message) => _singleton._logger.w(message);
}
