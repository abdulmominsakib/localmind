import 'dart:ffi';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_blocking_call.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';

/// A client/engine identity captured before one actual service turn.
final class ThinkingTurnOwner {
  ThinkingTurnOwner._(this.client, this.engineEpoch);
  final LiteRtLmRuntimeClientContract client;
  final int engineEpoch;
}

/// Successful engine creation identifies the service client, never its status.
final class ThinkingOwnerTracker {
  ThinkingTurnOwner? _current;
  int _epoch = 0;

  void engineCreated(LiteRtLmRuntimeClientContract client) {
    _current = ThinkingTurnOwner._(client, ++_epoch);
  }

  ThinkingTurnOwner capture() =>
      _current ?? (throw StateError('No initialized service engine owner.'));

  ({int engineEpoch, String? finish, String settlement}) observe(
    ThinkingTurnOwner turn,
  ) {
    if (!identical(_current, turn)) {
      throw StateError(
        'Service engine owner changed during the observed turn.',
      );
    }
    return (
      engineEpoch: turn.engineEpoch,
      finish: turn.client.lastFinishReason?.name,
      settlement: turn.client.nativeSettlement.name,
    );
  }
}

/// Delegates the unchanged native constructor and records only its real owner.
LiteRtLmV1RuntimeClient createTrackedThinkingClient(
  DynamicLibrary library,
  ThinkingOwnerTracker owners,
) {
  late final LiteRtLmV1RuntimeClient client;
  client = LiteRtLmV1RuntimeClient(
    library,
    createRunner: (request) async {
      final completion = await runLiteRtLmV1Create(request);
      final result = completion.value;
      if (completion.error == null &&
          result != null &&
          result.status == 0 &&
          result.ownerAddress > 0) {
        owners.engineCreated(client);
      }
      return completion;
    },
  );
  return client;
}
