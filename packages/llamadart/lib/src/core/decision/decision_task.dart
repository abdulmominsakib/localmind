part of 'decision_engine.dart';

/// Terminal state of a cooperative decision task.
enum DecisionCompletionState {
  /// The backend returned and the answer was decoded successfully.
  completed,

  /// Cancellation stopped preflight or discarded the finished answer.
  cancelled,

  /// Validation, tokenization or backend execution failed.
  failed,
}

/// The typed outcome of a [DecisionTask], without a throwing future.
final class DecisionCompletion<R extends Object> {
  const DecisionCompletion._({
    required this.state,
    this.result,
    this.error,
    this.stackTrace,
  });

  /// How the operation finished.
  final DecisionCompletionState state;

  /// The answer, present only when [state] is completed.
  final R? result;

  /// The failure, present only when [state] is failed.
  final LlamaException? error;

  /// Original failure stack, when [error] is present.
  final StackTrace? stackTrace;
}

/// An eagerly running decision operation with cooperative cancellation.
///
/// Created by [DecisionEngine.systemOneTask] or
/// [DecisionEngine.systemOneBatchTask]. It owns only its operation, never the
/// engine or its borrowed encoder. Cancellation stops before the next
/// tokenization or backend dispatch. Once dispatched, the backend runs to
/// completion and its answer is discarded. No native interruption is claimed.
final class DecisionTask<R extends Object> {
  DecisionTask._();

  final StreamController<R> _events = StreamController<R>();
  final Completer<DecisionCompletion<R>> _done =
      Completer<DecisionCompletion<R>>();
  bool _cancelled = false;

  /// One final answer on success, with no synthetic progress or partial batch.
  ///
  /// Single-subscription and buffered until observed. Pausing, cancelling or
  /// never adding a listener does not stop the operation or delay [done]. The
  /// stream never emits errors; cancelled and failed tasks emit no answer.
  Stream<R> get events => _events.stream;

  /// Stable, never-erroring completion after the underlying work has stopped.
  Future<DecisionCompletion<R>> get done => _done.future;

  /// The answer, or a typed failure/cancellation exception.
  ///
  /// Created lazily. Await it or attach an error handler as soon as you read
  /// it, to avoid an unhandled error from a stored future.
  Future<R> get result => _result;

  late final Future<R> _result = done.then((DecisionCompletion<R> completion) {
    switch (completion.state) {
      case DecisionCompletionState.completed:
        return completion.result!;
      case DecisionCompletionState.cancelled:
        throw LlamaStateException('Decision task was cancelled.');
      case DecisionCompletionState.failed:
        Error.throwWithStackTrace(completion.error!, completion.stackTrace!);
    }
  });

  /// Whether this task or its engine lifecycle requested cancellation.
  bool get isCancellationRequested => _cancelled;

  /// Requests cancellation only for this operation.
  ///
  /// Idempotent, and a no-op after completion. [done] still waits for any
  /// pending tokenizer or backend call. Errors from that work remain failures.
  /// It never calls global generation cancellation or disposes an engine.
  void cancel() {
    if (_done.isCompleted) return;
    _cancelled = true;
  }

  void _checkpoint() {
    if (_cancelled) throw const _DecisionTaskCancelled();
  }

  Future<void> _execute(Future<R> Function() operation) async {
    late final DecisionCompletion<R> completion;
    try {
      final value = await operation();
      completion = DecisionCompletion<R>._(
        state: DecisionCompletionState.completed,
        result: value,
      );
    } on _DecisionTaskCancelled {
      completion = DecisionCompletion<R>._(
        state: DecisionCompletionState.cancelled,
      );
    } catch (error, stackTrace) {
      completion = DecisionCompletion<R>._(
        state: DecisionCompletionState.failed,
        error: error is LlamaException
            ? error
            : LlamaDecisionException('Decision task failed.', error),
        stackTrace: stackTrace,
      );
    }
    // Publish terminal state before an answer observer can reenter cancel.
    _done.complete(completion);
    if (completion.state == DecisionCompletionState.completed) {
      _events.add(completion.result!);
    }
    // Closing an unobserved buffered stream can wait for its first listener.
    unawaited(_events.close());
  }
}

final class _DecisionTaskCancelled implements Exception {
  const _DecisionTaskCancelled();
}
