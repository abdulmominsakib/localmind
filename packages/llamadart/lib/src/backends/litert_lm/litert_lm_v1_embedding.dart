part of 'litert_lm_v1_runtime.dart';

typedef _EmbeddingComputeN =
    Int Function(
      Pointer<Void>,
      Pointer<Pointer<Void>>,
      Size,
      Pointer<Void>,
      Pointer<Pointer<Void>>,
    );
typedef _EmbeddingComputeD =
    int Function(
      Pointer<Void>,
      Pointer<Pointer<Void>>,
      int,
      Pointer<Void>,
      Pointer<Pointer<Void>>,
    );
typedef _EmbeddingSizeN = Int Function(Pointer<Void>, Pointer<Size>);
typedef _EmbeddingSizeD = int Function(Pointer<Void>, Pointer<Size>);
typedef _EmbeddingValuesN =
    Int Function(Pointer<Void>, Pointer<Pointer<Float>>);
typedef _EmbeddingValuesD =
    int Function(Pointer<Void>, Pointer<Pointer<Float>>);

const _embeddingSymbols = [
  'litert_lm_embedding_engine_settings_create',
  'litert_lm_embedding_engine_settings_delete',
  'litert_lm_embedding_engine_settings_set_cache_dir',
  'litert_lm_embedding_engine_settings_set_max_input_length',
  'litert_lm_embedding_engine_settings_set_num_threads',
  'litert_lm_embedding_engine_create',
  'litert_lm_embedding_engine_delete',
  'litert_lm_embedding_options_create',
  'litert_lm_embedding_options_delete',
  'litert_lm_embedding_options_set_normalize',
  'litert_lm_embedding_options_set_input_overflow_strategy',
  'litert_lm_input_data_create',
  'litert_lm_input_data_delete',
  'litert_lm_embedding_engine_compute_embedding',
  'litert_lm_embedding_response_get_size',
  'litert_lm_embedding_response_get_values',
  'litert_lm_embedding_response_delete',
  LiteRtLmLastError.messageSymbol,
  LiteRtLmLastError.clearSymbol,
];

Map<String, int> _embeddingAddresses(DynamicLibrary library) {
  for (final symbol in _embeddingSymbols) {
    if (!library.providesSymbol(symbol)) {
      throw LlamaUnsupportedException(
        'LiteRT-LM C API 1.0 embeddings require native export $symbol.',
      );
    }
  }
  return Map.unmodifiable({
    for (final symbol in _embeddingSymbols)
      symbol: library.lookup<Void>(symbol).address,
  });
}

// Only integer addresses cross isolates; native owners stay in their admitted
// family until the blocking scope explicitly returns.
final class _V1EmbeddingApi {
  _V1EmbeddingApi(this.addresses, this.paths);
  final Map<String, int> addresses;
  final List<String> paths;
  late final clear = function<Void Function()>(
    LiteRtLmLastError.clearSymbol,
  ).asFunction<void Function()>();
  late final message = function<Pointer<Utf8> Function()>(
    LiteRtLmLastError.messageSymbol,
  ).asFunction<Pointer<Utf8> Function()>();
  Pointer<NativeFunction<T>> function<T extends Function>(String name) =>
      Pointer<NativeFunction<T>>.fromAddress(addresses[name]!);
  late final settingsCreate = function<_SettingsN>(
    _embeddingSymbols[0],
  ).asFunction<_SettingsD>();
  late final settingsDelete = function<_DeleteN>(
    _embeddingSymbols[1],
  ).asFunction<_DeleteD>();
  late final setCache = function<_SetStringN>(
    _embeddingSymbols[2],
  ).asFunction<_SetStringD>();
  late final setContext = function<_SetIntN>(
    _embeddingSymbols[3],
  ).asFunction<_SetIntD>();
  late final setThreads = function<_SetIntN>(
    _embeddingSymbols[4],
  ).asFunction<_SetIntD>();
  late final engineDelete = function<_DeleteN>(
    _embeddingSymbols[6],
  ).asFunction<_DeleteD>();
  late final optionsCreate = function<_CreateN>(
    _embeddingSymbols[7],
  ).asFunction<_CreateD>();
  late final optionsDelete = function<_DeleteN>(
    _embeddingSymbols[8],
  ).asFunction<_DeleteD>();
  late final setNormalize = function<_SetBoolN>(
    _embeddingSymbols[9],
  ).asFunction<_SetBoolD>();
  late final setOverflow = function<_SetIntN>(
    _embeddingSymbols[10],
  ).asFunction<_SetIntD>();
  late final inputCreate = function<_InputN>(
    _embeddingSymbols[11],
  ).asFunction<_InputD>();
  late final inputDelete = function<_DeleteN>(
    _embeddingSymbols[12],
  ).asFunction<_DeleteD>();
  late final compute = function<_EmbeddingComputeN>(
    _embeddingSymbols[13],
  ).asFunction<_EmbeddingComputeD>();
  late final responseSize = function<_EmbeddingSizeN>(
    _embeddingSymbols[14],
  ).asFunction<_EmbeddingSizeD>();
  late final responseValues = function<_EmbeddingValuesN>(
    _embeddingSymbols[15],
  ).asFunction<_EmbeddingValuesD>();
  late final responseDelete = function<_DeleteN>(
    _embeddingSymbols[16],
  ).asFunction<_DeleteD>();

  void check(int status, String operation) {
    if (status == 0) return;
    final pointer = message();
    final detail = liteRtLmNativeErrorDetail(
      code: status,
      message: pointer == nullptr
          ? ''
          : utf8.decode(
              pointer.cast<Uint8>().asTypedList(pointer.length),
              allowMalformed: true,
            ),
      paths: paths,
    );
    throw LlamaInferenceException(
      'LiteRT-LM C API 1.0 embedding $operation failed (status $status)'
      ': $detail',
    );
  }
}

typedef _EmbeddingComputeRequest = ({
  Map<String, int> addresses,
  List<String> paths,
  int engine,
  List<LiteRtLmEmbeddingPart> inputs,
  bool normalize,
});

List<double> _computeV1Embedding(_EmbeddingComputeRequest request) {
  final api = _V1EmbeddingApi(request.addresses, request.paths);
  final output = calloc<Pointer<Void>>();
  final inputArray = calloc<Pointer<Void>>(request.inputs.length);
  final inputs = <Pointer<Void>>[];
  Pointer<Void> options = nullptr;
  Pointer<Void> response = nullptr;
  try {
    api.clear();
    var status = api.optionsCreate(output);
    options = output.value;
    api.check(status, 'options_create');
    if (options == nullptr) {
      throw LlamaInferenceException(
        'Embedding options creation returned no owner.',
      );
    }
    api.clear();
    api.check(api.setNormalize(options, request.normalize), 'set_normalize');
    api.clear();
    api.check(api.setOverflow(options, 2), 'set_input_overflow_strategy');
    for (var i = 0; i < request.inputs.length; i++) {
      final part = request.inputs[i];
      final bytes = calloc<Uint8>(part.bytes.length + 1);
      try {
        bytes.asTypedList(part.bytes.length).setAll(0, part.bytes);
        output.value = nullptr;
        api.clear();
        status = api.inputCreate(
          part.type,
          bytes.cast(),
          part.bytes.length,
          output,
        );
        final input = output.value;
        if (input != nullptr) inputs.add(input);
        api.check(status, 'input_data_create');
        if (input == nullptr) {
          throw LlamaInferenceException(
            'Embedding input creation returned no owner.',
          );
        }
        inputArray[i] = input;
      } finally {
        calloc.free(bytes);
      }
    }
    output.value = nullptr;
    api.clear();
    status = api.compute(
      Pointer.fromAddress(request.engine),
      inputArray,
      request.inputs.length,
      options,
      output,
    );
    response = output.value;
    api.check(status, 'compute_embedding');
    if (response == nullptr) {
      throw LlamaInferenceException(
        'Embedding compute returned no response owner.',
      );
    }
    final size = calloc<Size>();
    final values = calloc<Pointer<Float>>();
    try {
      api.clear();
      api.check(api.responseSize(response, size), 'response_get_size');
      api.clear();
      api.check(api.responseValues(response, values), 'response_get_values');
      if (size.value == 0 || values.value == nullptr) {
        throw LlamaInferenceException('LiteRT-LM returned an empty embedding.');
      }
      final vector = List<double>.of(values.value.asTypedList(size.value));
      if (vector.any((value) => !value.isFinite)) {
        throw LlamaInferenceException(
          'LiteRT-LM returned a nonfinite embedding.',
        );
      }
      return vector;
    } finally {
      calloc.free(size);
      calloc.free(values);
    }
  } finally {
    if (response != nullptr) api.responseDelete(response);
    for (final input in inputs) {
      api.inputDelete(input);
    }
    if (options != nullptr) api.optionsDelete(options);
    calloc.free(inputArray);
    calloc.free(output);
  }
}

typedef _EmbeddingCreateRequest = ({
  Map<String, int> addresses,
  List<String> paths,
  String model,
  String cache,
  int context,
  int threads,
  LlamaEmbeddingCapabilities capabilities,
});

int _createV1Embedding(_EmbeddingCreateRequest request) {
  final api = _V1EmbeddingApi(request.addresses, request.paths);
  final strings = [
    request.model,
    'cpu',
    request.cache,
  ].map((value) => value.toNativeUtf8(allocator: calloc)).toList();
  final output = calloc<Pointer<Void>>();
  Pointer<Void> settings = nullptr;
  Pointer<Void> engine = nullptr;
  var returned = false;
  try {
    api.clear();
    var status = api.settingsCreate(
      strings[0],
      strings[1],
      request.capabilities.image ? strings[1] : nullptr,
      request.capabilities.audio ? strings[1] : nullptr,
      output,
    );
    settings = output.value;
    api.check(status, 'settings_create');
    if (settings == nullptr) {
      throw LlamaModelException(
        'Embedding settings creation returned no owner.',
      );
    }
    api.clear();
    api.check(api.setCache(settings, strings[2]), 'set_cache_dir');
    api.clear();
    api.check(
      api.setContext(settings, request.context),
      'set_max_input_length',
    );
    if (request.threads > 0) {
      api.clear();
      api.check(api.setThreads(settings, request.threads), 'set_num_threads');
    }
    output.value = nullptr;
    api.clear();
    status = api
        .function<_CreateFromN>(_embeddingSymbols[5])
        .asFunction<_CreateFromD>()(settings, output);
    engine = output.value;
    api.check(status, 'engine_create');
    if (engine == nullptr) {
      throw LlamaModelException('Embedding engine creation returned no owner.');
    }
    returned = true;
    return engine.address;
  } finally {
    if (!returned && engine != nullptr) api.engineDelete(engine);
    if (settings != nullptr) api.settingsDelete(settings);
    calloc.free(output);
    for (final string in strings) {
      calloc.free(string);
    }
  }
}

Future<LiteRtLmBlockingCallResult<int>> _dispatchEmbeddingCreate(
  _EmbeddingCreateRequest request,
) => runLiteRtLmBlockingCall(() => _createV1Embedding(request));

Future<LiteRtLmBlockingCallResult<List<double>>> _dispatchEmbeddingCompute(
  _EmbeddingComputeRequest request,
) => runLiteRtLmBlockingCall(() => _computeV1Embedding(request));

LlamaEmbeddingCapabilities _embeddingBundle(String path) {
  final file = File(path).openSync();
  try {
    final prefix = file.readSync(32);
    if (prefix.length != 32) {
      throw LlamaUnsupportedException(
        'LiteRT-LM embedding bundle header is unavailable.',
      );
    }
    final end = ByteData.sublistView(prefix).getUint64(24, Endian.little);
    if (end <= 32 || end > 16 * 1024 * 1024) {
      throw LlamaUnsupportedException(
        'LiteRT-LM embedding bundle header is unsupported.',
      );
    }
    final capabilities = liteRtLmEmbeddingBundleCapabilities(
      Uint8List.fromList([...prefix, ...file.readSync(end - 32)]),
    );
    if (!capabilities.text) {
      throw LlamaUnsupportedException(
        'LiteRT-LM embedding loading requires bundle text-encoder and embedder sections.',
      );
    }
    return capabilities;
  } finally {
    file.closeSync();
  }
}

final class _V1EmbeddingSession implements LiteRtLmEmbeddingRuntimeSession {
  _V1EmbeddingSession(
    this._library,
    this._addresses,
    this._paths,
    this._address,
    this.capabilities,
  );
  // Retain the loaded library for the entire native owner lifetime.
  final DynamicLibrary _library;
  final Map<String, int> _addresses;
  final List<String> _paths;
  int _address;
  LiteRtLmNativeSettlement settlement = LiteRtLmNativeSettlement.settled;
  @override
  final LlamaEmbeddingCapabilities capabilities;

  @override
  Future<List<double>> compute(
    List<LiteRtLmEmbeddingPart> input, {
    required bool normalize,
  }) async {
    if (_address == 0 || settlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'Embedding session is disposed or has unsettled native work.',
      );
    }
    if (input.isEmpty ||
        input.any(
          (part) =>
              part.bytes.isEmpty ||
              !(part.type == 0 ||
                  part.type == 1 && capabilities.image ||
                  part.type == 3 && capabilities.audio),
        )) {
      throw LlamaArgumentException(
        'Embedding input must contain supported, nonempty text, image or audio parts.',
      );
    }
    final owned = input
        .map(
          (part) =>
              LiteRtLmEmbeddingPart(part.type, Uint8List.fromList(part.bytes)),
        )
        .toList();
    settlement = LiteRtLmNativeSettlement.pending;
    late LiteRtLmBlockingCallResult<List<double>> result;
    try {
      result = await _dispatchEmbeddingCompute((
        addresses: _addresses,
        paths: _paths,
        engine: _address,
        inputs: owned,
        normalize: normalize,
      ));
    } catch (_) {
      settlement = LiteRtLmNativeSettlement.quarantined;
      rethrow;
    }
    settlement = LiteRtLmNativeSettlement.settled;
    if (result.error case final error?) {
      Error.throwWithStackTrace(error, result.stackTrace!);
    }
    return result.value!;
  }

  @override
  void dispose() {
    if (_address == 0) return;
    if (settlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'Cannot dispose unsettled embedding native work.',
      );
    }
    _library.lookupFunction<_DeleteN, _DeleteD>(
      'litert_lm_embedding_engine_delete',
    )(Pointer.fromAddress(_address));
    _address = 0;
  }
}
