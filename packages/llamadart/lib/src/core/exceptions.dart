/// Base class for all Llama-related exceptions.
abstract class LlamaException implements Exception {
  /// A human-readable error message.
  final String message;

  /// Optional detail about the error.
  final dynamic details;

  /// Creates a new [LlamaException].
  LlamaException(this.message, [this.details]);

  @override
  String toString() =>
      'LlamaException: $message${details != null ? ' ($details)' : ''}';
}

/// Exception thrown when a model fails to load.
class LlamaModelException extends LlamaException {
  /// Creates a new [LlamaModelException].
  LlamaModelException(super.message, [super.details]);
}

/// Exception thrown when a context operation fails.
class LlamaContextException extends LlamaException {
  /// Creates a new [LlamaContextException].
  LlamaContextException(super.message, [super.details]);
}

/// Exception thrown during text generation or tokenization.
class LlamaInferenceException extends LlamaException {
  /// Creates a new [LlamaInferenceException].
  LlamaInferenceException(super.message, [super.details]);
}

/// Exception thrown when an operation is not supported on the current platform.
class LlamaUnsupportedException extends LlamaException {
  /// Creates a new [LlamaUnsupportedException].
  LlamaUnsupportedException(super.message);
}

/// Exception thrown when the engine is in an invalid state.
class LlamaStateException extends LlamaException {
  /// Creates a new [LlamaStateException].
  LlamaStateException(super.message, [super.details]);
}
