import 'dart:async';

import 'package:llamadart/llamadart.dart' as llama;

final Object operationUsageKey = Object();

// Request-local state follows the Genkit action through the model queue.
// Chat usage comes from completion chunks; raw text streams need an observer.
class OperationUsage {
  llama.LlamaGenerationUsage? usage;
  String? finishReason;
  double queueMs = 0;
  double initializationMs = 0;
}

final class UsageObserver extends llama.LlamaEngineObserver {
  const UsageObserver();

  @override
  llama.LlamaOperationObserver? onStart(llama.LlamaOperation operation) {
    final capture = Zone.current[operationUsageKey] as OperationUsage?;
    if (capture == null || operation is! llama.LlamaTextCompletionOperation) {
      return null;
    }
    return _UsageOperation(capture);
  }
}

final class _UsageOperation extends llama.LlamaOperationObserver {
  _UsageOperation(this.capture);
  final OperationUsage capture;
  @override
  void onEnd(llama.LlamaOperationResult result) {
    capture.usage = result.usage;
    capture.finishReason = result.finishReason;
  }
}
