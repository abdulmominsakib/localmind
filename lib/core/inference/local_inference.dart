import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One owner across generation and model transitions. Model changes wait for
/// native cleanup, and incoming HTTP requests never join the wait queue.
class InferenceCoordinator {
  Completer<void>? _active;
  int _waiting = 0;
  final _retainedSessions = <Future<void> Function()>{};

  InferenceLease? tryAcquire() {
    if (_active != null || _waiting != 0) return null;
    return _acquire();
  }

  InferenceLease _acquire() {
    final active = _active = Completer<void>();
    return InferenceLease(() {
      _active = null;
      active.complete();
    });
  }

  Future<T> transition<T>(Future<T> Function() operation) async {
    _waiting++;
    while (_active != null) {
      await _active!.future;
    }
    _waiting--;
    final lease = _acquire();
    try {
      await clearRetainedSessions();
      return await operation();
    } finally {
      lease.release();
    }
  }

  void retain(Future<void> Function() close) => _retainedSessions.add(close);
  void forget(Future<void> Function() close) => _retainedSessions.remove(close);

  Future<void> clearRetainedSessions() async {
    for (final close in _retainedSessions.toList()) {
      await close();
    }
  }
}

class InferenceLease {
  InferenceLease(this._release);
  void Function()? _release;

  void release() {
    final release = _release;
    _release = null;
    release?.call();
  }
}

final inferenceCoordinatorProvider = Provider<InferenceCoordinator>(
  (ref) => InferenceCoordinator(),
);

final localInferenceProvider = Provider<LocalInference?>((ref) => null);

final localInferenceModelProvider = Provider<LocalInferenceModel?>(
  (ref) => ref.watch(localInferenceProvider)?.model,
);

abstract interface class LocalInference {
  LocalInferenceModel? get model;
  Stream<InferenceEvent> generate(
    InferenceRequest request,
    InferenceCancellation cancellation,
  );
}

class LocalInferenceModel {
  const LocalInferenceModel(
    this.id, {
    required this.supportsTools,
    required this.supportsSampling,
  });
  final String id;
  final bool supportsTools;
  final bool supportsSampling;
}

enum InferenceRole { system, user, assistant, tool }

class InferenceMessage {
  const InferenceMessage(
    this.role,
    this.text, {
    this.calls = const [],
    this.toolCallId,
  });
  final InferenceRole role;
  final String text;
  final List<InferenceToolCall> calls;
  final String? toolCallId;
}

class InferenceTool {
  const InferenceTool(this.name, this.description, this.parameters);
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
}

class InferenceToolCall {
  const InferenceToolCall(this.name, this.arguments, {this.id});
  final String name;
  final String arguments;
  final String? id;
}

class InferenceRequest {
  const InferenceRequest({
    required this.model,
    required this.messages,
    required this.tools,
    this.temperature,
    this.topP,
    this.maxTokens,
  });
  final String model;
  final List<InferenceMessage> messages;
  final List<InferenceTool> tools;
  final double? temperature;
  final double? topP;
  final int? maxTokens;
}

sealed class InferenceEvent {
  const InferenceEvent();
}

class InferenceText extends InferenceEvent {
  const InferenceText(this.text);
  final String text;
}

class InferenceCall extends InferenceEvent {
  const InferenceCall(this.call);
  final InferenceToolCall call;
}

class InferenceFinished extends InferenceEvent {
  const InferenceFinished({this.length = false});
  final bool length;
}

/// Native adapters race the pending stream read against this signal and
/// await their native stream's cancellation before returning.
class InferenceCancellation {
  final _cancelled = Completer<bool>();
  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!isCancelled) _cancelled.complete(false);
  }

  Future<bool> moveNext<T>(StreamIterator<T> iterator) => isCancelled
      ? Future.value(false)
      : Future.any([iterator.moveNext(), _cancelled.future]);
}
