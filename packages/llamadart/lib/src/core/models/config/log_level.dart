/// Log level for the selected native inference backend.
enum LlamaLogLevel {
  /// No logging output.
  none,

  /// Detailed debug information.
  debug,

  /// General execution information.
  info,

  /// Warnings about potential issues.
  warn,

  /// Critical error messages only.
  error;

  /// Creates a [LlamaLogLevel] from an integer value.
  static LlamaLogLevel fromValue(int level) {
    switch (level) {
      case 0:
        return LlamaLogLevel.none;
      case 1:
        return LlamaLogLevel.debug;
      case 2:
        return LlamaLogLevel.info;
      case 3:
        return LlamaLogLevel.warn;
      case 4:
        return LlamaLogLevel.error;
      default:
        return LlamaLogLevel.none;
    }
  }
}
