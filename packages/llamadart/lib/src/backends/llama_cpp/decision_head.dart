import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../core/decision/decision_decoder.dart';
import '../../core/decision/decision_question.dart';
import '../../core/exceptions.dart';
import '../backend.dart';
import '../isolate_shutdown_releases.dart';
import 'bindings.dart';
import 'exit_teardown_api.dart';
import 'ggml_graph_api.dart';
import 'native_barrier_api.dart';
import 'safetensors.dart';

const double _layerNormEpsilon = 1e-5;

/// The shape-checked head tensors of a safetensors file.
///
/// The type embedding and the act MLP are read into memory as F32. The other
/// tensors stay in the file until [DecisionHeadRuntime.create] uploads them,
/// so the file must stay open until then.
final class DecisionHeadWeights {
  DecisionHeadWeights._({
    required this.hiddenSize,
    required this.heads,
    required this.layers,
    required this.ffnSize,
    required this.actHiddenSize,
    required this.actClasses,
    required SafetensorsFile file,
    required Float32List typeEmbedding,
    required _ActWeights act,
  }) : _file = file,
       _typeEmbedding = typeEmbedding,
       _act = act;

  /// Checks the head tensors of [file] for an encoder of width [hiddenSize]
  /// and reads the type embedding and act MLP.
  ///
  /// [layers] is the head's transformer layer count, the config's
  /// [DecisionHeadConfig.headLayers]. Tensors outside the head, such as
  /// `encoder.*` and `temperature`, are ignored. `type_emb.weight` is the
  /// first shape checked, and its error names the encoder's hidden size.
  /// Throws [ArgumentError] when [layers] is below 1, and
  /// [LlamaModelException] when [hiddenSize] is not positive or not
  /// divisible by [heads], when the file has tensors for more head layers
  /// than [layers], when a head tensor is missing (naming it) or mis-shaped
  /// (naming it with the expected and found shapes), and when
  /// [SafetensorsFile.readFloat32] cannot read one of the tensors read here.
  static DecisionHeadWeights read(
    SafetensorsFile file, {
    required int hiddenSize,
    required int layers,
  }) {
    if (layers < 1) {
      throw ArgumentError.value(layers, 'layers', 'must be at least 1');
    }
    final d = hiddenSize;
    if (d < 1) {
      throw LlamaModelException(
        'Decision head hidden size must be positive, got $d.',
      );
    }
    final heads = math.max(1, d ~/ 64);
    if (d % heads != 0) {
      throw LlamaModelException(
        'Decision head hidden size $d is not divisible by its $heads '
        'attention heads.',
      );
    }
    final extraLayer = 'head.layers.$layers.';
    if (file.tensors.keys.any((name) => name.startsWith(extraLayer))) {
      throw LlamaModelException(
        'Decision head file "${file.path}" has tensors for more than the '
        '$layers layers its config "head_layers" names.',
      );
    }

    final shapes = _ShapeCheck(file);
    shapes.expect(
      'type_emb.weight',
      [3, d],
      advice:
          ' The encoder has hidden size $d; use the head trained for this '
          'encoder.',
    );
    final ffn = shapes.rows('head.layers.0.linear1.weight', d, 'ffn');
    for (var i = 0; i < layers; i++) {
      final p = 'head.layers.$i';
      shapes
        ..expect('$p.self_attn.in_proj_weight', [3 * d, d])
        ..expect('$p.self_attn.in_proj_bias', [3 * d])
        ..expect('$p.self_attn.out_proj.weight', [d, d])
        ..expect('$p.self_attn.out_proj.bias', [d])
        ..expect('$p.linear1.weight', [ffn, d])
        ..expect('$p.linear1.bias', [ffn])
        ..expect('$p.linear2.weight', [d, ffn])
        ..expect('$p.linear2.bias', [d])
        ..expect('$p.norm1.weight', [d])
        ..expect('$p.norm1.bias', [d])
        ..expect('$p.norm2.weight', [d])
        ..expect('$p.norm2.bias', [d]);
    }
    shapes
      ..expect('scorer.0.weight', [d])
      ..expect('scorer.0.bias', [d])
      ..expect('scorer.1.weight', [d, d])
      ..expect('scorer.1.bias', [d])
      ..expect('scorer.3.weight', [1, d])
      ..expect('scorer.3.bias', [1]);
    final actHidden = shapes.rows('act_head.0.weight', d + 4, 'act hidden');
    shapes.expect('act_head.0.bias', [actHidden]);
    final actClasses = shapes.rows('act_head.2.weight', actHidden, 'classes');
    shapes.expect('act_head.2.bias', [actClasses]);

    return DecisionHeadWeights._(
      hiddenSize: d,
      heads: heads,
      layers: layers,
      ffnSize: ffn,
      actHiddenSize: actHidden,
      actClasses: actClasses,
      file: file,
      typeEmbedding: file.readFloat32('type_emb.weight'),
      act: _ActWeights(file.readFloat32),
    );
  }

  /// Width of the encoder output and of the head layers.
  final int hiddenSize;

  /// Attention heads per layer, `max(1, hiddenSize ~/ 64)`.
  final int heads;

  /// Transformer layers, the config's `head_layers`.
  final int layers;

  /// Feed-forward width of each layer.
  final int ffnSize;

  /// Hidden width of the act MLP.
  final int actHiddenSize;

  /// Number of act-head outputs.
  final int actClasses;

  final SafetensorsFile _file;
  final Float32List _typeEmbedding;
  final _ActWeights _act;
}

final class _ShapeCheck {
  _ShapeCheck(this.file);

  final SafetensorsFile file;

  List<int> _shape(String name) {
    final tensor = file.tensors[name];
    if (tensor == null) {
      throw LlamaModelException(
        'Decision head file "${file.path}" has no tensor "$name".',
      );
    }
    return tensor.shape;
  }

  void expect(String name, List<int> expected, {String advice = ''}) {
    final found = _shape(name);
    if (found.length != expected.length ||
        Iterable<int>.generate(
          found.length,
        ).any((i) => found[i] != expected[i])) {
      throw LlamaModelException(
        'Decision head tensor "$name" in "${file.path}" has shape $found; '
        'expected $expected.$advice',
      );
    }
  }

  int rows(String name, int columns, String rowName) {
    final found = _shape(name);
    if (found.length != 2 || found[0] < 1 || found[1] != columns) {
      throw LlamaModelException(
        'Decision head tensor "$name" in "${file.path}" has shape $found; '
        'expected [$rowName, $columns] with $rowName >= 1.',
      );
    }
    return found[0];
  }
}

final class _ActWeights {
  _ActWeights(Float32List Function(String) read)
    : hiddenWeight = read('act_head.0.weight'),
      hiddenBias = read('act_head.0.bias'),
      outWeight = read('act_head.2.weight'),
      outBias = read('act_head.2.bias');

  final Float32List hiddenWeight;
  final Float32List hiddenBias;
  final Float32List outWeight;
  final Float32List outBias;
}

final class _LayerTensors {
  late final Pointer<ggml_tensor> norm1Weight, norm1Bias;
  late final Pointer<ggml_tensor> queryWeight, queryBias;
  late final Pointer<ggml_tensor> keyWeight, keyBias;
  late final Pointer<ggml_tensor> valueWeight, valueBias;
  late final Pointer<ggml_tensor> outWeight, outBias;
  late final Pointer<ggml_tensor> norm2Weight, norm2Bias;
  late final Pointer<ggml_tensor> linear1Weight, linear1Bias;
  late final Pointer<ggml_tensor> linear2Weight, linear2Bias;
}

/// The decision head as a ggml graph whose weights live on one device; the
/// act MLP runs in Dart.
final class DecisionHeadRuntime {
  DecisionHeadRuntime._(
    this._api,
    this._exitTeardown,
    this._failures,
    DecisionHeadWeights weights,
  ) : _hiddenSize = weights.hiddenSize,
      _heads = weights.heads,
      _graphSize = 64 + 64 * weights.layers,
      _typeEmbedding = weights._typeEmbedding,
      _act = weights._act;

  /// Uploads [weights] to a backend buffer and creates a scheduler.
  ///
  /// The tensors [DecisionHeadWeights.read] left in the file are read from it
  /// here, one at a time through a staging buffer. With [device] null or the
  /// CPU device the head runs on the CPU only. Otherwise its weights live on
  /// [device], and the scheduler lists [device] first and the CPU backend
  /// last. [cpuThreads] sets the CPU backend's thread count when that backend
  /// exposes `ggml_backend_set_n_threads`; [opOffload] is passed to
  /// `ggml_backend_sched_new`. [api] is the ggml function table the head
  /// calls, [GgmlGraphApi.current] by default. With [exitTeardown], the
  /// backends, the weights buffer and the scheduler are tracked for exit
  /// teardown, and the graph is computed as a call it waits for. With the
  /// exception barrier of [failures], the calls that reach a backend go
  /// through its wrappers and report a C++ exception as a typed error. What
  /// was created before a failure is freed. Throws [ArgumentError] when
  /// [cpuThreads] is below 1,
  /// [LlamaUnsupportedException] when the native library does not export a
  /// ggml function the head calls, [LlamaModelException] when a backend, the
  /// weights buffer or the scheduler cannot be created or filled, and
  /// [LlamaStateException] when the file of [weights] has been closed.
  static DecisionHeadRuntime create(
    DecisionHeadWeights weights, {
    ggml_backend_dev_t? device,
    required int cpuThreads,
    required bool opOffload,
    GgmlGraphApi? api,
    ExitTeardownApi? exitTeardown,
    NativeCallFailures? failures,
  }) {
    if (cpuThreads < 1) {
      throw ArgumentError.value(cpuThreads, 'cpuThreads', 'must be at least 1');
    }
    final runtime = DecisionHeadRuntime._(
      api ?? GgmlGraphApi.current,
      exitTeardown,
      failures,
      weights,
    );
    try {
      withGgmlGraphSymbols(
        () => runtime._initialize(weights, device, cpuThreads, opOffload),
      );
    } catch (_) {
      runtime.dispose();
      rethrow;
    }
    return runtime;
  }

  final GgmlGraphApi _api;
  final ExitTeardownApi? _exitTeardown;
  final NativeCallFailures? _failures;
  String? _failedCall;
  final int _hiddenSize;
  final int _heads;
  final int _graphSize;
  final Float32List _typeEmbedding;
  final _ActWeights _act;
  final List<_LayerTensors> _layers = [];
  late final Pointer<ggml_tensor> _scorerNormWeight, _scorerNormBias;
  late final Pointer<ggml_tensor> _scorerHiddenWeight, _scorerHiddenBias;
  late final Pointer<ggml_tensor> _scorerOutWeight, _scorerOutBias;

  ggml_backend_t _cpuBackend = nullptr;
  ggml_backend_t _deviceBackend = nullptr;
  Pointer<ggml_context> _weightsContext = nullptr;
  ggml_backend_buffer_t _weightsBuffer = nullptr;
  ggml_backend_sched_t _sched = nullptr;
  final Set<int> _exitTracked = {};
  String _deviceName = '';
  bool _disposed = false;

  /// Name of the backend holding the head's weights, such as `CPU` or `MTL0`.
  String get deviceName => _deviceName;

  void _initialize(
    DecisionHeadWeights weights,
    ggml_backend_dev_t? device,
    int cpuThreads,
    bool opOffload,
  ) {
    final api = _api;
    final frees = ggmlFreeAddresses;
    final cpuDevice = api.devByType(
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
    );
    if (cpuDevice == nullptr) {
      throw LlamaModelException(
        'No ggml CPU device is registered; initialize the llama.cpp backend '
        'before loading a decision head.',
      );
    }
    _cpuBackend = _devInit(cpuDevice);
    if (_cpuBackend == nullptr) {
      throw LlamaModelException(
        'Could not start the ggml CPU backend for the decision head.',
      );
    }
    _own(ShutdownStage.backend, frees.backendFree, _cpuBackend);
    _setCpuThreads(cpuThreads);
    if (device != null && device != nullptr && device != cpuDevice) {
      _deviceBackend = _devInit(device);
      _own(ShutdownStage.backend, frees.backendFree, _deviceBackend);
      if (_deviceBackend == nullptr) {
        throw LlamaModelException(
          'Could not start the ggml backend of the model device for the '
          'decision head.',
        );
      }
    }
    final primary = _deviceBackend != nullptr ? _deviceBackend : _cpuBackend;
    _deviceName = api.backendName(primary).cast<Utf8>().toDartString();

    final uploads = <(String, List<Pointer<ggml_tensor>>, int)>[];
    final tensorCount = 16 * weights.layers + 6;
    _weightsContext = _newContext(api.tensorOverhead() * tensorCount);
    List<Pointer<ggml_tensor>> load(
      String name,
      int parts,
      int columns, [
      int? rows,
    ]) {
      final f32 = ggml_type.GGML_TYPE_F32.value;
      final tensors = [
        for (var i = 0; i < parts; i++)
          rows == null
              ? api.newTensor1d(_weightsContext, f32, columns)
              : api.newTensor2d(_weightsContext, f32, columns, rows),
      ];
      uploads.add((name, tensors, columns * (rows ?? 1)));
      return tensors;
    }

    Pointer<ggml_tensor> vector(String name, int size) =>
        load(name, 1, size).single;
    Pointer<ggml_tensor> matrix(String name, int columns, int rows) =>
        load(name, 1, columns, rows).single;

    final d = _hiddenSize;
    final ffn = weights.ffnSize;
    for (var i = 0; i < weights.layers; i++) {
      final p = 'head.layers.$i';
      final [queryWeight, keyWeight, valueWeight] = load(
        '$p.self_attn.in_proj_weight',
        3,
        d,
        d,
      );
      final [queryBias, keyBias, valueBias] = load(
        '$p.self_attn.in_proj_bias',
        3,
        d,
      );
      _layers.add(
        _LayerTensors()
          ..norm1Weight = vector('$p.norm1.weight', d)
          ..norm1Bias = vector('$p.norm1.bias', d)
          ..queryWeight = queryWeight
          ..keyWeight = keyWeight
          ..valueWeight = valueWeight
          ..queryBias = queryBias
          ..keyBias = keyBias
          ..valueBias = valueBias
          ..outWeight = matrix('$p.self_attn.out_proj.weight', d, d)
          ..outBias = vector('$p.self_attn.out_proj.bias', d)
          ..norm2Weight = vector('$p.norm2.weight', d)
          ..norm2Bias = vector('$p.norm2.bias', d)
          ..linear1Weight = matrix('$p.linear1.weight', d, ffn)
          ..linear1Bias = vector('$p.linear1.bias', ffn)
          ..linear2Weight = matrix('$p.linear2.weight', ffn, d)
          ..linear2Bias = vector('$p.linear2.bias', d),
      );
    }
    _scorerNormWeight = vector('scorer.0.weight', d);
    _scorerNormBias = vector('scorer.0.bias', d);
    _scorerHiddenWeight = matrix('scorer.1.weight', d, d);
    _scorerHiddenBias = vector('scorer.1.bias', d);
    _scorerOutWeight = matrix('scorer.3.weight', d, 1);
    _scorerOutBias = vector('scorer.3.bias', 1);

    final barrier = _failures?.barrier;
    _weightsBuffer = barrier == null
        ? api.allocCtxTensors(_weightsContext, primary)
        : barrier.ggmlBackendAllocCtxTensors(_weightsContext, primary);
    if (_weightsBuffer == nullptr) {
      _throwIfCaught('ggml_backend_alloc_ctx_tensors', LlamaModelException.new);
    }
    _own(ShutdownStage.modelUser, frees.bufferFree, _weightsBuffer);
    if (_weightsBuffer == nullptr) {
      throw LlamaModelException(
        'Could not allocate decision head weights on $_deviceName.',
      );
    }
    api.bufferSetUsage(
      _weightsBuffer,
      ggml_backend_buffer_usage.GGML_BACKEND_BUFFER_USAGE_WEIGHTS.value,
    );
    final largest = uploads.fold(
      0,
      (count, e) => math.max(count, e.$2.length * e.$3),
    );
    final staging = malloc<Float>(largest);
    try {
      for (final (name, tensors, size) in uploads) {
        weights._file.readFloat32Into(
          name,
          staging.asTypedList(tensors.length * size),
        );
        for (final (index, tensor) in tensors.indexed) {
          _tensorSet(
            tensor,
            (staging + index * size).cast(),
            size * 4,
            LlamaModelException.new,
          );
        }
      }
    } finally {
      malloc.free(staging);
    }

    final backends = calloc<ggml_backend_t>(2);
    try {
      var count = 0;
      if (_deviceBackend != nullptr) backends[count++] = _deviceBackend;
      backends[count++] = _cpuBackend;
      _sched = api.schedNew(
        backends,
        nullptr,
        count,
        math.max(2048, _graphSize),
        false,
        opOffload,
      );
    } finally {
      calloc.free(backends);
    }
    _own(ShutdownStage.scheduler, frees.schedFree, _sched);
    if (_sched == nullptr) {
      throw LlamaModelException(
        'Could not create the ggml scheduler for the decision head on '
        '$_deviceName.',
      );
    }
  }

  ggml_backend_t _devInit(ggml_backend_dev_t device) {
    final barrier = _failures?.barrier;
    if (barrier == null) return _api.devInit(device, nullptr);
    final backend = barrier.ggmlBackendDevInit(device, nullptr);
    if (backend == nullptr) {
      _throwIfCaught('ggml_backend_dev_init', LlamaModelException.new);
    }
    return backend;
  }

  void _tensorSet(
    Pointer<ggml_tensor> tensor,
    Pointer<Void> data,
    int size,
    NativeCallError error,
  ) {
    final barrier = _failures?.barrier;
    if (barrier == null) {
      _api.tensorSet(tensor, data, 0, size);
    } else if (!barrier.ggmlBackendTensorSet(tensor, data, 0, size)) {
      _throwIfCaught('ggml_backend_tensor_set', error);
    }
  }

  void _tensorGet(Pointer<ggml_tensor> tensor, Pointer<Void> data, int size) {
    final barrier = _failures?.barrier;
    if (barrier == null) {
      _api.tensorGet(tensor, data, 0, size);
    } else if (!barrier.ggmlBackendTensorGet(tensor, data, 0, size)) {
      _throwIfCaught('ggml_backend_tensor_get', LlamaInferenceException.new);
    }
  }

  // The backends, the buffer and the scheduler of a failed call may only be
  // freed, so the head stops running.
  void _throwIfCaught(String call, NativeCallError error) {
    try {
      _failures?.throwIfCaught(call, error);
    } on LlamaException {
      _failedCall = call;
      rethrow;
    }
  }

  void _setCpuThreads(int threads) {
    final api = _api;
    final registry = api.devBackendReg(api.backendGetDevice(_cpuBackend));
    final name = 'ggml_backend_set_n_threads'.toNativeUtf8();
    try {
      final setThreads = api.regGetProcAddress(registry, name.cast());
      if (setThreads == nullptr) return;
      setThreads
          .cast<NativeFunction<Void Function(ggml_backend_t, Int)>>()
          .asFunction<void Function(ggml_backend_t, int)>()(
        _cpuBackend,
        threads,
      );
    } finally {
      malloc.free(name);
    }
  }

  Pointer<ggml_context> _newContext(int bytes) {
    final params = calloc<ggml_init_params>();
    try {
      params.ref
        ..mem_size = bytes
        ..mem_buffer = nullptr
        ..no_alloc = true;
      return _api.init(params.ref);
    } finally {
      calloc.free(params);
    }
  }

  /// Runs the head on the encoder output of one sequence.
  ///
  /// [hidden] is the encoder's last hidden state, row-major
  /// `[tokenCount, hiddenSize]`. [questionType] selects the `type_emb` row
  /// by its index, and [markers] holds at least one option position in
  /// `[0, tokenCount)`. Returns one raw logit per marker and the act-head
  /// logits. Throws [ArgumentError] for inputs outside these bounds,
  /// [LlamaInferenceException] when the graph cannot be allocated or computed,
  /// [LlamaUnsupportedException] when the native library does not export a
  /// ggml function the head calls, and [LlamaStateException] after [dispose]
  /// or after a run that failed with a llama.cpp exception.
  BackendDecisionOutput run(
    Float32List hidden,
    int tokenCount,
    DecisionQuestionType questionType,
    Int32List markers,
  ) {
    if (_disposed) {
      throw LlamaStateException('The decision head has been freed.');
    }
    final failedCall = _failedCall;
    if (failedCall != null) {
      throw LlamaStateException(
        'The decision head is unusable after a llama.cpp exception in '
        '$failedCall. Load it again.',
      );
    }
    if (tokenCount < 1 || hidden.length != tokenCount * _hiddenSize) {
      throw ArgumentError(
        'Decision head input has ${hidden.length} values for $tokenCount '
        'tokens of width $_hiddenSize.',
      );
    }
    if (markers.isEmpty || markers.any((m) => m < 0 || m >= tokenCount)) {
      throw ArgumentError.value(
        markers,
        'markers',
        'must hold at least one position in [0, $tokenCount)',
      );
    }
    final (logits, cls) = withGgmlGraphSymbols(
      () => _computeGraph(hidden, tokenCount, questionType.index, markers),
    );
    return BackendDecisionOutput(
      logits: logits,
      actLogits: _actLogits(cls, logits),
    );
  }

  (Float32List, Float32List) _computeGraph(
    Float32List hidden,
    int tokenCount,
    int questionType,
    Int32List markers,
  ) {
    final api = _api;
    final d = _hiddenSize;
    final n = tokenCount;
    final headSize = d ~/ _heads;
    final rowCount = markers.length + 1;
    final g = _newContext(
      api.tensorOverhead() * _graphSize +
          api.graphOverheadCustom(_graphSize, false),
    );
    try {
      Pointer<ggml_tensor> norm(
        Pointer<ggml_tensor> x,
        Pointer<ggml_tensor> weight,
        Pointer<ggml_tensor> bias,
      ) => api.add(
        g,
        api.mul(g, api.norm(g, x, _layerNormEpsilon), weight),
        bias,
      );
      Pointer<ggml_tensor> linear(
        Pointer<ggml_tensor> x,
        Pointer<ggml_tensor> weight,
        Pointer<ggml_tensor> bias,
      ) => api.add(g, api.mulMat(g, weight, x), bias);
      Pointer<ggml_tensor> splitHeads(Pointer<ggml_tensor> x, int rows) => api
          .permute(g, api.reshape3d(g, x, headSize, _heads, rows), 0, 2, 1, 3);

      final f32 = ggml_type.GGML_TYPE_F32.value;
      final hiddenInput = api.newTensor2d(g, f32, d, n);
      final typeInput = api.newTensor1d(g, f32, d);
      final rowsInput = api.newTensor1d(
        g,
        ggml_type.GGML_TYPE_I32.value,
        rowCount,
      );
      for (final input in [hiddenInput, typeInput, rowsInput]) {
        api.setInput(input);
      }

      var x = api.add(g, hiddenInput, typeInput);
      for (final (index, layer) in _layers.indexed) {
        final a = norm(x, layer.norm1Weight, layer.norm1Bias);
        var queries = a;
        var queryRows = n;
        if (index == _layers.length - 1) {
          queries = api.getRows(g, a, rowsInput);
          x = api.getRows(g, x, rowsInput);
          queryRows = rowCount;
        }
        final q = splitHeads(
          linear(queries, layer.queryWeight, layer.queryBias),
          queryRows,
        );
        final k = splitHeads(linear(a, layer.keyWeight, layer.keyBias), n);
        final v = splitHeads(linear(a, layer.valueWeight, layer.valueBias), n);
        final scores = api.softMaxExt(
          g,
          api.mulMat(g, k, q),
          nullptr,
          1 / math.sqrt(headSize),
          0,
        );
        final attended = api.mulMat(
          g,
          api.cont(g, api.transpose(g, v)),
          scores,
        );
        final merged = api.cont2d(
          g,
          api.permute(g, attended, 0, 2, 1, 3),
          d,
          queryRows,
        );
        x = api.add(g, x, linear(merged, layer.outWeight, layer.outBias));
        final ff = norm(x, layer.norm2Weight, layer.norm2Bias);
        x = api.add(
          g,
          x,
          linear(
            api.relu(g, linear(ff, layer.linear1Weight, layer.linear1Bias)),
            layer.linear2Weight,
            layer.linear2Bias,
          ),
        );
      }
      final rows = x;
      api.setOutput(rows);
      var scores = norm(rows, _scorerNormWeight, _scorerNormBias);
      scores = api.geluErf(
        g,
        linear(scores, _scorerHiddenWeight, _scorerHiddenBias),
      );
      scores = linear(scores, _scorerOutWeight, _scorerOutBias);
      api.setOutput(scores);

      final graph = api.newGraphCustom(g, _graphSize, false);
      api.buildForwardExpand(graph, scores);
      api.buildForwardExpand(graph, rows);
      api.schedReset(_sched);
      final barrier = _failures?.barrier;
      final allocated = barrier == null
          ? api.schedAllocGraph(_sched, graph)
          : barrier.ggmlBackendSchedAllocGraph(_sched, graph);
      if (!allocated) {
        _throwIfCaught(
          'ggml_backend_sched_alloc_graph',
          LlamaInferenceException.new,
        );
        throw LlamaInferenceException(
          'Could not allocate decision head compute buffers on $_deviceName '
          'for $n tokens.',
        );
      }

      final staging = malloc<Float>(math.max(n * d, rowCount));
      try {
        final values = staging.asTypedList(n * d)..setAll(0, hidden);
        _tensorSet(
          hiddenInput,
          staging.cast(),
          values.lengthInBytes,
          LlamaInferenceException.new,
        );
        staging
            .asTypedList(d)
            .setAll(
              0,
              Float32List.sublistView(
                _typeEmbedding,
                questionType * d,
                (questionType + 1) * d,
              ),
            );
        _tensorSet(
          typeInput,
          staging.cast(),
          d * 4,
          LlamaInferenceException.new,
        );
        staging.cast<Int32>().asTypedList(rowCount)
          ..[0] = 0
          ..setAll(1, markers);
        _tensorSet(
          rowsInput,
          staging.cast(),
          rowCount * 4,
          LlamaInferenceException.new,
        );

        final status =
            (_exitTeardown?.schedGraphCompute ?? api.schedGraphCompute)(
              _sched,
              graph,
            );
        if (status != ggml_status.GGML_STATUS_SUCCESS.value) {
          _throwIfCaught(
            'ggml_backend_sched_graph_compute',
            LlamaInferenceException.new,
          );
          throw LlamaInferenceException(
            'Decision head compute failed on $_deviceName (ggml status '
            '$status).',
          );
        }
        _tensorGet(scores, staging.cast(), rowCount * 4);
        final logits = Float32List.fromList(
          staging.asTypedList(rowCount).sublist(1),
        );
        _tensorGet(rows, staging.cast(), d * 4);
        final cls = Float32List.fromList(staging.asTypedList(d));
        return (logits, cls);
      } finally {
        malloc.free(staging);
      }
    } finally {
      api.free(g);
    }
  }

  Float32List _actLogits(Float32List cls, Float32List logits) {
    final d = _hiddenSize;
    final inputs = Float64List(d + 4)
      ..setAll(0, cls)
      ..setAll(d, decisionActFeatures(logits));
    final hiddenWeight = _act.hiddenWeight;
    final hiddenBias = _act.hiddenBias;
    final hidden = Float64List(hiddenBias.length);
    for (var j = 0; j < hidden.length; j++) {
      var sum = hiddenBias[j].toDouble();
      final row = j * inputs.length;
      for (var i = 0; i < inputs.length; i++) {
        sum += hiddenWeight[row + i] * inputs[i];
      }
      hidden[j] = 0.5 * sum * (1 + decisionErf(sum / math.sqrt2));
    }
    final outWeight = _act.outWeight;
    final outBias = _act.outBias;
    final result = Float32List(outBias.length);
    for (var c = 0; c < result.length; c++) {
      var sum = outBias[c].toDouble();
      final row = c * hidden.length;
      for (var j = 0; j < hidden.length; j++) {
        sum += outWeight[row + j] * hidden[j];
      }
      result[c] = sum;
    }
    return result;
  }

  /// Synchronizes and frees the scheduler, then frees the weights and the
  /// backends.
  ///
  /// Later [run] calls throw; disposing again does nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final api = _api;
    if (_sched != nullptr) {
      final barrier = _failures?.barrier;
      if (barrier == null) {
        api.schedSynchronize(_sched);
      } else {
        barrier.ggmlBackendSchedSynchronize(_sched);
      }
      _disown(_sched, api.schedFree);
      _sched = nullptr;
    }
    if (_weightsBuffer != nullptr) {
      _disown(_weightsBuffer, api.bufferFree);
      _weightsBuffer = nullptr;
    }
    if (_weightsContext != nullptr) {
      api.free(_weightsContext);
      _weightsContext = nullptr;
    }
    if (_deviceBackend != nullptr) {
      _disown(_deviceBackend, api.backendFree);
      _deviceBackend = nullptr;
    }
    if (_cpuBackend != nullptr) {
      _disown(_cpuBackend, api.backendFree);
      _cpuBackend = nullptr;
    }
  }

  /// Frees [object] with [free] at isolate shutdown and, with exit teardown,
  /// at process exit, unless [_disown] frees it first.
  void _own<T extends NativeType>(
    ShutdownStage stage,
    Pointer<NativeFinalizerFunction> free,
    Pointer<T> object,
  ) {
    final exitTeardown = _exitTeardown;
    final tracked =
        exitTeardown != null &&
        object != nullptr &&
        exitTeardown.track(object.cast(), free.cast(), exitStageValue(stage));
    if (tracked) _exitTracked.add(object.address);
    IsolateShutdownReleases.current.hold(
      stage,
      tracked ? exitTeardown.freeAddress : free,
      object,
    );
  }

  void _disown<T extends NativeType>(
    Pointer<T> object,
    void Function(Pointer<T> object) free,
  ) {
    IsolateShutdownReleases.current.release(object);
    if (_exitTracked.remove(object.address)) {
      _exitTeardown!.free(object.cast());
    } else {
      free(object);
    }
  }
}

/// The error function by Abramowitz and Stegun 7.1.26, within 1.4e-7 of the
/// exact value; NaN stays NaN.
double decisionErf(double x) {
  final t = 1 / (1 + 0.3275911 * x.abs());
  final polynomial =
      0.254829592 +
      t *
          (-0.284496736 +
              t * (1.421413741 + t * (-1.453152027 + t * 1.061405429)));
  final y = 1 - t * polynomial * math.exp(-x * x);
  return x < 0 ? -y : y;
}
