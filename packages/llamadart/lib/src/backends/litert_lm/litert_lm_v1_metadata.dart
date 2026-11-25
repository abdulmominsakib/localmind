part of 'litert_lm_v1_runtime.dart';

typedef _ModelFileN = Int Function(Pointer<Utf8>, Pointer<Pointer<Void>>);
typedef _ModelFileD = int Function(Pointer<Utf8>, Pointer<Pointer<Void>>);
typedef _CapabilityN = Int Function(Pointer<Void>, Pointer<Bool>);
typedef _CapabilityD = int Function(Pointer<Void>, Pointer<Bool>);
typedef _ModalityN = Int Function(Pointer<Void>, Int, Pointer<Bool>);
typedef _ModalityD = int Function(Pointer<Void>, int, Pointer<Bool>);
typedef _RenderMessageN =
    Int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _RenderMessageD =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _MetricDoubleN = Int Function(Pointer<Void>, Pointer<Double>);
typedef _MetricDoubleD = int Function(Pointer<Void>, Pointer<Double>);
typedef _MetricCountAtN = Int Function(Pointer<Void>, Size, Pointer<Size>);
typedef _MetricCountAtD = int Function(Pointer<Void>, int, Pointer<Size>);
typedef _MetricRateAtN = Int Function(Pointer<Void>, Size, Pointer<Double>);
typedef _MetricRateAtD = int Function(Pointer<Void>, int, Pointer<Double>);

void _requireV1Symbols(DynamicLibrary library, List<String> symbols) {
  for (final symbol in symbols) {
    if (!library.providesSymbol(symbol)) {
      throw LlamaUnsupportedException(
        'C API 1.0 metadata/render/metrics requires native export $symbol.',
      );
    }
  }
}

/// Internal model-file declarations; these do not qualify executor support.
extension LiteRtLmV1ModelMetadata on LiteRtLmV1Runtime {
  /// Reads file metadata independently of the loaded engine. Thinking is only a
  /// declaration: it does not prove channel end tokens or admit thinking budgets.
  ({
    bool text,
    bool vision,
    bool audio,
    bool video,
    bool speculativeDecoding,
    bool declaredThinking,
    bool declaredFunctionCalling,
  })
  bundleCapabilities(String modelPath) {
    _requireLive();
    if (nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'Settle native work before inspecting metadata.',
      );
    }
    if (modelPath.isEmpty || modelPath.contains('\u0000')) {
      throw LlamaArgumentException('Model path must be nonempty without NUL.');
    }
    const symbols = [
      'litert_lm_loaded_file_create',
      'litert_lm_loaded_file_delete',
      'litert_lm_loaded_file_supports_input_modality',
      'litert_lm_loaded_file_has_speculative_decoding_support',
      'litert_lm_loaded_file_supports_thinking',
      'litert_lm_loaded_file_supports_function_calling',
    ];
    _requireV1Symbols(_library, symbols);
    final create = _library.lookupFunction<_ModelFileN, _ModelFileD>(
      symbols[0],
    );
    final delete = _library.lookupFunction<_DeleteN, _DeleteD>(symbols[1]);
    final modality = _library.lookupFunction<_ModalityN, _ModalityD>(
      symbols[2],
    );
    final input = modelPath.toNativeUtf8(allocator: calloc);
    final output = calloc<Pointer<Void>>();
    final supported = calloc<Bool>();
    final previousPaths = _diagnosticPaths;
    _diagnosticPaths = [...previousPaths, modelPath];
    Pointer<Void> file = nullptr;
    try {
      final status = create(input, output);
      file = output.value;
      _check(status, 'loaded_file_create');
      if (file == nullptr) {
        throw LlamaStateException('Model metadata returned no owned file.');
      }
      bool modalityAt(int value) {
        _check(modality(file, value, supported), symbols[2]);
        return supported.value;
      }

      bool flag(int index) {
        final get = _library.lookupFunction<_CapabilityN, _CapabilityD>(
          symbols[index],
        );
        _check(get(file, supported), symbols[index]);
        return supported.value;
      }

      return (
        text: modalityAt(0),
        vision: modalityAt(1),
        audio: modalityAt(2),
        video: modalityAt(3),
        speculativeDecoding: flag(3),
        declaredThinking: flag(4),
        declaredFunctionCalling: flag(5),
      );
    } finally {
      if (file != nullptr) delete(file);
      _diagnosticPaths = previousPaths;
      calloc.free(supported);
      calloc.free(output);
      calloc.free(input);
    }
  }
}

/// Internal, synchronous inspection of a settled conversation.
extension LiteRtLmV1ConversationMetadata on LiteRtLmV1Conversation {
  void _requireMetadataReady() {
    _runtime._requireLive();
    if (_handle == nullptr ||
        nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'C API 1.0 inspection requires an open, settled conversation.',
      );
    }
  }

  /// Renders the validated text/tool message subset without starting a turn.
  /// Copies the borrowed native string before another render can replace it.
  String renderMessageToString(Map<String, Object?> message) {
    _requireMetadataReady();
    LiteRtLmV1ConversationSettings._jsonValue(
      message,
      HashSet<Object>.identity(),
    );
    final encoded = jsonEncode(message);
    final snapshot = jsonDecode(encoded);
    LiteRtLmV1ConversationSettings._messages([snapshot]);
    _runtime._validateMediaMessages([snapshot]);
    const symbol = 'litert_lm_conversation_render_message_to_string';
    _requireV1Symbols(_runtime._library, const [symbol]);
    final render = _runtime._library
        .lookupFunction<_RenderMessageN, _RenderMessageD>(symbol);
    final input = encoded.toNativeUtf8(allocator: calloc);
    final output = calloc<Pointer<Utf8>>();
    try {
      _runtime._check(render(_handle, input, output), symbol);
      if (output.value == nullptr) {
        throw LlamaStateException(
          'Message rendering returned no borrowed text.',
        );
      }
      return output.value.toDartString();
    } finally {
      calloc.free(output);
      calloc.free(input);
    }
  }

  /// Sums all prefill/decode turns and uses the last throughput per phase,
  /// preserving the legacy client's aggregation. Native zero timing is retained.
  legacy.LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds}) {
    if (wallMilliseconds < 0) {
      throw LlamaArgumentException('Wall milliseconds must be nonnegative.');
    }
    final released = _releasedMetrics;
    if (_handle == nullptr && released != null) {
      _runtime._requireLive();
      return legacy.LiteRtLmRuntimeMetrics(
        inputTokens: released.inputTokens,
        outputTokens: released.outputTokens,
        prefillTokensPerSecond: released.prefillTokensPerSecond,
        decodeTokensPerSecond: released.decodeTokensPerSecond,
        timeToFirstTokenSeconds: released.timeToFirstTokenSeconds,
        initSeconds: released.initSeconds,
        wallMilliseconds: wallMilliseconds,
      );
    }
    return _readBenchmark(wallMilliseconds);
  }

  /// Reads the counters of a cancelled turn before its conversation is
  /// released; a failed read leaves them unavailable.
  void _captureMetricsBeforeRelease() {
    try {
      _releasedMetrics = _readBenchmark(0);
    } on Object {
      _releasedMetrics = null;
    }
  }

  legacy.LiteRtLmRuntimeMetrics _readBenchmark(int wallMilliseconds) {
    _requireMetadataReady();
    const prefix = 'litert_lm_benchmark_info_';
    const symbols = [
      'litert_lm_conversation_get_benchmark_info',
      '${prefix}delete',
      '${prefix}get_num_prefill_turns',
      '${prefix}get_num_decode_turns',
      '${prefix}get_prefill_token_count_at',
      '${prefix}get_decode_token_count_at',
      '${prefix}get_prefill_tokens_per_sec_at',
      '${prefix}get_decode_tokens_per_sec_at',
      '${prefix}get_time_to_first_token',
      '${prefix}get_total_init_time_in_second',
    ];
    final library = _runtime._library;
    _requireV1Symbols(library, symbols);
    final create = library.lookupFunction<_CreateFromN, _CreateFromD>(
      symbols[0],
    );
    final delete = library.lookupFunction<_DeleteN, _DeleteD>(symbols[1]);
    final output = calloc<Pointer<Void>>();
    final count = calloc<Size>();
    final value = calloc<Double>();
    Pointer<Void> info = nullptr;
    try {
      final status = create(_handle, output);
      info = output.value;
      _runtime._check(status, symbols[0]);
      if (info == nullptr) {
        throw LlamaStateException(
          'Benchmark reported success without an owner.',
        );
      }
      int turns(int index) {
        final get = library.lookupFunction<_TokenCountN, _TokenCountD>(
          symbols[index],
        );
        _runtime._check(get(info, count), symbols[index]);
        // A bounded snapshot prevents corrupt native lengths monopolizing the
        // isolate. It does not truncate a native history and report success.
        if (count.value < 0 || count.value > 1000000) {
          throw LlamaStateException(
            'Benchmark turn count exceeds safety bound.',
          );
        }
        return count.value;
      }

      int total(int index, int length) {
        final get = library.lookupFunction<_MetricCountAtN, _MetricCountAtD>(
          symbols[index],
        );
        var total = 0;
        for (var i = 0; i < length; i++) {
          _runtime._check(get(info, i, count), symbols[index]);
          // Dart native ints are signed; reject unsigned overflow before sums.
          if (count.value < 0 || count.value > 0x7fffffffffffffff - total) {
            throw LlamaStateException('Benchmark token count overflow.');
          }
          total += count.value;
        }
        return total;
      }

      double checkedValue() {
        if (!value.value.isFinite || value.value < 0) {
          throw LlamaStateException('Benchmark returned an invalid metric.');
        }
        return value.value;
      }

      double? rate(int index, int length) {
        if (length == 0) return null;
        final get = library.lookupFunction<_MetricRateAtN, _MetricRateAtD>(
          symbols[index],
        );
        _runtime._check(get(info, length - 1, value), symbols[index]);
        return checkedValue();
      }

      double timing(int index) {
        final get = library.lookupFunction<_MetricDoubleN, _MetricDoubleD>(
          symbols[index],
        );
        _runtime._check(get(info, value), symbols[index]);
        return checkedValue();
      }

      final prefill = turns(2);
      final decode = turns(3);
      return legacy.LiteRtLmRuntimeMetrics(
        inputTokens: total(4, prefill),
        outputTokens: total(5, decode),
        prefillTokensPerSecond: rate(6, prefill),
        decodeTokensPerSecond: rate(7, decode),
        timeToFirstTokenSeconds: timing(8),
        initSeconds: timing(9),
        wallMilliseconds: wallMilliseconds,
      );
    } finally {
      if (info != nullptr) delete(info);
      calloc.free(value);
      calloc.free(count);
      calloc.free(output);
    }
  }
}
