import 'dart:async';

import '../exceptions.dart';
import '../models/chat/completion.dart';
import '../models/chat/completion_chunk.dart';

/// Terminal state of a text or chat generation task.
enum GenerationTaskState {
  /// The source completed successfully.
  completed,

  /// Cancellation stopped the operation.
  cancelled,

  /// Generation or cancellation cleanup failed.
  failed,
}

/// The outcome of a chat generation, including any partial reply.
class ChatGenerationCompletion {
  ChatGenerationCompletion._(_TaskCompletion<LlamaCompletion> completion)
    : state = completion.state,
      partialResult = completion.partial,
      error = completion.error,
      stackTrace = completion.stackTrace;

  /// How the operation finished.
  final GenerationTaskState state;

  /// Content, reasoning, tools and usage received before the operation ended.
  /// This can be partial when [state] is cancelled or failed.
  final LlamaCompletion partialResult;

  /// The complete reply, or null unless the operation completed successfully.
  LlamaCompletion? get result =>
      state == GenerationTaskState.completed ? partialResult : null;

  /// The failure, including cancellation cleanup failures.
  final LlamaException? error;

  /// Original failure stack, when [error] is present.
  final StackTrace? stackTrace;
}

/// The outcome of raw text generation, including any partial output.
class TextGenerationCompletion {
  TextGenerationCompletion._(_TaskCompletion<String> completion)
    : state = completion.state,
      partialResult = completion.partial,
      error = completion.error,
      stackTrace = completion.stackTrace;

  /// How the operation finished.
  final GenerationTaskState state;

  /// Output received before the operation ended, possibly partial.
  final String partialResult;

  /// The complete text, or null unless the operation completed successfully.
  String? get result =>
      state == GenerationTaskState.completed ? partialResult : null;

  /// The failure, including cancellation cleanup failures.
  final LlamaException? error;

  /// Original failure stack, when [error] is present.
  final StackTrace? stackTrace;
}

/// An eagerly running chat generation owned by its caller.
///
/// Created by `LlamaEngine.createTask`. The task borrows the engine and never
/// disposes it. Await [done] before reusing the engine after cancellation.
class ChatGenerationTask {
  ChatGenerationTask._(this._operation)
    : _done = _operation.done.then(ChatGenerationCompletion._);

  final _GenerationOperation<LlamaCompletionChunk, LlamaCompletion> _operation;
  final Future<ChatGenerationCompletion> _done;

  /// Single-subscription observation of the original completion chunks.
  ///
  /// Listening is optional. The task starts and collects its result eagerly;
  /// absent or paused listeners buffer events without pausing generation.
  /// Cancelling this observation does not cancel the task: use [cancel].
  /// Errors are reported by [done] and [result], never by this stream.
  Stream<LlamaCompletionChunk> get events => _operation.events;

  /// Settles after source cleanup, independently of event observation.
  /// This future never completes with an error.
  Future<ChatGenerationCompletion> get done => _done;

  /// The successful reply. Throws on failure or cancellation.
  /// Attach an error handler when reading this lazily created future.
  Future<LlamaCompletion> get result => _result;
  late final Future<LlamaCompletion> _result = _operation.result;

  /// Whether this task or the engine requested cancellation.
  bool get isCancellationRequested => _operation.isCancellationRequested;

  /// Requests cancellation of this task's source subscription, not other
  /// engine operations. Repeated calls and calls after completion are safe.
  /// Cleanup can fail; [done] then reports [GenerationTaskState.failed].
  void cancel() => _operation.cancel();
}

/// An eagerly running raw-text generation owned by its caller.
///
/// Created by `LlamaEngine.generateTask`. The task borrows the engine and
/// never disposes it. Await [done] before reusing it after cancellation.
class TextGenerationTask {
  TextGenerationTask._(this._operation)
    : _done = _operation.done.then(TextGenerationCompletion._);

  final _GenerationOperation<String, String> _operation;
  final Future<TextGenerationCompletion> _done;

  /// Single-subscription text deltas. Observation is optional and buffered;
  /// cancelling or pausing observation does not stop the operation.
  /// Errors are reported by [done] and [result], never by this stream.
  Stream<String> get events => _operation.events;

  /// Settles after cleanup even without an event listener; never errors.
  Future<TextGenerationCompletion> get done => _done;

  /// The successful text. Throws on failure or cancellation.
  /// Attach an error handler when reading this lazily created future.
  Future<String> get result => _result;
  late final Future<String> _result = _operation.result;

  /// Whether this task or the engine requested cancellation.
  bool get isCancellationRequested => _operation.isCancellationRequested;

  /// Requests cancellation of this source subscription. Repeated calls and
  /// calls after completion are safe. Await [done] for cleanup and errors.
  void cancel() => _operation.cancel();
}

/// Package-internal bridge from the engine's request stream to a chat task.
ChatGenerationTask startChatGenerationTask(
  Stream<LlamaCompletionChunk> source,
  bool Function() isCancelled,
) {
  final accumulator = LlamaCompletionAccumulator();
  final operation = _GenerationOperation(
    source,
    accumulator.add,
    accumulator.build,
    isCancelled,
  );
  final task = ChatGenerationTask._(operation);
  operation.start();
  return task;
}

/// Package-internal bridge from the engine's request stream to a text task.
TextGenerationTask startTextGenerationTask(
  Stream<String> source,
  bool Function() isCancelled,
) {
  final text = StringBuffer();
  final operation = _GenerationOperation<String, String>(
    source,
    text.write,
    text.toString,
    isCancelled,
  );
  final task = TextGenerationTask._(operation);
  operation.start();
  return task;
}

class _TaskCompletion<R> {
  const _TaskCompletion(this.state, this.partial, this.error, this.stackTrace);
  final GenerationTaskState state;
  final R partial;
  final LlamaException? error;
  final StackTrace? stackTrace;
}

// Owns one subscription. Keeping observation separate makes done independent
// of a UI's paused, cancelled or absent events listener.
class _GenerationOperation<E, R> {
  _GenerationOperation(
    this._source,
    this._add,
    this._snapshot,
    this._cancelled,
  );

  final Stream<E> _source;
  final void Function(E) _add;
  final R Function() _snapshot;
  final bool Function() _cancelled;
  final StreamController<E> _events = StreamController<E>();
  final Completer<_TaskCompletion<R>> _done = Completer<_TaskCompletion<R>>();
  StreamSubscription<E>? _subscription;
  Future<void>? _stopping;
  (Object, StackTrace)? _failure;
  bool _requested = false;
  bool _stopWhenAttached = false;
  bool _finished = false;
  bool _cancellationAtFinish = false;

  Stream<E> get events => _events.stream;
  Future<_TaskCompletion<R>> get done => _done.future;
  bool get isCancellationRequested =>
      _requested || (_finished ? _cancellationAtFinish : _cancelled());

  Future<R> get result => done.then((completion) {
    if (completion.state == GenerationTaskState.failed) {
      Error.throwWithStackTrace(completion.error!, completion.stackTrace!);
    }
    if (completion.state == GenerationTaskState.cancelled) {
      throw LlamaStateException('Text generation was cancelled.');
    }
    return completion.partial;
  });

  void start() {
    try {
      _subscription = _source.listen(
        (event) {
          if (_finished || _failure != null || isCancellationRequested) return;
          try {
            _add(event);
            _events.add(event);
          } catch (error, stack) {
            _onError(error, stack);
          }
        },
        onError: _onError,
        onDone: () {
          if (_stopping == null && !_stopWhenAttached) _finish();
        },
      );
      if (_stopWhenAttached) _stop();
    } catch (error, stack) {
      _failure ??= (error, stack);
      _finish();
    }
  }

  void cancel() {
    if (_requested || _finished) return;
    _requested = true;
    _stop();
  }

  void _onError(Object error, StackTrace stack) {
    if (_finished) return;
    _failure ??= (error, stack);
    _stop();
  }

  void _stop() {
    if (_stopping != null || _finished) return;
    final subscription = _subscription;
    if (subscription == null) {
      _stopWhenAttached = true;
      return;
    }
    // Publish before invoking a custom stream's synchronous cancellation hook.
    final stopping = Completer<void>();
    _stopping = stopping.future;
    stopping.complete(_cancelSubscription(subscription));
  }

  Future<void> _cancelSubscription(StreamSubscription<E> subscription) async {
    try {
      await subscription.cancel();
    } catch (error, stack) {
      _failure ??= (error, stack);
    }
    _finish();
  }

  void _finish() {
    if (_finished) return;
    _cancellationAtFinish = isCancellationRequested;
    _finished = true;
    final failure = _failure;
    final state = failure != null
        ? GenerationTaskState.failed
        : isCancellationRequested
        ? GenerationTaskState.cancelled
        : GenerationTaskState.completed;
    _done.complete(
      _TaskCompletion(
        state,
        _snapshot(),
        failure == null
            ? null
            : switch (failure.$1) {
                LlamaException error => error,
                final error => LlamaInferenceException(
                  'Text generation failed.',
                  error,
                ),
              },
        failure?.$2,
      ),
    );
    // close waits for a late event listener; terminal completion must not.
    unawaited(_events.close());
  }
}
