import 'dart:isolate';

/// An explicit return from a synchronous native operation and its cleanup.
///
/// The operation must return only after native work has stopped. Its caller
/// still owns the engine family; an isolate transport error provides no result
/// and therefore no proof that this family is safe to destroy.
final class LiteRtLmBlockingCallResult<T> {
  const LiteRtLmBlockingCallResult._(this.value, this.error, this.stackTrace);

  /// The copied result, when the operation succeeded.
  final T? value;

  /// A failure whose synchronous operation and cleanup already unwound.
  final Object? error;

  /// Original operation stack, preserved across the isolate boundary.
  final StackTrace? stackTrace;
}

/// Runs a synchronous native scope, distinguishing its return from isolate loss.
Future<LiteRtLmBlockingCallResult<T>> runLiteRtLmBlockingCall<T>(
  T Function() operation,
) => Isolate.run(() {
  try {
    return LiteRtLmBlockingCallResult._(operation(), null, null);
  } catch (error, stackTrace) {
    return LiteRtLmBlockingCallResult._(null, error, stackTrace);
  }
});
