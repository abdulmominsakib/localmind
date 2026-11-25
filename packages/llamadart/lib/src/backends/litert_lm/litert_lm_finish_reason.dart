/// Why a native LiteRT-LM conversation stream ended, as the litert-lm-native
/// `stream_proxy_get_finish_reason` export reports it.
enum LiteRtLmFinishReason {
  /// Not reported: an older runtime, a blocking send, or a turn the runtime
  /// could not classify.
  unknown,

  /// A stop token or a native stop sequence ended the turn.
  stop,

  /// The turn reached its output-token budget (`maxTokens`).
  length,

  /// The prompt and output filled the context window.
  contextExhausted,

  /// The turn was cancelled.
  cancelled,

  /// The turn ended with an error.
  error;

  /// The reason for the export's wire [value]; values this version does not
  /// know map to [unknown].
  static LiteRtLmFinishReason fromWire(int value) => switch (value) {
    1 => stop,
    2 => length,
    3 => contextExhausted,
    4 => cancelled,
    5 => error,
    _ => unknown,
  };
}

/// Whether a runtime whose `stream_proxy_finish_reason_abi_version` returned
/// [abiVersion] reports finish reasons that llamadart can read.
///
/// [abiVersion] is null when the runtime lacks the export. Only version 1 is
/// understood; any other value is treated as not reporting. This is public
/// only for unit tests.
bool liteRtLmFinishReasonAbiSupported(int? abiVersion) => abiVersion == 1;
