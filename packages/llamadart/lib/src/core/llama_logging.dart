import 'dart:async';

import '../backends/backend.dart';
import 'llama_logger.dart';
import 'models/config/log_level.dart';

/// Library-wide logging configuration for Dart-side records and native
/// runtime output.
///
/// Every engine shares one configuration, so the last [configure] call
/// decides the levels and handler regardless of call order or engine.
abstract final class LlamaLogging {
  /// The level Dart-side records must reach to be handled.
  static LlamaLogLevel get level => LlamaLogger.instance.level;

  /// The level passed to the native llama.cpp and LiteRT-LM runtimes.
  static LlamaLogLevel get nativeLevel => _nativeLevel;

  /// Sets the Dart-side [level], the native runtime [nativeLevel] and the
  /// [handler] that receives Dart-side records.
  ///
  /// [nativeLevel] defaults to [level]. With no [handler], records at or
  /// above [level] are printed. Both levels default to [LlamaLogLevel.none].
  ///
  /// The new levels apply immediately on this isolate and to every engine
  /// created later, and are sent to the worker isolates and native runtimes
  /// of live engines. The returned future completes when every live engine
  /// has taken them, or after at most one second. An engine that fails or
  /// does not answer in time logs a warning; a busy worker takes the levels
  /// when its current operation finishes, a new worker starts with them, and
  /// every model load applies the native level again.
  ///
  /// Native llama.cpp and LiteRT-LM backends log from a worker isolate that
  /// forwards records at or above [level] to this isolate, where [handler]
  /// receives them with the error as its `toString` text and the stack trace
  /// rebuilt from text. An error thrown by [handler] on a forwarded record is
  /// printed, not thrown. Some native output, such as the LiteRT-LM WebGPU
  /// accelerator's, ignores [nativeLevel]; see
  /// https://llamadart.leehack.com/docs/configuration/logging.
  ///
  /// The stable_diffusion runtime of `ImageGenerationEngine` records its
  /// messages from the stricter of the two levels and hands them to
  /// [handler] after each load and generation. It takes the levels when a
  /// model loads, so a later call applies to the next load.
  static Future<void> configure({
    LlamaLogLevel level = LlamaLogLevel.none,
    LlamaLogLevel? nativeLevel,
    LlamaLogHandler? handler,
  }) {
    LlamaLogger.instance.setHandler(handler);
    return applyLogLevels(dart: level, native: nativeLevel ?? level);
  }
}

LlamaLogLevel _nativeLevel = LlamaLogLevel.none;

// A worker answers only between operations, so a long generation or a wedged
// worker must not block `configure`.
const Duration _pushTimeout = Duration(seconds: 1);

// Weak so an engine dropped without `dispose()` can still be collected.
final List<WeakReference<LlamaBackend>> _liveBackends =
    <WeakReference<LlamaBackend>>[];

/// Keeps [backend] in sync with later [LlamaLogging.configure] calls.
void registerLoggingBackend(LlamaBackend backend) {
  _liveBackends.add(WeakReference<LlamaBackend>(backend));
}

/// Stops syncing [backend] with [LlamaLogging.configure].
void unregisterLoggingBackend(LlamaBackend backend) {
  _liveBackends.removeWhere((reference) {
    final target = reference.target;
    return target == null || identical(target, backend);
  });
}

/// Sets the Dart and native levels, keeping the current handler, and pushes
/// them to every registered backend.
Future<void> applyLogLevels({
  required LlamaLogLevel dart,
  required LlamaLogLevel native,
}) async {
  LlamaLogger.instance.setLevel(dart);
  _nativeLevel = native;
  _liveBackends.removeWhere((reference) => reference.target == null);
  final backends = <LlamaBackend>[
    for (final reference in _liveBackends) ?reference.target,
  ];
  await Future.wait(<Future<void>>[
    for (final backend in backends) _pushLogLevels(backend, dart, native),
  ]);
}

Future<void> _pushLogLevels(
  LlamaBackend backend,
  LlamaLogLevel dart,
  LlamaLogLevel native,
) async {
  Future<void> push() async {
    try {
      if (backend is BackendDartLogLevel) {
        await (backend as BackendDartLogLevel).setDartLogLevel(dart);
      }
      await backend.setLogLevel(native);
    } catch (error, stackTrace) {
      LlamaLogger.instance.warn(
        'Could not apply log levels to a running backend; a new worker starts '
        'with them and the next model load applies the native level.',
        error,
        stackTrace,
      );
    }
  }

  await push().timeout(
    _pushTimeout,
    onTimeout: () => LlamaLogger.instance.warn(
      'A running backend did not take the new log levels within '
      '${_pushTimeout.inSeconds} s; it takes them when its current operation '
      'finishes.',
    ),
  );
}
