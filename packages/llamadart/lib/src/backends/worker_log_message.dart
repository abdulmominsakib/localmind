import 'dart:isolate';

import '../core/llama_logger.dart';
import '../core/models/config/log_level.dart';

/// A log record forwarded from a backend worker isolate to the main isolate.
///
/// The worker sends it on the log port supplied in its handshake; [emit]
/// re-logs it through the main isolate's [LlamaLogger.instance] at [level].
class WorkerLogMessage {
  /// The level the record was logged at in the worker.
  final LlamaLogLevel level;

  /// The log message.
  final String message;

  /// The record's error rendered with `toString`, if it had one.
  final String? error;

  /// The record's stack trace rendered with `toString`, if it had one.
  final String? stackTrace;

  /// Creates a forwarded log record.
  WorkerLogMessage(this.level, this.message, {this.error, this.stackTrace});

  /// Logs this record through [LlamaLogger.instance] at [level].
  ///
  /// [stackTrace] is passed as a [StackTrace] rebuilt from its text. An error
  /// thrown by the handler is printed instead of propagated, because no
  /// caller awaits a forwarded record.
  void emit() {
    final logger = LlamaLogger.instance;
    final trace = stackTrace == null
        ? null
        : StackTrace.fromString(stackTrace!);
    try {
      switch (level) {
        case LlamaLogLevel.none:
          return;
        case LlamaLogLevel.debug:
          logger.debug(message);
        case LlamaLogLevel.info:
          logger.info(message);
        case LlamaLogLevel.warn:
          logger.warn(message, error, trace);
        case LlamaLogLevel.error:
          logger.error(message, error, trace);
      }
    } catch (handlerError, handlerTrace) {
      print(
        'llamadart: log handler threw on a forwarded ${level.name} record: '
        '$handlerError\n$handlerTrace',
      );
    }
  }
}

/// Maximum number of [LlamaLogLevel.debug] records one worker forwards.
///
/// Records above debug are never capped. The last forwarded debug record
/// announces the cap.
const int workerForwardedDebugRecordCap = 1000;

/// Routes the current isolate's [LlamaLogger.instance] to [logPort].
///
/// Sets the logger level to [level], so records below it are dropped before
/// any message is sent, and replaces its handler with one that sends a
/// [WorkerLogMessage] per record, capped at [workerForwardedDebugRecordCap]
/// debug records.
void installWorkerLogForwarding(SendPort logPort, LlamaLogLevel level) {
  var forwardedDebugRecords = 0;
  final logger = LlamaLogger.instance;
  logger.setLevel(level);
  logger.setHandler((record) {
    if (record.level == LlamaLogLevel.debug) {
      if (forwardedDebugRecords >= workerForwardedDebugRecordCap) {
        return;
      }
      forwardedDebugRecords += 1;
      if (forwardedDebugRecords == workerForwardedDebugRecordCap) {
        logPort.send(
          WorkerLogMessage(
            LlamaLogLevel.debug,
            '${record.message}\nReached the cap of '
            '$workerForwardedDebugRecordCap forwarded debug records; further '
            'debug records from this worker are dropped.',
          ),
        );
        return;
      }
    }
    logPort.send(
      WorkerLogMessage(
        record.level,
        record.message,
        error: record.error?.toString(),
        stackTrace: record.stackTrace?.toString(),
      ),
    );
  });
}
