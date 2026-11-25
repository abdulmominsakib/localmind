import 'dart:async';

import '../llama_logger.dart';
import '../models/chat/completion_chunk.dart';
import 'engine_observer.dart';

/// Runs the [LlamaOperationObserver]s of one engine operation in the zone
/// that called the engine, isolating the engine from their exceptions.
class EngineObservation {
  final Zone _zone;
  final List<LlamaOperationObserver> _observers;
  bool _ended = false;

  EngineObservation._(this._zone, this._observers);

  /// Calls [LlamaEngineObserver.onStart] of each of [observers] in [zone].
  factory EngineObservation.start(
    List<LlamaEngineObserver> observers,
    Zone zone,
    LlamaOperation operation,
  ) => EngineObservation._(zone, <LlamaOperationObserver>[
    for (final observer in observers)
      ?_guard<LlamaOperationObserver?>(zone, () => observer.onStart(operation)),
  ]);

  /// Reports [chunk] to every operation observer.
  void chunk(LlamaCompletionChunk chunk) {
    for (final observer in _observers) {
      _guard(_zone, () => observer.onChunk(chunk));
    }
  }

  /// Reports [text] to every operation observer.
  void text(String text) {
    for (final observer in _observers) {
      _guard(_zone, () => observer.onText(text));
    }
  }

  /// Reports [result] to every operation observer, once.
  void end(LlamaOperationResult result) {
    if (_ended) return;
    _ended = true;
    for (final observer in _observers) {
      _guard(_zone, () => observer.onEnd(result));
    }
  }

  static T? _guard<T>(Zone zone, T Function() callback) {
    try {
      return zone.run(callback);
    } catch (error, stackTrace) {
      LlamaLogger.instance.warning(
        'A LlamaEngineObserver threw; the engine ignored it.',
        error,
        stackTrace,
      );
      return null;
    }
  }
}

/// Returns [source], observed from its listen to its end by [observers].
///
/// [operation] starts in [zone] when the returned stream is listened to.
/// [onItem] sees each event before the listener does. [result] builds the
/// result of a stream that completes, and [cancelResult] that of a stream
/// whose subscription is cancelled.
Stream<T> observeStream<T>(
  Stream<T> source, {
  required List<LlamaEngineObserver> observers,
  required Zone zone,
  required LlamaOperation operation,
  required void Function(EngineObservation observation, T item) onItem,
  required LlamaOperationResult Function() result,
  required LlamaOperationResult Function() cancelResult,
}) {
  StreamSubscription<T>? subscription;
  EngineObservation? observation;
  late final StreamController<T> controller;
  controller = StreamController<T>(
    sync: true,
    onListen: () {
      final started = EngineObservation.start(observers, zone, operation);
      observation = started;
      subscription = source.listen(
        (item) {
          onItem(started, item);
          controller.add(item);
        },
        onError: (Object error, StackTrace stackTrace) {
          started.end(
            LlamaOperationResult(error: error, stackTrace: stackTrace),
          );
          controller.addError(error, stackTrace);
        },
        onDone: () {
          started.end(result());
          controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      observation?.end(cancelResult());
      return subscription?.cancel();
    },
  );
  return controller.stream;
}

/// Returns the result of [body], observed by [observers] from this call to
/// its completion.
Future<T> observeFuture<T>(
  Future<T> Function() body, {
  required List<LlamaEngineObserver> observers,
  required LlamaOperation operation,
}) async {
  final observation = EngineObservation.start(
    observers,
    Zone.current,
    operation,
  );
  try {
    final value = await body();
    observation.end(const LlamaOperationResult());
    return value;
  } catch (error, stackTrace) {
    observation.end(LlamaOperationResult(error: error, stackTrace: stackTrace));
    rethrow;
  }
}
